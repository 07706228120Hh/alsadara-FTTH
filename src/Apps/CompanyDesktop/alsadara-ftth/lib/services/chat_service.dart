import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'api/api_client.dart';
import 'in_app_notification_service.dart';
import 'api/api_config.dart';

/// ═══════════════════════════════════════════════════════════════
/// خدمة المحادثة — SignalR + REST API
/// ═══════════════════════════════════════════════════════════════
class ChatService {
  static ChatService? _instance;
  static ChatService get instance => _instance ??= ChatService._();
  ChatService._();

  HubConnection? _hubConnection;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // ═══ Sound ═══
  final AudioPlayer _notifPlayer = AudioPlayer();
  bool soundEnabled = true;

  // ═══ Streams ═══
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _readController = StreamController<Map<String, dynamic>>.broadcast();
  final _deletedController = StreamController<Map<String, dynamic>>.broadcast();
  final _onlineController = StreamController<Map<String, dynamic>>.broadcast();
  final _roomEventController = StreamController<Map<String, dynamic>>.broadcast();
  final _unreadCountController = StreamController<int>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  Stream<Map<String, dynamic>> get onTyping => _typingController.stream;
  Stream<Map<String, dynamic>> get onRead => _readController.stream;
  Stream<Map<String, dynamic>> get onDeleted => _deletedController.stream;
  Stream<Map<String, dynamic>> get onOnlineStatus => _onlineController.stream;
  Stream<Map<String, dynamic>> get onRoomEvent => _roomEventController.stream;
  Stream<int> get onUnreadCount => _unreadCountController.stream;

  // ═══════════════════════════════════════
  // SignalR Connection
  // ═══════════════════════════════════════

  /// الاتصال بـ ChatHub
  Future<void> connect() async {
    if (_isConnected) return;

    final token = ApiClient.instance.authToken;
    if (token == null) return;

    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    final hubUrl = '$baseUrl/hubs/chat';

    _hubConnection = HubConnectionBuilder()
        .withUrl(
          '$hubUrl?access_token=$token',
          options: HttpConnectionOptions(
            accessTokenFactory: () async => token,
          ),
        )
        .withAutomaticReconnect()
        .build();

    // تسجيل المستمعين
    _hubConnection!.on('ReceiveMessage', _onReceiveMessage);
    _hubConnection!.on('MessageRead', _onMessageRead);
    _hubConnection!.on('MessageDeleted', _onMessageDeleted);
    _hubConnection!.on('UserTyping', _onUserTyping);
    _hubConnection!.on('UserStoppedTyping', _onUserStoppedTyping);
    _hubConnection!.on('UserOnline', _onUserOnline);
    _hubConnection!.on('UserOffline', _onUserOffline);
    _hubConnection!.on('AddedToRoom', _onAddedToRoom);
    _hubConnection!.on('RemovedFromRoom', _onRemovedFromRoom);

    _hubConnection!.onclose(({error}) {
      _isConnected = false;
      if (kDebugMode) print('💬 ChatHub disconnected: $error');
    });

    _hubConnection!.onreconnected(({connectionId}) {
      _isConnected = true;
      if (kDebugMode) print('💬 ChatHub reconnected: $connectionId');
    });

    try {
      await _hubConnection!.start();
      _isConnected = true;
      if (kDebugMode) print('💬 ChatHub connected');
      // جلب عدد الغير مقروء
      refreshUnreadCount();
    } catch (e) {
      if (kDebugMode) print('❌ ChatHub connection failed: $e');
    }
  }

  /// قطع الاتصال
  Future<void> disconnect() async {
    if (_hubConnection != null) {
      await _hubConnection!.stop();
      _isConnected = false;
    }
  }

  // ═══════════════════════════════════════
  // SignalR Actions (إرسال للسيرفر)
  // ═══════════════════════════════════════

  /// إرسال رسالة (SignalR أولاً، ثم REST كـ fallback)
  Future<void> sendMessage({
    required String roomId,
    required String content,
    int messageType = 0,
    String? replyToMessageId,
    List<String>? mentionUserIds,
  }) async {
    // محاولة عبر SignalR
    if (_isConnected) {
      try {
        await _hubConnection!.invoke('SendMessage', args: <Object>[
          roomId,
          content,
          messageType,
          replyToMessageId ?? '',
          mentionUserIds ?? <String>[],
        ]);
        return;
      } catch (e) {
        if (kDebugMode) print('⚠️ SignalR send failed, falling back to REST: $e');
      }
    }

    // Fallback: إرسال عبر REST API
    if (kDebugMode) print('📮 Sending message via REST to room $roomId');
    final result = await _postRaw('/chat/rooms/$roomId/messages', {
      'content': content,
      'messageType': messageType,
      if (replyToMessageId != null && replyToMessageId.isNotEmpty) 'replyToMessageId': replyToMessageId,
      if (mentionUserIds != null && mentionUserIds.isNotEmpty) 'mentionUserIds': mentionUserIds,
    });
    // إخطار المستمعين بالرسالة الجديدة
    if (result != null) {
      _messageController.add(result);
    }
  }

  /// تحديث حالة القراءة
  Future<void> markAsRead(String roomId) async {
    if (_isConnected) {
      try {
        await _hubConnection!.invoke('MarkAsRead', args: [roomId]);
        return;
      } catch (_) {}
    }
    // REST fallback
    await _putRaw('/chat/rooms/$roomId/mark-read', {});
  }

  /// بداية الكتابة
  Future<void> startTyping(String roomId) async {
    if (!_isConnected) return;
    await _hubConnection!.invoke('StartTyping', args: [roomId]);
  }

  /// نهاية الكتابة
  Future<void> stopTyping(String roomId) async {
    if (!_isConnected) return;
    await _hubConnection!.invoke('StopTyping', args: [roomId]);
  }

  /// جلب المتصلين
  Future<List<String>> getOnlineUsers() async {
    if (!_isConnected) return [];
    final result = await _hubConnection!.invoke('GetOnlineUsers');
    if (result is List) return result.cast<String>();
    return [];
  }

  /// انضمام لغرفة جديدة
  Future<void> joinRoom(String roomId) async {
    if (!_isConnected) return;
    await _hubConnection!.invoke('JoinRoom', args: [roomId]);
  }

  // ═══════════════════════════════════════
  // REST API Methods
  // ═══════════════════════════════════════

  /// جلب غرف المحادثة
  Future<List<Map<String, dynamic>>> getRooms() async {
    return _getRawList('/chat/rooms');
  }

  /// جلب جميع محادثات الشركة (مدير فقط)
  Future<List<Map<String, dynamic>>> getAllCompanyRooms() async {
    return _getRawList('/chat/rooms/all');
  }

  /// جلب رسائل غرفة
  Future<List<Map<String, dynamic>>> getMessages(String roomId, {int page = 1, int pageSize = 50, String? before}) async {
    var endpoint = '/chat/rooms/$roomId/messages?page=$page&pageSize=$pageSize';
    if (before != null) endpoint += '&before=$before';
    return _getRawList(endpoint);
  }

  /// إنشاء غرفة
  Future<Map<String, dynamic>?> createRoomPost({
    required int type,
    String? name,
    int? departmentId,
    List<String>? memberIds,
  }) async {
    final body = {
      'type': type,
      if (name != null) 'name': name,
      if (departmentId != null) 'departmentId': departmentId,
      if (memberIds != null) 'memberIds': memberIds,
    };
    return _postRaw('/chat/rooms', body);
  }

  /// جلب أعضاء الغرفة
  Future<List<Map<String, dynamic>>> getRoomMembers(String roomId) async {
    return _getRawList('/chat/rooms/$roomId/members');
  }

  /// بطاقة الموظف
  Future<Map<String, dynamic>?> getUserProfileCard(String userId) async {
    return _getRawAsMap('/chat/users/$userId/profile-card');
  }

  /// الموظفون المتاحون
  Future<List<Map<String, dynamic>>> getAvailableUsers({String? search}) async {
    var endpoint = '/chat/available-users';
    if (search != null && search.isNotEmpty) endpoint += '?search=$search';
    return _getRawList(endpoint);
  }

  /// الأقسام المتاحة
  Future<List<Map<String, dynamic>>> getAvailableDepartments() async {
    return _getRawList('/chat/available-departments');
  }

  /// عدد الغير مقروء
  Future<int> getUnreadCount() async {
    final data = await _getRawAsMap('/chat/unread-count');
    return data?['unreadCount'] ?? 0;
  }

  /// تحديث عداد الغير مقروء
  Future<void> refreshUnreadCount() async {
    final count = await getUnreadCount();
    _unreadCountController.add(count);
  }

  /// بحث في الرسائل
  Future<List<Map<String, dynamic>>> searchMessages(String query, {int page = 1}) async {
    return _getRawList('/chat/search?q=${Uri.encodeComponent(query)}&page=$page');
  }

  /// تفاعل (Reaction) على رسالة
  Future<List<Map<String, dynamic>>> toggleReaction(String messageId, String emoji) async {
    final result = await _postRaw('/chat/messages/$messageId/reactions', {'emoji': emoji});
    if (result != null && result.containsKey('success')) return [];
    // الـ API يرجع مصفوفة
    return _getRawList('/chat/messages/$messageId/reactions');
  }

  /// حذف محادثة كاملة (مدير الشركة فقط)
  Future<bool> deleteRoom(String roomId) async {
    try {
      final token = ApiClient.instance.authToken;
      final uri = Uri.parse('${ApiConfig.baseUrl}/chat/rooms/$roomId');
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);

      final response = await client.delete(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(ApiConfig.connectionTimeout);

      if (kDebugMode) print('🗑️ DeleteRoom $roomId → ${response.statusCode}');
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      if (kDebugMode) print('❌ DeleteRoom error: $e');
      return false;
    }
  }

  /// حذف رسالة
  Future<bool> deleteMessage(String messageId) async {
    final result = await ApiClient.instance.deleteRaw('/chat/messages/$messageId');
    return result != null;
  }

  /// مغادرة المجموعة
  Future<bool> leaveRoom(String roomId) async {
    try {
      final token = ApiClient.instance.authToken;
      final uri = Uri.parse('${ApiConfig.baseUrl}/chat/rooms/$roomId/leave');
      final httpClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);
      final response = await client.post(uri, headers: {
        'Authorization': 'Bearer $token',
      }).timeout(ApiConfig.connectionTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// تعديل اسم المجموعة
  Future<bool> updateRoomName(String roomId, String name) async {
    final result = await _putRawWithResponse('/chat/rooms/$roomId/name', {'name': name});
    return result;
  }

  Future<bool> _putRawWithResponse(String endpoint, Map<String, dynamic> body) async {
    try {
      final token = ApiClient.instance.authToken;
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final httpClient = HttpClient()..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);
      final response = await client.put(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }, body: jsonEncode(body)).timeout(ApiConfig.connectionTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// تثبيت/إلغاء تثبيت محادثة
  Future<void> togglePin(String roomId, bool pinned) async {
    await _putRaw('/chat/rooms/$roomId/pin', {'pinned': pinned});
  }

  /// كتم/إلغاء كتم
  Future<void> toggleMute(String roomId, bool muted) async {
    await _putRaw('/chat/rooms/$roomId/mute', {'muted': muted});
  }

  /// رفع مرفق
  Future<Map<String, dynamic>?> uploadAttachment(String roomId, File file) async {
    try {
      final token = ApiClient.instance.authToken;
      final baseUrl = ApiConfig.baseUrl;
      final uri = Uri.parse('$baseUrl/chat/rooms/$roomId/attachments');

      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(await http.MultipartFile.fromPath('file', file.path));

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final ioClient = IOClient(httpClient);

      final streamedResponse = await ioClient.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      if (kDebugMode) print('❌ Upload attachment error: $e');
    }
    return null;
  }

  /// إضافة أعضاء
  Future<void> addMembers(String roomId, List<String> userIds) async {
    await _postRaw('/chat/rooms/$roomId/members', {'userIds': userIds});
  }

  /// إزالة عضو
  Future<void> removeMember(String roomId, String userId) async {
    await ApiClient.instance.deleteRaw('/chat/rooms/$roomId/members/$userId');
  }

  // ═══════════════════════════════════════
  // SignalR Event Handlers
  // ═══════════════════════════════════════

  void _onReceiveMessage(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    final data = args[0];
    Map<String, dynamic>? msg;
    if (data is Map<String, dynamic>) {
      msg = data;
    } else if (data is Map) {
      msg = Map<String, dynamic>.from(data);
    }
    if (msg != null) {
      _messageController.add(msg);
      refreshUnreadCount();
      _playNotificationSound();
      // بانر داخل التطبيق
      final sender = msg['senderName']?.toString() ?? msg['sender']?.toString() ?? '';
      final content = msg['content']?.toString() ?? msg['message']?.toString() ?? 'رسالة جديدة';
      if (sender.isNotEmpty) {
        InAppNotificationService.instance.show(
          title: sender,
          body: content,
          type: InAppNotificationType.chat,
          referenceId: msg['roomId']?.toString(),
        );
      }
    }
  }

  /// تشغيل صوت إشعار الرسالة
  void _playNotificationSound() {
    if (!soundEnabled) return;
    try {
      _notifPlayer.play(AssetSource('sounds/chat_notify.wav'), volume: 0.5).catchError((_) {
        // fallback: صوت النظام
        SystemSound.play(SystemSoundType.alert);
      });
    } catch (e) {
      try { SystemSound.play(SystemSoundType.alert); } catch (_) {}
    }
  }

  void _onMessageRead(List<Object?>? args) {
    if (args == null || args.length < 3) return;
    _readController.add({
      'roomId': args[0]?.toString(),
      'userId': args[1]?.toString(),
      'readAt': args[2]?.toString(),
    });
  }

  void _onMessageDeleted(List<Object?>? args) {
    if (args == null || args.length < 2) return;
    _deletedController.add({
      'messageId': args[0]?.toString(),
      'roomId': args[1]?.toString(),
    });
  }

  void _onUserTyping(List<Object?>? args) {
    if (args == null || args.length < 3) return;
    _typingController.add({
      'roomId': args[0]?.toString(),
      'userId': args[1]?.toString(),
      'userName': args[2]?.toString(),
      'isTyping': true,
    });
  }

  void _onUserStoppedTyping(List<Object?>? args) {
    if (args == null || args.length < 2) return;
    _typingController.add({
      'roomId': args[0]?.toString(),
      'userId': args[1]?.toString(),
      'isTyping': false,
    });
  }

  void _onUserOnline(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    _onlineController.add({'userId': args[0]?.toString(), 'isOnline': true});
  }

  void _onUserOffline(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    _onlineController.add({'userId': args[0]?.toString(), 'isOnline': false});
  }

  void _onAddedToRoom(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    _roomEventController.add({'event': 'added', 'roomId': args[0]?.toString()});
    refreshUnreadCount();
  }

  void _onRemovedFromRoom(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    _roomEventController.add({'event': 'removed', 'roomId': args[0]?.toString()});
  }

  // ═══════════════════════════════════════
  // HTTP Helpers
  // ═══════════════════════════════════════

  Future<List<Map<String, dynamic>>> _getRawList(String endpoint) async {
    try {
      final token = ApiClient.instance.authToken;
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);

      final response = await client.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is List) {
          return body.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ ChatService GET $endpoint: $e');
    }
    return [];
  }

  Future<Map<String, dynamic>?> _getRawAsMap(String endpoint) async {
    try {
      final token = ApiClient.instance.authToken;
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);

      final response = await client.get(uri, headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      }).timeout(ApiConfig.connectionTimeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      if (kDebugMode) print('❌ ChatService GET $endpoint: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _postRaw(String endpoint, Map<String, dynamic> body) async {
    try {
      final token = ApiClient.instance.authToken;
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);

      final response = await client.post(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }, body: jsonEncode(body)).timeout(ApiConfig.connectionTimeout);

      if (kDebugMode) print('📮 ChatService POST $endpoint → ${response.statusCode}: ${response.body}');
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isNotEmpty) return jsonDecode(response.body);
        return {'success': true};
      }
    } catch (e) {
      if (kDebugMode) print('❌ ChatService POST $endpoint: $e');
    }
    return null;
  }

  Future<void> _putRaw(String endpoint, Map<String, dynamic> body) async {
    try {
      final token = ApiClient.instance.authToken;
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);

      await client.put(uri, headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      }, body: jsonEncode(body)).timeout(ApiConfig.connectionTimeout);
    } catch (e) {
      if (kDebugMode) print('❌ ChatService PUT $endpoint: $e');
    }
  }

  /// تنظيف
  void dispose() {
    _messageController.close();
    _typingController.close();
    _readController.close();
    _deletedController.close();
    _onlineController.close();
    _roomEventController.close();
    _unreadCountController.close();
    disconnect();
  }
}
