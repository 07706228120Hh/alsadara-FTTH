import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';

class MovementsPage extends StatefulWidget {
  final String companyId;
  const MovementsPage({super.key, required this.companyId});

  @override
  State<MovementsPage> createState() => _MovementsPageState();
}

class _MovementsPageState extends State<MovementsPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<StockMovement> _movements = [];

  // Pagination
  int _page = 1;
  int _pageSize = 30;
  int _total = 0;

  // Filters
  List<Warehouse> _warehouses = [];
  List<InventoryItem> _allItems = [];

  String? _selectedWarehouseId;
  String? _selectedItemId;
  String? _selectedType;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const Map<String, String> _movementTypeMap = {
    'PurchaseIn': 'وارد شراء',
    'SalesOut': 'صادر بيع',
    'TechnicianDispensing': 'صرف فني',
    'TechnicianReturn': 'إرجاع فني',
    'Adjustment': 'تعديل جرد',
    'TransferIn': 'تحويل وارد',
    'TransferOut': 'تحويل صادر',
    'InitialStock': 'رصيد افتتاحي',
    'Damaged': 'تالف',
  };

  static const Set<String> _inTypes = {
    'PurchaseIn',
    'TechnicianReturn',
    'TransferIn',
    'InitialStock',
    'Adjustment',
  };

  @override
  void initState() {
    super.initState();
    _loadLookups();
    _loadData();
  }

  Future<void> _loadLookups() async {
    try {
      final whRes = await _api.getWarehouses(companyId: widget.companyId);
      final whList = (whRes['items'] as List<dynamic>?) ?? [];
      _warehouses = whList
          .map((e) => Warehouse.fromJson(e as Map<String, dynamic>))
          .toList();

      final itRes = await _api.getItems(
          companyId: widget.companyId, pageSize: 500);
      final itList = (itRes['items'] as List<dynamic>?) ?? [];
      _allItems = itList
          .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
          .toList();

      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getMovements(
        companyId: widget.companyId,
        inventoryItemId: _selectedItemId,
        warehouseId: _selectedWarehouseId,
        movementType: _selectedType,
        from: _dateFrom?.toIso8601String().split('T').first,
        to: _dateTo?.toIso8601String().split('T').first,
        page: _page,
        pageSize: _pageSize,
      );
      final list = (res['data'] as List<dynamic>?) ?? [];
      _movements = list
          .map((e) => StockMovement.fromJson(e as Map<String, dynamic>))
          .toList();
      _total = (res['total'] as int?) ?? _movements.length;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _totalPages => (_total / _pageSize).ceil().clamp(1, 99999);

  void _resetFilters() {
    _selectedWarehouseId = null;
    _selectedItemId = null;
    _selectedType = null;
    _dateFrom = null;
    _dateTo = null;
    _page = 1;
    _loadData();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_dateFrom ?? DateTime.now())
        : (_dateTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime dt) {
    return '${_formatDate(dt)}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // --------------- Build ---------------

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), elevation: 0,
          title: const Text('حركات المخزون'),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'تحديث',
                onPressed: _loadData),
          ],
        ),
        body: Column(
          children: [
            _buildFilters(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
            if (!_loading && _error == null && _movements.isNotEmpty)
              _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String?>(
              value: _selectedItemId,
              decoration: const InputDecoration(
                  labelText: 'المادة',
                  border: OutlineInputBorder(),
                  isDense: true),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('الكل')),
                ..._allItems.map((item) => DropdownMenuItem(
                    value: item.id, child: Text(item.name))),
              ],
              onChanged: (v) {
                _selectedItemId = v;
                _page = 1;
                _loadData();
              },
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String?>(
              value: _selectedWarehouseId,
              decoration: const InputDecoration(
                  labelText: 'المستودع',
                  border: OutlineInputBorder(),
                  isDense: true),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('الكل')),
                ..._warehouses.map((w) =>
                    DropdownMenuItem(value: w.id, child: Text(w.name))),
              ],
              onChanged: (v) {
                _selectedWarehouseId = v;
                _page = 1;
                _loadData();
              },
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String?>(
              value: _selectedType,
              decoration: const InputDecoration(
                  labelText: 'نوع الحركة',
                  border: OutlineInputBorder(),
                  isDense: true),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('الكل')),
                ..._movementTypeMap.entries.map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) {
                _selectedType = v;
                _page = 1;
                _loadData();
              },
            ),
          ),
          // Date From
          InkWell(
            onTap: () => _pickDate(isFrom: true),
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'من تاريخ',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _dateFrom != null ? _formatDate(_dateFrom!) : '---',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (_dateFrom != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        setState(() => _dateFrom = null);
                        _page = 1;
                        _loadData();
                      },
                      child: const Icon(Icons.close, size: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Date To
          InkWell(
            onTap: () => _pickDate(isFrom: false),
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'إلى تاريخ',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _dateTo != null ? _formatDate(_dateTo!) : '---',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (_dateTo != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        setState(() => _dateTo = null);
                        _page = 1;
                        _loadData();
                      },
                      child: const Icon(Icons.close, size: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _resetFilters,
            icon: const Icon(Icons.filter_alt_off, size: 18),
            label: const Text('إزالة الفلاتر'),
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
    if (_movements.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('لا توجد حركات',
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
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('المادة')),
            DataColumn(label: Text('المستودع')),
            DataColumn(label: Text('نوع الحركة')),
            DataColumn(label: Text('الكمية'), numeric: true),
            DataColumn(label: Text('قبل'), numeric: true),
            DataColumn(label: Text('بعد'), numeric: true),
            DataColumn(label: Text('المرجع')),
            DataColumn(label: Text('المستخدم')),
          ],
          rows: _movements.map((mv) {
            final isIn = _inTypes.contains(mv.movementType);
            final qtyText = isIn ? '+${mv.quantity}' : '-${mv.quantity}';
            final qtyColor = isIn ? Colors.green.shade700 : Colors.red.shade700;

            return DataRow(cells: [
              DataCell(Text(_formatDateTime(mv.createdAt),
                  style: const TextStyle(fontSize: 12))),
              DataCell(Text(mv.itemName ?? '-')),
              DataCell(Text(mv.warehouseName ?? '-')),
              DataCell(Text(
                  _movementTypeMap[mv.movementType] ?? mv.movementType)),
              DataCell(Text(qtyText,
                  style: TextStyle(
                      color: qtyColor, fontWeight: FontWeight.bold))),
              DataCell(Text('${mv.stockBefore}')),
              DataCell(Text('${mv.stockAfter}')),
              DataCell(Text(mv.referenceNumber ?? '-')),
              DataCell(Text(mv.createdByName ?? '-')),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _page > 1
                ? () {
                    _page--;
                    _loadData();
                  }
                : null,
          ),
          Text('صفحة $_page من $_totalPages'),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page < _totalPages
                ? () {
                    _page++;
                    _loadData();
                  }
                : null,
          ),
          const SizedBox(width: 16),
          Text('الإجمالي: $_total',
              style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
