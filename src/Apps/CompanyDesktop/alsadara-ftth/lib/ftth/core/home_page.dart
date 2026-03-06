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
import 'package:iconsax_plus/iconsax_plus.dart';
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
import '../../permissions/permissions.dart';
import '../auth/auth_error_handler.dart';
import '../widgets/notification_filter.dart';
import '../whatsapp/whatsapp_bottom_window.dart'; // استيراد نظام الواتساب العائم
import '../widgets/floating_toolbar.dart'; // شريط الأدوات العائم الموحد
import '../../services/ticket_updates_service.dart'; // خدمة تحديثات التذاكر
import '../../pages/whatsapp_conversations_page.dart'; // صفحة محادثات WhatsApp
import '../../pages/whatsapp_bulk_sender_page.dart'; // صفحة إرسال رسائل جماعية (تحتوي على إعدادات API والتقارير)
import '../../pages/whatsapp_templates_page.dart'; // صفحة إدارة قوالب الواتساب
import '../../whatsapp/pages/whatsapp_settings_hub_page.dart'; // مركز إعدادات الواتساب الموحد

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
import '../../pages/ftth/fetch_server_data_page.dart'; // صفحة جلب بيانات الموقع
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
import '../../test_webview_standalone.dart'; // صفحة اختبار WebView للتقارير
import '../../pages/server_data_page.dart'; // صفحة بيانات السيرفر

class HomePage extends StatefulWidget {
  final String username;
  final String authToken;
  final String? permissions; // إضافة صلاحيات المستخدم
  final String? department; // إضافة القسم
  final String? center; // إضافة المركز
  final String? salary; // إضافة الراتب
  final Map<String, bool>? pageAccess; // إضافة صلاحيات الصفحات
  // معلومات النظام الأول
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
  final Duration _walletRefreshInterval = const Duration(
    minutes: 1,
  ); // يمكن تعديلها لاحقاً بسهولة
  bool _walletFetchInProgress = false; // منع تداخل طلبات الرصيد
  late AnimationController _refreshAnimationController;
  late AnimationController _cardAnimationController;
  late AnimationController _counterAnimationController;

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
    'google_sheets': false, // منع حفظ البيانات في الخادم افتراضياً
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
    'whatsapp_templates': false, // إدارة قوالب الواتساب
    'local_storage': false, // التخزين المحلي للمشتركين
    'local_storage_import': false, // زر استيراد البيانات في التخزين المحلي
    'superset_reports': false, // تقارير Superset
    'server_data': false, // بيانات السيرفر
    'dashboard_project': false, // مشروع Dashboard
    'fetch_server_data': false, // جلب بيانات الموقع
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

    // تحديث التوكن في خدمة تحديثات التذاكر
    TicketUpdatesService.instance.updateAuthToken(widget.authToken);

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
                success
                    ? IconsaxPlusBold.tick_circle
                    : IconsaxPlusBold.close_circle,
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

  // فحص صلاحيات المدير من النظام الأول فقط
  bool _isAdminByUsername() {
    // V2: فحص صلاحية المستخدمين من PermissionManager
    if (PermissionManager.instance.canView('users')) {
      debugPrint('✅ تم تحديد المدير من V2 - صلاحية users: view=true');
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

    // الأولوية الثالثة: فحص الصلاحيات من النظام الأول
    if (widget.firstSystemPermissions != null &&
        widget.firstSystemPermissions!.isNotEmpty) {
      final permissionsToCheck = widget.firstSystemPermissions!.toLowerCase();
      if (permissionsToCheck.contains('مدير') ||
          permissionsToCheck.contains('admin') ||
          permissionsToCheck.contains('administrator')) {
        debugPrint(
          'تم تحديد المدير من خلال صلاحيات النظام الأول: ${widget.firstSystemPermissions}',
        );
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

    _counterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    // بيكاتشو الآن في Overlay عالمي
  }

  Future<void> _initializeApp() async {
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      // ⚡ تحميل جميع الكاش بالتوازي لتسريع الظهور الأول
      final cacheResults = await Future.wait([
        FtthCacheService.loadDashboard(),
        FtthCacheService.loadWallet(),
        FtthCacheService.loadCurrentUser(),
      ]);
      final cachedDash = cacheResults[0];
      final cachedWallet = cacheResults[1];
      final cachedUser = cacheResults[2];

      // دمج كل setState في استدعاء واحد لتقليل إعادة البناء
      if (mounted) {
        setState(() {
          if (cachedDash != null) {
            dashboardData = cachedDash;
            isLoadingDashboard = false;
          }
          if (cachedWallet != null) {
            walletBalance = cachedWallet['balance'] ?? walletBalance;
            commission = cachedWallet['commission'] ?? commission;
            if (cachedWallet['teamMemberWallet'] is Map) {
              final tmw = cachedWallet['teamMemberWallet'];
              hasTeamMemberWallet = tmw['hasWallet'] == true;
              teamMemberWalletBalance = (tmw['balance'] ?? 0.0) * 1.0;
            }
          }
          if (cachedUser != null && cachedUser['self'] != null) {
            partnerId = cachedUser['self']['id']?.toString();
            partnerName = cachedUser['self']['displayValue'];
            userApiData = cachedUser;
            userPermissions = List<Map<String, dynamic>>.from(
              cachedUser['permissions'] ?? [],
            );
            userZones = List<Map<String, dynamic>>.from(
              cachedUser['zones'] ?? [],
            );
            userRoles = List<Map<String, dynamic>>.from(
              cachedUser['roles'] ?? [],
            );
            isAdmin = _checkAdminPermissions();
            isLoadingDashboard = false;
          }
        });
      }

      // حد أقصى لشاشة التحميل: 10 ثوانٍ ثم نعرض المحتوى حتى لو لم تكتمل البيانات
      if (isLoadingDashboard) {
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted && isLoadingDashboard) {
            setState(() => isLoadingDashboard = false);
          }
        });
      }

      await fetchCurrentUser(); // يستخدم الكاش + تحديث في الخلفية
      // تحميل الصلاحيات بعد تحديد حالة المدير
      await _loadUserPermissions();

      // تهيئة شريط الأدوات العائم الموحد
      if (mounted) {
        FloatingToolbar.init(context);
        _showGlobalWhatsAppButton();
        // إبقاء AgentTasksBubble القديم معطلاً — FloatingToolbar يتولى المهمة
      }

      _cardAnimationController.forward();
      _counterAnimationController.forward(from: 0.0);
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
    _counterAnimationController.dispose();

    // تنظيف شريط الأدوات العائم الموحد
    FloatingToolbar.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    // إيقاف المؤقتات والأنيميشن عند مغادرة الصفحة (Navigator.push فوقها)
    _timer?.cancel();
    _timer = null;
    _walletTimer?.cancel();
    _walletTimer = null;
    _cardAnimationController.stop();
    _counterAnimationController.stop();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    // إعادة تشغيل المؤقتات والأنيميشن عند العودة للصفحة
    startAutoRefresh();
    startWalletAutoRefresh();
    _cardAnimationController.forward();
    _counterAnimationController.forward(from: 0.0);
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
    // ⚡ محاولة تحميل بيانات المستخدم من الكاش أولاً لتسريع الظهور
    final cachedUser = await FtthCacheService.loadCurrentUser();
    if (cachedUser != null && cachedUser['self'] != null) {
      if (mounted) {
        setState(() {
          partnerId = cachedUser['self']['id']?.toString();
          partnerName = cachedUser['self']['displayValue'];
          userApiData = cachedUser;
          userPermissions = List<Map<String, dynamic>>.from(
            cachedUser['permissions'] ?? [],
          );
          userZones = List<Map<String, dynamic>>.from(
            cachedUser['zones'] ?? [],
          );
          userRoles = List<Map<String, dynamic>>.from(
            cachedUser['roles'] ?? [],
          );
          isAdmin = _checkAdminPermissions();
        });

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
      }
      // تحديث في الخلفية بدون إعادة عرض التحميل
      _refreshCurrentUserInBackground();
      return;
    }

    // لا يوجد كاش — جلب من السيرفر مع إعادة محاولة
    await _fetchCurrentUserFromServer();
  }

  /// تحديث بيانات المستخدم من السيرفر في الخلفية (بدون تأثير على واجهة المستخدم)
  Future<void> _refreshCurrentUserInBackground() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://api.ftth.iq/api/current-user',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['model'] != null && data['model']['self'] != null) {
          final model = data['model'];
          // حفظ في الكاش
          FtthCacheService.saveCurrentUser(model);
          if (mounted) {
            setState(() {
              partnerId = model['self']['id']?.toString();
              partnerName = model['self']['displayValue'];
              userApiData = model;
              userPermissions = List<Map<String, dynamic>>.from(
                model['permissions'] ?? [],
              );
              userZones = List<Map<String, dynamic>>.from(model['zones'] ?? []);
              userRoles = List<Map<String, dynamic>>.from(model['roles'] ?? []);
              isAdmin = _checkAdminPermissions();
            });
          }
        }
      } else if (response.statusCode == 401) {
        _handle401Error();
      }
    } catch (e) {
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
      }
      // أخطاء أخرى تُتجاهل بصمت — لأن لدينا كاش يعمل
    }
  }

  /// جلب بيانات المستخدم من السيرفر (مع إعادة محاولة)
  Future<void> _fetchCurrentUserFromServer() async {
    // إضافة إعادة محاولة لتقليل الأخطاء المؤقتة (شبكة / استجابة بطيئة)
    const int maxRetries = 2; // الحد الأقصى للمحاولات
    int attempt = 0;
    Duration delay = const Duration(milliseconds: 300);
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
            final model = data['model'];
            // حفظ في الكاش للاستخدام عند العودة للصفحة
            FtthCacheService.saveCurrentUser(model);
            setState(() {
              partnerId = model['self']['id'];
              partnerName = model['self']['displayValue'];
              userApiData = model;
              userPermissions = List<Map<String, dynamic>>.from(
                model['permissions'] ?? [],
              );
              userZones = List<Map<String, dynamic>>.from(model['zones'] ?? []);
              userRoles = List<Map<String, dynamic>>.from(model['roles'] ?? []);
              isAdmin = _checkAdminPermissions();
            });

            partnerId = model['self']['id']?.toString();
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
    // V2: فحص صلاحية المستخدمين من PermissionManager
    if (PermissionManager.instance.canView('users')) {
      debugPrint('✅ مدير معتمد من V2 - صلاحية users: view=true');
      return true;
    }

    // فحص permissions للبحث عن "manager" أو "مدير"
    if (widget.permissions != null && widget.permissions!.isNotEmpty) {
      final perms = widget.permissions!.toLowerCase();
      if (perms.contains('manager') ||
          perms.contains('مدير') ||
          perms.contains('admin') ||
          perms.contains('administrator')) {
        debugPrint('✅ مدير معتمد من permissions: ${widget.permissions}');
        return true;
      }
    }

    // المعيار الثالث: صلاحيات النظام الأول
    if (widget.firstSystemPermissions != null &&
        widget.firstSystemPermissions!.isNotEmpty) {
      final permissionsToCheck = widget.firstSystemPermissions!.toLowerCase();
      if (permissionsToCheck.contains('مدير') ||
          permissionsToCheck.contains('admin') ||
          permissionsToCheck.contains('administrator')) {
        debugPrint(
            'مدير معتمد من النظام الأول: ${widget.firstSystemPermissions}');
        return true;
      }
    }

    debugPrint('مستخدم عادي - لم توجد صلاحيات مدير');
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
            '[CustomersRefresh] total=${c['totalCount']?.toString() ?? 'null'} active=${c['totalActive']?.toString() ?? 'null'} inactive=${c['totalInactive']?.toString() ?? 'null'}',
          );
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
      // إذا كان لدينا بيانات مخزنة → لا نُظهر الخطأ، نبقى على الكاش بصمت
      if (dashboardData.isEmpty) {
        showError("حدث خطأ أثناء جلب البيانات: $e");
      } else {
        debugPrint(
            '⚠️ [Dashboard] تعذر تحديث البيانات (${e.toString().split('\n').first}) - يُعرض الكاش');
      }
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
      await Future.wait([fetchDashboardData(), fetchWalletBalance()]);
      // تم تعطيل إشعار نجاح التحديث (تحديث بيانات) ليكون صامتاً
    } catch (e) {
      // التحقق من أن الخطأ ليس متعلقاً بانتهاء الجلسة
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
        return;
      }
      _showErrorMessage('فشل في تحديث البيانات: $e');
    } finally {
      if (mounted) {
        _refreshAnimationController.stop();
        setState(() {
          isRefreshing = false;
        });
      }
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
      if (mounted) {
        _refreshAnimationController.stop();
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
    // V2: استخدام PermissionManager كمصدر وحيد للصلاحيات
    final pm = PermissionManager.instance;
    if (!pm.isLoaded) {
      await pm.loadPermissions();
    }
    debugPrint(
        'تحميل الصلاحيات V2 - مدير النظام الأول: ${_isFirstSystemAdmin()}');
    debugPrint('اسم المستخدم: ${widget.username}');

    // تحويل صلاحيات V2 إلى صلاحيات الصفحة المحلية
    final permissions = <String, bool>{};
    for (var key in _defaultPermissions.keys) {
      permissions[key] = pm.canView(key);
      debugPrint('صلاحية $key: ${permissions[key]} (V2 canView)');
    }

    setState(() => _userPermissions = permissions);
    debugPrint('تم تحميل الصلاحيات النهائية: $_userPermissions');
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
                // تحميل كلمة المرور المحفوظة من PermissionService
                final savedPassword =
                    await PermissionService.getSecondSystemDefaultPassword();

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
                          'لم يتم تعيين كلمة مرور افتراضية بعد. يرجى تعيينها من صفحة الصلاحيات.',
                        ),
                        backgroundColor: Colors.orange,
                        duration: Duration(seconds: 3),
                      ),
                    );
                    Navigator.of(
                      context,
                    ).pop(true); // السماح بالدخول إذا لم تكن هناك كلمة مرور
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
                      IconsaxPlusLinear.lock,
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
                      prefixIcon: Icon(IconsaxPlusLinear.password_check),
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
                              ? IconsaxPlusLinear.eye
                              : IconsaxPlusLinear.eye_slash,
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
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Icon(IconsaxPlusBold.tick_circle),
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
    // V2: مصدر وحيد — PermissionManager
    return PermissionManager.instance.canView(permissionKey);
  }

  /// فحص صلاحية V2 بإجراء محدد
  /// مثال: _hasAction('users', 'add') → هل يمكن إضافة مستخدم؟
  bool _hasAction(String feature, String action) {
    return PermissionManager.instance.hasAction(feature, action);
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
        return 'حفظ في الخادم';
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
  bool hasServerSavePermission() {
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
            icon: Icon(IconsaxPlusBold.warning_2, color: Colors.red, size: 48),
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
                    '1. قم بتحميل وتثبيت Microsoft Edge WebView2 Runtime',
                  ),
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
            Colors.orange,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح رابط التحميل: $e');
      if (mounted) {
        showMessage(
          'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.',
          Colors.orange,
        );
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
                    title: const Text(
                      'واتساب ويب داخلي',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      'إرسال عبر نافذة واتساب ويب داخل التطبيق',
                      style: TextStyle(fontSize: 11),
                    ),
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
                    title: const Text(
                      'الإرسال التلقائي',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      'إرسال الرسالة تلقائياً بعد لصق النص (TAB×16 + Enter)',
                      style: TextStyle(fontSize: 11),
                    ),
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
                                'رسالة تجريبية من نظام الصفحة الرئيسية',
                              );
                              final url = 'https://wa.me/$val?text=$msg';
                              await launchUrl(
                                Uri.parse(url),
                                mode: LaunchMode.externalApplication,
                              );
                            } catch (e) {
                              if (mounted) {
                                showMessage('خطأ: $e', Colors.red);
                              }
                            } finally {
                              if (mounted) {
                                setState(
                                  () => _isGeneratingWhatsAppLink = false,
                                );
                              }
                            }
                          },
                    icon: _isGeneratingWhatsAppLink
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(IconsaxPlusLinear.message),
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
            icon: Icon(IconsaxPlusBold.directbox_send),
            label: const Text('حفظ'),
          ),
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
    // ⚡ إيقاف الأنيميشنات قبل الانتقال لتحرير الـ UI thread
    _cardAnimationController.stop();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (ctx, animation, secondaryAnimation) => page,
        // تقليل مدة الانتقال من 300ms إلى 180ms لتجربة أسرع على الهاتف
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) =>
            child,
      ),
    ).then((_) {
      // إعادة إظهار زر الواتساب العائم عند العودة من أي صفحة
      if (mounted) {
        _cardAnimationController.forward();
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
                child: Icon(
                  IconsaxPlusBold.user_square,
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
                  // معلومات النظام الأول إذا كانت متوفرة
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
                              Icon(
                                IconsaxPlusBold.chart,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'النظام الأول',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildInfoRow(
                            'اسم المستخدم',
                            widget.firstSystemUsername!,
                            IconsaxPlusLinear.user,
                          ),
                          _buildInfoRow(
                            'الصلاحيات',
                            widget.firstSystemPermissions ?? 'غير محدد',
                            IconsaxPlusLinear.shield_tick,
                          ),
                          _buildInfoRow(
                            'القسم',
                            widget.firstSystemDepartment ?? 'غير محدد',
                            IconsaxPlusLinear.building,
                          ),
                          _buildInfoRow(
                            'المركز',
                            widget.firstSystemCenter ?? 'غير محدد',
                            IconsaxPlusLinear.building_4,
                          ),
                          _buildInfoRow(
                            'الراتب',
                            widget.firstSystemSalary ?? 'غير محدد',
                            IconsaxPlusLinear.money_recive,
                          ),
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
                            Icon(
                              IconsaxPlusBold.global_search,
                              color: Colors.blue[700],
                            ),
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
                          IconsaxPlusLinear.user,
                        ),
                        _buildInfoRow(
                          'الاسم الكامل',
                          partnerName ?? 'غير محدد',
                          IconsaxPlusLinear.card,
                        ),
                        _buildCopyableInfoRow(
                          'معرف الشريك',
                          partnerId ?? 'غير محدد',
                          IconsaxPlusLinear.finger_scan,
                          partnerId ?? '',
                        ),
                        _buildInfoRow(
                          'البريد الإلكتروني',
                          userApiData['email'] ?? 'غير محدد',
                          IconsaxPlusLinear.sms,
                        ),
                        _buildInfoRow(
                          'حالة المدير',
                          isAdmin ? 'مدير' : 'مستخدم عادي',
                          IconsaxPlusLinear.security_user,
                        ),
                        _buildInfoRow(
                          'نوع الأعمال',
                          _getBusinessLineText(),
                          IconsaxPlusLinear.briefcase,
                        ),
                        _buildInfoRow(
                          'حالة التمثيل',
                          userApiData['impersonated'] == true ? 'نعم' : 'لا',
                          IconsaxPlusLinear.arrow_swap_horizontal,
                        ),
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
                              Icon(
                                IconsaxPlusBold.verify,
                                color: Colors.purple[700],
                              ),
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
                          ..._getImportantPermissions().map(
                            (perm) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    IconsaxPlusBold.tick_circle,
                                    size: 16,
                                    color: Colors.green,
                                  ),
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
                            ),
                          ),
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
                              Icon(
                                IconsaxPlusLinear.briefcase,
                                color: Colors.orange[700],
                              ),
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
                          ...userRoles.take(5).map(
                                (role) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Row(
                                    children: [
                                      Icon(
                                        IconsaxPlusBold.star_1,
                                        size: 16,
                                        color: Colors.orange[600],
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _translateRole(
                                            role['displayValue'] ?? '',
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[700],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
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
                              Icon(
                                IconsaxPlusBold.map,
                                color: Colors.teal[700],
                              ),
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
                                .map(
                                  (zone) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
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
                                  ),
                                )
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
                            Icon(
                              IconsaxPlusBold.setting_2,
                              color: Colors.indigo[700],
                            ),
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
                                      ? IconsaxPlusBold.tick_circle
                                      : IconsaxPlusBold.close_circle,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              child: const Text(
                'إغلاق',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
    String label,
    String value,
    IconData icon,
    String toCopy,
  ) {
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
                  icon: Icon(IconsaxPlusLinear.copy, size: 18),
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
      'Can Transfer',
      'Can Manual',
    ];

    return userPermissions
        .where(
          (perm) => importantKeywords.any(
            (keyword) => perm['displayValue']?.contains(keyword) == true,
          ),
        )
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
      'ContractorMember': 'عضو مقاول',
      'Can Manual Activate': 'تفعيل عادي',
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
      'uma_authorization': 'تفويض UMA',
    };

    return translations[role] ?? role;
  }

  // إظهار الأزرار العائمة عبر الشريط الموحد
  void _showGlobalWhatsAppButton() {
    try {
      // تفعيل زر واتساب ويب — دائماً ظاهر
      FloatingToolbar.enableWhatsApp();

      // التحقق من صلاحية إظهار زر المحادثات
      if (_hasPermission('whatsapp_conversations_fab')) {
        FloatingToolbar.enableConversations(isAdmin: isAdmin);
      } else {
        FloatingToolbar.disableConversations();
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في إظهار الأزرار العائمة: $e');
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
          // خلفية Aurora فاخرة داكنة مع كرات ضوئية متحركة
          // خلفية ثابتة (بدون أنيميشن)
          Builder(builder: (context) {
            final size = MediaQuery.of(context).size;
            return Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF5F6FA),
                        Color(0xFFEEF1F8),
                        Color(0xFFF0F4FF),
                        Color(0xFFF5F6FA),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: size.width * 0.1,
                  top: size.height * 0.05,
                  child: Container(
                    width: size.width * 0.7,
                    height: size.width * 0.7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x0F3498DB), Color(0x003498DB)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: size.width * 0.65,
                  top: size.height * 0.5,
                  child: Container(
                    width: size.width * 0.6,
                    height: size.width * 0.6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x0D1ABC9C), Color(0x001ABC9C)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: size.width * 0.35,
                  top: size.height * 0.75,
                  child: Container(
                    width: size.width * 0.5,
                    height: size.width * 0.5,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x0A9B59B6), Color(0x009B59B6)],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _InternetIconsBackgroundPainter(
                      animValue: 0,
                      color: const Color(0xFF3498DB).withValues(alpha: 0.07),
                    ),
                  ),
                ),
              ],
            );
          }),
          Scaffold(
            backgroundColor: Colors.transparent,
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
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD5D5D5), width: 2.0),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3498DB).withValues(alpha: 0.06),
                    blurRadius: 20,
                    spreadRadius: -3,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
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
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF3B82F6),
                      ),
                      backgroundColor: const Color(
                        0xFF3B82F6,
                      ).withValues(alpha: 0.2),
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
                            color: Color(0xFF1A1A1A),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          progress.message,
                          style: TextStyle(
                            color: const Color(0xFF555555),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${progress.percentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Color(0xFF93C5FD),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // زر الإلغاء
                  InkWell(
                    onTap: () => syncService.cancelSync(),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        IconsaxPlusBold.close_circle,
                        color: const Color(0xFFFCA5A5),
                        size: 16,
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
    bool isTablet,
    bool isSmallPhone,
    double screenWidth,
  ) {
    // ألوان فاخرة - تيل أخضر مع تدرج عصري
    final gradientColors = [
      const Color(0xFF2C3E50), // أساس (نمط الحسابات)
      const Color(0xFF34495E), // متوسط
      const Color(0xFF2C3E50), // عودة
    ];

    // أحجام متجاوبة للشريط العلوي
    final appBarHeight = isSmallPhone ? 56.0 : (isTablet ? 72.0 : 64.0);
    final leadingMargin = isSmallPhone ? 6.0 : 10.0;
    final leadingRadius = isSmallPhone ? 10.0 : 14.0;
    final actionMarginH = isSmallPhone ? 1.0 : 2.0;
    final actionRadius = isSmallPhone ? 10.0 : 14.0;
    final actionBorderW = isSmallPhone ? 1.5 : 2.0;
    final actionPadding = isSmallPhone ? 6.0 : (isTablet ? 10.0 : 8.0);
    final actionIconSize = isSmallPhone ? 20.0 : (isTablet ? 28.0 : 24.0);

    return AppBar(
      elevation: 0,
      toolbarHeight: appBarHeight,
      shadowColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      leading: Builder(
        builder: (BuildContext context) {
          return Container(
            margin: EdgeInsets.all(leadingMargin),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                  const Color(0xFF8B5CF6).withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(leadingRadius),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                width: actionBorderW,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: Icon(
                IconsaxPlusBold.menu_1,
                color: const Color(0xFFC4B5FD),
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
            colors: [
              const Color(0xFF2C3E50), // أساس
              const Color(0xFF34495E), // متوسط
              const Color(0xFF2C3E50), // عودة
              const Color(0xFF34495E), // تكرار
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2C3E50).withValues(alpha: 0.15),
              blurRadius: 30,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: const Color(0xFF2C3E50).withValues(alpha: 0.3),
              blurRadius: 40,
              spreadRadius: -5,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        // طبقة بريق شفافة فوق التدرج
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF3498DB).withValues(alpha: 0.05),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.05),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
      ),
      centerTitle: true,
      title: partnerName != null
          ? GestureDetector(
              onTap: _showUserInfoDialog,
              child: Container(
                constraints: BoxConstraints(maxWidth: screenWidth * 0.4),
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallPhone ? 8.0 : 10.0,
                  vertical: isSmallPhone ? 4.0 : 6.0,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF3B82F6).withValues(alpha: 0.18),
                      const Color(0xFF3B82F6).withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12.0),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      IconsaxPlusLinear.user,
                      color: Colors.white,
                      size: isSmallPhone ? 18.0 : (isTablet ? 20.0 : 19.0),
                    ),
                    SizedBox(width: isSmallPhone ? 4.0 : 6.0),
                    Flexible(
                      child: Text(
                        partnerName!,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize:
                              isSmallPhone ? 12.0 : (isTablet ? 14.0 : 13.0),
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(width: isSmallPhone ? 2.0 : 4.0),
                    Icon(
                      IconsaxPlusLinear.info_circle,
                      color: Colors.white.withValues(alpha: 0.7),
                      size: isSmallPhone ? 16.0 : (isTablet ? 18.0 : 17.0),
                    ),
                  ],
                ),
              ),
            )
          : Text(
              'لوحة التحكم',
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmallPhone ? 16.0 : (isTablet ? 20.0 : 18.0),
                fontWeight: FontWeight.bold,
              ),
            ),
      actions: [
        // ✅ زر العودة للوحة تحكم Super Admin
        if (widget.isSuperAdminMode)
          Container(
            margin: EdgeInsets.symmetric(horizontal: actionMarginH * 2),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(actionRadius - 2),
              border: Border.all(
                color: Colors.amber.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            child: IconButton(
              icon: Icon(
                IconsaxPlusBold.security_user,
                color: Colors.amber,
                size: actionIconSize,
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
        Container(
          margin: EdgeInsets.symmetric(horizontal: actionMarginH),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFFEC4899).withValues(alpha: 0.22),
                const Color(0xFFEC4899).withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(actionRadius),
            border: Border.all(
              color: const Color(0xFFEC4899).withValues(alpha: 0.45),
              width: actionBorderW,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEC4899).withValues(alpha: 0.15),
                blurRadius: isSmallPhone ? 6 : 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              IconsaxPlusBold.arrow_right_1,
              color: const Color(0xFFF9A8D4),
              size: actionIconSize,
            ),
            onPressed: () {
              Navigator.of(context).pop();
            },
            tooltip: 'رجوع',
            padding: EdgeInsets.all(actionPadding),
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: actionMarginH),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF10B981).withValues(alpha: 0.22),
                const Color(0xFF10B981).withValues(alpha: 0.08),
              ],
            ),
            borderRadius: BorderRadius.circular(actionRadius),
            border: Border.all(
              color: const Color(0xFF10B981).withValues(alpha: 0.45),
              width: actionBorderW,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                blurRadius: isSmallPhone ? 6 : 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _refreshAnimationController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _refreshAnimationController.value * 2 * 3.14159,
                child: IconButton(
                  icon: Icon(
                    IconsaxPlusBold.refresh,
                    color: const Color(0xFF6EE7B7),
                    size: actionIconSize + 2,
                  ),
                  onPressed: isRefreshing ? null : _manualFullRefresh,
                  tooltip: 'تحديث كامل',
                  padding: EdgeInsets.all(actionPadding),
                ),
              );
            },
          ),
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24.0)),
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
            colors: [Color(0xFFF5F6FA), Color(0xFFEEF1F8)],
            stops: [0.0, 1.0],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildDrawerHeader(isTablet, isSmallPhone),
            Container(
              color: const Color(0xFFF5F6FA),
              child: Column(
                children: [
                  // ============ الأزرار التالية تظهر فقط في الواجهة الرئيسية (الوصول السريع) ============
                  // البحث السريع، المشتركين، الاشتراكات، الانتهاء قريباً، المهام، سجلات الحسابات
                  // ==================================================================================

                  // ═══════════════════════════════════════════════════════════════════
                  // 📊 قسم البيانات والإدارة
                  // ═══════════════════════════════════════════════════════════════════

                  // 0 تقارير Superset (WebView)
                  if (_hasPermission('superset_reports'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.chart_21,
                      title: 'تقارير Superset',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.blue,
                      onTap: () => navigateToPage(const TestWebViewPage()),
                    ),

                  // 0.5 بيانات السيرفر (ملفات JSON المحلية)
                  if (_hasPermission('server_data'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.data,
                      title: 'بيانات السيرفر',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.indigo,
                      onTap: () => navigateToPage(
                        ServerDataPage(authToken: currentToken),
                      ),
                    ),

                  // 0.6 مشروع Dashboard (جلب بيانات الشارتات)
                  if (_hasPermission('dashboard_project'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.element_3,
                      title: 'مشروع Dashboard',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.deepPurple,
                      onTap: () => navigateToPage(
                        DashboardProjectPage(authToken: currentToken),
                      ),
                    ),

                  // 1 بيانات (تفاصيل الوكلاء + بيانات المستخدمين)
                  if (_hasPermission('agents'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.folder_open,
                      title: 'بيانات',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.deepPurple,
                      onTap: () =>
                          navigateToPage(DataPage(authToken: currentToken)),
                    ),

                  // 2 إدارة الزونات
                  if (_hasPermission('zones'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.location,
                      title: 'إدارة الزونات',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.teal,
                      onTap: () =>
                          navigateToPage(ZonesPage(authToken: currentToken)),
                    ),

                  // 3 سجل التدقيق
                  if (_hasPermission('audit_logs'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.clock,
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
                      icon: IconsaxPlusBold.export_1,
                      title: 'تصدير البيانات',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.brown,
                      onTap: () =>
                          navigateToPage(ExportPage(authToken: currentToken)),
                    ),

                  // ═══════════════════════════════════════════════════════════════════
                  // 💰 قسم المالية
                  // ═══════════════════════════════════════════════════════════════════

                  // 5 التحويلات
                  if (_hasPermission('transactions'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.wallet_2,
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
                      icon: IconsaxPlusBold.message,
                      title: 'محادثات WhatsApp',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.green,
                      onTap: () => navigateToPage(
                        WhatsAppConversationsPage(isAdmin: isAdmin),
                      ),
                    ),

                  // 7 إرسال رسائل جماعية (يحتوي على إعدادات API والتقارير)
                  if (_hasPermission('whatsapp_bulk_sender'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.send_2,
                      title: 'إرسال رسائل جماعية',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.teal,
                      onTap: () =>
                          navigateToPage(const WhatsAppBulkSenderPage()),
                    ),

                  // 8 قوالب الرسائل
                  _buildDrawerItem(
                    icon: IconsaxPlusBold.document_text,
                    title: 'قوالب الرسائل',
                    isTablet: isTablet,
                    isSmallPhone: isSmallPhone,
                    color: Colors.deepPurple,
                    onTap: () => navigateToPage(const WhatsAppTemplatesPage()),
                  ),

                  // 9 إعدادات الواتساب
                  _buildDrawerItem(
                    icon: IconsaxPlusBold.setting_2,
                    title: 'إعدادات الواتساب',
                    isTablet: isTablet,
                    isSmallPhone: isSmallPhone,
                    color: Colors.green,
                    onTap: _openWhatsAppSettingsDialog,
                  ),

                  // 10 مركز إعدادات الواتساب (السيرفر، API، ويب)
                  if (_hasPermission('whatsapp_settings'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.mobile,
                      title: 'مركز الواتساب',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.green,
                      onTap: () =>
                          navigateToPage(const WhatsAppSettingsHubPage()),
                    ),

                  // ═══════════════════════════════════════════════════════════════════
                  // 🔧 قسم الخدمات
                  // ═══════════════════════════════════════════════════════════════════

                  // 10 فني التوصيل
                  if (_hasPermission('technicians'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.user_octagon,
                      title: 'فني التوصيل',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.blueGrey,
                      onTap: () => navigateToPage(const TechniciansPage()),
                    ),

                  // 11 التخزين الداخلي
                  if (_hasPermission('local_storage'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.box_1,
                      title: 'التخزين الداخلي',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.cyan,
                      onTap: () => navigateToPage(
                        LocalStoragePage(authToken: currentToken),
                      ),
                    ),

                  // 12 جلب بيانات الموقع
                  if (_hasPermission('fetch_server_data'))
                    _buildDrawerItem(
                      icon: IconsaxPlusBold.cloud_connection,
                      title: 'جلب بيانات الموقع',
                      isTablet: isTablet,
                      isSmallPhone: isSmallPhone,
                      color: Colors.teal,
                      onTap: () => navigateToPage(const FetchServerDataPage()),
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
                      !_hasPermission('local_storage') &&
                      !_hasPermission('superset_reports') &&
                      !_hasPermission('server_data') &&
                      !_hasPermission('dashboard_project') &&
                      !_hasPermission('fetch_server_data'))
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
                            IconsaxPlusLinear.lock,
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
      padding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: isSmallPhone ? 8 : 12,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2C3E50), Color(0xFF34495E), Color(0xFF2C3E50)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2C3E50).withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Stack(
        children: [
          // طبقة بريق شفافة
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFF59E0B).withValues(alpha: 0.06),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.2),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // أيقونة فخمة متوهجة
                Container(
                  padding: EdgeInsets.all(isSmallPhone ? 6 : 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        const Color(0xFFF59E0B).withValues(alpha: 0.3),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.55),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    IconsaxPlusBold.shield_tick,
                    color: const Color(0xFFFCD34D),
                    size: isSmallPhone ? 18 : 26,
                  ),
                ),
                SizedBox(height: isSmallPhone ? 4 : 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'القائمة الرئيسية',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isSmallPhone ? 13 : (isTablet ? 18 : 16),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
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
    final double boxSize = ((isSmallPhone ? 40 : baseBox * scale).clamp(
      36,
      52,
    )).toDouble();
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD5D5D5), width: 2.0),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            spreadRadius: -2,
            blurRadius: 12,
            offset: const Offset(0, 4),
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
              colors: [
                color.shade300.withValues(alpha: 0.12),
                color.shade500.withValues(alpha: 0.25),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.shade400.withValues(alpha: 0.55),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: color.shade400.withValues(alpha: 0.2),
                blurRadius: 14,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: color.shade300.withValues(alpha: 0.08),
                blurRadius: 24,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Icon(
            icon,
            size: iconSize.clamp(16, 26).toDouble(),
            color: color.shade300,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: titleFont.clamp(11, 15).toDouble(),
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1A1A1A),
            height: 1.15,
          ),
        ),
        trailing: Icon(
          IconsaxPlusBold.arrow_left_2,
          size: trailingSize.clamp(14, 20).toDouble(),
          color: const Color(0xFF555555),
        ),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          // حلقة تحميل فخمة - ثيم داكن
          Container(
            padding: const EdgeInsets.all(35),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFD5D5D5), width: 2.0),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3498DB).withValues(alpha: 0.06),
                  blurRadius: 40,
                  spreadRadius: -5,
                  offset: const Offset(0, 15),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 60,
                  spreadRadius: -10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // حلقة خارجية كبيرة - أزرق فاتح
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFF3498DB).withValues(alpha: 0.25),
                    ),
                  ),
                ),
                // حلقة وسطى - أزرق
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFF3498DB).withValues(alpha: 0.5),
                    ),
                  ),
                ),
                // حلقة داخلية أساسية - أزرق
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF3498DB),
                    ),
                  ),
                ),
                // أيقونة في المنتصف مع توهج
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Icon(
                    IconsaxPlusBold.verify,
                    color: const Color(0xFFFCD34D),
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          // نص التحميل
          Text(
            'جاري تحميل البيانات...',
            style: TextStyle(
              fontSize: isLargeScreen ? 18 : 16,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A1A),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'يرجى الانتظار لحظات',
            style: TextStyle(
              fontSize: isLargeScreen ? 14 : 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF555555),
              letterSpacing: 0.3,
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
            // المحتوى القابل للتمرير
            SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: isLargeScreen ? 28 : 16,
                vertical: isLargeScreen ? 16 : 10,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // بطاقة العملاء الحديثة في الأعلى فقط
                      _buildTopStatsRow(isLargeScreen),
                      const SizedBox(height: 12),
                      // كروت المحفظة في الأعلى (للمديرين فقط أو المصرح لهم)
                      if (hasWalletBalancePermission())
                        _buildWalletCards(isLargeScreen),

                      if (hasWalletBalancePermission())
                        const SizedBox(height: 10),

                      // بطاقة محفظة عضو الفريق تظهر دائماً إذا كانت المحفظة متوفرة حتى بدون صلاحية المحفظة العامة
                      if (!hasWalletBalancePermission() &&
                          hasTeamMemberWallet) ...[
                        _buildTeamMemberWalletCard(),
                        const SizedBox(height: 10),
                      ],

                      // شريط الأدوات السريعة المحدث
                      _buildQuickActionsBar(isLargeScreen, screenWidth),
                      const SizedBox(
                        height: 80,
                      ), // مسافة سفلية حتى لا يغطيها شريط "آخر تحديث"
                    ],
                  ),
                ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
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

  // صف علوي عصري لبطاقة العملاء فقط
  Widget _buildTopStatsRow(bool isLargeScreen) {
    return Row(children: [Expanded(child: _buildCustomersCard())]);
  }

  // بطاقة مخصصة لعرض العملاء بشكل حديث ونظيف
  Widget _buildCustomersCard() {
    final total = (dashboardData['customers']?['totalCount'] ?? 0) as int;
    final active = (dashboardData['customers']?['totalActive'] ?? 0) as int;
    final inactive = (dashboardData['customers']?['totalInactive'] ?? 0) as int;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    // فاصل بين البطاقات يتأقلم مع حجم الشاشة
    final gap = screenWidth < 360 ? 6.0 : (screenWidth < 420 ? 8.0 : 12.0);

    return Row(
      children: [
        Expanded(
          child: _buildCleanStatCard(
            label: 'إجمالي العملاء',
            value: total,
            icon: IconsaxPlusBold.people,
            color: const Color(0xFF2563EB),
            changeText: '100%',
            isPositive: true,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: _buildCleanStatCard(
            label: 'نشط',
            value: active,
            icon: IconsaxPlusBold.tick_circle,
            color: const Color(0xFF059669),
            changeText: total > 0
                ? '${(active / total * 100).toStringAsFixed(1)}%'
                : '0%',
            isPositive: true,
          ),
        ),
        SizedBox(width: gap),
        Expanded(
          child: _buildCleanStatCard(
            label: 'منتهي',
            value: inactive,
            icon: IconsaxPlusBold.close_circle,
            color: const Color(0xFFDC2626),
            changeText: total > 0
                ? '${(inactive / total * 100).toStringAsFixed(1)}%'
                : '0%',
            isPositive: false,
          ),
        ),
      ],
    );
  }

  // بطاقة إحصائية دائرية (Donut) مع عداد متحرك وتأثيرات hover
  Widget _buildCleanStatCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required String changeText,
    required bool isPositive,
  }) {
    // استخراج النسبة المئوية من changeText (مثل "75.5%" → 0.755)
    double percent = 1.0;
    final parsed = double.tryParse(changeText.replaceAll('%', '').trim());
    if (parsed != null) percent = (parsed / 100.0).clamp(0.0, 1.0);

    final hoverNotifier = ValueNotifier<bool>(false);

    // ألوان التدرج لكل بطاقة
    final Color glowColor1 = color;
    final Color glowColor2 = HSLColor.fromColor(
      color,
    ).withHue((HSLColor.fromColor(color).hue + 40) % 360).toColor();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        // أحجام متجاوبة حسب عرض البطاقة المتاح
        final circleSize = (cardWidth * 0.72).clamp(60.0, 90.0);
        final valueFontSize = (cardWidth * 0.14).clamp(12.0, 17.0);
        final pctFontSize = (cardWidth * 0.08).clamp(7.0, 9.0);
        final labelFontSize = (cardWidth * 0.09).clamp(8.0, 10.0);
        final iconSize = (cardWidth * 0.1).clamp(9.0, 12.0);
        final vPad = cardWidth < 100 ? 8.0 : (cardWidth < 120 ? 10.0 : 14.0);
        final hPad = cardWidth < 100 ? 6.0 : (cardWidth < 120 ? 8.0 : 10.0);

        return ValueListenableBuilder<bool>(
          valueListenable: hoverNotifier,
          builder: (context, isHovered, child) {
            return MouseRegion(
              onEnter: (_) => hoverNotifier.value = true,
              onExit: (_) => hoverNotifier.value = false,
              child: AnimatedScale(
                scale: isHovered ? 1.03 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  padding:
                      EdgeInsets.symmetric(vertical: vPad, horizontal: hPad),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(cardWidth < 100 ? 12 : 18),
                    border: Border.all(
                      color: isHovered
                          ? color.withValues(alpha: 0.35)
                          : const Color(0xFFE0E0E0),
                      width: isHovered ? 2.5 : 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isHovered
                            ? color.withValues(alpha: 0.12)
                            : Colors.black.withValues(alpha: 0.04),
                        blurRadius: isHovered ? 16 : 6,
                        spreadRadius: isHovered ? -1 : -2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // دائرة الأمواج الشعاعية — التصميم المستقبلي
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: percent),
                        duration: const Duration(milliseconds: 1600),
                        curve: Curves.easeOutCubic,
                        builder: (context, animPercent, _) {
                          return AnimatedBuilder(
                            animation: _counterAnimationController,
                            builder: (context, child) {
                              final curvedVal = Curves.easeOutExpo.transform(
                                _counterAnimationController.value,
                              );
                              final displayValue = (value * curvedVal).round();
                              return SizedBox(
                                width: circleSize,
                                height: circleSize,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CustomPaint(
                                      size: Size.square(circleSize),
                                      painter: _RadialWavePainter(
                                        progress: animPercent,
                                        color1: glowColor1,
                                        color2: glowColor2,
                                        animValue: 0,
                                      ),
                                    ),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            _formatCounterNumber(displayValue),
                                            style: TextStyle(
                                              fontSize: valueFontSize,
                                              fontWeight: FontWeight.w900,
                                              color: const Color(0xFF1A1A1A),
                                              letterSpacing: -0.3,
                                              height: 1.0,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          changeText,
                                          style: TextStyle(
                                            fontSize: pctFontSize,
                                            fontWeight: FontWeight.w700,
                                            color: color,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                      SizedBox(height: cardWidth < 100 ? 4 : 8),
                      // أيقونة + تسمية
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: color, size: iconSize),
                          SizedBox(width: cardWidth < 100 ? 2 : 4),
                          Flexible(
                            child: Text(
                              label,
                              style: TextStyle(
                                color: const Color(0xFF1A1A1A),
                                fontSize: labelFontSize,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // تنسيق رقم العداد مع فواصل الآلاف
  String _formatCounterNumber(int number) {
    if (number < 1000) return number.toString();
    final str = number.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) buffer.write(',');
    }
    return buffer.toString().split('').reversed.join('');
  }

  // نقاط الزوايا الزخرفية المتحركة
  List<Widget> _buildAnimatedCornerDots(Color color, bool isHovered) {
    final positions = [
      {'top': 6.0, 'left': 6.0},
      {'top': 6.0, 'right': 6.0},
      {'bottom': 6.0, 'left': 6.0},
      {'bottom': 6.0, 'right': 6.0},
    ];

    return positions.map((pos) {
      return Positioned(
        top: pos.containsKey('top') ? pos['top'] : null,
        bottom: pos.containsKey('bottom') ? pos['bottom'] : null,
        left: pos.containsKey('left') ? pos['left'] : null,
        right: pos.containsKey('right') ? pos['right'] : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          width: isHovered ? 7 : 5,
          height: isHovered ? 7 : 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: isHovered ? 0.8 : 0.45),
            boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 0,
                    ),
                  ]
                : [],
          ),
        ),
      );
    }).toList();
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
        // حاوية خارجية مع ظلال - ثيم فاتح
        Container(
          width: size + 8,
          height: size + 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: const Color(0xFFD5D5D5), width: 2.0),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3498DB).withValues(alpha: 0.06),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
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
                            color: const Color(0xFF1A1A1A),
                            shadows: [
                              Shadow(
                                color: const Color(
                                  0xFF3498DB,
                                ).withValues(alpha: 0.1),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF3498DB,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            percent >= 1.0 && label == 'الكلي'
                                ? '100%'
                                : '%$pctText',
                            style: TextStyle(
                              fontSize: pctFont,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF3498DB),
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
        // العنوان مع تصميم فاتح
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF3498DB).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8E8E8), width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF3498DB),
            ),
          ),
        ),
      ],
    );
  }

  // شريط الأد��ات السريعة المحدث
  Widget _buildQuickActionsBar(bool isLargeScreen, double screenWidth) {
    // تحديد عدد الأعمدة حسب حجم الشاشة - تصميم أفقي
    int crossAxisCount;
    double childAspectRatio;

    if (screenWidth < 320) {
      crossAxisCount = 1;
      childAspectRatio = 3.5;
    } else if (screenWidth < 380) {
      crossAxisCount = 1;
      childAspectRatio = 3.8;
    } else if (screenWidth < 500) {
      crossAxisCount = 2;
      childAspectRatio = 2.8;
    } else if (screenWidth < 600) {
      crossAxisCount = 2;
      childAspectRatio = 3.0;
    } else {
      crossAxisCount = 3;
      childAspectRatio = 3.2;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // فاصل فاخر مزخرف بأيقونة
        Container(
          margin: EdgeInsets.symmetric(
            horizontal: screenWidth < 380 ? 16 : 32,
            vertical: screenWidth < 380 ? 6 : 8,
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 1.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        const Color(0xFF3498DB).withValues(alpha: 0.3),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3498DB).withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF3498DB).withValues(alpha: 0.2),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3498DB).withValues(alpha: 0.1),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: Icon(
                  IconsaxPlusBold.element_2,
                  size: 16,
                  color: const Color(0xFF3498DB),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1.5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF3498DB).withValues(alpha: 0.3),
                        Colors.transparent,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: screenWidth < 380 ? 6 : 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          mainAxisSpacing: screenWidth < 380 ? 6 : 8,
          crossAxisSpacing: screenWidth < 380 ? 6 : 8,
          children: _buildQuickActionItems(screenWidth),
        ),
      ],
    );
  }

  List<Widget> _buildQuickActionItems(double screenWidth) {
    final actions = <Widget>[];

    // البحث السريع - يخضع لصلاحية quick_search
    if (_hasPermission('quick_search')) {
      actions.add(
        _buildQuickActionItem(
          'البحث السريع',
          IconsaxPlusBold.search_normal_1,
          Colors.green,
          () => navigateToPage(
            QuickSearchUsersPage(
              authToken: currentToken,
              activatedBy: widget.username,
              hasServerSavePermission: hasServerSavePermission(),
              hasWhatsAppPermission: hasWhatsAppPermission(),
              firstSystemPermissions: widget.firstSystemPermissions,
              isAdminFlag: isAdmin,
              importantFtthApiPermissions: _getImportantPermissions(),
            ),
          ),
        ),
      );
    }

    // المشتركين - أداة سريعة (تم تقديمها مكان الانتهاء قريباً)
    if (_hasPermission('users')) {
      actions.add(
        _buildQuickActionItem(
          'المشتركين',
          IconsaxPlusBold.profile_2user,
          Colors.purple,
          () => navigateToPage(
            UsersPage(
              authToken: currentToken,
              activatedBy: widget.username,
              hasServerSavePermission: hasServerSavePermission(),
              hasWhatsAppPermission: hasWhatsAppPermission(),
              firstSystemPermissions: widget.firstSystemPermissions,
              isAdminFlag: isAdmin,
              importantFtthApiPermissions: _getImportantPermissions(),
            ),
          ),
        ),
      );
    }

    // الاشتراكات - أداة سريعة
    if (_hasPermission('subscriptions')) {
      actions.add(
        _buildQuickActionItem(
          'الاشتراكات',
          IconsaxPlusBold.receipt_2,
          Colors.blue,
          () => navigateToPage(SubscriptionsPage(authToken: currentToken)),
        ),
      );
    }

    // الاشتراكات المنتهية قريباً - يخضع لصلاحية expiring_soon
    if (_hasPermission('expiring_soon')) {
      actions.add(
        _buildQuickActionItem(
          'الانتهاء قريباً',
          IconsaxPlusBold.timer_1,
          Colors.red,
          () => navigateToPage(
            ExpiringSoonPage(
              activatedBy: widget.username,
              hasServerSavePermission: hasServerSavePermission(),
              hasWhatsAppPermission: hasWhatsAppPermission(),
              firstSystemPermissions: widget.firstSystemPermissions,
              importantFtthApiPermissions: _getImportantPermissions(),
            ),
          ),
        ),
      );
    }

    // المهام - أداة سريعة
    if (_hasPermission('tasks')) {
      actions.add(_buildTasksActionItem());
    }

    // سجلات الحسابات - أداة سريعة (صلاحية مستقلة account_records)
    if (_hasPermission('account_records')) {
      actions.add(
        _buildQuickActionItem(
          'سجلات الحسابات',
          IconsaxPlusBold.document_text,
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
        ),
      );
    }

    return actions;
  }

  Widget _buildQuickActionItem(
    String title,
    IconData icon,
    MaterialColor color,
    VoidCallback onTap,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;

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
      maxLines = 2;
    } else {
      iconSize = 32;
      fontSize = 16;
      padding = 16;
      verticalSpacing = 8;
      maxLines = 2;
    }

    final circleSize = iconSize + 22;
    final hoverNotifier = ValueNotifier<bool>(false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellHeight = constraints.maxHeight;
        final effectiveHeight = cellHeight.isFinite && cellHeight > 0
            ? cellHeight
            : (padding * 6 + iconSize);

        return SizedBox(
          height: effectiveHeight,
          width: double.infinity,
          child: ValueListenableBuilder<bool>(
            valueListenable: hoverNotifier,
            builder: (context, isHovered, _) {
              return MouseRegion(
                onEnter: (_) => hoverNotifier.value = true,
                onExit: (_) => hoverNotifier.value = false,
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    if (mounted) onTap();
                  },
                  child: AnimatedScale(
                    scale: isHovered ? 1.045 : 1.0,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isHovered
                              ? [
                                  Color.lerp(Colors.white, color, 0.08)!,
                                  Color.lerp(
                                    const Color(0xFFF5F6FA),
                                    color,
                                    0.10,
                                  )!,
                                ]
                              : [Colors.white, const Color(0xFFF5F6FA)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isHovered
                              ? color.withValues(alpha: 0.35)
                              : const Color(0xFFE0E0E0),
                          width: isHovered ? 2.8 : 2.0,
                        ),
                        boxShadow: isHovered
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.15),
                                  blurRadius: 20,
                                  spreadRadius: -4,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 20,
                                  spreadRadius: -8,
                                  offset: const Offset(0, 16),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Stack(
                          children: [
                            // توهج خلفي متحرك عند المرور
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutCubic,
                              right: isHovered ? -10 : -70,
                              top: isHovered ? -10 : -70,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 400),
                                opacity: isHovered ? 1.0 : 0.0,
                                child: Container(
                                  width: circleSize * 3,
                                  height: circleSize * 3,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        color.withValues(alpha: 0.12),
                                        color.withValues(alpha: 0.04),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.45, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // توهج سفلي
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 600),
                              curve: Curves.easeOutCubic,
                              left: isHovered ? -20 : -80,
                              bottom: isHovered ? -20 : -80,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 400),
                                opacity: isHovered ? 0.7 : 0.0,
                                child: Container(
                                  width: circleSize * 2,
                                  height: circleSize * 2,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        color.withValues(alpha: 0.08),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // شريط ملون جانبي أيمن متحرك
                            Positioned(
                              top: 0,
                              bottom: 0,
                              right: 0,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 380),
                                curve: Curves.easeOutCubic,
                                width: isHovered ? 6 : 4,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: isHovered
                                        ? [
                                            color.shade200,
                                            color.shade500,
                                            color.shade200,
                                          ]
                                        : [
                                            color.withValues(alpha: 0.3),
                                            color,
                                            color.withValues(alpha: 0.3),
                                          ],
                                  ),
                                  boxShadow: isHovered
                                      ? [
                                          BoxShadow(
                                            color: color.withValues(
                                              alpha: 0.55,
                                            ),
                                            blurRadius: 14,
                                            spreadRadius: -1,
                                          ),
                                        ]
                                      : [],
                                ),
                              ),
                            ),
                            // المحتوى الرئيسي
                            Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: padding,
                                vertical: verticalSpacing,
                              ),
                              child: Row(
                                children: [
                                  // الأيقونة الملونة مع تأثيرات
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 380),
                                    curve: Curves.easeOutCubic,
                                    width:
                                        isHovered ? circleSize + 6 : circleSize,
                                    height:
                                        isHovered ? circleSize + 6 : circleSize,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: isHovered
                                            ? [color.shade300, color.shade800]
                                            : [color.shade400, color.shade700],
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withValues(
                                            alpha: isHovered ? 0.6 : 0.3,
                                          ),
                                          blurRadius: isHovered ? 22 : 10,
                                          spreadRadius: isHovered ? 0 : -2,
                                          offset: const Offset(0, 4),
                                        ),
                                        if (isHovered)
                                          BoxShadow(
                                            color: color.withValues(alpha: 0.2),
                                            blurRadius: 32,
                                            spreadRadius: -4,
                                          ),
                                      ],
                                    ),
                                    alignment: Alignment.center,
                                    child: AnimatedRotation(
                                      turns: isHovered ? 0.04 : 0.0,
                                      duration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      child: Icon(
                                        icon,
                                        size: iconSize,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: padding * 0.6),
                                  // النص مع تأثير متحرك
                                  Expanded(
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      curve: Curves.easeOut,
                                      style: TextStyle(
                                        fontSize: isHovered
                                            ? fontSize + 0.5
                                            : fontSize,
                                        fontWeight: isHovered
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                        color: isHovered
                                            ? color.shade700
                                            : const Color(0xFF1A1A1A),
                                        height: 1.2,
                                        letterSpacing: isHovered ? 0.4 : 0.2,
                                      ),
                                      child: Text(
                                        title,
                                        maxLines: maxLines,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: padding * 0.3),
                                  // سهم التنقل متحرك
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 380),
                                    curve: Curves.easeOutCubic,
                                    width: isHovered ? 36 : 28,
                                    height: isHovered ? 36 : 28,
                                    decoration: BoxDecoration(
                                      gradient: isHovered
                                          ? LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                color.shade400,
                                                color.shade700,
                                              ],
                                            )
                                          : null,
                                      color: isHovered
                                          ? null
                                          : color.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                      boxShadow: isHovered
                                          ? [
                                              BoxShadow(
                                                color: color.withValues(
                                                  alpha: 0.4,
                                                ),
                                                blurRadius: 12,
                                                spreadRadius: -2,
                                              ),
                                            ]
                                          : [],
                                    ),
                                    alignment: Alignment.center,
                                    child: AnimatedSlide(
                                      duration: const Duration(
                                        milliseconds: 350,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      offset: isHovered
                                          ? const Offset(-0.2, 0)
                                          : Offset.zero,
                                      child: Icon(
                                        IconsaxPlusLinear.arrow_left_2,
                                        size: isHovered ? 16 : 14,
                                        color: isHovered
                                            ? Colors.white
                                            : color.shade600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
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
          IconsaxPlusBold.task_square,
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
                          horizontal: 6,
                          vertical: 3,
                        ),
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
      const SizedBox(width: 12),
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
      cards.add(const SizedBox(width: 12));
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
    // تصميم أفقي متناسق مع بطاقات الإحصائيات
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        // أحجام متجاوبة مع عرض البطاقة
        final isVeryCompact = cardWidth < 160;
        final isCompact = cardWidth < 240;
        final iconBoxSize = isVeryCompact ? 34.0 : (isCompact ? 40.0 : 52.0);
        final iconSize = isVeryCompact ? 18.0 : (isCompact ? 20.0 : 26.0);
        final valueFontSize = isVeryCompact ? 14.0 : (isCompact ? 17.0 : 24.0);
        final titleFontSize = isVeryCompact ? 9.0 : (isCompact ? 10.0 : 12.0);
        final hPadding = isVeryCompact ? 8.0 : (isCompact ? 12.0 : 18.0);
        final vPadding = isVeryCompact ? 10.0 : (isCompact ? 12.0 : 16.0);
        final stripHeight = isVeryCompact ? 36.0 : (isCompact ? 44.0 : 56.0);
        final cardRadius = isVeryCompact ? 12.0 : 18.0;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(cardRadius),
            border: Border.all(
                color: const Color(0xFFD5D5D5),
                width: isVeryCompact ? 1.5 : 2.0),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 20,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(cardRadius),
            child: Stack(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: hPadding,
                    vertical: vPadding,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(cardRadius),
                  ),
                  child: Row(
                    children: [
                      // شريط تدرجي جانبي بلون البطاقة
                      Container(
                        width: isVeryCompact ? 2.5 : 3.5,
                        height: stripHeight,
                        margin: EdgeInsets.only(left: isVeryCompact ? 4 : 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              color.withValues(alpha: 0.4),
                              color,
                              color.withValues(alpha: 0.4),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.4),
                              blurRadius: 6,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: isVeryCompact ? 6 : 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                title,
                                style: TextStyle(
                                  color: const Color(0xFF555555),
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            SizedBox(height: isVeryCompact ? 4 : 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _animatedCount(
                                value,
                                TextStyle(
                                  color: const Color(0xFF1A1A1A),
                                  fontSize: valueFontSize,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // أيقونة بلون البطاقة
                      Container(
                        width: iconBoxSize,
                        height: iconBoxSize,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              color.withValues(alpha: 0.08),
                              color.withValues(alpha: 0.2),
                            ],
                          ),
                          borderRadius:
                              BorderRadius.circular(isVeryCompact ? 10 : 14),
                          border: Border.all(
                            color: color.withValues(alpha: 0.4),
                            width: isVeryCompact ? 1.5 : 2.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.25),
                              blurRadius: 12,
                              spreadRadius: -2,
                              offset: const Offset(0, 4),
                            ),
                            BoxShadow(
                              color: color.withValues(alpha: 0.1),
                              blurRadius: 20,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: Icon(
                          title.contains('عمولة')
                              ? IconsaxPlusBold.trend_up
                              : title.contains('فريق')
                                  ? IconsaxPlusBold.people
                                  : IconsaxPlusBold.wallet_2,
                          color: color,
                          size: iconSize,
                        ),
                      ),
                    ],
                  ),
                ),
                // نقاط زوايا زخرفية
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLastUpdateInfo(bool isLargeScreen) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 14.0),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD5D5D5), width: 2.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
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
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(
              IconsaxPlusBold.clock,
              color: const Color(0xFF6EE7B7),
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'آخر تحديث: ${DateFormat('yyyy/MM/dd - HH:mm:ss').format(lastUpdateTime!)}',
            style: TextStyle(
              fontSize: isLargeScreen ? 13 : 11,
              color: const Color(0xFF1A1A1A),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// رسام أمواج شعاعية مستقبلي — خطوط/أشواك تشع من دائرة بأطوال متفاوتة
class _RadialWavePainter extends CustomPainter {
  final double progress; // 0..1
  final Color color1;
  final Color color2;
  final double animValue; // 0..1 لتحريك الأمواج

  _RadialWavePainter({
    required this.progress,
    required this.color1,
    required this.color2,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2;
    final innerRadius = outerRadius * 0.52; // نصف قطر الدائرة الداخلية
    final spikeCount = 72; // عدد الأشواك

    // رسم الدائرة الداخلية البيضاء
    final innerCirclePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius + 2, innerCirclePaint);

    // حلقة داخلية خفيفة
    final innerRingPaint = Paint()
      ..color = color1.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, innerRadius, innerRingPaint);

    // رسم الأشواك الشعاعية
    for (int i = 0; i < spikeCount; i++) {
      final angle = (i / spikeCount) * 2 * math.pi - math.pi / 2;
      final spikeProgress = i / spikeCount;

      // موجة متعددة الطبقات لتنويع أطول الأشواك
      final wave1 =
          math.sin(spikeProgress * math.pi * 6 + animValue * math.pi * 2) * 0.4;
      final wave2 =
          math.sin(spikeProgress * math.pi * 10 + animValue * math.pi * 3) *
              0.25;
      final wave3 =
          math.cos(spikeProgress * math.pi * 14 + animValue * math.pi * 1.5) *
              0.15;
      final waveHeight =
          0.3 + (wave1 + wave2 + wave3 + 0.8).clamp(0.0, 1.0) * 0.7;

      // الطول الأقصى للشوكة
      final maxSpikeLen = (outerRadius - innerRadius - 2) * waveHeight;

      // حساب نقاط البداية والنهاية
      final startX = center.dx + (innerRadius + 2) * math.cos(angle);
      final startY = center.dy + (innerRadius + 2) * math.sin(angle);
      final start = Offset(startX, startY);

      // تحديد إذا كانت الشوكة في المنطقة النشطة
      final isActive = spikeProgress <= progress;

      if (isActive) {
        // شوكة نشطة — ملونة بتدرج
        final t = spikeProgress; // 0..1 على مدار الدائرة
        final spikeColor = Color.lerp(color1, color2, t)!;

        final endX = startX + maxSpikeLen * math.cos(angle);
        final endY = startY + maxSpikeLen * math.sin(angle);
        final end = Offset(endX, endY);

        // هالة خفيفة حول الأشواك النشطة
        final glowPaint = Paint()
          ..color = spikeColor.withValues(alpha: 0.15)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawLine(start, end, glowPaint);

        // الشوكة الرئيسية
        final spikePaint = Paint()
          ..color = spikeColor.withValues(alpha: 0.85)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(start, end, spikePaint);

        // نقطة مضيئة في نهاية الأشواك الطويلة
        if (waveHeight > 0.65) {
          final tipPaint = Paint()
            ..color = spikeColor.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
          canvas.drawCircle(end, 1.2, tipPaint);
        }
      } else {
        // شوكة غير نشطة — خافتة
        final dimLen = maxSpikeLen * 0.3;
        final endX = startX + dimLen * math.cos(angle);
        final endY = startY + dimLen * math.sin(angle);
        final end = Offset(endX, endY);

        final dimPaint = Paint()
          ..color = color1.withValues(alpha: 0.10)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(start, end, dimPaint);
      }
    }

    // هالة ملونة خارجية خفيفة عند التقدم
    if (progress > 0.01) {
      final glowAngle = progress * 2 * math.pi;
      final glowPaint = Paint()
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: -math.pi / 2 + 2 * math.pi,
          colors: [
            color1.withValues(alpha: 0.0),
            color1.withValues(alpha: 0.08),
            color2.withValues(alpha: 0.12),
            color2.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.3, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: outerRadius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = outerRadius - innerRadius
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      canvas.drawArc(
        Rect.fromCircle(
          center: center,
          radius: (outerRadius + innerRadius) / 2,
        ),
        -math.pi / 2,
        glowAngle,
        false,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadialWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color1 != color1 ||
        oldDelegate.color2 != color2 ||
        oldDelegate.animValue != animValue;
  }
}

// رسام خلفية رموز الإنترنت المتحركة (واي فاي، إشارة، سحابة، كرة أرضية، راوتر...)
class _InternetIconsBackgroundPainter extends CustomPainter {
  final double animValue; // 0..1
  final Color color;

  _InternetIconsBackgroundPainter({
    required this.animValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    // مواقع الرموز على الشاشة بشكل عشوائي ثابت
    final icons = <_IconDef>[
      // WiFi symbols
      _IconDef(0.08, 0.12, 0, 18),
      _IconDef(0.85, 0.08, 0, 14),
      _IconDef(0.45, 0.88, 0, 16),
      _IconDef(0.92, 0.55, 0, 12),
      _IconDef(0.15, 0.72, 0, 15),
      // Globe symbols
      _IconDef(0.72, 0.18, 1, 16),
      _IconDef(0.25, 0.42, 1, 13),
      _IconDef(0.60, 0.65, 1, 14),
      _IconDef(0.05, 0.45, 1, 11),
      // Signal bars
      _IconDef(0.55, 0.10, 2, 14),
      _IconDef(0.35, 0.58, 2, 12),
      _IconDef(0.80, 0.78, 2, 15),
      _IconDef(0.18, 0.25, 2, 11),
      // Cloud symbols
      _IconDef(0.40, 0.22, 3, 18),
      _IconDef(0.75, 0.42, 3, 14),
      _IconDef(0.10, 0.88, 3, 16),
      _IconDef(0.90, 0.30, 3, 12),
      // Ethernet/connection dots
      _IconDef(0.30, 0.78, 4, 13),
      _IconDef(0.65, 0.48, 4, 11),
      _IconDef(0.50, 0.35, 4, 14),
      _IconDef(0.20, 0.55, 4, 10),
      // Router symbol
      _IconDef(0.82, 0.88, 5, 16),
      _IconDef(0.12, 0.05, 5, 13),
      _IconDef(0.55, 0.52, 5, 11),
    ];

    for (int i = 0; i < icons.length; i++) {
      final def = icons[i];
      // حركة عائمة لكل رمز
      final phase = i * 0.37;
      final floatX = math.sin(animValue * math.pi * 2 + phase) * 6;
      final floatY = math.cos(animValue * math.pi * 2 + phase * 1.3) * 5;
      final alpha = 0.6 + math.sin(animValue * math.pi * 2 + phase * 0.7) * 0.4;

      final cx = size.width * def.x + floatX;
      final cy = size.height * def.y + floatY;
      final s = def.size;

      final iconColor = color.withValues(alpha: color.a * alpha);
      paint.color = iconColor;
      paint.strokeWidth = s * 0.08;
      fillPaint.color = iconColor;

      switch (def.type) {
        case 0: // WiFi — 3 أقواس
          _drawWifi(canvas, cx, cy, s, paint);
          break;
        case 1: // Globe — دائرة + خطوط
          _drawGlobe(canvas, cx, cy, s, paint);
          break;
        case 2: // Signal bars
          _drawSignal(canvas, cx, cy, s, fillPaint);
          break;
        case 3: // Cloud
          _drawCloud(canvas, cx, cy, s, paint);
          break;
        case 4: // Ethernet dots
          _drawEthernet(canvas, cx, cy, s, fillPaint, paint);
          break;
        case 5: // Router
          _drawRouter(canvas, cx, cy, s, paint, fillPaint);
          break;
      }
    }
  }

  void _drawWifi(Canvas canvas, double cx, double cy, double s, Paint p) {
    final rect1 = Rect.fromCenter(center: Offset(cx, cy), width: s, height: s);
    final rect2 = Rect.fromCenter(
      center: Offset(cx, cy),
      width: s * 0.65,
      height: s * 0.65,
    );
    final rect3 = Rect.fromCenter(
      center: Offset(cx, cy),
      width: s * 0.3,
      height: s * 0.3,
    );
    p.strokeWidth = s * 0.07;
    canvas.drawArc(rect1, -math.pi * 0.75, math.pi * 0.5, false, p);
    canvas.drawArc(rect2, -math.pi * 0.75, math.pi * 0.5, false, p);
    canvas.drawArc(rect3, -math.pi * 0.75, math.pi * 0.5, false, p);
    canvas.drawCircle(
      Offset(cx, cy + s * 0.15),
      s * 0.06,
      p..style = PaintingStyle.fill,
    );
    p.style = PaintingStyle.stroke;
  }

  void _drawGlobe(Canvas canvas, double cx, double cy, double s, Paint p) {
    final r = s * 0.45;
    p.strokeWidth = s * 0.06;
    canvas.drawCircle(Offset(cx, cy), r, p);
    // خط أفقي
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), p);
    // خط عمودي (قوس)
    final ovalRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: r,
      height: r * 2,
    );
    canvas.drawOval(ovalRect, p);
  }

  void _drawSignal(Canvas canvas, double cx, double cy, double s, Paint p) {
    final barW = s * 0.14;
    final gap = s * 0.06;
    final totalW = barW * 4 + gap * 3;
    final startX = cx - totalW / 2;
    for (int i = 0; i < 4; i++) {
      final barH = s * (0.25 + i * 0.2);
      final x = startX + i * (barW + gap);
      final y = cy + s * 0.4 - barH;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, barH),
          Radius.circular(barW * 0.3),
        ),
        p,
      );
    }
  }

  void _drawCloud(Canvas canvas, double cx, double cy, double s, Paint p) {
    p.strokeWidth = s * 0.06;
    final path = Path();
    // شكل سحابة مبسط
    path.moveTo(cx - s * 0.35, cy + s * 0.1);
    path.quadraticBezierTo(
      cx - s * 0.45,
      cy - s * 0.15,
      cx - s * 0.15,
      cy - s * 0.2,
    );
    path.quadraticBezierTo(
      cx - s * 0.05,
      cy - s * 0.45,
      cx + s * 0.15,
      cy - s * 0.2,
    );
    path.quadraticBezierTo(
      cx + s * 0.4,
      cy - s * 0.25,
      cx + s * 0.35,
      cy + s * 0.1,
    );
    path.close();
    canvas.drawPath(path, p);
  }

  void _drawEthernet(
    Canvas canvas,
    double cx,
    double cy,
    double s,
    Paint fill,
    Paint stroke,
  ) {
    // 3 نقاط متصلة بخطوط
    final r = s * 0.08;
    final pts = [
      Offset(cx - s * 0.25, cy - s * 0.15),
      Offset(cx + s * 0.25, cy - s * 0.15),
      Offset(cx, cy + s * 0.2),
    ];
    stroke.strokeWidth = s * 0.05;
    canvas.drawLine(pts[0], pts[1], stroke);
    canvas.drawLine(pts[1], pts[2], stroke);
    canvas.drawLine(pts[2], pts[0], stroke);
    for (final pt in pts) {
      canvas.drawCircle(pt, r, fill);
    }
  }

  void _drawRouter(
    Canvas canvas,
    double cx,
    double cy,
    double s,
    Paint stroke,
    Paint fill,
  ) {
    stroke.strokeWidth = s * 0.06;
    // جسم الراوتر
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy + s * 0.1),
        width: s * 0.6,
        height: s * 0.3,
      ),
      Radius.circular(s * 0.05),
    );
    canvas.drawRRect(bodyRect, stroke);
    // هوائيان
    canvas.drawLine(
      Offset(cx - s * 0.12, cy - s * 0.05),
      Offset(cx - s * 0.2, cy - s * 0.3),
      stroke,
    );
    canvas.drawLine(
      Offset(cx + s * 0.12, cy - s * 0.05),
      Offset(cx + s * 0.2, cy - s * 0.3),
      stroke,
    );
    // نقاط صغيرة على الهوائيات
    canvas.drawCircle(Offset(cx - s * 0.2, cy - s * 0.3), s * 0.04, fill);
    canvas.drawCircle(Offset(cx + s * 0.2, cy - s * 0.3), s * 0.04, fill);
  }

  @override
  bool shouldRepaint(covariant _InternetIconsBackgroundPainter oldDelegate) {
    return oldDelegate.animValue != animValue || oldDelegate.color != color;
  }
}

// بيان رمز واحد في الخلفية
class _IconDef {
  final double x; // 0..1 نسبي
  final double y; // 0..1 نسبي
  final int type; // 0=wifi, 1=globe, 2=signal, 3=cloud, 4=ethernet, 5=router
  final double size;
  const _IconDef(this.x, this.y, this.type, this.size);
}

// رسام Donut مخصص لبطاقات الإحصائيات — تصميم فاخر مع تدرج ونقطة نهاية
class _StatDonutPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final double strokeWidth;

  _StatDonutPainter({
    required this.progress,
    required this.color,
    double strokeWidth = 8.0,
  }) : strokeWidth = strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    if (progress <= 0.001) return;

    final sweepAngle = (progress.clamp(0.0, 1.0)) * 2 * math.pi;

    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: -math.pi / 2 + 2 * math.pi,
        colors: [
          color.withValues(alpha: 0.5),
          color,
          color,
          color.withValues(alpha: 0.7),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, sweepAngle, false, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _StatDonutPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
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
    double strokeWidth = 10,
  }) : strokeWidth = strokeWidth;

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
        colors: [color.shade400, color.shade600, color.shade400],
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
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => {
              if (mounted) setState(() => _isLoading = true),
            },
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
          ),
        )
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
    _loginMonitor = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _checkLoginOnce(),
    );
  }

  Future<void> _checkLoginOnce() async {
    if (_loggedIn) return;
    try {
      String res = '';
      if (Platform.isWindows && _winController != null) {
        res = await _winController!.executeScript(
              "(function(){return document.querySelector('#pane-side')?'LOGGED':'NOT';})()",
            ) ??
            '';
      } else if (!Platform.isWindows && _controller != null) {
        final r = await _controller!.runJavaScriptReturningResult(
          "(function(){return document.querySelector('#pane-side')?'LOGGED':'NOT';})()",
        );
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
        const SnackBar(content: Text('✅ تم تسجيل الدخول إلى WhatsApp Web')),
      );

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
          await _winController!.executeScript(
            "localStorage.clear(); sessionStorage.clear();",
          );
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
          const SnackBar(content: Text('🚪 تم تسجيل الخروج (محلي)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل تسجيل الخروج: $e')));
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
                'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.',
              ),
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
              'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.',
            ),
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
              Icon(IconsaxPlusBold.warning_2, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _initWeb,
                    icon: Icon(IconsaxPlusLinear.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                  if (Platform.isWindows && _error!.contains('WebView2')) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _launchWebView2Download,
                      icon: Icon(IconsaxPlusLinear.document_download),
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
        content = Column(
          children: [
            Expanded(child: wvwin.Webview(_winController!)),
            _bottomBar(),
          ],
        );
      }
    } else {
      if (_controller == null) {
        content = const Center(child: CircularProgressIndicator());
      } else {
        content = Column(
          children: [
            Expanded(child: WebViewWidget(controller: _controller!)),
            _bottomBar(),
          ],
        );
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
            icon: Icon(IconsaxPlusLinear.refresh),
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
            icon: Icon(IconsaxPlusLinear.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: Stack(
        children: [
          content,
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.05),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _bottomBar() => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _loggedIn
                    ? '✅ متصل - جلسة محلية (قد تُفقد عند إغلاق التطبيق)'
                    : 'افتح واتساب بالهاتف > الأجهزة المرتبطة > اربط جهازًا لمسح QR',
                style: TextStyle(
                  fontSize: 11.5,
                  color: _loggedIn ? Colors.green.shade700 : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'فتح خارجي',
              icon: Icon(IconsaxPlusLinear.global, size: 20),
              onPressed: () => launchUrl(
                Uri.parse('https://web.whatsapp.com'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      );
}
