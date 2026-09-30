import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
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
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
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

  Future<void> _update({String? status, String? priority, String? category}) async {
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          title: Text(
            t == null ? 'تذكرة #${widget.ticketId}' : 'تذكرة · ${t.subject}',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800),
          ),
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          actions: [
            if (t != null && _canManage)
              PopupMenuButton<String>(
                enabled: !_sending,
                icon: const Icon(Icons.more_vert_rounded),
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
                            style: GoogleFonts.cairo()),
                      ),
                  const PopupMenuDivider(),
                  _menuHeader('تغيير الأولوية'),
                  for (final e in sasTicketPriorities.entries)
                    if (e.key != t.priority)
                      PopupMenuItem(
                        value: 'p:${e.key}',
                        child: Text('الأولوية: ${e.value}',
                            style: GoogleFonts.cairo()),
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
                    ? const SasEmptyView(message: 'التذكرة غير موجودة')
                    : Column(
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
            style: GoogleFonts.cairo(
                fontSize: 11.sp,
                fontWeight: FontWeight.w800,
                color: Colors.grey[600])),
      );

  Widget _thread(SasTicket t) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 20.h),
        children: [
          _headerCard(t),
          SizedBox(height: 16.h),
          SasSectionHeader(
            title: 'المحادثة',
            icon: Icons.forum_rounded,
            trailingText: '${t.replies.length}',
          ),
          SizedBox(height: 10.h),
          _originalMessage(t),
          for (final r in t.replies) ...[
            SizedBox(height: 8.h),
            _replyBubble(r),
          ],
          if (t.replies.isEmpty) ...[
            SizedBox(height: 8.h),
            Center(
              child: Text('لا ردود بعد — كن أول من يرد',
                  style: GoogleFonts.cairo(
                      fontSize: 12.sp, color: Colors.grey[500])),
            ),
          ],
        ],
      ),
    );
  }

  Widget _headerCard(SasTicket t) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.subject,
            style: GoogleFonts.cairo(
                fontSize: 16.sp,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1A1A2E)),
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: [
              SasStatusBadge(
                label: sasStatusAr(t.status),
                color: _statusColor(t.status),
                icon: _statusIcon(t.status),
              ),
              SasStatusBadge(
                label: 'أولوية: ${sasPriorityAr(t.priority)}',
                color: _priorityColor(t.priority),
                icon: Icons.flag_rounded,
              ),
              SasStatusBadge(
                label: sasCategoryAr(t.category),
                color: Colors.blueGrey,
                icon: Icons.label_rounded,
              ),
            ],
          ),
          if (t.subscriberRef.isNotEmpty ||
              t.createdBy.isNotEmpty ||
              t.createdAt != null) ...[
            Divider(height: 22.h),
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
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15.sp, color: Colors.grey[500]),
          SizedBox(width: 6.w),
          Text('$label: ',
              style: GoogleFonts.cairo(
                  fontSize: 12.sp, color: Colors.grey[600])),
          Expanded(
            child: Text(value,
                style: GoogleFonts.cairo(
                    fontSize: 12.sp, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _originalMessage(SasTicket t) {
    return _bubble(
      author: t.createdBy.isNotEmpty ? t.createdBy : 'مقدّم الطلب',
      authorKind: t.createdByKind,
      body: t.body,
      ts: t.createdAt,
      internal: false,
      isOriginal: true,
    );
  }

  Widget _replyBubble(SasTicketReply r) {
    return _bubble(
      author: r.author.isNotEmpty ? r.author : sasAuthorAr(r.authorKind),
      authorKind: r.authorKind,
      body: r.body,
      ts: r.createdAt,
      internal: r.isInternal,
      isOriginal: false,
    );
  }

  Widget _bubble({
    required String author,
    required String authorKind,
    required String body,
    required DateTime? ts,
    required bool internal,
    required bool isOriginal,
  }) {
    final accent = internal
        ? AppTheme.warningColor
        : (isOriginal ? AppTheme.primaryColor : AppTheme.successColor);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(13.w),
      decoration: BoxDecoration(
        color: internal
            ? AppTheme.warningColor.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border: Border.all(
          color: accent.withValues(alpha: internal ? 0.35 : 0.16),
          width: 1.2,
        ),
        boxShadow: SasUi.cardShadow(accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 13.r,
                backgroundColor: accent.withValues(alpha: 0.14),
                child: Icon(
                  isOriginal ? Icons.person_rounded : Icons.reply_rounded,
                  size: 15.sp,
                  color: accent,
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  author,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 12.5.sp, fontWeight: FontWeight.w800),
                ),
              ),
              if (internal)
                SasStatusBadge(
                  label: 'داخلي',
                  color: AppTheme.warningColor,
                  icon: Icons.lock_rounded,
                ),
              if (ts != null) ...[
                SizedBox(width: 6.w),
                Text(_fmtDate(ts),
                    style: GoogleFonts.cairo(
                        fontSize: 10.5.sp, color: Colors.grey[500])),
              ],
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            body.isEmpty ? '—' : body,
            style: GoogleFonts.cairo(
                fontSize: 13.sp, height: 1.6, color: Colors.grey[850]),
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
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            spreadRadius: -2,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 12.h),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_canManage)
              _hint(Icons.lock_outline_rounded, 'لا تملك صلاحية الرد على التذاكر')
            else if (closed)
              _hint(Icons.lock_rounded, 'التذكرة مغلقة — لا يمكن إضافة ردود')
            else
              Row(
                children: [
                  Checkbox(
                    value: _internal,
                    activeColor: AppTheme.warningColor,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5.r)),
                    onChanged: (v) => setState(() => _internal = v ?? false),
                  ),
                  Text('ملاحظة داخلية',
                      style: GoogleFonts.cairo(
                          fontSize: 12.sp, fontWeight: FontWeight.w700)),
                  SizedBox(width: 4.w),
                  Icon(Icons.info_outline_rounded,
                      size: 13.sp, color: Colors.grey[500]),
                ],
              ),
            SizedBox(height: 6.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtl,
                    enabled: !disabled && !_sending,
                    minLines: 1,
                    maxLines: 4,
                    style: GoogleFonts.cairo(fontSize: 13.sp),
                    decoration: InputDecoration(
                      hintText: disabled ? 'الرد غير متاح' : 'اكتب ردّك…',
                      hintStyle: GoogleFonts.cairo(
                          fontSize: 12.5.sp, color: Colors.grey[500]),
                      filled: true,
                      fillColor: SasUi.pageBg,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                _sendButton(disabled),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sendButton(bool disabled) {
    return SizedBox(
      height: 46.h,
      child: FilledButton(
        onPressed: (disabled || _sending) ? null : _sendReply,
        style: FilledButton.styleFrom(
          backgroundColor:
              _internal ? AppTheme.warningColor : AppTheme.primaryColor,
          disabledBackgroundColor: Colors.grey.withValues(alpha: 0.30),
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
        ),
        child: _sending
            ? SizedBox(
                width: 18.w,
                height: 18.w,
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.send_rounded, color: Colors.white),
      ),
    );
  }

  Widget _hint(IconData icon, String text) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16.sp, color: Colors.grey[600]),
          SizedBox(width: 8.w),
          Text(text,
              style: GoogleFonts.cairo(
                  fontSize: 12.sp,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─────────────────────────── مساعدات مشتركة ───────────────────────────

Color _statusColor(String s) {
  switch (s) {
    case 'open':
      return AppTheme.primaryColor;
    case 'in_progress':
      return AppTheme.warningColor;
    case 'resolved':
      return AppTheme.successColor;
    case 'closed':
      return Colors.blueGrey;
    default:
      return Colors.grey;
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

Color _priorityColor(String p) {
  switch (p) {
    case 'urgent':
      return AppTheme.errorColor;
    case 'high':
      return const Color(0xFFF4511E);
    case 'normal':
      return Colors.blueGrey;
    case 'low':
      return Colors.grey;
    default:
      return Colors.blueGrey;
  }
}

String _fmtDate(DateTime d) {
  final dl = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dl.year}/${two(dl.month)}/${two(dl.day)} ${two(dl.hour)}:${two(dl.minute)}';
}
