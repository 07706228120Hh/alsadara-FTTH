import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// خدمة إدارة أحجام النصوص المتجاوبة
/// تحل مشكلة كبر النصوص على الحاسوب في جميع صفحات المشروع
class ResponsiveTextService {
  static ResponsiveTextService? _instance;
  static ResponsiveTextService get instance => _instance ??= ResponsiveTextService._();
  ResponsiveTextService._();

  late double _textScaleFactor;
  late bool _isDesktop;
  late bool _isTablet;
  late bool _isMobile;

  /// تهيئة الخدمة مع سياق التطبيق
  void initialize(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    _isDesktop = screenWidth > 1024;
    _isTablet = screenWidth > 600 && screenWidth <= 1024;
    _isMobile = screenWidth <= 600;

    // تحديد معامل التحجيم حسب نوع الجهاز
    if (_isDesktop) {
      _textScaleFactor = 0.4; // تقليل 60% على الحاسوب
    } else if (_isTablet) {
      _textScaleFactor = 0.65; // تقليل 35% على التابلت
    } else {
      _textScaleFactor = 1.0; // الحجم الطبيعي على الهاتف
    }
  }

  /// الحصول على حجم النص المتجاوب
  double getResponsiveTextSize(double originalSize) {
    return (originalSize * _textScaleFactor).sp;
  }

  /// الحصول على حجم الأيقونة المتجاوب
  double getResponsiveIconSize(double originalSize) {
    return (originalSize * _textScaleFactor).sp;
  }

  /// الحصول على حجم الحشو المتجاوب
  double getResponsivePadding(double originalPadding) {
    return (originalPadding * _textScaleFactor).w;
  }

  /// الحصول على ارتفاع متجاوب
  double getResponsiveHeight(double originalHeight) {
    return (originalHeight * _textScaleFactor).h;
  }

  /// الحصول على عرض متجاوب
  double getResponsiveWidth(double originalWidth) {
    return (originalWidth * _textScaleFactor).w;
  }

  // خصائص مفيدة للوصول السريع
  bool get isDesktop => _isDesktop;
  bool get isTablet => _isTablet;
  bool get isMobile => _isMobile;
  double get textScaleFactor => _textScaleFactor;

  /// دوال مختصرة للاستخدام السريع

  // أحجام النصوص الشائعة
  double get verySmallText => getResponsiveTextSize(10);
  double get smallText => getResponsiveTextSize(12);
  double get normalText => getResponsiveTextSize(14);
  double get mediumText => getResponsiveTextSize(16);
  double get largeText => getResponsiveTextSize(18);
  double get veryLargeText => getResponsiveTextSize(20);
  double get extraLargeText => getResponsiveTextSize(24);

  // أحجام الأيقونات الشائعة
  double get smallIcon => getResponsiveIconSize(16);
  double get normalIcon => getResponsiveIconSize(20);
  double get mediumIcon => getResponsiveIconSize(24);
  double get largeIcon => getResponsiveIconSize(28);
  double get extraLargeIcon => getResponsiveIconSize(32);

  // مسافات الحشو الشائعة
  double get tinyPadding => getResponsivePadding(4);
  double get smallPadding => getResponsivePadding(8);
  double get normalPadding => getResponsivePadding(12);
  double get mediumPadding => getResponsivePadding(16);
  double get largePadding => getResponsivePadding(20);
  double get extraLargePadding => getResponsivePadding(24);

  /// إنشاء TextStyle متجاوب
  TextStyle createResponsiveTextStyle({
    required double fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontSize: getResponsiveTextSize(fontSize),
      fontWeight: fontWeight ?? FontWeight.normal,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// إنشاء EdgeInsets متجاوب
  EdgeInsets createResponsivePadding({
    double? all,
    double? horizontal,
    double? vertical,
    double? left,
    double? right,
    double? top,
    double? bottom,
  }) {
    if (all != null) {
      return EdgeInsets.all(getResponsivePadding(all));
    }

    return EdgeInsets.only(
      left: getResponsivePadding(left ?? horizontal ?? 0),
      right: getResponsivePadding(right ?? horizontal ?? 0),
      top: getResponsivePadding(top ?? vertical ?? 0),
      bottom: getResponsivePadding(bottom ?? vertical ?? 0),
    );
  }

  /// إنشاء Size متجاوب
  Size createResponsiveSize(double width, double height) {
    return Size(
      getResponsiveWidth(width),
      getResponsiveHeight(height),
    );
  }
}

/// Widget مساعد للوصول السريع للخدمة
class ResponsiveText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight? fontWeight;
  final Color? color;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? letterSpacing;
  final double? height;

  const ResponsiveText(
    this.text, {
    required this.fontSize,
    this.fontWeight,
    this.color,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.letterSpacing,
    this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ResponsiveTextService.instance.createResponsiveTextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Extension للوصول السريع
extension ResponsiveDouble on double {
  /// تحويل الرقم إلى حجم نص متجاوب
  double get rt => ResponsiveTextService.instance.getResponsiveTextSize(this);

  /// تحويل الرقم إلى حجم أيقونة متجاوب
  double get ri => ResponsiveTextService.instance.getResponsiveIconSize(this);

  /// تحويل الرقم إلى حشو متجاوب
  double get rp => ResponsiveTextService.instance.getResponsivePadding(this);

  /// تحويل الرقم إلى ارتفاع متجاوب
  double get rh => ResponsiveTextService.instance.getResponsiveHeight(this);

  /// تحويل الرقم إلى عرض متجاوب
  double get rw => ResponsiveTextService.instance.getResponsiveWidth(this);
}
