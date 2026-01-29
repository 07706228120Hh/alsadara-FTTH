/// خدمة المصادقة الموحدة عبر VPS API
/// تستبدل Firebase بـ VPS API لجميع عمليات المصادقة
library;

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_client.dart';
import 'api/api_response.dart';
import 'api/auth/auth_models.dart';
import 'api/auth/super_admin_api.dart';
import 'api/auth/company_auth_api.dart';

/// نوع المستخدم المسجل
enum VpsAuthUserType {
  superAdmin,
  companyEmployee,
}

/// نتيجة تسجيل الدخول
class VpsAuthResult {
  final bool success;
  final String? errorMessage;
  final VpsAuthUserType? userType;
  final VpsSuperAdmin? superAdmin;
  final VpsCompanyUser? companyUser;
  final VpsCompanyInfo? company;

  VpsAuthResult({
    required this.success,
    this.errorMessage,
    this.userType,
    this.superAdmin,
    this.companyUser,
    this.company,
  });

  factory VpsAuthResult.success({
    required VpsAuthUserType userType,
    VpsSuperAdmin? superAdmin,
    VpsCompanyUser? companyUser,
    VpsCompanyInfo? company,
  }) {
    return VpsAuthResult(
      success: true,
      userType: userType,
      superAdmin: superAdmin,
      companyUser: companyUser,
      company: company,
    );
  }

  factory VpsAuthResult.failure(String message) {
    return VpsAuthResult(
      success: false,
      errorMessage: message,
    );
  }
}

/// خدمة المصادقة عبر VPS API
class VpsAuthService {
  static VpsAuthService? _instance;
  static VpsAuthService get instance =>
      _instance ??= VpsAuthService._internal();
  VpsAuthService._internal();

  final SuperAdminApi _superAdminApi = SuperAdminApi();
  final AuthApi _authApi = AuthApi();

  // حالة المصادقة الحالية (static للوصول العام)
  static VpsSuperAdmin? _currentSuperAdmin;
  static VpsCompanyUser? _currentUser;
  static VpsCompanyInfo? _currentCompany;
  static VpsAuthUserType? _currentUserType;

  // Getters للوصول من الـ instance
  VpsSuperAdmin? get currentSuperAdmin => _currentSuperAdmin;
  VpsCompanyUser? get currentUser => _currentUser;
  VpsCompanyInfo? get currentCompany => _currentCompany;
  VpsAuthUserType? get currentUserType => _currentUserType;

  // Setters للتعديل
  set currentSuperAdmin(VpsSuperAdmin? value) => _currentSuperAdmin = value;
  set currentUser(VpsCompanyUser? value) => _currentUser = value;
  set currentCompany(VpsCompanyInfo? value) => _currentCompany = value;
  set currentUserType(VpsAuthUserType? value) => _currentUserType = value;

  // التوكنات
  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiresAt;

  // Getter للتوكن الحالي (للاستخدام في التشخيص)
  String? get accessToken => _accessToken;

  // مفاتيح التخزين المحلي
  static const _keyAccessToken = 'vps_access_token';
  static const _keyRefreshToken = 'vps_refresh_token';
  static const _keyTokenExpiresAt = 'vps_token_expires_at';
  static const _keyUserType = 'vps_user_type';
  static const _keyUserData = 'vps_user_data';
  static const _keyCompanyData = 'vps_company_data';

  /// تسجيل دخول Super Admin
  Future<VpsAuthResult> loginSuperAdmin(
      String username, String password) async {
    try {
      final response = await _superAdminApi.login(username, password);

      return response.fold(
        onSuccess: (data) async {
          // حفظ التوكنات
          await _saveTokens(
            accessToken: data.token,
            refreshToken: data.refreshToken,
            expiresAt: data.expiresAt,
          );

          // إنشاء كائن المدير
          final admin = VpsSuperAdmin(
            id: data.id,
            username: data.username,
            fullName: data.fullName,
            email: data.email,
          );

          // حفظ البيانات
          currentSuperAdmin = admin;
          currentUserType = VpsAuthUserType.superAdmin;
          currentUser = null;
          currentCompany = null;

          await _saveUserData(admin: admin);

          return VpsAuthResult.success(
            userType: VpsAuthUserType.superAdmin,
            superAdmin: admin,
          );
        },
        onError: (error, statusCode) {
          // ترجمة رسائل الخطأ
          String message = _translateError(error, statusCode);
          return VpsAuthResult.failure(message);
        },
      );
    } catch (e) {
      return VpsAuthResult.failure('حدث خطأ في الاتصال بالخادم: $e');
    }
  }

  /// تسجيل دخول موظف الشركة
  Future<VpsAuthResult> loginCompanyEmployee({
    required String companyCode,
    required String username,
    required String password,
  }) async {
    try {
      final response = await _authApi.loginEmployee(
        companyCode: companyCode,
        username: username,
        password: password,
      );

      return response.fold(
        onSuccess: (data) async {
          // حفظ التوكنات
          await _saveTokens(
            accessToken: data.token,
            refreshToken: data.refreshToken,
            expiresAt: data.expiresAt,
          );

          // إنشاء كائنات المستخدم والشركة
          final user = VpsCompanyUser(
            id: data.user.id,
            username: data.user.username,
            fullName: data.user.fullName,
            email: data.user.email,
            phone: data.user.phone,
            role: data.user.role,
            permissions: data.user.permissions,
            isActive: data.user.isActive,
          );

          final company = VpsCompanyInfo(
            id: data.company.id,
            name: data.company.name,
            code: data.company.code,
            logoUrl: data.company.logoUrl,
            subscriptionEndDate: data.company.subscriptionEndDate,
            daysRemaining: data.company.daysRemaining,
            isExpired: data.company.isExpired,
            subscriptionStatus: data.company.subscriptionStatus,
          );

          // حفظ البيانات
          currentUser = user;
          currentCompany = company;
          currentUserType = VpsAuthUserType.companyEmployee;
          currentSuperAdmin = null;

          await _saveUserData(user: user, company: company);

          return VpsAuthResult.success(
            userType: VpsAuthUserType.companyEmployee,
            companyUser: user,
            company: company,
          );
        },
        onError: (error, statusCode) {
          String message = _translateError(error, statusCode);
          return VpsAuthResult.failure(message);
        },
      );
    } catch (e) {
      return VpsAuthResult.failure('حدث خطأ في الاتصال بالخادم: $e');
    }
  }

  /// تسجيل الدخول الموحد (يكتشف النوع تلقائياً)
  /// إذا كان الكود "1" أو "ADMIN" أو "SUPER" يحاول تسجيل دخول كـ Super Admin
  Future<VpsAuthResult> login({
    required String companyCodeOrType,
    required String username,
    required String password,
  }) async {
    // التحقق من كود مدير النظام
    if (companyCodeOrType == '1' ||
        companyCodeOrType.toUpperCase() == 'ADMIN' ||
        companyCodeOrType.toUpperCase() == 'SUPER') {
      return loginSuperAdmin(username, password);
    }

    // تسجيل دخول موظف شركة
    return loginCompanyEmployee(
      companyCode: companyCodeOrType,
      username: username,
      password: password,
    );
  }

  /// تسجيل الخروج
  Future<void> logout() async {
    // مسح التوكنات من الخادم
    if (currentUserType == VpsAuthUserType.superAdmin) {
      await _superAdminApi.logout();
    } else {
      await _authApi.logout();
    }

    // مسح البيانات المحلية
    await _clearAllData();

    currentSuperAdmin = null;
    currentUser = null;
    currentCompany = null;
    currentUserType = null;
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiresAt = null;
  }

  /// تحديث التوكن
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      ApiResponse<TokenRefreshResponse> response;

      if (currentUserType == VpsAuthUserType.superAdmin) {
        response = await _superAdminApi.refreshToken(_refreshToken!);
      } else {
        response = await _authApi.refreshToken(_refreshToken!);
      }

      if (response.isSuccess && response.data != null) {
        await _saveTokens(
          accessToken: response.data!.token,
          refreshToken: response.data!.refreshToken,
          expiresAt: response.data!.expiresAt,
        );
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// استعادة الجلسة من التخزين المحلي
  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // قراءة التوكنات
      _accessToken = prefs.getString(_keyAccessToken);
      _refreshToken = prefs.getString(_keyRefreshToken);

      final expiresAtStr = prefs.getString(_keyTokenExpiresAt);
      if (expiresAtStr != null) {
        _tokenExpiresAt = DateTime.tryParse(expiresAtStr);
      }

      debugPrint(
          '🔍 restoreSession: accessToken=${_accessToken != null ? "موجود (${_accessToken!.length} حرف)" : "غير موجود"}');
      debugPrint(
          '🔍 restoreSession: refreshToken=${_refreshToken != null ? "موجود" : "غير موجود"}');
      debugPrint('🔍 restoreSession: tokenExpiresAt=$_tokenExpiresAt');

      // التحقق من صلاحية التوكن
      if (_accessToken == null || _tokenExpiresAt == null) {
        debugPrint('❌ restoreSession: لا يوجد توكن أو تاريخ انتهاء');
        return false;
      }

      // إذا انتهى التوكن، حاول التحديث
      if (_tokenExpiresAt!.isBefore(DateTime.now())) {
        debugPrint(
            '⏰ restoreSession: التوكن منتهي الصلاحية، محاولة التحديث...');
        final refreshed = await refreshAccessToken();
        if (!refreshed) {
          await _clearAllData();
          return false;
        }
      }

      // تعيين التوكن للـ ApiClient
      debugPrint('✅ restoreSession: تعيين التوكن للـ ApiClient');
      ApiClient.instance.setAuthToken(_accessToken!);

      // قراءة نوع المستخدم والبيانات
      final userTypeStr = prefs.getString(_keyUserType);
      if (userTypeStr == 'superAdmin') {
        currentUserType = VpsAuthUserType.superAdmin;
        final userData = prefs.getString(_keyUserData);
        if (userData != null) {
          currentSuperAdmin = VpsSuperAdmin.fromJson(jsonDecode(userData));
        }
      } else if (userTypeStr == 'companyEmployee') {
        currentUserType = VpsAuthUserType.companyEmployee;

        final userData = prefs.getString(_keyUserData);
        if (userData != null) {
          currentUser = VpsCompanyUser.fromJson(jsonDecode(userData));
        }

        final companyData = prefs.getString(_keyCompanyData);
        if (companyData != null) {
          currentCompany = VpsCompanyInfo.fromJson(jsonDecode(companyData));
        }
      }

      return isLoggedIn;
    } catch (e) {
      return false;
    }
  }

  /// التحقق من تسجيل الدخول
  bool get isLoggedIn =>
      currentSuperAdmin != null ||
      (currentUser != null && currentCompany != null);

  /// هل المستخدم Super Admin؟
  bool get isSuperAdmin => currentUserType == VpsAuthUserType.superAdmin;

  /// هل المستخدم موظف شركة؟
  bool get isCompanyEmployee =>
      currentUserType == VpsAuthUserType.companyEmployee;

  /// الحصول على معرف الشركة الحالية
  String? get currentCompanyId => currentCompany?.id;

  /// الحصول على اسم الشركة الحالية
  String? get currentCompanyName => currentCompany?.name;

  /// الحصول على كود الشركة الحالية
  String? get currentCompanyCode => currentCompany?.code;

  /// هل التوكن على وشك الانتهاء؟ (خلال 5 دقائق)
  bool get isTokenExpiringSoon {
    if (_tokenExpiresAt == null) return true;
    return _tokenExpiresAt!.difference(DateTime.now()).inMinutes < 5;
  }

  // ===== الدوال المساعدة الخاصة =====

  /// حفظ التوكنات
  Future<void> _saveTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime expiresAt,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _tokenExpiresAt = expiresAt;

    // تعيين التوكن للـ ApiClient
    ApiClient.instance.setAuthToken(accessToken);

    // حفظ في التخزين المحلي
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    await prefs.setString(_keyRefreshToken, refreshToken);
    await prefs.setString(_keyTokenExpiresAt, expiresAt.toIso8601String());
  }

  /// حفظ بيانات المستخدم
  Future<void> _saveUserData({
    VpsSuperAdmin? admin,
    VpsCompanyUser? user,
    VpsCompanyInfo? company,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (admin != null) {
      await prefs.setString(_keyUserType, 'superAdmin');
      await prefs.setString(_keyUserData, jsonEncode(admin.toJson()));
      await prefs.remove(_keyCompanyData);
    } else if (user != null && company != null) {
      await prefs.setString(_keyUserType, 'companyEmployee');
      await prefs.setString(_keyUserData, jsonEncode(user.toJson()));
      await prefs.setString(_keyCompanyData, jsonEncode(company.toJson()));
    }
  }

  /// مسح جميع البيانات
  Future<void> _clearAllData() async {
    // مسح المتغيرات في الذاكرة
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiresAt = null;
    currentSuperAdmin = null;
    currentUser = null;
    currentCompany = null;
    currentUserType = null;

    // مسح من التخزين المحلي
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyTokenExpiresAt);
    await prefs.remove(_keyUserType);
    await prefs.remove(_keyUserData);
    await prefs.remove(_keyCompanyData);

    ApiClient.instance.clearAuthToken();
  }

  /// ترجمة رسائل الخطأ
  String _translateError(String error, int? statusCode) {
    final errorLower = error.toLowerCase();

    if (statusCode == 401 || errorLower.contains('unauthorized')) {
      return 'اسم المستخدم أو كلمة المرور غير صحيحة';
    }
    if (statusCode == 403 || errorLower.contains('forbidden')) {
      return 'ليس لديك صلاحية الوصول';
    }
    if (statusCode == 423 || errorLower.contains('locked')) {
      return 'الحساب مقفل. يرجى المحاولة لاحقاً';
    }
    if (errorLower.contains('subscription') || errorLower.contains('expired')) {
      return 'اشتراك الشركة منتهي';
    }
    if (errorLower.contains('inactive') || errorLower.contains('disabled')) {
      return 'الحساب معطل';
    }
    if (errorLower.contains('company') && errorLower.contains('not found')) {
      return 'لم يتم العثور على الشركة';
    }
    if (errorLower.contains('user') && errorLower.contains('not found')) {
      return 'المستخدم غير موجود';
    }
    if (errorLower.contains('network') || errorLower.contains('connection')) {
      return 'خطأ في الاتصال بالخادم';
    }
    if (errorLower.contains('timeout')) {
      return 'انتهت مهلة الاتصال';
    }

    return error;
  }
}

// ===== نماذج البيانات =====

/// نموذج Super Admin
class VpsSuperAdmin {
  final String id;
  final String username;
  final String fullName;
  final String? email;

  VpsSuperAdmin({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
  });

  factory VpsSuperAdmin.fromJson(Map<String, dynamic> json) {
    return VpsSuperAdmin(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'fullName': fullName,
        'email': email,
      };
}

/// نموذج موظف الشركة
class VpsCompanyUser {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String role;
  final List<String> permissions;
  final bool isActive;

  VpsCompanyUser({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    required this.role,
    required this.permissions,
    required this.isActive,
  });

  factory VpsCompanyUser.fromJson(Map<String, dynamic> json) {
    return VpsCompanyUser(
      id: json['id']?.toString() ?? '',
      username: json['username'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'],
      phone: json['phone'],
      role: json['role'] ?? 'Employee',
      permissions: (json['permissions'] as List?)?.cast<String>() ?? [],
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'fullName': fullName,
        'email': email,
        'phone': phone,
        'role': role,
        'permissions': permissions,
        'isActive': isActive,
      };

  /// التحقق من صلاحية معينة
  bool hasPermission(String permission) {
    return permissions.contains(permission) || role == 'Admin';
  }

  /// هل هو مدير الشركة
  bool get isAdmin => role == 'Admin';
}

/// نموذج معلومات الشركة
class VpsCompanyInfo {
  final String id;
  final String name;
  final String code;
  final String? logoUrl;
  final DateTime subscriptionEndDate;
  final int daysRemaining;
  final bool isExpired;
  final String subscriptionStatus;

  VpsCompanyInfo({
    required this.id,
    required this.name,
    required this.code,
    this.logoUrl,
    required this.subscriptionEndDate,
    required this.daysRemaining,
    required this.isExpired,
    required this.subscriptionStatus,
  });

  factory VpsCompanyInfo.fromJson(Map<String, dynamic> json) {
    return VpsCompanyInfo(
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'logoUrl': logoUrl,
        'subscriptionEndDate': subscriptionEndDate.toIso8601String(),
        'daysRemaining': daysRemaining,
        'isExpired': isExpired,
        'subscriptionStatus': subscriptionStatus,
      };

  /// هل الاشتراك سينتهي قريباً
  bool get isExpiringSoon => daysRemaining > 0 && daysRemaining <= 30;
}
