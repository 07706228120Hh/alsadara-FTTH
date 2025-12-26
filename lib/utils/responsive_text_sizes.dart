import 'package:flutter/material.dart';

class ResponsiveTextSizes {
  static const double _baseWidth = 375.0; // عرض الهاتف المرجعي
  static const double _baseTabletWidth = 768.0; // عرض التابلت المرجعي
  static const double _baseDesktopWidth = 1024.0; // عرض سطح المكتب المرجعي

  /// تحديد نوع الجهاز
  static DeviceType getDeviceType(double screenWidth) {
    if (screenWidth < 600) {
      return DeviceType.mobile;
    } else if (screenWidth < 1024) {
      return DeviceType.tablet;
    } else {
      return DeviceType.desktop;
    }
  }

  /// الحصول على أحجام النصوص حسب نوع الجهاز
  static TextSizes getTextSizes(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final deviceType = getDeviceType(screenWidth);

    switch (deviceType) {
      case DeviceType.mobile:
        return _getMobileTextSizes(screenWidth);
      case DeviceType.tablet:
        return _getTabletTextSizes(screenWidth);
      case DeviceType.desktop:
        return _getDesktopTextSizes(screenWidth);
    }
  }

  static TextSizes _getMobileTextSizes(double screenWidth) {
    // للهواتف - أحجام متكيفة
    final scale = screenWidth / _baseWidth;
    return TextSizes(
  // تقليل حجم عنوان الشريط العلوي قليلاً
  appBarTitle: (16 * scale).clamp(14, 18),
      pageTitle: (24 * scale).clamp(20, 26),
      sectionTitle: (20 * scale).clamp(18, 22),
      cardTitle: (16 * scale).clamp(14, 18),
      bodyText: (14 * scale).clamp(12, 16),
      caption: (12 * scale).clamp(10, 14),
      button: (14 * scale).clamp(12, 16),
  iconSize: (24 * scale).clamp(20, 28),
  // تقليل أيقونات الشريط العلوي
  appBarIconSize: (22 * scale).clamp(18, 22),
    );
  }

  static TextSizes _getTabletTextSizes(double screenWidth) {
    // للتابلت - أحجام متوسطة
    final scale = (screenWidth / _baseTabletWidth).clamp(0.8, 1.3);
    return TextSizes(
  appBarTitle: (20 * scale).clamp(18, 22),
      pageTitle: (28 * scale).clamp(24, 32),
      sectionTitle: (24 * scale).clamp(20, 28),
      cardTitle: (18 * scale).clamp(16, 22),
      bodyText: (16 * scale).clamp(14, 18),
      caption: (14 * scale).clamp(12, 16),
      button: (16 * scale).clamp(14, 18),
  iconSize: (28 * scale).clamp(24, 32),
  appBarIconSize: (24 * scale).clamp(20, 24),
    );
  }

  static TextSizes _getDesktopTextSizes(double screenWidth) {
    // لسطح المكتب - أحجام كبيرة ومقروءة
    final scale = (screenWidth / _baseDesktopWidth).clamp(1.0, 1.8);
    return TextSizes(
  appBarTitle: (22 * scale).clamp(20, 26),
      pageTitle: (34 * scale).clamp(28, 40),
      sectionTitle: (28 * scale).clamp(24, 34),
      cardTitle: (22 * scale).clamp(18, 26),
      bodyText: (18 * scale).clamp(16, 22),
      caption: (16 * scale).clamp(14, 18),
      button: (18 * scale).clamp(16, 22),
  iconSize: (32 * scale).clamp(28, 40),
  appBarIconSize: (26 * scale).clamp(20, 28),
    );
  }

  /// الحصول على padding متجاوب
  static EdgeInsets getPagePadding(BuildContext context) {
    final deviceType = getDeviceType(MediaQuery.of(context).size.width);
    switch (deviceType) {
      case DeviceType.mobile:
        return const EdgeInsets.all(16);
      case DeviceType.tablet:
        return const EdgeInsets.all(24);
      case DeviceType.desktop:
        return const EdgeInsets.all(32);
    }
  }

  /// الحصول على card padding متجاوب
  static EdgeInsets getCardPadding(BuildContext context) {
    final deviceType = getDeviceType(MediaQuery.of(context).size.width);
    switch (deviceType) {
      case DeviceType.mobile:
        return const EdgeInsets.all(12);
      case DeviceType.tablet:
        return const EdgeInsets.all(16);
      case DeviceType.desktop:
        return const EdgeInsets.all(20);
    }
  }

  /// الحصول على spacing متجاوب
  static double getSpacing(BuildContext context, {double factor = 1.0}) {
    final deviceType = getDeviceType(MediaQuery.of(context).size.width);
    double baseSpacing;
    switch (deviceType) {
      case DeviceType.mobile:
        baseSpacing = 8;
        break;
      case DeviceType.tablet:
        baseSpacing = 12;
        break;
      case DeviceType.desktop:
        baseSpacing = 16;
        break;
    }
    return baseSpacing * factor;
  }
}

enum DeviceType { mobile, tablet, desktop }

class TextSizes {
  final double appBarTitle;
  final double pageTitle;
  final double sectionTitle;
  final double cardTitle;
  final double bodyText;
  final double caption;
  final double button;
  final double iconSize;
  final double appBarIconSize;

  const TextSizes({
    required this.appBarTitle,
    required this.pageTitle,
    required this.sectionTitle,
    required this.cardTitle,
    required this.bodyText,
    required this.caption,
    required this.button,
    required this.iconSize,
    required this.appBarIconSize,
  });
}
