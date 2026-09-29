import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'common.dart';

/// عمود في [PTable].
class PColumn<T> {
  final String label;
  /// نص الخلية (يُستخدم للبطاقات على الموبايل والفرز الافتراضي).
  final String Function(T row) value;
  /// ودجت مخصّص للخلية (اختياري) — إن غاب يُعرض [value] نصاً.
  final Widget Function(BuildContext context, T row)? cell;
  /// أرقام؟ → خط أحادي المسافة ومحاذاة يسار (LTR).
  final bool numeric;
  /// يُخفى على الموبايل (يبقى في الجدول العريض فقط).
  final bool secondary;
  /// مفتاح فرز اختياري (num/String/DateTime) — إن غاب يُفرز بـ [value].
  final Comparable Function(T row)? sortKey;
  final double? width;

  const PColumn({
    required this.label,
    required this.value,
    this.cell,
    this.numeric = false,
    this.secondary = false,
    this.sortKey,
    this.width,
  });
}

/// جدول متجاوب موحّد: DataTable قابل للفرز على الشاشات العريضة (≥ 840)،
/// وبطاقات «مفتاح: قيمة» على الموبايل. يحمل حالة الفراغ ونقرة الصف.
class PTable<T> extends StatefulWidget {
  final List<PColumn<T>> columns;
  final List<T> rows;
  final void Function(T row)? onTap;
  /// عنوان البطاقة على الموبايل (افتراضي: أول عمود).
  final String Function(T row)? cardTitle;
  /// شارة/ودجت يمين عنوان البطاقة (حالة مثلاً).
  final Widget Function(BuildContext context, T row)? cardTrailing;
  final String emptyTitle;
  final String? emptySubtitle;
  final int? initialSortColumn;
  final bool initialAscending;
  final double minTableWidth;

  const PTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onTap,
    this.cardTitle,
    this.cardTrailing,
    this.emptyTitle = 'لا نتائج',
    this.emptySubtitle,
    this.initialSortColumn,
    this.initialAscending = true,
    this.minTableWidth = 720,
  });

  @override
  State<PTable<T>> createState() => _PTableState<T>();
}

class _PTableState<T> extends State<PTable<T>> {
  int? _sortCol;
  bool _asc = true;

  @override
  void initState() {
    super.initState();
    _sortCol = widget.initialSortColumn;
    _asc = widget.initialAscending;
  }

  List<T> get _sorted {
    final rows = List<T>.of(widget.rows);
    final c = _sortCol;
    if (c == null || c >= widget.columns.length) return rows;
    final col = widget.columns[c];
    rows.sort((a, b) {
      final ka = col.sortKey?.call(a) ?? col.value(a);
      final kb = col.sortKey?.call(b) ?? col.value(b);
      final r = Comparable.compare(ka, kb);
      return _asc ? r : -r;
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return EmptyView(icon: PhosphorIconsDuotone.tray, title: widget.emptyTitle, subtitle: widget.emptySubtitle);
    }
    return LayoutBuilder(builder: (context, c) {
      return c.maxWidth >= Bp.tablet ? _table(context, c.maxWidth) : _cards(context);
    });
  }

  Widget _table(BuildContext context, double maxWidth) {
    final pal = context.pal;
    final rows = _sorted;
    final table = DataTable(
      sortColumnIndex: _sortCol,
      sortAscending: _asc,
      showCheckboxColumn: false,
      columns: [
        for (var i = 0; i < widget.columns.length; i++)
          DataColumn(
            label: Text(widget.columns[i].label),
            numeric: widget.columns[i].numeric,
            onSort: (idx, asc) => setState(() {
              _sortCol = idx;
              _asc = asc;
            }),
          ),
      ],
      rows: [
        for (final r in rows)
          DataRow(
            onSelectChanged: widget.onTap == null ? null : (_) => widget.onTap!(r),
            cells: [
              for (final col in widget.columns)
                DataCell(
                  col.cell?.call(context, r) ??
                      (col.numeric
                          ? Text(col.value(r), textDirection: TextDirection.ltr, style: PlatformType.num(color: pal.text))
                          : Text(col.value(r), maxLines: 2, overflow: TextOverflow.ellipsis)),
                ),
            ],
          ),
      ],
    );
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: maxWidth < widget.minTableWidth ? widget.minTableWidth : maxWidth),
          child: Card(child: table),
        ),
      ),
    );
  }

  Widget _cards(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    final rows = _sorted;
    final titleOf = widget.cardTitle ?? widget.columns.first.value;
    final detailCols = widget.columns.where((c) => !c.secondary).skip(widget.cardTitle == null ? 1 : 0).toList();
    return ListView.separated(
      padding: const EdgeInsets.all(Space.md),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: Space.sm),
      itemBuilder: (context, i) {
        final r = rows[i];
        return Card(
          child: InkWell(
            borderRadius: Radii.rLg,
            onTap: widget.onTap == null ? null : () => widget.onTap!(r),
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(titleOf(r), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                  if (widget.cardTrailing != null) widget.cardTrailing!(context, r),
                  if (widget.onTap != null) ...[
                    const SizedBox(width: 6),
                    Icon(PhosphorIconsBold.caretLeft, size: 14, color: pal.textMuted),
                  ],
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: Space.lg, runSpacing: 4, children: [
                  for (final col in detailCols)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('${col.label}: ', style: t.bodySmall?.copyWith(color: pal.textMuted)),
                      col.cell?.call(context, r) ??
                          Text(col.value(r),
                              textDirection: col.numeric ? TextDirection.ltr : null,
                              style: col.numeric ? PlatformType.num(size: 12.5, color: pal.text) : t.bodySmall?.copyWith(color: pal.text)),
                    ]),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// شريط انتهاء الاشتراك: أخضر > 7 أيام، كهرماني ≤ 7، أحمر منتهٍ.
class ExpiryBar extends StatelessWidget {
  /// الأيام المتبقية (سالبة = منتهٍ)، null = غير معروف.
  final int? daysLeft;
  /// طول الدورة بالأيام (لحساب النسبة) — افتراضي 30.
  final int cycleDays;
  const ExpiryBar({super.key, required this.daysLeft, this.cycleDays = 30});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    final d = daysLeft;
    final Color color;
    final String label;
    final double frac;
    if (d == null) {
      color = pal.textMuted;
      label = 'تاريخ الانتهاء غير معروف';
      frac = 0;
    } else if (d < 0) {
      color = pal.danger;
      label = 'انتهى قبل ${-d} يوم';
      frac = 0;
    } else if (d == 0) {
      color = pal.danger;
      label = 'ينتهي اليوم';
      frac = 0.04;
    } else if (d <= 7) {
      color = pal.warning;
      label = 'متبقٍّ $d ${d == 1 ? 'يوم' : (d == 2 ? 'يومان' : 'أيام')}';
      frac = (d / cycleDays).clamp(0.04, 1.0);
    } else {
      color = pal.success;
      label = 'متبقٍّ $d يوماً';
      frac = (d / cycleDays).clamp(0.0, 1.0);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(PhosphorIconsBold.clockCountdown, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label, style: t.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: frac, minHeight: 6, color: color, backgroundColor: pal.surfaceVariant),
      ),
    ]);
  }
}
