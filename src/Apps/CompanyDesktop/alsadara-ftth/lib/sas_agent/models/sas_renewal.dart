/// نماذج التجديد لوحدة «وكيل الساس».
///
/// - [SasRenewalCandidate]: مشترك قرب الانتهاء من
///   `GET /accounts/{id}/renewal/candidates`.
/// - [SasRenewalResult]: نتيجة تجديد لكل مشترك من
///   `POST /accounts/{id}/renewal/bulk` (سواء معاينة dryRun أو تنفيذ فعلي).
library;

/// مرشّح للتجديد (مشترك قرب الانتهاء).
class SasRenewalCandidate {
  final String id;
  final String username;
  final String name;
  final String? expiry;
  final String? profile;

  const SasRenewalCandidate({
    required this.id,
    required this.username,
    required this.name,
    this.expiry,
    this.profile,
  });

  /// اسم للعرض: الاسم إن وُجد وإلا اسم المستخدم.
  String get displayName {
    final n = name.trim();
    if (n.isNotEmpty) return n;
    return username.trim().isEmpty ? id : username.trim();
  }

  factory SasRenewalCandidate.fromJson(Map<String, dynamic> json) {
    return SasRenewalCandidate(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      expiry: (json['expiry'] ?? json['Expiry'])?.toString(),
      profile: (json['profile'] ?? json['Profile'])?.toString(),
    );
  }
}

/// نتيجة تجديد مشترك واحد (معاينة أو تنفيذ).
class SasRenewalResult {
  final String id;
  final bool ok;
  final String message;

  const SasRenewalResult({
    required this.id,
    required this.ok,
    required this.message,
  });

  factory SasRenewalResult.fromJson(Map<String, dynamic> json) {
    return SasRenewalResult(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      ok: (json['ok'] ?? json['Ok'] ?? false) == true,
      message: (json['message'] ?? json['Message'] ?? '').toString(),
    );
  }
}
