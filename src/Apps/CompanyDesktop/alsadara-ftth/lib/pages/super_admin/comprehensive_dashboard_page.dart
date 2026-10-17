/// لوحة تحكم شاملة - Super Admin Comprehensive Dashboard
/// تعرض نظرة عامة كاملة على كل الشركات والنظام
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/api/api_client.dart';
import 'widgets/super_admin_widgets.dart';

import '../../frontend/tokens/sd_colors.dart' show SdColors;
import '../../frontend/components/sd_dash_kit.dart';
class ComprehensiveDashboardPage extends StatefulWidget {
  const ComprehensiveDashboardPage({super.key});

  @override
  State<ComprehensiveDashboardPage> createState() =>
      _ComprehensiveDashboardPageState();
}

class _ComprehensiveDashboardPageState
    extends State<ComprehensiveDashboardPage> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _dashboardData;
  final _numberFormat = NumberFormat('#,###');

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
      final client = ApiClient.instance;
      final response = await client.get(
        '/superadmin/comprehensive-dashboard',
        (json) => json,
      );

      if (mounted) {
        if (response.isSuccess && response.data != null) {
          setState(() {
            _dashboardData = response.data is Map<String, dynamic>
                ? response.data
                : {};
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = 'فشل تحميل البيانات';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'حدث خطأ في الاتصال';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: SdColors.ground,
        child: const Center(
          child:
              CircularProgressIndicator(color: SdColors.success),
        ),
      );
    }

    if (_error != null) {
      return Container(
        color: SdColors.ground,
        child: SdDashKit.errorWidget(
          message: _error!,
          onRetry: _loadData,
        ),
      );
    }

    final data = _dashboardData ?? {};
    final companySummary =
        data['companySummary'] as Map<String, dynamic>? ?? {};
    final usersSummary = data['usersSummary'] as Map<String, dynamic>? ?? {};
    final ordersSummary = data['ordersSummary'] as Map<String, dynamic>? ?? {};
    final alerts = data['alerts'] as List<dynamic>? ?? [];
    final companies = data['companies'] as List<dynamic>? ?? [];
    final systemHealth =
        data['systemHealth'] as Map<String, dynamic>? ?? {};

    return Container(
      color: SdColors.ground,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // === Header ===
          SAPageHeader(
            title: 'لوحة التحكم الشاملة',
            subtitle: 'نظرة عامة على كل الشركات والنظام',
            icon: Icons.dashboard_customize_rounded,
            color: SdColors.success,
            onRefresh: _loadData,
            trailing: Text(
              DateFormat('HH:mm').format(DateTime.now()),
              style: TextStyle(
                fontFamily: 'Cairo',
                color: SdColors.faint,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // === Alerts ===
          if (alerts.isNotEmpty) ...[
            SAAlertBanner(
              alerts: alerts.map((alert) {
                final a = alert as Map<String, dynamic>;
                return SAAlertItem(
                  type: a['type'] ?? 'info',
                  title: a['title'] ?? '',
                  message: a['message'] ?? '',
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // === Main Stats Cards ===
          Row(
            children: [
              Expanded(
                child: SAStatCard(
                  title: 'إجمالي الشركات',
                  value: '${companySummary['total'] ?? 0}',
                  subtitle: '${companySummary['active'] ?? 0} نشطة',
                  icon: Icons.business_rounded,
                  color: SdColors.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SAStatCard(
                  title: 'إجمالي المستخدمين',
                  value: '${usersSummary['total'] ?? 0}',
                  subtitle: '${usersSummary['activeToday'] ?? 0} نشط اليوم',
                  icon: Icons.people_rounded,
                  color: SdColors.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SAStatCard(
                  title: 'منتهية الاشتراك',
                  value: '${companySummary['expired'] ?? 0}',
                  subtitle:
                      '${companySummary['expiringIn7Days'] ?? 0} خلال 7 أيام',
                  icon: Icons.timer_off_rounded,
                  color: SdColors.danger,
                  alert: (companySummary['expired'] ?? 0) > 0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SAStatCard(
                  title: 'الطلبات اليوم',
                  value: '${ordersSummary['today'] ?? 0}',
                  subtitle: '${ordersSummary['thisMonth'] ?? 0} هذا الشهر',
                  icon: Icons.shopping_cart_rounded,
                  color: SdColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // === Company & Users Breakdown ===
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SASection(
                  title: 'توزيع حالة الشركات',
                  icon: Icons.pie_chart_rounded,
                  iconColor: SdColors.success,
                  child: _buildBreakdownItems(
                    items: [
                      _BreakdownItem('نشطة', companySummary['active'] ?? 0,
                          SdColors.success),
                      _BreakdownItem(
                          'تنتهي خلال 7 أيام',
                          companySummary['expiringIn7Days'] ?? 0,
                          SdColors.danger),
                      _BreakdownItem(
                          'تنتهي خلال 30 يوم',
                          companySummary['expiringIn30Days'] ?? 0,
                          SdColors.warning),
                      _BreakdownItem('منتهية', companySummary['expired'] ?? 0,
                          SdColors.danger),
                      _BreakdownItem('معلقة', companySummary['suspended'] ?? 0,
                          SdColors.faint),
                      _BreakdownItem(
                          'جديدة هذا الشهر',
                          companySummary['newThisMonth'] ?? 0,
                          SdColors.platformBase),
                    ],
                    total: companySummary['active'] ?? 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SASection(
                  title: 'نشاط المستخدمين',
                  icon: Icons.group_rounded,
                  iconColor: SdColors.success,
                  child: _buildBreakdownItems(
                    items: [
                      _BreakdownItem('إجمالي المستخدمين',
                          usersSummary['total'] ?? 0, SdColors.info),
                      _BreakdownItem(
                          'نشط اليوم',
                          usersSummary['activeToday'] ?? 0,
                          SdColors.success),
                      _BreakdownItem(
                          'نشط هذا الأسبوع',
                          usersSummary['activeThisWeek'] ?? 0,
                          SdColors.warning),
                      _BreakdownItem(
                          'جدد هذا الشهر',
                          usersSummary['newThisMonth'] ?? 0,
                          SdColors.platformBase),
                    ],
                    total: usersSummary['total'] ?? 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // === Companies Table ===
          SASection(
            title: 'حالة الشركات التفصيلية',
            icon: Icons.table_chart_rounded,
            iconColor: SdColors.info,
            trailing: SACountBadge(
              count: companies.length,
              color: SdColors.info,
            ),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SATableHeader(
                  columns: const [
                    SATableColumn(label: 'الشركة', flex: 3),
                    SATableColumn(label: 'الحالة', flex: 2),
                    SATableColumn(label: 'المستخدمين', flex: 2),
                    SATableColumn(label: 'انتهاء الاشتراك', flex: 2),
                    SATableColumn(label: 'أيام متبقية', flex: 1),
                  ],
                ),
                if (companies.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'لا توجد شركات',
                        style: TextStyle(
                            fontFamily: 'Cairo',
                            color: SdColors.faint),
                      ),
                    ),
                  )
                else
                  ...companies.map((c) {
                    final company = c as Map<String, dynamic>;
                    return _buildCompanyRow(company);
                  }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // === System Health ===
          SASection(
            title: 'حالة النظام',
            icon: Icons.monitor_heart_rounded,
            iconColor: SdColors.success,
            trailing: SAStatusBadge(
              text: systemHealth['status'] == 'operational'
                  ? 'يعمل بشكل طبيعي'
                  : 'يوجد مشاكل',
              color: systemHealth['status'] == 'operational'
                  ? SdColors.success
                  : SdColors.danger,
              icon: systemHealth['status'] == 'operational'
                  ? Icons.check_circle_rounded
                  : Icons.error_rounded,
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _healthItem('API', systemHealth['apiUptime'] ?? '-',
                    Icons.api_rounded),
                _healthItem('قاعدة البيانات',
                    systemHealth['databaseStatus'] ?? '-', Icons.storage_rounded),
                _healthItem('آخر نسخة احتياطية',
                    systemHealth['lastBackup'] ?? '-', Icons.backup_rounded),
                _healthItem('وقت السيرفر',
                    systemHealth['serverTime'] ?? '-', Icons.access_time_rounded),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Breakdown Items (shared for company & users sections)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildBreakdownItems({
    required List<_BreakdownItem> items,
    required int total,
  }) {
    return Column(
      children: items
          .map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: item.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: SdColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      _numberFormat.format(item.value),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: SdColors.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (total > 0 && item.value > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: item.color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${((item.value / total) * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: item.color,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ))
          .toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Company Table Row
  // ═══════════════════════════════════════════════════════════════

  Widget _buildCompanyRow(Map<String, dynamic> company) {
    final status = company['status'] ?? 'active';
    final statusColor = saStatusColor(status);
    final statusLabel = saStatusLabel(status);
    final daysRemaining = company['daysRemaining'] ?? 0;
    final currentUsers = company['currentUsers'] ?? 0;
    final maxUsers = company['maxUsers'] ?? 0;

    String endDateStr = '';
    try {
      final endDate = DateTime.parse(
          company['subscriptionEndDate']?.toString() ?? '');
      endDateStr = DateFormat('yyyy/MM/dd').format(endDate);
    } catch (_) {
      endDateStr = '-';
    }

    return SATableRow(
      flexes: const [3, 2, 2, 2, 1],
      highlightColor: status == 'expired' || status == 'critical'
          ? statusColor.withOpacity(0.05)
          : null,
      cells: [
        // Company name + avatar
        Row(
          children: [
            SACompanyAvatar(
              name: company['name']?.toString() ?? '?',
              color: statusColor,
              size: 30,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    company['name']?.toString() ?? '',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: SdColors.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    company['code']?.toString() ?? '',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: SdColors.faint,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Status badge
        SAStatusBadge(
          text: statusLabel,
          color: statusColor,
          icon: status == 'active'
              ? Icons.check_circle_rounded
              : status == 'expired'
                  ? Icons.cancel_rounded
                  : Icons.warning_rounded,
        ),
        // Users + progress bar
        Row(
          children: [
            Text(
              '$currentUsers / $maxUsers',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: SdColors.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SAProgressBar(
                value: maxUsers > 0
                    ? (currentUsers / maxUsers).clamp(0.0, 1.0)
                    : 0,
                height: 4,
              ),
            ),
          ],
        ),
        // End date
        Text(
          endDateStr,
          style: TextStyle(
            fontFamily: 'Cairo',
            color: SdColors.muted,
            fontSize: 12,
          ),
        ),
        // Days remaining
        SADaysRemainingBadge(days: daysRemaining),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Health Item
  // ═══════════════════════════════════════════════════════════════

  Widget _healthItem(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: SdColors.faint, size: 14),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: TextStyle(
            fontFamily: 'Cairo',
            color: SdColors.faint,
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Cairo',
            color: SdColors.success,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _BreakdownItem {
  final String label;
  final int value;
  final Color color;

  _BreakdownItem(this.label, this.value, this.color);
}
