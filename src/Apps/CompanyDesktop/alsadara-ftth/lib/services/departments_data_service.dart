/// خدمة جلب الأقسام والمهام من API
/// تُستخدم في جميع الأماكن التي تحتاج قائمة الأقسام (نماذج الموظفين، المهام، إلخ)
library;

import 'package:flutter/foundation.dart';
import 'sadara_api_service.dart';
import 'vps_auth_service.dart';

class DepartmentsDataService {
  // Singleton
  static DepartmentsDataService? _instance;
  static DepartmentsDataService get instance =>
      _instance ??= DepartmentsDataService._internal();
  DepartmentsDataService._internal();

  // البيانات المخزنة مؤقتاً
  List<String> _departmentNames = [];
  List<Map<String, dynamic>> _departments = [];
  Map<String, List<String>> _departmentTasks = {};
  DateTime? _lastFetch;

  /// مدة صلاحية الكاش (5 دقائق)
  static const _cacheDuration = Duration(minutes: 5);

  /// أسماء الأقسام (للاستخدام في dropdowns)
  List<String> get departmentNames => List.unmodifiable(_departmentNames);

  /// بيانات الأقسام الكاملة
  List<Map<String, dynamic>> get departments => List.unmodifiable(_departments);

  /// مهام كل قسم
  Map<String, List<String>> get departmentTasks =>
      Map.unmodifiable(_departmentTasks);

  /// هل البيانات محملة؟
  bool get isLoaded => _departmentNames.isNotEmpty;

  /// القيم الافتراضية في حالة فشل الجلب
  static const List<String> _defaultDepartments = [
    'الصيانة',
    'الحسابات',
    'الفنيين',
    'الوكلاء',
    'الاتصالات',
    'اللحام',
  ];

  /// جلب الأقسام من API (مع كاش)
  Future<List<String>> fetchDepartments({bool forceRefresh = false}) async {
    // إرجاع الكاش إذا كان صالحاً
    if (!forceRefresh &&
        _departmentNames.isNotEmpty &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheDuration) {
      return _departmentNames;
    }

    final companyId = VpsAuthService.instance.currentCompanyId;
    if (companyId == null || companyId.isEmpty) {
      debugPrint('⚠️ DepartmentsDataService: لا يوجد companyId');
      return _departmentNames.isNotEmpty
          ? _departmentNames
          : _defaultDepartments;
    }

    try {
      final response = await SadaraApiService.instance
          .get('/companies/$companyId/departments');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as List;
        _departments =
            data.map((d) => Map<String, dynamic>.from(d as Map)).toList();
        _departmentNames = _departments
            .map((d) => d['nameAr']?.toString() ?? '')
            .where((n) => n.isNotEmpty)
            .toList();

        // استخراج مهام كل قسم
        _departmentTasks = {};
        for (final dept in _departments) {
          final deptName = dept['nameAr']?.toString() ?? '';
          final tasks = dept['tasks'] as List? ?? [];
          final taskNames = tasks
              .map((t) => (t as Map)['nameAr']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .toList();
          if (deptName.isNotEmpty && taskNames.isNotEmpty) {
            _departmentTasks[deptName] = taskNames;
          }
        }

        _lastFetch = DateTime.now();
        debugPrint(
            '✅ DepartmentsDataService: تم جلب ${_departmentNames.length} قسم');
      }
    } catch (e) {
      debugPrint('❌ DepartmentsDataService: خطأ في جلب الأقسام');
    }

    return _departmentNames.isNotEmpty ? _departmentNames : _defaultDepartments;
  }

  /// جلب مهام قسم معين
  Future<List<String>> fetchTasksForDepartment(String departmentName) async {
    if (_departmentTasks.isEmpty) {
      await fetchDepartments();
    }
    return _departmentTasks[departmentName] ?? [];
  }

  /// مسح الكاش (عند تغيير الأقسام)
  void clearCache() {
    _departmentNames = [];
    _departments = [];
    _departmentTasks = {};
    _lastFetch = null;
  }
}
