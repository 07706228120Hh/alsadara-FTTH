import 'api/api_client.dart';
import 'api/api_response.dart';

/// خدمة إدارة المهام عبر VPS API
/// تستخدم ApiClient (توكن سيرفرنا) بدلاً من ApiService القديم (توكن FTTH)
class TaskApiService {
  static TaskApiService? _instance;
  static TaskApiService get instance =>
      _instance ??= TaskApiService._internal();

  TaskApiService._internal();

  final _client = ApiClient.instance;

  /// تحويل ApiResponse إلى Map<String, dynamic> للتوافق مع الكود الحالي
  Map<String, dynamic> _toMap<T>(ApiResponse<T> response) {
    if (response.success) {
      return {
        'success': true,
        'data': response.data,
        'statusCode': response.statusCode,
      };
    } else {
      return {
        'success': false,
        'message': response.message ?? 'خطأ غير معروف',
        'error': response.message ?? 'خطأ غير معروف',
        'statusCode': response.statusCode,
      };
    }
  }

  // ═══════ إنشاء مهمة جديدة ═══════

  /// إنشاء مهمة/طلب مباشر
  Future<Map<String, dynamic>> createTask({
    required String taskType,
    required String customerName,
    required String customerPhone,
    String? department,
    String? leader,
    String? technician,
    String? technicianPhone,
    String? fbg,
    String? fat,
    String? location,
    String? notes,
    String? summary,
    String priority = 'متوسط',
    String? serviceType,
    String? subscriptionDuration,
    double? subscriptionAmount,
    int serviceId = 9, // Internet FTTH
    int? operationTypeId,
  }) async {
    final body = <String, dynamic>{
      'TaskType': taskType,
      'CustomerName': customerName,
      'CustomerPhone': customerPhone,
      'Department': department,
      'Leader': leader,
      'Technician': technician,
      'TechnicianPhone': technicianPhone,
      'FBG': fbg,
      'FAT': fat,
      'Location': location,
      'Notes': notes,
      'Summary': summary,
      'Priority': priority,
      'ServiceType': serviceType,
      'SubscriptionDuration': subscriptionDuration,
      'SubscriptionAmount': subscriptionAmount,
      'ServiceId': serviceId,
      'OperationTypeId': operationTypeId,
    };

    // إزالة القيم null
    body.removeWhere((key, value) => value == null);

    final response = await _client.post(
      '/servicerequests/create-task',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════ جلب الطلبات ═══════

  /// جلب جميع الطلبات مع تصفية
  Future<Map<String, dynamic>> getRequests({
    int page = 1,
    int pageSize = 50,
    String? status,
    int? serviceId,
    String? source,
    String? department,
    String? technician,
  }) async {
    String query = '/servicerequests?page=$page&pageSize=$pageSize';
    if (status != null) query += '&status=$status';
    if (serviceId != null) query += '&serviceId=$serviceId';
    if (source != null) query += '&source=$source';
    if (department != null)
      query += '&department=${Uri.encodeComponent(department)}';
    if (technician != null)
      query += '&technician=${Uri.encodeComponent(technician)}';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// جلب طلب بالمعرف
  Future<Map<String, dynamic>> getRequestById(String id) async {
    final response = await _client.get('/servicerequests/$id', (json) => json);
    return _toMap(response);
  }

  // ═══════ تحديث الحالة ═══════

  /// تحديث حالة طلب
  Future<Map<String, dynamic>> updateStatus(
    String requestId, {
    required String status,
    String? note,
    double? amount,
  }) async {
    final body = <String, dynamic>{
      'Status': status,
      'Note': note,
    };
    if (amount != null && amount > 0) {
      body['Amount'] = amount;
    }
    final response = await _client.patch(
      '/servicerequests/$requestId/status',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════ تعيين مهمة ═══════

  /// تعيين مهمة مع تفاصيل فنية
  Future<Map<String, dynamic>> assignTask(
    String requestId, {
    String? department,
    String? leader,
    String? technician,
    String? technicianPhone,
    String? fbg,
    String? fat,
    String? employeeId,
    String? note,
  }) async {
    final body = <String, dynamic>{
      'Department': department,
      'Leader': leader,
      'Technician': technician,
      'TechnicianPhone': technicianPhone,
      'FBG': fbg,
      'FAT': fat,
      'Note': note,
    };

    if (employeeId != null) {
      body['EmployeeId'] = employeeId;
    }

    body.removeWhere((key, value) => value == null);

    final response = await _client.patch(
      '/servicerequests/$requestId/assign-task',
      body,
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════ بيانات القوائم ═══════

  /// جلب بيانات القوائم المنسدلة (أقسام، أولويات، مهام الأقسام، FBG، إلخ)
  Future<Map<String, dynamic>> getTaskLookupData() async {
    final response =
        await _client.get('/servicerequests/task-lookup', (json) => json);
    return _toMap(response);
  }

  /// جلب الموظفين (فنيين وليدرز) حسب القسم
  Future<Map<String, dynamic>> getTaskStaff({String? department}) async {
    String query = '/servicerequests/task-staff';
    if (department != null && department.isNotEmpty) {
      query += '?department=${Uri.encodeComponent(department)}';
    }
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  // ═══════ التعليقات ═══════

  /// إضافة تعليق على طلب
  Future<Map<String, dynamic>> addComment(
    String requestId, {
    required String content,
    bool isVisibleToCitizen = true,
  }) async {
    final response = await _client.post(
      '/servicerequests/$requestId/comments',
      {
        'Content': content,
        'IsVisibleToCitizen': isVisibleToCitizen,
      },
      (json) => json,
    );
    return _toMap(response);
  }

  /// جلب تعليقات الطلب
  Future<Map<String, dynamic>> getComments(String requestId) async {
    final response = await _client.get(
        '/servicerequests/$requestId/comments', (json) => json);
    return _toMap(response);
  }

  // ═══════ الإحصائيات ═══════

  /// إحصائيات الطلبات
  Future<Map<String, dynamic>> getStatistics() async {
    final response =
        await _client.get('/servicerequests/statistics', (json) => json);
    return _toMap(response);
  }

  // ═══════ الحذف ═══════

  /// حذف طلب (SuperAdmin فقط)
  Future<Map<String, dynamic>> deleteRequest(String requestId) async {
    final response =
        await _client.delete('/servicerequests/$requestId', (json) => json);
    return _toMap(response);
  }

  // ═══════ تعيين بسيط ═══════

  /// تعيين موظف للطلب (الطريقة القديمة)
  Future<Map<String, dynamic>> assignToEmployee(
    String requestId,
    String employeeId,
  ) async {
    final response = await _client.patch(
      '/servicerequests/$requestId/assign',
      {'EmployeeId': employeeId},
      (json) => json,
    );
    return _toMap(response);
  }

  // ═══════ مهامي (الطلبات المعينة لي) ═══════

  /// جلب المهام المعينة للفني الحالي
  Future<Map<String, dynamic>> getMyTasks({
    int page = 1,
    int pageSize = 50,
    String? technicianName,
    bool includeCompleted = false,
  }) async {
    String query = '/servicerequests/my-assigned?page=$page&pageSize=$pageSize';
    if (technicianName != null) {
      query += '&technicianName=${Uri.encodeComponent(technicianName)}';
    }
    if (includeCompleted) query += '&includeCompleted=true';
    final response = await _client.get(query, (json) => json);
    return _toMap(response);
  }

  /// جلب المهام حسب القسم
  Future<Map<String, dynamic>> getByDepartment({
    required String department,
    int page = 1,
    int pageSize = 50,
  }) async {
    return await getRequests(
      page: page,
      pageSize: pageSize,
      department: department,
    );
  }

  // ═══════ تدقيق المهام ═══════

  /// جلب جميع سجلات التدقيق كـ Map
  Future<Map<String, dynamic>> getAuditsBulk() async {
    final response = await _client.get('/taskaudits/bulk', (json) => json);
    return _toMap(response);
  }

  /// حفظ تدقيق مهمة واحدة
  Future<Map<String, dynamic>> saveAudit({
    required String requestNumber,
    String? auditStatus,
    int? rating,
    String? notes,
    String? auditedBy,
  }) async {
    final body = <String, dynamic>{
      'RequestNumber': requestNumber,
      'AuditStatus': auditStatus,
      'Rating': rating,
      'Notes': notes,
      'AuditedBy': auditedBy,
    };
    body.removeWhere((key, value) => value == null);

    final response = await _client.post(
      '/taskaudits',
      body,
      (json) => json,
    );
    return _toMap(response);
  }
}
