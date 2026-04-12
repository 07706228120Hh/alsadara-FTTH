import 'dart:async';
import 'package:flutter/material.dart';
import '../services/in_app_notification_service.dart';

/// ويدجت Overlay يُغلّف الـ child (كل الصفحات)
/// يعرض بانر متحرك أعلى الشاشة عند وصول إشعار
class InAppNotificationOverlay extends StatefulWidget {
  final Widget child;
  const InAppNotificationOverlay({super.key, required this.child});

  @override
  State<InAppNotificationOverlay> createState() => _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState extends State<InAppNotificationOverlay> {
  StreamSubscription<InAppNotification>? _sub;
  final List<_BannerEntry> _queue = [];

  @override
  void initState() {
    super.initState();
    _sub = InAppNotificationService.instance.stream.listen(_onNotification);
  }

  void _onNotification(InAppNotification notification) {
    if (!mounted) return;
    setState(() {
      // أقصى 3 بانرات مرئية في نفس الوقت
      if (_queue.length >= 3) _queue.removeAt(0);
      _queue.add(_BannerEntry(notification: notification));
    });
  }

  void _dismiss(_BannerEntry entry) {
    if (!mounted) return;
    setState(() => _queue.remove(entry));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // البانرات فوق كل شيء
        if (_queue.isNotEmpty)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Column(
              children: _queue.map((entry) => _NotificationBanner(
                key: ValueKey(entry.hashCode),
                notification: entry.notification,
                onDismiss: () => _dismiss(entry),
              )).toList(),
            ),
          ),
      ],
    );
  }
}

class _BannerEntry {
  final InAppNotification notification;
  _BannerEntry({required this.notification});
}

/// بانر إشعار واحد مع أنيميشن دخول + اختفاء تلقائي
class _NotificationBanner extends StatefulWidget {
  final InAppNotification notification;
  final VoidCallback onDismiss;

  const _NotificationBanner({
    super.key,
    required this.notification,
    required this.onDismiss,
  });

  @override
  State<_NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<_NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  Timer? _autoHideTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    _animController.forward();

    // اختفاء تلقائي بعد 5 ثوانٍ
    _autoHideTimer = Timer(const Duration(seconds: 5), _hideAndDismiss);
  }

  void _hideAndDismiss() {
    if (!mounted) return;
    _animController.reverse().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final config = _getTypeConfig(n.type);

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Dismissible(
          key: ValueKey(widget.key),
          direction: DismissDirection.up,
          onDismissed: (_) => widget.onDismiss(),
          child: GestureDetector(
            onTap: () {
              n.onTap?.call();
              _hideAndDismiss();
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: config.bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: config.borderColor, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // أيقونة النوع
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: config.iconBgColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(config.icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  // النصوص
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          n.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: config.textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          n.body,
                          style: TextStyle(
                            fontSize: 12,
                            color: config.textColor.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // زر إغلاق
                  GestureDetector(
                    onTap: _hideAndDismiss,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 18, color: config.textColor.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _BannerTypeConfig _getTypeConfig(InAppNotificationType type) {
    switch (type) {
      case InAppNotificationType.task:
        return _BannerTypeConfig(
          icon: Icons.task_alt_rounded,
          bgColor: const Color(0xFF1A237E),
          borderColor: const Color(0xFF3949AB),
          iconBgColor: const Color(0xFF3F51B5),
          textColor: Colors.white,
        );
      case InAppNotificationType.chat:
        return _BannerTypeConfig(
          icon: Icons.chat_rounded,
          bgColor: const Color(0xFF1B5E20),
          borderColor: const Color(0xFF43A047),
          iconBgColor: const Color(0xFF4CAF50),
          textColor: Colors.white,
        );
      case InAppNotificationType.agent:
        return _BannerTypeConfig(
          icon: Icons.storefront_rounded,
          bgColor: const Color(0xFFE65100),
          borderColor: const Color(0xFFFB8C00),
          iconBgColor: const Color(0xFFFF9800),
          textColor: Colors.white,
        );
      case InAppNotificationType.citizen:
        return _BannerTypeConfig(
          icon: Icons.person_rounded,
          bgColor: const Color(0xFF4A148C),
          borderColor: const Color(0xFF8E24AA),
          iconBgColor: const Color(0xFF9C27B0),
          textColor: Colors.white,
        );
      case InAppNotificationType.system:
        return _BannerTypeConfig(
          icon: Icons.notifications_rounded,
          bgColor: const Color(0xFF263238),
          borderColor: const Color(0xFF546E7A),
          iconBgColor: const Color(0xFF607D8B),
          textColor: Colors.white,
        );
    }
  }
}

class _BannerTypeConfig {
  final IconData icon;
  final Color bgColor;
  final Color borderColor;
  final Color iconBgColor;
  final Color textColor;

  _BannerTypeConfig({
    required this.icon,
    required this.bgColor,
    required this.borderColor,
    required this.iconBgColor,
    required this.textColor,
  });
}
