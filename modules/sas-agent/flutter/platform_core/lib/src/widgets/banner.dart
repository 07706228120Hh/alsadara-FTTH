import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/tokens.dart';

enum BannerKind { info, success, warning, error }

/// بانر رسائل موحّد (بدل النصوص الحمراء المتفرّقة).
class PBanner extends StatelessWidget {
  final BannerKind kind;
  final String text;
  final String? title;
  final Widget? action;
  final VoidCallback? onClose;
  final bool dense;

  const PBanner({
    super.key,
    required this.kind,
    required this.text,
    this.title,
    this.action,
    this.onClose,
    this.dense = false,
  });

  const PBanner.error(this.text, {super.key, this.title, this.action, this.onClose, this.dense = false})
      : kind = BannerKind.error;
  const PBanner.info(this.text, {super.key, this.title, this.action, this.onClose, this.dense = false})
      : kind = BannerKind.info;
  const PBanner.success(this.text, {super.key, this.title, this.action, this.onClose, this.dense = false})
      : kind = BannerKind.success;
  const PBanner.warning(this.text, {super.key, this.title, this.action, this.onClose, this.dense = false})
      : kind = BannerKind.warning;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final (color, icon) = switch (kind) {
      BannerKind.info => (pal.info, PhosphorIconsFill.info),
      BannerKind.success => (pal.success, PhosphorIconsFill.checkCircle),
      BannerKind.warning => (pal.warning, PhosphorIconsFill.warning),
      BannerKind.error => (pal.danger, PhosphorIconsFill.xCircle),
    };
    final t = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 8 : 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: context.isDark ? 0.16 : 0.09),
        borderRadius: Radii.rMd,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, color: color, size: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (title != null)
              Text(title!, style: t.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
            Text(text, style: t.bodyMedium?.copyWith(color: pal.text, height: 1.45)),
            if (action != null) Padding(padding: const EdgeInsets.only(top: 6), child: action),
          ]),
        ),
        if (onClose != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(PhosphorIconsBold.x, size: 16),
            onPressed: onClose,
            tooltip: 'إغلاق',
          ),
      ]),
    );
  }
}

/// تنبيه سفلي بلون موحّد.
void toast(BuildContext context, String msg, {BannerKind kind = BannerKind.info}) {
  final pal = context.pal;
  final color = switch (kind) {
    BannerKind.info => pal.info,
    BannerKind.success => pal.success,
    BannerKind.warning => pal.warning,
    BannerKind.error => pal.danger,
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Container(width: 4, height: 22, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(child: Text(msg)),
      ]),
    ));
}
