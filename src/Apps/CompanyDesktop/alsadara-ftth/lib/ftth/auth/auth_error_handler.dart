import 'package:flutter/material.dart';
import '../../pages/login/premium_login_page.dart';
import '../../services/dual_auth_service.dart';

/// خدمة مساعدة للتعامل مع أخطاء المصادقة في النظام الثاني
class AuthErrorHandler {
  // منع تنفيذ عمليات متزامنة لتسجيل الدخول الصامت
  static bool _isHandling401 = false;

  /// معالجة خطأ 401 - محاولة تسجيل دخول صامت أولاً، ثم صفحة تسجيل الدخول
  static Future<void> handle401Error(
    BuildContext context, {
    String? customMessage,
    String? firstSystemUsername,
    String? firstSystemDepartment,
    String? firstSystemCenter,
    String? firstSystemSalary,
  }) async {
    if (!context.mounted) return;
    if (_isHandling401) return; // منع التكرار
    _isHandling401 = true;

    try {
      // محاولة تسجيل دخول صامت أولاً
      print('🔄 [AuthErrorHandler] خطأ 401 — محاولة تسجيل دخول صامت...');
      final dual = DualAuthService.instance;
      final result = await dual.silentFtthLogin();

      if (result.success && dual.ftthToken != null) {
        print('✅ [AuthErrorHandler] نجح تسجيل الدخول الصامت — لا حاجة لشاشة تسجيل الدخول');
        _isHandling401 = false;
        return; // تم التجديد — لا حاجة للتوجيه لصفحة تسجيل الدخول
      }

      print('⚠️ [AuthErrorHandler] فشل تسجيل الدخول الصامت: ${result.message}');
    } catch (e) {
      print('❌ [AuthErrorHandler] خطأ في تسجيل الدخول الصامت');
    }

    _isHandling401 = false;

    // فشل التجديد الصامت — توجيه لصفحة تسجيل الدخول
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PremiumLoginPage()),
      (route) => false,
    );
  }

  /// فحص رمز الاستجابة ومعالجة أخطاء المصادقة
  static bool handleHttpResponse(BuildContext context, int statusCode,
      {String? responseBody}) {
    switch (statusCode) {
      case 401:
        handle401Error(context);
        return false;
      case 403:
        return false;
      case 200:
      case 201:
        return true;
      default:
        return true;
    }
  }
}
