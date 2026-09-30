/// ملخّص لوحة الوكيل — يُبنى من استجابة `GET /accounts/{id}/dashboard`.
///
/// البوّابة تمرّر استجابة نظام الساس الخام؛ لذا نقرأ المفاتيح بمرونة
/// (total/active/expired/online/offline) مع بحث في `data` إن كانت مغلَّفة.
library;

class SasDashboard {
  final int? total;
  final int? active;
  final int? expired;
  final int? online;
  final int? offline;

  /// المفاتيح الأصلية للعرض التشخيصي عند الحاجة.
  final Map<String, dynamic> raw;

  const SasDashboard({
    this.total,
    this.active,
    this.expired,
    this.online,
    this.offline,
    this.raw = const {},
  });

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  factory SasDashboard.fromJson(Map<String, dynamic> json) {
    // فكّ التغليف الشائع: {data: {...}} أو {result: {...}}.
    Map<String, dynamic> d = json;
    final inner = json['data'] ?? json['result'] ?? json['summary'];
    if (inner is Map) {
      d = inner.map((k, v) => MapEntry(k.toString(), v));
    }
    return SasDashboard(
      total: _asInt(d['total'] ?? d['totalUsers'] ?? d['count']),
      active: _asInt(d['active'] ?? d['activeUsers']),
      expired: _asInt(d['expired'] ?? d['expiredUsers']),
      online: _asInt(d['online'] ?? d['onlineUsers']),
      offline: _asInt(d['offline'] ?? d['offlineUsers']),
      raw: d,
    );
  }
}
