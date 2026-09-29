import '../models/portal_summary.dart';
import '../models/subscriber_row.dart';
import '../models/ticket.dart';
import '../session.dart';
import 'api_core.dart';

/// عميل مسارات الموظّفين — تطبيق الوكلاء وتطبيق الشركات (ومنصّة الوزارة).
/// العزل يفرضه الباكند حسب نطاق التوكن؛ هنا لا منطق صلاحيات.
class StaffApi {
  final ApiCore core;
  StaffApi({ApiCore? core}) : core = core ?? ApiCore();

  /// نطاق حساب SAS الافتراضي لهذه النسخة — يُحقن تلقائياً في كل نداءات SAS (تعدّد
  /// حسابات الوكيل). null = بلا تحديد (قوائم مدموجة عبر الحسابات / اعتماد الشركة).
  int? sasAccountScope;

  /// نسخة من هذا العميل مُنطّقة بحساب SAS محدّد (تشارك نفس الجلسة/التوكن).
  StaffApi scopedToSasAccount(int? id) => StaffApi(core: core)..sasAccountScope = id;

  /// المعرّف الفعّال: المُمرَّر صراحةً، وإلا نطاق النسخة.
  int? _sid(int? a) => a ?? sasAccountScope;

  // ─── المصادقة ───

  /// تسجيل الدخول ثم قراءة /me لتثبيت النطاق ونوع الحساب في الجلسة.
  /// [expected] إن حُدّد ويخالف نوع الحساب → يُرفض الدخول (تطبيق الوكلاء لا يقبل حساب شركة).
  Future<AccountKind> login(String username, String password, {AccountKind? expected}) async {
    final j = await core.post('/api/auth/login', {'username': username, 'password': password})
        as Map<String, dynamic>;
    final tk = j['token'] as String;
    // نثبّت التوكن مؤقتاً لقراءة /me
    await Session.set(tk: tk, usr: j['user'] as String?, rl: (j['role'] ?? 'viewer') as String,
        k: AccountKind.regulator);
    final me = await core.get('/api/auth/me') as Map<String, dynamic>;
    final k = kindFrom(me['kind'] as String?);
    if (expected != null && k != expected) {
      await Session.clear();
      throw ApiException(403, _wrongAppMessage(k, expected));
    }
    await Session.set(
      tk: tk,
      usr: me['user'] as String?,
      rl: (me['role'] ?? 'viewer') as String,
      k: k,
      cid: me['company_id'] as int?,
      ag: (me['agent'] as String?) ?? '',
    );
    return k;
  }

  static String _wrongAppMessage(AccountKind actual, AccountKind expected) {
    const names = {
      AccountKind.agent: 'تطبيق الوكلاء',
      AccountKind.company: 'تطبيق الشركات',
      AccountKind.regulator: 'منصّة الوزارة',
      AccountKind.subscriber: 'تطبيق المشتركين',
    };
    return 'هذا الحساب يخصّ ${names[actual]} — استخدم التطبيق المناسب أو حساباً من نوع ${names[expected]}';
  }

  Future<Map<String, dynamic>> me() async => await core.get('/api/auth/me') as Map<String, dynamic>;

  // ─── الملخّص ───

  Future<PortalSummary> summary() async =>
      PortalSummary.fromJson(await core.get('/api/portal/summary') as Map<String, dynamic>);

  // ─── المشتركون ───

  Future<({List<SubscriberRow> rows, int total})> subscribers({
    String? status,
    String? agent,
    String? governorate,
    String? expiring,          // overdue|today|soon3|soon7 — مرشّح «قائمة التجديد»
    String? search,
    int page = 1,
    int count = 50,
  }) async {
    final j = await core.get('/api/companies/subscribers', query: {
      'status': status,
      'agent': agent,
      'governorate': governorate,
      'expiring': expiring,
      'search': search,
      'page': '$page',
      'count': '$count',
    }) as Map<String, dynamic>;
    return (
      rows: ((j['subscribers'] as List?) ?? const [])
          .map((e) => SubscriberRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (j['total'] ?? 0) as int,
    );
  }

  // ─── الوكلاء والبلنك ───

  Future<List<AgentRow>> agents() async {
    final j = await core.get('/api/companies/agents/all') as Map<String, dynamic>;
    return ((j['agents'] as List?) ?? const [])
        .map((e) => AgentRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<({List<ReconRow> rows, Map<String, int> totals})> reconciliation() async {
    final j = await core.get('/api/companies/reconciliation') as Map<String, dynamic>;
    return (
      rows: ((j['rows'] as List?) ?? const [])
          .map((e) => ReconRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      totals: ((j['totals'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', (v as num).toInt())),
    );
  }

  /// تصريح الوكيل بعدد مشتركيه.
  Future<void> submitReport({
    required int companyId,
    required int agentId,
    required int declaredTotal,
    required int declaredActive,
    String note = '',
  }) async {
    await core.post('/api/companies/$companyId/agents/$agentId/report', {
      'declared_total': declaredTotal,
      'declared_active': declaredActive,
      'note': note,
    });
  }

  /// تزويد حساب دخول لوكيل (admin الشركة/الوزارة). يُرجع {username, password, ...}.
  Future<Map<String, dynamic>> provisionAgentAccount(int companyId, int agentId,
      {String? username, String role = 'operator'}) async {
    return await core.post('/api/companies/$companyId/agents/$agentId/account', {
      if (username != null && username.isNotEmpty) 'username': username,
      'role': role,
    }) as Map<String, dynamic>;
  }

  // ─── التذاكر ───

  Future<TicketStats> ticketStats() async =>
      TicketStats.fromJson(await core.get('/api/tickets/stats') as Map<String, dynamic>);

  Future<({List<Ticket> rows, int total})> tickets({
    String? status,
    String? category,
    bool? escalated,
    String? search,
    String? agent,
    int page = 1,
    int count = 50,
  }) async {
    final j = await core.get('/api/tickets', query: {
      'status': status,
      'category': category,
      'escalated': escalated == null ? null : '$escalated',
      'search': search,
      'agent': agent,
      'page': '$page',
      'count': '$count',
    }) as Map<String, dynamic>;
    return (
      rows: ((j['tickets'] as List?) ?? const [])
          .map((e) => Ticket.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (j['total'] ?? 0) as int,
    );
  }

  Future<Ticket> ticket(int id) async =>
      Ticket.fromJson(await core.get('/api/tickets/$id') as Map<String, dynamic>);

  Future<Ticket> createTicket({
    required int subscriberId,
    required String subject,
    String category = 'complaint',
    String body = '',
    String priority = 'normal',
  }) async =>
      Ticket.fromJson(await core.post('/api/tickets', {
        'subscriber_id': subscriberId,
        'subject': subject,
        'category': category,
        'body': body,
        'priority': priority,
      }) as Map<String, dynamic>);

  Future<Ticket> patchTicket(int id,
      {String? status, String? priority, String? assignedTo, bool? escalated}) async =>
      Ticket.fromJson(await core.patch('/api/tickets/$id', {
        if (status != null) 'status': status,
        if (priority != null) 'priority': priority,
        if (assignedTo != null) 'assigned_to': assignedTo,
        if (escalated != null) 'escalated': escalated,
      }) as Map<String, dynamic>);

  Future<void> reply(int id, String body, {bool internal = false}) async {
    await core.post('/api/tickets/$id/reply', {'body': body, 'internal': internal});
  }

  // ─── واجهة SAS الكاملة (بروكسي حيّ عبر الباكند، معزول بالنطاق) ───
  //
  // تعدّد حسابات SAS للوكيل: تمرير [accountId] يوجّه الطلب إلى حساب/خادم بعينه. عند
  // تركه null: القوائم تُدمَج عبر كل حسابات الوكيل (كل صفّ موسوم بـ _account_id)، أمّا
  // العمليات على مشترك بعينه فتتطلّب تحديد الحساب (يُقرأ من وسم الصفّ في الواجهة).

  Map<String, String> _acc(int? accountId, [Map<String, String>? base]) {
    final q = <String, String>{...?base};
    final id = _sid(accountId);
    if (id != null) q['account_id'] = '$id';
    return q;
  }

  Future<Map<String, dynamic>> sasDashboard(int cid, {int? accountId}) async =>
      await core.get('/api/companies/$cid/sas/dashboard', query: _acc(accountId)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> sasFinance(int cid, {int? accountId}) async =>
      await core.get('/api/companies/$cid/sas/finance', query: _acc(accountId)) as Map<String, dynamic>;

  /// قائمة المشتركين الحيّة من SAS {data:[...], total}. الوكيل بلا [accountId] → مدموجة.
  Future<({List<Map<String, dynamic>> rows, int total})> sasUsers(int cid, {
    int page = 1, int count = 50, String search = '',
    String sortBy = 'id', String direction = 'asc', int? accountId,
  }) async {
    final j = await core.get('/api/companies/$cid/sas/users', query: _acc(accountId, {
      'page': '$page', 'count': '$count', 'search': search,
      'sort_by': sortBy, 'direction': direction,
    })) as Map<String, dynamic>;
    return (
      rows: ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>(),
      total: (j['total'] ?? 0) as int,
    );
  }

  Future<Map<String, dynamic>> sasUser(int cid, int uid, {int? accountId}) async =>
      await core.get('/api/companies/$cid/sas/users/$uid', query: _acc(accountId)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> sasUserOverview(int cid, int uid, {int? accountId}) async =>
      await core.get('/api/companies/$cid/sas/users/$uid/overview', query: _acc(accountId)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> sasUserExtendData(int cid, int uid,
      {int? profileId, int? accountId}) async =>
      await core.get('/api/companies/$cid/sas/users/$uid/extend-data',
          query: _acc(accountId, {if (profileId != null) 'profile_id': '$profileId'})) as Map<String, dynamic>;

  /// تنفيذ إجراء SAS على مشترك (تفعيل/تمديد/تغيير باقة/رصيد/ترافيك/إعادة تسمية) —
  /// يُوجَّه إلى حساب المشترك ([accountId]).
  Future<Map<String, dynamic>> sasUserAction(int cid, int uid, String action,
      {Map<String, dynamic> payload = const {}, int? accountId}) async {
    final r = await core.post('/api/companies/$cid/sas/users/$uid/action',
        {'action': action, 'payload': payload, if (_sid(accountId) != null) 'account_id': _sid(accountId)});
    return (r is Map<String, dynamic>) ? r : <String, dynamic>{'result': r};
  }

  Future<({List<Map<String, dynamic>> rows, int total})> sasOnline(int cid, {
    int page = 1, int count = 100, String search = '', int? accountId,
  }) async {
    final j = await core.get('/api/companies/$cid/sas/online', query: _acc(accountId, {
      'page': '$page', 'count': '$count', 'search': search,
    })) as Map<String, dynamic>;
    return (
      rows: ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>(),
      total: (j['total'] ?? 0) as int,
    );
  }

  Future<({List<Map<String, dynamic>> rows, int total})> sasManagers(int cid, {
    int page = 1, int count = 200,
  }) async {
    final j = await core.get('/api/companies/$cid/sas/managers', query: {
      'page': '$page', 'count': '$count',
    }) as Map<String, dynamic>;
    return (
      rows: ((j['data'] as List?) ?? const []).cast<Map<String, dynamic>>(),
      total: (j['total'] ?? 0) as int,
    );
  }

  Future<List<Map<String, dynamic>>> sasProfiles(int cid, {int? accountId}) async {
    final r = await core.get('/api/companies/$cid/sas/profiles', query: _acc(accountId));
    final list = (r is Map<String, dynamic>) ? (r['data'] as List? ?? const []) : (r as List? ?? const []);
    return list.cast<Map<String, dynamic>>();
  }

  // ── حسابات السياق (للفلتر أعلى لوحة SAS) ──

  /// حسابات SAS المتاحة في السياق: الوكيل → كل حساباته؛ الشركة → حساب واحد.
  /// {is_agent, accounts:[{id,label,sas_username,enabled,configured}]}.
  Future<Map<String, dynamic>> sasContextAccounts(int cid) async =>
      await core.get('/api/companies/$cid/sas/accounts') as Map<String, dynamic>;

  // ── إعداد اتصال SAS (تضبطه الشركة نفسها داخل تطبيقها) ──

  /// بيانات الشركة الحالية (تشمل sas_host/sas_username/sas_https/sas_verify_tls/has_password).
  Future<Map<String, dynamic>> companyConfig(int cid) async =>
      await core.get('/api/companies/$cid') as Map<String, dynamic>;

  /// حفظ بيانات اتصال SAS للشركة (كلمة المرور الفارغة = إبقاء المحفوظة).
  Future<Map<String, dynamic>> saveSasConfig(
    int cid, {
    required String host,
    required String username,
    String? password,
    required bool https,
    required bool verifyTls,
  }) async =>
      await core.patch('/api/companies/$cid/sas-config', {
        'sas_host': host,
        'sas_username': username,
        if (password != null) 'sas_password': password,
        'sas_https': https,
        'sas_verify_tls': verifyTls,
      }) as Map<String, dynamic>;

  /// اختبار اتصال SAS ببيانات جديدة (أو المحفوظة إن تُركت فارغة).
  Future<Map<String, dynamic>> testSas(
    int cid, {
    String? host,
    String? username,
    String? password,
    bool? https,
    bool? verifyTls,
  }) async =>
      await core.post('/api/companies/$cid/sas/test', {
        if (host != null) 'sas_host': host,
        if (username != null) 'sas_username': username,
        if (password != null) 'sas_password': password,
        if (https != null) 'sas_https': https,
        if (verifyTls != null) 'sas_verify_tls': verifyTls,
      }) as Map<String, dynamic>;

  // ── إعداد SAS للوكيل (حساب المدير الخاص به؛ الخادم موروث من الشركة) ──

  /// إعداد SAS للوكيل الحالي + عنوان خادم شركته الموروث.
  Future<Map<String, dynamic>> agentSasConfig() async =>
      await core.get('/api/companies/agent/sas-config') as Map<String, dynamic>;

  /// حفظ بيانات اتصال الوكيل: خادمه الخاص + اسم مستخدمه + كلمة مروره (فارغة = إبقاء).
  Future<Map<String, dynamic>> saveAgentSasConfig({
    required String username,
    String? password,
    String? host,
    bool? https,
    bool? verifyTls,
  }) async =>
      await core.patch('/api/companies/agent/sas-config', {
        'sas_username': username,
        if (password != null) 'sas_password': password,
        if (host != null) 'sas_host': host,
        if (https != null) 'sas_https': https,
        if (verifyTls != null) 'sas_verify_tls': verifyTls,
      }) as Map<String, dynamic>;

  /// يسحب الوكيل مشتركيه من **كل حساباته** ويحفظها محلياً الآن — يُعيد {ok, count, accounts}.
  Future<Map<String, dynamic>> syncAgentNow() async =>
      await core.post('/api/companies/agent/sas-sync', const {}) as Map<String, dynamic>;

  // ── حسابات SAS المتعددة للوكيل (يربط عدة حسابات قد تكون على خوادم مختلفة) ──

  /// كل حسابات SAS التابعة للوكيل (مع عدد مشتركي كل حساب وحالة مزامنته).
  Future<List<Map<String, dynamic>>> agentSasAccounts() async {
    final j = await core.get('/api/companies/agent/sas-accounts') as Map<String, dynamic>;
    return ((j['accounts'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// إضافة حساب SAS جديد للوكيل — يُطلق سحباً خلفياً لمشتركيه.
  Future<Map<String, dynamic>> addAgentSasAccount({
    required String label,
    required String host,
    required String username,
    String? password,
    bool https = false,
    bool verifyTls = false,
    bool enabled = true,
  }) async =>
      await core.post('/api/companies/agent/sas-accounts', {
        'label': label,
        'sas_host': host,
        'sas_username': username,
        if (password != null) 'sas_password': password,
        'sas_https': https,
        'sas_verify_tls': verifyTls,
        'enabled': enabled,
      }) as Map<String, dynamic>;

  /// تعديل حساب SAS للوكيل (كلمة المرور الفارغة = إبقاء المحفوظة).
  Future<Map<String, dynamic>> updateAgentSasAccount(int id, {
    String? label,
    String? host,
    String? username,
    String? password,
    bool? https,
    bool? verifyTls,
    bool? enabled,
  }) async =>
      await core.patch('/api/companies/agent/sas-accounts/$id', {
        if (label != null) 'label': label,
        if (host != null) 'sas_host': host,
        if (username != null) 'sas_username': username,
        if (password != null && password.isNotEmpty) 'sas_password': password,
        if (https != null) 'sas_https': https,
        if (verifyTls != null) 'sas_verify_tls': verifyTls,
        if (enabled != null) 'enabled': enabled,
      }) as Map<String, dynamic>;

  Future<void> deleteAgentSasAccount(int id) async {
    await core.delete('/api/companies/agent/sas-accounts/$id');
  }

  /// اختبار اتصال حساب SAS للوكيل (المحفوظ أو ببيانات جديدة).
  Future<Map<String, dynamic>> testAgentSasAccount(int id, {
    String? host, String? username, String? password, bool? https, bool? verifyTls,
  }) async =>
      await core.post('/api/companies/agent/sas-accounts/$id/test', {
        if (host != null) 'sas_host': host,
        if (username != null) 'sas_username': username,
        if (password != null) 'sas_password': password,
        if (https != null) 'sas_https': https,
        if (verifyTls != null) 'sas_verify_tls': verifyTls,
      }) as Map<String, dynamic>;

  /// مزامنة مشتركي حساب SAS واحد الآن — يُعيد {ok, count}.
  Future<Map<String, dynamic>> syncAgentSasAccount(int id) async =>
      await core.post('/api/companies/agent/sas-accounts/$id/sync', const {}) as Map<String, dynamic>;

  /// عملية جماعية على عدة مشتركين على **حساب واحد** ([accountId]) — لكل مشترك
  /// transaction_id فريد. يُعيد {total, ok, failed, results:[{user_id, ok, error?}]}.
  Future<Map<String, dynamic>> sasBulkAction(int cid, String action, List<int> userIds,
          {Map<String, dynamic> payload = const {}, int? accountId}) async =>
      await core.post('/api/companies/$cid/sas/users/bulk-action', {
        'action': action,
        'user_ids': userIds,
        'payload': payload,
        if (_sid(accountId) != null) 'account_id': _sid(accountId),
      }) as Map<String, dynamic>;

  /// تعديل مشترك (تحميل-دمج-حفظ) — يُوجَّه إلى حساب المشترك ([accountId]). أمثلة changes:
  /// `{'enabled':0}` تعطيل · `{'password':'new'}` كلمة مرور · `{'phone':'…','firstname':'…'}`
  /// تعديل بيانات · `{'mac_auth':1,'allowed_macs':'AA:BB,CC:DD'}` إدارة MAC.
  Future<dynamic> sasUpdateUser(int cid, int uid, Map<String, dynamic> changes,
          {int? accountId}) async =>
      await core.post('/api/companies/$cid/sas/users/$uid/update',
          {'changes': changes, if (_sid(accountId) != null) 'account_id': _sid(accountId)});

  // ── إدارة حسابات الوكلاء (الأدمن ينشئها مباشرةً) ──

  /// إنشاء حساب دخول لوكيل (اسم مستخدم + كلمة مرور + معلوماته + مزوّده).
  Future<Map<String, dynamic>> createAgentAccount({
    required String username,
    required String password,
    String displayName = '',
    String phone = '',
    String provider = '',
    String role = 'operator',
  }) async =>
      await core.post('/api/companies/agent-accounts', {
        'username': username,
        'password': password,
        'display_name': displayName,
        'phone': phone,
        'provider': provider,
        'role': role,
      }) as Map<String, dynamic>;

  /// قائمة حسابات الوكلاء (مع حالة ضبط SAS لكلٍّ).
  Future<List<Map<String, dynamic>>> listAgentAccounts() async {
    final j = await core.get('/api/companies/agent-accounts') as Map<String, dynamic>;
    return ((j['accounts'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  Future<void> deleteAgentAccount(int id) async {
    await core.delete('/api/companies/agent-accounts/$id');
  }

  // ── لوحة SAS الكاملة: بروكسي عامّ + إجراءات كتابة/حذف ──

  /// قراءة تفاصيل SAS عبر البروكسي المُقيَّد (تفاصيل مشترك/تفعيل/استرداد/MAC/شجرة/
  /// مالية/صحّة النظام/ترخيص…). مثال: `sasGet(cid, 'user/123')`.
  Future<dynamic> sasGet(int cid, String path, {int? accountId}) async =>
      await core.get('/api/companies/$cid/sas/get', query: _acc(accountId, {'path': path}));

  /// قوائم بترقيم عبر البروكسي (سجلّ/قيود/ترافيك). مثال: `index/UserHistory/123`.
  Future<dynamic> sasPostList(int cid, String path,
          [Map<String, dynamic> payload = const {}, int? accountId]) async =>
      await core.post('/api/companies/$cid/sas/post',
          {'path': path, 'payload': payload, if (_sid(accountId) != null) 'account_id': _sid(accountId)});

  ({List<Map<String, dynamic>> rows, int total}) _rowsTotal(dynamic r) {
    if (r is Map) {
      final data = r['data'];
      final rows = (data is List) ? data.whereType<Map<String, dynamic>>().toList()
                                  : <Map<String, dynamic>>[];
      return (rows: rows, total: (r['total'] as num?)?.toInt() ?? rows.length);
    }
    if (r is List) return (rows: r.whereType<Map<String, dynamic>>().toList(), total: r.length);
    return (rows: const [], total: 0);
  }

  /// سجلّ تسجيل الدخول/المصادقة (index/userauthlog): username, reply, created_at, mac, nas_ip_address.
  Future<({List<Map<String, dynamic>> rows, int total})> sasAuthLog(int cid,
      {int page = 1, int count = 100, String search = ''}) async {
    final r = await sasPostList(cid, 'index/userauthlog',
        {'page': page, 'count': count, 'sortBy': 'id', 'direction': 'desc', 'search': search});
    return _rowsTotal(r);
  }

  /// سجلّ النظام (index/syslog): event, description, created_by, ip, created_at.
  Future<({List<Map<String, dynamic>> rows, int total})> sasSyslog(int cid,
      {int page = 1, int count = 100, String search = ''}) async {
    final r = await sasPostList(cid, 'index/syslog',
        {'page': page, 'count': count, 'sortBy': 'id', 'direction': 'desc', 'search': search});
    return _rowsTotal(r);
  }

  /// تنفيذ إجراء على مشترك (activate/extend/changeProfile/addTraffic/deposit/withdraw/
  /// ping/rename/create) — يُوجَّه إلى حساب المشترك ([accountId]).
  Future<dynamic> sasUserActionFull(int cid, int uid, String action,
          [Map<String, dynamic> payload = const {}, int? accountId]) async =>
      await core.post('/api/companies/$cid/sas/users/$uid/action',
          {'action': action, 'payload': payload, if (_sid(accountId) != null) 'account_id': _sid(accountId)});

  Future<dynamic> sasDeleteUser(int cid, int uid, {int? accountId}) async =>
      await core.delete('/api/companies/$cid/sas/users/$uid'
          '${_sid(accountId) != null ? '?account_id=${_sid(accountId)}' : ''}');

  /// إجراء على وكيل (deposit/withdraw/addRewardPoints/deductRewardPoints/payDebt/add/edit) — للشركة.
  Future<dynamic> sasManagerAction(int cid, int mid, String action,
          [Map<String, dynamic> payload = const {}]) async =>
      await core.post('/api/companies/$cid/sas/managers/$mid/action',
          {'action': action, 'payload': payload});

  Future<dynamic> sasDeleteManager(int cid, int mid) async =>
      await core.delete('/api/companies/$cid/sas/managers/$mid');

  // ── إنشاء مشترك (نقطة صريحة، بحمولة كاملة، بلا حقن user_id) ──

  /// إنشاء مشترك جديد في SAS تحت الحساب المحدَّد ([accountId]). للوكيل: يُسنده SAS
  /// لحسابه المُصادَق تلقائياً.
  Future<dynamic> sasCreateUser(int cid, Map<String, dynamic> payload, {int? accountId}) async =>
      await core.post('/api/companies/$cid/sas/users',
          {'payload': payload, if (_sid(accountId) != null) 'account_id': _sid(accountId)});

  // ── الإلغاء/الاسترداد ──

  /// بيانات الاسترداد قبل التنفيذ (refund_amount/price/remaining_days).
  Future<Map<String, dynamic>> sasRefundData(int cid, int uid, {int? accountId}) async {
    final r = await core.get('/api/companies/$cid/sas/users/$uid/refund-data',
        query: _acc(accountId));
    return (r is Map<String, dynamic>) ? r : <String, dynamic>{'value': r};
  }

  /// تنفيذ الإلغاء والاسترداد (إجراء مالي — operator).
  Future<dynamic> sasRefund(int cid, int uid, {int? accountId}) async =>
      await core.post('/api/companies/$cid/sas/users/$uid/refund',
          {if (_sid(accountId) != null) 'account_id': _sid(accountId)});

  // ── إضافة/تعديل وكيل (عبر إجراء الوكلاء) ──

  Future<dynamic> sasManagerAdd(int cid, Map<String, dynamic> payload) async =>
      await sasManagerAction(cid, 0, 'add', payload);

  Future<dynamic> sasManagerEdit(int cid, int mid, Map<String, dynamic> payload) async =>
      await sasManagerAction(cid, mid, 'edit', payload);

  // ── بيانات إضافية للعرض (عبر البروكسي المُقيَّد) ──

  /// معلومات التوكن/الرخصة/الصلاحيات (GET auth).
  Future<dynamic> sasAuthInfo(int cid) async => await sasGet(cid, 'auth');

  /// مواقع/فروع الشركة (GET site).
  Future<dynamic> sasSite(int cid) async => await sasGet(cid, 'site');

  /// عناوين MAC المسجّلة لمشترك (GET mac/{id}) — من حساب المشترك ([accountId]).
  Future<dynamic> sasMac(int cid, int uid, {int? accountId}) async =>
      await sasGet(cid, 'mac/$uid', accountId: accountId);

  /// سمات Radius المخصّصة لمشترك (GET customRadiusAttribute/user/{id}).
  Future<dynamic> sasCustomRadius(int cid, int uid, {int? accountId}) async =>
      await sasGet(cid, 'customRadiusAttribute/user/$uid', accountId: accountId);

  /// اللغات/الترجمات المتاحة (GET resources/languages).
  Future<dynamic> sasLanguages(int cid) async => await sasGet(cid, 'resources/languages');

  /// ترافيك المشترك على الشبكات (POST userNetworksTraffic).
  Future<dynamic> sasNetworksTraffic(int cid, int uid, {int? accountId}) async =>
      await sasPostList(cid, 'userNetworksTraffic', {'user_id': uid}, accountId);
}
