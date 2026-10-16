/// سجلّ نتائج الفحص واتجاهها — Network Quality (فحص متقدّم)
///
/// يحفظ ملخّص كل فحص محلياً في shared_preferences (مفتاح خاص بالوحدة، JSON)
/// بسقف ~50 إدخالاً (يُحذف الأقدم). كل القراءات/الكتابات محروسة بـtry/catch.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/quality_models.dart';

/// ملخّص فحص واحد يُحفظ في السجلّ.
class ScanSummary {
  final DateTime timestamp;
  final double overallScore;
  final QualityRating overallRating;
  final double? downloadMbps;
  final double? uploadMbps;
  final double? pingMs;
  final double? jitterMs;
  final double? packetLossPercent;
  final double? dnsMs;
  final double? rxPowerDbm;

  const ScanSummary({
    required this.timestamp,
    required this.overallScore,
    required this.overallRating,
    this.downloadMbps,
    this.uploadMbps,
    this.pingMs,
    this.jitterMs,
    this.packetLossPercent,
    this.dnsMs,
    this.rxPowerDbm,
  });

  factory ScanSummary.fromReport(FullQualityReport r) {
    final p = r.performance;
    return ScanSummary(
      timestamp: r.timestamp,
      overallScore: r.overallScore,
      overallRating: r.overallRating,
      downloadMbps: p.downloadMbps,
      uploadMbps: p.uploadMbps,
      pingMs: p.pingMs,
      jitterMs: p.jitterMs,
      packetLossPercent: p.packetLossPercent,
      dnsMs: p.dnsMs,
      rxPowerDbm: r.optical.available ? r.optical.rxPowerDbm : null,
    );
  }

  Map<String, dynamic> toJson() => {
        't': timestamp.toIso8601String(),
        's': overallScore,
        'r': overallRating.name,
        'dl': downloadMbps,
        'ul': uploadMbps,
        'p': pingMs,
        'j': jitterMs,
        'loss': packetLossPercent,
        'dns': dnsMs,
        'rx': rxPowerDbm,
      };

  static ScanSummary? fromJson(Map<String, dynamic> j) {
    try {
      final t = DateTime.tryParse(j['t']?.toString() ?? '');
      if (t == null) return null;
      QualityRating rating = QualityRating.unknown;
      final rn = j['r']?.toString();
      if (rn != null) {
        rating = QualityRating.values.firstWhere(
          (e) => e.name == rn,
          orElse: () => QualityRating.unknown,
        );
      }
      double? d(dynamic v) => v == null ? null : (v as num).toDouble();
      return ScanSummary(
        timestamp: t,
        overallScore: d(j['s']) ?? 0,
        overallRating: rating,
        downloadMbps: d(j['dl']),
        uploadMbps: d(j['ul']),
        pingMs: d(j['p']),
        jitterMs: d(j['j']),
        packetLossPercent: d(j['loss']),
        dnsMs: d(j['dns']),
        rxPowerDbm: d(j['rx']),
      );
    } catch (_) {
      return null;
    }
  }
}

class ScanHistoryService {
  static const _key = 'nq_scan_history';
  static const maxEntries = 50;

  /// يضيف ملخّصاً جديداً إلى السجلّ (ويحذف الأقدم عند تجاوز السقف).
  static Future<void> add(ScanSummary summary) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = _decode(sp.getString(_key));
      list.add(summary);
      // احتفظ بأحدث maxEntries فقط (الأقدم في البداية).
      final trimmed = list.length > maxEntries
          ? list.sublist(list.length - maxEntries)
          : list;
      final encoded =
          jsonEncode(trimmed.map((e) => e.toJson()).toList());
      await sp.setString(_key, encoded);
    } catch (e) {
      debugPrint('[History] add error: $e');
    }
  }

  /// يُعيد كل الملخّصات بترتيبها الزمني (الأقدم أولاً). العرض يرتّب حسب الحاجة.
  static Future<List<ScanSummary>> all() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return _decode(sp.getString(_key));
    } catch (e) {
      debugPrint('[History] read error: $e');
      return [];
    }
  }

  static Future<void> clear() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_key);
    } catch (e) {
      debugPrint('[History] clear error: $e');
    }
  }

  static List<ScanSummary> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      final out = <ScanSummary>[];
      for (final e in data) {
        if (e is Map) {
          final s = ScanSummary.fromJson(e.cast<String, dynamic>());
          if (s != null) out.add(s);
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }
}
