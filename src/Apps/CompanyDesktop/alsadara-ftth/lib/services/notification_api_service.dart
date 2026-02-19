import '../services/api_service.dart';

/// خدمة الإشعارات - جلب وإدارة الإشعارات من API
class NotificationApiService {
  static NotificationApiService? _instance;
  static NotificationApiService get instance =>
      _instance ??= NotificationApiService._internal();
  NotificationApiService._internal();

  final ApiService _api = ApiService.instance;

  /// جلب إشعاراتي
  Future<Map<String, dynamic>> getMyNotifications({
    int page = 1,
    int pageSize = 20,
    bool? unreadOnly,
  }) async {
    String query = '/notifications/me?page=$page&pageSize=$pageSize';
    if (unreadOnly == true) query += '&unreadOnly=true';
    return await _api.get(query);
  }

  /// عدد الإشعارات غير المقروءة
  Future<Map<String, dynamic>> getUnreadCount() async {
    return await _api.get('/notifications/me/unread-count');
  }

  /// تحديد إشعار كمقروء
  Future<Map<String, dynamic>> markAsRead(int notificationId) async {
    return await _api.patch('/notifications/$notificationId/read');
  }

  /// تحديد جميع الإشعارات كمقروءة
  Future<Map<String, dynamic>> markAllAsRead() async {
    return await _api.patch('/notifications/read-all/${_getCurrentUserId()}');
  }

  String _getCurrentUserId() {
    // سيتم استخدامه من خلال الـ token المخزن
    return '';
  }
}
