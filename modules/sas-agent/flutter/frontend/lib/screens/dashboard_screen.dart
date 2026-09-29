import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:platform_core/platform_core.dart';

import 'renewal_screen.dart';

/// لوحة الوكيل: بطاقته من SAS + مشتركوه + تذاكره + حالة تصريحه.
class DashboardScreen extends StatefulWidget {
  final StaffApi api;
  final VoidCallback onLoggedOut;
  const DashboardScreen({super.key, required this.api, required this.onLoggedOut});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  PortalSummary? _s;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.summary();
      if (mounted) setState(() { _s = s; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  void _openRenewal(String win) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => RenewalScreen(api: widget.api, initialWindow: win)))
        .then((_) => _load());     // حدّث اللوحة بعد أي تجديد
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return TabPage(
      title: 'لوحة الوكيل',
      subtitle: Session.user ?? '',
      onRefresh: _load,
      maxWidth: 1280,
      actions: [LogoutButton(onLoggedOut: widget.onLoggedOut)],
      child: s == null
          ? (_error != null ? ErrorView(_error!, onRetry: _load) : const SkeletonDashboard())
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 760;
              final pad = wide ? 24.0 : 14.0;
              Widget pair(Widget a, Widget b) => wide
                  ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: a), const SizedBox(width: 14), Expanded(child: b)]))
                  : Column(children: [a, const SizedBox(height: 14), b]);
              return ListView(padding: EdgeInsets.fromLTRB(pad, 8, pad, 40), children: [
                FadeSlide(child: pair(_agentCard(context, s), _balanceCard(context, s))),
                const SectionTitle('مشتركيّ', subtitle: 'من بيانات SAS آخر مزامنة'),
                FadeSlide(
                  delay: const Duration(milliseconds: 60),
                  child: StatGrid([
                    StatTile(label: 'إجمالي مشتركيّ (SAS)', value: Fmt.n(s.agent?.usersCount ?? s.subscribers.total),
                        icon: PhosphorIconsDuotone.usersThree, color: context.pal.accent),
                    StatTile(label: 'نشط', value: Fmt.n(s.subscribers.active), icon: PhosphorIconsDuotone.checkCircle,
                        color: context.pal.success, sub: '${Fmt.pct(s.subscribers.active, s.subscribers.total)} من الإجمالي'),
                    StatTile(label: 'منتهٍ', value: Fmt.n(s.subscribers.expired), icon: PhosphorIconsDuotone.clockCountdown,
                        color: context.pal.danger, sub: '${Fmt.pct(s.subscribers.expired, s.subscribers.total)} من الإجمالي'),
                    StatTile(label: 'متّصل الآن', value: Fmt.n(s.subscribers.online), icon: PhosphorIconsDuotone.wifiHigh,
                        color: context.pal.info),
                  ]),
                ),
                if (s.expiry.any) ...[
                  const SectionTitle('قرب الانتهاء — التجديد', subtitle: 'اضغط أي بطاقة لفتح التجديد الجماعي'),
                  StatGrid([
                    StatTile(label: 'منتهٍ', value: Fmt.n(s.expiry.overdue), icon: PhosphorIconsDuotone.warningCircle,
                        color: context.pal.danger, onTap: () => _openRenewal('overdue')),
                    StatTile(label: 'ينتهي اليوم', value: Fmt.n(s.expiry.today), icon: PhosphorIconsDuotone.clock,
                        color: context.pal.warning, onTap: () => _openRenewal('today')),
                    StatTile(label: 'خلال ٣ أيام', value: Fmt.n(s.expiry.soon3), icon: PhosphorIconsDuotone.clockCountdown,
                        color: context.pal.warning, onTap: () => _openRenewal('soon3')),
                    StatTile(label: 'خلال أسبوع', value: Fmt.n(s.expiry.soon7), icon: PhosphorIconsDuotone.calendarPlus,
                        color: context.pal.info, onTap: () => _openRenewal('soon7')),
                  ]),
                ],
                const SizedBox(height: 14),
                FadeSlide(
                  delay: const Duration(milliseconds: 120),
                  child: wide
                      ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: _ringCard(context, s)),
                          const SizedBox(width: 14),
                          Expanded(child: _ticketsCard(context, s)),
                          const SizedBox(width: 14),
                          Expanded(child: _reportCard(context, s)),
                        ]))
                      : Column(children: [
                          _ringCard(context, s), const SizedBox(height: 14),
                          _ticketsCard(context, s), const SizedBox(height: 14),
                          _reportCard(context, s),
                        ]),
                ),
              ]);
            }),
    );
  }

  Widget _cardTitle(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14.5)),
      );

  Widget _agentCard(BuildContext context, PortalSummary s) {
    final pal = context.pal;
    final tt = Theme.of(context).textTheme;
    final enabled = s.agent?.enabled != false;
    return GlowCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFD97706)]),
              boxShadow: Elev.glow(const Color(0xFFFBBF24), 0.3),
            ),
            child: const Icon(PhosphorIconsDuotone.briefcase, color: PlatformPalette.onPrimaryInk, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.agent?.name ?? Session.agent, style: tt.titleLarge?.copyWith(fontSize: 19)),
              const SizedBox(height: 2),
              Text('@${s.agent?.username ?? Session.agent} · ${s.company?.name ?? ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: pal.textMuted)),
            ]),
          ),
          StatusChip(enabled ? 'فعّال' : 'موقوف', color: enabled ? pal.success : pal.danger),
        ]),
        if ((s.agent?.parentUsername ?? '').isNotEmpty) ...[
          const SizedBox(height: 16),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'الوكيل الأعلى: ', style: TextStyle(color: pal.textMuted, fontSize: 12.5)),
            TextSpan(text: s.agent!.parentUsername, style: PlatformType.mono(size: 12.5, color: pal.text)),
          ])),
        ],
      ]),
    );
  }

  Widget _balanceCard(BuildContext context, PortalSummary s) {
    final pal = context.pal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(PhosphorIconsDuotone.wallet, color: pal.accent, size: 19),
            const SizedBox(width: 8),
            Expanded(child: Text('الرصيد لدى الشركة', style: TextStyle(color: pal.textMuted, fontSize: 13))),
            Text('د.ع', style: TextStyle(color: pal.textMuted, fontSize: 11)),
          ]),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(Fmt.n(s.agent?.balance ?? 0), style: PlatformType.display(size: 40, color: pal.text)),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: pal.outline))),
            child: Row(children: [
              Icon(PhosphorIconsDuotone.star, color: pal.accent, size: 15),
              const SizedBox(width: 6),
              Expanded(child: Text('نقاط المكافآت', style: TextStyle(color: pal.textMuted, fontSize: 12.5))),
              Text(Fmt.n(s.agent?.rewardPoints ?? 0), style: PlatformType.num(size: 13, color: pal.text)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _ringCard(BuildContext context, PortalSummary s) {
    final pal = context.pal;
    final total = s.subscribers.total;
    final f = total == 0 ? 0.0 : s.subscribers.active / total;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardTitle(context, 'توزيع الاشتراكات'),
          Row(children: [
            DonutRing(
              fraction: f,
              color: pal.success,
              rest: pal.danger,
              centerValue: Fmt.pct(s.subscribers.active, total),
              centerLabel: 'نشط',
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(children: [
                LegendRow(color: pal.success, label: 'نشط', value: Fmt.n(s.subscribers.active)),
                LegendRow(color: pal.danger, label: 'منتهٍ', value: Fmt.n(s.subscribers.expired)),
                LegendRow(color: pal.info, label: 'متّصل الآن', value: Fmt.n(s.subscribers.online)),
              ]),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _ticketsCard(BuildContext context, PortalSummary s) {
    final pal = context.pal;
    Widget box(IconData icon, Color color, int n, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 14),
              Text(Fmt.n(n), style: PlatformType.display(size: 30, color: pal.text)),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 12)),
            ]),
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardTitle(context, 'التذاكر'),
          Row(children: [
            box(PhosphorIconsDuotone.ticket, s.tickets.openTotal > 0 ? pal.danger : pal.textMuted, s.tickets.openTotal, 'مفتوحة تحتاج معالجة'),
            const SizedBox(width: 10),
            box(PhosphorIconsDuotone.checkSquare, pal.success, s.tickets.byStatus['resolved'] ?? 0, 'محلولة'),
          ]),
        ]),
      ),
    );
  }

  Widget _reportCard(BuildContext context, PortalSummary s) {
    final pal = context.pal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _cardTitle(context, 'الرصيد والتصريح'),
          KVRow('نقاط المكافآت', Fmt.n(s.agent?.rewardPoints ?? 0)),
          if (s.lastReport == null)
            KVRow('آخر تصريح', 'لم تُصرّح بعد — من تبويب «تصريحي»', color: pal.warning)
          else ...[
            KVRow('آخر تصريح', '${Fmt.n(s.lastReport!.declaredTotal)} مشترك (${Fmt.n(s.lastReport!.declaredActive)} نشط)'),
            KVRow('بتاريخ', Fmt.dateTime(s.lastReport!.ts)),
            KVRow('ما تُظهره SAS', Fmt.n(s.agent?.usersCount ?? 0),
                color: (s.agent?.usersCount ?? 0) == s.lastReport!.declaredTotal ? pal.success : pal.warning),
          ],
        ]),
      ),
    );
  }
}
