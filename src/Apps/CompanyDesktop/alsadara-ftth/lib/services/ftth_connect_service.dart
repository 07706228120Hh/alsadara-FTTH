import 'dart:convert';
import 'auth_service.dart';

/// سيرفس لعمليات توصيل المشتركين عبر FTTH API (admin.ftth.iq)
class FtthConnectService {
  static const String _baseUrl = 'https://admin.ftth.iq/api';

  static FtthConnectService? _instance;
  static FtthConnectService get instance =>
      _instance ??= FtthConnectService._();
  FtthConnectService._();

  final _auth = AuthService.instance;

  // ─── Headers إضافية مطلوبة من FTTH API ───
  Map<String, String> get _extraHeaders => {
        'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
        'x-user-role': '0',
      };

  // ═══════════════════════════════════════════
  //  أنواع المهام
  // ═══════════════════════════════════════════
  /// يُرجع [{id, displayValue}] — مثل Connect Customer, Sign Contract, Maintenance
  Future<List<Map<String, dynamic>>> getTaskTypes() async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/tasks/types',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) {
      throw Exception('فشل جلب أنواع المهام: ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  // ═══════════════════════════════════════════
  //  قائمة المهام
  // ═══════════════════════════════════════════
  /// status: 0=All, 1=Not started, 2=In progress, 3=Completed
  Future<Map<String, dynamic>> getTasks({
    int status = 1,
    List<String> typeIds = const [],
    int pageSize = 20,
    int pageNumber = 1,
    String? customerName,
    String? customerPhone,
    String? zoneId,
  }) async {
    final params = <String, String>{
      'pageSize': '$pageSize',
      'pageNumber': '$pageNumber',
      'sortCriteria.property': 'dueAt',
      'sortCriteria.direction': 'asc',
      'status': '$status',
      'hierarchyLevel': '0',
    };
    if (customerName != null && customerName.isNotEmpty) {
      params['customerName'] = customerName;
    }
    if (customerPhone != null && customerPhone.isNotEmpty) {
      params['customerPhone'] = customerPhone;
    }
    if (zoneId != null && zoneId.isNotEmpty) {
      params['zones'] = zoneId;
    }

    final uri = Uri.parse('$_baseUrl/tasks').replace(queryParameters: {
      ...params,
      if (typeIds.isNotEmpty) 'typeIds': typeIds,
    });

    final resp = await _auth.authenticatedRequest(
      'GET',
      uri.toString(),
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) {
      throw Exception('فشل جلب المهام: ${resp.statusCode}');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  // ═══════════════════════════════════════════
  //  تفاصيل مهمة
  // ═══════════════════════════════════════════
  Future<Map<String, dynamic>> getTaskDetails(String taskId) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/tasks/$taskId',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) {
      throw Exception('فشل جلب تفاصيل المهمة: ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    return data['model'] as Map<String, dynamic>;
  }

  // ═══════════════════════════════════════════
  //  تعليقات المهمة
  // ═══════════════════════════════════════════
  Future<List<Map<String, dynamic>>> getTaskComments(String taskId) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/tasks/$taskId/comments?pageSize=50&pageNumber=1',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  // ═══════════════════════════════════════════
  //  بيانات الشبكة (Zones, FDTs, FATs, ONT)
  // ═══════════════════════════════════════════
  Future<List<Map<String, dynamic>>> getZones() async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/locations/zones',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getOntVendors() async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/network-elements/ont-vendors',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    final model = data['model'] as Map<String, dynamic>? ?? {};
    return List<Map<String, dynamic>>.from(model['ontVendors'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getFdts(String zoneId) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/network-elements/fdts?zoneId=$zoneId',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    final model = data['model'] as Map<String, dynamic>? ?? {};
    return List<Map<String, dynamic>>.from(model['fdts'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getFats(String fdtId) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/network-elements/fats?fdtId=$fdtId',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    final model = data['model'] as Map<String, dynamic>? ?? {};
    return List<Map<String, dynamic>>.from(model['fats'] ?? []);
  }

  // ═══════════════════════════════════════════
  //  التحقق من Username / Password
  // ═══════════════════════════════════════════
  /// يرجع {isValid, regexPattern, regexDescription, status?}
  Future<Map<String, dynamic>> validateUsername(String username) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/subscriptions/validate-username?username=${Uri.encodeComponent(username)}',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) {
      return {'isValid': false, 'regexDescription': 'فشل التحقق'};
    }
    final data = json.decode(resp.body);
    return data['model'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> validatePassword(String password) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/subscriptions/validate-password?password=${Uri.encodeComponent(password)}',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) {
      return {'isValid': false, 'regexDescription': 'فشل التحقق'};
    }
    final data = json.decode(resp.body);
    return data['model'] as Map<String, dynamic>;
  }

  // ═══════════════════════════════════════════
  //  البحث عن مشترك (بالهاتف أو الاسم)
  // ═══════════════════════════════════════════
  Future<List<Map<String, dynamic>>> searchCustomers({
    String? phone,
    String? name,
    int pageSize = 10,
  }) async {
    final params = <String, String>{
      'pageSize': '$pageSize',
      'pageNumber': '1',
      'sortCriteria.property': 'self.displayValue',
      'sortCriteria.direction': 'asc',
    };
    if (phone != null && phone.isNotEmpty) params['phone'] = phone;
    if (name != null && name.isNotEmpty) params['name'] = name;

    final uri = Uri.parse('$_baseUrl/customers').replace(queryParameters: params);
    final resp = await _auth.authenticatedRequest(
      'GET',
      uri.toString(),
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  // ═══════════════════════════════════════════
  //  تفاصيل مشترك
  // ═══════════════════════════════════════════
  Future<Map<String, dynamic>> getCustomerDetails(String customerId) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/customers/$customerId',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return {};
    final data = json.decode(resp.body);
    return data['model'] as Map<String, dynamic>? ?? {};
  }

  // ═══════════════════════════════════════════
  //  عمليات (tasks) مرتبطة بمشترك
  // ═══════════════════════════════════════════
  Future<List<Map<String, dynamic>>> getCustomerTasks(String customerId) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/customers/$customerId/tasks',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  // ═══════════════════════════════════════════
  //  اشتراكات مشترك
  // ═══════════════════════════════════════════
  Future<List<Map<String, dynamic>>> getCustomerSubscriptions(String customerId) async {
    final resp = await _auth.authenticatedRequest(
      'GET',
      '$_baseUrl/customers/subscriptions?customerId=$customerId',
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  // ═══════════════════════════════════════════
  //  تنفيذ التوصيل — POST customer-connections
  // ═══════════════════════════════════════════
  /// يرجع {success, error?, data?}
  Future<Map<String, dynamic>> connectCustomer({
    required String taskId,
    required String deviceUsername,
    required String devicePassword,
    required String pointSupplyNumber,
    required String deviceSerial,
    required String fatId,
    required String fdtId,
    required String ontVendorId,
    required String installationCode,
  }) async {
    final body = json.encode({
      'taskId': taskId,
      'deviceUsername': deviceUsername,
      'devicePassword': devicePassword,
      'pointSupplyNumber': pointSupplyNumber,
      'deviceSerial': deviceSerial,
      'fat': fatId,
      'fdt': fdtId,
      'ontVendor': ontVendorId,
      'installationCode': installationCode,
    });

    final resp = await _auth.authenticatedRequest(
      'POST',
      '$_baseUrl/tasks/customer-connections',
      headers: {
        ..._extraHeaders,
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (resp.statusCode == 200 || resp.statusCode == 201) {
      return {
        'success': true,
        'data': resp.body.isNotEmpty ? json.decode(resp.body) : null,
      };
    }

    // تحليل الخطأ
    String errorMsg = 'خطأ غير معروف (${resp.statusCode})';
    String? errorType;
    try {
      final err = json.decode(resp.body);
      errorType = err['type'] as String?;
      errorMsg = err['title'] as String? ?? errorMsg;
    } catch (_) {}

    return {
      'success': false,
      'error': errorMsg,
      'errorType': errorType,
      'statusCode': resp.statusCode,
    };
  }
}
