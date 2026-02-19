import 'package:flutter/material.dart';

/// ثيم منصة الصدارة
/// Sadara Platform Theme
class AppTheme {
  // ═══════════════════════════════════════════════════════════════
  // الألوان الأساسية - Primary Colors
  // ═══════════════════════════════════════════════════════════════

  /// الأزرق الداكن - اللون الرئيسي
  static const Color primaryColor = Color(0xFF1E3A5F);

  /// الأزرق الفاتح
  static const Color primaryLight = Color(0xFF4A6FA5);

  /// الأزرق الأغمق
  static const Color primaryDark = Color(0xFF0D2137);

  /// الأخضر - للنجاح والتأكيد
  static const Color successColor = Color(0xFF2E7D32);

  /// البرتقالي - للتحذيرات والأزرار الثانوية
  static const Color accentColor = Color(0xFFFF9800);

  /// الأحمر - للأخطاء
  static const Color errorColor = Color(0xFFD32F2F);

  /// الرمادي الفاتح - للخلفيات
  static const Color backgroundColor = Color(0xFFF5F7FA);

  /// الأبيض
  static const Color white = Colors.white;

  /// الأسود للنصوص
  static const Color textDark = Color(0xFF1A1A1A);

  /// الرمادي للنصوص الثانوية
  static const Color textGrey = Color(0xFF6B7280);

  /// لون البطاقات
  static const Color cardColor = Colors.white;

  /// لون الحدود
  static const Color borderColor = Color(0xFFE5E7EB);

  // ═══════════════════════════════════════════════════════════════
  // ألوان الخدمات - Service Colors
  // ═══════════════════════════════════════════════════════════════

  /// لون خدمات الإنترنت
  static const Color internetColor = Color(0xFF2196F3);

  /// لون خدمة الماستر كارد
  static const Color masterCardColor = Color(0xFF9C27B0);

  /// لون المتجر
  static const Color storeColor = Color(0xFF4CAF50);

  /// لون الوكيل (تم تحديثه إلى الأزرق)
  static const Color agentColor = Color(0xFF1565C0);

  /// لون المعلومات
  static const Color infoColor = Color(0xFF2196F3);

  /// لون التحذير
  static const Color warningColor = Color(0xFFFF9800);

  // ═══════════════════════════════════════════════════════════════
  // التدرجات - Gradients
  // ═══════════════════════════════════════════════════════════════

  /// التدرج الرئيسي
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, primaryLight],
  );

  /// تدرج الهيدر
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [primaryDark, primaryColor],
  );

  /// تدرج الأخضر
  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF43A047), Color(0xFF2E7D32)],
  );

  /// تدرج البرتقالي
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFB74D), Color(0xFFFF9800)],
  );

  // ═══════════════════════════════════════════════════════════════
  // الظلال - Shadows
  // ═══════════════════════════════════════════════════════════════

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 10,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get buttonShadow => [
    BoxShadow(
      color: primaryColor.withOpacity(0.3),
      blurRadius: 8,
      offset: const Offset(0, 4),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════
  // الأبعاد - Dimensions
  // ═══════════════════════════════════════════════════════════════

  static const double borderRadius = 12.0;
  static const double borderRadiusLarge = 20.0;
  static const double borderRadiusSmall = 8.0;

  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // ═══════════════════════════════════════════════════════════════
  // أنماط النصوص - Text Styles
  // ═══════════════════════════════════════════════════════════════

  static const TextStyle headingLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: textDark,
    fontFamily: 'Cairo',
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textDark,
    fontFamily: 'Cairo',
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textDark,
    fontFamily: 'Cairo',
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: textDark,
    fontFamily: 'Cairo',
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: textGrey,
    fontFamily: 'Cairo',
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: white,
    fontFamily: 'Cairo',
  );

  // ═══════════════════════════════════════════════════════════════
  // ThemeData - بيانات الثيم الكاملة
  // ═══════════════════════════════════════════════════════════════

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Cairo',
    brightness: Brightness.light,
    colorScheme: ColorScheme.light(
      primary: primaryColor,
      secondary: accentColor,
      surface: white,
      error: errorColor,
    ),
    scaffoldBackgroundColor: backgroundColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryColor,
        side: const BorderSide(color: primaryColor, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        textStyle: buttonText.copyWith(color: primaryColor),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: errorColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textTheme: const TextTheme(
      headlineLarge: headingLarge,
      headlineMedium: headingMedium,
      headlineSmall: headingSmall,
      bodyLarge: bodyLarge,
      bodyMedium: bodyMedium,
    ),
  );

  // ═══════════════════════════════════════════════════════════════
  // Dark Theme - الوضع الليلي
  // ═══════════════════════════════════════════════════════════════

  // Dark Mode Colors
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkCard = Color(0xFF2C2C2C);
  static const Color darkTextPrimary = Color(0xFFE1E1E1);
  static const Color darkTextSecondary = Color(0xFF9E9E9E);
  static const Color darkBorder = Color(0xFF3D3D3D);

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Cairo',
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: primaryLight,
      secondary: accentColor,
      surface: darkSurface,
      error: errorColor,
    ),
    scaffoldBackgroundColor: darkBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: darkSurface,
      foregroundColor: darkTextPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: darkTextPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: darkCard,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryLight,
        foregroundColor: white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primaryLight,
        side: const BorderSide(color: primaryLight, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        textStyle: buttonText.copyWith(color: primaryLight),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: primaryLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: errorColor),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: const TextStyle(color: darkTextSecondary),
      hintStyle: const TextStyle(color: darkTextSecondary),
    ),
    textTheme: TextTheme(
      headlineLarge: headingLarge.copyWith(color: darkTextPrimary),
      headlineMedium: headingMedium.copyWith(color: darkTextPrimary),
      headlineSmall: headingSmall.copyWith(color: darkTextPrimary),
      bodyLarge: bodyLarge.copyWith(color: darkTextPrimary),
      bodyMedium: bodyMedium.copyWith(color: darkTextSecondary),
    ),
    dividerColor: darkBorder,
    iconTheme: const IconThemeData(color: darkTextPrimary),
    listTileTheme: const ListTileThemeData(
      textColor: darkTextPrimary,
      iconColor: darkTextSecondary,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: darkSurface,
      selectedItemColor: primaryLight,
      unselectedItemColor: darkTextSecondary,
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: darkSurface),
    dialogTheme: DialogThemeData(
      backgroundColor: darkCard,
      titleTextStyle: headingSmall.copyWith(color: darkTextPrimary),
      contentTextStyle: bodyLarge.copyWith(color: darkTextPrimary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: darkCard,
      contentTextStyle: bodyLarge.copyWith(color: darkTextPrimary),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: darkCard,
      labelStyle: bodyMedium.copyWith(color: darkTextPrimary),
      selectedColor: primaryLight.withOpacity(0.3),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: primaryLight,
      unselectedLabelColor: darkTextSecondary,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryLight;
        }
        return darkTextSecondary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryLight.withOpacity(0.5);
        }
        return darkBorder;
      }),
    ),
  );

  // ═══════════════════════════════════════════════════════════════
  // Agent Theme - ثيم الوكيل المخصص
  // ═══════════════════════════════════════════════════════════════

  static ThemeData get agentTheme => ThemeData(
    useMaterial3: true,
    fontFamily: 'Cairo',
    brightness: Brightness.light,
    primaryColor: agentColor,
    colorScheme: ColorScheme.light(
      primary: agentColor,
      secondary: accentColor,
      surface: white,
      error: errorColor,
    ),
    scaffoldBackgroundColor: backgroundColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: agentColor,
      foregroundColor: white,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: agentColor,
        foregroundColor: white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        textStyle: buttonText,
        elevation: 2,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: const BorderSide(color: agentColor, width: 2),
      ),
      prefixIconColor: agentColor,
      labelStyle: const TextStyle(color: textGrey),
    ),
    cardTheme: CardThemeData(
      color: white,
      elevation: 4,
      shadowColor: agentColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadiusLarge),
      ),
    ),
  );
}

/// أيقونات مخصصة للمنصة
class AppIcons {
  static const IconData internet = Icons.wifi;
  static const IconData masterCard = Icons.credit_card;
  static const IconData store = Icons.store;
  static const IconData agent = Icons.storefront;
  static const IconData citizen = Icons.person;
  static const IconData support = Icons.support_agent;
  static const IconData payment = Icons.payment;
  static const IconData location = Icons.location_on;
  static const IconData phone = Icons.phone;
  static const IconData email = Icons.email;
  static const IconData settings = Icons.settings;
  static const IconData logout = Icons.logout;
  static const IconData notifications = Icons.notifications;
  static const IconData search = Icons.search;
  static const IconData menu = Icons.menu;
  static const IconData back = Icons.arrow_back;
  static const IconData forward = Icons.arrow_forward;
  static const IconData check = Icons.check_circle;
  static const IconData close = Icons.close;
  static const IconData edit = Icons.edit;
  static const IconData delete = Icons.delete;
  static const IconData add = Icons.add;
  static const IconData refresh = Icons.refresh;
  static const IconData download = Icons.download;
  static const IconData upload = Icons.upload;
  static const IconData share = Icons.share;
  static const IconData copy = Icons.copy;
  static const IconData visibility = Icons.visibility;
  static const IconData visibilityOff = Icons.visibility_off;
}
