/// أدوات تصميم مشتركة لشاشات سجل العقارات (نواة الصدارة) — عرض فقط.
///
/// مستقلّة عن وحدة الساس (`lib/sas_agent/`): تعيد نفس اللغة البصرية (ألوان
/// [AppTheme] + Cairo + حواف مستديرة + ظلال ناعمة) لكن ضمن النظام الأساسي.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';

/// ثوابت/مولّدات بصرية موحّدة لشاشات العقارات.
class PropUi {
  PropUi._();

  static const Color pageBg = Color(0xFFF4F6FB);
  static const Color ink = Color(0xFF1A1A2E);
  static const double radius = 16;
  static const double radiusPill = 40;

  static List<BoxShadow> cardShadow([Color? tint]) {
    final base = tint ?? AppTheme.primaryColor;
    return [
      BoxShadow(
        color: base.withValues(alpha: 0.07),
        blurRadius: 14,
        spreadRadius: -3,
        offset: const Offset(0, 6),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 4,
        offset: const Offset(0, 1),
      ),
    ];
  }

  static BoxDecoration card() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.16), width: 1.2),
        boxShadow: cardShadow(),
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

  /// شريط علوي موحّد بتدرّج الصدارة.
  static PreferredSizeWidget appBar(String title,
      {List<Widget> actions = const [], IconData? leadingIcon}) {
    return AppBar(
      elevation: 0,
      toolbarHeight: 62,
      backgroundColor: AppTheme.primaryColor,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.blueGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
              ),
              child: Icon(leadingIcon, size: 19, color: Colors.white),
            ),
            const SizedBox(width: 10),
          ],
          Text(title,
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 17)),
        ],
      ),
      actions: actions,
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

/// شارة حالة صغيرة (نص + أيقونة + لون دلالي) — pill.
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
              style: GoogleFonts.cairo(
                  fontSize: 11, fontWeight: FontWeight.w800, color: color)),
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
    this.gradient = AppTheme.blueGradient,
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
              style: GoogleFonts.cairo(
                  fontSize: 15, fontWeight: FontWeight.w800, color: PropUi.ink)),
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
                style: GoogleFonts.cairo(
                    fontSize: 11,
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

/// حالة تحميل موحّدة.
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
              valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}

/// حالة خطأ موحّدة مع زرّ إعادة.
class PropErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const PropErrorView({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 42, color: AppTheme.errorColor),
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                    height: 1.5)),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded),
                label: Text('إعادة المحاولة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// حالة فراغ موحّدة.
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  size: 46,
                  color: AppTheme.primaryColor.withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    height: 1.5)),
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
