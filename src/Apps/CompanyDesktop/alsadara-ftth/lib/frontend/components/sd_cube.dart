/// مكعّب أيقونة ثلاثي الأبعاد (بثق قطري + منظور) بلون المجموعة.
library;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import 'sd_basics.dart';

class SdIconCube extends StatelessWidget {
  const SdIconCube({
    super.key,
    required this.icon,
    this.tone,
    this.group = SdGroup.admin,
    this.size = 52,
    this.lift = 0,
    this.badge,
  });

  final IconData icon;

  /// لون مخصّص؛ وإلا فلون [group].
  final SdTone? tone;
  final SdGroup group;
  final double size;

  /// 0 = وضع عادي، 1 = مرفوع (عند مرور الماوس) — يُحرَّك بسلاسة من الخارج.
  final double lift;

  /// رقم الشارة (طلبات/رسائل). null أو 0 = بلا شارة.
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? group.tone;
    final layers = (size / 9).round().clamp(3, 8);
    final cube = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .27),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [t.light, t.base],
        ),
        boxShadow: SdDepth.cube(t.edge, layers: layers),
      ),
      child: Icon(icon, color: Colors.white, size: size * .5),
    );
    final transform = Matrix4.translationValues(0, -3 * lift, 0)
      ..multiply(Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateX(0.24 - .1 * lift)
        ..rotateY(0.30 + .25 * lift));
    return SizedBox(
      width: size + layers + 6,
      height: size + layers + 6,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Transform(
            alignment: Alignment.center,
            transform: transform,
            child: cube,
          ),
          if ((badge ?? 0) > 0)
            PositionedDirectional(
              top: -6,
              end: -8,
              child: SdBadge(count: badge!),
            ),
        ],
      ),
    );
  }
}
