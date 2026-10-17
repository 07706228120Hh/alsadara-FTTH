import 'dart:async';

import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_account.dart';
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_citizen_statement.dart';
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

  num get _totalOwed => _debtors.fold<num>(0, (sum, d) => sum + d.balance);

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
    final hasList = !_loading && _error == null && _debtors.isNotEmpty;
    return SdPage(
      maxWidth: SdSpace.formMax,
      scrollable: false,
      padding: hasList ? EdgeInsets.zero : null,
      appBar: SdAppBar(
        title: 'المدينون',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loading ? null : _refreshManual,
          ),
        ],
      ),
      body: _body(),
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
      return const SdEmptyState(
        title: 'لا يوجد مدينون',
        message: 'جميع الذمم مسدّدة',
        icon: Icons.verified_rounded,
        status: SdStatus.success,
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshManual,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.sm,
            SdSpace.gutter, SdSpace.lg),
        itemCount: _debtors.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: SdSpace.xs),
        itemBuilder: (_, i) {
          if (i == 0) return _summaryCard();
          return _debtorCard(_debtors[i - 1]);
        },
      ),
    );
  }

  Widget _summaryCard() {
    const t = SdStatus.danger;
    final tone = t.tone;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: [
          BoxShadow(color: tone.tintEdge, offset: const Offset(0, SdDepth.card))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tone.tintEdge,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.groups_rounded, color: tone.base, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_debtors.length} مدين', style: SdText.titleSm),
                const SizedBox(height: 2),
                Text('إجمالي الذمم المستحقّة', style: SdText.caption),
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('${_fmt(_totalOwed)} IQD',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: tone.base)),
          ),
        ],
      ),
    );
  }

  Widget _debtorCard(SasDebtor d) {
    return SdRaised(
      onTap: () => _openStatement(d),
      radius: SdRadius.lg,
      padding: const EdgeInsets.all(12),
      semanticLabel: d.name.isEmpty ? d.subscriberUid : d.name,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: SdColors.warningTint,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: SdColors.warning, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name.isEmpty ? d.subscriberUid : d.name,
                    overflow: TextOverflow.ellipsis, style: SdText.label),
                if (d.name.isNotEmpty && d.subscriberUid.isNotEmpty)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(d.subscriberUid,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: SdColors.faint)),
                  ),
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('${_fmt(d.balance)} IQD',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: SdColors.danger)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_left_rounded,
              color: SdColors.faint, size: 20),
        ],
      ),
    );
  }

  String _fmt(num v) =>
      (v == v.roundToDouble()) ? v.round().toString() : v.toString();
}
