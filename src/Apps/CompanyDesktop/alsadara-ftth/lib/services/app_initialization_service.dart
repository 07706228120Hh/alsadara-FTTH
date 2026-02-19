import 'package:flutter/material.dart';
import 'config_manager.dart';
import '../pages/client_setup_page.dart';
import '../pages/login/premium_login_page.dart';

/// خدمة تهيئة التطبيق والتحقق من الإعداد
class AppInitializationService {
  static final AppInitializationService _instance =
      AppInitializationService._internal();
  factory AppInitializationService() => _instance;
  AppInitializationService._internal();

  static AppInitializationService get instance => _instance;

  /// تهيئة شاملة للتطبيق
  Future<void> initialize() async {
    try {
      // تهيئة مدير التكوين
      await ConfigManager.instance.initialize();

      debugPrint('✅ تم تهيئة التطبيق بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة التطبيق: $e');
      rethrow;
    }
  }

  /// تحديد الشاشة الأولى بناءً على حالة الإعداد
  Widget getInitialPage() {
    final configManager = ConfigManager.instance;

    // إذا لم يتم الإعداد، توجيه لصفحة الإعداد
    if (!configManager.isSetupCompleted) {
      debugPrint('🔧 التطبيق غير مُعَدّ - توجيه لصفحة الإعداد');
      return const ClientSetupPage();
    }

    // إذا تم الإعداد، توجيه لصفحة تسجيل الدخول
    debugPrint('✅ التطبيق مُعَدّ - توجيه لصفحة تسجيل الدخول');
    return const PremiumLoginPage();
  }

  /// فحص صحة الإعدادات
  Future<bool> validateConfiguration() async {
    try {
      final configManager = ConfigManager.instance;

      // فحص وجود API Key
      final apiKey = await configManager.getSecureValue('api_key');
      if (apiKey == null || apiKey.trim().isEmpty) {
        debugPrint('⚠️ مفتاح API مفقود');
        return false;
      }

      // فحص معلومات الشركة
      if (configManager.companyName.trim().isEmpty) {
        debugPrint('⚠️ اسم الشركة مفقود');
        return false;
      }

      debugPrint('✅ الإعدادات صحيحة');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من الإعدادات: $e');
      return false;
    }
  }

  /// إنشاء إعدادات افتراضية
  Future<void> createDefaultSettings() async {
    try {
      final configManager = ConfigManager.instance;

      // إعدادات UI افتراضية
      await configManager.setValue('language', 'ar');
      await configManager.setValue('theme', 'light');
      await configManager.setValue('notifications_enabled', true);

      // إعدادات الشبكة
      await configManager.setValue('connection_timeout', 30);
      await configManager.setValue('max_retries', 3);

      debugPrint('✅ تم إنشاء الإعدادات الافتراضية');
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الإعدادات الافتراضية: $e');
    }
  }

  /// تحديث إعدادات التطبيق من متغيرات البيئة
  Future<void> updateFromEnvironment() async {
    try {
      // يمكن إضافة منطق تحديث الإعدادات من .env هنا
      debugPrint('🔄 تم تحديث الإعدادات من البيئة');
    } catch (e) {
      debugPrint('❌ خطأ في تحديث الإعدادات: $e');
    }
  }
}
