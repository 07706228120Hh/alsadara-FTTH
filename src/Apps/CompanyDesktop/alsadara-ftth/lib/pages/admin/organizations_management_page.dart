/// صفحة إدارة الشركات والمؤسسات - Super Admin فقط
/// تسمح للمدير الأعلى بـ:
/// - عرض جميع الشركات
/// - إضافة شركة جديدة
/// - تعديل بيانات الشركات
/// - تفعيل/تعطيل الشركات
/// - إدارة مستخدمي كل شركة
/// - تعيين صلاحيات المستخدمين
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/organizations_service.dart';
import '../../services/firestore_permissions_service.dart';
import '../../citizen_portal/citizen_portal.dart';
import '../login/premium_login_page.dart';

class OrganizationsManagementPage extends StatefulWidget {
  const OrganizationsManagementPage({super.key});

  @override
  State<OrganizationsManagementPage> createState() =>
      _OrganizationsManagementPageState();
}

class _OrganizationsManagementPageState
    extends State<OrganizationsManagementPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _currentOrgId;
  bool _isLoading = true;
  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _orgUsers = [];
  Map<String, dynamic>? _selectedOrg;

  // Citizen Portal linking state
  String? _linkedCompanyId;
  bool _isCheckingLinked = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkPermissionsAndLoadData();
    _loadLinkedCompany();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// التحقق من صلاحيات Super Admin
  Future<void> _checkPermissionsAndLoadData() async {
    setState(() => _isLoading = true);

    try {
      final role = await FirebaseAuthService.getUserRole();

      if (role != 'super_admin') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ ليس لديك صلاحية الوصول لهذه الصفحة'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const PremiumLoginPage()),
        );
        return;
      }

      await _loadOrganizations();
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من الصلاحيات');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const PremiumLoginPage()),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// تحميل قائمة الشركات
  Future<void> _loadOrganizations() async {
    try {
      final orgs = await OrganizationsService.getAllOrganizations();
      if (mounted) {
        setState(() {
          _organizations = orgs;
          if (_organizations.isNotEmpty && _currentOrgId == null) {
            _currentOrgId = _organizations[0]['id'];
            _selectedOrg = _organizations[0];
            _loadOrganizationUsers(_currentOrgId!);
          }
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل الشركات');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// تحميل مستخدمي شركة معينة
  Future<void> _loadOrganizationUsers(String orgId) async {
    try {
      final users = await OrganizationsService.getOrganizationUsers(orgId);
      if (mounted) {
        setState(() => _orgUsers = users);
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل المستخدمين');
    }
  }

  /// تحميل معلومات الشركة المرتبطة بنظام المواطن
  Future<void> _loadLinkedCompany() async {
    setState(() => _isCheckingLinked = true);
    try {
      final linkedCompany = await CitizenPortalHelper.getLinkedCompany();
      if (mounted) {
        setState(() {
          _linkedCompanyId = linkedCompany?.id;
          _isCheckingLinked = false;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل الشركة المرتبطة');
      if (mounted) {
        setState(() => _isCheckingLinked = false);
      }
    }
  }

  /// ربط شركة بنظام المواطن
  Future<void> _linkToCitizenPortal(String orgId, String orgName) async {
    // تأكيد الربط
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تأكيد الربط',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Text(
          'هل أنت متأكد من ربط شركة "$orgName" بنظام المواطن؟\n\n'
          'ملاحظة: سيتم إلغاء ربط أي شركة أخرى تلقائياً.',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('تأكيد الربط', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCheckingLinked = true);
    try {
      // استدعاء API للربط
      await CompanyApiService.linkToCitizenPortal(orgId);

      // تحديث حالة الربط
      await _loadLinkedCompany();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم ربط شركة "$orgName" بنظام المواطن بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في ربط الشركة');
      if (mounted) {
        setState(() => _isCheckingLinked = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// إلغاء ربط شركة من نظام المواطن
  Future<void> _unlinkFromCitizenPortal(String orgId, String orgName) async {
    // تأكيد الإلغاء
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تأكيد إلغاء الربط',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Text(
          'هل أنت متأكد من إلغاء ربط شركة "$orgName" من نظام المواطن؟\n\n'
          'سيتم إخفاء بوابة المواطن من لوحة تحكم الشركة.',
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
            child: Text('تأكيد الإلغاء', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCheckingLinked = true);
    try {
      // استدعاء API لإلغاء الربط
      await CompanyApiService.unlinkFromCitizenPortal(orgId);

      // تحديث حالة الربط
      await _loadLinkedCompany();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم إلغاء ربط شركة "$orgName" من نظام المواطن'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في إلغاء ربط الشركة');
      if (mounted) {
        setState(() => _isCheckingLinked = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// حوار إضافة شركة جديدة
  Future<void> _showAddOrganizationDialog() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('إضافة شركة جديدة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'اسم الشركة *',
                  labelStyle: GoogleFonts.cairo(),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.trim().isEmpty ?? true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'الوصف',
                  labelStyle: GoogleFonts.cairo(),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
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
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                await _createOrganization(
                  nameController.text.trim(),
                  descController.text.trim(),
                );
              }
            },
            child: Text('إضافة', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  /// إنشاء شركة جديدة
  Future<void> _createOrganization(String name, String description) async {
    try {
      final orgId = await OrganizationsService.createOrganization(
        name: name,
        description: description,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم إنشاء الشركة: $name'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadOrganizations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// حوار تعديل الشركة
  Future<void> _showEditOrganizationDialog(Map<String, dynamic> org) async {
    final nameController = TextEditingController(text: org['name']);
    final descController =
        TextEditingController(text: org['description'] ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل بيانات الشركة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'اسم الشركة *',
                  labelStyle: GoogleFonts.cairo(),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.trim().isEmpty ?? true ? 'مطلوب' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'الوصف',
                  labelStyle: GoogleFonts.cairo(),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
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
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);
                await _updateOrganization(
                  org['id'],
                  nameController.text.trim(),
                  descController.text.trim(),
                );
              }
            },
            child: Text('حفظ', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  /// تحديث بيانات الشركة
  Future<void> _updateOrganization(
      String orgId, String name, String description) async {
    try {
      await OrganizationsService.updateOrganization(orgId, {
        'name': name,
        'description': description,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تحديث بيانات الشركة'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadOrganizations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// تبديل حالة الشركة (تفعيل/تعطيل)
  Future<void> _toggleOrganizationStatus(
      String orgId, bool currentStatus) async {
    try {
      await OrganizationsService.toggleOrganizationStatus(
          orgId, !currentStatus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(currentStatus ? '✅ تم تعطيل الشركة' : '✅ تم تفعيل الشركة'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadOrganizations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// حوار إضافة مستخدم للشركة
  Future<void> _showAddUserDialog(String orgId) async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final displayNameController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String selectedRole = 'user';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('إضافة مستخدم جديد',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: usernameController,
                    decoration: InputDecoration(
                      labelText: 'اسم المستخدم *',
                      labelStyle: GoogleFonts.cairo(),
                      border: const OutlineInputBorder(),
                      hintText: 'مثال: ahmed123',
                    ),
                    validator: (value) =>
                        value?.trim().isEmpty ?? true ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور *',
                      labelStyle: GoogleFonts.cairo(),
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) => (value?.length ?? 0) < 6
                        ? 'يجب أن تكون 6 أحرف على الأقل'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: displayNameController,
                    decoration: InputDecoration(
                      labelText: 'الاسم الكامل *',
                      labelStyle: GoogleFonts.cairo(),
                      border: const OutlineInputBorder(),
                      hintText: 'مثال: أحمد محمد',
                    ),
                    validator: (value) =>
                        value?.trim().isEmpty ?? true ? 'مطلوب' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: InputDecoration(
                      labelText: 'الدور الوظيفي',
                      labelStyle: GoogleFonts.cairo(),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'admin',
                          child: Text('مدير', style: GoogleFonts.cairo())),
                      DropdownMenuItem(
                          value: 'user',
                          child: Text('مستخدم', style: GoogleFonts.cairo())),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedRole = value!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context);
                  await _addUserToOrganization(
                    orgId,
                    usernameController.text.trim(),
                    passwordController.text,
                    displayNameController.text.trim(),
                    selectedRole,
                  );
                }
              },
              child: Text('إضافة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  /// إضافة مستخدم للشركة
  Future<void> _addUserToOrganization(
    String orgId,
    String username,
    String password,
    String displayName,
    String role,
  ) async {
    try {
      await OrganizationsService.addUserToOrganization(
        organizationId: orgId,
        username: username,
        password: password,
        displayName: displayName,
        role: role,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم إضافة المستخدم: $username'),
            backgroundColor: Colors.green,
          ),
        );
        await _loadOrganizationUsers(orgId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// حوار إدارة صلاحيات المستخدم
  Future<void> _showUserPermissionsDialog(
    String userId,
    String username,
    String orgId,
  ) async {
    final permissions =
        await FirestorePermissionsService.getPermissionsFromFirestore(
      organizationId: orgId,
      userId: userId,
    );

    final Map<String, bool> editablePermissions = Map.from(permissions);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'صلاحيات: $username',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            height: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPermissionSection(
                    'إدارة النظام',
                    [
                      'users',
                      'accounts',
                      'zones',
                      'export',
                    ],
                    editablePermissions,
                    setDialogState,
                  ),
                  const Divider(height: 24),
                  _buildPermissionSection(
                    'العمليات',
                    [
                      'subscriptions',
                      'tasks',
                      'agents',
                      'technicians',
                    ],
                    editablePermissions,
                    setDialogState,
                  ),
                  const Divider(height: 24),
                  _buildPermissionSection(
                    'المالية',
                    [
                      'wallet_balance',
                      'transactions',
                      'plans_bundles',
                    ],
                    editablePermissions,
                    setDialogState,
                  ),
                  const Divider(height: 24),
                  _buildPermissionSection(
                    'التقارير والبحث',
                    [
                      'quick_search',
                      'expiring_soon',
                      'notifications',
                      'audit_logs',
                    ],
                    editablePermissions,
                    setDialogState,
                  ),
                  const Divider(height: 24),
                  _buildPermissionSection(
                    'WhatsApp',
                    [
                      'whatsapp',
                      'whatsapp_business_api',
                      'whatsapp_bulk_sender',
                    ],
                    editablePermissions,
                    setDialogState,
                  ),
                ],
              ),
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
                await _updateUserPermissions(
                    orgId, userId, editablePermissions);
              },
              child: Text('حفظ الصلاحيات', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء قسم صلاحيات
  Widget _buildPermissionSection(
    String title,
    List<String> permissionKeys,
    Map<String, bool> permissions,
    StateSetter setDialogState,
  ) {
    final Map<String, String> permissionNames = {
      'users': 'إدارة المستخدمين',
      'accounts': 'إدارة الحسابات',
      'zones': 'إدارة المناطق',
      'export': 'تصدير البيانات',
      'subscriptions': 'الاشتراكات',
      'tasks': 'المهام',
      'agents': 'الوكلاء',
      'technicians': 'فني التوصيل',
      'wallet_balance': 'رصيد المحفظة',
      'transactions': 'التحويلات',
      'plans_bundles': 'الباقات',
      'quick_search': 'البحث السريع',
      'expiring_soon': 'المنتهية قريباً',
      'notifications': 'الإشعارات',
      'audit_logs': 'سجل التدقيق',
      'whatsapp': 'رسائل WhatsApp',
      'whatsapp_business_api': 'WhatsApp API',
      'whatsapp_bulk_sender': 'الإرسال الجماعي',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.blue[700],
          ),
        ),
        const SizedBox(height: 8),
        ...permissionKeys.map((key) => CheckboxListTile(
              title: Text(
                permissionNames[key] ?? key,
                style: GoogleFonts.cairo(fontSize: 14),
              ),
              value: permissions[key] ?? false,
              onChanged: (value) {
                setDialogState(() => permissions[key] = value ?? false);
              },
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            )),
      ],
    );
  }

  /// تحديث صلاحيات المستخدم
  Future<void> _updateUserPermissions(
    String orgId,
    String userId,
    Map<String, bool> permissions,
  ) async {
    try {
      await FirestorePermissionsService.updateUserPermissions(
        organizationId: orgId,
        userId: userId,
        permissions: permissions,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم تحديث صلاحيات المستخدم'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('إدارة الشركات', style: GoogleFonts.cairo()),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('إدارة الشركات والمؤسسات',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrganizations,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuthService.signOut();
              if (!mounted) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (context) => const PremiumLoginPage()),
              );
            },
            tooltip: 'تسجيل الخروج',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(child: Text('الشركات', style: GoogleFonts.cairo())),
            Tab(child: Text('المستخدمين', style: GoogleFonts.cairo())),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOrganizationsTab(),
          _buildUsersTab(),
        ],
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddOrganizationDialog,
              icon: const Icon(Icons.add),
              label: Text('إضافة شركة', style: GoogleFonts.cairo()),
            )
          : FloatingActionButton.extended(
              onPressed: _currentOrgId != null
                  ? () => _showAddUserDialog(_currentOrgId!)
                  : null,
              icon: const Icon(Icons.person_add),
              label: Text('إضافة مستخدم', style: GoogleFonts.cairo()),
            ),
    );
  }

  /// تبويب الشركات
  Widget _buildOrganizationsTab() {
    if (_organizations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business, size: 100, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'لا توجد شركات',
              style: GoogleFonts.cairo(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط على زر "إضافة شركة" للبدء',
              style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _organizations.length,
      itemBuilder: (context, index) {
        final org = _organizations[index];
        final isActive = org['isActive'] ?? true;
        final stats = org['stats'] as Map<String, dynamic>?;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: isActive ? Colors.green : Colors.grey,
              child: Icon(
                isActive ? Icons.business : Icons.business_center_outlined,
                color: Colors.white,
              ),
            ),
            title: Text(
              org['name'],
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (org['description']?.isNotEmpty ?? false)
                  Text(org['description'],
                      style: GoogleFonts.cairo(fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  isActive ? '🟢 نشطة' : '🔴 معطلة',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: isActive ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  child: Text('تعديل', style: GoogleFonts.cairo()),
                  onTap: () => Future.delayed(
                    Duration.zero,
                    () => _showEditOrganizationDialog(org),
                  ),
                ),
                PopupMenuItem(
                  child: Text(
                    isActive ? 'تعطيل' : 'تفعيل',
                    style: GoogleFonts.cairo(),
                  ),
                  onTap: () => _toggleOrganizationStatus(org['id'], isActive),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Citizen Portal Badge and Actions
                    if (_linkedCompanyId == org['id'])
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[300]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.verified,
                                color: Colors.green[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '✅ مرتبطة بنظام المواطن',
                                style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Citizen Portal Link/Unlink Button
                    if (isActive && !_isCheckingLinked)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: double.infinity,
                        child: _linkedCompanyId == org['id']
                            ? OutlinedButton.icon(
                                onPressed: () => _unlinkFromCitizenPortal(
                                    org['id'], org['name']),
                                icon: const Icon(Icons.link_off),
                                label: Text('إلغاء الربط بنظام المواطن',
                                    style: GoogleFonts.cairo()),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: () => _linkToCitizenPortal(
                                    org['id'], org['name']),
                                icon: const Icon(Icons.link),
                                label: Text('ربط بنظام المواطن',
                                    style: GoogleFonts.cairo()),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                      ),

                    if (_isCheckingLinked)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: CircularProgressIndicator(),
                        ),
                      ),

                    const Divider(),

                    Text('📊 الإحصائيات:',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatCard('المستخدمين', stats?['usersCount'] ?? 0,
                            Icons.people),
                        _buildStatCard(
                            'المهام', stats?['tasksCount'] ?? 0, Icons.task),
                        _buildStatCard(
                            'الاشتراكات',
                            stats?['subscriptionsCount'] ?? 0,
                            Icons.subscriptions),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _currentOrgId = org['id'];
                          _selectedOrg = org;
                          _tabController.animateTo(1);
                        });
                        _loadOrganizationUsers(org['id']);
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: Text('عرض المستخدمين', style: GoogleFonts.cairo()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// كارت إحصائية صغيرة
  Widget _buildStatCard(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 30, color: Colors.blue[700]),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: GoogleFonts.cairo(fontSize: 12)),
      ],
    );
  }

  /// تبويب المستخدمين
  Widget _buildUsersTab() {
    if (_currentOrgId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 100, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'الرجاء اختيار شركة من التبويب الأول',
              style: GoogleFonts.cairo(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue[50],
          child: Row(
            children: [
              const Icon(Icons.business, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'مستخدمو: ${_selectedOrg?['name'] ?? 'غير محدد'}',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => _loadOrganizationUsers(_currentOrgId!),
              ),
            ],
          ),
        ),
        Expanded(
          child: _orgUsers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_outline,
                          size: 100, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'لا يوجد مستخدمين',
                        style:
                            GoogleFonts.cairo(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orgUsers.length,
                  itemBuilder: (context, index) {
                    final user = _orgUsers[index];
                    final isActive = user['isActive'] ?? true;
                    final role = user['role'] ?? 'user';

                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive ? Colors.blue : Colors.grey,
                          child: Text(
                            user['displayName']?[0]?.toUpperCase() ?? '?',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          user['displayName'] ?? 'بدون اسم',
                          style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'اسم المستخدم: ${user['username']}',
                              style: GoogleFonts.cairo(fontSize: 12),
                            ),
                            Text(
                              'الدور: ${role == 'admin' ? 'مدير' : 'مستخدم'}',
                              style: GoogleFonts.cairo(fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.security),
                          onPressed: () => _showUserPermissionsDialog(
                            user['id'],
                            user['username'],
                            _currentOrgId!,
                          ),
                          tooltip: 'إدارة الصلاحيات',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
