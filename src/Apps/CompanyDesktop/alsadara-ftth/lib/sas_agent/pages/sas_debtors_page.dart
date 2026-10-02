import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_citizen_statement.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_state_views.dart';

/// صفحة «المدينون» — قائمة المشتركين الذين عليهم ذمّة (آجل) للحساب المحدّد.
///
/// كلّ مدين يعرض الاسم/المعرّف + الرصيد المستحق، وبالنقر يُفتح كشف حسابه
/// (`SasCitizenStatementScreen`) للاطّلاع والتسديد. تُعاد القائمة عند العودة.
class SasDebtorsPage extends StatefulWidget {
  final SasAccount account;
  const SasDebtorsPage({super.key, required this.account});

  @override
  State<SasDebtorsPage> createState() => _SasDebtorsPageState();
}

class _SasDebtorsPageState extends State<SasDebtorsPage> {
  final _api = SasAgentApiService.instance;

  List<SasDebtor> _debtors = [];
  bool _loading = true;
  String? _error;

  /// اشتراك ناقل التحديث المشترك — يعيد جلب المدينين عند أي عملية/تسديد.
  StreamSubscription<SasRefreshEvent>? _busSub;

  @override
  void initState() {
    super.initState();
    _load();
    _busSub = SasRefreshBus.instance.stream.listen(_onBusEvent);
  }

  @override
  void dispose() {
    _busSub?.cancel();
    super.dispose();
  }

  /// عند إشعار الناقل الخاص بهذا الحساب: أعد الجلب بصمت (بلا وميض).
  void _onBusEvent(SasRefreshEvent e) {
    if (!mounted || _loading) return;
    if (!e.matches(widget.account.id)) return;
    _load(silent: true);
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  /// [silent] يعيد الجلب دون إظهار حالة تحميل (بلا وميض) — عند إشعار الناقل.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getDebtors(widget.account.id);
      if (!mounted) return;
      setState(() {
        _debtors = list;
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

  num get _totalOwed =>
      _debtors.fold<num>(0, (sum, d) => sum + d.balance);

  /// تحديث يدوي (زر/سحب): مزامنة الحساب ثم إعادة جلب المدينين + إشعار بقية
  /// التبويبات. المزامنة معزولة؛ نُبقي العرض (silent) فلا يومض.
  Future<void> _refreshManual() async {
    await SasRefreshBus.instance
        .syncAndNotify(widget.account.id, reason: 'debtors-refresh-button');
    if (mounted) await _load(silent: true);
  }

  Future<void> _openStatement(SasDebtor d) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SasCitizenStatementScreen(
          accountId: widget.account.id,
          userId: d.subscriberUid,
          subscriberName: d.name,
        ),
      ),
    );
    // بعد العودة قد يكون تمّ تسديد — أعد جلب القائمة.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('المدينون',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.white)),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _refreshManual,
            ),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب المدينين…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _load);
    }
    if (_debtors.isEmpty) {
      return const SasEmptyView(
        message: 'لا يوجد مدينون — جميع الذمم مسدّدة',
        icon: Icons.verified_rounded,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: RefreshIndicator(
          onRefresh: _refreshManual,
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 20.h),
            itemCount: _debtors.length + 1,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (_, i) {
              if (i == 0) return _summaryCard();
              return _debtorCard(_debtors[i - 1]);
            },
          ),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.errorColor.withValues(alpha: 0.12),
            AppTheme.errorColor.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border:
            Border.all(color: AppTheme.errorColor.withValues(alpha: 0.28), width: 1.3),
        boxShadow: SasUi.cardShadow(AppTheme.errorColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44.w,
            height: 44.w,
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.groups_rounded,
                color: AppTheme.errorColor, size: 23.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_debtors.length} مدين',
                    style: GoogleFonts.cairo(
                        fontSize: 14.sp, fontWeight: FontWeight.w800)),
                SizedBox(height: 2.h),
                Text('إجمالي الذمم المستحقّة',
                    style: GoogleFonts.cairo(
                        fontSize: 11.5.sp, color: Colors.grey[700])),
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('${_fmt(_totalOwed)} IQD',
                style: GoogleFonts.robotoMono(
                    fontSize: 17.sp,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }

  Widget _debtorCard(SasDebtor d) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        onTap: () => _openStatement(d),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: SasUi.card(),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_rounded,
                    color: AppTheme.warningColor, size: 20.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name.isEmpty ? d.subscriberUid : d.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A2E))),
                    if (d.name.isNotEmpty && d.subscriberUid.isNotEmpty)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(d.subscriberUid,
                            style: GoogleFonts.robotoMono(
                                fontSize: 10.5.sp, color: Colors.grey[500])),
                      ),
                  ],
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('${_fmt(d.balance)} IQD',
                    style: GoogleFonts.robotoMono(
                        fontSize: 13.5.sp,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.errorColor)),
              ),
              SizedBox(width: 4.w),
              Icon(Icons.chevron_left_rounded,
                  color: Colors.grey[400], size: 20.sp),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(num v) =>
      (v == v.roundToDouble()) ? v.round().toString() : v.toString();
}
