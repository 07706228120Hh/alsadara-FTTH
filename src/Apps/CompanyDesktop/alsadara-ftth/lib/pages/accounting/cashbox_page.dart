import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';

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
      _errorMessage = 'خطأ في الاتصال: $e';
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
                                size: 48),
                            const SizedBox(height: 12),
                            Text(_errorMessage!,
                                style: GoogleFonts.cairo(
                                    color: AccountingTheme.textSecondary,
                                    fontSize: 14)),
                          ],
                        ))
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonGreenGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('الصناديق النقدية',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonPink.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_cashBoxes.length}',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonPink,
                )),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _showAddDialog,
            icon: const Icon(Icons.add, size: 16),
            label: Text('إضافة صندوق', style: GoogleFonts.cairo(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
      padding: const EdgeInsets.all(8),
      itemCount: _cashBoxes.length,
      itemBuilder: (_, i) {
        final box = _cashBoxes[i];
        final isSelected = _selectedBox?['Id'] == box['Id'];
        final balance = box['CurrentBalance'] ?? 0;
        final type = box['CashBoxType'] ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AccountingTheme.accent.withValues(alpha: 0.2)
                : AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
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
                  fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatNumber(balance),
                  style: TextStyle(
                    color: (balance is num && balance > 0)
                        ? AccountingTheme.success
                        : AccountingTheme.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _showEditCashBoxDialog(box),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AccountingTheme.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.edit,
                        color: AccountingTheme.info, size: 14),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _confirmDeleteCashBox(box),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AccountingTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: AccountingTheme.danger, size: 14),
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              color: AccountingTheme.textMuted, size: 64),
          SizedBox(height: 16),
          Text('اختر صندوقاً لعرض تفاصيله',
              style: TextStyle(color: AccountingTheme.textMuted, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildBoxDetail() {
    final box = _selectedBox!;
    return Column(
      children: [
        // بطاقة معلومات الصندوق
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AccountingTheme.accent.withValues(alpha: 0.12),
                AccountingTheme.accent.withValues(alpha: 0.03)
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AccountingTheme.accent.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  color: AccountingTheme.accent, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      box['Name'] ?? '',
                      style: const TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontSize: 20,
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
                  const Text('الرصيد الحالي',
                      style: TextStyle(
                          color: AccountingTheme.textMuted, fontSize: 12)),
                  Text(
                    '${_formatNumber(box['CurrentBalance'])} د.ع',
                    style: const TextStyle(
                        color: AccountingTheme.accent,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // أزرار إيداع/سحب
              Column(
                children: [
                  _actionButton('إيداع', Icons.add, AccountingTheme.success,
                      () => _showTransactionDialog(true)),
                  const SizedBox(height: 8),
                  _actionButton('سحب', Icons.remove, AccountingTheme.danger,
                      () => _showTransactionDialog(false)),
                ],
              ),
            ],
          ),
        ),
        // قائمة المعاملات
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('المعاملات',
                  style: TextStyle(
                      color: AccountingTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${_transactions.length} معاملة',
                  style: const TextStyle(
                      color: AccountingTheme.textMuted, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _transactions.length,
                      itemBuilder: (_, i) {
                        final t = _transactions[i];
                        final type = t['TransactionType'] ?? '';
                        final isDeposit =
                            type == 'Deposit' || type == 'TransferIn';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.all(12),
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
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t['Description'] ?? '',
                                      style: const TextStyle(
                                          color: AccountingTheme.textPrimary,
                                          fontSize: 13),
                                    ),
                                    Text(
                                      _formatDate(t['CreatedAt']),
                                      style: const TextStyle(
                                          color: AccountingTheme.textMuted,
                                          fontSize: 11),
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
                              const SizedBox(width: 12),
                              Text(
                                'رصيد: ${_formatNumber(t['BalanceAfter'])}',
                                style: const TextStyle(
                                    color: AccountingTheme.textMuted,
                                    fontSize: 11),
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
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.15),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
            title: const Text('إضافة صندوق',
                style: TextStyle(color: AccountingTheme.textPrimary)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _textField('اسم الصندوق', nameCtrl),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
                  _textField('الرصيد الأولي', balanceCtrl, isNumber: true),
                  const SizedBox(height: 12),
                  _textField('ملاحظات', notesCtrl),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
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
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _textField('المبلغ', amountCtrl, isNumber: true),
                const SizedBox(height: 12),
                _textField('الوصف', descCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
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
          title: const Text('تعديل الصندوق',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: AccountingTheme.textPrimary),
                    decoration: _inputDeco('اسم الصندوق')),
                const SizedBox(height: 10),
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
              child: const Text('إلغاء',
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
          title: const Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'هل تريد حذف الصندوق "${box['Name']}"?\nيجب أن يكون الرصيد صفراً.',
            style: const TextStyle(color: AccountingTheme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء',
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

  String _formatNumber(dynamic value) {
    if (value == null || value == 0) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString());
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return date.toString();
    }
  }
}
