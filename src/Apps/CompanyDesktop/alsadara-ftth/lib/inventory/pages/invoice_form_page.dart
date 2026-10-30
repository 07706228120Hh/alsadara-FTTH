import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
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

  // ── بطاقة تفاصيل المادة المحددة (جانبية) ──
  Map<String, dynamic>? _detailData; // تفاصيل آخر مادة مختارة
  String? _detailItemId;
  bool _detailLoading = false;

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
            backgroundColor: SdColors.danger,
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

  // ── حساب الطرف (عميل للبيع / مورّد للشراء) قبل وبعد الفاتورة ──
  Map<String, dynamic>? get _selectedParty {
    final id = _isSales ? _selectedCustomerId : _selectedSupplierId;
    if (id == null) return null;
    final list = _isSales ? _customers : _suppliers;
    final m = list.where((e) => '${e['Id'] ?? e['id']}' == id);
    return m.isEmpty ? null : m.first;
  }

  double get _partyBalance =>
      (_dv(_selectedParty, 'Balance') as num?)?.toDouble() ?? 0;

  // المدفوع الآن حسب نوع الدفع: نقد=كامل، آجل=صفر، جزئي=المُدخَل.
  double get _paidNow {
    switch (_paymentType) {
      case 0:
        return _netTotal;
      case 1:
        return 0;
      default:
        return parseN(_paidAmountController.text);
    }
  }

  // الرصيد بعد الفاتورة = السابق + المتبقّي غير المدفوع من هذه الفاتورة.
  double get _balanceAfter => _partyBalance + (_netTotal - _paidNow);

  // ═══════════════════════════════════════════
  //  أنماط الإدخال الموحّدة
  // ═══════════════════════════════════════════

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
                    activeColor: SdColors.primary,
                    title: Text(itemName,
                        style: TextStyle(
                            fontFamily: SdText.family,
                            fontSize: 13,
                            color:
                                alreadyAdded ? SdColors.faint : SdColors.ink)),
                    subtitle: alreadyAdded
                        ? const Text('مضاف مسبقاً',
                            style: TextStyle(
                                fontFamily: SdText.family, fontSize: 11, color: SdColors.faint))
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
                style: FilledButton.styleFrom(backgroundColor: SdColors.primary, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)),
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
                          // تعبئة السعر (بيع = حسب شريحة العميل، شراء = الكلفة)
                          if (_isSales) {
                            entry.priceController.text = _tierSalePrice(item);
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
          backgroundColor: SdColors.warning,
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
            backgroundColor: SdColors.success,
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
            backgroundColor: SdColors.danger,
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
    return SdPage(
      scrollable: false,
      maxWidth: double.infinity, // عرض كامل الشاشة (كصفحات المحاسبة/FTTH)
      appBar: SdAppBar(title: _isSales ? 'فاتورة بيع جديدة' : 'فاتورة شراء جديدة'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildHeaderSection(),
                  const SizedBox(height: SdSpace.lg),
                  _buildItemsWithDetails(),
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

  // ═══════════════════════════════════════════
  //  القسم 1: بيانات الرأس
  // ═══════════════════════════════════════════

  Widget _buildHeaderSection() {
    return InvCard(
      title: 'بيانات الفاتورة',
      icon: Icons.description_rounded,
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
                decoration: _dec('العميل *'),
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
                onChanged: (v) => setState(() {
                  _selectedCustomerId = v;
                  _applyTierToAllRows(); // أعِد تعبئة الأسعار حسب شريحة العميل
                }),
              ),
            )
          else
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                value: _selectedSupplierId,
                decoration: _dec('المورد *'),
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
              decoration: _dec('المستودع *'),
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
              decoration: _dec('نوع الدفع *'),
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
                decoration: _dec('الصندوق'),
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
                  decoration: _dec('تاريخ الاستحقاق',
                      suffixIcon: const Icon(Icons.calendar_today, size: 18, color: SdColors.faint)),
                  child: Text(
                    _dueDate != null
                        ? '${_dueDate!.year}/${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.day.toString().padLeft(2, '0')}'
                        : 'اختر تاريخ',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        color: _dueDate != null ? SdColors.ink : SdColors.faint),
                  ),
                ),
              ),
            ),

          if (_paymentType == 2) // جزئي → المبلغ المدفوع
            SizedBox(
              width: 200,
              child: TextFormField(
                controller: _paidAmountController,
                decoration: _dec('المبلغ المدفوع'),
                keyboardType: TextInputType.number,
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  القسم 2: المواد
  // ═══════════════════════════════════════════

  // قسم المواد + البطاقة الجانبية: جنباً إلى جنب على سطح المكتب، متراصّان على الهاتف.
  Widget _buildItemsWithDetails() {
    final phone = context.sd.isPhone;
    if (phone) {
      return Column(
        children: [
          _buildItemsSection(),
          const SizedBox(height: SdSpace.lg),
          _buildItemDetailCard(),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildItemsSection()),
        const SizedBox(width: SdSpace.lg),
        SizedBox(width: 320, child: _buildItemDetailCard()),
      ],
    );
  }

  // بطاقة تفاصيل المادة المحددة: آخر سعر شراء + المتوفر في المخزن + تكلفة/بيع…
  Widget _buildItemDetailCard() {
    Widget shell(Widget child) => InvCard(child: child);

    if (_detailLoading && _detailData == null) {
      return shell(const SizedBox(
          height: 120,
          child: Center(
              child: CircularProgressIndicator(color: SdColors.primary))));
    }
    if (_detailData == null) {
      return shell(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SdSectionHeader(title: 'تفاصيل المادة'),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.inventory_2_outlined, size: 18, color: SdColors.faint),
            const SizedBox(width: 8),
            Expanded(
                child: Text('اختر مادة لعرض تفاصيلها (آخر شراء، المتوفر…)',
                    style: SdText.bodySm.copyWith(color: SdColors.faint))),
          ]),
        ],
      ));
    }

    final d = _detailData!;
    final name = (_dv(d, 'Name') ?? '').toString();
    final sku = (_dv(d, 'SKU', 'sku') ?? '').toString();
    final num total = (_dv(d, 'TotalStock') as num?) ?? 0;
    final num minLvl = (_dv(d, 'MinStockLevel') as num?) ?? 0;
    final num? lastBuy = _dv(d, 'LastPurchasePrice') as num?;
    final lastBuyDate = (_dv(d, 'LastPurchaseDate'))?.toString();
    final num sell = (_dv(d, 'SellingPrice') as num?) ?? 0;
    final num cost = (_dv(d, 'CostPrice') as num?) ?? 0;

    // مخزون المستودع المحدّد في الفاتورة
    final stocks = (_dv(d, 'Stocks') as List?) ?? const [];
    Map? whStock;
    if (_selectedWarehouseId != null) {
      final match = stocks.where((s) =>
          (_dv(s as Map, 'WarehouseId'))?.toString() == _selectedWarehouseId);
      if (match.isNotEmpty) whStock = match.first as Map;
    }
    final num whQty = (whStock != null
            ? _dv(whStock, 'CurrentQuantity') as num?
            : null) ??
        0;
    final num whReserved =
        (whStock != null ? _dv(whStock, 'ReservedQuantity') as num? : null) ?? 0;
    final num avgCost =
        (whStock != null ? _dv(whStock, 'AverageCost') as num? : null) ?? cost;

    final bool lowStock = minLvl > 0 && total < minLvl;

    return shell(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SdSectionHeader(title: 'تفاصيل المادة'),
        const SizedBox(height: 4),
        Text(name,
            style: SdText.titleSm, maxLines: 2, overflow: TextOverflow.ellipsis),
        if (sku.isNotEmpty)
          Text('SKU: $sku',
              style: SdText.caption.copyWith(color: SdColors.faint)),
        const SizedBox(height: 10),
        // شارة المتوفر في المستودع المحدّد (الأبرز)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: (lowStock ? SdColors.danger : SdColors.success)
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(SdRadius.sm),
            border: Border.all(
                color: (lowStock ? SdColors.danger : SdColors.success)
                    .withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(lowStock ? Icons.warning_amber_rounded : Icons.inventory_2,
                size: 18,
                color: lowStock ? SdColors.danger : SdColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المتوفر في المستودع المحدّد',
                      style: SdText.caption.copyWith(color: SdColors.faint)),
                  Text(
                      _selectedWarehouseId == null
                          ? 'اختر المستودع أولاً'
                          : '${fmtN(whQty)}${whReserved > 0 ? '  (محجوز: ${fmtN(whReserved)})' : ''}',
                      style: SdText.label.copyWith(
                          fontWeight: FontWeight.w800,
                          color: lowStock
                              ? SdColors.danger
                              : SdColors.success)),
                ],
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        _detailRow('إجمالي المتوفر (كل المخازن)', fmtN(total)),
        _detailRow('آخر سعر شراء',
            lastBuy != null ? fmtN(lastBuy) : '—',
            hint: lastBuyDate != null && lastBuy != null
                ? _shortDate(lastBuyDate)
                : null),
        _detailRow('متوسط التكلفة', fmtN(avgCost)),
        _detailRow('سعر الشراء (افتراضي)', fmtN(cost)),
        _detailRow('سعر البيع', fmtN(sell), strong: true),
        _detailRow('الحد الأدنى للمخزون', fmtN(minLvl)),
        if (lowStock) ...[
          const SizedBox(height: 6),
          Text('⚠️ المخزون دون الحد الأدنى',
              style: SdText.caption.copyWith(
                  color: SdColors.danger, fontWeight: FontWeight.w700)),
        ],
      ],
    ));
  }

  Widget _detailRow(String label, String value,
      {String? hint, bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: SdText.bodySm),
                if (hint != null)
                  Text(hint,
                      style: SdText.caption.copyWith(color: SdColors.faint)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value,
              style: (strong ? SdText.label : SdText.body).copyWith(
                  fontWeight: FontWeight.w800,
                  color: strong ? SdColors.primary : null)),
        ],
      ),
    );
  }

  String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final l = dt.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')}';
  }

  Widget _buildItemsSection() {
    final phone = context.sd.isPhone;
    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Expanded: SdSectionHeader يحوي Spacer داخلياً فيلزمه عرض محدود (تفادي انهيار التخطيط).
              const Expanded(child: SdSectionHeader(title: 'المواد')),
              _toolbarBtn(Icons.checklist_rounded, 'تحديد متعدد', _showMultiSelectDialog),
              const SizedBox(width: 8),
              _toolbarBtn(Icons.add, 'إضافة مادة', _addLineItem),
            ],
          ),
          const SizedBox(height: 12),
          if (phone)
            for (int i = 0; i < _lineItems.length; i++) _buildItemCardPhone(i)
          else
            // جدول فاتورة احترافي: إطار موحّد + ترويسة ملوّنة + صفوف مخطّطة بخطوط فاصلة
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: SdColors.cardEdge),
                borderRadius: BorderRadius.circular(SdRadius.sm),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _tableHeader(),
                  for (int i = 0; i < _lineItems.length; i++) _buildItemRow(i),
                ],
              ),
            ),
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
                  fontFamily: SdText.family, fontSize: 12.5, fontWeight: FontWeight.w800, color: SdColors.primary)),
        ],
      ),
    );
  }

  // مُزخرِف خلية جدول: بلا عنوان عائم (الترويسة تكفي) — تلميح رمادي فقط، مُدمج.
  InputDecoration _cellDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: SdText.caption,
        filled: true,
        fillColor: SdColors.surface,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
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

  Widget _itemDropdown(_InvoiceItemEntry entry, int index,
      {InputDecoration? decoration}) {
    return DropdownButtonFormField<String>(
      value: entry.inventoryItemId,
      isExpanded: true,
      decoration: decoration ?? _dec('المادة', dense: true),
      items: _items
          .map((item) => DropdownMenuItem(
                value: '${item['Id'] ?? item['id'] ?? ''}',
                child: Text('${item['Name'] ?? item['name'] ?? ''}', overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (v) {
        setState(() {
          entry.inventoryItemId = v;
          final found = _items.where((i) => '${i['Id'] ?? i['id']}' == v);
          if (found.isNotEmpty) {
            final item = found.first;
            entry.itemName = '${item['Name'] ?? item['name'] ?? ''}';
            // تعبئة السعر تلقائياً (بيع = حسب شريحة العميل، شراء = الكلفة)
            if (_isSales) {
              entry.priceController.text = _tierSalePrice(item);
            } else {
              entry.priceController.text = '${item['CostPrice'] ?? item['costPrice'] ?? 0}';
            }
            // إذا آخر سطر → أضف سطر جديد تلقائياً
            if (index == _lineItems.length - 1) {
              _addLineItem();
            }
          }
        });
        // تحميل تفاصيل المادة للبطاقة الجانبية (آخر سعر شراء/المتوفر…)
        _loadItemDetail(v);
      },
    );
  }

  /// جلب تفاصيل المادة المحددة لعرضها في البطاقة الجانبية (مخزون/تكلفة/آخر شراء).
  Future<void> _loadItemDetail(String? itemId) async {
    if (itemId == null || itemId.isEmpty) return;
    setState(() {
      _detailItemId = itemId;
      _detailLoading = true;
    });
    try {
      final res = await _api.getItem(itemId);
      if (!mounted || _detailItemId != itemId) return; // تجاهل نتيجة قديمة
      setState(() {
        _detailData = (res['data'] as Map?)?.cast<String, dynamic>();
        _detailLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  /// قراءة مفتاح بصيغتي PascalCase/camelCase (الباكند يُرجع PascalCase).
  dynamic _dv(Map? m, String pascal, [String? camel]) =>
      m == null ? null : (m[pascal] ?? m[camel ?? _lower(pascal)]);
  String _lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  /// شريحة تسعير العميل المختار (0=مفرد، 1=جملة، 2=جملة الجملة).
  int get _customerTier {
    if (_selectedCustomerId == null) return 0;
    final c = _customers
        .where((e) => '${e['Id'] ?? e['id']}' == _selectedCustomerId);
    if (c.isEmpty) return 0;
    return (_dv(c.first, 'PriceTier') as num?)?.toInt() ?? 0;
  }

  /// سعر بيع المادة حسب شريحة العميل، مع تدرّج احتياطي (الشريحة ⇐ مفرد ⇐ الكلفة).
  String _tierSalePrice(Map item) {
    num? pick;
    switch (_customerTier) {
      case 2:
        pick = _dv(item, 'BulkWholesalePrice') as num?;
        break;
      case 1:
        pick = _dv(item, 'WholesalePrice') as num?;
        break;
    }
    pick ??= _dv(item, 'SellingPrice') as num?;
    pick ??= _dv(item, 'CostPrice') as num?;
    return '${pick ?? 0}';
  }

  /// يُعيد تعبئة أسعار كل الأسطر حسب شريحة العميل الحالي (عند تغيير العميل).
  void _applyTierToAllRows() {
    if (!_isSales) return;
    for (final e in _lineItems) {
      if (e.inventoryItemId == null) continue;
      final found =
          _items.where((i) => '${i['Id'] ?? i['id']}' == e.inventoryItemId);
      if (found.isNotEmpty) e.priceController.text = _tierSalePrice(found.first);
    }
  }

  Widget _qtyField(_InvoiceItemEntry entry,
          {InputDecoration? decoration, TextAlign textAlign = TextAlign.start}) =>
      TextFormField(
        controller: entry.qtyController,
        decoration: decoration ?? _dec('الكمية', dense: true),
        textAlign: textAlign,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
      );

  Widget _priceField(_InvoiceItemEntry entry,
          {InputDecoration? decoration, TextAlign textAlign = TextAlign.start}) =>
      TextFormField(
        controller: entry.priceController,
        decoration: decoration ?? _dec('السعر', dense: true),
        textAlign: textAlign,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
      );

  Widget _discField(_InvoiceItemEntry entry,
          {InputDecoration? decoration, TextAlign textAlign = TextAlign.start}) =>
      TextFormField(
        controller: entry.discountController,
        decoration: decoration ?? _dec('خصم%', dense: true),
        textAlign: textAlign,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
      );

  // ترويسة الجدول — أعمدة بعناوين واضحة بعرض مطابق لصفوف البيانات تماماً.
  Widget _tableHeader() {
    Widget cap(String t, {TextAlign align = TextAlign.center}) => Text(
          t,
          style: SdText.caption.copyWith(
              fontWeight: FontWeight.w800, color: SdColors.faint),
          textAlign: align,
        );
    return Container(
      color: SdColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(
        children: [
          SizedBox(width: 34, child: cap('#')),
          const SizedBox(width: 8),
          Expanded(flex: 5, child: cap('المادة', align: TextAlign.start)),
          const SizedBox(width: 8),
          SizedBox(width: 95, child: cap('الكمية')),
          const SizedBox(width: 8),
          SizedBox(width: 130, child: cap('السعر')),
          const SizedBox(width: 8),
          SizedBox(width: 90, child: cap('خصم%')),
          const SizedBox(width: 8),
          SizedBox(width: 140, child: cap('المجموع')),
          const SizedBox(width: 8),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final entry = _lineItems[index];
    final isLast = index == _lineItems.length - 1;
    return Container(
      decoration: BoxDecoration(
        // تخطيط صفوف متناوب خفيف + خط فاصل سفلي (إلا الأخير)
        color: index.isOdd
            ? SdColors.surfaceAlt.withValues(alpha: 0.35)
            : SdColors.surface,
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: SdColors.cardEdge)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
              width: 34,
              child: Text('${index + 1}',
                  style: SdText.label, textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          Expanded(
              flex: 5,
              child: _itemDropdown(entry, index,
                  decoration: _cellDec('اختر المادة'))),
          const SizedBox(width: 8),
          SizedBox(
              width: 95,
              child: _qtyField(entry,
                  decoration: _cellDec('0'), textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          SizedBox(
              width: 130,
              child: _priceField(entry,
                  decoration: _cellDec('0'), textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          SizedBox(
              width: 90,
              child: _discField(entry,
                  decoration: _cellDec('0'), textAlign: TextAlign.center)),
          const SizedBox(width: 8),
          // المجموع (محسوب) — نص بارز بدل حقل
          SizedBox(
            width: 140,
            child: Text(fmtN(entry.lineTotal),
                style: SdText.label.copyWith(
                    fontWeight: FontWeight.w800, color: SdColors.primary),
                textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          // حذف
          SizedBox(
            width: 48,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.delete_outline,
                  size: 20,
                  color: _lineItems.length > 1
                      ? SdColors.danger
                      : SdColors.faint),
              onPressed:
                  _lineItems.length > 1 ? () => _removeLineItem(index) : null,
              tooltip: 'حذف',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCardPhone(int index) {
    final entry = _lineItems[index];
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
                icon: Icon(Icons.delete_outline,
                    color: _lineItems.length > 1 ? SdColors.danger : SdColors.faint),
                onPressed: _lineItems.length > 1 ? () => _removeLineItem(index) : null,
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
              const SizedBox(width: 8),
              Expanded(child: _discField(entry)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('المجموع', style: SdText.bodySm),
              const Spacer(),
              Text(fmtN(entry.lineTotal), style: SdText.label),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  القسم 3: المجاميع
  // ═══════════════════════════════════════════

  Widget _buildTotalsSection() {
    final party = _selectedParty;
    final partyLabel = _isSales ? 'العميل' : 'المورّد';
    final bool afterUp = _balanceAfter > _partyBalance;
    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // صف إجماليات مدمج واحد (يلتفّ على الشاشات الضيقة)
          Wrap(
            spacing: 18,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _miniStat('المجموع الفرعي', fmtN(_subtotal)),
              _discountInline(),
              _taxInline(),
              if (party != null)
                _miniStat('حساب $partyLabel السابق', fmtN(_partyBalance),
                    color: SdColors.faint),
              _netStat(),
              if (party != null)
                _miniStat('حساب $partyLabel بعد الفاتورة', fmtN(_balanceAfter),
                    color: afterUp ? SdColors.danger : SdColors.success),
            ],
          ),
          const SizedBox(height: 12),
          // ملاحظات
          SizedBox(
            width: double.infinity,
            child: TextFormField(
              controller: _notesController,
              decoration: _dec('ملاحظات'),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  // كتلة إحصائية مصغّرة: عنوان صغير + قيمة بارزة.
  Widget _miniStat(String label, String value, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SdText.caption.copyWith(color: SdColors.faint)),
        const SizedBox(height: 2),
        Text(value,
            style: SdText.label
                .copyWith(fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  // الصافي النهائي — كتلة مميّزة.
  Widget _netStat() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: SdColors.primaryTint,
        borderRadius: BorderRadius.circular(SdRadius.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الصافي النهائي',
              style: SdText.caption.copyWith(
                  color: SdColors.primary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(fmtN(_netTotal),
              style: const TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: SdColors.primary)),
        ],
      ),
    );
  }

  // ارتفاع موحّد لكل حقول صف المجاميع.
  static const double _totFieldH = 44;

  // غلاف حقل موحّد: عنوان صغير أعلاه + صندوق بارتفاع ثابت.
  Widget _totField(String label, Color labelColor, double width, Widget field) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: SdText.caption.copyWith(color: labelColor)),
        const SizedBox(height: 4),
        SizedBox(width: width, height: _totFieldH, child: field),
      ],
    );
  }

  // الخصم — نوع + قيمة، بنمط موحّد.
  Widget _discountInline() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _totField(
          'نوع الخصم',
          SdColors.danger,
          104,
          DropdownButtonFormField<int>(
            value: _discountType,
            isExpanded: true,
            decoration: _cellDec(''),
            style: SdText.body.copyWith(color: SdColors.ink),
            items: _discountTypes.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _discountType = v);
            },
          ),
        ),
        const SizedBox(width: 8),
        _totField(
          'الخصم (−${fmtN(_discountAmount)})',
          SdColors.danger,
          88,
          TextFormField(
            controller: _discountValueController,
            decoration: _cellDec('0'),
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  // الضريبة % — نسبة، بنمط موحّد.
  Widget _taxInline() {
    return _totField(
      'ضريبة % (+${fmtN(_taxAmount)})',
      SdColors.info,
      88,
      TextFormField(
        controller: _taxRateController,
        decoration: _cellDec('0'),
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _buildTotalLine(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(label, style: SdText.body),
        const SizedBox(width: 16),
        SizedBox(
          width: 100,
          child: Text(value,
              textAlign: TextAlign.left,
              style: const TextStyle(
                  fontFamily: SdText.family, fontSize: 14, fontWeight: FontWeight.w700, color: SdColors.ink)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  زر الحفظ
  // ═══════════════════════════════════════════

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
      label: _isSales ? 'حفظ فاتورة البيع' : 'حفظ فاتورة الشراء',
      icon: Icons.save_rounded,
      expand: true,
      onPressed: _save,
    );
  }
}
