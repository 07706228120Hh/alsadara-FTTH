/// صفحة المراقبة المالية الشاملة - Financial Oversight
/// تعرض إيرادات ومصاريف كل الشركات
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme/energy_dashboard_theme.dart';
import '../../services/api/auth/super_admin_api.dart';
import 'widgets/super_admin_widgets.dart';

class FinancialOversightPage extends StatefulWidget {
  const FinancialOversightPage({super.key});

  @override
  State<FinancialOversightPage> createState() => _FinancialOversightPageState();
}

class _FinancialOversightPageState extends State<FinancialOversightPage> {
  bool _isLoading = true;
  List<Company> _companies = [];
  String _selectedPeriod = 'thisMonth';
  final _currencyFormat = NumberFormat('#,###');

  // Financial data per company (calculated from available data)
  List<_CompanyFinancialData> _financialData = [];

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
        final companies = response.data!.companies;

        // Build financial summary from company data
        final financialData = companies.map((c) {
          final daysActive = DateTime.now()
              .difference(c.subscriptionStartDate)
              .inDays
              .clamp(1, 9999);
          return _CompanyFinancialData(
            company: c,
            employeeCount: c.employeeCount,
            maxUsers: c.maxUsers,
            subscriptionDaysTotal: c.subscriptionEndDate
                .difference(c.subscriptionStartDate)
                .inDays,
            daysActive: daysActive,
            isExpired: c.isExpired,
            daysRemaining: c.daysRemaining,
          );
        }).toList();

        setState(() {
          _companies = companies;
          _financialData = financialData;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EnergyDashboardTheme.bgPrimary,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                  color: EnergyDashboardTheme.neonGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                _buildSummaryCards(),
                const SizedBox(height: 16),
                _buildSubscriptionStatusChart(),
                const SizedBox(height: 16),
                _buildCompanyFinancialTable(),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return SAPageHeader(
      title: 'المراقبة المالية',
      subtitle: 'نظرة شاملة على الاشتراكات والموارد',
      icon: Icons.account_balance_rounded,
      color: EnergyDashboardTheme.neonOrange,
      secondaryColor: EnergyDashboardTheme.neonGreen,
      onRefresh: _loadData,
      actions: [
        SADropdown(
          items: const [
            SADropdownItem(value: 'today', label: 'اليوم'),
            SADropdownItem(value: 'thisWeek', label: 'هذا الأسبوع'),
            SADropdownItem(value: 'thisMonth', label: 'هذا الشهر'),
            SADropdownItem(value: 'all', label: 'الكل'),
          ],
          value: _selectedPeriod,
          onChanged: (v) => setState(() => _selectedPeriod = v),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildSummaryCards() {
    final totalCompanies = _companies.length;
    final activeCompanies =
        _companies.where((c) => c.isActive && !c.isExpired).length;
    final expiredCompanies = _companies.where((c) => c.isExpired).length;
    final totalUsers = _companies.fold(0, (sum, c) => sum + c.employeeCount);
    final totalMaxUsers = _companies.fold(0, (sum, c) => sum + c.maxUsers);

    final utilizationRate = totalMaxUsers > 0
        ? ((totalUsers / totalMaxUsers) * 100).toStringAsFixed(1)
        : '0';

    final renewalRate = totalCompanies > 0
        ? ((activeCompanies / totalCompanies) * 100).toStringAsFixed(1)
        : '0';

    return Row(
      children: [
        Expanded(
          child: SAStatCard(
            title: 'الشركات النشطة',
            value: '$activeCompanies / $totalCompanies',
            subtitle: '$renewalRate%',
            icon: Icons.business_center_rounded,
            color: EnergyDashboardTheme.neonGreen,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SAStatCard(
            title: 'منتهية الاشتراك',
            value: '$expiredCompanies',
            subtitle: expiredCompanies > 0 ? 'تحتاج تجديد' : 'لا يوجد',
            icon: Icons.timer_off_rounded,
            color: expiredCompanies > 0
                ? EnergyDashboardTheme.danger
                : EnergyDashboardTheme.success,
            alert: expiredCompanies > 0,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SAStatCard(
            title: 'إجمالي المستخدمين',
            value: _currencyFormat.format(totalUsers),
            subtitle: 'من أصل ${_currencyFormat.format(totalMaxUsers)}',
            icon: Icons.people_rounded,
            color: EnergyDashboardTheme.neonBlue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SAStatCard(
            title: 'نسبة الاستخدام',
            value: '$utilizationRate%',
            subtitle: 'استخدام الموارد',
            icon: Icons.donut_large_rounded,
            color: EnergyDashboardTheme.neonPurple,
          ),
        ),
      ],
    );
  }

  Widget _buildSubscriptionStatusChart() {
    final active =
        _companies.where((c) => c.isActive && c.daysRemaining > 30).length;
    final warning = _companies
        .where((c) => c.daysRemaining > 7 && c.daysRemaining <= 30)
        .length;
    final critical = _companies
        .where((c) => c.daysRemaining > 0 && c.daysRemaining <= 7)
        .length;
    final expired = _companies.where((c) => c.isExpired).length;
    final suspended = _companies.where((c) => !c.isActive).length;
    final total = _companies.length;

    return SASection(
      title: 'توزيع حالة الاشتراكات',
      icon: Icons.bar_chart_rounded,
      iconColor: EnergyDashboardTheme.neonGreen,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: total > 0
          ? Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        if (active > 0)
                          Expanded(
                            flex: active,
                            child:
                                Container(color: EnergyDashboardTheme.success),
                          ),
                        if (warning > 0)
                          Expanded(
                            flex: warning,
                            child:
                                Container(color: EnergyDashboardTheme.warning),
                          ),
                        if (critical > 0)
                          Expanded(
                            flex: critical,
                            child: Container(
                                color: EnergyDashboardTheme.neonOrange),
                          ),
                        if (expired > 0)
                          Expanded(
                            flex: expired,
                            child:
                                Container(color: EnergyDashboardTheme.danger),
                          ),
                        if (suspended > 0)
                          Expanded(
                            flex: suspended,
                            child:
                                Container(color: EnergyDashboardTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _chartLegend('نشطة ($active)', EnergyDashboardTheme.success),
                    _chartLegend(
                        'تحذير ($warning)', EnergyDashboardTheme.warning),
                    _chartLegend(
                        'حرجة ($critical)', EnergyDashboardTheme.neonOrange),
                    _chartLegend(
                        'منتهية ($expired)', EnergyDashboardTheme.danger),
                    _chartLegend(
                        'معلقة ($suspended)', EnergyDashboardTheme.textMuted),
                  ],
                ),
              ],
            )
          : Center(
              child: Text('لا توجد بيانات',
                  style: GoogleFonts.cairo(
                      color: EnergyDashboardTheme.textMuted)),
            ),
    );
  }

  Widget _chartLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyFinancialTable() {
    final sorted = List<_CompanyFinancialData>.from(_financialData)
      ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

    return SASection(
      title: 'تفاصيل اشتراكات الشركات',
      icon: Icons.receipt_long_rounded,
      iconColor: EnergyDashboardTheme.neonOrange,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SATableHeader(
            columns: const [
              SATableColumn(label: 'الشركة', flex: 3),
              SATableColumn(label: 'الحالة', flex: 2),
              SATableColumn(label: 'الموظفين', flex: 1),
              SATableColumn(label: 'الحد الأقصى', flex: 1),
              SATableColumn(label: 'نسبة الاستخدام', flex: 2),
              SATableColumn(label: 'بداية الاشتراك', flex: 2),
              SATableColumn(label: 'نهاية الاشتراك', flex: 2),
              SATableColumn(label: 'متبقي', flex: 1),
            ],
          ),
          ...sorted.map((fd) => _buildFinancialRow(fd)),
        ],
      ),
    );
  }

  Widget _buildFinancialRow(_CompanyFinancialData fd) {
    final c = fd.company;
    final status = saCompanyStatus(
      isActive: c.isActive,
      isExpired: c.isExpired,
      daysRemaining: c.daysRemaining,
    );
    final statusColor = saStatusColor(status);
    final statusLabel = saStatusLabel(status);
    final utilization =
        fd.maxUsers > 0 ? (fd.employeeCount / fd.maxUsers) : 0.0;

    return SATableRow(
      flexes: const [3, 2, 1, 1, 2, 2, 2, 1],
      highlightColor:
          c.isExpired ? EnergyDashboardTheme.danger.withOpacity(0.04) : null,
      cells: [
        // Company name
        Text(
          c.name,
          style: GoogleFonts.cairo(
            color: EnergyDashboardTheme.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // Status badge
        SAStatusBadge(text: statusLabel, color: statusColor),
        // Employee count
        Text(
          '${fd.employeeCount}',
          style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textSecondary, fontSize: 12),
        ),
        // Max users
        Text(
          '${fd.maxUsers}',
          style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textSecondary, fontSize: 12),
        ),
        // Utilization progress bar
        SAProgressBar(
          value: utilization,
          showPercent: true,
        ),
        // Subscription start date
        Text(
          DateFormat('yyyy/MM/dd').format(c.subscriptionStartDate),
          style: GoogleFonts.cairo(
              color: EnergyDashboardTheme.textSecondary, fontSize: 11),
        ),
        // Subscription end date
        Text(
          DateFormat('yyyy/MM/dd').format(c.subscriptionEndDate),
          style: GoogleFonts.cairo(
            color: statusColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Days remaining badge
        SADaysRemainingBadge(days: c.daysRemaining),
      ],
    );
  }
}

class _CompanyFinancialData {
  final Company company;
  final int employeeCount;
  final int maxUsers;
  final int subscriptionDaysTotal;
  final int daysActive;
  final bool isExpired;
  final int daysRemaining;

  _CompanyFinancialData({
    required this.company,
    required this.employeeCount,
    required this.maxUsers,
    required this.subscriptionDaysTotal,
    required this.daysActive,
    required this.isExpired,
    required this.daysRemaining,
  });
}
