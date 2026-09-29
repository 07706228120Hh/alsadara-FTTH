import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:platform_core/platform_core.dart';

/// مشتركو الوكيل (النطاق يفرضه الباكند) مع بحث وتصفية وفتح تذكرة نيابةً عن المشترك.
class AgentSubscribersScreen extends StatefulWidget {
  final StaffApi api;
  const AgentSubscribersScreen({super.key, required this.api});
  @override
  State<AgentSubscribersScreen> createState() => _AgentSubscribersScreenState();
}

class _AgentSubscribersScreenState extends State<AgentSubscribersScreen> {
  List<SubscriberRow> _rows = [];
  int _total = 0;
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String? _status;
  String _search = '';
  int _page = 1;
  static const _count = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await widget.api.subscribers(status: _status, search: _search.isEmpty ? null : _search, page: _page, count: _count);
      if (mounted) setState(() { _rows = r.rows; _total = r.total; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  /// يسحب مشتركيه من خادم SAS ويحفظهم محلياً ثم يعيد التحميل من القاعدة.
  Future<void> _syncNow() async {
    setState(() { _syncing = true; });
    try {
      final res = await widget.api.syncAgentNow();
      final n = (res['count'] as num?)?.toInt() ?? 0;
      if (mounted) showMsg(context, 'تمت المزامنة — $n مشترك محفوظ محلياً');
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() { _syncing = false; });
      await _load();
    }
  }

  int get _pages => (_total / _count).ceil().clamp(1, 1 << 20);

  Future<void> _openTicketFor(SubscriberRow s) async {
    final res = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewTicketSheet(sub: s),
    );
    if (res == null) return;
    try {
      await widget.api.createTicket(
        subscriberId: s.id,
        subject: res['subject']!,
        category: res['category']!,
        body: res['body'] ?? '',
        priority: res['priority'] ?? 'normal',
      );
      if (mounted) showMsg(context, 'فُتحت التذكرة للمشترك ${s.username}');
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return TabPage(
      title: 'مشتركيّ',
      subtitle: 'الإجمالي: ${Fmt.n(_total)}',
      onRefresh: _load,
      actions: [
        _syncing
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : IconButton(
                tooltip: 'مزامنة من SAS الآن',
                icon: const Icon(PhosphorIconsBold.cloudArrowDown, size: 20),
                onPressed: _syncNow),
      ],
      child: Content(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: SearchField(hint: 'بحث باسم المستخدم أو الاسم أو الهاتف…', onSubmitted: (v) { _search = v; _page = 1; _load(); }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FilterChips<String>(
              options: const {null: 'الكل', 'active': 'نشط', 'expired': 'منتهٍ'},
              value: _status,
              onChanged: (v) { _status = v; _page = 1; _load(); },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const SkeletonList()
                : _error != null
                    ? ErrorView(_error!, onRetry: _load)
                    : _rows.isEmpty
                        ? EmptyView(
                            icon: PhosphorIconsDuotone.usersThree,
                            title: 'لا مشتركون بعد',
                            subtitle: 'اضغط «مزامنة من SAS الآن» لسحب مشتركيك من خادمك وحفظهم محلياً',
                            action: FilledButton.icon(
                              onPressed: _syncing ? null : _syncNow,
                              icon: const Icon(PhosphorIconsBold.cloudArrowDown, size: 18),
                              label: const Text('مزامنة من SAS الآن'),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _SubCard(s: _rows[i], onTicket: () => _openTicketFor(_rows[i])),
                          ),
          ),
          if (!_loading && _total > _count)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(onPressed: _page > 1 ? () { _page--; _load(); } : null, icon: const Icon(PhosphorIconsBold.caretRight)),
                Text('صفحة $_page من $_pages', style: tt.bodySmall),
                IconButton(onPressed: _page < _pages ? () { _page++; _load(); } : null, icon: const Icon(PhosphorIconsBold.caretLeft)),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _SubCard extends StatelessWidget {
  final SubscriberRow s;
  final VoidCallback onTicket;
  const _SubCard({required this.s, required this.onTicket});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final days = s.daysLeft;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(shape: BoxShape.circle, color: s.online ? BrandColors.green : BrandColors.slate.withValues(alpha: 0.4)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.username, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              if (s.name.isNotEmpty) Text(s.name, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusChip(s.active ? 'نشط' : 'منتهٍ', color: statusColor(s.status)),
                if (s.profile.isNotEmpty) StatusChip(s.profile, color: BrandColors.slate),
                if (days != null && s.active && days <= 5)
                  StatusChip(days <= 0 ? 'ينتهي اليوم' : 'ينتهي خلال $days يوم', color: BrandColors.amber, icon: PhosphorIconsBold.clock),
                if (s.governorate.isNotEmpty) StatusChip(s.governorate, color: BrandColors.blue),
              ]),
            ]),
          ),
          IconButton(tooltip: 'فتح تذكرة', onPressed: onTicket, icon: const Icon(PhosphorIconsDuotone.ticket)),
        ]),
      ),
    );
  }
}

class _NewTicketSheet extends StatefulWidget {
  final SubscriberRow sub;
  const _NewTicketSheet({required this.sub});
  @override
  State<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends State<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _cat = 'complaint';
  String _prio = 'normal';

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + pad),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('تذكرة جديدة — ${widget.sub.username}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _cat,
            decoration: const InputDecoration(labelText: 'التصنيف'),
            items: ticketCategories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _cat = v ?? 'complaint'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _prio,
            decoration: const InputDecoration(labelText: 'الأولوية'),
            items: ticketPriorities.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) => setState(() => _prio = v ?? 'normal'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _subject, decoration: const InputDecoration(labelText: 'الموضوع')),
          const SizedBox(height: 10),
          TextField(controller: _body, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'التفاصيل (اختياري)')),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              if (_subject.text.trim().length < 3) return;
              Navigator.pop(context, {'subject': _subject.text.trim(), 'category': _cat, 'body': _body.text.trim(), 'priority': _prio});
            },
            child: const Text('فتح التذكرة'),
          ),
        ]),
      ),
    );
  }
}
