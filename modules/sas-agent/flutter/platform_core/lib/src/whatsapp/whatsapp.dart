/// وحدة واتساب لتطبيق الوكلاء — مستقلّة ومجزّأة.
///
/// معماريّاً: واجهة `WaSender` مجرّدة بأنماط `{app, web, server, api}` (كنظام
/// الصدارة). المُفعَّل الآن: `app` (wa.me يدوي) و`server` (خادم whatsapp-web.js
/// محلي آلي). المؤجّل: `api` (Meta Cloud) قابس جاهز يُملأ لاحقاً بلا إعادة بناء.
///
/// هذا الملف هو الواجهة العامة الوحيدة للوحدة — استورد `package:platform_core`
/// واستعمل الرموز أدناه؛ لا تعتمد على ملفات الوحدة الداخلية مباشرة.
library;

// النواة
export 'core/wa_phone.dart';
export 'core/wa_mode.dart';
export 'core/wa_sender.dart';

// النماذج
export 'models/wa_recipient.dart';
export 'models/wa_message.dart';
export 'models/wa_template.dart';

// المُرسِلات
export 'senders/app_sender.dart'; // + openWhatsApp (توافقية)
export 'senders/server_sender.dart';
export 'senders/api_sender.dart'; // قابس Meta المؤجّل

// القوالب
export 'templates/default_templates.dart'; // + renewalReminderMessage (توافقية)
export 'templates/template_store.dart';

// الإعداد ومصنع المُرسِل
export 'config/wa_settings.dart';

// مُشغّل الخادم المحلي المدمج (ويندوز)
export 'server/wa_server_launcher.dart';

// الواجهة
export 'ui/wa_bulk_sheet.dart';
export 'ui/wa_templates_screen.dart';
export 'ui/wa_settings_screen.dart';
