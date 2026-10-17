import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../permissions/permission_manager.dart';
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
import 'sas_refresh_bus.dart';
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

  // نمط أرقام تقنية أحادي المسافة (مبالغ/تواريخ).
  static const _mono = TextStyle(fontFamily: 'monospace');

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
      content: Text(msg,
          style: const TextStyle(
              fontFamily: SdText.family, fontWeight: FontWeight.w600)),
      backgroundColor: error ? SdColors.danger : SdColors.success,
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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          _balanceCard(st.balance),
          const SizedBox(height: 14),
          SasSectionHeader(
            title: 'الشحنات',
            icon: Icons.receipt_long_rounded,
            gradient: const [SdColors.warning, SdColors.warningEdge],
            trailingText: '${st.charges.length}',
          ),
          const SizedBox(height: 8),
          if (st.charges.isEmpty)
            _emptyInline('لا توجد شحنات')
          else
            for (final c in st.charges) _chargeTile(c),
          const SizedBox(height: 16),
          SasSectionHeader(
            title: 'التسديدات',
            icon: Icons.payments_rounded,
            gradient: const [SdColors.success, SdColors.successEdge],
            trailingText: '${st.payments.length}',
          ),
          const SizedBox(height: 8),
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
    final color = owed ? SdColors.danger : SdColors.success;
    final tone = owed ? SdStatus.danger.tone : SdStatus.success.tone;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: [
          BoxShadow(color: tone.tintEdge, offset: const Offset(0, SdDepth.card)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tone.tintEdge,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الرصيد المستحق', style: SdText.caption),
                const SizedBox(height: 2),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '${_fmt(balance)} IQD',
                    style: _mono.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color),
                  ),
                ),
                const SizedBox(height: 2),
                Text(owed ? 'مدين على المواطن' : 'لا ذمّة مستحقة',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
          ),
          SdButton(
            label: _canManage ? 'تسديد' : 'لا صلاحية',
            icon: Icons.add_card_rounded,
            kind: SdButtonKind.accent,
            height: 46,
            onPressed: (!_canManage || _busy) ? null : _showPaymentDialog,
          ),
        ],
      ),
    );
  }

  Widget _chargeTile(SasCitizenCharge c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: SasUi.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.north_east_rounded,
              size: 18, color: SdColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.operationType.isEmpty
                      ? (c.planName.isEmpty ? '—' : c.planName)
                      : c.operationType,
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: SdColors.ink),
                ),
                if (c.planName.isNotEmpty && c.operationType.isNotEmpty)
                  Text(c.planName, style: SdText.caption),
                if (c.createdAt.isNotEmpty)
                  Text(c.createdAt,
                      style: _mono.copyWith(
                          fontSize: 10.5, color: SdColors.faint)),
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('${_fmt(c.amount ?? 0)} ${c.currency}',
                style: _mono.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: SdColors.warning)),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(SasCitizenPayment p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: SasUi.card(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.south_west_rounded,
              size: 18, color: SdColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تسديد (${p.methodAr})',
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: SdColors.ink)),
                if (p.note.isNotEmpty)
                  Text(p.note, style: SdText.caption),
                if (p.createdAt.isNotEmpty)
                  Text(p.createdAt,
                      style: _mono.copyWith(
                          fontSize: 10.5, color: SdColors.faint)),
              ],
            ),
          ),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('${_fmt(p.amount ?? 0)} IQD',
                style: _mono.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: SdColors.success)),
          ),
        ],
      ),
    );
  }

  Widget _emptyInline(String msg) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SdColors.surfaceAlt,
          borderRadius: BorderRadius.circular(SdRadius.sm),
          border: Border.all(color: SdColors.divider),
        ),
        child: Row(
          children: [
            const Icon(Icons.inbox_rounded, color: SdColors.faint, size: 18),
            const SizedBox(width: 8),
            Text(msg, style: SdText.bodySm),
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
            backgroundColor: SdColors.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SdRadius.lg)),
            title: Row(
              children: [
                const Icon(Icons.add_card_rounded,
                    color: SdColors.success, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('تسديد على الذمّة',
                      style: const TextStyle(
                          fontFamily: SdText.family,
                          fontWeight: FontWeight.w800,
                          color: SdColors.success)),
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
                          style: const TextStyle(
                              fontFamily: SdText.family,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: SdColors.muted)),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: amountCtl,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                      ],
                      style: _mono.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'المبلغ',
                        labelStyle: const TextStyle(
                            fontFamily: SdText.family, color: SdColors.muted),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(SdRadius.sm)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('طريقة التسديد',
                        style: const TextStyle(
                            fontFamily: SdText.family,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: SdColors.muted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        _methodChip('cash', 'نقد', method,
                            (v) => setLocal(() => method = v)),
                        _methodChip('master', 'ماستر', method,
                            (v) => setLocal(() => method = v)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: noteCtl,
                      style: const TextStyle(
                          fontFamily: SdText.family,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'ملاحظة (اختياري)',
                        labelStyle: const TextStyle(
                            fontFamily: SdText.family, color: SdColors.muted),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(SdRadius.sm)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        fontWeight: FontWeight.w700,
                        color: SdColors.muted)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor: SdColors.success),
                child: const Text('تسديد',
                    style: TextStyle(
                        fontFamily: SdText.family, fontWeight: FontWeight.w700)),
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
      // مزامنة الحساب ثم إشعار كل التبويبات المفتوحة (معزول — فشله لا يُسقط).
      await SasRefreshBus.instance
          .syncAndNotify(widget.accountId, reason: 'citizen-payment');
      if (!mounted) return;
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
          style: TextStyle(
              fontFamily: SdText.family,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : SdColors.muted)),
      selectedColor: SdColors.success,
      backgroundColor: SdColors.surfaceAlt,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm)),
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
    return SdPage(
      maxWidth: 820,
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: SdAppBar(
        title: subscriberName?.trim().isNotEmpty == true
            ? 'كشف: ${subscriberName!.trim()}'
            : 'كشف حساب المواطن',
      ),
      body: SasCitizenStatementView(
        accountId: accountId,
        userId: userId,
        subscriberName: subscriberName,
      ),
    );
  }
}
