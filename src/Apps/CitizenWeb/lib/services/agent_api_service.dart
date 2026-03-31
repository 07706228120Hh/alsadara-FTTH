import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

/// نموذج بيانات الوكيل
class AgentData {
  final String id;
  final String agentCode;
  final String name;
  final int type; // 0=Individual, 1=Business, 2=Master, 3=SubAgent
  final String phoneNumber;
  final String? city;
  final String? area;
  final double? latitude;
  final double? longitude;
  final String? pageId;
  final int status; // 0=Active, 1=Suspended, 2=Banned, 3=Inactive
  final double totalCharges;
  final double totalPayments;
  final double netBalance;
  final String? companyId;
  final String? companyName;
  final DateTime createdAt;

  AgentData({
    required this.id,
    required this.agentCode,
    required this.name,
    required this.type,
    required this.phoneNumber,
    this.city,
    this.area,
    this.latitude,
    this.longitude,
    this.pageId,
    required this.status,
    required this.totalCharges,
    required this.totalPayments,
    required this.netBalance,
    this.companyId,
    this.companyName,
    required this.createdAt,
  });

  factory AgentData.fromJson(Map<String, dynamic> json) {
    return AgentData(
      id: json['id'] ?? '',
      agentCode: json['agentCode'] ?? '',
      name: json['name'] ?? '',
      type: json['typeValue'] ?? (json['type'] is int ? json['type'] : 0),
      phoneNumber: json['phoneNumber'] ?? '',
      city: json['city'],
      area: json['area'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      pageId: json['pageId'],
      status:
          json['statusValue'] ?? (json['status'] is int ? json['status'] : 0),
      totalCharges: (json['totalCharges'] ?? 0).toDouble(),
      totalPayments: (json['totalPayments'] ?? 0).toDouble(),
      netBalance: (json['netBalance'] ?? 0).toDouble(),
      companyId: json['companyId'],
      companyName: json['companyName'],
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  String get typeName {
    switch (type) {
      case 0:
        return 'فردي';
      case 1:
        return 'شركة';
      case 2:
        return 'ماستر';
      case 3:
        return 'فرعي';
      default:
        return 'غير معروف';
    }
  }

  String get statusName {
    switch (status) {
      case 0:
        return 'نشط';
      case 1:
        return 'موقوف';
      case 2:
        return 'محظور';
      case 3:
        return 'غير نشط';
      default:
        return 'غير معروف';
    }
  }
}

/// نموذج بيانات عملية الوكيل
class AgentTransactionData {
  final int id;
  final String agentId;
  final int type; // 0=Charge, 1=Payment, 2=Discount, 3=Adjustment
  final int category;
  final double amount;
  final double balanceAfter;
  final String? description;
  final String? referenceNumber;
  final String? serviceRequestId;
  final DateTime createdAt;
  final String? createdByName;

  AgentTransactionData({
    required this.id,
    required this.agentId,
    required this.type,
    required this.category,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.referenceNumber,
    this.serviceRequestId,
    required this.createdAt,
    this.createdByName,
  });

  factory AgentTransactionData.fromJson(Map<String, dynamic> json) {
    return AgentTransactionData(
      id: json['id'] ?? 0,
      agentId: json['agentId'] ?? '',
      type: json['typeValue'] ?? (json['type'] is int ? json['type'] : 0),
      category:
          json['categoryValue'] ??
          (json['category'] is int ? json['category'] : 0),
      amount: (json['amount'] ?? 0).toDouble(),
      balanceAfter: (json['balanceAfter'] ?? 0).toDouble(),
      description: json['description'],
      referenceNumber: json['referenceNumber'],
      serviceRequestId: json['serviceRequestId']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      createdByName: json['createdByName'],
    );
  }

  bool get isIncoming => type == 0; // Charge = incoming

  String get typeName {
    switch (type) {
      case 0:
        return 'شحن';
      case 1:
        return 'تسديد';
      case 2:
        return 'خصم';
      case 3:
        return 'تعديل';
      default:
        return 'غير معروف';
    }
  }

  String get categoryName {
    switch (category) {
      case 0:
        return 'اشتراك جديد';
      case 1:
        return 'تجديد';
      case 2:
        return 'صيانة';
      case 3:
        return 'تحصيل فواتير';
      case 4:
        return 'تركيب';
      case 5:
        return 'نقل خدمة';
      case 6:
        return 'دفع نقدي';
      case 7:
        return 'تحويل بنكي';
      case 8:
        return 'أخرى';
      default:
        return 'أخرى';
    }
  }
}

/// نموذج ملخص الحسابات
class AgentAccountingSummaryData {
  final double totalCharges;
  final double totalPayments;
  final double netBalance;
  final int transactionsCount;
  final double todayCharges;
  final double todayPayments;

  AgentAccountingSummaryData({
    required this.totalCharges,
    required this.totalPayments,
    required this.netBalance,
    required this.transactionsCount,
    required this.todayCharges,
    required this.todayPayments,
  });

  factory AgentAccountingSummaryData.fromJson(Map<String, dynamic> json) {
    return AgentAccountingSummaryData(
      totalCharges: (json['totalCharges'] ?? 0).toDouble(),
      totalPayments: (json['totalPayments'] ?? 0).toDouble(),
      netBalance: (json['netBalance'] ?? 0).toDouble(),
      transactionsCount: json['transactionsCount'] ?? 0,
      todayCharges: (json['todayCharges'] ?? 0).toDouble(),
      todayPayments: (json['todayPayments'] ?? 0).toDouble(),
    );
  }
}

/// خدمة API الوكيل - تتصل بالخادم الحقيقي
class AgentApiService {
  final _storage = const FlutterSecureStorage();
  String? _token;
  AgentData? _currentAgent;

  // Singleton
  static final AgentApiService _instance = AgentApiService._internal();
  factory AgentApiService() => _instance;
  AgentApiService._internal();
  static AgentApiService get instance => _instance;

  AgentData? get currentAgent => _currentAgent;
  bool get isAuthenticated => _token != null && _currentAgent != null;

  http.Client _createClient() => http.Client();

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json; charset=utf-8',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  // ═══════════════════════════════════════════════════════════════
  // المصادقة
  // ═══════════════════════════════════════════════════════════════

  Future<String?> getToken() async {
    _token ??= await _storage.read(key: 'agent_token');
    return _token;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _storage.write(key: 'agent_token', value: token);
  }

  Future<void> clearToken() async {
    _token = null;
    _currentAgent = null;
    await _storage.delete(key: 'agent_token');
    await _storage.delete(key: 'agent_data');
  }

  /// حفظ حالة "تذكرني" للوكيل
  Future<void> setRememberMe(bool value) async {
    await _storage.write(
      key: 'agent_remember_me',
      value: value ? 'true' : 'false',
    );
  }

  /// قراءة حالة "تذكرني" للوكيل
  Future<bool> getRememberMe() async {
    final value = await _storage.read(key: 'agent_remember_me');
    return value == 'true';
  }

  /// حفظ بيانات الدخول محلياً
  Future<void> saveCredentials(String code, String password) async {
    await _storage.write(key: 'agent_saved_code', value: code);
    await _storage.write(key: 'agent_saved_pass', value: password);
  }

  /// جلب بيانات الدخول المحفوظة
  Future<({String? code, String? password})> getSavedCredentials() async {
    final code = await _storage.read(key: 'agent_saved_code');
    final pass = await _storage.read(key: 'agent_saved_pass');
    return (code: code, password: pass);
  }

  /// مسح بيانات الدخول المحفوظة
  Future<void> clearCredentials() async {
    await _storage.delete(key: 'agent_saved_code');
    await _storage.delete(key: 'agent_saved_pass');
  }

  /// تسجيل دخول الوكيل
  Future<Map<String, dynamic>> login({
    required String agentCode,
    required String password,
  }) async {
    final client = _createClient();

    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.agentLogin}'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({'AgentCode': agentCode, 'Password': password}),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));

        // API يرجع {success, data: {token, agent}} أو {token, agent}
        final responseData = data['data'] ?? data;

        if (responseData['token'] != null) {
          await saveToken(responseData['token']);
        }

        if (responseData['agent'] != null) {
          _currentAgent = AgentData.fromJson(responseData['agent']);
          // حفظ بيانات الوكيل محلياً
          await _storage.write(
            key: 'agent_data',
            value: json.encode(responseData['agent']),
          );
        }

        return responseData;
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(
        error['messageAr'] ?? error['message'] ?? 'فشل تسجيل الدخول',
      );
    } finally {
      client.close();
    }
  }

  /// جلب الملف الشخصي للوكيل
  Future<AgentData> getProfile() async {
    final token = await getToken();
    if (token == null) throw Exception('غير مسجل الدخول');

    final client = _createClient();

    try {
      final response = await client.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.agentProfile}'),
        headers: _authHeaders,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final profileData = data['data'] ?? data;
        _currentAgent = AgentData.fromJson(profileData);
        return _currentAgent!;
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(
        error['messageAr'] ?? error['message'] ?? 'خطأ في جلب الملف الشخصي',
      );
    } finally {
      client.close();
    }
  }

  /// تحميل بيانات الوكيل من التخزين المحلي
  Future<bool> tryRestoreSession() async {
    final token = await _storage.read(key: 'agent_token');
    final agentJson = await _storage.read(key: 'agent_data');

    if (token != null && agentJson != null) {
      _token = token;
      try {
        _currentAgent = AgentData.fromJson(json.decode(agentJson));
        // محاولة تحديث البيانات من الخادم بصمت
        try {
          await getProfile();
        } catch (_) {
          // استخدم البيانات المحفوظة إذا فشل الخادم
        }
        return true;
      } catch (_) {
        await clearToken();
        return false;
      }
    }
    return false;
  }

  /// تسجيل خروج
  Future<void> logout() async {
    await clearToken();
  }

  // ═══════════════════════════════════════════════════════════════
  // العمليات المالية
  // ═══════════════════════════════════════════════════════════════

  /// جلب عمليات الوكيل
  Future<List<AgentTransactionData>> getTransactions({
    int page = 1,
    int pageSize = 20,
    int? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final token = await getToken();
    if (token == null || _currentAgent == null) {
      throw Exception('غير مسجل الدخول');
    }

    final client = _createClient();
    final queryParams = <String, String>{
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    if (type != null) queryParams['type'] = type.toString();
    if (startDate != null) {
      queryParams['startDate'] = startDate.toIso8601String();
    }
    if (endDate != null) queryParams['endDate'] = endDate.toIso8601String();

    final uri = Uri.parse(
      '${ApiConfig.baseUrl}${ApiConfig.agentMyTransactions}',
    ).replace(queryParameters: queryParams);

    try {
      final response = await client.get(uri, headers: _authHeaders);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final items = data['data'] as List? ?? [];
        return items.map((e) => AgentTransactionData.fromJson(e)).toList();
      }

      final error = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(
        error['messageAr'] ?? error['message'] ?? 'خطأ في جلب العمليات',
      );
    } finally {
      client.close();
    }
  }

  /// جلب ملخص الحسابات
  Future<AgentAccountingSummaryData> getAccountingSummary() async {
    final token = await getToken();
    if (token == null || _currentAgent == null) {
      throw Exception('غير مسجل الدخول');
    }

    final client = _createClient();
    try {
      final response = await client.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.agentAccountingSummary}'),
        headers: _authHeaders,
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final bodyStr = utf8.decode(response.bodyBytes);
        final result = json.decode(bodyStr);
        if (result['success'] == true && result['data'] != null) {
          return AgentAccountingSummaryData.fromJson(result['data']);
        }
      }

      // fallback - استخدام بيانات الملف الشخصي
      if (_currentAgent != null) {
        return AgentAccountingSummaryData(
          totalCharges: _currentAgent!.totalCharges,
          totalPayments: _currentAgent!.totalPayments,
          netBalance: _currentAgent!.netBalance,
          transactionsCount: 0,
          todayCharges: 0,
          todayPayments: 0,
        );
      }

      throw Exception('فشل في جلب ملخص الحسابات');
    } catch (e) {
      // fallback from local data
      if (_currentAgent != null) {
        return AgentAccountingSummaryData(
          totalCharges: _currentAgent!.totalCharges,
          totalPayments: _currentAgent!.totalPayments,
          netBalance: _currentAgent!.netBalance,
          transactionsCount: 0,
          todayCharges: 0,
          todayPayments: 0,
        );
      }
      rethrow;
    } finally {
      client.close();
    }
  }

  /// طلب شحن رصيد (يرسل الطلب للشركة)
  Future<Map<String, dynamic>> requestCharge({
    required double amount,
    required String description,
    required int category, // 6=CashPayment, 7=BankTransfer
  }) async {
    final token = await getToken();
    if (token == null || _currentAgent == null) {
      throw Exception('غير مسجل الدخول');
    }

    final client = _createClient();

    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.agentBalanceRequest}'),
        headers: _authHeaders,
        body: json.encode({
          'amount': amount,
          'description': description,
          'category': category,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        // تحديث الرصيد المحلي من الاستجابة
        final responseData = data['data'] ?? data;
        if (responseData['agentBalance'] != null) {
          final bal = responseData['agentBalance'];
          _currentAgent = AgentData(
            id: _currentAgent!.id,
            agentCode: _currentAgent!.agentCode,
            name: _currentAgent!.name,
            type: _currentAgent!.type,
            phoneNumber: _currentAgent!.phoneNumber,
            city: _currentAgent!.city,
            area: _currentAgent!.area,
            status: _currentAgent!.status,
            totalCharges: (bal['totalCharges'] ?? 0).toDouble(),
            totalPayments: (bal['totalPayments'] ?? 0).toDouble(),
            netBalance: (bal['netBalance'] ?? 0).toDouble(),
            companyId: _currentAgent!.companyId,
            companyName: _currentAgent!.companyName,
            createdAt: _currentAgent!.createdAt,
          );
        }
        return data;
      }

      // معالجة أخطاء HTTP بأمان
      final bodyStr = utf8.decode(response.bodyBytes);
      if (bodyStr.isEmpty) {
        throw Exception(
          response.statusCode == 403
              ? 'غير مصرح بهذه العملية'
              : 'خطأ في الخادم (${response.statusCode})',
        );
      }
      final error = json.decode(bodyStr);
      throw Exception(
        error['messageAr'] ?? error['message'] ?? 'خطأ في طلب الشحن',
      );
    } finally {
      client.close();
    }
  }

  /// تسجيل تسديد
  Future<Map<String, dynamic>> recordPayment({
    required double amount,
    required String description,
    required int category,
  }) async {
    final token = await getToken();
    if (token == null || _currentAgent == null) {
      throw Exception('غير مسجل الدخول');
    }

    final client = _createClient();

    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.agentSelfPayment}'),
        headers: _authHeaders,
        body: json.encode({
          'amount': amount,
          'description': description,
          'category': category,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final responseData = data['data'] ?? data;
        if (responseData['agentBalance'] != null) {
          final bal = responseData['agentBalance'];
          _currentAgent = AgentData(
            id: _currentAgent!.id,
            agentCode: _currentAgent!.agentCode,
            name: _currentAgent!.name,
            type: _currentAgent!.type,
            phoneNumber: _currentAgent!.phoneNumber,
            city: _currentAgent!.city,
            area: _currentAgent!.area,
            status: _currentAgent!.status,
            totalCharges: (bal['totalCharges'] ?? 0).toDouble(),
            totalPayments: (bal['totalPayments'] ?? 0).toDouble(),
            netBalance: (bal['netBalance'] ?? 0).toDouble(),
            companyId: _currentAgent!.companyId,
            companyName: _currentAgent!.companyName,
            createdAt: _currentAgent!.createdAt,
          );
        }
        return data;
      }

      final bodyStr = utf8.decode(response.bodyBytes);
      if (bodyStr.isEmpty) {
        throw Exception(
          response.statusCode == 403
              ? 'غير مصرح بهذه العملية'
              : 'خطأ في الخادم (${response.statusCode})',
        );
      }
      final error = json.decode(bodyStr);
      throw Exception(
        error['messageAr'] ?? error['message'] ?? 'خطأ في تسجيل الدفع',
      );
    } finally {
      client.close();
    }
  }

  // ==================== تغيير كلمة المرور ====================

  /// تغيير كلمة مرور الوكيل
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await getToken();
    if (token == null || _currentAgent == null) {
      throw Exception('غير مسجل الدخول');
    }

    final client = _createClient();
    try {
      final response = await client.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.agentChangePassword}'),
        headers: _authHeaders,
        body: json.encode({
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return; // نجاح
      }

      final bodyStr = utf8.decode(response.bodyBytes);
      if (bodyStr.isEmpty) {
        throw Exception(
          response.statusCode == 403
              ? 'غير مصرح بهذه العملية'
              : 'خطأ في الخادم (${response.statusCode})',
        );
      }
      final error = json.decode(bodyStr);
      throw Exception(error['message'] ?? 'خطأ في تغيير كلمة المرور');
    } finally {
      client.close();
    }
  }

  // ==================== باقات الإنترنت ====================

  /// جلب باقات الإنترنت المتاحة
  Future<List<Map<String, dynamic>>> getInternetPlans() async {
    final client = http.Client();
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.publicInternetPlans}',
      );

      final response = await client.get(url, headers: _authHeaders);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final plans = data['plans'] ?? data['data'] ?? [];
        return List<Map<String, dynamic>>.from(plans);
      }

      return [];
    } catch (e) {
      print('Error fetching plans: $e');
      return [];
    } finally {
      client.close();
    }
  }

  // ==================== طلبات الخدمة ====================

  /// إنشاء طلب خدمة جديد (تفعيل اشتراك)
  Future<Map<String, dynamic>> createServiceRequest({
    required int serviceId,
    required int operationTypeId,
    String? internetPlanId,
    String? customerName,
    String? customerPhone,
    String? address,
    String? city,
    String? area,
    int priority = 3,
    int? subscriptionDuration,
    String? notes,
  }) async {
    final client = http.Client();
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.agentCreateServiceRequest}',
      );

      final body = <String, dynamic>{
        'ServiceId': serviceId,
        'OperationTypeId': operationTypeId,
        'Priority': priority,
      };

      if (internetPlanId != null) body['InternetPlanId'] = internetPlanId;
      if (customerName != null) body['CustomerName'] = customerName;
      if (customerPhone != null) body['CustomerPhone'] = customerPhone;
      if (address != null) body['Address'] = address;
      if (city != null) body['City'] = city;
      if (area != null) body['Area'] = area;
      if (subscriptionDuration != null) {
        body['SubscriptionDuration'] = subscriptionDuration;
      }
      if (notes != null) body['Notes'] = notes;

      final response = await client.post(
        url,
        headers: _authHeaders,
        body: json.encode(body),
      );

      final data = json.decode(utf8.decode(response.bodyBytes));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // تحديث الرصيد إذا تم إرجاعه
        final responseData = data['data'] ?? data;
        if (responseData['agentBalance'] != null) {
          final newBalance = (responseData['agentBalance'] ?? 0).toDouble();
          _currentAgent = AgentData(
            id: _currentAgent!.id,
            agentCode: _currentAgent!.agentCode,
            name: _currentAgent!.name,
            type: _currentAgent!.type,
            phoneNumber: _currentAgent!.phoneNumber,
            city: _currentAgent!.city,
            area: _currentAgent!.area,
            status: _currentAgent!.status,
            totalCharges: _currentAgent!.totalCharges,
            totalPayments: _currentAgent!.totalPayments,
            netBalance: newBalance,
            companyId: _currentAgent!.companyId,
            companyName: _currentAgent!.companyName,
            createdAt: _currentAgent!.createdAt,
          );
        }
        return data;
      }

      throw Exception(data['message'] ?? 'خطأ في إنشاء طلب الخدمة');
    } finally {
      client.close();
    }
  }

  /// جلب طلبات الخدمة للوكيل
  Future<Map<String, dynamic>> getMyServiceRequests({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final client = http.Client();
    try {
      var queryParams = 'page=$page&pageSize=$pageSize';
      if (status != null) queryParams += '&status=$status';

      final url = Uri.parse(
        '${ApiConfig.baseUrl}${ApiConfig.agentMyServiceRequests}?$queryParams',
      );

      final response = await client.get(url, headers: _authHeaders);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(utf8.decode(response.bodyBytes));
      }

      return {'success': false, 'data': [], 'total': 0};
    } catch (e) {
      print('Error fetching service requests: $e');
      return {'success': false, 'data': [], 'total': 0};
    } finally {
      client.close();
    }
  }
}
