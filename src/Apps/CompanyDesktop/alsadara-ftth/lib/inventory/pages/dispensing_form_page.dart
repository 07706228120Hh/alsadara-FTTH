import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';

class _DispenseItemEntry {
  String? inventoryItemId;
  String? itemName;
  int? availableQty;
  final TextEditingController qtyController = TextEditingController();

  void dispose() {
    qtyController.dispose();
  }
}

class DispensingFormPage extends StatefulWidget {
  final String companyId;

  const DispensingFormPage({super.key, required this.companyId});

  @override
  State<DispensingFormPage> createState() => _DispensingFormPageState();
}

class _DispensingFormPageState extends State<DispensingFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  List<Warehouse> _warehouses = [];
  List<InventoryItem> _inventoryItems = [];

  String? _selectedWarehouseId;
  String _type = 'Dispensing';
  final _technicianController = TextEditingController();
  final _serviceRequestController = TextEditingController();
  final _notesController = TextEditingController();

  List<_DispenseItemEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
  }

  @override
  void dispose() {
    _technicianController.dispose();
    _serviceRequestController.dispose();
    _notesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    try {
      final results = await Future.wait([
        _api.getWarehouses(companyId: widget.companyId),
        _api.getItems(companyId: widget.companyId, pageSize: 500),
      ]);

      final warehouseList = results[0]['data'] as List<dynamic>? ?? [];
      final itemList = results[1]['data'] as List<dynamic>? ?? [];

      if (!mounted) return;
      setState(() {
        _warehouses = warehouseList
            .map((e) => Warehouse.fromJson(e as Map<String, dynamic>))
            .toList();
        _inventoryItems = itemList
            .map((e) => InventoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
      _addItem();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل تحميل البيانات: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _addItem() {
    setState(() => _items.add(_DispenseItemEntry()));
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  int _getAvailableQty(String itemId) {
    final item = _inventoryItems.where((i) => i.id == itemId);
    if (item.isEmpty) return 0;
    if (_selectedWarehouseId != null && item.first.stocks != null) {
      final wStock = item.first.stocks!
          .where((s) => s.warehouseId == _selectedWarehouseId);
      if (wStock.isNotEmpty) return wStock.first.currentQuantity;
    }
    return item.first.totalStock ?? 0;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final validItems = _items.where((e) => e.inventoryItemId != null).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('أضف مادة واحدة على الأقل'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    // Stock validation for dispensing type
    if (_type == 'Dispensing') {
      for (final entry in validItems) {
        final qty = int.tryParse(entry.qtyController.text) ?? 0;
        final available = _getAvailableQty(entry.inventoryItemId!);
        if (qty > available) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'الكمية المطلوبة (${entry.itemName ?? ''}) أكبر من المتوفر ($available)'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);

    final data = {
      'companyId': widget.companyId,
      'technicianId': _technicianController.text,
      'technicianName': _technicianController.text,
      'warehouseId': _selectedWarehouseId,
      'serviceRequestId': _serviceRequestController.text.isEmpty
          ? null
          : _serviceRequestController.text,
      'type': _type,
      'notes': _notesController.text.isEmpty ? null : _notesController.text,
      'items': validItems.map((e) {
        return {
          'inventoryItemId': e.inventoryItemId,
          'quantity': int.tryParse(e.qtyController.text) ?? 0,
        };
      }).toList(),
    };

    try {
      await _api.createDispensing(data: data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم إنشاء سند الصرف'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), elevation: 0,title: const Text('صرف جديد')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeaderFields(),
                    const SizedBox(height: 20),
                    _buildItemsSection(),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('حفظ'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderFields() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 250,
              child: TextFormField(
                controller: _technicianController,
                decoration: const InputDecoration(
                  labelText: 'الفني *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'أدخل اسم الفني' : null,
              ),
            ),
            SizedBox(
              width: 250,
              child: DropdownButtonFormField<String>(
                value: _selectedWarehouseId,
                decoration: const InputDecoration(
                  labelText: 'المستودع *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null ? 'اختر المستودع' : null,
                items: _warehouses
                    .map((w) =>
                        DropdownMenuItem(value: w.id, child: Text(w.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedWarehouseId = v),
              ),
            ),
            SizedBox(
              width: 200,
              child: TextFormField(
                controller: _serviceRequestController,
                decoration: const InputDecoration(
                  labelText: 'رقم طلب الخدمة',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            SizedBox(
              width: 250,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('النوع', style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('صرف'),
                          value: 'Dispensing',
                          groupValue: _type,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _type = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('إرجاع'),
                          value: 'Return',
                          groupValue: _type,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setState(() => _type = v!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 520,
              child: TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('المواد',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة مادة'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _items.length; i++) _buildItemRow(i),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final entry = _items[index];
    final available = entry.inventoryItemId != null
        ? _getAvailableQty(entry.inventoryItemId!)
        : 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('${index + 1}.',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<String>(
              value: entry.inventoryItemId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'المادة',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: _inventoryItems
                  .map((item) => DropdownMenuItem(
                        value: item.id,
                        child: Text('${item.name} (${item.sku})',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  entry.inventoryItemId = v;
                  final found = _inventoryItems.where((i) => i.id == v);
                  if (found.isNotEmpty) {
                    entry.itemName = found.first.name;
                    entry.availableQty = _getAvailableQty(v!);
                  }
                });
              },
            ),
          ),
          if (_type == 'Dispensing' && entry.inventoryItemId != null) ...[
            const SizedBox(width: 4),
            Text('متوفر: $available',
                style: TextStyle(
                  fontSize: 11,
                  color: available > 0 ? Colors.green.shade700 : Colors.red,
                  fontWeight: FontWeight.w600,
                )),
          ],
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextFormField(
              controller: entry.qtyController,
              decoration: const InputDecoration(
                labelText: 'الكمية',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: _items.length > 1 ? Colors.red : Colors.grey),
            onPressed: _items.length > 1 ? () => _removeItem(index) : null,
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }
}
