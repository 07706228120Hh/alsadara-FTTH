import 'package:shared_preferences/shared_preferences.dart';

/// نوع الحساب — يحدّده الباكند من نطاق المستخدم (/api/auth/me → kind) أو توكن المشترك.
enum AccountKind { regulator, company, agent, subscriber }

AccountKind kindFrom(String? s) {
  switch (s) {
    case 'company':
      return AccountKind.company;
    case 'agent':
      return AccountKind.agent;
    case 'subscriber':
      return AccountKind.subscriber;
    default:
      return AccountKind.regulator;
  }
}

/// الجلسة الحالية — تُحفظ في shared_preferences كي تبقى بعد إغلاق التطبيق.
class Session {
  static String? token;
  static String? user; // اسم المستخدم (موظّف) أو رقم الهاتف (مشترك)
  static String role = 'viewer';
  static AccountKind kind = AccountKind.regulator;
  static int? companyId;
  static String agent = '';

  static bool get loggedIn => token != null && token!.isNotEmpty;
  static bool get isAdmin => role == 'admin';
  static bool get isOperator => role == 'operator' || role == 'admin';

  static const _kToken = 'pc_token';
  static const _kUser = 'pc_user';
  static const _kRole = 'pc_role';
  static const _kKind = 'pc_kind';
  static const _kCid = 'pc_cid';
  static const _kAgent = 'pc_agent';

  static Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      token = p.getString(_kToken);
      user = p.getString(_kUser);
      role = p.getString(_kRole) ?? 'viewer';
      kind = kindFrom(p.getString(_kKind));
      companyId = p.getInt(_kCid);
      agent = p.getString(_kAgent) ?? '';
    } catch (_) {
      // التخزين غير متاح (ويب بوضع خاص مثلاً) — نتابع بجلسة فارغة
    }
  }

  static Future<void> set({
    required String tk,
    required String? usr,
    required String rl,
    required AccountKind k,
    int? cid,
    String ag = '',
  }) async {
    token = tk;
    user = usr;
    role = rl;
    kind = k;
    companyId = cid;
    agent = ag;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kToken, tk);
      if (usr != null) await p.setString(_kUser, usr);
      await p.setString(_kRole, rl);
      await p.setString(_kKind, k.name);
      if (cid != null) {
        await p.setInt(_kCid, cid);
      } else {
        await p.remove(_kCid);
      }
      await p.setString(_kAgent, ag);
    } catch (_) {}
  }

  static Future<void> clear() async {
    token = null;
    user = null;
    role = 'viewer';
    kind = AccountKind.regulator;
    companyId = null;
    agent = '';
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in [_kToken, _kUser, _kRole, _kKind, _kCid, _kAgent]) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}

/// حفظ اختياري لاسم المستخدم وكلمة المرور محليّاً («تذكّرني»).
///
/// ⚠️ تنبيه أمني: تُخزَّن كلمة المرور **نصّاً صريحاً** في shared_preferences
/// (localStorage على الويب) — مناسب لجهاز موثوق/وضع تطوير؛ في الإنتاج فضّل مدير
/// كلمات مرور المتصفّح أو تخزيناً آمناً. المفتاح [key] لكل تطبيق لتفادي التداخل.
class RememberedCredentials {
  static String _uKey(String key) => 'pc_remember_u_$key';
  static String _pKey(String key) => 'pc_remember_p_$key';

  static Future<void> save(String key, String user, String pass) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_uKey(key), user);
      await p.setString(_pKey(key), pass);
    } catch (_) {}
  }

  static Future<({String user, String pass})?> load(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final u = p.getString(_uKey(key));
      final pw = p.getString(_pKey(key));
      if (u != null && u.isNotEmpty && pw != null) return (user: u, pass: pw);
    } catch (_) {}
    return null;
  }

  static Future<void> clear(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_uKey(key));
      await p.remove(_pKey(key));
    } catch (_) {}
  }
}
