/// بلاطة قسم في الواجهات الرئيسية/المراكز: مكعّب أيقونة مجسّم + عنوان + وصف
/// + شارة. ترتفع وتميل ويدور المكعّب عند المرور، وتغوص عند الضغط.
///
/// متجاوبة: أفقية (مكعّب بجانب النص) على الآيباد وسطح المكتب، وعمودية مدمجة
/// (مكعّب فوق العنوان، عمودان في الصف) على الهاتف.
library;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_responsive.dart';
import '../tokens/sd_typography.dart';
import 'sd_cube.dart';

enum SdTileLayout {
  /// يختار تلقائياً: عمودي على الهاتف، أفقي غير ذلك.
  auto,
  horizontal,
  vertical,
}

class SdMenuTile extends StatefulWidget {
  const SdMenuTile({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.group = SdGroup.admin,
    this.badge,
    this.enabled = true,
    this.layout = SdTileLayout.auto,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final SdGroup group;
  final int? badge;
  final VoidCallback? onTap;

  /// false = بلا صلاحية: تظهر باهتة مع قفل.
  final bool enabled;
  final SdTileLayout layout;

  @override
  State<SdMenuTile> createState() => _SdMenuTileState();
}

class _SdMenuTileState extends State<SdMenuTile> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final l = context.sd;
    final vertical = widget.layout == SdTileLayout.vertical ||
        (widget.layout == SdTileLayout.auto && l.isPhone);
    final active = widget.enabled && widget.onTap != null;
    final hover = _hover && active && !l.touch;
    final depth = _down ? 1.0 : SdDepth.card;
    final dy = _down ? SdDepth.card - 1 : (hover ? -4.0 : 0.0);
    final m = Matrix4.translationValues(0, dy, 0);
    if (hover && !_down) {
      m.multiply(Matrix4.identity()
        ..setEntry(3, 2, 0.0011)
        ..rotateX(0.09));
    }
    final r = BorderRadius.circular(SdRadius.md + 2);

    final cube = TweenAnimationBuilder<double>(
      tween: Tween(end: hover ? 1.0 : 0.0),
      duration: SdMotion.slow,
      curve: SdMotion.standard,
      builder: (_, lift, __) => SdIconCube(
        icon: widget.enabled ? widget.icon : Icons.lock_rounded,
        group: widget.group,
        size: l.cubeSize,
        lift: lift,
        badge: widget.badge,
      ),
    );

    final showSubtitle = widget.subtitle != null && !(vertical && l.isCompactPhone);
    final Widget content = vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              cube,
              const SizedBox(height: 6),
              Text(widget.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: SdText.label.copyWith(fontWeight: FontWeight.w900, fontSize: 12.5)),
              if (showSubtitle)
                Text(widget.subtitle!,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: SdText.caption),
            ],
          )
        : Row(
            children: [
              cube,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SdText.titleSm.copyWith(fontSize: 14.5)),
                    if (showSubtitle)
                      Text(widget.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SdText.bodySm),
                  ],
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: active,
      label: widget.subtitle == null ? widget.title : '${widget.title}، ${widget.subtitle}',
      child: Opacity(
        opacity: widget.enabled ? 1 : .55,
        child: AnimatedContainer(
          duration: SdMotion.normal,
          curve: SdMotion.standard,
          transform: m,
          transformAlignment: Alignment.center,
          constraints: BoxConstraints(minHeight: vertical ? 96 : (l.isPhone ? 58 : 62)),
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: r,
            border: _focus
                ? Border.all(color: SdColors.accentGlow, width: SdOutline.focusWidth)
                : SdOutline.all,
            boxShadow: [
              BoxShadow(color: SdColors.cardEdge, offset: Offset(0, depth)),
              BoxShadow(
                color: const Color(0x731A237E),
                offset: Offset(0, depth + 12),
                blurRadius: _down ? 10 : 26,
                spreadRadius: -18,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: r,
              onTap: active ? widget.onTap : null,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              onHighlightChanged: (v) => setState(() => _down = v),
              onHover: (v) => setState(() => _hover = v),
              onFocusChange: (v) => setState(() => _focus = v),
              child: Padding(
                padding: vertical
                    ? const EdgeInsets.fromLTRB(8, 12, 8, 10)
                    : EdgeInsets.symmetric(horizontal: l.isPhone ? 12 : 14, vertical: l.isPhone ? 9 : 10),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// شبكة بلاطات متجاوبة:
/// - الهاتف: عمودان (بلاطات عمودية مدمجة)، وعمود واحد إن طُلب [phoneColumns]: 1.
/// - الآيباد: 2–3 أعمدة حسب العرض.
/// - سطح المكتب: حتى [maxColumns] أعمدة.
class SdTileGrid extends StatelessWidget {
  const SdTileGrid({
    super.key,
    required this.children,
    this.minTileWidth = 210,
    this.maxColumns = 4,
    this.phoneColumns = 2,
    this.spacing,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final int phoneColumns;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final l = ctx.sd.forWidth(c.maxWidth);
      final gap = spacing ?? l.gridGap;
      final w = c.maxWidth;
      final cols = l.isPhone && MediaQuery.sizeOf(ctx).width < SdBreakpoints.phoneMax
          ? phoneColumns
          : l.columnsFor(w, minTile: minTileWidth, max: maxColumns, gap: gap);
      final tileW = (w - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in children) SizedBox(width: tileW, child: t)],
      );
    });
  }
}
