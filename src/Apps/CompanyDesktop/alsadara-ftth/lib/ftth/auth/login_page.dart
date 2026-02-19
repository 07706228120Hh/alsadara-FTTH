/// اسم الصفحة: دخول نظام FTTH
/// وصف الصفحة: صفحة تسجيل الدخول لنظام الألياف البصرية FTTH
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../pages/home_page.dart' as firstSystem;
import '../core/home_page.dart';
import '../../services/auth/session_manager.dart';
import '../../services/permission_checker.dart';

class LoginPage extends StatefulWidget {
  // إضافة معاملات لاستقبال بيانات المستخدم من النظام الأول
  final String? firstSystemUsername;
  final String? firstSystemPermissions;
  final String? firstSystemDepartment;
  final String? firstSystemCenter;
  final String? firstSystemSalary;
  final Map<String, bool>? firstSystemPageAccess;

  const LoginPage({
    super.key,
    this.firstSystemUsername,
    this.firstSystemPermissions,
    this.firstSystemDepartment,
    this.firstSystemCenter,
    this.firstSystemSalary,
    this.firstSystemPageAccess,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String loginMessage = "";
  bool isLoading = false;
  bool rememberMe = false;
  bool showPassword = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    loadSavedCredentials();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );
    _animationController.forward();

    // Animated fiber-optic background controller
    _bgController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  Future<void> loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      usernameController.text = prefs.getString('savedUsername') ?? '';
      passwordController.text = prefs.getString('savedPassword') ?? '';
      rememberMe = prefs.getBool('rememberMe') ?? false;
    });
  }

  Future<void> saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString('savedUsername', usernameController.text);
      await prefs.setString('savedPassword', passwordController.text);
      await prefs.setBool('rememberMe', true);
    } else {
      await prefs.remove('savedUsername');
      await prefs.remove('savedPassword');
      await prefs.setBool('rememberMe', false);
    }
  }

  Future<void> clearSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('savedUsername');
      await prefs.remove('savedPassword');
      await prefs.remove('rememberMe');

      setState(() {
        usernameController.clear();
        passwordController.clear();
        rememberMe = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ تم مسح البيانات المحفوظة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ في مسح البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> login() async {
    setState(() {
      isLoading = true;
      loginMessage = "";
    });

    try {
      final result = await AuthService.instance.login(
        usernameController.text.trim(),
        passwordController.text.trim(),
      );

      if (result['success']) {
        await saveCredentials();
        setState(() {
          loginMessage = result['message'];
        });

        if (!mounted) return;

        // تحديث جلسة FTTH الجديدة (تحميل الـ JWT داخل SessionManager)
        try {
          await SessionManager.instance.onLoginCompleted();
        } catch (e) {
          // ignore: avoid_print
          print('⚠️ تعذر تحديث الجلسة بعد تسجيل الدخول: $e');
        }

        // معلومات المستخدم من النظام الثاني (FTTH)
        final ftthUsername = usernameController.text.trim();
        final ftthIsAdmin = ftthUsername.toLowerCase().contains('admin') ||
            ftthUsername.toLowerCase().contains('مدير') ||
            ftthUsername == 'admin';

        // دمج الصلاحيات من النظامين
        final combinedPermissions = _combinePermissions(ftthIsAdmin);

        // تحديد الصلاحيات النهائية
        String finalPermissions;
        if (widget.firstSystemPermissions != null) {
          final isFirstSystemAdmin = widget.firstSystemPermissions!
                  .toLowerCase()
                  .contains('مدير') ||
              widget.firstSystemPermissions!.toLowerCase().contains('admin');
          finalPermissions =
              (isFirstSystemAdmin || ftthIsAdmin) ? 'مدير مجمع' : 'مستخدم مجمع';
        } else {
          finalPermissions = ftthIsAdmin ? 'مدير FTTH' : 'مستخدم FTTH';
        }

        final tokenData = result['data'];

        // تحميل صلاحيات V2 إذا لم تكن محملة
        if (!PermissionManager.instance.isLoaded) {
          await PermissionManager.instance.loadPermissions();
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(
              username: ftthUsername,
              authToken: tokenData['access_token'],
              permissions: finalPermissions,
              department: widget.firstSystemDepartment ?? 'FTTH',
              center: widget.firstSystemCenter ?? 'المركز الرئيسي',
              salary: widget.firstSystemSalary ?? '0',
              pageAccess: combinedPermissions,
              firstSystemUsername: widget.firstSystemUsername,
              firstSystemPermissions: widget.firstSystemPermissions,
              firstSystemDepartment: widget.firstSystemDepartment,
              firstSystemCenter: widget.firstSystemCenter,
              firstSystemSalary: widget.firstSystemSalary,
              firstSystemPageAccess: widget.firstSystemPageAccess,
            ),
          ),
        );
      } else {
        setState(() {
          loginMessage = result['message'];
        });
      }
    } catch (e) {
      setState(() {
        loginMessage = "حدث خطأ أثناء تسجيل الدخول: $e";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // V2: بناء صلاحيات الصفحات من PermissionManager
  Map<String, bool> _combinePermissions(bool ftthIsAdmin) {
    final pm = PermissionManager.instance;
    if (pm.isLoaded) {
      print('🔐 V2: استخدام صلاحيات PermissionManager');
      return pm.buildPageAccess();
    }

    // fallback: الصلاحيات الافتراضية لنظام FTTH
    final ftthPermissions = <String, bool>{
      'users': ftthIsAdmin,
      'subscriptions': true,
      'tasks': ftthIsAdmin,
      'zones': ftthIsAdmin,
      'accounts': ftthIsAdmin,
      'export': ftthIsAdmin,
      'agents': ftthIsAdmin,
    };

    return ftthPermissions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 20),
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => firstSystem.HomePage(
                          username: widget.firstSystemUsername ?? 'مستخدم',
                          permissions:
                              widget.firstSystemPermissions ?? 'default',
                          department: widget.firstSystemDepartment ?? 'عام',
                          center: widget.firstSystemCenter ?? 'الرئيسي',
                          salary: widget.firstSystemSalary ?? '0',
                          pageAccess: widget.firstSystemPageAccess ?? {},
                        ),
                      ),
                    );
                  },
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          // Base dark gradient to make additive glows show colors clearly
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0D1B2A), // dark blue
                    Color(0xFF0A1929),
                    Color(0xFF020817), // near black blue
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          // Animated fiber-optic background
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgController,
              builder: (context, _) => CustomPaint(
                painter: _FiberPainter(t: _bgController.value),
              ),
            ),
          ),
          // Subtle vignette overlay for readability
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 1.2,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.25),
                    ],
                    stops: const [0.6, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // شعار الشركة
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.3),
                                    Colors.white.withValues(alpha: 0.1),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(50),
                                child: Image.asset(
                                  'assets/splash_background.jpg',
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // كارد تسجيل الدخول مع فني الإنترنت
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final maxW =
                                    math.min(constraints.maxWidth - 32, 300.0);
                                return Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    child: Container(
                                      width: maxW,
                                      padding: const EdgeInsets.fromLTRB(
                                          18, 20, 18, 18),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(22),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.25),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.14),
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // أنيميشن تسجيل الدخول
                                          SizedBox(
                                            height: 100,
                                            width: 100,
                                            child: Lottie.network(
                                              'https://assets2.lottiefiles.com/packages/lf20_kkflmtur.json',
                                              fit: BoxFit.contain,
                                              repeat: true,
                                              animate: true,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return const Icon(
                                                  Icons.person,
                                                  size: 60,
                                                  color: Color(0xFF667eea),
                                                );
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 16),

                                          // حقل اسم المستخدم
                                          Container(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF667eea)
                                                      .withValues(alpha: 0.1),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 5),
                                                ),
                                              ],
                                            ),
                                            child: TextField(
                                              controller: usernameController,
                                              style:
                                                  const TextStyle(fontSize: 16),
                                              decoration: InputDecoration(
                                                labelText: 'اسم المستخدم',
                                                labelStyle: const TextStyle(
                                                  color: Color(0xFF718096),
                                                  fontSize: 15,
                                                ),
                                                prefixIcon: Container(
                                                  margin:
                                                      const EdgeInsets.all(12),
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    gradient:
                                                        const LinearGradient(
                                                      colors: [
                                                        Color(0xFF667eea),
                                                        Color(0xFF764ba2)
                                                      ],
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: const Icon(
                                                      Icons.person,
                                                      color: Colors.white,
                                                      size: 20),
                                                ),
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFF7FAFC),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                  borderSide: BorderSide.none,
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFF667eea),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),

                                          // حقل كلمة المرور
                                          Container(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF667eea)
                                                      .withValues(alpha: 0.1),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 5),
                                                ),
                                              ],
                                            ),
                                            child: TextField(
                                              controller: passwordController,
                                              style:
                                                  const TextStyle(fontSize: 16),
                                              obscureText: !showPassword,
                                              decoration: InputDecoration(
                                                labelText: 'كلمة المرور',
                                                labelStyle: const TextStyle(
                                                  color: Color(0xFF718096),
                                                  fontSize: 15,
                                                ),
                                                prefixIcon: Container(
                                                  margin:
                                                      const EdgeInsets.all(12),
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    gradient:
                                                        const LinearGradient(
                                                      colors: [
                                                        Color(0xFF667eea),
                                                        Color(0xFF764ba2)
                                                      ],
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10),
                                                  ),
                                                  child: const Icon(Icons.lock,
                                                      color: Colors.white,
                                                      size: 20),
                                                ),
                                                suffixIcon: IconButton(
                                                  icon: Icon(
                                                    showPassword
                                                        ? Icons.visibility
                                                        : Icons.visibility_off,
                                                    color:
                                                        const Color(0xFF718096),
                                                  ),
                                                  onPressed: () {
                                                    setState(() {
                                                      showPassword =
                                                          !showPassword;
                                                    });
                                                  },
                                                ),
                                                filled: true,
                                                fillColor:
                                                    const Color(0xFFF7FAFC),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                  borderSide: BorderSide.none,
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                  borderSide: const BorderSide(
                                                    color: Color(0xFF667eea),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),

                                          // خيار تذكرني
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Transform.scale(
                                                    scale: 1.2,
                                                    child: Checkbox(
                                                      value: rememberMe,
                                                      onChanged: (value) {
                                                        setState(() {
                                                          rememberMe =
                                                              value ?? false;
                                                        });
                                                      },
                                                      activeColor: const Color(
                                                          0xFF667eea),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                    ),
                                                  ),
                                                  const Text(
                                                    'تذكرني',
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      color: Color(0xFF4A5568),
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // زر مسح البيانات المحفوظة
                                              if (usernameController
                                                      .text.isNotEmpty ||
                                                  passwordController
                                                      .text.isNotEmpty)
                                                TextButton.icon(
                                                  onPressed:
                                                      clearSavedCredentials,
                                                  icon: const Icon(
                                                    Icons.clear_all_rounded,
                                                    size: 18,
                                                    color: Colors.red,
                                                  ),
                                                  label: const Text(
                                                    'مسح البيانات',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  style: TextButton.styleFrom(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                    minimumSize:
                                                        const Size(0, 32),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),

                                          // زر تسجيل الدخول
                                          isLoading
                                              ? Container(
                                                  height: 55,
                                                  decoration: BoxDecoration(
                                                    gradient:
                                                        const LinearGradient(
                                                      colors: [
                                                        Color(0xFF667eea),
                                                        Color(0xFF764ba2)
                                                      ],
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            15),
                                                  ),
                                                  child: const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                                  Color>(
                                                              Colors.white),
                                                    ),
                                                  ),
                                                )
                                              : Container(
                                                  width: double.infinity,
                                                  height: 50,
                                                  decoration: BoxDecoration(
                                                    gradient:
                                                        const LinearGradient(
                                                      colors: [
                                                        Color(0xFF667eea),
                                                        Color(0xFF764ba2)
                                                      ],
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            15),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: const Color(
                                                                0xFF667eea)
                                                            .withValues(
                                                                alpha: 0.4),
                                                        blurRadius: 15,
                                                        offset:
                                                            const Offset(0, 8),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ElevatedButton(
                                                    onPressed: login,
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      shadowColor:
                                                          Colors.transparent,
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(15),
                                                      ),
                                                    ),
                                                    child: const Text(
                                                      'تسجيل الدخول',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        letterSpacing: 0.5,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                          const SizedBox(height: 16),

                                          // رسالة تسجيل الدخول
                                          if (loginMessage.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.all(15),
                                              decoration: BoxDecoration(
                                                color: loginMessage
                                                        .contains("نجاح")
                                                    ? const Color(0xFF48BB78)
                                                        .withValues(alpha: 0.1)
                                                    : const Color(0xFFE53E3E)
                                                        .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: loginMessage
                                                          .contains("نجاح")
                                                      ? const Color(0xFF48BB78)
                                                      : const Color(0xFFE53E3E),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: loginMessage
                                                              .contains("نجاح")
                                                          ? const Color(
                                                              0xFF48BB78)
                                                          : const Color(
                                                              0xFFE53E3E),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                    ),
                                                    child: Icon(
                                                      loginMessage
                                                              .contains("نجاح")
                                                          ? Icons.check
                                                          : Icons.error_outline,
                                                      color: Colors.white,
                                                      size: 18,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Text(
                                                      loginMessage,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        color: loginMessage
                                                                .contains(
                                                                    "نجاح")
                                                            ? const Color(
                                                                0xFF22543D)
                                                            : const Color(
                                                                0xFF742A2A),
                                                        fontWeight:
                                                            FontWeight.w600,
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
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// رسام الخلفية المتحركة على شكل ألياف ضوئية
class _FiberPainter extends CustomPainter {
  final double t; // 0..1
  _FiberPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // إعدادات عامة
    final int lines = 12; // عدد أكبر من الأشرطة
    final double amplitude = size.height * 0.12;
    final double baseStroke = math.max(1.0, size.shortestSide * 0.0025);

    for (int i = 0; i < lines; i++) {
      final double p = (i / lines);
      final double phase = (t * 2 * math.pi) + (p * math.pi * 2);
      final double freq = 1.2 + 1.5 * (0.5 + 0.5 * math.sin(i));
      final double yBase = size.height * (0.15 + 0.7 * p);

      final Path path = Path();
      final int steps = 80;
      for (int s = 0; s <= steps; s++) {
        final double x = size.width * (s / steps);
        final double y = yBase +
            math.sin((x / size.width) * 2 * math.pi * freq + phase) *
                amplitude *
                (0.4 + 0.6 * (1 - p));
        if (s == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      // ألوان زرقاء ثابتة للأشرطة
      final Color cStart = const Color(0xFF42A5F5); // Blue 400
      final Color cEnd = const Color(0xFF1E88E5); // Blue 600

      final Paint glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStroke * (1.2 + 1.8 * (1 - p))
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8)
        ..shader = ui.Gradient.linear(
          Offset(0, yBase - amplitude),
          Offset(size.width, yBase + amplitude),
          [
            cStart.withValues(alpha: 0.12 + 0.22 * (1 - p)),
            cEnd.withValues(alpha: 0.12 + 0.22 * (1 - p)),
          ],
        );
      canvas.drawPath(path, glow);

      final Paint core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseStroke * (0.8 + 1.2 * (1 - p))
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.srcOver
        ..shader = ui.Gradient.linear(
          Offset(0, yBase),
          Offset(size.width, yBase),
          [
            cStart.withValues(alpha: 0.35 + 0.30 * (1 - p)),
            cEnd.withValues(alpha: 0.35 + 0.30 * (1 - p)),
          ],
        );
      canvas.drawPath(path, core);

      // إضافة عدة فوتونات تتحرك على الخط
      final int photons = 3;
      for (int j = 0; j < photons; j++) {
        final double offset = j / photons;
        final double speed = 1.0 + 0.5 * math.sin(i + j * 1.7);
        double pulsePos = (t * speed + 0.35 * p + offset) % 1.0;
        final double cx = size.width * pulsePos;
        final double cy = yBase +
            math.sin((cx / size.width) * 2 * math.pi * freq + phase) *
                amplitude *
                (0.4 + 0.6 * (1 - p));

        // لون الفوتون أخضر ساطع
        final Color pulseCore = const Color(0xFF00E676); // Green A400
        final double pulseR = baseStroke * (4.0 + 5.0 * (1 - p));

        // توهج الفوتون
        final Paint pulse = Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            pulseR,
            [
              pulseCore.withValues(alpha: 0.45),
              pulseCore.withValues(alpha: 0.0),
            ],
          );
        canvas.drawCircle(Offset(cx, cy), pulseR, pulse);

        // لمعة صغيرة في مركز الفوتون لحدة أعلى
        final Paint sparkle = Paint()
          ..blendMode = BlendMode.plus
          ..color = Colors.white.withValues(alpha: 0.65);
        canvas.drawCircle(Offset(cx, cy), pulseR * 0.25, sparkle);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FiberPainter oldDelegate) => oldDelegate.t != t;
}
