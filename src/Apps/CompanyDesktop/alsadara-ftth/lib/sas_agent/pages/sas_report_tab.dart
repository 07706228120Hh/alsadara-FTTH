import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_report.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
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
      content: Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
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
          title: Text('تأكيد إرسال التصريح',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: Text(
            'ستُصرّح بإجمالي «$total» مشترك منهم «$active» نشط.\n'
            'يُقارَن تصريحك آلياً مع ما تُظهره الشركة. متابعة؟',
            style: GoogleFonts.cairo(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('إرسال', style: GoogleFonts.cairo()),
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
        padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
        children: [
          _banner(),
          SizedBox(height: 16.h),
          if (_canSubmit) ...[
            const SasSectionHeader(
              title: 'تصريح جديد',
              icon: Icons.edit_note_rounded,
              gradient: AppTheme.orangeGradient,
            ),
            SizedBox(height: 10.h),
            _reportForm(),
            SizedBox(height: 18.h),
          ],
          const SasSectionHeader(
            title: 'نتيجة المطابقة (البلنك)',
            icon: Icons.balance_rounded,
          ),
          SizedBox(height: 10.h),
          if (_recon != null)
            SasReconciliationCard(recon: _recon!)
          else
            _noReconHint(),
          SizedBox(height: 18.h),
          SasSectionHeader(
            title: 'سجلّ التصاريح',
            icon: Icons.history_rounded,
            gradient: AppTheme.greenGradient,
            trailingText: _reports.isEmpty ? null : '${_reports.length}',
          ),
          SizedBox(height: 10.h),
          _reportsHistory(),
        ],
        ),
      ),
    );
  }

  Widget _banner() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppTheme.blueGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        boxShadow: SasUi.cardShadow(AppTheme.primaryColor),
      ),
      child: Row(
        children: [
          Container(
            width: 46.w,
            height: 46.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child:
                Icon(Icons.assignment_rounded, color: Colors.white, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'التصريح الشهري (البلنك الموحّد)',
                  style: GoogleFonts.cairo(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  widget.account.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5.sp,
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
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'صرّح بعدد مشتركيك الفعلي — يُقارَن آلياً مع ما تنسبه الشركة إليك.',
            style: GoogleFonts.cairo(
                fontSize: 12.sp, color: Colors.grey[700], height: 1.5),
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: _numField(
                  controller: _totalCtrl,
                  label: 'العدد الكلّي المصرّح',
                  icon: Icons.people_rounded,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _numField(
                  controller: _activeCtrl,
                  label: 'النشط المصرّح',
                  icon: Icons.person_pin_circle_rounded,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          _textField(
            controller: _noteCtrl,
            label: 'ملاحظة (اختياري)',
            icon: Icons.notes_rounded,
          ),
          SizedBox(height: 14.h),
          SizedBox(
            height: 48.h,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SasUi.radius.r)),
              ),
              icon: _submitting
                  ? SizedBox(
                      width: 18.w,
                      height: 18.w,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 19),
              label: Text('إرسال التصريح',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800, fontSize: 14.sp)),
            ),
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
      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
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
      style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
      decoration: _inputDecoration(label, icon),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
      prefixIcon: Icon(icon, color: AppTheme.primaryColor, size: 20.sp),
      filled: true,
      fillColor: const Color(0xFFF7F8FC),
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.18)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        borderSide:
            const BorderSide(color: AppTheme.primaryColor, width: 1.6),
      ),
    );
  }

  Widget _noReconHint() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              color: Colors.grey[500], size: 20.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'لا نتيجة مطابقة بعد — تظهر بعد مزامنة الشركة وتصريحك الأول.',
              style: GoogleFonts.cairo(
                  fontSize: 12.5.sp, color: Colors.grey[700], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportsHistory() {
    if (_reports.isEmpty) {
      return Container(
        padding: EdgeInsets.all(14.w),
        decoration: SasUi.card(),
        child: Row(
          children: [
            Icon(Icons.inbox_rounded, color: Colors.grey[400], size: 20.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                'لا تصاريح سابقة لهذا الحساب بعد.',
                style: GoogleFonts.cairo(
                    fontSize: 12.5.sp, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final r in _reports) ...[
          _reportRow(r),
          SizedBox(height: 8.h),
        ],
      ],
    );
  }

  Widget _reportRow(SasAgentReport r) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Row(
        children: [
          SasUi.gradientBadge(
            icon: Icons.assignment_turned_in_rounded,
            colors: AppTheme.greenGradient,
            size: 40,
            iconSize: 20,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'كلّي: ${r.declaredTotal} · نشط: ${r.declaredActive}',
                  style: GoogleFonts.cairo(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E)),
                ),
                if (r.note.trim().isNotEmpty) ...[
                  SizedBox(height: 3.h),
                  Text(
                    r.note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: 11.5.sp, color: Colors.grey[600]),
                  ),
                ],
                if (r.createdAt != null) ...[
                  SizedBox(height: 3.h),
                  Text(
                    _fmtDate(r.createdAt!),
                    style: GoogleFonts.cairo(
                        fontSize: 11.sp,
                        color: Colors.grey[500],
                        fontWeight: FontWeight.w500),
                  ),
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
