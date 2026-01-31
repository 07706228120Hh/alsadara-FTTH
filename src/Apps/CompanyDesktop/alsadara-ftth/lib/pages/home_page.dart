/// اسم الصفحة: الصفحة الرئيسية
/// وصف الصفحة: الصفحة الرئيسية للتطبيق تحتوي على الداشبورد والقوائم الرئيسية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:async'; // NEW
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart'; // Lottie animations
import 'package:alsadara/pages/track_users_map_page.dart';
import '../task/task_list_screen.dart';
import 'attendance_page.dart';
import 'search_users_page.dart';
import 'users_page.dart';
import 'users_page_firebase.dart';
import 'users_page_vps.dart';
import '../ftth/auth/login_page.dart' as ftth_login;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http; // NEW
import 'dart:convert'; // NEW
import 'dart:math' as math; // NEW: for rotations
import 'aria_page.dart';
import '../utils/breakpoints.dart';
import '../widgets/maintenance_messages_dialog.dart'; // إضافة حوار إعدادات الرسائل
import '../services/vps_auth_service.dart'; // ✅ خدمة VPS لتسجيل الخروج
import 'vps_tenant_login_page.dart'; // ✅ صفحة تسجيل الدخول
import '../ftth/whatsapp/whatsapp_bottom_window.dart'; // WhatsApp floating button
import 'super_admin/super_admin_dashboard.dart'; // لوحة تحكم Super Admin
import 'company_diagnostics_page.dart'; // صفحة تشخيص الشركة

class HomePage extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;
  final String salary;
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
    required this.pageAccess,
    this.tenantId,
    this.tenantCode,
    this.isSuperAdminMode = false,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
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
  };

  Map<String, bool> _userPermissions = {};
  // Animation controller for AppBar fiber effect
  late final AnimationController _fiberController;
  // Unified fiber optic color
  final Color _fiberColor = const Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _fiberController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
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

  Future<void> _loadUserPermissions() async {
    // استخدام الصلاحيات المُمررة من صفحة تسجيل الدخول (مفلترة حسب صلاحيات الشركة)
    final permissions = <String, bool>{};
    for (var key in _defaultPermissions.keys) {
      // الصلاحية من pageAccess (تحتوي على فلترة الشركة) أو القيمة الافتراضية
      permissions[key] = widget.pageAccess[key] ?? _defaultPermissions[key]!;
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
    // تسجيل الخروج من VPS API
    try {
      await VpsAuthService.instance.logout();
    } catch (e) {
      debugPrint('⚠️ خطأ في تسجيل الخروج: $e');
    }

    // الانتقال لصفحة تسجيل الدخول
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const VpsTenantLoginPage()),
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
  }) {
    final hasPermission = _userPermissions[permissionKey] ?? false;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasPermission ? onTap : null,
          borderRadius: BorderRadius.circular(32),
          splashColor: Colors.white.withValues(alpha: 0.2),
          highlightColor: Colors.white.withValues(alpha: 0.1),
          child: Stack(
            children: [
              // الطبقة الخلفية - الظل الخارجي
              Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: hasPermission
                      ? [
                          // ظل ملون أسفل الزر
                          BoxShadow(
                            color: gradient[1].withValues(alpha: 0.5),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                            spreadRadius: -10,
                          ),
                          // توهج خفيف حول الزر
                          BoxShadow(
                            color: gradient[0].withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                ),
              ),
              // الطبقة الرئيسية
              Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: hasPermission
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            gradient[0],
                            gradient[1],
                            Color.lerp(gradient[1], Colors.black, 0.2)!,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        )
                      : LinearGradient(
                          colors: [
                            Colors.grey[600]!.withValues(alpha: 0.6),
                            Colors.grey[800]!.withValues(alpha: 0.6),
                          ],
                        ),
                ),
                child: Stack(
                  children: [
                    // تأثير اللمعان العلوي (Glass effect)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(
                                  alpha: hasPermission ? 0.25 : 0.1),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // خط لامع على الحافة العلوية
                    Positioned(
                      top: 1,
                      left: 20,
                      right: 20,
                      child: Container(
                        height: 1,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.0),
                              Colors.white
                                  .withValues(alpha: hasPermission ? 0.5 : 0.2),
                              Colors.white.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // المحتوى الرئيسي
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      child: Row(
                        children: [
                          // أيقونة بتصميم 3D
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                center: const Alignment(-0.3, -0.3),
                                colors: [
                                  Colors.white.withValues(alpha: 0.3),
                                  Colors.white.withValues(alpha: 0.1),
                                  Colors.white.withValues(alpha: 0.05),
                                ],
                              ),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.5),
                                width: 2,
                              ),
                              boxShadow: [
                                // ظل داخلي
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                                // توهج خارجي
                                if (hasPermission)
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    blurRadius: 15,
                                    spreadRadius: -2,
                                  ),
                              ],
                            ),
                            child: Icon(
                              icon,
                              color: Colors.white,
                              size: 32,
                              shadows: const [
                                Shadow(
                                  color: Colors.black26,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          // النص
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                    shadows: [
                                      Shadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // سهم/قفل بتصميم فاخر
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                center: const Alignment(-0.3, -0.3),
                                colors: hasPermission
                                    ? [
                                        Colors.white.withValues(alpha: 0.35),
                                        Colors.white.withValues(alpha: 0.15),
                                        Colors.white.withValues(alpha: 0.05),
                                      ]
                                    : [
                                        Colors.red.withValues(alpha: 0.3),
                                        Colors.red.withValues(alpha: 0.1),
                                      ],
                              ),
                              border: Border.all(
                                color: hasPermission
                                    ? Colors.white.withValues(alpha: 0.5)
                                    : Colors.red.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: hasPermission
                                      ? Colors.white.withValues(alpha: 0.15)
                                      : Colors.red.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: Icon(
                              hasPermission
                                  ? Icons.arrow_forward_ios_rounded
                                  : Icons.lock_rounded,
                              color: hasPermission
                                  ? Colors.white
                                  : Colors.red[200],
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // حدود متوهجة
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: hasPermission
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.grey.withValues(alpha: 0.2),
                            width: 1.5,
                          ),
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
    );
  }

  @override
  void dispose() {
    _locationTimer?.cancel(); // NEW
    _fiberController.dispose();
    WhatsAppBottomWindow.hideBottomWindow(
        clearContent: true); // Hide WhatsApp floating button
    super.dispose();
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

  // Animated circular background for AppBar action icons (fiber-like sweep)
  Widget _buildAnimatedActionButton({
    required Icon icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color glowColor = Colors.cyanAccent,
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(horizontal: 4),
  }) {
    return Container(
      margin: margin,
      child: AnimatedBuilder(
        animation: _fiberController,
        builder: (context, _) {
          final angle = _fiberController.value * 2 * math.pi;
          return SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer animated glow ring
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        glowColor.withValues(alpha: 0.0),
                        glowColor.withValues(alpha: 0.36),
                        glowColor.withValues(alpha: 0.0),
                      ],
                      stops: const [0.08, 0.42, 0.92],
                      transform: GradientRotation(angle),
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: glowColor.withValues(alpha: 0.36),
                        blurRadius: 14,
                        spreadRadius: 1.0,
                      ),
                    ],
                  ),
                ),
                // Subtle inner fill to improve contrast
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                  ),
                ),
                // Tappable icon
                IconButton(
                  padding: const EdgeInsets.all(10),
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: icon,
                  tooltip: tooltip,
                  onPressed: onPressed,
                ),
              ],
            ),
          );
        },
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0D2137),
                Color(0xFF0A1628),
                Color(0xFF050D14),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // شعار متوهج
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                        blurRadius: 60,
                        spreadRadius: 20,
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
                // مؤشر تحميل فاخر
                SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFF00E5FF).withValues(alpha: 0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'جاري التحميل...',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        elevation: 0,
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
                Color(0xFF1A237E),
                Color(0xFF0D47A1),
                Color(0xFF01579B),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(24)),
              border: Border.all(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                width: 1,
              ),
            ),
          ),
        ),
        centerTitle: true,
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF00E5FF), Colors.white, Color(0xFF00E5FF)],
          ).createShader(bounds),
          child: const Text(
            '⚡ رمز الصدارة',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(
          color: Colors.white,
          size: 30.0, // تكبير حجم الأيقونات قليلاً
        ),
        actions: [
          // زر العودة للوحة تحكم Super Admin
          if (widget.isSuperAdminMode)
            _buildAnimatedActionButton(
              icon: const Icon(
                Icons.admin_panel_settings,
                color: Colors.amber,
                size: 30.0,
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
              size: 30.0,
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
              icon: const Icon(
                Icons.location_searching,
                color: Colors.white,
                size: 30.0,
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
      drawer: _buildDrawer(),
      body: _buildBody(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue[900]!,
              Colors.blue[700]!,
              Colors.white,
            ],
            stops: const [0.0, 0.4, 1.0],
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Compact drawer header
            Container(
              height: 160,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.blue[900]!, Colors.blue[600]!],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Compact company logo
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(35),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: Image.asset(
                        'assets/splash_background.jpg',
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Compact company name
                  const Text(
                    'شركة رمز الصدارة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // Compact system name
                  Text(
                    'النظام الإداري',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                  ),

                  // Compact admin badge
                  if (_isAdminUser) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Text(
                        'مدير النظام',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Compact user info section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue[50]!, Colors.blue[100]!],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue[200]!,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person, color: Colors.blue[700], size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'معلومات المستخدم',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(Icons.badge, 'الاسم', widget.username),
                  _buildInfoRow(Icons.business, 'القسم', widget.department),
                  _buildInfoRow(Icons.location_city, 'المركز', widget.center),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Users Management Button (Admin Only)
            if (_isAdminUser) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context); // Close drawer first
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => widget.tenantId != null &&
                                  widget.tenantCode != null
                              ? UsersPageVPS(
                                  companyId: widget.tenantId!,
                                  companyName: widget.department,
                                  permissions: {'users': true},
                                )
                              : widget.tenantId != null
                                  ? UsersPageFirebase(
                                      tenantId: widget.tenantId!,
                                      permissions: widget.permissions,
                                      pageAccess: widget.pageAccess,
                                    )
                                  : UsersPage(permissions: widget.permissions),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue[500]!, Colors.blue[700]!],
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.people, color: Colors.white, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'إدارة المستخدمين',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.arrow_forward_ios,
                              color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Non-Admin Users Button
            if (!_isAdminUser) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(context); // Close drawer first
                      _showPermissionDenied();
                    },
                    borderRadius: BorderRadius.circular(15),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.grey[400]!, Colors.grey[600]!],
                        ),
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.people_outline,
                              color: Colors.white, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'المستخدمين (محظور)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.lock, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // زر تشخيص النظام
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context); // Close drawer first
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CompanyDiagnosticsPage(
                          tenantId: widget.tenantId,
                          tenantCode: widget.tenantCode,
                          pageAccess: widget.pageAccess,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange[500]!, Colors.orange[700]!],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bug_report, color: Colors.white, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'تشخيص النظام',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Spacer(),
                        Icon(Icons.arrow_forward_ios,
                            color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Logout button with enhanced styling
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context); // Close drawer first
                    _showLogoutConfirmation();
                  },
                  borderRadius: BorderRadius.circular(15),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red[400]!, Colors.red[600]!],
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.logout, color: Colors.white, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'تسجيل الخروج',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Spacer(),
                        Icon(Icons.arrow_forward_ios,
                            color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final width = MediaQuery.of(context).size.width;
    final isWide = AppBreakpoints.isTablet(width) ||
        AppBreakpoints.isDesktop(width) ||
        AppBreakpoints.isLargeDesktop(width);
    final maxContentWidth = AppBreakpoints.isLargeDesktop(width)
        ? 1200.0
        : AppBreakpoints.isDesktop(width)
            ? 1000.0
            : AppBreakpoints.isTablet(width)
                ? 800.0
                : double.infinity;

    return Stack(
      children: [
        // Dark gradient background for high contrast
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0A2342), // deep blue
                Color(0xFF00101A), // dark teal
                Color(0xFF000000), // black
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Full-screen fiber beams layer
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _fiberController,
              builder: (context, _) {
                final t = _fiberController.value;
                return Stack(
                  children: [
                    // Many beams RTL across whole screen (softer to make photons pop)
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.10,
                        phase: 0.00,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 7.5,
                        color: _fiberColor,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.09,
                        phase: 0.11,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 7.0,
                        color: _fiberColor,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.08,
                        phase: 0.22,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 6.5,
                        color: _fiberColor,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.07,
                        phase: 0.33,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 8.0,
                        color: _fiberColor,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.06,
                        phase: 0.44,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 6.5,
                        color: _fiberColor,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.05,
                        phase: 0.55,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 7.0,
                        color: _fiberColor,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.045,
                        phase: 0.66,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 7.5,
                        color: _fiberColor,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.04,
                        phase: 0.77,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 6.5,
                        color: _fiberColor,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.035,
                        phase: 0.88,
                        widthFactor: 1.80,
                        angleRad: -math.pi / 6,
                        thickness: 7.0,
                        color: _fiberColor,
                        rightToLeft: true),
                    // a couple of crisp beams for definition
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.18,
                        phase: 0.12,
                        widthFactor: 1.65,
                        angleRad: -math.pi / 6,
                        thickness: 4.0,
                        color: Colors.cyanAccent,
                        rightToLeft: true),
                    _buildFiberBeam(
                        progress: t,
                        opacity: 0.16,
                        phase: 0.64,
                        widthFactor: 1.65,
                        angleRad: -math.pi / 6,
                        thickness: 4.0,
                        color: Colors.lightBlueAccent,
                        rightToLeft: true),

                    // Light photons passing through the fiber paths
                    // A few lanes across the vertical axis, with varying speeds and phases
                    for (final lane in const [
                      -0.82,
                      -0.62,
                      -0.42,
                      -0.22,
                      -0.02,
                      0.18,
                      0.38,
                      0.58,
                      0.78
                    ]) ...[
                      _buildPhoton(
                          progress: t,
                          phase: 0.05 + lane.abs() * 0.12,
                          y: lane,
                          speed: 1.15,
                          size: 7.0,
                          length: 56,
                          color: _fiberColor.withValues(alpha: 1.0),
                          rightToLeft: true),
                      _buildPhoton(
                          progress: t,
                          phase: 0.33 + lane.abs() * 0.18,
                          y: lane + 0.03,
                          speed: 1.5,
                          size: 7.5,
                          length: 62,
                          color: Colors.cyanAccent,
                          rightToLeft: true),
                      _buildPhoton(
                          progress: t,
                          phase: 0.66 + lane.abs() * 0.21,
                          y: lane - 0.02,
                          speed: 1.8,
                          size: 6.5,
                          length: 52,
                          color: Colors.white,
                          rightToLeft: true),
                    ],
                    // A couple of counter-direction photons for depth
                    _buildPhoton(
                        progress: t,
                        phase: 0.18,
                        y: -0.35,
                        speed: 0.85,
                        size: 6.0,
                        length: 44,
                        color: Colors.white70,
                        rightToLeft: false,
                        angleRad: -math.pi / 6),
                    _buildPhoton(
                        progress: t,
                        phase: 0.62,
                        y: 0.41,
                        speed: 0.95,
                        size: 5.5,
                        length: 40,
                        color: Colors.lightBlueAccent,
                        rightToLeft: false,
                        angleRad: -math.pi / 6),
                  ],
                );
              },
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
                padding: const EdgeInsets.symmetric(horizontal: 170),
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    // بطاقة ترحيب فاخرة مع تأثير زجاجي
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.15),
                            Colors.white.withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF00E5FF).withValues(alpha: 0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 15,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          // صورة مستخدم متوهجة
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF1DE9B6)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF)
                                      .withValues(alpha: 0.4),
                                  blurRadius: 15,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(3),
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF0A1628),
                              ),
                              padding: const EdgeInsets.all(2),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(25),
                                child: Image.asset(
                                  'assets/splash_background.jpg',
                                  width: 46,
                                  height: 46,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // رسالة ترحيب فاخرة
                                ShaderMask(
                                  shaderCallback: (bounds) =>
                                      const LinearGradient(
                                    colors: [
                                      Color(0xFF00E5FF),
                                      Color(0xFF64FFDA)
                                    ],
                                  ).createShader(bounds),
                                  child: const Text(
                                    '✨ مرحبا بكم في شركة الصدارة',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'مرحباً ${widget.username}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),

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
                          // شخصية متحركة ترحيبية
                          SizedBox(
                            width: 70,
                            height: 70,
                            child: Lottie.asset(
                              'assets/animations/welcome_person.json',
                              repeat: true,
                              animate: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // زر معلومات متوهج
                          InkWell(
                            onTap: () => _showUserInfo(context),
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF00E5FF)
                                        .withValues(alpha: 0.3),
                                    const Color(0xFF00E5FF)
                                        .withValues(alpha: 0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: const Color(0xFF00E5FF)
                                      .withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.info_outline,
                                color: Color(0xFF00E5FF),
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ), // Enhanced menu section
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: isWide
                          ? _buildGridMenu()
                          : Column(
                              children: [
                                // 1) Agent first
                                _buildEnhancedMenuItem(
                                  title: 'صفحة الوكيل',
                                  subtitle: 'إدارة خدمات العملاء',
                                  icon: Icons.person_outline,
                                  gradient: [
                                    Colors.green[500]!,
                                    Colors.green[700]!
                                  ],
                                  permissionKey: 'agent',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          ftth_login.LoginPage(
                                        firstSystemUsername: widget.username,
                                        firstSystemPermissions:
                                            widget.permissions,
                                        firstSystemDepartment:
                                            widget.department,
                                        firstSystemCenter: widget.center,
                                        firstSystemSalary: widget.salary,
                                        firstSystemPageAccess:
                                            widget.pageAccess,
                                      ),
                                    ),
                                  ),
                                ),
                                // 2) Tasks
                                _buildEnhancedMenuItem(
                                  title: 'المهام',
                                  subtitle: 'إدارة المهام اليومية',
                                  icon: Icons.task_alt,
                                  gradient: [
                                    Colors.orange[500]!,
                                    Colors.orange[700]!
                                  ],
                                  permissionKey: 'tasks',
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
                                  gradient: [
                                    Colors.purple[500]!,
                                    Colors.purple[700]!,
                                  ],
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
                                // 4) Attendance
                                _buildEnhancedMenuItem(
                                  title: 'البصمة',
                                  subtitle: 'تسجيل الحضور والانصراف',
                                  icon: Icons.fingerprint,
                                  gradient: [
                                    Colors.blue[600]!,
                                    Colors.blue[800]!
                                  ],
                                  permissionKey: 'attendance',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AttendancePage(
                                        username: widget.username,
                                        center: widget.center,
                                        permissions: widget.permissions,
                                      ),
                                    ),
                                  ),
                                ),
                                // 5) AI Search
                                _buildEnhancedMenuItem(
                                  title: 'البحث بالذكاء الاصطناعي',
                                  subtitle: 'البحث المتقدم والذكي',
                                  icon: Icons.psychology,
                                  gradient: [
                                    Colors.red[500]!,
                                    Colors.red[700]!
                                  ],
                                  permissionKey: 'ai_search',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const SearchUsersPage(),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
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

  // شبكة عناصر القائمة للشاشات الواسعة
  Widget _buildGridMenu() {
    final cards = <Widget>[
      // 1) Agent first
      _buildEnhancedMenuItem(
        title: 'صفحة الوكيل',
        subtitle: 'إدارة خدمات العملاء',
        icon: Icons.person_outline,
        gradient: [Colors.green[500]!, Colors.green[700]!],
        permissionKey: 'agent',
        onTap: () => Navigator.push(
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
        ),
      ),
      // 2) Tasks
      _buildEnhancedMenuItem(
        title: 'المهام',
        subtitle: 'إدارة المهام اليومية',
        icon: Icons.task_alt,
        gradient: [Colors.orange[500]!, Colors.orange[700]!],
        permissionKey: 'tasks',
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
      // 4) Attendance
      _buildEnhancedMenuItem(
        title: 'البصمة',
        subtitle: 'تسجيل الحضور والانصراف',
        icon: Icons.fingerprint,
        gradient: [Colors.blue[600]!, Colors.blue[800]!],
        permissionKey: 'attendance',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AttendancePage(
              username: widget.username,
              center: widget.center,
              permissions: widget.permissions,
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
    ];
    // واحد لكل صف على كل المقاسات
    return Column(children: cards);
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue[600], size: 14),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.blue[700],
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutConfirmation() {
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
          content: const Text(
            'هل أنت متأكد من رغبتك في تسجيل الخروج من التطبيق؟',
            style: TextStyle(fontSize: 16),
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
            child: const Text('حسنًا', style: TextStyle(fontSize: 16)),
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
    return Container(
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        children: [
          const Text(
            'إدارة صلاحيات المستخدمين',
            style: TextStyle(
              fontSize: 20,
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
                _buildPermissionSwitch(
                  title: 'صفحة البصمة',
                  value: permissions['attendance']!,
                  onChanged: (v) => onSave('attendance', v),
                ),
                _buildPermissionSwitch(
                  title: 'صفحة الوكيل',
                  value: permissions['agent']!,
                  onChanged: (v) => onSave('agent', v),
                ),
                _buildPermissionSwitch(
                  title: 'المهام',
                  value: permissions['tasks']!,
                  onChanged: (v) => onSave('tasks', v),
                ),
                _buildPermissionSwitch(
                  title: 'الزونات',
                  value: permissions['zones']!,
                  onChanged: (v) => onSave('zones', v),
                ),
                _buildPermissionSwitch(
                  title: 'البحث بالذكاء الاصطناعي',
                  value: permissions['ai_search']!,
                  onChanged: (v) => onSave('ai_search', v),
                ),
                _buildPermissionSwitch(
                  title: 'إدارة المستخدمين',
                  value: permissions['users'] ?? false,
                  onChanged: (v) => onSave('users', v),
                ),
                _buildPermissionSwitch(
                  title: 'إدارة الاشتراكات',
                  value: permissions['subscriptions'] ?? false,
                  onChanged: (v) => onSave('subscriptions', v),
                ),
                _buildPermissionSwitch(
                  title: 'إدارة الحسابات والمحاسبة',
                  value: permissions['accounts'] ?? false,
                  onChanged: (v) => onSave('accounts', v),
                ),
                _buildPermissionSwitch(
                  title: 'تصدير البيانات',
                  value: permissions['export'] ?? false,
                  onChanged: (v) => onSave('export', v),
                ),
                _buildPermissionSwitch(
                  title: 'إدارة الوكلاء',
                  value: permissions['agents'] ?? false,
                  onChanged: (v) => onSave('agents', v),
                ),
                _buildPermissionSwitch(
                  title: 'إرسال بيانات Google Sheets',
                  value: permissions['google_sheets'] ?? false,
                  onChanged: (v) => onSave('google_sheets', v),
                ),
                _buildPermissionSwitch(
                  title: 'إرسال رسائل WhatsApp',
                  value: permissions['whatsapp'] ?? false,
                  onChanged: (v) => onSave('whatsapp', v),
                ),
                _buildPermissionSwitch(
                  title: 'مشاهدة رصيد المحفظة',
                  value: permissions['wallet_balance'] ?? false,
                  onChanged: (v) => onSave('wallet_balance', v),
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
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue[100],
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Row(
          children: [
            Icon(Icons.person_pin, color: Colors.blue, size: 30),
            SizedBox(width: 10),
            Text(
              'معلومات المستخدم',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
      ),
      content: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoTile(Icons.person, 'ا��م المستخدم', username),
            const Divider(height: 20),
            _infoTile(Icons.admin_panel_settings, 'الصلاحيات', permissions),
            const Divider(height: 20),
            _infoTile(Icons.business, 'القسم', department),
            const Divider(height: 20),
            _infoTile(Icons.location_on, 'المركز', center),
            const Divider(height: 20),
            _infoTile(Icons.attach_money, 'الراتب', salary),
            if (isAdmin) ...[
              const Divider(height: 20),
              _infoTile(Icons.security, 'حالة المدير', 'مفعل'),
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

  Widget _infoTile(IconData icon, String title, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.blue[700], size: 24),
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
                  fontSize: 14,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
