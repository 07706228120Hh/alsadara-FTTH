import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import 'sas_metrics.dart';

/// عدّاد **حلقي دائري مسطّح أنيق** لوحدة «وكيل الساس» — عرض فقط، بلا منطق أعمال.
///
/// يرسم قوساً نظيفاً مستدير الأطراف يحيط برقم متحرّك في المنتصف، بثيم الصدارة:
/// مسار خلفي خافت فاتح + قوس تقدّم بلون الشريحة بأطراف مستديرة — **بلا توهّج
/// ثقيل وبلا بروز**، نظيف ومسطّح.
///
/// ## البنية البصرية (في [_RingPainter])
/// - **مسار خلفي خافت (track)**: قوس كامل (300°) بلون الشريحة بشفافية منخفضة،
///   سماكة موحّدة، أطراف مستديرة ([StrokeCap.round]).
/// - **قوس التقدّم**: فوق المسار بلون الشريحة بأطراف مستديرة؛ يمتلئ بنسبة القيمة.
///
/// ## منطق النسبة (value / max)
/// - إن مُرِّر [max] موجب: نسبة الامتلاء = `value / max` (مقصوصة ضمن 0..1)،
///   وتُعرَض نسبة مئوية صغيرة تحت التسمية اختيارياً ([showPercent]).
/// - إن كان [max] معدوماً/غير مُمرَّر: حلقة **مزخرفة** ممتلئة (100%) — مرجعية.
/// - إن كانت القيمة نفسها **نسبة مئوية** (0..100 أو 0..1)، مرِّر
///   [valueIsPercent] = true فيُشتقّ الامتلاء من القيمة مباشرة.
///
/// ## السماكة ([strokeScale])
/// السماكة الافتراضية متناسبة مع القطر؛ النمط الفاخر [SasRingMetric.premium]
/// يكبّرها قليلاً لقوس سميك أنيق واضح.
///
/// ## الرقم المتحرّك المتزامن (count-up)
/// [TweenAnimationBuilder] يحرّك من القيمة **السابقة** إلى الجديدة
/// (`easeOutCubic` ~820ms) فلا وميض عند التحديث الدوري؛ وأول ظهور من 0. القوس
/// والرقم يتحرّكان معاً لأن الـpainter يتغذّى من نفس القيمة المتحرّكة كل إطار.
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

  /// لون المقياس (أخضر=نشط · برتقالي=منتهٍ · أزرق=متصل · إلخ).
  final Color color;

  /// أيقونة صغيرة أعلى الرقم في المنتصف.
  final IconData icon;

  /// نقرة اختيارية (تفعّل تفاعل المرور والمؤشّر).
  final VoidCallback? onTap;

  /// معامل سماكة القوس (1.0 = الافتراضي). قيمة أصغر ⇒ قوس أرفع وأنعم.
  final double strokeScale;

  /// حالة **«غير متاح»**: القيمة الفعلية لم تصل بعد (مثل المالية قبل التحميل).
  /// تُعرَض الحلقة بمسار خافت فقط (بلا قوس تقدّم) ونصّ «غير متاح» بدل الرقم.
  final bool unavailable;

  /// النمط **الفاخر «premium»** (للصف العلوي): قوس أسمك بتدرّج لوني راقٍ
  /// ([SweepGradient]) + توهّج ناعم خلفه + رقم مركزي أكبر + أيقونة أوضح.
  /// نظيف احترافي بلا بروز ثلاثي الأبعاد؛ `.thin` يبقى مسطّحاً رفيعاً كما هو.
  final bool premium;

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
    this.strokeScale = 1.0,
    this.unavailable = false,
    this.premium = false,
  });

  /// منشئ مختصر للنمط **الفاخر «premium»** (قوس أسمك + تدرّج + توهّج) — للصف
  /// العلوي في اللوحة. سماكة أكبر وضوحاً (`strokeScale = 1.35`).
  const SasRingMetric.premium({
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
    this.unavailable = false,
  })  : strokeScale = 1.35,
        premium = true;

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

    // micro-interaction هادئة: تكبير طفيف عند المرور (سطح المكتب).
    final interactive = MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.03 : 1.0,
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
    final premium = widget.premium;
    // سماكة متناسبة مع القطر؛ [strokeScale] يصغّرها لقوس رفيع أنيق، أو يكبّرها
    // للنمط الفاخر. حدّ أعلى أكبر في الفاخر ليبدو قوساً سميكاً أنيقاً.
    final stroke = (diameter * 0.085 * widget.strokeScale)
        .clamp(5.0, premium ? 18.0 : 16.0)
        .toDouble();

    // حالة «غير متاح»: لا حركة رقم ولا قوس تقدّم — مسار خافت ونصّ تمييزي ثابت.
    if (widget.unavailable) {
      return CustomPaint(
        painter: _RingPainter(
          fraction: 0,
          color: color,
          stroke: stroke,
          premium: premium,
          hover: _hover,
        ),
        child: _center(diameter, color, '', unavailable: true),
      );
    }

    return TweenAnimationBuilder<double>(
      // نحرّك من _from إلى value؛ المفتاح بالقيمة يعيد التشغيل عند التغيّر فقط.
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
            premium: premium,
            hover: _hover,
          ),
          child: _center(diameter, color, _format(animated)),
        );
      },
    );
  }

  /// محتوى المنتصف: أيقونة صغيرة + رقم متحرّك + تسمية (+ نسبة % اختيارية).
  /// كلّه ملفوف بـ [FittedBox] فيتقلّص في الخلايا الصغيرة بلا overflow.
  /// عند [unavailable] يُعرَض «غير متاح» بدل الرقم (بلا نسبة).
  Widget _center(double diameter, Color color, String numberText,
      {bool unavailable = false}) {
    // نحصر المحتوى داخل الدائرة الداخلية (المربّع المحاط بها) تفادياً للتصادم
    // مع القوس: نصف قطر داخلي ≈ 0.70 من القطر ⇒ ضلع مربّع = القطر × 0.70 /√2.
    final innerSide = diameter * 0.70 / math.sqrt2;
    final premium = widget.premium;
    // الفاخر: أيقونة ورقم أبرز قليلاً (الـ FittedBox يقلّصهما بأمان عند الضيق).
    final iconSize = premium ? 19.sp : 16.sp;
    final numberSize = premium ? 27.sp : 22.sp;
    final showPct = !unavailable &&
        widget.showPercent &&
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
              Icon(widget.icon,
                  color: unavailable ? color.withValues(alpha: 0.45) : color,
                  size: iconSize),
              SizedBox(height: premium ? 4.h : 3.h),
              if (unavailable)
                Text(
                  'غير متاح',
                  maxLines: 1,
                  style: GoogleFonts.cairo(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryColor.withValues(alpha: 0.55),
                    height: 1.02,
                  ),
                )
              else
                Text(
                  numberText,
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                  style: GoogleFonts.cairo(
                    fontSize: numberSize,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.02,
                    letterSpacing: 0.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              // تسمية داخلية اختيارية: تُحذف تماماً عند تمرير نصّ فارغ (مثل
              // عدّادات الصف العلوي التي يظهر عنوانها أسفل الحلقة) فلا يبقى فراغ.
              if (widget.label.isNotEmpty) ...[
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
              ],
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

/// رسّام الحلقة: مسار خافت فاتح + قوس تقدّم بلون الشريحة.
///
/// القوس يبدأ من أسفل يسار الحلقة ويمتدّ 300° (فجوة 60° في الأسفل) — شكل مقياس
/// نظيف مألوف. الأطراف مستديرة ([StrokeCap.round]).
///
/// النمط **الافتراضي/الرفيع** مسطّح نظيف (بلا توهّج/بروز). النمط **الفاخر
/// ([premium])** يضيف — دون بروز ثلاثي أبعاد أو حفر داخلي — طبقاتٍ أنيقة:
/// (1) توهّج ناعم خلف قوس التقدّم بلون المقياس (ألفا منخفضة + [MaskFilter.blur])
///     يقوى قليلاً عند المرور ([hover])؛
/// (2) قوس تقدّم بتدرّج [SweepGradient] من درجة أغمق قليلاً عند البداية إلى درجة
///     أزهى/أفتح عند النهاية ⇒ إحساس عمق مسطّح راقٍ؛
/// (3) نقطة ضوئية خافتة عند رأس القوس عند الامتلاء الجزئي.
class _RingPainter extends CustomPainter {
  /// نسبة امتلاء قوس التقدّم (0..1) — تتغذّى من القيمة المتحرّكة.
  final double fraction;
  final Color color;
  final double stroke;

  /// النمط الفاخر (تدرّج + توهّج + نقطة رأس) مقابل المسطّح الرفيع.
  final bool premium;

  /// مرور المؤشّر — يقوّي التوهّج قليلاً في النمط الفاخر فقط.
  final bool hover;

  _RingPainter({
    required this.fraction,
    required this.color,
    required this.stroke,
    this.premium = false,
    this.hover = false,
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

    // 1) المسار الخلفي الناعم (track): كامل الـ300° بلون المقياس بشفافية منخفضة.
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: premium ? 0.14 : 0.12);
    canvas.drawArc(rect, _startAngle, _sweepTotal, false, trackPaint);

    final sweep = (_sweepTotal * fraction).clamp(0.0, _sweepTotal);
    if (sweep <= 0) return;

    if (!premium) {
      // النمط المسطّح النظيف: قوس تقدّم بلون الشريحة بأطراف مستديرة (بلا توهّج).
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color;
      canvas.drawArc(rect, _startAngle, sweep, false, arcPaint);
      return;
    }

    // ── النمط الفاخر ──────────────────────────────────────────────────────

    // 2) توهّج ناعم خلف قوس التقدّم بلون المقياس (ألفا منخفضة + blur خفيف) —
    //    لمسة فخامة هادئة؛ يقوى قليلاً عند المرور فقط. لا بروز ولا حفر.
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: hover ? 0.42 : 0.26)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, hover ? 7.0 : 5.0);
    canvas.drawArc(rect, _startAngle, sweep, false, glowPaint);

    // 3) قوس التقدّم بتدرّج SweepGradient على امتداد القوس: أغمق قليلاً عند
    //    البداية ⇒ أزهى/أفتح عند النهاية (إحساس عمق مسطّح راقٍ، بلا ثلاثية أبعاد).
    final darker = Color.lerp(color, Colors.black, 0.18) ?? color;
    final brighter = Color.lerp(color, Colors.white, 0.26) ?? color;
    final gradient = SweepGradient(
      startAngle: _startAngle,
      endAngle: _startAngle + _sweepTotal,
      tileMode: TileMode.clamp,
      colors: [darker, color, brighter],
      stops: const [0.0, 0.55, 1.0],
      transform: GradientRotation(_startAngle),
    );
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = gradient.createShader(rect);
    canvas.drawArc(rect, _startAngle, sweep, false, arcPaint);

    // 4) نقطة ضوئية صغيرة خافتة عند رأس القوس عند الامتلاء الجزئي فقط.
    if (fraction > 0.02 && fraction < 0.995) {
      final headAngle = _startAngle + sweep;
      final head = Offset(
        center.dx + radius * math.cos(headAngle),
        center.dy + radius * math.sin(headAngle),
      );
      final dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: hover ? 0.95 : 0.80);
      canvas.drawCircle(head, stroke * 0.22, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.stroke != stroke ||
      old.premium != premium ||
      old.hover != hover;
}
