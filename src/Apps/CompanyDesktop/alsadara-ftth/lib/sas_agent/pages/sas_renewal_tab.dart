import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_renewal.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';

/// تبويب «تجديد» — قائمة المشتركين قرب الانتهاء مع تحديد متعدّد وتجديد جماعي.
///
/// تدفّق التجديد بخطوتين:
///  1) **معاينة (dryRun=true)**: تعرض ما سيُنفَّذ لكل مشترك دون أي تغيير فعلي.
///  2) **تأكيد → تنفيذ (dryRun=false)**: يُنفَّذ فعلياً وتُعرَض نتيجة كل مشترك.
///
/// زر التنفيذ محكوم بصلاحية `sas_agent` عبر [PermissionManager.canAdd].
class SasRenewalTab extends StatefulWidget {
  final SasAccount account;
  const SasRenewalTab({super.key, required this.account});

  @override
  State<SasRenewalTab> createState() => _SasRenewalTabState();
}

class _SasRenewalTabState extends State<SasRenewalTab> {
  final _api = SasAgentApiService.instance;

  List<SasRenewalCandidate> _candidates = [];
  final Set<String> _selected = <String>{};
  bool _loading = true;
  String? _error;
  bool _busy = false; // أثناء المعاينة/التنفيذ

  int _days = 7;
  int _months = 1;

  static const _dayOptions = <int>[3, 7, 15, 30];

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SasRenewalTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) {
      _selected.clear();
      _load();
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await _api.getRenewalCandidates(widget.account.id, days: _days);
      if (!mounted) return;
      setState(() {
        _candidates = list;
        // أزل من التحديد ما لم يعد ضمن القائمة.
        _selected.removeWhere((id) => !list.any((c) => c.id == id));
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(String id, bool? v) {
    setState(() {
      if (v == true) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _toggleAll(bool select) {
    setState(() {
      _selected.clear();
      if (select) {
        _selected.addAll(_candidates.map((c) => c.id));
      }
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
    ));
  }

  /// الخطوة 1: معاينة (dryRun=true) ثم عرض حوار التأكيد؛ عند التأكيد → تنفيذ.
  Future<void> _startRenewal() async {
    if (_selected.isEmpty) {
      _snack('اختر مشتركاً واحداً على الأقل', error: true);
      return;
    }
    if (!_canManage) return;

    setState(() => _busy = true);
    List<SasRenewalResult> preview;
    try {
      preview = await _api.renewalBulk(
        widget.account.id,
        subscriberIds: _selected.toList(),
        months: _months,
        dryRun: true,
      );
    } catch (e) {
      _snack(_clean(e), error: true);
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final confirmed = await _showPreviewDialog(preview);
    if (confirmed != true) return;

    // الخطوة 2: تنفيذ فعلي (dryRun=false).
    setState(() => _busy = true);
    try {
      final results = await _api.renewalBulk(
        widget.account.id,
        subscriberIds: _selected.toList(),
        months: _months,
        dryRun: false,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _showResultsDialog(results);
      // بعد التنفيذ: أعد جلب القائمة (قد تتغيّر تواريخ الانتهاء).
      _selected.clear();
      await _load();
    } catch (e) {
      _snack(_clean(e), error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _showPreviewDialog(List<SasRenewalResult> preview) {
    final okCount = preview.where((r) => r.ok).length;
    final failCount = preview.length - okCount;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.preview_rounded, color: AppTheme.primaryColor),
              SizedBox(width: 8.w),
              Text('معاينة التجديد',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ],
          ),
          content: SizedBox(
            width: 420.w,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'سيتم تجديد $_months شهر لعدد ${preview.length} مشترك.\n'
                  'صالح: $okCount · تحذيرات: $failCount\n'
                  'هذه معاينة فقط — لم يُنفَّذ أي تغيير بعد.',
                  style: GoogleFonts.cairo(fontSize: 12.5.sp),
                ),
                SizedBox(height: 12.h),
                Flexible(
                  child: _resultsList(preview),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check_rounded),
              label: Text('تأكيد وتنفيذ', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showResultsDialog(List<SasRenewalResult> results) {
    final okCount = results.where((r) => r.ok).length;
    final failCount = results.length - okCount;
    return showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                failCount == 0
                    ? Icons.check_circle_rounded
                    : Icons.info_rounded,
                color: failCount == 0
                    ? AppTheme.successColor
                    : AppTheme.warningColor,
              ),
              SizedBox(width: 8.w),
              Text('نتيجة التجديد',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ],
          ),
          content: SizedBox(
            width: 420.w,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'نجح: $okCount · فشل: $failCount',
                  style: GoogleFonts.cairo(
                      fontSize: 13.sp, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12.h),
                Flexible(child: _resultsList(results)),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('تم', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultsList(List<SasRenewalResult> rows) {
    // ابحث عن اسم المشترك من المرشّحين لعرض أوضح.
    String nameOf(String id) {
      final c = _candidates.where((e) => e.id == id);
      return c.isEmpty ? id : c.first.displayName;
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: rows.length,
      separatorBuilder: (_, __) => Divider(height: 10.h),
      itemBuilder: (_, i) {
        final r = rows[i];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              r.ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 18.sp,
              color: r.ok ? AppTheme.successColor : AppTheme.errorColor,
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nameOf(r.id),
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp, fontWeight: FontWeight.w700),
                  ),
                  if (r.message.isNotEmpty)
                    Text(
                      r.message,
                      style: GoogleFonts.cairo(
                          fontSize: 11.sp, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _controls(),
        Expanded(child: _body()),
        if (_candidates.isNotEmpty) _bottomBar(),
      ],
    );
  }

  Widget _controls() {
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 6.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      decoration: SasUi.card(),
      child: Row(
        children: [
          Icon(Icons.event_repeat_rounded,
              size: 17.sp, color: AppTheme.primaryColor),
          SizedBox(width: 6.w),
          Text('قرب الانتهاء خلال:',
              style: GoogleFonts.cairo(
                  fontSize: 12.5.sp, fontWeight: FontWeight.w700)),
          SizedBox(width: 8.w),
          DropdownButton<int>(
            value: _days,
            style: GoogleFonts.cairo(
                fontSize: 13.sp, color: Colors.black87),
            items: [
              for (final d in _dayOptions)
                DropdownMenuItem(value: d, child: Text('$d يوم')),
            ],
            onChanged: _busy
                ? null
                : (v) {
                    if (v == null) return;
                    setState(() => _days = v);
                    _load();
                  },
          ),
          const Spacer(),
          if (_candidates.isNotEmpty)
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _toggleAll(_selected.length != _candidates.length),
              icon: Icon(
                _selected.length == _candidates.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
                size: 18.sp,
              ),
              label: Text(
                _selected.length == _candidates.length
                    ? 'إلغاء الكل'
                    : 'تحديد الكل',
                style: GoogleFonts.cairo(fontSize: 12.sp),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب المشتركين قرب الانتهاء…');
    }
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_candidates.isEmpty) {
      return const SasEmptyView(
        message: 'لا يوجد مشتركون قرب الانتهاء ضمن المدة المحددة',
        icon: Icons.event_available_rounded,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 12.h),
        itemCount: _candidates.length,
        separatorBuilder: (_, __) => SizedBox(height: 8.h),
        itemBuilder: (_, i) => _candidateCard(_candidates[i]),
      ),
    );
  }

  Widget _candidateCard(SasRenewalCandidate c) {
    final checked = _selected.contains(c.id);
    return InkWell(
      onTap: () => _toggle(c.id, !checked),
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: checked
              ? AppTheme.primaryColor.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(SasUi.radius.r),
          border: Border.all(
            color: checked
                ? AppTheme.primaryColor.withValues(alpha: 0.45)
                : Colors.grey.withValues(alpha: 0.16),
            width: checked ? 1.6 : 1.2,
          ),
          boxShadow: checked
              ? SasUi.cardShadow(AppTheme.primaryColor)
              : SasUi.cardShadow(),
        ),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              activeColor: AppTheme.primaryColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6.r)),
              onChanged: (v) => _toggle(c.id, v),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A2E)),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    [
                      if (c.username.isNotEmpty) c.username,
                      if (c.profile != null && c.profile!.isNotEmpty)
                        'باقة: ${c.profile}',
                      if (c.expiry != null && c.expiry!.isNotEmpty)
                        'انتهاء: ${c.expiry}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: 11.5.sp, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SasUi.radius.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 12.h),
        child: Row(
          children: [
            Text('الأشهر:',
                style: GoogleFonts.cairo(
                    fontSize: 12.5.sp, fontWeight: FontWeight.w700)),
            SizedBox(width: 6.w),
            _monthStepper(),
            const Spacer(),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                'محدّد: ${_selected.length}',
                style: GoogleFonts.cairo(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryColor),
              ),
            ),
            SizedBox(width: 10.w),
            FilledButton.icon(
              onPressed: (!_canManage || _busy || _selected.isEmpty)
                  ? null
                  : _startRenewal,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                disabledBackgroundColor:
                    Colors.grey.withValues(alpha: 0.30),
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              ),
              icon: _busy
                  ? SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.autorenew_rounded),
              label: Text(
                _canManage ? 'تجديد' : 'لا صلاحية',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthStepper() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _busy || _months <= 1
                ? null
                : () => setState(() => _months--),
            icon: Icon(Icons.remove_rounded, size: 18.sp),
          ),
          Text('$_months',
              style: GoogleFonts.cairo(
                  fontSize: 14.sp, fontWeight: FontWeight.w800)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _busy || _months >= 60
                ? null
                : () => setState(() => _months++),
            icon: Icon(Icons.add_rounded, size: 18.sp),
          ),
        ],
      ),
    );
  }
}
