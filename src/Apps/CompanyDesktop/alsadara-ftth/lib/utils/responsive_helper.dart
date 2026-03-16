/// أداة مساعدة للتجاوب مع أحجام الشاشات المختلفة
/// تدعم الهاتف والتابلت وسطح المكتب
/// تستخدم المساحة المتاحة فعلياً (بعد SafeArea وأشرطة النظام)
library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// نوع الجهاز المكتشف
enum ScreenType { mobile, tablet, desktop }

/// أداة مركزية للتجاوب - تُستخدم عبر كل الشاشات
class ResponsiveHelper {
  final BuildContext context;

  const ResponsiveHelper(this.context);

  // ─── حجم الشاشة المتاحة (بعد SafeArea وأشرطة النظام) ───

  /// عرض الشاشة المتاح فعلياً
  double get availableWidth => MediaQuery.of(context).size.width;

  /// ارتفاع الشاشة المتاح فعلياً
  double get availableHeight => MediaQuery.of(context).size.height;

  /// padding النظام (أشرطة الحالة والتنقل)
  EdgeInsets get systemPadding => MediaQuery.of(context).padding;

  /// الارتفاع الآمن بعد استبعاد أشرطة النظام
  double get safeHeight =>
      availableHeight - systemPadding.top - systemPadding.bottom;

  /// العرض الآمن بعد استبعاد أشرطة النظام
  double get safeWidth =>
      availableWidth - systemPadding.left - systemPadding.right;

  // ─── تحديد نوع الجهاز ───

  /// هل هو منصة هاتف محمول؟
  static bool get isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// هل هو منصة سطح مكتب؟
  static bool get isDesktopPlatform {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// نوع الشاشة بناءً على العرض المتاح
  ScreenType get screenType {
    if (availableWidth <= 600) return ScreenType.mobile;
    if (availableWidth <= 1024) return ScreenType.tablet;
    return ScreenType.desktop;
  }

  bool get isMobile => screenType == ScreenType.mobile;
  bool get isTablet => screenType == ScreenType.tablet;
  bool get isDesktop => screenType == ScreenType.desktop;

  /// هل الشاشة ضيقة (هاتف أو تابلت صغير)؟
  bool get isNarrow => availableWidth <= 700;

  /// هل الشاشة عريضة بما يكفي للسايدبار؟
  bool get showSidebar => availableWidth > 700;

  // ─── أعمدة الشبكة ───

  /// عدد أعمدة القائمة للشبكات الرئيسية
  int get gridColumns {
    if (availableWidth > 1200) return 4;
    if (availableWidth > 900) return 3;
    if (availableWidth > 600) return 2;
    return 2;
  }

  /// عدد أعمدة العدادات في الصف
  int get counterColumns {
    if (availableWidth > 700) return 3;
    if (availableWidth > 400) return 3;
    return 2; // هاتف صغير جداً
  }

  // ─── أحجام النص المتجاوبة ───

  /// عامل مقياس النص بناءً على العرض
  double get textScaleFactor {
    if (isMobile) return (availableWidth / 375).clamp(0.75, 1.1);
    if (isTablet) return (availableWidth / 768).clamp(0.85, 1.15);
    return (availableWidth / 1440).clamp(0.9, 1.3);
  }

  // ─── معامل التحجيم النسبي للموبايل (مرجع: 375px) ───
  // يجعل كل الأحجام تتناسب مع عرض الشاشة تلقائياً
  double get mobileScale => (availableWidth / 375).clamp(0.78, 1.1);

  /// دالة مساعدة: تطبق التحجيم التناسبي على الموبايل وتبقي التابلت والديسكتوب ثابتة
  double scaled(double mobile, double tablet, double desktop) {
    if (isMobile) return mobile * mobileScale;
    if (isTablet) return tablet;
    return desktop;
  }

  // Keep old private names as aliases for backward compatibility
  double get _mobileScale => mobileScale;
  double _scaled(double mobile, double tablet, double desktop) =>
      scaled(mobile, tablet, desktop);

  double get titleSize => scaled(15, 18, 20);
  double get subtitleSize => scaled(12, 13, 14);
  double get bodySize => scaled(12, 13, 14);
  double get captionSize => scaled(10, 11, 12);
  double get appBarTitleSize => scaled(16, 18, 20);
  double get counterValueSize => scaled(14, 16, 17);
  double get counterLabelSize => scaled(9, 10, 10);
  double get menuItemTitleSize => scaled(12, 14, 16);
  double get menuItemSubtitleSize => scaled(9, 11, 12);

  // ─── أحجام الأيقونات المتجاوبة (نسبية على الموبايل) ───

  double get iconSizeSmall => scaled(16, 18, 20);
  double get iconSizeMedium => scaled(20, 22, 24);
  double get iconSizeLarge => scaled(24, 26, 30);
  double get appBarIconSize => scaled(22, 26, 28);

  // ─── أحجام العناصر المتجاوبة (نسبية على الموبايل) ───

  /// ارتفاع بطاقة القائمة (الحد الأدنى)
  double get menuItemHeight => scaled(52, 66, 72);

  /// حجم أيقونة القائمة الدائرية
  double get menuIconCircleSize => scaled(32, 42, 48);

  /// حجم أيقونة القائمة الداخلية
  double get menuIconInnerSize => scaled(16, 21, 24);

  /// حجم دائرة السهم/القفل
  double get menuArrowCircleSize => scaled(22, 28, 32);

  /// حجم أيقونة السهم
  double get menuArrowIconSize => scaled(12, 13, 14);

  /// ارتفاع شريط التطبيق
  double get appBarHeight => scaled(56, 64, 70);

  /// حجم دائرة العداد
  double get counterCircleSize => scaled(60, 70, 80);

  /// حجم صورة المستخدم
  double get userAvatarSize => scaled(32, 36, 40);

  /// حجم Lottie
  double get lottieSize => scaled(36, 40, 44);

  /// حجم زر المعلومات
  double get infoButtonSize => scaled(26, 28, 30);

  // ─── المسافات والهوامش المتجاوبة ───

  /// هوامش المحتوى الأفقية
  double get contentPaddingH {
    if (isMobile) return 12.0;
    if (isTablet) return 18.0;
    return 24.0;
  }

  /// المسافة بين عناصر الشبكة
  double get gridSpacing {
    if (isMobile) return 8.0;
    if (isTablet) return 10.0;
    return 14.0;
  }

  /// المسافة بين العدادات
  double get counterSpacing {
    if (isMobile) return 6.0;
    if (isTablet) return 8.0;
    return 12.0;
  }

  /// padding بطاقة العداد
  EdgeInsets get counterCardPadding {
    if (isMobile) {
      return const EdgeInsets.symmetric(vertical: 8, horizontal: 6);
    }
    if (isTablet) {
      return const EdgeInsets.symmetric(vertical: 10, horizontal: 8);
    }
    return const EdgeInsets.symmetric(vertical: 14, horizontal: 10);
  }

  /// الحد الأقصى لعرض المحتوى
  double get maxContentWidth {
    if (availableWidth > 1440) return 1200.0;
    if (availableWidth > 1024) return 1000.0;
    if (availableWidth > 768) return 800.0;
    return double.infinity;
  }

  /// عرض السايدبار عند التوسع
  double get sidebarExpandedWidth {
    if (isTablet) return 180.0;
    return 200.0;
  }

  /// عرض السايدبار عند الطي
  double get sidebarCollapsedWidth => 56.0;

  // ─── نصف قطر الحدود المتجاوب ───

  double get cardRadius {
    if (isMobile) return 12.0;
    if (isTablet) return 14.0;
    return 16.0;
  }

  double get buttonRadius {
    if (isMobile) return 8.0;
    return 10.0;
  }

  // ─── أحجام نصوص إضافية للأزرار والبطاقات (نسبية على الموبايل) ───

  double get buttonTextSize => scaled(11, 13, 14);
  double get cardTitleSize => scaled(12, 14, 16);
  double get cardSubtitleSize => scaled(10, 11, 12);
  double get sectionTitleSize => scaled(14, 16, 18);
  double get statValueSize => scaled(18, 22, 26);
  double get labelSize => scaled(10, 11, 12);
  double get cardPadding => scaled(10, 14, 16);
  double get emptyStateIconSize => scaled(48, 56, 64);

  // ─── حجم الحوارات المتجاوبة ───

  /// أقصى عرض للحوارات
  double get dialogMaxWidth {
    final maxW = availableWidth * 0.9;
    if (isMobile) return maxW.clamp(280, 400);
    if (isTablet) return maxW.clamp(350, 500);
    return maxW.clamp(400, 600);
  }

  /// أقصى ارتفاع للحوارات
  double get dialogMaxHeight {
    return safeHeight * 0.85;
  }
}

/// Extension لسهولة الاستخدام من أي BuildContext
extension ResponsiveContext on BuildContext {
  ResponsiveHelper get responsive => ResponsiveHelper(this);
}

/// Widget يختار التخطيط المناسب بناءً على حجم الشاشة المتاحة
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= 600) {
          return mobile;
        } else if (constraints.maxWidth <= 1024) {
          return tablet ?? desktop;
        } else {
          return desktop;
        }
      },
    );
  }
}

/// Widget يلف المحتوى بـ SafeArea مع ConstrainedBox
class SafeResponsiveBody extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;

  const SafeResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Container(
      color: backgroundColor,
      child: SafeArea(
        child: Padding(
          padding:
              padding ?? EdgeInsets.symmetric(horizontal: r.contentPaddingH),
          child: maxWidth != null
              ? Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth!),
                    child: child,
                  ),
                )
              : child,
        ),
      ),
    );
  }
}
