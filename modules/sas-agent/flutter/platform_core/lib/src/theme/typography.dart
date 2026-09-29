import 'package:flutter/material.dart';

/// الخطوط الموحّدة — مضمّنة في حزمة platform_core (بلا جلب من الإنترنت).
/// IBM Plex Sans Arabic للنصوص، IBM Plex Mono للأرقام والمعرّفات.
abstract class PlatformType {
  /// اسم العائلة كما يراه Flutter عند استخدام خط من حزمة.
  static const String sansFamily = 'packages/platform_core/IBMPlexSansArabic';
  static const String monoFamily = 'packages/platform_core/IBMPlexMono';

  static const List<String> _fallback = ['Segoe UI', 'Roboto', 'Arial', 'sans-serif'];

  /// نمط نصّي عادي.
  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? spacing,
  }) =>
      TextStyle(
        fontFamily: sansFamily,
        fontFamilyFallback: _fallback,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      );

  /// أرقام/أكواد/IP/معرّفات — أحادي المسافة، لاتيني دائماً.
  static TextStyle mono({
    double size = 13,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double? height,
    double? spacing,
  }) =>
      TextStyle(
        fontFamily: monoFamily,
        fontFamilyFallback: const ['Consolas', 'Menlo', 'monospace'],
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// رقم KPI ضخم.
  static TextStyle display({double size = 28, Color? color}) =>
      mono(size: size, weight: FontWeight.w700, color: color, spacing: -1, height: 1);

  /// اسم دلالي لعرض الأرقام داخل الجداول.
  static TextStyle num({double size = 13, FontWeight weight = FontWeight.w600, Color? color}) =>
      mono(size: size, weight: weight, color: color);

  /// TextTheme كامل بعائلة الخط الموحّدة (يُطبَّق على ThemeData).
  static TextTheme textTheme(TextTheme base, Color body, Color muted) {
    TextStyle s(TextStyle? t, double size, FontWeight w, {double? h, Color? c}) =>
        sans(size: size, weight: w, color: c ?? body, height: h);
    return TextTheme(
      displayLarge: s(base.displayLarge, 48, FontWeight.w700, h: 1.1),
      displayMedium: s(base.displayMedium, 40, FontWeight.w700, h: 1.1),
      displaySmall: s(base.displaySmall, 34, FontWeight.w700, h: 1.15),
      headlineLarge: s(base.headlineLarge, 30, FontWeight.w700, h: 1.2),
      headlineMedium: s(base.headlineMedium, 26, FontWeight.w700, h: 1.2),
      headlineSmall: s(base.headlineSmall, 22, FontWeight.w700, h: 1.25),
      titleLarge: s(base.titleLarge, 19, FontWeight.w700, h: 1.3),
      titleMedium: s(base.titleMedium, 16, FontWeight.w600, h: 1.35),
      titleSmall: s(base.titleSmall, 14, FontWeight.w600, h: 1.35),
      bodyLarge: s(base.bodyLarge, 16, FontWeight.w400, h: 1.5),
      bodyMedium: s(base.bodyMedium, 14, FontWeight.w400, h: 1.5),
      bodySmall: s(base.bodySmall, 12.5, FontWeight.w400, h: 1.45, c: muted),
      labelLarge: s(base.labelLarge, 14, FontWeight.w600, h: 1.2),
      labelMedium: s(base.labelMedium, 12.5, FontWeight.w600, h: 1.2),
      labelSmall: s(base.labelSmall, 11, FontWeight.w600, h: 1.2, c: muted),
    );
  }
}
