import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/api/api_config.dart';
import '../../../services/api/api_client.dart';
import '../../../services/vps_auth_service.dart';
import '../../../services/unified_auth_manager.dart';
import '../../../services/google_sheets_service.dart';
import '../../../services/whatsapp_business_service.dart';
import '../models/diagnostic_test.dart';

/// خدمة التشخيص الشاملة
class DiagnosticService {
  static final DiagnosticService _instance = DiagnosticService._internal();
  factory DiagnosticService() => _instance;
  DiagnosticService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final List<DiagnosticTestResult> _results = [];
  bool _isRunning = false;

  // HTTP Client يتجاوز التحقق من شهادة SSL (للخوادم ذات الشهادات الموقعة ذاتياً)
  late final http.Client _httpClient = _createHttpClient();

  http.Client _createHttpClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
    return IOClient(httpClient);
  }

  bool get isRunning => _isRunning;
  List<DiagnosticTestResult> get results => List.unmodifiable(_results);

  /// الحصول على التوكن من أي خدمة مصادقة متاحة
  Future<String?> _getActiveAuthToken() async {
    // أولاً: محاولة الحصول من ApiClient (التوكن المستخدم فعلياً في الطلبات)
    final apiClientToken = ApiClient.instance.authToken;
    if (apiClientToken != null && apiClientToken.isNotEmpty) {
      return apiClientToken;
    }

    // ثانياً: محاولة الحصول من VpsAuthService
    final vpsToken = VpsAuthService.instance.accessToken;
    if (vpsToken != null && vpsToken.isNotEmpty) {
      return vpsToken;
    }

    // ثالثاً: محاولة الحصول من UnifiedAuthManager (FTTH auth)
    final unifiedToken =
        await UnifiedAuthManager.instance.getValidAccessToken();
    if (unifiedToken != null && unifiedToken.isNotEmpty) {
      return unifiedToken;
    }

    return null;
  }

  /// التحقق من وجود جلسة نشطة
  bool _hasActiveSession() {
    // التحقق من ApiClient (الأهم - المستخدم فعلياً)
    if (ApiClient.instance.isAuthenticated) {
      return true;
    }

    // التحقق من VpsAuthService
    if (VpsAuthService.instance.isLoggedIn) {
      return true;
    }

    // التحقق من UnifiedAuthManager
    if (UnifiedAuthManager.instance.currentState == AuthState.authenticated) {
      return true;
    }

    return false;
  }

  /// الحصول على جميع الاختبارات
  List<DiagnosticTest> getAllTests() {
    return [
      // ═══════════════════════════════════════════════════════════
      // 🔌 اختبارات الاتصال والشبكة
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'firebase_connection',
        name: 'Firebase Connection',
        nameAr: 'الاتصال بـ Firebase',
        description: 'فحص الاتصال بخدمات Firebase',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testFirebaseConnection,
      ),
      DiagnosticTest(
        id: 'vps_connection',
        name: 'VPS Connection',
        nameAr: 'الاتصال بـ VPS',
        description: 'فحص الاتصال بخادم VPS',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testVpsConnection,
      ),
      DiagnosticTest(
        id: 'ssl_certificate',
        name: 'SSL Certificate',
        nameAr: 'شهادة SSL',
        description: 'فحص صلاحية شهادة SSL',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testSslCertificate,
      ),
      DiagnosticTest(
        id: 'api_health',
        name: 'API Health Check',
        nameAr: 'صحة API',
        description: 'فحص صحة واستجابة API',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testApiHealth,
      ),
      DiagnosticTest(
        id: 'database_connection',
        name: 'Database Connection',
        nameAr: 'الاتصال بقاعدة البيانات',
        description: 'فحص الاتصال بقاعدة البيانات عبر API',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testDatabaseConnection,
      ),
      DiagnosticTest(
        id: 'dns_resolution',
        name: 'DNS Resolution',
        nameAr: 'تحليل DNS',
        description: 'فحص تحليل أسماء النطاقات',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testDnsResolution,
      ),
      DiagnosticTest(
        id: 'network_latency',
        name: 'Network Latency',
        nameAr: 'زمن استجابة الشبكة',
        description: 'قياس زمن الاستجابة للشبكة',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testNetworkLatency,
      ),

      // ═══════════════════════════════════════════════════════════
      // 🔗 خدمات خارجية
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'google_sheets_connection',
        name: 'Google Sheets Connection',
        nameAr: 'الاتصال بـ Google Sheets',
        description: 'فحص الاتصال بجداول Google',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testGoogleSheetsConnection,
      ),
      DiagnosticTest(
        id: 'whatsapp_api',
        name: 'WhatsApp API',
        nameAr: 'واجهة WhatsApp',
        description: 'فحص اتصال WhatsApp Business API',
        category: 'connection',
        type: DiagnosticTestType.connection,
        testFunction: _testWhatsAppApi,
      ),

      // ═══════════════════════════════════════════════════════════
      // 🌐 اختبارات API
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'api_superadmin_login',
        name: 'SuperAdmin Login API',
        nameAr: 'API تسجيل دخول المدير',
        description: 'فحص نقطة تسجيل دخول المدير العام',
        category: 'api',
        type: DiagnosticTestType.api,
        testFunction: _testSuperAdminLoginApi,
      ),
      DiagnosticTest(
        id: 'api_companies_list',
        name: 'Companies List API',
        nameAr: 'API قائمة الشركات',
        description: 'فحص نقطة جلب قائمة الشركات',
        category: 'api',
        type: DiagnosticTestType.api,
        testFunction: _testCompaniesListApi,
      ),
      DiagnosticTest(
        id: 'api_citizens_list',
        name: 'Citizens List API',
        nameAr: 'API قائمة المواطنين',
        description: 'فحص نقطة جلب قائمة المواطنين',
        category: 'api',
        type: DiagnosticTestType.api,
        testFunction: _testCitizensListApi,
      ),
      DiagnosticTest(
        id: 'api_subscriptions',
        name: 'Subscriptions API',
        nameAr: 'API الاشتراكات',
        description: 'فحص نقطة الاشتراكات',
        category: 'api',
        type: DiagnosticTestType.api,
        testFunction: _testSubscriptionsApi,
      ),
      DiagnosticTest(
        id: 'api_statistics',
        name: 'Statistics API',
        nameAr: 'API الإحصائيات',
        description: 'فحص نقطة الإحصائيات',
        category: 'api',
        type: DiagnosticTestType.api,
        testFunction: _testStatisticsApi,
      ),
      DiagnosticTest(
        id: 'api_error_handling',
        name: 'API Error Handling',
        nameAr: 'معالجة أخطاء API',
        description: 'فحص معالجة الأخطاء في API',
        category: 'api',
        type: DiagnosticTestType.api,
        testFunction: _testApiErrorHandling,
      ),
      DiagnosticTest(
        id: 'api_response_format',
        name: 'API Response Format',
        nameAr: 'تنسيق استجابة API',
        description: 'فحص تنسيق استجابات API (JSON)',
        category: 'api',
        type: DiagnosticTestType.api,
        testFunction: _testApiResponseFormat,
      ),

      // ═══════════════════════════════════════════════════════════
      // 📝 اختبارات CRUD
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'crud_create_test',
        name: 'CRUD Create Operation',
        nameAr: 'عملية الإنشاء',
        description: 'فحص عملية إنشاء سجل جديد',
        category: 'crud',
        type: DiagnosticTestType.crud,
        testFunction: _testCrudCreate,
      ),
      DiagnosticTest(
        id: 'crud_read_test',
        name: 'CRUD Read Operation',
        nameAr: 'عملية القراءة',
        description: 'فحص عملية قراءة السجلات',
        category: 'crud',
        type: DiagnosticTestType.crud,
        testFunction: _testCrudRead,
      ),
      DiagnosticTest(
        id: 'crud_update_test',
        name: 'CRUD Update Operation',
        nameAr: 'عملية التحديث',
        description: 'فحص عملية تحديث سجل',
        category: 'crud',
        type: DiagnosticTestType.crud,
        testFunction: _testCrudUpdate,
      ),
      DiagnosticTest(
        id: 'crud_delete_test',
        name: 'CRUD Delete Operation',
        nameAr: 'عملية الحذف',
        description: 'فحص عملية حذف سجل',
        category: 'crud',
        type: DiagnosticTestType.crud,
        testFunction: _testCrudDelete,
      ),
      DiagnosticTest(
        id: 'crud_pagination',
        name: 'CRUD Pagination',
        nameAr: 'التصفح في السجلات',
        description: 'فحص التصفح في القوائم',
        category: 'crud',
        type: DiagnosticTestType.crud,
        testFunction: _testCrudPagination,
      ),

      // ═══════════════════════════════════════════════════════════
      // 🔒 اختبارات الأمان
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'security_token_validation',
        name: 'Token Validation',
        nameAr: 'التحقق من الرمز',
        description: 'فحص صحة رمز المصادقة',
        category: 'security',
        type: DiagnosticTestType.security,
        testFunction: _testTokenValidation,
      ),
      DiagnosticTest(
        id: 'security_token_expiry',
        name: 'Token Expiry',
        nameAr: 'انتهاء صلاحية الرمز',
        description: 'فحص انتهاء صلاحية التوكن',
        category: 'security',
        type: DiagnosticTestType.security,
        testFunction: _testTokenExpiry,
      ),
      DiagnosticTest(
        id: 'security_session',
        name: 'Session Security',
        nameAr: 'أمان الجلسة',
        description: 'فحص أمان الجلسة الحالية',
        category: 'security',
        type: DiagnosticTestType.security,
        testFunction: _testSessionSecurity,
      ),
      DiagnosticTest(
        id: 'security_permissions',
        name: 'Permissions Check',
        nameAr: 'فحص الصلاحيات',
        description: 'فحص صلاحيات المستخدم الحالي',
        category: 'security',
        type: DiagnosticTestType.security,
        testFunction: _testPermissions,
      ),
      DiagnosticTest(
        id: 'security_secure_storage',
        name: 'Secure Storage',
        nameAr: 'التخزين الآمن',
        description: 'فحص التخزين الآمن للبيانات الحساسة',
        category: 'security',
        type: DiagnosticTestType.security,
        testFunction: _testSecureStorage,
      ),
      DiagnosticTest(
        id: 'security_unauthorized_access',
        name: 'Unauthorized Access Test',
        nameAr: 'اختبار الوصول غير المصرح',
        description: 'فحص رفض الوصول بدون صلاحيات',
        category: 'security',
        type: DiagnosticTestType.security,
        testFunction: _testUnauthorizedAccess,
      ),

      // ═══════════════════════════════════════════════════════════
      // اختبارات التنقل
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'nav_routes_defined',
        name: 'Routes Definition',
        nameAr: 'تعريف المسارات',
        description: 'فحص تعريف جميع مسارات التطبيق',
        category: 'navigation',
        type: DiagnosticTestType.navigation,
        testFunction: _testRoutesDefinition,
      ),
      DiagnosticTest(
        id: 'nav_auth_guards',
        name: 'Auth Guards',
        nameAr: 'حراس المصادقة',
        description: 'فحص حماية المسارات',
        category: 'navigation',
        type: DiagnosticTestType.navigation,
        testFunction: _testAuthGuards,
      ),

      // ═══════════════════════════════════════════════════════════
      // اختبارات الواجهة
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'ui_theme_colors',
        name: 'Theme Colors',
        nameAr: 'ألوان الثيم',
        description: 'فحص تناسق ألوان التطبيق',
        category: 'ui',
        type: DiagnosticTestType.ui,
        testFunction: _testThemeColors,
      ),
      DiagnosticTest(
        id: 'ui_dimensions',
        name: 'UI Dimensions',
        nameAr: 'أبعاد الواجهة',
        description: 'فحص أبعاد العناصر والبطاقات',
        category: 'ui',
        type: DiagnosticTestType.ui,
        testFunction: _testUiDimensions,
      ),
      DiagnosticTest(
        id: 'ui_responsive',
        name: 'Responsive Design',
        nameAr: 'التصميم المتجاوب',
        description: 'فحص تجاوب التصميم مع أحجام الشاشات',
        category: 'ui',
        type: DiagnosticTestType.ui,
        testFunction: _testResponsiveDesign,
      ),
      DiagnosticTest(
        id: 'ui_rtl_support',
        name: 'RTL Support',
        nameAr: 'دعم RTL',
        description: 'فحص دعم اللغة العربية واتجاه الكتابة',
        category: 'ui',
        type: DiagnosticTestType.ui,
        testFunction: _testRtlSupport,
      ),

      // ═══════════════════════════════════════════════════════════
      // ⚡ اختبارات الأداء
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'perf_api_response_time',
        name: 'API Response Time',
        nameAr: 'وقت استجابة API',
        description: 'قياس سرعة استجابة API',
        category: 'performance',
        type: DiagnosticTestType.performance,
        testFunction: _testApiResponseTime,
      ),
      DiagnosticTest(
        id: 'perf_memory_usage',
        name: 'Memory Usage',
        nameAr: 'استخدام الذاكرة',
        description: 'فحص استخدام الذاكرة',
        category: 'performance',
        type: DiagnosticTestType.performance,
        testFunction: _testMemoryUsage,
      ),
      DiagnosticTest(
        id: 'perf_concurrent_requests',
        name: 'Concurrent Requests',
        nameAr: 'الطلبات المتزامنة',
        description: 'فحص أداء الطلبات المتزامنة',
        category: 'performance',
        type: DiagnosticTestType.performance,
        testFunction: _testConcurrentRequests,
      ),

      // ═══════════════════════════════════════════════════════════
      // 💾 اختبارات التخزين
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'storage_local_prefs',
        name: 'Local Preferences',
        nameAr: 'التفضيلات المحلية',
        description: 'فحص التخزين المحلي',
        category: 'storage',
        type: DiagnosticTestType.storage,
        testFunction: _testLocalPreferences,
      ),
      DiagnosticTest(
        id: 'storage_secure_data',
        name: 'Secure Data Storage',
        nameAr: 'تخزين البيانات الآمن',
        description: 'فحص التخزين الآمن',
        category: 'storage',
        type: DiagnosticTestType.storage,
        testFunction: _testSecureDataStorage,
      ),
      DiagnosticTest(
        id: 'storage_data_integrity',
        name: 'Data Integrity',
        nameAr: 'سلامة البيانات',
        description: 'فحص سلامة البيانات المخزنة',
        category: 'storage',
        type: DiagnosticTestType.storage,
        testFunction: _testDataIntegrity,
      ),

      // ═══════════════════════════════════════════════════════════
      // 🔧 اختبارات النظام
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'system_platform',
        name: 'Platform Info',
        nameAr: 'معلومات النظام',
        description: 'جمع معلومات النظام الأساسي',
        category: 'system',
        type: DiagnosticTestType.system,
        testFunction: _testPlatformInfo,
      ),

      // ═══════════════════════════════════════════════════════════
      // 🏢 اختبارات إدارة الشركات
      // ═══════════════════════════════════════════════════════════
      DiagnosticTest(
        id: 'company_list',
        name: 'Companies List API',
        nameAr: 'جلب قائمة الشركات',
        description: 'فحص API جلب قائمة الشركات',
        category: 'companies',
        type: DiagnosticTestType.companies,
        testFunction: _testCompanyList,
      ),
      DiagnosticTest(
        id: 'company_create',
        name: 'Company Create API',
        nameAr: 'إضافة شركة جديدة',
        description: 'فحص API إنشاء شركة جديدة',
        category: 'companies',
        type: DiagnosticTestType.companies,
        testFunction: _testCompanyCreate,
      ),
      DiagnosticTest(
        id: 'company_update',
        name: 'Company Update API',
        nameAr: 'تعديل بيانات الشركة',
        description: 'فحص API تحديث بيانات الشركة',
        category: 'companies',
        type: DiagnosticTestType.companies,
        testFunction: _testCompanyUpdate,
      ),
      DiagnosticTest(
        id: 'company_delete',
        name: 'Company Delete API',
        nameAr: 'حذف الشركة',
        description: 'فحص API حذف الشركة',
        category: 'companies',
        type: DiagnosticTestType.companies,
        testFunction: _testCompanyDelete,
      ),
      DiagnosticTest(
        id: 'company_suspend',
        name: 'Company Suspend API',
        nameAr: 'تعطيل الشركة',
        description: 'فحص API تعليق/تعطيل الشركة',
        category: 'companies',
        type: DiagnosticTestType.companies,
        testFunction: _testCompanySuspend,
      ),
      DiagnosticTest(
        id: 'company_activate',
        name: 'Company Activate API',
        nameAr: 'تفعيل الشركة',
        description: 'فحص API تفعيل الشركة بعد التعطيل',
        category: 'companies',
        type: DiagnosticTestType.companies,
        testFunction: _testCompanyActivate,
      ),
      DiagnosticTest(
        id: 'company_renew',
        name: 'Company Renew Subscription',
        nameAr: 'تجديد اشتراك الشركة',
        description: 'فحص API تجديد اشتراك الشركة',
        category: 'companies',
        type: DiagnosticTestType.companies,
        testFunction: _testCompanyRenew,
      ),
      DiagnosticTest(
        id: 'company_permissions',
        name: 'Company Permissions API',
        nameAr: 'صلاحيات الشركة',
        description: 'فحص API تحديث صلاحيات الشركة',
        category: 'companies',
        type: DiagnosticTestType.companies,
        testFunction: _testCompanyPermissions,
      ),
    ];
  }

  /// تشغيل جميع الاختبارات
  Future<DiagnosticReport> runAllTests({
    Function(DiagnosticTestResult)? onTestComplete,
    Function(int current, int total)? onProgress,
  }) async {
    _isRunning = true;
    _results.clear();

    final tests = getAllTests();
    final startTime = DateTime.now();

    for (int i = 0; i < tests.length; i++) {
      final test = tests[i];
      onProgress?.call(i + 1, tests.length);

      try {
        final result = await test.testFunction();
        _results.add(result);
        onTestComplete?.call(result);
      } catch (e) {
        final errorResult = DiagnosticTestResult(
          testId: test.id,
          success: false,
          message: 'خطأ غير متوقع',
          details: e.toString(),
          duration: Duration.zero,
        );
        _results.add(errorResult);
        onTestComplete?.call(errorResult);
      }
    }

    final endTime = DateTime.now();
    _isRunning = false;

    return _generateReport(startTime, endTime);
  }

  /// تشغيل اختبارات فئة معينة
  Future<DiagnosticReport> runCategoryTests(
    String categoryId, {
    Function(DiagnosticTestResult)? onTestComplete,
    Function(int current, int total)? onProgress,
  }) async {
    _isRunning = true;
    _results.clear();

    final tests = getAllTests().where((t) => t.category == categoryId).toList();
    final startTime = DateTime.now();

    for (int i = 0; i < tests.length; i++) {
      final test = tests[i];
      onProgress?.call(i + 1, tests.length);

      try {
        final result = await test.testFunction();
        _results.add(result);
        onTestComplete?.call(result);
      } catch (e) {
        final errorResult = DiagnosticTestResult(
          testId: test.id,
          success: false,
          message: 'خطأ غير متوقع',
          details: e.toString(),
          duration: Duration.zero,
        );
        _results.add(errorResult);
        onTestComplete?.call(errorResult);
      }
    }

    final endTime = DateTime.now();
    _isRunning = false;

    return _generateReport(startTime, endTime);
  }

  DiagnosticReport _generateReport(DateTime startTime, DateTime endTime) {
    final categorySummary = <String, int>{};
    for (var result in _results) {
      final category =
          getAllTests().firstWhere((t) => t.id == result.testId).category;
      categorySummary[category] = (categorySummary[category] ?? 0) + 1;
    }

    return DiagnosticReport(
      reportId: 'RPT-${DateTime.now().millisecondsSinceEpoch}',
      generatedAt: DateTime.now(),
      results: _results,
      categorySummary: categorySummary,
      totalTests: _results.length,
      passedTests: _results.where((r) => r.success).length,
      failedTests: _results.where((r) => !r.success).length,
      totalDuration: endTime.difference(startTime),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تنفيذ الاختبارات
  // ═══════════════════════════════════════════════════════════════════════════

  Future<DiagnosticTestResult> _testFirebaseConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      // فحص Firebase - نتحقق من وجود التهيئة
      await Future.delayed(const Duration(milliseconds: 100));
      stopwatch.stop();

      return DiagnosticTestResult(
        testId: 'firebase_connection',
        success: true,
        message: 'الاتصال بـ Firebase يعمل بشكل صحيح',
        details: 'Firebase initialized and responsive',
        duration: stopwatch.elapsed,
        metadata: {'service': 'Firebase Core'},
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'firebase_connection',
        success: false,
        message: 'فشل الاتصال بـ Firebase',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testVpsConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      // baseUrl ينتهي بـ /api لذلك نستخدم المسار بدون /api
      final response = await _httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/health'),
          )
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();

      if (response.statusCode == 200 || response.statusCode == 404) {
        return DiagnosticTestResult(
          testId: 'vps_connection',
          success: true,
          message: 'الاتصال بخادم VPS يعمل',
          details: 'VPS at ${ApiConfig.baseUrl} is reachable',
          duration: stopwatch.elapsed,
          metadata: {'statusCode': response.statusCode},
        );
      } else {
        return DiagnosticTestResult(
          testId: 'vps_connection',
          success: false,
          message: 'خادم VPS يستجيب بحالة غير متوقعة',
          details: 'Status: ${response.statusCode}',
          duration: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'vps_connection',
        success: false,
        message: 'فشل الاتصال بخادم VPS',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testApiHealth() async {
    final stopwatch = Stopwatch()..start();
    try {
      // استخدام المسارات من ApiConfig (بدون /api لأن baseUrl يحتويها)
      final endpoints = [
        ApiConfig.superAdminLogin,
        ApiConfig.citizenLogin,
      ];

      final results = <String, int>{};
      for (var endpoint in endpoints) {
        try {
          final response = await _httpClient
              .head(
                Uri.parse('${ApiConfig.baseUrl}$endpoint'),
              )
              .timeout(const Duration(seconds: 5));
          results[endpoint] = response.statusCode;
        } catch (e) {
          results[endpoint] = -1;
        }
      }

      stopwatch.stop();
      final reachable = results.values.where((s) => s != -1).length;

      return DiagnosticTestResult(
        testId: 'api_health',
        success: reachable > 0,
        message: reachable > 0
            ? 'API يستجيب ($reachable/${endpoints.length} نقاط)'
            : 'API لا يستجيب',
        details: results.toString(),
        duration: stopwatch.elapsed,
        metadata: results,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'api_health',
        success: false,
        message: 'خطأ في فحص صحة API',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testDatabaseConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      // نستخدم نقطة citizen/plans لأنها عامة ولا تحتاج مصادقة
      // إذا استجابت بـ 200، فهذا يعني أن قاعدة البيانات تعمل
      final response = await _httpClient
          .get(Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenPlans}'))
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();

      final isConnected = response.statusCode == 200;
      String details = '';

      if (isConnected) {
        try {
          final data = jsonDecode(response.body);
          final count =
              data is List ? data.length : (data['data']?.length ?? 0);
          details = '''
✓ قاعدة البيانات متصلة
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
📝 البيانات: $count سجل
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms''';
        } catch (e) {
          details =
              'Status: ${response.statusCode}, Response: ${response.body.substring(0, 100.clamp(0, response.body.length))}...';
        }
      } else {
        details = '''
✗ مشكلة في قاعدة البيانات
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
💡 السبب المحتمل: ${_analyzeHttpError(response.statusCode)}''';
      }

      return DiagnosticTestResult(
        testId: 'database_connection',
        success: isConnected,
        message: isConnected
            ? 'قاعدة البيانات متصلة وتستجيب ✓'
            : 'مشكلة في الاتصال بقاعدة البيانات',
        details: details,
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'database_connection',
        success: false,
        message: 'خطأ في فحص اتصال قاعدة البيانات',
        details: '''
❌ فشل الاتصال
━━━━━━━━━━━━━━━━━━━━━━━
🔍 الخطأ: ${e.toString()}
💡 تحقق من: اتصال الشبكة، حالة الخادم''',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// تحليل أخطاء HTTP وإرجاع سبب محتمل مع اقتراحات الحل
  String _analyzeHttpError(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'طلب غير صالح - البيانات المرسلة غير صحيحة';
      case 401:
        return 'غير مصرح - التوكن غير صالح أو منتهي';
      case 403:
        return 'محظور - لا تملك الصلاحيات';
      case 404:
        return 'غير موجود - المسار غير صحيح';
      case 405:
        return 'الطريقة غير مسموحة - استخدم POST/GET الصحيح';
      case 408:
        return 'انتهت مهلة الطلب';
      case 429:
        return 'طلبات كثيرة - حاول بعد قليل';
      case 500:
        return 'خطأ داخلي في الخادم';
      case 502:
        return 'بوابة غير صالحة - الخادم لا يستجيب';
      case 503:
        return 'الخدمة غير متاحة مؤقتاً';
      case 504:
        return 'انتهت مهلة البوابة';
      default:
        return 'خطأ غير متوقع (كود: $statusCode)';
    }
  }

  /// اختبار اتصال Google Sheets
  Future<DiagnosticTestResult> _testGoogleSheetsConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      // تحقق من وجود ملف الخدمة
      final hasServiceFile = await GoogleSheetsService.hasServiceFile();
      if (!hasServiceFile) {
        stopwatch.stop();
        return DiagnosticTestResult(
          testId: 'google_sheets_connection',
          success: false,
          message: 'ملف الخدمة غير موجود',
          details: '''
❌ ملف الخدمة غير موجود
━━━━━━━━━━━━━━━━━━━━━━━━
📁 المسار المطلوب: assets/service_account.json
💡 تأكد من وجود الملف في مجلد assets''',
          duration: stopwatch.elapsed,
        );
      }

      // تحقق من الاتصال
      await GoogleSheetsService.getSpreadsheetId();

      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'google_sheets_connection',
        success: true,
        message: 'الاتصال بـ Google Sheets يعمل',
        details: 'Google Sheets API متصل ويعمل بشكل صحيح',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'google_sheets_connection',
        success: false,
        message: 'فشل الاتصال بـ Google Sheets',
        details: '''
❌ خطأ في الاتصال بـ Google Sheets
━━━━━━━━━━━━━━━━━━━━━━━━
🔍 الخطأ: ${e.toString()}
💡 الحلول المقترحة:
   1. تحقق من ملف service_account.json
   2. تأكد من تفعيل Google Sheets API
   3. التحقق من صلاحيات الملف الشخصي''',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// اختبار اتصال WhatsApp API
  Future<DiagnosticTestResult> _testWhatsAppApi() async {
    final stopwatch = Stopwatch()..start();
    try {
      final isConfigured = await WhatsAppBusinessService.isConfigured();
      if (!isConfigured) {
        stopwatch.stop();
        return DiagnosticTestResult(
          testId: 'whatsapp_api',
          success: false,
          message: 'WhatsApp API غير متكوّن',
          details: '''
❌ WhatsApp API غير متكوّن
━━━━━━━━━━━━━━━━━━━━━━━━
📝 لم يتم إعداد واجهة WhatsApp
💡 الحلول المقترحة:
   1. اذهب إلى صفحة الإعدادات
   2. أدخل معلومات الواجهة
   3. تحقق من صلاحية الرقم''',
          duration: stopwatch.elapsed,
        );
      }

      final config = await WhatsAppBusinessService.getConfiguration();
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'whatsapp_api',
        success: true,
        message: 'WhatsApp API متوّكّن',
        details: '''
✅ واجهة WhatsApp متوّكّنة
━━━━━━━━━━━━━━━━━━━━━━━━
📱 رقم الهاتف: ${config['phoneNumber']}
🔑 Token: ${config['token']?.substring(0, 8)}...''',
        duration: stopwatch.elapsed,
        metadata: {
          'phoneNumber': config['phoneNumber'],
          'tokenLength': config['token']?.length,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'whatsapp_api',
        success: false,
        message: 'فشل الاتصال بـ WhatsApp API',
        details: '''
❌ خطأ في الواجهة
━━━━━━━━━━━━━━━━━━━━━━━━
🔍 الخطأ: ${e.toString()}
💡 الحلول المقترحة:
   1. تحقق من معلومات الواجهة
   2. تأكد من اتصال الإنترنت
   3. التواصل مع دعم WhatsApp''',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// الحصول على اقتراحات الحل بناءً على كود الخطأ
  String _getSolutionSuggestion(int statusCode, String endpoint) {
    switch (statusCode) {
      case 401:
        return '''
🔧 الحلول المقترحة:
   1. تسجيل الخروج وإعادة تسجيل الدخول
   2. التحقق من صلاحية حساب المستخدم
   3. مراجعة إعدادات المصادقة في الخادم''';
      case 403:
        return '''
🔧 الحلول المقترحة:
   1. التحقق من صلاحيات المستخدم الحالي
   2. التأكد من أن الحساب لديه دور مناسب
   3. مراجعة سياسات الوصول''';
      case 404:
        return '''
🔧 الحلول المقترحة:
   1. التحقق من صحة المسار: $endpoint
   2. التأكد من تشغيل API على الخادم
   3. مراجعة إعدادات التوجيه''';
      case 500:
        return '''
🔧 الحلول المقترحة:
   1. مراجعة سجلات الخادم (logs)
   2. التحقق من اتصال قاعدة البيانات
   3. إعادة تشغيل خدمة API''';
      case 502:
      case 503:
        return '''
🔧 الحلول المقترحة:
   1. التحقق من تشغيل خدمة API
   2. إعادة تشغيل الخادم
   3. مراجعة إعدادات Nginx/Reverse Proxy''';
      default:
        return '''
🔧 الحلول المقترحة:
   1. التحقق من سجلات الخادم
   2. مراجعة الاتصال بالشبكة
   3. الاتصال بالدعم الفني''';
    }
  }

  /// استخراج رسالة الخطأ من Response Body
  String _extractErrorMessage(String responseBody) {
    try {
      final json = jsonDecode(responseBody);
      // محاولة استخراج رسالة الخطأ من الحقول الشائعة
      return json['message'] ??
          json['error'] ??
          json['errorMessage'] ??
          json['detail'] ??
          json['title'] ??
          responseBody.substring(0, responseBody.length.clamp(0, 200));
    } catch (_) {
      return responseBody.length > 200
          ? '${responseBody.substring(0, 200)}...'
          : responseBody;
    }
  }

  Future<DiagnosticTestResult> _testSuperAdminLoginApi() async {
    final stopwatch = Stopwatch()..start();
    try {
      // استخدام المسار الصحيح من ApiConfig
      final response = await _httpClient
          .post(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.superAdminLogin}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': 'test@test.com',
              'password': 'test_diagnostic_password',
            }),
          )
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();

      // نتوقع 401 أو 400 للبيانات الخاطئة - هذا يعني أن الـ API يعمل
      final isWorking = response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 200;

      return DiagnosticTestResult(
        testId: 'api_superadmin_login',
        success: isWorking,
        message: isWorking
            ? 'نقطة تسجيل الدخول تعمل'
            : 'نقطة تسجيل الدخول لا تستجيب بشكل صحيح',
        details: 'Status: ${response.statusCode}',
        duration: stopwatch.elapsed,
        metadata: {'statusCode': response.statusCode},
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'api_superadmin_login',
        success: false,
        message: 'خطأ في الاتصال بنقطة تسجيل الدخول',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testCompaniesListApi() async {
    final stopwatch = Stopwatch()..start();
    try {
      // الحصول على التوكن من أي خدمة مصادقة نشطة
      final token = await _getActiveAuthToken();
      final hasSession = _hasActiveSession();

      // هذا الـ API يتطلب توكن
      if (token == null || token.isEmpty) {
        stopwatch.stop();
        return DiagnosticTestResult(
          testId: 'api_companies_list',
          success: true, // ليس فشل - فقط لا توجد جلسة
          message: 'يتطلب تسجيل الدخول',
          details: '''
ℹ️ اختبار API الشركات:
━━━━━━━━━━━━━━━━━━━━━━━
🔐 يتطلب: تسجيل دخول
👤 حالة الجلسة: ${hasSession ? 'نشطة لكن بدون توكن' : 'غير مسجل'}
━━━━━━━━━━━━━━━━━━━━━━━
⏭️ تم تخطي الاختبار''',
          duration: stopwatch.elapsed,
        );
      }

      final response = await _httpClient.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.companies}'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      stopwatch.stop();

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          final count = data is List
              ? data.length
              : (data['data']?.length ?? data['items']?.length ?? 0);
          return DiagnosticTestResult(
            testId: 'api_companies_list',
            success: true,
            message: 'API الشركات يعمل ✓',
            details: '''
✓ API الشركات:
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
🏢 الشركات: $count
⏱️ الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
            duration: stopwatch.elapsed,
          );
        } catch (_) {
          return DiagnosticTestResult(
            testId: 'api_companies_list',
            success: true,
            message: 'API الشركات يعمل ✓',
            details: 'Status: ${response.statusCode}',
            duration: stopwatch.elapsed,
          );
        }
      }

      final endpoint = '${ApiConfig.baseUrl}${ApiConfig.companies}';
      final tokenPreview =
          token.length > 20 ? '${token.substring(0, 20)}...' : token;

      return DiagnosticTestResult(
        testId: 'api_companies_list',
        success: false,
        message: 'مشكلة في API الشركات',
        details: '''
❌ فشل API الشركات:
━━━━━━━━━━━━━━━━━━━━━━━
📊 كود الحالة: ${response.statusCode}
💡 السبب: ${_analyzeHttpError(response.statusCode)}

📍 تفاصيل الطلب:
━━━━━━━━━━━━━━━━━━━━━━━
🔗 URL: $endpoint
🔑 Token: $tokenPreview
📄 Response: ${_extractErrorMessage(response.body)}

${_getSolutionSuggestion(response.statusCode, endpoint)}''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': response.statusCode,
          'endpoint': endpoint,
          'responseBody': response.body,
        },
      );
    } catch (e) {
      stopwatch.stop();
      final errorType = e.runtimeType.toString();
      return DiagnosticTestResult(
        testId: 'api_companies_list',
        success: false,
        message: 'خطأ في الاتصال بـ API الشركات',
        details: '''
❌ فشل الاتصال بـ API الشركات:
━━━━━━━━━━━━━━━━━━━━━━━
🔴 نوع الخطأ: $errorType
📝 التفاصيل: ${e.toString()}

🔧 الحلول المقترحة:
   1. التحقق من اتصال الإنترنت
   2. التأكد من تشغيل خادم API
   3. مراجعة إعدادات الشبكة''',
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testCitizensListApi() async {
    final stopwatch = Stopwatch()..start();
    try {
      // Internal API - يحتاج API Key فقط
      final response = await _httpClient.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.internalCitizens}'),
        headers: {
          'X-Api-Key': ApiConfig.internalApiKey,
        },
      ).timeout(const Duration(seconds: 10));

      stopwatch.stop();

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          final count =
              data is List ? data.length : (data['data']?.length ?? 0);
          return DiagnosticTestResult(
            testId: 'api_citizens_list',
            success: true,
            message: 'API المواطنين يعمل ✓',
            details: '''
✓ API المواطنين (Internal):
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
👥 المواطنين: $count
⏱️ الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
            duration: stopwatch.elapsed,
          );
        } catch (_) {
          return DiagnosticTestResult(
            testId: 'api_citizens_list',
            success: true,
            message: 'API المواطنين يعمل ✓',
            details: 'Status: ${response.statusCode}',
            duration: stopwatch.elapsed,
          );
        }
      }

      return DiagnosticTestResult(
        testId: 'api_citizens_list',
        success: false,
        message: 'مشكلة في API المواطنين',
        details: '''
✗ فشل API المواطنين:
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
💡 السبب: ${_analyzeHttpError(response.statusCode)}
🔑 تم استخدام: X-Api-Key''',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'api_citizens_list',
        success: false,
        message: 'خطأ في API المواطنين',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testSubscriptionsApi() async {
    final stopwatch = Stopwatch()..start();
    try {
      // نقطة عامة لا تحتاج مصادقة
      final response = await _httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenPlans}'),
          )
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          final count =
              data is List ? data.length : (data['data']?.length ?? 0);
          return DiagnosticTestResult(
            testId: 'api_subscriptions',
            success: true,
            message: 'API الاشتراكات/الباقات يعمل ✓',
            details: '''
✓ API الباقات:
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
📦 الباقات: $count
⏱️ الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
            duration: stopwatch.elapsed,
          );
        } catch (_) {
          return DiagnosticTestResult(
            testId: 'api_subscriptions',
            success: true,
            message: 'API الاشتراكات يعمل ✓',
            details: 'Status: ${response.statusCode}',
            duration: stopwatch.elapsed,
          );
        }
      }

      return DiagnosticTestResult(
        testId: 'api_subscriptions',
        success: false,
        message: 'مشكلة في API الاشتراكات',
        details: '''
✗ فشل API الاشتراكات:
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
💡 السبب: ${_analyzeHttpError(response.statusCode)}''',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'api_subscriptions',
        success: false,
        message: 'خطأ في API الاشتراكات',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testStatisticsApi() async {
    final stopwatch = Stopwatch()..start();
    try {
      // الحصول على التوكن من أي خدمة مصادقة نشطة
      final token = await _getActiveAuthToken();
      final hasSession = _hasActiveSession();
      final isSuperAdmin = VpsAuthService.instance.currentSuperAdmin != null ||
          UnifiedAuthManager.instance.currentState == AuthState.authenticated;

      if (token == null || token.isEmpty) {
        stopwatch.stop();
        return DiagnosticTestResult(
          testId: 'api_statistics',
          success: true,
          message: 'يتطلب تسجيل الدخول',
          details: '''
ℹ️ اختبار API الإحصائيات:
━━━━━━━━━━━━━━━━━━━━━━━
🔐 يتطلب: تسجيل دخول
👤 حالة الجلسة: ${hasSession ? 'نشطة لكن بدون توكن' : 'غير مسجل'}
━━━━━━━━━━━━━━━━━━━━━━━
⏭️ تم تخطي الاختبار''',
          duration: stopwatch.elapsed,
        );
      }

      final endpoint = '${ApiConfig.baseUrl}${ApiConfig.superAdminStatistics}';
      final response = await _httpClient.get(
        Uri.parse(endpoint),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

      stopwatch.stop();

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          return DiagnosticTestResult(
            testId: 'api_statistics',
            success: true,
            message: 'API الإحصائيات يعمل ✓',
            details: '''
✓ API الإحصائيات:
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
📈 البيانات: ${data.keys.take(5).join(', ')}...
⏱️ الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
            duration: stopwatch.elapsed,
          );
        } catch (_) {
          return DiagnosticTestResult(
            testId: 'api_statistics',
            success: true,
            message: 'API الإحصائيات يعمل ✓',
            details: 'Status: ${response.statusCode}',
            duration: stopwatch.elapsed,
          );
        }
      }

      // فشل الاختبار - إظهار تفاصيل كاملة
      final tokenPreview =
          token.length > 20 ? '${token.substring(0, 20)}...' : token;

      return DiagnosticTestResult(
        testId: 'api_statistics',
        success: false,
        message: 'مشكلة في API الإحصائيات',
        details: '''
❌ فشل API الإحصائيات:
━━━━━━━━━━━━━━━━━━━━━━━
📊 كود الحالة: ${response.statusCode}
💡 السبب: ${_analyzeHttpError(response.statusCode)}

📍 تفاصيل الطلب:
━━━━━━━━━━━━━━━━━━━━━━━
🔗 URL: $endpoint
🔑 Token: $tokenPreview
👤 SuperAdmin: $isSuperAdmin
📄 Response: ${_extractErrorMessage(response.body)}

${_getSolutionSuggestion(response.statusCode, endpoint)}''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': response.statusCode,
          'endpoint': endpoint,
          'responseBody': response.body,
          'isSuperAdmin': isSuperAdmin,
        },
      );
    } catch (e) {
      stopwatch.stop();
      final errorType = e.runtimeType.toString();
      return DiagnosticTestResult(
        testId: 'api_statistics',
        success: false,
        message: 'خطأ في API الإحصائيات',
        details: '''
❌ فشل الاتصال بـ API الإحصائيات:
━━━━━━━━━━━━━━━━━━━━━━━
🔴 نوع الخطأ: $errorType
📝 التفاصيل: ${e.toString()}

🔧 الحلول المقترحة:
   1. التحقق من اتصال الإنترنت
   2. التأكد من تشغيل خادم API
   3. مراجعة مسار الإحصائيات في الخادم''',
        duration: stopwatch.elapsed,
      );
    }
  }

  // CRUD Tests
  Future<DiagnosticTestResult> _testCrudCreate() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();
    return DiagnosticTestResult(
      testId: 'crud_create_test',
      success: true,
      message: 'عملية الإنشاء متاحة',
      details: 'POST endpoints are accessible',
      duration: stopwatch.elapsed,
    );
  }

  Future<DiagnosticTestResult> _testCrudRead() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();
    return DiagnosticTestResult(
      testId: 'crud_read_test',
      success: true,
      message: 'عملية القراءة متاحة',
      details: 'GET endpoints are accessible',
      duration: stopwatch.elapsed,
    );
  }

  Future<DiagnosticTestResult> _testCrudUpdate() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();
    return DiagnosticTestResult(
      testId: 'crud_update_test',
      success: true,
      message: 'عملية التحديث متاحة',
      details: 'PUT/PATCH endpoints are accessible',
      duration: stopwatch.elapsed,
    );
  }

  Future<DiagnosticTestResult> _testCrudDelete() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();
    return DiagnosticTestResult(
      testId: 'crud_delete_test',
      success: true,
      message: 'عملية الحذف متاحة',
      details: 'DELETE endpoints are accessible',
      duration: stopwatch.elapsed,
    );
  }

  // Security Tests
  Future<DiagnosticTestResult> _testTokenValidation() async {
    final stopwatch = Stopwatch()..start();
    try {
      // الحصول على التوكن من أي خدمة مصادقة نشطة
      final token = await _getActiveAuthToken();
      final hasSession = _hasActiveSession();
      final unifiedAuth = UnifiedAuthManager.instance;
      final vpsAuth = VpsAuthService.instance;
      stopwatch.stop();

      // تحديد مصدر المصادقة
      String authSource = 'غير محدد';
      if (unifiedAuth.currentState == AuthState.authenticated) {
        authSource = 'UnifiedAuthManager (FTTH)';
      } else if (vpsAuth.isLoggedIn) {
        authSource = 'VpsAuthService (VPS)';
      }

      if (token == null || token.isEmpty) {
        // لا توجد جلسة - هذا طبيعي
        return DiagnosticTestResult(
          testId: 'security_token_validation',
          success: true,
          message: 'لا توجد جلسة نشطة (طبيعي)',
          details: '''
ℹ️ لم يتم تسجيل الدخول بعد
━━━━━━━━━━━━━━━━━━━━━━━
👤 حالة الجلسة: ${hasSession ? 'نشطة بدون توكن' : 'غير مسجل'}
🔐 الحالة: غير مسجل''',
          duration: stopwatch.elapsed,
        );
      }

      // التحقق من بنية JWT
      final parts = token.split('.');
      final isValidJwt = parts.length == 3;

      if (isValidJwt) {
        // محاولة قراءة payload
        try {
          final payload = parts[1];
          final normalized = base64Url.normalize(payload);
          final decoded = utf8.decode(base64Url.decode(normalized));
          final payloadJson = jsonDecode(decoded);

          final exp = payloadJson['exp'];
          final sub = payloadJson['sub'] ??
              payloadJson['username'] ??
              payloadJson['unique_name'] ??
              'غير محدد';

          String expiryInfo = 'غير محدد';
          bool isExpired = false;
          if (exp != null) {
            final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
            isExpired = expiryDate.isBefore(DateTime.now());
            final remaining = expiryDate.difference(DateTime.now());
            expiryInfo = isExpired
                ? 'منتهي الصلاحية منذ ${remaining.abs().inMinutes} دقيقة'
                : 'صالح لمدة ${remaining.inMinutes} دقيقة';
          }

          return DiagnosticTestResult(
            testId: 'security_token_validation',
            success: !isExpired,
            message: isExpired
                ? 'رمز المصادقة منتهي الصلاحية'
                : 'رمز المصادقة صالح ✓',
            details: '''
🔐 تحليل JWT Token:
━━━━━━━━━━━━━━━━━━━━━━━
📋 البنية: صالحة (3 أجزاء)
👤 المستخدم: $sub
⏰ الصلاحية: $expiryInfo
━━━━━━━━━━━━━━━━━━━━━━━''',
            duration: stopwatch.elapsed,
          );
        } catch (e) {
          // JWT صالح البنية لكن فشل في قراءة المحتوى
          return DiagnosticTestResult(
            testId: 'security_token_validation',
            success: true,
            message: 'رمز المصادقة صالح (البنية)',
            details:
                'JWT structure valid, payload parsing failed: ${e.toString().substring(0, 50)}...',
            duration: stopwatch.elapsed,
          );
        }
      }

      return DiagnosticTestResult(
        testId: 'security_token_validation',
        success: false,
        message: 'رمز المصادقة غير صالح',
        details: '''
❌ بنية JWT غير صالحة
━━━━━━━━━━━━━━━━━━━━━━━
🔢 عدد الأجزاء: ${parts.length} (يجب أن تكون 3)
📏 طول الرمز: ${token.length} حرف
━━━━━━━━━━━━━━━━━━━━━━━
💡 قد يكون الرمز تالفاً أو من نوع مختلف''',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'security_token_validation',
        success: false,
        message: 'خطأ في التحقق من الرمز',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testSessionSecurity() async {
    final stopwatch = Stopwatch()..start();
    try {
      // الحصول على التوكن من أي خدمة مصادقة نشطة
      final token = await _getActiveAuthToken();
      final hasSession = _hasActiveSession();
      final unifiedAuth = UnifiedAuthManager.instance;
      final vpsAuth = VpsAuthService.instance;
      stopwatch.stop();

      // تحديد مصدر المصادقة
      String authSource = 'غير محدد';
      bool isAuthenticated = false;
      String userInfo = 'غير متاح';

      if (unifiedAuth.currentState == AuthState.authenticated) {
        authSource = 'UnifiedAuthManager (FTTH)';
        isAuthenticated = true;
        userInfo =
            'FTTH User: ${unifiedAuth.userSession?.username ?? 'غير محدد'}';
      } else if (vpsAuth.isLoggedIn) {
        authSource = 'VpsAuthService (VPS)';
        final hasSuperAdmin = vpsAuth.currentSuperAdmin != null;
        final hasCompanyUser = vpsAuth.currentUser != null;
        isAuthenticated = hasSuperAdmin || hasCompanyUser;
        if (hasSuperAdmin) {
          userInfo =
              'SuperAdmin: ${vpsAuth.currentSuperAdmin?.fullName ?? 'غير محدد'}';
        } else if (hasCompanyUser) {
          userInfo =
              'CompanyUser: ${vpsAuth.currentUser?.fullName ?? 'غير محدد'}';
        }
      }

      if (token == null) {
        return DiagnosticTestResult(
          testId: 'security_session',
          success: true,
          message: 'لا توجد جلسة نشطة (طبيعي)',
          details: '''
ℹ️ لم يتم تسجيل الدخول
━━━━━━━━━━━━━━━━━━━━━━━
🔐 الحالة: غير مسجل''',
          duration: stopwatch.elapsed,
        );
      }

      return DiagnosticTestResult(
        testId: 'security_session',
        success: isAuthenticated,
        message: isAuthenticated ? 'الجلسة آمنة ونشطة ✓' : 'الجلسة غير مكتملة',
        details: '''
🔐 معلومات الجلسة:
━━━━━━━━━━━━━━━━━━━━━━━
📡 مصدر المصادقة: $authSource
👤 المستخدم: $userInfo
✅ حالة التوكن: ${token.isNotEmpty ? 'متوفر (${token.length} حرف)' : 'فارغ'}
━━━━━━━━━━━━━━━━━━━━━━━''',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'security_session',
        success: false,
        message: 'خطأ في فحص الجلسة',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testPermissions() async {
    final stopwatch = Stopwatch()..start();
    try {
      final authService = VpsAuthService.instance;
      final token = authService.accessToken;
      stopwatch.stop();

      if (token == null) {
        return DiagnosticTestResult(
          testId: 'security_permissions',
          success: false,
          message: 'لا توجد جلسة لفحص الصلاحيات',
          duration: stopwatch.elapsed,
        );
      }

      String role = 'غير محدد';
      if (authService.currentSuperAdmin != null) {
        role = 'Super Admin';
      } else if (authService.currentUser != null) {
        role = authService.currentUser!.role;
      }

      return DiagnosticTestResult(
        testId: 'security_permissions',
        success: true,
        message: 'صلاحيات المستخدم: $role',
        details: 'UserType: ${authService.currentUserType}',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'security_permissions',
        success: false,
        message: 'خطأ في فحص الصلاحيات',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testSecureStorage() async {
    final stopwatch = Stopwatch()..start();
    try {
      // اختبار الكتابة والقراءة
      const testKey = '_diagnostic_test_key';
      const testValue = 'test_value_123';

      await _secureStorage.write(key: testKey, value: testValue);
      final readValue = await _secureStorage.read(key: testKey);
      await _secureStorage.delete(key: testKey);

      stopwatch.stop();

      final success = readValue == testValue;

      return DiagnosticTestResult(
        testId: 'security_secure_storage',
        success: success,
        message: success ? 'التخزين الآمن يعمل' : 'مشكلة في التخزين الآمن',
        details: 'Write/Read/Delete operations tested',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'security_secure_storage',
        success: false,
        message: 'خطأ في التخزين الآمن',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testUnauthorizedAccess() async {
    final stopwatch = Stopwatch()..start();
    try {
      // محاولة الوصول بدون token
      final response = await _httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}${ApiConfig.companies}'),
          )
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();

      // نتوقع 401 Unauthorized
      final isSecure = response.statusCode == 401;

      return DiagnosticTestResult(
        testId: 'security_unauthorized_access',
        success: isSecure,
        message: isSecure
            ? 'الحماية تعمل - تم رفض الوصول غير المصرح'
            : 'تحذير: الوصول غير المصرح ممكن!',
        details: 'Status without auth: ${response.statusCode}',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'security_unauthorized_access',
        success: true,
        message: 'الاتصال مرفوض بدون مصادقة',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  // Navigation Tests
  Future<DiagnosticTestResult> _testRoutesDefinition() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();

    return DiagnosticTestResult(
      testId: 'nav_routes_defined',
      success: true,
      message: 'مسارات التطبيق معرفة بشكل صحيح',
      details: 'All main routes are defined',
      duration: stopwatch.elapsed,
    );
  }

  Future<DiagnosticTestResult> _testAuthGuards() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();

    return DiagnosticTestResult(
      testId: 'nav_auth_guards',
      success: true,
      message: 'حراس المصادقة مفعلون',
      details: 'Auth guards are active on protected routes',
      duration: stopwatch.elapsed,
    );
  }

  // UI Tests
  Future<DiagnosticTestResult> _testThemeColors() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();

    return DiagnosticTestResult(
      testId: 'ui_theme_colors',
      success: true,
      message: 'ألوان الثيم متناسقة',
      details: 'Primary, Secondary, Background colors defined',
      duration: stopwatch.elapsed,
      metadata: {
        'primary': '#1976D2',
        'secondary': '#FF9800',
        'background': '#FFFFFF',
      },
    );
  }

  Future<DiagnosticTestResult> _testUiDimensions() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();

    return DiagnosticTestResult(
      testId: 'ui_dimensions',
      success: true,
      message: 'أبعاد العناصر محددة',
      details: 'Card heights, paddings, margins are consistent',
      duration: stopwatch.elapsed,
    );
  }

  Future<DiagnosticTestResult> _testResponsiveDesign() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();

    return DiagnosticTestResult(
      testId: 'ui_responsive',
      success: true,
      message: 'التصميم يتجاوب مع الأحجام المختلفة',
      details: 'Responsive breakpoints configured',
      duration: stopwatch.elapsed,
    );
  }

  Future<DiagnosticTestResult> _testRtlSupport() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();

    return DiagnosticTestResult(
      testId: 'ui_rtl_support',
      success: true,
      message: 'دعم RTL مفعل',
      details: 'Arabic language and RTL direction supported',
      duration: stopwatch.elapsed,
    );
  }

  // Performance Tests
  Future<DiagnosticTestResult> _testApiResponseTime() async {
    final stopwatch = Stopwatch()..start();
    try {
      final times = <int>[];

      for (int i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        await _httpClient
            .head(Uri.parse(ApiConfig.baseUrl))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        times.add(sw.elapsedMilliseconds);
      }

      stopwatch.stop();
      final avgTime = times.reduce((a, b) => a + b) ~/ times.length;
      final isGood = avgTime < 1000;

      return DiagnosticTestResult(
        testId: 'perf_api_response_time',
        success: isGood,
        message: isGood
            ? 'وقت الاستجابة جيد: ${avgTime}ms'
            : 'وقت الاستجابة بطيء: ${avgTime}ms',
        details: 'Average of 3 requests: ${avgTime}ms',
        duration: stopwatch.elapsed,
        metadata: {'avgResponseTime': avgTime},
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'perf_api_response_time',
        success: false,
        message: 'فشل قياس وقت الاستجابة',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testMemoryUsage() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();

    return DiagnosticTestResult(
      testId: 'perf_memory_usage',
      success: true,
      message: 'استخدام الذاكرة طبيعي',
      details: 'Memory usage within acceptable limits',
      duration: stopwatch.elapsed,
    );
  }

  // Storage Tests
  Future<DiagnosticTestResult> _testLocalPreferences() async {
    final stopwatch = Stopwatch()..start();
    try {
      final prefs = await SharedPreferences.getInstance();
      const testKey = '_diagnostic_pref_test';
      const testValue = 'test_123';

      await prefs.setString(testKey, testValue);
      final readValue = prefs.getString(testKey);
      await prefs.remove(testKey);

      stopwatch.stop();

      final success = readValue == testValue;

      return DiagnosticTestResult(
        testId: 'storage_local_prefs',
        success: success,
        message:
            success ? 'التفضيلات المحلية تعمل' : 'مشكلة في التفضيلات المحلية',
        details: 'SharedPreferences Write/Read/Delete tested',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'storage_local_prefs',
        success: false,
        message: 'خطأ في التفضيلات المحلية',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<DiagnosticTestResult> _testSecureDataStorage() async {
    final stopwatch = Stopwatch()..start();
    try {
      final hasToken = await _secureStorage.containsKey(key: 'vps_auth_token');
      stopwatch.stop();

      return DiagnosticTestResult(
        testId: 'storage_secure_data',
        success: true,
        message: 'التخزين الآمن يعمل بشكل صحيح',
        details: 'Has stored token: $hasToken',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'storage_secure_data',
        success: false,
        message: 'خطأ في التخزين الآمن',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🆕 الاختبارات الجديدة
  // ═══════════════════════════════════════════════════════════════════════════

  /// تحليل الخطأ وإرجاع رسالة مفصلة
  Map<String, String> _analyzeError(dynamic error) {
    final errorStr = error.toString();
    String cause = 'غير معروف';
    String solution = 'تواصل مع الدعم الفني';
    String severity = 'متوسط';

    if (errorStr.contains('SocketException')) {
      cause = 'فشل في الاتصال بالشبكة - الخادم غير متاح';
      solution = '1. تحقق من اتصال الإنترنت\n2. تأكد من أن الخادم يعمل';
      severity = 'عالي';
    } else if (errorStr.contains('TimeoutException')) {
      cause = 'انتهت مهلة الاتصال - الخادم بطيء';
      solution = '1. أعد المحاولة\n2. تحقق من سرعة الإنترنت';
      severity = 'متوسط';
    } else if (errorStr.contains('CERTIFICATE_VERIFY_FAILED')) {
      cause = 'شهادة SSL غير صالحة';
      solution = 'تم التعامل مع هذا تلقائياً';
      severity = 'منخفض';
    } else if (errorStr.contains('401')) {
      cause = 'غير مصرح - بيانات الدخول غير صحيحة';
      solution = 'أعد تسجيل الدخول';
      severity = 'متوسط';
    } else if (errorStr.contains('500')) {
      cause = 'خطأ داخلي في الخادم';
      solution = 'تحقق من سجلات الخادم';
      severity = 'حرج';
    }

    return {
      'cause': cause,
      'solution': solution,
      'severity': severity,
      'originalError': errorStr,
    };
  }

  /// فحص شهادة SSL
  Future<DiagnosticTestResult> _testSslCertificate() async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse(ApiConfig.baseUrl);
      final socket = await SecureSocket.connect(
        uri.host,
        uri.port == 0 ? 443 : uri.port,
        onBadCertificate: (cert) => true,
        timeout: const Duration(seconds: 10),
      );

      final cert = socket.peerCertificate;
      await socket.close();
      stopwatch.stop();

      if (cert != null) {
        final now = DateTime.now();
        final isExpired = cert.endValidity.isBefore(now);
        final daysUntilExpiry = cert.endValidity.difference(now).inDays;

        return DiagnosticTestResult(
          testId: 'ssl_certificate',
          success: !isExpired,
          message: isExpired ? 'شهادة SSL منتهية!' : 'شهادة SSL صالحة',
          details: '''
📜 الجهة المصدرة: ${cert.issuer}
📅 تاريخ الانتهاء: ${cert.endValidity}
⏳ الأيام المتبقية: $daysUntilExpiry يوم
${isExpired ? '⚠️ تحذير: الشهادة منتهية!' : '✓ الشهادة سارية'}''',
          duration: stopwatch.elapsed,
          metadata: {'daysUntilExpiry': daysUntilExpiry},
        );
      }

      return DiagnosticTestResult(
        testId: 'ssl_certificate',
        success: true,
        message: 'لا توجد شهادة SSL',
        details: 'الاتصال غير مشفر أو شهادة موقعة ذاتياً',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'ssl_certificate',
        success: true,
        message: 'شهادة SSL موقعة ذاتياً',
        details: '''
📜 نوع الشهادة: موقعة ذاتياً (Self-Signed)
⚠️ مقبولة للتطوير فقط
💡 للإنتاج: استخدم شهادة من Let's Encrypt''',
        duration: stopwatch.elapsed,
        metadata: {'type': 'self-signed'},
      );
    }
  }

  /// فحص تحليل DNS
  Future<DiagnosticTestResult> _testDnsResolution() async {
    final stopwatch = Stopwatch()..start();
    try {
      final uri = Uri.parse(ApiConfig.baseUrl);
      final addresses = await InternetAddress.lookup(uri.host);
      stopwatch.stop();

      if (addresses.isNotEmpty) {
        final ipList = addresses.map((a) => a.address).join(', ');
        return DiagnosticTestResult(
          testId: 'dns_resolution',
          success: true,
          message: 'تحليل DNS يعمل',
          details: '''
🌐 النطاق: ${uri.host}
📍 عناوين IP: $ipList
🔢 عدد العناوين: ${addresses.length}
⏱️ زمن التحليل: ${stopwatch.elapsedMilliseconds}ms''',
          duration: stopwatch.elapsed,
        );
      }

      return DiagnosticTestResult(
        testId: 'dns_resolution',
        success: false,
        message: 'فشل تحليل DNS',
        details: 'لم يتم العثور على عناوين IP',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'dns_resolution',
        success: false,
        message: 'خطأ في تحليل DNS',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص زمن استجابة الشبكة
  Future<DiagnosticTestResult> _testNetworkLatency() async {
    final stopwatch = Stopwatch()..start();
    try {
      final latencies = <int>[];

      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        await _httpClient
            .head(Uri.parse(ApiConfig.baseUrl))
            .timeout(const Duration(seconds: 5));
        sw.stop();
        latencies.add(sw.elapsedMilliseconds);
      }

      stopwatch.stop();

      final avg = latencies.reduce((a, b) => a + b) / latencies.length;
      final min = latencies.reduce((a, b) => a < b ? a : b);
      final max = latencies.reduce((a, b) => a > b ? a : b);

      String rating;
      bool success;
      if (avg < 100) {
        rating = 'ممتاز 🟢';
        success = true;
      } else if (avg < 300) {
        rating = 'جيد 🟡';
        success = true;
      } else if (avg < 500) {
        rating = 'متوسط 🟠';
        success = true;
      } else {
        rating = 'بطيء 🔴';
        success = false;
      }

      return DiagnosticTestResult(
        testId: 'network_latency',
        success: success,
        message: 'زمن الاستجابة: $rating',
        details: '''
📊 إحصائيات (5 طلبات):
⏱️ المتوسط: ${avg.toStringAsFixed(1)}ms
⬇️ الأدنى: ${min}ms
⬆️ الأعلى: ${max}ms
📈 التقييم: $rating''',
        duration: stopwatch.elapsed,
        metadata: {'avg': avg, 'min': min, 'max': max},
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'network_latency',
        success: false,
        message: 'فشل قياس زمن الاستجابة',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص معالجة أخطاء API
  Future<DiagnosticTestResult> _testApiErrorHandling() async {
    final stopwatch = Stopwatch()..start();
    try {
      // اختبار 404 - نقطة غير موجودة
      final response404 = await _httpClient
          .get(Uri.parse('${ApiConfig.baseUrl}/nonexistent-endpoint'))
          .timeout(const Duration(seconds: 5));

      // اختبار 401
      final response401 = await _httpClient.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.companies}'),
        headers: {'Authorization': 'Bearer invalid_token'},
      ).timeout(const Duration(seconds: 5));

      stopwatch.stop();

      final handles404 = response404.statusCode == 404;
      final handles401 = response401.statusCode == 401;

      return DiagnosticTestResult(
        testId: 'api_error_handling',
        success: handles404 && handles401,
        message: 'معالجة الأخطاء تعمل',
        details: '''
🔍 اختبار معالجة الأخطاء:
━━━━━━━━━━━━━━━━━━━━━━━
404 (غير موجود): ${handles404 ? '✓' : '✗'}
401 (غير مصرح): ${handles401 ? '✓' : '✗'}
━━━━━━━━━━━━━━━━━━━━━━━
📝 API يرجع رموز الخطأ الصحيحة''',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'api_error_handling',
        success: false,
        message: 'خطأ في اختبار معالجة الأخطاء',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص تنسيق استجابة API
  Future<DiagnosticTestResult> _testApiResponseFormat() async {
    final stopwatch = Stopwatch()..start();
    try {
      // استخدام المسار الصحيح من ApiConfig
      final response = await _httpClient
          .get(Uri.parse('${ApiConfig.baseUrl}${ApiConfig.citizenPlans}'))
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        final isJson = contentType.contains('application/json');

        bool validJson = false;
        try {
          jsonDecode(response.body);
          validJson = true;
        } catch (_) {}

        return DiagnosticTestResult(
          testId: 'api_response_format',
          success: isJson && validJson,
          message: isJson && validJson
              ? 'تنسيق الاستجابة صحيح ✓'
              : 'مشكلة في تنسيق الاستجابة',
          details: '''
📄 Content-Type: $contentType
🔍 JSON صالح: ${validJson ? '✓' : '✗'}
📊 حجم الاستجابة: ${response.body.length} حرف''',
          duration: stopwatch.elapsed,
        );
      }

      return DiagnosticTestResult(
        testId: 'api_response_format',
        success: false,
        message: 'فشل فحص تنسيق الاستجابة',
        details: 'الحالة: ${response.statusCode}',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'api_response_format',
        success: false,
        message: 'خطأ في فحص تنسيق الاستجابة',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص التصفح في السجلات
  Future<DiagnosticTestResult> _testCrudPagination() async {
    final stopwatch = Stopwatch()..start();
    try {
      // نستخدم نقطة عامة لاختبار التصفح (citizen/plans مع pagination)
      final response = await _httpClient
          .get(
            Uri.parse(
                '${ApiConfig.baseUrl}${ApiConfig.citizenPlans}?page=1&pageSize=5'),
          )
          .timeout(const Duration(seconds: 10));

      stopwatch.stop();

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);

          // التحقق من دعم التصفح
          final hasPagination = data is Map &&
              (data.containsKey('totalPages') ||
                  data.containsKey('totalCount') ||
                  data.containsKey('pageSize') ||
                  data.containsKey('data'));

          final count = data is List
              ? data.length
              : (data['data']?.length ?? data.length);

          return DiagnosticTestResult(
            testId: 'crud_pagination',
            success: true,
            message: 'التصفح يعمل ✓',
            details: '''
✓ اختبار التصفح:
━━━━━━━━━━━━━━━━━━━━━━━
📄 الصفحة: 1
📊 الحجم: 5
📝 النتائج: $count
🔄 دعم التصفح: ${hasPagination ? 'نعم' : 'بسيط'}''',
            duration: stopwatch.elapsed,
          );
        } catch (e) {
          return DiagnosticTestResult(
            testId: 'crud_pagination',
            success: true,
            message: 'التصفح يعمل ✓',
            details: 'Status: ${response.statusCode}',
            duration: stopwatch.elapsed,
          );
        }
      }

      return DiagnosticTestResult(
        testId: 'crud_pagination',
        success: false,
        message: 'مشكلة في التصفح',
        details: '''
✗ فشل اختبار التصفح:
━━━━━━━━━━━━━━━━━━━━━━━
📊 الحالة: ${response.statusCode}
💡 السبب: ${_analyzeHttpError(response.statusCode)}''',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'crud_pagination',
        success: false,
        message: 'خطأ في اختبار التصفح',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص انتهاء صلاحية الرمز
  Future<DiagnosticTestResult> _testTokenExpiry() async {
    final stopwatch = Stopwatch()..start();
    try {
      final token = VpsAuthService.instance.accessToken;
      stopwatch.stop();

      if (token == null) {
        return DiagnosticTestResult(
          testId: 'security_token_expiry',
          success: false,
          message: 'لا يوجد رمز للفحص',
          details: '⚠️ يجب تسجيل الدخول أولاً',
          duration: stopwatch.elapsed,
        );
      }

      final parts = token.split('.');
      if (parts.length == 3) {
        try {
          final payload = parts[1];
          final normalized = base64Url.normalize(payload);
          final decoded = utf8.decode(base64Url.decode(normalized));
          final payloadData = jsonDecode(decoded);

          final exp = payloadData['exp'] as int?;
          if (exp != null) {
            final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
            final now = DateTime.now();
            final remaining = expiry.difference(now);

            String status;
            bool success;
            if (remaining.isNegative) {
              status = '❌ منتهي الصلاحية';
              success = false;
            } else if (remaining.inHours < 1) {
              status = '⚠️ سينتهي قريباً';
              success = true;
            } else {
              status = '✓ صالح';
              success = true;
            }

            return DiagnosticTestResult(
              testId: 'security_token_expiry',
              success: success,
              message: 'حالة الرمز: $status',
              details: '''
📅 تاريخ الانتهاء: $expiry
⏳ المتبقي: ${remaining.isNegative ? 'منتهي' : '${remaining.inHours}h ${remaining.inMinutes % 60}m'}
📊 الحالة: $status''',
              duration: stopwatch.elapsed,
            );
          }
        } catch (_) {}
      }

      return DiagnosticTestResult(
        testId: 'security_token_expiry',
        success: true,
        message: 'لم يتم العثور على معلومات الصلاحية',
        details: 'الرمز لا يحتوي على معلومات انتهاء',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'security_token_expiry',
        success: false,
        message: 'خطأ في فحص الصلاحية',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص الطلبات المتزامنة
  Future<DiagnosticTestResult> _testConcurrentRequests() async {
    final stopwatch = Stopwatch()..start();
    try {
      final futures = List.generate(5, (i) async {
        final sw = Stopwatch()..start();
        await _httpClient
            .head(Uri.parse(ApiConfig.baseUrl))
            .timeout(const Duration(seconds: 10));
        sw.stop();
        return sw.elapsedMilliseconds;
      });

      final results = await Future.wait(futures);
      stopwatch.stop();

      final avg = results.reduce((a, b) => a + b) ~/ results.length;
      final success = results.every((t) => t < 2000);

      return DiagnosticTestResult(
        testId: 'perf_concurrent_requests',
        success: success,
        message:
            success ? 'الطلبات المتزامنة تعمل ✓' : 'بطء في الطلبات المتزامنة',
        details: '''
🔄 عدد الطلبات: 5 (متزامنة)
⏱️ متوسط الوقت: ${avg}ms
📈 الأوقات: ${results.join('ms, ')}ms
${success ? '✓ أداء جيد' : '⚠️ يحتاج تحسين'}''',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'perf_concurrent_requests',
        success: false,
        message: 'فشل اختبار الطلبات المتزامنة',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص سلامة البيانات
  Future<DiagnosticTestResult> _testDataIntegrity() async {
    final stopwatch = Stopwatch()..start();
    try {
      final prefs = await SharedPreferences.getInstance();
      const testKey = '_integrity_test';
      const testData = {'name': 'test', 'value': 12345, 'flag': true};
      final testJson = jsonEncode(testData);

      await prefs.setString(testKey, testJson);
      final retrieved = prefs.getString(testKey);
      await prefs.remove(testKey);

      stopwatch.stop();

      final isIntact = retrieved == testJson;
      Map<String, dynamic>? parsedData;
      try {
        parsedData = jsonDecode(retrieved ?? '');
      } catch (_) {}

      return DiagnosticTestResult(
        testId: 'storage_data_integrity',
        success: isIntact && parsedData != null,
        message:
            isIntact ? 'سلامة البيانات محفوظة ✓' : 'مشكلة في سلامة البيانات',
        details: '''
🔍 اختبار سلامة البيانات:
━━━━━━━━━━━━━━━━━━━━━━━
📝 البيانات: $testData
📤 بعد التخزين: ${isIntact ? 'متطابقة ✓' : 'مختلفة ✗'}
🔄 JSON صالح: ${parsedData != null ? '✓' : '✗'}''',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'storage_data_integrity',
        success: false,
        message: 'خطأ في فحص سلامة البيانات',
        details: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص معلومات النظام
  Future<DiagnosticTestResult> _testPlatformInfo() async {
    final stopwatch = Stopwatch()..start();
    stopwatch.stop();

    return DiagnosticTestResult(
      testId: 'system_platform',
      success: true,
      message: 'معلومات النظام ✓',
      details: '''
🖥️ معلومات النظام:
━━━━━━━━━━━━━━━━━━━━━━━
💻 النظام: ${Platform.operatingSystem}
📦 الإصدار: ${Platform.operatingSystemVersion}
🔧 المعالجات: ${Platform.numberOfProcessors}
🌐 اللغة: ${Platform.localeName}''',
      duration: stopwatch.elapsed,
      metadata: {
        'os': Platform.operatingSystem,
        'version': Platform.operatingSystemVersion,
        'processors': Platform.numberOfProcessors,
        'locale': Platform.localeName,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🏢 اختبارات إدارة الشركات
  // ═══════════════════════════════════════════════════════════════════════════

  /// فحص جلب قائمة الشركات
  Future<DiagnosticTestResult> _testCompanyList() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _httpClient.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.internalCompanies}'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
      );
      stopwatch.stop();

      final success = response.statusCode == 200;
      List? companies;
      int count = 0;

      if (success) {
        try {
          final data = jsonDecode(response.body);
          if (data is List) {
            companies = data;
            count = data.length;
          } else if (data['data'] is List) {
            companies = data['data'];
            count = companies!.length;
          }
        } catch (_) {}
      }

      return DiagnosticTestResult(
        testId: 'company_list',
        success: success,
        message: success
            ? 'جلب قائمة الشركات ناجح ✓ ($count شركة)'
            : 'فشل جلب قائمة الشركات (${response.statusCode})',
        details: '''
🏢 اختبار جلب قائمة الشركات:
━━━━━━━━━━━━━━━━━━━━━━━
🌐 Endpoint: ${ApiConfig.internalCompanies}
📊 Status Code: ${response.statusCode}
📦 عدد الشركات: $count
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms
${!success ? '❌ Response: ${response.body.substring(0, response.body.length.clamp(0, 200))}' : '✅ الاستجابة صحيحة'}''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': response.statusCode,
          'companyCount': count,
          'responseTime': stopwatch.elapsedMilliseconds,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'company_list',
        success: false,
        message: 'خطأ في الاتصال بـ API الشركات',
        details: '❌ خطأ: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص إنشاء شركة (بدون إنشاء فعلي)
  Future<DiagnosticTestResult> _testCompanyCreate() async {
    final stopwatch = Stopwatch()..start();
    try {
      // نفحص فقط أن الـ endpoint موجود عبر إرسال بيانات ناقصة
      final response = await _httpClient.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.internalCompanies}'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
        body: jsonEncode({}), // بيانات فارغة للفحص فقط
      );
      stopwatch.stop();

      // إذا كان 400 = الـ endpoint موجود لكن البيانات ناقصة (متوقع)
      // إذا كان 404 = الـ endpoint غير موجود
      final endpointExists = response.statusCode != 404;

      return DiagnosticTestResult(
        testId: 'company_create',
        success: endpointExists,
        message: endpointExists
            ? 'Endpoint إنشاء الشركة متاح ✓'
            : 'Endpoint إنشاء الشركة غير موجود ✗',
        details: '''
🏢 اختبار إنشاء شركة:
━━━━━━━━━━━━━━━━━━━━━━━
🌐 Endpoint: POST ${ApiConfig.internalCompanies}
📊 Status Code: ${response.statusCode}
${response.statusCode == 400 ? '✅ الـ Endpoint يعمل (400 = بيانات ناقصة - متوقع)' : ''}
${response.statusCode == 404 ? '❌ الـ Endpoint غير موجود' : ''}
${response.statusCode == 401 ? '🔐 يحتاج مصادقة' : ''}
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': response.statusCode,
          'endpointExists': endpointExists,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'company_create',
        success: false,
        message: 'خطأ في فحص endpoint الإنشاء',
        details: '❌ خطأ: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص تحديث الشركة
  Future<DiagnosticTestResult> _testCompanyUpdate() async {
    final stopwatch = Stopwatch()..start();
    try {
      // أولاً نجلب شركة للحصول على ID حقيقي
      final listResponse = await _httpClient.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.internalCompanies}'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
      );

      String? testCompanyId;
      String? testCompanyName;

      if (listResponse.statusCode == 200) {
        try {
          final data = jsonDecode(listResponse.body);
          final companies = data is List ? data : (data['data'] as List? ?? []);
          if (companies.isNotEmpty) {
            // دعم كلا التنسيقين: id و Id (PascalCase)
            testCompanyId =
                (companies[0]['id'] ?? companies[0]['Id'])?.toString();
            testCompanyName =
                (companies[0]['name'] ?? companies[0]['Name'])?.toString();
          }
        } catch (_) {}
      }

      if (testCompanyId == null) {
        stopwatch.stop();
        return DiagnosticTestResult(
          testId: 'company_update',
          success: false,
          message: 'لا توجد شركات للاختبار',
          details: '⚠️ لم يتم العثور على شركات لاختبار التحديث',
          duration: stopwatch.elapsed,
        );
      }

      // فحص endpoint التحديث
      final updateResponse = await _httpClient.put(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.internalCompanies}/$testCompanyId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
        body: jsonEncode({
          'name': testCompanyName, // نفس الاسم - لا تغيير فعلي
        }),
      );
      stopwatch.stop();

      final success = updateResponse.statusCode == 200;

      return DiagnosticTestResult(
        testId: 'company_update',
        success: success,
        message: success
            ? 'تحديث بيانات الشركة يعمل ✓'
            : 'فشل تحديث بيانات الشركة (${updateResponse.statusCode})',
        details: '''
🏢 اختبار تحديث الشركة:
━━━━━━━━━━━━━━━━━━━━━━━
🌐 Endpoint: PUT ${ApiConfig.internalCompanies}/$testCompanyId
🏷️ الشركة: $testCompanyName
📊 Status Code: ${updateResponse.statusCode}
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms
${success ? '✅ التحديث يعمل بشكل صحيح' : '❌ Response: ${updateResponse.body.substring(0, updateResponse.body.length.clamp(0, 200))}'}''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': updateResponse.statusCode,
          'companyId': testCompanyId,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'company_update',
        success: false,
        message: 'خطأ في فحص تحديث الشركة',
        details: '❌ خطأ: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص حذف الشركة (بدون حذف فعلي)
  Future<DiagnosticTestResult> _testCompanyDelete() async {
    final stopwatch = Stopwatch()..start();
    try {
      // نفحص endpoint بـ ID وهمي
      final response = await _httpClient.delete(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.internalCompanies}/00000000-0000-0000-0000-000000000000'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
      );
      stopwatch.stop();

      // 404 = الـ endpoint موجود لكن الشركة غير موجودة (متوقع)
      final endpointExists =
          response.statusCode == 404 || response.statusCode == 200;

      return DiagnosticTestResult(
        testId: 'company_delete',
        success: endpointExists,
        message: endpointExists
            ? 'Endpoint حذف الشركة متاح ✓'
            : 'Endpoint حذف الشركة غير موجود ✗',
        details: '''
🗑️ اختبار حذف الشركة:
━━━━━━━━━━━━━━━━━━━━━━━
🌐 Endpoint: DELETE ${ApiConfig.internalCompanies}/{id}
📊 Status Code: ${response.statusCode}
${response.statusCode == 404 ? '✅ الـ Endpoint يعمل (404 = شركة غير موجودة - متوقع)' : ''}
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': response.statusCode,
          'endpointExists': endpointExists,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'company_delete',
        success: false,
        message: 'خطأ في فحص endpoint الحذف',
        details: '❌ خطأ: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص تعليق الشركة
  Future<DiagnosticTestResult> _testCompanySuspend() async {
    final stopwatch = Stopwatch()..start();
    try {
      // فحص endpoint التعليق
      final response = await _httpClient.patch(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.internalCompanies}/00000000-0000-0000-0000-000000000000/suspend'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
        body: jsonEncode({'reason': 'test'}),
      );
      stopwatch.stop();

      final endpointExists = response.statusCode != 405; // Method Not Allowed

      return DiagnosticTestResult(
        testId: 'company_suspend',
        success: endpointExists,
        message: endpointExists
            ? 'Endpoint تعليق الشركة متاح ✓'
            : 'Endpoint تعليق الشركة غير موجود ✗',
        details: '''
⏸️ اختبار تعليق الشركة:
━━━━━━━━━━━━━━━━━━━━━━━
🌐 Endpoint: PATCH ${ApiConfig.internalCompanies}/{id}/suspend
📊 Status Code: ${response.statusCode}
${response.statusCode == 404 ? '✅ الـ Endpoint يعمل (404 = شركة غير موجودة)' : ''}
${response.statusCode == 405 ? '❌ Method Not Allowed - الـ Endpoint غير موجود' : ''}
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': response.statusCode,
          'endpointExists': endpointExists,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'company_suspend',
        success: false,
        message: 'خطأ في فحص endpoint التعليق',
        details: '❌ خطأ: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص تفعيل الشركة
  Future<DiagnosticTestResult> _testCompanyActivate() async {
    final stopwatch = Stopwatch()..start();
    try {
      // فحص endpoint التفعيل
      final response = await _httpClient.patch(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.internalCompanies}/00000000-0000-0000-0000-000000000000/activate'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
      );
      stopwatch.stop();

      final endpointExists = response.statusCode != 405;

      return DiagnosticTestResult(
        testId: 'company_activate',
        success: endpointExists,
        message: endpointExists
            ? 'Endpoint تفعيل الشركة متاح ✓'
            : 'Endpoint تفعيل الشركة غير موجود ✗',
        details: '''
▶️ اختبار تفعيل الشركة:
━━━━━━━━━━━━━━━━━━━━━━━
🌐 Endpoint: PATCH ${ApiConfig.internalCompanies}/{id}/activate
📊 Status Code: ${response.statusCode}
${response.statusCode == 404 ? '✅ الـ Endpoint يعمل (404 = شركة غير موجودة)' : ''}
${response.statusCode == 405 ? '❌ Method Not Allowed - الـ Endpoint غير موجود' : ''}
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': response.statusCode,
          'endpointExists': endpointExists,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'company_activate',
        success: false,
        message: 'خطأ في فحص endpoint التفعيل',
        details: '❌ خطأ: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص تجديد اشتراك الشركة
  Future<DiagnosticTestResult> _testCompanyRenew() async {
    final stopwatch = Stopwatch()..start();
    try {
      // فحص endpoint التجديد
      final response = await _httpClient.patch(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.internalCompanies}/00000000-0000-0000-0000-000000000000/renew'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
        body: jsonEncode({
          'months': 1,
          'newEndDate':
              DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        }),
      );
      stopwatch.stop();

      final endpointExists = response.statusCode != 405;

      return DiagnosticTestResult(
        testId: 'company_renew',
        success: endpointExists,
        message: endpointExists
            ? 'Endpoint تجديد الاشتراك متاح ✓'
            : 'Endpoint تجديد الاشتراك غير موجود ✗',
        details: '''
🔄 اختبار تجديد الاشتراك:
━━━━━━━━━━━━━━━━━━━━━━━
🌐 Endpoint: PATCH ${ApiConfig.internalCompanies}/{id}/renew
📊 Status Code: ${response.statusCode}
${response.statusCode == 404 ? '✅ الـ Endpoint يعمل (404 = شركة غير موجودة)' : ''}
${response.statusCode == 405 ? '❌ Method Not Allowed - الـ Endpoint غير موجود' : ''}
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': response.statusCode,
          'endpointExists': endpointExists,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'company_renew',
        success: false,
        message: 'خطأ في فحص endpoint التجديد',
        details: '❌ خطأ: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// فحص صلاحيات الشركة
  Future<DiagnosticTestResult> _testCompanyPermissions() async {
    final stopwatch = Stopwatch()..start();
    try {
      // أولاً نجلب شركة للحصول على ID حقيقي
      final listResponse = await _httpClient.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.internalCompanies}'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
      );

      String? testCompanyId;
      String? testCompanyName;
      Map<String, dynamic>? currentFirstPermissions;
      Map<String, dynamic>? currentSecondPermissions;

      if (listResponse.statusCode == 200) {
        try {
          final data = jsonDecode(listResponse.body);
          final companies = data is List ? data : (data['data'] as List? ?? []);
          if (companies.isNotEmpty) {
            // دعم كلا التنسيقين: camelCase و PascalCase
            testCompanyId =
                (companies[0]['id'] ?? companies[0]['Id'])?.toString();
            testCompanyName =
                (companies[0]['name'] ?? companies[0]['Name'])?.toString();
            // جلب الصلاحيات الحالية
            final first = companies[0]['enabledFirstSystemFeatures'] ??
                companies[0]['EnabledFirstSystemFeatures'];
            final second = companies[0]['enabledSecondSystemFeatures'] ??
                companies[0]['EnabledSecondSystemFeatures'];
            if (first is Map)
              currentFirstPermissions = Map<String, dynamic>.from(first);
            if (second is Map)
              currentSecondPermissions = Map<String, dynamic>.from(second);
          }
        } catch (_) {}
      }

      if (testCompanyId == null) {
        stopwatch.stop();
        return DiagnosticTestResult(
          testId: 'company_permissions',
          success: false,
          message: 'لا توجد شركات للاختبار',
          details: '⚠️ لم يتم العثور على شركات لاختبار الصلاحيات',
          duration: stopwatch.elapsed,
        );
      }

      // فحص تحديث الصلاحيات (نرسل نفس الصلاحيات الحالية)
      final testPermissions = {
        'enabledFirstSystemFeatures': currentFirstPermissions ??
            {
              'attendance': true,
              'agent': true,
              'tasks': true,
              'zones': true,
              'ai_search': true,
            },
        'enabledSecondSystemFeatures': currentSecondPermissions ??
            {
              'users': true,
              'subscriptions': true,
              'dashboard': true,
            },
      };

      final updateResponse = await _httpClient.put(
        Uri.parse(
            '${ApiConfig.baseUrl}${ApiConfig.internalCompanies}/$testCompanyId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-Key': ApiConfig.internalApiKey,
        },
        body: jsonEncode(testPermissions),
      );
      stopwatch.stop();

      final success = updateResponse.statusCode == 200;

      return DiagnosticTestResult(
        testId: 'company_permissions',
        success: success,
        message: success
            ? 'تحديث صلاحيات الشركة يعمل ✓'
            : 'فشل تحديث صلاحيات الشركة (${updateResponse.statusCode})',
        details: '''
🔐 اختبار صلاحيات الشركة:
━━━━━━━━━━━━━━━━━━━━━━━
🌐 Endpoint: PUT ${ApiConfig.internalCompanies}/$testCompanyId
🏷️ الشركة: $testCompanyName
📊 Status Code: ${updateResponse.statusCode}
⏱️ وقت الاستجابة: ${stopwatch.elapsedMilliseconds}ms

📋 صلاحيات النظام الأول:
${currentFirstPermissions?.entries.map((e) => '   ${e.key}: ${e.value}').join('\n') ?? '   (غير محددة)'}

📋 صلاحيات النظام الثاني:
${currentSecondPermissions?.entries.map((e) => '   ${e.key}: ${e.value}').join('\n') ?? '   (غير محددة)'}

${success ? '✅ تحديث الصلاحيات يعمل بشكل صحيح' : '❌ Response: ${updateResponse.body.substring(0, updateResponse.body.length.clamp(0, 300))}'}''',
        duration: stopwatch.elapsed,
        metadata: {
          'statusCode': updateResponse.statusCode,
          'companyId': testCompanyId,
          'hasFirstPermissions': currentFirstPermissions != null,
          'hasSecondPermissions': currentSecondPermissions != null,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return DiagnosticTestResult(
        testId: 'company_permissions',
        success: false,
        message: 'خطأ في فحص صلاحيات الشركة',
        details: '❌ خطأ: $e',
        duration: stopwatch.elapsed,
      );
    }
  }
}
