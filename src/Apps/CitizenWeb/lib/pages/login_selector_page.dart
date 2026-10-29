import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';

/// اختيار نوع الدخول — موحّد على نظام تصميم الصدارة (3D).
class LoginSelectorPage extends StatelessWidget {
  const LoginSelectorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SdPage(
      maxWidth: 520,
      appBar: SdAppBar(title: 'أهلاً بك', onBack: () => context.go('/')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: SdSpace.sm),
          Text('اختر نوع الدخول للمتابعة',
              textAlign: TextAlign.center, style: SdText.bodySm),
          const SizedBox(height: SdSpace.lg),
          _choice(context,
              icon: Icons.person_rounded,
              title: 'دخول المواطن',
              subtitle: 'للاشتراكات والخدمات والمتجر',
              tone: null,
              group: SdGroup.admin,
              label: 'متابعة كمواطن',
              kind: SdButtonKind.primary,
              route: '/citizen/login'),
          const SizedBox(height: SdSpace.md),
          _choice(context,
              icon: Icons.storefront_rounded,
              title: 'دخول الوكيل',
              subtitle: 'للوكلاء ونقاط البيع المعتمدة',
              tone: null,
              group: SdGroup.field,
              label: 'متابعة كوكيل',
              kind: SdButtonKind.accent,
              route: '/agent/login'),
        ],
      ),
    );
  }

  Widget _choice(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      SdTone? tone,
      required SdGroup group,
      required String label,
      required SdButtonKind kind,
      required String route}) {
    return SdRaised(
      onTap: () => context.go(route),
      radius: SdRadius.xl,
      depth: SdDepth.card,
      padding: const EdgeInsets.all(SdSpace.lg),
      child: Column(
        children: [
          SdIconCube(icon: icon, tone: tone, group: group, size: 58),
          const SizedBox(height: SdSpace.sm),
          Text(title, style: SdText.title),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: SdText.bodySm),
          const SizedBox(height: SdSpace.md),
          SdButton(
              label: label,
              kind: kind,
              expand: true,
              onPressed: () => context.go(route)),
        ],
      ),
    );
  }
}
