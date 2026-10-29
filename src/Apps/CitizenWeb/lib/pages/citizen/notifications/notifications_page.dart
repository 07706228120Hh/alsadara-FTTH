import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';

/// الإشعارات — موحّدة على نظام تصميم الصدارة (3D).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final List<Map<String, dynamic>> _notifications = [
    {'id': '1', 'title': 'تم تجديد اشتراكك بنجاح', 'body': 'تم تجديد اشتراك الإنترنت الخاص بك لمدة شهر. شكراً لثقتك بنا.', 'type': 'success', 'category': 'subscription', 'time': 'منذ 5 دقائق', 'isRead': false},
    {'id': '2', 'title': 'فاتورة جديدة', 'body': 'تم إصدار فاتورة جديدة بمبلغ 299 د.ع. موعد السداد: 15 فبراير.', 'type': 'info', 'category': 'billing', 'time': 'منذ ساعة', 'isRead': false},
    {'id': '3', 'title': 'تحديث التذكرة', 'body': 'تم الرد على تذكرة الدعم الفني #TKT-001.', 'type': 'info', 'category': 'support', 'time': 'منذ 3 ساعات', 'isRead': true},
    {'id': '4', 'title': 'عرض خاص!', 'body': 'احصل على خصم 20% عند ترقية باقتك. العرض ساري حتى نهاية الشهر.', 'type': 'promo', 'category': 'offers', 'time': 'منذ يوم', 'isRead': true},
    {'id': '5', 'title': 'تنبيه: اشتراكك قارب على الانتهاء', 'body': 'اشتراكك سينتهي خلال 5 أيام. قم بالتجديد الآن للاستمرار بالخدمة.', 'type': 'warning', 'category': 'subscription', 'time': 'منذ يومين', 'isRead': true},
    {'id': '6', 'title': 'تم شحن طلبك', 'body': 'طلبك من المتجر في الطريق إليك. رقم التتبع: #SHP123456', 'type': 'info', 'category': 'store', 'time': 'منذ 3 أيام', 'isRead': true},
  ];

  int get _unread => _notifications.where((n) => n['isRead'] == false).length;

  void _markAllRead() =>
      setState(() => {for (final n in _notifications) n['isRead'] = true});

  void _handleTap(Map<String, dynamic> n) {
    setState(() => n['isRead'] = true);
    switch (n['category']) {
      case 'subscription': context.go('/citizen/internet'); break;
      case 'billing': context.go('/citizen/requests'); break;
      case 'support': context.go('/citizen/support'); break;
      case 'store': context.go('/citizen/store'); break;
      case 'offers': break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      maxWidth: 680,
      appBar: SdAppBar(
        title: 'الإشعارات',
        subtitle: _unread > 0 ? '$_unread غير مقروءة' : null,
        onBack: () => context.go('/citizen/home'),
        actions: [
          TextButton(
            onPressed: _unread > 0 ? _markAllRead : null,
            child: const Text('تعليم الكل'),
          ),
        ],
      ),
      body: _notifications.isEmpty
          ? const SdEmptyState(
              title: 'لا توجد إشعارات',
              message: 'ستظهر إشعاراتك هنا',
              icon: Icons.notifications_off_rounded,
            )
          : Column(
              children: [for (final n in _notifications) _card(n)],
            ),
    );
  }

  Widget _card(Map<String, dynamic> n) {
    final t = _typeOf(n['type'] as String);
    final unread = n['isRead'] == false;
    return Padding(
      padding: const EdgeInsets.only(bottom: SdSpace.sm),
      child: Opacity(
        opacity: unread ? 1 : 0.82,
        child: SdRaised(
          onTap: () => _handleTap(n),
          radius: SdRadius.lg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SdIconCube(icon: t.$1, tone: t.$2, size: 44),
              const SizedBox(width: SdSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(n['title'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SdText.label),
                        ),
                        if (unread)
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                                color: SdColors.accent, shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(n['body'] as String, style: SdText.bodySm),
                    const SizedBox(height: 4),
                    Text(n['time'] as String, style: SdText.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, SdTone) _typeOf(String t) {
    switch (t) {
      case 'success': return (Icons.check_circle_rounded, SdStatus.success.tone);
      case 'warning': return (Icons.warning_amber_rounded, SdStatus.warning.tone);
      case 'promo': return (Icons.local_offer_rounded, SdGroup.platform.tone);
      case 'info':
      default: return (Icons.info_rounded, SdStatus.info.tone);
    }
  }
}
