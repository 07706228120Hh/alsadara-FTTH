/// خدمة معاينة وإرسال يدوي لتذكير انتهاء الاشتراك
/// الإرسال التلقائي يتم عبر n8n workflow على السيرفر
/// هذه الخدمة للاستخدام من واجهة Flutter فقط (معاينة + إرسال يدوي)
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'bulk_messaging_service.dart';

class AutoRenewalReminderService {
  AutoRenewalReminderService._();
  static AutoRenewalReminderService? _instance;
  static AutoRenewalReminderService get instance =>
      _instance ??= AutoRenewalReminderService._();

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  // ═══ معاينة — جلب الأسماء بدون إرسال ═══

  /// جلب قائمة المشتركين لفترة معينة (للمعاينة فقط)
  Future<List<Map<String, dynamic>>> previewBatch(int days) async {
    final subscriptions = await fetchExpiringSubscriptions(days);
    final withPhones = await fetchPhonesInParallel(subscriptions);
    return withPhones;
  }

  // ═══ إرسال يدوي ═══

  /// إرسال يدوي لوجبة معينة (من الواجهة)
  Future<Map<String, dynamic>> sendManually(int days) async {
    if (_isRunning) {
      return {'total': 0, 'sent': 0, 'failed': 0, 'error': 'جاري الإرسال بالفعل'};
    }
    _isRunning = true;
    try {
      final subscriptions = await fetchExpiringSubscriptions(days);
      if (subscriptions.isEmpty) {
        return {'total': 0, 'sent': 0, 'failed': 0, 'names': <String>[]};
      }

      final withPhones = await fetchPhonesInParallel(subscriptions);

      final toSend = withPhones.where((sub) {
        final phone = sub['customerPhone']?.toString() ?? '';
        return phone.isNotEmpty && phone != 'غير متوفر';
      }).toList();

      if (toSend.isEmpty) {
        return {
          'total': subscriptions.length,
          'sent': 0,
          'failed': 0,
          'names': <String>[],
        };
      }

      final messages = _toBulkMessages(toSend);
      final sendResult = await BulkMessagingService.send(
        messages: messages,
        templateType: BulkTemplateType.expiringSoon,
      );

      final names =
          toSend.map((s) => s['customer']?['displayValue']?.toString() ?? '').toList();

      return {
        'total': subscriptions.length,
        'sent': sendResult.totalSent,
        'failed': sendResult.totalFailed,
        'names': names,
        'time': _nowTimeStr(),
        'date': _todayKey(),
      };
    } catch (e) {
      debugPrint('❌ [AutoReminder] خطأ في الإرسال اليدوي: $e');
      return {'total': 0, 'sent': 0, 'failed': 0, 'error': e.toString()};
    } finally {
      _isRunning = false;
    }
  }

  // ═══ جلب المشتركين ═══

  Future<List<Map<String, dynamic>>> fetchExpiringSubscriptions(
      int days) async {
    try {
      final now = DateTime.now();
      final DateTime fromDate;
      final DateTime toDate;
      if (days == 0) {
        fromDate = DateTime(now.year, now.month, now.day);
        toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      } else {
        fromDate = DateTime(now.year, now.month, now.day + days);
        toDate = DateTime(now.year, now.month, now.day + days, 23, 59, 59);
      }

      final List<Map<String, dynamic>> all = [];
      int page = 1;
      const pageSize = 100;

      while (true) {
        final url = 'https://admin.ftth.iq/api/subscriptions'
            '?pageSize=$pageSize&pageNumber=$page'
            '&sortCriteria.property=expires&sortCriteria.direction=asc'
            '&status=Active&hierarchyLevel=0'
            '&fromExpirationDate=${fromDate.toIso8601String().split('T')[0]}'
            '&toExpirationDate=${toDate.toIso8601String().split('T')[0]}';

        final response = await AuthService.instance
            .authenticatedRequest('GET', url)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode != 200) break;

        final data = jsonDecode(response.body);
        final items = data['items'] as List? ?? [];
        final total = data['totalCount'] ?? 0;

        for (final item in items) {
          all.add(Map<String, dynamic>.from(item as Map));
        }

        if (all.length >= total || items.isEmpty || all.length >= 500) break;
        page++;
      }

      return all;
    } catch (e) {
      debugPrint('❌ [AutoReminder] خطأ في جلب الاشتراكات: $e');
      return [];
    }
  }

  // ═══ جلب أرقام الهواتف ═══

  final Map<String, String> _phoneCache = {};

  Future<List<Map<String, dynamic>>> fetchPhonesInParallel(
      List<Map<String, dynamic>> subscriptions) async {
    const batchSize = 15;
    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < subscriptions.length; i += batchSize) {
      final end = (i + batchSize < subscriptions.length)
          ? i + batchSize
          : subscriptions.length;
      final batch = subscriptions.sublist(i, end);

      final futures = batch.map((sub) => _fetchSinglePhone(sub)).toList();
      result.addAll(await Future.wait(futures));

      if (i + batchSize < subscriptions.length) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    return result;
  }

  Future<Map<String, dynamic>> _fetchSinglePhone(
      Map<String, dynamic> subscription) async {
    final customerId = subscription['customer']?['id']?.toString();
    String phone = 'غير متوفر';

    if (customerId != null && customerId.isNotEmpty) {
      if (_phoneCache.containsKey(customerId)) {
        phone = _phoneCache[customerId]!;
      } else {
        try {
          final response = await AuthService.instance
              .authenticatedRequest(
                  'GET', 'https://admin.ftth.iq/api/customers/$customerId')
              .timeout(const Duration(seconds: 3));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            phone = data['model']?['primaryContact']?['mobile'] ?? 'غير متوفر';
            _phoneCache[customerId] = phone;
          }
        } catch (_) {
          _phoneCache[customerId] = 'غير متوفر';
        }
      }
    }

    final enhanced = Map<String, dynamic>.from(subscription);
    enhanced['customerPhone'] = phone;
    return enhanced;
  }

  // ═══ مساعدات ═══

  List<BulkMessage> _toBulkMessages(List<Map<String, dynamic>> subs) {
    return subs.map((sub) {
      return BulkMessage(
        phone: sub['customerPhone']?.toString() ?? '',
        subscriberName:
            sub['customer']?['displayValue']?.toString() ?? 'مشترك',
        planName: sub['bundle']?['displayValue']?.toString() ?? '',
        fbg: sub['zone']?['displayValue']?.toString() ?? '',
        daysRemaining: _calcDaysLeft(sub['expires']?.toString() ?? ''),
        endDate: _formatDate(sub['expires']?.toString() ?? ''),
      );
    }).toList();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _nowTimeStr() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  int _calcDaysLeft(String expiresStr) {
    try {
      return DateTime.parse(expiresStr).difference(DateTime.now()).inDays;
    } catch (_) {
      return 0;
    }
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}
