import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';

/// صفحة القيود المحاسبية
class JournalEntriesPage extends StatefulWidget {
  final String? companyId;

  const JournalEntriesPage({super.key, this.companyId});

  @override
  State<JournalEntriesPage> createState() => _JournalEntriesPageState();
}

class _JournalEntriesPageState extends State<JournalEntriesPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _entries = [];
  String _statusFilter = 'all'; // all, Draft, Posted, Voided

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
          .getJournalEntries(companyId: widget.companyId);
      if (result['success'] == true) {
        final all = (result['data'] is List) ? result['data'] as List : [];
        if (_statusFilter != 'all') {
          _entries = all
              .where((e) => e['Status']?.toString() == _statusFilter)
              .toList();
        } else {
          _entries = all;
        }
      } else {
        _errorMessage = result['message'] ?? 'خطأ';
      }
    } catch (e) {
      _errorMessage = 'خطأ: $e';
    }
    setState(() {
      _isLoading = false;
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
            _buildFilterBar(),
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
                      : _buildList(),
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
            child: const Icon(Icons.menu_book_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('القيود المحاسبية',
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
            child: Text('${_entries.length}',
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
            onPressed: _showCreateDialog,
            icon: const Icon(Icons.add, size: 16),
            label: Text('إنشاء قيد', style: GoogleFonts.cairo(fontSize: 13)),
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

  Widget _buildFilterBar() {
    final filters = [
      {
        'value': 'all',
        'label': 'الكل',
        'icon': Icons.check,
        'color': AccountingTheme.neonBlue
      },
      {
        'value': 'Draft',
        'label': 'مسودة',
        'icon': Icons.drafts,
        'color': AccountingTheme.textMuted
      },
      {
        'value': 'Posted',
        'label': 'مرحل',
        'icon': Icons.check_circle,
        'color': AccountingTheme.neonGreen
      },
      {
        'value': 'Voided',
        'label': 'ملغي',
        'icon': Icons.cancel,
        'color': AccountingTheme.danger
      },
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          ...filters.map((f) {
            final isSelected = _statusFilter == f['value'];
            final color = f['color'] as Color;
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: InkWell(
                onTap: () {
                  setState(() => _statusFilter = f['value'] as String);
                  _loadData();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? color.withOpacity(0.5)
                          : AccountingTheme.borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        Icon(f['icon'] as IconData, size: 14, color: color),
                        const SizedBox(width: 4),
                      ],
                      Text(f['label'] as String,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? color
                                : AccountingTheme.textSecondary,
                          )),
                    ],
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Text('${_entries.length} قيد',
              style: GoogleFonts.cairo(
                  color: AccountingTheme.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book,
                color: AccountingTheme.textMuted.withOpacity(0.3), size: 48),
            const SizedBox(height: 12),
            Text('لا توجد قيود',
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textMuted, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _entries.length,
      itemBuilder: (_, i) {
        final entry = _entries[i];
        final status = entry['Status']?.toString() ?? 'Draft';
        final statusInfo = _statusInfo(status);
        final lines = (entry['Lines'] as List?) ?? [];
        final totalDebit = lines.fold<double>(
            0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble());

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AccountingTheme.borderColor),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1)),
            ],
          ),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            iconColor: AccountingTheme.textMuted,
            collapsedIconColor: AccountingTheme.textMuted,
            title: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        (statusInfo['color'] as Color).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: (statusInfo['color'] as Color)
                            .withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    statusInfo['label'] as String,
                    style: GoogleFonts.cairo(
                        color: statusInfo['color'] as Color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry['Description'] ??
                        'قيد #${entry['EntryNumber'] ?? i + 1}',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textPrimary, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${_fmt(totalDebit)} د.ع',
                  style: GoogleFonts.cairo(
                      color: AccountingTheme.neonGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (entry['EntryNumber'] != null)
                    Text('#${entry['EntryNumber']}  ',
                        style: GoogleFonts.cairo(
                            color: AccountingTheme.neonBlue, fontSize: 11)),
                  Text(_formatDate(entry['EntryDate'] ?? entry['CreatedAt']),
                      style: GoogleFonts.cairo(
                          color: AccountingTheme.textMuted, fontSize: 11)),
                  if (entry['ReferenceType'] != null) ...[
                    const Text('  |  ',
                        style: TextStyle(color: AccountingTheme.textMuted)),
                    Text(_refTypeLabel(entry['ReferenceType']),
                        style: GoogleFonts.cairo(
                            color: AccountingTheme.textSecondary,
                            fontSize: 11)),
                  ],
                ],
              ),
            ),
            children: [
              // خطوط القيد
              if (lines.isNotEmpty) ...[
                Container(
                  decoration: BoxDecoration(
                    color: AccountingTheme.bgCardHover,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          children: const [
                            Expanded(
                                flex: 3,
                                child: Text('الحساب',
                                    style: TextStyle(
                                        color: AccountingTheme.textMuted,
                                        fontSize: 11))),
                            SizedBox(
                                width: 80,
                                child: Text('مدين',
                                    style: TextStyle(
                                        color: AccountingTheme.neonGreen,
                                        fontSize: 11),
                                    textAlign: TextAlign.center)),
                            SizedBox(
                                width: 80,
                                child: Text('دائن',
                                    style: TextStyle(
                                        color: AccountingTheme.danger,
                                        fontSize: 11),
                                    textAlign: TextAlign.center)),
                          ],
                        ),
                      ),
                      const Divider(
                          color: AccountingTheme.borderColor, height: 1),
                      ...lines.map<Widget>((line) {
                        final debit =
                            ((line['DebitAmount'] ?? 0) as num).toDouble();
                        final credit =
                            ((line['CreditAmount'] ?? 0) as num).toDouble();
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  line['AccountName'] ??
                                      'حساب #${line['AccountId']}',
                                  style: const TextStyle(
                                      color: AccountingTheme.textSecondary,
                                      fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  debit > 0 ? _fmt(debit) : '-',
                                  style: TextStyle(
                                      color: debit > 0
                                          ? AccountingTheme.neonGreen
                                          : AccountingTheme.textMuted,
                                      fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  credit > 0 ? _fmt(credit) : '-',
                                  style: TextStyle(
                                      color: credit > 0
                                          ? AccountingTheme.danger
                                          : AccountingTheme.textMuted,
                                      fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              // الأزرار
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'Draft') ...[
                    TextButton.icon(
                      onPressed: () => _showEditEntryDialog(entry),
                      icon: const Icon(Icons.edit, size: 14),
                      label:
                          const Text('تعديل', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          foregroundColor: AccountingTheme.info),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _postEntry(entry),
                      icon: const Icon(Icons.check_circle, size: 14),
                      label:
                          const Text('ترحيل', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          foregroundColor: AccountingTheme.success),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (status == 'Posted')
                    TextButton.icon(
                      onPressed: () => _voidEntry(entry),
                      icon: const Icon(Icons.cancel, size: 14),
                      label:
                          const Text('إلغاء', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          foregroundColor: AccountingTheme.danger),
                    ),
                  if (status != 'Voided') ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => _confirmDeleteEntry(entry),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: const Text('حذف', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                          foregroundColor: AccountingTheme.danger),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateDialog() async {
    // جلب دليل الحسابات أولاً
    final accountsResult = await AccountingService.instance
        .getAccounts(companyId: widget.companyId);
    if (accountsResult['success'] != true) {
      _snack('خطأ في جلب الحسابات', AccountingTheme.danger);
      return;
    }
    final accounts = (accountsResult['data'] as List?) ?? [];
    if (accounts.length < 2) {
      _snack('يجب أن يكون لديك حسابين على الأقل لإنشاء قيد',
          AccountingTheme.warning);
      return;
    }

    if (!mounted) return;

    final descCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final lines = <Map<String, dynamic>>[
      {'accountId': null, 'debit': 0.0, 'credit': 0.0},
      {'accountId': null, 'debit': 0.0, 'credit': 0.0},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          final totalDebit =
              lines.fold<double>(0, (s, l) => s + (l['debit'] as double));
          final totalCredit =
              lines.fold<double>(0, (s, l) => s + (l['credit'] as double));
          final isBalanced =
              totalDebit > 0 && (totalDebit - totalCredit).abs() < 0.01;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: AccountingTheme.bgCard,
              title: const Text('إنشاء قيد محاسبي',
                  style: TextStyle(color: AccountingTheme.textPrimary)),
              content: SizedBox(
                width: 600,
                height: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field('الوصف', descCtrl),
                      const SizedBox(height: 12),
                      // خطوط القيد
                      const Text('خطوط القيد:',
                          style: TextStyle(
                              color: AccountingTheme.textPrimary,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...List.generate(lines.length, (i) {
                        final amtDebitCtrl = TextEditingController(
                          text: lines[i]['debit'] > 0
                              ? lines[i]['debit'].toString()
                              : '',
                        );
                        final amtCreditCtrl = TextEditingController(
                          text: lines[i]['credit'] > 0
                              ? lines[i]['credit'].toString()
                              : '',
                        );

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AccountingTheme.bgCardHover,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  value: lines[i]['accountId']?.toString(),
                                  dropdownColor: AccountingTheme.bgCard,
                                  style: const TextStyle(
                                      color: AccountingTheme.textPrimary,
                                      fontSize: 12),
                                  isExpanded: true,
                                  items: accounts
                                      .map<DropdownMenuItem<String>>((a) {
                                    return DropdownMenuItem(
                                      value: a['Id']?.toString(),
                                      child: Text('${a['Code']} - ${a['Name']}',
                                          overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                  onChanged: (v) =>
                                      ss(() => lines[i]['accountId'] = v),
                                  decoration: InputDecoration(
                                    labelText: 'الحساب',
                                    labelStyle: const TextStyle(
                                        color: AccountingTheme.textMuted,
                                        fontSize: 11),
                                    filled: true,
                                    fillColor: AccountingTheme.bgCardHover,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: amtDebitCtrl,
                                  style: const TextStyle(
                                      color: AccountingTheme.success,
                                      fontSize: 13),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => ss(() => lines[i]['debit'] =
                                      double.tryParse(v) ?? 0.0),
                                  decoration: InputDecoration(
                                    labelText: 'مدين',
                                    labelStyle: const TextStyle(
                                        color: AccountingTheme.accent,
                                        fontSize: 10),
                                    filled: true,
                                    fillColor: AccountingTheme.bgCardHover,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: amtCreditCtrl,
                                  style: const TextStyle(
                                      color: AccountingTheme.danger,
                                      fontSize: 13),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => ss(() => lines[i]
                                      ['credit'] = double.tryParse(v) ?? 0.0),
                                  decoration: InputDecoration(
                                    labelText: 'دائن',
                                    labelStyle: const TextStyle(
                                        color: AccountingTheme.danger,
                                        fontSize: 10),
                                    filled: true,
                                    fillColor: AccountingTheme.bgCardHover,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                  ),
                                ),
                              ),
                              if (lines.length > 2)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle,
                                      color: AccountingTheme.danger, size: 18),
                                  onPressed: () => ss(() => lines.removeAt(i)),
                                ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () => ss(() => lines.add(
                            {'accountId': null, 'debit': 0.0, 'credit': 0.0})),
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('إضافة سطر',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: AccountingTheme.accent),
                      ),
                      const SizedBox(height: 8),
                      // الإجماليات
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isBalanced
                              ? AccountingTheme.success.withValues(alpha: 0.2)
                              : AccountingTheme.danger.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: isBalanced
                                  ? AccountingTheme.success
                                  : AccountingTheme.danger,
                              width: 0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text('مدين: ${_fmt(totalDebit)}',
                                style: const TextStyle(
                                    color: AccountingTheme.accent,
                                    fontSize: 13)),
                            Text('دائن: ${_fmt(totalCredit)}',
                                style: const TextStyle(
                                    color: AccountingTheme.danger,
                                    fontSize: 13)),
                            Icon(
                              isBalanced ? Icons.check_circle : Icons.warning,
                              color: isBalanced
                                  ? AccountingTheme.success
                                  : AccountingTheme.danger,
                              size: 18,
                            ),
                            Text(
                              isBalanced ? 'متوازن' : 'غير متوازن',
                              style: TextStyle(
                                  color: isBalanced
                                      ? AccountingTheme.success
                                      : AccountingTheme.danger,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
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
                    backgroundColor: isBalanced
                        ? AccountingTheme.neonGreen
                        : AccountingTheme.textMuted,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isBalanced
                      ? () async {
                          if (descCtrl.text.isEmpty) {
                            _snack('الرجاء إدخال وصف', AccountingTheme.warning);
                            return;
                          }
                          // تحقق من اختيار الحسابات
                          final validLines = lines
                              .where((l) =>
                                  l['accountId'] != null &&
                                  (l['debit'] > 0 || l['credit'] > 0))
                              .toList();
                          if (validLines.length < 2) {
                            _snack('يجب أن يكون هناك سطران على الأقل',
                                AccountingTheme.warning);
                            return;
                          }
                          Navigator.pop(ctx);
                          final userId =
                              VpsAuthService.instance.currentUser?.id;
                          final result = await AccountingService.instance
                              .createJournalEntry(
                            description: descCtrl.text,
                            lines: validLines
                                .map((l) => {
                                      'AccountId': l['accountId'],
                                      'DebitAmount': l['debit'],
                                      'CreditAmount': l['credit'],
                                    })
                                .toList(),
                            notes:
                                notesCtrl.text.isEmpty ? null : notesCtrl.text,
                            companyId: widget.companyId ?? '',
                            createdById: userId,
                          );
                          if (result['success'] == true) {
                            _snack('تم إنشاء القيد', AccountingTheme.success);
                            _loadData();
                          } else {
                            _snack(result['message'] ?? 'خطأ',
                                AccountingTheme.danger);
                          }
                        }
                      : null,
                  child: const Text('إنشاء'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _postEntry(dynamic entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('ترحيل القيد',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: const Text(
              'هل تريد ترحيل هذا القيد؟ لا يمكن التعديل بعد الترحيل.',
              style: TextStyle(color: AccountingTheme.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.success),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ترحيل'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    final result = await AccountingService.instance.postJournalEntry(
        entry['Id'].toString(),
        approvedById: VpsAuthService.instance.currentUser?.id);
    if (result['success'] == true) {
      _snack('تم ترحيل القيد', AccountingTheme.success);
      _loadData();
    } else {
      _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
    }
  }

  void _voidEntry(dynamic entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('إلغاء القيد',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: const Text('هل تريد إلغاء هذا القيد؟ سيتم عكس جميع الأرصدة.',
              style: TextStyle(color: AccountingTheme.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('رجوع',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء القيد'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    final result = await AccountingService.instance
        .voidJournalEntry(entry['Id'].toString());
    if (result['success'] == true) {
      _snack('تم إلغاء القيد', AccountingTheme.success);
      _loadData();
    } else {
      _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
    }
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

  String _refTypeLabel(dynamic refType) {
    switch (refType?.toString()) {
      case 'Manual':
        return 'يدوي';
      case 'CashTransaction':
        return 'حركة صندوق';
      case 'Salary':
        return 'رواتب';
      case 'TechnicianCollection':
        return 'تحصيل';
      case 'Expense':
        return 'مصروف';
      default:
        return refType?.toString() ?? '';
    }
  }

  Widget _field(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
        filled: true,
        fillColor: AccountingTheme.bgCardHover,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }

  void _showEditEntryDialog(Map<String, dynamic> entry) {
    final descCtrl = TextEditingController(text: entry['Description'] ?? '');
    final notesCtrl = TextEditingController(text: entry['Notes'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('تعديل القيد',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(color: AccountingTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'الوصف',
                    labelStyle:
                        const TextStyle(color: AccountingTheme.textMuted),
                    filled: true,
                    fillColor: AccountingTheme.bgCardHover,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(color: AccountingTheme.textPrimary),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات',
                    labelStyle:
                        const TextStyle(color: AccountingTheme.textMuted),
                    filled: true,
                    fillColor: AccountingTheme.bgCardHover,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                  ),
                ),
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
                final result =
                    await AccountingService.instance.updateJournalEntry(
                  entry['Id'].toString(),
                  {
                    'Description': descCtrl.text,
                    'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                  },
                );
                if (result['success'] == true) {
                  _snack('تم تحديث القيد', AccountingTheme.success);
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

  void _confirmDeleteEntry(Map<String, dynamic> entry) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: const Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'هل تريد حذف القيد "${entry['Description'] ?? 'قيد #${entry['EntryNumber']}'}"؟\nسيتم عكس أرصدة الحسابات المتأثرة.',
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
                    .deleteJournalEntry(entry['Id'].toString());
                if (result['success'] == true) {
                  _snack('تم حذف القيد', AccountingTheme.success);
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
