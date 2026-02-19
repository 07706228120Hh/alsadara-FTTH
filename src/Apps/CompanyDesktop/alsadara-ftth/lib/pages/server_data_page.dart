import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/agents_auth_service.dart';

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
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/partners/$_partnerId/dashboard/summary'),
        headers: _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint(
          'Dashboard summary error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Dashboard summary error: $e');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 🗺️ جلب المناطق من api.ftth.iq
  // ══════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> fetchZones() async {
    if (!hasToken) return null;

    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/locations/zones'),
        headers: _getAuthHeaders(),
      );

      debugPrint('Zones response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint('Zones error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Zones error: $e');
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
      final response = await http.get(
        Uri.parse(
            '$_apiBaseUrl/customers?pageNumber=$page&pageSize=$pageSize&sortCriteria.property=self.displayValue&sortCriteria.direction=asc'),
        headers: _getAuthHeaders(),
      );

      debugPrint('Customers response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint('Customers error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Customers error: $e');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 💰 جلب رصيد المحفظة من api.ftth.iq
  // ══════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>?> fetchWalletBalance() async {
    if (!hasToken) return null;

    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/partners/$_partnerId/wallets/balance'),
        headers: _getAuthHeaders(),
      );

      debugPrint('Wallet response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint('Wallet error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Wallet error: $e');
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
      final response = await http.get(
        Uri.parse(
            '$_apiBaseUrl/audit-logs?pageNumber=$page&pageSize=$pageSize&sortCriteria.property=createdAt&sortCriteria.direction=desc'),
        headers: _getAuthHeaders(),
      );

      debugPrint('Audit logs response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint('Audit logs error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Audit logs error: $e');
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
      final response = await http.get(
        Uri.parse(
            '$_apiBaseUrl/subscriptions?pageNumber=$page&pageSize=$pageSize'),
        headers: _getAuthHeaders(),
      );

      debugPrint('Subscriptions response: ${response.statusCode}');
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      debugPrint(
          'Subscriptions error: ${response.statusCode} - ${response.body}');
    } catch (e) {
      debugPrint('Subscriptions error: $e');
    }
    return null;
  }

  // ══════════════════════════════════════════════════════════════════
  // 🔧 Helper Methods
  // ══════════════════════════════════════════════════════════════════
  Map<String, String> _getAuthHeaders() {
    return {
      'Authorization': 'Bearer $_authToken',
      'Accept': 'application/json',
    };
  }

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
      print('Error loading local file: $e');
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
/// 📱 صفحة بيانات السيرفر المحسّنة
/// ═══════════════════════════════════════════════════════════════════

class ServerDataPage extends StatefulWidget {
  final String authToken;

  const ServerDataPage({super.key, required this.authToken});

  @override
  State<ServerDataPage> createState() => _ServerDataPageState();
}

class _ServerDataPageState extends State<ServerDataPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FtthServerDataService _service = FtthServerDataService();

  bool _isLoading = false;
  String _statusMessage = '';
  String _currentDataTitle = '';
  List<dynamic> _currentData = [];
  String _errorMessage = '';

  // إحصائيات
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // تمرير authToken للخدمة
    _service.setAuthToken(widget.authToken);
    _loadInitialStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialStats() async {
    setState(() => _isLoading = true);

    try {
      // محاولة قراءة من الملفات المحلية أولاً
      final dashboardSummary =
          await FtthServerDataService.loadDashboardSummary();
      final zones = await FtthServerDataService.loadZonesWithCounts();
      final customers = await FtthServerDataService.loadCustomers();

      setState(() {
        _stats = {
          'zones_count': zones?.length ?? 0,
          'customers_count': customers?.length ?? 0,
          'dashboard': dashboardSummary,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في تحميل الإحصائيات: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLocalData(String fileName, String title) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _currentDataTitle = title;
    });

    try {
      final filePath = '${FtthServerDataService.fullDataPath}\\$fileName';
      final data = await FtthServerDataService.loadLocalFile(filePath);

      setState(() {
        _currentData = data is List ? data : (data != null ? [data] : []);
        _isLoading = false;
        _statusMessage = 'تم تحميل ${_currentData.length} عنصر';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchFromServer(String endpoint, String title) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _statusMessage = 'جاري الاتصال بالسيرفر...';
      _currentDataTitle = title;
    });

    try {
      // التحقق من وجود Token
      if (!_service.hasToken) {
        setState(() {
          _errorMessage = 'Token غير متوفر - تأكد من تسجيل الدخول';
          _isLoading = false;
        });
        return;
      }

      dynamic data;
      setState(() => _statusMessage = 'جاري جلب البيانات من api.ftth.iq ...');

      switch (endpoint) {
        case 'zones':
          data = await _service.fetchZones();
          break;
        case 'customers':
          data = await _service.fetchCustomers();
          break;
        case 'wallet':
          data = await _service.fetchWalletBalance();
          break;
        case 'audit_logs':
          data = await _service.fetchAuditLogs();
          break;
        case 'subscriptions':
          data = await _service.fetchSubscriptions();
          break;
      }

      // معالجة البيانات بناءً على نوعها
      List<dynamic> processedData = [];
      if (data is Map && data.containsKey('items')) {
        processedData = data['items'] as List<dynamic>;
      } else if (data is List) {
        processedData = data;
      } else if (data != null) {
        processedData = [data];
      }

      setState(() {
        _currentData = processedData;
        _isLoading = false;
        _statusMessage = data != null
            ? 'تم الجلب بنجاح (${processedData.length} عنصر)'
            : 'لا توجد بيانات أو حدث خطأ';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في الاتصال: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('🗄️ بيانات السيرفر'),
          backgroundColor: Colors.indigo[700],
          foregroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(icon: Icon(Icons.folder), text: 'بيانات محلية'),
              Tab(icon: Icon(Icons.cloud_download), text: 'جلب من السيرفر'),
              Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildLocalDataTab(),
            _buildServerFetchTab(),
            _buildDashboardTab(),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 📁 تاب البيانات المحلية
  // ══════════════════════════════════════════════════════════════════
  Widget _buildLocalDataTab() {
    return Column(
      children: [
        // شريط الأزرار
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.indigo[50]!, Colors.white],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              const Text(
                '📁 البيانات المحفوظة محلياً',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'مسار الملفات: ${FtthServerDataService.fullDataPath}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  _buildLocalButton(
                    icon: Icons.location_on,
                    label: 'المناطق + الإحصائيات',
                    color: Colors.blue,
                    fileName: 'zones_with_user_counts.json',
                  ),
                  _buildLocalButton(
                    icon: Icons.map,
                    label: 'المناطق',
                    color: Colors.green,
                    fileName: 'zones.json',
                  ),
                  _buildLocalButton(
                    icon: Icons.people,
                    label: 'العملاء',
                    color: Colors.orange,
                    fileName: 'customers_full.json',
                  ),
                  _buildLocalButton(
                    icon: Icons.subscriptions,
                    label: 'الاشتراكات',
                    color: Colors.purple,
                    fileName: 'subscriptions_full.json',
                  ),
                ],
              ),
            ],
          ),
        ),

        // عرض البيانات
        Expanded(child: _buildDataView()),
      ],
    );
  }

  Widget _buildLocalButton({
    required IconData icon,
    required String label,
    required Color color,
    required String fileName,
  }) {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : () => _loadLocalData(fileName, label),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 🌐 تاب جلب من السيرفر
  // ══════════════════════════════════════════════════════════════════
  Widget _buildServerFetchTab() {
    return Column(
      children: [
        // معلومات API
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green[300]!),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700], size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✅ الاتصال بـ api.ftth.iq',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[900],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'يتم استخدام نفس Token الذي تم تسجيل الدخول به.\n'
                      'هذه الـ API تعمل مباشرة بدون مشاكل Cloudflare.',
                      style: TextStyle(fontSize: 12, color: Colors.green[800]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // أزرار الجلب من السيرفر
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              _buildServerButton(
                icon: Icons.location_on,
                label: 'المناطق',
                color: Colors.teal,
                endpoint: 'zones',
              ),
              _buildServerButton(
                icon: Icons.people,
                label: 'العملاء',
                color: Colors.blue,
                endpoint: 'customers',
              ),
              _buildServerButton(
                icon: Icons.account_balance_wallet,
                label: 'رصيد المحفظة',
                color: Colors.green,
                endpoint: 'wallet',
              ),
              _buildServerButton(
                icon: Icons.history,
                label: 'سجل التدقيق',
                color: Colors.orange,
                endpoint: 'audit_logs',
              ),
              _buildServerButton(
                icon: Icons.subscriptions,
                label: 'الاشتراكات',
                color: Colors.purple,
                endpoint: 'subscriptions',
              ),
            ],
          ),
        ),

        // حالة الاتصال
        if (_statusMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                const SizedBox(width: 8),
                Text(_statusMessage, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),

        // عرض البيانات
        Expanded(child: _buildDataView()),
      ],
    );
  }

  Widget _buildServerButton({
    required IconData icon,
    required String label,
    required Color color,
    required String endpoint,
  }) {
    return OutlinedButton.icon(
      onPressed: _isLoading ? null : () => _fetchFromServer(endpoint, label),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 📊 تاب Dashboard
  // ══════════════════════════════════════════════════════════════════
  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 🔷 زر فتح مشروع Dashboard
          _buildDashboardProjectButton(),
          const SizedBox(height: 16),

          // بطاقة معلومات المشروع
          _buildProjectInfoCard(),
          const SizedBox(height: 16),

          // الإحصائيات السريعة
          _buildQuickStats(),
          const SizedBox(height: 16),

          // APIs المتاحة
          _buildApiReferenceCard(),
          const SizedBox(height: 16),

          // ملفات البيانات
          _buildDataFilesCard(),
        ],
      ),
    );
  }

  /// 🔷 زر فتح مشروع Dashboard في شاشة منفصلة
  Widget _buildDashboardProjectButton() {
    return InkWell(
      onTap: () => _openDashboardProjectPage(),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.indigo[800]!, Colors.indigo[600]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.indigo.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.dashboard_customize,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📊 مشروع Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'عرض بيانات 07_Dashboard_Project من السيرفر',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// فتح صفحة مشروع Dashboard
  void _openDashboardProjectPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardProjectPage(
          authToken: widget.authToken,
        ),
      ),
    );
  }

  Widget _buildProjectInfoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.indigo[700]!, Colors.indigo[500]!],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.dashboard, color: Colors.white, size: 32),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FTTH Dashboard Project',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'مشروع استخراج بيانات لوحة المعلومات',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(color: Colors.white30, height: 24),
            _buildInfoRow('Partner ID', '2261175', Icons.badge),
            _buildInfoRow('Dashboard UUID', '2a63cc44-01f4...', Icons.key),
            _buildInfoRow(
                'تاريخ الاستخراج', '31 يناير 2026', Icons.calendar_today),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.white70)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final stats = [
      {
        'icon': Icons.location_on,
        'value': '613',
        'label': 'منطقة',
        'color': Colors.blue
      },
      {
        'icon': Icons.people,
        'value': '13,347',
        'label': 'عميل',
        'color': Colors.green
      },
      {
        'icon': Icons.check_circle,
        'value': '7,624',
        'label': 'نشط',
        'color': Colors.teal
      },
      {
        'icon': Icons.account_balance_wallet,
        'value': '3.78M',
        'label': 'IQD',
        'color': Colors.orange
      },
    ];

    return Row(
      children: stats.map((stat) {
        return Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(stat['icon'] as IconData,
                      color: stat['color'] as Color, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    stat['value'] as String,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: stat['color'] as Color,
                    ),
                  ),
                  Text(
                    stat['label'] as String,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildApiReferenceCard() {
    final apis = [
      {'endpoint': '/auth/Contractor/token', 'desc': 'تسجيل الدخول'},
      {'endpoint': '/current-user', 'desc': 'معلومات المستخدم'},
      {'endpoint': '/partners/{id}/wallets/balance', 'desc': 'رصيد المحفظة'},
      {'endpoint': '/partners/dashboard/summary', 'desc': 'ملخص Dashboard'},
      {'endpoint': '/tasks/summary', 'desc': 'ملخص المهام'},
      {'endpoint': '/partners/{id}/zones', 'desc': 'المناطق'},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.api, color: Colors.purple[700]),
                const SizedBox(width: 8),
                const Text(
                  'APIs المكتشفة',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            ...apis.map((api) => ListTile(
                  dense: true,
                  leading: Icon(Icons.link, color: Colors.grey[400], size: 16),
                  title: Text(
                    api['endpoint']!,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  subtitle: Text(api['desc']!),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildDataFilesCard() {
    final files = [
      {'name': 'chart_data.json', 'size': '316 KB', 'icon': Icons.bar_chart},
      {'name': 'zones_list.json', 'size': '21 KB', 'icon': Icons.map},
      {'name': 'all_responses.json', 'size': '500 KB', 'icon': Icons.storage},
      {'name': 'customers_full.json', 'size': '21 KB', 'icon': Icons.people},
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open, color: Colors.amber[700]),
                const SizedBox(width: 8),
                const Text(
                  'ملفات البيانات المحلية',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            ...files.map((file) => ListTile(
                  dense: true,
                  leading:
                      Icon(file['icon'] as IconData, color: Colors.indigo[400]),
                  title: Text(file['name'] as String),
                  trailing: Text(
                    file['size'] as String,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  onTap: () => _loadLocalData(
                    file['name'] as String,
                    file['name'] as String,
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // 📋 عرض البيانات
  // ══════════════════════════════════════════════════════════════════
  Widget _buildDataView() {
    if (_isLoading) {
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

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.red[700], fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadInitialStats,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_currentData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'اختر أحد الأزرار لعرض البيانات',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // عنوان البيانات
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.indigo[50],
          child: Row(
            children: [
              Icon(Icons.data_array, color: Colors.indigo[700]),
              const SizedBox(width: 8),
              Text(
                '$_currentDataTitle (${_currentData.length} عنصر)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo[700],
                ),
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

        // قائمة البيانات
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _currentData.length,
            itemBuilder: (context, index) {
              final item = _currentData[index];
              return _buildDataCard(item, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDataCard(dynamic item, int index) {
    if (item is Map<String, dynamic>) {
      final title = item['displayValue']?.toString() ??
          item['zone_name']?.toString() ??
          item['zone_id']?.toString() ??
          item['id']?.toString() ??
          'عنصر ${index + 1}';

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ExpansionTile(
          leading: CircleAvatar(
            backgroundColor: Colors.indigo[100],
            radius: 18,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: Colors.indigo[700],
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: _buildSubtitle(item),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
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
      leading: CircleAvatar(child: Text('${index + 1}')),
      title: Text(item.toString()),
    );
  }

  Widget? _buildSubtitle(Map<String, dynamic> item) {
    final parts = <String>[];

    if (item.containsKey('customers')) {
      parts.add('العملاء: ${item['customers']}');
    }
    if (item.containsKey('subscriptions')) {
      parts.add('الاشتراكات: ${item['subscriptions']}');
    }
    if (item.containsKey('customerType')) {
      final type = item['customerType'];
      if (type is Map) {
        parts.add('النوع: ${type['displayValue'] ?? 'غير محدد'}');
      }
    }

    if (parts.isEmpty) return null;
    return Text(
      parts.join(' | '),
      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
    );
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
  bool _isFetchingFromServer = false;
  bool _isFetchingAllData = false; // جلب كل البيانات من API مباشرة
  bool _showRawData = false; // للتبديل بين العرض المنظم والخام
  String _errorMessage = '';
  String _fetchStatus = '';
  String _currentFileName = '';
  dynamic _currentData;
  List<FileSystemEntity> _dashboardFiles = [];
  Process? _pythonProcess;
  String? _guestToken; // للمصادقة مع Dashboard API
  Map<String, dynamic> _allChartsData = {}; // بيانات كل الشارتات

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
    // جلب Guest Token تلقائياً عند فتح الصفحة
    _initGuestToken();
  }

  /// تهيئة Guest Token عند فتح الصفحة
  Future<void> _initGuestToken() async {
    debugPrint('🔄 تهيئة Guest Token...');
    debugPrint(
        '📋 Auth Token: ${widget.authToken.isNotEmpty ? "${widget.authToken.substring(0, 30)}..." : "فارغ"}');
    await _fetchGuestToken();
  }

  /// تحميل قائمة ملفات Dashboard Project
  Future<void> _loadDashboardFiles() async {
    setState(() => _isLoading = true);

    try {
      final dir = Directory(FtthServerDataService.dashboardPath);
      if (await dir.exists()) {
        // البحث بشكل متكرر في جميع المجلدات الفرعية
        final files = await dir
            .list(recursive: true)
            .where((f) => f.path.endsWith('.json'))
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
        _errorMessage = 'خطأ: $e';
        _isLoading = false;
      });
    }
  }

  /// تشغيل سكربت Python لجلب البيانات من السيرفر
  Future<void> _fetchFromServer(
      {bool allZones = false,
      bool useImproved = false,
      bool useDebug = false,
      bool useAdminApi = false}) async {
    final scriptsPath = '${FtthServerDataService.dashboardPath}\\scripts';
    String scriptName;
    if (useAdminApi) {
      scriptName = 'fetch_admin_api.py';
    } else if (useDebug) {
      scriptName = 'fetch_debug.py';
    } else if (useImproved) {
      scriptName = 'fetch_improved.py';
    } else if (allZones) {
      scriptName = 'fetch_all_zones_no_filter.py';
    } else {
      scriptName = 'fetch_all_dashboard_v2.py';
    }
    final scriptFile = File('$scriptsPath\\$scriptName');

    if (!await scriptFile.exists()) {
      _showErrorDialog(
          'سكربت Python غير موجود!\n\nالمسار المتوقع:\n$scriptsPath\\$scriptName');
      return;
    }

    // تأكيد قبل البدء
    String title;
    String description;
    IconData icon;
    Color iconColor;

    if (useAdminApi) {
      title = '🌐 جلب من Admin API';
      description =
          'سيتم جلب البيانات مباشرة من admin.ftth.iq API.\n\n✅ هذا الخيار يعمل بشكل مؤكد!';
      icon = Icons.api;
      iconColor = Colors.green;
    } else if (useDebug) {
      title = '🔍 تشخيص (Debug)';
      description =
          'سيتم تشغيل سكربت التشخيص الذي يلتقط كل الـ requests ويأخذ screenshots.\n\nالملفات ستُحفظ في مجلد debug.';
      icon = Icons.bug_report;
      iconColor = Colors.orange;
    } else if (useImproved) {
      title = '✨ جلب محسّن (التقاط تلقائي)';
      description =
          'سيتم استخدام السكربت المحسّن الذي يلتقط البيانات تلقائياً من Dashboard.';
      icon = Icons.auto_awesome;
      iconColor = Colors.amber;
    } else if (allZones) {
      title = 'جلب كل المناطق';
      description =
          'سيتم جلب بيانات جميع المناطق والشارتات من Superset Dashboard.\n\n✅ يتجاوز Cloudflare تلقائياً عبر Playwright.';
      icon = Icons.cloud_download;
      iconColor = Colors.indigo;
    } else {
      title = 'جلب بيانات (السكربت القديم)';
      description =
          'سيتم تشغيل سكربت Python القديم لجلب البيانات من admin panel فقط.';
      icon = Icons.cloud_download;
      iconColor = Colors.grey;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description),
            const SizedBox(height: 12),
            const Text('ملاحظات:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('• سيفتح متصفح للتعامل مع Cloudflare'),
            Text(allZones
                ? '• قد يستغرق وقتاً أطول (613 منطقة)'
                : '• قد يستغرق بضع دقائق'),
            const Text('• تأكد من تثبيت playwright'),
            if (allZones || useImproved)
              const Text('• لا تغلق نافذة المتصفح!',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold)),
            if (useImproved)
              const Text('• السكربت المحسّن يلتقط البيانات تلقائياً',
                  style: TextStyle(color: Colors.green)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.play_arrow),
            label: const Text('بدء الجلب'),
            style: ElevatedButton.styleFrom(backgroundColor: iconColor),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    String scriptType;
    if (useAdminApi) {
      scriptType = "🌐 جلب من Admin API";
    } else if (useDebug) {
      scriptType = "🔍 تشخيص (Debug)";
    } else if (useImproved) {
      scriptType = "✨ السكربت المحسّن (التقاط تلقائي)";
    } else if (allZones) {
      scriptType = "جلب جميع المناطق (613)";
    } else {
      scriptType = "جلب بيانات عادي";
    }

    _log('═══════════════════════════════════════════');
    _log('🚀 بدء تشغيل سكربت Python');
    _log('═══════════════════════════════════════════');
    _log('📋 السكربت: $scriptName');
    _log('📋 المسار: $scriptsPath');
    _log('📋 النوع: $scriptType');

    setState(() {
      _isFetchingFromServer = true;
      _fetchStatus = 'جاري تشغيل السكربت...';
    });

    try {
      _log('🔄 تشغيل Python...');
      // تشغيل سكربت Python مع PYTHONIOENCODING=utf-8 لتجنب مشاكل الترميز
      _pythonProcess = await Process.start(
        'python',
        ['-u', scriptFile.path], // -u للخرج unbuffered
        workingDirectory: scriptsPath,
        runInShell: true,
        environment: {
          'PYTHONIOENCODING': 'utf-8',
          'PYTHONLEGACYWINDOWSSTDIO': '0',
        },
      );

      _log('✅ تم تشغيل Python - PID: ${_pythonProcess!.pid}');

      // قراءة الخرج
      _pythonProcess!.stdout.transform(utf8.decoder).listen((data) {
        final trimmed = data.trim();
        if (trimmed.isNotEmpty) {
          _log('📤 Python: $trimmed');
        }
        setState(() => _fetchStatus = trimmed);
      });

      _pythonProcess!.stderr.transform(utf8.decoder).listen((data) {
        final trimmed = data.trim();
        if (trimmed.isNotEmpty) {
          _log('❌ Python Error: $trimmed');
        }
      });

      // انتظار انتهاء العملية
      final exitCode = await _pythonProcess!.exitCode;

      _log('📋 انتهى Python - Exit Code: $exitCode');

      setState(() {
        _isFetchingFromServer = false;
        if (exitCode == 0) {
          _fetchStatus = '✅ تم جلب البيانات بنجاح!';
          _log('✅ تم جلب البيانات بنجاح!');
        } else {
          _fetchStatus = '❌ فشل مع كود: $exitCode';
          _log('❌ فشل السكربت مع كود: $exitCode');
        }
      });

      _log('═══════════════════════════════════════════');

      // إعادة تحميل الملفات
      if (exitCode == 0) {
        await _loadDashboardFiles();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم تحديث البيانات بنجاح!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      _log('═══════════════════════════════════════════');
      _log('❌❌ خطأ استثنائي في تشغيل السكربت');
      _log('❌ الخطأ: $e');
      _log('📋 Stack Trace: $stackTrace');
      _log('═══════════════════════════════════════════');
      setState(() {
        _isFetchingFromServer = false;
        _fetchStatus = 'خطأ: $e';
      });
      _showErrorDialog(
          'فشل تشغيل السكربت:\n$e\n\nتأكد من:\n• تثبيت Python\n• تثبيت playwright (pip install playwright)\n• تشغيل: playwright install chromium');
    }
  }

  /// إيقاف عملية الجلب
  void _stopFetching() {
    if (_pythonProcess != null) {
      _pythonProcess!.kill();
      setState(() {
        _isFetchingFromServer = false;
        _fetchStatus = '⏹️ تم إيقاف العملية';
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
        _errorMessage = 'خطأ في قراءة الملف: $e';
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
      _log('❌ خطأ في جلب Guest Token: $e');
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
      debugPrint('❌ خطأ في تحميل البيانات المحلية: $e');
      setState(() {
        _isFetchingAllData = false;
        _fetchStatus = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ: $e'),
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
          width: 700,
          height: 500,
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
                            content: Text('خطأ: $e'),
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
      _log('❌ خطأ عام في جلب البيانات: $e');
      setState(() {
        _isFetchingAllData = false;
        _fetchStatus = '❌ خطأ: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في جلب البيانات: $e'),
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('📊 مشروع Dashboard'),
          backgroundColor: Colors.indigo[800],
          foregroundColor: Colors.white,
          elevation: 0,
          actions: [
            // زر جلب البيانات من السيرفر
            if (_isFetchingFromServer || _isFetchingAllData)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isFetchingFromServer)
                      IconButton(
                        icon: const Icon(Icons.stop, color: Colors.red),
                        tooltip: 'إيقاف',
                        onPressed: _stopFetching,
                      ),
                  ],
                ),
              )
            else ...[
              // حالة Guest Token
              if (_guestToken != null)
                Tooltip(
                  message: 'متصل بالداشبورد ✓',
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.check_circle,
                        color: Colors.greenAccent, size: 18),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.login, color: Colors.amber),
                  tooltip: 'تسجيل الدخول للداشبورد',
                  onPressed: _showLoginDialog,
                ),
              // 📂 زر تحميل البيانات من الملفات المحلية
              IconButton(
                icon: const Icon(Icons.folder_open, color: Colors.amber),
                tooltip: '📂 تحميل من ملفات Python المحلية',
                onPressed: _loadFromLocalFiles,
              ),
              // زر جلب من Admin API (يعمل بشكل مؤكد!)
              IconButton(
                icon: const Icon(Icons.api, color: Colors.green),
                tooltip: '🌐 جلب من Admin API (موصى به)',
                onPressed: () => _fetchFromServer(useAdminApi: true),
              ),
              // زر جلب جميع المناطق
              IconButton(
                icon: const Icon(Icons.public),
                tooltip: 'جلب جميع المناطق (613)',
                onPressed: () => _fetchFromServer(allZones: true),
              ),
              // زر السكربت المحسّن (يلتقط البيانات تلقائياً)
              IconButton(
                icon: const Icon(Icons.auto_awesome, color: Colors.amber),
                tooltip: '✨ جلب محسّن (التقاط تلقائي)',
                onPressed: () => _fetchFromServer(useImproved: true),
              ),
              // زر التشخيص (Debug)
              IconButton(
                icon: const Icon(Icons.bug_report, color: Colors.orange),
                tooltip: '🔍 تشخيص (Screenshots + Logs)',
                onPressed: () => _fetchFromServer(useDebug: true),
              ),
              // زر جلب كل المناطق (السكربت الذي يعمل)
              IconButton(
                icon: const Icon(Icons.cloud_download),
                tooltip: 'جلب بيانات جديدة (كل المناطق)',
                onPressed: () => _fetchFromServer(allZones: true),
              ),
              // 📋 زر عرض السجلات
              IconButton(
                icon: Badge(
                  isLabelVisible: _logs.isNotEmpty,
                  label: Text('${_logs.length}',
                      style: const TextStyle(fontSize: 10)),
                  child: const Icon(Icons.article_outlined),
                ),
                tooltip: '📋 عرض السجلات (${_logs.length})',
                onPressed: _showLogs,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث القائمة',
              onPressed: _loadDashboardFiles,
            ),
          ],
        ),
        body: Row(
          children: [
            // الشريط الجانبي - قائمة الملفات
            Container(
              width: 280,
              decoration: BoxDecoration(
                color: Colors.indigo[50],
                border: Border(
                  left: BorderSide(color: Colors.indigo[200]!),
                ),
              ),
              child: Column(
                children: [
                  // تحذير: البيانات مفلترة
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange[100],
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.orange, size: 16),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'البيانات الحالية مفلترة على منطقة واحدة',
                            style:
                                TextStyle(fontSize: 10, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // رأس القائمة
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.indigo[100],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.folder_special, color: Colors.indigo),
                            SizedBox(width: 8),
                            Text(
                              '07_Dashboard_Project',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_dashboardFiles.length} ملف JSON',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // شريط حالة جلب البيانات
                  if (_isFetchingFromServer || _fetchStatus.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isFetchingFromServer
                            ? Colors.blue[50]
                            : (_fetchStatus.contains('✅')
                                ? Colors.green[50]
                                : Colors.red[50]),
                        border: Border(
                          bottom: BorderSide(
                            color: _isFetchingFromServer
                                ? Colors.blue[200]!
                                : (_fetchStatus.contains('✅')
                                    ? Colors.green[200]!
                                    : Colors.red[200]!),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          if (_isFetchingFromServer)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              _fetchStatus.contains('✅')
                                  ? Icons.check_circle
                                  : Icons.info,
                              size: 16,
                              color: _fetchStatus.contains('✅')
                                  ? Colors.green
                                  : Colors.blue,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _fetchStatus,
                              style: const TextStyle(fontSize: 11),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!_isFetchingFromServer && _fetchStatus.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () =>
                                  setState(() => _fetchStatus = ''),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                    ),
                  // قائمة الملفات
                  Expanded(
                    child: _buildFilesList(),
                  ),
                ],
              ),
            ),

            // المحتوى الرئيسي
            Expanded(
              child: _buildMainContent(),
            ),
          ],
        ),
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
      '👥 المستخدمين': [],
      '📋 أخرى': [],
    };

    for (final file in _dashboardFiles) {
      final name = file.path.toLowerCase();
      if (name.contains('chart') || name.contains('graph')) {
        categories['📈 بيانات الرسوم']!.add(file);
      } else if (name.contains('zone')) {
        categories['🗺️ المناطق']!.add(file);
      } else if (name.contains('user') || name.contains('customer')) {
        categories['👥 المستخدمين']!.add(file);
      } else {
        categories['📋 أخرى']!.add(file);
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.indigo[200]),
            const SizedBox(height: 16),
            Text(
              'اختر ملفاً من القائمة لعرض محتواه',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
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
