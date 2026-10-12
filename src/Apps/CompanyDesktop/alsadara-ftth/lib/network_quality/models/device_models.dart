/// نماذج أجهزة الشبكة — Network Quality / اكتشاف وفحص الأجهزة
///
/// تمثّل الأجهزة المكتشَفة على الشبكة المحلية (ONU/ONT، راوتر، نقاط وصول،
/// والأجهزة المتصلة) وتقاريرها التفصيلية بعد الدخول.
library;

/// نوع الجهاز المُقدَّر.
enum DeviceType {
  onu, // وحدة فايبر ضوئية (ONU/ONT)
  router, // راوتر
  accessPoint, // نقطة وصول / مقوّي
  client, // جهاز متصل (هاتف/حاسبة/تلفاز...)
  unknown,
}

extension DeviceTypeX on DeviceType {
  String get arabicLabel {
    switch (this) {
      case DeviceType.onu:
        return 'وحدة فايبر (ONU/ONT)';
      case DeviceType.router:
        return 'راوتر';
      case DeviceType.accessPoint:
        return 'نقطة وصول/مقوّي';
      case DeviceType.client:
        return 'جهاز متصل';
      case DeviceType.unknown:
        return 'جهاز غير معروف';
    }
  }
}

/// حالة الوصول لواجهة الجهاز بعد محاولة الدخول.
enum InspectStatus {
  notInspected, // لم يُفحص بعد
  needsCredentials, // الدخول فشل بالاعتماد الافتراضي — يلزم إدخال يدوي
  authenticated, // تمّ الدخول وقراءة التقرير
  unreachableUi, // لا واجهة ويب (جهاز عميل عادي)
  error,
}

/// جهاز متصل بالراوتر (من جدول DHCP / قائمة العملاء).
class ConnectedClient {
  final String ip;
  final String mac;
  final String hostname;
  final String vendor; // من OUI
  final String connection; // wifi / ethernet / غير معروف
  final int? rssiDbm; // قوة إشارة المحطة اللاسلكية إن توفّرت

  const ConnectedClient({
    this.ip = '',
    this.mac = '',
    this.hostname = '',
    this.vendor = '',
    this.connection = '',
    this.rssiDbm,
  });
}

/// محطة WiFi متصلة (من قائمة المحطات في الراوتر).
class WifiStation {
  final String mac;
  final int? rssiDbm;
  final String band;
  final int? txRateMbps;

  const WifiStation({this.mac = '', this.rssiDbm, this.band = '', this.txRateMbps});
}

/// التقرير التفصيلي لجهاز بنية (ONU/راوتر) بعد الدخول.
class DeviceReport {
  final String model;
  final String firmware;
  final String hardwareVersion;
  final String uptime;
  final String wanConnectionType; // PPPoE / DHCP / Bridge ...
  final String pppoeUser;
  final String wanIp;
  final String lanIp;
  final String macAddress;

  // WiFi
  final String wifiSsid;
  final String wifiBand;
  final int? wifiChannel;
  final String wifiSecurity;

  // أداء الجهاز (حيثما توفّر)
  final double? cpuUsagePercent;
  final double? memUsagePercent;
  final double? temperatureC;

  final List<ConnectedClient> clients;
  final List<WifiStation> wifiStations;
  final Map<String, String> extra;

  const DeviceReport({
    this.model = '',
    this.firmware = '',
    this.hardwareVersion = '',
    this.uptime = '',
    this.wanConnectionType = '',
    this.pppoeUser = '',
    this.wanIp = '',
    this.lanIp = '',
    this.macAddress = '',
    this.wifiSsid = '',
    this.wifiBand = '',
    this.wifiChannel,
    this.wifiSecurity = '',
    this.cpuUsagePercent,
    this.memUsagePercent,
    this.temperatureC,
    this.clients = const [],
    this.wifiStations = const [],
    this.extra = const {},
  });

  bool get hasAnyData =>
      model.isNotEmpty ||
      firmware.isNotEmpty ||
      wanIp.isNotEmpty ||
      pppoeUser.isNotEmpty ||
      clients.isNotEmpty;
}

/// جهاز مكتشَف على الشبكة (قبل/بعد الفحص العميق).
class NetworkDevice {
  final String ip;
  String mac;
  String vendor; // من OUI
  DeviceType type;
  String brandGuess; // ماركة مُقدَّرة (Huawei/ZTE/TP-Link...)
  bool hasWebUi;
  String pageTitle;
  bool isGateway;
  bool isOnu;

  InspectStatus status;
  DeviceReport? report;
  OpticalReading? optical; // للـONU
  String error;

  NetworkDevice({
    required this.ip,
    this.mac = '',
    this.vendor = '',
    this.type = DeviceType.unknown,
    this.brandGuess = '',
    this.hasWebUi = false,
    this.pageTitle = '',
    this.isGateway = false,
    this.isOnu = false,
    this.status = InspectStatus.notInspected,
    this.report,
    this.optical,
    this.error = '',
  });

  String get displayName {
    if (brandGuess.isNotEmpty) return brandGuess;
    if (vendor.isNotEmpty) return vendor;
    return type.arabicLabel;
  }
}

/// قراءة الإشارة الضوئية المرتبطة بجهاز (نسخة خفيفة لربطها بالجهاز).
class OpticalReading {
  final double? rxPowerDbm;
  final double? txPowerDbm;
  final double? voltage;
  final double? biasCurrentMa;
  final double? temperatureC;

  const OpticalReading({
    this.rxPowerDbm,
    this.txPowerDbm,
    this.voltage,
    this.biasCurrentMa,
    this.temperatureC,
  });
}

/// نتيجة اكتشاف الشبكة.
class DiscoveryResult {
  final List<NetworkDevice> devices;
  final String? gatewayIp;
  final String? onuIp;
  final bool doubleNat;
  final String note;

  const DiscoveryResult({
    this.devices = const [],
    this.gatewayIp,
    this.onuIp,
    this.doubleNat = false,
    this.note = '',
  });
}
