import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/ticket.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'common.dart';

IconData categoryIcon(String c) {
  switch (c) {
    case 'outage':
      return PhosphorIconsDuotone.plugs;
    case 'billing':
      return PhosphorIconsDuotone.receipt;
    case 'speed':
      return PhosphorIconsDuotone.gauge;
    case 'complaint':
      return PhosphorIconsDuotone.chatCenteredText;
    default:
      return PhosphorIconsDuotone.question;
  }
}

/// بطاقة تذكرة في القوائم — مشتركة بين المشترك والوكيل والشركة والوزارة.
class TicketCard extends StatelessWidget {
  final Ticket t;
  final VoidCallback onTap;
  /// إظهار اسم المشترك/الشركة (الموظّفون) أو إخفاؤه (المشترك يعرف نفسه).
  final bool showParty;
  const TicketCard({super.key, required this.t, required this.onTap, this.showParty = true});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = statusColor(t.status);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(categoryIcon(t.category), color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(t.subject,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('#${t.id}', style: tt.bodySmall),
                ]),
                const SizedBox(height: 3),
                Text(
                  showParty
                      ? '${t.subscriberName.isNotEmpty ? t.subscriberName : t.subscriber} · ${t.company}'
                          '${t.agent.isNotEmpty ? ' · وكيل: ${t.agent}' : ''}'
                      : '${t.company}${t.agent.isNotEmpty ? ' · وكيل: ${t.agent}' : ''}',
                  style: tt.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  StatusChip(t.statusAr.isNotEmpty ? t.statusAr : ticketStatuses[t.status] ?? t.status, color: color),
                  StatusChip(t.categoryAr.isNotEmpty ? t.categoryAr : ticketCategories[t.category] ?? t.category,
                      color: BrandColors.slate),
                  if (t.priority == 'high' || t.priority == 'urgent')
                    StatusChip(ticketPriorities[t.priority]!, color: BrandColors.red, icon: PhosphorIconsBold.arrowUp),
                  if (t.escalated)
                    const StatusChip('مُصعَّدة للوزارة', color: BrandColors.violet, icon: PhosphorIconsBold.flag),
                ]),
              ]),
            ),
            const SizedBox(width: 8),
            Text(Fmt.ago(t.createdAt), style: tt.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// سلسلة الردود.
class TicketThread extends StatelessWidget {
  final Ticket t;
  const TicketThread({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget bubble(String author, String kind, String body, DateTime? ts, {bool internal = false, bool mine = false}) {
      final bg = internal
          ? BrandColors.amber.withValues(alpha: 0.12)
          : mine
              ? scheme.primary.withValues(alpha: 0.10)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5);
      return Align(
        alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(authorKindAr[kind] ?? kind, style: tt.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (author.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(kind == 'subscriber' ? Fmt.maskPhone(author) : author, style: tt.bodySmall),
              ],
              if (internal) ...[
                const SizedBox(width: 6),
                const StatusChip('داخلي', color: BrandColors.amber, icon: PhosphorIconsBold.lock),
              ],
            ]),
            const SizedBox(height: 4),
            SelectableText(body, style: tt.bodyMedium),
            const SizedBox(height: 4),
            Text(Fmt.dateTime(ts), style: tt.bodySmall?.copyWith(fontSize: 11)),
          ]),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (t.body.isNotEmpty) bubble(t.createdBy, t.createdByKind, t.body, t.createdAt),
      for (final r in t.replies)
        bubble(r.author, r.authorKind, r.body, r.ts, internal: r.internal, mine: r.authorKind != 'subscriber'),
      if (t.body.isEmpty && t.replies.isEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('لا ردود بعد', style: tt.bodySmall, textAlign: TextAlign.center),
        ),
    ]);
  }
}

/// محرّر ردّ مع خيار «داخلي» للموظّفين.
class ReplyComposer extends StatefulWidget {
  final Future<void> Function(String body, bool internal) onSend;
  final bool allowInternal;
  final bool enabled;
  const ReplyComposer({super.key, required this.onSend, this.allowInternal = false, this.enabled = true});
  @override
  State<ReplyComposer> createState() => _ReplyComposerState();
}

class _ReplyComposerState extends State<ReplyComposer> {
  final _c = TextEditingController();
  bool _internal = false;
  bool _busy = false;

  Future<void> _send() async {
    final body = _c.text.trim();
    if (body.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onSend(body, _internal);
      _c.clear();
      setState(() => _internal = false);
    } catch (e) {
      if (mounted) showMsg(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('التذكرة مغلقة — لا يمكن الردّ', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.allowInternal)
            Row(children: [
              Switch(value: _internal, onChanged: (v) => setState(() => _internal = v)),
              const SizedBox(width: 4),
              Text('ملاحظة داخلية (لا يراها المشترك)', style: Theme.of(context).textTheme.bodySmall),
            ]),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _c,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(hintText: _internal ? 'ملاحظة داخلية…' : 'اكتب ردّاً…', isDense: true),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              width: 48,
              child: FilledButton(
                onPressed: _busy ? null : _send,
                style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 48)),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(PhosphorIconsBold.paperPlaneTilt, size: 20),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
