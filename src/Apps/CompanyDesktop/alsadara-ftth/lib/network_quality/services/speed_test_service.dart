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
  ///
  /// القياس متين: يفتح عدّة اتصالات متوازية لتشبيع الوصلات السريعة، يتجاهل
  /// فترة إحماء قصيرة ثم يقيس الإنتاجية في نافذة الثبات (من أول بايت مستلم لا
  /// من قبل الإرسال)، ويكتشف توقّف التدفّق عبر مؤقّت خمول مستقلّ عن مهلة TTFB.
  /// يُعيد null (⇒ تُعرض «—») إن لم يصل رمز 200 أو إن كانت البايتات المستلمة
  /// أقلّ من [minBytes] — بدل إرجاع رقم كاذب مثل 0.0.
  static Future<double?> download({
    int bytes = 20 * 1024 * 1024, // إجمالي الحمولة عبر كل الاتصالات
    void Function(SpeedProgress)? onProgress,
    Duration maxDuration = const Duration(seconds: 15),
    Duration ttfbTimeout = const Duration(seconds: 8), // مهلة أول استجابة
    Duration idleTimeout = const Duration(seconds: 6), // توقّف التدفّق
    Duration warmup = const Duration(milliseconds: 800),
    int connections = 4,
    int minBytes = 512 * 1024, // أقلّ حجم معقول لاعتبار القياس صحيحاً
  }) async {
    connections = connections.clamp(1, 8);
    final perConn = (bytes / connections).ceil();

    final clients = <http.Client>[];
    final subs = <StreamSubscription>[];
    final completer = Completer<double?>();

    final sw = Stopwatch();
    int totalReceived = 0;
    int warmBytes = 0; // البايتات عند انتهاء الإحماء
    int warmStartUs = 0; // زمن انتهاء الإحماء (µs)
    bool warmDone = false;
    int activeStreams = 0;
    int pendingSetup = connections;
    bool finished = false;
    Timer? guard;
    Timer? idle;

    void cleanup() {
      guard?.cancel();
      idle?.cancel();
      for (final s in subs) {
        try {
          s.cancel();
        } catch (_) {}
      }
      for (final c in clients) {
        try {
          c.close();
        } catch (_) {}
      }
    }

    void finish() {
      if (finished) return;
      finished = true;
      sw.stop();
      cleanup();
      if (completer.isCompleted) return;
      // تدفّق ضئيل جداً ⇒ قياس غير موثوق ⇒ أعد null (تظهر «—»).
      if (totalReceived < minBytes) {
        completer.complete(null);
        return;
      }
      double mbps;
      if (warmDone && sw.elapsedMicroseconds > warmStartUs) {
        final secs = (sw.elapsedMicroseconds - warmStartUs) / 1e6;
        mbps = (totalReceived - warmBytes) * 8 / secs / 1e6;
      } else {
        final secs = sw.elapsedMicroseconds / 1e6;
        mbps = secs > 0 ? totalReceived * 8 / secs / 1e6 : 0;
      }
      completer.complete(mbps > 0 ? mbps : null);
    }

    void resetIdle() {
      idle?.cancel();
      idle = Timer(idleTimeout, finish);
    }

    void onChunk(int len) {
      if (!sw.isRunning) sw.start();
      totalReceived += len;
      final us = sw.elapsedMicroseconds;
      if (!warmDone && us >= warmup.inMicroseconds) {
        warmDone = true;
        warmBytes = totalReceived;
        warmStartUs = us;
      }
      resetIdle();
      if (onProgress != null) {
        double inst;
        if (warmDone && us > warmStartUs) {
          inst = (totalReceived - warmBytes) * 8 / ((us - warmStartUs) / 1e6) / 1e6;
        } else {
          inst = us > 0 ? totalReceived * 8 / (us / 1e6) / 1e6 : 0;
        }
        onProgress(SpeedProgress(inst, (totalReceived / bytes).clamp(0, 1)));
      }
    }

    void setupDone() {
      pendingSetup--;
      // كل الاتصالات فشلت في الحصول على 200/تدفّق ⇒ أعد null بوضوح.
      if (pendingSetup <= 0 && activeStreams == 0 && !finished) {
        finished = true;
        cleanup();
        if (!completer.isCompleted) completer.complete(null);
      }
    }

    Future<void> startConn() async {
      final client = http.Client();
      clients.add(client);
      try {
        final req = http.Request('GET', Uri.parse('$_downUrl?bytes=$perConn'));
        final resp = await client.send(req).timeout(ttfbTimeout);
        if (resp.statusCode != 200) {
          setupDone();
          return;
        }
        activeStreams++;
        setupDone();
        late StreamSubscription sub;
        sub = resp.stream.listen(
          (chunk) => onChunk(chunk.length),
          onDone: () {
            activeStreams--;
            if (activeStreams <= 0) finish();
          },
          onError: (_) {
            activeStreams--;
            if (activeStreams <= 0) finish();
          },
          cancelOnError: true,
        );
        subs.add(sub);
      } catch (_) {
        setupDone();
      }
    }

    try {
      for (var i = 0; i < connections; i++) {
        // لا ننتظر هنا — الاتصالات تنطلق متوازية والقياس يُدار بالمؤقّتات.
        unawaited(startConn());
      }
      guard = Timer(maxDuration, finish);
      return await completer.future;
    } catch (e) {
      debugPrint('[Speed] download error: $e');
      cleanup();
      return completer.isCompleted ? completer.future : null;
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
