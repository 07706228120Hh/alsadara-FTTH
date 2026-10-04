import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../permissions/permission_gate.dart';
import '../theme/app_theme.dart';
import '../utils/responsive_helper.dart';
import 'models/sas_account.dart';
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
/// التبويبات: لوحة · مشتركون · نظام الساس · تقارير · تجديد · تصريح/بلنك ·
/// تذاكر · إعدادات. إدارة الحسابات انتقلت لتبويب «الإعدادات»، والتبديل بين
/// الحسابات يتم من مُبدّل الحساب في الترويسة (AppBar).
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

  /// قائمة حسابات المستخدم (تُحمَّل مرّة في [initState]) لتغذية مُبدّل الحساب
  /// في الترويسة. فارغة حتى اكتمال التحميل.
  List<SasAccount> _accounts = <SasAccount>[];

  /// هل يجري تحميل قائمة الحسابات لمُبدّل الترويسة؟
  bool _accountsLoading = true;

  /// فهرس تبويب «مشتركون» — للانتقال إليه من بطاقات «قرب الانتهاء» في اللوحة.
  static const int _subscribersTabIndex = 1;

  /// فهرس تبويب «الإعدادات» — للانتقال إليه لإدارة الحسابات (نُقلت للإعدادات).
  static const int _settingsTabIndex = 7;

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

  /// مزامنة يدوية جارية من زر «تحديث» في الشريط العلوي (حارس ضدّ التكرار).
  bool _manualSyncing = false;

  /// مؤقّت debounce لتثبيت الاستقرار على تبويب قبل إطلاق المزامنة.
  Timer? _tabSyncDebounce;

  /// الحدّ الأدنى بين مزامنتَي الدخول للحساب الواحد.
  static const _tabSyncCooldown = Duration(seconds: 20);

  /// فترة تثبيت الاستقرار على التبويب قبل المزامنة (تمنع المزامنة أثناء التنقّل
  /// السريع عبر التبويبات).
  static const _tabSyncDebounceDelay = Duration(milliseconds: 600);

  /// فهارس تبويبات البيانات التي تستفيد من مزامنة عند الدخول (تحتاج حساباً
  /// محدّداً): لوحة · مشتركون · نظام · تقارير · تجديد · تصريح. تُستثنى: التذاكر
  /// (6، user-scoped) · الإعدادات (7).
  static const _dataTabIndices = <int>{0, 1, 2, 3, 4, 5};

  // مجموعة أيقونات موحّدة (Material rounded بوزن بصري واحد) بترتيب:
  // لوحة · مشتركون · نظام · تقارير · تجديد · تصريح · تذاكر · إعدادات.
  // (تبويب «الحسابات» نُقل لتبويب «الإعدادات»، والتبديل بين الحسابات من
  // مُبدّل الترويسة.) لون المؤشّر للمحدّد متدرّج، ولون موحّد (Slate) لغيره —
  // يُضبطان مركزياً في [_TabBarSurface].
  static const _tabs = <_TabDef>[
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
    _loadAccounts();
  }

  /// يحمّل قائمة الحسابات مرّة لتغذية مُبدّل الترويسة، ويختار الأول تلقائياً إن
  /// لم يُحدَّد حساب بعد (مُفضّلاً المفعّل). فشل التحميل معزول (يُبقي المبدّل
  /// فارغاً، وإدارة الحسابات من الإعدادات تبقى المرجع).
  Future<void> _loadAccounts() async {
    try {
      final list = await _api.getAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = list;
        _accountsLoading = false;
        if (_selected == null && list.isNotEmpty) {
          _selected =
              list.firstWhere((a) => a.isActive, orElse: () => list.first);
        }
      });
    } catch (_) {
      if (mounted) setState(() => _accountsLoading = false);
    }
  }

  @override
  void dispose() {
    _tabSyncDebounce?.cancel();
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onSelect(SasAccount acc) {
    // حدّث نسخة الحساب في قائمة المبدّل (قد تكون عُدّلت/أُنشئت من الإعدادات).
    final idx = _accounts.indexWhere((a) => a.id == acc.id);
    if (idx >= 0) {
      _accounts[idx] = acc;
    } else {
      _accounts = [..._accounts, acc];
    }
    if (_selected?.id == acc.id) {
      // نفس الحساب — فقط حدّث مرجع الكائن في المبدّل/الترويسة.
      setState(() => _selected = acc);
      return;
    }
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

  // ─────────────────────── مزامنة يدوية من الشريط العلوي ───────────────────────

  /// مزامنة كاملة يدوية للحساب المحدّد (زر «تحديث» في [AppBar]) — مستقلّة عن
  /// مزامنة دخول التبويب [_syncOnEnter]. تضرب SAS4 ثم تبثّ عبر الناقل فتعيد
  /// التبويبات المفتوحة (ومنها اللوحة) التحميل الخفيف تلقائياً. محميّة بحارس
  /// [_manualSyncing] ضدّ الضغط المتكرّر، وتعرض نتيجة عربية عبر SnackBar.
  Future<void> _manualSync() async {
    final acc = _selected;
    if (acc == null || _manualSyncing) return;
    setState(() => _manualSyncing = true);
    try {
      final r = await _api.syncAccount(acc.id);
      // سجّل ختم المزامنة فلا يكرّرها دخول التبويب مباشرةً بعدها.
      _lastTabSync[acc.id] = DateTime.now();
      if (!mounted) return;
      _snack('تمت المزامنة · ${r.count} مشترك');
      SasRefreshBus.instance.notify(accountId: acc.id, reason: 'appbar-sync');
    } catch (e) {
      if (mounted) {
        _snack(e.toString().replaceFirst('Exception: ', '').trim(),
            error: true);
      }
    } finally {
      if (mounted) setState(() => _manualSyncing = false);
    }
  }

  /// SnackBar عربي موحّد (نجاح أخضر/خطأ أحمر) بخط Cairo وسلوك عائم.
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
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
                    const SizedBox(height: 2),
                    _accountSwitcher(),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _syncAction(),
            const SizedBox(width: 6),
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
            // 1) لوحة
            _framed(_needsAccount(
              (acc) => SasDashboardTab(
                account: acc,
                key: ValueKey('dash-${acc.id}'),
                onOpenExpiring: _openSubscribersExpiring,
              ),
            )),
            // 2) مشتركون
            _framed(_needsAccount(
              (acc) => SasSubscribersTab(
                account: acc,
                initialExpiring: _pendingExpiring,
                // مفتاح يتضمّن رمز الطلب: يعيد بناء التبويب عند كل انتقال من
                // اللوحة ليطبّق الفلتر الجديد بثبات حتى لو لم يتغيّر الحساب.
                key: ValueKey('subs-${acc.id}-$_expiryNavToken'),
              ),
            )),
            // 3) نظام الساس (باقات + مالية + صحّة)
            _framed(_needsAccount(
              (acc) =>
                  SasSystemTab(account: acc, key: ValueKey('sys-${acc.id}')),
            )),
            // 4) تقارير (تبويب مستقل — التقارير المجمّعة + العشرة التفصيلية + الترخيص)
            _framed(_needsAccount(
              (acc) => SasReportsTab(
                  account: acc, key: ValueKey('reports-${acc.id}')),
            )),
            // 5) تجديد (مرشّحون + معاينة dryRun → تنفيذ)
            _framed(_needsAccount(
              (acc) =>
                  SasRenewalTab(account: acc, key: ValueKey('renew-${acc.id}')),
            )),
            // 6) تصريح/بلنك (تقرير الوكيل)
            _framed(_needsAccount(
              (acc) =>
                  SasReportTab(account: acc, key: ValueKey('report-${acc.id}')),
            )),
            // 7) تذاكر (إعادة استخدام نظام الدعم القائم)
            _framed(const SasTicketsTab()),
            // 8) إعدادات (الحسابات · الخادم · الواتساب · أدوات · ميزات محفوظة)
            _framed(SasSettingsTab(
              selected: _selected,
              onSelectAccount: _onSelect,
            )),
          ],
        ),
      ),
    );
  }

  /// زر «تحديث/مزامنة» في الشريط العلوي — بنفس نسق [_headerAction] (أيقونة
  /// بيضاء داخل مربّع شفّاف). ينفّذ مزامنة يدوية للحساب المحدّد عبر [_manualSync]
  /// (ثم بثّ عبر الناقل فتعيد التبويبات المفتوحة التحميل). أثناء المزامنة يُظهر
  /// مؤشّر دوران أبيض صغير مكان الأيقونة. يُعطَّل (بلا نقر، مع تعتيم) إن لم يوجد
  /// حساب محدّد أو أثناء تحميل الحسابات/المزامنة.
  Widget _syncAction() {
    final disabled = _selected == null || _accountsLoading || _manualSyncing;
    final box = Material(
      color: Colors.white.withValues(alpha: disabled ? 0.08 : 0.16),
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: disabled ? null : _manualSync,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
                color: Colors.white.withValues(alpha: disabled ? 0.16 : 0.28)),
          ),
          child: _manualSyncing
              ? const Center(
                  child: SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
                )
              : Icon(Icons.sync_rounded,
                  size: 19,
                  color: Colors.white.withValues(alpha: disabled ? 0.55 : 1.0)),
        ),
      ),
    );
    return Tooltip(message: 'تحديث/مزامنة', child: box);
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

  /// يُغلّف تبويباً يحتاج حساباً محدداً؛ يعرض إرشاداً إن لم يُحدَّد. إدارة
  /// الحسابات نُقلت لتبويب «الإعدادات»، فالزر يوجّه إليها لربط/تحديد حساب.
  Widget _needsAccount(Widget Function(SasAccount acc) builder) {
    final acc = _selected;
    if (acc == null) {
      // قد تكون القائمة ما زالت تُحمَّل عند أول فتح — اعرض مؤشّراً بدل الإرشاد.
      if (_accountsLoading) {
        return const SasLoadingView(message: 'جاري تحميل الحسابات…');
      }
      return SasEmptyView(
        message: 'لا يوجد حساب ساس محدَّد — اربط/حدِّد حساباً من «الإعدادات»',
        icon: Icons.touch_app_rounded,
        action: FilledButton.icon(
          onPressed: () => _tab.animateTo(_settingsTabIndex),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
          icon: const Icon(Icons.settings_rounded),
          label: Text('الذهاب للإعدادات',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        ),
      );
    }
    return builder(acc);
  }

  // ─────────────────────────── مُبدّل الحساب (الترويسة) ───────────────────────────

  /// مُبدّل الحساب النشط في الترويسة. يعرض اسم الحساب الفعّال دائماً:
  ///  • أثناء التحميل: «جاري التحميل…».
  ///  • حساب واحد فقط: اسمه كنصّ (بلا قائمة — لا جدوى من التبديل).
  ///  • حسابات متعدّدة: زر بقائمة منسدلة لاختيار حساب آخر (يفلتر كل الشاشات).
  ///  • لا حسابات: إرشاد مختصر يفتح الإعدادات لربط حساب.
  Widget _accountSwitcher() {
    if (_accountsLoading) {
      return Text('جاري التحميل…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.75)));
    }

    if (_accounts.isEmpty) {
      return InkWell(
        onTap: () => _tab.animateTo(_settingsTabIndex),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_link_rounded,
                size: 13, color: Colors.white.withValues(alpha: 0.85)),
            const SizedBox(width: 4),
            Text('اربط حساب ساس',
                style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
      );
    }

    final current = _selected;
    final label = current?.displayName ?? 'اختر حساباً';

    // حساب واحد فقط ⇒ اعرض الاسم كنصّ (لا قائمة).
    if (_accounts.length == 1) {
      return Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.80)));
    }

    // حسابات متعدّدة ⇒ قائمة منسدلة للتبديل.
    return PopupMenuButton<String>(
      tooltip: 'تبديل الحساب',
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (id) {
        final acc = _accounts.firstWhere((a) => a.id == id,
            orElse: () => _accounts.first);
        _onSelect(acc);
      },
      itemBuilder: (_) => [
        for (final a in _accounts)
          PopupMenuItem<String>(
            value: a.id,
            child: Row(
              children: [
                Icon(
                  a.id == current?.id
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: a.id == current?.id
                      ? AppTheme.primaryColor
                      : Colors.grey,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    a.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontWeight: a.id == current?.id
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: a.isActive ? null : Colors.grey,
                    ),
                  ),
                ),
                if (!a.isActive) ...[
                  const SizedBox(width: 6),
                  Text('(غير مفعّل)',
                      style: GoogleFonts.cairo(
                          fontSize: 10, color: Colors.grey)),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded,
                size: 15, color: Colors.white),
          ],
        ),
      ),
    );
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
