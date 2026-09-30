/// تطبيع أرقام الهاتف العراقية إلى صيغة واتساب الدولية.
///
/// وحدة مستقلّة صغيرة (مسؤولية واحدة) يُعاد استخدامها في كل المُرسِلات والواجهة.
library;

/// يطبّع رقم هاتف عراقياً إلى صيغة واتساب الدولية (9647XXXXXXXXX). يُعيد null إن تعذّر.
///
/// يعالج: `07XXXXXXXXX` · `+964...` · `00964...` · أرقاماً متعددة مفصولة
/// بفاصلة/شرطة/مسافة (يأخذ أوّل رقم صالح).
String? normalizeIraqiPhone(String raw) {
  if (raw.trim().isEmpty) return null;
  // قد يحوي الحقل أكثر من رقم ("077... - 078...") — خذ أوّل جزء رقمه ≥ 10 خانات
  final parts = raw.split(RegExp(r'[\s,/]+'));
  String pick = raw;
  for (final p in parts) {
    if (p.replaceAll(RegExp(r'\D'), '').length >= 10) {
      pick = p;
      break;
    }
  }
  var d = pick.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00964')) d = d.substring(5);
  if (d.startsWith('964')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  // بعد التطبيع يجب أن يبدأ بـ 7 وطوله 10 (7XXXXXXXXX)
  if (d.length == 10 && d.startsWith('7')) return '964$d';
  return null;
}

/// هل الرقم قابل للإرسال عبر واتساب بعد التطبيع؟
bool isSendableIraqiPhone(String raw) => normalizeIraqiPhone(raw) != null;
