import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ApiService {
  static const String baseUrl = 'https://api.ftth.iq/api';

  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._internal();

  ApiService._internal();

  // طلب GET مع التعامل التلقائي مع التوكن
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        '$baseUrl$endpoint',
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في طلب GET');
    }
  }

  // طلب POST مع التعامل التلقائي مع التوكن
  Future<Map<String, dynamic>> post(String endpoint, {Object? body}) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'POST',
        '$baseUrl$endpoint',
        body: body is Map ? json.encode(body) : body,
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في طلب POST');
    }
  }

  // طلب PUT مع التعامل التلقائي مع التوكن
  Future<Map<String, dynamic>> put(String endpoint, {Object? body}) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'PUT',
        '$baseUrl$endpoint',
        body: body is Map ? json.encode(body) : body,
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في طلب PUT');
    }
  }

  // طلب DELETE مع التعامل التلقائي مع التوكن
  Future<Map<String, dynamic>> delete(String endpoint) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'DELETE',
        '$baseUrl$endpoint',
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في طلب DELETE');
    }
  }

  // طلب PATCH مع التعامل التلقائي مع التوكن
  Future<Map<String, dynamic>> patch(String endpoint, {Object? body}) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'PATCH',
        '$baseUrl$endpoint',
        body: body is Map ? json.encode(body) : body,
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في طلب PATCH');
    }
  }

  // معالجة الاستجابة
  Map<String, dynamic> _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return {'success': true, 'data': null};
      }

      try {
        final data = json.decode(response.body);
        // إذا كان الـ API يرجع صيغة {success, data} مسبقاً، أرجعه مباشرة بدون تغليف إضافي
        if (data is Map<String, dynamic> && data.containsKey('success')) {
          data['statusCode'] = response.statusCode;
          return data;
        }
        return {
          'success': true,
          'data': data,
          'statusCode': response.statusCode,
        };
      } catch (e) {
        return {
          'success': true,
          'data': response.body,
          'statusCode': response.statusCode,
        };
      }
    } else {
      String errorMessage = 'خطأ في الخادم: ${response.statusCode}';
      try {
        final errorData = json.decode(response.body);
        if (errorData is Map && errorData.containsKey('message')) {
          errorMessage = errorData['message'];
        } else if (errorData is Map && errorData.containsKey('error')) {
          errorMessage = errorData['error'];
        }
      } catch (e) {
        // استخدم الرسالة الافتراضية
      }

      return {
        'success': false,
        'message': errorMessage,
        'error': errorMessage,
        'statusCode': response.statusCode,
      };
    }
  }

  // طلبات مخصصة للمواقع الأخرى (غير api.ftth.iq)
  Future<Map<String, dynamic>> customGet(String fullUrl) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        fullUrl,
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في الطلب المخصص');
    }
  }

  Future<Map<String, dynamic>> customPost(String fullUrl,
      {Object? body}) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'POST',
        fullUrl,
        body: body is Map ? json.encode(body) : body,
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('خطأ في الطلب المخصص');
    }
  }

  /// تحميل ملف كـ bytes (لتصدير CSV)
  Future<List<int>> getBytes(String endpoint) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        '$baseUrl$endpoint',
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      } else {
        throw Exception('خطأ في التحميل: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('خطأ في تحميل الملف');
    }
  }
}
