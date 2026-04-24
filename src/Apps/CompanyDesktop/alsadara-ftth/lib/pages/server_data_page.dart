import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'ftth/fetch_server_data_page.dart';
import '../services/agents_auth_service.dart';
import '../services/auth_service.dart';

/// ═══════════════════════════════════════════════════════════════════
/// 🗄️ FTTH Server Data Service
/// خدمة لإدارة وجلب البيانات من سيرفر FTTH
/// ═══════════════════════════════════════════════════════════════════

class FtthServerDataService {
  // ══════════════════════════════════════════════════════════════════
  // 🔐 بيانات الاعتماد
  // ══════════════════════════════════════════════════════════════════
  static const String _partnerId = '2261175';

  // ══════════════════════════════════════════════════════════════════
  // 🌐 URLs - استخدام api.ftth.iq (يعمل مع authToken)
  // ══════════════════════════════════════════════════════════════════
  static const String _apiBaseUrl = 'https://api.ftth.iq/api';
  static const String _supersetBaseUrl = 'https://dashboard.ftth.iq';

  // ══════════════════════════════════════════════════════════════════
  // 🔑 authToken - يتم تمريره من الخارج
  // ══════════════════════════════════════════════════════════════════
  String? _authToken;

  // ══════════════════════════════════════════════════════════════════
  // 📁 مسارات الملفات المحلية
  // ══════════════════════════════════════════════════════════════════
  static const String localDataPath = r'C:\Sadara.API\ftth_data_export';
  static const String fullDataPath =
      r'C:\Sadara.API\ftth_data_export\08_Full_Data';
  static const String dashboardPath =
      r'C:\Sadara.API\ftth_data_export\07_Dashboard_Project';
  static const String rawDataPath =
      r'C:\Sadara.API\ftth_data_export\01_Raw_Data';

  // Singleton
  static final FtthServerDataService _instance =
      FtthServerDataService._internal();
  factory FtthServerDataService() => _instance;
  FtthServerDataService._internal();

  // ══════════════════════════════════════════════════════════════════
  // 🔑 تعيين Token من الخارج (من تسجيل الدخول الأساسي)
  // ══════════════════════════════════════════════════════════════════
  void setAuthToken(String token) {
    _authToken = token;
  }

  bool get hasToken => _authToken != null && _authToken!.isNotEmpty;

  // ══════════════════════════════════════════════════════════════════
  // 📊 جلب ملخص Dashboard من API
  // ══════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> fetchDashboardSummary() async {
    if (!hasToken) return null;

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET', '$_apiBaseUrl/partners/$_partnerId/dashboard/summary',
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint(
          'Dashboard summary error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Dashboard summary error');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 🗺️ جلب المناطق من api.ftth.iq
  // ══════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> fetchZones() async {
    if (!hasToken) return null;

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET', '$_apiBaseUrl/locations/zones',
      );

      debugPrint('Zones response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint('Zones error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Zones error');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 👥 جلب العملاء من api.ftth.iq
  // ══════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> fetchCustomers(
      {int page = 1, int pageSize = 100}) async {
    if (!hasToken) return null;

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        '$_apiBaseUrl/customers?pageNumber=$page&pageSize=$pageSize&sortCriteria.property=self.displayValue&sortCriteria.direction=asc',
      );

      debugPrint('Customers response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint('Customers error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Customers error');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 💰 جلب رصيد المحفظة من api.ftth.iq
  // ══════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> fetchWalletBalance() async {
    if (!hasToken) return null;

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET', '$_apiBaseUrl/partners/$_partnerId/wallets/balance',
      );

      debugPrint('Wallet response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint('Wallet error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Wallet error');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 📋 جلب سجل التدقيق من api.ftth.iq
  // ══════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> fetchAuditLogs(
      {int page = 1, int pageSize = 50}) async {
    if (!hasToken) return null;

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        '$_apiBaseUrl/audit-logs?pageNumber=$page&pageSize=$pageSize&sortCriteria.property=createdAt&sortCriteria.direction=desc',
      );

      debugPrint('Audit logs response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint('Audit logs error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Audit logs error');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 📝 جلب الاشتراكات من api.ftth.iq
  // ══════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> fetchSubscriptions(
      {int page = 1, int pageSize = 50}) async {
    if (!hasToken) return null;

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        '$_apiBaseUrl/subscriptions?pageNumber=$page&pageSize=$pageSize',
      );

      debugPrint('Subscriptions response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint(
          'Subscriptions error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Subscriptions error');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 🔧 Helper Methods
  // ══════════════════════════════════════════════════════════════════
  // _getAuthHeaders removed — now using AuthService.instance.authenticatedRequest()

  // ══════════════════════════════════════════════════════════════════
  // 📁 قراءة البيانات من الملفات المحلية
  // ══════════════════════════════════════════════════════════════════
  static Future<dynamic> loadLocalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content);
      }
    } catch (e) {
      print('Error loading local file');
    }
    return null;
  }

  static Future<List<dynamic>?> loadZonesWithCounts() async {
    return await loadLocalFile('$fullDataPath\\zones_with_user_counts.json')
        as List<dynamic>?;
  }

  static Future<List<dynamic>?> loadZones() async {
    return await loadLocalFile('$fullDataPath\\zones.json') as List<dynamic>?;
  }

  static Future<List<dynamic>?> loadCustomers() async {
    return await loadLocalFile('$fullDataPath\\customers_full.json')
        as List<dynamic>?;
  }

  static Future<List<dynamic>?> loadSubscriptions() async {
    return await loadLocalFile('$fullDataPath\\subscriptions_full.json')
        as List<dynamic>?;
  }

  static Future<Map<String, dynamic>?> loadDashboardSummary() async {
    return await loadLocalFile('$rawDataPath\\dashboard_summary.json')
        as Map<String, dynamic>?;
  }
}

/// ═══════════════════════════════════════════════════════════════════
/// 📊 صفحة مشروع Dashboard - عرض بيانات 07_Dashboard_Project
/// ═══════════════════════════════════════════════════════════════════
class DashboardProjectPage extends StatefulWidget {
  final String authToken;

  const DashboardProjectPage({super.key, required this.authToken});

  @override
  State<DashboardProjectPage> createState() => _DashboardProjectPageState();
}

class _DashboardProjectPageState extends State<DashboardProjectPage> {
  bool _isLoading = false;
  bool _isFetchingAllData = false; // جلب كل البيانات من API مباشرة
  bool _showRawData = false; // للتبديل بين العرض المنظم والخام
  String _errorMessage = '';
  String _fetchStatus = '';
  String _currentFileName = '';
  dynamic _currentData;
  List<FileSystemEntity> _dashboardFiles = [];
  String? _guestToken; // للمصادقة مع Dashboard API
  Map<String, dynamic> _allChartsData = {}; // بيانات كل الشارتات

  // ══════════════════════════════════════════════════════════════════
  // 📊 بيانات Dashboard الحية
  // ══════════════════════════════════════════════════════════════════
  static final _numFmt = NumberFormat('#,##0', 'ar');
  Map<String, dynamic>? _dashboardSummary;
  Map<String, dynamic>? _walletBalance;
  Map<String, dynamic>? _tasksSummary;
  List<Map<String, dynamic>>? _requestsSummary;
  List<Map<String, dynamic>>? _supersetReports;
  bool _isLoadingDashboard = true;

  // بيانات Superset Charts
  bool _isLoadingSuperset = false;
  Map<int, Map<String, dynamic>?> _slicesData = {};

  // ══════════════════════════════════════════════════════════════════
  // 📋 نظام السجلات (Logging)
  // ══════════════════════════════════════════════════════════════════
  final List<String> _logs = [];

  /// إضافة سجل جديد مع الوقت
  void _log(String message) {
    final timestamp = DateTime.now().toString().split('.')[0].split(' ')[1];
    final logEntry = '[$timestamp] $message';
    setState(() => _logs.add(logEntry));
    debugPrint(logEntry);
  }

  /// عرض شاشة السجلات
  void _showLogs() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.article, color: Colors.indigo),
            const SizedBox(width: 8),
            const Expanded(child: Text('سجل العمليات')),
            // زر مسح السجلات
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'مسح السجلات',
              onPressed: () {
                setState(() => _logs.clear());
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ تم مسح السجلات')),
                );
              },
            ),
            // زر نسخ السجلات
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.blue),
              tooltip: 'نسخ السجلات',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _logs.join('\n')));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ تم نسخ السجلات')),
                );
              },
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.7,
          child: _logs.isEmpty
              ? const Center(child: Text('لا توجد سجلات'))
              : ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    Color bgColor = Colors.grey[100]!;
                    Color textColor = Colors.black87;

                    if (log.contains('✅') || log.contains('نجاح')) {
                      bgColor = Colors.green[50]!;
                      textColor = Colors.green[800]!;
                    } else if (log.contains('❌') ||
                        log.contains('فشل') ||
                        log.contains('خطأ')) {
                      bgColor = Colors.red[50]!;
                      textColor = Colors.red[800]!;
                    } else if (log.contains('🔄') || log.contains('جاري')) {
                      bgColor = Colors.blue[50]!;
                      textColor = Colors.blue[800]!;
                    } else if (log.contains('⚠️') || log.contains('تحذير')) {
                      bgColor = Colors.orange[50]!;
                      textColor = Colors.orange[800]!;
                    } else if (log.contains('📤') || log.contains('URL')) {
                      bgColor = Colors.purple[50]!;
                      textColor = Colors.purple[800]!;
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        log,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: textColor,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardFiles();
    _initGuestToken();
    _fetchLiveDashboard();
  }

  /// تهيئة Guest Token عند فتح الصفحة
  Future<void> _initGuestToken() async {
    await _fetchGuestToken();
  }

  // ══════════════════════════════════════════════════════════════════
  // 📊 جلب بيانات Dashboard الحية من APIs
  // ══════════════════════════════════════════════════════════════════

  Future<void> _fetchLiveDashboard() async {
    setState(() => _isLoadingDashboard = true);
    _log('🔄 جلب بيانات Dashboard الحية...');

    await Future.wait([
      _fetchDashboardSummary(),
      _fetchWalletBalance(),
      _fetchTasksSummary(),
      _fetchRequestsSummary(),
      _fetchSupersetReports(),
      _fetchSupersetCharts(),
    ]);

    if (mounted) {
      setState(() => _isLoadingDashboard = false);
      _log('✅ تم جلب بيانات Dashboard');
    }
  }

  Future<void> _fetchDashboardSummary() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/partners/dashboard/summary?hierarchyLevel=0',
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) setState(() => _dashboardSummary = data['model'] ?? data);
      }
    } catch (e) {
      debugPrint('❌ Dashboard summary error: $e');
    }
  }

  Future<void> _fetchWalletBalance() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/partners/2261175/wallets/balance',
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) setState(() => _walletBalance = data['model'] ?? data);
      }
    } catch (e) {
      debugPrint('❌ Wallet balance error: $e');
    }
  }

  Future<void> _fetchTasksSummary() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/tasks/summary?hierarchyLevel=0',
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) setState(() => _tasksSummary = data['model'] ?? data);
      }
    } catch (e) {
      debugPrint('❌ Tasks summary error: $e');
    }
  }

  Future<void> _fetchRequestsSummary() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/requests/summary?hierarchyLevel=0',
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List? ?? [];
        if (mounted) {
          setState(() => _requestsSummary =
              items.map((e) => e as Map<String, dynamic>).toList());
        }
      }
    } catch (e) {
      debugPrint('❌ Requests summary error: $e');
    }
  }

  Future<void> _fetchSupersetReports() async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://dashboard.ftth.iq/superset/dashboard/report/list',
        headers: {
          'user-type': 'Partner',
          'Accept': 'application/json, text/plain, */*',
        },
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List? ?? [];
        if (mounted) {
          setState(() => _supersetReports =
              items.map((e) => e as Map<String, dynamic>).toList());
        }
      }
    } catch (e) {
      debugPrint('❌ Superset reports error: $e');
    }
  }

  /// تحميل بيانات Superset Charts من الملفات المحفوظة محلياً
  Future<void> _fetchSupersetCharts() async {
    try {
      if (mounted) setState(() => _isLoadingSuperset = true);

      final loaded = await _loadSupersetDataLocally();
      if (!loaded) {
        _log('📂 لا توجد بيانات محفوظة — اضغط 🌐 لجلب البيانات من صفحة السيرفر');
      }
    } catch (e) {
      _log('❌ Superset Charts error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingSuperset = false);
    }
  }

  /// حفظ بيانات Superset محلياً (بنفس صيغة fetch_server_data_page)
  Future<void> _saveSupersetDataLocally(Map<int, Map<String, dynamic>?> data) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/ftth_data_$timestamp.json');

      final charts = <Map<String, dynamic>>[];
      for (var entry in data.entries) {
        if (entry.value != null) {
          charts.add({
            'type': 'slice_${entry.key}',
            'url': 'dashboard_api_slice_${entry.key}',
            'data': {
              'result': [
                {'data': entry.value!['data'] ?? []}
              ]
            },
            'colnames': entry.value!['colnames'],
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
        }
      }

      await file.writeAsString(json.encode({
        'timestamp': timestamp,
        'charts_count': charts.length,
        'charts': charts,
      }));
      _log('💾 تم حفظ البيانات: ${file.path}');
    } catch (e) {
      _log('⚠️ فشل الحفظ المحلي: $e');
    }
  }

  /// تحميل بيانات Superset المحفوظة محلياً من أحدث ملف ftth_data_*.json
  Future<bool> _loadSupersetDataLocally() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('ftth_data_') && f.path.endsWith('.json'))
          .toList();

      if (files.isEmpty) return false;

      // أحدث ملف
      files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      final latestFile = files.first;
      final content = await latestFile.readAsString();
      final parsed = json.decode(content) as Map<String, dynamic>;
      final charts = parsed['charts'] as List? ?? [];
      final timestamp = parsed['timestamp'] as String? ?? '';

      if (charts.isEmpty) return false;

      final results = <int, Map<String, dynamic>?>{};
      for (final chart in charts) {
        // استخراج slice_id من url: "dashboard_api_slice_52"
        final url = chart['url'] as String? ?? '';
        final match = RegExp(r'slice_(\d+)').firstMatch(url);
        if (match == null) continue;
        final sliceId = int.parse(match.group(1)!);

        // تحويل البيانات لصيغة _slicesData
        final dataResult = chart['data']?['result'] as List?;
        List dataRows = [];
        if (dataResult != null && dataResult.isNotEmpty) {
          final firstResult = dataResult[0] as Map<String, dynamic>?;
          dataRows = firstResult?['data'] as List? ?? [];
        }
        final colnames = chart['colnames'] as List?;

        results[sliceId] = {
          'data': dataRows,
          'colnames': colnames ?? [],
          'rowcount': dataRows.length,
        };
      }

      if (results.isEmpty) return false;

      if (mounted) {
        setState(() => _slicesData = results);
        _log('📂 تم تحميل ${results.length} slice من البيانات المحفوظة ($timestamp)');
      }
      return true;
    } catch (e) {
      _log('⚠️ فشل تحميل البيانات المحلية: $e');
      return false;
    }
  }

  /// تحميل قائمة ملفات Dashboard Project
  Future<void> _loadDashboardFiles() async {
    setState(() => _isLoading = true);

    try {
      final dir = Directory(FtthServerDataService.dashboardPath);
      if (await dir.exists()) {
        // عرض الكل + ملف all_zones_detailed.json فقط من ملفات المناطق
        final files = await dir
            .list(recursive: true)
            .where((f) =>
                f.path.endsWith('.json') &&
                (!f.path.toLowerCase().contains('zone') ||
                    f.path.contains('all_zones_detailed')))
            .toList();
        setState(() {
          _dashboardFiles = files;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'مجلد Dashboard غير موجود';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ';
        _isLoading = false;
      });
    }
  }

  /// عرض رسالة خطأ
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('خطأ'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  /// تحميل ملف محدد
  Future<void> _loadFile(String filePath, String fileName) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _currentFileName = fileName;
    });

    try {
      final data = await FtthServerDataService.loadLocalFile(filePath);
      setState(() {
        _currentData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في قراءة الملف';
        _isLoading = false;
      });
    }
  }

  /// جلب Guest Token من Dashboard API
  Future<void> _fetchGuestToken() async {
    try {
      _log('🔄 بدء جلب Guest Token...');
      _log('📤 URL: https://dashboard.ftth.iq/api/v1/security/guest_token/');

      // محاولة 1: استخدام authToken الحالي
      _log('🔄 محاولة 1: استخدام authToken الحالي...');
      var token = await AgentsAuthService.fetchGuestToken(
        authToken: widget.authToken.isNotEmpty ? widget.authToken : null,
      );

      // محاولة 2: استخدام التوكن المخزن
      if (token == null) {
        _log('⚠️ محاولة 1 فشلت - محاولة 2: استخدام Token المخزن...');
        token = await AgentsAuthService.getStoredGuestToken();
      }

      // محاولة 3: تسجيل الدخول
      if (token == null) {
        _log('⚠️ محاولة 2 فشلت - محاولة 3: تسجيل دخول viewer...');
        _log('📤 URL: https://dashboard.ftth.iq/login');
        final loginResult = await AgentsAuthService.login('viewer', 'viewer');
        _log(
            '📋 نتيجة تسجيل الدخول: ${loginResult.isSuccess ? "نجاح" : "فشل"}');
        if (loginResult.isSuccess && loginResult.accessToken != null) {
          token = await AgentsAuthService.fetchGuestToken(
            authToken: loginResult.accessToken,
          );
        }
      }

      if (token != null) {
        setState(() => _guestToken = token);
        _log('✅ تم جلب Guest Token بنجاح (${token.length} حرف)');
        _log('📋 Token: ${token.substring(0, 50)}...');
      } else {
        _log('❌ فشل نهائي في جلب Guest Token');
      }
    } catch (e) {
      _log('❌ خطأ في جلب Guest Token');
    }
  }

  /// تحميل البيانات من الملفات المحلية (Python output)
  Future<void> _loadFromLocalFiles() async {
    setState(() {
      _isFetchingAllData = true;
      _fetchStatus = 'جاري تحميل البيانات المحلية...';
    });

    try {
      // مسار ملفات Python
      const localDataPath =
          r'C:\Sadara.API\ftth_data_export\07_Dashboard_Project\data';

      // محاولة قراءة parsed_charts.json أو chart_data.json
      final parsedChartsFile = File('$localDataPath\\parsed_charts.json');
      final chartDataFile = File('$localDataPath\\chart_data.json');

      Map<String, dynamic>? localData;
      String sourceFile = '';

      if (await parsedChartsFile.exists()) {
        final content = await parsedChartsFile.readAsString();
        localData = jsonDecode(content) as Map<String, dynamic>;
        sourceFile = 'parsed_charts.json';
      } else if (await chartDataFile.exists()) {
        final content = await chartDataFile.readAsString();
        localData = jsonDecode(content) as Map<String, dynamic>;
        sourceFile = 'chart_data.json';
      }

      if (localData == null || localData.isEmpty) {
        throw Exception('لم يتم العثور على ملفات البيانات المحلية');
      }

      // تحويل البيانات للتنسيق المطلوب
      final fetchedData = <String, dynamic>{};
      int chartCount = 0;

      for (final entry in localData.entries) {
        final chartKey = entry.key;
        final chartData = entry.value as Map<String, dynamic>;

        fetchedData[chartKey] = {
          'slice_id': chartKey,
          'description': chartData['label'] ?? chartKey,
          'columns': chartData['columns'] ?? [],
          'rowcount': chartData['row_count'] ?? chartData['data']?.length ?? 0,
          'data': chartData['data'] ?? [],
          'source': 'local_file',
          'source_file': sourceFile,
        };
        chartCount++;
      }

      setState(() {
        _allChartsData = fetchedData;
        _isFetchingAllData = false;
        _fetchStatus = '';
      });

      // عرض النتائج
      if (mounted) {
        _showLocalDataDialog(fetchedData, sourceFile, chartCount);
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل البيانات المحلية');
      setState(() {
        _isFetchingAllData = false;
        _fetchStatus = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// عرض نافذة البيانات المحلية
  void _showLocalDataDialog(
      Map<String, dynamic> data, String sourceFile, int chartCount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.folder_open, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('📂 البيانات المحلية'),
            const Spacer(),
            Chip(
              label: Text('$chartCount charts'),
              backgroundColor: Colors.blue[50],
            ),
          ],
        ),
        content: SizedBox(
          width: min(700, MediaQuery.of(context).size.width * 0.85),
          height: min(500, MediaQuery.of(context).size.height * 0.6),
          child: Column(
            children: [
              // معلومات المصدر
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'المصدر: $sourceFile\nتم تحميل البيانات من ملفات Python المحلية',
                        style: TextStyle(color: Colors.blue[800]),
                      ),
                    ),
                  ],
                ),
              ),
              // قائمة الشارتات
              Expanded(
                child: ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final entry = data.entries.elementAt(index);
                    final chartInfo = entry.value as Map<String, dynamic>;
                    final columns = chartInfo['columns'] as List? ?? [];
                    final rowCount = chartInfo['rowcount'] ?? 0;

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue[100],
                          child: Text('${index + 1}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.blue[700])),
                        ),
                        title: Text(entry.key,
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${chartInfo['description']} | ${columns.length} عمود | $rowCount سجل',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        children: [
                          if (columns.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('الأعمدة:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: columns
                                        .take(10)
                                        .map((col) => Chip(
                                              label: Text(col.toString(),
                                                  style: const TextStyle(
                                                      fontSize: 11)),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ))
                                        .toList(),
                                  ),
                                  if (columns.length > 10)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                          '... و ${columns.length - 10} عمود آخر',
                                          style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12)),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: const JsonEncoder.withIndent('  ').convert(data),
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ تم نسخ البيانات')),
              );
            },
            child: const Text('📋 نسخ'),
          ),
          TextButton(
            onPressed: () async {
              final dir = Directory(FtthServerDataService.dashboardPath);
              if (!await dir.exists()) {
                await dir.create(recursive: true);
              }
              final timestamp = DateTime.now()
                  .toIso8601String()
                  .replaceAll(':', '-')
                  .split('.')[0];
              final filePath =
                  '${FtthServerDataService.dashboardPath}\\local_charts_$timestamp.json';
              final file = File(filePath);
              await file.writeAsString(
                  const JsonEncoder.withIndent('  ').convert(data));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ تم الحفظ: $filePath')),
                );
                Navigator.pop(context);
                _loadDashboardFiles();
              }
            },
            child: const Text('💾 حفظ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// عرض نافذة تسجيل الدخول للداشبورد
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
              Icon(Icons.login, color: Colors.indigo),
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
                          final newGuestToken =
                              await AgentsAuthService.fetchGuestToken(
                            authToken: result.accessToken!,
                          );

                          if (newGuestToken != null) {
                            setState(() {
                              _guestToken = newGuestToken;
                            });
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ تم تسجيل الدخول بنجاح'),
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
                            content: Text('خطأ'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      } finally {
                        setDialogState(() => isLoggingIn = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: isLoggingIn
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('دخول'),
            ),
          ],
        ),
      ),
    );
  }

  /// جلب كل البيانات من جميع الشارتات بدون فلاتر - مباشرة من API
  Future<void> _fetchAllDataWithoutFilters() async {
    // جلب Guest Token إذا لم يكن موجوداً
    if (_guestToken == null) {
      setState(() {
        _fetchStatus = 'جلب رمز المصادقة...';
        _isFetchingAllData = true;
      });
      await _fetchGuestToken();
    }

    if (_guestToken == null) {
      setState(() => _isFetchingAllData = false);
      if (mounted) {
        // عرض نافذة تسجيل الدخول
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('فشل في المصادقة - يرجى تسجيل الدخول'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'تسجيل الدخول',
              textColor: Colors.white,
              onPressed: _showLoginDialog,
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _isFetchingAllData = true;
      _fetchStatus = 'جاري جلب كل البيانات...';
    });

    try {
      _log('═══════════════════════════════════════════');
      _log('🚀 بدء جلب كل البيانات من Dashboard API');
      _log('═══════════════════════════════════════════');
      _log('📋 Guest Token: ${_guestToken!.substring(0, 30)}...');

      // قائمة الشارتات المطلوب جلبها مع أوصافها
      final chartsToFetch = [
        {'slice_id': 52, 'name': 'zones_detailed', 'desc': 'تفاصيل المناطق'},
        {
          'slice_id': 48,
          'name': 'timeseries_weekly',
          'desc': 'السلسلة الأسبوعية'
        },
        {
          'slice_id': 51,
          'name': 'timeseries_monthly',
          'desc': 'السلسلة الشهرية'
        },
        {'slice_id': 46, 'name': 'timeseries_46', 'desc': 'سلسلة زمنية'},
        {'slice_id': 34, 'name': 'users_34', 'desc': 'إحصائيات المستخدمين'},
        {'slice_id': 35, 'name': 'users_35', 'desc': 'إحصائيات المستخدمين 2'},
        {'slice_id': 36, 'name': 'users_36', 'desc': 'إحصائيات المستخدمين 3'},
        {'slice_id': 37, 'name': 'users_37', 'desc': 'إحصائيات المستخدمين 4'},
        {'slice_id': 38, 'name': 'users_38', 'desc': 'إحصائيات المستخدمين 5'},
      ];

      _log('📋 عدد الشارتات المطلوبة: ${chartsToFetch.length}');

      final fetchedData = <String, dynamic>{};
      int successCount = 0;
      int failCount = 0;

      for (var i = 0; i < chartsToFetch.length; i++) {
        final chart = chartsToFetch[i];
        if (!mounted) break;

        setState(() {
          _fetchStatus =
              'جلب ${chart['desc']} (${i + 1}/${chartsToFetch.length})...';
        });

        try {
          final sliceId = chart['slice_id'];
          final chartName = chart['name'];
          _log(
              '🔄 [${i + 1}/${chartsToFetch.length}] جلب $chartName (slice_id: $sliceId)...');
          _log('📤 URL: https://dashboard.ftth.iq/api/v1/chart/data');
          _log('📤 Payload: form_data.slice_id=$sliceId, dashboard_id=7');

          // إنشاء payload بدون فلاتر
          final requestPayload = {
            'form_data': {
              'slice_id': chart['slice_id'],
              // إزالة أي فلاتر native
              'extra_filters': [],
              'native_filters': [],
              'extra_form_data': {},
            },
            'dashboard_id': 7,
            'slice_id': chart['slice_id'],
          };

          final chartData = await AgentsAuthService.fetchChartData(
            chart['slice_id'] as int,
            7,
            guestToken: _guestToken,
            authToken: widget.authToken.isNotEmpty ? widget.authToken : null,
            requestPayload: requestPayload,
          );

          if (chartData != null) {
            final rowCount = (chartData['data'] as List?)?.length ?? 0;
            fetchedData[chart['name'] as String] = {
              'slice_id': chart['slice_id'],
              'description': chart['desc'],
              'data': chartData['data'],
              'colnames': chartData['colnames'],
              'coltypes': chartData['coltypes'],
              'rowcount': rowCount,
            };
            successCount++;
            _log('✅ ${chart['name']}: $rowCount سجل');
            _log(
                '   الأعمدة: ${chartData['colnames']?.toString() ?? "غير محدد"}');
          } else {
            failCount++;
            _log('❌ ${chart['name']}: فشل - البيانات فارغة');
          }
        } catch (e) {
          failCount++;
          _log('❌ ${chart['name']}: خطأ - $e');
        }
      }

      _log('═══════════════════════════════════════════');
      _log('📊 ملخص الجلب: $successCount نجاح، $failCount فشل');
      _log(
          '📊 إجمالي السجلات: ${fetchedData.values.fold<int>(0, (sum, item) => sum + ((item['rowcount'] ?? 0) as int))}');
      _log('═══════════════════════════════════════════');

      setState(() {
        _allChartsData = fetchedData;
        _isFetchingAllData = false;
        _fetchStatus =
            '✅ تم جلب $successCount شارت${failCount > 0 ? ' (فشل: $failCount)' : ''}';
      });

      // عرض نتيجة الجلب
      if (mounted) {
        _showAllDataDialog(fetchedData, successCount, failCount);
      }
    } catch (e) {
      _log('❌ خطأ عام في جلب البيانات');
      setState(() {
        _isFetchingAllData = false;
        _fetchStatus = '❌ خطأ';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب البيانات'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // عرض حوار نتائج جلب كل البيانات
  void _showAllDataDialog(Map<String, dynamic> data, int success, int fail) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              success > 0 ? Icons.check_circle : Icons.error,
              color: success > 0 ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            const Text('نتائج جلب البيانات'),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ملخص
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('$success',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.green)),
                        const Text('نجاح',
                            style: TextStyle(color: Colors.green)),
                      ],
                    ),
                    Column(
                      children: [
                        Text('$fail',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.red)),
                        const Text('فشل', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                            '${data.values.fold<int>(0, (sum, item) => sum + ((item['rowcount'] ?? 0) as int))}',
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue)),
                        const Text('إجمالي السجلات',
                            style: TextStyle(color: Colors.blue)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // قائمة الشارتات
              const Text('تفاصيل الشارتات:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final entry = data.entries.elementAt(index);
                    final chartInfo = entry.value as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo[100],
                          child: Text('${chartInfo['slice_id']}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.indigo[700])),
                        ),
                        title: Text(entry.key),
                        subtitle: Text(chartInfo['description'] ?? ''),
                        trailing: Chip(
                          label: Text('${chartInfo['rowcount']} سجل'),
                          backgroundColor: Colors.green[50],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // نسخ البيانات
              Clipboard.setData(ClipboardData(
                text: const JsonEncoder.withIndent('  ').convert(data),
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ تم نسخ البيانات')),
              );
            },
            child: const Text('📋 نسخ'),
          ),
          TextButton(
            onPressed: () async {
              // حفظ كملف JSON
              final dir = Directory(FtthServerDataService.dashboardPath);
              if (!await dir.exists()) {
                await dir.create(recursive: true);
              }
              final timestamp = DateTime.now()
                  .toIso8601String()
                  .replaceAll(':', '-')
                  .split('.')[0];
              final filePath =
                  '${FtthServerDataService.dashboardPath}\\all_charts_unfiltered_$timestamp.json';
              final file = File(filePath);
              await file.writeAsString(
                  const JsonEncoder.withIndent('  ').convert(data));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ تم الحفظ: $filePath')),
                );
                // إعادة تحميل الملفات
                _loadDashboardFiles();
              }
            },
            child: const Text('💾 حفظ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 📊 واجهة Dashboard الحية
  // ══════════════════════════════════════════════════════════════════

  Widget _buildLiveDashboard() {
    if (_isLoadingDashboard) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري تحميل البيانات...'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchLiveDashboard,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Superset Charts (native Flutter)
          _buildSupersetChartsSection(),
        ],
      ),
    );
  }


  Widget _buildWalletCards() {
    final balance = _walletBalance?['balance'] ?? 0;
    final commission = _walletBalance?['commission'] ?? 0;
    return Row(
      children: [
        Expanded(
          child: _statCard(
            'الرصيد',
            '${_numFmt.format(balance)} د.ع',
            Icons.account_balance_wallet,
            const Color(0xFF1565C0),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            'العمولة',
            '${_numFmt.format(commission)} د.ع',
            Icons.monetization_on,
            const Color(0xFF2E7D32),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerCards() {
    final c = _dashboardSummary?['customers'];
    final active = c?['totalActive'] ?? 0;
    final inactive = c?['totalInactive'] ?? 0;
    final total = c?['totalCount'] ?? 0;
    final expiring = c?['totalExpiring'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('  العملاء',
            style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700])),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _miniCard('الإجمالي', total, Icons.people,
                    const Color(0xFF37474F))),
            const SizedBox(width: 8),
            Expanded(
                child: _miniCard('نشط', active, Icons.check_circle,
                    const Color(0xFF2E7D32))),
            const SizedBox(width: 8),
            Expanded(
                child: _miniCard('منتهي', inactive, Icons.cancel,
                    const Color(0xFFC62828))),
            const SizedBox(width: 8),
            Expanded(
                child: _miniCard('ينتهي قريباً', expiring,
                    Icons.warning_amber, const Color(0xFFEF6C00))),
          ],
        ),
      ],
    );
  }

  Widget _buildSubscriptionCards() {
    final s = _dashboardSummary?['subscriptions'];
    final active = s?['totalActive'] ?? 0;
    final expiring = s?['totalExpiring'] ?? 0;
    final expired = s?['totalExpired'] ?? 0;
    final trial = s?['totalTrial'] ?? 0;
    final online = s?['totalOnline'] ?? 0;
    final offline = s?['totalOffline'] ?? 0;
    final total = s?['totalCount'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('  الاشتراكات',
            style: GoogleFonts.cairo(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700])),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _miniCard('الإجمالي', total, Icons.router,
                    const Color(0xFF37474F))),
            const SizedBox(width: 8),
            Expanded(
                child: _miniCard('نشط', active, Icons.wifi,
                    const Color(0xFF2E7D32))),
            const SizedBox(width: 8),
            Expanded(
                child: _miniCard('ينتهي قريباً', expiring,
                    Icons.access_time, const Color(0xFFEF6C00))),
            const SizedBox(width: 8),
            Expanded(
                child: _miniCard('منتهي', expired, Icons.wifi_off,
                    const Color(0xFFC62828))),
            if (trial > 0) ...[
              const SizedBox(width: 8),
              Expanded(
                  child: _miniCard('تجريبي', trial, Icons.science,
                      const Color(0xFF6A1B9A))),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _miniCard('متصل (Online)', online,
                    Icons.signal_wifi_4_bar, const Color(0xFF00695C))),
            const SizedBox(width: 8),
            Expanded(
                child: _miniCard('غير متصل (Offline)', offline,
                    Icons.signal_wifi_off, const Color(0xFF78909C))),
            const Spacer(),
            const Spacer(),
          ],
        ),
      ],
    );
  }

  Widget _buildChartsRow() {
    final c = _dashboardSummary?['customers'];
    final s = _dashboardSummary?['subscriptions'];
    if (c == null && s == null) return const SizedBox.shrink();

    return SizedBox(
      height: 280,
      child: Row(
        children: [
          if (c != null)
            Expanded(child: _buildPieChartCard('توزيع العملاء', [
              _PieItem('نشط', (c['totalActive'] ?? 0).toDouble(),
                  const Color(0xFF4CAF50)),
              _PieItem('منتهي', (c['totalInactive'] ?? 0).toDouble(),
                  const Color(0xFFE53935)),
            ])),
          const SizedBox(width: 12),
          if (s != null)
            Expanded(child: _buildPieChartCard('حالة الاشتراكات', [
              _PieItem('نشط', (s['totalActive'] ?? 0).toDouble(),
                  const Color(0xFF4CAF50)),
              _PieItem('ينتهي قريباً', (s['totalExpiring'] ?? 0).toDouble(),
                  const Color(0xFFFF9800)),
              _PieItem('منتهي', (s['totalExpired'] ?? 0).toDouble(),
                  const Color(0xFFE53935)),
            ])),
          const SizedBox(width: 12),
          if (s != null)
            Expanded(child: _buildBarChartCard('حالة الاتصال', [
              _BarItem('متصل', (s['totalOnline'] ?? 0).toDouble(),
                  const Color(0xFF00897B)),
              _BarItem('غير متصل', (s['totalOffline'] ?? 0).toDouble(),
                  const Color(0xFF78909C)),
            ])),
        ],
      ),
    );
  }

  Widget _buildPieChartCard(String title, List<_PieItem> items) {
    final total = items.fold<double>(0, (sum, e) => sum + e.value);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.cairo(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(PieChartData(
                      sections: items
                          .where((e) => e.value > 0)
                          .map((e) => PieChartSectionData(
                                color: e.color,
                                value: e.value,
                                title:
                                    '${(e.value / total * 100).toStringAsFixed(0)}%',
                                radius: 50,
                                titleStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ))
                          .toList(),
                      centerSpaceRadius: 30,
                      sectionsSpace: 2,
                    )),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: items
                          .map((e) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                            color: e.color,
                                            shape: BoxShape.circle)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                        child: Text(e.label,
                                            style: GoogleFonts.cairo(
                                                fontSize: 11))),
                                    Text(_numFmt.format(e.value.toInt()),
                                        style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChartCard(String title, List<_BarItem> items) {
    final maxVal =
        items.fold<double>(0, (m, e) => e.value > m ? e.value : m) * 1.2;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.cairo(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, gI, rod, rI) => BarTooltipItem(
                      _numFmt.format(rod.toY.toInt()),
                      GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, _) {
                        final i = val.toInt();
                        if (i < 0 || i >= items.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(items[i].label,
                            style: GoogleFonts.cairo(fontSize: 11));
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: items
                    .asMap()
                    .entries
                    .map((e) => BarChartGroupData(
                          x: e.key,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.value,
                              color: e.value.color,
                              width: 40,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                topRight: Radius.circular(6),
                              ),
                            ),
                          ],
                          showingTooltipIndicators: [0],
                        ))
                    .toList(),
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTasksAndRequestsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // بطاقة المهام
        if (_tasksSummary != null)
          Expanded(
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.task_alt,
                            color: Color(0xFF1565C0), size: 20),
                        const SizedBox(width: 8),
                        Text('المهام',
                            style: GoogleFonts.cairo(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _taskRow('مفتوحة', _tasksSummary!['totalOpen'],
                        const Color(0xFFEF6C00)),
                    _taskRow('مكتملة', _tasksSummary!['totalCompleted'],
                        const Color(0xFF2E7D32)),
                    _taskRow('مستحقة اليوم', _tasksSummary!['totalDueToday'],
                        const Color(0xFFC62828)),
                    _taskRow('مستحقة هذا الأسبوع',
                        _tasksSummary!['totalDueThisWeek'],
                        const Color(0xFF6A1B9A)),
                    const Divider(),
                    _taskRow('الإجمالي', _tasksSummary!['totalCount'],
                        const Color(0xFF37474F),
                        bold: true),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(width: 12),
        // بطاقة الطلبات
        if (_requestsSummary != null)
          Expanded(
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.assignment,
                            color: Color(0xFF00695C), size: 20),
                        const SizedBox(width: 8),
                        Text('الطلبات',
                            style: GoogleFonts.cairo(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._requestsSummary!.map((r) {
                      final name = _translateRequestType(
                          r['displayValue'] ?? r['type']?['displayValue'] ?? '');
                      final count = r['totalOpen'] ?? 0;
                      return _taskRow(name, count, const Color(0xFF00695C));
                    }),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSupersetChartsSection() {
    if (_isLoadingSuperset) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text('جاري تحميل تحليلات Superset...',
                  style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    final hasAnyData = _slicesData.values.any((v) => v != null);
    if (_slicesData.isEmpty || !hasAnyData) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_off, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('لم يتم تحميل بيانات Superset',
                        style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey)),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text('إعادة المحاولة',
                        style: GoogleFonts.cairo(fontSize: 12)),
                    onPressed: _fetchSupersetCharts,
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.language, size: 18),
                    label: Text('جلب من السيرفر',
                        style: GoogleFonts.cairo(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FetchServerDataPage(authToken: widget.authToken),
                        ),
                      );
                      // بعد الرجوع، إعادة تحميل البيانات المحلية
                      _fetchSupersetCharts();
                    },
                  ),
                ],
              ),
              // عرض كل السجلات للتشخيص
              if (_logs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _logs
                        .toList()
                        .reversed
                        .take(15)
                        .toList()
                        .reversed
                        .map((l) => Text(l,
                            style: const TextStyle(fontSize: 10, fontFamily: 'monospace')))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // العنوان
        Row(
          children: [
            const Icon(Icons.analytics, color: Color(0xFF6A1B9A), size: 22),
            const SizedBox(width: 8),
            Text('تحليلات Superset',
                style: GoogleFonts.cairo(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: 'تحديث بيانات Superset',
              onPressed: _fetchSupersetCharts,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // بطاقات KPI (slices 34-38)
        _buildSupersetStatCards(),

        const SizedBox(height: 16),

        // مخططات المناطق
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth > 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildZonesBarChart()),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildZonesTable()),
              ],
            );
          }
          return Column(
            children: [
              _buildZonesBarChart(),
              const SizedBox(height: 16),
              _buildZonesTable(),
            ],
          );
        }),

        const SizedBox(height: 16),

        // مخطط خطي يومي (slice 48)
        _buildTimeSeriesChart(),

        const SizedBox(height: 16),

        // مخطط خطي طويل المدى (slice 51)
        _buildLongTermChart(),
      ],
    );
  }

  /// بطاقات KPI من slices 34-38 (COUNT_DISTINCT(userId))
  Widget _buildSupersetStatCards() {
    final statSlices = {
      34: 'إجمالي المستخدمين',
      35: 'النشطين',
      36: 'غير النشطين',
      37: 'المنتهيين',
      38: 'الجدد',
    };
    final colors = [
      const Color(0xFF1565C0), // أزرق — إجمالي
      const Color(0xFF2E7D32), // أخضر — نشط
      const Color(0xFFE65100), // برتقالي — غير نشط
      const Color(0xFFC62828), // أحمر — منتهي
      const Color(0xFF00838F), // تيل — جديد
    ];
    final icons = [
      Icons.people,
      Icons.check_circle,
      Icons.pause_circle,
      Icons.cancel,
      Icons.person_add,
    ];

    final entries = statSlices.entries.toList();
    final hasData = entries.any((e) => _slicesData[e.key] != null);
    if (!hasData) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: List.generate(entries.length, (i) {
        final sliceId = entries[i].key;
        final label = entries[i].value;
        final data = _slicesData[sliceId];
        int? value;
        if (data != null) {
          final rows = data['data'] as List?;
          if (rows != null && rows.isNotEmpty) {
            final firstRow = rows[0] as Map<String, dynamic>;
            value = firstRow['COUNT_DISTINCT(userId)'] as int? ??
                int.tryParse(firstRow.values.first?.toString() ?? '');
          }
        }
        return SizedBox(
          width: 155,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [colors[i], colors[i].withOpacity(0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icons[i], color: Colors.white70, size: 18),
                  const SizedBox(height: 4),
                  Text(
                    value != null ? _numFmt.format(value) : '—',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(label,
                      style: GoogleFonts.cairo(
                          fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  /// مخطط أعمدة مكدس لإحصائيات المناطق (slice 46)
  Widget _buildZonesBarChart() {
    final data67 = _slicesData[46];
    if (data67 == null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('لا توجد بيانات إحصائيات المناطق',
              style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey)),
        ),
      );
    }

    final rows = (data67['data'] as List?) ?? [];
    // أخذ أول 12 منطقة لتجنب الازدحام
    final displayRows = rows.take(12).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: Color(0xFF6A1B9A), size: 20),
                const SizedBox(width: 8),
                Text('إحصائيات المناطق',
                    style: GoogleFonts.cairo(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${rows.length} منطقة',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 16),
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(const Color(0xFF4CAF50), 'نشط'),
                const SizedBox(width: 16),
                _legendDot(const Color(0xFFFF9800), 'غير نشط'),
                const SizedBox(width: 16),
                _legendDot(const Color(0xFFF44336), 'منتهي'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _getMaxZoneValue(displayRows) * 1.15,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipMargin: 4,
                    getTooltipItem: (group, gI, rod, rI) {
                      final zone = gI < displayRows.length
                          ? (displayRows[gI] as Map)['Zone']?.toString() ?? ''
                          : '';
                      final labels = ['نشط', 'غير نشط', 'منتهي'];
                      return BarTooltipItem(
                        '$zone\n${labels[rI]}: ${_numFmt.format(rod.toY.toInt())}',
                        GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      getTitlesWidget: (val, _) {
                        final i = val.toInt();
                        if (i < 0 || i >= displayRows.length) {
                          return const SizedBox.shrink();
                        }
                        final zone =
                            (displayRows[i] as Map)['Zone']?.toString() ?? '';
                        // اختصار اسم المنطقة
                        final short =
                            zone.length > 8 ? '${zone.substring(0, 8)}..' : zone;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(short,
                              style: GoogleFonts.cairo(fontSize: 9),
                              textAlign: TextAlign.center),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (val, _) => Text(
                          _numFmt.format(val.toInt()),
                          style: GoogleFonts.cairo(fontSize: 9)),
                    ),
                  ),
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: _getMaxZoneValue(displayRows) / 4),
                borderData: FlBorderData(show: false),
                barGroups: displayRows.asMap().entries.map((e) {
                  final row = e.value as Map;
                  final active = (row['Active'] ?? 0).toDouble();
                  final inactive = (row['Inactive'] ?? 0).toDouble();
                  final expired = (row['Expired'] ?? 0).toDouble();
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: active + inactive + expired,
                        width: 18,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                        rodStackItems: [
                          BarChartRodStackItem(
                              0, active, const Color(0xFF4CAF50)),
                          BarChartRodStackItem(
                              active, active + inactive, const Color(0xFFFF9800)),
                          BarChartRodStackItem(active + inactive,
                              active + inactive + expired, const Color(0xFFF44336)),
                        ],
                        color: Colors.transparent,
                      ),
                    ],
                  );
                }).toList(),
              )),
            ),
          ],
        ),
      ),
    );
  }

  double _getMaxZoneValue(List displayRows) {
    double maxVal = 0;
    for (var row in displayRows) {
      final r = row as Map;
      final total = ((r['Active'] ?? 0) as num).toDouble() +
          ((r['Inactive'] ?? 0) as num).toDouble() +
          ((r['Expired'] ?? 0) as num).toDouble();
      if (total > maxVal) maxVal = total;
    }
    return maxVal > 0 ? maxVal : 100;
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.cairo(fontSize: 11)),
      ],
    );
  }

  /// جدول تفاصيل المناطق (slice 52)
  Widget _buildZonesTable() {
    final data52 = _slicesData[52];
    if (data52 == null) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('لا توجد بيانات تفاصيل المناطق',
              style: GoogleFonts.cairo(fontSize: 13, color: Colors.grey)),
        ),
      );
    }

    final rows = (data52['data'] as List?) ?? [];
    // حساب إحصائيات النوع
    int mainCount = 0;
    int subCount = 0;
    for (var row in rows) {
      final r = row as Map;
      final type = r['ZoneType']?.toString() ?? '';
      if (type == 'Main') {
        mainCount++;
      } else {
        subCount++;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شريط العنوان
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF00695C),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('جدول المناطق: ${rows.length} منطقة',
                    style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ],
            ),
          ),
          // إحصائيات رئيسية/فرعية
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey[100],
            child: Row(
              children: [
                const Icon(Icons.home, color: Color(0xFF00695C), size: 16),
                const SizedBox(width: 4),
                Text('رئيسية: $mainCount',
                    style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00695C))),
                const SizedBox(width: 20),
                const Icon(Icons.apartment, color: Color(0xFFE65100), size: 16),
                const SizedBox(width: 4),
                Text('فرعية: $subCount',
                    style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFE65100))),
              ],
            ),
          ),
          // الجدول
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              height: 400,
              child: SingleChildScrollView(
                child: DataTable(
                  columnSpacing: 20,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 52,
                  headingRowHeight: 40,
                  headingTextStyle: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF00695C)),
                  headingRowColor:
                      WidgetStatePropertyAll(Colors.teal[50]),
                  columns: const [
                    DataColumn(label: Text('المنطقة')),
                    DataColumn(label: Text('النوع')),
                    DataColumn(label: Text('المقاول')),
                    DataColumn(label: Text('المقاول الرئيسي')),
                  ],
                  rows: rows.asMap().entries.map((e) {
                    final row = e.value as Map;
                    final isMain =
                        row['ZoneType']?.toString() == 'Main';
                    final isEven = e.key % 2 == 0;
                    return DataRow(
                      color: WidgetStatePropertyAll(
                          isEven ? const Color(0xFFE0F2F1) : Colors.white),
                      cells: [
                        DataCell(Text(
                          row['Zone']?.toString() ?? '',
                          style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF00695C)),
                        )),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isMain
                                ? const Color(0xFFE8F5E9)
                                : const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMain ? Icons.home : Icons.apartment,
                                size: 14,
                                color: isMain
                                    ? const Color(0xFF2E7D32)
                                    : const Color(0xFFE65100),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isMain ? 'رئيسية' : 'فرعية',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isMain
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFFE65100),
                                ),
                              ),
                            ],
                          ),
                        )),
                        DataCell(Text(
                          row['ZoneContractor']?.toString() ?? '',
                          style: GoogleFonts.cairo(fontSize: 12),
                        )),
                        DataCell(Text(
                          row['MainZoneContractor']?.toString() ?? '',
                          style: GoogleFonts.cairo(fontSize: 12),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// مخطط خطي يومي — اتجاه المستخدمين (slice 48)
  Widget _buildTimeSeriesChart() {
    final data48 = _slicesData[48];
    if (data48 == null) {
      return const SizedBox.shrink();
    }

    final rows = (data48['data'] as List?) ?? [];
    final colnames = (data48['colnames'] as List?)?.cast<String>() ?? [];
    if (rows.isEmpty || colnames.length < 2) return const SizedBox.shrink();

    // أعمدة المناطق (كل شيء ما عدا eventDate)
    final zoneColumns = colnames.where((c) => c != 'eventDate').toList();

    // اختيار أكبر 5 مناطق حسب المجموع
    final zoneTotals = <String, double>{};
    for (var col in zoneColumns) {
      zoneTotals[col] = rows.fold<double>(
          0.0, (sum, r) => sum + ((r[col] ?? 0) as num).toDouble());
    }
    final sortedZones = zoneTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sortedZones.take(5).map((e) => e.key).toList();

    final chartColors = [
      const Color(0xFF2196F3), // أزرق
      const Color(0xFF4CAF50), // أخضر
      const Color(0xFFFF9800), // برتقالي
      const Color(0xFF9C27B0), // بنفسجي
      const Color(0xFFF44336), // أحمر
    ];

    // بناء خطوط المخطط
    final lineBarsData = <LineChartBarData>[];
    for (var z = 0; z < top5.length; z++) {
      final col = top5[z];
      final spots = <FlSpot>[];
      for (var i = 0; i < rows.length; i++) {
        final val = ((rows[i][col] ?? 0) as num).toDouble();
        spots.add(FlSpot(i.toDouble(), val));
      }
      lineBarsData.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.3,
        color: chartColors[z],
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: chartColors[z].withOpacity(0.08),
        ),
      ));
    }

    // حساب أقصى قيمة Y
    double maxY = 0;
    for (var col in top5) {
      for (var row in rows) {
        final v = ((row[col] ?? 0) as num).toDouble();
        if (v > maxY) maxY = v;
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اتجاه المستخدمين اليومي (آخر شهر)',
                style: GoogleFonts.cairo(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('أكبر ${top5.length} مناطق',
                style: GoogleFonts.cairo(
                    fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: LineChart(LineChartData(
                lineBarsData: lineBarsData,
                minY: 0,
                maxY: maxY * 1.1,
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: (rows.length / 6).ceilToDouble().clamp(1, 100),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= rows.length) {
                          return const SizedBox.shrink();
                        }
                        final ts = rows[idx]['eventDate'] as int?;
                        if (ts == null) return const SizedBox.shrink();
                        final date =
                            DateTime.fromMillisecondsSinceEpoch(ts);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${date.month}/${date.day}',
                              style: const TextStyle(fontSize: 9)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (value, meta) {
                        return Text(_numFmt.format(value.toInt()),
                            style: const TextStyle(fontSize: 9));
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey[300]!,
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => spots.map((spot) {
                      final col = top5[spot.barIndex];
                      return LineTooltipItem(
                        '$col\n${_numFmt.format(spot.y.toInt())}',
                        TextStyle(
                          color: chartColors[spot.barIndex],
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )),
            ),
            const SizedBox(height: 8),
            // Legend
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: List.generate(top5.length, (i) {
                return _legendDot(chartColors[i], top5[i]);
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// مخطط خطي طويل المدى — اتجاه Active/Inactive (slice 51)
  Widget _buildLongTermChart() {
    final data51 = _slicesData[51];
    if (data51 == null) {
      return const SizedBox.shrink();
    }

    final rows = (data51['data'] as List?) ?? [];
    final colnames = (data51['colnames'] as List?)?.cast<String>() ?? [];
    if (rows.isEmpty || colnames.length < 2) return const SizedBox.shrink();

    // تجميع إجمالي Active و Inactive من كل المناطق لكل تاريخ
    final activeColumns =
        colnames.where((c) => c.contains('Active')).toList();
    final inactiveColumns =
        colnames.where((c) => c.contains('Inactive')).toList();

    if (activeColumns.isEmpty) return const SizedBox.shrink();

    final activeSpots = <FlSpot>[];
    final inactiveSpots = <FlSpot>[];
    double maxY = 0;

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      double activeSum = 0;
      double inactiveSum = 0;

      for (var col in activeColumns) {
        activeSum += ((row[col] ?? 0) as num).toDouble();
      }
      for (var col in inactiveColumns) {
        inactiveSum += ((row[col] ?? 0) as num).toDouble();
      }

      activeSpots.add(FlSpot(i.toDouble(), activeSum));
      inactiveSpots.add(FlSpot(i.toDouble(), inactiveSum));

      if (activeSum > maxY) maxY = activeSum;
      if (inactiveSum > maxY) maxY = inactiveSum;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اتجاه المستخدمين (طويل المدى)',
                style: GoogleFonts.cairo(
                    fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('مجموع كل المناطق — Active vs Inactive',
                style: GoogleFonts.cairo(
                    fontSize: 11, color: Colors.grey[600])),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: LineChart(LineChartData(
                lineBarsData: [
                  LineChartBarData(
                    spots: activeSpots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: const Color(0xFF4CAF50),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF4CAF50).withOpacity(0.12),
                    ),
                  ),
                  LineChartBarData(
                    spots: inactiveSpots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: const Color(0xFFF44336),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFF44336).withOpacity(0.08),
                    ),
                  ),
                ],
                minY: 0,
                maxY: maxY * 1.1,
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: (rows.length / 6).ceilToDouble().clamp(1, 1000),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= rows.length) {
                          return const SizedBox.shrink();
                        }
                        final ts = rows[idx]['eventDate'] as int?;
                        if (ts == null) return const SizedBox.shrink();
                        final date =
                            DateTime.fromMillisecondsSinceEpoch(ts);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${date.year}/${date.month}',
                              style: const TextStyle(fontSize: 9)),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      getTitlesWidget: (value, meta) {
                        return Text(_numFmt.format(value.toInt()),
                            style: const TextStyle(fontSize: 9));
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 0 ? maxY / 4 : 1,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey[300]!,
                    strokeWidth: 0.5,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => spots.map((spot) {
                      final labels = ['نشط', 'غير نشط'];
                      final colors = [
                        const Color(0xFF4CAF50),
                        const Color(0xFFF44336),
                      ];
                      return LineTooltipItem(
                        '${labels[spot.barIndex]}: ${_numFmt.format(spot.y.toInt())}',
                        TextStyle(
                          color: colors[spot.barIndex],
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              )),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(const Color(0xFF4CAF50), 'نشط'),
                const SizedBox(width: 20),
                _legendDot(const Color(0xFFF44336), 'غير نشط'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper widgets ──

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.cairo(
                          color: Colors.white70, fontSize: 12)),
                  Text(value,
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniCard(String title, dynamic value, IconData icon, Color color) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.cairo(
                          fontSize: 10, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    _numFmt.format(value is num ? value : 0),
                    style: GoogleFonts.cairo(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskRow(String label, dynamic value, Color color,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          Text(
            _numFmt.format(value is num ? value : 0),
            style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color),
          ),
        ],
      ),
    );
  }

  String _translateRequestType(String type) {
    const map = {
      'Customer Onboarding Request': 'طلب تسجيل عميل',
      'New Address Request': 'طلب عنوان جديد',
      'Subscription Transfer Request': 'طلب نقل اشتراك',
      'Subscription Transfer Request New Customer': 'نقل اشتراك لعميل جديد',
      'Change Account Information Request': 'تغيير معلومات الحساب',
    };
    return map[type] ?? type;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحليلات Dashboard'),
          backgroundColor: Colors.indigo[800],
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // 📋 زر عرض السجلات
            IconButton(
              icon: Badge(
                isLabelVisible: _logs.isNotEmpty,
                label: Text('${_logs.length}',
                    style: const TextStyle(fontSize: 10)),
                child: const Icon(Icons.article_outlined),
              ),
              tooltip: 'عرض السجلات',
              onPressed: _showLogs,
            ),
            IconButton(
              icon: const Icon(Icons.language),
              tooltip: 'جلب من الموقع',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FetchServerDataPage(authToken: widget.authToken),
                  ),
                );
                // بعد العودة — تحميل البيانات المحفوظة
                await _loadSupersetDataLocally();
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث البيانات',
              onPressed: _fetchLiveDashboard,
            ),
          ],
        ),
        body: _buildLiveDashboard(),
      ),
    );
  }

  Widget _buildFilesList() {
    if (_isLoading && _dashboardFiles.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_dashboardFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'لا توجد ملفات',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    // تصنيف الملفات
    final fileCategories = _categorizeFiles();

    return ListView(
      children: fileCategories.entries.map((category) {
        return ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(
            _getCategoryIcon(category.key),
            color: _getCategoryColor(category.key),
            size: 20,
          ),
          title: Text(
            category.key,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${category.value.length} ملف',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          children: category.value.map((file) {
            final fileName = file.path.split('\\').last;
            final isSelected = _currentFileName == fileName;

            return ListTile(
              dense: true,
              selected: isSelected,
              selectedTileColor: Colors.indigo[100],
              leading: Icon(
                Icons.description,
                size: 18,
                color: isSelected ? Colors.indigo[700] : Colors.grey[500],
              ),
              title: Text(
                fileName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.indigo[700] : Colors.black87,
                ),
              ),
              onTap: () => _loadFile(file.path, fileName),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Map<String, List<FileSystemEntity>> _categorizeFiles() {
    final categories = <String, List<FileSystemEntity>>{
      '📈 بيانات الرسوم': [],
      '🗺️ المناطق': [],
    };

    for (final file in _dashboardFiles) {
      final name = file.path.toLowerCase();
      if (name.contains('zone')) {
        categories['🗺️ المناطق']!.add(file);
      } else {
        categories['📈 بيانات الرسوم']!.add(file);
      }
    }

    // إزالة الفئات الفارغة
    categories.removeWhere((key, value) => value.isEmpty);

    return categories;
  }

  IconData _getCategoryIcon(String category) {
    if (category.contains('رسوم')) return Icons.bar_chart;
    if (category.contains('مناطق')) return Icons.map;
    if (category.contains('مستخدمين')) return Icons.people;
    return Icons.folder;
  }

  Color _getCategoryColor(String category) {
    if (category.contains('رسوم')) return Colors.blue;
    if (category.contains('مناطق')) return Colors.green;
    if (category.contains('مستخدمين')) return Colors.orange;
    return Colors.grey;
  }

  Widget _buildMainContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري التحميل...'),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.red[700]),
            ),
          ],
        ),
      );
    }

    if (_currentData == null) {
      return _buildLiveDashboard();
    }

    return Column(
      children: [
        // شريط معلومات الملف
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo[700],
          ),
          child: Row(
            children: [
              const Icon(Icons.description, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentFileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _getDataInfo(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // زر تبديل العرض (منظم / خام)
              if (_isChartData(_currentData))
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.table_chart,
                          color: !_showRawData ? Colors.yellow : Colors.white70,
                          size: 20,
                        ),
                        tooltip: 'عرض منظم',
                        onPressed: () => setState(() => _showRawData = false),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.code,
                          color: _showRawData ? Colors.yellow : Colors.white70,
                          size: 20,
                        ),
                        tooltip: 'بيانات خام',
                        onPressed: () => setState(() => _showRawData = true),
                      ),
                    ],
                  ),
                ),
              // زر النسخ
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white),
                tooltip: 'نسخ JSON',
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text: const JsonEncoder.withIndent('  ')
                        .convert(_currentData),
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ البيانات')),
                  );
                },
              ),
            ],
          ),
        ),

        // عرض البيانات
        Expanded(
          child: _buildDataViewer(),
        ),
      ],
    );
  }

  String _getDataInfo() {
    if (_currentData is List) {
      return '${(_currentData as List).length} عنصر';
    } else if (_currentData is Map) {
      return '${(_currentData as Map).length} حقل';
    }
    return 'بيانات';
  }

  Widget _buildDataViewer() {
    // التحقق من أن البيانات هي رسم بياني
    final isChartData = _isChartData(_currentData);

    // التحقق من بيانات zones
    final isZonesData = _isZonesData(_currentData);

    // إذا كان المستخدم يريد عرض البيانات الخام
    if (_showRawData) {
      return _buildRawJsonViewer();
    }

    // عرض خاص لبيانات zones كجدول
    if (isZonesData) {
      return _buildZonesTableViewer(_currentData as List);
    }

    // عرض خاص لبيانات الرسوم البيانية
    if (isChartData) {
      return _buildChartViewer(_currentData);
    }

    if (_currentData is List) {
      final list = _currentData as List;
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final item = list[index];
          return _buildItemCard(item, index);
        },
      );
    } else if (_currentData is Map) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildMapView(_currentData as Map<String, dynamic>),
      );
    }

    return Center(
      child: SelectableText(
        _currentData.toString(),
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }

  /// التحقق من بيانات zones
  bool _isZonesData(dynamic data) {
    if (data is! List || data.isEmpty) return false;
    final first = data.first;
    if (first is! Map) return false;
    // التحقق من وجود حقول zones المعروفة
    return first.containsKey('Zone') ||
        first.containsKey('ZoneType') ||
        first.containsKey('ZoneContractor');
  }

  /// عرض بيانات zones كجدول احترافي
  Widget _buildZonesTableViewer(List data) {
    // تحديد الأعمدة من أول عنصر
    final firstItem = data.first as Map<String, dynamic>;
    final columns = firstItem.keys.toList();

    // إحصائيات
    int mainCount = 0;
    int virtualCount = 0;
    Map<String, int> contractorStats = {};

    for (var item in data) {
      if (item is Map) {
        final zoneType = item['ZoneType']?.toString() ?? '';
        if (zoneType == 'Main') {
          mainCount++;
        } else if (zoneType == 'Virtual') {
          virtualCount++;
        }

        final contractor = item['ZoneContractor']?.toString() ?? 'غير محدد';
        contractorStats[contractor] = (contractorStats[contractor] ?? 0) + 1;
      }
    }

    return Column(
      children: [
        // شريط الإحصائيات
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal[700]!, Colors.teal[500]!],
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_on, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'جدول المناطق: ${data.length} منطقة',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              // إحصائيات سريعة
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.home, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text('رئيسية: $mainCount',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                    const SizedBox(width: 12),
                    const Icon(Icons.account_tree,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text('فرعية: $virtualCount',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white, size: 20),
                tooltip: 'نسخ الجدول',
                onPressed: () {
                  _copyZonesAsTable(data, columns);
                },
              ),
            ],
          ),
        ),

        // الجدول
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.teal[50]),
                dataRowMinHeight: 40,
                dataRowMaxHeight: 60,
                columnSpacing: 24,
                horizontalMargin: 16,
                columns: columns.map((col) {
                  return DataColumn(
                    label: Container(
                      constraints: const BoxConstraints(minWidth: 100),
                      child: Text(
                        _getArabicColumnName(col),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
                rows: data.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value as Map<String, dynamic>;
                  final isMain = item['ZoneType'] == 'Main';

                  return DataRow(
                    color: WidgetStateProperty.resolveWith((states) {
                      if (index % 2 == 0) {
                        return isMain ? Colors.blue[50] : Colors.grey[50];
                      }
                      return isMain ? Colors.blue[100] : null;
                    }),
                    cells: columns.map((col) {
                      final value = item[col];
                      return DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 250),
                          child: _buildZoneCellContent(col, value),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// تحويل اسم العمود للعربية
  String _getArabicColumnName(String col) {
    switch (col) {
      case 'Zone':
        return 'المنطقة';
      case 'ZoneType':
        return 'النوع';
      case 'ZoneContractor':
        return 'المقاول';
      case 'MainZoneContractor':
        return 'المقاول الرئيسي';
      default:
        return col;
    }
  }

  /// بناء محتوى خلية zone
  Widget _buildZoneCellContent(String col, dynamic value) {
    final strValue = value?.toString() ?? '-';

    if (col == 'ZoneType') {
      final isMain = strValue == 'Main';
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMain ? Colors.blue[100] : Colors.orange[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMain ? Icons.home : Icons.account_tree,
              size: 14,
              color: isMain ? Colors.blue[700] : Colors.orange[700],
            ),
            const SizedBox(width: 4),
            Text(
              isMain ? 'رئيسية' : 'فرعية',
              style: TextStyle(
                color: isMain ? Colors.blue[700] : Colors.orange[700],
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    if (col == 'Zone') {
      return Text(
        strValue,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.bold,
          color: Colors.teal,
        ),
      );
    }

    return Text(
      strValue,
      style: const TextStyle(fontSize: 13),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  /// نسخ الجدول كنص
  void _copyZonesAsTable(List data, List<String> columns) {
    final buffer = StringBuffer();

    // رأس الجدول
    buffer.writeln(columns.map(_getArabicColumnName).join('\t'));
    buffer.writeln('-' * 80);

    // البيانات
    for (var item in data) {
      if (item is Map) {
        final row =
            columns.map((col) => item[col]?.toString() ?? '-').join('\t');
        buffer.writeln(row);
      }
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم نسخ ${data.length} صف'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  /// التحقق مما إذا كانت البيانات رسم بياني
  bool _isChartData(dynamic data) {
    if (data == null) return false;

    // نوع 1: بيانات timeseries (columns + data)
    if (data is Map &&
        data.containsKey('columns') &&
        data.containsKey('data')) {
      return true;
    }

    // نوع 2: قائمة من الرسوم البيانية (parsed_charts)
    if (data is List && data.isNotEmpty && data.first is Map) {
      final first = data.first as Map;
      if (first.containsKey('chart_id') ||
          first.containsKey('data') ||
          first.containsKey('chartType')) {
        return true;
      }
    }

    // نوع 3: بيانات chart_data
    if (data is Map &&
        (data.containsKey('charts') || data.containsKey('result'))) {
      return true;
    }

    return false;
  }

  /// عرض البيانات الخام JSON
  Widget _buildRawJsonViewer() {
    return Column(
      children: [
        // شريط معلومات
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey[200],
          child: Row(
            children: [
              const Icon(Icons.code, color: Colors.grey),
              const SizedBox(width: 8),
              const Text(
                'عرض البيانات الخام (JSON)',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'نسخ',
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                    text: const JsonEncoder.withIndent('  ')
                        .convert(_currentData),
                  ));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ البيانات')),
                  );
                },
              ),
            ],
          ),
        ),
        // عرض JSON
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(_currentData),
              style: const TextStyle(
                fontFamily: 'Consolas, monospace',
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// عرض جميع أنواع الرسوم البيانية
  Widget _buildChartViewer(dynamic data) {
    // نوع 1: timeseries (columns + data)
    if (data is Map &&
        data.containsKey('columns') &&
        data.containsKey('data')) {
      return _buildTimeseriesViewer(data as Map<String, dynamic>);
    }

    // نوع 2: قائمة من الرسوم البيانية
    if (data is List) {
      return _buildChartsListViewer(data);
    }

    // نوع 3: بيانات معقدة
    if (data is Map) {
      return _buildComplexChartViewer(data as Map<String, dynamic>);
    }

    return _buildRawJsonViewer();
  }

  /// عرض قائمة من الرسوم البيانية
  Widget _buildChartsListViewer(List data) {
    return Column(
      children: [
        // ملخص
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.purple[50],
          child: Row(
            children: [
              const Icon(Icons.bar_chart, color: Colors.purple),
              const SizedBox(width: 8),
              Text(
                'قائمة رسوم بيانية: ${data.length} رسم',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        // قائمة الرسوم
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: data.length,
            itemBuilder: (context, index) {
              final chart = data[index];
              return _buildChartCard(chart, index);
            },
          ),
        ),
      ],
    );
  }

  /// بطاقة رسم بياني واحد
  Widget _buildChartCard(dynamic chart, int index) {
    if (chart is! Map<String, dynamic>) {
      return ListTile(title: Text('رسم ${index + 1}'));
    }

    final chartId = chart['chart_id']?.toString() ??
        chart['id']?.toString() ??
        'رسم ${index + 1}';
    final chartType = chart['chartType']?.toString() ??
        chart['type']?.toString() ??
        'غير محدد';
    final hasData = chart.containsKey('data') || chart.containsKey('columns');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple[100],
          child: Icon(_getChartIcon(chartType),
              color: Colors.purple[700], size: 20),
        ),
        title:
            Text(chartId, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('النوع: $chartType'),
        children: [
          if (hasData && chart['data'] != null) ...[
            _buildInlineChartData(chart),
          ],
          // عرض JSON كامل
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.grey[100],
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(chart),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
              maxLines: 20,
            ),
          ),
        ],
      ),
    );
  }

  /// عرض بيانات الرسم داخل البطاقة
  Widget _buildInlineChartData(Map<String, dynamic> chart) {
    final data = chart['data'];
    final columns = chart['columns'];

    if (columns != null && data != null && data is List) {
      // عرض جدول مصغر
      final cols = (columns as List).take(5).toList();
      final rows = data.take(10).toList();

      return Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            // رأس الجدول
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.indigo[50],
              child: Row(
                children: cols
                    .map((c) => Expanded(
                          child: Text(
                            c.toString(),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 10),
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
              ),
            ),
            // الصفوف
            ...rows.map((row) {
              if (row is! Map) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: cols.map((c) {
                    var val = row[c];
                    String display;
                    Color? color;

                    if (c.toString().contains('Date') && val is int) {
                      final d = DateTime.fromMillisecondsSinceEpoch(val);
                      display = '${d.month}/${d.day}';
                    } else if (val == null) {
                      display = '-';
                      color = Colors.grey;
                    } else if (c.toString().contains('Active')) {
                      display = val.toString();
                      color = Colors.green;
                    } else if (c.toString().contains('Inactive')) {
                      display = val.toString();
                      color = Colors.red;
                    } else {
                      display = val.toString();
                    }

                    return Expanded(
                      child: Text(
                        display,
                        style: TextStyle(fontSize: 10, color: color),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
            if (data.length > 10)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '... و ${data.length - 10} صفوف أخرى',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// أيقونة حسب نوع الرسم
  IconData _getChartIcon(String type) {
    switch (type.toLowerCase()) {
      case 'line':
      case 'timeseries':
        return Icons.show_chart;
      case 'bar':
        return Icons.bar_chart;
      case 'pie':
        return Icons.pie_chart;
      case 'area':
        return Icons.area_chart;
      default:
        return Icons.insert_chart;
    }
  }

  /// عرض بيانات رسم بياني معقدة
  Widget _buildComplexChartViewer(Map<String, dynamic> data) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.orange[50],
          child: Row(
            children: [
              const Icon(Icons.analytics, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'بيانات رسم بياني: ${data.keys.length} حقل',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildMapView(data),
          ),
        ),
      ],
    );
  }

  /// عرض بيانات الرسوم البيانية (timeseries) بشكل جدول
  Widget _buildTimeseriesViewer(Map<String, dynamic> chartData) {
    final columns = (chartData['columns'] as List).cast<String>();
    final data = (chartData['data'] as List).cast<Map<String, dynamic>>();

    return Column(
      children: [
        // ملخص البيانات
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.green[50],
          child: Row(
            children: [
              const Icon(Icons.show_chart, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'بيانات رسم بياني: ${columns.length} أعمدة × ${data.length} صفوف',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        // عرض الأعمدة
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.indigo[100],
          child: Row(
            children: columns
                .map((col) => Expanded(
                      child: Text(
                        col,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 11),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
          ),
        ),
        // عرض البيانات
        Expanded(
          child: ListView.builder(
            itemCount: data.length,
            itemBuilder: (context, index) {
              final row = data[index];
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: index.isEven ? Colors.white : Colors.grey[50],
                  border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: columns.map((col) {
                    var value = row[col];
                    String displayValue;
                    Color? textColor;

                    if (col == 'eventDate' && value is int) {
                      // تحويل timestamp إلى تاريخ
                      final date = DateTime.fromMillisecondsSinceEpoch(value);
                      displayValue = '${date.year}/${date.month}/${date.day}';
                    } else if (value == null) {
                      displayValue = '-';
                      textColor = Colors.grey;
                    } else if (col.contains('Active')) {
                      displayValue = value.toString();
                      textColor = Colors.green[700];
                    } else if (col.contains('Inactive')) {
                      displayValue = value.toString();
                      textColor = Colors.red[700];
                    } else {
                      displayValue = value.toString();
                    }

                    return Expanded(
                      child: Text(
                        displayValue,
                        style: TextStyle(
                          fontSize: 12,
                          color: textColor,
                          fontWeight:
                              col.contains('Active') || col.contains('Inactive')
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildItemCard(dynamic item, int index) {
    if (item is Map<String, dynamic>) {
      final title = item['displayValue']?.toString() ??
          item['zone_name']?.toString() ??
          item['name']?.toString() ??
          item['id']?.toString() ??
          'عنصر ${index + 1}';

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: Colors.indigo[100],
            radius: 16,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: Colors.indigo[700],
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.grey[50],
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(item),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 14,
        child: Text('${index + 1}', style: const TextStyle(fontSize: 10)),
      ),
      title: Text(item.toString(), style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _buildMapView(Map<String, dynamic> data) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo[700],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      entry.value is Map || entry.value is List
                          ? const JsonEncoder.withIndent('  ')
                              .convert(entry.value)
                          : entry.value.toString(),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _PieItem {
  final String label;
  final double value;
  final Color color;
  _PieItem(this.label, this.value, this.color);
}

class _BarItem {
  final String label;
  final double value;
  final Color color;
  _BarItem(this.label, this.value, this.color);
}

