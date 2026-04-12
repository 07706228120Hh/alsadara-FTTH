import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'task_api_service.dart';
import 'in_app_notification_service.dart';
import 'notification_service.dart';
import 'dart:convert';
import '../ftth/users/quick_search_users_page.dart';
import 'auth_service.dart';
import 'dual_auth_service.dart';
import '../../widgets/window_close_handler_fixed.dart' show navigatorKey;

/// خدمة Polling لمتابعة مهام التحصيل المكتملة — تُنبّه المشغل فوراً
/// تعمل على Windows فقط (مثل TicketUpdatesService)
class CollectionTasksPollingService {
  CollectionTasksPollingService._();
  static final CollectionTasksPollingService instance =
      CollectionTasksPollingService._();

  static const _prefsSeenKey = 'collection_tasks_seen_ids_v1';
  static const Duration defaultInterval = Duration(seconds: 60);

  Timer? _timer;
  bool _running = false;
  bool _fetchInProgress = false;
  final Set<String> _seenIds = <String>{};

  // Stream للمهام المكتملة الجديدة
  final StreamController<List<Map<String, dynamic>>>
      _completedTasksController = StreamController.broadcast();
  Stream<List<Map<String, dynamic>>> get completedTasksStream =>
      _completedTasksController.stream;

  bool get isRunning => _running;

  Future<void> start({Duration? interval}) async {
    if (!Platform.isWindows) return;
    if (_running) return;
    _running = true;

    await _loadSeenIds();

    // أول poll مباشر ثم مؤقت
    unawaited(_poll());
    _timer = Timer.periodic(interval ?? defaultInterval, (_) => _poll());
    debugPrint('✅ [CollectionPolling] بدء المراقبة كل ${(interval ?? defaultInterval).inSeconds} ثانية');
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  Future<void> _poll() async {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    try {
      // جلب مهام التحصيل المكتملة
      final result = await TaskApiService.instance.getRequests(
        status: 'Completed',
        pageSize: 20,
      );

      if (result['success'] != true || result['data'] == null) return;

      final data = result['data'];
      final List items =
          data is Map ? (data['items'] as List? ?? []) : (data is List ? data : []);

      // فلتر مهام التحصيل فقط
      final collectionTasks = items
          .whereType<Map<String, dynamic>>()
          .where((t) {
            final details = t['details']?.toString() ?? '';
            final taskType = t['taskType']?.toString() ?? '';
            return details.contains('تحصيل مبلغ تجديد') ||
                taskType.contains('تحصيل مبلغ تجديد');
          })
          .toList();

      // اكتشاف المهام الجديدة (غير المرئية سابقاً)
      final List<Map<String, dynamic>> fresh = [];
      for (final t in collectionTasks) {
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
        _completedTasksController.add(fresh);
        await _notifyCompletedCollections(fresh);
        debugPrint('🔔 [CollectionPolling] ${fresh.length} مهمة تحصيل مكتملة جديدة');
      }

      // ═══════ فحص مهام التحصيل المتأخرة (مفتوحة > 24 ساعة) ═══════
      await _checkOverdueCollections();
    } catch (e) {
      debugPrint('⚠️ [CollectionPolling] خطأ: $e');
    } finally {
      _fetchInProgress = false;
    }
  }

  // تتبع المهام المتأخرة التي تم التنبيه عليها (لمنع التكرار)
  final Set<String> _notifiedOverdue24 = <String>{};
  final Set<String> _notifiedOverdue48 = <String>{};
  static const int _maxNotifiedOverdue = 500;

  void _trimOverdueSets() {
    if (_notifiedOverdue24.length > _maxNotifiedOverdue) {
      final keep = _notifiedOverdue24.toList().sublist(_notifiedOverdue24.length - _maxNotifiedOverdue);
      _notifiedOverdue24..clear()..addAll(keep);
    }
    if (_notifiedOverdue48.length > _maxNotifiedOverdue) {
      final keep = _notifiedOverdue48.toList().sublist(_notifiedOverdue48.length - _maxNotifiedOverdue);
      _notifiedOverdue48..clear()..addAll(keep);
    }
  }

  Future<void> _checkOverdueCollections() async {
    try {
      final result = await TaskApiService.instance.getRequests(
        status: 'Pending',
        pageSize: 50,
      );
      if (result['success'] != true || result['data'] == null) return;

      final data = result['data'];
      final List items =
          data is Map ? (data['items'] as List? ?? []) : (data is List ? data : []);

      final now = DateTime.now();

      for (final t in items.whereType<Map<String, dynamic>>()) {
        final details = t['details']?.toString() ?? '';
        final taskType = t['taskType']?.toString() ?? '';
        if (!details.contains('تحصيل مبلغ') && !taskType.contains('تحصيل مبلغ')) continue;

        final id = t['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        final createdStr = t['createdAt']?.toString() ?? '';
        final created = DateTime.tryParse(createdStr);
        if (created == null) continue;

        final hours = now.difference(created).inHours;
        final citizenName = t['citizen']?['fullName']?.toString() ?? t['citizenName']?.toString() ?? '';
        final techName = t['technician']?['fullName']?.toString() ?? t['technicianName']?.toString() ?? '';

        if (hours >= 48 && !_notifiedOverdue48.contains(id)) {
          _notifiedOverdue48.add(id);
          _notifiedOverdue24.add(id); // لمنع تكرار تنبيه 24
          InAppNotificationService.instance.show(
            title: '🚨 تأخر تحصيل — تصعيد',
            body: 'مضى 48+ ساعة! الفني $techName لم يحصّل من $citizenName',
            type: InAppNotificationType.system,
            referenceId: id,
          );
          await NotificationService.showLocalNotification(
            title: '🚨 تصعيد: تأخر تحصيل 48+ ساعة',
            body: 'الفني $techName لم يحصّل من $citizenName',
          );
        } else if (hours >= 24 && !_notifiedOverdue24.contains(id)) {
          _notifiedOverdue24.add(id);
          InAppNotificationService.instance.show(
            title: '⏰ تأخر تحصيل',
            body: 'مضى 24+ ساعة! الفني $techName لم يحصّل من $citizenName',
            type: InAppNotificationType.task,
            referenceId: id,
          );
          await NotificationService.showLocalNotification(
            title: '⏰ تنبيه: تأخر تحصيل 24+ ساعة',
            body: 'الفني $techName لم يحصّل من $citizenName',
          );
        }
      }
      _trimOverdueSets();
    } catch (e) {
      debugPrint('⚠️ [CollectionPolling] خطأ فحص التأخر: $e');
    }
  }

  Future<void> _notifyCompletedCollections(
      List<Map<String, dynamic>> fresh) async {
    for (final t in fresh) {
      final details = t['details']?.toString() ?? '';
      final citizenName = t['citizen']?['fullName']?.toString() ??
          t['citizenName']?.toString() ?? '';
      final techName = t['technician']?['fullName']?.toString() ??
          t['technicianName']?.toString() ?? '';
      final citizenPhone = t['citizen']?['phoneNumber']?.toString() ??
          t['citizenPhone']?.toString() ?? '';

      // استخراج المبلغ والهاتف من details
      final amountMatch = RegExp(r'تحصيل\s+([\d,]+)').firstMatch(details);
      final amount = amountMatch?.group(1) ?? '';
      // استخراج الهاتف من الملاحظات إذا لم يكن موجوداً
      final phoneMatch = RegExp(r'الهاتف:\s*([\d]+)').firstMatch(details);
      final phone = citizenPhone.isNotEmpty
          ? citizenPhone
          : (phoneMatch?.group(1) ?? '');

      final title = '💰 تم تحصيل مبلغ';
      final body = amount.isNotEmpty
          ? 'الفني $techName حصّل $amount د.ع من $citizenName'
          : 'الفني $techName أكمل التحصيل من $citizenName';

      // بانر داخل التطبيق مع إمكانية النقر لفتح صفحة المشترك
      InAppNotificationService.instance.show(
        title: title,
        body: body,
        type: InAppNotificationType.task,
        referenceId: t['id']?.toString(),
        onTap: phone.isNotEmpty ? () => _navigateToSubscriber(phone, citizenName) : null,
      );

      // إشعار نظام (Windows)
      await NotificationService.showLocalNotification(
        title: title,
        body: body,
        payload: jsonEncode({
          'type': 'collection_completed',
          'taskId': t['id']?.toString(),
          'citizenName': citizenName,
          'technicianName': techName,
          'amount': amount,
          'phone': phone,
        }),
      );
    }
  }

  /// فتح صفحة البحث عن المشترك عند الضغط على إشعار التحصيل
  void _navigateToSubscriber(String phone, String customerName) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final token = await AuthService.instance.getAccessToken() ?? '';
    if (token.isEmpty) return;

    // تحويل الهاتف لصيغة البحث
    String searchQuery = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (searchQuery.startsWith('964')) searchQuery = '0${searchQuery.substring(3)}';

    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => QuickSearchUsersPage(
          authToken: token,
          activatedBy: DualAuthService.instance.ftthUsername ?? '',
          initialSearchQuery: searchQuery,
        ),
      ),
    );
  }

  Future<void> _loadSeenIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsSeenKey) ?? [];
      _seenIds
        ..clear()
        ..addAll(list);
    } catch (_) {}
  }

  Future<void> _persistSeenIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsSeenKey, _seenIds.toList());
    } catch (_) {}
  }

  void _trimSeen({int max = 300}) {
    if (_seenIds.length <= max) return;
    // الاحتفاظ بأحدث العناصر (آخر max عنصر مُضاف)
    final all = _seenIds.toList();
    final trimmed = all.sublist(all.length - max);
    _seenIds
      ..clear()
      ..addAll(trimmed);
  }

  void dispose() {
    stop();
    _completedTasksController.close();
  }
}
