import 'dart:async';

import '../services/sas_agent_api_service.dart';

/// حدث تحديث مبثوث على [SasRefreshBus].
///
/// [accountId] الحساب المعني (null = كل الحسابات/تحديث عام)، و[reason] سبب
/// وصفي للتسجيل/التمييز (مثل `billed-action` · `payment` · `tab-enter` · `button`).
class SasRefreshEvent {
  /// معرّف حساب الساس المعني بالتحديث؛ null يعني «يخصّ أيّ حساب».
  final String? accountId;

  /// سبب وصفي قصير (للتشخيص فقط — لا يؤثّر على المنطق).
  final String reason;

  const SasRefreshEvent({this.accountId, required this.reason});

  /// هل يعني هذا الحدث التبويبَ المهتمَّ بالحساب [forAccountId]؟
  /// حدث بلا حساب (`accountId == null`) يخصّ الجميع.
  bool matches(String? forAccountId) =>
      accountId == null || forAccountId == null || accountId == forAccountId;
}

/// ناقل تحديث مشترك خفيف لوحدة «وكيل الساس».
///
/// بثّ أحادي الاتجاه (broadcast) بلا تبعيات: أي موضع ينفّذ عملية مفوترة أو
/// مزامنة ينادي [notify]؛ وكل تبويب بيانات مفتوح يشترك عبر [stream] فيعيد تحميل
/// بياناته موضعياً (بلا وميض). الاشتراكات تُلغى في `dispose` لمنع التسريب.
///
/// ⚠️ لا يُجري أي مزامنة بنفسه — المزامنة (سحب SAS4→محلي) مسؤولية المستدعي عبر
/// [syncAndNotify]؛ هذا الناقل مجرّد وسيط إشعارات.
class SasRefreshBus {
  SasRefreshBus._();
  static final SasRefreshBus instance = SasRefreshBus._();

  final StreamController<SasRefreshEvent> _controller =
      StreamController<SasRefreshEvent>.broadcast();

  /// تيّار الأحداث — يشترك فيه كل تبويب بيانات ويعيد التحميل عند كل حدث يعنيه.
  Stream<SasRefreshEvent> get stream => _controller.stream;

  /// يبثّ حدث تحديث لكل المشتركين. [accountId] الحساب المعني (null = عام)،
  /// و[reason] سبب وصفي قصير للتشخيص.
  void notify({String? accountId, String reason = 'manual'}) {
    if (_controller.isClosed) return;
    _controller.add(SasRefreshEvent(accountId: accountId, reason: reason));
  }

  /// مزامنة الحساب (سحب SAS4→محلي) ثم بثّ إشعار تحديث لكل التبويبات.
  ///
  /// تُستخدم بعد كل عملية مفوترة/تسديد وعند دخول التبويب وزر التحديث. فشل
  /// المزامنة **لا يُسقط** العملية الأصلية: يُلتقط ويُتجاهل، ويُبثّ الإشعار دائماً
  /// حتى تعيد التبويبات القراءة من أحدث حالة محلية متاحة.
  ///
  /// [api] يُمرَّر للاختبار؛ وإلا يُستخدم المفرد الافتراضي.
  Future<void> syncAndNotify(
    String accountId, {
    required String reason,
    SasAgentApiService? api,
  }) async {
    final service = api ?? SasAgentApiService.instance;
    try {
      await service.syncAccount(accountId);
    } catch (_) {
      // فشل المزامنة معزول — نُبقي الإشعار لإعادة تحميل الحالة المحلية الحالية.
    }
    notify(accountId: accountId, reason: reason);
  }
}
