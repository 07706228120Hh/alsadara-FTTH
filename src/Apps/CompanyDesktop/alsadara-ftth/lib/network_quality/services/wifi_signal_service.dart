/// خدمة قراءة إشارة WiFi — Network Quality
///
/// Android: عبر قناة native (com.alsadara.ftth_project/netquality) تقرأ RSSI
/// وسرعة الوصلة والتردّد من WifiManager.
/// Windows: عبر `netsh wlan show interfaces` (لا يحتاج صلاحيات خاصة).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/quality_models.dart';

class WifiSignalService {
  static const _channel = MethodChannel('com.alsadara.ftth_project/netquality');

  static Future<WifiSignalInfo> read() async {
    try {
      if (Platform.isAndroid) return await _android();
      if (Platform.isWindows) return await _windows();
    } catch (e) {
      debugPrint('[WiFi] read error: $e');
      return WifiSignalInfo(error: e.toString());
    }
    return WifiSignalInfo.none;
  }

  static Future<WifiSignalInfo> _android() async {
    try {
      final res = await _channel
          .invokeMapMethod<String, dynamic>('getWifiInfo')
          .timeout(const Duration(seconds: 6));
      if (res == null) return WifiSignalInfo.none;
      final connected = res['connected'] == true;
      if (!connected) return const WifiSignalInfo(connectedViaWifi: false);
      final freq = _asInt(res['frequency']);
      return WifiSignalInfo(
        connectedViaWifi: true,
        ssid: (res['ssid'] ?? '').toString().replaceAll('"', ''),
        bssid: (res['bssid'] ?? '').toString(),
        rssiDbm: _asInt(res['rssi']),
        signalPercent: _asInt(res['signalLevel']),
        linkSpeedMbps: _asInt(res['linkSpeed']),
        frequencyMhz: freq,
        band: _band(freq),
        channel: _channelFromFreq(freq),
      );
    } on PlatformException catch (e) {
      debugPrint('[WiFi] android platform error: $e');
      return WifiSignalInfo(error: e.message ?? 'تعذّر قراءة WiFi');
    } on MissingPluginException {
      // القناة غير مسجّلة (نسخة قديمة) — تجاهُل آمن.
      return WifiSignalInfo.none;
    }
  }

  static Future<WifiSignalInfo> _windows() async {
    final r = await Process.run(
      'netsh',
      ['wlan', 'show', 'interfaces'],
      stdoutEncoding: const SystemEncoding(),
    ).timeout(const Duration(seconds: 6));
    final out = r.stdout.toString();
    if (out.trim().isEmpty || !out.contains(':')) {
      return const WifiSignalInfo(connectedViaWifi: false);
    }

    String grab(List<String> keys) {
      for (final line in out.split('\n')) {
        final idx = line.indexOf(':');
        if (idx < 0) continue;
        final k = line.substring(0, idx).trim().toLowerCase();
        if (keys.any((key) => k == key || k.startsWith(key))) {
          return line.substring(idx + 1).trim();
        }
      }
      return '';
    }

    final ssid = grab(['ssid']);
    final state = grab(['state', 'الحالة']);
    if (ssid.isEmpty && !state.toLowerCase().contains('connect')) {
      return const WifiSignalInfo(connectedViaWifi: false);
    }

    final signalStr = grab(['signal', 'الإشارة']); // مثل "82%"
    int? percent = int.tryParse(signalStr.replaceAll(RegExp(r'[^0-9]'), ''));
    // تقدير RSSI من النسبة: 100% ≈ -30dBm، 0% ≈ -90dBm.
    int? rssi;
    if (percent != null) rssi = (percent / 2 - 90).round();

    final rx = grab(['receive rate (mbps)', 'receive rate']);
    final tx = grab(['transmit rate (mbps)', 'transmit rate']);
    final linkSpeed = int.tryParse(
        (rx.isNotEmpty ? rx : tx).replaceAll(RegExp(r'[^0-9]'), ''));
    final radio = grab(['radio type']);
    final band = grab(['band']); // ويندوز 11 يعرض Band أحياناً
    final channelStr = grab(['channel', 'القناة']);

    return WifiSignalInfo(
      connectedViaWifi: true,
      ssid: ssid,
      bssid: grab(['bssid', 'ap bssid']),
      rssiDbm: rssi,
      signalPercent: percent,
      linkSpeedMbps: linkSpeed,
      band: band.isNotEmpty
          ? band
          : (channelStr.isNotEmpty
              ? _bandFromChannel(int.tryParse(channelStr))
              : (radio.contains('ax') || radio.contains('ac') ? '5GHz' : '')),
      channel: int.tryParse(channelStr),
    );
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v.toString());
  }

  static String _band(int? freqMhz) {
    if (freqMhz == null) return '';
    if (freqMhz >= 5900) return '6GHz';
    if (freqMhz >= 4900) return '5GHz';
    if (freqMhz >= 2400) return '2.4GHz';
    return '';
  }

  static String _bandFromChannel(int? ch) {
    if (ch == null) return '';
    return ch > 14 ? '5GHz' : '2.4GHz';
  }

  static int? _channelFromFreq(int? freqMhz) {
    if (freqMhz == null) return null;
    if (freqMhz >= 2412 && freqMhz <= 2484) {
      if (freqMhz == 2484) return 14;
      return ((freqMhz - 2412) ~/ 5) + 1;
    }
    if (freqMhz >= 5000 && freqMhz <= 5900) {
      return (freqMhz - 5000) ~/ 5;
    }
    return null;
  }
}
