import 'dart:async';

/// أنواع الإشعارات داخل التطبيق
enum InAppNotificationType {
  task,     // مهمة جديدة أو تحديث حالة
  chat,     // رسالة محادثة
  agent,    // طلب وكيل
  citizen,  // طلب مواطن
  system,   // إشعار نظام عام
}

/// نموذج إشعار داخل التطبيق
class InAppNotification {
  final String title;
  final String body;
  final InAppNotificationType type;
  final String? referenceId;
  final DateTime createdAt;
  final void Function()? onTap;

  InAppNotification({
    required this.title,
    required this.body,
    required this.type,
    this.referenceId,
    this.onTap,
  }) : createdAt = DateTime.now();
}

/// خدمة مركزية للإشعارات داخل التطبيق — singleton
/// كل المصادر (FCM, SignalR, Polling) تبث إليها
/// والـ Overlay يستمع منها
class InAppNotificationService {
  InAppNotificationService._();
  static final InAppNotificationService instance = InAppNotificationService._();

  final _controller = StreamController<InAppNotification>.broadcast();

  /// الاستماع للإشعارات
  Stream<InAppNotification> get stream => _controller.stream;

  /// بث إشعار جديد
  void show({
    required String title,
    required String body,
    required InAppNotificationType type,
    String? referenceId,
    void Function()? onTap,
  }) {
    _controller.add(InAppNotification(
      title: title,
      body: body,
      type: type,
      referenceId: referenceId,
      onTap: onTap,
    ));
  }

  void dispose() {
    _controller.close();
  }
}
