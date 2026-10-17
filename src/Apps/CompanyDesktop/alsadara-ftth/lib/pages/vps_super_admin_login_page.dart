/// صفحة تسجيل دخول مدير النظام عبر VPS API
/// تستخدم VpsAuthService بدلاً من Firebase
library;

import 'dart:math';

import 'package:flutter/material.dart';
import '../services/vps_auth_service.dart';
import 'super_admin/super_admin_dashboard.dart';
import '../frontend/tokens/sd_colors.dart' show SdColors;

class VpsSuperAdminLoginPage extends StatefulWidget {
  const VpsSuperAdminLoginPage({super.key});

  @override
  State<VpsSuperAdminLoginPage> createState() => _VpsSuperAdminLoginPageState();
}

class _VpsSuperAdminLoginPageState extends State<VpsSuperAdminLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = VpsAuthService.instance;

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  /// التحقق من وجود جلسة سابقة
  Future<void> _checkExistingSession() async {
    setState(() => _isLoading = true);

    try {
      final restored = await _authService.restoreSession();
      if (restored && _authService.isSuperAdmin && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminDashboard()),
        );
      }
    } catch (e) {
      // تجاهل الأخطاء - استمر في عرض شاشة تسجيل الدخول
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال اسم المستخدم وكلمة المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.loginSuperAdmin(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (result.success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SuperAdminDashboard()),
        );
      } else {
        setState(() => _errorMessage = result.errorMessage);
      }
    } catch (e) {
      setState(() => _errorMessage = 'حدث خطأ');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              SdColors.primaryEdge,
              SdColors.primary,
              SdColors.primary,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: min(400, MediaQuery.of(context).size.width * 0.85),
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الأيقونة
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: SdColors.primaryTint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.admin_panel_settings,
                        size: 64,
                        color: SdColors.primaryEdge,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // العنوان
                    Text(
                      'مدير النظام',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: SdColors.primaryEdge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'لوحة التحكم الرئيسية',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 16,
                        color: SdColors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // شارة VPS API
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: SdColors.successTint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done,
                              size: 16, color: SdColors.success),
                          const SizedBox(width: 4),
                          Text(
                            'VPS API',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: SdColors.success,
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
                          color: SdColors.dangerTint,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SdColors.dangerTintEdge),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: SdColors.danger),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style:
                                    TextStyle(fontFamily: 'Cairo', color: SdColors.danger),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // اسم المستخدم
                    TextField(
                      controller: _usernameController,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'اسم المستخدم',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: SdColors.surfaceAlt,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // كلمة المرور
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
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
                        fillColor: SdColors.surfaceAlt,
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 24),

                    // زر الدخول
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SdColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
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
                            : Text(
                                'تسجيل الدخول',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // رابط العودة
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 20),
                      label: Text(
                        'العودة لتسجيل دخول الشركات',
                        style: TextStyle(fontFamily: 'Cairo', color: SdColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
