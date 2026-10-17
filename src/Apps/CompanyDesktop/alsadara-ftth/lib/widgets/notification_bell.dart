import 'dart:async';
import 'package:flutter/material.dart';
import '../services/notification_api_service.dart';
import '../frontend/tokens/sd_colors.dart' show SdColors;

/// زر جرس إشعارات قابل لإعادة الاستخدام — يُضاف في أي AppBar
/// يعرض بادج بعدد الإشعارات غير المقروءة ويفتح لوحة الإشعارات
class NotificationBell extends StatefulWidget {
  final Color iconColor;
  final double iconSize;

  const NotificationBell({
    super.key,
    this.iconColor = Colors.white,
    this.iconSize = 24,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unreadCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _fetch();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await NotificationApiService.instance.getUnreadCount();
      if (res['success'] == true && mounted) {
        setState(() => _unreadCount = (res['data'] ?? 0) as int);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'الإشعارات',
      onPressed: () => _showPanel(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_outlined, color: widget.iconColor, size: widget.iconSize),
          if (_unreadCount > 0)
            Positioned(
              top: -4,
              right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: SdColors.danger,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: SdColors.danger.withValues(alpha: 0.4), blurRadius: 4)],
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                child: Text(
                  _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsPanel(onRead: _fetch),
    );
  }
}

/// لوحة الإشعارات
class _NotificationsPanel extends StatefulWidget {
  final VoidCallback? onRead;
  const _NotificationsPanel({this.onRead});

  @override
  State<_NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<_NotificationsPanel> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await NotificationApiService.instance.getMyNotifications(
        pageSize: 30,
        unreadOnly: _unreadOnly ? true : null,
      );
      if (res['success'] == true && mounted) {
        final items = res['data'] is List ? res['data'] as List : [];
        setState(() => _notifications = items.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _markAsRead(int id) async {
    await NotificationApiService.instance.markAsRead(id);
    widget.onRead?.call();
    _load();
  }

  Future<void> _markAllRead() async {
    await NotificationApiService.instance.markAllAsRead();
    widget.onRead?.call();
    _load();
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'RequestStatusUpdate': return Icons.task_alt_rounded;
      case 'RequestAssigned': return Icons.assignment_ind_rounded;
      case 'AgentRequest': return Icons.storefront_rounded;
      case 'ChatMessage': return Icons.chat_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String? type) {
    switch (type) {
      case 'RequestStatusUpdate': return SdColors.info;
      case 'RequestAssigned': return SdColors.accent;
      case 'AgentRequest': return SdColors.warning;
      case 'ChatMessage': return SdColors.success;
      default: return SdColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40, height: 4,
            decoration: BoxDecoration(color: SdColors.edge, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.notifications_rounded, color: SdColors.primary, size: 24),
                const SizedBox(width: 8),
                const Text('الإشعارات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SdColors.primary)),
                const Spacer(),
                FilterChip(
                  label: Text(_unreadOnly ? 'غير المقروءة' : 'الكل', style: const TextStyle(fontSize: 11)),
                  selected: _unreadOnly,
                  onSelected: (v) { setState(() => _unreadOnly = v); _load(); },
                  selectedColor: SdColors.primary.withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'قراءة الكل',
                  icon: const Icon(Icons.done_all_rounded, size: 20),
                  onPressed: _markAllRead,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_off_outlined, size: 48, color: SdColors.edge),
                            const SizedBox(height: 8),
                            Text('لا توجد إشعارات', style: TextStyle(color: SdColors.faint, fontSize: 14)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 60),
                          itemBuilder: (_, i) {
                            final n = _notifications[i];
                            final isRead = n['IsRead'] == true || n['isRead'] == true;
                            final type = n['Type']?.toString() ?? n['type']?.toString();
                            final title = n['TitleAr']?.toString() ?? n['Title']?.toString() ?? n['title']?.toString() ?? '';
                            final body = n['BodyAr']?.toString() ?? n['Body']?.toString() ?? n['body']?.toString() ?? '';
                            final id = n['Id'] ?? n['id'];
                            final createdAt = DateTime.tryParse(n['CreatedAt']?.toString() ?? n['createdAt']?.toString() ?? '');
                            final color = _typeColor(type);

                            return ListTile(
                              dense: true,
                              tileColor: isRead ? null : color.withValues(alpha: 0.05),
                              leading: Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(_typeIcon(type), color: color, size: 20),
                              ),
                              title: Text(title, style: TextStyle(fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(body, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if (createdAt != null)
                                    Text(_timeAgo(createdAt), style: TextStyle(fontSize: 10, color: SdColors.faint)),
                                ],
                              ),
                              trailing: !isRead && id != null
                                  ? IconButton(
                                      icon: Icon(Icons.check_circle_outline, size: 18, color: color),
                                      tooltip: 'قراءة',
                                      onPressed: () => _markAsRead(id is int ? id : int.tryParse(id.toString()) ?? 0),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 7) return 'قبل ${diff.inDays} يوم';
    return '${dt.day}/${dt.month}';
  }
}
