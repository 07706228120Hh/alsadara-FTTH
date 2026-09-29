import 'package:flutter/material.dart';
import 'brand.dart';
import 'platform_theme.dart';
import 'tokens.dart';

/// طبقة توافق مع الشيفرة القديمة — الألوان الدلالية تُقرأ الآن من `context.pal`
/// وهوية التطبيقات من [AppBrand]. تبقى هذه الثوابت للشاشات التي لم تُحوَّل بعد.
class BrandColors {
  static const agents = Color(0xFFD97706);
  static const companies = Color(0xFF059669);
  static const subscribers = Color(0xFF0891B2);
  static const ministry = Color(0xFF1D4ED8);

  static const green = Color(0xFF059669);
  static const amber = Color(0xFFD97706);
  static const red = Color(0xFFDC2626);
  static const blue = Color(0xFF2563EB);
  static const violet = Color(0xFF7C3AED);
  static const slate = Color(0xFF64748B);

  /// لكنة التطبيق من هويته.
  static Color of(AppBrand b) => b.accent;
}

/// توافق: `AppTheme.build(color, brightness)` يُحوَّل إلى الثيم الموحّد
/// بحسب أقرب هوية للّون المُمرَّر. الأفضل استدعاء [PlatformTheme.build] مباشرة.
class AppTheme {
  static ThemeData build(Color seed, Brightness brightness) {
    final brand = AppBrand.values.firstWhere(
      (b) => b.accent == seed,
      orElse: () => AppBrand.portal,
    );
    return PlatformTheme.build(brand, brightness);
  }

  static PlatformPalette palette(Brightness b) =>
      b == Brightness.dark ? PlatformPalette.dark : PlatformPalette.light;
}
