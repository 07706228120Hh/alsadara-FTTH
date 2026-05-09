import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
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

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F6FA),
          foregroundColor: const Color(0xFF1A1A2E),
          iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
          titleTextStyle: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
          title: Text(_customerLoading ? 'تفاصيل العميل' : _customerName),
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1A1A2E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF1A1A2E),
            tabs: const [
              Tab(text: 'كشف الحساب'),
              Tab(text: 'معلومات العميل'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Summary cards
            _buildSummaryCards(),
            const SizedBox(height: 4),
            // Quick actions
            _buildQuickActions(),
            const Divider(height: 1),
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
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _summaryCard(
              'اجمالي المبيعات',
              fmtN(_totalSales),
              Colors.blue,
              Icons.shopping_cart_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _summaryCard(
              'اجمالي المدفوعات',
              fmtN(_totalPayments),
              Colors.green,
              Icons.payments_outlined,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _summaryCard(
              'الرصيد',
              fmtN(_balance),
              _balance > 0 ? Colors.red : Colors.green,
              Icons.account_balance_wallet_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: color)),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _quickActionBtn(
            'فاتورة جديدة',
            Icons.receipt_long_outlined,
            Colors.blue,
            () {
              // TODO: navigate to invoice_form_page (will be created later)
            },
          ),
          const SizedBox(width: 12),
          _quickActionBtn(
            'سند قبض',
            Icons.money_outlined,
            Colors.green,
            () {
              // TODO: navigate to voucher_form_page (will be created later)
            },
          ),
          const SizedBox(width: 12),
          _quickActionBtn(
            'تعديل العميل',
            Icons.edit_outlined,
            Colors.orange,
            () {
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
        ],
      ),
    );
  }

  Widget _quickActionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: color),
      label: Text(label, style: TextStyle(color: color)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ---------------------------------------------------------------
  //  3. Tab 1 — كشف الحساب
  // ---------------------------------------------------------------

  Widget _buildStatementTab() {
    return Column(
      children: [
        _buildDateFilter(),
        const Divider(height: 1),
        Expanded(child: _buildStatementBody()),
      ],
    );
  }

  Widget _buildDateFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(
                _dateFrom != null ? 'من: ${_formatDate(_dateFrom!)}' : 'من تاريخ'),
            onPressed: () => _pickDate(true),
          ),
          const SizedBox(width: 12),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
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
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadStatement,
          ),
        ],
      ),
    );
  }

  Widget _buildStatementBody() {
    if (_statementLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_statementError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_statementError!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadStatement,
              icon: const Icon(Icons.refresh),
              label: const Text('اعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_statementRows.isEmpty) {
      return const Center(
        child: Text('لا توجد حركات',
            style: TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Table(
            border: TableBorder.all(color: Colors.black, width: 1),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              // Header
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade200),
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
              for (final row in _statementRows)
                TableRow(
                  children: [
                    _tableCell(_formatDateStr(row['Date'])),
                    _tableCell('${row['Reference'] ?? '-'}'),
                    _tableCell('${row['Description'] ?? '-'}', minWidth: 200),
                    _tableCell(fmtN(row['Debit']), align: TextAlign.center),
                    _tableCell(fmtN(row['Credit']), align: TextAlign.center),
                    _tableCell(fmtN(row['Balance']), align: TextAlign.center),
                  ],
                ),
              // Footer
              TableRow(
                decoration: BoxDecoration(color: Colors.grey.shade300),
                children: [
                  _tableCell('', isHeader: true),
                  _tableCell('', isHeader: true),
                  _tableCell('الاجمالي', isHeader: true, minWidth: 200),
                  _tableCell(fmtN(_totalDebit),
                      isHeader: true, align: TextAlign.center),
                  _tableCell(fmtN(_totalCredit),
                      isHeader: true, align: TextAlign.center),
                  _tableCell(fmtN(_closingBalance),
                      isHeader: true, align: TextAlign.center),
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
    TextAlign align = TextAlign.start,
    double? minWidth,
  }) {
    return Container(
      constraints: BoxConstraints(minWidth: minWidth ?? 80),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  //  4. Tab 2 — معلومات العميل
  // ---------------------------------------------------------------

  Widget _buildInfoTab() {
    if (_customerLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_customerError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_customerError!,
                style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadCustomer,
              icon: const Icon(Icons.refresh),
              label: const Text('اعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow('الكود', _customer['Code']),
            _infoRow('الاسم', _customer['Name']),
            _infoRow('الهاتف', _customer['Phone']),
            _infoRow('الهاتف2', _customer['Phone2']),
            _infoRow('الايميل', _customer['Email']),
            _infoRow('المدينة', _customer['City']),
            _infoRow('المنطقة', _customer['Area']),
            _infoRow('العنوان', _customer['Address']),
            _infoRow('النوع', _customer['Type']),
            _infoRow('سقف الائتمان', _customer['CreditLimit'] != null
                ? fmtN(_customer['CreditLimit'])
                : null),
            _infoRow('الرقم الضريبي', _customer['TaxNumber']),
            _infoRow('ملاحظات', _customer['Notes']),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, dynamic value) {
    final text = (value == null || '$value'.trim().isEmpty) ? '-' : '$value';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
