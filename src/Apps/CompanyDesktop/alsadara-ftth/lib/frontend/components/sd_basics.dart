/// مكوّنات أساسية: شارة عدد، شارة حالة، عنوان قسم، فلاتر، مفتاح، بطاقة،
/// صف معلومة، حالة فراغ — كلها بنمط البروز ثلاثي الأبعاد.
library;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_responsive.dart';
import '../tokens/sd_typography.dart';
import 'sd_raised.dart';

/// شارة عدد حمراء بارزة (طلبات/رسائل). تعرض «+99» فوق 99.
class SdBadge extends StatelessWidget {
  const SdBadge({super.key, required this.count, this.max = 99});
  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    final text = count > max ? '+$max' : '$count';
    return Semantics(
      label: '$count',
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: SdColors.danger,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [BoxShadow(color: SdColors.dangerEdge, offset: Offset(0, 2))],
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: SdText.family,
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// شارة حالة نصية (ممتاز/معلّق/مرفوض…) بخلفية فاتحة ونص داكن مقروء.
class SdStatusChip extends StatelessWidget {
  const SdStatusChip(this.label, {super.key, this.status = SdStatus.neutral, this.icon});
  final String label;
  final SdStatus status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = status.tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: t.tint,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        boxShadow: [BoxShadow(color: t.tintEdge, offset: const Offset(0, SdDepth.chip))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: t.text),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: t.text)),
        ],
      ),
    );
  }
}

/// عنوان قسم: مكعّب لون صغير + عنوان + عدد اختياري + عنصر جانبي.
class SdSectionHeader extends StatelessWidget {
  const SdSectionHeader({
    super.key,
    required this.title,
    this.tone,
    this.count,
    this.trailing,
  });
  final String title;
  final SdTone? tone;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = tone ?? SdGroup.admin.tone;
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.sm),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: t.base,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [BoxShadow(color: t.edge, offset: const Offset(0, 3))],
            ),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(title, style: SdText.titleSm)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: t.tint,
                borderRadius: BorderRadius.circular(SdRadius.pill),
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: t.text)),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// خيار في شريط الفلاتر.
class SdFilterOption<T> {
  const SdFilterOption(this.value, this.label);
  final T value;
  final String label;
}

/// شريط فلاتر بأقراص بارزة؛ المحدّد نيلي.
class SdFilterChips<T> extends StatelessWidget {
  const SdFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  final List<SdFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final chips = [
        for (final o in options)
          SdRaised(
            onTap: () => onSelected(o.value),
            toggled: o.value == selected,
            semanticLabel: o.label,
            radius: SdRadius.pill,
            depth: 4,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            color: o.value == selected ? SdColors.primary : SdColors.surface,
            edgeColor: o.value == selected ? SdColors.primaryEdge : SdColors.cardEdge,
            glowColor: const Color(0x261A237E),
            child: Text(
              o.label,
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: o.value == selected ? Colors.white : SdColors.ink,
              ),
            ),
          ),
    ];
    // الهاتف: صف واحد قابل للتمرير أفقياً بدل الالتفاف لعدة أسطر.
    if (context.sd.isPhone) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              chips[i],
            ],
          ],
        ),
      );
    }
    return Wrap(spacing: 10, runSpacing: 10, children: chips);
  }
}

/// مفتاح تشغيل مجسّم (يستقبل الضغط بنفسه).
class SdToggle extends StatelessWidget {
  const SdToggle({super.key, required this.value, required this.onChanged, this.label});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: SdMotion.normal,
          width: 50,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SdRadius.pill),
            border: SdOutline.all,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: value
                  ? const [Color(0xFF0B1150), SdColors.primary]
                  : const [Color(0xFFCDD2E4), Color(0xFFE3E6F0)],
            ),
          ),
          child: AnimatedAlign(
            duration: SdMotion.normal,
            curve: SdMotion.bounce,
            alignment: value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Colors.white : SdColors.faint,
                boxShadow: [
                  BoxShadow(
                      color: value ? SdColors.primaryTintEdge : SdColors.muted,
                      offset: const Offset(0, 3)),
                  const BoxShadow(color: Color(0x40000000), offset: Offset(0, 4), blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقة بيضاء بارزة مع رأس اختياري (أيقونة مكعّبة صغيرة + عنوان + جانبي).
class SdCard extends StatelessWidget {
  const SdCard({
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
    final padding = this.padding ?? EdgeInsets.all(context.sd.isPhone ? 14 : SdSpace.md);
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        border: SdOutline.all,
        boxShadow: SdDepth.raised(),
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
                      boxShadow: [BoxShadow(color: t.tintEdge, offset: const Offset(0, 3))],
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
                      if (subtitle != null) Text(subtitle!, style: SdText.caption),
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

/// صف معلومة (تسمية: قيمة) داخل بطاقة.
class SdInfoRow extends StatelessWidget {
  const SdInfoRow({super.key, required this.label, required this.value, this.icon, this.ltrValue = false});
  final String label;
  final String value;
  final IconData? icon;

  /// القيم التقنية (IP/هاتف) تُعرض LTR.
  final bool ltrValue;

  @override
  Widget build(BuildContext context) {
    // الشاشات الضيقة جداً: التسمية فوق القيمة بدل جنبها.
    if (context.sd.isCompactPhone) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: SdText.caption),
            Text(value,
                textDirection: ltrValue ? TextDirection.ltr : null,
                style: SdText.label),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: SdColors.faint),
            const SizedBox(width: 8),
          ],
          Text(label, style: SdText.bodySm),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: ltrValue ? TextDirection.ltr : null,
              style: SdText.label,
            ),
          ),
        ],
      ),
    );
  }
}

/// حالة فراغ/خطأ موحّدة.
class SdEmptyState extends StatelessWidget {
  const SdEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.status = SdStatus.neutral,
    this.action,
  });
  final String title;
  final String? message;
  final IconData icon;
  final SdStatus status;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = status.tone;
    return Padding(
      padding: const EdgeInsets.all(SdSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.tint,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [BoxShadow(color: t.tintEdge, offset: const Offset(0, 5))],
            ),
            child: Icon(icon, size: 32, color: t.base),
          ),
          const SizedBox(height: SdSpace.md),
          Text(title, style: SdText.titleSm, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, style: SdText.bodySm, textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: SdSpace.md),
            action!,
          ],
        ],
      ),
    );
  }
}
