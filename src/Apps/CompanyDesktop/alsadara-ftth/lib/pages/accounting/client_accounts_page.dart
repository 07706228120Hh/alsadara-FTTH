import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة كشف الحسابات - عرض جميع الحسابات الفرعية مع كشف حساب مفصّل
class ClientAccountsPage extends StatefulWidget {
  final String? companyId;
  final String? initialAccountId;

  const ClientAccountsPage({super.key, this.companyId, this.initialAccountId});

  @override
  State<ClientAccountsPage> createState() => _ClientAccountsPageState();
}

class _ClientAccountsPageState extends State<ClientAccountsPage> {
  // ─── الحسابات ───
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _allAccounts = [];
  List<Map<String, dynamic>> _allAccountsRaw = []; // كل الحسابات بما فيها الأب
  String _searchQuery = '';
  String _searchMode = 'accounts'; // 'accounts' أو 'journals'

  // ─── فلاتر البحث المتقدم ───
  String? _selectedAccountType; // Assets, Liabilities, etc.
  String? _selectedParentId; // فلتر حسب المجموعة الأب
  String _balanceFilter = 'all'; // all, debit, credit, zero
  bool _showFilters = true; // إظهار/إخفاء لوحة الفلاتر

  // ─── كشف الحساب المحدد ───
  Map<String, dynamic>? _selectedAccount;
  bool _isLoadingStatement = false;
  List<dynamic> _statementLines = [];
  Map<String, dynamic> _statementSummary = {};
  Map<String, dynamic> _statementAccount = {};

  // ─── بحث القيود ───
  List<Map<String, dynamic>> _journalSearchResults = [];
  bool _isSearchingJournals = false;
  String _lastJournalQuery = '';

  // ─── فلتر التاريخ ───
  DateTime? _fromDate;
  DateTime? _toDate;

  // ─── فلتر وترتيب كشف الحساب ───
  String _stmtTypeFilter = 'all'; // all, receipt, payment (قبض/صرف)
  String _stmtSearchQuery = ''; // بحث في القيود
  String? _stmtSortColumn; // 'date', 'type'
  bool _stmtSortAsc = true;

  final _dateFmt = DateFormat('yyyy-MM-dd');
  final _displayDateFmt = DateFormat('HH:mm yyyy/MM/dd');
  final _searchController = TextEditingController();
  final _stmtSearchController = TextEditingController();
  final _parentSearchController = TextEditingController();
  final _parentFocusNode = FocusNode();
  final _parentLayerLink = LayerLink();
  OverlayEntry? _parentOverlay;
  final _stmtScrollController = ScrollController();

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _stmtSearchController.dispose();
    _removeParentOverlay();
    _parentSearchController.dispose();
    _parentFocusNode.dispose();
    _stmtScrollController.dispose();
    super.dispose();
  }

  void _removeParentOverlay() {
    _parentOverlay?.remove();
    _parentOverlay = null;
  }

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    _searchController.addListener(_onSearchChanged);
  }

  /// بحث مع debounce — يبحث في القيود عند توقف الكتابة
  Future<void> _onSearchChanged() async {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      if (_journalSearchResults.isNotEmpty || _isSearchingJournals) {
        setState(() { _journalSearchResults = []; _isSearchingJournals = false; });
      }
      return;
    }
    if (query == _lastJournalQuery) return;
    _lastJournalQuery = query;
    setState(() => _isSearchingJournals = true);

    // debounce 400ms
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || _searchController.text.trim() != query) return;

    try {
      final result = await AccountingService.instance.getJournalEntries(
        companyId: widget.companyId,
        pageSize: 999999,
      );
      if (!mounted || _searchController.text.trim() != query) return;
      if (result['success'] == true) {
        final items = ((result['data'] is List ? result['data'] : (result['data']?['items'] ?? result['data']?['Items'] ?? [])) as List);
        final q = query.toLowerCase();
        final matched = <Map<String, dynamic>>[];
        for (final e in items) {
          final desc = (e['Description']?.toString() ?? '').toLowerCase();
          final notes = (e['Notes']?.toString() ?? '').toLowerCase();
          final entryNum = (e['EntryNumber']?.toString() ?? '').toLowerCase();
          final amount = _fmt(((e['TotalDebit'] ?? e['TotalAmount'] ?? 0) as num).toDouble());
          final date = e['EntryDate']?.toString() ?? '';
          final linesText = ((e['Lines'] as List?) ?? []).map((l) =>
            '${l['AccountName'] ?? l['Account']?['Name'] ?? ''} ${l['Description'] ?? ''} ${_fmt(((l['DebitAmount'] ?? 0) as num).toDouble())} ${_fmt(((l['CreditAmount'] ?? 0) as num).toDouble())}'
          ).join(' ').toLowerCase();

          if (desc.contains(q) || notes.contains(q) || entryNum.contains(q) ||
              amount.contains(q) || date.contains(q) || linesText.contains(q)) {
            matched.add(Map<String, dynamic>.from(e));
          }
        }
        if (mounted) setState(() { _journalSearchResults = matched; _isSearchingJournals = false; });
      } else {
        if (mounted) setState(() => _isSearchingJournals = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isSearchingJournals = false);
    }
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
        _allAccountsRaw = raw
            .map<Map<String, dynamic>>((a) => Map<String, dynamic>.from(a))
            .toList();
        // فقط الحسابات الفرعية (leaf)
        _allAccounts = _allAccountsRaw
            .where((a) => a['IsLeaf'] == true)
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
    if (mounted) {
      setState(() => _isLoading = false);
      // فتح حساب محدد تلقائياً
      if (widget.initialAccountId != null && _allAccounts.isNotEmpty) {
        final match = _allAccounts.where((a) =>
            a['Id']?.toString() == widget.initialAccountId).firstOrNull;
        if (match != null) _loadStatement(match);
      }
    }
  }

  /// الحسابات الأب (غير leaf) للفلتر حسب المجموعة
  List<Map<String, dynamic>> get _parentAccounts {
    return _allAccountsRaw
        .where((a) => a['IsLeaf'] != true)
        .toList()
      ..sort((a, b) => (a['Code']?.toString() ?? '').compareTo(b['Code']?.toString() ?? ''));
  }

  /// هل يوجد فلتر نشط؟
  bool get _hasActiveFilter =>
      (_searchMode == 'accounts' && (_searchQuery.isNotEmpty || _selectedAccountType != null || _selectedParentId != null || _balanceFilter != 'all')) ||
      (_searchMode == 'journals' && (_searchQuery.isNotEmpty || _journalSearchResults.isNotEmpty || _isSearchingJournals));

  List<Map<String, dynamic>> get _filteredAccounts {
    var list = _allAccounts.toList();

    // فلتر نوع الحساب
    if (_selectedAccountType != null) {
      list = list.where((a) => a['AccountType']?.toString() == _selectedAccountType).toList();
    }

    // فلتر المجموعة الأب
    if (_selectedParentId != null) {
      list = list.where((a) => a['ParentAccountId']?.toString() == _selectedParentId).toList();
    }

    // فلتر الرصيد
    if (_balanceFilter == 'debit') {
      list = list.where((a) {
        final b = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
        return b > 0;
      }).toList();
    } else if (_balanceFilter == 'credit') {
      list = list.where((a) {
        final b = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
        return b < 0;
      }).toList();
    } else if (_balanceFilter == 'zero') {
      list = list.where((a) {
        final b = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
        return b == 0;
      }).toList();
    }

    // فلتر البحث النصي
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((a) {
        final name = (a['Name']?.toString() ?? '').toLowerCase();
        final code = (a['Code']?.toString() ?? '').toLowerCase();
        return name.contains(q) || code.contains(q);
      }).toList();
    }

    return list;
  }

  Future<void> _loadStatement(Map<String, dynamic> account,
      {bool resetDates = true}) async {
    final accountId = account['Id']?.toString();
    if (accountId == null) return;
    // إذا التواريخ محددة من لوحة الفلاتر لا تعيد تصفيرها
    final keepDates = _fromDate != null || _toDate != null;
    setState(() {
      _selectedAccount = account;
      _isLoadingStatement = true;
      _statementLines = [];
      _statementSummary = {};
      _statementAccount = {};
      if (resetDates && !keepDates) {
        // الافتراضي: من أول الشهر الحالي إلى اليوم
        final now = DateTime.now();
        _fromDate = DateTime(now.year, now.month, 1);
        _toDate = DateTime(now.year, now.month, now.day);
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

  /// حركات الكشف مع الفلترة والترتيب
  List<dynamic> get _processedStatementLines {
    var lines = _statementLines.toList();

    // فلتر النوع
    if (_stmtTypeFilter != 'all') {
      lines = lines.where((line) {
        final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
        final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();
        final label = _txLabel(debit, credit);
        if (_stmtTypeFilter == 'receipt') return label == 'قبض';
        if (_stmtTypeFilter == 'payment') return label == 'صرف';
        return true;
      }).toList();
    }

    // بحث نصي في كل حقول القيد
    if (_stmtSearchQuery.isNotEmpty) {
      final q = _stmtSearchQuery.toLowerCase();
      lines = lines.where((line) {
        final desc = (line['Description']?.toString() ?? '').toLowerCase();
        final entryDesc = (line['EntryDescription']?.toString() ?? '').toLowerCase();
        final entryNum = (line['EntryNumber']?.toString() ?? '').toLowerCase();
        final entryId = (line['JournalEntryId']?.toString() ?? '').toLowerCase();
        final dateStr = line['EntryDate']?.toString() ?? '';
        final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
        final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();
        final debitStr = _fmt(debit);
        final creditStr = _fmt(credit);
        final origIdx = _statementLines.indexOf(line);
        final running = origIdx >= 0 ? _calcRunning(origIdx) : 0.0;
        final runningStr = _fmt(running.abs());
        final typeLabel = _txLabel(debit, credit);

        String formattedDate = '';
        try {
          final dt = DateTime.parse(dateStr).toLocal();
          formattedDate = _displayDateFmt.format(dt);
        } catch (_) {}

        return desc.contains(q) ||
            entryDesc.contains(q) ||
            entryNum.contains(q) ||
            entryId.contains(q) ||
            dateStr.contains(q) ||
            formattedDate.contains(q) ||
            debitStr.contains(q) ||
            creditStr.contains(q) ||
            runningStr.contains(q) ||
            typeLabel.contains(q);
      }).toList();
    }

    // ترتيب
    if (_stmtSortColumn != null) {
      lines.sort((a, b) {
        int cmp = 0;
        if (_stmtSortColumn == 'date') {
          final dA = a['EntryDate']?.toString() ?? '';
          final dB = b['EntryDate']?.toString() ?? '';
          cmp = dA.compareTo(dB);
        } else if (_stmtSortColumn == 'type') {
          final dA = ((a['DebitAmount'] ?? 0) as num).toDouble();
          final cA = ((a['CreditAmount'] ?? 0) as num).toDouble();
          final dB = ((b['DebitAmount'] ?? 0) as num).toDouble();
          final cB = ((b['CreditAmount'] ?? 0) as num).toDouble();
          cmp = _txLabel(dA, cA).compareTo(_txLabel(dB, cB));
        }
        return _stmtSortAsc ? cmp : -cmp;
      });
    }

    return lines;
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
        backgroundColor: const Color(0xFFF0F2F8),
        body: SafeArea(
          child: Container(
            margin: isMob ? const EdgeInsets.all(6) : const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isMob ? 16 : 20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3498DB).withAlpha(12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isMob ? 16 : 20),
              child: Column(
                children: [
                  _buildToolbar(),
                  _buildSearchBar(),
                  if (_selectedAccount == null && _searchMode == 'accounts')
                    _buildQuickFilters(),
                  if (_selectedAccount != null) ...[
                    _buildDateFilter(),
                    _buildStatementSummaryBar(),
                    Expanded(child: _buildStatementTable()),
                  ] else ...[
                    if (_searchMode == 'journals') ...[
                      if (_hasActiveFilter) ...[
                        _buildJournalFilterSummary(),
                        Expanded(child: _buildJournalResults()),
                      ] else ...[
                        Expanded(child: _buildSearchPrompt()),
                      ],
                    ] else ...[
                      if (_hasActiveFilter) ...[
                        _buildFilterSummary(),
                        Expanded(child: _buildAccountList()),
                      ] else ...[
                        Expanded(child: _buildSearchPrompt()),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
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
        margin: EdgeInsets.fromLTRB(hPad, 12, hPad, 8),
        padding: EdgeInsets.symmetric(
            horizontal: isMob ? 12 : 18, vertical: isMob ? 10 : 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF3498DB).withAlpha(8),
              const Color(0xFF8E44AD).withAlpha(5),
              Colors.white,
            ],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3498DB).withAlpha(30)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3498DB).withAlpha(8),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isMob ? 8 : 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3498DB), Color(0xFF2980B9)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3498DB).withAlpha(40),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.receipt_long_rounded,
                  size: isMob ? 16 : 20, color: Colors.white),
            ),
            SizedBox(width: isMob ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.cairo(
                          fontSize: isMob ? 14 : 17,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1A1A2E)),
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3498DB).withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('كود: $code',
                            style: GoogleFonts.cairo(
                                fontSize: isMob ? 10 : 11,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF3498DB))),
                      ),
                      SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _typeColor(type).withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(_translateType(type),
                            style: GoogleFonts.cairo(
                                fontSize: isMob ? 10 : 11,
                                fontWeight: FontWeight.w600,
                                color: _typeColor(type))),
                      ),
                      SizedBox(width: 6),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: isMob ? 6 : 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2ECC71).withAlpha(15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${_statementLines.length} حركة',
                            style: GoogleFonts.cairo(
                                fontSize: isMob ? 10 : 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2ECC71))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // وضع البحث — مع زر التبديل
    final isJournalMode = _searchMode == 'journals';
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 8),
      child: Row(
        children: [
          // ─── زر التبديل ───
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2C3E50), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _searchModeBtn('حسابات', Icons.account_balance_wallet_outlined, !isJournalMode, () {
                  setState(() { _searchMode = 'accounts'; _journalSearchResults = []; });
                }),
                _searchModeBtn('قيود', Icons.receipt_long_outlined, isJournalMode, () {
                  setState(() { _searchMode = 'journals'; });
                  _onSearchChanged();
                }),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // ─── حقل البحث ───
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE0E6ED), width: 1.5),
              ),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.cairo(
                    fontSize: isMob ? 14 : 15,
                    color: AccountingTheme.textPrimary),
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: isJournalMode ? 'ابحث في القيود...' : 'ابحث عن حساب بالاسم أو الكود...',
                  hintStyle: GoogleFonts.cairo(
                      fontSize: isMob ? 13 : 14,
                      color: const Color(0xFFADB5BD)),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(right: 12, left: 8),
                    child: Icon(Icons.search_rounded,
                        size: isMob ? 22 : 24, color: const Color(0xFF3498DB)),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() { _searchQuery = ''; _journalSearchResults = []; });
                          },
                          child: Container(
                            margin: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE74C3C).withAlpha(15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.close_rounded,
                                size: isMob ? 18 : 20,
                                color: const Color(0xFFE74C3C)),
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: isMob ? 12 : 20, vertical: isMob ? 12 : 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // لوحة الفلاتر المتقدمة
  // ═══════════════════════════════════════════
  Widget _buildAdvancedFilters() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    final hPad = isMob ? 10.0 : 24.0;

    return Container(
      margin: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
      padding: EdgeInsets.all(isMob ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E6ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── صف 1: نوع الحساب ───
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: const Color(0xFF3498DB).withAlpha(12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.category_rounded, size: isMob ? 14 : 16, color: const Color(0xFF3498DB)),
              ),
              SizedBox(width: isMob ? 6 : 10),
              Text('التصنيف:', style: GoogleFonts.cairo(fontSize: isMob ? 11 : 12, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50))),
              SizedBox(width: isMob ? 8 : 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('الكل', _selectedAccountType == null && _balanceFilter == 'all', () => setState(() { _selectedAccountType = null; _balanceFilter = 'all'; })),
                      SizedBox(width: isMob ? 4 : 6),
                      _filterChip('مدين', _balanceFilter == 'debit', () => setState(() => _balanceFilter = _balanceFilter == 'debit' ? 'all' : 'debit'), color: const Color(0xFFE74C3C)),
                      SizedBox(width: isMob ? 4 : 6),
                      _filterChip('دائن', _balanceFilter == 'credit', () => setState(() => _balanceFilter = _balanceFilter == 'credit' ? 'all' : 'credit'), color: const Color(0xFF2ECC71)),
                      SizedBox(width: isMob ? 6 : 10),
                      Container(width: 1.5, height: 22, decoration: BoxDecoration(color: const Color(0xFFE0E6ED), borderRadius: BorderRadius.circular(1))),
                      SizedBox(width: isMob ? 6 : 10),
                      _filterChip('أصول', _selectedAccountType == 'Assets', () => setState(() => _selectedAccountType = _selectedAccountType == 'Assets' ? null : 'Assets'), color: Colors.blue, icon: Icons.business_center_outlined),
                      SizedBox(width: isMob ? 4 : 6),
                      _filterChip('التزامات', _selectedAccountType == 'Liabilities', () => setState(() => _selectedAccountType = _selectedAccountType == 'Liabilities' ? null : 'Liabilities'), color: Colors.orange, icon: Icons.account_balance_outlined),
                      SizedBox(width: isMob ? 4 : 6),
                      _filterChip('حقوق ملكية', _selectedAccountType == 'Equity', () => setState(() => _selectedAccountType = _selectedAccountType == 'Equity' ? null : 'Equity'), color: Colors.purple, icon: Icons.shield_outlined),
                      SizedBox(width: isMob ? 4 : 6),
                      _filterChip('إيرادات', _selectedAccountType == 'Revenue', () => setState(() => _selectedAccountType = _selectedAccountType == 'Revenue' ? null : 'Revenue'), color: Colors.green, icon: Icons.trending_up_rounded),
                      SizedBox(width: isMob ? 4 : 6),
                      _filterChip('مصروفات', _selectedAccountType == 'Expenses', () => setState(() => _selectedAccountType = _selectedAccountType == 'Expenses' ? null : 'Expenses'), color: Colors.red, icon: Icons.trending_down_rounded),
                    ],
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMob ? 10 : 12),
          // ─── صف 2: المجموعة الأب + فلتر الرصيد ───
          Wrap(
            spacing: isMob ? 8 : 12,
            runSpacing: isMob ? 8 : 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildParentGroupDropdown(isMob),
              _buildDateRangeFilter(isMob),
              if (_hasActiveFilter)
                Material(
                  color: const Color(0xFFE74C3C).withAlpha(10),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: () => setState(() {
                      _selectedAccountType = null;
                      _selectedParentId = null;
                      _balanceFilter = 'all';
                      _fromDate = null;
                      _toDate = null;
                      _searchQuery = '';
                      _searchController.clear();
                    }),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: isMob ? 10 : 12, vertical: isMob ? 6 : 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.clear_all_rounded, size: isMob ? 14 : 16, color: const Color(0xFFE74C3C)),
                          SizedBox(width: 4),
                          Text('مسح الكل', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, fontWeight: FontWeight.w600, color: const Color(0xFFE74C3C))),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// chip فلتر
  Widget _filterChip(String label, bool selected, VoidCallback onTap, {Color? color, IconData? icon}) {
    final isMob = context.accR.isMobile;
    final chipColor = color ?? const Color(0xFF3498DB);
    return Material(
      color: selected ? chipColor.withAlpha(18) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isMob ? 10 : 12, vertical: isMob ? 5 : 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? chipColor.withAlpha(100) : const Color(0xFFDDE2E8),
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: isMob ? 12 : 14, color: selected ? chipColor : const Color(0xFF95A5A6)),
                SizedBox(width: 4),
              ],
              Text(label, style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : 11,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? chipColor : const Color(0xFF5D6D7E),
              )),
            ],
          ),
        ),
      ),
    );
  }

  /// حقل بحث وتصفية المجموعة الأب — inline autocomplete
  Widget _buildParentGroupDropdown(bool isMob) {
    return CompositedTransformTarget(
      link: _parentLayerLink,
      child: Container(
        constraints: BoxConstraints(maxWidth: isMob ? 200 : 250),
        height: isMob ? 34 : 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2C3E50), width: 1.2),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _parentSearchController,
                focusNode: _parentFocusNode,
                style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, color: AccountingTheme.textPrimary),
                onChanged: (_) => _showParentOverlay(),
                onTap: () => _showParentOverlay(),
                decoration: InputDecoration(
                  hintText: 'المجموعة...',
                  hintStyle: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, color: AccountingTheme.textMuted),
                  prefixIcon: Icon(Icons.folder_outlined, size: isMob ? 14 : 16, color: const Color(0xFF2C3E50)),
                  prefixIconConstraints: BoxConstraints(minWidth: isMob ? 28 : 32),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: isMob ? 6 : 7),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_selectedParentId != null)
              GestureDetector(
                onTap: () {
                  _parentSearchController.clear();
                  _removeParentOverlay();
                  setState(() => _selectedParentId = null);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.close, size: isMob ? 13 : 15, color: AccountingTheme.danger),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showParentOverlay() {
    _removeParentOverlay();
    final query = _parentSearchController.text.toLowerCase();
    var parents = _parentAccounts;
    if (_selectedAccountType != null) {
      parents = parents.where((a) => a['AccountType']?.toString() == _selectedAccountType).toList();
    }
    if (query.isNotEmpty) {
      parents = parents.where((p) {
        final name = (p['Name']?.toString() ?? '').toLowerCase();
        final code = (p['Code']?.toString() ?? '').toLowerCase();
        return name.contains(query) || code.contains(query);
      }).toList();
    }

    final isMob = context.accR.isMobile;
    final overlay = Overlay.of(context);

    // حساب عرض حقل البحث لمطابقة القائمة المنسدلة
    double fieldWidth = isMob ? 200 : 250;
    final renderBox = _parentFocusNode.context?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      fieldWidth = renderBox.size.width;
    }

    _parentOverlay = OverlayEntry(
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            // طبقة شفافة للإغلاق عند الضغط خارجاً
            Positioned.fill(
              child: GestureDetector(
                onTap: () => _removeParentOverlay(),
                behavior: HitTestBehavior.translucent,
              ),
            ),
            // القائمة المنسدلة
            CompositedTransformFollower(
              link: _parentLayerLink,
              showWhenUnlinked: false,
              offset: Offset(0, isMob ? 34 : 36),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                shadowColor: Colors.black26,
                child: Container(
                  width: fieldWidth,
                  constraints: BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE0E6ED)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        // "كل المجموعات"
                        InkWell(
                          onTap: () {
                            _parentSearchController.clear();
                            _removeParentOverlay();
                            _parentFocusNode.unfocus();
                            setState(() => _selectedParentId = null);
                          },
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedParentId == null ? AccountingTheme.neonBlue.withAlpha(15) : null,
                              border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
                            ),
                            child: Text('كل المجموعات', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600,
                                color: _selectedParentId == null ? AccountingTheme.neonBlue : AccountingTheme.textPrimary)),
                          ),
                        ),
                        ...parents.map((p) {
                          final id = p['Id']?.toString();
                          final isSel = _selectedParentId == id;
                          return InkWell(
                            onTap: () {
                              _parentSearchController.text = '${p['Code']} - ${p['Name']}';
                              _removeParentOverlay();
                              _parentFocusNode.unfocus();
                              setState(() => _selectedParentId = id);
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSel ? AccountingTheme.neonBlue.withAlpha(15) : null,
                                border: Border(bottom: BorderSide(color: AccountingTheme.borderColor.withAlpha(50))),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: isSel ? AccountingTheme.neonBlue.withAlpha(25) : AccountingTheme.bgPrimary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(p['Code']?.toString() ?? '', style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: isSel ? AccountingTheme.neonBlue : AccountingTheme.textSecondary)),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(child: Text(p['Name']?.toString() ?? '', style: GoogleFonts.cairo(fontSize: 11, color: isSel ? AccountingTheme.neonBlue : AccountingTheme.textPrimary), overflow: TextOverflow.ellipsis)),
                                  if (isSel) Icon(Icons.check_circle, size: 14, color: AccountingTheme.neonBlue),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (parents.isEmpty)
                          Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('لا توجد نتائج', textAlign: TextAlign.center, style: GoogleFonts.cairo(fontSize: 11, color: AccountingTheme.textMuted)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    overlay.insert(_parentOverlay!);
  }

  /// dropdown فلتر الرصيد
  Widget _buildBalanceFilterDropdown(bool isMob) {
    return Container(
      constraints: BoxConstraints(maxWidth: isMob ? 130 : 150),
      padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 10),
      decoration: BoxDecoration(
        color: AccountingTheme.bgPrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black87, width: 1.2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _balanceFilter,
          isExpanded: true,
          isDense: true,
          style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, color: AccountingTheme.textPrimary),
          icon: Icon(Icons.keyboard_arrow_down, size: isMob ? 16 : 18, color: AccountingTheme.textMuted),
          items: [
            DropdownMenuItem(value: 'all', child: Row(children: [
              Icon(Icons.account_balance_wallet_outlined, size: isMob ? 13 : 15, color: AccountingTheme.textMuted),
              SizedBox(width: 4),
              Text('كل الأرصدة', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11)),
            ])),
            DropdownMenuItem(value: 'debit', child: Row(children: [
              Icon(Icons.arrow_upward, size: isMob ? 13 : 15, color: AccountingTheme.danger),
              SizedBox(width: 4),
              Text('مدين فقط', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, color: AccountingTheme.danger)),
            ])),
            DropdownMenuItem(value: 'credit', child: Row(children: [
              Icon(Icons.arrow_downward, size: isMob ? 13 : 15, color: AccountingTheme.success),
              SizedBox(width: 4),
              Text('دائن فقط', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, color: AccountingTheme.success)),
            ])),
            DropdownMenuItem(value: 'zero', child: Row(children: [
              Icon(Icons.horizontal_rule, size: isMob ? 13 : 15, color: AccountingTheme.textMuted),
              SizedBox(width: 4),
              Text('رصيد صفر', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11)),
            ])),
          ],
          onChanged: (v) => setState(() => _balanceFilter = v ?? 'all'),
        ),
      ),
    );
  }

  /// فلتر الفترة الزمنية — حقلين منفصلين (من) و (إلى)
  Widget _buildDateRangeFilter(bool isMob) {
    final dateFmtShort = DateFormat('yyyy/MM/dd');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ─── حقل "من" ───
        InkWell(
          onTap: () => _pickFilterDate(true),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: isMob ? 34 : 36,
            padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2C3E50), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 14, color: const Color(0xFF2C3E50)),
                SizedBox(width: 6),
                Text(
                  _fromDate != null ? dateFmtShort.format(_fromDate!) : 'من',
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 10 : 11,
                    color: _fromDate != null ? const Color(0xFF2C3E50) : AccountingTheme.textMuted,
                    fontWeight: _fromDate != null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (_fromDate != null) ...[
                  SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => setState(() { _fromDate = null; }),
                    child: Icon(Icons.close, size: 13, color: AccountingTheme.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(width: 6),
        // ─── حقل "إلى" ───
        InkWell(
          onTap: () => _pickFilterDate(false),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: isMob ? 34 : 36,
            padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2C3E50), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 14, color: const Color(0xFF2C3E50)),
                SizedBox(width: 6),
                Text(
                  _toDate != null ? dateFmtShort.format(_toDate!) : 'إلى',
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 10 : 11,
                    color: _toDate != null ? const Color(0xFF2C3E50) : AccountingTheme.textMuted,
                    fontWeight: _toDate != null ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (_toDate != null) ...[
                  SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => setState(() { _toDate = null; }),
                    child: Icon(Icons.close, size: 13, color: AccountingTheme.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickFilterDate(bool isFrom) async {
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
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  /// شريط ملخص الفلاتر النشطة + عدد النتائج
  Widget _buildFilterSummary() {
    final ar = context.accR;
    final isMob = ar.isMobile;
    final hPad = isMob ? 10.0 : 24.0;
    final count = _filteredAccounts.length;

    return Container(
      margin: EdgeInsets.fromLTRB(hPad, 2, hPad, 6),
      padding: EdgeInsets.symmetric(horizontal: isMob ? 10 : 14, vertical: isMob ? 6 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3498DB).withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3498DB).withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list_rounded, size: isMob ? 14 : 16, color: AccountingTheme.neonBlue),
          SizedBox(width: 6),
          Text('نتائج البحث:', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, color: AccountingTheme.textSecondary)),
          SizedBox(width: 4),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: AccountingTheme.neonBlue.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count حساب', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, fontWeight: FontWeight.bold, color: AccountingTheme.neonBlue)),
          ),
          Spacer(),
          // إجمالي الأرصدة
          ..._buildTotalBalances(isMob),
        ],
      ),
    );
  }

  List<Widget> _buildTotalBalances(bool isMob) {
    final accounts = _filteredAccounts;
    double totalDebit = 0, totalCredit = 0;
    for (final a in accounts) {
      final b = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
      if (b > 0) totalDebit += b;
      if (b < 0) totalCredit += b.abs();
    }
    return [
      if (totalDebit > 0) ...[
        Text('مدين: ${_fmt(totalDebit)}', style: GoogleFonts.cairo(fontSize: isMob ? 9 : 10, fontWeight: FontWeight.bold, color: AccountingTheme.danger)),
        SizedBox(width: 8),
      ],
      if (totalCredit > 0)
        Text('دائن: ${_fmt(totalCredit)}', style: GoogleFonts.cairo(fontSize: isMob ? 9 : 10, fontWeight: FontWeight.bold, color: AccountingTheme.success)),
    ];
  }

  /// أزرار فلترة سريعة — تظهر فوق الحالة الفارغة
  Widget _buildQuickFilters() {
    final isMob = context.accR.isMobile;
    final hPad = isMob ? 10.0 : 24.0;
    final noFilter = _selectedAccountType == null && _balanceFilter == 'all';
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 8),
      child: Row(
        children: [
          // ─── الأزرار السريعة (قابلة للتمرير) ───
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _quickFilterButton('الكل', Icons.apps_rounded, const Color(0xFF3498DB), () {
                    setState(() { _selectedAccountType = null; _balanceFilter = 'all'; _selectedParentId = null; _fromDate = null; _toDate = null; _parentSearchController.clear(); });
                  }, selected: noFilter),
                  SizedBox(width: 6),
                  _quickFilterButton('مدين', Icons.arrow_upward_rounded, const Color(0xFFE74C3C), () {
                    setState(() { _balanceFilter = _balanceFilter == 'debit' ? 'all' : 'debit'; });
                  }, selected: _balanceFilter == 'debit'),
                  SizedBox(width: 6),
                  _quickFilterButton('دائن', Icons.arrow_downward_rounded, const Color(0xFF2ECC71), () {
                    setState(() { _balanceFilter = _balanceFilter == 'credit' ? 'all' : 'credit'; });
                  }, selected: _balanceFilter == 'credit'),
                  SizedBox(width: 10),
                  Container(width: 1.5, height: 28, decoration: BoxDecoration(color: const Color(0xFFE0E6ED), borderRadius: BorderRadius.circular(1))),
                  SizedBox(width: 10),
                  _quickFilterButton('أصول', Icons.business_center_outlined, Colors.blue, () {
                    setState(() { _selectedAccountType = _selectedAccountType == 'Assets' ? null : 'Assets'; });
                  }, selected: _selectedAccountType == 'Assets'),
                  SizedBox(width: 6),
                  _quickFilterButton('إيرادات', Icons.trending_up_rounded, Colors.green, () {
                    setState(() { _selectedAccountType = _selectedAccountType == 'Revenue' ? null : 'Revenue'; });
                  }, selected: _selectedAccountType == 'Revenue'),
                  SizedBox(width: 6),
                  _quickFilterButton('مصروفات', Icons.trending_down_rounded, Colors.red, () {
                    setState(() { _selectedAccountType = _selectedAccountType == 'Expenses' ? null : 'Expenses'; });
                  }, selected: _selectedAccountType == 'Expenses'),
                  SizedBox(width: 6),
                  _quickFilterButton('التزامات', Icons.account_balance_outlined, Colors.orange, () {
                    setState(() { _selectedAccountType = _selectedAccountType == 'Liabilities' ? null : 'Liabilities'; });
                  }, selected: _selectedAccountType == 'Liabilities'),
                  SizedBox(width: 6),
                  _quickFilterButton('حقوق ملكية', Icons.shield_outlined, Colors.purple, () {
                    setState(() { _selectedAccountType = _selectedAccountType == 'Equity' ? null : 'Equity'; });
                  }, selected: _selectedAccountType == 'Equity'),
                ],
              ),
            ),
          ),
          // ─── فلتر التاريخ + المجموعة ───
          SizedBox(width: 10),
          _buildDateRangeFilter(isMob),
          SizedBox(width: 8),
          _buildParentGroupDropdown(isMob),
        ],
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
            Container(
              padding: EdgeInsets.all(isMob ? 20 : 28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF3498DB).withAlpha(12),
                    const Color(0xFF8E44AD).withAlpha(8),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: EdgeInsets.all(isMob ? 16 : 22),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF3498DB).withAlpha(20),
                      const Color(0xFF2980B9).withAlpha(15),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.account_balance_wallet_outlined,
                    size: isMob ? 36 : 48,
                    color: const Color(0xFF3498DB).withAlpha(120)),
              ),
            ),
            SizedBox(height: isMob ? 20 : 28),
            Text('ابحث عن حساب',
                style: GoogleFonts.cairo(
                    fontSize: isMob ? 18 : 22,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2C3E50))),
            SizedBox(height: isMob ? 6 : 10),
            Text('اكتب اسم أو كود الحساب، أو استخدم الفلاتر أعلاه',
                style: GoogleFonts.cairo(
                    fontSize: isMob ? 12 : 14,
                    color: const Color(0xFF95A5A6))),
          ],
        ),
      ),
    );
  }

  /// زر تبديل وضع البحث (حسابات / قيود)
  Widget _searchModeBtn(String label, IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2C3E50) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? Colors.white : const Color(0xFF5D6D7E)),
            const SizedBox(width: 5),
            Text(label, style: GoogleFonts.cairo(
              fontSize: 12, fontWeight: FontWeight.bold,
              color: active ? Colors.white : const Color(0xFF5D6D7E),
            )),
          ],
        ),
      ),
    );
  }

  /// ملخص نتائج بحث القيود
  Widget _buildJournalFilterSummary() {
    final isMob = context.accR.isMobile;
    final hPad = isMob ? 10.0 : 24.0;
    final count = _journalSearchResults.length;

    return Container(
      margin: EdgeInsets.fromLTRB(hPad, 2, hPad, 6),
      padding: EdgeInsets.symmetric(horizontal: isMob ? 10 : 14, vertical: isMob ? 6 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFF8E44AD).withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF8E44AD).withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_rounded, size: isMob ? 14 : 16, color: const Color(0xFF8E44AD)),
          const SizedBox(width: 6),
          Text('نتائج القيود:', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, color: AccountingTheme.textSecondary)),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF8E44AD).withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: _isSearchingJournals
                ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF8E44AD)))
                : Text('$count قيد', style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, fontWeight: FontWeight.bold, color: const Color(0xFF8E44AD))),
          ),
        ],
      ),
    );
  }

  /// عرض نتائج بحث القيود فقط
  Widget _buildJournalResults() {
    final isMob = context.accR.isMobile;
    final hPad = isMob ? 8.0 : 24.0;

    if (_isSearchingJournals) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8E44AD)));
    }

    if (_journalSearchResults.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: AccountingTheme.textMuted.withAlpha(60)),
            const SizedBox(height: 8),
            Text('لا توجد قيود مطابقة', style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
      itemCount: _journalSearchResults.length,
      itemBuilder: (_, i) => _buildJournalResultCard(_journalSearchResults[i]),
    );
  }

  Widget _quickFilterButton(String label, IconData icon, Color color, VoidCallback onTap, {bool selected = false}) {
    final isMob = context.accR.isMobile;
    return Material(
      color: selected ? color.withAlpha(25) : color.withAlpha(8),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isMob ? 10 : 14, vertical: isMob ? 8 : 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : const Color(0xFF2C3E50),
              width: selected ? 1.5 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: isMob ? 14 : 16, color: selected ? color : color.withAlpha(160)),
              SizedBox(width: 6),
              Text(label, style: GoogleFonts.cairo(
                  fontSize: isMob ? 11 : 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  color: selected ? color : color.withAlpha(160))),
            ],
          ),
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
          horizontal: isMob ? 12 : 24, vertical: isMob ? 10 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
      ),
      child: Row(
        children: [
          Material(
            color: Colors.white.withAlpha(20),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () {
                if (_selectedAccount != null) {
                  setState(() {
                    _selectedAccount = null;
                    _searchQuery = '';
                    _searchController.clear();
                    _stmtSearchQuery = '';
                    _stmtSearchController.clear();
                    _stmtTypeFilter = 'all';
                    _statementLines = [];
                    _statementSummary = {};
                    _statementAccount = {};
                  });
                } else {
                  Navigator.of(context).pop();
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.all(isMob ? 6 : 8),
                child: Icon(Icons.arrow_back_rounded,
                    size: isMob ? 18 : 22, color: Colors.white),
              ),
            ),
          ),
          SizedBox(width: isMob ? 10 : 16),
          Container(
            padding: EdgeInsets.all(isMob ? 8 : 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3498DB), Color(0xFF2980B9)],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF3498DB).withAlpha(60),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: isMob ? 18 : 22),
          ),
          SizedBox(width: isMob ? 10 : 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('كشف الحسابات',
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 16 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  )),
              Text('${_allAccounts.length} حساب فرعي',
                  style: GoogleFonts.cairo(
                    fontSize: isMob ? 10 : 12,
                    color: Colors.white.withAlpha(180),
                  )),
            ],
          ),
          const Spacer(),
          _toolbarButton(
            icon: Icons.refresh_rounded,
            tooltip: 'تحديث',
            onTap: () {
              _loadAccounts();
              if (_selectedAccount != null) _reloadStatement();
            },
            isMob: isMob,
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool isMob,
    bool isActive = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isActive ? Colors.white.withAlpha(30) : Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.all(isMob ? 6 : 8),
            child: Icon(icon,
                size: isMob ? 18 : 20,
                color: isActive ? const Color(0xFF3498DB) : Colors.white.withAlpha(200)),
          ),
        ),
      ),
    );
  }

  /// عرض مشترك: حسابات + قيود
  Widget _buildCombinedResults() {
    final hasJournalResults = _searchQuery.length >= 2 && (_journalSearchResults.isNotEmpty || _isSearchingJournals);
    final isMob = context.accR.isMobile;
    final hPad = isMob ? 8.0 : 24.0;

    if (!hasJournalResults) return _buildAccountList();

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
      children: [
        // ─── قسم الحسابات ───
        if (_filteredAccounts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Row(children: [
              Icon(Icons.account_balance_wallet_outlined, size: 16, color: const Color(0xFF3498DB)),
              const SizedBox(width: 6),
              Text('حسابات (${_filteredAccounts.length})', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50))),
            ]),
          ),
          ..._filteredAccounts.take(10).toList().asMap().entries.map((e) => _buildAccountCard(e.value, e.key)),
          if (_filteredAccounts.length > 10)
            Center(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('و ${_filteredAccounts.length - 10} حساب آخر...', style: GoogleFonts.cairo(fontSize: 11, color: AccountingTheme.textMuted)),
            )),
          const SizedBox(height: 12),
        ],
        // ─── قسم القيود ───
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.receipt_long_rounded, size: 16, color: const Color(0xFF8E44AD)),
            const SizedBox(width: 6),
            Text('قيود محاسبية', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF2C3E50))),
            if (_isSearchingJournals) ...[
              const SizedBox(width: 8),
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFF8E44AD))),
            ] else ...[
              const SizedBox(width: 6),
              Text('(${_journalSearchResults.length})', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.textMuted)),
            ],
          ]),
        ),
        if (_isSearchingJournals)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8E44AD))),
          )
        else if (_journalSearchResults.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: Text('لا توجد قيود مطابقة', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.textMuted))),
          )
        else
          ..._journalSearchResults.map((entry) => _buildJournalResultCard(entry)),
      ],
    );
  }

  /// بطاقة نتيجة قيد محاسبي
  Widget _buildJournalResultCard(Map<String, dynamic> entry) {
    final entryNum = entry['EntryNumber']?.toString() ?? '';
    final desc = entry['Description']?.toString() ?? '';
    final status = entry['Status']?.toString() ?? 'Draft';
    final dateStr = entry['EntryDate']?.toString() ?? '';
    final totalDebit = ((entry['TotalDebit'] ?? 0) as num).toDouble();
    final totalCredit = ((entry['TotalCredit'] ?? 0) as num).toDouble();
    final lines = (entry['Lines'] as List?) ?? [];

    String formattedDate = '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      formattedDate = _displayDateFmt.format(dt);
    } catch (_) {
      formattedDate = dateStr.length > 10 ? dateStr.substring(0, 10) : dateStr;
    }

    return InkWell(
      onTap: () {
        final id = entry['Id']?.toString() ?? '';
        if (id.isNotEmpty) _showEntryEditDialog(id);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF8E44AD).withAlpha(40)),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(4), blurRadius: 4, offset: const Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صف 1: رقم القيد + الحالة + التاريخ
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF8E44AD).withAlpha(15), borderRadius: BorderRadius.circular(6)),
                child: Text(entryNum, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF8E44AD))),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: (status == 'Posted' ? AccountingTheme.success : status == 'Voided' ? AccountingTheme.danger : AccountingTheme.warning).withAlpha(15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  status == 'Posted' ? 'مرحّل' : status == 'Voided' ? 'ملغي' : 'مسودة',
                  style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.w600,
                      color: status == 'Posted' ? AccountingTheme.success : status == 'Voided' ? AccountingTheme.danger : AccountingTheme.warning),
                ),
              ),
              const Spacer(),
              Icon(Icons.calendar_today, size: 10, color: AccountingTheme.textMuted),
              const SizedBox(width: 3),
              Text(formattedDate, style: GoogleFonts.cairo(fontSize: 10, color: AccountingTheme.textMuted)),
            ]),
            // البيان
            if (desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(desc, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF2C3E50)), maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
            // الحسابات المتأثرة
            if (lines.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: lines.take(4).map<Widget>((l) {
                    final accName = (l['AccountName'] ?? l['Account']?['Name'] ?? '').toString();
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFF0F2F8), borderRadius: BorderRadius.circular(4)),
                      child: Text(accName, style: GoogleFonts.cairo(fontSize: 9, color: const Color(0xFF5D6D7E)), overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                ),
              ),
            const SizedBox(height: 8),
            // مدين + دائن
            Row(children: [
              Text('مدين: ${_fmt(totalDebit)}', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AccountingTheme.danger)),
              const SizedBox(width: 16),
              Text('دائن: ${_fmt(totalCredit)}', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AccountingTheme.success)),
            ]),
          ],
        ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: AccountingTheme.textMuted.withAlpha(60)),
            const SizedBox(height: 8),
            Text('لا توجد نتائج', style: GoogleFonts.cairo(color: AccountingTheme.textMuted, fontSize: context.accR.financialSmall)),
          ],
        ),
      );
    }

    final ar = context.accR;
    final isMob = ar.isMobile;
    final hPad = isMob ? 6.0 : ar.spaceXL;

    // ─── الموبايل: بطاقات ───
    if (isMob) {
      return ListView.builder(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: items.length,
        itemBuilder: (context, i) => _buildAccountCard(items[i], i),
      );
    }

    // ─── ديسكتوب: جدول احترافي ───
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE0E6ED)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            children: [
              // رأس الجدول
              _buildAccountTableHeader(),
              // صفوف الحسابات
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => _buildAccountTableRow(items[i], i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// رأس الجدول
  /// فاصل عمودي للجدول
  Widget _vDivider({double height = 28, Color? color}) {
    return Container(width: 1, height: height, color: color ?? AccountingTheme.borderColor.withAlpha(120));
  }

  Widget _buildAccountTableHeader() {
    final ar = context.accR;
    final s = GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold, color: Colors.white);
    final div = Container(width: 1, height: 28, color: Colors.white.withAlpha(40));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _hCell('#', 40, s),
            div,
            _hCellExpanded('اسم الحساب', s),
            div,
            _hCell('التصنيف', 85, s),
            div,
            _hCell('المدين', 110, s),
            div,
            _hCell('الدائن', 110, s),
            div,
            _hCell('الصافي', 130, s),
            div,
            _hCell('الحالة', 55, s),
          ],
        ),
      ),
    );
  }

  Widget _hCell(String text, double w, TextStyle s) => SizedBox(width: w, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6), child: Text(text, style: s, textAlign: TextAlign.center)));
  Widget _hCellExpanded(String text, TextStyle s) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10), child: Text(text, style: s)));

  /// صف في جدول الحسابات — مع hover + خطوط فاصلة
  Widget _buildAccountTableRow(Map<String, dynamic> a, int index) {
    final ar = context.accR;
    final name = a['Name']?.toString() ?? '';
    final type = a['AccountType']?.toString() ?? '';
    final balance = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
    final debitTotal = ((a['TotalDebit'] ?? (balance > 0 ? balance : 0)) as num).toDouble();
    final creditTotal = ((a['TotalCredit'] ?? (balance < 0 ? balance.abs() : 0)) as num).toDouble();
    final isActive = a['IsActive'] ?? true;
    final bgColor = index.isEven ? Colors.white : const Color(0xFFF8FAFE);
    const divColor = Color(0xFFE8ECF0);

    return Material(
      color: bgColor,
      child: InkWell(
        onTap: () => _loadStatement(a),
        hoverColor: const Color(0xFFEBF5FF),
        splashColor: const Color(0xFF3498DB).withAlpha(20),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEF0F4))),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // #
                SizedBox(
                  width: 40,
                  child: Center(child: Text('${index + 1}', style: GoogleFonts.cairo(fontSize: ar.small, color: AccountingTheme.textMuted))),
                ),
                _vDivider(height: double.infinity, color: divColor),
                // اسم الحساب
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    child: Text(name, overflow: TextOverflow.ellipsis, style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.w600, color: AccountingTheme.textPrimary)),
                  ),
                ),
                _vDivider(height: double.infinity, color: divColor),
                // التصنيف
                SizedBox(
                  width: 85,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _typeColor(type).withAlpha(15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_translateType(type), style: GoogleFonts.cairo(fontSize: ar.small - 1, fontWeight: FontWeight.w600, color: _typeColor(type))),
                    ),
                  ),
                ),
                _vDivider(height: double.infinity, color: divColor),
                // المدين
                SizedBox(
                  width: 110,
                  child: Center(
                    child: Text(debitTotal > 0 ? _fmt(debitTotal) : '-',
                        style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold, color: debitTotal > 0 ? AccountingTheme.danger : AccountingTheme.textMuted)),
                  ),
                ),
                _vDivider(height: double.infinity, color: divColor),
                // الدائن
                SizedBox(
                  width: 110,
                  child: Center(
                    child: Text(creditTotal > 0 ? _fmt(creditTotal) : '-',
                        style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold, color: creditTotal > 0 ? AccountingTheme.success : AccountingTheme.textMuted)),
                  ),
                ),
                _vDivider(height: double.infinity, color: divColor),
                // الصافي
                SizedBox(
                  width: 130,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (balance == 0 ? AccountingTheme.textMuted : (balance > 0 ? AccountingTheme.danger : AccountingTheme.success)).withAlpha(12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        balance == 0 ? '0' : '${_fmt(balance.abs())} ${balance > 0 ? 'مدين' : 'دائن'}',
                        style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold,
                            color: balance == 0 ? AccountingTheme.textMuted : (balance > 0 ? AccountingTheme.danger : AccountingTheme.success)),
                      ),
                    ),
                  ),
                ),
                _vDivider(height: double.infinity, color: divColor),
                // الحالة
                SizedBox(
                  width: 55,
                  child: Center(
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive == true ? AccountingTheme.success : AccountingTheme.danger,
                        boxShadow: [BoxShadow(color: (isActive == true ? AccountingTheme.success : AccountingTheme.danger).withAlpha(80), blurRadius: 4)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// بطاقة حساب للموبايل
  Widget _buildAccountCard(Map<String, dynamic> a, int index) {
    final code = a['Code']?.toString() ?? '';
    final name = a['Name']?.toString() ?? '';
    final type = a['AccountType']?.toString() ?? '';
    final balance = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
    final debitTotal = ((a['TotalDebit'] ?? (balance > 0 ? balance : 0)) as num).toDouble();
    final creditTotal = ((a['TotalCredit'] ?? (balance < 0 ? balance.abs() : 0)) as num).toDouble();

    return InkWell(
      onTap: () => _loadStatement(a),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E6ED)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(5),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // صف أول: رقم + كود + تصنيف
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AccountingTheme.neonBlue.withAlpha(20), borderRadius: BorderRadius.circular(6)),
                  child: Text(code, style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: AccountingTheme.neonBlue)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: _typeColor(type).withAlpha(15), borderRadius: BorderRadius.circular(4)),
                  child: Text(_translateType(type), style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.w600, color: _typeColor(type))),
                ),
                const Spacer(),
                Text('#${index + 1}', style: GoogleFonts.cairo(fontSize: 9, color: AccountingTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 6),
            // اسم الحساب
            Text(name, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: AccountingTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            // صف ثاني: مدين + دائن + صافي
            Row(
              children: [
                Expanded(child: _mobileAccountCell('المدين', debitTotal, AccountingTheme.danger)),
                const SizedBox(width: 4),
                Expanded(child: _mobileAccountCell('الدائن', creditTotal, AccountingTheme.success)),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: (balance == 0 ? AccountingTheme.textMuted : (balance > 0 ? AccountingTheme.danger : AccountingTheme.success)).withAlpha(12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE0E6ED)),
                    ),
                    child: Column(
                      children: [
                        Text('الصافي', style: GoogleFonts.cairo(fontSize: 8, color: AccountingTheme.textMuted)),
                        Text(balance == 0 ? '0' : _fmt(balance.abs()),
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold,
                                color: balance == 0 ? AccountingTheme.textMuted : (balance > 0 ? AccountingTheme.danger : AccountingTheme.success))),
                        if (balance != 0)
                          Text(balance > 0 ? 'مدين' : 'دائن',
                              style: GoogleFonts.cairo(fontSize: 8, fontWeight: FontWeight.w600,
                                  color: balance > 0 ? AccountingTheme.danger : AccountingTheme.success)),
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

  Widget _mobileAccountCell(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: value > 0 ? color.withAlpha(10) : const Color(0xFFF8FAFE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0E6ED)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.cairo(fontSize: 8, color: color.withAlpha(150))),
          Text(value > 0 ? _fmt(value) : '-',
              style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: value > 0 ? color : AccountingTheme.textMuted)),
        ],
      ),
    );
  }

  /// لون التصنيف
  Color _typeColor(String type) {
    switch (type) {
      case 'Assets': return Colors.blue;
      case 'Liabilities': return Colors.orange;
      case 'Equity': return Colors.purple;
      case 'Revenue': return Colors.green;
      case 'Expenses': return Colors.red;
      default: return AccountingTheme.textMuted;
    }
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
                const SizedBox(width: 6),
                _quickDateChip('اليوم', () {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  setState(() { _fromDate = today; _toDate = today; });
                  _reloadStatement();
                }),
                const SizedBox(width: 4),
                _quickDateChip('أمس', () {
                  final yesterday = DateTime.now().subtract(const Duration(days: 1));
                  final d = DateTime(yesterday.year, yesterday.month, yesterday.day);
                  setState(() { _fromDate = d; _toDate = d; });
                  _reloadStatement();
                }),
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
                Text('←',
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
                SizedBox(width: ar.spaceM),
                _quickDateChip('اليوم', () {
                  final now = DateTime.now();
                  final today = DateTime(now.year, now.month, now.day);
                  setState(() { _fromDate = today; _toDate = today; });
                  _reloadStatement();
                }),
                const SizedBox(width: 6),
                _quickDateChip('أمس', () {
                  final yesterday = DateTime.now().subtract(const Duration(days: 1));
                  final d = DateTime(yesterday.year, yesterday.month, yesterday.day);
                  setState(() { _fromDate = d; _toDate = d; });
                  _reloadStatement();
                }),
                const SizedBox(width: 6),
                _quickDateChip('الكل', () {
                  setState(() { _fromDate = null; _toDate = null; });
                  _reloadStatement();
                }),
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

  Widget _quickDateChip(String label, VoidCallback onTap) {
    return Material(
      color: const Color(0xFF3498DB).withAlpha(10),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2C3E50), width: 1.2),
          ),
          child: Text(label, style: GoogleFonts.cairo(fontSize: 11, color: const Color(0xFF3498DB), fontWeight: FontWeight.w600)),
        ),
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
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFF2C3E50),
              width: 1.2),
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
          horizontal: isMob ? 10 : 24, vertical: isMob ? 8 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFE),
        border: Border(
          bottom: BorderSide(color: const Color(0xFFE0E6ED)),
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
      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2C3E50), width: 1.2),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2C3E50), width: 1.2),
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

    final lines = _processedStatementLines;

    // على الهاتف: بطاقات بدل جدول
    if (isMob) {
      return Column(
        children: [
          _buildStmtFilterBar(true),
          Expanded(
            child: lines.isEmpty
                ? Center(child: Text('لا توجد نتائج', style: GoogleFonts.cairo(color: AccountingTheme.textMuted)))
                : ListView.builder(
                    padding: EdgeInsets.all(8),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => _buildMobileStatementCard(i, lines),
                  ),
          ),
        ],
      );
    }

    // ─── ديسكتوب: جدول بـ hover وخطوط فاصلة ───
    final hPad = ar.spaceXL;
    return Column(
      children: [
        _buildStmtFilterBar(false),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 8),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0E6ED)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(6),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Column(
                      children: [
                        _buildStmtTableHeader(),
                        Expanded(
                          child: lines.isEmpty
                              ? Center(child: Text('لا توجد نتائج', style: GoogleFonts.cairo(color: AccountingTheme.textMuted)))
                              : ScrollbarTheme(
                                  data: ScrollbarThemeData(
                                    thumbColor: WidgetStateProperty.all(Colors.black38),
                                    trackColor: WidgetStateProperty.all(Colors.black.withAlpha(15)),
                                    trackBorderColor: WidgetStateProperty.all(Colors.black12),
                                    thickness: WidgetStateProperty.all(8),
                                    radius: const Radius.circular(4),
                                  ),
                                  child: Scrollbar(
                                    controller: _stmtScrollController,
                                    thumbVisibility: true,
                                    trackVisibility: true,
                                    child: ListView.builder(
                                      controller: _stmtScrollController,
                                      itemCount: lines.length,
                                      itemBuilder: (_, i) {
                                        final line = lines[i];
                                        final origIdx = _statementLines.indexOf(line);
                                        final running = origIdx >= 0 ? _calcRunning(origIdx) : 0.0;
                                        final prevLine = i > 0 ? lines[i - 1] : null;
                                        return _buildStmtTableRow(i, line, running, prevLine: prevLine);
                                      },
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                // أزرار التنقل
                if (lines.length > 5)
                  Positioned(
                    left: 8,
                    bottom: 12,
                    child: Column(
                      children: [
                        _scrollNavButton(Icons.keyboard_double_arrow_up, 'الأعلى', () {
                          _stmtScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                        }),
                        const SizedBox(height: 6),
                        _scrollNavButton(Icons.keyboard_double_arrow_down, 'الأسفل', () {
                          _stmtScrollController.animateTo(
                            _stmtScrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        }),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scrollNavButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: Colors.black.withAlpha(20),
        shape: CircleBorder(side: BorderSide(color: const Color(0xFFE0E6ED))),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          hoverColor: const Color(0xFFEBF5FF),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: const Color(0xFF5D6D7E)),
          ),
        ),
      ),
    );
  }

  /// شريط فلتر القبض/الصرف
  Widget _buildStmtFilterBar(bool isMob) {
    final hPad = isMob ? 8.0 : context.accR.spaceXL;
    final hasFilter = _stmtTypeFilter != 'all' || _stmtSearchQuery.isNotEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 6),
      child: Row(
        children: [
          Icon(Icons.filter_alt_outlined, size: isMob ? 14 : 16, color: AccountingTheme.textSecondary),
          SizedBox(width: 6),
          _stmtFilterChip('الكل', _stmtTypeFilter == 'all', () => setState(() => _stmtTypeFilter = 'all')),
          SizedBox(width: isMob ? 4 : 6),
          _stmtFilterChip('قبض', _stmtTypeFilter == 'receipt', () => setState(() => _stmtTypeFilter = _stmtTypeFilter == 'receipt' ? 'all' : 'receipt'), color: AccountingTheme.success),
          SizedBox(width: isMob ? 4 : 6),
          _stmtFilterChip('صرف', _stmtTypeFilter == 'payment', () => setState(() => _stmtTypeFilter = _stmtTypeFilter == 'payment' ? 'all' : 'payment'), color: AccountingTheme.danger),
          SizedBox(width: isMob ? 8 : 14),
          // ─── مربع بحث القيود ───
          Container(
            width: isMob ? 160 : 250,
            height: isMob ? 30 : 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF2C3E50), width: 1.2),
            ),
            child: TextField(
              controller: _stmtSearchController,
              style: GoogleFonts.cairo(fontSize: isMob ? 11 : 12, color: AccountingTheme.textPrimary),
              onChanged: (v) => setState(() => _stmtSearchQuery = v),
              decoration: InputDecoration(
                hintText: 'ابحث في القيود...',
                hintStyle: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, color: const Color(0xFFADB5BD)),
                prefixIcon: Icon(Icons.search_rounded, size: isMob ? 16 : 18, color: const Color(0xFF3498DB)),
                prefixIconConstraints: BoxConstraints(minWidth: isMob ? 30 : 36),
                suffixIcon: _stmtSearchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _stmtSearchController.clear();
                          setState(() => _stmtSearchQuery = '');
                        },
                        child: Icon(Icons.close_rounded, size: isMob ? 14 : 16, color: AccountingTheme.danger),
                      )
                    : null,
                suffixIconConstraints: BoxConstraints(minWidth: isMob ? 28 : 32),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: isMob ? 6 : 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          Spacer(),
          if (hasFilter)
            Text('${_processedStatementLines.length} من ${_statementLines.length}',
                style: GoogleFonts.cairo(fontSize: isMob ? 9 : 10, color: AccountingTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _stmtFilterChip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    final isMob = context.accR.isMobile;
    final c = color ?? AccountingTheme.neonBlue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 10, vertical: isMob ? 3 : 4),
        decoration: BoxDecoration(
          color: selected ? c.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? c : const Color(0xFF2C3E50),
            width: selected ? 1.5 : 1.2,
          ),
        ),
        child: Text(label, style: GoogleFonts.cairo(fontSize: isMob ? 10 : 11, fontWeight: selected ? FontWeight.bold : FontWeight.w500, color: selected ? c : AccountingTheme.textSecondary)),
      ),
    );
  }

  /// رأس جدول الحركات — مع أزرار ترتيب
  Widget _buildStmtTableHeader() {
    final ar = context.accR;
    final s = GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold, color: Colors.white);
    const divColor = Color(0x55FFFFFF);
    const div = SizedBox(width: 1);

    Widget sortableHeader(String label, String col, double width) {
      final isActive = _stmtSortColumn == col;
      return InkWell(
        onTap: () => setState(() {
          if (_stmtSortColumn == col) {
            _stmtSortAsc = !_stmtSortAsc;
          } else {
            _stmtSortColumn = col;
            _stmtSortAsc = true;
          }
        }),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: s),
                SizedBox(width: 3),
                Icon(
                  isActive ? (_stmtSortAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                  size: 13,
                  color: isActive ? Colors.white : Colors.white.withAlpha(120),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            SizedBox(width: 42, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('#', style: s, textAlign: TextAlign.center))),
            Container(width: 1, color: divColor),
            SizedBox(width: 120, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('رقم القيد', style: s, textAlign: TextAlign.center))),
            Container(width: 1, color: divColor),
            sortableHeader('النوع', 'type', 75),
            Container(width: 1, color: divColor),
            sortableHeader('التاريخ', 'date', 110),
            Container(width: 1, color: divColor),
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), child: Text('البيان', style: s))),
            Container(width: 1, color: divColor),
            SizedBox(width: 110, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('مدين', style: s, textAlign: TextAlign.center))),
            Container(width: 1, color: divColor),
            SizedBox(width: 110, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('دائن', style: s, textAlign: TextAlign.center))),
            Container(width: 1, color: divColor),
            SizedBox(width: 130, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('الرصيد', style: s, textAlign: TextAlign.center))),
          ],
        ),
      ),
    );
  }

  /// ألوان الأيام — كل يوم يأخذ لون مختلف
  static const _dayColors = [
    Color(0xFF3498DB), // أزرق
    Color(0xFF2ECC71), // أخضر
    Color(0xFF9B59B6), // بنفسجي
    Color(0xFFE67E22), // برتقالي
    Color(0xFF1ABC9C), // فيروزي
    Color(0xFFE91E63), // وردي
    Color(0xFF795548), // بني
    Color(0xFF607D8B), // رمادي أزرق
    Color(0xFFFF5722), // أحمر برتقالي
    Color(0xFF00BCD4), // سماوي
  ];

  Color _dayColor(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final dayKey = dt.year * 10000 + dt.month * 100 + dt.day;
      return _dayColors[dayKey % _dayColors.length];
    } catch (_) {
      return _dayColors[0];
    }
  }

  /// صف حركة بـ hover + خطوط فاصلة
  String _dateOnly(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.year}-${dt.month}-${dt.day}';
    } catch (_) {
      return dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
    }
  }

  Widget _buildStmtTableRow(int index, dynamic line, double running, {dynamic prevLine}) {
    final ar = context.accR;
    final dateStr = line['EntryDate']?.toString() ?? '';
    final desc = (line['Description']?.toString().isNotEmpty == true ? line['Description'] : line['EntryDescription'])?.toString() ?? '';
    final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
    final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();

    String formattedDate = '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      formattedDate = _displayDateFmt.format(dt);
    } catch (_) {
      formattedDate = dateStr.length > 10 ? dateStr.substring(0, 10) : dateStr;
    }

    final bgColor = index.isEven ? Colors.white : const Color(0xFFF8FAFE);
    const divColor = Color(0xFFE8ECF0);

    // خط أسود فاصل بين الأيام المختلفة
    final isDayChange = prevLine != null &&
        _dateOnly(dateStr) != _dateOnly(prevLine['EntryDate']?.toString() ?? '');

    return Material(
      color: bgColor,
      child: InkWell(
        onTap: () => _showTransactionDetail(line, index),
        hoverColor: const Color(0xFFEBF5FF),
        splashColor: const Color(0xFF3498DB).withAlpha(20),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: isDayChange ? const BorderSide(color: Color(0xFF2C3E50), width: 2) : BorderSide.none,
              bottom: const BorderSide(color: Color(0xFFEEF0F4)),
            ),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                // #
                SizedBox(width: 42, child: Center(child: Text('${index + 1}', style: GoogleFonts.cairo(fontSize: ar.small, color: AccountingTheme.textMuted)))),
                _vDivider(height: double.infinity, color: divColor),
                // رقم القيد
                SizedBox(width: 120, child: Center(child: Text(
                  line['EntryNumber']?.toString() ?? '-',
                  style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.w600, color: const Color(0xFF3498DB)),
                ))),
                _vDivider(height: double.infinity, color: divColor),
                // النوع
                SizedBox(
                  width: 75,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _txColor(debit, credit).withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _txColor(debit, credit).withAlpha(120)),
                      ),
                      child: Text(_txLabel(debit, credit),
                          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: _txColor(debit, credit))),
                    ),
                  ),
                ),
                _vDivider(height: double.infinity, color: divColor),
                // التاريخ — مظلل حسب اليوم
                Container(
                  width: 110,
                  color: _dayColor(dateStr).withAlpha(18),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(formattedDate, style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.w600, color: _dayColor(dateStr).withAlpha(220))),
                    ),
                  ),
                ),
                _vDivider(height: double.infinity, color: divColor),
                // البيان
                Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Text(desc, style: GoogleFonts.cairo(fontSize: ar.small, color: AccountingTheme.textPrimary), overflow: TextOverflow.ellipsis))),
                _vDivider(height: double.infinity, color: divColor),
                // مدين
                SizedBox(width: 110, child: Center(child: Text(debit > 0 ? _fmt(debit) : '-',
                    style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold, color: debit > 0 ? AccountingTheme.danger : AccountingTheme.textMuted)))),
                _vDivider(height: double.infinity, color: divColor),
                // دائن
                SizedBox(width: 110, child: Center(child: Text(credit > 0 ? _fmt(credit) : '-',
                    style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold, color: credit > 0 ? AccountingTheme.success : AccountingTheme.textMuted)))),
                _vDivider(height: double.infinity, color: divColor),
                // الرصيد
                SizedBox(
                  width: 130,
                  child: Center(
                    child: Text(
                      '${_fmt(running.abs())} ${running > 0 ? 'مدين' : (running < 0 ? 'دائن' : '')}',
                      style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold,
                          color: running == 0 ? AccountingTheme.textMuted : (running > 0 ? AccountingTheme.danger : AccountingTheme.success)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// بطاقة حركة للهاتف
  Widget _buildMobileStatementCard(int index, [List<dynamic>? sourceLines]) {
    final src = sourceLines ?? _statementLines;
    final line = src[index];
    final entryNum = line['EntryNumber']?.toString() ?? '';
    final dateStr = line['EntryDate']?.toString() ?? '';
    final desc = (line['Description']?.toString().isNotEmpty == true
                ? line['Description']
                : line['EntryDescription'])
            ?.toString() ??
        '';
    final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
    final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();
    final origIdx = _statementLines.indexOf(line);
    final running = origIdx >= 0 ? _calcRunning(origIdx) : 0.0;

    String formattedDate = '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      formattedDate = _displayDateFmt.format(dt);
    } catch (_) {
      formattedDate = dateStr.length > 10 ? dateStr.substring(0, 10) : dateStr;
    }

    return InkWell(
      onTap: () => _showTransactionDetail(line, index),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E6ED)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(5),
                blurRadius: 6,
                offset: Offset(0, 2)),
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
                          ? AccountingTheme.danger.withAlpha(10)
                          : const Color(0xFFF8FAFE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE0E6ED)),
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
                          ? AccountingTheme.success.withAlpha(10)
                          : const Color(0xFFF8FAFE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE0E6ED)),
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
                          .withAlpha(10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE0E6ED)),
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

  /// حذف القيد من داخل الـ dialog
  void _confirmDeleteEntryFromDialog(BuildContext dialogCtx, Map<String, dynamic> entry) {
    showDialog(
      context: dialogCtx,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تأكيد الحذف', style: GoogleFonts.cairo(color: AccountingTheme.danger, fontWeight: FontWeight.bold)),
          content: Text(
            'هل تريد حذف القيد "${entry['Description'] ?? 'قيد #${entry['EntryNumber']}'}"؟\nسيتم عكس أرصدة الحسابات المتأثرة.',
            style: GoogleFonts.cairo(color: AccountingTheme.textPrimary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AccountingTheme.danger, foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx); // إغلاق التأكيد
                final result = await AccountingService.instance.deleteJournalEntry(entry['Id'].toString());
                if (!mounted) return;
                if (result['success'] == true) {
                  Navigator.pop(dialogCtx); // إغلاق dialog التعديل
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف القيد بنجاح'), backgroundColor: AccountingTheme.success),
                  );
                  if (_selectedAccount != null) _loadStatement(_selectedAccount!, resetDates: false);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result['message'] ?? 'خطأ في الحذف'), backgroundColor: AccountingTheme.danger),
                  );
                }
              },
              child: Text('حذف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullEntryDialog(Map<String, dynamic> entry) {
    final status = entry['Status']?.toString() ?? 'Draft';
    final isVoided = status == 'Voided';
    final effectiveReadOnly = isVoided;

    final descCtrl = TextEditingController(text: entry['Description'] ?? '');
    final notesCtrl = TextEditingController(text: entry['Notes'] ?? '');
    DateTime entryDate = DateTime.tryParse(entry['EntryDate']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    TimeOfDay entryTime = TimeOfDay(hour: entryDate.hour, minute: entryDate.minute);

    final lines = <Map<String, dynamic>>[];
    for (final l in ((entry['Lines'] as List?) ?? [])) {
      lines.add({
        'accountId': l['AccountId']?.toString() ?? '',
        'accountName': l['AccountName']?.toString() ?? l['Account']?['Name']?.toString() ?? '',
        'debitCtrl': TextEditingController(text: ((l['DebitAmount'] ?? 0) as num).toDouble() > 0 ? _fmt(((l['DebitAmount'] ?? 0) as num).toDouble()) : ''),
        'creditCtrl': TextEditingController(text: ((l['CreditAmount'] ?? 0) as num).toDouble() > 0 ? _fmt(((l['CreditAmount'] ?? 0) as num).toDouble()) : ''),
        'descCtrl': TextEditingController(text: l['Description']?.toString() ?? ''),
      });
    }

    List<Map<String, dynamic>> accounts = [];
    bool accountsLoaded = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          if (!accountsLoaded && !effectiveReadOnly) {
            accountsLoaded = true;
            AccountingService.instance.getAccounts(companyId: widget.companyId).then((res) {
              if (res['success'] == true && ctx.mounted) {
                final data = res['data'];
                final list = data is List ? data : (data is Map ? (data['items'] ?? []) as List : []);
                final leafAccounts = <Map<String, dynamic>>[];
                for (final a in list) {
                  if (a['IsLeaf'] == true || a['isLeaf'] == true) {
                    leafAccounts.add({
                      'id': (a['Id'] ?? a['id'])?.toString() ?? '',
                      'name': (a['Name'] ?? a['name'] ?? '').toString(),
                      'code': (a['Code'] ?? a['code'])?.toString() ?? '',
                    });
                  }
                }
                leafAccounts.sort((a, b) => a['code'].compareTo(b['code']));
                setDState(() => accounts = leafAccounts);
              }
            });
          }

          double totalDebit = 0, totalCredit = 0;
          for (final l in lines) {
            totalDebit += double.tryParse((l['debitCtrl'] as TextEditingController).text.replaceAll(',', '')) ?? 0;
            totalCredit += double.tryParse((l['creditCtrl'] as TextEditingController).text.replaceAll(',', '')) ?? 0;
          }
          final isBalanced = (totalDebit - totalCredit).abs() < 0.01;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              backgroundColor: AccountingTheme.bgCard,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 750, maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // العنوان
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        color: AccountingTheme.bgCardHover,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit_note, color: AccountingTheme.info, size: 22),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(effectiveReadOnly ? 'تفاصيل القيد' : 'تعديل القيد', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold)),
                            Text('#${entry['EntryNumber'] ?? ''}', style: GoogleFonts.cairo(color: AccountingTheme.neonBlue, fontSize: 12)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: (status == 'Posted' ? AccountingTheme.success : AccountingTheme.warning).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(status == 'Posted' ? 'مرحّل' : status == 'Voided' ? 'ملغي' : 'مسودة',
                                style: GoogleFonts.cairo(color: status == 'Posted' ? AccountingTheme.success : AccountingTheme.warning, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          // زر حذف القيد
                          if (!effectiveReadOnly)
                            IconButton(
                              onPressed: () => _confirmDeleteEntryFromDialog(ctx, entry),
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: 'حذف القيد',
                              style: IconButton.styleFrom(foregroundColor: AccountingTheme.danger),
                            ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 20)),
                        ],
                      ),
                    ),
                    // المحتوى
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(flex: 2, child: TextField(
                              controller: descCtrl, readOnly: effectiveReadOnly,
                              style: const TextStyle(color: AccountingTheme.textPrimary, fontSize: 13),
                              decoration: InputDecoration(labelText: 'الوصف', filled: true, fillColor: AccountingTheme.bgCardHover, isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                            )),
                            const SizedBox(width: 12),
                            Expanded(child: InkWell(
                              onTap: effectiveReadOnly ? null : () async {
                                final picked = await showDatePicker(context: ctx, initialDate: entryDate, firstDate: DateTime(2020), lastDate: DateTime(2030));
                                if (picked != null) setDState(() => entryDate = DateTime(picked.year, picked.month, picked.day, entryTime.hour, entryTime.minute));
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(labelText: 'التاريخ', filled: true, fillColor: AccountingTheme.bgCardHover, isDense: true,
                                    suffixIcon: const Icon(Icons.calendar_today, size: 16),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                                child: Text('${entryDate.year}/${entryDate.month.toString().padLeft(2, '0')}/${entryDate.day.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            )),
                            const SizedBox(width: 8),
                            SizedBox(width: 110, child: InkWell(
                              onTap: effectiveReadOnly ? null : () async {
                                final picked = await showTimePicker(context: ctx, initialTime: entryTime);
                                if (picked != null) setDState(() {
                                  entryTime = picked;
                                  entryDate = DateTime(entryDate.year, entryDate.month, entryDate.day, picked.hour, picked.minute);
                                });
                              },
                              child: InputDecorator(
                                decoration: InputDecoration(labelText: 'الوقت', filled: true, fillColor: AccountingTheme.bgCardHover, isDense: true,
                                    suffixIcon: const Icon(Icons.access_time, size: 16),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                                child: Text('${entryTime.hour.toString().padLeft(2, '0')}:${entryTime.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              ),
                            )),
                          ]),
                          const SizedBox(height: 12),
                          TextField(controller: notesCtrl, readOnly: effectiveReadOnly, maxLines: 2,
                              style: const TextStyle(fontSize: 13),
                              decoration: InputDecoration(labelText: 'ملاحظات', filled: true, fillColor: AccountingTheme.bgCardHover, isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none))),
                          if (entry['ReferenceType'] != null || entry['ReferenceId'] != null) ...[
                            const SizedBox(height: 8),
                            Wrap(spacing: 16, children: [
                              if (entry['ReferenceType'] != null) Text('النوع: ${_refTypeLabel(entry['ReferenceType'])}', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.textMuted)),
                              if (entry['ReferenceId'] != null) Text('مرجع: ${entry['ReferenceId']}', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.neonBlue)),
                            ]),
                          ],
                          const SizedBox(height: 18),
                          const Divider(color: AccountingTheme.borderColor),
                          const SizedBox(height: 10),
                          Row(children: [
                            Text('أسطر القيد', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold)),
                            const Spacer(),
                            if (!effectiveReadOnly) TextButton.icon(
                              onPressed: () => setDState(() => lines.add({
                                'accountId': '', 'accountName': '',
                                'debitCtrl': TextEditingController(), 'creditCtrl': TextEditingController(), 'descCtrl': TextEditingController(),
                              })),
                              icon: const Icon(Icons.add_circle_outline, size: 16),
                              label: Text('إضافة سطر', style: GoogleFonts.cairo(fontSize: 12)),
                              style: TextButton.styleFrom(foregroundColor: AccountingTheme.neonGreen),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          // رأس الجدول
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(color: AccountingTheme.bgCardHover, borderRadius: BorderRadius.circular(6)),
                            child: Row(children: [
                              const SizedBox(width: 30),
                              Expanded(flex: 3, child: Text('الحساب', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold))),
                              SizedBox(width: 100, child: Center(child: Text('مدين', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AccountingTheme.success)))),
                              SizedBox(width: 100, child: Center(child: Text('دائن', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: AccountingTheme.danger)))),
                              Expanded(flex: 2, child: Text('البيان', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold))),
                              if (!effectiveReadOnly) const SizedBox(width: 32),
                            ]),
                          ),
                          const SizedBox(height: 4),
                          ...lines.asMap().entries.map((e) {
                            final i = e.key; final l = e.value;
                            final accId = l['accountId'] as String;
                            final accName = accId.isNotEmpty ? (accounts.where((a) => a['id'] == accId).firstOrNull?['name'] ?? l['accountName'] ?? '') : l['accountName'] ?? '';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: i % 2 == 0 ? Colors.white : AccountingTheme.bgCardHover,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AccountingTheme.borderColor.withOpacity(0.5)),
                              ),
                              child: Row(children: [
                                SizedBox(width: 30, child: Text('${i + 1}', style: GoogleFonts.cairo(fontSize: 11, color: AccountingTheme.neonBlue, fontWeight: FontWeight.bold))),
                                Expanded(flex: 3, child: effectiveReadOnly
                                    ? Text(accName, style: GoogleFonts.cairo(fontSize: 12))
                                    : Autocomplete<Map<String, dynamic>>(
                                        initialValue: TextEditingValue(text: accName),
                                        optionsBuilder: (textEditingValue) {
                                          if (accounts.isEmpty) return const Iterable.empty();
                                          final q = textEditingValue.text.toLowerCase();
                                          if (q.isEmpty) return accounts.take(20);
                                          return accounts.where((a) =>
                                            (a['name'] as String).toLowerCase().contains(q) ||
                                            (a['code'] as String).toLowerCase().contains(q));
                                        },
                                        displayStringForOption: (a) => a['name'] as String,
                                        onSelected: (a) => setDState(() {
                                          l['accountId'] = a['id'] as String;
                                          l['accountName'] = a['name'] as String;
                                        }),
                                        optionsViewBuilder: (ctx2, onSelected, options) {
                                          return Align(
                                            alignment: Alignment.topRight,
                                            child: Material(
                                              elevation: 8,
                                              borderRadius: BorderRadius.circular(8),
                                              child: Container(
                                                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 350),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFF2C3E50)),
                                                ),
                                                child: ListView.builder(
                                                  padding: EdgeInsets.zero,
                                                  shrinkWrap: true,
                                                  itemCount: options.length,
                                                  itemBuilder: (_, idx) {
                                                    final opt = options.elementAt(idx);
                                                    return InkWell(
                                                      onTap: () => onSelected(opt),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                                        decoration: BoxDecoration(
                                                          border: Border(bottom: BorderSide(color: AccountingTheme.borderColor.withAlpha(60))),
                                                        ),
                                                        child: Row(children: [
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                            decoration: BoxDecoration(color: const Color(0xFF3498DB).withAlpha(15), borderRadius: BorderRadius.circular(4)),
                                                            child: Text(opt['code'] as String, style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF3498DB))),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Expanded(child: Text(opt['name'] as String, style: GoogleFonts.cairo(fontSize: 11), overflow: TextOverflow.ellipsis)),
                                                        ]),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        fieldViewBuilder: (ctx2, textCtrl, focusNode, onFieldSubmitted) {
                                          return TextField(
                                            controller: textCtrl,
                                            focusNode: focusNode,
                                            style: GoogleFonts.cairo(fontSize: 11, color: Colors.black),
                                            decoration: InputDecoration(
                                              hintText: 'اكتب للبحث...',
                                              hintStyle: GoogleFonts.cairo(fontSize: 10, color: AccountingTheme.textMuted),
                                              isDense: true,
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AccountingTheme.borderColor)),
                                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AccountingTheme.borderColor)),
                                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF3498DB), width: 1.5)),
                                            ),
                                          );
                                        },
                                      )),
                                const SizedBox(width: 4),
                                SizedBox(width: 100, child: TextField(
                                    controller: l['debitCtrl'], readOnly: effectiveReadOnly,
                                    keyboardType: TextInputType.number, textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AccountingTheme.success),
                                    decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), filled: true, fillColor: AccountingTheme.success.withOpacity(0.05),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none)),
                                    onChanged: (v) {
                                      final raw = v.replaceAll(',', '');
                                      final num = double.tryParse(raw);
                                      if (num != null && num > 0) {
                                        final formatted = _fmt(num);
                                        if (formatted != v) {
                                          (l['debitCtrl'] as TextEditingController).value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
                                        }
                                      }
                                      setDState(() {});
                                    })),
                                const SizedBox(width: 4),
                                SizedBox(width: 100, child: TextField(
                                    controller: l['creditCtrl'], readOnly: effectiveReadOnly,
                                    keyboardType: TextInputType.number, textAlign: TextAlign.center,
                                    style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: AccountingTheme.danger),
                                    decoration: InputDecoration(isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6), filled: true, fillColor: AccountingTheme.danger.withOpacity(0.05),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none)),
                                    onChanged: (v) {
                                      final raw = v.replaceAll(',', '');
                                      final num = double.tryParse(raw);
                                      if (num != null && num > 0) {
                                        final formatted = _fmt(num);
                                        if (formatted != v) {
                                          (l['creditCtrl'] as TextEditingController).value = TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
                                        }
                                      }
                                      setDState(() {});
                                    })),
                                const SizedBox(width: 4),
                                Expanded(flex: 2, child: TextField(
                                    controller: l['descCtrl'], readOnly: effectiveReadOnly,
                                    style: GoogleFonts.cairo(fontSize: 11),
                                    decoration: InputDecoration(hintText: 'بيان السطر', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AccountingTheme.borderColor))))),
                                if (!effectiveReadOnly)
                                  InkWell(
                                    onTap: lines.length > 1 ? () => setDState(() => lines.removeAt(i)) : null,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Icon(Icons.close_rounded, size: 16,
                                          color: lines.length > 1 ? AccountingTheme.danger : AccountingTheme.textMuted.withAlpha(80)),
                                    ),
                                  ),
                              ]),
                            );
                          }),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isBalanced ? AccountingTheme.success.withOpacity(0.08) : AccountingTheme.warning.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isBalanced ? AccountingTheme.success.withOpacity(0.3) : AccountingTheme.warning.withOpacity(0.3)),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(isBalanced ? '✓ القيد متوازن' : '⚠ غير متوازن', style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: isBalanced ? AccountingTheme.success : AccountingTheme.warning)),
                              Text('مدين: ${_fmt(totalDebit)}', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.success, fontWeight: FontWeight.bold)),
                              Text('دائن: ${_fmt(totalCredit)}', style: GoogleFonts.cairo(fontSize: 12, color: AccountingTheme.danger, fontWeight: FontWeight.bold)),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                    // زر الحفظ
                    if (!effectiveReadOnly) Container(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AccountingTheme.borderColor))),
                      child: Row(children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo(color: AccountingTheme.textMuted))),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: isSaving || !isBalanced ? null : () async {
                            for (final l in lines) { if ((l['accountId'] as String).isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب اختيار حساب لكل سطر'), backgroundColor: AccountingTheme.warning)); return; } }
                            setDState(() => isSaving = true);
                            final linesDtos = <Map<String, dynamic>>[];
                            for (final l in lines) {
                              linesDtos.add({
                                'AccountId': l['accountId'],
                                'DebitAmount': double.tryParse((l['debitCtrl'] as TextEditingController).text.replaceAll(',', '')) ?? 0.0,
                                'CreditAmount': double.tryParse((l['creditCtrl'] as TextEditingController).text.replaceAll(',', '')) ?? 0.0,
                                'Description': (l['descCtrl'] as TextEditingController).text,
                              });
                            }
                            final body = {
                              'Description': descCtrl.text,
                              'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                              'EntryDate': entryDate.toIso8601String(),
                              'Lines': linesDtos,
                            };
                            debugPrint('📝 [JE-UPDATE] id=${entry['Id']}, lines=${linesDtos.length}');
                            for (int i = 0; i < linesDtos.length; i++) {
                              debugPrint('   line[$i]: acc=${linesDtos[i]['AccountId']}, D=${linesDtos[i]['DebitAmount']}, C=${linesDtos[i]['CreditAmount']}');
                            }
                            final result = await AccountingService.instance.updateJournalEntry(entry['Id'].toString(), body);
                            debugPrint('📝 [JE-UPDATE] result: success=${result['success']}, msg=${result['message']}, code=${result['statusCode']}');
                            if (!ctx.mounted) return;
                            setDState(() => isSaving = false);
                            if (result['success'] == true) {
                              Navigator.pop(ctx);
                              if (_selectedAccount != null) _loadStatement(_selectedAccount!, resetDates: false);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث القيد بنجاح'), backgroundColor: AccountingTheme.success));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'خطأ'), backgroundColor: AccountingTheme.danger));
                            }
                          },
                          icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
                          label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ التعديلات', style: GoogleFonts.cairo(fontSize: 13)),
                          style: ElevatedButton.styleFrom(backgroundColor: AccountingTheme.info, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _refTypeLabel(dynamic type) {
    final t = type is int ? type : int.tryParse(type?.toString() ?? '') ?? 0;
    const map = {0: 'يدوي', 1: 'قبض', 2: 'راتب', 3: 'صندوق', 4: 'سحب', 5: 'إيداع', 6: 'بوليصة', 7: 'صرف', 8: 'وكيل', 9: 'خدمة', 10: 'تجديد', 11: 'تسليم كاش', 12: 'تحصيل آجل'};
    return map[t] ?? type.toString();
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
      final dt = DateTime.parse(dateStr).toLocal();
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
      'Liabilities': 'التزامات',
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
