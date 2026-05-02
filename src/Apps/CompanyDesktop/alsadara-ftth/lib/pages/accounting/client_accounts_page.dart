import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

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
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
      _errorMessage = 'خطأ';
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

  Future<void> _loadStatement(Map<String, dynamic> account,
      {bool resetDates = true}) async {
    final accountId = account['Id']?.toString();
    if (accountId == null) return;
    setState(() {
      _selectedAccount = account;
      _isLoadingStatement = true;
      _statementLines = [];
      _statementSummary = {};
      _statementAccount = {};
      if (resetDates) {
        _fromDate = null;
        _toDate = null;
      }
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
    if (_selectedAccount != null) {
      _loadStatement(_selectedAccount!, resetDates: false);
    }
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
    final isMob = context.accR.isMobile;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Container(
            margin: isMob ? const EdgeInsets.all(4) : const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AccountingTheme.bgPrimary,
              borderRadius: BorderRadius.circular(isMob ? 10 : 14),
              border: Border.all(color: Colors.black87, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isMob ? 8 : 12),
              child: Stack(
                children: [
                  // ─── زخرفة الزوايا ───
                  ...[
                    Positioned(top: 0, right: 0, child: _cornerOrnament()),
                    Positioned(
                        top: 0, left: 0, child: _cornerOrnament(flipH: true)),
                    Positioned(
                        bottom: 0,
                        right: 0,
                        child: _cornerOrnament(flipV: true)),
                    Positioned(
                        bottom: 0,
                        left: 0,
                        child: _cornerOrnament(flipH: true, flipV: true)),
                  ],
                  // ─── المحتوى ───
                  Column(
                    children: [
                      _buildToolbar(),
                      _buildSearchBar(),
                      if (_selectedAccount != null) ...[
                        _buildDateFilter(),
                        _buildStatementSummaryBar(),
                        Expanded(child: _buildStatementTable()),
                      ] else if (_searchQuery.isNotEmpty) ...[
                        Expanded(child: _buildAccountList()),
                      ] else ...[
                        Expanded(child: _buildSearchPrompt()),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// زخرفة زاوية
  Widget _cornerOrnament({bool flipH = false, bool flipV = false}) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scale(flipH ? -1.0 : 1.0, flipV ? -1.0 : 1.0),
      child: SizedBox(
        width: 32,
        height: 32,
        child: CustomPaint(painter: _CornerPainter()),
      ),
    );
  }

  /// شريط البحث - يتحول لبطاقة الحساب المحدد عند الاختيار
  Widget _buildSearchBar() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    final hPad = isMob ? 10.0 : ar.spaceXL;

    if (_selectedAccount != null) {
      final name = _selectedAccount?['Name']?.toString() ?? '';
      final code = _selectedAccount?['Code']?.toString() ?? '';
      final type = _statementAccount['AccountType'] ?? '';
      return Container(
        margin: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
        padding: EdgeInsets.symmetric(
            horizontal: isMob ? 10 : 14, vertical: isMob ? 8 : 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AccountingTheme.neonBlue.withAlpha(20),
              AccountingTheme.neonPurple.withAlpha(12),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AccountingTheme.neonBlue.withAlpha(50)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMob ? 6 : 8),
              decoration: BoxDecoration(
                color: AccountingTheme.neonBlue.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.receipt_long_rounded,
                  size: isMob ? 16 : ar.iconM, color: AccountingTheme.neonBlue),
            ),
            SizedBox(width: isMob ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.cairo(
                          fontSize: isMob ? 13 : ar.headingSmall,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.textPrimary),
                      overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                            'كشف حساب  •  كود: $code  •  ${_translateType(type)}',
                            style: GoogleFonts.cairo(
                                fontSize: isMob ? 10 : ar.small,
                                color: AccountingTheme.textMuted),
                            overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: isMob ? 5 : 8, vertical: 1),
                        decoration: BoxDecoration(
                          color: AccountingTheme.neonGreen.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${_statementLines.length} حركة',
                            style: GoogleFonts.cairo(
                                fontSize: isMob ? 9 : ar.small,
                                fontWeight: FontWeight.bold,
                                color: AccountingTheme.neonGreen)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            InkWell(
              onTap: () {
                setState(() {
                  _selectedAccount = null;
                  _searchQuery = '';
                  _searchController.clear();
                  _statementLines = [];
                  _statementSummary = {};
                  _statementAccount = {};
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.all(isMob ? 6 : 8),
                decoration: BoxDecoration(
                  color: AccountingTheme.danger.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.close,
                    size: isMob ? 16 : ar.iconM, color: AccountingTheme.danger),
              ),
            ),
          ],
        ),
      );
    }

    // وضع البحث
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.cairo(
            fontSize: isMob ? 13 : ar.financialSmall,
            color: AccountingTheme.textPrimary),
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(
          hintText: 'ابحث عن حساب بالاسم أو الكود...',
          hintStyle: GoogleFonts.cairo(
              fontSize: isMob ? 12 : ar.small,
              color: AccountingTheme.textMuted),
          prefixIcon: Icon(Icons.search,
              size: isMob ? 20 : ar.iconM, color: AccountingTheme.textMuted),
          suffixIcon: _searchQuery.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  child: Icon(Icons.clear,
                      size: isMob ? 18 : ar.iconM,
                      color: AccountingTheme.textMuted),
                )
              : null,
          filled: true,
          fillColor: AccountingTheme.bgCard,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AccountingTheme.borderColor)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AccountingTheme.borderColor)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AccountingTheme.neonBlue)),
          contentPadding: EdgeInsets.symmetric(
              horizontal: isMob ? 12 : ar.spaceXL, vertical: 10),
        ),
      ),
    );
  }

  /// حالة فارغة - ينتظر المستخدم البحث
  Widget _buildSearchPrompt() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isMob ? 24 : 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: isMob ? 48 : ar.iconEmpty,
                color: AccountingTheme.textMuted.withAlpha(60)),
            SizedBox(height: isMob ? 12 : ar.spaceXL),
            Text('ابحث عن حساب',
                style: GoogleFonts.cairo(
                    fontSize: isMob ? 14 : ar.headingSmall,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textMuted)),
            SizedBox(height: isMob ? 4 : ar.spaceS),
            Text('اكتب اسم أو كود الحساب في مربع البحث اعلاه',
                style: GoogleFonts.cairo(
                    fontSize: isMob ? 11 : ar.body,
                    color: AccountingTheme.textMuted.withAlpha(120))),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // شريط العنوان
  // ═══════════════════════════════════════════
  Widget _buildToolbar() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 6 : ar.spaceL),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.arrow_forward_rounded, size: isMob ? 20 : 24),
            tooltip: 'رجوع',
            padding: isMob ? EdgeInsets.all(4) : null,
            constraints: isMob
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMob ? 5 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonBlueGradient,
              borderRadius: BorderRadius.circular(isMob ? 6 : 8),
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: isMob ? 16 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('كشف الحسابات',
              style: GoogleFonts.cairo(
                fontSize: isMob ? 14 : ar.headingMedium,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: isMob ? 6 : 8, vertical: 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonBlue.withAlpha(40),
              borderRadius: BorderRadius.circular(ar.cardRadius),
            ),
            child: Text('${_allAccounts.length} حساب',
                style: GoogleFonts.cairo(
                  fontSize: isMob ? 10 : ar.small,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonBlue,
                )),
          ),
          Spacer(),
          IconButton(
            onPressed: () {
              _loadAccounts();
              if (_selectedAccount != null) _reloadStatement();
            },
            icon: Icon(Icons.refresh, size: isMob ? 18 : ar.iconM),
            tooltip: 'تحديث',
            padding: isMob ? EdgeInsets.all(4) : null,
            constraints: isMob
                ? const BoxConstraints(minWidth: 32, minHeight: 32)
                : null,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
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
        padding: EdgeInsets.all(context.accR.spaceXL),
        child: Text(_errorMessage!,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
                color: AccountingTheme.danger,
                fontSize: context.accR.financialSmall)),
      ));
    }
    final items = _filteredAccounts;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isEmpty ? 'لا توجد حسابات' : 'لا توجد نتائج',
          style: GoogleFonts.cairo(
              color: AccountingTheme.textMuted,
              fontSize: context.accR.financialSmall),
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
            padding: EdgeInsets.symmetric(
                horizontal: context.accR.spaceM, vertical: context.accR.spaceM),
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
                      fontSize: context.accR.small,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AccountingTheme.neonBlue
                          : AccountingTheme.textSecondary,
                    ),
                  ),
                ),
                SizedBox(width: context.accR.spaceS),
                // اسم الحساب
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: context.accR.small,
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
                    fontSize: context.accR.small,
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

  // ─── فلتر التاريخ ───
  Widget _buildDateFilter() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 6 : ar.spaceS),
      color: AccountingTheme.bgPrimary,
      child: isMob
          ? Row(
              children: [
                Text('الفترة:',
                    style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AccountingTheme.textSecondary)),
                const SizedBox(width: 6),
                Expanded(
                  child: _dateBtn(
                    label: _fromDate != null
                        ? _displayDateFmt.format(_fromDate!)
                        : 'من تاريخ',
                    onTap: () => _pickDate(true),
                    hasValue: _fromDate != null,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.arrow_back,
                      size: 12, color: AccountingTheme.textMuted),
                ),
                Expanded(
                  child: _dateBtn(
                    label: _toDate != null
                        ? _displayDateFmt.format(_toDate!)
                        : 'إلى تاريخ',
                    onTap: () => _pickDate(false),
                    hasValue: _toDate != null,
                  ),
                ),
                if (_fromDate != null || _toDate != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                      });
                      _reloadStatement();
                    },
                    child: Container(
                      padding: EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AccountingTheme.danger.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.close,
                          size: 14, color: AccountingTheme.danger),
                    ),
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Text('الفترة:',
                    style: GoogleFonts.cairo(
                        fontSize: ar.financialSmall,
                        fontWeight: FontWeight.w600,
                        color: AccountingTheme.textSecondary)),
                SizedBox(width: ar.spaceM),
                _dateBtn(
                  label: _fromDate != null
                      ? _displayDateFmt.format(_fromDate!)
                      : 'من تاريخ',
                  onTap: () => _pickDate(true),
                  hasValue: _fromDate != null,
                ),
                SizedBox(width: ar.spaceS),
                Text('→',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textMuted, fontSize: ar.body)),
                SizedBox(width: ar.spaceS),
                _dateBtn(
                  label: _toDate != null
                      ? _displayDateFmt.format(_toDate!)
                      : 'إلى تاريخ',
                  onTap: () => _pickDate(false),
                  hasValue: _toDate != null,
                ),
                if (_fromDate != null || _toDate != null) ...[
                  SizedBox(width: ar.spaceS),
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
                      padding: EdgeInsets.symmetric(
                          horizontal: ar.spaceS, vertical: ar.spaceXS),
                      decoration: BoxDecoration(
                        color: AccountingTheme.danger.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close,
                              size: ar.iconS, color: AccountingTheme.danger),
                          SizedBox(width: ar.spaceXS),
                          Text('مسح',
                              style: GoogleFonts.cairo(
                                  fontSize: ar.small,
                                  color: AccountingTheme.danger)),
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
        padding: EdgeInsets.symmetric(
            horizontal: context.accR.spaceM, vertical: context.accR.spaceXS),
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
                size: context.accR.iconS,
                color: hasValue
                    ? AccountingTheme.neonBlue
                    : AccountingTheme.textMuted),
            SizedBox(width: context.accR.spaceXS),
            Text(label,
                style: GoogleFonts.cairo(
                  fontSize: context.accR.small,
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
    final ar = context.accR;
    final isMob = ar.isMobile;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 6 : ar.spaceS),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(
          bottom: BorderSide(color: AccountingTheme.borderColor),
          top: BorderSide(color: AccountingTheme.borderColor),
        ),
      ),
      child: isMob
          ? Row(
              children: [
                Expanded(
                    child: _mobileSummaryChip(
                        'المدين', totalDebit, AccountingTheme.danger)),
                const SizedBox(width: 4),
                Expanded(
                    child: _mobileSummaryChip(
                        'الدائن', totalCredit, AccountingTheme.success)),
                const SizedBox(width: 4),
                Expanded(
                  child: _mobileSummaryChip(
                    'الرصيد',
                    balance.abs(),
                    balance == 0
                        ? AccountingTheme.textMuted
                        : (balance > 0
                            ? AccountingTheme.danger
                            : AccountingTheme.success),
                    suffix:
                        balance == 0 ? '' : (balance > 0 ? '(مدين)' : '(دائن)'),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _summaryChip(
                      'مجموع المدين', totalDebit, AccountingTheme.danger),
                ),
                SizedBox(width: ar.spaceS),
                Expanded(
                  child: _summaryChip(
                      'مجموع الدائن', totalCredit, AccountingTheme.success),
                ),
                SizedBox(width: ar.spaceS),
                Expanded(
                  child: _summaryChip(
                    'الرصيد',
                    balance.abs(),
                    balance == 0
                        ? AccountingTheme.textMuted
                        : (balance > 0
                            ? AccountingTheme.danger
                            : AccountingTheme.success),
                    suffix:
                        balance == 0 ? 'مسدد' : (balance > 0 ? 'مدين' : 'دائن'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _mobileSummaryChip(String label, double value, Color color,
      {String? suffix}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: 8, fontWeight: FontWeight.w600, color: color)),
          Text('${_fmt(value)} د.ع',
              style: GoogleFonts.cairo(
                  fontSize: 10, fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis),
          Text(suffix ?? '',
              style: GoogleFonts.cairo(fontSize: 8, color: color)),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, double value, Color color,
      {String? suffix}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: context.accR.small,
                  fontWeight: FontWeight.w600,
                  color: color)),
          const SizedBox(height: 2),
          Text('${_fmt(value)} د.ع',
              style: GoogleFonts.cairo(
                  fontSize: context.accR.financialSmall,
                  fontWeight: FontWeight.bold,
                  color: color)),
          Text(suffix != null ? '($suffix)' : '',
              style: GoogleFonts.cairo(
                  fontSize: context.accR.small, color: color)),
        ],
      ),
    );
  }

  // ─── جدول الحركات ───
  Widget _buildStatementTable() {
    final ar = context.accR;
    final isMob = ar.isMobile;
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
                size: isMob ? 36 : ar.iconXL,
                color: AccountingTheme.textMuted.withAlpha(60)),
            SizedBox(height: ar.spaceM),
            Text('لا توجد حركات لهذا الحساب',
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textMuted,
                    fontSize: isMob ? 12 : ar.financialSmall)),
            if (_fromDate != null || _toDate != null)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('جرّب تغيير فلتر التاريخ',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textMuted.withAlpha(100),
                        fontSize: isMob ? 10 : ar.small)),
              ),
          ],
        ),
      );
    }

    // على الهاتف: بطاقات بدل جدول
    if (isMob) {
      return ListView.builder(
        padding: EdgeInsets.all(8),
        itemCount: _statementLines.length,
        itemBuilder: (_, i) => _buildMobileStatementCard(i),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(ar.spaceXL),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - ar.spaceXL * 2),
          child: Container(
            decoration: BoxDecoration(
              color: AccountingTheme.bgCard,
              borderRadius: BorderRadius.circular(ar.cardRadius),
              border: Border.all(color: Colors.black, width: 1.2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ar.cardRadius),
              child: Table(
                columnWidths: {
                  0: const FixedColumnWidth(50), // #
                  1: const FixedColumnWidth(75), // النوع
                  2: const FixedColumnWidth(110), // التاريخ
                  3: const FlexColumnWidth(), // البيان
                  4: const FixedColumnWidth(120), // مدين
                  5: const FixedColumnWidth(120), // دائن
                  6: const FixedColumnWidth(130), // الرصيد
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                      color: AccountingTheme.borderColor.withAlpha(80)),
                ),
                children: [
                  // رأس الجدول
                  TableRow(
                    decoration: BoxDecoration(
                      color: AccountingTheme.bgSidebar,
                    ),
                    children: [
                      _th('#'),
                      _th('النوع'),
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
        ),
      ),
    );
  }

  /// بطاقة حركة للهاتف
  Widget _buildMobileStatementCard(int index) {
    final line = _statementLines[index];
    final entryNum = line['EntryNumber']?.toString() ?? '';
    final dateStr = line['EntryDate']?.toString() ?? '';
    final desc = (line['Description']?.toString().isNotEmpty == true
                ? line['Description']
                : line['EntryDescription'])
            ?.toString() ??
        '';
    final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
    final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();
    final running = _calcRunning(index);

    String formattedDate = '';
    try {
      final dt = DateTime.parse(dateStr);
      formattedDate = _displayDateFmt.format(dt);
    } catch (_) {
      formattedDate = dateStr.length > 10 ? dateStr.substring(0, 10) : dateStr;
    }

    return InkWell(
      onTap: () => _showTransactionDetail(line, index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black, width: 1.2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(10),
                blurRadius: 4,
                offset: Offset(0, 1)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصف الأول: رقم + تاريخ + رصيد
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AccountingTheme.neonBlue.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('#${index + 1}',
                      style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.neonBlue)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _txColor(debit, credit)
                        .withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _txColor(debit, credit)
                          .withAlpha(60),
                    ),
                  ),
                  child: Text(
                    _txLabel(debit, credit),
                    style: GoogleFonts.cairo(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: _txColor(debit, credit)),
                  ),
                ),
                const Spacer(),
                Icon(Icons.calendar_today,
                    size: 10, color: AccountingTheme.textMuted),
                const SizedBox(width: 3),
                Text(formattedDate,
                    style: GoogleFonts.cairo(
                        fontSize: 10, color: AccountingTheme.textMuted)),
              ],
            ),
            // البيان
            if (desc.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(desc,
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: AccountingTheme.textPrimary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            const SizedBox(height: 8),
            // الصف الثاني: مدين + دائن + رصيد
            Row(
              children: [
                // مدين
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: debit > 0
                          ? AccountingTheme.danger.withAlpha(15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black, width: 1.0),
                    ),
                    child: Column(
                      children: [
                        Text('مدين',
                            style: GoogleFonts.cairo(
                                fontSize: 8,
                                color: AccountingTheme.danger.withAlpha(150))),
                        Text(debit > 0 ? _fmt(debit) : '-',
                            style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: debit > 0
                                    ? AccountingTheme.danger
                                    : AccountingTheme.textMuted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // دائن
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: credit > 0
                          ? AccountingTheme.success.withAlpha(15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black, width: 1.0),
                    ),
                    child: Column(
                      children: [
                        Text('دائن',
                            style: GoogleFonts.cairo(
                                fontSize: 8,
                                color: AccountingTheme.success.withAlpha(150))),
                        Text(credit > 0 ? _fmt(credit) : '-',
                            style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: credit > 0
                                    ? AccountingTheme.success
                                    : AccountingTheme.textMuted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // الرصيد
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: (running == 0
                              ? AccountingTheme.textMuted
                              : (running > 0
                                  ? AccountingTheme.danger
                                  : AccountingTheme.success))
                          .withAlpha(15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.black, width: 1.0),
                    ),
                    child: Column(
                      children: [
                        Text('الرصيد',
                            style: GoogleFonts.cairo(
                                fontSize: 8, color: AccountingTheme.textMuted)),
                        Text(_fmt(running.abs()),
                            style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: running == 0
                                    ? AccountingTheme.textMuted
                                    : (running > 0
                                        ? AccountingTheme.danger
                                        : AccountingTheme.success))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// عرض تفاصيل الحركة — يفتح القيد الكامل للتعديل
  void _showTransactionDetail(dynamic line, int index) {
    final entryId =
        line['JournalEntryId']?.toString() ?? line['EntryId']?.toString() ?? '';
    if (entryId.isEmpty || entryId == '00000000-0000-0000-0000-000000000000') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد قيد مرتبط بهذه الحركة'), backgroundColor: AccountingTheme.warning),
      );
      return;
    }
    _showEntryEditDialog(entryId);
  }

  /// فتح dialog تعديل القيد الكامل
  Future<void> _showEntryEditDialog(String entryId) async {
    // جلب القيد الكامل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: AccountingTheme.accent)),
    );

    try {
      final result = await AccountingService.instance.getJournalEntry(entryId);
      if (!mounted) return;
      Navigator.pop(context); // إغلاق loading

      if (result['success'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'خطأ'), backgroundColor: AccountingTheme.danger),
        );
        return;
      }

      final entry = result['data'] as Map<String, dynamic>;
      _showFullEntryDialog(entry);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AccountingTheme.danger),
        );
      }
    }
  }

  void _showFullEntryDialog(Map<String, dynamic> entry) {
    final descCtrl = TextEditingController(text: entry['Description'] ?? '');
    final notesCtrl = TextEditingController(text: entry['Notes'] ?? '');
    final entryNum = entry['EntryNumber']?.toString() ?? '';
    final entryId = entry['Id']?.toString() ?? '';
    final status = entry['Status']?.toString() ?? 'Draft';
    final isPosted = status == 'Posted';

    final lines = <Map<String, dynamic>>[];
    for (final l in ((entry['Lines'] as List?) ?? [])) {
      lines.add({
        'accountId': l['AccountId']?.toString() ?? '',
        'accountLabel': '${l['AccountCode'] ?? ''} - ${l['AccountName'] ?? ''}',
        'debit': ((l['DebitAmount'] ?? 0) as num).toDouble(),
        'credit': ((l['CreditAmount'] ?? 0) as num).toDouble(),
        'desc': l['Description']?.toString() ?? '',
      });
    }

    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          final totalDebit = lines.fold<double>(0, (s, l) => s + (l['debit'] as double));
          final totalCredit = lines.fold<double>(0, (s, l) => s + (l['credit'] as double));
          final isBalanced = totalDebit > 0 && (totalDebit - totalCredit).abs() < 0.01;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              backgroundColor: AccountingTheme.bgCard,
              insetPadding: EdgeInsets.symmetric(
                horizontal: context.accR.isMobile ? 12 : MediaQuery.of(context).size.width * 0.15,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.edit_note, color: AccountingTheme.neonBlue, size: 24),
                        const SizedBox(width: 8),
                        Text('تعديل القيد', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Text('#$entryNum', style: GoogleFonts.cairo(fontSize: 13, color: AccountingTheme.neonBlue)),
                        if (isPosted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AccountingTheme.success.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('مرحل', style: GoogleFonts.cairo(fontSize: 10, color: AccountingTheme.success, fontWeight: FontWeight.bold)),
                          ),
                        ],
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                  ),
                  // Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: descCtrl,
                            style: const TextStyle(color: AccountingTheme.textPrimary),
                            decoration: InputDecoration(
                              labelText: 'وصف القيد',
                              labelStyle: const TextStyle(color: AccountingTheme.textMuted),
                              filled: true, fillColor: AccountingTheme.bgCardHover,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // أسطر القيد
                          ...lines.asMap().entries.map((e) {
                            final i = e.key;
                            final l = e.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AccountingTheme.bgCardHover,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AccountingTheme.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Text('${i + 1}', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.textMuted)),
                                  const SizedBox(width: 8),
                                  Expanded(flex: 3, child: Text(l['accountLabel'] ?? '', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.textPrimary))),
                                  const SizedBox(width: 8),
                                  SizedBox(width: 100, child: Text(l['debit'] > 0 ? _fmt(l['debit']) : '-', textAlign: TextAlign.center, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: l['debit'] > 0 ? AccountingTheme.success : AccountingTheme.textMuted))),
                                  const SizedBox(width: 8),
                                  SizedBox(width: 100, child: Text(l['credit'] > 0 ? _fmt(l['credit']) : '-', textAlign: TextAlign.center, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: l['credit'] > 0 ? AccountingTheme.danger : AccountingTheme.textMuted))),
                                  const SizedBox(width: 8),
                                  Expanded(flex: 2, child: Text(l['desc'] ?? '', style: GoogleFonts.cairo(fontSize: 11, color: AccountingTheme.textSecondary))),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          // ملخص
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isBalanced ? AccountingTheme.success.withAlpha(15) : AccountingTheme.warning.withAlpha(20),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isBalanced ? AccountingTheme.success.withAlpha(60) : AccountingTheme.warning.withAlpha(60)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(isBalanced ? '✓ متوازن' : '⚠ غير متوازن', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: isBalanced ? AccountingTheme.success : AccountingTheme.warning)),
                                Text('مدين: ${_fmt(totalDebit)}', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.success)),
                                Text('دائن: ${_fmt(totalCredit)}', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.danger)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: notesCtrl,
                            style: const TextStyle(color: AccountingTheme.textPrimary),
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: 'ملاحظات',
                              labelStyle: const TextStyle(color: AccountingTheme.textMuted),
                              filled: true, fillColor: AccountingTheme.bgCardHover,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Footer
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AccountingTheme.borderColor)),
                    ),
                    child: Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: isSaving ? null : () async {
                            setDState(() => isSaving = true);
                            final updateResult = await AccountingService.instance.updateJournalEntry(entryId, {
                              'Description': descCtrl.text.trim(),
                              'Notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                            });
                            setDState(() => isSaving = false);
                            if (updateResult['success'] == true) {
                              if (mounted) Navigator.pop(ctx);
                              if (_selectedAccount != null) _loadStatement(_selectedAccount!, resetDates: false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم حفظ التعديلات'), backgroundColor: AccountingTheme.success),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(updateResult['message'] ?? 'خطأ'), backgroundColor: AccountingTheme.danger),
                              );
                            }
                          },
                          icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
                          label: Text('حفظ التعديلات', style: GoogleFonts.cairo()),
                          style: ElevatedButton.styleFrom(backgroundColor: AccountingTheme.neonGreen, foregroundColor: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo(color: AccountingTheme.textMuted))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _translateStatus(String status) {
    const map = {
      'Draft': 'مسودة',
      'Posted': 'مرحّل',
      'Voided': 'ملغي',
      'Approved': 'معتمد',
    };
    return map[status] ?? status;
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
        _tdTap('${index + 1}', line, index, align: TextAlign.center),
        // صرف / قبض badge
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showTransactionDetail(line, index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _txColor(debit, credit).withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _txColor(debit, credit).withAlpha(120),
                  ),
                ),
                child: Text(
                  _txLabel(debit, credit),
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _txColor(debit, credit),
                  ),
                ),
              ),
            ),
          ),
        ),
        _tdTap(formattedDate, line, index, align: TextAlign.center),
        _tdTap(desc, line, index),
        _tdTap(debit > 0 ? _fmt(debit) : '-', line, index,
            color:
                debit > 0 ? AccountingTheme.danger : AccountingTheme.textMuted,
            align: TextAlign.center),
        _tdTap(credit > 0 ? _fmt(credit) : '-', line, index,
            color: credit > 0
                ? AccountingTheme.success
                : AccountingTheme.textMuted,
            align: TextAlign.center),
        _tdTap(
            '${_fmt(running.abs())} ${running > 0 ? 'مدين' : (running < 0 ? 'دائن' : '')}',
            line,
            index,
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
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(text,
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(
            fontSize: context.accR.small,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          )),
    );
  }

  Widget _td(String text,
      {Color? color, TextAlign align = TextAlign.start, bool bold = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(text,
          textAlign: align,
          style: GoogleFonts.cairo(
            fontSize: context.accR.small,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: color ?? AccountingTheme.textPrimary,
          )),
    );
  }

  /// خلية جدول قابلة للنقر
  Widget _tdTap(String text, dynamic line, int index,
      {Color? color, TextAlign align = TextAlign.start, bool bold = false}) {
    return GestureDetector(
      onTap: () => _showTransactionDetail(line, index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(text,
            textAlign: align,
            style: GoogleFonts.cairo(
              fontSize: context.accR.small,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AccountingTheme.textPrimary,
            )),
      ),
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

  /// تصنيف العملية حسب نوع الحساب
  /// الأصول والمصروفات: مدين = قبض (زيادة)، دائن = صرف (نقص)
  /// الالتزامات والإيرادات وحقوق الملكية: العكس
  String _txLabel(double debit, double credit) {
    final type = _statementAccount['AccountType']?.toString() ?? '';
    final isAssetOrExpense = (type == 'Assets' || type == 'Expenses');
    if (isAssetOrExpense) {
      return debit > 0 ? 'قبض' : 'صرف';
    } else {
      return debit > 0 ? 'صرف' : 'قبض';
    }
  }

  /// لون العملية حسب نوع الحساب
  Color _txColor(double debit, double credit) {
    return _txLabel(debit, credit) == 'قبض'
        ? AccountingTheme.success
        : AccountingTheme.danger;
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

/// رسام زخرفة الزوايا
class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..lineTo(0, 0)
      ..lineTo(size.width * 0.5, 0);
    canvas.drawPath(path, paint);

    // نقطة زخرفية
    final dotPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
        Offset(size.width * 0.15, size.height * 0.15), 2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
