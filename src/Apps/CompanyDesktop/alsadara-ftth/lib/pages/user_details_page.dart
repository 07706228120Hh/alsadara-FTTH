/// صفحة تفاصيل المستخدم
/// تعرض كافة معلومات المستخدم وصلاحياته ويمكن تعديلها
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/tenant_user.dart';
import '../services/custom_auth_service.dart';

class UserDetailsPage extends StatefulWidget {
  final TenantUser user;
  final String tenantId;

  const UserDetailsPage({
    super.key,
    required this.user,
    required this.tenantId,
  });

  @override
  State<UserDetailsPage> createState() => _UserDetailsPageState();
}

class _UserDetailsPageState extends State<UserDetailsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _codeController;
  late TextEditingController _departmentController;
  late TextEditingController _centerController;
  late TextEditingController _salaryController;

  late UserRole _selectedRole;
  late bool _isActive;
  late Map<String, bool> _firstSystemPermissions;
  late Map<String, bool> _secondSystemPermissions;

  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // تهيئة Controllers
    _fullNameController = TextEditingController(text: widget.user.fullName);
    _emailController = TextEditingController(text: widget.user.email);
    _phoneController = TextEditingController(text: widget.user.phone);
    _codeController = TextEditingController(text: widget.user.code);
    _departmentController = TextEditingController(text: widget.user.department);
    _centerController = TextEditingController(text: widget.user.center);
    _salaryController = TextEditingController(text: widget.user.salary);

    // تهيئة البيانات
    _selectedRole = widget.user.role;
    _isActive = widget.user.isActive;
    _firstSystemPermissions =
        Map<String, bool>.from(widget.user.firstSystemPermissions);
    _secondSystemPermissions =
        Map<String, bool>.from(widget.user.secondSystemPermissions);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    _departmentController.dispose();
    _centerController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenantId)
          .collection('users')
          .doc(widget.user.id)
          .update({
        'fullName': _fullNameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'code': _codeController.text.trim(),
        'department': _departmentController.text.trim(),
        'center': _centerController.text.trim(),
        'salary': _salaryController.text.trim(),
        'role': _selectedRole.value,
        'isActive': _isActive,
        'firstSystemPermissions': _firstSystemPermissions,
        'secondSystemPermissions': _secondSystemPermissions,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم حفظ التغييرات بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          _isEditing = false;
        });
        Navigator.pop(context, true); // إرجاع true للإشارة إلى نجاح التعديل
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ: $e',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'تغيير كلمة المرور',
          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'كلمة المرور الجديدة',
                labelStyle: GoogleFonts.cairo(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'تأكيد كلمة المرور',
                labelStyle: GoogleFonts.cairo(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'يرجى إدخال كلمة المرور',
                      style: GoogleFonts.cairo(),
                    ),
                  ),
                );
                return;
              }

              if (passwordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'كلمات المرور غير متطابقة',
                      style: GoogleFonts.cairo(),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(context);
              await _changePassword(passwordController.text);
            },
            child: Text('تغيير', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(String newPassword) async {
    try {
      final passwordHash = CustomAuthService.hashPassword(newPassword);

      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenantId)
          .collection('users')
          .doc(widget.user.id)
          .update({
        'passwordHash': passwordHash,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تغيير كلمة المرور بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ: $e',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        elevation: 2,
        title: Text(
          'تفاصيل المستخدم: ${widget.user.username}',
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'تعديل',
            ),
          if (_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _isEditing = false),
              tooltip: 'إلغاء',
            ),
            IconButton(
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveChanges,
              tooltip: 'حفظ',
            ),
          ],
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.6),
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          indicatorSize: TabBarIndicatorSize.tab,
          labelStyle: GoogleFonts.cairo(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          unselectedLabelStyle: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.normal,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tabs: [
            Tab(
              icon: const Icon(Icons.person, size: 24),
              text: 'المعلومات الشخصية',
              height: 70,
            ),
            Tab(
              icon: const Icon(Icons.security, size: 24),
              text: 'صلاحيات النظام الأول',
              height: 70,
            ),
            Tab(
              icon: const Icon(Icons.admin_panel_settings, size: 24),
              text: 'صلاحيات النظام الثاني',
              height: 70,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPersonalInfoTab(),
          _buildFirstSystemPermissionsTab(),
          _buildSecondSystemPermissionsTab(),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // صورة المستخدم
          Center(
            child: CircleAvatar(
              radius: 60,
              backgroundColor: _isActive ? Colors.blue : Colors.grey,
              child: Text(
                widget.user.username[0].toUpperCase(),
                style: GoogleFonts.cairo(
                  fontSize: 48,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // اسم المستخدم (غير قابل للتعديل)
          _buildInfoCard(
            icon: Icons.account_circle,
            title: 'اسم المستخدم',
            child: Text(
              widget.user.username,
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // الاسم الكامل
          _buildInfoCard(
            icon: Icons.person,
            title: 'الاسم الكامل',
            child: _isEditing
                ? TextField(
                    controller: _fullNameController,
                    style: GoogleFonts.cairo(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                : Text(
                    _fullNameController.text.isEmpty
                        ? 'غير محدد'
                        : _fullNameController.text,
                    style: GoogleFonts.cairo(fontSize: 16),
                  ),
          ),

          // البريد الإلكتروني
          _buildInfoCard(
            icon: Icons.email,
            title: 'البريد الإلكتروني',
            child: _isEditing
                ? TextField(
                    controller: _emailController,
                    style: GoogleFonts.cairo(),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                : Text(
                    _emailController.text.isEmpty
                        ? 'غير محدد'
                        : _emailController.text,
                    style: GoogleFonts.cairo(fontSize: 16),
                  ),
          ),

          // رقم الهاتف
          _buildInfoCard(
            icon: Icons.phone,
            title: 'رقم الهاتف',
            child: _isEditing
                ? TextField(
                    controller: _phoneController,
                    style: GoogleFonts.cairo(),
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                : Text(
                    _phoneController.text.isEmpty
                        ? 'غير محدد'
                        : _phoneController.text,
                    style: GoogleFonts.cairo(fontSize: 16),
                  ),
          ),

          // الكود
          _buildInfoCard(
            icon: Icons.qr_code,
            title: 'الكود',
            child: _isEditing
                ? TextField(
                    controller: _codeController,
                    style: GoogleFonts.cairo(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                : Text(
                    _codeController.text.isEmpty
                        ? 'غير محدد'
                        : _codeController.text,
                    style: GoogleFonts.cairo(fontSize: 16),
                  ),
          ),

          // الدور الوظيفي
          _buildInfoCard(
            icon: Icons.work,
            title: 'الدور الوظيفي',
            child: _isEditing
                ? DropdownButtonFormField<UserRole>(
                    value: _selectedRole,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: UserRole.values.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child:
                            Text(role.arabicName, style: GoogleFonts.cairo()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedRole = value);
                      }
                    },
                  )
                : Text(
                    _selectedRole.arabicName,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),

          // القسم
          _buildInfoCard(
            icon: Icons.business,
            title: 'القسم',
            child: _isEditing
                ? TextField(
                    controller: _departmentController,
                    style: GoogleFonts.cairo(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                : Text(
                    _departmentController.text.isEmpty
                        ? 'غير محدد'
                        : _departmentController.text,
                    style: GoogleFonts.cairo(fontSize: 16),
                  ),
          ),

          // المركز
          _buildInfoCard(
            icon: Icons.location_on,
            title: 'المركز',
            child: _isEditing
                ? TextField(
                    controller: _centerController,
                    style: GoogleFonts.cairo(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                : Text(
                    _centerController.text.isEmpty
                        ? 'غير محدد'
                        : _centerController.text,
                    style: GoogleFonts.cairo(fontSize: 16),
                  ),
          ),

          // الراتب
          _buildInfoCard(
            icon: Icons.attach_money,
            title: 'الراتب',
            child: _isEditing
                ? TextField(
                    controller: _salaryController,
                    style: GoogleFonts.cairo(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                : Text(
                    _salaryController.text.isEmpty
                        ? 'غير محدد'
                        : _salaryController.text,
                    style: GoogleFonts.cairo(fontSize: 16),
                  ),
          ),

          // حالة الحساب
          _buildInfoCard(
            icon: Icons.verified_user,
            title: 'حالة الحساب',
            child: _isEditing
                ? SwitchListTile(
                    title: Text('حساب نشط', style: GoogleFonts.cairo()),
                    value: _isActive,
                    onChanged: (value) => setState(() => _isActive = value),
                    contentPadding: EdgeInsets.zero,
                  )
                : Chip(
                    label: Text(
                      _isActive ? 'نشط' : 'غير نشط',
                      style: GoogleFonts.cairo(color: Colors.white),
                    ),
                    backgroundColor: _isActive ? Colors.green : Colors.red,
                  ),
          ),

          // تاريخ الإنشاء
          _buildInfoCard(
            icon: Icons.calendar_today,
            title: 'تاريخ الإنشاء',
            child: Text(
              '${widget.user.createdAt.year}-${widget.user.createdAt.month}-${widget.user.createdAt.day}',
              style: GoogleFonts.cairo(fontSize: 16),
            ),
          ),

          // آخر تسجيل دخول
          if (widget.user.lastLogin != null)
            _buildInfoCard(
              icon: Icons.login,
              title: 'آخر تسجيل دخول',
              child: Text(
                '${widget.user.lastLogin!.year}-${widget.user.lastLogin!.month}-${widget.user.lastLogin!.day}',
                style: GoogleFonts.cairo(fontSize: 16),
              ),
            ),

          const SizedBox(height: 16),

          // زر تغيير كلمة المرور
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showChangePasswordDialog,
              icon: const Icon(Icons.lock_reset),
              label: Text('تغيير كلمة المرور', style: GoogleFonts.cairo()),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFirstSystemPermissionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'صلاحيات النظام الأول',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._firstSystemPermissions.entries.map((entry) {
          return _buildPermissionTile(
            title: _getPermissionArabicName(entry.key),
            value: entry.value,
            onChanged: (value) {
              if (_isEditing) {
                setState(() {
                  _firstSystemPermissions[entry.key] = value ?? false;
                });
              }
            },
            enabled: _isEditing,
          );
        }),
      ],
    );
  }

  Widget _buildSecondSystemPermissionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'صلاحيات النظام الثاني (FTTH)',
          style: GoogleFonts.cairo(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ..._secondSystemPermissions.entries.map((entry) {
          return _buildPermissionTile(
            title: _getPermissionArabicName(entry.key),
            value: entry.value,
            onChanged: (value) {
              if (_isEditing) {
                setState(() {
                  _secondSystemPermissions[entry.key] = value ?? false;
                });
              }
            },
            enabled: _isEditing,
          );
        }),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required bool value,
    required ValueChanged<bool?> onChanged,
    required bool enabled,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        title: Text(
          title,
          style: GoogleFonts.cairo(
            color: enabled ? Colors.black : Colors.grey,
          ),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
        activeColor: Colors.green,
      ),
    );
  }

  String _getPermissionArabicName(String key) {
    const Map<String, String> permissionNames = {
      // النظام الأول
      'attendance': 'الحضور والغياب',
      'agent': 'الوكلاء',
      'tasks': 'المهام',
      'zones': 'المناطق',
      'ai_search': 'البحث الذكي',
      // النظام الثاني
      'users': 'المستخدمين',
      'subscriptions': 'الاشتراكات',
      'accounts': 'الحسابات',
      'account_records': 'سجلات الحسابات',
      'export': 'تصدير البيانات',
      'agents': 'الوكلاء',
      'google_sheets': 'حفظ في الخادم',
      'whatsapp': 'واتساب',
      'wallet_balance': 'رصيد المحفظة',
      'expiring_soon': 'الاشتراكات المنتهية قريباً',
      'quick_search': 'البحث السريع',
      'transactions': 'المعاملات',
      'notifications': 'الإشعارات',
      'audit_logs': 'سجلات التدقيق',
      'whatsapp_link': 'ربط واتساب',
      'whatsapp_settings': 'إعدادات واتساب',
      'plans_bundles': 'الباقات والعروض',
      'technicians': 'الفنيين',
      'whatsapp_business_api': 'واتساب بيزنس API',
      'whatsapp_bulk_sender': 'إرسال جماعي واتساب',
      'whatsapp_conversations_fab': 'محادثات واتساب',
      'local_storage': 'التخزين المحلي',
      'local_storage_import': 'استيراد التخزين المحلي',
    };
    return permissionNames[key] ?? key;
  }
}
