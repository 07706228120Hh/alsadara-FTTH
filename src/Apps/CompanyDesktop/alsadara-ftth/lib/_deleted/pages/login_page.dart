/// اسم الصفحة: صفحة تسجيل الدخول
/// وصف الصفحة: صفحة تسجيل الدخول للموظفين والمستخدمين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:math' as math;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'home_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import '../widgets/responsive_body.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/unified_auth_manager.dart';
import '../widgets/auth_status_monitor.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final FocusNode usernameFocusNode = FocusNode();
  final FocusNode phoneFocusNode = FocusNode();

  bool isLoading = false;
  String? errorMessage;
  bool rememberMe = false;
  bool _obscurePassword = true;
  bool _hasFieldFocus = false;

  // خلفية متحركة على نمط صفحة FTTH
  late AnimationController _bgController;

  // استخدام التخزين الآمن بدلاً من SharedPreferences
  static const _secureStorage = FlutterSecureStorage();

  // استخدام متغيرات البيئة الآمنة
  String get apiKey => dotenv.env['GOOGLE_SHEETS_API_KEY'] ?? '';
  String get spreadsheetId => dotenv.env['GOOGLE_SHEETS_SPREADSHEET_ID'] ?? '';
  String get range => dotenv.env['GOOGLE_SHEETS_RANGE'] ?? 'المستخدمين!A2:J';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    usernameFocusNode.addListener(_updateFocus);
    phoneFocusNode.addListener(_updateFocus);
    // محرك الخلفية المتحركة (مطابق لطريقة FTTH)
    _bgController = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    )..repeat();

    // تهيئة نظام المصادقة الموحد
    _initializeAuthSystem();
  }

  Future<void> _initializeAuthSystem() async {
    await UnifiedAuthManager.instance.initialize();
  }

  void _updateFocus() {
    final hasFocus = usernameFocusNode.hasFocus || phoneFocusNode.hasFocus;
    if (hasFocus != _hasFieldFocus) {
      setState(() => _hasFieldFocus = hasFocus);
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final savedUsername = await _secureStorage.read(key: 'username');
      final savedPhone = await _secureStorage.read(key: 'phone');
      final savedRememberMe = await _secureStorage.read(key: 'rememberMe');

      if (savedRememberMe == 'true') {
        setState(() {
          usernameController.text = savedUsername ?? '';
          phoneController.text = savedPhone ?? '';
          rememberMe = true;
        });
      }
    } catch (e) {
      print('خطأ في تحميل البيانات المحفوظة: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      if (rememberMe) {
        await _secureStorage.write(
            key: 'username', value: usernameController.text);
        await _secureStorage.write(key: 'phone', value: phoneController.text);
        await _secureStorage.write(key: 'rememberMe', value: 'true');
      } else {
        await _secureStorage.delete(key: 'username');
        await _secureStorage.delete(key: 'phone');
        await _secureStorage.write(key: 'rememberMe', value: 'false');
      }
    } catch (e) {
      print('خطأ في حفظ البيانات: $e');
    }
  }

  Future<void> _clearSavedCredentials() async {
    try {
      await _secureStorage.delete(key: 'username');
      await _secureStorage.delete(key: 'phone');
      await _secureStorage.delete(key: 'rememberMe');

      setState(() {
        usernameController.clear();
        phoneController.clear();
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

  Future<void> _callSupport() async {
    final uri = Uri(scheme: 'tel', path: '07727787789');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح الاتصال على هذا الجهاز')),
      );
    }
  }

  Future<void> login() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // محاولة تسجيل الدخول عبر النظام الموحد
      final result = await UnifiedAuthManager.instance.login(
        usernameController.text.trim(),
        phoneController.text.trim(),
        rememberMe: rememberMe,
      );

      if (result.isSuccess) {
        // حفظ بيانات تسجيل الدخول إذا طُلب ذلك
        await _saveCredentials();

        // الانتقال للصفحة الرئيسية مع بيانات أساسية
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(
              username: result.userSession!.username,
              permissions: 'USER', // صلاحية أساسية
              department: 'عام',
              salary: '',
              center: 'المركز الرئيسي',
              pageAccess: {
                'home': true,
                'home_page1': true,
                'home_page_tasks': true,
                'home_page2': true,
              },
            ),
          ),
        );
      } else {
        // إذا فشل النظام الموحد، جرب النظام التقليدي
        await _fallbackToTraditionalLogin();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الدخول: $e');
      // في حالة الخطأ، جرب النظام التقليدي
      await _fallbackToTraditionalLogin();
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _fallbackToTraditionalLogin() async {
    debugPrint('🔄 محاولة تسجيل الدخول التقليدي...');

    // التحقق من صحة مفاتيح API
    if (apiKey.isEmpty || spreadsheetId.isEmpty) {
      setState(() {
        errorMessage = 'خطأ في تكوين النظام. يرجى التواصل مع المطور.';
      });
      return;
    }

    final url =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range?key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['values'] != null) {
          final rows = data['values'] as List;

          String? userName;
          String? userPermissions;
          String? userDepartment;
          String? userSalary;
          String? userCenter;
          Map<String, bool> pageAccess = {};

          bool isUserValid = false;

          for (var row in rows) {
            if (row.length >= 2 &&
                row[0].toString().trim().toLowerCase() ==
                    usernameController.text.trim().toLowerCase() &&
                row[1].toString().trim() == phoneController.text.trim()) {
              isUserValid = true;
              userName = row.length > 0 ? row[0].toString().trim() : '';
              userPermissions = row.length > 2 ? row[2].toString().trim() : '';
              userDepartment = row.length > 3 ? row[3].toString().trim() : '';
              userSalary = row.length > 5 ? row[5].toString().trim() : '';
              userCenter = row.length > 4 ? row[4].toString().trim() : '';

              pageAccess = {
                'home': row.length > 6 && row[6] == 'TRUE',
                'home_page1': row.length > 7 && row[7] == 'TRUE',
                'home_page_tasks': row.length > 8 && row[8] == 'TRUE',
                'home_page2': row.length > 9 && row[9] == 'TRUE',
              };
              break;
            }
          }

          if (isUserValid) {
            // حفظ بيانات تسجيل الدخول
            await _saveCredentials();

            // الانتقال إلى الصفحة الرئيسية مع تمرير البيانات
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomePage(
                  username: userName ?? '',
                  permissions: userPermissions ?? '',
                  department: userDepartment ?? '',
                  salary: userSalary ?? '',
                  center: userCenter ?? '',
                  pageAccess: pageAccess, // إضافة صلاحيات الوصول
                ),
              ),
            );
          } else {
            setState(() {
              errorMessage = 'اسم المستخدم أو رقم الهاتف غير صحيح.';
            });
          }
        } else {
          setState(() {
            errorMessage = 'لا توجد بيانات مستخدمين في الجدول.';
          });
        }
      } else {
        setState(() {
          errorMessage = 'خطأ أثناء الاتصال: ${response.statusCode}';
        });
      }
    } on SocketException {
      setState(() {
        errorMessage = 'لا يوجد اتصال بالإنترنت.';
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ أثناء الاتصال: $e';
      });
    }
  }

  @override
  void dispose() {
    usernameController.dispose();
    phoneController.dispose();
    usernameFocusNode.removeListener(_updateFocus);
    phoneFocusNode.removeListener(_updateFocus);
    usernameFocusNode.dispose();
    phoneFocusNode.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthStatusMonitor(
      showNotifications: false, // إخفاء الإشعارات في صفحة تسجيل الدخول
      child: Scaffold(
        body: Stack(
          children: [
            // خلفية داكنة أساسية (مطابقة لـ FTTH)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0D1B2A),
                      Color(0xFF0A1929),
                      Color(0xFF020817),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            // رسام الألياف الضوئية المتحرك
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (context, _) => CustomPaint(
                  painter: _FiberPainter(t: _bgController.value),
                ),
              ),
            ),
            // تظليل خفيف لزيادة قابلية القراءة (Vignette)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.2),
                      radius: 1.2,
                      colors: [
                        Colors.transparent,
                        Colors.black54,
                      ],
                      stops: const [0.6, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // المحتوى الرئيسي
            Center(
              child: ResponsiveBody(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // اسم الشركة (العنوان العلوي)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.22),
                              Colors.white.withValues(alpha: 0.12),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.business,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'شركة الصدارة',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.tajawal(
                                color: const Color(0xFF00A1FF),
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                height: 1.1,
                                letterSpacing: 0.2,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black45,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // شعار الشركة
                      ClipRRect(
                        borderRadius: BorderRadius.circular(48),
                        child: Image.asset(
                          'assets/splash_background.jpg',
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // بطاقة تسجيل الدخول مع الأنيميشن
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final maxW = math.min(
                              MediaQuery.of(context).size.width - 120, 300.0);
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: BackdropFilter(
                              filter:
                                  ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                width: maxW,
                                padding:
                                    const EdgeInsets.fromLTRB(18, 20, 18, 18),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.14),
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
                                        borderRadius: BorderRadius.circular(15),
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
                                        focusNode: usernameFocusNode,
                                        style: const TextStyle(fontSize: 16),
                                        decoration: InputDecoration(
                                          labelText: 'اسم المستخدم',
                                          labelStyle: const TextStyle(
                                            color: Color(0xFF718096),
                                            fontSize: 15,
                                          ),
                                          prefixIcon: Container(
                                            margin: const EdgeInsets.all(12),
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF667eea),
                                                  Color(0xFF764ba2)
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.person,
                                                color: Colors.white, size: 20),
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFFF7FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            borderSide: BorderSide.none,
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF667eea),
                                                width: 2),
                                          ),
                                        ),
                                        textInputAction: TextInputAction.next,
                                        onSubmitted: (_) =>
                                            FocusScope.of(context)
                                                .requestFocus(phoneFocusNode),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // حقل كلمة المرور
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(15),
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
                                        controller: phoneController,
                                        focusNode: phoneFocusNode,
                                        style: const TextStyle(fontSize: 16),
                                        obscureText: _obscurePassword,
                                        decoration: InputDecoration(
                                          labelText: 'كلمة المرور',
                                          labelStyle: const TextStyle(
                                            color: Color(0xFF718096),
                                            fontSize: 15,
                                          ),
                                          prefixIcon: Container(
                                            margin: const EdgeInsets.all(12),
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF667eea),
                                                  Color(0xFF764ba2)
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.lock,
                                                color: Colors.white, size: 20),
                                          ),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                                _obscurePassword
                                                    ? Icons.visibility_off
                                                    : Icons.visibility,
                                                color: const Color(0xFF718096)),
                                            onPressed: () => setState(() =>
                                                _obscurePassword =
                                                    !_obscurePassword),
                                          ),
                                          filled: true,
                                          fillColor: const Color(0xFFF7FAFC),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            borderSide: BorderSide.none,
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(15),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF667eea),
                                                width: 2),
                                          ),
                                        ),
                                        keyboardType: TextInputType.text,
                                        textInputAction: TextInputAction.done,
                                        onSubmitted: (_) => login(),
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
                                                onChanged: (value) => setState(
                                                    () => rememberMe =
                                                        value ?? false),
                                                activeColor:
                                                    const Color(0xFF667eea),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4)),
                                              ),
                                            ),
                                            const Text(
                                              'تذكرني',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF4A5568),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // زر مسح البيانات المحفوظة
                                        if (usernameController
                                                .text.isNotEmpty ||
                                            phoneController.text.isNotEmpty)
                                          TextButton.icon(
                                            onPressed: _clearSavedCredentials,
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
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4),
                                              minimumSize: const Size(0, 32),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),

                                    // رسالة الخطأ
                                    if (errorMessage != null)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE53E3E)
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: const Color(0xFFE53E3E),
                                              width: 1),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFE53E3E),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Icon(
                                                  Icons.error_outline,
                                                  color: Colors.white,
                                                  size: 18),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                errorMessage!,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  color: Color(0xFF742A2A),
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    const SizedBox(height: 14),

                                    // زر تسجيل الدخول
                                    isLoading
                                        ? Container(
                                            height: 55,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF667eea),
                                                  Color(0xFF764ba2)
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                            ),
                                            child: const Center(
                                              child: CircularProgressIndicator(
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white),
                                              ),
                                            ),
                                          )
                                        : Container(
                                            width: double.infinity,
                                            height: 50,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF667eea),
                                                  Color(0xFF764ba2)
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(15),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF667eea)
                                                      .withValues(alpha: 0.4),
                                                  blurRadius: 15,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: ElevatedButton(
                                              onPressed: login,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            15)),
                                              ),
                                              child: const Text(
                                                'تسجيل الدخول',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 22),
                      // زر الدعم الفني (تصغير الحجم)
                      SizedBox(
                        width: math.min(
                            MediaQuery.of(context).size.width * 0.9, 360),
                        child: Material(
                          color: Colors.transparent,
                          elevation: 3,
                          borderRadius: BorderRadius.circular(12),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color.fromARGB(255, 25, 210, 108),
                                  Color.fromARGB(255, 51, 178, 58)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _callSupport,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.headset_mic_rounded,
                                        color: Colors.white, size: 22),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'الدعم الفني',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// رسام الخلفية المتحركة على غرار صفحة FTTH
class _FiberPainter extends CustomPainter {
  final double t; // 0..1
  _FiberPainter({required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    // إعدادات عامة (مطابقة لنسخة FTTH)
    final int lines = 12;
    final double amplitude = size.height * 0.12;
    final double baseStroke = math.max(1.0, size.shortestSide * 0.0025);

    for (int i = 0; i < lines; i++) {
      final double p = (i / lines);
      final double phase = (t * 2 * math.pi) + (p * math.pi * 2);
      final double freq = 1.2 + 1.5 * (0.5 + 0.5 * math.sin(i));
      final double yBase = size.height * (0.15 + 0.7 * p);

      final Path path = Path();
      const int steps = 80;
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

      // ألوان زرقاء للأشرطة
      const Color cStart = Color(0xFF42A5F5); // Blue 400
      const Color cEnd = Color(0xFF1E88E5); // Blue 600

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

      // فوتونات خضراء تتحرك
      const int photons = 3;
      for (int j = 0; j < photons; j++) {
        final double offset = j / photons;
        final double speed = 1.0 + 0.5 * math.sin(i + j * 1.7);
        final double pulsePos = (t * speed + 0.35 * p + offset) % 1.0;
        final double cx = size.width * pulsePos;
        final double cy = yBase +
            math.sin((cx / size.width) * 2 * math.pi * freq + phase) *
                amplitude *
                (0.4 + 0.6 * (1 - p));

        const Color pulseCore = Color(0xFF00E676); // Green A400
        final double pulseR = baseStroke * (4.0 + 5.0 * (1 - p));

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
