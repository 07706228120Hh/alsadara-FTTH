/// محرّك التقييم والدرجات — Network Quality
///
/// يحوّل القيم الخام (ping, jitter, rssi, dBm ضوئي...) إلى تقييمات QualityRating
/// وفق عتبات معيارية، ثم يحسب الدرجة الكلّية ويولّد توصيات عربية.
library;

import '../models/quality_models.dart';

class QualityScorer {
  // ═══════════════ عتبات مقاييس الإنترنت ═══════════════

  /// زمن الاستجابة (ms): أقل = أفضل.
  static QualityRating ratePing(double? ms) {
    if (ms == null) return QualityRating.unknown;
    if (ms <= 20) return QualityRating.excellent;
    if (ms <= 50) return QualityRating.good;
    if (ms <= 100) return QualityRating.fair;
    if (ms <= 200) return QualityRating.poor;
    return QualityRating.bad;
  }

  /// التذبذب (ms): أقل = أفضل.
  static QualityRating rateJitter(double? ms) {
    if (ms == null) return QualityRating.unknown;
    if (ms <= 5) return QualityRating.excellent;
    if (ms <= 15) return QualityRating.good;
    if (ms <= 30) return QualityRating.fair;
    if (ms <= 50) return QualityRating.poor;
    return QualityRating.bad;
  }

  /// فقدان الحزم (%): أقل = أفضل.
  static QualityRating ratePacketLoss(double? percent) {
    if (percent == null) return QualityRating.unknown;
    if (percent <= 0) return QualityRating.excellent;
    if (percent <= 1) return QualityRating.good;
    if (percent <= 2.5) return QualityRating.fair;
    if (percent <= 5) return QualityRating.poor;
    return QualityRating.bad;
  }

  /// سرعة التنزيل (Mbps): أعلى = أفضل.
  static QualityRating rateDownload(double? mbps) {
    if (mbps == null) return QualityRating.unknown;
    if (mbps >= 100) return QualityRating.excellent;
    if (mbps >= 50) return QualityRating.good;
    if (mbps >= 20) return QualityRating.fair;
    if (mbps >= 5) return QualityRating.poor;
    return QualityRating.bad;
  }

  /// سرعة الرفع (Mbps): أعلى = أفضل.
  static QualityRating rateUpload(double? mbps) {
    if (mbps == null) return QualityRating.unknown;
    if (mbps >= 50) return QualityRating.excellent;
    if (mbps >= 20) return QualityRating.good;
    if (mbps >= 10) return QualityRating.fair;
    if (mbps >= 2) return QualityRating.poor;
    return QualityRating.bad;
  }

  /// زمن استجابة DNS (ms): أقل = أفضل.
  static QualityRating rateDns(double? ms) {
    if (ms == null) return QualityRating.unknown;
    if (ms <= 20) return QualityRating.excellent;
    if (ms <= 50) return QualityRating.good;
    if (ms <= 120) return QualityRating.fair;
    if (ms <= 250) return QualityRating.poor;
    return QualityRating.bad;
  }

  // ═══════════════ عتبات إشارة WiFi ═══════════════

  /// قوة WiFi بالـdBm (سالبة): أقرب للصفر = أقوى.
  static QualityRating rateWifiRssi(int? dbm) {
    if (dbm == null) return QualityRating.unknown;
    if (dbm >= -50) return QualityRating.excellent;
    if (dbm >= -60) return QualityRating.good;
    if (dbm >= -70) return QualityRating.fair;
    if (dbm >= -80) return QualityRating.poor;
    return QualityRating.bad;
  }

  // ═══════════════ عتبات الإشارة الضوئية (الفايبر) ═══════════════

  /// قدرة الاستقبال الضوئية Rx (dBm): النطاق الصحّي تقريباً -8 .. -25.
  /// أقوى من -8 (قريب من الصفر) = فيض ضوئي؛ أضعف من -27 = إشارة منخفضة.
  static QualityRating rateOpticalRx(double? dbm) {
    if (dbm == null) return QualityRating.unknown;
    // القيم أقرب للصفر أقوى. المثالي بين -8 و -24.
    if (dbm <= -8 && dbm >= -24) return QualityRating.excellent;
    if (dbm < -24 && dbm >= -27) return QualityRating.good;
    if (dbm < -27 && dbm >= -29) return QualityRating.fair;
    if (dbm < -29 && dbm >= -31) return QualityRating.poor;
    if (dbm < -31) return QualityRating.bad;
    // أقوى من -8 (فيض زائد قد يُشبع المستقبل)
    if (dbm > -8 && dbm <= -3) return QualityRating.good;
    return QualityRating.poor; // > -3 dBm فيض ضوئي خطير
  }

  // ═══════════════ الدرجة الكلّية ═══════════════

  /// أوزان الفئات في الدرجة النهائية.
  static const double _wPerformance = 0.50; // أداء الإنترنت الأهم
  static const double _wOptical = 0.25; // الإشارة الضوئية
  static const double _wWifi = 0.15; // إشارة WiFi
  static const double _wDevice = 0.10; // جودة الجهاز

  /// يحسب درجة فئة أداء الإنترنت (0..100).
  static double performanceScore(InternetPerfResult p) {
    final parts = <double>[];
    void add(QualityRating r, double weight) {
      if (r != QualityRating.unknown) parts.add(r.score * weight);
    }

    // أوزان داخلية
    final ratings = <MapEntry<QualityRating, double>>[
      MapEntry(ratePing(p.pingMs), 0.25),
      MapEntry(rateJitter(p.jitterMs), 0.15),
      MapEntry(ratePacketLoss(p.packetLossPercent), 0.15),
      MapEntry(rateDownload(p.downloadMbps), 0.25),
      MapEntry(rateUpload(p.uploadMbps), 0.12),
      MapEntry(rateDns(p.dnsMs), 0.08),
    ];
    double totalWeight = 0;
    for (final e in ratings) {
      if (e.key != QualityRating.unknown) {
        add(e.key, e.value);
        totalWeight += e.value;
      }
    }
    if (totalWeight == 0) return 0;
    return parts.fold<double>(0, (a, b) => a + b) / totalWeight;
  }

  static double opticalScore(OpticalSignalInfo o) {
    if (!o.available || o.rxPowerDbm == null) return -1; // -1 = غير متوفّر
    return rateOpticalRx(o.rxPowerDbm).score;
  }

  static double wifiScore(WifiSignalInfo w) {
    if (!w.connectedViaWifi || w.rssiDbm == null) return -1;
    return rateWifiRssi(w.rssiDbm).score;
  }

  /// درجة جودة الجهاز — تقديرية من الذاكرة وعدد الأنوية.
  static double deviceScore(DeviceSpecs d) {
    if (d.totalRamMb == null && d.cpuCores == null) return -1;
    double ram = 60;
    if (d.totalRamMb != null) {
      if (d.totalRamMb! >= 8192) {
        ram = 100;
      } else if (d.totalRamMb! >= 4096) {
        ram = 80;
      } else if (d.totalRamMb! >= 2048) {
        ram = 55;
      } else {
        ram = 30;
      }
    }
    double cpu = 60;
    if (d.cpuCores != null) {
      if (d.cpuCores! >= 8) {
        cpu = 100;
      } else if (d.cpuCores! >= 4) {
        cpu = 80;
      } else if (d.cpuCores! >= 2) {
        cpu = 55;
      } else {
        cpu = 30;
      }
    }
    return (ram * 0.6) + (cpu * 0.4);
  }

  /// يحسب الدرجة الكلّية مع إعادة توزيع أوزان الفئات غير المتوفّرة.
  static double overall({
    required InternetPerfResult performance,
    required OpticalSignalInfo optical,
    required WifiSignalInfo wifi,
    required DeviceSpecs device,
  }) {
    final entries = <MapEntry<double, double>>[]; // (score, weight)
    entries.add(MapEntry(performanceScore(performance), _wPerformance));
    final os = opticalScore(optical);
    if (os >= 0) entries.add(MapEntry(os, _wOptical));
    final ws = wifiScore(wifi);
    if (ws >= 0) entries.add(MapEntry(ws, _wWifi));
    final ds = deviceScore(device);
    if (ds >= 0) entries.add(MapEntry(ds, _wDevice));

    double totalWeight = 0;
    double sum = 0;
    for (final e in entries) {
      if (e.key < 0) continue;
      sum += e.key * e.value;
      totalWeight += e.value;
    }
    if (totalWeight == 0) return 0;
    return (sum / totalWeight).clamp(0, 100);
  }

  static QualityRating ratingFromScore(double score) {
    if (score >= 85) return QualityRating.excellent;
    if (score >= 70) return QualityRating.good;
    if (score >= 50) return QualityRating.fair;
    if (score >= 30) return QualityRating.poor;
    return QualityRating.bad;
  }

  // ═══════════════ التوصيات ═══════════════

  static List<String> buildRecommendations({
    required InternetPerfResult p,
    required OpticalSignalInfo o,
    required WifiSignalInfo w,
    required DeviceSpecs d,
  }) {
    final recs = <String>[];

    if (ratePing(p.pingMs) == QualityRating.poor ||
        ratePing(p.pingMs) == QualityRating.bad) {
      recs.add('زمن الاستجابة مرتفع — تحقّق من ازدحام الشبكة أو جودة وصلة الفايبر.');
    }
    if (rateJitter(p.jitterMs) == QualityRating.poor ||
        rateJitter(p.jitterMs) == QualityRating.bad) {
      recs.add('التذبذب مرتفع — قد يؤثّر على المكالمات والبث؛ تحقّق من استقرار الاتصال.');
    }
    if ((p.packetLossPercent ?? 0) > 1) {
      recs.add('يوجد فقدان في الحزم — افحص الكيبل/الموصلات وجودة الإشارة الضوئية.');
    }
    if (rateDownload(p.downloadMbps) == QualityRating.poor ||
        rateDownload(p.downloadMbps) == QualityRating.bad) {
      recs.add('سرعة التنزيل أقل من المتوقّع — قارنها بسرعة الباقة المشترَك بها.');
    }

    if (o.available && o.rxPowerDbm != null) {
      final r = rateOpticalRx(o.rxPowerDbm);
      if (r == QualityRating.poor || r == QualityRating.bad) {
        recs.add(
            'الإشارة الضوئية (Rx=${o.rxPowerDbm!.toStringAsFixed(2)} dBm) ضعيفة — افحص اللحامات/الموصلات والمسافة عن الـOLT.');
      } else if (o.rxPowerDbm! > -8) {
        recs.add(
            'الإشارة الضوئية قوية جداً (فيض ضوئي) — قد تُشبع مستقبِل الـONU؛ يُنصح بمخمِّد (attenuator).');
      }
    }

    if (w.connectedViaWifi && w.rssiDbm != null) {
      final r = rateWifiRssi(w.rssiDbm);
      if (r == QualityRating.poor || r == QualityRating.bad) {
        recs.add(
            'إشارة WiFi ضعيفة (${w.rssiDbm} dBm) — قرّب الجهاز من الراوتر أو استخدم مقوّي إشارة.');
      }
      if (w.band == '2.4GHz') {
        recs.add('أنت على نطاق 2.4GHz — جرّب 5GHz لسرعة أعلى وتداخل أقل إن كان مدعوماً.');
      }
    }

    if ((d.totalRamMb ?? 99999) < 2048) {
      recs.add('ذاكرة الجهاز منخفضة — قد تحدّ من أداء التصفّح والتطبيقات.');
    }

    if (recs.isEmpty) {
      recs.add('كل المؤشّرات ضمن النطاق الجيّد — لا توجد مشاكل ظاهرة.');
    }
    return recs;
  }
}
