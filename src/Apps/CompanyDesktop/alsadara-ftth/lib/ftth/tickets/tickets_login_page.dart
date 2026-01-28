/// اسم الصفحة: دخول نظام التذاكر
/// وصف الصفحة: صفحة تسجيل الدخول لنظام إدارة التذاكر والطلبات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import 'tktats_page.dart';

class TicketsLoginPage extends StatefulWidget {
  const TicketsLoginPage({super.key});

  @override
  State<TicketsLoginPage> createState() => _TicketsLoginPageState();
}

class _TicketsLoginPageState extends State<TicketsLoginPage>
    with TickerProviderStateMixin {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  String loginMessage = "";
  bool isLoading = false;
  bool rememberMe = false;
  bool showPassword = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

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
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animationController, curve: Curves.easeOutBack));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUsername = prefs.getString('tickets_username');
    final savedPassword = prefs.getString('tickets_password');
    final savedRememberMe = prefs.getBool('tickets_remember_me') ?? false;

    if (savedRememberMe && savedUsername != null && savedPassword != null) {
      setState(() {
        usernameController.text = savedUsername;
        passwordController.text = savedPassword;
        rememberMe = savedRememberMe;
      });
      // تسجيل دخول تلقائي إذا كانت البيانات محفوظة
      handleLogin();
    }
  }

  Future<void> saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString('tickets_username', usernameController.text);
      await prefs.setString('tickets_password', passwordController.text);
      await prefs.setBool('tickets_remember_me', true);
    } else {
      await prefs.remove('tickets_username');
      await prefs.remove('tickets_password');
      await prefs.setBool('tickets_remember_me', false);
    }
  }

  Future<void> handleLogin() async {
    if (usernameController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      setState(() {
        loginMessage = "يرجى إدخال اسم المستخدم وكلمة المرور";
      });
      return;
    }

    setState(() {
      isLoading = true;
      loginMessage = "";
    });

    try {
      final authService = AuthService.instance;
      final result = await authService.login(
        usernameController.text.trim(),
        passwordController.text.trim(),
      );

      if (result['success'] == true) {
        await saveCredentials();

        // إصلاح: الحصول على التوكن من data بدلاً من token مباشرة
        String? authToken;
        if (result['data'] != null && result['data']['access_token'] != null) {
          authToken = result['data']['access_token'];
        }

        if (mounted && authToken != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => TKTATsPage(
                authToken: authToken!, // إصلاح: التأكد من أن التوكن ليس null
              ),
            ),
          );
        } else {
          setState(() {
            loginMessage = "خطأ في الحصول على التوكن";
          });
        }
      } else {
        setState(() {
          loginMessage = result['message'] ?? "فشل في تسجيل الدخول";
        });
      }
    } catch (e) {
      setState(() {
        loginMessage = "خطأ في الاتصال: ${e.toString()}";
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
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
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1E88E5),
              Color(0xFF1976D2),
              Color(0xFF1565C0),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 24.0,
                  ),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Card(
                        elevation: 20,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Container(
                          width: constraints.maxWidth > 500
                              ? 400
                              : constraints.maxWidth - 32,
                          padding: EdgeInsets.all(
                            constraints.maxWidth > 400 ? 32.0 : 20.0,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // شعار التطبيق
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF1E88E5),
                                      Color(0xFF1976D2)
                                    ],
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 8,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.support_agent,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),

                              SizedBox(height: 20),

                              // بطاقة معلومات النظام
                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue[200]!,
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    // عنوان نظام التذاكر
                                    Text(
                                      'نظام التذاكر',
                                      style: TextStyle(
                                        fontSize: constraints.maxWidth > 400
                                            ? 28
                                            : 24,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1976D2),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),

                                    SizedBox(height: 6),

                                    // وصف النظام
                                    SizedBox(
                                      width: double.infinity,
                                      child: Text(
                                        'تسجيل دخول إلى نظام إدارة التذاكر',
                                        style: TextStyle(
                                          fontSize: constraints.maxWidth > 400
                                              ? 16
                                              : 14,
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: 24),

                              // حقل اسم المستخدم
                              SizedBox(
                                height: 56,
                                child: TextFormField(
                                  controller: usernameController,
                                  textDirection: TextDirection.ltr,
                                  decoration: InputDecoration(
                                    labelText: 'اسم المستخدم',
                                    prefixIcon: Icon(Icons.person,
                                        color: Color(0xFF1976D2)),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide:
                                          BorderSide(color: Color(0xFF1976D2)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Color(0xFF1976D2), width: 2),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                  onFieldSubmitted: (_) => handleLogin(),
                                ),
                              ),

                              SizedBox(height: 16),

                              // حقل كلمة المرور
                              SizedBox(
                                height: 56,
                                child: TextFormField(
                                  controller: passwordController,
                                  obscureText: !showPassword,
                                  textDirection: TextDirection.ltr,
                                  decoration: InputDecoration(
                                    labelText: 'كلمة المرور',
                                    prefixIcon: Icon(Icons.lock,
                                        color: Color(0xFF1976D2)),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        showPassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: Color(0xFF1976D2),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          showPassword = !showPassword;
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide:
                                          BorderSide(color: Color(0xFF1976D2)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Color(0xFF1976D2), width: 2),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                  onFieldSubmitted: (_) => handleLogin(),
                                ),
                              ),

                              SizedBox(height: 16),

                              // خيار "تذكرني"
                              SizedBox(
                                height: 40,
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: rememberMe,
                                      activeColor: Color(0xFF1976D2),
                                      onChanged: (value) {
                                        setState(() {
                                          rememberMe = value ?? false;
                                        });
                                      },
                                    ),
                                    Expanded(
                                      child: Text(
                                        'تذكر بيانات الدخول',
                                        style: TextStyle(
                                          color: Colors.grey[700],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: 20),

                              // زر تسجيل الدخول
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: isLoading ? null : handleLogin,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Color(0xFF1976D2),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 3,
                                  ),
                                  child: isLoading
                                      ? Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Text('جاري تسجيل الدخول...'),
                                          ],
                                        )
                                      : Text(
                                          'تسجيل الدخول',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),

                              // رسالة الحالة
                              if (loginMessage.isNotEmpty) ...[
                                SizedBox(height: 16),
                                AnimatedContainer(
                                  duration: Duration(milliseconds: 300),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: loginMessage.contains('خطأ') ||
                                            loginMessage.contains('فشل')
                                        ? Colors.red[50]
                                        : Colors.green[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: loginMessage.contains('خطأ') ||
                                              loginMessage.contains('فشل')
                                          ? Colors.red[200]!
                                          : Colors.green[200]!,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        loginMessage.contains('خطأ') ||
                                                loginMessage.contains('فشل')
                                            ? Icons.error_outline
                                            : Icons.check_circle_outline,
                                        color: loginMessage.contains('خطأ') ||
                                                loginMessage.contains('فشل')
                                            ? Colors.red[600]
                                            : Colors.green[600],
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          loginMessage,
                                          style: TextStyle(
                                            color: loginMessage
                                                        .contains('خطأ') ||
                                                    loginMessage.contains('فشل')
                                                ? Colors.red[700]
                                                : Colors.green[700],
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
