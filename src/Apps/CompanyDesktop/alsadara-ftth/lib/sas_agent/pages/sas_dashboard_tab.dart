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
import '../widgets/sas_metrics.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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

    return RefreshIndicator(
      onRefresh: _refreshLight,
      child: LayoutBuilder(
        builder: (context, c) {
          // متجاوب سطح المكتب: عمودان للبطاقتين الكبيرتين على الشاشات العريضة.
          final wide = c.maxWidth >= 760;
          return ListView(
            padding: EdgeInsets.all(14.w),
            children: [
              // 0) بانر الحساب + آخر مزامنة/زر المزامنة + آخر تحديث تلقائي.
              _accountBanner(),
              SizedBox(height: 16.h),

              // 1) ملخّص المشتركين (من الملخّص المحلّي الموثوق).
              SasSectionHeader(
                title: 'ملخّص المشتركين',
                icon: Icons.insights_rounded,
                trailingText: '${s.total}',
              ),
              SizedBox(height: 12.h),
              _summaryStats(s),

              SizedBox(height: 20.h),

              // 2) قرب الانتهاء — التجديد (قابلة للنقر → تبويب مشتركون مفلتر).
              SasSectionHeader(
                title: 'قرب الانتهاء — التجديد',
                icon: Icons.event_repeat_rounded,
                gradient: AppTheme.orangeGradient,
                trailingText:
                    widget.onOpenExpiring != null ? 'اضغط للتصفية' : null,
              ),
              SizedBox(height: 12.h),
              _expiryCards(s),

              SizedBox(height: 20.h),

              // 3) المالية.
              _financeBlock(),

              SizedBox(height: 20.h),

              // 4) التصريح والمقاطعة.
              _reconBlock(),

              SizedBox(height: 20.h),

              // 5 + 6) توزيع الحالات (دونات) + التذاكر (عمودان على العريض).
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
          );
        },
      ),
    );
  }

  // ─────────────────────────── الشريط العلوي ───────────────────────────

  /// شريط علوي متدرّج: تعريف الحساب + زر مزامنة + آخر مزامنة + آخر تحديث تلقائي.
  Widget _accountBanner() {
    final syncedAt = _lastSyncAt ?? widget.account.lastSyncAt;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46.w,
                height: 46.w,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.30)),
                ),
                child: Icon(Icons.dashboard_rounded,
                    color: Colors.white, size: 24.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.account.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'لوحة معلومات الحساب',
                      style: GoogleFonts.cairo(
                        fontSize: 11.5.sp,
                        color: Colors.white.withValues(alpha: 0.80),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              _syncButton(),
            ],
          ),
          SizedBox(height: 12.h),
          // سطر الحالة: آخر مزامنة (يمين) + آخر تحديث تلقائي/مؤشّر خفيف (يسار).
          Wrap(
            spacing: 14.w,
            runSpacing: 6.h,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _bannerStatusChip(
                icon: Icons.sync_rounded,
                text: syncedAt != null
                    ? 'آخر مزامنة: ${_fmtDateTime(syncedAt)}'
                    : 'لم تُزامَن بعد',
              ),
              _autoRefreshChip(),
            ],
          ),
        ],
      ),
    );
  }

  /// شريحة حالة صغيرة داخل البانر (أيقونة + نص).
  Widget _bannerStatusChip({required IconData icon, required String text}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.sp, color: Colors.white.withValues(alpha: 0.75)),
        SizedBox(width: 5.w),
        Text(
          text,
          style: GoogleFonts.cairo(
            fontSize: 11.sp,
            color: Colors.white.withValues(alpha: 0.82),
            fontWeight: FontWeight.w600,
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
        Text(
          t != null
              ? 'آخر تحديث تلقائي: ${_fmtTime(t)}'
              : 'التحديث التلقائي مُفعَّل',
          style: GoogleFonts.cairo(
            fontSize: 11.sp,
            color: Colors.white.withValues(alpha: 0.82),
            fontWeight: FontWeight.w600,
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
  /// (لا «-» أبداً).
  Widget _summaryStats(SasSubscriberSummary s) {
    return Wrap(
      spacing: 10.w,
      runSpacing: 10.h,
      children: [
        SasStatCard(
          label: 'الإجمالي',
          value: '${s.total}',
          color: AppTheme.primaryColor,
          icon: Icons.groups_rounded,
        ),
        SasStatCard(
          label: 'نشط',
          value: '${s.active}',
          color: AppTheme.successColor,
          icon: Icons.check_circle_rounded,
        ),
        SasStatCard(
          label: 'منتهٍ',
          value: '${s.expired}',
          color: AppTheme.warningColor,
          icon: Icons.timer_off_rounded,
        ),
        SasStatCard(
          label: 'متصل الآن',
          value: '${s.online}',
          color: AppTheme.infoColor,
          icon: Icons.wifi_rounded,
        ),
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

    return LayoutBuilder(
      builder: (context, c) {
        // شبكة متجاوبة: 4 أعمدة على العريض، عمودان على الضيّق.
        final cols = c.maxWidth >= 720 ? 4 : 2;
        final spacing = 10.w;
        final itemW = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: 10.h,
          children: [
            for (final def in defs)
              SizedBox(width: itemW, child: _expiryCard(def)),
          ],
        );
      },
    );
  }

  Widget _expiryCard(_ExpiryDef def) {
    final enabled = widget.onOpenExpiring != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        onTap: enabled ? () => widget.onOpenExpiring!(def.key) : null,
        child: Container(
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                def.color.withValues(alpha: 0.12),
                def.color.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(SasUi.radius.r),
            border:
                Border.all(color: def.color.withValues(alpha: 0.28), width: 1.3),
            boxShadow: SasUi.cardShadow(def.color),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38.w,
                    height: 38.w,
                    decoration: BoxDecoration(
                      color: def.color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(11.r),
                    ),
                    child: Icon(def.icon, color: def.color, size: 20.sp),
                  ),
                  const Spacer(),
                  if (enabled)
                    Icon(Icons.chevron_left_rounded,
                        size: 18.sp,
                        color: def.color.withValues(alpha: 0.65)),
                ],
              ),
              SizedBox(height: 10.h),
              Text(
                '${def.count}',
                style: GoogleFonts.cairo(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w900,
                  color: def.color,
                  height: 1.05,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                def.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 11.5.sp,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
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

    return Wrap(
      spacing: 10.w,
      runSpacing: 10.h,
      children: [
        for (final e in show)
          SasKpiCard(
            label: _financeLabel(e.key),
            value: sasMoneyShort(e.key, e.value),
            icon: _financeIcon(e.key),
            color: _financeColor(e.key),
          ),
      ],
    );
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
    };
    final k = key.toLowerCase();
    if (labels.containsKey(k)) return labels[k]!;
    if (k.contains('balance')) return 'الرصيد';
    if (k.contains('income') || k.contains('revenue')) return 'الدخل';
    if (k.contains('debt')) return 'الديون';
    if (k.contains('credit')) return 'الائتمان';
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
