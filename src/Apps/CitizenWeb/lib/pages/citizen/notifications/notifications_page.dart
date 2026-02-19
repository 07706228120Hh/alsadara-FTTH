import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة الإشعارات
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  String _selectedFilter = 'all';

  // إشعارات تجريبية
  final List<Map<String, dynamic>> _notifications = [
    {
      'id': '1',
      'title': 'تم تجديد اشتراكك بنجاح',
      'body': 'تم تجديد اشتراك الإنترنت الخاص بك لمدة شهر. شكراً لثقتك بنا.',
      'type': 'success',
      'category': 'subscription',
      'time': 'منذ 5 دقائق',
      'isRead': false,
    },
    {
      'id': '2',
      'title': 'فاتورة جديدة',
      'body': 'تم إصدار فاتورة جديدة بمبلغ 299 د.ع. موعد السداد: 15 فبراير.',
      'type': 'info',
      'category': 'billing',
      'time': 'منذ ساعة',
      'isRead': false,
    },
    {
      'id': '3',
      'title': 'تحديث التذكرة',
      'body': 'تم الرد على تذكرة الدعم الفني #TKT-001.',
      'type': 'info',
      'category': 'support',
      'time': 'منذ 3 ساعات',
      'isRead': true,
    },
    {
      'id': '4',
      'title': 'عرض خاص!',
      'body': 'احصل على خصم 20% عند ترقية باقتك. العرض ساري حتى نهاية الشهر.',
      'type': 'promo',
      'category': 'offers',
      'time': 'منذ يوم',
      'isRead': true,
    },
    {
      'id': '5',
      'title': 'تنبيه: اشتراكك قارب على الانتهاء',
      'body': 'اشتراكك سينتهي خلال 5 أيام. قم بالتجديد الآن للاستمرار بالخدمة.',
      'type': 'warning',
      'category': 'subscription',
      'time': 'منذ يومين',
      'isRead': true,
    },
    {
      'id': '6',
      'title': 'تم شحن طلبك',
      'body': 'طلبك من المتجر في الطريق إليك. رقم التتبع: #SHP123456',
      'type': 'info',
      'category': 'store',
      'time': 'منذ 3 أيام',
      'isRead': true,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    final unreadCount = _notifications.where((n) => !n['isRead']).length;

    final filteredNotifications = _selectedFilter == 'all'
        ? _notifications
        : _selectedFilter == 'unread'
        ? _notifications.where((n) => !n['isRead']).toList()
        : _notifications
              .where((n) => n['category'] == _selectedFilter)
              .toList();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('الإشعارات'),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/home'),
          ),
          actions: [
            if (unreadCount > 0)
              TextButton.icon(
                onPressed: _markAllAsRead,
                icon: const Icon(Icons.done_all, color: Colors.white, size: 18),
                label: const Text(
                  'قراءة الكل',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'settings') {
                  _showNotificationSettings();
                } else if (value == 'clear') {
                  _clearAllNotifications();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings, size: 20),
                      SizedBox(width: 8),
                      Text('إعدادات الإشعارات'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, size: 20),
                      SizedBox(width: 8),
                      Text('مسح الكل'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // فلاتر التصنيفات
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.white,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterChip('all', 'الكل', null),
                    const SizedBox(width: 8),
                    _buildFilterChip('unread', 'غير مقروءة', unreadCount),
                    const SizedBox(width: 8),
                    _buildFilterChip('subscription', 'الاشتراكات', null),
                    const SizedBox(width: 8),
                    _buildFilterChip('billing', 'الفواتير', null),
                    const SizedBox(width: 8),
                    _buildFilterChip('support', 'الدعم', null),
                    const SizedBox(width: 8),
                    _buildFilterChip('offers', 'العروض', null),
                    const SizedBox(width: 8),
                    _buildFilterChip('store', 'المتجر', null),
                  ],
                ),
              ),
            ),

            // قائمة الإشعارات
            Expanded(
              child: filteredNotifications.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 0,
                        vertical: 8,
                      ),
                      itemCount: filteredNotifications.length,
                      itemBuilder: (context, index) {
                        return _buildNotificationItem(
                          filteredNotifications[index],
                          isWide,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, int? count) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count != null && count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : AppTheme.errorColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? AppTheme.primaryColor : Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      selectedColor: AppTheme.primaryColor.withOpacity(0.2),
      checkmarkColor: AppTheme.primaryColor,
      onSelected: (selected) {
        setState(() => _selectedFilter = value);
      },
    );
  }

  Widget _buildNotificationItem(
    Map<String, dynamic> notification,
    bool isWide,
  ) {
    final isUnread = !notification['isRead'];

    return Dismissible(
      key: Key(notification['id']),
      background: Container(
        color: AppTheme.errorColor,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: AppTheme.successColor,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      onDismissed: (direction) {
        setState(() {
          _notifications.removeWhere((n) => n['id'] == notification['id']);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم حذف الإشعار'),
            action: SnackBarAction(
              label: 'تراجع',
              onPressed: () {
                setState(() {
                  _notifications.add(notification);
                });
              },
            ),
          ),
        );
      },
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: isWide ? 0 : 0, vertical: 1),
        decoration: BoxDecoration(
          color: isUnread
              ? AppTheme.primaryColor.withOpacity(0.05)
              : Colors.white,
          border: Border(
            right: BorderSide(
              color: isUnread ? AppTheme.primaryColor : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: _buildNotificationIcon(notification['type']),
          title: Text(
            notification['title'],
            style: TextStyle(
              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
              color: AppTheme.textDark,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                notification['body'],
                style: const TextStyle(color: AppTheme.textGrey, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 12,
                    color: AppTheme.textGrey.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    notification['time'],
                    style: TextStyle(
                      color: AppTheme.textGrey.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildCategoryBadge(notification['category']),
                ],
              ),
            ],
          ),
          trailing: isUnread
              ? Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
          onTap: () {
            setState(() {
              notification['isRead'] = true;
            });
            _handleNotificationTap(notification);
          },
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(String type) {
    IconData icon;
    Color color;
    Color bgColor;

    switch (type) {
      case 'success':
        icon = Icons.check_circle;
        color = AppTheme.successColor;
        bgColor = AppTheme.successColor.withOpacity(0.1);
        break;
      case 'warning':
        icon = Icons.warning;
        color = AppTheme.warningColor;
        bgColor = AppTheme.warningColor.withOpacity(0.1);
        break;
      case 'error':
        icon = Icons.error;
        color = AppTheme.errorColor;
        bgColor = AppTheme.errorColor.withOpacity(0.1);
        break;
      case 'promo':
        icon = Icons.local_offer;
        color = Colors.purple;
        bgColor = Colors.purple.withOpacity(0.1);
        break;
      default:
        icon = Icons.info;
        color = AppTheme.infoColor;
        bgColor = AppTheme.infoColor.withOpacity(0.1);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  Widget _buildCategoryBadge(String category) {
    String label;
    switch (category) {
      case 'subscription':
        label = 'اشتراك';
        break;
      case 'billing':
        label = 'فواتير';
        break;
      case 'support':
        label = 'دعم';
        break;
      case 'offers':
        label = 'عروض';
        break;
      case 'store':
        label = 'متجر';
        break;
      default:
        label = category;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.textGrey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppTheme.textGrey, fontSize: 10),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 80,
            color: AppTheme.textGrey.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد إشعارات',
            style: TextStyle(fontSize: 18, color: AppTheme.textGrey),
          ),
          const SizedBox(height: 8),
          const Text(
            'ستظهر الإشعارات الجديدة هنا',
            style: TextStyle(fontSize: 14, color: AppTheme.textGrey),
          ),
        ],
      ),
    );
  }

  void _markAllAsRead() {
    setState(() {
      for (var notification in _notifications) {
        notification['isRead'] = true;
      }
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم تحديد الكل كمقروء')));
  }

  void _clearAllNotifications() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح جميع الإشعارات'),
        content: const Text('هل أنت متأكد من مسح جميع الإشعارات؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _notifications.clear();
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('مسح الكل'),
          ),
        ],
      ),
    );
  }

  void _showNotificationSettings() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'إعدادات الإشعارات',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              _buildSettingsSwitch(
                'إشعارات الاشتراكات',
                'تنبيهات التجديد والانتهاء',
                true,
                (value) {},
              ),
              _buildSettingsSwitch(
                'إشعارات الفواتير',
                'فواتير جديدة وتذكير السداد',
                true,
                (value) {},
              ),
              _buildSettingsSwitch(
                'إشعارات الدعم الفني',
                'تحديثات التذاكر والردود',
                true,
                (value) {},
              ),
              _buildSettingsSwitch(
                'العروض والتخفيضات',
                'عروض حصرية وخصومات',
                false,
                (value) {},
              ),
              _buildSettingsSwitch(
                'إشعارات المتجر',
                'تحديثات الطلبات والشحن',
                true,
                (value) {},
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSwitch(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
      ),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppTheme.primaryColor,
    );
  }

  void _handleNotificationTap(Map<String, dynamic> notification) {
    switch (notification['category']) {
      case 'subscription':
        context.go('/citizen/internet');
        break;
      case 'billing':
        context.go('/citizen/requests');
        break;
      case 'support':
        context.go('/citizen/support');
        break;
      case 'offers':
        // عرض تفاصيل العرض
        break;
      case 'store':
        context.go('/citizen/store');
        break;
    }
  }
}
