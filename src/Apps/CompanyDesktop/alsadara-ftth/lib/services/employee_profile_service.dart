/// 👤 خدمة ملف الموظف الشامل
/// تجمع بيانات الموظف من جميع الأنظمة المرتبطة
library;

import 'package:flutter/material.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';

class EmployeeProfileService {
  static EmployeeProfileService? _instance;
  static EmployeeProfileService get instance =>
      _instance ??= EmployeeProfileService._internal();
  EmployeeProfileService._internal();

  final ApiClient _api = ApiClient.instance;

  // ═══════════════════════════════════════
  // بيانات الموظف الأساسية
  // ═══════════════════════════════════════

  /// جلب بيانات موظف واحد
  Future<Map<String, dynamic>?> getEmployee(
      String companyId, String empId) async {
    try {
      final response = await _api.get(
        ApiConfig.internalEmployeeById(companyId, empId),
        (json) => json,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        if (response.data is Map)
          return Map<String, dynamic>.from(response.data);
        return null;
      }
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات الموظف');
      return null;
    }
  }

  /// تحديث بيانات HR للموظف
  Future<bool> updateEmployee(
      String companyId, String empId, Map<String, dynamic> data) async {
    try {
      final response = await _api.put(
        ApiConfig.internalEmployeeById(companyId, empId),
        data,
        (json) => json,
        useInternalKey: true,
      );
      return response.isSuccess;
    } catch (e) {
      debugPrint('❌ خطأ في تحديث بيانات الموظف');
      return false;
    }
  }

  /// تغيير كلمة مرور الموظف عبر endpoint مخصص
  Future<bool> changePassword(
      String companyId, String empId, String newPassword) async {
    try {
      final response = await _api.patch(
        ApiConfig.internalEmployeePassword(companyId, empId),
        {'NewPassword': newPassword},
        (json) => json,
        useInternalKey: true,
      );
      return response.isSuccess;
    } catch (e) {
      debugPrint('❌ خطأ في تغيير كلمة المرور');
      return false;
    }
  }

  // ═══════════════════════════════════════
  // سجل الحضور
  // ═══════════════════════════════════════

  /// جلب سجل حضور الموظف الشهري
  Future<List<Map<String, dynamic>>> getMonthlyAttendance(
      String userId, int month, int year) async {
    try {
      final response = await _api.get(
        '/attendance/$userId/monthly?month=$month&year=$year',
        (json) => json,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        if (response.data is List) {
          return List<Map<String, dynamic>>.from(
              response.data.map((e) => Map<String, dynamic>.from(e)));
        }
        final data = response.data;
        if (data is Map && data.containsKey('records')) {
          return List<Map<String, dynamic>>.from(
              data['records'].map((e) => Map<String, dynamic>.from(e)));
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب الحضور');
      return [];
    }
  }

  // ═══════════════════════════════════════
  // الرواتب
  // ═══════════════════════════════════════

  /// جلب سجل رواتب الموظف
  Future<List<Map<String, dynamic>>> getSalaries(String userId) async {
    try {
      final response = await _api.get(
        '/accounting/salaries?userId=$userId',
        (json) => json,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        if (response.data is List) {
          return List<Map<String, dynamic>>.from(
              response.data.map((e) => Map<String, dynamic>.from(e)));
        }
        final data = response.data;
        if (data is Map) {
          final list = data['data'] ?? data['salaries'] ?? data['items'] ?? [];
          return List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e)));
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب الرواتب');
      return [];
    }
  }

  // ═══════════════════════════════════════
  // المهام
  // ═══════════════════════════════════════

  /// جلب مهام الموظف
  Future<List<Map<String, dynamic>>> getEmployeeTasks(String userId) async {
    try {
      final response = await _api.get(
        '/servicerequests?assignedTo=$userId',
        (json) => json,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        if (response.data is List) {
          return List<Map<String, dynamic>>.from(
              response.data.map((e) => Map<String, dynamic>.from(e)));
        }
        final data = response.data;
        if (data is Map) {
          final list = data['data'] ?? data['items'] ?? data['requests'] ?? [];
          return List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e)));
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب المهام');
      return [];
    }
  }

  // ═══════════════════════════════════════
  // المعاملات المالية (فنيين)
  // ═══════════════════════════════════════

  /// جلب معاملات الفني المالية
  Future<List<Map<String, dynamic>>> getTechnicianTransactions(
      String userId) async {
    try {
      final response = await _api.get(
        '/technician-transactions/by-technician/$userId',
        (json) => json,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        if (response.data is List) {
          return List<Map<String, dynamic>>.from(
              response.data.map((e) => Map<String, dynamic>.from(e)));
        }
        final data = response.data;
        if (data is Map) {
          final list =
              data['data'] ?? data['transactions'] ?? data['items'] ?? [];
          return List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e)));
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب معاملات الفني');
      return [];
    }
  }

  // ═══════════════════════════════════════
  // تقييم الأداء
  // ═══════════════════════════════════════

  /// جلب تقييمات مهام الموظف
  Future<List<Map<String, dynamic>>> getTaskAudits(String userId) async {
    try {
      final response = await _api.get(
        '/taskaudits?userId=$userId',
        (json) => json,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        if (response.data is List) {
          return List<Map<String, dynamic>>.from(
              response.data.map((e) => Map<String, dynamic>.from(e)));
        }
        final data = response.data;
        if (data is Map) {
          final list = data['data'] ?? data['audits'] ?? data['items'] ?? [];
          return List<Map<String, dynamic>>.from(
              list.map((e) => Map<String, dynamic>.from(e)));
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ خطأ في جلب التقييمات');
      return [];
    }
  }

  // ═══════════════════════════════════════
  // FTTH
  // ═══════════════════════════════════════

  /// جلب ملخص حساب المشغل FTTH
  Future<Map<String, dynamic>?> getFtthOperatorSummary(String userId) async {
    try {
      final response = await _api.get(
        '/ftth-accounting/operator-summary/$userId',
        (json) => json,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        if (response.data is Map) {
          return Map<String, dynamic>.from(response.data);
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات FTTH');
      return null;
    }
  }

  // ═══════════════════════════════════════
  // الصلاحيات V2
  // ═══════════════════════════════════════

  /// جلب صلاحيات الموظف V2
  Future<Map<String, dynamic>?> getEmployeePermissionsV2(
      String companyId, String empId) async {
    try {
      final response = await _api.get(
        ApiConfig.internalEmployeePermissionsV2(companyId, empId),
        (json) => json,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        if (response.data is Map) {
          return Map<String, dynamic>.from(response.data);
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب الصلاحيات');
      return null;
    }
  }

  /// تحديث صلاحيات الموظف V2
  Future<bool> updateEmployeePermissionsV2(
      String companyId, String empId, Map<String, dynamic> permissions) async {
    try {
      final response = await _api.put(
        ApiConfig.internalEmployeePermissionsV2(companyId, empId),
        permissions,
        (json) => json,
        useInternalKey: true,
      );
      return response.isSuccess;
    } catch (e) {
      debugPrint('❌ خطأ في تحديث الصلاحيات');
      return false;
    }
  }
}
