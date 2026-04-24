/// إعدادات API للاتصال بـ Sadara Platform
class ApiConfig {
  // ============================================
  // URLs
  // ============================================

  /// رابط API للتطوير المحلي
  static const String devBaseUrl = 'http://localhost:5000/api';

  /// رابط API للإنتاج (VPS) - HTTPS مع دومين
  static const String prodBaseUrl = 'https://api.ramzalsadara.tech/api';

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
  static const String superAdminComprehensiveDashboard =
      '/superadmin/comprehensive-dashboard';

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
  static String internalCompanyEmployees(String id) =>
      '/internal/companies/$id/employees';
  static String internalEmployeeById(String companyId, String empId) =>
      '/internal/companies/$companyId/employees/$empId';
  static String internalEmployeePassword(String companyId, String empId) =>
      '/internal/companies/$companyId/employees/$empId/password';
  static String internalCompanyPermissionsV2(String companyId) =>
      '/internal/companies/$companyId/permissions-v2';
  static String internalEmployeePermissionsV2(String companyId, String empId) =>
      '/internal/companies/$companyId/employees/$empId/permissions-v2';

  // ============================================
  // Endpoints - Subscriber Cache (كاش المشتركين)
  // ============================================

  static String subscriberCacheByTenant(String tenantId) =>
      '/subscriber-cache/$tenantId';
  static String subscriberCacheSync(String tenantId) =>
      '/subscriber-cache/$tenantId/sync';

  // ============================================
  // Endpoints - Subscriber Cache Download (تنزيل البيانات من VPS)
  // ============================================

  static String subscriberCacheDownload(String tenantId) =>
      '/subscriber-cache/$tenantId/download';
  static String subscriberCacheUpdatedSince(String tenantId, DateTime since) =>
      '/subscriber-cache/$tenantId/updated-since?since=${since.toUtc().toIso8601String()}';

  // ============================================
  // Endpoints - Company FTTH Settings (إعدادات مزامنة FTTH)
  // ============================================

  static String companyFtthSettings(String companyId) =>
      '/company-ftth-settings/$companyId';
  static const String companyFtthSettingsSave = '/company-ftth-settings';
  static String companyFtthSettingsTest(String companyId) =>
      '/company-ftth-settings/$companyId/test';
  static String companyFtthSyncStatus(String companyId) =>
      '/company-ftth-settings/$companyId/sync-status';
  static String companyFtthTriggerSync(String companyId) =>
      '/company-ftth-settings/$companyId/trigger-sync';
  static String companyFtthCancelSync(String companyId) =>
      '/company-ftth-settings/$companyId/cancel-sync';
  static String companyFtthDeleteSyncLog(String companyId, dynamic logId) =>
      '/company-ftth-settings/$companyId/sync-logs/$logId';
  static String companyFtthDeleteAllSyncLogs(String companyId) =>
      '/company-ftth-settings/$companyId/sync-logs';
  static String companyFtthMissingStats(String companyId) =>
      '/company-ftth-settings/$companyId/missing-stats';
  static String companyFtthRefetchMissing(String companyId) =>
      '/company-ftth-settings/$companyId/refetch-missing';
  static String companyFtthDetailedStats(String companyId) =>
      '/company-ftth-settings/$companyId/detailed-stats';
  static String companyFtthClearData(String companyId) =>
      '/company-ftth-settings/$companyId/clear-data';

  // ============================================
  // Endpoints - IPTV Subscribers (مشتركي IPTV)
  // ============================================

  static const String iptvSubscribers = '/iptv-subscribers';
  static String iptvSubscriberById(int id) => '/iptv-subscribers/$id';

  // ============================================
  // API Keys
  // ============================================

  /// ⚠️ تم نقل المفاتيح إلى AppSecrets للأمان
  /// استخدم: AppSecrets.instance.internalApiKey
  @Deprecated('استخدم AppSecrets.instance.internalApiKey بدلاً من هذا')
  static const String internalApiKey = 'sadara-internal-2024-secure-key';

  // ============================================
  // Timeouts
  // ============================================

  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
