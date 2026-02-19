import 'api_service.dart';

/// خدمة إحصائيات المناطق عبر VPS API
class ZoneStatisticsApiService {
  static ZoneStatisticsApiService? _instance;
  static ZoneStatisticsApiService get instance =>
      _instance ??= ZoneStatisticsApiService._internal();
  ZoneStatisticsApiService._internal();

  final ApiService _api = ApiService.instance;

  /// جلب إحصائيات جميع المناطق
  Future<List<Map<String, dynamic>>> getAll({String? search}) async {
    String url = '/zonestatistics';
    if (search != null && search.isNotEmpty) url += '?search=$search';

    final response = await _api.get(url);
    final data = response['data'];
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }
    // Check for wrapped items
    if (data is Map && data.containsKey('items')) {
      return List<Map<String, dynamic>>.from(data['items'] ?? []);
    }
    return [];
  }

  /// جلب ملخص إحصائي (مجاميع ومتوسطات)
  Future<Map<String, dynamic>> getSummary() async {
    final response = await _api.get('/zonestatistics/summary');
    final data = response['data'];
    if (data is Map<String, dynamic>) return data;
    return response;
  }

  /// إضافة إحصائية منطقة
  Future<Map<String, dynamic>> create({
    required String zoneName,
    required int fats,
    required int totalUsers,
    required int activeUsers,
    required int inactiveUsers,
    String? regionName,
    String? companyId,
  }) async {
    return await _api.post('/zonestatistics', body: {
      'ZoneName': zoneName,
      'Fats': fats,
      'TotalUsers': totalUsers,
      'ActiveUsers': activeUsers,
      'InactiveUsers': inactiveUsers,
      'RegionName': regionName,
      'CompanyId': companyId,
    });
  }

  /// إضافة إحصائيات بالجملة
  Future<Map<String, dynamic>> bulkCreate(
      List<Map<String, dynamic>> zones) async {
    return await _api.post('/zonestatistics/bulk', body: zones);
  }

  /// تحديث إحصائية منطقة
  Future<Map<String, dynamic>> update(
    int id, {
    required String zoneName,
    required int fats,
    required int totalUsers,
    required int activeUsers,
    required int inactiveUsers,
    String? regionName,
  }) async {
    return await _api.put('/zonestatistics/$id', body: {
      'ZoneName': zoneName,
      'Fats': fats,
      'TotalUsers': totalUsers,
      'ActiveUsers': activeUsers,
      'InactiveUsers': inactiveUsers,
      'RegionName': regionName,
    });
  }

  /// حذف إحصائية منطقة
  Future<void> delete(int id) async {
    await _api.delete('/zonestatistics/$id');
  }
}
