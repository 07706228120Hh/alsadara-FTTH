/// الواجهة المجرّدة لكل مُرسِلات واتساب — العقد الذي يوحّد الأنماط الأربعة.
///
/// إضافة نمط جديد مستقبلاً (Meta API) = تنفيذ `WaSender` جديد فقط؛ لا تتغيّر
/// الواجهة ولا شاشات الإرسال (تتكيّف عبر `WaCapabilities`).
library;

import '../models/wa_message.dart';
import 'wa_mode.dart';

/// قدرات المُرسِل — الواجهة تتكيّف بناءً عليها (لا تفترض سلوكاً بعينه).
class WaCapabilities {
  /// يرسل فعلياً بلا تدخّل يدوي (server/api). إن كان false فالإرسال «يفتح» فقط.
  final bool automated;

  /// يدعم إرسالاً جماعياً حقيقياً بضغطة واحدة.
  final bool bulk;

  /// يحتاج جلسة/ربطاً (مسح QR للخادم) قبل العمل.
  final bool needsSession;

  /// يستطيع استقبال الردود الواردة (سجل محادثات) — مؤجّل.
  final bool inbound;

  const WaCapabilities({
    required this.automated,
    required this.bulk,
    this.needsSession = false,
    this.inbound = false,
  });
}

/// حالة اتصال/جاهزية المُرسِل.
enum WaConnState { ready, needsQr, connecting, disconnected, unavailable }

class WaStatus {
  final WaConnState state;

  /// رقم الهاتف المرتبط (للخادم بعد الربط)، إن وُجد.
  final String? phone;
  final String? detail;

  const WaStatus(this.state, {this.phone, this.detail});

  bool get ready => state == WaConnState.ready;

  /// النمط اليدوي (app) جاهز دائماً بلا جلسة.
  static const alwaysReady = WaStatus(WaConnState.ready);
}

/// العقد الموحّد. كل نمط ينفّذه؛ الواجهة تتعامل مع `WaSender` لا مع نمط بعينه.
abstract class WaSender {
  WaMode get mode;
  WaCapabilities get capabilities;

  /// جاهزية المُرسِل الآن (app: جاهز دائماً · server: يفحص الجلسة).
  Future<WaStatus> status();

  /// يرسل/يفتح رسالة واحدة.
  Future<WaSendResult> sendOne(WaOutgoing msg);

  /// يرسل دفعة ويبثّ التقدّم. للأنماط اليدوية يعالجها المُرسِل خطوةً بخطوة؛
  /// للأنماط الآلية يفوّضها للخادم. `delay` الفاصل بين الرسائل (throttle).
  Stream<WaBatchProgress> sendBulk(
    List<WaOutgoing> messages, {
    Duration delay = const Duration(seconds: 5),
  });

  /// تحرير الموارد (اتصالات HTTP). افتراضياً لا شيء.
  void dispose() {}
}

/// استثناء نمط غير مدعوم بعد (يُستخدم في قابس Meta المؤجّل).
class WaUnsupported implements Exception {
  final String message;
  const WaUnsupported([this.message = 'هذا النمط غير مُفعَّل بعد']);
  @override
  String toString() => message;
}
