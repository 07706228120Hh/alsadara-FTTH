import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'cloudflare_bypass_service.dart';

/// خدمة المصادقة المخصصة لصفحة تفاصيل الوكلاء
class AgentsAuthService {
  static const String _baseUrl = 'https://admin.ftth.iq/api';
  static const String _dashboardBaseUrl = 'https://dashboard.ftth.iq';

  // مفاتيح التخزين المحلي
  static const String _accessTokenKey = 'agents_access_token';
  static const String _refreshTokenKey = 'agents_refresh_token';
  static const String _guestTokenKey = 'agents_guest_token';
  static const String _userInfoKey = 'agents_user_info';
  static const String _tokenExpiryKey = 'agents_token_expiry';

  // متغيرات التخزين المؤقت
  static String? _cachedAccessToken;
  static String? _cachedGuestToken;
  static String? _cachedRefreshToken;
  static UserInfo? _cachedUserInfo;
  static DateTime? _tokenExpiry;

  // Session cookies for dashboard API
  static String? _sessionCookie;
  static final Map<String, String> _cookies = {};

  // Dashboard embedded URL for referer
  // UUID الصحيح من المتصفح - Dashboard 7 "My Zones Dash"
  static const String _dashboardId = '2a63cc44-01f4-4c59-a620-7d280c01411d';

  /// تسجيل الدخول باستخدام اسم المستخدم وكلمة المرور
  static Future<LoginResult> login(String username, String password) async {
    try {
      debugPrint('🔐 بدء عملية تسجيل الدخول للمستخدم: $username');

      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/Contractor/token'),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json, text/plain, */*',
              'Origin': 'https://admin.ftth.iq',
              'Referer': 'https://admin.ftth.iq/auth/login',
              'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
              'x-kl-ajax-request': 'Ajax_Request',
              'x-user-role': '0',
            },
            body: 'username=$username&password=$password&grant_type=password',
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('🔐 استجابة تسجيل الدخول: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> tokenData = jsonDecode(response.body);

        final accessToken = tokenData['access_token'] as String?;
        final refreshToken = tokenData['refresh_token'] as String?;
        final expiresIn = tokenData['expires_in'] as int? ?? 3600;

        if (accessToken != null) {
          // حفظ التوكنات
          await _saveTokens(accessToken, refreshToken, expiresIn);

          // جلب معلومات المستخدم
          final userInfo = await _fetchUserInfo(accessToken);

          if (userInfo != null) {
            debugPrint('✅ تم تسجيل الدخول بنجاح');
            return LoginResult.success(accessToken, refreshToken, userInfo);
          } else {
            throw Exception('فشل في جلب معلومات المستخدم');
          }
        } else {
          throw Exception('لم يتم الحصول على توكن صالح');
        }
      } else {
        final errorBody = response.body;
        debugPrint('❌ فشل تسجيل الدخول: $errorBody');
        return LoginResult.failure(
            'فشل في تسجيل الدخول: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الدخول');

      // 🔒 تم إزالة بيانات الاختبار لأسباب أمنية
      // في حالة فشل الاتصال، يتم إرجاع رسالة خطأ فقط
      return LoginResult.failure(
          'خطأ في الاتصال بالخادم. تأكد من اتصالك بالإنترنت.');
    }
  }

  /// الحصول على Guest Token من Dashboard
  static Future<String?> fetchGuestToken({String? authToken}) async {
    try {
      debugPrint('🎫 جلب Guest Token...');
      debugPrint(
          '🎫 Auth Token provided: ${authToken != null ? "${authToken.substring(0, 50)}..." : "NULL"}');

      // الـ endpoint مع / في النهاية (كما يستخدمه المتصفح)
      final url = Uri.parse('$_dashboardBaseUrl/api/v1/security/guest_token/');
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'user-type': 'Partner',
        'origin': 'https://admin.ftth.iq',
        'referer': 'https://admin.ftth.iq/',
      };

      // إضافة توكن المصادقة إذا كان متوفراً
      if (authToken != null && authToken.isNotEmpty) {
        headers['authorization'] = 'Bearer $authToken';
        debugPrint('🎫 Using provided auth token');
      } else {
        final cachedToken = await getStoredAccessToken();
        if (cachedToken != null) {
          headers['authorization'] = 'Bearer $cachedToken';
          debugPrint('🎫 Using cached auth token');
        } else {
          debugPrint('🎫 ⚠️ NO AUTH TOKEN AVAILABLE!');
        }
      }

      // Body للطلب - يحتوي على معلومات المستخدم والـ resources
      final requestBody = jsonEncode({
        "resources": [
          {"type": "dashboard", "id": _dashboardId}
        ],
        "rls": [],
        "user": {
          "username": "viewer",
          "first_name": "viewer",
          "last_name": "viewer"
        }
      });

      debugPrint('🎫 إرسال طلب Guest Token مع body: $requestBody');

      final response = await http
          .post(
            url,
            headers: headers,
            body: requestBody,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('🎫 استجابة Guest Token: ${response.statusCode}');
      debugPrint('🎫 Response body: ${response.body}');

      // Capture session cookies from response
      _extractCookies(response.headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final token = jsonBody['token'] as String?;

        if (token != null && token.isNotEmpty) {
          // حفظ Guest Token
          await _saveGuestToken(token);
          _cachedGuestToken = token;

          // فك تشفير JWT لمعرفة محتواه
          try {
            final parts = token.split('.');
            if (parts.length == 3) {
              final payload = parts[1];
              // إضافة padding إذا لزم الأمر
              final normalizedPayload = base64Url.normalize(payload);
              final decoded = utf8.decode(base64Url.decode(normalizedPayload));
              debugPrint('🎫 JWT Payload: $decoded');
            }
          } catch (e) {
            debugPrint('⚠️ لم يتم فك تشفير JWT');
          }

          debugPrint('✅ تم الحصول على Guest Token بنجاح');
          return token;
        }
      }

      debugPrint('❌ فشل في الحصول على Guest Token: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب Guest Token');
      return null;
    }
  }

  /// الحصول على Guest Token بطريقة بديلة (مثل agents_details_page)
  static Future<String?> fetchGuestTokenSimple({String? authToken}) async {
    try {
      debugPrint('🎫 جلب Guest Token (طريقة بسيطة)...');

      // استخدام نفس الـ URL من agents_details_page (مع / في النهاية)
      final url = Uri.parse('$_dashboardBaseUrl/api/v1/security/guest_token/');
      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'user-type': 'Partner',
      };

      // إضافة توكن المصادقة إذا كان متوفراً
      if (authToken != null && authToken.isNotEmpty) {
        headers['authorization'] = 'Bearer $authToken';
      }

      // Body فارغ مثل agents_details_page
      final response = await http
          .post(
            url,
            headers: headers,
            body: '{}',
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('🎫 استجابة Guest Token (بسيط): ${response.statusCode}');
      debugPrint('🎫 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final token = jsonBody['token'] as String?;

        if (token != null && token.isNotEmpty) {
          await _saveGuestToken(token);
          _cachedGuestToken = token;
          debugPrint('✅ تم الحصول على Guest Token (بسيط) بنجاح');
          return token;
        }
      }

      debugPrint('❌ فشل في الحصول على Guest Token (بسيط): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب Guest Token (بسيط)');
      return null;
    }
  }

  /// Extract and store cookies from response headers
  static void _extractCookies(Map<String, String> headers) {
    final setCookie = headers['set-cookie'];
    if (setCookie != null) {
      debugPrint('🍪 Received cookies: $setCookie');
      // Parse cookies
      final cookieParts = setCookie.split(';');
      for (var part in cookieParts) {
        final trimmed = part.trim();
        if (trimmed.contains('=')) {
          final keyValue = trimmed.split('=');
          if (keyValue.length >= 2) {
            final key = keyValue[0].trim();
            final value = keyValue.sublist(1).join('=').trim();
            if (key == 'session' ||
                key == 'cf_clearance' ||
                key.contains('csrf')) {
              _cookies[key] = value;
              debugPrint('🍪 Stored cookie: $key');
            }
          }
        }
      }
      _sessionCookie = _buildCookieString();
      debugPrint('🍪 Session cookie string: $_sessionCookie');
    }
  }

  /// Build cookie string from stored cookies
  static String _buildCookieString() {
    return _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Get headers with cookies for dashboard API requests
  static Map<String, String> _getDashboardHeaders(String guestToken,
      {String? authToken}) {
    final refererUrl = '$_dashboardBaseUrl/embedded/$_dashboardId';
    final headers = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'x-guesttoken': guestToken,
      'user-type': 'Partner',
      'origin': _dashboardBaseUrl,
      'referer': refererUrl,
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'same-origin',
      'sec-fetch-site': 'same-origin',
      'user-agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36',
    };

    // إضافة Authorization header — مطلوب من APISIX gateway
    if (authToken != null && authToken.isNotEmpty) {
      headers['authorization'] = 'Bearer $authToken';
    }

    // أولوية: استخدام cookies من خدمة تجاوز Cloudflare
    final cfBypass = CloudflareBypassService.instance;
    if (cfBypass.hasValidCookies) {
      final cfCookies = cfBypass.cookieString;
      // دمج cookies المحلية مع cookies Cloudflare
      final allCookies = <String>[];
      if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
        allCookies.add(_sessionCookie!);
      }
      if (cfCookies.isNotEmpty) {
        allCookies.add(cfCookies);
      }
      if (allCookies.isNotEmpty) {
        headers['cookie'] = allCookies.join('; ');
        debugPrint(
            '🍪 استخدام cookies مدمجة: ${headers['cookie']?.substring(0, 50)}...');
      }
    } else {
      // استخدام cookies المحلية فقط
      if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
        headers['cookie'] = _sessionCookie!;
      }
    }

    return headers;
  }

  /// جلب أدوار المستخدم من Dashboard
  static Future<Map<String, dynamic>?> fetchUserRoles(
      {String? guestToken, String? authToken}) async {
    try {
      debugPrint('👤 جلب أدوار المستخدم...');

      final token =
          guestToken ?? _cachedGuestToken ?? await getStoredGuestToken();
      if (token == null) {
        debugPrint('❌ لا يوجد Guest Token متاح');
        return null;
      }

      // بدون / في النهاية لتجنب 404
      final url = Uri.parse('$_dashboardBaseUrl/api/v1/me/roles');
      final response = await http
          .get(
            url,
            headers: _getDashboardHeaders(token, authToken: authToken)
              ..remove('Content-Type'),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('👤 استجابة أدوار المستخدم: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final result = jsonBody['result'] as Map<String, dynamic>?;

        debugPrint('✅ تم جلب أدوار المستخدم بنجاح');
        return result;
      } else {
        debugPrint('❌ فشل في جلب أدوار المستخدم: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب أدوار المستخدم');
      return null;
    }
  }

  /// جلب بيانات Dashboard
  static Future<Map<String, dynamic>?> fetchDashboardData(String dashboardId,
      {String? guestToken, String? authToken}) async {
    try {
      debugPrint('📊 جلب بيانات Dashboard: $dashboardId');

      final token =
          guestToken ?? _cachedGuestToken ?? await getStoredGuestToken();
      if (token == null) {
        debugPrint('❌ لا يوجد Guest Token متاح');
        return null;
      }

      final url = Uri.parse('$_dashboardBaseUrl/api/v1/dashboard/$dashboardId');
      final response = await http
          .get(
            url,
            headers: _getDashboardHeaders(token, authToken: authToken)
              ..remove('Content-Type'),
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('📊 استجابة بيانات Dashboard: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final result = jsonBody['result'] as Map<String, dynamic>?;

        debugPrint('✅ تم جلب بيانات Dashboard بنجاح');
        return result;
      } else {
        debugPrint('❌ فشل في جلب بيانات Dashboard: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات Dashboard');
      return null;
    }
  }

  /// جلب بيانات Chart من Dashboard
  static Future<Map<String, dynamic>?> fetchChartData(
      int sliceId, int dashboardId,
      {String? guestToken,
      String? authToken,
      Map<String, dynamic>? requestPayload}) async {
    try {
      debugPrint(
          '📈 جلب بيانات Chart: slice_id=$sliceId, dashboard_id=$dashboardId');

      final token =
          guestToken ?? _cachedGuestToken ?? await getStoredGuestToken();
      if (token == null) {
        debugPrint('❌ لا يوجد Guest Token متاح');
        return null;
      }

      final url = Uri.parse('$_dashboardBaseUrl/api/v1/chart/data');

      final headers = _getDashboardHeaders(token, authToken: authToken);

      // Use provided payload or default
      final body = requestPayload != null
          ? jsonEncode(requestPayload)
          : jsonEncode({
              'form_data': {'slice_id': sliceId},
              'dashboard_id': dashboardId,
            });

      debugPrint('📈 Request headers: $headers');
      debugPrint('📈 Request body: $body');

      final response = await http
          .post(
            url,
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📈 استجابة بيانات Chart: ${response.statusCode}');
      debugPrint('📈 Response body (POST): ${response.body}');

      // Capture any new cookies
      _extractCookies(response.headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);

        // التحقق من وجود خطأ في الـ response (حتى مع status 200)
        if (jsonBody['error_msg'] != null) {
          debugPrint('❌ خطأ من Superset (POST): ${jsonBody['error_msg']}');
          return null;
        }

        final resultList = jsonBody['result'] as List?;

        if (resultList != null && resultList.isNotEmpty) {
          final result = resultList[0] as Map<String, dynamic>;
          debugPrint(
              '✅ تم جلب بيانات Chart بنجاح - rows: ${result['rowcount']}');
          return result;
        }
      } else {
        debugPrint('❌ فشل Chart - Status: ${response.statusCode}');
        debugPrint('❌ Response: ${response.body}');
      }

      debugPrint('❌ فشل في جلب بيانات Chart: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات Chart');
      return null;
    }
  }

  /// جلب بيانات Chart — خطوتان:
  /// 1. GET /api/v1/chart/{id} → جلب metadata + query_context
  /// 2. POST /api/v1/chart/data → إرسال query_context لجلب البيانات
  static Future<Map<String, dynamic>?> fetchChartDataGet(
      int sliceId, int dashboardId,
      {String? guestToken, String? authToken}) async {
    try {
      final token =
          guestToken ?? _cachedGuestToken ?? await getStoredGuestToken();
      if (token == null) {
        debugPrint('❌ Slice $sliceId: لا يوجد Guest Token');
        return null;
      }

      // GET مباشرة مع form_data في URL (نفس طريقة fetch_server_data_page)
      final formData = Uri.encodeComponent('{"slice_id":$sliceId}');
      final url = Uri.parse(
          '$_dashboardBaseUrl/api/v1/chart/data?form_data=$formData&dashboard_id=$dashboardId');

      // Headers بسيطة بدون Content-Type (طلب GET)
      final headers = <String, String>{
        'x-guesttoken': token,
        'Accept': 'application/json',
        'origin': _dashboardBaseUrl,
        'referer': '$_dashboardBaseUrl/embedded/$_dashboardId',
      };
      if (authToken != null && authToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      debugPrint('📈 GET chart/data (slice $sliceId)...');

      final resp = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      debugPrint('📈 Slice $sliceId → Status: ${resp.statusCode}');

      // Capture cookies
      _extractCookies(resp.headers);

      if (resp.statusCode == 200) {
        final jsonBody = json.decode(resp.body);

        if (jsonBody['error_msg'] != null) {
          debugPrint('❌ Slice $sliceId خطأ: ${jsonBody['error_msg']}');
          return null;
        }

        final resultList = jsonBody['result'] as List?;
        if (resultList != null && resultList.isNotEmpty) {
          final result = resultList[0] as Map<String, dynamic>;
          debugPrint('✅ Slice $sliceId → ${result['rowcount']} rows');
          return result;
        } else {
          debugPrint('❌ Slice $sliceId → result فارغ');
        }
      } else {
        debugPrint('❌ Slice $sliceId → ${resp.statusCode}');
        debugPrint('❌ Body: ${resp.body.substring(0, (resp.body.length).clamp(0, 300))}');
      }

      return null;
    } catch (e) {
      debugPrint('❌ Slice $sliceId → خطأ: $e');
      return null;
    }
  }

  /// جلب بيانات عدة slices من Superset بالتوازي
  static Future<Map<int, Map<String, dynamic>?>> fetchMultipleSlices({
    required List<int> sliceIds,
    required String guestToken,
    String? authToken,
    int dashboardId = 7,
  }) async {
    final results = <int, Map<String, dynamic>?>{};
    await Future.wait(sliceIds.map((id) async {
      results[id] = await fetchChartDataGet(id, dashboardId,
          guestToken: guestToken, authToken: authToken);
    }));
    return results;
  }

  /// Fetch chart data with full request payload (from browser)
  static Future<Map<String, dynamic>?> fetchChartDataWithPayload(
      Map<String, dynamic> payload,
      {String? guestToken,
      String? authToken}) async {
    try {
      debugPrint('📈 جلب بيانات Chart مع payload كامل');

      final token =
          guestToken ?? _cachedGuestToken ?? await getStoredGuestToken();
      if (token == null) {
        debugPrint('❌ لا يوجد Guest Token متاح');
        return null;
      }

      final url = Uri.parse('$_dashboardBaseUrl/api/v1/chart/data');

      final headers = _getDashboardHeaders(token, authToken: authToken);
      final body = jsonEncode(payload);

      debugPrint('📈 Sending chart request with full payload');

      final response = await http
          .post(
            url,
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📈 استجابة بيانات Chart: ${response.statusCode}');

      // Capture any new cookies
      _extractCookies(response.headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final resultList = jsonBody['result'] as List?;

        if (resultList != null && resultList.isNotEmpty) {
          final result = resultList[0] as Map<String, dynamic>;
          debugPrint(
              '✅ تم جلب بيانات Chart بنجاح - rows: ${result['rowcount']}');
          return result;
        }
      } else {
        debugPrint('❌ فشل Chart - Status: ${response.statusCode}');
        debugPrint('❌ Response body: ${response.body}');
      }

      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات Chart');
      return null;
    }
  }

  /// جلب بيانات Zones Stats (Chart 67) - يحتوي على Active/Inactive/Expired لكل Zone
  /// هذا يستخدم نفس الطريقة التي يستخدمها المتصفح (POST مع datasource و queries)
  static Future<Map<String, dynamic>?> fetchZonesStats({
    String? guestToken,
    String? authToken,
  }) async {
    try {
      debugPrint('📊 جلب بيانات Zones Stats (Chart 67)...');

      final token =
          guestToken ?? _cachedGuestToken ?? await getStoredGuestToken();
      if (token == null) {
        debugPrint('❌ لا يوجد Guest Token متاح');
        return null;
      }

      // URL مع query parameters مثل المتصفح تماماً
      final url = Uri.parse(
          '$_dashboardBaseUrl/api/v1/chart/data?form_data=%7B%22slice_id%22%3A67%7D&dashboard_id=7');

      final headers = _getDashboardHeaders(token, authToken: authToken);

      // Payload مطابق لما يرسله المتصفح للـ Zones Stats (Chart 67)
      // datasource id=33 هو "Zones stats with Default"
      final payload = {
        "datasource": {"id": 33, "type": "table"},
        "force": false,
        "queries": [
          {
            "filters": [
              {
                "col": "Zone",
                "op": "NOT IN",
                "val": ["Default"]
              }
            ],
            "extras": {"time_grain_sqla": "P1D", "having": "", "where": ""},
            "applied_time_extras": {},
            "columns": ["Zone", "Active", "Inactive", "Expired"],
            "orderby": [],
            "annotation_layers": [],
            "row_limit": 1000,
            "series_limit": 0,
            "order_desc": true,
            "url_params": {},
            "custom_params": {},
            "custom_form_data": {},
            "post_processing": []
          }
        ],
        "form_data": {
          "viz_type": "table",
          "datasource": "33__table",
          "slice_id": 67,
          "url_params": {}
        },
        "result_format": "json",
        "result_type": "full"
      };

      final body = jsonEncode(payload);

      debugPrint('📊 Sending Zones Stats request to: $url');
      debugPrint('📊 Headers: ${headers.keys.toList()}');
      debugPrint('📊 Guest Token: ${token.substring(0, 50)}...');

      final response = await http
          .post(
            url,
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📊 استجابة Zones Stats: ${response.statusCode}');
      debugPrint(
          '📊 Response body preview: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

      // Capture any new cookies
      _extractCookies(response.headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);

        // التحقق من وجود خطأ في الاستجابة
        if (jsonBody['error_msg'] != null) {
          debugPrint('❌ خطأ من Superset: ${jsonBody['error_msg']}');
          debugPrint('❌ Full response: ${response.body}');
          return null;
        }

        final resultList = jsonBody['result'] as List?;

        if (resultList != null && resultList.isNotEmpty) {
          final result = resultList[0] as Map<String, dynamic>;
          debugPrint(
              '✅ تم جلب Zones Stats بنجاح - rows: ${result['rowcount']}');
          return result;
        }
      } else {
        debugPrint('❌ فشل Zones Stats - Status: ${response.statusCode}');
        debugPrint('❌ Response: ${response.body}');
      }

      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب Zones Stats');
      return null;
    }
  }

  /// جلب قائمة الـ Zones المتعلقة بالمستخدم (My Related Zones) - Chart 52
  /// هذا يستخدم datasource id=26 مع filter بـ partner
  /// يرجع: ZoneType, Zone, ZoneContractor, MainZoneContractor
  static Future<Map<String, dynamic>?> fetchMyRelatedZones({
    String? guestToken,
    String? authToken,
    String? partnerName,
  }) async {
    try {
      debugPrint('📍 جلب قائمة My Related Zones (Chart 52)...');

      final token =
          guestToken ?? _cachedGuestToken ?? await getStoredGuestToken();
      if (token == null) {
        debugPrint('❌ لا يوجد Guest Token متاح');
        return null;
      }

      // URL مع query parameters مثل المتصفح
      final url = Uri.parse(
          '$_dashboardBaseUrl/api/v1/chart/data?form_data=%7B%22slice_id%22%3A52%7D&dashboard_id=7');

      final headers = _getDashboardHeaders(token, authToken: authToken);

      // Payload مطابق لما يرسله المتصفح - datasource id=26 هو "My Related Zones"
      final Map<String, dynamic> payload = {
        "datasource": {"id": 26, "type": "table"},
        "force": false,
        "queries": [
          {
            "filters": partnerName != null
                ? [
                    {
                      "col": "partner",
                      "op": "IN",
                      "val": [partnerName]
                    }
                  ]
                : [],
            "extras": {"time_grain_sqla": "P1D", "having": "", "where": ""},
            "applied_time_extras": {},
            "columns": [
              "ZoneType",
              "Zone",
              "ZoneContractor",
              "MainZoneContractor"
            ],
            "orderby": [],
            "annotation_layers": [],
            "row_limit": 1000,
            "series_limit": 0,
            "order_desc": true,
            "url_params": {},
            "custom_params": {},
            "custom_form_data": {},
            "post_processing": []
          }
        ],
        "form_data": {
          "viz_type": "table",
          "datasource": "26__table",
          "slice_id": 52,
          "url_params": {}
        },
        "result_format": "json",
        "result_type": "full"
      };

      final body = jsonEncode(payload);

      debugPrint('📍 Sending My Related Zones request to: $url');

      final response = await http
          .post(
            url,
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📍 استجابة My Related Zones: ${response.statusCode}');
      debugPrint(
          '📍 Response body preview: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');

      _extractCookies(response.headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);

        if (jsonBody['error_msg'] != null) {
          debugPrint('❌ خطأ من Superset: ${jsonBody['error_msg']}');
          debugPrint('❌ Full response: ${response.body}');
          return null;
        }

        final resultList = jsonBody['result'] as List?;

        if (resultList != null && resultList.isNotEmpty) {
          final result = resultList[0] as Map<String, dynamic>;
          debugPrint(
              '✅ تم جلب My Related Zones بنجاح - rows: ${result['rowcount']}');
          return result;
        }
      } else {
        debugPrint('❌ فشل My Related Zones - Status: ${response.statusCode}');
        debugPrint('❌ Response: ${response.body}');
      }

      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب My Related Zones');
      return null;
    }
  }

  /// جلب بيانات الـ Zones من admin.ftth.iq API (بديل عن Superset)
  /// هذا يستخدم API مباشر بدلاً من Dashboard
  static Future<Map<String, dynamic>?> fetchZonesFromAdmin({
    String? authToken,
  }) async {
    try {
      debugPrint('🌍 جلب بيانات Zones من Admin API...');

      final token = authToken ?? await getStoredAccessToken();
      if (token == null) {
        debugPrint('❌ لا يوجد Auth Token متاح');
        return null;
      }

      final url = Uri.parse(
          'https://admin.ftth.iq/api/locations/zones?pageSize=1000&pageNumber=1');

      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      };

      debugPrint('🌍 Fetching zones from: $url');

      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      debugPrint('🌍 Admin Zones Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // تحويل البيانات لنفس الشكل المتوقع من Superset
        final List<Map<String, dynamic>> zonesData = [];

        // استخراج الـ zones من الاستجابة
        List<dynamic>? items;
        if (data is Map<String, dynamic>) {
          if (data['items'] is List) {
            items = data['items'] as List;
          } else if (data['model'] is Map && data['model']['items'] is List) {
            items = data['model']['items'] as List;
          } else if (data['zones'] is List) {
            items = data['zones'] as List;
          }
        }

        if (items != null) {
          for (final zone in items) {
            if (zone is Map<String, dynamic>) {
              final zoneName = zone['name'] ?? zone['zoneName'] ?? 'غير معروف';
              zonesData.add({
                'Zone': zoneName,
                'ZoneType': zone['type'] ?? zone['zoneType'] ?? '',
                'Active': 0, // سيتم حسابها لاحقاً
                'Inactive': 0,
                'Expired': 0,
              });
            }
          }
        }

        debugPrint('🌍 تم جلب ${zonesData.length} zone من Admin API');

        // إرجاع بنفس الشكل المتوقع
        return {
          'data': zonesData,
          'colnames': ['Zone', 'ZoneType', 'Active', 'Inactive', 'Expired'],
          'rowcount': zonesData.length,
        };
      } else {
        debugPrint('❌ فشل Admin Zones - Status: ${response.statusCode}');
        debugPrint('❌ Response: ${response.body}');
      }

      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب Zones من Admin');
      return null;
    }
  }

  /// جلب بيانات لوج Dashboard
  static Future<Map<String, dynamic>?> fetchDashboardLogData(int dashboardId,
      {String? guestToken}) async {
    try {
      debugPrint('📋 جلب بيانات لوج Dashboard: $dashboardId');

      final token =
          guestToken ?? _cachedGuestToken ?? await getStoredGuestToken();
      if (token == null) {
        debugPrint('❌ لا يوجد Guest Token متاح');
        return null;
      }

      final url = Uri.parse(
          '$_dashboardBaseUrl/superset/log/?explode=events&dashboard_id=$dashboardId');
      final request = http.MultipartRequest('POST', url);
      request.headers['x-guesttoken'] = token;
      request.headers['Accept'] = 'application/json';

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('📋 استجابة بيانات لوج Dashboard: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        debugPrint('✅ تم جلب بيانات لوج Dashboard بنجاح');
        return jsonBody;
      } else {
        debugPrint('❌ فشل في جلب بيانات لوج Dashboard: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب بيانات لوج Dashboard');
      return null;
    }
  }

  /// تجديد Access Token
  static Future<String?> refreshAccessToken() async {
    try {
      debugPrint('🔄 تجديد Access Token...');

      final refreshToken = await getStoredRefreshToken();
      if (refreshToken == null) {
        debugPrint('❌ لا يوجد Refresh Token متاح');
        return null;
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'refresh_token': refreshToken,
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('🔄 استجابة تجديد Token: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> tokenData = jsonDecode(response.body);
        final newAccessToken = tokenData['access_token'] as String?;
        final newRefreshToken = tokenData['refresh_token'] as String?;
        final expiresIn = tokenData['expires_in'] as int? ?? 3600;

        if (newAccessToken != null) {
          await _saveTokens(newAccessToken, newRefreshToken, expiresIn);
          debugPrint('✅ تم تجديد Access Token بنجاح');
          return newAccessToken;
        }
      }

      debugPrint('❌ فشل في تجديد Access Token');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في تجديد Access Token');
      return null;
    }
  }

  /// التحقق من صحة المصادقة
  static Future<bool> isAuthenticated() async {
    final accessToken = await getStoredAccessToken();
    final expiry = await _getTokenExpiry();

    if (accessToken == null) {
      return false;
    }

    // التحقق من انتهاء صلاحية التوكن
    if (expiry != null && DateTime.now().isAfter(expiry)) {
      debugPrint('⏰ انتهت صلاحية التوكن، محاولة التجديد...');
      final newToken = await refreshAccessToken();
      return newToken != null;
    }

    return true;
  }

  /// الحصول على رابط Dashboard مع التوكن
  static Future<String> getDashboardUrl(String dashboardId) async {
    final guestToken = await getStoredGuestToken();
    const baseUrl = 'https://dashboard.ftth.iq/embedded/';

    if (guestToken != null) {
      return '$baseUrl$dashboardId?token=$guestToken';
    }

    return '$baseUrl$dashboardId';
  }

  /// تسجيل الخروج
  static Future<void> logout() async {
    try {
      debugPrint('🚪 تسجيل الخروج...');

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessTokenKey);
      await prefs.remove(_refreshTokenKey);
      await prefs.remove(_guestTokenKey);
      await prefs.remove(_userInfoKey);
      await prefs.remove(_tokenExpiryKey);

      // مسح التخزين المؤقت
      _cachedAccessToken = null;
      _cachedGuestToken = null;
      _cachedRefreshToken = null;
      _cachedUserInfo = null;
      _tokenExpiry = null;

      debugPrint('✅ تم تسجيل الخروج بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الخروج');
    }
  }

  // ===== دالات الحصول على البيانات المحفوظة =====

  static Future<String?> getStoredAccessToken() async {
    if (_cachedAccessToken != null) return _cachedAccessToken;

    final prefs = await SharedPreferences.getInstance();
    _cachedAccessToken = prefs.getString(_accessTokenKey);
    return _cachedAccessToken;
  }

  static Future<String?> getStoredRefreshToken() async {
    if (_cachedRefreshToken != null) return _cachedRefreshToken;

    final prefs = await SharedPreferences.getInstance();
    _cachedRefreshToken = prefs.getString(_refreshTokenKey);
    return _cachedRefreshToken;
  }

  static Future<String?> getStoredGuestToken() async {
    if (_cachedGuestToken != null) return _cachedGuestToken;

    final prefs = await SharedPreferences.getInstance();
    _cachedGuestToken = prefs.getString(_guestTokenKey);
    return _cachedGuestToken;
  }

  static Future<UserInfo?> getStoredUserInfo() async {
    if (_cachedUserInfo != null) return _cachedUserInfo;

    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoJson = prefs.getString(_userInfoKey);

      if (userInfoJson != null) {
        final userInfoMap = jsonDecode(userInfoJson) as Map<String, dynamic>;
        _cachedUserInfo = UserInfo.fromJson(userInfoMap);
        return _cachedUserInfo;
      }
    } catch (e) {
      debugPrint('❌ خطأ في قراءة معلومات المستخدم');
    }

    return null;
  }

  // ===== دالات الحفظ الداخلية =====

  static Future<void> _saveTokens(
      String accessToken, String? refreshToken, int expiresIn) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_accessTokenKey, accessToken);
      if (refreshToken != null) {
        await prefs.setString(_refreshTokenKey, refreshToken);
      }

      // حفظ وقت انتهاء الصلاحية
      final expiry = DateTime.now().add(Duration(seconds: expiresIn));
      await prefs.setString(_tokenExpiryKey, expiry.toIso8601String());

      // تحديث التخزين المؤقت
      _cachedAccessToken = accessToken;
      _cachedRefreshToken = refreshToken;
      _tokenExpiry = expiry;

      debugPrint('💾 تم حفظ التوكنات بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ التوكنات');
    }
  }

  static Future<void> _saveGuestToken(String guestToken) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_guestTokenKey, guestToken);
      _cachedGuestToken = guestToken;
      debugPrint('💾 تم حفظ Guest Token بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ Guest Token');
    }
  }

  static Future<void> _saveUserInfo(UserInfo userInfo) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoJson = jsonEncode(userInfo.toJson());
      await prefs.setString(_userInfoKey, userInfoJson);
      _cachedUserInfo = userInfo;
      debugPrint('💾 تم حفظ معلومات المستخدم بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ معلومات المستخدم');
    }
  }

  static Future<UserInfo?> _fetchUserInfo(String accessToken) async {
    try {
      // محاولة جلب معلومات المستخدم من API
      final response = await http.get(
        Uri.parse('$_baseUrl/user/me'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final userData = jsonDecode(response.body) as Map<String, dynamic>;
        final userInfo = UserInfo.fromJson(userData);
        await _saveUserInfo(userInfo);
        return userInfo;
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب معلومات المستخدم');
    }

    // إرجاع بيانات افتراضية في حالة الفشل
    final defaultUserInfo = UserInfo(
      username: 'sa',
      accountId: '2261175',
      roles: ['SuperAdminMember', 'ContractorMember'],
      groups: ['/Team_Contractor_2261175_Members'],
      email: 'sa@ftth.iq',
    );

    await _saveUserInfo(defaultUserInfo);
    return defaultUserInfo;
  }

  static Future<DateTime?> _getTokenExpiry() async {
    if (_tokenExpiry != null) return _tokenExpiry;

    try {
      final prefs = await SharedPreferences.getInstance();
      final expiryString = prefs.getString(_tokenExpiryKey);

      if (expiryString != null) {
        _tokenExpiry = DateTime.parse(expiryString);
        return _tokenExpiry;
      }
    } catch (e) {
      debugPrint('❌ خطأ في قراءة وقت انتهاء التوكن');
    }

    return null;
  }
}

// ===== نماذج البيانات =====

/// نموذج بيانات المستخدم
class UserInfo {
  final String username;
  final String accountId;
  final List<String> roles;
  final List<String> groups;
  final String? email;
  final DateTime createdAt;

  UserInfo({
    required this.username,
    required this.accountId,
    required this.roles,
    required this.groups,
    this.email,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      username: json['username']?.toString() ?? '',
      accountId:
          json['accountId']?.toString() ?? json['account_id']?.toString() ?? '',
      roles: List<String>.from(json['roles'] ?? []),
      groups: List<String>.from(json['groups'] ?? []),
      email: json['email']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'accountId': accountId,
      'roles': roles,
      'groups': groups,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'UserInfo(username: $username, accountId: $accountId, roles: $roles)';
  }
}

/// نموذج نتيجة تسجيل الدخول
class LoginResult {
  final bool isSuccess;
  final String? accessToken;
  final String? refreshToken;
  final UserInfo? userInfo;
  final String? errorMessage;

  LoginResult._({
    required this.isSuccess,
    this.accessToken,
    this.refreshToken,
    this.userInfo,
    this.errorMessage,
  });

  factory LoginResult.success(
      String accessToken, String? refreshToken, UserInfo userInfo) {
    return LoginResult._(
      isSuccess: true,
      accessToken: accessToken,
      refreshToken: refreshToken,
      userInfo: userInfo,
    );
  }

  factory LoginResult.failure(String errorMessage) {
    return LoginResult._(
      isSuccess: false,
      errorMessage: errorMessage,
    );
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'LoginResult.success(user: ${userInfo?.username})';
    } else {
      return 'LoginResult.failure(error: $errorMessage)';
    }
  }
}
