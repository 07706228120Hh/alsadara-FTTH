import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:platform_core/platform_core.dart';
import 'screens/admin_agents_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/subscribers_screen.dart';

/// تطبيق الوكلاء — منتج مستقل. يدخل به:
///  • وكيل (حساب بنطاق company_id + agent) → واجهة الوكيل (لوحته · مشتركوه · SAS · تذاكره · تصريحه).
///  • أدمن مبيّت (حساب موظّف بدور admin/operator) → واجهة الأدمن (إدارة الوكلاء وإصدار حساباتهم · التذاكر).
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Session.restore();
  await ThemeController.instance.restore();
  runApp(const AgentsApp());
}

class AgentsApp extends StatefulWidget {
  const AgentsApp({super.key});
  @override
  State<AgentsApp> createState() => _AgentsAppState();
}

class _AgentsAppState extends State<AgentsApp> {
  final api = StaffApi();
  int _epoch = 0; // يُعاد بناء الشجرة عند الدخول/الخروج

  void _refresh() => setState(() => _epoch++);

  bool get _isAgent => Session.loggedIn && Session.kind == AccountKind.agent;
  // أدمن مبيّت: حساب موظّف (ليس مشتركاً ولا وكيلاً) بدور مشغّل/مدير.
  bool get _isAdmin =>
      Session.loggedIn &&
      Session.kind != AccountKind.subscriber &&
      Session.kind != AccountKind.agent &&
      Session.isOperator;

  @override
  Widget build(BuildContext context) {
    final Widget home;
    if (_isAgent) {
      home = _AgentHome(api: api, onLoggedOut: _refresh);
    } else if (_isAdmin) {
      home = _AdminHome(api: api, onLoggedOut: _refresh);
    } else if (Session.loggedIn) {
      home = _UnsupportedAccount(onLoggedOut: _refresh);
    } else {
      home = StaffLoginScreen(
        api: api,
        brand: AppBrand.agents,
        hint: 'ادخل بحساب الوكيل أو حساب الأدمن',
        onLoggedIn: _refresh,
      );
    }
    return PlatformApp(
      brand: AppBrand.agents,
      home: KeyedSubtree(key: ValueKey(_epoch), child: home),
    );
  }
}

/// واجهة الوكيل.
class _AgentHome extends StatelessWidget {
  final StaffApi api;
  final VoidCallback onLoggedOut;
  const _AgentHome({required this.api, required this.onLoggedOut});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      brand: AppBrand.agents,
      onLoggedOut: onLoggedOut,
      tabs: [
        ShellTab(
          label: 'لوحتي',
          icon: PhosphorIconsRegular.squaresFour,
          selectedIcon: PhosphorIconsFill.squaresFour,
          builder: () => DashboardScreen(api: api, onLoggedOut: onLoggedOut),
        ),
        ShellTab(
          label: 'مشتركيّ',
          icon: PhosphorIconsRegular.usersThree,
          selectedIcon: PhosphorIconsFill.usersThree,
          builder: () => AgentSubscribersScreen(api: api),
        ),
        ShellTab(
          label: 'نظام SAS',
          icon: PhosphorIconsRegular.database,
          selectedIcon: PhosphorIconsFill.database,
          builder: () => Session.companyId == null
              ? const Center(child: Text('لا شركة مرتبطة بهذا الحساب'))
              : SasSection(api: api, companyId: Session.companyId!, isAgent: true),
        ),
        ShellTab(
          label: 'التقارير',
          icon: PhosphorIconsRegular.chartBar,
          selectedIcon: PhosphorIconsFill.chartBar,
          builder: () => Session.companyId == null
              ? const Center(child: Text('لا شركة مرتبطة بهذا الحساب'))
              : SasReportsHub(api: api, cid: Session.companyId!),
        ),
        ShellTab(
          label: 'التذاكر',
          icon: PhosphorIconsRegular.ticket,
          selectedIcon: PhosphorIconsFill.ticket,
          builder: () => TicketsScreen(api: api, canEscalate: false, title: 'تذاكر مشتركيّ'),
        ),
        ShellTab(
          label: 'تصريحي',
          icon: PhosphorIconsRegular.scales,
          selectedIcon: PhosphorIconsFill.scales,
          builder: () => ReportScreen(api: api),
        ),
        ShellTab(
          label: 'الإعدادات',
          icon: PhosphorIconsRegular.gear,
          selectedIcon: PhosphorIconsFill.gear,
          builder: () => SettingsScreen(api: api),
        ),
      ],
    );
  }
}

/// واجهة الأدمن المبيّت — إدارة الوكلاء وإصدار حساباتهم + التذاكر.
class _AdminHome extends StatelessWidget {
  final StaffApi api;
  final VoidCallback onLoggedOut;
  const _AdminHome({required this.api, required this.onLoggedOut});

  @override
  Widget build(BuildContext context) {
    return AppShell(
      brand: AppBrand.agents,
      onLoggedOut: onLoggedOut,
      tabs: [
        ShellTab(
          label: 'الوكلاء',
          icon: PhosphorIconsRegular.briefcase,
          selectedIcon: PhosphorIconsFill.briefcase,
          builder: () => AdminAgentsScreen(api: api),
        ),
        ShellTab(
          label: 'التذاكر',
          icon: PhosphorIconsRegular.ticket,
          selectedIcon: PhosphorIconsFill.ticket,
          builder: () => TicketsScreen(api: api, canEscalate: true, title: 'التذاكر'),
        ),
        ShellTab(
          label: 'الإعدادات',
          icon: PhosphorIconsRegular.gear,
          selectedIcon: PhosphorIconsFill.gear,
          builder: () => SettingsScreen(api: api),
        ),
      ],
    );
  }
}

/// حساب موظّف لكنه بلا صلاحية كافية لهذا التطبيق (ليس وكيلاً ولا أدمن).
class _UnsupportedAccount extends StatelessWidget {
  final VoidCallback onLoggedOut;
  const _UnsupportedAccount({required this.onLoggedOut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(PhosphorIconsDuotone.warningCircle, size: 48),
            const SizedBox(height: 12),
            const Text(
              'هذا الحساب لا يملك صلاحية الدخول إلى تطبيق الوكلاء.\n'
              'ادخل بحساب وكيل، أو بحساب أدمن (دور مدير/مشغّل).',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            LogoutButton(onLoggedOut: onLoggedOut),
          ]),
        ),
      ),
    );
  }
}
