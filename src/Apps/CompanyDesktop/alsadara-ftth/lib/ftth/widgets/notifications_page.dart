/// اسم الصفحة: الإشعارات
/// وصف الصفحة: صفحة إدارة الإشعارات والتنبيهات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../auth/auth_error_handler.dart';

class NotificationsPage extends StatefulWidget {
  final String authToken;

  const NotificationsPage({
    super.key,
    required this.authToken,
  });

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool isLoading = true;
  List<Map<String, dynamic>> notifications = [];
  int totalCount = 0;
  int currentPage = 1;
  int pageSize = 20;
  final ScrollController _scrollController = ScrollController();
  bool isLoadingMore = false;
  bool showUnreadOnly = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.maxScrollExtent) {
      _loadMoreNotifications();
    }
  }

  Future<void> _loadNotifications({bool isRefresh = false}) async {
    if (isRefresh) {
      setState(() {
        currentPage = 1;
        notifications.clear();
        isLoading = true;
      });
    }

    try {
      final unreadParam = showUnreadOnly ? 'true' : 'false';
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/notifications?onlyUnreadNotifications=$unreadParam&pageSize=$pageSize&pageNumber=$currentPage',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          totalCount = data['totalCount'] ?? 0;
          if (isRefresh || currentPage == 1) {
            notifications =
                List<Map<String, dynamic>>.from(data['items'] ?? []);
          } else {
            notifications
                .addAll(List<Map<String, dynamic>>.from(data['items'] ?? []));
          }
          isLoading = false;
          isLoadingMore = false;
        });
      } else if (response.statusCode == 401) {
        _handle401Error();
      } else {
        _showError('فشل في تحميل الإشعارات: ${response.statusCode}');
      }
    } catch (e) {
      if (e.toString().contains('انتهت جلسة المستخدم')) {
        _handle401Error();
        return;
      }
      _showError('حدث خطأ في تحميل الإشعارات: $e');
    } finally {
      setState(() {
        isLoading = false;
        isLoadingMore = false;
      });
    }
  }

  Future<void> _loadMoreNotifications() async {
    if (isLoadingMore || notifications.length >= totalCount) return;

    setState(() {
      isLoadingMore = true;
      currentPage++;
    });

    await _loadNotifications();
  }

  void _handle401Error() {
    AuthErrorHandler.handle401Error(context);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays > 0) {
        return 'منذ ${diff.inDays} ${diff.inDays == 1 ? 'يوم' : 'أيام'}';
      } else if (diff.inHours > 0) {
        return 'منذ ${diff.inHours} ${diff.inHours == 1 ? 'ساعة' : 'ساعات'}';
      } else if (diff.inMinutes > 0) {
        return 'منذ ${diff.inMinutes} ${diff.inMinutes == 1 ? 'دقيقة' : 'دقائق'}';
      } else {
        return 'الآن';
      }
    } catch (e) {
      return DateFormat('yyyy/MM/dd HH:mm')
          .format(DateTime.tryParse(dateStr) ?? DateTime.now());
    }
  }

  String _getNotificationTitle(Map<String, dynamic> notification) {
    final self = notification['self'];
    if (self != null && self['displayValue'] != null) {
      return self['displayValue'].toString();
    }

    final description = notification['description']?.toString() ?? '';
    if (description.contains('password')) {
      return 'تم تحديث كلمة المرور';
    } else if (description.contains('Service request')) {
      return 'طلب خدمة';
    } else if (description.contains('wallet') ||
        description.contains('debited')) {
      return 'خصم من المحفظة';
    } else if (description.contains('approved')) {
      return 'تم الموافقة';
    }

    return 'إشعار';
  }

  IconData _getNotificationIcon(Map<String, dynamic> notification) {
    final description = notification['description']?.toString() ?? '';
    final title = _getNotificationTitle(notification).toLowerCase();

    if (description.contains('password') || title.contains('password')) {
      return Icons.lock;
    } else if (description.contains('Service request') ||
        description.contains('approved')) {
      return Icons.check_circle;
    } else if (description.contains('wallet') ||
        description.contains('debited')) {
      return Icons.account_balance_wallet;
    } else if (description.contains('updated')) {
      return Icons.update;
    }

    return Icons.notifications;
  }

  Color _getNotificationColor(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] ?? false;
    if (!isRead) {
      return const Color(0xFF1976D2);
    }

    final description = notification['description']?.toString() ?? '';
    if (description.contains('approved')) {
      return Colors.green;
    } else if (description.contains('debited')) {
      return Colors.orange;
    } else if (description.contains('password')) {
      return Colors.purple;
    }

    return Colors.grey;
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'POST',
        'https://admin.ftth.iq/api/notifications/$notificationId/mark-as-read',
      );

      if (response.statusCode == 200) {
        setState(() {
          final index = notifications
              .indexWhere((n) => n['self']['id'] == notificationId);
          if (index != -1) {
            notifications[index]['isRead'] = true;
            notifications[index]['readAt'] = DateTime.now().toIso8601String();
          }
        });
      }
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] ?? false;
    final description = notification['description'] ?? '';
    final createdAt = notification['createdAt'];
    final title = _getNotificationTitle(notification);
    final icon = _getNotificationIcon(notification);
    final color = _getNotificationColor(notification);
    final notificationId = notification['self']?['id'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: isRead ? 1 : 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!isRead && notificationId != null) {
            _markAsRead(notificationId);
          }
          _showNotificationDetails(notification);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isRead ? Colors.transparent : color.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    isRead ? FontWeight.w500 : FontWeight.bold,
                                color: isRead ? Colors.black87 : Colors.black,
                              ),
                            ),
                          ),
                          if (!isRead)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 14,
                          color: isRead ? Colors.grey[600] : Colors.black87,
                          height: 1.4,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(createdAt),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                _getNotificationIcon(notification),
                color: _getNotificationColor(notification),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'تفاصيل الإشعار',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                      'العنوان', _getNotificationTitle(notification)),
                  _buildDetailRow(
                      'الوصف', notification['description'] ?? 'غير متوفر'),
                  _buildDetailRow(
                      'تاريخ الإنشاء',
                      DateFormat('yyyy/MM/dd HH:mm').format(
                          DateTime.tryParse(notification['createdAt'] ?? '') ??
                              DateTime.now())),
                  _buildDetailRow(
                      'الحالة',
                      (notification['isRead'] ?? false)
                          ? 'مقروء'
                          : 'غير مقروء'),
                  if (notification['readAt'] != null)
                    _buildDetailRow(
                        'تاريخ القراءة',
                        DateFormat('yyyy/MM/dd HH:mm').format(
                            DateTime.tryParse(notification['readAt']) ??
                                DateTime.now())),
                  if (notification['templateId'] != null)
                    _buildDetailRow('معرف القالب', notification['templateId']),
                  if (notification['self']?['id'] != null)
                    _buildDetailRow('معرف الإشعار', notification['self']['id']),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final detailsText = _buildNotificationDetailsText(notification);
                await Clipboard.setData(ClipboardData(text: detailsText));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ تفاصيل الإشعار'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: const Text('نسخ التفاصيل'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text(
                'إغلاق',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C3E50),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildNotificationDetailsText(Map<String, dynamic> notification) {
    final details = StringBuffer();
    details.writeln('تفاصيل الإشعار:');
    details.writeln('================');
    details.writeln('العنوان: ${_getNotificationTitle(notification)}');
    details.writeln('الوصف: ${notification['description'] ?? 'غير متوفر'}');
    details.writeln(
        'تاريخ الإنشاء: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.tryParse(notification['createdAt'] ?? '') ?? DateTime.now())}');
    details.writeln(
        'الحالة: ${(notification['isRead'] ?? false) ? 'مقروء' : 'غير مقروء'}');

    if (notification['readAt'] != null) {
      details.writeln(
          'تاريخ القراءة: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.tryParse(notification['readAt']) ?? DateTime.now())}');
    }

    if (notification['templateId'] != null) {
      details.writeln('معرف القالب: ${notification['templateId']}');
    }

    if (notification['self']?['id'] != null) {
      details.writeln('معرف الإشعار: ${notification['self']['id']}');
    }

    return details.toString();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'الإشعارات',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1A237E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (String value) {
              setState(() {
                showUnreadOnly = value == 'unread';
              });
              _loadNotifications(isRefresh: true);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'all',
                child: Row(
                  children: [
                    Icon(
                      showUnreadOnly
                          ? Icons.radio_button_unchecked
                          : Icons.radio_button_checked,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('جميع الإشعارات'),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'unread',
                child: Row(
                  children: [
                    Icon(
                      showUnreadOnly
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('غير المقروءة فقط'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => _loadNotifications(isRefresh: true),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1A237E),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_active,
                      color: Colors.white,
                      size: isTablet ? 28 : 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        showUnreadOnly
                            ? 'الإشعارات غير المقروءة'
                            : 'جميع الإشعارات',
                        style: TextStyle(
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'إجمالي الإشعارات: $totalCount',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: Color(0xFF1A237E),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'جاري تحميل الإشعارات...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF2C3E50),
                          ),
                        ),
                      ],
                    ),
                  )
                : notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              showUnreadOnly
                                  ? Icons.notifications_off
                                  : Icons.notifications_none,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              showUnreadOnly
                                  ? 'لا توجد إشعارات غير مقروءة'
                                  : 'لا توجد إشعارات',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              showUnreadOnly
                                  ? 'تم قراءة جميع الإشعارات'
                                  : 'لا يوجد أي إشعارات متاحة',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadNotifications(isRefresh: true),
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount:
                              notifications.length + (isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == notifications.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Color(0xFF1A237E),
                                  ),
                                ),
                              );
                            }
                            return _buildNotificationCard(notifications[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
