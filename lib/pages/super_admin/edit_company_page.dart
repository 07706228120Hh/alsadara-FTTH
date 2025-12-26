/// صفحة تعديل بيانات الشركة
/// تتضمن تعديل بيانات الشركة والاشتراك
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../multi_tenant.dart';

class EditCompanyPage extends StatefulWidget {
  final Tenant tenant;

  const EditCompanyPage({super.key, required this.tenant});

  @override
  State<EditCompanyPage> createState() => _EditCompanyPageState();
}

class _EditCompanyPageState extends State<EditCompanyPage> {
  final _formKey = GlobalKey<FormState>();
  final TenantService _tenantService = TenantService();

  // بيانات الشركة
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _maxUsersController;

  // بيانات الاشتراك
  late DateTime _subscriptionEnd;
  late String _subscriptionPlan;
  late bool _isActive;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // تعبئة البيانات الحالية
    _nameController = TextEditingController(text: widget.tenant.name);
    _codeController = TextEditingController(text: widget.tenant.code);

    _phoneController = TextEditingController(text: widget.tenant.phone ?? '');
    _addressController =
        TextEditingController(text: widget.tenant.address ?? '');
    _maxUsersController =
        TextEditingController(text: widget.tenant.maxUsers.toString());

    _subscriptionEnd = widget.tenant.subscriptionEnd;
    _subscriptionPlan = widget.tenant.subscriptionPlan;
    _isActive = widget.tenant.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _maxUsersController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _subscriptionEnd,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() {
        _subscriptionEnd = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _tenantService.updateTenant(
        widget.tenant.id,
        {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          'address': _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          'maxUsers': int.tryParse(_maxUsersController.text) ?? 10,
          'subscriptionPlan': _subscriptionPlan,
          'isActive': _isActive,
        },
      );

      // تحديث تاريخ الاشتراك منفصلاً
      if (success) {
        await _tenantService.extendSubscription(
          widget.tenant.id,
          _subscriptionEnd,
          _subscriptionPlan,
        );
      }

      setState(() {
        _isLoading = false;
      });

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث بيانات الشركة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل تحديث بيانات الشركة'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');

    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل الشركة'),
        backgroundColor: const Color(0xFF1a237e),
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'حفظ',
              onPressed: _save,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // قسم بيانات الشركة
              _buildSectionCard(
                title: 'بيانات الشركة',
                icon: Icons.business,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الشركة *',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'الرجاء إدخال اسم الشركة';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _codeController,
                    readOnly: true,
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'كود الشركة',
                      prefixIcon: const Icon(Icons.tag),
                      border: const OutlineInputBorder(),
                      helperText: 'الكود يُنشأ تلقائياً ولا يمكن تغييره',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'العنوان',
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // قسم الاشتراك
              _buildSectionCard(
                title: 'بيانات الاشتراك',
                icon: Icons.card_membership,
                children: [
                  // تاريخ انتهاء الاشتراك
                  InkWell(
                    onTap: _selectDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'تاريخ انتهاء الاشتراك',
                        prefixIcon: Icon(Icons.calendar_today),
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(dateFormat.format(_subscriptionEnd)),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // نوع الباقة
                  DropdownButtonFormField<String>(
                    value: _subscriptionPlan,
                    decoration: const InputDecoration(
                      labelText: 'نوع الباقة',
                      prefixIcon: Icon(Icons.workspace_premium),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                      DropdownMenuItem(
                          value: 'quarterly', child: Text('ربع سنوي')),
                      DropdownMenuItem(value: 'yearly', child: Text('سنوي')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _subscriptionPlan = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // الحد الأقصى للمستخدمين
                  TextFormField(
                    controller: _maxUsersController,
                    decoration: const InputDecoration(
                      labelText: 'الحد الأقصى للمستخدمين',
                      prefixIcon: Icon(Icons.people),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'الرجاء إدخال عدد المستخدمين';
                      }
                      final number = int.tryParse(value);
                      if (number == null || number < 1) {
                        return 'الرجاء إدخال رقم صحيح';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // حالة الشركة
                  SwitchListTile(
                    title: const Text('الشركة نشطة'),
                    subtitle: Text(_isActive
                        ? 'الشركة فعالة ويمكن للمستخدمين تسجيل الدخول'
                        : 'الشركة معلقة ولا يمكن للمستخدمين تسجيل الدخول'),
                    value: _isActive,
                    activeColor: Colors.green,
                    onChanged: (value) {
                      setState(() {
                        _isActive = value;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // زر الحفظ
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _save,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: Text(_isLoading ? 'جاري الحفظ...' : 'حفظ التغييرات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1a237e),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF1a237e)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1a237e),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}
