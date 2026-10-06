/// ودجات مشتركة لوحدة فحص الجودة — Network Quality
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/quality_models.dart';

/// لون التقييم.
Color ratingColor(QualityRating r) {
  switch (r) {
    case QualityRating.excellent:
      return const Color(0xFF2E7D32);
    case QualityRating.good:
      return const Color(0xFF66BB6A);
    case QualityRating.fair:
      return const Color(0xFFF9A825);
    case QualityRating.poor:
      return const Color(0xFFEF6C00);
    case QualityRating.bad:
      return const Color(0xFFC62828);
    case QualityRating.unknown:
      return const Color(0xFF9E9E9E);
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

  const ScoreGauge({
    super.key,
    required this.score,
    required this.rating,
    this.size = 180,
  });

  @override
  Widget build(BuildContext context) {
    final color = ratingColor(rating);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GaugePainter(score / 100, color),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score.round().toString(),
                style: TextStyle(
                  fontSize: size * 0.3,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                rating.arabicLabel,
                style: TextStyle(
                  fontSize: size * 0.11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text('من 100',
                  style: TextStyle(
                      fontSize: size * 0.07, color: Colors.grey.shade500)),
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
  _GaugePainter(this.fraction, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const start = math.pi * 0.75;
    const sweepMax = math.pi * 1.5;

    final bg = Paint()
      ..color = Colors.grey.shade200
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
      old.fraction != fraction || old.color != color;
}

/// بطاقة قسم بعنوان وأيقونة.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? accent;
  final Widget child;
  final Widget? trailing;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = accent ?? const Color(0xFF1A237E);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, color: c, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14, color: c)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}

/// صف مقياس مفرد مع تقييم ملوّن.
class MetricTile extends StatelessWidget {
  final MetricResult metric;
  const MetricTile(this.metric, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = ratingColor(metric.rating);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(ratingIcon(metric.rating), color: c, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                if (metric.note != null)
                  Text(metric.note!,
                      style: TextStyle(
                          fontSize: 10.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Text(metric.displayValue,
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  fontFamily: 'monospace',
                  color: c)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(metric.rating.arabicLabel,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: c)),
          ),
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
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
