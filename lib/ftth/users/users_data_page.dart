/// اسم الصفحة: بيانات المستخدمين
/// وصف الصفحة: عرض بيانات المستخدمين من داشبورد slice_id=48
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/agents_auth_service.dart';
import '../../services/cloudflare_bypass_service.dart';
import 'package:url_launcher/url_launcher.dart';

class UsersDataPage extends StatefulWidget {
  final String authToken;
  const UsersDataPage({super.key, required this.authToken});

  @override
  State<UsersDataPage> createState() => _UsersDataPageState();
}

class _UsersDataPageState extends State<UsersDataPage> {
  bool isLoading = true;
  String? error;
  String? guestToken;
  bool isCloudflareError = false;
  bool isBypassingCloudflare = false;
  int retryCount = 0;
  static const int maxRetries = 3;

  // بيانات المستخدمين من slice_id=48
  List<Map<String, dynamic>> usersData = [];
  List<String> userZones = []; // قائمة zones من colnames
  Map<String, dynamic>? rawResponse;

  // فلترة وبحث
  String searchQuery = '';
  String? selectedZone;
  bool _autoBypassAttempted = false;

  @override
  void initState() {
    super.initState();
    _initAndLoadData();
  }

  /// تهيئة وتحميل البيانات - مع محاولة تجاوز Cloudflare تلقائياً
  Future<void> _initAndLoadData() async {
    // على Windows، نحاول تجاوز Cloudflare تلقائياً أولاً
    if (Platform.isWindows && !_autoBypassAttempted) {
      _autoBypassAttempted = true;

      // التحقق من وجود cookies صالحة
      await CloudflareBypassService.instance.loadSavedCookies();
      if (!CloudflareBypassService.instance.hasValidCookies) {
        // فتح WebView لتجاوز Cloudflare تلقائياً
        setState(() {
          isBypassingCloudflare = true;
        });

        final success = await CloudflareBypassService.instance.bypassCloudflare(
          context,
          'https://dashboard.ftth.iq/',
        );

        setState(() {
          isBypassingCloudflare = false;
        });

        if (!success) {
          debugPrint('⚠️ فشل تجاوز Cloudflare التلقائي');
        }
      }
    }

    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
      error = null;
      isCloudflareError = false;
    });

    try {
      // محاولة 1: جلب guest token بالطريقة الكاملة (مع resources)
      String? fetchedGuestToken = await AgentsAuthService.fetchGuestToken(
        authToken: widget.authToken,
      );

      // محاولة 2: الطريقة البسيطة
      if (fetchedGuestToken == null) {
        debugPrint('محاولة جلب Guest Token بالطريقة البسيطة...');
        fetchedGuestToken = await AgentsAuthService.fetchGuestTokenSimple(
          authToken: widget.authToken,
        );
      }

      // محاولة 3: طرق بديلة أخرى
      if (fetchedGuestToken == null) {
        debugPrint('محاولة جلب Guest Token بطرق بديلة...');
        fetchedGuestToken = await _tryAlternativeGuestToken();
      }

      if (fetchedGuestToken != null) {
        setState(() {
          guestToken = fetchedGuestToken;
        });

        // جلب بيانات Zones Stats (الطريقة الجديدة مثل المتصفح)
        final chartData = await _fetchDataWithRetry(fetchedGuestToken);

        if (chartData != null) {
          setState(() {
            rawResponse = chartData;
            usersData =
                (chartData['data'] as List?)?.cast<Map<String, dynamic>>() ??
                    [];

            // استخراج zones من البيانات
            final colnames =
                (chartData['colnames'] as List?)?.cast<String>() ?? [];

            // في My Related Zones، الأعمدة هي: ZoneType, Zone, ZoneContractor, MainZoneContractor
            if (colnames.contains('Zone')) {
              // استخراج أسماء الـ zones الفريدة من البيانات
              userZones = usersData
                  .map((row) => row['Zone']?.toString() ?? '')
                  .where((zone) => zone.isNotEmpty)
                  .toSet()
                  .toList();

              // ترتيب الـ zones
              userZones.sort();
            }

            // حساب إحصائيات الـ zones حسب النوع
            int mainZones = 0;
            int virtualZones = 0;
            for (var row in usersData) {
              final zoneType = row['ZoneType']?.toString() ?? '';
              if (zoneType == 'Main') {
                mainZones++;
              } else if (zoneType == 'Virtual') {
                virtualZones++;
              }
            }

            debugPrint('✅ تم جلب ${usersData.length} سجل');
            debugPrint('📍 عدد الـ zones الفريدة: ${userZones.length}');
            debugPrint('📍 Main Zones: $mainZones');
            debugPrint('📍 Virtual Zones: $virtualZones');
            debugPrint('📍 الأعمدة: ${colnames.join(", ")}');
          });
        } else {
          // التحقق من نوع الخطأ
          setState(() {
            if (isCloudflareError) {
              error =
                  'الخادم محمي بـ Cloudflare\nيرجى فتح Dashboard في المتصفح أولاً';
            } else {
              error = 'لا توجد بيانات متاحة';
            }
          });
        }
      } else {
        setState(() {
          error = 'فشل في الحصول على Guest Token';
        });
      }
    } catch (e) {
      setState(() {
        if (e.toString().contains('403') ||
            e.toString().contains('Cloudflare')) {
          isCloudflareError = true;
          error =
              'الخادم محمي بـ Cloudflare\nيرجى فتح Dashboard في المتصفح أولاً';
        } else {
          error = 'خطأ: $e';
        }
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  /// جلب البيانات مع إعادة المحاولة
  /// يستخدم الطريقة الجديدة (fetchZonesStats) أولاً ثم الطرق القديمة كـ fallback
  Future<Map<String, dynamic>?> _fetchDataWithRetry(String guestToken) async {
    // محاولة 1: استخدام fetchZonesStats (الطريقة الجديدة - datasource 33)
    debugPrint('🔄 محاولة fetchZonesStats (datasource 33)...');
    var chartData = await AgentsAuthService.fetchZonesStats(
      guestToken: guestToken,
      authToken: widget.authToken.isNotEmpty ? widget.authToken : null,
    );

    if (chartData != null) {
      debugPrint('✅ نجح fetchZonesStats!');
      return chartData;
    }

    // محاولة 2: استخدام fetchMyRelatedZones (datasource 26 - قائمة الـ zones فقط)
    debugPrint('🔄 محاولة fetchMyRelatedZones (datasource 26)...');
    chartData = await AgentsAuthService.fetchMyRelatedZones(
      guestToken: guestToken,
      authToken: widget.authToken.isNotEmpty ? widget.authToken : null,
    );

    if (chartData != null) {
      debugPrint('✅ نجح fetchMyRelatedZones!');
      return chartData;
    }

    // محاولة 3: جلب من Admin API مباشرة (بديل عن Superset)
    debugPrint('🔄 محاولة fetchZonesFromAdmin (Admin API)...');
    chartData = await AgentsAuthService.fetchZonesFromAdmin(
      authToken: widget.authToken.isNotEmpty ? widget.authToken : null,
    );

    if (chartData != null) {
      debugPrint('✅ نجح fetchZonesFromAdmin!');
      return chartData;
    }

    // محاولة 4: الطرق القديمة كـ fallback
    debugPrint('🔄 محاولة الطرق القديمة...');
    final sliceIds = [67, 52, 48]; // 67 = Zones Stats, 52 = My Related Zones

    for (int sliceId in sliceIds) {
      debugPrint('🔄 تجربة slice_id=$sliceId');

      // محاولة GET request
      chartData = await AgentsAuthService.fetchChartDataGet(
        sliceId,
        7,
        guestToken: guestToken,
        authToken: widget.authToken.isNotEmpty ? widget.authToken : null,
      );

      if (chartData != null) {
        debugPrint('✅ نجح slice_id=$sliceId (GET)');
        return chartData;
      }

      // محاولة POST request
      for (int i = 0; i < maxRetries; i++) {
        retryCount = i + 1;
        debugPrint('   محاولة POST $retryCount من $maxRetries');

        if (i > 0) {
          await Future.delayed(Duration(seconds: i * 2));
        }

        chartData = await AgentsAuthService.fetchChartData(
          sliceId, // slice_id
          7, // dashboard_id
          guestToken: guestToken,
          authToken: widget.authToken.isNotEmpty ? widget.authToken : null,
        );

        if (chartData != null) {
          debugPrint('✅ نجح slice_id=$sliceId (POST)');
          return chartData;
        }
      }
      debugPrint('❌ فشل slice_id=$sliceId');
    }

    // بعد فشل كل المحاولات، نفترض أنه خطأ Cloudflare
    isCloudflareError = true;
    return null;
  }

  /// محاولة جلب Guest Token بطرق بديلة
  Future<String?> _tryAlternativeGuestToken() async {
    try {
      // محاولة 1: استخدام التوكن المخزن مسبقاً
      final storedToken = await AgentsAuthService.getStoredGuestToken();
      if (storedToken != null && storedToken.isNotEmpty) {
        debugPrint('تم العثور على Guest Token مخزن');
        return storedToken;
      }

      // محاولة 2: طلب مباشر مع auth token
      final url =
          Uri.parse('https://dashboard.ftth.iq/api/v1/security/guest_token/');

      // Dashboard UUID الصحيح - Dashboard 7 "My Zones Dash"
      final requestBody = json.encode({
        "resources": [
          {"type": "dashboard", "id": "2a63cc44-01f4-4c59-a620-7d280c01411d"}
        ],
        "rls": [],
        "user": {
          "username": "viewer",
          "first_name": "viewer",
          "last_name": "viewer"
        }
      });

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'user-type': 'Partner',
        'origin': 'https://admin.ftth.iq',
        'referer': 'https://admin.ftth.iq/',
      };

      // إضافة auth token إذا كان متوفراً
      if (widget.authToken.isNotEmpty) {
        headers['authorization'] = 'Bearer ${widget.authToken}';
      }

      final response = await http
          .post(
            url,
            headers: headers,
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

  /// فتح Dashboard في المتصفح الخارجي
  Future<void> _openDashboardInBrowser() async {
    final dashboardUrl = Uri.parse(
        'https://dashboard.ftth.iq/superset/dashboard/7/?native_filters_key=&Authorization=${widget.authToken}');

    try {
      if (await canLaunchUrl(dashboardUrl)) {
        await launchUrl(dashboardUrl, mode: LaunchMode.externalApplication);

        // عرض رسالة للمستخدم
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'تم فتح Dashboard في المتصفح. بعد تسجيل الدخول، عد وأعد المحاولة'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في فتح المتصفح: $e');
    }
  }

  /// تجاوز Cloudflare باستخدام WebView (Windows فقط)
  Future<void> _bypassCloudflare() async {
    if (!Platform.isWindows) {
      // على الأنظمة الأخرى، افتح في المتصفح
      _openDashboardInBrowser();
      return;
    }

    setState(() {
      isBypassingCloudflare = true;
    });

    try {
      final success = await CloudflareBypassService.instance.bypassCloudflare(
        context,
        'https://dashboard.ftth.iq/superset/dashboard/7/',
      );

      if (success && mounted) {
        // إعادة تحميل البيانات بعد تجاوز Cloudflare
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('✅ تم تجاوز Cloudflare! جاري إعادة تحميل البيانات...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // إعادة تحميل البيانات
        await _loadData();
      }
    } catch (e) {
      debugPrint('❌ خطأ في تجاوز Cloudflare: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في تجاوز Cloudflare: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isBypassingCloudflare = false;
        });
      }
    }
  }

  // فلترة zones حسب البحث
  List<String> get filteredZones {
    if (searchQuery.isEmpty) return userZones;
    return userZones
        .where((zone) => zone.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'بيانات المستخدمين',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث البيانات',
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'معلومات',
            onPressed: () => _showInfoDialog(),
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('جاري تحميل بيانات المستخدمين...'),
                ],
              ),
            )
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isCloudflareError
                              ? Icons.security
                              : Icons.error_outline,
                          size: 64,
                          color: isCloudflareError ? Colors.orange : Colors.red,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isCloudflareError ? 'حماية Cloudflare' : 'خطأ',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isCloudflareError
                                ? Colors.orange[800]
                                : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style:
                              TextStyle(color: Colors.grey[700], fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (isCloudflareError) ...[
                          // زر تجاوز Cloudflare تلقائياً (Windows فقط)
                          if (Platform.isWindows) ...[
                            ElevatedButton.icon(
                              onPressed: isBypassingCloudflare
                                  ? null
                                  : _bypassCloudflare,
                              icon: isBypassingCloudflare
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.vpn_key),
                              label: Text(isBypassingCloudflare
                                  ? 'جاري التجاوز...'
                                  : 'تجاوز Cloudflare تلقائياً'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'أو',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 12),
                          ],
                          // زر فتح Dashboard في المتصفح
                          ElevatedButton.icon(
                            onPressed: _openDashboardInBrowser,
                            icon: const Icon(Icons.open_in_browser),
                            label: const Text('فتح Dashboard في المتصفح'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // تعليمات للمستخدم
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.info,
                                        color: Colors.blue[700], size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'خطوات الحل:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '1. اضغط على "فتح Dashboard في المتصفح"\n'
                                  '2. سجل الدخول في المتصفح\n'
                                  '3. عد إلى التطبيق واضغط "إعادة المحاولة"',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        ElevatedButton.icon(
                          onPressed: _loadData,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    // شريط الحالة
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: Colors.indigo[50],
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'متصل ✓ | عدد المناطق: ${userZones.length}',
                              style: TextStyle(
                                color: Colors.indigo[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // بطاقات الإحصائيات
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              'إجمالي المناطق',
                              userZones.length.toString(),
                              Colors.indigo,
                              Icons.location_on,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatCard(
                              'السجلات',
                              usersData.length.toString(),
                              Colors.teal,
                              Icons.table_chart,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // حقل البحث
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        onChanged: (value) {
                          setState(() {
                            searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'ابحث عن منطقة...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // عنوان القائمة
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.list, color: Colors.indigo),
                          const SizedBox(width: 8),
                          Text(
                            'قائمة المناطق (${filteredZones.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // قائمة المناطق
                    Expanded(
                      child: filteredZones.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 64, color: Colors.grey[400]),
                                  const SizedBox(height: 16),
                                  Text(
                                    'لا توجد نتائج',
                                    style: TextStyle(
                                        color: Colors.grey[600], fontSize: 16),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: filteredZones.length,
                              itemBuilder: (context, index) {
                                final zone = filteredZones[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.indigo[100],
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          color: Colors.indigo[800],
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      zone,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500),
                                    ),
                                    subtitle: Text(
                                      _getZoneType(zone),
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12),
                                    ),
                                    trailing: Icon(
                                      Icons.chevron_right,
                                      color: Colors.grey[400],
                                    ),
                                    onTap: () => _showZoneDetails(zone),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatCard(
      String title, String value, Color color, IconData icon) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getZoneType(String zone) {
    if (zone.contains('-')) {
      final parts = zone.split('-');
      if (parts.length > 1) {
        return 'فرعي - داش ${parts[1]}';
      }
    }
    return 'رئيسي';
  }

  void _showZoneDetails(String zone) {
    // البحث عن بيانات هذه المنطقة في usersData
    dynamic zoneValue;
    if (usersData.isNotEmpty) {
      zoneValue = usersData[0][zone];
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.location_on, color: Colors.indigo),
            const SizedBox(width: 8),
            Expanded(child: Text(zone)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('اسم المنطقة', zone),
            _buildDetailRow('النوع', _getZoneType(zone)),
            if (zoneValue != null)
              _buildDetailRow('القيمة', zoneValue.toString()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.indigo),
            SizedBox(width: 8),
            Text('معلومات البيانات'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('مصدر البيانات', 'Dashboard FTTH'),
              _buildDetailRow('slice_id', '48'),
              _buildDetailRow('dashboard_id', '7'),
              _buildDetailRow('نوع الرسم', 'echarts_timeseries_line'),
              const Divider(),
              _buildDetailRow('عدد المناطق', '${userZones.length}'),
              _buildDetailRow('عدد السجلات', '${usersData.length}'),
              const Divider(),
              const Text(
                'الفلاتر المطبقة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text('• Zone'),
              const Text('• eventDate'),
              const Text('• userStatus'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
