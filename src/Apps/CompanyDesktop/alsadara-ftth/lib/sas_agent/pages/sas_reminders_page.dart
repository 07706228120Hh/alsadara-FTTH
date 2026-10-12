import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_renewal.dart';
import '../services/sas_agent_api_service.dart';
import '../services/sas_reminder_scheduler.dart';
import '../whatsapp/whatsapp.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';

/// صفحة «الإشعارات والتذكير» — ترسل رسالة واتساب تذكيرية للمشتركين الذين تنتهي
/// اشتراكاتهم خلال N يوماً (إرسال يدوي «إرسال الآن» في هذه المرحلة).
///
/// تعيد استخدام البنية القائمة:
///  • [SasAgentApiService.getRenewalCandidates] لجلب «قرب الانتهاء» بـ`days=N`.
///  • قالب الواتساب [WaTemplateIds.reminder] («تذكير قرب الانتهاء») افتراضياً.
///  • ورقة الإرسال الجماعي [showWaBulkSheet] التي تتولّى الخادم/القالب/التقدّم.
///
/// لا منطق مالي هنا — مجرّد رسالة تذكير. العزل (شركة + مالك + صلاحية `sas_agent`)
/// يفرضه الخادم؛ لا نمرّر أي هوية هنا.
class SasRemindersPage extends StatefulWidget {
  final SasAccount account;
  const SasRemindersPage({super.key, required this.account});

  @override
  State<SasRemindersPage> createState() => _SasRemindersPageState();
}

class _SasRemindersPageState extends State<SasRemindersPage> {
  final _api = SasAgentApiService.instance;

  /// مفتاح حفظ تفضيل عدد الأيام محلياً (خاص بالساس).
  static const _prefsDaysKey = 'sas_reminder_days';

  /// أزرار الأيام السريعة.
  static const _quickDays = <int>[1, 2, 3, 7];

  int _days = 1;
  final _customDaysCtl = TextEditingController();

  List<SasRenewalCandidate> _candidates = [];
  bool _loading = false; // لم نجلب بعد — فارغ مبدئياً حتى يضغط المستخدم.
  bool _fetched = false;
  String? _error;

  // ─── حالة التذكير التلقائي (المجدوِل) ───
  final _scheduler = SasReminderScheduler.instance;

  /// إعدادات التذكير التلقائي المحمَّلة (افتراضياً معطَّل).
  SasAutoReminderSettings _auto = const SasAutoReminderSettings();

  /// آخر تاريخ تشغيل (YYYY-MM-DD) أو null.
  String? _autoLastRun;

  /// سجلّ مصغّر لآخر عمليات التشغيل.
  List<SasReminderRunLog> _autoLog = const [];

  /// هل النمط الحالي آلي (خادم)؟ إن لا، الإرسال التلقائي لن يعمل — نحذّر المستخدم.
  bool _autoMode = true;

  @override
  void initState() {
    super.initState();
    _restoreDays();
    _loadAuto();
  }

  /// يحمّل إعدادات التذكير التلقائي + السجلّ + نمط الواتساب الحالي.
  Future<void> _loadAuto() async {
    try {
      final s = await _scheduler.loadSettings();
      final last = await _scheduler.lastRunDate();
      final log = await _scheduler.loadLog();
      final wa = await WaSettingsStore().load();
      if (!mounted) return;
      setState(() {
        _auto = s;
        _autoLastRun = last;
        _autoLog = log;
        _autoMode = wa.buildSender().capabilities.automated;
        // زامِن منتقي الأيام مع إعداد المجدوِل إن اختلف (مصدر واحد للأيام).
        if (s.days > 0) _days = s.days;
      });
    } catch (_) {
      // إعداد محلي — فشله غير حرج.
    }
  }

  /// يحفظ إعدادات التذكير التلقائي ويعيد ضبط المجدوِل فوراً ثم يحدّث العرض.
  Future<void> _saveAuto(SasAutoReminderSettings s) async {
    setState(() => _auto = s);
    await _scheduler.saveSettings(s);
    final last = await _scheduler.lastRunDate();
    final log = await _scheduler.loadLog();
    if (!mounted) return;
    setState(() {
      _autoLastRun = last;
      _autoLog = log;
    });
  }

  @override
  void dispose() {
    _customDaysCtl.dispose();
    super.dispose();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _restoreDays() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_prefsDaysKey);
      if (saved != null && saved > 0 && mounted) {
        setState(() => _days = saved);
      }
    } catch (_) {
      // تفضيل محلي — فشله غير حرج.
    }
  }

  Future<void> _saveDays(int days) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsDaysKey, days);
    } catch (_) {
      // تفضيل محلي — فشله غير حرج.
    }
  }

  void _setDays(int days) {
    if (days < 1) days = 1;
    if (days > 365) days = 365;
    setState(() => _days = days);
    _saveDays(days);
    // وحّد عدد الأيام مع إعداد المجدوِل (مصدر واحد — منتقي الأيام يغذّي كليهما).
    if (_auto.days != days) {
      _saveAuto(_auto.copyWith(days: days));
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

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
      _fetched = true;
    });
    try {
      final list = await _api.getRenewalCandidates(widget.account.id,
          days: _days);
      if (!mounted) return;
      setState(() => _candidates = list);
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// يبني مستلِم واتساب من مرشّح تجديد (نفس نمط `sas_renewal_tab._recipientOf`).
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

  /// عدد المرشّحين الذين يملكون رقم هاتف صالح لواتساب (بعد التطبيع).
  int get _sendableCount =>
      _candidates.where((c) => _recipientOf(c).sendable).length;

  /// إرسال التذكير الآن لكل المرشّحين عبر ورقة الإرسال الجماعي.
  Future<void> _sendNow() async {
    if (_candidates.isEmpty) {
      _snack('لا يوجد مشتركون — اجلب القائمة أولاً', error: true);
      return;
    }
    final recipients = _candidates.map(_recipientOf).toList();
    final sendable = recipients.where((r) => r.sendable).length;
    if (sendable == 0) {
      _snack('لا يوجد أرقام هواتف صالحة لإرسال التذكير', error: true);
      return;
    }
    await showWaBulkSheet(context, recipients);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          toolbarHeight: 56,
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text('الإشعارات والتذكير',
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        body: SasContentWrap(
          maxWidth: 1000,
          child: Column(
            children: [
              _autoCard(),
              _controls(),
              Expanded(child: _body()),
              if (_fetched && !_loading && _error == null)
                _bottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── بطاقة التذكير التلقائي (المجدوِل) ───────────────────────────

  /// نصّ «التشغيل القادم» المحسوب من الموعد اليومي + حالة التشغيل اليوم.
  String _nextRunLabel() {
    final now = DateTime.now();
    final today = _dateKey(now);
    final due = DateTime(now.year, now.month, now.day, _auto.hour, _auto.minute);
    // إن شُغِّل اليوم أو فات الموعد → القادم غداً في نفس الساعة.
    if (_autoLastRun == today || now.isAfter(due)) {
      final tomorrow = due.add(const Duration(days: 1));
      return 'غداً ${_auto.timeLabel} (${_dateKey(tomorrow)})';
    }
    return 'اليوم ${_auto.timeLabel}';
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _auto.hour, minute: _auto.minute),
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null) {
      _saveAuto(_auto.copyWith(hour: picked.hour, minute: picked.minute));
    }
  }

  Widget _autoCard() {
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 0),
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان + مفتاح التفعيل
          Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 19.sp, color: AppTheme.primaryColor),
              SizedBox(width: 8.w),
              Expanded(
                child: Text('التذكير التلقائي اليومي',
                    style: GoogleFonts.cairo(
                        fontSize: 14.sp, fontWeight: FontWeight.w800)),
              ),
              Switch(
                value: _auto.enabled,
                activeThumbColor: AppTheme.primaryColor,
                onChanged: (v) => _saveAuto(_auto.copyWith(enabled: v)),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          // تنويه دائم: يعمل أثناء فتح التطبيق فقط.
          _hintRow(
            Icons.info_outline_rounded,
            'يعمل أثناء فتح التطبيق فقط — إن أُغلق التطبيق لا يُرسَل التذكير.',
            AppTheme.primaryColor,
          ),
          // تحذير النمط اليدوي.
          if (_auto.enabled && !_autoMode) ...[
            SizedBox(height: 6.h),
            _hintRow(
              Icons.warning_amber_rounded,
              'نمط الواتساب الحالي يدوي — الإرسال التلقائي لن يعمل. '
              'فعّل نمط «الخادم» من إعدادات الواتساب ليُرسَل تلقائياً.',
              AppTheme.warningColor,
            ),
          ],
          if (_auto.enabled) ...[
            SizedBox(height: 12.h),
            // منتقي الوقت + الأيام
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8.w,
              runSpacing: 8.h,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(
                        color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(SasUi.radiusSm.r)),
                  ),
                  icon: Icon(Icons.access_time_rounded, size: 17.sp),
                  label: Text('الموعد: ${_auto.timeLabel}',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
                  ),
                  child: Text('قبل الانتهاء بـ ${_auto.days} يوم',
                      style: GoogleFonts.cairo(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryColor)),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            // التشغيل القادم / آخر تشغيل
            Row(
              children: [
                Expanded(
                  child: _infoChip('التشغيل القادم', _nextRunLabel(),
                      Icons.event_rounded, AppTheme.primaryColor),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: _infoChip(
                      'آخر تشغيل',
                      _autoLastRun ?? 'لم يُشغَّل بعد',
                      Icons.history_rounded,
                      AppTheme.successColor),
                ),
              ],
            ),
            if (_autoLog.isNotEmpty) ...[
              SizedBox(height: 12.h),
              Text('سجلّ آخر العمليات',
                  style: GoogleFonts.cairo(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey[700])),
              SizedBox(height: 6.h),
              for (final e in _autoLog.take(5)) _logRow(e),
            ],
          ],
        ],
      ),
    );
  }

  Widget _hintRow(IconData icon, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15.sp, color: color),
        SizedBox(width: 6.w),
        Expanded(
          child: Text(text,
              style: GoogleFonts.cairo(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ),
      ],
    );
  }

  Widget _infoChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16.sp, color: color),
          SizedBox(width: 7.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.cairo(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600])),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logRow(SasReminderRunLog e) {
    final at = e.at;
    final when =
        '${_dateKey(at)} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final ok = e.sent > 0;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 15.sp,
            color: ok ? AppTheme.successColor : Colors.grey[500],
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$when · إجمالي ${e.total} · أُرسل ${e.sent} · فشل ${e.failed}',
                  style: GoogleFonts.cairo(
                      fontSize: 10.5.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey[800]),
                ),
                if (e.note.isNotEmpty)
                  Text(e.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: 10.sp, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── شريط التحكّم (منتقي الأيام) ───────────────────────────

  Widget _controls() {
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 6.h),
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_rounded,
                  size: 18.sp, color: AppTheme.primaryColor),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'تذكير المشتركين قبل انتهاء اشتراكهم بـ:',
                  style: GoogleFonts.cairo(
                      fontSize: 13.sp, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final d in _quickDays)
                ChoiceChip(
                  selected: _days == d,
                  onSelected: _loading ? null : (_) => _setDays(d),
                  label: Text('$d يوم',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700,
                          color: _days == d ? Colors.white : Colors.grey[700])),
                  selectedColor: AppTheme.primaryColor,
                  backgroundColor: Colors.grey.withValues(alpha: 0.10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
                ),
              SizedBox(
                width: 150.w,
                child: TextField(
                  controller: _customDaysCtl,
                  enabled: !_loading,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700, fontSize: 13.sp),
                  onSubmitted: (v) {
                    final n = int.tryParse(v.trim());
                    if (n != null && n > 0) _setDays(n);
                  },
                  decoration: InputDecoration(
                    labelText: 'عدد مخصّص',
                    labelStyle: GoogleFonts.cairo(
                        color: Colors.grey[600], fontSize: 11.5.sp),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(Icons.check_rounded, size: 18.sp),
                      onPressed: _loading
                          ? null
                          : () {
                              final n =
                                  int.tryParse(_customDaysCtl.text.trim());
                              if (n != null && n > 0) _setDays(n);
                            },
                    ),
                    border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(SasUi.radiusSm.r)),
                  ),
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text('المحدّد: $_days يوم',
                    style: GoogleFonts.cairo(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor)),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _fetch,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: EdgeInsets.symmetric(vertical: 13.h),
              ),
              icon: _loading
                  ? SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(Icons.search_rounded, size: 19.sp),
              label: Text('جلب قائمة قرب الانتهاء',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── جسم الصفحة (حالات) ───────────────────────────

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(
          message: 'جاري جلب المشتركين قرب الانتهاء…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _fetch);
    }
    if (!_fetched) {
      return const SasEmptyView(
        message:
            'اختر عدد الأيام ثم اضغط «جلب قائمة قرب الانتهاء» لعرض المشتركين',
        icon: Icons.notifications_none_rounded,
      );
    }
    if (_candidates.isEmpty) {
      return const SasEmptyView(
        message: 'لا يوجد مشتركون قرب الانتهاء ضمن المدة المحددة',
        icon: Icons.event_available_rounded,
      );
    }
    return Column(
      children: [
        _summaryBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetch,
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 12.h),
              itemCount: _candidates.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, i) => _candidateCard(_candidates[i]),
            ),
          ),
        ),
      ],
    );
  }

  /// شريط عدّاد الإجمالي + تمييز عدد من بلا رقم صالح.
  Widget _summaryBar() {
    final total = _candidates.length;
    final noPhone = total - _sendableCount;
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 8.h, 14.w, 2.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: SasUi.card(),
      child: Row(
        children: [
          SasStatusBadge(
            label: 'الإجمالي: $total',
            color: AppTheme.primaryColor,
            icon: Icons.people_rounded,
          ),
          SizedBox(width: 8.w),
          SasStatusBadge(
            label: 'سيصلهم: $_sendableCount',
            color: AppTheme.successColor,
            icon: Icons.chat_rounded,
          ),
          if (noPhone > 0) ...[
            SizedBox(width: 8.w),
            SasStatusBadge(
              label: 'بلا رقم: $noPhone',
              color: AppTheme.warningColor,
              icon: Icons.phone_disabled_rounded,
            ),
          ],
        ],
      ),
    );
  }

  Widget _candidateCard(SasRenewalCandidate c) {
    final sendable = _recipientOf(c).sendable;
    final daysLeft = _daysUntil(c.expiry);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border: Border.all(
          color: sendable
              ? Colors.grey.withValues(alpha: 0.16)
              : AppTheme.warningColor.withValues(alpha: 0.40),
          width: sendable ? 1.2 : 1.4,
        ),
        boxShadow: SasUi.cardShadow(),
      ),
      child: Row(
        children: [
          Icon(
            sendable ? Icons.chat_rounded : Icons.phone_disabled_rounded,
            size: 22.sp,
            color: sendable
                ? const Color(0xFF25D366)
                : AppTheme.warningColor,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A2E)),
                      ),
                    ),
                    if (daysLeft != null)
                      SasStatusBadge(
                        label: daysLeft <= 0
                            ? 'منتهٍ'
                            : 'باقٍ $daysLeft يوم',
                        color: daysLeft <= 0
                            ? AppTheme.errorColor
                            : (daysLeft <= 2
                                ? AppTheme.warningColor
                                : AppTheme.primaryColor),
                      ),
                  ],
                ),
                SizedBox(height: 3.h),
                Text(
                  [
                    if (c.username.isNotEmpty) c.username,
                    if (c.profile != null && c.profile!.isNotEmpty)
                      'باقة: ${c.profile}',
                    if (c.expiry != null && c.expiry!.isNotEmpty)
                      'انتهاء: ${(c.expiry ?? '').split(' ').first}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 11.5.sp, color: Colors.grey[600]),
                ),
                SizedBox(height: 2.h),
                Text(
                  sendable
                      ? 'الهاتف: ${c.phone}'
                      : (c.hasPhone
                          ? 'رقم غير صالح لواتساب: ${c.phone}'
                          : 'لا يوجد رقم هاتف — لن يصله التذكير'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: sendable
                        ? Colors.grey[700]
                        : AppTheme.warningColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// يحسب الأيام المتبقّية حتى تاريخ الانتهاء (قد يكون سالباً إن انتهى).
  int? _daysUntil(String? expiry) {
    if (expiry == null || expiry.trim().isEmpty) return null;
    final datePart = expiry.split(' ').first;
    final dt = DateTime.tryParse(datePart);
    if (dt == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    return target.difference(today).inDays;
  }

  // ─────────────────────────── شريط الإرسال السفلي ───────────────────────────

  Widget _bottomBar() {
    if (_candidates.isEmpty) return const SizedBox.shrink();
    final sendable = _sendableCount;
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
            Expanded(
              child: Text(
                sendable > 0
                    ? 'سيُرسَل التذكير إلى $sendable مشترك عبر واتساب'
                    : 'لا يوجد أرقام صالحة لإرسال التذكير',
                style: GoogleFonts.cairo(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700]),
              ),
            ),
            SizedBox(width: 10.w),
            FilledButton.icon(
              onPressed: sendable == 0 ? null : _sendNow,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                disabledBackgroundColor:
                    Colors.grey.withValues(alpha: 0.30),
                padding:
                    EdgeInsets.symmetric(horizontal: 20.w, vertical: 13.h),
              ),
              icon: Icon(Icons.send_rounded, size: 18.sp),
              label: Text('إرسال التذكير الآن',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}
