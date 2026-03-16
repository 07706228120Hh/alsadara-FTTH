import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';

/// خدمة إدارة مشتركي IPTV عبر VPS API
class IptvService {
  static final ApiClient _client = ApiClient.instance;

  /// جلب كل مشتركي IPTV لشركة محددة
  static Future<List<Map<String, dynamic>>> getAll(String companyId) async {
    try {
      final response = await _client.get(
        '${ApiConfig.iptvSubscribers}?companyId=$companyId',
        (json) => json,
        useInternalKey: true,
      );

      if (response.success && response.data != null) {
        final data = response.data;
        if (data is Map && data['data'] != null) {
          return List<Map<String, dynamic>>.from(
            (data['data'] as List).map((e) => Map<String, dynamic>.from(e)),
          );
        }
        if (data is List) {
          return List<Map<String, dynamic>>.from(
            data.map((e) => Map<String, dynamic>.from(e)),
          );
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('خطأ في جلب مشتركي IPTV');
      return [];
    }
  }

  /// إنشاء مشترك IPTV جديد
  static Future<Map<String, dynamic>?> create({
    required String companyId,
    String? subscriptionId,
    required String customerName,
    String? phone,
    String? iptvUsername,
    String? iptvPassword,
    String? iptvCode,
    DateTime? activationDate,
    int durationMonths = 1,
    bool isActive = true,
    String? location,
    String? notes,
  }) async {
    try {
      final body = {
        'companyId': companyId,
        if (subscriptionId != null && subscriptionId.isNotEmpty)
          'subscriptionId': subscriptionId,
        'customerName': customerName,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (iptvUsername != null && iptvUsername.isNotEmpty)
          'iptvUsername': iptvUsername,
        if (iptvPassword != null && iptvPassword.isNotEmpty)
          'iptvPassword': iptvPassword,
        if (iptvCode != null && iptvCode.isNotEmpty) 'iptvCode': iptvCode,
        if (activationDate != null)
          'activationDate': activationDate.toUtc().toIso8601String(),
        'durationMonths': durationMonths,
        'isActive': isActive,
        if (location != null && location.isNotEmpty) 'location': location,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };

      if (kDebugMode) print('📡 IPTV Create body: $body');

      final response = await _client.post(
        ApiConfig.iptvSubscribers,
        body,
        (json) => json,
        useInternalKey: true,
      );

      if (kDebugMode) {
        print('📡 IPTV Create response: success=${response.success}, '
            'statusCode=${response.statusCode}, '
            'data=${response.data}, '
            'errors=${response.errors}, message=${response.message}');
      }

      if (response.success && response.data != null) {
        final data = response.data;
        if (data is Map && data['data'] != null) {
          return Map<String, dynamic>.from(data['data']);
        }
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ خطأ في إنشاء مشترك IPTV: $e');
      return null;
    }
  }

  /// تعديل مشترك IPTV
  static Future<bool> update({
    required int id,
    String? subscriptionId,
    required String customerName,
    String? phone,
    String? iptvUsername,
    String? iptvPassword,
    String? iptvCode,
    DateTime? activationDate,
    int durationMonths = 1,
    bool isActive = true,
    String? location,
    String? notes,
  }) async {
    try {
      final body = {
        'subscriptionId': subscriptionId,
        'customerName': customerName,
        'phone': phone,
        'iptvUsername': iptvUsername,
        'iptvPassword': iptvPassword,
        'iptvCode': iptvCode,
        if (activationDate != null)
          'activationDate': activationDate.toIso8601String(),
        'durationMonths': durationMonths,
        'isActive': isActive,
        'location': location,
        'notes': notes,
      };

      final response = await _client.put(
        ApiConfig.iptvSubscriberById(id),
        body,
        (json) => json,
        useInternalKey: true,
      );

      return response.success;
    } catch (e) {
      if (kDebugMode) print('خطأ في تعديل مشترك IPTV');
      return false;
    }
  }

  /// حذف مشترك IPTV
  static Future<bool> delete(int id) async {
    try {
      final response = await _client.delete(
        ApiConfig.iptvSubscriberById(id),
        (json) => json,
        useInternalKey: true,
      );

      return response.success;
    } catch (e) {
      if (kDebugMode) print('خطأ في حذف مشترك IPTV');
      return false;
    }
  }
}
