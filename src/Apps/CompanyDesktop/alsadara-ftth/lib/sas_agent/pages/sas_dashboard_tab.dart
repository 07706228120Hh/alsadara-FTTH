import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_report.dart';
import '../models/sas_subscriber_summary.dart';
import '../models/sas_ticket.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_format.dart';
import '../widgets/sas_metric_card.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_ring_metric.dart';
import '../widgets/sas_report_widgets.dart';
import '../widgets/sas_state_views.dart';

/// تبويب «لوحة» — لوحة الوكيل الغنيّة للحساب المحدد بثيم منصّة الصدارة.
///
/// ## مصدر الأرقام الأساسية (موثوق)
/// بطاقات «ملخّص المشتركين» و«قرب الانتهاء» و«توزيع الحالات» تُملأ من
/// [SasAgentApiService.getSubscribersSummary] — **الملخّص المحلّي الموثوق**
/// (قاعدة الصدارة بعد المزامنة) لا من لوحة الساس الحيّة. لذا لا تُعرَض «-»
/// أبداً: رقم فعلي أو 0.
///
/// ## المصادر الثانوية (كلٌّ معزول — فشله لا يُسقط الباقي)
/// - [SasAgentApiService.getReconciliation] حكم المقاطعة (البلنك).
/// - [SasAgentApiService.getTicketsStats] إحصاءات التذاكر.
/// - [SasAgentApiService.getFinance] المالية (رصيد/دخل/ديون) بتنسيق M/K.
/// - [SasAgentApiService.listReports] آخر تصريح للوكيل.
///
/// ## المزامنة والتحديث
/// - **المزامنة الكاملة** [SasAgentApiService.syncAccount] ثقيلة (تضرب SAS4):
///   تُنفَّذ فقط (أ) عند أول تحميل إن لم توجد بيانات محلية (`last_sync == null`)،
///   (ب) بزر «مزامنة» اليدوي. **لا تُستدعى في المؤقّت إطلاقاً.**
/// - **تحديث تلقائي خفيف** كل 45 ثانية: ملخّص + مقاطعة + تذاكر + مالية فقط
///   (بلا مزامنة). يُوقَف في [dispose] وعند تبديل الحساب، ولا يُحدّث بعد
///   `!mounted`. يُعرَض سطر «آخر تحديث تلقائي» ومؤشّر خفيف بلا وميض للشاشة.
class SasDashboardTab extends StatefulWidget {
  final SasAccount account;

  /// ينتقل لتبويب «مشتركون» مفلترًا على نافذة الانتهاء المطلوبة
  /// (overdue/today/soon3/soon7). يُمرَّر من شل الوحدة.
  final void Function(String expiring)? onOpenExpiring;

  const SasDashboardTab({
    super.key,
    required this.account,
    this.onOpenExpiring,
  });

  @override
  State<SasDashboardTab> createState() => _SasDashboardTabState();
}

class _SasDashboardTabState extends State<SasDashboardTab> {
  final _api = SasAgentApiService.instance;

  /// فترة التحديث التلقائي الخفيف.
  static const _autoRefreshEvery = Duration(seconds: 45);

  // المصدر الأساسي الموثوق: الملخّص المحلّي (إن فشل أوّل تحميل تُعرَض حالة خطأ).
  SasSubscriberSummary? _summary;
  bool _loading = true;
  String? _error;

  // مصادر ثانوية (كل منها معزول — فشله لا يكسر اللوحة).
  Map<String, dynamic>? _finance;
  SasReconciliation? _recon;
  SasAgentReport? _lastReport;
  SasTicketStats? _tickets;

  bool _syncing = false; // مزامنة كاملة يدوية جارية
  bool _autoRefreshing = false; // تحديث خفيف دوري جارٍ (مؤشّر لطيف)
  DateTime? _lastAutoRefresh; // وقت آخر تحديث تلقائي ناجح
  DateTime? _lastSyncAt; // وقت آخر مزامنة كاملة (من الملخّص/الحساب)

  Timer? _timer;

  /// اشتراك ناقل التحديث المشترك — يعيد تحميلاً خفيفاً عند أي عملية/مزامنة.
  StreamSubscription<SasRefreshEvent>? _busSub;

  @override
  void initState() {
    super.initState();
    _load();
    _busSub = SasRefreshBus.instance.stream.listen(_onBusEvent);
  }

  /// عند إشعار الناقل الخاص بحساب هذه اللوحة: تحديث خفيف موضعي (بلا مزامنة ثقيلة
  /// ولا وميض) — المزامنة تمّت عند مصدر الحدث (العملية/الشل/الزر).
  void _onBusEvent(SasRefreshEvent e) {
    if (!mounted) return;
    if (!e.matches(widget.account.id)) return;
    _refreshLight();
  }

  @override
  void didUpdateWidget(covariant SasDashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // عند تبديل الحساب: أوقِف المؤقّت، صفّر الحالة، وأعِد التحميل من الصفر.
    if (oldWidget.account.id != widget.account.id) {
      _stopTimer();
      _summary = null;
      _finance = null;
      _recon = null;
      _lastReport = null;
      _tickets = null;
      _lastAutoRefresh = null;
      _lastSyncAt = null;
      _load();
    }
  }

  @override
  void dispose() {
    _busSub?.cancel();
    _stopTimer();
    super.dispose();
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  // ─────────────────────────── التحميل والتحديث ───────────────────────────

  /// المؤقّت الدوري الخفيف (يُعاد ضبطه بأمان — يلغي أيّ مؤقّت سابق أولاً).
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_autoRefreshEvery, (_) => _refreshLight());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// تحميل أوّلي كامل:
  /// - يجلب الملخّص المحلّي الموثوق (المصدر الأساسي).
  /// - إن لم توجد بيانات محلية (`last_sync == null`) يُشغّل مزامنة كاملة مرّة
  ///   واحدة ثم يعيد قراءة الملخّص.
  /// - يجلب المصادر الثانوية بالتوازي.
  /// - يُشغّل المؤقّت الدوري الخفيف في النهاية.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final id = widget.account.id;

    // المصدر الأساسي: الملخّص المحلّي الموثوق.
    try {
      var s = await _api.getSubscribersSummary(id);
      // لا بيانات محلية بعد؟ مزامنة كاملة مرّة واحدة (أول تحميل فقط) ثم إعادة قراءة.
      if (s.lastSync == null) {
        try {
          await _api.syncAccount(id);
          if (!mounted) return;
          s = await _api.getSubscribersSummary(id);
        } catch (_) {
          // فشل المزامنة الأولى لا يُسقط اللوحة — نعرض الملخّص كما هو (أصفار).
        }
      }
      if (!mounted) return;
      setState(() {
        _summary = s;
        _lastSyncAt = s.lastSync;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    }

    // المصادر الثانوية بالتوازي — كل نتيجة تُعالَج على حدة بلا إسقاط الباقي.
    // ملاحظة: إحصاءات التذاكر user-scoped (بلا account id) — تُحمَّل معها للعرض.
    await _fetchSecondary(id);

    if (!mounted) return;
    setState(() => _loading = false);

    // شغّل التحديث التلقائي الدوري بعد اكتمال أوّل تحميل.
    _startTimer();
  }

  /// جلب المصادر الثانوية بالتوازي وتحديث الحالة (بلا لمس _loading).
  Future<void> _fetchSecondary(String id) async {
    final results = await Future.wait<Object?>([
      _api.getReconciliation(id).then<Object?>((v) => v).catchError((_) => null),
      _api.getTicketsStats().then<Object?>((v) => v).catchError((_) => null),
      _api.getFinance(id).then<Object?>((v) => v).catchError((_) => null),
      _api.listReports(id).then<Object?>((v) => v).catchError((_) => null),
    ]);
    if (!mounted) return;
    setState(() {
      _recon = results[0] is SasReconciliation
          ? results[0] as SasReconciliation
          : _recon;
      _tickets =
          results[1] is SasTicketStats ? results[1] as SasTicketStats : _tickets;
      final fin = results[2];
      if (fin is Map<String, dynamic>) _finance = fin;
      final reports = results[3];
      if (reports is List<SasAgentReport>) {
        _lastReport = reports.isNotEmpty ? reports.first : null;
      }
    });
  }

  /// تحديث تلقائي **خفيف** (يستدعيه المؤقّت كل 45 ثانية):
  /// الملخّص المحلّي + المقاطعة + التذاكر + المالية فقط. **لا مزامنة.**
  ///
  /// لا يعرض حالة تحميل كاملة ولا يومض الشاشة؛ يُحدّث القيم مكانها بسلاسة مع
  /// مؤشّر صغير في الشريط العلوي.
  Future<void> _refreshLight() async {
    if (!mounted || _autoRefreshing || _syncing) return;
    setState(() => _autoRefreshing = true);
    final id = widget.account.id;
    try {
      // الملخّص الموثوق (بلا مزامنة — قراءة سريعة من قاعدة الصدارة).
      final s = await _api
          .getSubscribersSummary(id)
          .then<SasSubscriberSummary?>((v) => v)
          .catchError((_) => null);
      if (!mounted) return;
      if (s != null) {
        setState(() {
          _summary = s;
          _lastSyncAt = s.lastSync ?? _lastSyncAt;
        });
      }
      // المصادر الثانوية الخفيفة.
      await _fetchSecondary(id);
      if (!mounted) return;
      setState(() => _lastAutoRefresh = DateTime.now());
    } finally {
      if (mounted) setState(() => _autoRefreshing = false);
    }
  }

  /// مزامنة كاملة يدوية (زر «مزامنة») — ثقيلة، تضرب SAS4، تُنفَّذ بطلب المستخدم
  /// فقط. بعدها تُحدَّث القيم من الملخّص المحلّي الموثوق.
  Future<void> _syncManual() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final r = await _api.syncAccount(widget.account.id);
      if (!mounted) return;
      _snack('تمت مزامنة ${r.count} مشترك');
      // أعِد قراءة الملخّص الموثوق + المصادر الثانوية بعد المزامنة.
      final s = await _api
          .getSubscribersSummary(widget.account.id)
          .then<SasSubscriberSummary?>((v) => v)
          .catchError((_) => null);
      if (!mounted) return;
      if (s != null) {
        setState(() {
          _summary = s;
          _lastSyncAt = s.lastSync ?? r.syncedAt ?? _lastSyncAt;
        });
      } else {
        setState(() => _lastSyncAt = r.syncedAt ?? _lastSyncAt);
      }
      await _fetchSecondary(widget.account.id);
      // أبلغ بقية التبويبات المفتوحة لتتحدّث (نبثّ و_syncing لا يزال true فيتخطّى
      // مستمعنا الذاتي إعادةً مكرّرة؛ لوحتنا مُحدَّثة أصلاً أعلاه).
      SasRefreshBus.instance
          .notify(accountId: widget.account.id, reason: 'dashboard-sync-button');
    } catch (e) {
      _snack(_clean(e), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _summary == null) {
      return const SasLoadingView(message: 'جاري جلب اللوحة…');
    }
    if (_error != null && _summary == null) {
      return SasErrorView(message: _error!, onRetry: _load);
    }

    final s = _summary ?? SasSubscriberSummary.empty;

    return LayoutBuilder(
      builder: (context, c) {
        // ── قرار التخطيط المتجاوب ──
        // عريض (سطح المكتب) ⇐ العرض كافٍ لعمودين، وطويل ⇐ الارتفاع كافٍ
        // لعرض كل شيء بلا تمرير. نُقدّر عتبة ارتفاع تكفي للتخطيط المضغوط
        // ذي العمودين؛ دونها نتحوّل لخطة الأمان (تمرير) لمنع أي overflow.
        final wide = c.maxWidth >= 1000;
        final maxH = c.maxHeight;
        // عتبة عملية: التخطيط المضغوط ذو العمودين يحتاج ~560 لوجيكال ارتفاعاً.
        final tallEnough = maxH.isFinite && maxH >= 560;

        // سطح المكتب العريض والطويل: شاشة واحدة تملأ الارتفاع بلا تمرير.
        if (wide && tallEnough) {
          return _singleScreenWide(s, maxH);
        }

        // خطة الأمان: ضيّق أو قصير ⇐ تمرير رأسي (يمنع overflow نهائياً).
        return _scrollableFallback(s, wide);
      },
    );
  }

  // ─────────────────────── تخطيط الشاشة الواحدة (عريض) ───────────────────────

  /// تخطيط سطح المكتب: كل الأقسام في شاشة واحدة تملأ الارتفاع بلا تمرير.
  ///
  /// - أعلى: بانر حساب مضغوط بارتفاع ثابت صغير (سطر واحد).
  /// - وسط ([Expanded]): صفّ عمودين متساويين:
  ///   - يمين: «ملخّص المشتركين» فوق «قرب الانتهاء».
  ///   - يسار: «المالية» + «التصريح والمقاطعة» + «التذاكر» مكدّسة.
  ///
  /// كل الحاويات الداخلية `Expanded`/مرنة فتتوزّع المساحة العمودية بلا فراغ ولا
  /// تجاوز؛ والبطاقات تُلفّ بـ [FittedBox]/تمرير داخلي عند الضيق الشديد.
  Widget _singleScreenWide(SasSubscriberSummary s, double maxH) {
    // البانر المضغوط أقصر كلما ضاق الارتفاع (لإعطاء الأقسام مساحة أكبر).
    return Padding(
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _compactBanner(),
          SizedBox(height: 12.h),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // العمود الأيمن (RTL يضعه أولاً): الملخّص + قرب الانتهاء.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _panel(
                          title: 'ملخّص المشتركين',
                          icon: Icons.insights_rounded,
                          trailingText: '${s.total}',
                          child: _summaryStatsCompact(s),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Expanded(
                        flex: 5,
                        child: _panel(
                          title: 'قرب الانتهاء — التجديد',
                          icon: Icons.event_repeat_rounded,
                          gradient: AppTheme.orangeGradient,
                          trailingText: widget.onOpenExpiring != null
                              ? 'اضغط للتصفية'
                              : null,
                          child: _expiryCardsCompact(s),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                // العمود الأيسر: المالية + التصريح/المقاطعة + التذاكر.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _panel(
                          title: 'المالية',
                          icon: Icons.account_balance_wallet_rounded,
                          gradient: AppTheme.orangeGradient,
                          child: _financeCardsCompact(),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Expanded(
                        flex: 4,
                        child: _panel(
                          title: 'التصريح والمقاطعة',
                          icon: Icons.assignment_turned_in_rounded,
                          child: _reconContentCompact(),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Expanded(
                        flex: 3,
                        child: _panel(
                          title: 'التذاكر',
                          icon: Icons.confirmation_number_rounded,
                          gradient: AppTheme.orangeGradient,
                          child: _ticketsContentCompact(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// لوح موحّد: رأس قسم صغير + محتوى يملأ ما تبقّى (يمنع overflow بتقييد الطفل).
  Widget _panel({
    required String title,
    required IconData icon,
    required Widget child,
    List<Color> gradient = AppTheme.blueGradient,
    String? trailingText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SasSectionHeader(
          title: title,
          icon: icon,
          gradient: gradient,
          trailingText: trailingText,
        ),
        SizedBox(height: 10.h),
        // المحتوى يأخذ المتبقّي؛ ClipRect يحمي من أي فيض بصري لحظي عند التحجيم.
        Expanded(child: ClipRect(child: child)),
      ],
    );
  }

  // ─────────────────────── خطة الأمان: تمرير رأسي ───────────────────────

  /// نسخة قابلة للتمرير (نافذة صغيرة/قصيرة أو موبايل) — تحافظ على كل المعلومات
  /// وتمنع overflow بالسماح بالتمرير عند شحّ الارتفاع.
  Widget _scrollableFallback(SasSubscriberSummary s, bool wide) {
    return RefreshIndicator(
      onRefresh: _refreshLight,
      child: ListView(
        padding: EdgeInsets.all(14.w),
        children: [
          _compactBanner(),
          SizedBox(height: 16.h),
          SasSectionHeader(
            title: 'ملخّص المشتركين',
            icon: Icons.insights_rounded,
            trailingText: '${s.total}',
          ),
          SizedBox(height: 12.h),
          _summaryStats(s),
          SizedBox(height: 20.h),
          SasSectionHeader(
            title: 'قرب الانتهاء — التجديد',
            icon: Icons.event_repeat_rounded,
            gradient: AppTheme.orangeGradient,
            trailingText: widget.onOpenExpiring != null ? 'اضغط للتصفية' : null,
          ),
          SizedBox(height: 12.h),
          _expiryCards(s),
          SizedBox(height: 20.h),
          _financeBlock(),
          SizedBox(height: 20.h),
          _reconBlock(),
          SizedBox(height: 20.h),
          if (wide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _distributionBlock(s)),
                  SizedBox(width: 14.w),
                  Expanded(child: _ticketsBlock()),
                ],
              ),
            )
          else ...[
            _distributionBlock(s),
            SizedBox(height: 20.h),
            _ticketsBlock(),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────── الشريط العلوي ───────────────────────────

  /// بانر حساب **مضغوط** بارتفاع ثابت صغير (سطر واحد): شارة + اسم الحساب + آخر
  /// مزامنة + آخر تحديث تلقائي + زر مزامنة. يُلفّ سطر الحالة بـ [Flexible] +
  /// قطع نصّي فلا يفيض أفقياً مهما ضاق العرض.
  Widget _compactBanner() {
    final syncedAt = _lastSyncAt ?? widget.account.lastSyncAt;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
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
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child:
                Icon(Icons.dashboard_rounded, color: Colors.white, size: 22.sp),
          ),
          SizedBox(width: 12.w),
          // الاسم + سطر الحالة (آخر مزامنة/آخر تحديث) — كلها قابلة للقطع.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3.h),
                Row(
                  children: [
                    Flexible(
                      child: _bannerStatusChip(
                        icon: Icons.sync_rounded,
                        text: syncedAt != null
                            ? 'آخر مزامنة: ${_fmtDateTime(syncedAt)}'
                            : 'لم تُزامَن بعد',
                      ),
                    ),
                    SizedBox(width: 14.w),
                    Flexible(child: _autoRefreshChip()),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          _syncButton(),
        ],
      ),
    );
  }

  /// شريحة حالة صغيرة داخل البانر (أيقونة + نص) — النص قابل للقطع فلا يفيض.
  Widget _bannerStatusChip({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.sp, color: Colors.white.withValues(alpha: 0.75)),
        SizedBox(width: 5.w),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 11.sp,
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// شريحة «آخر تحديث تلقائي: HH:mm:ss» مع مؤشّر خفيف أثناء التحديث (بلا وميض).
  Widget _autoRefreshChip() {
    final t = _lastAutoRefresh;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 13.sp,
          height: 13.sp,
          child: _autoRefreshing
              ? CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: Colors.white.withValues(alpha: 0.85),
                )
              : Icon(Icons.autorenew_rounded,
                  size: 13.sp, color: Colors.white.withValues(alpha: 0.75)),
        ),
        SizedBox(width: 5.w),
        Flexible(
          child: Text(
            t != null
                ? 'آخر تحديث تلقائي: ${_fmtTime(t)}'
                : 'التحديث التلقائي مُفعَّل',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 11.sp,
              color: Colors.white.withValues(alpha: 0.82),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _syncButton() {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(SasUi.radiusPill.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radiusPill.r),
        onTap: _syncing ? null : _syncManual,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _syncing
                  ? SizedBox(
                      width: 15.w,
                      height: 15.w,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(Icons.sync_rounded, size: 16.sp, color: Colors.white),
              SizedBox(width: 6.w),
              Text(
                'مزامنة',
                style: GoogleFonts.cairo(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── ملخّص المشتركين ───────────────────────────

  /// بطاقات الملخّص من [SasSubscriberSummary] الموثوق — أرقام فعلية أو 0
  /// (لا «-» أبداً). عدّادات فاخرة بعرض ثابت مريح في وضع التمرير.
  Widget _summaryStats(SasSubscriberSummary s) {
    final cells = <_Metric>[
      _Metric('الإجمالي', s.total, AppTheme.primaryColor, Icons.groups_rounded),
      _Metric('نشط', s.active, AppTheme.successColor,
          Icons.check_circle_rounded),
      _Metric('منتهٍ', s.expired, AppTheme.warningColor,
          Icons.timer_off_rounded),
      _Metric('متصل الآن', s.online, AppTheme.infoColor, Icons.wifi_rounded),
    ];
    return _metricWrap([
      for (final m in cells)
        SasMetricCard(
          value: m.value,
          label: m.label,
          color: m.color,
          icon: m.icon,
        ),
    ]);
  }

  /// يلفّ بطاقات العدّاد الفاخرة في وضع التمرير بعرض ثابت مريح (بلا overflow:
  /// [Wrap] ينقل البطاقات لأسطر جديدة عند ضيق العرض).
  Widget _metricWrap(List<Widget> cards) {
    return Wrap(
      spacing: 12.w,
      runSpacing: 12.h,
      children: [
        for (final c in cards) SizedBox(width: 168.w, child: c),
      ],
    );
  }

  // ─────────────────────────── قرب الانتهاء ───────────────────────────

  /// بطاقات عدّادات الانتهاء القابلة للنقر (منتهٍ/اليوم/٣ أيام/أسبوع).
  /// المصدر: عدّادات الملخّص المحلّي الموثوق (`summary.expiry`).
  Widget _expiryCards(SasSubscriberSummary s) {
    final e = s.expiry;
    final defs = <_ExpiryDef>[
      _ExpiryDef('overdue', 'منتهٍ', e.overdue, AppTheme.errorColor,
          Icons.event_busy_rounded),
      _ExpiryDef('today', 'ينتهي اليوم', e.today, AppTheme.warningColor,
          Icons.today_rounded),
      _ExpiryDef('soon3', 'خلال ٣ أيام', e.soon3, const Color(0xFFF57C00),
          Icons.hourglass_bottom_rounded),
      _ExpiryDef('soon7', 'خلال أسبوع', e.soon7, AppTheme.infoColor,
          Icons.date_range_rounded),
    ];

    final enabled = widget.onOpenExpiring != null;
    return LayoutBuilder(
      builder: (context, c) {
        // شبكة متجاوبة: 4 أعمدة على العريض، عمودان على الضيّق.
        final cols = c.maxWidth >= 720 ? 4 : 2;
        final spacing = 12.w;
        final itemW = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: 12.h,
          children: [
            for (final def in defs)
              SizedBox(
                width: itemW,
                child: SasMetricCard(
                  value: def.count,
                  label: def.label,
                  color: def.color,
                  icon: def.icon,
                  // في وضع التمرير الأوسع نُظهرها عموديّة (رقم بارز أعلى التسمية).
                  horizontal: false,
                  onTap:
                      enabled ? () => widget.onOpenExpiring!(def.key) : null,
                ),
              ),
          ],
        );
      },
    );
  }

  // ─────────────────────────── المالية ───────────────────────────

  Widget _financeBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SasSectionHeader(
          title: 'المالية',
          icon: Icons.account_balance_wallet_rounded,
          gradient: AppTheme.orangeGradient,
        ),
        SizedBox(height: 12.h),
        _financeCards(),
      ],
    );
  }

  /// بطاقات KPI مالية بتنسيق M/K — نبرز الرصيد/الدخل/الديون إن توفّرت،
  /// وإلا نعرض أهمّ الحقول العددية المتاحة (حتى 4).
  Widget _financeCards() {
    final f = _finance;
    if (f == null || f.isEmpty) {
      return _emptyBox('لا يتوفّر ملخّص مالي');
    }
    final numeric = f.entries.where((e) => e.value is num).toList();
    if (numeric.isEmpty) {
      return _emptyBox('لا توجد تفاصيل مالية قابلة للعرض');
    }

    // ترتيب مُفضَّل: رصيد ثم دخل ثم ديون، ثم البقية.
    int rank(String k) {
      final key = k.toLowerCase();
      if (key.contains('balance') || key.contains('credit')) return 0;
      if (key.contains('income') ||
          key.contains('revenue') ||
          key.contains('profit')) return 1;
      if (key.contains('debt') || key.contains('expense')) return 2;
      return 3;
    }

    numeric.sort((a, b) => rank(a.key).compareTo(rank(b.key)));
    final show = numeric.take(4).toList();

    return _metricWrap([
      for (final e in show)
        SasMetricCard(
          value: e.value as num,
          label: _financeLabel(e.key),
          color: _financeColor(e.key),
          icon: _financeIcon(e.key),
          horizontal: false,
          formatter: (v) => sasMoneyShort(e.key, v),
        ),
    ]);
  }

  // ─────────────────────────── التصريح / المقاطعة ───────────────────────────

  Widget _reconBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SasSectionHeader(
          title: 'التصريح والمقاطعة',
          icon: Icons.assignment_turned_in_rounded,
        ),
        SizedBox(height: 12.h),
        _lastReportStrip(),
        SizedBox(height: 12.h),
        if (_recon != null)
          SasReconciliationCard(recon: _recon!)
        else
          _emptyBox('لا تتوفّر بيانات المقاطعة'),
      ],
    );
  }

  /// شريط «آخر تصريح» أعلى بطاقة المقاطعة.
  Widget _lastReportStrip() {
    final r = _lastReport;
    final hasReport = r != null;
    final color =
        hasReport ? AppTheme.primaryColor : AppTheme.warningColor;
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(borderColor: color.withValues(alpha: 0.22)),
      child: Row(
        children: [
          Container(
            width: 38.w,
            height: 38.w,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11.r),
            ),
            child: Icon(
              hasReport ? Icons.fact_check_rounded : Icons.pending_actions_rounded,
              color: color,
              size: 20.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'آخر تصريح',
                  style: GoogleFonts.cairo(
                    fontSize: 11.5.sp,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  hasReport
                      ? '${r.declaredTotal} مشترك (${r.declaredActive} نشط)'
                      : 'لم تُصرّح بعد — من تبويب «تصريح/بلنك»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                if (hasReport && r.createdAt != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    _fmtDateTime(r.createdAt!),
                    style: GoogleFonts.cairo(
                      fontSize: 10.5.sp,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── توزيع الحالات (دونات) ───────────────────────────

  Widget _distributionBlock(SasSubscriberSummary s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SasSectionHeader(
          title: 'توزيع الحالات',
          icon: Icons.donut_large_rounded,
          gradient: AppTheme.greenGradient,
        ),
        SizedBox(height: 12.h),
        _distributionCard(s),
      ],
    );
  }

  Widget _distributionCard(SasSubscriberSummary s) {
    final active = s.active;
    final expired = s.expired;
    // «أخرى» = الإجمالي ناقص (نشط + منتهٍ) إن كان موجبًا.
    final total = s.total > 0 ? s.total : (active + expired);
    final other = math.max(0, total - active - expired);
    final sum = active + expired + other;

    if (sum <= 0) {
      return _emptyBox('لا توجد بيانات كافية لرسم التوزيع');
    }

    final segments = <_Seg>[
      _Seg('نشط', active, AppTheme.successColor),
      _Seg('منتهٍ', expired, AppTheme.warningColor),
      if (other > 0) _Seg('أخرى', other, Colors.blueGrey),
    ];

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: SasUi.card(),
      child: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 520;
          final chart = SizedBox(
            width: 150.w,
            height: 150.w,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 44.r,
                    startDegreeOffset: -90,
                    sections: [
                      for (final seg in segments)
                        PieChartSectionData(
                          value: seg.value.toDouble(),
                          color: seg.color,
                          radius: 26.r,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${((active / sum) * 100).round()}%',
                      style: GoogleFonts.cairo(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.successColor,
                      ),
                    ),
                    Text(
                      'نشط',
                      style: GoogleFonts.cairo(
                        fontSize: 10.5.sp,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final seg in segments) _legendRow(seg, sum),
            ],
          );

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                chart,
                SizedBox(width: 22.w),
                Expanded(child: legend),
              ],
            );
          }
          return Column(
            children: [
              chart,
              SizedBox(height: 16.h),
              legend,
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────── التذاكر ───────────────────────────

  Widget _ticketsBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SasSectionHeader(
          title: 'التذاكر',
          icon: Icons.confirmation_number_rounded,
          gradient: AppTheme.orangeGradient,
        ),
        SizedBox(height: 12.h),
        _ticketsCard(),
      ],
    );
  }

  Widget _ticketsCard() {
    final t = _tickets;
    if (t == null) {
      return _emptyBox('لا تتوفّر إحصاءات التذاكر');
    }
    final openColor =
        t.open > 0 ? AppTheme.errorColor : AppTheme.successColor;

    Widget box(IconData icon, Color color, int n, String label) => Expanded(
          child: Container(
            padding: EdgeInsets.all(14.w),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(SasUi.radius.r),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22.sp),
                SizedBox(height: 12.h),
                Text(
                  '$n',
                  style: GoogleFonts.cairo(
                    fontSize: 26.sp,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5.sp,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              box(Icons.mark_email_unread_rounded, openColor, t.open,
                  'مفتوحة تحتاج معالجة'),
              SizedBox(width: 10.w),
              box(Icons.check_circle_rounded, AppTheme.successColor,
                  t.resolved, 'محلولة'),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Icon(Icons.summarize_rounded,
                  size: 15.sp, color: Colors.grey[500]),
              SizedBox(width: 6.w),
              Text(
                'إجمالي التذاكر: ${t.total}'
                '${t.inProgress > 0 ? ' · قيد المعالجة: ${t.inProgress}' : ''}',
                style: GoogleFonts.cairo(
                  fontSize: 11.5.sp,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendRow(_Seg s, int sum) {
    final pct = sum == 0 ? 0.0 : (s.value / sum) * 100;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        children: [
          Container(
            width: 12.w,
            height: 12.w,
            decoration: BoxDecoration(
              color: s.color,
              borderRadius: BorderRadius.circular(4.r),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              s.label,
              style: GoogleFonts.cairo(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
          ),
          Text(
            '${s.value}',
            style: GoogleFonts.cairo(
              fontSize: 13.sp,
              fontWeight: FontWeight.w900,
              color: s.color,
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            '(${pct.toStringAsFixed(0)}%)',
            style: GoogleFonts.cairo(
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── مساعدات ───────────────────────────

  Widget _emptyBox(String message) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 22.h),
      decoration: SasUi.card(),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded,
              size: 34.sp, color: AppTheme.primaryColor.withValues(alpha: 0.4)),
          SizedBox(height: 8.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 12.5.sp,
              color: Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime dt) =>
      DateFormat('yyyy/MM/dd HH:mm').format(dt.toLocal());

  String _fmtTime(DateTime dt) => DateFormat('HH:mm:ss').format(dt.toLocal());

  // تسميات/أيقونات/ألوان المالية — منسجمة مع تبويب «نظام الساس».
  String _financeLabel(String key) {
    const labels = <String, String>{
      'total_income': 'إجمالي الدخل',
      'income': 'الدخل',
      'revenue': 'الإيرادات',
      'total_debt': 'إجمالي الديون',
      'debt': 'الديون',
      'balance': 'الرصيد الإجمالي',
      'total_balance': 'إجمالي الأرصدة',
      'managers_balance': 'أرصدة الوكلاء',
      'agents_balance': 'أرصدة الوكلاء',
      'credit': 'الائتمان',
      'expenses': 'المصاريف',
      'profit': 'الأرباح',
      'registrations': 'التسجيلات',
      'registration': 'التسجيلات',
      'activations': 'التفعيلات',
      'activation': 'التفعيلات',
      'reward_points': 'نقاط المكافآت',
      'reward points': 'نقاط المكافآت',
      'rewardpoints': 'نقاط المكافآت',
      'points': 'النقاط',
      'cards': 'الكروت',
      'vouchers': 'القسائم',
    };
    final k = key.toLowerCase();
    if (labels.containsKey(k)) return labels[k]!;
    if (k.contains('balance')) return 'الرصيد';
    if (k.contains('income') || k.contains('revenue')) return 'الدخل';
    if (k.contains('debt')) return 'الديون';
    if (k.contains('credit')) return 'الائتمان';
    if (k.contains('registration')) return 'التسجيلات';
    if (k.contains('activation')) return 'التفعيلات';
    if (k.contains('reward') || k.contains('point')) return 'نقاط المكافآت';
    return key.replaceAll('_', ' ');
  }

  IconData _financeIcon(String key) {
    final k = key.toLowerCase();
    if (k.contains('income') || k.contains('revenue') || k.contains('profit')) {
      return Icons.trending_up_rounded;
    }
    if (k.contains('debt') || k.contains('expense')) {
      return Icons.trending_down_rounded;
    }
    if (k.contains('balance') || k.contains('credit')) {
      return Icons.account_balance_wallet_rounded;
    }
    return Icons.payments_rounded;
  }

  Color _financeColor(String key) {
    final k = key.toLowerCase();
    if (k.contains('income') || k.contains('revenue') || k.contains('profit')) {
      return AppTheme.successColor;
    }
    if (k.contains('debt') || k.contains('expense')) {
      return AppTheme.errorColor;
    }
    if (k.contains('balance') || k.contains('credit')) {
      return const Color(0xFF009688);
    }
    return AppTheme.primaryColor;
  }

  // ════════════════════ محتويات مضغوطة لتخطيط الشاشة الواحدة ════════════════════
  // بطاقات صغيرة مبنيّة بشبكة تملأ الارتفاع المتاح ([LayoutBuilder] لكل لوح)،
  // بأحجام خط/حشوة تتناسب مع ارتفاع الخلية عبر [FittedBox] فلا يحدث overflow
  // مهما ضاق اللوح. تحافظ على نفس البيانات والقابلية للنقر.

  /// ملخّص المشتركين — شبكة 2×2 تملأ اللوح (الإجمالي/نشط/منتهٍ/متصل)
  /// بعدّادات **حلقية دائرية فاخرة** ([SasRingMetric]): قوس متدرّج + توهّج +
  /// رقم count-up متزامن. نسبة كلّ حلقة من الإجمالي (`max = s.total`)، وحلقة
  /// «الإجمالي» ممتلئة 100% كمرجع.
  Widget _summaryStatsCompact(SasSubscriberSummary s) {
    // الإجمالي مرجع (بلا max ⇒ ممتلئ)؛ البقية نسبتها من الإجمالي.
    final total = s.total;
    final cells = <_RingDef>[
      _RingDef('الإجمالي', s.total, null,
          AppTheme.primaryColor, Icons.groups_rounded),
      _RingDef('نشط', s.active, total,
          AppTheme.successColor, Icons.check_circle_rounded),
      _RingDef('منتهٍ', s.expired, total,
          AppTheme.warningColor, Icons.timer_off_rounded),
      _RingDef('متصل الآن', s.online, total,
          AppTheme.infoColor, Icons.wifi_rounded),
    ];
    return _miniGrid(
      count: cells.length,
      builder: (i) => SasRingMetric(
        value: cells[i].value,
        max: cells[i].max,
        showPercent: cells[i].max != null,
        label: cells[i].label,
        color: cells[i].color,
        icon: cells[i].icon,
      ),
    );
  }

  /// قرب الانتهاء — شبكة 2×2 قابلة للنقر (منتهٍ/اليوم/٣ أيام/أسبوع)
  /// بعدّادات **حلقية دائرية فاخرة** ([SasRingMetric]): كلّ حلقة تُظهر حجم
  /// شريحتها نسبةً للإجمالي (`max = s.total`)، مع الحفاظ على `onTap` للتصفية.
  Widget _expiryCardsCompact(SasSubscriberSummary s) {
    final e = s.expiry;
    final total = s.total;
    final defs = <_ExpiryDef>[
      _ExpiryDef('overdue', 'منتهٍ', e.overdue, AppTheme.errorColor,
          Icons.event_busy_rounded),
      _ExpiryDef('today', 'ينتهي اليوم', e.today, AppTheme.warningColor,
          Icons.today_rounded),
      _ExpiryDef('soon3', 'خلال ٣ أيام', e.soon3, const Color(0xFFF57C00),
          Icons.hourglass_bottom_rounded),
      _ExpiryDef('soon7', 'خلال أسبوع', e.soon7, AppTheme.infoColor,
          Icons.date_range_rounded),
    ];
    final enabled = widget.onOpenExpiring != null;
    return _miniGrid(
      count: defs.length,
      builder: (i) => SasRingMetric(
        value: defs[i].count,
        max: total > 0 ? total : null,
        showPercent: total > 0,
        label: defs[i].label,
        color: defs[i].color,
        icon: defs[i].icon,
        onTap: enabled ? () => widget.onOpenExpiring!(defs[i].key) : null,
      ),
    );
  }

  /// المالية — شبكة 2×2 (حتى 4 حقول) بعدّادات فاخرة، أو حالة فراغ.
  /// count-up يحرّك الرقم الخام ويعرضه بتنسيق M/K عبر [sasMoneyShort].
  Widget _financeCardsCompact() {
    final f = _finance;
    if (f == null || f.isEmpty) {
      return _emptyBox('لا يتوفّر ملخّص مالي');
    }
    final numeric = f.entries.where((e) => e.value is num).toList();
    if (numeric.isEmpty) {
      return _emptyBox('لا توجد تفاصيل مالية قابلة للعرض');
    }
    int rank(String k) {
      final key = k.toLowerCase();
      if (key.contains('balance') || key.contains('credit')) return 0;
      if (key.contains('income') ||
          key.contains('revenue') ||
          key.contains('profit')) return 1;
      if (key.contains('debt') || key.contains('expense')) return 2;
      return 3;
    }

    numeric.sort((a, b) => rank(a.key).compareTo(rank(b.key)));
    final show = numeric.take(4).toList();
    return _miniGrid(
      count: show.length,
      // عمودان دائماً على اللوح الأيسر الضيّق نسبياً.
      forceCols: show.length <= 2 ? show.length : 2,
      builder: (i) {
        final key = show[i].key;
        final raw = (show[i].value as num);
        return SasMetricCard(
          value: raw,
          label: _financeLabel(key),
          color: _financeColor(key),
          icon: _financeIcon(key),
          // حرّك الرقم الخام واعرضه بتنسيق M/K المتوافق مع بقية اللوحة.
          formatter: (v) => sasMoneyShort(key, v),
        );
      },
    );
  }

  /// التصريح والمقاطعة — «آخر تصريح» مصغّر + حكم المقاطعة (بتمرير داخلي آمن).
  Widget _reconContentCompact() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _lastReportStrip(),
          SizedBox(height: 10.h),
          if (_recon != null)
            SasReconciliationCard(recon: _recon!)
          else
            _emptyBox('لا تتوفّر بيانات المقاطعة'),
        ],
      ),
    );
  }

  /// التذاكر — صندوقان (مفتوحة/محلولة) + سطر إجمالي، يملأ اللوح بلا overflow.
  Widget _ticketsContentCompact() {
    final t = _tickets;
    if (t == null) {
      return _emptyBox('لا تتوفّر إحصاءات التذاكر');
    }
    final openColor = t.open > 0 ? AppTheme.errorColor : AppTheme.successColor;

    Widget box(IconData icon, Color color, int n, String label) => Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(SasUi.radius.r),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 20.sp),
                  SizedBox(height: 6.h),
                  Text(
                    '$n',
                    style: GoogleFonts.cairo(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.05,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 11.sp,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              box(Icons.mark_email_unread_rounded, openColor, t.open,
                  'مفتوحة'),
              SizedBox(width: 10.w),
              box(Icons.check_circle_rounded, AppTheme.successColor, t.resolved,
                  'محلولة'),
            ],
          ),
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            Icon(Icons.summarize_rounded, size: 14.sp, color: Colors.grey[500]),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(
                'إجمالي: ${t.total}'
                '${t.inProgress > 0 ? ' · قيد المعالجة: ${t.inProgress}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 11.sp,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────── بنية الشبكة المضغوطة + بطاقاتها الصغيرة ───────────────

  /// شبكة تملأ الارتفاع/العرض المتاحين بلا تمرير: تُقسّم اللوح إلى صفوف/أعمدة
  /// [Expanded] فتتوزّع خلاياها بالتساوي على المساحة (لا [GridView] مُمرِّر).
  /// [forceCols] لتثبيت عدد الأعمدة (وإلا يُختار حسب العرض).
  Widget _miniGrid({
    required int count,
    required Widget Function(int index) builder,
    int? forceCols,
  }) {
    if (count == 0) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final cols = forceCols ?? (c.maxWidth >= 360 ? 2 : 1);
        final rows = (count / cols).ceil();
        const gap = 10.0;
        return Column(
          children: [
            for (var rIdx = 0; rIdx < rows; rIdx++) ...[
              if (rIdx > 0) SizedBox(height: gap.h),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var cIdx = 0; cIdx < cols; cIdx++) ...[
                      if (cIdx > 0) SizedBox(width: gap.w),
                      Expanded(
                        child: rIdx * cols + cIdx < count
                            ? builder(rIdx * cols + cIdx)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

}

/// تعريف بطاقة انتهاء (مفتاح expiring + تسمية + عدد + لون + أيقونة).
class _ExpiryDef {
  final String key;
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const _ExpiryDef(this.key, this.label, this.count, this.color, this.icon);
}

/// شريحة توزيع (تسمية + قيمة + لون) لمخطط الدونات.
class _Seg {
  final String label;
  final int value;
  final Color color;
  const _Seg(this.label, this.value, this.color);
}

/// بيانات عدّاد فاخر (تسمية + قيمة عددية + لون + أيقونة) لبطاقات [SasMetricCard].
class _Metric {
  final String label;
  final num value;
  final Color color;
  final IconData icon;
  const _Metric(this.label, this.value, this.color, this.icon);
}

/// بيانات عدّاد حلقي (تسمية + قيمة + max اختياري + لون + أيقونة) لـ [SasRingMetric].
/// [max] معدوم/غياب ⇒ حلقة مرجعية ممتلئة؛ موجب ⇒ الامتلاء = value/max.
class _RingDef {
  final String label;
  final num value;
  final num? max;
  final Color color;
  final IconData icon;
  const _RingDef(this.label, this.value, this.max, this.color, this.icon);
}
