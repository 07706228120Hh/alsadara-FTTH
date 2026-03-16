/// اسم الصفحة: المنتهية الصلاحية قريباً
/// وصف الصفحة: صفحة الاشتراكات المنتهية الصلاحية قريباً
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../widgets/notification_filter.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import '../../services/auth_service.dart';
import '../auth/auth_error_handler.dart';
import '../auth/login_page.dart';
import 'package:excel/excel.dart' as ExcelLib;
import 'package:path_provider/path_provider.dart';
import '../users/user_details_page.dart';
import 'package:intl/intl.dart';

class ExpiringSoonPage extends StatefulWidget {
  final String activatedBy;
  final bool hasServerSavePermission;
  final bool hasWhatsAppPermission;
  final bool? isAdminFlag; // علم إداري صريح
  final List<String>?
      importantFtthApiPermissions; // قائمة الصلاحيات المهمة من FTTH
  const ExpiringSoonPage(
      {super.key,
      required this.activatedBy,
      this.hasServerSavePermission = false,
      this.hasWhatsAppPermission = false,
      this.isAdminFlag,
      this.importantFtthApiPermissions});

  @override
  State<ExpiringSoonPage> createState() => _ExpiringSoonPageState();
}

class _ExpiringSoonPageState extends State<ExpiringSoonPage> {
  bool isLoading = true;
  List<dynamic> expiringSoonData = [];
  String errorMessage = '';
  bool showTrialSubscriptions = false; // متغير للتبديل بين نوعي الاشتراكات
  bool _showAdvancedFilters = false; // إظهار/إخفاء بطاقة التصفية المتقدمة

  // متغيرات التصدير
  bool isExporting = false;
  String exportMessage = '';

  // متغيرات التنقل بين الصفحات
  int currentPage = 1;
  int itemsPerPage = 50;
  int totalItems = 0;

  // cache لأرقام الهواتف لتجنب إعادة الجلب
  final Map<String, String> _phoneCache = {};

  // متغيرات التصفية المتقدمة
  List<Map<String, dynamic>> _zones = [];
  String? _selectedZoneId;
  String? _selectedPlanName;
  bool _isLoadingZones = false;
  final List<String> _planOptions = [
    'FIBER 35',
    'FIBER 50',
    'FIBER 75',
    'FIBER 100'
  ];

  // فلاتر التاريخ: today, tomorrow, custom, default (3 days), all (بدون قيد)
  String _dateFilterType = 'default';
  DateTime? _customStartDate; // تاريخ بداية مخصص
  DateTime? _customEndDate; // تاريخ نهاية مخصص

  // دالة لحساب from/to حسب الفلتر الحالي
  ({DateTime fromDate, DateTime toDate}) _computeDateRange() {
    final now = DateTime.now();
    DateTime fromDate = now;
    DateTime toDate;
    if (_dateFilterType == 'all') {
      // لن نستخدم هذا النطاق فعلياً لتمريره للـ API، فقط إرجاع الآن + سنة شكلية
      toDate = now.add(const Duration(days: 365));
    } else if (_dateFilterType == 'today') {
      toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    } else if (_dateFilterType == 'tomorrow') {
      final tm = now.add(const Duration(days: 1));
      toDate = DateTime(tm.year, tm.month, tm.day, 23, 59, 59);
    } else if (_dateFilterType == 'custom' &&
        _customStartDate != null &&
        _customEndDate != null) {
      // ضبط from/to إلى بداية يوم البداية ونهاية يوم النهاية
      final cs = _customStartDate!;
      final ce = _customEndDate!;
      // تأكد أن البداية <= النهاية، إن لم يكن بدّل
      DateTime start = cs.isBefore(ce) ? cs : ce;
      DateTime end = ce.isAfter(cs) ? ce : cs;
      fromDate = DateTime(start.year, start.month, start.day, 0, 0, 0);
      toDate = DateTime(end.year, end.month, end.day, 23, 59, 59);
    } else {
      // الافتراضي: اليوم + الغد + بعد الغد (3 أيام تقويمية فقط)
      final thirdDay = now.add(const Duration(days: 2));
      toDate =
          DateTime(thirdDay.year, thirdDay.month, thirdDay.day, 23, 59, 59);
    }
    return (fromDate: fromDate, toDate: toDate);
  }

  bool _hasActiveFilters() {
    final dateActive = _dateFilterType != 'all' && _dateFilterType != 'default';
    final defaultActive =
        _dateFilterType == 'default'; // تعتبر أيضاً فلتر زمني محدد
    return (_selectedZoneId != null && _selectedZoneId!.isNotEmpty) ||
        (_selectedPlanName != null && _selectedPlanName!.isNotEmpty) ||
        dateActive ||
        defaultActive ||
        (_customStartDate != null && _customEndDate != null);
  }

  @override
  void initState() {
    super.initState();
    _fetchZones();
    _fetchExpiringSoonData();
  }

  Future<void> _fetchExpiringSoonData() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      String apiUrl;

      if (showTrialSubscriptions) {
        // رابط الاشتراكات التجريبية
        apiUrl =
            'https://admin.ftth.iq/api/subscriptions/trial?pageSize=$itemsPerPage&pageNumber=$currentPage&sortCriteria.property=expires&sortCriteria.direction=asc&status=Active&hierarchyLevel=0';
      } else {
        final baseUrl =
            'https://admin.ftth.iq/api/subscriptions?pageSize=$itemsPerPage&pageNumber=$currentPage&sortCriteria.property=expires&sortCriteria.direction=asc&status=Active&hierarchyLevel=0';
        if (_dateFilterType == 'all') {
          apiUrl = baseUrl; // بدون نطاق
        } else {
          final range = _computeDateRange();
          final fromDate = range.fromDate.toIso8601String();
          final toDate = range.toDate.toIso8601String();
          apiUrl =
              '$baseUrl&fromExpirationDate=$fromDate&toExpirationDate=$toDate';
        }
      }

      // إضافة فلاتر التصفية المتقدمة
      if (_selectedZoneId != null && _selectedZoneId!.isNotEmpty) {
        apiUrl += '&zoneId=$_selectedZoneId';
      }

      if (_selectedPlanName != null && _selectedPlanName!.isNotEmpty) {
        apiUrl += '&bundleName=$_selectedPlanName';
      }

      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        apiUrl,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final subscriptions = data['items'] ?? [];
        totalItems = data['totalCount'] ?? 0; // الحصول على العدد الكلي للسجلات

        // جلب أرقام الهواتف لكل اشتراك بشكل متوازي
        List<dynamic> enhancedSubscriptions =
            await _fetchPhonesInParallel(subscriptions);

        if (!mounted) return;
        setState(() {
          expiringSoonData = enhancedSubscriptions;
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        // معالجة خطأ انتهاء صلاحية التوكن
        AuthErrorHandler.handle401Error(context);
        return;
      } else {
        if (!mounted) return;
        setState(() {
          errorMessage = 'تعذر جلب البيانات: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      // التحقق من أن الخطأ ليس متعلقاً بانتهاء الجلسة أو عدم وجود توكن صالح
      if (e.toString().contains('انتهت جلسة المستخدم') ||
          e.toString().contains('لا يوجد توكن صالح') ||
          e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        // إظهار رسالة للمستخدم
        if (mounted) {
          ftthShowSnackBar(
            context,
            SnackBar(
              content: Text(
                  'انتهت صلاحية جلسة المستخدم، جاري التوجيه إلى صفحة تسجيل الدخول...'),
              backgroundColor: Colors.red[600],
              duration: const Duration(seconds: 2),
            ),
          );

          // التوجيه المباشر إلى صفحة تسجيل الدخول
          Future.delayed(const Duration(milliseconds: 500), () {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const LoginPage(),
              ),
              (Route<dynamic> route) => false,
            );
          });
        }
        return;
      }

      if (mounted) {
        // عرض الخطأ كإشعار بسيط بدلاً من شاشة خطأ كاملة
        final shortMsg = 'حدث خطأ'.contains('TimeoutException')
            ? 'انتهت مهلة الاتصال — حاول مرة أخرى'
            : 'تعذر جلب البيانات';
        ftthShowSnackBar(
          context,
          SnackBar(
            content: Text(shortMsg),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'إعادة',
              textColor: Colors.white,
              onPressed: _fetchExpiringSoonData,
            ),
          ),
        );
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // دالة لجلب أرقام الهواتف بشكل متوازي
  Future<List<dynamic>> _fetchPhonesInParallel(
      List<dynamic> subscriptions) async {
    // تقسيم المهام إلى دفعات صغيرة لتجنب إرهاق الخادم
    const int batchSize =
        15; // زيادة عدد الطلبات المتوازية إلى 15 لتسريع العملية
    List<dynamic> enhancedSubscriptions = [];

    for (int i = 0; i < subscriptions.length; i += batchSize) {
      int end = (i + batchSize < subscriptions.length)
          ? i + batchSize
          : subscriptions.length;
      List<dynamic> batch = subscriptions.sublist(i, end);

      // إنشاء قائمة من Future للجلب المتوازي
      List<Future<Map<String, dynamic>>> futures = batch.map((subscription) {
        return _fetchSinglePhone(subscription);
      }).toList();

      // انتظار جميع العمليات في هذه الدفعة
      List<Map<String, dynamic>> batchResults = await Future.wait(futures);
      enhancedSubscriptions.addAll(batchResults);

      // توقف قصير بين الدفعات لتجنب إرهاق الخادم
      if (i + batchSize < subscriptions.length) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    return enhancedSubscriptions;
  }

  // دالة لجلب رقم هاتف واحد مع استخدام الـ cache
  Future<Map<String, dynamic>> _fetchSinglePhone(
      Map<String, dynamic> subscription) async {
    final customerId = subscription['customer']?['id']?.toString();
    String phone = 'غير متوفر';

    if (customerId != null && customerId.isNotEmpty) {
      // التحقق من الـ cache أولاً
      if (_phoneCache.containsKey(customerId)) {
        phone = _phoneCache[customerId]!;
      } else {
        try {
          final customerResponse = await AuthService.instance
              .authenticatedRequest(
                'GET',
                'https://admin.ftth.iq/api/customers/$customerId',
              )
              .timeout(const Duration(
                  seconds: 3)); // تقليل الـ timeout لتسريع العملية

          if (customerResponse.statusCode == 200) {
            final customerData = jsonDecode(customerResponse.body);
            phone = customerData['model']?['primaryContact']?['mobile'] ??
                'غير متوفر';

            // حفظ في الـ cache
            _phoneCache[customerId] = phone;
          }
        } catch (e) {
          debugPrint('خطأ في جلب رقم الهاتف للعميل $customerId');
          // في حالة الخطأ، نحفظ "غير متوفر" في الـ cache لتجنب المحاولة مرة أخرى
          _phoneCache[customerId] = 'غير متوفر';
        }
      }
    }

    // إنشاء نسخة جديدة من الاشتراك مع رقم الهاتف
    Map<String, dynamic> enhancedSubscription =
        Map<String, dynamic>.from(subscription);
    enhancedSubscription['customerPhone'] = phone;
    return enhancedSubscription;
  }

  Future<void> _exportToExcel() async {
    if (totalItems == 0) {
      ftthShowSnackBar(
        context,
        const SnackBar(
          content: Text('لا توجد بيانات للتصدير'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      isExporting = true;
      exportMessage = 'جاري جلب جميع البيانات للتصدير...';
    });

    try {
      // جلب جميع البيانات للتصدير
      List<dynamic> allData = await _fetchAllDataForExport();

      if (allData.isEmpty) {
        if (!mounted) return;
        setState(() {
          exportMessage = 'لا توجد بيانات للتصدير';
          isExporting = false;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        exportMessage = 'جاري إنشاء ملف Excel...';
      });
      // إنشاء ملف Excel جديد
      var excel = ExcelLib.Excel.createExcel();
      String sheetName =
          showTrialSubscriptions ? 'Trial_Subscriptions' : 'Expiring_Soon';
      ExcelLib.Sheet sheet = excel[sheetName];

      if (!mounted) return;
      setState(() {
        exportMessage = 'جاري إعداد رؤوس الأعمدة...';
      });

      // إضافة رؤوس الأعمدة (مطابقة للعينة المطلوبة)
      List<String> headers = [
        'اسم المشترك',
        'رقم الهاتف',
        'رقم تعريف المشترك',
        'حالة الاشتراك',
        'تاريخ بدء الاشتراك',
        'تاريخ انتهاء الاشتراك',
        'مدة الالتزام (شهر)',
        'المنطقة',
        'رقم تعريف الاشتراك',
        'نوع الباقة',
        'اسم المستخدم',
        'حالة الاتصال',
        'أول خدمة',
        'عنوان IP',
        'تاريخ الإنشاء',
      ];

      for (int i = 0; i < headers.length; i++) {
        var cell = sheet.cell(
            ExcelLib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = ExcelLib.TextCellValue(headers[i]);
      }

      if (!mounted) return;
      setState(() {
        exportMessage = 'جاري كتابة البيانات...';
      });

      // إضافة البيانات (دفعات منطقية لتحديث الرسالة فقط)
      const int progressChunk = 100;
      int written = 0;
      int excelRow = 1; // الصف 0 للرؤوس

      for (final item in allData) {
        final customerId = item['customer']?['id']?.toString() ?? '';
        final subscriptionId =
            item['id']?.toString() ?? item['self']?['id']?.toString() ?? '';
        final customerName =
            item['customer']?['displayValue']?.toString() ?? 'غير محدد';
        final phone = item['customerPhone']?.toString() ?? 'غير متوفر';
        final commitment = item['commitmentPeriod']?.toString() ?? '';
        final expiryStr = item['expires']?.toString();
        DateTime? expiryDate;
        try {
          if (expiryStr != null) expiryDate = DateTime.parse(expiryStr);
        } catch (_) {}
        String status = 'غير معروف';
        if (expiryDate != null) {
          final diff = expiryDate.difference(DateTime.now()).inDays;
          status = diff < 0 ? 'منتهي' : 'نشط';
        }
        DateTime? startDate;
        for (final key in [
          'activationDate',
          'activatedOn',
          'startDate',
          'starts',
          'createdOn'
        ]) {
          if (item[key] != null) {
            try {
              startDate = DateTime.parse(item[key]);
              break;
            } catch (_) {}
          }
        }
        if (startDate == null && expiryDate != null && commitment.isNotEmpty) {
          final months = int.tryParse(commitment) ?? 0;
          if (months > 0) {
            int y = expiryDate.year;
            int m = expiryDate.month - months;
            while (m <= 0) {
              m += 12;
              y -= 1;
            }
            final d = expiryDate.day;
            final lastDay = DateTime(y, m + 1, 0).day;
            startDate = DateTime(y, m, d > lastDay ? lastDay : d);
          }
        }
        String fmt(DateTime? dt) => dt == null
            ? ''
            : '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        final zoneName = item['zone']?['displayValue']?.toString() ?? '';
        final plan = item['bundle']?['displayValue']?.toString() ?? '';
        final username = item['username']?.toString() ?? '';
        final bool isOnline = item['hasActiveSession'] == true;
        String connectionStatus = isOnline ? 'متصل' : 'غير متصل';
        String firstServiceName = '';
        String ipAddress = '';
        if (item['services'] is List && (item['services'] as List).isNotEmpty) {
          final first = (item['services'] as List).first;
          try {
            firstServiceName = first['displayValue']?.toString() ??
                first['name']?.toString() ??
                '';
          } catch (_) {}
          for (final key in [
            'ip',
            'ipAddress',
            'framedIp',
            'framedIPAddress',
            'framedAddress',
            'framedIP'
          ]) {
            if (first[key] != null) {
              ipAddress = first[key].toString();
              break;
            }
          }
        }
        String createdOnFormatted = '';
        if (item['createdOn'] != null) {
          try {
            final created = DateTime.parse(item['createdOn']);
            createdOnFormatted = fmt(created);
          } catch (_) {}
        }

        List<dynamic> rowData = [
          customerName,
          phone,
          customerId,
          status,
          fmt(startDate),
          fmt(expiryDate),
          commitment,
          zoneName,
          subscriptionId,
          plan,
          username,
          connectionStatus,
          firstServiceName,
          ipAddress,
          createdOnFormatted,
        ];

        for (int j = 0; j < rowData.length; j++) {
          var cell = sheet.cell(ExcelLib.CellIndex.indexByColumnRow(
              columnIndex: j, rowIndex: excelRow));
          cell.value = ExcelLib.TextCellValue(rowData[j].toString());
        }
        excelRow++;
        written++;

        if (written % progressChunk == 0 && mounted) {
          setState(() {
            exportMessage = 'تم كتابة $written من ${allData.length} سجل...';
          });
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
      // رسالة نهائية قبل الحفظ
      if (!mounted) return;
      setState(() {
        exportMessage = 'تم كتابة ${allData.length} سجل - جاري الحفظ...';
      });

      setState(() {
        exportMessage = 'جاري حفظ الملف...';
      });

      // الحصول على مجلد التنزيلات
      String? downloadsPath;
      try {
        if (Platform.isAndroid) {
          downloadsPath = '/storage/emulated/0/Download';
        } else if (Platform.isWindows) {
          // في Windows نستخدم مجلد Documents
          final directory = await getApplicationDocumentsDirectory();
          downloadsPath = '${directory.path}\\FTTH_Exports';
          // إنشاء المجلد إذا لم يكن موجوداً
          final exportDir = Directory(downloadsPath);
          if (!await exportDir.exists()) {
            await exportDir.create(recursive: true);
          }
        } else {
          final directory = await getApplicationDocumentsDirectory();
          downloadsPath = directory.path;
        }
      } catch (e) {
        // في حالة فشل الحصول على المجلد، نستخدم Documents
        final directory = await getApplicationDocumentsDirectory();
        downloadsPath = directory.path;
      }

      // إنشاء اسم الملف مع التاريخ والوقت
      final now = DateTime.now();
      final timestamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
      final fileName =
          '${showTrialSubscriptions ? 'اشتراكات_تجريبية' : 'اشتراكات_منتهية_قريبا'}_$timestamp.xlsx';
      final filePath = '$downloadsPath/$fileName';

      // حفظ الملف
      List<int>? fileBytes = excel.save();
      File file = File(filePath);
      await file.writeAsBytes(fileBytes!);

      if (!mounted) return;
      setState(() {
        exportMessage = 'تم حفظ ${allData.length} سجل في $fileName';
        isExporting = false;
      });

      if (!mounted) return;
      ftthShowSnackBar(
        context,
        SnackBar(
          content: Text(
              'تم تصدير ${allData.length} سجل إلى Excel بنجاح!\nمحفوظ في: $filePath'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'نسخ المسار',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: filePath));
              ftthShowSnackBar(
                context,
                const SnackBar(
                  content: Text('تم نسخ مسار الملف'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ),
      );

      // مسح رسالة التصدير بعد 5 ثوانٍ
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            exportMessage = '';
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        exportMessage = 'فشل في التصدير';
        isExporting = false;
      });

      ftthShowSnackBar(
        context,
        SnackBar(
          content: Text('فشل في تصدير Excel'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<List<dynamic>> _fetchAllDataForExport() async {
    List<dynamic> allData = [];
    int page = 1;
    const int pageSize = 100; // جلب 100 سجل في كل دفعة

    try {
      while (true) {
        if (!mounted) break;
        setState(() {
          exportMessage =
              'جاري جلب البيانات - الدفعة $page (${allData.length} سجل تم جلبه)...';
        });

        String apiUrl;
        if (showTrialSubscriptions) {
          apiUrl =
              'https://admin.ftth.iq/api/subscriptions/trial?pageSize=$pageSize&pageNumber=$page&sortCriteria.property=expires&sortCriteria.direction=asc&status=Active&hierarchyLevel=0';
        } else {
          final baseUrl =
              'https://admin.ftth.iq/api/subscriptions?pageSize=$pageSize&pageNumber=$page&sortCriteria.property=expires&sortCriteria.direction=asc&status=Active&hierarchyLevel=0';
          if (_dateFilterType == 'all') {
            apiUrl = baseUrl;
          } else {
            final range = _computeDateRange();
            final fromDate = range.fromDate.toIso8601String();
            final toDate = range.toDate.toIso8601String();
            apiUrl =
                '$baseUrl&fromExpirationDate=$fromDate&toExpirationDate=$toDate';
          }
        }

        // إضافة فلاتر التصفية المتقدمة
        if (_selectedZoneId != null && _selectedZoneId!.isNotEmpty) {
          apiUrl += '&zoneId=$_selectedZoneId';
        }

        if (_selectedPlanName != null && _selectedPlanName!.isNotEmpty) {
          apiUrl += '&bundleName=$_selectedPlanName';
        }

        final response =
            await AuthService.instance.authenticatedRequest('GET', apiUrl);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final pageItems = data['items'] ?? [];

          if (pageItems.isEmpty) {
            break; // لا توجد المزيد من البيانات
          }

          // جلب أرقام الهواتف لكل اشتراك في هذه الدفعة بشكل متوازي
          List<dynamic> enhancedPageItems =
              await _fetchPhonesInParallel(pageItems);
          allData.addAll(enhancedPageItems);

          // تحديث التقدم كل 100 سجل
          if (mounted) {
            setState(() {
              exportMessage = 'تم جلب ${allData.length} سجل حتى الآن...';
            });
          }

          page++;

          // إضافة توقف قصير بين الطلبات لتجنب إرهاق الخادم
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          throw Exception(
              'فشل في جلب البيانات من الخادم: ${response.statusCode}');
        }
      }
    } catch (e) {
      throw Exception('خطأ في جلب البيانات');
    }

    return allData;
  }

  void _clearPhoneCache() {
    _phoneCache.clear();
    debugPrint('تم مسح ذاكرة التخزين المؤقت لأرقام الهواتف');
  }

  void _goToPage(int page) {
    if (page >= 1 && page <= _getTotalPages()) {
      setState(() {
        currentPage = page;
      });
      _fetchExpiringSoonData();
    }
  }

  void _goToNextPage() {
    if (currentPage < _getTotalPages()) {
      _goToPage(currentPage + 1);
    }
  }

  void _goToPreviousPage() {
    if (currentPage > 1) {
      _goToPage(currentPage - 1);
    }
  }

  int _getTotalPages() {
    return (totalItems / itemsPerPage).ceil();
  }

  // استخراج اسم المنطقة للعرض من هيكل JSON المختلف
  String _getZoneDisplayName(Map<String, dynamic> zone) {
    try {
      if (zone['self'] != null) {
        final self = zone['self'];
        if (self is Map<String, dynamic>) {
          if (self['displayValue'] != null) {
            return self['displayValue'].toString();
          }
          if (self['name'] != null) {
            return self['name'].toString();
          }
          if (self['title'] != null) {
            return self['title'].toString();
          }
        }
      }
      if (zone['displayValue'] != null) return zone['displayValue'].toString();
      if (zone['name'] != null) return zone['name'].toString();
      if (zone['title'] != null) return zone['title'].toString();
      if (zone['id'] != null) return zone['id'].toString();
    } catch (_) {}
    return 'غير معروف';
  }

  // استخراج أول رقم داخل النص (للفرز الطبيعي مثل FBG9 قبل FBG10)
  int? _extractFirstNumber(String input) {
    final match = RegExp(r"\d+").firstMatch(input);
    if (match != null) {
      return int.tryParse(match.group(0)!);
    }
    return null;
  }

  // مقارنة منطقيّة للمناطق: أولاً حسب البادئة الحرفية ثم رقمياً إن وجد رقم
  int _zoneComparator(Map<String, dynamic> a, Map<String, dynamic> b) {
    final nameA = _getZoneDisplayName(a).trim().toUpperCase();
    final nameB = _getZoneDisplayName(b).trim().toUpperCase();

    // قارن البادئة غير الرقمية أولاً
    final prefixA = RegExp(r"^[^0-9]+").stringMatch(nameA) ?? '';
    final prefixB = RegExp(r"^[^0-9]+").stringMatch(nameB) ?? '';

    final prefixCompare = prefixA.compareTo(prefixB);
    if (prefixCompare != 0) return prefixCompare;

    // إن وُجد أرقام، قارنها رقمياً
    final numA = _extractFirstNumber(nameA);
    final numB = _extractFirstNumber(nameB);
    if (numA != null && numB != null) {
      if (numA != numB) return numA.compareTo(numB);
    }

    // وإلا فمقارنة نصية عادية
    return nameA.compareTo(nameB);
  }

  // دالة جلب المناطق من API
  Future<void> _fetchZones() async {
    if (!mounted) return;
    setState(() {
      _isLoadingZones = true;
    });

    try {
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://admin.ftth.iq/api/locations/zones',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('🔍 استجابة API للمناطق: $data');

        if (data != null && data['items'] != null) {
          debugPrint('📊 عدد المناطق المُستلمة: ${data['items'].length}');

          // طباعة أول منطقة لفهم البنية
          if (data['items'].isNotEmpty) {
            debugPrint('🏢 أول منطقة - البنية الكاملة: ${data['items'][0]}');
          }
        }

        // تحويل وفرز تصاعدي حسب اسم المنطقة مع دعم الفرز الطبيعي للأرقام
        final zones = List<Map<String, dynamic>>.from(data['items'] ?? []);
        zones.sort(_zoneComparator);

        if (!mounted) return;
        setState(() {
          _zones = zones;
          _isLoadingZones = false;
        });
      } else {
        debugPrint('❌ خطأ في جلب المناطق: ${response.statusCode}');
        debugPrint('📄 رسالة الخطأ: ${response.body}');
        if (!mounted) return;
        setState(() {
          _zones = [];
          _isLoadingZones = false;
        });
      }
    } catch (e) {
      debugPrint('💥 خطأ في جلب المناطق');

      // التحقق من خطأ عدم وجود توكن صالح
      if (e.toString().contains('لا يوجد توكن صالح')) {
        debugPrint('🚨 التوكن غير صالح - التوجيه إلى صفحة تسجيل الدخول');

        // إظهار رسالة للمستخدم
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'انتهت صلاحية جلسة المستخدم، يرجى تسجيل الدخول مرة أخرى'),
              backgroundColor: Colors.red[600],
              duration: const Duration(seconds: 3),
            ),
          );

          // التوجيه إلى صفحة تسجيل الدخول
          Navigator.of(context).pushNamedAndRemoveUntil(
            '/login',
            (Route<dynamic> route) => false,
          );
        }
      }

      if (mounted) {
        setState(() {
          _zones = [];
          _isLoadingZones = false;
        });
      }
    }
  }

  // دالة إعادة تعيين الفلاتر
  void _resetFilters() {
    setState(() {
      _selectedZoneId = null;
      _selectedPlanName = null;
      _dateFilterType = 'default';
      _customStartDate = null;
      _customEndDate = null;
      currentPage = 1;
      _showAdvancedFilters = false; // إخفاء البطاقة بعد إعادة التعيين
    });
    _fetchExpiringSoonData();
  }

  // دالة تطبيق الفلاتر
  void _applyFilters() {
    setState(() {
      currentPage = 1; // العودة للصفحة الأولى عند تطبيق فلتر جديد
      _showAdvancedFilters = false; // إخفاء البطاقة بعد التطبيق
    });
    _fetchExpiringSoonData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              showTrialSubscriptions
                  ? 'الاشتراكات التجريبية'
                  : 'الاشتراكات المنتهية قريباً',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
        backgroundColor: showTrialSubscriptions
            ? const Color(0xFF6366F1)
            : const Color(0xFFEC4899),
        elevation: 4,
        actions: [
          if (_hasActiveFilters())
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.clear_all_rounded,
                      color: Colors.white, size: 22),
                  tooltip: 'مسح كل الفلاتر وعرض الكل',
                  onPressed: _resetFilters,
                ),
              ),
            ),
          // زر التصفية المتقدمة بإستايل أوضح
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: IconButton(
                icon: const Icon(Icons.tune_rounded,
                    color: Colors.white, size: 22),
                tooltip: 'التصفية المتقدمة',
                onPressed: () {
                  setState(() {
                    _showAdvancedFilters = !_showAdvancedFilters;
                  });
                },
              ),
            ),
          ),
          if (expiringSoonData.isNotEmpty && !isExporting)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.25)),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.cloud_download_rounded,
                      color: Colors.white, size: 22),
                  tooltip: 'تصدير البيانات',
                  onSelected: (String value) {
                    if (value == 'excel') {
                      _exportToExcel();
                    } else if (value == 'clear_cache') {
                      _clearPhoneCache();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'تم مسح ذاكرة التخزين المؤقت لأرقام الهواتف'),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'excel',
                      child: Row(
                        children: [
                          Icon(Icons.table_chart, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text('تصدير إلى Excel'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'clear_cache',
                      child: Row(
                        children: [
                          Icon(Icons.refresh, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Text('مسح ذاكرة أرقام الهواتف'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isExporting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: IconButton(
                icon: const Icon(Icons.autorenew_rounded,
                    color: Colors.white, size: 22),
                onPressed: _fetchExpiringSoonData,
                tooltip: 'تحديث البيانات',
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: showTrialSubscriptions
                  ? [const Color(0xFFF0F4FF), const Color(0xFFE0E7FF)]
                  : [const Color(0xFFFDF2F8), const Color(0xFFFCE7F3)],
            ),
          ),
          child: Column(
            children: [
              if (_showAdvancedFilters) _buildAdvancedFilters(),
              if (totalItems > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Card(
                    elevation: 6,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                            color: (showTrialSubscriptions
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFFEC4899))
                                .withValues(alpha: 0.25))),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          // صندوق المجموع الكلي
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    (showTrialSubscriptions
                                        ? const Color(0xFFEEF2FF)
                                        : const Color(0xFFFDF2F8)),
                                    Colors.white,
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: (showTrialSubscriptions
                                          ? const Color(0xFF6366F1)
                                          : const Color(0xFFEC4899))
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'المجموع الكلي',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '$totalItems',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: showTrialSubscriptions
                                          ? const Color(0xFF6366F1)
                                          : const Color(0xFFEC4899),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // صندوق المبلغ
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFEFFAF1), Colors.white],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.2)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'المبلغ',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Builder(
                                    builder: (_) {
                                      final amount = totalItems * 37000;
                                      final formatted =
                                          NumberFormat('#,##0').format(amount);
                                      return Text(
                                        formatted,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.green,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _buildBody(),
              ),
              if (totalItems > itemsPerPage) _buildPaginationControls(),
              if (exportMessage.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isExporting
                        ? (showTrialSubscriptions
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFEC4899))
                        : Colors.green,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (isExporting)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      if (isExporting) const SizedBox(width: 12),
                      if (!isExporting)
                        const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                      if (!isExporting) const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          exportMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedFilters() {
    return Container(
      constraints:
          const BoxConstraints(maxHeight: 160), // زيادة بسيطة لاستيعاب الزر
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Spacer(),
                if (_selectedZoneId != null || _selectedPlanName != null)
                  TextButton(
                    onPressed: _resetFilters,
                    child: const Text(
                      'إزالة الفلاتر',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // فلاتر التاريخ
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDateFilterChip('اليوم', 'today'),
                  _buildDateFilterChip('غداً', 'tomorrow'),
                  _buildDateFilterChip('3 أيام', 'default'),
                  _buildDateFilterChip('الكل', 'all'),
                  if (_dateFilterType == 'custom' ||
                      _customStartDate != null ||
                      _customEndDate != null) ...[
                    const SizedBox(width: 6),
                    _buildSingleDateBox(
                      label: 'البداية',
                      date: _customStartDate,
                      onTap: _pickStartDate,
                    ),
                    const SizedBox(width: 6),
                    _buildSingleDateBox(
                      label: 'النهاية',
                      date: _customEndDate,
                      onTap: _pickEndDate,
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      onPressed: (_customStartDate != null &&
                              _customEndDate != null)
                          ? () {
                              // منع التفعيل إن كانت النهاية قبل البداية (أمان إضافي)
                              if (_customStartDate!.isAfter(_customEndDate!)) {
                                final tmp = _customStartDate!;
                                setState(() {
                                  _customStartDate = _customEndDate;
                                  _customEndDate = tmp;
                                });
                              }
                              _applyFilters();
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        backgroundColor:
                            (_customStartDate != null && _customEndDate != null)
                                ? (showTrialSubscriptions
                                    ? const Color(0xFF6366F1)
                                    : const Color(0xFFEC4899))
                                : Colors.grey,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold),
                        elevation: 0,
                        minimumSize: const Size(64, 40),
                      ),
                      child: const Text('تطبيق'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // قائمة المناطق
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox.shrink(),
                      const SizedBox(height: 0),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _isLoadingZones
                            ? const SizedBox(
                                height: 44,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                ),
                              )
                            : DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _selectedZoneId != null &&
                                          _zones.any((zone) {
                                            String zoneId = zone['self'] !=
                                                        null &&
                                                    zone['self']['id'] != null
                                                ? zone['self']['id'].toString()
                                                : (zone['id']?.toString() ??
                                                    '');
                                            return zoneId == _selectedZoneId;
                                          })
                                      ? _selectedZoneId
                                      : null,
                                  hint: const Text('اختر المنطقة'),
                                  isExpanded: true,
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('جميع المناطق'),
                                    ),
                                    ..._zones.map((zone) {
                                      // استخدام نفس الطريقة المُستخدمة في zones_page.dart
                                      String zoneName = 'غير معروف';
                                      String zoneId = '';

                                      try {
                                        // الحصول على معرف المنطقة
                                        if (zone['self'] != null &&
                                            zone['self']['id'] != null) {
                                          zoneId =
                                              zone['self']['id'].toString();
                                        } else if (zone['id'] != null) {
                                          zoneId = zone['id'].toString();
                                        }

                                        // الحصول على اسم المنطقة
                                        // الطريقة الأولى: zone['self']['displayValue']
                                        if (zone['self'] != null &&
                                            zone['self']['displayValue'] !=
                                                null) {
                                          zoneName = zone['self']
                                                  ['displayValue']
                                              .toString();
                                        }
                                        // الطريقة الثانية: zone['displayValue']
                                        else if (zone['displayValue'] != null) {
                                          zoneName =
                                              zone['displayValue'].toString();
                                        }
                                        // الطريقة الثالثة: zone['name']
                                        else if (zone['name'] != null) {
                                          zoneName = zone['name'].toString();
                                        }
                                        // الطريقة الرابعة: zone['title']
                                        else if (zone['title'] != null) {
                                          zoneName = zone['title'].toString();
                                        }
                                        // الطريقة الخامسة: استخدام معرف المنطقة
                                        else if (zoneId.isNotEmpty) {
                                          zoneName = zoneId;
                                        }
                                      } catch (e) {
                                        debugPrint(
                                            'خطأ في معالجة اسم المنطقة');
                                      }

                                      return DropdownMenuItem<String>(
                                        value: zoneId.isEmpty ? null : zoneId,
                                        child: Text(zoneName),
                                      );
                                    }),
                                  ],
                                  onChanged: (String? value) {
                                    setState(() {
                                      _selectedZoneId = value;
                                    });
                                    _applyFilters();
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // قائمة الباقات
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox.shrink(),
                      const SizedBox(height: 0),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedPlanName != null &&
                                    _planOptions.contains(_selectedPlanName)
                                ? _selectedPlanName
                                : null,
                            hint: const Text('اختر الباقة'),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('جميع الباقات'),
                              ),
                              ..._planOptions.map((plan) {
                                return DropdownMenuItem<String>(
                                  value: plan,
                                  child: Text(plan),
                                );
                              }),
                            ],
                            onChanged: (String? value) {
                              setState(() {
                                _selectedPlanName = value;
                              });
                              _applyFilters();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_selectedZoneId != null || _selectedPlanName != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  if (_selectedZoneId != null)
                    Chip(
                      label: Text(
                        'المنطقة: ${_zones.firstWhere((z) => z['id']?.toString() == _selectedZoneId, orElse: () => {
                              'displayValue': 'غير محدد'
                            })['displayValue']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: showTrialSubscriptions
                          ? const Color(0xFFE0E7FF)
                          : const Color(0xFFFCE7F3),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() {
                          _selectedZoneId = null;
                        });
                        _applyFilters();
                      },
                    ),
                  if (_selectedPlanName != null)
                    Chip(
                      label: Text(
                        'الباقة: $_selectedPlanName',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: showTrialSubscriptions
                          ? const Color(0xFFE0E7FF)
                          : const Color(0xFFFCE7F3),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() {
                          _selectedPlanName = null;
                        });
                        _applyFilters();
                      },
                    ),
                  if (_dateFilterType != 'default')
                    Chip(
                      label: Text(
                        _dateFilterType == 'today'
                            ? 'اليوم'
                            : _dateFilterType == 'tomorrow'
                                ? 'غداً'
                                : _dateFilterType == 'custom' &&
                                        _customStartDate != null &&
                                        _customEndDate != null
                                    ? '${DateFormat('MM/dd').format(_customStartDate!)} - ${DateFormat('MM/dd').format(_customEndDate!)}'
                                    : _dateFilterType == 'all'
                                        ? 'الكل'
                                        : 'فلتر تاريخ',
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: showTrialSubscriptions
                          ? const Color(0xFFE0E7FF)
                          : const Color(0xFFFCE7F3),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () {
                        setState(() {
                          _dateFilterType = 'all';
                          _customStartDate = null;
                          _customEndDate = null;
                        });
                        _applyFilters();
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ), // إغلاق SingleChildScrollView
    ); // إغلاق Container
  }

  // عنصر واجهة Chip لاختيار نوع التاريخ
  Widget _buildDateFilterChip(String label, String type) {
    final selected = _dateFilterType == type;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: () async {
          setState(() {
            _dateFilterType = type;
          });
          if (type == 'custom') {
            // تهيئة التواريخ المخصصة الافتراضية إن لم تكن موجودة
            final now = DateTime.now();
            setState(() {
              _customStartDate ??= DateTime(now.year, now.month, now.day);
              _customEndDate ??= DateTime(now.year, now.month, now.day);
            });
          } else {
            _applyFilters();
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? (showTrialSubscriptions
                    ? const Color(0xFF6366F1)
                    : const Color(0xFFEC4899))
                : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? (showTrialSubscriptions
                          ? const Color(0xFF6366F1)
                          : const Color(0xFFEC4899))
                      .withValues(alpha: 0.6)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              if (type == 'custom')
                Icon(Icons.calendar_month,
                    size: 16,
                    color: selected
                        ? Colors.white
                        : (showTrialSubscriptions
                            ? const Color(0xFF6366F1)
                            : const Color(0xFFEC4899))),
              if (type == 'custom') const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : (showTrialSubscriptions
                          ? const Color(0xFF6366F1)
                          : const Color(0xFFEC4899)),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // واجهة اختيار تاريخ بداية منفصل
  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customStartDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'اختر تاريخ البداية',
      cancelText: 'إلغاء',
      confirmText: 'تم',
    );
    if (picked != null) {
      setState(() {
        _dateFilterType = 'custom';
        _customStartDate = DateTime(picked.year, picked.month, picked.day);
        // ضمان عدم تجاوز النهاية للبداية
        if (_customEndDate != null &&
            _customEndDate!.isBefore(_customStartDate!)) {
          _customEndDate = _customStartDate;
        }
      });
      // لا نطبق تلقائياً؛ ينتظر المستخدم زر "تطبيق"
    }
  }

  // واجهة اختيار تاريخ نهاية منفصل
  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final baseStart = _customStartDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: _customEndDate ?? baseStart,
      firstDate: baseStart,
      lastDate: baseStart.add(const Duration(days: 365)),
      helpText: 'اختر تاريخ النهاية',
      cancelText: 'إلغاء',
      confirmText: 'تم',
    );
    if (picked != null) {
      setState(() {
        _dateFilterType = 'custom';
        _customEndDate = DateTime(picked.year, picked.month, picked.day);
      });
      // لا نطبق تلقائياً؛ ينتظر المستخدم زر "تطبيق"
    }
  }

  Widget _buildSingleDateBox(
      {required String label,
      required DateTime? date,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blueGrey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.date_range, size: 16),
            const SizedBox(width: 4),
            Text(
              date == null
                  ? label
                  : '$label: ${DateFormat('MM/dd').format(date)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(showTrialSubscriptions
                  ? const Color(0xFF6366F1)
                  : const Color(0xFFEC4899)),
            ),
            const SizedBox(height: 16),
            Text(
              showTrialSubscriptions
                  ? 'جاري تحميل الاشتراكات التجريبية وأرقام الهواتف...'
                  : 'جاري تحميل البيانات وأرقام الهواتف...',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'التحميل بشكل متوازي لتسريع العملية',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    if (errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              'حدث خطأ',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchExpiringSoonData,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEC4899),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (expiringSoonData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.green[400],
            ),
            const SizedBox(height: 16),
            Text(
              showTrialSubscriptions
                  ? 'لا توجد اشتراكات تجريبية'
                  : 'لا توجد اشتراكات تنتهي خلال 3 أيام',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              showTrialSubscriptions
                  ? 'جميع الاشتراكات مفعلة بالكامل'
                  : 'جميع الاشتراكات النشطة في حالة جيدة',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchExpiringSoonData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: expiringSoonData.length,
        itemBuilder: (context, index) {
          final item = expiringSoonData[index];
          return _buildExpiringSoonCard(item);
        },
      ),
    );
  }

  Widget _buildExpiringSoonCard(dynamic item) {
    // تحويل تاريخ الانتهاء إلى نص مفهوم مع الوقت المتبقي
    String expiryDate = 'غير محدد';
    String daysRemaining = '';

    bool isExpired = false;
    int totalHours = 0;
    int remMinutes = 0;
    String remainingExact = '';
    if (item['expires'] != null) {
      try {
        final expiry = DateTime.parse(item['expires']);
        final now = DateTime.now();
        final difference = expiry.difference(now);
        final daysDiff = difference.inDays;

        expiryDate = '${expiry.day}/${expiry.month}/${expiry.year}';

        isExpired = difference.isNegative;
        totalHours = difference.inHours.abs();
        remMinutes = difference.inMinutes.abs() % 60;
        remainingExact = isExpired
            ? 'منتهي منذ $totalHoursس $remMinutesد'
            : 'متبقي $totalHoursس $remMinutesد';

        if (isExpired) {
          daysRemaining = 'منتهي';
        } else if (daysDiff == 0) {
          daysRemaining = 'ينتهي اليوم';
        } else {
          daysRemaining = 'متبقي $daysDiff يوم';
        }
      } catch (e) {
        expiryDate = 'تاريخ غير صالح';
      }
    }

    // استخراج أول خدمة فقط
    String firstService = '';
    try {
      if (item['services'] is List && (item['services'] as List).isNotEmpty) {
        final first = (item['services'] as List).first;
        if (first is Map && first['displayValue'] != null) {
          firstService = first['displayValue'].toString();
        }
      }
    } catch (_) {}

    // قيم إضافية مطلوبة للعرض بالترتيب المطلوب (إخفاء اسم العميل والحالة داخل تفاصيل البطاقة)
    final String phone = item['customerPhone'] ?? 'غير متوفر';
    final String idStr =
        item['id']?.toString() ?? item['self']?['id']?.toString() ?? 'غير محدد';
    final String zoneName = item['zone']?['displayValue'] ?? 'غير محدد';
    // حالة الجلسة لتلوين خلفية تفاصيل البطاقة
    final bool isOnline = item['hasActiveSession'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 3,
      shadowColor: showTrialSubscriptions
          ? const Color(0xFF6366F1).withValues(alpha: 0.15)
          : const Color(0xFFEC4899).withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: showTrialSubscriptions
                ? [Colors.white, const Color(0xFFF0F4FF)]
                : [Colors.white, const Color(0xFFFDF2F8)],
          ),
          border: Border.all(
            color: showTrialSubscriptions
                ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                : const Color(0xFFEC4899).withValues(alpha: 0.1),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // هيدر البطاقة
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: showTrialSubscriptions
                          ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                          : const Color(0xFFEC4899).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      showTrialSubscriptions
                          ? Icons.science_rounded
                          : Icons.warning_amber_rounded,
                      color: showTrialSubscriptions
                          ? const Color(0xFF6366F1)
                          : const Color(0xFFEC4899),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: () => _openUserDetails(item),
                      borderRadius: BorderRadius.circular(6),
                      child: Text(
                        item['customer']?['displayValue'] ??
                            'عميل غير محدد',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // زر نسخ
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(
                        text: '${item['customer']?['displayValue'] ?? ''}\n$phone\n${item['username'] ?? ''}',
                      ));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('تم النسخ'),
                        backgroundColor: Colors.teal,
                        duration: Duration(seconds: 1),
                      ));
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.copy_rounded, size: 16, color: Colors.grey[500]),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: showTrialSubscriptions
                          ? const Color(0xFF6366F1)
                          : const Color(0xFFEC4899),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      showTrialSubscriptions ? 'تجريبي' : daysRemaining,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // تفاصيل الاشتراك بالترتيب المطلوب
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  // تلوين خلفية تفاصيل البطاقة حسب حالة الجلسة
                  color: isOnline ? Colors.green[50] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: showTrialSubscriptions
                        ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                        : const Color(0xFFEC4899).withValues(alpha: 0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Builder(
                  builder: (context) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    final allRows = <Widget>[
                      _buildDetailRow(
                        'اليوزر نيم ',
                        item['username'] ?? 'غير محدد',
                        onTap: () => _openUserDetails(item),
                        isLink: true,
                      ),
                      _buildDetailRow('رقم الهاتف', phone),
                      _buildDetailRow('ID', idStr),
                      _buildDetailRow('تاريخ الانتهاء', expiryDate),
                      _buildDetailRow(
                        'الوقت المتبقي',
                        remainingExact.isNotEmpty
                            ? remainingExact
                            : (daysRemaining.isNotEmpty
                                ? daysRemaining
                                : 'غير محدد'),
                        valueColor:
                            isExpired ? Colors.red[700] : Colors.green[700],
                      ),
                      _buildDetailRow('المنطقة', zoneName),
                      if (firstService.isNotEmpty)
                        _buildDetailRow('أول خدمة', firstService),
                      _buildDetailRow('حالة الجلسة',
                          item['hasActiveSession'] == true ? 'متصل' : 'غير متصل'),
                    ];

                    // 4 أعمدة على سطح المكتب، 2 على التابلت، 1 على الهاتف
                    final int cols = screenWidth >= 900 ? 4 : (screenWidth >= 500 ? 2 : 1);
                    if (cols == 1) {
                      return Column(children: allRows);
                    }
                    final rows = <Widget>[];
                    for (int i = 0; i < allRows.length; i += cols) {
                      final rowItems = <Widget>[];
                      for (int j = 0; j < cols; j++) {
                        if (j > 0) rowItems.add(const SizedBox(width: 8));
                        rowItems.add(Expanded(
                          child: (i + j < allRows.length) ? allRows[i + j] : const SizedBox(),
                        ));
                      }
                      rows.add(Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: rowItems,
                      ));
                    }
                    return Column(children: rows);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openUserDetails(Map<String, dynamic> item) async {
    try {
      final customerId = item['customer']?['id']?.toString();
      if (customerId == null || customerId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يمكن فتح الصفحة: معرف العميل غير متوفر'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      // احصل على التوكن الحالي
      final token = await AuthService.instance.getAccessToken();
      if (token == null) {
        // جلسة غير صالحة -> توجيه لصفحة الدخول
        if (!mounted) return;
        AuthErrorHandler.handle401Error(context);
        return;
      }

      // اسم المُنفّذ: يُفضّل القادم من HomePage، وإن لم يتوفر نحاول جلبه ثم نستخدم "المستخدم" كافتراضي
      String activatedBy = (widget.activatedBy).toString().trim();
      if (activatedBy.isEmpty) {
        try {
          final resp = await AuthService.instance.authenticatedRequest(
            'GET',
            'https://api.ftth.iq/api/current-user',
          );
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            activatedBy = data['model']?['self']?['displayValue']?.toString() ??
                data['model']?['username']?.toString() ??
                '';
          }
        } catch (_) {}
        if (activatedBy.isEmpty) activatedBy = 'المستخدم';
      }

      final userName = item['customer']?['displayValue']?.toString() ??
          item['username']?.toString() ??
          'مستخدم';
      final userPhone = item['customerPhone']?.toString() ?? 'غير متوفر';

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetailsPage(
            userId: customerId,
            userName: userName,
            userPhone: userPhone,
            authToken: token,
            activatedBy: activatedBy,
            hasServerSavePermission: widget.hasServerSavePermission,
            hasWhatsAppPermission: widget.hasWhatsAppPermission,
            isAdminFlag: widget.isAdminFlag,
            userRoleHeader: '0',
            clientAppHeader: '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
            importantFtthApiPermissions: widget.importantFtthApiPermissions,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر فتح تفاصيل المستخدم'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildDetailRow(String label, String value,
      {Color? valueColor, VoidCallback? onTap, bool isLink = false}) {
    final isPhoneNumber = label == 'رقم الهاتف' && value != 'غير متوفر';
    final isExpiryDate = label == 'تاريخ الانتهاء';

    // أيقونة التصنيف
    IconData? labelIcon;
    Color? labelIconColor;
    if (isPhoneNumber) {
      labelIcon = Icons.phone_rounded;
      labelIconColor = Colors.green[600];
    } else if (isExpiryDate) {
      labelIcon = Icons.schedule_rounded;
      labelIconColor = showTrialSubscriptions
          ? const Color(0xFF6366F1)
          : const Color(0xFFEC4899);
    }

    // لون القيمة
    final effectiveValueColor = valueColor ??
        (isExpiryDate
            ? (showTrialSubscriptions
                ? const Color(0xFF6366F1)
                : const Color(0xFFEC4899))
            : const Color(0xFF2C3E50));

    // بناء القيمة
    Widget valueWidget;
    if (isPhoneNumber) {
      valueWidget = GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم نسخ رقم الهاتف: $value'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green[50],
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.green[200]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(value,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green[800]),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Icon(Icons.copy_rounded, size: 14, color: Colors.green[600]),
            ],
          ),
        ),
      );
    } else if (onTap != null) {
      final accent = showTrialSubscriptions ? const Color(0xFF6366F1) : const Color(0xFFEC4899);
      valueWidget = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(value,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: isLink ? (showTrialSubscriptions ? const Color(0xFF4338CA) : const Color(0xFF9D174D)) : effectiveValueColor,
                      decoration: isLink ? TextDecoration.underline : TextDecoration.none,
                    ),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 14, color: accent),
            ],
          ),
        ),
      );
    } else {
      valueWidget = Text(value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: effectiveValueColor),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (labelIcon != null) ...[
                Icon(labelIcon, size: 14, color: labelIconColor),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[600])),
            ],
          ),
          const SizedBox(height: 4),
          valueWidget,
        ],
      ),
    );
  }

  Widget _buildPaginationControls() {
    final totalPages = _getTotalPages();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: showTrialSubscriptions
                ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                : const Color(0xFFEC4899).withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // تمت إزالة شارة المجموع من الأسفل - أصبحت في الشريط العلوي

          // صف موحد: أزرار الانتقال يمين/يسار وأرقام الصفحات في الوسط
          Row(
            children: [
              // مجموعة الأزرار اليسرى (الأولى/السابق)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: currentPage > 1 ? () => _goToPage(1) : null,
                    icon: const Icon(Icons.first_page),
                    tooltip: 'الصفحة الأولى',
                    color: showTrialSubscriptions
                        ? const Color(0xFF6366F1)
                        : const Color(0xFFEC4899),
                  ),
                  IconButton(
                    onPressed: currentPage > 1 ? _goToPreviousPage : null,
                    icon: const Icon(Icons.chevron_left),
                    tooltip: 'الصفحة السابقة',
                    color: showTrialSubscriptions
                        ? const Color(0xFF6366F1)
                        : const Color(0xFFEC4899),
                  ),
                ],
              ),

              // الأرقام في الوسط مع تمرير أفقي
              Expanded(
                child: Center(
                  child: SizedBox(
                    height: 40,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...List.generate(
                            totalPages > 5 ? 5 : totalPages,
                            (index) {
                              int pageNumber;
                              if (totalPages <= 5) {
                                pageNumber = index + 1;
                              } else {
                                // عرض الصفحات المحيطة بالصفحة الحالية
                                int start =
                                    (currentPage - 2).clamp(1, totalPages - 4);
                                pageNumber = start + index;
                              }

                              return Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: pageNumber == currentPage
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: showTrialSubscriptions
                                              ? const Color(0xFF6366F1)
                                              : const Color(0xFFEC4899),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '$pageNumber',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      )
                                    : InkWell(
                                        onTap: () => _goToPage(pageNumber),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: showTrialSubscriptions
                                                  ? const Color(0xFF6366F1)
                                                      .withValues(alpha: 0.3)
                                                  : const Color(0xFFEC4899)
                                                      .withValues(alpha: 0.3),
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            '$pageNumber',
                                            style: TextStyle(
                                              color: showTrialSubscriptions
                                                  ? const Color(0xFF6366F1)
                                                  : const Color(0xFFEC4899),
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // مجموعة الأزرار اليمنى (التالي/الأخيرة)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: currentPage < totalPages ? _goToNextPage : null,
                    icon: const Icon(Icons.chevron_right),
                    tooltip: 'الصفحة التالية',
                    color: showTrialSubscriptions
                        ? const Color(0xFF6366F1)
                        : const Color(0xFFEC4899),
                  ),
                  IconButton(
                    onPressed: currentPage < totalPages
                        ? () => _goToPage(totalPages)
                        : null,
                    icon: const Icon(Icons.last_page),
                    tooltip: 'الصفحة الأخيرة',
                    color: showTrialSubscriptions
                        ? const Color(0xFF6366F1)
                        : const Color(0xFFEC4899),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
