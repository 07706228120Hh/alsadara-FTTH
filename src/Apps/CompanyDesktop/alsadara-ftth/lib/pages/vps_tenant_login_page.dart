/// صفحة تسجيل دخول الشركات عبر VPS API
/// تستخدم VpsAuthService بدلاً من Firebase
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/vps_auth_service.dart';
import 'home_page.dart';
import 'super_admin/super_admin_dashboard.dart';

class VpsTenantLoginPage extends StatefulWidget {
  const VpsTenantLoginPage({super.key});

  @override
  State<VpsTenantLoginPage> createState() => _VpsTenantLoginPageState();
}

class _VpsTenantLoginPageState extends State<VpsTenantLoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _companyCodeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = VpsAuthService.instance;

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
    // لا نفحص الجلسة تلقائياً - المستخدم يختار الدخول
    // _checkExistingSession();
  }

  /// التحقق من وجود جلسة سابقة - تم تعطيله للسماح بعرض صفحة تسجيل الدخول
  Future<void> _checkExistingSession() async {
    try {
      final restored = await _authService.restoreSession();
      if (restored && mounted) {
        _navigateAfterLogin();
      }
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCompanyCode = prefs.getString('vps_company_code');
      final savedUsername = prefs.getString('vps_username');
      final rememberMe = prefs.getBool('vps_remember_me') ?? false;

      if (rememberMe && savedCompanyCode != null && savedUsername != null) {
        setState(() {
          _companyCodeController.text = savedCompanyCode;
          _usernameController.text = savedUsername;
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
        await prefs.setString(
            'vps_company_code', _companyCodeController.text.trim());
        await prefs.setString('vps_username', _usernameController.text.trim());
        await prefs.setBool('vps_remember_me', true);
      } else {
        await prefs.remove('vps_company_code');
        await prefs.remove('vps_username');
        await prefs.setBool('vps_remember_me', false);
      }
    } catch (e) {
      debugPrint('خطأ في حفظ بيانات تسجيل الدخول: $e');
    }
  }

  @override
  void dispose() {
    _companyCodeController.dispose();
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

    try {
      final result = await _authService.login(
        companyCodeOrType: _companyCodeController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (result.success) {
        await _saveCredentials();
        _navigateAfterLogin();
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'حدث خطأ غير متوقع';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ في الاتصال: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateAfterLogin() {
    if (_authService.isSuperAdmin) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SuperAdminDashboard()),
      );
    } else if (_authService.currentUser != null &&
        _authService.currentCompany != null) {
      final user = _authService.currentUser!;
      final company = _authService.currentCompany!;

      // تحويل الصلاحيات
      final Map<String, bool> pageAccess = {};
      for (final permission in user.permissions) {
        pageAccess[permission] = true;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(
            username: user.username,
            permissions: user.isAdmin ? 'مدير' : user.role,
            department: company.name,
            center: company.code,
            salary: '0',
            pageAccess: pageAccess,
            tenantId: company.id,
            tenantCode: company.code,
          ),
        ),
      );
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
              const Color(0xFF1a237e),
              const Color(0xFF0d47a1),
              Colors.indigo[400]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // الشعار
                        AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.indigo[700]!,
                                    Colors.indigo[500]!,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.indigo.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.fiber_smart_record,
                                size: 64,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // العنوان
                        Text(
                          'منصة صدارة',
                          style: GoogleFonts.cairo(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'تسجيل الدخول',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // شارة VPS API
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_done,
                                  size: 16, color: Colors.green[700]),
                              const SizedBox(width: 4),
                              Text(
                                'VPS API',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // رسالة الخطأ
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red[700]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: GoogleFonts.cairo(
                                      color: Colors.red[700],
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // كود الشركة
                        TextFormField(
                          controller: _companyCodeController,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            labelText: 'كود الشركة',
                            labelStyle: GoogleFonts.cairo(),
                            hintText: 'أدخل كود الشركة (1 لمدير النظام)',
                            hintStyle: GoogleFonts.cairo(fontSize: 12),
                            prefixIcon: const Icon(Icons.business),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال كود الشركة';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // اسم المستخدم
                        TextFormField(
                          controller: _usernameController,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'اسم المستخدم',
                            labelStyle: GoogleFonts.cairo(),
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال اسم المستخدم';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // كلمة المرور
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            labelStyle: GoogleFonts.cairo(),
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(
                                    () => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال كلمة المرور';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 16),

                        // تذكرني
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() => _rememberMe = value ?? false);
                              },
                              activeColor: Colors.indigo[700],
                            ),
                            Text(
                              'تذكرني',
                              style: GoogleFonts.cairo(
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
                              backgroundColor: Colors.indigo[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 3,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.login),
                                      const SizedBox(width: 8),
                                      Text(
                                        'تسجيل الدخول',
                                        style: GoogleFonts.cairo(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // تسجيل الدخول كمدير نظام
                        TextButton.icon(
                          onPressed: () {
                            // ملء كود الشركة بـ 1 للتوجه لتسجيل دخول المدير
                            _companyCodeController.text = '1';
                          },
                          icon:
                              const Icon(Icons.admin_panel_settings, size: 18),
                          label: Text(
                            'تسجيل الدخول كمدير النظام',
                            style: GoogleFonts.cairo(
                              color: Colors.indigo[600],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
