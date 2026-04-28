import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';

class StockLevelsPage extends StatefulWidget {
  final String companyId;
  const StockLevelsPage({super.key, required this.companyId});

  @override
  State<StockLevelsPage> createState() => _StockLevelsPageState();
}

class _StockLevelsPageState extends State<StockLevelsPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _stockRows = [];
  List<Warehouse> _warehouses = [];

  String? _selectedWarehouseId;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
    _loadData();
  }

  Future<void> _loadWarehouses() async {
    try {
      final res = await _api.getWarehouses(companyId: widget.companyId);
      final list = (res['data'] as List<dynamic>?) ?? [];
      _warehouses =
          list.map((e) => Warehouse.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getStockLevels(
        companyId: widget.companyId,
        warehouseId: _selectedWarehouseId,
      );
      final list = (res['data'] as List<dynamic>?) ?? [];
      _stockRows = list.cast<Map<String, dynamic>>();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  // --------------- Helpers ---------------

  Widget _statusChip(Map<String, dynamic> row) {
    final current = (row['currentQuantity'] as num?)?.toInt() ?? 0;
    final min = (row['minStockLevel'] as num?)?.toInt() ?? 0;

    String label;
    Color bg;
    Color fg;

    if (min <= 0 || current >= min) {
      label = 'كافي';
      bg = Colors.green.shade50;
      fg = Colors.green.shade800;
    } else if (current >= (min * 0.5).round()) {
      label = 'منخفض';
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade800;
    } else {
      label = 'ناقص';
      bg = Colors.red.shade50;
      fg = Colors.red.shade800;
    }

    return Chip(
      label: Text(label, style: TextStyle(color: fg, fontSize: 12)),
      backgroundColor: bg,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  // --------------- Build ---------------

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), elevation: 0,
          title: const Text('مستويات المخزون'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'تحديث',
                onPressed: _loadData),
          ],
        ),
        body: Column(
          children: [
            _buildFilter(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String?>(
              value: _selectedWarehouseId,
              decoration: const InputDecoration(
                  labelText: 'المستودع',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('جميع المستودعات')),
                ..._warehouses.map((w) =>
                    DropdownMenuItem(value: w.id, child: Text(w.name))),
              ],
              onChanged: (v) {
                _selectedWarehouseId = v;
                _loadData();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_stockRows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('لا توجد بيانات مخزون',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
          columns: const [
            DataColumn(label: Text('المادة')),
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('المستودع')),
            DataColumn(label: Text('الكمية الحالية'), numeric: true),
            DataColumn(label: Text('المحجوز'), numeric: true),
            DataColumn(label: Text('المتاح'), numeric: true),
            DataColumn(label: Text('متوسط التكلفة'), numeric: true),
            DataColumn(label: Text('القيمة'), numeric: true),
            DataColumn(label: Text('الحالة')),
          ],
          rows: _stockRows.map((row) {
            final current = (row['currentQuantity'] as num?)?.toInt() ?? 0;
            final reserved =
                (row['reservedQuantity'] as num?)?.toInt() ?? 0;
            final available = current - reserved;
            final avgCost =
                (row['averageCost'] as num?)?.toDouble() ?? 0.0;
            final value = current * avgCost;

            return DataRow(cells: [
              DataCell(Text(row['itemName'] as String? ?? '-')),
              DataCell(Text(row['itemSku'] as String? ?? '-')),
              DataCell(Text(row['warehouseName'] as String? ?? '-')),
              DataCell(Text('$current')),
              DataCell(Text('$reserved')),
              DataCell(Text('$available')),
              DataCell(Text(fmtN(avgCost))),
              DataCell(Text(fmtN(value))),
              DataCell(_statusChip(row)),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
