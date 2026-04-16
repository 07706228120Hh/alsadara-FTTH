/// خدمة GenieACS — التواصل مع NBI API لإدارة الراوترات عن بعد
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class GenieAcsService {
  static const String _baseUrl = 'http://187.124.177.236:7557';
  String get baseUrl => _baseUrl;
  static String get acsUrl => _baseUrl.replaceFirst(':7557', ':7547');
  static final GenieAcsService instance = GenieAcsService._();
  GenieAcsService._();

  /// البحث عن جهاز بواسطة PPPoE username أو serial أو MAC
  /// يستخدم server-side query بدلاً من جلب كل الأجهزة (مهم للأداء مع 50k+ جهاز)
  Future<Map<String, dynamic>?> findDevice({String? pppoeUsername, String? serial, String? mac}) async {
    final queries = <String>[];

    // 1) بحث بالسيريال — exact ثم regex (السيريال في FTTH قد يختلف عن GenieACS)
    if (serial != null && serial.isNotEmpty) {
      queries.add('{"_deviceId._SerialNumber":"$serial"}');
      queries.add('{"_deviceId._SerialNumber":{"\$regex":"(?i)$serial"}}');
    }

    // 2) بحث بالـ MAC — في _deviceId وفي hosts
    if (mac != null && mac.isNotEmpty) {
      final cleanMac = mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
      queries.add('{"_deviceId._SerialNumber":{"\$regex":"(?i)$cleanMac"}}');
      // MAC في مواقع مختلفة حسب الراوتر
      queries.add('{"InternetGatewayDevice.LANDevice.1.Hosts.Host.1.MACAddress._value":{"\$regex":"(?i)$mac"}}');
    }

    // 3) بحث بالـ PPPoE username — المسارات تختلف حسب نوع الراوتر
    //    WANConnectionDevice قد يكون 1 أو 2 أو أكثر
    if (pppoeUsername != null && pppoeUsername.isNotEmpty) {
      for (final wcd in ['1', '2', '3']) {
        queries.add('{"InternetGatewayDevice.WANDevice.1.WANConnectionDevice.$wcd.WANPPPConnection.1.Username._value":"$pppoeUsername"}');
      }
      // بحث عام بالـ regex في كل مكان يحتوي Username
      queries.add('{"\$or":[{"InternetGatewayDevice.WANDevice.1.WANConnectionDevice.1.WANPPPConnection.1.Username._value":"$pppoeUsername"},{"InternetGatewayDevice.WANDevice.1.WANConnectionDevice.2.WANPPPConnection.1.Username._value":"$pppoeUsername"},{"_tags":"$pppoeUsername"}]}');
    }

    for (final q in queries) {
      try {
        final uri = Uri.parse('$_baseUrl/devices').replace(
          queryParameters: {'query': q},
        );
        debugPrint('[GenieACS] trying query: $q');
        final r = await http.get(uri).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          final list = jsonDecode(r.body) as List;
          if (list.isNotEmpty) {
            debugPrint('[GenieACS] found device with query: $q');
            return Map<String, dynamic>.from(list.first);
          }
        }
      } catch (e) {
        debugPrint('[GenieACS] findDevice query=$q error: $e');
      }
    }
    debugPrint('[GenieACS] device not found for pppoe=$pppoeUsername serial=$serial mac=$mac');
    return null;
  }

  /// البحث عن كل الأجهزة المرتبطة بمشترك (ONU + راوتر إذا موجود)
  Future<List<Map<String, dynamic>>> findAllDevices({String? pppoeUsername, String? serial, String? mac}) async {
    final found = <String, Map<String, dynamic>>{}; // _id → raw, لمنع التكرار

    final queries = <String>[];
    if (serial != null && serial.isNotEmpty) {
      queries.add('{"_deviceId._SerialNumber":"$serial"}');
      queries.add('{"_deviceId._SerialNumber":{"\$regex":"(?i)$serial"}}');
    }
    if (mac != null && mac.isNotEmpty) {
      final cleanMac = mac.replaceAll(':', '').replaceAll('-', '').toUpperCase();
      queries.add('{"_deviceId._SerialNumber":{"\$regex":"(?i)$cleanMac"}}');
      queries.add('{"InternetGatewayDevice.LANDevice.1.Hosts.Host.1.MACAddress._value":{"\$regex":"(?i)$mac"}}');
    }
    if (pppoeUsername != null && pppoeUsername.isNotEmpty) {
      for (final wcd in ['1', '2', '3']) {
        queries.add('{"InternetGatewayDevice.WANDevice.1.WANConnectionDevice.$wcd.WANPPPConnection.1.Username._value":"$pppoeUsername"}');
      }
      queries.add('{"\$or":[{"InternetGatewayDevice.WANDevice.1.WANConnectionDevice.1.WANPPPConnection.1.Username._value":"$pppoeUsername"},{"InternetGatewayDevice.WANDevice.1.WANConnectionDevice.2.WANPPPConnection.1.Username._value":"$pppoeUsername"},{"_tags":"$pppoeUsername"}]}');
    }

    for (final q in queries) {
      try {
        final uri = Uri.parse('$_baseUrl/devices').replace(queryParameters: {'query': q});
        final r = await http.get(uri).timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          final list = jsonDecode(r.body) as List;
          for (final item in list) {
            final m = Map<String, dynamic>.from(item);
            final id = m['_id']?.toString() ?? '';
            if (id.isNotEmpty) found[id] = m;
          }
        }
      } catch (e) {
        debugPrint('[GenieACS] findAllDevices query=$q error: $e');
      }
    }
    return found.values.toList();
  }

  /// كشف راوتر على الشبكة المحلية عبر HTTP
  static Future<RouterDetectResult> detectLocalRouter(String ip) async {
    final result = RouterDetectResult(ip: ip);
    try {
      final r = await http.get(Uri.parse('http://$ip/'))
          .timeout(const Duration(seconds: 5));
      result.reachable = true;
      result.statusCode = r.statusCode;
      final body = r.body.toLowerCase();
      final headers = r.headers.toString().toLowerCase();
      final combined = '$body $headers';

      // كشف العلامة التجارية
      if (combined.contains('tp-link') || combined.contains('tplinkwifi')) {
        result.brand = 'TP-Link';
        result.tr069Path = 'Advanced → System Tools → CWMP (TR-069)';
      } else if (combined.contains('tenda')) {
        result.brand = 'Tenda';
        result.tr069Path = 'Administration → TR-069';
      } else if (combined.contains('huawei') || combined.contains('hg8') || combined.contains('echolife')) {
        result.brand = 'Huawei';
        result.tr069Path = 'Advanced → WAN → TR-069';
      } else if (combined.contains('zte') || combined.contains('zxhn')) {
        result.brand = 'ZTE';
        result.tr069Path = 'Administration → TR-069 Client';
      } else if (combined.contains('mercusys')) {
        result.brand = 'Mercusys';
        result.supportsTr069 = false;
        result.tr069Path = 'غير مدعوم — Mercusys لا يدعم TR-069';
      } else if (combined.contains('xiaomi') || combined.contains('miwifi') || combined.contains('redmi')) {
        result.brand = 'Xiaomi';
        result.supportsTr069 = false;
        result.tr069Path = 'غير مدعوم — Xiaomi لا يدعم TR-069';
      } else if (combined.contains('d-link') || combined.contains('dlink')) {
        result.brand = 'D-Link';
        result.tr069Path = 'Management → TR-069 Client';
      } else if (combined.contains('netis')) {
        result.brand = 'Netis';
        result.tr069Path = 'System → CWMP Settings';
      } else if (combined.contains('mikrotik') || combined.contains('routeros')) {
        result.brand = 'MikroTik';
        result.tr069Path = 'System → TR-069 (package required)';
      }

      // محاولة استخراج الموديل من العنوان أو body
      final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>').firstMatch(r.body);
      if (titleMatch != null) {
        result.pageTitle = titleMatch.group(1)?.trim() ?? '';
      }
    } catch (e) {
      result.reachable = false;
      result.error = e.toString();
    }
    return result;
  }

  /// فحص عدة عناوين IP شائعة للراوترات
  static Future<List<RouterDetectResult>> scanLocalNetwork() async {
    final ips = ['192.168.1.1', '192.168.0.1', '192.168.100.1', '192.168.31.1', '10.0.0.1', '192.168.2.1'];
    final futures = ips.map((ip) => detectLocalRouter(ip));
    final results = await Future.wait(futures);
    return results.where((r) => r.reachable).toList();
  }

  /// جلب أجهزة مع فلتر اختياري + pagination
  /// [query] — MongoDB-style filter, مثال: '{"_tags":"online"}'
  /// [projection] — الحقول المطلوبة فقط (لتقليل حجم الاستجابة)
  /// [limit] — عدد النتائج (افتراضي 50، أقصى حد GenieACS = 10000)
  /// [skip] — تخطي أول N نتيجة (للصفحات التالية)
  Future<List<Map<String, dynamic>>> getDevices({
    String? query,
    String? projection,
    int limit = 50,
    int skip = 0,
  }) async {
    try {
      final params = <String, String>{
        'limit': '$limit',
        'skip': '$skip',
      };
      if (query != null) params['query'] = query;
      if (projection != null) params['projection'] = projection;

      final uri = Uri.parse('$_baseUrl/devices').replace(queryParameters: params);
      final r = await http.get(uri).timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('[GenieACS] getDevices error: $e');
    }
    return [];
  }

  /// جلب جهاز بالـ ID
  Future<Map<String, dynamic>?> getDevice(String deviceId) async {
    try {
      final encoded = Uri.encodeComponent(deviceId);
      final r = await http.get(Uri.parse('$_baseUrl/devices/$encoded')).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body);
        if (list is List && list.isNotEmpty) return Map<String, dynamic>.from(list.first);
      }
    } catch (e) {
      debugPrint('[GenieACS] getDevice error: $e');
    }
    return null;
  }

  /// إعادة تشغيل جهاز
  Future<bool> rebootDevice(String deviceId) async {
    return _postTask(deviceId, {'name': 'reboot'});
  }

  /// Factory Reset
  Future<bool> factoryReset(String deviceId) async {
    return _postTask(deviceId, {'name': 'factoryReset'});
  }

  /// قراءة قيمة parameter
  Future<bool> refreshDevice(String deviceId) async {
    return _postTask(deviceId, {
      'name': 'getParameterValues',
      'parameterNames': ['InternetGatewayDevice.'],
    });
  }

  /// تغيير قيمة parameter
  Future<bool> setParameter(String deviceId, String paramPath, dynamic value, String type) async {
    return _postTask(deviceId, {
      'name': 'setParameterValues',
      'parameterValues': [[paramPath, value, type]],
    });
  }

  /// تغيير عدة parameters دفعة واحدة
  Future<bool> setParameters(String deviceId, List<List<dynamic>> params) async {
    return _postTask(deviceId, {
      'name': 'setParameterValues',
      'parameterValues': params,
    });
  }

  // ═══ WiFi 2.4GHz (WLANConfiguration.1) ═══
  Future<bool> setWifiSsid(String deviceId, String ssid) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1.SSID', ssid, 'xsd:string');

  Future<bool> setWifiPassword(String deviceId, String password) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1.KeyPassphrase', password, 'xsd:string');

  Future<bool> setWifiEnabled(String deviceId, bool enabled) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1.Enable', enabled, 'xsd:boolean');

  Future<bool> setWifiChannel(String deviceId, int channel) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1.Channel', channel, 'xsd:unsignedInt');

  Future<bool> setWifiAutoChannel(String deviceId, bool auto) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1.AutoChannelEnable', auto, 'xsd:boolean');

  Future<bool> setWifiHidden(String deviceId, bool hidden) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1.SSIDAdvertisementEnabled', !hidden, 'xsd:boolean');

  Future<bool> setWifiMacFilter(String deviceId, bool enabled) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.1.MACAddressControlEnabled', enabled, 'xsd:boolean');

  // ═══ WiFi 5GHz (WLANConfiguration.5 أو .2 حسب الراوتر) ═══
  Future<bool> setWifi5Ssid(String deviceId, String ssid, int wlanIdx) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.$wlanIdx.SSID', ssid, 'xsd:string');

  Future<bool> setWifi5Password(String deviceId, String password, int wlanIdx) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.$wlanIdx.KeyPassphrase', password, 'xsd:string');

  Future<bool> setWifi5Enabled(String deviceId, bool enabled, int wlanIdx) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.WLANConfiguration.$wlanIdx.Enable', enabled, 'xsd:boolean');

  // ═══ DHCP ═══
  Future<bool> setDhcpEnabled(String deviceId, bool enabled) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.LANHostConfigManagement.DHCPServerEnable', enabled, 'xsd:boolean');

  Future<bool> setDhcpRange(String deviceId, String min, String max) =>
      setParameters(deviceId, [
        ['InternetGatewayDevice.LANDevice.1.LANHostConfigManagement.MinAddress', min, 'xsd:string'],
        ['InternetGatewayDevice.LANDevice.1.LANHostConfigManagement.MaxAddress', max, 'xsd:string'],
      ]);

  Future<bool> setDnsServers(String deviceId, String dns) =>
      setParameter(deviceId, 'InternetGatewayDevice.LANDevice.1.LANHostConfigManagement.DNSServers', dns, 'xsd:string');

  // ═══════════════════════════════════════════════
  // 1. تحديد سرعة المشترك (QoS / Bandwidth Limit)
  // ═══════════════════════════════════════════════

  /// تحديد سرعة التحميل والرفع (بالكيلوبت/ثانية)
  /// يحاول عدة مسارات لأن كل راوتر يختلف
  Future<bool> setBandwidthLimit(String deviceId, int downloadKbps, int uploadKbps) async {
    // المسارات الأكثر شيوعاً لتحديد السرعة عبر TR-069
    final paths = [
      // Huawei X_HW
      ['InternetGatewayDevice.WANDevice.1.WANConnectionDevice.*.WANPPPConnection.1.X_HW_DownlinkRate', downloadKbps, 'xsd:unsignedInt'],
      ['InternetGatewayDevice.WANDevice.1.WANConnectionDevice.*.WANPPPConnection.1.X_HW_UplinkRate', uploadKbps, 'xsd:unsignedInt'],
    ];
    // نحاول الـ Huawei paths أولاً
    var ok = await setParameters(deviceId, [
      ['InternetGatewayDevice.WANDevice.1.WANConnectionDevice.2.WANPPPConnection.1.X_HW_DownlinkRate', downloadKbps, 'xsd:unsignedInt'],
      ['InternetGatewayDevice.WANDevice.1.WANConnectionDevice.2.WANPPPConnection.1.X_HW_UplinkRate', uploadKbps, 'xsd:unsignedInt'],
    ]);
    if (ok) return true;
    // fallback: WANConnectionDevice.1
    ok = await setParameters(deviceId, [
      ['InternetGatewayDevice.WANDevice.1.WANConnectionDevice.1.WANPPPConnection.1.X_HW_DownlinkRate', downloadKbps, 'xsd:unsignedInt'],
      ['InternetGatewayDevice.WANDevice.1.WANConnectionDevice.1.WANPPPConnection.1.X_HW_UplinkRate', uploadKbps, 'xsd:unsignedInt'],
    ]);
    if (ok) return true;
    // Generic QoS (بعض الراوترات)
    return setParameters(deviceId, [
      ['InternetGatewayDevice.X_HW_QoS.DownlinkRate', downloadKbps, 'xsd:unsignedInt'],
      ['InternetGatewayDevice.X_HW_QoS.UplinkRate', uploadKbps, 'xsd:unsignedInt'],
    ]);
  }

  // ═══════════════════════════════════════════════
  // 2. تشخيص عن بعد (Ping / Traceroute)
  // ═══════════════════════════════════════════════

  /// تشغيل Ping من الراوتر
  Future<bool> startPing(String deviceId, String host, {int count = 4, int timeout = 5000}) async {
    return setParameters(deviceId, [
      ['InternetGatewayDevice.IPPingDiagnostics.Host', host, 'xsd:string'],
      ['InternetGatewayDevice.IPPingDiagnostics.NumberOfRepetitions', count, 'xsd:unsignedInt'],
      ['InternetGatewayDevice.IPPingDiagnostics.Timeout', timeout, 'xsd:unsignedInt'],
      ['InternetGatewayDevice.IPPingDiagnostics.DiagnosticsState', 'Requested', 'xsd:string'],
    ]);
  }

  /// قراءة نتائج Ping
  Future<PingResult?> getPingResult(String deviceId) async {
    // refresh القيم أولاً
    await _postTask(deviceId, {
      'name': 'getParameterValues',
      'parameterNames': ['InternetGatewayDevice.IPPingDiagnostics.'],
    });
    // انتظر ثم اقرأ
    await Future.delayed(const Duration(seconds: 3));
    final uri = Uri.parse('$_baseUrl/devices').replace(
      queryParameters: {'query': '{"_id":"$deviceId"}', 'projection': 'InternetGatewayDevice.IPPingDiagnostics'},
    );
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        if (list.isNotEmpty) {
          final raw = Map<String, dynamic>.from(list.first);
          final diag = raw['InternetGatewayDevice']?['IPPingDiagnostics'];
          if (diag is Map) {
            return PingResult(
              state: _val(diag['DiagnosticsState']),
              successCount: int.tryParse(_val(diag['SuccessCount'])) ?? 0,
              failureCount: int.tryParse(_val(diag['FailureCount'])) ?? 0,
              avgResponseTime: int.tryParse(_val(diag['AverageResponseTime'])) ?? 0,
              minResponseTime: int.tryParse(_val(diag['MinimumResponseTime'])) ?? 0,
              maxResponseTime: int.tryParse(_val(diag['MaximumResponseTime'])) ?? 0,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[GenieACS] getPingResult error: $e');
    }
    return null;
  }

  /// تشغيل Traceroute من الراوتر
  Future<bool> startTraceroute(String deviceId, String host) async {
    return setParameters(deviceId, [
      ['InternetGatewayDevice.TraceRouteDiagnostics.Host', host, 'xsd:string'],
      ['InternetGatewayDevice.TraceRouteDiagnostics.MaxHopCount', 30, 'xsd:unsignedInt'],
      ['InternetGatewayDevice.TraceRouteDiagnostics.Timeout', 5000, 'xsd:unsignedInt'],
      ['InternetGatewayDevice.TraceRouteDiagnostics.DiagnosticsState', 'Requested', 'xsd:string'],
    ]);
  }

  // ═══════════════════════════════════════════════
  // 4. مراقبة الأجهزة (Alerts)
  // ═══════════════════════════════════════════════

  /// جلب الأجهزة المنقطعة (آخر inform أكثر من [minutesThreshold] دقيقة)
  Future<List<DeviceInfo>> getOfflineDevices({int minutesThreshold = 15, int limit = 100}) async {
    final cutoff = DateTime.now().toUtc().subtract(Duration(minutes: minutesThreshold));
    final query = '{"_lastInform":{"\$lt":"${cutoff.toIso8601String()}"}}';
    final devices = await getDevices(
      query: query,
      projection: '_id,_deviceId,_lastInform,_lastBoot,_tags',
      limit: limit,
    );
    return devices.map((d) => parseDevice(d)).toList();
  }

  /// جلب الأجهزة المتصلة (آخر inform أقل من [minutesThreshold] دقيقة)
  Future<List<DeviceInfo>> getOnlineDevices({int minutesThreshold = 10, int limit = 100}) async {
    final cutoff = DateTime.now().toUtc().subtract(Duration(minutes: minutesThreshold));
    final query = '{"_lastInform":{"\$gt":"${cutoff.toIso8601String()}"}}';
    final devices = await getDevices(
      query: query,
      projection: '_id,_deviceId,_lastInform,_lastBoot,_tags',
      limit: limit,
    );
    return devices.map((d) => parseDevice(d)).toList();
  }

  /// إحصائيات سريعة
  Future<Map<String, int>> getDeviceStats() async {
    try {
      // عدد الكل
      final allUri = Uri.parse('$_baseUrl/devices').replace(queryParameters: {'projection': '_id', 'limit': '0'});
      // GenieACS doesn't support count directly, so we get with limit and count response
      final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 10));

      final onlineQuery = '{"_lastInform":{"\$gt":"${cutoff.toIso8601String()}"}}';
      final offlineQuery = '{"_lastInform":{"\$lt":"${cutoff.toIso8601String()}"}}';

      final onlineUri = Uri.parse('$_baseUrl/devices').replace(
        queryParameters: {'query': onlineQuery, 'projection': '_id', 'limit': '10000'},
      );
      final offlineUri = Uri.parse('$_baseUrl/devices').replace(
        queryParameters: {'query': offlineQuery, 'projection': '_id', 'limit': '10000'},
      );

      final results = await Future.wait([
        http.get(onlineUri).timeout(const Duration(seconds: 15)),
        http.get(offlineUri).timeout(const Duration(seconds: 15)),
      ]);

      final onlineCount = results[0].statusCode == 200 ? (jsonDecode(results[0].body) as List).length : 0;
      final offlineCount = results[1].statusCode == 200 ? (jsonDecode(results[1].body) as List).length : 0;

      return {'online': onlineCount, 'offline': offlineCount, 'total': onlineCount + offlineCount};
    } catch (e) {
      debugPrint('[GenieACS] getDeviceStats error: $e');
      return {'online': 0, 'offline': 0, 'total': 0};
    }
  }

  /// إرسال task عام
  Future<bool> _postTask(String deviceId, Map<String, dynamic> task) async {
    try {
      final encoded = Uri.encodeComponent(deviceId);
      final r = await http.post(
        Uri.parse('$_baseUrl/devices/$encoded/tasks?connection_request'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(task),
      ).timeout(const Duration(seconds: 15));
      debugPrint('[GenieACS] task ${task['name']} → ${r.statusCode}');
      return r.statusCode == 200 || r.statusCode == 202;
    } catch (e) {
      debugPrint('[GenieACS] _postTask error: $e');
      return false;
    }
  }

  /// استخراج معلومات مفيدة من بيانات الجهاز الخام
  static DeviceInfo parseDevice(Map<String, dynamic> raw) {
    final info = DeviceInfo();
    info.id = raw['_id']?.toString() ?? '';
    info.lastInform = raw['_lastInform']?.toString() ?? '';
    info.lastBoot = raw['_lastBoot']?.toString() ?? '';
    info.registered = raw['_registered']?.toString() ?? '';

    final deviceId = raw['_deviceId'];
    if (deviceId is Map) {
      info.manufacturer = deviceId['_Manufacturer']?.toString() ?? '';
      info.oui = deviceId['_OUI']?.toString() ?? '';
      info.productClass = deviceId['_ProductClass']?.toString() ?? '';
      info.serialNumber = deviceId['_SerialNumber']?.toString() ?? '';
    }

    final igw = raw['InternetGatewayDevice'];
    if (igw is Map) {
      // DeviceInfo
      final di = igw['DeviceInfo'];
      if (di is Map) {
        info.hardwareVersion = _val(di['HardwareVersion']);
        info.softwareVersion = _val(di['SoftwareVersion']);
      }

      // WAN IP
      final wan = igw['WANDevice'];
      if (wan is Map) {
        _walkMap(wan, (key, val) {
          if (key == 'ExternalIPAddress' && val is Map && val['_value'] != null) {
            info.wanIp = val['_value'].toString();
          }
        });
      }

      // Connected hosts
      final lan = igw['LANDevice'];
      if (lan is Map) {
        final l1 = lan['1'];
        if (l1 is Map) {
          final hosts = l1['Hosts'];
          if (hosts is Map) {
            final host = hosts['Host'];
            if (host is Map) {
              host.forEach((k, v) {
                if (v is Map) {
                  final h = ConnectedHost();
                  h.hostname = _val(v['HostName']);
                  h.ip = _val(v['IPAddress']);
                  h.mac = _val(v['MACAddress']);
                  if (h.ip.isNotEmpty || h.mac.isNotEmpty) {
                    info.connectedHosts.add(h);
                  }
                }
              });
            }
          }
        }
      }

      // WiFi configurations
      if (lan is Map) {
        final l1 = lan['1'];
        if (l1 is Map) {
          final wlanRoot = l1['WLANConfiguration'];
          if (wlanRoot is Map) {
            wlanRoot.forEach((wlanIdx, wlanData) {
              if (wlanData is Map && wlanIdx != '_object' && wlanIdx != '_writable' && wlanIdx != '_timestamp') {
                final w = WifiConfig();
                w.index = int.tryParse(wlanIdx.toString()) ?? 0;
                w.ssid = _val(wlanData['SSID']);
                w.password = _val(wlanData['KeyPassphrase']);
                w.channel = _val(wlanData['Channel']);
                w.autoChannel = _val(wlanData['AutoChannelEnable']).toLowerCase() == 'true';
                w.enabled = _val(wlanData['Enable']).toLowerCase() != 'false';
                w.hidden = _val(wlanData['SSIDAdvertisementEnabled']).toLowerCase() == 'false';
                w.macFilterEnabled = _val(wlanData['MACAddressControlEnabled']).toLowerCase() == 'true';
                w.standard = _val(wlanData['Standard']);
                w.beaconType = _val(wlanData['BeaconType']);
                if (w.ssid.isNotEmpty || w.index > 0) {
                  // تحديد إذا 5GHz من الـ standard أو الـ SSID
                  final std = w.standard.toLowerCase();
                  if (std.contains('ac') || std.contains('ax') || std.contains('a') && !std.contains('b')) {
                    w.is5Ghz = true;
                  } else if (w.ssid.toLowerCase().contains('5g')) {
                    w.is5Ghz = true;
                  }
                  info.wifiConfigs.add(w);
                }
              }
            });
          }

          // DHCP
          final dhcp = l1['LANHostConfigManagement'];
          if (dhcp is Map) {
            info.dhcpEnabled = _val(dhcp['DHCPServerEnable']).toLowerCase() == 'true';
            info.dhcpMinAddress = _val(dhcp['MinAddress']);
            info.dhcpMaxAddress = _val(dhcp['MaxAddress']);
            info.dhcpSubnetMask = _val(dhcp['SubnetMask']);
            info.dnsServers = _val(dhcp['DNSServers']);
            final ipIntf = dhcp['IPInterface'];
            if (ipIntf is Map) {
              _walkMap(ipIntf, (key, val) {
                if (key == 'IPInterfaceIPAddress' && val is Map && val['_value'] != null) {
                  info.lanIp = val['_value'].toString();
                }
              });
            }
          }
        }
      }

      // ManagementServer
      final ms = igw['ManagementServer'];
      if (ms is Map) {
        info.connectionRequestUrl = _val(ms['ConnectionRequestURL']);
        info.periodicInformInterval = _val(ms['PeriodicInformInterval']);
      }
    }

    return info;
  }

  static String _val(dynamic field) {
    if (field is Map) return field['_value']?.toString() ?? '';
    return field?.toString() ?? '';
  }

  static void _walkMap(Map map, void Function(String key, dynamic val) callback) {
    map.forEach((k, v) {
      callback(k.toString(), v);
      if (v is Map) _walkMap(v, callback);
    });
  }
}

class WifiConfig {
  int index = 0;
  String ssid = '';
  String password = '';
  String channel = '';
  bool autoChannel = true;
  bool enabled = true;
  bool hidden = false;
  bool macFilterEnabled = false;
  String standard = '';
  String beaconType = '';
  bool is5Ghz = false;

  String get bandLabel => is5Ghz ? '5GHz' : '2.4GHz';
}

class DeviceInfo {
  String id = '';
  String manufacturer = '';
  String oui = '';
  String productClass = '';
  String serialNumber = '';
  String hardwareVersion = '';
  String softwareVersion = '';
  String wanIp = '';
  String lanIp = '';
  String lastInform = '';
  String lastBoot = '';
  String registered = '';
  String connectionRequestUrl = '';
  String periodicInformInterval = '';
  List<ConnectedHost> connectedHosts = [];
  List<WifiConfig> wifiConfigs = [];
  // DHCP
  bool dhcpEnabled = false;
  String dhcpMinAddress = '';
  String dhcpMaxAddress = '';
  String dhcpSubnetMask = '';
  String dnsServers = '';

  bool get isOnline {
    if (lastInform.isEmpty) return false;
    try {
      final dt = DateTime.parse(lastInform);
      return DateTime.now().toUtc().difference(dt).inMinutes < 10;
    } catch (_) {
      return false;
    }
  }

  String get lastInformFormatted {
    if (lastInform.isEmpty) return '-';
    try {
      final dt = DateTime.parse(lastInform).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'الآن';
      if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
      if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
      return 'منذ ${diff.inDays} يوم';
    } catch (_) {
      return lastInform;
    }
  }
}

class ConnectedHost {
  String hostname = '';
  String ip = '';
  String mac = '';
}

class PingResult {
  final String state;
  final int successCount;
  final int failureCount;
  final int avgResponseTime;
  final int minResponseTime;
  final int maxResponseTime;

  PingResult({
    required this.state,
    required this.successCount,
    required this.failureCount,
    required this.avgResponseTime,
    required this.minResponseTime,
    required this.maxResponseTime,
  });

  bool get isComplete => state == 'Complete';
  String get summary => isComplete
      ? '$successCount/${ successCount + failureCount} — avg ${avgResponseTime}ms (min ${minResponseTime}ms, max ${maxResponseTime}ms)'
      : 'حالة: $state';
}

class RouterDetectResult {
  final String ip;
  bool reachable = false;
  int statusCode = 0;
  String brand = 'غير معروف';
  String pageTitle = '';
  String tr069Path = '';
  bool supportsTr069 = true;
  String error = '';

  RouterDetectResult({required this.ip});

  String get acsUrl => GenieAcsService._baseUrl.replaceFirst(':7557', ':7547');
}
