/// Router Adapter Service — إعداد الراوترات تلقائياً عبر API الخاص بكل نوع
/// يدعم: Tenda, Huawei ONU/ONT, TP-Link, ZTE ONU, MikroTik, D-Link, Netis
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// ═══════════════════════════════════════════════════════════
// الواجهة الأساسية — كل adapter يطبّقها
// ═══════════════════════════════════════════════════════════
class RouterSetupResult {
  final bool success;
  final String message;
  final List<String> log;
  RouterSetupResult({required this.success, required this.message, this.log = const []});
}

/// الإعدادات الحالية المقروءة من الراوتر
class RouterCurrentSettings {
  String pppoeUser = '';
  String pppoePass = '';
  String wifiSsid = '';
  String wifiPass = '';
  String wifiSsid5g = '';
  String wanIp = '';
  String lanIp = '';
  String macAddress = '';
  String firmwareVersion = '';
  String model = '';
  bool tr069Enabled = false;
  String tr069AcsUrl = '';
}

abstract class RouterAdapter {
  String get brandName;

  /// تسجيل دخول — يُرجع session/token
  Future<bool> login(String ip, String user, String pass);

  /// قراءة الإعدادات الحالية من الراوتر
  Future<RouterCurrentSettings> readSettings(String ip) async => RouterCurrentSettings();

  /// ضبط PPPoE
  Future<RouterSetupResult> setPppoe(String ip, String pppoeUser, String pppoePass);

  /// ضبط WiFi
  Future<RouterSetupResult> setWifi(String ip, String ssid, String password);

  /// ضبط TR-069
  Future<RouterSetupResult> setTr069(String ip, String acsUrl, {int interval = 300});

  /// تنفيذ كل الإعدادات دفعة واحدة
  Future<RouterSetupResult> setupAll(String ip, String loginUser, String loginPass, {
    String? pppoeUser, String? pppoePass,
    String? wifiSsid, String? wifiPass,
    String? acsUrl,
  }) async {
    final log = <String>[];
    log.add('═══ بدء إعداد $brandName ($ip) ═══');

    // 1. تسجيل الدخول
    log.add('1. تسجيل الدخول بـ $loginUser...');
    final loggedIn = await login(ip, loginUser, loginPass);
    if (!loggedIn) {
      log.add('   ✗ فشل تسجيل الدخول');
      return RouterSetupResult(success: false, message: 'فشل تسجيل الدخول', log: log);
    }
    log.add('   ✓ نجح تسجيل الدخول');

    // 2. PPPoE
    if (pppoeUser != null && pppoeUser.isNotEmpty) {
      log.add('2. إعداد PPPoE: $pppoeUser...');
      final r = await setPppoe(ip, pppoeUser, pppoePass ?? '');
      log.addAll(r.log);
      log.add(r.success ? '   ✓ تم إعداد PPPoE' : '   ✗ فشل إعداد PPPoE');
    }

    // 3. WiFi
    if (wifiSsid != null && wifiSsid.isNotEmpty) {
      log.add('3. إعداد WiFi: $wifiSsid...');
      final r = await setWifi(ip, wifiSsid, wifiPass ?? '');
      log.addAll(r.log);
      log.add(r.success ? '   ✓ تم إعداد WiFi' : '   ✗ فشل إعداد WiFi');
    }

    // 4. TR-069
    if (acsUrl != null && acsUrl.isNotEmpty) {
      log.add('4. إعداد TR-069: $acsUrl...');
      final r = await setTr069(ip, acsUrl);
      log.addAll(r.log);
      log.add(r.success ? '   ✓ تم إعداد TR-069' : '   ✗ فشل إعداد TR-069');
    }

    log.add('═══ تم الإنهاء ═══');
    return RouterSetupResult(success: true, message: 'تم الإعداد بنجاح', log: log);
  }
}

// ═══════════════════════════════════════════════════════════
// Helper — HTTP مشترك
// ═══════════════════════════════════════════════════════════
const _timeout = Duration(seconds: 8);

Map<String, String> _formHeaders(String? cookie) => {
  'Content-Type': 'application/x-www-form-urlencoded',
  if (cookie != null) 'Cookie': cookie,
};

// ═══════════════════════════════════════════════════════════
// 1. TENDA — أبسط API
// ═══════════════════════════════════════════════════════════
class TendaAdapter extends RouterAdapter {
  @override
  String get brandName => 'Tenda';
  String? _cookie;

  @override
  Future<RouterCurrentSettings> readSettings(String ip) async {
    final s = RouterCurrentSettings();
    try {
      // Tenda يُرجع الإعدادات عبر /goform/GetRouterStatus أو /goform/getSysStatusCfg
      final r = await http.get(Uri.parse('http://$ip/goform/getSysStatusCfg'), headers: _formHeaders(_cookie)).timeout(_timeout);
      if (r.statusCode == 200) {
        try {
          final j = jsonDecode(r.body);
          s.wanIp = j['wanIP']?.toString() ?? '';
          s.macAddress = j['wanMAC']?.toString() ?? '';
          s.firmwareVersion = j['softVersion']?.toString() ?? '';
          s.model = j['productModel']?.toString() ?? '';
        } catch (_) {}
      }
      // WiFi
      final r2 = await http.get(Uri.parse('http://$ip/goform/WifiBasicGet'), headers: _formHeaders(_cookie)).timeout(_timeout);
      if (r2.statusCode == 200) {
        try {
          final j = jsonDecode(r2.body);
          s.wifiSsid = j['wifiSSID']?.toString() ?? '';
          s.wifiPass = j['wifiPwd']?.toString() ?? '';
        } catch (_) {}
      }
      // WAN/PPPoE
      final r3 = await http.get(Uri.parse('http://$ip/goform/AdvSetWanGet'), headers: _formHeaders(_cookie)).timeout(_timeout);
      if (r3.statusCode == 200) {
        try {
          final j = jsonDecode(r3.body);
          s.pppoeUser = j['pppoeUser']?.toString() ?? '';
          s.pppoePass = j['pppoePwd']?.toString() ?? '';
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[Tenda] readSettings error: $e');
    }
    return s;
  }

  @override
  Future<bool> login(String ip, String user, String pass) async {
    try {
      // Tenda يستخدم password فقط (بدون username عادةً)
      final r = await http.get(
        Uri.parse('http://$ip/login/Auth?password=${base64Encode(utf8.encode(pass))}'),
      ).timeout(_timeout);
      if (r.statusCode == 200) {
        _cookie = r.headers['set-cookie'];
        final body = r.body;
        // بعض موديلات Tenda تُرجع {"errCode":0} عند النجاح
        if (body.contains('"errCode":0') || body.contains('0') || r.statusCode == 200) {
          return true;
        }
      }
      // محاولة بديلة — بعض الموديلات تستخدم /goform/login
      final r2 = await http.post(Uri.parse('http://$ip/goform/login'),
        headers: _formHeaders(null),
        body: 'username=$user&password=$pass',
      ).timeout(_timeout);
      _cookie = r2.headers['set-cookie'];
      return r2.statusCode == 200 || r2.statusCode == 302;
    } catch (e) {
      debugPrint('[Tenda] login error: $e');
      return false;
    }
  }

  @override
  Future<RouterSetupResult> setPppoe(String ip, String pppoeUser, String pppoePass) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/goform/AdvSetWan'),
        headers: _formHeaders(_cookie),
        body: 'wanMode=pppoe&pppoeUser=$pppoeUser&pppoePwd=$pppoePass&DNS1=8.8.8.8&DNS2=1.1.1.1',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setWifi(String ip, String ssid, String password) async {
    try {
      // 2.4GHz
      final r1 = await http.post(Uri.parse('http://$ip/goform/WifiBasicSet'),
        headers: _formHeaders(_cookie),
        body: 'wifiEn=1&wifiSSID=${Uri.encodeComponent(ssid)}&wifiSecurityMode=WPAWPA2%2FAES&wifiPwd=${Uri.encodeComponent(password)}',
      ).timeout(_timeout);
      // 5GHz (إذا يدعم)
      try {
        await http.post(Uri.parse('http://$ip/goform/WifiBasicSet'),
          headers: _formHeaders(_cookie),
          body: 'wifiEn=1&wifiSSID=${Uri.encodeComponent('${ssid}_5G')}&wifiSecurityMode=WPAWPA2%2FAES&wifiPwd=${Uri.encodeComponent(password)}&wifiBand=5',
        ).timeout(_timeout);
      } catch (_) {}
      return RouterSetupResult(success: r1.statusCode == 200, message: 'HTTP ${r1.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setTr069(String ip, String acsUrl, {int interval = 300}) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/goform/setTR069'),
        headers: _formHeaders(_cookie),
        body: 'tr069Enable=1&acsUrl=${Uri.encodeComponent(acsUrl)}&informInterval=$interval&tr069User=&tr069Pwd=',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 2. HUAWEI ONU/ONT (HG8xxx, EchoLife)
// ═══════════════════════════════════════════════════════════
class HuaweiAdapter extends RouterAdapter {
  @override
  String get brandName => 'Huawei ONU/ONT';
  String? _cookie;
  String? _hwToken;

  @override
  Future<RouterCurrentSettings> readSettings(String ip) async {
    final s = RouterCurrentSettings();
    try {
      // Huawei يقرأ من صفحات asp
      final r = await http.get(Uri.parse('http://$ip/html/status/wan/wan_ether_info_t.asp'), headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) {
        final body = r.body;
        s.pppoeUser = _extract(body, 'Username') ?? '';
        s.wanIp = _extract(body, 'IPAddress') ?? _extract(body, 'ExternalIPAddress') ?? '';
      }
      // WiFi
      final r2 = await http.get(Uri.parse('http://$ip/html/ssmp/wlan/wlan_basic_t.asp'), headers: _headers).timeout(_timeout);
      if (r2.statusCode == 200) {
        s.wifiSsid = _extract(r2.body, 'SSID') ?? _extract(r2.body, 'WlanSSID') ?? '';
      }
      // DeviceInfo
      final r3 = await http.get(Uri.parse('http://$ip/html/status/deviceinformation_t.asp'), headers: _headers).timeout(_timeout);
      if (r3.statusCode == 200) {
        s.firmwareVersion = _extract(r3.body, 'SoftwareVersion') ?? '';
        s.model = _extract(r3.body, 'ModelName') ?? _extract(r3.body, 'DeviceName') ?? '';
        s.macAddress = _extract(r3.body, 'MACAddress') ?? '';
      }
    } catch (e) {
      debugPrint('[Huawei] readSettings error: $e');
    }
    return s;
  }

  static String? _extract(String body, String key) {
    // يبحث عن key="value" أو key = 'value' أو Transfer("key","value")
    final patterns = [
      RegExp('$key["\']?\\s*[:=]\\s*["\']([^"\']+)["\']', caseSensitive: false),
      RegExp('Transfer\\([^)]*"$key"\\s*,\\s*"([^"]*)"', caseSensitive: false),
      RegExp('"$key"\\s*:\\s*"([^"]*)"', caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(body);
      if (m != null && m.group(1)!.isNotEmpty) return m.group(1);
    }
    return null;
  }

  @override
  Future<bool> login(String ip, String user, String pass) async {
    try {
      // الخطوة 1: جلب token
      final r1 = await http.get(Uri.parse('http://$ip/asp/GetRandCount')).timeout(_timeout);
      _cookie = r1.headers['set-cookie'];

      // الخطوة 2: تسجيل الدخول
      final r2 = await http.post(Uri.parse('http://$ip/login.cgi'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          if (_cookie != null) 'Cookie': _cookie!,
          'Referer': 'http://$ip/',
        },
        body: 'UserName=$user&PassWord=${base64Encode(utf8.encode(pass))}&x.X_HW_Token=${r1.body.trim()}',
      ).timeout(_timeout);

      if (r2.statusCode == 200 || r2.statusCode == 302) {
        // تحديث الكوكيز
        final newCookie = r2.headers['set-cookie'];
        if (newCookie != null) _cookie = newCookie;
        _hwToken = r1.body.trim();
        return true;
      }

      // محاولة بديلة — بعض الموديلات
      final r3 = await http.post(Uri.parse('http://$ip/'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'Username=$user&Password=$pass&action=login',
      ).timeout(_timeout);
      _cookie = r3.headers['set-cookie'];
      return r3.statusCode == 200 || r3.statusCode == 302;
    } catch (e) {
      debugPrint('[Huawei] login error: $e');
      return false;
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/x-www-form-urlencoded',
    if (_cookie != null) 'Cookie': _cookie!,
    if (_hwToken != null) 'X-HW-Token': _hwToken!,
  };

  @override
  Future<RouterSetupResult> setPppoe(String ip, String pppoeUser, String pppoePass) async {
    try {
      // Huawei يستخدم asp/SetWAN أو مسارات مختلفة
      final r = await http.post(Uri.parse('http://$ip/html/network/set.cgi'),
        headers: _headers,
        body: 'x.X_HW_WebUserName=$pppoeUser&x.X_HW_WebUserPassword=$pppoePass&x.ConnectionType=PPPoE_Routed',
      ).timeout(_timeout);
      if (r.statusCode == 200) return RouterSetupResult(success: true, message: 'OK');

      // مسار بديل
      final r2 = await http.post(Uri.parse('http://$ip/asp/SetWAN'),
        headers: _headers,
        body: 'IF_ACTION=Apply&WANMODE=PPPoE&USERNAME=$pppoeUser&PASSWORD=$pppoePass',
      ).timeout(_timeout);
      return RouterSetupResult(success: r2.statusCode == 200, message: 'HTTP ${r2.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setWifi(String ip, String ssid, String password) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/html/ssmp/wlan/set.cgi'),
        headers: _headers,
        body: 'x.X_HW_WlanSSID=${Uri.encodeComponent(ssid)}&x.X_HW_WpaPreSharedKey=${Uri.encodeComponent(password)}&x.Enable=1',
      ).timeout(_timeout);
      if (r.statusCode == 200) return RouterSetupResult(success: true, message: 'OK');

      final r2 = await http.post(Uri.parse('http://$ip/asp/SetWLAN'),
        headers: _headers,
        body: 'IF_ACTION=Apply&SSID=${Uri.encodeComponent(ssid)}&WPAPreSharedKey=${Uri.encodeComponent(password)}&Enable=1',
      ).timeout(_timeout);
      return RouterSetupResult(success: r2.statusCode == 200, message: 'HTTP ${r2.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setTr069(String ip, String acsUrl, {int interval = 300}) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/html/amp/set.cgi'),
        headers: _headers,
        body: 'x.URL=${Uri.encodeComponent(acsUrl)}&x.PeriodicInformEnable=1&x.PeriodicInformInterval=$interval&x.Username=&x.Password=',
      ).timeout(_timeout);
      if (r.statusCode == 200) return RouterSetupResult(success: true, message: 'OK');

      final r2 = await http.post(Uri.parse('http://$ip/asp/SetTR069'),
        headers: _headers,
        body: 'IF_ACTION=Apply&URL=${Uri.encodeComponent(acsUrl)}&PeriodicInformEnable=1&PeriodicInformInterval=$interval',
      ).timeout(_timeout);
      return RouterSetupResult(success: r2.statusCode == 200, message: 'HTTP ${r2.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 3. TP-LINK (Archer, TL-WR, TL-MR)
// ═══════════════════════════════════════════════════════════
class TpLinkAdapter extends RouterAdapter {
  @override
  String get brandName => 'TP-Link';
  String? _stok; // session token
  String? _cookie;

  @override
  Future<RouterCurrentSettings> readSettings(String ip) async {
    final s = RouterCurrentSettings();
    try {
      if (_stok != null) {
        // Modern TP-Link API
        final r = await http.post(Uri.parse('http://$ip$_baseApi/admin/status?form=all'), headers: _headers,
          body: jsonEncode({'method': 'get'})).timeout(_timeout);
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body);
          final data = j['result'] ?? j;
          s.wanIp = data['wan_ipv4_ipaddr']?.toString() ?? '';
          s.macAddress = data['mac']?.toString() ?? '';
          s.firmwareVersion = data['firmware_version']?.toString() ?? '';
          s.model = data['model']?.toString() ?? '';
        }
        // WiFi
        final r2 = await http.post(Uri.parse('http://$ip$_baseApi/admin/wireless?form=wireless_2g'), headers: _headers,
          body: jsonEncode({'method': 'get'})).timeout(_timeout);
        if (r2.statusCode == 200) {
          final j = jsonDecode(r2.body);
          final data = j['result'] ?? j;
          s.wifiSsid = data['ssid']?.toString() ?? '';
        }
        // WAN
        final r3 = await http.post(Uri.parse('http://$ip$_baseApi/admin/network?form=wan_ipv4'), headers: _headers,
          body: jsonEncode({'method': 'get'})).timeout(_timeout);
        if (r3.statusCode == 200) {
          final j = jsonDecode(r3.body);
          final data = j['result'] ?? j;
          s.pppoeUser = data['username']?.toString() ?? '';
        }
      }
    } catch (e) {
      debugPrint('[TP-Link] readSettings error: $e');
    }
    return s;
  }

  @override
  Future<bool> login(String ip, String user, String pass) async {
    try {
      // TP-Link الحديثة: Basic Auth أو form login
      // محاولة 1: Basic Auth
      final creds = base64Encode(utf8.encode('$user:$pass'));
      final r1 = await http.get(Uri.parse('http://$ip/'),
        headers: {'Authorization': 'Basic $creds'},
      ).timeout(_timeout);
      if (r1.statusCode == 200 && !r1.body.contains('loginErr') && !r1.body.contains('password')) {
        _cookie = r1.headers['set-cookie'];
        // استخراج stok من URL أو body
        final stokMatch = RegExp(r'stok=([a-f0-9]+)').firstMatch(r1.body);
        if (stokMatch != null) _stok = stokMatch.group(1);
        return true;
      }

      // محاولة 2: Form-based login (موديلات حديثة)
      final r2 = await http.post(Uri.parse('http://$ip/cgi-bin/luci/;stok=/login?form=login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'method': 'login', 'params': {'password': pass}}),
      ).timeout(_timeout);
      if (r2.statusCode == 200) {
        final json = jsonDecode(r2.body);
        if (json is Map && json['result'] != null) {
          _stok = json['result']['stok']?.toString();
          _cookie = r2.headers['set-cookie'];
          return _stok != null;
        }
      }

      // محاولة 3: Old style TP-Link
      final encodedAuth = base64Encode(utf8.encode('$user:$pass'));
      final r3 = await http.get(Uri.parse('http://$ip/userRpm/LoginRpm.htm?Save=Save'),
        headers: {'Authorization': 'Basic $encodedAuth', 'Cookie': 'Authorization=Basic%20$encodedAuth'},
      ).timeout(_timeout);
      _cookie = 'Authorization=Basic%20$encodedAuth';
      return r3.statusCode == 200;
    } catch (e) {
      debugPrint('[TP-Link] login error: $e');
      return false;
    }
  }

  String get _baseApi => _stok != null ? '/cgi-bin/luci/;stok=$_stok' : '';

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_cookie != null) 'Cookie': _cookie!,
  };

  @override
  Future<RouterSetupResult> setPppoe(String ip, String pppoeUser, String pppoePass) async {
    try {
      // Modern TP-Link API
      if (_stok != null) {
        final r = await http.post(Uri.parse('http://$ip$_baseApi/admin/network?form=wan_ipv4'),
          headers: _headers,
          body: jsonEncode({'method': 'set', 'params': {'proto': 'pppoe', 'username': pppoeUser, 'password': pppoePass}}),
        ).timeout(_timeout);
        if (r.statusCode == 200) return RouterSetupResult(success: true, message: 'OK');
      }
      // Old style
      final r2 = await http.get(
        Uri.parse('http://$ip/userRpm/PPPoECfgRpm.htm?wan=0&wantype=2&acc=$pppoeUser&psw=$pppoePass&confirm=$pppoePass&SecType=0&sta_ip=0.0.0.0&sta_mask=0.0.0.0&linktype=2&Save=Save'),
        headers: {'Cookie': _cookie ?? ''},
      ).timeout(_timeout);
      return RouterSetupResult(success: r2.statusCode == 200, message: 'HTTP ${r2.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setWifi(String ip, String ssid, String password) async {
    try {
      if (_stok != null) {
        // 2.4GHz
        await http.post(Uri.parse('http://$ip$_baseApi/admin/wireless?form=wireless_2g'),
          headers: _headers,
          body: jsonEncode({'method': 'set', 'params': {'ssid': ssid, 'psk_key': password, 'psk_cipher': 'aes', 'encryption': 'psk', 'psk_version': 'auto'}}),
        ).timeout(_timeout);
        // 5GHz
        await http.post(Uri.parse('http://$ip$_baseApi/admin/wireless?form=wireless_5g'),
          headers: _headers,
          body: jsonEncode({'method': 'set', 'params': {'ssid': '${ssid}_5G', 'psk_key': password, 'psk_cipher': 'aes', 'encryption': 'psk', 'psk_version': 'auto'}}),
        ).timeout(_timeout);
        return RouterSetupResult(success: true, message: 'OK');
      }
      // Old style
      final r = await http.get(
        Uri.parse('http://$ip/userRpm/WlanNetworkRpm.htm?ssid=${Uri.encodeComponent(ssid)}&psk=${Uri.encodeComponent(password)}&Save=Save'),
        headers: {'Cookie': _cookie ?? ''},
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setTr069(String ip, String acsUrl, {int interval = 300}) async {
    try {
      if (_stok != null) {
        final r = await http.post(Uri.parse('http://$ip$_baseApi/admin/system?form=cwmp'),
          headers: _headers,
          body: jsonEncode({'method': 'set', 'params': {'enable': true, 'url': acsUrl, 'inform_enable': true, 'inform_interval': interval, 'username': '', 'password': ''}}),
        ).timeout(_timeout);
        return RouterSetupResult(success: r.statusCode == 200, message: 'OK');
      }
      // Old style
      final r = await http.get(
        Uri.parse('http://$ip/userRpm/Tr069CfgRpm.htm?Enable=1&URL=${Uri.encodeComponent(acsUrl)}&InformEnable=1&InformInterval=$interval&Save=Save'),
        headers: {'Cookie': _cookie ?? ''},
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 4. ZTE ONU/ONT (ZXHN F660, F670, etc.)
// ═══════════════════════════════════════════════════════════
class ZteAdapter extends RouterAdapter {
  @override
  String get brandName => 'ZTE ONU/ONT';
  String? _cookie;
  String? _sessionToken;

  @override
  Future<RouterCurrentSettings> readSettings(String ip) async {
    final s = RouterCurrentSettings();
    try {
      final r = await http.get(Uri.parse('http://$ip/getpage.gch?pid=1002&nextpage=status_wan_info_t.gch'), headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) {
        final body = r.body;
        final ipMatch = RegExp("IP[Aa]ddress[\"\\s:=]+[\"']?(\\d+\\.\\d+\\.\\d+\\.\\d+)").firstMatch(body);
        if (ipMatch != null) s.wanIp = ipMatch.group(1)!;
        final userMatch = RegExp("[Uu]sername[\"\\s:=]+[\"']?([^\"'<\\s]+)").firstMatch(body);
        if (userMatch != null) s.pppoeUser = userMatch.group(1)!;
      }
      final r2 = await http.get(Uri.parse('http://$ip/getpage.gch?pid=1002&nextpage=net_wlanm_essid1_t.gch'), headers: _headers).timeout(_timeout);
      if (r2.statusCode == 200) {
        final ssidMatch = RegExp("ESSID[\"\\s:=]+[\"']?([^\"'<]+)").firstMatch(r2.body);
        if (ssidMatch != null) s.wifiSsid = ssidMatch.group(1)!.trim();
      }
    } catch (e) {
      debugPrint('[ZTE] readSettings error: $e');
    }
    return s;
  }

  @override
  Future<bool> login(String ip, String user, String pass) async {
    try {
      // ZTE login
      final r = await http.post(Uri.parse('http://$ip/'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'action=login&Username=$user&Password=$pass&Frm_Logintoken=',
      ).timeout(_timeout);
      _cookie = r.headers['set-cookie'];

      if (r.statusCode == 302 || (r.statusCode == 200 && !r.body.contains('error'))) {
        // استخراج session token
        final tokenMatch = RegExp(r'Frm_Logintoken\s*=\s*"?(\d+)"?').firstMatch(r.body);
        _sessionToken = tokenMatch?.group(1);
        return true;
      }

      // محاولة بديلة
      final r2 = await http.post(Uri.parse('http://$ip/getpage.gch?pid=1001'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'frashnum=&action=login&Frm_Logintoken=&Username=$user&Password=$pass',
      ).timeout(_timeout);
      _cookie = r2.headers['set-cookie'];
      return r2.statusCode == 200 || r2.statusCode == 302;
    } catch (e) {
      debugPrint('[ZTE] login error: $e');
      return false;
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/x-www-form-urlencoded',
    if (_cookie != null) 'Cookie': _cookie!,
  };

  @override
  Future<RouterSetupResult> setPppoe(String ip, String pppoeUser, String pppoePass) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/getpage.gch?pid=1002&nextpage=net_wancfg_t.gch'),
        headers: _headers,
        body: 'IF_ACTION=Apply&Ession_Token=${_sessionToken ?? ""}&WAN_Mode=PPPoE&PPPoE_Username=$pppoeUser&PPPoE_Password=$pppoePass',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setWifi(String ip, String ssid, String password) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/getpage.gch?pid=1002&nextpage=net_wlanm_essid1_t.gch'),
        headers: _headers,
        body: 'IF_ACTION=Apply&Ession_Token=${_sessionToken ?? ""}&ESSID=${Uri.encodeComponent(ssid)}&PreSharedKey=${Uri.encodeComponent(password)}&HideSSID=0&Enable=1',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setTr069(String ip, String acsUrl, {int interval = 300}) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/getpage.gch?pid=1002&nextpage=management_tr069_t.gch'),
        headers: _headers,
        body: 'IF_ACTION=Apply&Ession_Token=${_sessionToken ?? ""}&ACS_URL=${Uri.encodeComponent(acsUrl)}&InformEnable=1&InformInterval=$interval&ACS_UserName=&ACS_Password=',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 5. MIKROTIK (RouterOS REST API)
// ═══════════════════════════════════════════════════════════
class MikrotikAdapter extends RouterAdapter {
  @override
  String get brandName => 'MikroTik';
  String _auth = '';

  @override
  Future<RouterCurrentSettings> readSettings(String ip) async {
    final s = RouterCurrentSettings();
    try {
      final r = await http.get(Uri.parse('http://$ip/rest/system/resource'), headers: _headers).timeout(_timeout);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        s.firmwareVersion = j['version']?.toString() ?? '';
        s.model = j['board-name']?.toString() ?? '';
      }
      final r2 = await http.get(Uri.parse('http://$ip/rest/interface/pppoe-client'), headers: _headers).timeout(_timeout);
      if (r2.statusCode == 200) {
        final list = jsonDecode(r2.body);
        if (list is List && list.isNotEmpty) {
          s.pppoeUser = list.first['user']?.toString() ?? '';
        }
      }
      final r3 = await http.get(Uri.parse('http://$ip/rest/ip/address'), headers: _headers).timeout(_timeout);
      if (r3.statusCode == 200) {
        final list = jsonDecode(r3.body);
        if (list is List) {
          for (final addr in list) {
            if (addr['dynamic'] == true || addr['interface']?.toString().contains('pppoe') == true) {
              s.wanIp = addr['address']?.toString().split('/').first ?? '';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MikroTik] readSettings error: $e');
    }
    return s;
  }

  @override
  Future<bool> login(String ip, String user, String pass) async {
    try {
      _auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
      final r = await http.get(Uri.parse('http://$ip/rest/system/resource'),
        headers: {'Authorization': _auth},
      ).timeout(_timeout);
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('[MikroTik] login error: $e');
      return false;
    }
  }

  Map<String, String> get _headers => {
    'Authorization': _auth,
    'Content-Type': 'application/json',
  };

  @override
  Future<RouterSetupResult> setPppoe(String ip, String pppoeUser, String pppoePass) async {
    try {
      final r = await http.put(Uri.parse('http://$ip/rest/interface/pppoe-client'),
        headers: _headers,
        body: jsonEncode({'name': 'pppoe-out1', 'interface': 'ether1', 'user': pppoeUser, 'password': pppoePass, 'disabled': 'no'}),
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200 || r.statusCode == 201, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setWifi(String ip, String ssid, String password) async {
    try {
      // RouterOS 7+ WiFi
      final r = await http.patch(Uri.parse('http://$ip/rest/interface/wifi'),
        headers: _headers,
        body: jsonEncode({'.id': '*1', 'configuration.ssid': ssid, 'security.passphrase': password}),
      ).timeout(_timeout);
      if (r.statusCode == 200) return RouterSetupResult(success: true, message: 'OK');

      // RouterOS 6 wireless
      final r2 = await http.patch(Uri.parse('http://$ip/rest/interface/wireless'),
        headers: _headers,
        body: jsonEncode({'.id': '*1', 'ssid': ssid}),
      ).timeout(_timeout);
      return RouterSetupResult(success: r2.statusCode == 200, message: 'HTTP ${r2.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setTr069(String ip, String acsUrl, {int interval = 300}) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/rest/tr069-client/set'),
        headers: _headers,
        body: jsonEncode({'acs-url': acsUrl, 'enabled': 'yes', 'periodic-inform-enabled': 'yes', 'periodic-inform-interval': '${interval}s'}),
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 6. D-LINK
// ═══════════════════════════════════════════════════════════
class DlinkAdapter extends RouterAdapter {
  @override
  String get brandName => 'D-Link';
  String? _cookie;

  @override
  Future<bool> login(String ip, String user, String pass) async {
    try {
      final creds = base64Encode(utf8.encode('$user:$pass'));
      final r = await http.get(Uri.parse('http://$ip/'),
        headers: {'Authorization': 'Basic $creds'},
      ).timeout(_timeout);
      _cookie = r.headers['set-cookie'] ?? 'uid=Basic%20$creds';
      return r.statusCode == 200;
    } catch (e) {
      debugPrint('[D-Link] login error: $e');
      return false;
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/x-www-form-urlencoded',
    if (_cookie != null) 'Cookie': _cookie!,
  };

  @override
  Future<RouterSetupResult> setPppoe(String ip, String pppoeUser, String pppoePass) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/wan_pppoe.cgi'),
        headers: _headers,
        body: 'pppoeUser=$pppoeUser&pppoePass=$pppoePass&pppoeMode=KeepAlive&Apply=Apply',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setWifi(String ip, String ssid, String password) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/wlan_basic.cgi'),
        headers: _headers,
        body: 'SSID=${Uri.encodeComponent(ssid)}&WPAKey=${Uri.encodeComponent(password)}&security_type=WPA2&Apply=Apply',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setTr069(String ip, String acsUrl, {int interval = 300}) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/tr069_cfg.cgi'),
        headers: _headers,
        body: 'enable=1&acs_url=${Uri.encodeComponent(acsUrl)}&inform_enable=1&inform_interval=$interval&Apply=Apply',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 7. NETIS
// ═══════════════════════════════════════════════════════════
class NetisAdapter extends RouterAdapter {
  @override
  String get brandName => 'Netis';
  String? _cookie;

  @override
  Future<bool> login(String ip, String user, String pass) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/cgi-bin-igd/login.cgi'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'username=$user&password=$pass',
      ).timeout(_timeout);
      _cookie = r.headers['set-cookie'];
      return r.statusCode == 200 || r.statusCode == 302;
    } catch (e) {
      debugPrint('[Netis] login error: $e');
      return false;
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/x-www-form-urlencoded',
    if (_cookie != null) 'Cookie': _cookie!,
  };

  @override
  Future<RouterSetupResult> setPppoe(String ip, String pppoeUser, String pppoePass) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/cgi-bin-igd/wan_ppp.cgi'),
        headers: _headers,
        body: 'pppUser=$pppoeUser&pppPass=$pppoePass&wanType=pppoe&Submit=Apply',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setWifi(String ip, String ssid, String password) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/cgi-bin-igd/wlan_basic.cgi'),
        headers: _headers,
        body: 'SSID=${Uri.encodeComponent(ssid)}&PreSharedKey=${Uri.encodeComponent(password)}&Submit=Apply',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }

  @override
  Future<RouterSetupResult> setTr069(String ip, String acsUrl, {int interval = 300}) async {
    try {
      final r = await http.post(Uri.parse('http://$ip/cgi-bin-igd/tr069.cgi'),
        headers: _headers,
        body: 'enable=1&acsURL=${Uri.encodeComponent(acsUrl)}&informEnable=1&informInterval=$interval&Submit=Apply',
      ).timeout(_timeout);
      return RouterSetupResult(success: r.statusCode == 200, message: 'HTTP ${r.statusCode}');
    } catch (e) {
      return RouterSetupResult(success: false, message: e.toString());
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Factory — يختار الـ Adapter حسب نوع الراوتر
// ═══════════════════════════════════════════════════════════
class RouterAdapterFactory {
  static RouterAdapter? getAdapter(String brand) {
    final b = brand.toLowerCase();
    if (b.contains('tenda')) return TendaAdapter();
    if (b.contains('huawei') || b.contains('onu') || b.contains('ont') || b.contains('echolife')) return HuaweiAdapter();
    if (b.contains('tp-link') || b.contains('tplink') || b.contains('archer')) return TpLinkAdapter();
    if (b.contains('zte') || b.contains('zxhn')) return ZteAdapter();
    if (b.contains('mikrotik') || b.contains('routeros')) return MikrotikAdapter();
    if (b.contains('d-link') || b.contains('dlink')) return DlinkAdapter();
    if (b.contains('netis')) return NetisAdapter();
    return null;
  }

  static List<String> get supportedBrands => ['Tenda', 'Huawei ONU/ONT', 'TP-Link', 'ZTE ONU/ONT', 'MikroTik', 'D-Link', 'Netis'];
}
