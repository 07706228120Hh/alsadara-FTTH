/// 🏢 صفحة إدارة الشركات الموحدة
/// تجمع جميع ميزات إدارة الشركات في شاشة واحدة متكاملة
/// - الإحصائيات
/// - البحث والفلترة
/// - عرض الشركات
/// - إضافة/تعديل/حذف الشركات
/// - ربط المواطن
/// - تجديد الاشتراك
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/api/auth/super_admin_api.dart';
import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';
import '../../citizen_portal/citizen_portal.dart';
import 'add_company_page.dart';
import 'edit_company_page.dart';
import 'company_details_page.dart';
import 'admin_theme.dart';
import '../home_page.dart';
import '../../multi_tenant.dart';

/// حالة الاشتراك
enum CompanyStatus {
  active,
  warning,
  critical,
  expired,
  suspended,
}

class UnifiedCompaniesPage extends StatefulWidget {
  const UnifiedCompaniesPage({super.key});

  @override
  State<UnifiedCompaniesPage> createState() => _UnifiedCompaniesPageState();
}

class _UnifiedCompaniesPageState extends State<UnifiedCompaniesPage> {
  final SuperAdminApi _superAdminApi = SuperAdminApi();
  final ApiClient _apiClient = ApiClient.instance;
  final TextEditingController _searchController = TextEditingController();

  // حالة البيانات
  bool _isLoading = true;
  String? _errorMessage;
  List<Company> _companies = [];

  // الفلترة والبحث
  String _searchQuery = '';
  CompanyStatus? _statusFilter;

  // ربط بوابة المواطن
  String? _linkedCompanyId;
  bool _isLoadingLinked = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// تحميل جميع البيانات
  Future<void> _loadData() async {
    await Future.wait([
      _loadCompanies(),
      _loadLinkedCompany(),
    ]);
  }

  /// تحميل الشركات من VPS API
  Future<void> _loadCompanies() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
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

  /// تحميل معلومات الشركة المرتبطة ببوابة المواطن
  Future<void> _loadLinkedCompany() async {
    setState(() => _isLoadingLinked = true);
    try {
      final linkedId = await CitizenPortalHelper.getLinkedCompanyId();
      if (mounted) {
        setState(() {
          _linkedCompanyId = linkedId;
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

  /// الحصول على حالة الشركة
  CompanyStatus _getCompanyStatus(Company company) {
    if (!company.isActive) return CompanyStatus.suspended;
    if (company.isExpired) return CompanyStatus.expired;
    if (company.daysRemaining <= 7) return CompanyStatus.critical;
    if (company.daysRemaining <= 30) return CompanyStatus.warning;
    return CompanyStatus.active;
  }

  /// الحصول على لون الحالة
  Color _getStatusColor(CompanyStatus status) {
    switch (status) {
      case CompanyStatus.active:
        return const Color(0xFF10B981);
      case CompanyStatus.warning:
        return const Color(0xFFf7971e);
      case CompanyStatus.critical:
        return const Color(0xFFeb3349);
      case CompanyStatus.expired:
        return Colors.red;
      case CompanyStatus.suspended:
        return Colors.grey;
    }
  }

  /// الحصول على نص الحالة
  String _getStatusText(CompanyStatus status) {
    switch (status) {
      case CompanyStatus.active:
        return 'نشط';
      case CompanyStatus.warning:
        return 'تحذير';
      case CompanyStatus.critical:
        return 'حرج';
      case CompanyStatus.expired:
        return 'منتهي';
      case CompanyStatus.suspended:
        return 'معلق';
    }
  }

  /// فلترة الشركات
  List<Company> get _filteredCompanies {
    var result = _companies;

    // البحث
    if (_searchQuery.isNotEmpty) {
      result = result.where((c) {
        return c.name.toLowerCase().contains(_searchQuery) ||
            c.code.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // الفلترة حسب الحالة
    if (_statusFilter != null) {
      result =
          result.where((c) => _getCompanyStatus(c) == _statusFilter).toList();
    }

    return result;
  }

  /// حساب الإحصائيات
  Map<String, int> get _statistics {
    final total = _companies.length;
    final active = _companies.where((c) => c.isActive && !c.isExpired).length;
    final suspended = _companies.where((c) => !c.isActive).length;
    final expired = _companies.where((c) => c.isExpired).length;
    final critical = _companies
        .where((c) => c.daysRemaining <= 7 && c.daysRemaining > 0 && c.isActive)
        .length;
    final warning = _companies
        .where(
            (c) => c.daysRemaining <= 30 && c.daysRemaining > 7 && c.isActive)
        .length;

    return {
      'total': total,
      'active': active,
      'suspended': suspended,
      'expired': expired,
      'critical': critical,
      'warning': warning,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminTheme.backgroundColor,
      body: Column(
        children: [
          // شريط الأدوات العلوي
          _buildToolbar(),

          // المحتوى
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorWidget()
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  /// شريط الأدوات العلوي الموحد
  Widget _buildToolbar() {
    final stats = _statistics;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(color: AdminTheme.borderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الصف الأول: العنوان والأزرار
          Row(
            children: [
              // عنوان الصفحة
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.black.withOpacity(0.3), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.business_rounded,
                        color: AdminTheme.primaryColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إدارة الشركات',
                        style: TextStyle(
                          color: AdminTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'عرض وإدارة جميع الشركات المسجلة',
                        style: TextStyle(
                          color: AdminTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const Spacer(),

              // شارة VPS
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade50, Colors.green.shade100],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.black.withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done_rounded,
                        size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Text(
                      'VPS متصل',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // زر التحديث
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _loadCompanies,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AdminTheme.backgroundColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.black.withOpacity(0.3), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        size: 20, color: AdminTheme.textSecondary),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              // زر إضافة شركة
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.black.withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: AdminTheme.primaryColor.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToAddCompany(),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('إضافة شركة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // الصف الثاني: بطاقات الإحصائيات
          Row(
            children: [
              _buildStatChip('الكل', stats['total']!, Icons.apps_rounded,
                  const Color(0xFF6366F1), null),
              const SizedBox(width: 10),
              _buildStatChip(
                  'نشطة',
                  stats['active']!,
                  Icons.check_circle_rounded,
                  const Color(0xFF10B981),
                  CompanyStatus.active),
              const SizedBox(width: 10),
              _buildStatChip('تحذير', stats['warning']!, Icons.schedule_rounded,
                  const Color(0xFFf59e0b), CompanyStatus.warning),
              const SizedBox(width: 10),
              _buildStatChip('حرج', stats['critical']!, Icons.warning_rounded,
                  const Color(0xFFef4444), CompanyStatus.critical),
              const SizedBox(width: 10),
              _buildStatChip('منتهية', stats['expired']!, Icons.cancel_rounded,
                  const Color(0xFFdc2626), CompanyStatus.expired),
              const SizedBox(width: 10),
              _buildStatChip(
                  'معلقة',
                  stats['suspended']!,
                  Icons.pause_circle_rounded,
                  const Color(0xFF64748b),
                  CompanyStatus.suspended),
            ],
          ),
        ],
      ),
    );
  }

  /// بطاقة إحصائية جميلة
  Widget _buildStatChip(String label, int value, IconData icon, Color color,
      CompanyStatus? filterStatus) {
    final isSelected = _statusFilter == filterStatus;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _statusFilter = filterStatus),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withOpacity(0.15)
                  : AdminTheme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : Colors.black.withOpacity(0.3),
                width: isSelected ? 2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: isSelected
                      ? color.withOpacity(0.2)
                      : Colors.black.withOpacity(0.08),
                  blurRadius: isSelected ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.toString(),
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? color : AdminTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// محتوى الصفحة
  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: _loadCompanies,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // البحث والفلترة
            _buildSearchAndFilter(),

            const SizedBox(height: 16),

            // قائمة الشركات
            _buildCompaniesGrid(),
          ],
        ),
      ),
    );
  }

  /// قسم الإحصائيات
  Widget _buildStatisticsSection() {
    final stats = _statistics;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.analytics_outlined,
                color: AdminTheme.primaryColor, size: 20),
            const SizedBox(width: 8),
            const Text(
              'الإحصائيات',
              style: TextStyle(
                color: AdminTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildStatCard(
              title: 'إجمالي الشركات',
              value: stats['total'].toString(),
              icon: Icons.business_rounded,
              gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              onTap: () => setState(() => _statusFilter = null),
            ),
            _buildStatCard(
              title: 'نشطة',
              value: stats['active'].toString(),
              icon: Icons.check_circle_rounded,
              gradient: const [Color(0xFF10B981), Color(0xFF34D399)],
              onTap: () => setState(() => _statusFilter = CompanyStatus.active),
            ),
            _buildStatCard(
              title: 'تحتاج تجديد',
              value: stats['warning'].toString(),
              icon: Icons.schedule_rounded,
              gradient: const [Color(0xFFf7971e), Color(0xFFffd200)],
              onTap: () =>
                  setState(() => _statusFilter = CompanyStatus.warning),
            ),
            _buildStatCard(
              title: 'حرج',
              value: stats['critical'].toString(),
              icon: Icons.warning_rounded,
              gradient: const [Color(0xFFeb3349), Color(0xFFf45c43)],
              onTap: () =>
                  setState(() => _statusFilter = CompanyStatus.critical),
            ),
            _buildStatCard(
              title: 'منتهية',
              value: stats['expired'].toString(),
              icon: Icons.cancel_rounded,
              gradient: const [Color(0xFFeb3349), Color(0xFFf45c43)],
              onTap: () =>
                  setState(() => _statusFilter = CompanyStatus.expired),
            ),
            _buildStatCard(
              title: 'معلقة',
              value: stats['suspended'].toString(),
              icon: Icons.pause_circle_rounded,
              gradient: const [Color(0xFF64748B), Color(0xFF94A3B8)],
              onTap: () =>
                  setState(() => _statusFilter = CompanyStatus.suspended),
            ),
          ],
        ),
      ],
    );
  }

  /// بطاقة الإحصائية
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    final isSelected = _statusFilter != null &&
        ((title == 'نشطة' && _statusFilter == CompanyStatus.active) ||
            (title == 'تحتاج تجديد' &&
                _statusFilter == CompanyStatus.warning) ||
            (title == 'حرج' && _statusFilter == CompanyStatus.critical) ||
            (title == 'منتهية' && _statusFilter == CompanyStatus.expired) ||
            (title == 'معلقة' && _statusFilter == CompanyStatus.suspended) ||
            (title == 'إجمالي الشركات' && _statusFilter == null));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 140,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? gradient[0].withOpacity(0.1)
                : AdminTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? gradient[0] : AdminTheme.borderColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      gradient[0].withOpacity(0.15),
                      gradient[1].withOpacity(0.1)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: gradient[0], size: 18),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  color: gradient[0],
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  color: AdminTheme.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// البحث والفلترة
  Widget _buildSearchAndFilter() {
    return Row(
      children: [
        // حقل البحث
        Expanded(
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'البحث بالاسم أو الكود...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AdminTheme.surfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AdminTheme.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AdminTheme.borderColor),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
          ),
        ),

        const SizedBox(width: 12),

        // زر مسح الفلتر
        if (_statusFilter != null)
          TextButton.icon(
            onPressed: () => setState(() => _statusFilter = null),
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('مسح الفلتر'),
            style: TextButton.styleFrom(
              foregroundColor: AdminTheme.textSecondary,
            ),
          ),

        // عدد النتائج
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AdminTheme.surfaceColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AdminTheme.borderColor),
          ),
          child: Text(
            '${_filteredCompanies.length} شركة',
            style: TextStyle(
              color: AdminTheme.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  /// شبكة الشركات
  Widget _buildCompaniesGrid() {
    final companies = _filteredCompanies;

    if (companies.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.business_outlined,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty || _statusFilter != null
                    ? 'لا توجد نتائج'
                    : 'لا توجد شركات',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                ),
              ),
              if (_searchQuery.isEmpty && _statusFilter == null) ...[
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _navigateToAddCompany,
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة شركة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdminTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // ✅ عرض البطاقات بشكل مستطيل بعرض الشاشة الكامل
    return Column(
      children: companies.map((company) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _UnifiedCompanyCard(
            company: company,
            status: _getCompanyStatus(company),
            statusColor: _getStatusColor(_getCompanyStatus(company)),
            statusText: _getStatusText(_getCompanyStatus(company)),
            isLinkedToCitizen: _linkedCompanyId == company.id,
            onTap: () => _openCompanyDetails(company),
          ),
        );
      }).toList(),
    );
  }

  /// فتح شاشة تفاصيل الشركة
  void _openCompanyDetails(Company company) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompanyDetailsPage(
          company: company,
          isLinkedToCitizen: _linkedCompanyId == company.id,
          onRefresh: _loadCompanies,
        ),
      ),
    );
  }

  /// عرض رسالة الخطأ
  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.red),
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

  // ============================================
  // إجراءات الشركات
  // ============================================

  /// الانتقال لإضافة شركة
  void _navigateToAddCompany() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddCompanyPage()),
    ).then((_) => _loadCompanies());
  }

  /// إدارة صلاحيات الشركة
  void _managePermissions(Company company) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _CompanyPermissionsDialog(company: company),
    );

    // إعادة تحميل الشركات بعد حفظ الصلاحيات
    if (result == true) {
      _loadCompanies();
    }
  }

  /// تعديل الشركة
  void _editCompany(Company company) {
    // تحويل Company إلى Tenant لصفحة التعديل
    final tenant = Tenant(
      id: company.id,
      name: company.name,
      code: company.code,
      email: company.email,
      phone: company.phone,
      address: company.address,
      city: company.city,
      subscriptionStart: company.subscriptionStartDate,
      subscriptionEnd: company.subscriptionEndDate,
      subscriptionPlan: 'monthly',
      maxUsers: company.maxUsers,
      isActive: company.isActive,
      createdAt: company.createdAt,
      createdBy: 'system',
      enabledFirstSystemFeatures: const {},
      enabledSecondSystemFeatures: const {},
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditCompanyPage(tenant: tenant),
      ),
    ).then((_) => _loadCompanies());
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
            const SnackBar(content: Text('تم حذف الشركة بنجاح')),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: company.isActive ? Colors.orange : Colors.green,
            ),
            child: Text(company.isActive ? 'تعطيل' : 'تفعيل'),
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
                  Text('تم ${company.isActive ? "تعطيل" : "تفعيل"} الشركة'),
            ),
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
      style: ElevatedButton.styleFrom(
        backgroundColor: AdminTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }

  /// ربط الشركة ببوابة المواطن
  Future<void> _linkToCitizenPortal(Company company) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: Colors.teal),
            SizedBox(width: 8),
            Text('ربط بوابة المواطن'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد ربط شركة "${company.name}" ببوابة المواطن؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.teal),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم إلغاء ربط أي شركة أخرى مرتبطة حالياً',
                      style: TextStyle(color: Colors.teal),
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
            icon: const Icon(Icons.link),
            label: const Text('ربط'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await CompanyApiService.linkToCitizenPortal(company.id);
        CitizenPortalHelper.clearCache(); // مسح الكاش
        if (mounted) {
          setState(() {
            _linkedCompanyId = company.id;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم ربط الشركة ببوابة المواطن')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e')),
          );
        }
      }
    }
  }

  /// إلغاء ربط الشركة من بوابة المواطن
  Future<void> _unlinkFromCitizenPortal(Company company) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('إلغاء الربط'),
          ],
        ),
        content:
            Text('هل تريد إلغاء ربط شركة "${company.name}" من بوابة المواطن؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.link_off),
            label: const Text('إلغاء الربط'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await CompanyApiService.unlinkFromCitizenPortal(company.id);
        CitizenPortalHelper.clearCache(); // مسح الكاش
        if (mounted) {
          setState(() {
            _linkedCompanyId = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم إلغاء ربط الشركة من بوابة المواطن')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e')),
          );
        }
      }
    }
  }

  /// الدخول للشركة كمدير
  Future<void> _enterAsCompany(Company company) async {
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
}

// ============================================
// بطاقة الشركة الموحدة
// ============================================

class _UnifiedCompanyCard extends StatelessWidget {
  final Company company;
  final CompanyStatus status;
  final Color statusColor;
  final String statusText;
  final bool isLinkedToCitizen;
  final VoidCallback onTap;

  const _UnifiedCompanyCard({
    required this.company,
    required this.status,
    required this.statusColor,
    required this.statusText,
    required this.isLinkedToCitizen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: AdminTheme.surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLinkedToCitizen
                  ? Colors.teal
                  : Colors.black.withOpacity(0.4),
              width: isLinkedToCitizen ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // شريط الحالة الملون في الأعلى
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(11)),
                ),
              ),

              // المحتوى الرئيسي - صف أفقي
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1️⃣ أيقونة الشركة
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AdminTheme.primaryColor.withOpacity(0.15),
                            AdminTheme.primaryColor.withOpacity(0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AdminTheme.primaryColor.withOpacity(0.2),
                        ),
                      ),
                      child: company.logoUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                company.logoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.business_rounded,
                                  color: AdminTheme.primaryColor,
                                  size: 24,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.business_rounded,
                              color: AdminTheme.primaryColor,
                              size: 24,
                            ),
                    ),

                    const SizedBox(width: 16),

                    // 2️⃣ معلومات الشركة
                    Expanded(
                      flex: 2,
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
                                    color: AdminTheme.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // شارة الحالة
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: statusColor.withOpacity(0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      statusText,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color:
                                      AdminTheme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  company.code,
                                  style: const TextStyle(
                                    color: AdminTheme.primaryColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (company.email != null) ...[
                                const SizedBox(width: 12),
                                Icon(Icons.email_outlined,
                                    size: 14, color: AdminTheme.textMuted),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    company.email!,
                                    style: TextStyle(
                                      color: AdminTheme.textSecondary,
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                              if (isLinkedToCitizen) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.teal.withOpacity(0.3)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.people_alt_rounded,
                                          size: 12, color: Colors.teal),
                                      SizedBox(width: 4),
                                      Text(
                                        'مرتبطة',
                                        style: TextStyle(
                                          color: Colors.teal,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 20),

                    // 3️⃣ معلومات الاشتراك
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AdminTheme.backgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AdminTheme.borderColor),
                      ),
                      child: Row(
                        children: [
                          _buildCompactInfo(
                            Icons.calendar_month_rounded,
                            dateFormat.format(company.subscriptionEndDate),
                            color: company.daysRemaining <= 30
                                ? Colors.orange
                                : null,
                          ),
                          Container(
                            height: 30,
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            color: AdminTheme.borderColor,
                          ),
                          _buildCompactInfo(
                            Icons.hourglass_bottom_rounded,
                            '${company.daysRemaining} يوم',
                            color: company.daysRemaining <= 7
                                ? Colors.red
                                : company.daysRemaining <= 30
                                    ? Colors.orange
                                    : Colors.green,
                          ),
                          Container(
                            height: 30,
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            color: AdminTheme.borderColor,
                          ),
                          _buildCompactInfo(
                            Icons.groups_rounded,
                            '${company.employeeCount}/${company.maxUsers}',
                            color: company.employeeCount >= company.maxUsers
                                ? Colors.red
                                : null,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // أيقونة السهم للدخول
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AdminTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AdminTheme.primaryColor,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactInfo(IconData icon, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color ?? AdminTheme.textSecondary),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color ?? AdminTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ============================================
// صندوق حوار إدارة صلاحيات الشركة
// ============================================

class _CompanyPermissionsDialog extends StatefulWidget {
  final Company company;

  const _CompanyPermissionsDialog({required this.company});

  @override
  State<_CompanyPermissionsDialog> createState() =>
      _CompanyPermissionsDialogState();
}

class _CompanyPermissionsDialogState extends State<_CompanyPermissionsDialog>
    with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient.instance;
  bool _isLoading = false;
  late TabController _tabController;

  // صلاحيات النظام الأول (النظام الرئيسي)
  late Map<String, bool> _firstSystemPermissions;

  // صلاحيات النظام الثاني (FTTH)
  late Map<String, bool> _secondSystemPermissions;

  final Map<String, Map<String, dynamic>> _firstSystemFeatures = {
    'attendance': {
      'label': 'الحضور والانصراف',
      'icon': Icons.access_time_rounded,
      'description': 'تسجيل حضور وانصراف الموظفين'
    },
    'agent': {
      'label': 'إدارة الوكلاء',
      'icon': Icons.support_agent_rounded,
      'description': 'إدارة وكلاء المبيعات'
    },
    'tasks': {
      'label': 'المهام',
      'icon': Icons.task_alt_rounded,
      'description': 'إدارة المهام والتكليفات'
    },
    'zones': {
      'label': 'المناطق',
      'icon': Icons.map_rounded,
      'description': 'تحديد مناطق العمل'
    },
    'ai_search': {
      'label': 'البحث الذكي',
      'icon': Icons.auto_awesome_rounded,
      'description': 'بحث بالذكاء الاصطناعي'
    },
  };

  final Map<String, Map<String, dynamic>> _secondSystemFeatures = {
    'dashboard': {
      'label': 'لوحة التحكم',
      'icon': Icons.dashboard_rounded,
      'description': 'عرض الإحصائيات الرئيسية'
    },
    'users': {
      'label': 'إدارة المستخدمين',
      'icon': Icons.people_rounded,
      'description': 'إدارة المشتركين والعملاء'
    },
    'subscriptions': {
      'label': 'الاشتراكات',
      'icon': Icons.card_membership_rounded,
      'description': 'إدارة باقات الاشتراك'
    },
    'tasks': {
      'label': 'المهام',
      'icon': Icons.assignment_rounded,
      'description': 'إدارة مهام الصيانة'
    },
    'zones': {
      'label': 'المناطق',
      'icon': Icons.location_on_rounded,
      'description': 'تحديد مناطق التغطية'
    },
    'accounts': {
      'label': 'الحسابات',
      'icon': Icons.account_balance_wallet_rounded,
      'description': 'إدارة الحسابات المالية'
    },
    'export': {
      'label': 'التصدير',
      'icon': Icons.file_download_rounded,
      'description': 'تصدير البيانات والتقارير'
    },
    'agents': {
      'label': 'الوكلاء',
      'icon': Icons.store_rounded,
      'description': 'إدارة نقاط البيع'
    },
    'whatsapp': {
      'label': 'واتساب',
      'icon': Icons.chat_rounded,
      'description': 'التكامل مع واتساب'
    },
    'technicians': {
      'label': 'الفنيين',
      'icon': Icons.engineering_rounded,
      'description': 'إدارة فريق الصيانة'
    },
    'transactions': {
      'label': 'المعاملات',
      'icon': Icons.receipt_long_rounded,
      'description': 'سجل المعاملات المالية'
    },
    'reports': {
      'label': 'التقارير',
      'icon': Icons.analytics_rounded,
      'description': 'تقارير الأداء والمبيعات'
    },
    'settings': {
      'label': 'الإعدادات',
      'icon': Icons.settings_rounded,
      'description': 'إعدادات النظام'
    },
    'notifications': {
      'label': 'الإشعارات',
      'icon': Icons.notifications_rounded,
      'description': 'إدارة الإشعارات'
    },
    'maintenance': {
      'label': 'الصيانة',
      'icon': Icons.build_rounded,
      'description': 'جدولة أعمال الصيانة'
    },
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    debugPrint('🏢 فتح حوار الصلاحيات للشركة:');
    debugPrint('   ID: ${widget.company.id}');
    debugPrint('   Name: ${widget.company.name}');
    debugPrint(
        '   FirstFeatures: ${widget.company.enabledFirstSystemFeatures}');
    debugPrint(
        '   SecondFeatures: ${widget.company.enabledSecondSystemFeatures}');
    _loadCurrentPermissions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadCurrentPermissions() {
    // تحميل الصلاحيات الافتراضية (كلها مفعلة)
    _firstSystemPermissions = {
      for (var key in _firstSystemFeatures.keys) key: true,
    };

    _secondSystemPermissions = {
      for (var key in _secondSystemFeatures.keys) key: true,
    };

    // تحميل صلاحيات النظام الأول من الشركة
    if (widget.company.enabledFirstSystemFeatures != null &&
        widget.company.enabledFirstSystemFeatures!.isNotEmpty) {
      final features = widget.company.enabledFirstSystemFeatures!;
      debugPrint('📋 تحميل صلاحيات النظام الأول: $features');
      for (var key in _firstSystemPermissions.keys) {
        if (features.containsKey(key)) {
          _firstSystemPermissions[key] = features[key] == true;
        }
      }
    }

    // تحميل صلاحيات النظام الثاني من الشركة
    if (widget.company.enabledSecondSystemFeatures != null &&
        widget.company.enabledSecondSystemFeatures!.isNotEmpty) {
      final features = widget.company.enabledSecondSystemFeatures!;
      debugPrint('📋 تحميل صلاحيات النظام الثاني: $features');
      for (var key in _secondSystemPermissions.keys) {
        if (features.containsKey(key)) {
          _secondSystemPermissions[key] = features[key] == true;
        }
      }
    }

    debugPrint('✅ الصلاحيات بعد التحميل:');
    debugPrint('   النظام الأول: $_firstSystemPermissions');
    debugPrint('   النظام الثاني: $_secondSystemPermissions');
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 750,
        constraints: const BoxConstraints(maxHeight: 750),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1a1a2e),
              const Color(0xFF16213e),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 5,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: Colors.purple.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(child: _buildTabContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withOpacity(0.2),
            Colors.blue.withOpacity(0.1),
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          bottom: BorderSide(color: Colors.purple.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          // أيقونة متحركة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple, Colors.purple.shade700],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.4),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'صلاحيات الشركة',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.green.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_rounded,
                              color: Colors.green.shade400, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'نشطة',
                            style: TextStyle(
                              color: Colors.green.shade400,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.business_rounded,
                        color: Colors.white60, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      widget.company.name,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.company.code,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade300,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              padding: const EdgeInsets.all(12),
            ),
            icon: const Icon(Icons.close_rounded, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple, Colors.purple.shade700],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        padding: const EdgeInsets.all(6),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.home_rounded, size: 20),
                const SizedBox(width: 8),
                const Text('النظام الرئيسي'),
                const SizedBox(width: 8),
                _buildPermissionCount(_firstSystemPermissions),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.wifi_rounded, size: 20),
                const SizedBox(width: 8),
                const Text('نظام FTTH'),
                const SizedBox(width: 8),
                _buildPermissionCount(_secondSystemPermissions),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCount(Map<String, bool> permissions) {
    final enabled = permissions.values.where((v) => v).length;
    final total = permissions.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$enabled/$total',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildPermissionsGrid(
            _firstSystemPermissions, _firstSystemFeatures, Colors.blue),
        _buildPermissionsGrid(
            _secondSystemPermissions, _secondSystemFeatures, Colors.teal),
      ],
    );
  }

  Widget _buildPermissionsGrid(
    Map<String, bool> permissions,
    Map<String, Map<String, dynamic>> features,
    Color accentColor,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Quick Actions
          _buildQuickActions(permissions, accentColor),
          const SizedBox(height: 16),
          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 1.4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: features.length,
            itemBuilder: (context, index) {
              final key = features.keys.elementAt(index);
              final feature = features[key]!;
              final isEnabled = permissions[key] ?? false;

              return _buildPermissionCard(
                key: key,
                label: feature['label'] as String,
                icon: feature['icon'] as IconData,
                description: feature['description'] as String,
                isEnabled: isEnabled,
                accentColor: accentColor,
                onChanged: (value) {
                  setState(() {
                    permissions[key] = value;
                  });
                },
              );
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuickActions(Map<String, bool> permissions, Color accentColor) {
    final allEnabled = permissions.values.every((v) => v);
    final enabledCount = permissions.values.where((v) => v).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.1),
            accentColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.flash_on_rounded, color: accentColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'إجراءات سريعة',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '$enabledCount من ${permissions.length} صلاحية مفعلة',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                for (var key in permissions.keys) {
                  permissions[key] = true;
                }
              });
            },
            icon: const Icon(Icons.check_circle_rounded, size: 18),
            label: const Text('تفعيل الكل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.withOpacity(0.8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                for (var key in permissions.keys) {
                  permissions[key] = false;
                }
              });
            },
            icon: const Icon(Icons.remove_circle_rounded, size: 18),
            label: const Text('إلغاء الكل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard({
    required String key,
    required String label,
    required IconData icon,
    required String description,
    required bool isEnabled,
    required Color accentColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!isEnabled),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: isEnabled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withOpacity(0.2),
                      accentColor.withOpacity(0.1),
                    ],
                  )
                : null,
            color: isEnabled ? null : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isEnabled
                  ? accentColor.withOpacity(0.5)
                  : Colors.white.withOpacity(0.1),
              width: isEnabled ? 2 : 1,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: accentColor.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? accentColor.withOpacity(0.2)
                          : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      color: isEnabled ? accentColor : Colors.white38,
                      size: 22,
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isEnabled
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: isEnabled ? Colors.green : Colors.red.shade300,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? Colors.white : Colors.white60,
                  fontWeight: isEnabled ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          // معلومات
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded,
                    color: Colors.white38, size: 16),
                const SizedBox(width: 8),
                Text(
                  'سيتم تطبيق التغييرات فوراً',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // أزرار
          TextButton(
            onPressed: _isLoading ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white60,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('إلغاء'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _savePermissions,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 20),
            label: Text(_isLoading ? 'جاري الحفظ...' : 'حفظ الصلاحيات'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
              shadowColor: Colors.purple.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _savePermissions() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('📡 حفظ صلاحيات الشركة: ${widget.company.id}');
      debugPrint('📋 النظام الأول: $_firstSystemPermissions');
      debugPrint('📋 النظام الثاني: $_secondSystemPermissions');

      // إرسال الصلاحيات إلى VPS API
      final response = await _apiClient.put(
        '${ApiConfig.internalCompanies}/${widget.company.id}',
        {
          'enabledFirstSystemFeatures': _firstSystemPermissions,
          'enabledSecondSystemFeatures': _secondSystemPermissions,
        },
        (json) => json,
        useInternalKey: true,
      );

      debugPrint('📊 الاستجابة: ${response.isSuccess} - ${response.message}');

      setState(() => _isLoading = false);

      if (!mounted) return;

      if (response.isSuccess) {
        Navigator.pop(context, true); // إرجاع true للإشارة إلى التحديث
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('تم حفظ الصلاحيات بنجاح'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(response.message ?? 'فشل حفظ الصلاحيات')),
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

      if (!mounted) return;

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
