/// اسم الصفحة: إدارة المستخدمين
/// وصف الصفحة: صفحة عرض وإدارة بيانات المستخدمين والمشتركين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:excel/excel.dart' as ex;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../users/user_details_page.dart';
import '../auth/login_page.dart';
import 'dart:io';
import '../../services/api_service.dart';
import '../../utils/smart_text_color.dart';
import '../../permissions/permissions.dart';

class UsersPage extends StatefulWidget {
  final String authToken;
  final String activatedBy;
  final bool hasServerSavePermission;
  final bool hasWhatsAppPermission;
  // علم إداري صريح
  final bool? isAdminFlag;
  // قائمة الصلاحيات المهمة المفلترة من نظام FTTH
  final List<String>? importantFtthApiPermissions;

  const UsersPage({
    super.key,
    required this.authToken,
    required this.activatedBy,
    this.hasServerSavePermission = false,
    this.hasWhatsAppPermission = false,
    this.isAdminFlag,
    this.importantFtthApiPermissions,
  });

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  // === متغيرات عرض البيانات ===
  final List<dynamic> allUsers = [];
  final List<dynamic> zones = [];
  final List<dynamic> filteredZones = [];
  bool isLoading = true;
  String errorMessage = "";

  // === متغيرات التقسيم إلى صفحات ===
  int currentPage = 1;
  int pageSize = 20; // زيادة القيمة الافتراضية لعرض أفضل
  int totalUsers = 0;

  // === متغيرات البحث والتصفية ===
  String selectedZoneId = "";
  String searchName = "";
  String searchPhone = "";
  String zoneSearchQuery = "";
  bool showFilter = false;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _zoneSearchController = TextEditingController();

  // === دوال مساعدة للفرز الطبيعي (Natural Sort) للأسماء التي تحتوي أرقامًا مثل FBG1023 ===
  List<dynamic> _tokenizeForNaturalSort(String s) {
    final regex = RegExp(r'(\d+|\D+)');
    return regex.allMatches(s).map((m) {
      final t = m.group(0)!;
      final asInt = int.tryParse(t);
      return asInt ?? t.toLowerCase();
    }).toList();
  }

  int _naturalCompare(String a, String b) {
    final ta = _tokenizeForNaturalSort(a);
    final tb = _tokenizeForNaturalSort(b);
    final len = ta.length < tb.length ? ta.length : tb.length;
    for (int i = 0; i < len; i++) {
      final va = ta[i];
      final vb = tb[i];
      if (va is int && vb is int) {
        if (va != vb) return va.compareTo(vb);
      } else {
        final sa = va.toString();
        final sb = vb.toString();
        if (sa != sb) return sa.compareTo(sb);
      }
    }
    return ta.length.compareTo(tb.length);
  }

  int _compareZonesByNaturalOrder(dynamic a, dynamic b) {
    final sa = a['displayValue']?.toString() ?? '';
    final sb = b['displayValue']?.toString() ?? '';
    return _naturalCompare(sa, sb);
  }

  // متغيرات تصدير إكسل
  bool isExcelExporting = false;
  String excelExportMessage = "";
  double excelExportProgress = 0.0; // نسبة مئوية لعدد السجلات المعالجة
  // محاولة فشل سابقة لتجنب تكرار fallback عدة مرات
  bool _excelFallbackTried = false;
  @override
  void initState() {
    super.initState();
    // ⚡ تأجيل التحميل حتى بعد انتهاء transition animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchZones();
      _fetchUsers();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _zoneSearchController.dispose();
    super.dispose();
  }

  // ============================================================================
  // دوال جلب البيانات من الـ API
  // ============================================================================
  /// جلب قائمة المناطق من الخادم
  Future<void> _fetchZones() async {
    try {
      final result = await ApiService.instance.get('/locations/zones');
      if (result['success']) {
        final data = result['data'];
        if (data != null &&
            data.containsKey('items') &&
            data['items'] is List) {
          setState(() {
            zones
              ..clear()
              ..addAll(data['items'].map((item) => item['self']).toList());
            zones.sort(_compareZonesByNaturalOrder);
            filteredZones
              ..clear()
              ..addAll(zones);
          });
        } else {
          setState(() {
            errorMessage = "المفتاح 'items' غير موجود أو لا يحتوي على قائمة.";
          });
        }
      } else {
        setState(() {
          errorMessage = "فشل جلب المناطق: ${result['error']}";
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "حدث خطأ أثناء جلب المناطق: $e";
      });
    }
  }

  /// جلب قائمة المستخدمين مع إمكانية البحث والتصفية
  Future<void> _fetchUsers() async {
    setState(() {
      isLoading = true;
      errorMessage = "";
    });
    try {
      String endpoint =
          '/customers?pageSize=$pageSize&pageNumber=$currentPage&sortCriteria.property=self.displayValue&sortCriteria.direction=asc';
      if (searchName.isNotEmpty) endpoint += '&name=$searchName';
      if (searchPhone.isNotEmpty) endpoint += '&phone=$searchPhone';
      if (selectedZoneId.isNotEmpty) endpoint += '&zoneId=$selectedZoneId';

      final result = await ApiService.instance.get(endpoint);

      if (result['success']) {
        final data = result['data'];
        setState(() {
          totalUsers = data['totalCount'] ?? 0;
          allUsers
            ..clear()
            ..addAll(data['items'] as List? ?? []);
        });
      } else {
        setState(() {
          errorMessage = "فشل جلب البيانات: ${result['error']}";
        });
      }
    } catch (e) {
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
      setState(() {
        errorMessage = "حدث خطأ أثناء جلب البيانات: $e";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // ============================================================================
  // دوال مساعدة للتصدير
  // ============================================================================

  /// إعادة المحاولة للعمليات الفاشلة
  Future<T> _retryOperation<T>(Future<T> Function() operation,
      {int maxAttempts = 3}) async {
    int attempts = 0;
    while (attempts < maxAttempts) {
      try {
        return await operation();
      } catch (e) {
        attempts++;
        if (attempts == maxAttempts) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempts));
        debugPrint(
            'Retrying operation, attempt ${attempts + 1} of $maxAttempts');
      }
    }
    throw Exception('Failed after $maxAttempts attempts');
  }

  Future<void> _optimizeMemory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        debugPrint('Optimizing memory...');
        await Future.delayed(const Duration(milliseconds: 100));
        debugPrint('Memory optimization completed');
      } catch (e) {
        debugPrint('Memory optimization failed');
      }
    }
  }

  // ============================= دوال التصدير إلى إكسل =============================
  Future<void> _exportToExcel() async {
    try {
      setState(() {
        isExcelExporting = true;
        excelExportMessage = 'جاري جمع كل البيانات...';
        excelExportProgress = 0.0;
      });

      // إعلام فوري للمستخدم أن العملية بدأت
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'بدأ تصدير الإكسل (قد يستغرق وقتاً حسب عدد المستخدمين)...')),
        );
      }

      await _optimizeMemory();

      // تخزين الخرائط المسطحة مؤقتاً + تتبع جميع المفاتيح
      final List<Map<String, dynamic>> flattenedUsers = [];
      final Set<String> allKeys = {};

      int currentPage = 1;
      const int pageSize = 300;
      int totalProcessed = 0;
      int? totalCount;

      // دوال مساعدة للتسطيح
      Map<String, dynamic> flatten(dynamic value, [String prefix = '']) {
        final Map<String, dynamic> out = {};
        if (value is Map) {
          value.forEach((k, v) {
            final newKey = prefix.isEmpty ? '$k' : '$prefix.$k';
            out.addAll(flatten(v, newKey));
          });
        } else if (value is List) {
          for (var i = 0; i < value.length; i++) {
            final newKey = prefix.isEmpty ? '[$i]' : '$prefix[$i]';
            out.addAll(flatten(value[i], newKey));
          }
        } else {
          out[prefix] = value;
        }
        return out;
      }

      // إضافة عداد لفشل الصفحات المتتالي لتفادي حلقة لا نهائية
      int consecutiveFailures = 0;
      const int maxConsecutiveFailures = 3;
      while (true) {
        Map<String, dynamic> result;
        try {
          result = await _retryOperation(() async {
            return await ApiService.instance.get(
                '/customers?pageSize=$pageSize&pageNumber=$currentPage&sortCriteria.property=self.displayValue&sortCriteria.direction=asc');
          }, maxAttempts: 5);
        } catch (e) {
          consecutiveFailures++;
          if (consecutiveFailures >= maxConsecutiveFailures) {
            throw Exception(
                'توقف التصدير بعد فشل جلب $consecutiveFailures صفحات متتالية (آخر صفحة: $currentPage) - السبب');
          } else {
            setState(() {
              excelExportMessage =
                  'إعادة المحاولة بعد فشل الصفحة $currentPage (محاولة $consecutiveFailures)';
            });
            await Future.delayed(Duration(seconds: 1 * consecutiveFailures));
            continue; // أعد المحاولة لنفس الصفحة
          }
        }

        if (result['success'] != true) {
          consecutiveFailures++;
          if (consecutiveFailures >= maxConsecutiveFailures) {
            throw Exception(
                'فشل جلب البيانات في الصفحة $currentPage عدة مرات متتالية');
          } else {
            setState(() {
              excelExportMessage =
                  'فشل مؤقت في الصفحة $currentPage، إعادة المحاولة ($consecutiveFailures/$maxConsecutiveFailures)';
            });
            await Future.delayed(Duration(seconds: 1 * consecutiveFailures));
            continue;
          }
        } else {
          consecutiveFailures = 0; // نجاح، أعد التعيين
        }

        final data = result['data'];
        if (data is! Map) {
          throw Exception('تنسيق غير متوقع للبيانات في الصفحة $currentPage');
        }
        totalCount ??=
            (data['totalCount'] is int) ? data['totalCount'] as int : null;
        final users = data['items'] is List ? data['items'] as List : const [];
        if (users.isEmpty) {
          // لا توجد صفحات أخرى
          break;
        }

        for (final user in users) {
          final flat = flatten(user);
          flat.removeWhere((k, v) => v == null); // إزالة null
          flattenedUsers.add(flat);
          allKeys.addAll(flat.keys);
          totalProcessed++;
        }

        if (totalCount != null) {
          setState(() {
            final denom = (totalCount ?? 1);
            excelExportProgress = denom <= 0 ? 0.0 : totalProcessed / denom;
            excelExportMessage =
                'تم جمع $totalProcessed مستخدم (تهيئة الأعمدة)';
          });
        } else {
          setState(() {
            excelExportMessage =
                'تم جمع $totalProcessed مستخدم (لم يتم استلام العدد الكلي بعد)';
          });
        }

        currentPage++;
        if (totalProcessed % 900 == 0) {
          await _optimizeMemory();
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      if (flattenedUsers.isEmpty) {
        throw Exception('لا توجد بيانات لتصديرها');
      }

      // ترتيب المفاتيح: أولاً مجموعة مفضلة ثم البقية أبجدياً
      final preferredOrder = <String>[
        'self.id',
        'self.displayValue',
        'primaryContact.mobile',
        'primaryContact.phone',
        'primaryContact.email',
        'zone.id',
        'zone.displayValue',
        'subscription.id',
        'subscription.status',
        'subscription.plan',
        'status',
        'address.full',
        'address.city',
      ];
      final orderedKeys = <String>[];
      for (final k in preferredOrder) {
        if (allKeys.contains(k)) orderedKeys.add(k);
      }
      final remaining = allKeys.difference(orderedKeys.toSet()).toList()
        ..sort();
      orderedKeys.addAll(remaining);

      // ترجمة عناوين معروفة
      final Map<String, String> headerTranslations = {
        'self.id': 'ID',
        'self.displayValue': 'اسم المستخدم',
        'primaryContact.mobile': 'رقم الهاتف',
        'primaryContact.phone': 'هاتف إضافي',
        'primaryContact.email': 'البريد الإلكتروني',
        'zone.id': 'معرّف المنطقة',
        'zone.displayValue': 'المنطقة',
        'subscription.id': 'معرّف الاشتراك',
        'subscription.status': 'حالة الاشتراك',
        'subscription.plan': 'الباقة',
        'status': 'الحالة',
        'address.full': 'العنوان الكامل',
        'address.city': 'المدينة',
      };

      final excel = ex.Excel.createExcel();
      final sheet = excel['المستخدمون'];

      // صف العناوين
      sheet.appendRow([
        ex.TextCellValue('N'),
        ...orderedKeys.map((k) => ex.TextCellValue(headerTranslations[k] ?? k)),
      ]);

      // كتابة الصفوف
      int rowIndex = 0;
      for (final flat in flattenedUsers) {
        rowIndex++;
        final cells = <ex.CellValue>[ex.IntCellValue(rowIndex)];
        for (final k in orderedKeys) {
          final v = flat[k];
          if (v is num) {
            cells.add(ex.TextCellValue(v.toString()));
          } else if (v is bool) {
            cells.add(ex.TextCellValue(v ? 'true' : 'false'));
          } else {
            cells.add(ex.TextCellValue(v?.toString() ?? ''));
          }
        }
        sheet.appendRow(cells);
        if (rowIndex % 800 == 0) {
          setState(() {
            final denom = (totalCount ?? 1);
            excelExportProgress =
                totalCount == null || denom == 0 ? 0.0 : rowIndex / denom;
            excelExportMessage =
                'تم إنشاء $rowIndex صف من ${totalCount ?? '?'}';
          });
          await Future.delayed(const Duration(milliseconds: 80));
        }
      }

      // حفظ الملف
      Directory? baseDir;
      try {
        if (Platform.isAndroid || Platform.isIOS) {
          baseDir = await getApplicationDocumentsDirectory();
        } else {
          try {
            baseDir = await getDownloadsDirectory();
          } catch (_) {
            baseDir = await getApplicationDocumentsDirectory();
          }
        }
      } catch (e) {
        baseDir = await getApplicationDocumentsDirectory();
      }

      final exportDir =
          Directory('${baseDir!.path}${Platform.pathSeparator}ftth_exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final filePath =
          '${exportDir.path}${Platform.pathSeparator}users_export_full_$timestamp.xlsx';
      List<int>? bytes;
      try {
        bytes = excel.encode();
      } catch (e) {
        throw Exception(
            'فشل ترميز ملف الإكسل (ربما الحجم كبير جداً أو عمود غير مدعوم)');
      }
      File file;
      try {
        file = File(filePath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes!);
      } catch (e) {
        throw Exception('فشل حفظ الملف على القرص');
      }

      setState(() {
        excelExportProgress = 1.0;
        excelExportMessage = 'تم إنشاء الملف الكامل: $filePath';
      });

      Future.delayed(const Duration(milliseconds: 500), () {
        OpenFilex.open(file.path);
      });
    } catch (e, st) {
      // في حالة الفشل: جرّب أولاً توليد ملف مبسط أو CSV مرة واحدة
      setState(() {
        excelExportMessage = 'فشل التصدير';
      });
      debugPrint('Export Excel error');
      debugPrint('Stack: $st');
      if (!_excelFallbackTried) {
        _excelFallbackTried = true;
        debugPrint('Trying simplified / CSV fallback after Excel failure...');
        // محاولة fallback مبسط (أعمدة أساسية فقط) ثم CSV إذا لزم
        try {
          await _exportToExcelSimplified();
          return; // نجاح المبسط
        } catch (e2, st2) {
          debugPrint('Simplified Excel fallback failed: $e2');
          debugPrint('Stack: $st2');
          try {
            await _exportToCSVBasic();
            return;
          } catch (e3, st3) {
            debugPrint('CSV fallback also failed: $e3');
            debugPrint('Stack: $st3');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('فشل تصدير البيانات')),
              );
            }
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التصدير')),
        );
      }
    } finally {
      setState(() {
        isExcelExporting = false;
      });
      await _optimizeMemory();
    }
  }

  // نسخة مبسطة: أعمدة محددة فقط + صفوف بالتدريج لتقليل الذاكرة
  Future<void> _exportToExcelSimplified() async {
    setState(() {
      isExcelExporting = true;
      excelExportMessage = 'محاولة إنشاء نسخة مبسطة...';
      excelExportProgress = 0.0;
    });
    await _optimizeMemory();
    final preferred = <String>[
      'self.id',
      'self.displayValue',
      'primaryContact.mobile',
      'zone.displayValue',
      'subscription.status',
      'status',
    ];
    final translations = <String, String>{
      'self.id': 'ID',
      'self.displayValue': 'اسم المستخدم',
      'primaryContact.mobile': 'رقم الهاتف',
      'zone.displayValue': 'المنطقة',
      'subscription.status': 'حالة الاشتراك',
      'status': 'الحالة'
    };
    final excel = ex.Excel.createExcel();
    final sheet = excel['المستخدمون'];
    sheet.appendRow([
      ex.TextCellValue('N'),
      ...preferred.map((k) => ex.TextCellValue(translations[k] ?? k)),
    ]);
    int page = 1;
    int totalProcessed = 0;
    int? totalCount;
    while (true) {
      Map<String, dynamic> result;
      try {
        result = await _retryOperation(() async {
          return await ApiService.instance.get(
              '/customers?pageSize=300&pageNumber=$page&sortCriteria.property=self.displayValue&sortCriteria.direction=asc');
        }, maxAttempts: 4);
      } catch (e) {
        if (page == 1) {
          throw Exception('فشل جلب الصفحة الأولى في النسخة المبسطة');
        }
        break; // صفحات لاحقة فقط
      }
      if (result['success'] != true) break;
      final data = result['data'];
      if (data is! Map) break;
      totalCount ??= data['totalCount'] as int?;
      final users = data['items'] is List ? data['items'] as List : const [];
      debugPrint('[SIMPLE-EXPORT] page=$page items=${users.length}');
      if (users.isEmpty) break;
      for (final u in users) {
        totalProcessed++;
        final row = <ex.CellValue>[ex.IntCellValue(totalProcessed)];
        for (final k in preferred) {
          dynamic v;
          switch (k) {
            case 'self.id':
              v = u['self']?['id'];
              break;
            case 'self.displayValue':
              v = u['self']?['displayValue'];
              break;
            case 'primaryContact.mobile':
              v = u['primaryContact']?['mobile'];
              break;
            case 'zone.displayValue':
              v = u['zone']?['displayValue'];
              break;
            case 'subscription.status':
              v = u['subscription']?['status'];
              break;
            case 'status':
              v = u['status'];
              break;
          }
          row.add(ex.TextCellValue(v?.toString() ?? ''));
        }
        sheet.appendRow(row);
        if (totalProcessed % 500 == 0) {
          setState(() {
            final denom = (totalCount ?? (totalProcessed + 1));
            excelExportProgress = denom == 0 ? 0 : totalProcessed / denom;
            excelExportMessage = 'مبسّط: تم معالجة $totalProcessed';
          });
          await Future.delayed(const Duration(milliseconds: 60));
        }
      }
      page++;
      if (totalProcessed % 1200 == 0) await _optimizeMemory();
    }
    if (totalProcessed == 0) {
      throw Exception('النسخة المبسطة: لم يتم جلب أي مستخدم (0 صف).');
    }
    // حفظ المبسط
    Directory baseDir;
    try {
      baseDir = (Platform.isAndroid || Platform.isIOS)
          ? await getApplicationDocumentsDirectory()
          : (await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory());
    } catch (_) {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final dir =
        Directory('${baseDir.path}${Platform.pathSeparator}ftth_exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path =
        '${dir.path}${Platform.pathSeparator}users_export_simple_$ts.xlsx';
    List<int>? bytes;
    try {
      bytes = excel.encode();
    } catch (e) {
      throw Exception('فشل ترميز النسخة المبسطة');
    }
    try {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!);
    } catch (e) {
      throw Exception('فشل حفظ النسخة المبسطة');
    }
    setState(() {
      excelExportProgress = 1.0;
      excelExportMessage = 'تم إنشاء نسخة مبسطة: $path';
    });
    Future.delayed(
        const Duration(milliseconds: 500), () => OpenFilex.open(path));
  }

  // تصدير CSV أساسي (أخف)
  Future<void> _exportToCSVBasic() async {
    setState(() {
      isExcelExporting = true;
      excelExportMessage = 'محاولة إنشاء CSV بديل...';
      excelExportProgress = 0.0;
    });
    final preferred = <String>[
      'self.id',
      'self.displayValue',
      'primaryContact.mobile',
      'zone.displayValue',
      'subscription.status',
      'status'
    ];
    final translations = <String, String>{
      'self.id': 'ID',
      'self.displayValue': 'اسم المستخدم',
      'primaryContact.mobile': 'رقم الهاتف',
      'zone.displayValue': 'المنطقة',
      'subscription.status': 'حالة الاشتراك',
      'status': 'الحالة'
    };
    final buffer = StringBuffer();
    buffer.writeln(
        ['N', ...preferred.map((k) => translations[k] ?? k)].join(','));
    int page = 1;
    int totalProcessed = 0;
    int? totalCount;
    while (true) {
      Map<String, dynamic> result;
      try {
        result = await _retryOperation(() async {
          return await ApiService.instance.get(
              '/customers?pageSize=400&pageNumber=$page&sortCriteria.property=self.displayValue&sortCriteria.direction=asc');
        }, maxAttempts: 4);
      } catch (_) {
        break;
      }
      if (result['success'] != true) break;
      final data = result['data'];
      if (data is! Map) break;
      totalCount ??= data['totalCount'] as int?;
      final users = data['items'] is List ? data['items'] as List : const [];
      debugPrint('[CSV-EXPORT] page=$page items=${users.length}');
      if (users.isEmpty) break;
      for (final u in users) {
        totalProcessed++;
        final rowValues = <String>[totalProcessed.toString()];
        for (final k in preferred) {
          dynamic v;
          switch (k) {
            case 'self.id':
              v = u['self']?['id'];
              break;
            case 'self.displayValue':
              v = u['self']?['displayValue'];
              break;
            case 'primaryContact.mobile':
              v = u['primaryContact']?['mobile'];
              break;
            case 'zone.displayValue':
              v = u['zone']?['displayValue'];
              break;
            case 'subscription.status':
              v = u['subscription']?['status'];
              break;
            case 'status':
              v = u['status'];
              break;
          }
          final s = (v?.toString() ?? '').replaceAll('"', '""');
          // لف القيم التي تحتوي فواصل أو أسطر
          if (s.contains(',') || s.contains('\n')) {
            rowValues.add('"$s"');
          } else {
            rowValues.add(s);
          }
        }
        buffer.writeln(rowValues.join(','));
        if (totalProcessed % 800 == 0) {
          setState(() {
            final denom = (totalCount ?? (totalProcessed + 1));
            excelExportProgress = denom == 0 ? 0 : totalProcessed / denom;
            excelExportMessage = 'CSV: تمت معالجة $totalProcessed';
          });
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
      page++;
      if (totalProcessed % 1600 == 0) await _optimizeMemory();
    }
    if (totalProcessed == 0) {
      throw Exception('CSV: لم يتم جلب أي مستخدم (0 صف).');
    }
    Directory baseDir;
    try {
      baseDir = (Platform.isAndroid || Platform.isIOS)
          ? await getApplicationDocumentsDirectory()
          : (await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory());
    } catch (_) {
      baseDir = await getApplicationDocumentsDirectory();
    }
    final dir =
        Directory('${baseDir.path}${Platform.pathSeparator}ftth_exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path =
        '${dir.path}${Platform.pathSeparator}users_export_basic_$ts.csv';
    try {
      File(path)
        ..createSync(recursive: true)
        ..writeAsStringSync(buffer.toString(), encoding: utf8);
    } catch (e) {
      throw Exception('فشل حفظ CSV');
    }
    setState(() {
      excelExportProgress = 1.0;
      excelExportMessage = 'تم إنشاء CSV بديل: $path';
    });
    Future.delayed(
        const Duration(milliseconds: 400), () => OpenFilex.open(path));
  }

  // حقل لإدخال كلمة المرور inline
  final TextEditingController _exportPasswordController =
      TextEditingController();
  bool askingPassword = false;
  String? _passwordError;
  bool _showPassword = false; // التحكم في إظهار/إخفاء كلمة المرور

  Future<void> _onMainExportPressed() async {
    if (isExcelExporting) return;

    // الخطوة الأولى: إظهار حقل كلمة المرور إذا لم يكن ظاهر
    if (!askingPassword) {
      setState(() {
        askingPassword = true;
        _passwordError = null;
      });
      return;
    }

    // جلب كلمة المرور المحفوظة (أو الافتراضية إذا لم تُحفظ)
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

    // نجاح التحقق - تصدير مباشر إلى Excel
    setState(() {
      askingPassword = false;
      _passwordError = null;
      _exportPasswordController.clear();
    });
    _exportToExcel();
  }

  // ============================================================================
  // دوال التنقل والتحكم في الصفحات
  // ============================================================================

  /// الانتقال للصفحة التالية
  void _nextPage() {
    if ((currentPage * pageSize) < totalUsers) {
      setState(() {
        currentPage++;
      });
      _fetchUsers();
    }
  }

  /// الانتقال للصفحة السابقة
  void _previousPage() {
    if (currentPage > 1) {
      setState(() {
        currentPage--;
      });
      _fetchUsers();
    }
  }

  /// إعادة تعيين جميع المرشحات والبحوث
  void _resetFilters() {
    setState(() {
      selectedZoneId = "";
      searchName = "";
      searchPhone = "";
      zoneSearchQuery = "";
      currentPage = 1;
      // إعادة تعيين تصفية المناطق
      filteredZones
        ..clear()
        ..addAll(zones);
    });
    // مسح محتوى الحقول
    _nameController.clear();
    _phoneController.clear();
    _zoneSearchController.clear();
    _fetchUsers();
  }
  // ============================================================================
  // دوال بناء عناصر الواجهة
  // ============================================================================

  /// عنصر واجهة لتقدم تصدير الاكسل
  Widget _buildExcelExportProgress() {
    if (!isExcelExporting) return const SizedBox();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade50, Colors.green.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.green.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.table_view, color: Colors.green.shade700, size: 24),
              const SizedBox(width: 12),
              Text(
                'جاري إنشاء ملف إكسل...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            excelExportMessage,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: LinearProgressIndicator(
              value: excelExportProgress,
              backgroundColor: Colors.grey.shade300,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(excelExportProgress * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterFields() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.search, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              const Text(
                'خيارات البحث والتصفية',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16.0),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'بحث بالاسم',
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) => searchName = value,
          ),
          const SizedBox(height: 12.0),
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: 'بحث برقم الهاتف',
              prefixIcon: const Icon(Icons.phone),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            keyboardType: TextInputType.phone,
            onChanged: (value) => searchPhone = value,
          ),
          const SizedBox(height: 12.0),
          // حقل بحث للمناطق
          TextField(
            controller: _zoneSearchController,
            decoration: InputDecoration(
              labelText: 'بحث بالمنطقة (اسم أو رقم)',
              prefixIcon: const Icon(Icons.location_searching),
              suffixIcon: zoneSearchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          zoneSearchQuery = '';
                          _zoneSearchController.clear();
                          filteredZones
                            ..clear()
                            ..addAll(zones);
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: (value) {
              setState(() {
                zoneSearchQuery = value.trim();
                if (zoneSearchQuery.isEmpty) {
                  filteredZones
                    ..clear()
                    ..addAll(zones);
                } else {
                  final q = zoneSearchQuery.toLowerCase();
                  filteredZones
                    ..clear()
                    ..addAll(zones.where((z) {
                      final name =
                          z['displayValue']?.toString().toLowerCase() ?? '';
                      final id = z['id']?.toString().toLowerCase() ?? '';
                      return name.contains(q) || id.contains(q);
                    }));
                }
              });
            },
          ),
          const SizedBox(height: 12.0),
          DropdownButtonFormField<String>(
            initialValue: (selectedZoneId.isEmpty ||
                    !filteredZones
                        .any((z) => z['id']?.toString() == selectedZoneId))
                ? ""
                : selectedZoneId,
            items: [
              const DropdownMenuItem<String>(
                value: "",
                child: Text('الكل'),
              ),
              ...filteredZones.map<DropdownMenuItem<String>>((zone) {
                final zoneId = zone['id']?.toString();
                final displayValue =
                    zone['displayValue']?.toString() ?? 'غير معروف';
                return DropdownMenuItem<String>(
                  value: zoneId,
                  child: Text(displayValue),
                );
              }),
            ],
            onChanged: (value) {
              setState(() => selectedZoneId = value ?? "");
            },
            decoration: InputDecoration(
              labelText: 'المنطقة',
              prefixIcon: const Icon(Icons.location_on),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            menuMaxHeight: 300,
          ),
          const SizedBox(height: 16.0),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              onPressed: () {
                setState(() {
                  currentPage = 1;
                  showFilter = false;
                });
                _fetchUsers();
              },
              icon: const Icon(Icons.search),
              label: const Text('تطبيق التصفية'),
            ),
          ),
          const SizedBox(height: 8.0),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              onPressed: _resetFilters,
              icon: const Icon(Icons.clear_all),
              label: const Text('إلغاء التصفية'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalUsersCount() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isWide = w > 600;
        final double padH = isWide ? 20 : 14;
        final double padV = isWide ? 14 : 10;
        final double iconSize = isWide ? 22 : 18;
        final double fontSize = isWide ? 16 : 13.5;
        return Container(
          padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
          margin:
              EdgeInsets.symmetric(horizontal: isWide ? 16 : 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.blue.shade400],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(10.0),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.25),
                spreadRadius: 0.5,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people, color: Colors.white, size: iconSize),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'إجمالي: $totalUsers',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsersList() {
    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        itemCount: allUsers.length,
        itemBuilder: (context, index) {
          final user = allUsers[index];
          final userName =
              user['self']?['displayValue']?.toString() ?? 'غير معروف';
          final userPhone =
              user['primaryContact']?['mobile']?.toString() ?? 'غير متوفر';
          final userId = user['self']?['id']?.toString() ?? 'غير متوفر';

          return Card(
            margin: const EdgeInsets.only(bottom: 12.0),
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12.0),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserDetailsPage(
                      authToken: widget.authToken,
                      userId: userId,
                      userName: userName,
                      userPhone: userPhone,
                      activatedBy: widget.activatedBy,
                      hasServerSavePermission: widget.hasServerSavePermission,
                      hasWhatsAppPermission: widget.hasWhatsAppPermission,
                      isAdminFlag: widget.isAdminFlag,
                      importantFtthApiPermissions:
                          widget.importantFtthApiPermissions,
                      // تمرير حقول إضافية (ليست متاحة هنا حالياً إلا إن تم توسيع UsersPage لاحقاً)
                      // إبقاؤها null آمن لأن الحقول اختيارية في UserDetailsPage
                      userRoleHeader: '0',
                      clientAppHeader: '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Icon(
                            Icons.person,
                            color: Colors.blue.shade700,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SelectableText(
                            userName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.phone,
                          color: Colors.green.shade600,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        SelectableText(
                          userPhone,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.tag,
                          color: Colors.orange.shade600,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        SelectableText(
                          'ID: $userId',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.grey.shade400,
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = (totalUsers / pageSize).ceil();
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isWide = w > 600;
        final double padAll = isWide ? 12 : 8; // تصغير الحواف العامة
        final double gap = isWide ? 10 : 6; // تقليل المسافات
        final double btnHPad = isWide ? 10 : 8; // عرض داخلي أصغر للأزرار
        final double btnVPad = isWide ? 6 : 4; // ارتفاع داخلي أصغر للأزرار
        final double fontSize = isWide ? 12 : 11; // حجم نص ثانوي
        final double pageNumberFont = isWide ? 18 : 16; // رقم الصفحة أكبر
        final double pageSizeFont = isWide ? 14 : 13; // نص العدد أكبر

        final dropdown = Container(
          padding:
              EdgeInsets.symmetric(horizontal: isWide ? 10 : 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: DropdownButton<int>(
            value: pageSize,
            underline: const SizedBox(),
            isDense: true,
            iconSize: 18,
            style: TextStyle(
                fontSize: pageSizeFont,
                color: Colors.black87,
                fontWeight: FontWeight.w600),
            items: const [
              DropdownMenuItem(value: 10, child: Text('10')),
              DropdownMenuItem(value: 20, child: Text('20')),
              DropdownMenuItem(value: 50, child: Text('50')),
              DropdownMenuItem(value: 100, child: Text('100')),
            ],
            onChanged: (newSize) {
              if (newSize != null) {
                setState(() {
                  pageSize = newSize;
                  currentPage = 1;
                });
                _fetchUsers();
              }
            },
          ),
        );

        final pageInfo = Text(
          'صفحة $currentPage / $totalPages',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: fontSize,
            color: Colors.grey.shade700,
          ),
        );

        final navButtons = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    currentPage > 1 ? Colors.blue : Colors.grey.shade300,
                foregroundColor:
                    currentPage > 1 ? Colors.white : Colors.grey.shade600,
                padding: EdgeInsets.symmetric(
                    horizontal: btnHPad, vertical: btnVPad),
                minimumSize: const Size(40, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              onPressed: currentPage > 1 ? _previousPage : null,
              child: const Icon(Icons.arrow_back, size: 18),
            ),
            SizedBox(width: gap),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 18 : 14, vertical: isWide ? 10 : 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Text('$currentPage',
                  style: TextStyle(
                      fontSize: pageNumberFont,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            SizedBox(width: gap),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: (currentPage * pageSize) < totalUsers
                    ? Colors.blue
                    : Colors.grey.shade300,
                foregroundColor: (currentPage * pageSize) < totalUsers
                    ? Colors.white
                    : Colors.grey.shade600,
                padding: EdgeInsets.symmetric(
                    horizontal: btnHPad, vertical: btnVPad),
                minimumSize: const Size(40, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              onPressed:
                  (currentPage * pageSize) < totalUsers ? _nextPage : null,
              child: const Icon(Icons.arrow_forward, size: 18),
            ),
          ],
        );

        return Container(
          padding: EdgeInsets.all(padAll),
          margin:
              EdgeInsets.symmetric(horizontal: isWide ? 16 : 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.15),
                blurRadius: 4,
                spreadRadius: 0.5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isWide
              ? Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [
                          const Icon(Icons.view_list,
                              color: Colors.blue, size: 18),
                          const SizedBox(width: 6),
                          Text('عدد في الصفحة',
                              style: TextStyle(
                                  fontSize: pageSizeFont,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          dropdown
                        ]),
                        pageInfo,
                      ],
                    ),
                    SizedBox(height: gap),
                    navButtons,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.view_list,
                            color: Colors.blue, size: 16),
                        const SizedBox(width: 4),
                        Text('عدد:',
                            style: TextStyle(
                                fontSize: pageSizeFont,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(width: 6),
                        dropdown,
                        const Spacer(),
                        pageInfo,
                      ],
                    ),
                    SizedBox(height: gap),
                    navButtons,
                  ],
                ),
        );
      },
    );
  }
  //////////////////////////////////////////////////////////////////////////////
  // الجزء الرابع: بناء الواجهة الرئيسية
  // ////////////////////////////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    // تحديد ألوان التدرج للـ AppBar
    final gradientColors = [Colors.blue.shade700, Colors.blue.shade500];

    // تحديد لون النص والأيقونات بطريقة ذكية
    final smartTextColor =
        SmartTextColor.getAppBarTextColorWithGradient(context, gradientColors);
    final smartIconColor = smartTextColor;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        bottom: askingPassword
            ? PreferredSize(
                preferredSize: const Size.fromHeight(68),
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
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _exportPasswordController,
                          obscureText: !_showPassword,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'أدخل كلمة المرور',
                            errorText: _passwordError,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: Colors.blue.shade200,
                              ),
                            ),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip:
                                  _showPassword ? 'إخفاء الرمز' : 'إظهار الرمز',
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(() {
                                _showPassword = !_showPassword;
                              }),
                            ),
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
                  ),
                ),
              )
            : null,
        title: Row(
          children: [
            Icon(Icons.people, color: smartIconColor, size: 26),
            const SizedBox(width: 8),
            Text(
              'قائمة المستخدمين',
              style: SmartTextColor.getSmartTextStyle(
                context: context,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                gradientColors: gradientColors,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: smartIconColor, size: 26),
        elevation: 4,
        actions: [
          // زر التصفية في الشريط العلوي
          IconButton(
            icon: Icon(
              showFilter ? Icons.filter_alt_off : Icons.filter_alt,
              color: smartIconColor,
              size: 26,
            ),
            tooltip: showFilter ? 'إخفاء التصفية' : 'إظهار التصفية',
            onPressed: () => setState(() => showFilter = !showFilter),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: smartIconColor, size: 26),
            tooltip: 'إعادة تحميل الصفحة',
            onPressed: () async {
              setState(() => isLoading = true);
              await _fetchUsers();
            },
          ),
          if (!isExcelExporting &&
              !askingPassword &&
              PermissionManager.instance.canExport('users'))
            IconButton(
              tooltip: 'تصدير',
              icon: Icon(Icons.cloud_upload, color: smartIconColor, size: 26),
              onPressed: _onMainExportPressed,
            ),
          if (askingPassword && !isExcelExporting)
            IconButton(
              tooltip: 'إخفاء',
              icon:
                  Icon(Icons.close_fullscreen, color: smartIconColor, size: 24),
              onPressed: () => setState(() {
                askingPassword = false;
                _passwordError = null;
                _exportPasswordController.clear();
              }),
            ),
          if (isExcelExporting)
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
          const SizedBox(width: 8),
        ],
      ),
      backgroundColor: Colors.grey.shade50,
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'جاري تحميل البيانات...',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            )
          : errorMessage.isNotEmpty
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(24.0),
                    margin: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red.shade600,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          "خطأ: $errorMessage",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              errorMessage = "";
                              isLoading = true;
                            });
                            _fetchUsers();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildExcelExportProgress(),
                    if (showFilter) _buildFilterFields(),
                    _buildTotalUsersCount(),
                    _buildUsersList(),
                    _buildPagination(),
                  ],
                ),
    );
  }
}
