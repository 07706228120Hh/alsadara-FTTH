import 'package:shared_preferences/shared_preferences.dart';

class PermissionsStorage {
  static const String _key = 'permissions_granted';

  static Future<void> setPermissionsGranted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }

  static Future<bool> getPermissionsGranted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }
}
