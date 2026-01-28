import 'package:flutter/material.dart';

/// فئة لحفظ معايير التصفية وتمريرها بين الصفحات
class FilterCriteria {
  final String searchQuery;
  final String selectedOperationFilter; // نوع العملية
  final String selectedZoneFilter; // الزون
  final String selectedExecutorFilter; // منفذ العملية
  final String selectedSubscriptionTypeFilter; // نوع الاشتراك
  final String selectedPaymentTypeFilter; // نوع الدفع (نقد / آجل)
  final String selectedPrintStatusFilter; // حالة الطباعة
  final String selectedWhatsAppStatusFilter; // حالة الواتساب
  final DateTime? fromDate;
  final DateTime? toDate;
  final TimeOfDay? fromTime; // تصفية من وقت محدد في يوم البداية فقط
  final TimeOfDay? toTime; // تصفية إلى وقت محدد في يوم النهاية
  final bool mergeSimilarAccounts; // دمج الأسماء المتطابقة

  // خصائص إضافية للمهام (Tasks)
  final String? status; // حالة المهمة
  final String? department; // القسم
  final String? priority; // الأولوية
  final String? technician; // الفني
  final String? searchText; // نص البحث
  final DateTime? startDate; // تاريخ البداية
  final DateTime? endDate; // تاريخ النهاية

  const FilterCriteria({
    this.searchQuery = '',
    this.selectedOperationFilter = 'الكل',
    this.selectedZoneFilter = 'الكل',
    this.selectedExecutorFilter = 'الكل',
    this.selectedSubscriptionTypeFilter = 'الكل',
    this.selectedPaymentTypeFilter = 'الكل',
    this.selectedPrintStatusFilter = 'الكل',
    this.selectedWhatsAppStatusFilter = 'الكل',
    this.fromDate,
    this.toDate,
    this.fromTime,
    this.toTime,
    this.mergeSimilarAccounts = false,
    this.status,
    this.department,
    this.priority,
    this.technician,
    this.searchText,
    this.startDate,
    this.endDate,
  });

  /// إنشاء نسخة محدثة من معايير التصفية
  FilterCriteria copyWith({
    String? searchQuery,
    String? selectedOperationFilter,
    String? selectedZoneFilter,
    String? selectedExecutorFilter,
    String? selectedSubscriptionTypeFilter,
    String? selectedPaymentTypeFilter,
    String? selectedPrintStatusFilter,
    String? selectedWhatsAppStatusFilter,
    DateTime? fromDate,
    DateTime? toDate,
    TimeOfDay? fromTime,
    TimeOfDay? toTime,
    bool? mergeSimilarAccounts,
    String? status,
    String? department,
    String? priority,
    String? technician,
    String? searchText,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return FilterCriteria(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedOperationFilter:
          selectedOperationFilter ?? this.selectedOperationFilter,
      selectedZoneFilter: selectedZoneFilter ?? this.selectedZoneFilter,
      selectedExecutorFilter:
          selectedExecutorFilter ?? this.selectedExecutorFilter,
      selectedSubscriptionTypeFilter:
          selectedSubscriptionTypeFilter ?? this.selectedSubscriptionTypeFilter,
      selectedPaymentTypeFilter:
          selectedPaymentTypeFilter ?? this.selectedPaymentTypeFilter,
      selectedPrintStatusFilter:
          selectedPrintStatusFilter ?? this.selectedPrintStatusFilter,
      selectedWhatsAppStatusFilter:
          selectedWhatsAppStatusFilter ?? this.selectedWhatsAppStatusFilter,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      fromTime: fromTime ?? this.fromTime,
      toTime: toTime ?? this.toTime,
      status: status ?? this.status,
      department: department ?? this.department,
      priority: priority ?? this.priority,
      technician: technician ?? this.technician,
      searchText: searchText ?? this.searchText,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      mergeSimilarAccounts: mergeSimilarAccounts ?? this.mergeSimilarAccounts,
    );
  }

  /// التحقق من وجود أي تصفية نشطة
  bool get hasActiveFilters {
    return searchQuery.isNotEmpty ||
        selectedOperationFilter != 'الكل' ||
        selectedZoneFilter != 'الكل' ||
        selectedExecutorFilter != 'الكل' ||
        selectedSubscriptionTypeFilter != 'الكل' ||
        selectedPaymentTypeFilter != 'الكل' ||
        selectedPrintStatusFilter != 'الكل' ||
        selectedWhatsAppStatusFilter != 'الكل' ||
        fromDate != null ||
        toDate != null ||
        fromTime != null ||
        toTime != null ||
        mergeSimilarAccounts;
  }

  /// نص وصفي لمعايير التصفية النشطة
  String get activeFiltersDescription {
    List<String> activeFilters = [];

    if (searchQuery.isNotEmpty) {
      activeFilters.add('البحث: "$searchQuery"');
    }
    if (selectedOperationFilter != 'الكل') {
      activeFilters.add('العملية: $selectedOperationFilter');
    }
    if (selectedZoneFilter != 'الكل') {
      activeFilters.add('الزون: $selectedZoneFilter');
    }
    if (selectedExecutorFilter != 'الكل') {
      activeFilters.add('المنفذ: $selectedExecutorFilter');
    }
    if (selectedSubscriptionTypeFilter != 'الكل') {
      activeFilters.add('نوع الاشتراك: $selectedSubscriptionTypeFilter');
    }
    if (selectedPaymentTypeFilter != 'الكل') {
      activeFilters.add('الدفع: $selectedPaymentTypeFilter');
    }
    if (fromDate != null || toDate != null) {
      String dateRange = '';
      if (fromDate != null && toDate != null) {
        dateRange =
            'من ${fromDate!.day}/${fromDate!.month} إلى ${toDate!.day}/${toDate!.month}';
      } else if (fromDate != null) {
        dateRange = 'من ${fromDate!.day}/${fromDate!.month}';
      } else if (toDate != null) {
        dateRange = 'إلى ${toDate!.day}/${toDate!.month}';
      }
      activeFilters.add('التاريخ: $dateRange');
    }
    if (mergeSimilarAccounts) {
      activeFilters.add('دمج الأسماء المتطابقة');
    }

    return activeFilters.isEmpty ? 'بلا تصفية' : activeFilters.join(' • ');
  }

  @override
  String toString() {
    return 'FilterCriteria{hasActiveFilters: $hasActiveFilters, description: "$activeFiltersDescription"}';
  }
}
