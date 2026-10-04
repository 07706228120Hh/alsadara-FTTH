import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/sadara_api_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../premises/ui/premises_list_screen.dart';
import '../whatsapp/whatsapp.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';
import 'sas_accounts_page.dart';
import 'sas_admin_agents_page.dart';
import 'sas_debtors_page.dart';
import 'sas_explorer_page.dart';
import 'sas_package_prices_page.dart';
import 'sas_profits_page.dart';
import 'sas_regions_page.dart';

/// تبويب «الإعدادات» — مركز إعداد وحدة «وكيل الساس» بثيم منصّة الصدارة.
///
/// منقول ومكيّف من `settings_screen.dart` في تطبيق الوكلاء المرجعي؛ يشمل:
///  • الحساب: هوية المستخدم/الوكيل ودوره ونطاقه.
///  • الخادم: العنوان الحالي وفحص الاتصال الحيّ.
///  • حسابات الساس: تلخيص الحساب المحدّد + مدخل سريع لتبويب «الحسابات».
///  • الواتساب: إعدادات المُرسِل + القوالب (شاشات wa بثيم الصدارة).
///  • مستكشف الساس: متصفّح مدمج يلتقط طلبات الـ API لتحليلها.
///  • العقارات: العنوان الوطني (مدخل سريع).
///  • متقدّم — ميزات محفوظة: قدرات المنصّة (OLT/المراقبة…) كمداخل مؤجّلة.
///
/// لا يخزّن أي أسرار ولا يعرض كلمات مرور؛ يعتمد الجلسة الحيّة عبر
/// [VpsAuthService] وبوّابة الصدارة فقط.
class SasSettingsTab extends StatefulWidget {
  /// الحساب المحدّد حالياً (قد يكون null إن لم يُحدَّد بعد).
  final SasAccount? selected;

  /// يُستدعى عند تحديد/تعديل/إنشاء حساب من قسم «حسابات الساس» في الإعدادات،
  /// ليحدّث سياق الشِّل (الحساب النشط) فتُعاد بقية التبويبات بالحساب الجديد.
  final ValueChanged<SasAccount>? onSelectAccount;

  const SasSettingsTab({
    super.key,
    this.selected,
    this.onSelectAccount,
  });

  @override
  State<SasSettingsTab> createState() => _SasSettingsTabState();
}

class _SasSettingsTabState extends State<SasSettingsTab>
    with SingleTickerProviderStateMixin {
  final _api = SadaraApiService.instance;

  bool? _healthOk;
  bool _checking = false;

  /// وحدة التبويبات — يُحسب عددها في [initState] (الإشراف تبويب شرطي للأدمن).
  late final TabController _tabController;

  /// أوصاف التبويبات المُفعَّلة (مرتّبة) — يُبنى في [initState] حسب [_isAdmin].
  late final List<_SettingsTab> _tabs;

  /// هل المستخدم الحالي أدمن (CompanyAdmin/Admin/Manager)؟ لإظهار مدخل الإشراف.
  /// إخفاء المدخل تحسينٌ للتجربة فقط؛ الحماية النهائية في الخادم (يرد 403 لغيرهم).
  bool get _isAdmin => VpsAuthService.instance.currentUser?.isAdmin ?? false;

  @override
  void initState() {
    super.initState();
    _tabs = _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _checkHealth();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// يبني قائمة التبويبات المنطقية — الإشراف يُدرَج فقط للأدمن (تبويب شرطي).
  List<_SettingsTab> _buildTabs() {
    return <_SettingsTab>[
      _SettingsTab(
        label: 'عام',
        icon: Icons.tune_rounded,
        builder: () => [
          _section(
            title: 'الحساب',
            icon: Icons.badge_rounded,
            body: _accountCard(),
          ),
          _section(
            title: 'الخادم',
            icon: Icons.dns_rounded,
            gradient: AppTheme.greenGradient,
            body: _serverCard(),
          ),
          _section(
            title: 'حول الوحدة',
            icon: Icons.info_outline_rounded,
            body: _aboutCard(),
          ),
        ],
      ),
      _SettingsTab(
        label: 'حسابات الساس',
        icon: Icons.hub_rounded,
        builder: () => [
          _section(
            title: 'حسابات الساس',
            icon: Icons.hub_rounded,
            body: _sasAccountsCard(),
          ),
        ],
      ),
      _SettingsTab(
        label: 'التسعير والمحاسبة',
        icon: Icons.point_of_sale_rounded,
        builder: () => [
          _section(
            title: 'التسعير والمحاسبة',
            icon: Icons.point_of_sale_rounded,
            gradient: AppTheme.orangeGradient,
            body: _accountingCard(),
          ),
        ],
      ),
      _SettingsTab(
        label: 'الواتساب',
        icon: Icons.chat_rounded,
        builder: () => [
          _section(
            title: 'الواتساب',
            icon: Icons.chat_rounded,
            gradient: AppTheme.greenGradient,
            body: _whatsappCard(),
          ),
        ],
      ),
      _SettingsTab(
        label: 'أدوات',
        icon: Icons.build_rounded,
        builder: () => [
          _section(
            title: 'أدوات',
            icon: Icons.build_rounded,
            gradient: AppTheme.orangeGradient,
            body: _toolsCard(),
          ),
          _section(
            title: 'متقدّم — ميزات محفوظة',
            icon: Icons.inventory_2_rounded,
            note: Padding(
              padding: EdgeInsets.fromLTRB(4.w, 0, 4.w, 8.h),
              child: Text(
                'هذه القدرات محفوظة في الخادم للاستفادة منها لاحقاً — غير مفعّلة '
                'في واجهة الوكيل حالياً.',
                style: GoogleFonts.cairo(
                  fontSize: 12.sp,
                  color: Colors.grey[600],
                  height: 1.5,
                ),
              ),
            ),
            body: _preservedCard(),
          ),
        ],
      ),
      if (_isAdmin)
        _SettingsTab(
          label: 'الإشراف',
          icon: Icons.admin_panel_settings_rounded,
          builder: () => [
            _section(
              title: 'الإشراف',
              icon: Icons.admin_panel_settings_rounded,
              body: _adminCard(),
            ),
          ],
        ),
    ];
  }

  Future<void> _checkHealth() async {
    setState(() => _checking = true);
    bool ok;
    try {
      await _api.get('/server/health');
      ok = true;
    } catch (_) {
      ok = false;
    }
    if (mounted) {
      setState(() {
        _healthOk = ok;
        _checking = false;
      });
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  /// قسم = رأس أنيق + بطاقة محتواه، كوحدة واحدة متماسكة لتوزيعها على الأعمدة.
  Widget _section({
    required String title,
    required IconData icon,
    List<Color> gradient = AppTheme.blueGradient,
    Widget? note,
    required Widget body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SasSectionHeader(title: title, icon: icon, gradient: gradient),
        SizedBox(height: note != null ? 6.h : 10.h),
        if (note != null) note,
        body,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // البانر + شريط التبويبات ثابتان أعلى الشاشة؛ محتوى كل تبويب يُمرَّر مستقلاً.
        Padding(
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 0),
          child: SasContentWrap(maxWidth: 1180, child: _banner()),
        ),
        SizedBox(height: 12.h),
        SasContentWrap(maxWidth: 1180, child: _tabBar()),
        SizedBox(height: 4.h),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final t in _tabs) _tabContent(t.builder()),
            ],
          ),
        ),
      ],
    );
  }

  /// شريط تبويبات احترافي متجاوب (قابل للتمرير إن ضاق) بثيم الصدارة:
  /// مؤشّر بتدرّج أزرق، نص/أيقونة أبيض للمحدّد ورمادي (Slate) لغير المحدّد.
  Widget _tabBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 14.w),
      padding: EdgeInsets.all(5.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.16), width: 1.2),
        boxShadow: SasUi.cardShadow(),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        padding: EdgeInsets.zero,
        labelPadding: EdgeInsets.symmetric(horizontal: 4.w),
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: AppTheme.blueGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          boxShadow: SasUi.cardShadow(AppTheme.primaryColor),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle: GoogleFonts.cairo(fontSize: 13.sp, fontWeight: FontWeight.w800),
        unselectedLabelStyle:
            GoogleFonts.cairo(fontSize: 13.sp, fontWeight: FontWeight.w700),
        tabs: [
          for (final t in _tabs)
            Tab(
              height: 44.h,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(t.icon, size: 18.sp),
                    SizedBox(width: 7.w),
                    Text(t.label),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// محتوى تبويب: قائمة أقسامه قابلة للتمرير مستقلاً مع عرض محدود على العريض،
  /// وسحب-للتحديث يعيد فحص صحّة الخادم.
  Widget _tabContent(List<Widget> sections) {
    return RefreshIndicator(
      onRefresh: _checkHealth,
      child: SasContentWrap(
        maxWidth: 1180,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 28.h),
          children: [
            for (int i = 0; i < sections.length; i++) ...[
              if (i > 0) SizedBox(height: 20.h),
              sections[i],
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── الرأس ───────────────────────────

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
            child: Icon(Icons.settings_rounded, color: Colors.white, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إعدادات وكيل الساس',
                  style: GoogleFonts.cairo(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'الحساب · الخادم · الواتساب · أدوات · ميزات محفوظة',
                  maxLines: 1,
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

  // ─────────────────────────── بطاقة الحساب ───────────────────────────

  Widget _accountCard() {
    final u = VpsAuthService.instance.currentUser;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      decoration: SasUi.card(),
      child: Column(
        children: [
          _kvRow('المستخدم', u?.username ?? '—'),
          _divider(),
          _kvRow('الاسم', (u?.fullName.trim().isNotEmpty ?? false) ? u!.fullName : '—'),
          _divider(),
          _kvRow('الدور', _roleAr(u?.role ?? '')),
          if ((u?.phone ?? '').isNotEmpty) ...[
            _divider(),
            _kvRow('الهاتف', u!.phone!),
          ],
          if ((u?.department ?? '').isNotEmpty) ...[
            _divider(),
            _kvRow('القسم', u!.department!),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────── بطاقة الخادم ───────────────────────────

  Widget _serverCard() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kvRow('العنوان', SadaraApiService.baseUrl),
          _divider(),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h),
            child: Row(
              children: [
                _healthChip(),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _checking ? null : _checkHealth,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(
                        color: AppTheme.primaryColor.withValues(alpha: 0.40)),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(SasUi.radiusSm.r)),
                  ),
                  icon: _checking
                      ? SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.wifi_tethering_rounded, size: 18.sp),
                  label: Text('فحص الاتصال',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _healthChip() {
    final ok = _healthOk;
    if (ok == null) {
      return const SasStatusBadge(
        label: 'جارٍ الفحص…',
        color: Colors.grey,
        icon: Icons.hourglass_empty_rounded,
      );
    }
    return ok
        ? const SasStatusBadge(
            label: 'الخادم متصل',
            color: AppTheme.successColor,
            icon: Icons.check_circle_rounded,
          )
        : const SasStatusBadge(
            label: 'لا اتصال بالخادم',
            color: AppTheme.errorColor,
            icon: Icons.error_outline_rounded,
          );
  }

  // ─────────────────────────── حسابات الساس ───────────────────────────

  Widget _sasAccountsCard() {
    final acc = widget.selected;
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (acc != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
              child: Column(
                children: [
                  _kvRow('الحساب الفعّال', acc.displayName),
                  _divider(),
                  _kvRow('النوع', acc.accountType.labelAr),
                  _divider(),
                  _kvRow('الخادم', acc.serverUrl),
                  _divider(),
                  _kvRow('الحالة', acc.isActive ? 'مفعّل' : 'غير مفعّل',
                      valueColor: acc.isActive
                          ? AppTheme.successColor
                          : Colors.grey.shade600),
                ],
              ),
            )
          else
            Padding(
              padding: EdgeInsets.all(14.w),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.grey[500], size: 20.sp),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      'لم يُحدَّد حساب ساس بعد — اذهب لتبويب «الحسابات» لربط/تحديد حساب.',
                      style: GoogleFonts.cairo(
                          fontSize: 12.5.sp,
                          color: Colors.grey[700],
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          _tile(
            icon: Icons.manage_accounts_rounded,
            iconColor: AppTheme.primaryColor,
            title: 'إدارة حسابات الساس',
            subtitle: 'ربط · تعديل · حذف · اختبار · مزامنة · تحديد الحساب الفعّال',
            onTap: _openAccountsManager,
          ),
        ],
      ),
    );
  }

  /// يفتح شاشة إدارة حسابات الساس (ربط/تعديل/حذف/اختبار/مزامنة/تحديد) بثيم
  /// الصدارة؛ أي اختيار داخلها يُمرَّر لسياق الشِّل عبر [onSelectAccount] ليصبح
  /// الحساب النشط في الترويسة وبقية التبويبات.
  void _openAccountsManager() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _SasAccountsManagerScreen(
        selected: widget.selected,
        onSelect: (acc) => widget.onSelectAccount?.call(acc),
      ),
    ));
  }

  // ─────────────────────────── التسعير والمحاسبة ───────────────────────────

  Widget _accountingCard() {
    final acc = widget.selected;
    final disabledHint =
        acc == null ? 'حدّد حساب ساس أولاً من تبويب «الحسابات»' : null;
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _tile(
            icon: Icons.sell_rounded,
            iconColor: AppTheme.warningColor,
            title: 'أسعار الباقات',
            subtitle: disabledHint ??
                'تسعير كل باقة: الكلفة · سعر البيع · الربح المحسوب · التفعيل',
            onTap: acc == null
                ? null
                : () => _open(SasPackagePricesPage(account: acc)),
          ),
          const Divider(height: 1),
          _tile(
            icon: Icons.map_rounded,
            iconColor: AppTheme.accentColor,
            title: 'المناطق وأجور الصيانة',
            subtitle:
                'مناطق الشركة ومبلغ صيانة ثابت لكل منطقة يُطبَّق تلقائياً على مشتركيها',
            onTap: () => _open(const SasRegionsPage()),
          ),
          const Divider(height: 1),
          _tile(
            icon: Icons.insights_rounded,
            iconColor: AppTheme.successColor,
            title: 'تقرير الأرباح',
            subtitle:
                'أرباح الساس للشركة ضمن فترة — إجمالي وتفصيل حسب المنطقة والباقة',
            onTap: () => _open(const SasProfitsPage()),
          ),
          const Divider(height: 1),
          _tile(
            icon: Icons.account_balance_wallet_rounded,
            iconColor: AppTheme.errorColor,
            title: 'المدينون (ذمم المواطنين)',
            subtitle: disabledHint ??
                'المشتركون المدينون بالآجل — الرصيد المستحق وكشف الحساب والتسديد',
            onTap: acc == null
                ? null
                : () => _open(SasDebtorsPage(account: acc)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── الواتساب ───────────────────────────

  Widget _whatsappCard() {
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _tile(
            icon: Icons.settings_suggest_rounded,
            iconColor: AppTheme.successColor,
            title: 'إعدادات الواتساب',
            subtitle: 'وضع الإرسال (تطبيق/خادم محلي/Meta) وضبط الاتصال',
            onTap: () => _open(const WaSettingsScreen()),
          ),
          const Divider(height: 1),
          _tile(
            icon: Icons.description_rounded,
            iconColor: AppTheme.infoColor,
            title: 'قوالب الرسائل',
            subtitle: 'قوالب التذكير/التجديد القابلة للتعديل بالمتغيّرات',
            onTap: () => _open(const WaTemplatesScreen()),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── أدوات ───────────────────────────

  Widget _toolsCard() {
    final acc = widget.selected;
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // مستكشف الساس المتقدّم — أداة اكتشاف/أمن للمسؤول فقط (الباكند محصور بالمسؤول أيضاً).
          if (_isAdmin) ...[
            _tile(
              icon: Icons.travel_explore_rounded,
              iconColor: AppTheme.infoColor,
              title: 'مستكشف الساس المتقدّم (للمسؤول)',
              subtitle: acc == null
                  ? 'حدّد حساباً أولاً لفتح المستكشف'
                  : 'التقاط وفكّ تشفير طلبات SAS4 + كتالوج API + تحليل البنية والأمان',
              onTap: acc == null
                  ? null
                  : () => _open(SasExplorerPage(account: acc)),
            ),
            const Divider(height: 1),
          ],
          _tile(
            icon: Icons.maps_home_work_rounded,
            iconColor: AppTheme.warningColor,
            title: 'العقارات (العنوان الوطني)',
            subtitle: 'إدارة العقارات وربط الاشتراكات بالعنوان الوطني NPN',
            onTap: () => _open(const PremisesListScreen()),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── الإشراف (أدمن فقط) ───────────────────────────

  Widget _adminCard() {
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: _tile(
        icon: Icons.groups_2_rounded,
        iconColor: AppTheme.primaryColor,
        title: 'إدارة الوكلاء (للمشرفين)',
        subtitle:
            'البلنك الموحّد — وكلاء الشركة وحساباتهم ومقاطعتها (تصريح/فعلي/فارق/حكم)',
        onTap: () => _open(const SasAdminAgentsPage()),
      ),
    );
  }

  // ─────────────────────────── متقدّم — ميزات محفوظة ───────────────────────────

  Widget _preservedCard() {
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < _preserved.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _preservedTile(_preserved[i]),
          ],
        ],
      ),
    );
  }

  Widget _preservedTile(_Feature f) {
    return ListTile(
      leading: Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(11.r),
        ),
        child: Icon(f.icon, color: Colors.grey[500], size: 20.sp),
      ),
      title: Text(f.title,
          style: GoogleFonts.cairo(
              fontSize: 13.5.sp, fontWeight: FontWeight.w800)),
      subtitle: Text(f.desc,
          style: GoogleFonts.cairo(fontSize: 11.5.sp, color: Colors.grey[600])),
      trailing: const SasStatusBadge(
        label: 'محفوظ',
        color: Colors.grey,
        icon: Icons.inventory_2_rounded,
      ),
      onTap: () => _showPreservedInfo(f),
    );
  }

  void _showPreservedInfo(_Feature f) {
    showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(children: [
            Icon(f.icon, color: AppTheme.primaryColor),
            SizedBox(width: 8.w),
            Expanded(
                child: Text(f.title,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800))),
          ]),
          content: Text(
            '${f.desc}\n\nهذه الميزة محفوظة في الخادم (لم تُحذف) وستُفعَّل في '
            'واجهة الوكيل عند الحاجة لاحقاً.',
            style: GoogleFonts.cairo(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text('حسناً', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── حول ───────────────────────────

  Widget _aboutCard() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('وحدة وكيل الساس — منصّة الصدارة',
              style: GoogleFonts.cairo(
                  fontSize: 14.sp, fontWeight: FontWeight.w800)),
          SizedBox(height: 6.h),
          Text(
            'إدارة عمل الوكيل عبر نظام الساس الخاص بمزوّده — مشتركون · نظام · '
            'تجديد · تقارير · تصريح (بلنك) · تذاكر · عقارات — عبر بوّابة الصدارة '
            'الآمنة (عزل ثلاثي: شركة + مالك + صلاحية).',
            style: GoogleFonts.cairo(
                fontSize: 12.sp, color: Colors.grey[600], height: 1.6),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────── مساعدات عرض ───────────────────────────

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return ListTile(
      enabled: enabled,
      leading: Container(
        width: 40.w,
        height: 40.w,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11.r),
        ),
        child: Icon(icon, color: iconColor, size: 20.sp),
      ),
      title: Text(title,
          style: GoogleFonts.cairo(
              fontSize: 13.5.sp, fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle,
          style: GoogleFonts.cairo(fontSize: 11.5.sp, color: Colors.grey[600])),
      trailing: Icon(Icons.chevron_left_rounded,
          size: 20.sp, color: enabled ? Colors.grey[500] : Colors.grey[300]),
      onTap: onTap,
    );
  }

  Widget _kvRow(String label, String value, {Color? valueColor}) {
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
                    color: valueColor ?? AppTheme.primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.grey.withValues(alpha: 0.10));

  static String _roleAr(String r) {
    switch (r.toLowerCase()) {
      case 'admin':
        return 'مدير';
      case 'operator':
        return 'مشغّل';
      case 'agent':
        return 'وكيل';
      default:
        return r.isEmpty ? '—' : r;
    }
  }
}

/// شاشة مستقلّة تستضيف [SasAccountsPage] (إدارة حسابات الساس) بثيم الصدارة —
/// تُفتح من بطاقة «حسابات الساس» في الإعدادات بعد نقل تبويب «الحسابات» إليها.
///
/// تحتفظ بالحساب المحدَّد محلياً للتظليل، وتُمرّر كل اختيار لسياق الشِّل عبر
/// [onSelect] ليصبح الحساب النشط في الترويسة وبقية التبويبات فوراً.
class _SasAccountsManagerScreen extends StatefulWidget {
  final SasAccount? selected;
  final ValueChanged<SasAccount> onSelect;

  const _SasAccountsManagerScreen({
    required this.selected,
    required this.onSelect,
  });

  @override
  State<_SasAccountsManagerScreen> createState() =>
      _SasAccountsManagerScreenState();
}

class _SasAccountsManagerScreenState
    extends State<_SasAccountsManagerScreen> {
  late SasAccount? _selected = widget.selected;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
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
          title: Text('حسابات الساس',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, fontSize: 17.sp)),
        ),
        body: SasAccountsPage(
          selected: _selected,
          onSelect: (acc) {
            setState(() => _selected = acc);
            widget.onSelect(acc);
          },
        ),
      ),
    );
  }
}

/// وصف تبويب في شاشة الإعدادات — عنوان وأيقونة ومُنشئ أقسامه (يُبنى كسولاً عند
/// عرض التبويب فيلتقط أحدث حالة: الحساب المحدّد وصحّة الخادم).
class _SettingsTab {
  final String label;
  final IconData icon;
  final List<Widget> Function() builder;
  const _SettingsTab({
    required this.label,
    required this.icon,
    required this.builder,
  });
}

/// وصف ميزة محفوظة (مؤجّلة) تُعرَض كمدخل غير مفعّل.
class _Feature {
  final String title;
  final String desc;
  final IconData icon;
  const _Feature(this.title, this.desc, this.icon);
}

/// قدرات المنصّة المحفوظة في الخادم (تُعرَض كمداخل مؤجّلة — لا تُحذف).
const List<_Feature> _preserved = [
  _Feature('إدارة أجهزة OLT', 'الاتصال بأجهزة Huawei OLT عبر SSH/Telnet وإدارتها.',
      Icons.dns_rounded),
  _Feature('المراقبة اللحظية',
      'مراقبة دورية للقياسات والقدرة الضوئية مع تنبيهات.', Icons.monitor_heart_rounded),
  _Feature('التزويد التلقائي (FTTH)',
      'تدفّقات تزويد المشتركين وتسلسل الأوامر الآمن.', Icons.electrical_services_rounded),
  _Feature('SNMP والإنذارات',
      'استقبال Traps والاستعلام عبر OID وربطها بالتنبيهات.', Icons.notifications_active_rounded),
  _Feature('التشخيص الذكي',
      'محرك تشخيص بالقواعد الخبيرة من أدلة HCIA/HCIP.', Icons.medical_services_rounded),
  _Feature('اللوحة الوطنية والحوكمة',
      'صور اللوحة الوطنية وطبقات GIS والحوكمة.', Icons.map_rounded),
  _Feature('العبور و DFOS',
      'شبكات العبور ومراقبة الألياف DFOS.', Icons.account_tree_rounded),
  _Feature('المساعد الذكي (AI)',
      'مساعد ذكاء اصطناعي هجين للدعم الفني.', Icons.smart_toy_rounded),
];
