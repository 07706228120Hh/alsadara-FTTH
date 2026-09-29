import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:platform_core/platform_core.dart';

/// تصريح الوكيل بعدد مشتركيه + صفّه في البلنك الموحّد (ما تُظهره SAS مقابل تصريحه).
class ReportScreen extends StatefulWidget {
  final StaffApi api;
  const ReportScreen({super.key, required this.api});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  PortalSummary? _s;
  ReconRow? _row;
  String? _error;
  final _total = TextEditingController();
  final _active = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.summary();
      final rec = await widget.api.reconciliation();
      final me = Session.agent.trim();
      ReconRow? row;
      for (final r in rec.rows) {
        if (r.agentUsername == me) { row = r; break; }
      }
      if (mounted) {
        setState(() {
          _s = s; _row = row; _error = null;
          if (_total.text.isEmpty && s.lastReport != null) {
            _total.text = '${s.lastReport!.declaredTotal}';
            _active.text = '${s.lastReport!.declaredActive}';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _submit() async {
    final t = int.tryParse(_total.text.trim());
    final a = int.tryParse(_active.text.trim()) ?? 0;
    final s = _s;
    if (t == null || t < 0) { showMsg(context, 'أدخل العدد الإجمالي', error: true); return; }
    if (a < 0 || a > t) { showMsg(context, 'النشط يجب أن يكون بين 0 والإجمالي', error: true); return; }
    if (s?.agent?.id == null || s?.company?.id == null) { showMsg(context, 'تعذّر تحديد هوية الوكيل — أعد المزامنة', error: true); return; }
    setState(() => _busy = true);
    try {
      await widget.api.submitReport(companyId: s!.company!.id, agentId: s.agent!.id!, declaredTotal: t, declaredActive: a, note: _note.text.trim());
      if (mounted) showMsg(context, 'تم تسجيل تصريحك');
      _note.clear();
      await _load();
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final tt = Theme.of(context).textTheme;
    return TabPage(
      title: 'تصريحي',
      subtitle: 'البلنك الموحّد — تصريحك مقابل بيانات SAS',
      onRefresh: _load,
      child: s == null
          ? (_error != null ? ErrorView(_error!, onRetry: _load) : const LoadingView())
          : Content(
              maxWidth: 720,
              child: ListView(padding: const EdgeInsets.all(14), children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('تصريح جديد', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('صرّح بعدد مشتركيك الفعلي. يُقارَن آلياً مع ما تنسبه الشركة إليك في SAS (${Fmt.n(s.agent?.usersCount ?? 0)}).', style: tt.bodySmall),
                      const SizedBox(height: 14),
                      TextField(controller: _total, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'إجمالي مشتركيّ')),
                      const SizedBox(height: 10),
                      TextField(controller: _active, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'منهم نشط')),
                      const SizedBox(height: 10),
                      TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _busy ? null : _submit,
                        icon: const Icon(PhosphorIconsBold.paperPlaneTilt, size: 18),
                        label: const Text('إرسال التصريح'),
                      ),
                    ]),
                  ),
                ),
                const SectionTitle('نتيجة المطابقة'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _row == null
                        ? Text('لا صفّ مطابقة بعد — يظهر بعد مزامنة الشركة وتصريحك الأول.', style: tt.bodyMedium)
                        : Column(children: [
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: StatusChip(verdictAr[_row!.verdict] ?? _row!.verdict, color: statusColor(_row!.verdict), icon: PhosphorIconsBold.scales),
                            ),
                            const SizedBox(height: 10),
                            KVRow('ما تنسبه الشركة إليك (SAS)', Fmt.n(_row!.sasAttributed)),
                            KVRow('ما صرّحت به', _row!.agentDeclared == 0 && _row!.verdict == 'no_report' ? '—' : Fmt.n(_row!.agentDeclared)),
                            KVRow('الفارق', _row!.verdict == 'no_report' ? '—' : Fmt.n(_row!.diff),
                                color: _row!.diff == 0 ? BrandColors.green : BrandColors.amber),
                            KVRow('آخر تصريح', Fmt.dateTime(_row!.lastReportTs)),
                            const Divider(),
                            Text(
                              _row!.verdict == 'company_suspicious'
                                  ? 'تصريحك أعلى مما تُظهره الشركة — قد تكون هناك خطوط غير مسجّلة باسمك لدى الشركة.'
                                  : _row!.verdict == 'agent_suspicious'
                                      ? 'تصريحك أقل مما تنسبه الشركة إليك — راجع قائمة مشتركيك.'
                                      : _row!.verdict == 'matched'
                                          ? 'الأرقام متطابقة ضمن هامش 5٪.'
                                          : 'لم تُصرّح بعد.',
                              style: tt.bodySmall,
                            ),
                          ]),
                  ),
                ),
                const SizedBox(height: 30),
              ]),
            ),
    );
  }
}
