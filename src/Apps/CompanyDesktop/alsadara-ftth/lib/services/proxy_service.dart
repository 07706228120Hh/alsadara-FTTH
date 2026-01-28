import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// خدمة للاتصال المباشر بـ Dashboard (بدون Proxy)
class ProxyService {
  // عنوان Dashboard الرئيسي
  static const String _dashboardBaseUrl = 'https://dashboard.ftth.iq';

  // Dashboard ID الافتراضي
  static const String _defaultDashboardId =
      '2a63cc44-01f4-4c59-a620-7d280c01411d';

  /// جلب Guest Token مباشرة من Dashboard
  static Future<String?> getGuestToken({String? authToken}) async {
    try {
      debugPrint('🔑 جلب Guest Token مباشرة من Dashboard...');

      final url = Uri.parse('$_dashboardBaseUrl/api/v1/security/guest_token/');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Origin': _dashboardBaseUrl,
        'Referer': '$_dashboardBaseUrl/superset/dashboard/7',
      };

      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      final body = jsonEncode({
        'resources': [
          {
            'type': 'dashboard',
            'id': _defaultDashboardId,
          }
        ],
        'rls': [],
        'user': {
          'username': 'guest',
          'first_name': 'Guest',
          'last_name': 'User',
        }
      });

      final response = await http
          .post(
            url,
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 استجابة Dashboard: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['token'] != null) {
          final token = data['token'] as String;
          debugPrint('✅ تم الحصول على Guest Token مباشرة بنجاح');
          debugPrint('Token: ${token.substring(0, 20)}...');
          return token;
        }
      }

      debugPrint('❌ فشل في الحصول على Guest Token: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في الاتصال بـ Dashboard: $e');
      return null;
    }
  }

  /// جلب بيانات Chart مباشرة من Dashboard
  static Future<Map<String, dynamic>?> fetchChartData({
    required int sliceId,
    required int dashboardId,
    String? guestToken,
    String? authToken,
  }) async {
    try {
      debugPrint(
          '📊 جلب Chart Data مباشرة: slice_id=$sliceId, dashboard_id=$dashboardId');

      final url = Uri.parse('$_dashboardBaseUrl/api/v1/chart/data');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'Origin': _dashboardBaseUrl,
        'Referer': '$_dashboardBaseUrl/superset/dashboard/$dashboardId',
      };

      if (guestToken != null) {
        headers['X-GuestToken'] = guestToken;
      } else if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      final formData = {
        'slice_id': sliceId,
        'form_data': jsonEncode({
          'slice_id': sliceId,
        }),
      };

      final response = await http
          .post(
            url,
            headers: headers,
            body: jsonEncode(formData),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 استجابة Chart Data: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        debugPrint('✅ تم جلب Chart Data مباشرة بنجاح');

        // استخراج البيانات من response
        if (data['result'] is List && (data['result'] as List).isNotEmpty) {
          return data['result'][0] as Map<String, dynamic>;
        }

        return data as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        debugPrint('🔒 يتطلب Guest Token - استخدم getGuestToken() أولاً');
      }

      debugPrint('❌ فشل في جلب Chart Data: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب Chart Data: $e');
      return null;
    }
  }

  /// جلب Dashboard Data مباشرة
  static Future<Map<String, dynamic>?> fetchDashboardData({
    required String dashboardId,
    String? guestToken,
    String? authToken,
  }) async {
    try {
      debugPrint('📊 جلب Dashboard Data مباشرة: $dashboardId');

      final url = Uri.parse('$_dashboardBaseUrl/api/v1/dashboard/$dashboardId');

      final headers = <String, String>{
        'Accept': 'application/json',
        'Origin': _dashboardBaseUrl,
        'Referer': '$_dashboardBaseUrl/superset/dashboard/$dashboardId',
      };

      if (guestToken != null) {
        headers['X-GuestToken'] = guestToken;
      } else if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 استجابة Dashboard Data: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ تم جلب Dashboard Data مباشرة بنجاح');
        return data as Map<String, dynamic>;
      }

      debugPrint('❌ فشل في جلب Dashboard Data: ${response.body}');
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في جلب Dashboard Data: $e');
      return null;
    }
  }

  /// فحص اتصال Dashboard مباشرة
  static Future<bool> checkProxyHealth() async {
    try {
      debugPrint('🏥 فحص اتصال Dashboard...');

      final url = Uri.parse('$_dashboardBaseUrl/health');

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 404) {
        // 404 طبيعي إذا لم يكن هناك endpoint /health
        debugPrint('✅ Dashboard متاح ويعمل');
        return true;
      }

      debugPrint('⚠️ Dashboard يستجيب بشكل غير متوقع: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('❌ لا يمكن الاتصال بـ Dashboard: $e');
      return false;
    }
  }

  /// جلب zones stats من خلال Proxy
  static Future<Map<String, dynamic>?> fetchZonesStats({
    String? guestToken,
    String? authToken,
  }) async {
    // slice_id=67 هو Zones Stats في dashboard_id=7
    return await fetchChartData(
      sliceId: 67,
      dashboardId: 7,
      guestToken: guestToken,
      authToken: authToken,
    );
  }

  /// جلب My Related Zones من خلال Proxy
  static Future<Map<String, dynamic>?> fetchMyRelatedZones({
    String? guestToken,
    String? authToken,
  }) async {
    // slice_id=52 هو My Related Zones في dashboard_id=7
    return await fetchChartData(
      sliceId: 52,
      dashboardId: 7,
      guestToken: guestToken,
      authToken: authToken,
    );
  }
}
