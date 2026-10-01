import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_format.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';
import 'sas_explorer_page.dart';
import 'sas_license_page.dart';
import 'sas_package_prices_page.dart';
import 'sas_system_managers.dart';
import 'sas_system_online.dart';

/// تبويب «نظام الساس» — قسم مركزي بتبويبات فرعية للحساب المحدّد:
/// نظرة عامة (صحّة/مالية/باقات) · المتصلون الآن · الوكلاء · السجلات.
///
/// يوفّر أيضاً أزراراً سريعة للتقارير والترخيص والمستكشف. كل قسم يجلب من
/// نقطته المستقلّة بحالات تحميل/خطأ/فراغ، ويعالج حجب الوكلاء (403) بحالة واضحة.
class SasSystemTab extends StatefulWidget {
  final SasAccount account;
  const SasSystemTab({super.key, required this.account});

  @override
  State<SasSystemTab> createState() => _SasSystemTabState();
}

class _SasSystemTabState extends State<SasSystemTab>
    with SingleTickerProviderStateMixin {
  late final TabController _sub;

  static const _subTabs = <(String, IconData)>[
    ('نظرة عامة', Icons.speed_rounded),
    ('المتصلون', Icons.wifi_tethering_rounded),
    ('الوكلاء', Icons.badge_rounded),
    ('السجلات', Icons.history_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _sub = TabController(length: _subTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _sub.dispose();
    super.dispose();
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _quickActions(),
        _subTabBar(),
        Expanded(
          child: TabBarView(
            controller: _sub,
            children: [
              _SystemOverview(
                  account: widget.account,
                  key: ValueKey('ovw-${widget.account.id}')),
              SasSystemOnline(
                  account: widget.account,
                  key: ValueKey('onl-${widget.account.id}')),
              SasSystemManagers(
                  account: widget.account,
                  key: ValueKey('mgr-${widget.account.id}')),
              _SystemLogs(
                  account: widget.account,
                  key: ValueKey('log-${widget.account.id}')),
            ],
          ),
        ),
      ],
    );
  }

  /// أزرار سريعة (ترخيص · مستكشف) بتمرير أفقي فلا تُقطع.
  ///
  /// ملاحظة: التقارير المجمّعة والتفصيلية رُقّيت إلى تبويب «تقارير» مستقل في
  /// الشل (مطابقةً لتطبيق الوكلاء)، فلم تعد تُكرَّر هنا. يبقى الترخيص والمستكشف
  /// كاختصارَين سريعَين ضمن سياق نظام الساس.
  ///
  /// هامش علوي واضح يفصلها عن شريط تبويبات الشل أعلاه، وارتفاع كافٍ لظلال
  /// الرقائق فلا تُقطع بصرياً.
  Widget _quickActions() {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        children: [
          _actionChip('أسعار الباقات', Icons.sell_rounded,
              const [AppTheme.warningColor, Color(0xFFFFB74D)],
              () => _open(SasPackagePricesPage(account: widget.account))),
          SizedBox(width: 8.w),
          _actionChip('الترخيص', Icons.verified_user_rounded,
              AppTheme.orangeGradient,
              () => _open(SasLicensePage(account: widget.account))),
          SizedBox(width: 8.w),
          _actionChip('مستكشف الساس', Icons.travel_explore_rounded,
              const [AppTheme.infoColor, AppTheme.secondaryColor],
              () => _open(SasExplorerPage(account: widget.account))),
        ],
      ),
    );
  }

  Widget _actionChip(
      String label, IconData icon, List<Color> gradient, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30.r),
            boxShadow: [
              BoxShadow(
                color: gradient.first.withValues(alpha: 0.28),
                blurRadius: 8,
                spreadRadius: -2,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16.sp, color: Colors.white),
              SizedBox(width: 6.w),
              Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 12.5.sp,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subTabBar() {
    return Container(
      margin: EdgeInsets.fromLTRB(8.w, 0, 8.w, 6.h),
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: SasUi.cardShadow(),
      ),
      child: TabBar(
        controller: _sub,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          gradient: const LinearGradient(colors: AppTheme.blueGradient),
          borderRadius: BorderRadius.circular(10.r),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle:
            GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 12.5.sp),
        unselectedLabelStyle:
            GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12.5.sp),
        tabs: [
          for (final t in _subTabs)
            Tab(
              height: 36.h,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.$2, size: 15.sp),
                    SizedBox(width: 5.w),
                    Text(t.$1),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════ نظرة عامة: صحّة · مالية · باقات ═══════════════════════

class _SystemOverview extends StatefulWidget {
  final SasAccount account;
  const _SystemOverview({super.key, required this.account});

  @override
  State<_SystemOverview> createState() => _SystemOverviewState();
}

class _SystemOverviewState extends State<_SystemOverview> {
  final _api = SasAgentApiService.instance;

  List<Map<String, dynamic>>? _packages;
  String? _packagesError;
  Map<String, dynamic>? _finance;
  String? _financeError;
  Map<String, dynamic>? _health;
  String? _healthError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _packages = null;
      _packagesError = null;
      _finance = null;
      _financeError = null;
      _health = null;
      _healthError = null;
    });
    final id = widget.account.id;
    await Future.wait([
      _api.getPackages(id).then((v) => _packages = v).catchError((Object e) {
        _packagesError = _clean(e);
        return <Map<String, dynamic>>[];
      }),
      _api.getFinance(id).then((v) => _finance = v).catchError((Object e) {
        _financeError = _clean(e);
        return <String, dynamic>{};
      }),
      _api.getHealth(id).then((v) => _health = v).catchError((Object e) {
        _healthError = _clean(e);
        return <String, dynamic>{};
      }),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب نظام الساس…');
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: EdgeInsets.all(14.w),
        children: [
          const SasSectionHeader(
            title: 'صحّة النظام',
            icon: Icons.health_and_safety_rounded,
            gradient: AppTheme.greenGradient,
          ),
          SizedBox(height: 10.h),
          _healthSection(),
          SizedBox(height: 20.h),
          const SasSectionHeader(
            title: 'الملخّص المالي',
            icon: Icons.account_balance_wallet_rounded,
            gradient: AppTheme.orangeGradient,
          ),
          SizedBox(height: 10.h),
          _financeSection(),
          SizedBox(height: 20.h),
          const SasSectionHeader(
            title: 'الباقات',
            icon: Icons.inventory_2_rounded,
          ),
          SizedBox(height: 10.h),
          _packagesSection(),
        ],
      ),
    );
  }

  // ─── الصحّة: أشرطة استخدام + حالة خدمات ───
  Widget _healthSection() {
    if (_healthError != null) return _inlineError(_healthError!);
    final h = _health ?? const {};
    if (h.isEmpty) return _inlineEmpty('لا تتوفّر بيانات صحّة للنظام');

    // نلتقط النِّسب (CPU/RAM/Disk) من مفاتيح شائعة، والباقي كخدمات/قيم.
    double? pct(List<String> keys) {
      for (final k in h.keys) {
        if (keys.any((kk) => k.toLowerCase().contains(kk))) {
          final n = sasNum(h[k])?.toDouble();
          if (n != null) return n > 1 ? n : n * 100;
        }
      }
      return null;
    }

    final cpu = pct(['cpu']);
    final mem = pct(['mem', 'ram']);
    final disk = pct(['disk', 'storage']);

    final services = h.entries
        .where((e) => e.value is bool || e.value is String)
        .toList();

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cpu != null)
            SasUsageBar(
                label: 'المعالج (CPU)', percent: cpu, icon: Icons.memory),
          if (mem != null)
            SasUsageBar(
                label: 'الذاكرة (RAM)', percent: mem, icon: Icons.storage),
          if (disk != null)
            SasUsageBar(
                label: 'القرص (Disk)', percent: disk, icon: Icons.disc_full),
          if (cpu == null && mem == null && disk == null && services.isEmpty)
            _kvInline(h),
          if (services.isNotEmpty) ...[
            if (cpu != null || mem != null || disk != null)
              SizedBox(height: 6.h),
            Text('حالة الخدمات',
                style: GoogleFonts.cairo(
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[700])),
            SizedBox(height: 10.h),
            Wrap(
              spacing: 10.w,
              runSpacing: 10.h,
              children: [
                for (final e in services)
                  SasServiceCard(name: e.key, value: e.value),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── المالية: بطاقات KPI بتنسيق M/K ───
  Widget _financeSection() {
    if (_financeError != null) return _inlineError(_financeError!);
    final f = _finance ?? const {};
    if (f.isEmpty) return _inlineEmpty('لا يتوفّر ملخّص مالي');

    final numeric = f.entries.where((e) => e.value is num).toList();
    final textual =
        f.entries.where((e) => e.value != null && e.value is! num).toList();

    if (numeric.isEmpty && textual.isEmpty) {
      return _inlineEmpty('لا توجد تفاصيل مالية قابلة للعرض');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (numeric.isNotEmpty)
          Wrap(
            spacing: 10.w,
            runSpacing: 10.h,
            children: [
              for (final e in numeric)
                SasKpiCard(
                  label: _financeLabel(e.key),
                  value: sasMoneyShort(e.key, e.value),
                  icon: _financeIcon(e.key),
                  color: _financeColor(e.key),
                ),
            ],
          ),
        if (textual.isNotEmpty) ...[
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
            decoration: SasUi.card(),
            child: Column(
              children: [
                for (int i = 0; i < textual.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1,
                        color: Colors.grey.withValues(alpha: 0.10)),
                  _kvRow(_financeLabel(textual[i].key), '${textual[i].value}'),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ─── الباقات ───
  Widget _packagesSection() {
    if (_packagesError != null) return _inlineError(_packagesError!);
    final list = _packages ?? const [];
    if (list.isEmpty) return _inlineEmpty('لا توجد باقات لعرضها');
    return Column(
      children: [
        for (final p in list) ...[
          _packageCard(p),
          SizedBox(height: 8.h),
        ],
      ],
    );
  }

  Widget _packageCard(Map<String, dynamic> p) {
    final name = (p['name'] ??
            p['Name'] ??
            p['title'] ??
            p['profile'] ??
            p['label'] ??
            '')
        .toString();
    final price =
        (p['price'] ?? p['Price'] ?? p['cost'] ?? p['amount'])?.toString();
    final speed = (p['speed'] ?? p['Speed'] ?? p['bandwidth'])?.toString();
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Row(
        children: [
          SasUi.gradientBadge(
            icon: Icons.wifi_tethering_rounded,
            colors: const [AppTheme.infoColor, AppTheme.secondaryColor],
            size: 40,
            iconSize: 20,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.isEmpty ? '-' : name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A2E))),
                if (speed != null || price != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    [
                      if (speed != null) 'السرعة: $speed',
                      if (price != null) 'السعر: $price',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: 11.5.sp, color: Colors.grey[600]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvInline(Map<String, dynamic> map) {
    final entries = map.entries
        .where((e) => e.value is! Map && e.value is! List)
        .toList();
    if (entries.isEmpty) return _inlineEmpty('لا توجد تفاصيل قابلة للعرض');
    return Column(
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: Colors.grey.withValues(alpha: 0.10)),
          _kvRow(entries[i].key, '${entries[i].value}'),
        ],
      ],
    );
  }

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 12.5.sp,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: 10.w),
          Expanded(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.end,
                style: GoogleFonts.cairo(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

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
      'subscriptions': 'الاشتراكات',
      'total_subscriptions': 'إجمالي الاشتراكات',
      'renewals': 'التجديدات',
      'new_users': 'مشتركون جدد',
      'expired_users': 'مشتركون منتهون',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  IconData _financeIcon(String key) {
    if (key.contains('income') ||
        key.contains('revenue') ||
        key.contains('profit')) {
      return Icons.trending_up_rounded;
    }
    if (key.contains('debt') || key.contains('expense')) {
      return Icons.trending_down_rounded;
    }
    if (key.contains('balance') || key.contains('credit')) {
      return Icons.account_balance_wallet_rounded;
    }
    if (key.contains('subscription') || key.contains('renewal')) {
      return Icons.subscriptions_rounded;
    }
    if (key.contains('user') || key.contains('subscriber')) {
      return Icons.people_rounded;
    }
    return Icons.bar_chart_rounded;
  }

  Color _financeColor(String key) {
    if (key.contains('income') ||
        key.contains('revenue') ||
        key.contains('profit')) {
      return AppTheme.successColor;
    }
    if (key.contains('debt') || key.contains('expense')) {
      return AppTheme.errorColor;
    }
    if (key.contains('balance') || key.contains('credit')) {
      return const Color(0xFF009688);
    }
    if (key.contains('subscription')) return AppTheme.secondaryColor;
    if (key.contains('user')) return AppTheme.infoColor;
    return Colors.blueGrey;
  }

  Widget _inlineError(String msg) => Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12.r),
          border:
              Border.all(color: AppTheme.errorColor.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: AppTheme.errorColor, size: 20.sp),
            SizedBox(width: 8.w),
            Expanded(
                child: Text(msg,
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp, color: Colors.grey[800]))),
            TextButton(
                onPressed: _loadAll,
                child: Text('إعادة', style: GoogleFonts.cairo())),
          ],
        ),
      );

  Widget _inlineEmpty(String msg) => Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Icon(Icons.inbox_rounded, color: Colors.grey[400], size: 20.sp),
            SizedBox(width: 8.w),
            Expanded(
                child: Text(msg,
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp, color: Colors.grey[600]))),
          ],
        ),
      );
}

// ═══════════════════════ السجلات: دخول + نظام ═══════════════════════

class _SystemLogs extends StatefulWidget {
  final SasAccount account;
  const _SystemLogs({super.key, required this.account});

  @override
  State<_SystemLogs> createState() => _SystemLogsState();
}

class _SystemLogsState extends State<_SystemLogs>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14.w, 8.h, 14.w, 4.h),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                  value: 0,
                  label: Text('سجل الدخول'),
                  icon: Icon(Icons.login_rounded, size: 16)),
              ButtonSegment(
                  value: 1,
                  label: Text('سجل النظام'),
                  icon: Icon(Icons.terminal_rounded, size: 16)),
            ],
            selected: {_tab.index},
            showSelectedIcon: false,
            style: ButtonStyle(
              textStyle: WidgetStatePropertyAll(
                  GoogleFonts.cairo(fontSize: 12.sp, fontWeight: FontWeight.w700)),
            ),
            onSelectionChanged: (s) {
              setState(() => _tab.index = s.first);
            },
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab.index,
            children: [
              _LogList(
                  account: widget.account,
                  path: 'index/userauthlog',
                  kind: _LogKind.auth,
                  key: ValueKey('auth-${widget.account.id}')),
              _LogList(
                  account: widget.account,
                  path: 'index/syslog',
                  kind: _LogKind.syslog,
                  key: ValueKey('sys-${widget.account.id}')),
            ],
          ),
        ),
      ],
    );
  }
}

enum _LogKind { auth, syslog }

class _LogList extends StatefulWidget {
  final SasAccount account;
  final String path;
  final _LogKind kind;
  const _LogList(
      {super.key,
      required this.account,
      required this.path,
      required this.kind});

  @override
  State<_LogList> createState() => _LogListState();
}

class _LogListState extends State<_LogList> {
  final _api = SasAgentApiService.instance;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  bool _forbidden = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _forbidden = false;
    });
    try {
      final res = await _api.sasPost(widget.account.id, widget.path, payload: {
        'page': 1,
        'count': 100,
        'sortBy': 'id',
        'direction': 'desc',
        'search': '',
      });
      _rows = sasExtractList(res);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      final msg = _clean(e);
      if (mounted) {
        setState(() {
          _error = msg;
          _forbidden = msg.contains('403') ||
              msg.toLowerCase().contains('forbidden');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SasLoadingView(message: 'جاري جلب السجل…');
    if (_forbidden) {
      return SasEmptyView(
        message: 'هذا السجل غير متاح لحسابك (محجوب من نظام الساس).',
        icon: Icons.lock_outline_rounded,
        action: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('إعادة', style: GoogleFonts.cairo())),
      );
    }
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return SasEmptyView(
        message: 'لا سجلّات',
        icon: Icons.history_rounded,
        action: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('تحديث', style: GoogleFonts.cairo())),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: EdgeInsets.all(12.w),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => SizedBox(height: 6.h),
        itemBuilder: (_, i) => _logCard(_rows[i]),
      ),
    );
  }

  String _s(dynamic v) => (v ?? '').toString();

  Widget _logCard(Map<String, dynamic> row) {
    if (widget.kind == _LogKind.auth) {
      final reply = _s(row['reply']);
      final accepted = reply.toLowerCase().contains('accept');
      final color = accepted ? AppTheme.successColor : AppTheme.errorColor;
      return Container(
        padding: EdgeInsets.all(12.w),
        decoration: SasUi.card(),
        child: Row(
          children: [
            Icon(accepted ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: color, size: 22.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_s(row['username']),
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 13.sp)),
                  SizedBox(height: 2.h),
                  Text(reply.isEmpty ? '-' : reply,
                      style: GoogleFonts.cairo(fontSize: 11.5.sp, color: color)),
                  if (_s(row['mac']).isNotEmpty ||
                      _s(row['nas_ip_address']).isNotEmpty)
                    Text(
                      [
                        if (_s(row['mac']).isNotEmpty) 'MAC ${_s(row['mac'])}',
                        if (_s(row['nas_ip_address']).isNotEmpty)
                          'NAS ${_s(row['nas_ip_address'])}',
                      ].join(' · '),
                      style: GoogleFonts.cairo(
                          fontSize: 11.sp, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
            Text(_s(row['created_at']),
                style: GoogleFonts.cairo(
                    fontSize: 10.5.sp, color: Colors.grey[500])),
          ],
        ),
      );
    }
    // syslog
    final by = row['manager_details'];
    final byName = by is Map ? _s(by['username']) : _s(row['created_by']);
    final title =
        _s(row['event']).isEmpty ? _s(row['description']) : _s(row['event']);
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.article_outlined,
              color: Colors.blueGrey, size: 22.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.isEmpty ? '-' : title,
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700, fontSize: 12.5.sp)),
                if (_s(row['description']).isNotEmpty &&
                    _s(row['event']).isNotEmpty)
                  Text(_s(row['description']),
                      style: GoogleFonts.cairo(
                          fontSize: 11.5.sp, color: Colors.grey[700])),
                SizedBox(height: 2.h),
                Text(
                  [
                    if (byName.isNotEmpty) 'بواسطة $byName',
                    if (_s(row['ip']).isNotEmpty) 'IP ${_s(row['ip'])}',
                  ].join(' · '),
                  style: GoogleFonts.cairo(
                      fontSize: 11.sp, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Text(_s(row['created_at']),
              style:
                  GoogleFonts.cairo(fontSize: 10.5.sp, color: Colors.grey[500])),
        ],
      ),
    );
  }
}
