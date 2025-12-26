/// لوحة تحكم Super Admin الرئيسية - تصميم فخم
/// تعرض جميع الشركات مع إحصائيات وخيارات الإدارة
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../multi_tenant.dart';
import 'companies_list_page.dart';
import 'add_company_page.dart';
import 'edit_company_page.dart';
import 'tenant_features_page.dart';
import '../tenant_login_page.dart';
import '../home_page.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard>
    with SingleTickerProviderStateMixin {
  final CustomAuthService _authService = CustomAuthService();
  late AnimationController _animationController;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.logout, color: Colors.red),
            ),
            const SizedBox(width: 12),
            const Text('تسجيل الخروج'),
          ],
        ),
        content: const Text('هل تريد تسجيل الخروج من لوحة التحكم؟'),
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
      await _authService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const TenantLoginPage()),
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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF1B263B),
              Color(0xFF0D1B2A),
            ],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // القائمة الجانبية الفخمة
              _buildSidebar(),
              // المحتوى الرئيسي
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(),
                    Expanded(
                      child: _selectedIndex == 0
                          ? _buildDashboardContent()
                          : const CompaniesListPage(),
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

  Widget _buildSidebar() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Container(
          width: 280,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1a237e).withOpacity(0.95),
                const Color(0xFF0d47a1).withOpacity(0.95),
                const Color(0xFF01579B).withOpacity(0.95),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(5, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              // رأس القائمة مع الشعار
              _buildSidebarHeader(),
              const SizedBox(height: 20),
              // عناصر القائمة
              _buildNavItem(0, Icons.dashboard_rounded, 'لوحة التحكم'),
              _buildNavItem(1, Icons.business_rounded, 'إدارة الشركات'),
              _buildNavItem(2, Icons.add_business_rounded, 'إضافة شركة'),
              const Spacer(),
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
          // شعار متحرك
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    colors: const [
                      Color(0xFF00E5FF),
                      Colors.transparent,
                      Color(0xFF00E5FF),
                    ],
                    transform:
                        GradientRotation(_animationController.value * 6.28),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF1a237e), Color(0xFF0d47a1)],
                    ),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Text(
            CustomAuthService.currentSuperAdmin?.name ?? 'مدير النظام',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF00E5FF).withOpacity(0.5),
              ),
            ),
            child: const Text(
              '⚡ Super Admin',
              style: TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
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
            } else {
              setState(() => _selectedIndex = index);
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: isSelected
                  ? LinearGradient(
                      colors: [
                        const Color(0xFF00E5FF).withOpacity(0.3),
                        const Color(0xFF00E5FF).withOpacity(0.1),
                      ],
                    )
                  : null,
              border: isSelected
                  ? Border.all(
                      color: const Color(0xFF00E5FF).withOpacity(0.5),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? const Color(0xFF00E5FF)
                      : Colors.white.withOpacity(0.7),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFF00E5FF)
                        : Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF00E5FF),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF00E5FF),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ],
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.red.withOpacity(0.5)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'تسجيل الخروج',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
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
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _getGreeting(),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _selectedIndex == 0 ? 'لوحة التحكم' : 'إدارة الشركات',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00E5FF), Color(0xFF00B8D4)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E5FF).withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.add_rounded, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'شركة جديدة',
                style: TextStyle(
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

  Widget _buildDashboardContent() {
    return StreamBuilder<List<Tenant>>(
      stream: _authService.getAllTenants(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'خطأ: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        }

        final tenants = snapshot.data ?? [];
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // بطاقات الإحصائيات
              _buildStatsCards(tenants),
              const SizedBox(height: 32),
              // قسم الشركات
              _buildCompaniesSection(tenants),
            ],
          ),
        );
      },
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
        const Text(
          '📊 الإحصائيات',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
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
              gradient: const [Color(0xFF667eea), Color(0xFF764ba2)],
              onTap: () => _showFilteredCompanies(
                  context, tenants, 'جميع الشركات', null),
            ),
            _buildStatCard(
              title: 'الشركات النشطة',
              value: activeTenants.toString(),
              icon: Icons.check_circle_rounded,
              gradient: const [Color(0xFF11998e), Color(0xFF38ef7d)],
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
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 180,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: gradient[0].withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 8),
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
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Colors.white, size: 24),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white54,
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
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
              // العنوان
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00E5FF).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${filteredTenants.length}',
                        style: const TextStyle(
                          color: Color(0xFF00E5FF),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
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
                              color: Colors.white.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا توجد شركات',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
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
            const Text(
              '🏢 آخر الشركات',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _selectedIndex = 1),
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              label: const Text('عرض الكل'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00E5FF),
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
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.business_rounded,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'لا توجد شركات بعد',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على زر "شركة جديدة" للبدء',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
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
                // شعار الشركة
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getStatusColor(tenant.status),
                        _getStatusColor(tenant.status).withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      tenant.name.isNotEmpty ? tenant.name[0] : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
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
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'كود: ${tenant.code}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
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
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withOpacity(0.3),
                  size: 16,
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
}
