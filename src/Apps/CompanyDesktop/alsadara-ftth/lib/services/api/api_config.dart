/// إعدادات API للاتصال بـ Sadara Platform
class ApiConfig {
  // ============================================
  // URLs
  // ============================================

  /// رابط API للتطوير المحلي
  static const String devBaseUrl = 'http://localhost:5000/api';

  /// رابط API للإنتاج (VPS)
  static const String prodBaseUrl = 'https://72.61.183.61/api';

  /// استخدام بيئة التطوير أو الإنتاج
  static const bool isProduction = true;

  /// رابط API الفعلي
  static String get baseUrl => isProduction ? prodBaseUrl : devBaseUrl;

  // ============================================
  // Endpoints - Super Admin
  // ============================================

  static const String superAdminLogin = '/superadmin/login';
  static const String superAdminRefreshToken = '/superadmin/refresh-token';
  static const String superAdminLogout = '/superadmin/logout';
  static const String superAdminDashboard = '/superadmin/dashboard';
  static const String superAdminStatistics = '/superadmin/statistics';

  // ============================================
  // Endpoints - Companies
  // ============================================

  static const String companyLogin = '/companies/login';
  static const String companyRefreshToken = '/companies/refresh-token';
  static const String companies = '/superadmin/companies';
  static String companyById(String id) => '/superadmin/companies/$id';
  static String companyByCode(String code) => '/companies/by-code/$code';
  static String companyEmployees(String id) => '/companies/$id/employees';
  static String companyRenew(String id) => '/superadmin/companies/$id/renew';
  static String companyToggleStatus(String id) =>
      '/superadmin/companies/$id/toggle-status';

  // ============================================
  // Endpoints - Citizens
  // ============================================

  static const String citizenLogin = '/citizen/login';
  static const String citizenRegister = '/citizen/register';
  static const String citizenPlans = '/citizen/plans';
  static const String citizenSubscriptions = '/citizen/subscriptions';

  // ============================================
  // Endpoints - Internal Data
  // ============================================

  static const String internalCitizens = '/internal/citizens';
  static const String internalCompanies = '/internal/companies';
  static const String internalSubscriptions = '/internal/subscriptions';
  static const String internalPayments = '/internal/payments';

  // ============================================
  // API Keys
  // ============================================

  static const String internalApiKey = 'sadara-internal-2024-secure-key';

  // ============================================
  // Timeouts
  // ============================================

  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
