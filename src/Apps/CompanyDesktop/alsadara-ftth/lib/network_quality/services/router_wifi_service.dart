/// تعديل اسم/كلمة مرور WiFi للراوتر — Network Quality (فحص متقدّم، حسّاس)
///
/// ميزة كتابة إلى جهاز حقيقي. ضمانات أمنية صارمة:
///  • لا دخول صامت: الاعتماد يُدخَل صراحةً من المستخدم ويُمرَّر لكل عملية.
///  • لا طباعة/تسجيل/حفظ للاعتماد أو كلمة المرور إطلاقاً.
///  • التطبيق يتحقّق بإعادة القراءة؛ لا نجاح مُعلَن إلا بعد تأكيد.
///  • يدعم Huawei ثم ZTE؛ غير ذلك ⇒ رسالة واضحة بلا تغيير.
///
/// الواجهة [RouterWifiApi] مجرّدة ليُحقن منطق معزول في الاختبار (بلا اتصال فعلي).
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart' as pc;

/// الإعداد الحالي المقروء من الراوتر.
class RouterWifiConfig {
  final String ssid;
  final String security; // نوع التأمين إن توفّر
  final String model; // Huawei / ZTE
  const RouterWifiConfig(
      {required this.ssid, this.security = '', required this.model});
}

class RouterWifiReadResult {
  final bool ok;
  final RouterWifiConfig? config;
  final String error;
  const RouterWifiReadResult({required this.ok, this.config, this.error = ''});
}

class RouterWifiApplyResult {
  final bool ok; // نجحت العملية (طُبّقت وتُحقّق منها)
  final bool verified; // تأكّد التغيير بإعادة القراءة
  final String message;
  const RouterWifiApplyResult(
      {required this.ok, this.verified = false, required this.message});
}

/// واجهة مجرّدة (تُحقن في الاختبار لعزل الشبكة).
abstract class RouterWifiApi {
  Future<RouterWifiReadResult> read({
    required String host,
    required String user,
    required String pass,
    String? brandOverride,
  });

  Future<RouterWifiApplyResult> apply({
    required String host,
    required String user,
    required String pass,
    String? newSsid,
    String? newPassword,
    String? brandOverride,
  });
}

/// التنفيذ الفعلي عبر HTTP (Huawei/ZTE). لا يُطبع أي سرّ.
class RouterWifiService implements RouterWifiApi {
  static const _timeout = Duration(seconds: 7);

  /// رسالة رفض المضيف غير المحلّي (مشتركة مع الواجهة).
  static const invalidHostMessage =
      'عنوان الراوتر يجب أن يكون عنوان شبكة محلية (مثل 192.168.x.x).';

  /// يتحقّق أن [host] عنوان IPv4 ضمن نطاقات LAN الخاصة فقط
  /// (10/8، 172.16/12، 192.168/16، 127/8). يرفض أسماء النطاقات وأي مسار/استعلام.
  static bool isPrivateLanHost(String host) {
    final h = host.trim();
    if (h.isEmpty) return false;
    // لا يُسمح بأي محرف خارج أرقام IPv4 (يمنع أسماء النطاقات والمسارات/الاستعلامات).
    if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(h)) return false;
    final parts = h.split('.').map(int.parse).toList();
    if (parts.any((o) => o > 255)) return false;
    final a = parts[0], b = parts[1];
    if (a == 10) return true; // 10.0.0.0/8
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 127) return true; // 127.0.0.0/8 (loopback)
    return false;
  }

  @override
  Future<RouterWifiReadResult> read({
    required String host,
    required String user,
    required String pass,
    String? brandOverride,
  }) async {
    if (!isPrivateLanHost(host)) {
      return const RouterWifiReadResult(ok: false, error: invalidHostMessage);
    }
    // النوع اليدوي يتجاوز الكشف التلقائي ويُجبر مسار تلك الماركة.
    final forced = (brandOverride != null && brandOverride.isNotEmpty);
    final brand = forced ? brandOverride : await _probeBrand(host);

    // TP-Link/Mercusys: دخول مشفّر (RSA + AES + stok) عبر pointycastle.
    if (brand == 'TP-Link' || brand == 'Mercusys') {
      try {
        final ssid = await _tpReadSsid(host, user, pass);
        if (ssid != null) {
          return RouterWifiReadResult(
              ok: true, config: RouterWifiConfig(ssid: ssid, model: brand));
        }
      } catch (_) {
        debugPrint('[RouterWifi] tp read failed (sanitized)');
      }
      return RouterWifiReadResult(ok: false, error: _failMessage);
    }
    try {
      if (brand == 'ZTE') {
        final ssid = await _zteReadSsid(host, user, pass);
        if (ssid != null) {
          return RouterWifiReadResult(
              ok: true, config: RouterWifiConfig(ssid: ssid, model: 'ZTE'));
        }
      } else if (brand == 'Tenda') {
        final ssid = await _tendaReadSsid(host, user, pass);
        if (ssid != null) {
          return RouterWifiReadResult(
              ok: true, config: RouterWifiConfig(ssid: ssid, model: 'Tenda'));
        }
      } else if (brand == 'Huawei') {
        final ssid = await _huaweiReadSsid(host, user, pass);
        if (ssid != null) {
          return RouterWifiReadResult(
              ok: true, config: RouterWifiConfig(ssid: ssid, model: 'Huawei'));
        }
      } else {
        // ماركة غير مؤكّدة — جرّب كل المدعومة بالتسلسل:
        // Huawei → ZTE → Tenda → TP-Link/Mercusys (المشفّر).
        final hssid = await _huaweiReadSsid(host, user, pass);
        if (hssid != null) {
          return RouterWifiReadResult(
              ok: true, config: RouterWifiConfig(ssid: hssid, model: 'Huawei'));
        }
        final zssid = await _zteReadSsid(host, user, pass);
        if (zssid != null) {
          return RouterWifiReadResult(
              ok: true, config: RouterWifiConfig(ssid: zssid, model: 'ZTE'));
        }
        final tssid = await _tendaReadSsid(host, user, pass);
        if (tssid != null) {
          return RouterWifiReadResult(
              ok: true, config: RouterWifiConfig(ssid: tssid, model: 'Tenda'));
        }
        // محاولة أخيرة: المسار المشفّر (قد يكون Mercusys/TP-Link بلا كشف).
        try {
          final tp = await _tpReadSsid(host, user, pass);
          if (tp != null) {
            return RouterWifiReadResult(
                ok: true, config: RouterWifiConfig(ssid: tp, model: 'Mercusys'));
          }
        } catch (_) {}
      }
    } catch (e) {
      // لا نطبع تفاصيل قد تحوي اعتماداً.
      debugPrint('[RouterWifi] read failed (sanitized)');
    }
    return const RouterWifiReadResult(ok: false, error: _failMessage);
  }

  /// رسالة فشل موحّدة تذكر كل المدعوم وتوجّه للخيارات البديلة (بلا ادّعاء نجاح).
  static const String _failMessage =
      'تعذّر الدخول/قراءة الإعداد — تحقّق من اسم المستخدم وكلمة المرور. '
      'المدعوم: Huawei/ZTE/Tenda/TP‑Link/Mercusys. جرّب اختيار «نوع الراوتر» '
      'يدوياً، أو افتح واجهة الراوتر في المتصفح.';

  @override
  Future<RouterWifiApplyResult> apply({
    required String host,
    required String user,
    required String pass,
    String? newSsid,
    String? newPassword,
    String? brandOverride,
  }) async {
    if (!isPrivateLanHost(host)) {
      return const RouterWifiApplyResult(ok: false, message: invalidHostMessage);
    }
    // اقرأ أولاً للتأكّد من صحّة الاعتماد وتحديد الموديل (مع النوع اليدوي إن وُجد).
    final before = await read(
        host: host, user: user, pass: pass, brandOverride: brandOverride);
    if (!before.ok || before.config == null) {
      return RouterWifiApplyResult(ok: false, message: before.error);
    }
    final model = before.config!.model;
    try {
      bool applied = false;
      if (model == 'Huawei') {
        applied = await _huaweiApply(host, user, pass, newSsid, newPassword);
      } else if (model == 'ZTE') {
        applied = await _zteApply(host, user, pass, newSsid, newPassword);
      } else if (model == 'Tenda') {
        applied = await _tendaApply(host, user, pass, newSsid, newPassword);
      } else if (model == 'TP-Link' || model == 'Mercusys') {
        applied = await _tpApply(host, user, pass, newSsid, newPassword);
      } else {
        return const RouterWifiApplyResult(
            ok: false,
            message:
                'يدعم حالياً Huawei/ZTE/Tenda/TP‑Link/Mercusys؛ على غيرها استخدم واجهة الراوتر.');
      }
      if (!applied) {
        return const RouterWifiApplyResult(
            ok: false,
            message:
                'تعذّر تطبيق التغيير على هذا الموديل — استخدم واجهة الراوتر مباشرةً.');
      }
      // تحقّق بإعادة القراءة (SSID فقط؛ كلمة المرور لا تُقرأ لأسباب أمنية).
      if (newSsid != null && newSsid.isNotEmpty) {
        final after = await read(
            host: host, user: user, pass: pass, brandOverride: brandOverride);
        final verified = after.ok && after.config?.ssid == newSsid;
        return RouterWifiApplyResult(
          ok: true,
          verified: verified,
          message: verified
              ? 'تم التطبيق والتحقّق — أعد توصيل أجهزتك بالإعداد الجديد.'
              : 'طُبّق الطلب لكن تعذّر تأكيد التغيير تلقائياً — تحقّق يدوياً.',
        );
      }
      // كلمة المرور فقط: لا طريقة موثوقة لقراءتها ⇒ لا نُعلن نجاحاً مؤكَّداً.
      return const RouterWifiApplyResult(
        ok: true,
        verified: false,
        message:
            'أُرسل الطلب إلى الراوتر — تعذّر التأكيد التلقائي لتغيير كلمة المرور؛ '
            'تحقّق يدوياً بإعادة الاتصال بالكلمة الجديدة.',
      );
    } catch (e) {
      debugPrint('[RouterWifi] apply failed (sanitized)');
      return const RouterWifiApplyResult(
          ok: false,
          message: 'حدث خطأ أثناء التطبيق — لم يُؤكَّد أي تغيير.');
    }
  }

  // ═══════════════ كشف الماركة ═══════════════
  static Future<String> _probeBrand(String host) async {
    try {
      final r = await http
          .get(Uri.parse('http://$host/'))
          .timeout(const Duration(seconds: 4));
      return detectBrandFromBody(
          '${r.body} ${r.headers}');
    } catch (_) {}
    return 'Unknown';
  }

  /// كشف الماركة من نصّ الصفحة/الترويسات (نقيّ وقابل للاختبار بلا شبكة).
  static String detectBrandFromBody(String raw) {
    final body = raw.toLowerCase();
    // بصمة dynaform مميِّزة لفيرموير Tenda (AC6/AC8/AC10/AC12/AC15/AC18/AC23...).
    if (body.contains('dynaform')) return 'Tenda';
    if (body.contains('tenda')) return 'Tenda';
    // Mercusys قبل TP-Link (عائلة منفصلة رغم تقارب البرمجيات).
    if (body.contains('mercusys')) return 'Mercusys';
    if (body.contains('tp-link') ||
        body.contains('tplink') ||
        body.contains('archer') ||
        body.contains('tl-wr') ||
        body.contains('tl-wa')) {
      return 'TP-Link';
    }
    // عنوان صفحة على نمط موديل Tenda AC (بعد استبعاد Archer/TP-Link أعلاه).
    if (RegExp(r'\bac\d{1,4}\b').hasMatch(body)) return 'Tenda';
    if (body.contains('zte') || body.contains('zxhn') || body.contains('f6')) {
      return 'ZTE';
    }
    if (body.contains('huawei') ||
        body.contains('hg8') ||
        body.contains('echolife')) {
      return 'Huawei';
    }
    return 'Unknown';
  }

  // ═══════════════ Huawei ═══════════════
  // كوكيز الجلسة + توكن مكافحة التزوير (نمط HG8xxx/EG8xxx).
  static Future<_HwSession?> _huaweiLogin(
      http.Client client, String host, String user, String pass) async {
    final jar = <String, String>{};
    String cookie() => jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    void absorb(Map<String, String> h) {
      final sc = h['set-cookie'];
      if (sc == null) return;
      for (final part in sc.split(RegExp(r',(?=[^=;,]+=)'))) {
        final kv = part.split(';').first.trim();
        final i = kv.indexOf('=');
        if (i > 0) jar[kv.substring(0, i).trim()] = kv.substring(i + 1).trim();
      }
    }

    try {
      final r0 = await client.get(Uri.parse('http://$host/')).timeout(_timeout);
      absorb(r0.headers);
    } catch (_) {}
    String token = '';
    for (final tp in ['/asp/GetRandCount.asp', '/asp/GetRandCount']) {
      try {
        final rt = await client.get(Uri.parse('http://$host$tp'),
            headers: {'Cookie': cookie(), 'Referer': 'http://$host/'}).timeout(
            _timeout);
        absorb(rt.headers);
        final t = rt.body.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
        if (t.isNotEmpty) {
          token = t;
          break;
        }
      } catch (_) {}
    }
    for (final ep in ['/login.cgi', '/']) {
      try {
        final rl = await client.post(
          Uri.parse('http://$host$ep'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Cookie': cookie(),
            'Referer': 'http://$host/',
          },
          body: 'UserName=${Uri.encodeQueryComponent(user)}'
              '&PassWord=${base64Encode(utf8.encode(pass))}'
              '&Language=english&x.X_HW_Token=$token',
        ).timeout(_timeout);
        absorb(rl.headers);
      } catch (_) {}
    }
    if (jar.isEmpty) return null;
    return _HwSession(cookie(), token);
  }

  static const _hwWlanPages = [
    '/html/amp/wlan/wlanbasic.asp',
    '/html/network/wlan.asp',
    '/html/bbsp/wlanbasic/wlanbasic.asp',
    '/html/amp/wlan/wlanadvanced.asp',
  ];

  static Future<String?> _huaweiReadSsid(
      String host, String user, String pass) async {
    final client = http.Client();
    try {
      final s = await _huaweiLogin(client, host, user, pass);
      if (s == null) return null;
      for (final page in _hwWlanPages) {
        try {
          final r = await client.get(Uri.parse('http://$host$page'),
              headers: {'Cookie': s.cookie, 'Referer': 'http://$host/'}).timeout(
              _timeout);
          if (r.statusCode == 200 && r.body.length > 60) {
            final ssid = _extractSsid(r.body);
            if (ssid != null) return ssid;
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return null;
  }

  static Future<bool> _huaweiApply(String host, String user, String pass,
      String? newSsid, String? newPassword) async {
    final client = http.Client();
    try {
      final s = await _huaweiLogin(client, host, user, pass);
      if (s == null) return false;
      // نقاط ضبط WLAN الشائعة (تختلف حسب الموديل) — أفضل جهد.
      final fields = <String, String>{
        if (newSsid != null && newSsid.isNotEmpty) 'x.WlanSsid': newSsid,
        if (newPassword != null && newPassword.isNotEmpty)
          'x.WpaKey': newPassword,
        'x.X_HW_Token': s.token,
      };
      final body = fields.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      for (final ep in const [
        '/html/amp/wlan/set.cgi',
        '/html/network/wlan.cgi',
        '/html/bbsp/wlanbasic/set.cgi',
      ]) {
        try {
          final r = await client.post(Uri.parse('http://$host$ep'),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Cookie': s.cookie,
                'Referer': 'http://$host/',
              },
              body: body).timeout(_timeout);
          if (r.statusCode == 200 || r.statusCode == 302) return true;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return false;
  }

  // ═══════════════ ZTE ═══════════════
  static Future<String?> _zteLoginCookie(
      http.Client client, String host, String user, String pass) async {
    try {
      final r = await client.post(
        Uri.parse('http://$host/'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body:
            'action=login&Username=${Uri.encodeQueryComponent(user)}'
                '&Password=${Uri.encodeQueryComponent(pass)}&Frm_Logintoken=',
      ).timeout(_timeout);
      final c = r.headers['set-cookie'];
      if (c != null) return c;
    } catch (_) {}
    return null;
  }

  static const _zteWlanPages = [
    '/getpage.gch?pid=1002&nextpage=net_wlan_basic_t.gch',
    '/getpage.gch?pid=1002&nextpage=wlan_basic_t.gch',
  ];

  static Future<String?> _zteReadSsid(
      String host, String user, String pass) async {
    final client = http.Client();
    try {
      final cookie = await _zteLoginCookie(client, host, user, pass);
      if (cookie == null) return null;
      for (final page in _zteWlanPages) {
        try {
          final r = await client.get(Uri.parse('http://$host$page'),
              headers: {'Cookie': cookie}).timeout(_timeout);
          if (r.statusCode == 200 && r.body.length > 60) {
            final ssid = _extractSsid(r.body);
            if (ssid != null) return ssid;
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return null;
  }

  static Future<bool> _zteApply(String host, String user, String pass,
      String? newSsid, String? newPassword) async {
    final client = http.Client();
    try {
      final cookie = await _zteLoginCookie(client, host, user, pass);
      if (cookie == null) return false;
      final fields = <String, String>{
        if (newSsid != null && newSsid.isNotEmpty) 'ESSID': newSsid,
        if (newPassword != null && newPassword.isNotEmpty) 'KeyPassphrase': newPassword,
        'IF_ACTION': 'Apply',
      };
      final body = fields.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      for (final ep in const [
        '/common_page/net_wlan_basic_t.gch',
        '/manage_wlan_basic_t.gch',
      ]) {
        try {
          final r = await client.post(Uri.parse('http://$host$ep'),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Cookie': cookie,
              },
              body: body).timeout(_timeout);
          if (r.statusCode == 200 || r.statusCode == 302) return true;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return false;
  }

  // ═══════════════ Tenda (goform، بلا تشفير) ═══════════════
  // راوترات Tenda المنزلية (AC/F/W): دخول نموذجي يضبط كوكي جلسة، ثم قراءة/ضبط
  // WiFi عبر نقاط goform. أفضل جهد عبر نقاط شائعة؛ النجاح يُؤكَّد بإعادة القراءة.
  static Future<String?> _tendaLoginCookie(
      http.Client client, String host, String user, String pass) async {
    // كلمة مرور Tenda تُرسَل غالباً مُرمّزة base64.
    final pwB64 = base64Encode(utf8.encode(pass));
    final bodies = <String>[
      'username=${Uri.encodeQueryComponent(user)}&password=$pwB64',
      'password=$pwB64',
      'username=${Uri.encodeQueryComponent(user)}'
          '&password=${Uri.encodeQueryComponent(pass)}',
    ];
    for (final ep in const ['/login/Auth', '/goform/login']) {
      for (final body in bodies) {
        try {
          final r = await client.post(Uri.parse('http://$host$ep'),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Referer': 'http://$host/',
              },
              body: body).timeout(_timeout);
          final c = r.headers['set-cookie'];
          if (c != null && (r.statusCode == 200 || r.statusCode == 302)) {
            return c.split(';').first;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  static const _tendaWifiGet = [
    '/goform/WifiBasicGet',
    '/goform/getWifiBasic',
    '/goform/GetWifiBasic',
    '/goform/getWifi',
  ];

  static Future<String?> _tendaReadSsid(
      String host, String user, String pass) async {
    final client = http.Client();
    try {
      final cookie = await _tendaLoginCookie(client, host, user, pass);
      final headers = {if (cookie != null) 'Cookie': cookie};
      for (final ep in _tendaWifiGet) {
        try {
          final r = await client
              .get(Uri.parse('http://$host$ep'), headers: headers)
              .timeout(_timeout);
          if (r.statusCode == 200 && r.body.length > 10) {
            // Tenda ترجّع JSON بمفاتيح مثل wifiName/ssid/wl2gName.
            final ssid = _extractSsid(r.body) ??
                _firstMatch(r.body, [
                  RegExp(r'''wifiName["'\s:=]+["']([^"']{1,32})["']''',
                      caseSensitive: false),
                  RegExp(r'''wl2gName["'\s:=]+["']([^"']{1,32})["']''',
                      caseSensitive: false),
                ]);
            if (ssid != null) return ssid;
          }
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return null;
  }

  static Future<bool> _tendaApply(String host, String user, String pass,
      String? newSsid, String? newPassword) async {
    final client = http.Client();
    try {
      final cookie = await _tendaLoginCookie(client, host, user, pass);
      if (cookie == null) return false;
      final fields = <String, String>{
        if (newSsid != null && newSsid.isNotEmpty) 'wifiName': newSsid,
        if (newPassword != null && newPassword.isNotEmpty) 'wrlPwd': newPassword,
        if (newPassword != null && newPassword.isNotEmpty) 'security': 'wpapsk',
      };
      if (fields.isEmpty) return false;
      final body = fields.entries
          .map((e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      for (final ep in const [
        '/goform/WifiBasicSet',
        '/goform/setWifiBasic',
        '/goform/SetWifiBasic',
      ]) {
        try {
          final r = await client.post(Uri.parse('http://$host$ep'),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Cookie': cookie,
                'Referer': 'http://$host/',
              },
              body: body).timeout(_timeout);
          if (r.statusCode == 200 || r.statusCode == 302) return true;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return false;
  }

  static String? _firstMatch(String body, List<RegExp> res) {
    for (final re in res) {
      final m = re.firstMatch(body);
      if (m != null) {
        final v = m.group(1)!.trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }

  // ═══════════════ TP-Link / Mercusys (RSA + AES + stok) ═══════════════
  // فيرموير luci الحديث: مفتاح RSA لكلمة المرور، وإصدار AES يغلّف الحمولة مع
  // توقيع وseq. أفضل جهد لكلا الإصدارين؛ الفشل يبقى صادقاً (لا نجاح كاذب).

  static Future<_TpSession?> _tpLogin(
      http.Client client, String host, String user, String pass) async {
    final loginUrl = 'http://$host/cgi-bin/luci/;stok=/login';
    // 1) مفتاح RSA لكلمة المرور.
    List<String>? pwKey = await _tpGetKeys(client, '$loginUrl?form=keys');
    pwKey ??= await _tpGetKeys(client, '$loginUrl?form=login'); // بعض الفيرموير
    if (pwKey == null) return null;
    final encPw = rsaEncryptHex(pass, pwKey[0], pwKey[1]);

    // 2) إصدار AES (form=auth): مفتاح RSA ثانٍ + seq ⇒ يعني غلاف AES مطلوب.
    final auth = await _tpGetAuth(client, '$loginUrl?form=auth');
    if (auth != null) {
      final aesKey = _randomDigits(16);
      final aesIv = _randomDigits(16);
      final hash = md5Hex('$user$pass');
      final dataStr = 'password=$encPw';
      final encData = aesEncryptBase64(dataStr, aesKey, aesIv);
      final signInput =
          'key=$aesKey&iv=$aesIv&h=$hash&s=${auth.seq + encData.length}';
      final sign = rsaEncryptHex(signInput, auth.nHex, auth.eHex);
      try {
        final r = await client
            .post(Uri.parse('$loginUrl?form=login'),
                headers: {
                  'Content-Type': 'application/x-www-form-urlencoded',
                  'Referer': 'http://$host/',
                },
                body:
                    'sign=$sign&data=${Uri.encodeQueryComponent(encData)}')
            .timeout(_timeout);
        final decoded = _tpMaybeDecrypt(r.body, aesKey, aesIv);
        final stok = _tpExtractStok(decoded);
        if (stok != null) {
          return _TpSession(stok, aesKey: aesKey, aesIv: aesIv, encrypted: true);
        }
      } catch (_) {}
      return null;
    }

    // 3) إصدار RSA فقط (أقدم): POST JSON بكلمة المرور المشفّرة.
    try {
      final r = await client
          .post(Uri.parse('$loginUrl?form=login'),
              headers: {
                'Content-Type': 'application/json',
                'Referer': 'http://$host/',
              },
              body: jsonEncode({
                'method': 'do',
                'login': {'password': encPw}
              }))
          .timeout(_timeout);
      final stok = _tpExtractStok(r.body);
      if (stok != null) return _TpSession(stok, encrypted: false);
    } catch (_) {}
    return null;
  }

  static Future<List<String>?> _tpGetKeys(http.Client c, String url) async {
    try {
      final r = await c.get(Uri.parse(url)).timeout(_timeout);
      final j = jsonDecode(r.body);
      final key = (j is Map) ? ((j['data'] ?? j)['password']) : null;
      if (key is List && key.length >= 2) {
        return [key[0].toString(), key[1].toString()];
      }
    } catch (_) {}
    return null;
  }

  static Future<_TpAuth?> _tpGetAuth(http.Client c, String url) async {
    try {
      final r = await c.get(Uri.parse(url)).timeout(_timeout);
      final j = jsonDecode(r.body);
      final data = (j is Map) ? (j['data'] ?? j) : null;
      if (data is Map) {
        final key = data['key'];
        final seq = data['seq'];
        if (key is List && key.length >= 2 && seq != null) {
          return _TpAuth(
              key[0].toString(), key[1].toString(),
              int.tryParse(seq.toString()) ?? 0);
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _tpMaybeDecrypt(String body, String aesKey, String aesIv) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['data'] is String) {
        return aesDecryptToString(j['data'] as String, aesKey, aesIv);
      }
    } catch (_) {}
    return body;
  }

  static String? _tpExtractStok(String? body) {
    if (body == null) return null;
    final m = RegExp(r'"?stok"?\s*[:=]\s*"([0-9a-fA-F]{8,})"').firstMatch(body);
    return m?.group(1);
  }

  static const _tpWirelessForms = ['wireless_2g', 'wireless_5g', 'wireless_cfg'];

  static Future<String?> _tpReadSsid(
      String host, String user, String pass) async {
    final client = http.Client();
    try {
      final s = await _tpLogin(client, host, user, pass);
      if (s == null) return null;
      for (final form in _tpWirelessForms) {
        final url =
            'http://$host/cgi-bin/luci/;stok=${s.stok}/admin/wireless?form=$form';
        try {
          final r = await client.get(Uri.parse(url)).timeout(_timeout);
          final body = s.encrypted
              ? _tpMaybeDecrypt(r.body, s.aesKey!, s.aesIv!)
              : r.body;
          final ssid = body == null ? null : _extractSsid(body);
          if (ssid != null) return ssid;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return null;
  }

  static Future<bool> _tpApply(String host, String user, String pass,
      String? newSsid, String? newPassword) async {
    final client = http.Client();
    try {
      final s = await _tpLogin(client, host, user, pass);
      if (s == null) return false;
      final cfg = <String, String>{
        if (newSsid != null && newSsid.isNotEmpty) 'ssid': newSsid,
        if (newPassword != null && newPassword.isNotEmpty) 'key': newPassword,
      };
      if (cfg.isEmpty) return false;
      for (final form in _tpWirelessForms) {
        final url =
            'http://$host/cgi-bin/luci/;stok=${s.stok}/admin/wireless?form=$form';
        final payload = jsonEncode({'method': 'set', form: cfg});
        try {
          http.Response r;
          if (s.encrypted) {
            // تغليف AES للحمولة (أفضل جهد لإصدار الغلاف).
            final encData = aesEncryptBase64(payload, s.aesKey!, s.aesIv!);
            r = await client
                .post(Uri.parse(url),
                    headers: {
                      'Content-Type': 'application/x-www-form-urlencoded'
                    },
                    body: 'data=${Uri.encodeQueryComponent(encData)}')
                .timeout(_timeout);
          } else {
            r = await client
                .post(Uri.parse(url),
                    headers: {'Content-Type': 'application/json'},
                    body: payload)
                .timeout(_timeout);
          }
          if (r.statusCode == 200) return true;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
    return false;
  }

  // ─── أدوات تشفير نقيّة (pointycastle + crypto)، قابلة للاختبار بمعزل عن الشبكة ───

  /// MD5 hex لنصّ.
  static String md5Hex(String s) =>
      crypto.md5.convert(utf8.encode(s)).toString();

  /// RSA تشفير (PKCS#1 v1.5) مع التقطيع، مفتاح عام بصيغة hex، الناتج hex.
  static String rsaEncryptHex(String data, String nHex, String eHex) {
    final n = BigInt.parse(nHex, radix: 16);
    final e = BigInt.parse(eHex, radix: 16);
    final engine = pc.PKCS1Encoding(pc.RSAEngine())
      ..init(true,
          pc.PublicKeyParameter<pc.RSAPublicKey>(pc.RSAPublicKey(n, e)));
    final input = Uint8List.fromList(utf8.encode(data));
    final blockSize = engine.inputBlockSize;
    final sb = StringBuffer();
    for (var i = 0; i < input.length; i += blockSize) {
      final end = (i + blockSize < input.length) ? i + blockSize : input.length;
      final chunk = Uint8List.sublistView(input, i, end);
      final out = engine.process(chunk);
      for (final b in out) {
        sb.write(b.toRadixString(16).padLeft(2, '0'));
      }
    }
    return sb.toString();
  }

  /// AES-128-CBC/PKCS7 تشفير (مفتاح/iv نصّان من 16 رقماً)، الناتج base64.
  static String aesEncryptBase64(String data, String key16, String iv16) {
    final cipher = _aesCipher(true, key16, iv16);
    final out = cipher.process(Uint8List.fromList(utf8.encode(data)));
    return base64Encode(out);
  }

  /// AES-128-CBC/PKCS7 فكّ من base64 إلى نصّ.
  static String aesDecryptToString(String b64, String key16, String iv16) {
    final cipher = _aesCipher(false, key16, iv16);
    final out = cipher.process(base64Decode(b64));
    return utf8.decode(out, allowMalformed: true);
  }

  static pc.PaddedBlockCipher _aesCipher(bool forEncrypt, String key16, String iv16) {
    final key = Uint8List.fromList(utf8.encode(key16));
    final iv = Uint8List.fromList(utf8.encode(iv16));
    final params = pc.PaddedBlockCipherParameters<pc.CipherParameters,
            pc.CipherParameters>(
        pc.ParametersWithIV<pc.KeyParameter>(pc.KeyParameter(key), iv), null);
    return pc.PaddedBlockCipherImpl(
        pc.PKCS7Padding(), pc.CBCBlockCipher(pc.AESEngine()))
      ..init(forEncrypt, params);
  }

  static String _randomDigits(int n) {
    final r = Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < n; i++) {
      sb.write(r.nextInt(10));
    }
    return sb.toString();
  }

  // ═══════════════ استخراج SSID الحالي (أفضل جهد) ═══════════════
  static String? _extractSsid(String body) {
    for (final re in [
      RegExp(r'''WlanSsid["'\s=:]+["']([^"']{1,32})["']''', caseSensitive: false),
      RegExp(r'''ESSID["'\s=:]+["']([^"']{1,32})["']''', caseSensitive: false),
      RegExp(r'''["']?ssid["']?\s*[:=]\s*["']([^"']{1,32})["']''',
          caseSensitive: false),
    ]) {
      final m = re.firstMatch(body);
      if (m != null) {
        final v = m.group(1)!.trim();
        if (v.isNotEmpty) return v;
      }
    }
    return null;
  }
}

class _HwSession {
  final String cookie;
  final String token;
  const _HwSession(this.cookie, this.token);
}

/// جلسة TP-Link/Mercusys بعد الدخول (stok + مادّة AES إن كان الغلاف مفعّلاً).
class _TpSession {
  final String stok;
  final bool encrypted;
  final String? aesKey;
  final String? aesIv;
  const _TpSession(this.stok,
      {required this.encrypted, this.aesKey, this.aesIv});
}

/// مفتاح RSA لتغليف AES + seq (إصدار الغلاف المشفّر).
class _TpAuth {
  final String nHex;
  final String eHex;
  final int seq;
  const _TpAuth(this.nHex, this.eHex, this.seq);
}
