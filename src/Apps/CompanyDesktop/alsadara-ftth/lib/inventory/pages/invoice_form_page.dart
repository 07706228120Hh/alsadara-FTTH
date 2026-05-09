import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';

// ─────────────────────────────────────────────
//  نموذج سطر مادة واحدة
// ─────────────────────────────────────────────

class _InvoiceItemEntry {
  String? inventoryItemId;
  String? itemName;
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController discountController =
      TextEditingController(text: '0');

  double get _qty =>
      double.tryParse(qtyController.text.replaceAll(',', '')) ?? 0;
  double get _price => parseN(priceController.text);
  double get _discPct =>
      double.tryParse(discountController.text.replaceAll(',', '')) ?? 0;

  double get lineTotal {
    final gross = _qty * _price;
    return gross - (gross * _discPct / 100);
  }

  void dispose() {
    qtyController.dispose();
    priceController.dispose();
    discountController.dispose();
  }
}

// ─────────────────────────────────────────────
//  صفحة إنشاء فاتورة بيع / شراء
// ─────────────────────────────────────────────

class InvoiceFormPage extends StatefulWidget {
  final String companyId;

  /// 'Sales' أو 'Purchase'
  final String invoiceType;

  const InvoiceFormPage({
    super.key,
    required this.companyId,
    required this.invoiceType,
  });

  @override
  State<InvoiceFormPage> createState() => _InvoiceFormPageState();
}

class _InvoiceFormPageState extends State<InvoiceFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool get _isSales => widget.invoiceType == 'Sales';

  // ── حالة التحميل ──
  bool _loading = true;
  bool _saving = false;

  // ── بيانات Dropdown ──
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _cashBoxes = []; // سيُحمّل مستقبلاً

  // ── القيم المُختارة ──
  String? _selectedCustomerId;
  String? _selectedSupplierId;
  String? _selectedWarehouseId;
  int _paymentType = 0; // 0=نقد, 1=آجل, 2=جزئي
  String? _selectedCashBoxId;
  DateTime? _dueDate;

  // ── خصم عام + ضريبة ──
  int _discountType = 0; // 0=نسبة, 1=مبلغ
  final _discountValueController = TextEditingController(text: '0');
  final _taxRateController = TextEditingController(text: '0');
  final _paidAmountController = TextEditingController(text: '0');
  final _notesController = TextEditingController();

  // ── سطور المواد ──
  final List<_InvoiceItemEntry> _lineItems = [];

  // ═══════════════════════════════════════════
  //  ثوابت نوع الدفع
  // ═══════════════════════════════════════════

  static const _paymentTypes = <int, String>{
    0: 'نقد',
    1: 'آجل',
    2: 'جزئي',
  };

  static const _discountTypes = <int, String>{
    0: 'نسبة',
    1: 'مبلغ',
  };

  // ═══════════════════════════════════════════
  //  دورة الحياة
  // ═══════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
  }

  @override
  void dispose() {
    _discountValueController.dispose();
    _taxRateController.dispose();
    _paidAmountController.dispose();
    _notesController.dispose();
    for (final e in _lineItems) {
      e.dispose();
    }
    super.dispose();
  }

  // ═══════════════════════════════════════════
  //  تحميل البيانات
  // ═══════════════════════════════════════════

  Future<void> _loadDropdowns() async {
    try {
      final futures = <Future<Map<String, dynamic>>>[
        _api.getWarehouses(companyId: widget.companyId),
        _api.getItems(companyId: widget.companyId, pageSize: 500),
      ];
      if (_isSales) {
        futures.add(_api.getCustomers(companyId: widget.companyId));
      } else {
        futures.add(_api.getSuppliers(companyId: widget.companyId));
      }

      final results = await Future.wait(futures);
      if (!mounted) return;

      final warehouseRaw = results[0]['data'] as List<dynamic>? ?? [];
      final itemsRaw = results[1]['data'] as List<dynamic>? ?? [];
      final thirdRaw = results[2]['data'] as List<dynamic>? ?? [];

      setState(() {
        _warehouses = warehouseRaw
            .map((e) => e as Map<String, dynamic>)
            .toList();
        _items =
            itemsRaw.map((e) => e as Map<String, dynamic>).toList();

        if (_isSales) {
          _customers =
              thirdRaw.map((e) => e as Map<String, dynamic>).toList();
        } else {
          _suppliers =
              thirdRaw.map((e) => e as Map<String, dynamic>).toList();
        }

        _loading = false;
      });
      _addLineItem(); // سطر أول فارغ
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحميل البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════
  //  إدارة سطور المواد
  // ═══════════════════════════════════════════

  void _addLineItem() {
    setState(() => _lineItems.add(_InvoiceItemEntry()));
  }

  void _removeLineItem(int index) {
    if (_lineItems.length <= 1) return;
    setState(() {
      _lineItems[index].dispose();
      _lineItems.removeAt(index);
    });
  }

  // ═══════════════════════════════════════════
  //  الحسابات التلقائية
  // ═══════════════════════════════════════════

  double get _subtotal =>
      _lineItems.fold(0.0, (sum, e) => sum + e.lineTotal);

  double get _discountAmount {
    final v = parseN(_discountValueController.text);
    if (_discountType == 0) {
      // نسبة
      return _subtotal * v / 100;
    }
    return v; // مبلغ
  }

  double get _taxAmount {
    final rate = parseN(_taxRateController.text);
    return (_subtotal - _discountAmount) * rate / 100;
  }

  double get _netTotal => _subtotal - _discountAmount + _taxAmount;

  // ═══════════════════════════════════════════
  //  تحديد متعدد للمواد
  // ═══════════════════════════════════════════

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
                children: _items.map((item) {
                  final itemId =
                      '${item['Id'] ?? item['id'] ?? ''}';
                  final itemName =
                      '${item['Name'] ?? item['name'] ?? ''}';
                  final alreadyAdded = _lineItems
                      .any((e) => e.inventoryItemId == itemId);
                  return CheckboxListTile(
                    value: selected.contains(itemId) || alreadyAdded,
                    enabled: !alreadyAdded,
                    title: Text(itemName,
                        style: TextStyle(
                            fontSize: 13,
                            color:
                                alreadyAdded ? Colors.grey : null)),
                    subtitle: alreadyAdded
                        ? const Text('مضاف مسبقاً',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey))
                        : null,
                    dense: true,
                    onChanged: alreadyAdded
                        ? null
                        : (v) => setD(() {
                              if (v == true) {
                                selected.add(itemId);
                              } else {
                                selected.remove(itemId);
                              }
                            }),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        for (final id in selected) {
                          final item =
                              _items.firstWhere((i) =>
                                  '${i['Id'] ?? i['id']}' == id);
                          final entry = _InvoiceItemEntry()
                            ..inventoryItemId = id
                            ..itemName =
                                '${item['Name'] ?? item['name'] ?? ''}';
                          // تعبئة السعر حسب نوع الفاتورة
                          if (_isSales) {
                            entry.priceController.text = '${item['SellingPrice'] ?? item['sellingPrice'] ?? 0}';
                          } else {
                            entry.priceController.text = '${item['CostPrice'] ?? item['costPrice'] ?? 0}';
                          }
                          _lineItems.add(entry);
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

  // ═══════════════════════════════════════════
  //  اختيار تاريخ الاستحقاق
  // ═══════════════════════════════════════════

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  // ═══════════════════════════════════════════
  //  حفظ الفاتورة
  // ═══════════════════════════════════════════

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final validItems =
        _lineItems.where((e) => e.inventoryItemId != null).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أضف مادة واحدة على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final data = <String, dynamic>{
      'invoiceType': _isSales ? 0 : 1,
      'paymentType': _paymentType,
      'customerId': _isSales ? _selectedCustomerId : null,
      'supplierId': !_isSales ? _selectedSupplierId : null,
      'warehouseId': _selectedWarehouseId,
      'dueDate': _paymentType == 1 ? _dueDate?.toIso8601String() : null,
      'discountType': _discountType,
      'discountValue': parseN(_discountValueController.text),
      'taxRate': parseN(_taxRateController.text),
      'paidAmount': _paymentType == 2
          ? parseN(_paidAmountController.text)
          : 0,
      'cashBoxId': _paymentType == 0 ? _selectedCashBoxId : null,
      'notes': _notesController.text.isEmpty
          ? null
          : _notesController.text,
      'companyId': widget.companyId,
      'items': validItems.map((e) {
        return {
          'inventoryItemId': e.inventoryItemId,
          'quantity':
              int.tryParse(e.qtyController.text.replaceAll(',', '')) ??
                  1,
          'unitPrice': parseN(e.priceController.text),
          'discountPercent': double.tryParse(
                  e.discountController.text.replaceAll(',', '')) ??
              0,
        };
      }).toList(),
    };

    try {
      final res = await _api.createInvoice(data: data);
      // استخراج ID الفاتورة وتأكيدها فوراً
      final invoiceId = '${res['id'] ?? res['Id'] ?? res['data']?['id'] ?? res['data']?['Id'] ?? ''}';
      if (invoiceId.isNotEmpty) {
        await _api.confirmInvoice(invoiceId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isSales
                ? 'تم إنشاء فاتورة البيع وتأكيدها'
                : 'تم إنشاء فاتورة الشراء وتأكيدها'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الحفظ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ═══════════════════════════════════════════
  //  البناء الرئيسي
  // ═══════════════════════════════════════════

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
            fontWeight: FontWeight.w700,
          ),
          elevation: 0,
          title: Text(
              _isSales ? 'فاتورة بيع جديدة' : 'فاتورة شراء جديدة'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeaderSection(),
                    const SizedBox(height: 20),
                    _buildItemsSection(),
                    const SizedBox(height: 20),
                    _buildTotalsSection(),
                    const SizedBox(height: 24),
                    _buildSaveButton(),
                  ],
                ),
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  القسم 1: بيانات الرأس
  // ═══════════════════════════════════════════

  Widget _buildHeaderSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            // ── العميل أو المورد ──
            if (_isSales)
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                  value: _selectedCustomerId,
                  decoration: const InputDecoration(
                    labelText: 'العميل *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null ? 'اختر العميل' : null,
                  isExpanded: true,
                  items: _customers
                      .map((c) => DropdownMenuItem(
                            value:
                                '${c['Id'] ?? c['id'] ?? ''}',
                            child: Text(
                                '${c['FullName'] ?? c['fullName'] ?? c['Name'] ?? c['name'] ?? ''}',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedCustomerId = v),
                ),
              )
            else
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                  value: _selectedSupplierId,
                  decoration: const InputDecoration(
                    labelText: 'المورد *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null ? 'اختر المورد' : null,
                  isExpanded: true,
                  items: _suppliers
                      .map((s) => DropdownMenuItem(
                            value:
                                '${s['Id'] ?? s['id'] ?? ''}',
                            child: Text(
                                '${s['Name'] ?? s['name'] ?? ''}',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedSupplierId = v),
                ),
              ),

            // ── المستودع ──
            SizedBox(
              width: 250,
              child: DropdownButtonFormField<String>(
                value: _selectedWarehouseId,
                decoration: const InputDecoration(
                  labelText: 'المستودع *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null ? 'اختر المستودع' : null,
                isExpanded: true,
                items: _warehouses
                    .map((w) => DropdownMenuItem(
                          value:
                              '${w['Id'] ?? w['id'] ?? ''}',
                          child: Text(
                              '${w['Name'] ?? w['name'] ?? ''}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedWarehouseId = v),
              ),
            ),

            // ── نوع الدفع ──
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                value: _paymentType,
                decoration: const InputDecoration(
                  labelText: 'نوع الدفع *',
                  border: OutlineInputBorder(),
                ),
                items: _paymentTypes.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _paymentType = v);
                },
              ),
            ),

            // ── حقول مشروطة حسب نوع الدفع ──
            if (_paymentType == 0) // نقد → صندوق
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  value: _selectedCashBoxId,
                  decoration: const InputDecoration(
                    labelText: 'الصندوق',
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: _cashBoxes
                      .map((b) => DropdownMenuItem(
                            value:
                                '${b['Id'] ?? b['id'] ?? ''}',
                            child: Text(
                                '${b['Name'] ?? b['name'] ?? ''}',
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedCashBoxId = v),
                ),
              ),

            if (_paymentType == 1) // آجل → تاريخ استحقاق
              SizedBox(
                width: 200,
                child: InkWell(
                  onTap: _pickDueDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'تاريخ الاستحقاق',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    child: Text(
                      _dueDate != null
                          ? '${_dueDate!.year}/${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.day.toString().padLeft(2, '0')}'
                          : 'اختر تاريخ',
                      style: TextStyle(
                          color:
                              _dueDate != null ? null : Colors.grey),
                    ),
                  ),
                ),
              ),

            if (_paymentType == 2) // جزئي → المبلغ المدفوع
              SizedBox(
                width: 200,
                child: TextFormField(
                  controller: _paidAmountController,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ المدفوع',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  القسم 2: المواد
  // ═══════════════════════════════════════════

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
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _showMultiSelectDialog,
                  icon:
                      const Icon(Icons.checklist_rounded, size: 18),
                  label: const Text('تحديد متعدد'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: _addLineItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة مادة'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // رؤوس الأعمدة
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: const [
                  SizedBox(width: 28), // # col
                  Expanded(flex: 4, child: Text('المادة', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey))),
                  SizedBox(width: 8),
                  SizedBox(width: 90, child: Text('الكمية', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey))),
                  SizedBox(width: 8),
                  SizedBox(width: 120, child: Text('السعر', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey))),
                  SizedBox(width: 8),
                  SizedBox(width: 80, child: Text('خصم%', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey))),
                  SizedBox(width: 8),
                  SizedBox(width: 110, child: Text('المجموع', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey))),
                  SizedBox(width: 40), // delete btn
                ],
              ),
            ),
            for (int i = 0; i < _lineItems.length; i++)
              _buildItemRow(i),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final entry = _lineItems[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رقم السطر
          SizedBox(
            width: 28,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('${index + 1}.',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
          // المادة
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
              items: _items
                  .map((item) => DropdownMenuItem(
                        value:
                            '${item['Id'] ?? item['id'] ?? ''}',
                        child: Text(
                            '${item['Name'] ?? item['name'] ?? ''}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  entry.inventoryItemId = v;
                  final found = _items.where(
                      (i) => '${i['Id'] ?? i['id']}' == v);
                  if (found.isNotEmpty) {
                    final item = found.first;
                    entry.itemName =
                        '${item['Name'] ?? item['name'] ?? ''}';
                    // تعبئة السعر تلقائياً
                    if (_isSales) {
                      entry.priceController.text =
                          '${item['SellingPrice'] ?? item['sellingPrice'] ?? 0}';
                    } else {
                      entry.priceController.text =
                          '${item['CostPrice'] ?? item['costPrice'] ?? 0}';
                    }
                    // إذا آخر سطر → أضف سطر جديد تلقائياً
                    if (index == _lineItems.length - 1) {
                      _addLineItem();
                    }
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          // الكمية
          SizedBox(
            width: 90,
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
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          // السعر
          SizedBox(
            width: 120,
            child: TextFormField(
              controller: entry.priceController,
              decoration: const InputDecoration(
                labelText: 'السعر',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          // خصم%
          SizedBox(
            width: 80,
            child: TextFormField(
              controller: entry.discountController,
              decoration: const InputDecoration(
                labelText: 'خصم%',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          // المجموع (محسوب)
          SizedBox(
            width: 110,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'المجموع',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: Text(fmtN(entry.lineTotal),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 4),
          // حذف
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: _lineItems.length > 1
                    ? Colors.red
                    : Colors.grey.shade400),
            onPressed: _lineItems.length > 1
                ? () => _removeLineItem(index)
                : null,
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  القسم 3: المجاميع
  // ═══════════════════════════════════════════

  Widget _buildTotalsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // المجموع الفرعي
            _buildTotalLine('المجموع الفرعي', fmtN(_subtotal)),
            const SizedBox(height: 10),

            // الخصم
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('الخصم',
                    style: TextStyle(fontSize: 14)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: DropdownButtonFormField<int>(
                    value: _discountType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                    ),
                    items: _discountTypes.entries
                        .map((e) => DropdownMenuItem(
                            value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _discountType = v);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _discountValueController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: Text(fmtN(_discountAmount),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // الضريبة
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('الضريبة %',
                    style: TextStyle(fontSize: 14)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _taxRateController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: Text(fmtN(_taxAmount),
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                          color: Colors.blue, fontSize: 14)),
                ),
              ],
            ),

            const Divider(height: 24),

            // الصافي النهائي
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('الصافي النهائي',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    fmtN(_netTotal),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ملاحظات
            SizedBox(
              width: double.infinity,
              child: TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalLine(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 16),
        SizedBox(
          width: 100,
          child: Text(value,
              textAlign: TextAlign.left,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  زر الحفظ
  // ═══════════════════════════════════════════

  Widget _buildSaveButton() {
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save_rounded),
        label: Text(
          _isSales ? 'حفظ فاتورة البيع' : 'حفظ فاتورة الشراء',
          style: const TextStyle(fontSize: 16),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1A1A2E),
        ),
      ),
    );
  }
}
