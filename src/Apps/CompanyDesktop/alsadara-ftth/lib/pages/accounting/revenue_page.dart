import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';

/// صفحة الإيرادات - Revenue Page
class RevenuePage extends StatefulWidget {
  final String? companyId;

  const RevenuePage({super.key, this.companyId});

  @override
  State<RevenuePage> createState() => _RevenuePageState();
}

class _RevenuePageState extends State<RevenuePage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _revenueAccounts = [];
  List<dynamic> _allAccounts = [];
  List<dynamic> _revenueEntries = [];

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
      // جلب الحسابات وتصفية حسابات الإيرادات
      final accountsResult = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (accountsResult['success'] == true) {
        _allAccounts = (accountsResult['data'] as List?) ?? [];
        _revenueAccounts = _allAccounts
            .where((a) =>
                a['AccountType']?.toString() == 'Revenue' ||
                a['Type']?.toString() == 'Revenue' ||
                (a['Code']?.toString() ?? '').startsWith('4'))
            .toList();
        // استبعاد الحسابات الأب (غير النهائية) لتجنب الحساب المزدوج
        _revenueAccounts =
            _revenueAccounts.where((a) => a['IsLeaf'] == true).toList();
        // ترتيب حسب الكود
        _revenueAccounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
      }

      // جلب القيود المحاسبية
      final entriesResult = await AccountingService.instance
          .getJournalEntries(companyId: widget.companyId);
      if (entriesResult['success'] == true) {
        final allEntries = (entriesResult['data'] as List?) ?? [];
        // تصفية القيود التي تحتوي على حسابات إيرادات
        final revenueAccountIds = _revenueAccounts
            .map((a) => a['Id']?.toString())
            .where((id) => id != null)
            .toSet();

        _revenueEntries = allEntries.where((entry) {
          final lines = entry['Lines'] as List? ?? [];
          return lines.any((line) =>
              revenueAccountIds.contains(line['AccountId']?.toString()));
        }).toList();
      }
    } catch (e) {
      _errorMessage = 'خطأ في الاتصال: $e';
    }
    setState(() => _isLoading = false);
  }

  double get _totalRevenue {
    double total = 0;
    for (final acc in _revenueAccounts) {
      total +=
          ((acc['Balance'] ?? acc['CurrentBalance'] ?? 0) as num).toDouble();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: Column(
          children: [
            _buildPageToolbar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AccountingTheme.neonGreen))
                  : _errorMessage != null
                      ? Center(
                          child: Text(_errorMessage!,
                              style: const TextStyle(
                                  color: AccountingTheme.danger)))
                      : Column(
                          children: [
                            _buildSummary(),
                            _buildRevenueAccountsBar(),
                            Expanded(child: _buildEntriesList()),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
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
            child: const Icon(Icons.trending_up_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('الإيرادات',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showAddRevenueDialog,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة إيراد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final subCount = _revenueAccounts
        .where((a) =>
            a['Code']?.toString() == '4100' ||
            (a['Code']?.toString() ?? '').startsWith('41'))
        .fold<double>(
            0,
            (s, a) =>
                s +
                ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble());
    final installCount = _revenueAccounts
        .where((a) =>
            a['Code']?.toString() == '4200' ||
            (a['Code']?.toString() ?? '').startsWith('42'))
        .fold<double>(
            0,
            (s, a) =>
                s +
                ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble());
    final maintCount = _revenueAccounts
        .where((a) =>
            a['Code']?.toString() == '4300' ||
            (a['Code']?.toString() ?? '').startsWith('43'))
        .fold<double>(
            0,
            (s, a) =>
                s +
                ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble());
    final otherCount = _totalRevenue - subCount - installCount - maintCount;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _summaryChip('إجمالي الإيرادات', '${_fmt(_totalRevenue)} د.ع',
              AccountingTheme.success),
          _summaryChip(
              'اشتراكات', '${_fmt(subCount)} د.ع', AccountingTheme.info),
          _summaryChip(
              'تركيب', '${_fmt(installCount)} د.ع', AccountingTheme.neonGreen),
          _summaryChip(
              'صيانة', '${_fmt(maintCount)} د.ع', AccountingTheme.warning),
          _summaryChip(
              'أخرى', '${_fmt(otherCount)} د.ع', const Color(0xFF8B5CF6)),
          _summaryChip('عدد القيود', '${_revenueEntries.length}',
              AccountingTheme.accent),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style:
                  TextStyle(color: color.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildRevenueAccountsBar() {
    if (_revenueAccounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('لا توجد حسابات إيرادات',
            style: TextStyle(color: AccountingTheme.textMuted)),
      );
    }

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _revenueAccounts.length,
        itemBuilder: (_, i) {
          final acc = _revenueAccounts[i];
          final balance =
              ((acc['Balance'] ?? acc['CurrentBalance'] ?? 0) as num)
                  .toDouble();
          return Container(
            margin: const EdgeInsets.only(left: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AccountingTheme.success.withValues(alpha: 0.12),
                  AccountingTheme.success.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AccountingTheme.success.withValues(alpha: 0.25)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${acc['Code']} - ${acc['Name']}',
                  style: const TextStyle(
                      color: AccountingTheme.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_fmt(balance)} د.ع',
                  style: TextStyle(
                    color: balance > 0
                        ? AccountingTheme.neonGreen
                        : AccountingTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEntriesList() {
    if (_revenueEntries.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, color: AccountingTheme.textMuted, size: 64),
            SizedBox(height: 16),
            Text('لا توجد قيود إيرادات',
                style: TextStyle(
                    color: AccountingTheme.textSecondary, fontSize: 16)),
            SizedBox(height: 8),
            Text('اضغط + لإضافة إيراد جديد',
                style:
                    TextStyle(color: AccountingTheme.textMuted, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _revenueEntries.length,
      itemBuilder: (_, i) {
        final entry = _revenueEntries[i];
        final lines = entry['Lines'] as List? ?? [];
        final status = entry['Status']?.toString() ?? 'Draft';
        final statusInfo = _statusInfo(status);
        final totalDebit = (entry['TotalDebit'] ?? 0 as num).toDouble();

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border(
                right:
                    BorderSide(color: statusInfo['color'] as Color, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AccountingTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      entry['EntryNumber'] ?? '',
                      style: const TextStyle(
                          color: AccountingTheme.success,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry['Description'] ?? '',
                      style: const TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ),
                  // الحالة
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (statusInfo['color'] as Color)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusInfo['label'] as String,
                      style: TextStyle(
                          color: statusInfo['color'] as Color, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_fmt(totalDebit)} د.ع',
                    style: TextStyle(
                      color: AccountingTheme.neonGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...lines.take(4).map((line) {
                  final accName =
                      line['AccountName'] ?? line['AccountCode'] ?? '';
                  final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
                  final credit =
                      ((line['CreditAmount'] ?? 0) as num).toDouble();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(
                          credit > 0 ? Icons.arrow_back : Icons.arrow_forward,
                          color: credit > 0
                              ? AccountingTheme.accent
                              : AccountingTheme.info,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            accName.toString(),
                            style: const TextStyle(
                                color: AccountingTheme.textMuted, fontSize: 12),
                          ),
                        ),
                        if (debit > 0)
                          Text('مدين: ${_fmt(debit)}',
                              style: const TextStyle(
                                  color: AccountingTheme.info, fontSize: 11)),
                        if (credit > 0)
                          Text('دائن: ${_fmt(credit)}',
                              style: const TextStyle(
                                  color: AccountingTheme.accent, fontSize: 11)),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time,
                      color: AccountingTheme.textMuted, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(entry['EntryDate'] ?? entry['CreatedAt']),
                    style: const TextStyle(
                        color: AccountingTheme.textMuted, fontSize: 11),
                  ),
                  if (entry['Notes'] != null &&
                      entry['Notes'].toString().isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Tooltip(
                      message: entry['Notes'].toString(),
                      child: const Icon(Icons.notes,
                          color: AccountingTheme.textMuted, size: 14),
                    ),
                  ],
                  const Spacer(),
                  _actionBtn(Icons.edit, AccountingTheme.info,
                      () => _showEditRevenueDialog(entry)),
                  const SizedBox(width: 4),
                  _actionBtn(Icons.delete_outline, AccountingTheme.danger,
                      () => _confirmDeleteRevenue(entry)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }

  void _showEditRevenueDialog(Map<String, dynamic> entry) async {
    if (_allAccounts.isEmpty) {
      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (result['success'] == true) {
        _allAccounts = (result['data'] as List?) ?? [];
      }
    }

    final lines = entry['Lines'] as List? ?? [];
    final description = entry['Description'] ?? '';
    final notes = entry['Notes'] ?? '';
    final entryId = entry['Id']?.toString();
    if (entryId == null) return;

    // استخراج حساب الإيراد (الدائن) وحساب الأصل (المدين) من سطور القيد
    String? revenueAccId;
    String? assetAccId;
    double amount = 0;
    for (final line in lines) {
      final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();
      final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
      if (credit > 0) {
        revenueAccId = line['AccountId']?.toString();
        amount = credit;
      } else if (debit > 0) {
        assetAccId = line['AccountId']?.toString();
        if (amount == 0) amount = debit;
      }
    }

    final revenueAccounts = _allAccounts
        .where((a) =>
            a['AccountType']?.toString() == 'Revenue' ||
            a['Type']?.toString() == 'Revenue' ||
            (a['Code']?.toString() ?? '').startsWith('4'))
        .where((a) => a['IsLeaf'] == true)
        .toList();

    final assetAccounts = _allAccounts
        .where((a) =>
            a['AccountType']?.toString() == 'Assets' ||
            a['Type']?.toString() == 'Assets' ||
            (a['Code']?.toString() ?? '').startsWith('1'))
        .where((a) => a['IsLeaf'] == true)
        .toList();

    // التأكد من أن القيم الحالية موجودة في القوائم
    if (revenueAccId != null &&
        !revenueAccounts.any((a) => a['Id']?.toString() == revenueAccId)) {
      revenueAccId = revenueAccounts.isNotEmpty
          ? revenueAccounts.first['Id']?.toString()
          : null;
    }
    if (assetAccId != null &&
        !assetAccounts.any((a) => a['Id']?.toString() == assetAccId)) {
      assetAccId = assetAccounts.isNotEmpty
          ? assetAccounts.first['Id']?.toString()
          : null;
    }

    if (!mounted) return;

    final descCtrl = TextEditingController(text: description);
    final amountCtrl = TextEditingController(
        text: amount > 0 ? amount.toStringAsFixed(0) : '');
    final notesCtrl = TextEditingController(text: notes);
    String? selectedRevenueAccId = revenueAccId;
    String? selectedAssetAccId = assetAccId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: const Text('تعديل الإيراد',
                style: TextStyle(
                    color: AccountingTheme.info, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field('الوصف *', descCtrl),
                    const SizedBox(height: 12),
                    _field('المبلغ *', amountCtrl, isNumber: true),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedRevenueAccId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: revenueAccounts.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Code']} - ${a['Name']}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedRevenueAccId = v),
                      decoration: _inputDeco('حساب الإيراد (دائن)'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedAssetAccId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: assetAccounts.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Code']} - ${a['Name']}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedAssetAccId = v),
                      decoration: _inputDeco('حساب القبض (مدين)'),
                    ),
                    const SizedBox(height: 12),
                    _field('ملاحظات', notesCtrl),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء',
                      style: TextStyle(color: AccountingTheme.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.info,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  final newAmount = double.tryParse(amountCtrl.text) ?? 0;
                  if (descCtrl.text.isEmpty || newAmount <= 0) {
                    _snack('الرجاء ملء الوصف والمبلغ', AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);

                  final result = await AccountingService.instance
                      .updateJournalEntry(entryId, {
                    'Description': descCtrl.text,
                    'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    'Lines': [
                      {
                        'AccountId': selectedAssetAccId,
                        'DebitAmount': newAmount,
                        'CreditAmount': 0,
                        'Description': 'قبض إيراد: ${descCtrl.text}',
                      },
                      {
                        'AccountId': selectedRevenueAccId,
                        'DebitAmount': 0,
                        'CreditAmount': newAmount,
                        'Description': 'إيراد: ${descCtrl.text}',
                      },
                    ],
                  });

                  if (result['success'] == true) {
                    _snack('تم تعديل الإيراد', AccountingTheme.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                  }
                },
                child: const Text('حفظ التعديل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteRevenue(Map<String, dynamic> entry) {
    final entryId = entry['Id']?.toString();
    if (entryId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('حذف الإيراد',
              style: TextStyle(
                  color: AccountingTheme.danger, fontWeight: FontWeight.bold)),
          content: Text(
            'هل أنت متأكد من حذف الإيراد "${entry['Description'] ?? ''}"؟\nسيتم حذف القيد المحاسبي المرتبط.',
            style: const TextStyle(color: AccountingTheme.textPrimary),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance
                    .deleteJournalEntry(entryId);
                if (result['success'] == true) {
                  _snack('تم حذف الإيراد', AccountingTheme.success);
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

  void _showAddRevenueDialog() async {
    if (_allAccounts.isEmpty) {
      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (result['success'] == true) {
        _allAccounts = (result['data'] as List?) ?? [];
      }
    }

    // حسابات الإيراد (دائن - حسابات نهائية فقط)
    final revenueAccounts = _allAccounts
        .where((a) =>
            a['AccountType']?.toString() == 'Revenue' ||
            (a['Code']?.toString() ?? '').startsWith('4'))
        .where((a) => a['IsLeaf'] == true)
        .toList();

    // حسابات الأصول (مدين - حسابات نهائية فقط)
    final assetAccounts = _allAccounts
        .where((a) =>
            a['AccountType']?.toString() == 'Assets' ||
            (a['Code']?.toString() ?? '').startsWith('1'))
        .where((a) => a['IsLeaf'] == true)
        .toList();

    if (revenueAccounts.isEmpty) {
      _snack('لا توجد حسابات إيرادات. قم ببذر دليل الحسابات أولاً',
          AccountingTheme.warning);
      return;
    }
    if (assetAccounts.isEmpty) {
      _snack('لا توجد حسابات أصول', AccountingTheme.warning);
      return;
    }

    if (!mounted) return;

    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? selectedRevenueAccId = revenueAccounts.first['Id']?.toString();
    String? selectedAssetAccId = assetAccounts.first['Id']?.toString();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: const Text('إضافة إيراد',
                style: TextStyle(
                    color: AccountingTheme.success,
                    fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الوصف
                    _field('الوصف *', descCtrl),
                    const SizedBox(height: 12),
                    // المبلغ
                    _field('المبلغ *', amountCtrl, isNumber: true),
                    const SizedBox(height: 12),
                    // حساب الإيراد (دائن)
                    DropdownButtonFormField<String>(
                      value: selectedRevenueAccId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: revenueAccounts.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Code']} - ${a['Name']}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedRevenueAccId = v),
                      decoration: _inputDeco('حساب الإيراد (دائن)'),
                    ),
                    const SizedBox(height: 12),
                    // حساب الأصل (مدين - أين يذهب المال)
                    DropdownButtonFormField<String>(
                      value: selectedAssetAccId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: assetAccounts.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Code']} - ${a['Name']}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedAssetAccId = v),
                      decoration: _inputDeco('حساب القبض (مدين)'),
                    ),
                    const SizedBox(height: 12),
                    // ملاحظات
                    _field('ملاحظات', notesCtrl),
                    const SizedBox(height: 8),
                    // توضيح القيد
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AccountingTheme.success.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                AccountingTheme.success.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('القيد الناتج:',
                              style: TextStyle(
                                  color: AccountingTheme.success,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.arrow_forward,
                                  color: AccountingTheme.accent, size: 14),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text('حساب القبض ← مدين',
                                    style: TextStyle(
                                        color: AccountingTheme.accent,
                                        fontSize: 11)),
                              ),
                              Text(
                                  amountCtrl.text.isNotEmpty
                                      ? amountCtrl.text
                                      : '0',
                                  style: const TextStyle(
                                      color: AccountingTheme.accent,
                                      fontSize: 11)),
                            ],
                          ),
                          Row(
                            children: [
                              const Icon(Icons.arrow_back,
                                  color: AccountingTheme.success, size: 14),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text('حساب الإيراد ← دائن',
                                    style: TextStyle(
                                        color: AccountingTheme.success,
                                        fontSize: 11)),
                              ),
                              Text(
                                  amountCtrl.text.isNotEmpty
                                      ? amountCtrl.text
                                      : '0',
                                  style: const TextStyle(
                                      color: AccountingTheme.success,
                                      fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء',
                      style: TextStyle(color: AccountingTheme.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.neonGreen,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  if (descCtrl.text.isEmpty || amount <= 0) {
                    _snack('الرجاء ملء الوصف والمبلغ', AccountingTheme.warning);
                    return;
                  }
                  if (selectedRevenueAccId == null ||
                      selectedAssetAccId == null) {
                    _snack('الرجاء اختيار الحسابات', AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);

                  // إنشاء قيد محاسبي: مدين حساب الأصل / دائن حساب الإيراد
                  final userId = VpsAuthService.instance.currentUser?.id;
                  final result =
                      await AccountingService.instance.createJournalEntry(
                    description: descCtrl.text,
                    lines: [
                      {
                        'AccountId': selectedAssetAccId,
                        'DebitAmount': amount,
                        'CreditAmount': 0,
                        'Description': 'قبض إيراد: ${descCtrl.text}',
                      },
                      {
                        'AccountId': selectedRevenueAccId,
                        'DebitAmount': 0,
                        'CreditAmount': amount,
                        'Description': 'إيراد: ${descCtrl.text}',
                      },
                    ],
                    notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    companyId: widget.companyId ?? '',
                    createdById: userId,
                  );

                  if (result['success'] == true) {
                    // ترحيل القيد مباشرة
                    final entryId = result['data']?['Id']?.toString();
                    if (entryId != null) {
                      await AccountingService.instance
                          .postJournalEntry(entryId, approvedById: userId);
                    }
                    _snack('تم تسجيل الإيراد', AccountingTheme.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                  }
                },
                child: const Text('تسجيل الإيراد'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
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

  Map<String, dynamic> _statusInfo(String status) {
    switch (status) {
      case 'Posted':
        return {'label': 'مرحل', 'color': AccountingTheme.success};
      case 'Voided':
        return {'label': 'ملغي', 'color': AccountingTheme.danger};
      default:
        return {'label': 'مسودة', 'color': AccountingTheme.textMuted};
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _fmt(dynamic value) {
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
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
