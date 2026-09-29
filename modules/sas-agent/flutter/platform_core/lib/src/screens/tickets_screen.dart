import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../api/staff_api.dart';
import '../models/ticket.dart';
import '../session.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/ticket_widgets.dart';
import 'ticket_detail_screen.dart';

/// قائمة التذاكر للموظّفين (وكيل/شركة/وزارة) — النطاق يفرضه الباكند.
class TicketsScreen extends StatefulWidget {
  final StaffApi api;
  /// الشركة/الوزارة يمكنهما التصعيد؛ الوكيل لا.
  final bool canEscalate;
  /// تصفية ابتدائية (مثلاً المُصعَّدة فقط في الوزارة).
  final bool? initialEscalated;
  final String title;
  const TicketsScreen({
    super.key,
    required this.api,
    this.canEscalate = false,
    this.initialEscalated,
    this.title = 'التذاكر',
  });

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  List<Ticket> _rows = [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  String? _status = 'open';
  String? _category;
  String _search = '';
  bool? _escalated;

  @override
  void initState() {
    super.initState();
    _escalated = widget.initialEscalated;
    if (_escalated == true) _status = null;
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await widget.api.tickets(
        status: _status,
        category: _category,
        escalated: _escalated,
        search: _search.isEmpty ? null : _search,
        count: 200,
      );
      if (mounted) setState(() { _rows = r.rows; _total = r.total; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _open(Ticket t) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TicketDetailScreen(
        ticketId: t.id,
        staff: true,
        load: widget.api.ticket,
        onReply: (id, body, internal) => widget.api.reply(id, body, internal: internal),
        onPatch: Session.isOperator
            ? (id, {status, priority, escalated}) =>
                widget.api.patchTicket(id, status: status, priority: priority, escalated: escalated)
            : null,
        canEscalate: widget.canEscalate,
      ),
    ));
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return TabPage(
      title: widget.title,
      subtitle: 'الإجمالي: $_total',
      onRefresh: _load,
      child: Content(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: SearchField(hint: 'بحث بالموضوع أو المشترك أو الهاتف…', onSubmitted: (v) { _search = v; _load(); }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FilterChips<String>(
              options: const {null: 'الكل', 'open': 'مفتوحة', 'in_progress': 'قيد المعالجة', 'resolved': 'محلولة', 'closed': 'مغلقة'},
              value: _status,
              onChanged: (v) { _status = v; _load(); },
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: FilterChips<String>(
              options: const {null: 'كل التصنيفات', ...ticketCategories},
              value: _category,
              onChanged: (v) { _category = v; _load(); },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const LoadingView()
                : _error != null
                    ? ErrorView(_error!, onRetry: _load)
                    : _rows.isEmpty
                        ? const EmptyView(icon: PhosphorIconsDuotone.ticket, title: 'لا تذاكر', subtitle: 'لا تذاكر تطابق التصفية الحالية')
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 90),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => TicketCard(t: _rows[i], onTap: () => _open(_rows[i])),
                          ),
          ),
        ]),
      ),
    );
  }
}
