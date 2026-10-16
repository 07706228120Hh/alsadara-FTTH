/// عناصر «مادّية» تفاعلية: سطح بارز يرتفع ويميل عند المرور ويغوص عند الضغط.
library;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';

/// سطح بارز قابل للضغط — الأساس لكل الأزرار والبطاقات التفاعلية.
///
/// يدعم: لوحة المفاتيح (حلقة تركيز)، القارئ الشاشي (button/toggled)،
/// المرور بالماوس (ارتفاع + ميل اختياري)، والضغط (غوص الحافّة).
class SdRaised extends StatefulWidget {
  const SdRaised({
    super.key,
    required this.child,
    this.onTap,
    this.color = SdColors.surface,
    this.gradient,
    this.edgeColor = SdColors.cardEdge,
    this.glowColor = const Color(0x591A237E),
    this.radius = SdRadius.lg,
    this.depth = SdDepth.card,
    this.padding = const EdgeInsets.all(SdSpace.md),
    this.tilt = false,
    this.semanticLabel,
    this.toggled,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Gradient? gradient;
  final Color edgeColor;
  final Color glowColor;
  final double radius;
  final double depth;
  final EdgeInsetsGeometry padding;

  /// ميل خفيف ثلاثي الأبعاد عند المرور (سطح المكتب).
  final bool tilt;
  final String? semanticLabel;

  /// لعناصر التبديل (مفتاح/فلتر): يعلن حالته للقارئ الشاشي.
  final bool? toggled;
  final String? tooltip;

  @override
  State<SdRaised> createState() => _SdRaisedState();
}

class _SdRaisedState extends State<SdRaised> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final d = _down ? 1.0 : widget.depth;
    final dy = _down ? widget.depth - 1 : (_hover && enabled ? -3.0 : 0.0);
    final m = Matrix4.translationValues(0, dy, 0);
    if (_hover && widget.tilt && !_down && enabled) {
      m.multiply(Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(0.10));
    }
    final r = BorderRadius.circular(widget.radius);

    Widget body = AnimatedContainer(
      duration: SdMotion.fast,
      curve: Curves.easeOut,
      transform: m,
      transformAlignment: Alignment.center,
      decoration: BoxDecoration(
        color: widget.gradient == null ? widget.color : null,
        gradient: widget.gradient,
        borderRadius: r,
        border: _focus
            ? Border.all(color: SdColors.accentGlow, width: 2)
            : null,
        boxShadow: [
          BoxShadow(color: widget.edgeColor, offset: Offset(0, d)),
          BoxShadow(
            color: widget.glowColor,
            offset: Offset(0, d + 12),
            blurRadius: _down ? 10 : 28,
            spreadRadius: -14,
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: widget.onTap,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          onHighlightChanged: (v) => setState(() => _down = v),
          onHover: (v) => setState(() => _hover = v),
          onFocusChange: (v) => setState(() => _focus = v),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );

    if (widget.tooltip != null) {
      body = Tooltip(message: widget.tooltip!, child: body);
    }

    return Semantics(
      button: widget.toggled == null && enabled,
      toggled: widget.toggled,
      enabled: enabled,
      label: widget.semanticLabel,
      child: body,
    );
  }
}

/// زر بارز بنص وأيقونة اختيارية.
enum SdButtonKind { primary, accent, secondary, danger }

class SdButton extends StatelessWidget {
  const SdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = SdButtonKind.primary,
    this.expand = false,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final SdButtonKind kind;
  final bool expand;
  final double height;

  @override
  Widget build(BuildContext context) {
    late final Color fg;
    late final Color edge;
    Gradient? gradient;
    Color color = SdColors.surface;
    switch (kind) {
      case SdButtonKind.primary:
        fg = Colors.white;
        edge = SdColors.primaryEdge;
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SdColors.primaryMid, SdColors.primary],
        );
        break;
      case SdButtonKind.accent:
        fg = Colors.white;
        edge = SdColors.accentEdge;
        gradient = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF00949F), SdColors.accent],
        );
        break;
      case SdButtonKind.secondary:
        fg = SdColors.primary;
        edge = SdColors.cardEdge;
        break;
      case SdButtonKind.danger:
        fg = const Color(0xFFB71C1C);
        edge = const Color(0xFFEF9A9A);
        color = SdColors.dangerTint;
        break;
    }
    final disabled = onPressed == null;
    final content = SizedBox(
      height: height,
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: fg, size: 20),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Cairo',
                color: fg,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    return Opacity(
      opacity: disabled ? .5 : 1,
      child: SdRaised(
        onTap: onPressed,
        radius: SdRadius.md,
        depth: kind == SdButtonKind.secondary || kind == SdButtonKind.danger
            ? SdDepth.card
            : SdDepth.button,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        gradient: gradient,
        color: color,
        edgeColor: edge,
        glowColor: kind == SdButtonKind.secondary
            ? const Color(0x331A237E)
            : edge.withValues(alpha: .55),
        semanticLabel: label,
        child: content,
      ),
    );
  }
}
