/// شاشة نتائج فحص الجودة التفصيلية — Network Quality
library;

import 'package:flutter/material.dart';

import '../models/device_models.dart';
import '../models/quality_models.dart';
import '../services/quality_scorer.dart';
import '../widgets/quality_widgets.dart';
import 'device_detail_page.dart';

class QualityResultsPage extends StatefulWidget {
  final FullQualityReport report;
  const QualityResultsPage({super.key, required this.report});

  @override
  State<QualityResultsPage> createState() => _QualityResultsPageState();
}

class _QualityResultsPageState extends State<QualityResultsPage> {
  static const _indigo = Color(0xFF1A237E);

  FullQualityReport get report => widget.report;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F4F8),
        appBar: AppBar(
          title: const Text('نتيجة فحص الجودة',
              style: TextStyle(fontWeight: FontWeight.w800)),
          backgroundColor: _indigo,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _buildHeader(),
            _buildNetworkDevices(context),
            _buildPerformance(),
            _buildOptical(),
            _buildWifi(),
            _buildRecommendations(),
            _buildHostDevice(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF3949AB)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text('التقييم الكلّي للاتصال',
              style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 12),
          Container(
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            padding: const EdgeInsets.all(10),
            child: ScoreGauge(
                score: report.overallScore, rating: report.overallRating),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformance() {
    final p = report.performance;
    final metrics = <MetricResult>[
      MetricResult(
        name: 'زمن الاستجابة (Ping)',
        displayValue: p.pingMs != null ? '${p.pingMs!.toStringAsFixed(0)} ms' : '—',
        rating: QualityScorer.ratePing(p.pingMs),
        note: (p.minPingMs != null && p.maxPingMs != null)
            ? 'الأدنى ${p.minPingMs!.toStringAsFixed(0)} / الأعلى ${p.maxPingMs!.toStringAsFixed(0)} ms'
            : null,
      ),
      MetricResult(
        name: 'التذبذب (Jitter)',
        displayValue: p.jitterMs != null ? '${p.jitterMs!.toStringAsFixed(1)} ms' : '—',
        rating: QualityScorer.rateJitter(p.jitterMs),
      ),
      MetricResult(
        name: 'فقدان الحزم',
        displayValue: '${p.packetLossPercent?.toStringAsFixed(1) ?? '—'}%',
        rating: QualityScorer.ratePacketLoss(p.packetLossPercent),
      ),
      MetricResult(
        name: 'سرعة التنزيل',
        displayValue:
            p.downloadMbps != null ? '${p.downloadMbps!.toStringAsFixed(1)} Mbps' : '—',
        rating: QualityScorer.rateDownload(p.downloadMbps),
      ),
      MetricResult(
        name: 'سرعة الرفع',
        displayValue:
            p.uploadMbps != null ? '${p.uploadMbps!.toStringAsFixed(1)} Mbps' : '—',
        rating: QualityScorer.rateUpload(p.uploadMbps),
      ),
      MetricResult(
        name: 'استجابة DNS',
        displayValue: p.dnsMs != null ? '${p.dnsMs!.toStringAsFixed(0)} ms' : '—',
        rating: QualityScorer.rateDns(p.dnsMs),
      ),
    ];
    return SectionCard(
      title: 'أداء الإنترنت',
      icon: Icons.speed_rounded,
      accent: _indigo,
      child: Column(
        children: [
          ...metrics.map((m) => MetricTile(m)),
          if (p.traceroute.isNotEmpty) ...[
            const Divider(height: 20),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('تتبّع المسار:',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
            const SizedBox(height: 6),
            ...p.traceroute.take(16).map((h) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(h,
                      style: const TextStyle(
                          fontSize: 10.5, fontFamily: 'monospace')),
                )),
          ],
        ],
      ),
    );
  }

  /// يرجّح قراءة بصريات من الفحص العام أو من جهاز ONU مكتشَف (قراءة المتصفح).
  OpticalSignalInfo _resolveOptical() {
    final o = report.optical;
    if (o.available) return o;
    final onu = report.discovery?.devices
        .where((d) => d.isOnu && d.optical != null)
        .toList();
    if (onu != null && onu.isNotEmpty) {
      final r = onu.first.optical!;
      return OpticalSignalInfo(
        available: true,
        rxPowerDbm: r.rxPowerDbm,
        txPowerDbm: r.txPowerDbm,
        voltage: r.voltage,
        biasCurrentMa: r.biasCurrentMa,
        temperatureC: r.temperatureC,
        source: 'ONU ${onu.first.ip}',
      );
    }
    return o;
  }

  Widget _buildOptical() {
    final o = _resolveOptical();
    return SectionCard(
      title: 'الإشارة الضوئية (الفايبر)',
      icon: Icons.fiber_manual_record,
      accent: const Color(0xFF00838F),
      child: !o.available
          ? Text(
              o.error.isNotEmpty
                  ? o.error
                  : 'لم تُقرأ الإشارة الضوئية — يتطلّب اتصالاً مباشراً بجهاز ONU (Huawei/ZTE).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            )
          : Column(
              children: [
                MetricTile(MetricResult(
                  name: 'قدرة الاستقبال (Rx)',
                  displayValue: o.rxPowerDbm != null
                      ? '${o.rxPowerDbm!.toStringAsFixed(2)} dBm'
                      : '—',
                  rating: QualityScorer.rateOpticalRx(o.rxPowerDbm),
                  note: 'النطاق الصحّي: -8 إلى -27 dBm',
                )),
                if (o.txPowerDbm != null)
                  InfoRow('قدرة الإرسال (Tx)',
                      '${o.txPowerDbm!.toStringAsFixed(2)} dBm'),
                if (o.voltage != null)
                  InfoRow('الفولتية', '${o.voltage!.toStringAsFixed(2)} V'),
                if (o.biasCurrentMa != null)
                  InfoRow('تيار الانحياز',
                      '${o.biasCurrentMa!.toStringAsFixed(2)} mA'),
                if (o.temperatureC != null)
                  InfoRow('حرارة الوحدة',
                      '${o.temperatureC!.toStringAsFixed(1)} °C'),
                InfoRow('المصدر', o.source),
              ],
            ),
    );
  }

  Widget _buildWifi() {
    final w = report.wifi;
    return SectionCard(
      title: 'إشارة WiFi',
      icon: Icons.wifi_rounded,
      accent: const Color(0xFF6A1B9A),
      child: !w.connectedViaWifi
          ? Text(
              w.error.isNotEmpty
                  ? w.error
                  : 'الاتصال سلكي أو تعذّر قراءة WiFi — لا يوجد قياس لاسلكي.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            )
          : Column(
              children: [
                MetricTile(MetricResult(
                  name: 'قوة الإشارة (RSSI)',
                  displayValue:
                      w.rssiDbm != null ? '${w.rssiDbm} dBm' : '—',
                  rating: QualityScorer.rateWifiRssi(w.rssiDbm),
                  note: w.signalPercent != null ? 'النسبة ${w.signalPercent}%' : null,
                )),
                if (w.ssid.isNotEmpty) InfoRow('اسم الشبكة (SSID)', w.ssid),
                if (w.band.isNotEmpty) InfoRow('النطاق', w.band),
                if (w.channel != null) InfoRow('القناة', '${w.channel}'),
                if (w.linkSpeedMbps != null)
                  InfoRow('سرعة الوصلة', '${w.linkSpeedMbps} Mbps'),
                if (w.frequencyMhz != null)
                  InfoRow('التردّد', '${w.frequencyMhz} MHz'),
                if (w.bssid.isNotEmpty) InfoRow('BSSID', w.bssid),
              ],
            ),
    );
  }

  // ═══ أجهزة الشبكة (ONU/راوتر/المتصلين) — القسم الرئيسي الجديد ═══
  Widget _buildNetworkDevices(BuildContext context) {
    final disc = report.discovery;
    if (disc == null) {
      return SectionCard(
        title: 'الأجهزة على الشبكة',
        icon: Icons.lan_rounded,
        accent: const Color(0xFF00695C),
        child: Text('لم يُفعّل اكتشاف الأجهزة في هذا الفحص.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      );
    }
    if (disc.devices.isEmpty) {
      return SectionCard(
        title: 'الأجهزة على الشبكة',
        icon: Icons.lan_rounded,
        accent: const Color(0xFF00695C),
        child: Text(disc.note,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      );
    }

    final structural = disc.devices
        .where((d) => d.isOnu || d.isGateway || d.hasWebUi)
        .toList();
    final clients =
        disc.devices.where((d) => d.type == DeviceType.client).toList();

    return SectionCard(
      title: 'الأجهزة على الشبكة (${disc.devices.length})',
      icon: Icons.lan_rounded,
      accent: const Color(0xFF00695C),
      trailing: disc.doubleNat
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('Double-NAT',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.orange.shade800)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(disc.note,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          ...structural.map((d) => _deviceRow(context, d)),
          if (clients.isNotEmpty) ...[
            const Divider(height: 18),
            Text('الأجهزة المتصلة (${clients.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12.5)),
            const SizedBox(height: 4),
            ...clients.take(40).map(_clientRow),
          ],
        ],
      ),
    );
  }

  Widget _deviceRow(BuildContext context, NetworkDevice d) {
    IconData icon;
    Color color;
    switch (d.type) {
      case DeviceType.onu:
        icon = Icons.fiber_manual_record;
        color = const Color(0xFF00838F);
        break;
      case DeviceType.router:
        icon = Icons.router_rounded;
        color = const Color(0xFF1A237E);
        break;
      case DeviceType.accessPoint:
        icon = Icons.settings_input_antenna_rounded;
        color = const Color(0xFF6A1B9A);
        break;
      default:
        icon = Icons.device_hub_rounded;
        color = Colors.grey;
    }
    final rx = d.optical?.rxPowerDbm;
    final subtitle = <String>[
      d.ip,
      if (d.report?.model.isNotEmpty ?? false) d.report!.model,
      if (rx != null) 'Rx ${rx.toStringAsFixed(1)}dBm',
    ].join('  •  ');

    return InkWell(
      onTap: () async {
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => DeviceDetailPage(device: d)));
        if (mounted) setState(() {}); // تحديث بعد قراءة محتملة للبصريات
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(d.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      const SizedBox(width: 6),
                      Text(d.type.arabicLabel,
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade600,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
            if (d.status == InspectStatus.needsCredentials)
              Icon(Icons.key_rounded, size: 16, color: Colors.orange.shade700)
            else if (d.status == InspectStatus.authenticated)
              const Icon(Icons.check_circle, size: 16, color: Colors.green),
            const Icon(Icons.chevron_left_rounded, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _clientRow(NetworkDevice c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.smartphone_rounded, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${c.ip}   ${c.mac}',
                style: const TextStyle(
                    fontSize: 10.5, fontFamily: 'monospace')),
          ),
          if (c.vendor.isNotEmpty)
            Text(c.vendor,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // ═══ جهاز الفحص (الحاسبة) — ثانوي، مطوي ═══
  Widget _buildHostDevice() {
    final d = report.device;
    return SectionCard(
      title: 'جهاز الفحص (الحاسبة/الهاتف)',
      icon: Icons.computer_rounded,
      accent: const Color(0xFF90A4AE),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent, fontFamily: 'Cairo'),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('${d.platform} — ${d.model}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          subtitle: Text('اضغط لعرض مواصفات جهاز الفحص (ثانوي)',
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
          children: [_hostDeviceBody(d)],
        ),
      ),
    );
  }

  Widget _hostDeviceBody(DeviceSpecs d) {
    return Column(
        children: [
          InfoRow('المنصّة', d.platform),
          if (d.model.isNotEmpty) InfoRow('الموديل', d.model),
          if (d.manufacturer.isNotEmpty) InfoRow('الشركة المصنّعة', d.manufacturer),
          if (d.osVersion.isNotEmpty) InfoRow('نظام التشغيل', d.osVersion),
          if (d.totalRamMb != null)
            InfoRow('الذاكرة (RAM)',
                '${(d.totalRamMb! / 1024).toStringAsFixed(1)} GB'),
          if (d.cpuCores != null) InfoRow('أنوية المعالج', '${d.cpuCores}'),
          if (d.cpuInfo.isNotEmpty) InfoRow('المعالج', d.cpuInfo),
          ...d.extra.entries.map((e) => InfoRow(e.key, e.value)),
        ],
    );
  }

  Widget _buildRecommendations() {
    return SectionCard(
      title: 'التوصيات',
      icon: Icons.lightbulb_rounded,
      accent: const Color(0xFFF9A825),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: report.recommendations
            .map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• ',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      Expanded(
                          child: Text(r,
                              style: const TextStyle(
                                  fontSize: 12.5, height: 1.5))),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
