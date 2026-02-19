/// ⚠️ ملف المفاتيح السرية - يجب عدم رفعه إلى Git
///
/// هذا الملف يحتوي على قيم افتراضية للتطوير فقط.
/// في بيئة الإنتاج، يجب تحميل القيم من:
/// - Environment Variables
/// - Secure Storage
/// - ملف secrets.json محلي
///
/// 🔒 تم إضافة هذا الملف إلى .gitignore
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

    // محاولة تحميل من Environment Variables أولاً
    _internalApiKey = Platform.environment['SADARA_INTERNAL_API_KEY'] ??
        _defaultInternalApiKey;
    _googleDriveApiKey = Platform.environment['GOOGLE_DRIVE_API_KEY'] ??
        _defaultGoogleDriveApiKey;

    _initialized = true;
  }

  // ============================================
  // القيم الافتراضية (للتطوير فقط)
  // ⚠️ يجب تغييرها في الإنتاج
  // ============================================

  static const String _defaultInternalApiKey =
      'sadara-internal-2024-secure-key';
  static const String _defaultGoogleDriveApiKey = ''; // فارغ - يجب تعيينه

  // ============================================
  // القيم الفعلية
  // ============================================

  String _internalApiKey = _defaultInternalApiKey;
  String _googleDriveApiKey = _defaultGoogleDriveApiKey;

  // ============================================
  // Getters
  // ============================================

  /// مفتاح API الداخلي للاتصال بـ Sadara Backend
  String get internalApiKey => _internalApiKey;

  /// مفتاح Google Drive API
  String get googleDriveApiKey => _googleDriveApiKey;

  // ============================================
  // التحقق من الأمان
  // ============================================

  /// هل المفاتيح آمنة (ليست القيم الافتراضية)؟
  bool get isSecure {
    return _internalApiKey != _defaultInternalApiKey &&
        _internalApiKey.isNotEmpty;
  }

  /// طباعة تحذير إذا كانت المفاتيح افتراضية
  void warnIfInsecure() {
    if (!isSecure) {
      print('⚠️ تحذير أمني: يتم استخدام مفاتيح API الافتراضية!');
      print('⚠️ يجب تعيين SADARA_INTERNAL_API_KEY في Environment Variables');
    }
  }
}

/// للوصول السريع
AppSecrets get appSecrets => AppSecrets.instance;
