import 'api/api_client.dart';
import 'api/api_response.dart';

/// نموذج حساب مرتبط (FTTH أو ساس) — يطابق عقد بوّابة الصدارة
/// `/api/linked-accounts`. لا يحمل كلمة المرور إطلاقاً (تُكشف عبر endpoint منفصل).
class LinkedAccount {
  final String id;

  /// "Ftth" أو "Sas"
  final String provider;
  final String label;
  final String username;
  final String? serverUrl;
  final String? role;
  final bool isActive;
  final bool isPrimary;

  /// حالة التحقّق: Verified / Invalid / Unverified (أو ما يرسله الخادم)
  final String? status;
  final DateTime? lastVerifiedAt;
  final DateTime? lastLoginAt;

  /// رقم عضو الفريق على FTTH (يُجلب عند «توثيق»). null قبل التوثيق أو إن لم يُعثر عليه.
  final String? ftthMemberId;

  /// هل يملك الخادم سراً مخزّناً لهذا الحساب (بلا كشف قيمته).
  final bool hasSecret;

  /// نوع حساب الساس: 0 = SasManager (صفحة وكيل)، 1 = SasUser (نظام ساس).
  /// null لحسابات FTTH (لا ينطبق).
  final int? accountType;

  /// مُضاعِف المبلغ لحساب الساس. null لحسابات FTTH (لا ينطبق).
  final double? amountMultiplier;

  const LinkedAccount({
    required this.id,
    required this.provider,
    required this.label,
    required this.username,
    this.serverUrl,
    this.role,
    this.isActive = true,
    this.isPrimary = false,
    this.status,
    this.lastVerifiedAt,
    this.lastLoginAt,
    this.hasSecret = false,
    this.accountType,
    this.amountMultiplier,
    this.ftthMemberId,
  });

  bool get isFtth => provider.toLowerCase() == 'ftth';
  bool get isSas => provider.toLowerCase() == 'sas';

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString());
  }

  static bool _parseBool(dynamic v, {bool fallback = false}) {
    if (v == null) return fallback;
    if (v is bool) return v;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == '1';
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  factory LinkedAccount.fromJson(Map<String, dynamic> j) {
    return LinkedAccount(
      id: (j['id'] ?? j['Id'] ?? '').toString(),
      provider: (j['provider'] ?? j['Provider'] ?? '').toString(),
      label: (j['label'] ?? j['Label'] ?? '').toString(),
      username: (j['username'] ?? j['Username'] ?? '').toString(),
      serverUrl: (j['serverUrl'] ?? j['ServerUrl'])?.toString(),
      role: (j['role'] ?? j['Role'])?.toString(),
      isActive: _parseBool(j['isActive'] ?? j['IsActive'], fallback: true),
      isPrimary: _parseBool(j['isPrimary'] ?? j['IsPrimary']),
      status: (j['status'] ?? j['Status'])?.toString(),
      lastVerifiedAt: _parseDate(j['lastVerifiedAt'] ?? j['LastVerifiedAt']),
      lastLoginAt: _parseDate(j['lastLoginAt'] ?? j['LastLoginAt']),
      hasSecret: _parseBool(j['hasSecret'] ?? j['HasSecret']),
      accountType: _parseInt(j['accountType'] ?? j['AccountType']),
      amountMultiplier:
          _parseDouble(j['amountMultiplier'] ?? j['AmountMultiplier']),
      ftthMemberId: (j['ftthMemberId'] ?? j['FtthMemberId'])?.toString(),
    );
  }
}

/// خدمة الحسابات المرتبطة — تتصل ببوّابة الصدارة الداخلية `/api/linked-accounts`.
/// الخادم يفرض العزل (CompanyId من التوكن) والصلاحية `linked_accounts`.
/// كل الدوال تُرجع Map موحّدة: {success, data?, message?, statusCode}.
class LinkedAccountsService {
  static LinkedAccountsService? _instance;
  static LinkedAccountsService get instance =>
      _instance ??= LinkedAccountsService._internal();
  LinkedAccountsService._internal();

  final _client = ApiClient.instance;

  Map<String, dynamic> _toMap<T>(ApiResponse<T> response) {
    if (response.success) {
      return {
        'success': true,
        'data': response.data,
        'statusCode': response.statusCode,
        if (response.message != null) 'message': response.message,
      };
    }
    return {
      'success': false,
      'message': response.message ?? 'خطأ غير معروف',
      'statusCode': response.statusCode,
    };
  }

  /// جلب القائمة الموحّدة (FTTH + الساس) لمستخدم معيّن.
  /// يُرجع data = List&lt;LinkedAccount&gt; عند النجاح.
  Future<Map<String, dynamic>> getAccounts(String userId) async {
    final response = await _client.get(
      '/linked-accounts?userId=$userId',
      (json) => json,
    );
    final map = _toMap(response);
    if (map['success'] == true) {
      final data = map['data'];
      final List rawList =
          data is List ? data : (data is Map ? (data['data'] ?? data['items'] ?? []) as List : []);
      map['data'] = rawList
          .whereType<Map>()
          .map((e) => LinkedAccount.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return map;
  }

  /// تسجيل دخول خادمي لحساب FTTH مرتبط — المسار الآمن الجديد.
  /// الخادم يفكّ تشفير الاعتماد داخلياً ويسجّل الدخول لمزوّد FTTH ويُعيد
  /// التوكنات فقط، بلا أي كلمة مرور على العميل.
  /// يُرجع data = {accessToken, refreshToken, ...} عند النجاح.
  Future<Map<String, dynamic>> login(String ftthAccountId) async {
    final response = await _client.post(
      '/linked-accounts/ftth/$ftthAccountId/login',
      {},
      (json) => json,
    );
    return _toMap(response);
  }

  /// ربط حساب FTTH جديد — يُمرَّر ownerUserId = معرّف الموظف المعروض.
  Future<Map<String, dynamic>> createFtth({
    required String ownerUserId,
    required String label,
    required String username,
    required String password,
    String? serverUrl,
    String? role,
    bool? isPrimary,
  }) async {
    final body = <String, dynamic>{
      'ownerUserId': ownerUserId,
      'label': label,
      'username': username,
      'password': password,
      if (serverUrl != null && serverUrl.isNotEmpty) 'serverUrl': serverUrl,
      if (role != null && role.isNotEmpty) 'role': role,
      if (isPrimary != null) 'isPrimary': isPrimary,
    };
    final response =
        await _client.post('/linked-accounts/ftth', body, (json) => json);
    return _toMap(response);
  }

  /// تعديل حساب FTTH.
  Future<Map<String, dynamic>> updateFtth(
    String id, {
    String? label,
    String? username,
    String? password,
    bool? isActive,
    bool? isPrimary,
    String? serverUrl,
  }) async {
    final body = <String, dynamic>{
      if (label != null) 'label': label,
      if (username != null) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      if (isActive != null) 'isActive': isActive,
      if (isPrimary != null) 'isPrimary': isPrimary,
      if (serverUrl != null) 'serverUrl': serverUrl,
    };
    final response =
        await _client.put('/linked-accounts/ftth/$id', body, (json) => json);
    return _toMap(response);
  }

  /// حذف حساب FTTH.
  Future<Map<String, dynamic>> deleteFtth(String id) async {
    final response =
        await _client.delete('/linked-accounts/ftth/$id', (json) => json);
    return _toMap(response);
  }

  /// التحقّق من صحة حساب FTTH (محاولة دخول للمزوّد).
  /// يُرجع data = {verified, status, lastVerifiedAt}.
  Future<Map<String, dynamic>> verifyFtth(String id) async {
    final response = await _client.post(
      '/linked-accounts/ftth/$id/verify',
      {},
      (json) => json,
    );
    return _toMap(response);
  }

  /// كشف كلمة مرور FTTH (أدمن شركة فقط؛ قد يرجع 403).
  /// يُرجع data = {password} عند النجاح.
  Future<Map<String, dynamic>> revealFtth(String id) async {
    final response = await _client.post(
      '/linked-accounts/ftth/$id/reveal',
      {},
      (json) => json,
    );
    return _toMap(response);
  }

  /// كشف كلمة مرور الساس (أدمن شركة فقط؛ وخلف علَم خادمي قد يكون OFF).
  /// الخادم قد يُعيد:
  ///   - 403 «كشف اعتماد الساس معطّل» (العلَم OFF — الوضع الافتراضي حالياً)
  ///   - 403 صلاحية/ليس أدمن شركة
  ///   - 429 تجاوز عدد المحاولات
  /// يُرجع data = {password} عند النجاح، وMap موحّدة مع statusCode في كل الحالات.
  Future<Map<String, dynamic>> revealSas(String sasAccountId) async {
    final response = await _client.post(
      '/linked-accounts/sas/$sasAccountId/reveal',
      {},
      (json) => json,
    );
    return _toMap(response);
  }

  /// تعيين حساب FTTH كأساسي (يستخدم مسار التعديل).
  Future<Map<String, dynamic>> setPrimaryFtth(String id) async {
    return updateFtth(id, isPrimary: true);
  }

  // ═══════════════ إدارة حسابات الساس ═══════════════

  /// ربط حساب ساس جديد — يُمرَّر ownerUserId = معرّف الموظف المعروض.
  /// accountType: 0 = SasManager (صفحة وكيل)، 1 = SasUser (نظام ساس). الافتراضي 0.
  /// amountMultiplier: مُضاعِف المبلغ، الافتراضي 1000.
  Future<Map<String, dynamic>> createSas({
    required String ownerUserId,
    required String label,
    required String serverUrl,
    required String username,
    required String password,
    int accountType = 0,
    double amountMultiplier = 1000,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{
      'ownerUserId': ownerUserId,
      'label': label,
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'accountType': accountType,
      'amountMultiplier': amountMultiplier,
      if (isActive != null) 'isActive': isActive,
    };
    final response =
        await _client.post('/linked-accounts/sas', body, (json) => json);
    return _toMap(response);
  }

  /// تعديل حساب ساس. كلمة المرور فارغة = إبقاؤها بلا تغيير.
  Future<Map<String, dynamic>> updateSas(
    String id, {
    String? label,
    String? serverUrl,
    String? username,
    String? password,
    int? accountType,
    double? amountMultiplier,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{
      if (label != null) 'label': label,
      if (serverUrl != null) 'serverUrl': serverUrl,
      if (username != null) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      if (accountType != null) 'accountType': accountType,
      if (amountMultiplier != null) 'amountMultiplier': amountMultiplier,
      if (isActive != null) 'isActive': isActive,
    };
    final response =
        await _client.put('/linked-accounts/sas/$id', body, (json) => json);
    return _toMap(response);
  }

  /// حذف حساب ساس.
  Future<Map<String, dynamic>> deleteSas(String id) async {
    final response =
        await _client.delete('/linked-accounts/sas/$id', (json) => json);
    return _toMap(response);
  }
}
