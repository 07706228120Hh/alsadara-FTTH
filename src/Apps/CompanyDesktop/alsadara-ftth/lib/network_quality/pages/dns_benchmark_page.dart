/// أداة «اختبار ومقارنة DNS» — Network Quality (فحص متقدّم)
///
/// تقيس زمن استجابة عدّة مزوّدات DNS وتعرضها كأعمدة مجسّمة (Isometric) مع إبراز
/// الأسرع، وقائمة تفصيلية. التنفيذ عبر UDP/53 بلا حزم (DnsBenchmarkService).
library;

import 'package:flutter/material.dart';

import '../services/dns_benchmark_service.dart';
import '../services/quality_scorer.dart';
import '../widgets/depth_3d.dart';
import '../widgets/quality_widgets.dart' show ratingColor;

class DnsBenchmarkPage extends StatefulWidget {
  const DnsBenchmarkPage({super.key, this.runner});

  /// مُشغّل قابل للحقن (لاختبار العرض بلا شبكة). الافتراضي: الخدمة الحقيقية.
  final Future<List<DnsResult>> Function()? runner;

  @override
  State<DnsBenchmarkPage> createState() => _DnsBenchmarkPageState();
}

class _DnsBenchmarkPageState extends State<DnsBenchmarkPage> {
  List<DnsResult>? _results;
  bool _running = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final r = await (widget.runner?.call() ?? DnsBenchmarkService.run());
      if (!mounted) return;
      setState(() {
        _running = false;
        _results = r;
        if (r.every((e) => !e.reachable)) {
          _error = 'تعذّر الوصول لأي مزوّد DNS — قد يحجب UDP/53 على هذه الشبكة.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = 'تعذّر إجراء اختبار DNS.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Nq3d.ground,
        appBar: nq3dAppBar('اختبار ومقارنة DNS'),
        body: LayoutBuilder(
          builder: (ctx, c) {
            final w = c.maxWidth;
            final isPhone = w < 600;
            final maxContentWidth = isPhone ? w : (w >= 1024 ? 640.0 : 560.0);
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: _running
                      ? _loading()
                      : _results == null
                          ? const SizedBox.shrink()
                          : _body(_results!, isPhone),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _loading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3, color: Nq3d.indigo),
          ),
          const SizedBox(height: 16),
          Text('جارٍ اختبار مزوّدات DNS...',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Nq3d.muted)),
        ],
      ),
    );
  }

  Widget _body(List<DnsResult> results, bool isPhone) {
    final reachable = results.where((e) => e.reachable).toList();
    final fastest = reachable.isNotEmpty ? reachable.first.provider.ip : '';
    // أقصى زمن للمقياس (لإبراز الفروق).
    final maxMs = reachable.isEmpty
        ? 100.0
        : (reachable.map((e) => e.avgMs!).reduce((a, b) => a > b ? a : b) * 1.15)
            .clamp(40.0, 100000.0)
            .toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // منصّة الأعمدة المجسّمة.
        Container(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: raisedShadow(depth: 5, glow: const Color(0x661A237E)),
          ),
          child: LayoutBuilder(builder: (ctx, cc) {
            final n = results.length;
            final colW =
                ((cc.maxWidth - 8) / n).clamp(48.0, 84.0).toDouble();
            final row = Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: results
                  .map((r) => _dnsColumn(r, maxMs, colW,
                      isFastest: r.provider.ip == fastest))
                  .toList(),
            );
            final needed = n * (colW + 8);
            return SizedBox(
              child: needed <= cc.maxWidth + 0.5
                  ? row
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: SizedBox(width: needed, child: row),
                    ),
            );
          }),
        ),
        const SizedBox(height: 14),
        if (_error != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: Color(0xFFC62828)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_error!,
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFFC62828))),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // قائمة تفصيلية مرتّبة.
        ...List.generate(
            results.length, (i) => _dnsRow(i, results[i], results[i].provider.ip == fastest)),
        const SizedBox(height: 16),
        Raised3D(
          onTap: _run,
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
          semanticLabel: 'إعادة الاختبار',
          child: const SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.refresh_rounded, color: Colors.white),
                SizedBox(width: 8),
                Text('إعادة الاختبار',
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

  Widget _dnsColumn(DnsResult r, double maxMs, double colW,
      {required bool isFastest}) {
    final rating = QualityScorer.rateDns(r.avgMs);
    final frac = r.reachable
        ? (1 - (r.avgMs! / maxMs)).clamp(0.12, 1.0).toDouble()
        : 0.05;
    return SizedBox(
      width: colW,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 18,
            child: isFastest
                ? const Icon(Icons.emoji_events_rounded,
                    color: Color(0xFFF9A825), size: 18)
                : null,
          ),
          IsoSpeedColumn(
            fraction: frac,
            shade: r.reachable ? ratingShade(rating) : IsoShade.muted,
            width: colW * 0.72,
          ),
          const SizedBox(height: 4),
          Text(r.provider.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: Nq3d.ink)),
          Text(
            r.reachable ? '${r.avgMs!.toStringAsFixed(0)} ms' : '—',
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                fontFamily: 'monospace',
                color: r.reachable ? ratingColor(rating) : Nq3d.faint),
          ),
        ],
      ),
    );
  }

  Widget _dnsRow(int index, DnsResult r, bool isFastest) {
    final rating = QualityScorer.rateDns(r.avgMs);
    final c = r.reachable ? ratingColor(rating) : const Color(0xFF9E9E9E);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isFastest
                ? const Color(0xFFF9A825).withValues(alpha: 0.6)
                : Colors.grey.withValues(alpha: 0.12),
            width: isFastest ? 1.4 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: Nq3d.indigo.withValues(alpha: 0.1),
                shape: BoxShape.circle),
            child: Text('${index + 1}',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Nq3d.indigo)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(r.provider.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                    if (isFastest) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.emoji_events_rounded,
                          color: Color(0xFFF9A825), size: 15),
                    ],
                  ],
                ),
                Text(r.provider.ip,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                r.reachable ? '${r.avgMs!.toStringAsFixed(0)} ms' : 'غير متاح',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    color: c),
              ),
              Text(
                isFastest
                    ? 'الأسرع — موصى به'
                    : (r.reachable ? '${r.ok}/${r.total} استجابة' : 'محجوب/خطأ'),
                style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
