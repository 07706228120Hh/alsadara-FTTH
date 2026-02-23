/// صفحة قائمة الشركات عبر VPS API
/// تعرض جميع الشركات مع إمكانية البحث والفلترة
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/api/auth/super_admin_api.dart';
import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';
import '../../citizen_portal/citizen_portal.dart';
import 'add_company_page.dart';
import '../home_page.dart';
import '../../permissions/permissions.dart';

/// حالة الاشتراك
enum VpsSubscriptionStatus {
  active,
  warning,
  critical,
  expired,
  suspended,
}

class VpsCompaniesListPage extends StatefulWidget {
  const VpsCompaniesListPage({super.key});

  @override
  State<VpsCompaniesListPage> createState() => _VpsCompaniesListPageState();
}

class _VpsCompaniesListPageState extends State<VpsCompaniesListPage> {
  final SuperAdminApi _superAdminApi = SuperAdminApi();
  final ApiClient _apiClient = ApiClient.instance;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  VpsSubscriptionStatus? _statusFilter;

  // حالة التحميل
  bool _isLoading = true;
  String? _errorMessage;
  List<Company> _companies = [];

  // Citizen Portal linking state
  String? _linkedCompanyId;
  bool _isLoadingLinked = false;

  @override
  void initState() {
    super.initState();
    _loadCompanies();
    _loadLinkedCompany();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// تحميل الشركات من VPS API (Internal API - بدون تسجيل دخول)
  Future<void> _loadCompanies() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // استخدام Internal API مباشرة بدون الحاجة لتسجيل الدخول
      debugPrint('📡 جلب الشركات من Internal API...');

      final response = await _apiClient.get<List<Company>>(
        ApiConfig.internalCompanies,
        (json) {
          if (json is List) {
            return json
                .map((item) => Company.fromJson(item as Map<String, dynamic>))
                .toList();
          }
          return <Company>[];
        },
        useInternalKey: true,
      );

      if (mounted) {
        if (response.isSuccess && response.data != null) {
          debugPrint('✅ تم جلب ${response.data!.length} شركة بنجاح');
          setState(() {
            _companies = response.data!;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = response.message ?? 'خطأ في جلب البيانات';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب الشركات: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'خطأ في الاتصال: $e';
          _isLoading = false;
        });
      }
    }
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

  /// الحصول على حالة الاشتراك
  VpsSubscriptionStatus _getStatus(Company company) {
    if (!company.isActive) return VpsSubscriptionStatus.suspended;
    if (company.isExpired) return VpsSubscriptionStatus.expired;
    if (company.daysRemaining <= 7) return VpsSubscriptionStatus.critical;
    if (company.daysRemaining <= 30) return VpsSubscriptionStatus.warning;
    return VpsSubscriptionStatus.active;
  }

  /// الحصول على لون الحالة
  Color _getStatusColor(VpsSubscriptionStatus status) {
    switch (status) {
      case VpsSubscriptionStatus.active:
        return Colors.green;
      case VpsSubscriptionStatus.warning:
        return Colors.orange;
      case VpsSubscriptionStatus.critical:
        return Colors.deepOrange;
      case VpsSubscriptionStatus.expired:
        return Colors.red;
      case VpsSubscriptionStatus.suspended:
        return Colors.grey;
    }
  }

  /// الحصول على نص الحالة
  String _getStatusText(VpsSubscriptionStatus status) {
    switch (status) {
      case VpsSubscriptionStatus.active:
        return 'نشط';
      case VpsSubscriptionStatus.warning:
        return 'تحذير';
      case VpsSubscriptionStatus.critical:
        return 'حرج';
      case VpsSubscriptionStatus.expired:
        return 'منتهي';
      case VpsSubscriptionStatus.suspended:
        return 'معلق';
    }
  }

  /// فلترة الشركات
  List<Company> get _filteredCompanies {
    var result = _companies;

    // تطبيق البحث
    if (_searchQuery.isNotEmpty) {
      result = result.where((c) {
        return c.name.toLowerCase().contains(_searchQuery) ||
            c.code.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // تطبيق الفلتر
    if (_statusFilter != null) {
      result = result.where((c) => _getStatus(c) == _statusFilter).toList();
    }

    return result;
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

              // زر التحديث
              IconButton(
                onPressed: _loadCompanies,
                icon: const Icon(Icons.refresh),
                tooltip: 'تحديث',
              ),

              // فلتر الحالة
              PopupMenuButton<VpsSubscriptionStatus?>(
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
                      VpsSubscriptionStatus.active, 'نشط', Colors.green),
                  _buildFilterMenuItem(
                      VpsSubscriptionStatus.warning, 'تحذير', Colors.orange),
                  _buildFilterMenuItem(
                      VpsSubscriptionStatus.critical, 'حرج', Colors.deepOrange),
                  _buildFilterMenuItem(
                      VpsSubscriptionStatus.expired, 'منتهي', Colors.red),
                  _buildFilterMenuItem(
                      VpsSubscriptionStatus.suspended, 'معلق', Colors.grey),
                ],
              ),
            ],
          ),
        ),

        // شارة VPS API
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done, size: 14, color: Colors.green[700]),
                    const SizedBox(width: 4),
                    Text(
                      'VPS API',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_filteredCompanies.length} شركة',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // قائمة الشركات
        Expanded(
          child: _buildCompanyList(),
        ),
      ],
    );
  }

  Widget _buildCompanyList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
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
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadCompanies,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    final companies = _filteredCompanies;

    if (companies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.business_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _statusFilter != null
                  ? 'لا توجد نتائج'
                  : 'لا توجد شركات',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_searchQuery.isEmpty && _statusFilter == null)
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AddCompanyPage()),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('إضافة شركة'),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCompanies,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: companies.length,
        itemBuilder: (context, index) {
          final company = companies[index];
          return _VpsCompanyCard(
            company: company,
            status: _getStatus(company),
            linkedCompanyId: _linkedCompanyId,
            onTap: () => _showCompanyOptions(context, company),
            onEnterAsCompany: () => _enterAsCompany(context, company),
            onRefresh: _loadCompanies,
          );
        },
      ),
    );
  }

  PopupMenuItem<VpsSubscriptionStatus> _buildFilterMenuItem(
    VpsSubscriptionStatus status,
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

  /// الدخول للشركة كمدير
  void _enterAsCompany(BuildContext context, Company company) async {
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
            Text('هل تريد الدخول لشركة "${company.name}" كمدير؟'),
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
            department: company.name,
            center: company.code,
            salary: '0',
            pageAccess: fullPermissions,
            tenantId: company.id,
            tenantCode: company.code,
            isSuperAdminMode: true,
          ),
        ),
        (route) => false,
      );
    }
  }

  /// عرض خيارات الشركة
  void _showCompanyOptions(BuildContext context, Company company) {
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
              company.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'كود: ${company.code}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 24),

            // الدخول للشركة
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF1a237e),
                child: Icon(Icons.login, color: Colors.white),
              ),
              title: const Text('الدخول للشركة'),
              subtitle: const Text('الدخول كمدير بصلاحيات كاملة'),
              onTap: () {
                Navigator.pop(context);
                _enterAsCompany(context, company);
              },
            ),

            // تعديل الشركة
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child: Icon(Icons.edit, color: Colors.white),
              ),
              title: const Text('تعديل الشركة'),
              subtitle: const Text('تعديل بيانات الشركة والاشتراك'),
              onTap: () {
                Navigator.pop(context);
                // TODO: تعديل الشركة
              },
            ),

            // تفعيل/تعطيل
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    company.isActive ? Colors.orange : Colors.green,
                child: Icon(
                  company.isActive ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
              title: Text(company.isActive ? 'تعطيل الشركة' : 'تفعيل الشركة'),
              onTap: () {
                Navigator.pop(context);
                _toggleCompanyStatus(company);
              },
            ),

            // تجديد الاشتراك
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.teal,
                child: Icon(Icons.refresh, color: Colors.white),
              ),
              title: const Text('تجديد الاشتراك'),
              subtitle: Text('متبقي: ${company.daysRemaining} يوم'),
              onTap: () {
                Navigator.pop(context);
                _renewSubscription(company);
              },
            ),

            // حذف الشركة
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.red,
                child: Icon(Icons.delete, color: Colors.white),
              ),
              title: const Text('حذف الشركة'),
              subtitle: const Text('حذف الشركة وجميع بياناتها'),
              onTap: () {
                Navigator.pop(context);
                _deleteCompany(company);
              },
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// تبديل حالة الشركة
  Future<void> _toggleCompanyStatus(Company company) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(company.isActive ? 'تعطيل الشركة' : 'تفعيل الشركة'),
        content: Text(
          company.isActive
              ? 'هل تريد تعطيل شركة "${company.name}"؟'
              : 'هل تريد تفعيل شركة "${company.name}"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final response = await _superAdminApi.toggleCompanyStatus(company.id);
      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('تم ${company.isActive ? "تعطيل" : "تفعيل"} الشركة')),
          );
          _loadCompanies();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message ?? 'حدث خطأ')),
          );
        }
      }
    }
  }

  /// تجديد الاشتراك
  Future<void> _renewSubscription(Company company) async {
    int? days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تجديد الاشتراك'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('تجديد اشتراك شركة "${company.name}"'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildRenewOption(context, 30, 'شهر'),
                _buildRenewOption(context, 90, '3 أشهر'),
                _buildRenewOption(context, 180, '6 أشهر'),
                _buildRenewOption(context, 365, 'سنة'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (days != null) {
      final response = await _superAdminApi.renewSubscription(company.id, days);
      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تجديد الاشتراك بنجاح')),
          );
          _loadCompanies();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message ?? 'حدث خطأ')),
          );
        }
      }
    }
  }

  Widget _buildRenewOption(BuildContext context, int days, String label) {
    return ElevatedButton(
      onPressed: () => Navigator.pop(context, days),
      child: Text(label),
    );
  }

  /// حذف الشركة
  Future<void> _deleteCompany(Company company) async {
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
            Text('هل تريد حذف شركة "${company.name}"؟'),
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
                      'هذا الإجراء لا يمكن التراجع عنه!',
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final response = await _superAdminApi.deleteCompany(company.id);
      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف الشركة')),
          );
          _loadCompanies();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message ?? 'حدث خطأ')),
          );
        }
      }
    }
  }
}

/// بطاقة الشركة
class _VpsCompanyCard extends StatelessWidget {
  final Company company;
  final VpsSubscriptionStatus status;
  final String? linkedCompanyId;
  final VoidCallback onTap;
  final VoidCallback onEnterAsCompany;
  final VoidCallback onRefresh;

  const _VpsCompanyCard({
    required this.company,
    required this.status,
    this.linkedCompanyId,
    required this.onTap,
    required this.onEnterAsCompany,
    required this.onRefresh,
  });

  Color get _statusColor {
    switch (status) {
      case VpsSubscriptionStatus.active:
        return Colors.green;
      case VpsSubscriptionStatus.warning:
        return Colors.orange;
      case VpsSubscriptionStatus.critical:
        return Colors.deepOrange;
      case VpsSubscriptionStatus.expired:
        return Colors.red;
      case VpsSubscriptionStatus.suspended:
        return Colors.grey;
    }
  }

  String get _statusText {
    switch (status) {
      case VpsSubscriptionStatus.active:
        return 'نشط';
      case VpsSubscriptionStatus.warning:
        return 'تحذير';
      case VpsSubscriptionStatus.critical:
        return 'حرج';
      case VpsSubscriptionStatus.expired:
        return 'منتهي';
      case VpsSubscriptionStatus.suspended:
        return 'معلق';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLinked = linkedCompanyId == company.id;
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isLinked
            ? const BorderSide(color: Colors.teal, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الصف العلوي
              Row(
                children: [
                  // أيقونة الشركة
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1a237e).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: company.logoUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              company.logoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.business,
                                color: Color(0xFF1a237e),
                              ),
                            ),
                          )
                        : const Icon(Icons.business, color: Color(0xFF1a237e)),
                  ),
                  const SizedBox(width: 12),

                  // معلومات الشركة
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                company.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (isLinked)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.teal,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.link,
                                        size: 12, color: Colors.white),
                                    SizedBox(width: 2),
                                    Text(
                                      'المواطن',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'كود: ${company.code}',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  // شارة الحالة
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _statusColor),
                    ),
                    child: Text(
                      _statusText,
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const Divider(height: 24),

              // معلومات الاشتراك
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // تاريخ الانتهاء
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        'ينتهي: ${dateFormat.format(company.subscriptionEndDate)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),

                  // عدد الأيام المتبقية
                  Row(
                    children: [
                      Icon(
                        Icons.timer,
                        size: 16,
                        color: company.daysRemaining <= 7
                            ? Colors.red
                            : Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${company.daysRemaining} يوم',
                        style: TextStyle(
                          fontSize: 13,
                          color: company.daysRemaining <= 7
                              ? Colors.red
                              : Colors.grey[700],
                          fontWeight: company.daysRemaining <= 7
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),

                  // عدد الموظفين
                  Row(
                    children: [
                      Icon(Icons.people, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${company.employeeCount}/${company.maxUsers}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // أزرار الإجراءات السريعة
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onEnterAsCompany,
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('دخول'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1a237e),
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
}
