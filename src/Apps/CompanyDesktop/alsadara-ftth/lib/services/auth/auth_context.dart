import 'dart:convert';

/// يمثل سياق الهوية المستخرج من الـ JWT (Access Token)
class AuthContext {
  final Map<String, dynamic> payload;
  final String rawToken;
  AuthContext(this.payload, this.rawToken);

  factory AuthContext.fromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        throw const FormatException('Invalid JWT structure');
      }
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final map = json.decode(decoded) as Map<String, dynamic>;
      return AuthContext(map, token);
    } catch (_) {
      return AuthContext({}, token);
    }
  }

  DateTime? get expiryUtc {
    final exp = payload['exp'];
    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    }
    if (exp is double) {
      return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000,
          isUtc: true);
    }
    return null;
  }

  String? get accountId => payload['AccountId']?.toString();
  List<String> get realmRoles =>
      (payload['realm_access']?['roles'] as List?)?.cast<String>() ?? const [];
  Map<String, dynamic> get resourceAccess =>
      (payload['resource_access'] as Map?)?.cast<String, dynamic>() ?? const {};
  List<String> get accountRoles =>
      (resourceAccess['account']?['roles'] as List?)?.cast<String>() ??
      const [];
  List<String> get groups =>
      (payload['Groups'] as List?)?.cast<String>() ?? const [];

  bool hasRole(String role) =>
      realmRoles.contains(role) || accountRoles.contains(role);
  bool inGroup(String g) => groups.contains(g);

  /// زمن متبقٍ بالثواني لانتهاء التوكن (قد يرجع null إذا لم يتوفر exp)
  int? get remainingSeconds {
    final exp = expiryUtc;
    if (exp == null) return null;
    return exp.difference(DateTime.now().toUtc()).inSeconds;
  }
}
