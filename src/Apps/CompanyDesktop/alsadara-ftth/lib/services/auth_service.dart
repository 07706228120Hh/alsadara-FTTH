import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _baseUrl = 'https://admin.ftth.iq/api/auth/Contractor';
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenExpiryKey = 'token_expiry';
  static const String _refreshExpiryKey = 'refresh_expiry';

  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._internal();

  AuthService._internal();
  Timer? _tokenRefreshTimer;
  StreamController<bool>? _authStateController;

  // ===== تحسينات تقليل 401 =====
  bool _refreshInProgress = false; // منع سباق التجديد
  final List<Completer<bool>> _refreshWaiters = [];
  int _totalRequests = 0;
  int _unexpected401 = 0; // 401 بعد تجديد ناجح أو خارج إطار الانتهاء المتوقع
  int _handled401 = 0; // 401 تم حلها عبر Refresh

  int get totalRequests => _totalRequests;
  int get unexpected401Count => _unexpected401;
  int get handled401Count => _handled401;
  double get unexpected401Ratio =>
      _totalRequests == 0 ? 0 : _unexpected401 / _totalRequests;

  Stream<bool> get authStateStream {
    _initializeAuthStateController();
    return _authStateController!.stream;
  }

  void _initializeAuthStateController() {
    _authStateController ??= StreamController<bool>.broadcast();
  }

  // إخراج المستخدم عند انتهاء الجلسة
  void _notifyAuthStateChange(bool isAuthenticated) {
    if (_authStateController != null && !_authStateController!.isClosed) {
      _authStateController!.add(isAuthenticated);
    }
  }

  // تسجيل الدخول
  Future<Map<String, dynamic>> login(String username, String password) async {
    // حراسة: منع استدعاء بخانات فارغة
    if (username.trim().isEmpty || password.isEmpty) {
      return {
        'success': false,
        'message': 'الرجاء إدخال اسم المستخدم وكلمة المرور',
      };
    }

    // ترميز آمن (يعالج الرموز الخاصة مثل & و = والتي كانت قد تكسر الطلب)
    final encodedBody =
        'username=${Uri.encodeQueryComponent(username.trim())}&password=${Uri.encodeQueryComponent(password)}&grant_type=password&scope=openid%20profile';

    // إعادة المحاولة لحالات الشبكة المؤقتة
    const transientStatus = {408, 429, 500, 502, 503, 504};
    int attempt = 0;
    http.Response? response;
    dynamic lastError;

    while (attempt < 3) {
      attempt++;
      try {
        response = await http.post(
          Uri.parse('$_baseUrl/token'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
            'Accept': 'application/json, text/plain, */*',
            'Origin': 'https://admin.ftth.iq',
            'Referer': 'https://admin.ftth.iq/auth/login',
            'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
            'x-kl-ajax-request': 'Ajax_Request',
            'x-user-role': '0',
          },
          body: encodedBody,
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          // تحقق احترازي: وجود access_token
          if (data['access_token'] == null) {
            return {
              'success': false,
              'message': 'استجابة غير متوقعة من الخادم (بدون توكن)',
            };
          }
          await _saveTokens(data);
          _startTokenRefreshTimer();
          _initializeAuthStateController();
          _notifyAuthStateChange(true);
          return {
            'success': true,
            'message': 'تم تسجيل الدخول بنجاح',
            'data': data,
          };
        }

        // إذا كان خطأ اعتماد (400/401) أعد رسالة واضحة ولا تحاول أكثر
        if (response.statusCode == 400 || response.statusCode == 401) {
          return {
            'success': false,
            'message':
                'بيانات الدخول غير صحيحة (تحقق من اسم المستخدم أو كلمة المرور)',
          };
        }

        // إذا حالة عابرة جرّب مرة أخرى مع تأخير متزايد
        if (transientStatus.contains(response.statusCode) && attempt < 3) {
          final delay = Duration(milliseconds: 350 * attempt); // backoff بسيط
          await Future.delayed(delay);
          continue;
        }

        // حالات أخرى: أعد كود الحالة
        return {
          'success': false,
          'message': 'فشل تسجيل الدخول: ${response.statusCode}',
        };
      } catch (e) {
        lastError = e;
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 250 * attempt));
          continue;
        }
      }
    }

    return {
      'success': false,
      'message': 'خطأ في الاتصال: $lastError',
    };
  }

  // حفظ التوكنات
  Future<void> _saveTokens(Map<String, dynamic> tokenData) async {
    final prefs = await SharedPreferences.getInstance();

    final accessToken = tokenData['access_token'];
    final refreshToken = tokenData['refresh_token'];
    final expiresIn = tokenData['expires_in'] ?? 3600.0;
    final refreshExpiresIn = tokenData['refresh_expires_in'] ?? 691200.0;

    final now = DateTime.now();
    final accessTokenExpiry = now.add(Duration(seconds: expiresIn.toInt()));
    final refreshTokenExpiry =
        now.add(Duration(seconds: refreshExpiresIn.toInt()));

    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    await prefs.setString(_tokenExpiryKey, accessTokenExpiry.toIso8601String());
    await prefs.setString(
        _refreshExpiryKey, refreshTokenExpiry.toIso8601String());
  }

  // الحصول على التوكن الحالي
  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_accessTokenKey);
    final expiryString = prefs.getString(_tokenExpiryKey);

    if (token == null || expiryString == null) {
      // محاولة إعادة تسجيل الدخول تلقائياً
      final reloginSuccess = await _tryAutoRelogin();
      if (reloginSuccess) {
        return prefs.getString(_accessTokenKey);
      }
      return null;
    }

    final expiry = DateTime.parse(expiryString);
    final now = DateTime.now();

    // إذا كان التوكن سينتهي في أقل من 5 دقائق، جدده
    // تجديد استباقي عندما يتبقى أقل من 4 دقائق
    if (expiry.difference(now).inMinutes < 4) {
      final refreshed = await _singleFlightRefresh();
      if (refreshed) return prefs.getString(_accessTokenKey);

      // إذا فشل التجديد، جرب إعادة تسجيل الدخول
      final reloginSuccess = await _tryAutoRelogin();
      if (reloginSuccess) {
        return prefs.getString(_accessTokenKey);
      }
      return null;
    }

    return token;
  }

  // تحديث التوكن
  Future<bool> _refreshAccessToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString(_refreshTokenKey);
      final refreshExpiryString = prefs.getString(_refreshExpiryKey);

      if (refreshToken == null || refreshExpiryString == null) {
        return false;
      }

      final refreshExpiry = DateTime.parse(refreshExpiryString);
      if (DateTime.now().isAfter(refreshExpiry)) {
        return false;
      }

      // محاولة مع إعادة محاولة بسيطة في حال استجابة شبكة مؤقتة (مثل 502)
      int attempts = 0;
      while (attempts < 2) {
        // محاولة + إعادة محاولة واحدة
        attempts++;
        final response = await http.post(
          Uri.parse('$_baseUrl/refresh'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json, text/plain, */*',
            'Origin': 'https://admin.ftth.iq',
            'Referer': 'https://admin.ftth.iq/',
            'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
            'x-user-role': '0',
          },
          body: 'refresh_token=$refreshToken&grant_type=refresh_token',
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          await _saveTokens(data);
          return true;
        }
        if (response.statusCode == 400 || response.statusCode == 401) {
          // لا فائدة من إعادة المحاولة – توكن منتهي أو مرفوض
          return false;
        }
        await Future.delayed(const Duration(milliseconds: 600));
      }
      return false;
    } catch (e) {
      print('خطأ في تحديث التوكن: $e');
      return false;
    }
  }

  // يمنع توازي _refreshAccessToken عبر Single-Flight
  Future<bool> _singleFlightRefresh() async {
    if (_refreshInProgress) {
      final completer = Completer<bool>();
      _refreshWaiters.add(completer);
      return completer.future;
    }
    _refreshInProgress = true;
    bool ok = false;
    try {
      ok = await _refreshAccessToken();
    } finally {
      _refreshInProgress = false;
      for (final w in _refreshWaiters) {
        if (!w.isCompleted) w.complete(ok);
      }
      _refreshWaiters.clear();
    }
    return ok;
  }

  // بدء مؤقت تحديث التوكن
  void _startTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();

    // جدد التوكن كل 30 دقيقة (للحفاظ على الاتصال دائماً)
    _tokenRefreshTimer = Timer.periodic(Duration(minutes: 30), (timer) async {
      final refreshed = await _refreshAccessToken();
      if (!refreshed) {
        // محاولة إعادة تسجيل الدخول تلقائياً بدلاً من تسجيل الخروج
        final reloginSuccess = await _tryAutoRelogin();
        if (!reloginSuccess) {
          await logout();
          timer.cancel();
        }
      }
    });
  }

  /// محاولة إعادة تسجيل الدخول تلقائياً باستخدام البيانات المحفوظة
  Future<bool> _tryAutoRelogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // استخدام نفس الأسماء المستخدمة في login_page
      final savedUsername = prefs.getString('savedUsername');
      final savedPassword = prefs.getString('savedPassword');
      final rememberCredentials = prefs.getBool('rememberMe') ?? false;

      if (!rememberCredentials ||
          savedUsername == null ||
          savedPassword == null) {
        print('🔐 لا توجد بيانات محفوظة لإعادة تسجيل الدخول التلقائي');
        return false;
      }

      print('🔄 جاري إعادة تسجيل الدخول تلقائياً...');
      final result = await login(savedUsername, savedPassword);

      if (result['success'] == true) {
        print('✅ تم إعادة تسجيل الدخول تلقائياً بنجاح');
        return true;
      } else {
        print('❌ فشل إعادة تسجيل الدخول التلقائي: ${result['message']}');
        return false;
      }
    } catch (e) {
      print('❌ خطأ في إعادة تسجيل الدخول التلقائي: $e');
      return false;
    }
  }

  /// تجديد التوكن الآن (يمكن استدعاؤها من أي مكان)
  Future<bool> refreshTokenNow() async {
    final refreshed = await _refreshAccessToken();
    if (refreshed) return true;

    // إذا فشل التجديد، جرب إعادة تسجيل الدخول
    return await _tryAutoRelogin();
  }

  // التحقق من صحة الجلسة
  Future<bool> isValidSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_accessTokenKey);
    final refreshToken = prefs.getString(_refreshTokenKey);
    final refreshExpiryString = prefs.getString(_refreshExpiryKey);

    if (accessToken == null ||
        refreshToken == null ||
        refreshExpiryString == null) {
      return false;
    }

    final refreshExpiry = DateTime.parse(refreshExpiryString);
    return DateTime.now().isBefore(refreshExpiry);
  }

  // تسجيل الخروج
  Future<void> logout() async {
    _tokenRefreshTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_tokenExpiryKey);
    await prefs.remove(_refreshExpiryKey);

    _notifyAuthStateChange(false);
  }

  // تسجيل الخروج مع مسح جميع البيانات المحفوظة محلياً
  Future<void> logoutAndClearAll() async {
    _tokenRefreshTimer?.cancel();

    final prefs = await SharedPreferences.getInstance();

    // مسح معلومات المصادقة
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_tokenExpiryKey);
    await prefs.remove(_refreshExpiryKey);

    // مسح معلومات تسجيل الدخول المحفوظة
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
    await prefs.remove('remember_credentials');

    // مسح معلومات أخرى قد تكون محفوظة
    await prefs.remove('user_data');
    await prefs.remove('last_login_time');

    _notifyAuthStateChange(false);
  }

  // إنشاء رؤوس HTTP مع التوكن
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getAccessToken();
    if (token == null) {
      throw Exception('لا يوجد توكن صالح');
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  // طريقة لعمل طلبات HTTP مع التعامل التلقائي مع انتهاء التوكن
  Future<http.Response> authenticatedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    try {
      _totalRequests++;
      final authHeaders = await getAuthHeaders();
      final allHeaders = {...authHeaders, ...?headers};

      const requestTimeout = Duration(seconds: 30);
      http.Response response;
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http
              .get(Uri.parse(url), headers: allHeaders)
              .timeout(requestTimeout);
          break;
        case 'POST':
          response = await http
              .post(Uri.parse(url), headers: allHeaders, body: body)
              .timeout(requestTimeout);
          break;
        case 'PUT':
          response = await http
              .put(Uri.parse(url), headers: allHeaders, body: body)
              .timeout(requestTimeout);
          break;
        case 'DELETE':
          response = await http
              .delete(Uri.parse(url), headers: allHeaders)
              .timeout(requestTimeout);
          break;
        case 'PATCH':
          response = await http
              .patch(Uri.parse(url), headers: allHeaders, body: body)
              .timeout(requestTimeout);
          break;
        default:
          throw Exception('طريقة HTTP غير مدعومة: $method');
      }

      // إذا كان الرد 401 (غير مخول)، حاول تحديث التوكن
      if (response.statusCode == 401) {
        final refreshed = await _singleFlightRefresh();
        if (refreshed) {
          _handled401++;
          // أعد المحاولة مع التوكن الجديد
          final newAuthHeaders = await getAuthHeaders();
          final newAllHeaders = {...newAuthHeaders, ...?headers};

          switch (method.toUpperCase()) {
            case 'GET':
              response = await http
                  .get(Uri.parse(url), headers: newAllHeaders)
                  .timeout(requestTimeout);
              break;
            case 'POST':
              response = await http
                  .post(Uri.parse(url), headers: newAllHeaders, body: body)
                  .timeout(requestTimeout);
              break;
            case 'PUT':
              response = await http
                  .put(Uri.parse(url), headers: newAllHeaders, body: body)
                  .timeout(requestTimeout);
              break;
            case 'DELETE':
              response = await http
                  .delete(Uri.parse(url), headers: newAllHeaders)
                  .timeout(requestTimeout);
              break;
            case 'PATCH':
              response = await http
                  .patch(Uri.parse(url), headers: newAllHeaders, body: body)
                  .timeout(requestTimeout);
              break;
          }
        } else {
          // فشل التجديد – زيادة عداد 401 غير المتوقعة
          _unexpected401++;
          await logout();
          throw Exception('انتهت جلسة المستخدم');
        }
      }

      return response;
    } catch (e) {
      if (e.toString().contains('انتهت جلسة المستخدم') ||
          e.toString().contains('لا يوجد توكن صالح')) {
        rethrow;
      }
      throw Exception('خطأ في الطلب: $e');
    }
  }

  void dispose() {
    _tokenRefreshTimer?.cancel();
    _authStateController?.close();
  }
}
