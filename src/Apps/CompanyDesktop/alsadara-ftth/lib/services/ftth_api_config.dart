/// مصدر الحقيقة الموحّد لعنوان واجهة FTTH (admin.ftth.iq).
///
/// كل نطاقات ftth.iq الفعّالة محميّة بتحدّي Cloudflare على `admin.ftth.iq`.
/// نطاق `api.ftth.iq` نطاق Cloudflare منفصل يُسقط اتصال Dart، لذا المضيف
/// القانوني الموحّد للتطبيق هو `admin.ftth.iq` (نفس backend ونملك تصريح
/// cf_clearance له). أي تغيير مستقبلي للمضيف يتم من هنا فقط.
///
/// الاستخدام: `'${FtthApi.api}/customers/subscriptions?...'` بدل كتابة
/// `https://admin.ftth.iq/api/...` أو `https://api.ftth.iq/api/...` يدوياً.
library;

class FtthApi {
  FtthApi._();

  /// المضيف القانوني الموحّد (بدون بروتوكول).
  static const String host = 'admin.ftth.iq';

  /// المضيف القديم المهجور — يُعاد توجيهه إلى [host].
  static const String legacyHost = 'api.ftth.iq';

  /// الأصل الكامل: `https://admin.ftth.iq`.
  static const String origin = 'https://$host';

  /// جذر الـ API: `https://admin.ftth.iq/api`.
  static const String api = '$origin/api';

  /// هل المضيف ضمن نطاق ftth.iq (admin/api/dashboard...)؟
  static bool isFtthHost(String h) => h == 'ftth.iq' || h.endsWith('.ftth.iq');

  /// يحوّل أي رابط يستخدم المضيف القديم `api.ftth.iq` إلى المضيف الموحّد.
  /// آمن على الروابط التي تستخدم [host] أصلاً (يُعيدها كما هي).
  static String normalize(String url) =>
      url.replaceFirst('https://$legacyHost', origin);
}
