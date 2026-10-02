import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_report.dart';
import '../models/sas_subscriber.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_report_widgets.dart';
import '../widgets/sas_state_views.dart';
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

  _Source _source = _Source.live;

  /// فلتر عدّاد الانتهاء الفعّال (للمصدر المحلي): overdue/today/soon3/soon7.
  String? _expiring;

  List<SasSubscriber> _rows = [];
  SasExpiryCounts _expiryCounts = const SasExpiryCounts();
  int _localTotal = 0;

  bool _loading = true;
  bool _syncing = false;
  String? _error;

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
    _load();
    _busSub = SasRefreshBus.instance.stream.listen(_onBusEvent);
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
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

  void _switchSource(_Source s) {
    if (_source == s) return;
    setState(() {
      _source = s;
      if (s == _Source.live) _expiring = null; // الفلتر خاص بالمحلي.
    });
    _load();
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
      SasRefreshBus.instance
          .notify(accountId: widget.account.id, reason: 'subscribers-sync-button');
    } catch (e) {
      _snack(_clean(e), error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 4.h),
          child: Row(
            children: [
              Expanded(child: _searchBox()),
              SizedBox(width: 10.w),
              _quickSyncButton(),
              SizedBox(width: 8.w),
              SizedBox(
                height: 50.h,
                child: FilledButton.icon(
                  onPressed: _openCreate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SasUi.radius.r)),
                  ),
                  icon: const Icon(Icons.person_add_rounded, size: 19),
                  label: Text('إنشاء',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(14.w, 8.h, 14.w, 6.h),
          child: _sourceToggle(),
        ),
        if (_source == _Source.local) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(14.w, 2.h, 14.w, 6.h),
            child: SasExpiryChips(
              counts: _expiryCounts,
              selected: _expiring,
              onSelect: _onExpiringSelected,
            ),
          ),
        ],
        Expanded(child: _body()),
      ],
    );
  }

  Widget _searchBox() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        boxShadow: SasUi.cardShadow(),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _load(),
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'بحث عن مشترك…',
          hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
          filled: true,
          fillColor: Colors.white,
          prefixIcon:
              Icon(Icons.search_rounded, color: AppTheme.primaryColor),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.clear_rounded, color: Colors.grey[500]),
                  onPressed: () {
                    _searchCtrl.clear();
                    _load();
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radius.r),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radius.r),
            borderSide:
                BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radius.r),
            borderSide:
                const BorderSide(color: AppTheme.primaryColor, width: 1.6),
          ),
        ),
      ),
    );
  }

  Widget _quickSyncButton() {
    return SizedBox(
      height: 50.h,
      child: OutlinedButton.icon(
        onPressed: _syncing ? null : _quickSync,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.infoColor,
          side: BorderSide(color: AppTheme.infoColor.withValues(alpha: 0.45)),
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SasUi.radius.r)),
        ),
        icon: _syncing
            ? SizedBox(
                width: 16.w,
                height: 16.w,
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.infoColor),
              )
            : Icon(Icons.sync_rounded, size: 18.sp),
        label: Text('مزامنة',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w800, fontSize: 12.5)),
      ),
    );
  }

  /// مبدّل مصدر العرض (مباشر/محلي) بنمط segmented أنيق.
  Widget _sourceToggle() {
    Widget seg(String label, IconData icon, _Source s) {
      final sel = _source == s;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
            onTap: () => _switchSource(s),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 9.h),
              decoration: BoxDecoration(
                gradient: sel
                    ? const LinearGradient(
                        colors: AppTheme.blueGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      size: 16.sp,
                      color: sel ? Colors.white : Colors.grey[600]),
                  SizedBox(width: 6.w),
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                      color: sel ? Colors.white : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        boxShadow: SasUi.cardShadow(),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          seg('مباشر من الساس', Icons.cloud_sync_rounded, _Source.live),
          seg('محلي سريع', Icons.bolt_rounded, _Source.local),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SasLoadingView(message: 'جاري جلب المشتركين…');
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return SasEmptyView(
        message: _source == _Source.local
            ? 'لا مشتركون محليّون — نفّذ «مزامنة» أولاً'
            : 'لا يوجد مشتركون لعرضهم',
        icon: Icons.people_outline_rounded,
        action: _source == _Source.local
            ? OutlinedButton.icon(
                onPressed: _syncing ? null : _quickSync,
                icon: const Icon(Icons.sync_rounded),
                label: Text('مزامنة الآن', style: GoogleFonts.cairo()),
              )
            : null,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        children: [
          if (_source == _Source.local)
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 4.h, 14.w, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  _expiring == null
                      ? 'إجمالي محلي: $_localTotal · معروض: ${_rows.length}'
                      : 'مُفلتَر (${_rows.length}) من إجمالي محلي $_localTotal',
                  style: GoogleFonts.cairo(
                      fontSize: 11.sp,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(12.w, 6.h, 12.w, 12.h),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, i) => _subscriberCard(_rows[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscriberCard(SasSubscriber s) {
    final statusColor =
        s.isActive ? AppTheme.successColor : AppTheme.errorColor;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        onTap: () => _openDetail(s),
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: SasUi.card(),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44.w,
                    height: 44.w,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withValues(alpha: 0.18),
                          statusColor.withValues(alpha: 0.08),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.22)),
                    ),
                    child: Icon(Icons.person_rounded,
                        color: statusColor, size: 21.sp),
                  ),
                  if (s.online)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 13.w,
                        height: 13.w,
                        decoration: BoxDecoration(
                          color: AppTheme.successColor,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 2.2),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.username.isEmpty ? '-' : s.username,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1A1A2E)),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      '${s.fullName.isEmpty ? '' : '${s.fullName} · '}باقة: ${s.profileLabel}'
                      '${s.expiration != null ? ' · انتهاء: ${s.expiration}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontSize: 11.5.sp,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              SasStatusBadge(
                label: s.isActive ? 'نشط' : 'موقوف',
                color: statusColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
