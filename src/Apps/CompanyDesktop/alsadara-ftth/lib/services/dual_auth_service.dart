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

/// حالة تسجيل الدخول الصامت لـ FTTH
class FtthSilentLoginResult {
  final bool success;
  final String? ftthUsername;
  final String? ftthToken;
  final String? message;
  final bool noCredentials; // لا توجد بيانات FTTH مربوطة

  const FtthSilentLoginResult({
    required this.success,
    this.ftthUsername,
    this.ftthToken,
    this.message,
    this.noCredentials = false,
  });

  const FtthSilentLoginResult.noCredentials()
      : success = false,
        ftthUsername = null,
        ftthToken = null,
        message = 'لا توجد بيانات اعتماد FTTH مربوطة بهذا الحساب',
        noCredentials = true;

  const FtthSilentLoginResult.failed(String error)
      : success = false,
        ftthUsername = null,
        ftthToken = null,
        message = error,
        noCredentials = false;
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
      print('⚠️ [DualAuth] خطأ في مسح بيانات FTTH: $e');
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
        print('⚠️ [DualAuth] تعذر تحديث الجلسة: $e');
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
      print('❌ [DualAuth] خطأ غير متوقع: $e');
      return FtthSilentLoginResult.failed('خطأ غير متوقع: $e');
    }
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
      print('⚠️ [DualAuth] خطأ في فحص جلسة FTTH: $e');
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
  }
}
