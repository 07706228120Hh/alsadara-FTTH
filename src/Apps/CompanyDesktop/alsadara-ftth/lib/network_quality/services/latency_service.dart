/// خدمة قياس زمن الاستجابة والتذبذب وفقدان الحزم وDNS — Network Quality
///
/// تعمل على ويندوز وأندرويد عبر أمر ping الأصلي للنظام + قياس DNS عبر
/// InternetAddress.lookup. لا تعتمد على أي حزمة خارجية.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

class LatencySample {
  final List<double> rttsMs; // قيم زمن الاستجابة الناجحة
  final int sent;
  final int received;

  const LatencySample({required this.rttsMs, required this.sent, required this.received});

  double? get avg => rttsMs.isEmpty ? null : rttsMs.reduce((a, b) => a + b) / rttsMs.length;
  double? get minVal => rttsMs.isEmpty ? null : rttsMs.reduce(min);
  double? get maxVal => rttsMs.isEmpty ? null : rttsMs.reduce(max);

  /// التذبذب = متوسط الفرق المطلق بين القياسات المتتالية.
  double? get jitter {
    if (rttsMs.length < 2) return null;
    double sum = 0;
    for (var i = 1; i < rttsMs.length; i++) {
      sum += (rttsMs[i] - rttsMs[i - 1]).abs();
    }
    return sum / (rttsMs.length - 1);
  }

  double get packetLossPercent =>
      sent == 0 ? 0 : ((sent - received) / sent * 100).clamp(0, 100);
}

class LatencyService {
  /// يقيس ping/jitter/loss بإرسال [count] نبضات إلى [host].
  static Future<LatencySample> measurePing({
    String host = '8.8.8.8',
    int count = 15,
  }) async {
    try {
      final args = Platform.isWindows
          ? ['-n', '$count', '-w', '1500', host]
          : ['-c', '$count', '-W', '2', host];
      final r = await Process.run('ping', args,
              stdoutEncoding: const SystemEncoding())
          .timeout(Duration(seconds: count * 2 + 10));
      final out = r.stdout.toString();
      final rtts = _parseRtts(out);
      final received = rtts.length;
      // عدد المُرسَل: نثق بـcount إلا إن ذكر الخرج خلاف ذلك
      return LatencySample(rttsMs: rtts, sent: count, received: received);
    } catch (e) {
      debugPrint('[Latency] ping error: $e');
      // بديل: قياس عبر TCP connect عند تعذّر ICMP (بعض الأجهزة تمنع ping).
      return _tcpFallback(host);
    }
  }

  static List<double> _parseRtts(String out) {
    final rtts = <double>[];
    // ويندوز: time=14ms / time<1ms  | لينكس/أندرويد: time=14.2 ms
    final reg = RegExp(r'time[=<]\s*([\d.]+)\s*ms', caseSensitive: false);
    for (final m in reg.allMatches(out)) {
      final v = double.tryParse(m.group(1)!);
      if (v != null) rtts.add(v);
    }
    // التعامل مع "time<1ms" التي يلتقطها الريجيكس كـ1 (تقريب مقبول)
    return rtts;
  }

  /// قياس احتياطي عبر TCP connect (المنفذ 443) عند تعذّر ping.
  static Future<LatencySample> _tcpFallback(String host) async {
    final rtts = <double>[];
    const attempts = 8;
    final target = host == '8.8.8.8' ? 'google.com' : host;
    for (var i = 0; i < attempts; i++) {
      final sw = Stopwatch()..start();
      try {
        final s = await Socket.connect(target, 443,
            timeout: const Duration(seconds: 3));
        sw.stop();
        rtts.add(sw.elapsedMicroseconds / 1000.0);
        s.destroy();
      } catch (_) {
        sw.stop();
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
    return LatencySample(rttsMs: rtts, sent: attempts, received: rtts.length);
  }

  /// يقيس زمن استجابة DNS بحلّ عدّة أسماء وأخذ المتوسّط.
  static Future<double?> measureDns({
    List<String> hosts = const ['google.com', 'cloudflare.com', 'youtube.com'],
  }) async {
    final times = <double>[];
    for (final h in hosts) {
      final sw = Stopwatch()..start();
      try {
        final r = await InternetAddress.lookup(h)
            .timeout(const Duration(seconds: 4));
        sw.stop();
        if (r.isNotEmpty) times.add(sw.elapsedMicroseconds / 1000.0);
      } catch (_) {
        sw.stop();
      }
    }
    if (times.isEmpty) return null;
    return times.reduce((a, b) => a + b) / times.length;
  }

  /// تتبّع المسار (best-effort) — قد لا يتوفّر أمر tracert/traceroute على كل جهاز.
  static Future<List<String>> traceroute({String host = '8.8.8.8'}) async {
    try {
      final cmd = Platform.isWindows ? 'tracert' : 'traceroute';
      final args = Platform.isWindows
          ? ['-d', '-h', '15', '-w', '1000', host]
          : ['-n', '-m', '15', '-w', '2', host];
      final r = await Process.run(cmd, args,
              stdoutEncoding: const SystemEncoding())
          .timeout(const Duration(seconds: 35));
      return r.stdout
          .toString()
          .split('\n')
          .map((e) => e.trimRight())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[Latency] traceroute unavailable: $e');
      return const [];
    }
  }

  /// فحص سريع لوجود إنترنت فعلي.
  static Future<bool> hasInternet() async {
    try {
      final r = await InternetAddress.lookup('cloudflare.com')
          .timeout(const Duration(seconds: 4));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
