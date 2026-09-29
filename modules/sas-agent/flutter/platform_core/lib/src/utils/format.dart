import 'package:intl/intl.dart';

/// تنسيقات عربية موحّدة.
class Fmt {
  static final _num = NumberFormat.decimalPattern('ar');
  static final _numEn = NumberFormat.decimalPattern('en');

  /// أرقام بفواصل آلاف (أرقام لاتينية — أوضح في الجداول).
  static String n(num v) => _numEn.format(v);
  static String nAr(num v) => _num.format(v);

  static String date(DateTime? d) => d == null ? '—' : DateFormat('yyyy/MM/dd', 'en').format(d.toLocal());
  static String dateTime(DateTime? d) =>
      d == null ? '—' : DateFormat('yyyy/MM/dd HH:mm', 'en').format(d.toLocal());

  /// «قبل 5 دقائق» / «قبل 3 أيام».
  static String ago(DateTime? d) {
    if (d == null) return '—';
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
    return date(d);
  }

  /// نسبة مئوية آمنة.
  static String pct(num part, num whole) => whole == 0 ? '0%' : '${(part * 100 / whole).round()}%';

  /// إخفاء وسط رقم الهاتف: 9647701234567 → 0770****567
  static String maskPhone(String p) {
    if (p.length < 7) return p;
    final local = p.startsWith('964') ? '0${p.substring(3)}' : p;
    return '${local.substring(0, 4)}****${local.substring(local.length - 3)}';
  }
}
