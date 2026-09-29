import '../models/subscriber_row.dart';
import '../models/ticket.dart';
import '../session.dart';
import 'api_core.dart';

/// عميل تطبيق المشتركين — دخول OTP واتساب + الحسابات + التذاكر.
class SubscriberApi {
  final ApiCore core;
  SubscriberApi({ApiCore? core}) : core = core ?? ApiCore();

  /// طلب رمز. يُرجع (masked, devCode) — devCode يظهر فقط بوضع تطوير الباكند.
  Future<({String masked, String? devCode, int expiresIn})> requestOtp(String phone) async {
    final j = await core.post('/api/subscriber/otp/request', {'phone': phone}) as Map<String, dynamic>;
    return (
      masked: (j['masked'] ?? '') as String,
      devCode: j['dev_code'] as String?,
      expiresIn: (j['expires_in'] ?? 300) as int,
    );
  }

  /// التحقّق وتثبيت الجلسة.
  Future<int> verifyOtp(String phone, String code) async {
    final j = await core.post('/api/subscriber/otp/verify', {'phone': phone, 'code': code})
        as Map<String, dynamic>;
    await Session.set(
      tk: j['token'] as String,
      usr: j['phone'] as String?,
      rl: 'subscriber',
      k: AccountKind.subscriber,
    );
    return (j['accounts'] ?? 0) as int;
  }

  Future<({String phone, String masked, List<SubscriberRow> accounts})> me() async {
    final j = await core.get('/api/subscriber/me') as Map<String, dynamic>;
    return (
      phone: (j['phone'] ?? '') as String,
      masked: (j['masked'] ?? '') as String,
      accounts: ((j['accounts'] as List?) ?? const [])
          .map((e) => SubscriberRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<Ticket>> tickets({String? status}) async {
    final j = await core.get('/api/subscriber/tickets', query: {'status': status}) as Map<String, dynamic>;
    return ((j['tickets'] as List?) ?? const [])
        .map((e) => Ticket.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Ticket> ticket(int id) async =>
      Ticket.fromJson(await core.get('/api/subscriber/tickets/$id') as Map<String, dynamic>);

  Future<Ticket> createTicket({
    required int accountId,
    required String subject,
    String category = 'complaint',
    String body = '',
  }) async =>
      Ticket.fromJson(await core.post('/api/subscriber/tickets', {
        'account_id': accountId,
        'subject': subject,
        'category': category,
        'body': body,
      }) as Map<String, dynamic>);

  Future<void> reply(int id, String body) async {
    await core.post('/api/subscriber/tickets/$id/reply', {'body': body});
  }

  // ─── بوابة المشترك عبر SAS (/api/subscriber/sas/*) ───

  /// حالة ربط حساب SAS للمشترك.
  Future<({bool linked, String sasUsername})> sasLinkStatus(int accountId) async {
    final j = await core.get('/api/subscriber/sas/link/$accountId') as Map<String, dynamic>;
    return (linked: (j['linked'] ?? false) as bool, sasUsername: (j['sas_username'] ?? '') as String);
  }

  /// ربط اعتماد بوابة SAS (يُختبر الدخول قبل الحفظ).
  Future<bool> sasLink(int accountId, String sasUsername, String sasPassword) async {
    final j = await core.post('/api/subscriber/sas/link', {
      'account_id': accountId,
      'sas_username': sasUsername,
      'sas_password': sasPassword,
    }) as Map<String, dynamic>;
    return (j['linked'] ?? false) as bool;
  }

  Future<void> sasUnlink(int accountId) async {
    await core.delete('/api/subscriber/sas/link/$accountId');
  }

  // العرض (يعمل مربوطاً عبر البوابة أو غير مربوط عبر واجهة الإدارة)
  Future<dynamic> sasBalance(int accountId) async =>
      await core.get('/api/subscriber/sas/$accountId/balance');

  Future<dynamic> sasInvoices(int accountId, {int page = 1}) async =>
      await core.get('/api/subscriber/sas/$accountId/invoices', query: {'page': '$page'});

  Future<dynamic> sasSessions(int accountId) async =>
      await core.get('/api/subscriber/sas/$accountId/sessions');

  Future<dynamic> sasTraffic(int accountId, {int? month, int? year}) async =>
      await core.get('/api/subscriber/sas/$accountId/traffic',
          query: {if (month != null) 'month': '$month', if (year != null) 'year': '$year'});

  Future<dynamic> sasPackages(int accountId) async =>
      await core.get('/api/subscriber/sas/$accountId/packages');

  // عمليات كتابية (تتطلّب ربطاً) — txId يمنع التكرار
  Future<dynamic> sasChangePassword(int accountId, String newPassword,
          {String? currentPassword, String? txId}) async =>
      await core.post('/api/subscriber/sas/$accountId/change-password', {
        'new_password': newPassword,
        if (currentPassword != null) 'current_password': currentPassword,
        if (txId != null) 'transaction_id': txId,
      });

  Future<dynamic> sasRedeem(int accountId, String pin, {required String txId}) async =>
      await core.post('/api/subscriber/sas/$accountId/redeem',
          {'pin': pin, 'transaction_id': txId});

  Future<dynamic> sasChangeSubscription(int accountId, Object newService,
          {String? currentPassword, required String txId}) async =>
      await core.post('/api/subscriber/sas/$accountId/change-subscription', {
        'new_service': newService,
        if (currentPassword != null) 'current_password': currentPassword,
        'transaction_id': txId,
      });

  Future<dynamic> sasExtend(int accountId, Object profileId,
          {String? currentPassword, required String txId}) async =>
      await core.post('/api/subscriber/sas/$accountId/extend', {
        'profile_id': profileId,
        if (currentPassword != null) 'current_password': currentPassword,
        'transaction_id': txId,
      });

  Future<dynamic> sasActivate(int accountId, {required String uuid, String? currentPassword}) async =>
      await core.post('/api/subscriber/sas/$accountId/activate', {
        'uuid': uuid,
        if (currentPassword != null) 'current_password': currentPassword,
      });
}
