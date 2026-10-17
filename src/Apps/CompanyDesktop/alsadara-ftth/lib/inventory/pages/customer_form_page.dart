import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
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
              backgroundColor: SdColors.danger),
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
              content: Text('فشل الحفظ: $e'), backgroundColor: SdColors.danger),
        );
      }
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: SdText.bodySm,
        filled: true,
        fillColor: SdColors.surface,
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

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      maxWidth: SdSpace.formMax,
      appBar: SdAppBar(title: _isEditMode ? 'تعديل عميل' : 'إضافة عميل'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildFormFields(),
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

  Widget _buildFormFields() {
    return SdCard(
      title: 'بيانات العميل',
      icon: Icons.person_rounded,
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          // الاسم الكامل *
          SizedBox(
            width: 300,
            child: TextFormField(
              controller: _fullNameController,
              style: SdText.label,
              decoration: _dec('الاسم الكامل *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
            ),
          ),
          // الهاتف
          SizedBox(
            width: 200,
            child: TextFormField(
              controller: _phoneController,
              style: SdText.label,
              decoration: _dec('الهاتف'),
              keyboardType: TextInputType.phone,
            ),
          ),
          // الهاتف 2
          SizedBox(
            width: 200,
            child: TextFormField(
              controller: _phone2Controller,
              style: SdText.label,
              decoration: _dec('الهاتف 2'),
              keyboardType: TextInputType.phone,
            ),
          ),
          // البريد الإلكتروني
          SizedBox(
            width: 250,
            child: TextFormField(
              controller: _emailController,
              style: SdText.label,
              decoration: _dec('البريد الإلكتروني'),
              keyboardType: TextInputType.emailAddress,
            ),
          ),
          // المدينة
          SizedBox(
            width: 200,
            child: TextFormField(
              controller: _cityController,
              style: SdText.label,
              decoration: _dec('المدينة'),
            ),
          ),
          // المنطقة
          SizedBox(
            width: 200,
            child: TextFormField(
              controller: _areaController,
              style: SdText.label,
              decoration: _dec('المنطقة'),
            ),
          ),
          // العنوان
          SizedBox(
            width: 400,
            child: TextFormField(
              controller: _addressController,
              style: SdText.label,
              decoration: _dec('العنوان'),
            ),
          ),
          // نوع العميل *
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<int>(
              value: _customerType,
              style: SdText.label,
              decoration: _dec('نوع العميل *'),
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
                style: SdText.label,
                decoration: _dec('سقف الائتمان'),
                keyboardType: TextInputType.number,
              ),
            ),
          // الرقم الضريبي
          SizedBox(
            width: 200,
            child: TextFormField(
              controller: _taxNumberController,
              style: SdText.label,
              decoration: _dec('الرقم الضريبي'),
            ),
          ),
          // ملاحظات
          SizedBox(
            width: 400,
            child: TextFormField(
              controller: _notesController,
              style: SdText.label,
              decoration: _dec('ملاحظات'),
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }
}
