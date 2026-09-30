/// وحدة العقارات لتطبيق الوكلاء (Flutter) — معزولة عزلاً تامّاً (قابلة للاستخراج
/// كتطبيق مستقل مستقبلاً، على غرار وحدة واتساب).
///
/// تُثري مشتركي SAS بعنوان وطني مولَّد (NPN + IQ-Pin يُرسَم QR)، صورة الدار،
/// نوع السكن/الملكية، والموقع. عقار واحد قد يضمّ عدّة اشتراكات (جدول ربط بالباكند).
///
/// منافذ المنصّة الوحيدة (تُستبدَل عند الاستخراج): `ApiCore`/`Session`/`PlatformConfig`
/// (نواة الشبكة والجلسة) وخطّ IBMPlexSansArabic المضمَّن (للّصاقة). لا شيء آخر مشترك.
///
/// الاستخدام: `PremisesListScreen(api: PremisesApi(staffApi.core))`.
library;

export 'models/premises.dart';
export 'api/premises_api.dart';
export 'print/premises_label.dart';
export 'ui/premises_list_screen.dart';
export 'ui/premises_detail_screen.dart';
export 'ui/premises_form_screen.dart';
