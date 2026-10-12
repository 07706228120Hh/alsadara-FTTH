/// الفاحص العميق لأجهزة الشبكة — Network Quality
///
/// بعد الاكتشاف، يسجّل الدخول لكل جهاز بنية (ONU/راوتر) بالاعتماد الافتراضي
/// ثم اليدوي المحفوظ، ويقرأ تقريراً تفصيلياً (قراءة فقط): الموديل/الفيرموير/WAN/
/// WiFi + الإشارة الضوئية للـONU + الأجهزة المتصلة (best-effort حسب الماركة).
///
/// يعيد استخدام محوّلات الدخول الإنتاجية (router_adapter_service) للقراءة فقط
/// دون تعديلها.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../services/router_adapter_service.dart';
import '../models/device_models.dart';
import 'device_credentials_service.dart';
import 'optical_signal_service.dart';

class DeviceInspectorService {
  /// يفحص جهازاً ويحدّث حقوله (status/report/optical) في المكان.
  /// [manual] اعتماد يدوي من المستخدم (يُجرَّب أولاً ويُحفظ عند النجاح).
  static Future<void> inspect(NetworkDevice d, {DeviceCredential? manual}) async {
    // 1) الإشارة الضوئية للـONU (اعتماد ONU الافتراضي قياسي).
    if (d.isOnu) {
      try {
        final extra = manual != null
            ? <List<String>>[
                [manual.user, manual.pass]
              ]
            : const <List<String>>[];
        final o = await OpticalSignalService.readAt(d.ip, extraCreds: extra);
        if (o.available) {
          d.optical = OpticalReading(
            rxPowerDbm: o.rxPowerDbm,
            txPowerDbm: o.txPowerDbm,
            voltage: o.voltage,
            biasCurrentMa: o.biasCurrentMa,
            temperatureC: o.temperatureC,
          );
        } else if (o.error.isNotEmpty) {
          d.error = o.error; // تشخيص سبب تعذّر قراءة البصريات
        }
      } catch (e) {
        debugPrint('[Inspect] optical error: $e');
      }
    }

    final brandKey =
        d.brandGuess.isNotEmpty ? d.brandGuess : d.vendor;
    final adapter = RouterAdapterFactory.getAdapter(brandKey);

    if (adapter == null) {
      // لا محوّل لهذه الماركة — نكتفي بالضوئي إن توفّر.
      d.status = d.optical != null
          ? InspectStatus.authenticated
          : InspectStatus.needsCredentials;
      if (d.optical == null && brandKey.isEmpty) {
        d.status = InspectStatus.unreachableUi;
      }
      return;
    }

    // 2) قائمة الاعتمادات: يدوي → محفوظ → افتراضي للماركة.
    final creds = <DeviceCredential>[];
    if (manual != null) creds.add(manual);
    creds.addAll(await DeviceCredentialsService.candidatesFor(d.ip, brandKey));

    DeviceCredential? working;
    for (final c in creds) {
      try {
        final ok = await adapter.login(d.ip, c.user, c.pass);
        if (ok) {
          working = c;
          break;
        }
      } catch (e) {
        debugPrint('[Inspect] login error ${d.ip}: $e');
      }
    }

    if (working == null) {
      d.status =
          d.optical != null ? InspectStatus.authenticated : InspectStatus.needsCredentials;
      return;
    }

    // احفظ الاعتماد الناجح لتسريع المرّة القادمة.
    await DeviceCredentialsService.save(d.ip, working);

    // 3) قراءة الإعدادات الحالية.
    try {
      final s = await adapter.readSettings(d.ip);
      final clients = await _readClients(d, brandKey, working);
      d.report = DeviceReport(
        model: s.model,
        firmware: s.firmwareVersion,
        wanIp: s.wanIp,
        lanIp: s.lanIp,
        macAddress: s.macAddress,
        pppoeUser: s.pppoeUser,
        wanConnectionType: s.pppoeUser.isNotEmpty ? 'PPPoE' : '',
        wifiSsid: s.wifiSsid,
        clients: clients,
        extra: {
          if (s.tr069Enabled) 'TR-069': 'مفعّل',
          if (s.tr069AcsUrl.isNotEmpty) 'ACS URL': s.tr069AcsUrl,
          if (s.wifiSsid5g.isNotEmpty) 'SSID (5GHz)': s.wifiSsid5g,
        },
      );
      d.status = InspectStatus.authenticated;
    } catch (e) {
      debugPrint('[Inspect] readSettings error: $e');
      d.error = e.toString();
      d.status = d.optical != null
          ? InspectStatus.authenticated
          : InspectStatus.error;
    }
  }

  /// قراءة الأجهزة المتصلة — best-effort. MikroTik عبر REST (basic auth) موثوق؛
  /// غير ذلك فارغ (القائمة العامة في الاكتشاف تغطّي كل العملاء).
  static Future<List<ConnectedClient>> _readClients(
      NetworkDevice d, String brandKey, DeviceCredential cred) async {
    final b = brandKey.toLowerCase();
    try {
      if (b.contains('mikrotik') || b.contains('routeros')) {
        final auth =
            'Basic ${base64Encode(utf8.encode('${cred.user}:${cred.pass}'))}';
        final r = await http.get(
          Uri.parse('http://${d.ip}/rest/ip/dhcp-server/lease'),
          headers: {'Authorization': auth},
        ).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final list = jsonDecode(r.body);
          if (list is List) {
            return list
                .map((e) => ConnectedClient(
                      ip: e['address']?.toString() ?? '',
                      mac: e['mac-address']?.toString() ?? '',
                      hostname: e['host-name']?.toString() ?? '',
                      connection: 'ethernet',
                    ))
                .where((c) => c.ip.isNotEmpty)
                .toList();
          }
        }
      }
    } catch (e) {
      debugPrint('[Inspect] clients error: $e');
    }
    return const [];
  }
}
