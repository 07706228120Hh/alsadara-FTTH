/// نماذج بيانات وحدة «فحص جودة الإنترنت» (Network Quality)
///
/// وحدة معزولة تماماً تحت lib/network_quality/ — لا تعتمد على أي منطق إنتاجي
/// في التطبيق سوى ثيم الصدارة (AppTheme) ومحوّل الراوتر (للإشارة الضوئية).
library;

/// تقييم عام لأي مقياس — يُترجم لاحقاً إلى لون ونص عربي.
enum QualityRating {
  excellent, // ممتاز
  good, // جيد
  fair, // مقبول
  poor, // ضعيف
  bad, // سيّئ
  unknown, // غير متوفّر
}

extension QualityRatingX on QualityRating {
  String get arabicLabel {
    switch (this) {
      case QualityRating.excellent:
        return 'ممتاز';
      case QualityRating.good:
        return 'جيد';
      case QualityRating.fair:
        return 'مقبول';
      case QualityRating.poor:
        return 'ضعيف';
      case QualityRating.bad:
        return 'سيّئ';
      case QualityRating.unknown:
        return 'غير متوفّر';
    }
  }

  /// درجة من 0..100 تمثّل التقييم (تُستخدم في حساب الدرجة الكلّية).
  double get score {
    switch (this) {
      case QualityRating.excellent:
        return 100;
      case QualityRating.good:
        return 80;
      case QualityRating.fair:
        return 60;
      case QualityRating.poor:
        return 35;
      case QualityRating.bad:
        return 12;
      case QualityRating.unknown:
        return 0;
    }
  }
}

/// مقياس مفرد داخل أي فئة (مثلاً: Ping = 14ms → ممتاز).
class MetricResult {
  final String name; // اسم المقياس بالعربية
  final String displayValue; // القيمة المعروضة (مثل "14 ms")
  final double? rawValue; // القيمة الخام للحسابات (nullable إن تعذّر القياس)
  final QualityRating rating;
  final String? note; // ملاحظة/تفسير اختياري

  const MetricResult({
    required this.name,
    required this.displayValue,
    required this.rating,
    this.rawValue,
    this.note,
  });

  static const MetricResult unknownMetric = MetricResult(
    name: '',
    displayValue: '—',
    rating: QualityRating.unknown,
  );
}

/// مواصفات الجهاز المضيف (الحاسبة/الهاتف الذي يُجري الفحص).
class DeviceSpecs {
  final String platform; // Windows / Android / ...
  final String model; // موديل الجهاز
  final String manufacturer;
  final String osVersion;
  final int? totalRamMb;
  final int? cpuCores;
  final String cpuInfo;
  final String deviceId;
  final Map<String, String> extra; // تفاصيل إضافية للعرض

  const DeviceSpecs({
    required this.platform,
    this.model = '',
    this.manufacturer = '',
    this.osVersion = '',
    this.totalRamMb,
    this.cpuCores,
    this.cpuInfo = '',
    this.deviceId = '',
    this.extra = const {},
  });

  static const DeviceSpecs empty = DeviceSpecs(platform: 'غير معروف');
}

/// معلومات إشارة WiFi (عند الاتصال لاسلكياً).
class WifiSignalInfo {
  final bool connectedViaWifi;
  final String ssid;
  final String bssid;
  final int? rssiDbm; // قوة الإشارة بالـdBm (سالبة: -30 ممتاز، -90 سيّئ)
  final int? signalPercent; // 0..100
  final int? linkSpeedMbps; // سرعة الوصلة اللاسلكية
  final int? frequencyMhz; // 2400 / 5000
  final int? channel;
  final String band; // 2.4GHz / 5GHz
  final String error;

  const WifiSignalInfo({
    this.connectedViaWifi = false,
    this.ssid = '',
    this.bssid = '',
    this.rssiDbm,
    this.signalPercent,
    this.linkSpeedMbps,
    this.frequencyMhz,
    this.channel,
    this.band = '',
    this.error = '',
  });

  static const WifiSignalInfo none = WifiSignalInfo();
}

/// معلومات الإشارة الضوئية للفايبر — تُقرأ من الـONU/ONT.
/// هذه الميزة الاحترافية التي تميّزنا عن تطبيقات الفحص العادية.
class OpticalSignalInfo {
  final bool available;
  final double? rxPowerDbm; // قدرة الاستقبال (-8..-27 طبيعي؛ أقل من -27 ضعيف)
  final double? txPowerDbm; // قدرة الإرسال
  final double? voltage; // فولتية الليزر (V)
  final double? biasCurrentMa; // تيار الانحياز (mA)
  final double? temperatureC; // حرارة الوحدة الضوئية
  final String onuModel;
  final String source; // مصدر القراءة (Huawei / ZTE / ...)
  final String error;

  const OpticalSignalInfo({
    this.available = false,
    this.rxPowerDbm,
    this.txPowerDbm,
    this.voltage,
    this.biasCurrentMa,
    this.temperatureC,
    this.onuModel = '',
    this.source = '',
    this.error = '',
  });

  static const OpticalSignalInfo none = OpticalSignalInfo();
}

/// نتائج أداء الإنترنت (زمن الاستجابة، التذبذب، فقدان الحزم، السرعة، DNS).
class InternetPerfResult {
  final double? pingMs; // متوسط زمن الاستجابة
  final double? minPingMs;
  final double? maxPingMs;
  final double? jitterMs; // التذبذب
  final double? packetLossPercent;
  final double? downloadMbps;
  final double? uploadMbps;
  final double? dnsMs; // زمن استجابة DNS
  final bool hasInternet;
  final List<String> traceroute; // قفزات المسار (best-effort)
  final String error;

  const InternetPerfResult({
    this.pingMs,
    this.minPingMs,
    this.maxPingMs,
    this.jitterMs,
    this.packetLossPercent,
    this.downloadMbps,
    this.uploadMbps,
    this.dnsMs,
    this.hasInternet = false,
    this.traceroute = const [],
    this.error = '',
  });

  static const InternetPerfResult empty = InternetPerfResult();
}

/// التقرير الكامل لجلسة فحص واحدة.
class FullQualityReport {
  final DeviceSpecs device;
  final WifiSignalInfo wifi;
  final OpticalSignalInfo optical;
  final InternetPerfResult performance;
  final double overallScore; // 0..100
  final QualityRating overallRating;
  final List<String> recommendations;
  final DateTime timestamp;

  const FullQualityReport({
    required this.device,
    required this.wifi,
    required this.optical,
    required this.performance,
    required this.overallScore,
    required this.overallRating,
    required this.recommendations,
    required this.timestamp,
  });
}
