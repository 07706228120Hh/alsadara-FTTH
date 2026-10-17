/// أدوات تصميم مشتركة لشاشات سجل العقارات (نواة الصدارة) — عرض فقط.
///
/// مرحَّلة إلى نظام تصميم الصدارة الموحّد (sd): الألوان من [SdColors]، النص Cairo
/// عبر [SdText]، البروز المجسّم عبر [SdDepth]، وحالات الفراغ/الخطأ عبر
/// [SdEmptyState] والشريط العلوي عبر [SdAppBar]. تبقى أسماء/تواقيع الأدوات
/// العامة كما هي حتى لا تنكسر الشاشات المستهلكة.
library;

import 'package:flutter/material.dart';

import '../../frontend/components/sd_app_bar.dart';
import '../../frontend/components/sd_basics.dart';
import '../../frontend/components/sd_raised.dart';
import '../../frontend/tokens/sd_colors.dart';
import '../../frontend/tokens/sd_metrics.dart';
import '../../frontend/tokens/sd_typography.dart';

/// ثوابت/مولّدات بصرية موحّدة لشاشات العقارات (موجّهة لنظام sd).
class PropUi {
  PropUi._();

  static const Color pageBg = SdColors.ground;
  static const Color ink = SdColors.ink;
  static const double radius = SdRadius.lg;
  static const double radiusPill = SdRadius.pill;

  static List<BoxShadow> cardShadow([Color? tint]) {
    return SdDepth.raised(
      glow: tint == null ? const Color(0x591A237E) : tint.withValues(alpha: 0.30),
    );
  }

  static BoxDecoration card() => BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: SdDepth.raised(),
      );

  static Widget gradientBadge({
    required IconData icon,
    required List<Color> colors,
    double size = 44,
    double iconSize = 22,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }

  /// شريط علوي موحّد بهوية الصدارة (sd).
  static PreferredSizeWidget appBar(String title,
      {List<Widget> actions = const [], IconData? leadingIcon}) {
    return SdAppBar(
      title: title,
      actions: actions.isEmpty ? null : actions,
    );
  }
}

/// يحدّ عرض المحتوى على الشاشات العريضة (سطح المكتب) ويوسّطه.
class PropContentWrap extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const PropContentWrap({super.key, required this.child, this.maxWidth = 1000});

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

/// شارة حالة صغيرة (نص + أيقونة + لون دلالي) — pill بنمط sd.
class PropBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const PropBadge({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PropUi.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: color)),
        ],
      ),
    );
  }
}

/// رأس قسم (شارة أيقونة متدرّجة + عنوان + عدّاد/زر اختياري).
class PropSectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> gradient;
  final String? trailingText;
  final Widget? action;

  const PropSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.gradient = SdColors.blueGradient,
    this.trailingText,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        PropUi.gradientBadge(icon: icon, colors: gradient, size: 34, iconSize: 17),
        const SizedBox(width: 10),
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: SdColors.ink)),
        ),
        if (trailingText != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: gradient.first.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(trailingText!,
                style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: gradient.first)),
          ),
        ],
        const Spacer(),
        if (action != null) action!,
      ],
    );
  }
}

/// حالة تحميل موحّدة (sd).
class PropLoadingView extends StatelessWidget {
  final String? message;
  const PropLoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3.2,
              valueColor: AlwaysStoppedAnimation(SdColors.primary),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!,
                textAlign: TextAlign.center,
                style: SdText.bodySm),
          ],
        ],
      ),
    );
  }
}

/// حالة خطأ موحّدة مع زرّ إعادة (sd).
class PropErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const PropErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SdEmptyState(
        title: message,
        icon: Icons.error_outline_rounded,
        status: SdStatus.danger,
        action: onRetry == null
            ? null
            : SdButton(
                label: 'إعادة المحاولة',
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
      ),
    );
  }
}

/// حالة فراغ موحّدة (sd).
class PropEmptyView extends StatelessWidget {
  final String message;
  final IconData icon;
  final Widget? action;
  const PropEmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SdEmptyState(
        title: message,
        icon: icon,
        status: SdStatus.neutral,
        action: action,
      ),
    );
  }
}
