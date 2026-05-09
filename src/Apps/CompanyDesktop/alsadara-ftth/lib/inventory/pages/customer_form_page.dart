import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';

class CustomerFormPage extends StatefulWidget {
  final String companyId;
  final String? customerId;

  const CustomerFormPage({
    super.key,
    required this.companyId,
    this.customerId,
  });

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _saving = false;

  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _phone2Controller = TextEditingController();
  final _emailController = TextEditingController();
  final _cityController = TextEditingController();
  final _areaController = TextEditingController();
  final _addressController = TextEditingController();
  final _creditLimitController = TextEditingController();
  final _taxNumberController = TextEditingController();
  final _notesController = TextEditingController();

  // 0=Cash, 1=Credit, 2=VIP
  int _customerType = 0;

  bool get _isEditMode => widget.customerId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _loadCustomer();
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _phone2Controller.dispose();
    _emailController.dispose();
    _cityController.dispose();
    _areaController.dispose();
    _addressController.dispose();
    _creditLimitController.dispose();
    _taxNumberController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomer() async {
    setState(() => _loading = true);
    try {
      final res = await _api.getCustomer(widget.customerId!);
      final data = res['data'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _fullNameController.text = data['FullName'] ?? '';
        _phoneController.text = data['Phone'] ?? '';
        _phone2Controller.text = data['Phone2'] ?? '';
        _emailController.text = data['Email'] ?? '';
        _cityController.text = data['City'] ?? '';
        _areaController.text = data['Area'] ?? '';
        _addressController.text = data['Address'] ?? '';
        _customerType = data['CustomerType'] ?? 0;
        _creditLimitController.text =
            (data['CreditLimit'] ?? '').toString();
        _taxNumberController.text = data['TaxNumber'] ?? '';
        _notesController.text = data['Notes'] ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل تحميل بيانات العميل: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final data = <String, dynamic>{
      'fullName': _fullNameController.text.trim(),
      'phone': _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      'phone2': _phone2Controller.text.trim().isEmpty
          ? null
          : _phone2Controller.text.trim(),
      'email': _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      'city': _cityController.text.trim().isEmpty
          ? null
          : _cityController.text.trim(),
      'area': _areaController.text.trim().isEmpty
          ? null
          : _areaController.text.trim(),
      'address': _addressController.text.trim().isEmpty
          ? null
          : _addressController.text.trim(),
      'customerType': _customerType,
      'creditLimit': _customerType != 0
          ? (double.tryParse(_creditLimitController.text) ?? 0)
          : null,
      'taxNumber': _taxNumberController.text.trim().isEmpty
          ? null
          : _taxNumberController.text.trim(),
      'notes': _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      'companyId': widget.companyId,
    };

    try {
      if (_isEditMode) {
        await _api.updateCustomer(widget.customerId!, data: data);
      } else {
        await _api.createCustomer(data: data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditMode ? 'تم تعديل العميل' : 'تم إضافة العميل'),
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
          title: Text(_isEditMode ? 'تعديل عميل' : 'إضافة عميل'),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildFormFields(),
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

  Widget _buildFormFields() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            // الاسم الكامل *
            SizedBox(
              width: 300,
              child: TextFormField(
                controller: _fullNameController,
                decoration: const InputDecoration(
                  labelText: 'الاسم الكامل *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
            ),
            // الهاتف
            SizedBox(
              width: 200,
              child: TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'الهاتف',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
            // الهاتف 2
            SizedBox(
              width: 200,
              child: TextFormField(
                controller: _phone2Controller,
                decoration: const InputDecoration(
                  labelText: 'الهاتف 2',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
            ),
            // البريد الإلكتروني
            SizedBox(
              width: 250,
              child: TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            // المدينة
            SizedBox(
              width: 200,
              child: TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'المدينة',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            // المنطقة
            SizedBox(
              width: 200,
              child: TextFormField(
                controller: _areaController,
                decoration: const InputDecoration(
                  labelText: 'المنطقة',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            // العنوان
            SizedBox(
              width: 400,
              child: TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            // نوع العميل *
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<int>(
                value: _customerType,
                decoration: const InputDecoration(
                  labelText: 'نوع العميل *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('نقدي')),
                  DropdownMenuItem(value: 1, child: Text('آجل')),
                  DropdownMenuItem(value: 2, child: Text('VIP')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _customerType = v);
                },
                validator: (v) => v == null ? 'مطلوب' : null,
              ),
            ),
            // سقف الائتمان (only if type != Cash)
            if (_customerType != 0)
              SizedBox(
                width: 200,
                child: TextFormField(
                  controller: _creditLimitController,
                  decoration: const InputDecoration(
                    labelText: 'سقف الائتمان',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            // الرقم الضريبي
            SizedBox(
              width: 200,
              child: TextFormField(
                controller: _taxNumberController,
                decoration: const InputDecoration(
                  labelText: 'الرقم الضريبي',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            // ملاحظات
            SizedBox(
              width: 400,
              child: TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
