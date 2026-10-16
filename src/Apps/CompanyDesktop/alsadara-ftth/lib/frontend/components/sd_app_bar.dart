/// الشريط العلوي الموحّد: نيلي بحافّة سفلية بارزة، عنوان + سطر حالة اختياري،
/// وأزرار إجراءات بأسماء (لا أيقونات مبهمة).
library;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_responsive.dart';
import '../tokens/sd_typography.dart';

class SdAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SdAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleOk,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  final String title;

  /// سطر ثانوي تحت العنوان (مثل حالة الاتصال).
  final String? subtitle;

  /// null = سطر عادي، true = نقطة خضراء، false = نقطة حمراء.
  final bool? subtitleOk;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  static const double _edge = 6;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (subtitle != null ? 10 : 0) + _edge);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: SdColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: leading,
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: kToolbarHeight + (subtitle != null ? 10 : 0),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: context.sd.appBarTitle,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
          if (subtitle != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitleOk != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: subtitleOk! ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC8E6C9))),
                ),
              ],
            ),
        ],
      ),
      actions: actions == null
          ? null
          : [
              ...actions!,
              const SizedBox(width: SdSpace.xs),
            ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(_edge),
        child: SizedBox(
          height: _edge,
          width: double.infinity,
          child: ColoredBox(color: SdColors.primaryEdge),
        ),
      ),
    );
  }
}

/// زر إجراء في الشريط العلوي: أيقونة + اسم (يختفي الاسم في الشاشات الضيقة
/// ويبقى كتلميح).
class SdAppBarAction extends StatelessWidget {
  const SdAppBarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// تنبيه (مثل «الموقع متوقف») بلون أحمر فاتح.
  final bool danger;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    // الاسم بجانب الأيقونة على سطح المكتب فقط؛ الهاتف والآيباد: أيقونة + تلميح.
    final l = context.sd;
    final wide = l.isDesktop;
    final bg = danger ? SdColors.dangerTint : SdColors.primaryMid;
    final fg = danger ? const Color(0xFFB71C1C) : Colors.white;
    final edge = danger ? const Color(0xFFE57373) : const Color(0xFF0B1150);
    final button = Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(SdRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          onTap: onPressed,
          child: Container(
            height: l.touchTarget,
            constraints: BoxConstraints(minWidth: l.touchTarget),
            padding: EdgeInsets.symmetric(horizontal: wide ? 14 : 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SdRadius.sm),
              boxShadow: [BoxShadow(color: edge, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: fg),
                if (wide) ...[
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontFamily: SdText.family,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: fg)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: (badge ?? 0) > 0
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  button,
                  PositionedDirectional(
                    top: -4,
                    end: -4,
                    child: _MiniBadge(count: badge!),
                  ),
                ],
              )
            : button,
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SdColors.danger,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: SdColors.primary, width: 1.5),
      ),
      child: Text(count > 99 ? '+99' : '$count',
          style: const TextStyle(
              fontFamily: SdText.family,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.1)),
    );
  }
}
