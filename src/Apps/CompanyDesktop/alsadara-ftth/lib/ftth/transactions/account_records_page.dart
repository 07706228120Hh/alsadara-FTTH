/// اسم الصفحة: سجلات الحسابات
/// وصف الصفحة: صفحة عرض سجلات الحسابات والبيانات التاريخية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../../services/google_sheets_service.dart';
import 'package:intl/intl.dart';
import 'account_stats_page.dart';
import '../../models/filter_criteria.dart';

class AccountRecordsPage extends StatefulWidget {
  final String authToken;
  final String activatedBy;
  final Map<String, bool>? permissions; // تمرير صلاحيات من الصفحة الرئيسية
  // معلومات النظام الأول (Google Sheets)
  final String? firstSystemUsername;
  final String? firstSystemPermissions;
  final String? firstSystemDepartment;
  final String? firstSystemCenter;

  const AccountRecordsPage({
    super.key,
    required this.authToken,
    required this.activatedBy,
    this.permissions,
    this.firstSystemUsername,
    this.firstSystemPermissions,
    this.firstSystemDepartment,
    this.firstSystemCenter,
  });

  @override
  State<AccountRecordsPage> createState() => _AccountRecordsPageState();
}

class _AccountRecordsPageState extends State<AccountRecordsPage> {
  List<Map<String, dynamic>> allRecords = [];
  List<Map<String, dynamic>> filteredRecords = [];
  // تحكم في دمج الأسماء المتطابقة بدون حساسية حالة الأحرف (افتراضي: معطل بناءً على طلب المستخدم)
  bool mergeSimilarAccounts = false;
  bool isLoading = false;
  String searchQuery = '';
  String selectedOperationFilter = 'الكل'; // نوع العملية
  String selectedZoneFilter = 'الكل'; // الزون
  String selectedExecutorFilter = 'الكل'; // منفذ العملية
  String selectedSubscriptionTypeFilter = 'الكل'; // نوع الاشتراك
  String selectedPaymentTypeFilter = 'الكل'; // نوع الدفع (نقد / آجل)
  String selectedPrintStatusFilter = 'الكل'; // حالة الطباعة
  String selectedWhatsAppStatusFilter = 'الكل'; // حالة الواتساب
  String selectedReprintFilter = 'الكل'; // تصفية تكرار الطبع
  bool showDuplicatesOnly = false; // عرض السجلات المكررة فقط
  bool hideDuplicates = true; // إخفاء السجلات المكررة (الافتراضي: مفعل)
  DateTime? fromDate;
  DateTime? toDate;
  TimeOfDay? fromTime; // تصفية من وقت محدد في يوم البداية فقط
  TimeOfDay? toTime; // تصفية إلى وقت محدد في يوم النهاية
  bool showFilters = false; // للتحكم في إظهار/إخفاء التصفية

  // تصفية سريعة بالتاريخ: 'today_yesterday' (افتراضي), 'today', 'yesterday', 'all'
  String _quickDateFilter = 'today_yesterday';

  // صلاحيات
  bool isAdmin = false; // يتم تحديده حسب اسم المستخدم
  int totalFetchedRecords = 0; // العدد الكامل قبل التقييد
  // أسماء المدراء التلقائية (في حال لم تُمرر صلاحيات مفصلة)
  static const List<String> _fallbackAdminUsernames = ['admin', 'root'];

  final List<String> operationFilterOptions = [
    'الكل',
    'شراء اشتراك جديد',
    'تجديد اشتراك',
  ];

  // قوائم التصفية (ستملأ من البيانات المجلبة)
  List<String> zoneOptions = ['الكل'];
  List<String> executorOptions = ['الكل'];
  List<String> subscriptionTypeOptions = ['الكل']; // خيارات نوع الاشتراك

  @override
  void initState() {
    super.initState();
    _determineAdmin();
    _setInitialDateFilter(); // تعيين الفلتر الافتراضي بدون تطبيق (لأن البيانات لم تُحمّل بعد)
    _loadRecords();
  }

  // تعيين فلتر التاريخ الافتراضي (بدون استدعاء _applyFilters)
  void _setInitialDateFilter() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    fromDate = yesterday;
    toDate = today;
  }

  // الحصول على نص الفلتر السريع
  String _getQuickFilterLabel() {
    switch (_quickDateFilter) {
      case 'today':
        return 'اليوم';
      case 'yesterday':
        return 'أمس';
      case 'today_yesterday':
        return 'اليوم+أمس';
      case 'all':
        return 'الكل';
      default:
        return 'اليوم+أمس';
    }
  }

  // تطبيق فلتر التاريخ السريع - يُعيد تحميل البيانات من الشيت
  void _applyQuickDateFilter() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    switch (_quickDateFilter) {
      case 'today':
        fromDate = today;
        toDate = today;
        break;
      case 'yesterday':
        fromDate = yesterday;
        toDate = yesterday;
        break;
      case 'today_yesterday':
        fromDate = yesterday;
        toDate = today;
        break;
      case 'all':
        fromDate = null;
        toDate = null;
        break;
    }
    // إعادة تحميل البيانات من الشيت مع الفلتر الجديد
    _loadRecords();
  }

  void _determineAdmin() {
    final name = widget.activatedBy.trim();
    // إذا وصلت صلاحيات، استخدم مفتاح مثل 'admin' أو 'is_admin'
    final perms = widget.permissions;
    if (perms != null) {
      isAdmin = (perms['admin'] == true) || (perms['is_admin'] == true);
    }
    // أولوية النظام الأول: النص الحر لصلاحيات النظام الأول قد يحتوي على كلمة مدير
    if (!isAdmin && widget.firstSystemPermissions != null) {
      final fs = widget.firstSystemPermissions!.toLowerCase();
      if (fs.contains('مدير') ||
          fs.contains('admin') ||
          fs.contains('administrator')) {
        isAdmin = true;
      }
    }
    // fallback إذا لم تكن هناك صلاحيات صريحة
    if (!isAdmin) {
      isAdmin = _fallbackAdminUsernames
              .any((a) => a.toLowerCase() == name.toLowerCase()) ||
          name.toLowerCase().contains('admin');
    }
  }

  /// جلب السجلات من Google Sheets وتحديث الحالة
  Future<void> _loadRecords() async {
    setState(() {
      isLoading = true;
    });
    try {
      // جلب السجلات مع تصفية التاريخ من الشيت مباشرة
      final records = await GoogleSheetsService.getRecordsByDateRange(
        fromDate: fromDate,
        toDate: toDate,
      );
      totalFetchedRecords = records.length;
      List<Map<String, dynamic>> processed = records;
      if (mergeSimilarAccounts) {
        processed = _mergeAccountsCaseInsensitive(records);
      }

      // ✅ توحيد مفتاح اسم منفذ العملية: بعض الجداول تستخدم "المُفعِّل" بدل "منفذ العملية"
      // هذا يمنع ظهور الاسم كـ "غير محدد" وبالتالي فشل التنقل وإرسال specificUser خاطئ.
      for (final r in processed) {
        final hasExecutor = r.containsKey('منفذ العملية') &&
            (r['منفذ العملية']?.toString().trim().isNotEmpty ?? false);
        final activator = r['المُفعِّل']?.toString().trim();
        if (!hasExecutor && activator != null && activator.isNotEmpty) {
          r['منفذ العملية'] = activator; // إنشاء الاسم الموحد
        }
        // في حال كان كلاهما موجودين ويختلفان، نعتمد "منفذ العملية" ونُهمل الآخر (لا حاجة لتعديل)
      }

      // تطبيق تصفية الصلاحيات: المدير يرى كل شيء، غير المدير يرى سجلاته فقط
      if (!isAdmin) {
        processed = processed.where((record) {
          final executor =
              record['منفذ العملية']?.toString().trim().toLowerCase() ?? '';
          final activator =
              record['المُفعِّل']?.toString().trim().toLowerCase() ?? '';
          final currentUser = widget.activatedBy.trim().toLowerCase();

          // إظهار السجل إذا كان المستخدم الحالي هو منفذ العملية أو المُفعِّل
          return executor == currentUser || activator == currentUser;
        }).toList();

        debugPrint(
            '🔒 تصفية المستخدم غير المدير: عرض ${processed.length} من أصل $totalFetchedRecords سجل');
      } else {
        debugPrint('👨‍💼 المدير: عرض جميع السجلات (${processed.length} سجل)');
      }

      // ترتيب البيانات من الأحدث إلى الأقدم حسب التاريخ والوقت
      processed.sort((a, b) {
        final dateTimeA = _parseRecordDateTime(a);
        final dateTimeB = _parseRecordDateTime(b);

        // إذا لم يكن هناك تاريخ صالح، ضعه في النهاية
        if (dateTimeA == null && dateTimeB == null) return 0;
        if (dateTimeA == null) return 1;
        if (dateTimeB == null) return -1;

        // ترتيب تنازلي (الأحدث أولاً)
        return dateTimeB.compareTo(dateTimeA);
      });

      allRecords = processed;
      _extractFilterOptions(processed);
      // تطبيق الفلاتر (بما في ذلك إخفاء المكرر الافتراضي)
      _applyFilters();
      if (processed.isNotEmpty) {
        debugPrint('🔑 أول سجل - المفاتيح: ${processed.first.keys}');
      }
    } catch (e) {
      String errorTitle;
      String errorMessage;
      final errStr = e.toString();
      if (errStr.contains('timeout') || errStr.contains('انتهت مهلة')) {
        errorTitle = 'انتهت مهلة الاتصال';
        errorMessage =
            'استغرق تحميل البيانات وقتاً أطول من المتوقع.\nتحقق من سرعة الإنترنت وحاول مرة أخرى.';
      } else if (errStr.contains('permission') ||
          errStr.contains('auth') ||
          errStr.contains('صلاحيات')) {
        errorTitle = 'مشكلة في الصلاحيات';
        errorMessage =
            'لا يمكن الوصول لجدول البيانات.\nتحقق من صلاحيات التطبيق لـ Google Sheets.';
      } else if (errStr.contains('network') ||
          errStr.contains('connection') ||
          errStr.contains('اتصال')) {
        errorTitle = 'مشكلة في الاتصال';
        errorMessage =
            'لا يمكن الاتصال بالإنترنت.\nتحقق من اتصال الإنترنت وحاول مرة أخرى.';
      } else if (errStr.contains('Account') || errStr.contains('صفحة')) {
        errorTitle = 'جدول البيانات غير صحيح';
        errorMessage =
            'لم يتم العثور على صفحة "Account" في جدول البيانات.\nتحقق من إعدادات الجدول.';
      } else if (errStr.contains('تهيئة') ||
          errStr.contains('initialization') ||
          errStr.contains('أثناء التهيئة')) {
        errorTitle = 'خطأ في تهيئة الخدمة';
        errorMessage =
            'فشل في تهيئة الاتصال مع Google Sheets.\nتحقق من إعدادات التطبيق وملف المفاتيح.';
      } else {
        errorTitle = 'خطأ غير متوقع';
        errorMessage =
            'حدث خطأ أثناء تحميل البيانات.\nالتفاصيل: ${errStr.length > 120 ? '${errStr.substring(0, 120)}…' : errStr}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorTitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 6),
                Text(errorMessage, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                const Text('اضغط إعادة المحاولة',
                    style:
                        TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            duration: const Duration(seconds: 10),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: _loadRecords,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// حساب المجموع الإجمالي للمبالغ
  double _calculateTotalAmount() {
    double total = 0.0;
    for (var record in filteredRecords) {
      final priceString = record['سعر الباقة']?.toString() ?? '0';
      final price = double.tryParse(priceString.replaceAll(',', '')) ?? 0.0;
      total += price;
    }
    return total;
  }

  /// تنسيق المبلغ بالفواصل
  String _formatAmount(double amount) {
    final formatter = NumberFormat('#,###.##', 'en');
    return formatter.format(amount);
  }

  /// تنسيق المبلغ بشكل كامل (مع الفواصل للآلاف والملايين)
  String _formatAmountShort(double amount) {
    final formatter = NumberFormat('#,###', 'en_US');
    return formatter.format(amount.round());
  }

  /// توحيد نوع العملية إلى قيم قياسية
  /// - شراء اشتراك جديد
  /// - تجديد اشتراك (يشمل تغيير اشتراك)
  String _normalizeOperationType(String raw) {
    final v = raw.trim();
    final lower = v.toLowerCase();

    // شراء
    if (v.contains('شراء') ||
        lower.contains('purchase') ||
        lower.contains('buy')) {
      return 'شراء اشتراك جديد';
    }

    // تجديد أو تغيير => كلاهما يُحسب كتجديد
    if (v.contains('تجديد') ||
        v.contains('تغيير') ||
        lower.contains('renew') ||
        lower.contains('change')) {
      return 'تجديد اشتراك';
    }
    return v.isEmpty ? 'غير محدد' : v;
  }

  /// حساب إحصائيات عمليات الشراء
  Map<String, dynamic> _calculatePurchaseStats() {
    int count = 0;
    double total = 0.0;

    for (var record in filteredRecords) {
      final operationType =
          _normalizeOperationType(record['نوع العملية']?.toString() ?? '');
      if (operationType == 'شراء اشتراك جديد') {
        count++;
        final priceString = record['سعر الباقة']?.toString() ?? '0';
        final price = double.tryParse(priceString.replaceAll(',', '')) ?? 0.0;
        total += price;
      }
    }

    return {'count': count, 'total': total};
  }

  /// حساب إحصائيات عمليات التجديد
  Map<String, dynamic> _calculateRenewalStats() {
    int count = 0;
    double total = 0.0;

    for (var record in filteredRecords) {
      final operationType =
          _normalizeOperationType(record['نوع العملية']?.toString() ?? '');
      if (operationType == 'تجديد اشتراك') {
        count++;
        final priceString = record['سعر الباقة']?.toString() ?? '0';
        final price = double.tryParse(priceString.replaceAll(',', '')) ?? 0.0;
        total += price;
      }
    }

    return {'count': count, 'total': total};
  }

  // تمت إزالة أداة تنسيق المبلغ هنا؛ التنسيق أصبح ضمن صفحة الإحصائيات الجديدة

  /// دمج السجلات التي يختلف فيها اسم العميل فقط من حيث حالة الأحرف
  /// الهدف: اعتبار (ahmed / AHMED / Ahmed) حساباً واحداً
  /// حالياً: نحتفظ بأول سجل ونُهمل اللاحقة المتطابقة (يمكن لاحقاً تطوير الدمج التجميعي)
  List<Map<String, dynamic>> _mergeAccountsCaseInsensitive(
      List<Map<String, dynamic>> records) {
    final Map<String, Map<String, dynamic>> unique = {};
    final List<Map<String, dynamic>> others = []; // سجلات بلا اسم واضح
    final List<String> replacedVariants =
        []; // لأغراض التشخيص: ما الذي تم استبداله بأي شيء

    for (final r in records) {
      final rawName =
          (r['اسم العميل'] ?? r['Customer Name'] ?? '').toString().trim();
      if (rawName.isEmpty || rawName == 'غير محدد') {
        others.add(r); // لا يمكن التطبيع، الإبقاء كما هو
        continue;
      }
      final key = rawName.toLowerCase();
      if (!unique.containsKey(key)) {
        // نسخة قابلة للتعديل حتى لا نغير الأصل
        final copy = Map<String, dynamic>.from(r);
        // حفظ الاسم الأصلي + الاسم المطبع (للاستخدام المستقبلي إن لزم)
        copy['__normalized_customer_name'] =
            rawName; // يمكن الاستناد عليها لاحقاً
        copy['__merged_count'] = 1;
        unique[key] = copy;
      } else {
        final existing = unique[key]!;
        existing['__merged_count'] = (existing['__merged_count'] ?? 1) + 1;

        final currentName =
            existing['__normalized_customer_name']?.toString() ?? '';
        final newName = rawName;

        bool currentHasEmail = currentName.contains('@');
        bool newHasEmail = newName.contains('@');
        bool currentHasSymbols = _hasNonAlnum(currentName);
        bool newHasSymbols = _hasNonAlnum(newName);

        // اختيار النسخة الأكثر "غنى": بريد أولاً، ثم أكثر رموز، ثم الأطول
        bool shouldReplace = false;
        if (!currentHasEmail && newHasEmail) {
          shouldReplace = true;
        } else if (currentHasEmail == newHasEmail) {
          if (!currentHasSymbols && newHasSymbols) {
            shouldReplace = true;
          } else if (currentHasSymbols == newHasSymbols) {
            if (newName.length > currentName.length) {
              shouldReplace = true;
            }
          }
        }

        if (shouldReplace) {
          replacedVariants
              .add('استبدال "$currentName" بـ "$newName" (مكرر بحروف مختلفة)');
          existing['__normalized_customer_name'] = newName;
          if (existing.containsKey('اسم العميل')) {
            existing['اسم العميل'] = newName;
          } else if (existing.containsKey('Customer Name')) {
            existing['Customer Name'] = newName;
          }
        }
      }
    }

    final merged = [...unique.values, ...others];
    debugPrint('🧩 دمج الأسماء: قبل=${records.length} بعد=${merged.length}');
    if (replacedVariants.isNotEmpty) {
      debugPrint('🔁 تفاصيل الاستبدال (لا تُعرض للمستخدم):');
      for (final line in replacedVariants) {
        debugPrint('   • $line');
      }
    }
    return merged;
  }

  /// فحص إن كان الاسم يحتوي على رموز غير حرفية / رقمية (باستثناء المسافات)
  bool _hasNonAlnum(String s) {
    return RegExp(r'[^\p{L}\p{N} ]', unicode: true).hasMatch(s);
  }

  /// استخراج خيارات التصفية من البيانات المجلبة
  void _extractFilterOptions(List<Map<String, dynamic>> records) {
    Set<String> zones = {};
    // سنستخدم خريطة بدلاً من Set لتفادي التكرار بحالة الأحرف
    final Map<String, String> executorCanon = {};
    Set<String> subscriptionTypes = {};

    for (var record in records) {
      // استخراج الزونات من العمود K (بافتراض أن العنوان يحتوي على "زون" أو "zone")
      record.forEach((key, value) {
        if (key.toLowerCase().contains('zone') ||
            key.toLowerCase().contains('زون')) {
          if (value != null && value.toString().trim().isNotEmpty) {
            zones.add(value.toString().trim());
          }
        }
      });

      // استخراج منفذي العمليات - استخدام الاسم الصحيح للعمود
      final executorValue = record['منفذ العملية']?.toString();
      if (executorValue != null) {
        final trimmed = executorValue.trim();
        if (trimmed.isNotEmpty && trimmed != 'غير محدد') {
          final key = trimmed.toLowerCase();
          // احتفظ بأول شكل مكتوب للاسم
          executorCanon.putIfAbsent(key, () => trimmed);
        }
      }

      // استخراج أنواع الاشتراك من أسماء الباقات
      final packageName = record['اسم الباقة']?.toString();
      if (packageName != null && packageName.trim().isNotEmpty) {
        subscriptionTypes.add(packageName.trim());
      }
    }

    // تحديث الأسماء الموحدة في السجلات نفسها (اختياري لتحسين الاتساق في العرض)
    for (final r in records) {
      final ex = r['منفذ العملية']?.toString();
      if (ex != null) {
        final key = ex.trim().toLowerCase();
        if (executorCanon.containsKey(key)) {
          r['منفذ العملية'] = executorCanon[key];
        }
      }
    }

    setState(() {
      zoneOptions = ['الكل', ...zones.toList()..sort()];
      executorOptions = [
        'الكل',
        ...executorCanon.values.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()))
      ];
      subscriptionTypeOptions = ['الكل', ...subscriptionTypes.toList()..sort()];
    });
  }

  /// تطبيق التصفية على البيانات
  void _applyFilters() {
    setState(() {
      // تطبيع قيمة نوع العملية المختارة إن كانت قديمة 'تغيير اشتراك'
      if (selectedOperationFilter == 'تغيير اشتراك') {
        selectedOperationFilter = 'تجديد اشتراك';
      }
      filteredRecords = allRecords.where((record) {
        // تصفية حسب اسم العميل أو أي نص عام
        bool matchesSearch = searchQuery.isEmpty ||
            record.values.any((value) => value
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase()));

        // تصفية حسب نوع العملية
        final normalizedOp =
            _normalizeOperationType(record['نوع العملية']?.toString() ?? '');
        bool matchesOperation;
        if (selectedOperationFilter == 'الكل') {
          matchesOperation = true;
        } else if (selectedOperationFilter == 'تجديد اشتراك') {
          // كلاهما يعامل كتجديد
          matchesOperation = normalizedOp == 'تجديد اشتراك';
        } else if (selectedOperationFilter == 'شراء اشتراك جديد') {
          matchesOperation = normalizedOp == 'شراء اشتراك جديد';
        } else {
          // تطابق نصي افتراضي لأي قيم أخرى
          matchesOperation = (record['نوع العملية']?.toString() ?? '')
              .contains(selectedOperationFilter);
        }

        // تصفية حسب الزون
        bool matchesZone = selectedZoneFilter == 'الكل' ||
            record.values
                .any((value) => value.toString().contains(selectedZoneFilter));

        // تصفية حسب منفذ العملية
        bool matchesExecutor = true;
        if (selectedExecutorFilter != 'الكل') {
          final recExec =
              record['منفذ العملية']?.toString().trim().toLowerCase() ?? '';
          final selLower = selectedExecutorFilter.trim().toLowerCase();
          matchesExecutor = recExec == selLower;
        }

        // تصفية حسب نوع الاشتراك (اسم الباقة)
        bool matchesSubscriptionType =
            selectedSubscriptionTypeFilter == 'الكل' ||
                record['اسم الباقة']
                        ?.toString()
                        .contains(selectedSubscriptionTypeFilter) ==
                    true;

        // تصفية حسب نوع الدفع
        bool matchesPayment = true;
        if (selectedPaymentTypeFilter != 'الكل') {
          final payNorm = _derivePaymentType(record); // يعيد نقد / آجل أو خام
          if (selectedPaymentTypeFilter == 'نقد') {
            matchesPayment = payNorm == 'نقد';
          } else if (selectedPaymentTypeFilter == 'آجل') {
            matchesPayment = payNorm == 'آجل';
          }
        }

        // تصفية حسب التاريخ/الوقت مع دعم حد أدنى (من وقت) وحد أقصى (إلى وقت)
        bool matchesDate = true;
        if (fromDate != null || toDate != null) {
          final recordDT = _parseRecordDateTime(record);
          if (recordDT == null) {
            matchesDate = false;
          } else {
            DateTime? lowerBound;
            if (fromDate != null) {
              if (fromTime != null) {
                lowerBound = DateTime(fromDate!.year, fromDate!.month,
                    fromDate!.day, fromTime!.hour, fromTime!.minute);
              } else {
                lowerBound =
                    DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
              }
            }
            DateTime? upperBound; // حد علوي شامل
            if (toDate != null) {
              if (toTime != null) {
                // إلى وقت محدد ضمن يوم النهاية (شامل حتى الدقيقة المحددة)
                upperBound = DateTime(
                  toDate!.year,
                  toDate!.month,
                  toDate!.day,
                  toTime!.hour,
                  toTime!.minute,
                  59,
                  999,
                  999,
                );
              } else {
                // بدون وقت => نهاية اليوم بشكل شامل
                upperBound = DateTime(toDate!.year, toDate!.month, toDate!.day,
                    23, 59, 59, 999, 999);
              }
            }

            if (lowerBound != null && recordDT.isBefore(lowerBound)) {
              matchesDate = false;
            }
            if (upperBound != null && recordDT.isAfter(upperBound)) {
              matchesDate = false;
            }
          }
        }

        // تصفية حسب حالة الطباعة
        bool matchesPrintStatus = true;
        if (selectedPrintStatusFilter != 'الكل') {
          final printStatus = _extractFlexibleValue(
            record,
            specificKeys: const [
              'تم الطباعة',
              'Is Printed',
              'حالة الطباعة',
            ],
            containsPatterns: const ['طباعة', 'طباع', 'print', 'printed'],
          );

          if (selectedPrintStatusFilter == 'تم') {
            matchesPrintStatus = _isPrintedStatus(printStatus);
          } else if (selectedPrintStatusFilter == 'لم يتم') {
            matchesPrintStatus = !_isPrintedStatus(printStatus);
          }
        }

        // تصفية حسب حالة الواتساب
        bool matchesWhatsAppStatus = true;
        if (selectedWhatsAppStatusFilter != 'الكل') {
          final whatsappStatus = _extractFlexibleValue(
            record,
            specificKeys: const [
              'تم إرسال الواتساب',
              'WhatsApp Sent',
              'حالة الواتساب',
            ],
            containsPatterns: const ['whats', 'واتس', 'واتساب'],
          );

          if (selectedWhatsAppStatusFilter == 'تم') {
            matchesWhatsAppStatus = _isWhatsAppStatus(whatsappStatus);
          } else if (selectedWhatsAppStatusFilter == 'لم يتم') {
            matchesWhatsAppStatus = !_isWhatsAppStatus(whatsappStatus);
          }
        }

        // تصفية حسب تكرار الطبع
        bool matchesReprintFilter = true;
        if (selectedReprintFilter != 'الكل') {
          // البحث عن قيمة تكرار الطبع في العمود AN (index 39)
          String reprintCount = '';

          // محاولة استخراج القيمة من مفاتيح متعددة
          final possibleKeys = [
            'تكرار الطبع',
            'Print Count',
            'Reprint Count',
            'print_count',
            'reprint_count',
            // العمود AN قد يكون بترتيب معين في البيانات
          ];

          for (final key in possibleKeys) {
            if (record.containsKey(key) &&
                record[key] != null &&
                record[key].toString().trim().isNotEmpty) {
              reprintCount = record[key].toString().trim();
              break;
            }
          }

          // إذا لم نجد بالمفاتيح، نحاول البحث بالأنماط
          if (reprintCount.isEmpty) {
            reprintCount = _extractFlexibleValue(
              record,
              specificKeys: possibleKeys,
              containsPatterns: const [
                'تكرار',
                'reprint',
                'print count',
                'طبع'
              ],
            );
          }

          final count = int.tryParse(reprintCount) ?? 0;

          if (selectedReprintFilter == 'مطبوع أكثر من مرة') {
            matchesReprintFilter = count > 1;
          } else if (selectedReprintFilter == 'مطبوع مرة واحدة') {
            matchesReprintFilter = count == 1;
          } else if (selectedReprintFilter == 'لم يُطبع') {
            matchesReprintFilter = count == 0;
          }
        }

        return matchesSearch &&
            matchesOperation &&
            matchesZone &&
            matchesExecutor &&
            matchesSubscriptionType &&
            matchesPayment &&
            matchesDate &&
            matchesPrintStatus &&
            matchesWhatsAppStatus &&
            matchesReprintFilter;
      }).toList();

      // تطبيق فلتر التكرار إذا كان مفعلاً
      if (showDuplicatesOnly) {
        filteredRecords = _getDuplicateRecords(filteredRecords);
      }

      // تطبيق فلتر إخفاء التكرار إذا كان مفعلاً
      if (hideDuplicates) {
        filteredRecords = _getNonDuplicateRecords(filteredRecords);
      }

      // ترتيب البيانات من الأحدث إلى الأقدم حسب التاريخ والوقت
      filteredRecords.sort((a, b) {
        final dateTimeA = _parseRecordDateTime(a);
        final dateTimeB = _parseRecordDateTime(b);

        // إذا لم يكن هناك تاريخ صالح، ضعه في النهاية
        if (dateTimeA == null && dateTimeB == null) return 0;
        if (dateTimeA == null) return 1;
        if (dateTimeB == null) return -1;

        // ترتيب تنازلي (الأحدث أولاً)
        return dateTimeB.compareTo(dateTimeA);
      });
    });
  }

  /// تطبيق التصفية وإخفاء تبويبة التصفية
  void _applyFiltersAndHide() {
    _applyFilters();
    setState(() {
      showFilters = false;
    });
  }

  /// تبديل فلتر السجلات المكررة
  void _toggleDuplicatesFilter() {
    setState(() {
      showDuplicatesOnly = !showDuplicatesOnly;
    });
    _applyFilters();
  }

  /// الحصول على السجلات المكررة فقط (تطابق بالاسم أو معرف العميل)
  List<Map<String, dynamic>> _getDuplicateRecords(
      List<Map<String, dynamic>> records) {
    // جمع التكرارات حسب اسم العميل
    final nameCount = <String, int>{};
    // جمع التكرارات حسب معرف العميل
    final idCount = <String, int>{};

    for (final record in records) {
      final name = record['اسم العميل']?.toString().trim().toLowerCase() ?? '';
      final id = record['معرف العميل']?.toString().trim() ?? '';

      if (name.isNotEmpty) {
        nameCount[name] = (nameCount[name] ?? 0) + 1;
      }
      if (id.isNotEmpty) {
        idCount[id] = (idCount[id] ?? 0) + 1;
      }
    }

    // الأسماء والمعرفات المكررة (أكثر من مرة)
    final duplicateNames =
        nameCount.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
    final duplicateIds =
        idCount.entries.where((e) => e.value > 1).map((e) => e.key).toSet();

    // إرجاع السجلات التي تنتمي للمكررات
    return records.where((record) {
      final name = record['اسم العميل']?.toString().trim().toLowerCase() ?? '';
      final id = record['معرف العميل']?.toString().trim() ?? '';
      return duplicateNames.contains(name) || duplicateIds.contains(id);
    }).toList();
  }

  /// الحصول على السجلات غير المكررة فقط (إخفاء التكرار)
  List<Map<String, dynamic>> _getNonDuplicateRecords(
      List<Map<String, dynamic>> records) {
    // جمع التكرارات حسب اسم العميل
    final nameCount = <String, int>{};
    // جمع التكرارات حسب معرف العميل
    final idCount = <String, int>{};

    for (final record in records) {
      final name = record['اسم العميل']?.toString().trim().toLowerCase() ?? '';
      final id = record['معرف العميل']?.toString().trim() ?? '';

      if (name.isNotEmpty) {
        nameCount[name] = (nameCount[name] ?? 0) + 1;
      }
      if (id.isNotEmpty) {
        idCount[id] = (idCount[id] ?? 0) + 1;
      }
    }

    // الأسماء والمعرفات المكررة (أكثر من مرة)
    final duplicateNames =
        nameCount.entries.where((e) => e.value > 1).map((e) => e.key).toSet();
    final duplicateIds =
        idCount.entries.where((e) => e.value > 1).map((e) => e.key).toSet();

    // الإبقاء على سجل واحد فقط من كل مجموعة مكررة
    final seenNames = <String>{};
    final seenIds = <String>{};
    final result = <Map<String, dynamic>>[];

    for (final record in records) {
      final name = record['اسم العميل']?.toString().trim().toLowerCase() ?? '';
      final id = record['معرف العميل']?.toString().trim() ?? '';

      // إذا كان السجل غير مكرر، أضفه مباشرة
      final isDuplicateName = duplicateNames.contains(name);
      final isDuplicateId = duplicateIds.contains(id);

      if (!isDuplicateName && !isDuplicateId) {
        // سجل فريد - أضفه
        result.add(record);
      } else {
        // سجل مكرر - أضفه فقط إذا لم يظهر من قبل
        bool alreadySeen = false;
        if (name.isNotEmpty && seenNames.contains(name)) {
          alreadySeen = true;
        }
        if (id.isNotEmpty && seenIds.contains(id)) {
          alreadySeen = true;
        }

        if (!alreadySeen) {
          result.add(record);
          if (name.isNotEmpty) seenNames.add(name);
          if (id.isNotEmpty) seenIds.add(id);
        }
      }
    }

    return result;
  }

  /// إلغاء جميع التصفيات
  void _clearFilters() {
    setState(() {
      searchQuery = '';
      selectedOperationFilter = 'الكل';
      selectedZoneFilter = 'الكل';
      selectedExecutorFilter = 'الكل';
      selectedSubscriptionTypeFilter = 'الكل';
      selectedPaymentTypeFilter = 'الكل';
      selectedPrintStatusFilter = 'الكل';
      selectedWhatsAppStatusFilter = 'الكل';
      selectedReprintFilter = 'الكل';
      fromDate = null;
      toDate = null;
      fromTime = null;
      toTime = null;

      // إعادة ترتيب البيانات من الأحدث إلى الأقدم
      final sortedRecords = List<Map<String, dynamic>>.from(allRecords);
      sortedRecords.sort((a, b) {
        final dateTimeA = _parseRecordDateTime(a);
        final dateTimeB = _parseRecordDateTime(b);

        if (dateTimeA == null && dateTimeB == null) return 0;
        if (dateTimeA == null) return 1;
        if (dateTimeB == null) return -1;

        return dateTimeB.compareTo(dateTimeA);
      });

      filteredRecords = sortedRecords;
    });
  }

  /// تبديل إظهار/إخفاء التصفية
  void _toggleFilters() {
    setState(() {
      showFilters = !showFilters;
    });
  }

  /// هل هناك أي تصفية مفعلة حالياً؟ (لتفعيل/تعطيل زر الإلغاء في الشريط)
  bool _hasActiveFilters() {
    if (searchQuery.trim().isNotEmpty) return true;
    if (selectedOperationFilter != 'الكل') return true;
    if (selectedZoneFilter != 'الكل') return true;
    if (selectedExecutorFilter != 'الكل') return true;
    if (selectedSubscriptionTypeFilter != 'الكل') return true;
    if (selectedPaymentTypeFilter != 'الكل') return true;
    if (selectedPrintStatusFilter != 'الكل') return true;
    if (selectedWhatsAppStatusFilter != 'الكل') return true;
    if (selectedReprintFilter != 'الكل') return true;
    if (fromDate != null || toDate != null) return true;
    if (fromTime != null || toTime != null) return true;
    return false;
  }

  /// عرض تفاصيل السجل
  void _showRecordDetails(Map<String, dynamic> record) {
    // استخدام الاستخراج المرن ذاته لضمان التطابق
    String subscriptionNotes = _extractFlexibleValue(
      record,
      specificKeys: const [
        'ملاحظات الاشتراك',
        'Subscription Notes',
        'ملاحظات المشغل',
      ],
      containsPatterns: const ['ملاحظ', 'note'],
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('تفاصيل السجل'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (subscriptionNotes.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.note,
                              color: Colors.teal.shade600, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'ملاحظات الاشتراك:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subscriptionNotes,
                        style: TextStyle(color: Colors.teal.shade800),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              // باقي الحقول
              ...record.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          '${entry.key}:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[700],
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          entry.value?.toString() ?? 'غير متوفر',
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
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

  /// نافذة تفاصيل المستخدم (معطلة حالياً)
  /* void _showUserDetails() {
    final effectiveRecords = allRecords.length;
    final role = isAdmin ? 'مدير' : 'مستخدم عادي';
    final scopeText = isAdmin ? 'ترى كل السجلات' : 'ترى سجلاتك فقط';
    final diff = totalFetchedRecords - effectiveRecords;
    final limited = !isAdmin && diff > 0;

    // بيانات النظام الأول
    final fsUser = widget.firstSystemUsername;
    final fsPerm = widget.firstSystemPermissions;
    final fsDept = widget.firstSystemDepartment;
    final fsCenter = widget.firstSystemCenter;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('تفاصيل المستخدم',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _kv('الاسم', widget.activatedBy),
              _kv('الدور', role),
              _kv('نطاق العرض', scopeText),
              _kv('عدد السجلات المعروضة', '$effectiveRecords'),
              _kv('إجمالي السجلات الأصلية', '$totalFetchedRecords'),
              if (limited)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    'تم إخفاء $diff سجلات لا تخصك (منفذ العملية مختلف).',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade800),
                  ),
                ),
              const Divider(height: 24),
              Text('معلومات النظام الأول',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade700)),
              const SizedBox(height: 6),
              if (fsUser == null && fsPerm == null && fsDept == null && fsCenter == null)
                Text('لا تتوفر بيانات للنظام الأول.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
              else ...[
                if (fsUser != null) _kv('مستخدم النظام الأول', fsUser),
                if (fsPerm != null) _kv('صلاحيات النظام الأول', fsPerm),
                if (fsDept != null) _kv('قسم النظام الأول', fsDept),
                if (fsCenter != null) _kv('مركز النظام الأول', fsCenter),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  } */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        title: Text('سجلات الحسابات',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // زر التصفية السريعة بالتاريخ
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _quickDateFilter == 'all'
                    ? Colors.orange.withValues(alpha: 0.3)
                    : Colors.green.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _quickDateFilter == 'all'
                      ? Colors.orange
                      : Colors.greenAccent,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _getQuickFilterLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            tooltip: 'تصفية سريعة',
            onSelected: (value) {
              setState(() {
                _quickDateFilter = value;
                _applyQuickDateFilter();
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'today_yesterday',
                child: Row(
                  children: [
                    Icon(
                      _quickDateFilter == 'today_yesterday'
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: _quickDateFilter == 'today_yesterday'
                          ? Colors.green
                          : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text('اليوم وأمس'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'today',
                child: Row(
                  children: [
                    Icon(
                      _quickDateFilter == 'today'
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: _quickDateFilter == 'today'
                          ? Colors.green
                          : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text('اليوم فقط'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'yesterday',
                child: Row(
                  children: [
                    Icon(
                      _quickDateFilter == 'yesterday'
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: _quickDateFilter == 'yesterday'
                          ? Colors.green
                          : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text('أمس فقط'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(
                      _quickDateFilter == 'all'
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: _quickDateFilter == 'all'
                          ? Colors.orange
                          : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Text('الكل'),
                  ],
                ),
              ),
            ],
          ),
          // زر إخفاء المكرر
          GestureDetector(
            onTap: () {
              setState(() {
                hideDuplicates = !hideDuplicates;
                if (hideDuplicates) {
                  showDuplicatesOnly = false;
                }
              });
              _applyFilters();
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: hideDuplicates
                    ? Colors.blue.withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hideDuplicates ? Colors.lightBlueAccent : Colors.grey,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hideDuplicates ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'التكرار',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(showFilters ? Icons.filter_list_off : Icons.filter_list,
                size: 26),
            tooltip: showFilters ? 'إخفاء التصفية' : 'إظهار التصفية',
            onPressed: _toggleFilters,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: _hasActiveFilters()
                    ? Colors.redAccent.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: _hasActiveFilters()
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ),
              onPressed: _hasActiveFilters() ? _clearFilters : null,
              icon: Icon(Icons.clear_all,
                  size: 18,
                  color: _hasActiveFilters()
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6)),
              label: Text(
                'الغاء التصفية',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _hasActiveFilters()
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh, size: 26),
            tooltip: 'تحديث البيانات',
            onPressed: _loadRecords,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : (filteredRecords.isEmpty
                    ? Center(
                        child: Text('لا توجد سجلات مطابقة'),
                      )
                    : _buildRecordsList()),
          ),
        ],
      ),
    );
  }

  // تم حذف الدالة _kv لأنها كانت تُستخدم فقط ضمن نافذة تفاصيل المستخدم

  /// الانتقال إلى صفحة إحصائيات جديدة بدل النافذة السفلية
  void _openStatsPage() {
    final totalAmount = _calculateTotalAmount();
    final recordsCount = filteredRecords.length;
    final purchaseStats = _calculatePurchaseStats();
    final renewalStats = _calculateRenewalStats();

    // حساب الإحصائيات حسب نوع الدفع (نقد/آجل)
    int cashCount = 0;
    double cashTotal = 0.0;
    int creditCount = 0;
    double creditTotal = 0.0;
    // تجميع حسب منفذ العملية (المستخدم) باستخدام خريطة بسيطة
    final Map<String, Map<String, num>> userAgg = {};

    for (final r in filteredRecords) {
      final pay = _derivePaymentType(r); // يُرجع 'نقد' أو 'آجل' عند التطبيع
      final priceString = r['سعر الباقة']?.toString() ?? '0';
      final price = double.tryParse(priceString.replaceAll(',', '')) ?? 0.0;
      final op = _normalizeOperationType(r['نوع العملية']?.toString() ?? '');
      // استخدام الاسم الموحّد (منفذ العملية) مع الرجوع إلى "المُفعِّل" إذا لم يُوجد
      final executor = (r['منفذ العملية']?.toString().trim().isNotEmpty == true
              ? r['منفذ العملية']!.toString()
              : (r['المُفعِّل']?.toString() ?? 'غير محدد'))
          .trim();

      // تحديث المجاميع العامة لنوع الدفع
      if (pay == 'نقد' || pay.contains('نقد')) {
        cashCount++;
        cashTotal += price;
      } else if (pay == 'آجل' ||
          pay.contains('آجل') ||
          pay.contains('اجل') ||
          pay.contains('أجل')) {
        creditCount++;
        creditTotal += price;
      }

      final agg = userAgg.putIfAbsent(
          executor,
          () => {
                'purchaseCount': 0,
                'purchaseAmount': 0.0,
                'renewalCount': 0,
                'renewalAmount': 0.0,
                'cashCount': 0,
                'cashAmount': 0.0,
                'creditCount': 0,
                'creditAmount': 0.0,
              });
      if (op == 'شراء اشتراك جديد') {
        agg['purchaseCount'] = (agg['purchaseCount']! + 1);
        agg['purchaseAmount'] = (agg['purchaseAmount']! + price);
      } else if (op == 'تجديد اشتراك') {
        agg['renewalCount'] = (agg['renewalCount']! + 1);
        agg['renewalAmount'] = (agg['renewalAmount']! + price);
      }
      if (pay == 'نقد' || pay.contains('نقد')) {
        agg['cashCount'] = (agg['cashCount']! + 1);
        agg['cashAmount'] = (agg['cashAmount']! + price);
      } else if (pay == 'آجل' ||
          pay.contains('آجل') ||
          pay.contains('اجل') ||
          pay.contains('أجل')) {
        agg['creditCount'] = (agg['creditCount']! + 1);
        agg['creditAmount'] = (agg['creditAmount']! + price);
      }
    }

    // تحويل التجميع إلى قائمة UserAccountStat مرتبة حسب القيمة الإجمالية
    final userStatsList = userAgg.entries.map((e) {
      final a = e.value;
      return UserAccountStat(
        name: e.key,
        purchaseCount: a['purchaseCount']!.toInt(),
        purchaseAmount: a['purchaseAmount']!.toDouble(),
        renewalCount: a['renewalCount']!.toInt(),
        renewalAmount: a['renewalAmount']!.toDouble(),
        cashCount: a['cashCount']!.toInt(),
        cashAmount: a['cashAmount']!.toDouble(),
        creditCount: a['creditCount']!.toInt(),
        creditAmount: a['creditAmount']!.toDouble(),
      );
    }).toList()
      ..sort((b, a) => (a.totalAmount).compareTo(b.totalAmount));

    // إنشاء معايير التصفية الحالية لتمريرها للصفحات التالية
    FilterCriteria currentFilters = FilterCriteria(
      searchQuery: searchQuery,
      selectedOperationFilter: selectedOperationFilter,
      selectedZoneFilter: selectedZoneFilter,
      selectedExecutorFilter: selectedExecutorFilter,
      selectedSubscriptionTypeFilter: selectedSubscriptionTypeFilter,
      selectedPaymentTypeFilter: selectedPaymentTypeFilter,
      selectedPrintStatusFilter: selectedPrintStatusFilter,
      selectedWhatsAppStatusFilter: selectedWhatsAppStatusFilter,
      fromDate: fromDate,
      toDate: toDate,
      fromTime: fromTime,
      toTime: toTime,
      mergeSimilarAccounts: mergeSimilarAccounts,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountStatsPage(
          purchaseCount: purchaseStats['count'] as int,
          purchaseTotal: purchaseStats['total'] as double,
          renewalCount: renewalStats['count'] as int,
          renewalTotal: renewalStats['total'] as double,
          totalRecords: recordsCount,
          totalAmount: totalAmount,
          cashCount: cashCount,
          cashTotal: cashTotal,
          creditCount: creditCount,
          creditTotal: creditTotal,
          userStats: userStatsList,
          filterCriteria: currentFilters, // تمرير معايير التصفية
          filteredRecords: List<Map<String, dynamic>>.from(
              filteredRecords), // تمرير العمليات المفلترة
        ),
      ),
    );
  }

  /// بناء شريط البحث والتصفية
  Widget _buildFilterBar() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // شريط البحث - بارز ومميز (أول عنصر)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Color(0xFF1565C0), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'البحث في السجلات...',
                hintStyle: TextStyle(color: Colors.grey.shade500),
                prefixIcon:
                    Icon(Icons.search, color: Color(0xFF1565C0), size: 24),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.red.shade400),
                        onPressed: () {
                          setState(() {
                            searchQuery = '';
                          });
                          _applyFilters();
                        },
                      )
                    : null,
              ),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
                _applyFilters();
              },
            ),
          ),
          SizedBox(height: 12),
          // بطاقة الإحصائيات والأزرار - تصميم بارز وموحد
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white, Color(0xFFF8FAFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.black, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.12),
                  blurRadius: 15,
                  offset: Offset(0, 6),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // عرض عدد السجلات والمجموع المالي في صف واحد - تصميم فاخر
                Row(
                  children: [
                    // بطاقة عدد السجلات
                    Expanded(
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.format_list_numbered,
                                color: Colors.white, size: 22),
                            SizedBox(height: 6),
                            Text(
                              '${filteredRecords.length}',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontSize: 22,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'سجل معروض',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    // بطاقة المجموع المالي
                    Expanded(
                      child: Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.payments_outlined,
                                color: Colors.white, size: 22),
                            SizedBox(height: 6),
                            Text(
                              _formatAmountShort(_calculateTotalAmount()),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                fontSize: 20,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'المجموع المالي',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                // صف الأزرار: عرض الإحصائيات + التكرار + إخفاء المكرر (أسفل البطاقات)
                Row(
                  children: [
                    // زر عرض الإحصائيات
                    Expanded(
                      flex: 1,
                      child: Container(
                        margin: const EdgeInsets.only(left: 4),
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color.fromARGB(255, 38, 125, 36),
                              const Color.fromARGB(255, 49, 167, 51)
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _openStatsPage,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.insights,
                                      color: Colors.white, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    'الإحصائيات',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    // زر التكرار
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: showDuplicatesOnly
                                ? [
                                    const Color(0xFFE65100),
                                    const Color(0xFFFF9800)
                                  ]
                                : [
                                    const Color(0xFF7B1FA2),
                                    const Color(0xFFAB47BC)
                                  ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: (showDuplicatesOnly
                                      ? Colors.orange
                                      : Colors.purple)
                                  .withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _toggleDuplicatesFilter,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    showDuplicatesOnly
                                        ? Icons.filter_alt_off
                                        : Icons.content_copy,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    showDuplicatesOnly ? 'إلغاء' : 'اسم مكرر',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    // زر إظهار وصل مكرر (السجلات المطبوعة أكثر من مرة)
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: selectedReprintFilter == 'مطبوع أكثر من مرة'
                                ? [
                                    const Color(0xFFC62828),
                                    const Color(0xFFEF5350)
                                  ]
                                : [
                                    const Color(0xFF00695C),
                                    const Color(0xFF26A69A)
                                  ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (selectedReprintFilter == 'مطبوع أكثر من مرة'
                                          ? Colors.red
                                          : Colors.teal)
                                      .withValues(alpha: 0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setState(() {
                                if (selectedReprintFilter ==
                                    'مطبوع أكثر من مرة') {
                                  selectedReprintFilter = 'الكل';
                                } else {
                                  selectedReprintFilter = 'مطبوع أكثر من مرة';
                                }
                              });
                              _applyFilters();
                            },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    selectedReprintFilter == 'مطبوع أكثر من مرة'
                                        ? Icons.filter_alt_off
                                        : Icons.print,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    selectedReprintFilter == 'مطبوع أكثر من مرة'
                                        ? 'إلغاء'
                                        : 'وصل مكرر',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // حذف الكونتينر القديم لعرض الإحصائيات - تم دمجه في الصف أعلاه

          // التصفيات المتقدمة (تظهر فقط عند الضغط على زر التصفية)
          if (showFilters) ...[
            SizedBox(height: 16),
            // نجعل مساحة التصفية قابلة للتمرير وبإرتفاع أقصى لتجنب الانسكاب على الشاشات الصغيرة
            LayoutBuilder(
              builder: (context, constraints) {
                final screenHeight = MediaQuery.of(context).size.height;
                final maxHeight =
                    screenHeight * 0.65; // حد أقصى لارتفاع لوحة التصفية
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    // أقل من عرض الشاشة، وأقصى ارتفاع 65% من الشاشة
                    maxHeight: maxHeight,
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.black, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'التصفيات المتقدمة',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                          // زر التبديل لدمج الأسماء المتطابقة (بدون حساسية حالة)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'دمج الأسماء المتطابقة (حالة الأحرف)',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[800],
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Switch(
                                  value: mergeSimilarAccounts,
                                  activeThumbColor: Colors.deepPurple,
                                  onChanged: (v) {
                                    setState(() {
                                      mergeSimilarAccounts = v;
                                    });
                                    // إعادة تحميل لإعادة بناء القائمة حسب الخيار
                                    _loadRecords();
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 12), // الصف الأول: فلاتر مستجيبة
                          _buildResponsiveFilterDropdowns(),
                          SizedBox(height: 12),
                          _buildQuickDateButtonsRow(),

                          SizedBox(height: 12),

                          // الصف الثاني - تصفية التاريخ والأزرار على Wrap مستجيب
                          _buildDateSelectionActionsRow(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  /// اختيار تاريخ البداية  /// اختيار تاريخ النهاية
  Future<void> _selectToDate(BuildContext context) async {
    try {
      print('فتح تقويم النهاية...');
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: toDate ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
        locale: const Locale('ar'),
        builder: (ctx, child) {
          if (child == null) return const SizedBox.shrink();
          return Localizations.override(
              context: ctx, locale: const Locale('ar'), child: child);
        },
      );

      print('التاريخ المختار: $picked');

      if (picked != null) {
        setState(() {
          toDate = picked;
        });

        print('تم تحديث toDate إلى: $toDate');
      }
    } catch (e) {
      print('خطأ في اختيار التاريخ: $e');
    }
  }

  /// عناصر فلاتر منسقة باستجابة للحجم لتفادي عدم التناسق
  Widget _buildResponsiveFilterDropdowns() {
    const spacing = 8.0;
    InputDecoration dec(String label) => InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.black, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.black, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.deepPurple, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          filled: true,
          fillColor: Colors.grey.shade50,
        );

    Widget boxed(Widget child) => ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 160, maxWidth: 320),
          child: child,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = maxWidth >= 1400
            ? 7 // 7 أعمدة للشاشات الكبيرة جداً
            : maxWidth >= 1200
                ? 6 // 6 أعمدة للشاشات الكبيرة
                : maxWidth >= 1000
                    ? 5 // 5 أعمدة للشاشات المتوسطة الكبيرة
                    : maxWidth >= 800
                        ? 4 // 4 أعمدة للشاشات المتوسطة
                        : maxWidth >= 600
                            ? 3 // 3 أعمدة للتابلت
                            : maxWidth >= 400
                                ? 2 // عمودين للهواتف الكبيرة
                                : 1; // عمود واحد للهواتف الصغيرة
        final itemWidth = (maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: itemWidth,
              child: boxed(
                DropdownButtonFormField<String>(
                  initialValue: selectedOperationFilter,
                  decoration: dec('نوع العملية'),
                  items: operationFilterOptions
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(option,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() {
                    selectedOperationFilter = value ?? 'الكل';
                  }),
                ),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: boxed(
                DropdownButtonFormField<String>(
                  initialValue: selectedSubscriptionTypeFilter,
                  decoration: dec('نوع الاشتراك'),
                  items: subscriptionTypeOptions
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(option,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() {
                    selectedSubscriptionTypeFilter = value ?? 'الكل';
                  }),
                ),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: boxed(
                DropdownButtonFormField<String>(
                  initialValue: selectedZoneFilter,
                  decoration: dec('الزون'),
                  items: zoneOptions
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(option,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() {
                    selectedZoneFilter = value ?? 'الكل';
                  }),
                ),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: boxed(
                DropdownButtonFormField<String>(
                  initialValue: selectedExecutorFilter,
                  decoration: dec('منفذ العملية'),
                  items: executorOptions
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(option,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() {
                    selectedExecutorFilter = value ?? 'الكل';
                  }),
                ),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: boxed(
                DropdownButtonFormField<String>(
                  initialValue: selectedPaymentTypeFilter,
                  decoration: dec('نوع الدفع'),
                  items: ['الكل', 'نقد', 'آجل']
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(option,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (value) => setState(() {
                    selectedPaymentTypeFilter = value ?? 'الكل';
                  }),
                ),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: boxed(
                DropdownButtonFormField<String>(
                  initialValue: selectedPrintStatusFilter,
                  decoration: dec('حالة الطباعة'),
                  items: ['الكل', 'تم', 'لم يتم']
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(option,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedPrintStatusFilter = value ?? 'الكل';
                    });
                    _applyFilters();
                  },
                ),
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: boxed(
                DropdownButtonFormField<String>(
                  initialValue: selectedWhatsAppStatusFilter,
                  decoration: dec('حالة الواتساب'),
                  items: ['الكل', 'تم', 'لم يتم']
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(option,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedWhatsAppStatusFilter = value ?? 'الكل';
                    });
                    _applyFilters();
                  },
                ),
              ),
            ),
            // فلتر تكرار الطبع
            SizedBox(
              width: itemWidth,
              child: boxed(
                DropdownButtonFormField<String>(
                  initialValue: selectedReprintFilter,
                  decoration: dec('تكرار الطبع'),
                  items: [
                    'الكل',
                    'مطبوع أكثر من مرة',
                    'مطبوع مرة واحدة',
                    'لم يُطبع'
                  ]
                      .map((option) => DropdownMenuItem(
                            value: option,
                            child: Text(option,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedReprintFilter = value ?? 'الكل';
                    });
                    _applyFilters();
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// صف أزرار التاريخ السريعة (أمس/اليوم/الأسبوع) بتخطيط Wrap
  Widget _buildQuickDateButtonsRow() {
    const spacing = 8.0;
    ButtonStyle style(Color bg) => ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        );

    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final columns = maxWidth >= 520 ? 3 : 1;
      final itemWidth = (maxWidth - spacing * (columns - 1)) / columns;

      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          SizedBox(
            width: itemWidth,
            child: ElevatedButton.icon(
              onPressed: _setYesterdayDate,
              icon: const Icon(Icons.calendar_view_day, size: 16),
              label: const Text('أمس', style: TextStyle(fontSize: 12)),
              style: style(Colors.orange.shade600),
            ),
          ),
          SizedBox(
            width: itemWidth,
            child: ElevatedButton.icon(
              onPressed: _setTodayDate,
              icon: const Icon(Icons.today, size: 16),
              label: const Text('اليوم', style: TextStyle(fontSize: 12)),
              style: style(Colors.green.shade600),
            ),
          ),
          SizedBox(
            width: itemWidth,
            child: ElevatedButton.icon(
              onPressed: _setThisWeekDate,
              icon: const Icon(Icons.date_range, size: 16),
              label: const Text('الأسبوع', style: TextStyle(fontSize: 12)),
              style: style(Colors.blue.shade600),
            ),
          ),
        ],
      );
    });
  }

  /// صف اختيار التاريخ وأزرار التطبيق/الإلغاء بتخطيط Wrap
  Widget _buildDateSelectionActionsRow() {
    const spacing = 8.0;
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth;
      final columns = maxWidth >= 1000
          ? 4
          : maxWidth >= 760
              ? 3
              : maxWidth >= 520
                  ? 2
                  : 1;
      final itemWidth = (maxWidth - spacing * (columns - 1)) / columns;

      Widget dateBox({
        required String label,
        required String? display,
        required VoidCallback onTap,
        required bool isFrom,
      }) {
        final active = (isFrom ? fromDate : toDate) != null;
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                  color: active
                      ? Colors.deepPurple.shade400
                      : Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
              color: active ? Colors.deepPurple.shade50 : Colors.grey.shade50,
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 16, color: active ? Colors.deepPurple : Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    display ?? label,
                    style: TextStyle(
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          SizedBox(
            width: itemWidth,
            child: dateBox(
              label: 'اضغط لاختيار من تاريخ',
              display: fromDate != null
                  ? 'من: ${_arabicDigits(DateFormat('yyyy/MM/dd').format(fromDate!))}'
                  : null,
              onTap: () => _selectFromDateWithDebug(context),
              isFrom: true,
            ),
          ),
          SizedBox(
            width: itemWidth,
            child: dateBox(
              label: 'اضغط لاختيار إلى تاريخ',
              display: toDate != null
                  ? 'إلى: ${_arabicDigits(DateFormat('yyyy/MM/dd').format(toDate!))}'
                  : null,
              onTap: () => _selectToDate(context),
              isFrom: false,
            ),
          ),
          SizedBox(
            width: itemWidth,
            child: InkWell(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: toTime ?? TimeOfDay.now(),
                );
                if (picked != null) {
                  setState(() => toTime = picked);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: (toTime != null)
                          ? Colors.deepPurple.shade400
                          : Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                  color: (toTime != null)
                      ? Colors.deepPurple.shade50
                      : Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 16,
                        color:
                            (toTime != null) ? Colors.deepPurple : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        toTime == null
                            ? 'اضغط لاختيار إلى وقت'
                            : 'إلى وقت: ${_formatTimeWithArabicPeriod(toTime!)}',
                        style: TextStyle(
                          fontWeight: (toTime != null)
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: itemWidth,
            child: InkWell(
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: fromTime ?? TimeOfDay.now(),
                );
                if (picked != null) {
                  setState(() => fromTime = picked);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: (fromTime != null)
                          ? Colors.deepPurple.shade400
                          : Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                  color: (fromTime != null)
                      ? Colors.deepPurple.shade50
                      : Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 16,
                        color: (fromTime != null)
                            ? Colors.deepPurple
                            : Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fromTime == null
                            ? 'اضغط لاختيار من وقت'
                            : 'من وقت: ${_formatTimeWithArabicPeriod(fromTime!)}',
                        style: TextStyle(
                          fontWeight: (fromTime != null)
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: itemWidth,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _applyFiltersAndHide,
                    icon: const Icon(Icons.check, size: 22),
                    label: const Text('تطبيق',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear, size: 22),
                    label: const Text('إلغاء',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 54),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      foregroundColor: const Color.fromARGB(255, 126, 5, 5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// تحويل الأرقام إلى أرقام عربية (٠١٢٣٤٥٦٧٨٩)
  String _arabicDigits(String input) {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var s = input;
    for (int i = 0; i < western.length; i++) {
      s = s.replaceAll(western[i], arabic[i]);
    }
    return s;
  }

  /// محاولة استخراج DateTime من السجل لحقول التاريخ والوقت المعروفة
  DateTime? _parseRecordDateTime(Map<String, dynamic> record) {
    // 1) اقرأ التاريخ من الحقول المحتملة
    final dateColumns = ['تاريخ التفعيل', 'التاريخ', 'Date'];
    String? dateStr;
    for (final c in dateColumns) {
      final v = record[c]?.toString();
      if (v != null && v.trim().isNotEmpty) {
        dateStr = v.trim();
        break;
      }
    }
    if (dateStr == null || dateStr.isEmpty) return null;

    // قد يكون الوقت ضمن نفس النص على شكل "... في HH:mm"
    String? timeStr;
    if (dateStr.contains(' في ')) {
      final parts = dateStr.split(' في ');
      if (parts.length == 2) {
        dateStr = parts[0].trim();
        timeStr = parts[1].trim();
      }
    }
    // أو حقول الوقت المعروفة
    timeStr ??=
        (record['الوقت']?.toString() ?? record['Time']?.toString())?.trim();

    // 2) حاول DateTime.tryParse أولاً
    DateTime? dateOnly = DateTime.tryParse(dateStr);
    if (dateOnly == null) {
      // جرّب dd/MM/yyyy أو yyyy/MM/dd
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        try {
          int a = int.parse(parts[0]);
          int b = int.parse(parts[1]);
          int c = int.parse(parts[2]);
          // إن كان أول جزء > 31 فهو سنة غالباً
          if (a > 31) {
            dateOnly = DateTime(a, b, c);
          } else {
            // اعتبر dd/MM/yyyy
            dateOnly = DateTime(c, b, a);
          }
        } catch (_) {}
      }
    }
    if (dateOnly == null) return null;

    // 3) تحليل الوقت
    int hh = 0, mm = 0, ss = 0;
    if (timeStr != null &&
        timeStr.isNotEmpty &&
        timeStr.toLowerCase() != 'غير محدد') {
      final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(timeStr);
      if (m != null) {
        hh = int.tryParse(m.group(1)!) ?? 0;
        mm = int.tryParse(m.group(2)!) ?? 0;
        ss = int.tryParse(m.group(3) ?? '0') ?? 0;
      }
    }

    return DateTime(dateOnly.year, dateOnly.month, dateOnly.day, hh, mm, ss);
  }

  /// تحديد تاريخ اليوم
  void _setTodayDate() {
    final today = DateTime.now();
    setState(() {
      fromDate = DateTime(today.year, today.month, today.day);
      toDate = DateTime(today.year, today.month, today.day, 23, 59, 59);
    });

    // إظهار رسالة تأكيد
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.today, color: Colors.white),
            SizedBox(width: 8),
            Text(
                'تم تحديد تاريخ اليوم: ${_arabicDigits(DateFormat('yyyy/MM/dd').format(today))}'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green.shade600,
      ),
    );

    // لم نعد نطبق التصفية مباشرة حتى يتمكن المستخدم من إضافة عناصر أخرى قبل التطبيق
  }

  /// تحديد تاريخ أمس
  void _setYesterdayDate() {
    final yesterday = DateTime.now().subtract(Duration(days: 1));
    setState(() {
      fromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
      toDate =
          DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
    });

    // إظها�� رسالة تأكيد
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.calendar_view_day, color: Colors.white),
            SizedBox(width: 8),
            Text(
                'تم تحديد تاريخ الأمس: ${_arabicDigits(DateFormat('yyyy/MM/dd').format(yesterday))}'),
          ],
        ),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.orange.shade600,
      ),
    );

    // عدم التطبيق الفوري للتصفية
  }

  /// تحديد تاريخ هذا الأسبوع
  void _setThisWeekDate() {
    final now = DateTime.now();
    // الحصول على بداية الأسبوع (الأحد)
    final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
    final endOfWeek = startOfWeek.add(Duration(days: 6));

    setState(() {
      fromDate = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
      toDate =
          DateTime(endOfWeek.year, endOfWeek.month, endOfWeek.day, 23, 59, 59);
    });

    // إظهار رسالة تأكيد
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.date_range, color: Colors.white),
            SizedBox(width: 8),
            Text(
                'تم تحديد فترة هذا الأسبوع: ${_arabicDigits(DateFormat('MM/dd').format(startOfWeek))} - ${_arabicDigits(DateFormat('MM/dd').format(endOfWeek))}'),
          ],
        ),
        duration: Duration(seconds: 3),
        backgroundColor: Colors.blue.shade600,
      ),
    );

    // عدم التطبيق الفوري للتصفية
  }

  // تم استبدال عرض الإحصائيات بانتقال إلى صفحة مخصصة

  // تمت إزالة مكونات بطاقات الإحصائيات من هذه الصفحة لتجنب التكرار

  /// بناء قائمة السجلات
  Widget _buildRecordsList() {
    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: filteredRecords.length,
      itemBuilder: (context, index) {
        final record = filteredRecords[index];
        return _buildRecordCard(record, index);
      },
    );
  }

  /// بناء بطاقة السجل
  Widget _buildRecordCard(Map<String, dynamic> record, int index) {
    // طباعة أسماء الأعمدة للتشخيص
    if (index == 0) {
      print('أسماء الأعمدة المتاحة:');
      for (var key in record.keys) {
        print('- $key');
      }
    } // استخدام الأسماء الفعلية للأعمدة
    final customerName = record['اسم العميل']?.toString() ??
        record['Customer Name']?.toString() ??
        'غير محدد';
    final planName = record['اسم الباقة']?.toString() ?? 'غير محدد';
    final totalPrice = record['سعر الباقة']?.toString() ?? '0';
    final activatedBy = record['منفذ العملية']?.toString() ?? 'غير محدد';
    final operationTypeRaw = record['نوع العملية']?.toString() ?? 'غير محدد';
    final operationType = _normalizeOperationType(operationTypeRaw);
    final paymentType = _derivePaymentType(record);
    // تحديد لون البطاقة حسب نوع الدفع
    final bool isCashPayment = paymentType.contains('نقد');
    final bool isCreditPayment = paymentType.contains('آجل');

    // استخراج التاريخ والوقت من الأعمدة المختلفة
    final activationDate = record['تاريخ التفعيل']?.toString() ??
        record['التاريخ']?.toString() ??
        record['Date']?.toString() ??
        'غير محدد';

    final activationTime =
        record['الوقت']?.toString() ?? record['Time']?.toString() ?? '';

    // لم يعد نستخدم دمج التاريخ والوقت كسطر واحد؛ سيتم استخلاصهما بدوال مخصصة

    final currency = 'IQD'; // العملة افتراضية

    // تحديد لون الخلفية والإطار حسب نوع الدفع
    Color cardBgColor;
    Color cardBorderColor;
    if (isCashPayment) {
      cardBgColor = Color(0xFFE8F5E9); // أخضر فاتح
      cardBorderColor = Color(0xFF4CAF50); // أخضر
    } else if (isCreditPayment) {
      cardBgColor = Color(0xFFFFEBEE); // أحمر فاتح
      cardBorderColor = Color(0xFFE53935); // أحمر
    } else {
      cardBgColor = Color(0xFFF5F5F5); // رمادي فاتح
      cardBorderColor = Color(0xFF9E9E9E); // رمادي
    }

    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      elevation: 4,
      shadowColor: cardBorderColor.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cardBorderColor, width: 2),
      ),
      color: cardBgColor,
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بطاقة المفعل في الأعلى
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.shade600,
                    Colors.deepPurple.shade800,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مفعل بواسطة',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          activatedBy,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '#${index + 1}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16), // المعلومات الأساسية
            _buildInfoRow('👤 اسم المستخدم', customerName, FontWeight.bold, 16),
            SizedBox(height: 8),
            _buildInfoRow('📦 اسم الباقة', planName, FontWeight.w600, 15),
            SizedBox(height: 8),
            _buildInfoRow('⚙️ نوع العملية', operationType, FontWeight.w600, 15,
                Colors.orange.shade700),
            SizedBox(height: 8),
            _buildInfoRow('💰 سعر الباقة', '$totalPrice $currency',
                FontWeight.bold, 15, Colors.green.shade700),
            SizedBox(height: 8),
            _buildInfoRow(
                '💳 نوع الدفع',
                paymentType,
                FontWeight.w600,
                14,
                paymentType.contains('نقد')
                    ? Colors.teal.shade700
                    : Colors.purple.shade700),
            SizedBox(height: 8),
            // استخراج تاريخ/وقت أكثر موثوقية وإظهاره دائماً
            Builder(builder: (ctx) {
              final extractedDate = _deriveDisplayDate(record, activationDate);
              final extractedTime = _deriveDisplayTime(record, activationTime);
              // طباعة للتشخيص (تظهر مرة لكل بطاقة)
              debugPrint(
                  '🗓️ Record #${index + 1} date="$extractedDate" time="$extractedTime" rawDate="$activationDate" rawTime="$activationTime"');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    '📅 التاريخ',
                    extractedDate.isEmpty ? 'غير محدد' : extractedDate,
                    FontWeight.w500,
                    14,
                    Colors.blue.shade600,
                  ),
                  if (extractedTime.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: _buildInfoRow(
                        '⏰ الوقت',
                        extractedTime,
                        FontWeight.w500,
                        14,
                        Colors.indigo.shade600,
                      ),
                    ),
                ],
              );
            }),

            SizedBox(height: 8),

            // إضافة ملاحظات الاشتراك وحالات الطباعة والواتساب
            Builder(builder: (ctx) {
              // استخراج مرن يدعم اختلاف المفاتيح أو وجود فراغات أو اختلاف حالة الأحرف
              String subscriptionNotes = _extractFlexibleValue(
                record,
                specificKeys: const [
                  'ملاحظات الاشتراك',
                  'Subscription Notes',
                  'ملاحظات المشغل',
                ],
                containsPatterns: const ['ملاحظ', 'note'],
              );
              String printStatus = _extractFlexibleValue(
                record,
                specificKeys: const [
                  'تم الطباعة',
                  'Is Printed',
                  'حالة الطباعة',
                ],
                containsPatterns: const ['طباعة', 'طباع', 'print', 'printed'],
              );
              String whatsappStatus = _extractFlexibleValue(
                record,
                specificKeys: const [
                  'تم إرسال الواتساب',
                  'WhatsApp Sent',
                  'حالة الواتساب',
                ],
                containsPatterns: const ['whats', 'واتس', 'واتساب'],
              );

              // استخراج عدد مرات الطباعة
              String printCountStr = _extractFlexibleValue(
                record,
                specificKeys: const [
                  'تكرار الطبع',
                  'Print Count',
                  'Reprint Count',
                  'print_count',
                ],
                containsPatterns: const [
                  'تكرار',
                  'طبع',
                  'print count',
                  'reprint'
                ],
              );
              int printCount = int.tryParse(printCountStr) ?? 0;

              // تنظيف قيم placeholder الشائعة
              bool isPlaceholder(String v) => v.isEmpty || v == 'غير محدد';
              if (isPlaceholder(subscriptionNotes)) subscriptionNotes = '';
              if (isPlaceholder(printStatus)) printStatus = '';
              // Fallback إضافي: إذا بقيت فارغة نحاول إيجاد أي قيمة يدويًا
              if (printStatus.isEmpty) {
                for (final e in record.entries) {
                  final k = e.key.toString();
                  if (k
                          .toLowerCase()
                          .replaceAll('\u200f', '')
                          .replaceAll('\u200e', '')
                          .contains('print') ||
                      k.contains('طباعة')) {
                    final val = e.value?.toString().trim() ?? '';
                    if (val.isNotEmpty && val != 'غير محدد') {
                      printStatus = val;
                      debugPrint(
                          '🔁 Fallback printStatus استرجعت "$printStatus" من المفتاح "$k" للسجل #${index + 1}');
                      break;
                    }
                  }
                }
              }

              // لو ما زالت فارغة لكن التفاصيل تُظهر "تم" سنسجل raw key
              if (printStatus.isEmpty) {
                final raw = record['تم الطباعة'] ?? record['Is Printed'];
                if (raw != null && raw.toString().trim().isNotEmpty) {
                  debugPrint(
                      '⚠️ mismatch: extractor فشل رغم أن القيمة الخام = "${raw.toString()}" للسجل #${index + 1}');
                  // استخدم الخام مباشرة
                  printStatus = raw.toString();
                }
              }
              if (isPlaceholder(whatsappStatus)) whatsappStatus = '';

              if (index == 0) {
                debugPrint(
                    '🧪 Flexible extract => notes="$subscriptionNotes" print="$printStatus" wa="$whatsappStatus"');
                debugPrint('🧾 Keys sample: ${record.keys}');
                // طباعة المقارنة بين البطاقة والتفاصيل
                debugPrint('🔍 تفاصيل حالة الطباعة:');
                debugPrint('   - القيمة المستخرجة: "$printStatus"');
                debugPrint(
                    '   - _isPrintedStatus: ${_isPrintedStatus(printStatus)}');
                debugPrint(
                    '   - _getStatusText: ${_getStatusText(printStatus)}');
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ملخص حالة المعالجة (نفس منطق نافذة التفاصيل)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueGrey.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.settings,
                            color: Colors.blueGrey.shade600, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.print,
                                    size: 16,
                                    color: printStatus.isEmpty
                                        ? Colors.red.shade600
                                        : (_isPrintedStatus(printStatus)
                                            ? Colors.green.shade600
                                            : Colors.red.shade600),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'طباعة: ${printStatus.isEmpty ? 'لم يتم' : _getStatusText(printStatus)}${printCount > 0 ? ' ($printCount)' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: printStatus.isEmpty
                                          ? Colors.red.shade700
                                          : (_isPrintedStatus(printStatus)
                                              ? Colors.green.shade700
                                              : Colors.red.shade700),
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.chat,
                                    size: 16,
                                    color: whatsappStatus.isEmpty
                                        ? Colors.red.shade600
                                        : (_isWhatsAppStatus(whatsappStatus)
                                            ? Colors.green.shade600
                                            : Colors.red.shade600),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'واتساب: ${whatsappStatus.isEmpty ? 'لم يتم' : _getStatusText(whatsappStatus)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: whatsappStatus.isEmpty
                                          ? Colors.red.shade700
                                          : (_isWhatsAppStatus(whatsappStatus)
                                              ? Colors.green.shade700
                                              : Colors.red.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (subscriptionNotes.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12),
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.note,
                                  color: Colors.teal.shade600, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'ملاحظات الاشتراك:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6),
                          Text(
                            subscriptionNotes,
                            style: TextStyle(
                              color: Colors.teal.shade800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }),

            SizedBox(height: 16),

            // زر عرض التفاصيل
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _showRecordDetails(record),
                  icon: Icon(Icons.visibility, size: 16),
                  label: Text('عرض التفاصيل'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// بناء صف المعلومات
  Widget _buildInfoRow(
      String label, String value, FontWeight fontWeight, double fontSize,
      [Color? textColor]) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize - 1,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: textColor ?? Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  /// اشتقاق التاريخ المعروض من السجل أو من القيمة الخام
  String _deriveDisplayDate(Map<String, dynamic> record, String rawDate) {
    String candidate = rawDate;
    // أولوية أعمدة معروفة
    for (final key in ['تاريخ التفعيل', 'التاريخ', 'Date']) {
      final v = record[key]?.toString();
      if (v != null && v.trim().isNotEmpty && v.trim() != 'غير محدد') {
        candidate = v.trim();
        break;
      }
    }
    if (candidate.contains(' في ')) {
      candidate = candidate.split(' في ').first.trim();
    }
    // تنظيف احتمالي
    candidate = candidate.replaceAll('\n', ' ').trim();
    // محاولة تحويله لصيغة موحدة
    DateTime? parsed;
    try {
      parsed = DateTime.tryParse(candidate);
    } catch (_) {}
    if (parsed != null) {
      return DateFormat('yyyy/MM/dd').format(parsed);
    }
    // fallback: إعادة النص كما هو إن كان معقولاً
    if (candidate.isEmpty || candidate == 'غير محدد') return '';
    return candidate;
  }

  /// اشتقاق الوقت المعروض من السجل أو القيمة الخام
  String _deriveDisplayTime(Map<String, dynamic> record, String rawTime) {
    String candidate = rawTime;
    for (final key in ['الوقت', 'Time']) {
      final v = record[key]?.toString();
      if (v != null && v.trim().isNotEmpty) {
        candidate = v.trim();
        break;
      }
    }
    // إذا الوقت فارغ ربما مدمج ضمن التاريخ بصيغة "yyyy/MM/dd في HH:mm"
    if ((candidate.isEmpty || candidate == 'غير محدد')) {
      for (final key in ['تاريخ التفعيل', 'التاريخ', 'Date']) {
        final v = record[key]?.toString();
        if (v != null && v.contains(' في ')) {
          final parts = v.split(' في ');
          if (parts.length == 2) {
            candidate = parts[1].trim();
            break;
          }
        }
      }
    }
    // تطبيع بسيط لصيغة الوقت
    candidate = candidate.replaceAll('\n', ' ').trim();
    if (candidate.toLowerCase().startsWith('00:00')) {
      return ''; // وقت افتراضي غير مفيد
    }
    // عرض بصيغة 12 ساعة مع ص/م
    return _formatTimeStringWithArabicPeriod(candidate);
  }

  /// تنسيق TimeOfDay بعرض 12 ساعة مع ص/م
  String _formatTimeWithArabicPeriod(TimeOfDay t) {
    final h12 = (t.hourOfPeriod == 0) ? 12 : t.hourOfPeriod;
    final period = t.period == DayPeriod.am ? 'ص' : 'م';
    return '${_two(h12)}:${_two(t.minute)} $period';
  }

  /// محاولة تنسيق نص وقت إلى 12 ساعة مع ص/م
  String _formatTimeStringWithArabicPeriod(String input) {
    var s = input.trim();
    if (s.isEmpty || s == 'غير محدد') return '';

    // استبدال AM/PM الإنجليزية إن وُجدت
    s = s
        .replaceAll(RegExp(r'\bAM\b', caseSensitive: false), 'ص')
        .replaceAll(RegExp(r'\bPM\b', caseSensitive: false), 'م');

    // إذا كان يحتوي أصلاً على ص/م نُبقيه كما هو مع تنظيف بسيط
    if (RegExp(r'[صم]').hasMatch(s)) {
      return s;
    }

    // مطابقة أنماط HH:mm أو H:mm (اختياري ثواني)
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(s);
    if (m != null) {
      int hh = int.tryParse(m.group(1)!) ?? 0;
      int mm = int.tryParse(m.group(2)!) ?? 0;
      final isAM = hh < 12;
      int h12 = hh % 12;
      if (h12 == 0) h12 = 12;
      final period = isAM ? 'ص' : 'م';
      return '${_two(h12)}:${_two(mm)} $period';
    }

    // لم نتمكن من التحليل؛ إرجاع كما هو
    return s;
  }

  /// استخراج نوع الدفع (نقد / أجل) من الحقول المحتملة مع تطبيع
  String _derivePaymentType(Map<String, dynamic> record) {
    // مفاتيح محتملة لنوع الدفع
    final keys = [
      'نوع الدفع',
      'طريقة الدفع',
      'Payment Type',
      'Payment',
      'طريقة الدفع ',
    ];
    String raw = '';
    for (final k in keys) {
      final v = record[k]?.toString();
      if (v != null && v.trim().isNotEmpty && v.trim() != 'غير محدد') {
        raw = v.trim();
        break;
      }
    }
    if (raw.isEmpty) return 'غير محدد';

    final lower = raw.toLowerCase();
    // تطبيع محتمل
    if (lower.contains('cash') ||
        lower.contains('نقد') ||
        lower.contains('كاش')) {
      return 'نقد';
    }
    if (lower.contains('اجل') ||
        lower.contains('آجل') ||
        lower.contains('أجل') ||
        lower.contains('credit') ||
        lower.contains('deferred')) {
      return 'آجل';
    }
    return raw; // تركه كما هو إن لم يُطبع
  }

  /// دالة بديلة لاختيار التاريخ مع تشخيص مفصل
  Future<void> _selectFromDateWithDebug(BuildContext context) async {
    print('🔍 بداية تشخيص مشكلة التقويم...');

    try {
      // التحقق من صحة السياق
      if (!mounted) {
        print('❌ الصف��ة غير مُرفقة (not mounted)');
        return;
      }

      print('✅ السياق صحيح');
      print('📅 محاولة فتح التقويم...');

      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
        locale: const Locale('ar'),
        builder: (ctx, child) {
          if (child == null) return const SizedBox.shrink();
          return Localizations.override(
              context: ctx, locale: const Locale('ar'), child: child);
        },
      );

      if (picked != null) {
        print('✅ تم اختيار التاريخ: $picked');
        if (mounted) {
          setState(() {
            fromDate = picked;
          });
          print('✅ تم تحديث fromDate');
        }
      } else {
        print('❌ لم يتم اختيار أي تاريخ');
      }
    } catch (e, stackTrace) {
      print('❌ خطأ في فتح التقويم: $e');
      print('📋 Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// التحقق من حالة الطباعة
  bool _isPrintedStatus(String status) {
    if (status.isEmpty) return false;
    final lower = status.toLowerCase().trim();
    // أنماط سلبية أولا حتى لا تُخطئ عبارة "لم يتم" بسبب احتوائها "تم"
    if (lower.contains('لم يتم') ||
        lower.startsWith('لم ') ||
        lower == 'لا' ||
        lower == 'no' ||
        lower == 'false' ||
        lower == '0' ||
        lower.contains('غير') ||
        lower.contains('لم تطبع')) {
      return false;
    }
    return lower == 'نعم' ||
        lower == 'yes' ||
        lower == 'true' ||
        lower == '1' ||
        lower.contains('تم') ||
        lower.contains('printed');
  }

  /// التحقق من حالة الواتساب
  bool _isWhatsAppStatus(String status) {
    if (status.isEmpty || status == 'غير محدد') return false;
    final lower = status.toLowerCase().trim();
    return lower == 'نعم' ||
        lower == 'yes' ||
        lower == 'true' ||
        lower == '1' ||
        lower.contains('تم') ||
        lower.contains('sent');
  }

  /// الحصول على نص الحالة باللغة العربية
  String _getStatusText(String status) {
    if (status.isEmpty) return 'لم يتم';
    final lower = status.toLowerCase().trim();
    // سلبية أولاً
    if (lower.contains('لم يتم') ||
        lower.startsWith('لم ') ||
        lower == 'لا' ||
        lower == 'no' ||
        lower == 'false' ||
        lower == '0' ||
        lower.contains('غير')) {
      return 'لم يتم';
    }
    if (lower == 'نعم' ||
        lower == 'yes' ||
        lower == 'true' ||
        lower == '1' ||
        lower.contains('تم') ||
        lower.contains('printed')) {
      return 'تم';
    }
    return 'لم يتم';
  }

  /// استخراج مرن لقيمة حقل باحتمالية اختلاف الاسم أو وجود مسافات إضافية أو اختلاف حالة الأحرف
  /// - specificKeys: أسماء صريحة نحاول مطابقتها مباشرة (case-insensitive + trim)
  /// - containsPatterns: جزء من الاسم نبحث عنه داخل المفاتيح (lowercase)
  String _extractFlexibleValue(
    Map<String, dynamic> record, {
    List<String> specificKeys = const [],
    List<String> containsPatterns = const [],
  }) {
    if (record.isEmpty) return '';

    // بناء خريطة مفاتيح مطبعة إلى المفتاح الأصلي لسهولة البحث
    final Map<String, String> normalizedKeyMap = {};
    for (final k in record.keys) {
      final norm = k
          .replaceAll('\u200f', '') // إزالة رمز RTL إن وجد
          .replaceAll('\u200e', '')
          .trim()
          .toLowerCase();
      normalizedKeyMap[norm] = k;
    }

    // 1) محاولة مطابقة الأسماء الصريحة
    for (final sk in specificKeys) {
      final normSk = sk.trim().toLowerCase();
      final match = normalizedKeyMap.entries.firstWhere(
        (e) => e.key == normSk,
        orElse: () => const MapEntry('', ''),
      );
      if (match.key.isNotEmpty) {
        final v = record[match.value]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
    }

    // 2) البحث بالأنماط الجزئية
    if (containsPatterns.isNotEmpty) {
      for (final entry in normalizedKeyMap.entries) {
        for (final pat in containsPatterns) {
          final p = pat.toLowerCase();
          if (entry.key.contains(p)) {
            final v = record[entry.value]?.toString().trim() ?? '';
            if (v.isNotEmpty) return v;
          }
        }
      }
    }

    return '';
  }
}
