import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import 'return_form_page.dart';

class ReturnsPage extends StatefulWidget {
  final String companyId;
  const ReturnsPage({super.key, required this.companyId});

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage>
    with SingleTickerProviderStateMixin {
  final _api = InventoryApiService.instance;
  late TabController _tabController;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _salesReturns = [];
  List<Map<String, dynamic>> _purchaseReturns = [];

  static const _statusLabels = {
    'Draft': 'مسودة',
    'Confirmed': 'مؤكد',
    'Cancelled': 'ملغي',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getReturns(companyId: widget.companyId, type: 'SalesReturn'),
        _api.getReturns(companyId: widget.companyId, type: 'PurchaseReturn'),
      ]);

      final srList = (results[0]['data'] as List<dynamic>?) ?? [];
      final prList = (results[1]['data'] as List<dynamic>?) ?? [];

      if (mounted) {
        setState(() {
          _salesReturns = srList.cast<Map<String, dynamic>>();
          _purchaseReturns = prList.cast<Map<String, dynamic>>();
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

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  List<Widget> _buildReturnActions(String id, String status) {
    final actions = <Widget>[];
    if (status == 'Draft') {
      actions.add(_returnActionBtn(Icons.check_circle_outline, 'تأكيد', Colors.green.shade800, () => _confirmReturn(id)));
      actions.add(_returnActionBtn(Icons.cancel_outlined, 'إلغاء', Colors.orange.shade800, () => _cancelReturn(id)));
      actions.add(_returnActionBtn(Icons.delete_outline, 'حذف', Colors.red.shade800, () => _deleteReturn(id)));
    }
    return actions;
  }

  Widget _returnActionBtn(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 20, color: color)),
      ),
    );
  }

  Future<void> _confirmReturn(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد المرتجع'),
          content: const Text('هل تريد تأكيد هذا المرتجع؟ سيتم تعديل المخزون تلقائياً.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.confirmReturn(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأكيد المرتجع'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteReturn(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المرتجع'),
          content: const Text('هل تريد حذف هذا المرتجع نهائياً؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteReturn(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المرتجع'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _cancelReturn(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إلغاء المرتجع'),
          content: const Text('هل تريد إلغاء هذا المرتجع؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء المرتجع')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.cancelReturn(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء المرتجع'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Draft':
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        break;
      case 'Confirmed':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        break;
      case 'Cancelled':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusLabels[status] ?? status,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

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
              fontWeight: FontWeight.w700),
          elevation: 0,
          title: const Text('المرتجعات'),
          actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReturnFormPage(
                      companyId: widget.companyId,
                      returnType: _tabController.index == 0
                          ? 'SalesReturn'
                          : 'PurchaseReturn',
                    ),
                  ),
                ).then((_) => _loadData());
              },
              icon: const Icon(Icons.add),
              label: const Text('مرتجع جديد'),
            ),
            const SizedBox(width: 12),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1A1A2E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF1A1A2E),
            tabs: const [
              Tab(text: 'مرتجع مبيعات'),
              Tab(text: 'مرتجع مشتريات'),
            ],
          ),
        ),
        body: _buildBody(),
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

    return TabBarView(
      controller: _tabController,
      children: [
        _buildTable(_salesReturns, 'لا توجد مرتجعات مبيعات'),
        _buildTable(_purchaseReturns, 'لا توجد مرتجعات مشتريات'),
      ],
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> data, String emptyMsg) {
    if (data.isEmpty) {
      return Center(
        child: Text(emptyMsg,
            style: const TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Table(
          border: TableBorder.all(color: Colors.black54),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade200),
              children: const [
                _Cell('رقم المرتجع', isHeader: true),
                _Cell('التاريخ', isHeader: true),
                _Cell('الفاتورة الأصلية', isHeader: true),
                _Cell('المبلغ', isHeader: true),
                _Cell('الحالة', isHeader: true),
                _Cell('إجراءات', isHeader: true),
              ],
            ),
            ...data.asMap().entries.map((entry) {
              final i = entry.key;
              final m = entry.value;
              final status =
                  (m['Status'] ?? m['status'] ?? '').toString();
              final rId = (m['Id'] ?? m['id'] ?? '').toString();
              return TableRow(
                decoration: BoxDecoration(
                  color: i.isEven ? Colors.white : Colors.grey.shade50,
                ),
                children: [
                  _Cell((m['ReturnNumber'] ?? m['returnNumber'] ?? '-')
                      .toString()),
                  _Cell(_formatDate(
                      (m['Date'] ?? m['date'] ?? '').toString())),
                  _Cell(
                      (m['InvoiceNumber'] ?? m['invoiceNumber'] ?? '-')
                          .toString()),
                  _Cell(fmtN(m['TotalAmount'] ?? m['totalAmount'] ?? m['Amount'] ?? m['amount'])),
                  _CellWidget(child: _statusChip(status)),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _buildReturnActions(rId, status),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool isHeader;
  const _Cell(this.text, {this.isHeader = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: isHeader ? 13 : 12,
        ),
      ),
    );
  }
}

class _CellWidget extends StatelessWidget {
  final Widget child;
  const _CellWidget({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Center(child: child),
    );
  }
}
