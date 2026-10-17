import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../services/inventory_api_service.dart';
import 'customer_form_page.dart';

class CustomerDetailsPage extends StatefulWidget {
  final String companyId;
  final String customerId;

  const CustomerDetailsPage({
    super.key,
    required this.companyId,
    required this.customerId,
  });

  @override
  State<CustomerDetailsPage> createState() => _CustomerDetailsPageState();
}

class _CustomerDetailsPageState extends State<CustomerDetailsPage>
    with SingleTickerProviderStateMixin {
  final _api = InventoryApiService.instance;

  late TabController _tabController;

  // --- Customer info ---
  bool _customerLoading = true;
  String? _customerError;
  Map<String, dynamic> _customer = {};

  // --- Statement ---
  bool _statementLoading = true;
  String? _statementError;
  List<Map<String, dynamic>> _statementRows = [];
  double _totalDebit = 0;
  double _totalCredit = 0;
  double _closingBalance = 0;

  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCustomer();
    _loadStatement();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  //  Data loading
  // ---------------------------------------------------------------

  Future<void> _loadCustomer() async {
    setState(() {
      _customerLoading = true;
      _customerError = null;
    });
    try {
      final res = await _api.getCustomer(widget.customerId);
      if (mounted) {
        setState(() {
          _customer = (res['data'] as Map<String, dynamic>?) ?? {};
          _customerLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _customerError = e.toString();
          _customerLoading = false;
        });
      }
    }
  }

  Future<void> _loadStatement() async {
    setState(() {
      _statementLoading = true;
      _statementError = null;
    });
    try {
      final res = await _api.getCustomerStatement(
        widget.customerId,
        from: _dateFrom?.toIso8601String().split('T').first,
        to: _dateTo?.toIso8601String().split('T').first,
      );
      final data = res['data'] as Map<String, dynamic>? ?? {};
      final list = (data['statement'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _statementRows = list.cast<Map<String, dynamic>>();
          _totalDebit = _toDouble(data['totalDebit']);
          _totalCredit = _toDouble(data['totalCredit']);
          _closingBalance = _toDouble(data['closingBalance']);
          _statementLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statementError = e.toString();
          _statementLoading = false;
        });
      }
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  // ---------------------------------------------------------------
  //  Helpers
  // ---------------------------------------------------------------

  String get _customerName =>
      (_customer['Name'] as String?) ?? 'تفاصيل العميل';

  double get _totalSales => _toDouble(_customer['TotalSales']);
  double get _totalPayments => _toDouble(_customer['TotalPayments']);
  double get _balance => _toDouble(_customer['Balance']);

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  String _formatDateStr(dynamic v) {
    if (v == null) return '-';
    final d = DateTime.tryParse('$v');
    if (d == null) return '$v';
    return _formatDate(d);
  }

  // ignore: unused_element
  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? SdColors.danger : SdColors.success,
      ),
    );
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
      _loadStatement();
    }
  }

  // ---------------------------------------------------------------
  //  Build
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(title: _customerLoading ? 'تفاصيل العميل' : _customerName),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Summary cards
          _buildSummaryCards(),
          const SizedBox(height: SdSpace.sm),
          // Quick actions
          _buildQuickActions(),
          const SizedBox(height: SdSpace.sm),
          // Tabs
          _buildTabBar(),
          const SizedBox(height: SdSpace.sm),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStatementTab(),
                _buildInfoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: SdColors.primary,
        unselectedLabelColor: SdColors.muted,
        indicatorColor: SdColors.primary,
        labelStyle: SdText.label,
        unselectedLabelStyle: SdText.label.copyWith(fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'كشف الحساب'),
          Tab(text: 'معلومات العميل'),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  //  1. Summary Cards
  // ---------------------------------------------------------------

  Widget _buildSummaryCards() {
    if (_customerLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(color: SdColors.primary)),
      );
    }
    return SdTileGrid(
      minTileWidth: 170,
      maxColumns: 3,
      phoneColumns: 1,
      children: [
        _summaryCard('اجمالي المبيعات', fmtN(_totalSales), SdStatus.info.tone,
            Icons.shopping_cart_outlined),
        _summaryCard('اجمالي المدفوعات', fmtN(_totalPayments), SdStatus.success.tone,
            Icons.payments_outlined),
        _summaryCard('الرصيد', fmtN(_balance),
            _balance > 0 ? SdStatus.danger.tone : SdStatus.success.tone,
            Icons.account_balance_wallet_outlined),
      ],
    );
  }

  Widget _summaryCard(String label, String value, SdTone tone, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: SdDepth.raised(),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tone.tint,
              borderRadius: BorderRadius.circular(SdRadius.sm),
              boxShadow: [BoxShadow(color: tone.tintEdge, offset: const Offset(0, 3))],
            ),
            child: Icon(icon, color: tone.base, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: SdText.caption),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                      maxLines: 1,
                      style: SdText.numberSm.copyWith(fontSize: 18, color: tone.edge)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  //  2. Quick Actions
  // ---------------------------------------------------------------

  Widget _buildQuickActions() {
    final buttons = [
      SdButton(
        label: 'فاتورة جديدة',
        icon: Icons.receipt_long_outlined,
        kind: SdButtonKind.secondary,
        expand: true,
        onPressed: () {
          // TODO: navigate to invoice_form_page (will be created later)
        },
      ),
      SdButton(
        label: 'سند قبض',
        icon: Icons.money_outlined,
        kind: SdButtonKind.secondary,
        expand: true,
        onPressed: () {
          // TODO: navigate to voucher_form_page (will be created later)
        },
      ),
      SdButton(
        label: 'تعديل العميل',
        icon: Icons.edit_outlined,
        kind: SdButtonKind.secondary,
        expand: true,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CustomerFormPage(
                companyId: widget.companyId,
                customerId: widget.customerId,
              ),
            ),
          ).then((_) {
            _loadCustomer();
            _loadStatement();
          });
        },
      ),
    ];

    if (context.sd.isPhone) {
      return Column(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            buttons[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------
  //  3. Tab 1 — كشف الحساب
  // ---------------------------------------------------------------

  Widget _buildStatementTab() {
    return Column(
      children: [
        _buildDateFilter(),
        const SizedBox(height: SdSpace.xs),
        Expanded(child: _buildStatementBody()),
      ],
    );
  }

  Widget _buildDateFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
            label: Text(
                _dateFrom != null ? 'من: ${_formatDate(_dateFrom!)}' : 'من تاريخ'),
            onPressed: () => _pickDate(true),
          ),
          const SizedBox(width: 12),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
            label: Text(
                _dateTo != null ? 'الى: ${_formatDate(_dateTo!)}' : 'الى تاريخ'),
            onPressed: () => _pickDate(false),
          ),
          const SizedBox(width: 12),
          if (_dateFrom != null || _dateTo != null)
            ActionChip(
              avatar: const Icon(Icons.clear, size: 18),
              label: const Text('مسح'),
              onPressed: () {
                setState(() {
                  _dateFrom = null;
                  _dateTo = null;
                });
                _loadStatement();
              },
            ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.refresh, color: SdColors.primary),
            tooltip: 'تحديث',
            onPressed: _loadStatement,
          ),
        ],
      ),
    );
  }

  Widget _buildStatementBody() {
    if (_statementLoading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (_statementError != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل كشف الحساب',
          message: _statementError,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(
            label: 'اعادة المحاولة',
            icon: Icons.refresh_rounded,
            kind: SdButtonKind.secondary,
            onPressed: _loadStatement,
          ),
        ),
      );
    }
    if (_statementRows.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد حركات', icon: Icons.inbox_rounded),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.lg),
            boxShadow: SdDepth.raised(),
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              // Header
              TableRow(
                decoration: const BoxDecoration(color: SdColors.primary),
                children: [
                  _tableCell('التاريخ', isHeader: true),
                  _tableCell('المرجع', isHeader: true),
                  _tableCell('البيان', isHeader: true, minWidth: 200),
                  _tableCell('مدين', isHeader: true),
                  _tableCell('دائن', isHeader: true),
                  _tableCell('الرصيد', isHeader: true),
                ],
              ),
              // Data rows
              for (int i = 0; i < _statementRows.length; i++)
                TableRow(
                  decoration: BoxDecoration(
                    color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
                  ),
                  children: [
                    _tableCell(_formatDateStr(_statementRows[i]['Date'])),
                    _tableCell('${_statementRows[i]['Reference'] ?? '-'}'),
                    _tableCell('${_statementRows[i]['Description'] ?? '-'}', minWidth: 200),
                    _tableCell(fmtN(_statementRows[i]['Debit']), align: TextAlign.center),
                    _tableCell(fmtN(_statementRows[i]['Credit']), align: TextAlign.center),
                    _tableCell(fmtN(_statementRows[i]['Balance']), align: TextAlign.center),
                  ],
                ),
              // Footer
              TableRow(
                decoration: const BoxDecoration(color: SdColors.primaryTint),
                children: [
                  _tableCell('', isFooter: true),
                  _tableCell('', isFooter: true),
                  _tableCell('الاجمالي', isFooter: true, minWidth: 200),
                  _tableCell(fmtN(_totalDebit), isFooter: true, align: TextAlign.center),
                  _tableCell(fmtN(_totalCredit), isFooter: true, align: TextAlign.center),
                  _tableCell(fmtN(_closingBalance), isFooter: true, align: TextAlign.center),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableCell(
    String text, {
    bool isHeader = false,
    bool isFooter = false,
    TextAlign align = TextAlign.start,
    double? minWidth,
  }) {
    final Color color = isHeader
        ? Colors.white
        : isFooter
            ? SdColors.primary
            : SdColors.ink;
    return Container(
      constraints: BoxConstraints(minWidth: minWidth ?? 80),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontFamily: SdText.family,
          fontWeight: (isHeader || isFooter) ? FontWeight.w800 : FontWeight.w500,
          fontSize: 12.5,
          color: color,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  //  4. Tab 2 — معلومات العميل
  // ---------------------------------------------------------------

  Widget _buildInfoTab() {
    if (_customerLoading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (_customerError != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل بيانات العميل',
          message: _customerError,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(
            label: 'اعادة المحاولة',
            icon: Icons.refresh_rounded,
            kind: SdButtonKind.secondary,
            onPressed: _loadCustomer,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('الكود', _customer['Code']),
            _infoRow('الاسم', _customer['Name']),
            _infoRow('الهاتف', _customer['Phone'], ltr: true),
            _infoRow('الهاتف2', _customer['Phone2'], ltr: true),
            _infoRow('الايميل', _customer['Email'], ltr: true),
            _infoRow('المدينة', _customer['City']),
            _infoRow('المنطقة', _customer['Area']),
            _infoRow('العنوان', _customer['Address']),
            _infoRow('النوع', _customer['Type']),
            _infoRow('سقف الائتمان',
                _customer['CreditLimit'] != null ? fmtN(_customer['CreditLimit']) : null),
            _infoRow('الرقم الضريبي', _customer['TaxNumber'], ltr: true),
            _infoRow('ملاحظات', _customer['Notes']),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, dynamic value, {bool ltr = false}) {
    final text = (value == null || '$value'.trim().isEmpty) ? '-' : '$value';
    return SdInfoRow(label: label, value: text, ltrValue: ltr);
  }
}
