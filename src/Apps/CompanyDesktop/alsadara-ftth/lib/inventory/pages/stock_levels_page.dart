import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
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
      // normalize keys: PascalCase → camelCase
      _stockRows = list.map((e) {
        final m = e as Map<String, dynamic>;
        return <String, dynamic>{
          for (final k in m.keys)
            '${k[0].toLowerCase()}${k.substring(1)}': m[k],
          ...m, // keep originals too
        };
      }).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: SdText.bodySm,
        filled: true,
        fillColor: SdColors.surface,
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

  // --------------- Adjust / Transfer Dialogs ---------------

  Future<void> _showAdjustDialog() async {
    String? selectedItemId;
    String? selectedWarehouseId = _selectedWarehouseId;
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();

    // load items for dropdown
    List<InventoryItem> items = [];
    try {
      final res = await _api.getItems(companyId: widget.companyId, pageSize: 500);
      items = ((res['data'] as List?) ?? []).map((e) => InventoryItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعديل رصيد المخزون (جرد)'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedWarehouseId,
                    decoration: _dec('المستودع'),
                    items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                    onChanged: (v) => setD(() => selectedWarehouseId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedItemId,
                    isExpanded: true,
                    decoration: _dec('المادة'),
                    items: items.map((i) => DropdownMenuItem(value: i.id, child: Text(i.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setD(() => selectedItemId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: qtyController, decoration: _dec('الكمية الجديدة'), keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  TextField(controller: reasonController, decoration: _dec('السبب')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.primary), onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
            ],
          ),
        );
      }),
    );
    if (ok != true || selectedItemId == null || selectedWarehouseId == null) return;
    try {
      await _api.adjustStock(data: {
        'warehouseId': selectedWarehouseId,
        'inventoryItemId': selectedItemId,
        'newQuantity': int.tryParse(qtyController.text) ?? 0,
        'reason': reasonController.text,
        'companyId': widget.companyId,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل الرصيد'), backgroundColor: SdColors.success));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  Future<void> _showTransferDialog() async {
    String? selectedItemId;
    String? sourceWarehouseId = _selectedWarehouseId;
    String? destWarehouseId;
    final qtyController = TextEditingController();

    List<InventoryItem> items = [];
    try {
      final res = await _api.getItems(companyId: widget.companyId, pageSize: 500);
      items = ((res['data'] as List?) ?? []).map((e) => InventoryItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تحويل بين المستودعات'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: sourceWarehouseId,
                    decoration: _dec('من مستودع'),
                    items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                    onChanged: (v) => setD(() => sourceWarehouseId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: destWarehouseId,
                    decoration: _dec('إلى مستودع'),
                    items: _warehouses.where((w) => w.id != sourceWarehouseId).map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                    onChanged: (v) => setD(() => destWarehouseId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedItemId,
                    isExpanded: true,
                    decoration: _dec('المادة'),
                    items: items.map((i) => DropdownMenuItem(value: i.id, child: Text(i.name, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setD(() => selectedItemId = v),
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: qtyController, decoration: _dec('الكمية'), keyboardType: TextInputType.number),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.primary), onPressed: () => Navigator.pop(ctx, true), child: const Text('تحويل')),
            ],
          ),
        );
      }),
    );
    if (ok != true || selectedItemId == null || sourceWarehouseId == null || destWarehouseId == null) return;
    try {
      await _api.transferStock(data: {
        'sourceWarehouseId': sourceWarehouseId,
        'destinationWarehouseId': destWarehouseId,
        'inventoryItemId': selectedItemId,
        'quantity': int.tryParse(qtyController.text) ?? 0,
        'companyId': widget.companyId,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التحويل بنجاح'), backgroundColor: SdColors.success));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  // --------------- Helpers ---------------

  SdStatus _statusFor(Map<String, dynamic> row) {
    final current = (row['currentQuantity'] as num?)?.toInt() ?? 0;
    final min = (row['minStockLevel'] as num?)?.toInt() ?? 0;
    if (min <= 0 || current >= min) return SdStatus.success;
    if (current >= (min * 0.5).round()) return SdStatus.warning;
    return SdStatus.danger;
  }

  Widget _statusChip(Map<String, dynamic> row) {
    final status = _statusFor(row);
    final label = status == SdStatus.success
        ? 'كافي'
        : status == SdStatus.warning
            ? 'منخفض'
            : 'ناقص';
    return SdStatusChip(label, status: status);
  }

  // --------------- Build ---------------

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'مستويات المخزون',
        actions: [
          SdAppBarAction(icon: Icons.tune, label: 'تعديل رصيد', onPressed: _showAdjustDialog),
          SdAppBarAction(icon: Icons.swap_horiz, label: 'تحويل', onPressed: _showTransferDialog),
          SdAppBarAction(icon: Icons.refresh_rounded, label: 'تحديث', onPressed: _loadData),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilter(),
          const SizedBox(height: SdSpace.sm),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilter() {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: context.sd.isPhone ? double.infinity : 280,
        child: DropdownButtonFormField<String?>(
          value: _selectedWarehouseId,
          decoration: _dec('المستودع'),
          items: [
            const DropdownMenuItem(value: null, child: Text('جميع المستودعات')),
            ..._warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))),
          ],
          onChanged: (v) {
            _selectedWarehouseId = v;
            _loadData();
          },
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    if (_error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل المخزون',
          message: _error,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: _loadData),
        ),
      );
    }
    if (_stockRows.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد بيانات مخزون', icon: Icons.inventory_outlined),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _stockRows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildStockCard(_stockRows[i]),
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
              DataColumn(label: Text('المادة')),
              DataColumn(label: Text('المستودع')),
              DataColumn(label: Text('الكمية الحالية'), numeric: true),
              DataColumn(label: Text('المحجوز'), numeric: true),
              DataColumn(label: Text('المتاح'), numeric: true),
              DataColumn(label: Text('متوسط التكلفة'), numeric: true),
              DataColumn(label: Text('القيمة'), numeric: true),
              DataColumn(label: Text('الحالة')),
            ],
            rows: [
              for (int i = 0; i < _stockRows.length; i++) _buildDataRow(_stockRows[i], i),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(Map<String, dynamic> row, int index) {
    final current = (row['currentQuantity'] as num?)?.toInt() ?? 0;
    final reserved = (row['reservedQuantity'] as num?)?.toInt() ?? 0;
    final available = current - reserved;
    final avgCost = (row['averageCost'] as num?)?.toDouble() ?? 0.0;
    final value = current * avgCost;

    return DataRow(
      color: WidgetStateProperty.all(index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      cells: [
        DataCell(Text(row['itemName'] as String? ?? '-')),
        DataCell(Text(row['warehouseName'] as String? ?? '-')),
        DataCell(Text('$current')),
        DataCell(Text('$reserved')),
        DataCell(Text('$available')),
        DataCell(Text(fmtN(avgCost))),
        DataCell(Text(fmtN(value))),
        DataCell(_statusChip(row)),
      ],
    );
  }

  Widget _buildStockCard(Map<String, dynamic> row) {
    final current = (row['currentQuantity'] as num?)?.toInt() ?? 0;
    final reserved = (row['reservedQuantity'] as num?)?.toInt() ?? 0;
    final available = current - reserved;
    final avgCost = (row['averageCost'] as num?)?.toDouble() ?? 0.0;
    final value = current * avgCost;

    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(row['itemName'] as String? ?? '-', style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              _statusChip(row),
            ],
          ),
          const SizedBox(height: 4),
          SdInfoRow(label: 'المستودع', value: row['warehouseName'] as String? ?? '-'),
          SdInfoRow(label: 'الكمية الحالية', value: '$current'),
          SdInfoRow(label: 'المحجوز', value: '$reserved'),
          SdInfoRow(label: 'المتاح', value: '$available'),
          SdInfoRow(label: 'متوسط التكلفة', value: fmtN(avgCost)),
          SdInfoRow(label: 'القيمة', value: fmtN(value)),
        ],
      ),
    );
  }
}
