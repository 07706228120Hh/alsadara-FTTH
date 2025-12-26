/// اسم الصفحة: إدارة المناطق
/// وصف الصفحة: صفحة عرض وإدارة المناطق الجغرافية والزونات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../utils/smart_text_color.dart';
import '../auth/login_page.dart';

class ZonesPage extends StatefulWidget {
  final String authToken;
  const ZonesPage({super.key, required this.authToken});

  @override
  State<ZonesPage> createState() => _ZonesPageState();
}

class _ZonesPageState extends State<ZonesPage> {
  List<String> zones = [];
  bool isLoading = true;
  String message = "";
  int totalZones = 0;
  int serverTotalCount = 0;
  // إضافة متغيرات ج��يدة لتفاصيل الزونات
  Map<String, Map<String, dynamic>> zoneDetails = {};
  Map<String, bool> zoneDetailsLoading = {};

  @override
  void initState() {
    super.initState();
    fetchZones();
  }

  // دالة مساعدة لاستخراج اسم الزون من عنصر واحد بأي بنية محتملة
  String _extractZoneNameFromItem(Map<String, dynamic> zone) {
    try {
      if (zone['self'] != null && zone['self'] is Map) {
        final self = zone['self'] as Map;
        if (self['displayValue'] != null &&
            self['displayValue'].toString().trim().isNotEmpty) {
          return self['displayValue'].toString();
        }
        // fallback إضافي: استخدام self.id إذا displayValue غير متوفر
        if (self['id'] != null && self['id'].toString().trim().isNotEmpty) {
          return self['id'].toString();
        }
      }
      if (zone['displayValue'] != null) return zone['displayValue'].toString();
      if (zone['name'] != null) return zone['name'].toString();
      if (zone['title'] != null) return zone['title'].toString();
      if (zone['zoneName'] != null) return zone['zoneName'].toString();
      if (zone['id'] != null) return zone['id'].toString();
    } catch (_) {}
    return 'غير معروف';
  }

  // دالة مساعدة لاستخراج قائمة الزونات من استجابة API ببنيات متعددة
  List<String> _extractZonesFromData(dynamic data) {
    final List<String> fetchedZones = [];

    try {
      if (data == null) return fetchedZones;

      // إذا كانت الاستجابة مصفوفة مباشرة
      if (data is List) {
        for (final item in data) {
          if (item is Map<String, dynamic>) {
            final name = _extractZoneNameFromItem(item);
            if (name == 'غير معروف') {
              debugPrint('Unknown zone item (list form): $item');
            }
            fetchedZones.add(name);
          } else if (item != null) {
            // في حال العنصر نصي مباشر
            fetchedZones.add(item.toString());
          } else {
            fetchedZones.add('غير معروف');
          }
        }
        return fetchedZones;
      }

      if (data is Map<String, dynamic>) {
        // الشكل الشائع: { items: [...] }
        if (data['items'] is List) {
          for (final zone in (data['items'] as List)) {
            if (zone is Map<String, dynamic>) {
              final name = _extractZoneNameFromItem(zone);
              if (name == 'غير معروف') {
                debugPrint('Unknown zone item (items form): $zone');
              }
              fetchedZones.add(name);
            } else if (zone != null) {
              fetchedZones.add(zone.toString());
            } else {
              fetchedZones.add('غير معروف');
            }
          }
        }

        // شكل بديل: { model: { items: [...] } }
        else if (data['model'] is Map && (data['model']['items'] is List)) {
          for (final zone in (data['model']['items'] as List)) {
            if (zone is Map<String, dynamic>) {
              final name = _extractZoneNameFromItem(zone);
              if (name == 'غير معروف') {
                debugPrint('Unknown zone item (model.items form): $zone');
              }
              fetchedZones.add(name);
            } else if (zone != null) {
              fetchedZones.add(zone.toString());
            } else {
              fetchedZones.add('غير معروف');
            }
          }
        }

        // شكل بديل آخر: { zones: [...] }
        else if (data['zones'] is List) {
          for (final zone in (data['zones'] as List)) {
            if (zone is Map<String, dynamic>) {
              final name = _extractZoneNameFromItem(zone);
              if (name == 'غير معروف') {
                debugPrint('Unknown zone item (zones form): $zone');
              }
              fetchedZones.add(name);
            } else if (zone != null) {
              fetchedZones.add(zone.toString());
            } else {
              fetchedZones.add('غير معروف');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error extracting zones from data: $e');
    }

    return fetchedZones;
  }

  Future<void> fetchZones() async {
    try {
      // 1) محاولة الجلب من admin كتعليمات المستخدم للمعلومات العامة
      final adminUrl = Uri.parse(
          'https://admin.ftth.iq/api/locations/zones?pageSize=1000&pageNumber=1');
      final headersAdmin = {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
        // محاكاة وكيل مستخدم كما في تفاصيل الزون لتقليل مشاكل الرفض
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        // بعض الخدمات تعتمد على هذا الهيدر لتحديد نطاق البيانات
        'x-user-role': '0',
      };

      final adminResponse = await http.get(adminUrl, headers: headersAdmin);
      debugPrint('Admin Zones Response Code: ${adminResponse.statusCode}');

      List<String> fetchedZones = [];
      int? lastStatusCode;
      String? lastBody;

      if (adminResponse.statusCode == 200) {
        final data = jsonDecode(adminResponse.body);
        debugPrint('Admin API Response keys: '
            '${data is Map ? (data).keys : 'N/A'}');
        fetchedZones = _extractZonesFromData(data);
        if (data is Map<String, dynamic>) {
          final totalCount = data['totalCount'];
          debugPrint(
              'Admin totalCount: $totalCount, extracted: ${fetchedZones.length}');
          serverTotalCount = totalCount is int ? totalCount : 0;
        } else {
          serverTotalCount = 0;
        }
        lastStatusCode = 200;
      } else {
        lastStatusCode = adminResponse.statusCode;
        lastBody = adminResponse.body;
        debugPrint('Admin zones fetch failed: $lastStatusCode');
      }

      // 2) في حال فشل أو لم نجد عناصر، نرجع لواجهة api العامة السابقة كبديل
      if (fetchedZones.isEmpty) {
        final apiUrl = Uri.parse('https://api.ftth.iq/api/locations/zones');
        final apiResponse = await http.get(apiUrl, headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
          'x-user-role': '0',
        });
        debugPrint('Public API Zones Response Code: ${apiResponse.statusCode}');

        if (apiResponse.statusCode == 200) {
          final data = jsonDecode(apiResponse.body);
          debugPrint('Public API Response keys: '
              '${data is Map ? (data).keys : 'N/A'}');
          fetchedZones = _extractZonesFromData(data);
          if (data is Map<String, dynamic>) {
            final totalCount = data['totalCount'];
            serverTotalCount = totalCount is int ? totalCount : 0;
          }
          lastStatusCode = 200;
        } else {
          lastStatusCode = apiResponse.statusCode;
          lastBody = apiResponse.body;
        }
      }

      if (!mounted) return;

      setState(() {
        if (fetchedZones.isEmpty) {
          // تحديد الرسالة حسب آخر حالة/كود
          if (lastStatusCode == 403) {
            message =
                "تم رفض الوصول: يبدو أنك لا تمتلك الصلاحيات اللازمة لعرض البيانات. الرجاء مراجعة الصلاحيات.";
          } else if (lastStatusCode != null) {
            message =
                "فشل جلب البيانات: $lastStatusCode${lastBody != null ? ' - $lastBody' : ''}";
          } else {
            message =
                "تم عرض بيانات افتراضية - لم يتم العثور على مناطق في الاستجابة";
          }

          zones = ['المنطقة الأولى', 'المنطقة الثانية', 'المنطقة الثالثة'];
        } else {
          zones = fetchedZones..sort();
          message = "";
        }

        totalZones = zones.length;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Exception in fetchZones: $e');
      // التحقق من أن الخطأ ليس متعلقاً بانتهاء الجلسة أو التوكن
      if (e.toString().contains('انتهت جلسة المستخدم') ||
          e.toString().contains('لا يوجد توكن صالح') ||
          e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (Route<dynamic> route) => false,
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        message = "حدث خطأ أثناء جلب البيانات: $e";
        isLoading = false;
      });
    }
  }

  // دالة جلب تفاصيل زون محدد
  Future<Map<String, dynamic>?> fetchZoneDetails(String zoneId) async {
    try {
      debugPrint('🔍 جلب تفاصيل الزون: $zoneId');

      final url = Uri.parse(
          'https://admin.ftth.iq/api/network-elements?zoneId=$zoneId');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      });

      debugPrint('📡 استجابة API للزون $zoneId: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ تم جلب تفاصيل الزون $zoneId بنجاح');
        debugPrint('📊 البيانات المُستلمة: $data');

        // تحليل البيانات وحفظها
        if (data != null && data['model'] != null) {
          final model = data['model'];
          final fdts = model['fdts'] ?? [];
          final ontVendors = model['ontVendors'] ?? [];

          int totalFats = 0;
          for (var fdt in fdts) {
            if (fdt['fats'] != null) {
              totalFats += (fdt['fats'] as List).length;
            }
          }

          final details = {
            'fdts': fdts,
            'ontVendors': ontVendors,
            'totalFdts': fdts.length,
            'totalFats': totalFats,
            'totalOntVendors': ontVendors.length,
          };

          debugPrint('📈 إحصائيات الزون $zoneId:');
          debugPrint('  - عدد FDTs: ${details['totalFdts']}');
          debugPrint('  - عدد FATs: ${details['totalFats']}');
          debugPrint('  - عدد ONT Vendors: ${details['totalOntVendors']}');
          return details;
        }
      } else {
        debugPrint('❌ فشل جلب تفاصيل الزون $zoneId: ${response.statusCode}');
        debugPrint('📄 رسالة الخطأ: ${response.body}');
      }
    } catch (e) {
      debugPrint('💥 خطأ في جلب تفاصيل الزون $zoneId: $e');
    }

    return null;
  }

  // دالة جلب تفاصيل زون محدد مع تحديث الحالة
  Future<void> loadZoneDetails(String zoneId) async {
    if (zoneDetails.containsKey(zoneId)) {
      debugPrint('🎯 تفاصيل الزون $zoneId موجودة مسبقاً');
      return; // البيانات موجودة مسبقاً
    }

    setState(() {
      zoneDetailsLoading[zoneId] = true;
    });

    final details = await fetchZoneDetails(zoneId);

    if (mounted) {
      setState(() {
        zoneDetailsLoading[zoneId] = false;
        if (details != null) {
          zoneDetails[zoneId] = details;
        }
      });
    }
  }

  // دالة استخراج معرف الزون من اسم الزون
  String? extractZoneId(String zoneName) {
    // في حالة أن اسم الزون هو نفسه المعرف (مثل FBG1027)
    // يمكن تحسين هذه الدالة بناءً على بنية البيانات الفعلية
    if (zoneName.contains('FBG') || zoneName.contains('FDT')) {
      return zoneName;
    }

    // إذا كان اسم الزون مختلف عن المعرف، نحتاج لتحديد طريقة الربط
    // مؤقتاً سنرجع اسم الزون نفسه
    return zoneName;
  }

  // دالة عرض تفاصيل الزون في نافذة منبثقة
  void showZoneDetails(String zoneName) {
    final zoneId = extractZoneId(zoneName);
    if (zoneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا يمكن تحديد معرف الزون'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.location_city, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تفاصيل الزون: $zoneName',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 500,
            child: FutureBuilder<Map<String, dynamic>?>(
              future: fetchZoneDetails(zoneId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('جاري تحميل تفاصيل الزون...'),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red),
                        SizedBox(height: 16),
                        Text(
                          'فشل في تحميل تفاصيل الزون',
                          style: TextStyle(color: Colors.red),
                        ),
                        if (snapshot.hasError)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'الخطأ: ${snapshot.error}',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  );
                }

                final details = snapshot.data!;
                final fdts = details['fdts'] as List;
                final ontVendors = details['ontVendors'] as List;

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // إحصائيات عامة
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'إحصائيات الزون',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatCard(
                                    'FDTs',
                                    '${details['totalFdts']}',
                                    Icons.device_hub,
                                    Colors.green),
                                _buildStatCard(
                                    'FATs',
                                    '${details['totalFats']}',
                                    Icons.router,
                                    Colors.orange),
                                _buildStatCard(
                                    'ONT Vendors',
                                    '${details['totalOntVendors']}',
                                    Icons.business,
                                    Colors.purple),
                              ],
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 16),

                      // قائمة FDTs
                      if (fdts.isNotEmpty) ...[
                        Text(
                          'FDTs (${fdts.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                        SizedBox(height: 8),
                        ...fdts.map((fdt) => _buildFdtCard(fdt)),
                        SizedBox(height: 16),
                      ],

                      // قائمة ONT Vendors
                      if (ontVendors.isNotEmpty) ...[
                        Text(
                          'ONT Vendors (${ontVendors.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ontVendors
                              .map((vendor) => Chip(
                                    label: Text(
                                        vendor['displayValue'] ?? 'غير معروف'),
                                    backgroundColor: Colors.purple.shade100,
                                    labelStyle: TextStyle(
                                        color: Colors.purple.shade800),
                                  ))
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  // نافذة بحث مخصصة لا تؤثر على القائمة الرئيسية
  Future<void> _openZoneSearchDialog() async {
    if (zones.isEmpty) return;

    await showDialog(
      context: context,
      builder: (context) {
        String query = '';
        List<String> filtered = List<String>.from(zones);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            List<String> filter(String q) {
              final t = q.trim().toLowerCase();
              if (t.isEmpty) return List<String>.from(zones);
              final results =
                  zones.where((z) => z.toLowerCase().contains(t)).toList();
              results.sort();
              return results;
            }

            return AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.search, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('بحث عن منطقة'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'اكتب اسم المنطقة أو جزء منه...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (v) {
                        setStateDialog(() {
                          query = v;
                          filtered = filter(query);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Center(child: Text('لا توجد نتائج'))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final zone = filtered[index];
                                return ListTile(
                                  leading: const Icon(Icons.location_city,
                                      color: Colors.blue),
                                  title: Text(zone),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    showZoneDetails(zone);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إغلاق'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // دالة مساعدة لبناء بطاقة إحصائية
  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  // دالة مساعدة لبناء بطاقة FDT
  Widget _buildFdtCard(Map<String, dynamic> fdt) {
    final fats = fdt['fats'] as List? ?? [];

    return Card(
      margin: EdgeInsets.only(bottom: 8),
      elevation: 2,
      child: ExpansionTile(
        leading: Icon(Icons.device_hub, color: Colors.green),
        title: Text(
          fdt['displayValue'] ?? 'FDT غير معروف',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${fats.length} FAT'),
        children: [
          if (fats.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FATs (${fats.length}):',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: fats
                        .map((fat) => Chip(
                              label: Text(
                                fat['displayValue'] ?? 'غير معروف',
                                style: TextStyle(fontSize: 12),
                              ),
                              backgroundColor: Colors.orange.shade100,
                              labelStyle:
                                  TextStyle(color: Colors.orange.shade800),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'لا توجد FATs',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // تحديد ألوان التدرج للـ AppBar
    final gradientColors = [Colors.blueAccent, Colors.blue[600]!];

    // تحديد لون النص والأيقونات بطريقة ذكية
    final smartTextColor =
        SmartTextColor.getAppBarTextColorWithGradient(context, gradientColors);
    final smartIconColor = smartTextColor;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        title: Text(
          'الزونات',
          style: SmartTextColor.getSmartTextStyle(
            context: context,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            gradientColors: gradientColors,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: smartIconColor, size: 28),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: smartIconColor, size: 28),
            tooltip: 'بحث عن منطقة',
            onPressed: zones.isEmpty ? null : _openZoneSearchDialog,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: smartIconColor, size: 28),
            tooltip: 'إعادة تحميل الصفحة',
            onPressed: () async {
              setState(() => isLoading = true);
              await fetchZones();
            },
          ),
        ],
      ),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'جاري تحميل المناطق...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // عرض رسالة الحالة
                if (message.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.all(16),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: message.contains('افتراضية') ||
                              message.contains('رفض')
                          ? Colors.orange[50]
                          : Colors.red[50],
                      border: Border.all(
                        color: message.contains('افتراضية') ||
                                message.contains('رفض')
                            ? Colors.orange
                            : Colors.red,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          message.contains('افتراضية') ||
                                  message.contains('رفض')
                              ? Icons.warning
                              : Icons.error,
                          color: message.contains('افتراضية') ||
                                  message.contains('رفض')
                              ? Colors.orange
                              : Colors.red,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            style: TextStyle(
                              color: message.contains('افتراضية') ||
                                      message.contains('رفض')
                                  ? Colors.orange[800]
                                  : Colors.red[800],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // عرض إحصائيات
                if (zones.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.blue),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 2),
                            Text(
                              'المعروض في التطبيق: $totalZones',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[800],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // قائمة المناطق
                Expanded(
                  child: zones.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_off,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد مناطق للعرض',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'اضغط على زر التحديث للمحاولة مرة أخرى',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                              SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  setState(() => isLoading = true);
                                  await fetchZones();
                                },
                                icon: Icon(Icons.refresh),
                                label: Text('إعادة المحاولة'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          itemCount: zones.length,
                          itemBuilder: (context, index) {
                            return Card(
                              margin: EdgeInsets.only(bottom: 8),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white,
                                      Colors.blue[50]!,
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                  leading: Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.location_city,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    zones[index],
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                  subtitle: Text(
                                    'المنطقة رقم ${index + 1} - اضغط لعرض التفاصيل',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.blue,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.blueAccent,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    // عرض تفاصيل الزون
                                    showZoneDetails(zones[index]);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// مفوض البحث عن المناطق
class ZonesSearchDelegate extends SearchDelegate<String> {
  final List<String> zones;

  ZonesSearchDelegate({required this.zones});

  @override
  String? get searchFieldLabel => 'ابحث عن منطقة...';

  @override
  TextInputAction get textInputAction => TextInputAction.search;

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
          tooltip: 'مسح',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
      tooltip: 'إغلاق',
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = _filtered();
    return _buildList(context, results);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = _filtered();
    return _buildList(context, results);
  }

  List<String> _filtered() {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return zones;
    return zones.where((z) => z.toLowerCase().contains(q)).toList()..sort();
  }

  Widget _buildList(BuildContext context, List<String> items) {
    if (items.isEmpty) {
      return const Center(child: Text('لا توجد نتائج'));
    }
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final zone = items[index];
        return ListTile(
          leading: const Icon(Icons.location_city),
          title: Text(zone),
          onTap: () => close(context, zone),
        );
      },
    );
  }
}

class PartnersPage extends StatelessWidget {
  final String authToken;

  const PartnersPage({super.key, required this.authToken});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text('الشركاء',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
      ),
      body: Center(
        child:
            Text('صفحة الشركاء قيد التطوير.', style: TextStyle(fontSize: 18)),
      ),
    );
  }
}

class FinancialTransactionsPage extends StatelessWidget {
  final String authToken;

  const FinancialTransactionsPage({super.key, required this.authToken});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text('المعاملات المالية',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
      ),
      body: Center(
        child: Text('صفحة المعاملات المالية قيد التطوير.',
            style: TextStyle(fontSize: 18)),
      ),
    );
  }
}

class ZoneNotificationsPage extends StatelessWidget {
  final String authToken;

  const ZoneNotificationsPage({super.key, required this.authToken});

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final url = Uri.parse(
        'https://api.ftth.iq/api/notifications?onlyUnreadNotifications=true&pageSize=50&pageNumber=1');
    final response = await http.get(url, headers: {
      'Authorization': 'Bearer $authToken',
      'Accept': 'application/json',
    });

    debugPrint('Notifications Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['items'] ?? []).cast<Map<String, dynamic>>();
    } else {
      throw Exception(
          'فشل جلب الإشعارات: ${response.statusCode} - ${response.body}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text('الإشعارات',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blueAccent,
        iconTheme: const IconThemeData(color: Colors.white, size: 20),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: fetchNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: SelectableText(
                '${snapshot.error}',
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(
                'لا توجد إشعارات جديدة.',
                style: TextStyle(fontSize: 16),
              ),
            );
          } else {
            final notifications = snapshot.data!;
            return ListView.builder(
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    title: Text(
                      notification['self']['displayValue'] ??
                          'إشعار بدون عنوان',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    subtitle:
                        Text(notification['description'] ?? 'لا يوجد وصف'),
                    trailing: Text(
                      notification['createdAt'] ?? '',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}
