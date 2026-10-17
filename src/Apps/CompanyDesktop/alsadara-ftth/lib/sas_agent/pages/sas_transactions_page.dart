import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_account.dart';
import '../models/sas_transaction.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_format.dart';
import '../widgets/sas_state_views.dart';

/// شاشة «سجل الحركات» — حركات العمليات المفوترة (تفعيل/تمديد/تغيير باقة) للحساب
/// المحدّد، من دفتر الصدارة الموحّد (Source=sas) عبر `GET accounts/{id}/transactions`.
///
/// تعرض لكل حركة: التاريخ · الإجراء (عربي) · المشترك · الباقة · المبلغ المحصّل ·
/// نوع التحصيل (عربي) · الحالة. مع:
///  • سحب-للتحديث (يُعيد من البداية).
///  • ترقيم عبر limit/offset (زر «تحميل المزيد» يضيف الدفعة التالية).
///  • حالات تحميل/فراغ/خطأ موحّدة عبر [sas_state_views].
///
/// ⚠️ لا هوية تُمرَّر؛ العزل (شركة + مالك) يفرضه الخادم. لا تُعرَض كلمات مرور.
class SasTransactionsPage extends StatefulWidget {
  final SasAccount account;
  const SasTransactionsPage({super.key, required this.account});

  @override
  State<SasTransactionsPage> createState() => _SasTransactionsPageState();
}

class _SasTransactionsPageState extends State<SasTransactionsPage> {
  final _api = SasAgentApiService.instance;

  static const int _pageSize = 50;

  final List<SasTransaction> _rows = [];
  int _total = 0;
  bool _loading = true; // التحميل الأوّل
  bool _loadingMore = false; // تحميل دفعة إضافية
  String? _error;

  String get _aid => widget.account.id;

  bool get _hasMore => _rows.length < _total;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  /// تحميل أوّل/إعادة من البداية (offset=0).
  Future<void> _loadFirst() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page =
          await _api.getTransactions(_aid, limit: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(page.data);
        _total = page.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _clean(e);
        _loading = false;
      });
    }
  }

  /// سحب-للتحديث.
  Future<void> _refresh() => _loadFirst();

  /// تحميل الدفعة التالية (offset = عدد الصفوف الحالي).
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.getTransactions(
        _aid,
        limit: _pageSize,
        offset: _rows.length,
      );
      if (!mounted) return;
      setState(() {
        _rows.addAll(page.data);
        _total = page.total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذّر تحميل المزيد: ${_clean(e)}',
            style: const TextStyle(fontFamily: SdText.family)),
        backgroundColor: SdColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasList = !_loading && _error == null && _rows.isNotEmpty;
    return SdPage(
      maxWidth: 980,
      scrollable: false,
      padding: hasList ? EdgeInsets.zero : null,
      appBar: SdAppBar(
        title: 'سجل الحركات',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب سجل الحركات…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _loadFirst);
    }
    if (_rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: const [
            SizedBox(height: 100),
            SdEmptyState(
              title: 'لا حركات مفوترة مسجّلة بعد',
              icon: Icons.receipt_long_rounded,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.sm,
            SdSpace.gutter, SdSpace.lg),
        // صف إضافي أخير = شريط العدّاد/«تحميل المزيد».
        itemCount: _rows.length + 1,
        separatorBuilder: (_, i) => SizedBox(
            height: i < _rows.length - 1 ? SdSpace.xs : SdSpace.sm),
        itemBuilder: (_, i) {
          if (i == _rows.length) return _footer();
          return _row(_rows[i]);
        },
      ),
    );
  }

  Widget _footer() {
    return Column(
      children: [
        Text('عرض ${_rows.length} من $_total', style: SdText.caption),
        if (_hasMore) ...[
          const SizedBox(height: SdSpace.sm),
          if (_loadingMore)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2.4, color: SdColors.primary),
            )
          else
            SdButton(
              label: 'تحميل المزيد',
              icon: Icons.expand_more_rounded,
              kind: SdButtonKind.secondary,
              onPressed: _loadMore,
            ),
        ],
      ],
    );
  }

  Widget _row(SasTransaction t) {
    final actionTone = _actionTone(t.action);
    final ok = t.isSuccess;
    final amount = t.collectedAmount;

    return SdCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // السطر العلوي: الإجراء + الحالة + المبلغ.
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: actionTone.tint,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                        color: actionTone.tintEdge, offset: const Offset(0, 3))
                  ],
                ),
                child: Icon(_actionIcon(t.action),
                    color: actionTone.base, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(t.actionAr,
                              overflow: TextOverflow.ellipsis,
                              style: SdText.label),
                        ),
                        const SizedBox(width: 8),
                        SdStatusChip(t.statusAr,
                            status:
                                ok ? SdStatus.success : SdStatus.danger),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        t.subscriberUsername.isEmpty
                            ? (t.subscriberUid.isEmpty ? '—' : t.subscriberUid)
                            : t.subscriberUsername,
                        textAlign: TextAlign.start,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: SdColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount != null ? _money(amount) : '—',
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: SdColors.success),
                  ),
                  Text(t.currency,
                      style: const TextStyle(
                          fontFamily: SdText.family,
                          fontSize: 11.5,
                          color: SdColors.faint)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: SdColors.divider),
          const SizedBox(height: 8),
          // السطر السفلي: الباقة · نوع التحصيل · على مَن · المُنفِّذ · التاريخ.
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _chip(Icons.wifi_rounded, 'الباقة',
                  t.planName.isEmpty ? '—' : t.planName),
              _chip(Icons.point_of_sale_rounded, 'التحصيل',
                  t.collectionTypeAr),
              // «على مَن»: اسم الفنّي/الوكيل أو «المواطن» (يظهر فقط عند وجود إسناد).
              if (t.assigneeAr.isNotEmpty)
                _chip(_assigneeIcon(t.collectionType), 'على مَن', t.assigneeAr),
              // المُنفِّذ (مختِم الحركة) — يظهر عند توفّره فقط.
              if (t.activatedBy.isNotEmpty)
                _chip(Icons.badge_rounded, 'المُنفِّذ', t.activatedBy),
              _chip(Icons.schedule_rounded, 'التاريخ',
                  t.createdAt.isEmpty ? '—' : sasDash(t.createdAt),
                  mono: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, String value,
      {bool mono = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: SdColors.faint),
        const SizedBox(width: 4),
        Text('$label: ', style: SdText.caption),
        mono
            ? Directionality(
                textDirection: TextDirection.ltr,
                child: Text(value,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        color: SdColors.ink)),
              )
            : Text(value,
                style: const TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: SdColors.ink)),
      ],
    );
  }

  /// أيقونة «على مَن» حسب نوع التحصيل (فنّي/وكيل/مواطن).
  IconData _assigneeIcon(String collectionType) {
    switch (collectionType) {
      case 'technician':
        return Icons.engineering_rounded;
      case 'agent':
        return Icons.store_rounded;
      case 'citizen':
        return Icons.person_pin_rounded;
      default:
        return Icons.person_outline_rounded;
    }
  }

  SdTone _actionTone(String action) {
    switch (action) {
      case 'activate':
        return SdStatus.success.tone;
      case 'extend':
        return SdStatus.info.tone;
      case 'changeProfile':
        return SdGroup.field.tone;
      default:
        return SdGroup.neutral.tone;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'activate':
        return Icons.play_arrow_rounded;
      case 'extend':
        return Icons.event_available_rounded;
      case 'changeProfile':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.receipt_long_rounded;
    }
  }

  String _money(num v) {
    final n = v == v.roundToDouble() ? v.round() : v;
    return n.toString();
  }
}
