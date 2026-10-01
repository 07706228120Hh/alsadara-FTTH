/// القوالب المدمجة الافتراضية (عربية) — تذكير/تفعيل-تجديد/انتهاء.
///
/// تطابق أنواع قوالب الصدارة (reminder/renewed/expired) مع متغيّرات عربية.
/// المتغيّرات المتاحة:
/// الأساسية: `{name}` `{username}` `{profile}` `{expiration}` `{days}`
/// الغنية (بعد التفعيل المفوتر): `{plan}` `{price}` `{currency}` `{months}`
/// `{endDate}` `{paymentMethod}` `{activatedBy}`.
///
/// أي متغيّر مفقود يُستبدل بفراغ ويُنظَّف السطر (منطق [WaTemplate.render])، فتبقى
/// القوالب صالحة سواء وُفّرت الحقول الغنية أم لا.
library;

import '../models/wa_template.dart';

/// معرّفات القوالب المدمجة الثابتة.
class WaTemplateIds {
  static const reminder = 'reminder';
  static const renewed = 'renewed';
  static const expired = 'expired';
}

/// القوالب الافتراضية المدمجة (تُعاد للضبط، لا تُحذف).
const List<WaTemplate> kDefaultTemplates = [
  WaTemplate(
    id: WaTemplateIds.reminder,
    title: 'تذكير قرب الانتهاء',
    builtin: true,
    body: 'مرحباً {name} 👋\n'
        'اشتراكك ({username}) ينتهي بتاريخ {expiration}.\n'
        'يرجى التجديد لتفادي انقطاع خدمة الإنترنت. شكراً لك 🌐',
  ),
  WaTemplate(
    id: WaTemplateIds.renewed,
    title: 'تأكيد التفعيل/التجديد',
    builtin: true,
    // قالب غنيّ: يعرض الباقة/المدة/السعر/طريقة الدفع إن توفّرت، ويتقلّص بسلاسة
    // (تُنظَّف الأسطر الفارغة) عند غياب أيٍّ منها.
    body: 'مرحباً {name} ✅\n'
        'تم تفعيل/تجديد اشتراكك ({username}) بنجاح.\n'
        'الباقة: {plan}\n'
        'المدة: {months} شهر\n'
        'المبلغ المدفوع: {price} {currency} ({paymentMethod})\n'
        'صالح حتى {endDate}.\n'
        'نتمنّى لك تصفّحاً ممتعاً 🌐',
  ),
  WaTemplate(
    id: WaTemplateIds.expired,
    title: 'إشعار انتهاء',
    builtin: true,
    body: 'مرحباً {name} ⚠️\n'
        'انتهى اشتراكك ({username}) بتاريخ {expiration}.\n'
        'للاستمرار بالخدمة يرجى التجديد. نحن بخدمتك 🌐',
  ),
];

/// يبني رسالة تذكير تجديد جاهزة (دالة توافقية للنداءات القديمة).
String renewalReminderMessage({
  required String name,
  String expiration = '',
  String username = '',
}) {
  final tpl = kDefaultTemplates.firstWhere((t) => t.id == WaTemplateIds.reminder);
  return tpl.render({
    'name': name,
    'username': username,
    'expiration': expiration.split(' ').first,
  });
}
