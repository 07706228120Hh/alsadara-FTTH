import 'package:shared_preferences/shared_preferences.dart';

class TemplatePasswordStorage {
  static const String _key = 'template_edit_password';

  static Future<void> savePassword(String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, password);
  }

  static Future<String?> loadPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  static Future<void> clearPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
