/// صفحة قائمة الشركات
/// تعرض جميع الشركات مع إمكانية البحث والفلترة
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../multi_tenant.dart';
import '../../citizen_portal/citizen_portal.dart';
import 'add_company_page.dart';
import 'edit_company_page.dart';
import '../home_page.dart';
import '../../permissions/permissions.dart';

class CompaniesListPage extends StatefulWidget {
  const CompaniesListPage({super.key});

  @override
  State<CompaniesListPage> createState() => _CompaniesListPageState();
}

class _CompaniesListPageState extends State<CompaniesListPage> {
  final CustomAuthService _authService = CustomAuthService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  SubscriptionStatus? _statusFilter;

  // Citizen Portal linking state
  String? _linkedCompanyId;
  bool _isLoadingLinked = false;

  @override
  void initState() {
    super.initState();
    _loadLinkedCompany();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// تحميل معلومات الشركة المرتبطة بنظام المواطن
  Future<void> _loadLinkedCompany() async {
    setState(() => _isLoadingLinked = true);
    try {
      final linkedCompany = await CitizenPortalHelper.getLinkedCompany();
      if (mounted) {
        setState(() {
          _linkedCompanyId = linkedCompany?.id;
          _isLoadingLinked = false;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل الشركة المرتبطة: $e');
      if (mounted) {
        setState(() => _isLoadingLinked = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // شريط البحث والفلترة
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // البحث
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'البحث بالاسم أو الكود...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),

              // فلتر الحالة
              PopupMenuButton<SubscriptionStatus?>(
                icon: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_list),
                      if (_statusFilter != null) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _getStatusColor(_statusFilter!),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                onSelected: (value) {
                  setState(() {
                    _statusFilter = value;
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: null, child: Text('جميع الحالات')),
                  const PopupMenuDivider(),
                  _buildFilterMenuItem(
                    SubscriptionStatus.active,
                    'نشط',
                    Colors.green,
                  ),
                  _buildFilterMenuItem(
                    SubscriptionStatus.warning,
                    'تحذير',
                    Colors.orange,
                  ),
                  _buildFilterMenuItem(
                    SubscriptionStatus.critical,
                    'حرج',
                    Colors.deepOrange,
                  ),
                  _buildFilterMenuItem(
                    SubscriptionStatus.expired,
                    'منتهي',
                    Colors.red,
                  ),
                  _buildFilterMenuItem(
                    SubscriptionStatus.suspended,
                    'معلق',
                    Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),

        // قائمة الشركات
        Expanded(
          child: StreamBuilder<List<Tenant>>(
            stream: _authService.getAllTenants(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text('خطأ: ${snapshot.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                );
              }

              var tenants = snapshot.data ?? [];

              // تطبيق البحث
              if (_searchQuery.isNotEmpty) {
                tenants = tenants.where((t) {
                  return t.name.toLowerCase().contains(_searchQuery) ||
                      t.code.toLowerCase().contains(_searchQuery);
                }).toList();
              }

              // تطبيق الفلتر
              if (_statusFilter != null) {
                tenants =
                    tenants.where((t) => t.status == _statusFilter).toList();
              }

              if (tenants.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.business_outlined,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty || _statusFilter != null
                            ? 'لا توجد نتائج'
                            : 'لا توجد شركات',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_searchQuery.isEmpty && _statusFilter == null)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AddCompanyPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة شركة'),
                        ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tenants.length,
                itemBuilder: (context, index) {
                  final tenant = tenants[index];
                  return _CompanyCard(
                    tenant: tenant,
                    linkedCompanyId: _linkedCompanyId,
                    onTap: () => _showCompanyOptions(context, tenant),
                    onEnterAsCompany: () => _enterAsCompany(context, tenant),
                    onEdit: () => _editCompany(context, tenant),
                    onDelete: () => _deleteCompany(context, tenant),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// الدخول للشركة كمدير
  void _enterAsCompany(BuildContext context, Tenant tenant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.login, color: Color(0xFF1a237e)),
            SizedBox(width: 8),
            Text('الدخول للشركة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد الدخول لشركة "${tenant.name}" كمدير؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ستحصل على جميع صلاحيات المدير',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.login),
            label: const Text('دخول'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1a237e),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      // V2: منح جميع الصلاحيات للسوبر أدمن
      PermissionManager.instance.grantAll([
        'attendance',
        'agent',
        'tasks',
        'zones',
        'ai_search',
        'users_management',
        'reports',
        'settings',
        'dashboard',
        'tickets',
        'notifications',
        'maintenance',
        'users',
        'subscriptions',
        'accounts',
        'account_records',
        'export',
        'technicians',
        'transactions',
        'local_storage',
        'sadara_portal',
        'accounting',
        'diagnostics',
      ]);
      final fullPermissions = PermissionManager.instance.buildPageAccess();

      // الانتقال للصفحة الرئيسية كمدير
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => HomePage(
            username: 'Super Admin',
            permissions: 'مدير',
            department: tenant.name,
            center: tenant.code,
            salary: '0',
            pageAccess: fullPermissions,
            tenantId: tenant.id,
            tenantCode: tenant.code,
            isSuperAdminMode: true, // وضع مدير النظام
          ),
        ),
        (route) => false,
      );
    }
  }

  /// عرض خيارات الشركة
  void _showCompanyOptions(BuildContext context, Tenant tenant) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tenant.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'كود: ${tenant.code}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1a237e),
                child: Icon(Icons.login, color: Colors.white),
              ),
              title: const Text('الدخول للشركة'),
              subtitle: const Text('الدخول كمدير بصلاحيات كاملة'),
              onTap: () {
                Navigator.pop(context);
                _enterAsCompany(context, tenant);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.edit, color: Colors.white),
              ),
              title: const Text('تعديل الشركة'),
              subtitle: const Text('تعديل بيانات الشركة والاشتراك'),
              onTap: () {
                Navigator.pop(context);
                _editCompany(context, tenant);
              },
            ),
            if (tenant.isActive)
              tenant.isLinkedToCitizenPortal
                  ? ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.deepOrange,
                        child: Icon(Icons.link_off, color: Colors.white),
                      ),
                      title: const Text('إلغاء الربط بنظام المواطن'),
                      subtitle: const Text('إزالة الارتباط بنظام المواطن'),
                      trailing: const Icon(Icons.verified, color: Colors.green),
                      onTap: () {
                        Navigator.pop(context);
                        _unlinkFromCitizenPortal(context, tenant);
                      },
                    )
                  : ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.link, color: Colors.white),
                      ),
                      title: const Text('ربط بنظام المواطن'),
                      subtitle: const Text('السماح بإدارة نظام المواطن'),
                      onTap: () {
                        Navigator.pop(context);
                        _linkToCitizenPortal(context, tenant);
                      },
                    ),
            if (tenant.isActive)
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.pause, color: Colors.white),
                ),
                title: const Text('تعليق الشركة'),
                subtitle: const Text('إيقاف مؤقت للشركة'),
                onTap: () {
                  Navigator.pop(context);
                  _suspendCompany(context, tenant);
                },
              )
            else
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(Icons.play_arrow, color: Colors.white),
                ),
                title: const Text('تفعيل الشركة'),
                subtitle: const Text('إعادة تفعيل الشركة'),
                onTap: () {
                  Navigator.pop(context);
                  _reactivateCompany(context, tenant);
                },
              ),
            // إدارة مدير الشركة
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.indigo.shade700,
                child:
                    const Icon(Icons.admin_panel_settings, color: Colors.white),
              ),
              title: const Text('إدارة مدير الشركة'),
              subtitle: Text(
                tenant.adminUsername != null
                    ? 'المدير: ${tenant.adminFullName ?? tenant.adminUsername}'
                    : 'لم يتم تعيين مدير',
              ),
              onTap: () {
                Navigator.pop(context);
                _manageCompanyAdmin(context, tenant);
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.red,
                child: Icon(Icons.delete, color: Colors.white),
              ),
              title: const Text('حذف الشركة'),
              subtitle: const Text('حذف الشركة وجميع بياناتها'),
              onTap: () {
                Navigator.pop(context);
                _deleteCompany(context, tenant);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// تعديل الشركة
  void _editCompany(BuildContext context, Tenant tenant) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditCompanyPage(tenant: tenant),
      ),
    );
  }

  /// تعليق الشركة
  void _suspendCompany(BuildContext context, Tenant tenant) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.pause_circle, color: Colors.orange),
            SizedBox(width: 8),
            Text('تعليق الشركة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('هل تريد تعليق شركة "${tenant.name}"؟'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'سبب التعليق',
                hintText: 'أدخل سبب التعليق (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('تعليق'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final tenantService = TenantService();
      final success = await tenantService.suspendTenant(
        tenant.id,
        reasonController.text.trim().isEmpty
            ? 'تم التعليق بواسطة المدير'
            : reasonController.text.trim(),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'تم تعليق الشركة بنجاح' : 'فشل تعليق الشركة',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  /// إعادة تفعيل الشركة
  void _reactivateCompany(BuildContext context, Tenant tenant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.play_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('تفعيل الشركة'),
          ],
        ),
        content: Text('هل تريد إعادة تفعيل شركة "${tenant.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final tenantService = TenantService();
      final success = await tenantService.reactivateTenant(tenant.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? 'تم تفعيل الشركة بنجاح' : 'فشل تفعيل الشركة',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  /// حذف الشركة
  void _deleteCompany(BuildContext context, Tenant tenant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('حذف الشركة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد حذف شركة "${tenant.name}"؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم حذف جميع بيانات الشركة والمستخدمين!',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final tenantService = TenantService();
      final result = await tenantService.deleteTenant(tenant.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.success
                  ? 'تم حذف الشركة بنجاح (${result.deletedUsers} مستخدم)'
                  : 'فشل حذف الشركة: ${result.errorMessage}',
            ),
            backgroundColor: result.success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  /// ربط شركة بنظام المواطن
  Future<void> _linkToCitizenPortal(BuildContext context, Tenant tenant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: Colors.teal),
            SizedBox(width: 8),
            Text('ربط بنظام المواطن'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد ربط شركة "${tenant.name}" بنظام المواطن؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ملاحظة: سيتم إلغاء ربط أي شركة أخرى تلقائياً',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد الربط'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      setState(() => _isLoadingLinked = true);
      try {
        // إلغاء ربط أي شركة أخرى أولاً
        final firestore = FirebaseFirestore.instance;
        final linkedTenants = await firestore
            .collection('tenants')
            .where('isLinkedToCitizenPortal', isEqualTo: true)
            .get();

        for (final doc in linkedTenants.docs) {
          await doc.reference.update({
            'isLinkedToCitizenPortal': false,
            'linkedToCitizenPortalAt': null,
          });
        }

        // ربط الشركة الجديدة
        await firestore.collection('tenants').doc(tenant.id).update({
          'isLinkedToCitizenPortal': true,
          'linkedToCitizenPortalAt': FieldValue.serverTimestamp(),
        });

        setState(() {
          _linkedCompanyId = tenant.id;
          _isLoadingLinked = false;
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('✅ تم ربط شركة "${tenant.name}" بنظام المواطن بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ خطأ في ربط الشركة: $e');
        if (context.mounted) {
          setState(() => _isLoadingLinked = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ خطأ: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  /// إلغاء ربط شركة من نظام المواطن
  Future<void> _unlinkFromCitizenPortal(
      BuildContext context, Tenant tenant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link_off, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('إلغاء الربط بنظام المواطن'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد إلغاء ربط شركة "${tenant.name}" من نظام المواطن؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_outlined, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم إخفاء بوابة المواطن من لوحة التحكم',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      setState(() => _isLoadingLinked = true);
      try {
        final firestore = FirebaseFirestore.instance;
        await firestore.collection('tenants').doc(tenant.id).update({
          'isLinkedToCitizenPortal': false,
          'linkedToCitizenPortalAt': null,
        });

        setState(() {
          _linkedCompanyId = null;
          _isLoadingLinked = false;
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('✅ تم إلغاء ربط شركة "${tenant.name}" من نظام المواطن'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ خطأ في إلغاء ربط الشركة: $e');
        if (context.mounted) {
          setState(() => _isLoadingLinked = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ خطأ: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  /// إدارة مدير الشركة (عرض/تعديل بيانات الدخول)
  Future<void> _manageCompanyAdmin(BuildContext context, Tenant tenant) async {
    final fullNameController =
        TextEditingController(text: tenant.adminFullName ?? '');
    final usernameController =
        TextEditingController(text: tenant.adminUsername ?? '');
    final passwordController =
        TextEditingController(text: tenant.adminPassword ?? '');
    bool showPassword = false;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.admin_panel_settings, color: Colors.indigo.shade700),
              const SizedBox(width: 8),
              const Text('إدارة مدير الشركة'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // اسم الشركة
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.business, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        tenant.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                // الاسم الكامل
                TextField(
                  controller: fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل للمدير',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // اسم المستخدم
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    prefixIcon: Icon(Icons.account_circle),
                    border: OutlineInputBorder(),
                    hintText: 'admin',
                  ),
                ),
                const SizedBox(height: 12),
                // كلمة المرور
                TextField(
                  controller: passwordController,
                  obscureText: !showPassword,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => showPassword = !showPassword),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ملاحظة
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'هذه البيانات مرئية فقط لمدير النظام',
                          style: TextStyle(color: Colors.blue, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, {
                'fullName': fullNameController.text.trim(),
                'username': usernameController.text.trim(),
                'password': passwordController.text,
              }),
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null && context.mounted) {
      try {
        final firestore = FirebaseFirestore.instance;
        final username = result['username']!;
        final password = result['password']!;
        final fullName = result['fullName']!;

        if (username.isEmpty || password.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ يجب إدخال اسم المستخدم وكلمة المرور'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        // تشفير كلمة المرور
        final hashedPassword = CustomAuthService.hashPassword(password);

        // البحث عن مدير موجود
        final existingAdmin = await firestore
            .collection('tenants')
            .doc(tenant.id)
            .collection('users')
            .where('role', isEqualTo: 'admin')
            .limit(1)
            .get();

        if (existingAdmin.docs.isNotEmpty) {
          // تحديث المدير الموجود
          await existingAdmin.docs.first.reference.update({
            'username': username,
            'passwordHash': hashedPassword,
            'plainPassword': password,
            'fullName': fullName,
          });
        } else {
          // إنشاء مدير جديد
          await firestore
              .collection('tenants')
              .doc(tenant.id)
              .collection('users')
              .add({
            'username': username,
            'passwordHash': hashedPassword,
            'plainPassword': password,
            'fullName': fullName,
            'role': 'admin',
            'isActive': true,
            'firstSystemPermissions': {},
            'secondSystemPermissions': {},
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': 'super_admin',
          });
        }

        // تحديث البيانات المرجعية في الشركة
        await firestore.collection('tenants').doc(tenant.id).update({
          'adminFullName': fullName,
          'adminUsername': username,
          'adminPassword': password,
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('✅ تم حفظ بيانات المدير بنجاح'),
                  const SizedBox(height: 4),
                  Text(
                    'يمكن للمدير تسجيل الدخول باستخدام:\nكود الشركة: ${tenant.code}\nاسم المستخدم: $username',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ خطأ: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  PopupMenuItem<SubscriptionStatus> _buildFilterMenuItem(
    SubscriptionStatus status,
    String label,
    Color color,
  ) {
    return PopupMenuItem(
      value: status,
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Color _getStatusColor(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.active:
        return Colors.green;
      case SubscriptionStatus.warning:
        return Colors.orange;
      case SubscriptionStatus.critical:
        return Colors.deepOrange;
      case SubscriptionStatus.expired:
        return Colors.red;
      case SubscriptionStatus.suspended:
        return Colors.grey;
    }
  }
}

/// بطاقة الشركة
class _CompanyCard extends StatelessWidget {
  final Tenant tenant;
  final VoidCallback onTap;
  final VoidCallback onEnterAsCompany;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String? linkedCompanyId;

  const _CompanyCard({
    required this.tenant,
    required this.onTap,
    required this.onEnterAsCompany,
    required this.onEdit,
    required this.onDelete,
    this.linkedCompanyId,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _getStatusColor(tenant.status).withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // شريط الربط بنظام المواطن
              if (tenant.isLinkedToCitizenPortal)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.teal.shade600, Colors.teal.shade400],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.teal.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.verified,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'مرتبطة بنظام المواطن',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              // الصف الأول: الاسم والحالة
              Row(
                children: [
                  // الشعار/الحرف الأول
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: _getStatusColor(tenant.status),
                    child: tenant.logo != null
                        ? ClipOval(
                            child: Image.network(
                              tenant.logo!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Text(
                                tenant.name.isNotEmpty ? tenant.name[0] : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                          )
                        : Text(
                            tenant.name.isNotEmpty ? tenant.name[0] : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),

                  // الاسم والكود
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tenant.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'كود: ${tenant.code}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // شريحة الحالة
                  _buildStatusChip(tenant.status),
                ],
              ),
              const SizedBox(height: 16),

              // الصف الثاني: معلومات الاشتراك
              Row(
                children: [
                  _InfoItem(
                    icon: Icons.calendar_today,
                    label: 'تاريخ الانتهاء',
                    value: dateFormat.format(tenant.subscriptionEnd),
                    color: tenant.isExpired ? Colors.red : null,
                  ),
                  const SizedBox(width: 24),
                  _InfoItem(
                    icon: Icons.timer,
                    label: 'المتبقي',
                    value: tenant.isExpired
                        ? 'منتهي'
                        : '${tenant.daysRemaining} يوم',
                    color: tenant.daysRemaining <= 7
                        ? Colors.red
                        : tenant.daysRemaining <= 30
                            ? Colors.orange
                            : Colors.green,
                  ),
                  const SizedBox(width: 24),
                  _InfoItem(
                    icon: Icons.card_membership,
                    label: 'الباقة',
                    value: _getPlanName(tenant.subscriptionPlan),
                  ),
                ],
              ),

              // رسالة التعليق إن وجدت
              if (!tenant.isActive && tenant.suspensionReason != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سبب التعليق: ${tenant.suspensionReason}',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // معلومات مدير الشركة
              if (tenant.adminUsername != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.admin_panel_settings,
                            color: Colors.indigo.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'معلومات مدير الشركة',
                            style: TextStyle(
                              color: Colors.indigo.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _AdminInfoItem(
                              icon: Icons.person,
                              label: 'الاسم',
                              value: tenant.adminFullName ?? 'غير محدد',
                            ),
                          ),
                          Expanded(
                            child: _AdminInfoItem(
                              icon: Icons.account_circle,
                              label: 'اسم المستخدم',
                              value: tenant.adminUsername!,
                              canCopy: true,
                            ),
                          ),
                          Expanded(
                            child: _AdminInfoItem(
                              icon: Icons.lock,
                              label: 'كلمة المرور',
                              value: tenant.adminPassword ?? '••••••',
                              isPassword: true,
                              canCopy: tenant.adminPassword != null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // أزرار الإجراءات
              const SizedBox(height: 16),
              Row(
                children: [
                  // زر الدخول للشركة
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onEnterAsCompany,
                      icon: const Icon(Icons.login, size: 18),
                      label: const Text('الدخول للشركة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1a237e),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // زر التعديل
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                    color: Colors.blue,
                    tooltip: 'تعديل',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue.shade50,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // زر الحذف
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete),
                    color: Colors.red,
                    tooltip: 'حذف',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.active:
        return Colors.green;
      case SubscriptionStatus.warning:
        return Colors.orange;
      case SubscriptionStatus.critical:
        return Colors.deepOrange;
      case SubscriptionStatus.expired:
        return Colors.red;
      case SubscriptionStatus.suspended:
        return Colors.grey;
    }
  }

  Widget _buildStatusChip(SubscriptionStatus status) {
    String label;
    Color color;
    IconData icon;

    switch (status) {
      case SubscriptionStatus.active:
        label = 'نشط';
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      case SubscriptionStatus.warning:
        label = 'تحذير';
        color = Colors.orange;
        icon = Icons.schedule;
        break;
      case SubscriptionStatus.critical:
        label = 'حرج';
        color = Colors.deepOrange;
        icon = Icons.warning;
        break;
      case SubscriptionStatus.expired:
        label = 'منتهي';
        color = Colors.red;
        icon = Icons.cancel;
        break;
      case SubscriptionStatus.suspended:
        label = 'معلق';
        color = Colors.grey;
        icon = Icons.pause_circle;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _getPlanName(String plan) {
    switch (plan) {
      case 'monthly':
        return 'شهري';
      case 'quarterly':
        return 'ربع سنوي';
      case 'yearly':
        return 'سنوي';
      default:
        return plan;
    }
  }
}

/// عنصر معلومات صغير
class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

/// عنصر معلومات المدير مع إمكانية النسخ وإظهار/إخفاء كلمة المرور
class _AdminInfoItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isPassword;
  final bool canCopy;

  const _AdminInfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.isPassword = false,
    this.canCopy = false,
  });

  @override
  State<_AdminInfoItem> createState() => _AdminInfoItemState();
}

class _AdminInfoItemState extends State<_AdminInfoItem> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(widget.icon, size: 14, color: Colors.indigo.shade600),
            const SizedBox(width: 4),
            Text(
              widget.label,
              style: TextStyle(fontSize: 11, color: Colors.indigo.shade600),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.isPassword && !_showPassword ? '••••••••' : widget.value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.indigo.shade900,
                  fontFamily: widget.isPassword ? 'monospace' : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.isPassword)
              InkWell(
                onTap: () => setState(() => _showPassword = !_showPassword),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                    color: Colors.indigo.shade400,
                  ),
                ),
              ),
            if (widget.canCopy)
              InkWell(
                onTap: () {
                  // نسخ القيمة
                  final data = ClipboardData(text: widget.value);
                  Clipboard.setData(data);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم نسخ ${widget.label}'),
                      duration: const Duration(seconds: 1),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy,
                    size: 16,
                    color: Colors.indigo.shade400,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
