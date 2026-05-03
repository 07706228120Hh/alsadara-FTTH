/// اسم الصفحة: سجلات المستخدم
/// وصف الصفحة: صفحة سجلات وتاريخ المستخدم
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import '../../services/subscription_logs_service.dart';
import 'package:intl/intl.dart';
import '../../models/filter_criteria.dart';

/// صفحة سجلات مستخدم محدد - مشابهة لـ account_records_page ولكن مفلترة حسب المستخدم
class UserRecordsPage extends StatefulWidget {
  final String userName; // اسم المستخدم المحدد
  final FilterCriteria? initialFilterCriteria; // معايير التصفية الأولية
  final List<Map<String, dynamic>>?
      userSpecificRecords; // العمليات المفلترة للمستخدم

  const UserRecordsPage({
    super.key,
    required this.userName,
    this.initialFilterCriteria,
    this.userSpecificRecords, // العمليات المفلترة الاختيارية
  });

  @override
  State<UserRecordsPage> createState() => _UserRecordsPageState();
}

class _UserRecordsPageState extends State<UserRecordsPage> {
  List<Map<String, dynamic>> allRecords = [];
  List<Map<String, dynamic>> filteredRecords = [];
  bool isLoading = false;
  String searchQuery = '';
  String selectedOperationFilter = 'الكل'; // نوع العملية
  String selectedZoneFilter = 'الكل'; // الزون
  String selectedExecutorFilter = 'الكل'; // منفذ العملية (مضاف)
  String selectedSubscriptionTypeFilter = 'الكل'; // نوع الاشتراك
  String selectedPaymentTypeFilter = 'الكل'; // نوع الدفع (نقد / آجل)
  String selectedPrintStatusFilter = 'الكل'; // حالة الطباعة
  String selectedWhatsAppStatusFilter = 'الكل'; // حالة الواتساب
  DateTime? fromDate;
  DateTime? toDate;
  TimeOfDay? fromTime;
  TimeOfDay? toTime;
  bool showFilters = false;

  final List<String> operationFilterOptions = [
    'الكل',
    'شراء اشتراك جديد',
    'تجديد اشتراك',
  ];

  // قوائم التصفية
  List<String> zoneOptions = ['الكل'];
  List<String> executorOptions = ['الكل']; // قائمة منفذي العمليات (مضافة)
  List<String> subscriptionTypeOptions = ['الكل'];

  @override
  void initState() {
    super.initState();
    _initializeFromCriteria();

    // إذا تم تمرير العمليات المفلترة، استخدمها مباشرة
    if (widget.userSpecificRecords != null) {
      print('📦 UserRecordsPage - استخدام العمليات المفلترة الممررة');
      print('   - عدد العمليات الممررة: ${widget.userSpecificRecords!.length}');
      _useProvidedRecords();
    } else {
      print('🔄 UserRecordsPage - جلب العمليات من الخادم');
      _loadUserRecords();
    }
  }

  /// تطبيق معايير التصفية الأولية إن وُجدت
  void _initializeFromCriteria() {
    final criteria = widget.initialFilterCriteria;
    if (criteria != null) {
      searchQuery = criteria.searchQuery;
      selectedOperationFilter = criteria.selectedOperationFilter;
      selectedZoneFilter = criteria.selectedZoneFilter;
      selectedExecutorFilter =
          criteria.selectedExecutorFilter; // تطبيق selectedExecutorFilter
      selectedSubscriptionTypeFilter = criteria.selectedSubscriptionTypeFilter;
      selectedPaymentTypeFilter = criteria.selectedPaymentTypeFilter;
      selectedPrintStatusFilter = criteria.selectedPrintStatusFilter;
      selectedWhatsAppStatusFilter = criteria.selectedWhatsAppStatusFilter;
      fromDate = criteria.fromDate;
      toDate = criteria.toDate;
      fromTime = criteria.fromTime;
      toTime = criteria.toTime;

      print('🔧 UserRecordsPage - تطبيق معايير التصفية الأولية:');
      print('   - البحث: "$searchQuery"');
      print('   - نوع العملية: $selectedOperationFilter');
      print('   - الزون: $selectedZoneFilter');
      print('   - منفذ العملية: $selectedExecutorFilter');
      print('   - نوع الاشتراك: $selectedSubscriptionTypeFilter');
      print('   - نوع الدفع: $selectedPaymentTypeFilter');
      print('   - حالة الطباعة: $selectedPrintStatusFilter');
      print('   - حالة الواتساب: $selectedWhatsAppStatusFilter');
      print('   - من تاريخ: $fromDate');
      print('   - إلى تاريخ: $toDate');
      print('   - من وقت: $fromTime');
      print('   - إلى وقت: $toTime');
    }
  }

  /// استخدام العمليات المفلترة الممررة من account_stats_page
  void _useProvidedRecords() {
    final providedRecords = widget.userSpecificRecords!;

    setState(() {
      allRecords = List<Map<String, dynamic>>.from(providedRecords);
      filteredRecords = List<Map<String, dynamic>>.from(providedRecords);
    });

    // استخراج خيارات التصفية من البيانات المتوفرة
    _extractFilterOptions(providedRecords);

    print('✅ UserRecordsPage - تم تحميل العمليات المفلترة');
    print('   - عدد العمليات الكلي: ${allRecords.length}');
    print('   - عدد العمليات المفلترة: ${filteredRecords.length}');

    if (providedRecords.isNotEmpty) {
      print('🔑 أول سجل - المفاتيح: ${providedRecords.first.keys}');
    }
  }

  /// جلب سجلات المستخدم المحدد من الخادم
  Future<void> _loadUserRecords() async {
    setState(() {
      isLoading = true;
    });

    try {
      final allSheetsRecords =
          await SubscriptionLogsService.instance.getAllRecords();

      // تصفية السجلات الخاصة بالمستخدم المحدد
      final userRecords = allSheetsRecords.where((record) {
        final executor =
            (record['منفذ العملية']?.toString().trim() ?? '').toLowerCase();
        final activator =
            (record['المُفعِّل']?.toString().trim() ?? '').toLowerCase();
        final targetUser = widget.userName.toLowerCase();

        return executor == targetUser || activator == targetUser;
      }).toList();

      // توحيد مفتاح اسم منفذ العملية
      for (final r in userRecords) {
        final hasExecutor = r.containsKey('منفذ العملية') &&
            (r['منفذ العملية']?.toString().trim().isNotEmpty ?? false);
        final activator = r['المُفعِّل']?.toString().trim();
        if (!hasExecutor && activator != null && activator.isNotEmpty) {
          r['منفذ العملية'] = activator;
        }
      }

      // ترتيب من الأحدث إلى الأقدم
      userRecords.sort((a, b) {
        final dateTimeA = _parseRecordDateTime(a);
        final dateTimeB = _parseRecordDateTime(b);

        if (dateTimeA == null && dateTimeB == null) return 0;
        if (dateTimeA == null) return 1;
        if (dateTimeB == null) return -1;

        return dateTimeB.compareTo(dateTimeA);
      });

      allRecords = userRecords;
      filteredRecords = userRecords;
      _extractFilterOptions(userRecords);
      _applyFilters(); // تطبيق التصفية الأولية
    } catch (e) {
      _showErrorSnackBar(e);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// عرض رسالة خطأ
  void _showErrorSnackBar(dynamic e) {
    if (!mounted) return;

    final errStr = 'حدث خطأ';
    String errorTitle = 'خطأ في تحميل البيانات';
    String errorMessage =
        'حدث خطأ أثناء تحميل سجلات المستخدم.\nالتفاصيل: $errStr';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errorTitle,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(errorMessage, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'إعادة المحاولة',
          textColor: Colors.white,
          onPressed: _loadUserRecords,
        ),
      ),
    );
  }

  /// استخراج خيارات التصفية
  void _extractFilterOptions(List<Map<String, dynamic>> records) {
    Set<String> zones = {};
    Set<String> subscriptionTypes = {};
    Set<String> executors = {}; // مضاف لاستخراج منفذي العمليات

    for (var record in records) {
      // استخراج الزونات
      record.forEach((key, value) {
        if (key.toLowerCase().contains('zone') ||
            key.toLowerCase().contains('زون')) {
          if (value != null && value.toString().trim().isNotEmpty) {
            zones.add(value.toString().trim());
          }
        }
      });

      // استخراج منفذي العمليات
      final executorValue = _extractFlexibleValue(record, specificKeys: const [
        'المُفعِّل',
        'منفذ العملية',
        'executor',
        'activator'
      ], containsPatterns: const [
        'فعّل',
        'فعل',
        'منفذ',
        'مُفعِّل'
      ]);
      if (executorValue.isNotEmpty) {
        executors.add(executorValue.trim());
      }

      // استخراج أنواع الاشتراك
      final packageName = record['اسم الباقة']?.toString();
      if (packageName != null && packageName.trim().isNotEmpty) {
        subscriptionTypes.add(packageName.trim());
      }
    }

    setState(() {
      zoneOptions = ['الكل', ...zones.toList()..sort()];
      executorOptions = [
        'الكل',
        ...executors.toList()..sort()
      ]; // تحديث قائمة منفذي العمليات
      subscriptionTypeOptions = ['الكل', ...subscriptionTypes.toList()..sort()];
    });
  }

  /// توحيد نوع العملية
  String _normalizeOperationType(String raw) {
    final v = raw.trim();
    final lower = v.toLowerCase();

    if (v.contains('شراء') ||
        lower.contains('purchase') ||
        lower.contains('buy')) {
      return 'شراء اشتراك جديد';
    }

    if (v.contains('تجديد') ||
        v.contains('تغيير') ||
        lower.contains('renew') ||
        lower.contains('change')) {
      return 'تجديد اشتراك';
    }

    return v.isEmpty ? 'غير محدد' : v;
  }

  /// استنتاج نوع الدفع
  String _derivePaymentType(Map<String, dynamic> record) {
    // البحث في جميع القيم عن مؤشرات الدفع
    for (final value in record.values) {
      final str = value?.toString().toLowerCase() ?? '';
      if (str.contains('نقد') || str.contains('cash')) {
        return 'نقد';
      }
      if (str.contains('آجل') ||
          str.contains('اجل') ||
          str.contains('أجل') ||
          str.contains('credit') ||
          str.contains('deferred')) {
        return 'آجل';
      }
    }
    return 'غير محدد';
  }

  /// استخراج قيمة مرنة من السجل
  String _extractFlexibleValue(
    Map<String, dynamic> record, {
    required List<String> specificKeys,
    required List<String> containsPatterns,
  }) {
    // البحث في المفاتيح المحددة أولاً
    for (final key in specificKeys) {
      final value = record[key]?.toString();
      if (value != null && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    // البحث في المفاتيح التي تحتوي على الأنماط
    for (final entry in record.entries) {
      final key = entry.key.toLowerCase();
      if (containsPatterns
          .any((pattern) => key.contains(pattern.toLowerCase()))) {
        final value = entry.value?.toString();
        if (value != null && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    return '';
  }

  /// فحص حالة الطباعة
  bool _isPrintedStatus(String status) {
    final lower = status.toLowerCase();
    return lower.contains('تم') ||
        lower.contains('true') ||
        lower.contains('yes') ||
        lower.contains('printed') ||
        lower == '1';
  }

  /// فحص حالة الواتساب
  bool _isWhatsAppStatus(String status) {
    final lower = status.toLowerCase();
    return lower.contains('تم') ||
        lower.contains('true') ||
        lower.contains('yes') ||
        lower.contains('sent') ||
        lower == '1';
  }

  /// تطبيق التصفية
  void _applyFilters() {
    print('🔍 تطبيق الفلاتر:');
    print('   - حالة الواتساب المحددة: "$selectedWhatsAppStatusFilter"');
    print('   - عدد السجلات قبل التصفية: ${allRecords.length}');

    setState(() {
      filteredRecords = allRecords.where((record) {
        // تصفية البحث العام
        bool matchesSearch = searchQuery.isEmpty ||
            record.values.any((value) => value
                .toString()
                .toLowerCase()
                .contains(searchQuery.toLowerCase()));

        // تصفية نوع العملية
        final normalizedOp =
            _normalizeOperationType(record['نوع العملية']?.toString() ?? '');
        bool matchesOperation = selectedOperationFilter == 'الكل' ||
            normalizedOp == selectedOperationFilter;

        // تصفية الزون
        bool matchesZone = selectedZoneFilter == 'الكل' ||
            record.values
                .any((value) => value.toString().contains(selectedZoneFilter));

        // تصفية منفذ العملية (المُفعِّل)
        bool matchesExecutor = true;
        if (selectedExecutorFilter != 'الكل') {
          // البحث عن قيمة منفذ العملية بطرق مختلفة
          final executorValue = _extractFlexibleValue(record,
              specificKeys: const [
                'المُفعِّل',
                'منفذ العملية',
                'executor',
                'activator'
              ],
              containsPatterns: const [
                'فعّل',
                'فعل',
                'منفذ',
                'مُفعِّل'
              ]);

          if (executorValue.isNotEmpty) {
            // تطابق نص منفذ العملية مع المحدد
            matchesExecutor = executorValue.contains(selectedExecutorFilter);
          } else {
            // إذا لم نجد قيمة منفذ العملية، نتركها تمر (أو يمكن استبعادها حسب الحاجة)
            matchesExecutor = true;
          }
        }

        // تصفية نوع الاشتراك
        bool matchesSubscriptionType =
            selectedSubscriptionTypeFilter == 'الكل' ||
                record['اسم الباقة']
                        ?.toString()
                        .contains(selectedSubscriptionTypeFilter) ==
                    true;

        // تصفية نوع الدفع
        bool matchesPayment = true;
        if (selectedPaymentTypeFilter != 'الكل') {
          final payNorm = _derivePaymentType(record);
          matchesPayment =
              (selectedPaymentTypeFilter == 'نقد' && payNorm == 'نقد') ||
                  (selectedPaymentTypeFilter == 'آجل' && payNorm == 'آجل');
        }

        // تصفية التاريخ
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

            DateTime? upperBound;
            if (toDate != null) {
              if (toTime != null) {
                upperBound = DateTime(toDate!.year, toDate!.month, toDate!.day,
                    toTime!.hour, toTime!.minute, 59, 999, 999);
              } else {
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

        // تصفية حالة الطباعة
        bool matchesPrintStatus = true;
        if (selectedPrintStatusFilter != 'الكل') {
          final printStatus = _extractFlexibleValue(record,
              specificKeys: const ['تم الطباعة', 'Is Printed', 'حالة الطباعة'],
              containsPatterns: const ['طباعة', 'طباع', 'print', 'printed']);

          if (selectedPrintStatusFilter == 'تم') {
            matchesPrintStatus = _isPrintedStatus(printStatus);
          } else if (selectedPrintStatusFilter == 'لم يتم') {
            matchesPrintStatus = !_isPrintedStatus(printStatus);
          }
        }

        // تصفية حالة الواتساب مع debug logging مفصل
        bool matchesWhatsAppStatus = true;
        if (selectedWhatsAppStatusFilter != 'الكل') {
          final whatsappStatus = _extractFlexibleValue(record,
              specificKeys: const [
                'تم إرسال الواتساب',
                'WhatsApp Sent',
                'حالة الواتساب'
              ],
              containsPatterns: const [
                'whats',
                'واتس',
                'واتساب'
              ]);

          // Debug logging للواتساب (فقط للسجلات القليلة الأولى لتجنب spam)
          final customerName = record['اسم العميل']?.toString() ?? 'غير محدد';
          if (allRecords.indexOf(record) < 5) {
            // فقط أول 5 سجلات
            print('🔍 فحص الواتساب للعميل: $customerName');
            print(
                '   - البيانات المتاحة: ${record.keys.take(10).join(', ')}...');
            print('   - قيمة الواتساب المستخرجة: "$whatsappStatus"');
            print('   - فلتر مطلوب: "$selectedWhatsAppStatusFilter"');
          }

          if (selectedWhatsAppStatusFilter == 'تم') {
            matchesWhatsAppStatus = _isWhatsAppStatus(whatsappStatus);
            if (allRecords.indexOf(record) < 5) {
              print('   - النتيجة (تم): $matchesWhatsAppStatus');
            }
          } else if (selectedWhatsAppStatusFilter == 'لم يتم') {
            matchesWhatsAppStatus = !_isWhatsAppStatus(whatsappStatus);
            if (allRecords.indexOf(record) < 5) {
              print('   - النتيجة (لم يتم): $matchesWhatsAppStatus');
            }
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
            matchesWhatsAppStatus;
      }).toList();

      // ترتيب النتائج من الأحدث إلى الأقدم
      filteredRecords.sort((a, b) {
        final dateTimeA = _parseRecordDateTime(a);
        final dateTimeB = _parseRecordDateTime(b);

        if (dateTimeA == null && dateTimeB == null) return 0;
        if (dateTimeA == null) return 1;
        if (dateTimeB == null) return -1;

        return dateTimeB.compareTo(dateTimeA);
      });

      print(
          '✅ انتهاء التصفية - عدد السجلات بعد التصفية: ${filteredRecords.length}');
    });
  }

  /// مسح التصفية
  void _clearFilters() {
    setState(() {
      searchQuery = '';
      selectedOperationFilter = 'الكل';
      selectedZoneFilter = 'الكل';
      selectedExecutorFilter = 'الكل'; // مسح فلتر منفذ العملية أيضاً
      selectedSubscriptionTypeFilter = 'الكل';
      selectedPaymentTypeFilter = 'الكل';
      selectedPrintStatusFilter = 'الكل';
      selectedWhatsAppStatusFilter = 'الكل';
      fromDate = null;
      toDate = null;
      fromTime = null;
      toTime = null;
      showFilters = false;
    });
    _applyFilters();
  }

  /// حساب المجموع الإجمالي
  double _calculateTotalAmount() {
    double total = 0.0;
    for (var record in filteredRecords) {
      final priceString = record['سعر الباقة']?.toString() ?? '0';
      final price = double.tryParse(priceString.replaceAll(',', '')) ?? 0.0;
      total += price;
    }
    return total;
  }

  /// تحليل التاريخ والوقت من السجل
  DateTime? _parseRecordDateTime(Map<String, dynamic> record) {
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

    String? timeStr;
    if (dateStr.contains(' في ')) {
      final parts = dateStr.split(' في ');
      if (parts.length == 2) {
        dateStr = parts[0].trim();
        timeStr = parts[1].trim();
      }
    }
    timeStr ??=
        (record['الوقت']?.toString() ?? record['Time']?.toString())?.trim();

    DateTime? dateOnly = DateTime.tryParse(dateStr);
    if (dateOnly == null) {
      final parts = dateStr.split('/');
      if (parts.length == 3) {
        try {
          int a = int.parse(parts[0]);
          int b = int.parse(parts[1]);
          int c = int.parse(parts[2]);
          if (a > 31) {
            dateOnly = DateTime(a, b, c);
          } else {
            dateOnly = DateTime(c, b, a);
          }
        } catch (_) {}
      }
    }
    if (dateOnly == null) return null;

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

  /// عرض تفاصيل السجل
  void _showRecordDetails(Map<String, dynamic> record) {
    String subscriptionNotes = _extractFlexibleValue(record,
        specificKeys: const [
          'ملاحظات الاشتراك',
          'Subscription Notes',
          'ملاحظات المشغل'
        ],
        containsPatterns: const [
          'ملاحظ',
          'note'
        ]);

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
                          Text('ملاحظات الاشتراك:',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade700)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(subscriptionNotes,
                          style: TextStyle(color: Colors.teal.shade800)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              ...record.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text('${entry.key}:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[700],
                                fontSize: 13)),
                      ),
                      Expanded(
                        child: Text(entry.value?.toString() ?? 'غير متوفر',
                            style: const TextStyle(
                                color: Colors.black87, fontSize: 13)),
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

  @override
  Widget build(BuildContext context) {
    final totalAmount = _calculateTotalAmount();

    return Scaffold(
      appBar: AppBar(
        title: Text('سجلات ${widget.userName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(showFilters ? Icons.filter_list_off : Icons.filter_list),
            tooltip: showFilters ? 'إخفاء التصفية' : 'إظهار التصفية',
            onPressed: () => setState(() => showFilters = !showFilters),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث البيانات',
            onPressed: _loadUserRecords,
          ),
        ],
      ),
      body: Column(
        children: [
          // عرض الفلاتر النشطة (إن وُجدت)
          if (widget.initialFilterCriteria != null &&
              widget.initialFilterCriteria!.hasActiveFilters)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(Icons.filter_list,
                      color: Colors.blue.shade700, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'الفلاتر النشطة: ${widget.initialFilterCriteria!.activeFiltersDescription}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          // شريط المعلومات والإحصائيات
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.deepPurple.shade600,
                  Colors.deepPurple.shade800
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.deepPurple.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCard(
                        'المجموع',
                        NumberFormat('#,###', 'ar').format(totalAmount),
                        'IQD',
                        Colors.green),
                    _buildStatCard('العدد', '${filteredRecords.length}', 'سجل',
                        Colors.blue),
                    _buildStatCard('الإجمالي', '${allRecords.length}', 'سجل',
                        Colors.orange),
                  ],
                ),
              ],
            ),
          ),

          // شريط البحث والتصفية
          if (showFilters) _buildFilterSection(),

          // شريط البحث السريع
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'البحث في السجلات...',
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => searchQuery = '');
                          _applyFilters();
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                setState(() => searchQuery = value);
                _applyFilters();
              },
            ),
          ),

          // قائمة السجلات
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredRecords.isEmpty
                    ? const Center(child: Text('لا توجد سجلات مطابقة'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: filteredRecords.length,
                        itemBuilder: (context, index) {
                          final record = filteredRecords[index];
                          return _buildRecordCard(record);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, String unit, MaterialColor color) {
    final isMobile = MediaQuery.of(context).size.width < 400;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.all(isMobile ? 8 : 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(title,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 10 : 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: isMobile ? 14 : 18,
                      fontWeight: FontWeight.bold)),
            ),
            Text(unit,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    final isNarrow = MediaQuery.of(context).size.width < 500;
    return Container(
      padding: EdgeInsets.all(isNarrow ? 12 : 16),
      color: Colors.grey[50],
      child: Column(
        children: [
          // الصف الأول: نوع العملية والزون
          if (isNarrow) ...[
            DropdownButtonFormField<String>(
              initialValue: selectedOperationFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'نوع العملية', border: OutlineInputBorder(), isDense: true),
              items: operationFilterOptions
                  .map((option) =>
                      DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                setState(() => selectedOperationFilter = value ?? 'الكل');
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedZoneFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'الزون', border: OutlineInputBorder(), isDense: true),
              items: zoneOptions
                  .map((option) =>
                      DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                setState(() => selectedZoneFilter = value ?? 'الكل');
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedExecutorFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'منفذ العملية', border: OutlineInputBorder(), isDense: true),
              items: executorOptions
                  .map((option) =>
                      DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                setState(() => selectedExecutorFilter = value ?? 'الكل');
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedSubscriptionTypeFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'نوع الاشتراك', border: OutlineInputBorder(), isDense: true),
              items: subscriptionTypeOptions
                  .map((option) =>
                      DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                setState(
                    () => selectedSubscriptionTypeFilter = value ?? 'الكل');
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedPaymentTypeFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'نوع الدفع', border: OutlineInputBorder(), isDense: true),
              items: ['الكل', 'نقد', 'آجل']
                  .map((option) =>
                      DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                setState(() => selectedPaymentTypeFilter = value ?? 'الكل');
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedPrintStatusFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'حالة الطباعة', border: OutlineInputBorder(), isDense: true),
              items: ['الكل', 'تم', 'لم يتم']
                  .map((option) =>
                      DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                setState(() => selectedPrintStatusFilter = value ?? 'الكل');
                _applyFilters();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedWhatsAppStatusFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'حالة الواتساب', border: OutlineInputBorder(), isDense: true),
              items: ['الكل', 'تم', 'لم يتم']
                  .map((option) =>
                      DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                setState(
                    () => selectedWhatsAppStatusFilter = value ?? 'الكل');
                _applyFilters();
              },
            ),
          ] else ...[
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedOperationFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'نوع العملية', border: OutlineInputBorder()),
                  items: operationFilterOptions
                      .map((option) =>
                          DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => selectedOperationFilter = value ?? 'الكل');
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedZoneFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'الزون', border: OutlineInputBorder()),
                  items: zoneOptions
                      .map((option) =>
                          DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => selectedZoneFilter = value ?? 'الكل');
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // الصف الثاني: منفذ العملية ونوع الاشتراك
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedExecutorFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'منفذ العملية', border: OutlineInputBorder()),
                  items: executorOptions
                      .map((option) =>
                          DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => selectedExecutorFilter = value ?? 'الكل');
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedSubscriptionTypeFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'نوع الاشتراك', border: OutlineInputBorder()),
                  items: subscriptionTypeOptions
                      .map((option) =>
                          DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) {
                    setState(
                        () => selectedSubscriptionTypeFilter = value ?? 'الكل');
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // الصف الثالث: نوع الدفع وحالة الطباعة
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedPaymentTypeFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'نوع الدفع', border: OutlineInputBorder()),
                  items: ['الكل', 'نقد', 'آجل']
                      .map((option) =>
                          DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => selectedPaymentTypeFilter = value ?? 'الكل');
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedPrintStatusFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'حالة الطباعة', border: OutlineInputBorder()),
                  items: ['الكل', 'تم', 'لم يتم']
                      .map((option) =>
                          DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) {
                    setState(() => selectedPrintStatusFilter = value ?? 'الكل');
                    _applyFilters();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // الصف الرابع: حالة الواتساب
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedWhatsAppStatusFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'حالة الواتساب', border: OutlineInputBorder()),
                  items: ['الكل', 'تم', 'لم يتم']
                      .map((option) =>
                          DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (value) {
                    setState(
                        () => selectedWhatsAppStatusFilter = value ?? 'الكل');
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // مساحة فارغة للتوازن
              const Expanded(child: SizedBox()),
            ],
          ),
          ],
          const SizedBox(height: 12),
          // أزرار التطبيق والمسح
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _applyFilters,
                  icon: const Icon(Icons.check),
                  label: const Text('تطبيق'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear),
                  label: const Text('مسح'),
                  style: ElevatedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(Map<String, dynamic> record) {
    final customerName = record['اسم العميل']?.toString() ??
        record['Customer Name']?.toString() ??
        'غير محدد';
    final planName = record['اسم الباقة']?.toString() ?? 'غير محدد';
    final totalPrice = record['سعر الباقة']?.toString() ?? '0';
    final operationType =
        _normalizeOperationType(record['نوع العملية']?.toString() ?? '');
    final paymentType = _derivePaymentType(record);
    final activationDate = record['تاريخ التفعيل']?.toString() ??
        record['التاريخ']?.toString() ??
        'غير محدد';

    final isCashPayment = paymentType.contains('نقد');
    final isCreditPayment = paymentType.contains('آجل');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isCashPayment
          ? Colors.green.shade50
          : isCreditPayment
              ? Colors.red.shade50
              : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showRecordDetails(record),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(customerName,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: operationType == 'شراء اشتراك جديد'
                          ? Colors.blue.shade100
                          : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(operationType,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: operationType == 'شراء اشتراك جديد'
                                ? Colors.blue.shade800
                                : Colors.orange.shade800)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الباقة: $planName',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('التاريخ: $activationDate',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                          '${NumberFormat('#,###', 'ar').format(double.tryParse(totalPrice.replaceAll(',', '')) ?? 0)} IQD',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCashPayment
                              ? Colors.green.shade200
                              : Colors.red.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(paymentType,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isCashPayment
                                    ? Colors.green.shade800
                                    : Colors.red.shade800)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
