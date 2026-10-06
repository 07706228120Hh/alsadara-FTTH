import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_transaction.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_format.dart';
import '../widgets/sas_metrics.dart';
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
      final page = await _api.getTransactions(_aid, limit: _pageSize, offset: 0);
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
            style: GoogleFonts.cairo()),
        backgroundColor: AppTheme.errorColor,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppTheme.primaryColor,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('سجل الحركات',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.white)),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _refresh,
            ),
          ],
        ),
        body: _body(),
      ),
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
            SizedBox(height: 120),
            SasEmptyView(
              message: 'لا حركات مفوترة مسجّلة بعد',
              icon: Icons.receipt_long_rounded,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 24.h),
            // صف إضافي أخير = شريط العدّاد/«تحميل المزيد».
            itemCount: _rows.length + 1,
            separatorBuilder: (_, i) =>
                i < _rows.length - 1 ? SizedBox(height: 8.h) : SizedBox(height: 14.h),
            itemBuilder: (_, i) {
              if (i == _rows.length) return _footer();
              return _row(_rows[i]);
            },
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    return Column(
      children: [
        Text(
          'عرض ${_rows.length} من $_total',
          style: GoogleFonts.cairo(
              fontSize: 12.sp, color: Colors.grey[600], fontWeight: FontWeight.w600),
        ),
        if (_hasMore) ...[
          SizedBox(height: 10.h),
          FilledButton.tonalIcon(
            onPressed: _loadingMore ? null : _loadMore,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.10),
              foregroundColor: AppTheme.primaryColor,
              padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 12.h),
            ),
            icon: _loadingMore
                ? SizedBox(
                    width: 16.w,
                    height: 16.w,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primaryColor),
                  )
                : const Icon(Icons.expand_more_rounded),
            label: Text('تحميل المزيد',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ],
    );
  }

  Widget _row(SasTransaction t) {
    final actionColor = _actionColor(t.action);
    final ok = t.isSuccess;
    final statusColor = ok ? AppTheme.successColor : AppTheme.errorColor;
    final amount = t.collectedAmount;

    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // السطر العلوي: الإجراء + الحالة + المبلغ.
          Row(
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11.r),
                ),
                child: Icon(_actionIcon(t.action),
                    color: actionColor, size: 20.sp),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(t.actionAr,
                            style: GoogleFonts.cairo(
                                fontSize: 13.5.sp,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1A1A2E))),
                        SizedBox(width: 8.w),
                        SasStatusBadge(label: t.statusAr, color: statusColor),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        t.subscriberUsername.isEmpty
                            ? (t.subscriberUid.isEmpty ? '—' : t.subscriberUid)
                            : t.subscriberUsername,
                        textAlign: TextAlign.start,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.robotoMono(
                            fontSize: 12.sp, color: Colors.grey[700]),
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
                    style: GoogleFonts.cairo(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.successColor),
                  ),
                  Text(t.currency,
                      style: GoogleFonts.cairo(
                          fontSize: 10.sp, color: Colors.grey[500])),
                ],
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.12)),
          SizedBox(height: 8.h),
          // السطر السفلي: الباقة · نوع التحصيل · على مَن · المُنفِّذ · التاريخ.
          Wrap(
            spacing: 16.w,
            runSpacing: 6.h,
            children: [
              _chip(Icons.wifi_rounded, 'الباقة',
                  t.planName.isEmpty ? '—' : t.planName),
              _chip(Icons.point_of_sale_rounded, 'التحصيل', t.collectionTypeAr),
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

  Widget _chip(IconData icon, String label, String value, {bool mono = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14.sp, color: Colors.grey[500]),
        SizedBox(width: 4.w),
        Text('$label: ',
            style:
                GoogleFonts.cairo(fontSize: 11.5.sp, color: Colors.grey[600])),
        mono
            ? Directionality(
                textDirection: TextDirection.ltr,
                child: Text(value,
                    style: GoogleFonts.robotoMono(
                        fontSize: 11.sp, color: const Color(0xFF1A1A2E))),
              )
            : Text(value,
                style: GoogleFonts.cairo(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1A1A2E))),
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

  Color _actionColor(String action) {
    switch (action) {
      case 'activate':
        return AppTheme.successColor;
      case 'extend':
        return AppTheme.infoColor;
      case 'changeProfile':
        return AppTheme.accentColor;
      default:
        return Colors.blueGrey;
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
