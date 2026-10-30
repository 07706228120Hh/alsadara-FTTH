/// نظام تصميم الصدارة الموحّد — الآن مصدره حزمة sadara_design المشتركة.
///
/// الجوهر (الرموز/الثيم/المكوّنات) يعيش في `package:sadara_design`؛ هذه الملفات
/// في `frontend/` أصبحت إعادة تصدير فقط، فيبقى كل استيراد قديم يعمل بلا تغيير،
/// والمصدر الوحيد هو الحزمة (لا مزامنة يدوية).
library;

export 'package:sadara_design/sadara_design.dart';

// مكوّنات الدخول ثلاثية الأبعاد خاصة بسطح المكتب (تعتمد webview) — تبقى محلية.
export 'components/sd_login_scene.dart';
export 'components/sd_login_3d.dart';
