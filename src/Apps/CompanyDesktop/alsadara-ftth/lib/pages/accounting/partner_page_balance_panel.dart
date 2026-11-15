import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../frontend/tokens/sd_colors.dart' show SdColors;
import '../../permissions/permission_manager.dart';
import 'dart:convert';
import '../../services/accounting_service.dart';
import '../../services/auth_service.dart';
import '../../services/linked_accounts_service.dart';

/// Reads a field from a backend DTO regardless of casing (records are
/// serialized PascalCase, anonymous wrappers camelCase).
dynamic _f(Map m, String pascal) {
  if (m.containsKey(pascal)) return m[pascal];
  final camel = pascal[0].toLowerCase() + pascal.substring(1);
  return m[camel];
}

double _num(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

final _money = NumberFormat('#,##0', 'en_US');

String _fmt(double v) => '${_money.format(v)} د.ع';

const _cairo = 'Cairo';

/// Compact panel for the «خادمنا» tab: general page balance + one balance per
/// FTTH partner, with top-up / transfer / statement actions for the selected
/// partner. Self-contained: loads its own data and reloads after any change.
class PartnerPageBalancePanel extends StatefulWidget {
  /// Selected partner (FtthPartner id) from the tab's dropdown; null = all.
  final String? selectedPartnerId;

  /// Tapping a partner tile selects it in the tab's dropdown.
  final ValueChanged<String?>? onSelectPartner;

  const PartnerPageBalancePanel({
    super.key,
    this.selectedPartnerId,
    this.onSelectPartner,
  });

  @override
  State<PartnerPageBalancePanel> createState() =>
      _PartnerPageBalancePanelState();
}

class _PartnerPageBalancePanelState extends State<PartnerPageBalancePanel> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _overview;

  bool get _canEdit =>
      PermissionManager.instance.canEdit('accounting.ftth_operators');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await AccountingService.instance.getPartnerPageBalances();
      if (!mounted) return;
      if (res['success'] == true && res['data'] is Map) {
        _overview = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = (res['message'] ?? 'تعذّر جلب أرصدة الشركاء').toString();
      }
    } catch (_) {
      _error = 'تعذّر جلب أرصدة الشركاء';
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _partners {
    final raw = _overview == null ? null : _f(_overview!, 'Partners');
    if (raw is! List) return const [];
    return [
      for (final p in raw)
        if (p is Map) Map<String, dynamic>.from(p)
    ];
  }

  Map<String, dynamic>? get _selected {
    final id = widget.selectedPartnerId?.toLowerCase();
    if (id == null) return null;
    for (final p in _partners) {
      if (_f(p, 'PartnerId')?.toString().toLowerCase() == id) return p;
    }
    return null;
  }

  Future<void> _openFund(Map<String, dynamic> partner,
      {required bool fromGeneral, bool toGeneral = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FundDialog(
        partner: partner,
        overview: _overview!,
        fromGeneral: fromGeneral,
        toGeneral: toGeneral,
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _openStatement(Map<String, dynamic> partner) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _StatementDialog(partner: partner, canEdit: _canEdit),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26),
      ),
      child: _loading
          ? const SizedBox(
              height: 40,
              child: Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))))
          : _error != null
              ? Row(children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: SdColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              fontFamily: _cairo,
                              fontSize: 12,
                              color: SdColors.danger))),
                  TextButton(
                      onPressed: _load,
                      child: const Text('إعادة المحاولة',
                          style: TextStyle(fontFamily: _cairo, fontSize: 12))),
                ])
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    final o = _overview!;
    final selected = _selected;
    final tiles = <Widget>[
      _tile('الرصيد العام', _num(_f(o, 'GeneralBalance')), SdColors.primary,
          icon: Icons.account_balance_wallet_outlined),
    ];

    if (widget.selectedPartnerId == null) {
      tiles.add(_tile(
          'مجموع الشركاء', _num(_f(o, 'PartnersTotal')), SdColors.info,
          icon: Icons.functions));
      for (final p in _partners) {
        // A deleted partner cannot be selected; its leftover balance can only
        // be returned to the general balance.
        final deleted = _f(p, 'PartnerDeleted') == true;
        tiles.add(_tile(
          deleted
              ? '${(_f(p, 'Name') ?? '').toString()} (محذوف)'
              : (_f(p, 'Name') ?? '').toString(),
          _num(_f(p, 'Balance')),
          deleted ? SdColors.danger : SdColors.accent,
          icon: deleted ? Icons.undo : Icons.business,
          onTap: deleted
              ? (_canEdit && _f(p, 'PartnerId') != null
                  ? () => _openFund(p, fromGeneral: false, toGeneral: true)
                  : null)
              : widget.onSelectPartner == null
                  ? null
                  : () =>
                      widget.onSelectPartner!(_f(p, 'PartnerId')?.toString()),
        ));
      }
    } else if (selected != null) {
      tiles.add(_tile(
        'رصيد ${(_f(selected, 'Name') ?? '').toString()}',
        _num(_f(selected, 'Balance')),
        SdColors.accent,
        icon: Icons.business,
        subtitle: (_f(selected, 'Code') ?? '').toString(),
      ));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsetsDirectional.only(end: 4),
          child: Text('رصيد الصفحة',
              style: TextStyle(
                  fontFamily: _cairo,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ),
        ...tiles,
        if (widget.selectedPartnerId != null && selected == null)
          const Text('لا يوجد حساب رصيد لهذا الشريك',
              style: TextStyle(
                  fontFamily: _cairo, fontSize: 12, color: SdColors.faint)),
        if (selected != null) ...[
          if (_canEdit) ...[
            _action('شحن', Icons.add_card, SdColors.success,
                () => _openFund(selected, fromGeneral: false)),
            _action(
                'تحويل من الرصيد العام إلى شريك',
                Icons.swap_horiz,
                SdColors.info,
                () => _openFund(selected, fromGeneral: true)),
            _action(
                'إرجاع إلى الرصيد العام',
                Icons.undo,
                SdColors.danger,
                () => _openFund(selected, fromGeneral: false, toGeneral: true)),
          ],
          _action('كشف الحساب', Icons.receipt_long, SdColors.primary,
              () => _openStatement(selected)),
        ],
        IconButton(
          onPressed: _load,
          tooltip: 'تحديث',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          icon: const Icon(Icons.refresh, size: 16, color: SdColors.faint),
        ),
      ],
    );
  }

  Widget _tile(String title, double value, Color color,
      {IconData? icon, String? subtitle, VoidCallback? onTap}) {
    final negative = value < 0;
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
        ],
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              subtitle == null || subtitle.isEmpty
                  ? title
                  : '$title · $subtitle',
              style: const TextStyle(
                  fontFamily: _cairo, fontSize: 10, color: Colors.black54),
            ),
            Text(
              _fmt(value),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: _cairo,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: negative ? SdColors.danger : Colors.black87,
              ),
            ),
          ],
        ),
      ]),
    );
    if (onTap == null) return body;
    return InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(8), child: body);
  }

  Widget _action(
      String label, IconData icon, Color color, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label,
          style: const TextStyle(fontFamily: _cairo, fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Top-up / transfer dialog
// ════════════════════════════════════════════════════════════════

class _FundDialog extends StatefulWidget {
  final Map<String, dynamic> partner;
  final Map<String, dynamic> overview;

  /// true = transfer from the general page balance; false = top-up from a cash box.
  final bool fromGeneral;

  /// true = return from the partner's balance to the general page balance.
  final bool toGeneral;

  const _FundDialog({
    required this.partner,
    required this.overview,
    required this.fromGeneral,
    this.toGeneral = false,
  });

  @override
  State<_FundDialog> createState() => _FundDialogState();
}

class _FundDialogState extends State<_FundDialog> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _source; // 'petty' | 'main'
  bool _busy = false;
  String? _error;

  // One key per distinct (amount, source) attempt: a retry of the same request
  // never double-posts, while a corrected amount is a new request.
  String _key = _newKey();
  String? _keySignature;

  static String _newKey() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final rnd = Random.secure();
    return List.generate(24, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  bool get _hasPetty => _f(widget.overview, 'HasPettyCash') == true;
  bool get _hasMain => _f(widget.overview, 'HasCompanyMainCash') == true;
  double get _pettyBalance => _num(_f(widget.overview, 'PettyCashBalance'));
  double get _mainBalance =>
      _num(_f(widget.overview, 'CompanyMainCashBalance'));
  double get _generalBalance => _num(_f(widget.overview, 'GeneralBalance'));

  double get _partnerBalance => _num(_f(widget.partner, 'Balance'));

  double get _available => widget.toGeneral
      ? _partnerBalance
      : widget.fromGeneral
      ? _generalBalance
      : _source == 'petty'
          ? _pettyBalance
          : _source == 'main'
              ? _mainBalance
              : 0;

  @override
  void initState() {
    super.initState();
    if (!widget.fromGeneral && !widget.toGeneral) {
      _source = _hasPetty ? 'petty' : (_hasMain ? 'main' : null);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغاً صحيحاً أكبر من صفر');
      return;
    }
    if (!widget.fromGeneral && !widget.toGeneral && _source == null) {
      setState(() => _error = 'اختر مصدر الشحن');
      return;
    }
    if (amount > _available) {
      setState(() => _error = widget.toGeneral
          ? 'المبلغ يتجاوز رصيد الشريك (${_fmt(_available)})'
          : 'المبلغ يتجاوز الرصيد المتاح في المصدر (${_fmt(_available)})');
      return;
    }

    final signature = '$amount|$_source';
    if (_keySignature != null && _keySignature != signature) _key = _newKey();
    _keySignature = signature;

    setState(() {
      _busy = true;
      _error = null;
    });
    final partnerId = _f(widget.partner, 'PartnerId').toString();
    final notes = _notesCtrl.text.trim();
    Map<String, dynamic> res;
    try {
      res = widget.toGeneral
          ? await AccountingService.instance.returnPartnerPageBalanceToGeneral(
              partnerId,
              amount: amount,
              idempotencyKey: _key,
              notes: notes)
          : widget.fromGeneral
          ? await AccountingService.instance
              .transferGeneralToPartnerPageBalance(partnerId,
                  amount: amount, idempotencyKey: _key, notes: notes)
          : await AccountingService.instance.topUpPartnerPageBalance(partnerId,
              amount: amount,
              source: _source!,
              idempotencyKey: _key,
              notes: notes);
    } catch (_) {
      res = {'success': false, 'message': 'تعذّر الاتصال بالخادم'};
    }
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = (res['message'] ?? 'فشلت العملية').toString();
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = (_f(widget.partner, 'Name') ?? '').toString();
    final title = widget.toGeneral
        ? 'إرجاع من $name إلى الرصيد العام'
        : widget.fromGeneral
            ? 'تحويل من الرصيد العام إلى $name'
            : 'شحن رصيد $name';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(title,
            style: const TextStyle(
                fontFamily: _cairo,
                fontSize: 15,
                fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'الرصيد الحالي للشريك: ${_fmt(_num(_f(widget.partner, 'Balance')))}',
                  style: const TextStyle(fontFamily: _cairo, fontSize: 12)),
              const SizedBox(height: 8),
              if (widget.toGeneral)
                Text('الرصيد العام الحالي: ${_fmt(_generalBalance)}',
                    style: const TextStyle(fontFamily: _cairo, fontSize: 12))
              else if (widget.fromGeneral)
                Text('المتاح في الرصيد العام: ${_fmt(_generalBalance)}',
                    style: const TextStyle(fontFamily: _cairo, fontSize: 12))
              else if (!_hasPetty && !_hasMain)
                const Text(
                    'لا يوجد حساب القاصة ولا صندوق الشركة الرئيسي في شجرة الحسابات',
                    style: TextStyle(
                        fontFamily: _cairo,
                        fontSize: 12,
                        color: SdColors.danger))
              else
                Wrap(spacing: 8, runSpacing: 6, children: [
                  if (_hasPetty)
                    _sourceChip('petty', 'القاصة', _pettyBalance),
                  if (_hasMain)
                    _sourceChip('main', 'صندوق الشركة الرئيسي', _mainBalance),
                ]),
              const SizedBox(height: 10),
              TextField(
                controller: _amountCtrl,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontFamily: _cairo, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'المبلغ (د.ع)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _busy ? null : _submit(),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                enabled: !_busy,
                maxLength: 200,
                style: const TextStyle(fontFamily: _cairo, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: const TextStyle(
                        fontFamily: _cairo,
                        fontSize: 12,
                        color: SdColors.danger)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: _cairo)),
          ),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.success,
                foregroundColor: Colors.white),
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(
                    widget.toGeneral
                        ? 'إرجاع'
                        : widget.fromGeneral
                            ? 'تحويل'
                            : 'شحن',
                    style: const TextStyle(fontFamily: _cairo)),
          ),
        ],
      ),
    );
  }

  Widget _sourceChip(String value, String label, double balance) {
    return ChoiceChip(
      selected: _source == value,
      onSelected: _busy ? null : (_) => setState(() => _source = value),
      label: Text('$label — ${_fmt(balance)}',
          style: const TextStyle(fontFamily: _cairo, fontSize: 12)),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Statement dialog
// ════════════════════════════════════════════════════════════════

class _StatementDialog extends StatefulWidget {
  final Map<String, dynamic> partner;
  final bool canEdit;

  const _StatementDialog({required this.partner, required this.canEdit});

  @override
  State<_StatementDialog> createState() => _StatementDialogState();
}

class _StatementDialogState extends State<_StatementDialog> {
  static const _pageSize = 50;
  final _rows = <Map<String, dynamic>>[];
  final _dateFmt = DateFormat('yyyy/MM/dd HH:mm');
  Map<String, dynamic>? _head;
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  String? _error;
  String? _reversingId;
  bool _changed = false;

  String get _partnerId => _f(widget.partner, 'PartnerId').toString();

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _reload() async {
    _rows.clear();
    _page = 0;
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await AccountingService.instance.getPartnerPageStatement(
          _partnerId,
          page: _page + 1,
          pageSize: _pageSize);
      if (!mounted) return;
      if (res['success'] == true && res['data'] is Map) {
        final d = Map<String, dynamic>.from(res['data'] as Map);
        _head = d;
        _total = _num(_f(d, 'Total')).toInt();
        final rows = _f(d, 'Rows');
        if (rows is List) {
          for (final r in rows) {
            if (r is Map) _rows.add(Map<String, dynamic>.from(r));
          }
        }
        _page++;
      } else {
        _error = (res['message'] ?? 'تعذّر جلب كشف الحساب').toString();
      }
    } catch (_) {
      _error = 'تعذّر جلب كشف الحساب';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reverse(Map<String, dynamic> row) async {
    final amount = max(_num(_f(row, 'Debit')), _num(_f(row, 'Credit')));
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('عكس العملية',
              style: TextStyle(
                  fontFamily: _cairo,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
          content: Text(
              'سيُنشأ قيد معاكس بمبلغ ${_fmt(amount)} ويعود المبلغ إلى مصدره. لا يمكن التراجع عن العكس. هل تريد المتابعة؟',
              style: const TextStyle(fontFamily: _cairo, fontSize: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    const Text('إلغاء', style: TextStyle(fontFamily: _cairo))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.danger,
                    foregroundColor: Colors.white),
                child: const Text('عكس',
                    style: TextStyle(fontFamily: _cairo))),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    final id = _f(row, 'JournalEntryId').toString();
    setState(() => _reversingId = id);
    Map<String, dynamic> res;
    try {
      res = await AccountingService.instance.reversePartnerPageFunding(id);
    } catch (_) {
      res = {'success': false, 'message': 'تعذّر الاتصال بالخادم'};
    }
    if (!mounted) return;
    setState(() => _reversingId = null);
    if (res['success'] == true) {
      _changed = true;
      await _reload();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((res['message'] ?? 'فشل عكس العملية').toString(),
              style: const TextStyle(fontFamily: _cairo))));
    }
  }

  String _kindLabel(String kind) {
    switch (kind.toLowerCase()) {
      case 'topup':
        return 'شحن';
      case 'transfer':
      case 'xfer':
        return 'تحويل من العام';
      case 'reversal':
      case 'rev':
        return 'عكس';
      case 'return':
        return 'إرجاع للعام';
      case 'activation':
        return 'تفعيل';
      default:
        return 'قيد';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (_f(widget.partner, 'Name') ?? '').toString();
    final head = _head;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.pop(context, _changed);
        },
        child: AlertDialog(
          title: Row(children: [
            Expanded(
              child: Text('كشف حساب رصيد $name',
                  style: const TextStyle(
                      fontFamily: _cairo,
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
            ),
            IconButton(
                onPressed: () => Navigator.pop(context, _changed),
                icon: const Icon(Icons.close, size: 18)),
          ]),
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          content: SizedBox(
            width: 720,
            height: 460,
            child: Column(children: [
              if (head != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Wrap(spacing: 14, runSpacing: 4, children: [
                    _stat('الرصيد الحالي',
                        _num(_f(head, 'CurrentBalance')), SdColors.primary),
                    _stat('إجمالي الشحن', _num(_f(head, 'TotalDebit')),
                        SdColors.success),
                    _stat('إجمالي الخصم', _num(_f(head, 'TotalCredit')),
                        SdColors.danger),
                  ]),
                ),
              const Divider(height: 1),
              Expanded(child: _buildList()),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, double value, Color color) => Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          TextSpan(
              text: _fmt(value),
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
        style: const TextStyle(fontFamily: _cairo),
      );

  Widget _buildList() {
    if (_rows.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
          child: Text(_error ?? 'لا توجد حركات',
              style: TextStyle(
                  fontFamily: _cairo,
                  fontSize: 13,
                  color: _error != null ? SdColors.danger : SdColors.faint)));
    }
    final hasMore = _rows.length < _total;
    return ListView.separated(
      itemCount: _rows.length + (hasMore || _error != null ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        if (i >= _rows.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(
                      onPressed: _loadMore,
                      child: Text(
                          _error != null ? 'إعادة المحاولة' : 'تحميل المزيد',
                          style: const TextStyle(
                              fontFamily: _cairo, fontSize: 12))),
            ),
          );
        }
        return _buildRow(_rows[i]);
      },
    );
  }

  Widget _buildRow(Map<String, dynamic> r) {
    final debit = _num(_f(r, 'Debit'));
    final credit = _num(_f(r, 'Credit'));
    final isIn = debit > 0;
    final color = isIn ? SdColors.success : SdColors.danger;
    final dateRaw = (_f(r, 'CreatedAt') ?? _f(r, 'EntryDate'))?.toString();
    final date = dateRaw == null ? null : DateTime.tryParse(dateRaw);
    final id = _f(r, 'JournalEntryId').toString();
    final reversed = _f(r, 'Reversed') == true;
    final canReverse = widget.canEdit && _f(r, 'CanReverse') == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
          width: 108,
          child: Text(date == null ? '—' : _dateFmt.format(date.toLocal()),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                  fontFamily: _cairo, fontSize: 11, color: Colors.black54)),
        ),
        Container(
          margin: const EdgeInsetsDirectional.only(end: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(_kindLabel((_f(r, 'Kind') ?? '').toString()),
              style: TextStyle(fontFamily: _cairo, fontSize: 11, color: color)),
        ),
        Expanded(
          child: Text(
            '${(_f(r, 'Description') ?? '').toString()}${reversed ? ' (معكوسة)' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontFamily: _cairo,
                fontSize: 12,
                decoration: reversed ? TextDecoration.lineThrough : null),
          ),
        ),
        SizedBox(
          width: 120,
          child: Text(
            '${isIn ? '+' : '−'} ${_money.format(isIn ? debit : credit)}',
            textAlign: TextAlign.end,
            textDirection: TextDirection.ltr,
            style: TextStyle(
                fontFamily: _cairo,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color),
          ),
        ),
        SizedBox(
          width: 64,
          child: !canReverse
              ? null
              : _reversingId == id
                  ? const Center(
                      child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : TextButton(
                      onPressed:
                          _reversingId != null ? null : () => _reverse(r),
                      style: TextButton.styleFrom(
                          foregroundColor: SdColors.danger,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact),
                      child: const Text('عكس',
                          style: TextStyle(fontFamily: _cairo, fontSize: 12))),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Partner balances window — opened from the main accounts page
// ════════════════════════════════════════════════════════════════

/// Opens the dedicated partner-balances window.
Future<void> showPartnerBalancesDialog(BuildContext context) =>
    showDialog<void>(
        context: context, builder: (_) => const PartnerBalancesDialog());

/// Per-partner FTTH («صفحة الشريك») fetch state.
class _FtthBalanceState {
  final bool loading;
  final double? balance;
  final String? error;
  const _FtthBalanceState({this.loading = true, this.balance, this.error});
}

/// Dialog that lists every FTTH partner with two balances side by side —
/// «خادمنا» (our page-balance account) and «صفحة الشريك» (the partner's real
/// FTTH wallet) — their difference, and all operations (top-up / transfer /
/// return / statement). The FTTH column is loaded automatically on open,
/// one partner at a time (a login + wallet query per partner).
class PartnerBalancesDialog extends StatefulWidget {
  const PartnerBalancesDialog({super.key});

  @override
  State<PartnerBalancesDialog> createState() => _PartnerBalancesDialogState();
}

class _PartnerBalancesDialogState extends State<PartnerBalancesDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _overview;
  final Map<String, _FtthBalanceState> _ftth = {}; // PartnerId → state

  bool get _canEdit =>
      PermissionManager.instance.canEdit('accounting.ftth_operators');

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await AccountingService.instance.getPartnerPageBalances();
      if (!mounted) return;
      if (res['success'] == true && res['data'] is Map) {
        _overview = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = (res['message'] ?? 'تعذّر جلب الأرصدة').toString();
      }
    } catch (_) {
      _error = 'تعذّر جلب الأرصدة';
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (_error == null) _loadAllFtth();
  }

  List<Map<String, dynamic>> get _partners {
    final raw = _overview == null ? null : _f(_overview!, 'Partners');
    if (raw is! List) return const [];
    return [
      for (final p in raw)
        if (p is Map) Map<String, dynamic>.from(p)
    ];
  }

  Future<void> _loadAllFtth() async {
    // Sequential: each partner needs its own FTTH login, and hammering the
    // provider in parallel is neither needed nor polite.
    for (final p in _partners) {
      if (!mounted) return;
      if (_f(p, 'PartnerDeleted') == true) continue;
      await _loadFtthFor(p);
    }
  }

  Future<void> _loadFtthFor(Map<String, dynamic> partner) async {
    final partnerId = _f(partner, 'PartnerId')?.toString();
    final ftthId = _f(partner, 'PartnerAccountId')?.toString();
    if (partnerId == null || partnerId.isEmpty) return;
    if (!mounted) return;
    setState(() => _ftth[partnerId] = const _FtthBalanceState(loading: true));
    if (ftthId == null || ftthId.isEmpty) {
      if (mounted) {
        setState(() => _ftth[partnerId] = const _FtthBalanceState(
            loading: false, error: 'لا يوجد معرّف FTTH'));
      }
      return;
    }
    try {
      final loginRes =
          await LinkedAccountsService.instance.loginPartner(partnerId);
      if (!mounted) return;
      final data = loginRes['data'];
      final token = (loginRes['success'] == true && data is Map)
          ? (data['accessToken'] ?? data['AccessToken'])?.toString()
          : null;
      if (token == null || token.isEmpty) {
        setState(() => _ftth[partnerId] =
            const _FtthBalanceState(loading: false, error: 'تعذّر الدخول'));
        return;
      }
      final response = await AuthService.instance.authenticatedRequest(
        'GET',
        'https://api.ftth.iq/api/partners/$ftthId/wallets/balance',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (response.statusCode == 200) {
        final model =
            (jsonDecode(response.body)['model'] ?? {}) as Map<String, dynamic>;
        setState(() => _ftth[partnerId] = _FtthBalanceState(
            loading: false, balance: _num(model['balance'])));
      } else {
        setState(() => _ftth[partnerId] = _FtthBalanceState(
            loading: false, error: 'خطأ ${response.statusCode}'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _ftth[partnerId] =
            const _FtthBalanceState(loading: false, error: 'تعذّر الجلب'));
      }
    }
  }

  Future<void> _openFund(Map<String, dynamic> partner,
      {required bool fromGeneral, bool toGeneral = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FundDialog(
        partner: partner,
        overview: _overview!,
        fromGeneral: fromGeneral,
        toGeneral: toGeneral,
      ),
    );
    if (ok == true) _loadAll();
  }

  Future<void> _openStatement(Map<String, dynamic> partner) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _StatementDialog(partner: partner, canEdit: _canEdit),
    );
    if (changed == true) _loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Container(
        width: min(900, size.width * 0.95),
        constraints: BoxConstraints(maxHeight: size.height * 0.9),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, color: SdColors.danger),
                  const SizedBox(width: 8),
                  Text(_error!,
                      style: const TextStyle(
                          fontFamily: _cairo, color: SdColors.danger)),
                  const SizedBox(width: 12),
                  TextButton(
                      onPressed: _loadAll,
                      child: const Text('إعادة المحاولة',
                          style: TextStyle(fontFamily: _cairo))),
                ]),
              )
            else
              Flexible(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final general =
        _overview == null ? 0.0 : _num(_f(_overview!, 'GeneralBalance'));
    final partnersTotal =
        _overview == null ? 0.0 : _num(_f(_overview!, 'PartnersTotal'));
    return Row(children: [
      const Icon(Icons.account_balance_wallet_outlined,
          color: SdColors.primary, size: 22),
      const SizedBox(width: 8),
      const Text('أرصدة الشركاء',
          style: TextStyle(
              fontFamily: _cairo, fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(width: 16),
      if (!_loading && _error == null) ...[
        Flexible(child: _chip('الرصيد العام', general, SdColors.primary)),
        const SizedBox(width: 8),
        Flexible(child: _chip('مجموع الشركاء', partnersTotal, SdColors.info)),
      ],
      const Spacer(),
      IconButton(
        tooltip: 'تحديث',
        onPressed: _loading ? null : _loadAll,
        icon: const Icon(Icons.refresh, color: SdColors.faint),
      ),
      IconButton(
        tooltip: 'إغلاق',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close, color: SdColors.faint),
      ),
    ]);
  }

  Widget _chip(String label, double value, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label: ',
              style: const TextStyle(
                  fontFamily: _cairo, fontSize: 11, color: Colors.black54)),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_fmt(value),
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontFamily: _cairo,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: value < 0 ? SdColors.danger : Colors.black87)),
            ),
          ),
        ]),
      );

  Widget _body() {
    final partners = _partners;
    if (partners.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: Text('لا يوجد شركاء',
                style: TextStyle(fontFamily: _cairo, color: SdColors.faint))),
      );
    }
    return SingleChildScrollView(
      child: Column(
        children: [
          _rowHeader(),
          const Divider(height: 1),
          for (final p in partners) _partnerRow(p),
        ],
      ),
    );
  }

  static const _wName = 3;
  static const _wNum = 2;
  static const _wActions = 2;

  Widget _rowHeader() {
    const st = TextStyle(
        fontFamily: _cairo,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Colors.black54);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(children: [
        Expanded(flex: _wName, child: Text('الشريك', style: st)),
        Expanded(
            flex: _wNum,
            child: Text('خادمنا', style: st, textAlign: TextAlign.center)),
        Expanded(
            flex: _wNum,
            child: Text('صفحة الشريك', style: st, textAlign: TextAlign.center)),
        Expanded(
            flex: _wNum,
            child: Text('الفرق', style: st, textAlign: TextAlign.center)),
        Expanded(
            flex: _wActions,
            child: Text('إجراءات', style: st, textAlign: TextAlign.center)),
      ]),
    );
  }

  Widget _partnerRow(Map<String, dynamic> p) {
    final partnerId = _f(p, 'PartnerId')?.toString();
    final deleted = _f(p, 'PartnerDeleted') == true;
    final name = (_f(p, 'Name') ?? '').toString();
    final ourBalance = _num(_f(p, 'Balance'));
    final ftth = partnerId == null ? null : _ftth[partnerId];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x11000000))),
      ),
      child: Row(children: [
        Expanded(
          flex: _wName,
          child: Row(children: [
            Icon(deleted ? Icons.undo : Icons.business,
                size: 15, color: deleted ? SdColors.danger : SdColors.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(deleted ? '$name (محذوف)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: _cairo, fontSize: 12)),
            ),
          ]),
        ),
        Expanded(flex: _wNum, child: _money(ourBalance)),
        Expanded(flex: _wNum, child: _ftthCell(deleted, ftth)),
        Expanded(flex: _wNum, child: _diffCell(ourBalance, deleted, ftth)),
        Expanded(flex: _wActions, child: _actions(p, deleted)),
      ]),
    );
  }

  Widget _money(double v, {Color? color}) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          _fmt(v),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: _cairo,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color ?? (v < 0 ? SdColors.danger : Colors.black87)),
        ),
      );

  Widget _ftthCell(bool deleted, _FtthBalanceState? ftth) {
    if (deleted) {
      return const Text('—',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: _cairo, color: SdColors.faint));
    }
    if (ftth == null || ftth.loading) {
      return const Center(
          child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (ftth.error != null) {
      return Text(ftth.error!,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              fontFamily: _cairo, fontSize: 11, color: SdColors.danger));
    }
    return _money(ftth.balance ?? 0);
  }

  Widget _diffCell(double ourBalance, bool deleted, _FtthBalanceState? ftth) {
    if (deleted ||
        ftth == null ||
        ftth.loading ||
        ftth.error != null ||
        ftth.balance == null) {
      return const Text('—',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: _cairo, color: SdColors.faint));
    }
    final diff = ourBalance - ftth.balance!;
    if (diff.abs() < 0.5) {
      return const Icon(Icons.check_circle, size: 16, color: SdColors.success);
    }
    return _money(diff, color: SdColors.warning);
  }

  Widget _actions(Map<String, dynamic> p, bool deleted) {
    return PopupMenuButton<String>(
      tooltip: 'إجراءات',
      iconSize: 18,
      icon: const Icon(Icons.more_horiz, size: 18, color: SdColors.faint),
      onSelected: (v) {
        switch (v) {
          case 'topup':
            _openFund(p, fromGeneral: false);
            break;
          case 'fromGeneral':
            _openFund(p, fromGeneral: true);
            break;
          case 'toGeneral':
            _openFund(p, fromGeneral: false, toGeneral: true);
            break;
          case 'statement':
            _openStatement(p);
            break;
          case 'refreshFtth':
            _loadFtthFor(p);
            break;
        }
      },
      itemBuilder: (_) => [
        if (_canEdit && !deleted)
          _menuItem('topup', 'شحن', Icons.add_card, SdColors.success),
        if (_canEdit && !deleted)
          _menuItem('fromGeneral', 'تحويل من الرصيد العام', Icons.swap_horiz,
              SdColors.info),
        if (_canEdit)
          _menuItem('toGeneral', 'إرجاع إلى الرصيد العام', Icons.undo,
              SdColors.danger),
        if (!deleted)
          _menuItem('statement', 'كشف الحساب', Icons.receipt_long,
              SdColors.primary),
        if (!deleted)
          _menuItem('refreshFtth', 'تحديث صفحة الشريك', Icons.refresh,
              SdColors.faint),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
          String value, String label, IconData icon, Color color) =>
      PopupMenuItem<String>(
        value: value,
        height: 38,
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontFamily: _cairo, fontSize: 12)),
        ]),
      );
}
