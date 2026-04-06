import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api/api_client.dart';
import 'api/api_config.dart';

/// ═══════════════════════════════════════════════════════════════
/// خدمة الإعلانات والتبليغات
/// ═══════════════════════════════════════════════════════════════
class AnnouncementService {
  static AnnouncementService? _instance;
  static AnnouncementService get instance => _instance ??= AnnouncementService._();
  AnnouncementService._();

  /// جلب الإعلانات الموجهة للمستخدم الحالي
  Future<Map<String, dynamic>> getMyAnnouncements({int page = 1, int pageSize = 20}) async {
    try {
      final response = await ApiClient.instance.getRaw(
        '/announcements/my?page=$page&pageSize=$pageSize',
      );
      return response ?? {'success': false};
    } catch (e) {
      debugPrint('❌ خطأ في جلب إعلاناتي: $e');
      return {'success': false};
    }
  }

  /// عدد الإعلانات غير المقروءة
  Future<int> getUnreadCount() async {
    try {
      final response = await ApiClient.instance.getRaw('/announcements/unread-count');
      if (response?['success'] == true) {
        return response!['count'] as int? ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('❌ خطأ في جلب عدد الإعلانات غير المقروءة: $e');
      return 0;
    }
  }

  /// تسجيل قراءة إعلان
  Future<bool> markAsRead(int announcementId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/announcements/$announcementId/read');
      final response = await http.patch(
        uri,
        headers: {
          'Authorization': 'Bearer ${ApiClient.instance.authToken}',
          'Content-Type': 'application/json',
        },
        body: '{}',
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل القراءة: $e');
      return false;
    }
  }

  /// جلب جميع الإعلانات (للمدير)
  Future<Map<String, dynamic>> getAllAnnouncements({int page = 1, int pageSize = 50}) async {
    try {
      final response = await ApiClient.instance.getRaw(
        '/announcements?page=$page&pageSize=$pageSize',
      );
      return response ?? {'success': false};
    } catch (e) {
      debugPrint('❌ خطأ في جلب الإعلانات: $e');
      return {'success': false};
    }
  }

  /// إنشاء إعلان جديد
  Future<Map<String, dynamic>> createAnnouncement({
    required String title,
    required String body,
    String? imageUrl,
    int targetType = 0,
    String? targetValue,
    bool isPublished = true,
    bool isUrgent = false,
    bool isPinned = false,
    DateTime? expiresAt,
    List<String>? targetUserIds,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/announcements');
      final payload = {
        'title': title,
        'body': body,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'targetType': targetType,
        if (targetValue != null) 'targetValue': targetValue,
        'isPublished': isPublished,
        'isUrgent': isUrgent,
        'isPinned': isPinned,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
        if (targetUserIds != null) 'targetUserIds': targetUserIds,
      };
      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer ${ApiClient.instance.authToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الإعلان: $e');
      return {'success': false};
    }
  }

  /// تعديل إعلان
  Future<Map<String, dynamic>> updateAnnouncement({
    required int id,
    required String title,
    required String body,
    String? imageUrl,
    int targetType = 0,
    String? targetValue,
    bool isPublished = true,
    bool isUrgent = false,
    bool isPinned = false,
    DateTime? expiresAt,
    List<String>? targetUserIds,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/announcements/$id');
      final payload = {
        'title': title,
        'body': body,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'targetType': targetType,
        if (targetValue != null) 'targetValue': targetValue,
        'isPublished': isPublished,
        'isUrgent': isUrgent,
        'isPinned': isPinned,
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
        if (targetUserIds != null) 'targetUserIds': targetUserIds,
      };
      final response = await http.put(
        uri,
        headers: {
          'Authorization': 'Bearer ${ApiClient.instance.authToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('❌ خطأ في تعديل الإعلان: $e');
      return {'success': false};
    }
  }

  /// حذف إعلان
  Future<bool> deleteAnnouncement(int id) async {
    try {
      final response = await ApiClient.instance.deleteRaw('/announcements/$id');
      return response?['success'] == true;
    } catch (e) {
      debugPrint('❌ خطأ في حذف الإعلان: $e');
      return false;
    }
  }

  /// تقرير القراءة — من قرأ ومن لم يقرأ
  Future<Map<String, dynamic>> getReadReport(int announcementId) async {
    try {
      final response = await ApiClient.instance.getRaw('/announcements/$announcementId/read-report');
      return response ?? {'success': false};
    } catch (e) {
      debugPrint('❌ خطأ في جلب تقرير القراءة: $e');
      return {'success': false};
    }
  }

  /// رفع صورة مرفقة
  Future<String?> uploadImage(File imageFile) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/announcements/upload-image');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer ${ApiClient.instance.authToken}'
        ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final json = jsonDecode(body);
      if (json['success'] == true) {
        return json['data']?['url'];
      }
      return null;
    } catch (e) {
      debugPrint('❌ خطأ في رفع الصورة: $e');
      return null;
    }
  }
}
