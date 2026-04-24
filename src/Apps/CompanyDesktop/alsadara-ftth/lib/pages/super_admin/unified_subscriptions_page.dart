/// صفحة مراقبة الاشتراكات الموحدة - Unified Subscriptions Monitoring
/// تعرض كل الاشتراكات عبر جميع الشركات مع فلاتر متقدمة
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme/energy_dashboard_theme.dart';
import '../../services/api/auth/super_admin_api.dart';
import 'widgets/super_admin_widgets.dart';

class UnifiedSubscriptionsPage extends StatefulWidget {
  const UnifiedSubscriptionsPage({super.key});

  @override
  State<UnifiedSubscriptionsPage> createState() =>
      _UnifiedSubscriptionsPageState();
}

class _UnifiedSubscriptionsPageState extends State<UnifiedSubscriptionsPage> {
  bool _isLoading = true;
  List<Company> _companies = [];
  String _statusFilter = 'all';
  String _searchQuery = '';
  String _sortBy = 'daysRemaining';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final api = SuperAdminApi();
      final response = await api.getCompanies(pageSize: 100);

      if (mounted && response.isSuccess && response.data != null) {
        setState(() {
          _companies = response.data!.companies;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Company> get _filteredCompanies {
    var list = List<Company>.from(_companies);

    // Filter by status
    switch (_statusFilter) {
      case 'active':
        list = list.where((c) => c.isActive && c.daysRemaining > 30).toList();
        break;
      case 'warning':
        list = list
            .where((c) => c.daysRemaining > 7 && c.daysRemaining <= 30)
            .toList();
        break;
      case 'critical':
        list = list
            .where((c) => c.daysRemaining > 0 && c.daysRemaining <= 7)
            .toList();
        break;
      case 'expired':
        list = list.where((c) => c.isExpired).toList();
        break;
      case 'suspended':
        list = list.where((c) => !c.isActive).toList();
        break;
    }

    // Search
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((c) =>
              c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              c.code.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Sort
    switch (_sortBy) {
      case 'daysRemaining':
        list.sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));
        break;
      case 'name':
        list.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'endDate':
        list.sort((a, b) =>
            a.subscriptionEndDate.compareTo(b.subscriptionEndDate));
        break;
      case 'users':
        list.sort((a, b) => b.employeeCount.compareTo(a.employeeCount));
        break;
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EnergyDashboardTheme.bgPrimary,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: EnergyDashboardTheme.neonGreen))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SAPageHeader(
                    title: 'مراقبة الاشتراكات',
                    subtitle: 'جميع اشتراكات الشركات في مكان واحد',
                    icon: Icons.subscriptions_rounded,
                    color: EnergyDashboardTheme.neonPurple,
                    onRefresh: _loadData,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SAFilterBar(
                    searchHint: 'بحث بالاسم أو الكود...',
                    onSearchChanged: (v) =>
                        setState(() => _searchQuery = v),
                    chips: const [
                      SAFilterChip(
                        key: 'all',
                        label: 'الكل',
                        color: EnergyDashboardTheme.neonBlue,
                      ),
                      SAFilterChip(
                        key: 'active',
                        label: 'نشطة',
                        color: EnergyDashboardTheme.success,
                      ),
                      SAFilterChip(
                        key: 'warning',
                        label: 'تحذير',
                        color: EnergyDashboardTheme.warning,
                      ),
                      SAFilterChip(
                        key: 'critical',
                        label: 'حرجة',
                        color: EnergyDashboardTheme.neonOrange,
                      ),
                      SAFilterChip(
                        key: 'expired',
                        label: 'منتهية',
                        color: EnergyDashboardTheme.danger,
                      ),
                    ],
                    selectedChip: _statusFilter,
                    onChipSelected: (v) =>
                        setState(() => _statusFilter = v),
                    sortItems: const [
                      SADropdownItem(
                          value: 'daysRemaining', label: 'الأقرب انتهاءً'),
                      SADropdownItem(value: 'name', label: 'الاسم'),
                      SADropdownItem(
                          value: 'endDate', label: 'تاريخ الانتهاء'),
                      SADropdownItem(
                          value: 'users', label: 'عدد المستخدمين'),
                    ],
                    selectedSort: _sortBy,
                    onSortChanged: (v) => setState(() => _sortBy = v),
                  ),
                ),
                _buildStatsBar(),
                Expanded(child: _buildSubscriptionsList()),
              ],
            ),
    );
  }

  Widget _buildStatsBar() {
    final filtered = _filteredCompanies;
    final total = filtered.length;
    final avgDays = total > 0
        ? (filtered.fold(0, (sum, c) => sum + c.daysRemaining) / total)
            .toStringAsFixed(0)
        : '0';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Text(
            '$total شركة',
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 16),
          Container(
            width: 1,
            height: 16,
            color: EnergyDashboardTheme.borderColor,
          ),
          const SizedBox(width: 16),
          Text(
            'متوسط الأيام المتبقية: $avgDays يوم',
            style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionsList() {
    final filtered = _filteredCompanies;

    if (filtered.isEmpty) {
      return EnergyDashboardTheme.emptyWidget(
        message: 'لا توجد اشتراكات مطابقة للفلتر',
        icon: Icons.search_off_rounded,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final company = filtered[index];
        return _buildSubscriptionCard(company);
      },
    );
  }

  Widget _buildSubscriptionCard(Company company) {
    final status = saCompanyStatus(
      isActive: company.isActive,
      isExpired: company.isExpired,
      daysRemaining: company.daysRemaining,
    );
    final statusColor = saStatusColor(status);

    final totalDays = company.subscriptionEndDate
        .difference(company.subscriptionStartDate)
        .inDays;
    final elapsed = DateTime.now()
        .difference(company.subscriptionStartDate)
        .inDays
        .clamp(0, totalDays);
    final progress = totalDays > 0 ? elapsed / totalDays : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: company.isExpired || company.daysRemaining <= 7
              ? statusColor.withOpacity(0.4)
              : EnergyDashboardTheme.borderColor,
        ),
      ),
      child: Row(
        children: [
          // Company avatar
          SACompanyAvatar(
            name: company.name,
            color: statusColor,
            size: 40,
          ),
          const SizedBox(width: 12),
          // Company info
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  company.name,
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${company.code} | ${company.employeeCount} مستخدم',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Progress bar
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('MM/dd').format(company.subscriptionStartDate),
                      style: GoogleFonts.cairo(
                          color: EnergyDashboardTheme.textMuted, fontSize: 9),
                    ),
                    Text(
                      DateFormat('MM/dd').format(company.subscriptionEndDate),
                      style: GoogleFonts.cairo(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SAProgressBar(
                  value: progress,
                  color: statusColor,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Status badge
          SAStatusBadge(
            text: saStatusLabel(status),
            color: statusColor,
          ),
          const SizedBox(width: 12),
          // Days remaining
          SADaysRemainingBadge(days: company.daysRemaining),
        ],
      ),
    );
  }
}
