import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'vps_auth_service.dart';
import 'api/api_client.dart';

/// خدمة الاتصال بـ Sadara Platform API الجديد
/// تعمل مع Firebase Auth للمصادقة
class SadaraApiService {
  // ============================================
  // إعدادات API
  // ============================================

  /// رابط API للتطوير المحلي
  static const String _devBaseUrl = 'http://localhost:5000/api';

  /// رابط API للإنتاج (VPS) - HTTPS مع دومين
  static const String _prodBaseUrl = 'https://api.ramzalsadara.tech/api';

  /// استخدام بيئة التطوير أو الإنتاج
  static const bool _isProduction = true;

  /// رابط API الفعلي
  static String get baseUrl => _isProduction ? _prodBaseUrl : _devBaseUrl;

  // Singleton
  static SadaraApiService? _instance;
  static SadaraApiService get instance =>
      _instance ??= SadaraApiService._internal();
  SadaraApiService._internal();

  // JWT Token المخزن محلياً
  String? _jwtToken;
  DateTime? _tokenExpiry;

  // ============================================
  // المصادقة
  // ============================================

  /// تسجيل الدخول باستخدام رقم الهاتف وكلمة المرور
  Future<AuthResult> login(String phoneNumber, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'phoneNumber': phoneNumber,
          'password': password,
        }),
      );

      final data = _handleResponse(response);

      if (data['success'] == true && data['data'] != null) {
        _jwtToken = data['data']['token'];
        _tokenExpiry = DateTime.now().add(const Duration(hours: 1));

        return AuthResult(
          success: true,
          token: _jwtToken,
          user: data['data']['user'],
        );
      }

      return AuthResult(
          success: false, error: data['message'] ?? 'فشل تسجيل الدخول');
    } catch (e) {
      return AuthResult(success: false, error: 'خطأ في الاتصال: $e');
    }
  }

  /// تسجيل الدخول باستخدام Firebase Token
  Future<AuthResult> loginWithFirebase() async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) {
        return AuthResult(
            success: false, error: 'لم يتم تسجيل الدخول في Firebase');
      }

      final firebaseToken = await firebaseUser.getIdToken();

      final response = await http.post(
        Uri.parse('$baseUrl/auth/firebase'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'firebaseToken': firebaseToken,
          'phoneNumber': firebaseUser.phoneNumber,
        }),
      );

      final data = _handleResponse(response);

      if (data['success'] == true && data['data'] != null) {
        _jwtToken = data['data']['token'];
        _tokenExpiry = DateTime.now().add(const Duration(hours: 1));

        return AuthResult(
          success: true,
          token: _jwtToken,
          user: data['data']['user'],
        );
      }

      return AuthResult(
          success: false, error: data['message'] ?? 'فشل المصادقة');
    } catch (e) {
      return AuthResult(success: false, error: 'خطأ: $e');
    }
  }

  /// تسجيل الخروج
  void logout() {
    _jwtToken = null;
    _tokenExpiry = null;
  }

  /// التحقق من صلاحية التوكن
  bool get isAuthenticated =>
      _jwtToken != null && (_tokenExpiry?.isAfter(DateTime.now()) ?? false);

  // ============================================
  // طلبات HTTP
  // ============================================

  /// طلب GET
  Future<Map<String, dynamic>> get(String endpoint) async {
    return _request('GET', endpoint);
  }

  /// طلب POST
  Future<Map<String, dynamic>> post(String endpoint,
      {Map<String, dynamic>? body}) async {
    return _request('POST', endpoint, body: body);
  }

  /// طلب PUT
  Future<Map<String, dynamic>> put(String endpoint,
      {Map<String, dynamic>? body}) async {
    return _request('PUT', endpoint, body: body);
  }

  /// طلب DELETE
  Future<Map<String, dynamic>> delete(String endpoint) async {
    return _request('DELETE', endpoint);
  }

  /// طلب مع رفع ملف
  Future<Map<String, dynamic>> uploadFile(String endpoint, File file,
      {Map<String, String>? fields}) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));

      request.headers.addAll(_getHeaders());
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      if (fields != null) {
        request.fields.addAll(fields);
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في رفع الملف: $e');
    }
  }

  /// تنفيذ الطلب
  Future<Map<String, dynamic>> _request(String method, String endpoint,
      {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = _getHeaders();

      http.Response response;

      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(uri,
              headers: headers, body: body != null ? json.encode(body) : null);
          break;
        case 'PUT':
          response = await http.put(uri,
              headers: headers, body: body != null ? json.encode(body) : null);
          break;
        case 'PATCH':
          response = await http.patch(uri,
              headers: headers, body: body != null ? json.encode(body) : null);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        default:
          throw Exception('طريقة غير مدعومة: $method');
      }

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في طلب $method: $e');
    }
  }

  /// الحصول على Headers
  Map<String, String> _getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    // محاولة الحصول على التوكن من عدة مصادر
    final token = _jwtToken ??
        VpsAuthService.instance.accessToken ??
        ApiClient.instance.authToken;

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
      debugPrint('🔑 SadaraAPI: Token found (${token.length} chars)');
    } else {
      debugPrint('⚠️ SadaraAPI: No auth token available from any source');
    }

    return headers;
  }

  /// معالجة الاستجابة
  Map<String, dynamic> _handleResponse(http.Response response) {
    try {
      final data = json.decode(response.body) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      }

      // معالجة الأخطاء
      if (response.statusCode == 401) {
        _jwtToken = null;
        throw Exception('انتهت صلاحية الجلسة - يرجى تسجيل الدخول مرة أخرى');
      }

      throw Exception(
          data['message'] ?? 'خطأ غير معروف (${response.statusCode})');
    } catch (e) {
      if (e is FormatException) {
        // الاستجابة ليست JSON
        if (response.statusCode == 401 || response.statusCode == 403) {
          _jwtToken = null;
          throw Exception(
              'غير مصرح - يرجى تسجيل الدخول مرة أخرى (${response.statusCode})');
        }
        if (response.statusCode == 404) {
          throw Exception('الخدمة غير متوفرة (404)');
        }
        if (response.statusCode >= 500) {
          throw Exception('خطأ في الخادم (${response.statusCode})');
        }
        throw Exception(
            'خطأ في تنسيق الاستجابة (${response.statusCode}): ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
      }
      rethrow;
    }
  }

  // ============================================
  // APIs المتاحة
  // ============================================

  // --- الخدمات ---
  Future<List<dynamic>> getServices() async {
    final result = await get('/services');
    return result['data'] ?? [];
  }

  Future<Map<String, dynamic>> getService(String id) async {
    return await get('/services/$id');
  }

  // --- طلبات الصيانة ---
  Future<List<dynamic>> getServiceRequests(
      {int page = 1, int pageSize = 20}) async {
    final result = await get('/servicerequests?page=$page&pageSize=$pageSize');
    return result['data'] ?? [];
  }

  Future<Map<String, dynamic>> getServiceRequest(String id) async {
    return await get('/servicerequests/$id');
  }

  Future<Map<String, dynamic>> createServiceRequest(
      Map<String, dynamic> request) async {
    return await post('/servicerequests', body: request);
  }

  Future<Map<String, dynamic>> updateServiceRequestStatus(
      String id, String status,
      {String? notes}) async {
    return await _request('PATCH', '/servicerequests/$id/status', body: {
      'status': status,
      'note': notes,
    });
  }

  Future<Map<String, dynamic>> addServiceRequestComment(
      String id, String content,
      {bool isInternal = false}) async {
    return await post('/servicerequests/$id/comments', body: {
      'content': content,
      'isVisibleToCitizen': !isInternal,
    });
  }

  Future<Map<String, dynamic>> deleteServiceRequest(String id) async {
    return await delete('/servicerequests/$id');
  }

  /// جلب الموظفين (فنيين وليدرز) للتعيين
  Future<Map<String, dynamic>> getTaskStaff({String? department}) async {
    final query = department != null ? '?department=$department' : '';
    return await get('/servicerequests/task-staff$query');
  }

  /// جلب بيانات القوائم المنسدلة للمهام
  Future<Map<String, dynamic>> getTaskLookupData() async {
    return await get('/servicerequests/task-lookup');
  }

  /// تعيين مهمة مع تفاصيل فنية
  Future<Map<String, dynamic>> assignTask(
    String id, {
    String? department,
    String? leader,
    String? technician,
    String? technicianPhone,
    String? fbg,
    String? fat,
    String? address,
    String? employeeId,
    String? note,
  }) async {
    final body = <String, dynamic>{
      if (department != null) 'Department': department,
      if (leader != null) 'Leader': leader,
      if (technician != null) 'Technician': technician,
      if (technicianPhone != null) 'TechnicianPhone': technicianPhone,
      if (fbg != null) 'FBG': fbg,
      if (fat != null) 'FAT': fat,
      if (address != null) 'Address': address,
      if (employeeId != null) 'EmployeeId': employeeId,
      if (note != null) 'Note': note,
    };
    return await _request('PATCH', '/servicerequests/$id/assign-task',
        body: body);
  }

  Future<Map<String, dynamic>> getServiceRequestStatistics(
      {String? companyId}) async {
    final query = companyId != null ? '?companyId=$companyId' : '';
    return await get('/servicerequests/statistics$query');
  }

  Future<List<dynamic>> getAvailableServices() async {
    final result = await get('/servicerequests/services');
    return result['data'] ?? [];
  }

  // --- الملف الشخصي ---
  Future<Map<String, dynamic>> getProfile() async {
    return await get('/users/profile');
  }

  Future<Map<String, dynamic>> updateProfile(
      Map<String, dynamic> profile) async {
    return await put('/users/profile', body: profile);
  }

  // --- الإحصائيات ---
  Future<Map<String, dynamic>> getDashboardStats() async {
    return await get('/statistics/dashboard');
  }

  // --- الإشعارات ---
  Future<List<dynamic>> getNotifications({int page = 1}) async {
    final result = await get('/notifications?page=$page');
    return result['data'] ?? [];
  }

  Future<void> markNotificationAsRead(String id) async {
    await put('/notifications/$id/read');
  }

  // --- للسوبر أدمن فقط ---
  Future<Map<String, dynamic>> getServerHealth() async {
    return await get('/server/health');
  }

  Future<Map<String, dynamic>> getServerDashboard() async {
    return await get('/server/dashboard');
  }

  Future<List<dynamic>> getAllUsers({int page = 1, int pageSize = 20}) async {
    final result = await get('/superadmin/users?page=$page&pageSize=$pageSize');
    return result['data'] ?? [];
  }

  // --- إدارة الباقات (سوبر أدمن) ---
  Future<List<dynamic>> getPlans() async {
    final result = await get('/superadmin/plans');
    return result['data'] ?? [];
  }

  Future<Map<String, dynamic>> createPlan(Map<String, dynamic> plan) async {
    return await post('/superadmin/plans', body: plan);
  }

  Future<Map<String, dynamic>> updatePlan(
      String id, Map<String, dynamic> plan) async {
    return await put('/superadmin/plans/$id', body: plan);
  }

  Future<Map<String, dynamic>> deletePlan(String id) async {
    return await delete('/superadmin/plans/$id');
  }
}

/// نتيجة المصادقة
class AuthResult {
  final bool success;
  final String? token;
  final Map<String, dynamic>? user;
  final String? error;

  AuthResult({
    required this.success,
    this.token,
    this.user,
    this.error,
  });
}
