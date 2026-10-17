import 'dart:async';

import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_account.dart';
import '../models/sas_report.dart';
import '../models/sas_subscriber.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_report_widgets.dart';
import '../widgets/sas_state_views.dart';
import 'sas_bulk_import_page.dart';
import 'sas_subscriber_detail_page.dart';
import 'sas_subscriber_form_page.dart';

/// مصدر عرض المشتركين: مباشر من نظام الساس، أو محلي سريع (بعد المزامنة).
enum _Source { live, local }

/// تبويب «مشتركون» — يدعم مصدرين: «مباشر من الساس» (بطيء، حيّ) و«محلي سريع»
/// (من قاعدة الصدارة بعد المزامنة) مع شرائح عدّادات انتهاء قابلة للنقر للفلترة.
class SasSubscribersTab extends StatefulWidget {
  final SasAccount account;

  /// فلتر انتهاء ابتدائي (overdue/today/soon3/soon7) — يُمرَّر عند القدوم من
  /// بطاقات «قرب الانتهاء» في تبويب «لوحة». يفتح المصدر المحلي مباشرةً مفلترًا.
  final String? initialExpiring;

  const SasSubscribersTab({
    super.key,
    required this.account,
    this.initialExpiring,
  });

  @override
  State<SasSubscribersTab> createState() => _SasSubscribersTabState();
}

class _SasSubscribersTabState extends State<SasSubscribersTab> {
  final _api = SasAgentApiService.instance;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // «محلي أولاً»: نبدأ دائماً من اللقطة المحلية (عرض فوري بلا تأخير)، ثم نزامن بصمت.
  _Source _source = _Source.local;

  /// فلتر عدّاد الانتهاء الفعّال (للمصدر المحلي): overdue/today/soon3/soon7.
  String? _expiring;

  List<SasSubscriber> _rows = [];
  SasExpiryCounts _expiryCounts = const SasExpiryCounts();
  int _localTotal = 0;

  bool _loading = true;
  bool _syncing = false;

  /// تحديث خلفي جارٍ (مزامنة صامتة لا تحجب العرض).
  bool _refreshing = false;
  String? _error;

  /// آخر مزامنة خلفية تلقائية لكل حساب (لمنع التكرار عند التنقّل السريع بين التبويبات).
  static final Map<String, DateTime> _lastAutoSync = {};

  /// أدنى فاصل بين مزامنتين خلفيّتين تلقائيّتين عند الفتح (الخدمة الخلفية تتكفّل بالدوري).
  static const Duration _autoSyncThrottle = Duration(minutes: 2);

  /// اشتراك ناقل التحديث المشترك — يعيد التحميل عند أي عملية/مزامنة.
  StreamSubscription<SasRefreshEvent>? _busSub;

  @override
  void initState() {
    super.initState();
    // إن قدِمنا من بطاقة «قرب الانتهاء» في اللوحة: افتح المصدر المحلي مفلترًا.
    if (widget.initialExpiring != null && widget.initialExpiring!.isNotEmpty) {
      _source = _Source.local;
      _expiring = widget.initialExpiring;
    }
    // محلي أولاً: اعرض اللقطة فوراً ثم زامن بصمت من SAS4 (تحديث خلفي عند الفتح).
    _load().then((_) => _maybeAutoRefresh());
    _busSub = SasRefreshBus.instance.stream.listen(_onBusEvent);
  }

  /// مزامنة خلفية صامتة عند فتح القائمة (محلي فقط) — بلا حجب العرض، مع كبح التكرار.
  /// الفشل صامت (تبقى اللقطة المحلية معروضة)؛ الخدمة الخلفية في الخادم تتكفّل بالدوري.
  Future<void> _maybeAutoRefresh() async {
    if (!mounted || _source != _Source.local || _syncing || _refreshing) return;
    final last = _lastAutoSync[widget.account.id];
    if (last != null && DateTime.now().difference(last) < _autoSyncThrottle) {
      return; // زامنّا حديثاً — لا داعي
    }
    setState(() => _refreshing = true);
    try {
      final r = await _api.syncAccount(widget.account.id);
      _lastAutoSync[widget.account.id] = DateTime.now();
      if (!mounted) return;
      _expiryCounts = r.expiry;
      await _load(silent: true); // أعد الجلب دون وميض تحميل
    } catch (_) {
      // صامت: اللقطة المحلية تبقى معروضة
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// عند إشعار الناقل الخاص بهذا الحساب: أعد تحميل القائمة الحالية موضعياً (بلا
  /// مزامنة ثقيلة — تمّت عند مصدر الحدث). نتجنّب التحميل أثناء مزامنة سريعة جارية.
  void _onBusEvent(SasRefreshEvent e) {
    if (!mounted || _syncing) return;
    if (!e.matches(widget.account.id)) return;
    _load();
  }

  @override
  void didUpdateWidget(covariant SasSubscribersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) {
      _searchCtrl.clear();
      _expiring = widget.initialExpiring;
      _source = (widget.initialExpiring != null &&
              widget.initialExpiring!.isNotEmpty)
          ? _Source.local
          : _Source.live;
      _load();
    } else if (oldWidget.initialExpiring != widget.initialExpiring &&
        widget.initialExpiring != null &&
        widget.initialExpiring!.isNotEmpty) {
      // تغيّر الفلتر المطلوب من اللوحة لنفس الحساب — طبّقه فورًا.
      _expiring = widget.initialExpiring;
      _source = _Source.local;
      _load();
    }
  }

  @override
  void dispose() {
    _busSub?.cancel();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    final search =
        _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim();
    try {
      if (_source == _Source.local) {
        final page = await _api.getLocalSubscribers(
          widget.account.id,
          search: search,
          expiring: _expiring,
          count: 100,
        );
        if (!mounted) return;
        setState(() {
          _rows = page.subscribers.map(SasSubscriber.fromJson).toList();
          _expiryCounts = page.expiry;
          _localTotal = page.total;
        });
      } else {
        final rows = await _api.getSubscribers(
          widget.account.id,
          search: search,
          pageSize: 100,
        );
        if (!mounted) return;
        setState(() => _rows = rows);
      }
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _load);
  }

  void _onExpiringSelected(String? key) {
    setState(() => _expiring = key);
    _load();
  }

  /// مزامنة سريعة ثم تبديل إلى المصدر المحلي لعرض النتيجة فوراً.
  Future<void> _quickSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final r = await _api.syncAccount(widget.account.id);
      if (!mounted) return;
      _snack('تمت مزامنة ${r.count} مشترك');
      setState(() {
        _source = _Source.local;
        _expiryCounts = r.expiry;
      });
      await _load();
      // أبلغ بقية التبويبات المفتوحة لتتحدّث (نبثّ و_syncing لا يزال true فيتخطّى
      // مستمعنا الذاتي إعادةً مكرّرة؛ قائمتنا مُحمَّلة أصلاً أعلاه).
      SasRefreshBus.instance.notify(
          accountId: widget.account.id, reason: 'subscribers-sync-button');
    } catch (e) {
      _snack(_clean(e), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontFamily: SdText.family, fontWeight: FontWeight.w600)),
      backgroundColor: error ? SdColors.danger : SdColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _openDetail(SasSubscriber s) async {
    if (s.id.isEmpty) {
      _snack('تعذّر فتح المشترك: معرّف غير متاح', error: true);
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SasSubscriberDetailPage(
          account: widget.account,
          userId: s.id,
          username: s.username,
        ),
      ),
    );
    if (changed == true && mounted) _load();
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SasSubscriberFormPage(account: widget.account),
      ),
    );
    if (created == true && mounted) _load();
  }

  /// فتح شاشة «رفع مجموعة مشتركين» (استيراد ملف / إدخال متعدّد ثم إنشاء دفعة).
  Future<void> _openBulkImport() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SasBulkImportPage(account: widget.account),
      ),
    );
    // أعد التحميل بعد العودة (قد يكون أُنشئ مشتركون؛ ناقل التحديث يبثّ أيضاً).
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return SasContentWrap(
      maxWidth: 1100,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Row(
              children: [
                Expanded(child: _searchBox()),
                const SizedBox(width: 10),
                _quickSyncButton(),
                const SizedBox(width: 8),
                SizedBox(
                  height: 50,
                  child: SdButton(
                    label: 'رفع مجموعة',
                    icon: Icons.upload_file_rounded,
                    kind: SdButtonKind.secondary,
                    height: 50,
                    onPressed: _openBulkImport,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 50,
                  child: SdButton(
                    label: 'إنشاء',
                    icon: Icons.person_add_rounded,
                    height: 50,
                    onPressed: _openCreate,
                  ),
                ),
              ],
            ),
          ),
          // قائمة موحّدة (محلي أولاً + تحديث خلفي) — بلا مُبدّل مصدر.
          // شرائح فلتر الانتهاء تبقى (كلها على المصدر المحلي).
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: SasExpiryChips(
              counts: _expiryCounts,
              selected: _expiring,
              onSelect: _onExpiringSelected,
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _searchBox() {
    OutlineInputBorder border(Color color, [double width = 1.2]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.md),
          borderSide: BorderSide(color: color, width: width),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _load(),
        style: const TextStyle(
            fontFamily: SdText.family,
            fontWeight: FontWeight.w600,
            color: SdColors.ink),
        decoration: InputDecoration(
          hintText: 'بحث عن مشترك…',
          hintStyle: const TextStyle(
              fontFamily: SdText.family, color: SdColors.faint),
          filled: true,
          fillColor: SdColors.surface,
          prefixIcon:
              const Icon(Icons.search_rounded, color: SdColors.primary),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear_rounded, color: SdColors.faint),
                  onPressed: () {
                    _searchCtrl.clear();
                    _load();
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SdRadius.md),
            borderSide: BorderSide.none,
          ),
          enabledBorder: border(SdColors.edge),
          focusedBorder: border(SdColors.primary, 1.6),
        ),
      ),
    );
  }

  Widget _quickSyncButton() {
    if (_syncing) {
      return const SizedBox(
        height: 50,
        width: 50,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: SdColors.info),
          ),
        ),
      );
    }
    return SizedBox(
      height: 50,
      child: SdButton(
        label: 'مزامنة',
        icon: Icons.sync_rounded,
        kind: SdButtonKind.accent,
        height: 50,
        onPressed: _quickSync,
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SasLoadingView(message: 'جاري جلب المشتركين…');
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return SdEmptyState(
        title: 'لا مشتركون بعد',
        message: 'اضغط «تحديث» لجلبهم من الساس',
        icon: Icons.people_outline_rounded,
        action: SdButton(
          label: 'تحديث الآن',
          icon: Icons.sync_rounded,
          kind: SdButtonKind.secondary,
          onPressed: _syncing ? null : _quickSync,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          if (_source == _Source.local)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _expiring == null
                          ? 'إجمالي محلي: $_localTotal · معروض: ${_rows.length}'
                          : 'مُفلتَر (${_rows.length}) من إجمالي محلي $_localTotal',
                      style: SdText.caption,
                    ),
                  ),
                  if (_refreshing)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: SdColors.info),
                        ),
                        const SizedBox(width: 6),
                        Text('يُحدّث من الساس…',
                            style: SdText.caption
                                .copyWith(color: SdColors.info)),
                      ],
                    ),
                ],
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: SdSpace.xs),
              itemBuilder: (_, i) => _subscriberCard(_rows[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscriberCard(SasSubscriber s) {
    final tone = s.isActive ? SdStatus.success.tone : SdStatus.danger.tone;
    return SdRaised(
      onTap: () => _openDetail(s),
      radius: SdRadius.lg,
      padding: const EdgeInsets.all(12),
      semanticLabel: s.username.isEmpty ? '-' : s.username,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tone.tint,
                      shape: BoxShape.circle,
                      border: Border.all(color: tone.tintEdge),
                    ),
                    child: Icon(Icons.person_rounded,
                        color: tone.base, size: 21),
                  ),
                  if (s.online)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: SdColors.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اسم المستخدم (المعرّف) + الاسم الكامل بارزاً تحته.
                    Text(
                      s.username.isEmpty ? '-' : s.username,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: SdColors.ink),
                    ),
                    if (s.fullName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        s.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SdText.bodySm.copyWith(
                            color: const Color(0xFF475569),
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SdStatusChip(
                s.isActive ? 'نشط' : 'موقوف',
                status: s.isActive ? SdStatus.success : SdStatus.danger,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // حقول المشترك كشرائح واضحة (باقة · انتهاء · هاتف · اتصال).
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _infoChip(
                  Icons.inventory_2_rounded, s.profileLabel, SdStatus.info),
              if (s.expiration != null && s.expiration!.trim().isNotEmpty)
                _infoChip(Icons.event_busy_rounded, s.expiration!,
                    SdStatus.warning),
              if (_phoneOf(s).isNotEmpty)
                _infoChip(Icons.phone_rounded, _phoneOf(s), SdStatus.success,
                    ltr: true),
              if (s.online)
                _infoChip(Icons.wifi_rounded, 'متصل', SdStatus.success),
            ],
          ),
        ],
      ),
    );
  }

  /// رقم هاتف المشترك من الحقول الخام (إن توفّر).
  String _phoneOf(SasSubscriber s) =>
      (s.raw['phone'] ?? s.raw['phone_norm'] ?? s.raw['mobile'] ?? '')
          .toString()
          .trim();

  /// شريحة حقل صغيرة (أيقونة + نص) بلون موحّد.
  Widget _infoChip(IconData icon, String text, SdStatus status,
      {bool ltr = false}) {
    final tone = status.tone;
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontFamily: SdText.family,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: tone.text),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        border: Border.all(color: tone.tintEdge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: tone.text),
          const SizedBox(width: 4),
          ltr
              ? Directionality(textDirection: TextDirection.ltr, child: label)
              : label,
        ],
      ),
    );
  }
}
