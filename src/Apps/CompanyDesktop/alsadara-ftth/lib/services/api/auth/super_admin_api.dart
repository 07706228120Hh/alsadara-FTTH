import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../api_client.dart';
import '../api_config.dart';
import '../api_response.dart';
import 'auth_models.dart';
import '../../../models/tenant.dart';

/// خدمة API لمدير النظام
class SuperAdminApi {
  final ApiClient _client;

  SuperAdminApi([ApiClient? client]) : _client = client ?? ApiClient.instance;

  // ============================================
  // Authentication
  // ============================================

  /// تسجيل دخول مدير النظام
  Future<ApiResponse<SuperAdminLoginResponse>> login(
    String username,
    String password,
  ) async {
    return _client.post(
      ApiConfig.superAdminLogin,
      {
        'username': username,
        'password': password,
      },
      (json) => SuperAdminLoginResponse.fromJson(json),
    );
  }

  /// تحديث التوكن
  Future<ApiResponse<TokenRefreshResponse>> refreshToken(
    String refreshToken,
  ) async {
    return _client.post(
      ApiConfig.superAdminRefreshToken,
      {'refreshToken': refreshToken},
      (json) => TokenRefreshResponse.fromJson(json),
    );
  }

  /// تسجيل الخروج
  Future<ApiResponse<bool>> logout() async {
    final response = await _client.post(
      ApiConfig.superAdminLogout,
      {},
      (json) => true,
    );

    if (response.isSuccess) {
      _client.clearAuthToken();
    }

    return response;
  }

  // ============================================
  // Dashboard
  // ============================================

  /// جلب إحصائيات لوحة التحكم
  Future<ApiResponse<DashboardStats>> getDashboard() async {
    return _client.get(
      ApiConfig.superAdminDashboard,
      (json) => DashboardStats.fromJson(json),
    );
  }

  /// جلب الإحصائيات
  Future<ApiResponse<SystemStatistics>> getStatistics() async {
    return _client.get(
      ApiConfig.superAdminStatistics,
      (json) => SystemStatistics.fromJson(json),
    );
  }

  // ============================================
  // Companies Management
  // ============================================

  /// جلب جميع الشركات
  Future<ApiResponse<CompaniesListResponse>> getCompanies({
    int page = 1,
    int pageSize = 20,
  }) async {
    return _client.get(
      '${ApiConfig.companies}?page=$page&pageSize=$pageSize',
      (json) => CompaniesListResponse.fromJson(json),
    );
  }

  /// جلب شركة بالمعرف
  Future<ApiResponse<Company>> getCompanyById(String id) async {
    return _client.get(
      ApiConfig.companyById(id),
      (json) => Company.fromJson(json),
    );
  }

  /// إنشاء شركة جديدة
  Future<ApiResponse<Company>> createCompany(
      CreateCompanyRequest request) async {
    return _client.post(
      ApiConfig.companies,
      request.toJson(),
      (json) => Company.fromJson(json),
    );
  }

  /// تحديث شركة
  Future<ApiResponse<Company>> updateCompany(
    String id,
    UpdateCompanyRequest request,
  ) async {
    return _client.put(
      ApiConfig.companyById(id),
      request.toJson(),
      (json) => Company.fromJson(json),
    );
  }

  /// تفعيل/تعطيل شركة
  Future<ApiResponse<Company>> toggleCompanyStatus(String id) async {
    return _client.patch(
      ApiConfig.companyToggleStatus(id),
      {},
      (json) => Company.fromJson(json),
    );
  }

  /// تجديد اشتراك شركة
  Future<ApiResponse<Company>> renewSubscription(String id, int days) async {
    return _client.patch(
      ApiConfig.companyRenew(id),
      {'days': days},
      (json) => Company.fromJson(json),
    );
  }

  /// حذف شركة
  Future<ApiResponse<bool>> deleteCompany(String id) async {
    return _client.delete(
      ApiConfig.companyById(id),
      (json) => true,
    );
  }

  // ============================================
  // VPS Companies as Tenants (لتوحيد مصدر البيانات)
  // ============================================

  /// جلب الشركات من VPS وتحويلها إلى Tenant objects
  /// هذه الدالة تستخدم Internal API للحصول على الشركات بدون مصادقة
  Future<List<Tenant>> getTenantsFromVps() async {
    try {
      final response = await _client.get(
        ApiConfig.internalCompanies,
        (json) => json,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final List<dynamic> companiesJson = response.data is List
            ? response.data
            : (response.data['data'] ?? []);

        return companiesJson.map((json) => _companyToTenant(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب الشركات من VPS: $e');
      return [];
    }
  }

  /// تحويل بيانات الشركة من VPS JSON إلى Tenant object
  Tenant _companyToTenant(Map<String, dynamic> json) {
    // استخراج القيم مع دعم PascalCase و camelCase
    final id = (json['Id'] ?? json['id'])?.toString() ?? '';
    final name = json['Name'] ?? json['name'] ?? '';
    final code = json['Code'] ?? json['code'] ?? '';
    final email = json['Email'] ?? json['email'];
    final phone = json['Phone'] ?? json['phone'];
    final address = json['Address'] ?? json['address'];
    final logoUrl = json['LogoUrl'] ?? json['logoUrl'];
    final isActive = json['IsActive'] ?? json['isActive'] ?? true;
    final maxUsers = json['MaxUsers'] ?? json['maxUsers'] ?? 10;

    // تواريخ الاشتراك
    final subscriptionStartStr = json['SubscriptionStartDate'] ??
        json['subscriptionStartDate'] ??
        json['SubscriptionStart'] ??
        json['subscriptionStart'];
    final subscriptionEndStr = json['SubscriptionEndDate'] ??
        json['subscriptionEndDate'] ??
        json['SubscriptionEnd'] ??
        json['subscriptionEnd'];
    final createdAtStr = json['CreatedAt'] ?? json['createdAt'];

    DateTime subscriptionStart = DateTime.now();
    DateTime subscriptionEnd = DateTime.now().add(const Duration(days: 30));
    DateTime createdAt = DateTime.now();

    if (subscriptionStartStr != null) {
      try {
        subscriptionStart = DateTime.parse(subscriptionStartStr.toString());
      } catch (_) {}
    }
    if (subscriptionEndStr != null) {
      try {
        subscriptionEnd = DateTime.parse(subscriptionEndStr.toString());
      } catch (_) {}
    }
    if (createdAtStr != null) {
      try {
        createdAt = DateTime.parse(createdAtStr.toString());
      } catch (_) {}
    }

    // ربط بوابة المواطن
    final isLinkedToCitizenPortal = json['IsLinkedToCitizenPortal'] ??
        json['isLinkedToCitizenPortal'] ??
        false;
    final linkedToCitizenPortalAtStr =
        json['LinkedToCitizenPortalAt'] ?? json['linkedToCitizenPortalAt'];

    DateTime? linkedToCitizenPortalAt;
    if (linkedToCitizenPortalAtStr != null) {
      try {
        linkedToCitizenPortalAt =
            DateTime.parse(linkedToCitizenPortalAtStr.toString());
      } catch (_) {}
    }

    // معلومات المدير
    final adminUserName = json['AdminUserName'] ?? json['adminUserName'];

    return Tenant(
      id: id,
      name: name,
      code: code,
      email: email,
      phone: phone,
      address: address,
      logo: logoUrl,
      isActive: isActive,
      suspensionReason: null,
      suspendedAt: null,
      suspendedBy: null,
      subscriptionStart: subscriptionStart,
      subscriptionEnd: subscriptionEnd,
      subscriptionPlan: 'vps',
      maxUsers: maxUsers,
      createdAt: createdAt,
      createdBy: 'vps',
      enabledFirstSystemFeatures: {},
      enabledSecondSystemFeatures: {},
      isLinkedToCitizenPortal: isLinkedToCitizenPortal,
      linkedToCitizenPortalAt: linkedToCitizenPortalAt,
      adminUsername: adminUserName,
      adminPassword: null,
      adminFullName: adminUserName,
    );
  }
}

// ============================================
// Models
// ============================================

/// استجابة تسجيل دخول مدير النظام
class SuperAdminLoginResponse {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String token;
  final String refreshToken;
  final DateTime expiresAt;

  SuperAdminLoginResponse({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
    required this.token,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory SuperAdminLoginResponse.fromJson(Map<String, dynamic> json) {
    // API يرجع أسماء الحقول بـ PascalCase
    return SuperAdminLoginResponse(
      id: (json['Id'] ?? json['id'])?.toString() ?? '',
      username: json['Username'] ?? json['username'] ?? '',
      fullName: json['FullName'] ?? json['fullName'] ?? '',
      email: json['Email'] ?? json['email'],
      token: json['Token'] ?? json['token'] ?? '',
      refreshToken: json['RefreshToken'] ?? json['refreshToken'] ?? '',
      expiresAt: (json['ExpiresAt'] ?? json['expiresAt']) != null
          ? DateTime.parse(json['ExpiresAt'] ?? json['expiresAt'])
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }
}

/// إحصائيات لوحة التحكم
class DashboardStats {
  final SystemStatus systemStatus;
  final SystemStatistics statistics;
  final List<RecentActivity> recentActivities;
  final List<SystemAlert> alerts;

  DashboardStats({
    required this.systemStatus,
    required this.statistics,
    required this.recentActivities,
    required this.alerts,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      systemStatus: SystemStatus.fromJson(json['systemStatus'] ?? {}),
      statistics: SystemStatistics.fromJson(json['statistics'] ?? {}),
      recentActivities: (json['recentActivities'] as List?)
              ?.map((e) => RecentActivity.fromJson(e))
              .toList() ??
          [],
      alerts: (json['alerts'] as List?)
              ?.map((e) => SystemAlert.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class SystemStatus {
  final String status;
  final String apiVersion;
  final String environment;
  final String uptime;

  SystemStatus({
    required this.status,
    required this.apiVersion,
    required this.environment,
    required this.uptime,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      status: json['status'] ?? '',
      apiVersion: json['apiVersion'] ?? '',
      environment: json['environment'] ?? '',
      uptime: json['uptime'] ?? '',
    );
  }
}

class SystemStatistics {
  final int totalUsers;
  final int activeUsersToday;
  final int totalCompanies;
  final int activeCompanies;
  final int totalProducts;
  final int totalMerchants;
  final int ordersToday;
  final double revenueToday;

  SystemStatistics({
    required this.totalUsers,
    required this.activeUsersToday,
    required this.totalCompanies,
    required this.activeCompanies,
    required this.totalProducts,
    required this.totalMerchants,
    required this.ordersToday,
    required this.revenueToday,
  });

  factory SystemStatistics.fromJson(Map<String, dynamic> json) {
    return SystemStatistics(
      totalUsers: json['totalUsers'] ?? 0,
      activeUsersToday: json['activeUsersToday'] ?? 0,
      totalCompanies: json['totalCompanies'] ?? 0,
      activeCompanies: json['activeCompanies'] ?? 0,
      totalProducts: json['totalProducts'] ?? 0,
      totalMerchants: json['totalMerchants'] ?? 0,
      ordersToday: json['ordersToday'] ?? 0,
      revenueToday: (json['revenueToday'] ?? 0).toDouble(),
    );
  }
}

class RecentActivity {
  final String type;
  final String description;
  final DateTime timestamp;

  RecentActivity({
    required this.type,
    required this.description,
    required this.timestamp,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      type: json['type'] ?? '',
      description: json['description'] ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }
}

class SystemAlert {
  final String id;
  final String type;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool acknowledged;

  SystemAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.acknowledged,
  });

  factory SystemAlert.fromJson(Map<String, dynamic> json) {
    return SystemAlert(
      id: json['id']?.toString() ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      acknowledged: json['acknowledged'] ?? false,
    );
  }
}

/// قائمة الشركات
class CompaniesListResponse {
  final List<Company> companies;
  final int total;
  final int page;
  final int pageSize;

  CompaniesListResponse({
    required this.companies,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory CompaniesListResponse.fromJson(dynamic json) {
    // قد يكون json قائمة مباشرة أو كائن يحتوي على البيانات
    if (json is List) {
      return CompaniesListResponse(
        companies: json.map((e) => Company.fromJson(e)).toList(),
        total: json.length,
        page: 1,
        pageSize: json.length,
      );
    }

    final data = json as Map<String, dynamic>;
    return CompaniesListResponse(
      companies:
          (data['data'] as List?)?.map((e) => Company.fromJson(e)).toList() ??
              (json is List
                  ? (json as List).map((e) => Company.fromJson(e)).toList()
                  : []),
      total: data['total'] ?? 0,
      page: data['page'] ?? 1,
      pageSize: data['pageSize'] ?? 20,
    );
  }
}

/// نموذج الشركة
class Company {
  final String id;
  final String name;
  final String code;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? logoUrl;
  final DateTime subscriptionStartDate;
  final DateTime subscriptionEndDate;
  final int maxUsers;
  final bool isActive;
  final String? adminUserId;
  final String? adminUserName;
  final int employeeCount;
  final int daysRemaining;
  final bool isExpired;
  final String subscriptionStatus;
  final DateTime createdAt;
  final Map<String, dynamic>? enabledFirstSystemFeatures;
  final Map<String, dynamic>? enabledSecondSystemFeatures;

  Company({
    required this.id,
    required this.name,
    required this.code,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.logoUrl,
    required this.subscriptionStartDate,
    required this.subscriptionEndDate,
    required this.maxUsers,
    required this.isActive,
    this.adminUserId,
    this.adminUserName,
    required this.employeeCount,
    required this.daysRemaining,
    required this.isExpired,
    required this.subscriptionStatus,
    required this.createdAt,
    this.enabledFirstSystemFeatures,
    this.enabledSecondSystemFeatures,
  });

  factory Company.fromJson(Map<String, dynamic> json) {
    // دعم كلا التنسيقين: PascalCase (من Internal API) و camelCase (من SuperAdmin API)

    return Company(
      id: (json['id'] ?? json['Id'])?.toString() ?? '',
      name: json['name'] ?? json['Name'] ?? '',
      code: json['code'] ?? json['Code'] ?? '',
      email: json['email'] ?? json['Email'],
      phone: json['phone'] ?? json['Phone'],
      address: json['address'] ?? json['Address'],
      city: json['city'] ?? json['City'],
      logoUrl: json['logoUrl'] ?? json['LogoUrl'],
      subscriptionStartDate: _parseDate(json['subscriptionStartDate'] ??
          json['SubscriptionStartDate'] ??
          DateTime.now().subtract(Duration(days: 30))),
      subscriptionEndDate: _parseDate(json['subscriptionEndDate'] ??
          json['SubscriptionEndDate'] ??
          DateTime.now().add(Duration(days: 30))),
      maxUsers: json['maxUsers'] ?? json['MaxUsers'] ?? 10,
      isActive: json['isActive'] ?? json['IsActive'] ?? true,
      adminUserId: (json['adminUserId'] ?? json['AdminUserId'])?.toString(),
      adminUserName: json['adminUserName'] ?? json['AdminUserName'],
      employeeCount: json['employeeCount'] ?? json['EmployeeCount'] ?? 0,
      daysRemaining: _calculateDaysRemaining(json),
      isExpired: _checkIsExpired(json),
      subscriptionStatus: _getSubscriptionStatus(json),
      createdAt:
          _parseDate(json['createdAt'] ?? json['CreatedAt'] ?? DateTime.now()),
      enabledFirstSystemFeatures: _parseFeatures(
          json['enabledFirstSystemFeatures'] ??
              json['EnabledFirstSystemFeatures']),
      enabledSecondSystemFeatures: _parseFeatures(
          json['enabledSecondSystemFeatures'] ??
              json['EnabledSecondSystemFeatures']),
    );
  }

  /// تحليل الصلاحيات من JSON string أو Map
  static Map<String, dynamic>? _parseFeatures(dynamic value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final parsed = Map<String, dynamic>.from(value.isNotEmpty
            ? (value.startsWith('{') ? _decodeJson(value) : {})
            : {});
        return parsed;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// فك تشفير JSON
  static Map<String, dynamic> _decodeJson(String value) {
    try {
      return Map<String, dynamic>.from((value.isNotEmpty)
          ? (Map<String, dynamic>.from(jsonDecode(value)))
          : {});
    } catch (_) {
      return {};
    }
  }

  /// تحليل التاريخ بأمان
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  /// حساب الأيام المتبقية
  static int _calculateDaysRemaining(Map<String, dynamic> json) {
    if (json['daysRemaining'] != null) return json['daysRemaining'];
    if (json['DaysRemaining'] != null) return json['DaysRemaining'];

    final endDateStr =
        json['subscriptionEndDate'] ?? json['SubscriptionEndDate'];
    if (endDateStr != null) {
      try {
        final endDate = DateTime.parse(endDateStr.toString());
        return endDate.difference(DateTime.now()).inDays;
      } catch (_) {}
    }
    return 0;
  }

  /// التحقق من انتهاء الاشتراك
  static bool _checkIsExpired(Map<String, dynamic> json) {
    if (json['isExpired'] != null) return json['isExpired'];
    if (json['IsExpired'] != null) return json['IsExpired'];

    final endDateStr =
        json['subscriptionEndDate'] ?? json['SubscriptionEndDate'];
    if (endDateStr != null) {
      try {
        final endDate = DateTime.parse(endDateStr.toString());
        return endDate.isBefore(DateTime.now());
      } catch (_) {}
    }
    return false;
  }

  /// الحصول على حالة الاشتراك
  static String _getSubscriptionStatus(Map<String, dynamic> json) {
    if (json['subscriptionStatus'] != null) return json['subscriptionStatus'];
    if (json['SubscriptionStatus'] != null) return json['SubscriptionStatus'];

    final isActive = json['isActive'] ?? json['IsActive'] ?? true;
    if (!isActive) return 'Suspended';

    final isExpired = _checkIsExpired(json);
    if (isExpired) return 'Expired';

    final daysRemaining = _calculateDaysRemaining(json);
    if (daysRemaining <= 7) return 'Critical';
    if (daysRemaining <= 30) return 'Warning';

    return 'Active';
  }
}

/// طلب إنشاء شركة
class CreateCompanyRequest {
  final String name;
  final String code;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? logoUrl;
  final String adminName;
  final String adminEmail;
  final String adminPhone;
  final String adminPassword;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;
  final int? maxUsers;

  CreateCompanyRequest({
    required this.name,
    required this.code,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.logoUrl,
    required this.adminName,
    required this.adminEmail,
    required this.adminPhone,
    required this.adminPassword,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
    this.maxUsers,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'code': code,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (logoUrl != null) 'logoUrl': logoUrl,
        'adminName': adminName,
        'adminEmail': adminEmail,
        'adminPhone': adminPhone,
        'adminPassword': adminPassword,
        if (subscriptionStartDate != null)
          'subscriptionStartDate': subscriptionStartDate!.toIso8601String(),
        if (subscriptionEndDate != null)
          'subscriptionEndDate': subscriptionEndDate!.toIso8601String(),
        if (maxUsers != null) 'maxUsers': maxUsers,
      };
}

/// طلب تحديث شركة
class UpdateCompanyRequest {
  final String? name;
  final String? code;
  final String? email;
  final String? phone;
  final String? address;
  final String? city;
  final String? logoUrl;
  final DateTime? subscriptionStartDate;
  final DateTime? subscriptionEndDate;
  final int? maxUsers;

  UpdateCompanyRequest({
    this.name,
    this.code,
    this.email,
    this.phone,
    this.address,
    this.city,
    this.logoUrl,
    this.subscriptionStartDate,
    this.subscriptionEndDate,
    this.maxUsers,
  });

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (code != null) 'code': code,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (address != null) 'address': address,
        if (city != null) 'city': city,
        if (logoUrl != null) 'logoUrl': logoUrl,
        if (subscriptionStartDate != null)
          'subscriptionStartDate': subscriptionStartDate!.toIso8601String(),
        if (subscriptionEndDate != null)
          'subscriptionEndDate': subscriptionEndDate!.toIso8601String(),
        if (maxUsers != null) 'maxUsers': maxUsers,
      };
}
