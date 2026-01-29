/// لوحة تحكم Super Admin الرئيسية - تصميم عصري
/// تعرض جميع الشركات مع إحصائيات وخيارات الإدارة
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../multi_tenant.dart';
import '../../config/data_source_config.dart'; // ✅ إعدادات مصدر البيانات
import '../../services/vps_auth_service.dart'; // ✅ خدمة VPS
import '../../services/api/auth/super_admin_api.dart'; // ✅ VPS API للشركات
import 'unified_companies_page.dart'; // ✅ الشاشة الموحدة لإدارة الشركات
import 'add_company_page.dart';
import 'edit_company_page.dart';
import 'tenant_features_page.dart';
import 'firebase_data_manager_page.dart';
import 'vps_data_manager_page.dart';
import '../tenant_login_page.dart';
import '../vps_tenant_login_page.dart'; // ✅ صفحة تسجيل دخول VPS
import '../home_page.dart';
import 'admin_theme.dart';
import '../diagnostics/system_diagnostics_page.dart'; // 🔧 صفحة التشخيص

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard>
    with SingleTickerProviderStateMixin {
  final CustomAuthService _authService = CustomAuthService();
  final SuperAdminApi _superAdminApi = SuperAdminApi(); // ✅ VPS API
  late AnimationController _animationController;
  int _selectedIndex = 0;

  // ✅ بيانات الشركات من VPS
  List<Tenant> _vpsTenants = [];
  bool _isLoadingVpsTenants = false;
  String? _vpsTenantsError;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // ✅ تحميل الشركات من VPS عند البدء
    _loadVpsTenants();
  }

  /// ✅ تحميل الشركات من VPS
  Future<void> _loadVpsTenants() async {
    if (_isLoadingVpsTenants) return;

    setState(() {
      _isLoadingVpsTenants = true;
      _vpsTenantsError = null;
    });

    try {
      final tenants = await _superAdminApi.getTenantsFromVps();
      if (mounted) {
        setState(() {
          _vpsTenants = tenants;
          _isLoadingVpsTenants = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _vpsTenantsError = e.toString();
          _isLoadingVpsTenants = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AdminTheme.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminTheme.dangerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.logout, color: AdminTheme.dangerColor),
            ),
            const SizedBox(width: 14),
            const Text('تسجيل الخروج',
                style: TextStyle(
                    color: AdminTheme.textPrimary,
                    fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text('هل تريد تسجيل الخروج من لوحة التحكم؟',
            style: TextStyle(color: AdminTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء',
                style: TextStyle(color: AdminTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminTheme.dangerColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // تسجيل الخروج من الخدمة المناسبة
      if (DataSourceConfig.useVpsApi) {
        await VpsAuthService.instance.logout();
      } else {
        await _authService.logout();
      }

      if (mounted) {
        // الانتقال لصفحة تسجيل الدخول المناسبة
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => DataSourceConfig.useVpsApi
                ? const VpsTenantLoginPage()
                : const TenantLoginPage(),
          ),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: AdminTheme.backgroundColor,
        ),
        child: SafeArea(
          child: Row(
            children: [
              // القائمة الجانبية العصرية
              _buildSidebar(),
              // المحتوى الرئيسي
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      child: _buildMainContent(),
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

  /// ✅ بناء المحتوى الرئيسي حسب التبويب المحدد
  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0:
        // ✅ لوحة التحكم الرئيسية مع الإحصائيات
        return _buildDashboardContent();
      case 1:
        // ✅ إدارة الشركات
        return const UnifiedCompaniesPage();
      case 5:
        // ✅ بوابة المواطن
        return _buildCitizenPortalContent();
      default:
        return _buildDashboardContent();
    }
  }

  Widget _buildSidebar() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Container(
          width: 280,
          decoration: BoxDecoration(
            color: AdminTheme.surfaceColor,
            border: const Border(
              left: BorderSide(color: AdminTheme.borderColor),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(-5, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              // رأس القائمة مع الشعار
              _buildSidebarHeader(),
              const SizedBox(height: 10),
              // عناصر القائمة في حاوية قابلة للتمرير
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildNavItem(0, Icons.dashboard_rounded, 'لوحة التحكم'),
                      _buildNavItem(1, Icons.business_rounded, 'إدارة الشركات'),
                      const Divider(color: Colors.white24, height: 20),
                      _buildNavItem(
                          5, Icons.people_alt_rounded, 'بوابة المواطن'),
                      const Divider(color: Colors.white24, height: 20),
                      _buildNavItem(3, Icons.cloud, 'بيانات Firebase'),
                      _buildNavItem(4, Icons.dns, 'بيانات VPS'),
                      _buildNavItem(
                          6, Icons.medical_services_rounded, 'تشخيص النظام'),
                    ],
                  ),
                ),
              ),
              // زر تسجيل الخروج
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildLogoutButton(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // شعار عصري
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AdminTheme.primaryColor, AdminTheme.accentColor],
              ),
              boxShadow: [
                BoxShadow(
                  color: AdminTheme.primaryColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [AdminTheme.primaryColor, AdminTheme.accentColor],
                ).createShader(bounds),
                child: const Icon(
                  Icons.admin_panel_settings,
                  size: 45,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            CustomAuthService.currentSuperAdmin?.name ?? 'مدير النظام',
            style: const TextStyle(
              color: AdminTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AdminTheme.primaryColor.withOpacity(0.1),
                  AdminTheme.accentColor.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AdminTheme.primaryColor.withOpacity(0.3),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: AdminTheme.primaryColor, size: 14),
                SizedBox(width: 6),
                Text(
                  'Super Admin',
                  style: TextStyle(
                    color: AdminTheme.primaryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddCompanyPage()),
              );
            } else if (index == 3) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FirebaseDataManagerPage()),
              );
            } else if (index == 4) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VpsDataManagerPage()),
              );
            } else if (index == 5) {
              // ✅ بوابة المواطن - التحقق من VPS فقط
              if (DataSourceConfig.useVpsApi) {
                setState(() => _selectedIndex = index);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('بوابة المواطن متاحة فقط مع VPS API'),
                    backgroundColor: AdminTheme.dangerColor,
                  ),
                );
              }
            } else if (index == 6) {
              // 🔧 فتح صفحة تشخيص النظام
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SystemDiagnosticsPage()),
              );
            } else {
              setState(() => _selectedIndex = index);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color:
                  isSelected ? AdminTheme.primaryColor.withOpacity(0.1) : null,
              border: isSelected
                  ? Border.all(color: AdminTheme.primaryColor.withOpacity(0.3))
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AdminTheme.primaryColor.withOpacity(0.15)
                        : AdminTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: isSelected
                        ? AdminTheme.primaryColor
                        : AdminTheme.textMuted,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? AdminTheme.primaryColor
                          : AdminTheme.textSecondary,
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AdminTheme.primaryColor,
                      boxShadow: [
                        BoxShadow(
                          color: AdminTheme.primaryColor.withOpacity(0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _logout,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: AdminTheme.dangerColor.withOpacity(0.1),
            border: Border.all(color: AdminTheme.dangerColor.withOpacity(0.3)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded,
                  color: AdminTheme.dangerColor, size: 20),
              SizedBox(width: 8),
              Text(
                'تسجيل الخروج',
                style: TextStyle(
                  color: AdminTheme.dangerColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor,
        border: const Border(
          bottom: BorderSide(color: AdminTheme.borderColor),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: const TextStyle(
                  color: AdminTheme.textMuted,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _getPageTitle(),
                style: const TextStyle(
                  color: AdminTheme.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Spacer(),
          // زر الإضافة السريعة
          _buildQuickAddButton(),
        ],
      ),
    );
  }

  /// ✅ عنوان الصفحة حسب التبويب
  String _getPageTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'لوحة التحكم';
      case 1:
        return 'إدارة الشركات';
      case 5:
        return 'بوابة المواطن';
      default:
        return 'لوحة التحكم';
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صباح الخير 🌅';
    if (hour < 17) return 'مساء الخير ☀️';
    return 'مساء الخير 🌙';
  }

  Widget _buildQuickAddButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddCompanyPage()),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AdminTheme.primaryColor, AdminTheme.accentColor],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AdminTheme.primaryColor.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.add_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'شركة جديدة',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardContent() {
    // ✅ استخدام VPS API بدلاً من Firebase
    if (_isLoadingVpsTenants) {
      return AdminTheme.buildLoadingIndicator();
    }

    if (_vpsTenantsError != null) {
      return AdminTheme.buildErrorWidget(
        message: 'خطأ: $_vpsTenantsError',
        onRetry: _loadVpsTenants,
      );
    }

    final tenants = _vpsTenants;
    return RefreshIndicator(
      onRefresh: _loadVpsTenants,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // زر التحديث
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _loadVpsTenants,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('تحديث'),
                  style: TextButton.styleFrom(
                    foregroundColor: AdminTheme.primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // بطاقات الإحصائيات
            _buildStatsCards(tenants),
            const SizedBox(height: 32),
            // قسم الشركات
            _buildCompaniesSection(tenants),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards(List<Tenant> tenants) {
    final totalTenants = tenants.length;
    final activeTenants =
        tenants.where((t) => t.isActive && !t.isExpired).length;
    final suspendedTenants = tenants.where((t) => !t.isActive).length;
    final expiredTenants = tenants.where((t) => t.isExpired).length;
    final expiringSoonTenants = tenants.where((t) => t.isExpiringSoon).length;
    final warningTenants = tenants.where((t) => t.needsWarning).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.analytics_outlined,
                color: AdminTheme.primaryColor, size: 22),
            SizedBox(width: 8),
            Text(
              'الإحصائيات',
              style: TextStyle(
                color: AdminTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              title: 'إجمالي الشركات',
              value: totalTenants.toString(),
              icon: Icons.business_rounded,
              gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              onTap: () => _showFilteredCompanies(
                  context, tenants, 'جميع الشركات', null),
            ),
            _buildStatCard(
              title: 'الشركات النشطة',
              value: activeTenants.toString(),
              icon: Icons.check_circle_rounded,
              gradient: const [Color(0xFF10B981), Color(0xFF34D399)],
              onTap: () => _showFilteredCompanies(context, tenants,
                  'الشركات النشطة', (t) => t.isActive && !t.isExpired),
            ),
            _buildStatCard(
              title: 'الشركات المعلقة',
              value: suspendedTenants.toString(),
              icon: Icons.pause_circle_rounded,
              gradient: const [Color(0xFFf093fb), Color(0xFFf5576c)],
              onTap: () => _showFilteredCompanies(
                  context, tenants, 'الشركات المعلقة', (t) => !t.isActive),
            ),
            _buildStatCard(
              title: 'اشتراكات منتهية',
              value: expiredTenants.toString(),
              icon: Icons.cancel_rounded,
              gradient: const [Color(0xFFeb3349), Color(0xFFf45c43)],
              onTap: () => _showFilteredCompanies(
                  context, tenants, 'اشتراكات منتهية', (t) => t.isExpired),
            ),
            _buildStatCard(
              title: 'تنتهي قريباً',
              value: expiringSoonTenants.toString(),
              icon: Icons.warning_rounded,
              gradient: const [Color(0xFFf7971e), Color(0xFFffd200)],
              onTap: () => _showFilteredCompanies(context, tenants,
                  'تنتهي خلال 7 أيام', (t) => t.isExpiringSoon),
            ),
            _buildStatCard(
              title: 'تحتاج تجديد',
              value: warningTenants.toString(),
              icon: Icons.schedule_rounded,
              gradient: const [Color(0xFF4facfe), Color(0xFF00f2fe)],
              onTap: () => _showFilteredCompanies(context, tenants,
                  'تحتاج تجديد (30 يوم)', (t) => t.needsWarning),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AdminTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminTheme.borderColor),
            boxShadow: [
              BoxShadow(
                color: gradient[0].withOpacity(0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          gradient[0].withOpacity(0.15),
                          gradient[1].withOpacity(0.1)
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: gradient[0], size: 22),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AdminTheme.textMuted,
                    size: 14,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: TextStyle(
                  color: gradient[0],
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(
                  color: AdminTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilteredCompanies(
    BuildContext context,
    List<Tenant> allTenants,
    String title,
    bool Function(Tenant)? filter,
  ) {
    final filteredTenants =
        filter != null ? allTenants.where(filter).toList() : allTenants;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AdminTheme.surfaceColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // مقبض السحب
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AdminTheme.borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // العنوان
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AdminTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AdminTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${filteredTenants.length}',
                        style: const TextStyle(
                          color: AdminTheme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon:
                          const Icon(Icons.close, color: AdminTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Divider(color: AdminTheme.borderColor, height: 1),
              // قائمة الشركات
              Expanded(
                child: filteredTenants.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_rounded,
                              size: 64,
                              color: AdminTheme.textMuted.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد شركات',
                              style: TextStyle(
                                color: AdminTheme.textMuted,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredTenants.length,
                        itemBuilder: (context, index) {
                          final tenant = filteredTenants[index];
                          return _buildCompanyListItem(context, tenant);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompaniesSection(List<Tenant> tenants) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Row(
              children: [
                Icon(Icons.business_rounded,
                    color: AdminTheme.primaryColor, size: 22),
                SizedBox(width: 8),
                Text(
                  'آخر الشركات',
                  style: TextStyle(
                    color: AdminTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _selectedIndex = 1),
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              label: const Text('عرض الكل'),
              style: TextButton.styleFrom(
                foregroundColor: AdminTheme.primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (tenants.isEmpty)
          _buildEmptyState()
        else
          ...tenants.take(5).map((tenant) => _buildCompanyCard(tenant)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.borderColor),
      ),
      child: Column(
        children: [
          Icon(
            Icons.business_rounded,
            size: 64,
            color: AdminTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد شركات بعد',
            style: TextStyle(
              color: AdminTheme.textMuted,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على زر "شركة جديدة" للبدء',
            style: TextStyle(
              color: AdminTheme.textMuted.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanyCard(Tenant tenant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showCompanyDetails(context, tenant),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AdminTheme.surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AdminTheme.borderColor),
              boxShadow: [
                BoxShadow(
                  color: _getStatusColor(tenant.status).withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // شعار الشركة
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _getStatusColor(tenant.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getStatusColor(tenant.status).withOpacity(0.3),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      tenant.name.isNotEmpty ? tenant.name[0] : '?',
                      style: TextStyle(
                        color: _getStatusColor(tenant.status),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // معلومات الشركة
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant.name,
                        style: const TextStyle(
                          color: AdminTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'كود: ${tenant.code}',
                        style: const TextStyle(
                          color: AdminTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // حالة الاشتراك
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildStatusBadge(tenant.status),
                    const SizedBox(height: 4),
                    Text(
                      tenant.isExpired
                          ? 'منتهي'
                          : '${tenant.daysRemaining} يوم',
                      style: TextStyle(
                        color: _getStatusColor(tenant.status),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AdminTheme.textMuted,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompanyListItem(BuildContext context, Tenant tenant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            _showCompanyDetails(context, tenant);
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _getStatusColor(tenant.status).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getStatusColor(tenant.status),
                        _getStatusColor(tenant.status).withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      tenant.name.isNotEmpty ? tenant.name[0] : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tenant.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'كود: ${tenant.code}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusBadge(tenant.status),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCompanyDetails(BuildContext context, Tenant tenant) {
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Color(0xFF1B263B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // مقبض السحب
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // رأس التفاصيل
            Container(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          _getStatusColor(tenant.status),
                          _getStatusColor(tenant.status).withOpacity(0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color:
                              _getStatusColor(tenant.status).withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        tenant.name.isNotEmpty ? tenant.name[0] : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tenant.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.tag,
                              size: 16,
                              color: Colors.white.withOpacity(0.5),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tenant.code,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 12),
                            _buildStatusBadge(tenant.status),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            // المحتوى
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // معلومات الاشتراك
                    _buildDetailSection(
                      title: 'معلومات الاشتراك',
                      icon: Icons.card_membership_rounded,
                      children: [
                        _buildDetailRow('تاريخ البدء',
                            dateFormat.format(tenant.subscriptionStart)),
                        _buildDetailRow('تاريخ الانتهاء',
                            dateFormat.format(tenant.subscriptionEnd)),
                        _buildDetailRow(
                            'الأيام المتبقية',
                            tenant.isExpired
                                ? 'منتهي'
                                : '${tenant.daysRemaining} يوم'),
                        _buildDetailRow('نوع الباقة',
                            _getPlanName(tenant.subscriptionPlan)),
                        _buildDetailRow(
                            'الحد الأقصى للمستخدمين', '${tenant.maxUsers}'),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // معلومات التواصل
                    _buildDetailSection(
                      title: 'معلومات التواصل',
                      icon: Icons.contact_mail_rounded,
                      children: [
                        _buildDetailRow(
                            'رقم الهاتف', tenant.phone ?? 'غير محدد'),
                        _buildDetailRow(
                            'العنوان', tenant.address ?? 'غير محدد'),
                      ],
                    ),
                    if (!tenant.isActive &&
                        tenant.suspensionReason != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.red.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'سبب التعليق: ${tenant.suspensionReason}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                    // أزرار الإجراءات
                    _buildActionButtons(context, tenant),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF00E5FF), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, Tenant tenant) {
    return Column(
      children: [
        // زر الدخول للشركة
        _buildActionButton(
          icon: Icons.login_rounded,
          label: 'الدخول للشركة',
          gradient: const [Color(0xFF667eea), Color(0xFF764ba2)],
          onTap: () {
            Navigator.pop(context);
            _enterCompany(tenant);
          },
        ),
        const SizedBox(height: 12),
        // زر إدارة ميزات الشركة
        _buildActionButton(
          icon: Icons.tune_rounded,
          label: 'إدارة ميزات الشركة',
          gradient: const [Color(0xFF11998e), Color(0xFF38ef7d)],
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TenantFeaturesPage(tenant: tenant),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.edit_rounded,
                label: 'تعديل',
                gradient: const [Color(0xFF4facfe), Color(0xFF00f2fe)],
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditCompanyPage(tenant: tenant),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: tenant.isActive
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                label: tenant.isActive ? 'تعليق' : 'تفعيل',
                gradient: tenant.isActive
                    ? const [Color(0xFFf093fb), Color(0xFFf5576c)]
                    : const [Color(0xFF11998e), Color(0xFF38ef7d)],
                onTap: () {
                  Navigator.pop(context);
                  if (tenant.isActive) {
                    _suspendCompany(context, tenant);
                  } else {
                    _reactivateCompany(context, tenant);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildActionButton(
          icon: Icons.delete_rounded,
          label: 'حذف الشركة',
          gradient: const [Color(0xFFeb3349), Color(0xFFf45c43)],
          onTap: () {
            Navigator.pop(context);
            _deleteCompany(context, tenant);
          },
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradient),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: gradient[0].withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enterCompany(Tenant tenant) {
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
          department: tenant.name,
          center: tenant.code,
          salary: '0',
          pageAccess: fullPermissions,
          tenantId: tenant.id,
          tenantCode: tenant.code,
          isSuperAdminMode: true,
        ),
      ),
      (route) => false,
    );
  }

  void _suspendCompany(BuildContext context, Tenant tenant) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              decoration: InputDecoration(
                labelText: 'سبب التعليق',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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

    if (confirm == true) {
      final tenantService = TenantService();
      await tenantService.suspendTenant(
        tenant.id,
        reasonController.text.trim().isEmpty
            ? 'تم التعليق بواسطة المدير'
            : reasonController.text.trim(),
      );
    }
  }

  void _reactivateCompany(BuildContext context, Tenant tenant) async {
    final tenantService = TenantService();
    await tenantService.reactivateTenant(tenant.id);
  }

  void _deleteCompany(BuildContext _, Tenant tenant) async {
    final tenantService = TenantService();

    // جلب عدد البيانات أولاً
    final dataCount = await tenantService.getTenantDataCount(tenant.id);

    if (!mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.delete_forever, color: Colors.red, size: 28),
            ),
            const SizedBox(width: 12),
            const Text(
              'حذف الشركة نهائياً',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red.withOpacity(0.1),
                    Colors.orange.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    tenant.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tenant.code,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // عرض البيانات التي سيتم حذفها
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'البيانات التي سيتم حذفها:',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildDeleteDataRow(
                      Icons.people, 'المستخدمون', '${dataCount.usersCount}'),
                  _buildDeleteDataRow(Icons.folder, 'البيانات الأخرى',
                      '${dataCount.otherDataCount}'),
                  const Divider(color: Colors.white24, height: 20),
                  _buildDeleteDataRow(Icons.storage, 'إجمالي السجلات',
                      '${dataCount.totalCount}',
                      isTotal: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تحذير: هذا الإجراء لا يمكن التراجع عنه!',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
            ),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever),
            label: const Text('حذف نهائي'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // عرض مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (loadingContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00E5FF)),
            const SizedBox(height: 20),
            const Text(
              'جاري حذف الشركة...',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'يتم حذف جميع البيانات والمستخدمين',
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
            ),
          ],
        ),
      ),
    );

    final result = await tenantService.deleteTenant(tenant.id);

    // إغلاق مؤشر التحميل
    if (!mounted) return;
    Navigator.of(context).pop();

    if (!mounted) return;

    // عرض نتيجة الحذف
    showDialog(
      context: context,
      builder: (resultContext) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: result.success
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                result.success ? Icons.check_circle : Icons.error,
                color: result.success ? Colors.green : Colors.red,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              result.success ? 'تم الحذف بنجاح!' : 'فشل الحذف',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (result.success) ...[
              Text(
                'تم حذف ${result.deletedUsers} مستخدم',
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
              if (result.deletedSubcollections > 0)
                Text(
                  'تم حذف ${result.deletedSubcollections} سجل إضافي',
                  style: TextStyle(color: Colors.white.withOpacity(0.7)),
                ),
            ] else
              Text(
                result.errorMessage ?? 'حدث خطأ غير متوقع',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(resultContext),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF00E5FF),
            ),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteDataRow(IconData icon, String label, String count,
      {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: isTotal ? const Color(0xFF00E5FF) : Colors.white54),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isTotal ? const Color(0xFF00E5FF) : Colors.white70,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isTotal
                  ? const Color(0xFF00E5FF).withOpacity(0.2)
                  : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              count,
              style: TextStyle(
                color: isTotal ? const Color(0xFF00E5FF) : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(SubscriptionStatus status) {
    String label;
    Color color;

    switch (status) {
      case SubscriptionStatus.active:
        label = 'نشط';
        color = const Color(0xFF38ef7d);
        break;
      case SubscriptionStatus.warning:
        label = 'تحذير';
        color = const Color(0xFFffd200);
        break;
      case SubscriptionStatus.critical:
        label = 'حرج';
        color = const Color(0xFFf45c43);
        break;
      case SubscriptionStatus.expired:
        label = 'منتهي';
        color = const Color(0xFFeb3349);
        break;
      case SubscriptionStatus.suspended:
        label = 'معلق';
        color = Colors.grey;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.active:
        return const Color(0xFF38ef7d);
      case SubscriptionStatus.warning:
        return const Color(0xFFffd200);
      case SubscriptionStatus.critical:
        return const Color(0xFFf45c43);
      case SubscriptionStatus.expired:
        return const Color(0xFFeb3349);
      case SubscriptionStatus.suspended:
        return Colors.grey;
    }
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

  // ✅ ====================== بوابة المواطن ======================

  /// محتوى صفحة بوابة المواطن للسوبر أدمن
  Widget _buildCitizenPortalContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس الصفحة
          _buildCitizenPortalHeader(),
          const SizedBox(height: 24),

          // بطاقات الإحصائيات السريعة
          _buildCitizenPortalStats(),
          const SizedBox(height: 32),

          // الأقسام الرئيسية
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // القسم الأيسر - إدارة سريعة
              Expanded(
                flex: 2,
                child: _buildQuickActionsSection(),
              ),
              const SizedBox(width: 24),
              // القسم الأيمن - الشركة المرتبطة
              Expanded(
                flex: 1,
                child: _buildLinkedCompanyInfo(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCitizenPortalHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF667eea).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.people_alt_rounded,
              color: Colors.white,
              size: 40,
            ),
          ),
          const SizedBox(width: 20),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نظام بوابة المواطن',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'إدارة المواطنين والاشتراكات والمدفوعات من مكان واحد',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // زر الانتقال للتطبيق الكامل
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const _CitizenPortalMainPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF667eea),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.open_in_new),
            label: const Text(
              'فتح النظام الكامل',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCitizenPortalStats() {
    // سيتم تحميلها من API لاحقاً
    final stats = [
      {
        'title': 'إجمالي المواطنين',
        'value': '1,247',
        'icon': Icons.people_outline,
        'color': const Color(0xFF38ef7d),
        'trend': '+12%',
      },
      {
        'title': 'الاشتراكات النشطة',
        'value': '893',
        'icon': Icons.wifi,
        'color': const Color(0xFF667eea),
        'trend': '+8%',
      },
      {
        'title': 'المدفوعات الشهرية',
        'value': '45.2M',
        'icon': Icons.payments_outlined,
        'color': const Color(0xFFffd200),
        'trend': '+15%',
      },
      {
        'title': 'تذاكر الدعم المفتوحة',
        'value': '23',
        'icon': Icons.support_agent,
        'color': const Color(0xFFf45c43),
        'trend': '-5%',
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
        childAspectRatio: 1.5,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        final color = stat['color'] as Color;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AdminTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdminTheme.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Icon(stat['icon'] as IconData, color: color, size: 22),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (stat['trend'] as String).startsWith('+')
                          ? const Color(0xFF38ef7d).withOpacity(0.1)
                          : const Color(0xFFf45c43).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      stat['trend'] as String,
                      style: TextStyle(
                        color: (stat['trend'] as String).startsWith('+')
                            ? const Color(0xFF38ef7d)
                            : const Color(0xFFf45c43),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                stat['value'] as String,
                style: const TextStyle(
                  color: AdminTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stat['title'] as String,
                style: const TextStyle(
                  color: AdminTheme.textMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickActionsSection() {
    final actions = [
      {
        'title': 'إدارة المواطنين',
        'subtitle': 'عرض وإضافة وتعديل بيانات المواطنين',
        'icon': Icons.people_alt_rounded,
        'color': const Color(0xFF38ef7d),
        'route': 'citizens',
      },
      {
        'title': 'إدارة الاشتراكات',
        'subtitle': 'متابعة وتفعيل وإلغاء الاشتراكات',
        'icon': Icons.card_membership_rounded,
        'color': const Color(0xFF667eea),
        'route': 'subscriptions',
      },
      {
        'title': 'المدفوعات',
        'subtitle': 'تسجيل ومتابعة المدفوعات',
        'icon': Icons.payments_rounded,
        'color': const Color(0xFFffd200),
        'route': 'payments',
      },
      {
        'title': 'باقات الإنترنت',
        'subtitle': 'إدارة باقات الاشتراك والأسعار',
        'icon': Icons.wifi_rounded,
        'color': const Color(0xFF764ba2),
        'route': 'plans',
      },
      {
        'title': 'تذاكر الدعم',
        'subtitle': 'الرد على استفسارات المواطنين',
        'icon': Icons.support_agent_rounded,
        'color': const Color(0xFFf45c43),
        'route': 'tickets',
      },
      {
        'title': 'التقارير',
        'subtitle': 'تقارير شاملة عن النظام',
        'icon': Icons.analytics_rounded,
        'color': const Color(0xFF00b4db),
        'route': 'reports',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.flash_on_rounded, color: AdminTheme.primaryColor),
              SizedBox(width: 8),
              Text(
                'الإجراءات السريعة',
                style: TextStyle(
                  color: AdminTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.8,
            ),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              final color = action['color'] as Color;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    // الانتقال للصفحة المطلوبة
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _CitizenPortalMainPage(
                          initialTab: action['route'] as String,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(action['icon'] as IconData,
                                  color: color, size: 20),
                            ),
                            const Spacer(),
                            Icon(Icons.arrow_forward_ios,
                                color: color, size: 14),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          action['title'] as String,
                          style: TextStyle(
                            color: color,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          action['subtitle'] as String,
                          style: const TextStyle(
                            color: AdminTheme.textMuted,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLinkedCompanyInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AdminTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AdminTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.business_rounded, color: AdminTheme.primaryColor),
              SizedBox(width: 8),
              Text(
                'الشركة المرتبطة',
                style: TextStyle(
                  color: AdminTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // معلومات الشركة - سيتم تحميلها من API
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF667eea).withOpacity(0.1),
                  const Color(0xFF764ba2).withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: const Color(0xFF667eea).withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667eea).withOpacity(0.2),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.wifi_rounded,
                    color: Color(0xFF667eea),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'شركة الصدارة للإنترنت',
                  style: TextStyle(
                    color: AdminTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38ef7d).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified, color: Color(0xFF38ef7d), size: 14),
                      SizedBox(width: 6),
                      Text(
                        'مرتبطة بنظام المواطن',
                        style: TextStyle(
                          color: Color(0xFF38ef7d),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // إحصائيات سريعة
          _buildCompanyStatItem('المشتركين النشطين', '893', Icons.people),
          const SizedBox(height: 8),
          _buildCompanyStatItem(
              'الإيرادات الشهرية', '45.2M د.ع', Icons.attach_money),
          const SizedBox(height: 8),
          _buildCompanyStatItem('نسبة التحصيل', '87%', Icons.trending_up),
        ],
      ),
    );
  }

  Widget _buildCompanyStatItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminTheme.backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AdminTheme.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AdminTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AdminTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ✅ صفحة بوابة المواطن الرئيسية (placeholder للنظام الكامل)
class _CitizenPortalMainPage extends StatefulWidget {
  final String? initialTab;
  const _CitizenPortalMainPage({this.initialTab});

  @override
  State<_CitizenPortalMainPage> createState() => _CitizenPortalMainPageState();
}

class _CitizenPortalMainPageState extends State<_CitizenPortalMainPage> {
  late String _currentTab;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab ?? 'citizens';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTabTitle(_currentTab)),
        backgroundColor: const Color(0xFF667eea),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // تحديث البيانات
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // القائمة الجانبية
          Container(
            width: 220,
            color: const Color(0xFF1a1a2e),
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildSideNavItem(
                    'citizens', Icons.people_alt_rounded, 'المواطنين'),
                _buildSideNavItem('subscriptions',
                    Icons.card_membership_rounded, 'الاشتراكات'),
                _buildSideNavItem(
                    'payments', Icons.payments_rounded, 'المدفوعات'),
                _buildSideNavItem('plans', Icons.wifi_rounded, 'الباقات'),
                _buildSideNavItem(
                    'tickets', Icons.support_agent_rounded, 'الدعم'),
                _buildSideNavItem(
                    'reports', Icons.analytics_rounded, 'التقارير'),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'بوابة المواطن v1.0',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // المحتوى
          Expanded(
            child: Container(
              color: const Color(0xFF0f0f1a),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getTabIcon(_currentTab),
                      size: 80,
                      color: const Color(0xFF667eea).withOpacity(0.5),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _getTabTitle(_currentTab),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'قيد التطوير - سيتم إضافة المحتوى قريباً',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideNavItem(String tab, IconData icon, String title) {
    final isSelected = _currentTab == tab;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _currentTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF667eea).withOpacity(0.2) : null,
            border: Border(
              right: BorderSide(
                color:
                    isSelected ? const Color(0xFF667eea) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF667eea) : Colors.white54,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF667eea) : Colors.white54,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTabTitle(String tab) {
    switch (tab) {
      case 'citizens':
        return 'إدارة المواطنين';
      case 'subscriptions':
        return 'إدارة الاشتراكات';
      case 'payments':
        return 'المدفوعات';
      case 'plans':
        return 'باقات الإنترنت';
      case 'tickets':
        return 'تذاكر الدعم';
      case 'reports':
        return 'التقارير';
      default:
        return 'بوابة المواطن';
    }
  }

  IconData _getTabIcon(String tab) {
    switch (tab) {
      case 'citizens':
        return Icons.people_alt_rounded;
      case 'subscriptions':
        return Icons.card_membership_rounded;
      case 'payments':
        return Icons.payments_rounded;
      case 'plans':
        return Icons.wifi_rounded;
      case 'tickets':
        return Icons.support_agent_rounded;
      case 'reports':
        return Icons.analytics_rounded;
      default:
        return Icons.dashboard_rounded;
    }
  }
}
