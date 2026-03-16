import 'package:flutter/foundation.dart';
import 'api/api_client.dart';

/// خدمة إحصائيات المناطق عبر VPS API
class ZoneStatisticsApiService {
  static ZoneStatisticsApiService? _instance;
  static ZoneStatisticsApiService get instance =>
      _instance ??= ZoneStatisticsApiService._internal();
  ZoneStatisticsApiService._internal();

  static final ApiClient _client = ApiClient.instance;

  /// جلب إحصائيات جميع المناطق
  Future<List<Map<String, dynamic>>> getAll({String? search}) async {
    String url = '/zonestatistics';
    if (search != null && search.isNotEmpty) url += '?search=$search';

    final response = await _client.get(
      url,
      (json) => json,
      useInternalKey: true,
    );

    if (response.success && response.data != null) {
      final data = response.data;
      if (data is List) {
        return List<Map<String, dynamic>>.from(
            data.map((e) => Map<String, dynamic>.from(e)));
      }
      if (data is Map && data['items'] is List) {
        return List<Map<String, dynamic>>.from(
            (data['items'] as List).map((e) => Map<String, dynamic>.from(e)));
      }
    }
    return [];
  }

  /// جلب ملخص إحصائي (مجاميع ومتوسطات)
  Future<Map<String, dynamic>> getSummary() async {
    final response = await _client.get(
      '/zonestatistics/summary',
      (json) => json,
      useInternalKey: true,
    );

    if (response.success && response.data != null) {
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
    }
    return {};
  }

  /// إضافة إحصائية منطقة
  Future<Map<String, dynamic>?> create({
    required String zoneName,
    required int fats,
    required int totalUsers,
    required int activeUsers,
    required int inactiveUsers,
    String? regionName,
    String? companyId,
  }) async {
    final response = await _client.post(
      '/zonestatistics',
      {
        'ZoneName': zoneName,
        'Fats': fats,
        'TotalUsers': totalUsers,
        'ActiveUsers': activeUsers,
        'InactiveUsers': inactiveUsers,
        'RegionName': regionName,
        'CompanyId': companyId,
      },
      (json) => json,
      useInternalKey: true,
    );

    if (response.success && response.data != null) {
      return response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : null;
    }
    return null;
  }

  /// إضافة إحصائيات بالجملة
  Future<Map<String, dynamic>?> bulkCreate(
      List<Map<String, dynamic>> zones) async {
    final response = await _client.post(
      '/zonestatistics/bulk',
      zones,
      (json) => json,
      useInternalKey: true,
    );

    if (response.success && response.data != null) {
      return response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : null;
    }
    return null;
  }

  /// تحديث إحصائية منطقة
  Future<bool> update(
    int id, {
    required String zoneName,
    required int fats,
    required int totalUsers,
    required int activeUsers,
    required int inactiveUsers,
    String? regionName,
  }) async {
    final response = await _client.put(
      '/zonestatistics/$id',
      {
        'ZoneName': zoneName,
        'Fats': fats,
        'TotalUsers': totalUsers,
        'ActiveUsers': activeUsers,
        'InactiveUsers': inactiveUsers,
        'RegionName': regionName,
      },
      (json) => json,
      useInternalKey: true,
    );

    return response.success;
  }

  /// مزامنة الزونات من FTTH (upsert - إضافة الجديد وتحديث Fats فقط للموجود)
  Future<Map<String, dynamic>> syncZones(
      List<Map<String, dynamic>> zones) async {
    try {
      final response = await _client.post(
        '/zonestatistics/sync',
        zones,
        (json) => json,
        useInternalKey: true,
      );

      if (kDebugMode) {
        print('📡 ZoneSync response: success=${response.success}, '
            'data=${response.data}');
      }

      if (response.success && response.data != null) {
        if (response.data is Map<String, dynamic>) {
          return response.data as Map<String, dynamic>;
        }
      }
      return {'error': response.message ?? 'فشل المزامنة'};
    } catch (e) {
      if (kDebugMode) print('❌ خطأ في مزامنة الزونات: $e');
      return {'error': e.toString()};
    }
  }

  /// حذف إحصائية منطقة
  Future<bool> delete(int id) async {
    final response = await _client.delete(
      '/zonestatistics/$id',
      (json) => json,
      useInternalKey: true,
    );

    return response.success;
  }
}
