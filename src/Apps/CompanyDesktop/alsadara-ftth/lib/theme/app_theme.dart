import 'package:flutter/material.dart';

class AppTheme {
  // الألوان الأساسية للنظام
  static const primaryColor = Color(0xFF1A237E);
  static const secondaryColor = Color(0xFF3949AB);
  static const accentColor = Color(0xFF64B5F6);

  // ألوان إضافية
  static const successColor = Color(0xFF4CAF50);
  static const warningColor = Color(0xFFFF9800);
  static const errorColor = Color(0xFFE53935);
  static const infoColor = Color(0xFF2196F3);

  static const _radius12 = 12.0;
  static const _radius16 = 16.0;

  // ثيم موحد (فاتح)
  static ThemeData lightTheme = _buildTheme(Brightness.light);
  // ثيم موحد (مظلم)
  static ThemeData darkTheme = _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: 'Cairo',

      // AppBar موحد
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),

      // البطاقات
      cardTheme: CardThemeData(
        elevation: 4,
        shadowColor:
            (brightness == Brightness.light ? Colors.grey : Colors.black)
                .withValues(alpha: brightness == Brightness.light ? 0.2 : 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius16),
        ),
        margin: const EdgeInsets.all(8),
      ),

      // الأزرار
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radius12),
          ),
        ),
      ),

      // الحوارات
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius16),
        ),
        backgroundColor: brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1E1E1E),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: brightness == Brightness.light
              ? const Color(0xFF1A237E)
              : Colors.white,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: brightness == Brightness.light
              ? const Color(0xFF2C3E50)
              : Colors.white70,
        ),
      ),

      // الحقول
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? const Color(0xFFF7FAFC)
            : const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius12),
          borderSide: BorderSide(
            color: brightness == Brightness.light
                ? Colors.grey.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),

      // العناصر العامة
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius12),
        ),
        iconColor: colorScheme.primary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius12),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.withValues(alpha: 0.2),
        space: 0.8,
        thickness: 0.8,
      ),

      // انتقالات موحدة
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _InstantPageTransitionsBuilder(),
          TargetPlatform.iOS: _InstantPageTransitionsBuilder(),
          TargetPlatform.windows: _InstantPageTransitionsBuilder(),
          TargetPlatform.linux: _InstantPageTransitionsBuilder(),
          TargetPlatform.macOS: _InstantPageTransitionsBuilder(),
        },
      ),
    );
  }

  // تدرجات لونية مخصصة
  static const List<Color> blueGradient = [
    Color(0xFF283593),
    Color(0xFF1976D2),
    Color(0xFF64B5F6),
  ];

  static const List<Color> greenGradient = [
    Color(0xFF4CAF50),
    Color(0xFF45A049),
  ];

  static const List<Color> orangeGradient = [
    Color(0xFFFF9800),
    Color(0xFFFF8F00),
  ];
}

/// انتقال فوري بين الصفحات - بدون أنيميشن لأداء أفضل على Windows Desktop
class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child; // بدون أي أنيميشن - انتقال فوري
  }
}
