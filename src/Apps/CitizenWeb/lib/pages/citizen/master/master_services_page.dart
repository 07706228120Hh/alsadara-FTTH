import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';

/// خدمات بطاقات الماستر — موحّدة على نظام تصميم الصدارة (3D).
class MasterServicesPage extends StatelessWidget {
  const MasterServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SdPage(
      appBar: SdAppBar(
        title: 'خدمات الماستر',
        onBack: () => context.go('/citizen/home'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardBalance(),
          const SizedBox(height: SdSpace.lg),
          const SdSectionHeader(title: 'الخدمات المتاحة'),
          const SizedBox(height: SdSpace.sm),
          SdTileGrid(
            phoneColumns: 2,
            maxColumns: 4,
            children: [
              _tile(context,
                  icon: Icons.add_card_rounded,
                  title: 'بطاقة جديدة',
                  subtitle: 'اطلب وتسلّم',
                  tone: SdStatus.success.tone,
                  route: '/citizen/master/new-card'),
              _tile(context,
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'شحن رصيد',
                  subtitle: 'عبّئ بطاقتك',
                  group: SdGroup.platform,
                  route: '/citizen/master/recharge'),
              _tile(context,
                  icon: Icons.delivery_dining_rounded,
                  title: 'سحب ديلفري',
                  subtitle: 'نقداً إلى بابك',
                  tone: SdStatus.warning.tone,
                  route: '/citizen/master/delivery-withdraw'),
              _tile(context,
                  icon: Icons.receipt_long_rounded,
                  title: 'كشف حساب',
                  subtitle: 'سجل المعاملات',
                  group: SdGroup.admin,
                  route: '/citizen/master/statement'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardBalance() {
    return SdRaised(
      radius: SdRadius.xl,
      depth: SdDepth.hero,
      padding: const EdgeInsets.all(SdSpace.lg),
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [SdColors.platformEdge, SdColors.platformMid],
      ),
      edgeColor: SdColors.platformEdge,
      glowColor: const Color(0x805B21B6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الرصيد المتاح',
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('320,000 د.ع',
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: SdSpace.sm),
          const Text('•••• •••• •••• 4821',
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: Colors.white70,
                  fontSize: 13,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

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
}
