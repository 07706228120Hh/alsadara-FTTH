/// نموذج حساب الساس — يطابق SasAccountDto في البوّابة `/api/sas-agent`.
///
/// ⚠️ أمن: هذا النموذج لا يحمل كلمة المرور إطلاقاً؛ كلمة المرور تُدخَل فقط
/// لحظة الإنشاء/التعديل وتُرسَل مباشرةً للبوّابة (لا تُخزَّن ولا تُطبَع).
library;

/// نوع حساب الساس (يُسلسَل نصّياً في الـ API عبر JsonStringEnumConverter).
enum SasAccountType {
  /// «صفحة وكيل» — حساب مدير (Manager) في نظام الساس؛ يفتح لوحة الوكيل.
  sasManager,

  /// «نظام الساس» — حساب مستخدم عادي في نظام الساس.
  sasUser,
}

extension SasAccountTypeX on SasAccountType {
  /// القيمة النصّية المرسَلة/المستقبَلة من الـ API (تطابق أسماء enum الخادم).
  String get apiValue {
    switch (this) {
      case SasAccountType.sasManager:
        return 'SasManager';
      case SasAccountType.sasUser:
        return 'SasUser';
    }
  }

  /// تسمية عربية للعرض.
  String get labelAr {
    switch (this) {
      case SasAccountType.sasManager:
        return 'صفحة وكيل (مدير)';
      case SasAccountType.sasUser:
        return 'نظام الساس (مستخدم)';
    }
  }

  /// يقبل صيغة الخادم النصّية أو الرقمية (توافقاً دفاعياً).
  static SasAccountType parse(dynamic raw) {
    if (raw == null) return SasAccountType.sasManager;
    final s = raw.toString().trim().toLowerCase();
    if (s == 'sasuser' || s == '1') return SasAccountType.sasUser;
    return SasAccountType.sasManager;
  }
}

/// حساب ساس واحد كما تعرضه البوّابة (بلا كلمة مرور).
class SasAccount {
  final String id;
  final String label;
  final String serverUrl;
  final String username;
  final SasAccountType accountType;
  final bool isActive;
  final DateTime? lastSyncAt;

  const SasAccount({
    required this.id,
    required this.label,
    required this.serverUrl,
    required this.username,
    required this.accountType,
    required this.isActive,
    this.lastSyncAt,
  });

  /// اسم للعرض: التسمية إن وُجدت وإلا اسم المستخدم.
  String get displayName =>
      label.trim().isNotEmpty ? label.trim() : username;

  factory SasAccount.fromJson(Map<String, dynamic> json) {
    DateTime? sync;
    final rawSync = json['lastSyncAt'] ?? json['LastSyncAt'];
    if (rawSync != null) {
      sync = DateTime.tryParse(rawSync.toString());
    }
    return SasAccount(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      label: (json['label'] ?? json['Label'] ?? '').toString(),
      serverUrl: (json['serverUrl'] ?? json['ServerUrl'] ?? '').toString(),
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      accountType: SasAccountTypeX.parse(
        json['accountType'] ?? json['AccountType'],
      ),
      isActive: (json['isActive'] ?? json['IsActive'] ?? true) == true,
      lastSyncAt: sync,
    );
  }
}
