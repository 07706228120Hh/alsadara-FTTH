/// المُرسِل عبر الخادم الذاتي (whatsapp-web.js) — النمط `server`، مجاني وآلي.
///
/// يتحدّث إلى خادم Node محلي (افتراضياً 127.0.0.1:3100) عبر HTTP. الإرسال الجماعي
/// يُنسَّق من جهة التطبيق (نداء `/send` لكل مستلِم) لإتاحة تقدّم حيّ وإلغاء موحّد
/// مع بقية الأنماط؛ ويبقى `/send-bulk` في الخادم متاحاً للتشغيل الخلفي.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/wa_mode.dart';
import '../core/wa_sender.dart';
import '../models/wa_message.dart';

class ServerSender implements WaSender {
  /// عنوان الخادم المحلي (بلا شرطة نهائية).
  final String baseUrl;

  /// معرّف المستأجر — افتراضياً `default` (مستأجر واحد)، يدعم التعدّد مستقبلاً.
  final String tenant;

  final http.Client _http;
  final Duration _timeout;

  ServerSender({
    required this.baseUrl,
    this.tenant = 'default',
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
  })  : _http = client ?? http.Client(),
        _timeout = timeout;

  @override
  WaMode get mode => WaMode.server;

  @override
  WaCapabilities get capabilities => const WaCapabilities(
        automated: true,
        bulk: true,
        needsSession: true,
        inbound: true, // الخادم يدعم استقبال الردود (يُفعَّل لاحقاً)
      );

  String get _base => baseUrl.replaceAll(RegExp(r'/+$'), '');
  Uri _u(String path) => Uri.parse('$_base/$path');

  /// رابط صورة رمز QR للعرض المباشر في الواجهة (Image.network).
  String qrImageUrl() => '$_base/qr-image/$tenant';

  // ── إدارة الجلسة (تستخدمها شاشة الإعدادات لربط QR) ──

  /// يُنشئ/يُهيّئ الجلسة (يبدأ توليد QR إن لم تكن مربوطة).
  Future<void> initSession() async {
    await _http.post(_u('session/$tenant')).timeout(_timeout);
  }

  /// يقطع الجلسة ويحذفها (يتطلّب مسح QR جديداً لاحقاً).
  Future<void> resetSession() async {
    await _http.delete(_u('session/$tenant')).timeout(_timeout);
  }

  @override
  Future<WaStatus> status() async {
    try {
      final r = await _http.get(_u('status/$tenant')).timeout(_timeout);
      if (r.statusCode != 200) {
        return const WaStatus(WaConnState.unavailable, detail: 'الخادم لا يستجيب');
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final state = switch ((j['state'] as String?) ?? 'disconnected') {
        'ready' => WaConnState.ready,
        'qr' || 'needsQr' => WaConnState.needsQr,
        'connecting' || 'initializing' => WaConnState.connecting,
        _ => WaConnState.disconnected,
      };
      return WaStatus(state, phone: j['phone'] as String?);
    } on TimeoutException {
      return const WaStatus(WaConnState.unavailable, detail: 'انتهت مهلة الاتصال بالخادم');
    } catch (_) {
      return const WaStatus(WaConnState.unavailable, detail: 'الخادم المحلي غير مشغّل');
    }
  }

  @override
  Future<WaSendResult> sendOne(WaOutgoing msg) async {
    final n = msg.phone;
    if (n == null) return WaSendResult.failure(msg, 'رقم غير صالح لواتساب');
    try {
      final r = await _http
          .post(
            _u('send/$tenant'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'phone': n, 'message': msg.text}),
          )
          .timeout(_timeout);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return (j['success'] == true)
            ? WaSendResult.success(msg)
            : WaSendResult.failure(msg, (j['error'] as String?) ?? 'فشل الإرسال');
      }
      return WaSendResult.failure(msg, 'خطأ الخادم (${r.statusCode})');
    } on TimeoutException {
      return WaSendResult.failure(msg, 'انتهت المهلة');
    } catch (e) {
      return WaSendResult.failure(msg, 'تعذّر الاتصال بالخادم: $e');
    }
  }

  @override
  Stream<WaBatchProgress> sendBulk(
    List<WaOutgoing> messages, {
    Duration delay = const Duration(seconds: 5),
  }) async* {
    var prog = WaBatchProgress(total: messages.length);
    yield prog;
    for (var i = 0; i < messages.length; i++) {
      final res = await sendOne(messages[i]);
      prog = prog.copyWith(
        current: i + 1,
        sent: res.ok ? prog.sent + 1 : prog.sent,
        failed: res.ok ? prog.failed : prog.failed + 1,
        last: res,
      );
      yield prog;
      if (i < messages.length - 1) await Future<void>.delayed(delay);
    }
    yield prog.copyWith(done: true);
  }

  @override
  void dispose() => _http.close();
}
