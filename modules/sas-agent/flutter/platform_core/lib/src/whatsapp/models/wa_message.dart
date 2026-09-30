/// نماذج الرسالة الصادرة ونتيجة الإرسال وتقدّم الدفعة.
///
/// هذه أنواع خالصة (بلا اعتماد على Flutter) يتشاركها كل المُرسِلات والواجهة.
library;

import 'wa_recipient.dart';

/// رسالة صادرة جاهزة: مستلِم + نصّ مُركَّب (بعد ملء القالب).
class WaOutgoing {
  final WaRecipient recipient;
  final String text;

  const WaOutgoing({required this.recipient, required this.text});

  String? get phone => recipient.phone;
}

/// نتيجة إرسال رسالة واحدة.
class WaSendResult {
  final WaOutgoing message;
  final bool ok;

  /// للأنماط اليدوية (app): يعني «فُتحت المحادثة» لا «أُرسلت» فعلاً.
  final bool opened;
  final String? error;

  const WaSendResult({
    required this.message,
    required this.ok,
    this.opened = false,
    this.error,
  });

  factory WaSendResult.success(WaOutgoing m, {bool opened = false}) =>
      WaSendResult(message: m, ok: true, opened: opened);

  factory WaSendResult.failure(WaOutgoing m, String error) =>
      WaSendResult(message: m, ok: false, error: error);
}

/// لقطة تقدّم أثناء إرسال دفعة — تُبثّ من `WaSender.sendBulk`.
class WaBatchProgress {
  final int total;
  final int sent;
  final int failed;

  /// فهرس الرسالة الجارية (1-based)، و0 قبل البدء.
  final int current;
  final WaSendResult? last;
  final bool done;

  const WaBatchProgress({
    required this.total,
    this.sent = 0,
    this.failed = 0,
    this.current = 0,
    this.last,
    this.done = false,
  });

  int get processed => sent + failed;
  double get fraction => total == 0 ? 0 : processed / total;

  WaBatchProgress copyWith({
    int? sent,
    int? failed,
    int? current,
    WaSendResult? last,
    bool? done,
  }) =>
      WaBatchProgress(
        total: total,
        sent: sent ?? this.sent,
        failed: failed ?? this.failed,
        current: current ?? this.current,
        last: last ?? this.last,
        done: done ?? this.done,
      );
}

/// تقرير نهائي مختصر لدفعة (للعرض/السجل).
class WaBatchReport {
  final int total;
  final int sent;
  final int failed;
  final int skipped; // أرقام غير صالحة استُبعدت قبل الإرسال

  const WaBatchReport({
    required this.total,
    required this.sent,
    required this.failed,
    this.skipped = 0,
  });
}
