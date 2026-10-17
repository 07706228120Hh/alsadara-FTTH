/// صفحة مركز الموارد البشرية - HR Hub
/// تحتوي على جميع أزرار الموارد البشرية في شاشة واحدة
library;

import 'package:flutter/material.dart';
import '../frontend/frontend.dart';
import 'work_schedules_page.dart';
import 'leave_management_page.dart';
import 'salary_management_page.dart';
import 'deductions_bonuses_page.dart';
import 'hr_reports_page.dart';
import 'users_page.dart';
import 'users_page_firebase.dart';
import 'users_page_vps.dart';
import '../task/audit_dashboard_page.dart';
import '../services/vps_auth_service.dart';
import '../services/attendance_api_service.dart';
import '../widgets/notification_bell.dart';
class HrHubPage extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;
  final String? tenantId;
  final String? tenantCode;

  const HrHubPage({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
    this.tenantId,
    this.tenantCode,
  });

  @override
  State<HrHubPage> createState() => _HrHubPageState();
}

class _HrHubPageState extends State<HrHubPage> {
  int _pendingLeaves = 0;
  int _pendingWithdrawals = 0;

  @override
  void initState() {
    super.initState();
    _fetchCounts();
  }

  Future<void> _fetchCounts() async {
    try {
      final results = await Future.wait([
        AttendanceApiService.instance.getLeaveSummary().catchError((_) => <String, dynamic>{}),
        AttendanceApiService.instance.getWithdrawalRequests(status: 0, page: 1, pageSize: 1).catchError((_) => <String, dynamic>{}),
      ]);

      final leaveRaw = results[0];
      final withdrawRaw = results[1];
      debugPrint('📊 HR leaves: $leaveRaw');
      debugPrint('📊 HR withdrawals: $withdrawRaw');

      if (mounted) {
        final leaveData = (leaveRaw['data'] is Map) ? leaveRaw['data'] as Map<String, dynamic> : leaveRaw;
        final withdrawData = (withdrawRaw['data'] is Map) ? withdrawRaw['data'] as Map<String, dynamic> : withdrawRaw;
        setState(() {
          _pendingLeaves = _extractInt(leaveData, 'Pending') + _extractInt(leaveData, 'pending');
          _pendingWithdrawals = _extractInt(withdrawData, 'Total') + _extractInt(withdrawData, 'total');
        });
      }
    } catch (e) {
      debugPrint('❌ HR _fetchCounts error: $e');
    }
  }

  int _extractInt(Map<String, dynamic> map, String key) {
    final val = map[key];
    if (val == null) return 0;
    if (val is int) return val;
    if (val is double) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      appBar: SdAppBar(
        title: 'الموارد البشرية',
        subtitle: 'إدارة الموظفين والحضور والرواتب',
        actions: const [NotificationBell()],
      ),
      body: SdTileGrid(
        minTileWidth: 260,
        maxColumns: 4,
        children: _buildHrTiles(context),
      ),
    );
  }

  List<Widget> _buildHrTiles(BuildContext context) {
    return [
      // 1) إدارة المستخدمين
      SdMenuTile(
        icon: Icons.people_rounded,
        title: 'إدارة المستخدمين',
        subtitle: 'إضافة وتعديل بيانات الموظفين',
        onTap: () {
          final companyId =
              widget.tenantId ?? VpsAuthService.instance.currentCompanyId;
          final companyCode =
              widget.tenantCode ?? VpsAuthService.instance.currentCompanyCode;
          final companyName = VpsAuthService.instance.currentCompanyName ?? 'الشركة';
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => companyId != null && companyCode != null
                  ? UsersPageVPS(
                      companyId: companyId,
                      companyName: companyName,
                      permissions: {'users': true},
                    )
                  : companyId != null
                      ? UsersPageFirebase(
                          tenantId: companyId,
                          permissions: widget.permissions,
                        )
                      : UsersPage(permissions: widget.permissions),
            ),
          );
        },
      ),

      // 2) جداول الدوام
      SdMenuTile(
        icon: Icons.schedule_rounded,
        title: 'جداول الدوام',
        subtitle: 'إدارة أوقات العمل والورديات',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const WorkSchedulesPage(),
          ),
        ),
      ),

      // 4) الإجازات
      SdMenuTile(
        icon: Icons.beach_access_rounded,
        title: 'الإجازات',
        subtitle: 'طلبات الإجازات والأرصدة',
        badge: _pendingLeaves,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const LeaveManagementPage(),
          ),
        ),
      ),

      // 5) الرواتب
      SdMenuTile(
        icon: Icons.payments_rounded,
        title: 'الرواتب',
        subtitle: 'مسيّر الرواتب والخصومات',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SalaryManagementPage(),
          ),
        ),
      ),

      // 6) الخصومات والمكافآت
      SdMenuTile(
        icon: Icons.receipt_long_rounded,
        title: 'الخصومات والمكافآت',
        subtitle: 'إدارة الخصومات والمكافآت والبدلات',
        badge: _pendingWithdrawals,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DeductionsBonusesPage(),
          ),
        ),
      ),

      // 7) التقارير والإحصائيات
      SdMenuTile(
        icon: Icons.assessment_rounded,
        title: 'التقارير والإحصائيات',
        subtitle: 'تقارير شاملة مع تصدير CSV',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HrReportsPage(),
          ),
        ),
      ),

      // 8) داشبورد المتابعة
      SdMenuTile(
        icon: Icons.dashboard_rounded,
        title: 'داشبورد المتابعة',
        subtitle: 'إحصائيات وتحليلات الأداء',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AuditDashboardPage(
              username: widget.username,
              permissions: widget.permissions,
              department: widget.department,
              center: widget.center,
            ),
          ),
        ),
      ),
    ];
  }

  Map<String, bool> _parsePermissions(String perms) {
    try {
      final map = <String, bool>{};
      // parse JSON-like string if needed
      if (perms.startsWith('{')) {
        final cleaned =
            perms.replaceAll('{', '').replaceAll('}', '').replaceAll('"', '');
        for (final pair in cleaned.split(',')) {
          final kv = pair.split(':');
          if (kv.length == 2) {
            map[kv[0].trim()] = kv[1].trim().toLowerCase() == 'true';
          }
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
