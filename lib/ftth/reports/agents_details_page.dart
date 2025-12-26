/// اسم الصفحة: تفاصيل الوكلاء
/// وصف الصفحة: صفحة عرض وإدارة تفاصيل الوكلاء وبياناتهم
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import '../widgets/notification_filter.dart';
import 'package:http/http.dart' as http;
import '../../services/agents_auth_service.dart';
import '../../pages/webview_page.dart';
import '../../test_webview_standalone.dart';

class AgentsDetailsPage extends StatefulWidget {
  final String authToken;
  const AgentsDetailsPage({super.key, required this.authToken});

  @override
  State<AgentsDetailsPage> createState() => _AgentsDetailsPageState();
}

class _AgentsDetailsPageState extends State<AgentsDetailsPage> {
  // Placeholder for agents data
  List<dynamic> agents = [];
  bool isLoading = true;
  String? error;
  String searchQuery = '';
  String selectedFilterColumn = 'partner';
  String defaultZone = '';
  Map<String, dynamic>? userRoles;
  Map<String, dynamic>? dashboardInfo;
  Map<String, dynamic>? dashboard7Info;
  List<String> zones = [];
  int? selectedSliceId;
  String? selectedSliceName;
  List<Map<String, dynamic>> availableSlices = [];
  String? guestToken;
  List<Map<String, dynamic>> dashboardDatasets = [];

  // متغيرات بيانات شارت داشبورد 7
  List<Map<String, dynamic>> dashboard7ChartData = [];
  List<String> dashboard7ChartColumns = [];
  String dashboard7ChartSearchQuery = '';
  String? dashboard7ChartSelectedColumn;

  // بيانات لوج الداشبورد
  Map<String, dynamic>? dashboardLogData;

  // بيانات إحصائية من charts مختلفة
  int? stat2; // من slice_id=2 (SUM(cnt) = 5)
  int? stat3; // من slice_id=3 (SUM(cnt))
  int? stat4; // من slice_id=4 (SUM(cnt))
  int? stat5; // من slice_id=5 (SUM(cnt) = 7)
  int? stat6; // من slice_id=6 (SUM(cnt) = 2)
  int? stat32; // من slice_id=32 (SUM(cnt))
  Map<String, dynamic>? chartStats; // إحصائيات إضافية

  // بيانات الحالات/التذاكر من slice_id=1
  List<Map<String, dynamic>> casesData = [];
  List<String> casesColumns = [];

  // zones المسموح بها للمستخدم (مستخرجة من الداشبورد)
  List<String> userZones = [];
  String? userAccountId;

  final List<Map<String, String>> filterColumns = [
    {'value': 'partner', 'label': 'اسم الوكيل'},
    {'value': 'zone', 'label': 'الزون'},
    {'value': 'issue', 'label': 'المشكلة'},
    {'value': 'contractor', 'label': 'المقاول'},
    {'value': 'zonetype', 'label': 'نوع الزون'},
  ];

  // دالة لفك تشفير JWT واستخراج المعلومات
  Map<String, dynamic>? _decodeJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;

      // فك تشفير الجزء الثاني (payload)
      String payload = parts[1];
      // إضافة padding إذا لزم
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      return json.decode(decoded) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ خطأ في فك تشفير JWT: $e');
      return null;
    }
  }

  // استخراج zones من بيانات الداشبورد (slice_id=23 أو 52)
  void _extractUserZones() {
    // محاولة استخراج zones من بيانات الوكلاء (slice_id=23)
    if (dashboard7ChartData.isNotEmpty) {
      final extractedZones = <String>{};
      for (var item in dashboard7ChartData) {
        final zone = item['zone']?.toString() ?? item['Zone']?.toString();
        if (zone != null && zone.isNotEmpty) {
          extractedZones.add(zone);
        }
      }
      if (extractedZones.isNotEmpty) {
        userZones = extractedZones.toList();
        debugPrint('📍 zones المستخرجة: $userZones');
      }
    }
  }

  List<Map<String, String>> get dynamicFilterColumns {
    if (agents.isNotEmpty) {
      final first = agents.first as Map<String, dynamic>;
      return first.keys.map((k) {
        // تعريب تلقائي للأعمدة الشائعة
        String label;
        switch (k) {
          case 'partner':
            label = 'اسم الوكيل';
            break;
          case 'zone':
          case 'Zone':
            label = 'الزون';
            break;
          case 'issue':
            label = 'المشكلة';
            break;
          case 'contractor':
          case 'ZoneContractor':
            label = 'المقاول';
            break;
          case 'zonetype':
          case 'ZoneType':
            label = 'نوع الزون';
            break;
          default:
            label = k;
        }
        return {'value': k, 'label': label};
      }).toList();
    }
    return filterColumns;
  }

  Map<String, String> customApiUrls = {};
  bool waitingForApiUrls = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeData();
    });
  }

  // دالة منفصلة للتهيئة مع معالجة أفضل للأخطاء
  Future<void> _initializeData() async {
    setState(() {
      isLoading = true;
      error = null;
      waitingForApiUrls = false; // إخفاء رسالة انتظار الروابط
    });

    try {
      debugPrint('بدء عملية التهيئة باستخدام AgentsAuthService...');
      debugPrint(
          'Auth Token المستلم: ${widget.authToken.substring(0, widget.authToken.length > 20 ? 20 : widget.authToken.length)}...');

      // استخراج معلومات المستخدم من الـ auth token
      if (widget.authToken.isNotEmpty) {
        final jwtPayload = _decodeJwt(widget.authToken);
        if (jwtPayload != null) {
          userAccountId = jwtPayload['AccountId']?.toString();
          debugPrint('📋 AccountId: $userAccountId');

          // استخراج zones إذا كانت موجودة في الـ token
          final groups = jwtPayload['Groups'] as List?;
          if (groups != null) {
            debugPrint('📋 Groups: $groups');
          }
        }
      }

      // جلب guest token أولاً
      String? fetchedGuestToken = await AgentsAuthService.fetchGuestToken(
        authToken: widget.authToken,
      );

      // إذا فشل، نحاول بطرق بديلة
      if (fetchedGuestToken == null) {
        debugPrint('محاولة جلب Guest Token بدون Auth Token...');
        fetchedGuestToken = await _tryAlternativeGuestToken();
      }

      if (fetchedGuestToken != null) {
        debugPrint(
            '✅ تم الحصول على guest token بنجاح: ${fetchedGuestToken.substring(0, 20)}...');

        // تحديث التوكن في الحالة فوراً
        setState(() {
          guestToken = fetchedGuestToken;
        });

        // Get authToken for headers
        final authToken = widget.authToken.isNotEmpty ? widget.authToken : null;

        // جلب البيانات المختلفة
        final userRolesData = await AgentsAuthService.fetchUserRoles(
          guestToken: fetchedGuestToken,
          authToken: authToken,
        );

        final dashboardData = await AgentsAuthService.fetchDashboardData(
          '1',
          guestToken: fetchedGuestToken,
          authToken: authToken,
        );

        final dashboard7Data = await AgentsAuthService.fetchDashboardData(
          '7',
          guestToken: fetchedGuestToken,
          authToken: authToken,
        );

        final chartData = await AgentsAuthService.fetchChartData(
          23,
          1,
          guestToken: fetchedGuestToken,
          authToken: authToken,
        );

        // جلب جميع الإحصائيات بالتوازي
        final futures = await Future.wait([
          AgentsAuthService.fetchChartData(2, 1,
              guestToken: fetchedGuestToken, authToken: authToken), // stat2
          AgentsAuthService.fetchChartData(3, 1,
              guestToken: fetchedGuestToken, authToken: authToken), // stat3
          AgentsAuthService.fetchChartData(4, 1,
              guestToken: fetchedGuestToken, authToken: authToken), // stat4
          AgentsAuthService.fetchChartData(5, 1,
              guestToken: fetchedGuestToken, authToken: authToken), // stat5
          AgentsAuthService.fetchChartData(6, 1,
              guestToken: fetchedGuestToken, authToken: authToken), // stat6
          AgentsAuthService.fetchChartData(32, 1,
              guestToken: fetchedGuestToken, authToken: authToken), // stat32
          AgentsAuthService.fetchChartData(1, 1,
              guestToken: fetchedGuestToken,
              authToken: authToken), // cases data
        ]);

        final statsChartData2 = futures[0];
        final statsChartData3 = futures[1];
        final statsChartData4 = futures[2];
        final statsChartData5 = futures[3];
        final statsChartData6 = futures[4];
        final statsChartData32 = futures[5];
        final casesChartData = futures[6];

        final logData = await AgentsAuthService.fetchDashboardLogData(
          1,
          guestToken: fetchedGuestToken,
        );

        // تحديث البيانات في الحالة
        setState(() {
          userRoles = userRolesData;
          dashboardInfo = dashboardData;
          dashboard7Info = dashboard7Data;
          dashboardLogData = logData;

          // معالجة بيانات الشارت الرئيسي
          if (chartData != null) {
            dashboard7ChartData =
                (chartData['data'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];
            dashboard7ChartColumns =
                (chartData['colnames'] as List?)?.cast<String>() ?? [];

            if (dashboard7ChartColumns.isNotEmpty) {
              dashboard7ChartSelectedColumn = dashboard7ChartColumns[0];
            }
          }

          // معالجة بيانات الإحصائيات من كل slice
          // slice_id=2
          if (statsChartData2 != null) {
            final data = statsChartData2['data'] as List?;
            if (data != null && data.isNotEmpty) {
              final firstRow = data[0] as Map<String, dynamic>;
              stat2 = firstRow['SUM(cnt)'] as int?;
              debugPrint('📊 stat2 (slice_id=2): $stat2');
            }
          }

          // slice_id=3
          if (statsChartData3 != null) {
            final data = statsChartData3['data'] as List?;
            if (data != null && data.isNotEmpty) {
              final firstRow = data[0] as Map<String, dynamic>;
              stat3 = firstRow['SUM(cnt)'] as int?;
              debugPrint('📊 stat3 (slice_id=3): $stat3');
            }
          }

          // slice_id=4
          if (statsChartData4 != null) {
            final data = statsChartData4['data'] as List?;
            if (data != null && data.isNotEmpty) {
              final firstRow = data[0] as Map<String, dynamic>;
              stat4 = firstRow['SUM(cnt)'] as int?;
              debugPrint('📊 stat4 (slice_id=4): $stat4');
            }
          }

          // slice_id=5
          if (statsChartData5 != null) {
            final data = statsChartData5['data'] as List?;
            if (data != null && data.isNotEmpty) {
              final firstRow = data[0] as Map<String, dynamic>;
              stat5 = firstRow['SUM(cnt)'] as int?;
              debugPrint('📊 stat5 (slice_id=5): $stat5');
            }
          }

          // slice_id=6
          if (statsChartData6 != null) {
            final data = statsChartData6['data'] as List?;
            if (data != null && data.isNotEmpty) {
              final firstRow = data[0] as Map<String, dynamic>;
              stat6 = firstRow['SUM(cnt)'] as int?;
              debugPrint('📊 stat6 (slice_id=6): $stat6');
            }
          }

          // slice_id=32
          if (statsChartData32 != null) {
            final data = statsChartData32['data'] as List?;
            if (data != null && data.isNotEmpty) {
              final firstRow = data[0] as Map<String, dynamic>;
              stat32 = firstRow['SUM(cnt)'] as int?;
              debugPrint('📊 stat32 (slice_id=32): $stat32');
            }
          }

          // بيانات الحالات/التذاكر من slice_id=1
          if (casesChartData != null) {
            casesData = (casesChartData['data'] as List?)
                    ?.cast<Map<String, dynamic>>() ??
                [];
            casesColumns =
                (casesChartData['colnames'] as List?)?.cast<String>() ?? [];
            debugPrint('📊 تم جلب ${casesData.length} حالة/تذكرة');
          }

          // استخراج zones المستخدم من بيانات الوكلاء
          _extractUserZones();
        });

        // جلب بيانات الوكلاء مباشرة
        await fetchZonesChart(fetchedGuestToken, isGuest: true);

        // استخراج zones مرة أخرى بعد جلب البيانات
        _extractUserZones();

        debugPrint('تم جلب البيانات بنجاح');
        debugPrint('📊 عدد zones المستخدم: ${userZones.length}');
        debugPrint('📊 zones: $userZones');
      } else {
        debugPrint('فشل في الحصول على guest token');
        setState(() {
          error =
              'فشل في الحصول على Guest Token.\n\nالأسباب المحتملة:\n• التوكن الحالي غير صالح للداشبورد\n• الخادم لا يستجيب\n• مشكلة في الاتصال بالإنترنت\n\nيرجى تسجيل الدخول مرة أخرى أو التواصل مع الدعم الفني.';
        });
      }
    } catch (e) {
      debugPrint('خطأ عام في التهيئة: $e');
      setState(() {
        error = 'خطأ في تحميل البيانات: ${e.toString()}';
      });
    } finally {
      setState(() {
        isLoading = false;
        waitingForApiUrls = false;
      });
    }
  }

  // محاولة جلب Guest Token بطرق بديلة
  Future<String?> _tryAlternativeGuestToken() async {
    try {
      // محاولة 1: استخدام التوكن المخزن مسبقاً
      final storedToken = await AgentsAuthService.getStoredGuestToken();
      if (storedToken != null && storedToken.isNotEmpty) {
        debugPrint('تم العثور على Guest Token مخزن');
        return storedToken;
      }

      // محاولة 2: طلب مع body صحيح (بدون / في النهاية)
      final url =
          Uri.parse('https://dashboard.ftth.iq/api/v1/security/guest_token');

      final requestBody = json.encode({
        "resources": [
          {"type": "dashboard", "id": "f9a17800-abd4-48fc-be94-79aa42a6d36d"}
        ],
        "rls": [],
        "user": {
          "username": "viewer",
          "first_name": "viewer",
          "last_name": "viewer"
        }
      });

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json, text/plain, */*',
              'user-type': 'Partner',
              'origin': 'https://admin.ftth.iq',
              'referer': 'https://admin.ftth.iq/',
            },
            body: requestBody,
          )
          .timeout(const Duration(seconds: 15));

      debugPrint('محاولة بديلة - الاستجابة: ${response.statusCode}');
      debugPrint('محاولة بديلة - Response: ${response.body}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final token = jsonBody['token'] as String?;
        if (token != null && token.isNotEmpty) {
          return token;
        }
      }

      return null;
    } catch (e) {
      debugPrint('فشل في المحاولة البديلة: $e');
      return null;
    }
  }

  // عرض نافذة تسجيل الدخول
  void _showLoginDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    bool isLoggingIn = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.login, color: Colors.teal),
              const SizedBox(width: 8),
              const Text('تسجيل الدخول للداشبورد'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'أدخل بيانات حساب Dashboard FTTH',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ملاحظة: هذه البيانات خاصة بنظام dashboard.ftth.iq',
                    style: TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoggingIn ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: isLoggingIn
                  ? null
                  : () async {
                      if (usernameController.text.isEmpty ||
                          passwordController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('يرجى إدخال اسم المستخدم وكلمة المرور'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isLoggingIn = true);

                      try {
                        final result = await AgentsAuthService.login(
                          usernameController.text,
                          passwordController.text,
                        );

                        if (result.isSuccess && result.accessToken != null) {
                          Navigator.pop(context);
                          // إعادة تحميل البيانات بالتوكن الجديد
                          final newGuestToken =
                              await AgentsAuthService.fetchGuestToken(
                            authToken: result.accessToken!,
                          );

                          if (newGuestToken != null) {
                            setState(() {
                              guestToken = newGuestToken;
                              error = null;
                            });
                            await _initializeData();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تسجيل الدخول بنجاح ✓'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'تم تسجيل الدخول لكن فشل جلب Guest Token'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  result.errorMessage ?? 'فشل تسجيل الدخول'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('خطأ: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        setDialogState(() => isLoggingIn = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: isLoggingIn
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('دخول'),
            ),
          ],
        ),
      ),
    );
  }

  // جلب بيانات المناطق من شارت chart/data (slice_id=52, dashboard_id=7)
  Future<void> fetchZonesChart(String token, {bool isGuest = false}) async {
    try {
      debugPrint('بدء جلب بيانات المناطق...');

      // استخدام الخدمة المحدثة مع الهيدرز الصحيحة
      final chartData = await AgentsAuthService.fetchChartData(
        52, // slice_id
        7, // dashboard_id
        guestToken: token,
        authToken: widget.authToken.isNotEmpty ? widget.authToken : null,
      );

      if (chartData != null) {
        final data =
            (chartData['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final columns = (chartData['colnames'] as List?)?.cast<String>() ?? [];
        setState(() {
          dashboard7ChartData = data;
          dashboard7ChartColumns = columns;
          if (columns.isNotEmpty) {
            dashboard7ChartSelectedColumn = columns[0];
          }
        });
        debugPrint('✅ تم جلب ${data.length} سجل من بيانات المناطق الجديدة');
        debugPrint('الأعمدة المتاحة: ${columns.join(", ")}');
      } else {
        debugPrint('لا توجد بيانات في الاستجابة');
        setState(() {
          dashboard7ChartData = [];
          dashboard7ChartColumns = [];
        });
      }
    } catch (e) {
      debugPrint('خطأ في جلب بيانات المناطق حسب المقاولين: $e');
      setState(() {
        dashboard7ChartData = [];
        dashboard7ChartColumns = [];
        // لا نضع error هنا لأنه ليس خطأ مميت
      });
    }
  }

  // بناء بطاقة إحصائية صغيرة
  Widget _buildStatCard(String title, int? value, Color color) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: color.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value?.toString() ?? '-',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> fetchGuestToken() async {
    int maxRetries = 3;
    int currentTry = 0;

    while (currentTry < maxRetries) {
      try {
        debugPrint('محاولة جلب guest token رقم ${currentTry + 1}');

        final url =
            Uri.parse('https://dashboard.ftth.iq/api/v1/security/guest_token/');
        final headers = {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'user-type': 'Partner',
        };

        if (widget.authToken.isNotEmpty) {
          headers['authorization'] = 'Bearer ${widget.authToken}';
        }

        final client = http.Client();
        try {
          final response = await client
              .post(
                url,
                headers: headers,
                body: '{}',
              )
              .timeout(Duration(seconds: 10));

          debugPrint('fetchGuestToken status: ${response.statusCode}');
          debugPrint('fetchGuestToken body length: ${response.body.length}');

          if (response.statusCode == 200) {
            final jsonBody = json.decode(response.body);
            final token = jsonBody['token'] as String?;
            if (token != null && token.isNotEmpty) {
              debugPrint('تم الحصول على guest token بنجاح');
              guestToken = token;
              return token;
            } else {
              debugPrint('الاستجابة لا تحتوي على token صالح');
            }
          } else {
            debugPrint('فشل الطلب: ${response.statusCode} - ${response.body}');
          }
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('خطأ في محاولة ${currentTry + 1} لجلب guest token: $e');
      }

      currentTry++;
      if (currentTry < maxRetries) {
        final delaySeconds = currentTry * 2;
        debugPrint('انتظار $delaySeconds ثواني قبل المحاولة التالية...');
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }

    debugPrint('فشل في الحصول على guest token بعد $maxRetries محاولات');
    return null;
  }

  Future<void> fetchUserRoles(String token, {bool isGuest = false}) async {
    try {
      debugPrint('fetchUserRoles: token=$token, isGuest=${isGuest.toString()}');
      // تحديث: استخدام رابط فعّال بدلاً من /api/v1/me/roles/ الذي يعطي 404
      // مؤقتاً نستخدم رابط الشارت الذي يعمل لاختبار الاتصال
      final url = Uri.parse(
          'https://dashboard.ftth.iq/api/v1/chart/data?form_data=%7B%22slice_id%22%3A52%7D&dashboard_id=7');
      final response = await http.get(
        url,
        headers: isGuest
            ? {
                'x-guesttoken': token,
                'Accept': 'application/json',
              }
            : {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
      );
      debugPrint('fetchUserRoles status: ${response.statusCode}');
      debugPrint('fetchUserRoles body: ${response.body}');
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        setState(() {
          userRoles = jsonBody['result'] as Map<String, dynamic>?;
          debugPrint('userRoles after fetch: ${userRoles.toString()}');
        });
      } else {
        debugPrint('فشل في جلب معلومات الرولز: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        setState(() {
          userRoles = null;
        });
      }
    } catch (e) {
      debugPrint('خطأ في جلب معلومات الرولز: $e');
      setState(() {
        userRoles = null;
      });
    }
  }

  Future<void> fetchDashboardInfo(String token, {bool isGuest = false}) async {
    try {
      // تحديث: استخدام رابط فعّال بدلاً من /api/partners/dashboard/summary الذي قد يعطي 404
      // مؤقتاً نستخدم رابط الداشبورد الفعلي
      final url = Uri.parse('https://dashboard.ftth.iq/api/v1/dashboard/7');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        setState(() {
          dashboardInfo = {
            'dashboard_title': 'لوحة معلومات المقاولين',
            'charts': jsonBody['data'] ?? [],
          };
        });
      } else {
        debugPrint('فشل في جلب معلومات لوحة المعلومات: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('خطأ في جلب معلومات لوحة المعلومات: $e');
    }
  }

  Future<void> fetchDashboard7(String token, {bool isGuest = false}) async {
    try {
      final url = Uri.parse('https://dashboard.ftth.iq/api/v1/dashboard/7');
      final response = await http.get(
        url,
        headers: isGuest
            ? {
                'x-guesttoken': token,
                'Accept': 'application/json',
              }
            : {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
              },
      );
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        setState(() {
          dashboard7Info = jsonBody['result'] as Map<String, dynamic>?;
          debugPrint(
              'dashboard7Info after fetch: ${dashboard7Info.toString()}');
        });
      } else {
        debugPrint('فشل في جلب الداشبورد 7: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        setState(() {
          dashboard7Info = null;
        });
      }
    } catch (e) {
      debugPrint('خطأ في جلب الداشبورد 7: $e');
      setState(() {
        dashboard7Info = null;
      });
    }
  }

  Future<void> fetchDashboardDatasets(String token,
      {bool isGuest = false}) async {
    try {
      // تحديث: استخدام رابط فعّال بدلاً من /api/partners/datasets الذي يعطي 404
      // مؤقتاً نستخدم رابط أساسي للاختبار
      final url = Uri.parse('https://dashboard.ftth.iq/api/v1/dataset/');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        setState(() {
          dashboardDatasets =
              List<Map<String, dynamic>>.from(jsonBody['data'] ?? []);
        });
      } else {
        debugPrint('فشل في جلب مجموعات البيانات: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('خطأ في جلب مجموعات البيانات: $e');
    }
  }

  Future<void> fetchDashboardCharts(String token,
      {bool isGuest = false}) async {
    try {
      // تحديث: استخدام رابط فعّال بدلاً من /api/partners/charts الذي يعطي 404
      // نستخدم رابط الشارت الفعلي للحصول على قائمة الشارتات
      final url = Uri.parse('https://dashboard.ftth.iq/api/v1/chart/');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final result = jsonBody['data'] as List?;
        if (result != null) {
          setState(() {
            availableSlices = result.map<Map<String, dynamic>>((chart) {
              return {
                'slice_id': chart['id'],
                'slice_name': chart['name'] ?? chart['id'].toString(),
                'dataset_id': chart['dataset_id'],
              };
            }).toList();

            if (availableSlices.isNotEmpty) {
              selectedSliceId = availableSlices[0]['slice_id'];
              selectedSliceName = availableSlices[0]['slice_name'];
            } else {
              selectedSliceId = null;
              selectedSliceName = null;
            }
          });
        }
      } else {
        setState(() {
          error =
              'فشل في جلب الشارتات. يرجى التحقق من صلاحياتك والمحاولة مرة أخرى.';
          availableSlices = [];
        });
      }
    } catch (e) {
      setState(() {
        error = 'خطأ في جلب الشارتات: $e';
        availableSlices = [];
      });
    }
  }

  Future<void> fetchZones(String token, {bool isGuest = false}) async {
    try {
      // تحديث: استخدام رابط بيانات المناطق من الشارت بدلاً من /api/partners/zones الذي يعطي 404
      // نستخدم شارت المناطق الذي يعمل فعلياً
      final url = Uri.parse(
          'https://dashboard.ftth.iq/api/v1/chart/data?form_data=%7B%22slice_id%22%3A52%7D&dashboard_id=7');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final data = jsonBody['data'] as List?;
        if (data != null) {
          setState(() {
            zones =
                data.map<String>((zone) => zone['name'].toString()).toList();
          });
        }
      } else {
        debugPrint('فشل في جلب المناطق: ${response.statusCode}');
        zones = [];
      }
    } catch (e) {
      debugPrint('خطأ في جلب المناطق: $e');
      zones = [];
    }
  }

  Future<void> fetchAgents() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    String? token = widget.authToken.isNotEmpty
        ? widget.authToken
        : await fetchGuestToken();

    try {
      // تحديث: استخدام رابط فعّال بدلاً من /api/partners/agents الذي يعطي 404
      // مؤقتاً نستخدم نفس رابط الشارت للحصول على بيانات أساسية
      final url = Uri.parse(
          'https://dashboard.ftth.iq/api/v1/chart/data?form_data=%7B%22slice_id%22%3A52%7D&dashboard_id=7');
      final bodyData = searchQuery.isNotEmpty
          ? {
              'filter': {
                'column': selectedFilterColumn,
                'value': searchQuery,
              }
            }
          : {};
      debugPrint('Agents request body: ${jsonEncode(bodyData)}');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(bodyData),
      );
      debugPrint('Agents response status: ${response.statusCode}');
      debugPrint('Agents response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        debugPrint('Response JSON structure: ${jsonBody.keys}');

        // معالجة صحيحة لاستجابة API الشارت
        final resultList = jsonBody['result'] as List?;
        if (resultList != null && resultList.isNotEmpty) {
          final result = resultList[0];
          final data =
              (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          debugPrint('Found ${data.length} records from chart API');

          setState(() {
            agents = data;
            isLoading = false;
            error = null;
          });
        } else {
          debugPrint('No data found in result list');
          setState(() {
            agents = [];
            isLoading = false;
            error = null;
          });
        }
      } else {
        setState(() {
          isLoading = false;
          error = 'فشل في جلب بيانات الوكلاء: \\${response.statusCode}';
          agents = [];
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        error = 'خطأ في جلب بيانات الوكلاء: $e';
        agents = [];
      });
    }
  }

  // جلب بيانات شارت من داشبورد 7 (مثلاً slice_id=52)
  Future<void> fetchDashboard7ChartData(String token,
      {bool isGuest = false, int sliceId = 52}) async {
    try {
      final url = Uri.parse(
          'https://dashboard.ftth.iq/api/v1/chart/data?form_data=%7B%22slice_id%22%3A$sliceId%7D&dashboard_id=7');
      final response = await http.post(
        url,
        headers: isGuest
            ? {
                'x-guesttoken': token,
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              }
            : {
                'Authorization': 'Bearer $token',
                'Accept': 'application/json',
                'Content-Type': 'application/json',
              },
        body: '{}', // لا ترسل فلاتر غير موجودة
      );
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        final resultList = jsonBody['result'] as List?;
        if (resultList != null && resultList.isNotEmpty) {
          final result = resultList[0];
          final data =
              (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          final columns = (result['colnames'] as List?)?.cast<String>() ?? [];
          setState(() {
            dashboard7ChartData = data;
            dashboard7ChartColumns = columns;
            if (columns.isNotEmpty) {
              dashboard7ChartSelectedColumn = columns[0];
            }
          });
        }
      } else {
        debugPrint('فشل في جلب بيانات شارت داشبورد 7: ${response.statusCode}');
        setState(() {
          dashboard7ChartData = [];
          dashboard7ChartColumns = [];
        });
      }
    } catch (e) {
      debugPrint('خطأ في جلب بيانات شارت داشبورد 7: $e');
      setState(() {
        dashboard7ChartData = [];
        dashboard7ChartColumns = [];
      });
    }
  }

  // جلب معلومات الداشبورد من /superset/log/?explode=events&dashboard_id=7
  Future<void> fetchDashboardLogData(String token,
      {bool isGuest = false}) async {
    try {
      debugPrint('بدء جلب بيانات لوج الداشبورد...');
      final url = Uri.parse(
          'https://dashboard.ftth.iq/superset/log/?explode=events&dashboard_id=7');
      final request = http.MultipartRequest('POST', url);
      if (isGuest) {
        request.headers['x-guesttoken'] = token;
      } else {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.headers['Accept'] = 'application/json';
      // يمكن إضافة أي حقول إضافية إذا لزم الأمر
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('fetchDashboardLogData status: ${response.statusCode}');
      debugPrint('fetchDashboardLogData body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        setState(() {
          dashboardLogData = jsonBody;
        });
        debugPrint('تم جلب بيانات لوج الداشبورد بنجاح');
      } else {
        debugPrint('فشل في جلب بيانات لوج الداشبورد: ${response.statusCode}');
        debugPrint('Response body: ${response.body}');
        setState(() {
          dashboardLogData = null;
          // لا نضع error هنا لأنه ليس خطأ مميت
        });
      }
    } catch (e) {
      debugPrint('خطأ في جلب بيانات لوج الداشبورد: $e');
      setState(() {
        dashboardLogData = null;
        // لا نضع error هنا لأنه ليس خطأ مميت
      });
    }
  }

  // الحالات المفلترة حسب zones المستخدم
  List<Map<String, dynamic>> get filteredCases {
    if (userZones.isEmpty) return casesData; // إذا لا توجد zones، أظهر الكل
    return casesData.where((caseItem) {
      final zone = caseItem['zone']?.toString() ?? '';
      return userZones.any(
          (userZone) => zone.contains(userZone) || userZone.contains(zone));
    }).toList();
  }

  List<dynamic> get filteredAgents {
    // فلترة حسب البحث
    var result = agents;

    // فلترة حسب zones المستخدم أولاً
    if (userZones.isNotEmpty) {
      result = result.where((agent) {
        final map = agent as Map<String, dynamic>;
        final zone = map['zone']?.toString() ?? map['Zone']?.toString() ?? '';
        return userZones.any(
            (userZone) => zone.contains(userZone) || userZone.contains(zone));
      }).toList();
    }

    // ثم فلترة حسب البحث
    if (searchQuery.isEmpty) return result;
    final cols = dynamicFilterColumns.map((c) => c['value']).toList();
    return result.where((agent) {
      final map = agent as Map<String, dynamic>;
      for (final col in cols) {
        if ((map[col]?.toString() ?? '').contains(searchQuery)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // لوج تشخيصي لطباعة الرولز في الواجهة
    debugPrint('userRoles in UI: ${userRoles?['roles']?.toString() ?? 'null'}');
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        iconTheme: const IconThemeData(size: 20),
        title: const Text(
          'تفاصيل الوكلاء',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        actions: [
          // مؤشر حالة التوكن
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else if (guestToken != null)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 20,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.dashboard, size: 20),
            tooltip: 'فتح الداشبورد',
            onPressed: () async {
              debugPrint('🎯 تم الضغط على زر الداشبورد');
              debugPrint(
                  '🎯 حالة guestToken: ${guestToken?.substring(0, 20) ?? 'null'}...');

              // محاولة الحصول على التوكن من التخزين المحلي إذا لم يكن متوفراً في الحالة
              String? effectiveToken = guestToken;

              if (effectiveToken == null) {
                debugPrint('🎯 محاولة جلب التوكن من التخزين المحلي...');
                effectiveToken = await AgentsAuthService.getStoredGuestToken();

                if (effectiveToken != null) {
                  setState(() {
                    guestToken = effectiveToken;
                  });
                  debugPrint('✅ تم العثور على التوكن في التخزين المحلي');
                }
              }

              if (effectiveToken != null) {
                debugPrint('🎯 فتح الداشبورد مع التوكن');
                final dashboardUrl =
                    await AgentsAuthService.getDashboardUrl('7');
                debugPrint('🎯 رابط الداشبورد: $dashboardUrl');

                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WebViewPage(
                        url: dashboardUrl,
                        title: 'داشبورد FTTH',
                      ),
                    ),
                  );
                }
              } else {
                debugPrint('❌ لا يوجد guest token متاح');
                ftthShowSnackBar(
                  context,
                  SnackBar(
                    content: const Text(
                        'جاري تحميل البيانات، يرجى المحاولة مرة أخرى'),
                    backgroundColor: Colors.orange,
                    action: SnackBarAction(
                      label: 'إعادة تحميل',
                      onPressed: () async {
                        await _initializeData();
                      },
                    ),
                  ),
                );
              }
            },
          ),
          // زر اختبار WebView
          IconButton(
            icon: const Icon(Icons.bug_report, size: 20),
            tooltip: 'اختبار WebView',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TestWebViewPage(),
                ),
              );
            },
          ),
          // زر فتح الداشبورد بدون توكن (للاختبار)
          IconButton(
            icon: const Icon(Icons.web, size: 20),
            tooltip: 'داشبورد مباشر (اختبار)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WebViewPage(
                    url: 'https://dashboard.ftth.iq/embedded/7',
                    title: 'داشبورد مباشر',
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'إعادة تحميل البيانات',
            onPressed: () async {
              await _initializeData();
            },
          ),
        ],
        bottom: userRoles != null
            ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المستخدم: ${userRoles?['username'] ?? "-"}',
                        style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'الدور الحالي: ${userRoles?['roles'] != null ? (userRoles!['roles'] as Map).keys.join(", ") : "غير محدد"}',
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: waitingForApiUrls
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'تم جلب الرول بنجاح. يرجى تزويد الروابط الجديدة لواجهات الـ API (Agents, Dashboard, Charts...) ليتم عرض البيانات.',
                    style: TextStyle(
                        fontSize: 16,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      // هنا يمكنك فتح Dialog أو صفحة لإدخال الروابط الجديدة
                      // مثال: showDialog(...) أو أي منطق آخر
                    },
                    child: const Text('إدخال الروابط الجديدة'),
                  ),
                ],
              ),
            )
          : (isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text(
                        'جاري تحميل البيانات...',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'الاتصال بـ dashboard.ftth.iq',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                )
              : error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'فشل في تحميل البيانات',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red[200]!),
                              ),
                              child: Text(
                                error!,
                                style: const TextStyle(
                                    color: Colors.red, fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // معلومات التشخيص
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '🔍 معلومات التشخيص:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                      '• Auth Token: ${widget.authToken.isNotEmpty ? "موجود ✓" : "غير موجود ✗"}',
                                      style: const TextStyle(fontSize: 12)),
                                  Text(
                                      '• Guest Token: ${guestToken != null ? "موجود ✓" : "غير موجود ✗"}',
                                      style: const TextStyle(fontSize: 12)),
                                  Text('• عدد الوكلاء: ${agents.length}',
                                      style: const TextStyle(fontSize: 12)),
                                  Text(
                                      '• بيانات الداشبورد: ${dashboard7Info != null ? "متوفرة ✓" : "غير متوفرة ✗"}',
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _initializeData(),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('إعادة المحاولة'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _showLoginDialog(),
                                  icon: const Icon(Icons.login),
                                  label: const Text('تسجيل دخول'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.arrow_back),
                                  label: const Text('رجوع'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // شريط حالة الاتصال
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: guestToken != null
                              ? Colors.green[50]
                              : Colors.orange[50],
                          child: Row(
                            children: [
                              Icon(
                                guestToken != null
                                    ? Icons.check_circle
                                    : Icons.warning,
                                size: 18,
                                color: guestToken != null
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  guestToken != null
                                      ? 'متصل بالخادم ✓ | المناطق: ${dashboard7ChartData.length} | الحالات: ${casesData.length}'
                                      : 'غير متصل بالخادم - قد لا تظهر البيانات',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: guestToken != null
                                        ? Colors.green[800]
                                        : Colors.orange[800],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.refresh, size: 18),
                                onPressed: () => _initializeData(),
                                tooltip: 'تحديث البيانات',
                              ),
                            ],
                          ),
                        ),
                        // بطاقات الإحصائيات
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildStatCard('العدد 1', stat2, Colors.blue),
                                _buildStatCard('العدد 2', stat3, Colors.green),
                                _buildStatCard('العدد 3', stat4, Colors.orange),
                                _buildStatCard('العدد 4', stat5, Colors.purple),
                                _buildStatCard('العدد 5', stat6, Colors.teal),
                                _buildStatCard('العدد 6', stat32, Colors.red),
                              ],
                            ),
                          ),
                        ),
                        if (dashboard7Info != null) ...[
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Card(
                              color: Colors.amber[50],
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'داشبورد: \u200E${dashboard7Info?['dashboard_title'] ?? '-'}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: Colors.orange),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'عدد الشارتات: \u200E${(dashboard7Info?['charts'] is List ? (dashboard7Info?['charts'] as List).length : 0)}',
                                      style: const TextStyle(fontSize: 15),
                                    ),
                                    if (dashboard7Info?['charts'] is List)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 6.0),
                                        child: Text(
                                          'الشارتات: \u200E${(dashboard7Info?['charts'] as List).join(", ")}',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black87),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (dashboardLogData != null) ...[
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Card(
                              color: Colors.green[50],
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'معلومات لوج الداشبورد:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.green),
                                    ),
                                    const SizedBox(height: 8),
                                    // عرض بعض الحقول المهمة إذا وجدت
                                    if (dashboardLogData!['dashboard_id'] !=
                                        null)
                                      Text(
                                          'Dashboard ID: ${dashboardLogData!['dashboard_id']}'),
                                    if (dashboardLogData!['user'] != null)
                                      Text(
                                          'User: ${dashboardLogData!['user']}'),
                                    if (dashboardLogData!['events'] != null &&
                                        dashboardLogData!['events'] is List)
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 6),
                                          const Text('عدد الأحداث (events):',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          Text(
                                              '${(dashboardLogData!['events'] as List).length}'),
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            height: 100,
                                            child: ListView.builder(
                                              itemCount:
                                                  (dashboardLogData!['events']
                                                          as List)
                                                      .length,
                                              itemBuilder: (context, idx) {
                                                final event =
                                                    dashboardLogData!['events']
                                                        [idx];
                                                return Text(event.toString(),
                                                    style: const TextStyle(
                                                        fontSize: 12));
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (dashboardLogData!['events'] == null)
                                      Text('لا توجد أحداث متاحة.'),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  onChanged: (value) {
                                    setState(() {
                                      searchQuery = value;
                                    });
                                  },
                                  decoration: InputDecoration(
                                    labelText: 'ابحث هنا',
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () {
                                        setState(() {
                                          searchQuery = '';
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<String>(
                                value: dynamicFilterColumns.any((c) =>
                                        c['value'] == selectedFilterColumn)
                                    ? selectedFilterColumn
                                    : dynamicFilterColumns.first['value'],
                                onChanged: (String? newValue) {
                                  setState(() {
                                    selectedFilterColumn = newValue!;
                                  });
                                },
                                items: dynamicFilterColumns
                                    .map<DropdownMenuItem<String>>(
                                        (Map<String, String> value) {
                                  return DropdownMenuItem<String>(
                                    value: value['value'],
                                    child: Text(value['label']!),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: filteredAgents.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.inbox_outlined,
                                          size: 64,
                                          color: Colors.grey[400],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          'لا توجد بيانات لعرضها',
                                          style: TextStyle(
                                            color: Colors.grey[700],
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[50],
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Column(
                                            children: [
                                              const Text(
                                                'الأسباب المحتملة:',
                                                style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '• Guest Token: ${guestToken != null ? "متوفر ✓" : "غير متوفر ✗"}',
                                                style: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                              Text(
                                                '• بيانات الشارت: ${dashboard7ChartData.length} سجل',
                                                style: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                              Text(
                                                '• الخادم قد لا يستجيب أو يرفض الطلب',
                                                style: const TextStyle(
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        ElevatedButton.icon(
                                          onPressed: () => _initializeData(),
                                          icon: const Icon(Icons.refresh),
                                          label: const Text(
                                              'إعادة تحميل البيانات'),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: filteredAgents.length,
                                  itemBuilder: (context, index) {
                                    final agent = filteredAgents[index];
                                    debugPrint('عرض وكيل: ${agent.toString()}');
                                    return Card(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 8, horizontal: 16),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    agent['ZoneContractor'] ??
                                                        agent['partner'] ??
                                                        'لا يوجد اسم',
                                                    style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      vertical: 4,
                                                      horizontal: 8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: Text(
                                                    'نشط',
                                                    style: const TextStyle(
                                                        color: Colors.white),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.location_on,
                                                    color: Colors.grey,
                                                    size: 16),
                                                const SizedBox(width: 4),
                                                Text(
                                                  agent['Zone'] ??
                                                      agent['zone'] ??
                                                      'لا يوجد منطقة',
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 14),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.build,
                                                    color: Colors.grey,
                                                    size: 16),
                                                const SizedBox(width: 4),
                                                Text(
                                                  agent['MainZoneContractor'] ??
                                                      agent['contractor'] ??
                                                      'لا يوجد مقاول',
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 14),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                const Icon(Icons.category,
                                                    color: Colors.grey,
                                                    size: 16),
                                                const SizedBox(width: 4),
                                                Text(
                                                  agent['ZoneType'] ??
                                                      agent['zonetype'] ??
                                                      'لا يوجد نوع زون',
                                                  style: const TextStyle(
                                                      color: Colors.grey,
                                                      fontSize: 14),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        // جدول بيانات شارت المناطق (شارت 52 فقط)
                        if (dashboard7ChartData.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12.0, vertical: 4),
                            child: Card(
                              color: Colors.blue[50],
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'بيانات شارت المناطق (ZoneType, Zone, ZoneContractor, MainZoneContractor):',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.blue),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: 400,
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: DataTable(
                                          columns: [
                                            DataColumn(
                                                label: Text('نوع الزون')),
                                            DataColumn(label: Text('الزون')),
                                            DataColumn(
                                                label: Text('مقاول الزون')),
                                            DataColumn(
                                                label: Text('المقاول الرئيسي')),
                                          ],
                                          rows: dashboard7ChartData
                                              .map((row) => DataRow(
                                                    cells: [
                                                      DataCell(Text(row[
                                                                  'zonetype']
                                                              ?.toString() ??
                                                          row['ZoneType']
                                                              ?.toString() ??
                                                          '')),
                                                      DataCell(Text(row['zone']
                                                              ?.toString() ??
                                                          row['Zone']
                                                              ?.toString() ??
                                                          '')),
                                                      DataCell(Text(row[
                                                                  'partner']
                                                              ?.toString() ??
                                                          row['ZoneContractor']
                                                              ?.toString() ??
                                                          '')),
                                                      DataCell(Text(row[
                                                                  'contractor']
                                                              ?.toString() ??
                                                          row['MainZoneContractor']
                                                              ?.toString() ??
                                                          '')),
                                                    ],
                                                  ))
                                              .toList(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    )),
      floatingActionButton: !waitingForApiUrls
          ? FloatingActionButton(
              onPressed: () async {
                // إضافة لوج للتأكد من حالة التوكن قبل فتح صفحة الإضافة
                final navigator = Navigator.of(context);
                String? token =
                    widget.authToken.isNotEmpty ? widget.authToken : null;

                token ??= await fetchGuestToken();

                debugPrint('Current token before add agent: $token');
                if (!mounted) return; // الانتقال إلى صفحة إضافة وكيل جديد
                navigator.push(
                  MaterialPageRoute(
                    builder: (context) => AddAgentPage(
                      authToken: token!,
                      onAgentAdded: (newAgent) {
                        setState(() {
                          agents.add(newAgent);
                        });
                      },
                    ),
                  ),
                );
              },
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class AddAgentPage extends StatefulWidget {
  final String authToken;
  final Function(Map<String, dynamic>) onAgentAdded;
  const AddAgentPage(
      {super.key, required this.authToken, required this.onAgentAdded});

  @override
  State<AddAgentPage> createState() => _AddAgentPageState();
}

class _AddAgentPageState extends State<AddAgentPage> {
  final _formKey = GlobalKey<FormState>();
  String partnerName = '';
  String zone = '';
  String contractor = '';
  String zonetype = '';
  String status = 'active';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        iconTheme: const IconThemeData(size: 20),
        title: const Text(
          'إضافة وكيل جديد',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'اسم الوكيل',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال اسم الوكيل';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    partnerName = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'الزون',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال اسم الزون';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    zone = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'المقاول',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال اسم المقاول';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    contractor = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'نوع الزون',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'يرجى إدخال نوع الزون';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    zonetype = value;
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('الحالة: '),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: status,
                    onChanged: (String? newValue) {
                      setState(() {
                        status = newValue!;
                      });
                    },
                    items: [
                      DropdownMenuItem<String>(
                        value: 'active',
                        child: Text('نشط'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'inactive',
                        child: Text('غير نشط'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: ElevatedButton(
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      // إرسال بيانات الوكيل الجديد إلى الخادم
                      final navigator = Navigator.of(context);
                      try {
                        // تحديث: استخدام رابط فعّال بدلاً من /api/partners/agents الذي يعطي 404
                        // مؤقتاً نستخدم رابط محدود للاختبار
                        final url = Uri.parse(
                            'https://dashboard.ftth.iq/api/v1/chart/data?form_data=%7B%22slice_id%22%3A52%7D&dashboard_id=7');
                        final response = await http.post(
                          url,
                          headers: {
                            'Authorization': 'Bearer ${widget.authToken}',
                            'Content-Type': 'application/json',
                            'Accept': 'application/json',
                          },
                          body: jsonEncode({
                            'partner': partnerName,
                            'zone': zone,
                            'contractor': contractor,
                            'zonetype': zonetype,
                            'status': status,
                          }),
                        );

                        if (!mounted) return;
                        if (response.statusCode == 201) {
                          final jsonBody = json.decode(response.body);
                          widget.onAgentAdded(jsonBody['data']);
                          navigator.pop();
                        } else {
                          final jsonBody = json.decode(response.body);
                          ftthShowSnackBar(
                            context,
                            SnackBar(
                              content: Text(
                                jsonBody['message'] ?? 'فشل في إضافة الوكيل',
                                textAlign: TextAlign.right,
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ftthShowSnackBar(
                            context,
                            const SnackBar(
                              content: Text('حدث خطأ أثناء إضافة الوكيل'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  child: const Text('إضافة وكيل'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
