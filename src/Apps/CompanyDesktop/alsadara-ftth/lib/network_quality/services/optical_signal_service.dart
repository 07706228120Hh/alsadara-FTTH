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

  // اعتمادات افتراضية شائعة لقراءة المعلومات فقط (قراءة لا كتابة).
  static const _huaweiCreds = [
    ['telecomadmin', 'admintelecom'],
    ['root', 'adminHW'],
    ['admin', 'admin'],
  ];
  static const _zteCreds = [
    ['admin', 'admin'],
    ['user', 'user'],
  ];

  /// يحاول قراءة الإشارة الضوئية. [gatewayHint] عنوان الراوتر إن عُرف مسبقاً.
  static Future<OpticalSignalInfo> read({String? gatewayHint}) async {
    final ips = <String>{
      if (gatewayHint != null && gatewayHint.isNotEmpty) gatewayHint,
      ..._candidateIps,
    };
    final detectedGw = await _detectGateway();
    if (detectedGw != null) ips.add(detectedGw);

    for (final ip in ips) {
      final brand = await _probeBrand(ip);
      if (brand == _Brand.huawei) {
        final r = await _readHuawei(ip);
        if (r.available) return r;
      } else if (brand == _Brand.zte) {
        final r = await _readZte(ip);
        if (r.available) return r;
      }
    }
    return const OpticalSignalInfo(
      available: false,
      error: 'تعذّر قراءة الإشارة الضوئية — تأكد من الاتصال المباشر بالـONU (Huawei/ZTE).',
    );
  }

  // ═══════════════ كشف نوع الجهاز ═══════════════
  static Future<_Brand> _probeBrand(String ip) async {
    try {
      final r =
          await http.get(Uri.parse('http://$ip/')).timeout(const Duration(seconds: 4));
      final body = '${r.body.toLowerCase()} ${r.headers.toString().toLowerCase()}';
      if (body.contains('huawei') ||
          body.contains('hg8') ||
          body.contains('echolife')) {
        return _Brand.huawei;
      }
      if (body.contains('zte') || body.contains('zxhn') || body.contains('f6')) {
        return _Brand.zte;
      }
    } catch (_) {}
    return _Brand.unknown;
  }

  // ═══════════════ Huawei ═══════════════
  static Future<OpticalSignalInfo> _readHuawei(String ip) async {
    String? cookie;
    String? token;
    try {
      // 1. جلب التوكن
      final r1 = await http
          .get(Uri.parse('http://$ip/asp/GetRandCount'))
          .timeout(_timeout);
      cookie = r1.headers['set-cookie'];
      token = r1.body.trim();

      // 2. تسجيل الدخول (قراءة فقط)
      for (final c in _huaweiCreds) {
        final r2 = await http.post(
          Uri.parse('http://$ip/login.cgi'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            if (cookie != null) 'Cookie': cookie,
            'Referer': 'http://$ip/',
          },
          body:
              'UserName=${c[0]}&PassWord=${base64Encode(utf8.encode(c[1]))}&x.X_HW_Token=$token',
        ).timeout(_timeout);
        final nc = r2.headers['set-cookie'];
        if (nc != null) cookie = nc;
        if (r2.statusCode == 200 || r2.statusCode == 302) break;
      }

      // 3. قراءة صفحات المعلومات الضوئية
      final headers = {
        if (cookie != null) 'Cookie': cookie,
        'X-HW-Token': token,
      };
      const opticPages = [
        '/html/amp/opticinfo/opticinfo.asp',
        '/html/ssmp/opticinfo/opticinfo.asp',
        '/html/status/opticinfo_t.asp',
      ];
      for (final page in opticPages) {
        final rr =
            await http.get(Uri.parse('http://$ip$page'), headers: headers).timeout(_timeout);
        if (rr.statusCode == 200 && rr.body.length > 80) {
          final parsed = _parseOptical(rr.body, source: 'Huawei', ip: ip);
          if (parsed.available) return parsed;
        }
      }
    } catch (e) {
      debugPrint('[Optical/Huawei] error: $e');
    }
    return const OpticalSignalInfo(available: false, source: 'Huawei');
  }

  // ═══════════════ ZTE ═══════════════
  static Future<OpticalSignalInfo> _readZte(String ip) async {
    String? cookie;
    try {
      for (final c in _zteCreds) {
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

  // ═══════════════ تحليل القيم ═══════════════
  static OpticalSignalInfo _parseOptical(String body,
      {required String source, required String ip}) {
    double? rx = _findSigned(body, [
      'rxpower', 'rx_power', 'rx power', 'opticalrxpower', 'rxopticalpower',
      'receiveopticalpower', 'rx'
    ]);
    double? tx = _findSigned(body, [
      'txpower', 'tx_power', 'tx power', 'opticaltxpower', 'txopticalpower',
      'transmitopticalpower', 'tx'
    ]);
    final voltage = _findSigned(body, ['voltage', 'supplyvoltage']);
    final bias = _findSigned(body, ['biascurrent', 'bias_current', 'bias']);
    final temp = _findSigned(body, ['temperature', 'temp']);

    // تطبيع: بعض الأجهزة تُرجع dBm×100 أو ×1000 (مثل -1523 تعني -15.23).
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
