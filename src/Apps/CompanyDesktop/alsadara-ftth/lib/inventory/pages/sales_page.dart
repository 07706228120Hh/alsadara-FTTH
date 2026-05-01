import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';
import 'sale_form_page.dart';

class SalesPage extends StatefulWidget {
  final String companyId;
  const SalesPage({super.key, required this.companyId});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<SalesOrder> _orders = [];
  int _totalCount = 0;
  int _page = 1;
  final int _pageSize = 20;

  String? _statusFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const _statusMap = {
    null: 'الكل',
    'Draft': 'مسودة',
    'Confirmed': 'مؤكد',
    'Delivered': 'تم التسليم',
    'Cancelled': 'ملغي',
  };

  static const _paymentLabels = {
    'Cash': 'نقدي',
    'BankTransfer': 'تحويل بنكي',
    'ZainCash': 'زين كاش',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getSalesOrders(
        companyId: widget.companyId,
        status: _statusFilter,
        from: _dateFrom?.toIso8601String().split('T').first,
        to: _dateTo?.toIso8601String().split('T').first,
        page: _page,
        pageSize: _pageSize,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _orders = list
              .map((e) => SalesOrder.fromJson(e as Map<String, dynamic>))
              .toList();
          _totalCount = res['totalCount'] as int? ?? _orders.length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Widget _statusChip(String status) {
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
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'مؤكد';
        break;
      case 'Delivered':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        label = 'تم التسليم';
        break;
      case 'Cancelled':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        label = 'ملغي';
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  List<Widget> _buildActions(SalesOrder order) {
    final actions = <Widget>[];
    switch (order.status) {
      case 'Draft':
        actions.addAll([
          _actionBtn(Icons.check_circle_outline, 'تأكيد', Colors.green,
              () => _confirmOrder(order)),
          _actionBtn(Icons.cancel_outlined, 'إلغاء', Colors.red,
              () => _cancelOrder(order)),
        ]);
        break;
      case 'Confirmed':
        actions.add(
          _actionBtn(Icons.cancel_outlined, 'إلغاء', Colors.red,
              () => _cancelOrder(order)),
        );
        break;
    }
    return actions;
  }

  Widget _actionBtn(
      IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  Future<void> _confirmOrder(SalesOrder order) async {
    final ok = await _confirmDialog(
        'تأكيد عملية البيع', 'هل أنت متأكد من تأكيد عملية البيع ${order.orderNumber}؟');
    if (!ok) return;
    try {
      await _api.confirmSalesOrder(order.id);
      _showSnackBar('تم تأكيد عملية البيع');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل التأكيد: $e', isError: true);
    }
  }

  Future<void> _cancelOrder(SalesOrder order) async {
    final ok = await _confirmDialog(
        'إلغاء عملية البيع', 'هل أنت متأكد من إلغاء عملية البيع ${order.orderNumber}؟');
    if (!ok) return;
    try {
      await _api.cancelSalesOrder(order.id);
      _showSnackBar('تم إلغاء عملية البيع');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الإلغاء: $e', isError: true);
    }
  }

  Future<bool> _confirmDialog(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('تأكيد')),
            ],
          ),
        ) ??
        false;
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
      _page = 1;
      _loadData();
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)), titleTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700), elevation: 0,
          title: const Text('المبيعات'),
          actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SaleFormPage(companyId: widget.companyId),
                  ),
                ).then((_) => _loadData());
              },
              icon: const Icon(Icons.add),
              label: const Text('بيع جديد'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            _buildFilters(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String?>(
              value: _statusFilter,
              decoration: const InputDecoration(
                labelText: 'الحالة',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: _statusMap.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                setState(() => _statusFilter = v);
                _page = 1;
                _loadData();
              },
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(
                _dateFrom != null ? 'من: ${_formatDate(_dateFrom!)}' : 'من تاريخ'),
            onPressed: () => _pickDate(true),
          ),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(
                _dateTo != null ? 'إلى: ${_formatDate(_dateTo!)}' : 'إلى تاريخ'),
            onPressed: () => _pickDate(false),
          ),
          if (_dateFrom != null || _dateTo != null || _statusFilter != null)
            ActionChip(
              avatar: const Icon(Icons.clear, size: 18),
              label: const Text('مسح الفلاتر'),
              onPressed: () {
                setState(() {
                  _statusFilter = null;
                  _dateFrom = null;
                  _dateTo = null;
                });
                _page = 1;
                _loadData();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return const Center(
        child:
            Text('لا توجد عمليات بيع', style: TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    final totalPages = (_totalCount / _pageSize).ceil();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('رقم العملية')),
                  DataColumn(label: Text('العميل')),
                  DataColumn(label: Text('المستودع')),
                  DataColumn(label: Text('التاريخ')),
                  DataColumn(label: Text('المبلغ')),
                  DataColumn(label: Text('طريقة الدفع')),
                  DataColumn(label: Text('الحالة')),
                  DataColumn(label: Text('إجراءات')),
                ],
                rows: _orders.map((o) {
                  return DataRow(cells: [
                    DataCell(Text(o.orderNumber)),
                    DataCell(Text(o.customerName ?? '-')),
                    DataCell(Text(o.warehouseName ?? '-')),
                    DataCell(Text(_formatDate(o.orderDate))),
                    DataCell(Text(fmtN(o.netAmount))),
                    DataCell(Text(
                        _paymentLabels[o.paymentMethod] ?? o.paymentMethod ?? '-')),
                    DataCell(_statusChip(o.status)),
                    DataCell(Row(children: _buildActions(o))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
        if (totalPages > 1)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _page > 1
                      ? () {
                          setState(() => _page--);
                          _loadData();
                        }
                      : null,
                ),
                Text('صفحة $_page من $totalPages'),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _page < totalPages
                      ? () {
                          setState(() => _page++);
                          _loadData();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
