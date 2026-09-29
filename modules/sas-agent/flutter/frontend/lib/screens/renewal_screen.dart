import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:platform_core/platform_core.dart';

/// قائمة التجديد — مشتركو الوكيل الأقرب انتهاءً، مع تحديد متعدّد وعملية جماعية
/// (تمديد/تفعيل دفعةً واحدة). كل مشترك يحمل transaction_id فريد يمنع تكرار الخصم.
class RenewalScreen extends StatefulWidget {
  final StaffApi api;
  final String initialWindow;        // overdue|today|soon3|soon7
  const RenewalScreen({super.key, required this.api, this.initialWindow = 'soon7'});
  @override
  State<RenewalScreen> createState() => _RenewalScreenState();
}

class _RenewalScreenState extends State<RenewalScreen> {
  static const _windows = {
    'overdue': 'منتهٍ', 'today': 'ينتهي اليوم', 'soon3': 'خلال ٣ أيام', 'soon7': 'خلال أسبوع',
  };
  late String _win = widget.initialWindow;
  List<SubscriberRow> _rows = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _bulkBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await widget.api.subscribers(expiring: _win, count: 300);
      if (mounted) setState(() { _rows = r.rows; _selected.clear(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  void _toggle(int id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      });

  void _selectAll() => setState(() {
        if (_selected.length == _rows.length) {
          _selected.clear();
        } else {
          _selected
            ..clear()
            ..addAll(_rows.map((r) => r.id));
        }
      });

  Future<bool> _confirm(String action, int n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$action $n مشترك؟'),
        content: Text('سيُنفَّذ «$action» على $n مشترك عبر نظام SAS الآن. '
            'كل عملية تُخصم من رصيدك (إن لزم) ولا تُكرَّر. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _bulk(String sasAction, String label) async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    if (!await _confirm(label, ids.length)) return;
    setState(() => _bulkBusy = true);
    try {
      final res = await widget.api.sasBulkAction(
          Session.companyId!, sasAction, ids, payload: const {'method': 'credit'});
      final ok = (res['ok'] as num?)?.toInt() ?? 0;
      final failed = (res['failed'] as num?)?.toInt() ?? 0;
      if (mounted) {
        showMsg(context, failed == 0
            ? 'تمّ «$label» لـ $ok مشترك بنجاح'
            : 'نجح $ok · فشل $failed — راجع المشتركين المتبقّين', error: failed != 0);
      }
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final n = _selected.length;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قائمة التجديد'),
          actions: [
            IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _load,
                icon: const Icon(PhosphorIconsBold.arrowsClockwise)),
          ],
        ),
        body: Column(children: [
          // مرشّح النافذة
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(children: [
              for (final e in _windows.entries)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _win == e.key,
                    onSelected: (_) { setState(() => _win = e.key); _load(); },
                  ),
                ),
            ]),
          ),
          if (!_loading && _rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(children: [
                TextButton.icon(
                  onPressed: _selectAll,
                  icon: Icon(_selected.length == _rows.length
                      ? PhosphorIconsBold.checkSquare : PhosphorIconsBold.square, size: 18),
                  label: Text(_selected.length == _rows.length ? 'إلغاء التحديد' : 'تحديد الكل'),
                ),
                const Spacer(),
                Text('${Fmt.n(_rows.length)} مشترك', style: tt.bodySmall),
              ]),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorView(_error!, onRetry: _load)
                    : _rows.isEmpty
                        ? const EmptyView(
                            icon: PhosphorIconsDuotone.checkCircle,
                            title: 'لا مشتركين في هذه النافذة',
                            subtitle: 'جرّب نافذة أخرى (اليوم/خلال أسبوع)')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, i) => _RenewCard(
                              s: _rows[i],
                              selected: _selected.contains(_rows[i].id),
                              onToggle: () => _toggle(_rows[i].id),
                            ),
                          ),
          ),
        ]),
        bottomSheet: n == 0 ? null : _BulkBar(
          count: n,
          busy: _bulkBusy,
          onExtend: () => _bulk('extend', 'تمديد'),
          onActivate: () => _bulk('activate', 'تفعيل'),
        ),
      ),
    );
  }
}

class _RenewCard extends StatelessWidget {
  final SubscriberRow s;
  final bool selected;
  final VoidCallback onToggle;
  const _RenewCard({required this.s, required this.selected, required this.onToggle});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final d = s.daysLeft;
    final (String dLabel, Color dColor) = d == null
        ? ('—', BrandColors.slate)
        : d < 0
            ? ('انتهى منذ ${-d} يوم', BrandColors.red)
            : d == 0
                ? ('ينتهي اليوم', BrandColors.amber)
                : ('خلال $d يوم', d <= 3 ? BrandColors.amber : BrandColors.blue);
    return Card(
      color: selected ? BrandColors.blue.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
          child: Row(children: [
            Checkbox(value: selected, onChanged: (_) => onToggle()),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.username, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                if (s.name.isNotEmpty)
                  Text(s.name, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  StatusChip(dLabel, color: dColor, icon: PhosphorIconsBold.clock),
                  if (s.profile.isNotEmpty) StatusChip(s.profile, color: BrandColors.slate),
                  StatusChip(s.active ? 'نشط' : 'منتهٍ', color: statusColor(s.status)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _BulkBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onExtend, onActivate;
  const _BulkBar({required this.count, required this.busy, required this.onExtend, required this.onActivate});
  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Row(children: [
          Text('$count محدَّد', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (busy)
            const Padding(padding: EdgeInsets.all(8),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            OutlinedButton.icon(onPressed: onActivate,
                icon: const Icon(PhosphorIconsBold.power, size: 18), label: const Text('تفعيل')),
            const SizedBox(width: 8),
            FilledButton.icon(onPressed: onExtend,
                icon: const Icon(PhosphorIconsBold.calendarPlus, size: 18), label: const Text('تمديد')),
          ],
        ]),
      ),
    );
  }
}
