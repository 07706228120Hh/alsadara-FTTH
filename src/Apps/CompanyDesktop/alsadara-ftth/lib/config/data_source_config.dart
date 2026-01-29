/// إعدادات مصدر البيانات
/// يسمح بالتبديل بين Firebase و VPS API
library;

/// مصدر البيانات المستخدم
enum DataSource {
  /// Firebase Firestore (قديم)
  firebase,

  /// VPS API (جديد - موصى به)
  vpsApi,
}

/// إعدادات مصدر البيانات
class DataSourceConfig {
  /// مصدر البيانات الحالي
  /// ⚠️ غير هذا القيمة للتبديل بين Firebase و VPS API
  static const DataSource currentSource = DataSource.vpsApi;

  /// هل نستخدم VPS API؟
  static bool get useVpsApi => currentSource == DataSource.vpsApi;

  /// هل نستخدم Firebase؟
  static bool get useFirebase => currentSource == DataSource.firebase;

  /// الوصف النصي للمصدر الحالي
  static String get sourceDescription {
    switch (currentSource) {
      case DataSource.firebase:
        return 'Firebase Firestore';
      case DataSource.vpsApi:
        return 'VPS API (PostgreSQL)';
    }
  }
}
