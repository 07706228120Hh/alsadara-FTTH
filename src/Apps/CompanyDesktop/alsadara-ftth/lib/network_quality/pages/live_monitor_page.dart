/// أداة «المراقبة الحيّة» — Network Quality (فحص متقدّم)
///
/// مراقبة فورية لاستقرار الاتصال: ping متكرّر كل ~1s مع رسم حيّ (fl_chart) +
/// إحصاءات حيّة (الحالي/المتوسط/الأدنى/الأعلى/التذبذب/نسبة الفقد). المؤقّت يتوقّف
/// عند الإيقاف وفي dispose. تعمل على كل المنصّات عبر LatencyService.
library;

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../services/latency_service.dart';
import '../widgets/depth_3d.dart';

class LiveMonitorPage extends StatefulWidget {
  const LiveMonitorPage({
    super.key,
    this.host = '8.8.8.8',
    this.pinger,
    this.debugSamples,
  });

  final String host;

  /// مُزوّد ping قابل للحقن (لاختبار بلا شبكة). يُعيد زمن الاستجابة ms أو null (فقد).
  final Future<double?> Function()? pinger;

  /// عيّنات ابتدائية للعرض (لاختبار الرسم بلا تشغيل فعلي).
  final List<double?>? debugSamples;

  @override
  State<LiveMonitorPage> createState() => _LiveMonitorPageState();
}

class _LiveMonitorPageState extends State<LiveMonitorPage> {
  static const _maxSamples = 60;
  final List<double?> _samples = []; // null = فقد حزمة
  Timer? _timer;
  bool _running = false;
  bool _ticking = false;
  int _sent = 0;
  int _lost = 0;

  @override
  void initState() {
    super.initState();
    if (widget.debugSamples != null) {
      for (final s in widget.debugSamples!) {
        _samples.add(s);
        _sent++;
        if (s == null) _lost++;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggle() {
    if (_running) {
      _stop();
    } else {
      _startMonitor();
    }
  }

  void _startMonitor() {
    setState(() => _running = true);
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _running = false);
  }

  Future<void> _tick() async {
    if (_ticking) return; // تفادي تداخل النبضات
    _ticking = true;
    try {
      final rtt = await (widget.pinger?.call() ?? _defaultPing());
      if (!mounted) return;
      setState(() {
        _samples.add(rtt);
        if (_samples.length > _maxSamples) _samples.removeAt(0);
        _sent++;
        if (rtt == null) _lost++;
      });
    } catch (_) {
      // تجاهل — ستُحسب كفقد في النبضة التالية إن استمرّ.
    } finally {
      _ticking = false;
    }
  }

  Future<double?> _defaultPing() async {
    final s = await LatencyService.measurePing(host: widget.host, count: 1);
    return s.received > 0 ? s.avg : null;
  }

  // ── إحصاءات ──
  List<double> get _valid => _samples.whereType<double>().toList();
  double? get _current => _samples.isEmpty ? null : _samples.last;
  double? get _avg =>
      _valid.isEmpty ? null : _valid.reduce((a, b) => a + b) / _valid.length;
  double? get _min =>
      _valid.isEmpty ? null : _valid.reduce((a, b) => a < b ? a : b);
  double? get _max =>
      _valid.isEmpty ? null : _valid.reduce((a, b) => a > b ? a : b);
  double? get _jitter {
    if (_valid.length < 2) return null;
    double sum = 0;
    for (var i = 1; i < _valid.length; i++) {
      sum += (_valid[i] - _valid[i - 1]).abs();
    }
    return sum / (_valid.length - 1);
  }

  double get _lossPercent =>
      _sent == 0 ? 0 : (_lost / _sent * 100).clamp(0, 100).toDouble();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Nq3d.ground,
        appBar: nq3dAppBar('المراقبة الحيّة'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _startButton(),
                      const SizedBox(height: 14),
                      _chartCard(isPhone),
                      const SizedBox(height: 14),
                      _statsGrid(isPhone),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _startButton() {
    return Raised3D(
      onTap: _toggle,
      radius: 16,
      depth: 6,
      padding: EdgeInsets.zero,
      edgeColor: _running ? const Color(0xFF9B1C1C) : Nq3d.indigoDark,
      glowColor: const Color(0x990F1660),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _running
            ? const [Color(0xFFE53935), Color(0xFFB71C1C)]
            : const [Color(0xFF283593), Nq3d.indigo],
      ),
      semanticLabel: _running ? 'إيقاف المراقبة' : 'بدء المراقبة',
      child: SizedBox(
        height: 54,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded,
                color: Colors.white),
            const SizedBox(width: 8),
            Text(_running ? 'إيقاف المراقبة' : 'بدء المراقبة',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(bool isPhone) {
    final spots = <FlSpot>[];
    for (var i = 0; i < _samples.length; i++) {
      final v = _samples[i];
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }
    final maxY = spots.isEmpty
        ? 100.0
        : (spots.map((e) => e.y).reduce((a, b) => a > b ? a : b) * 1.3)
            .clamp(30.0, 100000.0)
            .toDouble();
    final maxX =
        (_samples.isEmpty ? _maxSamples : _samples.length).toDouble() - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: raisedShadow(depth: 5, glow: const Color(0x661A237E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                    color: _running
                        ? const Color(0xFF2E7D32)
                        : Nq3d.faint,
                    shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(_running ? 'مباشر — زمن الاستجابة (ms)' : 'زمن الاستجابة (ms)',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: Nq3d.ink)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: isPhone ? 150 : 190,
            child: spots.isEmpty
                ? Center(
                    child: Text('اضغط «بدء المراقبة» لعرض الرسم الحيّ',
                        style: TextStyle(fontSize: 12, color: Nq3d.muted)),
                  )
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxX < 1 ? 1 : maxX,
                      minY: 0,
                      maxY: maxY,
                      lineTouchData: const LineTouchData(enabled: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 4,
                        getDrawingHorizontalLine: (v) => FlLine(
                            color: Colors.grey.withValues(alpha: 0.12),
                            strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            interval: maxY / 2,
                            getTitlesWidget: (v, meta) => Text(
                                v.toStringAsFixed(0),
                                style: const TextStyle(
                                    fontSize: 9, color: Nq3d.faint)),
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          preventCurveOverShooting: true,
                          color: Nq3d.indigo,
                          barWidth: 2.4,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Nq3d.indigo.withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(bool isPhone) {
    final items = <({String label, String value, Color color, IconData icon})>[
      (
        label: 'الحالي',
        value: _fmt(_current),
        color: Nq3d.indigo,
        icon: Icons.bolt_rounded
      ),
      (
        label: 'المتوسط',
        value: _fmt(_avg),
        color: const Color(0xFF3949AB),
        icon: Icons.timeline_rounded
      ),
      (
        label: 'الأدنى',
        value: _fmt(_min),
        color: const Color(0xFF2E7D32),
        icon: Icons.south_rounded
      ),
      (
        label: 'الأعلى',
        value: _fmt(_max),
        color: const Color(0xFFEF6C00),
        icon: Icons.north_rounded
      ),
      (
        label: 'التذبذب',
        value: _fmt(_jitter),
        color: const Color(0xFF6A1B9A),
        icon: Icons.ssid_chart_rounded
      ),
      (
        label: 'نسبة الفقد',
        value: '${_lossPercent.toStringAsFixed(0)} %',
        color: const Color(0xFFC62828),
        icon: Icons.scatter_plot_rounded
      ),
    ];
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 560 ? 3 : 2;
      final tileW = (c.maxWidth - (cols - 1) * 10) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items
            .map((it) => SizedBox(width: tileW, child: _statTile(it)))
            .toList(),
      );
    });
  }

  Widget _statTile(
      ({String label, String value, Color color, IconData icon}) it) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: raisedShadow(depth: 3, glow: const Color(0x331A237E)),
        border: Border.all(color: it.color.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(it.icon, size: 18, color: it.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(it.label,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                const SizedBox(height: 1),
                Text(it.value,
                    textDirection: TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        color: it.color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double? ms) =>
      ms == null ? '—' : '${ms.toStringAsFixed(ms >= 100 ? 0 : 1)} ms';
}
