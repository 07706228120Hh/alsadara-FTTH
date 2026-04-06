import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// طابور الموقع — يحفظ النقاط عند انقطاع الإنترنت ويرسلها عند العودة
class LocationOfflineQueue {
  static const _queueKey = 'location_offline_queue';
  static const _maxQueueSize = 500; // حد أقصى 500 نقطة مخزنة

  /// إضافة نقطة للطابور
  static Future<void> enqueue(Map<String, dynamic> locationData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_queueKey) ?? [];

      if (queue.length >= _maxQueueSize) {
        queue.removeAt(0); // حذف الأقدم
      }

      queue.add(jsonEncode(locationData));
      await prefs.setStringList(_queueKey, queue);
      debugPrint('📦 [OfflineQueue] Queued (${queue.length} pending)');
    } catch (e) {
      debugPrint('⚠️ [OfflineQueue] Enqueue error: $e');
    }
  }

  /// إرسال كل النقاط المعلقة
  /// يُرجع عدد النقاط المرسلة بنجاح
  static Future<int> flush() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_queueKey) ?? [];
      if (queue.isEmpty) return 0;

      debugPrint('📦 [OfflineQueue] Flushing ${queue.length} points...');

      int sent = 0;
      final failed = <String>[];

      for (final item in queue) {
        try {
          final data = jsonDecode(item) as Map<String, dynamic>;
          final url = Uri.parse('https://api.ramzalsadara.tech/api/employee-location');
          final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
          final request = await client.postUrl(url);
          request.headers.set('Content-Type', 'application/json');
          request.headers.set('X-Api-Key', 'sadara-internal-2024-secure-key');
          request.write(jsonEncode(data));
          final response = await request.close();
          await response.drain();
          client.close();

          if (response.statusCode >= 200 && response.statusCode < 300) {
            sent++;
          } else {
            failed.add(item);
          }
        } catch (_) {
          failed.add(item);
          break; // لا فائدة نكمل إذا لا يوجد إنترنت
        }
      }

      // حفظ النقاط التي فشلت فقط
      await prefs.setStringList(_queueKey, failed);
      debugPrint('📦 [OfflineQueue] Sent $sent, remaining ${failed.length}');
      return sent;
    } catch (e) {
      debugPrint('⚠️ [OfflineQueue] Flush error: $e');
      return 0;
    }
  }

  /// عدد النقاط المعلقة
  static Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_queueKey) ?? []).length;
  }

  /// مسح الطابور
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  }
}
