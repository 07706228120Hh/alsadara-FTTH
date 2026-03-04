import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache بسيط بزمن صلاحية قصير (TTL) لبيانات لوحة التحكم و الرصيد و بيانات المستخدم.
class FtthCacheService {
  static const _dashKey = 'ftth_cache_dashboard';
  static const _walletKey = 'ftth_cache_wallet';
  static const _userKey = 'ftth_cache_current_user';
  static const _tsKeyDash = 'ftth_cache_dashboard_ts';
  static const _tsKeyWallet = 'ftth_cache_wallet_ts';
  static const _tsKeyUser = 'ftth_cache_current_user_ts';
  static const Duration ttl = Duration(minutes: 5);

  // ════════════ كاش في الذاكرة (أسرع من SharedPreferences) ════════════
  static Map<String, dynamic>? _memDashboard;
  static Map<String, dynamic>? _memWallet;
  static Map<String, dynamic>? _memUser;
  static int? _memDashTs;
  static int? _memWalletTs;
  static int? _memUserTs;

  /// هل الكاش صالح (لم تنتهِ صلاحيته)؟
  static bool _isValid(int? ts) {
    if (ts == null) return false;
    return DateTime.now().millisecondsSinceEpoch - ts < ttl.inMilliseconds;
  }

  // ═══════════ Dashboard ═══════════

  static Future<void> saveDashboard(Map<String, dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _memDashboard = data;
    _memDashTs = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_dashKey, json.encode(data));
    await prefs.setInt(_tsKeyDash, now);
  }

  static Future<Map<String, dynamic>?> loadDashboard() async {
    // ذاكرة أولاً
    if (_isValid(_memDashTs) && _memDashboard != null) return _memDashboard;
    // ثم SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dashKey);
    final ts = prefs.getInt(_tsKeyDash);
    if (raw == null || ts == null) return null;
    if (!_isValid(ts)) return null;
    try {
      final data = json.decode(raw) as Map<String, dynamic>;
      _memDashboard = data;
      _memDashTs = ts;
      return data;
    } catch (_) {
      return null;
    }
  }

  // ═══════════ Wallet ═══════════

  static Future<void> saveWallet(Map<String, dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _memWallet = data;
    _memWalletTs = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_walletKey, json.encode(data));
    await prefs.setInt(_tsKeyWallet, now);
  }

  static Future<Map<String, dynamic>?> loadWallet() async {
    if (_isValid(_memWalletTs) && _memWallet != null) return _memWallet;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_walletKey);
    final ts = prefs.getInt(_tsKeyWallet);
    if (raw == null || ts == null) return null;
    if (!_isValid(ts)) return null;
    try {
      final data = json.decode(raw) as Map<String, dynamic>;
      _memWallet = data;
      _memWalletTs = ts;
      return data;
    } catch (_) {
      return null;
    }
  }

  // ═══════════ Current User ═══════════

  static Future<void> saveCurrentUser(Map<String, dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _memUser = data;
    _memUserTs = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, json.encode(data));
    await prefs.setInt(_tsKeyUser, now);
  }

  static Future<Map<String, dynamic>?> loadCurrentUser() async {
    if (_isValid(_memUserTs) && _memUser != null) return _memUser;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    final ts = prefs.getInt(_tsKeyUser);
    if (raw == null || ts == null) return null;
    if (!_isValid(ts)) return null;
    try {
      final data = json.decode(raw) as Map<String, dynamic>;
      _memUser = data;
      _memUserTs = ts;
      return data;
    } catch (_) {
      return null;
    }
  }

  // ═══════════ مسح الكاش ═══════════

  /// مسح جميع الكاش (عند تسجيل الخروج مثلاً)
  static Future<void> clearAll() async {
    _memDashboard = null;
    _memWallet = null;
    _memUser = null;
    _memDashTs = null;
    _memWalletTs = null;
    _memUserTs = null;
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_dashKey),
      prefs.remove(_walletKey),
      prefs.remove(_userKey),
      prefs.remove(_tsKeyDash),
      prefs.remove(_tsKeyWallet),
      prefs.remove(_tsKeyUser),
    ]);
  }
}
