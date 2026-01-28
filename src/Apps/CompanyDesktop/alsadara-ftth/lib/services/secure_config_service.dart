import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureConfigService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Google Sheets Configuration
  static String get googleSheetsApiKey => dotenv.env['GOOGLE_SHEETS_API_KEY'] ?? '';
  static String get spreadsheetId => dotenv.env['GOOGLE_SHEETS_SPREADSHEET_ID'] ?? '';
  static String get sheetsRange => dotenv.env['GOOGLE_SHEETS_RANGE'] ?? 'المستخدمين!A2:J';

  // التحقق من صحة التكوين
  static bool get isConfigValid {
    return googleSheetsApiKey.isNotEmpty && 
           spreadsheetId.isNotEmpty && 
           sheetsRange.isNotEmpty;
  }

  // حفظ بيانات المستخدم بشكل آمن
  static Future<void> saveUserCredentials({
    required String username,
    required String phone,
    required bool rememberMe,
  }) async {
    try {
      if (rememberMe) {
        await _storage.write(key: 'username', value: username);
        await _storage.write(key: 'phone', value: phone);
        await _storage.write(key: 'rememberMe', value: 'true');
      } else {
        await _storage.delete(key: 'username');
        await _storage.delete(key: 'phone');
        await _storage.write(key: 'rememberMe', value: 'false');
      }
    } catch (e) {
      throw Exception('خطأ في حفظ بيانات المستخدم: $e');
    }
  }

  // استرداد بيانات المستخدم المحفوظة
  static Future<Map<String, String?>> getSavedCredentials() async {
    try {
      return {
        'username': await _storage.read(key: 'username'),
        'phone': await _storage.read(key: 'phone'),
        'rememberMe': await _storage.read(key: 'rememberMe'),
      };
    } catch (e) {
      throw Exception('خطأ في استرداد بيانات المستخدم: $e');
    }
  }

  // مسح جميع البيانات المحفوظة
  static Future<void> clearAllData() async {
    try {
      await _storage.deleteAll();
    } catch (e) {
      throw Exception('خطأ في مسح البيانات: $e');
    }
  }
}
