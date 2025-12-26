import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// مدير التكوين المركزي للتطبيق
/// يدير جميع إعدادات التطبيق والعميل بطريقة آمنة
class ConfigManager {
  static final ConfigManager _instance = ConfigManager._internal();
  factory ConfigManager() => _instance;
  ConfigManager._internal();

  static ConfigManager get instance => _instance;

  // التخزين الآمن للبيانات الحساسة
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  late SharedPreferences _prefs;
  Map<String, dynamic>? _clientConfig;
  bool _initialized = false;

  /// تهيئة مدير التكوين
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // تحميل متغيرات البيئة
      await dotenv.load(fileName: ".env");

      // تهيئة SharedPreferences
      _prefs = await SharedPreferences.getInstance();

      // تحميل تكوين العميل
      await _loadClientConfig();

      _initialized = true;
      debugPrint('✅ تم تهيئة مدير التكوين بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة مدير التكوين: $e');
      rethrow;
    }
  }

  /// تحميل تكوين العميل من ملف JSON
  Future<void> _loadClientConfig() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final configFile = File('${appDir.path}/client_config.json');

      if (await configFile.exists()) {
        final configString = await configFile.readAsString();
        _clientConfig = jsonDecode(configString);
        debugPrint('✅ تم تحميل تكوين العميل');
      } else {
        // إنشاء ملف التكوين الافتراضي
        await _createDefaultConfig(configFile);
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في تحميل تكوين العميل: $e');
      _clientConfig = {};
    }
  }

  /// إنشاء ملف التكوين الافتراضي
  Future<void> _createDefaultConfig(File configFile) async {
    final defaultConfig = {
      'client_info': {
        'company_name': '',
        'setup_date': DateTime.now().toIso8601String(),
        'version': dotenv.env['APP_VERSION'] ?? '1.0.0',
      },
      'api_settings': {
        'base_url': dotenv.env['FTTH_API_BASE_URL'] ?? 'https://api.ftth.iq',
        'timeout_seconds':
            int.tryParse(dotenv.env['CONNECTION_TIMEOUT_SECONDS'] ?? '30') ??
                30,
      },
      'ui_settings': {
        'language': dotenv.env['DEFAULT_LANGUAGE'] ?? 'ar',
        'theme': dotenv.env['DEFAULT_THEME'] ?? 'light',
        'notifications_enabled': dotenv.env['ENABLE_NOTIFICATIONS'] == 'true',
      },
      'features': {
        'whatsapp_enabled': true,
        'google_sheets_enabled': dotenv.env['GOOGLE_SHEETS_ENABLED'] == 'true',
        'auto_backup_enabled': dotenv.env['ENABLE_AUTO_BACKUP'] == 'true',
      }
    };

    await configFile.writeAsString(jsonEncode(defaultConfig));
    _clientConfig = defaultConfig;
    debugPrint('✅ تم إنشاء ملف التكوين الافتراضي');
  }

  /// حفظ إعداد آمن (للبيانات الحساسة)
  Future<void> setSecureValue(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  /// قراءة إعداد آمن
  Future<String?> getSecureValue(String key) async {
    return await _secureStorage.read(key: key);
  }

  /// حفظ إعداد عام
  Future<void> setValue(String key, dynamic value) async {
    if (value is String) {
      await _prefs.setString(key, value);
    } else if (value is int) {
      await _prefs.setInt(key, value);
    } else if (value is double) {
      await _prefs.setDouble(key, value);
    } else if (value is bool) {
      await _prefs.setBool(key, value);
    } else if (value is List<String>) {
      await _prefs.setStringList(key, value);
    }
  }

  /// قراءة إعداد عام
  T? getValue<T>(String key, [T? defaultValue]) {
    switch (T) {
      case String:
        return _prefs.getString(key) as T? ?? defaultValue;
      case int:
        return _prefs.getInt(key) as T? ?? defaultValue;
      case double:
        return _prefs.getDouble(key) as T? ?? defaultValue;
      case bool:
        return _prefs.getBool(key) as T? ?? defaultValue;
      default:
        return defaultValue;
    }
  }

  /// الحصول على إعدادات API
  Map<String, dynamic> get apiSettings {
    return {
      'base_url': dotenv.env['FTTH_API_BASE_URL'] ?? 'https://api.ftth.iq',
      'version': dotenv.env['FTTH_API_VERSION'] ?? 'v1',
      'timeout':
          int.tryParse(dotenv.env['CONNECTION_TIMEOUT_SECONDS'] ?? '30') ?? 30,
      'max_retries': int.tryParse(dotenv.env['MAX_RETRY_ATTEMPTS'] ?? '3') ?? 3,
    };
  }

  /// الحصول على إعدادات الواتساب
  Map<String, dynamic> get whatsappSettings {
    return {
      'enabled': _clientConfig?['features']?['whatsapp_enabled'] ?? true,
    };
  }

  /// الحصول على معلومات العميل
  Map<String, dynamic> get clientInfo {
    return _clientConfig?['client_info'] ?? {};
  }

  /// تحديث معلومات العميل
  Future<void> updateClientInfo(Map<String, dynamic> info) async {
    _clientConfig ??= {};
    _clientConfig!['client_info'] = {...clientInfo, ...info};
    await _saveClientConfig();
  }

  /// حفظ ملف التكوين
  Future<void> _saveClientConfig() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final configFile = File('${appDir.path}/client_config.json');
      await configFile.writeAsString(jsonEncode(_clientConfig));
    } catch (e) {
      debugPrint('❌ خطأ في حفظ التكوين: $e');
    }
  }

  /// فحص التحديثات
  Future<Map<String, dynamic>?> checkForUpdates() async {
    final updateServer = dotenv.env['UPDATE_SERVER_URL'];
    if (updateServer == null || updateServer.isEmpty) return null;

    try {
      // TODO: تنفيذ منطق فحص التحديثات
      debugPrint('🔍 فحص التحديثات من: $updateServer');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في فحص التحديثات: $e');
      return null;
    }
  }

  /// إعداد أولي للعميل
  Future<bool> setupClient({
    required String companyName,
    required String apiKey,
    String? clientId,
    String? clientSecret,
  }) async {
    try {
      // حفظ البيانات الحساسة
      if (clientId != null) await setSecureValue('client_id', clientId);
      if (clientSecret != null) {
        await setSecureValue('client_secret', clientSecret);
      }
      await setSecureValue('api_key', apiKey);

      // تحديث معلومات العميل
      await updateClientInfo({
        'company_name': companyName,
        'setup_completed': true,
        'setup_date': DateTime.now().toIso8601String(),
      });

      debugPrint('✅ تم إعداد العميل بنجاح: $companyName');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في إعداد العميل: $e');
      return false;
    }
  }

  /// التحقق من اكتمال الإعداد
  bool get isSetupCompleted {
    return clientInfo['setup_completed'] == true;
  }

  /// الحصول على اسم الشركة
  String get companyName {
    return clientInfo['company_name'] ?? 'الصدارة';
  }

  /// تصدير الإعدادات للنسخ الاحتياطي
  Future<String> exportSettings() async {
    final settings = {
      'client_config': _clientConfig,
      'app_preferences':
          _prefs.getKeys().fold<Map<String, dynamic>>({}, (map, key) {
        final value = _prefs.get(key);
        if (value != null) map[key] = value;
        return map;
      }),
      'export_date': DateTime.now().toIso8601String(),
      'app_version': dotenv.env['APP_VERSION'],
    };

    return jsonEncode(settings);
  }

  /// استيراد الإعدادات من نسخة احتياطية
  Future<bool> importSettings(String settingsJson) async {
    try {
      final settings = jsonDecode(settingsJson);

      // استيراد تكوين العميل
      if (settings['client_config'] != null) {
        _clientConfig = settings['client_config'];
        await _saveClientConfig();
      }

      // استيراد تفضيلات التطبيق
      if (settings['app_preferences'] != null) {
        final prefs = settings['app_preferences'] as Map<String, dynamic>;
        for (final entry in prefs.entries) {
          final key = entry.key;
          final value = entry.value;

          if (value is String) {
            await _prefs.setString(key, value);
          } else if (value is int) {
            await _prefs.setInt(key, value);
          } else if (value is double) {
            await _prefs.setDouble(key, value);
          } else if (value is bool) {
            await _prefs.setBool(key, value);
          } else if (value is List) {
            await _prefs.setStringList(key, value.cast<String>());
          }
        }
      }

      debugPrint('✅ تم استيراد الإعدادات بنجاح');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في استيراد الإعدادات: $e');
      return false;
    }
  }

  /// مسح جميع البيانات (إعادة تعيين)
  Future<void> resetAll() async {
    await _prefs.clear();
    await _secureStorage.deleteAll();

    final appDir = await getApplicationDocumentsDirectory();
    final configFile = File('${appDir.path}/client_config.json');
    if (await configFile.exists()) {
      await configFile.delete();
    }

    _clientConfig = null;
    _initialized = false;

    debugPrint('🔄 تم مسح جميع البيانات');
  }
}
