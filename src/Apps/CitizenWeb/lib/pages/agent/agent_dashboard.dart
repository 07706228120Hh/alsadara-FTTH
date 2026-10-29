import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:sadara_design/sadara_design.dart';
import '../../providers/agent_auth_provider.dart';
import '../../services/agent_api_service.dart';

/// لوحة تحكّم الوكيل — موحّدة على نظام تصميم الصدارة (3D).
class AgentDashboard extends StatefulWidget {
  const AgentDashboard({super.key});
  @override
  State<AgentDashboard> createState() => _AgentDashboardState();
}

class _AgentDashboardState extends State<AgentDashboard> {
  AgentData? _agent;
  AgentAccountingSummaryData? _summary;

  @override
  void initState() {
    super.initState();
    _agent = context.read<AgentAuthProvider>().agent;
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AgentAuthProvider>();
    try {
      final s = await auth.getAccountingSummary();
      if (mounted) setState(() => _summary = s);
    } catch (_) {}
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'صباح الخير';
    if (h < 17) return 'مساء الخير';
    return 'مساء النور';
  }

  static String fmt(num n) {
    final s = n.round().abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return (n < 0 ? '-' : '') + b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final charges = _summary?.totalCharges ?? _agent?.totalCharges ?? 0;
    final payments = _summary?.totalPayments ?? _agent?.totalPayments ?? 0;
    final net = _summary?.netBalance ?? _agent?.netBalance ?? 0;
    final maxv = (charges > payments ? charges : payments);

    return SdPage(
      appBar: SdAppBar(
        title: '${_greeting()}، ${_agent?.name ?? 'الوكيل'}',
        subtitle: 'كود الوكيل: ${_agent?.agentCode ?? '—'}',
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'تسجيل الخروج',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await context.read<AgentAuthProvider>().logout();
              if (context.mounted) context.go('/');
            },
          ),
        ],
      ),
      bottomBar: const _AgentNav(active: 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _balanceHero(net, charges, payments),
          const SizedBox(height: SdSpace.lg),
          const SdSectionHeader(title: 'مؤشّرات الحساب'),
          const SizedBox(height: SdSpace.sm),
          Row(
            children: [
              Expanded(
                child: SdStatPedestal(
                  value: charges,
                  max: maxv,
                  label: 'إجمالي الشحن',
                  caption: 'د.ع',
                  group: SdGroup.field,
                ),
              ),
              const SizedBox(width: SdSpace.sm),
              Expanded(
                child: SdStatPedestal(
                  value: payments,
                  max: maxv,
                  label: 'إجمالي التسديد',
                  caption: 'د.ع',
                  group: SdGroup.admin,
                ),
              ),
            ],
          ),
          const SizedBox(height: SdSpace.lg),
          const SdSectionHeader(title: 'إجراءات سريعة'),
          const SizedBox(height: SdSpace.sm),
          SdTileGrid(
            phoneColumns: 2,
            maxColumns: 4,
            children: [
              _tile(
                context,
                icon: Icons.cell_tower_rounded,
                title: 'تفعيل مشترك',
                subtitle: 'اشتراك • تجديد',
                tone: SdStatus.success.tone,
                route: '/agent/activate',
              ),
              _tile(
                context,
                icon: Icons.credit_card_rounded,
                title: 'شحن ماستر',
                subtitle: 'تعبئة بطاقة',
                group: SdGroup.platform,
                route: '/agent/master-recharge',
              ),
              _tile(
                context,
                icon: Icons.account_balance_wallet_rounded,
                title: 'طلب رصيد',
                subtitle: 'شحن حسابك',
                tone: SdStatus.warning.tone,
                route: '/agent/balance-request',
              ),
              _tile(
                context,
                icon: Icons.receipt_rounded,
                title: 'سداد مديونية',
                subtitle: 'تسديد نقدي',
                tone: SdStatus.danger.tone,
                route: '/agent/debt-payment',
              ),
            ],
          ),
          const SizedBox(height: SdSpace.lg),
          SdSectionHeader(
            title: 'آخر العمليات',
            trailing: TextButton(
              onPressed: () => context.go('/agent/transactions'),
              child: const Text('عرض الكل'),
            ),
          ),
          const SizedBox(height: SdSpace.sm),
          SdRaised(
            onTap: () => context.go('/agent/transactions'),
            radius: SdRadius.lg,
            child: Row(
              children: [
                SdIconCube(
                  icon: Icons.swap_vert_rounded,
                  group: SdGroup.admin,
                  size: 44,
                ),
                const SizedBox(width: SdSpace.sm),
                Expanded(
                  child: Text(
                    'سجل العمليات والحركات المالية',
                    style: SdText.label,
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: SdColors.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceHero(num net, num charges, num payments) {
    return SdRaised(
      radius: SdRadius.xl,
      depth: SdDepth.hero,
      padding: const EdgeInsets.all(SdSpace.lg),
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [SdColors.primaryEdge, SdColors.primaryLight],
      ),
      edgeColor: SdColors.primaryEdge,
      glowColor: const Color(0x80132A5E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الرصيد الصافي',
            style: TextStyle(
              fontFamily: SdText.family,
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${fmt(net)} د.ع',
            style: const TextStyle(
              fontFamily: SdText.family,
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: SdSpace.md),
          Row(
            children: [
              _mini(fmt(charges), 'إجمالي الشحن'),
              const SizedBox(width: SdSpace.sm),
              _mini(fmt(payments), 'إجمالي التسديد'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SdRadius.sm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: SdText.family,
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontFamily: SdText.family,
              color: Colors.white70,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    SdTone? tone,
    SdGroup group = SdGroup.admin,
    required String route,
  }) {
    return SdRaised(
      onTap: () => context.go(route),
      tilt: true,
      radius: SdRadius.lg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: Row(
        children: [
          SdIconCube(icon: icon, tone: tone, group: group, size: 46),
          const SizedBox(width: SdSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SdText.titleSm.copyWith(fontSize: 14.5),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SdText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentNav extends StatelessWidget {
  const _AgentNav({required this.active});
  final int active;
  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.home_rounded, 'الرئيسية', '/agent/home'),
      (Icons.swap_vert_rounded, 'العمليات', '/agent/transactions'),
      (Icons.bar_chart_rounded, 'التقارير', '/agent/reports'),
      (Icons.settings_rounded, 'الإعدادات', '/agent/settings'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        border: SdOutline.all,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0B1B3F),
            blurRadius: 18,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _item(context, items[i].$1, items[i].$2, items[i].$3, i == active),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    IconData icon,
    String label,
    String route,
    bool on,
  ) {
    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(SdRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: on
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [SdColors.primaryMid, SdColors.primary],
                      )
                    : null,
                color: on ? null : SdColors.surfaceAlt,
                borderRadius: BorderRadius.circular(SdRadius.sm),
                border: on
                    ? Border.all(color: SdColors.goldLight, width: 1)
                    : null,
              ),
              child: Icon(
                icon,
                size: 18,
                color: on ? Colors.white : SdColors.muted,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: on ? SdColors.primary : SdColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
