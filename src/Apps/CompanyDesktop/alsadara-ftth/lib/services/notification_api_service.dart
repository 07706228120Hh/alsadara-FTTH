import '../services/api_service.dart';

/// خدمة الإشعارات - جلب وإدارة الإشعارات من API
class NotificationApiService {
  static NotificationApiService? _instance;
  static NotificationApiService get instance =>
      _instance ??= NotificationApiService._internal();
  NotificationApiService._internal();

  final ApiService _api = ApiService.instance;

  /// جلب إشعاراتي
  ///
  /// ملاحظة: مسارات `/notifications/me*` غير موجودة على backend admin.ftth.iq
  /// (تُرجع 404). نستخدم نفس مسار موقع المزوّد: `/notifications?...` الذي يُعيد
  /// `{totalCount, items}`، ونُعيد `items` كقائمة ليتوافق مع المستدعين.
  Future<Map<String, dynamic>> getMyNotifications({
    int page = 1,
    int pageSize = 20,
    bool? unreadOnly,
  }) async {
    String query = '/notifications?pageNumber=$page&pageSize=$pageSize';
    if (unreadOnly == true) query += '&onlyUnreadNotifications=true';
    final res = await _api.get(query);
    if (res['success'] == true) {
      final data = res['data'];
      final items = (data is Map && data['items'] is List)
          ? data['items']
          : (data is List ? data : <dynamic>[]);
      return {'success': true, 'data': items};
    }
    return {'success': false, 'data': <dynamic>[]};
  }

  /// عدد الإشعارات غير المقروءة (totalCount من مسار الإشعارات غير المقروءة)
  Future<Map<String, dynamic>> getUnreadCount() async {
    final res = await _api
        .get('/notifications?onlyUnreadNotifications=true&pageSize=1&pageNumber=1');
    if (res['success'] == true) {
      final data = res['data'];
      final total = (data is Map ? data['totalCount'] : null) ?? 0;
      final count = total is int ? total : (int.tryParse('$total') ?? 0);
      return {'success': true, 'data': count};
    }
    return {'success': false, 'data': 0};
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
