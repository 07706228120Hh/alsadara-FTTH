/// 🎨 Energy Dashboard Home - الشاشة الرئيسية
/// مطابق لتصميم Figma - Energy Management Dashboard
/// https://fade-tag-69073310.figma.site
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/energy_dashboard_theme.dart';
import '../../services/api/auth/super_admin_api.dart';
import '../../services/api/api_response.dart';

class EnergyDashboardHome extends StatefulWidget {
  const EnergyDashboardHome({super.key});

  @override
  State<EnergyDashboardHome> createState() => _EnergyDashboardHomeState();
}

class _EnergyDashboardHomeState extends State<EnergyDashboardHome> {
  final SuperAdminApi _superAdminApi = SuperAdminApi();
  List<Company> _companies = [];
  SystemStatistics? _statistics;
  bool _isLoading = true;
  String? _error;

  // إحصائيات النظام (من API)
  int _totalCompanies = 0;
  int _totalUsers = 0;
  int _activeCompanies = 0;
  int _ordersToday = 0;
  int _activeUsersToday = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // جلب البيانات بالتوازي
      final results = await Future.wait([
        _superAdminApi.getCompanies(pageSize: 100),
        _superAdminApi.getStatistics(),
      ]);

      final companiesResponse =
          results[0] as ApiResponse<CompaniesListResponse>;
      final statsResponse = results[1] as ApiResponse<SystemStatistics>;

      if (mounted) {
        setState(() {
          // بيانات الشركات
          if (companiesResponse.isSuccess && companiesResponse.data != null) {
            _companies = companiesResponse.data!.companies;
          }

          // الإحصائيات من قاعدة البيانات
          if (statsResponse.isSuccess && statsResponse.data != null) {
            _statistics = statsResponse.data;
            _totalCompanies = _statistics!.totalCompanies;
            _totalUsers = _statistics!.totalUsers;
            _activeCompanies = _statistics!.activeCompanies;
            _ordersToday = _statistics!.ordersToday;
            _activeUsersToday = _statistics!.activeUsersToday;
          } else {
            // استخدام بيانات الشركات كبديل
            _totalCompanies = _companies.length;
            _totalUsers = _companies.fold(0, (sum, c) => sum + c.employeeCount);
            _activeCompanies = _companies.where((c) => c.isActive).length;
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isCompact = screenSize.width < 600;
    final padding = isCompact ? 8.0 : 16.0;
    final spacing = isCompact ? 8.0 : 12.0;

    return Container(
      color: EnergyDashboardTheme.bgPrimary,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          children: [
            // 🔍 شريط البحث والفلاتر (مضغوط)
            _buildCompactFilters(),
            SizedBox(height: spacing),

            // 📊 بطاقات الإحصائيات
            Expanded(
              flex: 2,
              child: _buildStatCards(),
            ),
            SizedBox(height: spacing),

            // 📈 الرسوم البيانية وحالة الشركات
            Expanded(
              flex: 3,
              child: _buildChartsAndStatus(),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // � شريط الفلاتر المضغوط
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCompactFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Row(
        children: [
          // حالة المراقبة
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: EnergyDashboardTheme.neonGreen,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'نشط',
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.neonGreen,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          // الفلاتر
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildMiniFilter('جميع الشركات', Icons.filter_list_rounded),
                  const SizedBox(width: 8),
                  _buildMiniFilter('الكل', Icons.business_rounded),
                  const SizedBox(width: 8),
                  _buildMiniFilter('مباشر', Icons.speed_rounded),
                  const SizedBox(width: 8),
                  _buildMiniFilter('اليوم', Icons.calendar_today_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // زر التحديث
          InkWell(
            onTap: _loadData,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: EnergyDashboardTheme.neonGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.refresh_rounded,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    'تحديث',
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniFilter(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgSecondary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: EnergyDashboardTheme.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // �👋 قسم الترحيب
  // ═══════════════════════════════════════════════════════════════

  Widget _buildWelcomeSection(String userName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'مرحباً، $userName! 👋',
          style: GoogleFonts.cairo(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: EnergyDashboardTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'ماذا تبحث عنه اليوم؟',
          style: GoogleFonts.cairo(
            fontSize: 16,
            color: EnergyDashboardTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 🔍 شريط البحث والفلاتر
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSearchAndFilters() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 500;
        final padding = isCompact ? 12.0 : 20.0;

        return Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: EnergyDashboardTheme.borderColor),
          ),
          child: Column(
            children: [
              // حالة المراقبة
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
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
                    'المراقبة المباشرة نشطة',
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.neonGreen,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // الفلاتر
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildFilterDropdown(
                    label: 'نوع الفلتر',
                    value: 'جميع الشركات',
                    icon: Icons.filter_list_rounded,
                  ),
                  _buildFilterDropdown(
                    label: 'اختر الشركة',
                    value: 'الكل',
                    icon: Icons.business_rounded,
                  ),
                  _buildFilterDropdown(
                    label: 'وضع البيانات',
                    value: 'مباشر',
                    icon: Icons.speed_rounded,
                  ),
                  _buildFilterDropdown(
                    label: 'الفترة الزمنية',
                    value: 'اليوم',
                    icon: Icons.calendar_today_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // زر تطبيق الفلتر
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(
                    'تحديث البيانات',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnergyDashboardTheme.neonGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: EnergyDashboardTheme.textMuted, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.cairo(
                  color: EnergyDashboardTheme.textMuted,
                  fontSize: 10,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.cairo(
                  color: EnergyDashboardTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: EnergyDashboardTheme.textMuted,
            size: 18,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 📊 بطاقات الإحصائيات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStatCards() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: EnergyDashboardTheme.neonGreen),
      );
    }

    // دائماً عرض البطاقات في صف واحد
    return Row(
      children: [
        Expanded(
          child: _buildCompactStatCard(
            title: 'الشركات',
            value: _totalCompanies.toString(),
            unit: 'شركة',
            trend: '$_activeCompanies نشط',
            icon: Icons.business_rounded,
            color: EnergyDashboardTheme.neonBlue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCompactStatCard(
            title: 'المستخدمين',
            value: _totalUsers.toString(),
            unit: 'مستخدم',
            trend: '$_activeUsersToday نشط',
            icon: Icons.people_rounded,
            color: EnergyDashboardTheme.neonGreen,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCompactStatCard(
            title: 'النشطة',
            value: _activeCompanies.toString(),
            unit: 'نشط',
            trend:
                '${_totalCompanies > 0 ? ((_activeCompanies / _totalCompanies) * 100).toStringAsFixed(0) : 0}%',
            icon: Icons.verified_rounded,
            color: EnergyDashboardTheme.neonPurple,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCompactStatCard(
            title: 'الطلبات',
            value: _ordersToday.toString(),
            unit: 'طلب',
            trend: _ordersToday > 0 ? '+$_ordersToday' : 'لا طلبات',
            icon: Icons.shopping_cart_rounded,
            color: EnergyDashboardTheme.neonOrange,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactStatCard({
    required String title,
    required String value,
    required String unit,
    required String trend,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.2),
            color.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  trend,
                  style: GoogleFonts.cairo(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: EnergyDashboardTheme.textPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  unit,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textMuted,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardsOld() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: EnergyDashboardTheme.neonGreen),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final isMedium = constraints.maxWidth > 600;

        if (isWide) {
          return Row(
            children: [
              Expanded(
                  child: _buildStatCard(
                title: 'الشركات',
                value: _totalCompanies.toString(),
                unit: 'شركة',
                status: _activeCompanies > 0 ? 'high' : 'normal',
                statusText: 'إجمالي الشركات في النظام',
                trend: '$_activeCompanies نشط',
                icon: Icons.business_rounded,
                color: EnergyDashboardTheme.neonBlue,
              )),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildStatCard(
                title: 'المستخدمين',
                value: _totalUsers.toString(),
                unit: 'مستخدم',
                status: _activeUsersToday > 0 ? 'high' : 'normal',
                statusText: 'إجمالي المستخدمين',
                trend: '$_activeUsersToday نشط اليوم',
                icon: Icons.people_rounded,
                color: EnergyDashboardTheme.neonGreen,
              )),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildStatCard(
                title: 'الشركات النشطة',
                value: _activeCompanies.toString(),
                unit: 'نشط',
                status:
                    _activeCompanies == _totalCompanies ? 'optimal' : 'normal',
                statusText: 'شركات باشتراك فعال',
                trend:
                    '${_totalCompanies > 0 ? ((_activeCompanies / _totalCompanies) * 100).toStringAsFixed(0) : 0}%',
                icon: Icons.verified_rounded,
                color: EnergyDashboardTheme.neonPurple,
              )),
              const SizedBox(width: 16),
              Expanded(
                  child: _buildStatCard(
                title: 'الطلبات اليوم',
                value: _ordersToday.toString(),
                unit: 'طلب',
                status: _ordersToday > 0 ? 'high' : 'optimal',
                statusText: 'طلبات اليوم',
                trend: _ordersToday > 0 ? '+$_ordersToday' : 'لا طلبات',
                icon: Icons.shopping_cart_rounded,
                color: EnergyDashboardTheme.neonOrange,
              )),
            ],
          );
        } else if (isMedium) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: _buildStatCard(
                    title: 'الشركات',
                    value: _totalCompanies.toString(),
                    unit: 'شركة',
                    status: _activeCompanies > 0 ? 'high' : 'normal',
                    statusText: 'إجمالي الشركات',
                    trend: '$_activeCompanies نشط',
                    icon: Icons.business_rounded,
                    color: EnergyDashboardTheme.neonBlue,
                  )),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _buildStatCard(
                    title: 'المستخدمين',
                    value: _totalUsers.toString(),
                    unit: 'مستخدم',
                    status: _activeUsersToday > 0 ? 'high' : 'normal',
                    statusText: 'إجمالي المستخدمين',
                    trend: '$_activeUsersToday نشط اليوم',
                    icon: Icons.people_rounded,
                    color: EnergyDashboardTheme.neonGreen,
                  )),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      child: _buildStatCard(
                    title: 'الشركات النشطة',
                    value: _activeCompanies.toString(),
                    unit: 'نشط',
                    status: _activeCompanies == _totalCompanies
                        ? 'optimal'
                        : 'normal',
                    statusText: 'شركات باشتراك فعال',
                    trend:
                        '${_totalCompanies > 0 ? ((_activeCompanies / _totalCompanies) * 100).toStringAsFixed(0) : 0}%',
                    icon: Icons.verified_rounded,
                    color: EnergyDashboardTheme.neonPurple,
                  )),
                  const SizedBox(width: 16),
                  Expanded(
                      child: _buildStatCard(
                    title: 'الطلبات اليوم',
                    value: _ordersToday.toString(),
                    unit: 'طلب',
                    status: _ordersToday > 0 ? 'high' : 'optimal',
                    statusText: 'طلبات اليوم',
                    trend: _ordersToday > 0 ? '+$_ordersToday' : 'لا طلبات',
                    icon: Icons.shopping_cart_rounded,
                    color: EnergyDashboardTheme.neonOrange,
                  )),
                ],
              ),
            ],
          );
        } else {
          return Column(
            children: [
              _buildStatCard(
                title: 'الشركات',
                value: _totalCompanies.toString(),
                unit: 'شركة',
                status: _activeCompanies > 0 ? 'high' : 'normal',
                statusText: 'إجمالي الشركات',
                trend: '$_activeCompanies نشط',
                icon: Icons.business_rounded,
                color: EnergyDashboardTheme.neonBlue,
              ),
              const SizedBox(height: 12),
              _buildStatCard(
                title: 'المستخدمين',
                value: _totalUsers.toString(),
                unit: 'مستخدم',
                status: _activeUsersToday > 0 ? 'high' : 'normal',
                statusText: 'إجمالي المستخدمين',
                trend: '$_activeUsersToday نشط اليوم',
                icon: Icons.people_rounded,
                color: EnergyDashboardTheme.neonGreen,
              ),
              const SizedBox(height: 12),
              _buildStatCard(
                title: 'الشركات النشطة',
                value: _activeCompanies.toString(),
                unit: 'نشط',
                status:
                    _activeCompanies == _totalCompanies ? 'optimal' : 'normal',
                statusText: 'شركات باشتراك فعال',
                trend:
                    '${_totalCompanies > 0 ? ((_activeCompanies / _totalCompanies) * 100).toStringAsFixed(0) : 0}%',
                icon: Icons.verified_rounded,
                color: EnergyDashboardTheme.neonPurple,
              ),
              const SizedBox(height: 12),
              _buildStatCard(
                title: 'الطلبات اليوم',
                value: _ordersToday.toString(),
                unit: 'طلب',
                status: _ordersToday > 0 ? 'high' : 'optimal',
                statusText: 'طلبات اليوم',
                trend: _ordersToday > 0 ? '+$_ordersToday' : 'لا طلبات',
                icon: Icons.shopping_cart_rounded,
                color: EnergyDashboardTheme.neonOrange,
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String unit,
    required String status,
    required String statusText,
    required String trend,
    required IconData icon,
    required Color color,
    bool isNegative = false,
  }) {
    Color statusColor;
    switch (status) {
      case 'high':
        statusColor = EnergyDashboardTheme.neonGreen;
        break;
      case 'optimal':
        statusColor = EnergyDashboardTheme.neonBlue;
        break;
      default:
        statusColor = EnergyDashboardTheme.textSecondary;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.18),
            color.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان والأيقونة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    title,
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              // شارة الحالة
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.cairo(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // القيمة الكبيرة
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.cairo(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: EnergyDashboardTheme.textPrimary,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // الوصف والنسبة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                statusText,
                style: GoogleFonts.cairo(
                  color: EnergyDashboardTheme.textMuted,
                  fontSize: 12,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isNegative
                          ? EnergyDashboardTheme.danger
                          : EnergyDashboardTheme.success)
                      .withOpacity(0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  trend,
                  style: GoogleFonts.cairo(
                    color: isNegative
                        ? EnergyDashboardTheme.danger
                        : EnergyDashboardTheme.success,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 📈 الرسوم البيانية وحالة الشركات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildChartsAndStatus() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // الرسم البياني
        Expanded(
          flex: 2,
          child: _buildCompactActivityChart(),
        ),
        const SizedBox(width: 12),
        // حالة الشركات
        Expanded(
          flex: 1,
          child: _buildCompactCompanyStatus(),
        ),
      ],
    );
  }

  Widget _buildCompactActivityChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'نظرة عامة على النشاط',
                style: GoogleFonts.cairo(
                  color: EnergyDashboardTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.neonGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$_activeCompanies',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.neonGreen,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'شركة نشطة',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // الرسم البياني
          Expanded(
            child: _buildSimpleChart(),
          ),
          const SizedBox(height: 8),
          // وسيلة الإيضاح
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMiniLegend('نشط', EnergyDashboardTheme.neonGreen),
              const SizedBox(width: 16),
              _buildMiniLegend('مستخدمين', EnergyDashboardTheme.neonBlue),
              const SizedBox(width: 16),
              _buildMiniLegend('طلبات', EnergyDashboardTheme.neonOrange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textMuted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCompanyStatus() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حالة الشركات',
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // قائمة الشركات
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: EnergyDashboardTheme.neonGreen,
                      strokeWidth: 2,
                    ),
                  )
                : _companies.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.business_outlined,
                              size: 32,
                              color: EnergyDashboardTheme.textMuted
                                  .withOpacity(0.5),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'لا توجد شركات',
                              style: GoogleFonts.cairo(
                                color: EnergyDashboardTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _companies.take(4).length,
                        itemBuilder: (context, index) {
                          final company = _companies[index];
                          return _buildMiniCompanyItem(
                            name: company.name,
                            isActive: company.isActive,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCompanyItem({required String name, required bool isActive}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgSecondary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: (isActive
                      ? EnergyDashboardTheme.neonGreen
                      : EnergyDashboardTheme.textMuted)
                  .withOpacity(0.35),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.business_rounded,
              color: isActive
                  ? EnergyDashboardTheme.neonGreen
                  : EnergyDashboardTheme.textMuted,
              size: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.cairo(
                color: EnergyDashboardTheme.textPrimary,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isActive
                  ? EnergyDashboardTheme.neonGreen
                  : EnergyDashboardTheme.danger,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartsAndStatusOld() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final isMedium = constraints.maxWidth > 600;
        final chartHeight = isWide ? 280.0 : (isMedium ? 240.0 : 200.0);

        if (isWide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // الرسم البياني
                Expanded(
                  flex: 2,
                  child: _buildActivityChart(chartHeight: chartHeight),
                ),
                const SizedBox(width: 24),
                // حالة الشركات
                Expanded(
                  flex: 1,
                  child: _buildCompanyStatus(),
                ),
              ],
            ),
          );
        } else {
          return Column(
            children: [
              _buildActivityChart(chartHeight: chartHeight),
              const SizedBox(height: 16),
              _buildCompanyStatus(),
            ],
          );
        }
      },
    );
  }

  Widget _buildActivityChart({double chartHeight = 200}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'نظرة عامة على النشاط',
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'توزيع النشاط عبر جميع الشركات لهذا اليوم',
                    style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              // إحصائية إجمالية
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: EnergyDashboardTheme.neonGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: EnergyDashboardTheme.neonGreen.withOpacity(0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '$_activeCompanies',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.neonGreen,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'شركة نشطة من $_totalCompanies',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // الرسم البياني المبسط
          SizedBox(
            height: chartHeight,
            child: _buildSimpleChart(),
          ),
          const SizedBox(height: 16),

          // وسيلة الإيضاح
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              _buildLegendItem(
                  'الشركات النشطة', EnergyDashboardTheme.neonGreen),
              _buildLegendItem('المستخدمين', EnergyDashboardTheme.neonBlue),
              _buildLegendItem('الطلبات', EnergyDashboardTheme.neonOrange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleChart() {
    // رسم بياني مبسط باستخدام شرائط
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(12, (index) {
        final height = 50.0 + (index * 10) % 150;
        final isHighlighted = index == 8;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  height: height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: isHighlighted
                          ? [
                              EnergyDashboardTheme.neonGreen,
                              EnergyDashboardTheme.neonGreen.withOpacity(0.5),
                            ]
                          : [
                              EnergyDashboardTheme.neonBlue.withOpacity(0.8),
                              EnergyDashboardTheme.neonBlue.withOpacity(0.5),
                            ],
                    ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: isHighlighted
                        ? EnergyDashboardTheme.glowCustom(
                            EnergyDashboardTheme.neonGreen,
                            intensity: 0.3,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(index * 2).toString().padLeft(2, '0')}:00',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyStatus() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EnergyDashboardTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حالة الشركات',
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),

          // قائمة الشركات
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(
                  color: EnergyDashboardTheme.neonGreen,
                ),
              ),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'خطأ في تحميل البيانات',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.danger,
                  ),
                ),
              ),
            )
          else if (_companies.isEmpty)
            _buildEmptyCompanyState()
          else
            ...(_companies.take(5).map((company) => _buildCompanyStatusItem(
                  name: company.name,
                  value: '${company.employeeCount} موظف',
                  isActive: company.isActive,
                ))),

          if (_companies.length > 5) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {
                  // التنقل لصفحة الشركات
                },
                child: Text(
                  'عرض الكل (${_companies.length})',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.neonGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompanyStatusItem({
    required String name,
    required String value,
    required bool isActive,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? EnergyDashboardTheme.neonGreen.withOpacity(0.2)
              : EnergyDashboardTheme.borderColor,
        ),
      ),
      child: Row(
        children: [
          // أيقونة الحالة
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (isActive
                      ? EnergyDashboardTheme.neonGreen
                      : EnergyDashboardTheme.textMuted)
                  .withOpacity(0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.business_rounded,
              color: isActive
                  ? EnergyDashboardTheme.neonGreen
                  : EnergyDashboardTheme.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          // اسم الشركة
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // شارة الحالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: (isActive
                      ? EnergyDashboardTheme.neonGreen
                      : EnergyDashboardTheme.danger)
                  .withOpacity(0.35),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isActive ? 'نشط' : 'غير نشط',
              style: GoogleFonts.cairo(
                color: isActive
                    ? EnergyDashboardTheme.neonGreen
                    : EnergyDashboardTheme.danger,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCompanyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: 48,
            color: EnergyDashboardTheme.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'لا توجد شركات حالياً',
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textMuted,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(
              'تحديث',
              style: GoogleFonts.cairo(),
            ),
            style: TextButton.styleFrom(
              foregroundColor: EnergyDashboardTheme.neonGreen,
            ),
          ),
        ],
      ),
    );
  }
}
