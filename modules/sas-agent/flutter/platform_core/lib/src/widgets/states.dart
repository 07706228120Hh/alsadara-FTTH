import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// هيكل تحميل نابض (بلا مكتبات) — يُستخدم بدل الدائرة في القوائم واللوحات.
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 6});

  /// سطر نص.
  const Skeleton.line({super.key, this.width, this.height = 14}) : radius = 6;

  /// دائرة/مربّع أيقونة.
  const Skeleton.box({super.key, double size = 40, this.radius = 12})
      : width = size,
        height = size;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.pal.outline;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(widget.radius)),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.45 + 0.4 * _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// هيكل بطاقة KPI (يطابق StatTile).
class SkeletonStatTile extends StatelessWidget {
  const SkeletonStatTile({super.key});
  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Skeleton.box(size: 34, radius: 10),
            SizedBox(height: 14),
            Skeleton.line(width: 72, height: 22),
            SizedBox(height: 8),
            Skeleton.line(width: 110, height: 12),
          ]),
        ),
      );
}

/// شبكة هياكل KPI (عمودان على الموبايل، 3–4 على العريض) — تطابق StatGrid.
class SkeletonStatGrid extends StatelessWidget {
  final int count;
  const SkeletonStatGrid({super.key, this.count = 4});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 1100 ? 4 : (c.maxWidth > 700 ? 3 : 2);
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cols == 2 ? 1.35 : 1.7,
          children: List.generate(count, (_) => const SkeletonStatTile()),
        );
      });
}

/// هيكل قائمة (صفوف ببطاقة لكل صف).
class SkeletonList extends StatelessWidget {
  final int rows;
  final bool withAvatar;
  const SkeletonList({super.key, this.rows = 6, this.withAvatar = true});
  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              if (withAvatar) ...[const Skeleton.box(size: 40), const SizedBox(width: 12)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Skeleton.line(width: 140 + (i % 3) * 30.0),
                  const SizedBox(height: 8),
                  const Skeleton.line(width: 220, height: 11),
                ]),
              ),
              const SizedBox(width: 12),
              const Skeleton.line(width: 56, height: 22),
            ]),
          ),
        ),
      );
}

/// هيكل لوحة كاملة: بطاقة رأس + شبكة KPI + قائمة قصيرة.
class SkeletonDashboard extends StatelessWidget {
  const SkeletonDashboard({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(14), children: const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(children: [
              Skeleton.box(size: 52, radius: 26),
              SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Skeleton.line(width: 160, height: 16),
                  SizedBox(height: 8),
                  Skeleton.line(width: 240, height: 11),
                ]),
              ),
            ]),
          ),
        ),
        SizedBox(height: 16),
        Skeleton.line(width: 120, height: 16),
        SizedBox(height: 10),
        SkeletonStatGrid(),
        SizedBox(height: 16),
        Skeleton.line(width: 120, height: 16),
        SizedBox(height: 10),
        SkeletonStatGrid(count: 2),
      ]);
}
