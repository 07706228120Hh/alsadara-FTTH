import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../permissions/permission_gate.dart';
import '../theme/app_theme.dart';
import 'models/sas_account.dart';
import 'pages/sas_accounts_page.dart';
import 'pages/sas_dashboard_tab.dart';
import 'pages/sas_renewal_tab.dart';
import 'pages/sas_report_tab.dart';
import 'pages/sas_subscribers_tab.dart';
import 'pages/sas_system_tab.dart';
import 'pages/sas_tickets_tab.dart';
import 'widgets/sas_state_views.dart';

/// صفحة «وكيل الساس» — شل بتبويبات يعمل على بوّابة الصدارة `/api/sas-agent/*`.
///
/// التبويبات: حسابات · لوحة · مشتركون · نظام الساس · تجديد · تصريح/بلنك · تذاكر.
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

  static const _tabs = <_TabDef>[
    _TabDef('الحسابات', Icons.link_rounded),
    _TabDef('لوحة', Icons.dashboard_rounded),
    _TabDef('مشتركون', Icons.people_rounded),
    _TabDef('نظام الساس', Icons.dns_rounded),
    _TabDef('تجديد', Icons.autorenew_rounded),
    _TabDef('تصريح/بلنك', Icons.assignment_rounded),
    _TabDef('تذاكر', Icons.confirmation_number_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _onSelect(SasAccount acc) {
    if (_selected?.id == acc.id) return;
    setState(() => _selected = acc);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('صفحة وكيل الساس',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800, fontSize: 17.sp)),
              if (_selected != null)
                Text(
                  _selected!.displayName,
                  style: GoogleFonts.cairo(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70),
                ),
            ],
          ),
          bottom: TabBar(
            controller: _tab,
            isScrollable: true,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13.sp),
            unselectedLabelStyle: GoogleFonts.cairo(fontSize: 13.sp),
            tabs: [
              for (final t in _tabs)
                Tab(
                  height: 46.h,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon, size: 16.sp),
                      SizedBox(width: 6.w),
                      Text(t.label),
                    ],
                  ),
                ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tab,
          children: [
            // 1) الحسابات
            SasAccountsPage(selected: _selected, onSelect: _onSelect),
            // 2) لوحة
            _needsAccount(
              (acc) => SasDashboardTab(account: acc, key: ValueKey('dash-${acc.id}')),
            ),
            // 3) مشتركون
            _needsAccount(
              (acc) => SasSubscribersTab(account: acc, key: ValueKey('subs-${acc.id}')),
            ),
            // 4) نظام الساس (باقات + مالية + صحّة)
            _needsAccount(
              (acc) => SasSystemTab(account: acc, key: ValueKey('sys-${acc.id}')),
            ),
            // 5) تجديد (مرشّحون + معاينة dryRun → تنفيذ)
            _needsAccount(
              (acc) =>
                  SasRenewalTab(account: acc, key: ValueKey('renew-${acc.id}')),
            ),
            // 6) تصريح/بلنك (تقرير الوكيل)
            _needsAccount(
              (acc) =>
                  SasReportTab(account: acc, key: ValueKey('report-${acc.id}')),
            ),
            // 7) تذاكر (إعادة استخدام نظام الدعم القائم)
            const SasTicketsTab(),
          ],
        ),
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
        action: OutlinedButton.icon(
          onPressed: () => _tab.animateTo(0),
          icon: const Icon(Icons.link_rounded),
          label: Text('الذهاب للحسابات', style: GoogleFonts.cairo()),
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
