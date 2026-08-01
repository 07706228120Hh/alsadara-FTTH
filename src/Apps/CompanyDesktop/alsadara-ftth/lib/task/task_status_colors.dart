import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// ألوان حالات المهام — مصدر موحّد لكل شاشات المهام.
///
/// الدلالة الثابتة:
///   مفتوحة  → أزرق   (0xFF2196F3)
///   قيد التنفيذ → برتقالي (0xFFFF9800)
///   مكتملة  → أخضر   (0xFF4CAF50)
///   ملغية   → أحمر   (0xFFE53935)
///
/// مرادفات مدعومة: جديدة → أزرق، مرفوضة → أحمر.
/// حالات إضافية تحافظ على دلالتها السابقة (قيد المراجعة/موافق عليه/معينة/معلقة).
/// أي حالة غير معروفة → رمادي.
///
/// ملاحظة: هذا الملف بصري بحت ولا يغيّر أي منطق تصنيف/فلترة/تعيين للحالة.
class TaskStatusColors {
  const TaskStatusColors._();

  static const Color open = Color(0xFF2196F3); // مفتوحة
  static const Color inProgress = Color(0xFFFF9800); // قيد التنفيذ
  static const Color completed = Color(0xFF4CAF50); // مكتملة
  static const Color cancelled = Color(0xFFE53935); // ملغية

  // حالات ثانوية (يحافظ عليها بعض الشاشات)
  static const Color underReview = Color(0xFF9B59B6); // قيد المراجعة
  static const Color approved = Color(0xFF009688); // موافق عليه
  static const Color assigned = Color(0xFF8E44AD); // معينة
  static const Color pending = Color(0xFFF39C12); // معلقة

  static const Color unknown = Color(0xFF95A5A6); // افتراضي

  /// يعيد اللون المناسب للحالة العربية (مع مرادفاتها).
  static Color colorFor(String status) {
    switch (status.trim()) {
      case 'مفتوحة':
      case 'جديدة':
        return open;
      case 'قيد التنفيذ':
        return inProgress;
      case 'مكتملة':
        return completed;
      case 'ملغية':
      case 'مرفوضة':
        return cancelled;
      case 'قيد المراجعة':
        return underReview;
      case 'موافق عليه':
        return approved;
      case 'معينة':
        return assigned;
      case 'معلقة':
        return pending;
      default:
        return unknown;
    }
  }
}

/// تنسيق المبالغ بفواصل الآلاف لعرض « د.ع» في شاشات المهام.
///
/// يستخدم `NumberFormat` (حزمة intl المستخدمة أصلاً للتواريخ).
final NumberFormat _taskAmountFormat = NumberFormat.decimalPattern('en');

/// يعيد المبلغ منسّقاً بفواصل الآلاف (بدون كسور)، مثل: 1,250,000.
String formatTaskAmount(num value) {
  return _taskAmountFormat.format(value.round());
}
