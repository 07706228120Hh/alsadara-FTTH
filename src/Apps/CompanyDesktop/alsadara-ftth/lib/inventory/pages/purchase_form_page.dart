import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحميل البيانات: $e'), backgroundColor: SdColors.danger));
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
                    activeColor: SdColors.primary,
                    title: Text(item.name,
                        style: TextStyle(
                            fontFamily: SdText.family,
                            fontSize: 13,
                            color: alreadyAdded ? SdColors.faint : SdColors.ink)),
                    subtitle: alreadyAdded
                        ? const Text('مضاف مسبقاً',
                            style: TextStyle(
                                fontFamily: SdText.family, fontSize: 11.5, color: SdColors.faint))
                        : null,
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
                style: FilledButton.styleFrom(backgroundColor: SdColors.primary, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف صنف واحد على الأقل'), backgroundColor: SdColors.warning));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEditing ? 'تم تحديث أمر الشراء' : 'تم إنشاء أمر الشراء'), backgroundColor: SdColors.success));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: SdColors.danger));
      }
    }
  }

  InputDecoration _dec(String? label, {bool dense = false, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: SdText.bodySm,
      filled: true,
      fillColor: SdColors.surface,
      isDense: dense,
      suffixIcon: suffixIcon,
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : null,
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
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      maxWidth: double.infinity, // عرض كامل الشاشة (كصفحات المحاسبة/FTTH)
      appBar: SdAppBar(title: _isEditing ? 'تعديل أمر شراء' : 'أمر شراء جديد'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildHeaderFields(),
                  const SizedBox(height: SdSpace.lg),
                  _buildItemsSection(),
                  const SizedBox(height: SdSpace.lg),
                  _buildTotalsSection(),
                  const SizedBox(height: SdSpace.xl),
                  _buildSaveButton(),
                  const SizedBox(height: SdSpace.md),
                ],
              ),
            ),
    );
  }

  Widget _buildSaveButton() {
    if (_saving) {
      return Opacity(
        opacity: .7,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SdRadius.md),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SdColors.primaryMid, SdColors.primary],
            ),
            boxShadow: const [BoxShadow(color: SdColors.primaryEdge, offset: Offset(0, 6))],
          ),
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
          ),
        ),
      );
    }
    return SdButton(
      label: _isEditing ? 'تحديث' : 'حفظ',
      icon: Icons.save_rounded,
      expand: true,
      onPressed: _save,
    );
  }

  Widget _buildHeaderFields() {
    return InvCard(
      title: 'بيانات أمر الشراء',
      icon: Icons.shopping_cart_rounded,
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          // المورد
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              value: _selectedSupplierId,
              style: SdText.label,
              isExpanded: true,
              decoration: _dec('المورد *'),
              validator: (v) => v == null ? 'اختر المورد' : null,
              items: _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _selectedSupplierId = v),
            ),
          ),
          // المستودع
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              value: _selectedWarehouseId,
              style: SdText.label,
              isExpanded: true,
              decoration: _dec('المستودع *'),
              validator: (v) => v == null ? 'اختر المستودع' : null,
              items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _selectedWarehouseId = v),
            ),
          ),
          // نوع الدفع
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _paymentType,
              style: SdText.label,
              decoration: _dec('نوع الدفع *'),
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
                decoration: _dec('تاريخ التسليم المتوقع',
                    suffixIcon: const Icon(Icons.calendar_today, size: 18, color: SdColors.faint)),
                child: Text(
                  _expectedDeliveryDate != null
                      ? '${_expectedDeliveryDate!.year}/${_expectedDeliveryDate!.month.toString().padLeft(2, '0')}/${_expectedDeliveryDate!.day.toString().padLeft(2, '0')}'
                      : 'اختر تاريخ',
                  style: TextStyle(
                      fontFamily: SdText.family,
                      color: _expectedDeliveryDate != null ? SdColors.ink : SdColors.faint),
                ),
              ),
            ),
          ),
          // ملاحظات
          SizedBox(
            width: 520,
            child: TextFormField(
              controller: _notesController,
              style: SdText.label,
              decoration: _dec('ملاحظات'),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    final phone = context.sd.isPhone;
    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Expanded: SdSectionHeader يحوي Spacer داخلياً فيلزمه عرض محدود (تفادي انهيار التخطيط).
            const Expanded(child: SdSectionHeader(title: 'الأصناف')),
            _toolbarBtn(Icons.checklist_rounded, 'تحديد متعدد', _showMultiSelectDialog),
            const SizedBox(width: 8),
            _toolbarBtn(Icons.add, 'إضافة صنف', _addItem),
          ]),
          const SizedBox(height: 12),
          for (int i = 0; i < _items.length; i++)
            phone ? _buildItemCardPhone(i) : _buildItemRow(i),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, String label, VoidCallback onTap) {
    return SdRaised(
      onTap: onTap,
      semanticLabel: label,
      radius: SdRadius.sm,
      depth: 3,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: SdColors.surfaceAlt,
      edgeColor: SdColors.cardEdge,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: SdColors.primary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: SdColors.primary)),
        ],
      ),
    );
  }

  Widget _itemDropdown(_OrderItemEntry entry, int index) => DropdownButtonFormField<String>(
        value: entry.inventoryItemId,
        isExpanded: true,
        style: SdText.label,
        decoration: _dec('المادة', dense: true),
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
      );

  Widget _qtyField(_OrderItemEntry entry) => TextFormField(
        controller: entry.qtyController,
        style: SdText.label,
        decoration: _dec('الكمية', dense: true),
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
      );

  Widget _priceField(_OrderItemEntry entry) => TextFormField(
        controller: entry.priceController,
        style: SdText.label,
        decoration: _dec('سعر الوحدة', dense: true),
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
      );

  Widget _buildItemRow(int index) {
    final entry = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${index + 1}.', style: SdText.label),
            ),
          ),
          Expanded(flex: 4, child: _itemDropdown(entry, index)),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: _qtyField(entry)),
          const SizedBox(width: 8),
          SizedBox(width: 120, child: _priceField(entry)),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: InputDecorator(
              decoration: _dec('الإجمالي', dense: true),
              child: Text(fmtN(entry.total), style: SdText.label),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.delete_outline, color: _items.length > 1 ? SdColors.danger : SdColors.faint),
            onPressed: _items.length > 1 ? () => _removeItem(index) : null,
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }

  Widget _buildItemCardPhone(int index) {
    final entry = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(SdSpace.sm),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: kInvFrameEdge, width: kInvFrameWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${index + 1}.', style: SdText.label),
              const SizedBox(width: 6),
              Expanded(child: _itemDropdown(entry, index)),
              IconButton(
                icon: Icon(Icons.delete_outline, color: _items.length > 1 ? SdColors.danger : SdColors.faint),
                onPressed: _items.length > 1 ? () => _removeItem(index) : null,
                tooltip: 'حذف',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _qtyField(entry)),
              const SizedBox(width: 8),
              Expanded(child: _priceField(entry)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('الإجمالي', style: SdText.bodySm),
              const Spacer(),
              Text(fmtN(entry.total), style: SdText.label),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection() {
    return InvCard(
      title: 'المجاميع',
      icon: Icons.calculate_rounded,
      child: Column(children: [
        _totalRow('المجموع', _subtotal),
        const SizedBox(height: 8),
        Row(children: [
          const SizedBox(width: 100, child: Text('الخصم', style: SdText.body)),
          SizedBox(width: 150, child: TextFormField(
            controller: _discountController,
            style: SdText.label,
            decoration: _dec(null, dense: true),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const SizedBox(width: 100, child: Text('الضريبة', style: SdText.body)),
          SizedBox(width: 150, child: TextFormField(
            controller: _taxController,
            style: SdText.label,
            decoration: _dec(null, dense: true),
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          )),
        ]),
        const Divider(height: 20, color: SdColors.divider),
        _totalRow('الصافي', _net, bold: true),
      ]),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false}) {
    return Row(children: [
      SizedBox(
          width: 100,
          child: Text(label, style: bold ? SdText.titleSm : SdText.body)),
      Text(fmtN(value),
          style: bold
              ? SdText.titleSm.copyWith(color: SdColors.primary)
              : SdText.label),
    ]);
  }
}
