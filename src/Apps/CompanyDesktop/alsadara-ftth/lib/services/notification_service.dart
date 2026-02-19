import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/task.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static String? _fcmToken; // آخر توكن FCM

  // معرف قناة أندرويد ثابت
  static const AndroidNotificationChannel _mainChannel =
      AndroidNotificationChannel(
    'tasks_channel',
    'إشعارات المهام',
    description: 'إشعارات خاصة بالمهام والتحديثات',
    importance: Importance.high,
    showBadge: true,
  );

  /// معالج رسائل الخلفية (يجب أن يكون top-level لكن نبقي التعريف هنا ونمرره في main عند الحاجة)
  @pragma('vm:entry-point')
  static Future<void> firebaseMessagingBackgroundHandler(
      RemoteMessage message) async {
    // ملاحظة: Firebase.initializeApp() تم في main
    try {
      await _showRemoteAsLocal(message, fromBackground: true);
    } catch (e) {
      debugPrint('🔥 خطأ في معالج خلفية FCM: $e');
    }
  }

  /// تهيئة خدمة الإشعارات
  static Future<void> initialize() async {
    try {
      // تهيئة الإشعارات المحلية + القناة
      await _initializeLocalNotifications();
      // تهيئة FCM
      await _initializeFirebaseMessaging();
      print('✅ تم تهيئة الإشعارات (محلية + FCM)');
    } catch (e) {
      print('❌ خطأ في تهيئة الإشعارات: $e');
      // الاستمرار حتى لو فشلت التهيئة
      try {
        await _initializeLocalNotifications();
      } catch (localError) {
        print('❌ خطأ في تهيئة الإشعارات المحلية: $localError');
      }
    }
  }

  /// تهيئة الإشعارات المحلية
  static Future<void> _initializeLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // إنشاء القناة (أندرويد فقط)
    final androidImpl = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(_mainChannel);
      await androidImpl.requestNotificationsPermission();
    }

    // طلب الصلاحيات للأندرويد 13+
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }
  }

  /// تهيئة FCM: صلاحيات + توكن + مستمعين
  static Future<void> _initializeFirebaseMessaging() async {
    // طلب الصلاحيات (iOS + Android 13+)
    final settings = await _messaging.requestPermission(
        alert: true, badge: true, sound: true, provisional: false);
    debugPrint('🔐 FCM permission: ${settings.authorizationStatus}');

    // الحصول على التوكن
    try {
      _fcmToken = await _messaging.getToken();
      debugPrint('📨 FCM Token: $_fcmToken');
    } catch (e) {
      debugPrint('⚠️ فشل الحصول على FCM token: $e');
    }

    // الاستماع لتحديث التوكن
    _messaging.onTokenRefresh.listen((t) {
      _fcmToken = t;
      debugPrint('♻️ تم تحديث FCM Token: $t');
    });

    // foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('📩 رسالة FCM في الـ foreground: ${message.messageId}');
      await _showRemoteAsLocal(message);
    });

    // عند فتح من الإشعار (terminated -> opened)
    final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMsg != null) {
      _handleNotificationNavigation(initialMsg.data);
    }

    // عند فتح من الخلفية
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage m) {
      _handleNotificationNavigation(m.data);
    });
  }

  /// عرض إشعار محلي عام
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int? id,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'tasks_channel',
      'إشعارات المهام',
      channelDescription: 'إشعارات خاصة بالمهام والتحديثات',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// إشعار عند إضافة مهمة جديدة
  static Future<void> notifyNewTask({
    required Task task,
    required String assignedTo,
    required List<String> notifyUsers,
  }) async {
    // تحضير نص الإشعار مع رقم هاتف الفني
    String notificationBody =
        'تم إضافة مهمة جديدة: ${task.title}\nمكلف بها: $assignedTo';
    if (task.technicianPhone.isNotEmpty) {
      notificationBody += '\nهاتف الفني: ${task.technicianPhone}';
    }

    // إشعار محلي
    await showLocalNotification(
      title: '🆕 مهمة جديدة',
      body: notificationBody,
      payload: jsonEncode({
        'type': 'new_task',
        'taskId': task.id,
        'assignedTo': assignedTo,
        'technicianPhone': task.technicianPhone,
      }),
    );

    // إرسال إشعارات مدفوعة للمستخدمين المحددين
    for (String userId in notifyUsers) {
      await _sendPushNotificationToUser(
        userId: userId,
        title: '🆕 مهمة جديدة',
        body: notificationBody,
        data: {
          'type': 'new_task',
          'taskId': task.id,
          'assignedTo': assignedTo,
          'department': task.department,
          'priority': task.priority,
          'technicianPhone': task.technicianPhone,
        },
      );
    }
  }

  /// إشعار عند تحديث حالة المهمة
  static Future<void> notifyTaskStatusUpdate({
    required Task task,
    required String oldStatus,
    required String newStatus,
    required List<String> notifyUsers,
  }) async {
    String statusEmoji = _getStatusEmoji(newStatus);

    // تحضير نص الإشعار مع رقم هاتف الفني
    String notificationBody =
        'المهمة: ${task.title}\nالحالة: من "$oldStatus" إلى "$newStatus"';
    if (task.technicianPhone.isNotEmpty) {
      notificationBody += '\nهاتف الفني: ${task.technicianPhone}';
    }

    await showLocalNotification(
      title: '$statusEmoji تحديث حالة المهمة',
      body: notificationBody,
      payload: jsonEncode({
        'type': 'status_update',
        'taskId': task.id,
        'oldStatus': oldStatus,
        'newStatus': newStatus,
        'technicianPhone': task.technicianPhone,
      }),
    );

    // إرسال إشعارات مدفوعة
    for (String userId in notifyUsers) {
      await _sendPushNotificationToUser(
        userId: userId,
        title: '$statusEmoji تحديث حالة المهمة',
        body: notificationBody,
        data: {
          'type': 'status_update',
          'taskId': task.id,
          'oldStatus': oldStatus,
          'newStatus': newStatus,
          'technicianPhone': task.technicianPhone,
        },
      );
    }
  }

  /// إشعار للمهام المتأخرة
  static Future<void> notifyOverdueTasks({
    required List<Task> overdueTasks,
    required List<String> notifyUsers,
  }) async {
    if (overdueTasks.isEmpty) return;

    await showLocalNotification(
      title: '⚠️ مهام متأخرة',
      body: 'لديك ${overdueTasks.length} مهام متأخرة تحتاج متابعة عاجلة',
      payload: jsonEncode({
        'type': 'overdue_tasks',
        'count': overdueTasks.length,
        'taskIds': overdueTasks.map((t) => t.id).toList(),
      }),
    );

    // إرسال إشعارات مدفوعة
    for (String userId in notifyUsers) {
      await _sendPushNotificationToUser(
        userId: userId,
        title: '⚠️ مهام متأخرة',
        body: 'يوجد ${overdueTasks.length} مهام متأخرة تحتاج متابعة',
        data: {
          'type': 'overdue_tasks',
          'count': overdueTasks.length.toString(),
        },
      );
    }
  }

  /// إرسال إشعار مدفوع لمستخدم محدد
  static Future<void> _sendPushNotificationToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // هنا يجب استبدال الـ SERVER_KEY بالمفتاح الحقيقي من Firebase
      const String serverKey = 'YOUR_FIREBASE_SERVER_KEY';

      // الحصول على FCM Token للمستخدم من قاعدة البيانات
      String? userToken = await _getUserFCMToken(userId);

      if (userToken == null) return;

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$serverKey',
        },
        body: jsonEncode({
          'to': userToken,
          'notification': {
            'title': title,
            'body': body,
            'sound': 'default',
            'badge': 1,
          },
          'data': data ?? {},
          'priority': 'high',
        }),
      );

      if (response.statusCode == 200) {
        print('Push notification sent successfully to $userId');
      } else {
        print('Failed to send push notification: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending push notification: $e');
    }
  }

  /// الحصول على FCM Token للمستخدم
  static Future<String?> _getUserFCMToken(String userId) async {
    // هذه الدالة يجب أن تجلب الـ token من قاعدة البيانات
    // يمكن تنفيذها باستخدام VPS API أو قاعدة بيانات أخرى

    // مثال مؤقت - يجب استبداله بالتنفيذ الحقيقي
    return null;
  }

  /// حفظ FCM Token للمستخدم الحالي
  static Future<void> saveFCMTokenForUser(String userId) async {
    if (_fcmToken != null) {
      // هنا يجب حفظ الـ token في قاعدة البيانات مع معرف المستخدم
      print('Saving FCM Token for user $userId: $_fcmToken');

      // يمكن إضافة الكود لحفظ الـ token في قاعدة البيانات
    }
  }

  /// الحصول على emoji حسب حالة المهمة
  static String _getStatusEmoji(String status) {
    switch (status) {
      case 'مكتملة':
        return '✅';
      case 'قيد التنفيذ':
        return '🔄';
      case 'مفتوحة':
        return '📝';
      case 'ملغية':
        return '❌';
      case 'متأخرة':
        return '⚠️';
      default:
        return '📋';
    }
  }

  /// معالجة النق�� على الإشعار
  static void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        Map<String, dynamic> data = jsonDecode(response.payload!);
        _handleNotificationNavigation(data);
      } catch (e) {
        print('Error parsing notification payload: $e');
      }
    }
  }

  /// معالجة بيانات الإشعار (تنقل أو منطق) - قابلة للتوسعة لاحقاً
  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'];
    debugPrint('🔗 فتح إشعار نوعه: $type => data=$data');
    // TODO: دمج مع Navigator عبر GlobalKey<NavigatorState> إذا توفر.
  }

  /// تحويل رسالة FCM إلى إشعار محلي
  static Future<void> _showRemoteAsLocal(RemoteMessage message,
      {bool fromBackground = false}) async {
    try {
      final data = message.data;
      final notif = message.notification;
      final title = notif?.title ?? data['title'] ?? 'إشعار جديد';
      final body = notif?.body ??
          data['body'] ??
          (data['ticketTitle'] ?? 'تم استلام تحديث');
      final payload = jsonEncode(data.isEmpty ? {'raw': true} : data);
      await showLocalNotification(title: title, body: body, payload: payload);
      debugPrint(
          '✅ تم عرض إشعار محلي (${fromBackground ? 'خلفية' : 'Foreground'})');
    } catch (e) {
      debugPrint('❌ فشل تحويل رسالة FCM لإشعار محلي: $e');
    }
  }

  /// إلغاء جميع الإشعارات
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  /// إلغاء إشعار محدد
  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  /// الحصول على FCM Token الحالي
  static String? get fcmToken => _fcmToken;
}
