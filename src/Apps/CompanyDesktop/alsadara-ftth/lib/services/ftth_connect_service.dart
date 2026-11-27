import 'dart:convert';
import 'package:http/http.dart' as http;
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

  /// قاعدة الـ API: تجاوز اختياري (مثل خادم شريك محدّد) وإلا الافتراضي admin.ftth.iq.
  String _base(String? baseUrl) =>
      (baseUrl == null || baseUrl.isEmpty) ? _baseUrl : '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api';

  /// نداء HTTP لـ FTTH:
  ///  - إن مُرِّر [token] (توكن شريك محدّد): نداء مباشر بترويسة Bearer + ترويسات WAF.
  ///  - وإلا: يُستخدم توكن جلسة FTTH المزدوجة الحالية عبر [AuthService].
  Future<http.Response> _req(
    String method,
    String url, {
    String? token,
    Map<String, String>? headers,
    String? body,
  }) {
    if (token == null) {
      return _auth.authenticatedRequest(method, url, headers: headers, body: body);
    }
    final h = <String, String>{
      ..._extraHeaders,
      ...?headers,
      'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse(url);
    switch (method.toUpperCase()) {
      case 'GET':
        return http.get(uri, headers: h);
      case 'POST':
        return http.post(uri, headers: h, body: body);
      case 'PUT':
        return http.put(uri, headers: h, body: body);
      case 'DELETE':
        return http.delete(uri, headers: h, body: body);
      default:
        throw UnsupportedError('HTTP method $method');
    }
  }

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
  Future<List<Map<String, dynamic>>> getZones({String? token, String? baseUrl}) async {
    final resp = await _req(
      'GET',
      '${_base(baseUrl)}/locations/zones',
      token: token,
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

  // ═══════════════════════════════════════════
  //  إدارة الفريق (المشغّلين) — teams/members
  //  يُنفَّذ بجلسة الشريك الرئيسية المميّزة (dual-auth). إنشاء مشغّل
  //  يحتاج حساباً بصلاحية إدارة الفريق (الحساب الرئيسي/السوبر أدمن).
  // ═══════════════════════════════════════════

  /// أدوار الفريق — [{id, displayValue, name, description,
  /// canAccessAllPartnerZones, canPerformMonetaryAction}]
  Future<List<Map<String, dynamic>>> getTeamRoles({String? token, String? baseUrl}) async {
    final resp = await _req(
      'GET',
      '${_base(baseUrl)}/teams/roles',
      token: token,
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) {
      throw Exception('فشل جلب الأدوار: ${resp.statusCode}');
    }
    final data = json.decode(resp.body);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  /// سياسات كلمة المرور — [{type:{displayValue}, value}]
  /// مثل: MinimumLength=12، UppercaseCharacters=1، LowercaseCharacters=1، Digits=1
  Future<List<Map<String, dynamic>>> getPasswordPolicies({String? token, String? baseUrl}) async {
    final resp = await _req(
      'GET',
      '${_base(baseUrl)}/passwords/policies',
      token: token,
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return [];
    final data = json.decode(resp.body);
    return List<Map<String, dynamic>>.from(data['items'] ?? []);
  }

  /// التحقّق من توفّر اسم المستخدم. يرجع true إذا كان متاحاً (غير مأخوذ).
  Future<bool> isTeamUsernameAvailable(String username, {String? token, String? baseUrl}) async {
    final resp = await _req(
      'GET',
      '${_base(baseUrl)}/teams/members/validate-username?username=${Uri.encodeComponent(username)}',
      token: token,
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) return false;
    final data = json.decode(resp.body);
    final isTaken = (data['model'] as Map<String, dynamic>?)?['isTaken'] == true;
    return !isTaken;
  }

  /// قائمة أعضاء الفريق (المشغّلين) — ترجع {totalCount, items[]}
  Future<Map<String, dynamic>> getTeamMembers({
    int pageNumber = 1,
    int pageSize = 50,
    String? token,
    String? baseUrl,
  }) async {
    final resp = await _req(
      'GET',
      '${_base(baseUrl)}/teams/members?pageNumber=$pageNumber&pageSize=$pageSize',
      token: token,
      headers: _extraHeaders,
    );
    if (resp.statusCode != 200) {
      throw Exception('فشل جلب المشغّلين: ${resp.statusCode}');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  /// إنشاء مشغّل جديد للشريك. يرجع {success, error?, errorType?, statusCode?}.
  /// [roleId] = معرّف الدور (GUID) من [getTeamRoles].
  /// [walletBalance] يحرّك مالاً — لا تمرّره إلا بعد تأكيد المستخدم.
  Future<Map<String, dynamic>> createTeamMember({
    required String username,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String password,
    required List<String> zoneIds,
    required String roleId,
    List<String> accessibleLOBs = const ['Ftth'],
    bool hasWallet = false,
    num walletBalance = 0,
    String? token,
    String? baseUrl,
  }) async {
    final body = json.encode({
      'username': username,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': phoneNumber,
      'password': password,
      'zoneIds': zoneIds,
      'role': roleId,
      'accessibleLOBs': accessibleLOBs,
      'walletSetup': {
        'hasWallet': hasWallet,
        'balance': hasWallet ? walletBalance : 0,
      },
    });

    final resp = await _req(
      'POST',
      '${_base(baseUrl)}/teams/members',
      token: token,
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

    String errorMsg = 'فشل إنشاء المشغّل (${resp.statusCode})';
    String? errorType;
    try {
      final err = json.decode(resp.body);
      errorType = err['type'] as String?;
      errorMsg = err['title'] as String? ?? errorMsg;
    } catch (_) {}

    // ترجمة الأخطاء المعروفة لرسائل عربية
    switch (errorType) {
      case 'TeamMemberPhoneNumberUsed':
        errorMsg = 'رقم الهاتف مستخدم لمشغّل آخر';
        break;
      case 'TeamMemberUsernameUsed':
        errorMsg = 'اسم المستخدم مستخدم مسبقاً';
        break;
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      errorMsg =
          'لا تملك صلاحية إدارة الفريق — سجّل الدخول بحساب الشريك الرئيسي';
    }

    return {
      'success': false,
      'error': errorMsg,
      'errorType': errorType,
      'statusCode': resp.statusCode,
    };
  }

  /// معالجة موحّدة لاستجابات التعديل/الشحن (نجاح 2xx بجسم فارغ غالباً).
  Map<String, dynamic> _mutationResult(http.Response resp, String fallback) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return {'success': true, 'statusCode': resp.statusCode};
    }
    String errorMsg = '$fallback (${resp.statusCode})';
    String? errorType;
    try {
      final err = json.decode(resp.body);
      errorType = err['type'] as String?;
      errorMsg = err['title'] as String? ?? errorMsg;
    } catch (_) {}
    if (errorType == 'TeamMemberPhoneNumberUsed') {
      errorMsg = 'رقم الهاتف مستخدم لمشغّل آخر';
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      errorMsg = 'لا تملك صلاحية إدارة الفريق';
    }
    return {
      'success': false,
      'error': errorMsg,
      'errorType': errorType,
      'statusCode': resp.statusCode,
    };
  }

  /// تعديل مشغّل — **كل حقل في طلب مستقلّ** (نموذج بوّابة FTTH الرسمية).
  ///
  /// سبب الفصل: خادم FTTH فيه عطل — أي طلب يحتوي `zoneIds` يُعيد بناء المشغّل
  /// ويمسح `firstName`/`lastName` إلى null (حتى لو لم يُرسَل الاسم إطلاقاً).
  /// لذلك نُرسل الزونات وحدها، ثم **نُعيد ختم الاسم بطلب اسم-فقط في النهاية**،
  /// وتعديل الاسم المنفرد يعمل ويثبت بشكل موثوق.
  ///
  /// [nameForRestamp] = مرِّر true عندما يجب إعادة ختم الاسم بعد تغيير الزونات
  /// (لأن الزونات ستمسحه). [roleId] = معرّف الدور (GUID).
  Future<Map<String, dynamic>> updateTeamMember({
    required String id,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? password,
    String? roleId,
    List<String>? zoneIds,
    bool restampName = false,
    String? token,
    String? baseUrl,
  }) async {
    Future<http.Response> put(Map<String, dynamic> b) => _req(
          'PUT',
          '${_base(baseUrl)}/teams/members/$id',
          token: token,
          headers: {..._extraHeaders, 'Content-Type': 'application/json'},
          body: json.encode(b),
        );

    http.Response? last;

    // 1) الهاتف منفرداً
    if (phoneNumber != null) last = await put({'phoneNumber': phoneNumber});
    // 2) الدور منفرداً
    if (roleId != null) last = await put({'role': roleId});
    // 3) كلمة المرور منفردة
    if (password != null && password.isNotEmpty) {
      last = await put({'password': password});
    }
    // 4) الزونات منفردة (تمسح الاسم على الخادم)
    if (zoneIds != null) last = await put({'zoneIds': zoneIds});
    // 5) الاسم آخراً ومنفرداً — يُثبّت الاسم بعد أن مسحته الزونات
    final doName = (firstName != null || lastName != null) &&
        (firstName != null && firstName.isNotEmpty ||
            lastName != null && lastName.isNotEmpty ||
            restampName);
    if (doName) {
      last = await put({
        if (firstName != null) 'firstName': firstName,
        if (lastName != null) 'lastName': lastName,
      });
    }

    if (last == null) return {'success': true, 'statusCode': 200};
    return _mutationResult(last, 'فشل تعديل المشغّل');
  }

  /// شحن محفظة مشغّل موجود — POST wallet-refill. يحرّك مالاً من محفظة الشريك؛ بتأكيد فقط.
  Future<Map<String, dynamic>> refillTeamMemberWallet({
    required String id,
    required num amount,
    String? token,
    String? baseUrl,
  }) async {
    final resp = await _req(
      'POST',
      '${_base(baseUrl)}/teams/members/$id/wallet-refill',
      token: token,
      headers: {..._extraHeaders, 'Content-Type': 'application/json'},
      body: json.encode({'amount': amount}),
    );
    return _mutationResult(resp, 'فشل شحن المحفظة');
  }
}
