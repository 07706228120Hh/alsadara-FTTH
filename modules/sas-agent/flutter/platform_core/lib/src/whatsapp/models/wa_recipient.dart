/// مستلِم رسالة واتساب — اسم + رقم خام + متغيّرات لملء القالب.
library;

import '../core/wa_phone.dart';

/// مستلِم واحد. `raw` الرقم كما ورد من SAS (قد يكون غير مطبّع)؛ `vars` قيم
/// متغيّرات القالب (مثل الباقة/تاريخ الانتهاء) لهذا المستلِم تحديداً.
class WaRecipient {
  final String name;
  final String rawPhone;
  final Map<String, String> vars;

  const WaRecipient({
    required this.name,
    required this.rawPhone,
    this.vars = const {},
  });

  /// الرقم المطبّع (9647XXXXXXXXX) أو null إن تعذّر.
  String? get phone => normalizeIraqiPhone(rawPhone);

  /// هل يمكن مراسلته عبر واتساب؟
  bool get sendable => phone != null;

  /// متغيّرات القالب مع ضمان وجود {name}.
  Map<String, String> get templateVars => {
        'name': name.trim(),
        ...vars,
      };
}
