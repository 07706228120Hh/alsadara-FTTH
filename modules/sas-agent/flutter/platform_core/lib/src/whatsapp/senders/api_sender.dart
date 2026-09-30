/// المُرسِل عبر Meta Cloud API الرسمي — النمط `api`.
///
/// **قابس مؤجّل (stub):** الهيكل جاهز والواجهة موحّدة؛ يُملأ لاحقاً دون تغيير أي
/// شاشة. عند التفعيل مستقبلاً — تطابقاً مع نظام الصدارة — تُنفَّذ الأجسام أدناه:
///   • الإرسال: `POST https://graph.facebook.com/v21.0/{phoneNumberId}/messages`
///     برأس `Authorization: Bearer {accessToken}` وجسم قالب معتمد.
///   • يُفضَّل توجيهه عبر باكند التطبيق (يحفظ التوكن سرّاً) لا من الجهاز مباشرة.
///   • الاستقبال: webhook في الباكند يخزّن الردود (سجل محادثات).
library;

import 'dart:async';

import '../core/wa_mode.dart';
import '../core/wa_sender.dart';
import '../models/wa_message.dart';

/// إعداد Meta (يُملأ عند التفعيل). محفوظ الآن للمرجعية فقط.
class MetaApiConfig {
  final String phoneNumberId;
  final String accessToken;

  /// توجيه اختياري عبر الباكند بدل النداء المباشر (موصى به).
  final String? backendRelayUrl;

  const MetaApiConfig({
    this.phoneNumberId = '',
    this.accessToken = '',
    this.backendRelayUrl,
  });

  bool get isConfigured =>
      backendRelayUrl != null || (phoneNumberId.isNotEmpty && accessToken.isNotEmpty);
}

class ApiSender implements WaSender {
  final MetaApiConfig config;
  const ApiSender({this.config = const MetaApiConfig()});

  @override
  WaMode get mode => WaMode.api;

  @override
  WaCapabilities get capabilities => const WaCapabilities(
        automated: true,
        bulk: true,
        needsSession: false,
        inbound: true,
      );

  @override
  Future<WaStatus> status() async =>
      const WaStatus(WaConnState.unavailable, detail: 'قناة Meta الرسمية قيد التطوير');

  @override
  Future<WaSendResult> sendOne(WaOutgoing msg) async {
    // TODO(meta): نفّذ نداء Graph API (أو التوجيه عبر الباكند) هنا.
    throw const WaUnsupported('نمط Meta API غير مُفعَّل بعد');
  }

  @override
  Stream<WaBatchProgress> sendBulk(
    List<WaOutgoing> messages, {
    Duration delay = const Duration(seconds: 1),
  }) async* {
    // TODO(meta): الدفعة عبر Graph API (Meta لا يحتاج throttle يدوي كالخادم).
    throw const WaUnsupported('نمط Meta API غير مُفعَّل بعد');
  }

  @override
  void dispose() {}
}
