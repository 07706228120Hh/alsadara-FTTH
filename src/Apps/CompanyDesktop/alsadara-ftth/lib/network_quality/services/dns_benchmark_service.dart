/// خدمة اختبار ومقارنة مزوّدات DNS — Network Quality (فحص متقدّم)
///
/// ترسل استعلام DNS خام (A-record) عبر UDP/53 لكل مزوّد بـ RawDatagramSocket
/// (بلا أي حزمة خارجية)، تقيس زمن الاستجابة (RTT) على عدّة نطاقات وتأخذ المتوسط،
/// وترتّب المزوّدات من الأسرع للأبطأ. تعمل على ويندوز وأندرويد.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// مزوّد DNS (اسم + عنوان IP).
class DnsProvider {
  final String name;
  final String ip;
  const DnsProvider(this.name, this.ip);
}

/// نتيجة اختبار مزوّد واحد.
class DnsResult {
  final DnsProvider provider;
  final double? avgMs; // متوسط زمن الاستجابة (null = غير متاح)
  final int ok; // عدد الاستعلامات الناجحة
  final int total; // إجمالي الاستعلامات
  const DnsResult({
    required this.provider,
    required this.avgMs,
    required this.ok,
    required this.total,
  });

  bool get reachable => avgMs != null && ok > 0;
}

class DnsBenchmarkService {
  /// المزوّدات الافتراضية المختبَرة.
  static const defaultProviders = <DnsProvider>[
    DnsProvider('Cloudflare', '1.1.1.1'),
    DnsProvider('Google', '8.8.8.8'),
    DnsProvider('Quad9', '9.9.9.9'),
    DnsProvider('OpenDNS', '208.67.222.222'),
  ];

  static const _defaultDomains = ['example.com', 'google.com', 'wikipedia.org'];

  /// يختبر كل المزوّدات بالتوازي ويعيد النتائج مرتّبة (الأسرع أولاً ثم غير المتاح).
  static Future<List<DnsResult>> run({
    List<DnsProvider> providers = defaultProviders,
    List<String> domains = _defaultDomains,
    Duration perQueryTimeout = const Duration(seconds: 2),
  }) async {
    final results = await Future.wait(providers.map(
        (p) => _benchProvider(p, domains, perQueryTimeout)));
    results.sort((a, b) {
      if (a.reachable && b.reachable) return a.avgMs!.compareTo(b.avgMs!);
      if (a.reachable) return -1;
      if (b.reachable) return 1;
      return 0;
    });
    return results;
  }

  static Future<DnsResult> _benchProvider(
      DnsProvider p, List<String> domains, Duration timeout) async {
    final times = <double>[];
    for (final d in domains) {
      final ms = await _query(p.ip, d, timeout);
      if (ms != null) times.add(ms);
    }
    final avg =
        times.isEmpty ? null : times.reduce((a, b) => a + b) / times.length;
    return DnsResult(
        provider: p, avgMs: avg, ok: times.length, total: domains.length);
  }

  /// استعلام A-record واحد عبر UDP/53 وقياس RTT (أو null عند الفشل/المهلة).
  static Future<double?> _query(
      String serverIp, String domain, Duration timeout) async {
    RawDatagramSocket? sock;
    StreamSubscription? sub;
    try {
      final server = InternetAddress.tryParse(serverIp);
      if (server == null) return null;
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final id = Random().nextInt(0xFFFF);
      final packet = _buildQuery(id, domain);
      final completer = Completer<double?>();
      final sw = Stopwatch()..start();
      sub = sock.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = sock!.receive();
        if (dg == null) return;
        final data = dg.data;
        if (data.length >= 2 &&
            data[0] == ((id >> 8) & 0xFF) &&
            data[1] == (id & 0xFF)) {
          if (!completer.isCompleted) {
            completer.complete(sw.elapsedMicroseconds / 1000.0);
          }
        }
      });
      sock.send(packet, server, 53);
      return await completer.future
          .timeout(timeout, onTimeout: () => null);
    } catch (e) {
      debugPrint('[DNS] query error ($serverIp): $e');
      return null;
    } finally {
      await sub?.cancel();
      sock?.close();
    }
  }

  /// يبني حزمة استعلام DNS قياسية (A-record، recursion desired).
  static Uint8List _buildQuery(int id, String domain) {
    final b = BytesBuilder();
    // الترويسة.
    b.addByte((id >> 8) & 0xFF);
    b.addByte(id & 0xFF);
    b.addByte(0x01); // RD = 1
    b.addByte(0x00);
    b.addByte(0x00);
    b.addByte(0x01); // QDCOUNT = 1
    b.addByte(0x00);
    b.addByte(0x00); // ANCOUNT = 0
    b.addByte(0x00);
    b.addByte(0x00); // NSCOUNT = 0
    b.addByte(0x00);
    b.addByte(0x00); // ARCOUNT = 0
    // السؤال: QNAME كتسلسل تسميات.
    for (final label in domain.split('.')) {
      final bytes = label.codeUnits;
      b.addByte(bytes.length & 0x3F);
      b.add(bytes);
    }
    b.addByte(0x00); // نهاية الاسم
    b.addByte(0x00);
    b.addByte(0x01); // QTYPE = A
    b.addByte(0x00);
    b.addByte(0x01); // QCLASS = IN
    return b.toBytes();
  }
}
