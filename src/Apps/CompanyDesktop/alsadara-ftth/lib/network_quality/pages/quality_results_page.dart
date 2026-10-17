/// شاشة نتائج فحص الجودة التفصيلية — Network Quality
///
/// تصميم ثلاثي الأبعاد (widgets/depth_3d.dart): بطاقة بطل نيلية بقرص مجسّم
/// للدرجة الكلّية وعمودَي تنزيل/رفع مجسّمين، ثم شبكة مؤشّرات بارزة
/// (Ping/Jitter/فقدان/DNS)، وأعمدة زمن الاستجابة المجسّمة، وشريط الإشارة
/// الضوئية البارز بعتبات QualityScorer، وأعمدة WiFi، وأجهزة الشبكة بأيقونات
/// متساوية القياس، والتوصيات، والرادار، وجهاز الفحص.
///
/// التخطيط: عمود واحد دائماً (طراز الهاتف) — على الشاشات الكبيرة (آيباد/ويندوز)
/// يُقيَّد العرض الأقصى للمحتوى ويُوسَّط.
library;

import 'package:flutter/material.dart';

import '../../frontend/frontend.dart';
import '../models/device_models.dart';
import '../models/quality_models.dart';
import '../services/device_discovery_service.dart';
import '../services/latency_service.dart';
import '../services/quality_scorer.dart';
import '../services/scan_history_service.dart';
import '../services/url_opener.dart';
import '../widgets/depth_3d.dart';
import '../widgets/quality_widgets.dart';
import 'advanced_tools_page.dart';
import 'device_detail_page.dart';

class QualityResultsPage extends StatefulWidget {
  final FullQualityReport report;
  const QualityResultsPage({super.key, required this.report});

  @override
  State<QualityResultsPage> createState() => _QualityResultsPageState();
}

class _QualityResultsPageState extends State<QualityResultsPage> {
  static const _indigo = SdColors.primary;
  static const _teal = SdColors.accent;
  static const _purple = SdColors.platformBase;
  static const _green = SdColors.success;

  // ألوان البطل: خلفية كحلي/فحمي محايدة + accentان حيويان متمايزان + أبيض.
  static const _traceAccent = Nq3d.trace; // بنفسجي تتبّع المسار

  FullQualityReport get report => widget.report;

  // ── حالة تتبّع المسار (عند الطلب داخل صفحة النتائج) ──
  List<TraceHop>? _traceHops; // null = لم يُطلب بعد
  bool _traceRunning = false;
  String? _traceError;
  bool _traceListHidden = false; // طيّ القائمة النصّية للقفزات فقط

  @override
  void initState() {
    super.initState();
    // إن احتوى التقرير على تتبّع سابق (فحص قديم) اعرضه مباشرةً.
    final existing = report.performance.traceroute;
    if (existing.isNotEmpty) {
      final hops = TraceHop.parse(existing);
      if (hops.isNotEmpty) _traceHops = hops;
    }
    // احفظ ملخّص هذا الفحص في السجلّ مرّة واحدة (لا في build).
    ScanHistoryService.add(ScanSummary.fromReport(report));
  }

  Future<void> _runTrace() async {
    setState(() {
      _traceRunning = true;
      _traceError = null;
    });
    try {
      final raw = await LatencyService.traceroute(host: '8.8.8.8');
      final hops = TraceHop.parse(raw);
      if (!mounted) return;
      setState(() {
        _traceRunning = false;
        if (hops.isEmpty) {
          _traceError = 'تعذّر تتبّع المسار — قد تمنعه الشبكة أو انتهت المهلة.';
          _traceHops = null;
        } else {
          _traceHops = hops;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _traceRunning = false;
        _traceError = 'تعذّر تتبّع المسار — قد تمنعه الشبكة أو انتهت المهلة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      padding: EdgeInsets.zero,
      scrollable: false,
      maxWidth: double.infinity,
      appBar: SdAppBar(
        title: 'نتيجة فحص الجودة',
        actions: [
          SdAppBarAction(
            icon: Icons.science_rounded,
            label: 'فحص متقدم',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdvancedToolsPage(
                  gatewayIp: report.discovery?.gatewayIp,
                  onuIp: report.discovery?.onuIp,
                ),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, c) {
          final w = c.maxWidth;
          // نقاط الفصل: هاتف < 600، آيباد 600–1023، سطح المكتب ≥ 1024.
          final isPhone = w < 600;
          final isDesktop = w >= 1024;
          // عمود واحد دائماً، لكن العرض مُقيَّد ومُوسَّط على الشاشات الكبيرة
          // ليبدو كتطبيق هاتف أنيق بدل بطاقات ممطوطة.
          final maxContentWidth = isPhone ? w : (isDesktop ? 700.0 : 620.0);
          return SingleChildScrollView(
            padding: EdgeInsets.only(top: isPhone ? 0 : 8, bottom: 28),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHero(isDesktop: isDesktop),
                    ..._detailCards(context),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════ ترتيب البطاقات ═══════════════════

  List<Widget> _detailCards(BuildContext context) => [
        _buildMetricsGrid(),
        _buildLatencyCard(),
        _buildTraceCard(),
        _buildOptical(),
        _buildWifi(),
        _buildNetworkDevices(context),
        _buildRecommendations(),
        _buildRadar(),
        _buildHostDevice(),
        _buildActions(context),
      ];

  // ════════════════════════════ البطل (Hero) ════════════════════════════

  /// البطل: قرص الدرجة الكلّية المجسّم + عمودا التنزيل/الرفع المجسّمان.
  Widget _buildHero({required bool isDesktop}) {
    final p = report.performance;
    final rating = report.overallRating;
    final ringColor = ratingColorOnDark(rating);
    final (pillFg, _, _) = RatingChip3D.colorsFor(rating);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Nq3d.indigo,
        borderRadius: BorderRadius.circular(26),
        boxShadow: raisedShadow(
            edge: Nq3d.indigoDark,
            depth: 8,
            glow: const Color(0xB30F1660)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('التقييم الكلّي للاتصال',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .78),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          ScoreDisc3D(
            score: report.overallScore,
            color: ringColor,
            maxWidth: isDesktop ? 340 : 320,
            semanticLabel:
                'الدرجة الكلّية ${report.overallScore.round()} من 100 — ${rating.arabicLabel}',
          ),
          Center(
            child: Transform.translate(
              offset: const Offset(0, -4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                decoration: BoxDecoration(
                  color: ringColor,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(color: Color(0x59000000), offset: Offset(0, 4)),
                  ],
                ),
                child: Text(rating.arabicLabel,
                    style: TextStyle(
                        color: pillFg,
                        fontSize: 14,
                        fontWeight: FontWeight.w900)),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _speedCell(
                  label: '↓ تنزيل',
                  value: p.downloadMbps,
                  rating: QualityScorer.rateDownload(p.downloadMbps),
                  shade: IsoShade.teal,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _speedCell(
                  label: '↑ رفع',
                  value: p.uploadMbps,
                  rating: QualityScorer.rateUpload(p.uploadMbps),
                  shade: IsoShade.amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _speedCell({
    required String label,
    required double? value,
    required QualityRating rating,
    required IsoShade shade,
  }) {
    final fraction = value == null ? 0.0 : value / _speedMax(value);
    return Semantics(
      label:
          '$label ${value?.toStringAsFixed(1) ?? 'غير متوفّر'} ميغابت/ث — ${rating.arabicLabel}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              IsoSpeedColumn(fraction: fraction, shade: shade, width: 68),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .75),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(value?.toStringAsFixed(1) ?? '—',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              height: 1.1,
                              fontWeight: FontWeight.w900)),
                    ),
                    Text('Mbps',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .7),
                            fontSize: 11)),
                    if (value != null)
                      Text(rating.arabicLabel,
                          style: TextStyle(
                              color: ratingColorOnDark(rating),
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _speedMax(double? v) {
    if (v == null) return 100;
    for (final m in [50, 100, 200, 500, 1000, 2000]) {
      if (v <= m * 0.95) return m.toDouble();
    }
    return v * 1.1;
  }

  // ═══════════════ بطاقة زمن الاستجابة والاستقرار ═══════════════

  Widget _buildLatencyCard() {
    final p = report.performance;
    final hasPingStats =
        p.pingMs != null || p.minPingMs != null || p.maxPingMs != null;

    return SectionCard(
      title: 'زمن الاستجابة والاستقرار',
      subtitle: 'زمن الاستجابة · التذبذب · فقدان الحزم · DNS',
      icon: Icons.network_ping_rounded,
      accent: _indigo,
      trailing: RatingBadge(QualityScorer.ratePing(p.pingMs)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasPingStats)
            PingPrisms3D(
              minMs: p.minPingMs,
              avgMs: p.pingMs,
              maxMs: p.maxPingMs,
              rate: QualityScorer.ratePing,
            ),
        ],
      ),
    );
  }

  // ═══════════════ تتبّع المسار (عند الطلب) ═══════════════

  Widget _buildTraceCard() {
    final hops = _traceHops;
    return SectionCard(
      title: 'تتبّع مسار الحزم',
      subtitle: 'المسار من جهازك حتى الخادم، قفزة بقفزة',
      icon: Icons.route_rounded,
      accent: _traceAccent,
      trailing: hops != null
          ? _statusChip('${hops.length} قفزة', _traceAccent)
          : null,
      child: _buildTraceBody(hops),
    );
  }

  Widget _buildTraceBody(List<TraceHop>? hops) {
    if (_traceRunning) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: _traceAccent),
            ),
            const SizedBox(height: 14),
            Text('جارٍ تتبّع المسار... قد يستغرق حتى 30 ثانية',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: SdColors.muted)),
          ],
        ),
      );
    }

    if (hops == null) {
      // لم يُطلب بعد (أو فشل سابق).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_traceError != null) ...[
            _emptyNote(_traceError!),
            const SizedBox(height: 12),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'اكتشف الطريق الذي تسلكه حزم بياناتك عبر الشبكة حتى الوصول للخادم.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: SdColors.muted),
              ),
            ),
          ],
          _traceButton(
              _traceError != null ? 'إعادة المحاولة' : 'اكتشاف مسار الحزم'),
        ],
      );
    }

    // نتيجة متاحة: رسم 3D (يبقى دائماً) + قائمة القفزات قابلة للطيّ.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TraceRoute3D(hops: hops, maxWidth: 380),
        const SizedBox(height: 10),
        _traceListToggle(),
        if (!_traceListHidden) ...[
          const SizedBox(height: 6),
          ...hops.map(_traceHopRow),
        ],
        const SizedBox(height: 10),
        _traceButton('إعادة التتبّع'),
      ],
    );
  }

  /// زرّ طيّ/إظهار قائمة القفزات النصّية (لا يؤثّر على الرسم 3D).
  Widget _traceListToggle() {
    final hidden = _traceListHidden;
    return InkWell(
      onTap: () => setState(() => _traceListHidden = !_traceListHidden),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _traceAccent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _traceAccent.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                size: 16, color: _traceAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(hidden ? 'إظهار قائمة القفزات' : 'إخفاء قائمة القفزات',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _traceAccent)),
            ),
            Icon(hidden ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                size: 18, color: _traceAccent),
          ],
        ),
      ),
    );
  }

  Widget _traceButton(String label) {
    return Raised3D(
      onTap: _runTrace,
      radius: 14,
      depth: 5,
      padding: EdgeInsets.zero,
      edgeColor: SdColors.platformEdge,
      glowColor: const Color(0x807E57C2),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF7E57C2), SdColors.platformBase],
      ),
      semanticLabel: label,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.travel_explore_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Widget _traceHopRow(TraceHop h) {
    final timedOut = h.timedOut || h.ip.isEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      decoration: BoxDecoration(
        color: SdColors.groundAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SdColors.faint.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _traceAccent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text('${h.index}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: _traceAccent)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              timedOut ? 'طلب منتهي المهلة (*)' : h.ip,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                  color: timedOut ? SdColors.faint : Colors.black87),
            ),
          ),
          if (h.ms != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: _traceAccent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('${h.ms!.toStringAsFixed(0)} ms',
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                      color: _traceAccent)),
            ),
        ],
      ),
    );
  }

  // ═══════════════ الإشارة الضوئية (الفايبر) ═══════════════

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
    final rxRating = QualityScorer.rateOpticalRx(o.rxPowerDbm);
    return SectionCard(
      title: 'الإشارة الضوئية (الفايبر)',
      subtitle: 'قدرة الاستقبال والإرسال وصحّة الوحدة الضوئية',
      icon: Icons.fiber_manual_record,
      accent: _teal,
      trailing: o.available ? RatingBadge(rxRating) : _statusChip('غير متاح'),
      child: !o.available
          ? _emptyNote(o.error.isNotEmpty
              ? o.error
              : 'لم تُقرأ الإشارة الضوئية — يتطلّب اتصالاً مباشراً بجهاز ONU (Huawei/ZTE).')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // بطاقتا Rx/Tx البارزتان.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _opticalStat(
                        label: 'قدرة الاستقبال (Rx)',
                        value: o.rxPowerDbm != null
                            ? '${o.rxPowerDbm!.toStringAsFixed(2)} dBm'
                            : '—',
                        color: ratingColor(rxRating),
                        icon: Icons.download_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _opticalStat(
                        label: 'قدرة الإرسال (Tx)',
                        value: o.txPowerDbm != null
                            ? '${o.txPowerDbm!.toStringAsFixed(2)} dBm'
                            : '—',
                        color: _teal,
                        icon: Icons.upload_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // شريط Rx مجسّم بعتبات QualityScorer.rateOpticalRx.
                if (o.rxPowerDbm != null) OpticalBand3D(rxDbm: o.rxPowerDbm!),
                const SizedBox(height: 12),
                SpecGrid(
                  accent: _teal,
                  items: [
                    if (o.voltage != null)
                      (
                        label: 'الفولتية',
                        value: '${o.voltage!.toStringAsFixed(2)} V',
                        icon: Icons.bolt_rounded
                      ),
                    if (o.biasCurrentMa != null)
                      (
                        label: 'تيار الانحياز',
                        value: '${o.biasCurrentMa!.toStringAsFixed(2)} mA',
                        icon: Icons.electrical_services_rounded
                      ),
                    if (o.temperatureC != null)
                      (
                        label: 'حرارة الوحدة',
                        value: '${o.temperatureC!.toStringAsFixed(1)} °C',
                        icon: Icons.thermostat_rounded
                      ),
                    if (o.onuModel.isNotEmpty && o.onuModel != o.source)
                      (
                        label: 'الموديل/العنوان',
                        value: o.onuModel,
                        icon: Icons.memory_rounded
                      ),
                    if (o.source.isNotEmpty)
                      (
                        label: 'المصدر',
                        value: o.source,
                        icon: Icons.info_outline_rounded
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  /// بطاقة قيمة ضوئية بارزة (Rx/Tx) بطابع تقني.
  Widget _opticalStat({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [color.withValues(alpha: 0.13), color.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: SdColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: ValueUnit(value, color: color, numberSize: 20),
          ),
        ],
      ),
    );
  }

  /// شريحة حالة محايدة (مثل «غير متاح»).
  Widget _statusChip(String text, [Color color = SdColors.faint]) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }

  // ═══════════════ إشارة WiFi ═══════════════

  Widget _buildWifi() {
    final w = report.wifi;
    final rating = QualityScorer.rateWifiRssi(w.rssiDbm);
    return SectionCard(
      title: 'إشارة WiFi',
      subtitle: 'قوة ومواصفات الاتصال اللاسلكي',
      icon: Icons.wifi_rounded,
      accent: _purple,
      trailing: w.connectedViaWifi
          ? RatingBadge(rating)
          : _statusChip('غير متصل'),
      child: !w.connectedViaWifi
          ? _emptyNote(w.error.isNotEmpty
              ? w.error
              : 'الاتصال سلكي أو تعذّر قراءة WiFi — لا يوجد قياس لاسلكي.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // رأس بصري: أشرطة إشارة + قيمة RSSI داخل بطاقة بارزة.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [
                        ratingColor(rating).withValues(alpha: 0.12),
                        ratingColor(rating).withValues(alpha: 0.03),
                      ],
                    ),
                    border: Border.all(
                        color: ratingColor(rating).withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      WifiPrisms3D(rating: rating, width: 96),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('قوة الإشارة (RSSI)',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: SdColors.muted)),
                            const SizedBox(height: 2),
                            ValueUnit(
                              w.rssiDbm != null ? '${w.rssiDbm} dBm' : '—',
                              color: ratingColor(rating),
                              numberSize: 24,
                            ),
                            if (w.signalPercent != null)
                              Text('النسبة ${w.signalPercent}%',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: SdColors.muted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (w.rssiDbm != null)
                  SignalRangeBar(
                    fraction: ((w.rssiDbm! + 90) / 60).clamp(0.0, 1.0),
                    rating: rating,
                    startLabel: '-90 (ضعيف)',
                    endLabel: '-30 (ممتاز)',
                    valueLabel: '${w.rssiDbm} dBm',
                    gradientColors: const [
                      SdColors.danger,
                      SdColors.warning,
                      SdColors.warning,
                      Color(0xFF66BB6A),
                      SdColors.success,
                    ],
                  ),
                const SizedBox(height: 12),
                SpecGrid(
                  accent: _purple,
                  items: [
                    if (w.ssid.isNotEmpty)
                      (
                        label: 'اسم الشبكة (SSID)',
                        value: w.ssid,
                        icon: Icons.router_rounded
                      ),
                    if (w.band.isNotEmpty)
                      (
                        label: 'النطاق',
                        value: w.band,
                        icon: Icons.signal_cellular_alt_rounded
                      ),
                    if (w.channel != null)
                      (
                        label: 'القناة',
                        value: '${w.channel}',
                        icon: Icons.graphic_eq_rounded
                      ),
                    if (w.linkSpeedMbps != null)
                      (
                        label: 'سرعة الوصلة',
                        value: '${w.linkSpeedMbps} Mbps',
                        icon: Icons.speed_rounded
                      ),
                    if (w.frequencyMhz != null)
                      (
                        label: 'التردّد',
                        value: '${w.frequencyMhz} MHz',
                        icon: Icons.waves_rounded
                      ),
                    if (w.bssid.isNotEmpty)
                      (
                        label: 'BSSID',
                        value: w.bssid,
                        icon: Icons.fingerprint_rounded
                      ),
                  ],
                ),
              ],
            ),
    );
  }

  // ═══════════════ رادار ملخّص الأبعاد ═══════════════

  Widget _buildRadar() {
    final p = report.performance;
    final o = _resolveOptical();
    final w = report.wifi;

    double speedDim =
        QualityScorer.rateDownload(p.downloadMbps).score;
    double latDim = QualityScorer.ratePing(p.pingMs).score;
    double optDim = (o.available && o.rxPowerDbm != null)
        ? QualityScorer.rateOpticalRx(o.rxPowerDbm).score
        : 0;
    double wifiDim = (w.connectedViaWifi && w.rssiDbm != null)
        ? QualityScorer.rateWifiRssi(w.rssiDbm).score
        : 0;

    final dims = <({String label, double value})>[
      (label: 'السرعة', value: speedDim),
      (label: 'زمن الاستجابة', value: latDim),
      (label: 'الإشارة الضوئية', value: optDim),
      (label: 'واي‑فاي', value: wifiDim),
    ];
    final maxDim = dims.fold<double>(0, (a, b) => a > b.value ? a : b.value);

    return SectionCard(
      title: 'ملخّص أبعاد الجودة',
      subtitle: 'نظرة شاملة على أبعاد الأداء الأربعة',
      icon: Icons.radar_rounded,
      accent: SdColors.accent,
      child: maxDim <= 0
          ? _emptyNote('لا تتوفّر بيانات كافية لرسم ملخّص الأبعاد.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                QualityRadarChart(dims: dims),
                const SizedBox(height: 4),
                Text(
                  'كلّما اتّسع الشكل نحو الأطراف كانت الجودة أعلى في ذلك البُعد.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: SdColors.muted),
                ),
              ],
            ),
    );
  }

  // ═══════════════ أجهزة الشبكة (ONU/راوتر/المتصلين) ═══════════════

  Widget _buildNetworkDevices(BuildContext context) {
    final disc = report.discovery;
    if (disc == null) {
      return SectionCard(
        title: 'الأجهزة على الشبكة',
        icon: Icons.lan_rounded,
        accent: SdColors.accent,
        child: _emptyNote('لم يُفعّل اكتشاف الأجهزة في هذا الفحص.'),
      );
    }
    if (disc.devices.isEmpty) {
      return SectionCard(
        title: 'الأجهزة على الشبكة',
        icon: Icons.lan_rounded,
        accent: SdColors.accent,
        child: _emptyNote(disc.note.isNotEmpty
            ? disc.note
            : 'لم يُعثر على أجهزة على الشبكة.'),
      );
    }

    final structural = disc.devices
        .where((d) => d.isOnu || d.isGateway || d.hasWebUi)
        .toList();
    // أجهزة unicast حقيقية فقط (استبعاد multicast/broadcast كطبقة أمان عند العرض).
    final clients = disc.devices
        .where((d) =>
            d.type == DeviceType.client &&
            !DeviceDiscoveryService.isNoiseEndpoint(d.ip, d.mac))
        .toList();

    return SectionCard(
      title: 'الأجهزة على الشبكة',
      subtitle: 'المكوّنات والأجهزة المتصلة بالشبكة المحلية',
      icon: Icons.lan_rounded,
      accent: SdColors.accent,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (disc.doubleNat) ...[
            _statusChip('Double-NAT', SdColors.warning),
            const SizedBox(width: 6),
          ],
          _statusChip('${disc.devices.length} جهاز', SdColors.accent),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (disc.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(disc.note,
                  style:
                      TextStyle(fontSize: 11.5, color: SdColors.muted)),
            ),
          ...structural.map((d) => _deviceRow(context, d)),
          if (clients.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.devices_other_rounded,
                    size: 15, color: SdColors.faint),
                const SizedBox(width: 6),
                Text('الأجهزة المتصلة (${clients.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 6),
            ...clients.take(40).map(_clientCard),
            const SizedBox(height: 4),
            Text(
              'الأسماء الوديّة الكاملة تحتاج قائمة DHCP من الراوتر؛ ما يظهر هنا '
              'أفضل جهد عبر DNS العكسي/NetBIOS والمصنّع.',
              style: TextStyle(fontSize: 10, color: SdColors.faint),
            ),
          ],
        ],
      ),
    );
  }

  Widget _deviceRow(BuildContext context, NetworkDevice d) {
    Color color;
    switch (d.type) {
      case DeviceType.onu:
        color = _teal;
        break;
      case DeviceType.router:
        color = _indigo;
        break;
      case DeviceType.accessPoint:
        color = _purple;
        break;
      default:
        color = SdColors.faint;
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: SdColors.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.14)),
          boxShadow: const [
            BoxShadow(color: Nq3d.sideLeft, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            IsoDeviceIcon(type: d.type, size: 44),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(d.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(d.type.arabicLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10, color: SdColors.faint)),
                      ),
                    ],
                  ),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 10.5,
                          color: SdColors.muted,
                          fontFamily: 'monospace')),
                ],
              ),
            ),
            if (d.status == InspectStatus.needsCredentials)
              Icon(Icons.key_rounded, size: 16, color: SdColors.warning)
            else if (d.status == InspectStatus.authenticated)
              const Icon(Icons.check_circle, size: 16, color: SdColors.success),
            // فتح واجهة الجهاز مباشرةً في المتصفح (وصول سريع بلا فتح التفاصيل).
            IconButton(
              tooltip: 'فتح واجهة الجهاز',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.open_in_browser_rounded, size: 18, color: color),
              onPressed: () => _openDeviceWeb(d.ip),
            ),
            const Icon(Icons.chevron_left_rounded, color: SdColors.faint),
          ],
        ),
      ),
    );
  }

  /// يفتح واجهة الجهاز (http://ip) في المتصفح الافتراضي مع بديل ويندوز.
  Future<void> _openDeviceWeb(String ip) async {
    final ok = await openUrlRobust('http://$ip');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر فتح http://$ip')));
    }
  }

  /// يخمّن نوع الجهاز المتصل من المصنّع/الاسم (أفضل جهد) لعرض أيقونة/وصف.
  ({String label, IconData icon}) _guessClientKind(NetworkDevice c) {
    final s = '${c.vendor} ${c.hostname} ${c.brandGuess}'.toLowerCase();
    bool has(List<String> k) => k.any(s.contains);
    if (has(['apple', 'iphone', 'samsung', 'xiaomi', 'redmi', 'oppo', 'vivo',
        'huawei', 'realme', 'phone', 'android'])) {
      return (label: 'هاتف محمول (مُخمَّن)', icon: Icons.smartphone_rounded);
    }
    if (has(['intel', 'microsoft', 'dell', 'hp', 'lenovo', 'asus', 'pc',
        'desktop', 'laptop'])) {
      return (label: 'حاسوب (مُخمَّن)', icon: Icons.computer_rounded);
    }
    if (has(['tv', 'roku', 'chromecast', 'google', 'lg', 'sony'])) {
      return (label: 'تلفاز/بثّ (مُخمَّن)', icon: Icons.tv_rounded);
    }
    return (label: 'جهاز متصل', icon: Icons.devices_other_rounded);
  }

  /// بطاقة جهاز متصل قابلة للتوسيع: الاسم عنوان أساسي، الـIP ثانوي، والتفاصيل
  /// (IP/MAC/المصنّع/النوع/الحالة) عند التوسيع.
  Widget _clientCard(NetworkDevice c) {
    const accent = SdColors.accent;
    final kind = _guessClientKind(c);
    final hasName = c.hostname.isNotEmpty;
    final title = hasName
        ? c.hostname
        : (c.vendor.isNotEmpty ? c.vendor : 'جهاز غير معروف');
    final subtitle = hasName
        ? (c.ip.isNotEmpty ? c.ip : '—')
        : (c.ip.isNotEmpty ? c.ip : '—');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: SdColors.groundAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SdColors.faint.withValues(alpha: 0.12)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          dense: true,
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(kind.icon, size: 17, color: accent),
          ),
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800)),
          subtitle: Text(subtitle,
              style: TextStyle(
                  fontSize: 10.5,
                  color: SdColors.muted,
                  fontFamily: 'monospace')),
          trailing: c.vendor.isNotEmpty
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(c.vendor,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accent.withValues(alpha: 0.9))),
                )
              : const Icon(Icons.expand_more_rounded, color: SdColors.faint),
          children: [
            SpecGrid(
              accent: accent,
              items: [
                if (hasName)
                  (label: 'الاسم', value: c.hostname, icon: Icons.badge_rounded),
                (
                  label: 'عنوان IP',
                  value: c.ip.isNotEmpty ? c.ip : '—',
                  icon: Icons.tag_rounded
                ),
                (
                  label: 'MAC',
                  value: c.mac.isNotEmpty ? c.mac : '—',
                  icon: Icons.fingerprint_rounded
                ),
                (
                  label: 'المصنّع',
                  value: c.vendor.isNotEmpty ? c.vendor : 'غير معروف',
                  icon: Icons.business_rounded
                ),
                (
                  label: 'النوع المُخمَّن',
                  value: kind.label,
                  icon: kind.icon
                ),
                (
                  label: 'الحالة',
                  value: 'متصل بالشبكة',
                  icon: Icons.wifi_tethering_rounded
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════ جهاز الفحص (الحاسبة) ═══════════════

  Widget _buildHostDevice() {
    final d = report.device;
    return SectionCard(
      title: 'جهاز الفحص (الحاسبة/الهاتف)',
      subtitle: 'مواصفات الجهاز الذي أجرى الفحص',
      icon: Icons.computer_rounded,
      accent: SdColors.muted,
      trailing: _statusChip(d.platform, SdColors.muted),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent, fontFamily: 'Cairo'),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: Text('${d.platform} — ${d.model}',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          subtitle: Text('اضغط لعرض مواصفات جهاز الفحص (ثانوي)',
              style: TextStyle(fontSize: 10.5, color: SdColors.faint)),
          children: [_hostDeviceBody(d)],
        ),
      ),
    );
  }

  Widget _hostDeviceBody(DeviceSpecs d) {
    return SpecGrid(
      accent: SdColors.muted,
      items: [
        (label: 'المنصّة', value: d.platform, icon: Icons.devices_rounded),
        if (d.model.isNotEmpty)
          (label: 'الموديل', value: d.model, icon: Icons.phone_android_rounded),
        if (d.manufacturer.isNotEmpty)
          (
            label: 'الشركة المصنّعة',
            value: d.manufacturer,
            icon: Icons.business_rounded
          ),
        if (d.osVersion.isNotEmpty)
          (
            label: 'نظام التشغيل',
            value: d.osVersion,
            icon: Icons.settings_rounded
          ),
        if (d.totalRamMb != null)
          (
            label: 'الذاكرة (RAM)',
            value: '${(d.totalRamMb! / 1024).toStringAsFixed(1)} GB',
            icon: Icons.memory_rounded
          ),
        if (d.cpuCores != null)
          (
            label: 'أنوية المعالج',
            value: '${d.cpuCores}',
            icon: Icons.developer_board_rounded
          ),
        if (d.cpuInfo.isNotEmpty)
          (label: 'المعالج', value: d.cpuInfo, icon: Icons.memory_rounded),
        ...d.extra.entries.map(
            (e) => (label: e.key, value: e.value, icon: Icons.info_outline)),
      ],
    );
  }

  // ═══════════════ التوصيات ═══════════════

  (IconData, Color) _recoStyle(String r) {
    if (r.contains('ضوئية') || r.contains('فيض')) {
      return (Icons.fiber_manual_record, _teal);
    }
    if (r.contains('WiFi') ||
        r.contains('واي') ||
        r.contains('2.4') ||
        r.contains('5GHz')) {
      return (Icons.wifi_rounded, _purple);
    }
    if (r.contains('التنزيل') || r.contains('سرعة')) {
      return (Icons.speed_rounded, _indigo);
    }
    if (r.contains('زمن') || r.contains('تذبذب') || r.contains('الاستجابة')) {
      return (Icons.timer_rounded, SdColors.warning);
    }
    if (r.contains('الحزم')) {
      return (Icons.lan_rounded, SdColors.danger);
    }
    if (r.contains('ذاكرة') || r.contains('الجهاز')) {
      return (Icons.sd_card_rounded, SdColors.muted);
    }
    if (r.contains('لا توجد') || r.contains('ضمن النطاق')) {
      return (Icons.verified_rounded, _green);
    }
    return (Icons.lightbulb_rounded, SdColors.warning);
  }

  Widget _buildRecommendations() {
    return SectionCard(
      title: 'التوصيات',
      subtitle: 'إرشادات لتحسين جودة الاتصال',
      icon: Icons.lightbulb_rounded,
      accent: SdColors.warning,
      trailing: _statusChip(
          '${report.recommendations.length}', SdColors.warning),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: report.recommendations.map((r) {
          final (icon, color) = _recoStyle(r);
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: SdColors.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RaisedIconTile(
                  icon: icon,
                  color: color,
                  background: Color.alphaBlend(
                      color.withValues(alpha: 0.12), Colors.white),
                  edgeColor: Color.alphaBlend(
                      color.withValues(alpha: 0.30), Colors.white),
                  size: 30,
                  radius: 9,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(r,
                      style:
                          const TextStyle(fontSize: 12.5, height: 1.5)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════ شبكة المؤشّرات المجسّمة (Ping/Jitter/فقدان/DNS) ═══════════════

  Widget _buildMetricsGrid() {
    final p = report.performance;
    final tiles = [
      _metricTile3D('زمن الاستجابة (Ping)', p.pingMs?.toStringAsFixed(0), 'ms',
          QualityScorer.ratePing(p.pingMs)),
      _metricTile3D('التذبذب (Jitter)', p.jitterMs?.toStringAsFixed(1), 'ms',
          QualityScorer.rateJitter(p.jitterMs)),
      _metricTile3D('فقدان الحزم', p.packetLossPercent?.toStringAsFixed(1), '%',
          QualityScorer.ratePacketLoss(p.packetLossPercent)),
      _metricTile3D('استجابة DNS', p.dnsMs?.toStringAsFixed(0), 'ms',
          QualityScorer.rateDns(p.dnsMs)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          Row(children: [
            Expanded(child: tiles[0]),
            const SizedBox(width: 14),
            Expanded(child: tiles[1]),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: tiles[2]),
            const SizedBox(width: 14),
            Expanded(child: tiles[3]),
          ]),
        ],
      ),
    );
  }

  Widget _metricTile3D(
      String label, String? value, String unit, QualityRating rating) {
    return Semantics(
      label: '$label ${value ?? 'غير متوفّر'} $unit — ${rating.arabicLabel}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: raisedShadow(
                edge: Nq3d.cardEdge, glow: const Color(0x661A237E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Nq3d.muted)),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: value ?? '—',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Nq3d.ink)),
                  if (value != null)
                    TextSpan(
                        text: ' $unit',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Nq3d.muted)),
                ]),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 4),
              RatingChip3D(rating),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════ أزرار أسفل الصفحة ═══════════════

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SdButton(
        label: 'فحص جديد',
        icon: Icons.refresh_rounded,
        expand: true,
        onPressed: () => Navigator.of(context).maybePop(),
      ),
    );
  }

  Widget _emptyNote(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: SdColors.faint),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: SdText.bodySm)),
      ],
    );
  }
}
