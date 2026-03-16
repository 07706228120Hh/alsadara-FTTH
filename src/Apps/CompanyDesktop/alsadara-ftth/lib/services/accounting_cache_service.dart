import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache بسيط بزمن صلاحية قصير (TTL) لبيانات المحاسبة.
/// نمط مطابق لـ FtthCacheService: L1 ذاكرة static، L2 SharedPreferences.
class AccountingCacheService {
  static const _dashKey = 'acc_cache_dashboard';
  static const _accountsKey = 'acc_cache_accounts';
  static const _trialKey = 'acc_cache_trial_balance';
  static const _fundsKey = 'acc_cache_funds';
  static const _tsDash = 'acc_cache_dashboard_ts';
  static const _tsAccounts = 'acc_cache_accounts_ts';
  static const _tsTrial = 'acc_cache_trial_balance_ts';
  static const _tsFunds = 'acc_cache_funds_ts';
  static const Duration ttl = Duration(minutes: 5);

  // ════════════ كاش في الذاكرة ════════════
  static Map<String, dynamic>? _memDashboard;
  static List<dynamic>? _memAccounts;
  static List<dynamic>? _memTrial;
  static Map<String, dynamic>? _memFunds;
  static int? _memDashTs;
  static int? _memAccountsTs;
  static int? _memTrialTs;
  static int? _memFundsTs;

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
    await prefs.setInt(_tsDash, now);
  }

  static Future<Map<String, dynamic>?> loadDashboard() async {
    if (_isValid(_memDashTs) && _memDashboard != null) return _memDashboard;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_dashKey);
    final ts = prefs.getInt(_tsDash);
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

  static void invalidateDashboard() {
    _memDashboard = null;
    _memDashTs = null;
  }

  // ═══════════ Accounts ═══════════

  static Future<void> saveAccounts(List<dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _memAccounts = data;
    _memAccountsTs = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountsKey, json.encode(data));
    await prefs.setInt(_tsAccounts, now);
  }

  static Future<List<dynamic>?> loadAccounts() async {
    if (_isValid(_memAccountsTs) && _memAccounts != null) return _memAccounts;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    final ts = prefs.getInt(_tsAccounts);
    if (raw == null || ts == null) return null;
    if (!_isValid(ts)) return null;
    try {
      final data = json.decode(raw) as List<dynamic>;
      _memAccounts = data;
      _memAccountsTs = ts;
      return data;
    } catch (_) {
      return null;
    }
  }

  static void invalidateAccounts() {
    _memAccounts = null;
    _memAccountsTs = null;
  }

  // ═══════════ Trial Balance ═══════════

  static Future<void> saveTrialBalance(List<dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _memTrial = data;
    _memTrialTs = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_trialKey, json.encode(data));
    await prefs.setInt(_tsTrial, now);
  }

  static Future<List<dynamic>?> loadTrialBalance() async {
    if (_isValid(_memTrialTs) && _memTrial != null) return _memTrial;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_trialKey);
    final ts = prefs.getInt(_tsTrial);
    if (raw == null || ts == null) return null;
    if (!_isValid(ts)) return null;
    try {
      final data = json.decode(raw) as List<dynamic>;
      _memTrial = data;
      _memTrialTs = ts;
      return data;
    } catch (_) {
      return null;
    }
  }

  // ═══════════ Funds Overview ═══════════

  static Future<void> saveFunds(Map<String, dynamic> data) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _memFunds = data;
    _memFundsTs = now;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fundsKey, json.encode(data));
    await prefs.setInt(_tsFunds, now);
  }

  static Future<Map<String, dynamic>?> loadFunds() async {
    if (_isValid(_memFundsTs) && _memFunds != null) return _memFunds;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_fundsKey);
    final ts = prefs.getInt(_tsFunds);
    if (raw == null || ts == null) return null;
    if (!_isValid(ts)) return null;
    try {
      final data = json.decode(raw) as Map<String, dynamic>;
      _memFunds = data;
      _memFundsTs = ts;
      return data;
    } catch (_) {
      return null;
    }
  }

  // ═══════════ إبطال + مسح ═══════════

  static void invalidateAll() {
    _memDashboard = null;
    _memAccounts = null;
    _memTrial = null;
    _memFunds = null;
    _memDashTs = null;
    _memAccountsTs = null;
    _memTrialTs = null;
    _memFundsTs = null;
  }

  static Future<void> clearAll() async {
    invalidateAll();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_dashKey),
      prefs.remove(_accountsKey),
      prefs.remove(_trialKey),
      prefs.remove(_fundsKey),
      prefs.remove(_tsDash),
      prefs.remove(_tsAccounts),
      prefs.remove(_tsTrial),
      prefs.remove(_tsFunds),
    ]);
  }
}
