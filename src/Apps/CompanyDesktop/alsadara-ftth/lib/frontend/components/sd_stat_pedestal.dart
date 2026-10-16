/// مؤشّر رقمي على عمود متساوي القياس (Isometric) — بديل العدّادات المسطّحة.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_responsive.dart';
import '../tokens/sd_typography.dart';
import 'sd_raised.dart';

/// بطاقة مؤشّر: عمود مجسّم يتناسب ارتفاعه مع [value]/[max] + الرقم والاسم.
class SdStatPedestal extends StatelessWidget {
  const SdStatPedestal({
    super.key,
    required this.value,
    required this.label,
    this.max,
    this.tone,
    this.group = SdGroup.admin,
    this.onTap,
    this.caption,
  });

  final num value;
  final String label;

  /// أقصى قيمة للمقارنة بين المؤشرات (عادة أكبر قيمة بينها). null = عمود ممتلئ.
  final num? max;
  final SdTone? tone;
  final SdGroup group;
  final VoidCallback? onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? group.tone;
    final m = (max == null || max == 0) ? value : max!;
    final f = m == 0 ? 0.0 : (value / m).clamp(0.0, 1.0).toDouble();
    // الهاتف: بطاقة أقصر بعمود أصغر ورقم أصغر.
    final phone = context.sd.isPhone;
    return SdRaised(
      onTap: onTap,
      semanticLabel: '$label: $value',
      radius: SdRadius.xl,
      depth: 6,
      padding: EdgeInsetsDirectional.fromSTEB(phone ? 16 : 20, phone ? 4 : 8, phone ? 8 : 12, phone ? 4 : 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$value',
                    style: (phone ? SdText.numberSm.copyWith(fontSize: 28) : SdText.number)
                        .copyWith(color: t.edge)),
                Text(label, style: SdText.label),
                if (caption != null) Text(caption!, style: SdText.caption),
              ],
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: f),
            duration: const Duration(milliseconds: 900),
            curve: SdMotion.bounce,
            builder: (_, v, __) => SizedBox(
              width: phone ? 64 : 96,
              height: phone ? 80 : 120,
              child: CustomPaint(painter: _PedestalPainter(v.clamp(0.0, 1.0), t)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PedestalPainter extends CustomPainter {
  _PedestalPainter(this.f, this.t);
  final double f;
  final SdTone t;

  static const double _k = 0.8660254;

  Path _poly(List<Offset> p) => Path()..addPolygon(p, true);

  @override
  void paint(Canvas canvas, Size size) {
    // مساحة تصميم 120×150 تُحجَّم للحجم الفعلي.
    canvas.save();
    canvas.scale(size.width / 120, size.height / 150);
    const x = 60.0, yBase = 100.0, w = 34.0, maxH = 70.0;
    const dx = w * _k, dy = w * .5;
    final h = math.max(3.0, maxH * f);
    final y0 = yBase - h;

    canvas.drawOval(Rect.fromCenter(center: const Offset(60, 136), width: 92, height: 22),
        Paint()..color = const Color(0x1A1A237E));

    // خيال الحدّ الأقصى.
    final ghost = _poly(const [
      Offset(x, yBase - maxH),
      Offset(x + dx, yBase - maxH + dy),
      Offset(x + dx, yBase + dy),
      Offset(x, yBase + 2 * dy),
      Offset(x - dx, yBase + dy),
      Offset(x - dx, yBase - maxH + dy),
    ]);
    canvas.drawPath(
        ghost,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = SdColors.sideShade);

    final top = [Offset(x, y0), Offset(x + dx, y0 + dy), Offset(x, y0 + 2 * dy), Offset(x - dx, y0 + dy)];
    final left = [Offset(x - dx, y0 + dy), Offset(x, y0 + 2 * dy), Offset(x, y0 + 2 * dy + h), Offset(x - dx, y0 + dy + h)];
    final right = [Offset(x, y0 + 2 * dy), Offset(x + dx, y0 + dy), Offset(x + dx, y0 + dy + h), Offset(x, y0 + 2 * dy + h)];
    canvas.drawPath(_poly(left), Paint()..color = t.base);
    canvas.drawPath(_poly(right), Paint()..color = t.edge);
    canvas.drawPath(_poly(top), Paint()..color = Color.lerp(t.light, Colors.white, .45)!);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PedestalPainter old) => old.f != f || old.t != t;
}
