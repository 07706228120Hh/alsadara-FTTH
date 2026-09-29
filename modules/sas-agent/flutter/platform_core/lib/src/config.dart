/// إعدادات مشتركة — تُمرَّر وقت البناء عبر `--dart-define`:
///   flutter run --dart-define=API_BASE=http://10.0.2.2:8000      (محاكي أندرويد)
///   flutter build web --dart-define=API_BASE=https://api.example.iq --dart-define=APP_VERSION=1.2.0
/// بلا تعريف: http://127.0.0.1:8000 (ويب/ويندوز محلي).
class PlatformConfig {
  static const String apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:8000');
  static const String platformName = 'تطبيق الوكلاء';
  static const String platformNameEn = 'Aluklaa';
  static const Duration httpTimeout = Duration(seconds: 25);

  /// إصدار التطبيق المعروض في شاشة الدخول (يُمرَّر من البناء).
  static const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  /// رابط الدعم الفني (واتساب/بريد) — يظهر في شاشة الدخول.
  static const String supportUrl = String.fromEnvironment('SUPPORT_URL', defaultValue: '');

  /// رابط البوّابة الرئيسية (لتوجيه المستخدم إلى التطبيق الصحيح عند دخول حساب من نوع آخر).
  static const String portalUrl = String.fromEnvironment('PORTAL_URL', defaultValue: '/');

  /// بيئة تطوير؟ (عنوان محلي) — تُظهر شارة «بيئة تطوير» ورمز OTP التجريبي.
  static bool get isDevEnvironment =>
      apiBase.contains('127.0.0.1') || apiBase.contains('localhost') || apiBase.contains('10.0.2.2');
}
