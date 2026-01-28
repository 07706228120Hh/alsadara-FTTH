import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/maintenance_messages.dart';

class MaintenanceMessagesService {
  static const String _messagesKey = 'maintenance_messages';
  static const String _passwordKey = 'maintenance_password';
  static const String _defaultPassword = '0770'; // تغيير كلمة المرور الافتراضية

  /// الحصول على الرسائل المحفوظة
  static Future<MaintenanceMessages> getMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = prefs.getString(_messagesKey);

      if (messagesJson != null) {
        final Map<String, dynamic> messagesMap = json.decode(messagesJson);
        return MaintenanceMessages.fromMap(messagesMap);
      }
    } catch (e) {
      print('خطأ في تحميل الرسائل: $e');
    }

    // إرجاع الرسائل الافتراضية إذا لم توجد رسائل محفوظة
    return MaintenanceMessages.defaultMessages();
  }

  /// حفظ الرسائل الجديدة
  static Future<bool> saveMessages(MaintenanceMessages messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final messagesJson = json.encode(messages.toMap());
      return await prefs.setString(_messagesKey, messagesJson);
    } catch (e) {
      print('خطأ في حفظ الرسائل: $e');
      return false;
    }
  }

  /// التحقق من كلمة المرور
  static Future<bool> verifyPassword(String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPassword = prefs.getString(_passwordKey) ?? _defaultPassword;
      return password == savedPassword;
    } catch (e) {
      print('خطأ في التحقق من كلمة المرور: $e');
      return false;
    }
  }

  /// تغيير كلمة المرور
  static Future<bool> changePassword(String oldPassword, String newPassword) async {
    try {
      // التحقق من كلمة المرور القديمة
      final isOldPasswordCorrect = await verifyPassword(oldPassword);
      if (!isOldPasswordCorrect) {
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      return await prefs.setString(_passwordKey, newPassword);
    } catch (e) {
      print('خطأ في تغيير كلمة المرور: $e');
      return false;
    }
  }

  /// الحصول على كلمة المرور الافتراضية (للمطورين فقط)
  static String getDefaultPassword() {
    return _defaultPassword;
  }

  /// إعادة تعيين الرسائل للقيم الافتراضية
  static Future<bool> resetToDefault() async {
    try {
      final defaultMessages = MaintenanceMessages.defaultMessages();
      return await saveMessages(defaultMessages);
    } catch (e) {
      print('خطأ في إعادة التعيين: $e');
      return false;
    }
  }

  /// تصدير الرسائل لأغراض النسخ الاحتياطي
  static Future<String?> exportMessages() async {
    try {
      final messages = await getMessages();
      return json.encode(messages.toMap());
    } catch (e) {
      print('خطأ في تصدير الرسائل: $e');
      return null;
    }
  }

  /// استيراد الرسائل من نسخة احتياطية
  static Future<bool> importMessages(String messagesJson, String currentUserName) async {
    try {
      final Map<String, dynamic> messagesMap = json.decode(messagesJson);
      final messages = MaintenanceMessages.fromMap(messagesMap);

      // تحديث معلومات آخر تعديل
      final updatedMessages = messages.copyWith(
        lastUpdated: DateTime.now(),
        updatedBy: currentUserName,
      );

      return await saveMessages(updatedMessages);
    } catch (e) {
      print('خطأ في استيراد الرسائل: $e');
      return false;
    }
  }
}
