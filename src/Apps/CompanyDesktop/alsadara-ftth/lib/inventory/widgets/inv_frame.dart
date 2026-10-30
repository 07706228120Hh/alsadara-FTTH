import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';

/// ── إطار المخزون البارز ──────────────────────────────────────────────
/// حدّ أوضح قليلاً + ظل أعمق من البطاقة القياسية، مخصّص لشاشات المخزون
/// فقط (لا يمسّ نظام التصميم العام). يُستخدم في البطاقات والجداول والأزرار
/// لإعطاء القسم مظهراً «بارزاً» متناسقاً.

/// لون الحدّ الأبرز (أغمق قليلاً من SdColors.outline = C9D4E8).
const Color kInvFrameEdge = Color(0xFFB4C2DC);
const double kInvFrameWidth = 1.5;

/// مُزخرِف موحّد لإطار المخزون البارز (جداول/حاويات/أزرار مخصّصة).
BoxDecoration invFrameDeco({
  Color? fill,
  double? radius,
  Color? borderColor,
  bool shadow = true,
}) {
  return BoxDecoration(
    color: fill ?? SdColors.surface,
    borderRadius: BorderRadius.circular(radius ?? SdRadius.lg),
    border: Border.all(
      color: borderColor ?? kInvFrameEdge,
      width: kInvFrameWidth,
    ),
    boxShadow: shadow
        ? SdDepth.raised(depth: SdDepth.hero, edge: SdColors.cardEdge)
        : null,
  );
}

/// بطاقة المخزون — واجهة مطابقة لـ[SdCard] تماماً مع إطار أبرز.
/// بديل مباشر: استبدل `SdCard(` بـ `InvCard(` دون تغيير الوسائط.
class InvCard extends StatelessWidget {
  const InvCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.tone,
    this.trailing,
    this.padding,
  });
  final Widget child;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final SdTone? tone;
  final Widget? trailing;

  /// null = حشو تلقائي (14 على الهاتف، 16 غير ذلك).
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? SdGroup.admin.tone;
    final padding =
        this.padding ?? EdgeInsets.all(context.sd.isPhone ? 14 : SdSpace.md);
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        border: Border.all(color: kInvFrameEdge, width: kInvFrameWidth),
        boxShadow: SdDepth.raised(depth: SdDepth.hero, edge: SdColors.cardEdge),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: t.tint,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: [
                        BoxShadow(color: t.tintEdge, offset: const Offset(0, 3))
                      ],
                    ),
                    child: Icon(icon, color: t.base, size: 19),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title!, style: SdText.titleSm),
                      if (subtitle != null)
                        Text(subtitle!, style: SdText.caption),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: SdSpace.sm),
          ],
          child,
        ],
      ),
    );
  }
}
