/// خدمة قراءة الإشارة الضوئية للفايبر (Rx/Tx Optical Power) — Network Quality
///
/// الميزة الاحترافية: نقرأ قدرة الإشارة الضوئية الحقيقية من الـONU/ONT
/// (Huawei / ZTE) — شيء لا توفّره تطبيقات فحص السرعة العادية.
///
/// معزولة تماماً: تنفّذ تسجيل دخول وقراءة خاصّين بها عبر HTTP ولا تعدّل
/// منطق إعداد الراوتر الإنتاجي (router_adapter_service.dart).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/quality_models.dart';

class OpticalSignalService {
  static const _timeout = Duration(seconds: 6);

  // عناوين ONU/ONT الشائعة في العراق (Huawei/ZTE بالدرجة الأولى).
  static const _candidateIps = [
    '192.168.100.1', // Huawei افتراضي
    '192.168.1.1', // ZTE / Nokia
    '192.168.101.1',
  ];

  // اعتمادات هواوي الشائعة — telecomadmin أولاً لأنه الوحيد الذي يُظهر
  // معلومات البصريات على أغلب موديلات GPON (الحساب admin العادي مقيّد).
  static const _huaweiCreds = [
    ['telecomadmin', 'admintelecom'],
    ['telecomadmin', 'nE7jA%5m'],
    ['telecomadmin', 'telecomadmin'],
    ['root', 'adminHW'],
    ['root', 'admin'],
    ['admin', 'admin'],
    ['admin', 'admin@huawei.com'],
    ['admin', 'admintelecom'],
    ['admin', 'HW_admin'],
    ['admin', 'password'],
    ['epuser', 'userEp'],
    ['superadmin', 'superadmin'],
    ['user', 'user'],
  ];
  static const _zteCreds = [
    ['admin', 'admin'],
    ['user', 'user'],
    ['admin', 'Web@0063'],
    ['admin', 'Zte521'],
  ];

  /// يقرأ الإشارة الضوئية من عنوان جهاز محدّد (يُستخدم من فاحص الأجهزة).
  /// يجرّب هواوي ثم ZTE؛ وإن لم تُعرف الماركة يجرّب الاثنين على أي حال.
  /// [extraCreds] اعتمادات يدوية من المستخدم تُجرَّب أولاً ([user, pass]).
  static Future<OpticalSignalInfo> readAt(String ip,
      {List<List<String>> extraCreds = const []}) async {
    final brand = await _probeBrand(ip);
    if (brand == _Brand.huawei) {
      final r = await _readHuawei(ip, extraCreds);
      if (r.available) return r;
    }
    if (brand == _Brand.zte) {
      final r = await _readZte(ip, extraCreds);
      if (r.available) return r;
    }
    // ماركة غير مؤكّدة — جرّب الاثنين (الأجهزة لا تُظهر دائماً اسم الماركة).
    final h = await _readHuawei(ip, extraCreds);
    if (h.available) return h;
    final z = await _readZte(ip, extraCreds);
    if (z.available) return z;
    return h.error.isNotEmpty ? h : z;
  }

  /// يحاول قراءة الإشارة الضوئية. [gatewayHint] عنوان الراوتر إن عُرف مسبقاً.
  static Future<OpticalSignalInfo> read({String? gatewayHint}) async {
    final ips = <String>{
      if (gatewayHint != null && gatewayHint.isNotEmpty) gatewayHint,
      ..._candidateIps,
    };
    final detectedGw = await _detectGateway();
    if (detectedGw != null) {
      ips.add(detectedGw);
      // أضف عنوان ONU المحتمل على نفس الشبكة (.100.1 / .1)
      final p = detectedGw.split('.');
      if (p.length == 4) {
        ips.add('${p[0]}.${p[1]}.100.1');
        ips.add('${p[0]}.${p[1]}.${p[2]}.1');
      }
    }

    String lastError = '';
    for (final ip in ips) {
      // تحقّق أن العنوان يستجيب أصلاً قبل محاولة الدخول الطويلة.
      if (!await _reachable(ip)) continue;
      final r = await readAt(ip);
      if (r.available) return r;
      if (r.error.isNotEmpty) lastError = r.error;
    }
    return OpticalSignalInfo(
      available: false,
      error: lastError.isNotEmpty
          ? lastError
          : 'تعذّر قراءة الإشارة الضوئية — تأكد من الاتصال المباشر بالـONU (Huawei/ZTE) ومن صحّة اعتماد الدخول.',
    );
  }

  static Future<bool> _reachable(String ip) async {
    try {
      await http
          .get(Uri.parse('http://$ip/'))
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ═══════════════ كشف نوع الجهاز ═══════════════
  static Future<_Brand> _probeBrand(String ip) async {
    try {
      final r =
          await http.get(Uri.parse('http://$ip/')).timeout(const Duration(seconds: 4));
      final body = '${r.body.toLowerCase()} ${r.headers.toString().toLowerCase()}';
      if (body.contains('huawei') ||
          body.contains('hg8') ||
          body.contains('echolife') ||
          body.contains('x.x_hw')) {
        return _Brand.huawei;
      }
      if (body.contains('zte') || body.contains('zxhn') || body.contains('f6')) {
        return _Brand.zte;
      }
    } catch (_) {}
    return _Brand.unknown;
  }

  // صفحات معلومات البصريات في هواوي (تختلف حسب الموديل/الفيرموير).
  static const _huaweiOpticPages = [
    '/html/amp/opticinfo/opticinfo.asp',
    '/html/ssmp/opticinfo/opticinfo.asp',
    '/html/status/opticinfo.asp',
    '/html/status/opticinfo_t.asp',
    '/html/network/opticinfo.asp',
    '/html/bbsp/common/opticinfo.asp',
    '/html/ssmp/accessdev/opticinfo.asp',
  ];

  // ═══════════════ Huawei (HTTP صِرف بإدارة كوكيز الجلسة) ═══════════════
  static Future<OpticalSignalInfo> _readHuawei(String ip,
      [List<List<String>> extraCreds = const []]) async {
    final creds = [...extraCreds, ..._huaweiCreds];
    final tried = <String>[];
    final jar = <String, String>{};
    final client = http.Client();
    bool reachedOptic = false;

    String cookieHeader() =>
        jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    void absorb(Map<String, String> headers) {
      final sc = headers['set-cookie'];
      if (sc == null) return;
      // قد تحوي أكثر من كوكي؛ نقسّم على الفاصلة التي تسبق "اسم=".
      for (final part in sc.split(RegExp(r',(?=[^=;,]+=)'))) {
        final kv = part.split(';').first.trim();
        final i = kv.indexOf('=');
        if (i > 0) jar[kv.substring(0, i).trim()] = kv.substring(i + 1).trim();
      }
    }

    try {
      // 1) GET / لتأسيس كوكي الجلسة الأولي.
      try {
        final r0 = await client.get(Uri.parse('http://$ip/')).timeout(_timeout);
        absorb(r0.headers);
      } catch (_) {}

      for (final c in creds) {
        tried.add(c[0]);

        // 2) توكن مكافحة التزوير.
        String token = '';
        for (final tp in ['/asp/GetRandCount.asp', '/asp/GetRandCount']) {
          try {
            final rt = await client.get(Uri.parse('http://$ip$tp'), headers: {
              'Cookie': cookieHeader(),
              'Referer': 'http://$ip/',
            }).timeout(_timeout);
            absorb(rt.headers);
            final t = rt.body.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
            if (t.isNotEmpty) {
              token = t;
              break;
            }
          } catch (_) {}
        }

        // 3) تسجيل الدخول (login.cgi ثم الجذر كبديل) مع تمرير سلسلة الكوكيز.
        for (final ep in ['/login.cgi', '/']) {
          try {
            final rl = await client.post(
              Uri.parse('http://$ip$ep'),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Cookie': cookieHeader(),
                'Referer': 'http://$ip/',
              },
              body: 'UserName=${c[0]}'
                  '&PassWord=${base64Encode(utf8.encode(c[1]))}'
                  '&Language=english&x.X_HW_Token=$token',
            ).timeout(_timeout);
            absorb(rl.headers);
          } catch (_) {}
        }

        // 4) قراءة البصريات بالجلسة الحالية.
        final got = await _tryHuaweiOptic(ip, cookieHeader(), token);
        if (got != null) return got;

        // 5) اكتشاف رابط البصريات من القوائم وإعادة المحاولة.
        final extra = await _discoverHuaweiOpticPages(ip, cookieHeader(), token);
        for (final page in extra) {
          final g2 = await _tryHuaweiOpticPage(ip, cookieHeader(), token, page);
          if (g2 != null) return g2;
        }

        // هل وصلنا لصفحة بصريات (للتشخيص)؟
        final snip = await _huaweiDiagnosticSnippet(ip, cookieHeader(), token);
        if (snip.isNotEmpty) reachedOptic = true;
      }

      return OpticalSignalInfo(
        available: false,
        source: 'Huawei',
        error: reachedOptic
            ? 'تم الوصول لصفحة البصريات لكن تعذّر تحليلها — استخدم «قراءة متقدمة عبر المتصفح».'
            : 'فشل دخول هواوي بـHTTP (${tried.toSet().join('، ')}). استخدم «قراءة متقدمة عبر المتصفح».',
      );
    } catch (e) {
      debugPrint('[Optical/Huawei] error: $e');
      return const OpticalSignalInfo(available: false, source: 'Huawei');
    } finally {
      client.close();
    }
  }

  /// يمسح قوائم/إطارات هواوي ليجد رابط صفحة البصريات الفعلي (href يحوي optic).
  static Future<List<String>> _discoverHuaweiOpticPages(
      String ip, String? cookie, String token) async {
    final found = <String>{};
    const menuPages = [
      '/',
      '/index.asp',
      '/html/ssmp/common/menu.asp',
      '/html/ssmp/leftmenu.asp',
      '/html/amp/menu.asp',
      '/html/frame/menu.asp',
      '/html/ssmp/accessdev/menu.asp',
    ];
    final headers = {
      if (cookie != null) 'Cookie': cookie,
      if (token.isNotEmpty) 'X-HW-Token': token,
    };
    for (final mp in menuPages) {
      try {
        final r = await http
            .get(Uri.parse('http://$ip$mp'), headers: headers)
            .timeout(_timeout);
        if (r.statusCode != 200) continue;
        // روابط تحوي optic (href="..." أو location/menu arrays)
        final reg = RegExp(r'''["'(]([^"'()\s]*optic[^"'()\s]*\.asp[^"'()\s]*)''',
            caseSensitive: false);
        for (final m in reg.allMatches(r.body)) {
          var p = m.group(1)!;
          if (!p.startsWith('/')) p = '/$p';
          found.add(p);
        }
      } catch (_) {}
    }
    return found.toList();
  }

  static Future<OpticalSignalInfo?> _tryHuaweiOpticPage(
      String ip, String? cookie, String token, String page) async {
    try {
      final rr = await http.get(Uri.parse('http://$ip$page'), headers: {
        if (cookie != null) 'Cookie': cookie,
        if (token.isNotEmpty) 'X-HW-Token': token,
      }).timeout(_timeout);
      if (rr.statusCode == 200 && rr.body.length > 80) {
        final parsed = _parseOptical(rr.body, source: 'Huawei', ip: ip);
        if (parsed.available) return parsed;
      }
    } catch (_) {}
    return null;
  }

  /// يلتقط مقتطفاً من صفحة البصريات حول كلمات القدرة (للتشخيص فقط).
  static Future<String> _huaweiDiagnosticSnippet(
      String ip, String? cookie, String token) async {
    final headers = {
      if (cookie != null) 'Cookie': cookie,
      if (token.isNotEmpty) 'X-HW-Token': token,
    };
    for (final page in _huaweiOpticPages) {
      try {
        final rr = await http
            .get(Uri.parse('http://$ip$page'), headers: headers)
            .timeout(_timeout);
        if (rr.statusCode == 200 && rr.body.length > 80) {
          final low = rr.body.toLowerCase();
          for (final kw in ['power', 'optic', 'dbm', 'voltage']) {
            final i = low.indexOf(kw);
            if (i >= 0) {
              final s = (i - 20).clamp(0, rr.body.length);
              final e = (i + 80).clamp(0, rr.body.length);
              return rr.body
                  .substring(s, e)
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
            }
          }
          return '($page طوله ${rr.body.length} بلا كلمات قدرة)';
        }
      } catch (_) {}
    }
    return '';
  }

  /// يحاول قراءة أي صفحة بصريات بجلسة معيّنة؛ يُعيد النتيجة أو null.
  static Future<OpticalSignalInfo?> _tryHuaweiOptic(
      String ip, String? cookie, String? token) async {
    final headers = {
      if (cookie != null) 'Cookie': cookie,
      if (token != null && token.isNotEmpty) 'X-HW-Token': token,
      'Referer': 'http://$ip/index.asp',
    };
    for (final page in _huaweiOpticPages) {
      try {
        final rr = await http
            .get(Uri.parse('http://$ip$page'), headers: headers)
            .timeout(_timeout);
        if (rr.statusCode == 200 && rr.body.length > 80) {
          final parsed = _parseOptical(rr.body, source: 'Huawei', ip: ip);
          if (parsed.available) return parsed;
        }
      } catch (_) {}
    }
    return null;
  }

  // ═══════════════ ZTE ═══════════════
  static Future<OpticalSignalInfo> _readZte(String ip,
      [List<List<String>> extraCreds = const []]) async {
    String? cookie;
    try {
      for (final c in [...extraCreds, ..._zteCreds]) {
        final r = await http.post(
          Uri.parse('http://$ip/'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: 'action=login&Username=${c[0]}&Password=${c[1]}&Frm_Logintoken=',
        ).timeout(_timeout);
        final nc = r.headers['set-cookie'];
        if (nc != null) cookie = nc;
        if (r.statusCode == 200 || r.statusCode == 302) break;
      }
      final headers = {if (cookie != null) 'Cookie': cookie};
      const opticPages = [
        '/getpage.gch?pid=1002&nextpage=pon_status_t.gch',
        '/getpage.gch?pid=1002&nextpage=status_pon_t.gch',
        '/getpage.gch?pid=1002&nextpage=net_ponstatus_t.gch',
      ];
      for (final page in opticPages) {
        final rr =
            await http.get(Uri.parse('http://$ip$page'), headers: headers).timeout(_timeout);
        if (rr.statusCode == 200 && rr.body.length > 80) {
          final parsed = _parseOptical(rr.body, source: 'ZTE', ip: ip);
          if (parsed.available) return parsed;
        }
      }
    } catch (e) {
      debugPrint('[Optical/ZTE] error: $e');
    }
    return const OpticalSignalInfo(available: false, source: 'ZTE');
  }

  /// تحليل عامّ لمحتوى صفحة بصريات (يُستخدم من قارئ المتصفح المدمج).
  static OpticalSignalInfo parseBody(String body,
          {String source = 'WebView', String ip = ''}) =>
      _parseOptical(body, source: source, ip: ip);

  /// مسارات صفحات البصريات (لاستخدام قارئ المتصفح المدمج عبر XHR).
  static List<String> get opticPagePaths => _huaweiOpticPages;

  // ═══════════════ تحليل القيم ═══════════════
  static OpticalSignalInfo _parseOptical(String body,
      {required String source, required String ip}) {
    // 0) فكّ ترميز \xHH — هواوي تُرمّز '-'=\x2d و'.'=\x2e ومسافة=\x20.
    final decoded = _unescapeHex(body);

    // 1) تنسيق هواوي الدقيق: new stOpticInfo(domain, Tx, Rx, V, Temp, Bias, ...)
    final hw = _parseHuaweiStOptic(decoded, source, ip);
    if (hw != null && hw.available) return hw;

    // 2) محلّل عام بالمفاتيح (لموديلات/ماركات أخرى).
    double? rx = _findSigned(decoded, [
      'receivepowervalue', 'receivepower', 'revopticpower', 'rxopticalpower',
      'opticalrxpower', 'receiveopticalpower', 'rxpower', 'rx_power',
      'rx power', 'rx optical'
    ]);
    double? tx = _findSigned(decoded, [
      'sendpowervalue', 'sendpower', 'transopticpower', 'launchpower',
      'txopticalpower', 'opticaltxpower', 'transmitopticalpower',
      'transmitpower', 'txpower', 'tx_power', 'tx power', 'tx optical'
    ]);
    final voltage =
        _findSigned(decoded, ['voltagevalue', 'supplyvoltage', 'voltage']);
    final bias = _findSigned(decoded,
        ['biasvalue', 'biascurrent', 'bias_current', 'biascurr', 'bias']);
    final temp =
        _findSigned(decoded, ['tempvalue', 'temperature', 'temp']);

    rx = _normalizeDbm(rx);
    tx = _normalizeDbm(tx);

    final available = rx != null || tx != null;
    return OpticalSignalInfo(
      available: available,
      rxPowerDbm: rx,
      txPowerDbm: tx,
      voltage: voltage,
      biasCurrentMa: bias,
      temperatureC: temp,
      source: source,
      onuModel: ip,
    );
  }

  /// يفكّ تسلسلات \xHH إلى رموزها (هواوي تُرمّز الأرقام السالبة والنقاط هكذا).
  /// يتعامل مع باكسلاش مفرد أو مزدوج (حسب ترميز WebView عند النقل).
  static String _unescapeHex(String s) {
    if (!s.contains('x')) return s;
    return s.replaceAllMapped(RegExp(r'\\{1,2}x([0-9A-Fa-f]{2})'), (m) {
      final code = int.parse(m.group(1)!, radix: 16);
      return String.fromCharCode(code);
    });
  }

  /// محلّل تنسيق هواوي stOpticInfo الموضعي (الأدق لـHG8xxx/EG8xxx).
  /// ترتيب الوسائط: domain, transOpticPower(Tx), revOpticPower(Rx),
  /// voltage(mV), temperature(°C), bias(mA), ...
  static OpticalSignalInfo? _parseHuaweiStOptic(
      String decoded, String source, String ip) {
    final re = RegExp(r'new\s+stOpticInfo\(([^)]*)\)');
    for (final m in re.allMatches(decoded)) {
      final args = _splitArgs(m.group(1)!);
      if (args.length < 3) continue;
      final tx = _num(args[1]);
      final rx = _num(args[2]);
      if (tx == null && rx == null) continue; // استدعاء افتراضي بقيم '--'
      final volt = args.length > 3 ? _num(args[3]) : null;
      final temp = args.length > 4 ? _num(args[4]) : null;
      final bias = args.length > 5 ? _num(args[5]) : null;
      return OpticalSignalInfo(
        available: true,
        rxPowerDbm: rx,
        txPowerDbm: tx,
        // الفولتية بالـmV ⇒ ÷1000 (مثل 3237 → 3.24V).
        voltage: (volt != null && volt > 100) ? volt / 1000.0 : volt,
        temperatureC: temp,
        biasCurrentMa: bias,
        source: source,
        onuModel: ip,
      );
    }
    return null;
  }

  /// يقسّم وسائط استدعاء دالة إلى قيم نصّية (مع إزالة علامات الاقتباس).
  static List<String> _splitArgs(String s) {
    return s.split(',').map((e) {
      var v = e.trim();
      if (v.startsWith('"') || v.startsWith("'")) v = v.substring(1);
      if (v.endsWith('"') || v.endsWith("'")) v = v.substring(0, v.length - 1);
      return v.trim();
    }).toList();
  }

  /// يستخرج رقماً من نصّ قد يحوي مسافات أو '--' أو إشارة.
  static double? _num(String s) {
    final t = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
    if (t.isEmpty || t == '-' || t == '--' || t == '.' || t == '-.') {
      return null;
    }
    return double.tryParse(t);
  }

  /// يبحث عن أول رقم عشري مُشار (موجب/سالب) قرب أحد المفاتيح.
  static double? _findSigned(String body, List<String> keys) {
    final lower = body.toLowerCase();
    for (final key in keys) {
      var idx = 0;
      while (true) {
        final pos = lower.indexOf(key, idx);
        if (pos < 0) break;
        // ابحث عن رقم ضمن 40 حرفاً بعد المفتاح
        final window = body.substring(
            pos, (pos + key.length + 40).clamp(0, body.length));
        final m = RegExp(r'(-?\d+(?:\.\d+)?)').firstMatch(
            window.substring(key.length.clamp(0, window.length)));
        if (m != null) {
          final v = double.tryParse(m.group(1)!);
          if (v != null && v != 0) return v;
        }
        idx = pos + key.length;
      }
    }
    return null;
  }

  /// تحويل القيم الخام إلى dBm منطقية (النطاق المتوقّع تقريباً -40..+10).
  static double? _normalizeDbm(double? v) {
    if (v == null) return null;
    var x = v;
    // قيم ضخمة ⇒ مقسومة (×100 أو ×1000)
    while (x.abs() > 60) {
      x = x / 10;
    }
    return double.parse(x.toStringAsFixed(2));
  }

  // ═══════════════ كشف البوّابة ═══════════════
  static Future<String?> _detectGateway() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('ipconfig', [],
            stdoutEncoding: const SystemEncoding());
        for (final line in r.stdout.toString().split('\n')) {
          if (line.contains('Default Gateway') && !line.trim().endsWith(':')) {
            final m = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
                .firstMatch(line);
            if (m != null && m.group(1) != '0.0.0.0') return m.group(1);
          }
        }
      } else {
        final r = await Process.run('ip', ['route', 'show', 'default']);
        final m = RegExp(r'via\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
            .firstMatch(r.stdout.toString());
        if (m != null) return m.group(1);
      }
    } catch (_) {}
    return null;
  }
}

enum _Brand { huawei, zte, unknown }
