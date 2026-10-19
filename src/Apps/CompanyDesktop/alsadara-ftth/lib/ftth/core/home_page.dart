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
import '../../pages/whatsapp_bulk_sender_page.dart'; // صفحة إرسال رسائل جماعية (تحتوي على إعدادات API والتقارير)
import '../../whatsapp/pages/whatsapp_settings_hub_page.dart'; // مركز إعدادات الواتساب الموحد

import '../users/user_details_page.dart';
import '../users/users_page.dart';
import '../tickets/tktats_page.dart'; // تغيير الاستيراد إلى tktats_page
import '../reports/zones_page.dart';
import '../../pages/kml_zones_map_page.dart';
import '../subscriptions/subscriptions_page.dart';
import '../transactions/caounter_details_page.dart';
import '../reports/export_page.dart';
import '../users/quick_search_users_page.dart';
import '../transactions/account_records_page.dart';
import '../transactions/daily_settlement_page.dart';
import '../../pages/local_storage_page.dart'; // صفحة التخزين الداخلي
import '../../pages/ftth/fetch_server_data_page.dart'; // صفحة جلب بيانات الموقع
import '../../pages/ftth/ftth_company_page.dart'; // صفحة الشركة
import '../../widgets/platform_webview.dart'; // WebView للواجهات الخارجية
import '../../services/background_sync_service.dart'; // خدمة المزامنة في الخلفية
import '../subscriptions/expiring_soon_page.dart';
import '../transactions/transactions_page.dart';
import '../../services/badge_service.dart';
import '../../services/auth/session_manager.dart';
import '../../services/vps_sync_service.dart';
import '../../services/vps_upload_service.dart';
import '../../services/ftth_whatsapp_settings_service.dart';
import '../../services/auth/auth_context.dart';
import '../../services/dual_auth_service.dart';
import '../../services/vps_auth_service.dart'; // لمعرّف الموظف الحالي (مُبدّل حساب FTTH)
import '../../services/linked_accounts_service.dart'; // جلب حسابات FTTH المرتبطة للتبديل
import '../../services/ftth/ftth_cache_service.dart';
import '../../services/ftth/ftth_event_bus.dart';

import '../../utils/responsive_helper.dart';
import '../../widgets/notification_bell.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../pages/super_admin/super_admin_dashboard.dart'; // ✅ لوحة تحكم Super Admin
import '../../pages/server_data_page.dart'; // صفحة بيانات السيرفر
import '../tasks/ftth_tasks_page.dart'; // صفحة مهام التوصيل FTTH
import '../tasks/customer_search_connect_page.dart'; // بحث مشترك + توصيل
import '../requests/customer_hub_page.dart'; // مشترك جديد (Hub)

class HomePage extends StatefulWidget {
  final String username;
  final String authToken;
  final String? permissions; // إضافة صلاحيات المستخدم
  final String? department; // إضافة القسم
  final String? center; // إضافة المركز
  final String? salary; // إضافة الراتب
  // معلومات النظام الأول
  final String? firstSystemUsername; // اسم المستخدم في النظام الأول
  final String? firstSystemDepartment; // قسم النظام الأول
  final String? firstSystemCenter; // مركز النظام الأول
  final String? firstSystemSalary; // راتب النظام الأول
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
    this.firstSystemUsername,
    this.firstSystemDepartment,
    this.firstSystemCenter,
    this.firstSystemSalary,
    this.isSuperAdminMode = false,
    this.tenantId,
    this.tenantCode,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();

  /// رقم هاتف معلّق للبحث (يُملأ من صفحة المحادثات)
  static String? pendingPhoneSearch;
  static final ValueNotifier<String?> phoneSearchNotifier = ValueNotifier(null);

  /// اسم معلّق للبحث (يُملأ من صفحة المحادثات)
  static final ValueNotifier<String?> nameSearchNotifier = ValueNotifier(null);

  // دالة عامة للحصول على إعداد الإرسال التلقائي
  static Future<bool> getWhatsAppAutoSendSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('whatsapp_auto_send') ?? true; // مُفعل افتراضياً
    } catch (e) {
      debugPrint('❌ خطأ في تحميل إعداد الإرسال التلقائي');
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
  int _expiringSoonCount = 0;
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
  // أعلام للتحميل المبكر وتحكم تكرار الطلبات
  bool _earlyPrefetchStarted = false;
  bool _dashboardRequested = false;
  bool _walletRequested = false;
  bool _dashboardFetchInProgress = false; // منع تداخل طلبات لوحة التحكم
  DateTime? _lastDashboardFetch; // throttle: 10 ثوانٍ بين كل جلبين

  // Sidebar state (للشاشات العريضة)

  // Mobile Bottom Navigation
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- البحث السريع في الشاشة الرئيسية ---
  final TextEditingController _searchNameCtrl = TextEditingController();
  final TextEditingController _searchPhoneCtrl = TextEditingController();
  final List<dynamic> _searchZones = [];
  final List<dynamic> _searchResults = [];
  String _searchZoneId = '';
  int _searchPage = 1;
  int _searchTotal = 0;
  bool _searchLoading = false;
  bool _searchLoadingMore = false;
  bool _searchDone = false; // هل تم تنفيذ بحث سابق
  bool _searchWaiting = false; // انتظار debounce
  int _searchSeq = 0;
  int _lastSearchSeq = 0;
  Timer? _searchDebounce;
  final ScrollController _searchScrollCtrl = ScrollController();
  // كاش المنطقة للبحث السريع
  static final Map<String, String> _searchZoneCache = {};
  final Set<String> _searchZoneFetching = {};
  StreamSubscription<String>? _ftthEventBusSub;

  // حسابات FTTH المرتبطة بالموظف الحالي — لمُبدّل الحساب في الشريط العلوي.
  // يُعرض المبدّل فقط إذا كان العدد >= 2 (بعد فلترة النشط + نوع FTTH).
  List<LinkedAccount> _ftthAccounts = [];

  @override
  void initState() {
    super.initState();
    currentToken = widget.authToken;

    // مراقبة بحث الهاتف من صفحة المحادثات
    HomePage.phoneSearchNotifier.addListener(_onPhoneSearchRequested);
    HomePage.nameSearchNotifier.addListener(_onNameSearchRequested);

    // تحديث التوكن في خدمة تحديثات التذاكر
    TicketUpdatesService.instance.updateAuthToken(widget.authToken);

    // فحص أولي لحال�� المدير باستخدام اسم المستخدم
    isAdmin = _isAdminByUsername();

    _initializeAnimations();
    _initializeApp();
    // مزامنة إعدادات واتساب FTTH لكل شركة من السيرفر عند الدخول
    // (fire-and-forget؛ محميّة بالكامل — تتخطّى بصمت عند غياب الشركة/الاتصال)
    FtthWhatsAppSettingsService.syncFromServer();
    _startEarlyPrefetch();
    _fetchSearchZones();
    _searchScrollCtrl.addListener(_onSearchScroll);

    // بيكاتشو يُدار الآن من Overlay عالمي (لا حاجة لتحميل إعداداته هنا)

    // الاشتراك في قناة التحديث الفوري (مع حفظ المرجع لإلغائه في dispose)
    _ftthEventBusSub = FtthEventBus.instance.stream.listen((event) {
      if (!mounted) return;
      if (event == FtthEvents.forceRefresh) {
        _performRefresh();
      }
    });

    // إعداد إشعار المزامنة في الخلفية
    _setupBackgroundSyncNotification();

    // بدء المزامنة التلقائية حسب وضع الجهاز
    // Master: يجلب من FTTH ويرفع للسيرفر — لا يحتاج تنزيل من VPS
    // عادي: ينزّل من VPS فقط
    VpsUploadService.isMasterDevice().then((isMaster) {
      if (isMaster) {
        VpsUploadService.instance.startAutoSync();
      } else {
        VpsSyncService.instance.startAutoSync();
      }
    });

    // الزر العائم للواتساب يتم إظهاره بعد تحميل الصلاحيات في _initializeApp

    // جلب حسابات FTTH المرتبطة للموظف الحالي (fire-and-forget؛ فشل صامت)
    _loadFtthAccounts();
  }

  // ─────────────── مُبدّل حساب FTTH في الشريط العلوي ───────────────

  /// يجلب حسابات FTTH المرتبطة بالموظف المسجَّل دخوله (نظام الصدارة الأول)
  /// ويحتفظ بالنشطة منها فقط. فشل الطلب/403/غياب المعرّف = فشل صامت لا يكسر
  /// الشريط. لا يُخزَّن أي اعتماد — فقط بيانات العرض من البوّابة الداخلية.
  Future<void> _loadFtthAccounts() async {
    try {
      final selfUserId = VpsAuthService.instance.currentUser?.id;
      if (selfUserId == null || selfUserId.isEmpty) return;

      final result =
          await LinkedAccountsService.instance.getAccounts(selfUserId);
      if (!mounted) return;
      if (result['success'] != true) return;

      final data = result['data'];
      if (data is! List) return;
      final ftth = data
          .whereType<LinkedAccount>()
          .where((a) => a.isFtth && a.isActive)
          .toList();

      setState(() => _ftthAccounts = ftth);
    } catch (_) {
      // فشل صامت — لا يُظهر المبدّل ولا يكسر الشريط العلوي.
    }
  }

  /// تنفيذ تبديل الجلسة النشطة إلى حساب FTTH مرتبط آخر.
  /// يسجّل الدخول خادمياً (توكن فقط، بلا كلمة مرور على العميل) ثم يعيد بناء
  /// كامل شاشة HomePage بالتوكن/الاسم الجديدين عبر pushReplacement.
  Future<void> _onSwitchFtthAccount(LinkedAccount account) async {
    final currentUsername = DualAuthService.instance.ftthUsername;
    if (account.username == currentUsername) return; // نفس الحساب — لا شيء.

    // مؤشّر انشغال غير قابل للإلغاء أثناء الدخول الخادمي.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result =
        await DualAuthService.instance.loginWithLinkedFtthAccount(account);

    if (!mounted) return;
    // أغلق مؤشّر الانشغال.
    Navigator.of(context, rootNavigator: true).pop();

    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message ?? 'تعذّر تبديل الحساب — بقي الحساب الحالي',
            style: const TextStyle(fontFamily: SdText.family),
          ),
          backgroundColor: SdColors.danger,
        ),
      );
      return;
    }

    final newUsername = DualAuthService.instance.ftthUsername ?? account.username;
    final newToken = DualAuthService.instance.ftthToken ?? '';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم التبديل إلى: ${account.label.isNotEmpty ? account.label : account.username}',
          style: const TextStyle(fontFamily: SdText.family),
        ),
        backgroundColor: SdColors.success,
      ),
    );

    // إعادة بناء كامل الشاشة بالقيم الجديدة — نفس وسائط HomePage الحالية.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/ftth-home'),
        builder: (_) => HomePage(
          username: newUsername,
          authToken: newToken,
          permissions: widget.permissions,
          department: widget.department,
          center: widget.center,
          salary: widget.salary,
          firstSystemUsername: widget.firstSystemUsername,
          firstSystemDepartment: widget.firstSystemDepartment,
          firstSystemCenter: widget.firstSystemCenter,
          firstSystemSalary: widget.firstSystemSalary,
          isSuperAdminMode: widget.isSuperAdminMode,
          tenantId: widget.tenantId,
          tenantCode: widget.tenantCode,
        ),
      ),
    );
  }

  /// ودجت مُبدّل حساب FTTH في الشريط العلوي (على نمط مُبدّل الساس).
  /// يظهر فقط عند توفّر حسابين نشطين فأكثر؛ غير ذلك = فراغ.
  Widget _buildFtthAccountSwitcher() {
    final accounts = _ftthAccounts;
    if (accounts.length < 2) return const SizedBox.shrink();

    final currentUsername = DualAuthService.instance.ftthUsername;
    String labelOf(LinkedAccount a) =>
        a.label.isNotEmpty ? a.label : a.username;
    final currentAcc = accounts.firstWhere(
      (a) => a.username == currentUsername,
      orElse: () => accounts.first,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: PopupMenuButton<String>(
        tooltip: 'تبديل حساب FTTH',
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onSelected: (id) {
          final acc = accounts.firstWhere((a) => a.id == id,
              orElse: () => accounts.first);
          _onSwitchFtthAccount(acc);
        },
        itemBuilder: (_) => [
          for (final a in accounts)
            PopupMenuItem<String>(
              value: a.id,
              child: Row(
                children: [
                  Icon(
                    a.username == currentUsername
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: a.username == currentUsername
                        ? SdColors.primary
                        : SdColors.faint,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      labelOf(a),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: SdText.family,
                        fontWeight: a.username == currentUsername
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: SdColors.ink,
                      ),
                    ),
                  ),
                  if (a.isPrimary) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: SdColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'أساسي',
                        style: TextStyle(
                          fontFamily: SdText.family,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: SdColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz_rounded,
                  size: 16, color: Colors.white),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  labelOf(currentAcc),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.expand_more_rounded,
                  size: 16, color: Colors.white),
            ],
          ),
        ),
      ),
    );
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
      }
    });
  }

  void _onPhoneSearchRequested() {
    final phone = HomePage.phoneSearchNotifier.value;
    if (phone != null && phone.isNotEmpty && mounted) {
      HomePage.phoneSearchNotifier.value = null;
      _searchPhoneCtrl.text = phone;
      _searchNameCtrl.clear();
      _searchZoneId = '';
      setState(() { _searchPage = 1; _searchDone = true; });
      _performQuickSearch();
    }
  }

  void _onNameSearchRequested() {
    final name = HomePage.nameSearchNotifier.value;
    if (name != null && name.isNotEmpty && mounted) {
      HomePage.nameSearchNotifier.value = null;
      _searchNameCtrl.text = name;
      _searchPhoneCtrl.clear();
      _searchZoneId = '';
      setState(() { _searchPage = 1; _searchDone = true; });
      _performQuickSearch();
    }
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
            _syncFtthPermissions();
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
      }

      // التذكير التلقائي يُدار عبر n8n workflow على السيرفر

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
      _fetchExpiringSoonCount();
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
    HomePage.phoneSearchNotifier.removeListener(_onPhoneSearchRequested);
    HomePage.nameSearchNotifier.removeListener(_onNameSearchRequested);

    // إلغاء اشتراك EventBus أولاً لمنع أي callbacks بعد dispose
    _ftthEventBusSub?.cancel();
    _ftthEventBusSub = null;

    // إلغاء callback المزامنة لمنع استدعاءات على widget محذوف
    BackgroundSyncService.instance.onSyncComplete = null;

    VpsSyncService.instance.stopAutoSync();
    VpsUploadService.instance.stopAutoSync();
    _timer?.cancel();
    _walletTimer?.cancel();
    _searchDebounce?.cancel();

    // إخفاء واتساب فقط — الشريط العائم يبقى ويُعاد تهيئته في النظام الأول
    Future.microtask(() {
      WhatsAppBottomWindow.hideConversationsFloatingButton();
    });

    _refreshAnimationController.dispose();
    _cardAnimationController.dispose();
    _counterAnimationController.dispose();
    _searchNameCtrl.dispose();
    _searchPhoneCtrl.dispose();
    _searchScrollCtrl.dispose();
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
      firstSystemDepartment: widget.firstSystemDepartment,
      firstSystemCenter: widget.firstSystemCenter,
      firstSystemSalary: widget.firstSystemSalary,
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
          _syncFtthPermissions();
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
              _syncFtthPermissions();
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
              _syncFtthPermissions();
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
      // جلب التوكن الحالي من AuthService (يتم تجديده تلقائياً إذا اقترب من الانتهاء)
      final freshToken = await AuthService.instance.getAccessToken();
      if (freshToken != null && freshToken != currentToken && mounted) {
        setState(() {
          currentToken = freshToken;
        });
        // تحديث التوكن في الخدمات الأخرى
        TicketUpdatesService.instance.updateAuthToken(freshToken);
      }
    } catch (e) {
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
        return;
      }
    }
  } // نظام محدود لتحديد الصلاحيات الإدارية - النظام الأول فقط

  /// مزامنة صلاحيات FTTH مع DualAuthService ليمكن الوصول لها من أي مكان
  void _syncFtthPermissions() {
    DualAuthService.instance.updateFtthPermissions(
      isAdmin: isAdmin,
      importantPermissions: _getImportantPermissions(),
    );
  }

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

    debugPrint('مستخدم عادي - لم توجد صلاحيات مدير');
    return false;
  }

  // فحص خاص لصلاحيات مدير النظام الأول فقط (يستخدم PermissionManager بدلاً من النص)
  bool _isFirstSystemAdmin() {
    return PermissionManager.instance.canView('users');
  }

  Future<void> fetchDashboardData() async {
    // منع التداخل: إذا كان جلب سابق جارٍ، تخطَّ
    if (_dashboardFetchInProgress) return;
    // throttle: تجاهل إذا مضى أقل من 10 ثوانٍ على آخر جلب ناجح
    final now = DateTime.now();
    if (_lastDashboardFetch != null &&
        now.difference(_lastDashboardFetch!).inSeconds < 10) {
      return;
    }
    _dashboardFetchInProgress = true;

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
        _lastDashboardFetch = DateTime.now(); // تحديث وقت آخر جلب ناجح
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
        // معالجة خطأ انتهاء صلاحية التوكن
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
    } finally {
      _dashboardFetchInProgress = false;
    }
  }

  /// جلب عدد الاشتراكات المنتهية قريباً (خلال 3 أيام)
  Future<void> _fetchExpiringSoonCount() async {
    try {
      final now = DateTime.now();
      final from = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final to3 = now.add(const Duration(days: 3));
      final to = '${to3.year}-${to3.month.toString().padLeft(2, '0')}-${to3.day.toString().padLeft(2, '0')}';

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/subscriptions?pageSize=1&fromExpirationDate=$from&toExpirationDate=$to',
      );
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _expiringSoonCount = (data['totalCount'] ?? 0) as int;
        });
      }
    } catch (e) {
      debugPrint('⚠️ تعذر جلب عدد المنتهي قريباً');
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
      _showErrorMessage('فشل في تحديث البيانات');
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
      _showErrorMessage('فشل في التحديث الكامل');
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
        backgroundColor: SdColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // تحميل الصلاحيات من PermissionManager (V2)
  Future<void> _loadUserPermissions() async {
    final pm = PermissionManager.instance;
    if (!pm.isLoaded) {
      await pm.loadPermissions();
    }
    debugPrint(
        'تحميل الصلاحيات V2 - مدير النظام الأول: ${_isFirstSystemAdmin()}');
    debugPrint('اسم المستخدم: ${widget.username}');
    // تحديث الواجهة بعد تحميل الصلاحيات
    if (mounted) setState(() {});
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
                        backgroundColor: SdColors.warning,
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
                        backgroundColor: SdColors.danger,
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
                      content: Text('خطأ في التحقق من كلمة المرور'),
                      backgroundColor: SdColors.danger,
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
                      color: SdColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Icon(
                      IconsaxPlusLinear.lock,
                      color: SdColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'إدخال كلمة المرور',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: SdColors.primary,
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
                          color: SdColors.primary,
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
                    backgroundColor: SdColors.primary,
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

  /// هل الصلاحية مُعطّلة صراحةً؟ (موجودة في البيانات وقيمتها false)
  /// إذا المفتاح غير موجود أصلاً (مستخدم قديم) → يُعتبر غير مُعطّل (يظهر افتراضياً)
  bool _isExplicitlyDisabled(String key) {
    final pm = PermissionManager.instance;
    if (!pm.hasKey(key)) return false; // غير موجود → افتراضي يظهر
    return !pm.canView(key); // موجود → نتحقق من قيمته
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

  // دالة للحصول على جميع الصلاحيات (من PermissionManager مباشرة)
  Map<String, bool> getAllPermissions() {
    final pm = PermissionManager.instance;
    final result = <String, bool>{};
    for (final entry in pm.firstSystemPermissions.entries) {
      result[entry.key] = entry.value['view'] == true;
    }
    for (final entry in pm.secondSystemPermissions.entries) {
      result[entry.key] = entry.value['view'] == true;
    }
    return result;
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

  // بيكاتشو الآن في Overlay عالمي - لا حاجة لدوال محلية

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
      debugPrint('❌ خطأ في فتح صفحة ربط الواتساب');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: Icon(IconsaxPlusBold.warning_2, color: SdColors.danger, size: 48),
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
                Text('تفاصيل الخطأ'),
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
      debugPrint('❌ خطأ في فتح رابط التحميل');
      if (mounted) {
        showMessage(
          'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.',
          Colors.orange,
        );
      }
    }
  }

  void changeHierarchyLevel(int level) {
    setState(() {
      hierarchyLevel = level;
      isAdmin = _checkAdminPermissions();
      _syncFtthPermissions();
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
                  color: SdColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Icon(
                  IconsaxPlusBold.user_square,
                  color: SdColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'معلومات الشريك التفصيلية',
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width < 400 ? 15 : 20,
                    fontWeight: FontWeight.bold,
                    color: SdColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
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
                          colors: [SdColors.successTint, SdColors.successTint],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: SdColors.successTintEdge),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                IconsaxPlusBold.chart,
                                color: SdColors.success,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'النظام الأول',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: SdColors.success,
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
                            widget.permissions ?? 'غير محدد',
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
                        colors: [SdColors.infoTint, SdColors.infoTint],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SdColors.infoTintEdge),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              IconsaxPlusBold.global_search,
                              color: SdColors.info,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'نظام FTTH - المعلومات الأساسية',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: SdColors.info,
                                ),
                                overflow: TextOverflow.ellipsis,
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
                          colors: [SdColors.platformTint, SdColors.platformTint],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: SdColors.platformTintEdge),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                IconsaxPlusBold.verify,
                                color: SdColors.platformBase,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'صلاحيات النظام (${userPermissions.length})',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: SdColors.platformBase,
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
                                    color: SdColors.success,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      perm,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: SdColors.platformBase,
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
                                  color: SdColors.platformBase,
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
                          colors: [SdColors.warningTint, SdColors.warningTint],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: SdColors.warningTintEdge),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                IconsaxPlusLinear.briefcase,
                                color: SdColors.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'الأدوار والمناصب (${userRoles.length})',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: SdColors.warning,
                                  ),
                                  overflow: TextOverflow.ellipsis,
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
                                        color: SdColors.warning,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _translateRole(
                                            role['displayValue'] ?? '',
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: SdColors.warning,
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
                          colors: [SdColors.accentTint, SdColors.accentTint],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: SdColors.accentTintEdge),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                IconsaxPlusBold.map,
                                color: SdColors.accent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'الزونات المصرح بها (${userZones.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: SdColors.accent,
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
                                      color: SdColors.accentTintEdge,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      zone['displayValue'] ?? '',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: SdColors.accent,
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
                                  color: SdColors.accent,
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
                        colors: [SdColors.primaryTint, SdColors.primaryTint],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SdColors.primaryTintEdge),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              IconsaxPlusBold.setting_2,
                              color: SdColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'صلاحيات النظام المحلي',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: SdColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...getAllPermissions().entries.map((permission) {
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
                                      color: SdColors.primary,
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
          Icon(icon, size: 16, color: SdColors.muted),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: SdColors.muted,
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
                color: SdColors.ink,
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
          Icon(icon, size: 16, color: SdColors.muted),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: SdColors.muted,
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
                      color: SdColors.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(IconsaxPlusLinear.copy, size: 18),
                  color: SdColors.faint,
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
      // تفعيل زر واتساب ويب — فقط إذا مصرح للمستخدم
      if (_hasPermission('whatsapp')) {
        FloatingToolbar.enableWhatsApp();
      }

      // التحقق من صلاحية إظهار زر المحادثات
      if (_hasPermission('whatsapp_conversations_fab')) {
        FloatingToolbar.enableConversations(isAdmin: isAdmin);
      } else {
        FloatingToolbar.disableConversations();
      }

      // زر التذاكر العائم (FTTH)
      if (_hasPermission('tasks') && !_isExplicitlyDisabled('fab_tasks')) {
        FloatingToolbar.enableTasks();
      }

      // زر المهام (النظام الأول) — يبقى ظاهراً إذا كان مُفعّلاً سابقاً
      FloatingToolbar.reEnableS1Tasks();

      // زر المحادثة الداخلية العائم
      if (_hasPermission('chat') && !_isExplicitlyDisabled('fab_chat')) {
        FloatingToolbar.enableChat();
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في إظهار الأزرار العائمة');
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
          // خلفية سادة موحّدة (sd) — أُزيلت زخرفة Aurora والأيقونات الباهتة
          const Positioned.fill(
            child: ColoredBox(color: SdColors.ground),
          ),
          Scaffold(
            key: _scaffoldKey,
            backgroundColor: Colors.transparent,
            appBar: _buildAppBar(isTablet, isSmallPhone, screenWidth),
            // القائمة الجانبية الموحّدة (SdSideNav): درج على الهاتف، لوحة جانبية غير ذلك.
            drawer: context.sd.isPhone
                ? SdSideNav.drawer(context, _buildSideNav(inDrawer: true))
                : null,
            bottomNavigationBar: null,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!context.sd.isPhone) _buildSideNav(inDrawer: false),
                Expanded(
                  child: isLoadingDashboard
                      ? _buildLoadingIndicator(isTablet)
                      : _buildDashboardContent(isTablet, screenWidth),
                ),
              ],
            ),
          ),
          // مؤشر الجلب في الخلفية - عائم
          _buildFloatingBackgroundSyncIndicator(),
          // مؤشر تنزيل VPS العائم
          _buildFloatingVpsSyncIndicator(),
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
                color: SdColors.surface,
                borderRadius: BorderRadius.circular(SdRadius.md),
                border: Border.all(color: SdColors.cardEdge, width: 2.0),
                boxShadow: SdDepth.raised(),
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
                        SdColors.info,
                      ),
                      backgroundColor: SdColors.info.withValues(alpha: 0.2),
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
                            color: SdColors.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          progress.message,
                          style: const TextStyle(
                            color: SdColors.muted,
                            fontSize: 11.5,
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
                      color: SdColors.infoTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: SdColors.infoTintEdge,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      '${progress.percentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: SdColors.info,
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
                        color: SdColors.dangerTint,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: SdColors.dangerTintEdge,
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        IconsaxPlusBold.close_circle,
                        color: SdColors.danger,
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

  /// مؤشر تنزيل VPS العائم — يظهر فقط أثناء التنزيل
  Widget _buildFloatingVpsSyncIndicator() {
    return ListenableBuilder(
      listenable: VpsSyncService.instance,
      builder: (context, _) {
        final vps = VpsSyncService.instance;
        if (!vps.isSyncing && vps.progress <= 0) {
          return const SizedBox.shrink();
        }

        final isError = vps.lastResult?.success == false;
        final color = isError ? SdColors.danger : SdColors.accent;

        return Positioned(
          bottom: 16,
          left: 16,
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: SdColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (vps.isSyncing)
                    SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: vps.progress > 0.05 ? vps.progress : null,
                        valueColor: AlwaysStoppedAnimation(color),
                        backgroundColor: color.withValues(alpha: 0.15),
                      ),
                    )
                  else
                    Icon(
                      isError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 18, color: color,
                    ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width < 400 ? 150 : 220),
                    child: Text(
                      vps.statusMessage,
                      style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (vps.isSyncing && vps.progress > 0.05) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${(vps.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w700),
                    ),
                  ],
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
    // الشريط العلوي الموحّد (sd): نيلي الصدارة بحافّة بارزة، وأزرار إجراء
    // بأيقونة + اسم. كل المنطق والتنقّل كما هو.
    final name = partnerName;
    return SdAppBar(
      title: name ?? 'لوحة التحكم',
      automaticallyImplyLeading: true,
      // زر العودة الموحّد (leading) مع تنظيف واتساب قبل العودة.
      onBack: () {
        WhatsAppBottomWindow.hideConversationsFloatingButton();
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      actions: [
        // جرس الإشعارات (ودجت موحّد قائم بذاته)
        const NotificationBell(iconSize: 22.0),
        // مُبدّل حساب FTTH — يظهر فقط عند توفّر حسابين نشطين فأكثر للموظف.
        _buildFtthAccountSwitcher(),
        // معلومات الحساب — تفتح نفس نافذة بيانات المستخدم
        if (name != null)
          SdAppBarAction(
            icon: IconsaxPlusLinear.info_circle,
            label: 'معلومات الحساب',
            onPressed: _showUserInfoDialog,
          ),
        if (widget.isSuperAdminMode)
          SdAppBarAction(
            icon: IconsaxPlusBold.security_user,
            label: 'لوحة مدير النظام',
            onPressed: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const SuperAdminDashboard()),
                (route) => false,
              );
            },
          ),
        // تحديث كامل
        SdAppBarAction(
          icon: IconsaxPlusBold.refresh,
          label: 'تحديث كامل',
          onPressed: isRefreshing ? null : _manualFullRefresh,
        ),
        // زر القائمة الجانبية يُضاف تلقائياً من SdAppBar على الهاتف.
      ],
    );
  }

  // ═══ القائمة الجانبية الموحّدة (SdSideNav) ═══
  // مصدر واحد لعناصر القائمة بدل الشريط الجانبي والدرج المكرّرين سابقاً.

  Widget _buildSideNav({required bool inDrawer}) {
    return SdSideNav(
      inDrawer: inDrawer,
      title: 'القائمة الرئيسية',
      subtitle: widget.username,
      sections: _navSections(),
      footer: _navFooter(),
    );
  }

  List<SdNavSection> _navSections() {
    final sections = <SdNavSection>[
      SdNavSection(
        title: 'العمليات الميدانية',
        items: [
          if (_hasPermission('tasks'))
            SdNavItem(
              id: 'ftth_tasks',
              label: 'مهام التوصيل',
              icon: IconsaxPlusBold.wifi,
              group: SdGroup.field,
              onTap: () => navigateToPage(const FtthTasksPage()),
            ),
          if (_hasPermission('users'))
            SdNavItem(
              id: 'customer_search_connect',
              label: 'بحث مشترك — توصيل',
              icon: IconsaxPlusBold.user_search,
              group: SdGroup.field,
              onTap: () => navigateToPage(const CustomerSearchConnectPage()),
            ),
          if (_hasPermission('users'))
            SdNavItem(
              id: 'customer_hub',
              label: 'تسجيل مشترك جديد',
              icon: IconsaxPlusBold.user_add,
              group: SdGroup.field,
              onTap: () =>
                  navigateToPage(CustomerHubPage(authToken: currentToken)),
            ),
          if (_hasPermission('quick_search'))
            SdNavItem(
              id: 'quick_search',
              label: 'البحث السريع',
              icon: IconsaxPlusBold.search_normal_1,
              group: SdGroup.field,
              onTap: () => navigateToPage(
                QuickSearchUsersPage(
                  authToken: currentToken,
                  activatedBy: widget.username,
                  hasServerSavePermission: hasServerSavePermission(),
                  hasWhatsAppPermission: hasWhatsAppPermission(),
                  isAdminFlag: isAdmin,
                  importantFtthApiPermissions: _getImportantPermissions(),
                ),
              ),
            ),
          if (_hasPermission('users'))
            SdNavItem(
              id: 'users',
              label: 'المشتركين',
              icon: IconsaxPlusBold.profile_2user,
              group: SdGroup.field,
              onTap: () => navigateToPage(
                UsersPage(
                  authToken: currentToken,
                  activatedBy: widget.username,
                  hasServerSavePermission: hasServerSavePermission(),
                  hasWhatsAppPermission: hasWhatsAppPermission(),
                  isAdminFlag: isAdmin,
                  importantFtthApiPermissions: _getImportantPermissions(),
                ),
              ),
            ),
          // إدارة راوترات المستخدمين (GenieACS)
          if (_hasPermission('routers'))
            SdNavItem(
              id: 'routers',
              label: 'إدارة الراوترات',
              icon: IconsaxPlusBold.cpu,
              group: SdGroup.field,
              onTap: () => navigateToPage(PlatformWebView(
                url: 'http://187.124.177.236:3000',
                title: 'إدارة راوترات المستخدمين',
              )),
            ),
        ],
      ),
      SdNavSection(
        title: 'الزونات والخرائط',
        items: [
          if (_hasPermission('zones'))
            SdNavItem(
              id: 'zones',
              label: 'إدارة الزونات',
              icon: IconsaxPlusBold.location,
              group: SdGroup.field,
              onTap: () => navigateToPage(ZonesPage(authToken: currentToken)),
            ),
          if (_hasPermission('zones'))
            SdNavItem(
              id: 'kml_zones_map',
              label: 'خريطة الزونات',
              icon: IconsaxPlusBold.map,
              group: SdGroup.field,
              onTap: () => navigateToPage(const KmlZonesMapPage()),
            ),
        ],
      ),
      SdNavSection(
        title: 'البيانات والتقارير',
        items: [
          if (_hasPermission('audit_logs'))
            SdNavItem(
              id: 'audit_logs',
              label: 'سجل التدقيق',
              icon: IconsaxPlusBold.clock,
              group: SdGroup.platform,
              onTap: () => navigateToPage(
                CaounterDetailsPage(
                  authToken: currentToken,
                  username: widget.username,
                ),
              ),
            ),
          if (_hasPermission('export'))
            SdNavItem(
              id: 'export',
              label: 'تصدير البيانات',
              icon: IconsaxPlusBold.export_1,
              group: SdGroup.platform,
              onTap: () => navigateToPage(ExportPage(authToken: currentToken)),
            ),
          if (_hasPermission('fetch_server_data'))
            SdNavItem(
              id: 'fetch_server_data',
              label: 'جلب بيانات الموقع',
              icon: IconsaxPlusBold.cloud_connection,
              group: SdGroup.platform,
              onTap: () => navigateToPage(
                  FetchServerDataPage(authToken: currentToken)),
            ),
          if (_hasPermission('local_storage'))
            SdNavItem(
              id: 'local_storage',
              label: 'التخزين الداخلي',
              icon: IconsaxPlusBold.box_1,
              group: SdGroup.platform,
              onTap: () => navigateToPage(
                LocalStoragePage(authToken: currentToken),
              ),
            ),
          // مشروع Dashboard (جلب بيانات الشارتات)
          if (_hasPermission('dashboard_project'))
            SdNavItem(
              id: 'dashboard_project',
              label: 'مشروع Dashboard',
              icon: IconsaxPlusBold.element_3,
              group: SdGroup.platform,
              onTap: () => navigateToPage(
                DashboardProjectPage(authToken: currentToken),
              ),
            ),
          if (_hasPermission('dashboard_project'))
            SdNavItem(
              id: 'superset',
              label: 'تحليلات Superset',
              icon: IconsaxPlusBold.chart,
              group: SdGroup.platform,
              onTap: () => navigateToPage(
                  DashboardProjectPage(authToken: currentToken)),
            ),
        ],
      ),
      SdNavSection(
        title: 'المالية',
        items: [
          if (_hasPermission('transactions'))
            SdNavItem(
              id: 'transactions',
              label: 'التحويلات',
              icon: IconsaxPlusBold.wallet_2,
              group: SdGroup.admin,
              onTap: _navigateToTransactionsWithPassword,
            ),
        ],
      ),
      SdNavSection(
        title: 'الواتساب',
        items: [
          if (_hasPermission('whatsapp_bulk_sender'))
            SdNavItem(
              id: 'whatsapp_bulk_sender',
              label: 'إرسال رسائل جماعية',
              icon: IconsaxPlusBold.send_2,
              group: SdGroup.comms,
              onTap: () => navigateToPage(const WhatsAppBulkSenderPage()),
            ),
          if (_hasPermission('whatsapp_settings'))
            SdNavItem(
              id: 'whatsapp_settings',
              label: 'مركز الواتساب',
              icon: IconsaxPlusBold.mobile,
              group: SdGroup.comms,
              onTap: () => navigateToPage(const WhatsAppSettingsHubPage()),
            ),
        ],
      ),
    ];
    // إخفاء الأقسام الفارغة (حسب الصلاحيات).
    return sections.where((sec) => sec.items.isNotEmpty).toList();
  }

  /// تذييل القائمة: تنبيه «لا توجد صلاحيات» عند غياب كل الصلاحيات
  /// (نفس شرط الدرج السابق).
  List<SdNavItem> _navFooter() {
    const keys = [
      'users', 'subscriptions', 'tasks', 'zones', 'accounts',
      'account_records', 'export', 'agents', 'expiring_soon', 'quick_search',
      'google_sheets', 'audit_logs', 'whatsapp', 'wallet_balance',
      'whatsapp_link', 'whatsapp_settings', 'plans_bundles', 'local_storage',
      'server_data', 'dashboard_project', 'fetch_server_data',
    ];
    final none = keys.every((k) => !_hasPermission(k));
    if (!none) return const [];
    return const [
      SdNavItem(
        id: 'no_permissions',
        label: 'لا توجد صلاحيات متاحة',
        hint: 'يرجى التواصل مع المدير لمنح الصلاحيات',
        icon: IconsaxPlusLinear.lock,
        group: SdGroup.comms,
        enabled: false,
      ),
    ];
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط التنقل السفلي (للموبايل فقط — screenWidth <= 700)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildBottomNav() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: SdColors.primary,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white54,
      currentIndex: 0,
      selectedFontSize: 11,
      unselectedFontSize: 10,
      elevation: 8,
      onTap: (index) {
        if (index == 0) return; // الرئيسية — نحن عليها بالفعل
        if (index == 1 && _hasPermission('subscriptions')) {
          navigateToPage(SubscriptionsPage(
            authToken: currentToken,
            activatedBy: widget.username,
            hasServerSavePermission: hasServerSavePermission(),
            hasWhatsAppPermission: hasWhatsAppPermission(),
            isAdminFlag: isAdmin,
            importantFtthApiPermissions: _getImportantPermissions(),
          ));
        } else if (index == 2 && _hasPermission('account_records')) {
          navigateToPage(AccountRecordsPage(
            authToken: currentToken,
            activatedBy: widget.username,
            permissions: getAllPermissions(),
            firstSystemUsername: widget.firstSystemUsername,
            firstSystemDepartment: widget.firstSystemDepartment,
            firstSystemCenter: widget.firstSystemCenter,
          ));
        } else if (index == 3) {
          _scaffoldKey.currentState?.openDrawer();
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_rounded),
          label: 'الرئيسية',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.wifi_rounded),
          label: 'الاشتراكات',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.receipt_long_rounded),
          label: 'التسديدات',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.menu_rounded),
          label: 'القائمة',
        ),
      ],
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
              color: SdColors.surface,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: SdColors.cardEdge, width: 2.0),
              boxShadow: SdDepth.raised(depth: SdDepth.hero),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // حلقة خارجية كبيرة - تركوازي فاتح
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      SdColors.accent.withValues(alpha: 0.25),
                    ),
                  ),
                ),
                // حلقة وسطى - تركوازي
                SizedBox(
                  width: 60,
                  height: 60,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      SdColors.accent.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                // حلقة داخلية أساسية - تركوازي
                const SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      SdColors.accent,
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
                        color: SdColors.warning.withValues(alpha: 0.4),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    IconsaxPlusBold.verify,
                    color: SdColors.warning,
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
              color: SdColors.ink,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'يرجى الانتظار لحظات',
            style: TextStyle(
              fontSize: isLargeScreen ? 14 : 12,
              fontWeight: FontWeight.w500,
              color: SdColors.muted,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  // ========== البحث السريع في الشاشة الرئيسية ==========

  String _toWestern(String s) {
    const ea = '٠١٢٣٤٥٦٧٨٩';
    const pe = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final c in s.split('')) {
      final i1 = ea.indexOf(c);
      if (i1 != -1) { b.write(i1); continue; }
      final i2 = pe.indexOf(c);
      if (i2 != -1) { b.write(i2); continue; }
      b.write(c);
    }
    return b.toString();
  }

  Future<void> _fetchSearchZones() async {
    try {
      final r = await AuthService.instance.authenticatedRequest(
        'GET', 'https://api.ftth.iq/api/locations/zones',
      );
      if (r.statusCode == 200 && mounted) {
        final data = jsonDecode(r.body);
        final items = List<dynamic>.from(data['items'] as List? ?? []);
        items.sort((a, b) {
          final sa = a['self']?['displayValue']?.toString().trim() ?? '';
          final sb = b['self']?['displayValue']?.toString().trim() ?? '';
          final re = RegExp(r'^(\D*)(\d+)?');
          final ma = re.firstMatch(sa), mb = re.firstMatch(sb);
          final cmp = (ma?.group(1) ?? '').toLowerCase().compareTo((mb?.group(1) ?? '').toLowerCase());
          if (cmp != 0) return cmp;
          final na = int.tryParse(ma?.group(2) ?? ''), nb = int.tryParse(mb?.group(2) ?? '');
          if (na != null && nb != null && na != nb) return na.compareTo(nb);
          return sa.toLowerCase().compareTo(sb.toLowerCase());
        });
        setState(() { _searchZones..clear()..addAll(items); });
      }
    } catch (_) {}
  }

  void _onSearchQueryChanged() {
    _searchDebounce?.cancel();
    final name = _toWestern(_searchNameCtrl.text).trim();
    final phone = _toWestern(_searchPhoneCtrl.text).replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (name.isEmpty && phone.isEmpty) {
      setState(() { _searchDone = false; _searchLoading = false; _searchWaiting = false; _searchResults.clear(); _searchTotal = 0; });
      return;
    }
    setState(() => _searchWaiting = true);
    _searchDebounce = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      // تحقق مرة أخرى بعد الانتظار — قد يكون المستخدم مسح النص
      final n2 = _toWestern(_searchNameCtrl.text).trim();
      final p2 = _toWestern(_searchPhoneCtrl.text).replaceAll(RegExp(r'[^0-9+]'), '').trim();
      if (n2.isEmpty && p2.isEmpty) {
        setState(() { _searchDone = false; _searchLoading = false; _searchWaiting = false; _searchResults.clear(); _searchTotal = 0; });
        return;
      }
      setState(() { _searchPage = 1; _searchDone = true; _searchWaiting = false; });
      _performQuickSearch();
    });
  }

  void _onSearchScroll() {
    if (!_searchDone || _searchLoadingMore || _searchLoading) return;
    if ((_searchPage * 25) >= _searchTotal) return;
    if (_searchScrollCtrl.position.pixels >= _searchScrollCtrl.position.maxScrollExtent - 200) {
      setState(() { _searchPage++; _searchLoadingMore = true; });
      _performQuickSearch(append: true);
    }
  }

  Future<void> _performQuickSearch({bool append = false}) async {
    final name = _toWestern(_searchNameCtrl.text).trim();
    final phone = _toWestern(_searchPhoneCtrl.text).replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (name.isEmpty && phone.isEmpty) {
      if (!append) setState(() { _searchResults.clear(); _searchTotal = 0; });
      return;
    }
    if (phone.isEmpty && name.isNotEmpty && name.length < 2) return;
    final phoneDigits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (name.isEmpty && phoneDigits.isNotEmpty && phoneDigits.length < 7) return;

    final seq = ++_searchSeq;
    if (!append) setState(() { _searchLoading = true; if (_searchPage == 1) _searchResults.clear(); });

    try {
      var url = 'https://api.ftth.iq/api/customers?pageSize=25&pageNumber=$_searchPage&sortCriteria.property=self.displayValue&sortCriteria.direction=asc';
      if (name.isNotEmpty) url += '&name=${Uri.encodeQueryComponent(name)}';
      if (phone.isNotEmpty) url += '&phone=${Uri.encodeQueryComponent(phone)}';
      if (_searchZoneId.isNotEmpty) url += '&zoneId=$_searchZoneId';

      final r = await AuthService.instance.authenticatedRequest('GET', url);
      if (!mounted || seq < _lastSearchSeq) return;

      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final items = List<dynamic>.from(data['items'] as List? ?? []);
        if (items.isNotEmpty) {
        }
        setState(() {
          _lastSearchSeq = seq;
          _searchTotal = data['totalCount'] ?? 0;
          if (append) { _searchResults.addAll(items); } else { _searchResults..clear()..addAll(items); }
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('انتهت جلسة المستخدم')
            ? 'انتهت الجلسة — يرجى إعادة تسجيل الدخول'
            : 'خطأ في البحث — تحقق من الاتصال';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: SdColors.danger, duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      if (mounted) setState(() { _searchLoading = false; _searchLoadingMore = false; _searchWaiting = false; });
    }
  }

  void _fetchSearchZone(String customerId) {
    if (_searchZoneCache.containsKey(customerId) || _searchZoneFetching.contains(customerId)) return;
    _searchZoneFetching.add(customerId);
    AuthService.instance.authenticatedRequest('GET',
      'https://admin.ftth.iq/api/customers/subscriptions?customerId=$customerId',
    ).then((r) {
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        final items = data['items'] as List? ?? [];
        if (items.isNotEmpty) {
          final zone = items[0]['zone']?['displayValue']?.toString() ?? '';
          if (zone.isNotEmpty && mounted) {
            setState(() => _searchZoneCache[customerId] = zone);
          }
        }
      }
      _searchZoneFetching.remove(customerId);
    }).catchError((_) { _searchZoneFetching.remove(customerId); });
  }

  void _resetQuickSearch() {
    setState(() {
      _searchNameCtrl.clear();
      _searchPhoneCtrl.clear();
      _searchZoneId = '';
      _searchPage = 1;
      _searchResults.clear();
      _searchTotal = 0;
      _searchDone = false;
    });
  }

  Widget _buildQuickSearchSection(bool isLargeScreen) {
    final r = context.responsive;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobileLayout = screenWidth < 600;
    final bdr = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(r.buttonRadius)), borderSide: const BorderSide(color: SdColors.cardEdge, width: 1.5));
    final fbdr = OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(r.buttonRadius)), borderSide: const BorderSide(color: SdColors.primary, width: 2));
    final lbl = TextStyle(fontSize: r.bodySize, fontWeight: FontWeight.w700, color: SdColors.muted);
    final searchPad = r.scaled(6, 8, 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // بطاقة البحث
        Container(
          padding: EdgeInsets.fromLTRB(searchPad, searchPad + 2, searchPad, searchPad - 2),
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.sm),
            border: Border.all(color: SdColors.cardEdge, width: 2),
            boxShadow: SdDepth.raised(),
          ),
          child: isMobileLayout
              // ═══ موبايل: حقلان عموديان (هاتف + اسم) ═══
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // رقم الهاتف
                    TextField(
                      controller: _searchPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      textAlign: TextAlign.right,
                      onChanged: (_) { setState(() {}); _onSearchQueryChanged(); },
                      onSubmitted: (_) { setState(() { _searchPage = 1; _searchDone = true; }); _performQuickSearch(); },
                      decoration: InputDecoration(
                        labelText: 'رقم الهاتف',
                        labelStyle: lbl,
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        floatingLabelAlignment: FloatingLabelAlignment.center,
                        filled: true, fillColor: SdColors.surface, isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: r.scaled(10, 12, 14)),
                        prefixIcon: Icon(Icons.phone, color: SdColors.primary, size: r.iconSizeSmall),
                        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        suffixIcon: _searchPhoneCtrl.text.isNotEmpty
                            ? IconButton(tooltip: 'مسح', icon: const Icon(Icons.clear, size: 16, color: SdColors.danger), onPressed: _resetQuickSearch, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                            : IconButton(tooltip: 'لصق', icon: const Icon(Icons.content_paste_go, size: 16, color: SdColors.primary), onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                if (data?.text != null && data!.text!.isNotEmpty && mounted) {
                                  final cleaned = _toWestern(data.text!).replaceAll(RegExp(r'[^0-9+]'), '').trim();
                                  if (cleaned.isEmpty) return;
                                  _searchPhoneCtrl.text = cleaned;
                                  _searchPhoneCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _searchPhoneCtrl.text.length));
                                  setState(() {}); _onSearchQueryChanged();
                                }
                              }, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                        enabledBorder: bdr,
                        focusedBorder: fbdr,
                      ),
                      style: TextStyle(fontSize: r.bodySize),
                    ),
                    const SizedBox(height: 8),
                    // اسم المشترك
                    TextField(
                      controller: _searchNameCtrl,
                      textAlign: TextAlign.right,
                      textInputAction: TextInputAction.search,
                      onChanged: (_) { setState(() {}); _onSearchQueryChanged(); },
                      onSubmitted: (_) { setState(() { _searchPage = 1; _searchDone = true; }); _performQuickSearch(); },
                      decoration: InputDecoration(
                        labelText: 'اسم المشترك',
                        labelStyle: lbl,
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        floatingLabelAlignment: FloatingLabelAlignment.center,
                        filled: true, fillColor: SdColors.surface, isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: r.scaled(10, 12, 14)),
                        prefixIcon: Icon(Icons.person_search, color: SdColors.primary, size: r.iconSizeMedium),
                        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        suffixIcon: (_searchLoading && _searchNameCtrl.text.isNotEmpty)
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : _searchWaiting
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))
                                : (_searchNameCtrl.text.isNotEmpty
                                    ? IconButton(tooltip: 'مسح', icon: const Icon(Icons.clear, size: 16, color: SdColors.danger), onPressed: _resetQuickSearch, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                                    : IconButton(tooltip: 'لصق', icon: const Icon(Icons.content_paste_go, size: 16, color: SdColors.primary), onPressed: () async {
                                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                                        if (data?.text != null && data!.text!.isNotEmpty && mounted) {
                                          _searchNameCtrl.text = _toWestern(data.text!).trim();
                                          _searchNameCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _searchNameCtrl.text.length));
                                          setState(() {}); _onSearchQueryChanged();
                                        }
                                      }, padding: EdgeInsets.zero, constraints: const BoxConstraints())),
                        enabledBorder: bdr,
                        focusedBorder: fbdr,
                      ),
                      style: TextStyle(fontSize: r.bodySize),
                    ),
                  ],
                )
              // ═══ ديسكتوب: صف أفقي (منطقة + اسم + هاتف) ═══
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // المنطقة — حقل بحث مع تصفية
                    SizedBox(
                      width: r.scaled(140, 180, 220),
                      child: Autocomplete<Map<String, dynamic>>(
                        optionsBuilder: (textEditingValue) {
                          final query = textEditingValue.text.trim().toLowerCase();
                          final typed = _searchZones.cast<Map<String, dynamic>>();
                          if (query.isEmpty) return typed;
                          return typed.where((z) {
                            final name = (z['self']?['displayValue'] ?? '').toString().toLowerCase();
                            return name.contains(query);
                          });
                        },
                        displayStringForOption: (z) => z['self']?['displayValue'] ?? '',
                        onSelected: (z) {
                          setState(() => _searchZoneId = z['self']?['id']?.toString() ?? '');
                          if (_searchNameCtrl.text.isNotEmpty || _searchPhoneCtrl.text.isNotEmpty) _onSearchQueryChanged();
                        },
                        fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              labelText: 'المنطقة',
                              labelStyle: lbl,
                              floatingLabelBehavior: FloatingLabelBehavior.always,
                              floatingLabelAlignment: FloatingLabelAlignment.center,
                              filled: true, fillColor: SdColors.surface, isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: r.scaled(10, 12, 14)),
                              prefixIcon: Icon(Icons.location_on, color: SdColors.primary, size: r.iconSizeSmall),
                              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                              suffixIcon: controller.text.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'مسح المنطقة',
                                      icon: const Icon(Icons.clear, size: 16, color: SdColors.danger),
                                      onPressed: () {
                                        controller.clear();
                                        setState(() => _searchZoneId = '');
                                        if (_searchNameCtrl.text.isNotEmpty || _searchPhoneCtrl.text.isNotEmpty) _onSearchQueryChanged();
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    )
                                  : null,
                              enabledBorder: bdr,
                              focusedBorder: fbdr,
                            ),
                            style: TextStyle(fontSize: r.bodySize),
                            onChanged: (v) {
                              if (v.isEmpty) setState(() => _searchZoneId = '');
                            },
                          );
                        },
                        optionsViewBuilder: (ctx, onSelected, options) {
                          return Align(
                            alignment: Alignment.topRight,
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(10),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: 250, maxWidth: r.scaled(140, 180, 220)),
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (ctx, i) {
                                    final z = options.elementAt(i);
                                    final name = z['self']?['displayValue'] ?? '';
                                    return InkWell(
                                      onTap: () => onSelected(z),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        child: Text(name, style: const TextStyle(fontSize: 13), textAlign: TextAlign.right),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // اسم المشترك
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchNameCtrl,
                        textAlign: TextAlign.right,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) { setState(() {}); _onSearchQueryChanged(); },
                        onSubmitted: (_) { setState(() { _searchPage = 1; _searchDone = true; }); _performQuickSearch(); },
                        decoration: InputDecoration(
                          labelText: 'اسم المشترك',
                          labelStyle: lbl,
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          floatingLabelAlignment: FloatingLabelAlignment.center,
                          filled: true, fillColor: SdColors.surface, isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: r.scaled(10, 12, 14)),
                          prefixIcon: Icon(Icons.person_search, color: SdColors.primary, size: r.iconSizeMedium),
                          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          suffixIcon: (_searchLoading && _searchNameCtrl.text.isNotEmpty)
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : _searchWaiting
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5))
                                  : (_searchNameCtrl.text.isNotEmpty
                                      ? IconButton(tooltip: 'مسح', icon: const Icon(Icons.clear, size: 16, color: SdColors.danger), onPressed: _resetQuickSearch, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                                      : IconButton(tooltip: 'لصق', icon: const Icon(Icons.content_paste_go, size: 16, color: SdColors.primary), onPressed: () async {
                                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                                          if (data?.text != null && data!.text!.isNotEmpty && mounted) {
                                            _searchNameCtrl.text = _toWestern(data.text!).trim();
                                            _searchNameCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _searchNameCtrl.text.length));
                                            setState(() {}); _onSearchQueryChanged();
                                          }
                                        }, padding: EdgeInsets.zero, constraints: const BoxConstraints())),
                          enabledBorder: bdr,
                          focusedBorder: fbdr,
                        ),
                        style: TextStyle(fontSize: r.bodySize),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // رقم الهاتف
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        textAlign: TextAlign.right,
                        onChanged: (_) { setState(() {}); _onSearchQueryChanged(); },
                        onSubmitted: (_) { setState(() { _searchPage = 1; _searchDone = true; }); _performQuickSearch(); },
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف',
                          labelStyle: lbl,
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          floatingLabelAlignment: FloatingLabelAlignment.center,
                          filled: true, fillColor: SdColors.surface, isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: r.scaled(10, 12, 14)),
                          prefixIcon: Icon(Icons.phone, color: SdColors.primary, size: r.iconSizeSmall),
                          suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                          suffixIcon: _searchPhoneCtrl.text.isNotEmpty
                              ? IconButton(tooltip: 'مسح', icon: const Icon(Icons.clear, size: 16, color: SdColors.danger), onPressed: _resetQuickSearch, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                              : IconButton(tooltip: 'لصق', icon: const Icon(Icons.content_paste_go, size: 16, color: SdColors.primary), onPressed: () async {
                                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                                  if (data?.text != null && data!.text!.isNotEmpty && mounted) {
                                    final cleaned = _toWestern(data.text!).replaceAll(RegExp(r'[^0-9+]'), '').trim();
                                    if (cleaned.isEmpty) return;
                                    _searchPhoneCtrl.text = cleaned;
                                    _searchPhoneCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _searchPhoneCtrl.text.length));
                                    setState(() {}); _onSearchQueryChanged();
                                  }
                                }, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                          enabledBorder: bdr,
                          focusedBorder: fbdr,
                        ),
                        style: TextStyle(fontSize: r.bodySize),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (_searchNameCtrl.text.isNotEmpty || _searchPhoneCtrl.text.isNotEmpty || _searchZoneId.isNotEmpty)
                      IconButton(
                        tooltip: 'مسح الكل',
                        icon: Icon(Icons.clear_all, color: SdColors.danger, size: r.iconSizeMedium),
                        onPressed: _resetQuickSearch,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                  ],
                ),
        ),

        // نتائج البحث
        if (_searchLoading)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(SdColors.primary))),
                SizedBox(width: 12),
                Text('جاري البحث...', style: TextStyle(color: SdColors.primary, fontWeight: FontWeight.w600)),
              ],
            ),
          )
        else if (_searchDone && _searchResults.isEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            child: const Text('لا توجد نتائج', style: TextStyle(color: SdColors.faint, fontSize: 14)),
          )
        else if (_searchResults.isNotEmpty) ...[
          // عداد النتائج
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: SdColors.primary, borderRadius: BorderRadius.circular(SdRadius.xs)),
            child: Row(
              children: [
                const Icon(Icons.manage_search, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text('$_searchTotal مستخدم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // قائمة النتائج
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: ListView.builder(
              controller: _searchScrollCtrl,
              shrinkWrap: true,
              itemCount: _searchResults.length + (_searchLoadingMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (_searchLoadingMore && i == _searchResults.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))),
                  );
                }
                final user = _searchResults[i];
                final userName = user['self']?['displayValue'] ?? 'غير متوفر';
                final userId = user['self']?['id']?.toString() ?? '';
                // جلب المنطقة من API أو من الكاش
                var zone = user['zone']?['displayValue']?.toString() ?? '';
                if (zone.isEmpty && userId.isNotEmpty) {
                  zone = _searchZoneCache[userId] ?? '';
                  if (zone.isEmpty) _fetchSearchZone(userId);
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  elevation: 2,
                  color: SdColors.surface,
                  surfaceTintColor: SdColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: SdColors.cardEdge, width: 1)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      navigateToPage(UserDetailsPage(
                        authToken: currentToken,
                        userId: userId,
                        userName: userName,
                        userPhone: user['primaryContact']?['mobile'] ?? '',
                        activatedBy: widget.username,
                        hasServerSavePermission: _hasPermission('server_save'),
                        hasWhatsAppPermission: _hasPermission('whatsapp'),
                        isAdminFlag: isAdmin,
                        userRoleHeader: '0',
                        clientAppHeader: '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
                        importantFtthApiPermissions: _getImportantPermissions(),
                      ));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [SdColors.primary, SdColors.primaryLight]),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.person, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: SdColors.primary), overflow: TextOverflow.ellipsis),
                                if (zone.isNotEmpty)
                                  Text(zone, style: const TextStyle(fontSize: 11.5, color: SdColors.muted), overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: SdColors.faint, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
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
                horizontal: screenWidth < 500 ? 8 : context.responsive.contentPaddingH,
                vertical: isLargeScreen ? 16 : 6,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: context.responsive.maxContentWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // بطاقة العملاء الحديثة في الأعلى فقط
                      _buildTopStatsRow(isLargeScreen),
                      SizedBox(height: screenWidth < 500 ? 6 : 12),
                      // كروت المحفظة في الأعلى (للمديرين فقط أو المصرح لهم)
                      if (hasWalletBalancePermission())
                        _buildWalletCards(isLargeScreen),

                      if (hasWalletBalancePermission())
                        SizedBox(height: screenWidth < 500 ? 6 : 10),

                      // بطاقة محفظة عضو الفريق تظهر دائماً إذا كانت المحفظة متوفرة حتى بدون صلاحية المحفظة العامة
                      if (!hasWalletBalancePermission() &&
                          hasTeamMemberWallet) ...[
                        _buildTeamMemberWalletCard(),
                        SizedBox(height: screenWidth < 500 ? 6 : 10),
                      ],

                      // شريط الأدوات السريعة المحدث
                      _buildQuickActionsBar(isLargeScreen, screenWidth),
                      SizedBox(height: screenWidth < 500 ? 6 : 10),
                      // البحث السريع عن المشتركين
                      _buildQuickSearchSection(isLargeScreen),
                      SizedBox(
                        height: screenWidth < 500 ? 30 : 80,
                      ), // مسافة سفلية
                    ],
                  ),
                ),
              ),
            ),
            // تم إزالة بطاقة "آخر تحديث" بناءً على طلب المستخدم
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
    final isPhone = screenWidth < 500;

    // فاصل بين البطاقات يتأقلم مع حجم الشاشة
    final gap = screenWidth < 360 ? 6.0 : (screenWidth < 420 ? 8.0 : 12.0);

    final cards = [
      _buildCleanStatCard(
        label: 'إجمالي العملاء',
        value: total,
        icon: IconsaxPlusBold.people,
        color: SdColors.info,
        changeText: '100%',
        isPositive: true,
      ),
      _buildCleanStatCard(
        label: 'نشط',
        value: active,
        icon: IconsaxPlusBold.tick_circle,
        color: SdColors.success,
        changeText: total > 0
            ? '${(active / total * 100).toStringAsFixed(1)}%'
            : '0%',
        isPositive: true,
      ),
      _buildCleanStatCard(
        label: 'منتهي',
        value: inactive,
        icon: IconsaxPlusBold.close_circle,
        color: SdColors.danger,
        changeText: total > 0
            ? '${(inactive / total * 100).toStringAsFixed(1)}%'
            : '0%',
        isPositive: false,
      ),
      _buildCleanStatCard(
        label: 'ينتهي قريباً',
        value: _expiringSoonCount,
        icon: IconsaxPlusBold.timer_1,
        color: SdColors.warning,
        changeText: total > 0
            ? '${(_expiringSoonCount / total * 100).toStringAsFixed(1)}%'
            : '0%',
        isPositive: false,
      ),
    ];

    // على الهاتف: شبكة 2×2 بدل صف واحد مزدحم
    if (isPhone) {
      return Column(
        children: [
          Row(children: [
            Expanded(child: cards[0]),
            SizedBox(width: gap),
            Expanded(child: cards[1]),
          ]),
          SizedBox(height: gap),
          Row(children: [
            Expanded(child: cards[2]),
            SizedBox(width: gap),
            Expanded(child: cards[3]),
          ]),
        ],
      );
    }

    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: cards[i]),
        ],
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

    final screenWidth = MediaQuery.of(context).size.width;
    final isPhone = screenWidth < 500;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;

        // ═══ تصميم مدمج للهاتف — أفقي بدون دائرة ═══
        if (isPhone) {
          return ValueListenableBuilder<bool>(
            valueListenable: hoverNotifier,
            builder: (context, isHovered, _) {
              return AnimatedBuilder(
                animation: _counterAnimationController,
                builder: (context, _) {
                  final curvedVal = Curves.easeOutExpo.transform(
                    _counterAnimationController.value,
                  );
                  final displayValue = (value * curvedVal).round();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: SdColors.surface,
                      borderRadius: BorderRadius.circular(SdRadius.sm),
                      border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
                      boxShadow: SdDepth.raised(
                        edge: SdColors.cardEdge,
                        depth: SdDepth.card,
                        glow: color.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      children: [
                        // أيقونة ملونة
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(icon, color: color, size: 18),
                        ),
                        const SizedBox(width: 8),
                        // الرقم + التسمية
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _formatCounterNumber(displayValue),
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: SdColors.ink,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: SdColors.muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // النسبة
                        Text(
                          changeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        }

        // ═══ التصميم الأصلي للشاشات الكبيرة — دائرة + عداد ═══
        // أحجام متجاوبة حسب عرض البطاقة المتاح
        final circleSize = (cardWidth * 0.65).clamp(45.0, 100.0);
        final valueFontSize = (cardWidth * 0.13).clamp(11.0, 22.0);
        final pctFontSize = (cardWidth * 0.07).clamp(6.0, 12.0);
        final labelFontSize = (cardWidth * 0.085).clamp(7.0, 13.0);
        final iconSize = (cardWidth * 0.09).clamp(8.0, 16.0);
        final vPad = cardWidth < 100 ? 6.0 : (cardWidth < 120 ? 8.0 : (cardWidth < 200 ? 10.0 : 14.0));
        final hPad = cardWidth < 100 ? 4.0 : (cardWidth < 120 ? 6.0 : (cardWidth < 200 ? 8.0 : 12.0));

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
                    color: SdColors.surface,
                    borderRadius:
                        BorderRadius.circular(cardWidth < 100 ? 12 : 18),
                    border: Border.all(
                      color: isHovered
                          ? color.withValues(alpha: 0.35)
                          : SdColors.cardEdge,
                      width: isHovered ? 2.5 : 2.0,
                    ),
                    boxShadow: SdDepth.raised(
                      edge: SdColors.cardEdge,
                      depth: isHovered ? SdDepth.hero : SdDepth.card,
                      glow: isHovered
                          ? color.withValues(alpha: 0.22)
                          : const Color(0x591A237E),
                    ),
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
                                              color: SdColors.ink,
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
                                color: SdColors.ink,
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
            border: Border.all(color: SdColors.edge, width: 2.0),
            boxShadow: [
              BoxShadow(
                color: SdColors.info.withValues(alpha: 0.06),
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
                            color: SdColors.neutralBase,
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
                              color: SdColors.info,
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
            color: SdColors.info.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SdColors.ground, width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: SdColors.info,
            ),
          ),
        ),
      ],
    );
  }

  // شريط الأد��ات السريعة المحدث
  Widget _buildQuickActionsBar(bool isLargeScreen, double screenWidth) {
    final items = _buildQuickActionItems(screenWidth);
    final itemCount = items.length;
    if (itemCount == 0) return const SizedBox.shrink();

    int crossAxisCount;
    double childAspectRatio;

    if (screenWidth < 380) {
      // هاتف صغير — عمودين مدمجين
      crossAxisCount = 2;
      childAspectRatio = 3.2;
    } else if (screenWidth < 600) {
      // هاتف — عمودين مدمجين
      crossAxisCount = 2;
      childAspectRatio = 3.4;
    } else if (screenWidth < 900) {
      // تابلت — صف واحد
      crossAxisCount = itemCount;
      childAspectRatio = 3.2;
    } else {
      // لابتوب/ديسكتوب — صف واحد مريح
      crossAxisCount = itemCount;
      childAspectRatio = 3.5;
    }

    final isPhone = screenWidth < 500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // فاصل فاخر مزخرف — مخفي على الهاتف لتوفير المساحة
        if (!isPhone)
          Container(
            margin: EdgeInsets.symmetric(
              horizontal: screenWidth < 600 ? 16 : 32,
              vertical: screenWidth < 600 ? 6 : 8,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1.5,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Colors.transparent,
                          SdColors.accentTintEdge,
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
                    color: SdColors.accentTint,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: SdColors.accentTintEdge,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: SdColors.accent.withValues(alpha: 0.1),
                        blurRadius: 8,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    IconsaxPlusBold.element_2,
                    size: 16,
                    color: SdColors.accent,
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1.5,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          SdColors.accentTintEdge,
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
        SizedBox(height: isPhone ? 2 : (screenWidth < 600 ? 6 : 8)),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          mainAxisSpacing: isPhone ? 4 : 8,
          crossAxisSpacing: isPhone ? 4 : 8,
          children: items,
        ),
      ],
    );
  }

  List<Widget> _buildQuickActionItems(double screenWidth) {
    final actions = <Widget>[];

    // البحث السريع — تم نقله إلى القائمة الجانبية

    // الاشتراكات - أداة سريعة
    if (_hasPermission('subscriptions')) {
      actions.add(
        _buildQuickActionItem(
          'الاشتراكات',
          IconsaxPlusBold.wifi_square,
          SdStatus.info.tone,
          () => navigateToPage(SubscriptionsPage(
            authToken: currentToken,
            activatedBy: widget.username,
            hasServerSavePermission: hasServerSavePermission(),
            hasWhatsAppPermission: hasWhatsAppPermission(),
            isAdminFlag: isAdmin,
            importantFtthApiPermissions: _getImportantPermissions(),
          )),
        ),
      );
    }

    // التذاكر - أداة سريعة
    if (_hasPermission('tasks')) {
      actions.add(_buildTasksActionItem());
    }

    // المنتهي قريباً - أداة سريعة
    if (_hasPermission('expiring_soon')) {
      actions.add(
        _buildQuickActionItem(
          'المنتهي قريباً',
          IconsaxPlusBold.timer_1,
          SdStatus.danger.tone,
          () => navigateToPage(
            ExpiringSoonPage(
              activatedBy: widget.username,
              hasServerSavePermission: hasServerSavePermission(),
              hasWhatsAppPermission: hasWhatsAppPermission(),
              isAdminFlag: isAdmin,
              importantFtthApiPermissions: _getImportantPermissions(),
            ),
          ),
        ),
      );
    }

    // سجلات الحسابات - أداة سريعة (صلاحية مستقلة account_records)
    if (_hasPermission('account_records')) {
      actions.add(
        _buildQuickActionItem(
          'سجلات الحسابات',
          IconsaxPlusBold.book_1,
          SdGroup.field.tone,
          () => navigateToPage(
            AccountRecordsPage(
              authToken: currentToken,
              activatedBy: widget.username,
              permissions: getAllPermissions(),
              firstSystemUsername: widget.firstSystemUsername,
              firstSystemDepartment: widget.firstSystemDepartment,
              firstSystemCenter: widget.firstSystemCenter,
            ),
          ),
        ),
      );
    }

    // التسديدات اليومية - أداة سريعة (نفس صلاحية account_records)
    if (_hasPermission('account_records')) {
      actions.add(
        _buildQuickActionItem(
          'التسديدات اليومية',
          IconsaxPlusBold.money_send,
          SdStatus.success.tone,
          () => navigateToPage(
            DailySettlementPage(
              authToken: currentToken,
              activatedBy: widget.username,
              permissions: getAllPermissions(),
            ),
          ),
        ),
      );
    }

    // صفحة الشركة - فتح لوحة تحكم FTTH في WebView
    if (_hasPermission('company_dashboard')) {
      actions.add(
        _buildQuickActionItem(
          'صفحة الشركة',
          IconsaxPlusBold.building_4,
          SdGroup.admin.tone,
          () => navigateToPage(const FtthCompanyPage()),
        ),
      );
    }

    return actions;
  }

  Widget _buildQuickActionItem(
    String title,
    IconData icon,
    SdTone tone,
    VoidCallback onTap,
  ) {
    final r = context.responsive;
    final phoneSm = MediaQuery.of(context).size.width < 500;
    final iconBoxSize = phoneSm ? 26.0 : r.scaled(30, 34, 38);
    final iconSz = phoneSm ? 15.0 : r.scaled(17, 20, 22);
    final textSz = phoneSm ? 12.0 : r.scaled(13, 15, 16);
    final hPad = phoneSm ? 6.0 : r.scaled(8, 10, 12);
    final vPad = phoneSm ? 6.0 : r.scaled(10, 12, 14);
    return SdRaised(
      onTap: () { if (mounted) onTap(); },
      radius: phoneSm ? SdRadius.sm : SdRadius.md,
      depth: SdDepth.button,
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tone.light, tone.base],
      ),
      edgeColor: tone.edge,
      glowColor: tone.edge.withValues(alpha: 0.45),
      semanticLabel: title,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // الأيقونة
            Container(
              width: iconBoxSize, height: iconBoxSize,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: iconSz, color: Colors.white),
            ),
            const SizedBox(width: 8),
            // النص
            Text(
              title,
              style: TextStyle(
                fontSize: textSz,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }

  // عنصر خاص لزر المهام مع شارة عددية
  Widget _buildTasksActionItem() {
    return ValueListenableBuilder<int>(
      valueListenable: BadgeService.instance.unreadNotifier,
      builder: (context, count, _) {
        final taskButton = _buildQuickActionItem(
          'تذاكر',
          IconsaxPlusBold.task_square,
          SdGroup.comms.tone,
          () {
            BadgeService.instance.clear();
            navigateToPage(TKTATsPage(authToken: currentToken));
          },
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            taskButton,
            if (count > 0)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: SdColors.danger,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(color: SdColors.dangerEdge, blurRadius: 5, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold, height: 1),
                  ),
                ),
              ),
          ],
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
          color: SdColors.primary,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _buildWalletCard(
          title: 'العمولة',
          value: commission,
          color: SdColors.success,
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
            color: SdColors.primaryLight,
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
            color: SdColors.primaryLight,
          ),
        ),
      ],
    );
  }

  Widget _buildWalletCard({
    required String title,
    required double value,
    required Color color,
  }) {
    // تصميم أفقي متناسق مع بطاقات الإحصائيات
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        // أحجام متجاوبة مع عرض البطاقة
        final isVeryCompact = cardWidth < 160;
        final isCompact = cardWidth < 240;
        final iconBoxSize = isVeryCompact ? 28.0 : (isCompact ? 32.0 : 38.0);
        final iconSize = isVeryCompact ? 15.0 : (isCompact ? 17.0 : 20.0);
        final valueFontSize = isVeryCompact ? 12.0 : (isCompact ? 14.0 : 18.0);
        final titleFontSize = isVeryCompact ? 8.0 : (isCompact ? 9.0 : 10.0);
        final hPadding = isVeryCompact ? 6.0 : (isCompact ? 8.0 : 12.0);
        final vPadding = isVeryCompact ? 6.0 : (isCompact ? 8.0 : 10.0);
        final stripHeight = isVeryCompact ? 28.0 : (isCompact ? 34.0 : 40.0);
        final cardRadius = isVeryCompact ? 10.0 : 14.0;

        return Container(
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(cardRadius),
            border: Border.all(
                color: SdColors.cardEdge,
                width: isVeryCompact ? 1.5 : 2.0),
            boxShadow: SdDepth.raised(
              edge: SdColors.cardEdge,
              depth: SdDepth.card,
              glow: color.withValues(alpha: 0.18),
            ),
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
                    color: SdColors.surface,
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
                                  color: SdColors.muted,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            SizedBox(height: isVeryCompact ? 2 : 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _animatedCount(
                                value,
                                TextStyle(
                                  color: SdColors.ink,
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
        border: Border.all(color: SdColors.edge, width: 2.0),
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
              color: SdColors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: SdColors.success.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Icon(
              IconsaxPlusBold.clock,
              color: SdColors.fieldLight,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'آخر تحديث: ${DateFormat('yyyy/MM/dd - HH:mm:ss').format(lastUpdateTime!)}',
            style: TextStyle(
              fontSize: isLargeScreen ? 13 : 11,
              color: SdColors.neutralBase,
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
// محفوظ خاملاً بعد توحيد الخلفية إلى SdColors.ground.
// ignore: unused_element
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
      debugPrint('❌ خطأ في تهيئة WebView');
      if (mounted) {
        setState(() {
          if (Platform.isWindows && e.toString().contains('WebView2')) {
            _error =
                'يتطلب Microsoft Edge WebView2 Runtime لعمل الواتساب.\n\nيرجى تحميله وتثبيته من موقع مايكروسوفت الرسمي.';
          } else {
            _error = 'خطأ في تحميل واتساب ويب';
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
      debugPrint('❌ خطأ في تهيئة Windows WebView');
      // إعادة رمي الخطأ ليتم التعامل معه في _initWeb
      throw Exception('Windows WebView2 initialization failed');
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
      debugPrint('❌ خطأ في تهيئة Flutter WebView');
      throw Exception('Flutter WebView initialization failed');
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
        ).showSnackBar(SnackBar(content: Text('فشل تسجيل الخروج')));
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
              backgroundColor: SdColors.warning,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح رابط التحميل');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر فتح رابط التحميل. يرجى البحث عن "Microsoft Edge WebView2 Runtime" وتحميله من موقع مايكروسوفت الرسمي.',
            ),
            backgroundColor: SdColors.warning,
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
              Icon(IconsaxPlusBold.warning_2, size: 48, color: SdColors.danger),
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
                        backgroundColor: SdColors.info,
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
      appBar: SdAppBar(title: 'تسجيل الدخول - WhatsApp Web', actions: [
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
        ]),
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
          color: SdColors.groundAlt,
          border: Border(top: BorderSide(color: SdColors.edge)),
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
                  color: _loggedIn ? SdColors.success : null,
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
