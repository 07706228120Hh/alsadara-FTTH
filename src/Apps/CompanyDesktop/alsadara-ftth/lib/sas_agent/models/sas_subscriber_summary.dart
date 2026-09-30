/// ملخّص المشتركين المحلّي الموثوق — من
/// `GET /api/sas-agent/accounts/{id}/subscribers/summary`.
///
/// المصدر: قاعدة الصدارة (بعد المزامنة) لا لوحة الساس الحيّة؛ لذا الأرقام
/// موثوقة وثابتة. البوّابة قد تُرجِع الرد ملفوفاً بـ `data`، والحقول قد تأتي
/// snake_case أو camelCase — القراءة متساهلة (حقل مفقود = 0 / null).
///
/// عرض فقط — لا أسرار ولا استدعاءات API هنا.
library;

import 'sas_report.dart' show SasExpiryCounts;

class SasSubscriberSummary {
  /// إجمالي المشتركين المُزامَنين محليّاً.
  final int total;

  /// النشطون.
  final int active;

  /// المنتهون.
  final int expired;

  /// المتصلون الآن.
  final int online;

  /// عدّادات قرب/بعد الانتهاء (overdue/today/soon3/soon7).
  final SasExpiryCounts expiry;

  /// وقت آخر مزامنة محلية (null = لم تُزامَن بعد).
  final DateTime? lastSync;

  const SasSubscriberSummary({
    this.total = 0,
    this.active = 0,
    this.expired = 0,
    this.online = 0,
    this.expiry = const SasExpiryCounts(),
    this.lastSync,
  });

  /// ملخّص فارغ (كل الأرقام صفر) — يُستخدم كبديل بلا «-».
  static const empty = SasSubscriberSummary();

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  static dynamic _pick(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      final v = j[k];
      if (v != null) return v;
    }
    return null;
  }

  factory SasSubscriberSummary.fromJson(Map<String, dynamic> json) {
    // فكّ غلاف data/result/summary إن وُجد.
    Map<String, dynamic> j = json;
    final inner = json['data'] ?? json['result'] ?? json['summary'];
    if (inner is Map) {
      j = inner.map((k, v) => MapEntry(k.toString(), v));
    }

    // عدّادات الانتهاء: قد تأتي متداخلة تحت expiry، أو مسطّحة في الجذر.
    final rawExpiry = j['expiry'] ?? j['Expiry'];
    final expiry = rawExpiry is Map
        ? SasExpiryCounts.fromJson(rawExpiry.cast<String, dynamic>())
        : SasExpiryCounts.fromJson(j);

    final rawSync =
        _pick(j, ['last_sync', 'lastSync', 'synced_at', 'syncedAt', 'LastSync']);

    return SasSubscriberSummary(
      total: _int(_pick(j, ['total', 'totalUsers', 'count'])),
      active: _int(_pick(j, ['active', 'activeUsers'])),
      expired: _int(_pick(j, ['expired', 'expiredUsers'])),
      online: _int(_pick(j, ['online', 'onlineUsers'])),
      expiry: expiry,
      lastSync: (rawSync == null) ? null : DateTime.tryParse('$rawSync'),
    );
  }
}
