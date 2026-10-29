import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'landing_style.dart';

/// هل طلب المستخدم تقليل الحركة من إعدادات النظام؟
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

// ═══════════════════════════════════════════════════════════════
// Tilt3D: يميل العنصر باتجاه المؤشر مع لمعة تتبعه (على الكمبيوتر فقط)
// ═══════════════════════════════════════════════════════════════
class Tilt3D extends StatefulWidget {
  final Widget child;
  final double maxDeg;
  final BorderRadius radius;
  final double lift;
  final Color glare;
  const Tilt3D({super.key, required this.child, this.maxDeg = 9, this.radius = const BorderRadius.all(Radius.circular(22)), this.lift = 0, this.glare = const Color(0x40FFFFFF)});

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> {
  Offset _p = const Offset(.5, .5);
  bool _hot = false;

  void _move(PointerHoverEvent e, Size size) {
    setState(() {
      _hot = true;
      _p = Offset((e.localPosition.dx / size.width).clamp(0, 1), (e.localPosition.dy / size.height).clamp(0, 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth.isFinite ? c.maxWidth : 300, c.maxHeight.isFinite ? c.maxHeight : 300);
      final rad = widget.maxDeg * math.pi / 180;
      final target = _hot ? Offset((0.5 - _p.dy) * 2 * rad, (_p.dx - 0.5) * 2 * rad) : Offset.zero;
      return MouseRegion(
        onHover: (e) => _move(e, context.size ?? size),
        onExit: (_) => setState(() => _hot = false),
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(end: target),
          duration: Duration(milliseconds: _hot ? 80 : 300),
          curve: Curves.easeOut,
          builder: (context, v, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0011)
              ..rotateX(v.dx)
              ..rotateY(v.dy)
              ..translate(0.0, _hot ? widget.lift : 0.0),
            child: child,
          ),
          child: Stack(children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _hot ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: widget.radius,
                      gradient: RadialGradient(
                        center: Alignment(_p.dx * 2 - 1, _p.dy * 2 - 1),
                        radius: .9,
                        colors: [widget.glare, widget.glare.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════════
// Press3D: زر بارز على حافة، ينخفض عند الضغط ويعود
// ═══════════════════════════════════════════════════════════════
enum Btn3DStyle { gold, teal, ghostDark, ghostLight, light }

class Press3D extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Btn3DStyle style;
  final IconData? icon;
  final double height;
  final double fontSize;
  final bool sheen;
  const Press3D({super.key, required this.label, required this.onTap, this.style = Btn3DStyle.gold, this.icon, this.height = 46, this.fontSize = 15, this.sheen = false});

  @override
  State<Press3D> createState() => _Press3DState();
}

class _Press3DState extends State<Press3D> with SingleTickerProviderStateMixin {
  bool _down = false, _hover = false;
  late final AnimationController _sheen = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));

  @override
  void initState() {
    super.initState();
    if (widget.sheen) _sheen.repeat();
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  ({Gradient? g, Color? c, Color fg, Color edge, BoxBorder? border}) get _look {
    switch (widget.style) {
      case Btn3DStyle.gold:
        return (g: LColors.goldGradient, c: null, fg: LColors.goldInk, edge: LColors.edgeGold, border: null);
      case Btn3DStyle.teal:
        return (g: const LinearGradient(colors: [LColors.teal, LColors.tealLight]), c: null, fg: Colors.white, edge: LColors.edgeTeal, border: null);
      case Btn3DStyle.ghostDark:
        return (g: null, c: Colors.white.withValues(alpha: .08), fg: Colors.white, edge: const Color(0x59000000), border: Border.all(color: Colors.white.withValues(alpha: .25)));
      case Btn3DStyle.ghostLight:
        return (g: null, c: Colors.white, fg: LColors.navy, edge: const Color(0xFFC3CFE2), border: Border.all(color: LColors.line));
      case Btn3DStyle.light:
        return (g: null, c: Colors.white, fg: LColors.navy, edge: const Color(0xFFB9C7DD), border: null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _look;
    final depth = _down ? 1.0 : 5.0;
    return Semantics(
      button: true,
      label: widget.label,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap())},
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) {
            setState(() => _down = false);
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: widget.height,
            transform: Matrix4.translationValues(0, _down ? 4 : (_hover ? -2 : 0), 0),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              gradient: l.g,
              color: l.c,
              border: l.border,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: l.edge, offset: Offset(0, depth)),
                if (!_down) BoxShadow(color: l.edge.withValues(alpha: .35), offset: const Offset(0, 16), blurRadius: 26, spreadRadius: -14),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(alignment: Alignment.center, children: [
                if (widget.sheen)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _sheen,
                      builder: (context, _) {
                        final t = (_sheen.value / .55).clamp(0.0, 1.0);
                        return Align(
                          alignment: Alignment(-1.6 + t * 3.2, 0),
                          child: Transform(
                            transform: Matrix4.skewX(-.35),
                            child: Container(width: 40, color: Colors.white.withValues(alpha: t > 0 && t < 1 ? .3 : 0)),
                          ),
                        );
                      },
                    ),
                  ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(widget.label, style: LText.b(widget.fontSize, weight: FontWeight.w600, color: l.fg, height: 1.2)),
                  if (widget.icon != null) ...[const SizedBox(width: 10), Icon(widget.icon, size: 18, color: l.fg)],
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ShineText: لمعة متحركة تمر على كلمة
// ═══════════════════════════════════════════════════════════════
class ShineText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final List<Color> colors;
  const ShineText(this.text, {super.key, required this.style, this.colors = const [LColors.teal, LColors.tealLight, Color(0xFF5FD4E8), LColors.teal]});

  @override
  State<ShineText> createState() => _ShineTextState();
}

class _ShineTextState extends State<ShineText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _c.stop();
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
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: widget.colors,
          transform: _SlideGradient(_c.value),
        ).createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
        child: child,
      ),
      child: Text(widget.text, style: widget.style.copyWith(color: Colors.white, shadows: const [])),
    );
  }
}

class _SlideGradient extends GradientTransform {
  final double t;
  const _SlideGradient(this.t);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

// ═══════════════════════════════════════════════════════════════
// PulseDot: نقطة تنبض (للعناوين الصغيرة والخريطة)
// ═══════════════════════════════════════════════════════════════
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final Duration delay;
  const PulseDot({super.key, required this.color, this.size = 8, this.delay = Duration.zero});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.repeat();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 3,
      height: s * 3,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(alignment: Alignment.center, children: [
          if (!reduceMotion(context))
            Container(
              width: s + s * 2 * _c.value,
              height: s + s * 2 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: .45 * (1 - _c.value))),
            ),
          Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color, border: Border.all(color: Colors.white, width: s > 10 ? 2.5 : 0))),
        ]),
      ),
    );
  }
}

/// عنوان صغير فوق الأقسام مع نقطة نابضة.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const Eyebrow(this.text, {super.key, this.bg = LColors.tealSoft, this.fg = LColors.teal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: fg.withValues(alpha: .2), offset: const Offset(0, 3))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        PulseDot(color: fg, size: 6),
        const SizedBox(width: 2),
        Text(text, style: LText.b(13.5, weight: FontWeight.w600, color: fg, height: 1.4)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// خلفية حيّة: بقع لونية تتحرك ببطء + نقاط شبكية
// ═══════════════════════════════════════════════════════════════
class LivingOrbs extends StatefulWidget {
  const LivingOrbs({super.key});
  @override
  State<LivingOrbs> createState() => _LivingOrbsState();
}

class _LivingOrbsState extends State<LivingOrbs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 30))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _orb(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)])),
      );

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = still ? 0.0 : _c.value * 2 * math.pi;
          return Stack(children: [
            Positioned(top: -160 + math.sin(t) * 60, right: -160 + math.cos(t) * 80, child: _orb(const Color(0x4D5FC9DF), 620)),
            Positioned(bottom: -200 + math.cos(t) * 50, left: -180 + math.sin(t) * 70, child: _orb(const Color(0x59E6C67A), 620)),
            Positioned(top: 520 + math.sin(t + 2) * 60, left: 300 + math.cos(t + 1) * 90, child: _orb(const Color(0x407E95D8), 480)),
          ]);
        },
      ),
    );
  }
}

class DotGridPainter extends CustomPainter {
  final Color color;
  final double gap;
  const DotGridPainter({this.color = const Color(0x12FFFFFF), this.gap = 26});
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (double y = gap / 2; y < size.height; y += gap) {
      for (double x = gap / 2; x < size.width; x += gap) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DotGridPainter old) => old.color != color || old.gap != gap;
}

// ═══════════════════════════════════════════════════════════════
// Marquee: شريط أسماء الخدمات يمرّ باستمرار ويتوقف عند المرور بالمؤشر
// ═══════════════════════════════════════════════════════════════
class Marquee extends StatefulWidget {
  final List<String> items;
  const Marquee({super.key, required this.items});
  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  final _sc = ScrollController();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((now) {
      final dt = (now - _last).inMicroseconds / 1e6;
      _last = now;
      if (_hover || !_sc.hasClients || reduceMotion(context)) return;
      _sc.jumpTo(_sc.offset + dt * 40);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _hover = true,
      onExit: (_) => _hover = false,
      child: Container(
        height: 44,
        decoration: const BoxDecoration(gradient: LColors.marqueeGradient),
        child: ListView.builder(
          controller: _sc,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, i) => Row(children: [
            Text(widget.items[i % widget.items.length], style: LText.h(15, weight: FontWeight.w700, color: Colors.white, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(width: 7, height: 7, decoration: BoxDecoration(color: LColors.goldLight, boxShadow: [BoxShadow(color: LColors.goldLight.withValues(alpha: .8), blurRadius: 10)])),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Reveal: يرتفع العنصر قليلاً عند ظهوره أول مرة (المحتوى ظاهر دائماً)
// ═══════════════════════════════════════════════════════════════
class Reveal extends StatefulWidget {
  final Widget child;
  final int index;
  const Reveal({super.key, required this.child, this.index = 0});
  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> {
  final _id = UniqueKey();
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return VisibilityDetector(
      key: _id,
      onVisibilityChanged: (info) {
        if (!_shown && info.visibleFraction > .15) {
          Future.delayed(Duration(milliseconds: 90 * widget.index), () {
            if (mounted) setState(() => _shown = true);
          });
        }
      },
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, .06),
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
