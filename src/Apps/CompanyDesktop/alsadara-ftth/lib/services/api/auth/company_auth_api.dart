import 'dart:convert';

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

  /// تغيير كلمة المرور (Unified Auth)
  Future<ApiResponse<bool>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _client.post(
      '/api/v2/auth/change-password',
      {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      (json) => true,
    );
  }

  /// تحديث الملف الشخصي (Unified Auth)
  Future<ApiResponse<Map<String, dynamic>>> updateProfile({
    String? username,
    String? fullName,
    String? email,
    String? city,
    String? area,
    String? address,
  }) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (fullName != null) body['fullName'] = fullName;
    if (email != null) body['email'] = email;
    if (city != null) body['city'] = city;
    if (area != null) body['area'] = area;
    if (address != null) body['address'] = address;

    return _client.put(
      '/api/v2/auth/profile',
      body,
      (json) => json as Map<String, dynamic>,
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
    // دعم كلا التنسيقين: camelCase و PascalCase
    final companyJson = json['company'] ?? json['Company'] ?? {};
    final userJson = json['user'] ?? json['User'] ?? {};

    final company = CompanyInfo.fromJson(companyJson);
    final user = CompanyUser.fromJson(userJson);

    // ملاحظة: دمج صلاحيات المدير يتم الآن في VpsAuthService عبر PermissionManager

    return CompanyLoginResponse(
      user: user,
      company: company,
      token: json['token'] ?? json['Token'] ?? '',
      refreshToken: json['refreshToken'] ?? json['RefreshToken'] ?? '',
      expiresAt: (json['expiresAt'] ?? json['ExpiresAt']) != null
          ? DateTime.parse(json['expiresAt'] ?? json['ExpiresAt'])
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

  /// صلاحيات V2 الخام — النظام الأول والثاني
  final String? rawFirstSystemV2;
  final String? rawSecondSystemV2;
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
    this.rawFirstSystemV2,
    this.rawSecondSystemV2,
    required this.isActive,
    this.lastLogin,
  });

  factory CompanyUser.fromJson(Map<String, dynamic> json) {
    // قراءة V2 الخام فقط
    final firstSystemV2Str =
        (json['firstSystemPermissionsV2'] ?? json['FirstSystemPermissionsV2'])
            ?.toString();
    final secondSystemV2Str =
        (json['secondSystemPermissionsV2'] ?? json['SecondSystemPermissionsV2'])
            ?.toString();

    // بناء قائمة permissions من V2 (المفاتيح التي view==true)
    List<String> permissionsList = [];
    _extractViewPermissions(firstSystemV2Str, permissionsList);
    _extractViewPermissions(secondSystemV2Str, permissionsList);

    final role = json['role'] ?? json['Role'] ?? 'Employee';

    // استخراج الاسم واسم المستخدم (دعم camelCase و PascalCase)
    final id = json['id']?.toString() ?? json['Id']?.toString() ?? '';
    final phoneNumber = json['phoneNumber'] ?? json['PhoneNumber'];
    final username = json['username'] ?? json['Username'];
    final fullName = json['fullName'] ?? json['FullName'] ?? '';
    final email = json['email'] ?? json['Email'];
    final phone = phoneNumber ?? json['phone'] ?? json['Phone'];
    final isActive = json['isActive'] ?? json['IsActive'] ?? true;
    final lastLoginStr = json['lastLogin'] ?? json['LastLogin'];

    return CompanyUser(
      id: id,
      username: phoneNumber ?? username ?? '',
      fullName: fullName,
      email: email,
      phone: phone,
      role: role,
      permissions: permissionsList,
      rawFirstSystemV2: firstSystemV2Str,
      rawSecondSystemV2: secondSystemV2Str,
      isActive: isActive,
      lastLogin: lastLoginStr != null ? DateTime.parse(lastLoginStr) : null,
    );
  }

  /// استخراج مفاتيح الميزات التي view==true من V2 JSON
  static void _extractViewPermissions(
      String? v2JsonStr, List<String> target) {
    if (v2JsonStr == null || v2JsonStr.isEmpty || v2JsonStr == 'null') return;
    try {
      final decoded = jsonDecode(v2JsonStr) as Map<String, dynamic>;
      decoded.forEach((feature, value) {
        if (value is Map && value['view'] == true) {
          if (!target.contains(feature)) target.add(feature);
        } else if (value == true) {
          // بعض الحقول قد تكون bool مباشرة
          if (!target.contains(feature)) target.add(feature);
        }
      });
    } catch (_) {}
  }

  /// هل هو مدير الشركة
  bool get isAdmin =>
      role == 'CompanyAdmin' || role == 'Admin' || role == 'Manager';

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
  final Map<String, bool> enabledFirstSystemFeatures;
  final Map<String, bool> enabledSecondSystemFeatures;

  CompanyInfo({
    required this.id,
    required this.name,
    required this.code,
    this.logoUrl,
    required this.subscriptionEndDate,
    required this.daysRemaining,
    required this.isExpired,
    required this.subscriptionStatus,
    this.enabledFirstSystemFeatures = const {},
    this.enabledSecondSystemFeatures = const {},
  });

  factory CompanyInfo.fromJson(Map<String, dynamic> json) {
    // قراءة صلاحيات الشركة (دعم camelCase و PascalCase)
    Map<String, bool> firstFeatures = {};
    Map<String, bool> secondFeatures = {};

    final firstFeaturesStr = json['enabledFirstSystemFeatures'] ??
        json['EnabledFirstSystemFeatures'];
    if (firstFeaturesStr != null &&
        firstFeaturesStr is String &&
        firstFeaturesStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(firstFeaturesStr) as Map<String, dynamic>;
        firstFeatures = decoded.map((k, v) => MapEntry(k, v == true));
      } catch (_) {}
    } else if (firstFeaturesStr is Map) {
      firstFeatures = Map<String, bool>.from(
          firstFeaturesStr.map((k, v) => MapEntry(k.toString(), v == true)));
    }

    final secondFeaturesStr = json['enabledSecondSystemFeatures'] ??
        json['EnabledSecondSystemFeatures'];
    if (secondFeaturesStr != null &&
        secondFeaturesStr is String &&
        secondFeaturesStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(secondFeaturesStr) as Map<String, dynamic>;
        secondFeatures = decoded.map((k, v) => MapEntry(k, v == true));
      } catch (_) {}
    } else if (secondFeaturesStr is Map) {
      secondFeatures = Map<String, bool>.from(
          secondFeaturesStr.map((k, v) => MapEntry(k.toString(), v == true)));
    }

    // استخراج الحقول (دعم camelCase و PascalCase)
    final id = json['id']?.toString() ?? json['Id']?.toString() ?? '';
    final name = json['name'] ?? json['Name'] ?? '';
    final code = json['code'] ?? json['Code'] ?? '';
    final logoUrl = json['logoUrl'] ?? json['LogoUrl'];
    final subscriptionEndDateStr =
        json['subscriptionEndDate'] ?? json['SubscriptionEndDate'];
    final daysRemaining = json['daysRemaining'] ?? json['DaysRemaining'] ?? 0;
    final isExpired = json['isExpired'] ?? json['IsExpired'] ?? false;
    final subscriptionStatus =
        json['subscriptionStatus'] ?? json['SubscriptionStatus'] ?? 'Active';

    return CompanyInfo(
      id: id,
      name: name,
      code: code,
      logoUrl: logoUrl,
      subscriptionEndDate: subscriptionEndDateStr != null
          ? DateTime.parse(subscriptionEndDateStr)
          : DateTime.now(),
      daysRemaining: daysRemaining,
      isExpired: isExpired,
      subscriptionStatus: subscriptionStatus,
      enabledFirstSystemFeatures: firstFeatures,
      enabledSecondSystemFeatures: secondFeatures,
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
    final userJson = json['user'] ?? json['User'] ?? json;
    final companyJson = json['company'] ?? json['Company'] ?? {};
    return UserProfileResponse(
      user: CompanyUser.fromJson(userJson),
      company: CompanyInfo.fromJson(companyJson),
    );
  }
}
