import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'template_password_storage.dart';

/// خدمة إدارة مسح البيانات عند إغلاق التطبيق نهائياً
class AppCloseHandler {
  static bool _isHandlingClose = false;
  static const _secureStorage = FlutterSecureStorage();

  /// مسح فقط بيانات تسجيل الدخول المحفوظة (اسم المستخدم وكلمة المرور) عند إغلاق التطبيق
  static Future<void> clearSavedLoginCredentials() async {
    if (_isHandlingClose) {
      debugPrint('⚠️ عملية مسح بيانات تسجيل الدخول قيد التنفيذ بالفعل');
      return; // منع التنفيذ المتكرر
    }
    _isHandlingClose = true;

    try {
      debugPrint(
          '🧹 بدء مسح بيانات تسجيل الدخول المحفوظة فقط عند إغلاق التطبيق...');

      final prefs = await SharedPreferences.getInstance();

      // مسح بيانات تسجيل الدخول المحفوظة للنظام الأول
      await _clearSavedCredentialsSystem1(prefs);

      // مسح بيانات تسجيل الدخول المحفوظة للنظام الثاني
      await _clearSavedCredentialsSystem2(prefs);

      // مسح بيانات الصفحة الرئيسية من FlutterSecureStorage
      await _clearSecureStorageCredentials();

      // مسح بيانات صفحة التذاكر من SharedPreferences
      await _clearTicketsCredentials(prefs);

      // إجبار حفظ التغييرات
      await prefs.reload();

      debugPrint('✅ تم مسح بيانات تسجيل الدخول المحفوظة بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات تسجيل الدخول المحفوظة: $e');
    } finally {
      _isHandlingClose = false;
    }
  }

  /// مسح بيانات تسجيل الدخول المحفوظة للنظام الأول (FTTH) فقط
  static Future<void> _clearSavedCredentialsSystem1(
      SharedPreferences prefs) async {
    try {
      debugPrint('🧹 مسح بيانات تسجيل الدخول المحفوظة لنظام FTTH...');

      // مسح بيانات تسجيل الدخول المحفوظة بالمفاتيح الصحيحة لـ FTTH
      await prefs.remove('savedUsername'); // المفتاح الصحيح لـ FTTH
      await prefs.remove('savedPassword'); // المفتاح الصحيح لـ FTTH
      await prefs.remove('rememberMe'); // المفتاح الصحيح لـ FTTH

      debugPrint('✅ تم مسح بيانات تسجيل الدخول المحفوظة لنظام FTTH');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات تسجيل الدخول المحفوظة لنظام FTTH: $e');
    }
  }

  /// مسح بيانات تسجيل الدخول المحفوظة للنظام الثاني (النظام الرئيسي) فقط
  static Future<void> _clearSavedCredentialsSystem2(
      SharedPreferences prefs) async {
    try {
      debugPrint('🧹 مسح بيانات تسجيل الدخول المحفوظة للنظام الرئيسي...');

      // لا نحتاج لمسح FlutterSecureStorage هنا لأنه يتم مسحها في _clearSecureStorageCredentials()
      // مسح أي بيانات أخرى للنظام الثاني إن وُجدت
      await prefs.remove('agents_saved_username');
      await prefs.remove('agents_saved_password');
      await prefs.remove('agents_remember_credentials');

      debugPrint('✅ تم مسح بيانات تسجيل الدخول المحفوظة للنظام الثاني');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات تسجيل الدخول المحفوظة للنظام الثاني: $e');
    }
  }

  /// مسح جميع بيانات تسجيل الدخول المحفوظة عند إغلاق التطبيق (دالة قديمة - للتوافق)
  static Future<void> clearAllLoginData() async {
    if (_isHandlingClose) {
      debugPrint('⚠️ عملية مسح البيانات قيد التنفيذ بالفعل');
      return; // منع التنفيذ المتكرر
    }
    _isHandlingClose = true;

    try {
      debugPrint('🧹 بدء مسح بيانات تسجيل الدخول عند إغلاق التطبيق...');

      final prefs = await SharedPreferences.getInstance();

      // مسح بيانات النظام الأول (AuthService)
      await _clearAuthServiceData(prefs);

      // مسح بيانات النظام الثاني (AgentsAuthService)
      await _clearAgentsAuthServiceData(prefs);

      // مسح بيانات إضافية
      await _clearAdditionalData(prefs);

      // مسح البيانات المؤقتة وذاكرة التخزين المؤقت
      await _clearTemporaryData(prefs);

      // إجبار حفظ التغييرات
      await prefs.reload();

      debugPrint('✅ تم مسح جميع بيانات تسجيل الدخول بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات تسجيل الدخول: $e');
      // حاول مسح البيانات الحرجة على الأقل
      try {
        final prefs = await SharedPreferences.getInstance();
        await _clearCriticalLoginData(prefs);
        debugPrint('✅ تم مسح البيانات الحرجة كحل احتياطي');
      } catch (e2) {
        debugPrint('❌❌ فشل في مسح البيانات الحرجة: $e2');
      }
    } finally {
      _isHandlingClose = false;
    }
  }

  /// مسح بيانات النظام الأول (AuthService)
  static Future<void> _clearAuthServiceData(SharedPreferences prefs) async {
    try {
      debugPrint('🧹 مسح بيانات النظام الأول (FTTH)...');

      // مسح التوكنات والجلسة
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('token_expiry');
      await prefs.remove('refresh_expiry');

      // مسح بيانات تسجيل الدخول المحفوظة
      await prefs.remove('saved_username');
      await prefs.remove('saved_password');
      await prefs.remove('remember_credentials');

      // مسح بيانات المستخدم
      await prefs.remove('user_data');
      await prefs.remove('last_login_time');

      debugPrint('✅ تم مسح بيانات النظام الأول');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات النظام الأول: $e');
    }
  }

  /// مسح بيانات النظام الثاني (AgentsAuthService)
  static Future<void> _clearAgentsAuthServiceData(
      SharedPreferences prefs) async {
    try {
      debugPrint('🧹 مسح بيانات النظام الثاني (Agents)...');

      // مسح توكنات النظام الثاني
      await prefs.remove('agents_access_token');
      await prefs.remove('agents_refresh_token');
      await prefs.remove('agents_guest_token');
      await prefs.remove('agents_user_info');
      await prefs.remove('agents_token_expiry');

      // مسح بيانات تسجيل الدخول المحفوظة للنظام الثاني (إذا وُجدت)
      await prefs.remove('agents_saved_username');
      await prefs.remove('agents_saved_password');
      await prefs.remove('agents_remember_credentials');

      debugPrint('✅ تم مسح بيانات النظام الثاني');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات النظام الثاني: $e');
    }
  }

  /// مسح البيانات الإضافية
  static Future<void> _clearAdditionalData(SharedPreferences prefs) async {
    try {
      debugPrint('🧹 مسح البيانات الإضافية...');

      // مسح صلاحيات المستخدم
      await prefs.remove('user_role');
      await prefs.remove('user_name');

      // مسح كلمة مرور تعديل القوالب
      await TemplatePasswordStorage.clearPassword();

      // مسح أي بيانات أخرى قد تكون مرتبطة بالجلسة
      await prefs.remove('last_dashboard_data');
      await prefs.remove('cached_user_roles');

      debugPrint('✅ تم مسح البيانات الإضافية');
    } catch (e) {
      debugPrint('❌ خطأ في مسح البيانات الإضافية: $e');
    }
  }

  /// مسح البيانات المؤقتة وذاكرة التخزين المؤقت
  static Future<void> _clearTemporaryData(SharedPreferences prefs) async {
    try {
      debugPrint('🧹 مسح البيانات المؤقتة...');

      // مسح البيانات المؤقتة
      await prefs.remove('temp_data');
      await prefs.remove('cache_data');
      await prefs.remove('session_cache');
      await prefs.remove('login_cache');

      // مسح بيانات الـ FCM
      await prefs.remove('fcm_token');
      await prefs.remove('notification_settings');

      debugPrint('✅ تم مسح البيانات المؤقتة');
    } catch (e) {
      debugPrint('❌ خطأ في مسح البيانات المؤقتة: $e');
    }
  }

  /// مسح البيانات الحرجة فقط (كحل احتياطي)
  static Future<void> _clearCriticalLoginData(SharedPreferences prefs) async {
    try {
      debugPrint('🚨 مسح البيانات الحرجة فقط...');

      // مسح التوكنات الأساسية فقط
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('agents_access_token');
      await prefs.remove('agents_refresh_token');

      // مسح كلمات المرور المحفوظة
      await prefs.remove('saved_password');
      await prefs.remove('agents_saved_password');

      debugPrint('✅ تم مسح البيانات الحرجة');
    } catch (e) {
      debugPrint('❌ خطأ في مسح البيانات الحرجة: $e');
    }
  }

  /// التحقق من أن التطبيق يتم إغلاقه فعلاً وليس مجرد تنقل
  static bool get isAppClosing {
    // في منصة Windows/Desktop، يمكن التحقق من حالة النافذة
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // عادة ما يتم استدعاء هذا عند إغلاق النافذة الرئيسية
      return true;
    }

    // في المنصات الأخرى (Android/iOS)، يمكن الاعتماد على AppLifecycleState.detached
    return false;
  }

  /// مسح البيانات بشكل انتقائي (للاختبار أو الحالات الخاصة)
  static Future<void> clearSpecificData({
    bool clearAuth = true,
    bool clearAgents = true,
    bool clearPermissions = true,
    bool clearTemplatePassword = true,
  }) async {
    try {
      debugPrint('🧹 بدء المسح الانتقائي للبيانات...');

      final prefs = await SharedPreferences.getInstance();

      if (clearAuth) {
        await _clearAuthServiceData(prefs);
      }

      if (clearAgents) {
        await _clearAgentsAuthServiceData(prefs);
      }

      if (clearPermissions) {
        await prefs.remove('user_role');
        await prefs.remove('user_name');
      }

      if (clearTemplatePassword) {
        await TemplatePasswordStorage.clearPassword();
      }

      debugPrint('✅ تم المسح الانتقائي بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في المسح الانتقائي: $e');
    }
  }

  /// مسح البيانات مع الحفاظ على إعدادات التطبيق
  static Future<void> clearLoginDataOnly() async {
    try {
      debugPrint('🧹 مسح بيانات تسجيل الدخول فقط...');

      final prefs = await SharedPreferences.getInstance();

      // مسح التوكنات والجلسات فقط
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('token_expiry');
      await prefs.remove('refresh_expiry');
      await prefs.remove('agents_access_token');
      await prefs.remove('agents_refresh_token');
      await prefs.remove('agents_guest_token');
      await prefs.remove('agents_user_info');
      await prefs.remove('agents_token_expiry');

      // مسح بيانات تسجيل الدخول المحفوظة
      await prefs.remove('saved_username');
      await prefs.remove('saved_password');
      await prefs.remove('remember_credentials');
      await prefs.remove('agents_saved_username');
      await prefs.remove('agents_saved_password');
      await prefs.remove('agents_remember_credentials');

      // الحفاظ على إعدادات التطبيق مثل:
      // - permissions_granted
      // - app_text_scale
      // - whatsapp_use_web
      // - whatsapp_auto_send
      // - window_*

      debugPrint('✅ تم مسح بيانات تسجيل الدخول فقط');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات تسجيل الدخول: $e');
    }
  }

  /// مسح بيانات الصفحة الرئيسية من FlutterSecureStorage
  static Future<void> _clearSecureStorageCredentials() async {
    try {
      debugPrint('🧹 مسح بيانات FlutterSecureStorage (الصفحة الرئيسية)...');

      // مسح بيانات الصفحة الرئيسية login_page.dart
      await _secureStorage.delete(key: 'username');
      await _secureStorage.delete(key: 'phone');
      await _secureStorage.delete(key: 'rememberMe');

      debugPrint('✅ تم مسح بيانات FlutterSecureStorage');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات FlutterSecureStorage: $e');
    }
  }

  /// مسح بيانات صفحة التذاكر من SharedPreferences
  static Future<void> _clearTicketsCredentials(SharedPreferences prefs) async {
    try {
      debugPrint('🧹 مسح بيانات صفحة التذاكر...');

      // مسح بيانات صفحة التذاكر tickets_login_page.dart
      await prefs.remove('tickets_username');
      await prefs.remove('tickets_password');
      await prefs.remove('tickets_remember_me');

      debugPrint('✅ تم مسح بيانات صفحة التذاكر');
    } catch (e) {
      debugPrint('❌ خطأ في مسح بيانات صفحة التذاكر: $e');
    }
  }
}
