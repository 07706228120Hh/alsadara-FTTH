import '../api_client.dart';
import '../api_config.dart';
import '../api_response.dart';
import 'auth_models.dart';

/// خدمة API للمصادقة (موظفي الشركات)
class AuthApi {
  final ApiClient _client;

  AuthApi([ApiClient? client]) : _client = client ?? ApiClient.instance;

  // ============================================
  // Company Employee Authentication
  // ============================================

  /// تسجيل دخول موظف الشركة
  Future<ApiResponse<CompanyLoginResponse>> loginEmployee({
    required String companyCode,
    required String username,
    required String password,
  }) async {
    return _client.post(
      ApiConfig.companyLogin,
      {
        'companyCode': companyCode,
        'username': username,
        'password': password,
      },
      (json) => CompanyLoginResponse.fromJson(json),
    );
  }

  /// تحديث التوكن
  Future<ApiResponse<TokenRefreshResponse>> refreshToken(
    String refreshToken,
  ) async {
    return _client.post(
      ApiConfig.companyRefreshToken,
      {'refreshToken': refreshToken},
      (json) => TokenRefreshResponse.fromJson(json),
    );
  }

  /// تسجيل الخروج
  Future<ApiResponse<bool>> logout() async {
    final response = await _client.post(
      '/companies/logout',
      {},
      (json) => true,
    );

    if (response.isSuccess) {
      _client.clearAuthToken();
    }

    return response;
  }

  /// تغيير كلمة المرور
  Future<ApiResponse<bool>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _client.post(
      '/companies/change-password',
      {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      (json) => true,
    );
  }

  /// طلب إعادة تعيين كلمة المرور
  Future<ApiResponse<bool>> requestPasswordReset(String email) async {
    return _client.post(
      '/companies/forgot-password',
      {'email': email},
      (json) => true,
    );
  }

  /// التحقق من صلاحية التوكن
  Future<ApiResponse<UserProfileResponse>> validateToken() async {
    return _client.get(
      '/companies/profile',
      (json) => UserProfileResponse.fromJson(json),
    );
  }
}

// ============================================
// Models
// ============================================

/// استجابة تسجيل دخول موظف الشركة
class CompanyLoginResponse {
  final CompanyUser user;
  final CompanyInfo company;
  final String token;
  final String refreshToken;
  final DateTime expiresAt;

  CompanyLoginResponse({
    required this.user,
    required this.company,
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory CompanyLoginResponse.fromJson(Map<String, dynamic> json) {
    return CompanyLoginResponse(
      user: CompanyUser.fromJson(json['user'] ?? {}),
      company: CompanyInfo.fromJson(json['company'] ?? {}),
      token: json['token'] ?? '',
      refreshToken: json['refreshToken'] ?? '',
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'])
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }
}

/// معلومات المستخدم (موظف الشركة)
class CompanyUser {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;
  final List<String> permissions;
  final bool isActive;
  final DateTime? lastLogin;

  CompanyUser({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    required this.role,
    required this.permissions,
    required this.isActive,
    this.lastLogin,
  });

  factory CompanyUser.fromJson(Map<String, dynamic> json) {
    return CompanyUser(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'],
      phone: json['phone'],
      role: json['role'] ?? 'Employee',
      permissions: (json['permissions'] as List?)?.cast<String>() ?? [],
      isActive: json['isActive'] ?? true,
      lastLogin:
          json['lastLogin'] != null ? DateTime.parse(json['lastLogin']) : null,
    );
  }

  /// التحقق من صلاحية معينة
  bool hasPermission(String permission) {
    return permissions.contains(permission) || role == 'Admin';
  }

  /// هل هو مدير الشركة
  bool get isAdmin => role == 'Admin';

  /// هل هو محاسب
  bool get isAccountant => role == 'Accountant' || isAdmin;

  /// هل هو فني
  bool get isTechnician => role == 'Technician' || isAdmin;
}

/// معلومات الشركة
class CompanyInfo {
  final String id;
  final String name;
  final String code;
  final String? logoUrl;
  final DateTime subscriptionEndDate;
  final int daysRemaining;
  final bool isExpired;
  final String subscriptionStatus;

  CompanyInfo({
    required this.id,
    required this.name,
    required this.code,
    this.logoUrl,
    required this.subscriptionEndDate,
    required this.daysRemaining,
    required this.isExpired,
    required this.subscriptionStatus,
  });

  factory CompanyInfo.fromJson(Map<String, dynamic> json) {
    return CompanyInfo(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? '',
      logoUrl: json['logoUrl'],
      subscriptionEndDate: json['subscriptionEndDate'] != null
          ? DateTime.parse(json['subscriptionEndDate'])
          : DateTime.now(),
      daysRemaining: json['daysRemaining'] ?? 0,
      isExpired: json['isExpired'] ?? false,
      subscriptionStatus: json['subscriptionStatus'] ?? 'Active',
    );
  }

  /// هل الاشتراك سينتهي قريباً (خلال 30 يوم)
  bool get isExpiringSoon => daysRemaining > 0 && daysRemaining <= 30;
}

/// استجابة ملف المستخدم
class UserProfileResponse {
  final CompanyUser user;
  final CompanyInfo company;

  UserProfileResponse({
    required this.user,
    required this.company,
  });

  factory UserProfileResponse.fromJson(Map<String, dynamic> json) {
    return UserProfileResponse(
      user: CompanyUser.fromJson(json['user'] ?? json),
      company: CompanyInfo.fromJson(json['company'] ?? {}),
    );
  }
}
