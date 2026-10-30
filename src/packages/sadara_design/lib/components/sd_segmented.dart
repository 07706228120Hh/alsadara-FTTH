/// مفتاح مقسّم (Segmented control) بنمط البروز ثلاثي الأبعاد.
///
/// خانتان أو أكثر داخل خلفية غائرة؛ الخانة المحدّدة بيضاء بارزة بنص نيلي،
/// وغير المحدّدة شفّافة بنص رمادي. يُستخدم مثلاً لاختيار «موظف شركة | مدير النظام».
library;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_typography.dart';

/// خانة في [SdSegmented].
class SdSegment {
  const SdSegment(this.label, {this.icon});
  final String label;
  final IconData? icon;
}

class SdSegmented extends StatelessWidget {
  const SdSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.height = 46,
    this.glass = false,
  });

  /// نسخة زجاجية داكنة (فوق الخلفيات الداكنة/الشفافة).
  final bool glass;

  final List<SdSegment> segments;
  final int selected;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: glass ? const Color(0x1AFFFFFF) : const Color(0xFFEEF0F7),
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: glass ? Border.all(color: const Color(0x33FFFFFF)) : SdOutline.all,
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F1660),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(child: _buildSegment(i)),
          ],
        ],
      ),
    );
  }

  Widget _buildSegment(int i) {
    final on = i == selected;
    final seg = segments[i];
    final fg = on ? SdColors.primary : (glass ? const Color(0xCCFFFFFF) : SdColors.muted);
    return Semantics(
      button: true,
      selected: on,
      label: seg.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: on ? null : () => onChanged(i),
        child: AnimatedContainer(
          duration: SdMotion.fast,
          curve: Curves.easeOut,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? SdColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(SdRadius.sm),
            border: on ? SdOutline.all : null,
            boxShadow: on
                ? const [
                    BoxShadow(color: SdColors.cardEdge, offset: Offset(0, 3)),
                    BoxShadow(
                      color: Color(0x381A237E),
                      offset: Offset(0, 8),
                      blurRadius: 14,
                      spreadRadius: -8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (seg.icon != null) ...[
                Icon(seg.icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  seg.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
