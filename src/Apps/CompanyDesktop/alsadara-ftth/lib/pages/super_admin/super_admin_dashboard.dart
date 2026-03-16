/// لوحة تحكم Super Admin الرئيسية - تصميم Energy Dashboard
/// مستوحى من تصاميم Energy Management Dashboard العصرية
/// خلفية داكنة + ألوان نيون متوهجة + Glassmorphism
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:google_fonts/google_fonts.dart';
import '../../utils/responsive_helper.dart';
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
import '../login/premium_login_page.dart'; // ✨ صفحة تسجيل الدخول الفخمة
import '../home_page.dart';
import '../../theme/energy_dashboard_theme.dart'; // 🔋 ثيم Energy Dashboard الموحد
import '../diagnostics/system_diagnostics_page.dart'; // 🔧 صفحة التشخيص
import '../../permissions/permissions.dart';
import '../account/account_info_page.dart'; // ✅ صفحة معلومات الحساب
import '../admin/database_admin_page.dart'; // ✅ صفحة إدارة قاعدة البيانات
import 'energy_dashboard_home.dart'; // 🔋 الشاشة الرئيسية بتصميم Energy Dashboard
import 'subscription_logs_page.dart'; // 📋 سجلات الاشتراكات
import 'agents_management_page.dart'; // 👤 إدارة الوكلاء
import 'service_requests_page.dart'; // 📋 طلبات الخدمة
import 'sadara_portal_page.dart'; // 🌐 منصة الصدارة
import 'plans_management_page.dart'; // 💰 إدارة الباقات والأسعار

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
  int _selectedIndex = 0; // 🏠 البدء في الشاشة الرئيسية
  bool _isSidebarCollapsed = false; // ✅ حالة إخفاء/إظهار الشريط الجانبي

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
          _vpsTenantsError = 'حدث خطأ';
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
        backgroundColor: EnergyDashboardTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                boxShadow: EnergyDashboardTheme.glowCustom(
                  EnergyDashboardTheme.danger,
                  intensity: 0.2,
                ),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: EnergyDashboardTheme.danger,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              'تسجيل الخروج',
              style: GoogleFonts.cairo(
                color: EnergyDashboardTheme.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'هل تريد تسجيل الخروج من لوحة التحكم؟',
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'إلغاء',
              style: GoogleFonts.cairo(
                color: EnergyDashboardTheme.textMuted,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: EnergyDashboardTheme.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'تسجيل الخروج',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
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
        // الانتقال لصفحة تسجيل الدخول
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => const PremiumLoginPage(),
          ),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return Scaffold(
      drawer: r.showSidebar
          ? null
          : Drawer(
              width: 260,
              backgroundColor: const Color(0xFF0F172A),
              child: SafeArea(
                child: _buildEnergySidebar(forDrawer: true),
              ),
            ),
      body: Container(
        decoration: const BoxDecoration(
          // 🔋 خلفية Energy Dashboard - أسود مزرق عميق
          gradient: EnergyDashboardTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: Row(
            children: [
              // 🎨 القائمة الجانبية بتصميم Energy Dashboard
              if (r.showSidebar) _buildEnergySidebar(),
              // المحتوى الرئيسي
              Expanded(
                child: Column(
                  children: [
                    // الشريط العلوي
                    _buildEnergyTopBar(),
                    // المحتوى
                    Expanded(child: _buildMainContent()),
                    // الشريط السفلي
                    _buildEnergyFooter(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔋 Energy Dashboard - الشريط العلوي
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEnergyTopBar() {
    final r = context.responsive;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: r.contentPaddingH,
        vertical: r.isMobile ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgSecondary,
        border: const Border(
          bottom: BorderSide(color: EnergyDashboardTheme.borderColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: EnergyDashboardTheme.neonGreen.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // زر القائمة للشاشات الصغيرة
          if (!r.showSidebar) ...[
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white70),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
            const SizedBox(width: 8),
          ],
          // شعار الصدارة مع توهج نيون
          Row(
            children: [
              Container(
                width: r.isMobile ? 36 : 42,
                height: r.isMobile ? 36 : 42,
                decoration: BoxDecoration(
                  gradient: EnergyDashboardTheme.neonGreenGradient,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: EnergyDashboardTheme.glowCustom(
                    EnergyDashboardTheme.neonGreen,
                    intensity: 0.3,
                  ),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: EnergyDashboardTheme.bgPrimary,
                  size: r.isMobile ? 20 : 24,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'منصة الصدارة',
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: r.titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'لوحة تحكم مدير النظام',
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.neonGreen,
                      fontSize: r.captionSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          // أزرار الإجراءات السريعة
          if (!r.isMobile) ...[
            _buildTopBarAction(
              icon: Icons.notifications_outlined,
              color: EnergyDashboardTheme.neonBlue,
              badge: '3',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBarAction({
    required IconData icon,
    required Color color,
    String? badge,
  }) {
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        if (badge != null)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.danger,
                shape: BoxShape.circle,
                boxShadow: EnergyDashboardTheme.glowCustom(
                  EnergyDashboardTheme.danger,
                  intensity: 0.4,
                ),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔋 Energy Dashboard - الشريط السفلي
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEnergyFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgSecondary,
        border: const Border(
          top: BorderSide(color: EnergyDashboardTheme.borderColor, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.neonGreen,
                  shape: BoxShape.circle,
                  boxShadow: EnergyDashboardTheme.glowCustom(
                    EnergyDashboardTheme.neonGreen,
                    intensity: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'متصل بالخادم',
                style: GoogleFonts.cairo(
                  color: EnergyDashboardTheme.neonGreen,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Text(
            '© 2026 منصة الصدارة. جميع الحقوق محفوظة.',
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔋 Energy Dashboard - القائمة الجانبية
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEnergySidebar({bool forDrawer = false}) {
    final r = context.responsive;
    final sidebarWidth = forDrawer
        ? 260.0
        : (_isSidebarCollapsed ? 50.0 : r.sidebarExpandedWidth);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: sidebarWidth,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        border: const Border(
          left: BorderSide(color: Color(0xFF334155), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),

          // جميع عناصر القائمة
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              children: [
                _buildEnergyNavItem(
                  index: 0,
                  icon: Icons.dashboard_rounded,
                  label: 'الرئيسية',
                  color: EnergyDashboardTheme.neonGreen,
                ),
                _buildEnergyNavItem(
                  index: 1,
                  icon: Icons.business_rounded,
                  label: 'إدارة الشركات',
                  color: EnergyDashboardTheme.neonBlue,
                ),
                _buildEnergyNavItem(
                  index: 2,
                  icon: Icons.support_agent_rounded,
                  label: 'الوكلاء',
                  color: EnergyDashboardTheme.neonPink,
                ),
                _buildEnergyNavItem(
                  index: 5,
                  icon: Icons.people_outline_rounded,
                  label: 'بوابة المواطن',
                  color: EnergyDashboardTheme.neonPurple,
                ),
                _buildEnergyNavItem(
                  index: 6,
                  icon: Icons.monitor_heart_rounded,
                  label: 'تشخيص النظام',
                  color: EnergyDashboardTheme.neonOrange,
                ),
                _buildEnergyNavItem(
                  index: 3,
                  icon: Icons.cloud_outlined,
                  label: 'بيانات Firebase',
                  color: EnergyDashboardTheme.neonOrange,
                ),
                _buildEnergyNavItem(
                  index: 4,
                  icon: Icons.dns_outlined,
                  label: 'بيانات VPS',
                  color: EnergyDashboardTheme.neonBlue,
                ),
                _buildEnergyNavItem(
                  index: 8,
                  icon: Icons.storage_outlined,
                  label: 'قاعدة البيانات',
                  color: EnergyDashboardTheme.neonPurple,
                ),
                _buildEnergyNavItem(
                  index: 9,
                  icon: Icons.receipt_long_rounded,
                  label: 'سجلات الاشتراكات',
                  color: EnergyDashboardTheme.neonGreen,
                ),
                _buildEnergyNavItem(
                  index: 10,
                  icon: Icons.assignment_rounded,
                  label: 'طلبات الخدمة',
                  color: EnergyDashboardTheme.neonPink,
                ),
                _buildEnergyNavItem(
                  index: 11,
                  icon: Icons.hub_rounded,
                  label: 'منصة الصدارة',
                  color: EnergyDashboardTheme.neonPurple,
                ),
                _buildEnergyNavItem(
                  index: 7,
                  icon: Icons.settings_outlined,
                  label: 'الإعدادات',
                  color: EnergyDashboardTheme.textOnDarkSecondary,
                ),
                const SizedBox(height: 4),
                _buildEnergyLogoutItem(),
              ],
            ),
          ),

          // زر طي القائمة
          GestureDetector(
            onTap: () =>
                setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Center(
                child: Icon(
                  _isSidebarCollapsed
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                  color: EnergyDashboardTheme.textOnDarkMuted,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnergySidebarHeader() {
    return Container(
      padding: EdgeInsets.all(_isSidebarCollapsed ? 8 : 12),
      child: Column(
        children: [
          // الشعار
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: EnergyDashboardTheme.neonGreenGradient,
              boxShadow: EnergyDashboardTheme.glowCustom(
                EnergyDashboardTheme.neonGreen,
                intensity: 0.3,
              ),
            ),
            child: Container(
              padding: EdgeInsets.all(_isSidebarCollapsed ? 8 : 10),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0F172A),
              ),
              child: Icon(
                Icons.shield_rounded,
                size: _isSidebarCollapsed ? 18 : 22,
                color: EnergyDashboardTheme.neonGreen,
              ),
            ),
          ),

          if (!_isSidebarCollapsed) ...[
            const SizedBox(height: 8),
            Text(
              VpsAuthService.instance.currentSuperAdmin?.fullName ??
                  CustomAuthService.currentSuperAdmin?.name ??
                  'مدير النظام',
              style: GoogleFonts.cairo(
                color: EnergyDashboardTheme.textOnDark,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: EnergyDashboardTheme.neonGreenGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified_rounded,
                    color: EnergyDashboardTheme.bgPrimary,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Super Admin',
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.bgPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnergyNavItem({
    required int index,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isSelected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (index == 5 && !DataSourceConfig.useVpsApi) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'بوابة المواطن متاحة فقط مع VPS API',
                    style: GoogleFonts.cairo(),
                  ),
                  backgroundColor: EnergyDashboardTheme.danger,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            } else {
              setState(() => _selectedIndex = index);
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarCollapsed ? 6 : 8,
              vertical: 6,
            ),
            decoration: isSelected
                ? EnergyDashboardTheme.sidebarActiveItem(color)
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: color.withOpacity(0.15),
                      width: 1,
                    ),
                    color: color.withOpacity(0.04),
                  ),
            child: _isSidebarCollapsed
                ? Center(
                    child: Tooltip(
                      message: label,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withOpacity(0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          icon,
                          size: 18,
                          color: isSelected
                              ? color
                              : EnergyDashboardTheme.textOnDarkMuted,
                        ),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: color.withOpacity(isSelected ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: isSelected
                              ? EnergyDashboardTheme.glowCustom(color,
                                  intensity: 0.2)
                              : null,
                        ),
                        child: Icon(
                          icon,
                          size: 16,
                          color: isSelected
                              ? color
                              : EnergyDashboardTheme.textOnDarkMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          label,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? EnergyDashboardTheme.textOnDark
                                : EnergyDashboardTheme.textOnDarkSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: EnergyDashboardTheme.glowCustom(color,
                                intensity: 0.5),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnergyLogoutItem() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _logout,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _isSidebarCollapsed ? 6 : 8,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.danger.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isSidebarCollapsed
              ? Center(
                  child: Tooltip(
                    message: 'خروج',
                    child: Icon(
                      Icons.logout_rounded,
                      size: 14,
                      color: EnergyDashboardTheme.danger,
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      size: 14,
                      color: EnergyDashboardTheme.danger,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'خروج',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: EnergyDashboardTheme.danger,
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
        // 🏠 الشاشة الرئيسية - Energy Dashboard Home
        return const EnergyDashboardHome();
      case 1:
        // ✅ إدارة الشركات
        return const UnifiedCompaniesPage();
      case 2:
        // 👤 إدارة الوكلاء
        return const AgentsManagementPage();
      case 3:
        // ✅ بيانات Firebase
        return const FirebaseDataManagerPage();
      case 4:
        // ✅ بيانات VPS
        return const VpsDataManagerPage();
      case 5:
        // ✅ بوابة المواطن
        return _buildCitizenPortalContent();
      case 6:
        // ✅ تشخيص النظام
        return const SystemDiagnosticsPage();
      case 7:
        // ✅ حسابي
        return const AccountInfoPage();
      case 8:
        // ✅ إدارة قاعدة البيانات
        return const DatabaseAdminPage();
      case 9:
        // 📋 سجلات الاشتراكات
        return const SubscriptionLogsPage();
      case 10:
        // 📋 طلبات الخدمة
        return const ServiceRequestsManagementPage();
      case 11:
        // 🌐 منصة الصدارة
        return const SadaraPortalPage();
      default:
        // 🏠 الافتراضي: الشاشة الرئيسية
        return const EnergyDashboardHome();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 🎨 القائمة الجانبية بالتصميم الجديد (Al-Sadara Theme)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNewSidebar() {
    // الحصول على حجم الشاشة
    final screenWidth = MediaQuery.of(context).size.width;
    final sidebarWidth =
        _isSidebarCollapsed ? 56.0 : (screenWidth < 800 ? 150.0 : 170.0);

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgSidebar,
        border: Border(
          left: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // عناصر القائمة الرئيسية
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNewNavItem(
                    index: 0,
                    icon: Icons.dashboard_rounded,
                    label: 'الرئيسية',
                  ),
                  const SizedBox(height: 2),
                  _buildNewNavItem(
                    index: 1,
                    icon: Icons.business_rounded,
                    label: 'إدارة الشركات',
                  ),
                  const SizedBox(height: 2),
                  _buildNewNavItem(
                    index: 5,
                    icon: Icons.people_outline_rounded,
                    label: 'بوابة المواطن',
                  ),
                  const SizedBox(height: 2),
                  _buildNewNavItem(
                    index: 6,
                    icon: Icons.monitor_heart_rounded,
                    label: 'تشخيص النظام',
                  ),
                  const SizedBox(height: 2),
                  _buildNewNavItem(
                    index: 3,
                    icon: Icons.cloud_outlined,
                    label: 'بيانات Firebase',
                  ),
                  const SizedBox(height: 2),
                  _buildNewNavItem(
                    index: 4,
                    icon: Icons.dns_outlined,
                    label: 'بيانات VPS',
                  ),
                  const SizedBox(height: 2),
                  _buildNewNavItem(
                    index: 8,
                    icon: Icons.storage_outlined,
                    label: 'قاعدة البيانات',
                  ),
                  const SizedBox(height: 2),
                  _buildNewNavItem(
                    index: 11,
                    icon: Icons.hub_rounded,
                    label: 'منصة الصدارة',
                  ),
                  const SizedBox(height: 2),
                  _buildNewNavItem(
                    index: 7,
                    icon: Icons.settings_outlined,
                    label: 'الإعدادات',
                  ),
                ],
              ),
            ),
          ),

          // تسجيل الخروج في الأسفل
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildLogoutItem(),
          ),

          const SizedBox(height: 8),

          // زر طي القائمة
          GestureDetector(
            onTap: () =>
                setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF152238),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  _isSidebarCollapsed
                      ? Icons.chevron_right
                      : Icons.chevron_left,
                  color: const Color(0xFF64748B),
                  size: 18,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// عنصر قائمة بالتصميم الجديد
  Widget _buildNewNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedIndex == index;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (index == 5 && !DataSourceConfig.useVpsApi) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('بوابة المواطن متاحة فقط مع VPS API'),
                backgroundColor: const Color(0xFFEF4444),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            );
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _isSidebarCollapsed ? 8 : 10,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF3B82F6).withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: const Color(0xFF3B82F6).withOpacity(0.4))
                : null,
          ),
          child: _isSidebarCollapsed
              ? Center(
                  child: Tooltip(
                    message: label,
                    child: Icon(
                      icon,
                      size: 20,
                      color: isSelected
                          ? EnergyDashboardTheme.neonBlue
                          : EnergyDashboardTheme.textOnDarkMuted,
                    ),
                  ),
                )
              : Row(
                  children: [
                    Icon(
                      icon,
                      size: 18,
                      color: isSelected
                          ? EnergyDashboardTheme.neonBlue
                          : EnergyDashboardTheme.textOnDarkMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected
                              ? EnergyDashboardTheme.textOnDark
                              : EnergyDashboardTheme.textOnDarkSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// عنصر تسجيل الخروج
  Widget _buildLogoutItem() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _logout,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: _isSidebarCollapsed ? 8 : 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withOpacity(0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: _isSidebarCollapsed
              ? Center(
                  child: Tooltip(
                    message: 'تسجيل الخروج',
                    child: Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 14,
                      color: const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'خروج',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPremiumSidebar() {
    return _buildNewSidebar();
  }

  Widget _buildPremiumSidebarHeader() {
    return Container(
      padding: EdgeInsets.all(_isSidebarCollapsed ? 12 : 16),
      child: Column(
        children: [
          // زر إخفاء/إظهار
          Row(
            mainAxisAlignment: _isSidebarCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.spaceBetween,
            children: [
              if (!_isSidebarCollapsed)
                // الشعار النصي
                ShaderMask(
                  shaderCallback: (bounds) =>
                      EnergyDashboardTheme.primaryGradient.createShader(bounds),
                  child: const Text(
                    'SADARA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              IconButton(
                onPressed: () =>
                    setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
                icon: Icon(
                  _isSidebarCollapsed
                      ? Icons.keyboard_double_arrow_left
                      : Icons.keyboard_double_arrow_right,
                  color: Colors.white.withOpacity(0.6),
                  size: 18,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: _isSidebarCollapsed ? 10 : 14),

          // الشعار والمعلومات
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: EnergyDashboardTheme.primaryGradient,
              boxShadow:
                  EnergyDashboardTheme.glowShadow(EnergyDashboardTheme.primary),
            ),
            child: Container(
              padding: EdgeInsets.all(_isSidebarCollapsed ? 10 : 12),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: EnergyDashboardTheme.bgDark,
              ),
              child: Icon(
                Icons.shield_rounded,
                size: _isSidebarCollapsed ? 20 : 26,
                color: Colors.white,
              ),
            ),
          ),

          if (!_isSidebarCollapsed) ...[
            const SizedBox(height: 10),
            Text(
              VpsAuthService.instance.currentSuperAdmin?.fullName ??
                  CustomAuthService.currentSuperAdmin?.name ??
                  'مدير النظام',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: EnergyDashboardTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: Colors.white.withOpacity(0.9),
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Super Admin',
                    style: TextStyle(
                      color: Colors.white,
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
    );
  }

  Widget _buildPremiumNavItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: _isSidebarCollapsed ? title : '',
          preferBelow: false,
          child: InkWell(
            onTap: () {
              if (index == 5 && !DataSourceConfig.useVpsApi) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('بوابة المواطن متاحة فقط مع VPS API'),
                    backgroundColor: EnergyDashboardTheme.danger,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                );
              } else {
                setState(() => _selectedIndex = index);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                horizontal: _isSidebarCollapsed ? 10 : 12,
                vertical: 10,
              ),
              decoration: isSelected
                  ? EnergyDashboardTheme.sidebarActiveDecoration
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.transparent,
                    ),
              child: Row(
                mainAxisAlignment: _isSidebarCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withOpacity(0.6),
                    size: 20,
                  ),
                  if (!_isSidebarCollapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withOpacity(0.7),
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelected)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withOpacity(0.5),
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
      ),
    );
  }

  Widget _buildPremiumLogoutButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _logout,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: 14,
            horizontal: _isSidebarCollapsed ? 12 : 16,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: EnergyDashboardTheme.danger.withOpacity(0.15),
            border: Border.all(
              color: EnergyDashboardTheme.danger.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: _isSidebarCollapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.center,
            children: [
              Icon(
                Icons.logout_rounded,
                color: EnergyDashboardTheme.danger,
                size: 20,
              ),
              if (!_isSidebarCollapsed) ...[
                const SizedBox(width: 10),
                const Text(
                  'تسجيل الخروج',
                  style: TextStyle(
                    color: EnergyDashboardTheme.danger,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // القائمة الجانبية القديمة (للمرجع)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSidebar() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.surfaceColor,
            border: const Border(
              left: BorderSide(color: EnergyDashboardTheme.borderColor),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(-5, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              // رأس القائمة مع الشعار
              _buildSidebarHeader(),
              // عناصر القائمة في حاوية قابلة للتمرير
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildNavItem(1, Icons.business_rounded, 'إدارة الشركات'),
                      _buildNavItem(
                          5, Icons.people_alt_rounded, 'بوابة المواطن'),
                      if (!_isSidebarCollapsed)
                        const Divider(
                            color: Colors.white24,
                            height: 8,
                            indent: 16,
                            endIndent: 16),
                      _buildNavItem(3, Icons.cloud, 'بيانات Firebase'),
                      _buildNavItem(4, Icons.dns, 'بيانات VPS'),
                      _buildNavItem(8, Icons.storage, 'إدارة قاعدة البيانات'),
                      _buildNavItem(11, Icons.hub_rounded, 'منصة الصدارة'),
                      _buildNavItem(
                          6, Icons.medical_services_rounded, 'تشخيص النظام'),
                      if (!_isSidebarCollapsed)
                        const Divider(
                            color: Colors.white24,
                            height: 8,
                            indent: 16,
                            endIndent: 16),
                      _buildNavItem(7, Icons.person, 'حسابي'),
                    ],
                  ),
                ),
              ),
              // زر تسجيل الخروج
              Padding(
                padding: EdgeInsets.all(_isSidebarCollapsed ? 8 : 12),
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
      padding: EdgeInsets.all(_isSidebarCollapsed ? 12 : 16),
      child: Column(
        children: [
          // زر إخفاء/إظهار الشريط الجانبي
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () =>
                  setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
              icon: Icon(
                _isSidebarCollapsed ? Icons.menu_open : Icons.menu,
                color: EnergyDashboardTheme.textMuted,
                size: 22,
              ),
              tooltip: _isSidebarCollapsed ? 'توسيع القائمة' : 'تصغير القائمة',
              style: IconButton.styleFrom(
                backgroundColor: EnergyDashboardTheme.backgroundColor,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          SizedBox(height: _isSidebarCollapsed ? 8 : 12),
          // شعار عصري
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  EnergyDashboardTheme.primaryColor,
                  EnergyDashboardTheme.accentColor
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: EnergyDashboardTheme.primaryColor.withOpacity(0.3),
                  blurRadius: 15,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Container(
              padding: EdgeInsets.all(_isSidebarCollapsed ? 10 : 14),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    EnergyDashboardTheme.primaryColor,
                    EnergyDashboardTheme.accentColor
                  ],
                ).createShader(bounds),
                child: Icon(
                  Icons.admin_panel_settings,
                  size: _isSidebarCollapsed ? 24 : 36,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (!_isSidebarCollapsed) ...[
            const SizedBox(height: 12),
            Text(
              CustomAuthService.currentSuperAdmin?.name ?? 'مدير النظام',
              style: const TextStyle(
                color: EnergyDashboardTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    EnergyDashboardTheme.primaryColor.withOpacity(0.1),
                    EnergyDashboardTheme.accentColor.withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: EnergyDashboardTheme.primaryColor.withOpacity(0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified,
                      color: EnergyDashboardTheme.primaryColor, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'Super Admin',
                    style: TextStyle(
                      color: EnergyDashboardTheme.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: _isSidebarCollapsed ? 10 : 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: _isSidebarCollapsed ? title : '',
          preferBelow: false,
          child: InkWell(
            onTap: () {
              if (index == 2) {
                // إضافة شركة - فتح صفحة جديدة
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddCompanyPage()),
                );
              } else if (index == 5) {
                // ✅ بوابة المواطن - التحقق من VPS فقط
                if (DataSourceConfig.useVpsApi) {
                  setState(() => _selectedIndex = index);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('بوابة المواطن متاحة فقط مع VPS API'),
                      backgroundColor: EnergyDashboardTheme.dangerColor,
                    ),
                  );
                }
              } else {
                // ✅ جميع الشاشات الأخرى تظهر في المحتوى الرئيسي
                setState(() => _selectedIndex = index);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: _isSidebarCollapsed ? 8 : 12,
                vertical: _isSidebarCollapsed ? 10 : 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isSelected
                    ? EnergyDashboardTheme.primaryColor.withOpacity(0.1)
                    : null,
                border: isSelected
                    ? Border.all(
                        color:
                            EnergyDashboardTheme.primaryColor.withOpacity(0.3))
                    : null,
              ),
              child: Row(
                mainAxisAlignment: _isSidebarCollapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: isSelected
                        ? EnergyDashboardTheme.primaryColor
                        : EnergyDashboardTheme.textMuted,
                    size: _isSidebarCollapsed ? 22 : 18,
                  ),
                  if (!_isSidebarCollapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: isSelected
                              ? EnergyDashboardTheme.primaryColor
                              : EnergyDashboardTheme.textSecondary,
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSelected)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: EnergyDashboardTheme.primaryColor,
                          boxShadow: [
                            BoxShadow(
                              color: EnergyDashboardTheme.primaryColor
                                  .withOpacity(0.4),
                              blurRadius: 6,
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
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Tooltip(
      message: _isSidebarCollapsed ? 'تسجيل الخروج' : '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _logout,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: _isSidebarCollapsed ? 12 : 10,
              horizontal: _isSidebarCollapsed ? 12 : 0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: EnergyDashboardTheme.dangerColor.withOpacity(0.1),
              border: Border.all(
                  color: EnergyDashboardTheme.dangerColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded,
                    color: EnergyDashboardTheme.dangerColor, size: 18),
                if (!_isSidebarCollapsed) ...[
                  const SizedBox(width: 6),
                  const Text(
                    'تسجيل الخروج',
                    style: TextStyle(
                      color: EnergyDashboardTheme.dangerColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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

  // تم نقل _buildTopBar للأعلى في التصميم الجديد

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
              colors: [
                EnergyDashboardTheme.primaryColor,
                EnergyDashboardTheme.accentColor
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: EnergyDashboardTheme.primaryColor.withOpacity(0.3),
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
      return EnergyDashboardTheme.buildLoadingIndicator();
    }

    if (_vpsTenantsError != null) {
      return EnergyDashboardTheme.buildErrorWidget(
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
                    foregroundColor: EnergyDashboardTheme.primaryColor,
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
                color: EnergyDashboardTheme.primaryColor, size: 22),
            SizedBox(width: 8),
            Text(
              'الإحصائيات',
              style: TextStyle(
                color: EnergyDashboardTheme.textPrimary,
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
              gradient: const [
                EnergyDashboardTheme.danger,
                EnergyDashboardTheme.neonPink
              ],
              onTap: () => _showFilteredCompanies(
                  context, tenants, 'اشتراكات منتهية', (t) => t.isExpired),
            ),
            _buildStatCard(
              title: 'تنتهي قريباً',
              value: expiringSoonTenants.toString(),
              icon: Icons.warning_rounded,
              gradient: const [
                EnergyDashboardTheme.neonOrange,
                EnergyDashboardTheme.neonYellow
              ],
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
            color: EnergyDashboardTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EnergyDashboardTheme.borderColor),
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
                    color: EnergyDashboardTheme.textMuted,
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
                  color: EnergyDashboardTheme.textSecondary,
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
            color: EnergyDashboardTheme.surfaceColor,
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
                  color: EnergyDashboardTheme.borderColor,
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
                        color: EnergyDashboardTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            EnergyDashboardTheme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${filteredTenants.length}',
                        style: const TextStyle(
                          color: EnergyDashboardTheme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close,
                          color: EnergyDashboardTheme.textMuted),
                    ),
                  ],
                ),
              ),
              const Divider(color: EnergyDashboardTheme.borderColor, height: 1),
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
                              color: EnergyDashboardTheme.textMuted
                                  .withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد شركات',
                              style: TextStyle(
                                color: EnergyDashboardTheme.textMuted,
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
                    color: EnergyDashboardTheme.primaryColor, size: 22),
                SizedBox(width: 8),
                Text(
                  'آخر الشركات',
                  style: TextStyle(
                    color: EnergyDashboardTheme.textPrimary,
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
                foregroundColor: EnergyDashboardTheme.primaryColor,
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
        color: EnergyDashboardTheme.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        children: [
          Icon(
            Icons.business_rounded,
            size: 64,
            color: EnergyDashboardTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد شركات بعد',
            style: TextStyle(
              color: EnergyDashboardTheme.textMuted,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على زر "شركة جديدة" للبدء',
            style: TextStyle(
              color: EnergyDashboardTheme.textMuted.withOpacity(0.7),
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
              color: EnergyDashboardTheme.surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: EnergyDashboardTheme.borderColor),
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
                          color: EnergyDashboardTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'كود: ${tenant.code}',
                        style: const TextStyle(
                          color: EnergyDashboardTheme.textMuted,
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
                  color: EnergyDashboardTheme.textMuted,
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
              color: Colors.white.withOpacity(0.15),
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
        color: Colors.white.withOpacity(0.15),
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
          gradient: const [
            EnergyDashboardTheme.neonBlue,
            EnergyDashboardTheme.neonPurple
          ],
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
          gradient: const [
            EnergyDashboardTheme.success,
            EnergyDashboardTheme.neonGreen
          ],
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
                    : const [
                        EnergyDashboardTheme.success,
                        EnergyDashboardTheme.neonGreen
                      ],
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
          gradient: const [
            EnergyDashboardTheme.danger,
            EnergyDashboardTheme.neonPink
          ],
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
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => HomePage(
          username: 'Super Admin',
          permissions: 'مدير',
          department: tenant.name,
          center: tenant.code,
          salary: '0',
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
                color: Colors.white.withOpacity(0.15),
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
        color = EnergyDashboardTheme.success;
        break;
      case SubscriptionStatus.warning:
        label = 'تحذير';
        color = EnergyDashboardTheme.neonOrange;
        break;
      case SubscriptionStatus.critical:
        label = 'حرج';
        color = EnergyDashboardTheme.danger;
        break;
      case SubscriptionStatus.expired:
        label = 'منتهي';
        color = EnergyDashboardTheme.danger;
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
        return EnergyDashboardTheme.success;
      case SubscriptionStatus.warning:
        return EnergyDashboardTheme.neonOrange;
      case SubscriptionStatus.critical:
        return EnergyDashboardTheme.danger;
      case SubscriptionStatus.expired:
        return EnergyDashboardTheme.danger;
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
        gradient: EnergyDashboardTheme.neonPurpleGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: EnergyDashboardTheme.neonPurple.withOpacity(0.2),
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
              foregroundColor: EnergyDashboardTheme.neonBlue,
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
        'color': EnergyDashboardTheme.success,
        'trend': '+12%',
      },
      {
        'title': 'الاشتراكات النشطة',
        'value': '893',
        'icon': Icons.wifi,
        'color': EnergyDashboardTheme.neonBlue,
        'trend': '+8%',
      },
      {
        'title': 'المدفوعات الشهرية',
        'value': '45.2M',
        'icon': Icons.payments_outlined,
        'color': EnergyDashboardTheme.neonOrange,
        'trend': '+15%',
      },
      {
        'title': 'تذاكر الدعم المفتوحة',
        'value': '23',
        'icon': Icons.support_agent,
        'color': EnergyDashboardTheme.danger,
        'trend': '-5%',
      },
    ];

    // استخدام LayoutBuilder للتكيف مع الشاشة
    return LayoutBuilder(
      builder: (context, constraints) {
        // حساب عدد الأعمدة بناءً على عرض الشاشة
        final crossAxisCount = constraints.maxWidth > 900
            ? 4
            : (constraints.maxWidth > 600 ? 2 : 1);

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: stats.map((stat) {
            final color = stat['color'] as Color;
            // حساب عرض البطاقة
            final cardWidth =
                (constraints.maxWidth - (16 * (crossAxisCount - 1))) /
                    crossAxisCount;

            return SizedBox(
              width: cardWidth.clamp(200.0, 280.0),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: EnergyDashboardTheme.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(stat['icon'] as IconData,
                              color: color, size: 22),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (stat['trend'] as String).startsWith('+')
                                ? EnergyDashboardTheme.success.withOpacity(0.15)
                                : EnergyDashboardTheme.danger.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            stat['trend'] as String,
                            style: TextStyle(
                              color: (stat['trend'] as String).startsWith('+')
                                  ? EnergyDashboardTheme.success
                                  : EnergyDashboardTheme.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      stat['value'] as String,
                      style: const TextStyle(
                        color: EnergyDashboardTheme.textPrimary,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stat['title'] as String,
                      style: const TextStyle(
                        color: EnergyDashboardTheme.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
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
        'color': EnergyDashboardTheme.success,
        'route': 'citizens',
      },
      {
        'title': 'إدارة الاشتراكات',
        'subtitle': 'متابعة وتفعيل وإلغاء الاشتراكات',
        'icon': Icons.card_membership_rounded,
        'color': EnergyDashboardTheme.neonBlue,
        'route': 'subscriptions',
      },
      {
        'title': 'المدفوعات',
        'subtitle': 'تسجيل ومتابعة المدفوعات',
        'icon': Icons.payments_rounded,
        'color': EnergyDashboardTheme.neonOrange,
        'route': 'payments',
      },
      {
        'title': 'باقات الإنترنت',
        'subtitle': 'إدارة باقات الاشتراك والأسعار',
        'icon': Icons.wifi_rounded,
        'color': EnergyDashboardTheme.neonPurple,
        'route': 'plans',
      },
      {
        'title': 'تذاكر الدعم',
        'subtitle': 'الرد على استفسارات المواطنين',
        'icon': Icons.support_agent_rounded,
        'color': EnergyDashboardTheme.danger,
        'route': 'tickets',
      },
      {
        'title': 'التقارير',
        'subtitle': 'تقارير شاملة عن النظام',
        'icon': Icons.analytics_rounded,
        'color': EnergyDashboardTheme.info,
        'route': 'reports',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flash_on_rounded,
                  color: EnergyDashboardTheme.neonBlue),
              const SizedBox(width: 8),
              const Text(
                'الإجراءات السريعة',
                style: TextStyle(
                  color: EnergyDashboardTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // استخدام Wrap بدلاً من GridView لتجنب التداخل
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth > 700
                  ? 3
                  : (constraints.maxWidth > 450 ? 2 : 1);
              final cardWidth =
                  (constraints.maxWidth - (16 * (crossAxisCount - 1))) /
                      crossAxisCount;

              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: actions.map((action) {
                  final color = action['color'] as Color;
                  return SizedBox(
                    width: cardWidth.clamp(140.0, 250.0),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
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
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: color.withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
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
                              const SizedBox(height: 10),
                              Text(
                                action['title'] as String,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                action['subtitle'] as String,
                                style: const TextStyle(
                                  color: EnergyDashboardTheme.textMuted,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.business_rounded,
                  color: EnergyDashboardTheme.primaryColor),
              SizedBox(width: 8),
              Text(
                'الشركة المرتبطة',
                style: TextStyle(
                  color: EnergyDashboardTheme.textPrimary,
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
                  EnergyDashboardTheme.neonBlue.withOpacity(0.15),
                  EnergyDashboardTheme.neonPurple.withOpacity(0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: EnergyDashboardTheme.neonBlue.withOpacity(0.4)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: EnergyDashboardTheme.bgCard,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: EnergyDashboardTheme.neonBlue.withOpacity(0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.wifi_rounded,
                    color: EnergyDashboardTheme.neonBlue,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'شركة الصدارة للإنترنت',
                  style: TextStyle(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: EnergyDashboardTheme.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified,
                          color: EnergyDashboardTheme.success, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'مرتبطة بنظام المواطن',
                        style: TextStyle(
                          color: EnergyDashboardTheme.success,
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
        color: EnergyDashboardTheme.bgSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: EnergyDashboardTheme.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: EnergyDashboardTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: EnergyDashboardTheme.textPrimary,
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
        backgroundColor: EnergyDashboardTheme.neonBlue,
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
            color: EnergyDashboardTheme.bgSidebar,
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
                      color: EnergyDashboardTheme.textOnDarkMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // المحتوى
          Expanded(
            child: _currentTab == 'plans'
                ? const PlansManagementPage()
                : Container(
                    color: EnergyDashboardTheme.bgPrimary,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getTabIcon(_currentTab),
                            size: 80,
                            color:
                                EnergyDashboardTheme.neonBlue.withOpacity(0.5),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            _getTabTitle(_currentTab),
                            style: const TextStyle(
                              color: EnergyDashboardTheme.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'قيد التطوير - سيتم إضافة المحتوى قريباً',
                            style: TextStyle(
                              color: EnergyDashboardTheme.textMuted,
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
            color: isSelected
                ? EnergyDashboardTheme.neonBlue.withOpacity(0.2)
                : null,
            border: Border(
              right: BorderSide(
                color: isSelected
                    ? EnergyDashboardTheme.neonBlue
                    : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? EnergyDashboardTheme.neonBlue
                    : EnergyDashboardTheme.textOnDarkSecondary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: isSelected
                      ? EnergyDashboardTheme.neonBlue
                      : EnergyDashboardTheme.textOnDarkSecondary,
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
