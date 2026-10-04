/// مشترك ساس — يُبنى من استجابة `GET /accounts/{id}/subscribers` (تمرير خام).
///
/// نقرأ المفاتيح بمرونة لأن الشكل يعتمد على نظام الساس الخارجي.
library;

class SasSubscriber {
  final String username;
  final String firstName;
  final String lastName;
  final String profile;
  final String? expiration;
  final dynamic status;
  final bool online;

  final Map<String, dynamic> raw;

  const SasSubscriber({
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.profile,
    this.expiration,
    this.status,
    this.online = false,
    this.raw = const {},
  });

  /// معرّف المشترك في نظام الساس (uid) — يُستخدم لفتح التفاصيل/الإجراءات.
  /// المصدر الحيّ يستخدم `id`؛ المصدر المحلي (local_subscribers) يستخدم `sub_id`.
  /// يعيد نصاً فارغاً إن غاب المعرّف.
  String get id {
    final v = raw['id'] ??
        raw['sub_id'] ??
        raw['subId'] ??
        raw['user_id'] ??
        raw['userId'] ??
        raw['Id'];
    final s = v?.toString() ?? '';
    return (s == '0') ? '' : s; // 0 = مُدخَل يدوي بلا معرّف ساس
  }

  /// الاسم الكامل (قد يكون فارغاً).
  String get fullName => ('$firstName $lastName').trim();

  /// اسم للعرض: الاسم الكامل إن وُجد وإلا اسم المستخدم.
  String get displayName => fullName.isNotEmpty ? fullName : username;

  /// تسمية اسم الباقة.
  String get profileLabel => profile.trim().isEmpty ? '-' : profile.trim();

  /// هل المشترك نشط؟ (يتحمّل bool أو نص مثل 'active').
  bool get isActive {
    if (status is bool) return status as bool;
    final s = status?.toString().toLowerCase() ?? '';
    return s == 'true' || s == 'active' || s == '1' || s == 'online';
  }

  static String _profileName(Map<String, dynamic> row) {
    final p = row['profile_details'] ?? row['profileDetails'];
    if (p is Map && p['name'] != null) return '${p['name']}';
    return '${row['profile_name'] ?? row['user_profile_name'] ?? row['profile_id'] ?? row['profile'] ?? ''}';
  }

  factory SasSubscriber.fromJson(Map<String, dynamic> json) {
    final onlineRaw = json['online_status'] ?? json['online'];
    return SasSubscriber(
      username: (json['username'] ?? json['user'] ?? '').toString(),
      // المصدر الحيّ: firstname/lastname؛ المصدر المحلي: حقل `name` مفرد.
      firstName:
          (json['firstname'] ?? json['firstName'] ?? json['name'] ?? '')
              .toString(),
      lastName: (json['lastname'] ?? json['lastName'] ?? '').toString(),
      profile: _profileName(json),
      expiration:
          (json['expiration'] ?? json['expiry'] ?? json['expire_date'])
              ?.toString(),
      status: json['status'] ?? json['enabled'],
      online: onlineRaw == true || onlineRaw?.toString() == 'true',
      raw: json,
    );
  }
}
