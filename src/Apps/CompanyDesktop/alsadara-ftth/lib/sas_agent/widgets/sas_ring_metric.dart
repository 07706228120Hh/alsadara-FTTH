import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import 'sas_metrics.dart';

/// عدّاد **حلقي دائري فاخر (radial ring gauge)** لوحدة «وكيل الساس» —
/// عرض فقط، بلا منطق أعمال.
///
/// بديلٌ بصريّ فاخر لبطاقة العدّاد المستطيلة ([SasMetricCard])؛ يرسم قوساً
/// متدرّجاً مستدير الأطراف يحيط برقم متحرّك في المنتصف.
///
/// ## البنية البصرية (كلّها في [CustomPainter] واحد — [_RingPainter])
/// - **مسار خلفي خافت (track)**: قوس كامل (300°) بلون المقياس بشفافية منخفضة،
///   سماكة موحّدة، أطراف مستديرة ([StrokeCap.round]).
/// - **قوس التقدّم**: فوق المسار، بتدرّج لوني ([SweepGradient] كـ shader على
///   نفس القوس) من درجة داكنة إلى فاتحة من لون المقياس؛ يمتلئ بنسبة القيمة.
/// - **توهّج ملوّن (glow)**: طبقة قوس إضافية بلون المقياس + [MaskFilter.blur]
///   خلف قوس التقدّم لإحساس الإضاءة (يقوى قليلاً عند المرور).
///
/// ## منطق النسبة (value / max)
/// - إن مُرِّر [max] موجب: نسبة الامتلاء = `value / max` (مقصوصة ضمن 0..1)،
///   وتُعرَض نسبة مئوية صغيرة تحت التسمية اختيارياً ([showPercent]).
/// - إن كان [max] معدوماً/غير مُمرَّر: حلقة **مزخرفة** ممتلئة (100%) — مرجعية
///   (مثل بطاقة «الإجمالي») أو للمالية غير النسبية، بلا دلالة نسبة.
/// - إن كانت القيمة نفسها **نسبة مئوية** (0..100 أو 0..1)، مرِّر
///   [valueIsPercent] = true فيُشتقّ الامتلاء من القيمة مباشرة.
///
/// ## الرقم المتحرّك المتزامن (count-up)
/// نفس منطق [SasMetricCard]: [TweenAnimationBuilder] يحرّك من القيمة **السابقة**
/// إلى الجديدة (منحنى `easeOutCubic` ~820ms) فلا وميض عند التحديث الدوري؛ وأول
/// ظهور من 0. **القوس والرقم يتحرّكان معاً** لأن الـpainter يتغذّى من نفس القيمة
/// المتحرّكة في كل إطار.
///
/// ## منع الـoverflow في الشبكة 2×2
/// الودجت تملأ خليّتها عبر [LayoutBuilder]: تحسب قطراً = أصغر بُعد متاح، ثم
/// تُقلّص السماكة/أحجام الخطوط تناسبياً مع القطر. النصّ الداخلي ملفوف بـ
/// [FittedBox]`(scaleDown)` فيتقلّص بدل أن يفيض. لا مقاسات ثابتة كبيرة، فلا
/// [RenderFlex] overflow مهما ضاقت الخليّة ضمن المقاسات المعقولة.
///
/// ## الأداء
/// حركة عبر [TweenAnimationBuilder] لمرّة واحدة عند تغيّر القيمة فقط (لا
/// [AnimationController] دائم، لا تسريب). [_RingPainter.shouldRepaint] يُعيد
/// الرسم فقط عند تغيّر القيمة المتحرّكة/اللون/المرور.
class SasRingMetric extends StatefulWidget {
  /// القيمة العددية الحالية (يُحرّك العدّاد والقوس نحوها).
  final num value;

  /// الحدّ الأقصى للامتلاء (اختياري). موجب ⇒ الامتلاء = value/max.
  /// معدوم/غير مُمرَّر ⇒ حلقة مزخرفة ممتلئة (مرجع).
  final num? max;

  /// القيمة نفسها نسبة مئوية (0..100 أو 0..1) ⇒ يُشتقّ الامتلاء منها مباشرة.
  final bool valueIsPercent;

  /// إظهار نسبة مئوية صغيرة تحت التسمية (عندما تكون النسبة ذات دلالة).
  final bool showPercent;

  /// منسّق العرض للرقم المتحرّك في المنتصف. الافتراضي: عدد صحيح.
  /// يُستدعى على القيمة **المتحرّكة** كل إطار.
  final String Function(num animatedValue)? formatter;

  /// التسمية أسفل الرقم.
  final String label;

  /// لون المقياس (أخضر=نشط · برتقالي=منتهٍ · أزرق=متصل · بنفسجي=إجمالي…).
  final Color color;

  /// أيقونة صغيرة أعلى الرقم في المنتصف.
  final IconData icon;

  /// نقرة اختيارية (تفعّل تفاعل المرور والمؤشّر).
  final VoidCallback? onTap;

  const SasRingMetric({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
    this.max,
    this.valueIsPercent = false,
    this.showPercent = false,
    this.formatter,
    this.onTap,
  });

  @override
  State<SasRingMetric> createState() => _SasRingMetricState();
}

class _SasRingMetricState extends State<SasRingMetric> {
  /// القيمة التي بدأت منها الحركة الحالية — تمنع البدء من الصفر عند كل تحديث
  /// دوري (فلا وميض)؛ أوّل ظهور فقط من 0.
  late num _from;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _from = 0;
  }

  @override
  void didUpdateWidget(covariant SasRingMetric old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = old.value;
    }
  }

  String _format(num v) => widget.formatter?.call(v) ?? '${v.round()}';

  /// نسبة الامتلاء المستهدفة (0..1) من القيمة النهائية — لِعرض «%» الثابت.
  double get _targetFraction => _fractionFor(widget.value);

  /// يشتقّ نسبة الامتلاء (0..1) لقيمة مُعطاة حسب النمط (نسبة/max/مرجع).
  double _fractionFor(num v) {
    if (widget.valueIsPercent) {
      final p = v.toDouble();
      final norm = p > 1.0 ? p / 100.0 : p; // يقبل 0..100 أو 0..1.
      return norm.clamp(0.0, 1.0);
    }
    final max = widget.max;
    if (max != null && max > 0) {
      return (v / max).clamp(0.0, 1.0).toDouble();
    }
    return 1.0; // مرجع/مزخرف: حلقة ممتلئة.
  }

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onTap != null;

    final content = LayoutBuilder(
      builder: (context, c) {
        // القطر = أصغر بُعد متاح (يتقلّص بأمان في الخلايا الصغيرة).
        final diameter = math.min(c.maxWidth, c.maxHeight);
        return Center(
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: _ring(diameter),
          ),
        );
      },
    );

    // micro-interaction: تكبير طفيف + رفع التوهّج عند المرور (سطح المكتب).
    final interactive = MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.035 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: content,
      ),
    );

    if (!tappable) return interactive;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: interactive,
      ),
    );
  }

  /// الحلقة الكاملة: قوس مرسوم ([CustomPaint]) + محتوى المنتصف فوقه.
  Widget _ring(double diameter) {
    final color = widget.color;
    // سماكة/أحجام متناسبة مع القطر (تتقلّص في الخلايا الصغيرة).
    final stroke = (diameter * 0.085).clamp(6.0, 15.0);

    return TweenAnimationBuilder<double>(
      // نحرّك من _from إلى value؛ المفتاح بالقيمة يعيد التشغيل عند التغيّر فقط
      // (لا AnimationController دائم — حركة لمرّة واحدة).
      key: ValueKey<num>(widget.value),
      tween: Tween<double>(
        begin: _from.toDouble(),
        end: widget.value.toDouble(),
      ),
      duration: const Duration(milliseconds: 820),
      curve: Curves.easeOutCubic,
      builder: (context, animated, _) {
        // القوس يتحرّك متزامناً مع الرقم: نشتقّ نسبته من القيمة المتحرّكة نفسها.
        final fraction = _fractionFor(animated);
        return CustomPaint(
          painter: _RingPainter(
            fraction: fraction,
            color: color,
            stroke: stroke,
            hover: _hover,
          ),
          child: _center(diameter, color, _format(animated)),
        );
      },
    );
  }

  /// محتوى المنتصف: أيقونة صغيرة + رقم متحرّك + تسمية (+ نسبة % اختيارية).
  /// كلّه ملفوف بـ [FittedBox] فيتقلّص في الخلايا الصغيرة بلا overflow.
  Widget _center(double diameter, Color color, String numberText) {
    // نحصر المحتوى داخل الدائرة الداخلية (المربّع المحاط بها) تفادياً للتصادم
    // مع القوس: نصف قطر داخلي ≈ 0.66 من القطر ⇒ ضلع مربّع = القطر × 0.66 /√2.
    final innerSide = diameter * 0.66 / math.sqrt2;
    final showPct = widget.showPercent &&
        !widget.valueIsPercent &&
        (widget.max != null && widget.max! > 0);
    return Center(
      child: SizedBox(
        width: innerSide,
        height: innerSide,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, color: color, size: 16.sp),
              SizedBox(height: 3.h),
              Text(
                numberText,
                maxLines: 1,
                style: GoogleFonts.cairo(
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.02,
                  letterSpacing: 0.2,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                widget.label,
                maxLines: 1,
                style: GoogleFonts.cairo(
                  fontSize: 10.sp,
                  color: AppTheme.primaryColor.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (showPct) ...[
                SizedBox(height: 1.h),
                Text(
                  '${(_targetFraction * 100).round()}%',
                  maxLines: 1,
                  style: GoogleFonts.cairo(
                    fontSize: 9.sp,
                    color: color.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// رسّام الحلقة: مسار خافت + قوس تقدّم متدرّج + توهّج ملوّن.
///
/// القوس يبدأ من أسفل الحلقة ويمتدّ 300° (فجوة 60° في الأسفل) — شكل مقياس
/// فاخر مألوف. الأطراف مستديرة ([StrokeCap.round]).
class _RingPainter extends CustomPainter {
  /// نسبة امتلاء قوس التقدّم (0..1) — تتغذّى من القيمة المتحرّكة.
  final double fraction;
  final Color color;
  final double stroke;
  final bool hover;

  _RingPainter({
    required this.fraction,
    required this.color,
    required this.stroke,
    required this.hover,
  });

  // زاوية بداية القوس (أسفل يسار، 135°) وامتداده الكلّي (300° = فجوة 60° أسفل).
  static const double _startAngle = math.pi * 135 / 180; // 135°
  static const double _sweepTotal = math.pi * 300 / 180; // 300° (= 5π/3)

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    if (radius <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1) المسار الخلفي الخافت (track): كامل الـ300°.
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.13);
    canvas.drawArc(rect, _startAngle, _sweepTotal, false, trackPaint);

    final sweep = (_sweepTotal * fraction).clamp(0.0, _sweepTotal);
    if (sweep <= 0) return;

    // 2) توهّج ملوّن (glow) خلف قوس التقدّم — طبقة مموّهة بلون المقياس.
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: hover ? 0.55 : 0.38)
      ..maskFilter =
          MaskFilter.blur(BlurStyle.normal, hover ? stroke * 0.85 : stroke * 0.6);
    canvas.drawArc(rect, _startAngle, sweep, false, glowPaint);

    // 3) قوس التقدّم بتدرّج لوني (SweepGradient shader محاذٍ لبداية القوس).
    final gradient = SweepGradient(
      startAngle: _startAngle,
      endAngle: _startAngle + _sweepTotal,
      tileMode: TileMode.clamp,
      colors: [
        _shade(color, -0.18), // درجة داكنة عند البداية.
        color,
        _shade(color, 0.28), // درجة فاتحة/مشعّة عند النهاية.
      ],
      stops: const [0.0, 0.55, 1.0],
    );
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = gradient.createShader(rect);
    canvas.drawArc(rect, _startAngle, sweep, false, arcPaint);

    // 4) نقطة مضيئة صغيرة عند رأس القوس (لمسة premium) عند الامتلاء الجزئي.
    if (fraction > 0.02 && fraction < 0.999) {
      final tipAngle = _startAngle + sweep;
      final tip = Offset(
        center.dx + radius * math.cos(tipAngle),
        center.dy + radius * math.sin(tipAngle),
      );
      final tipPaint = Paint()
        ..color = _shade(color, 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(tip, stroke * 0.32, tipPaint);
    }
  }

  /// يفتّح/يعتّم اللون بنسبة [amount] (+فاتح / -داكن) عبر مزج بالأبيض/الأسود.
  Color _shade(Color c, double amount) {
    if (amount >= 0) {
      return Color.lerp(c, Colors.white, amount) ?? c;
    }
    return Color.lerp(c, Colors.black, -amount) ?? c;
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.stroke != stroke ||
      old.hover != hover;
}
