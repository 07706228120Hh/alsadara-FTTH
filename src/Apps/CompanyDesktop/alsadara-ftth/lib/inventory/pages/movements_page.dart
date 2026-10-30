import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
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

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: SdText.bodySm,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: const BorderSide(color: SdColors.cardEdge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: const BorderSide(color: SdColors.cardEdge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: const BorderSide(color: SdColors.primary, width: 1.5),
        ),
      );

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
    final showPagination = !_loading && _error == null && _movements.isNotEmpty;
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'حركات المخزون',
        actions: [
          SdAppBarAction(icon: Icons.refresh_rounded, label: 'تحديث', onPressed: _loadData),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilters(),
          const SizedBox(height: SdSpace.sm),
          Expanded(child: _buildBody()),
          if (showPagination) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            value: _selectedItemId,
            decoration: _dec('المادة'),
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
            decoration: _dec('المستودع'),
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
            decoration: _dec('نوع الحركة'),
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
            decoration: _dec('من تاريخ'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 16, color: SdColors.faint),
                const SizedBox(width: 6),
                Text(
                  _dateFrom != null ? _formatDate(_dateFrom!) : '---',
                  style: SdText.bodySm,
                ),
                if (_dateFrom != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      setState(() => _dateFrom = null);
                      _page = 1;
                      _loadData();
                    },
                    child: const Icon(Icons.close, size: 14, color: SdColors.faint),
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
            decoration: _dec('إلى تاريخ'),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_today, size: 16, color: SdColors.faint),
                const SizedBox(width: 6),
                Text(
                  _dateTo != null ? _formatDate(_dateTo!) : '---',
                  style: SdText.bodySm,
                ),
                if (_dateTo != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      setState(() => _dateTo = null);
                      _page = 1;
                      _loadData();
                    },
                    child: const Icon(Icons.close, size: 14, color: SdColors.faint),
                  ),
                ],
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _resetFilters,
          icon: const Icon(Icons.filter_alt_off, size: 18, color: SdColors.primary),
          label: const Text('إزالة الفلاتر', style: TextStyle(color: SdColors.primary)),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    if (_error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل الحركات',
          message: _error,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: _loadData),
        ),
      );
    }
    if (_movements.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد حركات', icon: Icons.swap_horiz),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _movements.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(_movements[i]),
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
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(SdColors.primary),
            headingTextStyle: const TextStyle(
                fontFamily: SdText.family, fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
            dataTextStyle: const TextStyle(
                fontFamily: SdText.family, fontSize: 12.5, fontWeight: FontWeight.w500, color: SdColors.ink),
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
            rows: [
              for (int i = 0; i < _movements.length; i++) _buildDataRow(_movements[i], i),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(StockMovement mv, int index) {
    final isIn = _inTypes.contains(mv.movementType);
    final qtyText = isIn ? '+${mv.quantity}' : '-${mv.quantity}';
    final qtyColor = isIn ? SdColors.success : SdColors.danger;

    return DataRow(
      color: WidgetStateProperty.all(index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      cells: [
        DataCell(Text(_formatDateTime(mv.createdAt), style: const TextStyle(fontFamily: SdText.family, fontSize: 12))),
        DataCell(Text(mv.itemName ?? '-')),
        DataCell(Text(mv.warehouseName ?? '-')),
        DataCell(Text(_movementTypeMap[mv.movementType] ?? mv.movementType)),
        DataCell(Text(qtyText,
            style: TextStyle(fontFamily: SdText.family, color: qtyColor, fontWeight: FontWeight.w800))),
        DataCell(Text('${mv.stockBefore}')),
        DataCell(Text('${mv.stockAfter}')),
        DataCell(Text(mv.referenceNumber ?? '-')),
        DataCell(Text(mv.createdByName ?? '-')),
      ],
    );
  }

  Widget _buildCard(StockMovement mv) {
    final isIn = _inTypes.contains(mv.movementType);
    final qtyText = isIn ? '+${mv.quantity}' : '-${mv.quantity}';
    final qtyColor = isIn ? SdColors.success : SdColors.danger;
    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(mv.itemName ?? '-', style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SdStatusChip(_movementTypeMap[mv.movementType] ?? mv.movementType,
                  status: isIn ? SdStatus.success : SdStatus.danger),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text('الكمية', style: SdText.bodySm),
                const Spacer(),
                Text(qtyText,
                    style: TextStyle(fontFamily: SdText.family, fontSize: 14, fontWeight: FontWeight.w800, color: qtyColor)),
              ],
            ),
          ),
          SdInfoRow(label: 'المستودع', value: mv.warehouseName ?? '-'),
          SdInfoRow(label: 'قبل', value: '${mv.stockBefore}'),
          SdInfoRow(label: 'بعد', value: '${mv.stockAfter}'),
          SdInfoRow(label: 'المرجع', value: mv.referenceNumber ?? '-'),
          SdInfoRow(label: 'المستخدم', value: mv.createdByName ?? '-'),
          SdInfoRow(label: 'التاريخ', value: _formatDateTime(mv.createdAt)),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.only(top: SdSpace.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_right, color: SdColors.primary),
            onPressed: _page > 1
                ? () {
                    _page--;
                    _loadData();
                  }
                : null,
          ),
          Text('صفحة $_page من $_totalPages', style: SdText.label),
          IconButton(
            icon: const Icon(Icons.chevron_left, color: SdColors.primary),
            onPressed: _page < _totalPages
                ? () {
                    _page++;
                    _loadData();
                  }
                : null,
          ),
          const SizedBox(width: 16),
          Text('الإجمالي: $_total', style: SdText.bodySm),
        ],
      ),
    );
  }
}
