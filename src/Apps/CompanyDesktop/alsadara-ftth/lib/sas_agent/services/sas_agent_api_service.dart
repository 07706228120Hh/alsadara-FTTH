import '../../services/sadara_api_service.dart';
import '../models/sas_account.dart';
import '../models/sas_dashboard.dart';
import '../models/sas_renewal.dart';
import '../models/sas_subscriber.dart';

/// خدمة API لوحدة «وكيل الساس» — تخاطب بوّابة الصدارة `/api/sas-agent/*`.
///
/// - الاتصال عبر [SadaraApiService] الموجود مسبقاً (Bearer token من VpsAuthService).
/// - العزل الثلاثي (شركة + مالك + صلاحية) مفروض في الخادم؛ لا نمرّر أي هوية هنا.
/// - ⚠️ كلمة مرور الساس تُرسَل فقط في الإنشاء/التعديل ولا تُخزَّن ولا تُطبَع.
class SasAgentApiService {
  static SasAgentApiService? _instance;
  static SasAgentApiService get instance =>
      _instance ??= SasAgentApiService._internal();
  SasAgentApiService._internal();

  final SadaraApiService _api = SadaraApiService.instance;

  static const String _base = '/sas-agent';

  // ============================================================
  //  إدارة الحسابات (قاعدة بيانات الصدارة)
  // ============================================================

  /// جلب حسابات الساس للمستخدم الحالي (بلا كلمات مرور).
  Future<List<SasAccount>> getAccounts() async {
    final res = await _api.get('$_base/accounts');
    final data = res['data'];
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => SasAccount.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  /// ربط حساب ساس جديد. تعيد الحساب المنشأ.
  Future<SasAccount?> createAccount({
    required String label,
    required String serverUrl,
    required String username,
    required String password,
    required SasAccountType accountType,
    bool isActive = true,
  }) async {
    final res = await _api.post('$_base/accounts', body: {
      'label': label,
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
      'accountType': accountType.apiValue,
      'isActive': isActive,
    });
    final data = res['data'];
    if (data is Map) {
      return SasAccount.fromJson(data.cast<String, dynamic>());
    }
    return null;
  }

  /// تعديل حساب ساس. كلمة المرور اختيارية — تُرسَل فقط عند تغييرها.
  Future<bool> updateAccount(
    String id, {
    String? label,
    String? serverUrl,
    String? username,
    String? password,
    SasAccountType? accountType,
    bool? isActive,
  }) async {
    final body = <String, dynamic>{
      if (label != null) 'label': label,
      if (serverUrl != null) 'serverUrl': serverUrl,
      if (username != null) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      if (accountType != null) 'accountType': accountType.apiValue,
      if (isActive != null) 'isActive': isActive,
    };
    final res = await _api.put('$_base/accounts/$id', body: body);
    return res['success'] == true;
  }

  /// حذف حساب ساس (حذف ناعم في الخادم).
  Future<bool> deleteAccount(String id) async {
    final res = await _api.delete('$_base/accounts/$id');
    return res['success'] == true;
  }

  // ============================================================
  //  تمرير لخدمة الساس
  // ============================================================

  /// تسجيل دخول صامت لنظام الساس باعتماد الحساب.
  Future<bool> login(String id) async {
    final res = await _api.post('$_base/accounts/$id/login', body: {});
    return res['success'] == true;
  }

  /// جلب لوحة الوكيل من نظام الساس.
  Future<SasDashboard> getDashboard(String id) async {
    final res = await _api.get('$_base/accounts/$id/dashboard');
    return SasDashboard.fromJson(res);
  }

  /// جلب مشتركي الوكيل من نظام الساس (يدعم بحث/صفحات مسموحة في الخادم).
  Future<List<SasSubscriber>> getSubscribers(
    String id, {
    String? search,
    int? page,
    int? pageSize,
    String? status,
  }) async {
    final params = <String>[];
    if (search != null && search.isNotEmpty) params.add('search=$search');
    if (page != null) params.add('page=$page');
    if (pageSize != null) params.add('pageSize=$pageSize');
    if (status != null && status.isNotEmpty) params.add('status=$status');
    final qs = params.isEmpty ? '' : '?${params.join('&')}';

    final res = await _api.get('$_base/accounts/$id/subscribers$qs');
    // الاستجابة خام من نظام الساس: قد تكون قائمة مباشرة أو مغلّفة في data/rows.
    dynamic list = res['data'] ?? res['rows'] ?? res['subscribers'];
    if (list is Map) {
      list = list['data'] ?? list['rows'] ?? list['items'];
    }
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => SasSubscriber.fromJson(e.cast<String, dynamic>()))
          .toList();
    }
    return const [];
  }

  /// جلب تقرير الوكيل (التصريح/البلنك) — يعاد خاماً للعرض المرحلي.
  Future<Map<String, dynamic>> getReport(
    String id, {
    String? from,
    String? to,
  }) async {
    final params = <String>[];
    if (from != null && from.isNotEmpty) params.add('from=$from');
    if (to != null && to.isNotEmpty) params.add('to=$to');
    final qs = params.isEmpty ? '' : '?${params.join('&')}';
    return await _api.get('$_base/accounts/$id/report$qs');
  }

  // ============================================================
  //  نظام الساس: باقات · مالية · صحّة
  // ============================================================

  /// جلب باقات/بروفايلات الساس للحساب — تُعاد خاماً كقائمة خرائط.
  ///
  /// الاستجابة قد تكون قائمة مباشرة أو مغلّفة في data/rows/items.
  Future<List<Map<String, dynamic>>> getPackages(String id) async {
    final res = await _api.get('$_base/accounts/$id/packages');
    return _asMapList(res['data'] ?? res['rows'] ?? res['items'] ?? res);
  }

  /// جلب الملخّص المالي للحساب — يُعاد خاماً للعرض.
  Future<Map<String, dynamic>> getFinance(String id) async {
    final res = await _api.get('$_base/accounts/$id/finance');
    final data = res['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return res;
  }

  /// جلب صحّة نظام الساس للحساب — يُعاد خاماً للعرض.
  Future<Map<String, dynamic>> getHealth(String id) async {
    final res = await _api.get('$_base/accounts/$id/health');
    final data = res['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return res;
  }

  // ============================================================
  //  التجديد: مرشّحون + تجديد جماعي (معاينة/تنفيذ)
  // ============================================================

  /// جلب المشتركين قرب الانتهاء خلال [days] يوماً.
  Future<List<SasRenewalCandidate>> getRenewalCandidates(
    String id, {
    int days = 7,
  }) async {
    final res = await _api.get('$_base/accounts/$id/renewal/candidates?days=$days');
    final list = _asMapList(res['data'] ?? res['rows'] ?? res['items'] ?? res);
    return list.map(SasRenewalCandidate.fromJson).toList();
  }

  /// تجديد جماعي — يجب أن يبدأ دائماً بـ [dryRun]=true للمعاينة ثم يُنفَّذ.
  ///
  /// [subscriberIds] معرّفات المشتركين · [months] عدد الأشهر (1..60)
  /// · [profileId] بروفايل اختياري للترقية · [dryRun] معاينة بلا تنفيذ.
  Future<List<SasRenewalResult>> renewalBulk(
    String id, {
    required List<String> subscriberIds,
    required int months,
    String? profileId,
    required bool dryRun,
  }) async {
    final res = await _api.post('$_base/accounts/$id/renewal/bulk', body: {
      'subscriberIds': subscriberIds,
      'months': months,
      if (profileId != null && profileId.isNotEmpty) 'profileId': profileId,
      'dryRun': dryRun,
    });
    final list = _asMapList(res['data'] ?? res['results'] ?? res['rows'] ?? res);
    return list.map(SasRenewalResult.fromJson).toList();
  }

  /// أداة داخلية: تحويل استجابة مرنة إلى قائمة خرائط.
  List<Map<String, dynamic>> _asMapList(dynamic raw) {
    var list = raw;
    if (list is Map) {
      list = list['data'] ?? list['rows'] ?? list['items'];
    }
    if (list is List) {
      return list
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return const [];
  }
}
