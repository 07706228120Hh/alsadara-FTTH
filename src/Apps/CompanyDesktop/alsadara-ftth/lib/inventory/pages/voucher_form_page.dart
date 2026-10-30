import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
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
        backgroundColor: isError ? SdColors.danger : SdColors.success,
      ),
    );
  }

  InputDecoration _dec(String? label) {
    return InputDecoration(
      labelText: label,
      labelStyle: SdText.bodySm,
      filled: true,
      fillColor: SdColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    final title = _voucherType == 'Receipt' ? 'سند قبض' : 'سند صرف';

    return SdPage(
      scrollable: false,
      maxWidth: SdSpace.formMax,
      appBar: SdAppBar(title: title),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          InvCard(
            title: 'بيانات السند',
            icon: Icons.receipt_long_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // نوع السند (فقط إذا لم يكن محدّداً مسبقاً)
                if (widget.voucherType == null) ...[
                  const Text('نوع السند', style: SdText.label),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('سند قبض', style: SdText.body),
                          value: 'Receipt',
                          activeColor: SdColors.primary,
                          contentPadding: EdgeInsets.zero,
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
                          title: const Text('سند صرف', style: SdText.body),
                          value: 'Payment',
                          activeColor: SdColors.primary,
                          contentPadding: EdgeInsets.zero,
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

                // الجهة
                DropdownButtonFormField<String>(
                  value: _selectedEntityId,
                  isExpanded: true,
                  style: SdText.label,
                  decoration: _dec(_entityLabel),
                  items: _entityList.map((e) {
                    final id = (e['Id'] ?? e['id'] ?? '').toString();
                    final name = (e['Name'] ?? e['name'] ?? '-').toString();
                    return DropdownMenuItem(
                        value: id, child: Text(name, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: widget.entityId != null
                      ? null
                      : (v) {
                          setState(() {
                            _selectedEntityId = v;
                            final entity = _entityList.firstWhere(
                              (e) => (e['Id'] ?? e['id']).toString() == v,
                              orElse: () => {},
                            );
                            _selectedEntityName =
                                (entity['Name'] ?? entity['name'] ?? '').toString();
                          });
                        },
                  validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 16),

                // المبلغ
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  style: SdText.label,
                  decoration: _dec('المبلغ'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'مطلوب';
                    if ((double.tryParse(v) ?? 0) <= 0) return 'أدخل مبلغ صحيح';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // طريقة الدفع
                DropdownButtonFormField<int>(
                  value: _paymentMethod,
                  style: SdText.label,
                  decoration: _dec('طريقة الدفع'),
                  items: _paymentMethods.entries
                      .map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _paymentMethod = v ?? 0),
                ),
                const SizedBox(height: 16),

                // الصندوق
                DropdownButtonFormField<String>(
                  value: _selectedCashBoxId,
                  isExpanded: true,
                  style: SdText.label,
                  decoration: _dec('الصندوق'),
                  items: _cashBoxes.map((e) {
                    final id = (e['Id'] ?? e['id'] ?? '').toString();
                    final name = (e['Name'] ?? e['name'] ?? '-').toString();
                    return DropdownMenuItem(
                        value: id, child: Text(name, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedCashBoxId = v),
                  validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 16),

                // ربط بفاتورة (اختياري)
                DropdownButtonFormField<String>(
                  value: _selectedInvoiceId,
                  isExpanded: true,
                  style: SdText.label,
                  decoration: _dec('ربط بفاتورة (اختياري)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('بدون')),
                    ..._invoices.map((e) {
                      final id = (e['Id'] ?? e['id'] ?? '').toString();
                      final num =
                          (e['InvoiceNumber'] ?? e['invoiceNumber'] ?? '-').toString();
                      final name =
                          (e['EntityName'] ?? e['entityName'] ?? '').toString();
                      return DropdownMenuItem(
                          value: id,
                          child: Text('$num - $name', overflow: TextOverflow.ellipsis));
                    }),
                  ],
                  onChanged: widget.invoiceId != null
                      ? null
                      : (v) => setState(() => _selectedInvoiceId = v),
                ),
                const SizedBox(height: 16),

                // ملاحظات
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  style: SdText.label,
                  decoration: _dec('ملاحظات'),
                ),
              ],
            ),
          ),
          const SizedBox(height: SdSpace.xl),
          _buildSaveButton(),
          const SizedBox(height: SdSpace.md),
        ],
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
      label: 'حفظ السند',
      icon: Icons.save_rounded,
      expand: true,
      onPressed: _save,
    );
  }
}
