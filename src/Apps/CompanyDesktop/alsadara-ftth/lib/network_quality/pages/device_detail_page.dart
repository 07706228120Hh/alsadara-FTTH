/// شاشة تفاصيل جهاز شبكة — Network Quality
///
/// تعرض التقرير الكامل لجهاز بنية (ONU/راوتر/AP) وتتيح إدخال اعتماد يدوي
/// محفوظ وإعادة الفحص.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../models/device_models.dart';
import '../models/quality_models.dart';
import '../services/device_credentials_service.dart';
import '../services/device_inspector_service.dart';
import '../services/quality_scorer.dart';
import '../widgets/quality_widgets.dart';
import 'optical_webview_page.dart';

class DeviceDetailPage extends StatefulWidget {
  final NetworkDevice device;
  const DeviceDetailPage({super.key, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  static const _indigo = Color(0xFF1A237E);
  bool _busy = false;

  NetworkDevice get d => widget.device;

  Future<void> _reinspect({DeviceCredential? manual}) async {
    setState(() => _busy = true);
    try {
      await DeviceInspectorService.inspect(d, manual: manual);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enterCredentials() async {
    final userCtrl = TextEditingController(
        text: (await DeviceCredentialsService.getSaved(d.ip))?.user ?? '');
    final passCtrl = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('اعتماد الدخول — ${d.ip}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userCtrl,
                decoration: const InputDecoration(
                    labelText: 'اسم المستخدم', prefixIcon: Icon(Icons.person)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'كلمة المرور', prefixIcon: Icon(Icons.lock)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _indigo, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('فحص'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _reinspect(manual: DeviceCredential(userCtrl.text.trim(), passCtrl.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F4F8),
        appBar: AppBar(
          title: Text(d.displayName,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: 'إعادة الفحص',
              icon: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)))
                  : const Icon(Icons.refresh),
              onPressed: _busy ? null : () => _reinspect(),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _buildIdentity(),
            if (d.status == InspectStatus.needsCredentials) _buildNeedsCreds(),
            if (d.optical != null)
              _buildOptical()
            else if (d.isOnu)
              _buildOpticalFailed(),
            if (d.report != null && d.report!.hasAnyData) _buildReport(),
            if (d.report?.clients.isNotEmpty ?? false) _buildClients(),
          ],
        ),
      ),
    );
  }

  Widget _buildIdentity() {
    return SectionCard(
      title: 'هوية الجهاز',
      icon: Icons.devices_other_rounded,
      accent: _indigo,
      trailing: _statusChip(),
      child: Column(
        children: [
          InfoRow('النوع', d.type.arabicLabel),
          InfoRow('عنوان IP', d.ip),
          if (d.mac.isNotEmpty) InfoRow('MAC', d.mac),
          if (d.vendor.isNotEmpty) InfoRow('الشركة المصنّعة', d.vendor),
          if (d.brandGuess.isNotEmpty) InfoRow('الماركة', d.brandGuess),
          if (d.pageTitle.isNotEmpty) InfoRow('عنوان الواجهة', d.pageTitle),
          InfoRow('بوّابة؟', d.isGateway ? 'نعم' : 'لا'),
        ],
      ),
    );
  }

  Widget _statusChip() {
    String text;
    Color color;
    switch (d.status) {
      case InspectStatus.authenticated:
        text = 'تم الفحص';
        color = Colors.green;
        break;
      case InspectStatus.needsCredentials:
        text = 'يلزم اعتماد';
        color = Colors.orange;
        break;
      case InspectStatus.unreachableUi:
        text = 'جهاز متصل';
        color = Colors.blueGrey;
        break;
      case InspectStatus.error:
        text = 'خطأ';
        color = Colors.red;
        break;
      case InspectStatus.notInspected:
        text = 'لم يُفحص';
        color = Colors.grey;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _buildNeedsCreds() {
    return SectionCard(
      title: 'يلزم اعتماد الدخول',
      icon: Icons.key_rounded,
      accent: Colors.orange,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تعذّر الدخول بالاعتماد الافتراضي لهذا الجهاز. أدخل اسم المستخدم وكلمة المرور ليُفحص بالتفصيل (يُحفظ مشفّراً للمرّة القادمة).',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text('إدخال اعتماد الدخول'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white),
              onPressed: _busy ? null : _enterCredentials,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptical() {
    final o = d.optical!;
    return SectionCard(
      title: 'الإشارة الضوئية',
      icon: Icons.fiber_manual_record,
      accent: const Color(0xFF00838F),
      child: Column(
        children: [
          MetricTile(MetricResult(
            name: 'قدرة الاستقبال (Rx)',
            displayValue:
                o.rxPowerDbm != null ? '${o.rxPowerDbm!.toStringAsFixed(2)} dBm' : '—',
            rating: QualityScorer.rateOpticalRx(o.rxPowerDbm),
            note: 'النطاق الصحّي: -8 إلى -27 dBm',
          )),
          if (o.txPowerDbm != null)
            InfoRow('قدرة الإرسال (Tx)', '${o.txPowerDbm!.toStringAsFixed(2)} dBm'),
          if (o.voltage != null) InfoRow('الفولتية', '${o.voltage!.toStringAsFixed(2)} V'),
          if (o.biasCurrentMa != null)
            InfoRow('تيار الانحياز', '${o.biasCurrentMa!.toStringAsFixed(2)} mA'),
          if (o.temperatureC != null)
            InfoRow('حرارة الوحدة', '${o.temperatureC!.toStringAsFixed(1)} °C'),
        ],
      ),
    );
  }

  Future<void> _openWebViewRead() async {
    // اعتمادات مرشّحة (المحفوظ + الافتراضي للماركة) بصيغة [[user, pass], ...].
    final cands = await DeviceCredentialsService.candidatesFor(
        d.ip, d.brandGuess.isNotEmpty ? d.brandGuess : d.vendor);
    final creds = cands.map((c) => [c.user, c.pass]).toList();
    if (!mounted) return;
    final reading = await Navigator.push<OpticalReading?>(
      context,
      MaterialPageRoute(
        builder: (_) => OpticalWebViewPage(
          ip: d.ip,
          credentials: creds.isNotEmpty
              ? creds
              : const [
                  ['telecomadmin', 'admintelecom']
                ],
        ),
      ),
    );
    if (reading != null && mounted) {
      setState(() {
        d.optical = reading;
        d.error = '';
      });
    }
  }

  Widget _buildOpticalFailed() {
    return SectionCard(
      title: 'الإشارة الضوئية',
      icon: Icons.fiber_manual_record,
      accent: const Color(0xFF00838F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.error.isNotEmpty
                ? d.error
                : 'تعذّر قراءة الإشارة الضوئية — جرّب إدخال اعتماد telecomadmin يدوياً.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (Platform.isWindows)
                ElevatedButton.icon(
                  icon: const Icon(Icons.travel_explore_rounded, size: 18),
                  label: const Text('قراءة متقدمة عبر المتصفح (موصى به)'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00838F),
                      foregroundColor: Colors.white),
                  onPressed: _busy ? null : _openWebViewRead,
                ),
              OutlinedButton.icon(
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('إدخال اعتماد وإعادة المحاولة'),
                onPressed: _busy ? null : _enterCredentials,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReport() {
    final r = d.report!;
    return SectionCard(
      title: 'تفاصيل الجهاز',
      icon: Icons.info_rounded,
      accent: _indigo,
      child: Column(
        children: [
          if (r.model.isNotEmpty) InfoRow('الموديل', r.model),
          if (r.firmware.isNotEmpty) InfoRow('الفيرموير', r.firmware),
          if (r.hardwareVersion.isNotEmpty) InfoRow('نسخة العتاد', r.hardwareVersion),
          if (r.uptime.isNotEmpty) InfoRow('مدة التشغيل', r.uptime),
          if (r.wanConnectionType.isNotEmpty)
            InfoRow('نوع اتصال WAN', r.wanConnectionType),
          if (r.pppoeUser.isNotEmpty) InfoRow('مستخدم PPPoE', r.pppoeUser),
          if (r.wanIp.isNotEmpty) InfoRow('عنوان WAN', r.wanIp),
          if (r.lanIp.isNotEmpty) InfoRow('عنوان LAN', r.lanIp),
          if (r.macAddress.isNotEmpty) InfoRow('MAC', r.macAddress),
          if (r.wifiSsid.isNotEmpty) InfoRow('اسم WiFi', r.wifiSsid),
          if (r.wifiBand.isNotEmpty) InfoRow('النطاق', r.wifiBand),
          if (r.wifiChannel != null) InfoRow('القناة', '${r.wifiChannel}'),
          if (r.cpuUsagePercent != null)
            InfoRow('استهلاك المعالج', '${r.cpuUsagePercent!.toStringAsFixed(0)}%'),
          if (r.memUsagePercent != null)
            InfoRow('استهلاك الذاكرة', '${r.memUsagePercent!.toStringAsFixed(0)}%'),
          if (r.temperatureC != null)
            InfoRow('الحرارة', '${r.temperatureC!.toStringAsFixed(1)} °C'),
          ...r.extra.entries.map((e) => InfoRow(e.key, e.value)),
        ],
      ),
    );
  }

  Widget _buildClients() {
    final clients = d.report!.clients;
    return SectionCard(
      title: 'الأجهزة المتصلة (${clients.length})',
      icon: Icons.group_rounded,
      accent: const Color(0xFF455A64),
      child: Column(
        children: clients
            .map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.smartphone_rounded,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.hostname.isNotEmpty ? c.hostname : c.ip,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12.5)),
                            Text('${c.ip}  •  ${c.mac}',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.grey.shade600,
                                    fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      if (c.vendor.isNotEmpty)
                        Text(c.vendor,
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
