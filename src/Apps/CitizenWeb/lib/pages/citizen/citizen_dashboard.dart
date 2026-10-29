import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';
import '../../providers/auth_provider.dart';

/// لوحة تحكّم المواطن — مبنيّة بالكامل على نظام تصميم الصدارة الموحّد (3D).
class CitizenDashboard extends StatelessWidget {
  const CitizenDashboard({super.key});

  // نبرة تركوازية مخصّصة لخدمات الإنترنت (الفايبر) — من ألوان النظام الموحّد.
  static const SdTone _net = SdTone(
    light: SdColors.accentGlow,
    base: SdColors.accent,
    edge: SdColors.accentEdge,
    tint: SdColors.accentTint,
    tintEdge: SdColors.accentTintEdge,
    text: SdColors.accentEdge,
  );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = auth.citizen?.fullName ?? 'مستخدم';

    return SdPage(
      appBar: SdAppBar(
        title: 'مرحباً، $name',
        subtitle: 'منصة الصدارة',
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'الإشعارات',
            icon: const Icon(Icons.notifications_rounded),
            onPressed: () => context.go('/citizen/notifications'),
          ),
          IconButton(
            tooltip: 'حسابي',
            icon: const Icon(Icons.person_rounded),
            onPressed: () => context.go('/citizen/profile'),
          ),
        ],
      ),
      bottomBar: _BottomNav(active: 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _subscriptionHero(context),
          const SizedBox(height: SdSpace.lg),
          const SdSectionHeader(title: 'خدمات سريعة'),
          const SizedBox(height: SdSpace.sm),
          _services(context),
          const SizedBox(height: SdSpace.lg),
          SdSectionHeader(
            title: 'آخر الطلبات',
            trailing: TextButton(
              onPressed: () => context.go('/citizen/requests'),
              child: const Text('عرض الكل'),
            ),
          ),
          const SizedBox(height: SdSpace.sm),
          ..._recentRequests(context),
        ],
      ),
    );
  }

  // ── بطاقة الاشتراك الحالي (بارزة، تدرّج كحلي + حافّة ذهبية) ──
  Widget _subscriptionHero(BuildContext context) {
    return SdRaised(
      onTap: () => context.go('/citizen/internet'),
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
          Row(
            children: [
              const Expanded(
                child: Text('اشتراكك الحالي',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              const SdStatusChip('مُفعّل', status: SdStatus.success),
            ],
          ),
          const SizedBox(height: 6),
          const Text('باقة 50 ميجا — غير محدود',
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: SdSpace.md),
          Row(
            children: [
              _heroMini('23 يوم', 'المتبقّي'),
              const SizedBox(width: SdSpace.sm),
              _heroMini('25,000 د.ع', 'الاشتراك الشهري'),
            ],
          ),
          const SizedBox(height: SdSpace.md),
          SdButton(
            label: 'تجديد الاشتراك',
            icon: Icons.autorenew_rounded,
            kind: SdButtonKind.accent,
            expand: true,
            onPressed: () => context.go('/citizen/internet/renewal'),
          ),
        ],
      ),
    );
  }

  Widget _heroMini(String value, String label) => Expanded(
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
              Text(value,
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900)),
              Text(label,
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      color: Colors.white70,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  // ── شبكة الخدمات السريعة (مكعّبات 3D) ──
  Widget _services(BuildContext context) {
    return SdTileGrid(
      phoneColumns: 2,
      maxColumns: 4,
      children: [
        _serviceTile(context,
            icon: Icons.wifi_rounded,
            title: 'الإنترنت',
            subtitle: 'اشتراك • تجديد • صيانة',
            tone: _net,
            route: '/citizen/internet'),
        _serviceTile(context,
            icon: Icons.credit_card_rounded,
            title: 'ماستر كارد',
            subtitle: 'طلب • شحن • سحب',
            group: SdGroup.platform,
            route: '/citizen/master'),
        _serviceTile(context,
            icon: Icons.shopping_cart_rounded,
            title: 'المتجر',
            subtitle: 'راوترات • أجهزة',
            group: SdGroup.field,
            route: '/citizen/store'),
        _serviceTile(context,
            icon: Icons.map_rounded,
            title: 'خريطة التغطية',
            subtitle: 'مناطق الشبكة',
            group: SdGroup.admin,
            route: '/citizen/kml-map'),
      ],
    );
  }

  Widget _serviceTile(
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
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SdText.titleSm.copyWith(fontSize: 14.5)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SdText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── آخر الطلبات ──
  List<Widget> _recentRequests(BuildContext context) {
    final items = <_Req>[
      _Req(Icons.autorenew_rounded, 'تجديد اشتراك', 'طلب #10294 • اليوم',
          'مكتمل', SdStatus.success, _net, '/citizen/internet/renewal'),
      _Req(Icons.delivery_dining_rounded, 'سحب ديلفري 100,000', 'طلب #10287 • أمس',
          'قيد التنفيذ', SdStatus.warning, null, '/citizen/master'),
      _Req(Icons.build_rounded, 'طلب صيانة', 'طلب #10261 • قبل 3 أيام',
          'جديد', SdStatus.info, null, '/citizen/internet/maintenance'),
    ];
    final out = <Widget>[];
    for (final r in items) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: SdSpace.sm),
        child: SdRaised(
          onTap: () => context.go(r.route),
          radius: SdRadius.md,
          depth: SdDepth.small,
          padding: const EdgeInsets.all(SdSpace.sm),
          child: Row(
            children: [
              SdIconCube(
                  icon: r.icon,
                  tone: r.tone ?? r.status.tone,
                  size: 40),
              const SizedBox(width: SdSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SdText.label),
                    Text(r.sub, style: SdText.caption),
                  ],
                ),
              ),
              SdStatusChip(r.statusLabel, status: r.status),
            ],
          ),
        ),
      ));
    }
    return out;
  }
}

class _Req {
  final IconData icon;
  final String title;
  final String sub;
  final String statusLabel;
  final SdStatus status;
  final SdTone? tone;
  final String route;
  _Req(this.icon, this.title, this.sub, this.statusLabel, this.status,
      this.tone, this.route);
}

// ── شريط التنقّل السفلي ──
class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.active});
  final int active;

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, String)>[
      (Icons.home_rounded, 'الرئيسية', '/citizen/home'),
      (Icons.receipt_long_rounded, 'طلباتي', '/citizen/requests'),
      (Icons.shopping_cart_rounded, 'المتجر', '/citizen/store'),
      (Icons.person_rounded, 'حسابي', '/citizen/profile'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        border: SdOutline.all,
        boxShadow: const [
          BoxShadow(color: Color(0x1A0B1B3F), blurRadius: 18, offset: Offset(0, -2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            _navItem(context, items[i].$1, items[i].$2, items[i].$3, i == active),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, IconData icon, String label,
      String route, bool on) {
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
                        colors: [SdColors.primaryMid, SdColors.primary])
                    : null,
                color: on ? null : SdColors.surfaceAlt,
                borderRadius: BorderRadius.circular(SdRadius.sm),
                border: on
                    ? Border.all(color: SdColors.goldLight, width: 1)
                    : null,
              ),
              child: Icon(icon,
                  size: 18, color: on ? Colors.white : SdColors.muted),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: on ? SdColors.primary : SdColors.muted)),
          ],
        ),
      ),
    );
  }
}
