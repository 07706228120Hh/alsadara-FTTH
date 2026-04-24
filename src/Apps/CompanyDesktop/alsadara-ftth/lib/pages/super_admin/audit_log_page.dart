/// صفحة سجل العمليات المركزي - Centralized Audit Log
/// تعرض سجل كامل لكل العمليات عبر جميع الشركات
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme/energy_dashboard_theme.dart';
import '../../services/api/api_client.dart';
import 'widgets/super_admin_widgets.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _logs = [];
  String _typeFilter = 'all';
  String _searchQuery = '';
  int _currentPage = 1;
  final int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);

    try {
      final client = ApiClient.instance;
      final response = await client.get(
        '/superadmin/audit-logs?page=$_currentPage&pageSize=$_pageSize',
        (json) => json,
        useInternalKey: true,
      );

      if (mounted) {
        if (response.isSuccess && response.data != null) {
          final data = response.data;
          final logsData = data is List
              ? data
              : (data is Map ? (data['data'] ?? data['logs'] ?? []) : []);

          setState(() {
            _logs = (logsData as List)
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _isLoading = false;
          });
        } else {
          // Use mock data for demo
          _generateMockLogs();
        }
      }
    } catch (e) {
      if (mounted) _generateMockLogs();
    }
  }

  void _generateMockLogs() {
    final now = DateTime.now();
    final actions = [
      {'action': 'login', 'desc': 'تسجيل دخول', 'user': 'أحمد محمد', 'company': 'شركة الأمل'},
      {'action': 'company_created', 'desc': 'إنشاء شركة جديدة', 'user': 'مدير النظام', 'company': 'النظام'},
      {'action': 'subscription_renewed', 'desc': 'تجديد اشتراك', 'user': 'مدير النظام', 'company': 'شركة النور'},
      {'action': 'user_created', 'desc': 'إنشاء مستخدم جديد', 'user': 'علي حسين', 'company': 'شركة الأمل'},
      {'action': 'settings_changed', 'desc': 'تعديل إعدادات الشركة', 'user': 'خالد عمر', 'company': 'شركة البناء'},
      {'action': 'status_changed', 'desc': 'تغيير حالة شركة', 'user': 'مدير النظام', 'company': 'شركة التقنية'},
      {'action': 'permission_changed', 'desc': 'تعديل صلاحيات', 'user': 'سعد يوسف', 'company': 'شركة الأمل'},
      {'action': 'logout', 'desc': 'تسجيل خروج', 'user': 'محمد علي', 'company': 'شركة النور'},
      {'action': 'password_reset', 'desc': 'إعادة تعيين كلمة المرور', 'user': 'مدير النظام', 'company': 'النظام'},
      {'action': 'data_export', 'desc': 'تصدير بيانات', 'user': 'أحمد محمد', 'company': 'شركة الأمل'},
    ];

    setState(() {
      _logs = List.generate(30, (i) {
        final action = actions[i % actions.length];
        return {
          'id': 'log-$i',
          'action': action['action'],
          'description': action['desc'],
          'userName': action['user'],
          'companyName': action['company'],
          'ipAddress': '192.168.1.${100 + i}',
          'timestamp': now.subtract(Duration(minutes: i * 15 + i * 3)).toIso8601String(),
        };
      });
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredLogs {
    var list = List<Map<String, dynamic>>.from(_logs);

    if (_typeFilter != 'all') {
      list = list.where((l) => l['action'] == _typeFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      list = list
          .where((l) =>
              (l['description'] ?? '').toString().contains(_searchQuery) ||
              (l['userName'] ?? '').toString().contains(_searchQuery) ||
              (l['companyName'] ?? '').toString().contains(_searchQuery))
          .toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: EnergyDashboardTheme.bgPrimary,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: SAPageHeader(
              title: 'سجل العمليات المركزي',
              subtitle: 'تتبع كل العمليات عبر جميع الشركات',
              icon: Icons.history_rounded,
              color: EnergyDashboardTheme.neonBlue,
              secondaryColor: EnergyDashboardTheme.neonPurple,
              onRefresh: _loadLogs,
              trailing: SACountBadge(
                count: _filteredLogs.length,
                color: EnergyDashboardTheme.neonBlue,
              ),
            ),
          ),
          // Filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SAFilterBar(
              searchHint: 'بحث في السجلات...',
              onSearchChanged: (v) => setState(() => _searchQuery = v),
              extraWidgets: [
                const SizedBox(width: 10),
                SADropdown(
                  items: const [
                    SADropdownItem(value: 'all', label: 'كل العمليات'),
                    SADropdownItem(value: 'login', label: 'تسجيل دخول'),
                    SADropdownItem(value: 'logout', label: 'تسجيل خروج'),
                    SADropdownItem(value: 'company_created', label: 'إنشاء شركة'),
                    SADropdownItem(value: 'subscription_renewed', label: 'تجديد اشتراك'),
                    SADropdownItem(value: 'user_created', label: 'إنشاء مستخدم'),
                    SADropdownItem(value: 'settings_changed', label: 'تعديل إعدادات'),
                    SADropdownItem(value: 'status_changed', label: 'تغيير حالة'),
                    SADropdownItem(value: 'permission_changed', label: 'تعديل صلاحيات'),
                  ],
                  value: _typeFilter,
                  onChanged: (v) => setState(() => _typeFilter = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: EnergyDashboardTheme.neonGreen))
                : _buildLogsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList() {
    final logs = _filteredLogs;

    if (logs.isEmpty) {
      return EnergyDashboardTheme.emptyWidget(
        message: 'لا توجد سجلات مطابقة',
        icon: Icons.history_rounded,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, index) => _buildLogItem(logs[index]),
    );
  }

  Widget _buildLogItem(Map<String, dynamic> log) {
    final action = log['action'] ?? '';
    final color = _getActionColor(action);
    final icon = _getActionIcon(action);

    DateTime? timestamp;
    try {
      timestamp = DateTime.parse(log['timestamp'] ?? '');
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: EnergyDashboardTheme.borderColor.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          // Description
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log['description'] ?? '',
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.person_rounded,
                        color: EnergyDashboardTheme.textMuted, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      log['userName'] ?? '',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.business_rounded,
                        color: EnergyDashboardTheme.textMuted, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      log['companyName'] ?? '',
                      style: GoogleFonts.cairo(
                        color: EnergyDashboardTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // IP
          Expanded(
            flex: 1,
            child: Text(
              log['ipAddress'] ?? '',
              style: GoogleFonts.cairo(
                color: EnergyDashboardTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ),
          // Time
          if (timestamp != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  DateFormat('yyyy/MM/dd').format(timestamp),
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  DateFormat('HH:mm').format(timestamp),
                  style: GoogleFonts.cairo(
                    color: EnergyDashboardTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'login':
        return EnergyDashboardTheme.neonGreen;
      case 'logout':
        return EnergyDashboardTheme.textMuted;
      case 'company_created':
        return EnergyDashboardTheme.neonBlue;
      case 'subscription_renewed':
        return EnergyDashboardTheme.neonPurple;
      case 'user_created':
        return EnergyDashboardTheme.neonOrange;
      case 'settings_changed':
        return EnergyDashboardTheme.warning;
      case 'status_changed':
        return EnergyDashboardTheme.neonPink;
      case 'permission_changed':
        return EnergyDashboardTheme.danger;
      case 'password_reset':
        return EnergyDashboardTheme.warning;
      case 'data_export':
        return EnergyDashboardTheme.neonBlue;
      default:
        return EnergyDashboardTheme.textMuted;
    }
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'login':
        return Icons.login_rounded;
      case 'logout':
        return Icons.logout_rounded;
      case 'company_created':
        return Icons.add_business_rounded;
      case 'subscription_renewed':
        return Icons.autorenew_rounded;
      case 'user_created':
        return Icons.person_add_rounded;
      case 'settings_changed':
        return Icons.settings_rounded;
      case 'status_changed':
        return Icons.toggle_on_rounded;
      case 'permission_changed':
        return Icons.shield_rounded;
      case 'password_reset':
        return Icons.lock_reset_rounded;
      case 'data_export':
        return Icons.download_rounded;
      default:
        return Icons.info_rounded;
    }
  }
}
