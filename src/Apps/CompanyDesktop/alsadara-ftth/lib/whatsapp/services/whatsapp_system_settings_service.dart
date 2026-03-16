import 'package:shared_preferences/shared_preferences.dart';

/// أنظمة الواتساب المتاحة
enum WhatsAppSystem {
  app, // التطبيق العادي
  web, // واتساب ويب (WebView)
  server, // واتساب سيرفر
  api, // WhatsApp API (Meta)
}

/// نوع العملية
enum WhatsAppOperationType {
  renewal, // التجديد (يدوي/تلقائي)
  bulk, // الإرسال الجماعي (تنبيهات/منتهي/عروض)
}

/// خدمة إعدادات نظام الواتساب
class WhatsAppSystemSettingsService {
  // مفاتيح SharedPreferences
  static const String _keyRenewalSystem = 'whatsapp_renewal_system';
  static const String _keyBulkSystem = 'whatsapp_bulk_system';

  // ============ الثوابت ============
  static const Map<WhatsAppSystem, String> systemNames = {
    WhatsAppSystem.app: 'التطبيق العادي',
    WhatsAppSystem.web: 'واتساب ويب',
    WhatsAppSystem.server: 'واتساب سيرفر',
    WhatsAppSystem.api: 'WhatsApp API',
  };

  static const Map<WhatsAppSystem, String> systemIcons = {
    WhatsAppSystem.app: '📱',
    WhatsAppSystem.web: '🌐',
    WhatsAppSystem.server: '🖥️',
    WhatsAppSystem.api: '☁️',
  };

  static const Map<WhatsAppSystem, String> systemDescriptions = {
    WhatsAppSystem.app: 'فتح تطبيق واتساب ديسكتوب',
    WhatsAppSystem.web: 'واتساب ويب داخل التطبيق (إرسال تلقائي)',
    WhatsAppSystem.server: 'إرسال مباشر عبر السيرفر',
    WhatsAppSystem.api: 'إرسال عبر API الرسمي من Meta',
  };

  // ============ تحويلات ============
  static String _systemToString(WhatsAppSystem system) {
    switch (system) {
      case WhatsAppSystem.app:
        return 'app';
      case WhatsAppSystem.web:
        return 'web';
      case WhatsAppSystem.server:
        return 'server';
      case WhatsAppSystem.api:
        return 'api';
    }
  }

  static WhatsAppSystem _stringToSystem(String str) {
    switch (str) {
      case 'app':
        return WhatsAppSystem.app;
      case 'web':
        return WhatsAppSystem.web;
      case 'server':
        return WhatsAppSystem.server;
      case 'api':
        return WhatsAppSystem.api;
      default:
        return WhatsAppSystem.app;
    }
  }

  // ============ حفظ إعدادات النظام ============
  static Future<bool> saveSystemSettings({
    required WhatsAppSystem renewalSystem,
    required WhatsAppSystem bulkSystem,
    String? tenantId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyRenewalSystem, _systemToString(renewalSystem));
      await prefs.setString(_keyBulkSystem, _systemToString(bulkSystem));
      return true;
    } catch (e) {
      return false;
    }
  }

  // ============ تحميل إعدادات النظام ============
  static Future<Map<String, WhatsAppSystem>> getSystemSettings({
    String? tenantId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'renewal':
            _stringToSystem(prefs.getString(_keyRenewalSystem) ?? 'app'),
        'bulk': _stringToSystem(prefs.getString(_keyBulkSystem) ?? 'server'),
      };
    } catch (e) {
      return _defaultSettings;
    }
  }

  // ============ الحصول على نظام عملية معينة ============
  static Future<WhatsAppSystem> getSystemForOperation(
    WhatsAppOperationType operation, {
    String? tenantId,
  }) async {
    final settings = await getSystemSettings(tenantId: tenantId);
    switch (operation) {
      case WhatsAppOperationType.renewal:
        return settings['renewal']!;
      case WhatsAppOperationType.bulk:
        return settings['bulk']!;
    }
  }

  // ============ الإعدادات الافتراضية ============
  static Map<String, WhatsAppSystem> get _defaultSettings => {
        'renewal': WhatsAppSystem.app,
        'bulk': WhatsAppSystem.server,
      };

  // ============ التحقق من توفر النظام ============
  /// يتحقق من أن النظام مُعدٌّ (server URL محفوظ، API token محفوظ)
  static Future<bool> isSystemAvailable(
    WhatsAppSystem system, {
    String? tenantId,
  }) async {
    switch (system) {
      case WhatsAppSystem.app:
        return true; // دائماً متاح

      case WhatsAppSystem.web:
        return true; // واتساب ويب دائماً متاح

      case WhatsAppSystem.server:
        try {
          final prefs = await SharedPreferences.getInstance();
          final url = prefs.getString('whatsapp_server_url') ?? '';
          return url.isNotEmpty;
        } catch (_) {
          return false;
        }

      case WhatsAppSystem.api:
        try {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('whatsapp_api_token') ?? '';
          return token.isNotEmpty;
        } catch (_) {
          return false;
        }
    }
  }

  // ============ الحصول على الأنظمة المتاحة لنوع العملية ============
  static List<WhatsAppSystem> getAvailableSystemsForOperation(
    WhatsAppOperationType operation,
  ) {
    switch (operation) {
      case WhatsAppOperationType.renewal:
        // التجديد: كل الأنظمة متاحة
        return WhatsAppSystem.values;
      case WhatsAppOperationType.bulk:
        // الإرسال الجماعي: سيرفر و API فقط
        return [WhatsAppSystem.server, WhatsAppSystem.api];
    }
  }
}
