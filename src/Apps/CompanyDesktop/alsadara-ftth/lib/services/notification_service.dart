import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:local_notifier/local_notifier.dart';
import '../models/task.dart';
import 'firebase_availability.dart';
import '../pages/chat/chat_conversation_page.dart';
import '../widgets/window_close_handler_fixed.dart' show navigatorKey;
import 'chat_service.dart';
import 'in_app_notification_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static FirebaseMessaging get _messaging => FirebaseMessaging.instance;

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

  static const AndroidNotificationChannel _chatChannel =
      AndroidNotificationChannel(
    'chat_channel',
    'المحادثات',
    description: 'إشعارات الرسائل والمحادثات الداخلية',
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
      debugPrint('🔥 خطأ في معالج خلفية FCM');
    }
  }

  static bool _windowsNotificationsReady = false;

  /// تهيئة خدمة الإشعارات
  static Future<void> initialize() async {
    try {
      if (Platform.isWindows) {
        // Windows: استخدام local_notifier بدلاً من flutter_local_notifications
        await _initializeWindowsNotifications();
      } else {
        // Android/iOS: الإشعارات المحلية + القناة
        await _initializeLocalNotifications();
      }
      // تهيئة FCM (Android/iOS فقط)
      await _initializeFirebaseMessaging();
      print('✅ تم تهيئة الإشعارات (محلية + FCM)');
    } catch (e) {
      print('❌ خطأ في تهيئة الإشعارات: $e');
      // محاولة ثانية للإشعارات المحلية فقط
      try {
        if (Platform.isWindows) {
          await _initializeWindowsNotifications();
        } else {
          await _initializeLocalNotifications();
        }
      } catch (localError) {
        print('❌ خطأ في تهيئة الإشعارات المحلية: $localError');
      }
    }
  }

  /// تهيئة إشعارات Windows عبر local_notifier
  static Future<void> _initializeWindowsNotifications() async {
    try {
      await localNotifier.setup(
        appName: 'الصدارة FTTH',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      _windowsNotificationsReady = true;
      debugPrint('✅ [Windows] تم تهيئة إشعارات Windows بنجاح');
    } catch (e) {
      debugPrint('❌ [Windows] خطأ في تهيئة إشعارات Windows: $e');
    }
  }

  /// عرض إشعار Windows عبر local_notifier
  static Future<void> _showWindowsNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_windowsNotificationsReady) {
      debugPrint('⚠️ [Windows] إشعارات Windows غير مُهيّأة');
      return;
    }
    try {
      final notification = LocalNotification(
        title: title,
        body: body,
      );
      notification.onClick = () {
        if (payload != null) {
          try {
            final data = jsonDecode(payload) as Map<String, dynamic>;
            _handleNotificationNavigation(data);
          } catch (_) {}
        }
      };
      await notification.show();
    } catch (e) {
      debugPrint('⚠️ [Windows] خطأ في عرض إشعار Windows: $e');
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
    _localNotificationsReady = true;

    // إنشاء القناة (أندرويد فقط)
    final androidImpl = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(_mainChannel);
      await androidImpl.createNotificationChannel(_chatChannel);
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
    if (!FirebaseAvailability.isAvailable) {
      debugPrint('⚠️ Firebase غير متاح - تخطي تهيئة FCM');
      return;
    }
    // طلب الصلاحيات (iOS + Android 13+)
    final settings = await _messaging.requestPermission(
        alert: true, badge: true, sound: true, provisional: false);
    debugPrint('🔐 FCM permission: ${settings.authorizationStatus}');

    // الحصول على التوكن
    try {
      _fcmToken = await _messaging.getToken();
      debugPrint('📨 FCM Token: $_fcmToken');
    } catch (e) {
      debugPrint('⚠️ فشل الحصول على FCM token');
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
      // بانر داخل التطبيق
      final data = message.data;
      final notif = message.notification;
      final fcmTitle = notif?.title ?? data['title'] ?? 'إشعار جديد';
      final fcmBody = notif?.body ?? data['body'] ?? '';
      final fcmType = data['type']?.toString() ?? '';
      InAppNotificationType bannerType;
      if (fcmType.contains('task') || fcmType.contains('status')) {
        bannerType = InAppNotificationType.task;
      } else if (fcmType.contains('chat') || fcmType.contains('message')) {
        bannerType = InAppNotificationType.chat;
      } else if (fcmType.contains('agent')) {
        bannerType = InAppNotificationType.agent;
      } else if (fcmType.contains('citizen')) {
        bannerType = InAppNotificationType.citizen;
      } else {
        bannerType = InAppNotificationType.system;
      }
      InAppNotificationService.instance.show(
        title: fcmTitle,
        body: fcmBody,
        type: bannerType,
        referenceId: data['requestId']?.toString() ?? data['ticketId']?.toString(),
      );
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

  static bool _localNotificationsReady = false;

  /// عرض إشعار محلي عام (يدعم Windows + Android + iOS)
  static Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int? id,
  }) async {
    // Windows: استخدام local_notifier
    if (Platform.isWindows) {
      await _showWindowsNotification(title: title, body: body, payload: payload);
      return;
    }

    // Android/iOS: استخدام flutter_local_notifications
    if (!_localNotificationsReady) {
      debugPrint(
          '⚠️ [Notification] Local notifications not initialized, skipping');
      return;
    }

    try {
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
    } catch (e) {
      debugPrint('⚠️ [Notification] Error showing local notification: $e');
    }
  }

  /// إشعار محادثة داخلية مع إمكانية الرد المباشر (Android)
  static Future<void> showChatNotification({
    required String title,
    required String body,
    required String roomId,
    String? messageId,
  }) async {
    // Windows: استخدام إشعار عادي
    if (Platform.isWindows) {
      await _showWindowsNotification(
        title: title,
        body: body,
        payload: jsonEncode({
          'type': 'chat_message',
          'roomId': roomId,
          if (messageId != null) 'messageId': messageId,
        }),
      );
      return;
    }

    if (!_localNotificationsReady) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        'chat_channel',
        'المحادثات',
        channelDescription: 'إشعارات الرسائل والمحادثات الداخلية',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        playSound: true,
        icon: '@mipmap/ic_launcher',
        category: AndroidNotificationCategory.message,
        styleInformation: const BigTextStyleInformation(''),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'reply_$roomId',
            'رد',
            inputs: <AndroidNotificationActionInput>[
              const AndroidNotificationActionInput(label: 'اكتب رداً...'),
            ],
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            'open_$roomId',
            'فتح',
            showsUserInterface: true,
          ),
        ],
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
        payload: jsonEncode({
          'type': 'chat_message',
          'roomId': roomId,
          if (messageId != null) 'messageId': messageId,
        }),
      );
    } catch (e) {
      debugPrint('⚠️ [Notification] Chat notification error: $e');
    }
  }

  /// معالجة الرد من الإشعار
  static Future<void> handleNotificationReply(
      String actionId, String? inputText) async {
    if (inputText == null || inputText.isEmpty) return;

    if (actionId.startsWith('reply_')) {
      final roomId = actionId.substring(6);
      if (roomId.isEmpty) return;

      try {
        await ChatService.instance.sendMessage(
          roomId: roomId,
          content: inputText,
          messageType: 0,
        );
        debugPrint('✅ تم إرسال الرد من الإشعار: $inputText');
      } catch (e) {
        debugPrint('❌ فشل إرسال الرد من الإشعار: $e');
      }
    }
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

    // Push notifications تُرسل من السيرفر عبر FcmNotificationService
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
  }

  // ملاحظة: إرسال Push Notifications يتم من السيرفر (Backend) عبر FcmNotificationService
  // تسجيل FCM Token يتم عبر FcmTokenService في Flutter

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
    // معالجة الرد من الإشعار (Android inline reply)
    final actionId = response.actionId;
    if (actionId != null && actionId.startsWith('reply_')) {
      final inputText = response.input;
      handleNotificationReply(actionId, inputText);
      return;
    }

    if (response.payload != null) {
      try {
        Map<String, dynamic> data = jsonDecode(response.payload!);
        _handleNotificationNavigation(data);
      } catch (e) {
        print('Error parsing notification payload');
      }
    }
  }

  /// معالجة بيانات الإشعار — فتح الصفحة المناسبة
  static void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    debugPrint('🔗 فتح إشعار نوعه: $type => data=$data');

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (type) {
      case 'chat_message':
      case 'chat_mention':
        final roomId = data['roomId']?.toString();
        if (roomId == null || roomId.isEmpty) return;
        nav.push(MaterialPageRoute(
          builder: (_) => ChatConversationPage(
            roomId: roomId,
            roomName: data['roomName']?.toString() ?? 'محادثة',
            roomType: int.tryParse(data['roomType']?.toString() ?? '0') ?? 0,
          ),
        ));
        break;
      default:
        debugPrint('📌 نوع إشعار غير معروف: $type');
    }
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
      debugPrint('❌ فشل تحويل رسالة FCM لإشعار محلي');
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
