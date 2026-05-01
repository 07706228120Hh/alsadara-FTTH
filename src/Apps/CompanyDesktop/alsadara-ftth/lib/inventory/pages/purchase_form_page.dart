import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';

class _OrderItemEntry {
  String? inventoryItemId;
  String? itemName;
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  double get total {
    final qty = int.tryParse(qtyController.text.replaceAll(',', '')) ?? 0;
    final price = parseN(priceController.text);
    return qty * price;
  }
  void dispose() {
    qtyController.dispose();
    priceController.dispose();
  }
}

class PurchaseFormPage extends StatefulWidget {
  final String companyId;
  final PurchaseOrder? existingOrder;
  const PurchaseFormPage({super.key, required this.companyId, this.existingOrder});

  @override
  State<PurchaseFormPage> createState() => _PurchaseFormPageState();
}

class _PurchaseFormPageState extends State<PurchaseFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  List<Supplier> _suppliers = [];
  List<Warehouse> _warehouses = [];
  List<InventoryItem> _inventoryItems = [];

  String? _selectedSupplierId;
  String? _selectedWarehouseId;
  DateTime? _expectedDeliveryDate;
  final _notesController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');

  // نوع الدفع: نقد أو آجل
  String _paymentType = 'نقد';

  List<_OrderItemEntry> _items = [];

  bool get _isEditing => widget.existingOrder != null;

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _discountController.dispose();
    _taxController.dispose();
    for (final item in _items) { item.dispose(); }
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    try {
      final results = await Future.wait([
        _api.getSuppliers(companyId: widget.companyId),
        _api.getWarehouses(companyId: widget.companyId),
        _api.getItems(companyId: widget.companyId, pageSize: 500),
      ]);
      if (!mounted) return;
      setState(() {
        _suppliers = (results[0]['data'] as List? ?? []).map((e) => Supplier.fromJson(e as Map<String, dynamic>)).toList();
        _warehouses = (results[1]['data'] as List? ?? []).map((e) => Warehouse.fromJson(e as Map<String, dynamic>)).toList();
        _inventoryItems = (results[2]['data'] as List? ?? []).map((e) => InventoryItem.fromJson(e as Map<String, dynamic>)).toList();
        _loading = false;
      });
      if (_isEditing) { _populateFromExisting(); } else { _addItem(); }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحميل البيانات: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _populateFromExisting() {
    final order = widget.existingOrder!;
    _selectedSupplierId = order.supplierId;
    _selectedWarehouseId = order.warehouseId;
    _expectedDeliveryDate = order.expectedDeliveryDate;
    _notesController.text = order.notes ?? '';
    _discountController.text = fmtN(order.discountAmount ?? 0);
    _taxController.text = fmtN(order.taxAmount ?? 0);
    if (order.items != null) {
      for (final item in order.items!) {
        final entry = _OrderItemEntry()
          ..inventoryItemId = item.inventoryItemId
          ..itemName = item.itemName
          ..qtyController.text = item.quantity.toString()
          ..priceController.text = fmtN(item.unitPrice);
        _items.add(entry);
      }
    }
    if (_items.isEmpty) _addItem();
    setState(() {});
  }

  void _addItem() {
    setState(() => _items.add(_OrderItemEntry()));
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() { _items[index].dispose(); _items.removeAt(index); });
  }

  double get _subtotal => _items.fold(0.0, (sum, e) => sum + e.total);
  double get _discount => parseN(_discountController.text);
  double get _tax => parseN(_taxController.text);
  double get _net => _subtotal - _discount + _tax;

  // ═══ إضافة متعددة ═══
  Future<void> _showMultiSelectDialog() async {
    final selected = <String>{};
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('اختيار مواد متعددة'),
            content: SizedBox(
              width: 400,
              height: 400,
              child: ListView(
                children: _inventoryItems.map((item) {
                  // لا نعرض المواد المضافة سابقاً
                  final alreadyAdded = _items.any((e) => e.inventoryItemId == item.id);
                  return CheckboxListTile(
                    value: selected.contains(item.id) || alreadyAdded,
                    enabled: !alreadyAdded,
                    title: Text(item.name, style: TextStyle(fontSize: 13, color: alreadyAdded ? Colors.grey : null)),
                    subtitle: alreadyAdded ? const Text('مضاف مسبقاً', style: TextStyle(fontSize: 11, color: Colors.grey)) : null,
                    dense: true,
                    onChanged: alreadyAdded ? null : (v) => setD(() {
                      if (v == true) { selected.add(item.id); } else { selected.remove(item.id); }
                    }),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                onPressed: selected.isEmpty ? null : () {
                  for (final id in selected) {
                    final item = _inventoryItems.firstWhere((i) => i.id == id);
                    final entry = _OrderItemEntry()
                      ..inventoryItemId = item.id
                      ..itemName = item.name
                      ..priceController.text = fmtN(item.costPrice);
                    _items.add(entry);
                  }
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: Text('إضافة ${selected.length} مادة'),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _pickDeliveryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDeliveryDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) setState(() => _expectedDeliveryDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final validItems = _items.where((e) => e.inventoryItemId != null).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنف واحد على الأقل'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _saving = true);

    final data = {
      'companyId': widget.companyId,
      'supplierId': _selectedSupplierId,
      'warehouseId': _selectedWarehouseId,
      'expectedDeliveryDate': _expectedDeliveryDate?.toIso8601String(),
      'notes': '${_paymentType == 'آجل' ? '[آجل] ' : '[نقد] '}${_notesController.text}',
      'discountAmount': _discount,
      'taxAmount': _tax,
      'items': validItems.map((e) => {
        'inventoryItemId': e.inventoryItemId,
        'quantity': int.tryParse(e.qtyController.text.replaceAll(',', '')) ?? 0,
        'unitPrice': parseN(e.priceController.text),
      }).toList(),
    };

    try {
      if (_isEditing) {
        await _api.updatePurchaseOrder(widget.existingOrder!.id, data: data);
      } else {
        await _api.createPurchaseOrder(data: data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEditing ? 'تم تحديث أمر الشراء' : 'تم إنشاء أمر الشراء'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)), titleTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700), elevation: 0,
          title: Text(_isEditing ? 'تعديل أمر شراء' : 'أمر شراء جديد'),
        ),
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
                    const SizedBox(height: 20),
                    _buildTotalsSection(),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(_isEditing ? 'تحديث' : 'حفظ', style: const TextStyle(fontSize: 16)),
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
            // المورد
            SizedBox(
              width: 250,
              child: DropdownButtonFormField<String>(
                value: _selectedSupplierId,
                decoration: const InputDecoration(labelText: 'المورد *', border: OutlineInputBorder()),
                validator: (v) => v == null ? 'اختر المورد' : null,
                items: _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (v) => setState(() => _selectedSupplierId = v),
              ),
            ),
            // المستودع
            SizedBox(
              width: 250,
              child: DropdownButtonFormField<String>(
                value: _selectedWarehouseId,
                decoration: const InputDecoration(labelText: 'المستودع *', border: OutlineInputBorder()),
                validator: (v) => v == null ? 'اختر المستودع' : null,
                items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                onChanged: (v) => setState(() => _selectedWarehouseId = v),
              ),
            ),
            // نوع الدفع
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                value: _paymentType,
                decoration: const InputDecoration(labelText: 'نوع الدفع *', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                  DropdownMenuItem(value: 'آجل', child: Text('آجل')),
                ],
                onChanged: (v) => setState(() => _paymentType = v ?? 'نقد'),
              ),
            ),
            // تاريخ التسليم
            SizedBox(
              width: 250,
              child: InkWell(
                onTap: _pickDeliveryDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'تاريخ التسليم المتوقع', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)),
                  child: Text(
                    _expectedDeliveryDate != null
                        ? '${_expectedDeliveryDate!.year}/${_expectedDeliveryDate!.month.toString().padLeft(2, '0')}/${_expectedDeliveryDate!.day.toString().padLeft(2, '0')}'
                        : 'اختر تاريخ',
                    style: TextStyle(color: _expectedDeliveryDate != null ? null : Colors.grey),
                  ),
                ),
              ),
            ),
            // ملاحظات
            SizedBox(
              width: 520,
              child: TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder()),
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
            Row(children: [
              const Text('الأصناف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _showMultiSelectDialog,
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: const Text('تحديد متعدد'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة صنف'),
              ),
            ]),
            const SizedBox(height: 12),
            for (int i = 0; i < _items.length; i++) _buildItemRow(i),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final entry = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${index + 1}.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<String>(
              value: entry.inventoryItemId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'المادة', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: _inventoryItems.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) {
                setState(() {
                  entry.inventoryItemId = v;
                  final found = _inventoryItems.where((i) => i.id == v);
                  if (found.isNotEmpty) {
                    entry.itemName = found.first.name;
                    // سعر الوحدة تلقائي من سعر التكلفة
                    entry.priceController.text = fmtN(found.first.costPrice);
                    // إذا كان آخر سطر، أضف سطر جديد تلقائياً
                    if (index == _items.length - 1) _addItem();
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextFormField(
              controller: entry.qtyController,
              decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: TextFormField(
              controller: entry.priceController,
              decoration: const InputDecoration(labelText: 'سعر الوحدة', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'الإجمالي', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              child: Text(fmtN(entry.total)),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.delete_outline, color: _items.length > 1 ? Colors.red : Colors.grey),
            onPressed: _items.length > 1 ? () => _removeItem(index) : null,
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _totalRow('المجموع', _subtotal),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 100, child: Text('الخصم')),
            SizedBox(width: 150, child: TextFormField(
              controller: _discountController,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            )),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 100, child: Text('الضريبة')),
            SizedBox(width: 150, child: TextFormField(
              controller: _taxController,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            )),
          ]),
          const Divider(height: 20),
          _totalRow('الصافي', _net, bold: true),
        ]),
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontSize: bold ? 18 : 14, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Row(children: [
      SizedBox(width: 100, child: Text(label, style: style)),
      Text(fmtN(value), style: style),
    ]);
  }
}
