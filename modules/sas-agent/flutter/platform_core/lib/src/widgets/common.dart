import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../utils/format.dart';

/// بطاقة رقم (KPI) — تُستخدم في لوحات التطبيقات الثلاثة.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? sub;
  final VoidCallback? onTap;
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.sub,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pal = context.pal;
    return Card(
      child: InkWell(
        borderRadius: Radii.rLg,
        onTap: onTap,
        child: Stack(children: [
          // شريط لوني جانبي (بداية السطر في RTL)
          PositionedDirectional(
            start: 0, top: 14, bottom: 14,
            child: Container(width: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: pal.textMuted, fontSize: 12.5)),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                  child: Icon(icon, color: color, size: 18),
                ),
              ]),
              const SizedBox(height: 14),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: PlatformType.display(size: 30, color: pal.text)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Text(sub ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: sub == null ? pal.textMuted : color, fontWeight: FontWeight.w600, fontSize: 11.5)),
                ),
                if (onTap != null) Icon(PhosphorIconsBold.caretLeft, size: 13, color: pal.textMuted),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// شبكة KPI متجاوبة: عمودان على الموبايل، 3-4 على الشاشات العريضة.
class StatGrid extends StatelessWidget {
  final List<Widget> tiles;
  const StatGrid(this.tiles, {super.key});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 1100 ? 4 : (c.maxWidth > 700 ? 3 : 2);
      return GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: cols == 2 ? 1.25 : 1.6,
        children: tiles,
      );
    });
  }
}

/// شارة حالة صغيرة.
class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const StatusChip(this.label, {super.key, required this.color, this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: Radii.rPill,
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
        Text(label,
            maxLines: 1,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11.5, height: 1.2)),
      ]),
    );
  }
}

/// ألوان الحالات الموحّدة (تذاكر/اشتراكات) — تقرأ من اللوحة الموحّدة عند توفّر السياق.
Color statusColor(String status, [BuildContext? context]) {
  if (context != null) return context.pal.status(status);
  const pal = PlatformPalette.light;
  return pal.status(status);
}

/// عنوان قسم.
class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const SectionTitle(this.title, {super.key, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitle != null)
              Text(subtitle!, style: t.bodySmall?.copyWith(color: t.bodySmall?.color)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// حالة فارغة.
class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyView({super.key, required this.icon, required this.title, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: t.bodySmall?.color?.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(title, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: t.bodyMedium?.copyWith(color: t.bodySmall?.color), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// خطأ مع إعادة محاولة.
class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView(this.message, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyView(
        icon: PhosphorIconsDuotone.warningCircle,
        title: 'تعذّر التحميل',
        subtitle: message,
        action: onRetry == null
            ? null
            : OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16),
                label: const Text('إعادة المحاولة')),
      );
}

/// تحميل موحّد.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// صف بيانات «مفتاح: قيمة» داخل بطاقة.
class KVRow extends StatelessWidget {
  final String k;
  final String v;
  final Color? color;
  const KVRow(this.k, this.v, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: context.pal.outline.withValues(alpha: 0.7)))),
      child: Row(children: [
        Text(k, style: t.bodyMedium?.copyWith(color: context.pal.textMuted, fontSize: 13)),
        const Spacer(),
        Flexible(
          child: Text(v,
              textAlign: TextAlign.left,
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: color),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// شريط بحث بسيط يُرسل عند الإدخال.
class SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onSubmitted;
  const SearchField({super.key, required this.hint, required this.onSubmitted});
  @override
  Widget build(BuildContext context) => TextField(
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(PhosphorIconsBold.magnifyingGlass, size: 18),
          isDense: true,
        ),
      );
}

/// صفّ رقائق تصفية أحادية الاختيار.
class FilterChips<T> extends StatelessWidget {
  final Map<T?, String> options;
  final T? value;
  final ValueChanged<T?> onChanged;
  const FilterChips({super.key, required this.options, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.entries
              .map((e) => Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: value == e.key,
                      onSelected: (_) => onChanged(e.key),
                    ),
                  ))
              .toList(),
        ),
      );
}

/// تنبيه SnackBar بلون.
void showMsg(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? context.pal.danger : null,
  ));
}

/// نسبة ملوّنة صغيرة (نشط/إجمالي).
class RatioBar extends StatelessWidget {
  final int part;
  final int whole;
  final Color color;
  final String label;
  const RatioBar({super.key, required this.part, required this.whole, required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = whole == 0 ? 0.0 : (part / whole).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: t.bodySmall),
        const Spacer(),
        Text('${Fmt.n(part)} / ${Fmt.n(whole)}  ·  ${Fmt.pct(part, whole)}',
            style: t.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(value: f, minHeight: 7, color: color,
            backgroundColor: color.withValues(alpha: 0.12)),
      ),
    ]);
  }
}


/// بطاقة بارزة بتوهّج اللكنة (بطاقة الوكيل/نتيجة المطابقة).
class GlowCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  const GlowCard({super.key, required this.child, this.color, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final c = color ?? pal.accent;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: context.isDark ? 0.28 : 0.32)),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.withValues(alpha: context.isDark ? 0.14 : 0.10), pal.surfaceCard],
          stops: const [0, 0.6],
        ),
      ),
      child: Stack(children: [
        PositionedDirectional(
          end: -60, top: -60,
          child: IgnorePointer(
            child: Container(
              width: 190, height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [c.withValues(alpha: 0.22), c.withValues(alpha: 0)]),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// حلقة نسبة (مخطط دائري) — نشط/منتهٍ.
class DonutRing extends StatelessWidget {
  final double fraction;
  final Color color;
  final Color rest;
  final double size;
  final String centerValue;
  final String centerLabel;
  const DonutRing({
    super.key,
    required this.fraction,
    required this.color,
    required this.rest,
    required this.centerValue,
    required this.centerLabel,
    this.size = 128,
  });
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SizedBox(
      width: size, height: size,
      child: CustomPaint(
        painter: _DonutPainter(fraction.clamp(0.0, 1.0), color, rest),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(centerValue, style: PlatformType.display(size: size * 0.18, color: pal.text)),
            const SizedBox(height: 4),
            Text(centerLabel, style: TextStyle(fontSize: 10.5, color: pal.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double f;
  final Color a;
  final Color b;
  _DonutPainter(this.f, this.a, this.b);
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * 0.12;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, p..color = b);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * f, false, p..color = a);
  }
  @override
  bool shouldRepaint(covariant _DonutPainter o) => o.f != f || o.a != a || o.b != b;
}

/// صف مفتاح ملوّن لمخطط (نقطة + اسم + قيمة).
class LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const LegendRow({super.key, required this.color, required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: pal.textMuted))),
        Text(value, style: PlatformType.num(size: 13, color: pal.text)),
      ]),
    );
  }
}
