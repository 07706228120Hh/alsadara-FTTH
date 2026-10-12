/// محرّك اكتشاف أجهزة الشبكة — Network Quality
///
/// يكتشف الأجهزة على الشبكة المحلية عبر: كشف البوّابة + جدول ARP + مسح عناوين
/// الويب الشائعة + عناوين ONU المعروفة + كشف Double-NAT. يميّز الماركة من الـMAC
/// (OUI) ومن عنوان صفحة الويب.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/device_models.dart';
import 'oui_service.dart';

class DeviceDiscoveryService {
  /// عناوين ONU/الراوتر الشائعة التي تملك واجهات ويب.
  static const _commonUiIps = [
    '192.168.1.1',
    '192.168.0.1',
    '192.168.100.1', // Huawei ONU
    '192.168.101.1',
    '192.168.31.1', // Xiaomi
    '192.168.88.1', // MikroTik
    '10.0.0.1',
    '192.168.2.1',
  ];

  /// كلمات مفتاحية لتمييز الماركة من صفحة الويب.
  static const Map<String, List<String>> _brandKeywords = {
    'Huawei': ['huawei', 'hg8', 'hg6', 'echolife', 'smartax'],
    'ZTE': ['zte', 'zxhn', 'zxa10', 'f660', 'f670'],
    'TP-Link': ['tp-link', 'tplink', 'archer', 'tl-wr'],
    'Tenda': ['tenda'],
    'D-Link': ['d-link', 'dlink', 'dir-'],
    'MikroTik': ['mikrotik', 'routeros'],
    'Netis': ['netis'],
    'Nokia': ['nokia', 'alcatel', 'g-240'],
  };

  void Function(String status)? onStatus;

  Future<DiscoveryResult> discover({bool scanClients = true}) async {
    await OuiService.ensureLoaded();
    final byIp = <String, NetworkDevice>{};

    // 1) البوّابة
    _status('كشف بوّابة الشبكة...');
    final gateway = await _detectGateway();

    // 2) جدول ARP — كل الأجهزة على الشبكة (أقوى على ويندوز)
    if (scanClients) {
      _status('قراءة جدول ARP...');
      final arp = await _arpTable();
      for (final e in arp) {
        final d = byIp.putIfAbsent(e.key, () => NetworkDevice(ip: e.key));
        d.mac = e.value;
        d.vendor = OuiService.lookup(e.value);
        d.type = DeviceType.client; // مبدئياً
      }
    }

    // 3) المرشّحون لواجهات الويب (ONU/راوترات)
    final uiCandidates = <String>{
      ..._commonUiIps,
      if (gateway != null) gateway,
      // عناوين من نفس شبكة البوّابة (.1)
      if (gateway != null) _sameSubnetBase(gateway),
    }..removeWhere((e) => e.isEmpty);
    // أضف من ARP أيضاً (قد يكون جهاز بنية بعنوان غير شائع)
    uiCandidates.addAll(byIp.keys);

    _status('فحص واجهات الأجهزة (${uiCandidates.length})...');
    final probes = await _probeMany(uiCandidates.toList());
    for (final p in probes) {
      if (p == null) continue;
      final d = byIp.putIfAbsent(p.ip, () => NetworkDevice(ip: p.ip));
      d.hasWebUi = true;
      d.pageTitle = p.pageTitle;
      if (p.brand.isNotEmpty) d.brandGuess = p.brand;
      if (d.mac.isNotEmpty && d.vendor.isEmpty) {
        d.vendor = OuiService.lookup(d.mac);
      }
      if (d.brandGuess.isEmpty && d.vendor.isNotEmpty) d.brandGuess = d.vendor;
    }

    // 4) التصنيف
    for (final d in byIp.values) {
      d.isGateway = gateway != null && d.ip == gateway;
      final brandLower = '${d.brandGuess} ${d.vendor}'.toLowerCase();
      final onuBrand = brandLower.contains('huawei') ||
          brandLower.contains('zte') ||
          brandLower.contains('nokia') ||
          brandLower.contains('alcatel');
      final onuIpLike = d.ip.endsWith('.100.1') || d.ip.endsWith('.101.1');
      d.isOnu = (onuBrand && d.hasWebUi) || onuIpLike;

      if (d.isOnu) {
        d.type = DeviceType.onu;
      } else if (d.isGateway) {
        d.type = DeviceType.router;
      } else if (d.hasWebUi) {
        d.type = DeviceType.accessPoint; // جهاز بنية آخر بواجهة ويب
      } else if (d.mac.isNotEmpty) {
        d.type = DeviceType.client;
      }
    }

    // 5) كشف Double-NAT: بوّابة راوتر + ONU منفصل على شبكة أخرى
    String? onuIp;
    bool doubleNat = false;
    final onu = byIp.values.where((d) => d.isOnu).toList();
    if (onu.isNotEmpty) {
      onuIp = onu.first.ip;
      if (gateway != null && onuIp != gateway) {
        final gwSub = _subnetOf(gateway);
        final onuSub = _subnetOf(onuIp);
        if (gwSub != onuSub) doubleNat = true;
      }
    }

    // ترتيب: البنية أولاً ثم العملاء
    final devices = byIp.values.toList()
      ..sort((a, b) {
        int rank(NetworkDevice d) {
          if (d.isOnu) return 0;
          if (d.isGateway) return 1;
          if (d.hasWebUi) return 2;
          return 3;
        }

        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.ip.compareTo(b.ip);
      });

    final note = devices.isEmpty
        ? 'لم تُكتشف أجهزة — تأكد من الاتصال بشبكة الراوتر.'
        : 'عُثر على ${devices.length} جهاز'
            '${doubleNat ? ' (ONU منفصل خلف الراوتر — Double NAT)' : ''}.';
    _status(note);

    return DiscoveryResult(
      devices: devices,
      gatewayIp: gateway,
      onuIp: onuIp,
      doubleNat: doubleNat,
      note: note,
    );
  }

  // ═══════════════ ARP ═══════════════
  static Future<List<MapEntry<String, String>>> _arpTable() async {
    final out = <String, String>{};
    try {
      if (Platform.isWindows) {
        final r = await Process.run('arp', ['-a'],
                stdoutEncoding: const SystemEncoding())
            .timeout(const Duration(seconds: 8));
        final reg = RegExp(
            r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+([0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2})');
        for (final m in reg.allMatches(r.stdout.toString())) {
          final ip = m.group(1)!;
          final mac = m.group(2)!.replaceAll('-', ':').toLowerCase();
          if (!mac.startsWith('ff:ff') && !ip.endsWith('.255')) {
            out[ip] = mac;
          }
        }
      } else {
        // Android/Linux: جرّب /proc/net/arp
        try {
          final f = File('/proc/net/arp');
          if (await f.exists()) {
            final lines = await f.readAsLines();
            for (final line in lines.skip(1)) {
              final parts = line.split(RegExp(r'\s+'));
              if (parts.length >= 4) {
                final ip = parts[0];
                final mac = parts[3].toLowerCase();
                if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(ip) &&
                    mac != '00:00:00:00:00:00') {
                  out[ip] = mac;
                }
              }
            }
          }
        } catch (_) {}
        // بديل: ip neigh
        if (out.isEmpty) {
          try {
            final r = await Process.run('ip', ['neigh'])
                .timeout(const Duration(seconds: 6));
            final reg = RegExp(
                r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}).*?([0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2}:[0-9a-f]{2})');
            for (final m in reg.allMatches(r.stdout.toString())) {
              out[m.group(1)!] = m.group(2)!.toLowerCase();
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[Discovery] arp error: $e');
    }
    return out.entries.toList();
  }

  // ═══════════════ فحص واجهات الويب ═══════════════
  Future<List<_Probe?>> _probeMany(List<String> ips) async {
    final results = <_Probe?>[];
    const chunk = 16;
    for (var i = 0; i < ips.length; i += chunk) {
      final slice = ips.skip(i).take(chunk).toList();
      results.addAll(await Future.wait(slice.map(_probe)));
    }
    return results;
  }

  static Future<_Probe?> _probe(String ip) async {
    try {
      final r = await http
          .get(Uri.parse('http://$ip/'))
          .timeout(const Duration(seconds: 3));
      final body = '${r.body.toLowerCase()} ${r.headers.toString().toLowerCase()}';
      String brand = '';
      for (final e in _brandKeywords.entries) {
        if (e.value.any(body.contains)) {
          brand = e.key;
          break;
        }
      }
      String title = '';
      final t = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false)
          .firstMatch(r.body);
      if (t != null) title = t.group(1)!.trim();
      return _Probe(ip: ip, brand: brand, pageTitle: title);
    } catch (_) {
      return null;
    }
  }

  // ═══════════════ البوّابة والشبكة الفرعية ═══════════════
  static Future<String?> _detectGateway() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('ipconfig', [],
            stdoutEncoding: const SystemEncoding());
        for (final line in r.stdout.toString().split('\n')) {
          if (line.contains('Default Gateway') && !line.trim().endsWith(':')) {
            final m = RegExp(r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
                .firstMatch(line);
            if (m != null && m.group(1) != '0.0.0.0') return m.group(1);
          }
        }
      } else {
        final r = await Process.run('ip', ['route', 'show', 'default']);
        final m = RegExp(r'via\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})')
            .firstMatch(r.stdout.toString());
        if (m != null) return m.group(1);
      }
    } catch (_) {}
    return null;
  }

  static String _sameSubnetBase(String ip) {
    final p = ip.split('.');
    if (p.length == 4) return '${p[0]}.${p[1]}.${p[2]}.1';
    return '';
  }

  static String _subnetOf(String ip) {
    final p = ip.split('.');
    if (p.length == 4) return '${p[0]}.${p[1]}.${p[2]}';
    return ip;
  }

  void _status(String s) => onStatus?.call(s);
}

class _Probe {
  final String ip;
  final String brand;
  final String pageTitle;
  _Probe({required this.ip, required this.brand, required this.pageTitle});
}
