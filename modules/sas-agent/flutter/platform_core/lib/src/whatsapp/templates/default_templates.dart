/// القوالب المدمجة الافتراضية (عربية) — تذكير/تجديد/انتهاء.
///
/// تطابق أنواع قوالب الصدارة (reminder/renewed/expired) مع متغيّرات عربية.
/// المتغيّرات المتاحة: `{name}` `{username}` `{profile}` `{expiration}` `{days}`.
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
    title: 'تأكيد التجديد',
    builtin: true,
    body: 'مرحباً {name} ✅\n'
        'تم تجديد اشتراكك ({username}) بنجاح.\n'
        'صالح حتى {expiration}. نتمنّى لك تصفّحاً ممتعاً 🌐',
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
