import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppTheme.primaryColor,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.greenGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('تقرير الأرباح',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.white)),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: _body(),
      ),
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
      return const SasEmptyView(
          message: 'لا توجد بيانات', icon: Icons.bar_chart_rounded);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
          children: [
            _dateBar(),
            SizedBox(height: 12.h),
            _totalsCard(rep.totals),
            SizedBox(height: 14.h),
            _breakdown('حسب المنطقة', Icons.location_on_rounded,
                AppTheme.orangeGradient, rep.byRegion),
            SizedBox(height: 14.h),
            _breakdown('حسب الباقة', Icons.inventory_2_rounded,
                AppTheme.blueGradient, rep.byPackage),
          ],
        ),
      ),
    );
  }

  Widget _dateBar() {
    String fmt(DateTime? d) =>
        d == null ? '—' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Row(
        children: [
          Icon(Icons.date_range_rounded,
              color: AppTheme.primaryColor, size: 20.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text('${fmt(_from)}  ←  ${fmt(_to)}',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700, fontSize: 12.5.sp)),
          ),
          TextButton.icon(
            onPressed: _loading ? null : _pickRange,
            icon: const Icon(Icons.edit_calendar_rounded),
            label: Text('تغيير الفترة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _totalsCard(SasProfitRow t) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: AppTheme.greenGradient),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize_rounded, color: Colors.white, size: 20.sp),
              SizedBox(width: 8.w),
              Text('الإجمالي (${t.count} عملية)',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: 14.sp)),
            ],
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              _totalItem('الربح', t.profit, Colors.white),
              _totalItem('المحصّل', t.revenue,
                  Colors.white.withValues(alpha: 0.9)),
              _totalItem('الكلفة', t.cost,
                  Colors.white.withValues(alpha: 0.9)),
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
              style: GoogleFonts.cairo(
                  color: color.withValues(alpha: 0.85), fontSize: 11.sp)),
          SizedBox(height: 4.h),
          Text(_n(value),
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: color, fontSize: 16.sp)),
        ],
      ),
    );
  }

  Widget _breakdown(
      String title, IconData icon, List<Color> gradient, List<SasProfitRow> rows) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SasSectionHeader(title: title, icon: icon, gradient: gradient),
          SizedBox(height: 10.h),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Text('لا توجد بيانات في هذه الفترة',
                  style: GoogleFonts.cairo(color: Colors.grey[600])),
            )
          else ...[
            _headerRow(),
            const Divider(height: 1),
            for (final r in rows) _dataRow(r),
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
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.sp,
                  color: Colors.grey[700])),
        );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
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

  Widget _dataRow(SasProfitRow r) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(r.label,
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700, fontSize: 12.sp)),
          ),
          Expanded(
            flex: 2,
            child: Text('${r.count}',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(fontSize: 12.sp)),
          ),
          Expanded(
            flex: 3,
            child: Text(_n(r.cost),
                textAlign: TextAlign.end,
                style: GoogleFonts.robotoMono(fontSize: 12.sp)),
          ),
          Expanded(
            flex: 3,
            child: Text(_n(r.profit),
                textAlign: TextAlign.end,
                style: GoogleFonts.robotoMono(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.sp,
                    color: AppTheme.successColor)),
          ),
        ],
      ),
    );
  }
}
