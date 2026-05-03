import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show NumberFormat;
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../utils/responsive_helper.dart';

/// صفحة إدارة الصناديق النقدية
class CashBoxPage extends StatefulWidget {
  final String? companyId;

  const CashBoxPage({super.key, this.companyId});

  @override
  State<CashBoxPage> createState() => _CashBoxPageState();
}

class _CashBoxPageState extends State<CashBoxPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _cashBoxes = [];
  Map<String, dynamic>? _selectedBox;
  List<dynamic> _transactions = [];
  bool _loadingTransactions = false;

  final _boxTypes = {
    'Main': 'صندوق رئيسي',
    'PettyCash': 'نثرية',
    'Bank': 'بنك'
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await AccountingService.instance
          .getCashBoxes(companyId: widget.companyId);
      if (result['success'] == true) {
        _cashBoxes = (result['data'] is List) ? result['data'] : [];
      } else {
        _errorMessage = result['message'] ?? 'خطأ';
      }
    } catch (e) {
      _errorMessage = 'خطأ في الاتصال';
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadTransactions(String cashBoxId) async {
    setState(() {
      _loadingTransactions = true;
    });
    try {
      final result =
          await AccountingService.instance.getCashBoxTransactions(cashBoxId);
      if (result['success'] == true) {
        _transactions = (result['data'] is List) ? result['data'] : [];
      }
    } catch (_) {}
    setState(() {
      _loadingTransactions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AccountingTheme.neonGreen))
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color:
                                    AccountingTheme.textMuted.withOpacity(0.3),
                                size: context.accR.iconXL),
                            SizedBox(height: context.accR.spaceM),
                            Text(_errorMessage!,
                                style: GoogleFonts.cairo(
                                    color: AccountingTheme.textSecondary,
                                    fontSize: context.accR.body)),
                          ],
                        ))
                      : context.responsive.isMobile
                          ? (_selectedBox != null
                              ? _buildBoxDetail()
                              : _buildBoxesList())
                          : Row(
                              children: [
                                SizedBox(
                                  width: 320,
                                  child: _buildBoxesList(),
                                ),
                                VerticalDivider(
                                    width: 1, color: AccountingTheme.borderColor),
                                Expanded(
                                    child: _selectedBox != null
                                        ? _buildBoxDetail()
                                        : _buildEmptyState()),
                              ],
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final ar = context.accR;
    final isMobile = context.responsive.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : ar.spaceXL,
          vertical: isMobile ? 6 : ar.spaceL),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (isMobile && _selectedBox != null) {
                setState(() => _selectedBox = null);
              } else {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: isMobile && _selectedBox != null ? 'رجوع للقائمة' : 'رجوع',
            iconSize: isMobile ? 20 : 24,
            constraints: isMobile ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
            padding: isMobile ? EdgeInsets.zero : null,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMobile ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonGreenGradient,
              borderRadius: BorderRadius.circular(ar.btnRadius),
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: isMobile ? 18 : ar.iconM),
          ),
          SizedBox(width: isMobile ? 6 : ar.spaceM),
          Expanded(
            child: Text('الصناديق النقدية',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : ar.headingMedium,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary,
                )),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: ar.spaceS, vertical: 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonPink.withOpacity(0.2),
              borderRadius: BorderRadius.circular(ar.cardRadius),
            ),
            child: Text('${_cashBoxes.length}',
                style: GoogleFonts.cairo(
                  fontSize: ar.small,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonPink,
                )),
          ),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh, size: isMobile ? 18 : ar.iconM),
            tooltip: 'تحديث',
            constraints: isMobile ? const BoxConstraints(minWidth: 32, minHeight: 32) : null,
            padding: isMobile ? EdgeInsets.zero : null,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMobile ? 4 : ar.spaceXS),
          ElevatedButton.icon(
            onPressed: _showAddDialog,
            icon: Icon(Icons.add, size: isMobile ? 16 : ar.iconS),
            label: Text(isMobile ? 'إضافة' : 'إضافة صندوق',
                style: GoogleFonts.cairo(fontSize: isMobile ? 11 : ar.buttonText)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonGreen,
              foregroundColor: Colors.white,
              padding: isMobile
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                  : ar.buttonPadding,
              minimumSize: isMobile ? const Size(0, 30) : null,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ar.btnRadius)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoxesList() {
    if (_cashBoxes.isEmpty) {
      return const Center(
        child: Text('لا توجد صناديق',
            style: TextStyle(color: AccountingTheme.textMuted)),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.all(context.accR.spaceS),
      itemCount: _cashBoxes.length,
      itemBuilder: (_, i) {
        final box = _cashBoxes[i];
        final isSelected = _selectedBox?['Id'] == box['Id'];
        final balance = box['CurrentBalance'] ?? 0;
        final type = box['CashBoxType'] ?? '';

        return Container(
          margin: EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AccountingTheme.accent.withValues(alpha: 0.2)
                : AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(context.accR.cardRadius),
            border: isSelected
                ? Border.all(color: AccountingTheme.accent, width: 1.5)
                : null,
          ),
          child: ListTile(
            leading: Icon(
              type == 'Bank'
                  ? Icons.account_balance
                  : Icons.account_balance_wallet,
              color: isSelected
                  ? AccountingTheme.accent
                  : AccountingTheme.textMuted,
            ),
            title: Text(
              box['Name'] ?? '',
              style: TextStyle(
                color: isSelected
                    ? AccountingTheme.accent
                    : AccountingTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              _boxTypes[type] ?? type,
              style: TextStyle(
                  color: AccountingTheme.textMuted.withValues(alpha: 0.5),
                  fontSize: context.accR.small),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatNumber(balance),
                  style: TextStyle(
                    color: (balance is num && balance < 0)
                        ? Colors.red
                        : (balance is num && balance > 0)
                            ? AccountingTheme.success
                            : AccountingTheme.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: context.accR.body,
                  ),
                ),
                SizedBox(width: context.accR.spaceS),
                InkWell(
                  onTap: () => _showEditCashBoxDialog(box),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: EdgeInsets.all(context.accR.spaceXS),
                    decoration: BoxDecoration(
                      color: AccountingTheme.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.edit,
                        color: AccountingTheme.info, size: context.accR.iconXS),
                  ),
                ),
                SizedBox(width: context.accR.spaceXS),
                InkWell(
                  onTap: () => _confirmDeleteCashBox(box),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: EdgeInsets.all(context.accR.spaceXS),
                    decoration: BoxDecoration(
                      color: AccountingTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.delete_outline,
                        color: AccountingTheme.danger,
                        size: context.accR.iconXS),
                  ),
                ),
              ],
            ),
            onTap: () {
              setState(() {
                _selectedBox = box;
              });
              _loadTransactions(box['Id']);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              color: AccountingTheme.textMuted, size: context.accR.iconEmpty),
          SizedBox(height: context.accR.spaceXL),
          Text('اختر صندوقاً لعرض تفاصيله',
              style: TextStyle(
                  color: AccountingTheme.textMuted,
                  fontSize: context.accR.headingSmall)),
        ],
      ),
    );
  }

  Widget _buildBoxDetail() {
    final box = _selectedBox!;
    final isMobile = context.responsive.isMobile;
    return Column(
      children: [
        // بطاقة معلومات الصندوق
        Container(
          margin: EdgeInsets.all(isMobile ? 8 : context.accR.spaceXL),
          padding: EdgeInsets.all(isMobile ? 10 : context.accR.spaceXL),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AccountingTheme.accent.withValues(alpha: 0.12),
                AccountingTheme.accent.withValues(alpha: 0.03)
              ],
            ),
            borderRadius: BorderRadius.circular(context.accR.cardRadius),
            border: Border.all(
                color: AccountingTheme.accent.withValues(alpha: 0.5)),
          ),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_wallet,
                            color: AccountingTheme.accent, size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            box['Name'] ?? '',
                            style: TextStyle(
                                color: AccountingTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _boxTypes[box['CashBoxType']] ?? '',
                          style: TextStyle(
                              color: AccountingTheme.textSecondary
                                  .withValues(alpha: 0.5),
                              fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        '${_formatNumber(box['CurrentBalance'])} د.ع',
                        style: TextStyle(
                            color: AccountingTheme.accent,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _actionButton('إيداع', Icons.add, AccountingTheme.success,
                              () => _showTransactionDialog(true)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _actionButton('سحب', Icons.remove, AccountingTheme.danger,
                              () => _showTransactionDialog(false)),
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
            children: [
              Icon(Icons.account_balance_wallet,
                  color: AccountingTheme.accent, size: context.accR.iconXL),
              SizedBox(width: context.accR.spaceXL),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      box['Name'] ?? '',
                      style: TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontSize: context.accR.headingMedium,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _boxTypes[box['CashBoxType']] ?? '',
                      style: TextStyle(
                          color: AccountingTheme.textSecondary
                              .withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('الرصيد الحالي',
                      style: TextStyle(
                          color: AccountingTheme.textMuted,
                          fontSize: context.accR.small)),
                  Text(
                    '${_formatNumber(box['CurrentBalance'])} د.ع',
                    style: TextStyle(
                        color: AccountingTheme.accent,
                        fontSize: context.accR.financialLarge,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              SizedBox(width: context.accR.spaceXL),
              // أزرار إيداع/سحب
              Column(
                children: [
                  _actionButton('إيداع', Icons.add, AccountingTheme.success,
                      () => _showTransactionDialog(true)),
                  SizedBox(height: context.accR.spaceS),
                  _actionButton('سحب', Icons.remove, AccountingTheme.danger,
                      () => _showTransactionDialog(false)),
                ],
              ),
            ],
          ),
        ),
        // قائمة المعاملات
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.accR.paddingH),
          child: Row(
            children: [
              Text('المعاملات',
                  style: TextStyle(
                      color: AccountingTheme.textPrimary,
                      fontSize: context.accR.headingSmall,
                      fontWeight: FontWeight.bold)),
              Spacer(),
              Text('${_transactions.length} معاملة',
                  style: TextStyle(
                      color: AccountingTheme.textMuted,
                      fontSize: context.accR.small)),
            ],
          ),
        ),
        SizedBox(height: context.accR.spaceS),
        Expanded(
          child: _loadingTransactions
              ? const Center(
                  child:
                      CircularProgressIndicator(color: AccountingTheme.accent))
              : _transactions.isEmpty
                  ? const Center(
                      child: Text('لا توجد معاملات',
                          style: TextStyle(color: AccountingTheme.textMuted)))
                  : ListView.builder(
                      padding: EdgeInsets.symmetric(
                          horizontal: context.accR.paddingH),
                      itemCount: _transactions.length,
                      itemBuilder: (_, i) {
                        final t = _transactions[i];
                        final type = t['TransactionType'] ?? '';
                        final isDeposit =
                            type == 'Deposit' || type == 'TransferIn';
                        return Container(
                          margin: EdgeInsets.only(bottom: 4),
                          padding: EdgeInsets.all(context.accR.spaceM),
                          decoration: BoxDecoration(
                            color: AccountingTheme.bgCard,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isDeposit
                                    ? Icons.arrow_downward
                                    : Icons.arrow_upward,
                                color: isDeposit
                                    ? AccountingTheme.success
                                    : AccountingTheme.danger,
                                size: context.accR.iconM,
                              ),
                              SizedBox(width: context.accR.spaceM),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t['Description'] ?? '',
                                      style: TextStyle(
                                          color: AccountingTheme.textPrimary,
                                          fontSize:
                                              context.accR.financialSmall),
                                    ),
                                    Text(
                                      _formatDate(t['CreatedAt']),
                                      style: TextStyle(
                                          color: AccountingTheme.textMuted,
                                          fontSize: context.accR.small),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${isDeposit ? '+' : '-'} ${_formatNumber(t['Amount'])}',
                                style: TextStyle(
                                  color: isDeposit
                                      ? AccountingTheme.accent
                                      : AccountingTheme.danger,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: context.accR.spaceM),
                              Text(
                                'رصيد: ${_formatNumber(t['BalanceAfter'])}',
                                style: TextStyle(
                                    color: AccountingTheme.textMuted,
                                    fontSize: context.accR.small),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _actionButton(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return SizedBox(
      width: 100,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: context.accR.iconS),
        label: Text(label, style: TextStyle(fontSize: context.accR.small)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          padding: EdgeInsets.symmetric(
              horizontal: context.accR.spaceS, vertical: context.accR.spaceXS),
        ),
      ),
    );
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController();
    String boxType = 'Main';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Text('إضافة صندوق',
                style: TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: context.accR.isMobile
                  ? MediaQuery.of(context).size.width * 0.85
                  : 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _textField('اسم الصندوق', nameCtrl),
                  SizedBox(height: context.accR.spaceM),
                  DropdownButtonFormField<String>(
                    value: boxType,
                    dropdownColor: AccountingTheme.bgCard,
                    style: const TextStyle(color: AccountingTheme.textPrimary),
                    items: _boxTypes.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => ss(() => boxType = v ?? 'Main'),
                    decoration: _inputDeco('النوع'),
                  ),
                  SizedBox(height: context.accR.spaceM),
                  _textField('الرصيد الأولي', balanceCtrl, isNumber: true),
                  SizedBox(height: context.accR.spaceM),
                  _textField('ملاحظات', notesCtrl),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.neonGreen,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  Navigator.pop(ctx);
                  final result = await AccountingService.instance.createCashBox(
                    name: nameCtrl.text,
                    cashBoxType: boxType,
                    initialBalance: double.tryParse(balanceCtrl.text) ?? 0,
                    notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    companyId: widget.companyId ?? '',
                  );
                  if (result['success'] == true) {
                    _snack('تم إنشاء الصندوق', AccountingTheme.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                  }
                },
                child: const Text('إنشاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionDialog(bool isDeposit) {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text(
            isDeposit ? 'إيداع' : 'سحب',
            style: TextStyle(
                color: isDeposit
                    ? AccountingTheme.success
                    : AccountingTheme.danger),
          ),
          content: SizedBox(
            width: min(350, MediaQuery.of(context).size.width * 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _textField('المبلغ', amountCtrl, isNumber: true),
                SizedBox(height: context.accR.spaceM),
                _textField('الوصف', descCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDeposit
                    ? AccountingTheme.success
                    : AccountingTheme.danger,
              ),
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0 || descCtrl.text.isEmpty) {
                  _snack('الرجاء ملء جميع الحقول', AccountingTheme.warning);
                  return;
                }
                Navigator.pop(ctx);
                final fn = isDeposit
                    ? AccountingService.instance.depositToCashBox
                    : AccountingService.instance.withdrawFromCashBox;
                final result = await fn(
                  _selectedBox!['Id'],
                  amount: amount,
                  description: descCtrl.text,
                );
                if (result['success'] == true) {
                  _snack(isDeposit ? 'تم الإيداع' : 'تم السحب',
                      AccountingTheme.success);
                  _loadData();
                  _loadTransactions(_selectedBox!['Id']);
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                }
              },
              child: Text(isDeposit ? 'إيداع' : 'سحب'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField(String label, TextEditingController ctrl,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: _inputDeco(label),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AccountingTheme.textMuted),
      filled: true,
      fillColor: AccountingTheme.bgCardHover,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    );
  }

  void _showEditCashBoxDialog(Map<String, dynamic> box) {
    final nameCtrl = TextEditingController(text: box['Name'] ?? '');
    final notesCtrl = TextEditingController(text: box['Notes'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تعديل الصندوق',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: SizedBox(
            width: context.accR.dialogSmallW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    style: TextStyle(color: AccountingTheme.textPrimary),
                    decoration: _inputDeco('اسم الصندوق')),
                SizedBox(height: context.accR.spaceM),
                TextField(
                    controller: notesCtrl,
                    style: const TextStyle(color: AccountingTheme.textPrimary),
                    decoration: _inputDeco('ملاحظات')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.info,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance.updateCashBox(
                  box['Id'].toString(),
                  {
                    'Name': nameCtrl.text,
                    'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                  },
                );
                if (result['success'] == true) {
                  _snack('تم تحديث الصندوق', AccountingTheme.success);
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCashBox(Map<String, dynamic> box) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'هل تريد حذف الصندوق "${box['Name']}"?\nيجب أن يكون الرصيد صفراً.',
            style: const TextStyle(color: AccountingTheme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance
                    .deleteCashBox(box['Id'].toString());
                if (result['success'] == true) {
                  _snack('تم حذف الصندوق', AccountingTheme.success);
                  setState(() => _selectedBox = null);
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                }
              },
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  static final _numFmt = NumberFormat('#,##0', 'ar');
  String _formatNumber(dynamic value) {
    if (value == null || value == 0) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return _numFmt.format(n);
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString()).toLocal();
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return date.toString();
    }
  }
}
