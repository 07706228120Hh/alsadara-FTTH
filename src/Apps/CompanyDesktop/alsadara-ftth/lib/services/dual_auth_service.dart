/// خدمة المصادقة المزدوجة - تسجيل دخول FTTH الصامت
/// تقوم بجلب بيانات اعتماد FTTH من الخادم وتسجيل الدخول بصمت
/// عند نجاح تسجيل الدخول للنظام الأول (VPS/Sadara)
library;

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'auth/session_manager.dart';
import 'vps_auth_service.dart';
import 'accounting_service.dart';
import 'linked_accounts_service.dart';

/// حالة تسجيل الدخول الصامت لـ FTTH
class FtthSilentLoginResult {
  final bool success;
  final String? ftthUsername;
  final String? ftthToken;
  final String? message;
  final bool noCredentials; // لا توجد بيانات FTTH مربوطة
  final bool cancelled; // ألغى المستخدم اختيار الحساب (لا فشل فعلي)

  const FtthSilentLoginResult({
    required this.success,
    this.ftthUsername,
    this.ftthToken,
    this.message,
    this.noCredentials = false,
    this.cancelled = false,
  });

  const FtthSilentLoginResult.noCredentials()
      : success = false,
        ftthUsername = null,
        ftthToken = null,
        message = 'لا توجد بيانات اعتماد FTTH مربوطة بهذا الحساب',
        noCredentials = true,
        cancelled = false;

  const FtthSilentLoginResult.failed(String error)
      : success = false,
        ftthUsername = null,
        ftthToken = null,
        message = error,
        noCredentials = false,
        cancelled = false;

  const FtthSilentLoginResult.cancelledByUser()
      : success = false,
        ftthUsername = null,
        ftthToken = null,
        message = 'تم إلغاء اختيار حساب FTTH',
        noCredentials = false,
        cancelled = true;
}

/// خدمة المصادقة المزدوجة (Singleton)
class DualAuthService {
  static DualAuthService? _instance;
  static DualAuthService get instance =>
      _instance ??= DualAuthService._internal();
  DualAuthService._internal();

  /// هل تم تسجيل الدخول لنظام FTTH بنجاح؟
  bool _isFtthLoggedIn = false;
  bool get isFtthLoggedIn => _isFtthLoggedIn;

  /// اسم مستخدم FTTH الحالي
  String? _ftthUsername;
  String? get ftthUsername => _ftthUsername;

  /// توكن FTTH الحالي (يُحدّث تلقائياً عبر AuthService)
  String? _ftthToken;
  String? get ftthToken => _ftthToken;

  // ============ صلاحيات FTTH المركزية ============
  /// هل المستخدم مدير في نظام FTTH؟
  bool _ftthIsAdmin = false;
  bool get ftthIsAdmin => _ftthIsAdmin;

  /// صلاحيات FTTH المهمة (مفلترة ومترجمة)
  List<String> _ftthImportantPermissions = [];
  List<String> get ftthImportantPermissions => _ftthImportantPermissions;

  /// تحديث صلاحيات FTTH (يُستدعى من ftth/core/home_page بعد جلب بيانات المستخدم)
  void updateFtthPermissions({required bool isAdmin, required List<String> importantPermissions}) {
    _ftthIsAdmin = isAdmin;
    _ftthImportantPermissions = importantPermissions;
    print('🔐 [DualAuth] تحديث صلاحيات FTTH: isAdmin=$isAdmin, permissions=${importantPermissions.length}');
  }

  /// SharedPreferences keys لحفظ حالة الربط
  static const String _ftthLinkedKey = 'dual_auth_ftth_linked';
  static const String _ftthUsernameKey = 'dual_auth_ftth_username';

  /// Stream لإعلام المستمعين بتغيّر حالة تسجيل دخول FTTH
  StreamController<bool>? _ftthStateController;

  Stream<bool> get ftthStateStream {
    _ftthStateController ??= StreamController<bool>.broadcast();
    return _ftthStateController!.stream;
  }

  void _notifyFtthStateChange(bool isLoggedIn) {
    if (_ftthStateController != null && !_ftthStateController!.isClosed) {
      _ftthStateController!.add(isLoggedIn);
    }
  }

  /// مسح بيانات FTTH من الذاكرة و SharedPreferences (بدون تأثير على AuthService)
  /// يُستخدم قبل كل تسجيل دخول جديد لمنع تسرب بيانات المستخدم السابق
  Future<void> clearFtthData() async {
    reset(); // مسح الحالة في الذاكرة فوراً
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_ftthLinkedKey);
      await prefs.remove(_ftthUsernameKey);
      await prefs.remove('savedUsername');
      await prefs.remove('savedPassword');
      await prefs.remove('rememberMe');
    } catch (e) {
      print('⚠️ [DualAuth] خطأ في مسح بيانات FTTH');
    }
  }

  /// تسجيل دخول FTTH الصامت بعد نجاح تسجيل دخول VPS
  /// يجلب بيانات الاعتماد من الخادم ويسجل الدخول تلقائياً
  Future<FtthSilentLoginResult> silentFtthLogin() async {
    try {
      // 1) التحقق من وجود مستخدم VPS مسجل دخول
      final vpsUser = VpsAuthService.instance.currentUser;
      if (vpsUser == null) {
        return const FtthSilentLoginResult.failed(
            'لم يتم تسجيل الدخول للنظام الأول');
      }

      final userId = vpsUser.id;
      print('🔄 [DualAuth] بدء تسجيل دخول FTTH الصامت للمستخدم: $userId');

      // 2) جلب بيانات اعتماد FTTH من الخادم
      final credResult =
          await AccountingService.instance.getFtthCredentials(userId);

      if (!credResult['success']) {
        print('⚠️ [DualAuth] فشل جلب بيانات FTTH: ${credResult['message']}');
        return FtthSilentLoginResult.failed(
            credResult['message'] ?? 'فشل جلب بيانات FTTH');
      }

      final data = credResult['data'];
      if (data == null || data['hasFtthAccount'] != true) {
        print('ℹ️ [DualAuth] لا توجد بيانات FTTH مربوطة');
        return const FtthSilentLoginResult.noCredentials();
      }

      final ftthUser = data['ftthUsername'] as String?;
      final ftthPass = data['ftthPasswordEncrypted'] as String?;

      if (ftthUser == null ||
          ftthUser.isEmpty ||
          ftthPass == null ||
          ftthPass.isEmpty) {
        print('⚠️ [DualAuth] بيانات FTTH غير مكتملة');
        return const FtthSilentLoginResult.noCredentials();
      }

      // 3) تسجيل الدخول لنظام FTTH
      print('🔐 [DualAuth] تسجيل الدخول لـ FTTH باسم: $ftthUser');
      final loginResult = await AuthService.instance.login(ftthUser, ftthPass);

      if (!loginResult['success']) {
        print('❌ [DualAuth] فشل تسجيل دخول FTTH: ${loginResult['message']}');
        return FtthSilentLoginResult.failed(
            'فشل تسجيل دخول FTTH: ${loginResult['message']}');
      }

      // 4) تحديث SessionManager
      try {
        await SessionManager.instance.onLoginCompleted();
      } catch (e) {
        print('⚠️ [DualAuth] تعذر تحديث الجلسة');
      }

      // 5) حفظ الحالة
      final tokenData = loginResult['data'];
      _isFtthLoggedIn = true;
      _ftthUsername = ftthUser;
      _ftthToken = tokenData['access_token'];

      // حفظ في SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ftthLinkedKey, true);
      await prefs.setString(_ftthUsernameKey, ftthUser);

      // حفظ بيانات الدخول للتجديد التلقائي
      await prefs.setString('savedUsername', ftthUser);
      await prefs.setString('savedPassword', ftthPass);
      await prefs.setBool('rememberMe', true);

      print('✅ [DualAuth] تم تسجيل دخول FTTH بنجاح! المستخدم: $ftthUser');
      // إعلام home_page وأي مستمع آخر بنجاح تسجيل الدخول
      _notifyFtthStateChange(true);

      return FtthSilentLoginResult(
        success: true,
        ftthUsername: ftthUser,
        ftthToken: tokenData['access_token'],
        message: 'تم تسجيل دخول FTTH بنجاح',
      );
    } catch (e) {
      print('❌ [DualAuth] خطأ غير متوقع');
      return FtthSilentLoginResult.failed('خطأ غير متوقع');
    }
  }

  // ======================================================================
  // المسار الجديد: الحسابات المرتبطة المتعددة (دخول FTTH خادمي)
  //
  // تدرّج آمن 100% إضافي: المستخدمون الحاليون (بلا صلاحية linked_accounts،
  // أو بلا حسابات مرتبطة جديدة، أو عند أي خطأ شبكة) يرجعون تلقائياً للمسار
  // القديم [silentFtthLogin] دون أي تغيير سلوكي. في المسار الجديد لا تُخزَّن
  // ولا تُمرَّر كلمة مرور FTTH على العميل إطلاقاً — فقط التوكن المُعاد من الخادم.
  // ======================================================================

  /// منسّق دخول FTTH الذكي.
  /// [onMultiple]: دالّة واجهة تعرض اختيار الحساب عند وجود أكثر من حساب FTTH
  /// نشط؛ تُعيد الحساب المختار أو null عند الإلغاء. عند غيابها (مسار خلفي بلا
  /// واجهة) يُختار الحساب الأساسي تلقائياً.
  Future<FtthSilentLoginResult> smartFtthLogin({
    Future<LinkedAccount?> Function(List<LinkedAccount> accounts)? onMultiple,
  }) async {
    try {
      final vpsUser = VpsAuthService.instance.currentUser;
      if (vpsUser == null) {
        // ليس موظف شركة (مثلاً Super Admin) — المسار القديم يتولّى الأمر
        return await silentFtthLogin();
      }

      final userId = vpsUser.id;

      // 1) جلب الحسابات المرتبطة للمستخدم الحالي
      Map<String, dynamic> accountsResult;
      try {
        accountsResult =
            await LinkedAccountsService.instance.getAccounts(userId);
      } catch (e) {
        // خطأ شبكة/استثناء ⇒ ارجع للمسار القديم كما هو
        print('⚠️ [DualAuth] تعذّر جلب الحسابات المرتبطة — المسار القديم');
        return await silentFtthLogin();
      }

      if (accountsResult['success'] != true) {
        // 403 (لا صلاحية linked_accounts) أو أي خطأ ⇒ المسار القديم
        print(
            'ℹ️ [DualAuth] الحسابات المرتبطة غير متاحة (${accountsResult['statusCode']}) — المسار القديم');
        return await silentFtthLogin();
      }

      final all = (accountsResult['data'] as List?)
              ?.whereType<LinkedAccount>()
              .toList() ??
          const <LinkedAccount>[];
      final ftthAccounts =
          all.where((a) => a.isFtth && a.isActive).toList();

      if (ftthAccounts.isEmpty) {
        // لا حسابات FTTH مرتبطة جديدة ⇒ المسار القديم (المستخدمون الحاليون)
        print('ℹ️ [DualAuth] لا حسابات FTTH مرتبطة — المسار القديم');
        return await silentFtthLogin();
      }

      // 2) تحديد الحساب المطلوب
      LinkedAccount chosen;
      if (ftthAccounts.length == 1) {
        chosen = ftthAccounts.first;
      } else {
        if (onMultiple != null) {
          final selected = await onMultiple(ftthAccounts);
          if (selected == null) {
            // ألغى المستخدم الاختيار صراحةً — لا دخول ولا رجوع للقديم
            return const FtthSilentLoginResult.cancelledByUser();
          }
          chosen = selected;
        } else {
          // مسار خلفي بلا واجهة ⇒ الحساب الأساسي ثم الأول
          chosen = _pickPrimary(ftthAccounts);
        }
      }

      // 3) تسجيل الدخول خادمياً بالحساب المختار (بلا كلمة مرور على العميل)
      return await loginWithLinkedFtthAccount(chosen);
    } catch (e) {
      // أي خطأ غير متوقّع ⇒ المسار القديم الآمن
      print('⚠️ [DualAuth] خطأ غير متوقّع في المسار الذكي — المسار القديم');
      return await silentFtthLogin();
    }
  }

  LinkedAccount _pickPrimary(List<LinkedAccount> accounts) {
    for (final a in accounts) {
      if (a.isPrimary) return a;
    }
    return accounts.first;
  }

  /// تسجيل دخول FTTH خادمياً عبر حساب مرتبط محدّد (المسار الجديد).
  /// يستخدم التوكن المُعاد من الخادم فقط ويحفظه عبر نفس آلية جلسة FTTH في
  /// [AuthService]/[SessionManager]. لا يُخزَّن أي كلمة مرور على العميل.
  /// عند فشل الدخول الخادمي يرجع للمسار القديم كاحتياطي أخير.
  Future<FtthSilentLoginResult> loginWithLinkedFtthAccount(
      LinkedAccount account) async {
    try {
      print('🔐 [DualAuth] دخول FTTH خادمي للحساب المرتبط: ${account.label}');
      final result = await LinkedAccountsService.instance.login(account.id);

      if (result['success'] != true) {
        print(
            '⚠️ [DualAuth] فشل الدخول الخادمي (${result['statusCode']}) — المسار القديم');
        return await silentFtthLogin();
      }

      final tokens = _extractTokens(result['data']);
      final accessToken = tokens['accessToken'];
      final refreshToken = tokens['refreshToken'];

      if (accessToken == null || accessToken.isEmpty) {
        print('⚠️ [DualAuth] الاستجابة الخادمية بلا توكن — المسار القديم');
        return await silentFtthLogin();
      }

      // حفظ جلسة FTTH بالتوكن الخادمي (بلا كلمة مرور على العميل)
      await AuthService.instance.saveExternalTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );

      // تحديث SessionManager
      try {
        await SessionManager.instance.onLoginCompleted();
      } catch (e) {
        print('⚠️ [DualAuth] تعذّر تحديث الجلسة');
      }

      // حفظ الحالة في الذاكرة
      _isFtthLoggedIn = true;
      _ftthUsername = account.username;
      _ftthToken = accessToken;

      // حفظ علامات الربط في SharedPreferences — دون أي كلمة مرور
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ftthLinkedKey, true);
      await prefs.setString(_ftthUsernameKey, account.username);
      await prefs.setString('savedUsername', account.username);
      // المسار الجديد لا يعتمد على كلمة مرور للعميل — نمنع relogin بكلمة مرور
      await prefs.remove('savedPassword');
      await prefs.setBool('rememberMe', false);

      print('✅ [DualAuth] تم دخول FTTH خادمياً: ${account.username}');
      // إعلام مؤشّر حالة الاتصال وبقية المستمعين (مطابق للمسار القديم)
      _notifyFtthStateChange(true);

      return FtthSilentLoginResult(
        success: true,
        ftthUsername: account.username,
        ftthToken: accessToken,
        message: 'تم تسجيل دخول FTTH بنجاح',
      );
    } catch (e) {
      print('⚠️ [DualAuth] خطأ في الدخول الخادمي — المسار القديم');
      return await silentFtthLogin();
    }
  }

  /// استخراج التوكنات من استجابة الخادم بمرونة (camelCase/PascalCase/snake).
  Map<String, String?> _extractTokens(dynamic data) {
    if (data is Map) {
      final outer = Map<String, dynamic>.from(data);
      final inner = outer['data'] is Map
          ? Map<String, dynamic>.from(outer['data'] as Map)
          : outer;
      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = inner[k] ?? outer[k];
          if (v != null && v.toString().isNotEmpty) return v.toString();
        }
        return null;
      }

      // حصر المفاتيح تطابقاً مع عقد بوّابة /api/linked-accounts/ftth/{id}/login:
      // access token: accessToken/access_token فقط · refresh: refreshToken/refresh_token فقط.
      // (حُذفت المفاتيح العامة المبهمة token/Token.)
      return {
        'accessToken': pick(['accessToken', 'access_token']),
        'refreshToken': pick(['refreshToken', 'refresh_token']),
      };
    }
    return {'accessToken': null, 'refreshToken': null};
  }

  /// التحقق مما إذا كان FTTH مسجل دخول حالياً (من التوكن المحفوظ)
  Future<bool> checkFtthSession() async {
    try {
      // أولاً: تحقق من وجود رابط FTTH صريح لهذا المستخدم
      // هذا يمنع استخدام جلسة FTTH لمستخدم آخر
      final prefs = await SharedPreferences.getInstance();
      final isLinked = prefs.getBool(_ftthLinkedKey) ?? false;
      if (!isLinked) {
        _isFtthLoggedIn = false;
        _ftthToken = null;
        _ftthUsername = null;
        return false;
      }

      final token = await AuthService.instance.getAccessToken();
      if (token != null) {
        _isFtthLoggedIn = true;
        _ftthToken = token;

        // استرجاع اسم المستخدم المحفوظ
        _ftthUsername = prefs.getString(_ftthUsernameKey);
        // fallback: إذا كان فارغاً استخدم savedUsername
        if (_ftthUsername == null || _ftthUsername!.isEmpty) {
          _ftthUsername = prefs.getString('savedUsername');
          if (_ftthUsername != null && _ftthUsername!.isNotEmpty) {
            await prefs.setString(_ftthUsernameKey, _ftthUsername!);
          }
        }

        return true;
      }
    } catch (e) {
      print('⚠️ [DualAuth] خطأ في فحص جلسة FTTH');
    }
    _isFtthLoggedIn = false;
    _ftthToken = null;
    return false;
  }

  /// الحصول على التوكن الحالي (مع تجديد تلقائي)
  Future<String?> getFtthToken() async {
    if (!_isFtthLoggedIn) return null;
    // AuthService.getAccessToken يجدد تلقائياً إذا لزم
    final token = await AuthService.instance.getAccessToken();
    _ftthToken = token;
    if (token == null) _isFtthLoggedIn = false;
    return token;
  }

  /// تسجيل الخروج من FTTH
  Future<void> logoutFtth() async {
    await AuthService.instance.logout();
    _isFtthLoggedIn = false;
    _ftthUsername = null;
    _ftthToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ftthLinkedKey);
    await prefs.remove(_ftthUsernameKey);
    // حذف بيانات الدخول المحفوظة لمنع تسرب جلسة المستخدم السابق
    await prefs.remove('savedUsername');
    await prefs.remove('savedPassword');
    await prefs.remove('rememberMe');

    _notifyFtthStateChange(false);
    print('🚪 [DualAuth] تم تسجيل الخروج من FTTH');
  }

  /// تسجيل الخروج من كلا النظامين
  Future<void> logoutAll() async {
    await logoutFtth();
    await VpsAuthService.instance.logout();
    print('🚪 [DualAuth] تم تسجيل الخروج من كلا النظامين');
  }

  /// إعادة تعيين الحالة (عند تسجيل الخروج من النظام الأول)
  void reset() {
    _isFtthLoggedIn = false;
    _ftthUsername = null;
    _ftthToken = null;
    _ftthIsAdmin = false;
    _ftthImportantPermissions = [];
  }
}
