/// نماذج المصادقة المشتركة
library;

/// استجابة تحديث التوكن - مشتركة بين جميع أنواع المستخدمين
class TokenRefreshResponse {
  final String token;
  final String refreshToken;
  final DateTime expiresAt;

  TokenRefreshResponse({
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory TokenRefreshResponse.fromJson(Map<String, dynamic> json) {
    return TokenRefreshResponse(
      token: json['token'] ?? '',
      refreshToken: json['refreshToken'] ?? '',
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.toIso8601String(),
      };
}
