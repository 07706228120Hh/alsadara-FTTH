import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';
import 'api_config.dart';
import 'api_response.dart';
import '../../config/app_secrets.dart';

/// العميل الأساسي للاتصال بـ API
class ApiClient {
  static ApiClient? _instance;
  static ApiClient get instance => _instance ??= ApiClient._internal();
  ApiClient._internal();

  /// إنشاء HTTP Client يدعم الشهادات الموقعة ذاتياً
  late final http.Client _client = _createHttpClient();

  /// إنشاء HttpClient مع تجاوز التحقق من الشهادات (للتطوير)
  http.Client _createHttpClient() {
    // في بيئة الإنتاج مع شهادة موقعة ذاتياً، نحتاج لتجاوز التحقق
    final httpClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // السماح بالشهادات الموقعة ذاتياً للـ VPS فقط
        if (kDebugMode) {
          print('⚠️ تجاوز التحقق من الشهادة لـ: $host:$port');
        }
        return true; // قبول جميع الشهادات (للتطوير فقط)
      };
    return IOClient(httpClient);
  }

  String? _authToken;
  DateTime? _tokenExpiry;
  String? _refreshToken;

  // ============================================
  // Token Management
  // ============================================

  /// تعيين التوكن
  void setAuthToken(String token, {String? refreshToken, DateTime? expiresAt}) {
    _authToken = token;
    _refreshToken = refreshToken;
    _tokenExpiry = expiresAt ?? DateTime.now().add(const Duration(hours: 24));
  }

  /// مسح التوكن
  void clearAuthToken() {
    _authToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
  }

  /// هل مصادق؟
  bool get isAuthenticated =>
      _authToken != null && (_tokenExpiry?.isAfter(DateTime.now()) ?? false);

  /// الحصول على التوكن
  String? get authToken => _authToken;

  /// الحصول على Refresh Token
  String? get refreshToken => _refreshToken;

  // ============================================
  // Headers
  // ============================================

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  Map<String, String> get _internalHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Api-Key': appSecrets.internalApiKey, // 🔒 تم نقله إلى AppSecrets
      };

  // ============================================
  // HTTP Methods
  // ============================================

  /// طلب GET
  Future<ApiResponse<T>> get<T>(
    String endpoint,
    T Function(dynamic) parser, {
    bool useInternalKey = false,
  }) async {
    return _request('GET', endpoint, parser, useInternalKey: useInternalKey);
  }

  /// طلب POST
  Future<ApiResponse<T>> post<T>(
    String endpoint,
    dynamic body,
    T Function(dynamic) parser, {
    bool useInternalKey = false,
  }) async {
    return _request('POST', endpoint, parser,
        body: body, useInternalKey: useInternalKey);
  }

  /// طلب PUT
  Future<ApiResponse<T>> put<T>(
    String endpoint,
    dynamic body,
    T Function(dynamic) parser, {
    bool useInternalKey = false,
  }) async {
    return _request('PUT', endpoint, parser,
        body: body, useInternalKey: useInternalKey);
  }

  /// طلب PATCH
  Future<ApiResponse<T>> patch<T>(
    String endpoint,
    dynamic body,
    T Function(dynamic) parser, {
    bool useInternalKey = false,
  }) async {
    return _request('PATCH', endpoint, parser,
        body: body, useInternalKey: useInternalKey);
  }

  /// طلب DELETE
  Future<ApiResponse<T>> delete<T>(
    String endpoint,
    T Function(dynamic) parser, {
    bool useInternalKey = false,
  }) async {
    return _request('DELETE', endpoint, parser, useInternalKey: useInternalKey);
  }

  // ============================================
  // Internal Request Handler
  // ============================================

  Future<ApiResponse<T>> _request<T>(
    String method,
    String endpoint,
    T Function(dynamic) parser, {
    dynamic body,
    bool useInternalKey = false,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
      final headers = useInternalKey ? _internalHeaders : _headers;

      if (kDebugMode) {
        print('🌐 API Request: $method $uri');
        if (body != null) print('📤 Body: ${jsonEncode(body)}');
        // إضافة لوج للتحقق من التوكن
        if (!useInternalKey) {
          if (_authToken != null && _authToken!.isNotEmpty) {
            final tokenPreview = _authToken!.length > 20
                ? '${_authToken!.substring(0, 20)}...'
                : _authToken!;
            print('🔑 Token: $tokenPreview');
          } else {
            print('⚠️ لا يوجد توكن في ApiClient!');
          }
        }
      }

      http.Response response;

      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(ApiConfig.connectionTimeout);
          break;
        case 'POST':
          response = await _client
              .post(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(ApiConfig.connectionTimeout);
          break;
        case 'PUT':
          response = await _client
              .put(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(ApiConfig.connectionTimeout);
          break;
        case 'PATCH':
          response = await _client
              .patch(uri,
                  headers: headers,
                  body: body != null ? jsonEncode(body) : null)
              .timeout(ApiConfig.connectionTimeout);
          break;
        case 'DELETE':
          response = await _client
              .delete(uri, headers: headers)
              .timeout(ApiConfig.connectionTimeout);
          break;
        default:
          throw Exception('Unsupported HTTP method: $method');
      }

      return _handleResponse(response, parser);
    } on SocketException {
      return ApiResponse.error('لا يوجد اتصال بالإنترنت', statusCode: 0);
    } on HttpException {
      return ApiResponse.error('خطأ في الاتصال', statusCode: 0);
    } on FormatException {
      return ApiResponse.error('خطأ في تنسيق البيانات', statusCode: 0);
    } catch (e) {
      if (kDebugMode) print('❌ API Error: $e');
      return ApiResponse.error('خطأ: $e', statusCode: 0);
    }
  }

  // ============================================
  // Response Handler
  // ============================================

  ApiResponse<T> _handleResponse<T>(
    http.Response response,
    T Function(dynamic) parser,
  ) {
    if (kDebugMode) {
      final bodyPreview = response.body.isEmpty
          ? '(empty)'
          : response.body.substring(
              0, response.body.length > 500 ? 500 : response.body.length);
      print('📥 Response [${response.statusCode}]: $bodyPreview');
    }

    // التحقق من body فارغ
    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // نجاح بدون محتوى
        try {
          return ApiResponse.success(
            true as T,
            statusCode: response.statusCode,
          );
        } catch (_) {
          return ApiResponse.error(
            'استجابة فارغة',
            statusCode: response.statusCode,
          );
        }
      } else {
        // فشل بدون محتوى
        return ApiResponse.error(
          _getErrorMessage(response.statusCode),
          statusCode: response.statusCode,
        );
      }
    }

    try {
      final body = jsonDecode(response.body);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // نجاح

        // تحليل الاستجابة - دعم أنواع مختلفة من الاستجابات:
        // 1. استجابة بسيطة (Array من الشركات من Internal API)
        if (body is List) {
          return ApiResponse.success(
            parser(body),
            statusCode: response.statusCode,
            message: 'تم استلام البيانات بنجاح',
          );
        }

        // 2. استجابة مع wrapper { "success": true, "data": ... }
        if (body['success'] == true && body['data'] != null) {
          return ApiResponse.success(
            parser(body['data']),
            statusCode: response.statusCode,
            message: body['message']?.toString(),
          );
        }

        // 3. استجابة ناجحة بدون data (مثل logout)
        else if (body['success'] == true) {
          try {
            return ApiResponse.success(
              parser(body),
              statusCode: response.statusCode,
              message: body['message']?.toString(),
            );
          } catch (_) {
            return ApiResponse.success(
              true as T,
              statusCode: response.statusCode,
              message: body['message']?.toString(),
            );
          }
        }

        // 4. استجابة من InternalDataController التي تحتوي على { data: [...], total: ... }
        // بدون success wrapper
        if (body['data'] != null) {
          return ApiResponse.success(
            parser(body['data']),
            statusCode: response.statusCode,
            message: 'تم استلام البيانات بنجاح',
          );
        }

        // 5. استجابة مباشرة بدون أي wrapper
        return ApiResponse.success(
          parser(body),
          statusCode: response.statusCode,
          message: 'تم استلام البيانات بنجاح',
        );
      } else {
        // فشل
        return ApiResponse.error(
          body['message']?.toString() ?? _getErrorMessage(response.statusCode),
          statusCode: response.statusCode,
          errors:
              body['errors'] != null ? List<String>.from(body['errors']) : null,
        );
      }
    } catch (e) {
      return ApiResponse.error(
        'خطأ في معالجة الاستجابة: $e',
        statusCode: response.statusCode,
      );
    }
  }

  String _getErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'طلب غير صالح';
      case 401:
        return 'غير مصرح';
      case 403:
        return 'ممنوع الوصول';
      case 404:
        return 'غير موجود';
      case 500:
        return 'خطأ في الخادم';
      default:
        return 'خطأ غير معروف ($statusCode)';
    }
  }

  // ============================================
  // Cleanup
  // ============================================

  void dispose() {
    _client.close();
  }
}
