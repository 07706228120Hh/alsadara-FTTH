import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة عمليات المحفظة — عرض شامل لجميع معاملات المحفظة من خادم FTTH
class WalletTransactionsPage extends StatefulWidget {
  final String? companyId;
  const WalletTransactionsPage({super.key, this.companyId});

  @override
  State<WalletTransactionsPage> createState() => _WalletTransactionsPageState();
}

class _WalletTransactionsPageState extends State<WalletTransactionsPage> {
  // ── حالة التحميل ──
  bool _isLoading = false;
  String? _errorMessage;
  bool _ftthAuthenticated = false;

  // ── البيانات ──
  List<_WalletTx> _allTransactions = [];
  List<_WalletTx> _filteredTransactions = [];

  // ── الفلاتر ──
  DateTime? _fromDate;
  DateTime? _toDate;
  String _dateLabel = 'اليوم + أمس';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  List<String> _selectedTypes = [];
  List<String> _selectedWalletTypes = [];
  List<String> _selectedWalletOwnerTypes = ['partner'];
  List<String> _selectedZones = [];
  String? _selectedOperator;
  bool _showFilters = true;

  // ── الترتيب ──
  int _sortColumnIndex = 0;
  bool _sortAscending = false;

  // ── ترقيم الصفحات ──
  int _rowsPerPage = 25;
  int _currentPage = 0;

  // ── قوائم مرجعية ──
  List<String> _availableOperators = [];
  List<String> _availableZones = [];

  final _currencyFormat = NumberFormat('#,###', 'ar');

  // أنواع عمليات المحفظة
  static const _walletTransactionTypes = [
    {'value': 'WALLET_TOPUP', 'label': 'شحن محفظة'},
    {'value': 'WALLET_REFUND', 'label': 'استرداد محفظة'},
    {'value': 'WALLET_TRANSFER', 'label': 'تحويل محفظة'},
    {'value': 'WALLET_TRANSFER_FEE', 'label': 'رسوم تحويل'},
    {'value': 'WALLET_REVERSAL', 'label': 'عكس محفظة'},
    {'value': 'WALLET_TRANSFER_COMMISSION', 'label': 'عمولة تحويل محفظة'},
  ];

  static const _walletTypeOptions = [
    {'value': 'Main', 'label': 'المحفظة الرئيسية'},
    {'value': 'Secondary', 'label': 'المحفظة الثانوية'},
  ];

  static const _walletOwnerTypeOptions = [
    {'value': 'partner', 'label': 'شريك'},
    {'value': 'customer', 'label': 'عميل'},
    {'value': 'agent', 'label': 'وكيل'},
    {'value': 'master', 'label': 'ماستر'},
  ];

  static String _translateType(String type) {
    const map = {
      'WALLET_TOPUP': 'شحن محفظة',
      'WALLET_REFUND': 'استرداد محفظة',
      'WALLET_TRANSFER': 'تحويل محفظة',
      'WALLET_TRANSFER_FEE': 'رسوم تحويل',
      'WALLET_REVERSAL': 'عكس محفظة',
      'WALLET_TRANSFER_COMMISSION': 'عمولة تحويل محفظة',
      'WALLET_RECHARGE': 'إعادة شحن',
      'REFUND_BALANCE': 'استرجاع رصيد',
      'DEDUCT_BALANCE': 'خصم رصيد',
      'ADJUST_BALANCE': 'تعديل رصيد',
      'REFILL_BALANCE': 'تعبئة رصيد',
    };
    return map[type] ?? type;
  }

  /// هل المبلغ إيداع (موجب من منظور المحفظة)
  static bool _isCredit(String type) {
    return const {
      'WALLET_TOPUP',
      'WALLET_RECHARGE',
      'WALLET_REFUND',
      'REFUND_BALANCE',
      'REFILL_BALANCE',
      'ADJUST_BALANCE',
    }.contains(type);
  }

  @override
  void initState() {
    super.initState();
    _setTodayAndYesterday();
    _checkFtthAuth();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════
  //  التاريخ
  // ════════════════════════════════════════════════════════════════

  void _setTodayAndYesterday() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    _fromDate = DateTime(yesterday.year, yesterday.month, yesterday.day);
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _dateLabel = 'اليوم + أمس';
  }

  void _setQuickDate(String label, DateTime from, DateTime to) {
    setState(() {
      _fromDate = from;
      _toDate = to;
      _dateLabel = label;
    });
    _loadData();
  }

  // ════════════════════════════════════════════════════════════════
  //  المصادقة
  // ════════════════════════════════════════════════════════════════

  Future<void> _checkFtthAuth() async {
    final token = await AuthService.instance.getAccessToken();
    if (mounted) {
      setState(() => _ftthAuthenticated = token != null && token.isNotEmpty);
    }
    if (_ftthAuthenticated) _loadData();
  }

  // ════════════════════════════════════════════════════════════════
  //  جلب البيانات
  // ════════════════════════════════════════════════════════════════

  Future<void> _loadData() async {
    if (!_ftthAuthenticated || !mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      DateTime from = _fromDate ?? DateTime.now().subtract(const Duration(days: 1));
      DateTime to = _toDate ?? DateTime.now();

      final utcFrom = from.toUtc();
      final utcTo = to.toUtc();
      final fromStr = '${DateFormat('yyyy-MM-ddTHH:mm:ss.SSS').format(utcFrom)}Z';
      final toStr = '${DateFormat('yyyy-MM-ddTHH:mm:ss.SSS').format(utcTo)}Z';

      List<_WalletTx> allTx = [];
      final Set<String> seenIds = {};
      int page = 1;
      const pageSize = 1000;
      bool hasMore = true;

      // أنواع المحفظة للفلترة على الخادم
      final walletTypes = [
        'WALLET_TOPUP', 'WALLET_REFUND', 'WALLET_TRANSFER',
        'WALLET_TRANSFER_FEE', 'WALLET_REVERSAL', 'WALLET_TRANSFER_COMMISSION',
      ];

      while (hasMore) {
        final params = <String>[
          'pageSize=$pageSize',
          'pageNumber=$page',
          'sortCriteria.property=occuredAt',
          'sortCriteria.direction=desc',
          'occuredAt.from=$fromStr',
          'occuredAt.to=$toStr',
          'createdAt.from=$fromStr',
          'createdAt.to=$toStr',
        ];

        // فلتر أنواع المعاملات
        for (final t in walletTypes) {
          params.add('transactionTypes=$t');
        }

        // فلتر نوع المحفظة
        for (final v in _selectedWalletTypes) {
          params.add('walletType=$v');
        }

        // فلتر مالك المحفظة
        if (_selectedWalletOwnerTypes.isNotEmpty) {
          for (final v in _selectedWalletOwnerTypes) {
            params.add('walletOwnerType=$v');
          }
        } else {
          params.add('walletOwnerType=partner');
        }

        // فلتر المناطق
        for (final v in _selectedZones) {
          params.add('zones=$v');
        }

        final url = 'https://admin.ftth.iq/api/transactions?${params.join('&')}';
        final response = await AuthService.instance.authenticatedRequest('GET', url);

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

          for (final tx in items) {
            final txId = tx['id']?.toString() ?? '';
            if (txId.isNotEmpty && !seenIds.add(txId)) continue;

            final createdBy = (tx['createdBy'] ?? '').toString().trim();
            final transactionUser = (tx['transactionUser'] ?? '').toString().trim();
            final username = (tx['username'] ?? '').toString().trim();
            final operatorName = createdBy.isNotEmpty
                ? createdBy
                : transactionUser.isNotEmpty
                    ? transactionUser
                    : username.isNotEmpty
                        ? username
                        : 'بدون منشئ';

            final amtVal = tx['transactionAmount']?['value'] ?? 0.0;
            final num amtNum = (amtVal is num) ? amtVal : double.tryParse(amtVal.toString()) ?? 0.0;
            final double amount = amtNum.toDouble();

            final remBalVal = tx['remainingBalance']?['value'] ?? 0.0;
            final double remainingBalance = (remBalVal is num)
                ? remBalVal.toDouble()
                : double.tryParse(remBalVal.toString()) ?? 0.0;

            allTx.add(_WalletTx(
              id: txId,
              type: tx['type']?.toString() ?? '',
              amount: amount,
              remainingBalance: remainingBalance,
              customerName: tx['customer']?['displayValue']?.toString() ?? '',
              customerId: tx['customer']?['id']?.toString() ?? '',
              operatorName: operatorName,
              occuredAt: tx['occuredAt']?.toString() ?? '',
              paymentMethod: tx['paymentMethod']?['displayValue']?.toString() ?? '',
              zoneId: tx['zoneId']?.toString() ?? '',
            ));
          }

          final serverTotal = data['totalCount'] ?? 0;
          if (page * pageSize >= serverTotal || items.isEmpty) {
            hasMore = false;
          } else {
            page++;
          }
        } else if (response.statusCode == 401) {
          if (mounted) {
            setState(() {
              _ftthAuthenticated = false;
              _errorMessage = 'انتهت جلسة FTTH — يرجى تسجيل الدخول مرة أخرى';
            });
          }
          return;
        } else {
          _errorMessage = 'خطأ من خادم FTTH: ${response.statusCode}';
          hasMore = false;
        }
      }

      _allTransactions = allTx;

      // استخراج المشغلين والمناطق الفريدة
      final ops = <String>{};
      final zones = <String>{};
      for (final tx in allTx) {
        if (tx.operatorName.isNotEmpty) ops.add(tx.operatorName);
        if (tx.zoneId.isNotEmpty) zones.add(tx.zoneId);
      }
      _availableOperators = ops.toList()..sort();
      _availableZones = zones.toList()..sort();

      _applyLocalFilters();
    } catch (e) {
      _errorMessage = 'خطأ في جلب بيانات المحفظة: $e';
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ════════════════════════════════════════════════════════════════
  //  التصفية المحلية
  // ════════════════════════════════════════════════════════════════

  void _applyLocalFilters() {
    var list = List<_WalletTx>.from(_allTransactions);

    // فلتر نوع العملية
    if (_selectedTypes.isNotEmpty) {
      list = list.where((tx) => _selectedTypes.contains(tx.type)).toList();
    }

    // فلتر المشغل
    if (_selectedOperator != null && _selectedOperator!.isNotEmpty) {
      list = list.where((tx) => tx.operatorName == _selectedOperator).toList();
    }

    // فلتر البحث النصي
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((tx) =>
          tx.customerName.toLowerCase().contains(q) ||
          tx.customerId.toLowerCase().contains(q) ||
          tx.operatorName.toLowerCase().contains(q)).toList();
    }

    // الترتيب
    _sortList(list);

    _filteredTransactions = list;
    _currentPage = 0;
    if (mounted) setState(() {});
  }

  void _sortList(List<_WalletTx> list) {
    list.sort((a, b) {
      int cmp;
      switch (_sortColumnIndex) {
        case 1: // التاريخ
          cmp = a.occuredAt.compareTo(b.occuredAt);
          break;
        case 2: // المشغل
          cmp = a.operatorName.compareTo(b.operatorName);
          break;
        case 3: // العميل
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case 5: // المبلغ
          cmp = a.amount.compareTo(b.amount);
          break;
        case 6: // الرصيد المتبقي
          cmp = a.remainingBalance.compareTo(b.remainingBalance);
          break;
        default:
          cmp = b.occuredAt.compareTo(a.occuredAt);
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
    _sortList(_filteredTransactions);
    setState(() {});
  }

  // ════════════════════════════════════════════════════════════════
  //  الملخصات
  // ════════════════════════════════════════════════════════════════

  int get _totalCount => _filteredTransactions.length;

  double get _totalTopup => _filteredTransactions
      .where((tx) => const {'WALLET_TOPUP', 'WALLET_RECHARGE', 'REFILL_BALANCE'}.contains(tx.type))
      .fold(0.0, (sum, tx) => sum + tx.amount.abs());

  double get _totalRefund => _filteredTransactions
      .where((tx) => const {'WALLET_REFUND', 'REFUND_BALANCE'}.contains(tx.type))
      .fold(0.0, (sum, tx) => sum + tx.amount.abs());

  double get _totalTransfer => _filteredTransactions
      .where((tx) => const {'WALLET_TRANSFER'}.contains(tx.type))
      .fold(0.0, (sum, tx) => sum + tx.amount.abs());

  double get _totalFees => _filteredTransactions
      .where((tx) => const {'WALLET_TRANSFER_FEE', 'WALLET_TRANSFER_COMMISSION'}.contains(tx.type))
      .fold(0.0, (sum, tx) => sum + tx.amount.abs());

  double get _totalPositive => _filteredTransactions
      .where((tx) => tx.amount > 0)
      .fold(0.0, (sum, tx) => sum + tx.amount);

  double get _totalNegative => _filteredTransactions
      .where((tx) => tx.amount < 0)
      .fold(0.0, (sum, tx) => sum + tx.amount.abs());

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(),
              if (_showFilters) _buildFilters(),
              _buildSummaryCards(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                                const SizedBox(height: 12),
                                Text(_errorMessage!, style: GoogleFonts.cairo(color: Colors.red.shade700)),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: _loadData,
                                  icon: const Icon(Icons.refresh),
                                  label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
                                ),
                              ],
                            ),
                          )
                        : !_ftthAuthenticated
                            ? _buildAuthPrompt()
                            : _filteredTransactions.isEmpty
                                ? Center(
                                    child: Text('لا توجد عمليات محفظة في هذه الفترة',
                                        style: GoogleFonts.cairo(color: Colors.grey.shade600, fontSize: 15)),
                                  )
                                : _buildTable(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  TOOLBAR
  // ════════════════════════════════════════════════════════════════

  Widget _buildToolbar() {
    final r = context.accR;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.spaceM, vertical: r.spaceS),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)],
      ),
      child: Row(
        children: [
          // رجوع
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 18),
            tooltip: 'رجوع',
          ),
          Icon(Icons.account_balance_wallet_rounded, color: Colors.amber.shade300, size: 22),
          SizedBox(width: r.spaceS),
          Text('عمليات المحفظة',
              style: GoogleFonts.cairo(
                  color: Colors.white, fontSize: r.headingSmall, fontWeight: FontWeight.w700)),
          const Spacer(),
          // عدد النتائج
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('${_filteredTransactions.length} عملية',
                style: GoogleFonts.cairo(color: Colors.white70, fontSize: r.small)),
          ),
          SizedBox(width: r.spaceS),
          // فلاتر
          IconButton(
            onPressed: () => setState(() => _showFilters = !_showFilters),
            icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list,
                color: Colors.white, size: 20),
            tooltip: _showFilters ? 'إخفاء الفلاتر' : 'إظهار الفلاتر',
          ),
          // تحديث
          IconButton(
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            tooltip: 'تحديث',
          ),
          // تصدير
          IconButton(
            onPressed: _filteredTransactions.isEmpty ? null : _exportToExcel,
            icon: Icon(Icons.download_rounded,
                color: _filteredTransactions.isEmpty ? Colors.white38 : Colors.greenAccent, size: 20),
            tooltip: 'تصدير Excel',
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  FILTERS
  // ════════════════════════════════════════════════════════════════

  Widget _buildFilters() {
    final r = context.accR;
    return Container(
      padding: EdgeInsets.all(r.spaceM),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // صف 1: فلاتر التاريخ السريعة
          _buildQuickDateRow(),
          SizedBox(height: r.spaceS),
          // صف 2: فلاتر متقدمة
          Wrap(
            spacing: r.spaceS,
            runSpacing: r.spaceS,
            children: [
              // بحث نصي
              SizedBox(
                width: 220,
                height: 36,
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.cairo(fontSize: r.small),
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم أو الرقم...',
                    hintStyle: GoogleFonts.cairo(fontSize: r.small, color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              _searchQuery = '';
                              _applyLocalFilters();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    _searchQuery = v;
                    _applyLocalFilters();
                  },
                ),
              ),
              // نوع العملية
              _buildMultiChipFilter(
                label: 'نوع العملية',
                options: _walletTransactionTypes,
                selected: _selectedTypes,
                onChanged: (v) {
                  _selectedTypes = v;
                  _applyLocalFilters();
                },
              ),
              // المشغل
              _buildDropdownFilter(
                label: 'المشغل',
                value: _selectedOperator,
                items: _availableOperators,
                onChanged: (v) {
                  _selectedOperator = v;
                  _applyLocalFilters();
                },
              ),
              // نوع المحفظة
              _buildMultiChipFilter(
                label: 'نوع المحفظة',
                options: _walletTypeOptions,
                selected: _selectedWalletTypes,
                onChanged: (v) {
                  _selectedWalletTypes = v;
                  _loadData();
                },
              ),
              // مالك المحفظة
              _buildMultiChipFilter(
                label: 'مالك المحفظة',
                options: _walletOwnerTypeOptions,
                selected: _selectedWalletOwnerTypes,
                onChanged: (v) {
                  _selectedWalletOwnerTypes = v;
                  _loadData();
                },
              ),
              // مسح الفلاتر
              if (_selectedTypes.isNotEmpty ||
                  _selectedOperator != null ||
                  _searchQuery.isNotEmpty ||
                  _selectedWalletTypes.isNotEmpty ||
                  _selectedWalletOwnerTypes.length != 1 ||
                  _selectedWalletOwnerTypes.first != 'partner')
                ActionChip(
                  avatar: const Icon(Icons.clear_all, size: 16),
                  label: Text('مسح الكل', style: GoogleFonts.cairo(fontSize: 11)),
                  backgroundColor: Colors.red.shade50,
                  onPressed: () {
                    _selectedTypes.clear();
                    _selectedOperator = null;
                    _searchController.clear();
                    _searchQuery = '';
                    _selectedWalletTypes.clear();
                    _selectedWalletOwnerTypes = ['partner'];
                    _loadData();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickDateRow() {
    final r = context.accR;
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    final chips = <Map<String, dynamic>>[
      {
        'label': 'اليوم + أمس',
        'from': DateTime(yesterday.year, yesterday.month, yesterday.day),
        'to': DateTime(now.year, now.month, now.day, 23, 59, 59),
      },
      {
        'label': 'اليوم',
        'from': DateTime(now.year, now.month, now.day),
        'to': DateTime(now.year, now.month, now.day, 23, 59, 59),
      },
      {
        'label': 'أمس',
        'from': DateTime(yesterday.year, yesterday.month, yesterday.day),
        'to': DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59),
      },
      {
        'label': 'آخر 7 أيام',
        'from': now.subtract(const Duration(days: 7)),
        'to': DateTime(now.year, now.month, now.day, 23, 59, 59),
      },
      {
        'label': 'هذا الشهر',
        'from': DateTime(now.year, now.month, 1),
        'to': DateTime(now.year, now.month, now.day, 23, 59, 59),
      },
    ];

    return Row(
      children: [
        Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
        SizedBox(width: r.spaceXS),
        ...chips.map((c) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: ChoiceChip(
                label: Text(c['label'],
                    style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: _dateLabel == c['label'] ? Colors.white : Colors.grey.shade700)),
                selected: _dateLabel == c['label'],
                selectedColor: const Color(0xFF1A237E),
                backgroundColor: Colors.grey.shade100,
                onSelected: (_) => _setQuickDate(c['label'], c['from'], c['to']),
                visualDensity: VisualDensity.compact,
              ),
            )),
        const SizedBox(width: 4),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 14),
          label: Text('مخصص', style: GoogleFonts.cairo(fontSize: 11)),
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
              initialDateRange: _fromDate != null && _toDate != null
                  ? DateTimeRange(start: _fromDate!, end: _toDate!)
                  : null,
              locale: const Locale('ar'),
            );
            if (picked != null && mounted) {
              _setQuickDate(
                '${DateFormat('MM/dd').format(picked.start)} - ${DateFormat('MM/dd').format(picked.end)}',
                picked.start,
                DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildMultiChipFilter({
    required String label,
    required List<Map<String, String>> options,
    required List<String> selected,
    required ValueChanged<List<String>> onChanged,
  }) {
    return PopupMenuButton<String>(
      tooltip: label,
      offset: const Offset(0, 36),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
              color: selected.isNotEmpty ? const Color(0xFF1A237E) : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
          color: selected.isNotEmpty ? const Color(0xFF1A237E).withOpacity(0.06) : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: selected.isNotEmpty ? const Color(0xFF1A237E) : Colors.grey.shade600)),
            if (selected.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${selected.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
      itemBuilder: (_) => options.map((o) {
            final isSelected = selected.contains(o['value']);
            return PopupMenuItem<String>(
              value: o['value'],
              child: Row(
                children: [
                  Icon(isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 18,
                      color: isSelected ? const Color(0xFF1A237E) : Colors.grey),
                  const SizedBox(width: 8),
                  Text(o['label']!, style: GoogleFonts.cairo(fontSize: 12)),
                ],
              ),
            );
          }).toList(),
      onSelected: (value) {
        final newList = List<String>.from(selected);
        if (newList.contains(value)) {
          newList.remove(value);
        } else {
          newList.add(value);
        }
        onChanged(newList);
      },
    );
  }

  Widget _buildDropdownFilter({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      height: 36,
      decoration: BoxDecoration(
        border: Border.all(color: value != null ? const Color(0xFF1A237E) : Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: value != null ? const Color(0xFF1A237E).withOpacity(0.06) : Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          hint: Text(label, style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600)),
          value: value,
          isDense: true,
          style: GoogleFonts.cairo(fontSize: 11, color: Colors.black87),
          items: [
            DropdownMenuItem<String>(value: null, child: Text('الكل', style: GoogleFonts.cairo(fontSize: 11))),
            ...items.map((i) =>
                DropdownMenuItem<String>(value: i, child: Text(i, style: GoogleFonts.cairo(fontSize: 11)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  SUMMARY CARDS
  // ════════════════════════════════════════════════════════════════

  Widget _buildSummaryCards() {
    final r = context.accR;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: r.spaceM, vertical: r.spaceS),
      child: Row(
        children: [
          _summaryCard('إجمالي العمليات', '$_totalCount', Icons.receipt_long, Colors.indigo),
          SizedBox(width: r.spaceS),
          _summaryCard('الوارد', _currencyFormat.format(_totalPositive), Icons.arrow_downward, Colors.green),
          SizedBox(width: r.spaceS),
          _summaryCard('الصادر', _currencyFormat.format(_totalNegative), Icons.arrow_upward, Colors.red),
          SizedBox(width: r.spaceS),
          _summaryCard('شحن', _currencyFormat.format(_totalTopup), Icons.add_circle_outline, Colors.blue),
          SizedBox(width: r.spaceS),
          _summaryCard('استرداد', _currencyFormat.format(_totalRefund), Icons.replay, Colors.orange),
          SizedBox(width: r.spaceS),
          _summaryCard('تحويل', _currencyFormat.format(_totalTransfer), Icons.swap_horiz, Colors.purple),
          if (_totalFees > 0) ...[
            SizedBox(width: r.spaceS),
            _summaryCard('رسوم', _currencyFormat.format(_totalFees), Icons.money_off, Colors.brown),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    final r = context.accR;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: r.spaceS, vertical: r.spaceS),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(r.radiusL),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: color.withOpacity(0.06), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            SizedBox(width: r.spaceXS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: GoogleFonts.cairo(
                          fontSize: r.body, fontWeight: FontWeight.w700, color: color)),
                  Text(label,
                      style: GoogleFonts.cairo(fontSize: r.caption, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  TABLE
  // ════════════════════════════════════════════════════════════════

  // نسب عرض الأعمدة (مجموعها = 1.0)
  static const _colFlex = <double>[
    0.04, // #
    0.13, // التاريخ
    0.13, // المشغل
    0.18, // العميل
    0.12, // نوع العملية
    0.12, // المبلغ
    0.12, // الرصيد المتبقي
    0.09, // طريقة الدفع
    0.07, // المنطقة
  ];

  Widget _buildTable() {
    final r = context.accR;
    final totalPages = (_filteredTransactions.length / _rowsPerPage).ceil();
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _filteredTransactions.length);
    final pageData = _filteredTransactions.sublist(startIndex, endIndex);

    const headerLabels = ['#', 'التاريخ', 'المشغل', 'العميل', 'نوع العملية', 'المبلغ', 'الرصيد المتبقي', 'طريقة الدفع', 'المنطقة'];
    // الأعمدة القابلة للترتيب
    const sortableColumns = {1, 2, 3, 5, 6};

    return Column(
      children: [
        // ── رأس الجدول ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF1A237E),
          ),
          child: Row(
            children: List.generate(headerLabels.length, (i) {
              final isSortable = sortableColumns.contains(i);
              final isSorted = _sortColumnIndex == i;
              return Expanded(
                flex: (_colFlex[i] * 100).round(),
                child: InkWell(
                  onTap: isSortable
                      ? () => _onSort(i, isSorted ? !_sortAscending : true)
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(headerLabels[i],
                            style: GoogleFonts.cairo(
                                color: Colors.white,
                                fontSize: r.small,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isSorted)
                        Icon(
                          _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                          color: Colors.amber.shade300,
                          size: 14,
                        ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        // ── صفوف البيانات ──
        Expanded(
          child: ListView.builder(
            itemCount: pageData.length,
            itemBuilder: (context, i) {
              final tx = pageData[i];
              final isPositive = tx.amount >= 0;
              final rowColor = i.isEven ? Colors.grey.shade50 : Colors.white;

              String dateStr = '';
              if (tx.occuredAt.length >= 16) {
                try {
                  final dt = DateTime.parse(tx.occuredAt).toLocal();
                  dateStr = DateFormat('yyyy/MM/dd HH:mm').format(dt);
                } catch (_) {
                  dateStr = tx.occuredAt.substring(0, 16);
                }
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: rowColor,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade200, width: 0.5)),
                ),
                child: Row(
                  children: [
                    // #
                    _cell(_colFlex[0], Text('${startIndex + i + 1}',
                        style: TextStyle(fontSize: r.small, color: Colors.grey))),
                    // التاريخ
                    _cell(_colFlex[1], Text(dateStr, style: GoogleFonts.cairo(fontSize: r.small))),
                    // المشغل
                    _cell(_colFlex[2], Text(tx.operatorName,
                        style: GoogleFonts.cairo(fontSize: r.small, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis)),
                    // العميل
                    _cell(_colFlex[3], Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tx.customerName,
                            style: GoogleFonts.cairo(fontSize: r.small),
                            overflow: TextOverflow.ellipsis),
                        if (tx.customerId.isNotEmpty)
                          Text(tx.customerId,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                              overflow: TextOverflow.ellipsis),
                      ],
                    )),
                    // نوع العملية
                    _cell(_colFlex[4], Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isCredit(tx.type) ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_translateType(tx.type),
                          style: GoogleFonts.cairo(
                              fontSize: r.small,
                              fontWeight: FontWeight.w600,
                              color: _isCredit(tx.type) ? Colors.green.shade800 : Colors.red.shade800),
                          overflow: TextOverflow.ellipsis),
                    )),
                    // المبلغ
                    _cell(_colFlex[5], Text(
                      '${isPositive ? "+" : "-"}${_currencyFormat.format(tx.amount.abs())}',
                      style: GoogleFonts.cairo(
                        fontSize: r.small,
                        fontWeight: FontWeight.w700,
                        color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    )),
                    // الرصيد المتبقي
                    _cell(_colFlex[6], Text(
                      _currencyFormat.format(tx.remainingBalance),
                      style: GoogleFonts.cairo(fontSize: r.small, color: Colors.blue.shade700),
                    )),
                    // طريقة الدفع
                    _cell(_colFlex[7], Text(tx.paymentMethod,
                        style: GoogleFonts.cairo(fontSize: r.small),
                        overflow: TextOverflow.ellipsis)),
                    // المنطقة
                    _cell(_colFlex[8], Text(tx.zoneId,
                        style: GoogleFonts.cairo(fontSize: r.small, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis)),
                  ],
                ),
              );
            },
          ),
        ),
        // ── شريط الترقيم ──
        _buildPagination(totalPages),
      ],
    );
  }

  Widget _cell(double flex, Widget child) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      ),
    );
  }

  Widget _buildPagination(int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text('عرض',
              style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _rowsPerPage,
              isDense: true,
              items: [10, 25, 50, 100].map((v) => DropdownMenuItem(
                  value: v, child: Text('$v', style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) {
                if (v != null) setState(() { _rowsPerPage = v; _currentPage = 0; });
              },
            ),
          ),
          const SizedBox(width: 8),
          Text('من ${_filteredTransactions.length}',
              style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.first_page, size: 20),
            onPressed: _currentPage > 0 ? () => setState(() => _currentPage = 0) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1A237E),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('${_currentPage + 1} / $totalPages',
                style: GoogleFonts.cairo(color: Colors.white, fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page, size: 20),
            onPressed: _currentPage < totalPages - 1
                ? () => setState(() => _currentPage = totalPages - 1)
                : null,
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  AUTH PROMPT
  // ════════════════════════════════════════════════════════════════

  Widget _buildAuthPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('يرجى تسجيل الدخول من صفحة حسابات التفعيلات أولاً',
              style: GoogleFonts.cairo(color: Colors.grey.shade600, fontSize: 15)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
            label: Text('رجوع', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  EXCEL EXPORT
  // ════════════════════════════════════════════════════════════════

  Future<void> _exportToExcel() async {
    if (_filteredTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('لا توجد بيانات للتصدير', style: GoogleFonts.cairo()),
            backgroundColor: Colors.orange),
      );
      return;
    }

    final excel = xl.Excel.createExcel();

    // ── ورقة 1: المعاملات التفصيلية ──
    final sheet1Name = 'عمليات المحفظة';
    final sheet1 = excel[sheet1Name];
    excel.setDefaultSheet(sheet1Name);

    final headers = [
      '#', 'التاريخ', 'المشغل', 'العميل', 'رقم العميل',
      'نوع العملية', 'المبلغ', 'الرصيد المتبقي', 'طريقة الدفع', 'المنطقة',
    ];
    final headerStyle = xl.CellStyle(
      bold: true,
      backgroundColorHex: xl.ExcelColor.fromHexString('FF1A237E'),
      fontColorHex: xl.ExcelColor.white,
    );
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet1.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (int i = 0; i < _filteredTransactions.length; i++) {
      final tx = _filteredTransactions[i];
      String dateStr = '';
      if (tx.occuredAt.length >= 16) {
        try {
          final dt = DateTime.parse(tx.occuredAt).toLocal();
          dateStr = DateFormat('yyyy/MM/dd HH:mm').format(dt);
        } catch (_) {
          dateStr = tx.occuredAt;
        }
      }
      final rowData = [
        '${i + 1}',
        dateStr,
        tx.operatorName,
        tx.customerName,
        tx.customerId,
        _translateType(tx.type),
        tx.amount.toStringAsFixed(0),
        tx.remainingBalance.toStringAsFixed(0),
        tx.paymentMethod,
        tx.zoneId,
      ];
      final rowStyle = xl.CellStyle(
        backgroundColorHex: i.isEven
            ? xl.ExcelColor.fromHexString('FFF5F5FF')
            : xl.ExcelColor.white,
      );
      for (int j = 0; j < rowData.length; j++) {
        final cell = sheet1.cell(xl.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
        cell.value = xl.TextCellValue(rowData[j]);
        cell.cellStyle = rowStyle;
      }
    }

    // ── ورقة 2: ملخص المشغلين ──
    final sheet2 = excel['ملخص المشغلين'];
    final summaryHeaders = ['المشغل', 'عدد العمليات', 'الوارد', 'الصادر', 'الصافي'];
    final summaryHeaderStyle = xl.CellStyle(
      bold: true,
      backgroundColorHex: xl.ExcelColor.fromHexString('FF4A148C'),
      fontColorHex: xl.ExcelColor.white,
    );
    for (int i = 0; i < summaryHeaders.length; i++) {
      final cell = sheet2.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(summaryHeaders[i]);
      cell.cellStyle = summaryHeaderStyle;
    }

    // تجميع حسب المشغل
    final Map<String, _OperatorSummary> opSummary = {};
    for (final tx in _filteredTransactions) {
      final s = opSummary.putIfAbsent(tx.operatorName, () => _OperatorSummary());
      s.count++;
      if (tx.amount >= 0) {
        s.totalIn += tx.amount;
      } else {
        s.totalOut += tx.amount.abs();
      }
    }
    final sortedOps = opSummary.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));

    for (int i = 0; i < sortedOps.length; i++) {
      final e = sortedOps[i];
      final rowData = [
        e.key,
        e.value.count.toString(),
        e.value.totalIn.toStringAsFixed(0),
        e.value.totalOut.toStringAsFixed(0),
        (e.value.totalIn - e.value.totalOut).toStringAsFixed(0),
      ];
      for (int j = 0; j < rowData.length; j++) {
        final cell = sheet2.cell(xl.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
        cell.value = xl.TextCellValue(rowData[j]);
      }
    }

    // ── ورقة 3: ملخص حسب النوع ──
    final sheet3 = excel['ملخص حسب النوع'];
    final typeHeaders = ['نوع العملية', 'العدد', 'إجمالي المبلغ'];
    final typeHeaderStyle = xl.CellStyle(
      bold: true,
      backgroundColorHex: xl.ExcelColor.fromHexString('FF00695C'),
      fontColorHex: xl.ExcelColor.white,
    );
    for (int i = 0; i < typeHeaders.length; i++) {
      final cell = sheet3.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(typeHeaders[i]);
      cell.cellStyle = typeHeaderStyle;
    }

    final Map<String, _TypeSummary> typeSummary = {};
    for (final tx in _filteredTransactions) {
      final s = typeSummary.putIfAbsent(tx.type, () => _TypeSummary());
      s.count++;
      s.totalAmount += tx.amount;
    }
    final sortedTypes = typeSummary.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));

    for (int i = 0; i < sortedTypes.length; i++) {
      final e = sortedTypes[i];
      final rowData = [
        _translateType(e.key),
        e.value.count.toString(),
        e.value.totalAmount.toStringAsFixed(0),
      ];
      for (int j = 0; j < rowData.length; j++) {
        final cell = sheet3.cell(xl.CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i + 1));
        cell.value = xl.TextCellValue(rowData[j]);
      }
    }

    // حذف الورقة الافتراضية
    excel.delete('Sheet1');

    // حفظ الملف
    final bytes = excel.save();
    if (bytes == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إنشاء الملف', style: GoogleFonts.cairo()), backgroundColor: Colors.red),
        );
      }
      return;
    }

    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final filePath = '${dir.path}/wallet_transactions_$timestamp.xlsx';
    File(filePath)
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم حفظ الملف: $filePath', style: GoogleFonts.cairo()),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'فتح',
          textColor: Colors.white,
          onPressed: () => OpenFilex.open(filePath),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Models
// ════════════════════════════════════════════════════════════════

class _WalletTx {
  final String id;
  final String type;
  final double amount;
  final double remainingBalance;
  final String customerName;
  final String customerId;
  final String operatorName;
  final String occuredAt;
  final String paymentMethod;
  final String zoneId;

  _WalletTx({
    required this.id,
    required this.type,
    required this.amount,
    required this.remainingBalance,
    required this.customerName,
    required this.customerId,
    required this.operatorName,
    required this.occuredAt,
    this.paymentMethod = '',
    this.zoneId = '',
  });
}

class _OperatorSummary {
  int count = 0;
  double totalIn = 0;
  double totalOut = 0;
}

class _TypeSummary {
  int count = 0;
  double totalAmount = 0;
}
