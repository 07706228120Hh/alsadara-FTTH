import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_renewal.dart';
import '../services/sas_agent_api_service.dart';
import '../whatsapp/whatsapp.dart';
import '../widgets/sas_billing_post_actions.dart';
import '../widgets/sas_metrics.dart';
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

  // ── واتساب: تذكير فردي وجماعي للمشتركين قرب الانتهاء ──

  /// يبني مستلِم واتساب من مرشّح تجديد (يملأ متغيّرات القالب من بياناته).
  WaRecipient _recipientOf(SasRenewalCandidate c) => WaRecipient(
        name: c.displayName,
        rawPhone: c.phone ?? '',
        vars: {
          'username': c.username,
          if (c.profile != null) 'profile': c.profile!,
          if (c.expiry != null) 'expiration': (c.expiry ?? '').split(' ').first,
          'days': '$_days',
        },
      );

  /// إرسال تذكير واتساب فردي: يبني الرسالة من قالب «تذكير» ويفتحها/يرسلها حسب النمط.
  Future<void> _sendWhatsAppOne(SasRenewalCandidate c) async {
    if (!c.hasPhone) {
      _snack('لا يوجد رقم هاتف لهذا المشترك', error: true);
      return;
    }
    final recipient = _recipientOf(c);
    if (!recipient.sendable) {
      _snack('رقم الهاتف غير صالح لواتساب (${c.phone})', error: true);
      return;
    }

    final settings = await WaSettingsStore().load();
    // نمط الخادم: شغّل الخادم المدمج تلقائياً قبل الإرسال.
    if (settings.mode == WaMode.server) {
      await WaServerLauncher.instance.ensureRunning(baseUrl: settings.serverUrl);
    }
    final tpl = await LocalTemplateStore().byId(WaTemplateIds.reminder);
    final text = tpl?.render(recipient.templateVars) ??
        renewalReminderMessage(
          name: c.displayName,
          username: c.username,
          expiration: (c.expiry ?? '').split(' ').first,
        );

    final sender = settings.buildSender();
    try {
      final res = await sender.sendOne(
        WaOutgoing(recipient: recipient, text: text),
      );
      if (!mounted) return;
      if (res.ok) {
        _snack(res.opened
            ? 'فُتحت محادثة واتساب — اضغط «إرسال»'
            : 'أُرسلت رسالة الواتساب بنجاح');
      } else {
        _snack(res.error ?? 'تعذّر إرسال الواتساب', error: true);
      }
    } finally {
      sender.dispose();
    }
  }

  /// إرسال واتساب جماعي للمحدَّدين عبر ورقة `wa_bulk_sheet`.
  Future<void> _sendWhatsAppBulk() async {
    if (_selected.isEmpty) {
      _snack('اختر مشتركاً واحداً على الأقل', error: true);
      return;
    }
    final recipients = _candidates
        .where((c) => _selected.contains(c.id))
        .map(_recipientOf)
        .toList();
    final withPhone = recipients.where((r) => r.rawPhone.trim().isNotEmpty).length;
    if (withPhone == 0) {
      _snack('لا يوجد أرقام هواتف للمشتركين المحدَّدين', error: true);
      return;
    }
    await showWaBulkSheet(context, recipients);
  }

  /// التدفّق المفوتر: حوار تحصيل غنيّ (نوع التحصيل + صيانة/خصم + تحذير فعلي) →
  /// `renewalBulkBilled` (تنفيذ فعلي يخصم من الرصيد) → لكل ناجح له إيصال: طباعة
  /// إيصال + واتساب (خلفياً تسلسلياً، كلٌّ معزول) مع عدّاد تقدّم → ملخّص النتائج.
  Future<void> _startRenewal() async {
    if (_selected.isEmpty) {
      _snack('اختر مشتركاً واحداً على الأقل', error: true);
      return;
    }
    if (!_canManage) return;

    final count = _selected.length;
    // 1) حوار التحصيل الغنيّ + التحذير الصريح (فعلي + طباعة N + إرسال N).
    final collection = await _showBilledConfirmDialog(count);
    if (collection == null || !mounted) return;

    // 2) التنفيذ الفعلي المفوتر.
    final ids = _selected.toList();
    setState(() => _busy = true);
    Map<String, dynamic> res;
    try {
      res = await _api.renewalBulkBilled(
        widget.account.id,
        subscriberIds: ids,
        action: 'extend',
        months: _months,
        collectionType: collection.collectionType,
        maintenanceFee: collection.maintenanceFee,
        manualDiscount: collection.manualDiscount,
        systemDiscountEnabled: true,
      );
    } catch (e) {
      _snack(_clean(e), error: true);
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    // 3) تفكيك النتائج.
    final results = _extractResults(res);
    final succeeded = results.where((r) => r.ok).toList();
    final failed = results.where((r) => !r.ok).toList();

    // 4) لكل ناجح له إيصال → طباعة + واتساب خلفياً (تسلسلياً، كلٌّ معزول) مع تقدّم.
    final withReceipt =
        succeeded.where((r) => r.receipt != null).toList(growable: false);
    if (withReceipt.isNotEmpty) {
      await _runPostActionsSequential(withReceipt);
    }

    // 5) ملخّص النتائج.
    if (!mounted) return;
    await _showResultsDialog(
      succeeded: succeeded.length,
      failed: failed.length,
      rows: results,
    );

    // بعد التنفيذ: أعد جلب القائمة (قد تتغيّر تواريخ الانتهاء).
    _selected.clear();
    await _load();
  }

  /// يُفكّك قائمة النتائج من رد `bulk-billed` (يدعم results/data/rows).
  List<_BilledResult> _extractResults(Map<String, dynamic> res) {
    final raw = res['results'] ?? res['data'] ?? res['rows'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => _BilledResult.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// ينفّذ الطباعة + الواتساب لكل ناجح تسلسلياً مع شريط تقدّم معياري، وكلٌّ
  /// داخل `try/catch` مستقل (لا يُفشل الدفعة). يُحدَّث العدّاد لكل عنصر.
  Future<void> _runPostActionsSequential(List<_BilledResult> rows) async {
    final total = rows.length;
    final progress = ValueNotifier<int>(0);

    // حوار تقدّم غير قابل للإغلاق (معزول عن حالة الودجة).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (_, done, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('طباعة الإيصالات وإرسال الرسائل…',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800, fontSize: 13.5.sp)),
                SizedBox(height: 12.h),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6.r),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : done / total,
                    minHeight: 10.h,
                    backgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryColor),
                  ),
                ),
                SizedBox(height: 10.h),
                Text('تمت معالجة $done من $total',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                        fontSize: 12.sp, color: Colors.grey[700])),
              ],
            ),
          ),
        ),
      ),
    );

    for (final r in rows) {
      try {
        final c = _candidateOf(r.uid);
        await SasBillingPostActions.run(
          r.receipt!,
          customerName: c?.displayName ?? r.subscriberUsername,
          phone: c?.phone,
          newExpiration: c?.expiry,
        );
      } catch (_) {
        // معزول — لا نُفشل الدفعة.
      }
      progress.value = progress.value + 1;
    }

    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
  }

  SasRenewalCandidate? _candidateOf(String uid) {
    for (final c in _candidates) {
      if (c.id == uid) return c;
    }
    return null;
  }

  /// حوار التحصيل الغنيّ قبل التنفيذ الفعلي: منتقي نوع التحصيل + حقلا صيانة/خصم
  /// اختياريان + **تحذير صريح** بأن العملية فعلية وتخصم من الرصيد وستطبع N
  /// إيصالاً وترسل N رسالة. يعيد [_SasCollection] عند التأكيد أو null عند الإلغاء.
  Future<_SasCollection?> _showBilledConfirmDialog(int count) {
    String collectionType = 'cash';
    final maintenanceCtl = TextEditingController();
    final discountCtl = TextEditingController();

    return showDialog<_SasCollection>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SasUi.radius.r)),
            title: Row(
              children: [
                const Icon(Icons.point_of_sale_rounded,
                    color: AppTheme.primaryColor, size: 24),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text('تأكيد التجديد الجماعي المفوتر',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryColor)),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // تحذير صريح.
                    Container(
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: AppTheme.warningColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
                        border: Border.all(
                            color:
                                AppTheme.warningColor.withValues(alpha: 0.30)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppTheme.warningColor, size: 20),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              'سيُجدَّد $_months شهر لعدد $count مشترك فعلياً '
                              'ويُخصَم من رصيدك.\n'
                              'وبعد النجاح سيُطبَع حتى $count إيصالاً ويُرسَل '
                              'حتى $count رسالة واتساب.',
                              style: GoogleFonts.cairo(
                                  fontSize: 12.5.sp,
                                  fontWeight: FontWeight.w700,
                                  height: 1.5,
                                  color: const Color(0xFF8A5A00)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 14.h),
                    Text('نوع التحصيل',
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.sp,
                            color: Colors.grey[700])),
                    SizedBox(height: 6.h),
                    Wrap(
                      spacing: 8.w,
                      runSpacing: 8.h,
                      children: [
                        _collectionChip('cash', 'نقد', collectionType,
                            (v) => setLocal(() => collectionType = v)),
                        _collectionChip('credit', 'أجل المشغّل', collectionType,
                            (v) => setLocal(() => collectionType = v)),
                        _collectionChip('agent', 'وكيل', collectionType,
                            (v) => setLocal(() => collectionType = v)),
                        _collectionChip('citizen', 'آجل (ذمة المواطن)',
                            collectionType,
                            (v) => setLocal(() => collectionType = v)),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    Row(
                      children: [
                        Expanded(
                          child: _miniField(
                              maintenanceCtl, 'أجور صيانة (اختياري)'),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child:
                              _miniField(discountCtl, 'خصم يدوي (اختياري)'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  ctx,
                  _SasCollection(
                    collectionType: collectionType,
                    maintenanceFee: num.tryParse(maintenanceCtl.text.trim()),
                    manualDiscount: num.tryParse(discountCtl.text.trim()),
                  ),
                ),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor),
                child: Text('تأكيد وتنفيذ',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collectionChip(String value, String label, String selected,
      ValueChanged<String> onPick) {
    final active = value == selected;
    return ChoiceChip(
      selected: active,
      onSelected: (_) => onPick(value),
      label: Text(label,
          style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : Colors.grey[700])),
      selectedColor: AppTheme.primaryColor,
      backgroundColor: Colors.grey.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
    );
  }

  Widget _miniField(TextEditingController ctl, String label) {
    return TextField(
      controller: ctl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            GoogleFonts.cairo(color: Colors.grey[600], fontSize: 11.5.sp),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
      ),
    );
  }

  Future<void> _showResultsDialog({
    required int succeeded,
    required int failed,
    required List<_BilledResult> rows,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(
                failed == 0
                    ? Icons.check_circle_rounded
                    : Icons.info_rounded,
                color:
                    failed == 0 ? AppTheme.successColor : AppTheme.warningColor,
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
                  'نجح: $succeeded · فشل: $failed',
                  style: GoogleFonts.cairo(
                      fontSize: 13.sp, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 12.h),
                Flexible(child: _resultsList(rows)),
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

  Widget _resultsList(List<_BilledResult> rows) {
    String nameOf(String uid, String fallback) {
      final c = _candidateOf(uid);
      if (c != null) return c.displayName;
      return fallback.isEmpty ? uid : fallback;
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
                    nameOf(r.uid, r.subscriberUsername),
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
            _whatsAppButton(c),
          ],
        ),
      ),
    );
  }

  /// زر واتساب فردي لكل مشترك — يرسل تذكير التجديد (يُعطَّل إن لا رقم هاتف).
  Widget _whatsAppButton(SasRenewalCandidate c) {
    final enabled = c.hasPhone;
    const wa = Color(0xFF25D366);
    return Tooltip(
      message: enabled ? 'تذكير عبر واتساب' : 'لا يوجد رقم هاتف',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? () => _sendWhatsAppOne(c) : null,
          borderRadius: BorderRadius.circular(10.r),
          child: Container(
            width: 38.w,
            height: 38.w,
            decoration: BoxDecoration(
              color: enabled
                  ? wa.withValues(alpha: 0.12)
                  : Colors.grey.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: enabled
                    ? wa.withValues(alpha: 0.35)
                    : Colors.grey.withValues(alpha: 0.20),
              ),
            ),
            child: Icon(
              Icons.chat_rounded,
              size: 18.sp,
              color: enabled ? wa : Colors.grey.withValues(alpha: 0.55),
            ),
          ),
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
            // إرسال تذكير واتساب جماعي للمحدَّدين.
            OutlinedButton.icon(
              onPressed:
                  (_busy || _selected.isEmpty) ? null : _sendWhatsAppBulk,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF25D366),
                side: BorderSide(
                    color: const Color(0xFF25D366).withValues(alpha: 0.45)),
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              ),
              icon: Icon(Icons.chat_rounded, size: 18.sp),
              label: Text('واتساب',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800, fontSize: 12.sp)),
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

/// نتيجة تجديد مفوتر لمشترك واحد من رد `renewal/bulk-billed` (تتضمّن `receipt`).
class _BilledResult {
  final String uid;
  final bool ok;
  final String message;
  final String subscriberUsername;

  /// بيانات الإيصال (إن نجح وأُنشئ) — تُمرَّر لمساعد الطباعة/الواتساب المشترك.
  final Map<String, dynamic>? receipt;

  const _BilledResult({
    required this.uid,
    required this.ok,
    required this.message,
    required this.subscriberUsername,
    this.receipt,
  });

  factory _BilledResult.fromJson(Map<String, dynamic> json) {
    final rawReceipt = json['receipt'];
    final rawUsername =
        (rawReceipt is Map) ? rawReceipt['subscriberUsername'] : null;
    return _BilledResult(
      uid: (json['uid'] ?? json['id'] ?? json['Id'] ?? '').toString(),
      ok: (json['ok'] ?? json['Ok'] ?? false) == true,
      message: (json['message'] ?? json['Message'] ?? '').toString(),
      subscriberUsername:
          (json['subscriberUsername'] ?? rawUsername ?? '').toString(),
      receipt: (rawReceipt is Map)
          ? rawReceipt.cast<String, dynamic>()
          : null,
    );
  }
}

/// اختيار المستخدم في حوار التحصيل: نوع التحصيل + الحقول الاختيارية.
class _SasCollection {
  final String collectionType; // cash | credit | agent
  final num? maintenanceFee;
  final num? manualDiscount;

  const _SasCollection({
    required this.collectionType,
    this.maintenanceFee,
    this.manualDiscount,
  });
}
