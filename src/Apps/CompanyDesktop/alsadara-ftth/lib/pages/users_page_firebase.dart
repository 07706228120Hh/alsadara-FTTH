/// صفحة إدارة المستخدمين - Firebase Multi-Tenant
/// تجلب البيانات من Firebase Firestore حسب الشركة
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/tenant_user.dart';
import '../services/custom_auth_service.dart';
import 'user_details_page.dart';

class UsersPageFirebase extends StatefulWidget {
  final String tenantId; // معرف الشركة
  final String permissions; // صلاحيات المستخدم الحالي
  @Deprecated('استخدم PermissionManager.instance.canView() مباشرة')
  final Map<String, bool> pageAccess; // صلاحيات الصفحات

  const UsersPageFirebase({
    super.key,
    required this.tenantId,
    required this.permissions,
    this.pageAccess = const {},
  });

  @override
  State<UsersPageFirebase> createState() => _UsersPageFirebaseState();
}

class _UsersPageFirebaseState extends State<UsersPageFirebase> {
  final TextEditingController _searchController = TextEditingController();
  List<TenantUser> _allUsers = [];
  List<TenantUser> _filteredUsers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenantId)
          .collection('users')
          .orderBy('username')
          .get();

      final users = usersSnapshot.docs
          .map((doc) => TenantUser.fromFirestore(doc, widget.tenantId))
          .toList();

      setState(() {
        _allUsers = users;
        _filteredUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء جلب المستخدمين: $e';
        _isLoading = false;
      });
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        _filteredUsers = _allUsers.where((user) {
          return user.username.toLowerCase().contains(query) ||
              user.fullName.toLowerCase().contains(query) ||
              (user.phone?.toLowerCase().contains(query) ?? false) ||
              (user.email?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  Future<void> _showAddUserDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final fullNameController = TextEditingController();
    final phoneController = TextEditingController();
    final codeController = TextEditingController();
    final departmentController = TextEditingController();
    final centerController = TextEditingController();
    final salaryController = TextEditingController();
    UserRole selectedRole = UserRole.employee;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'إضافة مستخدم جديد',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: 'اسم المستخدم *',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور *',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: fullNameController,
                  decoration: InputDecoration(
                    labelText: 'الاسم الكامل',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  decoration: InputDecoration(
                    labelText: 'الدور الوظيفي',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                  items: UserRole.values.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role.arabicName, style: GoogleFonts.cairo()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedRole = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: departmentController,
                  decoration: InputDecoration(
                    labelText: 'القسم',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: centerController,
                  decoration: InputDecoration(
                    labelText: 'المركز',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salaryController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الراتب',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () async {
                if (usernameController.text.isEmpty ||
                    passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'يرجى إدخال اسم المستخدم وكلمة المرور',
                        style: GoogleFonts.cairo(),
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                await _addUser(
                  username: usernameController.text.trim(),
                  password: passwordController.text,
                  fullName: fullNameController.text.trim(),
                  phone: phoneController.text.trim(),
                  role: selectedRole,
                  code: codeController.text.trim(),
                  department: departmentController.text.trim(),
                  center: centerController.text.trim(),
                  salary: salaryController.text.trim(),
                );
              },
              child: Text('إضافة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addUser({
    required String username,
    required String password,
    String? fullName,
    String? phone,
    required UserRole role,
    String? code,
    String? department,
    String? center,
    String? salary,
  }) async {
    try {
      // التحقق من عدم وجود نفس اسم المستخدم
      final existingUser = await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenantId)
          .collection('users')
          .where('username', isEqualTo: username)
          .get();

      if (existingUser.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'اسم المستخدم موجود بالفعل',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // تشفير كلمة المرور
      final passwordHash = CustomAuthService.hashPassword(password);

      // إضافة المستخدم
      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenantId)
          .collection('users')
          .add({
        'username': username,
        'passwordHash': passwordHash,
        'plainPassword': password, // حفظ كلمة المرور للعرض
        'fullName': fullName,
        'phone': phone,
        'role': role.value,
        'department': department,
        'center': center,
        'salary': salary,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': 'admin', // يمكن تعديله لاحقاً
        'firstSystemPermissions': defaultFirstSystemPermissions,
        'secondSystemPermissions': defaultSecondSystemPermissions,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إضافة المستخدم بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء إضافة المستخدم: $e',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEditUserDialog(TenantUser user) async {
    final fullNameController = TextEditingController(text: user.fullName);
    final phoneController = TextEditingController(text: user.phone);
    final codeController = TextEditingController(text: user.code);
    final departmentController = TextEditingController(text: user.department);
    final centerController = TextEditingController(text: user.center);
    final salaryController = TextEditingController(text: user.salary);
    UserRole selectedRole = user.role;
    bool isActive = user.isActive;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'تعديل بيانات: ${user.username}',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fullNameController,
                  decoration: InputDecoration(
                    labelText: 'الاسم الكامل',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  value: selectedRole,
                  decoration: InputDecoration(
                    labelText: 'الدور الوظيفي',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                  items: UserRole.values.map((role) {
                    return DropdownMenuItem(
                      value: role,
                      child: Text(role.arabicName, style: GoogleFonts.cairo()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedRole = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: departmentController,
                  decoration: InputDecoration(
                    labelText: 'القسم',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: centerController,
                  decoration: InputDecoration(
                    labelText: 'المركز',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: salaryController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'الراتب',
                    labelStyle: GoogleFonts.cairo(),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: Text('حساب نشط', style: GoogleFonts.cairo()),
                  value: isActive,
                  onChanged: (value) {
                    setDialogState(() => isActive = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _updateUser(
                  user.id,
                  fullName: fullNameController.text.trim(),
                  phone: phoneController.text.trim(),
                  role: selectedRole,
                  code: codeController.text.trim(),
                  department: departmentController.text.trim(),
                  center: centerController.text.trim(),
                  salary: salaryController.text.trim(),
                  isActive: isActive,
                );
              },
              child: Text('حفظ', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateUser(
    String userId, {
    String? fullName,
    String? phone,
    required UserRole role,
    String? code,
    String? department,
    String? center,
    String? salary,
    required bool isActive,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenantId)
          .collection('users')
          .doc(userId)
          .update({
        'fullName': fullName,
        'phone': phone,
        'role': role.value,
        'code': code,
        'department': department,
        'center': center,
        'salary': salary,
        'isActive': isActive,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحديث المستخدم بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ أثناء تحديث المستخدم: $e',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(TenantUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تأكيد الحذف', style: GoogleFonts.cairo()),
        content: Text(
          'هل أنت متأكد من حذف المستخدم "${user.username}"؟',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('حذف', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('tenants')
            .doc(widget.tenantId)
            .collection('users')
            .doc(user.id)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم حذف المستخدم بنجاح',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }

        _loadUsers();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'حدث خطأ أثناء حذف المستخدم: $e',
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showChangePasswordDialog(TenantUser user) async {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'تغيير كلمة المرور: ${user.username}',
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
              await _changePassword(user.id, passwordController.text);
            },
            child: Text('تغيير', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(String userId, String newPassword) async {
    try {
      final passwordHash = CustomAuthService.hashPassword(newPassword);

      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenantId)
          .collection('users')
          .doc(userId)
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
              'حدث خطأ أثناء تغيير كلمة المرور: $e',
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
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.people_alt, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Text(
              'إدارة الموظفين',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1a237e),
        foregroundColor: Colors.white,
        elevation: 4,
        actions: [
          Container(
            margin: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadUsers,
              tooltip: 'تحديث',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'بحث',
                labelStyle: GoogleFonts.cairo(),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // قائمة المستخدمين
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error, size: 64, color: Colors.red[300]),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: GoogleFonts.cairo(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadUsers,
                              icon: const Icon(Icons.refresh),
                              label: Text('إعادة المحاولة',
                                  style: GoogleFonts.cairo()),
                            ),
                          ],
                        ),
                      )
                    : _filteredUsers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline,
                                    size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  'لا يوجد مستخدمين',
                                  style: GoogleFonts.cairo(
                                    fontSize: 18,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredUsers.length,
                            padding: const EdgeInsets.all(16),
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: user.isActive
                                        ? Colors.green
                                        : Colors.grey,
                                    child: Text(
                                      user.username[0].toUpperCase(),
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  title: Text(
                                    user.fullName.isNotEmpty
                                        ? user.fullName
                                        : user.username,
                                    style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'المستخدم: ${user.username}',
                                        style: GoogleFonts.cairo(fontSize: 12),
                                      ),
                                      if (user.plainPassword != null &&
                                          user.plainPassword!.isNotEmpty)
                                        Row(
                                          children: [
                                            Text(
                                              'كلمة المرور: ',
                                              style: GoogleFonts.cairo(
                                                  fontSize: 12),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                user.plainPassword!,
                                                style: GoogleFonts.cairo(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      Text(
                                        'الدور: ${user.role.arabicName}',
                                        style: GoogleFonts.cairo(fontSize: 12),
                                      ),
                                      if (user.phone != null)
                                        Text(
                                          'الهاتف: ${user.phone}',
                                          style:
                                              GoogleFonts.cairo(fontSize: 12),
                                        ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    tooltip: 'حذف',
                                    onPressed: () => _deleteUser(user),
                                  ),
                                  onTap: () async {
                                    // فتح صفحة تفاصيل المستخدم
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => UserDetailsPage(
                                          user: user,
                                          tenantId: widget.tenantId,
                                        ),
                                      ),
                                    );
                                    // إعادة تحميل البيانات إذا تم التعديل
                                    if (result == true) {
                                      _loadUsers();
                                    }
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddUserDialog,
        icon: const Icon(Icons.add),
        label: Text('إضافة مستخدم', style: GoogleFonts.cairo()),
      ),
    );
  }
}
