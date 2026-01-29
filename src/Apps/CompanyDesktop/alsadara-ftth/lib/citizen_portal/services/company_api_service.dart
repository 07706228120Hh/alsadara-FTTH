import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/company_model.dart';

/// خدمة API للتعامل مع الشركات
class CompanyApiService {
  // TODO: قراءة من ملف .env أو تكوين
  static const String baseUrl = 'https://72.61.183.61/api';

  /// الحصول على جميع الشركات
  static Future<List<CompanyModel>> getAllCompanies({String? token}) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);

      final request = await client.getUrl(Uri.parse('$baseUrl/Companies'));
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(responseBody);
        return jsonList.map((json) => CompanyModel.fromJson(json)).toList();
      } else {
        throw Exception('فشل في تحميل الشركات: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// الحصول على الشركة المرتبطة بنظام المواطن
  static Future<CompanyModel?> getLinkedCompany() async {
    try {
      final client = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);

      final request = await client
          .getUrl(Uri.parse('$baseUrl/Companies/linked-to-citizen-portal'));
      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 200) {
        return CompanyModel.fromJson(json.decode(responseBody));
      } else if (response.statusCode == 404) {
        return null; // لا توجد شركة مرتبطة
      } else {
        throw Exception('فشل في تحميل الشركة المرتبطة: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// إنشاء شركة جديدة
  static Future<CompanyModel> createCompany({
    required String name,
    required String code,
    String? email,
    String? phone,
    String? address,
    String? city,
    required DateTime subscriptionEndDate,
    required String subscriptionPlan,
    required int maxUsers,
    String? token,
  }) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);

      final request = await client.postUrl(Uri.parse('$baseUrl/Companies'));
      request.headers.set('Content-Type', 'application/json');
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }

      final body = {
        'name': name,
        'code': code,
        'email': email,
        'phone': phone,
        'address': address,
        'city': city,
        'subscriptionEndDate': subscriptionEndDate.toIso8601String(),
        'subscriptionPlan': subscriptionPlan,
        'maxUsers': maxUsers,
      };

      request.write(json.encode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 201 || response.statusCode == 200) {
        return CompanyModel.fromJson(json.decode(responseBody));
      } else {
        final error = json.decode(responseBody);
        throw Exception(error['message'] ?? 'فشل في إنشاء الشركة');
      }
    } catch (e) {
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// ربط شركة بنظام المواطن - حفظ محلي
  static Future<void> linkToCitizenPortal(String companyId,
      {String? token}) async {
    try {
      // حفظ محلي في SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('linked_citizen_company_id', companyId);
      debugPrint('✅ تم ربط الشركة $companyId بنظام المواطن محلياً');
    } catch (e) {
      throw Exception('خطأ في حفظ الربط: $e');
    }
  }

  /// إلغاء ربط شركة من نظام المواطن - حفظ محلي
  static Future<void> unlinkFromCitizenPortal(String companyId,
      {String? token}) async {
    try {
      // مسح من SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('linked_citizen_company_id');
      debugPrint('✅ تم إلغاء ربط الشركة $companyId من نظام المواطن');
    } catch (e) {
      throw Exception('خطأ في إلغاء الربط: $e');
    }
  }

  /// الحصول على معرف الشركة المرتبطة محلياً
  static Future<String?> getLocalLinkedCompanyId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('linked_citizen_company_id');
    } catch (e) {
      return null;
    }
  }

  /// تعليق أو تفعيل شركة
  static Future<void> toggleCompanyStatus(String companyId,
      {String? reason, String? token}) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);

      final request = await client
          .postUrl(Uri.parse('$baseUrl/Companies/$companyId/toggle-status'));
      request.headers.set('Content-Type', 'application/json');
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }

      final body = {'reason': reason};
      request.write(json.encode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        final error = json.decode(responseBody);
        throw Exception(error['message'] ?? 'فشل في تغيير حالة الشركة');
      }
    } catch (e) {
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  /// حذف شركة
  static Future<void> deleteCompany(String companyId, {String? token}) async {
    try {
      final client = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);

      final request =
          await client.deleteUrl(Uri.parse('$baseUrl/Companies/$companyId'));
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        final error = json.decode(responseBody);
        throw Exception(error['message'] ?? 'فشل في حذف الشركة');
      }
    } catch (e) {
      throw Exception('خطأ في الاتصال: $e');
    }
  }
}
