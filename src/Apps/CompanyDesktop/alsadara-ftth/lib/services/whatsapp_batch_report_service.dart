import 'api/api_client.dart';

/// خدمة تقارير الإرسال الجماعي — تستخدم PostgreSQL عبر API
class WhatsAppBatchReportService {
  /// جلب التقارير
  static Future<List<Map<String, dynamic>>> getBatchReports({
    int limit = 50,
  }) async {
    try {
      final response = await ApiClient.instance.get(
        '/whatsapp/batch-reports?limit=$limit',
        (data) => data,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final list = (response.data['data'] as List?) ?? [];
        return list
            .map((e) =>
                e is Map<String, dynamic> ? e : <String, dynamic>{})
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// حذف تقرير
  static Future<bool> deleteBatchReport(int id) async {
    try {
      final response = await ApiClient.instance.delete(
        '/whatsapp/batch-reports/$id',
        (data) => data,
        useInternalKey: true,
      );
      return response.isSuccess;
    } catch (e) {
      return false;
    }
  }
}
