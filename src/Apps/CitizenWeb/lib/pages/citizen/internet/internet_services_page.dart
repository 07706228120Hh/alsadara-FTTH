import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';

/// خدمات الإنترنت — موحّدة على نظام تصميم الصدارة (3D).
class InternetServicesPage extends StatelessWidget {
  const InternetServicesPage({super.key});

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
    return SdPage(
      appBar: SdAppBar(
        title: 'خدمات الإنترنت',
        onBack: () => context.go('/citizen/home'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _activePlan(),
          const SizedBox(height: SdSpace.lg),
          const SdSectionHeader(title: 'الخدمات المتاحة'),
          const SizedBox(height: SdSpace.sm),
          SdTileGrid(
            phoneColumns: 2,
            maxColumns: 4,
            children: [
              _tile(context,
                  icon: Icons.add_circle_outline_rounded,
                  title: 'اشتراك جديد',
                  subtitle: 'تفعيل باقة',
                  tone: SdStatus.success.tone,
                  route: '/citizen/internet/new'),
              _tile(context,
                  icon: Icons.autorenew_rounded,
                  title: 'تجديد الاشتراك',
                  subtitle: 'مدّد باقتك الشهرية',
                  group: SdGroup.admin,
                  route: '/citizen/internet/renewal'),
              _tile(context,
                  icon: Icons.upgrade_rounded,
                  title: 'ترقية الباقة',
                  subtitle: 'سرعة أعلى',
                  tone: SdStatus.warning.tone,
                  route: '/citizen/internet/upgrade'),
              _tile(context,
                  icon: Icons.build_rounded,
                  title: 'طلب صيانة',
                  subtitle: 'بلّغ عن عطل',
                  tone: SdStatus.danger.tone,
                  route: '/citizen/internet/maintenance'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activePlan() {
    return SdRaised(
      radius: SdRadius.xl,
      depth: SdDepth.hero,
      padding: const EdgeInsets.all(SdSpace.lg),
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [SdColors.accentEdge, SdColors.accentLight],
      ),
      edgeColor: SdColors.accentEdge,
      glowColor: const Color(0x800E7490),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('الباقة الفعّالة',
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('50 ميجا — غير محدود',
              style: TextStyle(
                  fontFamily: SdText.family,
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: SdSpace.md),
          Row(
            children: const [
              _Mini('23 يوم', 'المتبقّي'),
              SizedBox(width: SdSpace.sm),
              _Mini('25,000 د.ع', 'الاشتراك الشهري'),
            ],
          ),
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

class _Mini extends StatelessWidget {
  const _Mini(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
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
}
