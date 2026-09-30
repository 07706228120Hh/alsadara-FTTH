/// المُرسِل عبر تطبيق/موقع واتساب (wa.me) — النمط `app`، مجاني ويدوي.
///
/// يفتح واتساب برسالة جاهزة؛ المستخدم يضغط «إرسال». لا تكلفة ولا مزوّد خارجي.
library;

import 'package:url_launcher/url_launcher.dart';

import '../core/wa_mode.dart';
import '../core/wa_sender.dart';
import '../models/wa_message.dart';
import '../models/wa_recipient.dart';

class AppSender implements WaSender {
  const AppSender();

  @override
  WaMode get mode => WaMode.app;

  @override
  WaCapabilities get capabilities => const WaCapabilities(
        automated: false, // يفتح فقط؛ الإرسال بضغط المستخدم
        bulk: false,
        needsSession: false,
      );

  @override
  Future<WaStatus> status() async => WaStatus.alwaysReady;

  /// يفتح محادثة واتساب مع الرقم برسالة مُعبّأة.
  @override
  Future<WaSendResult> sendOne(WaOutgoing msg) async {
    final n = msg.phone;
    if (n == null) {
      return WaSendResult.failure(msg, 'رقم غير صالح لواتساب');
    }
    final uri =
        Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(msg.text)}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok
          ? WaSendResult.success(msg, opened: true)
          : WaSendResult.failure(msg, 'تعذّر فتح واتساب');
    } catch (e) {
      return WaSendResult.failure(msg, 'تعذّر فتح واتساب: $e');
    }
  }

  /// يفتح كل رسالة تِباعاً بفاصل زمني. النمط يدوي — «فُتحت» لا «أُرسلت».
  /// الواجهة عادةً تفضّل النمط الخطوي (sendOne لكل صف)، وهذا خيار «افتح الكل».
  @override
  Stream<WaBatchProgress> sendBulk(
    List<WaOutgoing> messages, {
    Duration delay = const Duration(seconds: 3),
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
  void dispose() {}
}

/// دالة توافقية مختصرة (تُبقي النداءات القديمة `openWhatsApp` تعمل).
Future<bool> openWhatsApp(String phone, String message) async {
  final res = await const AppSender().sendOne(
    WaOutgoing(recipient: WaRecipient(name: '', rawPhone: phone), text: message),
  );
  return res.ok;
}
