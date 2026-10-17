/// ⚠️ ملف المفاتيح السرية — لا تضع أي قيمة سرّية حقيقية هنا (الملف متتبَّع في Git).
///
/// القيم تُحمَّل من:
/// - Environment Variables
/// - Secure Storage
/// - ملف secrets.json محلي
///
/// المرحلة 0 / A2: أُزيل المفتاح الداخلي (internal API key) نهائياً من التطبيق — كل نداءات خادم
/// الصدارة تُصادَق بتوكن JWT للمستخدم (انظر `services/api/vps_auth_headers.dart`). المفتاح الداخلي
/// يبقى سرّاً خادمياً فقط (n8n/السكربتات) ولا يجوز إعادته إلى كود التطبيق.
library;

import 'dart:io';

/// مدير المفاتيح السرية
class AppSecrets {
  // Singleton pattern
  static final AppSecrets _instance = AppSecrets._internal();
  static AppSecrets get instance => _instance;
  AppSecrets._internal();

  // ============================================
  // التهيئة
  // ============================================

  bool _initialized = false;

  /// تهيئة المفاتيح من Environment Variables
  Future<void> initialize() async {
    if (_initialized) return;

    _googleDriveApiKey = Platform.environment['GOOGLE_DRIVE_API_KEY'] ??
        _defaultGoogleDriveApiKey;

    _initialized = true;
  }

  // ============================================
  // القيم الافتراضية (فارغة — لا أسرار في الكود)
  // ============================================

  static const String _defaultGoogleDriveApiKey = ''; // فارغ - يجب تعيينه

  // ============================================
  // القيم الفعلية
  // ============================================

  String _googleDriveApiKey = _defaultGoogleDriveApiKey;

  // ============================================
  // Getters
  // ============================================

  /// مفتاح Google Drive API
  String get googleDriveApiKey => _googleDriveApiKey;

  // ============================================
  // التحقق من الأمان
  // ============================================

  /// لا توجد مفاتيح خادمية مضمّنة في التطبيق بعد الآن.
  bool get isSecure => true;

  /// (للتوافق مع main.dart) لا شيء للتحذير منه — لا مفاتيح افتراضية مضمّنة.
  void warnIfInsecure() {}
}

/// للوصول السريع
AppSecrets get appSecrets => AppSecrets.instance;
