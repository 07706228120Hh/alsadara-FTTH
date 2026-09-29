import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/ticket.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/ticket_widgets.dart';

/// تفاصيل تذكرة — تعمل للمشترك (بلا إجراءات) وللموظّف (تغيير الحالة/الأولوية/التصعيد).
class TicketDetailScreen extends StatefulWidget {
  final int ticketId;
  final Future<Ticket> Function(int id) load;
  final Future<void> Function(int id, String body, bool internal) onReply;
  /// إن كانت null → لا إجراءات (مشترك أو viewer).
  final Future<Ticket> Function(int id, {String? status, String? priority, bool? escalated})? onPatch;
  final bool canEscalate;
  final bool staff;
  const TicketDetailScreen({
    super.key,
    required this.ticketId,
    required this.load,
    required this.onReply,
    this.onPatch,
    this.canEscalate = false,
    this.staff = false,
  });

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  Ticket? _t;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.load(widget.ticketId);
      if (mounted) setState(() { _t = t; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _patch({String? status, String? priority, bool? escalated}) async {
    try {
      final t = await widget.onPatch!(widget.ticketId, status: status, priority: priority, escalated: escalated);
      _changed = true;
      if (mounted) setState(() => _t = t);
      await _load();
    } catch (e) {
      if (mounted) showMsg(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
          appBar: AppBar(
            title: Text(t == null ? 'تذكرة #${widget.ticketId}' : '#${t.id} · ${t.subject}'),
            leading: BackButton(onPressed: () => Navigator.of(context).pop(_changed)),
            actions: [
              if (t != null && widget.onPatch != null)
                PopupMenuButton<String>(
                  icon: const Icon(PhosphorIconsBold.dotsThreeVertical),
                  onSelected: (v) {
                    if (v.startsWith('s:')) _patch(status: v.substring(2));
                    if (v.startsWith('p:')) _patch(priority: v.substring(2));
                    if (v == 'esc') _patch(escalated: !t.escalated);
                  },
                  itemBuilder: (_) => [
                    for (final e in ticketStatuses.entries)
                      if (e.key != t.status)
                        PopupMenuItem(value: 's:${e.key}', child: Text('الحالة: ${e.value}')),
                    const PopupMenuDivider(),
                    for (final e in ticketPriorities.entries)
                      if (e.key != t.priority)
                        PopupMenuItem(value: 'p:${e.key}', child: Text('الأولوية: ${e.value}')),
                    if (widget.canEscalate) ...[
                      const PopupMenuDivider(),
                      PopupMenuItem(value: 'esc', child: Text(t.escalated ? 'إلغاء التصعيد' : 'تصعيد للوزارة')),
                    ],
                  ],
                ),
            ],
          ),
          body: t == null
              ? (_error != null ? ErrorView(_error!, onRetry: _load) : const LoadingView())
              : Column(children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Wrap(spacing: 6, runSpacing: 6, children: [
                                  StatusChip(ticketStatuses[t.status] ?? t.status, color: statusColor(t.status)),
                                  StatusChip(ticketCategories[t.category] ?? t.category, color: BrandColors.slate),
                                  StatusChip('أولوية: ${ticketPriorities[t.priority] ?? t.priority}',
                                      color: t.priority == 'urgent' || t.priority == 'high' ? BrandColors.red : BrandColors.slate),
                                  if (t.escalated)
                                    const StatusChip('مُصعَّدة للوزارة', color: BrandColors.violet, icon: PhosphorIconsBold.flag),
                                ]),
                                const Divider(height: 22),
                                KVRow('الشركة', t.company),
                                if (t.agent.isNotEmpty) KVRow('الوكيل', t.agent),
                                if (widget.staff) ...[
                                  KVRow('المشترك', t.subscriberName.isNotEmpty ? '${t.subscriberName} (${t.subscriber})' : t.subscriber),
                                  KVRow('الهاتف', t.subscriberPhone.isNotEmpty ? '0${t.subscriberPhone.replaceFirst('964', '')}' : '—'),
                                ] else
                                  KVRow('الحساب', t.subscriber),
                                KVRow('فُتحت', Fmt.dateTime(t.createdAt)),
                                KVRow('آخر تحديث', Fmt.ago(t.updatedAt)),
                                if (t.resolvedAt != null) KVRow('حُلّت', Fmt.dateTime(t.resolvedAt), color: BrandColors.green),
                                KVRow('فتحها', authorKindAr[t.createdByKind] ?? t.createdByKind),
                              ]),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
                            child: Text('المحادثة', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          TicketThread(t: t),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ReplyComposer(
                    enabled: t.status != 'closed',
                    allowInternal: widget.staff,
                    onSend: (body, internal) async {
                      await widget.onReply(widget.ticketId, body, internal);
                      _changed = true;
                      await _load();
                    },
                  ),
                ]),
      ),
    );
  }
}
