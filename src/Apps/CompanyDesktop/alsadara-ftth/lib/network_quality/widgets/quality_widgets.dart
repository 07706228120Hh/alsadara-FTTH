/// ودجات مشتركة لوحدة فحص الجودة — Network Quality
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/quality_models.dart';
import '../../frontend/tokens/sd_colors.dart' show SdColors;

/// لون التقييم.
Color ratingColor(QualityRating r) {
  switch (r) {
    case QualityRating.excellent:
      return SdColors.success;
    case QualityRating.good:
      return const Color(0xFF66BB6A);
    case QualityRating.fair:
      return SdColors.warning;
    case QualityRating.poor:
      return SdColors.warning;
    case QualityRating.bad:
      return SdColors.danger;
    case QualityRating.unknown:
      return const Color(0xFF9E9E9E);
  }
}

/// لون التقييم بدرجة فاتحة واضحة على الخلفيات الداكنة (البطل) — تباين أعلى.
Color ratingColorOnDark(QualityRating r) {
  switch (r) {
    case QualityRating.excellent:
      return const Color(0xFF81C784); // أخضر فاتح
    case QualityRating.good:
      return const Color(0xFF9CCC65); // أخضر ليموني
    case QualityRating.fair:
      return const Color(0xFFFFD54F); // كهرماني فاتح
    case QualityRating.poor:
      return const Color(0xFFFFB74D); // برتقالي فاتح
    case QualityRating.bad:
      return const Color(0xFFE57373); // أحمر فاتح
    case QualityRating.unknown:
      return const Color(0xFFB0BEC5); // رمادي فاتح
  }
}

IconData ratingIcon(QualityRating r) {
  switch (r) {
    case QualityRating.excellent:
      return Icons.verified_rounded;
    case QualityRating.good:
      return Icons.check_circle_rounded;
    case QualityRating.fair:
      return Icons.info_rounded;
    case QualityRating.poor:
      return Icons.warning_amber_rounded;
    case QualityRating.bad:
      return Icons.error_rounded;
    case QualityRating.unknown:
      return Icons.help_outline_rounded;
  }
}

/// مقياس دائري للدرجة الكلّية (0..100).
class ScoreGauge extends StatelessWidget {
  final double score; // 0..100
  final QualityRating rating;
  final double size;
  final bool onDark; // على خلفية داكنة (البطل)

  const ScoreGauge({
    super.key,
    required this.score,
    required this.rating,
    this.size = 180,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = ratingColor(rating);
    // على الخلفية الداكنة نرفع إضاءة اللون قليلاً لضمان التباين.
    final numberColor = onDark
        ? Color.lerp(color, Colors.white, 0.25)!
        : color;
    final trackColor =
        onDark ? Colors.white.withValues(alpha: 0.14) : SdColors.divider;
    final hintColor =
        onDark ? Colors.white.withValues(alpha: 0.6) : SdColors.faint;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(score / 100, color, trackColor),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.round().toString(),
                style: TextStyle(
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.w900,
                  color: numberColor,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rating.arabicLabel,
                style: TextStyle(
                  fontSize: size * 0.11,
                  fontWeight: FontWeight.w700,
                  color: numberColor,
                ),
              ),
              Text('من 100',
                  style: TextStyle(
                      fontSize: size * 0.07, color: hintColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double fraction; // 0..1
  final Color color;
  final Color trackColor;
  _GaugePainter(this.fraction, this.color, [this.trackColor = SdColors.divider]);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const start = math.pi * 0.75;
    const sweepMax = math.pi * 1.5;

    final bg = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius), start, sweepMax, false, bg);

    final fg = Paint()
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0.6), color],
        startAngle: start,
        endAngle: start + sweepMax,
        transform: GradientRotation(start),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start,
        sweepMax * fraction.clamp(0, 1), false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.trackColor != trackColor;
}

/// بطاقة قسم بنظام موحّد أنيق: شريط accent علوي رفيع + رأس احترافي (أيقونة داخل
/// شريحة ملوّنة + عنوان + عنوان فرعي اختياري + شارة حالة trailing) + محتوى.
class SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color? accent;
  final Widget child;
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = accent ?? SdColors.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 7, 12, 12),
      // بطاقة «مادّية» بارزة: حافّة سفلية صلبة + توهّج ناعم (تصميم ثلاثي الأبعاد).
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0xFFD6DBEA), offset: Offset(0, 5)),
          BoxShadow(
              color: Color(0x661A237E),
              offset: Offset(0, 17),
              blurRadius: 22,
              spreadRadius: -16),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Row(
                children: [
                  // مربّع أيقونة بارز بحافّة سفلية.
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                          c.withValues(alpha: 0.12), Colors.white),
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(
                            color: Color.alphaBlend(
                                c.withValues(alpha: 0.28), Colors.white),
                            offset: const Offset(0, 3)),
                      ],
                    ),
                    child: Icon(icon, color: c, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: Color(0xFF1B1E2B))),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(subtitle!,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: SdColors.faint)),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 2, 12, 14),
                child: child),
          ],
        ),
      ),
    );
  }
}

/// يفصل القيمة المعروضة إلى رقم ووحدة (مثل "57.9 Mbps" → "57.9" + "Mbps").
({String number, String unit}) splitValueUnit(String v) {
  final t = v.trim();
  final m = RegExp(r'^(-?[\d.,]+)\s*(.*)$').firstMatch(t);
  if (m != null && m.group(1)!.isNotEmpty) {
    return (number: m.group(1)!, unit: m.group(2)!.trim());
  }
  return (number: t, unit: '');
}

/// شارة حالة التقييم (ممتاز/جيد/...). [onDark] يستخدم درجة لون فاتحة للخلفية
/// الداكنة (البطل) لرفع التباين.
class RatingBadge extends StatelessWidget {
  final QualityRating rating;
  final double fontSize;
  final bool onDark;
  const RatingBadge(this.rating,
      {super.key, this.fontSize = 10, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final c = onDark ? ratingColorOnDark(rating) : ratingColor(rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: onDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: c.withValues(alpha: onDark ? 0.55 : 0.35), width: 1)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ratingIcon(rating), color: c, size: fontSize + 2),
          const SizedBox(width: 4),
          Text(rating.arabicLabel,
              style: TextStyle(
                  fontSize: fontSize, fontWeight: FontWeight.w800, color: c)),
        ],
      ),
    );
  }
}

/// رقم تقني بارز مع وحدة صغيرة بجانبه.
class ValueUnit extends StatelessWidget {
  final String display;
  final Color color;
  final double numberSize;
  const ValueUnit(this.display,
      {super.key, required this.color, this.numberSize = 17});

  @override
  Widget build(BuildContext context) {
    final p = splitValueUnit(display);
    return Row(
      mainAxisSize: MainAxisSize.min,
      textBaseline: TextBaseline.alphabetic,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      children: [
        Text(p.number,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: numberSize,
                fontFamily: 'monospace',
                color: color,
                height: 1)),
        if (p.unit.isNotEmpty) ...[
          const SizedBox(width: 3),
          Text(p.unit,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: numberSize * 0.6,
                  color: color.withValues(alpha: 0.75))),
        ],
      ],
    );
  }
}

/// صف مقياس مفرد مع تقييم ملوّن وطابع تقني.
class MetricTile extends StatelessWidget {
  final MetricResult metric;
  final Widget? rangeBar; // مؤشّر نطاق بصري اختياري أسفل الصف (SignalRangeBar/HealthBandBar)
  const MetricTile(this.metric, {super.key, this.rangeBar});

  @override
  Widget build(BuildContext context) {
    final c = ratingColor(metric.rating);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border(right: BorderSide(color: c, width: 3.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(ratingIcon(metric.rating), color: c, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    if (metric.note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(metric.note!,
                            style: TextStyle(
                                fontSize: 10.5, color: SdColors.muted)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ValueUnit(metric.displayValue, color: c),
                  const SizedBox(height: 3),
                  RatingBadge(metric.rating),
                ],
              ),
            ],
          ),
          if (rangeBar != null) ...[
            const SizedBox(height: 8),
            rangeBar!,
          ],
        ],
      ),
    );
  }
}

/// شريط نطاق بصري يوضّح موقع القيمة ضمن مدى (مثل Rx dBm أو Ping).
/// [fraction] موقع المؤشّر 0..1 (0 = بداية المدى، 1 = نهايته).
class SignalRangeBar extends StatelessWidget {
  final double fraction;
  final QualityRating rating;
  final String startLabel;
  final String endLabel;
  final String? valueLabel; // شريحة قيمة اختيارية فوق المؤشّر
  final List<Color> gradientColors;
  const SignalRangeBar({
    super.key,
    required this.fraction,
    required this.rating,
    required this.startLabel,
    required this.endLabel,
    this.valueLabel,
    // الافتراضي: المدى الطرفاه سيّئان والوسط هو الأفضل (مناسب لـRx الضوئي).
    this.gradientColors = const [
      SdColors.danger,
      SdColors.warning,
      SdColors.success,
      SdColors.warning,
      SdColors.danger,
    ],
  });

  @override
  Widget build(BuildContext context) {
    final c = ratingColor(rating);
    final f = fraction.clamp(0.0, 1.0);
    // الشريط يُرسم باتجاه LTR لثبات دلالة المدى (الرقم يسار↦يمين).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (ctx, cons) {
              final w = cons.maxWidth;
              final x = f * w;
              final hasChip = valueLabel != null;
              return SizedBox(
                height: hasChip ? 40 : 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // شريحة القيمة فوق المؤشّر.
                    if (hasChip)
                      Positioned(
                        top: 0,
                        left: (x - 26).clamp(0.0, w - 52),
                        child: Container(
                          width: 52,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                  color: c.withValues(alpha: 0.4),
                                  blurRadius: 5),
                            ],
                          ),
                          child: Text(valueLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace')),
                        ),
                      ),
                    // المسار المتدرّج.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: hasChip ? 26 : 7,
                      child: Container(
                        height: 7,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          gradient: LinearGradient(colors: gradientColors),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 2,
                                offset: const Offset(0, 1)),
                          ],
                        ),
                      ),
                    ),
                    // المؤشّر «thumb» بتوهّج خفيف.
                    Positioned(
                      left: (x - 9).clamp(0.0, w - 18),
                      top: hasChip ? 20 : 1,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: c, width: 3.5),
                          boxShadow: [
                            BoxShadow(
                                color: c.withValues(alpha: 0.5),
                                blurRadius: 7),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(startLabel,
                  style: TextStyle(
                      fontSize: 9.5,
                      color: SdColors.faint,
                      fontFamily: 'monospace')),
              Text(endLabel,
                  style: TextStyle(
                      fontSize: 9.5,
                      color: SdColors.faint,
                      fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }
}

/// بطاقة إحصائية بارزة (لسرعة التنزيل/الرفع) بطابع تقني.
class BigStatTile extends StatelessWidget {
  final String label;
  final String display; // القيمة مع الوحدة ("57.9 Mbps" أو "—")
  final IconData icon;
  final QualityRating rating;
  const BigStatTile({
    super.key,
    required this.label,
    required this.display,
    required this.icon,
    required this.rating,
  });

  @override
  Widget build(BuildContext context) {
    final c = ratingColor(rating);
    final p = splitValueUnit(display);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [c.withValues(alpha: 0.14), c.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: SdColors.muted)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(p.number,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      color: c,
                      height: 1)),
              if (p.unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(p.unit,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.withValues(alpha: 0.7))),
              ],
            ],
          ),
          const SizedBox(height: 8),
          RatingBadge(rating),
        ],
      ),
    );
  }
}

/// صف معلومة بسيط (مفتاح/قيمة) بلا تقييم.
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const InfoRow(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: TextStyle(fontSize: 12, color: SdColors.muted)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
//  ودجات التصميم الاحترافي (طراز Speedtest) — البطل والمخططات والمؤشّرات
// ════════════════════════════════════════════════════════════════════════

/// عدّاد سرعة نصف‑دائري (Speedometer) بـCustomPaint — لمعدّل نقل البيانات.
///
/// يرسم قوساً علوياً (180°) مع خلفية مسار ومؤشّر معبّأ ملوّن + علامات صغيرة،
/// ويعرض الرقم العملاق ووحدته في فتحة القوس. [value] بوحدة Mbps (null ⇒ «—»).
class Speedometer extends StatelessWidget {
  final double? value; // Mbps
  final double maxValue; // أقصى قيمة للمقياس
  final QualityRating rating;
  final String caption; // نص أسفل الرقم (مثل «تنزيل»)
  final IconData icon;
  final double size; // العرض
  final bool onDark;
  // لون accent صريح للقوس (يتجاوز لون التقييم) — لتمييز التنزيل عن الرفع
  // بلونين حيويين عاليَي التباين على الخلفية الداكنة.
  final Color? accentColor;

  const Speedometer({
    super.key,
    required this.value,
    required this.rating,
    required this.caption,
    required this.icon,
    this.maxValue = 200,
    this.size = 220,
    this.onDark = true,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = ratingColor(rating);
    final arcColor = accentColor ??
        (onDark ? Color.lerp(color, Colors.white, 0.18)! : color);
    // مسار غير مُعبّأ شفّاف فاتح يبرز التعبئة بوضوح.
    final trackColor =
        onDark ? Colors.white.withValues(alpha: 0.16) : SdColors.divider;
    final tickColor =
        onDark ? Colors.white.withValues(alpha: 0.30) : SdColors.faint;
    // مقياس لوغاريتمي-لطيف: يمنع تكدّس القيم الصغيرة ويحتوي الكبيرة.
    final v = value ?? 0;
    final frac = maxValue <= 0
        ? 0.0
        : (math.sqrt((v / maxValue).clamp(0.0, 1.0))).clamp(0.0, 1.0);
    final hasValue = value != null;
    final numberText = !hasValue
        ? '—'
        : (v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
    final numColor = onDark ? Colors.white : color;

    return SizedBox(
      width: size,
      height: size * 0.66,
      child: CustomPaint(
        painter: _SpeedometerPainter(
          hasValue ? frac : 0,
          arcColor,
          trackColor,
          tickColor,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: size * 0.02),
            // عرض الأرقام محصور ضمن عرض العدّاد؛ FittedBox يضمن عدم أي تجاوز
            // مهما اختلفت مقاييس الخطوط (خاصّةً في بيئة الاختبار).
            child: SizedBox(
              width: size * 0.9,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          numberText,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w900,
                            fontSize: size * 0.20,
                            height: 1,
                            color: numColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Mbps',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: size * 0.065,
                            color: numColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon,
                            size: size * 0.07,
                            color: numColor.withValues(alpha: 0.8)),
                        const SizedBox(width: 4),
                        Text(
                          caption,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: size * 0.062,
                            color: numColor.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedometerPainter extends CustomPainter {
  final double fraction; // 0..1
  final Color arcColor;
  final Color trackColor;
  final Color tickColor;
  _SpeedometerPainter(
      this.fraction, this.arcColor, this.trackColor, this.tickColor);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final radius = size.width / 2 - stroke / 2 - 2;
    final center = Offset(size.width / 2, radius + stroke / 2 + 2);
    const start = math.pi; // 180° (يسار)
    const sweep = math.pi; // علوي حتى 360° (يمين)
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, start, sweep, false, track);

    // علامات صغيرة على طول القوس.
    final tick = Paint()
      ..color = tickColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    const ticks = 10;
    for (var i = 0; i <= ticks; i++) {
      final a = start + sweep * (i / ticks);
      final outer = Offset(
        center.dx + (radius - stroke / 2 - 2) * math.cos(a),
        center.dy + (radius - stroke / 2 - 2) * math.sin(a),
      );
      final inner = Offset(
        center.dx + (radius - stroke / 2 - 7) * math.cos(a),
        center.dy + (radius - stroke / 2 - 7) * math.sin(a),
      );
      canvas.drawLine(inner, outer, tick);
    }

    if (fraction > 0) {
      final fg = Paint()
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [arcColor.withValues(alpha: 0.55), arcColor],
          transform: const GradientRotation(math.pi),
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep * fraction.clamp(0, 1), false, fg);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedometerPainter old) =>
      old.fraction != fraction ||
      old.arcColor != arcColor ||
      old.trackColor != trackColor ||
      old.tickColor != tickColor;
}

/// شريحة مقياس صغيرة (Ping/Jitter/فقدان/DNS) ملوّنة بالتقييم — للبطل.
class MiniMetricChip extends StatelessWidget {
  final String label;
  final String value;
  final QualityRating rating;
  final IconData icon;
  final bool onDark;
  const MiniMetricChip({
    super.key,
    required this.label,
    required this.value,
    required this.rating,
    required this.icon,
    this.onDark = true,
  });

  @override
  Widget build(BuildContext context) {
    // على الداكن نستخدم درجة التقييم الفاتحة لرفع التباين.
    final accent = onDark ? ratingColorOnDark(rating) : ratingColor(rating);
    final c = accent;
    final bg = onDark
        ? Colors.white.withValues(alpha: 0.08)
        : c.withValues(alpha: 0.06);
    final labelColor = onDark
        ? Colors.white.withValues(alpha: 0.7)
        : SdColors.muted;
    final valueColor = onDark ? Colors.white : c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: labelColor)),
              const SizedBox(height: 1),
              Text(value,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      height: 1.1,
                      color: valueColor)),
            ],
          ),
        ],
      ),
    );
  }
}

/// أشرطة إشارة WiFi (5 أعمدة تصاعدية) ملوّنة حسب التقييم.
class WifiSignalBars extends StatelessWidget {
  final QualityRating rating;
  final double height;
  const WifiSignalBars({super.key, required this.rating, this.height = 34});

  int get _activeBars {
    switch (rating) {
      case QualityRating.excellent:
        return 5;
      case QualityRating.good:
        return 4;
      case QualityRating.fair:
        return 3;
      case QualityRating.poor:
        return 2;
      case QualityRating.bad:
        return 1;
      case QualityRating.unknown:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ratingColor(rating);
    final active = _activeBars;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(5, (i) {
          final on = i < active;
          final h = height * (0.35 + i * 0.1625);
          return Container(
            width: 7,
            height: h.clamp(0, height),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: on ? c : c.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}

/// شريط نطاق صحّي: مسار رمادي + منطقة صحّية خضراء + مؤشّر موضع.
/// الكسور [bandStart]/[bandEnd]/[markerFraction] كلّها 0..1 باتجاه LTR.
class HealthBandBar extends StatelessWidget {
  final double? markerFraction; // null ⇒ بلا مؤشّر
  final double bandStart;
  final double bandEnd;
  final QualityRating rating;
  final String startLabel;
  final String endLabel;
  final String? bandLabel;
  final String? valueLabel; // شريحة قيمة اختيارية فوق المؤشّر
  const HealthBandBar({
    super.key,
    required this.markerFraction,
    required this.bandStart,
    required this.bandEnd,
    required this.rating,
    required this.startLabel,
    required this.endLabel,
    this.bandLabel,
    this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    final c = ratingColor(rating);
    const bandGreen = SdColors.success;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (ctx, cons) {
              final w = cons.maxWidth;
              final bs = bandStart.clamp(0.0, 1.0);
              final be = bandEnd.clamp(0.0, 1.0);
              final left = (bs * w).clamp(0.0, w);
              final bandW = ((be - bs) * w).clamp(0.0, w);
              final mf = markerFraction;
              final hasChip = valueLabel != null && mf != null;
              final trackTop = hasChip ? 28.0 : 8.0;
              return SizedBox(
                height: hasChip ? 44 : 22,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // شريحة القيمة فوق المؤشّر.
                    if (hasChip)
                      Positioned(
                        top: 0,
                        left: (mf.clamp(0.0, 1.0) * w - 28).clamp(0.0, w - 56),
                        child: Container(
                          width: 56,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                  color: c.withValues(alpha: 0.4),
                                  blurRadius: 5),
                            ],
                          ),
                          child: Text(valueLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace')),
                        ),
                      ),
                    // المسار الكامل (خارج النطاق = أحمر باهت).
                    Positioned(
                      left: 0,
                      right: 0,
                      top: trackTop,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: SdColors.danger.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                    // المنطقة الصحّية الخضراء (أوضح + توهّج خفيف).
                    Positioned(
                      left: left,
                      top: trackTop,
                      child: Container(
                        width: bandW,
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            bandGreen.withValues(alpha: 0.75),
                            bandGreen,
                          ]),
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: [
                            BoxShadow(
                                color: bandGreen.withValues(alpha: 0.35),
                                blurRadius: 5),
                          ],
                        ),
                      ),
                    ),
                    if (mf != null)
                      Positioned(
                        left: (mf.clamp(0.0, 1.0) * w - 9).clamp(0.0, w - 18),
                        top: trackTop - 5,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: c, width: 3.5),
                            boxShadow: [
                              BoxShadow(
                                  color: c.withValues(alpha: 0.5),
                                  blurRadius: 7),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(startLabel,
                  style: TextStyle(
                      fontSize: 9.5,
                      color: SdColors.faint,
                      fontFamily: 'monospace')),
              if (bandLabel != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: SdColors.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(bandLabel!,
                        style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: SdColors.success)),
                  ],
                ),
              Text(endLabel,
                  style: TextStyle(
                      fontSize: 9.5,
                      color: SdColors.faint,
                      fontFamily: 'monospace')),
            ],
          ),
        ],
      ),
    );
  }
}

/// مخطّط أعمدة لزمن الاستجابة: الأدنى/المتوسط/الأعلى (fl_chart).
class PingBarChart extends StatelessWidget {
  final double? minMs;
  final double? avgMs;
  final double? maxMs;
  const PingBarChart(
      {super.key, required this.minMs, required this.avgMs, required this.maxMs});

  @override
  Widget build(BuildContext context) {
    final items = <({String label, double? v, Color c})>[
      (label: 'الأدنى', v: minMs, c: SdColors.success),
      (label: 'المتوسط', v: avgMs, c: SdColors.primaryLight),
      (label: 'الأعلى', v: maxMs, c: SdColors.warning),
    ];
    final values = items.map((e) => e.v ?? 0).toList();
    final maxY = (values.fold<double>(0, math.max)) * 1.25;
    final safeMaxY = maxY <= 0 ? 10.0 : maxY;

    return Column(
      children: [
        SizedBox(
          height: 110,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceEvenly,
              maxY: safeMaxY,
              minY: 0,
              barTouchData: BarTouchData(enabled: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: safeMaxY / 4,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: SdColors.faint.withValues(alpha: 0.12),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                // تسميات المحور السفلي تظهر في صف الأسطورة أسفل المخطّط لتفادي
                // التكرار وإبقاء المخطّط نظيفاً.
                bottomTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: [
                for (var i = 0; i < items.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: items[i].v ?? 0,
                        color: items[i].c,
                        width: 26,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: safeMaxY,
                          color: SdColors.faint.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: items
              .map((e) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: e.c, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Text(e.label,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: SdColors.muted)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        e.v != null ? '${e.v!.toStringAsFixed(0)} ms' : '—',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'monospace',
                            color: e.c),
                      ),
                    ],
                  ))
              .toList(),
        ),
      ],
    );
  }
}

/// رادار يلخّص أبعاد الجودة (سرعة/زمن/ضوئي/واي‑فاي) — fl_chart.
class QualityRadarChart extends StatelessWidget {
  final List<({String label, double value})> dims; // value 0..100
  final bool onDark;
  const QualityRadarChart(
      {super.key, required this.dims, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final titleColor =
        onDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF37474F);
    final gridColor = onDark
        ? Colors.white.withValues(alpha: 0.18)
        : SdColors.faint.withValues(alpha: 0.35);
    const accent = SdColors.accent;
    return SizedBox(
      height: 230,
      child: RadarChart(
        RadarChartData(
          radarShape: RadarShape.polygon,
          dataSets: [
            RadarDataSet(
              dataEntries: dims
                  .map((d) => RadarEntry(value: d.value.clamp(0, 100)))
                  .toList(),
              fillColor: accent.withValues(alpha: 0.22),
              borderColor: accent,
              borderWidth: 2.5,
              entryRadius: 3,
            ),
          ],
          radarBackgroundColor: Colors.transparent,
          radarBorderData: BorderSide(color: gridColor, width: 1),
          gridBorderData: BorderSide(color: gridColor, width: 1),
          tickBorderData: BorderSide(color: gridColor, width: 1),
          tickCount: 4,
          ticksTextStyle:
              const TextStyle(color: Colors.transparent, fontSize: 8),
          titlePositionPercentageOffset: 0.14,
          titleTextStyle: TextStyle(
              color: titleColor,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              fontFamily: 'Cairo'),
          getTitle: (index, angle) {
            if (index < 0 || index >= dims.length) {
              return const RadarChartTitle(text: '');
            }
            return RadarChartTitle(text: dims[index].label, angle: 0);
          },
        ),
      ),
    );
  }
}

/// شبكة مواصفات منسّقة (مفتاح/قيمة) تتجاوب — بديل أنيق لصفوف InfoRow.
class SpecGrid extends StatelessWidget {
  final List<({String label, String value, IconData? icon})> items;
  final Color accent;
  const SpecGrid({super.key, required this.items, required this.accent});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      // عمودان حين يتّسع العرض، وإلا عمود واحد.
      final twoCols = cons.maxWidth >= 360;
      final tileW =
          twoCols ? (cons.maxWidth - 10) / 2 : cons.maxWidth;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items
            .map((it) => SizedBox(
                  width: tileW,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: accent.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        if (it.icon != null) ...[
                          Icon(it.icon, size: 16, color: accent),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(it.label,
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: SdColors.muted)),
                              const SizedBox(height: 2),
                              Text(it.value.isEmpty ? '—' : it.value,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ))
            .toList(),
      );
    });
  }
}
