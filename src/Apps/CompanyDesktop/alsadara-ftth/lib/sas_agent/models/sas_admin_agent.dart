/// نماذج «إدارة الوكلاء» (البلنك الموحّد) للأدمن — تطابق نقطة البوّابة
/// `GET /api/sas-agent/admin/agents`.
///
/// كلّ النماذج قراءة-فقط للعرض؛ لا تحمل أسراراً ولا كلمات مرور. الـ fromJson
/// متساهل: أي حقل مفقود = 0/null (لا ينهار أمام رد جزئي أو مقاطعة null).
library;

import 'sas_report.dart' show SasVerdict, SasVerdictX;

/// أداة داخلية: تحويل آمن لعدد صحيح (يقبل رقماً أو نصاً).
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// مقاطعة/مطابقة حساب ساس واحد (المُصرَّح مقابل الفعلي) — قد تكون `null` كاملةً
/// من الخادم إذا تعذّرت خدمة الساس (تُعرَض حينها كـ «تعذّر جلب المقاطعة»).
class SasAdminReconciliation {
  final int declaredTotal;
  final int declaredActive;
  final int actualTotal;
  final int actualActive;
  final int diff;
  final SasVerdict verdict;
  final DateTime? lastSync;

  const SasAdminReconciliation({
    this.declaredTotal = 0,
    this.declaredActive = 0,
    this.actualTotal = 0,
    this.actualActive = 0,
    this.diff = 0,
    this.verdict = SasVerdict.noReport,
    this.lastSync,
  });

  factory SasAdminReconciliation.fromJson(Map<String, dynamic> json) {
    final rawSync = json['lastSync'] ?? json['last_sync'] ?? json['LastSync'];
    return SasAdminReconciliation(
      declaredTotal: _int(json['declaredTotal'] ?? json['declared_total']),
      declaredActive: _int(json['declaredActive'] ?? json['declared_active']),
      actualTotal: _int(json['actualTotal'] ?? json['actual_total']),
      actualActive: _int(json['actualActive'] ?? json['actual_active']),
      diff: _int(json['diff'] ?? json['Diff']),
      verdict: SasVerdictX.parse(json['verdict'] ?? json['Verdict']),
      lastSync: rawSync == null ? null : DateTime.tryParse('$rawSync'),
    );
  }
}

/// حساب ساس واحد ضمن وكيل (بلا أسرار) + مقاطعته (قد تكون null).
class SasAdminAccount {
  final String id;
  final String label;
  final String serverUrl;
  final bool isActive;

  /// المقاطعة — `null` إذا تعذّرت خدمة الساس لهذا الحساب.
  final SasAdminReconciliation? reconciliation;

  const SasAdminAccount({
    required this.id,
    required this.label,
    required this.serverUrl,
    required this.isActive,
    this.reconciliation,
  });

  /// اسم للعرض: التسمية إن وُجدت وإلا معرّف مختصر.
  String get displayLabel => label.trim().isNotEmpty ? label.trim() : id;

  /// هل توفّرت مقاطعة صالحة (خدمة الساس متاحة)؟
  bool get hasReconciliation => reconciliation != null;

  factory SasAdminAccount.fromJson(Map<String, dynamic> json) {
    final rawRecon = json['reconciliation'] ?? json['Reconciliation'];
    return SasAdminAccount(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      label: (json['label'] ?? json['Label'] ?? '').toString(),
      serverUrl: (json['serverUrl'] ?? json['ServerUrl'] ?? '').toString(),
      isActive: (json['isActive'] ?? json['IsActive'] ?? true) == true,
      reconciliation: rawRecon is Map
          ? SasAdminReconciliation.fromJson(rawRecon.cast<String, dynamic>())
          : null,
    );
  }
}

/// مجاميع وكيل واحد: عدد الحسابات + مجموع المُصرَّح + مجموع الفعلي.
class SasAdminTotals {
  final int accounts;
  final int declared;
  final int actual;

  const SasAdminTotals({
    this.accounts = 0,
    this.declared = 0,
    this.actual = 0,
  });

  /// الفارق الإجمالي (فعلي − مصرَّح) — موجب يعني «الشركة تُظهر أكثر».
  int get diff => actual - declared;

  factory SasAdminTotals.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const {};
    return SasAdminTotals(
      accounts: _int(j['accounts'] ?? j['Accounts']),
      declared: _int(j['declared'] ?? j['Declared']),
      actual: _int(j['actual'] ?? j['Actual']),
    );
  }
}

/// وكيل واحد (مالك حسابات ساس) ضمن الشركة + حساباته + مجاميعه.
class SasAdminAgent {
  final String userId;
  final String fullName;
  final String username;
  final List<SasAdminAccount> accounts;
  final SasAdminTotals totals;

  const SasAdminAgent({
    required this.userId,
    required this.fullName,
    required this.username,
    required this.accounts,
    required this.totals,
  });

  /// اسم للعرض: الاسم الكامل إن وُجد وإلا اسم المستخدم وإلا معرّف مختصر.
  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (username.trim().isNotEmpty) return username.trim();
    return userId;
  }

  /// أحكام حسابات هذا الوكيل التي توفّرت لها مقاطعة (لتصنيف مطابق/مشبوه).
  Iterable<SasVerdict> get verdicts => accounts
      .where((a) => a.reconciliation != null)
      .map((a) => a.reconciliation!.verdict);

  factory SasAdminAgent.fromJson(Map<String, dynamic> json) {
    final rawAccounts = json['accounts'] ?? json['Accounts'];
    final accounts = rawAccounts is List
        ? rawAccounts
            .whereType<Map>()
            .map((e) => SasAdminAccount.fromJson(e.cast<String, dynamic>()))
            .toList()
        : <SasAdminAccount>[];
    final rawTotals = json['totals'] ?? json['Totals'];
    return SasAdminAgent(
      userId: (json['userId'] ?? json['UserId'] ?? '').toString(),
      fullName: (json['fullName'] ?? json['FullName'] ?? '').toString(),
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      accounts: accounts,
      totals: SasAdminTotals.fromJson(
        rawTotals is Map ? rawTotals.cast<String, dynamic>() : null,
      ),
    );
  }
}
