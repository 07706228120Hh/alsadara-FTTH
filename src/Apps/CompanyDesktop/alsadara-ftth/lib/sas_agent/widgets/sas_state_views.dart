import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)

/// نظام تصميم موحّد لوحدة «وكيل الساس» بثيم منصّة الصدارة الموحّد (sd).
///
/// ملف ودجات عرض فقط (حالات/بطاقات/رؤوس) — لا منطق أعمال ولا استدعاءات API.
/// يعتمد رموز نظام تصميم الصدارة (SdColors/SdText/SdRadius/SdDepth) وخط Cairo
/// وحواف مستديرة وبروز ثلاثي الأبعاد كما في بقية شاشات المنصّة المرحَّلة.
///
/// الأسماء والتواقيع العامة مُبقاة كما كانت (لئلا تنكسر مستهلكاتها)، وأُعيد
/// تنفيذها بصرياً برموز sd بدل AppTheme/GoogleFonts/screenutil.

/// أدوات تنسيق مشتركة للوحدة (ثوابت بصرية + مولّدات ديكور) بنبرة sd.
class SasUi {
  SasUi._();

  /// خلفية الوحدة — خلفية صفحات الصدارة.
  static const Color pageBg = SdColors.ground;

  static const double radius = SdRadius.lg;
  static const double radiusSm = SdRadius.sm;
  static const double radiusPill = SdRadius.pill;

  /// ظل بطاقة بارزة (حافّة صلبة + توهّج ناعم) بنبرة sd.
  static List<BoxShadow> cardShadow([Color? tint]) {
    return SdDepth.raised(
      edge: SdColors.cardEdge,
      glow: (tint ?? SdColors.primary).withValues(alpha: 0.18),
    );
  }

  /// ديكور بطاقة بيضاء بارزة بنمط sd.
  static BoxDecoration card({
    Color? borderColor,
    double borderWidth = 1.2,
    List<BoxShadow>? shadow,
    double? radius,
  }) {
    return BoxDecoration(
      color: SdColors.surface,
      borderRadius: BorderRadius.circular(radius ?? SasUi.radius),
      border: borderColor != null
          ? Border.all(color: borderColor, width: borderWidth)
          : null,
      boxShadow: shadow ?? cardShadow(),
    );
  }

  /// أيقونة مربّعة بارزة (شارة للبطاقات/الرؤوس) بنمط مكعّب sd.
  static Widget gradientBadge({
    required IconData icon,
    required List<Color> colors,
    double size = 44,
    double iconSize = 22,
  }) {
    final base = colors.isNotEmpty ? colors.first : SdColors.primary;
    final edge = colors.length > 1 ? colors.last : SdColors.primaryEdge;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [BoxShadow(color: edge, offset: const Offset(0, 3))],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

/// يحدّ عرض المحتوى الرئيسي على الشاشات العريضة (سطح المكتب) ويوسّطه.
class SasContentWrap extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const SasContentWrap({super.key, required this.child, this.maxWidth = 1100});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// رأس قسم (شارة أيقونة بارزة + عنوان + عدّاد/زر اختياري) بنبرة sd.
class SasSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> gradient;
  final String? trailingText;
  final Widget? action;

  const SasSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.gradient = const [SdColors.primaryLight, SdColors.primary],
    this.trailingText,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final base = gradient.isNotEmpty ? gradient.first : SdColors.primary;
    return Row(
      children: [
        SasUi.gradientBadge(
          icon: icon,
          colors: gradient,
          size: 34,
          iconSize: 18,
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(title, style: SdText.titleSm)),
        if (trailingText != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: base.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SdRadius.pill),
            ),
            child: Text(
              trailingText!,
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: base,
              ),
            ),
          ),
        ],
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}

/// شارة حالة صغيرة (نص + لون دلالي) — pill.
class SasStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const SasStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(SdRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة تحميل موحّدة لوحدة وكيل الساس.
///
/// ملفوفة بتمرير آمن (`_ScrollSafeCenter`) بمقاسات ثابتة معقولة فلا يحدث تجاوز
/// عمودي مهما ضاق ارتفاع النافذة/حاوية التبويب.
class SasLoadingView extends StatelessWidget {
  final String? message;
  const SasLoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return _ScrollSafeCenter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3.2,
              valueColor: AlwaysStoppedAnimation(SdColors.primary),
              backgroundColor: SdColors.primaryTint,
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: SdText.bodySm,
            ),
          ],
        ],
      ),
    );
  }
}

/// حالة خطأ موحّدة مع زر إعادة المحاولة.
class SasErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const SasErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return _ScrollSafeCenter(
      child: SdEmptyState(
        title: 'تعذّر تحميل البيانات',
        message: message,
        icon: Icons.error_outline_rounded,
        status: SdStatus.danger,
        action: onRetry == null
            ? null
            : SdButton(
                label: 'إعادة المحاولة',
                icon: Icons.refresh_rounded,
                kind: SdButtonKind.primary,
                onPressed: onRetry,
              ),
      ),
    );
  }
}

/// حالة فراغ موحّدة.
class SasEmptyView extends StatelessWidget {
  final String message;
  final IconData icon;
  final Widget? action;
  const SasEmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return _ScrollSafeCenter(
      child: SdEmptyState(
        title: message,
        icon: icon,
        status: SdStatus.neutral,
        action: action,
      ),
    );
  }
}

/// يوسّط محتوى الحالة عمودياً وأفقياً مع تمرير آمن يمنع أي تجاوز عمودي
/// (`BOTTOM OVERFLOWED`) عندما يقلّ ارتفاع الحاوية عن ارتفاع المحتوى.
class _ScrollSafeCenter extends StatelessWidget {
  final Widget child;
  const _ScrollSafeCenter({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight.isFinite
                  ? constraints.maxHeight - 48 // خصم الحشوة العلوية/السفلية
                  : 0,
            ),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

/// بطاقة إحصائية (رقم كبير + عنوان + أيقونة) بثيم الصدارة — بروز sd ثلاثي الأبعاد.
class SasStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const SasStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: SdDepth.raised(glow: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.28), offset: const Offset(0, 3)),
              ],
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: color,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 1),
              Text(label, style: SdText.caption),
            ],
          ),
        ],
      ),
    );
  }
}
