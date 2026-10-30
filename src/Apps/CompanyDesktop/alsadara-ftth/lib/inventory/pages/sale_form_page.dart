import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';

class _SaleItemEntry {
  String? inventoryItemId;
  String? itemName;
  int? availableQty;
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  double get total {
    final qty = int.tryParse(qtyController.text) ?? 0;
    final price = double.tryParse(priceController.text) ?? 0;
    return qty * price;
  }

  void dispose() {
    qtyController.dispose();
    priceController.dispose();
  }
}

class SaleFormPage extends StatefulWidget {
  final String companyId;

  const SaleFormPage({super.key, required this.companyId});

  @override
  State<SaleFormPage> createState() => _SaleFormPageState();
}

class _SaleFormPageState extends State<SaleFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  List<Warehouse> _warehouses = [];
  List<InventoryItem> _inventoryItems = [];

  String? _selectedWarehouseId;
  String _paymentMethod = 'Cash';
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _notesController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');

  List<_SaleItemEntry> _items = [];

  static const _paymentMethods = {
    'Cash': 'نقدي',
    'BankTransfer': 'تحويل بنكي',
    'ZainCash': 'زين كاش',
  };

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _notesController.dispose();
    _discountController.dispose();
    _taxController.dispose();
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
          SnackBar(content: Text('فشل تحميل البيانات: $e'), backgroundColor: SdColors.danger),
        );
      }
    }
  }

  void _addItem() {
    setState(() => _items.add(_SaleItemEntry()));
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  double get _subtotal => _items.fold(0.0, (sum, e) => sum + e.total);
  double get _discount => double.tryParse(_discountController.text) ?? 0;
  double get _tax => double.tryParse(_taxController.text) ?? 0;
  double get _net => _subtotal - _discount + _tax;

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
            content: Text('أضف صنف واحد على الأقل'), backgroundColor: SdColors.warning),
      );
      return;
    }

    // Stock validation
    for (final entry in validItems) {
      final qty = int.tryParse(entry.qtyController.text) ?? 0;
      final available = _getAvailableQty(entry.inventoryItemId!);
      if (qty > available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'الكمية المطلوبة (${entry.itemName ?? ''}) أكبر من المتوفر ($available)'),
            backgroundColor: SdColors.warning,
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    final data = {
      'companyId': widget.companyId,
      'customerName': _customerNameController.text.isEmpty
          ? null
          : _customerNameController.text,
      'customerPhone': _customerPhoneController.text.isEmpty
          ? null
          : _customerPhoneController.text,
      'warehouseId': _selectedWarehouseId,
      'paymentMethod': _paymentMethod,
      'notes': _notesController.text.isEmpty ? null : _notesController.text,
      'discountAmount': _discount,
      'taxAmount': _tax,
      'items': validItems.map((e) {
        return {
          'inventoryItemId': e.inventoryItemId,
          'quantity': int.tryParse(e.qtyController.text) ?? 0,
          'unitPrice': double.tryParse(e.priceController.text) ?? 0,
        };
      }).toList(),
    };

    try {
      await _api.createSalesOrder(data: data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم إنشاء عملية البيع'), backgroundColor: SdColors.success),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: SdColors.danger),
        );
      }
    }
  }

  InputDecoration _dec(String? label, {bool dense = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: SdText.bodySm,
      filled: true,
      fillColor: SdColors.surface,
      isDense: dense,
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
      appBar: const SdAppBar(title: 'بيع جديد'),
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
      label: 'حفظ',
      icon: Icons.save_rounded,
      expand: true,
      onPressed: _save,
    );
  }

  Widget _buildHeaderFields() {
    return InvCard(
      title: 'بيانات البيع',
      icon: Icons.point_of_sale_rounded,
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 250,
            child: TextFormField(
              controller: _customerNameController,
              style: SdText.label,
              decoration: _dec('اسم العميل'),
            ),
          ),
          SizedBox(
            width: 200,
            child: TextFormField(
              controller: _customerPhoneController,
              style: SdText.label,
              decoration: _dec('هاتف العميل'),
              keyboardType: TextInputType.phone,
            ),
          ),
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              value: _selectedWarehouseId,
              style: SdText.label,
              isExpanded: true,
              decoration: _dec('المستودع *'),
              validator: (v) => v == null ? 'اختر المستودع' : null,
              items: _warehouses
                  .map((w) => DropdownMenuItem(
                      value: w.id,
                      child: Text(w.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedWarehouseId = v),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              value: _paymentMethod,
              style: SdText.label,
              decoration: _dec('طريقة الدفع *'),
              items: _paymentMethods.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _paymentMethod = v);
              },
            ),
          ),
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
          Row(
            children: [
              // Expanded: SdSectionHeader يحوي Spacer داخلياً فيلزمه عرض محدود؛
              // بلا Expanded يصله عرض لانهائي داخل Row ⇒ انهيار تخطيط وصفحة بيضاء.
              const Expanded(child: SdSectionHeader(title: 'الأصناف')),
              _toolbarBtn(Icons.add, 'إضافة صنف', _addItem),
            ],
          ),
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

  Widget _itemDropdown(_SaleItemEntry entry) => DropdownButtonFormField<String>(
        value: entry.inventoryItemId,
        isExpanded: true,
        style: SdText.label,
        decoration: _dec('المادة', dense: true),
        items: _inventoryItems
            .map((item) => DropdownMenuItem(
                  value: item.id,
                  child: Text(item.name, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) {
          setState(() {
            entry.inventoryItemId = v;
            final found = _inventoryItems.where((i) => i.id == v);
            if (found.isNotEmpty) {
              entry.itemName = found.first.name;
              entry.availableQty = _getAvailableQty(v!);
              if (entry.priceController.text.isEmpty) {
                entry.priceController.text =
                    fmtN(found.first.sellingPrice ?? found.first.costPrice);
              }
            }
          });
        },
      );

  Widget _availableLabel(int available) => Text('متوفر: $available',
      style: TextStyle(
        fontFamily: SdText.family,
        fontSize: 11.5,
        color: available > 0 ? SdColors.success : SdColors.danger,
        fontWeight: FontWeight.w700,
      ));

  Widget _qtyField(_SaleItemEntry entry) => TextFormField(
        controller: entry.qtyController,
        style: SdText.label,
        decoration: _dec('الكمية', dense: true),
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
      );

  Widget _priceField(_SaleItemEntry entry) => TextFormField(
        controller: entry.priceController,
        style: SdText.label,
        decoration: _dec('سعر الوحدة', dense: true),
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
      );

  Widget _buildItemRow(int index) {
    final entry = _items[index];
    final available = entry.inventoryItemId != null
        ? _getAvailableQty(entry.inventoryItemId!)
        : 0;
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
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _itemDropdown(entry),
                if (entry.inventoryItemId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _availableLabel(available),
                  ),
              ],
            ),
          ),
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
            icon: Icon(Icons.delete_outline,
                color: _items.length > 1 ? SdColors.danger : SdColors.faint),
            onPressed: _items.length > 1 ? () => _removeItem(index) : null,
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }

  Widget _buildItemCardPhone(int index) {
    final entry = _items[index];
    final available = entry.inventoryItemId != null
        ? _getAvailableQty(entry.inventoryItemId!)
        : 0;
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
              Expanded(child: _itemDropdown(entry)),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: _items.length > 1 ? SdColors.danger : SdColors.faint),
                onPressed: _items.length > 1 ? () => _removeItem(index) : null,
                tooltip: 'حذف',
              ),
            ],
          ),
          if (entry.inventoryItemId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _availableLabel(available),
            ),
          const SizedBox(height: 4),
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
      child: Column(
        children: [
          _totalRow('المجموع', _subtotal),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 100, child: Text('الخصم', style: SdText.body)),
              SizedBox(
                width: 150,
                child: TextFormField(
                  controller: _discountController,
                  style: SdText.label,
                  decoration: _dec(null, dense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 100, child: Text('الضريبة', style: SdText.body)),
              SizedBox(
                width: 150,
                child: TextFormField(
                  controller: _taxController,
                  style: SdText.label,
                  decoration: _dec(null, dense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: SdColors.divider),
          _totalRow('الصافي', _net, bold: true),
        ],
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false}) {
    return Row(
      children: [
        SizedBox(
            width: 100,
            child: Text(label, style: bold ? SdText.titleSm : SdText.body)),
        Text(fmtN(value),
            style: bold
                ? SdText.titleSm.copyWith(color: SdColors.primary)
                : SdText.label),
      ],
    );
  }
}
