import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';

/// صفحة كشف الحسابات - عرض جميع الحسابات الفرعية مع كشف حساب مفصّل
class ClientAccountsPage extends StatefulWidget {
  final String? companyId;

  const ClientAccountsPage({super.key, this.companyId});

  @override
  State<ClientAccountsPage> createState() => _ClientAccountsPageState();
}

class _ClientAccountsPageState extends State<ClientAccountsPage> {
  // ─── الحسابات ───
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _allAccounts = [];
  String _searchQuery = '';

  // ─── كشف الحساب المحدد ───
  Map<String, dynamic>? _selectedAccount;
  bool _isLoadingStatement = false;
  List<dynamic> _statementLines = [];
  Map<String, dynamic> _statementSummary = {};
  Map<String, dynamic> _statementAccount = {};

  // ─── فلتر التاريخ ───
  DateTime? _fromDate;
  DateTime? _toDate;

  final _dateFmt = DateFormat('yyyy-MM-dd');
  final _displayDateFmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (!mounted) return;
      if (result['success'] == true) {
        final raw = (result['data'] as List?) ?? [];
        // فقط الحسابات الفرعية (leaf)
        _allAccounts = raw
            .where((a) => a['IsLeaf'] == true)
            .map<Map<String, dynamic>>((a) => Map<String, dynamic>.from(a))
            .toList();
        _allAccounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
      } else {
        _errorMessage = result['message'] ?? 'خطأ في تحميل الحسابات';
      }
    } catch (e) {
      if (!mounted) return;
      _errorMessage = 'خطأ: $e';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filteredAccounts {
    if (_searchQuery.isEmpty) return _allAccounts;
    final q = _searchQuery.toLowerCase();
    return _allAccounts.where((a) {
      final name = (a['Name']?.toString() ?? '').toLowerCase();
      final code = (a['Code']?.toString() ?? '').toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  Future<void> _loadStatement(Map<String, dynamic> account) async {
    final accountId = account['Id']?.toString();
    if (accountId == null) return;
    setState(() {
      _selectedAccount = account;
      _isLoadingStatement = true;
      _statementLines = [];
      _statementSummary = {};
      _statementAccount = {};
    });
    try {
      final result = await AccountingService.instance.getAccountStatement(
        accountId,
        fromDate: _fromDate != null ? _dateFmt.format(_fromDate!) : null,
        toDate: _toDate != null ? _dateFmt.format(_toDate!) : null,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        final data = result['data'] ?? {};
        _statementLines = (data['Lines'] as List?) ?? [];
        _statementSummary = Map<String, dynamic>.from(data['Summary'] ?? {});
        _statementAccount = Map<String, dynamic>.from(data['Account'] ?? {});
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingStatement = false);
  }

  void _reloadStatement() {
    if (_selectedAccount != null) _loadStatement(_selectedAccount!);
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _fromDate : _toDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: AccountingTheme.neonBlue,
              onPrimary: Colors.white,
              surface: AccountingTheme.bgCard,
            ),
          ),
          child: child!,
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
      _reloadStatement();
    }
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
              child: Row(
                children: [
                  // ─── القائمة الجانبية: الحسابات ───
                  _buildAccountsSidebar(),
                  // ─── المحتوى: كشف الحساب ───
                  Expanded(child: _buildStatementArea()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // شريط العنوان
  // ═══════════════════════════════════════════
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
              gradient: AccountingTheme.neonBlueGradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('كشف الحسابات',
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonBlue.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_allAccounts.length} حساب',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonBlue,
                )),
          ),
          const Spacer(),
          IconButton(
            onPressed: () {
              _loadAccounts();
              if (_selectedAccount != null) _reloadStatement();
            },
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // القائمة الجانبية - قائمة الحسابات
  // ═══════════════════════════════════════════
  Widget _buildAccountsSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(left: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Column(
        children: [
          // بحث
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              height: 36,
              child: TextField(
                style: GoogleFonts.cairo(
                    fontSize: 13, color: AccountingTheme.textPrimary),
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم أو الكود...',
                  hintStyle: GoogleFonts.cairo(
                      fontSize: 12, color: AccountingTheme.textMuted),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AccountingTheme.textMuted),
                  filled: true,
                  fillColor: AccountingTheme.bgPrimary,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: AccountingTheme.borderColor)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: AccountingTheme.borderColor)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AccountingTheme.neonBlue)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: AccountingTheme.borderColor),
          // القائمة
          Expanded(child: _buildAccountList()),
        ],
      ),
    );
  }

  Widget _buildAccountList() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(
              color: AccountingTheme.neonBlue, strokeWidth: 2));
    }
    if (_errorMessage != null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_errorMessage!,
            textAlign: TextAlign.center,
            style:
                GoogleFonts.cairo(color: AccountingTheme.danger, fontSize: 13)),
      ));
    }
    final items = _filteredAccounts;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'لا توجد حسابات' : 'لا توجد نتائج',
          style:
              GoogleFonts.cairo(color: AccountingTheme.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final a = items[i];
        final code = a['Code']?.toString() ?? '';
        final name = a['Name']?.toString() ?? '';
        final balance =
            ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
        final isSelected =
            _selectedAccount != null && _selectedAccount!['Id'] == a['Id'];

        return InkWell(
          onTap: () => _loadStatement(a),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AccountingTheme.neonBlue.withAlpha(20)
                  : Colors.transparent,
              border: Border(
                right: BorderSide(
                  color: isSelected
                      ? AccountingTheme.neonBlue
                      : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(
                    color: AccountingTheme.borderColor.withAlpha(80)),
              ),
            ),
            child: Row(
              children: [
                // كود الحساب
                Container(
                  width: 48,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AccountingTheme.neonBlue.withAlpha(30)
                        : AccountingTheme.bgPrimary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    code,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AccountingTheme.neonBlue
                          : AccountingTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // اسم الحساب
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? AccountingTheme.neonBlue
                          : AccountingTheme.textPrimary,
                    ),
                  ),
                ),
                // الرصيد
                Text(
                  _fmt(balance.abs()),
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: balance == 0
                        ? AccountingTheme.textMuted
                        : (balance > 0
                            ? AccountingTheme.danger
                            : AccountingTheme.success),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  // منطقة كشف الحساب
  // ═══════════════════════════════════════════
  Widget _buildStatementArea() {
    if (_selectedAccount == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 64, color: AccountingTheme.textMuted.withAlpha(60)),
            const SizedBox(height: 16),
            Text('اختر حساباً من القائمة لعرض كشف الحساب',
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textMuted, fontSize: 14)),
            const SizedBox(height: 8),
            Text('يمكنك البحث بالاسم أو الكود',
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textMuted.withAlpha(120),
                    fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildStatementHeader(),
        _buildDateFilter(),
        _buildStatementSummaryBar(),
        Expanded(child: _buildStatementTable()),
      ],
    );
  }

  // ─── رأس كشف الحساب ───
  Widget _buildStatementHeader() {
    final name = _selectedAccount?['Name'] ?? '';
    final code = _selectedAccount?['Code'] ?? '';
    final type = _statementAccount['AccountType'] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AccountingTheme.neonPurple.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.receipt_long_rounded,
                color: AccountingTheme.neonPurple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كشف حساب: $name',
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.textPrimary,
                    )),
                Text('كود: $code  •  النوع: ${_translateType(type)}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: AccountingTheme.textMuted,
                    )),
              ],
            ),
          ),
          // عدد الحركات
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AccountingTheme.neonGreen.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_statementLines.length} حركة',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonGreen,
                )),
          ),
        ],
      ),
    );
  }

  // ─── فلتر التاريخ ───
  Widget _buildDateFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: AccountingTheme.bgPrimary,
      child: Row(
        children: [
          Text('الفترة:',
              style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AccountingTheme.textSecondary)),
          const SizedBox(width: 12),
          // من تاريخ
          _dateBtn(
            label: _fromDate != null
                ? _displayDateFmt.format(_fromDate!)
                : 'من تاريخ',
            onTap: () => _pickDate(true),
            hasValue: _fromDate != null,
          ),
          const SizedBox(width: 8),
          Text('→',
              style: GoogleFonts.cairo(
                  color: AccountingTheme.textMuted, fontSize: 14)),
          const SizedBox(width: 8),
          // إلى تاريخ
          _dateBtn(
            label: _toDate != null
                ? _displayDateFmt.format(_toDate!)
                : 'إلى تاريخ',
            onTap: () => _pickDate(false),
            hasValue: _toDate != null,
          ),
          if (_fromDate != null || _toDate != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                setState(() {
                  _fromDate = null;
                  _toDate = null;
                });
                _reloadStatement();
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AccountingTheme.danger.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 14, color: AccountingTheme.danger),
                    const SizedBox(width: 4),
                    Text('مسح',
                        style: GoogleFonts.cairo(
                            fontSize: 11, color: AccountingTheme.danger)),
                  ],
                ),
              ),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  Widget _dateBtn(
      {required String label,
      required VoidCallback onTap,
      bool hasValue = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: hasValue
              ? AccountingTheme.neonBlue.withAlpha(15)
              : AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: hasValue
                  ? AccountingTheme.neonBlue.withAlpha(80)
                  : AccountingTheme.borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today,
                size: 14,
                color: hasValue
                    ? AccountingTheme.neonBlue
                    : AccountingTheme.textMuted),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: hasValue
                      ? AccountingTheme.neonBlue
                      : AccountingTheme.textMuted,
                )),
          ],
        ),
      ),
    );
  }

  // ─── ملخص كشف الحساب ───
  Widget _buildStatementSummaryBar() {
    final totalDebit =
        ((_statementSummary['TotalDebit'] ?? 0) as num).toDouble();
    final totalCredit =
        ((_statementSummary['TotalCredit'] ?? 0) as num).toDouble();
    final balance = ((_statementSummary['Balance'] ?? 0) as num).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(
          bottom: BorderSide(color: AccountingTheme.borderColor),
          top: BorderSide(color: AccountingTheme.borderColor),
        ),
      ),
      child: Row(
        children: [
          _summaryChip('مجموع المدين', totalDebit, AccountingTheme.danger),
          const SizedBox(width: 16),
          _summaryChip('مجموع الدائن', totalCredit, AccountingTheme.success),
          const SizedBox(width: 16),
          _summaryChip(
            'الرصيد',
            balance.abs(),
            balance == 0
                ? AccountingTheme.textMuted
                : (balance > 0
                    ? AccountingTheme.danger
                    : AccountingTheme.success),
            suffix: balance == 0 ? 'مسدد' : (balance > 0 ? 'مدين' : 'دائن'),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, double value, Color color,
      {String? suffix}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: GoogleFonts.cairo(
                fontSize: 12, color: AccountingTheme.textMuted)),
        Text('${_fmt(value)} د.ع',
            style: GoogleFonts.cairo(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        if (suffix != null) ...[
          const SizedBox(width: 4),
          Text('($suffix)',
              style: GoogleFonts.cairo(fontSize: 11, color: color)),
        ],
      ],
    );
  }

  // ─── جدول الحركات ───
  Widget _buildStatementTable() {
    if (_isLoadingStatement) {
      return const Center(
          child: CircularProgressIndicator(
              color: AccountingTheme.neonBlue, strokeWidth: 2));
    }

    if (_statementLines.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48, color: AccountingTheme.textMuted.withAlpha(60)),
            const SizedBox(height: 12),
            Text('لا توجد حركات لهذا الحساب',
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textMuted, fontSize: 13)),
            if (_fromDate != null || _toDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('جرّب تغيير فلتر التاريخ',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textMuted.withAlpha(100),
                        fontSize: 12)),
              ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AccountingTheme.borderColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Table(
            columnWidths: {
              0: const FixedColumnWidth(50), // #
              1: const FixedColumnWidth(100), // رقم القيد
              2: const FixedColumnWidth(110), // التاريخ
              3: const FlexColumnWidth(), // البيان
              4: const FixedColumnWidth(120), // مدين
              5: const FixedColumnWidth(120), // دائن
              6: const FixedColumnWidth(130), // الرصيد
            },
            border: TableBorder(
              horizontalInside:
                  BorderSide(color: AccountingTheme.borderColor.withAlpha(80)),
            ),
            children: [
              // رأس الجدول
              TableRow(
                decoration: BoxDecoration(
                  color: AccountingTheme.bgSidebar,
                ),
                children: [
                  _th('#'),
                  _th('رقم القيد'),
                  _th('التاريخ'),
                  _th('البيان'),
                  _th('مدين'),
                  _th('دائن'),
                  _th('الرصيد'),
                ],
              ),
              // الصفوف
              for (int i = 0; i < _statementLines.length; i++)
                _buildTableRow(i, _statementLines[i], _calcRunning(i)),
            ],
          ),
        ),
      ),
    );
  }

  double _calcRunning(int upToIndex) {
    double r = 0;
    for (int j = 0; j <= upToIndex; j++) {
      final line = _statementLines[j];
      final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
      final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();
      r += debit - credit;
    }
    return r;
  }

  TableRow _buildTableRow(int index, dynamic line, double running) {
    final entryNum = line['EntryNumber']?.toString() ?? '';
    final dateStr = line['EntryDate']?.toString() ?? '';
    final desc = (line['Description']?.toString().isNotEmpty == true
                ? line['Description']
                : line['EntryDescription'])
            ?.toString() ??
        '';
    final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
    final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();

    String formattedDate = '';
    try {
      final dt = DateTime.parse(dateStr);
      formattedDate = _displayDateFmt.format(dt);
    } catch (_) {
      formattedDate = dateStr.length > 10 ? dateStr.substring(0, 10) : dateStr;
    }

    final bgColor =
        index.isEven ? Colors.transparent : AccountingTheme.bgPrimary;

    return TableRow(
      decoration: BoxDecoration(color: bgColor),
      children: [
        _td('${index + 1}', align: TextAlign.center),
        _td(entryNum, align: TextAlign.center),
        _td(formattedDate, align: TextAlign.center),
        _td(desc),
        _td(debit > 0 ? _fmt(debit) : '-',
            color:
                debit > 0 ? AccountingTheme.danger : AccountingTheme.textMuted,
            align: TextAlign.center),
        _td(credit > 0 ? _fmt(credit) : '-',
            color: credit > 0
                ? AccountingTheme.success
                : AccountingTheme.textMuted,
            align: TextAlign.center),
        _td('${_fmt(running.abs())} ${running > 0 ? 'مدين' : (running < 0 ? 'دائن' : '')}',
            color: running == 0
                ? AccountingTheme.textMuted
                : (running > 0
                    ? AccountingTheme.danger
                    : AccountingTheme.success),
            align: TextAlign.center,
            bold: true),
      ],
    );
  }

  // ─── خلايا الجدول ───
  Widget _th(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(text,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
    );
  }

  Widget _td(String text,
      {Color? color, TextAlign align = TextAlign.start, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(text,
          textAlign: align,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: color ?? AccountingTheme.textPrimary,
          )),
    );
  }

  // ─── مساعدات ───
  String _translateType(String type) {
    const map = {
      'Assets': 'أصول',
      'Liabilities': 'خصوم',
      'Equity': 'حقوق ملكية',
      'Revenue': 'إيرادات',
      'Expenses': 'مصروفات',
    };
    return map[type] ?? type;
  }

  String _fmt(dynamic value) {
    if (value == null || value == 0) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
}
