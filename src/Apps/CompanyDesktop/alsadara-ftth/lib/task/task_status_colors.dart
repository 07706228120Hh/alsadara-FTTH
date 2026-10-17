import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../frontend/tokens/sd_colors.dart' show SdColors;

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

  static const Color open = SdColors.info; // مفتوحة
  static const Color inProgress = SdColors.warning; // قيد التنفيذ
  static const Color completed = SdColors.success; // مكتملة
  static const Color cancelled = SdColors.danger; // ملغية

  // حالات ثانوية (يحافظ عليها بعض الشاشات)
  static const Color underReview = SdColors.platformBase; // قيد المراجعة
  static const Color approved = SdColors.accent; // موافق عليه
  static const Color assigned = SdColors.platformBase; // معينة
  static const Color pending = SdColors.warning; // معلقة

  static const Color unknown = SdColors.faint; // افتراضي

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

/// تطبيع اسم (فني/مستخدم) لمطابقة موحّدة في شاشات المهام.
///
/// يقصّ المسافات الطرفية ويدمج أي تسلسل مسافات/فراغات داخلية (بما فيها
/// المسافات المتعددة والـtabs والأسطر) إلى مسافة واحدة. يمنع سقوط مهام بسبب
/// اختلاف المسافات بين الاسم المخزّن والاسم المُقارن به.
///
/// ملاحظة: بصري/مطابقة فقط — لا يغيّر منطق التصنيف أو الحالة. عند إرساله
/// للخادم كـ`assignee` نكتفي بالتطبيع نفسه (لا نغيّر دلالة الاسم).
String normalizeName(String name) {
  return name.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// تنسيق المبالغ بفواصل الآلاف لعرض « د.ع» في شاشات المهام.
///
/// يستخدم `NumberFormat` (حزمة intl المستخدمة أصلاً للتواريخ).
final NumberFormat _taskAmountFormat = NumberFormat.decimalPattern('en');

/// يعيد المبلغ منسّقاً بفواصل الآلاف (بدون كسور)، مثل: 1,250,000.
String formatTaskAmount(num value) {
  return _taskAmountFormat.format(value.round());
}
