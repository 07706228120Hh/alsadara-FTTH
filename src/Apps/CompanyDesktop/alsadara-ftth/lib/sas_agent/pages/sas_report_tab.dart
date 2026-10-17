import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../permissions/permission_manager.dart';
import '../models/sas_account.dart';
import '../models/sas_report.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_report_widgets.dart';
import '../widgets/sas_state_views.dart';

/// تبويب «تصريح/بلنك» — نموذج تصريح الوكيل + بطاقة المقاطعة (البلنك) + سجل
/// التصاريح، بثيم الصدارة. يعمل على الحساب المحدد عبر `/accounts/{id}/...`.
class SasReportTab extends StatefulWidget {
  final SasAccount account;
  const SasReportTab({super.key, required this.account});

  @override
  State<SasReportTab> createState() => _SasReportTabState();
}

class _SasReportTabState extends State<SasReportTab> {
  final _api = SasAgentApiService.instance;

  final _totalCtrl = TextEditingController();
  final _activeCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  SasReconciliation? _recon;
  List<SasAgentReport> _reports = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  bool get _canSubmit => PermissionManager.instance.canAdd('sas_agent');

  /// اشتراك ناقل التحديث المشترك — يعيد جلب المقاطعة/التصاريح عند أي حدث.
  StreamSubscription<SasRefreshEvent>? _busSub;

  @override
  void initState() {
    super.initState();
    _load();
    _busSub = SasRefreshBus.instance.stream.listen(_onBusEvent);
  }

  /// عند إشعار الناقل الخاص بهذا الحساب: أعد الجلب بصمت (بلا وميض).
  void _onBusEvent(SasRefreshEvent e) {
    if (!mounted || _loading || _submitting) return;
    if (!e.matches(widget.account.id)) return;
    _load(silent: true);
  }

  @override
  void didUpdateWidget(covariant SasReportTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) {
      _totalCtrl.clear();
      _activeCtrl.clear();
      _noteCtrl.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _busSub?.cancel();
    _totalCtrl.dispose();
    _activeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  /// [silent] يعيد الجلب دون إظهار حالة تحميل (بلا وميض) — يُستخدم عند إشعار
  /// الناقل؛ تُستبدل القيم عند وصول الجديدة.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      // المقاطعة أساسية؛ سجل التصاريح أفضل-جهد (قد يكون فارغاً قبل أول تصريح).
      final recon = await _api.getReconciliation(widget.account.id);
      List<SasAgentReport> reports = const [];
      try {
        reports = await _api.listReports(widget.account.id);
      } catch (_) {/* لا سجل بعد */}
      if (!mounted) return;
      setState(() {
        _recon = recon;
        _reports = reports;
        // تعبئة النموذج بآخر تصريح لتسهيل التعديل.
        if (_totalCtrl.text.isEmpty && reports.isNotEmpty) {
          _totalCtrl.text = '${reports.first.declaredTotal}';
          _activeCtrl.text = '${reports.first.declaredActive}';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontFamily: SdText.family, fontWeight: FontWeight.w600)),
      backgroundColor: error ? SdColors.danger : SdColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// سحب للتحديث: مزامنة الحساب (سحب SAS4→محلي) ثم إعادة جلب المقاطعة/التصاريح
  /// + إشعار بقية التبويبات. المزامنة معزولة؛ نُبقي العرض (silent) فلا يومض.
  Future<void> _refreshManual() async {
    await SasRefreshBus.instance
        .syncAndNotify(widget.account.id, reason: 'report-refresh-pull');
    if (mounted) await _load(silent: true);
  }

  Future<void> _submit() async {
    final total = int.tryParse(_totalCtrl.text.trim());
    final active = int.tryParse(_activeCtrl.text.trim()) ?? 0;
    if (total == null || total < 0) {
      _snack('أدخل العدد الكلّي المصرّح (رقم صحيح)', error: true);
      return;
    }
    if (active < 0 || active > total) {
      _snack('النشط يجب أن يكون بين 0 والعدد الكلّي', error: true);
      return;
    }

    // تأكيد قبل الإرسال.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد إرسال التصريح',
              style: TextStyle(
                  fontFamily: SdText.family, fontWeight: FontWeight.w800)),
          content: Text(
            'ستُصرّح بإجمالي «$total» مشترك منهم «$active» نشط.\n'
            'يُقارَن تصريحك آلياً مع ما تُظهره الشركة. متابعة؟',
            style: const TextStyle(fontFamily: SdText.family, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: SdText.family)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SdColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إرسال',
                  style: TextStyle(fontFamily: SdText.family)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    setState(() => _submitting = true);
    try {
      await _api.submitReport(
        widget.account.id,
        declaredTotal: total,
        declaredActive: active,
        note: _noteCtrl.text.trim(),
      );
      _snack('تم تسجيل تصريحك بنجاح');
      _noteCtrl.clear();
      await _load();
    } catch (e) {
      _snack(_clean(e), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SasLoadingView(message: 'جاري جلب التصريح…');
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);

    return RefreshIndicator(
      onRefresh: _refreshManual,
      child: SasContentWrap(
        maxWidth: 900,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            _banner(),
            const SizedBox(height: SdSpace.md),
            if (_canSubmit) ...[
              SdSectionHeader(
                  title: 'تصريح جديد', tone: SdGroup.comms.tone),
              const SizedBox(height: SdSpace.xs),
              _reportForm(),
              const SizedBox(height: SdSpace.md),
            ],
            const SdSectionHeader(title: 'نتيجة المطابقة (البلنك)'),
            const SizedBox(height: SdSpace.xs),
            if (_recon != null)
              SasReconciliationCard(recon: _recon!)
            else
              _noReconHint(),
            const SizedBox(height: SdSpace.md),
            SdSectionHeader(
              title: 'سجلّ التصاريح',
              tone: SdStatus.success.tone,
              count: _reports.isEmpty ? null : _reports.length,
            ),
            const SizedBox(height: SdSpace.xs),
            _reportsHistory(),
          ],
        ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SdColors.primaryMid, SdColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: [
          BoxShadow(color: SdColors.primaryEdge, offset: const Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: const Icon(Icons.assignment_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'التصريح الشهري (البلنك الموحّد)',
                  style: TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.account.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
                    color: Colors.white.withValues(alpha: 0.80),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportForm() {
    return SdCard(
      tone: SdGroup.comms.tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'صرّح بعدد مشتركيك الفعلي — يُقارَن آلياً مع ما تنسبه الشركة إليك.',
            style: SdText.bodySm.copyWith(height: 1.5),
          ),
          const SizedBox(height: SdSpace.sm),
          Row(
            children: [
              Expanded(
                child: _numField(
                  controller: _totalCtrl,
                  label: 'العدد الكلّي المصرّح',
                  icon: Icons.people_rounded,
                ),
              ),
              const SizedBox(width: SdSpace.xs),
              Expanded(
                child: _numField(
                  controller: _activeCtrl,
                  label: 'النشط المصرّح',
                  icon: Icons.person_pin_circle_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: SdSpace.xs),
          _textField(
            controller: _noteCtrl,
            label: 'ملاحظة (اختياري)',
            icon: Icons.notes_rounded,
          ),
          const SizedBox(height: SdSpace.sm),
          if (_submitting)
            const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: SdColors.primary),
                ),
              ),
            )
          else
            SdButton(
              label: 'إرسال التصريح',
              icon: Icons.send_rounded,
              expand: true,
              onPressed: _submit,
            ),
        ],
      ),
    );
  }

  Widget _numField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: const TextStyle(
          fontFamily: SdText.family,
          fontWeight: FontWeight.w700,
          color: SdColors.ink),
      decoration: _inputDecoration(label, icon),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(
          fontFamily: SdText.family,
          fontWeight: FontWeight.w600,
          color: SdColors.ink),
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    OutlineInputBorder border(Color color, [double width = 1.2]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          fontFamily: SdText.family, color: SdColors.muted),
      prefixIcon: Icon(icon, color: SdColors.primary, size: 20),
      filled: true,
      fillColor: SdColors.surfaceAlt,
      isDense: true,
      border: border(SdColors.edge),
      enabledBorder: border(SdColors.edge),
      focusedBorder: border(SdColors.primary, 1.6),
    );
  }

  Widget _noReconHint() {
    return SdCard(
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: SdColors.faint, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'لا نتيجة مطابقة بعد — تظهر بعد مزامنة الشركة وتصريحك الأول.',
              style: SdText.bodySm.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportsHistory() {
    if (_reports.isEmpty) {
      return SdCard(
        child: Row(
          children: [
            const Icon(Icons.inbox_rounded, color: SdColors.faint, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('لا تصاريح سابقة لهذا الحساب بعد.',
                  style: SdText.bodySm),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final r in _reports) ...[
          _reportRow(r),
          const SizedBox(height: SdSpace.xs),
        ],
      ],
    );
  }

  Widget _reportRow(SasAgentReport r) {
    final tone = SdStatus.success.tone;
    return SdCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tone.tint,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(color: tone.tintEdge, offset: const Offset(0, 3))
              ],
            ),
            child: Icon(Icons.assignment_turned_in_rounded,
                color: tone.base, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'كلّي: ${r.declaredTotal} · نشط: ${r.declaredActive}',
                  style: SdText.label,
                ),
                if (r.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    r.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: SdText.caption,
                  ),
                ],
                if (r.createdAt != null) ...[
                  const SizedBox(height: 3),
                  Text(_fmtDate(r.createdAt!),
                      style: SdText.caption
                          .copyWith(color: SdColors.faint)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}/${two(l.month)}/${two(l.day)} · ${two(l.hour)}:${two(l.minute)}';
  }
}
