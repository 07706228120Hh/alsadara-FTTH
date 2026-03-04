/// اسم الصفحة: الصفحة الرئيسية
/// وصف الصفحة: الصفحة الرئيسية للتطبيق تحتوي على الداشبورد والقوائم الرئيسية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:async'; // NEW
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:alsadara/pages/track_users_map_page.dart';
import '../task/task_list_screen.dart';
import 'hr_hub_page.dart';
import 'search_users_page.dart';
import 'users_page.dart';
import 'users_page_firebase.dart';
import 'users_page_vps.dart';
import '../ftth/auth/login_page.dart' as ftth_login;
import '../ftth/core/home_page.dart' as ftth_home;
import '../services/dual_auth_service.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http; // NEW
import 'dart:convert'; // NEW
import 'dart:math' as math; // NEW: for rotations
import 'aria_page.dart';
import '../utils/responsive_helper.dart';
import '../widgets/maintenance_messages_dialog.dart'; // إضافة حوار إعدادات الرسائل
import '../services/vps_auth_service.dart'; // ✅ خدمة VPS لتسجيل الخروج
import '../services/api/api_client.dart'; // ✅ ApiClient للتحقق من التوكن
import 'login/premium_login_page.dart'; // ✨ صفحة تسجيل الدخول الفخمة
import '../ftth/whatsapp/whatsapp_bottom_window.dart'; // WhatsApp floating button
import 'super_admin/super_admin_dashboard.dart'; // لوحة تحكم Super Admin
import 'company_diagnostics_page.dart'; // صفحة تشخيص الشركة
import 'company_settings_page.dart'; // إعدادات الشركة
import 'super_admin/sadara_portal_page.dart'; // منصة الصدارة
import 'accounting/accounting_dashboard_page.dart'; // نظام المحاسبة
import '../task/follow_up_page.dart'; // صفحة المتابعة
import '../task/audit_dashboard_page.dart'; // داشبورد التدقيق
// شاشتي - معاملات الفني
import 'my_dashboard_page.dart'; // شاشتي - لوحة الموظف الشخصية
import '../permissions/permissions.dart';
import '../services/task_api_service.dart';
import '../services/attendance_api_service.dart';
import '../widgets/update_dialog.dart'; // فحص التحديث التلقائي
// تم نقل زر جلب بيانات الموقع إلى النظام الثاني

class HomePage extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;
  final String salary;
  @Deprecated('استخدم PermissionManager.instance.canView() مباشرة')
  final Map<String, bool> pageAccess;
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
    this.pageAccess = const {},
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

  // NEW: الموقع
  bool _isLocationActive = false;
  Timer? _locationTimer;
  final Map<String, bool> _defaultPermissions = {
    'attendance': false,
    'agent': false,
    'tasks': false,
    'zones': false,
    'ai_search': false,
    'sadara_portal': false,
    'accounting': false,
    'diagnostics': false,
    'hr': false,
    'follow_up': false,
    'audit_dashboard': false,
    'my_dashboard': false,
  };

  Map<String, bool> _userPermissions = {};
  // حالة تسجيل دخول FTTH (النظام الثاني)
  bool _isFtthConnected = false;
  String? _ftthConnectedUsername;
  StreamSubscription<bool>? _ftthStateSubscription;
  // ===== عدادات الصفحة الرئيسية =====
  int _pendingAgentRequests = 0;
  int _openTasksCount = 0;
  int _pendingEmployeeRequests = 0; // إجازات + سلف
  bool _countersLoading = true;
  bool _counterRetried = false; // لمحاولة إعادة جلب العدادات مرة واحدة
  late final AnimationController _counterAnimController;

  // Unified fiber optic color
  final Color _fiberColor = const Color(0xFF00E5FF);

  // ===== القائمة الجانبية =====
  bool _sidebarExpanded = false;
  Timer? _autoCollapseTimer;
  // ألوان ثيم القائمة الجانبية (مطابقة لشاشة الحسابات)
  static const _sidebarBg = Colors.white;
  static const _sidebarBorder = Color(0xFFE8E8E8);
  static const _sidebarToolbar = Color(0xFF2C3E50);
  static const _sidebarTextDark = Color(0xFF333333);
  static const _sidebarTextGray = Color(0xFF999999);

  @override
  void initState() {
    super.initState();
    _counterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _initializeApp();
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
      await _loadUserPermissions();

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

      // جلب العدادات
      _fetchCounters();

      // فحص التحديث التلقائي بعد 5 ثوانٍ
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          UpdateManager.checkAndShowUpdateDialog(context);
        }
      });

      // إظهار زر واتساب ويب بعد التهيئة وإخفاء زر المحادثات
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showGlobalWhatsAppButton();
        }
      });
    } catch (e) {
      debugPrint('Error initializing app: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  // Unused function - commented out to fix lint warning
  // Future<void> _checkAdminStatus() async {
  //   final isAdmin = widget.permissions.toLowerCase().contains('مدير') ||
  //       widget.permissions.toLowerCase().contains('admin');
  //   setState(() => _isAdminUser = isAdmin);

  //   // المدير يحصل على جميع الصلاحيات تلقائياً ولا نحتاج لحفظها
  //   if (_isAdminUser) {
  //     setState(() {
  //       _userPermissions =
  //           _defaultPermissions.map((key, value) => MapEntry(key, true));
  //     });
  //   }  //   // if (_isAdminUser)
  // }

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
      debugPrint('⚠️ خطأ في فحص FTTH: $e');
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
        // 1) إحصائيات طلبات الخدمة (تشمل طلبات الوكلاء والمهام)
        TaskApiService.instance.getStatistics().catchError((e) {
          debugPrint('❌ خطأ في جلب الإحصائيات: $e');
          return <String, dynamic>{};
        }),
        // 2) ملخص الإجازات
        AttendanceApiService.instance.getLeaveSummary().catchError((e) {
          debugPrint('❌ خطأ في جلب الإجازات: $e');
          return <String, dynamic>{};
        }),
        // 3) طلبات السحب المعلقة (status=0 = Pending)
        AttendanceApiService.instance
            .getWithdrawalRequests(status: 0, page: 1, pageSize: 1)
            .catchError((e) {
          debugPrint('❌ خطأ في جلب السحب: $e');
          return <String, dynamic>{};
        }),
      ]);

      final statsRaw = results[0];
      final leaveSummaryRaw = results[1];
      final withdrawalsRaw = results[2];

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

      // طلبات الوكلاء الجديدة = Pending
      final pendingAgent = _safeInt(stats, 'Pending', 'pending');

      // المهام المفتوحة = Total - Completed - Cancelled - Rejected
      // (أفضل من جمع الحالات لأن بعض الحالات قد لا تكون في الاستجابة)
      final total = _safeInt(stats, 'Total', 'total');
      final completed = _safeInt(stats, 'Completed', 'completed');
      final cancelled = _safeInt(stats, 'Cancelled', 'cancelled');
      final rejected = _safeInt(stats, 'Rejected', 'rejected');
      final openTasks = total - completed - cancelled - rejected;
      debugPrint(
          '📊 حساب المهام: total=$total - completed=$completed - cancelled=$cancelled - rejected=$rejected = open=$openTasks');

      // طلبات الموظفين = إجازات معلقة + سحب معلقة
      final pendingLeaves = _safeInt(leaveSummary, 'Pending', 'pending');
      final pendingWithdrawals = _safeInt(withdrawals, 'Total', 'total');
      final employeeRequests = pendingLeaves + pendingWithdrawals;

      debugPrint('📊 عدادات: stats=$stats');
      debugPrint(
          '📊 agent=$pendingAgent, tasks=$openTasks, emp=$employeeRequests');

      if (mounted) {
        setState(() {
          _pendingAgentRequests = pendingAgent;
          _openTasksCount = openTasks;
          _pendingEmployeeRequests = employeeRequests;
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
      debugPrint('⚠️ خطأ في جلب العدادات: $e');
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

  Future<void> _loadUserPermissions() async {
    // V2: استخدام PermissionManager كمصدر وحيد للصلاحيات
    final pm = PermissionManager.instance;
    if (!pm.isLoaded) {
      await pm.loadPermissions();
    }
    final permissions = <String, bool>{};
    for (var key in _defaultPermissions.keys) {
      permissions[key] = pm.canView(key);
    }

    setState(() => _userPermissions = permissions);
  }

  // NEW: إرسال الموقع
  Future<void> _sendLiveLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await http.post(
        Uri.parse(
            'https://script.google.com/macros/s/AKfycbx0CoIlbxdl0Fn9QDNq_QPV3LcRhn2RUvpXhj5JV9XYBhbBLgaBwuFDK5juW8YODAFp/exec'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'اسم المستخدم': widget.username,
          'lat': position.latitude,
          'lng': position.longitude,
        }),
      );
    } catch (e) {
      debugPrint("مشكلة في إرسال الموقع: $e");
    }
  }

  // NEW: إيقاف إرسال الموقع
  Future<void> _stopLiveLocation() async {
    try {
      await http.delete(
        Uri.parse(
            'https://script.google.com/macros/s/AKfycbx0CoIlbxdl0Fn9QDNq_QPV3LcRhn2RUvpXhj5JV9XYBhbBLgaBwuFDK5juW8YODAFp/exec'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'اسم المستخدم': widget.username}),
      );
    } catch (e) {
      debugPrint("مشكلة في إيقاف مشاركة الموقع: $e");
    }
  }

  // Show global WhatsApp floating button
  void _showGlobalWhatsAppButton() {
    try {
      if (mounted) {
        // إخفاء زر المحادثات (خاص بـ FTTH فقط)
        WhatsAppBottomWindow.hideConversationsFloatingButton();
        // استخدام ensureFloatingButton لضمان إظهار الزر حتى لو كان مختفياً
        WhatsAppBottomWindow.ensureFloatingButton(context);
      }
    } catch (e) {
      debugPrint('Error showing WhatsApp floating button: $e');
    }
  }

  Future<void> _logout() async {
    // تسجيل الخروج من كلا النظامين (VPS + FTTH)
    try {
      await DualAuthService.instance.logoutAll();
    } catch (e) {
      debugPrint('⚠️ خطأ في تسجيل الخروج: $e');
    }

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

  Widget _buildEnhancedMenuItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
    required String permissionKey,
    int badgeCount = 0,
  }) {
    final hasPermission = PermissionManager.instance.canView(permissionKey);
    final r = context.responsive;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasPermission ? onTap : null,
          borderRadius: BorderRadius.circular(r.cardRadius),
          splashColor: gradient[0].withOpacity(0.1),
          highlightColor: gradient[0].withOpacity(0.05),
          child: Container(
            constraints: BoxConstraints(minHeight: r.menuItemHeight),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(r.cardRadius),
              border: Border.all(
                color: const Color(0xFFD5D5D5),
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: r.isMobile ? 10 : 16,
                  vertical: r.isMobile ? 6 : 8),
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
                          gradient: hasPermission
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: gradient,
                                )
                              : LinearGradient(
                                  colors: [
                                    Colors.grey[400]!,
                                    Colors.grey[500]!
                                  ],
                                ),
                          boxShadow: hasPermission
                              ? [
                                  BoxShadow(
                                    color: gradient[0].withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Icon(
                          icon,
                          color: Colors.white,
                          size: r.menuIconInnerSize,
                        ),
                      ),
                      if (badgeCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.red.withOpacity(0.4),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
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
                              color: hasPermission
                                  ? const Color(0xFF000000)
                                  : const Color(0xFF888888),
                              fontSize: r.menuItemTitleSize,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        SizedBox(height: r.isMobile ? 1 : 3),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            subtitle,
                            style: TextStyle(
                              color: hasPermission
                                  ? const Color(0xFF1A1A1A)
                                  : const Color(0xFFBBBBBB),
                              fontSize: r.menuItemSubtitleSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // سهم/قفل
                  Container(
                    width: r.menuArrowCircleSize,
                    height: r.menuArrowCircleSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasPermission
                          ? gradient[0].withOpacity(0.1)
                          : Colors.red.withOpacity(0.08),
                    ),
                    child: Icon(
                      hasPermission
                          ? Icons.arrow_forward_ios_rounded
                          : Icons.lock_rounded,
                      color: hasPermission ? gradient[0] : Colors.red[300],
                      size: r.menuArrowIconSize,
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

  @override
  void dispose() {
    _ftthStateSubscription?.cancel();
    _locationTimer?.cancel(); // NEW
    _autoCollapseTimer?.cancel();
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

  // Simple action button for AppBar
  Widget _buildAnimatedActionButton({
    required Icon icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color glowColor = Colors.cyanAccent,
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(horizontal: 4),
  }) {
    return Container(
      margin: margin,
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
          color: const Color(0xFFF5F6FA),
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
                        color: const Color(0xFF3498DB).withOpacity(0.2),
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
                      Color(0xFF3498DB),
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

    final r = context.responsive;

    return Scaffold(
      // ── درج جانبي للشاشات الصغيرة ──
      drawer: r.showSidebar
          ? null
          : Drawer(
              width: 260,
              child: SafeArea(child: _buildDrawerContent()),
            ),
      appBar: AppBar(
        toolbarHeight: r.appBarHeight,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        elevation: 0,
        leading: r.showSidebar
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: Icon(Icons.menu,
                      color: Colors.white, size: r.appBarIconSize),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2C3E50),
                Color(0xFF34495E),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2C3E50).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '⚡ رمز الصدارة',
              style: TextStyle(
                fontSize: r.appBarTitleSize,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isFtthConnected
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    boxShadow: [
                      BoxShadow(
                        color: (_isFtthConnected
                                ? Colors.greenAccent
                                : Colors.orangeAccent)
                            .withOpacity(0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _isFtthConnected
                      ? 'FTTH متصل ✓ ($_ftthConnectedUsername)'
                      : 'FTTH غير متصل',
                  style: TextStyle(
                    color: _isFtthConnected
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: r.labelSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(
          color: Colors.white,
          size: r.appBarIconSize,
        ),
        actions: [
          // زر العودة للوحة تحكم Super Admin
          if (widget.isSuperAdminMode)
            _buildAnimatedActionButton(
              icon: Icon(
                Icons.admin_panel_settings,
                color: Colors.amber,
                size: r.appBarIconSize,
              ),
              tooltip: 'العودة للوحة تحكم مدير النظام',
              glowColor: Colors.amber,
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => const SuperAdminDashboard(),
                  ),
                  (route) => false,
                );
              },
            ),
          // زر تفعيل/إيقاف الموقع بخلفية متحركة
          _buildAnimatedActionButton(
            icon: Icon(
              _isLocationActive ? Icons.location_on : Icons.location_off,
              color: _isLocationActive ? Colors.greenAccent : Colors.redAccent,
              size: r.appBarIconSize,
            ),
            tooltip: _isLocationActive
                ? 'إيقاف مشاركة الموقع'
                : 'تشغيل مشاركة الموقع',
            glowColor:
                _isLocationActive ? Colors.greenAccent : Colors.redAccent,
            onPressed: () async {
              if (!_isLocationActive) {
                setState(() => _isLocationActive = true);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                LocationPermission permission =
                    await Geolocator.requestPermission();

                if (!mounted) return;

                if (permission == LocationPermission.denied ||
                    permission == LocationPermission.deniedForever) {
                  setState(() => _isLocationActive = false);
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(
                        content: Text('يرجى السماح بالوصول إلى الموقع')),
                  );
                  return;
                }
                _locationTimer =
                    Timer.periodic(const Duration(seconds: 5), (timer) {
                  _sendLiveLocation();
                });
              } else {
                setState(() => _isLocationActive = false);
                _locationTimer?.cancel();
                await _stopLiveLocation();
              }
            },
          ),
          const SizedBox(width: 6),
          if (_isAdminUser)
            _buildAnimatedActionButton(
              icon: Icon(
                Icons.location_searching,
                color: Colors.white,
                size: r.appBarIconSize,
              ),
              tooltip: 'تتبع الكادر على الخريطة',
              glowColor: Colors.cyanAccent,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TrackUsersMapPage()),
                );
              },
            ),
        ],
      ),
      body: Row(
        children: [
          // ═══ القائمة الجانبية - فقط على الشاشات العريضة ═══
          if (r.showSidebar) _buildSidebar(),
          // ═══ المحتوى الرئيسي ═══
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  // ═══ محتوى الدرج الجانبي للشاشات الصغيرة ═══
  Widget _buildDrawerContent() {
    final r = context.responsive;
    return Container(
      color: _sidebarBg,
      child: Column(
        children: [
          const SizedBox(height: 16),
          // عنوان القائمة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.menu_open,
                    color: _sidebarToolbar, size: r.iconSizeSmall),
                const SizedBox(width: 8),
                Text(
                  'القائمة',
                  style: GoogleFonts.cairo(
                    fontSize: r.sectionTitleSize,
                    fontWeight: FontWeight.bold,
                    color: _sidebarToolbar,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _sidebarBorder),
          const SizedBox(height: 8),
          // عناصر القائمة
          if (_isAdminUser)
            _drawerBtn(
              icon: Icons.people,
              label: 'إدارة المستخدمين',
              color: const Color(0xFF3498DB),
              onTap: () {
                Navigator.pop(context); // أغلق الدرج
                final companyId =
                    widget.tenantId ?? VpsAuthService.instance.currentCompanyId;
                final companyCode = widget.tenantCode ??
                    VpsAuthService.instance.currentCompanyCode;
                final companyName = widget.department.isNotEmpty
                    ? widget.department
                    : (VpsAuthService.instance.currentCompanyName ?? 'الشركة');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        companyId != null && companyCode != null
                            ? UsersPageVPS(
                                companyId: companyId,
                                companyName: companyName,
                                permissions: {'users': true})
                            : companyId != null
                                ? UsersPageFirebase(
                                    tenantId: companyId,
                                    permissions: widget.permissions,
                                    pageAccess: widget.pageAccess)
                                : UsersPage(permissions: widget.permissions),
                  ),
                );
              },
            ),
          if (!_isAdminUser)
            _drawerBtn(
              icon: Icons.people_outline,
              label: 'المستخدمين',
              color: Colors.grey,
              onTap: () {
                Navigator.pop(context);
                _showPermissionDenied();
              },
            ),
          if (PermissionManager.instance.canView('diagnostics'))
            _drawerBtn(
              icon: Icons.bug_report,
              label: 'تشخيص النظام',
              color: const Color(0xFFE67E22),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CompanyDiagnosticsPage(
                        tenantId: widget.tenantId,
                        tenantCode: widget.tenantCode,
                        pageAccess: widget.pageAccess,
                      ),
                    ));
              },
            ),
          _drawerBtn(
              icon: Icons.settings,
              label: 'إعدادات الشركة',
              color: const Color(0xFFF39C12),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CompanySettingsPage(
                        companyId: widget.tenantId ??
                            VpsAuthService.instance.currentCompanyId,
                        companyCode: widget.tenantCode ??
                            VpsAuthService.instance.currentCompanyCode,
                        currentUserRole: widget.permissions,
                        currentUsername: widget.username,
                      ),
                    ));
              },
            ),
          _drawerBtn(
            icon: Icons.logout,
            label: 'تسجيل الخروج',
            color: const Color(0xFFE74C3C),
            onTap: () {
              Navigator.pop(context);
              _showLogoutConfirmation();
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  /// زر الدرج الجانبي (للشاشات الصغيرة)
  Widget _drawerBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final r = context.responsive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: color.withOpacity(0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: r.iconSizeSmall),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: GoogleFonts.cairo(
                        fontSize: r.subtitleSize,
                        fontWeight: FontWeight.w600,
                        color: _sidebarTextDark,
                      )),
                ),
                Icon(Icons.chevron_left,
                    color: _sidebarTextGray, size: r.iconSizeSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══ القائمة الجانبية (بنفس تصميم شاشة الحسابات) ═══
  Widget _buildSidebar() {
    final r = context.responsive;
    final expanded = _sidebarExpanded;
    final width = expanded ? r.sidebarExpandedWidth : r.sidebarCollapsedWidth;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
      decoration: BoxDecoration(
        color: _sidebarBg,
        border: const Border(
          left: BorderSide(color: _sidebarBorder, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // زر طي/فتح القائمة
          InkWell(
            onTap: () {
              _autoCollapseTimer?.cancel();
              setState(() => _sidebarExpanded = !_sidebarExpanded);
              if (_sidebarExpanded) {
                _autoCollapseTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted && _sidebarExpanded) {
                    setState(() => _sidebarExpanded = false);
                  }
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.menu_open,
                        color: _sidebarToolbar, size: r.iconSizeSmall),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 8),
                    Text(
                      'القائمة',
                      style: GoogleFonts.cairo(
                        fontSize: r.bodySize,
                        fontWeight: FontWeight.bold,
                        color: _sidebarToolbar,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: _sidebarBorder),
          const SizedBox(height: 8),
          // ── عناصر القائمة ──
          // إدارة المستخدمين (مدير فقط)
          if (_isAdminUser)
            _sidebarBtn(
              icon: Icons.people,
              label: 'إدارة المستخدمين',
              color: const Color(0xFF3498DB),
              onTap: () {
                final companyId =
                    widget.tenantId ?? VpsAuthService.instance.currentCompanyId;
                final companyCode = widget.tenantCode ??
                    VpsAuthService.instance.currentCompanyCode;
                final companyName = widget.department.isNotEmpty
                    ? widget.department
                    : (VpsAuthService.instance.currentCompanyName ?? 'الشركة');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        companyId != null && companyCode != null
                            ? UsersPageVPS(
                                companyId: companyId,
                                companyName: companyName,
                                permissions: {'users': true},
                              )
                            : companyId != null
                                ? UsersPageFirebase(
                                    tenantId: companyId,
                                    permissions: widget.permissions,
                                    pageAccess: widget.pageAccess,
                                  )
                                : UsersPage(permissions: widget.permissions),
                  ),
                );
              },
            ),
          // المستخدمين (محظور) لغير المدراء
          if (!_isAdminUser)
            _sidebarBtn(
              icon: Icons.people_outline,
              label: 'المستخدمين',
              color: Colors.grey,
              onTap: () => _showPermissionDenied(),
            ),
          // تشخيص النظام
          if (PermissionManager.instance.canView('diagnostics'))
            _sidebarBtn(
              icon: Icons.bug_report,
              label: 'تشخيص النظام',
              color: const Color(0xFFE67E22),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CompanyDiagnosticsPage(
                    tenantId: widget.tenantId,
                    tenantCode: widget.tenantCode,
                    pageAccess: widget.pageAccess,
                  ),
                ),
              ),
            ),
          // إعدادات الشركة
          _sidebarBtn(
            icon: Icons.settings,
            label: 'إعدادات الشركة',
            color: const Color(0xFFF39C12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CompanySettingsPage(
                  companyId: widget.tenantId ??
                      VpsAuthService.instance.currentCompanyId,
                  companyCode: widget.tenantCode ??
                      VpsAuthService.instance.currentCompanyCode,
                  currentUserRole: widget.permissions,
                  currentUsername: widget.username,
                ),
              ),
            ),
          ),
          // تسجيل الخروج
          _sidebarBtn(
            icon: Icons.logout,
            label: 'تسجيل الخروج',
            color: const Color(0xFFE74C3C),
            onTap: () => _showLogoutConfirmation(),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  /// زر القائمة الجانبية (بنفس تصميم شاشة الحسابات)
  Widget _sidebarBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final r = context.responsive;
    final expanded = _sidebarExpanded;
    return Tooltip(
      message: expanded ? '' : label,
      preferBelow: false,
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: expanded ? 8 : 6, vertical: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            hoverColor: color.withOpacity(0.08),
            splashColor: color.withOpacity(0.15),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 10 : 0, vertical: 10),
              child: expanded
                  ? Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child:
                              Icon(icon, color: color, size: r.iconSizeSmall),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: GoogleFonts.cairo(
                              fontSize: r.subtitleSize,
                              fontWeight: FontWeight.w600,
                              color: _sidebarTextDark,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_left,
                            color: _sidebarTextGray, size: r.iconSizeSmall),
                      ],
                    )
                  : Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: r.iconSizeSmall),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final r = context.responsive;
    final maxContentWidth = r.maxContentWidth;

    return Stack(
          children: [
            // Light background
            Container(
              color: const Color(0xFFF5F6FA),
            ),
            // رموز إنترنت ثابتة في الخلفية
            Positioned.fill(
              child: CustomPaint(
                painter: _InternetIconsBgPainter(
                  animValue: 0,
                  color: const Color(0xFF3498DB).withValues(alpha: 0.35),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // Add small top spacing to lower the company title a bit on phones
                  const SizedBox(height: 2),
                  // Compact header section
                  Container(
                    width: double.infinity,
                    padding:
                        EdgeInsets.symmetric(horizontal: r.contentPaddingH),
                    child: Column(
                      children: [
                        const SizedBox(height: 4),
                        // بطاقة ترحيب بتصميم فاتح
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: EdgeInsets.symmetric(
                              horizontal: r.isMobile ? 10 : 16,
                              vertical: r.isMobile ? 8 : 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFD5D5D5),
                              width: 2.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // صورة مستخدم
                              Container(
                                width: r.userAvatarSize,
                                height: r.userAvatarSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF3498DB),
                                      Color(0xFF2980B9)
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF3498DB)
                                          .withOpacity(0.3),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(2),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                  ),
                                  padding: const EdgeInsets.all(2),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(25),
                                    child: Image.asset(
                                      'assets/splash_background.jpg',
                                      width: r.userAvatarSize - 8,
                                      height: r.userAvatarSize - 8,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: r.isMobile ? 8 : 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '✨ مرحبا بكم في شركة الصدارة',
                                      style: TextStyle(
                                        color: const Color(0xFF000000),
                                        fontSize: r.captionSize + 1,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'مرحباً ${widget.username}',
                                      style: TextStyle(
                                        color: const Color(0xFF000000),
                                        fontSize: r.subtitleSize + 1,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    if (_isAdminUser) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 2),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // شخصية ترحيبية ثابتة
                              Text('🧔',
                                  style:
                                      TextStyle(fontSize: r.statValueSize)),
                              const SizedBox(width: 6),
                              // زر معلومات
                              InkWell(
                                onTap: () => _showUserInfo(context),
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  width: r.infoButtonSize,
                                  height: r.infoButtonSize,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3498DB)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: const Color(0xFF3498DB)
                                          .withOpacity(0.3),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.info_outline,
                                    color: const Color(0xFF3498DB),
                                    size: r.iconSizeSmall - 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ), // Enhanced menu section
                  // ===== عدادات سريعة =====
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: r.contentPaddingH),
                    child: _buildCountersRow(),
                  ),
                  SizedBox(height: r.isMobile ? 4 : 8),
                  Expanded(
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: r.contentPaddingH),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: maxContentWidth),
                          child: _buildMenuGrid(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
  }

  // التنقل إلى صفحة FTTH - مباشرة إذا كان مسجل دخول، أو عبر صفحة تسجيل الدخول
  Future<void> _navigateToFtth() async {
    final dual = DualAuthService.instance;

    // فحص إذا كان FTTH مسجل دخول بالفعل
    final hasSession = await dual.checkFtthSession();

    if (hasSession && dual.ftthToken != null && dual.ftthUsername != null && dual.ftthUsername!.isNotEmpty) {
      // ✅ FTTH مسجل دخول - انتقل مباشرة بدون صفحة تسجيل الدخول
      final ftthUsername = dual.ftthUsername!;
      final ftthIsAdmin = ftthUsername.toLowerCase().contains('admin') ||
          ftthUsername.toLowerCase().contains('مدير');

      // بناء الصلاحيات المجمعة
      final pm = PermissionManager.instance;
      Map<String, bool> combinedPermissions;
      if (pm.isLoaded) {
        combinedPermissions = pm.buildPageAccess();
      } else {
        combinedPermissions = widget.pageAccess;
      }

      // تحديد الصلاحيات النهائية
      final isFirstSystemAdmin =
          widget.permissions.toLowerCase().contains('مدير') ||
              widget.permissions.toLowerCase().contains('admin');
      final finalPermissions =
          (isFirstSystemAdmin || ftthIsAdmin) ? 'مدير مجمع' : 'مستخدم مجمع';

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ftth_home.HomePage(
            username: ftthUsername,
            authToken: dual.ftthToken!,
            permissions: finalPermissions,
            department: widget.department,
            center: widget.center,
            salary: widget.salary,
            pageAccess: combinedPermissions,
            firstSystemUsername: widget.username,
            firstSystemPermissions: widget.permissions,
            firstSystemDepartment: widget.department,
            firstSystemCenter: widget.center,
            firstSystemSalary: widget.salary,
            firstSystemPageAccess: widget.pageAccess,
          ),
        ),
      );
    } else {
      // ❌ FTTH غير مسجل دخول - فتح صفحة تسجيل الدخول العادية
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ftth_login.LoginPage(
            firstSystemUsername: widget.username,
            firstSystemPermissions: widget.permissions,
            firstSystemDepartment: widget.department,
            firstSystemCenter: widget.center,
            firstSystemSalary: widget.salary,
            firstSystemPageAccess: widget.pageAccess,
          ),
        ),
      );
    }
  }

  // ===== صف العدادات السريعة (تصميم FTTH) =====
  Widget _buildCountersRow() {
    final r = context.responsive;
    return Row(
      children: [
        Expanded(
          child: _buildFtthCounterCard(
            label: 'طلبات الوكلاء',
            value: _pendingAgentRequests,
            icon: Icons.person_add_alt_1_rounded,
            color: const Color(0xFFE74C3C),
            loading: _countersLoading,
          ),
        ),
        SizedBox(width: r.counterSpacing),
        Expanded(
          child: _buildFtthCounterCard(
            label: 'المهام المفتوحة',
            value: _openTasksCount,
            icon: Icons.assignment_late_rounded,
            color: const Color(0xFFF39C12),
            loading: _countersLoading,
          ),
        ),
        SizedBox(width: r.counterSpacing),
        Expanded(
          child: _buildFtthCounterCard(
            label: 'طلبات الموظفين',
            value: _pendingEmployeeRequests,
            icon: Icons.request_page_rounded,
            color: const Color(0xFF8E44AD),
            loading: _countersLoading,
          ),
        ),
      ],
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
                                          color: const Color(0xFF1A1A1A),
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
                  SizedBox(height: r.isMobile ? 4 : 8),
                  // أيقونة + تسمية
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: color, size: r.counterLabelSize + 1),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            color: const Color(0xFF1A1A1A),
                            fontSize: r.counterLabelSize,
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

  // شبكة عناصر القائمة - تخطيط شبكي فاخر
  Widget _buildMenuGrid() {
    final r = context.responsive;
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = r.gridColumns;
        final spacing = r.gridSpacing;
        final itemWidth =
            (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                crossAxisCount;

        final items = <Widget>[
          // 1) Agent
          _buildEnhancedMenuItem(
            title: 'صفحة الوكيل',
            subtitle: 'إدارة خدمات العملاء',
            icon: Icons.person_outline,
            gradient: [Colors.green[500]!, Colors.green[700]!],
            permissionKey: 'agent',
            badgeCount: _pendingAgentRequests,
            onTap: () => _navigateToFtth(),
          ),
          // 2) Tasks
          _buildEnhancedMenuItem(
            title: 'المهام',
            subtitle: 'إدارة المهام اليومية',
            icon: Icons.task_alt,
            gradient: [Colors.orange[500]!, Colors.orange[700]!],
            permissionKey: 'tasks',
            badgeCount: _openTasksCount,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => TaskListScreen(
                  username: widget.username,
                  permissions: widget.permissions,
                  department: widget.department,
                  center: widget.center,
                ),
              ),
            ),
          ),

          // 3) Zones
          _buildEnhancedMenuItem(
            title: 'الزونات',
            subtitle: 'إدارة المناطق الجغرافية',
            icon: Icons.map_outlined,
            gradient: [Colors.purple[500]!, Colors.purple[700]!],
            permissionKey: 'zones',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AriaPage(
                  username: widget.username,
                  permissions: widget.permissions,
                  department: widget.department,
                  center: widget.center,
                ),
              ),
            ),
          ),
          // 4) HR - الموارد البشرية
          _buildEnhancedMenuItem(
            title: 'HR',
            subtitle: 'الموارد البشرية والحضور والرواتب',
            icon: Icons.groups_rounded,
            gradient: [const Color(0xFF0D47A1), const Color(0xFF1565C0)],
            permissionKey: 'hr',
            badgeCount: _pendingEmployeeRequests,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => HrHubPage(
                  username: widget.username,
                  permissions: widget.permissions,
                  department: widget.department,
                  center: widget.center,
                  pageAccess: widget.pageAccess,
                  tenantId: widget.tenantId,
                  tenantCode: widget.tenantCode,
                ),
              ),
            ),
          ),
          // 5) AI Search
          _buildEnhancedMenuItem(
            title: 'البحث بالذكاء الاصطناعي',
            subtitle: 'البحث المتقدم والذكي',
            icon: Icons.psychology,
            gradient: [Colors.red[500]!, Colors.red[700]!],
            permissionKey: 'ai_search',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SearchUsersPage(),
              ),
            ),
          ),
          // 6) منصة الصدارة
          _buildEnhancedMenuItem(
            title: 'منصة الصدارة',
            subtitle: 'طلبات المواطن والوكيل',
            icon: Icons.hub_rounded,
            gradient: [const Color(0xFF667eea), const Color(0xFF764ba2)],
            permissionKey: 'sadara_portal',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const Scaffold(
                  body: SadaraPortalPage(),
                ),
              ),
            ),
          ),
          // 7) الحسابات
          _buildEnhancedMenuItem(
            title: 'الحسابات',
            subtitle: 'النظام المالي والمحاسبي',
            icon: Icons.account_balance_wallet,
            gradient: [Colors.amber[600]!, Colors.amber[900]!],
            permissionKey: 'accounting',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PermissionGate.page(
                  permission: 'accounting',
                  pageName: 'الحسابات',
                  child: AccountingDashboardPage(
                    companyId: widget.tenantId,
                  ),
                ),
              ),
            ),
          ),
          // 8) المتابعة والتقييم
          _buildEnhancedMenuItem(
            title: 'المتابعة',
            subtitle: 'متابعة وتقييم المهام',
            icon: Icons.fact_check_rounded,
            gradient: [Colors.indigo[500]!, Colors.indigo[800]!],
            permissionKey: 'follow_up',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FollowUpPage(
                  username: widget.username,
                  permissions: widget.permissions,
                  department: widget.department,
                  center: widget.center,
                ),
              ),
            ),
          ),
          // 9) داشبورد التدقيق
          _buildEnhancedMenuItem(
            title: 'داشبورد التدقيق',
            subtitle: 'إحصائيات وتحليلات شاملة',
            icon: Icons.dashboard_rounded,
            gradient: [const Color(0xFF1A237E), const Color(0xFF283593)],
            permissionKey: 'audit_dashboard',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => AuditDashboardPage(
                  username: widget.username,
                  permissions: widget.permissions,
                  department: widget.department,
                  center: widget.center,
                ),
              ),
            ),
          ),
          // 10) شاشتي - لوحة الموظف الشخصية
          _buildEnhancedMenuItem(
            title: 'شاشتي',
            subtitle: 'البصمة والمعاملات والراتب',
            icon: Icons.dashboard_rounded,
            gradient: [Colors.teal[500]!, Colors.teal[800]!],
            permissionKey: 'my_dashboard',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MyDashboardPage(
                  username: widget.username,
                  permissions: widget.permissions,
                  center: widget.center,
                ),
              ),
            ),
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: r.isMobile ? 8 : 12,
          children: items
              .map((item) => SizedBox(width: itemWidth, child: item))
              .toList(),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final r = context.responsive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue[600], size: r.iconSizeSmall),
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
                color: Colors.grey[700],
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
              Icon(Icons.logout, color: Colors.red[600]),
              const SizedBox(width: 10),
              const Text('تأكيد تسجيل الخروج'),
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
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
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
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
          backgroundColor: Colors.green,
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
              color: Colors.blue,
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
            style: const TextStyle(color: Colors.blue),
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
                      color: Colors.amber,
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
                      color: Colors.cyan,
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
        color: value ? Colors.green : Colors.red,
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
          color: Colors.blue[100],
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            Icon(Icons.person_pin, color: Colors.blue, size: r.iconSizeLarge),
            const SizedBox(width: 10),
            Text(
              'معلومات المستخدم',
              style: TextStyle(
                color: Colors.blue,
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
          color: Colors.grey[50],
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
            foregroundColor: Colors.red,
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
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.blue[700], size: r.iconSizeMedium),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey[600],
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
