/// اسم الصفحة: الصفحة الرئيسية
/// وصف الصفحة: الصفحة الرئيسية للتطبيق تحتوي على الداشبورد والقوائم الرئيسية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:async'; // NEW
import 'dart:convert'; // لفكّ حقل details في طلبات الوكلاء
import 'package:flutter/material.dart';

import 'package:alsadara/pages/track_users_map_page.dart';
import '../task/task_list_screen.dart';
import '../services/fcm_token_service.dart';
import '../services/location_foreground_service.dart';
import 'dart:io' show Platform;
import 'hr_hub_page.dart';
import 'search_users_page.dart';
import 'users_page.dart';
import 'users_page_firebase.dart';
import 'users_page_vps.dart';
import '../ftth/core/home_page.dart' as ftth_home;
import '../services/dual_auth_service.dart';
import '../ftth/auth/cloudflare_gate_dialog.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math' as math; // NEW: for rotations
import 'aria_page.dart';
import '../utils/responsive_helper.dart';
import '../widgets/maintenance_messages_dialog.dart'; // إضافة حوار إعدادات الرسائل
import '../services/vps_auth_service.dart'; // ✅ خدمة VPS لتسجيل الخروج
import '../services/api/api_client.dart'; // ✅ ApiClient للتحقق من التوكن
import 'login/premium_login_page.dart'; // ✨ صفحة تسجيل الدخول الفخمة
import '../ftth/whatsapp/whatsapp_bottom_window.dart'; // WhatsApp floating button
import '../ftth/widgets/floating_toolbar.dart'; // شريط الأدوات العائم الموحد
import 'super_admin/super_admin_dashboard.dart'; // لوحة تحكم Super Admin
import 'company_diagnostics_page.dart'; // صفحة تشخيص الشركة
import 'company_settings_page.dart'; // إعدادات الشركة
import 'ftth/ftth_company_page.dart'; // صفحة الشركة
import 'settings/ftth_sync_settings_page.dart'; // إعدادات مزامنة FTTH
import 'super_admin/sadara_portal_page.dart'; // منصة الصدارة
import 'accounting/accounting_dashboard_page.dart'; // نظام المحاسبة
import '../inventory/inventory_page.dart'; // نظام المخازن
import '../sas_agent/sas_agent_page.dart'; // صفحة وكيل الساس (بوّابة /api/sas-agent)
import 'properties/properties_list_page.dart'; // سجل العقارات المستقل (بوّابة /api/properties)
import '../task/follow_up_page.dart'; // صفحة المتابعة
// import '../task/audit_dashboard_page.dart'; // داشبورد التدقيق — مخفي حالياً
// شاشتي - معاملات الفني
import 'my_dashboard_page.dart'; // شاشتي - لوحة الموظف الشخصية
import '../permissions/permissions.dart';
import 'chat/chat_rooms_page.dart';
import '../services/chat_service.dart';
import '../services/task_api_service.dart';
import '../services/sadara_api_service.dart'; // عدّ طلبات الوكلاء (منصة الصدارة)
import '../services/attendance_api_service.dart';
import '../widgets/update_dialog.dart'; // فحص التحديث التلقائي
import '../services/message_log_service.dart'; // التقرير اليومي
import 'iptv/iptv_subscribers_page.dart'; // صفحة مشتركي IPTV
import 'kml_zones_map_page.dart'; // خريطة الزونات
import 'announcements/announcements_page.dart'; // صفحة الإعلانات والتبليغات
import '../ftth/requests/customer_hub_page.dart'; // مشترك جديد (Hub)
import '../services/announcement_service.dart'; // خدمة الإعلانات
import '../services/notification_api_service.dart'; // خدمة الإشعارات API
import '../services/api/api_config.dart'; // إعدادات API
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
// تم نقل زر جلب بيانات الموقع إلى النظام الثاني

class HomePage extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;
  final String salary;
  final String? tenantId; // معرف الشركة
  final String? tenantCode; // كود الشركة
  final bool isSuperAdminMode; // هل دخل كـ Super Admin

  const HomePage({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
    required this.salary,
    this.tenantId,
    this.tenantCode,
    this.isSuperAdminMode = false,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  bool _isAdminUser = false;
  bool _isLoading = true;

  // الموقع — تردد ذكي حسب الحركة + Offline queue
  bool _isLocationActive = false;
  Timer? _locationTimer;
  double? _lastLat;
  double? _lastLng;
  int _currentInterval = 10;
  final List<Map<String, dynamic>> _offlineQueue = [];
  // حالة تسجيل دخول FTTH (النظام الثاني)
  bool _isFtthConnected = false;
  String? _ftthConnectedUsername;
  StreamSubscription<bool>? _ftthStateSubscription;
  // ===== عدادات الصفحة الرئيسية =====
  int _pendingAgentRequests = 0;
  int _openTasksCount = 0;
  int _pendingEmployeeRequests = 0; // إجازات + سلف
  int _unreadChatCount = 0;
  int _unreadNotificationsCount = 0;
  Timer? _notificationsTimer;
  int _unreadAnnouncementsCount = 0;
  List<Map<String, dynamic>> _myAnnouncements = []; // كل الإعلانات الموجهة
  int _currentAnnouncementIndex = 0;
  bool _announcementExpanded = false; // حالة عرض محلية فقط (طيّ البطاقة) — لا تمسّ منطق التدوير
  Timer? _announcementRotateTimer;
  StreamSubscription? _chatUnreadSub;
  bool _countersLoading = true;
  bool _counterRetried = false; // لمحاولة إعادة جلب العدادات مرة واحدة
  Timer? _countersRefreshTimer; // تحديث تلقائي للعدادات
  late final AnimationController _counterAnimController;

  // أقسام الليدر المتعددة (محمّلة من API)
  String _resolvedDepartments = '';

  // Unified fiber optic color
  final Color _fiberColor = SdColors.accentGlow;


  @override
  void initState() {
    super.initState();
    _counterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _resolvedDepartments = widget.department;
    _initializeApp();
    _initChat();
    _initNotificationsPolling();
    _loadUserDepartments();
  }

  /// جلب أقسام الليدر المتعددة من API
  Future<void> _loadUserDepartments() async {
    if (widget.permissions != 'ليدر' && widget.permissions != 'مدير') return;
    try {
      final result = await TaskApiService.instance.getMyDepartments();
      if (result['success'] == true && result['data'] != null && mounted) {
        final depts = (result['data'] as List)
            .map((d) => d['Name']?.toString() ?? d['name']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();
        if (depts.isNotEmpty) {
          setState(() => _resolvedDepartments = depts.join(','));
          debugPrint('📋 أقسام الليدر: $_resolvedDepartments');
        }
      }
    } catch (e) {
      debugPrint('⚠️ فشل جلب أقسام الليدر: $e');
    }
  }

  /// جلب عدد الإشعارات غير المقروءة دورياً
  void _initNotificationsPolling() {
    _fetchUnreadNotificationsCount();
    _notificationsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _fetchUnreadNotificationsCount();
    });
  }

  Future<void> _fetchUnreadNotificationsCount() async {
    try {
      final res = await NotificationApiService.instance.getUnreadCount();
      if (res['success'] == true && mounted) {
        setState(() => _unreadNotificationsCount = (res['data'] ?? 0) as int);
      }
    } catch (_) {}
  }

  /// عرض لوحة الإشعارات
  void _showNotificationsPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsPanel(
        onRead: () {
          _fetchUnreadNotificationsCount();
        },
      ),
    );
  }

  /// تهيئة نظام المحادثة
  Timer? _chatPollTimer;
  void _initChat() {
    if (PermissionManager.instance.canView('chat')) {
      ChatService.instance.connect();
      _chatUnreadSub = ChatService.instance.onUnreadCount.listen((count) {
        if (mounted) setState(() => _unreadChatCount = count);
      });
      // تحديث العداد فوراً + كل 30 ثانية
      ChatService.instance.refreshUnreadCount();
      _chatPollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) ChatService.instance.refreshUnreadCount();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // إظهار زر واتساب ويب فقط (الزر الأخضر على اليمين) وإخفاء زر المحادثات
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showGlobalWhatsAppButton();
      }
    });
  }

  Future<void> _initializeApp() async {
    try {
      await () async {
        final isAdmin = widget.permissions.toLowerCase().contains('مدير') ||
            widget.permissions.toLowerCase().contains('admin');
        setState(() => _isAdminUser = isAdmin);
      }();
      await _ensurePermissionsLoaded();

      // فحص حالة تسجيل دخول FTTH
      _checkFtthStatus();

      // الاستماع لتغييرات حالة FTTH (يُحدّث الواجهة عند اكتمال silentFtthLogin)
      _ftthStateSubscription =
          DualAuthService.instance.ftthStateStream.listen((isLoggedIn) {
        if (mounted) {
          setState(() {
            _isFtthConnected = isLoggedIn;
            _ftthConnectedUsername =
                isLoggedIn ? DualAuthService.instance.ftthUsername : null;
          });
        }
      });

      // جلب العدادات + تحديث تلقائي كل 30 ثانية
      _fetchCounters();
      _countersRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) _fetchCounters();
      });

      // تدوير الإعلانات كل 5 ثوانٍ
      _announcementRotateTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted && _myAnnouncements.length > 1) {
          setState(() {
            _currentAnnouncementIndex = (_currentAnnouncementIndex + 1) % _myAnnouncements.length;
          });
        }
      });

      // فحص التحديث التلقائي بعد 5 ثوانٍ
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          UpdateManager.checkAndShowUpdateDialog(context);
        }
      });

      // نافذة الإعلانات غير المقروءة بعد 8 ثوانٍ (بعد فحص التحديث)
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) _showAutoAnnouncementPopup();
      });

      // إرسال التقرير اليومي (تقرير الأمس) بعد 10 ثوانٍ
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) {
          MessageLogService.sendDailyReportIfNeeded().then((sent) {
            if (sent) debugPrint('📊 تم إرسال التقرير اليومي للمدير');
          });
        }
      });

      // إظهار زر واتساب ويب بعد التهيئة وإخفاء زر المحادثات
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showGlobalWhatsAppButton();
        }
      });
    } catch (e) {
      debugPrint('Error initializing app');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  /// فحص حالة تسجيل دخول النظام الثاني (FTTH)
  Future<void> _checkFtthStatus() async {
    try {
      final dual = DualAuthService.instance;
      final connected = await dual.checkFtthSession();
      if (mounted) {
        setState(() {
          _isFtthConnected = connected;
          _ftthConnectedUsername = dual.ftthUsername;
        });
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في فحص FTTH');
    }
  }

  /// جلب عدادات الصفحة الرئيسية (طلبات الوكلاء، المهام المفتوحة، طلبات الموظفين)
  Future<void> _fetchCounters() async {
    debugPrint('━━━━ _fetchCounters بدأ ━━━━');
    debugPrint(
        '🔑 ApiClient.authToken: ${ApiClient.instance.authToken != null ? "موجود (${ApiClient.instance.authToken!.length} حرف)" : "NULL"}');
    debugPrint(
        '🔑 VpsAuth.accessToken: ${VpsAuthService.instance.accessToken != null ? "موجود (${VpsAuthService.instance.accessToken!.length} حرف)" : "NULL"}');
    try {
      // ✅ التأكد من وجود التوكن قبل جلب البيانات
      if (ApiClient.instance.authToken == null ||
          ApiClient.instance.authToken!.isEmpty) {
        final vpsToken = VpsAuthService.instance.accessToken;
        if (vpsToken != null && vpsToken.isNotEmpty) {
          debugPrint('🔑 _fetchCounters: تعيين التوكن من VpsAuthService');
          ApiClient.instance.setAuthToken(vpsToken);
        } else {
          debugPrint('⚠️ _fetchCounters: لا يوجد توكن بتاتاً - تأجيل الجلب');
          if (!_counterRetried) {
            _counterRetried = true;
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                _counterRetried = false;
                _fetchCounters();
              }
            });
          }
          if (mounted) setState(() => _countersLoading = false);
          return;
        }
      }

      debugPrint('✅ التوكن موجود، جاري جلب البيانات...');

      // جلب البيانات بالتوازي
      final results = await Future.wait([
        // 1) إحصائيات طلبات الخدمة — مفلترة حسب الدور
        TaskApiService.instance.getStatistics(
          // المدير يرى الكل، الليدر يرى قسمه، الفني يرى مهامه
          department: (widget.permissions == 'ليدر') ? _resolvedDepartments : null,
          technician: (widget.permissions != 'مدير' && widget.permissions != 'ليدر') ? widget.username : null,
        ).catchError((e) {
          debugPrint('❌ خطأ في جلب الإحصائيات');
          return <String, dynamic>{};
        }),
        // 2) ملخص الإجازات
        AttendanceApiService.instance.getLeaveSummary().catchError((e) {
          debugPrint('❌ خطأ في جلب الإجازات');
          return <String, dynamic>{};
        }),
        // 3) طلبات السحب المعلقة (status=0 = Pending)
        AttendanceApiService.instance
            .getWithdrawalRequests(status: 0, page: 1, pageSize: 1)
            .catchError((e) {
          debugPrint('❌ خطأ في جلب السحب');
          return <String, dynamic>{};
        }),
        // 4) ملخّص «اليوم» لعدد المهام المفتوحة اليوم فقط (buckets.open)
        //    نطاق [بداية اليوم المحلي، بداية الغد المحلي) → UTC، بنفس سياق الدور
        //    المستخدم في getStatistics أعلاه، ليطابق تماماً شاشة المهام (فلتر اليوم).
        TaskApiService.instance.getSummary(
          from: _startOfTodayLocal().toUtc(),
          to: _startOfTomorrowLocal().toUtc(),
          department:
              (widget.permissions == 'ليدر') ? _resolvedDepartments : null,
          assignee: (widget.permissions != 'مدير' &&
                  widget.permissions != 'ليدر')
              ? widget.username
              : null,
        ).catchError((e) {
          debugPrint('❌ خطأ في جلب ملخّص اليوم');
          return <String, dynamic>{};
        }),
        // 5) طلبات الوكلاء الحقيقية = طلبات الخدمة serviceId=11 ومصدرها
        //    agent_portal — مطابقةً تماماً لعدّاد «الوكيل» في صفحة منصة الصدارة
        //    (SadaraPortalPage). كان العمود يقرأ Pending من إحصائيات المهام
        //    (طلبات خدمة معلّقة) فيظهر رقماً خاطئاً لا علاقة له بالوكلاء.
        SadaraApiService.instance
            .getServiceRequests(page: 1, pageSize: 200, serviceId: 11)
            .catchError((e) {
          debugPrint('❌ خطأ في جلب طلبات الوكلاء');
          return <dynamic>[];
        }),
      ]);

      final statsRaw = (results[0] as Map).cast<String, dynamic>();
      final leaveSummaryRaw = (results[1] as Map).cast<String, dynamic>();
      final withdrawalsRaw = (results[2] as Map).cast<String, dynamic>();
      final todaySummaryRaw = (results[3] as Map).cast<String, dynamic>();
      final agentRequestsRaw =
          (results[4] is List) ? results[4] as List : const <dynamic>[];

      debugPrint('📊 RAW statsRaw=$statsRaw');
      debugPrint('📊 RAW leaveSummaryRaw=$leaveSummaryRaw');
      debugPrint('📊 RAW withdrawalsRaw=$withdrawalsRaw');

      // التحقق من نجاح استدعاء الإحصائيات
      if (statsRaw['success'] == false) {
        debugPrint(
            '⚠️ فشل جلب الإحصائيات: ${statsRaw['message']} (status: ${statsRaw['statusCode']})');
      }

      // استخراج البيانات من داخل wrapper الـ API (data key)
      final stats = (statsRaw['data'] is Map)
          ? statsRaw['data'] as Map<String, dynamic>
          : statsRaw;
      final leaveSummary = (leaveSummaryRaw['data'] is Map)
          ? leaveSummaryRaw['data'] as Map<String, dynamic>
          : leaveSummaryRaw;
      final withdrawals = (withdrawalsRaw['data'] is Map)
          ? withdrawalsRaw['data'] as Map<String, dynamic>
          : withdrawalsRaw;

      // طلبات الوكلاء = عدد طلبات الخدمة (serviceId=11) التي مصدرها agent_portal،
      // بنفس منطق صفحة منصة الصدارة (SadaraPortalPage._getAgentRequests): نفكّ
      // حقل details JSON ونطابق source == 'agent_portal'. غير القابل للفكّ أو
      // بلا مصدر = مواطن (لا يُحتسب هنا).
      final pendingAgent = _countAgentPortalRequests(agentRequestsRaw);

      // المهام المفتوحة = «المفتوحة اليوم فقط» (buckets.open لنطاق اليوم) —
      // مطابقةً تماماً لبطاقة «مفتوحة» في شاشة المهام تحت فلتر «اليوم».
      // المصدر: GET /servicerequests/summary?from&to (العنصر [3] من Future.wait).
      final todaySummary = (todaySummaryRaw['data'] is Map)
          ? todaySummaryRaw['data'] as Map
          : todaySummaryRaw;
      final todayBuckets = todaySummary['buckets'];
      final openTasks = (todayBuckets is Map)
          ? _asInt(todayBuckets['open'], 0)
          : 0;
      debugPrint(
          '📊 المهام المفتوحة اليوم (buckets.open) = $openTasks');

      // طلبات الموظفين = إجازات معلقة + سحب معلقة
      final pendingLeaves = _safeInt(leaveSummary, 'Pending', 'pending');
      final pendingWithdrawals = _safeInt(withdrawals, 'Total', 'total');
      final employeeRequests = pendingLeaves + pendingWithdrawals;

      debugPrint('📊 عدادات: stats=$stats');
      debugPrint(
          '📊 agent=$pendingAgent, tasks=$openTasks, emp=$employeeRequests');

      // جلب عداد الإعلانات غير المقروءة + كل الإعلانات
      final announcementsCount = await AnnouncementService.instance.getUnreadCount().catchError((_) => 0);
      List<Map<String, dynamic>> myAnns = [];
      try {
        final annResponse = await AnnouncementService.instance.getMyAnnouncements(page: 1, pageSize: 10);
        if (annResponse['success'] == true) {
          final annData = annResponse['data'] as List?;
          if (annData != null && annData.isNotEmpty) {
            myAnns = annData.map((a) => Map<String, dynamic>.from(a)).toList();
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _pendingAgentRequests = pendingAgent;
          _openTasksCount = openTasks;
          FloatingToolbar.updateS1TasksBadge(openTasks);
          _pendingEmployeeRequests = employeeRequests;
          _unreadAnnouncementsCount = announcementsCount;
          _myAnnouncements = myAnns;
          if (_currentAnnouncementIndex >= myAnns.length) _currentAnnouncementIndex = 0;
          _countersLoading = false;
        });
        _counterAnimController.forward(from: 0.0);

        // إعادة المحاولة تلقائياً إذا فشلت الإحصائيات (مثل التوكن لم يكن جاهزاً)
        if (statsRaw['success'] == false && !_counterRetried) {
          _counterRetried = true;
          debugPrint('🔄 إعادة محاولة جلب العدادات بعد 5 ثوانٍ...');
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) _fetchCounters();
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب العدادات');
      if (mounted) {
        setState(() => _countersLoading = false);
        // إعادة المحاولة مرة واحدة في حالة الخطأ
        if (!_counterRetried) {
          _counterRetried = true;
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) _fetchCounters();
          });
        }
      }
    }
  }

  /// استخراج قيمة int من Map بشكل آمن (لتجنب أخطاء type cast)
  int _extractInt(Map<String, dynamic> map, String key) {
    final val = map[key];
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  /// استخراج int مع محاولة مفتاحين (PascalCase ثم camelCase) لتجنب التكرار
  int _safeInt(Map<String, dynamic> map, String key1, String key2) {
    final v1 = _extractInt(map, key1);
    if (v1 > 0) return v1;
    return _extractInt(map, key2);
  }

  /// تحويل قيمة ديناميكية إلى int (int أو num أو نص رقمي)، وإلا [fallback].
  /// يُستخدم لقراءة buckets ملخّص المهام القادمة من الخادم.
  int _asInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  /// بداية اليوم بالوقت المحلي — لنطاق «اليوم» في ملخّص المهام المفتوحة.
  DateTime _startOfTodayLocal() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// بداية الغد بالوقت المحلي — الحدّ الأعلى (غير شامل) لنطاق «اليوم».
  DateTime _startOfTomorrowLocal() =>
      _startOfTodayLocal().add(const Duration(days: 1));

  /// عدّ طلبات الوكلاء ضمن قائمة طلبات الخدمة الخام (serviceId=11):
  /// الطلب للوكيل إذا كان حقل details يحوي `source == 'agent_portal'`.
  /// يطابق منطق [SadaraPortalPage] تماماً، فيتطابق العدّاد مع تبويب «الوكيل».
  int _countAgentPortalRequests(List<dynamic> rows) {
    var count = 0;
    for (final row in rows) {
      if (row is! Map) continue;
      final details = row['details'] ?? row['Details'];
      if (details is! String || details.isEmpty) continue;
      try {
        final decoded = json.decode(details);
        if (decoded is Map &&
            decoded['source']?.toString().toLowerCase() == 'agent_portal') {
          count++;
        }
      } catch (_) {
        // details غير قابل للفكّ ⇒ يُعامل كمواطن (لا يُحتسب).
      }
    }
    return count;
  }

  Future<void> _ensurePermissionsLoaded() async {
    final pm = PermissionManager.instance;
    if (!pm.isLoaded) {
      await pm.loadPermissions();
    }
  }

  DateTime? _lastLocationTime; // لكشف السرعة المستحيلة

  // إرسال الموقع إلى Sadara API — تردد ذكي + حماية من Fake Location
  Future<void> _sendLiveLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );

      // ═══════ طبقة 1: كشف Mock Location ═══════
      if (position.isMocked) {
        debugPrint('🚨 [SECURITY] Mock location detected! Rejecting.');
        return; // رفض الموقع المزيف
      }

      // ═══════ طبقة 2: فحص دقة الموقع ═══════
      // المواقع المزيفة غالباً تكون بدقة 0 أو دقة مثالية جداً (< 1 متر)
      if (position.accuracy < 1.0 || position.accuracy > 500) {
        debugPrint('🚨 [SECURITY] Suspicious accuracy: ${position.accuracy}m');
        return;
      }

      // ═══════ طبقة 3: كشف السرعة المستحيلة ═══════
      if (_lastLat != null && _lastLng != null && _lastLocationTime != null) {
        final distance = Geolocator.distanceBetween(
          _lastLat!, _lastLng!, position.latitude, position.longitude,
        );
        final timeDiff = DateTime.now().difference(_lastLocationTime!).inSeconds;
        if (timeDiff > 0) {
          final speed = distance / timeDiff; // متر/ثانية
          if (speed > 80) { // > 288 كم/ساعة = مستحيل
            debugPrint('🚨 [SECURITY] Impossible speed: ${(speed * 3.6).round()} km/h');
            return;
          }
        }
      }

      // حساب المسافة من الموقع السابق
      int newInterval = 60;
      if (_lastLat != null && _lastLng != null) {
        final distance = Geolocator.distanceBetween(
          _lastLat!, _lastLng!, position.latitude, position.longitude,
        );
        if (distance > 10) {
          newInterval = 10;
        } else {
          newInterval = 60;
        }
      } else {
        newInterval = 10;
      }

      _lastLat = position.latitude;
      _lastLng = position.longitude;
      _lastLocationTime = DateTime.now();

      // تغيير التايمر إذا تغيّر التردد
      if (newInterval != _currentInterval && _isLocationActive) {
        _currentInterval = newInterval;
        _locationTimer?.cancel();
        _locationTimer = Timer.periodic(
          Duration(seconds: _currentInterval),
          (_) => _sendLiveLocation(),
        );
      }

      final payload = {
        'userId': widget.username,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'isMocked': position.isMocked,
      };

      // مزامنة المواقع المخزّنة أثناء عدم الاتصال
      if (_offlineQueue.isNotEmpty) {
        final queued = List<Map<String, dynamic>>.from(_offlineQueue);
        _offlineQueue.clear();
        for (final p in queued) {
          await ApiClient.instance.post('/employee-location', p, (d) => d, useInternalKey: true);
        }
      }

      final result = await ApiClient.instance.post(
        '/employee-location', payload, (d) => d, useInternalKey: true,
      );

      if (!result.isSuccess) {
        // فشل الإرسال → تخزين محلي
        _offlineQueue.add(payload);
        debugPrint("Offline: queued location (${_offlineQueue.length})");
      }
    } catch (e) {
      // لا إنترنت → تخزين محلي
      if (_lastLat != null) {
        _offlineQueue.add({
          'userId': widget.username,
          'latitude': _lastLat,
          'longitude': _lastLng,
        });
        debugPrint("Offline: queued (${_offlineQueue.length})");
      }
    }
  }

  // إيقاف إرسال الموقع
  Future<void> _stopLiveLocation() async {
    try {
      await ApiClient.instance.delete(
        '/employee-location/${Uri.encodeComponent(widget.username)}',
        (data) => data,
        useInternalKey: true,
      );
    } catch (e) {
      debugPrint("مشكلة في إيقاف مشاركة الموقع: $e");
    }
  }

  // Show global WhatsApp floating button
  /// هل صلاحية fab مُعطّلة صراحةً؟ (مفتاح غير موجود = افتراضي يظهر)
  bool _isFabDisabled(PermissionManager pm, String key) {
    if (!pm.hasKey(key)) return false;
    return !pm.canView(key);
  }

  void _showGlobalWhatsAppButton() {
    try {
      if (!mounted) return;
      final pm = PermissionManager.instance;

      // تهيئة الشريط العائم الموحد
      FloatingToolbar.init(context);
      FloatingToolbar.enableWhatsApp();

      // انتظر حتى تُحمّل الصلاحيات فعلاً قبل تفعيل الأزرار المشروطة
      if (!pm.isLoaded) return;

      // زر محادثات الواتساب
      if (pm.canView('whatsapp_conversations_fab')) {
        FloatingToolbar.enableConversations(isAdmin: _isAdminUser);
      }

      // زر المهام (النظام الأول)
      if (pm.canView('tasks') && !_isFabDisabled(pm, 'fab_tasks')) {
        FloatingToolbar.enableS1Tasks(
          onTap: () {
            if (!mounted) return;
            _navigateTo(TaskListScreen(
              username: widget.username,
              permissions: widget.permissions,
              department: _resolvedDepartments,
              center: widget.center,
            ));
          },
          badgeCount: _openTasksCount,
        );
      }

      // زر التذاكر (FTTH) — يظهر أيضاً في النظام الأول
      if (pm.canView('tasks') && !_isFabDisabled(pm, 'fab_tasks')) {
        FloatingToolbar.enableTasks();
      }

      // زر المحادثة الداخلية
      if (pm.canView('chat') && !_isFabDisabled(pm, 'fab_chat')) {
        FloatingToolbar.enableChat();
      }
    } catch (e) {
      debugPrint('Error showing WhatsApp floating button: $e');
    }
  }

  Future<void> _logout() async {
    // إلغاء تسجيل FCM token (منع إشعارات المستخدم السابق)
    try {
      await FcmTokenService.instance.unregisterToken();
    } catch (e) {
      debugPrint('⚠️ خطأ في إلغاء FCM token');
    }
    // تسجيل الخروج من كلا النظامين (VPS + FTTH)
    try {
      await DualAuthService.instance.logoutAll();
    } catch (e) {
      debugPrint('⚠️ خطأ في تسجيل الخروج');
    }

    // إزالة الشريط العائم
    FloatingToolbar.dispose();

    // الانتقال لصفحة تسجيل الدخول
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PremiumLoginPage()),
        (route) => false,
      );
    }
  }

  void _showUserInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => UserInfoDialog(
        username: widget.username,
        permissions: widget.permissions,
        department: widget.department,
        center: widget.center,
        salary: widget.salary,
        isAdmin: _isAdminUser,
      ),
    );
  }

  /*
  Widget _buildPermissionSwitch({
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: _isAdminUser ? onChanged : null,
      secondary: Icon(
        value ? Icons.lock_open : Icons.lock_outline,
        color: value ? Colors.green : Colors.red,
      ),
    );
  }
  */

  // انتقال سريع بدون أنيميشن — يمنع التأخير عند الدخول والخروج
  void _navigateTo(Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (ctx, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) => child,
      ),
    ).then((_) {
      if (mounted) _showGlobalWhatsAppButton();
    });
  }

  Widget _buildEnhancedMenuItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
    required String permissionKey,
    int badgeCount = 0,
  }) {
    final hasPermission = permissionKey.isEmpty || PermissionManager.instance.canView(permissionKey);
    if (!hasPermission) return const SizedBox.shrink();
    final r = context.responsive;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasPermission ? onTap : null,
        borderRadius: BorderRadius.circular(r.cardRadius + 2),
        splashColor: gradient[0].withOpacity(0.08),
        highlightColor: gradient[0].withOpacity(0.04),
        child: Container(
          constraints: BoxConstraints(minHeight: r.menuItemHeight),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(r.cardRadius + 2),
            border: Border.all(
              color: gradient[0].withOpacity(0.35),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: gradient[0].withOpacity(0.08),
                blurRadius: 12,
                spreadRadius: -2,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: r.isMobile ? 10 : 16,
                vertical: r.isMobile ? 8 : 10),
            child: Row(
              children: [
                // أيقونة دائرية ملونة + badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: r.menuIconCircleSize,
                      height: r.menuIconCircleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: gradient,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: gradient[0].withOpacity(0.35),
                            blurRadius: 10,
                            spreadRadius: -2,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: r.menuIconInnerSize,
                      ),
                    ),
                    if (badgeCount > 0)
                      Positioned(
                        top: -5,
                        right: -5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: SdColors.danger,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: SdColors.danger.withOpacity(0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          constraints: const BoxConstraints(
                              minWidth: 18, minHeight: 16),
                          child: Text(
                            badgeCount > 99 ? '99+' : badgeCount.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: r.captionSize,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: r.isMobile ? 10 : 14),
                // النص
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          title,
                          style: TextStyle(
                            color: SdColors.ink,
                            fontSize: r.menuItemTitleSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      if (!r.isMobile) ...[
                        SizedBox(height: 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              color: SdColors.muted,
                              fontSize: r.menuItemSubtitleSize,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // سهم
                Container(
                  width: r.menuArrowCircleSize,
                  height: r.menuArrowCircleSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gradient[0].withOpacity(0.08),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: gradient[0].withOpacity(0.6),
                    size: r.menuArrowIconSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _chatUnreadSub?.cancel();
    _chatPollTimer?.cancel();
    _notificationsTimer?.cancel();
    _ftthStateSubscription?.cancel();
    _countersRefreshTimer?.cancel();
    _announcementRotateTimer?.cancel();
    if (_isLocationActive) {
      if (Platform.isAndroid || Platform.isIOS) {
        LocationForegroundService.instance.stop();
      } else {
        _stopLiveLocation();
      }
    }
    _locationTimer?.cancel();
    _counterAnimController.dispose();
    WhatsAppBottomWindow.hideBottomWindow(
        clearContent: true); // Hide WhatsApp floating button
    super.dispose();
  }

  @override
  void deactivate() {
    _locationTimer?.cancel();
    _locationTimer = null;
    super.deactivate();
  }

  // Animated diagonal "fiber optic" beam used in AppBar background
  Widget _buildFiberBeam({
    required double progress,
    required double opacity,
    required double phase,
    double widthFactor = 0.55,
    double angleRad = -math.pi / 7,
    double thickness = 7.0,
    Color color = Colors.cyanAccent,
    bool rightToLeft = false,
    // lively pattern controls
    double waveAmp =
        0.12, // vertical wave amplitude (-1..1 space) - clearer lines
    double waveFreq = 1.2, // waves per cycle
    double pulseAmp = 0.18, // reduced pulsing to avoid visual noise
    double pulseFreq = 0.9, // pulses per cycle
  }) {
    final f = (progress + phase) % 1.0;
    final twoPi = 2 * math.pi;
    final time = (progress + phase);
    final wave = math.sin(twoPi * time * waveFreq) * waveAmp;
    final pulse = 0.5 + 0.5 * math.sin(twoPi * time * pulseFreq);
    final opacityMod = (1 - pulseAmp) + pulseAmp * pulse; // 0..1
    final thicknessMod = (1 - pulseAmp * 0.6) + (pulseAmp * 0.6) * pulse;
    return IgnorePointer(
      ignoring: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final beamWidth = constraints.maxWidth * widthFactor;
          final beamHeight = thickness * thicknessMod;
          // Move diagonally from top-left to bottom-right
          final alignVal =
              rightToLeft ? (1 - 2 * f) : (-1 + 2 * f); // x from 1..-1 if RTL
          return Align(
            alignment: Alignment(alignVal, wave), // lively vertical wave
            child: Transform.rotate(
              angle: angleRad, // rotation of the beam
              child: Container(
                width: beamWidth,
                height: beamHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.0),
                      color.withValues(
                          alpha: (opacity * opacityMod).clamp(0.0, 1.0)),
                      color.withValues(alpha: 0.0),
                    ],
                    stops: const [0.05, 0.5, 0.95],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(
                          alpha: (opacity * opacityMod * 0.9).clamp(0.0, 1.0)),
                      blurRadius: 12 + 8 * pulse,
                      spreadRadius: 1.5,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
  Widget _buildAnimatedActionButtonLegacy({
    required Icon icon,
    required VoidCallback onPressed,
    String? tooltip,
    EdgeInsetsGeometry? margin,
  }) {
    final r = context.responsive;
    final btnSize = r.scaled(34, 40, 44);
    final btnPad = r.isMobile ? 5.0 : 8.0;
    return Container(
      margin: margin ?? EdgeInsets.symmetric(horizontal: r.isMobile ? 2 : 4),
      child: SizedBox(
        width: btnSize,
        height: btnSize,
        child: IconButton(
          padding: EdgeInsets.all(btnPad),
          constraints: BoxConstraints(minWidth: btnSize, minHeight: btnSize),
          icon: icon,
          tooltip: tooltip,
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.12),
            shape: const CircleBorder(),
          ),
        ),
      ),
    );
  }

  // Small animated light streak ("photon") that travels along the same diagonal as the beams
  Widget _buildPhoton({
    required double progress,
    required double phase,
    required double y, // vertical lane position in -1..1 space
    double angleRad = -math.pi / 6,
    bool rightToLeft = true,
    double size = 7.5, // thicker streak for visibility
    double length = 60.0, // longer streak for prominence
    Color? color,
    double speed = 1.0,
    double maxGlow = 0.85,
  }) {
    final c = color ?? _fiberColor;
    final twoPi = 2 * math.pi;
    final t = (progress * speed + phase) % 1.0;
    // Twinkle a bit while moving
    final twinkle = 0.75 + 0.25 * math.sin(twoPi * (progress + phase) * 1.6);
    final x = rightToLeft ? (1 - 2 * t) : (-1 + 2 * t);
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment(x, y),
        child: Transform.rotate(
          angle: angleRad,
          child: SizedBox(
            width: length,
            height: size * 2,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // faint trail
                Container(
                  width: length * 1.15,
                  height: size * 0.75,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        c.withValues(alpha: 0.0),
                        c.withValues(alpha: 0.25 * twinkle),
                        c.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: c.withValues(alpha: 0.35 * twinkle),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                // main streak
                Container(
                  width: length,
                  height: size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        c.withValues(alpha: 0.0),
                        Colors.white
                            .withValues(alpha: 0.95 * twinkle), // bright core
                        c.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: c.withValues(alpha: maxGlow * twinkle),
                        blurRadius: 14,
                        spreadRadius: 0.8,
                      ),
                    ],
                  ),
                ),
                // glowing core dot
                Container(
                  width: size * 1.4,
                  height: size * 1.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.95 * twinkle),
                        c.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: c.withValues(alpha: 0.9 * twinkle),
                        blurRadius: 20,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // تم إزالة إظهار الزر العائم للواتساب - يظهر فقط في FTTH

    if (_isLoading) {
      return Scaffold(
        body: Container(
          color: SdColors.surfaceAlt,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: SdColors.info.withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(60),
                    child: Image.asset(
                      'assets/splash_background.jpg',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      SdColors.info,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'جاري التحميل...',
                  style: TextStyle(
                    color: const Color(0xFF000000),
                    fontSize: context.responsive.titleSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SdNavShell(
      backgroundColor: SdColors.ground,
      // ── القائمة الجانبية الموحّدة (درج على الهاتف، شريط على الآيباد/المكتب) ──
      sections: _navSections(),
      footer: _navFooter(),
      title: 'رمز الصدارة',
      subtitle: VpsAuthService.instance.currentCompanyName,
      selectedId: 'home',
      appBar: SdAppBar(
        title: 'رمز الصدارة',
        subtitle: _isFtthConnected
            ? 'FTTH متصل · $_ftthConnectedUsername'
            : 'FTTH غير متصل',
        subtitleOk: _isFtthConnected,
        actions: [
          // زر العودة للوحة تحكم Super Admin
          if (widget.isSuperAdminMode)
            SdAppBarAction(
              icon: Icons.admin_panel_settings,
              label: 'لوحة مدير النظام',
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const SuperAdminDashboard(),
                  ),
                  (route) => false,
                );
              },
            ),
          // زر تتبّع الكادر على الخريطة
          if (_isAdminUser || PermissionManager.instance.canView('tracking'))
            SdAppBarAction(
              icon: Icons.my_location_rounded,
              label: 'تتبّع الكادر',
              onPressed: () => _navigateTo(const TrackUsersMapPage()),
            ),
          // زر الإشعارات (بشارة) — يفتح لوحة الإشعارات
          SdAppBarAction(
            icon: Icons.notifications_outlined,
            label: 'الإشعارات',
            badge: _unreadNotificationsCount,
            onPressed: _showNotificationsPanel,
          ),
          // زر الموقع — أيقونة فقط: أخضر إذا يعمل، أحمر إذا متوقف
          SdAppBarAction(
            icon: _isLocationActive ? Icons.location_on : Icons.location_off,
            label: _isLocationActive
                ? 'الموقع يعمل'
                : 'الموقع متوقف — تفعيل',
            iconOnly: true,
            success: _isLocationActive,
            danger: !_isLocationActive,
            onPressed: () async {
              if (!_isLocationActive) {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                LocationPermission permission =
                    await Geolocator.requestPermission();

                if (!mounted) return;

                if (permission == LocationPermission.denied ||
                    permission == LocationPermission.deniedForever) {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                        content: Text('يرجى السماح بالوصول إلى الموقع')),
                  );
                  return;
                }

                // تشغيل الخدمة في الخلفية (Android/iOS)
                if (Platform.isAndroid || Platform.isIOS) {
                  // 🛡️ فحص الجهاز — كشف تطبيقات الفيك (تحذير فقط، لا يمنع التشغيل)
                  final warning = await LocationForegroundService.instance.checkDeviceIntegrity();
                  if (warning != null && mounted) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(
                        content: Text('⚠️ $warning\nسيتم تسجيل أي موقع وهمي'),
                        backgroundColor: SdColors.warning,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    // لا نرجع — نسمح بالتشغيل مع التحذير
                  }

                  final started = await LocationForegroundService.instance.start(widget.username);
                  if (started) {
                    setState(() => _isLocationActive = true);
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('✅ مشاركة الموقع تعمل في الخلفية'),
                        backgroundColor: SdColors.success,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                } else {
                  // Windows: استخدام Timer العادي
                  setState(() => _isLocationActive = true);
                  _sendLiveLocation();
                  _currentInterval = 10;
                  _locationTimer =
                      Timer.periodic(Duration(seconds: _currentInterval), (timer) {
                    _sendLiveLocation();
                  });
                }
              } else {
                setState(() => _isLocationActive = false);
                if (Platform.isAndroid || Platform.isIOS) {
                  await LocationForegroundService.instance.stop();
                } else {
                  _locationTimer?.cancel();
                  await _stopLiveLocation();
                }
              }
            },
          ),
        ],
      ),
      // ═══ المحتوى الرئيسي ═══
      body: _buildBody(),
    );
  }

  // ═══ القائمة الجانبية الموحّدة: مصدر واحد لكل الأحجام ═══
  List<SdNavSection> _navSections() {
    return [
      SdNavSection(
        title: 'الإدارة',
        items: [
          // إدارة المستخدمين (مدير فقط)
          if (_isAdminUser)
            SdNavItem(
              id: 'users',
              label: 'إدارة المستخدمين',
              icon: Icons.people,
              group: SdGroup.admin,
              onTap: () {
                final companyId =
                    widget.tenantId ?? VpsAuthService.instance.currentCompanyId;
                final companyCode = widget.tenantCode ??
                    VpsAuthService.instance.currentCompanyCode;
                final companyName =
                    VpsAuthService.instance.currentCompanyName ?? 'الشركة';
                _navigateTo(
                  companyId != null && companyCode != null
                      ? UsersPageVPS(
                          companyId: companyId,
                          companyName: companyName,
                          permissions: const {'users': true},
                        )
                      : companyId != null
                          ? UsersPageFirebase(
                              tenantId: companyId,
                              permissions: widget.permissions,
                            )
                          : UsersPage(permissions: widget.permissions),
                );
              },
            ),
          // المستخدمين (محظور) لغير المدراء
          if (!_isAdminUser)
            SdNavItem(
              id: 'users',
              label: 'المستخدمين',
              icon: Icons.people_outline,
              group: SdGroup.neutral,
              enabled: false,
              onTap: () => _showPermissionDenied(),
            ),
          // إعدادات الشركة (للمدير فقط)
          if (_isAdminUser)
            SdNavItem(
              id: 'company_settings',
              label: 'إعدادات الشركة',
              icon: Icons.settings,
              group: SdGroup.neutral,
              onTap: () => _navigateTo(CompanySettingsPage(
                companyId:
                    widget.tenantId ?? VpsAuthService.instance.currentCompanyId,
                companyCode: widget.tenantCode ??
                    VpsAuthService.instance.currentCompanyCode,
                currentUserRole: widget.permissions,
                currentUsername: widget.username,
              )),
            ),
        ],
      ),
      SdNavSection(
        title: 'النظام والتواصل',
        items: [
          // تشخيص النظام
          if (PermissionManager.instance.canView('diagnostics'))
            SdNavItem(
              id: 'diagnostics',
              label: 'تشخيص النظام',
              icon: Icons.bug_report,
              group: SdGroup.comms,
              onTap: () => _navigateTo(CompanyDiagnosticsPage(
                tenantId: widget.tenantId,
                tenantCode: widget.tenantCode,
              )),
            ),
          // مزامنة FTTH (للمدير فقط)
          if (_isAdminUser)
            SdNavItem(
              id: 'ftth_sync',
              label: 'مزامنة FTTH',
              icon: Icons.sync_rounded,
              group: SdGroup.field,
              onTap: () => _navigateTo(const FtthSyncSettingsPage()),
            ),
          // المحادثة
          if (PermissionManager.instance.canView('chat'))
            SdNavItem(
              id: 'chat',
              label: 'المحادثة',
              icon: Icons.forum_rounded,
              group: SdGroup.comms,
              onTap: () => _navigateTo(const ChatRoomsPage()),
            ),
        ],
      ),
    ];
  }

  List<SdNavItem> _navFooter() {
    return [
      SdNavItem(
        id: 'logout',
        label: 'تسجيل الخروج',
        icon: Icons.logout,
        danger: true,
        onTap: () => _showLogoutConfirmation(),
      ),
    ];
  }

  Widget _buildBody() {
    final r = context.responsive;
    final maxContentWidth = r.maxContentWidth;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // خلفية سادة SdColors.ground (أُزيلت زخرفة الأيقونات الباهتة)
    return ColoredBox(
      color: SdColors.ground,
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            left: r.contentPaddingH,
            right: r.contentPaddingH,
            bottom: bottomPadding + 80,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: Column(
                children: [
                  const SizedBox(height: 4),
                  // بطاقة التعليمات/الترحيب
                  _buildWelcomeOrAnnouncementCard(r),
                  // ===== العدّادات الثلاثة =====
                  _buildCountersRow(),
                  SizedBox(height: r.isMobile ? 8 : 10),
                  // شبكة القوائم المقسّمة
                  _buildMenuGrid(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // التنقل إلى صفحة FTTH
  void _goToFtthHome(DualAuthService dual) {
    final ftthUsername = dual.ftthUsername!;
    final ftthIsAdmin = ftthUsername.toLowerCase().contains('admin') ||
        ftthUsername.toLowerCase().contains('مدير');
    final isFirstSystemAdmin =
        widget.permissions.toLowerCase().contains('مدير') ||
            widget.permissions.toLowerCase().contains('admin');
    final finalPermissions =
        (isFirstSystemAdmin || ftthIsAdmin) ? 'مدير مجمع' : 'مستخدم مجمع';

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/ftth-home'),
        builder: (context) => ftth_home.HomePage(
          username: ftthUsername,
          authToken: dual.ftthToken!,
          permissions: finalPermissions,
          department: widget.department,
          center: widget.center,
          salary: widget.salary,
          firstSystemUsername: widget.username,
          firstSystemDepartment: widget.department,
          firstSystemCenter: widget.center,
          firstSystemSalary: widget.salary,
        ),
      ),
    ).then((_) {
      // عند العودة من FTTH — إعادة تهيئة الشريط العائم للنظام الأول
      if (mounted) {
        _showGlobalWhatsAppButton();
      }
    });
  }

  // التنقل إلى صفحة FTTH - مباشرة إذا كان مسجل دخول، أو عبر تسجيل دخول صامت
  Future<void> _navigateToFtth() async {
    final dual = DualAuthService.instance;

    // 0) تحقق Cloudflare قبل أي دخول تلقائي — يظهر نافذة التحقق إن لزم،
    //    ويلتقط cf_clearance ويحقنه في كل طلبات admin.ftth.iq.
    if (!mounted) return;
    final cleared = await CloudflareGateDialog.ensure(context);
    if (!cleared) {
      print('⚠️ [FTTH] لم يكتمل التحقق الأمني — إلغاء الدخول');
      return;
    }
    // مهلة استقرار بعد التحقق قبل الدخول التلقائي وجلب البيانات
    await Future.delayed(const Duration(milliseconds: 1500));

    // 1) فحص الجلسة الحالية
    final hasSession = await dual.checkFtthSession();

    if (hasSession && dual.ftthToken != null && dual.ftthUsername != null && dual.ftthUsername!.isNotEmpty) {
      if (!mounted) return;
      _goToFtthHome(dual);
      return;
    }

    // 2) الجلسة منتهية — حاول تسجيل دخول صامت تلقائياً (المسار الذكي الجديد
    //    مع تدرّج آمن للمسار القديم، وحوار اختيار عند تعدّد حسابات FTTH)
    print('🔄 [FTTH] الجلسة منتهية — محاولة تسجيل دخول صامت...');
    // لا حوار اختيار عند الدخول — ندخل تلقائياً بالحساب الأساسي؛
    // التبديل يتم من مُبدّل الحساب في الشريط العلوي داخل التطبيق.
    final silentResult = await dual.smartFtthLogin();

    if (silentResult.success && dual.ftthToken != null && dual.ftthUsername != null) {
      print('✅ [FTTH] نجح تسجيل الدخول الصامت — الانتقال مباشرة');
      if (!mounted) return;
      _goToFtthHome(dual);
      return;
    }

    // 2.ب) ألغى المستخدم اختيار الحساب — ابقَ في الرئيسية بلا إعادة توجيه
    if (silentResult.cancelled) {
      print('ℹ️ [FTTH] أُلغي اختيار حساب FTTH — البقاء في الصفحة الرئيسية');
      return;
    }

    // 3) فشل تسجيل الدخول الصامت — العودة لشاشة تسجيل الدخول الرئيسية
    print('⚠️ [FTTH] فشل تسجيل الدخول الصامت: ${silentResult.message}');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PremiumLoginPage()),
      (route) => false,
    );
  }

  // ===== العدّادات الثلاثة (أعمدة مجسّمة SdStatPedestal) =====
  Widget _buildCountersRow() {
    final l = context.sd;
    // المقياس = أكبر قيمة بين العدّادات الثلاثة.
    final maxVal = [
      _pendingAgentRequests,
      _openTasksCount,
      _pendingEmployeeRequests,
    ].reduce((a, b) => a > b ? a : b);

    final agent = SdStatPedestal(
      value: _pendingAgentRequests,
      label: 'طلبات الوكلاء',
      max: maxVal,
      group: SdGroup.field,
      // يفتح منصة الوكلاء والمواطنين (منصة الصدارة) بدل لوحة FTTH
      onTap: () => _navigateTo(const Scaffold(body: SadaraPortalPage())),
    );
    final tasks = SdStatPedestal(
      value: _openTasksCount,
      label: 'المهام المفتوحة',
      max: maxVal,
      group: SdGroup.admin,
      onTap: () => _navigateTo(TaskListScreen(
        username: widget.username,
        permissions: widget.permissions,
        department: _resolvedDepartments,
        center: widget.center,
      )),
    );
    final employees = SdStatPedestal(
      value: _pendingEmployeeRequests,
      label: 'طلبات الموظفين',
      max: maxVal,
      group: SdGroup.platform,
      onTap: () => _navigateTo(HrHubPage(
        username: widget.username,
        permissions: widget.permissions,
        department: widget.department,
        center: widget.center,
        tenantId: widget.tenantId,
        tenantCode: widget.tenantCode,
      )),
    );

    final gap = l.gridGap;
    // الهاتف: عمود واحد.
    if (l.isPhone) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            agent,
            SizedBox(height: gap),
            tasks,
            SizedBox(height: gap),
            employees,
          ],
        ),
      );
    }
    // الآيباد/سطح المكتب: ثلاثة أعمدة متساوية.
    // IntrinsicHeight يمنح الصفّ ارتفاعاً محدوداً (أطول عمود) داخل التمرير
    // العمودي، فيعمل stretch دون طلب ارتفاع لا نهائي.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: agent),
            SizedBox(width: gap),
            Expanded(child: tasks),
            SizedBox(width: gap),
            Expanded(child: employees),
          ],
        ),
      ),
    );
  }

  /// بطاقة عداد بتصميم FTTH مع مقياس الأمواج الشعاعية
  Widget _buildFtthCounterCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required bool loading,
  }) {
    // لون ثانوي للتدرج
    final Color color2 = HSLColor.fromColor(color)
        .withHue((HSLColor.fromColor(color).hue + 40) % 360)
        .toColor();

    final hoverNotifier = ValueNotifier<bool>(false);

    return ValueListenableBuilder<bool>(
      valueListenable: hoverNotifier,
      builder: (context, isHovered, child) {
        final r = context.responsive;
        return MouseRegion(
          onEnter: (_) => hoverNotifier.value = true,
          onExit: (_) => hoverNotifier.value = false,
          child: AnimatedScale(
            scale: isHovered ? 1.04 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding: r.counterCardPadding,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isHovered
                      ? color.withValues(alpha: 0.35)
                      : SdColors.divider,
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
                  // دائرة الأمواج الشعاعية
                  loading
                      ? SizedBox(
                          width: r.counterCircleSize,
                          height: r.counterCircleSize,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: color,
                            ),
                          ),
                        )
                      : AnimatedBuilder(
                          animation: _counterAnimController,
                          builder: (context, child) {
                            final curvedVal = Curves.easeOutExpo
                                .transform(_counterAnimController.value);
                            final displayValue = (value * curvedVal).round();
                            return SizedBox(
                              width: r.counterCircleSize,
                              height: r.counterCircleSize,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CustomPaint(
                                    size: Size.square(r.counterCircleSize),
                                    painter: _HomeRadialWavePainter(
                                      progress: 1.0,
                                      color1: color,
                                      color2: color2,
                                      animValue: 0,
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatCounter(displayValue),
                                        style: TextStyle(
                                          fontSize: r.counterValueSize,
                                          fontWeight: FontWeight.w900,
                                          color: SdColors.neutralBase,
                                          letterSpacing: -0.3,
                                          height: 1.0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                  SizedBox(height: r.isMobile ? 2 : 8),
                  // تسمية
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: r.counterLabelSize + 1),
                        const SizedBox(width: 3),
                        Text(
                          label,
                          style: TextStyle(
                            color: SdColors.neutralBase,
                            fontSize: r.counterLabelSize,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
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

  /// تنسيق عداد مع فواصل الآلاف
  String _formatCounter(int number) {
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

  /// بطاقة الترحيب أو الإعلانات (دوري)
  Widget _buildWelcomeOrAnnouncementCard(dynamic r) {
    final l = context.sd;
    final hasAnnouncements = _myAnnouncements.isNotEmpty;
    final ann =
        hasAnnouncements ? _myAnnouncements[_currentAnnouncementIndex] : null;
    final cubeSize = l.isPhone ? 44.0 : 46.0;

    // ── حالة الترحيب (لا تعليمات) ──
    if (!hasAnnouncements) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SdRaised(
          radius: SdRadius.lg,
          depth: 5,
          padding: EdgeInsets.all(l.isPhone ? 12 : 14),
          child: Row(
            children: [
              SdIconCube(
                  icon: Icons.person_rounded,
                  group: SdGroup.admin,
                  size: cubeSize),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('مرحبا بكم في شركة الصدارة', style: SdText.caption),
                    Text('مرحباً ${widget.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SdText.titleSm),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // زر معلومات المستخدم
              SdRaised(
                onTap: () => _showUserInfo(context),
                radius: SdRadius.sm,
                depth: 3,
                color: SdColors.infoTint,
                edgeColor: SdColors.infoTintEdge,
                glowColor: const Color(0x261565C0),
                padding: const EdgeInsets.all(10),
                semanticLabel: 'معلومات المستخدم',
                child: const Icon(Icons.info_outline,
                    color: SdColors.info, size: 20),
              ),
            ],
          ),
        ),
      );
    }

    // ── بطاقة التعليمات الجديدة (إعلان) — مدمجة وقابلة للطيّ ──
    final t = SdGroup.comms.tone;
    final body = ann!['body']?.toString() ?? '';
    final title = ann['title']?.toString() ?? '';
    final smallCube = l.isPhone ? 34.0 : 36.0;
    final expanded = _announcementExpanded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SdRaised(
        // الضغط على البطاقة يطوي/يوسّع (عرض فقط) — لا يمسّ منطق الإعلانات
        onTap: () => setState(() => _announcementExpanded = !expanded),
        radius: SdRadius.lg,
        depth: 5,
        edgeColor: t.tintEdge,
        glowColor: const Color(0x4DEF6C00),
        padding: EdgeInsets.symmetric(
            horizontal: l.isPhone ? 12 : 14, vertical: l.isPhone ? 7 : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── الشريط الرفيع (دائماً ظاهر) ──
            Row(
              children: [
                SdIconCube(
                    icon: Icons.campaign_rounded,
                    group: SdGroup.comms,
                    size: smallCube),
                const SizedBox(width: 10),
                Text('التعليمات الجديدة',
                    style: SdText.caption.copyWith(
                        color: t.text, fontWeight: FontWeight.w900)),
                if (_unreadAnnouncementsCount > 0) ...[
                  const SizedBox(width: 6),
                  SdBadge(count: _unreadAnnouncementsCount),
                ],
                const SizedBox(width: 10),
                // تلميح العنوان عند الطيّ
                Expanded(
                  child: expanded
                      ? const SizedBox.shrink()
                      : Text(title.isNotEmpty ? title : body,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SdText.bodySm),
                ),
                const SizedBox(width: 6),
                Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: t.text,
                    size: 20),
                if (!l.isCompactPhone) ...[
                  const SizedBox(width: 8),
                  // زر عرض التعليمات — يبقى يفتح نفس الشاشة
                  SdRaised(
                    onTap: () => _showAnnouncementPopup(ann),
                    radius: SdRadius.sm,
                    depth: 3,
                    color: t.tint,
                    edgeColor: t.tintEdge,
                    glowColor: const Color(0x26EF6C00),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    semanticLabel: 'عرض التعليمات',
                    child: Text('عرض التعليمات',
                        style: SdText.caption.copyWith(
                            color: t.text, fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
            // ── المحتوى الموسّع (عند الطلب فقط) ──
            if (expanded) ...[
              const SizedBox(height: 8),
              if (title.isNotEmpty)
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SdText.label),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: SdText.bodySm),
              ],
            ],
            // ── مؤشّر التدوير (نقاط) ──
            if (_myAnnouncements.length > 1) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children:
                    List.generate(_myAnnouncements.length.clamp(0, 6), (i) {
                  final on = i == _currentAnnouncementIndex;
                  return Container(
                    width: on ? 18 : 5,
                    height: 5,
                    margin: const EdgeInsetsDirectional.only(end: 3),
                    decoration: BoxDecoration(
                      color: on ? t.base : t.tintEdge,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// نافذة منبثقة لتفاصيل الإعلان
  /// عرض نافذة تفاصيل إعلان (مشتركة — من البطاقة أو تلقائياً)
  void _showAnnouncementPopup(Map<String, dynamic> ann, {bool isAutoPopup = false}) {
    final isUrgent = ann['isUrgent'] == true;
    final blockDismiss = isUrgent && isAutoPopup;

    // تسجيل القراءة (إلا إذا عاجل تلقائي — ينتظر "قرأت وفهمت")
    if (!blockDismiss) {
      final annId = ann['id'];
      if (annId != null && ann['isRead'] != true) {
        AnnouncementService.instance.markAsRead(annId is int ? annId : int.tryParse(annId.toString()) ?? 0);
      }
    }

    final imageUrl = ann['imageUrl']?.toString();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final isMobile = screenW < 600;

    showDialog(
      context: context,
      barrierDismissible: !blockDismiss,
      useSafeArea: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: PopScope(
          canPop: !blockDismiss,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 12 : 16)),
            clipBehavior: Clip.antiAlias,
            insetPadding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 40, vertical: isMobile ? 24 : 40),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isMobile ? screenW : 450,
                maxHeight: isMobile ? screenH * 0.75 : 550,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 10 : 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isUrgent
                            ? [SdColors.danger, SdColors.danger]
                            : [SdColors.warningEdge, SdColors.warning],
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(isUrgent ? Icons.warning_rounded : Icons.campaign_rounded, color: Colors.white, size: isMobile ? 20 : 22),
                        SizedBox(width: isMobile ? 8 : 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isUrgent)
                                Text('تبليغ عاجل', style: TextStyle(color: Colors.white70, fontSize: isMobile ? 10 : 11, fontWeight: FontWeight.bold)),
                              Text(
                                ann['title']?.toString() ?? '',
                                style: TextStyle(color: Colors.white, fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.bold),
                                maxLines: 2, overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (!blockDismiss)
                          InkWell(
                            onTap: () => Navigator.pop(ctx),
                            child: const Icon(Icons.close, color: Colors.white70, size: 22),
                          ),
                      ],
                    ),
                  ),
                  // Image
                  if (hasImage)
                    Container(
                      width: double.infinity,
                      constraints: BoxConstraints(maxHeight: isMobile ? 120 : 180),
                      child: Image.network(
                        imageUrl.startsWith('http') ? imageUrl : '${ApiConfig.baseUrl.replaceFirst('/api', '')}$imageUrl',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  // Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(isMobile ? 12 : 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          ann['body']?.toString() ?? '',
                          style: TextStyle(fontSize: isMobile ? 14 : 15, color: SdColors.neutralBase, height: 1.7),
                        ),
                      ),
                    ),
                  ),
                  // Footer
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: isMobile ? 8 : 10),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: SdColors.divider))),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline, size: 13, color: SdColors.faint),
                        const SizedBox(width: 4),
                        Flexible(child: Text(ann['createdBy']?.toString() ?? '', style: TextStyle(fontSize: isMobile ? 11 : 12, color: SdColors.muted), overflow: TextOverflow.ellipsis)),
                        const Spacer(),
                        if (blockDismiss)
                          ElevatedButton.icon(
                            onPressed: () {
                              final annId = ann['id'];
                              if (annId != null) {
                                AnnouncementService.instance.markAsRead(annId is int ? annId : int.tryParse(annId.toString()) ?? 0);
                              }
                              Navigator.pop(ctx);
                              _fetchCounters();
                            },
                            icon: Icon(Icons.check_circle, size: isMobile ? 16 : 18),
                            label: Text('قرأت وفهمت', style: TextStyle(fontSize: isMobile ? 12 : 14)),
                            style: ElevatedButton.styleFrom(backgroundColor: SdColors.danger, foregroundColor: Colors.white),
                          )
                        else ...[
                          if (ann['createdAt'] != null) ...[
                            Icon(Icons.access_time, size: 13, color: SdColors.faint),
                            const SizedBox(width: 3),
                            Text(_formatAnnDate(ann['createdAt'].toString()), style: TextStyle(fontSize: isMobile ? 10 : 12, color: SdColors.muted)),
                          ],
                        ],
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
  }

  String _formatAnnDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  /// نافذة إعلانات تلقائية بعد تسجيل الدخول
  void _showAutoAnnouncementPopup() {
    if (_myAnnouncements.isEmpty) return;
    final unread = _myAnnouncements.where((a) => a['isRead'] != true).toList();
    if (unread.isEmpty) return;

    // الأولوية: عاجل أولاً، ثم مثبت، ثم الأحدث
    final ann = unread.firstWhere(
      (a) => a['isUrgent'] == true,
      orElse: () => unread.firstWhere(
        (a) => a['isPinned'] == true,
        orElse: () => unread.first,
      ),
    );

    _showAnnouncementPopup(ann, isAutoPopup: true);
  }

  // شبكة عناصر القائمة - تخطيط شبكي فاخر
  Widget _buildMenuGrid() {
    final l = context.sd;

    // ── العمليات الميدانية ──
    final fieldTiles = <Widget?>[
      _menuTile(
        title: 'صفحة الوكيل',
        subtitle: 'إدارة خدمات العملاء',
        icon: Icons.person_outline,
        group: SdGroup.field,
        permissionKey: 'agent',
        onTap: () => _navigateToFtth(),
      ),
      _menuTile(
        title: 'المهام',
        subtitle: 'إدارة المهام اليومية',
        icon: Icons.task_alt,
        group: SdGroup.field,
        permissionKey: 'tasks',
        badge: _openTasksCount,
        onTap: () => _navigateTo(TaskListScreen(
          username: widget.username,
          permissions: widget.permissions,
          department: _resolvedDepartments,
          center: widget.center,
        )),
      ),
      _menuTile(
        title: 'الزونات',
        subtitle: 'إدارة المناطق الجغرافية',
        icon: Icons.map_outlined,
        group: SdGroup.field,
        permissionKey: 'zones',
        onTap: () => _navigateTo(AriaPage(
          username: widget.username,
          permissions: widget.permissions,
          department: _resolvedDepartments,
          center: widget.center,
        )),
      ),
      _menuTile(
        title: 'خريطة الزونات',
        subtitle: 'خريطة تفاعلية لنقاط FAT والمناطق',
        icon: Icons.location_on_rounded,
        group: SdGroup.field,
        permissionKey: 'zones',
        onTap: () => _navigateTo(const KmlZonesMapPage()),
      ),
      _menuTile(
        title: 'مشترك جديد',
        subtitle: 'تسجيل مشترك FTTH جديد',
        icon: Icons.person_add_alt_1_rounded,
        group: SdGroup.field,
        permissionKey: '',
        onTap: () => _navigateTo(CustomerHubPage(
          authToken: DualAuthService.instance.ftthToken ?? '',
        )),
      ),
      _menuTile(
        title: 'مشتركي IPTV',
        subtitle: 'إدارة اشتراكات التلفزيون',
        icon: Icons.live_tv_rounded,
        group: SdGroup.field,
        permissionKey: 'iptv',
        onTap: () => _navigateTo(const IptvSubscribersPage()),
      ),
      _menuTile(
        title: 'صفحة وكيل الساس',
        subtitle: 'حسابات الساس ولوحة الوكيل والمشتركين',
        icon: Icons.dns_rounded,
        group: SdGroup.field,
        permissionKey: 'sas_agent',
        onTap: () => _navigateTo(const SasAgentPage()),
      ),
    ].whereType<Widget>().toList();

    // ── الإدارة والموارد ──
    final adminTiles = <Widget?>[
      _menuTile(
        title: 'HR',
        subtitle: 'الموارد البشرية والحضور والرواتب',
        icon: Icons.groups_rounded,
        group: SdGroup.admin,
        permissionKey: 'hr',
        badge: _pendingEmployeeRequests,
        onTap: () => _navigateTo(HrHubPage(
          username: widget.username,
          permissions: widget.permissions,
          department: widget.department,
          center: widget.center,
          tenantId: widget.tenantId,
          tenantCode: widget.tenantCode,
        )),
      ),
      _menuTile(
        title: 'شاشتي',
        subtitle: 'البصمة والمعاملات والراتب',
        icon: Icons.dashboard_rounded,
        group: SdGroup.admin,
        permissionKey: 'my_dashboard',
        onTap: () => _navigateTo(MyDashboardPage(
          username: widget.username,
          permissions: widget.permissions,
          center: widget.center,
        )),
      ),
      _menuTile(
        title: 'المتابعة',
        subtitle: 'متابعة وتقييم المهام',
        icon: Icons.fact_check_rounded,
        group: SdGroup.admin,
        permissionKey: 'follow_up',
        onTap: () => _navigateTo(FollowUpPage(
          username: widget.username,
          permissions: widget.permissions,
          department: _resolvedDepartments,
          center: widget.center,
        )),
      ),
      _menuTile(
        title: 'المخازن',
        subtitle: 'إدارة المواد والمستودعات',
        icon: Icons.warehouse_rounded,
        group: SdGroup.admin,
        permissionKey: 'inventory',
        onTap: () => _navigateTo(PermissionGate.page(
          permission: 'inventory',
          pageName: 'المخازن',
          child: InventoryPage(
            companyId: widget.tenantId,
          ),
        )),
      ),
      _menuTile(
        title: 'الحسابات',
        subtitle: 'النظام المالي والمحاسبي',
        icon: Icons.account_balance_wallet,
        group: SdGroup.admin,
        permissionKey: 'accounting',
        onTap: () => _navigateTo(PermissionGate.page(
          permission: 'accounting',
          pageName: 'الحسابات',
          child: AccountingDashboardPage(
            companyId: widget.tenantId,
          ),
        )),
      ),
      _menuTile(
        title: 'صفحة الشركة',
        subtitle: 'لوحة تحكم الشركة',
        icon: Icons.business,
        group: SdGroup.admin,
        permissionKey: '',
        onTap: () => _navigateTo(const FtthCompanyPage()),
      ),
    ].whereType<Widget>().toList();

    // ── التواصل ──
    final commsTiles = <Widget?>[
      _menuTile(
        title: 'المحادثة',
        subtitle: 'محادثات الموظفين الداخلية',
        icon: Icons.forum_rounded,
        group: SdGroup.comms,
        permissionKey: 'chat',
        badge: _unreadChatCount,
        onTap: () => _navigateTo(const ChatRoomsPage()),
      ),
      _menuTile(
        title: 'التبليغات',
        subtitle: 'الإعلانات والتبليغات',
        icon: Icons.campaign_rounded,
        group: SdGroup.comms,
        permissionKey: 'announcements',
        badge: _unreadAnnouncementsCount,
        onTap: () => _navigateTo(const AnnouncementsPage()),
      ),
    ].whereType<Widget>().toList();

    // ── المنصّات والبيانات ──
    final platformTiles = <Widget?>[
      _menuTile(
        title: 'منصة الصدارة',
        subtitle: 'طلبات المواطن والوكيل',
        icon: Icons.hub_rounded,
        group: SdGroup.platform,
        permissionKey: 'sadara_portal',
        onTap: () => _navigateTo(const Scaffold(
          body: SadaraPortalPage(),
        )),
      ),
      _menuTile(
        title: 'سجل العقارات',
        subtitle: 'عنوان وطني (QR + NPN) ومواطنون وخدمات',
        icon: Icons.home_work_rounded,
        group: SdGroup.platform,
        permissionKey: 'property_registry',
        onTap: () => _navigateTo(const PropertiesListPage()),
      ),
      _menuTile(
        title: 'البحث بالذكاء الاصطناعي',
        subtitle: 'البحث المتقدم والذكي',
        icon: Icons.psychology,
        group: SdGroup.platform,
        permissionKey: 'ai_search',
        onTap: () => _navigateTo(const SearchUsersPage()),
      ),
    ].whereType<Widget>().toList();

    // كل الأقسام تظهر دائماً (أُزيل شريط الفلاتر بطلب المستخدم)
    final children = <Widget>[];

    if (fieldTiles.isNotEmpty) {
      children
        ..add(SdSectionHeader(
            title: 'العمليات الميدانية', tone: SdGroup.field.tone))
        ..add(SdTileGrid(
            maxColumns: 4, minTileWidth: 260, children: fieldTiles))
        ..add(SizedBox(height: l.isPhone ? 10 : 12));
    }

    // قسم موحّد: الإدارة والموارد · التواصل
    final combined = <Widget>[...adminTiles, ...commsTiles];
    if (combined.isNotEmpty) {
      children
        ..add(_adminCommsHeader(
          showAdmin: adminTiles.isNotEmpty,
          showComms: commsTiles.isNotEmpty,
        ))
        ..add(SdTileGrid(
            maxColumns: 4, minTileWidth: 260, children: combined))
        ..add(SizedBox(height: l.isPhone ? 10 : 12));
    }

    if (platformTiles.isNotEmpty) {
      children
        ..add(SdSectionHeader(
            title: 'المنصّات والبيانات', tone: SdGroup.platform.tone))
        ..add(SdTileGrid(
            maxColumns: 4, minTileWidth: 260, children: platformTiles));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// بلاطة قسم موحّدة (SdMenuTile) تحترم الصلاحية — null إن لم تُمنح.
  Widget? _menuTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required SdGroup group,
    required String permissionKey,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    if (permissionKey.isNotEmpty &&
        !PermissionManager.instance.canView(permissionKey)) {
      return null;
    }
    return SdMenuTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      group: group,
      badge: badge > 0 ? badge : null,
      onTap: onTap,
    );
  }

  /// عنوان قسم «الإدارة والموارد · التواصل» بمربّعين ملوّنين.
  Widget _adminCommsHeader({required bool showAdmin, required bool showComms}) {
    final adminT = SdGroup.admin.tone;
    final commsT = SdGroup.comms.tone;
    Widget label(SdTone t, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: t.base,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: t.edge, offset: const Offset(0, 3))],
              ),
            ),
            const SizedBox(width: 10),
            Text(text, style: SdText.titleSm),
          ],
        );
    if (showAdmin && showComms) {
      return Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.sm),
        child: Wrap(
          spacing: 18,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            label(adminT, 'الإدارة والموارد'),
            label(commsT, 'التواصل'),
          ],
        ),
      );
    }
    if (showAdmin) {
      return SdSectionHeader(title: 'الإدارة والموارد', tone: adminT);
    }
    return SdSectionHeader(title: 'التواصل', tone: commsT);
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final r = context.responsive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: SdColors.info, size: r.iconSizeSmall),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w700,
              fontSize: r.subtitleSize,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: SdColors.muted,
                fontSize: r.captionSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation() {
    final r = context.responsive;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.logout, color: SdColors.danger),
              const SizedBox(width: 10),
              const Expanded(child: Text('تأكيد تسجيل الخروج')),
            ],
          ),
          content: Text(
            'هل أنت متأكد من رغبتك في تسجيل الخروج من التطبيق؟',
            style: TextStyle(fontSize: r.titleSize),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'إلغاء',
                style: TextStyle(color: SdColors.muted),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.danger,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'تسجيل الخروج',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPermissionDenied() {
    final r = context.responsive;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('صلاحية غير كافية',
            style: TextStyle(color: SdColors.danger, fontWeight: FontWeight.bold)),
        content: const Text(
          'ليس لديك صلاحية الوصول إلى هذه الصفحة.\nيرجى الاتصال على 07727787789 المسؤول.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('حسنًا', style: TextStyle(fontSize: r.titleSize)),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  void _showMaintenanceMessagesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MaintenanceMessagesDialog(
        currentUserName: widget.username,
      ),
    );

    // إذا تم حفظ الرسائل بنجاح، عرض رسالة تأكيد
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث رسائل الصيانة بنجاح'),
          backgroundColor: SdColors.success,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

// ��فس الكلاسات الثانوية التي أرسلتها (لا تغيير عليها):
class PermissionsManagementPanel extends StatelessWidget {
  final bool isAdmin;
  final Map<String, bool> permissions;
  final Function(String, bool) onSave;
  final String username;

  const PermissionsManagementPanel({
    super.key,
    required this.isAdmin,
    required this.permissions,
    required this.onSave,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Container(
      padding: EdgeInsets.all(r.contentPaddingH),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          Text(
            'إدارة صلاحيات المستخدمين',
            style: TextStyle(
              fontSize: r.titleSize,
              fontWeight: FontWeight.bold,
              color: SdColors.info,
            ),
          ),
          const Divider(thickness: 2),
          const SizedBox(height: 10),
          const Text(
            'المستخدم الحالي:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            username,
            style: const TextStyle(color: SdColors.info),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView(
              children: [
                // ═══ صلاحيات النظام الأول (تُولّد تلقائياً من السجل المركزي) ═══
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '— النظام الأول —',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SdColors.warning,
                      fontSize: r.subtitleSize,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                ...PermissionRegistry.firstSystem.map(
                  (entry) => _buildPermissionSwitch(
                    title: entry.labelAr,
                    value: permissions[entry.key] ?? false,
                    onChanged: (v) => onSave(entry.key, v),
                  ),
                ),
                // ═══ صلاحيات النظام الثاني (تُولّد تلقائياً من السجل المركزي) ═══
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '— النظام الثاني (FTTH) —',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SdColors.accent,
                      fontSize: r.subtitleSize,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                ...PermissionRegistry.secondSystem.map(
                  (entry) => _buildPermissionSwitch(
                    title: entry.labelAr,
                    value: permissions[entry.key] ?? false,
                    onChanged: (v) => onSave(entry.key, v),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حفظ وإغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionSwitch({
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: isAdmin ? onChanged : null,
      secondary: Icon(
        value ? Icons.lock_open : Icons.lock_outline,
        color: value ? SdColors.success : SdColors.danger,
      ),
    );
  }
}

class UserInfoDialog extends StatelessWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;
  final String salary;
  final bool isAdmin;

  const UserInfoDialog({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
    required this.salary,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Container(
        padding: EdgeInsets.all(r.cardPadding),
        decoration: BoxDecoration(
          color: SdColors.infoTint,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(Icons.person_pin, color: SdColors.info, size: r.iconSizeLarge),
            const SizedBox(width: 10),
            Text(
              'معلومات المستخدم',
              style: TextStyle(
                color: SdColors.info,
                fontWeight: FontWeight.bold,
                fontSize: r.titleSize,
              ),
            ),
          ],
        ),
      ),
      content: Container(
        padding: EdgeInsets.all(r.contentPaddingH),
        decoration: BoxDecoration(
          color: SdColors.surfaceAlt,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoTile(context, Icons.person, 'اسم المستخدم', username),
            const Divider(height: 20),
            _infoTile(
                context, Icons.admin_panel_settings, 'الصلاحيات', permissions),
            const Divider(height: 20),
            _infoTile(context, Icons.business, 'القسم', department),
            const Divider(height: 20),
            _infoTile(context, Icons.location_on, 'المركز', center),
            const Divider(height: 20),
            _infoTile(context, Icons.attach_money, 'الراتب', salary),
            if (isAdmin) ...[
              const Divider(height: 20),
              _infoTile(context, Icons.security, 'حالة المدير', 'مفعل'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.close),
          label: const Text('إغلاق'),
          style: TextButton.styleFrom(
            foregroundColor: SdColors.danger,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _infoTile(
      BuildContext context, IconData icon, String title, String value) {
    final r = context.responsive;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: SdColors.infoTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: SdColors.info, size: r.iconSizeMedium),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: SdColors.muted,
                  fontSize: r.bodySize,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: r.titleSize,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// رسام الأمواج الشعاعية (مقياس الأمواج) — نفس تصميم FTTH
// ═══════════════════════════════════════════════════════════════════
class _HomeRadialWavePainter extends CustomPainter {
  final double progress; // 0..1
  final Color color1;
  final Color color2;
  final double animValue; // 0..1 لتحريك الأمواج

  _HomeRadialWavePainter({
    required this.progress,
    required this.color1,
    required this.color2,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = math.min(size.width, size.height) / 2;
    final innerRadius = outerRadius * 0.52;
    final spikeCount = 72;

    // دائرة داخلية بيضاء
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

      final maxSpikeLen = (outerRadius - innerRadius - 2) * waveHeight;

      final startX = center.dx + (innerRadius + 2) * math.cos(angle);
      final startY = center.dy + (innerRadius + 2) * math.sin(angle);
      final start = Offset(startX, startY);

      final isActive = spikeProgress <= progress;

      if (isActive) {
        final t = spikeProgress;
        final spikeColor = Color.lerp(color1, color2, t)!;

        final endX = startX + maxSpikeLen * math.cos(angle);
        final endY = startY + maxSpikeLen * math.sin(angle);
        final end = Offset(endX, endY);

        // هالة
        final glowPaint = Paint()
          ..color = spikeColor.withValues(alpha: 0.15)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
        canvas.drawLine(start, end, glowPaint);

        // الشوكة
        final spikePaint = Paint()
          ..color = spikeColor.withValues(alpha: 0.85)
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(start, end, spikePaint);

        // نقطة مضيئة
        if (waveHeight > 0.65) {
          final tipPaint = Paint()
            ..color = spikeColor.withValues(alpha: 0.6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
          canvas.drawCircle(end, 1.2, tipPaint);
        }
      } else {
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

    // هالة ملونة خارجية
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
            center: center, radius: (outerRadius + innerRadius) / 2),
        -math.pi / 2,
        glowAngle,
        false,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HomeRadialWavePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color1 != color1 ||
        oldDelegate.color2 != color2 ||
        oldDelegate.animValue != animValue;
  }
}

// ═══════════════════════════════════════════════════════════════════
// رسام خلفية رموز الإنترنت المتحركة
// ═══════════════════════════════════════════════════════════════════
class _InternetIconsBgPainter extends CustomPainter {
  final double animValue;
  final Color color;

  _InternetIconsBgPainter({
    required this.animValue,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    final icons = <_HomeIconDef>[
      // WiFi
      _HomeIconDef(0.08, 0.12, 0, 42),
      _HomeIconDef(0.85, 0.08, 0, 36),
      _HomeIconDef(0.45, 0.88, 0, 40),
      _HomeIconDef(0.92, 0.55, 0, 34),
      _HomeIconDef(0.15, 0.72, 0, 38),
      // Globe
      _HomeIconDef(0.72, 0.18, 1, 40),
      _HomeIconDef(0.25, 0.42, 1, 34),
      _HomeIconDef(0.60, 0.65, 1, 36),
      _HomeIconDef(0.05, 0.45, 1, 30),
      // Signal bars
      _HomeIconDef(0.55, 0.10, 2, 36),
      _HomeIconDef(0.35, 0.58, 2, 32),
      _HomeIconDef(0.80, 0.78, 2, 38),
      _HomeIconDef(0.18, 0.25, 2, 30),
      // Cloud
      _HomeIconDef(0.40, 0.22, 3, 42),
      _HomeIconDef(0.75, 0.42, 3, 36),
      _HomeIconDef(0.10, 0.88, 3, 40),
      _HomeIconDef(0.90, 0.30, 3, 32),
      // Ethernet
      _HomeIconDef(0.30, 0.78, 4, 34),
      _HomeIconDef(0.65, 0.48, 4, 30),
      _HomeIconDef(0.50, 0.35, 4, 36),
      _HomeIconDef(0.20, 0.55, 4, 28),
      // Router
      _HomeIconDef(0.82, 0.88, 5, 40),
      _HomeIconDef(0.12, 0.05, 5, 34),
      _HomeIconDef(0.55, 0.52, 5, 30),
      // Server
      _HomeIconDef(0.03, 0.32, 6, 38),
      _HomeIconDef(0.68, 0.02, 6, 32),
      _HomeIconDef(0.95, 0.68, 6, 28),
      // Shield
      _HomeIconDef(0.38, 0.05, 7, 34),
      _HomeIconDef(0.78, 0.60, 7, 30),
      _HomeIconDef(0.22, 0.90, 7, 36),
    ];

    for (int i = 0; i < icons.length; i++) {
      final def = icons[i];
      final phase = i * 0.37;
      final floatX = math.sin(animValue * math.pi * 2 + phase) * 12;
      final floatY = math.cos(animValue * math.pi * 2 + phase * 1.3) * 10;
      final alpha = 0.6 + math.sin(animValue * math.pi * 2 + phase * 0.7) * 0.4;

      final cx = size.width * def.x + floatX;
      final cy = size.height * def.y + floatY;
      final s = def.size;

      final iconColor = color.withValues(alpha: color.a * alpha);
      paint.color = iconColor;
      paint.strokeWidth = s * 0.12;
      fillPaint.color = iconColor;

      switch (def.type) {
        case 0:
          _drawWifi(canvas, cx, cy, s, paint);
          break;
        case 1:
          _drawGlobe(canvas, cx, cy, s, paint);
          break;
        case 2:
          _drawSignal(canvas, cx, cy, s, fillPaint);
          break;
        case 3:
          _drawCloud(canvas, cx, cy, s, paint);
          break;
        case 4:
          _drawEthernet(canvas, cx, cy, s, fillPaint, paint);
          break;
        case 5:
          _drawRouter(canvas, cx, cy, s, paint, fillPaint);
          break;
        case 6:
          _drawServer(canvas, cx, cy, s, paint, fillPaint);
          break;
        case 7:
          _drawShield(canvas, cx, cy, s, paint);
          break;
      }
    }
  }

  void _drawWifi(Canvas canvas, double cx, double cy, double s, Paint p) {
    final rect1 = Rect.fromCenter(center: Offset(cx, cy), width: s, height: s);
    final rect2 = Rect.fromCenter(
        center: Offset(cx, cy), width: s * 0.65, height: s * 0.65);
    final rect3 = Rect.fromCenter(
        center: Offset(cx, cy), width: s * 0.3, height: s * 0.3);
    p.strokeWidth = s * 0.07;
    canvas.drawArc(rect1, -math.pi * 0.75, math.pi * 0.5, false, p);
    canvas.drawArc(rect2, -math.pi * 0.75, math.pi * 0.5, false, p);
    canvas.drawArc(rect3, -math.pi * 0.75, math.pi * 0.5, false, p);
    canvas.drawCircle(
        Offset(cx, cy + s * 0.15), s * 0.06, p..style = PaintingStyle.fill);
    p.style = PaintingStyle.stroke;
  }

  void _drawGlobe(Canvas canvas, double cx, double cy, double s, Paint p) {
    final r = s * 0.45;
    p.strokeWidth = s * 0.06;
    canvas.drawCircle(Offset(cx, cy), r, p);
    canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), p);
    final ovalRect =
        Rect.fromCenter(center: Offset(cx, cy), width: r, height: r * 2);
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
    path.moveTo(cx - s * 0.35, cy + s * 0.1);
    path.quadraticBezierTo(
        cx - s * 0.45, cy - s * 0.15, cx - s * 0.15, cy - s * 0.2);
    path.quadraticBezierTo(
        cx - s * 0.05, cy - s * 0.45, cx + s * 0.15, cy - s * 0.2);
    path.quadraticBezierTo(
        cx + s * 0.4, cy - s * 0.25, cx + s * 0.35, cy + s * 0.1);
    path.close();
    canvas.drawPath(path, p);
  }

  void _drawEthernet(
      Canvas canvas, double cx, double cy, double s, Paint fill, Paint stroke) {
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
      Canvas canvas, double cx, double cy, double s, Paint stroke, Paint fill) {
    stroke.strokeWidth = s * 0.06;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
          center: Offset(cx, cy + s * 0.1), width: s * 0.6, height: s * 0.3),
      Radius.circular(s * 0.05),
    );
    canvas.drawRRect(bodyRect, stroke);
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
    canvas.drawCircle(Offset(cx - s * 0.2, cy - s * 0.3), s * 0.04, fill);
    canvas.drawCircle(Offset(cx + s * 0.2, cy - s * 0.3), s * 0.04, fill);
  }

  void _drawServer(
      Canvas canvas, double cx, double cy, double s, Paint stroke, Paint fill) {
    stroke.strokeWidth = s * 0.06;
    final top = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - s * 0.3, cy - s * 0.3, s * 0.6, s * 0.25),
      Radius.circular(s * 0.04),
    );
    final bot = RRect.fromRectAndRadius(
      Rect.fromLTWH(cx - s * 0.3, cy + s * 0.02, s * 0.6, s * 0.25),
      Radius.circular(s * 0.04),
    );
    canvas.drawRRect(top, stroke);
    canvas.drawRRect(bot, stroke);
    canvas.drawCircle(Offset(cx + s * 0.15, cy - s * 0.17), s * 0.035, fill);
    canvas.drawCircle(Offset(cx + s * 0.15, cy + s * 0.15), s * 0.035, fill);
  }

  void _drawShield(Canvas canvas, double cx, double cy, double s, Paint p) {
    p.strokeWidth = s * 0.07;
    final path = Path();
    path.moveTo(cx, cy - s * 0.4);
    path.lineTo(cx - s * 0.3, cy - s * 0.2);
    path.lineTo(cx - s * 0.3, cy + s * 0.1);
    path.quadraticBezierTo(cx, cy + s * 0.4, cx + s * 0.3, cy + s * 0.1);
    path.lineTo(cx + s * 0.3, cy - s * 0.2);
    path.close();
    canvas.drawPath(path, p);
    p.strokeWidth = s * 0.08;
    canvas.drawLine(
      Offset(cx - s * 0.1, cy),
      Offset(cx - s * 0.02, cy + s * 0.1),
      p,
    );
    canvas.drawLine(
      Offset(cx - s * 0.02, cy + s * 0.1),
      Offset(cx + s * 0.12, cy - s * 0.08),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _InternetIconsBgPainter oldDelegate) {
    return oldDelegate.animValue != animValue || oldDelegate.color != color;
  }
}

class _HomeIconDef {
  final double x;
  final double y;
  final int type;
  final double size;
  const _HomeIconDef(this.x, this.y, this.type, this.size);
}

/// لوحة الإشعارات — تظهر كـ BottomSheet
class _NotificationsPanel extends StatefulWidget {
  final VoidCallback? onRead;
  const _NotificationsPanel({this.onRead});

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await NotificationApiService.instance.getMyNotifications(
        pageSize: 30,
        unreadOnly: _unreadOnly ? true : null,
      );
      if (res['success'] == true && mounted) {
        final items = res['data'] is List ? res['data'] as List : [];
        setState(() => _notifications = items.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(int id) async {
    await NotificationApiService.instance.markAsRead(id);
    widget.onRead?.call();
    _load();
  }

  Future<void> _markAllRead() async {
    await NotificationApiService.instance.markAllAsRead();
    widget.onRead?.call();
    _load();
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'RequestStatusUpdate': return Icons.task_alt_rounded;
      case 'RequestAssigned': return Icons.assignment_ind_rounded;
      case 'AgentRequest': return Icons.storefront_rounded;
      case 'ChatMessage': return Icons.chat_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'RequestStatusUpdate': return SdColors.info;
      case 'RequestAssigned': return SdColors.accent;
      case 'AgentRequest': return SdColors.warning;
      case 'ChatMessage': return SdColors.success;
      default: return SdColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40, height: 4,
            decoration: BoxDecoration(color: SdColors.edge, borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.notifications_rounded, color: SdColors.primary, size: 24),
                const SizedBox(width: 8),
                const Text('الإشعارات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SdColors.primary)),
                const Spacer(),
                // فلتر غير المقروءة
                FilterChip(
                  label: Text(_unreadOnly ? 'غير المقروءة' : 'الكل', style: const TextStyle(fontSize: 11)),
                  selected: _unreadOnly,
                  onSelected: (v) { setState(() => _unreadOnly = v); _load(); },
                  selectedColor: SdColors.primary.withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                // قراءة الكل
                IconButton(
                  tooltip: 'قراءة الكل',
                  icon: const Icon(Icons.done_all_rounded, size: 20),
                  onPressed: _markAllRead,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 48, color: SdColors.edge),
                            const SizedBox(height: 8),
                            Text('لا توجد إشعارات', style: TextStyle(color: SdColors.faint, fontSize: 14)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                          itemBuilder: (_, i) {
                            final n = _notifications[i];
                            final isRead = n['IsRead'] == true || n['isRead'] == true;
                            final type = n['Type']?.toString() ?? n['type']?.toString();
                            final title = n['TitleAr']?.toString() ?? n['Title']?.toString() ?? n['title']?.toString() ?? '';
                            final body = n['BodyAr']?.toString() ?? n['Body']?.toString() ?? n['body']?.toString() ?? '';
                            final id = n['Id'] ?? n['id'];
                            final createdAt = DateTime.tryParse(n['CreatedAt']?.toString() ?? n['createdAt']?.toString() ?? '');
                            final color = _typeColor(type);

                            return ListTile(
                              dense: true,
                              tileColor: isRead ? null : color.withValues(alpha: 0.05),
                              leading: Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_typeIcon(type), color: color, size: 20),
                              ),
                              title: Text(title, style: TextStyle(fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(body, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if (createdAt != null)
                                    Text(_timeAgo(createdAt), style: TextStyle(fontSize: 10, color: SdColors.faint)),
                                ],
                              ),
                              trailing: !isRead && id != null
                                  ? IconButton(
                                      icon: Icon(Icons.check_circle_outline, size: 18, color: color),
                                      tooltip: 'قراءة',
                                      onPressed: () => _markAsRead(id is int ? id : int.tryParse(id.toString()) ?? 0),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
    return '${dt.day}/${dt.month}';
  }
}
