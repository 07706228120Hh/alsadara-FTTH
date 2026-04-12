/// اسم الصفحة: الاشتراكات
/// وصف الصفحة: صفحة إدارة الاشتراكات الفعالة
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../utils/smart_text_color.dart';
import 'package:intl/intl.dart';
import '../../permissions/permissions.dart';
import '../../services/local_database_service.dart';
import '../../services/whatsapp_bulk_sender_service.dart';
import '../../services/whatsapp_business_service.dart';
import '../../pages/whatsapp_batch_reports_page.dart';
import '../users/user_details_page.dart';
import '../../services/auth_service.dart';

// استثناء خاص لإلغاء عمليات التصدير
class _CancelledExport implements Exception {
  final String message;
  const _CancelledExport() : message = 'تم إلغاء عملية التصدير';
  @override
  String toString() => message;
}

class SubscriptionsPage extends StatefulWidget {
  final String authToken;
  final bool hasServerSavePermission;
  final bool hasWhatsAppPermission;
  final bool? isAdminFlag;
  final List<String>? importantFtthApiPermissions;
  final String? activatedBy;
  const SubscriptionsPage({
    super.key,
    required this.authToken,
    this.hasServerSavePermission = false,
    this.hasWhatsAppPermission = false,
    this.isAdminFlag,
    this.importantFtthApiPermissions,
    this.activatedBy,
  });

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

  // === متغير جلب البيانات الإضافية (هاتف، FAT، Serial) ===
  bool _extrasLoaded = false;
  bool _isLoadingExtras = false;

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
  String selectedSessionFilter = 'الكل'; // الكل / نشطة / غير نشطة
  // === الترتيب المحلي ===
  String _sortField = 'الانتهاء'; // الاسم / الانتهاء / الحالة / الباقة
  bool _sortAsc = true;
  final TextEditingController fromDateController = TextEditingController();
  final TextEditingController toDateController = TextEditingController();
  final TextEditingController customerNameController = TextEditingController();
  final TextEditingController customerPhoneController = TextEditingController();

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

  /// جلب البيانات الإضافية (هاتف، FAT، Serial) عند طلب المستخدم
  Future<void> _fetchExtras() async {
    if (_isLoadingExtras) return;
    setState(() {
      _isLoadingExtras = true;
      _extrasLoaded = true;
    });
    try {
      final fetchId = _currentFetchId;
      if (subscriptions.isNotEmpty) {
        await Future.wait([
          _quickLoadDevicesFor(subscriptions, fetchId),
          _enhanceSubscriptions(subscriptions, fetchId),
        ]);
      }
    } catch (e) {
      debugPrint('خطأ في جلب البيانات الإضافية');
    }
    if (mounted) setState(() => _isLoadingExtras = false);
  }

  @override
  void initState() {
    super.initState();
    // تحميل الاشتراكات والمناطق مبكراً (المناطق بدون عرضها لتجهيزها لاحقاً)
    // ⚡ تأجيل التحميل حتى بعد انتهاء transition animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      fetchSubscriptions();
      fetchZones();
    });
  }

  /// جلب تفاصيل الاشتراك الكاملة
  Future<Map<String, dynamic>?> fetchSubscriptionDetails(
      String subscriptionId) async {
    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/subscriptions/$subscriptionId',
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('خطأ تفاصيل الاشتراك $subscriptionId');
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
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/subscriptions/$subscriptionId/device',
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['model'] is Map<String, dynamic>) return decoded['model'];
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('خطأ جهاز الاشتراك $subscriptionId');
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
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/locations/zones',
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
          zoneErrorMessage = 'حدث خطأ أثناء جلب المناطق';
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
    final reg = RegExp(r'^(.*?)(\d+)(.*)?');
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
      // المناطق تُطبق دائماً إن كانت مختارة
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
      // الفلاتر الإضافية (تاريخ، اسم) تُطبق عند الطلب
      if (applyFilters) {
        final fromDate = fromDateController.text.trim();
        final toDate = toDateController.text.trim();
        final customerName = customerNameController.text.trim();
        if (fromDate.isNotEmpty) url += '&fromExpirationDate=$fromDate';
        if (toDate.isNotEmpty) url += '&toExpirationDate=$toDate';
        if (customerName.isNotEmpty) url += '&customerName=$customerName';
      }

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        url,
      ).timeout(requestTimeout, onTimeout: () {
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

      // جلب البيانات الإضافية فقط إذا طلبها المستخدم مسبقاً
      if (_extrasLoaded && rawSubscriptions.isNotEmpty) {
        unawaited(_quickLoadDevicesFor(rawSubscriptions, fetchId));
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
          errorMessage = 'حدث خطأ';
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
            final resp = await AuthService.instance.authenticatedRequest(
              'GET',
              url,
            ).timeout(const Duration(seconds: 20));
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
      // تحميل سريع للأجهزة فقط إذا طلبها المستخدم
      if (_extrasLoaded) {
        unawaited(_quickLoadDevicesFor(subscriptions, fetchId));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'فشل جلب بيانات المناطق المتعددة';
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
            final resp = await AuthService.instance.authenticatedRequest(
              'GET',
              url,
            ).timeout(const Duration(seconds: 12));
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
          debugPrint('ملخص العملاء (دفعة) فشل');
        }
      }
    } catch (e) {
      debugPrint('خطأ ملخص العملاء');
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
        debugPrint('دفعة تفاصيل/أجهزة فشلت');
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
        debugPrint('جلب سريع للأجهزة فشل');
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
      debugPrint('خطأ في جلب الأرقام من التخزين المحلي');
      if (mounted) {
        setState(() {
          _isLoadingLocalPhones = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب الأرقام'),
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
      debugPrint('خطأ في جلب الأرقام للتصدير');
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

    // فتح شاشة الإرسال الجماعي
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              title: const Text('إرسال واتساب جماعي'),
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            body: _BulkWhatsAppDialog(
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
          ),
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
        setState(() => errorMessage = 'فشل التصدير إلى Excel');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التصدير'),
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
    final urlStr =
      'https://admin.ftth.iq/api/customers/summary?${customerIds.map((id) => 'customerIds=$id').join('&')}';
    final response = await AuthService.instance.authenticatedRequest(
      'GET',
      urlStr,
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
            final resp = await AuthService.instance.authenticatedRequest(
              'GET',
              apiUrl,
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
                'خطأ (مناطق متعددة) في جلب معلومات المشتركين (المجموعة $i)');
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

        final response = await AuthService.instance.authenticatedRequest(
          'GET',
          apiUrl,
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
              debugPrint('خطأ في جلب معلومات المشتركين (المجموعة $i)');
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
      throw Exception('فشل في جلب جميع البيانات');
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
        debugPrint('فشل تحميل تفاصيل/أجهزة للتصدير');
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
        customerPhoneController.clear();
        currentPage = 1;
        isFiltering = false;
        selectedSessionFilter = 'الكل';
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
    final stored = await PermissionService.getSecondSystemDefaultPassword();
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
        toolbarHeight: 46,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight((askingPassword || showExportOptions) ? 100 : 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // شريط التصفية (الكل/الفعال/المنتهي + المناطق + فلتر)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: _buildStatusSegmentedControl()),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 30,
                      child: ElevatedButton.icon(
                        onPressed: zonesLoading
                            ? null
                            : () async {
                                if (zones.isEmpty && !zonesLoading) await fetchZones();
                                if (!mounted) return;
                                if (zones.isEmpty) return;
                                _openZonesBottomSheet();
                              },
                        icon: const Icon(Icons.map, size: 14),
                        label: const Text('المناطق', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedZoneIds.isNotEmpty ? Colors.blue.shade700 : Colors.white.withValues(alpha: 0.2),
                          foregroundColor: selectedZoneIds.isNotEmpty ? Colors.white : smartIconColor,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: toggleFilters,
                      icon: Icon(
                        isFiltering ? Icons.filter_list_off : Icons.filter_list,
                        color: smartIconColor,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: isFiltering ? 'إخفاء الفلاتر' : 'إظهار الفلاتر',
                    ),
                  ],
                ),
              ),
              // شريط التصدير (يظهر فقط عند الحاجة)
              if (askingPassword || showExportOptions)
                Container(
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
            ],
          ),
        ),
        title: LayoutBuilder(
          builder: (context, constraints) {
            final sw = MediaQuery.of(context).size.width;
            final isMobile = sw < 600;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'الاشتراكات',
                  style: TextStyle(
                    color: smartTextColor,
                    fontSize: isMobile ? 13 : 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(width: isMobile ? 6 : 10),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 6 : 12,
                    vertical: isMobile ? 3 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    isMobile
                        ? _formatNumber(totalSubscriptions)
                        : 'العدد: ${_formatNumber(totalSubscriptions)}',
                    style: TextStyle(
                      color: smartTextColor,
                      fontSize: isMobile ? 11 : 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            );
          },
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
          // القائمة الجانبية للأزرار الأخرى
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: smartIconColor, size: 24),
            tooltip: 'المزيد',
            onSelected: (value) {
              switch (value) {
                case 'extras':
                  _fetchExtras();
                  break;
                case 'refresh':
                  if (!isLoading) fetchSubscriptions();
                  break;
                case 'whatsapp':
                  _showBulkWhatsAppDialog();
                  break;
                case 'export':
                  _onMainExportPressed();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'extras',
                enabled: !_isLoadingExtras,
                child: ListTile(
                  leading: Icon(
                    _extrasLoaded ? Icons.cloud_done : Icons.cloud_download,
                    color: _extrasLoaded ? Colors.green : Colors.blueGrey,
                    size: 22,
                  ),
                  title: Text(
                    _extrasLoaded ? 'تحديث التفاصيل (FAT, Serial)' : 'جلب التفاصيل (FAT, Serial)',
                    style: const TextStyle(fontSize: 13),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                enabled: !isLoading,
                child: const ListTile(
                  leading: Icon(Icons.refresh, size: 22),
                  title: Text('إعادة تحميل البيانات', style: TextStyle(fontSize: 13)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (PermissionManager.instance.canSend('subscriptions'))
                PopupMenuItem(
                  value: 'whatsapp',
                  child: ListTile(
                    leading: Icon(Icons.send, color: Colors.green.shade600, size: 22),
                    title: const Text('إرسال واتساب جماعي', style: TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (PermissionManager.instance.canExport('subscriptions'))
                PopupMenuItem(
                  value: 'export',
                  child: ListTile(
                    leading: Icon(Icons.cloud_upload, color: Colors.blue.shade600, size: 22),
                    title: const Text('تصدير', style: TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
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
    if (!isFiltering) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _buildAdvancedFilters(),
    );
  }

  Widget _buildStatusSegmentedControl() {
    final options = [
      {'label': 'الكل', 'color': Colors.blue, 'icon': Icons.select_all},
      {'label': 'الفعال', 'color': Colors.green, 'icon': Icons.check_circle},
      {'label': 'المنتهي', 'color': Colors.red, 'icon': Icons.error_outline},
    ];

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: options.map((opt) {
          final bool isSelected = selectedStatus == opt['label'];
          final Color base = opt['color'] as Color;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
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
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? base : Colors.white.withValues(alpha: 0.5),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        opt['icon'] as IconData,
                        size: 14,
                        color: isSelected ? base : Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            opt['label'] as String,
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: isSelected ? base : Colors.white,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 12,
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

  void _triggerSearch() {
    if (isLoading || isExporting) return;
    if (!mounted) return;
    // إذا أُدخل رقم هاتف → نبحث عن اسم المشترك أولاً ثم نفلتر
    final phone = customerPhoneController.text.replaceAll(RegExp(r'[^0-9+]'), '').trim();
    if (phone.isNotEmpty && phone.length >= 7) {
      _searchByPhone(phone);
    } else {
      setState(() { currentPage = 1; isFiltering = false; });
      fetchSubscriptions(applyFilters: true);
    }
  }

  Future<void> _searchByPhone(String phone) async {
    setState(() { isLoading = true; });
    try {
      final r = await AuthService.instance.authenticatedRequest(
        'GET', 'https://api.ftth.iq/api/customers?pageSize=5&pageNumber=1&phone=${Uri.encodeQueryComponent(phone)}',
      );
      if (r.statusCode == 200 && mounted) {
        final data = jsonDecode(r.body);
        final items = (data['items'] as List?) ?? [];
        if (items.isNotEmpty) {
          final name = items[0]['self']?['displayValue']?.toString() ?? '';
          if (name.isNotEmpty) {
            customerNameController.text = name;
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() { currentPage = 1; isFiltering = false; });
      fetchSubscriptions(applyFilters: true);
    }
  }

  Widget _buildAdvancedFilters() {
    const double h = 40.0;
    const borderColor = Colors.black;
    const radius = BorderRadius.all(Radius.circular(8));
    const fieldBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Colors.black),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
    );
    const ts = TextStyle(fontSize: 13);
    final hintTs = TextStyle(fontSize: 12, color: Colors.grey.shade400);

    // === حقل إدخال موحد ===
    Widget field(TextEditingController ctrl, String hint, IconData icon,
        {int flex = 1, TextInputType? kb}) {
      return Expanded(
        flex: flex,
        child: SizedBox(
          height: h,
          child: TextFormField(
            controller: ctrl,
            style: ts,
            keyboardType: kb,
            onFieldSubmitted: (_) => _triggerSearch(),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: hintTs,
              filled: true,
              fillColor: Colors.white,
              border: fieldBorder,
              enabledBorder: fieldBorder,
              focusedBorder: focusBorder,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
              prefixIcon: Icon(icon, size: 18, color: Colors.grey.shade500),
              prefixIconConstraints: const BoxConstraints(minWidth: 36),
              isDense: true,
            ),
          ),
        ),
      );
    }

    // === زر جلسة متصل (SegmentedButton style) ===
    Widget sessionSegment() {
      final items = [
        {'label': 'الكل', 'color': Colors.blueGrey},
        {'label': 'نشطة', 'color': const Color(0xFF388E3C)},
        {'label': 'غير نشطة', 'color': const Color(0xFFC62828)},
      ];
      return Container(
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(items.length, (i) {
            final item = items[i];
            final label = item['label'] as String;
            final color = item['color'] as Color;
            final sel = selectedSessionFilter == label;
            return GestureDetector(
              onTap: () => setState(() => selectedSessionFilter = label),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? color : Colors.white,
                  border: i > 0
                      ? Border(
                          right: BorderSide(color: borderColor, width: 0.5))
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: sel ? Colors.white : Colors.grey.shade600,
                  ),
                ),
              ),
            );
          }),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final isMobileLayout = constraints.maxWidth < 520;
      return Column(
      children: [
        // ── الصف الأول: حقول البحث والتواريخ ──
        if (isMobileLayout) ...[
          // موبايل: صف للاسم+الهاتف، وصف للتواريخ
          Row(
            children: [
              field(customerNameController, 'اسم المشترك', Icons.person_search, flex: 3),
              const SizedBox(width: 8),
              field(customerPhoneController, 'رقم الهاتف', Icons.phone, flex: 2, kb: TextInputType.phone),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: h,
                  child: _buildMiniDateField(fromDateController, 'من تاريخ', fieldBorder, ts, hintTs, focusBorder: focusBorder, fillColor: Colors.white),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SizedBox(
                  height: h,
                  child: _buildMiniDateField(toDateController, 'إلى تاريخ', fieldBorder, ts, hintTs, focusBorder: focusBorder, fillColor: Colors.white),
                ),
              ),
            ],
          ),
        ] else
        Row(
          children: [
            field(customerNameController, 'اسم المشترك',
                Icons.person_search,
                flex: 3),
            const SizedBox(width: 8),
            field(customerPhoneController, 'رقم الهاتف', Icons.phone,
                flex: 2, kb: TextInputType.phone),
            const SizedBox(width: 8),
            SizedBox(
              width: 130,
              height: h,
              child: _buildMiniDateField(fromDateController, 'من تاريخ',
                  fieldBorder, ts, hintTs,
                  focusBorder: focusBorder, fillColor: Colors.white),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 130,
              height: h,
              child: _buildMiniDateField(toDateController, 'إلى تاريخ',
                  fieldBorder, ts, hintTs,
                  focusBorder: focusBorder, fillColor: Colors.white),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
        // ── الصف الثاني: الجلسة + ترتيب + بحث/مسح ──
        Row(
          children: [
            sessionSegment(),
            const SizedBox(width: 10),
            _buildSortButton(h),
            const Spacer(),
            // === بحث ===
            SizedBox(
              height: h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade500, Colors.blue.shade700],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ElevatedButton.icon(
                  onPressed:
                      (isLoading || isExporting) ? null : _triggerSearch,
                  icon: const Icon(Icons.search, size: 15),
                  label: const Text('بحث',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // === مسح ===
            GestureDetector(
              onTap: resetFilters,
              child: Container(
                height: h,
                width: h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child:
                    Icon(Icons.close, size: 16, color: Colors.red.shade400),
              ),
            ),
          ],
        ),
      ],
    );
    }); // LayoutBuilder
  }

  Widget _buildSortButton(double h) {
    final borderColor = Colors.grey.shade300;
    return SizedBox(
      height: h,
      child: PopupMenuButton<String>(
        tooltip: 'ترتيب',
        padding: EdgeInsets.zero,
        constraints: BoxConstraints(minWidth: h, minHeight: h),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: Colors.blue.shade600),
              const SizedBox(width: 4),
              Text(_sortField, style: TextStyle(fontSize: 12, color: Colors.blue.shade600, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        onSelected: (val) {
          setState(() {
            if (val == _sortField) {
              _sortAsc = !_sortAsc;
            } else {
              _sortField = val;
              _sortAsc = true;
            }
          });
        },
        itemBuilder: (_) => [
          _sortMenuItem('الاسم', Icons.person),
          _sortMenuItem('الانتهاء', Icons.event),
          _sortMenuItem('الحالة', Icons.toggle_on),
          _sortMenuItem('الباقة', Icons.inventory_2),
          _sortMenuItem('الجلسة', Icons.wifi),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortMenuItem(String label, IconData icon) {
    final active = _sortField == label;
    return PopupMenuItem<String>(
      value: label,
      height: 34,
      child: Row(
        children: [
          Icon(icon, size: 15, color: active ? Colors.blue : Colors.grey.shade600),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          if (active) ...[
            const Spacer(),
            Icon(_sortAsc ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: Colors.blue),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniDateField(TextEditingController controller, String hint,
      OutlineInputBorder border, TextStyle ts, TextStyle hintTs, {Color? fillColor, OutlineInputBorder? focusBorder}) {
    return TextFormField(
      controller: controller,
      style: ts,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: hintTs,
        filled: fillColor != null,
        fillColor: fillColor,
        border: border,
        enabledBorder: border,
        focusedBorder: focusBorder ?? border.copyWith(borderSide: const BorderSide(color: Colors.blue)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        suffixIcon: Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade400),
        suffixIconConstraints: const BoxConstraints(minWidth: 26),
        isDense: true,
      ),
      readOnly: true,
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null && mounted) {
          controller.text =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
    );
  }

  Widget _buildDateField(TextEditingController controller, String hint) {
    return SizedBox(
      height: 40,
      child: TextFormField(
        controller: controller,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: hint,
          labelStyle: const TextStyle(fontSize: 12),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          prefixIcon: const Icon(Icons.calendar_today, size: 18),
          isDense: true,
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
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
      ),
    );
  }

  // زر فتح اختيار المناطق في BottomSheet (لتجنب ثِقل البناء الفوري)
  Widget _buildZonesSelectorButton() {
    final count =
        selectedZoneIds.isEmpty ? 'الكل' : '${selectedZoneIds.length} مختارة';
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: zonesLoading
                  ? null
                  : () async {
                      if (zones.isEmpty && !zonesLoading) await fetchZones();
                      if (!mounted) return;
                      if (zones.isEmpty) return;
                      _openZonesBottomSheet();
                    },
              icon: const Icon(Icons.map, size: 16),
              label: Text('المناطق: $count', style: const TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
          ),
        ),
        if (zonesLoading) ...[
          const SizedBox(width: 6),
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        if (zoneErrorMessage.isNotEmpty) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: fetchZones,
            icon: const Icon(Icons.refresh, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            tooltip: 'إعادة المحاولة',
          ),
        ],
        if (selectedZoneIds.isNotEmpty) ...[
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => setState(() {
              selectedZoneIds.clear();
              selectedZoneId = 'all';
            }),
            icon: const Icon(Icons.clear, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            tooltip: 'مسح المناطق',
          ),
        ],
      ],
    );
  }

  void _openZonesBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        // نسخة عمل مؤقتة (حتى يتم الحفظ)
        final tempSelected = Set<String>.from(selectedZoneIds);
        Set<String>? undoBackup; // نسخة احتياطية للتراجع
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
                                if (tempSelected.isNotEmpty) {
                                  undoBackup = Set<String>.from(tempSelected);
                                }
                                tempSelected.clear();
                              });
                            },
                          ),
                        ),
                        if (undoBackup != null && undoBackup!.isNotEmpty && tempSelected.isEmpty)
                          TextButton.icon(
                            onPressed: () {
                              setModalState(() {
                                tempSelected.addAll(undoBackup!);
                                undoBackup = null;
                              });
                            },
                            icon: const Icon(Icons.undo, size: 16),
                            label: const Text('تراجع'),
                            style: TextButton.styleFrom(foregroundColor: Colors.orange),
                          ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempSelected.clear();
                              for (final z in filtered) {
                                final id = (z['id'] ?? '').toString();
                                if (id.isNotEmpty) tempSelected.add(id);
                              }
                            });
                          },
                          child: const Text('تحديد الكل'),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              if (tempSelected.isNotEmpty) {
                                undoBackup = Set<String>.from(tempSelected);
                              }
                              tempSelected.clear();
                            });
                          },
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
                              // بعد حفظ الاختيار، نجلب البيانات مباشرة (سواء اختار مناطق أو ألغاها)
                              currentPage = 1;
                              fetchSubscriptions(applyFilters: true);
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

  /// فتح شاشة تفاصيل المشترك
  Future<void> _openUserDetails(Map<String, dynamic> subscription, Map<String, dynamic> customer) async {
    final customerId = customer['id']?.toString() ?? '';
    if (customerId.isEmpty) return;
    final userName = customer['displayValue']?.toString() ?? 'مستخدم';
    final phone = subscription['localPhone']?.toString() ??
        subscription['customerSummary']?['primaryPhone']?.toString() ??
        customer['primaryContact']?['mobile']?.toString() ??
        'غير متوفر';

    // جلب activatedBy من widget أو current-user
    String activatedBy = widget.activatedBy ?? '';
    if (activatedBy.isEmpty) {
      try {
        final resp = await AuthService.instance.authenticatedRequest(
          'GET',
          'https://api.ftth.iq/api/current-user',
        );
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          activatedBy = data['model']?['self']?['displayValue']?.toString() ??
              data['model']?['username']?.toString() ?? '';
        }
      } catch (_) {}
    }
    if (activatedBy.isEmpty) activatedBy = 'المستخدم';

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailsPage(
          userId: customerId,
          userName: userName,
          userPhone: phone,
          authToken: widget.authToken,
          activatedBy: activatedBy,
          hasServerSavePermission: widget.hasServerSavePermission,
          hasWhatsAppPermission: widget.hasWhatsAppPermission,
          isAdminFlag: widget.isAdminFlag,
          importantFtthApiPermissions: widget.importantFtthApiPermissions,
          userRoleHeader: '0',
          clientAppHeader: '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
        ),
      ),
    );
  }

  /// قائمة الاشتراكات
  Widget _buildSubscriptionsList() {
    // تصفية حسب حالة الجلسة (محلياً)
    var filtered = selectedSessionFilter == 'الكل'
        ? List<Map<String, dynamic>>.from(subscriptions)
        : subscriptions.where((s) {
            final hasActive = s['hasActiveSession'] == true;
            return selectedSessionFilter == 'نشطة' ? hasActive : !hasActive;
          }).toList();

    // ترتيب محلي
    if (_sortField != 'الانتهاء' || !_sortAsc) {
      filtered.sort((a, b) {
        int cmp;
        switch (_sortField) {
          case 'الاسم':
            final na = a['customer']?['displayValue']?.toString() ?? '';
            final nb = b['customer']?['displayValue']?.toString() ?? '';
            cmp = na.compareTo(nb);
            break;
          case 'الحالة':
            final sa = a['status']?.toString() ?? '';
            final sb = b['status']?.toString() ?? '';
            cmp = sa.compareTo(sb);
            break;
          case 'الباقة':
            final pa = _getFirstServiceName(a);
            final pb = _getFirstServiceName(b);
            cmp = pa.compareTo(pb);
            break;
          case 'الجلسة':
            final ja = a['hasActiveSession'] == true ? 1 : 0;
            final jb = b['hasActiveSession'] == true ? 1 : 0;
            cmp = ja.compareTo(jb);
            break;
          default: // الانتهاء
            final ea = a['expires']?.toString() ?? '';
            final eb = b['expires']?.toString() ?? '';
            cmp = ea.compareTo(eb);
        }
        return _sortAsc ? cmp : -cmp;
      });
    }

    if (filtered.isEmpty) {
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final subscription = filtered[index];
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
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
            border: Border.all(
              color: Colors.black87,
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: _buildInfoGrid(subscription, customer),
          ),
        );
      },
    );
  }

  Widget _buildCardHeader(Map<String, dynamic> customer, String status) {
    return Row(
      children: [
        Icon(
          getStatusIcon(status),
          color: getStatusColor(status),
          size: 18,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            customer['displayValue'] ?? 'غير متوفر',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () {
            final name = customer['displayValue']?.toString() ?? '';
            if (name.isEmpty) return;
            Clipboard.setData(ClipboardData(text: name));
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('تم نسخ الاسم'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Icon(Icons.copy, size: 14, color: Colors.grey.shade500),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: getStatusColor(status),
            borderRadius: BorderRadius.circular(10),
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
              fontSize: 10,
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

    final status = subscription['status'] ?? 'غير معروف';
    final customerName = customer['displayValue'] ?? 'غير متوفر';

    final items = <List<dynamic>>[
      ['الاسم', customerName, Icons.person, Colors.blueGrey.shade800],
      [
        'الجلسة',
        session,
        Icons.wifi,
        subscription['hasActiveSession'] == true
            ? Colors.green.shade700
            : Colors.red.shade600
      ],
      ['الهاتف', phone, Icons.phone, Colors.blue.shade600],
      ['المنطقة', zoneName, Icons.location_on, Colors.orange.shade700],
      ['نوع الباقة', bundle, Icons.business_center, Colors.indigo.shade600],
      ['الانتهاء', end, Icons.stop_circle_outlined, Colors.red.shade600],
      ['متبقي', remain, Icons.timer, Colors.blue.shade600],
      ['مدة الالتزام', commit, Icons.schedule, Colors.purple.shade600],
      // FAT و ONT Serial يظهران فقط إذا جُلبت البيانات الإضافية وكانت متوفرة
      if (_extrasLoaded && fatName != '-')
        ['FAT', fatName, Icons.cable, Colors.deepOrange.shade700],
      if (_extrasLoaded && ontSerial != '-')
        [
          'ONT Serial',
          ontSerial,
          Icons.confirmation_number,
          Colors.blueGrey.shade700
        ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = MediaQuery.of(context).size.width;
        final int cols;
        if (screenW >= 900) {
          cols = 4;
        } else if (constraints.maxWidth > 420) {
          cols = 2;
        } else {
          cols = 2;
        }
        final itemWidth = (constraints.maxWidth / cols) - (6.0 * (cols - 1));
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: items.map((r) {
            final box = _buildInfoBox(r, itemWidth);
            if (r[0] == 'الاسم') {
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _openUserDetails(subscription, customer),
                  child: box,
                ),
              );
            }
            return box;
          }).toList(),
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
        label == 'الاسم' || label == 'الهاتف' || label == 'المعرف' || label == 'المستخدم';
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: outerBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: iconColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: headerTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          if (!(isSessionActive || isSessionInactive))
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
                      padding: const EdgeInsets.only(right: 2),
                      child: Icon(Icons.copy,
                          size: 13, color: color.withValues(alpha: .7)),
                    ),
                  )
              ],
            )
          else
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // أزرار التنقل
          IconButton(
            onPressed: currentPage > 1 ? previousPage : null,
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: 'الصفحة السابقة',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          IconButton(
            onPressed: currentPage < totalPages ? nextPage : null,
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: 'الصفحة التالية',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 8),
          // اختيار حجم الصفحة
          PopupMenuButton<int>(
            initialValue: pageSize,
            tooltip: 'عدد البطاقات في الصفحة',
            onSelected: changePageSize,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$pageSize', style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                  Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey.shade600),
                ],
              ),
            ),
            itemBuilder: (_) => pageSizeOptions.map((size) {
              return PopupMenuItem<int>(
                value: size,
                height: 36,
                child: Text('$size', style: TextStyle(
                  fontSize: 13,
                  fontWeight: size == pageSize ? FontWeight.bold : FontWeight.normal,
                )),
              );
            }).toList(),
          ),
          const SizedBox(width: 10),
          // معلومات الصفحة
          Text(
            'صفحة $currentPage من $totalPages',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          ),
          const SizedBox(width: 6),
          Text(
            'عرض ${((currentPage - 1) * pageSize) + 1} - ${(currentPage * pageSize).clamp(0, totalSubscriptions)} من $totalSubscriptions',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
      const int pageSize = 100;

      // تحديد المناطق المطلوبة
      final List<String> zonesList = widget.selectedZoneIds.toList();
      final bool hasMultipleZones = zonesList.length > 1;
      final String singleZone = zonesList.length == 1
          ? zonesList.first
          : (widget.selectedZoneId.isNotEmpty && widget.selectedZoneId != 'all')
              ? widget.selectedZoneId
              : '';

      if (hasMultipleZones) {
        // ─── جلب لكل منطقة على حدة (API لا يدعم zoneIds) ───
        int completedZones = 0;
        const int batchSize = 5;

        for (int i = 0; i < zonesList.length; i += batchSize) {
          if (!mounted) return;
          final batch = zonesList.skip(i).take(batchSize).toList();

          final futures = batch.map((zoneId) async {
            List<Map<String, dynamic>> zoneSubs = [];
            int page = 1;
            int totalPages = 1;
            do {
              String url =
                  '${widget.getApiUrl()}&pageNumber=$page&pageSize=$pageSize&zoneId=$zoneId';
              if (widget.fromDate.isNotEmpty) {
                url += '&fromExpirationDate=${widget.fromDate}';
              }
              if (widget.toDate.isNotEmpty) {
                url += '&toExpirationDate=${widget.toDate}';
              }
              if (widget.customerName.isNotEmpty) {
                url += '&customerName=${widget.customerName}';
              }
              try {
                final response =
                    await AuthService.instance.authenticatedRequest(
                  'GET',
                  url,
                ).timeout(const Duration(seconds: 30));
                if (response.statusCode == 200) {
                  final data = jsonDecode(response.body);
                  final items = (data['items'] ?? []) as List<dynamic>;
                  final totalCount = data['totalCount'] ?? items.length;
                  totalPages = (totalCount / pageSize).ceil();
                  for (final item in items) {
                    if (item is Map<String, dynamic>) {
                      zoneSubs.add(item);
                    }
                  }
                  page++;
                } else {
                  break;
                }
              } catch (_) {
                break;
              }
              if (page <= totalPages) {
                await Future.delayed(const Duration(milliseconds: 50));
              }
            } while (page <= totalPages);
            return zoneSubs;
          });

          final results = await Future.wait(futures);
          for (final zoneSubs in results) {
            allSubs.addAll(zoneSubs);
          }
          completedZones += batch.length;
          if (mounted) {
            setState(() {
              _progress = completedZones / zonesList.length;
              _loadingMessage =
                  'جاري تحميل المنطقة $completedZones من ${zonesList.length}...';
            });
          }
          if (i + batchSize < zonesList.length) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }

        // ترتيب حسب تاريخ الانتهاء
        allSubs.sort((a, b) {
          final ea = a['expires']?.toString() ?? '';
          final eb = b['expires']?.toString() ?? '';
          return ea.compareTo(eb);
        });
      } else {
        // ─── جلب عادي (منطقة واحدة أو بدون فلتر منطقة) ───
        int currentPage = 1;
        int totalPages = 1;

        do {
          String url =
              '${widget.getApiUrl()}&pageNumber=$currentPage&pageSize=$pageSize';

          if (singleZone.isNotEmpty) {
            url += '&zoneId=$singleZone';
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

          final response = await AuthService.instance.authenticatedRequest(
            'GET',
            url,
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

          if (currentPage <= totalPages) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        } while (currentPage <= totalPages);
      }

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
      debugPrint('❌ خطأ في جلب الأرقام');
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
      debugPrint('❌ خطأ في جلب الأرقام');
      setState(() {
        _isLoadingLocalPhones = false;
        _loadingMessage = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل جلب الأرقام'),
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
      if (_showOnlyWithPhone && !_hasPhoneNumber(sub)) return false;

      // فلترة حسب البحث
      if (_searchQuery.isNotEmpty) {
        final customer = sub['customer'] as Map<String, dynamic>? ?? {};
        final name = customer['displayValue']?.toString().toLowerCase() ?? '';
        final phone = _getPhoneNumber(sub).toLowerCase();
        final id = _getUniqueId(sub).toLowerCase();
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
        filtered.every((s) => _selectedIds.contains(_getUniqueId(s)));

    setState(() {
      if (allSelected) {
        // إلغاء تحديد الكل
        for (final s in filtered) {
          _selectedIds.remove(_getUniqueId(s));
        }
      } else {
        // تحديد الكل (الذين لديهم أرقام)
        for (final s in filtered) {
          final uid = _getUniqueId(s);
          if (uid.isNotEmpty && _hasPhoneNumber(s)) {
            _selectedIds.add(uid);
          }
        }
      }
      _updateSelectedSubscriptions();
    });
  }

  /// تحديث قائمة المحددين
  void _updateSelectedSubscriptions() {
    _selectedSubscriptions = _allSubscriptions
        .where((s) => _selectedIds.contains(_getUniqueId(s)))
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
            ? _offerTextController.text
                .trim()
                .replaceAll('\r\n', ' ')
                .replaceAll('\n', ' ')
                .replaceAll('\r', ' ')
                .replaceAll('\t', ' ')
                .replaceAll(RegExp(r' {4,}'), '   ')
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
      debugPrint('خطأ في الإرسال');
      if (mounted) {
        setState(() {
          _isSending = false;
          _loadingMessage = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الإرسال'),
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
    // أولاً: self.id (البنية الأساسية من API)
    final selfId = sub['self']?['id']?.toString() ?? '';
    if (selfId.isNotEmpty) return selfId;

    final id = sub['id']?.toString() ?? '';
    if (id.isNotEmpty) return id;

    final subscriptionId = sub['subscriptionId']?.toString() ?? '';
    if (subscriptionId.isNotEmpty) return subscriptionId;

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

    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

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
                              (s) => _selectedIds.contains(_getUniqueId(s)))
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
                      final uniqueId = _getUniqueId(sub);
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
                                    _buildInfoItem('uniqueId', uniqueId),
                                    _buildInfoItem(
                                        'self.id', sub['self']?['id']?.toString() ?? '-'),
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
uniqueId: $uniqueId
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
