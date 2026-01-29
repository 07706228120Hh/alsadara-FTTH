/// اسم الصفحة: الصفحة الرئيسية FTTH
/// وصف الصفحة: الصفحة الرئيسية لنظام إدارة الألياف البصرية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

// filepath: c:\div\APP\ramz_alsadara21\filter_page\lib\ftth\home_page.dart
// تم تحديث نظام تحديد الصلاحيات الإدارية بنظام متقدم يشمل:
// 1. فحص المستوى الهرمي (0-2 للمديرين)
// 2. البحث في اسم الشريك عن الكلمات الإدارية (عربية وإنجليزية)
// 3. فحص اسم المستخدم للأنماط الإدارية
// 4. إخفاء كروت المحفظة عن غير المديرين لحماية البيانات المالية
// 5. زر تحديث فوري للبيانات مع رسائل تفاعلية
// 6. تحسينات المظهر البصري والتفاعلية المحدثة

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as wvwin;
import 'dart:io';
import '../../services/auth_service.dart';
import '../../services/permissions_service.dart';
import '../../utils/smart_text_color.dart';
import '../../pages/home_page.dart' as firstSystem; // استيراد صفحة النظام الأول
import '../auth/auth_error_handler.dart';
import '../widgets/notification_filter.dart';
import '../whatsapp/whatsapp_bottom_window.dart'; // استيراد نظام الواتساب العائم
import '../../widgets/logout_dialog.dart';
import '../../pages/whatsapp_conversations_page.dart'; // صفحة محادثات WhatsApp
import '../../pages/whatsapp_bulk_sender_page.dart'; // صفحة إرسال رسائل جماعية (تحتوي على إعدادات API والتقارير)

import '../users/users_page.dart';
import '../tickets/tktats_page.dart'; // تغيير الاستيراد إلى tktats_page
import '../reports/zones_page.dart';
import '../subscriptions/subscriptions_page.dart';
import '../tickets/technicians_page.dart'; // صفحة فني التوصيل المحلية
import '../transactions/caounter_details_page.dart';
import '../reports/export_page.dart';
import '../reports/data_page.dart'; // صفحة البيانات الموحدة (تفاصيل الوكلاء + بيانات المستخدمين)
import '../users/quick_search_users_page.dart';
import '../transactions/account_records_page.dart';
import '../../pages/local_storage_page.dart'; // صفحة التخزين الداخلي
import '../../services/background_sync_service.dart'; // خدمة المزامنة في الخلفية
import '../subscriptions/expiring_soon_page.dart';
import '../transactions/transactions_page.dart';
import '../../services/badge_service.dart';
import '../../services/auth/session_manager.dart';
import '../../services/auth/auth_context.dart';
import '../../services/ftth/ftth_cache_service.dart';
import '../../services/ftth/ftth_event_bus.dart';
import '../widgets/pikachu_overlay.dart';
import '../../pages/super_admin/super_admin_dashboard.dart'; // ✅ لوحة تحكم Super Admin

class HomePage extends StatefulWidget {
  final String username;
  final String authToken;
  final String? permissions; // إضافة صلاحيات المستخدم
  final String? department; // إضافة القسم
  final String? center; // إضافة المركز
  final String? salary; // إضافة الراتب
  final Map<String, bool>? pageAccess; // إضافة صلاحيات الصفحات
  // معلومات النظام الأول (Google Sheets)
  final String? firstSystemUsername; // اسم المستخدم في النظام الأول
  final String? firstSystemPermissions; // صلاحيات النظام الأول
  final String? firstSystemDepartment; // قسم النظام الأول
  final String? firstSystemCenter; // مركز النظام الأول
  final String? firstSystemSalary; // راتب النظام الأول
  final Map<String, bool>? firstSystemPageAccess; // صلاحيات صفحات النظام الأول
  // ✅ دعم وضع Super Admin
  final bool isSuperAdminMode; // هل دخل كـ Super Admin
  final String? tenantId; // معرف الشركة
  final String? tenantCode; // كود الشركة
  const HomePage({
    required this.username,
    required this.authToken,
    this.permissions,
    this.department,
    this.center,
    this.salary,
    this.pageAccess,
    this.firstSystemUsername,
    this.firstSystemPermissions,
    this.firstSystemDepartment,
    this.firstSystemCenter,
    this.firstSystemSalary,
    this.firstSystemPageAccess,
    this.isSuperAdminMode = false,
    this.tenantId,
    this.tenantCode,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();

  // دالة عامة للحصول على إعداد الإرسال التلقائي
  static Future<bool> getWhatsAppAutoSendSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('whatsapp_auto_send') ?? true; // مُفعل افتراضياً
    } catch (e) {
      debugPrint('❌ خطأ في تحميل إعداد الإرسال التلقائي: $e');
      return true; // افتراضي مُفعل في حالة الخطأ
    }
  }
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late String currentToken;
  Timer? _timer; // تغيير إلى nullable لتجنب الأخطاء
  // مؤقت مستقل لتحديث رصيد المحفظة والعمولة ومحفظة عضو الفريق بصورة أسرع من تحديث لوحة التحكم
  Timer? _walletTimer;
  final Duration _walletRefreshInterval =
      const Duration(minutes: 1); // يمكن تعديلها لاحقاً بسهولة
  bool _walletFetchInProgress = false; // منع تداخل طلبات الرصيد
  late AnimationController _refreshAnimationController;
  late AnimationController _cardAnimationController;
  late AnimationController _fiberLightController; // حركة أضواء الألياف
  late Animation<double> _fiberAnim;

  // ⚡ بيكاتشو الآن في Overlay عالمي (pikachu_overlay.dart)

  bool isLoadingDashboard = true;
  bool isRefreshing = false;
  Map<String, dynamic> dashboardData = {};
  int hierarchyLevel = 0;
  double walletBalance = 0.0;
  double commission = 0.0;
  // رصيد محفظة عضو الفريق (يُعرض فقط إذا كانت المحفظة موجودة hasWallet = true)
  double teamMemberWalletBalance = 0.0;
  bool hasTeamMemberWallet = false;
  String? partnerId;
  String? partnerName;
  bool isAdmin = false;
  DateTime? lastUpdateTime; // نظام إدارة الصلاحيات - الحالة الافتراضية
  // نظام إدارة الصلاحيات - إعطاء صلاحيات أساسية للجميع
  final Map<String, bool> _defaultPermissions = {
    'users': false, // السماح بعرض المستخدمين للجميع
    'subscriptions': false, // السماح بعرض الاشتراكات للجميع
    'tasks': false, // السماح بعرض المهام للجميع
    'zones': false, // منع إدارة المناطق افتراضياً (للمديرين فقط)
    'accounts': false, // منع إدارة الحسابات افتراضياً (للمديرين فقط)
    'account_records': false, // منع سجلات الحسابات افتراضياً (مستقلة)
    'export': false, // منع ترحيل البيانات افتراضياً (للمديرين فقط)
    'agents': false, // تعطيل افتراضياً وإظهاره عبر زر الصلاحيات
    'google_sheets': false, // منع إرسال المعلومات إلى Google Sheets افتراضياً
    'whatsapp': false, // منع إرسال رسائل WhatsApp افتراضياً
    'wallet_balance': false, // السماح بمشاهدة رصيد المحفظة للجميع
    'expiring_soon':
        false, // التحكم بزر "الانتهاء قريباً" في الوصول السريع والقائمة
    'quick_search': false, // التحكم بزر "البحث السريع" في الوصول السريع
    'transactions': false, // تعطيل افتراضياً وإظهاره عبر زر الصلاحيات
    'notifications': false, // تعطيل افتراضياً وإظهاره عبر زر الصلاحيات
    'audit_logs': false, // منع الوصول لسجل التدقيق افتراضياً (للمديرين فقط)
    // مفاتيح جديدة لعناصر كانت تظهر دائماً
    'whatsapp_link': false, // ربط الواتساب (QR)
    'whatsapp_settings': false, // إعدادات الواتساب
    'plans_bundles': false, // باقات وعروض
    'technicians': false, // فني التوصيل (محلي) مخفي افتراضياً
    'whatsapp_business_api': false, // إعدادات WhatsApp Business API
    'whatsapp_bulk_sender': false, // إرسال رسائل جماعية
    'whatsapp_conversations_fab': false, // الزر العائم لمحادثات الواتساب
    'local_storage': false, // التخزين المحلي للمشتركين
    'local_storage_import': false, // زر استيراد البيانات في التخزين المحلي
  };

  Map<String, bool> _userPermissions = {};
  // أعلام للتحميل المبكر وتحكم تكرار الطلبات
  bool _earlyPrefetchStarted = false;
  bool _dashboardRequested = false;
  bool _walletRequested = false;

  // متغيرات إعدادات الواتساب
  String? _defaultWhatsAppPhone;
  bool _useWhatsAppWeb = true;
  bool _whatsAppAutoSend = true; // الإرسال التلقائي للواتساب - مُفعل افتراضياً
  bool _isGeneratingWhatsAppLink = false;

  @override
  void initState() {
    super.initState();
    currentToken = widget.authToken;

    // فحص أولي لحال�� المدير باستخدام اسم المستخدم
    isAdmin = _isAdminByUsername();

    _initializeAnimations();
    _initializeApp();
    _startEarlyPrefetch();

    // تحميل إعدادات الواتساب
    _loadDefaultWhatsAppPhone();
    _loadWhatsAppSettings();

    // بيكاتشو يُدار الآن من Overlay عالمي (لا حاجة لتحميل إعداداته هنا)

    // الاشتراك في قناة التحديث الفوري
    FtthEventBus.instance.stream.listen((event) {
      if (!mounted) return;
      if (event == FtthEvents.forceRefresh) {
        // تحديث سريع: نحاول تحديث المحفظة أولاً ثم لوحة التحكم
        _performRefresh();
      }
    });

    // إعداد إشعار المزامنة في الخلفية
    _setupBackgroundSyncNotification();

    // الزر العائم للواتساب يتم إظهاره بعد تحميل الصلاحيات في _initializeApp
  }

  /// إعداد إشعار المزامنة في الخلفية
  void _setupBackgroundSyncNotification() {
    BackgroundSyncService.instance.onSyncComplete = (success, message) {
      if (!mounted) return;

      // عرض إشعار عند اكتمال المزامنة
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  success ? 'تم جلب البيانات: $message' : 'فشل الجلب: $message',
                ),
              ),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'عرض',
            textColor: Colors.white,
            onPressed: () {
              // فتح صفحة التخزين المحلي
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      LocalStoragePage(authToken: currentToken),
                ),
              );
            },
          ),
        ),
      );
    };
  }

  // إعادة إظهار زر الواتساب العائم وبيكاتشو عند العودة للصفحة
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // إعادة إظهار الأزرار العائمة عند العودة من صفحة أخرى
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showGlobalWhatsAppButton();
        // التأكد من إظهار بيكاتشو وزر التحكم
        PikachuOverlay.ensureVisible(context);
      }
    });
  }

  // فحص صلاحيات المدير من النظا�� الأول فقط
  bool _isAdminByUsername() {
    // فحص الصلاحيات الجديدة من pageAccess (نظام Firebase متعدد المستأجرين)
    if (widget.pageAccess != null && widget.pageAccess!['users'] == true) {
      debugPrint('✅ تم تحديد المدير من pageAccess - صلاحية users: true');
      return true;
    }

    // فحص permissions للبحث عن "manager" أو "مدير"
    if (widget.permissions != null && widget.permissions!.isNotEmpty) {
      final perms = widget.permissions!.toLowerCase();
      if (perms.contains('manager') ||
          perms.contains('مدير') ||
          perms.contains('admin') ||
          perms.contains('administrator')) {
        debugPrint('✅ تم تحديد المدير من permissions: ${widget.permissions}');
        return true;
      }
    }

    // الأولوية الثالثة: فحص الصلاحيات من النظام الأول (Google Sheets)
    if (widget.firstSystemPermissions != null &&
        widget.firstSystemPermissions!.isNotEmpty) {
      final permissionsToCheck = widget.firstSystemPermissions!.toLowerCase();
      if (permissionsToCheck.contains('مدير') ||
          permissionsToCheck.contains('admin') ||
          permissionsToCheck.contains('administrator')) {
        debugPrint(
            'تم تحديد المدير من خلال صلاحيات النظام الأول: ${widget.firstSystemPermissions}');
        return true;
      }
    }
    debugPrint('لم يتم تحديد المدير - مستخدم عادي (لا توجد صلاحيات مدير)');
    return false;
  }

  void _initializeAnimations() {
    _refreshAnimationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // حركة أضواء الخلفية بشكل هادئ
    _fiberLightController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat();
    _fiberAnim =
        CurvedAnimation(parent: _fiberLightController, curve: Curves.linear);

    // بيكاتشو الآن في Overlay عالمي
  }

  Future<void> _initializeApp() async {
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      // إزالة إعادة تعيين الصلاحيات - للاحتفاظ بالإعدادات المحفوظة
      // تم حذف: await PermissionsService.resetSecondSystemPermissions();
      // محاولة تحميل بيانات dashboard و wallet من الكاش لتسريع الظهور الأول
      final cachedDash = await FtthCacheService.loadDashboard();
      final cachedWallet = await FtthCacheService.loadWallet();
      if (mounted && cachedDash != null) {
        setState(() {
          dashboardData = cachedDash;
          isLoadingDashboard = false; // نظهر البيانات فوراً ثم نحدث لاحقاً
        });
      }
      if (mounted && cachedWallet != null) {
        setState(() {
          walletBalance = cachedWallet['balance'] ?? walletBalance;
          commission = cachedWallet['commission'] ?? commission;
          if (cachedWallet['teamMemberWallet'] is Map) {
            final tmw = cachedWallet['teamMemberWallet'];
            hasTeamMemberWallet = tmw['hasWallet'] == true;
            teamMemberWalletBalance = (tmw['balance'] ?? 0.0) * 1.0;
          }
        });
      }

      await fetchCurrentUser(); // لم نعد ننتظر داخله dashboard + wallet (تم نقل جزء مبكر)
      // تحميل الصلاحيات بعد تحديد حالة المدير
      await _loadUserPermissions();

      // إظهار الزر العائم للواتساب بعد تحميل الصلاحيات
      if (mounted) {
        _showGlobalWhatsAppButton();
      }

      _cardAnimationController.forward();
    });
  }

  void _startEarlyPrefetch() {
    if (_earlyPrefetchStarted) return;
    _earlyPrefetchStarted = true;
    final AuthContext? ctx = SessionManager.instance.context;
    // استخدام AccountId من التوكن مؤقتاً لحين اكتمال current-user
    if (partnerId == null && ctx?.accountId != null) {
      partnerId = ctx!.accountId;
    }
    if (!_dashboardRequested) {
      _dashboardRequested = true;
      fetchDashboardData();
    }
    if (partnerId != null && !_walletRequested) {
      _walletRequested = true;
      fetchWalletBalance();
    }
  }

  // تنسيق مختصر للأرقام الكبيرة (1.2K / 3.4M) + عداد حركة لطيف
  Widget _animatedCount(num value, TextStyle style) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (_, v, __) =>
          Text(NumberFormat('#,##0').format(v), style: style),
    );
  }

  @override
  void dispose() {
    // التحقق من وجود Timer قبل إلغائه
    if (_timer != null && _timer!.isActive) {
      _timer!.cancel();
    }
    if (_walletTimer != null && _walletTimer!.isActive) {
      _walletTimer!.cancel();
    }
    _refreshAnimationController.dispose();
    _cardAnimationController.dispose();
    _fiberLightController.dispose();

    // إخفاء زر محادثات API فقط عند الخروج من FTTH (زر واتساب ويب يبقى ظاهراً)
    try {
      WhatsAppBottomWindow.hideConversationsFloatingButton();
    } catch (e) {
      debugPrint('⚠️ خطأ في إخفاء زر محادثات الواتساب: $e');
    }
    super.dispose();
  }

  /// معالجة خطأ 401 - توجيه إلى صفحة تسجيل الدخول
  void _handle401Error() {
    AuthErrorHandler.handle401Error(
      context,
      firstSystemUsername: widget.firstSystemUsername,
      firstSystemPermissions: widget.firstSystemPermissions,
      firstSystemDepartment: widget.firstSystemDepartment,
      firstSystemCenter: widget.firstSystemCenter,
      firstSystemSalary: widget.firstSystemSalary,
      firstSystemPageAccess: widget.firstSystemPageAccess,
    );
  }

  // بيانات تفصيلية من API
  Map<String, dynamic> userApiData = {};
  List<Map<String, dynamic>> userPermissions = [];
  List<Map<String, dynamic>> userZones = [];
  List<Map<String, dynamic>> userRoles = [];
  Future<void> fetchCurrentUser() async {
    // إضافة إعادة محاولة لتقليل الأخطاء المؤقتة (شبكة / استجابة بطيئة)
    const int maxRetries = 3; // الحد الأقصى للمحاولات
    int attempt = 0;
    Duration delay = const Duration(milliseconds: 400);
    Object? lastError;
    httpResponseLoop:
    while (attempt < maxRetries && mounted) {
      attempt++;
      try {
        final response = await AuthService.instance.authenticatedRequest(
          'GET',
          'https://api.ftth.iq/api/current-user',
        );

        // استجابة ناجحة
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['model'] != null && data['model']['self'] != null) {
            if (!mounted) return;
            setState(() {
              partnerId = data['model']['self']['id'];
              partnerName = data['model']['self']['displayValue'];
              userApiData = data['model'];
              userPermissions = List<Map<String, dynamic>>.from(
                  data['model']['permissions'] ?? []);
              userZones =
                  List<Map<String, dynamic>>.from(data['model']['zones'] ?? []);
              userRoles =
                  List<Map<String, dynamic>>.from(data['model']['roles'] ?? []);
              isAdmin = _checkAdminPermissions();
            });

            partnerId = data['model']['self']['id']?.toString();
            if (!_dashboardRequested) {
              _dashboardRequested = true;
              fetchDashboardData();
            }
            if (!_walletRequested && partnerId != null) {
              _walletRequested = true;
              fetchWalletBalance();
            }
            startAutoRefresh();
            startWalletAutoRefresh();
            break httpResponseLoop; // نجاح كامل، الخروج
          } else {
            lastError = 'missing_model';
            // لا نظهر رسالة مباشرة، نحاول مرة أخرى إن توفرت محاولات
          }
        } else if (response.statusCode == 401) {
          _handle401Error();
          return;
        } else if (response.statusCode == 429 ||
            (response.statusCode >= 500 && response.statusCode < 600)) {
          // أخطاء عابرة / ضغط / سيرفر: نعيد المحاولة بصمت
          lastError = 'status_${response.statusCode}';
        } else {
          // أخطاء أخرى (400,403,404,..) لا فائدة من الإعادة غالباً
          showError("تعذر جلب بيانات الشريك (رمز ${response.statusCode})");
          return;
        }
      } catch (e) {
        if (e.toString().contains('انتهت جلسة المستخدم')) {
          _handle401Error();
          return;
        }
        lastError = e;
      }

      // إذا لم ننجح ونملك محاولات متبقية ننتظر (تزايدي)
      if (attempt < maxRetries) {
        await Future.delayed(delay);
        delay *= 2; // تزايد بسيط
        continue; // محاولة جديدة
      }
    }

    // بعد استنفاد المحاولات بدون نجاح
    if (partnerId == null || partnerName == null) {
      if (lastError == 'missing_model') {
        showError('بيانات الشريك غير مكتملة من الخادم، حاول لاحقاً');
      } else if (lastError != null) {
        showError('تعذر جلب بيانات الشريك، تحقق من الاتصال وحاول مجدداً');
      }
    }
  }

  Future<void> refreshToken() async {
    try {
      // لا حاجة لهذه الدالة لأن AuthService يدير التحديث التلقائي
      // تم تعطيل إشعار نجاح تحديث التوكن حسب الطلب (صامت)
    } catch (e) {
      // التحقق من أن الخطأ ليس متعلقاً بانتهاء الجلسة
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
        return;
      }
      showError("حدث خطأ أ��ناء تجديد التوكن: $e");
    }
  } // نظام محدود لتحديد الصلاحيات الإدارية - النظام الأول فقط

  bool _checkAdminPermissions() {
    // فحص الصلاحيات الجديدة من pageAccess (نظام Firebase متعدد المستأجرين)
    if (widget.pageAccess != null && widget.pageAccess!['users'] == true) {
      print('✅ مدير معتمد من pageAccess - صلاحية users: true');
      return true;
    }

    // فحص permissions للبحث عن "manager" أو "مدير"
    if (widget.permissions != null && widget.permissions!.isNotEmpty) {
      final perms = widget.permissions!.toLowerCase();
      if (perms.contains('manager') ||
          perms.contains('مدير') ||
          perms.contains('admin') ||
          perms.contains('administrator')) {
        print('✅ مدير معتمد من permissions: ${widget.permissions}');
        return true;
      }
    }

    // المعيار الثالث: صلاحيات النظام الأول (Google Sheets)
    if (widget.firstSystemPermissions != null &&
        widget.firstSystemPermissions!.isNotEmpty) {
      final permissionsToCheck = widget.firstSystemPermissions!.toLowerCase();
      if (permissionsToCheck.contains('مدير') ||
          permissionsToCheck.contains('admin') ||
          permissionsToCheck.contains('administrator')) {
        print('مدير معتمد من النظام الأول: ${widget.firstSystemPermissions}');
        return true;
      }
    }

    print('مستخدم عادي - لم توجد صلاحيات مدير');
    return false;
  }

  // فحص خاص لصلاحيات مدير النظام الأول فقط
  bool _isFirstSystemAdmin() {
    if (widget.firstSystemPermissions != null &&
        widget.firstSystemPermissions!.isNotEmpty) {
      final permissionsToCheck = widget.firstSystemPermissions!.toLowerCase();
      return permissionsToCheck.contains('مدير') ||
          permissionsToCheck.contains('admin') ||
          permissionsToCheck.contains('administrator');
    }
    return false;
  }

  Future<void> fetchDashboardData() async {
    if (mounted) {
      setState(() {
        isLoadingDashboard =
            dashboardData.isEmpty; // حمّل مؤشر فقط إذا لا بيانات معروضة
      });
    }

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://api.ftth.iq/api/partners/dashboard/summary?hierarchyLevel=$hierarchyLevel',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final model = data["model"];
        if (mounted) {
          setState(() {
            dashboardData = model;
            isLoadingDashboard = false;
          });
        }
        try {
          final c = model['customers'] ?? {};
          debugPrint(
              '[CustomersRefresh] total=${c['totalCount']?.toString() ?? 'null'} active=${c['totalActive']?.toString() ?? 'null'} inactive=${c['totalInactive']?.toString() ?? 'null'}');
        } catch (_) {}
        // حفظ كاش
        try {
          await FtthCacheService.saveDashboard(model);
        } catch (_) {}
      } else if (response.statusCode == 401) {
        // معالجة خ��أ انتهاء صلاحية التوكن
        _handle401Error();
        return;
      } else {
        showError("تعذر جلب البيانات: ${response.statusCode}");
        if (mounted) {
          setState(() {
            isLoadingDashboard = false;
          });
        }
      }
    } catch (e) {
      // التحقق من أن الخطأ ليس متعلقاً بانتهاء الجلسة أو التوكن
      if (e.toString().contains('انتهت جلسة المستخدم') ||
          e.toString().contains('لا يوجد توكن صالح') ||
          e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        _handle401Error();
        return;
      }
      showError("حدث خطأ أثناء جلب البيانات: $e");
      if (mounted) {
        setState(() {
          isLoadingDashboard = false;
        });
      }
    }
  }

  Future<void> fetchWalletBalance() async {
    if (partnerId == null) {
      showError("لا يوجد بيانات للشريك");
      return;
    }
    // منع تداخل الطلبات المتزامنة خصوصاً مع المؤقت التلقائي
    if (_walletFetchInProgress) return;
    _walletFetchInProgress = true;
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://api.ftth.iq/api/partners/$partnerId/wallets/balance',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final model = data['model'] ?? {};
        if (mounted) {
          setState(() {
            walletBalance = model['balance'] ?? 0.0;
            commission = model['commission'] ?? 0.0;
            final tmw = model['teamMemberWallet'];
            if (tmw != null) {
              teamMemberWalletBalance = (tmw['balance'] ?? 0.0) * 1.0;
              hasTeamMemberWallet = tmw['hasWallet'] == true;
            } else {
              teamMemberWalletBalance = 0.0;
              hasTeamMemberWallet = false;
            }
          });
        }
        try {
          await FtthCacheService.saveWallet(model);
        } catch (_) {}
      } else if (response.statusCode == 401) {
        // معالجة خطأ انتهاء صلاحية التوكن
        _handle401Error();
        return;
      } else {
        // تم تجاهل رسالة فشل جلب الرصيد حسب طلب المستخدم (عدم إظهار إشعار)
      }
    } catch (e) {
      // التحقق من أن الخطأ ليس متعلقاً بانتهاء الجلسة
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
        return;
      }
      // تجاهل الإشعار بفشل جلب الرصيد
    } finally {
      _walletFetchInProgress = false;
    }
  }

  // مبدئ التحديث العام: دقيقة واحدة لتحديث الواجهة كاملة (لوحة + محفظة)
  void startAutoRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      // نتجنب التداخل إن كان تحديث سابق ما زال جارياً
      if (!isRefreshing) {
        await _performRefresh();
      }
    });
  }

  // تشغيل تحديث آلي سريع للمحفظة فقط (الرصيد / العمولة / محفظة عضو الفريق)
  void startWalletAutoRefresh() {
    if (_walletTimer?.isActive ?? false) return; // Already running
    _walletTimer = Timer.periodic(_walletRefreshInterval, (timer) {
      if (partnerId != null) {
        fetchWalletBalance();
      }
    });
  }

  Future<void> _performRefresh() async {
    if (isRefreshing) return;

    setState(() {
      isRefreshing = true;
      lastUpdateTime = DateTime.now();
    });

    _refreshAnimationController.repeat();

    try {
      await refreshToken();
      await Future.wait([
        fetchDashboardData(),
        fetchWalletBalance(),
      ]);
      // تم تعطيل إشعار نجاح التحديث (تحديث بيانات) ليكون صامتاً
    } catch (e) {
      // التحقق من أن الخطأ ليس متعلقاً بانتهاء الجلسة
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
        return;
      }
      _showErrorMessage('فشل في تحديث البيانات: $e');
    } finally {
      _refreshAnimationController.stop();
      setState(() {
        isRefreshing = false;
      });
    }
  }

  // تحديث كامل يدوي يشمل (current-user, dashboard, wallet, permissions)
  Future<void> _manualFullRefresh() async {
    if (isRefreshing) return;
    setState(() {
      isRefreshing = true;
      lastUpdateTime = DateTime.now();
    });
    _refreshAnimationController.repeat();
    try {
      await refreshToken();
      await fetchCurrentUser();
      await Future.wait([
        fetchDashboardData(),
        fetchWalletBalance(),
        _loadUserPermissions(),
      ]);
      // تم تعطيل إشعار نجاح التحديث الكامل ليكون صامتاً
    } catch (e) {
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
        return;
      }
      _showErrorMessage('فشل في التحديث الكامل: $e');
    } finally {
      _refreshAnimationController.stop();
      if (mounted) {
        setState(() {
          isRefreshing = false;
        });
      }
    }
  }

  // تم تعطيل رسائل النجاح؛ يمكن إعادة التفعيل بإرجاع دالة الإشعار.

  void _showErrorMessage(String message) {
    if (!mounted) return;
    // Route error SnackBars through the FTTH filter
    ftthShowSnackBar(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // دوال إدارة الصلاحيات مع الحفظ الدائم للجميع (بما في ذلك المديرين)
  Future<void> _loadUserPermissions() async {
    // استخدام الصلاحيات المُمررة من صفحة تسجيل الدخول (مفلترة حسب صلاحيات الشركة)
    print('تحميل الصلاحيات - مدير النظام الأول: ${_isFirstSystemAdmin()}');
    print('صلاحيات النظام الأول: ${widget.firstSystemPermissions}');
    print('اسم المستخدم: ${widget.username}');
    print('pageAccess من تسجيل الدخول: ${widget.pageAccess}');

    // تحويل الصلاحيات المُمررة إلى صلاحيات الصفحة المحلية
    final permissions = <String, bool>{};
    for (var key in _defaultPermissions.keys) {
      // الصلاحية من pageAccess (تحتوي على فلترة الشركة) أو القيمة الافتراضية
      permissions[key] = widget.pageAccess?[key] ?? _defaultPermissions[key]!;
      print(
          'صلاحية $key: ${permissions[key]} (${_isFirstSystemAdmin() ? "مدير" : "مستخدم عادي"})');
    }

    setState(() => _userPermissions = permissions);
    print('تم تحميل الصلاحيات النهائية: $_userPermissions');
  }

  // نافذة إدخال كلمة المرور للدخول لصفحة التحويلات
  Future<bool> _showPasswordDialogForTransactions() async {
    final passwordController = TextEditingController();
    bool passwordObscured = true;
    bool isVerifying = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> verifyPassword(String password) async {
              setState(() {
                isVerifying = true;
              });

              try {
                // تحميل كلمة المرور المحفوظة من PermissionsService
                final savedPassword =
                    await PermissionsService.getSecondSystemDefaultPassword();

                // التحقق من كلمة المرور
                if (savedPassword != null &&
                    savedPassword.isNotEmpty &&
                    password == savedPassword) {
                  // كلمة المرور صحيحة
                  if (context.mounted) {
                    Navigator.of(context).pop(true);
                  }
                } else if (savedPassword == null || savedPassword.isEmpty) {
                  // لا توجد كلمة مرور محفوظة - رسالة تنبيه
                  if (context.mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'لم يتم تعيين كلمة مرور افتراضية بعد. يرجى تعيينها من صفحة الصلاحيات.'),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 3),
                      ),
                    );
                    Navigator.of(context)
                        .pop(true); // السماح بالدخول إذا لم تكن هناك كلمة مرور
                  }
                } else {
                  // كلمة المرور خاطئة
                  if (context.mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text('كلمة المرور غير صحيحة'),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              } catch (e) {
                // خطأ في التحقق
                if (context.mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('خطأ في التحقق من كلمة المرور: $e'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } finally {
                if (context.mounted) {
                  setState(() {
                    isVerifying = false;
                  });
                }
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFF1A237E),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'إدخال كلمة المرور',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'يرجى إدخال كلمة المرور للوصول إلى صفحة التحويلات',
                    style: TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: passwordController,
                    obscureText: passwordObscured,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      hintText: 'أدخل كلمة المرور',
                      prefixIcon: const Icon(Icons.password_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF1A237E),
                          width: 2,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          passwordObscured
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () {
                          setState(() {
                            passwordObscured = !passwordObscured;
                          });
                        },
                      ),
                    ),
                    onSubmitted: (_) {
                      if (!isVerifying && passwordController.text.isNotEmpty) {
                        verifyPassword(passwordController.text);
                      }
                    },
                  ),
                  if (isVerifying) ...[
                    const SizedBox(height: 16),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('جاري التحقق...'),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: isVerifying || passwordController.text.isEmpty
                      ? null
                      : () => verifyPassword(passwordController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: isVerifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(isVerifying ? 'جاري التحقق...' : 'تأكيد'),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  // دالة للتنقل إلى صفحة التحويلات مع حماية كلمة المرور
  void _navigateToTransactionsWithPassword() async {
    // إظهار نافذة إدخال كلمة المرور قبل الدخول لصفحة التحويلات
    final passwordEntered = await _showPasswordDialogForTransactions();
    if (!passwordEntered) return;

    // الانتقال إلى صفحة التحويلات
    navigateToPage(TransactionsPage(authToken: currentToken));
  }

  bool _hasPermission(String permissionKey) {
    // التأكد من أن الصلاحيات محملة، وإلا استخدم القيم الافتراضية
    if (_userPermissions.isEmpty) {
      return _defaultPermissions[permissionKey] ?? false;
    }
    return _userPermissions[permissionKey] ??
        _defaultPermissions[permissionKey] ??
        false;
  }

  String _getPermissionTitle(String key) {
    switch (key) {
      case 'users':
        return 'المستخدمين';
      case 'subscriptions':
        return 'الاشتراكات';
      case 'tasks':
        return 'المهام';
      case 'zones':
        return 'الزونات';
      case 'accounts':
        return 'الحسابات';
      case 'account_records':
        return 'سجلات الحسابات';
      case 'export':
        return 'تصدير البيانات';
      case 'agents':
        return 'تفاصيل الوكلاء';
      case 'google_sheets':
        return 'Google Sheets';
      case 'whatsapp':
        return 'رسائل WhatsApp';
      case 'wallet_balance':
        return 'رصيد المحفظة';
      case 'expiring_soon':
        return 'الانتهاء قريباً';
      case 'quick_search':
        return 'البحث السريع';
      case 'transactions':
        return 'التحويلات';
      case 'notifications':
        return 'الإشعارات';
      case 'audit_logs':
        return 'سجل التدقيق';
      case 'whatsapp_link':
        return 'ربط الواتساب';
      case 'whatsapp_settings':
        return 'إعدادات الواتساب';
      case 'plans_bundles':
        return 'باقات وعروض';
      case 'technicians':
        return 'فني التوصيل';
      case 'whatsapp_business_api':
        return 'WhatsApp Business API';
      case 'whatsapp_bulk_sender':
        return 'إرسال رسائل جماعية';
      case 'whatsapp_conversations_fab':
        return 'زر محادثات الواتساب';
      case 'local_storage':
        return 'التخزين المحلي';
      default:
        return key;
    }
  }

  // دوال مساعدة للتحقق من الصلاحيات ال��يدة
  bool hasGoogleSheetsPermission() {
    return _hasPermission('google_sheets');
  }

  bool hasWhatsAppPermission() {
    return _hasPermission('whatsapp');
  }

  bool hasWalletBalancePermission() {
    return _hasPermission('wallet_balance');
  }

  // دالة للحصول على جميع الصلاحيات (لاستخدامها في الصفحا�� الأخرى)
  Map<String, bool> getAllPermissions() {
    return Map<String, bool>.from(_userPermissions);
  }

  void showError(String message) {
    _showErrorMessage(message);
  }

  void showMessage(String message, Color color) {
    if (!mounted) return;
    ftthShowSnackBar(
      context,
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // دوال إعدادات الواتساب
  Future<void> _loadDefaultWhatsAppPhone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('default_whatsapp_phone');
      if (v != null && v.trim().isNotEmpty) {
        setState(() => _defaultWhatsAppPhone = v.trim());
      }
    } catch (_) {}
  }

  Future<void> _saveDefaultWhatsAppPhone(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = phone.trim();
    await prefs.setString('default_whatsapp_phone', clean);
    setState(() => _defaultWhatsAppPhone = clean);
  }

  Future<void> _loadWhatsAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final useWebSaved = prefs.getBool('whatsapp_use_web') ?? true;
      final autoSendSaved =
          prefs.getBool('whatsapp_auto_send') ?? true; // مُفعل افتراضياً
      setState(() {
        _useWhatsAppWeb = useWebSaved;
        _whatsAppAutoSend = autoSendSaved;
      });
    } catch (e) {
      debugPrint('❌ خطأ في تحميل إعدادات الواتساب: $e');
    }
  }

  // بيكاتشو الآن في Overlay عالمي - لا حاجة لدوال محلية

  Future<void> _saveWhatsAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('whatsapp_use_web', _useWhatsAppWeb);
      await prefs.setBool('whatsapp_auto_send', _whatsAppAutoSend);
    } catch (e) {
      debugPrint('❌ خطأ في حفظ إعدادات الواتساب: $e');
    }
  }

  void _openWhatsAppWebLogin() async {
    try {
      // التحقق من وجود نافذة واتساب مخفية
      if (WhatsAppBottomWindow.hasHiddenWindow) {
        // إظهار النافذة المخفية (maximize)
        WhatsAppBottomWindow.showBottomWindow(context, '', '');
        return;
      }

      // فتح صفحة واتساب جديدة فقط إذا لم تكن هناك نافذة مخفية
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const WhatsAppWebLoginPage()),
      );

      // إعادة إظهار زر الواتساب العائم عند العودة
      if (mounted) {
        _showGlobalWhatsAppButton();
      }

      if (mounted && result == true) {
        showMessage('تم تسجيل الدخول بنجاح لواتساب ويب', Colors.green);
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح صفحة ربط الواتساب: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.error_outline, color: Colors.red, size: 48),
            title: const Text('خطأ في ربط الواتساب'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('عذراً، حدث خطأ في فتح صفحة ربط الواتساب.'),
                const SizedBox(height: 12),
                if (Platform.isWindows) ...[
                  const Text('المشكلة الأكثر شيوعاً:'),
                  const SizedBox(height: 8),
                  const Text('• عدم تثبيت Microsoft Edge WebView2 Runtime'),
                  const SizedBox(height: 8),
                  const Text('الحل:'),
                  const SizedBox(height: 4),
                  const Text(
                      '1. قم بتحميل وتثبيت Microsoft Edge WebView2 Runtime'),
                  const Text('2. أعد تشغيل التطبيق'),
                  const SizedBox(height: 12),
                ],
                Text('تفاصيل الخطأ: ${e.toString()}'),
              ],
            ),
            actions: [
              if (Platform.isWindows)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _launchWebView2DownloadPage();
                  },
                  child: const Text('تحميل WebView2'),
                ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('موافق'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// فتح صفحة تحميل WebView2 Runtime
  void _launchWebView2DownloadPage() async {
    const url =
        'https://developer.microsoft.com/en-us/microsoft-edge/webview2/';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          showMessage(
              'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.',
              Colors.orange);
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح رابط التحميل: $e');
      if (mounted) {
        showMessage(
            'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.',
            Colors.orange);
      }
    }
  }

  void _openWhatsAppSettingsDialog() async {
    // تحميل الإعدادات أولاً
    await _loadDefaultWhatsAppPhone();
    await _loadWhatsAppSettings();

    final controller = TextEditingController(text: _defaultWhatsAppPhone ?? '');
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعداد الواتساب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'رقم العميل (مع رمز الدولة بدون +)',
                hintText: 'مثال: 9647XXXXXXXXX',
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('واتساب ويب داخلي',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'إرسال عبر نافذة واتساب ويب داخل التطبيق',
                        style: TextStyle(fontSize: 11)),
                    value: _useWhatsAppWeb,
                    onChanged: (v) {
                      setState(() => _useWhatsAppWeb = v);
                      _saveWhatsAppSettings();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('الإرسال التلقائي',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'إرسال الرسالة تلقائياً بعد لصق النص (TAB×16 + Enter)',
                        style: TextStyle(fontSize: 11)),
                    value: _whatsAppAutoSend,
                    onChanged: (v) {
                      setState(() => _whatsAppAutoSend = v);
                      _saveWhatsAppSettings();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGeneratingWhatsAppLink
                        ? null
                        : () async {
                            final val = controller.text.trim();
                            if (val.isEmpty) {
                              showMessage('ادخل الرقم أولاً', Colors.red);
                              return;
                            }

                            if (_isGeneratingWhatsAppLink) return;
                            setState(() => _isGeneratingWhatsAppLink = true);
                            try {
                              // استخدام رابط wa.me المباشر
                              final msg = Uri.encodeComponent(
                                  'رسالة تجريبية من نظام الصفحة الرئيسية');
                              final url = 'https://wa.me/$val?text=$msg';
                              await launchUrl(Uri.parse(url),
                                  mode: LaunchMode.externalApplication);
                            } catch (e) {
                              if (mounted) {
                                showMessage('خطأ: $e', Colors.red);
                              }
                            } finally {
                              if (mounted) {
                                setState(
                                    () => _isGeneratingWhatsAppLink = false);
                              }
                            }
                          },
                    icon: _isGeneratingWhatsAppLink
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chat_outlined),
                    label: const Text('إرسال تجريبي'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final val = controller.text.trim();
              if (val.isEmpty) {
                showMessage('الرقم فارغ', Colors.red);
                return;
              }
              await _saveDefaultWhatsAppPhone(val);
              await _saveWhatsAppSettings();
              if (mounted) {
                Navigator.of(ctx).pop();
                showMessage('تم الحفظ', Colors.green);
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          )
        ],
      ),
    );
  }

  void changeHierarchyLevel(int level) {
    setState(() {
      hierarchyLevel = level;
      isAdmin = _checkAdminPermissions();
    });
    fetchDashboardData();
    _loadUserPermissions(); // إعادة تحميل الصلاحيا�� عند تغيير المستوى
  }

  void navigateToPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    ).then((_) {
      // إعادة إظهار زر الواتساب العائم عند العودة من أي صفحة
      if (mounted) {
        _showGlobalWhatsAppButton();
      }
    });
  }

  // وظيفة عرض معلومات المستخدم من الن��امين مع البيانات التفصيلية
  void _showUserInfoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Icon(
                  Icons.person_pin_rounded,
                  color: Color(0xFF1A237E),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'معلومات الشريك التفصيلية',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // معلومات النظام الأول (Google Sheets) إذا كانت متوفرة
                  if (widget.firstSystemUsername != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green[50]!, Colors.green[100]!],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.table_chart, color: Colors.green[700]),
                              const SizedBox(width: 8),
                              Text(
                                'نظام Google Sheets',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow('اسم المستخدم',
                              widget.firstSystemUsername!, Icons.person),
                          _buildInfoRow(
                              'الصلاحيات',
                              widget.firstSystemPermissions ?? 'غير محدد',
                              Icons.security),
                          _buildInfoRow(
                              'القسم',
                              widget.firstSystemDepartment ?? 'غير محدد',
                              Icons.business),
                          _buildInfoRow(
                              'المركز',
                              widget.firstSystemCenter ?? 'غير محدد',
                              Icons.location_city),
                          _buildInfoRow(
                              'الراتب',
                              widget.firstSystemSalary ?? 'غير محدد',
                              Icons.attach_money),
                        ],
                      ),
                    ),

                  // معلومات النظام الثاني (FTTH) - المعلومات الأساسية
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue[50]!, Colors.blue[100]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.fiber_smart_record,
                                color: Colors.blue[700]),
                            const SizedBox(width: 8),
                            Text(
                              'نظام FTTH - المعلومات الأساسية',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                            'اسم المستخدم',
                            userApiData['username'] ?? widget.username,
                            Icons.person),
                        _buildInfoRow('الاسم الكامل', partnerName ?? 'غير محدد',
                            Icons.badge),
                        _buildCopyableInfoRow(
                          'معرف الشريك',
                          partnerId ?? 'غير محدد',
                          Icons.fingerprint,
                          partnerId ?? '',
                        ),
                        _buildInfoRow('البريد الإلكتروني',
                            userApiData['email'] ?? 'غير محدد', Icons.email),
                        _buildInfoRow(
                            'حالة المدير',
                            isAdmin ? 'مدير' : 'مستخدم عادي',
                            Icons.admin_panel_settings),
                        _buildInfoRow('نوع الأعمال', _getBusinessLineText(),
                            Icons.business_center),
                        _buildInfoRow(
                            'حالة التمثيل',
                            userApiData['impersonated'] == true ? 'نعم' : 'لا',
                            Icons.swap_horiz),
                      ],
                    ),
                  ),

                  // صلاحيات النظام - عرض مضغوط لل��لاحيات المهمة
                  if (userPermissions.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.purple[50]!, Colors.purple[100]!],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_user,
                                  color: Colors.purple[700]),
                              const SizedBox(width: 8),
                              Text(
                                'صلاحيات النظام (${userPermissions.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // عرض الصلاحيات المهمة فقط
                          ..._getImportantPermissions().map((perm) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.check_circle,
                                        size: 16, color: Colors.green),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        perm,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.purple[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          if (userPermissions.length >
                              _getImportantPermissions().length)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'و ${userPermissions.length - _getImportantPermissions().length} صلاحية أخر��...',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.purple[600],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // الأدوار والمناصب
                  if (userRoles.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.orange[50]!, Colors.orange[100]!],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.work_outline,
                                  color: Colors.orange[700]),
                              const SizedBox(width: 8),
                              Text(
                                'الأدوار والمناصب (${userRoles.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...userRoles.take(5).map((role) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.star,
                                        size: 16, color: Colors.orange[600]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _translateRole(
                                            role['displayValue'] ?? ''),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),

                  // معلومات الزونات
                  if (userZones.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.teal[50]!, Colors.teal[100]!],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.map, color: Colors.teal[700]),
                              const SizedBox(width: 8),
                              Text(
                                'الزونات المصرح بها (${userZones.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // عرض أول 10 زونات في صفوف
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: userZones
                                .take(10)
                                .map((zone) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.teal[200],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        zone['displayValue'] ?? '',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal[800],
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                          if (userZones.length > 10)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'و ${userZones.length - 10} زون أخرى...',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.teal[600],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                  // إحصائيات ��لصلاحيات من النظام المحلي
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.indigo[50]!, Colors.indigo[100]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.settings, color: Colors.indigo[700]),
                            const SizedBox(width: 8),
                            Text(
                              'صلاحيات النظام المحلي',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._userPermissions.entries.map((permission) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Icon(
                                  permission.value
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  size: 16,
                                  color: permission.value
                                      ? Colors.green
                                      : Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _getPermissionTitle(permission.key),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.indigo[700],
                                    ),
                                  ),
                                ),
                                Text(
                                  permission.value ? 'مفعل' : 'معطل',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: permission.value
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'إغلاق',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // وظيفة مساعدة لبناء صف المعلومات
  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          const Text(': ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // صف معلومات مع زر نسخ للقيمة (مثلاً معرف الشريك)
  Widget _buildCopyableInfoRow(
      String label, String value, IconData icon, String toCopy) {
    final bool hasValue = value.trim().isNotEmpty && value != 'غير محدد';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          const Text(': ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C3E50),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  color: Colors.blueGrey,
                  tooltip: 'نسخ',
                  onPressed: hasValue
                      ? () async {
                          await Clipboard.setData(ClipboardData(text: toCopy));
                          if (mounted) {
                            ftthShowSnackBar(
                              context,
                              const SnackBar(
                                content: Text('تم نسخ المعرف'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        }
                      : null,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ��وال مساعدة لمعالجة البيانات التفصيلية

  String _getBusinessLineText() {
    if (userApiData['linesOfBusiness'] != null &&
        userApiData['linesOfBusiness'].isNotEmpty) {
      return userApiData['linesOfBusiness'][0]['displayValue'] ?? 'FTTH';
    }
    return 'FTTH';
  }

  List<String> _getImportantPermissions() {
    final importantKeywords = [
      'Query Customers',
      'Query Subscriptions',
      'Query Tasks',
      'Query Zones',
      'Query Partners',
      'Query Dashboard',
      'SuperAdminMember',
      'ContractorMember',
      'Can Manage',
      'Can Create',
      'Can Cancel',
      'Can Transfer'
    ];

    return userPermissions
        .where((perm) => importantKeywords
            .any((keyword) => perm['displayValue']?.contains(keyword) == true))
        .take(8)
        .map((perm) => _translatePermission(perm['displayValue'] ?? ''))
        .toList();
  }

  String _translatePermission(String permission) {
    final translations = {
      'Can Query Customers': 'الاستعلام عن العملاء',
      'Can Query Subscriptions': 'الاستعلام عن الاشتراكات',
      'Can Query Tasks': 'الاستعلام عن المهام',
      'Can Query Zones': 'الاستعلام عن الزونات',
      'Can Query Partners': 'الاستعلام عن الشركاء',
      'Can Query Dashboard': 'الوصول للوحة التحكم',
      'Can Create Subscription': 'إنشاء اشتراكات',
      'Can Cancel Subscription': 'إلغاء اشتراكات',
      'Can Renew Subscription': 'تجديد اشتراكات',
      'Can Transfer Commission': 'تحويل العمولات',
      'Can Query Customer Wallet': 'الاستعلام عن محافظ العملاء',
      'Can Query Partner Wallet': 'الاستعلام عن محفظة الشريك',
      'SuperAdminMember': 'عضو مدير عام',
      'ContractorMember': 'عضو مقاول'
    };

    return translations[permission] ?? permission;
  }

  String _translateRole(String role) {
    final translations = {
      'SuperAdminMember': 'عضو مدير عام',
      'ContractorMember': 'عضو مقاول',
      'manage-account': 'إدارة الحساب',
      'manage-account-links': 'إدارة ر��ابط الحساب',
      'view-profile': 'عرض الملف الشخصي',
      'default-roles-partners': 'أدوار الشركاء الافتراضية',
      'offline_access': 'الوصول غير المتصل',
      'uma_authorization': 'تفويض UMA'
    };

    return translations[role] ?? role;
  }

  // إظهار الزر العائم للواتساب بشكل عام
  void _showGlobalWhatsAppButton() {
    try {
      // إظهار زر واتساب ويب (الزر الأيمن) - دائماً ظاهر
      WhatsAppBottomWindow.ensureFloatingButton(context);

      // التحقق من صلاحية إظهار الزر العائم للمحادثات (الزر الأيسر)
      if (_hasPermission('whatsapp_conversations_fab')) {
        WhatsAppBottomWindow.showConversationsFloatingButton(context,
            isAdmin: isAdmin);
      } else {
        // إخفاء الزر العائم إذا لم تكن هناك صلاحية
        WhatsAppBottomWindow.hideConversationsFloatingButton();
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في إظهار زر الواتساب العائم: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // تحسين فحص الشاشة مع مراعاة أحجام مختلفة
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final isTablet = screenWidth > 600;
    final isSmallPhone = screenWidth < 380;

    // حماية من الأخطاء أثناء البناء
    return RepaintBoundary(
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            appBar: _buildAppBar(isTablet, isSmallPhone, screenWidth),
            drawer: _buildDrawer(isTablet, isSmallPhone, screenWidth),
            body: isLoadingDashboard
                ? _buildLoadingIndicator(isTablet)
                : _buildDashboardContent(isTablet, screenWidth),
          ),
          // مؤشر الجلب في الخلفية - عائم
          _buildFloatingBackgroundSyncIndicator(),
        ],
      ),
    );
  }

  /// بناء مؤشر الجلب في الخلفية العائم
  Widget _buildFloatingBackgroundSyncIndicator() {
    return ListenableBuilder(
      listenable: BackgroundSyncService.instance,
      builder: (context, _) {
        final syncService = BackgroundSyncService.instance;
        if (!syncService.isSyncing) {
          return const SizedBox.shrink();
        }

        final progress = syncService.progress;
        return Positioned(
          top: MediaQuery.of(context).padding.top + 70,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1A237E),
                    const Color(0xFF3949AB),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // أيقونة متحركة
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      value: progress.total > 0
                          ? progress.current / progress.total
                          : null,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                      backgroundColor: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // النص والنسبة
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'جلب البيانات في الخلفية',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          progress.message,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // النسبة المئوية
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${progress.percentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // زر الإلغاء
                  InkWell(
                    onTap: () => syncService.cancelSync(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
      bool isTablet, bool isSmallPhone, double screenWidth) {
    // الألوان المستخدمة في التدرج - فخم وأنيق
    final gradientColors = [
      const Color(0xFF0D1B2A), // أزرق داكن فاخر
      const Color(0xFF1B263B), // أزرق متوسط
      const Color(0xFF415A77), // أزرق فاتح أنيق
    ];

    // تحديد لون النص والأيقونات بطريقة ذكية
    final smartTextColor =
        SmartTextColor.getAppBarTextColorWithGradient(context, gradientColors);

    return AppBar(
      elevation: 0,
      toolbarHeight: 64,
      shadowColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      leading: Builder(
        builder: (BuildContext context) {
          return Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: IconButton(
              icon: Icon(
                Icons.menu_rounded,
                color: smartTextColor,
                size: isSmallPhone ? 22.0 : (isTablet ? 26.0 : 24.0),
              ),
              onPressed: () => Scaffold.of(context).openDrawer(),
              tooltip: 'القائمة الجانبية',
            ),
          );
        },
      ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
            stops: const [0.0, 0.5, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0D1B2A).withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
      centerTitle: true,
      title: partnerName != null
          ? GestureDetector(
              onTap: _showUserInfoDialog,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: screenWidth * 0.4, // تحديد العرض الأقصى
                ),
                padding: EdgeInsets.symmetric(
                    horizontal: isSmallPhone ? 8.0 : 10.0,
                    vertical: isSmallPhone ? 4.0 : 6.0),
                decoration: BoxDecoration(
                  color: smartTextColor == Colors.white
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.black.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(
                    color: smartTextColor.withValues(alpha: 0.3),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_outline,
                        color: smartTextColor,
                        size: isSmallPhone ? 18.0 : (isTablet ? 20.0 : 19.0)),
                    SizedBox(width: isSmallPhone ? 4.0 : 6.0),
                    Flexible(
                      child: Text(
                        partnerName!,
                        style: TextStyle(
                          color: smartTextColor,
                          fontSize:
                              isSmallPhone ? 12.0 : (isTablet ? 14.0 : 13.0),
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(width: isSmallPhone ? 2.0 : 4.0),
                    Icon(Icons.info_outline,
                        color: smartTextColor.withValues(alpha: 0.8),
                        size: isSmallPhone ? 16.0 : (isTablet ? 18.0 : 17.0)),
                  ],
                ),
              ),
            )
          : Text(
              'لوحة التحكم',
              style: TextStyle(
                color: smartTextColor,
                fontSize: isSmallPhone ? 16.0 : (isTablet ? 20.0 : 18.0),
                fontWeight: FontWeight.bold,
              ),
            ),
      actions: [
        // ✅ زر العودة للوحة تحكم Super Admin
        if (widget.isSuperAdminMode)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: IconButton(
              icon: Icon(
                Icons.admin_panel_settings,
                color: Colors.amber,
                size: isSmallPhone ? 22.0 : (isTablet ? 28.0 : 26.0),
              ),
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const SuperAdminDashboard(),
                  ),
                  (route) => false,
                );
              },
              tooltip: 'العودة للوحة تحكم مدير النظام',
            ),
          ),
        IconButton(
          icon: Icon(
            Icons.logout_rounded,
            color: smartTextColor,
            size: isSmallPhone ? 24.0 : (isTablet ? 30.0 : 28.0),
          ),
          onPressed: () async {
            final result = await LogoutDialogHelper.show(
              context,
              title: 'تسجيل الخروج',
              message: 'هل تريد العودة إلى النظام الأول؟',
              confirmText: 'تسجيل الخروج',
              icon: Icons.logout_rounded,
            );

            if (result != null && result['confirmed'] == true) {
              // تنفيذ تسجيل الخروج بناءً على خيار المستخدم
              if (result['clearCredentials'] == true) {
                await AuthService.instance.logoutAndClearAll();
              } else {
                await AuthService.instance.logout();
              }

              if (mounted) {
                // إظهار الزر العائم للواتساب قبل الانتقال لضمان عدم اختفائه
                try {
                  WhatsAppBottomWindow.ensureFloatingButton(context);
                } catch (e) {
                  debugPrint('⚠️ خطأ في إظهار زر الواتساب قبل الانتقال: $e');
                }

                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => firstSystem.HomePage(
                      username: widget.firstSystemUsername ?? 'مستخدم',
                      permissions: widget.firstSystemPermissions ?? 'default',
                      department: widget.firstSystemDepartment ?? 'عام',
                      center: widget.firstSystemCenter ?? 'الرئيسي',
                      salary: widget.firstSystemSalary ?? '0',
                      pageAccess: widget.firstSystemPageAccess ?? {},
                    ),
                  ),
                );
              }
            }
          },
          tooltip: 'العودة للنظام الأول',
          padding: EdgeInsets.all(isSmallPhone ? 10.0 : 12.0),
        ),
        AnimatedBuilder(
          animation: _refreshAnimationController,
          builder: (context, child) {
            return Transform.rotate(
              angle: _refreshAnimationController.value * 2 * 3.14159,
              child: IconButton(
                icon: Icon(
                  Icons.refresh_rounded,
                  color: smartTextColor,
                  size: isSmallPhone ? 24.0 : (isTablet ? 30.0 : 28.0),
                ),
                onPressed: isRefreshing ? null : _manualFullRefresh,
                tooltip: 'تحديث كامل',
                padding: EdgeInsets.all(isSmallPhone ? 10.0 : 12.0),
              ),
            );
          },
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(12.0),
        ),
      ),
    );
  }

  Widget _buildDrawer(bool isTablet, bool isSmallPhone, double screenWidth) {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
            stops: [0.0, 0.3],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildDrawerHeader(isTablet, isSmallPhone),
            Container(
              color: Colors.white,
              child: Column(
                children: [
                  // ============ الأزرار التالية تظهر فقط في الواجهة الرئيسية (الوصول السريع) ============
                  // البحث السريع، المشتركين، الاشتراكات، الانتهاء قريباً، المهام، سجلات الحسابات
                  // ==================================================================================

                  // ═══════════════════════════════════════════════════════════════════
                  // 📊 قسم البيانات والإدارة
                  // ═══════════════════════════════════════════════════════════════════

                  // 1 بيانات (تفاصيل الوكلاء + بيانات المستخدمين)
                  if (_hasPermission('agents'))
                    _buildDrawerItem(
                      icon: Icons.folder_shared_rounded,
                      title: 'بيانات',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.deepPurple,
                      onTap: () => navigateToPage(
                        DataPage(authToken: currentToken),
                      ),
                    ),

                  // 2 إدارة الزونات
                  if (_hasPermission('zones'))
                    _buildDrawerItem(
                      icon: Icons.location_on_rounded,
                      title: 'إدارة الزونات',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.teal,
                      onTap: () => navigateToPage(
                        ZonesPage(authToken: currentToken),
                      ),
                    ),

                  // 3 سجل التدقيق
                  if (_hasPermission('audit_logs'))
                    _buildDrawerItem(
                      icon: Icons.history_rounded,
                      title: 'سجل التدقيق',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.indigo,
                      onTap: () => navigateToPage(
                        CaounterDetailsPage(
                          authToken: currentToken,
                          username: widget.username,
                        ),
                      ),
                    ),

                  // 4 تصدير البيانات
                  if (_hasPermission('export'))
                    _buildDrawerItem(
                      icon: Icons.import_export_rounded,
                      title: 'تصدير البيانات',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.brown,
                      onTap: () => navigateToPage(
                        ExportPage(authToken: currentToken),
                      ),
                    ),

                  // ═══════════════════════════════════════════════════════════════════
                  // 💰 قسم المالية
                  // ═══════════════════════════════════════════════════════════════════

                  // 5 التحويلات
                  if (_hasPermission('transactions'))
                    _buildDrawerItem(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'التحويلات',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.amber,
                      onTap: _navigateToTransactionsWithPassword,
                    ),

                  // ═══════════════════════════════════════════════════════════════════
                  // 💬 قسم الواتساب
                  // ═══════════════════════════════════════════════════════════════════

                  // 6 محادثات WhatsApp
                  if (_hasPermission('whatsapp_conversations_fab'))
                    _buildDrawerItem(
                      icon: Icons.chat_rounded,
                      title: 'محادثات WhatsApp',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.green,
                      onTap: () => navigateToPage(
                          WhatsAppConversationsPage(isAdmin: isAdmin)),
                    ),

                  // 7 إرسال رسائل جماعية (يحتوي على إعدادات API والتقارير)
                  if (_hasPermission('whatsapp_bulk_sender'))
                    _buildDrawerItem(
                      icon: Icons.send_rounded,
                      title: 'إرسال رسائل جماعية',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.teal,
                      onTap: () => navigateToPage(
                        const WhatsAppBulkSenderPage(),
                      ),
                    ),

                  // 8 إعدادات الواتساب
                  if (_hasPermission('whatsapp_settings'))
                    _buildDrawerItem(
                      icon: Icons.settings_applications_rounded,
                      title: 'إعدادات الواتساب',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.green,
                      onTap: _openWhatsAppSettingsDialog,
                    ),

                  // ═══════════════════════════════════════════════════════════════════
                  // 🔧 قسم الخدمات
                  // ═══════════════════════════════════════════════════════════════════

                  // 10 فني التوصيل
                  if (_hasPermission('technicians'))
                    _buildDrawerItem(
                      icon: Icons.engineering_rounded,
                      title: 'فني التوصيل',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.blueGrey,
                      onTap: () => navigateToPage(const TechniciansPage()),
                    ),

                  // 11 التخزين الداخلي
                  if (_hasPermission('local_storage'))
                    _buildDrawerItem(
                      icon: Icons.storage_rounded,
                      title: 'التخزين الداخلي',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.cyan,
                      onTap: () => navigateToPage(
                          LocalStoragePage(authToken: currentToken)),
                    ),

                  // تمت إزالة زر معلومات الشريك من القائمة الجانبية بناءً على الطلب

                  // رسالة في حالة عدم وجود صلاحيات
                  if (!_hasPermission('users') &&
                      !_hasPermission('subscriptions') &&
                      !_hasPermission('tasks') &&
                      !_hasPermission('zones') &&
                      !_hasPermission('accounts') &&
                      !_hasPermission('account_records') &&
                      !_hasPermission('export') &&
                      !_hasPermission('agents') &&
                      !_hasPermission('expiring_soon') &&
                      !_hasPermission('quick_search') &&
                      !_hasPermission('google_sheets') &&
                      !_hasPermission('audit_logs') &&
                      !_hasPermission('whatsapp') &&
                      !_hasPermission('wallet_balance') &&
                      !_hasPermission('whatsapp_link') &&
                      !_hasPermission('whatsapp_settings') &&
                      !_hasPermission('plans_bundles') &&
                      !_hasPermission('technicians') &&
                      !_hasPermission('local_storage'))
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.lock_outline,
                            color: Colors.orange[600],
                            size: isSmallPhone ? 24 : 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'لا توجد صلاحيات متاحة',
                            style: TextStyle(
                              color: Colors.orange[700],
                              fontWeight: FontWeight.bold,
                              fontSize: isSmallPhone ? 12 : 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'يرجى التواصل مع المدير لمنح الصلاحيات',
                            style: TextStyle(
                              color: Colors.orange[600],
                              fontSize: isSmallPhone ? 10 : 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader(bool isTablet, bool isSmallPhone) {
    final double headerHeight = isSmallPhone ? 90 : (isTablet ? 100 : 95);
    return Container(
      height: headerHeight,
      margin: EdgeInsets.zero,
      padding:
          EdgeInsets.symmetric(horizontal: 20, vertical: isSmallPhone ? 8 : 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0D1B2A),
            Color(0xFF1B263B),
            Color(0xFF415A77),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D1B2A).withValues(alpha: 0.5),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // أيقونة فخمة
          Container(
            padding: EdgeInsets.all(isSmallPhone ? 4 : 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.diamond_rounded,
              color: Colors.amber[300],
              size: isSmallPhone ? 16 : 24,
            ),
          ),
          SizedBox(height: isSmallPhone ? 2 : 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'القائمة الرئيسية',
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmallPhone ? 12 : (isTablet ? 18 : 16),
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    offset: const Offset(1, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required bool isTablet,
    required bool isSmallPhone,
    required MaterialColor color,
    required VoidCallback onTap,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    double scale;
    if (screenWidth < 330) {
      scale = 0.78;
    } else if (screenWidth < 370) {
      scale = 0.84;
    } else if (screenWidth < 420) {
      scale = 0.88;
    } else if (screenWidth < 500) {
      scale = 0.92;
    } else if (screenWidth < 600) {
      scale = 0.95;
    } else {
      scale = 1.0;
    }

    final double baseBox = isTablet ? 52 : 48;
    final double boxSize =
        ((isSmallPhone ? 40 : baseBox * scale).clamp(36, 52)).toDouble();
    final double iconSize =
        ((isSmallPhone ? 18 : (isTablet ? 24 : 20)) * scale).toDouble();
    final double titleFont = ((isSmallPhone ? 12 : (isTablet ? 14 : 13)) *
            (scale < 0.85 ? 0.95 : 1.0))
        .toDouble();
    final double trailingSize =
        ((isSmallPhone ? 16 : (isTablet ? 20 : 18)) * scale).toDouble();
    final double horizPad = ((isSmallPhone ? 8 : 12) * scale).toDouble();
    final double vertPad = ((isSmallPhone ? 6 : 8) * scale).toDouble();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white,
            color.shade50,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.shade200.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.8),
            spreadRadius: -2,
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          width: boxSize,
          height: boxSize,
          padding: EdgeInsets.all(isSmallPhone ? 8 : (boxSize * 0.22)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.shade300, color.shade600],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: iconSize.clamp(16, 26).toDouble(),
            color: Colors.white,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: titleFont.clamp(11, 15).toDouble(),
            fontWeight: FontWeight.w600,
            color: color.shade900,
            height: 1.15,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: trailingSize.clamp(14, 20).toDouble(),
          color: color.shade600,
        ),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: horizPad.clamp(8, 16).toDouble(),
          vertical: vertPad.clamp(4, 12).toDouble(),
        ),
        minLeadingWidth: 0,
        dense: true,
      ),
    );
  }

  Widget _buildLoadingIndicator(bool isLargeScreen) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // حلقة تحميل فخمة متوهجة
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  const Color(0xFFF0F4FF),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D1B2A).withValues(alpha: 0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.9),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // حلقة خارجية متوهجة
                SizedBox(
                  width: 70,
                  height: 70,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFF415A77).withValues(alpha: 0.3),
                    ),
                  ),
                ),
                // حلقة داخلية
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF0D1B2A),
                    ),
                  ),
                ),
                // أيقونة في المنتصف
                Icon(
                  Icons.diamond_outlined,
                  color: const Color(0xFF415A77),
                  size: 20,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // نص متحرك
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF0D1B2A), Color(0xFF415A77), Color(0xFF0D1B2A)],
            ).createShader(bounds),
            child: Text(
              'جاري تحميل البيانات...',
              style: TextStyle(
                fontSize: isLargeScreen ? 18 : 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent(bool isLargeScreen, double screenWidth) {
    // بيكاتشو الآن في Overlay عالمي (لا حاجة لـ MouseRegion هنا)
    return RefreshIndicator(
      onRefresh: _performRefresh,
      child: SizedBox.expand(
        child: Stack(
          children: [
            // طبقة حركة الاضواء (ألياف)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _fiberAnim,
                  builder: (context, _) => CustomPaint(
                    painter: _FiberLightPainter(progress: _fiberAnim.value),
                  ),
                ),
              ),
            ),
            // خلفية زخرفية خفيفة مستوحاة من الألياف (دوائر متدرجة)
            Positioned(
              top: -80,
              right: -60,
              child: _decorCircle(const Color(0xFF00BCD4), 180, 0.10),
            ),
            Positioned(
              bottom: -100,
              left: -60,
              child: _decorCircle(const Color(0xFF1A237E), 220, 0.08),
            ),
            // المحتوى القابل للتمرير
            SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(isLargeScreen ? 20 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // بطاقة العملاء الحديثة في الأعلى فقط
                  _buildTopStatsRow(isLargeScreen),
                  const SizedBox(height: 16),
                  // كروت المحفظة في الأعلى (للمديرين فقط أو المصرح لهم)
                  if (hasWalletBalancePermission())
                    _buildWalletCards(isLargeScreen),

                  if (hasWalletBalancePermission()) const SizedBox(height: 20),

                  // بطاقة محفظة عضو الفريق تظهر دائماً إذا كانت المحفظة متوفرة حتى بدون صلاحية المحفظة العامة
                  if (!hasWalletBalancePermission() && hasTeamMemberWallet) ...[
                    _buildTeamMemberWalletCard(),
                    const SizedBox(height: 20),
                  ],

                  // شريط الأدوات السريعة المحدث
                  _buildQuickActionsBar(isLargeScreen, screenWidth),
                  const SizedBox(
                      height: 80), // مسافة سفلية حتى لا يغطيها شريط "آخر تحديث"
                ],
              ),
            ),
            // معلومات آخر تحديث - مثبتة أسفل الشاشة
            if (lastUpdateTime != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: _buildLastUpdateInfo(isLargeScreen),
                  ),
                ),
              ),
            // ⚡ بيكاتشو الآن في Overlay عالمي (pikachu_overlay.dart)
          ],
        ),
      ),
    );
  }

  // عنصر زخرفي دائري بخلفية شعاعية
  Widget _decorCircle(Color color, double size, double opacity) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: opacity), Colors.transparent],
          ),
        ),
      ),
    );
  }

  // صف علوي عصري لبطاقة العملاء فقط
  Widget _buildTopStatsRow(bool isLargeScreen) {
    return Row(
      children: [
        Expanded(child: _buildCustomersCard()),
      ],
    );
  }

  // بطاقة مخصصة لعرض العملاء بشكل حديث وفخم
  Widget _buildCustomersCard() {
    final total = (dashboardData['customers']?['totalCount'] ?? 0) as int;
    final active = (dashboardData['customers']?['totalActive'] ?? 0) as int;
    final inactive = (dashboardData['customers']?['totalInactive'] ?? 0) as int;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Container(
      padding: EdgeInsets.all(isTablet ? 16 : 14),
      decoration: BoxDecoration(
        // خلفية زجاجية فاخرة
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0D1B2A).withValues(alpha: 0.95),
            const Color(0xFF1B263B).withValues(alpha: 0.9),
            const Color(0xFF415A77).withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D1B2A).withValues(alpha: 0.5),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: const Color(0xFF415A77).withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: -5,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // البطاقات الإحصائية الفخمة
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final cardWidth = (availableWidth - 24) / 3;
              return Row(
                children: [
                  Expanded(
                    child: _buildLuxuryStatCard(
                      label: 'إجمالي العملاء',
                      value: total,
                      icon: Icons.groups_rounded,
                      gradientColors: const [
                        Color(0xFFFF9800),
                        Color(0xFFFF5722)
                      ],
                      glowColor: const Color(0xFFFF9800),
                      isTotal: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildLuxuryStatCard(
                      label: 'نشط',
                      value: active,
                      icon: Icons.check_circle_rounded,
                      gradientColors: const [
                        Color(0xFF4CAF50),
                        Color(0xFF2E7D32)
                      ],
                      glowColor: const Color(0xFF4CAF50),
                      percent: total > 0 ? (active / total * 100).round() : 0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildLuxuryStatCard(
                      label: 'منتهي',
                      value: inactive,
                      icon: Icons.cancel_rounded,
                      gradientColors: const [
                        Color(0xFFE53935),
                        Color(0xFFB71C1C)
                      ],
                      glowColor: const Color(0xFFE53935),
                      percent: total > 0 ? (inactive / total * 100).round() : 0,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // بطاقة إحصائية فخمة مع تأثيرات بصرية
  Widget _buildLuxuryStatCard({
    required String label,
    required int value,
    required IconData icon,
    required List<Color> gradientColors,
    required Color glowColor,
    int? percent,
    bool isTotal = false,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 400;

    return Container(
      padding: EdgeInsets.all(isSmall ? 10 : 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isTotal
              ? [
                  gradientColors[0].withValues(alpha: 0.3),
                  gradientColors[1].withValues(alpha: 0.2),
                ]
              : [
                  Colors.white.withValues(alpha: 0.15),
                  Colors.white.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isTotal
              ? gradientColors[0].withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.2),
          width: isTotal ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: isTotal ? 0.4 : 0.2),
            blurRadius: isTotal ? 25 : 20,
            spreadRadius: isTotal ? 0 : -5,
          ),
        ],
      ),
      child: Column(
        children: [
          // الأيقونة المتوهجة
          Container(
            padding: EdgeInsets.all(isSmall ? 8 : 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.6),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: isSmall ? 18 : 20,
            ),
          ),
          SizedBox(height: isSmall ? 8 : 10),
          // الرقم البارز جداً
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  gradientColors[0].withValues(alpha: 0.2),
                  Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              NumberFormat('#,##0').format(value),
              style: TextStyle(
                fontSize: isSmall ? 22 : 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1,
                height: 1,
                shadows: [
                  Shadow(
                    color: gradientColors[0].withValues(alpha: 0.8),
                    offset: const Offset(0, 0),
                    blurRadius: 20,
                  ),
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // شريط النسبة أو شارة الإجمالي
          if (percent != null) ...[
            // شريط النسبة المتحرك
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerRight,
                widthFactor: percent / 100,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradientColors),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.7),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // النسبة المئوية بارزة
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    gradientColors[0].withValues(alpha: 0.3),
                    gradientColors[1].withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: gradientColors[0].withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '$percent%',
                style: TextStyle(
                  fontSize: isSmall ? 12 : 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: gradientColors[0],
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // شارة "الكل" للإجمالي
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradientColors),
                borderRadius: BorderRadius.circular(3),
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.7),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    gradientColors[0].withValues(alpha: 0.3),
                    gradientColors[1].withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: gradientColors[0].withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '100%',
                style: TextStyle(
                  fontSize: isSmall ? 12 : 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: gradientColors[0],
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: isSmall ? 6 : 8),
          // العنوان
          Text(
            label,
            style: TextStyle(
              fontSize: isSmall ? 10 : 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // عنصر إحصائي بدائرة نسبية (Donut)
  Widget _buildDonutStat({
    required String label,
    required int value,
    required double percent, // 0..1 نسبة من الإجمالي
    required MaterialColor color,
    required double size,
  }) {
    final pctText = (percent * 100).round();
    // ضبط أحجام الخط داخل الدائرة حسب حجمها
    final valueFont = size >= 110 ? 22.0 : (size >= 98 ? 19.0 : 17.0);
    final pctFont = size >= 110 ? 12.0 : (size >= 98 ? 11.0 : 10.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // حاوية خارجية مع ظلال فخمة
        Container(
          width: size + 8,
          height: size + 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.25),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.9),
                blurRadius: 10,
                spreadRadius: -3,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            width: size,
            height: size,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: percent.isNaN ? 0.0 : percent),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, p, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(size),
                      painter: _DonutProgressPainter(
                        progress: p,
                        color: color,
                        strokeWidth: size / 7.0,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // العدد داخل الدائرة
                        Text(
                          NumberFormat('#,##0').format(value),
                          style: TextStyle(
                            fontSize: valueFont,
                            fontWeight: FontWeight.w900,
                            color: color.shade800,
                            shadows: [
                              Shadow(
                                color: color.withValues(alpha: 0.3),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            percent >= 1.0 && label == 'الكلي'
                                ? '100%'
                                : '%$pctText',
                            style: TextStyle(
                              fontSize: pctFont,
                              fontWeight: FontWeight.w700,
                              color: color.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        // العنوان مع تصميم فخم
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.shade100, color.shade50],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.shade200,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color.shade800,
            ),
          ),
        ),
      ],
    );
  }

  // شريط الأد��ات السريعة المحدث
  Widget _buildQuickActionsBar(bool isLargeScreen, double screenWidth) {
    // تحديد عدد الأعمدة حسب حجم الشاشة
    int crossAxisCount;
    double childAspectRatio;

    if (screenWidth < 320) {
      crossAxisCount = 1; // شاشة صغيرة جداً - عمود واحد
      // تقليل النسبة لزيادة الارتفاع لاستيعاب حجم أكبر للأزرار
      childAspectRatio = 3.0;
    } else if (screenWidth < 380) {
      crossAxisCount = 2; // شاشة صغيرة - عمودين
      childAspectRatio = 2.4;
    } else if (screenWidth < 500) {
      crossAxisCount = 2; // شاشة متوسطة - عمودين
      childAspectRatio = 2.2;
    } else if (screenWidth < 600) {
      crossAxisCount = 3; // شاشة كبيرة - ثلاثة أعمدة
      childAspectRatio = 2.0;
    } else {
      crossAxisCount = 4; // تابلت - أربعة أعمدة
      childAspectRatio = 2.4;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // خط فاصل فخم أسود وذهبي
        Container(
          margin: EdgeInsets.symmetric(
            horizontal: screenWidth < 380 ? 16 : 24,
            vertical: screenWidth < 380 ? 12 : 16,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // الخط الأساسي الأسود
              Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      const Color(0xFF1a1a1a),
                      const Color(0xFF000000),
                      const Color(0xFF1a1a1a),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.15, 0.5, 0.85, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // الخط الذهبي المتوهج فوق الأسود
              Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      const Color(0xFFFFD700).withValues(alpha: 0.5),
                      const Color(0xFFFFD700),
                      const Color(0xFFFFD700).withValues(alpha: 0.5),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                  ),
                  borderRadius: BorderRadius.circular(1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              // ماسة ذهبية بإطار أسود في الوسط
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFFFD700),
                      Color(0xFFFFA500),
                      Color(0xFFFFD700),
                    ],
                  ),
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: Colors.black,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.8),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                transform: Matrix4.rotationZ(0.785398), // 45 درجة
              ),
            ],
          ),
        ),
        SizedBox(height: screenWidth < 380 ? 8 : 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          mainAxisSpacing: screenWidth < 380 ? 8 : 12,
          crossAxisSpacing: screenWidth < 380 ? 8 : 12,
          children: _buildQuickActionItems(screenWidth),
        ),
      ],
    );
  }

  List<Widget> _buildQuickActionItems(double screenWidth) {
    final actions = <Widget>[];

    // البحث السريع - يخضع لصلاحية quick_search
    if (_hasPermission('quick_search')) {
      actions.add(_buildQuickActionItem(
        'البحث السريع',
        Icons.search_rounded,
        Colors.green,
        () => navigateToPage(QuickSearchUsersPage(
          authToken: currentToken,
          activatedBy: widget.username,
          hasGoogleSheetsPermission: hasGoogleSheetsPermission(),
          hasWhatsAppPermission: hasWhatsAppPermission(),
          firstSystemPermissions: widget.firstSystemPermissions,
          isAdminFlag: isAdmin,
          importantFtthApiPermissions: _getImportantPermissions(),
        )),
      ));
    }

    // المشتركين - أداة سريعة (تم تقديمها مكان الانتهاء قريباً)
    if (_hasPermission('users')) {
      actions.add(_buildQuickActionItem(
        'المشتركين',
        Icons.people_alt_rounded,
        Colors.purple,
        () => navigateToPage(UsersPage(
          authToken: currentToken,
          activatedBy: widget.username,
          hasGoogleSheetsPermission: hasGoogleSheetsPermission(),
          hasWhatsAppPermission: hasWhatsAppPermission(),
          firstSystemPermissions: widget.firstSystemPermissions,
          isAdminFlag: isAdmin,
          importantFtthApiPermissions: _getImportantPermissions(),
        )),
      ));
    }

    // الاشتراكات - أداة سريعة
    if (_hasPermission('subscriptions')) {
      actions.add(_buildQuickActionItem(
        'الاشتراكات',
        Icons.subscriptions_rounded,
        Colors.blue,
        () => navigateToPage(SubscriptionsPage(authToken: currentToken)),
      ));
    }

    // الاشتراكات المنتهية قريباً - يخضع لصلاحية expiring_soon
    if (_hasPermission('expiring_soon')) {
      actions.add(_buildQuickActionItem(
        'الانتهاء قريباً',
        Icons.schedule_rounded,
        Colors.red,
        () => navigateToPage(ExpiringSoonPage(
          activatedBy: widget.username,
          hasGoogleSheetsPermission: hasGoogleSheetsPermission(),
          hasWhatsAppPermission: hasWhatsAppPermission(),
          firstSystemPermissions: widget.firstSystemPermissions,
          importantFtthApiPermissions: _getImportantPermissions(),
        )),
      ));
    }

    // المهام - أداة سريعة
    if (_hasPermission('tasks')) {
      actions.add(_buildTasksActionItem());
    }

    // سجلات الحسابات - أداة سريعة (صلاحية مستقلة account_records)
    if (_hasPermission('account_records')) {
      actions.add(_buildQuickActionItem(
        'سجلات الحسابات',
        Icons.table_chart_rounded,
        Colors.cyan,
        () => navigateToPage(
          AccountRecordsPage(
            authToken: currentToken,
            activatedBy: widget.username,
            permissions: _userPermissions,
            firstSystemUsername: widget.firstSystemUsername,
            firstSystemPermissions: widget.firstSystemPermissions,
            firstSystemDepartment: widget.firstSystemDepartment,
            firstSystemCenter: widget.firstSystemCenter,
          ),
        ),
      ));
    }

    return actions;
  }

  Widget _buildQuickActionItem(
      String title, IconData icon, MaterialColor color, VoidCallback onTap) {
    // الحصول على عرض الشاشة من MediaQuery
    final screenWidth = MediaQuery.of(context).size.width;

    // تحديد الأحجام المناسبة لكل شاشة مع تحسينات إضافية
    double iconSize;
    double fontSize;
    double padding;
    double verticalSpacing;
    int maxLines;

    if (screenWidth < 320) {
      iconSize = 22;
      fontSize = 11;
      padding = 8;
      verticalSpacing = 4;
      maxLines = 2;
    } else if (screenWidth < 380) {
      iconSize = 24;
      fontSize = 12;
      padding = 10;
      verticalSpacing = 5;
      maxLines = 2;
    } else if (screenWidth < 500) {
      iconSize = 26;
      fontSize = 13;
      padding = 12;
      verticalSpacing = 6;
      maxLines = 2;
    } else if (screenWidth < 600) {
      iconSize = 28;
      fontSize = 14;
      padding = 14;
      verticalSpacing = 7;
      maxLines = 2; // نجبر الكل لسطرين لضبط الارتفاع
    } else {
      iconSize = 32;
      fontSize = 16;
      padding = 16;
      verticalSpacing = 8;
      maxLines = 2; // أيضاً سطران على الشاشات الكبيرة
    }

    // نمط فخم بتدرجات لونية وتأثيرات بصرية
    final labelColor = Colors.white;
    final iconFg = Colors.white;

    final circleSize = iconSize + 14;
    final circleIcon = Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.3),
            Colors.white.withValues(alpha: 0.1),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.2),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize, color: iconFg),
    );

    // جعل الزر يملأ ارتفاع خلية الشبكة لمنع تفاوت الأطوال
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellHeight = constraints.maxHeight;
        // ضمان ألا يكون أصغر من حد أدنى منطقي
        final effectiveHeight = cellHeight.isFinite && cellHeight > 0
            ? cellHeight
            : (padding * 6 + iconSize);

        return SizedBox(
          height: effectiveHeight,
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  color.shade400,
                  color.shade600,
                  color.shade800,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.black,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: color.shade300.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: -2,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: FilledButton.tonal(
              onPressed: () {
                if (mounted) onTap();
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: labelColor,
                minimumSize: Size(double.infinity, effectiveHeight),
                padding: EdgeInsets.symmetric(
                    horizontal: padding, vertical: verticalSpacing),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  circleIcon,
                  SizedBox(height: verticalSpacing),
                  Text(
                    title,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      height: 1.15,
                      letterSpacing: 0.3,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // عنصر خاص لزر المهام مع شارة عددية
  Widget _buildTasksActionItem() {
    return ValueListenableBuilder<int>(
      valueListenable: BadgeService.instance.unreadNotifier,
      builder: (context, count, _) {
        // نستخدم Stack لكن بدون إزاحات سالبة، مع محاذاة الشارة داخل حدود الزر
        final taskButton = _buildQuickActionItem(
          'المهام',
          Icons.task_alt_rounded,
          Colors.orange,
          () {
            BadgeService.instance.clear();
            navigateToPage(TKTATsPage(authToken: currentToken));
          },
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            // تقدير ارتفاع الزر القياسي (نفسه المستخدم في الأزرار الأخرى) عبر constraint
            // لا نحدد ارتفاعاً ثابتاً حتى يستمر التكيّف مع أحجام الشاشات، فقط نضمن ان الشارة داخل.
            return Stack(
              alignment: Alignment.topRight,
              children: [
                taskButton,
                if (count > 0)
                  Positioned(
                    top: 6, // داخل حدود الزر بدل قيم سالبة
                    right: 6,
                    child: AnimatedScale(
                      scale: 1,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red[700],
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.35),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          count > 99 ? '99+' : count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildWalletCards(bool isLargeScreen) {
    final cards = <Widget>[
      Expanded(
        child: _buildWalletCard(
          title: 'رصيد المحفظة',
          value: walletBalance,
          color: Colors.blue,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: _buildWalletCard(
          title: 'العمولة',
          value: commission,
          color: Colors.green,
        ),
      ),
    ];

    // إضافة بطاقة محفظة عضو الفريق إذا كانت متوفرة
    if (hasTeamMemberWallet) {
      cards.add(const SizedBox(width: 16));
      cards.add(
        Expanded(
          child: _buildWalletCard(
            title: 'محفظة عضو الفريق',
            value: teamMemberWalletBalance,
            color: Colors.deepPurple,
          ),
        ),
      );
    }

    // إذا تجاوز عدد العناصر 5 (3 Expanded + 2 SizedBox) نستخدم Wrap لتجنب ضغط البطاقات في صف ضيق
    final expandedCardCount = hasTeamMemberWallet ? 3 : 2;
    if (expandedCardCount > 2) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 820; // تقدير عرض ضيق
          if (isNarrow) {
            // ترتيب عمودي بصفين / أكثر
            return Column(
              children: [
                Row(
                  children: cards.take(3).toList(), // أول بطاقتين + فاصل
                ),
                const SizedBox(height: 12),
                Row(
                  children: cards.skip(3).toList(), // البطاقات المتبقية
                ),
              ],
            );
          }
          return Row(children: cards);
        },
      );
    }
    return Row(children: cards);
  }

  // بطاقة مستقلة لمحفظة عضو الفريق تستخدم عند عدم توفر صلاحية المحفظة العامة
  Widget _buildTeamMemberWalletCard() {
    return Row(
      children: [
        Expanded(
          child: _buildWalletCard(
            title: 'محفظة عضو الفريق',
            value: teamMemberWalletBalance,
            color: Colors.deepPurple,
          ),
        ),
      ],
    );
  }

  Widget _buildWalletCard({
    required String title,
    required double value,
    required MaterialColor color,
  }) {
    // الحصول على عرض الشاشة لتحديد الأحجام المناسبة
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;
    final isDesktop = screenWidth > 1024;

    // تحديد أحجام النصوص حسب حجم الشاشة - أحجام أكبر
    double titleFontSize = isDesktop ? 14 : (isLargeScreen ? 15 : 16);
    double valueFontSize = isDesktop ? 22 : (isLargeScreen ? 24 : 26);
    double cardPadding = isDesktop ? 16 : (isLargeScreen ? 18 : 20);

    return Container(
      padding: EdgeInsets.all(cardPadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color[300]!,
            color[500]!,
            color[700]!,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: color[200]!.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: titleFontSize,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          _animatedCount(
            value,
            TextStyle(
              color: Colors.white,
              fontSize: valueFontSize,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          // تم إزالة كتابة العملة حسب الطلب
        ],
      ),
    );
  }

  Widget _buildLastUpdateInfo(bool isLargeScreen) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.95),
            const Color(0xFFF8FAFF).withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF415A77).withValues(alpha: 0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D1B2A).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF415A77).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.access_time_rounded,
              color: const Color(0xFF415A77),
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'آخر تحديث: ${DateFormat('yyyy/MM/dd - HH:mm:ss').format(lastUpdateTime!)}',
            style: TextStyle(
              fontSize: isLargeScreen ? 13 : 11,
              color: const Color(0xFF415A77),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// رسام خلفية لأشعة ضوئية تتحرك بشكل مائل لمحاكاة الألياف (Top-level)
class _FiberLightPainter extends CustomPainter {
  final double progress; // 0..1
  _FiberLightPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // خطوط رفيعة تشبه الألياف مع نبضات ضوء تتحرك خلالها
    final double angle = -0.35; // ~ -20° لميول الألياف
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    canvas.translate(-size.width / 2, -size.height / 2);

    final double height = size.height * 1.6;
    final double top = -(height - size.height) / 2;
    final double left = -size.width * 0.2; // تمديد بسيط يمين/يسار
    final double right = size.width * 1.2;

    // خصائص الخطوط
    final int linesCount = 12;
    final double spacing = height / (linesCount + 1);
    final double baseWidth = 1.4;
    final Color baseColor =
        const Color(0xFF80DEEA).withValues(alpha: 0.22); // سماوي خافت
    final Color pulseColor =
        const Color(0xFF00E5FF).withValues(alpha: 0.75); // نبضة فاتحة

    final Paint basePaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseWidth
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < linesCount; i++) {
      final double y = top + (i + 1) * spacing + (i % 2 == 0 ? 0 : 3);

      // خط أساسي ممتد عبر العرض
      canvas.drawLine(Offset(left, y), Offset(right, y), basePaint);

      // نبضتان تتحركان بسرعات/مراحل مختلفة
      for (int k = 0; k < 2; k++) {
        final double speed = 1.0 + k * 0.25 + (i % 3) * 0.05; // اختلاف بسيط
        final double phase = (progress * speed + i * 0.07 + k * 0.33) % 1.0;
        final double trackWidth = right - left;
        final double pulseLen = math.max(28.0, size.width * 0.08);
        final double px = left + phase * trackWidth;
        final double x0 = px - pulseLen * 0.5;
        final double x1 = px + pulseLen * 0.5;

        final Paint glow = Paint()
          ..color = pulseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

        final Paint pulse = Paint()
          ..color = pulseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;

        // توهّج خفيف ثم النبضة
        canvas.drawLine(Offset(x0, y), Offset(x1, y), glow);
        canvas.drawLine(Offset(x0, y), Offset(x1, y), pulse);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FiberLightPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// رسام دائرة نسبية (Donut) قابلة لإعادة الاستخدام
class _DonutProgressPainter extends CustomPainter {
  final double progress; // 0..1
  final MaterialColor color;
  final double strokeWidth;

  _DonutProgressPainter({
    required this.progress,
    required this.color,
    this.strokeWidth = 10,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    // هالة خفيفة لإحساس عائم
    final glowPaint = Paint()
      ..color = color.shade200.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius, glowPaint);

    // الخلفية الخافتة
    final bgPaint = Paint()
      ..color = color.shade100
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // التدرج للجزء المتقدم
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi,
        colors: [
          color.shade400,
          color.shade600,
          color.shade400,
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (progress.clamp(0.0, 1.0)) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

// فئة بسيطة لصفحة تسجيل دخول واتساب ويب
// فئة كاملة لصفحة تسجيل دخول واتساب ويب مع WebView
class WhatsAppWebLoginPage extends StatefulWidget {
  const WhatsAppWebLoginPage({super.key});

  @override
  State<WhatsAppWebLoginPage> createState() => _WhatsAppWebLoginPageState();
}

class _WhatsAppWebLoginPageState extends State<WhatsAppWebLoginPage> {
  bool _isLoading = true;
  bool _loggedIn = false;
  String? _error;
  WebViewController? _controller;
  wvwin.WebviewController? _winController;
  Timer? _loginMonitor;

  @override
  void initState() {
    super.initState();
    _restoreFlag();
    _initWeb();
  }

  Future<void> _restoreFlag() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getBool('wa_web_logged_in') ?? false;
      if (v && mounted) setState(() => _loggedIn = true);
    } catch (_) {}
  }

  Future<void> _initWeb() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (Platform.isWindows) {
        await _initWindowsWebView();
      } else {
        await _initFlutterWebView();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة WebView: $e');
      if (mounted) {
        setState(() {
          if (Platform.isWindows && e.toString().contains('WebView2')) {
            _error =
                'يتطلب Microsoft Edge WebView2 Runtime لعمل الواتساب.\n\nيرجى تحميله وتثبيته من موقع مايكروسوفت الرسمي.';
          } else {
            _error = 'خطأ في تحميل واتساب ويب: ${e.toString()}';
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _initWindowsWebView() async {
    try {
      final c = wvwin.WebviewController();

      // التحقق من وجود WebView2 Runtime قبل التهيئة
      await c.initialize();
      await c.setBackgroundColor(Colors.white);
      await c.loadUrl('https://web.whatsapp.com');

      if (mounted) {
        setState(() {
          _winController = c;
          _isLoading = false;
        });
        _startMonitor();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة Windows WebView: $e');
      // إعادة رمي الخطأ ليتم التعامل معه في _initWeb
      throw Exception('Windows WebView2 initialization failed: $e');
    }
  }

  Future<void> _initFlutterWebView() async {
    try {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (_) =>
              {if (mounted) setState(() => _isLoading = true)},
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
            _checkLoginOnce();
          },
          onWebResourceError: (e) {
            debugPrint('❌ خطأ في تحميل الصفحة: ${e.description}');
            if (mounted) {
              setState(() {
                _error = 'تعذر التحميل: ${e.description}';
                _isLoading = false;
              });
            }
          },
        ))
        ..loadRequest(Uri.parse('https://web.whatsapp.com'));

      if (mounted) {
        setState(() => _controller = c);
        _startMonitor();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة Flutter WebView: $e');
      throw Exception('Flutter WebView initialization failed: $e');
    }
  }

  void _startMonitor() {
    _loginMonitor?.cancel();
    _loginMonitor =
        Timer.periodic(const Duration(seconds: 3), (_) => _checkLoginOnce());
  }

  Future<void> _checkLoginOnce() async {
    if (_loggedIn) return;
    try {
      String res = '';
      if (Platform.isWindows && _winController != null) {
        res = await _winController!.executeScript(
                "(function(){return document.querySelector('#pane-side')?'LOGGED':'NOT';})()") ??
            '';
      } else if (!Platform.isWindows && _controller != null) {
        final r = await _controller!.runJavaScriptReturningResult(
            "(function(){return document.querySelector('#pane-side')?'LOGGED':'NOT';})()");
        res = r.toString().replaceAll('"', '');
      }
      if (res.contains('LOGGED')) {
        _onLoginDetected();
      }
    } catch (_) {}
  }

  Future<void> _onLoginDetected() async {
    if (!mounted) return;
    setState(() => _loggedIn = true);
    _loginMonitor?.cancel();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('wa_web_logged_in', true);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تسجيل الدخول إلى WhatsApp Web')));

      Timer(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      });
    }
  }

  Future<void> _logout() async {
    try {
      if (Platform.isWindows && _winController != null) {
        try {
          await _winController!
              .executeScript("localStorage.clear(); sessionStorage.clear();");
        } catch (_) {}
        await _winController!.loadUrl('https://web.whatsapp.com');
      } else if (!Platform.isWindows && _controller != null) {
        try {
          await _controller!.clearCache();
        } catch (_) {}
        try {
          final cm = WebViewCookieManager();
          await cm.clearCookies();
        } catch (_) {}
        await _controller!.loadRequest(Uri.parse('https://web.whatsapp.com'));
      }
      final p = await SharedPreferences.getInstance();
      await p.setBool('wa_web_logged_in', false);
      if (mounted) {
        setState(() {
          _loggedIn = false;
          _isLoading = true;
        });
        _startMonitor();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('🚪 تم تسجيل الخروج (محلي)')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل تسجيل الخروج: $e')));
      }
    }
  }

  /// فتح صفحة تحميل WebView2 Runtime
  void _launchWebView2Download() async {
    const url =
        'https://developer.microsoft.com/en-us/microsoft-edge/webview2/';
    try {
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح رابط التحميل: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _loginMonitor?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_error != null) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _initWeb,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                  if (Platform.isWindows && _error!.contains('WebView2')) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _launchWebView2Download,
                      icon: const Icon(Icons.download),
                      label: const Text('تحميل WebView2'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    } else if (Platform.isWindows) {
      if (_winController == null) {
        content = const Center(child: CircularProgressIndicator());
      } else {
        content = Column(children: [
          Expanded(child: wvwin.Webview(_winController!)),
          _bottomBar()
        ]);
      }
    } else {
      if (_controller == null) {
        content = const Center(child: CircularProgressIndicator());
      } else {
        content = Column(children: [
          Expanded(child: WebViewWidget(controller: _controller!)),
          _bottomBar()
        ]);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تسجيل الدخول - WhatsApp Web'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (Platform.isWindows && _winController != null) {
                _winController!.reload();
              } else if (!Platform.isWindows && _controller != null) {
                _controller!.reload();
              }
              _startMonitor();
            },
          ),
          IconButton(
            tooltip: 'تسجيل خروج',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(children: [
        content,
        if (_isLoading)
          Container(
              color: Colors.black.withValues(alpha: 0.05),
              child: const Center(child: CircularProgressIndicator())),
      ]),
    );
  }

  Widget _bottomBar() => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(top: BorderSide(color: Colors.grey.shade300))),
        child: Row(children: [
          Expanded(
              child: Text(
            _loggedIn
                ? '✅ متصل - جلسة محلية (قد تُفقد عند إغلاق التطبيق)'
                : 'افتح واتساب بالهاتف > الأجهزة المرتبطة > اربط جهازًا لمسح QR',
            style: TextStyle(
                fontSize: 11.5,
                color: _loggedIn ? Colors.green.shade700 : null),
            overflow: TextOverflow.ellipsis,
          )),
          IconButton(
            tooltip: 'فتح خارجي',
            icon: const Icon(Icons.open_in_browser, size: 20),
            onPressed: () => launchUrl(Uri.parse('https://web.whatsapp.com'),
                mode: LaunchMode.externalApplication),
          ),
        ]),
      );
}
