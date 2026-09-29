import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../config.dart';
import '../theme/brand.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// شعار التطبيق: مربّع بتدرّج اللكنة + أيقونة الهوية.
class BrandMark extends StatelessWidget {
  final AppBrand brand;
  final double size;
  final bool glow;
  const BrandMark({super.key, required this.brand, this.size = 56, this.glow = true});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: brand.gradient(b),
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: glow ? Elev.glow(brand.accentFor(b), 0.35) : null,
      ),
      child: Icon(brand.iconFill, color: Colors.white, size: size * 0.52),
    );
  }
}

/// شارة الهوية: الشعار + اسم التطبيق + اسم المنصّة (تُستخدم في الشريط العلوي والدخول).
class BrandBadge extends StatelessWidget {
  final AppBrand brand;
  final bool showPlatform;
  final double markSize;
  final MainAxisAlignment alignment;
  const BrandBadge({
    super.key,
    required this.brand,
    this.showPlatform = true,
    this.markSize = 40,
    this.alignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: alignment, children: [
      BrandMark(brand: brand, size: markSize, glow: false),
      const SizedBox(width: Space.md),
      // Flexible + ellipsis: لا تتجاوز الشارة عرضها المتاح (شريط AppBar ضيّق على الموبايل).
      Flexible(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(brand.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
          if (showPlatform)
            Text(PlatformConfig.platformName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodySmall?.copyWith(color: context.pal.textMuted, height: 1.2)),
        ]),
      ),
    ]);
  }
}

/// شارة صغيرة «بيئة تطوير» تظهر فقط عندما يكون عنوان الباكند محلياً.
class EnvBadge extends StatelessWidget {
  const EnvBadge({super.key});
  @override
  Widget build(BuildContext context) {
    if (!PlatformConfig.isDevEnvironment) return const SizedBox.shrink();
    final pal = context.pal;
    return Tooltip(
      message: PlatformConfig.apiBase,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: pal.warning.withValues(alpha: 0.14),
          borderRadius: Radii.rSm,
          border: Border.all(color: pal.warning.withValues(alpha: 0.4)),
        ),
        child: Text('بيئة تطوير',
            style: TextStyle(color: pal.warning, fontWeight: FontWeight.w700, fontSize: 11.5, height: 1.2)),
      ),
    );
  }
}

/// حركة دخول: تلاشٍ + انزلاق خفيف من الأسفل (تحترم تقليل الحركة).
class FadeSlide extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  const FadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Motion.slow,
    this.offsetY = 18,
  });
  @override
  State<FadeSlide> createState() => _FadeSlideState();
}

class _FadeSlideState extends State<FadeSlide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Motion.curve);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(offset: Offset(0, widget.offsetY * (1 - _a.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// خلفية رقمية: شبكة إحداثيات خافتة + عُقَد متّصلة (شبكة اتصالات) بانجراف بطيء.
/// [t] قيمة الحركة 0..1 — تُمرَّر من AnimationController، أو تُترك ثابتة.
class DigitalBackground extends StatelessWidget {
  final double t;
  final Color? color;
  const DigitalBackground({super.key, this.t = 0, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NetPainter(t, color ?? Colors.white),
      size: Size.infinite,
      isComplex: true,
      willChange: t != 0,
    );
  }
}

class _NetPainter extends CustomPainter {
  final double t;
  final Color color;
  _NetPainter(this.t, this.color);

  static const List<Offset> _base = [
    Offset(0.08, 0.18), Offset(0.20, 0.42), Offset(0.14, 0.75),
    Offset(0.32, 0.62), Offset(0.30, 0.15), Offset(0.46, 0.35),
    Offset(0.52, 0.72), Offset(0.66, 0.22), Offset(0.68, 0.55),
    Offset(0.80, 0.40), Offset(0.86, 0.72), Offset(0.92, 0.20),
    Offset(0.58, 0.10), Offset(0.40, 0.88), Offset(0.74, 0.86),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    const step = 54.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final pts = <Offset>[];
    for (var i = 0; i < _base.length; i++) {
      final b = _base[i];
      final dx = math.sin(t * 2 * math.pi + i) * 10;
      final dy = math.cos(t * 2 * math.pi + i * 1.3) * 10;
      pts.add(Offset(b.dx * size.width + dx, b.dy * size.height + dy));
    }
    final linkMax = size.shortestSide * 0.28;
    for (var i = 0; i < pts.length; i++) {
      for (var j = i + 1; j < pts.length; j++) {
        final d = (pts[i] - pts[j]).distance;
        if (d < linkMax) {
          canvas.drawLine(
            pts[i],
            pts[j],
            Paint()
              ..color = color.withValues(alpha: (1 - d / linkMax) * 0.25)
              ..strokeWidth = 1,
          );
        }
      }
    }
    for (var i = 0; i < pts.length; i++) {
      final big = i % 4 == 0;
      final r = big ? 4.5 : 2.5;
      canvas.drawCircle(
        pts[i],
        r * 2.6,
        Paint()
          ..color = color.withValues(alpha: big ? 0.30 : 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(pts[i], r, Paint()..color = color.withValues(alpha: big ? 0.9 : 0.6));
    }
  }

  @override
  bool shouldRepaint(covariant _NetPainter old) => old.t != t || old.color != color;
}

/// لوحة هوية بتدرّج اللكنة وخلفية رقمية — تُستخدم في شاشة الدخول (الشاشات العريضة) والبوّابة.
class BrandPanel extends StatelessWidget {
  final AppBrand brand;
  final Widget? child;
  final double animation;
  const BrandPanel({super.key, required this.brand, this.child, this.animation = 0});

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final accent = brand.accentFor(b);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color.lerp(accent, const Color(0xFF0B1220), 0.35)!,
            const Color(0xFF0B1220),
          ],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        Positioned.fill(child: DigitalBackground(t: animation, color: Colors.white)),
        Align(
          alignment: const Alignment(0.8, -0.9),
          child: Container(
            width: 320,
            height: 320,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [accent.withValues(alpha: 0.45), accent.withValues(alpha: 0)]),
            ),
          ),
        ),
        if (child != null) child!,
      ]),
    );
  }
}

/// نص أحادي المسافة للأرقام/المعرّفات — LTR دائماً.
class MonoText extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;
  const MonoText(this.text, {super.key, this.size = 13, this.color, this.weight = FontWeight.w500});
  @override
  Widget build(BuildContext context) => Text(
        text,
        textDirection: TextDirection.ltr,
        style: PlatformType.mono(size: size, color: color ?? context.pal.text, weight: weight),
      );
}
