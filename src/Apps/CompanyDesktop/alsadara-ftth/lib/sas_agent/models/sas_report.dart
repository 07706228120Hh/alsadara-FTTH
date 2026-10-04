/// نماذج «التصريح/البلنك» + «المقاطعة» + نتائج الاختبار/المزامنة + عدّادات الانتهاء
/// لوحدة «وكيل الساس». تطابق نقاط البوّابة `/api/sas-agent/accounts/{id}/...`.
///
/// كل النماذج قراءة-فقط للعرض؛ لا تحمل أسراراً ولا كلمات مرور.
library;

/// عدّادات المشتركين قرب/بعد الانتهاء — تُعاد من `sync` و`subscribers-local`.
///
/// - [overdue] منتهون (مضى تاريخهم)
/// - [today] ينتهون اليوم
/// - [soon3] خلال ٣ أيام
/// - [soon7] خلال أسبوع
class SasExpiryCounts {
  final int overdue;
  final int today;
  final int soon3;
  final int soon7;

  const SasExpiryCounts({
    this.overdue = 0,
    this.today = 0,
    this.soon3 = 0,
    this.soon7 = 0,
  });

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  factory SasExpiryCounts.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const {};
    return SasExpiryCounts(
      overdue: _int(j['overdue'] ?? j['Overdue']),
      today: _int(j['today'] ?? j['Today']),
      soon3: _int(j['soon3'] ?? j['Soon3'] ?? j['soon_3']),
      soon7: _int(j['soon7'] ?? j['Soon7'] ?? j['soon_7']),
    );
  }

  bool get isEmpty => overdue == 0 && today == 0 && soon3 == 0 && soon7 == 0;
}

/// نتيجة اختبار الاتصال بحساب الساس — `POST accounts/{id}/test`.
class SasTestResult {
  final bool ok;
  final String message;
  final int? subscribersCount;

  const SasTestResult({
    required this.ok,
    required this.message,
    this.subscribersCount,
  });

  factory SasTestResult.fromJson(Map<String, dynamic> json) {
    final rawCount = json['subscribers_count'] ??
        json['subscribersCount'] ??
        json['count'];
    return SasTestResult(
      ok: json['ok'] == true || json['success'] == true,
      message: (json['message'] ?? json['error'] ?? '').toString(),
      subscribersCount:
          rawCount == null ? null : int.tryParse('$rawCount'),
    );
  }
}

/// نتيجة المزامنة المحلية — `POST accounts/{id}/sync`.
class SasSyncResult {
  final int count;
  final SasExpiryCounts expiry;
  final DateTime? syncedAt;

  const SasSyncResult({
    required this.count,
    required this.expiry,
    this.syncedAt,
  });

  factory SasSyncResult.fromJson(Map<String, dynamic> json) {
    final rawSync = json['synced_at'] ?? json['syncedAt'];
    return SasSyncResult(
      count: json['count'] is num
          ? (json['count'] as num).toInt()
          : int.tryParse('${json['count'] ?? ''}') ?? 0,
      expiry: SasExpiryCounts.fromJson(
          (json['expiry'] as Map?)?.cast<String, dynamic>()),
      syncedAt: rawSync == null ? null : DateTime.tryParse('$rawSync'),
    );
  }
}

/// صفحة مشتركين محليّين — `GET accounts/{id}/subscribers-local`.
class SasLocalSubscribersPage {
  final int total;
  final int page;
  final int count;
  final SasExpiryCounts expiry;
  final List<Map<String, dynamic>> subscribers;

  const SasLocalSubscribersPage({
    required this.total,
    required this.page,
    required this.count,
    required this.expiry,
    required this.subscribers,
  });

  factory SasLocalSubscribersPage.fromJson(Map<String, dynamic> json) {
    final list = json['subscribers'] ?? json['data'] ?? json['rows'];
    return SasLocalSubscribersPage(
      total: json['total'] is num
          ? (json['total'] as num).toInt()
          : int.tryParse('${json['total'] ?? ''}') ?? 0,
      page: json['page'] is num
          ? (json['page'] as num).toInt()
          : int.tryParse('${json['page'] ?? ''}') ?? 1,
      count: json['count'] is num
          ? (json['count'] as num).toInt()
          : int.tryParse('${json['count'] ?? ''}') ?? 0,
      expiry: SasExpiryCounts.fromJson(
          (json['expiry'] as Map?)?.cast<String, dynamic>()),
      subscribers: list is List
          ? list
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList()
          : const [],
    );
  }
}

/// تصريح وكيل واحد — عنصر من `GET accounts/{id}/reports` و ناتج `POST report`.
class SasAgentReport {
  final String id;
  final int declaredTotal;
  final int declaredActive;
  final String note;
  final DateTime? createdAt;

  const SasAgentReport({
    required this.id,
    required this.declaredTotal,
    required this.declaredActive,
    required this.note,
    this.createdAt,
  });

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  factory SasAgentReport.fromJson(Map<String, dynamic> json) {
    final rawTs = json['createdAt'] ??
        json['created_at'] ??
        json['CreatedAt'] ??
        json['timestamp'];
    return SasAgentReport(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      declaredTotal: _int(json['declaredTotal'] ??
          json['declared_total'] ??
          json['DeclaredTotal']),
      declaredActive: _int(json['declaredActive'] ??
          json['declared_active'] ??
          json['DeclaredActive']),
      note: (json['note'] ?? json['Note'] ?? '').toString(),
      createdAt: rawTs == null ? null : DateTime.tryParse('$rawTs'),
    );
  }
}

/// حكم المقاطعة (البلنك) بين المصرّح والفعلي.
enum SasVerdict { matched, companySuspicious, agentSuspicious, noReport }

extension SasVerdictX on SasVerdict {
  /// يحوّل نصّ الخادم إلى تعداد.
  static SasVerdict parse(dynamic raw) {
    final s = (raw ?? '').toString().trim().toLowerCase();
    switch (s) {
      case 'matched':
        return SasVerdict.matched;
      case 'company_suspicious':
      case 'companysuspicious':
        return SasVerdict.companySuspicious;
      case 'agent_suspicious':
      case 'agentsuspicious':
        return SasVerdict.agentSuspicious;
      default:
        return SasVerdict.noReport;
    }
  }

  /// تسمية عربية قصيرة (للشارة).
  String get labelAr {
    switch (this) {
      case SasVerdict.matched:
        return 'مطابق';
      case SasVerdict.companySuspicious:
        return 'اشتباه بالشركة';
      case SasVerdict.agentSuspicious:
        return 'اشتباه بالوكيل';
      case SasVerdict.noReport:
        return 'لا تصريح';
    }
  }

  /// شرح عربي مفصّل (يظهر أسفل الشارة).
  String get explanationAr {
    switch (this) {
      case SasVerdict.matched:
        return 'الأرقام متطابقة ضمن الهامش المسموح — تصريحك يوافق ما تُظهره الشركة.';
      case SasVerdict.companySuspicious:
        return 'تصريحك أعلى مما تُظهره الشركة — قد تكون هناك خطوط غير مسجّلة باسمك لدى الشركة.';
      case SasVerdict.agentSuspicious:
        return 'تصريحك أقل مما تنسبه الشركة إليك — راجع قائمة مشتركيك.';
      case SasVerdict.noReport:
        return 'لم تُصرّح بعد — أرسل تصريحك ليُقارَن آلياً مع بيانات الشركة.';
    }
  }
}

/// نتيجة المقاطعة — `GET accounts/{id}/reconciliation`.
class SasReconciliation {
  final int declared;
  final int actual;
  final int diff;
  final SasVerdict verdict;
  final String source;

  const SasReconciliation({
    required this.declared,
    required this.actual,
    required this.diff,
    required this.verdict,
    required this.source,
  });

  static int _int(dynamic v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  factory SasReconciliation.fromJson(Map<String, dynamic> json) {
    return SasReconciliation(
      declared: _int(json['declared'] ?? json['Declared']),
      actual: _int(json['actual'] ?? json['Actual']),
      diff: _int(json['diff'] ?? json['Diff']),
      verdict: SasVerdictX.parse(json['verdict'] ?? json['Verdict']),
      source: (json['source'] ?? json['Source'] ?? '').toString(),
    );
  }
}
