/// اسم الصفحة: إدارة المناطق
/// وصف الصفحة: صفحة عرض وإدارة المناطق الجغرافية والزونات
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/auth_service.dart';
import '../../services/zone_statistics_api_service.dart';
import '../auth/auth_error_handler.dart';

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
  bool _isExporting = false;

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
      debugPrint('Error extracting zones from data');
    }

    return fetchedZones;
  }

  Future<void> fetchZones() async {
    try {
      // 1) محاولة الجلب من admin كتعليمات المستخدم للمعلومات العامة
      final adminUrl =
          'https://admin.ftth.iq/api/locations/zones?pageSize=1000&pageNumber=1';
      final headersAdmin = {
        'Accept': 'application/json',
        // محاكاة وكيل مستخدم كما في تفاصيل الزون لتقليل مشاكل الرفض
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        // بعض الخدمات تعتمد على هذا الهيدر لتحديد نطاق البيانات
        'x-user-role': '0',
      };

      final adminResponse = await AuthService.instance.authenticatedRequest('GET', adminUrl, headers: headersAdmin);
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
      } else if (adminResponse.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return;
      } else {
        lastStatusCode = adminResponse.statusCode;
        lastBody = adminResponse.body;
        debugPrint('Admin zones fetch failed: $lastStatusCode');
      }

      // 2) في حال فشل أو لم نجد عناصر، نرجع لواجهة api العامة السابقة كبديل
      if (fetchedZones.isEmpty) {
        final apiUrl = 'https://api.ftth.iq/api/locations/zones';
        final apiResponse = await AuthService.instance.authenticatedRequest('GET', apiUrl, headers: {
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
        } else if (apiResponse.statusCode == 401) {
          if (mounted) AuthErrorHandler.handle401Error(context);
          return;
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
      debugPrint('Exception in fetchZones');
      // التحقق من أن الخطأ ليس متعلقاً بانتهاء الجلسة أو التوكن
      if (e.toString().contains('انتهت جلسة المستخدم') ||
          e.toString().contains('لا يوجد توكن صالح') ||
          e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        if (mounted) AuthErrorHandler.handle401Error(context);
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

      final url =
          'https://admin.ftth.iq/api/network-elements?zoneId=$zoneId';
      final response = await AuthService.instance.authenticatedRequest('GET', url, headers: {
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
      } else if (response.statusCode == 401) {
        if (mounted) AuthErrorHandler.handle401Error(context);
        return null;
      } else {
        debugPrint('❌ فشل جلب تفاصيل الزون $zoneId: ${response.statusCode}');
        debugPrint('📄 رسالة الخطأ: ${response.body}');
      }
    } catch (e) {
      debugPrint('💥 خطأ في جلب تفاصيل الزون $zoneId');
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
          backgroundColor: SdColors.danger,
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
              Icon(Icons.location_city, color: SdColors.primary),
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
            height: min(500, MediaQuery.of(context).size.height * 0.6),
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
                        Icon(Icons.error_outline, size: 48, color: SdColors.danger),
                        SizedBox(height: 16),
                        Text(
                          'فشل في تحميل تفاصيل الزون',
                          style: TextStyle(color: SdColors.danger),
                        ),
                        if (snapshot.hasError)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'الخطأ: ${snapshot.error}',
                              style:
                                  TextStyle(fontSize: 12, color: SdColors.muted),
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
                          color: SdColors.primaryTint,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SdColors.primaryTintEdge),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'إحصائيات الزون',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: SdColors.primary,
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
                                    SdColors.success),
                                _buildStatCard(
                                    'FATs',
                                    '${details['totalFats']}',
                                    Icons.router,
                                    SdColors.warning),
                                _buildStatCard(
                                    'ONT Vendors',
                                    '${details['totalOntVendors']}',
                                    Icons.business,
                                    SdColors.platformBase),
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
                            color: SdColors.success,
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
                            color: SdColors.platformBase,
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
                                    backgroundColor: SdColors.platformTint,
                                    labelStyle: TextStyle(
                                        color: SdColors.platformBase),
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
                  Icon(Icons.search, color: SdColors.primary),
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
                                      color: SdColors.primary),
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

  /// تصدير الزونات مع FAT إلى سيرفر VPS
  Future<void> _exportToVps() async {
    if (_isExporting || zones.isEmpty) return;

    setState(() => _isExporting = true);
    _exportCancelled = false;

    try {
      // عرض dialog لتتبع التقدم
      int processed = 0;
      final total = zones.length;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            // حفظ مرجع لتحديث الـ dialog
            _dialogSetState = setDialogState;
            _dialogProcessed = processed;
            _dialogTotal = total;
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.cloud_upload, color: SdColors.primary),
                  SizedBox(width: 8),
                  Text('تصدير إلى السيرفر'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: _dialogTotal > 0 && _dialogProcessed >= 0
                        ? _dialogProcessed / _dialogTotal
                        : null,
                    backgroundColor: SdColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        _dialogProcessed < 0 ? SdColors.warning : SdColors.primary),
                  ),
                  SizedBox(height: 12),
                  Text(
                    _dialogProcessed < 0
                        ? 'السيرفر محظور مؤقتاً... جاري الانتظار 30 ثانية'
                        : 'جاري جلب FAT... $_dialogProcessed/$_dialogTotal',
                    style: TextStyle(
                      color: _dialogProcessed < 0 ? SdColors.warningText : null,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _exportCancelled = true;
                    Navigator.of(ctx).pop();
                  },
                  child: Text('إلغاء', style: TextStyle(color: SdColors.danger)),
                ),
              ],
            );
          },
        ),
      );

      // جلب FAT لكل زون (واحد تلو الآخر لتجنب حظر السيرفر)
      final List<Map<String, dynamic>> syncData = [];
      int consecutiveFailures = 0;

      for (int i = 0; i < zones.length; i++) {
        if (_exportCancelled) break;
        final zoneName = zones[i];

        // إذا كانت التفاصيل محمّلة مسبقاً
        if (zoneDetails.containsKey(zoneName)) {
          syncData.add({
            'zoneName': zoneName,
            'fats': zoneDetails[zoneName]!['totalFats'] ?? 0,
          });
        } else {
          final zoneId = extractZoneId(zoneName);
          if (zoneId == null) {
            syncData.add({'zoneName': zoneName, 'fats': 0});
          } else {
            bool success = false;
            for (int attempt = 0; attempt < 3; attempt++) {
              try {
                final details = await fetchZoneDetails(zoneId);
                if (details != null) {
                  syncData.add({
                    'zoneName': zoneName,
                    'fats': details['totalFats'] ?? 0,
                  });
                  success = true;
                  consecutiveFailures = 0;
                  break;
                }
              } catch (_) {}
              // تأخير متزايد بين المحاولات
              await Future.delayed(Duration(seconds: 3 * (attempt + 1)));
            }
            if (!success) {
              syncData.add({'zoneName': zoneName, 'fats': 0});
              consecutiveFailures++;
              // إذا فشل 5 متتالية → توقف 30 ثانية
              if (consecutiveFailures >= 5) {
                if (_dialogSetState != null) {
                  _dialogSetState!(() {
                    _dialogProcessed = -1; // إشارة للانتظار
                  });
                }
                await Future.delayed(const Duration(seconds: 30));
                consecutiveFailures = 0;
              }
            }
          }
        }

        processed = syncData.length;
        // تحديث dialog التقدم
        if (_dialogSetState != null) {
          _dialogSetState!(() {
            _dialogProcessed = processed;
          });
        }

        // تأخير 1.5 ثانية بين كل طلب
        if (i < zones.length - 1 && !zoneDetails.containsKey(zones[i])) {
          await Future.delayed(const Duration(milliseconds: 1500));
        }
      }

      // إذا تم الإلغاء
      if (_exportCancelled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إلغاء التصدير (تم جلب ${syncData.length}/${zones.length})'),
              backgroundColor: SdColors.warning,
            ),
          );
        }
        return;
      }

      // إغلاق dialog التقدم
      if (mounted) Navigator.of(context).pop();

      // إرسال إلى VPS
      final result =
          await ZoneStatisticsApiService.instance.syncZones(syncData);

      if (!mounted) return;

      final added = result['added'] ?? 0;
      final updated = result['updated'] ?? 0;
      final unchanged = result['unchanged'] ?? 0;
      final error = result['error'];

      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $error'),
            backgroundColor: SdColors.danger,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'تم التصدير: أُضيف $added، حُدّث $updated، لم يتغير $unchanged'),
            backgroundColor: SdColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // إغلاق dialog إذا كان مفتوحاً
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في التصدير: $e'),
            backgroundColor: SdColors.danger,
          ),
        );
      }
    } finally {
      _dialogSetState = null;
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // متغيرات مؤقتة للـ dialog
  void Function(void Function())? _dialogSetState;
  int _dialogProcessed = 0;
  int _dialogTotal = 0;
  bool _exportCancelled = false;

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
        leading: Icon(Icons.device_hub, color: SdColors.success),
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
                      color: SdColors.warningText,
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
                              backgroundColor: SdColors.warningTint,
                              labelStyle:
                                  TextStyle(color: SdColors.warningText),
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
                style: TextStyle(color: SdColors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 500;
    final isWarnMessage =
        message.contains('افتراضية') || message.contains('رفض');

    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'الزونات',
          actions: [
            SdAppBarAction(
              icon: Icons.search,
              label: 'بحث عن منطقة',
              onPressed: zones.isEmpty ? null : _openZoneSearchDialog,
            ),
            if (_isExporting)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),
              )
            else
              SdAppBarAction(
                icon: Icons.cloud_upload,
                label: 'تصدير إلى السيرفر (VPS)',
                onPressed: zones.isEmpty ? null : _exportToVps,
              ),
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'إعادة تحميل الصفحة',
              onPressed: () async {
                setState(() => isLoading = true);
                await fetchZones();
              },
            ),
          ],
        ),
        body: isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(SdColors.primary),
                    ),
                    SizedBox(height: 16),
                    Text('جاري تحميل المناطق...', style: SdText.bodySm),
                  ],
                ),
              )
            : SafeArea(
                top: false,
                child: Column(
                  children: [
                    // عرض رسالة الحالة
                    if (message.isNotEmpty)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isWarnMessage
                              ? SdColors.warningTint
                              : SdColors.dangerTint,
                          border: Border.all(
                            color: isWarnMessage
                                ? SdColors.warning
                                : SdColors.danger,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isWarnMessage ? Icons.warning : Icons.error,
                              color: isWarnMessage
                                  ? SdColors.warning
                                  : SdColors.danger,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                message,
                                style: TextStyle(
                                  color: isWarnMessage
                                      ? SdColors.warningText
                                      : const Color(0xFFB71C1C),
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
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: SdColors.infoTint,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SdColors.infoTintEdge),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: SdColors.info),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(
                                  'المعروض في التطبيق: $totalZones',
                                  style: TextStyle(
                                    fontSize: isPhone ? 16 : 20,
                                    fontWeight: FontWeight.bold,
                                    color: SdColors.infoEdge,
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
                              child: SdEmptyState(
                                icon: Icons.location_off,
                                title: 'لا توجد مناطق للعرض',
                                message:
                                    'اضغط على زر التحديث للمحاولة مرة أخرى',
                                action: SdButton(
                                  label: 'إعادة المحاولة',
                                  icon: Icons.refresh,
                                  onPressed: () async {
                                    setState(() => isLoading = true);
                                    await fetchZones();
                                  },
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: zones.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SdRaised(
                                    onTap: () => showZoneDetails(zones[index]),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: SdColors.primary,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.location_city,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                zones[index],
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: SdColors.ink,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'المنطقة رقم ${index + 1} - اضغط لعرض التفاصيل',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: SdColors.muted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.info_outline,
                                          color: SdColors.info,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          color: SdColors.primary,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
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
        backgroundColor: SdColors.info,
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
        backgroundColor: SdColors.info,
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
    final url =
        'https://api.ftth.iq/api/notifications?onlyUnreadNotifications=true&pageSize=50&pageNumber=1';
    final response = await AuthService.instance.authenticatedRequest('GET', url, headers: {
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
        backgroundColor: SdColors.info,
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
                style: TextStyle(color: SdColors.danger, fontSize: 16),
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
                      style: TextStyle(fontSize: 12, color: SdColors.muted),
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
