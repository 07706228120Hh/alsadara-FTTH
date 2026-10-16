/// المسافات والأنصاف أقطار والعمق والحركة — نظام تصميم الصدارة.
library;

import 'package:flutter/material.dart';

import 'sd_colors.dart';

/// مقياس المسافات (مضاعفات 4).
class SdSpace {
  SdSpace._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// الحشو الجانبي للصفحة.
  static const double gutter = 20;

  /// أقصى عرض لمحتوى الصفحات (سطح المكتب).
  static const double contentMax = 1400;

  /// أقصى عرض لصفحات النماذج والتفاصيل.
  static const double formMax = 760;

  /// أدنى ارتفاع لأي هدف لمس/نقر.
  static const double touch = 44;
}

/// أنصاف الأقطار.
class SdRadius {
  SdRadius._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// العمق «المادّي» ثلاثي الأبعاد: حافّة سفلية صلبة + توهّج ناعم.
class SdDepth {
  SdDepth._();

  /// ارتفاعات البروز القياسية.
  static const double chip = 2;
  static const double small = 3;
  static const double button = 6;
  static const double card = 5;
  static const double hero = 8;

  /// ظل عنصر بارز. [depth] سماكة الحافّة، [glow] لون التوهّج.
  static List<BoxShadow> raised({
    Color edge = SdColors.cardEdge,
    double depth = card,
    Color glow = const Color(0x591A237E),
  }) {
    return [
      BoxShadow(color: edge, offset: Offset(0, depth)),
      BoxShadow(
        color: glow,
        offset: Offset(0, depth + 12),
        blurRadius: 28,
        spreadRadius: -14,
      ),
    ];
  }

  /// ظل مضغوط (أثناء الضغط) — الحافّة تكاد تختفي.
  static List<BoxShadow> pressed({Color edge = SdColors.cardEdge}) {
    return [
      BoxShadow(color: edge, offset: const Offset(0, 1)),
    ];
  }

  /// سماكة مكعّب أيقونة: طبقات قطرية متتالية تعطي إحساس البثق.
  static List<BoxShadow> cube(Color edge, {int layers = 6, double glowAlpha = .35}) {
    return [
      for (var i = 1; i <= layers; i++)
        BoxShadow(color: edge, offset: Offset(-i.toDouble(), i.toDouble())),
      BoxShadow(
        color: edge.withValues(alpha: glowAlpha),
        offset: Offset(-(layers + 4).toDouble(), (layers + 8).toDouble()),
        blurRadius: 18,
      ),
    ];
  }
}

/// الحركة: مدد ومنحنيات موحّدة.
class SdMotion {
  SdMotion._();
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 450);
  static const Curve standard = Curves.easeOutCubic;
  static const Curve bounce = Curves.easeOutBack;
}
