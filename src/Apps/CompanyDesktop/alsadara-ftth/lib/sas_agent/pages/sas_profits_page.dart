import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';

/// صفحة «تقرير الأرباح» — أرباح الساس للشركة ضمن فترة.
///
/// تعرض: إجمالي (كلفة · ربح · محصّل · عدد عمليات) + تفصيل حسب المنطقة والباقة.
/// الربح = المحصّل − الكلفة (يضمّ ربح الباقة + أجور صيانة المنطقة). company-scoped.
class SasProfitsPage extends StatefulWidget {
  const SasProfitsPage({super.key});

  @override
  State<SasProfitsPage> createState() => _SasProfitsPageState();
}

class _SasProfitsPageState extends State<SasProfitsPage> {
  final _api = SasAgentApiService.instance;

  SasProfitReport? _report;
  bool _loading = true;
  String? _error;

  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    // الافتراضي: الشهر الحالي.
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _load();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rep = await _api.getProfitsReport(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _report = rep;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _clean(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: (_from != null && _to != null)
          ? DateTimeRange(start: _from!, end: _to!)
          : null,
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(
          picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
    });
    _load();
  }

  String _n(num v) {
    final i = v.round();
    final s = i.abs().toString();
    final buf = StringBuffer();
    for (int k = 0; k < s.length; k++) {
      if (k > 0 && (s.length - k) % 3 == 0) buf.write(',');
      buf.write(s[k]);
    }
    return '${v < 0 ? '-' : ''}$buf';
  }

  @override
  Widget build(BuildContext context) {
    final hasData = !_loading && _error == null && _report != null;
    return SdPage(
      maxWidth: 980,
      scrollable: hasData,
      appBar: SdAppBar(
        title: 'تقرير الأرباح',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري حساب الأرباح…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _load);
    }
    final rep = _report;
    if (rep == null) {
      return const SdEmptyState(
          title: 'لا توجد بيانات', icon: Icons.bar_chart_rounded);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dateBar(),
        const SizedBox(height: SdSpace.sm),
        _totalsCard(rep.totals),
        const SizedBox(height: SdSpace.sm),
        _breakdown('حسب المنطقة', Icons.location_on_rounded,
            SdGroup.comms.tone, rep.byRegion),
        const SizedBox(height: SdSpace.sm),
        _breakdown('حسب الباقة', Icons.inventory_2_rounded, SdGroup.admin.tone,
            rep.byPackage),
      ],
    );
  }

  Widget _dateBar() {
    String fmt(DateTime? d) => d == null
        ? '—'
        : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return SdCard(
      padding: const EdgeInsets.all(SdSpace.sm),
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded,
              color: SdColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${fmt(_from)}  ←  ${fmt(_to)}',
                style: SdText.bodySm.copyWith(
                    color: SdColors.ink, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            onPressed: _loading ? null : _pickRange,
            icon: const Icon(Icons.edit_calendar_rounded,
                color: SdColors.primary),
            label: Text('تغيير الفترة',
                style: SdText.label.copyWith(color: SdColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _totalsCard(SasProfitRow t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SdColors.success, SdColors.success],
        ),
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: [
          BoxShadow(color: SdColors.successEdge, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.summarize_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text('الإجمالي (${t.count} عملية)',
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _totalItem('الربح', t.profit, Colors.white),
              _totalItem(
                  'المحصّل', t.revenue, Colors.white.withValues(alpha: 0.9)),
              _totalItem(
                  'الكلفة', t.cost, Colors.white.withValues(alpha: 0.9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalItem(String label, num value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: color.withValues(alpha: 0.85),
                  fontSize: 11.5)),
          const SizedBox(height: 4),
          Text(_n(value),
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontSize: 16)),
        ],
      ),
    );
  }

  Widget _breakdown(String title, IconData icon, SdTone tone,
      List<SasProfitRow> rows) {
    return SdCard(
      title: title,
      icon: icon,
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SdSpace.sm),
              child: Text('لا توجد بيانات في هذه الفترة', style: SdText.bodySm),
            )
          else ...[
            _headerRow(),
            for (var i = 0; i < rows.length; i++) _dataRow(rows[i], i.isOdd),
          ],
        ],
      ),
    );
  }

  Widget _headerRow() {
    Widget h(String t, int flex, {TextAlign align = TextAlign.start}) =>
        Expanded(
          flex: flex,
          child: Text(t,
              textAlign: align,
              style: const TextStyle(
                  fontFamily: SdText.family,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  color: Colors.white)),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
      decoration: const BoxDecoration(
        color: SdColors.primary,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(SdRadius.xs),
          topRight: Radius.circular(SdRadius.xs),
        ),
      ),
      child: Row(
        children: [
          h('المجموعة', 4),
          h('عدد', 2, align: TextAlign.center),
          h('الكلفة', 3, align: TextAlign.end),
          h('الربح', 3, align: TextAlign.end),
        ],
      ),
    );
  }

  Widget _dataRow(SasProfitRow r, bool alt) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
      color: alt ? SdColors.surfaceAlt : SdColors.surface,
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(r.label,
                style: const TextStyle(
                    fontFamily: SdText.family,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: SdColors.ink)),
          ),
          Expanded(
            flex: 2,
            child: Text('${r.count}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 12.5,
                    color: SdColors.ink)),
          ),
          Expanded(
            flex: 3,
            child: Text(_n(r.cost),
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: SdColors.muted)),
          ),
          Expanded(
            flex: 3,
            child: Text(_n(r.profit),
                textAlign: TextAlign.end,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: SdColors.success)),
          ),
        ],
      ),
    );
  }
}
