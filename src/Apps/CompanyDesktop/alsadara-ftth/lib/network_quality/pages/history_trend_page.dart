/// أداة «السجلّ والاتجاه» — Network Quality (فحص متقدّم)
///
/// تعرض اتجاه نتائج الفحوص عبر الوقت (fl_chart) وقائمة الفحوص السابقة من
/// ScanHistoryService، مع مسح السجلّ وحالة فراغ واضحة. متجاوبة.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../frontend/frontend.dart';
import '../models/quality_models.dart';
import '../services/scan_history_service.dart';
import '../widgets/depth_3d.dart';
import '../widgets/quality_widgets.dart' show ratingColor;

class HistoryTrendPage extends StatefulWidget {
  const HistoryTrendPage({super.key, this.initialHistory});

  /// سجلّ محقون (لاختبار العرض بلا تخزين). الافتراضي: يُحمّل من الخدمة.
  final List<ScanSummary>? initialHistory;

  @override
  State<HistoryTrendPage> createState() => _HistoryTrendPageState();
}

enum _Metric { score, download, upload, ping }

class _HistoryTrendPageState extends State<HistoryTrendPage> {
  List<ScanSummary>? _items; // بترتيب زمني (الأقدم أولاً)
  bool _loading = true;
  _Metric _metric = _Metric.score;

  @override
  void initState() {
    super.initState();
    if (widget.initialHistory != null) {
      _items = widget.initialHistory;
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ScanHistoryService.all();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('مسح السجلّ'),
          content: const Text('هل تريد حذف كل الفحوص المحفوظة؟ لا يمكن التراجع.'),
          actions: [
            SdButton(
              label: 'إلغاء',
              kind: SdButtonKind.secondary,
              height: 44,
              onPressed: () => Navigator.pop(ctx, false),
            ),
            SdButton(
              label: 'مسح',
              kind: SdButtonKind.danger,
              height: 44,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await ScanHistoryService.clear();
      if (!mounted) return;
      setState(() => _items = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items ?? const [];
    return SdPage(
      padding: EdgeInsets.zero,
      scrollable: false,
      maxWidth: double.infinity,
      appBar: SdAppBar(
        title: 'السجلّ والاتجاه',
        actions: [
          if (items.isNotEmpty)
            SdAppBarAction(
              icon: Icons.delete_outline_rounded,
              label: 'مسح السجلّ',
              danger: true,
              onPressed: _confirmClear,
            ),
        ],
      ),
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
                child: _loading
                    ? _loadingView()
                    : items.isEmpty
                        ? _emptyView()
                        : _body(items, isPhone),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _loadingView() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: SdColors.primary),
          ),
        ),
      );

  Widget _emptyView() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: SdEmptyState(
          icon: Icons.timeline_rounded,
          title: 'لا سجلّ بعد — شغّل فحصاً',
          message: 'تُحفظ ملخّصات الفحوص تلقائياً هنا بعد كل فحص.',
        ),
      );

  Widget _body(List<ScanSummary> items, bool isPhone) {
    final newestFirst = items.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _metricTabs(),
        const SizedBox(height: 14),
        _trendCard(items, isPhone),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.history_rounded, size: 15, color: SdColors.faint),
            const SizedBox(width: 6),
            Text('الفحوص السابقة (${items.length})',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 6),
        ...newestFirst.map(_historyCard),
      ],
    );
  }

  Widget _metricTabs() {
    Widget tab(_Metric m, String label, Color color) {
      final selected = _metric == m;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _metric = m),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: selected ? Colors.white : SdColors.muted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: raisedShadow(depth: 3, glow: const Color(0x331A237E)),
      ),
      child: Row(
        children: [
          tab(_Metric.score, 'الدرجة', SdColors.primary),
          tab(_Metric.download, 'تنزيل', const Color(0xFF26A69A)),
          tab(_Metric.upload, 'رفع', SdColors.warning),
          tab(_Metric.ping, 'الاستجابة', SdColors.platformBase),
        ],
      ),
    );
  }

  ({Color color, String unit, double? Function(ScanSummary) pick}) get _spec {
    switch (_metric) {
      case _Metric.score:
        return (
          color: SdColors.primary,
          unit: '',
          pick: (s) => s.overallScore
        );
      case _Metric.download:
        return (
          color: const Color(0xFF26A69A),
          unit: 'Mbps',
          pick: (s) => s.downloadMbps
        );
      case _Metric.upload:
        return (
          color: SdColors.warning,
          unit: 'Mbps',
          pick: (s) => s.uploadMbps
        );
      case _Metric.ping:
        return (
          color: SdColors.platformBase,
          unit: 'ms',
          pick: (s) => s.pingMs
        );
    }
  }

  /// الحدّ الأقصى لمحور Y حسب المقياس (آمن ضد القيم الفارغة/الواحدة).
  double _maxYFor(List<double> values) {
    final peak = values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    double ceilTo(double v, double step) => (v / step).ceilToDouble() * step;
    switch (_metric) {
      case _Metric.score:
        return 100.0; // الدرجة ثابتة 0–100 (لا تتجاوز 100)
      case _Metric.ping:
        return ceilTo(peak * 1.2, 10).clamp(50.0, 100000.0).toDouble();
      case _Metric.download:
      case _Metric.upload:
        return ceilTo(peak * 1.2, 10).clamp(10.0, 1000000.0).toDouble();
    }
  }

  Widget _trendCard(List<ScanSummary> items, bool isPhone) {
    final spec = _spec;
    final spots = <FlSpot>[];
    for (var i = 0; i < items.length; i++) {
      final v = spec.pick(items[i]);
      if (v != null) spots.add(FlSpot(i.toDouble(), v));
    }
    final maxY = _maxYFor(spots.map((e) => e.y).toList());
    final maxX = (items.length - 1).clamp(1, 100000).toDouble();
    // يلزم نقطتان على الأقل لرسم خطّ ذي معنى.
    final enoughForLine = spots.length >= 2;

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
          Text('اتجاه ${_metricLabel()} عبر الوقت',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: SdColors.ink)),
          const SizedBox(height: 10),
          SizedBox(
            height: isPhone ? 160 : 200,
            child: !enoughForLine
                ? _singlePointView(spots.isEmpty ? null : spots.first.y, spec)
                : LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxX,
                      minY: 0,
                      maxY: maxY,
                      lineTouchData: const LineTouchData(enabled: false),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: maxY / 4,
                        getDrawingHorizontalLine: (v) => FlLine(
                            color: SdColors.faint.withValues(alpha: 0.12),
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
                            reservedSize: 36,
                            interval: maxY / 2,
                            getTitlesWidget: (v, meta) => Text(
                                v.toStringAsFixed(0),
                                style: const TextStyle(
                                    fontSize: 9, color: SdColors.faint)),
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          preventCurveOverShooting: true,
                          color: spec.color,
                          barWidth: 2.6,
                          dotData: FlDotData(
                            show: spots.length <= 20,
                            getDotPainter: (s, _, __, ___) =>
                                FlDotCirclePainter(
                                    radius: 3,
                                    color: spec.color,
                                    strokeWidth: 0),
                          ),
                          belowBarData: BarAreaData(
                            show: true,
                            color: spec.color.withValues(alpha: 0.12),
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

  /// عرض بديل عند توفّر قيمة واحدة (أو لا شيء): يبرز القيمة ويطلب فحصاً آخر.
  Widget _singlePointView(
      double? value,
      ({Color color, String unit, double? Function(ScanSummary) pick}) spec) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value == null
                    ? '—'
                    : value.toStringAsFixed(value >= 100 ? 0 : 1),
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    height: 1,
                    color: spec.color),
              ),
              if (spec.unit.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(spec.unit,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: spec.color.withValues(alpha: 0.7))),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(_metricLabel(),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: SdColors.ink)),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'سجّل فحصاً آخر لعرض الاتجاه — تحتاج نقطتين على الأقل.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: SdColors.muted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  String _metricLabel() {
    switch (_metric) {
      case _Metric.score:
        return 'الدرجة الكلّية';
      case _Metric.download:
        return 'سرعة التنزيل';
      case _Metric.upload:
        return 'سرعة الرفع';
      case _Metric.ping:
        return 'زمن الاستجابة';
    }
  }

  Widget _historyCard(ScanSummary s) {
    final c = ratingColor(s.overallRating);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SdColors.divider),
      ),
      child: Row(
        children: [
          // شارة الدرجة.
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: c.withValues(alpha: 0.4), width: 2),
            ),
            child: Text(s.overallScore.round().toString(),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    color: c)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_fmtDate(s.timestamp),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  '↓ ${_v(s.downloadMbps)} · ↑ ${_v(s.uploadMbps)} Mbps · ${_v(s.pingMs)} ms',
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: SdColors.muted,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(s.overallRating.arabicLabel,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }

  String _v(double? x) => x == null ? '—' : x.toStringAsFixed(x >= 100 ? 0 : 1);

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}/${two(d.month)}/${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }
}
