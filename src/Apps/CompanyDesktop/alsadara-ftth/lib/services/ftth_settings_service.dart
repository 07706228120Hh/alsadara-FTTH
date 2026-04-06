import 'api/api_client.dart';
import 'api/api_config.dart';

/// خدمة إعدادات مزامنة FTTH — تتواصل مع VPS API
class FtthSettingsService {
  static final _client = ApiClient.instance;

  /// جلب الإعدادات الحالية
  static Future<Map<String, dynamic>?> getSettings(String companyId) async {
    try {
      final res = await _client.get(
        ApiConfig.companyFtthSettings(companyId),
        (json) => json as Map<String, dynamic>,
        useInternalKey: true,
      );
      if (res.success && res.data != null) return res.data;
    } catch (_) {}
    return null;
  }

  /// حفظ بيانات الدخول والإعدادات
  static Future<bool> saveSettings({
    required String companyId,
    required String ftthUsername,
    required String ftthPassword,
    int syncIntervalMinutes = 60,
    bool isAutoSyncEnabled = true,
    int syncStartHour = 6,
    int syncEndHour = 23,
  }) async {
    try {
      final res = await _client.post(
        ApiConfig.companyFtthSettingsSave,
        {
          'companyId': companyId,
          'ftthUsername': ftthUsername,
          'ftthPassword': ftthPassword,
          'syncIntervalMinutes': syncIntervalMinutes,
          'isAutoSyncEnabled': isAutoSyncEnabled,
          'syncStartHour': syncStartHour,
          'syncEndHour': syncEndHour,
        },
        (json) => json,
        useInternalKey: true,
      );
      return res.success;
    } catch (_) {
      return false;
    }
  }

  /// اختبار الاتصال
  static Future<Map<String, dynamic>> testConnection(String companyId) async {
    try {
      final res = await _client.post(
        ApiConfig.companyFtthSettingsTest(companyId),
        null,
        (json) => json as Map<String, dynamic>,
        useInternalKey: true,
      );
      if (res.success && res.data != null) return res.data!;
      return {'success': false, 'error': 'فشل الاتصال'};
    } catch (e) {
      return {'success': false, 'error': 'فشل الاتصال بالخادم'};
    }
  }

  /// جلب حالة المزامنة
  static Future<Map<String, dynamic>?> getSyncStatus(String companyId) async {
    try {
      final res = await _client.get(
        ApiConfig.companyFtthSyncStatus(companyId),
        (json) => json as Map<String, dynamic>,
        useInternalKey: true,
      );
      if (res.success && res.data != null) return res.data;
    } catch (_) {}
    return null;
  }

  /// تشغيل مزامنة يدوية
  static Future<bool> triggerSync(String companyId) async {
    try {
      final res = await _client.post(
        ApiConfig.companyFtthTriggerSync(companyId),
        null,
        (json) => json,
        useInternalKey: true,
      );
      return res.success;
    } catch (_) {
      return false;
    }
  }

  /// إلغاء المزامنة الجارية
  static Future<bool> cancelSync(String companyId) async {
    try {
      final res = await _client.post(
        ApiConfig.companyFtthCancelSync(companyId),
        null,
        (json) => json,
        useInternalKey: true,
      );
      return res.success;
    } catch (_) {
      return false;
    }
  }

  /// جلب سجل المزامنات
  static Future<List<Map<String, dynamic>>> getSyncLogs(String companyId, {int limit = 50}) async {
    try {
      final res = await _client.get(
        '/company-ftth-settings/$companyId/sync-logs?limit=$limit',
        (json) => json,
        useInternalKey: true,
      );
      if (res.success && res.data != null) {
        if (res.data is List) return List<Map<String, dynamic>>.from(res.data);
      }
    } catch (_) {}
    return [];
  }

  /// حذف سجل مزامنة واحد
  static Future<bool> deleteSyncLog(String companyId, String logId) async {
    try {
      final res = await _client.delete(
        ApiConfig.companyFtthDeleteSyncLog(companyId, logId),
        (json) => json,
        useInternalKey: true,
      );
      return res.success;
    } catch (_) {
      return false;
    }
  }

  /// جلب إحصائيات البيانات الناقصة
  static Future<Map<String, dynamic>?> getMissingStats(String companyId) async {
    try {
      final res = await _client.get(
        ApiConfig.companyFtthMissingStats(companyId),
        (json) => json as Map<String, dynamic>,
        useInternalKey: true,
      );
      if (res.success && res.data != null) return res.data;
    } catch (_) {}
    return null;
  }

  /// إعادة جلب البيانات الناقصة (FAT + هواتف)
  static Future<Map<String, dynamic>?> refetchMissing(String companyId) async {
    try {
      final res = await _client.post(
        ApiConfig.companyFtthRefetchMissing(companyId),
        null,
        (json) => json as Map<String, dynamic>,
        useInternalKey: true,
      );
      if (res.success && res.data != null) return res.data;
    } catch (_) {}
    return null;
  }

  /// إحصائيات تفصيلية مع نسب الاكتمال
  static Future<Map<String, dynamic>?> getDetailedStats(String companyId) async {
    try {
      final res = await _client.get(
        ApiConfig.companyFtthDetailedStats(companyId),
        (json) => json as Map<String, dynamic>,
        useInternalKey: true,
      );
      if (res.success && res.data != null) return res.data;
    } catch (_) {}
    return null;
  }

  /// مسح بيانات محددة (all, phones, details, subscriptions)
  static Future<Map<String, dynamic>?> clearData(String companyId, String type) async {
    try {
      final res = await _client.post(
        ApiConfig.companyFtthClearData(companyId),
        {'type': type},
        (json) => json as Map<String, dynamic>,
        useInternalKey: true,
      );
      if (res.success && res.data != null) return res.data;
    } catch (_) {}
    return null;
  }

  /// حذف كل سجلات المزامنة
  static Future<bool> deleteAllSyncLogs(String companyId) async {
    try {
      final res = await _client.delete(
        ApiConfig.companyFtthDeleteAllSyncLogs(companyId),
        (json) => json,
        useInternalKey: true,
      );
      return res.success;
    } catch (_) {
      return false;
    }
  }
}
