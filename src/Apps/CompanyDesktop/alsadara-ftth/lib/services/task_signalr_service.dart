import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';

/// خدمة SignalR لإشعارات المهام الفورية — بديل الـ Polling
class TaskSignalRService {
  static TaskSignalRService? _instance;
  static TaskSignalRService get instance => _instance ??= TaskSignalRService._();
  TaskSignalRService._();

  HubConnection? _hubConnection;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Streams للإشعارات
  final _taskCreatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _taskUpdatedController = StreamController<Map<String, dynamic>>.broadcast();
  final _taskAssignedController = StreamController<Map<String, dynamic>>.broadcast();
  final _taskDeletedController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onTaskCreated => _taskCreatedController.stream;
  Stream<Map<String, dynamic>> get onTaskUpdated => _taskUpdatedController.stream;
  Stream<Map<String, dynamic>> get onTaskAssigned => _taskAssignedController.stream;
  Stream<Map<String, dynamic>> get onTaskDeleted => _taskDeletedController.stream;

  /// stream موحّد — أي تغيير (إنشاء/تحديث/تعيين/حذف)
  final _anyChangeController = StreamController<String>.broadcast();
  Stream<String> get onAnyChange => _anyChangeController.stream;

  /// الاتصال بـ TaskHub
  Future<void> connect() async {
    if (_isConnected) return;

    final token = ApiClient.instance.authToken;
    if (token == null) return;

    final baseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    final hubUrl = '$baseUrl/hubs/tasks';

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
    _hubConnection!.on('TaskCreated', _onTaskCreated);
    _hubConnection!.on('TaskUpdated', _onTaskUpdated);
    _hubConnection!.on('TaskAssigned', _onTaskAssigned);
    _hubConnection!.on('TaskDeleted', _onTaskDeleted);

    _hubConnection!.onclose(({error}) {
      _isConnected = false;
      if (kDebugMode) debugPrint('📋 TaskHub disconnected: $error');
    });

    _hubConnection!.onreconnected(({connectionId}) {
      _isConnected = true;
      if (kDebugMode) debugPrint('📋 TaskHub reconnected: $connectionId');
    });

    try {
      await _hubConnection!.start();
      _isConnected = true;
      if (kDebugMode) debugPrint('📋 TaskHub connected');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ TaskHub connection failed: $e');
    }
  }

  /// قطع الاتصال
  Future<void> disconnect() async {
    try {
      await _hubConnection?.stop();
    } catch (_) {}
    _isConnected = false;
  }

  // ═══ Handlers ═══

  void _onTaskCreated(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    final data = _parseArg(args[0]);
    if (data != null) {
      _taskCreatedController.add(data);
      _anyChangeController.add('created');
    }
  }

  void _onTaskUpdated(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    final data = _parseArg(args[0]);
    if (data != null) {
      _taskUpdatedController.add(data);
      _anyChangeController.add('updated');
    }
  }

  void _onTaskAssigned(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    final data = _parseArg(args[0]);
    if (data != null) {
      _taskAssignedController.add(data);
      _anyChangeController.add('assigned');
    }
  }

  void _onTaskDeleted(List<Object?>? args) {
    if (args == null || args.isEmpty) return;
    final data = _parseArg(args[0]);
    if (data != null) {
      _taskDeletedController.add(data);
      _anyChangeController.add('deleted');
    }
  }

  Map<String, dynamic>? _parseArg(Object? arg) {
    if (arg is Map) return Map<String, dynamic>.from(arg);
    return null;
  }

  /// تنظيف
  void dispose() {
    disconnect();
    _taskCreatedController.close();
    _taskUpdatedController.close();
    _taskAssignedController.close();
    _taskDeletedController.close();
    _anyChangeController.close();
  }
}
