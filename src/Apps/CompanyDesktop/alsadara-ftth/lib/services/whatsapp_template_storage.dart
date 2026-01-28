import 'package:shared_preferences/shared_preferences.dart';

class WhatsAppTemplateStorage {
  static const _key = 'whatsapp_template';

  static Future<void> saveTemplate(String template) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, template);
  }

  static Future<String?> loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }
}
