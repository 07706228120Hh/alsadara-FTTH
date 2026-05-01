import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';
import 'purchase_form_page.dart';

class PurchasesPage extends StatefulWidget {
  final String companyId;
  const PurchasesPage({super.key, required this.companyId});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<PurchaseOrder> _orders = [];
  int _totalCount = 0;
  int _page = 1;
  final int _pageSize = 20;

  // Filters
  String? _statusFilter;
  String? _supplierFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  List<Supplier> _suppliers = [];

  static const _statusMap = {
    null: 'الكل',
    'Draft': 'مسودة',
    'Approved': 'معتمد',
    'PartiallyReceived': 'استلام جزئي',
    'Received': 'مستلم',
    'Cancelled': 'ملغي',
  };

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _loadData();
  }

  Future<void> _loadSuppliers() async {
    try {
      final res =
          await _api.getSuppliers(companyId: widget.companyId);
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _suppliers =
              list.map((e) => Supplier.fromJson(e as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getPurchaseOrders(
        companyId: widget.companyId,
        status: _statusFilter,
        supplierId: _supplierFilter,
        from: _dateFrom?.toIso8601String().split('T').first,
        to: _dateTo?.toIso8601String().split('T').first,
        page: _page,
        pageSize: _pageSize,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _orders = list
              .map((e) =>
                  PurchaseOrder.fromJson(e as Map<String, dynamic>))
              .where((o) => o.status != 'Cancelled') // إخفاء الملغي
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
      case 'Approved':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        label = 'معتمد';
        break;
      case 'PartiallyReceived':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        label = 'استلام جزئي';
        break;
      case 'Received':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'مستلم';
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

  List<Widget> _buildActions(PurchaseOrder order) {
    return [
      _actionBtn(Icons.delete_outline, 'حذف', Colors.red.shade800, () => _deleteOrder(order)),
    ];
  }

  Future<void> _deleteOrder(PurchaseOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف أمر الشراء "${order.orderNumber}"؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      // نستخدم cancel كحذف ناعم (soft delete)
      await _api.cancelPurchaseOrder(order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف'), backgroundColor: Colors.green));
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
      }
    }
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

  void _editOrder(PurchaseOrder order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseFormPage(
          companyId: widget.companyId,
          existingOrder: order,
        ),
      ),
    ).then((_) => _loadData());
  }

  Future<void> _approveOrder(PurchaseOrder order) async {
    final confirmed = await _confirmDialog('اعتماد أمر الشراء', 'هل أنت متأكد من اعتماد أمر الشراء ${order.orderNumber}؟');
    if (!confirmed) return;
    try {
      await _api.approvePurchaseOrder(order.id);
      _showSnackBar('تم اعتماد أمر الشراء بنجاح');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الاعتماد: $e', isError: true);
    }
  }

  Future<void> _cancelOrder(PurchaseOrder order) async {
    final confirmed = await _confirmDialog('إلغاء أمر الشراء', 'هل أنت متأكد من إلغاء أمر الشراء ${order.orderNumber}؟');
    if (!confirmed) return;
    try {
      await _api.cancelPurchaseOrder(order.id);
      _showSnackBar('تم إلغاء أمر الشراء');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الإلغاء: $e', isError: true);
    }
  }

  Future<void> _receiveOrder(PurchaseOrder order) async {
    // For now, receive all remaining items
    final confirmed = await _confirmDialog('استلام أمر الشراء', 'هل تريد استلام كامل الأصناف المتبقية في أمر الشراء ${order.orderNumber}؟');
    if (!confirmed) return;
    try {
      // Fetch full order to get items
      final fullRes = await _api.getPurchaseOrder(order.id);
      final fullOrder = PurchaseOrder.fromJson(fullRes['data'] as Map<String, dynamic>? ?? fullRes);
      final receiveItems = (fullOrder.items ?? []).map((item) {
        return {
          'purchaseOrderItemId': item.id,
          'receivedQuantity': item.quantity - item.receivedQuantity,
        };
      }).where((m) => (m['receivedQuantity'] as int) > 0).toList();

      if (receiveItems.isEmpty) {
        _showSnackBar('لا توجد أصناف متبقية للاستلام');
        return;
      }
      await _api.receivePurchaseOrder(order.id, items: receiveItems);
      _showSnackBar('تم الاستلام بنجاح');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الاستلام: $e', isError: true);
    }
  }

  Future<bool> _confirmDialog(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)), titleTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700), elevation: 0,
          title: const Text('أوامر الشراء'),
          actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PurchaseFormPage(companyId: widget.companyId),
                  ),
                ).then((_) => _loadData());
              },
              icon: const Icon(Icons.add),
              label: const Text('أمر شراء جديد'),
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
    String dateFormat(DateTime? d) =>
        d != null ? '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}' : '';
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
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: _statusMap.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                setState(() => _statusFilter = v);
                _page = 1;
                _loadData();
              },
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              value: _supplierFilter,
              decoration: const InputDecoration(
                labelText: 'المورد',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('الكل')),
                ..._suppliers.map((s) =>
                    DropdownMenuItem(value: s.id, child: Text(s.name))),
              ],
              onChanged: (v) {
                setState(() => _supplierFilter = v);
                _page = 1;
                _loadData();
              },
            ),
          ),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(_dateFrom != null ? 'من: ${dateFormat(_dateFrom)}' : 'من تاريخ'),
            onPressed: () => _pickDate(true),
          ),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(_dateTo != null ? 'إلى: ${dateFormat(_dateTo)}' : 'إلى تاريخ'),
            onPressed: () => _pickDate(false),
          ),
          if (_dateFrom != null || _dateTo != null || _statusFilter != null || _supplierFilter != null)
            ActionChip(
              avatar: const Icon(Icons.clear, size: 18),
              label: const Text('مسح الفلاتر'),
              onPressed: () {
                setState(() {
                  _statusFilter = null;
                  _supplierFilter = null;
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
        child: Text('لا توجد أوامر شراء', style: TextStyle(fontSize: 16, color: Colors.grey)),
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
                  DataColumn(label: Text('رقم الأمر')),
                  DataColumn(label: Text('المورد')),
                  DataColumn(label: Text('المستودع')),
                  DataColumn(label: Text('التاريخ')),
                  DataColumn(label: Text('المبلغ')),
                  DataColumn(label: Text('الحالة')),
                  DataColumn(label: Text('عدد الأصناف')),
                  DataColumn(label: Text('إجراءات')),
                ],
                rows: _orders.map((o) {
                  return DataRow(cells: [
                    DataCell(Text(o.orderNumber)),
                    DataCell(Text(o.supplierName ?? '-')),
                    DataCell(Text(o.warehouseName ?? '-')),
                    DataCell(Text(
                        '${o.orderDate.year}/${o.orderDate.month.toString().padLeft(2, '0')}/${o.orderDate.day.toString().padLeft(2, '0')}')),
                    DataCell(Text(fmtN(o.netAmount))),
                    DataCell(_statusChip(o.status)),
                    DataCell(Text('${o.itemsCount ?? o.items?.length ?? 0}')),
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
