/// أنماط إرسال واتساب المدعومة — تطابق تصميم منصّة الصدارة ({app, web, server, api})
/// ليكون التوسّع مستقبلاً (Meta API) مجرّد إضافة مُرسِل جديد لا إعادة بناء.
library;

/// نمط الإرسال. الحالي: `app` (wa.me يدوي) و`server` (خادم whatsapp-web.js محلي آلي).
/// المؤجّل: `web` (واجهة ويب مضمّنة) و`api` (Meta Cloud API الرسمي).
enum WaMode {
  /// يفتح تطبيق/موقع واتساب برسالة جاهزة — المستخدم يضغط «إرسال». مجاني، يدوي.
  app,

  /// واجهة واتساب-ويب مضمّنة مع إرسال شبه آلي (مؤجّل).
  web,

  /// خادم Node ذاتي (whatsapp-web.js) — إرسال جماعي آلي مجاني بعد مسح QR.
  server,

  /// Meta Cloud API الرسمي — الأعلى موثوقية (مؤجّل، يحتاج حساب أعمال موثّق).
  api;

  /// المفتاح المخزّن (يطابق أسماء الصدارة لسهولة الترحيل مستقبلاً).
  String get key => name;

  static WaMode fromKey(String? k) =>
      WaMode.values.firstWhere((m) => m.key == k, orElse: () => WaMode.app);

  /// العنوان العربي المعروض.
  String get label => switch (this) {
        WaMode.app => 'تطبيق واتساب (يدوي)',
        WaMode.web => 'واتساب ويب (مضمّن)',
        WaMode.server => 'خادم محلي (آلي)',
        WaMode.api => 'Meta الرسمي (API)',
      };

  /// وصف موجز يُعرَض في الإعدادات.
  String get description => switch (this) {
        WaMode.app => 'مجاني وبسيط — يفتح واتساب لكل رسالة وتضغط أنت «إرسال».',
        WaMode.web => 'واجهة واتساب-ويب مدمجة (قيد التطوير).',
        WaMode.server => 'إرسال جماعي آلي مجاني عبر خادم محلي — يتطلّب مسح رمز QR مرّة.',
        WaMode.api => 'قناة Meta الرسمية — قوالب معتمدة وموثوقية عالية (قيد التطوير).',
      };

  /// هل النمط جاهز للاستخدام الآن؟ (web/api مؤجّلان).
  bool get isAvailable => this == WaMode.app || this == WaMode.server;
}
