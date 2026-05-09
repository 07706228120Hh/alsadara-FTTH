import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';

class ReturnFormPage extends StatefulWidget {
  final String companyId;
  final String returnType; // 'SalesReturn' or 'PurchaseReturn'
  final String? invoiceId;

  const ReturnFormPage({
    super.key,
    required this.companyId,
    required this.returnType,
    this.invoiceId,
  });

  @override
  State<ReturnFormPage> createState() => _ReturnFormPageState();
}

class _ReturnFormPageState extends State<ReturnFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  bool _loadingItems = false;

  List<Map<String, dynamic>> _invoices = [];
  String? _selectedInvoiceId;
  List<Map<String, dynamic>> _invoiceItems = [];
  List<TextEditingController> _qtyControllers = [];

  String _refundMethod = 'Cash'; // Cash, Credit, None
  String? _selectedCashBoxId;
  List<Map<String, dynamic>> _cashBoxes = [];
  final _reasonController = TextEditingController();

  static const _refundMethods = {
    'Cash': 'نقد',
    'Credit': 'خصم من الرصيد',
    'None': 'بدون',
  };

  @override
  void initState() {
    super.initState();
    _selectedInvoiceId = widget.invoiceId;
    _loadDropdowns();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    try {
      final invoiceType =
          widget.returnType == 'SalesReturn' ? 'Sales' : 'Purchase';
      final results = await Future.wait([
        _api.getInvoices(
          companyId: widget.companyId,
          type: invoiceType,
          status: 'Confirmed',
        ),
        _api.getWarehouses(companyId: widget.companyId),
      ]);

      final invList = (results[0]['data'] as List<dynamic>?) ?? [];
      final whList = (results[1]['data'] as List<dynamic>?) ?? [];

      if (mounted) {
        setState(() {
          _invoices = invList.cast<Map<String, dynamic>>();
          _cashBoxes = whList.cast<Map<String, dynamic>>();
          _loading = false;
        });

        // If invoiceId was pre-set, load its items
        if (_selectedInvoiceId != null) {
          _loadInvoiceItems(_selectedInvoiceId!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnackBar('فشل تحميل البيانات: $e', isError: true);
      }
    }
  }

  Future<void> _loadInvoiceItems(String invoiceId) async {
    setState(() => _loadingItems = true);
    try {
      final res = await _api.getInvoice(invoiceId);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final items = (data['Items'] ?? data['items'] ?? []) as List<dynamic>;

      // Dispose old controllers
      for (final c in _qtyControllers) {
        c.dispose();
      }

      if (mounted) {
        setState(() {
          _invoiceItems = items.cast<Map<String, dynamic>>();
          _qtyControllers = List.generate(
            _invoiceItems.length,
            (_) => TextEditingController(text: '0'),
          );
          _loadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingItems = false);
        _showSnackBar('فشل تحميل بنود الفاتورة: $e', isError: true);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInvoiceId == null) {
      _showSnackBar('يرجى اختيار الفاتورة الأصلية', isError: true);
      return;
    }

    // Validate at least one item has qty > 0
    final returnItems = <Map<String, dynamic>>[];
    for (var i = 0; i < _invoiceItems.length; i++) {
      final qty = int.tryParse(_qtyControllers[i].text) ?? 0;
      if (qty > 0) {
        final item = _invoiceItems[i];
        returnItems.add({
          'inventoryItemId':
              (item['InventoryItemId'] ?? item['inventoryItemId'] ?? '').toString(),
          'itemName': (item['ItemName'] ?? item['itemName'] ?? '').toString(),
          'quantity': qty,
          'unitPrice': item['UnitPrice'] ?? item['unitPrice'] ?? 0,
        });
      }
    }

    if (returnItems.isEmpty) {
      _showSnackBar('يرجى إدخال كمية مرتجعة لبند واحد على الأقل',
          isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'returnType': widget.returnType == 'SalesReturn' ? 0 : 1,
        'invoiceId': _selectedInvoiceId,
        'items': returnItems,
        'reason': _reasonController.text,
        'refundMethod': _refundMethod,
        'cashBoxId':
            _refundMethod == 'Cash' ? _selectedCashBoxId : null,
        'companyId': widget.companyId,
      };

      final createRes = await _api.createReturn(data: data);
      final returnId =
          (createRes['data']?['Id'] ?? createRes['data']?['id'] ?? createRes['id'] ?? '')
              .toString();

      // Auto-confirm
      if (returnId.isNotEmpty) {
        await _api.confirmReturn(returnId);
      }

      if (mounted) {
        _showSnackBar('تم إنشاء المرتجع وتأكيده بنجاح');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('فشل الحفظ: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.returnType == 'SalesReturn'
        ? 'مرتجع مبيعات'
        : 'مرتجع مشتريات';

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
              fontWeight: FontWeight.w700),
          elevation: 0,
          title: Text(title),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step 1: Select invoice
            const Text('1. اختر الفاتورة الأصلية',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedInvoiceId,
              decoration: const InputDecoration(
                labelText: 'الفاتورة',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: _invoices.map((e) {
                final id = (e['Id'] ?? e['id'] ?? '').toString();
                final num =
                    (e['InvoiceNumber'] ?? e['invoiceNumber'] ?? '-')
                        .toString();
                final name =
                    (e['EntityName'] ?? e['entityName'] ?? '').toString();
                return DropdownMenuItem(
                    value: id, child: Text('$num - $name'));
              }).toList(),
              onChanged: widget.invoiceId != null
                  ? null
                  : (v) {
                      setState(() => _selectedInvoiceId = v);
                      if (v != null) _loadInvoiceItems(v);
                    },
              validator: (v) =>
                  v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 24),

            // Step 2: Items with return quantities
            if (_loadingItems)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (_invoiceItems.isNotEmpty) ...[
              const Text('2. حدد كميات الإرجاع',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  border: TableBorder.all(color: Colors.black54),
                  defaultColumnWidth: const IntrinsicColumnWidth(),
                  defaultVerticalAlignment:
                      TableCellVerticalAlignment.middle,
                  children: [
                    TableRow(
                      decoration:
                          BoxDecoration(color: Colors.grey.shade200),
                      children: const [
                        _Cell('المادة', isHeader: true),
                        _Cell('الكمية الأصلية', isHeader: true),
                        _Cell('كمية الإرجاع', isHeader: true),
                      ],
                    ),
                    ..._invoiceItems.asMap().entries.map((entry) {
                      final i = entry.key;
                      final m = entry.value;
                      final originalQty =
                          (m['Quantity'] ?? m['quantity'] ?? 0);
                      return TableRow(
                        decoration: BoxDecoration(
                          color: i.isEven
                              ? Colors.white
                              : Colors.grey.shade50,
                        ),
                        children: [
                          _Cell((m['ItemName'] ?? m['itemName'] ?? '-')
                              .toString()),
                          _Cell(fmtN(originalQty)),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: SizedBox(
                              width: 80,
                              child: TextFormField(
                                controller: _qtyControllers[i],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 6),
                                  isDense: true,
                                ),
                                validator: (v) {
                                  final qty = int.tryParse(v ?? '') ?? 0;
                                  final max = (originalQty is int)
                                      ? originalQty
                                      : (int.tryParse('$originalQty') ?? 0);
                                  if (qty < 0) return 'غير صالح';
                                  if (qty > max) return 'أكبر من المتاح';
                                  return null;
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Reason
              TextFormField(
                controller: _reasonController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'سبب الإرجاع',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Refund method
              DropdownButtonFormField<String>(
                value: _refundMethod,
                decoration: const InputDecoration(
                  labelText: 'طريقة الاسترداد',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: _refundMethods.entries
                    .map((e) => DropdownMenuItem(
                        value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _refundMethod = v ?? 'Cash'),
              ),
              const SizedBox(height: 16),

              // Cash box (if refund is cash)
              if (_refundMethod == 'Cash')
                DropdownButtonFormField<String>(
                  value: _selectedCashBoxId,
                  decoration: const InputDecoration(
                    labelText: 'الصندوق',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: _cashBoxes.map((e) {
                    final id = (e['Id'] ?? e['id'] ?? '').toString();
                    final name =
                        (e['Name'] ?? e['name'] ?? '-').toString();
                    return DropdownMenuItem(
                        value: id, child: Text(name));
                  }).toList(),
                  onChanged: (v) =>
                      setState(() => _selectedCashBoxId = v),
                  validator: (v) =>
                      _refundMethod == 'Cash' && (v == null || v.isEmpty)
                          ? 'مطلوب'
                          : null,
                ),
              if (_refundMethod == 'Cash') const SizedBox(height: 16),

              // Save button
              SizedBox(
                height: 48,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('إنشاء وتأكيد المرتجع',
                          style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool isHeader;
  const _Cell(this.text, {this.isHeader = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: isHeader ? 13 : 12,
        ),
      ),
    );
  }
}
