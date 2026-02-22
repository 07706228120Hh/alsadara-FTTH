import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'sadara_api_service.dart';

/// خدمة الحضور والانصراف عبر Sadara Platform API
class AttendanceApiService {
  static AttendanceApiService? _instance;
  static AttendanceApiService get instance =>
      _instance ??= AttendanceApiService._internal();
  AttendanceApiService._internal();

  final SadaraApiService _api = SadaraApiService.instance;

  /// توليد بصمة الجهاز (Layer 1) - تجمع معلومات فريدة للجهاز
  String _generateDeviceFingerprint() {
    try {
      final parts = <String>[];
      // اسم الجهاز
      parts.add(Platform.localHostname);
      // نظام التشغيل
      parts.add(Platform.operatingSystem);
      parts.add(Platform.operatingSystemVersion);
      // عدد المعالجات (ثابت لكل جهاز)
      parts.add(Platform.numberOfProcessors.toString());
      // اسم المستخدم في النظام
      parts.add(Platform.environment['USERNAME'] ??
          Platform.environment['USER'] ??
          '');
      // مسار المستخدم (فريد لكل جهاز/حساب)
      parts.add(Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '');

      final raw = parts.join('|');
      // تحويل لـ SHA-256 hash لحماية الخصوصية
      final hash = sha256.convert(utf8.encode(raw)).toString();
      return hash;
    } catch (e) {
      // fallback: استخدام اسم الجهاز فقط
      return sha256.convert(utf8.encode(Platform.localHostname)).toString();
    }
  }

  /// تسجيل حضور
  Future<Map<String, dynamic>> checkIn({
    required String userId,
    required String userName,
    String? companyId,
    String? centerName,
    double? latitude,
    double? longitude,
    String? securityCode,
  }) async {
    return await _api.post('/attendance/checkin', body: {
      'UserId': userId,
      'UserName': userName,
      'CompanyId': companyId,
      'CenterName': centerName,
      'Latitude': latitude,
      'Longitude': longitude,
      'SecurityCode': securityCode,
      'DeviceFingerprint': _generateDeviceFingerprint(),
    });
  }

  /// تسجيل انصراف
  Future<Map<String, dynamic>> checkOut({
    required String userId,
    double? latitude,
    double? longitude,
    String? notes,
  }) async {
    return await _api.post('/attendance/checkout', body: {
      'UserId': userId,
      'Latitude': latitude,
      'Longitude': longitude,
      'Notes': notes,
      'DeviceFingerprint': _generateDeviceFingerprint(),
    });
  }

  /// جلب سجل الحضور الشهري لموظف
  Future<Map<String, dynamic>> getMonthlyAttendance({
    required String userId,
    int? year,
    int? month,
  }) async {
    String url = '/attendance/$userId/monthly';
    List<String> params = [];
    if (year != null) params.add('year=$year');
    if (month != null) params.add('month=$month');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final response = await _api.get(url);
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    return response;
  }

  /// جلب حضور جميع الموظفين لتاريخ معين
  Future<List<Map<String, dynamic>>> getDailyAttendance({
    String? date,
    String? companyId,
  }) async {
    String url = '/attendance/daily';
    List<String> params = [];
    if (date != null) params.add('date=$date');
    if (companyId != null) params.add('companyId=$companyId');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final response = await _api.get(url);
    final data = response['data'];
    if (data is List) return List<Map<String, dynamic>>.from(data);
    return [];
  }

  /// جلب مراكز العمل
  Future<List<Map<String, dynamic>>> getCenters({String? companyId}) async {
    String url = '/attendance/centers';
    if (companyId != null) url += '?companyId=$companyId';

    final response = await _api.get(url);
    final data = response['data'];
    if (data is List) return List<Map<String, dynamic>>.from(data);
    return [];
  }

  /// إضافة مركز عمل
  Future<Map<String, dynamic>> addCenter({
    required String name,
    required double latitude,
    required double longitude,
    double? radiusMeters,
    String? companyId,
  }) async {
    return await _api.post('/attendance/centers', body: {
      'Name': name,
      'Latitude': latitude,
      'Longitude': longitude,
      'RadiusMeters': radiusMeters ?? 200,
      'CompanyId': companyId,
    });
  }

  // ============================================================
  //  جداول الدوام (Work Schedules)
  // ============================================================

  /// جلب جداول الدوام
  Future<List<Map<String, dynamic>>> getSchedules({String? companyId}) async {
    String url = '/attendance/schedules';
    if (companyId != null) url += '?companyId=$companyId';

    final response = await _api.get(url);
    final data = response is List ? response : (response['data'] ?? response);
    if (data is List) return List<Map<String, dynamic>>.from(data);
    return [];
  }

  /// إضافة جدول دوام
  Future<Map<String, dynamic>> addSchedule({
    required String name,
    required String workStartTime,
    required String workEndTime,
    String? companyId,
    String? centerName,
    int? dayOfWeek,
    int? lateGraceMinutes,
    int? earlyDepartureThresholdMinutes,
    bool? isDefault,
  }) async {
    return await _api.post('/attendance/schedules', body: {
      'Name': name,
      'WorkStartTime': workStartTime,
      'WorkEndTime': workEndTime,
      'CompanyId': companyId,
      'CenterName': centerName,
      'DayOfWeek': dayOfWeek,
      'LateGraceMinutes': lateGraceMinutes ?? 15,
      'EarlyDepartureThresholdMinutes': earlyDepartureThresholdMinutes ?? 15,
      'IsDefault': isDefault ?? false,
    });
  }

  /// تعديل جدول دوام
  Future<Map<String, dynamic>> updateSchedule({
    required int id,
    required String name,
    required String workStartTime,
    required String workEndTime,
    String? companyId,
    String? centerName,
    int? dayOfWeek,
    int? lateGraceMinutes,
    int? earlyDepartureThresholdMinutes,
    bool? isDefault,
  }) async {
    return await _api.put('/attendance/schedules/$id', body: {
      'Name': name,
      'WorkStartTime': workStartTime,
      'WorkEndTime': workEndTime,
      'CompanyId': companyId,
      'CenterName': centerName,
      'DayOfWeek': dayOfWeek,
      'LateGraceMinutes': lateGraceMinutes ?? 15,
      'EarlyDepartureThresholdMinutes': earlyDepartureThresholdMinutes ?? 15,
      'IsDefault': isDefault ?? false,
    });
  }

  /// حذف جدول دوام
  Future<Map<String, dynamic>> deleteSchedule(int id) async {
    return await _api.delete('/attendance/schedules/$id');
  }

  // ============================================================
  //  نظام الإجازات (Leave Management)
  // ============================================================

  /// تقديم طلب إجازة
  Future<Map<String, dynamic>> submitLeaveRequest({
    required String userId,
    required int leaveType,
    required String startDate,
    required String endDate,
    String? reason,
    String? attachmentUrl,
  }) async {
    return await _api.post('/leave/requests', body: {
      'UserId': userId,
      'LeaveType': leaveType,
      'StartDate': startDate,
      'EndDate': endDate,
      'Reason': reason,
      'AttachmentUrl': attachmentUrl,
    });
  }

  /// جلب طلبات الإجازة
  Future<Map<String, dynamic>> getLeaveRequests({
    String? userId,
    int? status,
    String? companyId,
    int? year,
    int? month,
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String>[];
    if (userId != null) params.add('userId=$userId');
    if (status != null) params.add('status=$status');
    if (companyId != null) params.add('companyId=$companyId');
    if (year != null) params.add('year=$year');
    if (month != null) params.add('month=$month');
    params.add('page=$page');
    params.add('pageSize=$pageSize');
    final url = '/leave/requests?${params.join('&')}';
    return await _api.get(url);
  }

  /// إلغاء طلب إجازة
  Future<Map<String, dynamic>> cancelLeaveRequest(int id) async {
    return await _api.post('/leave/requests/$id/cancel', body: {});
  }

  /// الموافقة على طلب إجازة
  Future<Map<String, dynamic>> approveLeaveRequest(int id,
      {String? notes}) async {
    return await _api.post('/leave/requests/$id/approve', body: {
      'Notes': notes,
    });
  }

  /// رفض طلب إجازة
  Future<Map<String, dynamic>> rejectLeaveRequest(int id,
      {String? notes}) async {
    return await _api.post('/leave/requests/$id/reject', body: {
      'Notes': notes,
    });
  }

  /// جلب رصيد إجازات موظف
  Future<Map<String, dynamic>> getLeaveBalances(String userId,
      {int? year}) async {
    String url = '/leave/balances/$userId';
    if (year != null) url += '?year=$year';
    return await _api.get(url);
  }

  /// تعيين رصيد إجازات
  Future<Map<String, dynamic>> setLeaveBalance({
    required String userId,
    required int year,
    required int leaveType,
    required int totalAllowance,
  }) async {
    return await _api.post('/leave/balances', body: {
      'UserId': userId,
      'Year': year,
      'LeaveType': leaveType,
      'TotalAllowance': totalAllowance,
    });
  }

  /// تعيين رصيد لجميع موظفي الشركة
  Future<Map<String, dynamic>> bulkSetLeaveBalances({
    required String companyId,
    required int leaveType,
    required int totalAllowance,
    int? year,
  }) async {
    return await _api.post('/leave/balances/bulk', body: {
      'CompanyId': companyId,
      'LeaveType': leaveType,
      'TotalAllowance': totalAllowance,
      'Year': year,
    });
  }

  /// ملخص إحصائيات الإجازات
  Future<Map<String, dynamic>> getLeaveSummary(
      {String? companyId, int? year}) async {
    final params = <String>[];
    if (companyId != null) params.add('companyId=$companyId');
    if (year != null) params.add('year=$year');
    final url = params.isEmpty
        ? '/leave/summary'
        : '/leave/summary?${params.join('&')}';
    return await _api.get(url);
  }

  // ==================== طلبات سحب الأموال - Withdrawal Requests ====================

  /// تقديم طلب سحب أموال
  Future<Map<String, dynamic>> submitWithdrawalRequest({
    required String userId,
    required double amount,
    String? reason,
    String? notes,
  }) async {
    return await _api.post('/withdrawalrequest/requests', body: {
      'UserId': userId,
      'Amount': amount,
      'Reason': reason,
      'Notes': notes,
    });
  }

  /// جلب طلبات سحب الأموال للموظف الحالي
  Future<Map<String, dynamic>> getMyWithdrawalRequests({
    int? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final params = <String>[];
    if (status != null) params.add('status=$status');
    params.add('page=$page');
    params.add('pageSize=$pageSize');
    final url = '/withdrawalrequest/my-requests?${params.join('&')}';
    return await _api.get(url);
  }

  /// جلب طلبات سحب الأموال (إدارة)
  Future<Map<String, dynamic>> getWithdrawalRequests({
    String? userId,
    int? status,
    String? companyId,
    int? year,
    int? month,
    int page = 1,
    int pageSize = 50,
  }) async {
    final params = <String>[];
    if (userId != null) params.add('userId=$userId');
    if (status != null) params.add('status=$status');
    if (companyId != null) params.add('companyId=$companyId');
    if (year != null) params.add('year=$year');
    if (month != null) params.add('month=$month');
    params.add('page=$page');
    params.add('pageSize=$pageSize');
    final url = '/withdrawalrequest/requests?${params.join('&')}';
    return await _api.get(url);
  }

  /// إلغاء طلب سحب أموال
  Future<Map<String, dynamic>> cancelWithdrawalRequest(int id) async {
    return await _api.post('/withdrawalrequest/requests/$id/cancel', body: {});
  }

  /// الموافقة على طلب سحب أموال
  Future<Map<String, dynamic>> approveWithdrawalRequest(int id,
      {String? notes}) async {
    return await _api.post('/withdrawalrequest/requests/$id/approve', body: {
      'Notes': notes,
    });
  }

  /// صرف طلب سحب أموال (سلفة على الراتب)
  Future<Map<String, dynamic>> payWithdrawalRequest(int id,
      {String? notes, bool overrideLimit = false}) async {
    return await _api.post('/withdrawalrequest/requests/$id/pay', body: {
      'Notes': notes,
      'OverrideLimit': overrideLimit,
    });
  }

  /// جلب الحد الأقصى للسحب المتاح للموظف بناءً على أيام الحضور
  Future<Map<String, dynamic>> getMaxWithdrawal(String userId,
      {int? month, int? year}) async {
    final params = <String>[];
    if (month != null) params.add('month=$month');
    if (year != null) params.add('year=$year');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';
    return await _api.get('/withdrawalrequest/max-withdrawal/$userId$query');
  }

  /// رفض طلب سحب أموال
  Future<Map<String, dynamic>> rejectWithdrawalRequest(int id,
      {String? notes}) async {
    return await _api.post('/withdrawalrequest/requests/$id/reject', body: {
      'Notes': notes,
    });
  }

  // ==================== الخصومات والمكافآت - Employee Adjustments ====================

  /// جلب موظفي الشركة (للقوائم المنسدلة)
  Future<Map<String, dynamic>> getCompanyEmployees(String companyId) async {
    return await _api.get('/companies/$companyId/employees?pageSize=200');
  }

  /// جلب الخصومات والمكافآت
  Future<Map<String, dynamic>> getEmployeeAdjustments({
    String? companyId,
    String? userId,
    int? month,
    int? year,
    int? type, // 0=Deduction, 1=Bonus, 2=Allowance
  }) async {
    final params = <String>[];
    if (companyId != null) params.add('companyId=$companyId');
    if (userId != null) params.add('userId=$userId');
    if (month != null) params.add('month=$month');
    if (year != null) params.add('year=$year');
    if (type != null) params.add('type=$type');
    final url = params.isEmpty
        ? '/accounting/employee-adjustments'
        : '/accounting/employee-adjustments?${params.join('&')}';
    return await _api.get(url);
  }

  /// إضافة خصم أو مكافأة يدوية
  Future<Map<String, dynamic>> createEmployeeAdjustment({
    required String userId,
    required String companyId,
    required int type, // 0=Deduction, 1=Bonus, 2=Allowance
    String? category,
    required double amount,
    required int month,
    required int year,
    String? description,
    String? notes,
    required String createdById,
    bool isRecurring = false,
  }) async {
    return await _api.post('/accounting/employee-adjustments', body: {
      'UserId': userId,
      'CompanyId': companyId,
      'Type': type,
      'Category': category ?? '',
      'Amount': amount,
      'Month': month,
      'Year': year,
      'Description': description ?? '',
      'Notes': notes,
      'CreatedById': createdById,
      'IsRecurring': isRecurring,
    });
  }

  /// تعديل خصم أو مكافأة
  Future<Map<String, dynamic>> updateEmployeeAdjustment(
    int id, {
    int? type,
    String? category,
    double? amount,
    String? description,
    String? notes,
    bool? isRecurring,
    bool? isActive,
  }) async {
    return await _api.put('/accounting/employee-adjustments/$id', body: {
      if (type != null) 'Type': type,
      if (category != null) 'Category': category,
      if (amount != null) 'Amount': amount,
      if (description != null) 'Description': description,
      if (notes != null) 'Notes': notes,
      if (isRecurring != null) 'IsRecurring': isRecurring,
      if (isActive != null) 'IsActive': isActive,
    });
  }

  /// حذف خصم أو مكافأة
  Future<Map<String, dynamic>> deleteEmployeeAdjustment(int id) async {
    return await _api.delete('/accounting/employee-adjustments/$id');
  }

  // ==================== الرواتب - Salaries ====================

  /// جلب رواتب شهر معين
  Future<Map<String, dynamic>> getSalaries({
    String? companyId,
    int? month,
    int? year,
    String? status,
  }) async {
    final params = <String>[];
    if (companyId != null) params.add('companyId=$companyId');
    if (month != null) params.add('month=$month');
    if (year != null) params.add('year=$year');
    if (status != null) params.add('status=$status');
    final url = params.isEmpty
        ? '/accounting/salaries'
        : '/accounting/salaries?${params.join('&')}';
    return await _api.get(url);
  }

  /// جلب تفاصيل كشف راتب
  Future<Map<String, dynamic>> getSalaryDetails(int id) async {
    return await _api.get('/accounting/salaries/$id/details');
  }

  /// إنشاء مسيّر رواتب شهري
  Future<Map<String, dynamic>> generateMonthlySalaries({
    required String companyId,
    required int month,
    required int year,
  }) async {
    return await _api.post('/accounting/salaries/generate', body: {
      'CompanyId': companyId,
      'Month': month,
      'Year': year,
    });
  }

  /// تعديل سطر راتب
  Future<Map<String, dynamic>> updateSalary(
    int id, {
    double? baseSalary,
    double? allowances,
    double? deductions,
    double? bonuses,
    String? notes,
  }) async {
    return await _api.put('/accounting/salaries/$id', body: {
      if (baseSalary != null) 'BaseSalary': baseSalary,
      if (allowances != null) 'Allowances': allowances,
      if (deductions != null) 'Deductions': deductions,
      if (bonuses != null) 'Bonuses': bonuses,
      if (notes != null) 'Notes': notes,
    });
  }

  /// صرف راتب
  Future<Map<String, dynamic>> paySalary(
    int id, {
    String? cashBoxId,
    required String paidById,
  }) async {
    return await _api.post('/accounting/salaries/$id/pay', body: {
      if (cashBoxId != null) 'CashBoxId': cashBoxId,
      'PaidById': paidById,
    });
  }

  /// صرف جميع رواتب شهر
  Future<Map<String, dynamic>> payAllSalaries({
    required String companyId,
    required int month,
    required int year,
    String? cashBoxId,
    required String paidById,
  }) async {
    return await _api.post('/accounting/salaries/pay-all', body: {
      'CompanyId': companyId,
      'Month': month,
      'Year': year,
      if (cashBoxId != null) 'CashBoxId': cashBoxId,
      'PaidById': paidById,
    });
  }

  /// حذف مسيّر رواتب شهر
  Future<Map<String, dynamic>> deletePayroll({
    required String companyId,
    required int month,
    required int year,
  }) async {
    return await _api.delete(
      '/accounting/salaries/payroll?companyId=$companyId&month=$month&year=$year',
    );
  }

  // ==================== سياسة الرواتب - Salary Policy ====================

  /// جلب سياسات الرواتب
  Future<Map<String, dynamic>> getSalaryPolicies(String companyId) async {
    return await _api.get('/accounting/salary-policies?companyId=$companyId');
  }

  /// إنشاء سياسة رواتب
  Future<Map<String, dynamic>> createSalaryPolicy({
    required String companyId,
    required String name,
    bool isDefault = true,
    double deductionPerLateMinute = 0,
    double maxLateDeductionPercent = 25,
    double absentDayMultiplier = 1,
    double deductionPerEarlyDepartureMinute = 0,
    double overtimeHourlyMultiplier = 1.5,
    int maxOvertimeHoursPerMonth = 40,
    double unpaidLeaveDayMultiplier = 1,
    int workDaysPerMonth = 26,
  }) async {
    return await _api.post('/accounting/salary-policies', body: {
      'CompanyId': companyId,
      'Name': name,
      'IsDefault': isDefault,
      'DeductionPerLateMinute': deductionPerLateMinute,
      'MaxLateDeductionPercent': maxLateDeductionPercent,
      'AbsentDayMultiplier': absentDayMultiplier,
      'DeductionPerEarlyDepartureMinute': deductionPerEarlyDepartureMinute,
      'OvertimeHourlyMultiplier': overtimeHourlyMultiplier,
      'MaxOvertimeHoursPerMonth': maxOvertimeHoursPerMonth,
      'UnpaidLeaveDayMultiplier': unpaidLeaveDayMultiplier,
      'WorkDaysPerMonth': workDaysPerMonth,
    });
  }

  /// تحديث سياسة رواتب
  Future<Map<String, dynamic>> updateSalaryPolicy(
    int id, {
    required String companyId,
    required String name,
    bool isDefault = true,
    double deductionPerLateMinute = 0,
    double maxLateDeductionPercent = 25,
    double absentDayMultiplier = 1,
    double deductionPerEarlyDepartureMinute = 0,
    double overtimeHourlyMultiplier = 1.5,
    int maxOvertimeHoursPerMonth = 40,
    double unpaidLeaveDayMultiplier = 1,
    int workDaysPerMonth = 26,
  }) async {
    return await _api.put('/accounting/salary-policies/$id', body: {
      'CompanyId': companyId,
      'Name': name,
      'IsDefault': isDefault,
      'DeductionPerLateMinute': deductionPerLateMinute,
      'MaxLateDeductionPercent': maxLateDeductionPercent,
      'AbsentDayMultiplier': absentDayMultiplier,
      'DeductionPerEarlyDepartureMinute': deductionPerEarlyDepartureMinute,
      'OvertimeHourlyMultiplier': overtimeHourlyMultiplier,
      'MaxOvertimeHoursPerMonth': maxOvertimeHoursPerMonth,
      'UnpaidLeaveDayMultiplier': unpaidLeaveDayMultiplier,
      'WorkDaysPerMonth': workDaysPerMonth,
    });
  }

  /// حذف سياسة رواتب
  Future<Map<String, dynamic>> deleteSalaryPolicy(int id) async {
    return await _api.delete('/accounting/salary-policies/$id');
  }

  // ==================== تقارير HR ====================
  // ==================== HR Reports ====================

  /// تقرير الحضور الشهري الشامل
  Future<Map<String, dynamic>> getAttendanceReport({
    required String companyId,
    int? month,
    int? year,
  }) async {
    String endpoint = '/hr-reports/attendance/monthly?companyId=$companyId';
    if (month != null) endpoint += '&month=$month';
    if (year != null) endpoint += '&year=$year';
    return await _api.get(endpoint);
  }

  /// تقرير الرواتب الشهري
  Future<Map<String, dynamic>> getSalaryReport({
    required String companyId,
    int? month,
    int? year,
  }) async {
    String endpoint = '/hr-reports/salaries/monthly?companyId=$companyId';
    if (month != null) endpoint += '&month=$month';
    if (year != null) endpoint += '&year=$year';
    return await _api.get(endpoint);
  }

  /// تقرير الإجازات
  Future<Map<String, dynamic>> getLeavesReport({
    required String companyId,
    int? year,
    int? month,
  }) async {
    String endpoint = '/hr-reports/leaves/summary?companyId=$companyId';
    if (year != null) endpoint += '&year=$year';
    if (month != null) endpoint += '&month=$month';
    return await _api.get(endpoint);
  }

  /// داشبورد الموارد البشرية
  Future<Map<String, dynamic>> getHrDashboard(String companyId) async {
    return await _api.get('/hr-reports/dashboard?companyId=$companyId');
  }

  /// تقرير موظف فردي
  Future<Map<String, dynamic>> getEmployeeReport({
    required String userId,
    int? month,
    int? year,
  }) async {
    String endpoint = '/hr-reports/employee/$userId';
    final params = <String>[];
    if (month != null) params.add('month=$month');
    if (year != null) params.add('year=$year');
    if (params.isNotEmpty) endpoint += '?${params.join('&')}';
    return await _api.get(endpoint);
  }

  /// تقريري الشخصي (لا يحتاج Admin - يجلب بيانات المستخدم الحالي)
  Future<Map<String, dynamic>> getMyReport({
    int? month,
    int? year,
  }) async {
    String endpoint = '/hr-reports/my-report';
    final params = <String>[];
    if (month != null) params.add('month=$month');
    if (year != null) params.add('year=$year');
    if (params.isNotEmpty) endpoint += '?${params.join('&')}';
    return await _api.get(endpoint);
  }

  /// تصدير حضور CSV
  Future<List<int>> exportAttendanceCsv({
    required String companyId,
    int? month,
    int? year,
  }) async {
    String endpoint = '/hr-reports/export/attendance?companyId=$companyId';
    if (month != null) endpoint += '&month=$month';
    if (year != null) endpoint += '&year=$year';
    return await _api.getBytes(endpoint);
  }

  /// تصدير رواتب CSV
  Future<List<int>> exportSalariesCsv({
    required String companyId,
    int? month,
    int? year,
  }) async {
    String endpoint = '/hr-reports/export/salaries?companyId=$companyId';
    if (month != null) endpoint += '&month=$month';
    if (year != null) endpoint += '&year=$year';
    return await _api.getBytes(endpoint);
  }

  /// تصدير إجازات CSV
  Future<List<int>> exportLeavesCsv({
    required String companyId,
    int? year,
  }) async {
    String endpoint = '/hr-reports/export/leaves?companyId=$companyId';
    if (year != null) endpoint += '&year=$year';
    return await _api.getBytes(endpoint);
  }

  // ============================================================
  //  تعديل/إنشاء/حذف سجلات الحضور
  // ============================================================

  /// تعديل سجل حضور موجود
  Future<Map<String, dynamic>> updateAttendanceRecord(
    int id, {
    int? status,
    String? checkInTime,
    String? checkOutTime,
    bool? clearCheckIn,
    bool? clearCheckOut,
    int? lateMinutes,
    int? overtimeMinutes,
    int? earlyDepartureMinutes,
    String? notes,
  }) async {
    final body = <String, dynamic>{};
    if (status != null) body['Status'] = status;
    if (checkInTime != null) body['CheckInTime'] = checkInTime;
    if (checkOutTime != null) body['CheckOutTime'] = checkOutTime;
    if (clearCheckIn == true) body['ClearCheckIn'] = true;
    if (clearCheckOut == true) body['ClearCheckOut'] = true;
    if (lateMinutes != null) body['LateMinutes'] = lateMinutes;
    if (overtimeMinutes != null) body['OvertimeMinutes'] = overtimeMinutes;
    if (earlyDepartureMinutes != null) {
      body['EarlyDepartureMinutes'] = earlyDepartureMinutes;
    }
    if (notes != null) body['Notes'] = notes;
    return await _api.put('/attendance/records/$id', body: body);
  }

  /// إنشاء سجل حضور يدوي
  Future<Map<String, dynamic>> createAttendanceRecord({
    required String userId,
    required String date,
    required int status,
    String? checkInTime,
    String? checkOutTime,
    int? lateMinutes,
    int? overtimeMinutes,
    int? earlyDepartureMinutes,
    String? notes,
  }) async {
    return await _api.post('/attendance/records', body: {
      'UserId': userId,
      'Date': date,
      'Status': status,
      'CheckInTime': checkInTime,
      'CheckOutTime': checkOutTime,
      'LateMinutes': lateMinutes,
      'OvertimeMinutes': overtimeMinutes,
      'EarlyDepartureMinutes': earlyDepartureMinutes,
      'Notes': notes,
    });
  }

  /// حذف سجل حضور
  Future<Map<String, dynamic>> deleteAttendanceRecord(int id) async {
    return await _api.delete('/attendance/records/$id');
  }
}
