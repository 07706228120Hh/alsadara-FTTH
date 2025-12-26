import 'package:flutter/material.dart';

/// نظام نمطي موحّد (Typography Tokens)
/// هدفه: تقليل الإستخدام العشوائي للأرقام (fontSize: 22 / 24 / 18 ...) في الصفحات
/// وتعويضه بأنماط (semantic) ثابتة تساعد في توحيد المظهر بين الهاتف والحاسوب.
///
/// الخطوات المقترحة للاعتماد:
/// 1. استبدل كل TextStyle يدوي يحتوي (fontSize: رقم) بأقرب نمط هنا.
/// 2. لو احتجت حجماً مختلفاً تماماً، أضفه هنا أولاً بدلاً من كتابته داخل الصفحة.
/// 3. استخدم Theme.of(context).extension<AppTypography>() للوصول.
///
/// المجموعات:
/// - Display: عناوين رئيسية كبيرة (نادراً داخل التطبيق) => display
/// - Title: عناوين صفحات وأقسام => titleLarge / title / titleSmall
/// - Body: نصوص عادية وفقرة => body / bodySmall / bodyTiny
/// - Label: أزرار / تسميات صغيرة => label / labelSmall
/// - Mono: نصوص أحادية (logs / code) => mono
class AppTypography extends ThemeExtension<AppTypography> {
  final TextStyle display;
  final TextStyle titleLarge;
  final TextStyle title;
  final TextStyle titleSmall;
  final TextStyle body;
  final TextStyle bodySmall;
  final TextStyle bodyTiny;
  final TextStyle label;
  final TextStyle labelSmall;
  final TextStyle mono;

  const AppTypography({
    required this.display,
    required this.titleLarge,
    required this.title,
    required this.titleSmall,
    required this.body,
    required this.bodySmall,
    required this.bodyTiny,
    required this.label,
    required this.labelSmall,
    required this.mono,
  });

  @override
  AppTypography copyWith({
    TextStyle? display,
    TextStyle? titleLarge,
    TextStyle? title,
    TextStyle? titleSmall,
    TextStyle? body,
    TextStyle? bodySmall,
    TextStyle? bodyTiny,
    TextStyle? label,
    TextStyle? labelSmall,
    TextStyle? mono,
  }) => AppTypography(
        display: display ?? this.display,
        titleLarge: titleLarge ?? this.titleLarge,
        title: title ?? this.title,
        titleSmall: titleSmall ?? this.titleSmall,
        body: body ?? this.body,
        bodySmall: bodySmall ?? this.bodySmall,
        bodyTiny: bodyTiny ?? this.bodyTiny,
        label: label ?? this.label,
        labelSmall: labelSmall ?? this.labelSmall,
        mono: mono ?? this.mono,
      );

  @override
  ThemeExtension<AppTypography> lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    TextStyle lerpStyle(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTypography(
      display: lerpStyle(display, other.display),
      titleLarge: lerpStyle(titleLarge, other.titleLarge),
      title: lerpStyle(title, other.title),
      titleSmall: lerpStyle(titleSmall, other.titleSmall),
      body: lerpStyle(body, other.body),
      bodySmall: lerpStyle(bodySmall, other.bodySmall),
      bodyTiny: lerpStyle(bodyTiny, other.bodyTiny),
      label: lerpStyle(label, other.label),
      labelSmall: lerpStyle(labelSmall, other.labelSmall),
      mono: lerpStyle(mono, other.mono),
    );
  }

  /// مُنشئ جاهز يُبنى حسب المقياس النهائي (overallScale)
  factory AppTypography.build(double scale, {String? fontFamily}) {
    TextStyle base(double size, {FontWeight w = FontWeight.w400, double? letter, double? height, FontStyle? style, Color? color, bool mono = false}) {
      return TextStyle(
        fontSize: size * scale,
        fontWeight: w,
        letterSpacing: letter,
        height: height,
        fontFamily: mono ? 'monospace' : fontFamily,
        color: color,
      );
    }

    return AppTypography(
      display: base(30, w: FontWeight.w700),
      titleLarge: base(22, w: FontWeight.w700),
      title: base(18, w: FontWeight.w600),
      titleSmall: base(16, w: FontWeight.w600),
      body: base(14, w: FontWeight.w400, height: 1.3),
      bodySmall: base(13, w: FontWeight.w400, height: 1.3),
      bodyTiny: base(11.5, w: FontWeight.w400, height: 1.25),
      label: base(13, w: FontWeight.w600),
      labelSmall: base(11, w: FontWeight.w500),
      mono: base(13, w: FontWeight.w500, mono: true, height: 1.2),
    );
  }
}

extension AppTypographyX on BuildContext {
  AppTypography get typography => Theme.of(this).extension<AppTypography>()!;
}
