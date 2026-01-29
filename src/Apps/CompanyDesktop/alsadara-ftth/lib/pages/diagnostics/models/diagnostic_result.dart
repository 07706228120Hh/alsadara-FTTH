/// حالة نتيجة التشخيص
enum DiagnosticStatus {
  pending, // قيد الانتظار
  running, // قيد التنفيذ
  success, // نجح
  failed, // فشل
  warning, // تحذير
  skipped, // تم تخطيه
}

/// فئات التشخيص
class DiagnosticCategory {
  final String id;
  final String name;
  final String nameAr;
  final String icon;
  final String description;
  final List<String> testIds;

  const DiagnosticCategory({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.icon,
    required this.description,
    required this.testIds,
  });
}

/// الفئات المحددة مسبقاً
class DiagnosticCategories {
  static const connection = DiagnosticCategory(
    id: 'connection',
    name: 'Connection Tests',
    nameAr: 'اختبارات الاتصال',
    icon: '🔗',
    description: 'فحص الاتصال بالخوادم والخدمات',
    testIds: [
      'firebase_connection',
      'vps_connection',
      'api_health',
      'database_connection'
    ],
  );

  static const api = DiagnosticCategory(
    id: 'api',
    name: 'API Tests',
    nameAr: 'اختبارات API',
    icon: '🌐',
    description: 'فحص جميع نقاط API',
    testIds: [
      'api_companies',
      'api_citizens',
      'api_subscriptions',
      'api_payments'
    ],
  );

  static const crud = DiagnosticCategory(
    id: 'crud',
    name: 'CRUD Operations',
    nameAr: 'عمليات CRUD',
    icon: '📝',
    description: 'فحص عمليات الإضافة والتعديل والحذف والعرض',
    testIds: ['crud_create', 'crud_read', 'crud_update', 'crud_delete'],
  );

  static const security = DiagnosticCategory(
    id: 'security',
    name: 'Security Tests',
    nameAr: 'اختبارات الأمان',
    icon: '🔒',
    description: 'فحص الأمان والصلاحيات',
    testIds: ['auth_token', 'permissions', 'session_validation', 'encryption'],
  );

  static const navigation = DiagnosticCategory(
    id: 'navigation',
    name: 'Navigation Tests',
    nameAr: 'اختبارات التنقل',
    icon: '🧭',
    description: 'فحص التنقل بين الصفحات',
    testIds: ['nav_routes', 'nav_guards', 'nav_deep_links'],
  );

  static const ui = DiagnosticCategory(
    id: 'ui',
    name: 'UI Tests',
    nameAr: 'اختبارات الواجهة',
    icon: '🎨',
    description: 'فحص الألوان والأبعاد والمكونات',
    testIds: [
      'ui_colors',
      'ui_dimensions',
      'ui_responsive',
      'ui_accessibility'
    ],
  );

  static const performance = DiagnosticCategory(
    id: 'performance',
    name: 'Performance Tests',
    nameAr: 'اختبارات الأداء',
    icon: '⚡',
    description: 'فحص سرعة وأداء النظام',
    testIds: ['perf_api_response', 'perf_memory', 'perf_render'],
  );

  static const storage = DiagnosticCategory(
    id: 'storage',
    name: 'Storage Tests',
    nameAr: 'اختبارات التخزين',
    icon: '💾',
    description: 'فحص التخزين المحلي والآمن',
    testIds: ['storage_local', 'storage_secure', 'storage_cache'],
  );

  static const system = DiagnosticCategory(
    id: 'system',
    name: 'System Tests',
    nameAr: 'اختبارات النظام',
    icon: '🔧',
    description: 'فحص معلومات النظام والبيئة',
    testIds: ['system_platform', 'system_environment'],
  );

  static const companies = DiagnosticCategory(
    id: 'companies',
    name: 'Companies Management Tests',
    nameAr: 'اختبارات إدارة الشركات',
    icon: '🏢',
    description:
        'فحص شامل لجميع عمليات إدارة الشركات (إضافة، تعديل، حذف، تعطيل، تمديد، الصلاحيات)',
    testIds: [
      'company_list',
      'company_create',
      'company_update',
      'company_delete',
      'company_suspend',
      'company_activate',
      'company_renew',
      'company_permissions',
    ],
  );

  static List<DiagnosticCategory> get all => [
        connection,
        api,
        crud,
        security,
        navigation,
        ui,
        performance,
        storage,
        system,
        companies,
      ];
}

/// ملخص فئة التشخيص
class CategoryDiagnosticSummary {
  final DiagnosticCategory category;
  final int total;
  final int passed;
  final int failed;
  final int warnings;
  final Duration totalDuration;

  CategoryDiagnosticSummary({
    required this.category,
    required this.total,
    required this.passed,
    required this.failed,
    required this.warnings,
    required this.totalDuration,
  });

  double get successRate => total > 0 ? (passed / total) * 100 : 0;

  DiagnosticStatus get overallStatus {
    if (failed > 0) return DiagnosticStatus.failed;
    if (warnings > 0) return DiagnosticStatus.warning;
    if (passed == total) return DiagnosticStatus.success;
    return DiagnosticStatus.pending;
  }
}
