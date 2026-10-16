/// محلّل قنوات WiFi واختيار أفضل قناة — Network Quality (فحص متقدّم)
///
/// ويندوز: يمسح الشبكات المجاورة عبر `netsh wlan show networks mode=bssid`
/// (محلّل متين ضد التعريب: يلتقط BSSID عبر MAC، والإشارة عبر %، والقناة عبر
/// تسميات/أرقام). أندرويد/iOS: غير مدعوم (رسالة واضحة، بلا حزم).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// شبكة مجاورة مكتشَفة في الجو.
class NearbyNetwork {
  final String ssid;
  final String bssid;
  final int channel;
  final String band; // 2.4GHz / 5GHz / 6GHz
  final int? signalPercent;

  const NearbyNetwork({
    required this.ssid,
    required this.bssid,
    required this.channel,
    required this.band,
    this.signalPercent,
  });

  bool get is24 => band == '2.4GHz';
  bool get is5 => band == '5GHz';
}

/// توصية بأفضل قناة لنطاق معيّن.
class ChannelRecommendation {
  final String band;
  final int? bestChannel;
  final String note;
  const ChannelRecommendation(
      {required this.band, required this.bestChannel, required this.note});
}

/// نتيجة المسح الكاملة.
class WifiScanResult {
  final bool supported;
  final String message; // رسالة المنصّة غير المدعومة أو خطأ
  final List<NearbyNetwork> networks;
  final ChannelRecommendation? rec24;
  final ChannelRecommendation? rec5;

  const WifiScanResult({
    required this.supported,
    this.message = '',
    this.networks = const [],
    this.rec24,
    this.rec5,
  });

  factory WifiScanResult.unsupported(String message) =>
      WifiScanResult(supported: false, message: message);
}

class WifiChannelAnalyzerService {
  /// قنوات 2.4GHz غير المتداخلة المرشّحة.
  static const nonOverlap24 = [1, 6, 11];

  /// قنوات 5GHz الشائعة (غير DFS أولاً).
  static const common5 = [36, 40, 44, 48, 149, 153, 157, 161, 165];

  /// نطاق DFS في 5GHz (قد تسبّب انقطاعاً عند كشف الرادار).
  static bool isDfs(int ch) => ch >= 52 && ch <= 144;

  static Future<WifiScanResult> scan() async {
    if (Platform.isWindows) {
      try {
        final r = await Process.run(
          'netsh',
          ['wlan', 'show', 'networks', 'mode=bssid'],
          stdoutEncoding: const SystemEncoding(),
        ).timeout(const Duration(seconds: 10));
        final nets = parseNetsh(r.stdout.toString());
        return buildResult(nets);
      } catch (e) {
        debugPrint('[WifiCh] scan error: $e');
        return WifiScanResult.unsupported('تعذّر مسح الشبكات المجاورة: $e');
      }
    }
    if (Platform.isAndroid) {
      return WifiScanResult.unsupported(
          'مسح الشبكات المجاورة يتطلّب نسخة لاحقة على أندرويد.');
    }
    if (Platform.isIOS) {
      return WifiScanResult.unsupported(
          'مسح الشبكات المجاورة غير متاح على iOS (قيود النظام).');
    }
    return WifiScanResult.unsupported('غير مدعوم على هذه المنصّة.');
  }

  /// يبني النتيجة الكاملة مع التوصيات من قائمة شبكات (يُستخدم أيضاً في الاختبار).
  static WifiScanResult buildResult(List<NearbyNetwork> nets) {
    return WifiScanResult(
      supported: true,
      networks: nets,
      rec24: recommend(nets, band24: true),
      rec5: recommend(nets, band24: false),
    );
  }

  // ═══════════════ محلّل netsh (متين ضد التعريب) ═══════════════

  static final _macReg = RegExp(
      r'([0-9a-fA-F]{2}[:-][0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){4})');
  static final _ssidHeaderReg = RegExp(
      r'^\s*(?:SSID|اسم الشبكة|الشبكة)\s+\d+\s*:\s*(.*)$',
      caseSensitive: false);
  static final _pctReg = RegExp(r'(\d{1,3})\s*%');
  static final _intReg = RegExp(r'(\d{1,3})');

  static List<NearbyNetwork> parseNetsh(String out) {
    final nets = <NearbyNetwork>[];
    var currentSsid = '';
    // الحقول المعلّقة لآخر BSSID.
    String? bssid;
    int? signal;
    int? channel;
    String band = '';

    void commit() {
      if (bssid != null && channel != null) {
        nets.add(NearbyNetwork(
          ssid: currentSsid.isEmpty ? '(شبكة مخفية)' : currentSsid,
          bssid: bssid!,
          channel: channel!,
          band: band.isNotEmpty ? band : _bandFromChannel(channel!),
          signalPercent: signal,
        ));
      }
      bssid = null;
      signal = null;
      channel = null;
      band = '';
    }

    for (final raw in out.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) continue;

      // رأس SSID جديد.
      final sm = _ssidHeaderReg.firstMatch(line);
      if (sm != null && _macReg.firstMatch(line) == null) {
        commit();
        currentSsid = sm.group(1)!.trim();
        continue;
      }

      final idx = line.indexOf(':');
      final key = idx >= 0 ? line.substring(0, idx).trim().toLowerCase() : '';
      final val = idx >= 0 ? line.substring(idx + 1).trim() : line.trim();

      // سطر BSSID (مرساة MAC موثوقة بصرف النظر عن اللغة).
      final mac = _macReg.firstMatch(line);
      final looksBssid = key.contains('bssid') || key.contains('معرف');
      if (mac != null && (looksBssid || key.isEmpty || key.contains('bssid'))) {
        commit();
        bssid = mac.group(1)!.toLowerCase().replaceAll('-', ':');
        continue;
      }

      // النطاق (Band) — يحتوي GHz/جيجا.
      final lower = line.toLowerCase();
      if (key.contains('band') ||
          key.contains('النطاق') ||
          lower.contains('ghz') ||
          line.contains('جيجا') ||
          line.contains('غيغا')) {
        if (val.contains('6')) {
          band = '6GHz';
        } else if (val.contains('5')) {
          band = '5GHz';
        } else if (val.contains('2')) {
          band = '2.4GHz';
        }
        // لا continue: قد يكون نفس السطر لا يحمل غير النطاق.
        continue;
      }

      // الإشارة (%).
      if (key.contains('signal') ||
          key.contains('الإشارة') ||
          key.contains('اشارة') ||
          _pctReg.hasMatch(line)) {
        final pm = _pctReg.firstMatch(line);
        if (pm != null) {
          signal = int.tryParse(pm.group(1)!);
          continue;
        }
      }

      // القناة.
      if (key.contains('channel') ||
          key.contains('القناة') ||
          key.contains('قناة')) {
        final cm = _intReg.firstMatch(val);
        if (cm != null) channel = int.tryParse(cm.group(1)!);
        continue;
      }
    }
    commit();
    return nets;
  }

  static String _bandFromChannel(int ch) {
    if (ch >= 1 && ch <= 14) return '2.4GHz';
    if (ch >= 32 && ch <= 177) return '5GHz';
    return ch > 14 ? '5GHz' : '2.4GHz';
  }

  // ═══════════════ التحليل والتوصية ═══════════════

  /// حِمل كل قناة (تداخل مرجّح بالإشارة) للنطاق المطلوب — للعرض والتوصية.
  static Map<int, double> channelLoads(List<NearbyNetwork> nets,
      {required bool band24}) {
    final loads = <int, double>{};
    final subset = nets.where((n) => band24 ? n.is24 : n.is5).toList();
    final channels = band24
        ? List<int>.generate(13, (i) => i + 1)
        : _channels5(subset);
    for (final c in channels) {
      double load = 0;
      for (final n in subset) {
        final w = (n.signalPercent ?? 50).toDouble();
        if (band24) {
          final d = (n.channel - c).abs();
          final overlap = ((5 - d) / 5).clamp(0.0, 1.0); // تداخل جزئي ±4
          load += w * overlap;
        } else {
          // 5GHz: 20MHz غير متداخلة غالباً؛ نحسب الإشغال المباشر + جوار بسيط.
          if (n.channel == c) {
            load += w;
          } else if ((n.channel - c).abs() <= 4) {
            load += w * 0.25;
          }
        }
      }
      loads[c] = load;
    }
    return loads;
  }

  static List<int> _channels5(List<NearbyNetwork> subset) {
    final set = <int>{...common5};
    for (final n in subset) {
      set.add(n.channel);
    }
    final list = set.toList()..sort();
    return list;
  }

  /// يوصي بأفضل قناة للنطاق (أقلّ حِمل)، مع ملاحظة عربية موضّحة.
  static ChannelRecommendation recommend(List<NearbyNetwork> nets,
      {required bool band24}) {
    final band = band24 ? '2.4GHz' : '5GHz';
    final subset = nets.where((n) => band24 ? n.is24 : n.is5).toList();
    if (subset.isEmpty) {
      return ChannelRecommendation(
        band: band,
        bestChannel: band24 ? 1 : 36,
        note: band24
            ? 'لا شبكات على 2.4GHz — أي قناة من 1/6/11 ممتازة.'
            : 'لا شبكات على 5GHz — أي قناة ممتازة (ابدأ بـ36).',
      );
    }
    final loads = channelLoads(nets, band24: band24);
    final candidates = band24 ? nonOverlap24 : _preferredNonDfs5(loads);
    int? best;
    double bestLoad = double.infinity;
    for (final c in candidates) {
      final l = loads[c] ?? 0;
      if (l < bestLoad) {
        bestLoad = l;
        best = c;
      }
    }
    final count = subset.length;
    final note = band24
        ? 'القناة $best أقلّ تداخلاً بين (1/6/11) — $count شبكة مجاورة على 2.4GHz.'
        : (best != null && isDfs(best)
            ? 'القناة $best الأقلّ ازدحاماً (ضمن DFS — قد تنقطع عند كشف الرادار).'
            : 'القناة $best الأقلّ ازدحاماً على 5GHz — $count شبكة مجاورة.');
    return ChannelRecommendation(band: band, bestChannel: best, note: note);
  }

  /// قنوات 5GHz المرشّحة: غير DFS الشائعة + أيّ قناة مستخدمة غير DFS.
  static List<int> _preferredNonDfs5(Map<int, double> loads) {
    final set = <int>{...common5.where((c) => !isDfs(c))};
    for (final c in loads.keys) {
      if (!isDfs(c)) set.add(c);
    }
    final list = set.toList()..sort();
    return list.isEmpty ? const [36] : list;
  }
}
