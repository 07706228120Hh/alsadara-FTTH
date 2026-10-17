import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../permissions/permission_manager.dart';
import '../models/sas_ticket.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';

/// تفاصيل تذكرة «وكيل الساس» — رأس التذكرة + سلسلة المحادثة + صندوق رد
/// (مع خيار «داخلي») + أزرار تغيير الحالة/الأولوية.
///
/// الكتابة (رد/تحديث) محكومة بصلاحية `sas_agent` عبر [PermissionManager.canAdd].
/// يعيد `true` عند الإغلاق إذا حدث أي تغيير (ليعيد المستدعي تحميل القائمة).
class SasTicketDetailPage extends StatefulWidget {
  final String ticketId;
  const SasTicketDetailPage({super.key, required this.ticketId});

  @override
  State<SasTicketDetailPage> createState() => _SasTicketDetailPageState();
}

class _SasTicketDetailPageState extends State<SasTicketDetailPage> {
  final _api = SasAgentApiService.instance;
  final _replyCtl = TextEditingController();

  SasTicket? _ticket;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  bool _internal = false;
  bool _changed = false;

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyCtl.dispose();
    super.dispose();
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await _api.getTicket(widget.ticketId);
      if (!mounted) return;
      setState(() {
        _ticket = t;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _clean(e);
          _loading = false;
        });
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: SdText.family)),
      backgroundColor: error ? SdColors.danger : SdColors.success,
    ));
  }

  Future<void> _sendReply() async {
    final body = _replyCtl.text.trim();
    if (body.isEmpty || !_canManage || _sending) return;
    setState(() => _sending = true);
    try {
      await _api.replyTicket(widget.ticketId,
          body: body, isInternal: _internal);
      _replyCtl.clear();
      _internal = false;
      _changed = true;
      await _load();
      _snack('تم إرسال الرد');
    } catch (e) {
      _snack(_clean(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _update(
      {String? status, String? priority, String? category}) async {
    if (!_canManage) return;
    setState(() => _sending = true);
    try {
      await _api.updateTicket(widget.ticketId,
          status: status, priority: priority, category: category);
      _changed = true;
      await _load();
      _snack('تم تحديث التذكرة');
    } catch (e) {
      _snack(_clean(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return SdPage(
      maxWidth: 900,
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: SdAppBar(
        title: t == null ? 'تذكرة #${widget.ticketId}' : 'تذكرة · ${t.subject}',
        leading: BackButton(
          color: Colors.white,
          onPressed: () => Navigator.of(context).pop(_changed),
        ),
        actions: [
          if (t != null && _canManage)
            PopupMenuButton<String>(
              enabled: !_sending,
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              onSelected: (v) {
                if (v.startsWith('s:')) _update(status: v.substring(2));
                if (v.startsWith('p:')) _update(priority: v.substring(2));
                if (v.startsWith('c:')) _update(category: v.substring(2));
              },
              itemBuilder: (_) => [
                _menuHeader('تغيير الحالة'),
                for (final e in sasTicketStatuses.entries)
                  if (e.key != t.status)
                    PopupMenuItem(
                      value: 's:${e.key}',
                      child: Text('الحالة: ${e.value}',
                          style: const TextStyle(fontFamily: SdText.family)),
                    ),
                const PopupMenuDivider(),
                _menuHeader('تغيير الأولوية'),
                for (final e in sasTicketPriorities.entries)
                  if (e.key != t.priority)
                    PopupMenuItem(
                      value: 'p:${e.key}',
                      child: Text('الأولوية: ${e.value}',
                          style: const TextStyle(fontFamily: SdText.family)),
                    ),
              ],
            ),
        ],
      ),
      body: _loading
          ? const SasLoadingView(message: 'جاري تحميل التذكرة…')
          : _error != null
              ? SasErrorView(message: _error!, onRetry: _load)
              : t == null
                  ? const SdEmptyState(title: 'التذكرة غير موجودة')
                  : SasContentWrap(
                      maxWidth: 900,
                      child: Column(
                        children: [
                          Expanded(child: _thread(t)),
                          _composer(t),
                        ],
                      ),
                    ),
    );
  }

  PopupMenuItem<String> _menuHeader(String text) => PopupMenuItem<String>(
        enabled: false,
        height: 30,
        child: Text(text,
            style: const TextStyle(
                fontFamily: SdText.family,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: SdColors.muted)),
      );

  Widget _thread(SasTicket t) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [
          _headerCard(t),
          const SizedBox(height: SdSpace.md),
          SdSectionHeader(
            title: 'المحادثة',
            tone: SdGroup.comms.tone,
            count: t.replies.length,
          ),
          const SizedBox(height: SdSpace.xs),
          _originalMessage(t),
          for (final r in t.replies) ...[
            const SizedBox(height: SdSpace.xs),
            _replyBubble(r),
          ],
          if (t.replies.isEmpty) ...[
            const SizedBox(height: SdSpace.xs),
            Center(
              child: Text('لا ردود بعد — كن أول من يرد', style: SdText.bodySm),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerCard(SasTicket t) {
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.subject, style: SdText.title),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              SdStatusChip(sasStatusAr(t.status),
                  status: _statusStatus(t.status), icon: _statusIcon(t.status)),
              SdStatusChip('أولوية: ${sasPriorityAr(t.priority)}',
                  status: _priorityStatus(t.priority),
                  icon: Icons.flag_rounded),
              SdStatusChip(sasCategoryAr(t.category),
                  status: SdStatus.neutral, icon: Icons.label_rounded),
            ],
          ),
          if (t.subscriberRef.isNotEmpty ||
              t.createdBy.isNotEmpty ||
              t.createdAt != null) ...[
            const Divider(height: 22, color: SdColors.divider),
            if (t.subscriberRef.isNotEmpty)
              _kv(Icons.person_rounded, 'المشترك', t.subscriberRef),
            if (t.createdBy.isNotEmpty)
              _kv(Icons.badge_rounded, 'فتحها',
                  '${t.createdBy}${t.createdByKind.isNotEmpty ? ' (${sasAuthorAr(t.createdByKind)})' : ''}'),
            if (t.createdAt != null)
              _kv(Icons.schedule_rounded, 'فُتحت', _fmtDate(t.createdAt!)),
            if (t.updatedAt != null)
              _kv(Icons.update_rounded, 'آخر تحديث', _fmtDate(t.updatedAt!)),
          ],
        ],
      ),
    );
  }

  Widget _kv(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: SdColors.faint),
          const SizedBox(width: 6),
          Text('$label: ', style: SdText.bodySm),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: SdColors.ink)),
          ),
        ],
      ),
    );
  }

  Widget _originalMessage(SasTicket t) {
    return _bubble(
      author: t.createdBy.isNotEmpty ? t.createdBy : 'مقدّم الطلب',
      body: t.body,
      ts: t.createdAt,
      internal: false,
      isOriginal: true,
    );
  }

  Widget _replyBubble(SasTicketReply r) {
    return _bubble(
      author: r.author.isNotEmpty ? r.author : sasAuthorAr(r.authorKind),
      body: r.body,
      ts: r.createdAt,
      internal: r.isInternal,
      isOriginal: false,
    );
  }

  Widget _bubble({
    required String author,
    required String body,
    required DateTime? ts,
    required bool internal,
    required bool isOriginal,
  }) {
    final tone = internal
        ? SdStatus.warning.tone
        : (isOriginal ? SdGroup.admin.tone : SdStatus.success.tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: internal ? SdColors.warningTint : SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        border: Border.all(
          color: internal ? tone.tintEdge : SdColors.cardEdge,
          width: 1.2,
        ),
        boxShadow: SdDepth.raised(
            edge: internal ? tone.tintEdge : SdColors.cardEdge,
            depth: SdDepth.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: tone.tint,
                child: Icon(
                  isOriginal ? Icons.person_rounded : Icons.reply_rounded,
                  size: 15,
                  color: tone.base,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  author,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: SdColors.ink),
                ),
              ),
              if (internal)
                const SdStatusChip('داخلي',
                    status: SdStatus.warning, icon: Icons.lock_rounded),
              if (ts != null) ...[
                const SizedBox(width: 6),
                Text(_fmtDate(ts),
                    style: SdText.caption.copyWith(color: SdColors.faint)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body.isEmpty ? '—' : body,
            style: SdText.body,
          ),
        ],
      ),
    );
  }

  Widget _composer(SasTicket t) {
    final closed = t.status == 'closed';
    final disabled = !_canManage || closed;
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_canManage)
              _hint(Icons.lock_outline_rounded,
                  'لا تملك صلاحية الرد على التذاكر')
            else if (closed)
              _hint(Icons.lock_rounded, 'التذكرة مغلقة — لا يمكن إضافة ردود')
            else
              Row(
                children: [
                  Checkbox(
                    value: _internal,
                    activeColor: SdColors.warning,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5)),
                    onChanged: (v) => setState(() => _internal = v ?? false),
                  ),
                  Text('ملاحظة داخلية',
                      style: SdText.bodySm.copyWith(
                          color: SdColors.ink, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.info_outline_rounded,
                      size: 13, color: SdColors.faint),
                ],
              ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtl,
                    enabled: !disabled && !_sending,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 13,
                        color: SdColors.ink),
                    decoration: InputDecoration(
                      hintText: disabled ? 'الرد غير متاح' : 'اكتب ردّك…',
                      hintStyle: const TextStyle(
                          fontFamily: SdText.family,
                          fontSize: 12.5,
                          color: SdColors.faint),
                      filled: true,
                      fillColor: SdColors.ground,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SdRadius.sm),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _sendButton(disabled),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendButton(bool disabled) {
    final enabled = !disabled && !_sending;
    return SizedBox(
      height: 46,
      width: 56,
      child: SdRaised(
        onTap: enabled ? _sendReply : null,
        radius: SdRadius.sm,
        depth: SdDepth.button,
        color: _internal ? SdColors.warning : SdColors.primary,
        edgeColor: _internal ? SdColors.warningEdge : SdColors.primaryEdge,
        padding: EdgeInsets.zero,
        semanticLabel: 'إرسال',
        child: Center(
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.send_rounded, color: Colors.white),
        ),
      ),
    );
  }

  Widget _hint(IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.sm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: SdColors.muted),
          const SizedBox(width: 8),
          Text(text,
              style: SdText.bodySm.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────── مساعدات مشتركة ───────────────────────────

SdStatus _statusStatus(String s) {
  switch (s) {
    case 'open':
      return SdStatus.info;
    case 'in_progress':
      return SdStatus.warning;
    case 'resolved':
      return SdStatus.success;
    case 'closed':
      return SdStatus.neutral;
    default:
      return SdStatus.neutral;
  }
}

IconData _statusIcon(String s) {
  switch (s) {
    case 'open':
      return Icons.mark_email_unread_rounded;
    case 'in_progress':
      return Icons.autorenew_rounded;
    case 'resolved':
      return Icons.check_circle_rounded;
    case 'closed':
      return Icons.lock_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

SdStatus _priorityStatus(String p) {
  switch (p) {
    case 'urgent':
      return SdStatus.danger;
    case 'high':
      return SdStatus.warning;
    case 'normal':
      return SdStatus.neutral;
    case 'low':
      return SdStatus.neutral;
    default:
      return SdStatus.neutral;
  }
}

String _fmtDate(DateTime d) {
  final dl = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dl.year}/${two(dl.month)}/${two(dl.day)} ${two(dl.hour)}:${two(dl.minute)}';
}
