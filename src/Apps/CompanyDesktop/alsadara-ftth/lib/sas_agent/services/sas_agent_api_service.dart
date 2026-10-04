import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/sadara_api_service.dart';
import '../../services/vps_auth_service.dart';
import '../models/sas_account.dart';
import '../models/sas_accounting.dart';
import '../models/sas_admin_agent.dart';
import '../models/sas_dashboard.dart';
import '../models/sas_renewal.dart';
import '../models/sas_report.dart';
import '../models/sas_subscriber.dart';
import '../models/sas_subscriber_summary.dart';
import '../models/sas_ticket.dart';
import '../models/sas_transaction.dart';
import '../premises/models/premises.dart';

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
  //  إدارة الوكلاء (للأدمن فقط) — البلنك الموحّد على مستوى الشركة
  // ============================================================

  /// إدارة الوكلاء للأدمن — `GET admin/agents`.
  ///
  /// يعيد وكلاء الشركة (ملّاك حسابات ساس) مع حساباتهم ومقاطعتها (البلنك
  /// الموحّد). المقاطعة قد تكون `null` لكل حساب إذا تعذّرت خدمة الساس؛
  /// النموذج يتحمّل ذلك (يُعرَض «تعذّر جلب المقاطعة»).
  ///
  /// - الحماية النهائية في الخادم: يرفض `403` غير الأدمن؛ نُطلق حينها
  ///   [SasAdminForbiddenException] لتُعرَض حالة «للمشرفين فقط» بلا انهيار.
  /// - لا نمرّر أي هوية هنا؛ العزل (شركة + دور) يفرضه الخادم.
  Future<List<SasAdminAgent>> getAdminAgents() async {
    final token = VpsAuthService.instance.accessToken;
    final uri = Uri.parse('${SadaraApiService.baseUrl}$_base/admin/agents');
    final res = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );

    if (res.statusCode == 403) {
      throw const SasAdminForbiddenException();
    }
    if (res.statusCode == 401) {
      throw Exception('انتهت صلاحية الجلسة - يرجى تسجيل الدخول مرة أخرى');
    }

    Map<String, dynamic> decoded;
    try {
      final d = json.decode(res.body);
      decoded = d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
    } on FormatException {
      decoded = <String, dynamic>{};
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
          decoded['message'] ?? 'خطأ غير معروف (${res.statusCode})');
    }

    final list = _asMapList(decoded['data'] ?? decoded);
    return list.map(SasAdminAgent.fromJson).toList();
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
  //  اختبار/مزامنة الحساب + المشتركون المحليون (سريع، بلا نداء ساس)
  // ============================================================

  /// اختبار الاتصال بحساب الساس — `POST accounts/{id}/test`.
  /// يعيد `{ok, message, subscribers_count?}`.
  Future<SasTestResult> testAccount(String id) async {
    final res = await _api.post('$_base/accounts/$id/test', body: {});
    return SasTestResult.fromJson(res);
  }

  /// مزامنة محلية للحساب — `POST accounts/{id}/sync`.
  /// يعيد `{count, expiry:{overdue,today,soon3,soon7}, synced_at}`.
  Future<SasSyncResult> syncAccount(String id) async {
    final res = await _api.post('$_base/accounts/$id/sync', body: {});
    return SasSyncResult.fromJson(res);
  }

  /// ملخّص المشتركين المحلّي الموثوق — `GET accounts/{id}/subscribers/summary`.
  ///
  /// المصدر قاعدة الصدارة (بعد المزامنة) لا لوحة الساس الحيّة؛ الأرقام ثابتة
  /// وموثوقة. يعيد `{total, active, expired, online, expiry{...}, last_sync}`
  /// (قد يعود ملفوفاً بـ `data`؛ النموذج يقرأ بمرونة snake_case/camelCase).
  Future<SasSubscriberSummary> getSubscribersSummary(String id) async {
    final res = await _api.get('$_base/accounts/$id/subscribers/summary');
    return SasSubscriberSummary.fromJson(res);
  }

  /// المشتركون المحليون (سريع، من قاعدة الصدارة بعد المزامنة) —
  /// `GET accounts/{id}/subscribers-local`.
  ///
  /// [search] بحث نصّي حُر (اسم/معرّف المشترك).
  /// [status] فلتر الحالة: `active` / `expired` (اختياري، null = الكل).
  /// [profile] فلتر الباقة/البروفايل (اختياري).
  /// [expiring] فلتر عدّاد الانتهاء: overdue/today/soon3/soon7 (اختياري).
  Future<SasLocalSubscribersPage> getLocalSubscribers(
    String id, {
    String? search,
    String? status,
    String? profile,
    String? expiring,
    int? page,
    int? count,
  }) async {
    final params = <String>[];
    if (search != null && search.isNotEmpty) {
      params.add('search=${Uri.encodeQueryComponent(search)}');
    }
    if (status != null && status.isNotEmpty) {
      params.add('status=${Uri.encodeQueryComponent(status)}');
    }
    if (profile != null && profile.isNotEmpty) {
      params.add('profile=${Uri.encodeQueryComponent(profile)}');
    }
    if (expiring != null && expiring.isNotEmpty) {
      params.add('expiring=${Uri.encodeQueryComponent(expiring)}');
    }
    if (page != null) params.add('page=$page');
    if (count != null) params.add('count=$count');
    final qs = params.isEmpty ? '' : '?${params.join('&')}';
    final res = await _api.get('$_base/accounts/$id/subscribers-local$qs');
    return SasLocalSubscribersPage.fromJson(res);
  }

  // ============================================================
  //  التصريح/البلنك: إرسال تصريح · سجل التصاريح · المقاطعة
  // ============================================================

  /// إرسال تصريح جديد — `POST accounts/{id}/report`.
  /// يعيد التصريح المُنشأ (AgentReport).
  Future<SasAgentReport?> submitReport(
    String id, {
    required int declaredTotal,
    required int declaredActive,
    String? note,
  }) async {
    final res = await _api.post('$_base/accounts/$id/report', body: {
      'declaredTotal': declaredTotal,
      'declaredActive': declaredActive,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    final data = res['data'];
    if (data is Map) {
      return SasAgentReport.fromJson(data.cast<String, dynamic>());
    }
    // بعض الردود تعيد الحقول في الجذر مباشرةً.
    if (res.containsKey('declaredTotal') || res.containsKey('id')) {
      return SasAgentReport.fromJson(res);
    }
    return null;
  }

  /// سجل تصاريح الحساب — `GET accounts/{id}/reports`.
  Future<List<SasAgentReport>> listReports(String id) async {
    final res = await _api.get('$_base/accounts/$id/reports');
    final list = _asMapList(res['data'] ?? res['rows'] ?? res['items'] ?? res);
    return list.map(SasAgentReport.fromJson).toList();
  }

  /// مقاطعة التصريح مقابل الفعلي — `GET accounts/{id}/reconciliation`.
  /// يعيد `{declared, actual, diff, verdict, source}`.
  Future<SasReconciliation> getReconciliation(String id) async {
    final res = await _api.get('$_base/accounts/$id/reconciliation');
    final data = res['data'];
    if (data is Map) {
      return SasReconciliation.fromJson(data.cast<String, dynamic>());
    }
    return SasReconciliation.fromJson(res);
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

  /// تجديد جماعي **مفوتر** — ينفّذ فعلياً على الساس ويختم القيد المزدوج وحركة
  /// الاشتراك في دفتر الصدارة الموحّد (Source=sas) لكل مشترك ناجح، ويعيد الرد
  /// كاملاً مع `results` (كلّ عنصر قد يحمل `receipt` للطباعة/الواتساب).
  ///
  /// ⚠️ عملية فعلية تخصم من رصيد الوكيل — لا معاينة. السعر يُحسب **خادمياً**؛
  /// لا نرسل أي سعر من العميل. الهوية والعزل (شركة + مالك) مختومان خادمياً.
  ///
  /// [action] أحد: `extend` (افتراضي) · `activate`.
  /// يعيد الخريطة العُليا كما هي:
  /// `{ success, total, succeeded, failed, results:[{uid, ok, message,
  ///    logId?, journalEntryId?, receipt?{...}}] }`.
  Future<Map<String, dynamic>> renewalBulkBilled(
    String id, {
    required List<String> subscriberIds,
    String action = 'extend',
    int? months,
    String? profileId,
    required String collectionType,
    num? maintenanceFee,
    num? manualDiscount,
    bool systemDiscountEnabled = true,
    String? linkedAgentId,
  }) async {
    final res = await _api.post(
      '$_base/accounts/$id/renewal/bulk-billed',
      body: {
        'subscriberIds': subscriberIds,
        'action': action,
        if (months != null) 'months': months,
        if (profileId != null && profileId.isNotEmpty) 'profileId': profileId,
        'collectionType': collectionType,
        if (maintenanceFee != null) 'maintenanceFee': maintenanceFee,
        if (manualDiscount != null) 'manualDiscount': manualDiscount,
        'systemDiscountEnabled': systemDiscountEnabled,
        if (linkedAgentId != null && linkedAgentId.isNotEmpty)
          'linkedAgentId': linkedAgentId,
      },
    );
    return _asMapKeepTop(res);
  }

  // ============================================================
  //  سجل الحركات المفوترة (Source=sas) — من دفتر الصدارة
  // ============================================================

  /// سجلّ حركات العمليات المفوترة للحساب — `GET accounts/{id}/transactions`.
  ///
  /// يعيد صفحة مُرقّمة `{total, data:[...]}` (النموذج متساهل مع التسمية). العزل
  /// (شركة + مالك) يفرضه الخادم؛ لا نمرّر أي هوية هنا.
  Future<SasTransactionsPage> getTransactions(
    String id, {
    int limit = 50,
    int offset = 0,
  }) async {
    final res =
        await _api.get('$_base/accounts/$id/transactions?limit=$limit&offset=$offset');
    return SasTransactionsPage.fromJson(_asMapKeepTop(res));
  }

  // ============================================================
  //  النظام المحاسبي (المرحلة 5): تسعير · معلومات مواطن · كشف · ذمم
  // ============================================================

  /// جلب أسعار الباقات (كلفة/بيع/ربح/مفعّل) — `GET accounts/{id}/package-prices`.
  ///
  /// يُملأ تلقائياً من باقات الساس في الخادم إن لم تُسعَّر بعد؛ الربح محسوب للعرض.
  Future<List<SasPackagePrice>> getPackagePrices(String id) async {
    final res = await _api.get('$_base/accounts/$id/package-prices');
    final list = _asMapList(res['data'] ?? res['rows'] ?? res['items'] ?? res);
    return list.map(SasPackagePrice.fromJson).toList();
  }

  /// حفظ أسعار الباقات — `PUT accounts/{id}/package-prices`.
  /// نُرسل الكلفة/البيع/المفعّل فقط (الربح يُحسب خادمياً).
  Future<bool> savePackagePrices(
      String id, List<SasPackagePrice> items) async {
    final res = await _api.put('$_base/accounts/$id/package-prices', body: {
      'items': items.map((e) => e.toSaveJson()).toList(),
    });
    return res['success'] != false;
  }

  // ============================================================
  //  المناطق (SasRegion) — بيانات رئيسية على مستوى الشركة
  //  (company-scoped: لا تحتاج معرّف حساب)
  // ============================================================

  /// قائمة مناطق الشركة (مع عدد المشتركين) — `GET regions`.
  Future<List<SasRegion>> getRegions() async {
    final res = await _api.get('$_base/regions');
    final list = _asMapList(res['data'] ?? res['rows'] ?? res['items'] ?? res);
    return list.map(SasRegion.fromJson).toList();
  }

  /// إنشاء منطقة — `POST regions`. تعيد المنطقة المنشأة أو null.
  Future<SasRegion?> createRegion(SasRegion region) async {
    final res = await _api.post('$_base/regions', body: region.toSaveJson());
    final data = res['data'];
    if (data is Map) return SasRegion.fromJson(data.cast<String, dynamic>());
    return null;
  }

  /// تعديل منطقة — `PUT regions/{rid}`.
  Future<bool> updateRegion(String rid, SasRegion region) async {
    final res = await _api.put('$_base/regions/$rid', body: region.toSaveJson());
    return res['success'] != false;
  }

  /// حذف منطقة (ناعم) — `DELETE regions/{rid}`. يفشل إن كانت مرتبطة بمشتركين.
  Future<bool> deleteRegion(String rid) async {
    final res = await _api.delete('$_base/regions/$rid');
    return res['success'] == true;
  }

  /// تقرير أرباح الساس للشركة ضمن فترة — `GET reports/profits`.
  Future<SasProfitReport> getProfitsReport({DateTime? from, DateTime? to}) async {
    final qs = <String>[];
    if (from != null) qs.add('from=${from.toUtc().toIso8601String()}');
    if (to != null) qs.add('to=${to.toUtc().toIso8601String()}');
    final suffix = qs.isEmpty ? '' : '?${qs.join('&')}';
    final res = await _api.get('$_base/reports/profits$suffix');
    return SasProfitReport.fromJson(_asMapKeepTop(res));
  }

  /// جلب معلومات المواطن الموسّعة — `GET accounts/{id}/users/{uid}/profile`.
  Future<SasSubscriberProfile> getSubscriberProfile(
      String id, String uid) async {
    final res = await _api.get('$_base/accounts/$id/users/$uid/profile');
    return SasSubscriberProfile.fromJson(_asMap(res));
  }

  /// حفظ معلومات المواطن الموسّعة — `PUT accounts/{id}/users/{uid}/profile`.
  Future<bool> saveSubscriberProfile(
      String id, String uid, SasSubscriberProfile fields) async {
    final res = await _api.put(
      '$_base/accounts/$id/users/$uid/profile',
      body: fields.toSaveJson(),
    );
    return res['success'] != false;
  }

  /// كشف حساب المواطن (شحنات + تسديدات + رصيد مستحق) —
  /// `GET accounts/{id}/users/{uid}/statement`.
  Future<SasCitizenStatement> getStatement(String id, String uid) async {
    final res = await _api.get('$_base/accounts/$id/users/$uid/statement');
    return SasCitizenStatement.fromJson(_asMapKeepTop(res));
  }

  /// تسجيل تسديد على ذمّة المواطن — `POST accounts/{id}/users/{uid}/payment`.
  /// ⚠️ عملية مالية (يؤكّدها المستدعي). [method] أحد: `cash` · `master`.
  Future<SasPaymentResult> recordCitizenPayment(
    String id,
    String uid, {
    required num amount,
    required String method,
    String? note,
  }) async {
    final res = await _api.post(
      '$_base/accounts/$id/users/$uid/payment',
      body: {
        'amount': amount,
        'method': method,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return SasPaymentResult.fromJson(_asMapKeepTop(res));
  }

  /// قائمة المشتركين المدينين (الاسم/المعرّف + الرصيد) —
  /// `GET accounts/{id}/debtors`.
  Future<List<SasDebtor>> getDebtors(String id) async {
    final res = await _api.get('$_base/accounts/$id/debtors');
    final list = _asMapList(res['data'] ?? res['rows'] ?? res['items'] ?? res);
    return list.map(SasDebtor.fromJson).toList();
  }

  // ============================================================
  //  مشترك واحد: تفاصيل · نظرة عامة · سجل · بيانات التمديد
  //  (account-scoped قراءات تحت /accounts/{id}/users/...)
  // ============================================================

  /// تفاصيل مشترك كاملة — تُعاد خريطة الحقول (تُفكّ من غلاف `data` إن وُجد).
  Future<Map<String, dynamic>> getUserDetail(String id, String uid) async {
    final res = await _api.get('$_base/accounts/$id/users/$uid/detail');
    return _asMap(res);
  }

  /// نظرة عامة على مشترك محدّد (رصيد/باقة/مرور متبقٍّ…) — تُعاد خام.
  Future<Map<String, dynamic>> getUserOverview(String id, String uid) async {
    final res = await _api.get('$_base/accounts/$id/users/$uid/overview');
    return _asMap(res);
  }

  /// سجل/تاريخ مشترك — قائمة أحداث.
  Future<List<Map<String, dynamic>>> getUserHistory(String id, String uid) async {
    final res = await _api.get('$_base/accounts/$id/users/$uid/history');
    return _asMapList(res['data'] ?? res);
  }

  /// بيانات التمديد (وسائط + سعر…) — تُعاد خام؛ [profileId] اختياري (مُررّ كمسار بروكسي عند الحاجة).
  Future<Map<String, dynamic>> getUserExtendData(String id, String uid,
      {String? profileId}) async {
    // البوّابة لا تستقبل profile_id على هذه النقطة؛ نُبقيه للتوافق ونستخدم البروكسي عند تمريره.
    if (profileId != null && profileId.isNotEmpty) {
      final res = await sasGet(id, 'allowedExtensions/$profileId');
      return _asMap(res);
    }
    final res = await _api.get('$_base/accounts/$id/users/$uid/extend-data');
    return _asMap(res);
  }

  // ============================================================
  //  مشترك واحد: كتابات (إجراء · إنشاء · تعديل · حذف · استرداد)
  // ============================================================

  /// تنفيذ إجراء على مشترك: activate/extend/changeProfile/addTraffic/deposit/
  /// withdraw/ping/rename — يُعاد الرد الخام. ⚠️ عملية كتابية (يؤكّدها المستدعي).
  Future<Map<String, dynamic>> userAction(
    String id,
    String uid,
    String action, {
    Map<String, dynamic> params = const {},
  }) async {
    final res = await _api.post('$_base/accounts/$id/users/$uid/action', body: {
      'action': action,
      'params': params,
    });
    return _asMap(res);
  }

  /// تفعيل/تمديد/تغيير باقة **مفوتر** — ينفّذ على الساس ثم يختم القيد المزدوج
  /// وحركة الاشتراك في دفتر الصدارة الموحّد (Source=sas)، ويعيد بيانات الإيصال.
  ///
  /// ⚠️ السعر يُحسب **خادمياً** من `activationData` — لا نُرسل السعر من العميل.
  /// الهوية والعزل (شركة + مالك) مختومان خادمياً. [transactionId] يمنع التكرار.
  ///
  /// [action] أحد: `activate` · `extend` · `changeProfile`.
  /// يعيد خريطة الرد الكاملة متضمّنةً `receipt` (operationType/planName/months/
  /// basePrice/maintenanceFee/manualDiscount/collectedAmount/currency/
  /// collectionType/transactionId/activatedByUserId/subscriberUsername).
  Future<Map<String, dynamic>> activateBilled(
    String id,
    String uid, {
    required String action,
    int? months,
    String? profileId,
    required String collectionType,
    num? maintenanceFee,
    num? manualDiscount,
    bool systemDiscountEnabled = true,
    String? linkedAgentId,
    String? phone,
    String? subscriberUsername,
    String? transactionId,
    String? note,
  }) async {
    final res = await _api.post(
      '$_base/accounts/$id/users/$uid/activate-billed',
      body: {
        'action': action,
        if (months != null) 'months': months,
        if (profileId != null && profileId.isNotEmpty) 'profileId': profileId,
        'collectionType': collectionType,
        if (maintenanceFee != null) 'maintenanceFee': maintenanceFee,
        if (manualDiscount != null) 'manualDiscount': manualDiscount,
        'systemDiscountEnabled': systemDiscountEnabled,
        if (linkedAgentId != null && linkedAgentId.isNotEmpty)
          'linkedAgentId': linkedAgentId,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (subscriberUsername != null && subscriberUsername.isNotEmpty)
          'subscriberUsername': subscriberUsername,
        if (transactionId != null && transactionId.isNotEmpty)
          'transactionId': transactionId,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return _asMapKeepTop(res);
  }

  /// يُعلّم سجل اشتراك الساس بأن رسالة واتساب أُرسلت فعلاً (IsWhatsAppSent=true).
  /// idempotent وصامت الفشل عند المستدعي (لا يُفشل العملية الأساسية).
  Future<void> reportWhatsAppSent(String id, int logId) async {
    await _api.post(
      '$_base/accounts/$id/subscription-logs/$logId/whatsapp-sent',
      body: const {},
    );
  }

  /// إجراء جماعي على عدة مشتركين على الحساب نفسه.
  Future<Map<String, dynamic>> usersBulkAction(
    String id,
    List<String> uids,
    String action, {
    Map<String, dynamic> params = const {},
  }) async {
    final res = await _api.post('$_base/accounts/$id/users/bulk-action', body: {
      'uids': uids,
      'action': action,
      'params': params,
    });
    return _asMap(res);
  }

  /// إنشاء مشترك جديد — [payload] الحمولة الكاملة (بلا حقن هوية).
  Future<Map<String, dynamic>> createUser(
      String id, Map<String, dynamic> payload) async {
    final res = await _api.post('$_base/accounts/$id/users/create', body: {
      'payload': payload,
    });
    return _asMap(res);
  }

  /// تعديل مشترك — [payload] الحقول المُحدَّثة.
  Future<Map<String, dynamic>> updateUser(
      String id, String uid, Map<String, dynamic> payload) async {
    final res = await _api.put('$_base/accounts/$id/users/$uid', body: {
      'payload': payload,
    });
    return _asMap(res);
  }

  /// حذف مشترك نهائياً من نظام الساس.
  Future<bool> deleteUser(String id, String uid) async {
    final res = await _api.delete('$_base/accounts/$id/users/$uid');
    return res['success'] != false; // البوّابة تعيد رد الساس الخام أو {success}
  }

  /// بيانات الاسترداد قبل التنفيذ (refund_amount/price/remaining_days) — تحضير كتابي.
  Future<Map<String, dynamic>> getUserRefundData(String id, String uid) async {
    final res =
        await _api.post('$_base/accounts/$id/users/$uid/refund-data', body: {});
    return _asMap(res);
  }

  /// تنفيذ الإلغاء والاسترداد — عملية مالية (يؤكّدها المستدعي).
  Future<Map<String, dynamic>> refundUser(String id, String uid) async {
    final res =
        await _api.post('$_base/accounts/$id/users/$uid/refund', body: {});
    return _asMap(res);
  }

  // ============================================================
  //  المتصلون · الوكلاء/المدراء
  // ============================================================

  /// قائمة المتصلين حالياً — تُعاد خام كقائمة خرائط.
  Future<List<Map<String, dynamic>>> getOnline(String id) async {
    final res = await _api.get('$_base/accounts/$id/online');
    return _asMapList(res['data'] ?? res['rows'] ?? res);
  }

  /// قائمة الوكلاء/المدراء — تُعاد خام كقائمة خرائط.
  Future<List<Map<String, dynamic>>> getManagers(String id) async {
    final res = await _api.get('$_base/accounts/$id/managers');
    return _asMapList(res['data'] ?? res['rows'] ?? res);
  }

  /// تنفيذ إجراء على وكيل/مدير — عملية كتابية (يؤكّدها المستدعي).
  Future<Map<String, dynamic>> managerAction(
    String id,
    String mid,
    String action, {
    Map<String, dynamic> params = const {},
  }) async {
    final res =
        await _api.post('$_base/accounts/$id/managers/$mid/action', body: {
      'action': action,
      'params': params,
    });
    return _asMap(res);
  }

  /// حذف وكيل/مدير — عملية كتابية (يؤكّدها المستدعي).
  Future<bool> deleteManager(String id, String mid) async {
    final res = await _api.delete('$_base/accounts/$id/managers/$mid');
    return res['success'] != false;
  }

  // ============================================================
  //  مستكشف الساس: فكّ حمولات مشفّرة دفعةً واحدة
  // ============================================================

  /// يفكّ دفعة حمولات ساس مشفّرة (مستكشف الساس) — `POST explorer/decrypt`.
  ///
  /// فكّ AES يجري **داخل الخدمة** بمفتاح SAS4 الثابت (بلا اعتماد، محصورة
  /// بالمسؤول خادمياً). [items] قائمة الحمولات المشفّرة (base64). يعيد قائمة
  /// نتائج بالترتيب نفسه: `{ok:true, text:"..."}` أو `{ok:false, error:"..."}`.
  Future<List<Map<String, dynamic>>> decryptPayloads(List<String> items) async {
    final res = await _api.post('$_base/explorer/decrypt', body: {'items': items});
    final data = res['data'];
    final list = (data is Map ? data['results'] : null) ?? res['results'];
    return (list is List)
        ? list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : const [];
  }

  // ============================================================
  //  البروكسي العام لـ SAS (مسارات index/* المسموحة)
  // ============================================================

  /// بروكسي GET عام لأي مسار ساس مسموح — يُعاد الرد الخام.
  Future<dynamic> sasGet(String id, String path) async {
    final res = await _api.get('$_base/accounts/$id/sas/get?path=$path');
    return res;
  }

  /// بروكسي POST عام لأي مسار ساس مسموح (جلسات/فواتير/إيصالات/قيود/حصص/ترافيك) —
  /// يُعاد الرد الخام. يُستخدم لتبويبات `index/*` القائمة على ترقيم.
  Future<dynamic> sasPost(String id, String path,
      {Map<String, dynamic> payload = const {}}) async {
    final res = await _api.post('$_base/accounts/$id/sas/post', body: {
      'path': path,
      'payload': payload,
    });
    return res;
  }

  // ============================================================
  //  العقارات (Premises · user-scoped · بلا account id)
  //  تحت /api/sas-agent/premises — العزل (شركة + مالك) يفرضه الخادم.
  //  ⚠️ صورة الدار تُرسَل base64 (JSON) لا multipart.
  // ============================================================

  /// قائمة عقارات مُرقّمة/مُفلترة — `GET premises?search=&ownership=&ptype=&page=&count=`.
  Future<List<Premises>> getPremises({
    String? search,
    String? ownership,
    String? propertyType,
    int page = 1,
    int count = 50,
  }) async {
    final params = <String>['page=$page', 'count=$count'];
    if (search != null && search.isNotEmpty) {
      params.add('search=${Uri.encodeQueryComponent(search)}');
    }
    if (ownership != null && ownership.isNotEmpty) {
      params.add('ownership=$ownership');
    }
    if (propertyType != null && propertyType.isNotEmpty) {
      params.add('ptype=$propertyType');
    }
    final res = await _api.get('$_base/premises?${params.join('&')}');
    final list = _asMapList(
        res['premises'] ?? res['data'] ?? res['rows'] ?? res['items'] ?? res);
    return list.map(Premises.fromJson).toList();
  }

  /// عقار واحد بتفاصيله (يتضمّن اشتراكاته) — `GET premises/{pid}`.
  Future<Premises> getPremise(int pid) async {
    final res = await _api.get('$_base/premises/$pid');
    return Premises.fromJson(_asMap(res));
  }

  /// إنشاء عقار — `POST premises`. يعيد العقار المُنشأ.
  Future<Premises?> createPremise(Map<String, dynamic> body) async {
    final res = await _api.post('$_base/premises', body: body);
    final data = res['data'] ?? res['premises'];
    if (data is Map) return Premises.fromJson(data.cast<String, dynamic>());
    if (res.containsKey('id')) return Premises.fromJson(res);
    return null;
  }

  /// تعديل عقار — `PATCH premises/{pid}`. يعيد العقار المُحدَّث.
  Future<Premises?> updatePremise(int pid, Map<String, dynamic> body) async {
    final res = await _patch('$_base/premises/$pid', body);
    final data = res['data'] ?? res['premises'];
    if (data is Map) return Premises.fromJson(data.cast<String, dynamic>());
    if (res.containsKey('id')) return Premises.fromJson(res);
    return null;
  }

  /// حذف عقار — `DELETE premises/{pid}` (يفكّ ربط اشتراكاته ولا يحذفها).
  Future<bool> deletePremise(int pid) async {
    final res = await _api.delete('$_base/premises/$pid');
    return res['success'] != false;
  }

  /// رفع صورة الدار (base64) — `POST premises/{pid}/photo`.
  ///
  /// [bytes] بايتات الصورة (JPEG/PNG)؛ تُشفَّر base64 وتُرسَل في الجسم.
  /// لا تُخزَّن الصورة محلياً ولا تُطبَع في السجل.
  Future<bool> uploadPremisePhoto(
    int pid,
    List<int> bytes, {
    String contentType = 'image/jpeg',
  }) async {
    final res = await _api.post('$_base/premises/$pid/photo', body: {
      'contentType': contentType,
      'data': base64Encode(bytes),
    });
    return res['success'] != false;
  }

  /// جلب صورة الدار (bytes) — `GET premises/{pid}/photo`.
  /// يعيد null عند غياب الصورة.
  Future<List<int>?> getPremisePhoto(int pid) async {
    try {
      final bytes = await _api.getBytes('$_base/premises/$pid/photo');
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  /// اشتراكات مرتبطة بعقار — `GET premises/{pid}/subscribers`.
  Future<List<PremisesSub>> getPremiseSubscribers(int pid) async {
    final res = await _api.get('$_base/premises/$pid/subscribers');
    final list = _asMapList(
        res['subscribers'] ?? res['data'] ?? res['rows'] ?? res['items'] ?? res);
    return list.map(PremisesSub.fromJson).toList();
  }

  /// العقار المرتبط بمرجع اشتراك — `GET premises/by-subscriber/{sref}`.
  /// يعيد null إن لم يكن الاشتراك مرتبطاً بأي عقار.
  Future<Premises?> premiseBySubscriber(String subscriberRef) async {
    final res = await _api.get(
        '$_base/premises/by-subscriber/${Uri.encodeComponent(subscriberRef)}');
    final data = res['premises'] ?? res['data'];
    if (data is Map) return Premises.fromJson(data.cast<String, dynamic>());
    if (res.containsKey('id')) return Premises.fromJson(res);
    return null;
  }

  /// مرشّحو الربط (اشتراكات ضمن النطاق) — `GET premises/link-candidates?search=`.
  /// كل عنصر: `{ref/id, username, name, phone, premises_id?}`.
  Future<List<Map<String, dynamic>>> premiseLinkCandidates({
    String search = '',
  }) async {
    final qs =
        search.isEmpty ? '' : '?search=${Uri.encodeQueryComponent(search)}';
    final res = await _api.get('$_base/premises/link-candidates$qs');
    return _asMapList(
        res['candidates'] ?? res['data'] ?? res['rows'] ?? res['items'] ?? res);
  }

  /// ربط اشتراكات بعقار — `POST premises/{pid}/link`.
  Future<bool> linkPremiseSubscribers(
      int pid, List<String> subscriberRefs) async {
    final res = await _api.post('$_base/premises/$pid/link', body: {
      'subscriberRefs': subscriberRefs,
    });
    return res['success'] != false;
  }

  /// فكّ ربط اشتراكات عن عقار — `POST premises/{pid}/unlink`.
  Future<bool> unlinkPremiseSubscribers(
      int pid, List<String> subscriberRefs) async {
    final res = await _api.post('$_base/premises/$pid/unlink', body: {
      'subscriberRefs': subscriberRefs,
    });
    return res['success'] != false;
  }

  // ============================================================
  //  التذاكر (نظام تذاكر أصلي · user-scoped · بلا account id)
  //  تحت /api/sas-agent/tickets — العزل يفرضه الخادم.
  // ============================================================

  /// إحصاءات التذاكر — `GET tickets/stats`.
  /// يعيد `{total, open, in_progress, resolved, closed}`.
  Future<SasTicketStats> getTicketsStats() async {
    final res = await _api.get('$_base/tickets/stats');
    final data = res['data'];
    if (data is Map) {
      return SasTicketStats.fromJson(data.cast<String, dynamic>());
    }
    return SasTicketStats.fromJson(res);
  }

  /// قائمة تذاكر مُرقّمة — `GET tickets?status=&category=&search=&page=&count=`.
  Future<SasTicketsPage> getTickets({
    String? status,
    String? category,
    String? search,
    int page = 1,
    int count = 20,
  }) async {
    final params = <String>[
      'page=$page',
      'count=$count',
    ];
    if (status != null && status.isNotEmpty) params.add('status=$status');
    if (category != null && category.isNotEmpty) {
      params.add('category=$category');
    }
    if (search != null && search.isNotEmpty) {
      params.add('search=${Uri.encodeQueryComponent(search)}');
    }
    final res = await _api.get('$_base/tickets?${params.join('&')}');
    return SasTicketsPage.fromJson(res);
  }

  /// تذكرة واحدة + ردودها — `GET tickets/{ticketId}`.
  Future<SasTicket> getTicket(String ticketId) async {
    final res = await _api.get('$_base/tickets/$ticketId');
    return SasTicket.fromJson(_asMap(res));
  }

  /// إنشاء تذكرة — `POST tickets`.
  /// يعيد التذكرة المُنشأة عند توفّرها.
  Future<SasTicket?> createTicket({
    required String subject,
    required String body,
    String? category,
    String? priority,
    String? subscriberRef,
  }) async {
    final res = await _api.post('$_base/tickets', body: {
      'subject': subject,
      'body': body,
      if (category != null && category.isNotEmpty) 'category': category,
      if (priority != null && priority.isNotEmpty) 'priority': priority,
      if (subscriberRef != null && subscriberRef.isNotEmpty)
        'subscriberRef': subscriberRef,
    });
    final data = res['data'];
    if (data is Map) {
      return SasTicket.fromJson(data.cast<String, dynamic>());
    }
    if (res.containsKey('id') || res.containsKey('_id')) {
      return SasTicket.fromJson(res);
    }
    return null;
  }

  /// رد على تذكرة — `POST tickets/{ticketId}/reply`.
  /// [isInternal] ملاحظة داخلية لا تظهر للمشترك.
  Future<bool> replyTicket(
    String ticketId, {
    required String body,
    bool isInternal = false,
  }) async {
    final res = await _api.post('$_base/tickets/$ticketId/reply', body: {
      'body': body,
      'isInternal': isInternal,
    });
    return res['success'] != false;
  }

  /// تحديث تذكرة (حالة/أولوية/تصنيف) — `PATCH tickets/{ticketId}`.
  /// عملية كتابية (يحكمها `canAdd('sas_agent')` في الواجهة، والخادم نهائياً).
  Future<SasTicket?> updateTicket(
    String ticketId, {
    String? status,
    String? priority,
    String? category,
  }) async {
    final res = await _patch('$_base/tickets/$ticketId', {
      if (status != null && status.isNotEmpty) 'status': status,
      if (priority != null && priority.isNotEmpty) 'priority': priority,
      if (category != null && category.isNotEmpty) 'category': category,
    });
    final data = res['data'];
    if (data is Map) {
      return SasTicket.fromJson(data.cast<String, dynamic>());
    }
    if (res.containsKey('id') || res.containsKey('_id')) {
      return SasTicket.fromJson(res);
    }
    return null;
  }

  /// طلب PATCH — [SadaraApiService] لا يعرض `patch` عاماً، فننفّذه هنا
  /// بإعادة استخدام نفس القاعدة والتوكن الحيّ من [VpsAuthService] (بلا تخزين
  /// توكن ثابت، وبنفس عزل الجلسة الذي تعتمده بقية الخدمة).
  Future<Map<String, dynamic>> _patch(
      String endpoint, Map<String, dynamic> body) async {
    final token = VpsAuthService.instance.accessToken;
    final uri = Uri.parse('${SadaraApiService.baseUrl}$endpoint');
    final res = await http.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: json.encode(body),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('انتهت صلاحية الجلسة - يرجى تسجيل الدخول مرة أخرى');
    }
    Map<String, dynamic> decoded;
    try {
      final d = json.decode(res.body);
      decoded = d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};
    } on FormatException {
      decoded = <String, dynamic>{};
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    throw Exception(decoded['message'] ?? 'خطأ غير معروف (${res.statusCode})');
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

  /// أداة داخلية: يعيد الخريطة العُليا كما هي (بلا فكّ `data`) — لردود تحمل
  /// حقولاً في الجذر مباشرةً مثل `{success, logId, journalEntryId, receipt}`.
  Map<String, dynamic> _asMapKeepTop(dynamic raw) =>
      raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};

  /// أداة داخلية: يفكّ غلاف `data` إن كان خريطة، وإلا يعيد الخريطة كما هي.
  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      final data = raw['data'];
      if (data is Map) return data.cast<String, dynamic>();
      return raw.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }
}

/// استثناء «للمشرفين فقط» — يُطلَق عند رد الخادم `403` على نقطة إدارة الوكلاء.
///
/// تلتقطه الشاشة لعرض حالة صريحة بدل رسالة خطأ عامة (الحماية النهائية في
/// الخادم؛ إخفاء المدخل في الواجهة تحسينٌ للتجربة لا حاجزٌ أمني).
class SasAdminForbiddenException implements Exception {
  const SasAdminForbiddenException();
  @override
  String toString() => 'SasAdminForbiddenException';
}

/// مساعد لاستخراج قائمة خرائط من رد ساس مرن (خارج الخدمة — للاستهلاك في الصفحات).
List<Map<String, dynamic>> sasExtractList(dynamic raw) {
  var list = raw;
  if (list is Map) {
    list = list['data'] ?? list['rows'] ?? list['items'];
  }
  if (list is List) {
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
  return const [];
}
