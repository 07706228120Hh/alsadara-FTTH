/// اسم الصفحة: اختبار الويب فيو المستقل
/// وصف الصفحة: صفحة اختبار عرض المحتوى من الويب بشكل مستقل
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// صفحة تست بسيطة لاختبار WebView مع رابط مباشر
class TestWebViewPage extends StatefulWidget {
  const TestWebViewPage({super.key});

  @override
  State<TestWebViewPage> createState() => _TestWebViewPageState();
}

class _TestWebViewPageState extends State<TestWebViewPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _guestToken;
  String? _bearerToken;
  String? _selectedDashboardId;
  List<Map<String, dynamic>> _availableDashboards = [];

  @override
  void initState() {
    super.initState();
    _initializeWithNewToken(); // بدء العملية الكاملة
  }

  /// العملية الكاملة: جلب قائمة التقارير، ثم Guest Token، ثم WebView
  Future<void> _initializeWithNewToken() async {
    try {
      // استخدام Bearer Token الجديد
      _bearerToken =
          'eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI5Nzc4UnE5VVRxT3o5S3FXaE1nUmY2OVlBbWtjdGtaV3BFX1BOTDNKVzRnIn0.eyJleHAiOjE3NTA4OTkwODYsImlhdCI6MTc1MDg5NTQ4NiwianRpIjoiY2E1OTZkYjMtMjkxOC00NWEzLTk1OGEtMWMyMmExZDU1ZDcxIiwiaXNzIjoiaHR0cHM6Ly9zc28uZnR0aC5pcS9hdXRoL3JlYWxtcy9QYXJ0bmVycyIsImF1ZCI6ImFjY291bnQiLCJzdWIiOiJiZDg0ZjljOC1mN2Y2LTRiYjctYTFhOC0wNjI3ZjM1NTkyODkiLCJ0eXAiOiJCZWFyZXIiLCJhenAiOiJlYXJ0aGxpbmstcG9ydGFscyIsInNlc3Npb25fc3RhdGUiOiJhOWY1NjVjNS1jMWI2LTRlNzMtOTUwNi04NTM1MTk0NjU2ZDMiLCJhbGxvd2VkLW9yaWdpbnMiOlsiaHR0cHM6Ly9hZG1pbi5mdHRoLmlxIl0sInJlYWxtX2FjY2VzcyI6eyJyb2xlcyI6WyJTdXBlckFkbWluTWVtYmVyIiwiZGVmYXVsdC1yb2xlcy1wYXJ0bmVycyIsIkNvbnRyYWN0b3JNZW1iZXIiLCJvZmZsaW5lX2FjY2VzcyIsInVtYV9hdXRob3JizemF0aW9uIl19LCJyZXNvdXJjZV9hY2Nlc3MiOnsiYWNjb3VudCI6eyJyb2xlcyI6WyJtYW5hZ2UtYWNjb3VudCIsIm1hbmFnZS1hY2NvdW50LWxpbmtzIiwidmlldy1wcm9maWxlIl19fSwic2NvcGUiOiJwcm9maWxlIGVtYWlsIiwic2lkIjoiYTlmNTY1YzUtYzFiNi00ZTczLTk1MDYtODUzNTE5NDY1NmQzIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJBY2NvdW50SWQiOiIyMjYxMTc1IiwiR3JvdXBzIjpbIi9UZWFtX0NvbnRyYWN0b3JfMjI2MTE3NV9NZW1iZXJzIl0sInByZWZlcnJlZF91c2VybmFtZSI6ImhhaSJ9.h01pVBirT-254oK5NN6kX4R0m4k0o8tppb95dFjfGzhyU2Wj1zzD78OyHKtwVPSytbe-Y-KbHMQVEcN1MV3Qn-PsvXThkvFDZdXim5hF_0hiNz9qKOSLVUBOewvLSRgLM2cBLUhA6V2Cm0ceCXzTHopohfEQXfs3baKoVAck_M48eaxoH664YxozRRjldAuxG_N271PXdw5m1NYjGTsqrOyaw2MDl8PESeF9PkNfLsxZn3aPNCC2ZYVfVGUvi1ayz3fuOC_ugUzzYx5Bc_RhSwgpOViVSOvTDoyOm0PvCeyPxTwGH8EgjsZwOsRNqRVYN6VAIokz3mgTrz1RdYJXiQ';

      debugPrint('🚀 Starting complete workflow with new Bearer Token...');

      // الخطوة 1: جلب قائمة التقارير المتاحة
      await _fetchAvailableDashboards();

      // الخطوة 2: العثور على معرف "إحصائيات المستخدمين"
      final userStatsId = _findUserStatsDashboardId();

      if (userStatsId != null) {
        _selectedDashboardId = userStatsId;
        debugPrint('✅ Found User Statistics dashboard ID: $userStatsId');

        // الخطوة 3: جلب Guest Token لهذا التقرير المحدد
        await _fetchGuestTokenForDashboard(userStatsId);
      } else {
        debugPrint('❌ User Statistics dashboard not found');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم العثور على تقرير "إحصائيات المستخدمين"'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error in complete workflow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في سير العمل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// جلب قائمة التقارير المتاحة
  Future<void> _fetchAvailableDashboards() async {
    try {
      debugPrint('📊 Fetching available dashboards...');

      final headers = {
        'accept': 'application/json, text/plain, */*',
        'authorization': 'Bearer $_bearerToken',
        'origin': 'https://admin.ftth.iq',
        'referer': 'https://admin.ftth.iq/',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        'user-type': 'Partner',
      };

      final response = await http.get(
        Uri.parse('https://dashboard.ftth.iq/superset/dashboard/report/list'),
        headers: headers,
      );

      debugPrint('Dashboard list response: ${response.statusCode}');
      debugPrint('Dashboard list body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final items = jsonBody['items'] as List?;

        if (items != null) {
          _availableDashboards = items.cast<Map<String, dynamic>>();
          debugPrint('✅ Found ${_availableDashboards.length} dashboards:');
          for (final dashboard in _availableDashboards) {
            debugPrint(
                '  - ${dashboard['arabicName']} (${dashboard['englishName']}) - ID: ${dashboard['id']}');
          }
        }
      } else {
        debugPrint('❌ Failed to fetch dashboards: ${response.statusCode}');
        throw Exception('Failed to fetch dashboards: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching dashboards: $e');
      rethrow;
    }
  }

  /// العثور على معرف تقرير "إحصائيات المستخدمين"
  String? _findUserStatsDashboardId() {
    debugPrint('📊 Available dashboards:');
    for (final dashboard in _availableDashboards) {
      final arabicName = dashboard['arabicName'] as String?;
      final englishName = dashboard['englishName'] as String?;
      final id = dashboard['id'] as String?;

      debugPrint('  - Arabic: $arabicName, English: $englishName, ID: $id');

      if (arabicName == 'إحصائيات المستخدمين' ||
          englishName == 'User statistics') {
        debugPrint('✅ Found User Statistics dashboard: $id');
        return id;
      }
    }

    debugPrint('❌ User Statistics dashboard not found');
    return null;
  }

  /// جلب Guest Token لتقرير محدد
  Future<void> _fetchGuestTokenForDashboard(String dashboardId) async {
    try {
      debugPrint('🔑 Fetching guest token for dashboard: $dashboardId');

      // محاكاة Headers بالضبط كما في الطلب الناجح
      final headers = {
        'accept': 'application/json, text/plain, */*',
        'authorization': 'Bearer $_bearerToken',
        'content-type': 'application/json',
        'origin': 'https://admin.ftth.iq',
        'referer': 'https://admin.ftth.iq/',
        'sec-ch-ua':
            '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        'user-type': 'Partner',
      };

      // إرسال طلب Guest Token مع معرف التقرير في Body - مطابقة البيانات الصحيحة
      final body = json.encode({
        'resources': [
          {
            'type': 'dashboard',
            'id': dashboardId,
          }
        ],
        'rls': [], // rls وليس rls_rules
        'user': {
          'username': 'viewer',
          'first_name': 'viewer',
          'last_name': 'viewer',
        }
      });

      debugPrint('Request body: $body');

      final response = await http.post(
        Uri.parse('https://dashboard.ftth.iq/api/v1/security/guest_token/'),
        headers: headers,
        body: body,
      );

      debugPrint('Guest token response: ${response.statusCode}');
      debugPrint('Guest token body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        _guestToken = jsonBody['token'];
        debugPrint(
            '✅ Guest token received for User Statistics: ${_guestToken?.substring(0, 30)}...');

        if (mounted) {
          setState(() {});
          _initializeWebView();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('تم الحصول على Guest Token لإحصائيات المستخدمين! 🎉'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        debugPrint('❌ Failed to get guest token: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل في جلب Guest Token: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching guest token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء جلب Guest Token: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// جلب التوكنات المطلوبة أولاً ثم تهيئة WebView
  Future<void> _fetchTokensAndInitialize() async {
    try {
      // استخدام Bearer Token المعطى من المستخدم
      _bearerToken =
          'eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI5Nzc4UnE5VVRxT3o5S3FXaE1nUmY2OVlBbWtjdGtaV3BFX1BOTDNKVzRnIn0.eyJleHAiOjE3NTA4OTUxOTcsImlhdCI6MTc1MDg5MTU5NywianRpIjoiOWM0YTBhOWUtOWExMy00YjFkLWFmZmEtY2E4NDg3MTM3NzRkIiwiaXNzIjoiaHR0cHM6Ly9zc28uZnR0aC5pcS9hdXRoL3JlYWxtcy9QYXJ0bmVycyIsImF1ZCI6ImFjY291bnQiLCJzdWIiOiJiZDg0ZjljOC1mN2Y2LTRiYjctYTFhOC0wNjI3ZjM1NTkyODkiLCJ0eXAiOiJCZWFyZXIiLCJhenAiOiJlYXJ0aGxpbmstcG9ydGFscyIsInNlc3Npb25fc3RhdGUiOiI2OGEyZTRlMi01NDNmLTQ4ZjgtOWQ0Yi01MzMzNDFiZjQwYzAiLCJhbGxvd2VkLW9yaWdpbnMiOlsiaHR0cHM6Ly9hZG1pbi5mdHRoLmlxIl0sInJlYWxtX2FjY2VzcyI6eyJyb2xlcyI6WyJTdXBlckFkbWluTWVtYmVyIiwiZGVmYXVsdC1yb2xlcy1wYXJ0bmVycyIsIkNvbnRyYWN0b3JNZW1iZXIiLCJvZmZsaW5lX2FjY2VzcyIsInVtYV9hdXRob3JizemF0aW9uIl19LCJyZXNvdXJjZV9hY2Nlc3MiOnsiYWNjb3VudCI6eyJyb2xlcyI6WyJtYW5hZ2UtYWNjb3VudCIsIm1hbmFnZS1hY2NvdW50LWxpbmtzIiwidmlldy1wcm9maWxlIl19fSwic2NvcGUiOiJwcm9maWxlIGVtYWlsIiwic2lkIjoiNjhhMmU0ZTItNTQzZi00OGY4LTlkNGItNTMzMzQxYmY0MGMwIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJBY2NvdW50SWQiOiIyMjYxMTc1IiwiR3JvdXBzIjpbIi9UZWFtX0NvbnRyYWN0b3JfMjI2MTE3NV9NZW1iZXJzIl0sInByZWZlcnJlZF91c2VybmFtZSI6ImhhaSJ9.aS_ra9qEGcdJCZYTaXjatlP_qKia9iZINY0GK4k-NvnqRl0ffkWkI7R4xc4HYb9us_I4g2Y8dEn7MI93wUJ9kNUPueIkFVCVko6XTDu6leBGsiyG409gK3gu9KA3zs-jwYvq681QiDugzIixAjAw1miqFf5TB1k540FZDvTKmSYib77_-tK6FlpKHV4AG1mLWYvEWKlFZaPyfJjcdt3vskeI8DOFDcuuq87rJS6gT53CzAsqxJz_vL_46C6s-mqG8yh3GbxAK3TB89aDGtNWUmGZWs9ByUMuTqcHdMjx_jd7BT5G4hPX7CIvOwD0GLe_z1l6tCNuOUP6sgswLzr62A';

      debugPrint('🔑 Fetching guest token...');
      debugPrint('Using Bearer Token: ${_bearerToken?.substring(0, 50)}...');

      // اختبار Bearer Token أولاً
      final bearerTokenValid = await _testBearerToken();
      if (!bearerTokenValid) {
        debugPrint('❌ Bearer Token validation failed, stopping...');
        return;
      }

      // محاولة طرق مختلفة لإرسال الطلب - محاكاة الطلب الناجح بالضبط
      final headers = {
        'authorization': 'Bearer $_bearerToken', // lowercase 'authorization'
        'accept': 'application/json, text/plain, */*', // lowercase 'accept'
        'content-type': 'application/json', // lowercase 'content-type'
        'referer': 'https://admin.ftth.iq/',
        'sec-ch-ua':
            '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        'user-type': 'Partner',
      };

      debugPrint('Request headers: $headers');

      final response = await http.post(
        Uri.parse('https://dashboard.ftth.iq/api/v1/security/guest_token/'),
        headers: headers,
        body: '', // إرسال body فارغ تماماً كما في الطلب الناجح
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        _guestToken = jsonBody['token'];
        debugPrint(
            '✅ Guest token received: ${_guestToken?.substring(0, 30)}...');

        if (mounted) {
          setState(() {});
          _initializeWebView();
        }
      } else {
        debugPrint('❌ Failed to get guest token: ${response.statusCode}');
        debugPrint('Error response body: ${response.body}');

        String errorMessage =
            'فشل في الحصول على guest token: ${response.statusCode}';

        // محاولة قراءة رسالة الخطأ من الاستجابة
        try {
          final errorBody = json.decode(response.body);
          if (errorBody['message'] != null) {
            errorMessage += '\nالسبب: ${errorBody['message']}';
          } else if (errorBody['detail'] != null) {
            errorMessage += '\nالتفاصيل: ${errorBody['detail']}';
          }
        } catch (e) {
          errorMessage += '\nاستجابة الخادم: ${response.body}';
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'جرب طرق بديلة',
                textColor: Colors.white,
                onPressed: () {
                  _tryAlternativeTokenFetch();
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error fetching guest token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب التوكن: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _initializeWebView() {
    if (_guestToken == null) {
      debugPrint('❌ Cannot initialize WebView: No guest token available');
      return;
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebView loading progress: $progress%');
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
            debugPrint('🌐 Page started loading: $url');

            // تحقق من Cloudflare Challenge
            if (url.contains('cdn-cgi/challenge-platform')) {
              debugPrint(
                  '🔒 Cloudflare Challenge detected - waiting for completion...');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('جاري التحقق من الحماية (Cloudflare)...'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            debugPrint('✅ Page finished loading: $url');

            if (url.contains('embedded/7')) {
              debugPrint('🎉 Dashboard loaded successfully!');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم تحميل الداشبورد بنجاح! ✅'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('''
❌ WebView Error:
  code: ${error.errorCode}
  description: ${error.description}
  errorType: ${error.errorType}
  isForMainFrame: ${error.isForMainFrame}
  URL: ${error.url ?? 'Unknown'}
            ''');

            // تجاهل أخطاء Cloudflare Challenge والـ Sentry
            if (error.url?.contains('cdn-cgi/challenge-platform') == true ||
                error.url?.contains('elsentry.earthlink.iq') == true) {
              debugPrint('ℹ️ Ignoring expected Cloudflare/Sentry error');
              return;
            }

            // عرض رسالة خطأ للمستخدم فقط للأخطاء المهمة
            if (mounted && (error.isForMainFrame ?? false)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'خطأ في التحميل: ${error.description}\nالكود: ${error.errorCode}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'إعادة المحاولة',
                    textColor: Colors.white,
                    onPressed: () {
                      _loadDashboardWithToken();
                    },
                  ),
                ),
              );
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('🔗 Navigation request: ${request.url}');
            return NavigationDecision.navigate;
          },
        ),
      );

    // تحميل الداشبورد مع التوكن
    _loadDashboardWithToken();
  }

  /// تحميل الداشبورد باستخدام Guest Token
  void _loadDashboardWithToken() {
    if (_guestToken == null) {
      debugPrint('❌ Cannot load dashboard: No guest token');
      return;
    }

    // استخدام معرف الداشبورد المحدد إذا كان متوفراً، وإلا استخدم 7 كافتراضي
    final dashboardId = _selectedDashboardId ?? '7';
    final dashboardUrl = 'https://dashboard.ftth.iq/embedded/$dashboardId';

    final headers = {
      'x-guesttoken': _guestToken!,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'ar,en;q=0.9',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    };

    debugPrint('🚀 Loading dashboard with guest token...');
    debugPrint('Dashboard URL: $dashboardUrl');
    debugPrint('Dashboard ID: $dashboardId');
    debugPrint('Headers: $headers');

    _controller.loadRequest(
      Uri.parse(dashboardUrl),
      headers: headers,
    );
  }

  void _testDifferentUrl(String urlType) {
    String url;
    Map<String, String> headers = {};

    // استخدام معرف الداشبورد المحدد
    final dashboardId = _selectedDashboardId ?? '7';

    // إضافة guest token إذا كان متوفراً
    if (_guestToken != null) {
      headers['x-guesttoken'] = _guestToken!;
    }

    switch (urlType) {
      case 'embedded':
        url = 'https://dashboard.ftth.iq/embedded/$dashboardId';
        break;
      case 'login':
        url = 'https://dashboard.ftth.iq/login';
        headers = {}; // لا نحتاج token للـ login page
        break;
      case 'public':
        url = 'https://dashboard.ftth.iq/superset/dashboard/$dashboardId';
        break;
      case 'api':
        url = 'https://dashboard.ftth.iq/api/v1/dashboard/$dashboardId';
        if (_bearerToken != null) {
          headers['Authorization'] = 'Bearer $_bearerToken';
        }
        break;
      default:
        url = 'https://dashboard.ftth.iq/embedded/$dashboardId';
    }

    debugPrint('🔄 Testing URL: $url');
    debugPrint('🔄 Dashboard ID: $dashboardId');
    debugPrint('🔄 With headers: $headers');

    _controller.loadRequest(Uri.parse(url), headers: headers);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('جاري اختبار: $url'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// اختبار Guest Token مع طلب API مباشر
  Future<void> _testGuestTokenDirectly() async {
    if (_guestToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد Guest Token للاختبار'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      debugPrint('🧪 Testing guest token with direct API call...');

      final response = await http.get(
        Uri.parse('https://dashboard.ftth.iq/api/v1/dashboard/7'),
        headers: {
          'x-guesttoken': _guestToken!,
          'Accept': 'application/json',
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'اختبار Guest Token: ${response.statusCode}\n'
              'الطول: ${response.body.length} حرف',
            ),
            backgroundColor:
                response.statusCode == 200 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      debugPrint('Test API response: ${response.statusCode}');
      debugPrint('Response length: ${response.body.length}');
    } catch (e) {
      debugPrint('❌ Error testing guest token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في اختبار التوكن: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// اختبار صحة Bearer Token قبل طلب Guest Token
  Future<bool> _testBearerToken() async {
    if (_bearerToken == null) return false;

    try {
      debugPrint('🧪 Testing Bearer Token validity...');

      // اختبار التوكن مع endpoint بسيط
      final response = await http.get(
        Uri.parse('https://dashboard.ftth.iq/api/v1/me'),
        headers: {
          'Authorization': 'Bearer $_bearerToken',
          'Accept': 'application/json',
        },
      );

      debugPrint('Bearer token test response: ${response.statusCode}');
      debugPrint('Bearer token test body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('✅ Bearer Token is valid');
        return true;
      } else if (response.statusCode == 401) {
        debugPrint('❌ Bearer Token is expired or invalid');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bearer Token منتهي الصلاحية أو غير صحيح'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return false;
      } else {
        debugPrint('⚠️ Bearer Token test returned: ${response.statusCode}');
        return true; // نفترض أنه صالح ونحاول Guest Token
      }
    } catch (e) {
      debugPrint('❌ Error testing Bearer Token: $e');
      return true; // نحاول المتابعة رغم الخطأ
    }
  }

  /// محاولة بديلة لجلب Guest Token بطرق مختلفة
  Future<void> _tryAlternativeTokenFetch() async {
    debugPrint('🔄 Trying alternative methods to fetch guest token...');

    final methods = [
      {
        'name': 'Method 1: Standard POST with empty JSON',
        'body': '{}',
        'contentType': 'application/json',
      },
      {
        'name': 'Method 2: POST with null body',
        'body': null,
        'contentType': 'application/json',
      },
      {
        'name': 'Method 3: POST with form data',
        'body': '',
        'contentType': 'application/x-www-form-urlencoded',
      },
    ];

    for (final method in methods) {
      try {
        debugPrint('Trying: ${method['name']}');

        final headers = {
          'Authorization': 'Bearer $_bearerToken',
          'Accept': 'application/json, text/plain, */*',
          'user-type': 'Partner',
          'Referer': 'https://admin.ftth.iq/',
          'Origin': 'https://admin.ftth.iq',
        };

        if (method['contentType'] != null) {
          headers['Content-Type'] = method['contentType']!;
        }

        final response = await http.post(
          Uri.parse('https://dashboard.ftth.iq/api/v1/security/guest_token/'),
          headers: headers,
          body: method['body'],
        );

        debugPrint('${method['name']} - Status: ${response.statusCode}');
        debugPrint('${method['name']} - Body: ${response.body}');

        if (response.statusCode == 200) {
          final jsonBody = json.decode(response.body);
          _guestToken = jsonBody['token'];
          debugPrint('✅ Success with ${method['name']}!');

          if (mounted) {
            setState(() {});
            _initializeWebView();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('تم الحصول على Guest Token بـ ${method['name']}'),
                backgroundColor: Colors.green,
              ),
            );
          }
          return;
        }
      } catch (e) {
        debugPrint('❌ ${method['name']} failed: $e');
      }
    }

    debugPrint('❌ All alternative methods failed');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل في جلب Guest Token بجميع الطرق المتاحة'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 8),
        ),
      );
    }
  }

  /// محاكاة الطلب الناجح بالضبط كما تم إرساله من المتصفح
  Future<void> _fetchTokenExactMatch() async {
    try {
      debugPrint('🎯 Fetching guest token with exact browser headers...');

      // تحديث Bearer Token - قد يكون انتهت صلاحيته
      _bearerToken =
          'eyJhbGciOiJSUzI1NiIsInR5cCIgOiAiSldUIiwia2lkIiA6ICI5Nzc4UnE5VVRxT3o5S3FXaE1nUmY2OVlBbWtjdGtaV3BFX1BOTDNKVzRnIn0.eyJleHAiOjE3NTA4OTUxOTcsImlhdCI6MTc1MDg5MTU5NywianRpIjoiOWM0YTBhOWUtOWExMy00YjFkLWFmZmEtY2E4NDg3MTM3NzRkIiwiaXNzIjoiaHR0cHM6Ly9zc28uZnR0aC5pcS9hdXRoL3JlYWxtcy9QYXJ0bmVycyIsImF1ZCI6ImFjY291bnQiLCJzdWIiOiJiZDg0ZjljOC1mN2Y2LTRiYjctYTFhOC0wNjI3ZjM1NTkyODkiLCJ0eXAiOiJCZWFyZXIiLCJhenAiOiJlYXJ0aGxpbmstcG9ydGFscyIsInNlc3Npb25fc3RhdGUiOiI2OGEyZTRlMi01NDNmLTQ4ZjgtOWQ0Yi01MzMzNDFiZjQwYzAiLCJhbGxvd2VkLW9yaWdpbnMiOlsiaHR0cHM6Ly9hZG1pbi5mdHRoLmlxIl0sInJlYWxtX2FjY2VzcyI6eyJyb2xlcyI6WyJTdXBlckFkbWluTWVtYmVyIiwiZGVmYXVsdC1yb2xlcy1wYXJ0bmVycyIsIkNvbnRyYWN0b3JNZW1iZXIiLCJvZmZsaW5lX2FjY2VzcyIsInVtYV9hdXRob3JizemF0aW9uIl19LCJyZXNvdXJjZV9hY2Nlc3MiOnsiYWNjb3VudCI6eyJyb2xlcyI6WyJtYW5hZ2UtYWNjb3VudCIsIm1hbmFnZS1hY2NvdW50LWxpbmtzIiwidmlldy1wcm9maWxlIl19fSwic2NvcGUiOiJwcm9maWxlIGVtYWlsIiwic2lkIjoiNjhhMmU0ZTItNTQzZi00OGY4LTlkNGItNTMzMzQxYmY0MGMwIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJBY2NvdW50SWQiOiIyMjYxMTc1IiwiR3JvdXBzIjpbIi9UZWFtX0NvbnRyYWN0b3JfMjI2MTE3NV9NZW1iZXJzIl0sInByZWZlcnJlZF91c2VybmFtZSI6ImhhaSJ9.aS_ra9qEGcdJCZYTaXjatlP_qKia9iZINY0GK4k-NvnqRl0ffkWkI7R4xc4HYb9us_I4g2Y8dEn7MI93wUJ9kNUPueIkFVCVko6XTDu6leBGsiyG409gK3gu9KA3zs-jwYvq681QiDugzIixAjAw1miqFf5TB1k540FZDvTKmSYib77_-tK6FlpKHV4AG1mLWYvEWKlFZaPyfJjcdt3vskeI8DOFDcuuq87rJS6gT53CzAsqxJz_vL_46C6s-mqG8yh3GbxAK3TB89aDGtNWUmGZWs9ByUMuTqcHdMjx_jd7BT5G4hPX7CIvOwD0GLe_z1l6tCNuOUP6sgswLzr62A';

      debugPrint('🔍 Using Bearer Token: ${_bearerToken?.substring(0, 50)}...');

      // محاكاة Headers بالضبط كما في الطلب الناجح
      final headers = {
        'accept': 'application/json, text/plain, */*',
        'authorization': 'Bearer $_bearerToken',
        'content-type': 'application/json',
        'referer': 'https://admin.ftth.iq/',
        'sec-ch-ua':
            '"Google Chrome";v="137", "Chromium";v="137", "Not/A)Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'user-agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36',
        'user-type': 'Partner',
      };

      debugPrint('🔍 Exact match headers: $headers');

      final response = await http.post(
        Uri.parse('https://dashboard.ftth.iq/api/v1/security/guest_token/'),
        headers: headers,
        body: '', // إرسال body فارغ
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response headers: ${response.headers}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        _guestToken = jsonBody['token'];
        debugPrint(
            '✅ Guest token received with exact match: ${_guestToken?.substring(0, 30)}...');

        if (mounted) {
          setState(() {});
          _initializeWebView();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم الحصول على Guest Token بنجاح! 🎉'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else if (response.statusCode == 403) {
        debugPrint('❌ 403 Forbidden - Bearer Token may be expired or invalid');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  '403 Forbidden - Bearer Token منتهي الصلاحية أو غير صحيح\n'
                  'يرجى الحصول على Bearer Token جديد من المتصفح'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 8),
              action: SnackBarAction(
                label: 'كيفية الحصول على Token',
                textColor: Colors.white,
                onPressed: () {
                  _showTokenInstructions();
                },
              ),
            ),
          );
        }
      } else {
        debugPrint('❌ Exact match failed: ${response.statusCode}');
        debugPrint('Error body: ${response.body}');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'فشل المطابقة الدقيقة: ${response.statusCode}\n${response.body}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error in exact match: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في المطابقة الدقيقة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// عرض تعليمات الحصول على Bearer Token جديد
  void _showTokenInstructions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('كيفية الحصول على Bearer Token جديد'),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'لحل مشكلة 403 Forbidden، تحتاج إلى Bearer Token جديد:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Text('1. افتح المتصفح واذهب إلى:'),
                Text(
                  'https://admin.ftth.iq/',
                  style: TextStyle(color: Colors.blue, fontFamily: 'monospace'),
                ),
                SizedBox(height: 8),
                Text('2. سجل الدخول إلى حسابك'),
                SizedBox(height: 8),
                Text('3. افتح Developer Tools (F12)'),
                SizedBox(height: 8),
                Text('4. اذهب إلى تبويب Network'),
                SizedBox(height: 8),
                Text('5. ابحث عن طلب لـ guest_token'),
                SizedBox(height: 8),
                Text('6. انسخ قيمة Authorization header'),
                SizedBox(height: 8),
                Text('7. ألصقها في الكود'),
                SizedBox(height: 16),
                Text(
                  'ملاحظة: Bearer Tokens لها مدة صلاحية محددة وتحتاج إلى تجديد دوري.',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.orange),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('فهمت'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showTokenInputDialog();
              },
              child: const Text('إدخال Token جديد'),
            ),
          ],
        );
      },
    );
  }

  /// عرض dialog لإدخال Bearer Token جديد
  void _showTokenInputDialog() {
    final tokenController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('إدخال Bearer Token جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('الصق Bearer Token الجديد هنا:'),
              const SizedBox(height: 16),
              TextField(
                controller: tokenController,
                decoration: const InputDecoration(
                  labelText: 'Bearer Token',
                  border: OutlineInputBorder(),
                  hintText: 'eyJhbGciOiJSUzI1NiIs...',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () {
                final newToken = tokenController.text.trim();
                if (newToken.isNotEmpty) {
                  setState(() {
                    _bearerToken = newToken;
                    _guestToken = null; // مسح Guest Token القديم
                  });
                  Navigator.of(context).pop();
                  _fetchTokenExactMatch(); // محاولة جلب Guest Token مرة أخرى

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('تم تحديث Bearer Token، جاري إعادة المحاولة...'),
                      backgroundColor: Colors.blue,
                    ),
                  );
                }
              },
              child: const Text('تحديث'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختبار WebView'),
        backgroundColor: Colors.blue[800],
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.link),
            tooltip: 'اختبار روابط مختلفة',
            onSelected: (String value) {
              _testDifferentUrl(value);
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'embedded',
                child: Text('Embedded Dashboard'),
              ),
              const PopupMenuItem(
                value: 'login',
                child: Text('Login Page'),
              ),
              const PopupMenuItem(
                value: 'public',
                child: Text('Public Dashboard'),
              ),
              const PopupMenuItem(
                value: 'api',
                child: Text('API Endpoint'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.science),
            tooltip: 'اختبار Guest Token',
            onPressed: () {
              _testGuestTokenDirectly();
            },
          ),
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'إدخال Bearer Token جديد',
            onPressed: () {
              _showTokenInputDialog();
            },
          ),
          IconButton(
            icon: const Icon(Icons.precision_manufacturing),
            tooltip: 'مطابقة دقيقة للطلب',
            onPressed: () {
              _fetchTokenExactMatch();
            },
          ),
          IconButton(
            icon: const Icon(Icons.alt_route),
            tooltip: 'طرق بديلة لجلب التوكن',
            onPressed: () {
              _tryAlternativeTokenFetch();
            },
          ),
          IconButton(
            icon: const Icon(Icons.token),
            tooltip: 'إعادة جلب Guest Token',
            onPressed: () {
              _fetchTokenExactMatch(); // استخدام المطابقة الدقيقة
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_guestToken != null) {
                _loadDashboardWithToken();
              } else {
                _fetchTokenExactMatch(); // استخدام المطابقة الدقيقة
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // معلومات المشكلة والحل
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _guestToken != null ? Colors.green[100] : Colors.orange[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _guestToken != null ? Icons.check_circle : Icons.warning,
                      color: _guestToken != null
                          ? Colors.green[800]
                          : Colors.orange[800],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _guestToken != null
                          ? 'تم الحصول على Guest Token بنجاح ✅'
                          : 'جاري جلب Guest Token...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _guestToken != null
                            ? Colors.green[800]
                            : Colors.orange[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _guestToken != null
                      ? 'Guest Token: ${_guestToken!.substring(0, 30)}...\nDashboard ID: ${_selectedDashboardId ?? "7"} (${_selectedDashboardId != null ? "إحصائيات المستخدمين" : "افتراضي"})'
                      : _bearerToken != null
                          ? 'Bearer Token: ${_bearerToken!.substring(0, 30)}... (جاري جلب Guest Token)\nDashboard ID: ${_selectedDashboardId ?? "غير محدد"}'
                          : 'لا يوجد Bearer Token - يرجى إدخال Token صحيح',
                  style: const TextStyle(fontSize: 12),
                ),
                if (_guestToken != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info, color: Colors.blue[800], size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'معلومات مهمة:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '• قد يستغرق التحميل وقتاً أطول بسبب حماية Cloudflare\n'
                          '• رابط challenge-platform طبيعي ولا يعني خطأ\n'
                          '• Sentry errors متوقعة وغير مضرة',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
                // إضافة معلومات عن مشكلة 403
                if (_guestToken == null && _bearerToken != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error, color: Colors.red[800], size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'إذا كنت تواجه خطأ 403:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red[800],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '• Bearer Token قد يكون منتهي الصلاحية\n'
                          '• اضغط على زر المفتاح 🔑 لإدخال Token جديد\n'
                          '• احصل على Token من admin.ftth.iq',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // WebView
          Expanded(
            child: _guestToken == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('جاري الحصول على Guest Token...'),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      WebViewWidget(controller: _controller),
                      if (_isLoading)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('جاري تحميل الداشبورد...'),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
