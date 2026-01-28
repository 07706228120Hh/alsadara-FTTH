/// صفحة قائمة الشركات
/// تعرض جميع الشركات مع إمكانية البحث والفلترة
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../multi_tenant.dart';
import 'add_company_page.dart';
import 'edit_company_page.dart';
import '../home_page.dart';

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      // إنشاء صلاحيات المدير الكاملة
      final Map<String, bool> fullPermissions = {
        'attendance': true,
        'agent': true,
        'tasks': true,
        'zones': true,
        'ai_search': true,
        'users_management': true,
        'reports': true,
        'settings': true,
        'dashboard': true,
        'tickets': true,
        'notifications': true,
        'maintenance': true,
      };

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

  const _CompanyCard({
    required this.tenant,
    required this.onTap,
    required this.onEnterAsCompany,
    required this.onEdit,
    required this.onDelete,
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
