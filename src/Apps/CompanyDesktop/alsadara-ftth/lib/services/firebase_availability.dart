/// خدمة التحقق من توفر Firebase
/// على Android بدون google-services.json لن يعمل Firebase
/// التطبيق يعمل بشكل طبيعي بدون Firebase (يستخدم VPS API)
library;

import 'package:firebase_core/firebase_core.dart';

class FirebaseAvailability {
  FirebaseAvailability._();

  static bool _initialized = false;

  /// هل تم تهيئة Firebase بنجاح؟
  static bool get isAvailable => _initialized;

  /// تسجيل نجاح التهيئة
  static void markInitialized() => _initialized = true;

  /// التحقق من أن Firebase جاهز، وإلا يرمي استثناء واضح
  static FirebaseApp get app {
    if (!_initialized) {
      throw FirebaseException(
        plugin: 'core',
        message: 'Firebase غير متاح على هذه المنصة',
      );
    }
    return Firebase.app();
  }
}
