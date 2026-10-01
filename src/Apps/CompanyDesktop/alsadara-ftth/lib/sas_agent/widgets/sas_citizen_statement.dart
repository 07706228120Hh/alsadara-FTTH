import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
import 'sas_metrics.dart';
import 'sas_state_views.dart';

/// عرض «كشف حساب المواطن» (الآجل/الذمّة) القابل لإعادة الاستخدام:
/// الرصيد المستحق بارز + زر «تسديد» + قائمة الشحنات + قائمة التسديدات.
///
/// يُستخدم كتبويب داخل صفحة تفاصيل المشترك، وكشاشة مستقلّة من صفحة المدينين.
/// التسديد محكوم بصلاحية `sas_agent` (الحماية النهائية في الخادم).
class SasCitizenStatementView extends StatefulWidget {
  final String accountId;
  final String userId;

  /// اسم المواطن للعرض في حوار التسديد (اختياري).
  final String? subscriberName;

  /// يُستدعى بعد تسديد ناجح (لتحديث قوائم خارجية مثل المدينين).
  final VoidCallback? onChanged;

  const SasCitizenStatementView({
    super.key,
    required this.accountId,
    required this.userId,
    this.subscriberName,
    this.onChanged,
  });

  @override
  State<SasCitizenStatementView> createState() =>
      _SasCitizenStatementViewState();
}

class _SasCitizenStatementViewState extends State<SasCitizenStatementView> {
  final _api = SasAgentApiService.instance;

  SasCitizenStatement? _statement;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final st = await _api.getStatement(widget.accountId, widget.userId);
      if (!mounted) return;
      setState(() {
        _statement = st;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _clean(e);
          _loading = false;
        });
      }
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب كشف الحساب…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _load);
    }
    final st = _statement!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 20.h),
        children: [
          _balanceCard(st.balance),
          SizedBox(height: 14.h),
          SasSectionHeader(
            title: 'الشحنات',
            icon: Icons.receipt_long_rounded,
            gradient: AppTheme.orangeGradient,
            trailingText: '${st.charges.length}',
          ),
          SizedBox(height: 8.h),
          if (st.charges.isEmpty)
            _emptyInline('لا توجد شحنات')
          else
            for (final c in st.charges) _chargeTile(c),
          SizedBox(height: 16.h),
          SasSectionHeader(
            title: 'التسديدات',
            icon: Icons.payments_rounded,
            gradient: AppTheme.greenGradient,
            trailingText: '${st.payments.length}',
          ),
          SizedBox(height: 8.h),
          if (st.payments.isEmpty)
            _emptyInline('لا توجد تسديدات')
          else
            for (final p in st.payments) _paymentTile(p),
        ],
      ),
    );
  }

  Widget _balanceCard(num balance) {
    final owed = balance > 0;
    final color = owed ? AppTheme.errorColor : AppTheme.successColor;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1.3),
        boxShadow: SasUi.cardShadow(color),
      ),
      child: Row(
        children: [
          Container(
            width: 46.w,
            height: 46.w,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: color, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الرصيد المستحق',
                    style: GoogleFonts.cairo(
                        fontSize: 12.sp, color: Colors.grey[700])),
                SizedBox(height: 2.h),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${_fmt(balance)} IQD',
                    style: GoogleFonts.robotoMono(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                        color: color),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(owed ? 'مدين على المواطن' : 'لا ذمّة مستحقة',
                    style: GoogleFonts.cairo(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: (!_canManage || _busy) ? null : _showPaymentDialog,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.successColor,
              disabledBackgroundColor: Colors.grey.withValues(alpha: 0.30),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            ),
            icon: _busy
                ? SizedBox(
                    width: 16.w,
                    height: 16.w,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.add_card_rounded),
            label: Text(_canManage ? 'تسديد' : 'لا صلاحية',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _chargeTile(SasCitizenCharge c) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.north_east_rounded,
              size: 18.sp, color: AppTheme.warningColor),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.operationType.isEmpty ? (c.planName.isEmpty ? '—' : c.planName) : c.operationType,
                  style: GoogleFonts.cairo(
                      fontSize: 12.5.sp, fontWeight: FontWeight.w800),
                ),
                if (c.planName.isNotEmpty && c.operationType.isNotEmpty)
                  Text(c.planName,
                      style: GoogleFonts.cairo(
                          fontSize: 11.sp, color: Colors.grey[600])),
                if (c.createdAt.isNotEmpty)
                  Text(c.createdAt,
                      style: GoogleFonts.robotoMono(
                          fontSize: 10.5.sp, color: Colors.grey[500])),
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('${_fmt(c.amount ?? 0)} ${c.currency}',
                style: GoogleFonts.robotoMono(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.warningColor)),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(SasCitizenPayment p) {
    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.all(12.w),
      decoration: SasUi.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.south_west_rounded,
              size: 18.sp, color: AppTheme.successColor),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تسديد (${p.methodAr})',
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp, fontWeight: FontWeight.w800)),
                if (p.note.isNotEmpty)
                  Text(p.note,
                      style: GoogleFonts.cairo(
                          fontSize: 11.sp, color: Colors.grey[600])),
                if (p.createdAt.isNotEmpty)
                  Text(p.createdAt,
                      style: GoogleFonts.robotoMono(
                          fontSize: 10.5.sp, color: Colors.grey[500])),
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('${_fmt(p.amount ?? 0)} IQD',
                style: GoogleFonts.robotoMono(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.successColor)),
          ),
        ],
      ),
    );
  }

  Widget _emptyInline(String msg) => Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.inbox_rounded, color: Colors.grey[400], size: 18.sp),
            SizedBox(width: 8.w),
            Text(msg,
                style: GoogleFonts.cairo(
                    fontSize: 12.sp, color: Colors.grey[600])),
          ],
        ),
      );

  // ─── حوار التسديد ───

  Future<void> _showPaymentDialog() async {
    final amountCtl = TextEditingController();
    final noteCtl = TextEditingController();
    String method = 'cash';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SasUi.radius.r)),
            title: Row(
              children: [
                const Icon(Icons.add_card_rounded,
                    color: AppTheme.successColor, size: 24),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text('تسديد على الذمّة',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.successColor)),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((widget.subscriberName ?? '').isNotEmpty) ...[
                      Text('المواطن: ${widget.subscriberName}',
                          style: GoogleFonts.cairo(
                              fontSize: 12.5.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[700])),
                      SizedBox(height: 12.h),
                    ],
                    TextField(
                      controller: amountCtl,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                      style: GoogleFonts.robotoMono(
                          fontWeight: FontWeight.w700, fontSize: 14.sp),
                      decoration: InputDecoration(
                        labelText: 'المبلغ',
                        labelStyle:
                            GoogleFonts.cairo(color: Colors.grey[600]),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(SasUi.radiusSm.r)),
                      ),
                    ),
                    SizedBox(height: 14.h),
                    Text('طريقة التسديد',
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.sp,
                            color: Colors.grey[700])),
                    SizedBox(height: 6.h),
                    Wrap(
                      spacing: 8.w,
                      children: [
                        _methodChip('cash', 'نقد', method,
                            (v) => setLocal(() => method = v)),
                        _methodChip('master', 'ماستر', method,
                            (v) => setLocal(() => method = v)),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    TextField(
                      controller: noteCtl,
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w600, fontSize: 13.sp),
                      decoration: InputDecoration(
                        labelText: 'ملاحظة (اختياري)',
                        labelStyle:
                            GoogleFonts.cairo(color: Colors.grey[600]),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(SasUi.radiusSm.r)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.successColor),
                child: Text('تسديد',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    final amount = num.tryParse(amountCtl.text.trim()) ?? 0;
    if (amount <= 0) {
      _snack('أدخل مبلغاً صالحاً', error: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await _api.recordCitizenPayment(
        widget.accountId,
        widget.userId,
        amount: amount,
        method: method,
        note: noteCtl.text.trim().isEmpty ? null : noteCtl.text.trim(),
      );
      if (!mounted) return;
      _snack('تم تسجيل التسديد');
      widget.onChanged?.call();
      await _load();
    } catch (e) {
      if (mounted) _snack(_clean(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _methodChip(String value, String label, String selected,
      ValueChanged<String> onPick) {
    final active = value == selected;
    return ChoiceChip(
      selected: active,
      onSelected: (_) => onPick(value),
      label: Text(label,
          style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : Colors.grey[700])),
      selectedColor: AppTheme.successColor,
      backgroundColor: Colors.grey.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
    );
  }

  String _fmt(num v) =>
      (v == v.roundToDouble()) ? v.round().toString() : v.toString();
}

/// شاشة كشف حساب مواطن مستقلّة (تُفتح من صفحة المدينين) — تغلّف العرض المشترك.
class SasCitizenStatementScreen extends StatelessWidget {
  final String accountId;
  final String userId;
  final String? subscriberName;

  const SasCitizenStatementScreen({
    super.key,
    required this.accountId,
    required this.userId,
    this.subscriberName,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
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
          title: Text(
            subscriberName?.trim().isNotEmpty == true
                ? 'كشف: ${subscriberName!.trim()}'
                : 'كشف حساب المواطن',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: SasCitizenStatementView(
              accountId: accountId,
              userId: userId,
              subscriberName: subscriberName,
            ),
          ),
        ),
      ),
    );
  }
}
