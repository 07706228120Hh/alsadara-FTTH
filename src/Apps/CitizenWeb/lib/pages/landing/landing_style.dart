import 'package:flutter/material.dart';
import 'package:sadara_design/sadara_design.dart';

/// رموز الواجهة الرئيسية الجديدة (Landing).
///
/// كل الألوان مأخوذة من [SdColors] (نظام التصميم الموحّد) حتى يبقى أي تعديل
/// على الهوية في مكان واحد. القيم الإضافية هنا خاصة بالواجهة فقط
/// (حواف البروز ثلاثي الأبعاد، الخلفيات المتدرّجة).
class LColors {
  LColors._();

  // الهوية
  static const navy = SdColors.primary; // #132A5E
  static const navyDeep = SdColors.primaryEdge; // #0B1B3F
  static const navyLight = SdColors.primaryLight; // #1E3A8A
  static const navySoft = SdColors.primarySoft; // #3B5BA9
  static const teal = SdColors.accent; // #0E7490
  static const tealLight = SdColors.accentLight; // #06B6D4
  static const tealGlow = SdColors.accentGlow; // #22D3EE
  static const tealSoft = Color(0xFFE3F6FA);
  static const gold = SdColors.gold; // #C9A44C
  static const goldLight = SdColors.goldLight; // #E6C67A
  static const goldPale = Color(0xFFF5E2A8);
  static const goldSoft = Color(0xFFFFF5DC);
  static const goldInk = Color(0xFF2E2204);
  static const goldText = Color(0xFF8A6A1F);
  static const ink = SdColors.ink;
  static const muted = Color(0xFF4F5870);
  static const line = Color(0xFFDFE6F0);
  static const onNavy = Color(0xFFC8D3EA);
  static const onNavyMuted = Color(0xFFAEBBD6);
  static const green = Color(0xFF10B981);
  static const greenInk = Color(0xFF0F7A45);
  static const greenSoft = Color(0xFFE7F8EF);
  static const indigoSoft = Color(0xFFEEF2FF);

  // حواف البروز (البعد الثالث)
  static const edgeCard = Color(0xFFD2DCEA);
  static const edgeTeal = Color(0xFF0A5466);
  static const edgeGold = Color(0xFF8A6A1F);
  static const edgeDeep = Color(0xFF050E24);

  // خلفيات الأقسام
  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFDCE5F1), Color(0xFFE9EEF5), Color(0xFFEFE9DF)],
    stops: [0, .4, 1],
  );
  static const heroGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF0B1B3F), Color(0xFF132A5E), Color(0xFF0E5E78)],
    stops: [0, .45, 1],
  );
  static const navyBandGradient = LinearGradient(
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
    colors: [Color(0xFF0F2350), Color(0xFF132A5E), Color(0xFF0B4F66)],
    stops: [0, .5, 1],
  );
  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [goldLight, gold],
  );
  static const marqueeGradient = LinearGradient(
    colors: [teal, Color(0xFF0B5D74), navy],
  );
}

/// الخطوط: Alexandria للعناوين و IBM Plex Sans Arabic للنصوص.
/// ملفات الخط مقسّمة (عربي/لاتيني) لذلك نمرّر قائمة احتياطية.
class LText {
  LText._();
  static const display = 'Alexandria';
  static const body = 'PlexArabic';
  static const _fallback = ['AlexandriaLatin', 'PlexLatin', 'Cairo'];
  static const _bodyFallback = ['PlexLatin', 'Cairo'];

  static TextStyle h(double size, {FontWeight weight = FontWeight.w800, Color color = LColors.ink, double height = 1.35, List<Shadow>? shadows}) =>
      TextStyle(fontFamily: display, fontFamilyFallback: _fallback, fontSize: size, fontWeight: weight, color: color, height: height, shadows: shadows);

  static TextStyle b(double size, {FontWeight weight = FontWeight.w400, Color color = LColors.muted, double height = 1.7}) =>
      TextStyle(fontFamily: body, fontFamilyFallback: _bodyFallback, fontSize: size, fontWeight: weight, color: color, height: height);

  /// ظل "منحوت" للعناوين يعطي عمقاً خفيفاً.
  static const carvedLight = [
    Shadow(color: Color(0xFFD0DBEA), offset: Offset(0, 2)),
    Shadow(color: Color(0x2E132A5E), offset: Offset(0, 10), blurRadius: 22),
  ];
  static const carvedDark = [
    Shadow(color: Color(0x40000000), offset: Offset(0, 2)),
    Shadow(color: Color(0x59000000), offset: Offset(0, 12), blurRadius: 30),
  ];
}

/// زخرفة "بارزة": سطح يقف على حافة صلبة + ظل ناعم تحته.
BoxDecoration raised({
  Color? color,
  Gradient? gradient,
  double radius = 22,
  Color edge = LColors.edgeCard,
  double depth = 6,
  Color softShadow = const Color(0x73132A5E),
  BoxBorder? border,
}) =>
    BoxDecoration(
      color: gradient == null ? (color ?? Colors.white) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: border,
      boxShadow: [
        BoxShadow(color: edge, offset: Offset(0, depth)),
        BoxShadow(color: softShadow, offset: Offset(0, depth + 18), blurRadius: 40, spreadRadius: -24),
      ],
    );

/// نقاط التوقف المستخدمة في الواجهة.
class LBreak {
  LBreak._();
  static const phone = 560.0;
  static const stackHero = 720.0;
  static const tablet = 1000.0;
  static const wide = 1100.0;
  static const maxWidth = 1200.0;
}
