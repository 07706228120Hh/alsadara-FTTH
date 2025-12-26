import 'package:flutter/material.dart';
import '../auth/login_page.dart'; // إضافة استيراد صفحة تسجيل الدخول للنظام الثاني

/// خدمة مساعدة للتعامل مع أخطاء المصادقة في النظام الثاني
class AuthErrorHandler {
  /// معالجة خطأ 401 - توجيه إلى صفحة تسجيل الدخول للنظام الثاني مباشرة
  static void handle401Error(
    BuildContext context, {
    String? customMessage,
    String? firstSystemUsername,
    String? firstSystemPermissions,
    String? firstSystemDepartment,
    String? firstSystemCenter,
    String? firstSystemSalary,
    Map<String, bool>? firstSystemPageAccess,
  }) {
    if (!context.mounted) return;

    // التوجيه المباشر إلى صفحة تسجيل الدخول للنظام الثاني بدون رسائل تنبيه
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => LoginPage(
          // تمرير بيانات النظام الأول للاحتفاظ بها
          firstSystemUsername: firstSystemUsername,
          firstSystemPermissions: firstSystemPermissions,
          firstSystemDepartment: firstSystemDepartment,
          firstSystemCenter: firstSystemCenter,
          firstSystemSalary: firstSystemSalary,
          firstSystemPageAccess: firstSystemPageAccess,
        ),
      ),
      (route) => false, // إزالة جميع الصفحات السابقة
    );
  }

  /// فحص رمز الاستجابة ومعالجة أخطاء المصادقة
  static bool handleHttpResponse(BuildContext context, int statusCode,
      {String? responseBody}) {
    switch (statusCode) {
      case 401:
        handle401Error(context); // إزالة الرسالة المخصصة
        return false;
      case 403:
        // إزالة رسالة التنبيه للخطأ 403 أيضاً
        return false;
      case 200:
      case 201:
        return true;
      default:
        return true; // دع الصفحة تتعامل مع أخطاء أخرى
    }
  }
}
