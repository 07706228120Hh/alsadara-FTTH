import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache بسيط بزمن صلاحية قصير (TTL) لبيانات لوحة التحكم و الرصيد.
class FtthCacheService {
  static const _dashKey = 'ftth_cache_dashboard';
  static const _walletKey = 'ftth_cache_wallet';
  static const _tsKeyDash = 'ftth_cache_dashboard_ts';
  static const _tsKeyWallet = 'ftth_cache_wallet_ts';
  static const Duration ttl = Duration(minutes: 5);

  static Future<void> saveDashboard(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dashKey, json.encode(data));
    await prefs.setInt(_tsKeyDash, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> saveWallet(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_walletKey, json.encode(data));
    await prefs.setInt(_tsKeyWallet, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<Map<String, dynamic>?> loadDashboard() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dashKey);
    final ts = prefs.getInt(_tsKeyDash);
    if (raw == null || ts == null) return null;
    if (DateTime.now().millisecondsSinceEpoch - ts > ttl.inMilliseconds) {
      return null;
    }
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> loadWallet() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_walletKey);
    final ts = prefs.getInt(_tsKeyWallet);
    if (raw == null || ts == null) return null;
    if (DateTime.now().millisecondsSinceEpoch - ts > ttl.inMilliseconds) {
      return null;
    }
    try {
      return json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
