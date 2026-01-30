import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'vps_auth_service.dart';

/// خدمة الاتصال بـ Sadara Platform API الجديد
/// تعمل مع Firebase Auth للمصادقة
class SadaraApiService {
  // ============================================
  // إعدادات API
  // ============================================

  /// رابط API للتطوير المحلي
  static const String _devBaseUrl = 'http://localhost:5000/api';

  /// رابط API للإنتاج (VPS)
  static const String _prodBaseUrl = 'http://72.61.183.61/api';

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

    // استخدام التوكن من VpsAuthService إذا لم يكن موجوداً
    final token = _jwtToken ?? VpsAuthService.instance.accessToken;
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
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
        throw Exception('انتهت صلاحية الجلسة');
      }

      throw Exception(data['message'] ?? 'خطأ غير معروف');
    } catch (e) {
      if (e is FormatException) {
        throw Exception('خطأ في تنسيق الاستجابة');
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
    return await put('/servicerequests/$id/status', body: {
      'status': status,
      'notes': notes,
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
