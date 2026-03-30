import 'dart:async';
import 'api/api_client.dart';
import '../models/whatsapp_conversation.dart';

/// خدمة إدارة محادثات WhatsApp — تستخدم PostgreSQL عبر API بدلاً من Firestore
class WhatsAppConversationService {
  // ── إعدادات Polling ──
  static const _conversationPollInterval = Duration(seconds: 4);
  static const _messagePollInterval = Duration(seconds: 3);

  // ── كاش ──
  static List<WhatsAppConversation>? _cachedConversations;
  static DateTime? _lastConversationFetch;

  // ── StreamControllers نشطة ──
  static StreamController<List<WhatsAppConversation>>? _conversationsController;
  static Timer? _conversationsTimer;
  static int _conversationsListeners = 0;

  static final Map<String, StreamController<List<WhatsAppMessage>>>
      _messageControllers = {};
  static final Map<String, Timer?> _messageTimers = {};

  static StreamController<int>? _unreadController;
  static Timer? _unreadTimer;
  static int _unreadListeners = 0;

  // ══════════════════════════════════════
  // getConversations() -> Stream
  // ══════════════════════════════════════

  /// الحصول على المحادثات — يرجع الكاش فوراً ثم يحدث عبر polling
  static Stream<List<WhatsAppConversation>> getConversations() {
    _conversationsListeners++;
    if (_conversationsController == null || _conversationsController!.isClosed) {
      _conversationsController =
          StreamController<List<WhatsAppConversation>>.broadcast(
        onCancel: _onConversationsCancel,
      );
    }

    // إرسال الكاش فوراً إن وُجد
    if (_cachedConversations != null) {
      Future.microtask(
          () => _conversationsController?.add(_cachedConversations!));
    }

    // بدء الـ polling إذا لم يكن يعمل
    if (_conversationsTimer == null) {
      _fetchConversations(); // fetch فوري
      _conversationsTimer = Timer.periodic(
          _conversationPollInterval, (_) => _fetchConversations());
    }

    return _conversationsController!.stream;
  }

  static void _onConversationsCancel() {
    _conversationsListeners--;
    if (_conversationsListeners <= 0) {
      _conversationsTimer?.cancel();
      _conversationsTimer = null;
      _conversationsController?.close();
      _conversationsController = null;
      _conversationsListeners = 0;
    }
  }

  static Future<void> _fetchConversations() async {
    try {
      final url = _lastConversationFetch != null
          ? '/whatsapp/conversations?limit=200&updatedSince=${_lastConversationFetch!.toUtc().toIso8601String()}'
          : '/whatsapp/conversations?limit=200';

      final response = await ApiClient.instance.get(
        url,
        (data) => data,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        // ApiClient يمرر body['data'] مباشرة عند success
        // فقد يكون List أو Map حسب الاستجابة
        final rawData = response.data;
        final serverData = rawData is List
            ? rawData
            : (rawData is Map ? (rawData['data'] as List?) ?? [] : []);

        if (_lastConversationFetch != null && _cachedConversations != null) {
          // تحديث تدريجي: دمج التغييرات الجديدة في الكاش
          final updatedMap = {
            for (var c in _cachedConversations!) c.phoneNumber: c
          };
          for (var json in serverData) {
            final conv = WhatsAppConversation.fromJson(
                json is Map<String, dynamic> ? json : {});
            updatedMap[conv.phoneNumber] = conv;
          }
          _cachedConversations = updatedMap.values.toList()
            ..sort(
                (a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
        } else {
          // أول fetch — تحميل كامل
          _cachedConversations = serverData
              .map((json) => WhatsAppConversation.fromJson(
                  json is Map<String, dynamic> ? json : {}))
              .toList();
        }

        _lastConversationFetch = DateTime.now().toUtc();
        _conversationsController?.add(_cachedConversations!);

        // تحديث عدد غير المقروءة
        _updateUnreadFromCache();
      }
    } catch (e) {
      // عند الخطأ — إرسال الكاش الموجود
      if (_cachedConversations != null) {
        _conversationsController?.add(_cachedConversations!);
      }
    }
  }

  /// مسح الكاش
  static void invalidateCache() {
    _cachedConversations = null;
    _lastConversationFetch = null;
  }

  // ══════════════════════════════════════
  // getMessages(phone) -> Stream
  // ══════════════════════════════════════

  /// الحصول على رسائل محادثة معينة
  static Stream<List<WhatsAppMessage>> getMessages(String phoneNumber) {
    if (!_messageControllers.containsKey(phoneNumber) ||
        _messageControllers[phoneNumber]!.isClosed) {
      _messageControllers[phoneNumber] =
          StreamController<List<WhatsAppMessage>>.broadcast(
        onCancel: () {
          _messageTimers[phoneNumber]?.cancel();
          _messageTimers.remove(phoneNumber);
          _messageControllers[phoneNumber]?.close();
          _messageControllers.remove(phoneNumber);
        },
      );

      // بدء الـ polling
      _fetchMessages(phoneNumber);
      _messageTimers[phoneNumber] = Timer.periodic(
          _messagePollInterval, (_) => _fetchMessages(phoneNumber));
    }

    return _messageControllers[phoneNumber]!.stream;
  }

  static Future<void> _fetchMessages(String phoneNumber) async {
    try {
      final response = await ApiClient.instance.get(
        '/whatsapp/conversations/$phoneNumber/messages?limit=200',
        (data) => data,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final rawData = response.data;
        final serverData = rawData is List
            ? rawData
            : (rawData is Map ? (rawData['data'] as List?) ?? [] : []);
        final messages = serverData
            .map((json) => WhatsAppMessage.fromJson(
                json is Map<String, dynamic> ? json : {}))
            .toList();
        _messageControllers[phoneNumber]?.add(messages);
      }
    } catch (e) {
      // صامت — لا داعي لإزعاج المستخدم
    }
  }

  // ══════════════════════════════════════
  // getUnreadCount() -> Stream<int>
  // ══════════════════════════════════════

  /// عدد الرسائل غير المقروءة
  static Stream<int> getUnreadCount() {
    _unreadListeners++;
    if (_unreadController == null || _unreadController!.isClosed) {
      _unreadController = StreamController<int>.broadcast(
        onCancel: _onUnreadCancel,
      );
    }

    // بدء الـ polling
    if (_unreadTimer == null) {
      _fetchUnreadCount();
      _unreadTimer = Timer.periodic(
          _conversationPollInterval, (_) => _fetchUnreadCount());
    }

    return _unreadController!.stream;
  }

  static void _onUnreadCancel() {
    _unreadListeners--;
    if (_unreadListeners <= 0) {
      _unreadTimer?.cancel();
      _unreadTimer = null;
      _unreadController?.close();
      _unreadController = null;
      _unreadListeners = 0;
    }
  }

  static Future<void> _fetchUnreadCount() async {
    try {
      final response = await ApiClient.instance.get(
        '/whatsapp/unread-count',
        (data) => data,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final rawData = response.data;
        int count = 0;
        if (rawData is Map) {
          count = rawData['unreadCount'] ?? rawData['data']?['unreadCount'] ?? 0;
        }
        _unreadController?.add(count);
      }
    } catch (e) {
      // fallback: حساب من الكاش
      _updateUnreadFromCache();
    }
  }

  static void _updateUnreadFromCache() {
    if (_cachedConversations != null &&
        _unreadController != null &&
        !_unreadController!.isClosed) {
      final total =
          _cachedConversations!.fold<int>(0, (sum, c) => sum + c.unreadCount);
      _unreadController?.add(total);
    }
  }

  // ══════════════════════════════════════
  // sendMessage() — POST إلى API
  // ══════════════════════════════════════

  /// إرسال رسالة (حفظها في PostgreSQL)
  static Future<void> sendMessage({
    required String phoneNumber,
    required String message,
    String type = 'text',
  }) async {
    try {
      await ApiClient.instance.post(
        '/whatsapp/conversations/$phoneNumber/messages',
        {'message': message, 'type': type},
        (data) => data,
        useInternalKey: true,
      );

      // تحديث فوري للمحادثات
      _lastConversationFetch = null;
      _fetchConversations();
      _fetchMessages(phoneNumber);
    } catch (e) {
      print('❌ خطأ في حفظ الرسالة: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════
  // markAsRead()
  // ══════════════════════════════════════

  /// تحديث حالة قراءة المحادثة
  static Future<void> markAsRead(String phoneNumber) async {
    // تحديث محلي فوري (optimistic)
    if (_cachedConversations != null) {
      final idx = _cachedConversations!
          .indexWhere((c) => c.phoneNumber == phoneNumber);
      if (idx >= 0) {
        final old = _cachedConversations![idx];
        _cachedConversations![idx] = WhatsAppConversation(
          phoneNumber: old.phoneNumber,
          userName: old.userName,
          lastMessage: old.lastMessage,
          lastMessageTime: old.lastMessageTime,
          lastMessageType: old.lastMessageType,
          unreadCount: 0,
          isIncoming: old.isIncoming,
          updatedAt: old.updatedAt,
        );
        _conversationsController?.add(_cachedConversations!);
        _updateUnreadFromCache();
      }
    }

    try {
      await ApiClient.instance.put(
        '/whatsapp/conversations/$phoneNumber/read',
        {},
        (data) => data,
        useInternalKey: true,
      );
    } catch (e) {
      // صامت
    }
  }

  // ══════════════════════════════════════
  // deleteConversation()
  // ══════════════════════════════════════

  /// حذف محادثة
  static Future<void> deleteConversation(String phoneNumber) async {
    try {
      await ApiClient.instance.delete(
        '/whatsapp/conversations/$phoneNumber',
        (data) => data,
        useInternalKey: true,
      );

      // إزالة من الكاش فوراً
      _cachedConversations
          ?.removeWhere((c) => c.phoneNumber == phoneNumber);
      _conversationsController?.add(_cachedConversations ?? []);
      _updateUnreadFromCache();
    } catch (e) {
      print('❌ خطأ في حذف المحادثة: $e');
      rethrow;
    }
  }

  // ══════════════════════════════════════
  // searchConversations() — بحث محلي في الكاش
  // ══════════════════════════════════════

  /// البحث في المحادثات
  static Future<List<WhatsAppConversation>> searchConversations(
      String query) async {
    if (_cachedConversations != null) {
      return _cachedConversations!
          .where((conv) =>
              conv.phoneNumber.contains(query) ||
              (conv.userName?.toLowerCase().contains(query.toLowerCase()) ??
                  false) ||
              conv.lastMessage.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    return [];
  }

  // ══════════════════════════════════════
  // دوال التنظيف والمزامنة
  // ══════════════════════════════════════

  /// حذف المحادثات القديمة — تتم على السيرفر
  static Future<Map<String, int>> cleanupOldConversations(
      {int days = 3}) async {
    invalidateCache();
    return {'conversations': 0, 'messages': 0};
  }

  /// مسح cache محلي
  static Future<void> clearLocalCache() async {
    invalidateCache();
  }

  /// لم تعد ضرورية — n8n يرسل للـ API مباشرة
  static void startIncomingMessagesListener() {}
  static Future<void> syncNamesFromMessages() async {}
  static Future<void> syncConversationsFromMessages() async {}

  /// حفظ رسالة واردة (للتوافق — تُستخدم لو احتجنا الاستدعاء من الكود مباشرة)
  static Future<void> saveIncomingMessage({
    required String messageId,
    required String phoneNumber,
    required String message,
    required int timestamp,
    String? contactName,
    String type = 'text',
  }) async {
    try {
      await ApiClient.instance.post(
        '/whatsapp/webhook/incoming',
        {
          'messageId': messageId,
          'phoneNumber': phoneNumber,
          'text': message,
          'messageType': type,
          'contactName': contactName,
          'timestamp': timestamp,
        },
        (data) => data,
        useInternalKey: true,
      );

      // تحديث فوري
      _lastConversationFetch = null;
      _fetchConversations();
    } catch (e) {
      print('❌ خطأ في حفظ الرسالة الواردة: $e');
    }
  }

  /// تحرير الموارد
  static void dispose() {
    _conversationsTimer?.cancel();
    _conversationsTimer = null;
    _conversationsController?.close();
    _conversationsController = null;
    _conversationsListeners = 0;

    _unreadTimer?.cancel();
    _unreadTimer = null;
    _unreadController?.close();
    _unreadController = null;
    _unreadListeners = 0;

    for (final timer in _messageTimers.values) {
      timer?.cancel();
    }
    for (final controller in _messageControllers.values) {
      if (!controller.isClosed) controller.close();
    }
    _messageTimers.clear();
    _messageControllers.clear();

    _cachedConversations = null;
    _lastConversationFetch = null;
  }
}
