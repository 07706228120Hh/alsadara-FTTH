import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import 'invoice_form_page.dart';
import 'invoice_details_page.dart';

class InvoicesPage extends StatefulWidget {
  final String companyId;
  const InvoicesPage({super.key, required this.companyId});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage>
    with SingleTickerProviderStateMixin {
  final _api = InventoryApiService.instance;
  late final TabController _tabController;

  // ---- Sales tab state ----
  bool _salesLoading = true;
  String? _salesError;
  List<Map<String, dynamic>> _salesInvoices = [];
  String? _salesStatusFilter;
  DateTime? _salesDateFrom;
  DateTime? _salesDateTo;

  // ---- Purchase tab state ----
  bool _purchaseLoading = true;
  String? _purchaseError;
  List<Map<String, dynamic>> _purchaseInvoices = [];
  String? _purchaseStatusFilter;
  DateTime? _purchaseDateFrom;
  DateTime? _purchaseDateTo;

  static const _statusMap = <String?, String>{
    null: 'الكل',
    'Draft': 'مسودة',
    'Confirmed': 'مؤكدة',
    'PartiallyPaid': 'مدفوعة جزئياً',
    'Paid': 'مدفوعة',
    'Cancelled': 'ملغاة',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadSales();
    _loadPurchases();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ================================================================
  //  Data loading
  // ================================================================

  Future<void> _loadSales() async {
    setState(() {
      _salesLoading = true;
      _salesError = null;
    });
    try {
      final res = await _api.getInvoices(
        companyId: widget.companyId,
        type: 'Sales',
        status: _salesStatusFilter,
        from: _salesDateFrom?.toIso8601String().split('T').first,
        to: _salesDateTo?.toIso8601String().split('T').first,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _salesInvoices =
              list.map((e) => e as Map<String, dynamic>).toList();
          _salesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _salesError = e.toString();
          _salesLoading = false;
        });
      }
    }
  }

  Future<void> _loadPurchases() async {
    setState(() {
      _purchaseLoading = true;
      _purchaseError = null;
    });
    try {
      final res = await _api.getInvoices(
        companyId: widget.companyId,
        type: 'Purchase',
        status: _purchaseStatusFilter,
        from: _purchaseDateFrom?.toIso8601String().split('T').first,
        to: _purchaseDateTo?.toIso8601String().split('T').first,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _purchaseInvoices =
              list.map((e) => e as Map<String, dynamic>).toList();
          _purchaseLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _purchaseError = e.toString();
          _purchaseLoading = false;
        });
      }
    }
  }

  // ================================================================
  //  Helpers
  // ================================================================

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  String _formatDateStr(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return _formatDate(dt);
  }

  Future<void> _pickDate(bool isFrom, {required bool isSales}) async {
    final current = isSales
        ? (isFrom ? _salesDateFrom : _salesDateTo)
        : (isFrom ? _purchaseDateFrom : _purchaseDateTo);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isSales) {
          if (isFrom) {
            _salesDateFrom = picked;
          } else {
            _salesDateTo = picked;
          }
        } else {
          if (isFrom) {
            _purchaseDateFrom = picked;
          } else {
            _purchaseDateTo = picked;
          }
        }
      });
      isSales ? _loadSales() : _loadPurchases();
    }
  }

  Widget _statusChip(String? status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'Draft':
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = 'مسودة';
        break;
      case 'Confirmed':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        label = 'مؤكدة';
        break;
      case 'PartiallyPaid':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        label = 'مدفوعة جزئياً';
        break;
      case 'Paid':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'مدفوعة';
        break;
      case 'Cancelled':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        label = 'ملغاة';
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = status ?? '-';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _paymentChip(String? paymentType) {
    Color bg;
    Color fg;
    String label;
    switch (paymentType) {
      case 'Cash':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'نقدي';
        break;
      case 'Credit':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        label = 'آجل';
        break;
      case 'Partial':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        label = 'جزئي';
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = paymentType ?? '-';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style:
              TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  // ================================================================
  //  Build
  // ================================================================

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
          title: const Text('الفواتير'),
          actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoiceFormPage(
                      companyId: widget.companyId,
                      invoiceType: 'Sales',
                    ),
                  ),
                ).then((_) {
                  _loadSales();
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('فاتورة بيع +'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoiceFormPage(
                      companyId: widget.companyId,
                      invoiceType: 'Purchase',
                    ),
                  ),
                ).then((_) {
                  _loadPurchases();
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('فاتورة شراء +'),
            ),
            const SizedBox(width: 12),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1A1A2E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF1A1A2E),
            tabs: const [
              Tab(text: 'فواتير البيع'),
              Tab(text: 'فواتير الشراء'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildTabContent(
              isSales: true,
              loading: _salesLoading,
              error: _salesError,
              invoices: _salesInvoices,
              statusFilter: _salesStatusFilter,
              dateFrom: _salesDateFrom,
              dateTo: _salesDateTo,
              onStatusChanged: (v) {
                setState(() => _salesStatusFilter = v);
                _loadSales();
              },
              onClearFilters: () {
                setState(() {
                  _salesStatusFilter = null;
                  _salesDateFrom = null;
                  _salesDateTo = null;
                });
                _loadSales();
              },
              onReload: _loadSales,
              counterpartLabel: 'العميل',
            ),
            _buildTabContent(
              isSales: false,
              loading: _purchaseLoading,
              error: _purchaseError,
              invoices: _purchaseInvoices,
              statusFilter: _purchaseStatusFilter,
              dateFrom: _purchaseDateFrom,
              dateTo: _purchaseDateTo,
              onStatusChanged: (v) {
                setState(() => _purchaseStatusFilter = v);
                _loadPurchases();
              },
              onClearFilters: () {
                setState(() {
                  _purchaseStatusFilter = null;
                  _purchaseDateFrom = null;
                  _purchaseDateTo = null;
                });
                _loadPurchases();
              },
              onReload: _loadPurchases,
              counterpartLabel: 'المورد',
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  //  Tab content
  // ================================================================

  Widget _buildTabContent({
    required bool isSales,
    required bool loading,
    required String? error,
    required List<Map<String, dynamic>> invoices,
    required String? statusFilter,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required ValueChanged<String?> onStatusChanged,
    required VoidCallback onClearFilters,
    required VoidCallback onReload,
    required String counterpartLabel,
  }) {
    return Column(
      children: [
        // Filters row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  value: statusFilter,
                  decoration: const InputDecoration(
                    labelText: 'الحالة',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  items: _statusMap.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: onStatusChanged,
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(dateFrom != null
                    ? 'من: ${_formatDate(dateFrom)}'
                    : 'من تاريخ'),
                onPressed: () => _pickDate(true, isSales: isSales),
              ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(dateTo != null
                    ? 'إلى: ${_formatDate(dateTo)}'
                    : 'إلى تاريخ'),
                onPressed: () => _pickDate(false, isSales: isSales),
              ),
              if (dateFrom != null || dateTo != null || statusFilter != null)
                ActionChip(
                  avatar: const Icon(Icons.clear, size: 18),
                  label: const Text('مسح الفلاتر'),
                  onPressed: onClearFilters,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Body
        Expanded(
          child: _buildTabBody(
            loading: loading,
            error: error,
            invoices: invoices,
            onReload: onReload,
            counterpartLabel: counterpartLabel,
            isSales: isSales,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody({
    required bool loading,
    required String? error,
    required List<Map<String, dynamic>> invoices,
    required VoidCallback onReload,
    required String counterpartLabel,
    required bool isSales,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(error, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (invoices.isEmpty) {
      return const Center(
        child: Text('لا توجد فواتير',
            style: TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.all(color: Colors.black, width: 1),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            // Header row
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade200),
              children: [
                _headerCell('رقم الفاتورة'),
                _headerCell(counterpartLabel),
                _headerCell('التاريخ'),
                _headerCell('المبلغ'),
                _headerCell('المدفوع'),
                _headerCell('المتبقي'),
                _headerCell('نوع الدفع'),
                _headerCell('الحالة'),
                _headerCell('إجراءات'),
              ],
            ),
            // Data rows
            for (var i = 0; i < invoices.length; i++)
              _buildDataRow(invoices[i], i, counterpartLabel, isSales),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _dataCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Center(child: child),
    );
  }

  TableRow _buildDataRow(
    Map<String, dynamic> inv,
    int index,
    String counterpartLabel,
    bool isSales,
  ) {
    final id = inv['Id']?.toString() ?? '';
    final invoiceNumber = inv['InvoiceNumber']?.toString() ?? '-';
    final counterpart = isSales
        ? (inv['CustomerName']?.toString() ?? '-')
        : (inv['SupplierName']?.toString() ?? '-');
    final date = _formatDateStr(inv['InvoiceDate']?.toString());
    final amount = fmtN(inv['TotalAmount']);
    final paid = fmtN(inv['PaidAmount']);
    final remaining = fmtN(inv['RemainingAmount']);
    final paymentType = inv['PaymentType']?.toString();
    final status = inv['Status']?.toString();

    return TableRow(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : Colors.grey.shade50,
      ),
      children: [
        _tappableCell(
          child: Text(invoiceNumber,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
          onTap: () => _navigateToDetails(id),
        ),
        _tappableCell(
          child: Text(counterpart,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
          onTap: () => _navigateToDetails(id),
        ),
        _tappableCell(
          child: Text(date,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
          onTap: () => _navigateToDetails(id),
        ),
        _tappableCell(
          child: Text(amount,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
          onTap: () => _navigateToDetails(id),
        ),
        _tappableCell(
          child: Text(paid,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
          onTap: () => _navigateToDetails(id),
        ),
        _tappableCell(
          child: Text(remaining,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
          onTap: () => _navigateToDetails(id),
        ),
        _tappableCell(
          child: _paymentChip(paymentType),
          onTap: () => _navigateToDetails(id),
        ),
        _tappableCell(
          child: _statusChip(status),
          onTap: () => _navigateToDetails(id),
        ),
        // أزرار الإجراءات
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _buildInvoiceActions(id, status, isSales),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildInvoiceActions(String id, String? status, bool isSales) {
    final actions = <Widget>[];

    // تعديل — فقط للمسودة
    if (status == 'Draft') {
      actions.add(_invoiceActionBtn(Icons.edit_outlined, 'تعديل', Colors.blue.shade800, () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => InvoiceFormPage(companyId: widget.companyId, invoiceType: isSales ? 'Sales' : 'Purchase'),
        )).then((_) { _loadSales(); _loadPurchases(); });
      }));
    }

    // تأكيد — فقط للمسودة
    if (status == 'Draft') {
      actions.add(_invoiceActionBtn(Icons.check_circle_outline, 'تأكيد', Colors.green.shade800, () => _confirmInvoice(id)));
    }

    // إلغاء — فقط للمسودة (الفواتير المؤكدة تحتاج مرتجع)
    if (status == 'Draft') {
      actions.add(_invoiceActionBtn(Icons.cancel_outlined, 'إلغاء', Colors.red.shade800, () => _cancelInvoice(id)));
    }

    // عرض التفاصيل — دائماً
    actions.add(_invoiceActionBtn(Icons.visibility_outlined, 'عرض', Colors.grey.shade700, () => _navigateToDetails(id)));

    return actions;
  }

  Widget _invoiceActionBtn(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 20, color: color)),
      ),
    );
  }

  Future<void> _confirmInvoice(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الفاتورة'),
        content: const Text('هل تريد تأكيد هذه الفاتورة؟ سيتم خصم/إضافة المخزون تلقائياً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.confirmInvoice(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأكيد الفاتورة بنجاح'), backgroundColor: Colors.green));
      _loadSales(); _loadPurchases();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التأكيد: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _cancelInvoice(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: const Text('هل تريد إلغاء هذه الفاتورة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء الفاتورة')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.cancelInvoice(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الفاتورة'), backgroundColor: Colors.green));
      _loadSales(); _loadPurchases();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _tappableCell({required Widget child, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Center(child: child),
      ),
    );
  }

  void _navigateToDetails(String invoiceId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailsPage(
          companyId: widget.companyId,
          invoiceId: invoiceId,
        ),
      ),
    ).then((_) {
      _loadSales();
      _loadPurchases();
    });
  }
}
