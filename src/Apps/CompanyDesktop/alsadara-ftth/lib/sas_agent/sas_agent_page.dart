import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../permissions/permission_gate.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_helper.dart';
import 'models/sas_account.dart';
import 'pages/sas_accounts_page.dart';
import 'pages/sas_dashboard_tab.dart';
import 'pages/sas_renewal_tab.dart';
import 'pages/sas_report_tab.dart';
import 'pages/sas_reports_tab.dart';
import 'pages/sas_settings_tab.dart';
import 'pages/sas_subscribers_tab.dart';
import 'pages/sas_system_tab.dart';
import 'pages/sas_tickets_tab.dart';
import 'premises/ui/premises_list_screen.dart';
import 'services/sas_agent_api_service.dart';
import 'whatsapp/whatsapp.dart';
import 'widgets/sas_refresh_bus.dart';
import 'widgets/sas_state_views.dart';

/// صفحة «وكيل الساس» — شل بتبويبات يعمل على بوّابة الصدارة `/api/sas-agent/*`.
///
/// التبويبات (مطابقة لتطبيق الوكلاء): حسابات · لوحة · مشتركون · نظام الساس ·
/// تقارير · تجديد · تصريح/بلنك · تذاكر · إعدادات.
/// الظهور محكوم بصلاحية `sas_agent` عبر [PermissionGate.page].
class SasAgentPage extends StatelessWidget {
  const SasAgentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PermissionGate.page(
      permission: 'sas_agent',
      pageName: 'صفحة وكيل الساس',
      child: const _SasAgentShell(),
    );
  }
}

class _SasAgentShell extends StatefulWidget {
  const _SasAgentShell();

  @override
  State<_SasAgentShell> createState() => _SasAgentShellState();
}

class _SasAgentShellState extends State<_SasAgentShell>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  /// الحساب المحدد الذي تعمل عليه بقية التبويبات.
  SasAccount? _selected;

  /// فهرس تبويب «مشتركون» — للانتقال إليه من بطاقات «قرب الانتهاء» في اللوحة.
  static const int _subscribersTabIndex = 2;

  /// فهرس تبويب «الحسابات» — للانتقال إليه من تبويب «الإعدادات».
  static const int _accountsTabIndex = 0;

  /// فلتر انتهاء مطلوب من اللوحة (overdue/today/soon3/soon7)؛ يُمرَّر لتبويب
  /// «مشتركون» ثم يُصفَّر. يُغيَّر مفتاح الودجة عند كل طلب لإعادة تطبيقه بثبات.
  String? _pendingExpiring;
  int _expiryNavToken = 0;

  // ─── مزامنة عند دخول التبويب (debounce + حارس) ───
  // الساس يُسحب بالاستعلام لا بالدفع، فالمزامنة = syncAccount ثم إشعار الناقل.
  final _api = SasAgentApiService.instance;

  /// آخر وقت مزامنة ناجح لكل حساب (لمنع المزامنة المتكرّرة عند التنقّل السريع).
  final Map<String, DateTime> _lastTabSync = <String, DateTime>{};

  /// مزامنة تبويب جارية الآن (حارس يمنع التزامن المكرّر).
  bool _tabSyncing = false;

  /// مؤقّت debounce لتثبيت الاستقرار على تبويب قبل إطلاق المزامنة.
  Timer? _tabSyncDebounce;

  /// الحدّ الأدنى بين مزامنتَي الدخول للحساب الواحد.
  static const _tabSyncCooldown = Duration(seconds: 20);

  /// فترة تثبيت الاستقرار على التبويب قبل المزامنة (تمنع المزامنة أثناء التنقّل
  /// السريع عبر التبويبات).
  static const _tabSyncDebounceDelay = Duration(milliseconds: 600);

  /// فهارس تبويبات البيانات التي تستفيد من مزامنة عند الدخول (تحتاج حساباً
  /// محدّداً): لوحة · مشتركون · نظام · تقارير · تجديد · تصريح. تُستثنى: الحسابات
  /// (0) · التذاكر (7، user-scoped) · الإعدادات (8).
  static const _dataTabIndices = <int>{1, 2, 3, 4, 5, 6};

  // مجموعة أيقونات موحّدة (Material rounded بوزن بصري واحد) بترتيب مطابق
  // لتطبيق الوكلاء المرجعي: حسابات · لوحة · مشتركون · نظام · تقارير · تجديد ·
  // تصريح · تذاكر · إعدادات. لون المؤشّر للمحدّد متدرّج، ولون موحّد (Slate)
  // لغير المحدّد — يُضبطان مركزياً في [_TabBarSurface].
  static const _tabs = <_TabDef>[
    _TabDef('الحسابات', Icons.link_rounded),
    _TabDef('لوحة', Icons.dashboard_rounded),
    _TabDef('مشتركون', Icons.people_rounded),
    _TabDef('نظام الساس', Icons.dns_rounded),
    _TabDef('تقارير', Icons.bar_chart_rounded),
    _TabDef('تجديد', Icons.autorenew_rounded),
    _TabDef('تصريح/بلنك', Icons.balance_rounded),
    _TabDef('تذاكر', Icons.confirmation_number_rounded),
    _TabDef('إعدادات', Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    _tab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabSyncDebounce?.cancel();
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onSelect(SasAccount acc) {
    if (_selected?.id == acc.id) return;
    setState(() {
      _selected = acc;
      _pendingExpiring = null; // فلتر اللوحة خاص بالحساب السابق.
    });
    // حساب جديد ⇒ أسقِط ختم المزامنة السابق فتُزامَن عند دخول أوّل تبويب بيانات.
    _lastTabSync.remove(acc.id);
  }

  // ─────────────────────── مزامنة عند دخول التبويب ───────────────────────

  /// يُستدعى عند تغيّر التبويب النشط. يطلق مزامنة مؤجّلة (debounce) عند الاستقرار
  /// على تبويب بيانات، إن مرّ وقت كافٍ على آخر مزامنة للحساب.
  void _onTabChanged() {
    // نتفاعل فقط عند استقرار التبويب (نهاية الحركة) لا أثناء الانزلاق.
    if (_tab.indexIsChanging) return;
    _maybeSyncCurrentTab();
  }

  /// يجدول مزامنة للحساب المحدّد إن كان التبويب الحالي تبويب بيانات وانقضى وقت
  /// التهدئة منذ آخر مزامنة. مؤجّلة عبر [_tabSyncDebounceDelay] لمنع التكرار عند
  /// التنقّل السريع، ومحميّة بحارس [_tabSyncing] ضدّ التزامن المكرّر.
  void _maybeSyncCurrentTab() {
    final acc = _selected;
    if (acc == null) return;
    if (!_dataTabIndices.contains(_tab.index)) return;

    final last = _lastTabSync[acc.id];
    if (last != null && DateTime.now().difference(last) < _tabSyncCooldown) {
      return; // مُزامَن حديثاً — لا داعي.
    }

    _tabSyncDebounce?.cancel();
    _tabSyncDebounce = Timer(_tabSyncDebounceDelay, () => _syncOnEnter(acc.id));
  }

  /// ينفّذ المزامنة الفعلية ثم يبثّ الإشعار (معزول). يسجّل ختم الوقت عند النجاح
  /// فقط فلا نُطيل التهدئة عند الفشل.
  Future<void> _syncOnEnter(String accountId) async {
    if (_tabSyncing) return;
    // قد يكون المستخدم بدّل الحساب خلال التأجيل — تحقّق مجدّداً.
    if (_selected?.id != accountId) return;
    _tabSyncing = true;
    try {
      await _api.syncAccount(accountId);
      _lastTabSync[accountId] = DateTime.now();
    } catch (_) {
      // فشل المزامنة معزول — نُبقي الإشعار لإعادة قراءة الحالة المحلية الحالية.
    } finally {
      _tabSyncing = false;
    }
    // أبلغ التبويبات المفتوحة لتعيد التحميل (حتى عند فشل المزامنة: تقرأ الأحدث).
    SasRefreshBus.instance.notify(accountId: accountId, reason: 'tab-enter');
  }

  /// ينتقل لتبويب «مشتركون» مفلترًا على نافذة الانتهاء المطلوبة من اللوحة.
  void _openSubscribersExpiring(String expiring) {
    setState(() {
      _pendingExpiring = expiring;
      _expiryNavToken++;
    });
    _tab.animateTo(_subscribersTabIndex);
  }

  @override
  Widget build(BuildContext context) {
    // أحجام ثابتة/مقيّدة لسطح المكتب — لا نعتمد على `.h/.w/.sp` المتضخّمة على
    // النوافذ العريضة (designSize=375). الرأس أعلى من ارتفاع محتواه بهامش كافٍ
    // فلا يتصادم مع شريط التبويبات أسفله، والتبويبات قابلة للتمرير فلا تُقطع.
    const double toolbarH = 64;
    const double tabBarH = 60;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          toolbarHeight: toolbarH,
          // خلفية صلبة داكنة أسفل التدرّج + مقدّمة بيضاء صريحة (زر العودة/الأيقونات/العنوان)
          // لضمان ظهورها دائماً حتى لو تعذّر رسم التدرّج (كانت بيضاء على خلفية فاتحة فتختفي).
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
          actionsIconTheme: const IconThemeData(color: Colors.white),
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.30)),
                ),
                child: const Icon(Icons.hub_rounded,
                    size: 20, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('وكيل الساس',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w800, fontSize: 17)),
                    Text(
                      _selected?.displayName ?? 'إدارة حسابات الساس',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _headerAction(
              tooltip: 'العقارات (العنوان الوطني)',
              icon: Icons.maps_home_work_rounded,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PremisesListScreen()),
              ),
            ),
            const SizedBox(width: 6),
            _headerAction(
              tooltip: 'إعدادات وقوالب الواتساب',
              icon: Icons.chat_rounded,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WaSettingsScreen()),
              ),
            ),
            const SizedBox(width: 10),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(tabBarH),
            child: _TabBarSurface(controller: _tab, tabs: _tabs),
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            // 1) الحسابات
            _framed(SasAccountsPage(selected: _selected, onSelect: _onSelect)),
            // 2) لوحة
            _framed(_needsAccount(
              (acc) => SasDashboardTab(
                account: acc,
                key: ValueKey('dash-${acc.id}'),
                onOpenExpiring: _openSubscribersExpiring,
              ),
            )),
            // 3) مشتركون
            _framed(_needsAccount(
              (acc) => SasSubscribersTab(
                account: acc,
                initialExpiring: _pendingExpiring,
                // مفتاح يتضمّن رمز الطلب: يعيد بناء التبويب عند كل انتقال من
                // اللوحة ليطبّق الفلتر الجديد بثبات حتى لو لم يتغيّر الحساب.
                key: ValueKey('subs-${acc.id}-$_expiryNavToken'),
              ),
            )),
            // 4) نظام الساس (باقات + مالية + صحّة)
            _framed(_needsAccount(
              (acc) =>
                  SasSystemTab(account: acc, key: ValueKey('sys-${acc.id}')),
            )),
            // 5) تقارير (تبويب مستقل — التقارير المجمّعة + العشرة التفصيلية + الترخيص)
            _framed(_needsAccount(
              (acc) => SasReportsTab(
                  account: acc, key: ValueKey('reports-${acc.id}')),
            )),
            // 6) تجديد (مرشّحون + معاينة dryRun → تنفيذ)
            _framed(_needsAccount(
              (acc) =>
                  SasRenewalTab(account: acc, key: ValueKey('renew-${acc.id}')),
            )),
            // 7) تصريح/بلنك (تقرير الوكيل)
            _framed(_needsAccount(
              (acc) =>
                  SasReportTab(account: acc, key: ValueKey('report-${acc.id}')),
            )),
            // 8) تذاكر (إعادة استخدام نظام الدعم القائم)
            _framed(const SasTicketsTab()),
            // 9) إعدادات (الحساب · الخادم · الواتساب · أدوات · ميزات محفوظة)
            _framed(SasSettingsTab(
              selected: _selected,
              onGoToAccounts: () => _tab.animateTo(_accountsTabIndex),
            )),
          ],
        ),
      ),
    );
  }

  /// زر رأس موحّد النسق: أيقونة بيضاء داخل مربّع شفّاف بحواف مستديرة — نفس
  /// أسلوب شارة العنوان في الرأس، فتتّسق أزرار الواتساب/العقارات بصرياً.
  Widget _headerAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onPressed,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// يحصر عرض محتوى التبويب على الشاشات العريضة (سطح المكتب) ويوسّطه — بنفس
  /// نمط `home_page.dart` (`ConstrainedBox(maxWidth: maxContentWidth)`) — فلا
  /// يتمدّد المحتوى عبر ~1900px. على الهاتف/التابلت يبقى بعرض كامل.
  Widget _framed(Widget child) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: context.responsive.maxContentWidth),
        child: child,
      ),
    );
  }

  /// يُغلّف تبويباً يحتاج حساباً محدداً؛ يعرض إرشاداً إن لم يُحدَّد.
  Widget _needsAccount(Widget Function(SasAccount acc) builder) {
    final acc = _selected;
    if (acc == null) {
      return SasEmptyView(
        message: 'اختر حساب ساس من تبويب «الحسابات» أولاً',
        icon: Icons.touch_app_rounded,
        action: FilledButton.icon(
          onPressed: () => _tab.animateTo(0),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
          icon: const Icon(Icons.link_rounded),
          label: Text('الذهاب للحسابات',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        ),
      );
    }
    return builder(acc);
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  const _TabDef(this.label, this.icon);
}

/// سطح شريط تبويبات أنيق يجلس أسفل رأس التطبيق:
/// شريط أبيض بحواف مستديرة علوية وظل خفيف، مؤشّر متدرّج مدمج (pill) —
/// يفصل التبويبات بصرياً عن رأس التطبيق فلا يتداخلان.
class _TabBarSurface extends StatelessWidget {
  final TabController controller;
  final List<_TabDef> tabs;

  const _TabBarSurface({required this.controller, required this.tabs});

  @override
  Widget build(BuildContext context) {
    // مقاسات ثابتة معقولة لسطح المكتب — لا تعتمد على `.sp/.h/.w/.r` المتضخّمة
    // على النوافذ العريضة. `isScrollable: true` يمنع قطع نصوص التبويبات التسعة.
    // لون موحّد للأيقونة والنص (أبيض للمحدّد فوق مؤشّر متدرّج، Slate لغيره).
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(12),
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppTheme.blueGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withValues(alpha: 0.30),
              blurRadius: 8,
              spreadRadius: -2,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF64748B),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        labelStyle:
            GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 13),
        unselectedLabelStyle:
            GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: [
          for (final t in tabs)
            Tab(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon, size: 16),
                    const SizedBox(width: 6),
                    Text(t.label),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
