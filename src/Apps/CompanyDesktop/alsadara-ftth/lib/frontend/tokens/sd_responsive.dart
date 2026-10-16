/// التجاوب مع الهاتف والآيباد وسطح المكتب — نظام تصميم الصدارة.
///
/// نقاط الفصل نفسها المستخدمة في المشروع (utils/breakpoints.dart):
///   هاتف < 600 ≤ آيباد < 1024 ≤ سطح مكتب
///
/// الاستخدام داخل أي ودجت:
/// ```dart
/// final l = context.sd;
/// padding: EdgeInsets.all(l.gutter)
/// columns: l.pick(phone: 1, tablet: 2, desktop: 4)
/// ```
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum SdDevice { phone, tablet, desktop }

class SdBreakpoints {
  SdBreakpoints._();
  static const double phoneMax = 600;
  static const double tabletMax = 1024;

  static SdDevice deviceFor(double width) {
    if (width < phoneMax) return SdDevice.phone;
    if (width < tabletMax) return SdDevice.tablet;
    return SdDevice.desktop;
  }
}

/// معلومات التخطيط الحالية + قيم جاهزة لكل جهاز.
@immutable
class SdLayout {
  const SdLayout._({
    required this.width,
    required this.height,
    required this.device,
    required this.touch,
    required this.padding,
  });

  factory SdLayout.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final platform = Theme.of(context).platform;
    final mobileOs = !kIsWeb &&
        (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
    return SdLayout._(
      width: w,
      height: mq.size.height,
      device: SdBreakpoints.deviceFor(w),
      touch: mobileOs,
      padding: mq.padding,
    );
  }

  /// تخطيط لعرض محدّد (داخل LayoutBuilder) مع وراثة نوع الإدخال من السياق.
  SdLayout forWidth(double w) => SdLayout._(
        width: w,
        height: height,
        device: SdBreakpoints.deviceFor(w),
        touch: touch,
        padding: padding,
      );

  final double width;
  final double height;
  final SdDevice device;

  /// جهاز لمسي (أندرويد/iOS): أهداف لمس أكبر وبلا تأثيرات المرور.
  final bool touch;

  /// حواف النظام (النتوء/شريط الإيماءات).
  final EdgeInsets padding;

  bool get isPhone => device == SdDevice.phone;
  bool get isTablet => device == SdDevice.tablet;
  bool get isDesktop => device == SdDevice.desktop;
  bool get isLandscape => width > height;

  /// هاتف صغير جداً (< 360) — يُخفى فيه النص الثانوي الطويل.
  bool get isCompactPhone => width < 360;

  /// اختيار قيمة حسب الجهاز (tablet اختياري؛ يأخذ قيمة desktop إن غاب).
  T pick<T>({required T phone, T? tablet, required T desktop}) {
    switch (device) {
      case SdDevice.phone:
        return phone;
      case SdDevice.tablet:
        return tablet ?? desktop;
      case SdDevice.desktop:
        return desktop;
    }
  }

  // ── قيم جاهزة ──

  /// الحشو الجانبي للصفحة.
  double get gutter => pick(phone: 14, tablet: 20, desktop: 24);

  /// المسافة بين أقسام الصفحة.
  double get sectionGap => pick(phone: 18, tablet: 22, desktop: 28);

  /// المسافة بين البطاقات في الشبكات.
  double get gridGap => pick(phone: 12, tablet: 16, desktop: 18);

  /// أدنى ارتفاع لهدف اللمس/النقر.
  double get touchTarget => touch ? 48 : 44;

  /// حجم مكعّب الأيقونة في البلاطات.
  double get cubeSize => pick(phone: 44, tablet: 50, desktop: 52);

  /// حجم عنوان الصفحة في الشريط العلوي.
  double get appBarTitle => pick(phone: 16, tablet: 17, desktop: 18);

  /// عدد أعمدة شبكة لعرض [available] وأدنى عرض بلاطة [minTile].
  int columnsFor(double available, {double minTile = 250, int max = 4, double? gap}) {
    final g = gap ?? gridGap;
    final c = ((available + g) / (minTile + g)).floor();
    return c.clamp(1, max);
  }
}

extension SdLayoutContext on BuildContext {
  /// معلومات التجاوب: `context.sd.isPhone`، `context.sd.gutter`…
  SdLayout get sd => SdLayout.of(this);
}

/// يبني واجهة مختلفة لكل جهاز (tablet اختياري).
class SdAdaptive extends StatelessWidget {
  const SdAdaptive({super.key, required this.phone, this.tablet, required this.desktop});
  final WidgetBuilder phone;
  final WidgetBuilder? tablet;
  final WidgetBuilder desktop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final l = ctx.sd.forWidth(c.maxWidth);
      return l.pick(phone: phone, tablet: tablet, desktop: desktop)(ctx);
    });
  }
}

/// لوحتان (قائمة + تفاصيل): جنباً إلى جنب على الآيباد الأفقي وسطح المكتب،
/// وواحدة فوق الأخرى (أو القائمة وحدها) على الهاتف.
class SdTwoPane extends StatelessWidget {
  const SdTwoPane({
    super.key,
    required this.primary,
    required this.secondary,
    this.splitAt = 900,
    this.primaryFlex = 2,
    this.secondaryFlex = 3,
    this.showSecondaryWhenStacked = true,
  });

  final Widget primary;
  final Widget secondary;

  /// أقل عرض لعرض اللوحتين جنباً إلى جنب.
  final double splitAt;
  final int primaryFlex;
  final int secondaryFlex;

  /// على الهاتف: هل تظهر اللوحة الثانية تحت الأولى؟ (false = تُفتح بشاشة مستقلة).
  final bool showSecondaryWhenStacked;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final gap = ctx.sd.forWidth(c.maxWidth).gridGap;
      if (c.maxWidth >= splitAt) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: primaryFlex, child: primary),
            SizedBox(width: gap),
            Expanded(flex: secondaryFlex, child: secondary),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          if (showSecondaryWhenStacked) ...[SizedBox(height: gap), secondary],
        ],
      );
    });
  }
}
