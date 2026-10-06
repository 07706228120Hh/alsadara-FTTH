/// خدمة قياس سرعة التنزيل والرفع — Network Quality
///
/// تستخدم نقاط Cloudflare المفتوحة (speed.cloudflare.com) لقياس الإنتاجية
/// الفعلية. تعتمد على http الموجودة أصلاً. القياس تدفّقي لحساب السرعة اللحظية.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class SpeedProgress {
  final double mbps; // السرعة اللحظية/التراكمية
  final double fraction; // 0..1 نسبة الإنجاز
  const SpeedProgress(this.mbps, this.fraction);
}

class SpeedTestService {
  static const _downUrl = 'https://speed.cloudflare.com/__down';
  static const _upUrl = 'https://speed.cloudflare.com/__up';

  /// قياس سرعة التنزيل (Mbps). [onProgress] للسرعة اللحظية أثناء القياس.
  static Future<double?> download({
    int bytes = 25 * 1024 * 1024, // 25MB افتراضياً
    void Function(SpeedProgress)? onProgress,
    Duration maxDuration = const Duration(seconds: 15),
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse('$_downUrl?bytes=$bytes'));
      final sw = Stopwatch()..start();
      final resp = await client.send(req).timeout(maxDuration);
      int received = 0;
      final completer = Completer<double?>();
      late StreamSubscription sub;
      Timer? guard;

      void finish() {
        sw.stop();
        guard?.cancel();
        sub.cancel();
        if (!completer.isCompleted) {
          final secs = sw.elapsedMicroseconds / 1e6;
          if (secs <= 0 || received == 0) {
            completer.complete(null);
          } else {
            completer.complete(received * 8 / secs / 1e6);
          }
        }
      }

      guard = Timer(maxDuration, finish);
      sub = resp.stream.listen(
        (chunk) {
          received += chunk.length;
          final secs = sw.elapsedMicroseconds / 1e6;
          if (secs > 0 && onProgress != null) {
            onProgress(SpeedProgress(
              received * 8 / secs / 1e6,
              (received / bytes).clamp(0, 1),
            ));
          }
        },
        onDone: finish,
        onError: (_) => finish(),
        cancelOnError: true,
      );

      return await completer.future;
    } catch (e) {
      debugPrint('[Speed] download error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// قياس سرعة الرفع (Mbps) برفع حمولة عشوائية.
  static Future<double?> upload({
    int bytes = 10 * 1024 * 1024, // 10MB افتراضياً
    Duration maxDuration = const Duration(seconds: 15),
  }) async {
    final client = http.Client();
    try {
      final payload = Uint8List(bytes); // أصفار — كافٍ لقياس الإنتاجية
      final sw = Stopwatch()..start();
      final resp = await client
          .post(Uri.parse(_upUrl), body: payload)
          .timeout(maxDuration);
      sw.stop();
      if (resp.statusCode >= 200 && resp.statusCode < 400) {
        final secs = sw.elapsedMicroseconds / 1e6;
        if (secs <= 0) return null;
        return bytes * 8 / secs / 1e6;
      }
      return null;
    } catch (e) {
      debugPrint('[Speed] upload error: $e');
      return null;
    } finally {
      client.close();
    }
  }
}
