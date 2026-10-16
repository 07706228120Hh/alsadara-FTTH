/// أداة «محلّل قنوات WiFi» — Network Quality (فحص متقدّم)
///
/// تمسح الشبكات المجاورة، ترسم إشغال القنوات مجسّماً (2.4/5GHz) وتبرز القناة
/// الموصى بها، مع قائمة الشبكات. التنفيذ عبر WifiChannelAnalyzerService (قابل للحقن).
library;

import 'package:flutter/material.dart';

import '../models/quality_models.dart';
import '../services/wifi_channel_analyzer_service.dart';
import '../widgets/depth_3d.dart';

class WifiChannelAnalyzerPage extends StatefulWidget {
  const WifiChannelAnalyzerPage({super.key, this.scanner});

  /// ماسح قابل للحقن (لاختبار العرض بلا منصّة). الافتراضي: الخدمة الحقيقية.
  final Future<WifiScanResult> Function()? scanner;

  @override
  State<WifiChannelAnalyzerPage> createState() =>
      _WifiChannelAnalyzerPageState();
}

class _WifiChannelAnalyzerPageState extends State<WifiChannelAnalyzerPage> {
  WifiScanResult? _result;
  bool _scanning = false;
  bool _band24 = true; // التبويب الحالي

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final r = await (widget.scanner?.call() ??
          WifiChannelAnalyzerService.scan());
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _result = r;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _result = WifiScanResult.unsupported('تعذّر مسح الشبكات المجاورة.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Nq3d.ground,
        appBar: nq3dAppBar('محلّل قنوات WiFi'),
        body: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            final isPhone = w < 600;
            final maxContentWidth = isPhone ? w : (w >= 1024 ? 720.0 : 600.0);
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: _scanning
                      ? _loading()
                      : _result == null
                          ? const SizedBox.shrink()
                          : (!_result!.supported
                              ? _unsupported(_result!.message)
                              : _body(_result!, isPhone)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _loading() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: Nq3d.indigo)),
            const SizedBox(height: 16),
            Text('جارٍ مسح الشبكات المجاورة...',
                style: TextStyle(fontSize: 13, color: Nq3d.muted)),
          ],
        ),
      );

  Widget _unsupported(String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 8),
        child: Column(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 54, color: Nq3d.faint),
            const SizedBox(height: 14),
            Text(msg.isEmpty ? 'غير مدعوم على هذه المنصّة.' : msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: Nq3d.ink)),
            const SizedBox(height: 6),
            Text(
              'محلّل القنوات متاح حالياً على ويندوز عبر مسح الشبكات المجاورة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Nq3d.muted),
            ),
          ],
        ),
      );

  Widget _body(WifiScanResult r, bool isPhone) {
    final nets = r.networks.where((n) => _band24 ? n.is24 : n.is5).toList();
    final rec = _band24 ? r.rec24 : r.rec5;
    final loads = WifiChannelAnalyzerService.channelLoads(r.networks,
        band24: _band24);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bandTabs(),
        const SizedBox(height: 14),
        // توصية أفضل قناة.
        if (rec != null) _recCard(rec),
        const SizedBox(height: 14),
        // رسم إشغال القنوات المجسّم.
        _channelChartCard(loads, rec?.bestChannel),
        const SizedBox(height: 14),
        // قائمة الشبكات للنطاق الحالي.
        Row(
          children: [
            Icon(Icons.wifi_rounded, size: 15, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text('شبكات ${_band24 ? '2.4GHz' : '5GHz'} (${nets.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 6),
        if (nets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('لا شبكات على هذا النطاق.',
                style: TextStyle(fontSize: 12, color: Nq3d.muted)),
          )
        else
          ...nets.map(_netCard),
        const SizedBox(height: 16),
        Raised3D(
          onTap: _scan,
          radius: 16,
          depth: 6,
          padding: EdgeInsets.zero,
          edgeColor: Nq3d.indigoDark,
          glowColor: const Color(0x990F1660),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF283593), Nq3d.indigo],
          ),
          semanticLabel: 'إعادة المسح',
          child: const SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('إعادة المسح',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bandTabs() {
    Widget tab(String label, bool is24) {
      final selected = _band24 == is24;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _band24 = is24),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? Nq3d.indigo : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    color: selected ? Colors.white : Nq3d.muted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: raisedShadow(depth: 3, glow: const Color(0x331A237E)),
      ),
      child: Row(children: [tab('2.4GHz', true), tab('5GHz', false)]),
    );
  }

  Widget _recCard(ChannelRecommendation rec) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: raisedShadow(
            edge: const Color(0xFF14421A),
            depth: 5,
            glow: const Color(0x592E7D32)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('القناة الموصى بها: ${rec.bestChannel ?? '—'}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
                const SizedBox(height: 2),
                Text(rec.note,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11.5,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelChartCard(Map<int, double> loads, int? recommended) {
    final maxLoad =
        loads.values.isEmpty ? 1.0 : loads.values.reduce((a, b) => a > b ? a : b);
    final scale = maxLoad <= 0 ? 1.0 : maxLoad;
    final channels = loads.keys.toList()..sort();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: raisedShadow(depth: 5, glow: const Color(0x661A237E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('إشغال القنوات (الأعلى = أكثر ازدحاماً)',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Nq3d.ink)),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (ctx, c) {
            final n = channels.length;
            final colW = (n == 0 ? 40.0 : (c.maxWidth - 8) / n)
                .clamp(34.0, 64.0)
                .toDouble();
            final row = Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: channels
                  .map((ch) => _channelColumn(
                      ch, (loads[ch] ?? 0) / scale, colW,
                      recommended: ch == recommended))
                  .toList(),
            );
            final needed = n * (colW + 6);
            return needed <= c.maxWidth + 0.5
                ? row
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: SizedBox(width: needed, child: row),
                  );
          }),
        ],
      ),
    );
  }

  Widget _channelColumn(int ch, double frac, double colW,
      {required bool recommended}) {
    // ارتفاع أعلى = ازدحام أعلى؛ اللون يتدرّج من الأخضر (خالٍ) للأحمر (مزدحم).
    final rating = _loadRating(frac);
    final shade = recommended
        ? const IsoShade(
            Color(0xFF81C784), Color(0xFF43A047), Color(0xFF2E7D32))
        : ratingShade(rating);
    return SizedBox(
      width: colW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 16,
            child: recommended
                ? const Icon(Icons.emoji_events_rounded,
                    color: Color(0xFF2E7D32), size: 15)
                : null,
          ),
          IsoSpeedColumn(
              fraction: frac.clamp(0.05, 1.0).toDouble(),
              shade: shade,
              width: colW * 0.66),
          const SizedBox(height: 3),
          Text('$ch',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: recommended ? const Color(0xFF2E7D32) : Nq3d.muted)),
        ],
      ),
    );
  }

  QualityRating _loadRating(double frac) {
    if (frac < 0.2) return QualityRating.excellent;
    if (frac < 0.4) return QualityRating.good;
    if (frac < 0.6) return QualityRating.fair;
    if (frac < 0.8) return QualityRating.poor;
    return QualityRating.bad;
  }

  Widget _netCard(NearbyNetwork n) {
    final sig = n.signalPercent ?? 0;
    final sigColor = sig >= 66
        ? const Color(0xFF2E7D32)
        : sig >= 40
            ? const Color(0xFFF9A825)
            : const Color(0xFFC62828);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Nq3d.indigo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_rounded, size: 15, color: Nq3d.indigo),
                Text('ق${n.channel}',
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        color: Nq3d.indigo)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(n.ssid,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text('${n.bssid}  •  قناة ${n.channel}  •  ${n.band}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('$sig%',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  color: sigColor)),
        ],
      ),
    );
  }
}
