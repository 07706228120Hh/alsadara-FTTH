/// صفحة تسجيل دخول مدير النظام
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'super_admin/super_admin_dashboard.dart';
import '../frontend/tokens/sd_colors.dart' show SdColors;

class SuperAdminLoginPage extends StatefulWidget {
  const SuperAdminLoginPage({super.key});

  @override
  State<SuperAdminLoginPage> createState() => _SuperAdminLoginPageState();
}

class _SuperAdminLoginPageState extends State<SuperAdminLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
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
      final querySnapshot = await FirebaseFirestore.instance
          .collection('super_admins')
          .where('username', isEqualTo: _usernameController.text.trim())
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        setState(() => _errorMessage = 'اسم المستخدم غير صحيح');
        return;
      }

      final adminData = querySnapshot.docs.first.data();
      final storedHash = adminData['passwordHash'] ?? '';
      final inputHash = _hashPassword(_passwordController.text);

      if (storedHash != inputHash) {
        setState(() => _errorMessage = 'كلمة المرور غير صحيحة');
        return;
      }

      if (adminData['isActive'] != true) {
        setState(() => _errorMessage = 'الحساب معطل');
        return;
      }

      // تحديث آخر تسجيل دخول
      await querySnapshot.docs.first.reference.update({
        'lastLogin': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const SuperAdminDashboard(),
          ),
        );
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
                      decoration: InputDecoration(
                        labelText: 'اسم المستخدم',
                        labelStyle: TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // كلمة المرور
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
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
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(
                                'دخول',
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
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
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
