/// صفحة تعديل بيانات الشركة - تستخدم VPS API
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';
import '../../multi_tenant.dart';
import '../../theme/energy_dashboard_theme.dart';

class EditCompanyPage extends StatefulWidget {
  final Tenant tenant;

  const EditCompanyPage({super.key, required this.tenant});

  @override
  State<EditCompanyPage> createState() => _EditCompanyPageState();
}

class _EditCompanyPageState extends State<EditCompanyPage> {
  final _formKey = GlobalKey<FormState>();
  final ApiClient _apiClient = ApiClient.instance;

  // بيانات الشركة
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _cityController;
  late final TextEditingController _maxUsersController;

  // بيانات الاشتراك
  late DateTime _subscriptionEnd;
  late String _subscriptionPlan;
  late bool _isActive;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tenant.name);
    _codeController = TextEditingController(text: widget.tenant.code);
    _phoneController = TextEditingController(text: widget.tenant.phone ?? '');
    _emailController = TextEditingController(text: widget.tenant.email ?? '');
    _addressController =
        TextEditingController(text: widget.tenant.address ?? '');
    _cityController = TextEditingController(text: widget.tenant.city ?? '');
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
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: EnergyDashboardTheme.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _subscriptionEnd = picked;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await _apiClient.put(
        '${ApiConfig.internalCompanies}/${widget.tenant.id}',
        {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          'email': _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          'address': _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          'city': _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          'maxUsers': int.tryParse(_maxUsersController.text) ?? 10,
          'subscriptionEndDate': _subscriptionEnd.toIso8601String(),
          'isActive': _isActive,
        },
        (json) => json,
        useInternalKey: true,
      );

      setState(() => _isLoading = false);

      if (response.isSuccess && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('تم تحديث بيانات الشركة بنجاح'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(response.message ?? 'فشل تحديث بيانات الشركة')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('حدث خطأ: $e')),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');

    return Scaffold(
      backgroundColor: EnergyDashboardTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('تعديل الشركة'),
        backgroundColor: EnergyDashboardTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded, color: Colors.white),
                label: const Text('حفظ',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // قسم بيانات الشركة
              _buildModernCard(
                title: 'بيانات الشركة',
                icon: Icons.business_rounded,
                color: Colors.blue,
                children: [
                  _buildTextField(
                    controller: _nameController,
                    label: 'اسم الشركة',
                    icon: Icons.business_rounded,
                    required: true,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _codeController,
                    label: 'كود الشركة',
                    icon: Icons.tag_rounded,
                    readOnly: true,
                    hint: 'الكود يُنشأ تلقائياً ولا يمكن تغييره',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _phoneController,
                          label: 'رقم الهاتف',
                          icon: Icons.phone_rounded,
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextField(
                          controller: _emailController,
                          label: 'البريد الإلكتروني',
                          icon: Icons.email_rounded,
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _addressController,
                          label: 'العنوان',
                          icon: Icons.location_on_rounded,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextField(
                          controller: _cityController,
                          label: 'المدينة',
                          icon: Icons.location_city_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // قسم الاشتراك
              _buildModernCard(
                title: 'بيانات الاشتراك',
                icon: Icons.card_membership_rounded,
                color: Colors.green,
                children: [
                  // تاريخ انتهاء الاشتراك
                  _buildDateField(
                    label: 'تاريخ انتهاء الاشتراك',
                    value: dateFormat.format(_subscriptionEnd),
                    onTap: _selectDate,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      // نوع الباقة
                      Expanded(
                        child: _buildDropdownField(
                          label: 'نوع الباقة',
                          value: _subscriptionPlan,
                          items: const [
                            DropdownMenuItem(
                                value: 'monthly', child: Text('شهري')),
                            DropdownMenuItem(
                                value: 'quarterly', child: Text('ربع سنوي')),
                            DropdownMenuItem(
                                value: 'yearly', child: Text('سنوي')),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _subscriptionPlan = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      // الحد الأقصى للمستخدمين
                      Expanded(
                        child: _buildTextField(
                          controller: _maxUsersController,
                          label: 'الحد الأقصى للمستخدمين',
                          icon: Icons.people_rounded,
                          keyboardType: TextInputType.number,
                          required: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // حالة الشركة
                  _buildStatusSwitch(),
                ],
              ),
              const SizedBox(height: 32),

              // زر الحفظ
              _buildSaveButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.1), color.withOpacity(0.15)],
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    bool readOnly = false,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        hintText: hint,
        prefixIcon: Icon(icon, color: EnergyDashboardTheme.primaryColor),
        filled: true,
        fillColor: readOnly
            ? Colors.grey.shade100
            : EnergyDashboardTheme.backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: EnergyDashboardTheme.borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: EnergyDashboardTheme.borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: EnergyDashboardTheme.primaryColor, width: 2),
        ),
      ),
      validator: required
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return 'هذا الحقل مطلوب';
              }
              return null;
            }
          : null,
    );
  }

  Widget _buildDateField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: EnergyDashboardTheme.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EnergyDashboardTheme.borderColor),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_rounded,
                color: EnergyDashboardTheme.primaryColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: EnergyDashboardTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down,
                color: EnergyDashboardTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: DropdownButtonFormField<String>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          prefixIcon: Icon(Icons.workspace_premium_rounded,
              color: EnergyDashboardTheme.primaryColor),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildStatusSwitch() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isActive
            ? Colors.green.withOpacity(0.1)
            : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isActive
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _isActive
                  ? Colors.green.withOpacity(0.2)
                  : Colors.orange.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isActive
                  ? Icons.check_circle_rounded
                  : Icons.pause_circle_rounded,
              color: _isActive ? Colors.green : Colors.orange,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isActive ? 'الشركة نشطة' : 'الشركة معلقة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isActive ? Colors.green : Colors.orange,
                  ),
                ),
                Text(
                  _isActive
                      ? 'الشركة فعالة ويمكن للمستخدمين تسجيل الدخول'
                      : 'الشركة معلقة ولا يمكن للمستخدمين تسجيل الدخول',
                  style: TextStyle(
                    fontSize: 12,
                    color: EnergyDashboardTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _isActive,
            onChanged: (value) => setState(() => _isActive = value),
            activeColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isLoading
              ? [Colors.grey, Colors.grey.shade600]
              : [EnergyDashboardTheme.primaryColor, const Color(0xFF3949AB)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: _isLoading
            ? null
            : [
                BoxShadow(
                  color: EnergyDashboardTheme.primaryColor.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _save,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: _isLoading
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'جاري الحفظ...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save_rounded, color: Colors.white, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'حفظ التغييرات',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
