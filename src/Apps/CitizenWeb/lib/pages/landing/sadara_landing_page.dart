import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'landing_data.dart';
import 'landing_effects.dart';
import 'landing_sections.dart';
import 'landing_style.dart';
import 'landing_video.dart';

/// الواجهة الرئيسية الجديدة لمنصة الصدارة (المسار `/`).
///
/// الترتيب من الأعلى:
/// رأس ثابت ← فيديو الخدمات + وصفها ← شريط الخدمات ← بطاقات الخدمات (فيديو لكل خدمة)
/// ← خطوات سحب ديلفري ← التغطية ← دعوة التسجيل ← التذييل.
/// دخول الوكيل موجود في القائمة الجانبية فقط.
///
/// الملفات:
/// - landing_style.dart   الألوان والخطوط وزخرفة البروز
/// - landing_data.dart    الخدمات ومساراتها ونصوص الأقسام وبيانات التواصل
/// - landing_effects.dart الميلان، الأزرار البارزة، اللمعة، النقاط النابضة، الشريط المتحرك
/// - landing_video.dart   مشغّل فيديو الخدمات وفيديو البطاقات
/// - landing_sections.dart أقسام الصفحة
class SadaraLandingPage extends StatefulWidget {
  const SadaraLandingPage({super.key});

  @override
  State<SadaraLandingPage> createState() => _SadaraLandingPageState();
}

class _SadaraLandingPageState extends State<SadaraLandingPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  final _player = HeroPlayerController();
  final _keys = {'services': GlobalKey(), 'delivery': GlobalKey(), 'coverage': GlobalKey()};
  int _current = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _player.dispose();
    super.dispose();
  }

  void _goSection(String id) {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: Duration(milliseconds: reduceMotion(context) ? 0 : 600), curve: Curves.easeInOutCubic, alignmentPolicy: ScrollPositionAlignmentPolicy.explicit, alignment: 0);
  }

  void _open(String route) => context.go(route);

  void _watch(int i) {
    _player.select(i);
    _scroll.animateTo(0, duration: Duration(milliseconds: reduceMotion(context) ? 0 : 600), curve: Curves.easeInOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: _scaffold,
        backgroundColor: const Color(0xFFE9EEF5),
        // في الاتجاه من اليمين لليسار تنفتح القائمة من اليمين
        drawer: AgentDrawer(onAgentLogin: () => _open('/agent/login'), onNav: _goSection),
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: LColors.pageGradient),
          child: Stack(children: [
            const Positioned.fill(child: LivingOrbs()),
            CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: LandingHeaderDelegate(
                    onMenu: () => _scaffold.currentState?.openDrawer(),
                    onLogin: () => _open('/citizen/login'),
                    onNav: _goSection,
                  ),
                ),
                SliverToBoxAdapter(
                  child: HeroSection(
                    player: _player,
                    current: _current,
                    onIndexChanged: (i) => setState(() => _current = i),
                    onAllServices: () => _goSection('services'),
                    onOpenRoute: _open,
                  ),
                ),
                const SliverToBoxAdapter(child: Marquee(items: kMarquee)),
                SliverToBoxAdapter(child: KeyedSubtree(key: _keys['services'], child: ServicesSection(onWatch: _watch))),
                SliverToBoxAdapter(child: KeyedSubtree(key: _keys['delivery'], child: const DeliveryStepsSection())),
                SliverToBoxAdapter(child: KeyedSubtree(key: _keys['coverage'], child: CoverageSection(onOpenMap: () => _open('/citizen/kml-map')))),
                SliverToBoxAdapter(child: CtaSection(onRegister: () => _open('/citizen/register'), onLogin: () => _open('/citizen/login'))),
                SliverToBoxAdapter(child: LandingFooter(onNav: _goSection, onOpenRoute: _open)),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
