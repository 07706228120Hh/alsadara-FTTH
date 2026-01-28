import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

/// خدمة خلفية بسيطة (Polling) لاكتشاف التذاكر الجديدة على بيئة سطح المكتب (Windows)
/// NOTE: مخصصة عندما لا يتوفر WebSocket ولا تعمل FCM على Windows.
class TicketUpdatesService {
  TicketUpdatesService._();
  static final TicketUpdatesService instance = TicketUpdatesService._();

  static const _prefsSeenKey = 'ticket_updates_seen_ids_v1';
  static const _prefsEnabledKey = 'ticket_updates_enabled';
  static const Duration defaultInterval = Duration(seconds: 45); // يمكن ضبطها

  Timer? _timer;
  bool _running = false;
  String? _authToken;
  bool _fetchInProgress = false;
  final Set<String> _seenIds = <String>{};
  final StreamController<List<Map<String, dynamic>>> _newTicketsController =
      StreamController.broadcast();

  Stream<List<Map<String, dynamic>>> get newTicketsStream => _newTicketsController.stream;

  Future<void> start({String? authToken, Duration? interval}) async {
    if (!Platform.isWindows) return; // لا نفعّل على غير Windows
    if (_running) return;
    _running = true;
    _authToken = authToken ?? await _loadStoredToken();

    await _loadSeenIds();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, true);

    // أول تشغيل مباشر ثم مؤقت
    unawaited(_poll());
    _timer = Timer.periodic(interval ?? defaultInterval, (_) => _poll());
  }

  bool get isRunning => _running;

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabledKey, false);
  }

  Future<void> _poll() async {
    if (_fetchInProgress) return;
    if (_authToken == null || _authToken!.isEmpty) return;
    _fetchInProgress = true;
    try {
      final uri = Uri.parse(
          'https://api.ftth.iq/api/support/tickets?pageSize=30&pageNumber=1&sortCriteria.property=createdAt&sortCriteria.direction=desc&status=0&hierarchyLevel=0');
      final resp = await http.get(uri, headers: {
        'Authorization': 'Bearer $_authToken',
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 25));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final List items = (data['items'] as List?) ?? [];
        final List<Map<String, dynamic>> parsed = items
            .whereType<Map<String, dynamic>>()
            .map((e) => e)
            .toList(growable: false);

        final List<Map<String, dynamic>> fresh = [];
        for (final t in parsed) {
          final id = t['id']?.toString();
          if (id == null || id.isEmpty) continue;
          if (!_seenIds.contains(id)) {
            _seenIds.add(id);
            fresh.add(t);
          }
        }
        if (fresh.isNotEmpty) {
          _trimSeen();
          await _persistSeenIds();
          _newTicketsController.add(fresh);
          // إشعار مجمع
          await _notifyNewTickets(fresh);
        }
      }
    } catch (_) {
      // تجاهل أخطاء الشبكة بصمت هنا
    } finally {
      _fetchInProgress = false;
    }
  }

  Future<void> _notifyNewTickets(List<Map<String, dynamic>> fresh) async {
    if (fresh.isEmpty) return;
    if (fresh.length == 1) {
      final f = fresh.first;
      final title = f['self']?['displayValue']?.toString() ?? f['title']?.toString() ?? 'تذكرة جديدة';
      final customer = f['customer']?['displayValue']?.toString();
      final body = customer == null || customer.isEmpty
          ? 'تم إنشاء تذكرة جديدة: $title'
          : 'تذكرة جديدة: $title للعميل $customer';
      await NotificationService.showLocalNotification(
        title: '🔔 تذكرة جديدة',
        body: body,
        payload: jsonEncode({
          'type': 'new_ticket_poll',
          'ticketId': f['id']?.toString(),
          'title': title,
          'customer': customer,
        }),
      );
    } else {
      await NotificationService.showLocalNotification(
        title: '🔔 ${fresh.length} تذاكر جديدة',
        body: 'وصلت ${fresh.length} تذاكر جديدة (Polling خلفي)',
        payload: jsonEncode({
          'type': 'new_ticket_batch_poll',
          'count': fresh.length,
          'ids': fresh.map((e) => e['id']?.toString()).whereType<String>().toList(),
        }),
      );
    }
  }

  Future<void> _loadSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsSeenKey) ?? [];
    _seenIds
      ..clear()
      ..addAll(list);
  }

  Future<void> _persistSeenIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsSeenKey, _seenIds.toList());
  }

  void _trimSeen({int max = 500}) {
    if (_seenIds.length <= max) return;
    // نحافظ على آخر max فقط (ليست مرتبة حالياً؛ يمكن تحسينها بتخزين timestamps)
    final trimmed = _seenIds.take(max).toList();
    _seenIds
      ..clear()
      ..addAll(trimmed);
  }

  Future<String?> _loadStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('auth_token'); // مفتاح متوقع، قد تحتاج للتعديل وفق تطبيقك
    } catch (_) {
      return null;
    }
  }
}
