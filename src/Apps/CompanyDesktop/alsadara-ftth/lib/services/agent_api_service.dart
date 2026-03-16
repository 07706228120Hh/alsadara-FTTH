import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/agent.dart';
import 'api/api_config.dart';
import 'vps_auth_service.dart';

/// خدمة إدارة الوكلاء - تتواصل مع Sadara Platform API
/// تستخدم api.ramzalsadara.tech (نفس سيرفر المنصة)
/// Singleton pattern
class AgentApiService {
  static AgentApiService? _instance;
  static AgentApiService get instance =>
      _instance ??= AgentApiService._internal();
  AgentApiService._internal();

  /// الحصول على headers المصادقة
  Map<String, String> get _headers {
    final token = VpsAuthService.instance.accessToken;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// تنفيذ طلب HTTP ومعالجة الاستجابة
  Future<Map<String, dynamic>> _request(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$endpoint');
    final timeout = const Duration(seconds: 15);

    http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: _headers).timeout(timeout);
        break;
      case 'POST':
        response = await http
            .post(uri,
                headers: _headers,
                body: body != null ? json.encode(body) : null)
            .timeout(timeout);
        break;
      case 'PUT':
        response = await http
            .put(uri,
                headers: _headers,
                body: body != null ? json.encode(body) : null)
            .timeout(timeout);
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: _headers).timeout(timeout);
        break;
      default:
        throw Exception('طريقة غير مدعومة: $method');
    }

    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {'success': true, 'data': null};
      }
      throw Exception('خطأ في الخادم: ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data; // الـ API يرجع {success, data, message} مباشرة
    }

    if (response.statusCode == 401) {
      throw Exception('انتهت صلاحية الجلسة، يرجى تسجيل الدخول مرة أخرى');
    }

    throw Exception(data['message'] ?? 'خطأ في الخادم: ${response.statusCode}');
  }

  // ==================== CRUD ====================

  /// جلب جميع الوكلاء
  Future<List<AgentModel>> getAll(
      {String? companyId, AgentStatus? status}) async {
    try {
      String endpoint = '/agents';
      List<String> params = [];
      if (companyId != null) params.add('companyId=$companyId');
      if (status != null) params.add('status=${status.intValue}');
      if (params.isNotEmpty) endpoint += '?${params.join('&')}';

      final response = await _request('GET', endpoint);
      if (response['success'] == true && response['data'] != null) {
        final List data = response['data'] is List ? response['data'] : [];
        return data.map((json) => AgentModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('خطأ في جلب الوكلاء');
    }
  }

  /// جلب وكيل بالمعرف
  Future<AgentModel?> getById(String id) async {
    try {
      final response = await _request('GET', '/agents/$id');
      if (response['success'] == true && response['data'] != null) {
        return AgentModel.fromJson(response['data']);
      }
      return null;
    } catch (e) {
      throw Exception('خطأ في جلب بيانات الوكيل');
    }
  }

  /// إنشاء وكيل جديد
  Future<AgentModel?> create({
    required String name,
    required AgentType type,
    required String phoneNumber,
    required String password,
    required String companyId,
    String? email,
    String? city,
    String? area,
    String? fullAddress,
    double? latitude,
    double? longitude,
    String? pageId,
    String? notes,
  }) async {
    try {
      final body = {
        'name': name,
        'type': type.intValue,
        'phoneNumber': phoneNumber,
        'password': password,
        'companyId': companyId,
        if (email != null) 'email': email,
        if (city != null) 'city': city,
        if (area != null) 'area': area,
        if (fullAddress != null) 'fullAddress': fullAddress,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (pageId != null) 'pageId': pageId,
        if (notes != null) 'notes': notes,
      };

      final response = await _request('POST', '/agents', body: body);
      if (response['success'] == true && response['data'] != null) {
        return AgentModel.fromJson(response['data']);
      }
      throw Exception(response['message'] ?? 'فشل في إنشاء الوكيل');
    } catch (e) {
      if (e.toString().contains('فشل') ||
          e.toString().contains('خطأ في الخادم') ||
          e.toString().contains('انتهت صلاحية')) {
        rethrow;
      }
      throw Exception('خطأ في إنشاء الوكيل');
    }
  }

  /// تعديل بيانات وكيل
  Future<AgentModel?> update(
    String id, {
    String? name,
    AgentType? type,
    String? phoneNumber,
    String? newPassword,
    String? email,
    String? city,
    String? area,
    String? fullAddress,
    double? latitude,
    double? longitude,
    String? pageId,
    AgentStatus? status,
    String? notes,
    String? profileImageUrl,
  }) async {
    try {
      final body = <String, dynamic>{
        if (name != null) 'name': name,
        if (type != null) 'type': type.intValue,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
        if (newPassword != null) 'newPassword': newPassword,
        if (email != null) 'email': email,
        if (city != null) 'city': city,
        if (area != null) 'area': area,
        if (fullAddress != null) 'fullAddress': fullAddress,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (pageId != null) 'pageId': pageId,
        if (status != null) 'status': status.intValue,
        if (notes != null) 'notes': notes,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
      };

      final response = await _request('PUT', '/agents/$id', body: body);
      if (response['success'] == true && response['data'] != null) {
        return AgentModel.fromJson(response['data']);
      }
      throw Exception(response['message'] ?? 'فشل في تعديل الوكيل');
    } catch (e) {
      if (e.toString().contains('فشل') ||
          e.toString().contains('خطأ في الخادم') ||
          e.toString().contains('انتهت صلاحية')) {
        rethrow;
      }
      throw Exception('خطأ في تعديل الوكيل');
    }
  }

  /// حذف وكيل (حذف ناعم)
  Future<bool> delete(String id) async {
    try {
      final response = await _request('DELETE', '/agents/$id');
      return response['success'] == true;
    } catch (e) {
      throw Exception('خطأ في حذف الوكيل');
    }
  }

  // ==================== المحاسبة ====================

  /// جلب معاملات وكيل
  Future<Map<String, dynamic>> getTransactions(
    String agentId, {
    TransactionType? type,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      String endpoint =
          '/agents/$agentId/transactions?page=$page&pageSize=$pageSize';
      if (type != null) endpoint += '&type=${type.index}';
      if (from != null) endpoint += '&from=${from.toIso8601String()}';
      if (to != null) endpoint += '&to=${to.toIso8601String()}';

      final response = await _request('GET', endpoint);
      if (response['success'] == true) {
        final List txData = response['data'] is List ? response['data'] : [];
        return {
          'transactions': txData
              .map((json) => AgentTransactionModel.fromJson(json))
              .toList(),
          'total': response['total'] ?? 0,
          'page': response['page'] ?? 1,
          'totalPages': response['totalPages'] ?? 1,
          'summary': response['summary'],
        };
      }
      return {'transactions': [], 'total': 0};
    } catch (e) {
      throw Exception('خطأ في جلب المعاملات');
    }
  }

  /// إضافة أجور على الوكيل
  Future<Map<String, dynamic>> addCharge(
    String agentId, {
    required double amount,
    required TransactionCategory category,
    String? description,
    String? referenceNumber,
    String? serviceRequestId,
    String? citizenId,
    String? notes,
  }) async {
    try {
      final body = {
        'amount': amount,
        'category': category.intValue,
        if (description != null) 'description': description,
        if (referenceNumber != null) 'referenceNumber': referenceNumber,
        if (serviceRequestId != null) 'serviceRequestId': serviceRequestId,
        if (citizenId != null) 'citizenId': citizenId,
        if (notes != null) 'notes': notes,
      };

      final response =
          await _request('POST', '/agents/$agentId/charge', body: body);
      return response;
    } catch (e) {
      throw Exception('خطأ في إضافة الأجور');
    }
  }

  /// تسجيل تسديد من الوكيل
  Future<Map<String, dynamic>> addPayment(
    String agentId, {
    required double amount,
    required TransactionCategory category,
    String? description,
    String? referenceNumber,
    String? notes,
  }) async {
    try {
      final body = {
        'amount': amount,
        'category': category.intValue,
        if (description != null) 'description': description,
        if (referenceNumber != null) 'referenceNumber': referenceNumber,
        if (notes != null) 'notes': notes,
      };

      final response =
          await _request('POST', '/agents/$agentId/payment', body: body);
      return response;
    } catch (e) {
      throw Exception('خطأ في تسجيل التسديد');
    }
  }

  /// ملخص المحاسبة لجميع الوكلاء
  Future<AgentAccountingSummary?> getAccountingSummary(
      {String? companyId}) async {
    try {
      String endpoint = '/agents/accounting/summary';
      if (companyId != null) endpoint += '?companyId=$companyId';

      final response = await _request('GET', endpoint);
      if (response['success'] == true && response['data'] != null) {
        return AgentAccountingSummary.fromJson(response['data']);
      }
      return null;
    } catch (e) {
      throw Exception('خطأ في جلب ملخص المحاسبة');
    }
  }

  /// جلب قائمة الشركات (للسوبر أدمن)
  Future<List<Map<String, dynamic>>> getCompanies() async {
    try {
      final response = await _request('GET', '/superadmin/companies');
      if (response['success'] == true && response['data'] != null) {
        final data = response['data'];
        // API يرجع {data: {companies: [...], totalCount, ...}}
        final List companiesList = data['companies'] is List
            ? data['companies']
            : (data is List ? data : []);
        return companiesList.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      throw Exception('خطأ في جلب الشركات');
    }
  }

  // ==================== تعديل وحذف المعاملات (مدير النظام فقط) ====================

  /// تعديل معاملة مالية
  Future<Map<String, dynamic>> updateTransaction(
    int transactionId, {
    double? amount,
    TransactionCategory? category,
    String? description,
    String? notes,
  }) async {
    try {
      final body = <String, dynamic>{
        if (amount != null) 'amount': amount,
        if (category != null) 'category': category.intValue,
        if (description != null) 'description': description,
        if (notes != null) 'notes': notes,
      };

      final response = await _request(
          'PUT', '/agents/transactions/$transactionId',
          body: body);
      return response;
    } catch (e) {
      throw Exception('خطأ في تعديل المعاملة');
    }
  }

  /// حذف معاملة مالية
  Future<bool> deleteTransaction(int transactionId) async {
    try {
      final response =
          await _request('DELETE', '/agents/transactions/$transactionId');
      return response['success'] == true;
    } catch (e) {
      throw Exception('خطأ في حذف المعاملة');
    }
  }

  /// جلب جميع معاملات الوكلاء لشركة
  Future<Map<String, dynamic>> getAllTransactions({
    String? companyId,
    int? type,
    DateTime? from,
    DateTime? to,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final params = <String>[];
      if (companyId != null) params.add('companyId=$companyId');
      if (type != null) params.add('type=$type');
      if (from != null) params.add('from=${from.toIso8601String()}');
      if (to != null) params.add('to=${to.toIso8601String()}');
      params.add('page=$page');
      params.add('pageSize=$pageSize');
      final query = params.join('&');
      return await _request('GET', '/agents/transactions/all?$query');
    } catch (e) {
      throw Exception('خطأ في جلب معاملات الوكلاء');
    }
  }

  // ==================== إدارة نسب العمولات ====================

  /// جلب نسب عمولات وكيل معين
  Future<List<Map<String, dynamic>>> getAgentCommissionRates(
      String agentId) async {
    try {
      final response =
          await _request('GET', '/accounting/agent-commissions/rates/$agentId');
      if (response['success'] == true && response['data'] != null) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
      return [];
    } catch (e) {
      throw Exception('خطأ في جلب نسب العمولات');
    }
  }

  /// جلب نسب عمولات جميع الوكلاء لشركة
  Future<List<Map<String, dynamic>>> getAllCommissionRates(
      String companyId) async {
    try {
      final response = await _request(
          'GET', '/accounting/agent-commissions/rates?companyId=$companyId');
      if (response['success'] == true && response['data'] != null) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
      return [];
    } catch (e) {
      throw Exception('خطأ في جلب نسب العمولات');
    }
  }

  /// تعيين نسبة عمولة وكيل لباقة
  Future<Map<String, dynamic>> setCommissionRate({
    required String agentId,
    required String internetPlanId,
    required double commissionPercentage,
    required String companyId,
    String? notes,
  }) async {
    try {
      return await _request('POST', '/accounting/agent-commissions/rates',
          body: {
            'agentId': agentId,
            'internetPlanId': internetPlanId,
            'commissionPercentage': commissionPercentage,
            'companyId': companyId,
            'isActive': true,
            if (notes != null) 'notes': notes,
          });
    } catch (e) {
      throw Exception('خطأ في تحديد نسبة العمولة');
    }
  }

  /// تعيين نسب عمولة لوكيل لجميع الباقات دفعة واحدة
  Future<Map<String, dynamic>> setBulkCommissionRates({
    required String agentId,
    required String companyId,
    required List<Map<String, dynamic>> rates,
  }) async {
    try {
      return await _request('POST', '/accounting/agent-commissions/rates/bulk',
          body: {
            'agentId': agentId,
            'companyId': companyId,
            'rates': rates,
          });
    } catch (e) {
      throw Exception('خطأ في تعيين نسب العمولات');
    }
  }

  /// حذف نسبة عمولة
  Future<bool> deleteCommissionRate(int rateId) async {
    try {
      final response = await _request(
          'DELETE', '/accounting/agent-commissions/rates/$rateId');
      return response['success'] == true;
    } catch (e) {
      throw Exception('خطأ في حذف نسبة العمولة');
    }
  }

  /// جلب الباقات مع الأرباح
  Future<List<Map<String, dynamic>>> getPlansWithProfit(
      String companyId) async {
    try {
      final response = await _request(
          'GET', '/accounting/internet-plans/with-profit?companyId=$companyId');
      if (response['success'] == true && response['data'] != null) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
      return [];
    } catch (e) {
      throw Exception('خطأ في جلب الباقات');
    }
  }

  /// تحديث ربح باقة
  Future<Map<String, dynamic>> updatePlanProfit(
      String planId, double profitAmount) async {
    try {
      return await _request('PUT', '/accounting/internet-plans/$planId/profit',
          body: {
            'profitAmount': profitAmount,
          });
    } catch (e) {
      throw Exception('خطأ في تحديث ربح الباقة');
    }
  }
}
