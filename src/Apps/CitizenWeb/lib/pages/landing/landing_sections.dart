import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'landing_data.dart';
import 'landing_effects.dart';
import 'landing_style.dart';
import 'landing_video.dart';

/// حاوية بعرض أقصى ثابت وحواف جانبية آمنة.
class LWrap extends StatelessWidget {
  final Widget child;
  final double max;
  const LWrap({super.key, required this.child, this.max = LBreak.maxWidth});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child)),
    );
  }
}

/// رأس القسم: عنوان صغير + عنوان كبير (مع كلمة لامعة) + سطر وصف.
class SectionHead extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String shine;
  final String? sub;
  final bool dark;
  const SectionHead({super.key, required this.eyebrow, required this.title, required this.shine, this.sub, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final size = w < LBreak.phone ? 24.0 : 32.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Eyebrow(eyebrow, bg: dark ? LColors.goldLight.withValues(alpha: .14) : LColors.tealSoft, fg: dark ? LColors.goldLight : LColors.teal),
        const SizedBox(height: 8),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('$title ', style: LText.h(size, color: dark ? Colors.white : LColors.ink, shadows: dark ? LText.carvedDark : LText.carvedLight)),
          ShineText(shine,
              style: LText.h(size),
              colors: dark ? const [LColors.goldLight, Color(0xFFFFF1C6), LColors.goldLight] : const [LColors.teal, LColors.tealLight, Color(0xFF5FD4E8), LColors.teal]),
        ]),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(sub!, style: LText.b(15, color: dark ? LColors.onNavy : LColors.muted)),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// الرأس العلوي (ثابت أثناء التمرير)
// ═══════════════════════════════════════════════════════════════
class LandingHeaderDelegate extends SliverPersistentHeaderDelegate {
  final VoidCallback onMenu;
  final VoidCallback onLogin;
  final void Function(String section) onNav;
  LandingHeaderDelegate({required this.onMenu, required this.onLogin, required this.onNav});

  @override
  double get minExtent => 68;
  @override
  double get maxExtent => 68;
  @override
  bool shouldRebuild(covariant LandingHeaderDelegate old) => false;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      decoration: BoxDecoration(
        color: LColors.navyDeep.withValues(alpha: .94),
        border: Border(bottom: BorderSide(color: LColors.goldLight.withValues(alpha: .25))),
      ),
      child: LWrap(
        child: Row(children: [
          Flexible(child: BrandMark(showName: w > 380)),
          const Spacer(),
          if (w > LBreak.tablet) ...[
            for (final n in const [('services', 'الخدمات'), ('delivery', 'سحب ديلفري'), ('coverage', 'التغطية')])
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _NavLink(n.$2, onTap: () => onNav(n.$1)),
              ),
            const Spacer(),
          ],
          Press3D(label: w < LBreak.phone ? 'دخول المواطن' : 'تسجيل دخول المواطن', onTap: onLogin, height: 42, fontSize: 14),
          const SizedBox(width: 10),
          _Burger(onTap: onMenu),
        ]),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  const _NavLink(this.text, {required this.onTap});
  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _h = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(widget.text, style: LText.b(15, weight: FontWeight.w500, color: _h ? LColors.goldLight : LColors.onNavy)),
      ),
    );
  }
}

class _Burger extends StatelessWidget {
  final VoidCallback onTap;
  const _Burger({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'فتح القائمة',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
            boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(0, 4))],
          ),
          child: const Icon(Icons.menu_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

/// الشعار في مربع أبيض + اسم المنصة.
class BrandMark extends StatelessWidget {
  final Color textColor;
  final bool showName;
  const BrandMark({super.key, this.textColor = Colors.white, this.showName = true});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 42,
        height: 42,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: LColors.goldLight.withValues(alpha: .6)),
          boxShadow: const [BoxShadow(color: Color(0x2E0B1B3F), offset: Offset(0, 4))],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(11), child: Image.asset('assets/images/logo.png', fit: BoxFit.cover)),
      ),
      if (showName) ...[
        const SizedBox(width: 10),
        Flexible(child: Text('منصة الصدارة', maxLines: 1, overflow: TextOverflow.ellipsis, style: LText.h(18, weight: FontWeight.w700, color: textColor, height: 1.2))),
      ],
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════
// القائمة الجانبية (دخول الوكيل هنا)
// ═══════════════════════════════════════════════════════════════
class AgentDrawer extends StatelessWidget {
  final VoidCallback onAgentLogin;
  final void Function(String section) onNav;
  const AgentDrawer({super.key, required this.onAgentLogin, required this.onNav});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Drawer(
      width: math.min(360, w * .88),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [LColors.navy, LColors.navyDeep]),
          border: Border(left: BorderSide(color: LColors.goldLight.withValues(alpha: .3))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const BrandMark(),
                const Spacer(),
                IconButton(
                  tooltip: 'إغلاق القائمة',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .06), side: BorderSide(color: Colors.white.withValues(alpha: .2))),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ]),
              const SizedBox(height: 20),
              for (final n in const [('services', 'الخدمات'), ('delivery', 'سحب ديلفري'), ('coverage', 'خريطة التغطية')])
                ListTile(
                  title: Text(n.$2, style: LText.b(17, weight: FontWeight.w600, color: const Color(0xFFDCE5F3))),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  hoverColor: Colors.white.withValues(alpha: .07),
                  onTap: () {
                    Navigator.of(context).pop();
                    onNav(n.$1);
                  },
                ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(colors: [LColors.goldLight.withValues(alpha: .14), Colors.white.withValues(alpha: .04)], begin: Alignment.topRight, end: Alignment.bottomLeft),
                  border: Border.all(color: LColors.goldLight.withValues(alpha: .35)),
                  boxShadow: const [BoxShadow(color: Color(0x4D000000), offset: Offset(0, 6))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Eyebrow('بوابة الوكلاء', bg: LColors.goldLight.withValues(alpha: .16), fg: LColors.goldLight),
                  const SizedBox(height: 10),
                  Text('دخول الوكيل', style: LText.h(22, color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('لوحة الوكيل لتفعيل المشتركين، شحن الماستر، طلب الرصيد والتقارير.', style: LText.b(14, color: LColors.onNavy)),
                  const SizedBox(height: 14),
                  Press3D(
                    label: 'دخول وكيل',
                    icon: Icons.arrow_back_rounded,
                    onTap: () {
                      Navigator.of(context).pop();
                      onAgentLogin();
                    },
                  ),
                ]),
              ),
              const Spacer(),
              Text(LContact.phone, textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: LText.b(14, color: LColors.onNavyMuted)),
              Text(LContact.email, textDirection: TextDirection.ltr, textAlign: TextAlign.right, style: LText.b(14, color: LColors.onNavyMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// بداية الصفحة: وصف الخدمة الحالية + مشغّل الفيديو
// ═══════════════════════════════════════════════════════════════
class HeroSection extends StatelessWidget {
  final HeroPlayerController player;
  final int current;
  final ValueChanged<int> onIndexChanged;
  final VoidCallback onAllServices;
  final ValueChanged<String> onOpenRoute;
  const HeroSection({super.key, required this.player, required this.current, required this.onIndexChanged, required this.onAllServices, required this.onOpenRoute});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final stacked = w <= LBreak.stackHero;
    final side = _HeroSide(index: current, onStart: () => onOpenRoute(kServices[current].route), onAll: onAllServices);
    final video = HeroPlayer(controller: player, onIndexChanged: onIndexChanged);
    return Container(
      decoration: const BoxDecoration(gradient: LColors.heroGradient),
      child: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(-.7, -.9), radius: 1.1, colors: [LColors.tealLight.withValues(alpha: .35), Colors.transparent]),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: const Alignment(.9, 1), radius: .9, colors: [LColors.goldLight.withValues(alpha: .25), Colors.transparent]),
            ),
          ),
        ),
        const Positioned.fill(child: CustomPaint(painter: DotGridPainter())),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: LWrap(
            child: stacked
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [video, const SizedBox(height: 22), side])
                : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(flex: w <= LBreak.tablet ? 100 : 85, child: side),
                    const SizedBox(width: 40),
                    Expanded(flex: w <= LBreak.tablet ? 135 : 170, child: video),
                  ]),
          ),
        ),
      ]),
    );
  }
}

class _HeroSide extends StatelessWidget {
  final int index;
  final VoidCallback onStart;
  final VoidCallback onAll;
  const _HeroSide({required this.index, required this.onStart, required this.onAll});

  @override
  Widget build(BuildContext context) {
    final s = kServices[index];
    final next = kServices[(index + 1) % kServices.length];
    final w = MediaQuery.sizeOf(context).width;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a), child: child)),
      child: Column(
        key: ValueKey(index),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Eyebrow('خدمات منصة الصدارة', bg: LColors.goldLight.withValues(alpha: .14), fg: LColors.goldLight),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: s.bg,
                borderRadius: BorderRadius.circular(13),
                boxShadow: const [BoxShadow(color: Color(0x4D000000), offset: Offset(0, 4))],
              ),
              child: Icon(s.icon, color: s.fg, size: 22),
            ),
            const SizedBox(width: 12),
            Text('${arDigits(index + 1)} / ${arDigits(kServices.length)}', style: LText.h(14, weight: FontWeight.w500, color: LColors.onNavyMuted)),
          ]),
          const SizedBox(height: 10),
          Text(s.title, style: LText.h(w < LBreak.tablet ? 28 : 34, color: Colors.white, shadows: LText.carvedDark)),
          const SizedBox(height: 6),
          Text(s.desc, style: LText.b(15, color: LColors.onNavy)),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 12, children: [
            Press3D(label: 'ابدأ الآن', onTap: onStart, sheen: true, height: 44, fontSize: 14),
            Press3D(label: 'كل الخدمات', onTap: onAll, style: Btn3DStyle.ghostDark, height: 44, fontSize: 14),
          ]),
          const SizedBox(height: 12),
          Text('التالي: ${next.title}', style: LText.b(13.5, color: LColors.onNavyMuted)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// الخدمات: بطاقة لكل خدمة فيها فيديوها
// ═══════════════════════════════════════════════════════════════
class ServicesSection extends StatelessWidget {
  final ValueChanged<int> onWatch;
  const ServicesSection({super.key, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= LBreak.wide ? 6 : (w > LBreak.phone ? 3 : 2);
    final gap = cols == 6 ? 12.0 : 14.0;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE3EAF4), Color(0xFFEDEBE4)])),
      padding: EdgeInsets.symmetric(vertical: w < LBreak.phone ? 36 : 48),
      child: LWrap(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHead(eyebrow: 'خدماتنا', title: 'ست خدمات تغطي', shine: 'يومك الرقمي', sub: 'كل خدمة تجدها في حسابك على المنصة، ويمكنك مشاهدة مقطعها في أعلى الصفحة.'),
          LayoutBuilder(builder: (context, c) {
            final cardW = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (int i = 0; i < kServices.length; i++)
                SizedBox(width: cardW, child: Reveal(index: i % cols, child: _ServiceCard(service: kServices[i], compact: cols == 6, narrow: cols == 2, onWatch: () => onWatch(i)))),
            ]);
          }),
        ]),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final LService service;
  final bool compact;
  final bool narrow;
  final VoidCallback onWatch;
  const _ServiceCard({required this.service, required this.compact, required this.narrow, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    final s = service;
    return Tilt3D(
      radius: BorderRadius.circular(20),
      lift: -6,
      child: Container(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 12, compact ? 8 : 12, compact ? 8 : 12, compact ? 10 : 14),
        decoration: raised(
          radius: 20,
          depth: 7,
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFF4F7FB), Color(0xFFEEF3F9)], stops: [0, .55, 1]),
          border: Border.all(color: LColors.gold.withValues(alpha: .35)),
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          // خط ذهبي رفيع في أعلى البطاقة
          Positioned(
            top: -8,
            left: 16,
            right: 16,
            child: Container(height: 3, decoration: const BoxDecoration(borderRadius: BorderRadius.vertical(bottom: Radius.circular(4)), gradient: LinearGradient(colors: [Colors.transparent, LColors.gold, Colors.transparent]))),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            MiniVideo(service: s),
            const SizedBox(height: 10),
            Row(children: [
              Container(
                width: compact ? 26 : 30,
                height: compact ? 26 : 30,
                decoration: BoxDecoration(color: s.bg, borderRadius: BorderRadius.circular(9), boxShadow: const [BoxShadow(color: Color(0x2E0B1B3F), offset: Offset(0, 3))]),
                child: Icon(s.icon, size: compact ? 15 : 17, color: s.fg),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: LText.h(compact || narrow ? 14 : 16, weight: FontWeight.w700))),
            ]),
            if (!narrow) ...[
              const SizedBox(height: 6),
              Text(s.desc, maxLines: 2, overflow: TextOverflow.ellipsis, style: LText.b(compact ? 12.5 : 13.5, height: 1.6)),
            ],
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onWatch,
              style: TextButton.styleFrom(foregroundColor: LColors.teal, padding: const EdgeInsets.symmetric(horizontal: 2), minimumSize: const Size(0, 36)),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text('شاهد مقطعها', style: LText.b(compact ? 13 : 14, weight: FontWeight.w600, color: LColors.teal, height: 1.2)),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// خطوات سحب ديلفري (شريط كحلي + بطاقات زجاجية متحركة)
// ═══════════════════════════════════════════════════════════════
class DeliveryStepsSection extends StatelessWidget {
  const DeliveryStepsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = w > LBreak.tablet ? 4 : 2;
    final phone = w <= LBreak.phone;
    return Container(
      decoration: const BoxDecoration(gradient: LColors.navyBandGradient),
      padding: EdgeInsets.symmetric(vertical: phone ? 36 : 48),
      child: LWrap(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHead(eyebrow: 'سحب ديلفري', title: 'اسحب من بطاقتك…', shine: 'والنقد يصلك للبيت', sub: 'أربع خطوات من طلبك في التطبيق حتى استلام المبلغ نقداً من المندوب.', dark: true),
          LayoutBuilder(builder: (context, c) {
            const gap = 12.0;
            final cw = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (int i = 0; i < kDeliverySteps.length; i++)
                SizedBox(width: cw, child: Reveal(index: i, child: _StepTile(n: i, step: kDeliverySteps[i], showText: !phone))),
            ]);
          }),
        ]),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int n;
  final LStep step;
  final bool showText;
  const _StepTile({required this.n, required this.step, required this.showText});

  @override
  Widget build(BuildContext context) {
    return Tilt3D(
      radius: BorderRadius.circular(20),
      glare: const Color(0x2EFFFFFF),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: .1), Colors.white.withValues(alpha: .03)]),
          border: Border.all(color: Colors.white.withValues(alpha: .14)),
          boxShadow: const [BoxShadow(color: Color(0x59000000), offset: Offset(0, 7)), BoxShadow(color: Color(0xB3000000), offset: Offset(0, 26), blurRadius: 40, spreadRadius: -30)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(gradient: LColors.goldGradient, borderRadius: BorderRadius.circular(11), boxShadow: const [BoxShadow(color: Color(0x4D000000), offset: Offset(0, 4))]),
              child: Text('١٢٣٤'[n], style: LText.h(15, weight: FontWeight.w700, color: LColors.goldInk, height: 1)),
            ),
            const Spacer(),
            StepAnim(kind: n),
          ]),
          const SizedBox(height: 8),
          Text(step.title, style: LText.h(16, weight: FontWeight.w700, color: Colors.white)),
          if (showText) ...[
            const SizedBox(height: 4),
            Text(step.text, style: LText.b(13.5, color: LColors.onNavy, height: 1.6)),
          ],
        ]),
      ),
    );
  }
}

/// حركة صغيرة لكل خطوة: كتابة المبلغ، سقوط الدبوس، علامة النجاح، أوراق نقدية.
class StepAnim extends StatefulWidget {
  final int kind;
  const StepAnim({super.key, required this.kind});
  @override
  State<StepAnim> createState() => _StepAnimState();
}

class _StepAnimState extends State<StepAnim> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: [4000, 2400, 2600, 2800][widget.kind]));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.value = .6;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = [Colors.white.withValues(alpha: .1), Colors.white.withValues(alpha: .1), LColors.green.withValues(alpha: .18), LColors.goldLight.withValues(alpha: .15)][widget.kind];
    return Container(
      height: 36,
      width: 92,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(11)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(animation: _c, builder: (context, _) => _frame(_c.value)),
    );
  }

  Widget _frame(double t) {
    switch (widget.kind) {
      case 0: // كتابة المبلغ
        const full = '250,000';
        final k = t < .1 ? 0.0 : (t > .9 ? 0.0 : ((t - .1) / .5).clamp(0.0, 1.0));
        final n = (k * full.length).floor();
        return Row(mainAxisAlignment: MainAxisAlignment.center, textDirection: TextDirection.ltr, children: [
          Text(full.substring(0, n), style: LText.h(14, weight: FontWeight.w700, color: const Color(0xFF7FE3F2), height: 1)),
          Opacity(opacity: (t * 10).floor().isEven ? 1.0 : 0.0, child: Container(width: 2, height: 18, color: const Color(0xFF7FE3F2))),
        ]);
      case 1: // سقوط الدبوس
        final k = t < .3 ? Curves.bounceOut.transform(t / .3) : (t > .85 ? 1 - (t - .85) / .15 : 1.0);
        return Stack(alignment: Alignment.center, children: [
          Positioned(bottom: 5, child: Container(width: 20 * k + 4, height: 5, decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: LColors.teal.withValues(alpha: .35 * k)))),
          Transform.translate(offset: Offset(0, -34 * (1 - k)), child: const Icon(Icons.location_on_rounded, color: LColors.tealGlow, size: 26)),
        ]);
      case 2: // علامة النجاح
        final k = t < .15 ? 0.0 : (t < .35 ? Curves.elasticOut.transform((t - .15) / .2) : (t > .85 ? 1 - (t - .85) / .15 : 1.0));
        return Center(
          child: Transform.scale(
            scale: k.clamp(0.0, 1.3),
            child: Container(width: 28, height: 28, decoration: const BoxDecoration(shape: BoxShape.circle, color: LColors.green), child: const Icon(Icons.check_rounded, color: Colors.white, size: 20)),
          ),
        );
      default: // أوراق نقدية تنزلق
        return Stack(alignment: Alignment.center, children: [
          for (int i = 0; i < 3; i++)
            Builder(builder: (context) {
              final f = ((t - i * .09) % 1 + 1) % 1;
              final x = f < .25 ? 60 * (1 - f / .25) : (f > .75 ? -60 * ((f - .75) / .25) : 0.0);
              final op = f < .25 ? f / .25 : (f > .75 ? 1 - (f - .75) / .25 : 1.0);
              return Opacity(
                opacity: op.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(x, 0),
                  child: Transform.rotate(
                    angle: -.07,
                    child: Container(
                      width: 42,
                      height: 22,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF5CC08F), Color(0xFF2E9D6A)]),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: const Color(0xFFE8F7EE), width: 2),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ]);
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// التغطية: خريطة نقاط نابضة + حقل بحث يفتح خريطة التغطية الحقيقية
// ═══════════════════════════════════════════════════════════════
class CoverageSection extends StatefulWidget {
  final VoidCallback onOpenMap;
  const CoverageSection({super.key, required this.onOpenMap});
  @override
  State<CoverageSection> createState() => _CoverageSectionState();
}

class _CoverageSectionState extends State<CoverageSection> {
  final _area = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _area.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final focused = _focus.hasFocus;
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFEDEBE4), Color(0xFFE3EAF4)])),
      padding: EdgeInsets.symmetric(vertical: w < LBreak.phone ? 36 : 48),
      child: LWrap(
        max: 760,
        child: Reveal(
          child: Tilt3D(
            maxDeg: 4,
            radius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: raised(
                radius: 22,
                depth: 7,
                gradient: const LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFE2F4F8), Colors.white, Color(0xFFFBF4E3)], stops: [0, .6, 1]),
                border: Border.all(color: LColors.teal.withValues(alpha: .25)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Eyebrow('خريطة التغطية'),
                const SizedBox(height: 10),
                Wrap(children: [
                  Text('هل منطقتك ', style: LText.h(24, shadows: LText.carvedLight)),
                  ShineText('ضمن الشبكة؟', style: LText.h(24)),
                ]),
                const SizedBox(height: 6),
                Text('افتح خريطة التغطية التفاعلية لترى المناطق المخدومة بالفايبر، واطلب اشتراكك مباشرة.', style: LText.b(14)),
                const SizedBox(height: 12),
                const _MiniMap(),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: focused ? Colors.white : const Color(0xFFEEF3F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: focused ? LColors.tealLight : LColors.edgeCard),
                        boxShadow: focused
                            ? [BoxShadow(color: LColors.tealLight.withValues(alpha: .18), spreadRadius: 4), const BoxShadow(color: Color(0xFFCFE7EE), offset: Offset(0, 6))]
                            : const [BoxShadow(color: Color(0x14132A5E), offset: Offset(0, 3), blurRadius: 0, spreadRadius: -1)],
                      ),
                      child: Row(children: [
                        const Icon(Icons.location_on_outlined, color: LColors.teal, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _area,
                            focusNode: _focus,
                            onSubmitted: (_) => widget.onOpenMap(),
                            style: LText.b(15, color: LColors.ink, height: 1.2),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: 'اكتب اسم منطقتك أو حيّك',
                              hintStyle: LText.b(15, color: const Color(0xFF7C869C), height: 1.2),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Press3D(label: 'تحقّق', onTap: widget.onOpenMap, style: Btn3DStyle.teal, height: 46, fontSize: 14),
                ]),
                const SizedBox(height: 8),
                Text('سنفتح لك خريطة التغطية لتحدّد موقعك عليها.', style: LText.b(13.5)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  const _MiniMap();
  @override
  Widget build(BuildContext context) {
    const pins = [(.22, .30, LColors.teal), (.46, .58, LColors.gold), (.68, .24, LColors.teal), (.78, .70, LColors.gold), (.12, .46, LColors.teal)];
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 130,
        child: LayoutBuilder(builder: (context, c) {
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _GridMapPainter())),
            for (int i = 0; i < pins.length; i++)
              Positioned(
                left: c.maxWidth * pins[i].$1 - 21,
                top: 130 * pins[i].$2 - 21,
                child: PulseDot(color: pins[i].$3, size: 14, delay: Duration(milliseconds: 600 * i)),
              ),
          ]);
        }),
      ),
    );
  }
}

class _GridMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE6EEF6));
    final p = Paint()..color = Colors.white;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 5, size.height), p);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 5), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════
// دعوة التسجيل (ضوء ذهبي يدور في الخلفية)
// ═══════════════════════════════════════════════════════════════
class CtaSection extends StatefulWidget {
  final VoidCallback onRegister;
  final VoidCallback onLogin;
  const CtaSection({super.key, required this.onRegister, required this.onLogin});
  @override
  State<CtaSection> createState() => _CtaSectionState();
}

class _CtaSectionState extends State<CtaSection> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!reduceMotion(context) && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE3EAF4),
      padding: const EdgeInsets.only(bottom: 4),
      child: LWrap(
        child: Tilt3D(
          maxDeg: 3,
          radius: BorderRadius.circular(24),
          glare: const Color(0x2EFFFFFF),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: LColors.goldLight.withValues(alpha: .35)),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [LColors.teal, LColors.navy, LColors.navyDeep], stops: [0, .6, 1]),
              boxShadow: const [BoxShadow(color: Color(0xFF0B2F57), offset: Offset(0, 9)), BoxShadow(color: Color(0xB30E7490), offset: Offset(0, 36), blurRadius: 60, spreadRadius: -30)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: SweepGradient(
                        transform: GradientRotation(_c.value * 2 * math.pi),
                        colors: [Colors.transparent, LColors.goldLight.withValues(alpha: .3), Colors.transparent, Colors.white.withValues(alpha: .14), Colors.transparent],
                        stops: const [0, .15, .3, .45, .6],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(28),
                child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 18, spacing: 24, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Wrap(children: [
                      Text('جاهز تبدأ مع ', style: LText.h(26, color: Colors.white)),
                      ShineText('الصدارة؟', style: LText.h(26), colors: const [LColors.goldLight, Color(0xFFFFF1C6), LColors.goldLight]),
                    ]),
                    const SizedBox(height: 6),
                    Text('أنشئ حسابك وابدأ بإدارة خدماتك من مكان واحد.', style: LText.b(14, color: const Color(0xFFD6EEF4))),
                  ]),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    Press3D(label: 'إنشاء حساب مجاني', onTap: widget.onRegister, style: Btn3DStyle.light, sheen: true),
                    Press3D(label: 'تسجيل الدخول', onTap: widget.onLogin, style: Btn3DStyle.ghostDark),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// التذييل + بيانات التواصل
// ═══════════════════════════════════════════════════════════════
class LandingFooter extends StatelessWidget {
  final void Function(String section) onNav;
  final ValueChanged<String> onOpenRoute;
  const LandingFooter({super.key, required this.onNav, required this.onOpenRoute});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = w > LBreak.tablet ? 4 : 2;
    Widget col(String title, List<Widget> items) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: LText.h(15, weight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 10),
          ...items,
        ]);
    Widget link(String t, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(t, style: LText.b(14.5, color: LColors.onNavyMuted))),
        );
    final blocks = <Widget>[
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const BrandMark(),
        const SizedBox(height: 10),
        Text('منصة رقمية لخدمات الإنترنت والدفع والتسوّق.', style: LText.b(14.5, color: LColors.onNavyMuted)),
      ]),
      col('الخدمات', [
        link('إنترنت فايبر', () => onOpenRoute('/citizen/internet')),
        link('ماستر كارد', () => onOpenRoute('/citizen/master')),
        link('سحب ديلفري', () => onOpenRoute('/citizen/master/delivery-withdraw')),
        link('المتجر', () => onOpenRoute('/citizen/store')),
      ]),
      col('المساعدة', [
        link('الدعم الفني', () => onOpenRoute('/citizen/support')),
        link('خريطة التغطية', () => onOpenRoute('/citizen/kml-map')),
        link('طلباتي', () => onOpenRoute('/citizen/orders')),
      ]),
      col('تواصل معنا', const [
        _ContactRow(icon: Icons.call_outlined, value: LContact.phone, uri: 'tel:${LContact.phone}'),
        _ContactRow(icon: Icons.mail_outline_rounded, value: LContact.email, uri: 'mailto:${LContact.email}'),
      ]),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 48),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0F2350), LColors.navyDeep]),
        border: Border(top: BorderSide(color: LColors.goldLight.withValues(alpha: .25))),
      ),
      child: LWrap(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 26),
          LayoutBuilder(builder: (context, c) {
            const gap = 18.0;
            final cw = (c.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: 22, children: [for (final b in blocks) SizedBox(width: cw, child: b)]);
          }),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: .1)))),
            child: Text('© ${LContact.company}', style: LText.b(13, color: const Color(0xFF8392B3))),
          ),
        ]),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String uri;
  const _ContactRow({required this.icon, required this.value, required this.uri});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: LColors.goldLight.withValues(alpha: .14), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: LColors.goldLight),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: InkWell(
            onTap: () => launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication),
            child: Text(value, textDirection: TextDirection.ltr, style: LText.b(14.5, color: Colors.white, height: 1.4)),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'نسخ',
          child: InkWell(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم النسخ: $value'), duration: const Duration(seconds: 2)));
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white.withValues(alpha: .2))),
              child: Text('نسخ', style: LText.b(12, color: LColors.onNavy, height: 1.2)),
            ),
          ),
        ),
      ]),
    );
  }
}
