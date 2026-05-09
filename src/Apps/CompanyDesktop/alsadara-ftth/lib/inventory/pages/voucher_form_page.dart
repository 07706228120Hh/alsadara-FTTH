import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';

class VoucherFormPage extends StatefulWidget {
  final String companyId;
  final String? voucherType; // 'Receipt' or 'Payment'
  final String? entityId;
  final String? entityName;
  final String? invoiceId;

  const VoucherFormPage({
    super.key,
    required this.companyId,
    this.voucherType,
    this.entityId,
    this.entityName,
    this.invoiceId,
  });

  @override
  State<VoucherFormPage> createState() => _VoucherFormPageState();
}

class _VoucherFormPageState extends State<VoucherFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  String _voucherType = 'Receipt'; // 'Receipt' or 'Payment'
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _cashBoxes = [];

  String? _selectedEntityId;
  String? _selectedEntityName;
  String? _selectedInvoiceId;
  String? _selectedCashBoxId;
  int _paymentMethod = 0; // 0=Cash, 1=BankTransfer, 2=ZainCash

  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  static const _paymentMethods = {
    0: 'نقدي',
    1: 'تحويل بنكي',
    2: 'زين كاش',
  };

  @override
  void initState() {
    super.initState();
    if (widget.voucherType != null) {
      _voucherType = widget.voucherType!;
    }
    if (widget.entityId != null) {
      _selectedEntityId = widget.entityId;
      _selectedEntityName = widget.entityName;
    }
    if (widget.invoiceId != null) {
      _selectedInvoiceId = widget.invoiceId;
    }
    _loadDropdowns();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    try {
      final results = await Future.wait([
        _api.getCustomers(companyId: widget.companyId),
        _api.getSuppliers(companyId: widget.companyId),
        _api.getInvoices(companyId: widget.companyId, status: 'Confirmed'),
        _api.getWarehouses(companyId: widget.companyId),
      ]);

      final custList = (results[0]['data'] as List<dynamic>?) ?? [];
      final suppList = (results[1]['data'] as List<dynamic>?) ?? [];
      final invList = (results[2]['data'] as List<dynamic>?) ?? [];
      final whList = (results[3]['data'] as List<dynamic>?) ?? [];

      if (mounted) {
        setState(() {
          _customers = custList.cast<Map<String, dynamic>>();
          _suppliers = suppList.cast<Map<String, dynamic>>();
          _invoices = invList.cast<Map<String, dynamic>>();
          _cashBoxes = whList.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnackBar('فشل تحميل البيانات: $e', isError: true);
      }
    }
  }

  List<Map<String, dynamic>> get _entityList =>
      _voucherType == 'Receipt' ? _customers : _suppliers;

  String get _entityLabel =>
      _voucherType == 'Receipt' ? 'العميل' : 'المورد';

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final data = {
        'voucherType': _voucherType == 'Receipt' ? 0 : 1,
        'entityType': _voucherType == 'Receipt' ? 0 : 1,
        'entityId': _selectedEntityId,
        'entityName': _selectedEntityName ?? '',
        'amount': double.tryParse(_amountController.text) ?? 0,
        'paymentMethod': _paymentMethod,
        'cashBoxId': _selectedCashBoxId,
        'invoiceId': _selectedInvoiceId,
        'notes': _notesController.text,
        'companyId': widget.companyId,
      };

      await _api.createVoucher(data: data);
      if (mounted) {
        _showSnackBar('تم حفظ السند بنجاح');
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
    final title = _voucherType == 'Receipt' ? 'سند قبض' : 'سند صرف';

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
            // Voucher type selector (only if not pre-set)
            if (widget.voucherType == null) ...[
              const Text('نوع السند',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('سند قبض'),
                      value: 'Receipt',
                      groupValue: _voucherType,
                      onChanged: (v) {
                        setState(() {
                          _voucherType = v!;
                          _selectedEntityId = null;
                          _selectedEntityName = null;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('سند صرف'),
                      value: 'Payment',
                      groupValue: _voucherType,
                      onChanged: (v) {
                        setState(() {
                          _voucherType = v!;
                          _selectedEntityId = null;
                          _selectedEntityName = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Entity dropdown
            DropdownButtonFormField<String>(
              value: _selectedEntityId,
              decoration: InputDecoration(
                labelText: _entityLabel,
                border: const OutlineInputBorder(),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: _entityList.map((e) {
                final id = (e['Id'] ?? e['id'] ?? '').toString();
                final name = (e['Name'] ?? e['name'] ?? '-').toString();
                return DropdownMenuItem(value: id, child: Text(name));
              }).toList(),
              onChanged: widget.entityId != null
                  ? null
                  : (v) {
                      setState(() {
                        _selectedEntityId = v;
                        final entity = _entityList.firstWhere(
                          (e) =>
                              (e['Id'] ?? e['id']).toString() == v,
                          orElse: () => {},
                        );
                        _selectedEntityName =
                            (entity['Name'] ?? entity['name'] ?? '')
                                .toString();
                      });
                    },
              validator: (v) =>
                  v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),

            // Amount
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'المبلغ',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'مطلوب';
                if ((double.tryParse(v) ?? 0) <= 0) return 'أدخل مبلغ صحيح';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Payment method
            DropdownButtonFormField<int>(
              value: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'طريقة الدفع',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: _paymentMethods.entries
                  .map((e) =>
                      DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _paymentMethod = v ?? 0),
            ),
            const SizedBox(height: 16),

            // Cash box
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
                final name = (e['Name'] ?? e['name'] ?? '-').toString();
                return DropdownMenuItem(value: id, child: Text(name));
              }).toList(),
              onChanged: (v) => setState(() => _selectedCashBoxId = v),
              validator: (v) =>
                  v == null || v.isEmpty ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),

            // Invoice (optional)
            DropdownButtonFormField<String>(
              value: _selectedInvoiceId,
              decoration: const InputDecoration(
                labelText: 'ربط بفاتورة (اختياري)',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('بدون')),
                ..._invoices.map((e) {
                  final id = (e['Id'] ?? e['id'] ?? '').toString();
                  final num =
                      (e['InvoiceNumber'] ?? e['invoiceNumber'] ?? '-')
                          .toString();
                  final name =
                      (e['EntityName'] ?? e['entityName'] ?? '').toString();
                  return DropdownMenuItem(
                      value: id, child: Text('$num - $name'));
                }),
              ],
              onChanged: widget.invoiceId != null
                  ? null
                  : (v) => setState(() => _selectedInvoiceId = v),
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

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
                    : const Text('حفظ السند', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
