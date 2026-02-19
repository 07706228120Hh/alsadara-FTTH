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
    var user = CompanyUser.fromJson(userJson);

    // إذا كان مدير الشركة (CompanyAdmin)، يحصل على صلاحيات الشركة
    if (user.isAdmin) {
      // دمج صلاحيات الشركة مع صلاحيات المستخدم
      final mergedFirstPerms =
          Map<String, bool>.from(user.firstSystemPermissions);
      final mergedSecondPerms =
          Map<String, bool>.from(user.secondSystemPermissions);
      final mergedPermissions = List<String>.from(user.permissions);

      // إضافة صلاحيات الشركة
      company.enabledFirstSystemFeatures.forEach((key, value) {
        if (value == true) {
          mergedFirstPerms[key] = true;
          if (!mergedPermissions.contains(key)) {
            mergedPermissions.add(key);
          }
        }
      });

      company.enabledSecondSystemFeatures.forEach((key, value) {
        if (value == true) {
          mergedSecondPerms[key] = true;
          if (!mergedPermissions.contains(key)) {
            mergedPermissions.add(key);
          }
        }
      });

      // إنشاء مستخدم جديد بالصلاحيات المدمجة
      user = CompanyUser(
        id: user.id,
        username: user.username,
        fullName: user.fullName,
        email: user.email,
        phone: user.phone,
        role: user.role,
        permissions: mergedPermissions,
        firstSystemPermissions: mergedFirstPerms,
        secondSystemPermissions: mergedSecondPerms,
        rawFirstSystemV1: user.rawFirstSystemV1,
        rawFirstSystemV2: user.rawFirstSystemV2,
        rawSecondSystemV1: user.rawSecondSystemV1,
        rawSecondSystemV2: user.rawSecondSystemV2,
        isActive: user.isActive,
        lastLogin: user.lastLogin,
      );
    }

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
  final Map<String, bool> firstSystemPermissions;
  final Map<String, bool> secondSystemPermissions;

  /// صلاحيات V2 الخام — النظام الأول والثاني
  final String? rawFirstSystemV2;
  final String? rawSecondSystemV2;
  final String? rawFirstSystemV1;
  final String? rawSecondSystemV1;
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
    required this.firstSystemPermissions,
    required this.secondSystemPermissions,
    this.rawFirstSystemV2,
    this.rawSecondSystemV2,
    this.rawFirstSystemV1,
    this.rawSecondSystemV1,
    required this.isActive,
    this.lastLogin,
  });

  factory CompanyUser.fromJson(Map<String, dynamic> json) {
    // استخراج الصلاحيات من JSON strings
    Map<String, bool> firstPerms = {};
    Map<String, bool> secondPerms = {};
    List<String> permissionsList = [];

    // ============ قراءة صلاحيات V1 أو V2 للنظام الأول ============
    final firstSystemStr =
        json['firstSystemPermissions'] ?? json['FirstSystemPermissions'];
    final firstSystemV2Str =
        json['firstSystemPermissionsV2'] ?? json['FirstSystemPermissionsV2'];

    // أولوية V2 إذا كان V1 فارغ
    final firstSourceStr = (firstSystemStr != null &&
            firstSystemStr.toString().isNotEmpty &&
            firstSystemStr.toString() != 'null')
        ? firstSystemStr
        : firstSystemV2Str;

    if (firstSourceStr != null &&
        firstSourceStr is String &&
        firstSourceStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(firstSourceStr) as Map<String, dynamic>;
        // التعامل مع V2 format: {"feature": {"view": true, "add": true, ...}}
        decoded.forEach((feature, value) {
          if (value is Map) {
            // V2 format - نحول إلى V1 (إذا view=true يعني الميزة مفعلة)
            final hasViewPermission = value['view'] == true;
            firstPerms[feature] = hasViewPermission;
            if (hasViewPermission) permissionsList.add(feature);
          } else if (value == true) {
            // V1 format
            firstPerms[feature] = true;
            permissionsList.add(feature);
          }
        });
      } catch (_) {}
    }

    // ============ قراءة صلاحيات V1 أو V2 للنظام الثاني ============
    final secondSystemStr =
        json['secondSystemPermissions'] ?? json['SecondSystemPermissions'];
    final secondSystemV2Str =
        json['secondSystemPermissionsV2'] ?? json['SecondSystemPermissionsV2'];

    // أولوية V2 إذا كان V1 فارغ
    final secondSourceStr = (secondSystemStr != null &&
            secondSystemStr.toString().isNotEmpty &&
            secondSystemStr.toString() != 'null')
        ? secondSystemStr
        : secondSystemV2Str;

    if (secondSourceStr != null &&
        secondSourceStr is String &&
        secondSourceStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(secondSourceStr) as Map<String, dynamic>;
        // التعامل مع V2 format: {"feature": {"view": true, "add": true, ...}}
        decoded.forEach((feature, value) {
          if (value is Map) {
            // V2 format - نحول إلى V1 (إذا view=true يعني الميزة مفعلة)
            final hasViewPermission = value['view'] == true;
            secondPerms[feature] = hasViewPermission;
            if (hasViewPermission && !permissionsList.contains(feature)) {
              permissionsList.add(feature);
            }
          } else if (value == true) {
            // V1 format
            secondPerms[feature] = true;
            if (!permissionsList.contains(feature)) {
              permissionsList.add(feature);
            }
          }
        });
      } catch (_) {}
    }

    // ملاحظة: مدير الشركة (CompanyAdmin) يحصل على صلاحيات الشركة
    // وليس جميع الصلاحيات - سيتم دمجها في CompanyLoginResponse
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
      firstSystemPermissions: firstPerms,
      secondSystemPermissions: secondPerms,
      rawFirstSystemV1: firstSystemStr?.toString(),
      rawFirstSystemV2: firstSystemV2Str?.toString(),
      rawSecondSystemV1: secondSystemStr?.toString(),
      rawSecondSystemV2: secondSystemV2Str?.toString(),
      isActive: isActive,
      lastLogin: lastLoginStr != null ? DateTime.parse(lastLoginStr) : null,
    );
  }

  /// التحقق من صلاحية معينة
  bool hasPermission(String permission) {
    return permissions.contains(permission) ||
        firstSystemPermissions[permission] == true ||
        secondSystemPermissions[permission] == true;
  }

  /// هل هو مدير الشركة
  bool get isAdmin => role == 'CompanyAdmin' || role == 'Admin';

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
