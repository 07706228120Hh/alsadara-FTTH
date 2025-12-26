import 'package:flutter/material.dart';

class SmartTextColor {
  /// حساب لون النص المناسب بناءً على لون الخلفية
  static Color getContrastingTextColor(Color backgroundColor) {
    // حساب الـ luminance للخلفية
    double luminance = backgroundColor.computeLuminance();

    // إذا كانت الخلفية فاتحة، استخدم نص داكن
    // إذا كانت الخلفية داكنة، استخدم نص فاتح
    if (luminance > 0.5) {
      return Colors.black87; // خلفية فاتحة = نص داكن
    } else {
      return Colors.white; // خلفية داكنة = نص فاتح
    }
  }

  /// حساب لون النص للـ AppBar بناءً على الثيم والخلفية
  static Color getAppBarTextColor(BuildContext context, {Color? customBackground}) {
    if (customBackground != null) {
      return getContrastingTextColor(customBackground);
    }

    // التحقق من ثيم التطبيق
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    // إذا كان الثيم فاتح والخلفية شفافة، تحقق من لون scaffold
    if (brightness == Brightness.light) {
      final scaffoldColor = theme.scaffoldBackgroundColor;
      return getContrastingTextColor(scaffoldColor);
    }

    return Colors.white; // الافتراضي للثيم المظلم
  }

  /// تحديد لون النص للـ AppBar مع مراعاة التدرج اللوني
  static Color getAppBarTextColorWithGradient(BuildContext context, List<Color>? gradientColors) {
    if (gradientColors == null || gradientColors.isEmpty) {
      return getAppBarTextColor(context);
    }

    // حساب متوسط luminance للتدرج
    double averageLuminance = 0;
    for (Color color in gradientColors) {
      averageLuminance += color.computeLuminance();
    }
    averageLuminance /= gradientColors.length;

    // تحديد لون النص بناءً على متوسط الإضاءة
    if (averageLuminance > 0.5) {
      return Colors.black87;
    } else {
      return Colors.white;
    }
  }

  /// إضافة ظل للنص لتحسين الوضوح
  static List<Shadow> getTextShadow(Color textColor) {
    if (textColor == Colors.white) {
      // ظل داكن للنص الأبيض
      return [
        Shadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];
    } else {
      // ظل فاتح للنص الداكن
      return [
        Shadow(
          color: Colors.white.withValues(alpha: 0.8),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
    }
  }

  /// إنشاء TextStyle مع لون ذكي وظل
  static TextStyle getSmartTextStyle({
    required BuildContext context,
    required double fontSize,
    FontWeight fontWeight = FontWeight.normal,
    Color? backgroundColor,
    List<Color>? gradientColors,
  }) {
    Color textColor;

    if (gradientColors != null) {
      textColor = getAppBarTextColorWithGradient(context, gradientColors);
    } else {
      textColor = getAppBarTextColor(context, customBackground: backgroundColor);
    }

    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: textColor,
      shadows: getTextShadow(textColor),
      letterSpacing: 0.5,
    );
  }
}
