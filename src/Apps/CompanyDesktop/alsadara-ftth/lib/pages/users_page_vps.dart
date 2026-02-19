/// 👥 صفحة إدارة موظفي الشركة - VPS API
/// تعرض موظفي الشركة من قاعدة بيانات PostgreSQL عبر VPS API
/// مع إمكانية إضافة/تعديل/حذف الموظفين وإدارة الصلاحيات
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api/api_client.dart';
import '../services/api/api_config.dart';
import 'super_admin/permissions_management_v2_page.dart';
import '../services/permission_checker.dart';

/// صفحة إدارة موظفي الشركة عبر VPS
class UsersPageVPS extends StatefulWidget {
  final String companyId;
  final String companyName;
  final Map<String, dynamic>? permissions;
  final int maxUsers;

  const UsersPageVPS({
    super.key,
    required this.companyId,
    required this.companyName,
    this.permissions,
    this.maxUsers = 100,
  });

  @override
  State<UsersPageVPS> createState() => _UsersPageVPSState();
}

class _UsersPageVPSState extends State<UsersPageVPS> {
  final ApiClient _apiClient = ApiClient.instance;
  final TextEditingController _searchController = TextEditingController();

  List<EmployeeModel> _employees = [];
  List<EmployeeModel> _filteredEmployees = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// تحميل الموظفين من VPS API
  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('📡 جلب موظفي الشركة: ${widget.companyId}');

      final response = await _apiClient.get(
        ApiConfig.internalCompanyEmployees(widget.companyId),
        (json) => json,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final List<dynamic> usersJson = response.data is List
            ? response.data
            : (response.data['data'] ?? response.data['users'] ?? []);

        setState(() {
          _employees =
              usersJson.map((json) => EmployeeModel.fromJson(json)).toList();
          _filteredEmployees = _employees;
          _isLoading = false;
        });

        debugPrint('✅ تم جلب ${_employees.length} موظف');
      } else {
        setState(() {
          _error = response.message ?? 'فشل في جلب الموظفين';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب الموظفين: $e');
      setState(() {
        _error = 'خطأ في الاتصال: $e';
        _isLoading = false;
      });
    }
  }

  /// فلترة الموظفين حسب البحث
  void _filterEmployees(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredEmployees = _employees;
      } else {
        _filteredEmployees = _employees.where((emp) {
          return emp.fullName.toLowerCase().contains(query.toLowerCase()) ||
              emp.phoneNumber.contains(query) ||
              (emp.email?.toLowerCase().contains(query.toLowerCase()) ??
                  false) ||
              (emp.role?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: _buildAppBar(),
        body: _buildBody(),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إدارة الموظفين',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            widget.companyName,
            style:
                TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1976D2),
      foregroundColor: Colors.white,
      elevation: 0,
      actions: [
        // عدد الموظفين
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people, size: 16),
              const SizedBox(width: 4),
              Text(
                '${_employees.length}/${widget.maxUsers}',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        // زر التحديث
        IconButton(
          onPressed: _loadEmployees,
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'تحديث',
        ),
      ],
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // شريط البحث
        _buildSearchBar(),
        // المحتوى
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildErrorWidget()
                  : _filteredEmployees.isEmpty
                      ? _buildEmptyWidget()
                      : _buildEmployeesList(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: TextField(
        controller: _searchController,
        onChanged: _filterEmployees,
        decoration: InputDecoration(
          hintText: 'بحث عن موظف...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _filterEmployees('');
                  },
                  icon: const Icon(Icons.clear_rounded),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: TextStyle(color: Colors.red.shade700, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadEmployees,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'لا توجد نتائج للبحث "$_searchQuery"'
                : 'لا يوجد موظفين',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 24),
          if (_searchQuery.isEmpty &&
              PermissionManager.instance.canAdd('users'))
            ElevatedButton.icon(
              onPressed: () => _showAddEmployeeDialog(),
              icon: const Icon(Icons.person_add_rounded),
              label: const Text('إضافة أول موظف'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmployeesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredEmployees.length,
      itemBuilder: (context, index) {
        final employee = _filteredEmployees[index];
        return _buildEmployeeCard(employee);
      },
    );
  }

  Widget _buildEmployeeCard(EmployeeModel employee) {
    final roleColor = _getRoleColor(employee.role);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: InkWell(
        onTap: () => _showEmployeeDetails(employee),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // الصف الأول: الأفاتار والمعلومات الأساسية
              Row(
                children: [
                  // الأفاتار
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: employee.isActive
                        ? roleColor.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    child: Text(
                      employee.fullName.isNotEmpty
                          ? employee.fullName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: employee.isActive ? roleColor : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // المعلومات
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // الاسم والحالة
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                employee.fullName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // شارة الحالة
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: employee.isActive
                                    ? const Color(0xFFE8F5E9)
                                    : const Color(0xFFFFEBEE),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                employee.isActive ? 'نشط' : 'معطل',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: employee.isActive
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFF44336),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // الدور
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: roleColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getRoleNameAr(employee.role),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: roleColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (employee.employeeCode != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                employee.employeeCode!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // الصف الثاني: معلومات الاتصال
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    // الهاتف
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.phone_rounded,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              employee.phoneNumber,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // البريد
                    if (employee.email != null && employee.email!.isNotEmpty)
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.email_rounded,
                                size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                employee.email!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // الصف الثالث: أزرار الإجراءات
              Row(
                children: [
                  // زر الصلاحيات
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _managePermissions(employee),
                      icon: const Icon(Icons.security_rounded, size: 18),
                      label: const Text('الصلاحيات'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF9C27B0),
                        side: const BorderSide(color: Color(0xFF9C27B0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // زر التعديل
                  if (PermissionManager.instance.canEdit('users'))
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editEmployee(employee),
                        icon: const Icon(Icons.edit_rounded, size: 18),
                        label: const Text('تعديل'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2196F3),
                          side: const BorderSide(color: Color(0xFF2196F3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  // زر كلمة المرور
                  IconButton(
                    onPressed: () => _showPasswordDialog(employee),
                    icon: const Icon(Icons.key_rounded),
                    color: const Color(0xFFFF9800),
                    tooltip: 'كلمة المرور',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildFAB() {
    if (_employees.length >= widget.maxUsers) return null;
    if (!PermissionManager.instance.canAdd('users')) return null;

    return FloatingActionButton.extended(
      onPressed: () => _showAddEmployeeDialog(),
      backgroundColor: const Color(0xFF4CAF50),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.person_add_rounded),
      label: const Text('إضافة موظف'),
    );
  }

  /// عرض تفاصيل الموظف
  void _showEmployeeDetails(EmployeeModel employee) {
    showDialog(
      context: context,
      builder: (context) => _EmployeeDetailsDialog(
        employee: employee,
        onEdit: () {
          Navigator.pop(context);
          _editEmployee(employee);
        },
        onManagePermissions: () {
          Navigator.pop(context);
          _managePermissions(employee);
        },
        onDelete: PermissionManager.instance.canDelete('users')
            ? () async {
                Navigator.pop(context);
                await _deleteEmployee(employee);
              }
            : null,
      ),
    );
  }

  /// إدارة صلاحيات الموظف
  Future<void> _managePermissions(EmployeeModel employee) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PermissionsManagementV2Page(
          companyId: widget.companyId,
          companyName: widget.companyName,
          employeeId: employee.id,
          employeeName: employee.fullName,
        ),
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  /// إضافة موظف جديد
  Future<void> _showAddEmployeeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddEditEmployeeDialog(
        companyId: widget.companyId,
        apiClient: _apiClient,
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  /// تعديل موظف
  Future<void> _editEmployee(EmployeeModel employee) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddEditEmployeeDialog(
        companyId: widget.companyId,
        apiClient: _apiClient,
        employee: employee,
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  /// حذف موظف
  Future<void> _deleteEmployee(EmployeeModel employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('تأكيد الحذف'),
          ],
        ),
        content: Text('هل أنت متأكد من حذف الموظف "${employee.fullName}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final response = await _apiClient.delete(
          ApiConfig.internalEmployeeById(widget.companyId, employee.id),
          (json) => json,
          useInternalKey: true,
        );

        if (response.isSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف الموظف بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          _loadEmployees();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'فشل في حذف الموظف'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// عرض كلمة المرور
  Future<void> _showPasswordDialog(EmployeeModel employee) async {
    final passwordController = TextEditingController();
    bool showPassword = false;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.key_rounded, color: Color(0xFFFF9800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'كلمة مرور ${employee.fullName}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // كلمة المرور الحالية
              if (employee.password != null && employee.password!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFE0B2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Color(0xFFFF9800), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'كلمة المرور الحالية:',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF795548)),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              employee.password!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: employee.password!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ كلمة المرور'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'نسخ',
                      ),
                    ],
                  ),
                ),
              // تغيير كلمة المرور
              const Text(
                'تغيير كلمة المرور:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: !showPassword,
                decoration: InputDecoration(
                  hintText: 'كلمة المرور الجديدة',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setDialogState(() => showPassword = !showPassword),
                    icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              onPressed: isSaving || passwordController.text.isEmpty
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);

                      try {
                        final response = await _apiClient.patch(
                          ApiConfig.internalEmployeePassword(
                              widget.companyId, employee.id),
                          {'NewPassword': passwordController.text},
                          (json) => json,
                          useInternalKey: true,
                        );

                        if (response.isSuccess) {
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تغيير كلمة المرور بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadEmployees();
                          }
                        } else {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(response.message ??
                                    'فشل في تغيير كلمة المرور'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// الحصول على لون الدور
  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'companyadmin':
        return const Color(0xFF9C27B0);
      case 'manager':
        return const Color(0xFF2196F3);
      case 'technicalleader':
        return const Color(0xFF00BCD4);
      case 'technician':
        return const Color(0xFF4CAF50);
      case 'viewer':
        return const Color(0xFF607D8B);
      default:
        return const Color(0xFF795548);
    }
  }

  /// الحصول على اسم الدور بالعربي
  String _getRoleNameAr(String? role) {
    switch (role?.toLowerCase()) {
      case 'companyadmin':
        return 'مدير الشركة';
      case 'manager':
        return 'مدير';
      case 'technicalleader':
        return 'ليدر فني';
      case 'technician':
        return 'فني';
      case 'viewer':
        return 'مشاهد';
      case 'employee':
        return 'موظف';
      default:
        return role ?? 'غير محدد';
    }
  }
}

// ============================================
// نموذج الموظف
// ============================================

class EmployeeModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String? role;
  final String? department;
  final String? employeeCode;
  final String? center;
  final String? salary;
  final String? password;
  final bool isActive;
  final DateTime? createdAt;
  final Map<String, dynamic>? firstSystemPermissions;
  final Map<String, dynamic>? secondSystemPermissions;

  EmployeeModel({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.email,
    this.role,
    this.department,
    this.employeeCode,
    this.center,
    this.salary,
    this.password,
    required this.isActive,
    this.createdAt,
    this.firstSystemPermissions,
    this.secondSystemPermissions,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      id: (json['id'] ?? json['Id'] ?? json['userId'] ?? json['UserId'])
              ?.toString() ??
          '',
      fullName: json['fullName'] ??
          json['FullName'] ??
          json['name'] ??
          json['Name'] ??
          '',
      phoneNumber: json['phoneNumber'] ??
          json['PhoneNumber'] ??
          json['phone'] ??
          json['Phone'] ??
          '',
      email: json['email'] ?? json['Email'],
      role:
          json['role'] ?? json['Role'] ?? json['jobTitle'] ?? json['JobTitle'],
      department: json['department'] ?? json['Department'],
      employeeCode: json['employeeCode'] ?? json['EmployeeCode'],
      center: json['center'] ?? json['Center'],
      salary: json['salary']?.toString() ?? json['Salary']?.toString(),
      password: json['password'] ?? json['Password'],
      isActive: json['isActive'] ?? json['IsActive'] ?? true,
      createdAt: json['createdAt'] != null || json['CreatedAt'] != null
          ? DateTime.tryParse(
              (json['createdAt'] ?? json['CreatedAt']).toString())
          : null,
      firstSystemPermissions: _parsePermissions(
          json['firstSystemPermissions'] ?? json['FirstSystemPermissions']),
      secondSystemPermissions: _parsePermissions(
          json['secondSystemPermissions'] ?? json['SecondSystemPermissions']),
    );
  }

  static Map<String, dynamic>? _parsePermissions(dynamic value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(value));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

// ============================================
// نافذة تفاصيل الموظف
// ============================================

class _EmployeeDetailsDialog extends StatelessWidget {
  final EmployeeModel employee;
  final VoidCallback onEdit;
  final VoidCallback onManagePermissions;
  final VoidCallback? onDelete;

  const _EmployeeDetailsDialog({
    required this.employee,
    required this.onEdit,
    required this.onManagePermissions,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // الأفاتار
            CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFF1976D2).withOpacity(0.1),
              child: Text(
                employee.fullName.isNotEmpty
                    ? employee.fullName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1976D2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // الاسم
            Text(
              employee.fullName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            // الدور
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getRoleNameAr(employee.role),
                style: const TextStyle(
                  color: Color(0xFF1976D2),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // المعلومات
            _buildInfoRow(Icons.phone_rounded, 'الهاتف', employee.phoneNumber),
            if (employee.email != null && employee.email!.isNotEmpty)
              _buildInfoRow(Icons.email_rounded, 'البريد', employee.email!),
            if (employee.department != null && employee.department!.isNotEmpty)
              _buildInfoRow(
                  Icons.business_rounded, 'القسم', employee.department!),
            if (employee.center != null && employee.center!.isNotEmpty)
              _buildInfoRow(
                  Icons.location_on_rounded, 'المركز', employee.center!),
            if (employee.employeeCode != null)
              _buildInfoRow(
                  Icons.badge_rounded, 'الكود', employee.employeeCode!),
            const SizedBox(height: 24),
            // الأزرار
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onManagePermissions,
                    icon: const Icon(Icons.security_rounded),
                    label: const Text('الصلاحيات'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9C27B0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('تعديل'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2196F3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_rounded),
                    label: const Text('حذف'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          onDelete != null ? Colors.red : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('إغلاق'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }

  String _getRoleNameAr(String? role) {
    switch (role?.toLowerCase()) {
      case 'companyadmin':
        return 'مدير الشركة';
      case 'manager':
        return 'مدير';
      case 'technicalleader':
        return 'ليدر فني';
      case 'technician':
        return 'فني';
      case 'viewer':
        return 'مشاهد';
      case 'employee':
        return 'موظف';
      default:
        return role ?? 'غير محدد';
    }
  }
}

// ============================================
// نافذة إضافة/تعديل موظف
// ============================================

class _AddEditEmployeeDialog extends StatefulWidget {
  final String companyId;
  final ApiClient apiClient;
  final EmployeeModel? employee;

  const _AddEditEmployeeDialog({
    required this.companyId,
    required this.apiClient,
    this.employee,
  });

  @override
  State<_AddEditEmployeeDialog> createState() => _AddEditEmployeeDialogState();
}

class _AddEditEmployeeDialogState extends State<_AddEditEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _departmentController = TextEditingController();
  final _centerController = TextEditingController();
  final _salaryController = TextEditingController();

  String _selectedRole = 'Employee';
  bool _isActive = true;
  bool _isSaving = false;

  static const List<Map<String, String>> _roles = [
    {'value': 'Employee', 'label': 'موظف'},
    {'value': 'Viewer', 'label': 'مشاهد'},
    {'value': 'Technician', 'label': 'فني'},
    {'value': 'TechnicalLeader', 'label': 'ليدر فني'},
    {'value': 'Manager', 'label': 'مدير'},
    {'value': 'CompanyAdmin', 'label': 'مدير الشركة'},
  ];

  static const List<String> _departments = [
    'الصيانة',
    'الحسابات',
    'الفنيين',
    'الوكلاء',
    'الاتصالات',
    'اللحام',
  ];

  bool get isEditing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final emp = widget.employee!;
      _nameController.text = emp.fullName;
      _phoneController.text = emp.phoneNumber;
      _emailController.text = emp.email ?? '';
      _departmentController.text = emp.department ?? '';
      _centerController.text = emp.center ?? '';
      _salaryController.text = emp.salary ?? '';
      // التأكد أن الدور موجود في القائمة
      final role = emp.role ?? 'Employee';
      final roleExists =
          _roles.any((r) => r['value']!.toLowerCase() == role.toLowerCase());
      _selectedRole = roleExists
          ? _roles.firstWhere(
              (r) => r['value']!.toLowerCase() == role.toLowerCase())['value']!
          : 'Employee';
      _isActive = emp.isActive;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _departmentController.dispose();
    _centerController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final data = {
        'fullName': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'email': _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : null,
        'role': _selectedRole,
        'department': _departmentController.text.trim().isNotEmpty
            ? _departmentController.text.trim()
            : null,
        'center': _centerController.text.trim().isNotEmpty
            ? _centerController.text.trim()
            : null,
        'salary': _salaryController.text.trim().isNotEmpty
            ? _salaryController.text.trim()
            : null,
        'isActive': _isActive,
      };

      // إضافة كلمة المرور فقط عند الإضافة أو إذا تم تعديلها
      if (!isEditing || _passwordController.text.isNotEmpty) {
        data['password'] = _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null;
      }

      final response = isEditing
          ? await widget.apiClient.put(
              ApiConfig.internalEmployeeById(
                  widget.companyId, widget.employee!.id),
              data,
              (json) => json,
              useInternalKey: true,
            )
          : await widget.apiClient.post(
              ApiConfig.internalCompanyEmployees(widget.companyId),
              data,
              (json) => json,
              useInternalKey: true,
            );

      if (response.isSuccess) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEditing
                  ? 'تم تحديث الموظف بنجاح'
                  : 'تم إضافة الموظف بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ??
                  'فشل في ${isEditing ? 'تحديث' : 'إضافة'} الموظف'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // العنوان
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isEditing
                    ? const Color(0xFF2196F3)
                    : const Color(0xFF4CAF50),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'تعديل موظف' : 'إضافة موظف جديد',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            // النموذج
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // المعلومات الأساسية
                      _buildSectionTitle(
                          'المعلومات الأساسية', Icons.person_rounded),
                      const SizedBox(height: 12),
                      // الاسم
                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration(
                            'الاسم الكامل *', Icons.person_outline),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      // الهاتف
                      TextFormField(
                        controller: _phoneController,
                        decoration: _inputDecoration(
                            'رقم الهاتف * (للدخول)', Icons.phone_outlined),
                        keyboardType: TextInputType.phone,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      // كلمة المرور
                      TextFormField(
                        controller: _passwordController,
                        decoration: _inputDecoration(
                          isEditing
                              ? 'كلمة المرور الجديدة (اختياري)'
                              : 'كلمة المرور (افتراضي: 123456)',
                          Icons.lock_outline,
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      // البريد
                      TextFormField(
                        controller: _emailController,
                        decoration: _inputDecoration(
                            'البريد الإلكتروني (اختياري)',
                            Icons.email_outlined),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 20),
                      // الدور والحالة
                      _buildSectionTitle('الدور والحالة', Icons.badge_rounded),
                      const SizedBox(height: 12),
                      // الدور
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: _inputDecoration(
                            'الدور الوظيفي *', Icons.work_outline),
                        items: _roles
                            .map((r) => DropdownMenuItem(
                                  value: r['value'],
                                  child: Text(r['label']!),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedRole = v!),
                      ),
                      const SizedBox(height: 12),
                      // الحالة
                      SwitchListTile(
                        title: const Text('الحساب نشط'),
                        subtitle: Text(_isActive
                            ? 'يمكنه تسجيل الدخول'
                            : 'محظور من الدخول'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        secondary: Icon(
                          _isActive ? Icons.check_circle : Icons.block,
                          color: _isActive ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // معلومات إضافية
                      _buildSectionTitle(
                          'معلومات إضافية (اختياري)', Icons.info_outline),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _departmentController.text.isNotEmpty &&
                                      _getAllDepartments()
                                          .contains(_departmentController.text)
                                  ? _departmentController.text
                                  : null,
                              decoration: _inputDecoration(
                                  _departmentController.text.isNotEmpty &&
                                          !_departments.contains(
                                              _departmentController.text)
                                      ? 'القسم (الحالي: ${_departmentController.text})'
                                      : 'القسم',
                                  Icons.business_outlined),
                              items: _getAllDepartments()
                                  .map((d) => DropdownMenuItem(
                                      value: d, child: Text(d)))
                                  .toList(),
                              onChanged: (v) {
                                setState(() {
                                  _departmentController.text = v ?? '';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _centerController,
                              decoration: _inputDecoration(
                                  'المركز', Icons.location_on_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _salaryController,
                        decoration:
                            _inputDecoration('الراتب', Icons.attach_money),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // الأزرار
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(isEditing
                              ? Icons.save_rounded
                              : Icons.person_add_rounded),
                      label: Text(isEditing ? 'حفظ التغييرات' : 'إضافة الموظف'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isEditing
                            ? const Color(0xFF2196F3)
                            : const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// قائمة الأقسام مع إضافة القسم الحالي إذا لم يكن في القائمة الافتراضية
  List<String> _getAllDepartments() {
    final current = _departmentController.text;
    if (current.isNotEmpty && !_departments.contains(current)) {
      return [current, ..._departments];
    }
    return _departments;
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF1976D2)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1976D2),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}
