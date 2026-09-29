import 'package:flutter/material.dart';

/// ─── نظام التصميم الموحّد لمنصة العراق الرقمية ───
///
/// كل الألوان الدلالية تُقرأ من [PlatformPalette] عبر `context.pal` — لا ألوان
/// مضمّنة في الشاشات. اللون الأساسي (primary) واحد للمنصّة كلّها، ولكل تطبيق
/// «لكنة» ثانوية فقط ([PlatformPalette.accent]).

/// لوحة الألوان الدلالية (امتداد للثيم كي تتبدّل مع الوضع الفاتح/الداكن تلقائياً).
class PlatformPalette extends ThemeExtension<PlatformPalette> {
  /// خلفية الصفحة.
  final Color surface;
  /// خلفية البطاقة/اللوحة.
  final Color surfaceCard;
  /// خلفية الحقول والصفوف البديلة والتحويم.
  final Color surfaceVariant;
  /// الحدود والفواصل.
  final Color outline;
  /// النص الأساسي.
  final Color text;
  /// النص الثانوي/الباهت.
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  /// لكنة التطبيق الحالي (شارة/أيقونة/إبراز).
  final Color accent;
  /// سلسلة ألوان المخططات (تُكرَّر دورياً).
  final List<Color> chartSeries;

  const PlatformPalette({
    required this.surface,
    required this.surfaceCard,
    required this.surfaceVariant,
    required this.outline,
    required this.text,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.accent,
    required this.chartSeries,
  });

  // الهوية العصرية لتطبيق الوكلاء: كهرماني على خلفية ليلية/ضبابية فاتحة.
  static const Color primaryLight = Color(0xFFF59E0B);
  static const Color primaryDark = Color(0xFFFBBF24);
  static const Color primaryContainerLight = Color(0xFFFFF5DC);
  static const Color primaryContainerDark = Color(0xFF1A1405);
  /// نص فوق الأزرار الكهرمانية (داكن في الوضعين).
  static const Color onPrimaryInk = Color(0xFF1A1204);
  /// تدرّج الأزرار البارزة والشعار.
  static const List<Color> accentGradient = [Color(0xFFFBBF24), Color(0xFFF59E0B)];

  static const light = PlatformPalette(
    surface: Color(0xFFF3F5F9),
    surfaceCard: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF6F8FB),
    outline: Color(0xFFE2E8F0),
    text: Color(0xFF0F172A),
    textMuted: Color(0xFF64748B),
    success: Color(0xFF059669),
    warning: Color(0xFFB45309),
    danger: Color(0xFFDC2626),
    info: Color(0xFF0891B2),
    accent: Color(0xFFB45309),
    chartSeries: [
      Color(0xFF0E7490),
      Color(0xFF059669),
      Color(0xFFD97706),
      Color(0xFFC026D3),
      Color(0xFF7C3AED),
      Color(0xFFDC2626),
    ],
  );

  static const dark = PlatformPalette(
    surface: Color(0xFF080B11),
    surfaceCard: Color(0xFF0F1622),
    surfaceVariant: Color(0xFF0A1019),
    outline: Color(0xFF1C2838),
    text: Color(0xFFE6EDF3),
    textMuted: Color(0xFF94A3B8),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF22D3EE),
    accent: primaryDark,
    chartSeries: [
      Color(0xFF22D3EE),
      Color(0xFF34D399),
      Color(0xFFFBBF24),
      Color(0xFFE879F9),
      Color(0xFFA78BFA),
      Color(0xFFF87171),
    ],
  );

  /// لون حالة موحّد (تذاكر/اشتراكات/أجهزة) — مكان واحد لكل التطبيقات.
  Color status(String s) {
    switch (s) {
      case 'active':
      case 'resolved':
      case 'matched':
      case 'online':
      case 'ok':
        return success;
      case 'in_progress':
      case 'pending':
        return warning;
      case 'expired':
        return danger;
      case 'agent_suspicious':
      case 'company_suspicious':
      case 'warning':
        return warning;
      case 'open':
      case 'urgent':
      case 'critical':
      case 'offline':
      case 'error':
        return danger;
      default:
        return textMuted;
    }
  }

  @override
  PlatformPalette copyWith({
    Color? surface,
    Color? surfaceCard,
    Color? surfaceVariant,
    Color? outline,
    Color? text,
    Color? textMuted,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? accent,
    List<Color>? chartSeries,
  }) =>
      PlatformPalette(
        surface: surface ?? this.surface,
        surfaceCard: surfaceCard ?? this.surfaceCard,
        surfaceVariant: surfaceVariant ?? this.surfaceVariant,
        outline: outline ?? this.outline,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        info: info ?? this.info,
        accent: accent ?? this.accent,
        chartSeries: chartSeries ?? this.chartSeries,
      );

  @override
  PlatformPalette lerp(ThemeExtension<PlatformPalette>? other, double t) {
    if (other is! PlatformPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return PlatformPalette(
      surface: c(surface, other.surface),
      surfaceCard: c(surfaceCard, other.surfaceCard),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      outline: c(outline, other.outline),
      text: c(text, other.text),
      textMuted: c(textMuted, other.textMuted),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      info: c(info, other.info),
      accent: c(accent, other.accent),
      chartSeries: t < 0.5 ? chartSeries : other.chartSeries,
    );
  }
}

/// وصول مختصر: `context.pal.success`
extension PaletteX on BuildContext {
  PlatformPalette get pal =>
      Theme.of(this).extension<PlatformPalette>() ??
      (Theme.of(this).brightness == Brightness.dark ? PlatformPalette.dark : PlatformPalette.light);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// المسافات (px).
abstract class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double x3 = 32;
  static const double x4 = 48;
}

/// أنصاف الأقطار.
abstract class Radii {
  static const double sm = 10;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double pill = 999;
  static BorderRadius get rPill => BorderRadius.circular(pill);
  static BorderRadius get rSm => BorderRadius.circular(sm);
  static BorderRadius get rMd => BorderRadius.circular(md);
  static BorderRadius get rLg => BorderRadius.circular(lg);
  static BorderRadius get rXl => BorderRadius.circular(xl);
}

/// نقاط التجاوب.
abstract class Bp {
  /// أقل منها: موبايل (شريط سفلي).
  static const double mobile = 600;
  /// من هنا: Rail جانبي.
  static const double tablet = 840;
  /// من هنا: Rail موسّع بعناوين.
  static const double wide = 1180;

  static bool isMobile(BuildContext c) => MediaQuery.sizeOf(c).width < mobile;
  static bool isWide(BuildContext c) => MediaQuery.sizeOf(c).width >= tablet;
}

/// مدد الحركة.
abstract class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Curves.easeOutCubic;
}

/// ظلال موحّدة.
abstract class Elev {
  static List<BoxShadow> card(BuildContext c) => [
        BoxShadow(
          color: (c.isDark ? Colors.black : const Color(0xFF0F172A)).withValues(alpha: c.isDark ? 0.30 : 0.05),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];
  static List<BoxShadow> float(BuildContext c) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: c.isDark ? 0.5 : 0.12),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ];
  static List<BoxShadow> glow(Color color, [double alpha = 0.25]) => [
        BoxShadow(color: color.withValues(alpha: alpha), blurRadius: 24, offset: const Offset(0, 8)),
      ];
}
