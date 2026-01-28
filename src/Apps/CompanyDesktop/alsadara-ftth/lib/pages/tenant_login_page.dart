/// صفحة تسجيل دخول الشركات والمستخدمين
/// تتضمن: اسم الشركة، اسم المستخدم، كلمة المرور
/// مدير النظام يدخل برقم "1" في حقل اسم الشركة
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/custom_auth_service.dart';
import '../models/tenant_user.dart';
import 'home_page.dart';
import 'super_admin/super_admin_dashboard.dart';

class TenantLoginPage extends StatefulWidget {
  const TenantLoginPage({super.key});

  @override
  State<TenantLoginPage> createState() => _TenantLoginPageState();
}

class _TenantLoginPageState extends State<TenantLoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _tenantCodeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = CustomAuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _rememberMe = false;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTenantCode = prefs.getString('tenant_code');
      final savedUsername = prefs.getString('username');
      final savedPassword = prefs.getString('password');
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (rememberMe &&
          savedTenantCode != null &&
          savedUsername != null &&
          savedPassword != null) {
        setState(() {
          _tenantCodeController.text = savedTenantCode;
          _usernameController.text = savedUsername;
          _passwordController.text = savedPassword;
          _rememberMe = rememberMe;
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل بيانات تسجيل الدخول: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('tenant_code', _tenantCodeController.text.trim());
        await prefs.setString('username', _usernameController.text.trim());
        await prefs.setString('password', _passwordController.text);
        await prefs.setBool('remember_me', true);
      } else {
        await prefs.remove('tenant_code');
        await prefs.remove('username');
        await prefs.remove('password');
        await prefs.setBool('remember_me', false);
      }
    } catch (e) {
      debugPrint('خطأ في حفظ بيانات تسجيل الدخول: $e');
    }
  }

  @override
  void dispose() {
    _tenantCodeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.loginTenantUser(
      _tenantCodeController.text.trim(),
      _usernameController.text.trim(),
      _passwordController.text,
    );

    setState(() {
      _isLoading = false;
    });

    // التحقق من نوع المستخدم (مدير نظام أو مستخدم شركة)
    if (result.success) {
      await _saveCredentials();

      if (mounted) {
        // إذا كان مدير نظام
        if (result.userType == AuthUserType.superAdmin &&
            result.superAdmin != null) {
          print('✅ تسجيل دخول مدير النظام ناجح');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const SuperAdminDashboard(),
            ),
          );
          return;
        }

        // إذا كان مستخدم شركة
        if (result.tenantUser != null && result.tenant != null) {
          final user = result.tenantUser!;
          final tenant = result.tenant!;

          print('✅ تسجيل دخول ناجح:');
          print('  Username: ${user.username}');
          print('  Role: ${user.role.value}');

          // تحويل الصلاحيات إلى Map مع تطبيق صلاحيات الشركة
          final Map<String, bool> pageAccess = {};

          // صلاحيات النظام الأول (تُفلتر حسب صلاحيات الشركة)
          user.firstSystemPermissions.forEach((key, value) {
            // الصلاحية تكون true فقط إذا:
            // 1. المستخدم لديه الصلاحية
            // 2. الشركة مفعلة لهذه الميزة
            final isEnabledForTenant = tenant.isFirstSystemFeatureEnabled(key);
            pageAccess[key] = value && isEnabledForTenant;
          });

          // صلاحيات النظام الثاني (تُفلتر حسب صلاحيات الشركة)
          user.secondSystemPermissions.forEach((key, value) {
            final isEnabledForTenant = tenant.isSecondSystemFeatureEnabled(key);
            pageAccess[key] = value && isEnabledForTenant;
          });

          print(
              '  Tenant enabled features (First): ${tenant.enabledFirstSystemFeatures}');
          print(
              '  Tenant enabled features (Second): ${tenant.enabledSecondSystemFeatures}');
          print('  Final pageAccess: $pageAccess');

          // الانتقال إلى الصفحة الرئيسية
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => HomePage(
                username: user.username,
                permissions: user.role == UserRole.manager
                    ? 'مدير'
                    : user.role.arabicName,
                department: user.department ?? tenant.name,
                center: user.center ?? tenant.code,
                salary: user.salary ?? '0',
                pageAccess: pageAccess,
                tenantId: tenant.id,
                tenantCode: tenant.code,
              ),
            ),
          );
        }
      }
    } else {
      setState(() {
        _errorMessage = result.errorMessage ?? 'حدث خطأ غير متوقع';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              const Color(0xFF1E3A8A), // أزرق داكن
              const Color(0xFF3B82F6), // أزرق فاتح
              const Color(0xFF60A5FA), // أزرق سماوي
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // شعار التطبيق مع أنيميشن
                  _buildAnimatedLogo(),
                  const SizedBox(height: 32),

                  // بطاقة تسجيل الدخول
                  Card(
                    elevation: 20,
                    shadowColor: Colors.black.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    color: Colors.white, // 🎨 فرض اللون الأبيض
                    child: Container(
                      width: 450,
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // عنوان
                            Text(
                              'مرحباً بك في السدارة',
                              style: GoogleFonts.cairo(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E3A8A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'نظام إدارة شبكات FTTH',
                              style: GoogleFonts.cairo(
                                fontSize: 15,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // رسالة الخطأ
                            if (_errorMessage != null)
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFFFCA5A5)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Color(0xFFDC2626), size: 22),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: GoogleFonts.cairo(
                                          color: const Color(0xFFDC2626),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // حقل اسم الشركة
                            TextFormField(
                              controller: _tenantCodeController,
                              decoration: InputDecoration(
                                labelText: 'اسم الشركة',
                                hintText: 'أدخل رقم 1 لمدير النظام',
                                prefixIcon: const Icon(Icons.business,
                                    color: Color(0xFF3B82F6)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE5E7EB)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE5E7EB)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF3B82F6), width: 2),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                labelStyle:
                                    GoogleFonts.cairo(color: Colors.grey[700]),
                                hintStyle:
                                    GoogleFonts.cairo(color: Colors.grey[400]),
                              ),
                              style: GoogleFonts.cairo(color: Colors.grey[800]),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'يرجى إدخال اسم الشركة';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),

                            // حقل اسم المستخدم
                            TextFormField(
                              controller: _usernameController,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(
                                labelText: 'اسم المستخدم',
                                hintText: 'أدخل اسم المستخدم',
                                prefixIcon: const Icon(Icons.person,
                                    color: Color(0xFF3B82F6)),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE5E7EB)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE5E7EB)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF3B82F6), width: 2),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                labelStyle:
                                    GoogleFonts.cairo(color: Colors.grey[700]),
                                hintStyle:
                                    GoogleFonts.cairo(color: Colors.grey[400]),
                              ),
                              style: GoogleFonts.cairo(color: Colors.grey[800]),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'يرجى إدخال اسم المستخدم';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),

                            // حقل كلمة المرور
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(
                                labelText: 'كلمة المرور',
                                hintText: 'أدخل كلمة المرور',
                                prefixIcon: const Icon(Icons.lock,
                                    color: Color(0xFF3B82F6)),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.grey[600],
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE5E7EB)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE5E7EB)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF3B82F6), width: 2),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                                labelStyle:
                                    GoogleFonts.cairo(color: Colors.grey[700]),
                                hintStyle:
                                    GoogleFonts.cairo(color: Colors.grey[400]),
                              ),
                              style: GoogleFonts.cairo(color: Colors.grey[800]),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'يرجى إدخال كلمة المرور';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _login(),
                            ),
                            const SizedBox(height: 18),

                            // تذكرني
                            Row(
                              children: [
                                Checkbox(
                                  value: _rememberMe,
                                  activeColor: const Color(0xFF3B82F6),
                                  onChanged: (value) {
                                    setState(() {
                                      _rememberMe = value ?? false;
                                    });
                                  },
                                ),
                                Text(
                                  'تذكرني',
                                  style: GoogleFonts.cairo(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // زر تسجيل الدخول
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 6,
                                  shadowColor:
                                      const Color(0xFF3B82F6).withOpacity(0.4),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        'تسجيل الدخول',
                                        style: GoogleFonts.cairo(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ملاحظة لمدير النظام
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F9FF),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: const Color(0xFFBAE6FD)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lightbulb_outline,
                                      color: Color(0xFF0369A1), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'مدير النظام: اكتب "1" في اسم الشركة',
                                      style: GoogleFonts.cairo(
                                        fontSize: 13,
                                        color: const Color(0xFF0369A1),
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

                  const SizedBox(height: 24),

                  // معلومات التطبيق
                  Text(
                    'تطبيق السدارة لإدارة شبكات FTTH',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إصدار 1.2.8 - نظام Multi-Tenant',
                    style: GoogleFonts.cairo(
                      color: Colors.white70,
                      fontSize: 12,
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

  Widget _buildAnimatedLogo() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          children: [
            // الشعار
            Center(
              child: Image.asset(
                'assets/1.jpg',
                fit: BoxFit.cover,
                width: 140,
                height: 140,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.router,
                    size: 70,
                    color: Color(0xFF1E3A8A),
                  );
                },
              ),
            ),
            // دائرة متحركة
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: CircleProgressPainter(
                    progress: _animationController.value,
                  ),
                  size: const Size(140, 140),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// رسم دائرة تقدم متحركة
class CircleProgressPainter extends CustomPainter {
  final double progress;

  CircleProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3B82F6).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14 / 2, // بداية من الأعلى
      3.14 * 2 * progress,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(CircleProgressPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
