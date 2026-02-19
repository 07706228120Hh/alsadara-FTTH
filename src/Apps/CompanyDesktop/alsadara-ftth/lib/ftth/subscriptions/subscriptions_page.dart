/// اسم الصفحة: الاشتراكات
/// وصف الصفحة: صفحة إدارة الاشتراكات الفعالة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../utils/smart_text_color.dart';
import 'package:intl/intl.dart';
import '../../services/permissions_service.dart';
import '../../services/local_database_service.dart';
import '../../services/whatsapp_bulk_sender_service.dart';
import '../../services/whatsapp_business_service.dart';
import '../../pages/whatsapp_batch_reports_page.dart';
import '../../services/permission_checker.dart';

// استثناء خاص لإلغاء عمليات التصدير
class _CancelledExport implements Exception {
  final String message;
  const _CancelledExport() : message = 'تم إلغاء عملية التصدير';
  @override
  String toString() => message;
}

class SubscriptionsPage extends StatefulWidget {
  final String authToken;
  const SubscriptionsPage({super.key, required this.authToken});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  // === متغيرات البيانات الأساسية ===
  List<dynamic> subscriptions = [];
  List<dynamic> zones = [];
  bool isLoading = true;
  bool isFiltering = false;
  bool isExporting = false;
  String errorMessage = "";
  String progressMessage = "";
  bool zonesLoading = false;
  String zoneErrorMessage = '';
  double exportProgress = 0.0;
  int totalItemsToExport = 0;
  int exportedItemsCount = 0;
  bool _cancelRequested = false;
  // عدادات المناطق المختارة المتعددة
  Map<String, int> multiZoneCounts = {}; // zoneId -> count
  bool multiZoneCountsLoading = false;
  int _zoneCountsRequestId = 0; // لضمان إهمال النتائج القديمة
  // معرّف طلب حالي للاشتراكات لمنع تداخل تحديثات الأجهزة/التفاصيل القديمة
  int _currentFetchId = 0;
  // معرّف طلب تحسين (تفاصيل + أجهزة) لإلغاء الدُفعات القديمة عند تصفية جديدة
  int _enhanceRequestId = 0;

  // === متغيرات جلب أرقام الهواتف من التخزين المحلي ===
  bool _isLoadingLocalPhones = false;
  bool _localPhonesLoaded = false;
  Map<String, String> _localPhonesMap = {}; // subscriptionId -> phone
  bool _exportWithLocalPhones =
      false; // خيار جلب الأرقام من الذاكرة عند التصدير

  // === متغيرات الإرسال الجماعي ===
  // ignore: unused_field
  final bool _isBulkSending = false;
  // ignore: unused_field
  final bool _isLoadingAllSubscriptions = false;

  // === حالة التصفية ===
  String selectedStatus = 'الكل';
  String selectedZoneId = 'all';
  final Set<String> selectedZoneIds = <String>{};
  String zoneSearchQuery = '';
  final TextEditingController fromDateController = TextEditingController();
  final TextEditingController toDateController = TextEditingController();
  final TextEditingController customerNameController = TextEditingController();

  // === التقسيم إلى صفحات ===
  int pageSize = 25;
  int currentPage = 1;
  int totalSubscriptions = 0;
  final List<int> pageSizeOptions = [25, 50, 100];

  // API URLs
  final String allUrl =
      'https://admin.ftth.iq/api/subscriptions?sortCriteria.property=expires&sortCriteria.direction=asc&hierarchyLevel=0';
  final String activeUrl =
      'https://admin.ftth.iq/api/subscriptions?sortCriteria.property=expires&sortCriteria.direction=asc&status=Active&hierarchyLevel=0';
  final String expiredUrl =
      'https://admin.ftth.iq/api/subscriptions?sortCriteria.property=expires&sortCriteria.direction=asc&status=Expired&hierarchyLevel=0';

  // Export auth
  final TextEditingController _exportPasswordController =
      TextEditingController();
  bool askingPassword = false;
  bool showExportOptions = false;
  bool _showPassword = false;
  String? _passwordError;
  // تمت إزالة الكاش السابق للمناطق (_zonesVersion, _cachedFilteredZones, _lastZoneSearchQuery) بعد الانتقال إلى BottomSheet.

  @override
  void initState() {
    super.initState();
    // تحميل الاشتراكات والمناطق مبكراً (المناطق بدون عرضها لتجهيزها لاحقاً)
    fetchSubscriptions();
    fetchZones();
  }

  /// جلب تفاصيل الاشتراك الكاملة
  Future<Map<String, dynamic>?> fetchSubscriptionDetails(
      String subscriptionId) async {
    try {
      final response = await http.get(
        Uri.parse('https://admin.ftth.iq/api/subscriptions/$subscriptionId'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('خطأ تفاصيل الاشتراك $subscriptionId: $e');
    }
    return null;
  }

  Future<Map<String, Map<String, dynamic>>> fetchMultipleSubscriptionsDetails(
      List<String> ids) async {
    final Map<String, Map<String, dynamic>> out = {};
    const batchSize = 10;
    for (int i = 0; i < ids.length; i += batchSize) {
      final batch = ids.skip(i).take(batchSize).toList();
      final results = await Future.wait(batch.map(fetchSubscriptionDetails));
      for (int j = 0; j < batch.length; j++) {
        final r = results[j];
        if (r != null) out[batch[j]] = r;
      }
      if (i + batchSize < ids.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
    return out;
  }

  Future<Map<String, dynamic>?> fetchSubscriptionDevice(
      String subscriptionId) async {
    try {
      final response = await http.get(
        Uri.parse(
            'https://admin.ftth.iq/api/subscriptions/$subscriptionId/device'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['model'] is Map<String, dynamic>) return decoded['model'];
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('خطأ جهاز الاشتراك $subscriptionId: $e');
    }
    return null;
  }

  Future<Map<String, Map<String, dynamic>>> fetchMultipleSubscriptionsDevices(
      List<String> ids) async {
    final Map<String, Map<String, dynamic>> devices = {};
    const batchSize = 12;
    for (int i = 0; i < ids.length; i += batchSize) {
      final batch = ids.skip(i).take(batchSize).toList();
      final results = await Future.wait(batch.map(fetchSubscriptionDevice));
      for (int j = 0; j < batch.length; j++) {
        final r = results[j];
        if (r != null) devices[batch[j]] = r;
      }
      if (i + batchSize < ids.length) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
    }
    return devices;
  }

  @override
  void dispose() {
    fromDateController.dispose();
    toDateController.dispose();
    customerNameController.dispose();
    _exportPasswordController.dispose();
    super.dispose();
  }

  /// جلب قائمة المناطق من الخادم
  Future<void> fetchZones() async {
    if (!mounted) return;
    if (zonesLoading) return; // منع التكرار
    setState(() {
      zonesLoading = true;
      zoneErrorMessage = '';
    });
    try {
      final response = await http.get(
        Uri.parse('https://admin.ftth.iq/api/locations/zones'),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': 'application/json',
        },
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> rawZones = data['items'] ?? [];
        if (rawZones.isNotEmpty) {
          debugPrint('تم جلب ${rawZones.length} منطقة بنجاح');
        }
        final List<Map<String, String>> parsedZones = rawZones
            .map<Map<String, String>>((zone) {
              String id = '';
              String displayValue = 'غير معروف';
              if (zone is Map<String, dynamic>) {
                if (zone['self'] != null &&
                    zone['self'] is Map<String, dynamic>) {
                  id = zone['self']['id']?.toString() ?? '';
                  displayValue =
                      zone['self']['displayValue']?.toString() ?? 'غير معروف';
                } else {
                  id = zone['id']?.toString() ?? '';
                  if (zone['displayValue'] != null) {
                    displayValue = zone['displayValue'].toString();
                  } else if (zone['name'] != null) {
                    displayValue = zone['name'].toString();
                  } else if (zone['title'] != null) {
                    displayValue = zone['title'].toString();
                  } else if (id.isNotEmpty) {
                    displayValue = id;
                  }
                }
              }
              return {'id': id, 'displayValue': displayValue};
            })
            .where((zone) => zone['id'] != null && zone['id']!.isNotEmpty)
            .toList();
        // ترتيب تصاعدي (طبيعي)
        parsedZones.sort((a, b) => _alphaNumericCompare(
              a['displayValue'] ?? '',
              b['displayValue'] ?? '',
            ));
        setState(() {
          zones = parsedZones;
          if (selectedZoneId != 'all' &&
              !zones.any((z) => z['id'] == selectedZoneId)) {
            selectedZoneId = 'all';
          }
        });
      } else {
        setState(() {
          zoneErrorMessage = 'فشل جلب المناطق: ${response.statusCode}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          zoneErrorMessage = 'حدث خطأ أثناء جلب المناطق: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          zonesLoading = false;
        });
      }
    }
  }

  // مقارنة أبجدية-رقمية: تقارن البادئة النصية أولاً ثم أول رقم موجود إن وجد
  int _alphaNumericCompare(String a, String b) {
    final la = a.toLowerCase();
    final lb = b.toLowerCase();
    final reg = RegExp(r'^(.*?)(\d+)(.*) ?');
    final ma = reg.firstMatch(la);
    final mb = reg.firstMatch(lb);

    if (ma != null && mb != null) {
      final pa = ma.group(1) ?? '';
      final pb = mb.group(1) ?? '';
      final prefixCompare = pa.compareTo(pb);
      if (prefixCompare != 0) return prefixCompare;
      final na = int.tryParse(ma.group(2) ?? '') ?? 0;
      final nb = int.tryParse(mb.group(2) ?? '') ?? 0;
      if (na != nb) return na.compareTo(nb);
      // إذا تساوت الأرقام، ارجع للمقارنة الكاملة كحل نهائي
      return la.compareTo(lb);
    }

    // إذا لم يوجد أرقام في أحدهما، استخدم المقارنة النصية العادية
    return la.compareTo(lb);
  }

  /// تحديد رابط API حسب نوع الفلتر المختار
  String getApiUrl() {
    if (selectedStatus == 'الفعال') {
      return activeUrl;
    } else if (selectedStatus == 'المنتهي') {
      return expiredUrl;
    } else {
      return allUrl;
    }
  }

  /// جلب قائمة الاشتراكات (عرض سريع ثم تحسين تدريجي)
  Future<void> fetchSubscriptions({bool applyFilters = false}) async {
    if (!mounted) return;
    const requestTimeout = Duration(seconds: 15);
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    final int fetchId = ++_currentFetchId; // تمييز هذا الجلب
    try {
      // في حالة اختيار أكثر من منطقة: تنفيذ جلب مخصص ودمج محلي
      if (selectedZoneIds.length > 1) {
        await _fetchMultiZonesCombined(applyFilters: applyFilters);
        // بعد دمج متعدد المناطق نطلق جلب سريع للأجهزة
        unawaited(_quickLoadDevicesFor(subscriptions, fetchId));
        return;
      }
      String url = "${getApiUrl()}&pageNumber=$currentPage&pageSize=$pageSize";
      if (applyFilters) {
        final fromDate = fromDateController.text.trim();
        final toDate = toDateController.text.trim();
        final customerName = customerNameController.text.trim();
        // إصلاح: عند اختيار أكثر من منطقة كان يتم تمرير المعامل مكرراً &zoneId= فيتجاهل الخادم الباقي
        // الحل: إذا كان هناك أكثر من منطقة نستخدم zoneIds=ID1,ID2,ID3
        if (selectedZoneIds.isNotEmpty) {
          final zonesList = selectedZoneIds.toList();
          if (zonesList.length == 1) {
            url += '&zoneId=${zonesList.first}';
          } else {
            url += '&zoneIds=${zonesList.join(',')}';
          }
        } else if (selectedZoneId.isNotEmpty && selectedZoneId != 'all') {
          url += '&zoneId=$selectedZoneId';
        }
        if (fromDate.isNotEmpty) url += '&fromExpirationDate=$fromDate';
        if (toDate.isNotEmpty) url += '&toExpirationDate=$toDate';
        if (customerName.isNotEmpty) url += '&customerName=$customerName';
      }

      final response = await http.get(Uri.parse(url), headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
      }).timeout(requestTimeout, onTimeout: () {
        throw TimeoutException('انتهى وقت الانتظار للاتصال');
      });

      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          errorMessage = 'فشل جلب البيانات: ${response.statusCode}';
          isLoading = false;
        });
        return;
      }

      final data = jsonDecode(response.body);
      final List<dynamic> rawSubscriptions = data['items'] ?? [];
      setState(() {
        totalSubscriptions = data['totalCount'] ?? rawSubscriptions.length;
        subscriptions = rawSubscriptions; // عرض فوري
        isLoading = false;
      });

      // جلب سريع للأجهزة (للحصول على FAT و Serial مبكراً) دون انتظار تحسين كامل
      unawaited(_quickLoadDevicesFor(rawSubscriptions, fetchId));

      // جلب عدادات المناطق المتعددة إن لزم
      if (selectedZoneIds.length > 1) {
        fetchSelectedZonesCounts(
            fromDate: fromDateController.text.trim(),
            toDate: toDateController.text.trim(),
            customerName: customerNameController.text.trim());
      } else {
        if (multiZoneCounts.isNotEmpty) {
          setState(() => multiZoneCounts.clear());
        }
      }

      // تحسين البيانات في الخلفية بدون حجب الواجهة
      if (rawSubscriptions.isNotEmpty) {
        unawaited(_enhanceSubscriptions(rawSubscriptions, fetchId));
      }
    } on TimeoutException catch (_) {
      if (mounted) {
        setState(() {
          errorMessage = 'انتهى وقت الانتظار. تحقق من الشبكة';
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'حدث خطأ: $e';
          isLoading = false;
        });
      }
    }
  }

  /// جلب ودمج اشتراكات عدة مناطق محلياً (حل بديل لأن API لا يعيد نتائج صحيحة عند تمرير عدة zoneId)
  Future<void> _fetchMultiZonesCombined({bool applyFilters = false}) async {
    final currentZones = selectedZoneIds.toList();
    final fromDate = applyFilters ? fromDateController.text.trim() : '';
    final toDate = applyFilters ? toDateController.text.trim() : '';
    final customerName = applyFilters ? customerNameController.text.trim() : '';
    final int fetchId = ++_currentFetchId;
    final base = getApiUrl();
    // نحتاج على الأقل العناصر حتى نهاية الصفحة الحالية
    final int needed = currentPage * pageSize;
    final int perZoneLimit =
        needed.clamp(pageSize, 300); // سقف 300 لكل منطقة لتجنب الضغط
    Map<String, int> zoneTotals = {};
    List<dynamic> combined = [];
    try {
      // نجلب بالتوازي بدفعات صغيرة
      const batchSize = 5;
      for (int i = 0; i < currentZones.length; i += batchSize) {
        final batch = currentZones.skip(i).take(batchSize).toList();
        final futures = batch.map((zoneId) async {
          String url =
              '$base&pageNumber=1&pageSize=$perZoneLimit&zoneId=$zoneId';
          if (fromDate.isNotEmpty) url += '&fromExpirationDate=$fromDate';
          if (toDate.isNotEmpty) url += '&toExpirationDate=$toDate';
          if (customerName.isNotEmpty) url += '&customerName=$customerName';
          try {
            final resp = await http.get(Uri.parse(url), headers: {
              'Authorization': 'Bearer ${widget.authToken}',
              'Accept': 'application/json',
            }).timeout(const Duration(seconds: 20));
            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body);
              final items = (data['items'] ?? []) as List<dynamic>;
              final total = data['totalCount'] ?? items.length;
              return (zoneId: zoneId, total: total as int, items: items);
            }
          } catch (_) {}
          return (zoneId: zoneId, total: 0, items: <dynamic>[]);
        });
        final results = await Future.wait(futures);
        for (final r in results) {
          zoneTotals[r.zoneId] = r.total;
          combined.addAll(r.items);
        }
        if (!mounted) return;
        setState(() {
          multiZoneCounts = Map<String, int>.from(zoneTotals);
        });
        if (i + batchSize < currentZones.length) {
          await Future.delayed(const Duration(milliseconds: 120));
        }
      }
      // ترتيب حسب تاريخ الانتهاء asc كما في الاستعلام الأصلي
      combined.sort((a, b) {
        final ea = a['expires']?.toString();
        final eb = b['expires']?.toString();
        if (ea == null && eb == null) return 0;
        if (ea == null) return 1;
        if (eb == null) return -1;
        return ea.compareTo(eb);
      });
      final totalCombined = zoneTotals.values.fold<int>(0, (p, c) => p + c);
      final start = (currentPage - 1) * pageSize;
      final end = (start + pageSize).clamp(0, combined.length);
      final slice =
          start < combined.length ? combined.sublist(start, end) : <dynamic>[];
      if (!mounted) return;
      setState(() {
        totalSubscriptions = totalCombined;
        subscriptions = slice;
        isLoading = false;
        errorMessage = '';
        // تحديث حالة عدادات المناطق (لم تعد قيد التحميل هنا)
        multiZoneCountsLoading = false;
      });
      // تحميل سريع للأجهزة للنتيجة المجمّعة
      unawaited(_quickLoadDevicesFor(subscriptions, fetchId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'فشل جلب بيانات المناطق المتعددة: $e';
        isLoading = false;
      });
    }
  }

  /// جلب عدد الاشتراكات لكل منطقة عند تحديد أكثر من منطقة
  Future<void> fetchSelectedZonesCounts({
    String? fromDate,
    String? toDate,
    String? customerName,
  }) async {
    if (selectedZoneIds.length < 2) return; // ليس متعدد
    final currentRequestId = ++_zoneCountsRequestId;
    setState(() {
      multiZoneCountsLoading = true;
      multiZoneCounts = {};
    });
    try {
      final zonesList = selectedZoneIds.toList();
      // إعداد الفلاتر العامة المشتركة
      final baseUrl = getApiUrl();
      // سنعمل على دفعات صغيرة لتجنب ضغط الخادم
      const batchSize = 5;
      for (int i = 0; i < zonesList.length; i += batchSize) {
        if (!mounted) return; // خرجنا
        if (currentRequestId != _zoneCountsRequestId) {
          return; // تم إلغاء الطلب بمنطقياً
        }
        final batch = zonesList.skip(i).take(batchSize).toList();
        final futures = batch.map((zoneId) async {
          String url = '$baseUrl&pageNumber=1&pageSize=1&zoneId=$zoneId';
          if (fromDate != null && fromDate.isNotEmpty) {
            url += '&fromExpirationDate=$fromDate';
          }
          if (toDate != null && toDate.isNotEmpty) {
            url += '&toExpirationDate=$toDate';
          }
          if (customerName != null && customerName.isNotEmpty) {
            url += '&customerName=$customerName';
          }
          try {
            final resp = await http.get(Uri.parse(url), headers: {
              'Authorization': 'Bearer ${widget.authToken}',
              'Accept': 'application/json',
            }).timeout(const Duration(seconds: 12));
            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body);
              final count =
                  data['totalCount'] ?? (data['items'] as List?)?.length ?? 0;
              return MapEntry(zoneId, count as int);
            } else {
              return MapEntry(zoneId, 0);
            }
          } catch (_) {
            return MapEntry(zoneId, 0);
          }
        });
        final results = await Future.wait(futures);
        if (!mounted || currentRequestId != _zoneCountsRequestId) return;
        setState(() {
          for (final e in results) {
            multiZoneCounts[e.key] = e.value;
          }
        });
        if (i + batchSize < zonesList.length) {
          await Future.delayed(const Duration(milliseconds: 120));
        }
      }
    } finally {
      if (mounted && currentRequestId == _zoneCountsRequestId) {
        setState(() => multiZoneCountsLoading = false);
      }
    }
  }

  /// تحسين الاشتراكات (معلومات العميل + تفاصيل + جهاز) على دفعات
  Future<void> _enhanceSubscriptions(List<dynamic> list, int fetchId) async {
    if (!mounted) return;
    final int enhanceId = ++_enhanceRequestId;
    // 1. ملخص العملاء
    try {
      final customerIds = list
          .map((s) => s['customer']?['id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toSet()
          .toList();
      const customerBatch = 50;
      for (int i = 0; i < customerIds.length; i += customerBatch) {
        if (!mounted) return;
        if (fetchId != _currentFetchId || enhanceId != _enhanceRequestId) {
          return; // تم بدء جلب جديد
        }
        final batch = customerIds.skip(i).take(customerBatch).toList();
        try {
          final summary = await fetchCustomersSummary(batch)
              .timeout(const Duration(seconds: 20));
          final items = summary['items'] as List<dynamic>? ?? [];
          for (var s in list) {
            final cid = s['customer']?['id']?.toString();
            if (cid != null && batch.contains(cid)) {
              final cs = items.firstWhere(
                (e) => e['id'].toString() == cid,
                orElse: () => null,
              );
              if (cs != null) s['customerSummary'] = cs;
            }
          }
          if (mounted) setState(() {}); // تحديث تدريجي
        } catch (e) {
          debugPrint('ملخص العملاء (دفعة) فشل: $e');
        }
      }
    } catch (e) {
      debugPrint('خطأ ملخص العملاء: $e');
    }

    // 2. تفاصيل الاشتراكات + الأجهزة مع حد توازي
    final subIds = list
        .map((s) => s['self']?['id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toList();
    const detailBatch = 8;
    for (int i = 0; i < subIds.length; i += detailBatch) {
      if (!mounted) return;
      if (fetchId != _currentFetchId || enhanceId != _enhanceRequestId) {
        return; // إلغاء مبكر
      }
      final batch = subIds.skip(i).take(detailBatch).toList();
      try {
        final detailsMap = await fetchMultipleSubscriptionsDetails(batch);
        final devicesMap = await fetchMultipleSubscriptionsDevices(batch);
        for (var s in list) {
          final sid = s['self']?['id']?.toString();
          if (sid != null) {
            final d = detailsMap[sid];
            if (d != null) {
              s['fullDetails'] = d;
              if (d['package'] != null) s['package'] = d['package'];
              if (d['service'] != null) s['service'] = d['service'];
              if (d['plan'] != null) s['plan'] = d['plan'];
            }
            final dm = devicesMap[sid];
            if (dm != null) s['deviceModel'] = dm;
          }
        }
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('دفعة تفاصيل/أجهزة فشلت: $e');
      }
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  /// تحميل سريع للأجهزة فقط (للحصول على FAT و Serial) دون انتظار كل التفاصيل
  Future<void> _quickLoadDevicesFor(List<dynamic> list, int fetchId) async {
    if (!mounted) return;
    // حدد الاشتراكات التي لا تملك deviceModel بعد
    final ids = list
        .where((s) => s['deviceModel'] == null)
        .map((s) => s['self']?['id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toList();
    if (ids.isEmpty) return;
    const batch = 12;
    for (int i = 0; i < ids.length; i += batch) {
      if (!mounted) return;
      if (fetchId != _currentFetchId) return; // تم بدء جلب جديد
      final slice = ids.skip(i).take(batch).toList();
      try {
        final devicesMap = await fetchMultipleSubscriptionsDevices(slice);
        for (var s in list) {
          final sid = s['self']?['id']?.toString();
          if (sid != null && devicesMap.containsKey(sid)) {
            s['deviceModel'] = devicesMap[sid];
          }
        }
        if (mounted && fetchId == _currentFetchId) setState(() {});
      } catch (e) {
        debugPrint('جلب سريع للأجهزة فشل: $e');
      }
      await Future.delayed(const Duration(milliseconds: 80));
    }
  }

  /// جلب أرقام الهواتف من التخزين المحلي ومطابقتها مع الاشتراكات
  Future<void> _loadPhonesFromLocalStorage() async {
    if (!mounted) return;
    if (_isLoadingLocalPhones) return; // منع التكرار

    setState(() {
      _isLoadingLocalPhones = true;
    });

    try {
      // تهيئة خدمة التخزين المحلي
      final localDb = LocalDatabaseService.instance;
      await localDb.initialize();

      // جلب جميع المشتركين من التخزين المحلي
      final subscribers = await localDb.searchSubscribers();

      // بناء خريطة الهواتف: subscription_id -> phone
      final Map<String, String> phonesMap = {};
      for (final sub in subscribers) {
        final subscriptionId = sub['subscription_id']?.toString() ?? '';
        final phone = sub['phone']?.toString() ?? '';
        if (subscriptionId.isNotEmpty && phone.isNotEmpty) {
          phonesMap[subscriptionId] = phone;
        }
      }

      if (!mounted) return;

      // تحديث الاشتراكات المعروضة بأرقام الهواتف
      int matchedCount = 0;
      for (var subscription in subscriptions) {
        final subscriptionId = subscription['self']?['id']?.toString() ?? '';
        if (subscriptionId.isNotEmpty &&
            phonesMap.containsKey(subscriptionId)) {
          // إضافة رقم الهاتف من التخزين المحلي
          subscription['localPhone'] = phonesMap[subscriptionId];
          matchedCount++;
        }
      }

      setState(() {
        _localPhonesMap = phonesMap;
        _localPhonesLoaded = true;
        _isLoadingLocalPhones = false;
      });

      // إظهار رسالة نجاح
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم جلب ${phonesMap.length} رقم هاتف، تم مطابقة $matchedCount اشتراك',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            backgroundColor: matchedCount > 0
                ? Colors.green.shade600
                : Colors.orange.shade600,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في جلب الأرقام من التخزين المحلي: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocalPhones = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب الأرقام: $e'),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// جلب أرقام الهواتف من التخزين المحلي للتصدير (بدون رسائل)
  Future<void> _loadPhonesFromLocalStorageForExport() async {
    try {
      final localDb = LocalDatabaseService.instance;
      await localDb.initialize();

      final subscribers = await localDb.searchSubscribers();

      final Map<String, String> phonesMap = {};
      for (final sub in subscribers) {
        final subscriptionId = sub['subscription_id']?.toString() ?? '';
        final phone = sub['phone']?.toString() ?? '';
        if (subscriptionId.isNotEmpty && phone.isNotEmpty) {
          phonesMap[subscriptionId] = phone;
        }
      }

      _localPhonesMap = phonesMap;
      _localPhonesLoaded = true;

      debugPrint('✅ تم جلب ${phonesMap.length} رقم هاتف من الذاكرة للتصدير');
    } catch (e) {
      debugPrint('خطأ في جلب الأرقام للتصدير: $e');
    }
  }

  // ============================================================
  // === دوال الإرسال الجماعي عبر واتساب ===
  // ============================================================

  /// عرض Dialog الإرسال الجماعي
  Future<void> _showBulkWhatsAppDialog() async {
    // التحقق من وجود إعدادات WhatsApp
    final webhookUrl = await WhatsAppBulkSenderService.getWebhookUrl();
    final phoneNumberId = await WhatsAppBusinessService.getPhoneNumberId();
    final accessToken = await WhatsAppBusinessService.getUserToken();

    if (webhookUrl == null || webhookUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى إعداد رابط n8n Webhook من الإعدادات أولاً'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (phoneNumberId == null || accessToken == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('يرجى إعداد WhatsApp Business API من الإعدادات أولاً'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // عرض Dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _BulkWhatsAppDialog(
          authToken: widget.authToken,
          phoneNumberId: phoneNumberId,
          accessToken: accessToken,
          getApiUrl: getApiUrl,
          selectedZoneIds: selectedZoneIds,
          selectedZoneId: selectedZoneId,
          fromDate: fromDateController.text.trim(),
          toDate: toDateController.text.trim(),
          customerName: customerNameController.text.trim(),
          localPhonesMap: _localPhonesMap,
          getFirstServiceName: _getFirstServiceName,
        ),
      );
    }
  }

  /// تصدير كل النتائج الحالية (مع الفلاتر) إلى ملف Excel محلي
  Future<void> exportToExcel() async {
    if (!mounted) return;
    setState(() {
      isExporting = true;
      errorMessage = '';
      progressMessage = 'جاري تحضير ملف Excel...';
      _cancelRequested = false;
      exportedItemsCount = 0;
      exportProgress = 0.0;
    });
    try {
      // إذا كان خيار جلب الأرقام مفعلاً، نجلب الأرقام من الذاكرة الداخلية أولاً
      if (_exportWithLocalPhones) {
        setState(() {
          progressMessage = 'جاري جلب أرقام الهواتف من الذاكرة الداخلية...';
        });
        await _loadPhonesFromLocalStorageForExport();
        if (_cancelRequested) throw const _CancelledExport();
      }

      // جلب جميع النتائج المصفاة
      setState(() {
        progressMessage = 'جاري جلب جميع النتائج...';
      });
      final allSubs = await fetchAllSubscriptionsForExport();
      if (_cancelRequested) throw const _CancelledExport();
      totalItemsToExport = allSubs.length;

      // تحميل التفاصيل والأجهزة (قبل إنشاء الصفوف) لضمان توفر FAT/Serial
      if (allSubs.isNotEmpty) {
        setState(() {
          progressMessage = 'جاري جلب تفاصيل الاشتراكات والأجهزة...';
        });
        await _loadDetailsAndDevicesForExport(allSubs,
            base: 0.05, span: 0.15); // حتى 0.20 من شريط التقدم
        if (_cancelRequested) throw const _CancelledExport();
      }

      // إنشاء ملف Excel
      final workbook = excel.Excel.createExcel();
      final String sheetName = 'Subscriptions';
      final sheet = workbook[sheetName];
      // رأس الأعمدة
      final headers = [
        'اسم المشترك',
        'رقم تعريف المشترك',
        'رقم الهاتف',
        'اسم المستخدم',
        'حالة الاشتراك',
        'حالة الجلسة',
        'نوع الباقة',
        'مدة الالتزام',
        'تاريخ البدء',
        'تاريخ الانتهاء',
        'متبقي',
        'المنطقة',
        'FAT',
        'ONT Serial',
        'رقم تعريف الاشتراك',
      ];
      for (var c = 0; c < headers.length; c++) {
        sheet
            .cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
            .value = excel.TextCellValue(headers[c]);
      }

      int processed = 0;
      for (final subscription in allSubs) {
        if (_cancelRequested) throw const _CancelledExport();
        final customer = subscription['customer'] ?? {};
        // أولاً نحاول جلب الهاتف من التخزين المحلي، ثم من السيرفر
        final subscriptionId = subscription['self']?['id']?.toString() ?? '';
        final localPhone = _localPhonesMap[subscriptionId] ?? '';
        final serverPhone = (subscription['customerSummary']?['primaryPhone'] ??
                customer['primaryContact']?['mobile'] ??
                customer['mobile'] ??
                customer['phone'] ??
                '')
            .toString();
        final phone = localPhone.isNotEmpty
            ? localPhone
            : (serverPhone.isNotEmpty ? serverPhone : 'غير متوفر');
        final username = (subscription['deviceDetails']?['username'] ??
                subscription['fullDetails']?['deviceDetails']?['username'] ??
                subscription['username'] ??
                'غير معروف')
            .toString();
        final start = subscription['startedAt']?.split('T')[0] ?? 'غير متوفر';
        final end = subscription['expires']?.split('T')[0] ?? 'غير متوفر';
        final remain = (() {
          final expiresStr = subscription['expires'];
          if (expiresStr is String && expiresStr.isNotEmpty) {
            try {
              final exp = DateTime.parse(expiresStr);
              final d = exp.difference(DateTime.now()).inDays;
              if (d < 0) return 'منتهي ${d.abs()} يوم';
              return '$d يوم';
            } catch (_) {}
          }
          return 'غير معروف';
        })();
        final bundle = _getFirstServiceName(subscription);
        final fatName = (() {
          final deviceModel = subscription['deviceModel'];
          if (deviceModel is Map<String, dynamic>) {
            final fat = deviceModel['fat'];
            if (fat is Map<String, dynamic>) {
              return fat['displayValue']?.toString() ?? '-';
            }
          }
          return '-';
        })();
        final ontSerial = (() {
          final deviceModel = subscription['deviceModel'];
          if (deviceModel is Map<String, dynamic>) {
            final v = deviceModel['ontSerial'];
            if (v != null && v.toString().isNotEmpty) return v.toString();
          }
          return '-';
        })();
        final row = [
          customer['displayValue'] ?? 'غير متوفر', // اسم المشترك
          customer['id'] ?? 'غير متوفر', // رقم تعريف المشترك
          phone, // رقم الهاتف
          username, // اسم المستخدم
          (subscription['status'] == 'Active')
              ? 'فعال'
              : (subscription['status'] == 'Expired')
                  ? 'منتهي'
                  : (subscription['status'] == 'Suspended')
                      ? 'معلق'
                      : (subscription['status'] ??
                          'غير متوفر'), // حالة الاشتراك
          subscription['hasActiveSession'] == true
              ? 'نشطة'
              : 'غير نشطة', // حالة الجلسة
          bundle, // نوع الباقة
          subscription['commitmentPeriod']?.toString() ??
              'غير متوفر', // مدة الالتزام
          start, // تاريخ البدء
          end, // تاريخ الانتهاء
          remain, // متبقي
          subscription['zone']?['self']?['displayValue'] ??
              subscription['zone']?['displayValue'] ??
              'غير معروف', // المنطقة
          fatName, // FAT
          ontSerial, // ONT Serial
          subscription['self']?['id'] ?? 'غير متوفر', // رقم تعريف الاشتراك
        ];
        final rowIndex = processed + 1; // +1 لأن الصف 0 للرأس
        for (var c = 0; c < row.length; c++) {
          sheet
              .cell(excel.CellIndex.indexByColumnRow(
                  columnIndex: c, rowIndex: rowIndex))
              .value = excel.TextCellValue(row[c].toString());
        }
        processed++;
        if (processed % 50 == 0 || processed == allSubs.length) {
          if (!mounted) return;
          setState(() {
            exportedItemsCount = processed;
            exportProgress = allSubs.isEmpty
                ? 1.0
                : (processed / allSubs.length).clamp(0, 1) * 0.9; // حتى 90%
            progressMessage = 'تمت معالجة $processed من ${allSubs.length}';
          });
        }
      }

      if (_cancelRequested) throw const _CancelledExport();

      // حفظ الملف
      final dir = await getApplicationDocumentsDirectory();
      final fileName =
          'اشتراكات_FTTH_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final filePath = '${dir.path}/$fileName';
      final bytes = workbook.encode();
      if (bytes != null) {
        final outFile = File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);
        if (!mounted) return;
        setState(() {
          exportProgress = 1.0;
          progressMessage = 'تم إنشاء الملف بنجاح';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تم تصدير ${allSubs.length} اشتراك إلى Excel'),
                Text('المسار: ${outFile.path}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            duration: const Duration(seconds: 6),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
    } on _CancelledExport catch (_) {
      _handleExportCancelled();
      return;
    } catch (e) {
      if (mounted) {
        setState(() => errorMessage = 'فشل التصدير إلى Excel: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التصدير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        // نؤخر إعادة التصفير قليلاً لإتاحة رؤية 100%
        await Future.delayed(const Duration(milliseconds: 400));
        if (!_cancelRequested) {
          setState(() {
            isExporting = false;
            progressMessage = '';
            exportProgress = 0.0;
            totalItemsToExport = 0;
            exportedItemsCount = 0;
          });
        }
      }
    }
  }

  /// جلب معلومات إضافية عن المشتركين (أرقام هواتف، نوع المشترك...)
  Future<Map<String, dynamic>> fetchCustomersSummary(
      List<String> customerIds) async {
    final url = Uri.parse(
      'https://admin.ftth.iq/api/customers/summary?${customerIds.map((id) => 'customerIds=$id').join('&')}',
    );
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception('فشل في جلب معلومات المشتركين: ${response.statusCode}');
    }
  }

  /// جلب جميع الاشتراكات مع التصفية المطبقة (لأغراض التصدير)
  Future<List<dynamic>> fetchAllSubscriptionsForExport() async {
    List<dynamic> allSubscriptions = [];
    int page = 1;
    const int batchSize = 100; // حجم كبير لتقليل عدد الطلبات

    try {
      // إذا تم اختيار أكثر من منطقة: نجلب كل منطقة كاملة على حدة ثم ندمج
      if (selectedZoneIds.length > 1) {
        final zonesList = selectedZoneIds.toList();
        final fromDate = fromDateController.text.trim();
        final toDate = toDateController.text.trim();
        final customerName = customerNameController.text.trim();
        int zoneIndex = 0;
        for (final zoneId in zonesList) {
          zoneIndex++;
          if (_cancelRequested) throw _CancelledExport();
          int zPage = 1;
          while (true) {
            if (_cancelRequested) throw _CancelledExport();
            String apiUrl =
                "${getApiUrl()}&pageNumber=$zPage&pageSize=$batchSize&zoneId=$zoneId";
            if (fromDate.isNotEmpty) apiUrl += '&fromExpirationDate=$fromDate';
            if (toDate.isNotEmpty) apiUrl += '&toExpirationDate=$toDate';
            if (customerName.isNotEmpty) {
              apiUrl += '&customerName=$customerName';
            }
            final resp = await http.get(
              Uri.parse(apiUrl),
              headers: {
                'Authorization': 'Bearer ${widget.authToken}',
                'Accept': 'application/json',
              },
            );
            if (resp.statusCode != 200) {
              // نسجل ونخرج من هذه المنطقة
              debugPrint(
                  'فشل جلب صفحة التصدير للمنطقة $zoneId: ${resp.statusCode}');
              break;
            }
            final data = jsonDecode(resp.body);
            final List<dynamic> pageSubscriptions = data['items'] ?? [];
            if (pageSubscriptions.isEmpty) break;
            allSubscriptions.addAll(pageSubscriptions);
            if (mounted) {
              setState(() {
                progressMessage =
                    'منطقة $zoneIndex/${zonesList.length} - تم جلب ${allSubscriptions.length}';
                // تقدير مبسط: 10% لجلب البيانات
                exportProgress = (allSubscriptions.length /
                            ((data['totalCount'] ?? pageSubscriptions.length) *
                                zonesList.length))
                        .clamp(0, 1) *
                    0.1;
              });
            }
            final totalCountZone = data['totalCount'] ?? 0;
            if (allSubscriptions.length >= totalCountZone &&
                pageSubscriptions.length < batchSize) {
              break;
            }
            zPage++;
            if (pageSubscriptions.length < batchSize) {
              break; // آخر صفحة لهذه المنطقة
            }
          }
        }
        // بعد جمع كل المناطق نجري دمج معلومات العملاء كما في المنطق الأصلي
        if (allSubscriptions.isEmpty) return allSubscriptions;
        final customerIds = allSubscriptions
            .map((sub) => sub['customer']?['id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList();
        const customerBatchSize = 50;
        for (int i = 0; i < customerIds.length; i += customerBatchSize) {
          if (_cancelRequested) throw _CancelledExport();
          final batch = customerIds.skip(i).take(customerBatchSize).toList();
          try {
            final customersSummary = await fetchCustomersSummary(batch);
            final summaryItems =
                customersSummary['items'] as List<dynamic>? ?? [];
            for (var subscription in allSubscriptions) {
              final customerId = subscription['customer']?['id']?.toString();
              if (customerId != null && batch.contains(customerId)) {
                final customerSummary = summaryItems.firstWhere(
                  (item) => item['id'].toString() == customerId,
                  orElse: () => null,
                );
                if (customerSummary != null) {
                  subscription['customerSummary'] = customerSummary;
                }
              }
            }
            if (mounted) {
              setState(() {
                // تقدم فرعي داخل مرحلة العملاء (حتى 5% من الإجمالي)
                exportProgress = 0.02 +
                    0.03 *
                        ((i + batch.length) / customerIds.length).clamp(0, 1);
              });
            }
          } catch (e) {
            debugPrint(
                'خطأ (مناطق متعددة) في جلب معلومات المشتركين (المجموعة $i): $e');
          }
        }
        return allSubscriptions;
      }
      while (true) {
        if (_cancelRequested) throw _CancelledExport();
        // بناء URL مع التصفية المطبقة
        String apiUrl = "${getApiUrl()}&pageNumber=$page&pageSize=$batchSize";

        // إضافة المرشحات إذا كانت مطبقة
        final fromDate = fromDateController.text.trim();
        final toDate = toDateController.text.trim();
        final customerName = customerNameController.text.trim();

        // نفس إصلاح التصفية الرئيسية للتصدير الكامل
        if (selectedZoneIds.isNotEmpty) {
          final zonesList = selectedZoneIds.toList();
          if (zonesList.length == 1) {
            apiUrl += '&zoneId=${zonesList.first}';
          } else {
            apiUrl += '&zoneIds=${zonesList.join(',')}';
          }
        } else if (selectedZoneId.isNotEmpty && selectedZoneId != 'all') {
          apiUrl += '&zoneId=$selectedZoneId';
        }
        if (fromDate.isNotEmpty) {
          apiUrl += '&fromExpirationDate=$fromDate';
        }
        if (toDate.isNotEmpty) {
          apiUrl += '&toExpirationDate=$toDate';
        }
        if (customerName.isNotEmpty) {
          apiUrl += '&customerName=$customerName';
        }

        final response = await http.get(
          Uri.parse(apiUrl),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> pageSubscriptions = data['items'] ?? [];

          if (pageSubscriptions.isEmpty) {
            break; // لا توجد المزيد من البيانات
          }

          allSubscriptions.addAll(pageSubscriptions); // تحديث رسالة التقدم
          if (mounted) {
            setState(() {
              exportProgress = 0.1 *
                  (allSubscriptions.length /
                      (data['totalCount'] ?? allSubscriptions.length));
              progressMessage =
                  "جاري جلب البيانات... تم جلب ${allSubscriptions.length} اشتراك";
            });
          }

          if (_cancelRequested) throw _CancelledExport();
          page++;

          // فحص إذا كانت هذه آخر صفحة
          final totalCount = data['totalCount'] ?? 0;
          if (allSubscriptions.length >= totalCount) {
            break;
          }
        } else {
          throw Exception('فشل في جلب البيانات: ${response.statusCode}');
        }
      }

      // جلب معلومات المشتركين الإضافية
      if (allSubscriptions.isNotEmpty) {
        final customerIds = allSubscriptions
            .map((sub) => sub['customer']?['id']?.toString())
            .where((id) => id != null && id.isNotEmpty)
            .cast<String>()
            .toList();

        if (customerIds.isNotEmpty) {
          // تقسيم customerIds إلى مجموعات لتجنب URL طويل جداً
          const customerBatchSize = 50;
          for (int i = 0; i < customerIds.length; i += customerBatchSize) {
            if (_cancelRequested) throw _CancelledExport();
            final batch = customerIds.skip(i).take(customerBatchSize).toList();
            try {
              final customersSummary = await fetchCustomersSummary(batch);
              final summaryItems =
                  customersSummary['items'] as List<dynamic>? ?? [];

              // دمج معلومات المشتركين مع الاشتراكات
              for (var subscription in allSubscriptions) {
                if (_cancelRequested) throw _CancelledExport();
                final customerId = subscription['customer']?['id']?.toString();
                if (customerId != null && batch.contains(customerId)) {
                  final customerSummary = summaryItems.firstWhere(
                    (item) => item['id'].toString() == customerId,
                    orElse: () => null,
                  );
                  if (customerSummary != null) {
                    subscription['customerSummary'] = customerSummary;
                  }
                }
              }
            } catch (e) {
              debugPrint('خطأ في جلب معلومات المشتركين (المجموعة $i): $e');
            }
            if (mounted) {
              setState(() {
                // تقدم فرعي داخل مرحلة العملاء (حتى 5% من الإجمالي)
                exportProgress = 0.02 +
                    0.03 *
                        ((i + batch.length) / customerIds.length).clamp(0, 1);
              });
            }
          }
        }
      }
    } catch (e) {
      if (e is _CancelledExport) rethrow;
      throw Exception('فشل في جلب جميع البيانات: $e');
    }
    return allSubscriptions;
  }

  /// تحميل تفاصيل الاشتراكات والأجهزة للتصدير (لا تؤثر على واجهة العرض الحالية)
  Future<void> _loadDetailsAndDevicesForExport(List<dynamic> subs,
      {double base = 0.05, double span = 0.15}) async {
    final ids = subs
        .map((s) => s['self']?['id']?.toString())
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toList();
    if (ids.isEmpty) return;
    const sliceSize = 20; // دفعة واحدة تجمع تفاصيل + أجهزة
    for (int i = 0; i < ids.length; i += sliceSize) {
      if (_cancelRequested) throw const _CancelledExport();
      final slice = ids.skip(i).take(sliceSize).toList();
      try {
        final detailsMap = await fetchMultipleSubscriptionsDetails(slice);
        if (_cancelRequested) throw const _CancelledExport();
        final devicesMap = await fetchMultipleSubscriptionsDevices(slice);
        for (final s in subs) {
          final sid = s['self']?['id']?.toString();
          if (sid != null) {
            final d = detailsMap[sid];
            if (d != null) {
              s['fullDetails'] = d;
              if (d['package'] != null) s['package'] = d['package'];
              if (d['service'] != null) s['service'] = d['service'];
              if (d['plan'] != null) s['plan'] = d['plan'];
            }
            final dm = devicesMap[sid];
            if (dm != null) s['deviceModel'] = dm;
          }
        }
      } catch (e) {
        debugPrint('فشل تحميل تفاصيل/أجهزة للتصدير: $e');
      }
      if (mounted) {
        setState(() {
          final progressBatch = ((i + slice.length) / ids.length).clamp(0, 1);
          exportProgress = base + span * progressBatch; // مثلاً حتى 0.20
        });
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // (تمت إزالة التعريفات المكررة لواجهات الجهاز)

  // ============================================================================
  // دوال التحكم في التصفية والتنقل
  // ============================================================================

  /// تغيير حجم الصفحة وإعادة تحميل البيانات
  void changePageSize(int size) {
    if (mounted) {
      setState(() {
        pageSize = size;
        currentPage = 1;
      });
      fetchSubscriptions();
    }
  }

  /// الانتقال للصفحة التالية
  void nextPage() {
    if ((currentPage * pageSize) < totalSubscriptions && mounted) {
      setState(() {
        currentPage++;
      });
      fetchSubscriptions();
    }
  }

  /// الانتقال للصفحة السابقة
  void previousPage() {
    if (currentPage > 1 && mounted) {
      setState(() {
        currentPage--;
      });
      fetchSubscriptions();
    }
  }

  /// إظهار/إخفاء قسم التصفية
  void toggleFilters() {
    if (mounted) {
      setState(() {
        isFiltering = !isFiltering;
      });
      // تحميل المناطق عند فتح التصفية لأول مرة فقط
      if (isFiltering && zones.isEmpty && !zonesLoading) {
        fetchZones();
      }
    }
  }

  /// إعادة تعيين جميع الفلاتر
  void resetFilters() {
    if (mounted) {
      setState(() {
        selectedZoneId = 'all';
        selectedZoneIds.clear();
        zoneSearchQuery = '';
        fromDateController.clear();
        toDateController.clear();
        customerNameController.clear();
        currentPage = 1;
        isFiltering = false;
      });
      fetchSubscriptions();
    }
  }

  /// دالة مساعدة لتحديد لون الحالة
  Color getStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'active' || lowerStatus == 'فعال') {
      return Colors.green;
    } else if (lowerStatus == 'expired' || lowerStatus == 'منتهي') {
      return Colors.red;
    } else if (lowerStatus == 'suspended' || lowerStatus == 'معلق') {
      return Colors.orange;
    } else {
      return Colors.grey;
    }
  }

  /// دالة مساعدة لتحديد أيقونة الحالة
  IconData getStatusIcon(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'active' || lowerStatus == 'فعال') {
      return Icons.check_circle;
    } else if (lowerStatus == 'expired' || lowerStatus == 'منتهي') {
      return Icons.error;
    } else if (lowerStatus == 'suspended' || lowerStatus == 'معلق') {
      return Icons.pause_circle;
    } else {
      return Icons.help;
    }
  }

  // ============================================================================
  // دوال بناء عناصر الواجهة
  // ============================================================================
  // طلب إلغاء التصدير
  void _requestCancelExport() {
    if (!mounted) return;
    setState(() {
      _cancelRequested = true;
      progressMessage = 'جاري إلغاء العملية...';
    });
  }

  // دالة الضغط على زر التصدير الرئيسي (قبل التحقق)
  Future<void> _onMainExportPressed() async {
    if (isExporting) return; // منع التكرار أثناء التصدير

    // إذا لم يكن الحقل ظاهر ولم تظهر الخيارات -> أظهر حقل كلمة المرور
    if (!askingPassword && !showExportOptions) {
      setState(() {
        askingPassword = true;
        _passwordError = null;
      });
      return;
    }

    // التحقق من كلمة المرور المدخلة
    final stored = await PermissionsService.getSecondSystemDefaultPassword();
    final expected =
        (stored == null || stored.trim().isEmpty) ? '0770' : stored.trim();
    final entered = _exportPasswordController.text.trim();

    if (entered != expected) {
      setState(() {
        _passwordError = 'كلمة مرور غير صحيحة';
      });
      return;
    }

    // نجاح التحقق
    setState(() {
      askingPassword = false;
      showExportOptions = true;
      _passwordError = null;
      _exportPasswordController.clear();
    });
  }

  // التعامل مع الإلغاء بشكل أنيق
  void _handleExportCancelled() {
    if (!mounted) return;
    setState(() {
      isExporting = false;
      exportProgress = 0.0;
      totalItemsToExport = 0;
      exportedItemsCount = 0;
      progressMessage = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إلغاء عملية التصدير'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // تحديد ألوان التدرج للـ AppBar
    final gradientColors = [Colors.blue.shade600, Colors.blue.shade800];

    // تحديد لون النص والأيقونات بطريقة ذكية
    final smartTextColor =
        SmartTextColor.getAppBarTextColorWithGradient(context, gradientColors);
    final smartIconColor = smartTextColor;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        bottom: (askingPassword || showExportOptions)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(70),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        gradientColors.first.withValues(alpha: .9),
                        gradientColors.last.withValues(alpha: .9)
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    border: Border(
                      top: BorderSide(
                          color: Colors.black.withValues(alpha: 0.05)),
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: askingPassword
                        ? Row(
                            key: const ValueKey('pw_row'),
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _exportPasswordController,
                                  obscureText: !_showPassword,
                                  decoration: InputDecoration(
                                    labelText: 'كلمة مرور التصدير',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_exportPasswordController
                                            .text.isNotEmpty)
                                          IconButton(
                                            icon: const Icon(Icons.clear),
                                            tooltip: 'مسح',
                                            onPressed: () {
                                              setState(() {
                                                _exportPasswordController
                                                    .clear();
                                              });
                                            },
                                          ),
                                        IconButton(
                                          icon: Icon(_showPassword
                                              ? Icons.visibility_off
                                              : Icons.visibility),
                                          tooltip:
                                              _showPassword ? 'إخفاء' : 'إظهار',
                                          onPressed: () => setState(() =>
                                              _showPassword = !_showPassword),
                                        ),
                                      ],
                                    ),
                                    errorText: _passwordError,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                  ),
                                  onSubmitted: (_) => _onMainExportPressed(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                onPressed: _onMainExportPressed,
                                icon: const Icon(Icons.lock_open),
                                label: const Text('تأكيد'),
                              ),
                            ],
                          )
                        : Row(
                            key: const ValueKey('opts_row'),
                            children: [
                              // خيار جلب الأرقام من الذاكرة
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _exportWithLocalPhones =
                                        !_exportWithLocalPhones;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _exportWithLocalPhones
                                        ? Colors.orange.shade600
                                        : Colors.grey.shade600,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _exportWithLocalPhones
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'جلب الأرقام',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                ),
                                onPressed: () {
                                  setState(() => showExportOptions = false);
                                  exportToExcel();
                                },
                                icon: const Icon(Icons.table_view),
                                label: const Text('Excel'),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'إغلاق',
                                onPressed: () => setState(() {
                                  showExportOptions = false;
                                  askingPassword = false;
                                  _passwordError = null;
                                  _exportPasswordController.clear();
                                }),
                                icon: const Icon(Icons.close,
                                    color: Colors.white),
                              )
                            ],
                          ),
                  ),
                ),
              )
            : null,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            'العدد: ${_formatNumber(totalSubscriptions)}',
            style: TextStyle(
              color: smartTextColor,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: smartIconColor, size: 26),
        centerTitle: true,
        elevation: 2,
        actions: [
          // زر جلب الأرقام من التخزين المحلي
          if (!isExporting && !_isLoadingLocalPhones)
            IconButton(
              icon: Icon(
                _localPhonesLoaded ? Icons.phone_enabled : Icons.phone_callback,
                color:
                    _localPhonesLoaded ? Colors.green.shade300 : smartIconColor,
                size: 24,
              ),
              onPressed: _loadPhonesFromLocalStorage,
              tooltip: _localPhonesLoaded
                  ? 'تم جلب الأرقام (اضغط للتحديث)'
                  : 'جلب الأرقام من التخزين المحلي',
            ),
          if (_isLoadingLocalPhones)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(smartIconColor),
                ),
              ),
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: smartIconColor, size: 26),
            onPressed: isLoading ? null : fetchSubscriptions,
            tooltip: 'إعادة تحميل البيانات',
          ),
          // زر الإرسال الجماعي
          if (!isExporting &&
              !_isBulkSending &&
              !askingPassword &&
              !showExportOptions &&
              PermissionManager.instance.canSend('subscriptions'))
            IconButton(
              tooltip: 'إرسال واتساب جماعي',
              onPressed: _showBulkWhatsAppDialog,
              icon: Icon(Icons.send, color: Colors.green.shade300, size: 24),
            ),
          if (_isBulkSending || _isLoadingAllSubscriptions)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.green.shade300),
                ),
              ),
            ),
          if (!isExporting &&
              !askingPassword &&
              !showExportOptions &&
              PermissionManager.instance.canExport('subscriptions'))
            IconButton(
              tooltip: 'تصدير',
              onPressed: _onMainExportPressed,
              icon: Icon(Icons.cloud_upload, color: smartIconColor, size: 26),
            ),
          if ((askingPassword || showExportOptions) && !isExporting)
            IconButton(
              tooltip: 'إخفاء',
              onPressed: () => setState(() {
                askingPassword = false;
                showExportOptions = false;
                _passwordError = null;
                _exportPasswordController.clear();
              }),
              icon:
                  Icon(Icons.close_fullscreen, color: smartIconColor, size: 24),
            ),
          if (isExporting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(smartIconColor),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // شريط التقدم
          if (isExporting)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.blue.shade50,
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.file_download, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          progressMessage.isNotEmpty
                              ? progressMessage
                              : 'جاري التصدير...',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '${(exportProgress * 100).toInt()}%',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: exportProgress,
                    backgroundColor: Colors.blue.shade100,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                  ),
                  if (totalItemsToExport > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '$exportedItemsCount من $totalItemsToExport',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _cancelRequested ? null : _requestCancelExport,
                        icon: const Icon(Icons.cancel, size: 18),
                        label: Text(
                            _cancelRequested ? 'جارٍ الإلغاء...' : 'إلغاء'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          // باقي المحتوى
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return isLoading && !isExporting
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري تحميل البيانات...'),
              ],
            ),
          )
        : errorMessage.isNotEmpty && !isExporting
            ? Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        "خطأ: $errorMessage",
                        style: const TextStyle(fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: fetchSubscriptions,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  _buildStatsHeader(),
                  _buildFilterSection(),
                  if (selectedZoneIds.length > 1) _buildMultiZoneCountsBar(),
                  Expanded(child: _buildSubscriptionsList()),
                  _buildPagination(),
                ],
              );
  }

  /// شريط يعرض عدد الاشتراكات لكل منطقة مختارة
  Widget _buildMultiZoneCountsBar() {
    if (selectedZoneIds.length < 2) return const SizedBox.shrink();
    final zoneNameById = {for (final z in zones) z['id']: z['displayValue']};
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade50,
        border: Border(
          top: BorderSide(color: Colors.blueGrey.shade100),
          bottom: BorderSide(color: Colors.blueGrey.shade100),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.area_chart, size: 18, color: Colors.blueGrey.shade700),
              const SizedBox(width: 6),
              Text(
                multiZoneCountsLoading
                    ? 'جاري حساب أعداد المناطق...'
                    : 'أعداد المناطق المختارة',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey.shade800,
                ),
              ),
              const Spacer(),
              if (multiZoneCountsLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: selectedZoneIds.map((id) {
              final name = zoneNameById[id] ?? id;
              final count = multiZoneCounts[id];
              final label = count == null
                  ? '$name: ...'
                  : '$name: ${_formatNumber(count)}';
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blueGrey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueGrey.shade100.withValues(alpha: .4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    final gradient = LinearGradient(
      colors: [Colors.blue.shade600, Colors.blue.shade800],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: gradient),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // تم نقل الإجمالي إلى شريط العنوان في الأعلى لتمييزه
                const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStatusSegmentedControl()),
              const SizedBox(width: 8),
              IconButton(
                onPressed: toggleFilters,
                icon: Icon(
                  isFiltering ? Icons.filter_list_off : Icons.filter_list,
                  color: Colors.blue.shade700,
                ),
                iconSize: 22,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: isFiltering ? 'إخفاء الفلاتر' : 'إظهار الفلاتر',
              ),
            ],
          ),
          if (isFiltering) _buildAdvancedFilters(),
        ],
      ),
    );
  }

  Widget _buildStatusSegmentedControl() {
    final options = [
      {'label': 'الكل', 'color': Colors.blue, 'icon': Icons.select_all},
      {'label': 'الفعال', 'color': Colors.green, 'icon': Icons.check_circle},
      {'label': 'المنتهي', 'color': Colors.red, 'icon': Icons.error_outline},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: options.map((opt) {
          final bool isSelected = selectedStatus == opt['label'];
          final Color base = opt['color'] as Color;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  if (!isSelected) {
                    setState(() {
                      selectedStatus = opt['label'] as String;
                      currentPage = 1;
                    });
                    fetchSubscriptions();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? base.withValues(alpha: 0.12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? base : Colors.grey.shade300,
                      width: isSelected ? 1.2 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        opt['icon'] as IconData,
                        size: 16,
                        color: isSelected ? base : base.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            opt['label'] as String,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: base,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // تنسيق الأرقام بشكل جميل (مثلاً 12,345) مع مراعاة العربية
  String _formatNumber(num value) {
    try {
      return NumberFormat.decimalPattern('ar').format(value);
    } catch (_) {
      return value.toString();
    }
  }

  Widget _buildAdvancedFilters() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تصفية متقدمة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 12),
          // زر اختيار المناطق (قائمة منسدلة داخل BottomSheet)
          _buildZonesSelectorButton(),
          const SizedBox(height: 12),
          // تواريخ انتهاء الاشتراك
          Row(
            children: [
              Expanded(
                child: _buildDateField(fromDateController, 'من تاريخ'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateField(toDateController, 'إلى تاريخ'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // اسم المشترك
          TextFormField(
            controller: customerNameController,
            decoration: const InputDecoration(
              labelText: 'اسم المشترك',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_search),
            ),
          ),
          const SizedBox(height: 16),
          // أزرار التحكم
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (isLoading || isExporting)
                      ? null
                      : () {
                          if (mounted) {
                            setState(() {
                              currentPage = 1;
                            });
                            fetchSubscriptions(applyFilters: true);
                          }
                        },
                  icon: const Icon(Icons.search),
                  label: const Text('تطبيق الفلاتر'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: resetFilters,
                  icon: const Icon(Icons.clear),
                  label: const Text('مسح الفلاتر'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateField(TextEditingController controller, String hint) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: hint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.calendar_today),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => controller.clear(),
              )
            : null,
      ),
      readOnly: true,
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (date != null) {
          controller.text = date.toIso8601String().split('T')[0];
        }
      },
    );
  }

  // زر فتح اختيار المناطق في BottomSheet (لتجنب ثِقل البناء الفوري)
  Widget _buildZonesSelectorButton() {
    final count =
        selectedZoneIds.isEmpty ? 'الكل' : '${selectedZoneIds.length} مختارة';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('المناطق',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: zonesLoading
                  ? null
                  : () async {
                      if (zones.isEmpty && !zonesLoading) await fetchZones();
                      if (!mounted) return;
                      if (zones.isEmpty) return; // فشل أو لا توجد
                      _openZonesBottomSheet();
                    },
              icon: const Icon(Icons.map),
              label: Text('اختيار المناطق: $count'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
            if (zonesLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            if (zoneErrorMessage.isNotEmpty)
              TextButton.icon(
                onPressed: fetchZones,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            if (selectedZoneIds.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  selectedZoneIds.clear();
                  selectedZoneId = 'all';
                }),
                icon: const Icon(Icons.clear),
                label: const Text('مسح'),
              ),
          ],
        ),
      ],
    );
  }

  void _openZonesBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // نسخة عمل مؤقتة (حتى يتم الحفظ)
        final tempSelected = Set<String>.from(selectedZoneIds);
        String localSearch = '';
        // تجنب إنشاء نسخة كاملة جديدة كبيرة: استخدام cast فقط (O(1))
        final List<Map<String, dynamic>> allZones =
            zones.cast<Map<String, dynamic>>();
        debugPrint(
            '[ZonesSheet] فتح النافذة - عدد المناطق: ${allZones.length}');
        final bool isHuge = allZones.length > 4000; // عتبة الحجم الكبير
        const int maxDisplay = 800; // حد أقصى للعرض في الواجهة
        List<Map<String, dynamic>> filtered = const [];
        // ScrollController مخصص لضمان ربط Scrollbar بقائمة لديها عملاء وتجنب الخطأ:
        // 'ScrollController not attached to any scroll views'
        final ScrollController zonesScrollController = ScrollController();

        // دالة فلترة محسّنة بدون إنشاء نسخ ضخمة متكررة
        List<Map<String, dynamic>> runFilter(String q) {
          final query = q.toLowerCase();
          // عند عدم وجود بحث وقائمة ضخمة لا نعرض شيئاً لتجنب التجمّد
          if (query.isEmpty && isHuge) return const [];
          if (query.isEmpty) {
            return allZones.length > maxDisplay
                ? allZones.take(maxDisplay).toList()
                : allZones;
          }
          final List<Map<String, dynamic>> out = [];
          for (final z in allZones) {
            final name = (z['displayValue'] ?? '').toString().toLowerCase();
            if (name.contains(query)) {
              out.add(z);
              if (out.length >= maxDisplay) break; // إيقاف مبكر
            }
          }
          return out;
        }

        filtered = runFilter(localSearch);
        Timer? debounceTimer;
        return StatefulBuilder(
          builder: (context, setModalState) {
            void applySearch(String v) {
              debounceTimer?.cancel();
              debounceTimer = Timer(const Duration(milliseconds: 220), () {
                if (!Navigator.of(context).mounted) return;
                setModalState(() {
                  localSearch = v.trim();
                  filtered = runFilter(localSearch);
                });
              });
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.map, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text('اختيار المناطق',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.blue.shade800)),
                        const Spacer(),
                        Text('${tempSelected.length} مختارة',
                            style: TextStyle(color: Colors.grey.shade700)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'بحث',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: applySearch,
                    ),
                    if (isHuge && localSearch.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'عدد المناطق كبير (${allZones.length}). اكتب على الأقل حرفين لإظهار النتائج.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.orange.shade700),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('جميع المناطق'),
                            dense: true,
                            value: tempSelected.isEmpty,
                            onChanged: (v) {
                              setModalState(() {
                                tempSelected.clear();
                              });
                            },
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setModalState(() => tempSelected.clear()),
                          child: const Text('تفريغ'),
                        )
                      ],
                    ),
                    SizedBox(
                      height: 300,
                      child: Scrollbar(
                        controller: zonesScrollController,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: zonesScrollController,
                          primary: false,
                          itemCount: filtered.length,
                          itemBuilder: (c, i) {
                            final z = filtered[i];
                            final id = (z['id'] ?? '').toString();
                            if (id.isEmpty) return const SizedBox.shrink();
                            final label = (z['displayValue'] ?? id).toString();
                            final checked = tempSelected.contains(id);
                            return CheckboxListTile(
                              title: Text(label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              value: checked,
                              dense: true,
                              onChanged: (v) {
                                setModalState(() {
                                  if (v == true) {
                                    tempSelected.add(id);
                                  } else {
                                    tempSelected.remove(id);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
                      ),
                    ),
                    if (filtered.isNotEmpty && filtered.length >= maxDisplay)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'عرض أول $maxDisplay فقط (اكتب مزيد من الأحرف لتصفية أكثر).',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('إغلاق'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                selectedZoneIds
                                  ..clear()
                                  ..addAll(tempSelected);
                                selectedZoneId =
                                    selectedZoneIds.isEmpty ? 'all' : '';
                                zoneSearchQuery =
                                    localSearch; // تحديث البحث الأساسي
                              });
                              Navigator.pop(context);
                              // بعد حفظ اختيار متعدد، نجلب البيانات مباشرة بالتصفية
                              if (selectedZoneIds.length > 1) {
                                currentPage = 1;
                                fetchSubscriptions(applyFilters: true);
                              } else if (selectedZoneIds.length == 1) {
                                currentPage = 1;
                                fetchSubscriptions(applyFilters: true);
                              }
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('حفظ'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // تمت إزالة واجهة الاختيار المدمجة للمناطق بعد استبدالها بنافذة BottomSheet أخف.

  /// دوال مساعدة للباقة قبل استخدامها في بناء البطاقات
  String _getFirstServiceName(Map<String, dynamic> subscription) {
    final services = subscription['services'];
    if (services != null && services is List && services.isNotEmpty) {
      final firstService = services[0];
      if (firstService is Map<String, dynamic>) {
        final serviceName = firstService['displayValue']?.toString() ??
            firstService['id']?.toString() ??
            '';
        if (serviceName.isNotEmpty && _isDescriptiveServiceName(serviceName)) {
          return serviceName;
        }
        if (serviceName.isNotEmpty) return serviceName;
      }
    }
    final bundleDisplayValue =
        subscription['bundle']?['displayValue']?.toString() ?? '';
    if (bundleDisplayValue.isNotEmpty &&
        _isDescriptiveBundleName(bundleDisplayValue)) {
      return bundleDisplayValue;
    }
    if (bundleDisplayValue.isNotEmpty) return bundleDisplayValue;
    final bundleId = subscription['bundleId']?.toString() ?? '';
    if (bundleId.isNotEmpty) return bundleId;
    return 'غير محدد';
  }

  bool _isDescriptiveServiceName(String serviceName) {
    final descriptiveKeywords = [
      'FIBER',
      'TV',
      'PHONE',
      'INTERNET',
      'IPTV',
      'PACKAGE',
      'ADSL'
    ];
    return descriptiveKeywords
        .any((k) => serviceName.toUpperCase().contains(k));
  }

  bool _isDescriptiveBundleName(String bundleName) {
    final descriptiveKeywords = [
      'PACKAGE',
      'PLAN',
      'BUNDLE',
      'FIBER',
      'BASIC',
      'PREMIUM',
      'STANDARD'
    ];
    return descriptiveKeywords.any((k) => bundleName.toUpperCase().contains(k));
  }

  /// قائمة الاشتراكات
  Widget _buildSubscriptionsList() {
    if (subscriptions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد اشتراكات للعرض',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'جرب تغيير المرشحات أو إعادة تحميل البيانات',
              style: TextStyle(
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: subscriptions.length,
      itemBuilder: (context, index) {
        final subscription = subscriptions[index];
        final customer = subscription['customer'] ?? {};
        final status = subscription['status'] ?? 'غير معروف';
        final bgColor = status == 'Active'
            ? Colors.green.shade50
            : status == 'Expired'
                ? Colors.red.shade50
                : Colors.white;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(
              color: getStatusColor(status).withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardHeader(customer, status),
                const SizedBox(height: 8),
                const Divider(height: 20, thickness: .7),
                _buildInfoGrid(subscription, customer),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardHeader(Map<String, dynamic> customer, String status) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: getStatusColor(status).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            getStatusIcon(status),
            color: getStatusColor(status),
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      customer['displayValue'] ?? 'غير متوفر',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      final name = customer['displayValue']?.toString() ?? '';
                      if (name.isEmpty) return;
                      Clipboard.setData(ClipboardData(text: name));
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تم نسخ الاسم'),
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      child: Icon(
                        Icons.copy,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                ],
              ),
              // تم إخفاء المعرف هنا لأنّه يظهر الآن في مربع مستقل ضمن التفاصيل
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: getStatusColor(status),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            status == 'Active'
                ? 'فعال'
                : status == 'Expired'
                    ? 'منتهي'
                    : status == 'Suspended'
                        ? 'معلق'
                        : status,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
      ],
    );
  }

  Widget _buildInfoGrid(
      Map<String, dynamic> subscription, Map<String, dynamic> customer) {
    final zoneName = (() {
      final zone = subscription['zone'];
      if (zone != null &&
          zone['self'] != null &&
          zone['self']['displayValue'] != null) {
        return zone['self']['displayValue'];
      } else if (zone != null && zone['displayValue'] != null) {
        return zone['displayValue'];
      }
      return 'غير معروف';
    })();

    // أولاً نحاول جلب الهاتف من التخزين المحلي، ثم من السيرفر
    final localPhone = subscription['localPhone']?.toString() ?? '';
    final serverPhone = (subscription['customerSummary']?['primaryPhone'] ??
            customer['primaryContact']?['mobile'] ??
            customer['mobile'] ??
            customer['phone'] ??
            '')
        .toString();
    final phone = localPhone.isNotEmpty
        ? localPhone
        : (serverPhone.isNotEmpty ? serverPhone : 'غير متوفر');

    final username = (subscription['deviceDetails']?['username'] ??
            subscription['fullDetails']?['deviceDetails']?['username'] ??
            subscription['username'] ??
            'غير معروف')
        .toString();

    final start = subscription['startedAt']?.split('T')[0] ?? 'غير متوفر';
    final end = subscription['expires']?.split('T')[0] ?? 'غير متوفر';
    final remain = (() {
      final expiresStr = subscription['expires'];
      if (expiresStr is String && expiresStr.isNotEmpty) {
        try {
          final exp = DateTime.parse(expiresStr);
          final d = exp.difference(DateTime.now()).inDays;
          if (d < 0) return 'منتهي ${d.abs()} يوم';
          return '$d يوم';
        } catch (_) {}
      }
      return 'غير معروف';
    })();
    final bundle = _getFirstServiceName(subscription);
    final commit = '${subscription['commitmentPeriod'] ?? '-'} شهر';
    final session =
        subscription['hasActiveSession'] == true ? 'نشطة' : 'غير نشطة';
    final customerId = customer['id']?.toString() ?? '-';
    // FAT من بيانات الجهاز (قد تأتي من deviceModel.fat.displayValue)
    final fatName = (() {
      final deviceModel = subscription['deviceModel'];
      if (deviceModel is Map<String, dynamic>) {
        final fat = deviceModel['fat'];
        if (fat is Map<String, dynamic>) {
          return fat['displayValue']?.toString() ?? '-';
        }
      }
      return '-';
    })();
    final ontSerial = (() {
      final deviceModel = subscription['deviceModel'];
      if (deviceModel is Map<String, dynamic>) {
        final v = deviceModel['ontSerial'];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      return '-';
    })();

    final items = <List<dynamic>>[
      ['الهاتف', phone, Icons.phone, Colors.blue.shade600],
      ['المعرف', customerId, Icons.badge, Colors.brown.shade600],
      ['المستخدم', username, Icons.person, Colors.teal.shade700],
      [
        'الجلسة',
        session,
        Icons.wifi,
        subscription['hasActiveSession'] == true
            ? Colors.green.shade700
            : Colors.red.shade600
      ],
      ['المنطقة', zoneName, Icons.location_on, Colors.orange.shade700],
      ['نوع الباقة', bundle, Icons.business_center, Colors.indigo.shade600],
      ['البدء', start, Icons.play_arrow, Colors.green.shade600],
      ['الانتهاء', end, Icons.stop_circle_outlined, Colors.red.shade600],
      ['متبقي', remain, Icons.timer, Colors.blue.shade600],
      ['مدة الالتزام', commit, Icons.schedule, Colors.purple.shade600],
      ['FAT', fatName, Icons.cable, Colors.deepOrange.shade700],
      [
        'ONT Serial',
        ontSerial,
        Icons.confirmation_number,
        Colors.blueGrey.shade700
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth > 420;
        final itemWidth =
            twoColumns ? (constraints.maxWidth / 2) - 10 : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items.map((r) => _buildInfoBox(r, itemWidth)).toList(),
        );
      },
    );
  }

  Widget _buildInfoBox(List<dynamic> data, double width) {
    final String label = data[0];
    final String value = (data[1] ?? '-').toString();
    final IconData icon = data[2] as IconData;
    final Color color = data[3] as Color;
    final bool isSession = label == 'الجلسة';
    final bool isSessionActive = isSession && value == 'نشطة';
    final bool isSessionInactive = isSession && value == 'غير نشطة';
    final bool canCopy =
        label == 'الهاتف' || label == 'المعرف' || label == 'المستخدم';
    final Color outerBg = isSessionActive
        ? Colors.green.shade600
        : isSessionInactive
            ? Colors.red.shade600
            : color.withValues(alpha: 0.04);
    final Color borderColor = isSessionActive
        ? Colors.green.shade700
        : isSessionInactive
            ? Colors.red.shade700
            : color.withValues(alpha: 0.35);
    final Color headerTextColor = (isSessionActive || isSessionInactive)
        ? Colors.white
        : color.withValues(alpha: .9);
    final Color iconColor =
        (isSessionActive || isSessionInactive) ? Colors.white : color;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: outerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: headerTextColor,
                  letterSpacing: .3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (!(isSessionActive || isSessionInactive))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: .25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (canCopy)
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: value));
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم النسخ: $value'),
                            duration: const Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: Icon(Icons.copy,
                            size: 16, color: color.withValues(alpha: .8)),
                      ),
                    )
                ],
              ),
            )
          else
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
  // تم الاستغناء عن _buildQuickMetaChips بعد إعادة تنظيم البطاقة

  // تمت إزالة الدوال القديمة _buildMetaChip و _buildInfoRow بعد اعتماد الجدول

  /// التنقل بين الصفحات
  Widget _buildPagination() {
    final totalPages = (totalSubscriptions / pageSize).ceil();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          // معلومات الصفحة الحالية
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'صفحة $currentPage من $totalPages',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'عرض ${((currentPage - 1) * pageSize) + 1} - ${(currentPage * pageSize).clamp(0, totalSubscriptions)} من $totalSubscriptions',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // اختيار حجم الصفحة
          DropdownButton<int>(
            value: pageSize,
            items: pageSizeOptions.map((size) {
              return DropdownMenuItem(
                value: size,
                child: Text('$size'),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                changePageSize(value);
              }
            },
          ),
          const SizedBox(width: 16),
          // أزرار التنقل
          Row(
            children: [
              IconButton(
                onPressed: currentPage > 1 ? previousPage : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'الصفحة السابقة',
              ),
              IconButton(
                onPressed: currentPage < totalPages ? nextPage : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'الصفحة التالية',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // تمت إعادة تعريف دوال الباقة بالأعلى
}

// ============================================================
// === Dialog الإرسال الجماعي عبر واتساب ===
// ============================================================

class _BulkWhatsAppDialog extends StatefulWidget {
  final String authToken;
  final String phoneNumberId;
  final String accessToken;
  final String Function() getApiUrl;
  final Set<String> selectedZoneIds;
  final String selectedZoneId;
  final String fromDate;
  final String toDate;
  final String customerName;
  final Map<String, String> localPhonesMap;
  final String Function(Map<String, dynamic>) getFirstServiceName;

  const _BulkWhatsAppDialog({
    required this.authToken,
    required this.phoneNumberId,
    required this.accessToken,
    required this.getApiUrl,
    required this.selectedZoneIds,
    required this.selectedZoneId,
    required this.fromDate,
    required this.toDate,
    required this.customerName,
    required this.localPhonesMap,
    required this.getFirstServiceName,
  });

  @override
  State<_BulkWhatsAppDialog> createState() => _BulkWhatsAppDialogState();
}

class _BulkWhatsAppDialogState extends State<_BulkWhatsAppDialog> {
  // حالة التحميل
  bool _isLoading = false;
  bool _isSending = false;
  String _loadingMessage = '';
  double _progress = 0.0;

  // البيانات
  List<Map<String, dynamic>> _allSubscriptions = [];
  List<Map<String, dynamic>> _selectedSubscriptions = [];
  final Set<String> _selectedIds = {};

  // القوالب المتاحة
  final List<Map<String, dynamic>> _templates = [
    {
      'id': 'sadara_reminder',
      'name': 'تذكير قبل الانتهاء',
      'description': 'تذكير المشتركين باقتراب انتهاء اشتراكهم',
      'icon': Icons.alarm,
      'color': Colors.orange,
    },
    {
      'id': 'sadara_renewed',
      'name': 'تم التجديد بنجاح',
      'description': 'إشعار المشتركين بنجاح تجديد اشتراكهم',
      'icon': Icons.check_circle,
      'color': Colors.green,
    },
    {
      'id': 'sadara_expired',
      'name': 'اشتراك منتهي + عروض',
      'description': 'إرسال عروض للمشتركين المنتهية اشتراكاتهم',
      'icon': Icons.local_offer,
      'color': Colors.red,
    },
  ];
  String _selectedTemplate = 'sadara_reminder';

  // نص العرض (لقالب sadara_expired)
  final TextEditingController _offerTextController = TextEditingController(
    text: 'لدينا عروض مميزة لك! خصم 20% على التجديد',
  );

  // فلترة
  String _filterStatus = 'الكل';
  String _searchQuery = '';
  bool _showOnlyWithPhone = false;
  bool _isLoadingLocalPhones = false;
  bool _localPhonesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAllSubscriptions();
  }

  @override
  void dispose() {
    _offerTextController.dispose();
    super.dispose();
  }

  /// جلب جميع الاشتراكات من كل الصفحات
  Future<void> _loadAllSubscriptions() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'جاري تحميل بيانات الاشتراكات...';
      _progress = 0.0;
    });

    try {
      List<Map<String, dynamic>> allSubs = [];
      int currentPage = 1;
      int totalPages = 1;
      const int pageSize = 100;

      do {
        String url =
            '${widget.getApiUrl()}&pageNumber=$currentPage&pageSize=$pageSize';

        // إضافة فلاتر
        if (widget.selectedZoneIds.isNotEmpty) {
          final zonesList = widget.selectedZoneIds.toList();
          if (zonesList.length == 1) {
            url += '&zoneId=${zonesList.first}';
          } else {
            url += '&zoneIds=${zonesList.join(',')}';
          }
        } else if (widget.selectedZoneId.isNotEmpty &&
            widget.selectedZoneId != 'all') {
          url += '&zoneId=${widget.selectedZoneId}';
        }
        if (widget.fromDate.isNotEmpty) {
          url += '&fromExpirationDate=${widget.fromDate}';
        }
        if (widget.toDate.isNotEmpty) {
          url += '&toExpirationDate=${widget.toDate}';
        }
        if (widget.customerName.isNotEmpty) {
          url += '&customerName=${widget.customerName}';
        }

        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer ${widget.authToken}',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = (data['items'] ?? []) as List<dynamic>;
          final totalCount = data['totalCount'] ?? items.length;
          totalPages = (totalCount / pageSize).ceil();

          for (final item in items) {
            if (item is Map<String, dynamic>) {
              allSubs.add(item);
            }
          }

          setState(() {
            _progress = currentPage / totalPages;
            _loadingMessage =
                'جاري تحميل الصفحة $currentPage من $totalPages...';
          });

          currentPage++;
        } else {
          throw Exception('فشل في جلب البيانات: ${response.statusCode}');
        }

        // تأخير بسيط لتجنب الضغط على السيرفر
        if (currentPage <= totalPages) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } while (currentPage <= totalPages);

      // جلب أرقام الهواتف من التخزين المحلي
      setState(() {
        _loadingMessage = 'جاري جلب أرقام الهواتف...';
      });

      await _loadLocalPhones(allSubs);

      setState(() {
        _allSubscriptions = allSubs;
        _isLoading = false;
        _loadingMessage = '';
      });
    } catch (e) {
      debugPrint('خطأ في تحميل الاشتراكات: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// جلب أرقام الهواتف من التخزين المحلي
  Future<void> _loadLocalPhones(List<Map<String, dynamic>> subs) async {
    try {
      final localDb = LocalDatabaseService.instance;
      await localDb.initialize();
      final subscribers = await localDb.searchSubscribers();

      debugPrint(
          '📱 _loadLocalPhones: جلب ${subscribers.length} مشترك من الذاكرة');

      // إنشاء خريطة بـ customer_id
      final Map<String, String> phonesByCustomerId = {};
      for (final sub in subscribers) {
        final customerId = sub['customer_id']?.toString() ?? '';
        final phone = sub['phone']?.toString() ?? '';
        if (customerId.isNotEmpty && phone.isNotEmpty) {
          phonesByCustomerId[customerId] = phone;
        }
      }

      debugPrint(
          '📱 _loadLocalPhones: استخراج ${phonesByCustomerId.length} رقم');
      if (phonesByCustomerId.isNotEmpty) {
        debugPrint(
            '📱 أول 3 أرقام: ${phonesByCustomerId.entries.take(3).map((e) => '${e.key}=${e.value}').join(', ')}');
      }

      int matchedCount = 0;
      // دمج الأرقام مع الاشتراكات
      for (final sub in subs) {
        final customerSummary =
            sub['customerSummary'] as Map<String, dynamic>? ?? {};
        final customer = sub['customer'] as Map<String, dynamic>? ?? {};

        // الحصول على customerId
        final customerId = customerSummary['customerId']?.toString() ??
            customer['id']?.toString() ??
            '';

        // أولوية: التخزين المحلي ثم السيرفر
        String phone = '';

        // أولاً: من التخزين المحلي - البحث بـ customerId
        if (phonesByCustomerId.containsKey(customerId)) {
          phone = phonesByCustomerId[customerId]!;
          matchedCount++;
        }
        // ثانياً: من الخريطة الممررة
        else if (widget.localPhonesMap.containsKey(customerId)) {
          phone = widget.localPhonesMap[customerId]!;
        }
        // ثالثاً: من السيرفر
        else {
          phone = customerSummary['primaryPhone']?.toString() ??
              customer['primaryContact']?['mobile']?.toString() ??
              customer['mobile']?.toString() ??
              customer['phone']?.toString() ??
              '';
        }

        sub['_phone'] = phone;
        sub['_hasPhone'] = phone.isNotEmpty;
      }

      debugPrint(
          '✅ _loadLocalPhones: تم مطابقة $matchedCount اشتراك من ${subs.length}');
    } catch (e) {
      debugPrint('❌ خطأ في جلب الأرقام: $e');
    }
  }

  /// جلب أرقام الهواتف من الذاكرة الداخلية (زر مستقل)
  Future<void> _fetchPhonesFromLocalStorage() async {
    if (_isLoadingLocalPhones) return;

    setState(() {
      _isLoadingLocalPhones = true;
      _loadingMessage = 'جاري جلب أرقام الهواتف من الذاكرة الداخلية...';
    });

    try {
      final localDb = LocalDatabaseService.instance;
      await localDb.initialize();
      final subscribers = await localDb.searchSubscribers();

      debugPrint('🔍 تم جلب ${subscribers.length} مشترك من الذاكرة الداخلية');

      // إنشاء خريطة بـ customer_id
      final Map<String, String> phonesByCustomerId = {};
      for (final sub in subscribers) {
        final customerId = sub['customer_id']?.toString() ?? '';
        final phone = sub['phone']?.toString() ?? '';
        if (customerId.isNotEmpty && phone.isNotEmpty) {
          phonesByCustomerId[customerId] = phone;
        }
      }

      debugPrint(
          '📱 تم استخراج ${phonesByCustomerId.length} رقم هاتف (بـ customer_id)');

      // طباعة أمثلة للمقارنة
      if (phonesByCustomerId.isNotEmpty) {
        debugPrint(
            '🔑 أول 3 customer_id من الذاكرة: ${phonesByCustomerId.keys.take(3).toList()}');
      }
      if (_allSubscriptions.isNotEmpty) {
        debugPrint(
            '🔑 أول 3 من API: ${_allSubscriptions.take(3).map((s) => 'customerId=${s['customerSummary']?['customerId']}').toList()}');
      }

      int updatedCount = 0;
      int alreadyHadPhone = 0;

      // تحديث الأرقام في الاشتراكات - البحث بـ customerId
      for (final sub in _allSubscriptions) {
        // الحصول على customerId من customerSummary أو customer
        final customerSummary =
            sub['customerSummary'] as Map<String, dynamic>? ?? {};
        final customer = sub['customer'] as Map<String, dynamic>? ?? {};

        final customerId = customerSummary['customerId']?.toString() ??
            customer['id']?.toString() ??
            '';

        // البحث بـ customerId
        String? matchedPhone;
        if (phonesByCustomerId.containsKey(customerId)) {
          matchedPhone = phonesByCustomerId[customerId];
        }

        if (matchedPhone != null && matchedPhone.isNotEmpty) {
          final currentPhone = sub['_phone']?.toString() ?? '';
          final id = sub['id']?.toString() ?? '';

          // تحديث الرقم
          if (currentPhone.isEmpty ||
              currentPhone == 'غير متوفر' ||
              currentPhone == 'لا يوجد رقم') {
            sub['_phone'] = matchedPhone;
            sub['_hasPhone'] = true;
            updatedCount++;
            debugPrint(
                '✅ تحديث اشتراك $id (customerId=$customerId): $matchedPhone');
          } else {
            // الرقم موجود مسبقاً، نحدّثه إذا كان مختلفاً
            if (currentPhone != matchedPhone) {
              sub['_phone'] = matchedPhone;
              sub['_hasPhone'] = true;
              alreadyHadPhone++;
              debugPrint(
                  '🔄 تحديث رقم اشتراك $id: $currentPhone -> $matchedPhone');
            }
          }
        }
      }

      // تحديث قائمة المحددين بعد جلب الأرقام
      _updateSelectedSubscriptions();

      setState(() {
        _isLoadingLocalPhones = false;
        _localPhonesLoaded = true;
        _loadingMessage = '';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ تم جلب ${phonesByCustomerId.length} رقم من الذاكرة\n'
              'جديد: $updatedCount | محدّث: $alreadyHadPhone',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب الأرقام: $e');
      setState(() {
        _isLoadingLocalPhones = false;
        _loadingMessage = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل جلب الأرقام: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// فلترة الاشتراكات
  List<Map<String, dynamic>> get _filteredSubscriptions {
    return _allSubscriptions.where((sub) {
      // فلترة حسب الحالة
      if (_filterStatus != 'الكل') {
        final status = sub['status']?.toString() ?? '';
        if (_filterStatus == 'الفعال' && status != 'Active') return false;
        if (_filterStatus == 'المنتهي' && status != 'Expired') return false;
      }

      // فلترة حسب وجود رقم هاتف
      if (_showOnlyWithPhone && !(sub['_hasPhone'] == true)) return false;

      // فلترة حسب البحث
      if (_searchQuery.isNotEmpty) {
        final customer = sub['customer'] as Map<String, dynamic>? ?? {};
        final name = customer['displayValue']?.toString().toLowerCase() ?? '';
        final phone = sub['_phone']?.toString() ?? '';
        final id = sub['id']?.toString() ?? '';
        final query = _searchQuery.toLowerCase();

        if (!name.contains(query) &&
            !phone.contains(query) &&
            !id.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// تحديد/إلغاء تحديد الكل
  void _toggleSelectAll() {
    final filtered = _filteredSubscriptions;
    final allSelected =
        filtered.every((s) => _selectedIds.contains(s['id']?.toString()));

    setState(() {
      if (allSelected) {
        // إلغاء تحديد الكل
        for (final s in filtered) {
          _selectedIds.remove(s['id']?.toString());
        }
      } else {
        // تحديد الكل (فقط الذين لديهم أرقام)
        for (final s in filtered) {
          if (s['_hasPhone'] == true) {
            _selectedIds.add(s['id']?.toString() ?? '');
          }
        }
      }
      _updateSelectedSubscriptions();
    });
  }

  /// تحديث قائمة المحددين
  void _updateSelectedSubscriptions() {
    _selectedSubscriptions = _allSubscriptions
        .where((s) => _selectedIds.contains(s['id']?.toString()))
        .toList();
  }

  /// إرسال الرسائل
  Future<void> _sendMessages() async {
    // الحصول على الاشتراكات المحددة مباشرة
    final selectedSubs = _allSubscriptions
        .where((s) => _selectedIds.contains(_getUniqueId(s)))
        .toList();

    if (selectedSubs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد مشتركين للإرسال'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // فلترة من لديهم أرقام
    final subsWithPhone =
        selectedSubs.where((s) => _hasPhoneNumber(s)).toList();
    if (subsWithPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('المشتركون المحددون ليس لديهم أرقام هواتف'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // تأكيد الإرسال
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الإرسال'),
        content: Text('سيتم إرسال ${subsWithPhone.length} رسالة عبر واتساب.\n\n'
            'القالب: ${_templates.firstWhere((t) => t['id'] == _selectedTemplate)['name']}\n\n'
            'هل تريد المتابعة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('إرسال', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isSending = true;
      _loadingMessage = 'جاري إرسال الرسائل...';
      _progress = 0.0;
    });

    try {
      // تحضير بيانات المستلمين من المشتركين الذين لديهم أرقام
      final recipients = subsWithPhone.map((sub) {
        final customer = sub['customer'] as Map<String, dynamic>? ?? {};
        final phone = _getPhoneNumber(sub);
        return {
          'name': customer['displayValue']?.toString() ?? 'عزيزي المشترك',
          'phoneNumber': phone,
          'phone': phone,
          'expiryDate': sub['expires']?.toString().split('T')[0] ?? '',
          'expires': sub['expires']?.toString().split('T')[0] ?? '',
          'planName': widget.getFirstServiceName(sub),
          'plan': widget.getFirstServiceName(sub),
          'price': '',
        };
      }).toList();

      if (recipients.isEmpty) {
        throw Exception('لا يوجد مستلمين لديهم أرقام هواتف');
      }

      // إرسال عبر الخدمة
      final result = await WhatsAppBulkSenderService.sendTemplateMessages(
        templateType: _selectedTemplate,
        recipients: recipients,
        phoneNumberId: widget.phoneNumberId,
        accessToken: widget.accessToken,
        offerText: _selectedTemplate == 'sadara_expired'
            ? _offerTextController.text.trim()
            : null,
      );

      setState(() {
        _isSending = false;
        _loadingMessage = '';
      });

      if (mounted) {
        if (result['success'] == true) {
          final data = result['data'] as Map<String, dynamic>? ?? {};
          final isAsync = result['isAsync'] == true;

          if (isAsync) {
            // Fire-and-Forget - الإرسال يتم في الخلفية
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🚀 تم إرسال الطلب بنجاح!'),
                    Text(
                        'سيتم إرسال ${data['total'] ?? recipients.length} رسالة في الخلفية'),
                    const Text('يمكنك متابعة التقدم من صفحة التقارير',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'التقارير',
                  textColor: Colors.white,
                  onPressed: () {
                    // يمكن فتح صفحة التقارير هنا
                  },
                ),
              ),
            );
          } else {
            // الإرسال اكتمل (الطريقة التقليدية)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ تم الإرسال بنجاح!\n'
                    'المرسلة: ${data['totalSent'] ?? data['sent'] ?? recipients.length}\n'
                    'الفاشلة: ${data['totalFailed'] ?? data['failed'] ?? 0}'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '❌ فشل الإرسال: ${result['message'] ?? 'خطأ غير معروف'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('خطأ في الإرسال: $e');
      if (mounted) {
        setState(() {
          _isSending = false;
          _loadingMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الإرسال: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// بناء قسم معلومات
  Widget _buildInfoSection(String title, List<Widget> items) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.blue)),
          const SizedBox(height: 4),
          ...items,
        ],
      ),
    );
  }

  /// بناء عنصر معلومات
  Widget _buildInfoItem(String key, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text('$key:',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                color: highlight
                    ? (value == 'فارغ' ? Colors.red : Colors.green.shade700)
                    : (value == 'فارغ' || value == '-'
                        ? Colors.grey
                        : Colors.black87),
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// دالة مساعدة للتحقق من وجود رقم هاتف
  bool _hasPhoneNumber(Map<String, dynamic> sub) {
    // تحقق من _phone أولاً
    final phone = sub['_phone']?.toString() ?? '';
    if (phone.isNotEmpty) return true;

    // تحقق من customerSummary
    final customerSummary =
        sub['customerSummary'] as Map<String, dynamic>? ?? {};
    final serverPhone = customerSummary['primaryPhone']?.toString() ?? '';
    if (serverPhone.isNotEmpty) return true;

    // تحقق من customer
    final customer = sub['customer'] as Map<String, dynamic>? ?? {};
    final customerPhone = customer['primaryContact']?['mobile']?.toString() ??
        customer['mobile']?.toString() ??
        customer['phone']?.toString() ??
        '';
    if (customerPhone.isNotEmpty) return true;

    return false;
  }

  /// الحصول على رقم الهاتف من أي مصدر متاح
  String _getPhoneNumber(Map<String, dynamic> sub) {
    // أولاً: من _phone
    final phone = sub['_phone']?.toString() ?? '';
    if (phone.isNotEmpty) return phone;

    // ثانياً: من customerSummary
    final customerSummary =
        sub['customerSummary'] as Map<String, dynamic>? ?? {};
    final serverPhone = customerSummary['primaryPhone']?.toString() ?? '';
    if (serverPhone.isNotEmpty) return serverPhone;

    // ثالثاً: من customer
    final customer = sub['customer'] as Map<String, dynamic>? ?? {};
    final customerPhone = customer['primaryContact']?['mobile']?.toString() ??
        customer['mobile']?.toString() ??
        customer['phone']?.toString() ??
        '';
    if (customerPhone.isNotEmpty) return customerPhone;

    return '';
  }

  /// الحصول على معرف فريد للاشتراك
  String _getUniqueId(Map<String, dynamic> sub) {
    final id = sub['id']?.toString() ?? '';
    if (id.isNotEmpty) return id;

    final subscriptionId = sub['subscriptionId']?.toString() ?? '';
    if (subscriptionId.isNotEmpty) return subscriptionId;

    final customerSummary =
        sub['customerSummary'] as Map<String, dynamic>? ?? {};
    final customerId = customerSummary['customerId']?.toString() ?? '';
    if (customerId.isNotEmpty) return customerId;

    final customer = sub['customer'] as Map<String, dynamic>? ?? {};
    final customerIdFromCustomer = customer['id']?.toString() ?? '';
    if (customerIdFromCustomer.isNotEmpty) return customerIdFromCustomer;

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSubscriptions;
    final withPhone = filtered.where((s) => _hasPhoneNumber(s)).length;

    // حساب المحددين مباشرة من _allSubscriptions لضمان البيانات المحدثة
    final selectedSubs = _allSubscriptions
        .where((s) => _selectedIds.contains(_getUniqueId(s)))
        .toList();
    final selectedWithPhone =
        selectedSubs.where((s) => _hasPhoneNumber(s)).length;

    // Debug
    debugPrint(
        '🔍 BUILD: filtered=${filtered.length}, withPhone=$withPhone, selected=${_selectedIds.length}, selectedWithPhone=$selectedWithPhone');

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // العنوان
            Row(
              children: [
                Icon(Icons.send, color: Colors.green.shade700, size: 28),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'إرسال رسائل واتساب جماعية',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),

            // شريط التحميل
            if (_isLoading || _isSending) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(_loadingMessage),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null),
                  ],
                ),
              ),
            ] else ...[
              // إحصائيات
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('إجمالي', _allSubscriptions.length, Colors.blue),
                    _buildStat('معروض', filtered.length, Colors.purple),
                    _buildStat('لديهم أرقام', withPhone, Colors.green),
                    _buildStat(
                        'محدد للإرسال', selectedWithPhone, Colors.orange),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // فلاتر
              Row(
                children: [
                  // فلتر الحالة
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _filterStatus,
                      decoration: const InputDecoration(
                        labelText: 'الحالة',
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: ['الكل', 'الفعال', 'المنتهي'].map((s) {
                        return DropdownMenuItem(value: s, child: Text(s));
                      }).toList(),
                      onChanged: (v) =>
                          setState(() => _filterStatus = v ?? 'الكل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // بحث
                  Expanded(
                    flex: 2,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'بحث بالاسم أو الرقم',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // فلتر الأرقام
                  FilterChip(
                    label: const Text('لديهم أرقام فقط'),
                    selected: _showOnlyWithPhone,
                    onSelected: (v) => setState(() => _showOnlyWithPhone = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // أزرار التحديد وجلب الأرقام
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _toggleSelectAll,
                    icon: const Icon(Icons.select_all, size: 18),
                    label: Text(
                      _filteredSubscriptions.every(
                              (s) => _selectedIds.contains(s['id']?.toString()))
                          ? 'إلغاء تحديد الكل'
                          : 'تحديد الكل ($withPhone)',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade100,
                      foregroundColor: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_selectedIds.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        _selectedIds.clear();
                        _selectedSubscriptions.clear();
                      }),
                      icon: const Icon(Icons.clear_all, size: 18),
                      label: const Text('إلغاء التحديد'),
                    ),
                  const Spacer(),
                  // زر جلب الأرقام من الذاكرة الداخلية
                  ElevatedButton.icon(
                    onPressed: _isLoadingLocalPhones
                        ? null
                        : _fetchPhonesFromLocalStorage,
                    icon: _isLoadingLocalPhones
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _localPhonesLoaded
                                ? Icons.phone_enabled
                                : Icons.phone_callback,
                            size: 18,
                          ),
                    label: Text(
                        _localPhonesLoaded ? 'تحديث الأرقام' : 'جلب الأرقام'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _localPhonesLoaded
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                      foregroundColor: _localPhonesLoaded
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // قائمة المشتركين
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final sub = filtered[index];
                      final customer =
                          sub['customer'] as Map<String, dynamic>? ?? {};
                      final customerSummary =
                          sub['customerSummary'] as Map<String, dynamic>? ?? {};
                      final id = sub['id']?.toString() ?? '';
                      final subscriptionId =
                          sub['subscriptionId']?.toString() ?? '';
                      // استخدام معرف فريد - أول معرف موجود
                      final uniqueId = id.isNotEmpty
                          ? id
                          : (subscriptionId.isNotEmpty
                              ? subscriptionId
                              : (customerSummary['customerId']?.toString() ??
                                  customer['id']?.toString() ??
                                  ''));
                      final name =
                          customer['displayValue']?.toString() ?? 'غير معروف';
                      final phone = _getPhoneNumber(sub);
                      final hasPhone = phone.isNotEmpty;
                      final status = sub['status']?.toString() ?? '';
                      final expires =
                          sub['expires']?.toString().split('T')[0] ?? '';
                      final isSelected = _selectedIds.contains(uniqueId);

                      // أرقام من مصادر مختلفة
                      final serverPhone =
                          customerSummary['primaryPhone']?.toString() ?? '';
                      final customerPhone =
                          customer['primaryContact']?['mobile']?.toString() ??
                              customer['mobile']?.toString() ??
                              customer['phone']?.toString() ??
                              '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        child: ExpansionTile(
                          leading: Checkbox(
                            value: isSelected,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedIds.add(uniqueId);
                                } else {
                                  _selectedIds.remove(uniqueId);
                                }
                                _updateSelectedSubscriptions();
                              });
                            },
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: hasPhone ? null : Colors.grey,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: status == 'Active'
                                      ? Colors.green.shade100
                                      : Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  status == 'Active' ? 'فعال' : 'منتهي',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: status == 'Active'
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Row(
                            children: [
                              Icon(
                                hasPhone ? Icons.phone : Icons.phone_disabled,
                                size: 14,
                                color: hasPhone ? Colors.green : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  hasPhone ? phone : 'لا يوجد رقم',
                                  style: TextStyle(
                                    color: hasPhone
                                        ? Colors.green.shade700
                                        : Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Icon(Icons.calendar_today,
                                  size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(expires,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600)),
                            ],
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.grey.shade50,
                              width: double.infinity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // المعرفات
                                  _buildInfoSection('المعرفات', [
                                    _buildInfoItem('id', id),
                                    _buildInfoItem(
                                        'subscriptionId', subscriptionId),
                                    _buildInfoItem(
                                        'customerId',
                                        customerSummary['customerId']
                                                ?.toString() ??
                                            customer['id']?.toString() ??
                                            '-'),
                                  ]),

                                  const SizedBox(height: 8),

                                  // أرقام الهواتف
                                  _buildInfoSection('أرقام الهواتف', [
                                    _buildInfoItem('_phone (مستخدم)',
                                        phone.isEmpty ? 'فارغ' : phone,
                                        highlight: true),
                                    _buildInfoItem(
                                        'customerSummary.primaryPhone',
                                        serverPhone.isEmpty
                                            ? 'فارغ'
                                            : serverPhone),
                                    _buildInfoItem(
                                        'customer.mobile/phone',
                                        customerPhone.isEmpty
                                            ? 'فارغ'
                                            : customerPhone),
                                  ]),

                                  const SizedBox(height: 8),

                                  // معلومات إضافية
                                  _buildInfoSection('معلومات إضافية', [
                                    _buildInfoItem('zoneName',
                                        sub['zoneName']?.toString() ?? '-'),
                                    _buildInfoItem('bundleId',
                                        sub['bundleId']?.toString() ?? '-'),
                                    _buildInfoItem('expires', expires),
                                    _buildInfoItem('status', status),
                                  ]),

                                  const SizedBox(height: 8),

                                  // زر نسخ المعلومات
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      final info = '''
=== معلومات الاشتراك ===
id: $id
subscriptionId: $subscriptionId
customerId: ${customerSummary['customerId'] ?? customer['id'] ?? '-'}
name: $name
status: $status
expires: $expires

=== أرقام الهواتف ===
_phone: ${sub['_phone'] ?? 'null'}
customerSummary.primaryPhone: $serverPhone
customer.mobile: ${customer['mobile'] ?? 'null'}
customer.phone: ${customer['phone'] ?? 'null'}

=== _hasPhoneNumber result ===
hasPhone: $hasPhone
phone (from _getPhoneNumber): $phone

=== customerSummary ===
${customerSummary.toString()}

=== customer ===
${customer.toString()}
''';
                                      Clipboard.setData(
                                          ClipboardData(text: info));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('✅ تم نسخ المعلومات'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy, size: 16),
                                    label: const Text('نسخ المعلومات'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // جميع المفاتيح
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text('جميع المفاتيح:',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11)),
                                        const SizedBox(height: 4),
                                        Text(
                                          sub.keys.join(' | '),
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.black54),
                                        ),
                                      ],
                                    ),
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
              ),
              const SizedBox(height: 12),

              // اختيار القالب
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'اختر القالب:',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedTemplate,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      isExpanded: true,
                      items: _templates.map((t) {
                        return DropdownMenuItem(
                          value: t['id'] as String,
                          child: Row(
                            children: [
                              Icon(t['icon'] as IconData,
                                  color: t['color'] as Color, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t['name'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(
                          () => _selectedTemplate = v ?? 'sadara_reminder'),
                    ),
                    // وصف القالب المحدد
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _templates.firstWhere((t) =>
                                t['id'] == _selectedTemplate)['description']
                            as String,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    // حقل نص العرض (لقالب العروض فقط)
                    if (_selectedTemplate == 'sadara_expired') ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _offerTextController,
                        decoration: const InputDecoration(
                          labelText: 'نص العرض',
                          hintText: 'أدخل نص العرض الذي سيظهر في الرسالة',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // تنبيه إذا كان هناك محددين بدون أرقام
              if (_selectedIds.isNotEmpty && selectedWithPhone == 0)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'المشتركون المحددون ليس لديهم أرقام هواتف!\n'
                          'اضغط على "جلب الأرقام" أولاً.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),

              // أزرار الإجراءات
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // زر التقارير
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const WhatsAppBatchReportsPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.analytics, size: 18),
                    label: const Text('التقارير'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: selectedWithPhone > 0 ? _sendMessages : null,
                    icon: const Icon(Icons.send, color: Colors.white),
                    label: Text(
                      'إرسال ($selectedWithPhone)',
                      style: const TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
