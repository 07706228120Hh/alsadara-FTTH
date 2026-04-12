/// صفحة مركز الموارد البشرية - HR Hub
/// تحتوي على جميع أزرار الموارد البشرية في شاشة واحدة
library;

import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';
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
    final r = context.responsive;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              // AppBar مع تصميم متناسق
              SliverAppBar(
                expandedHeight: r.isMobile ? 130 : 160,
                pinned: true,
                backgroundColor: const Color(0xFF0D47A1),
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_rounded,
                      color: Colors.white, size: r.appBarIconSize),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: const [
                  NotificationBell(),
                  SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: true,
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(height: r.isMobile ? 12 : 20),
                        Container(
                          width: r.isMobile ? 44 : 56,
                          height: r.isMobile ? 44 : 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.15),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3), width: 2),
                          ),
                          child: Icon(Icons.groups_rounded,
                              color: Colors.white, size: r.isMobile ? 22 : 30),
                        ),
                        SizedBox(height: r.isMobile ? 6 : 10),
                        Text(
                          'الموارد البشرية',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: r.titleSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إدارة الموظفين والحضور والرواتب',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: r.captionSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // المحتوى - الأزرار
              SliverPadding(
                padding: EdgeInsets.all(r.contentPaddingH),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: r.isMobile ? 200 : 280,
                    mainAxisSpacing: r.gridSpacing,
                    crossAxisSpacing: r.gridSpacing,
                    childAspectRatio: r.isMobile ? 1.2 : 1.4,
                  ),
                  delegate: SliverChildListDelegate(
                    _buildHrCards(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildHrCards(BuildContext context) {
    return [
      // 1) إدارة المستخدمين
      _HrCard(
        icon: Icons.people_rounded,
        title: 'إدارة المستخدمين',
        subtitle: 'إضافة وتعديل بيانات الموظفين',
        gradient: [Colors.blue[600]!, Colors.blue[800]!],
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
      _HrCard(
        icon: Icons.schedule_rounded,
        title: 'جداول الدوام',
        subtitle: 'إدارة أوقات العمل والورديات',
        gradient: [Colors.teal[500]!, Colors.teal[700]!],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const WorkSchedulesPage(),
          ),
        ),
      ),

      // 4) الإجازات
      _HrCard(
        icon: Icons.beach_access_rounded,
        title: 'الإجازات',
        subtitle: 'طلبات الإجازات والأرصدة',
        gradient: [Colors.orange[600]!, Colors.orange[800]!],
        badgeCount: _pendingLeaves,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const LeaveManagementPage(),
          ),
        ),
      ),

      // 5) الرواتب
      _HrCard(
        icon: Icons.payments_rounded,
        title: 'الرواتب',
        subtitle: 'مسيّر الرواتب والخصومات',
        gradient: [Colors.deepPurple[500]!, Colors.deepPurple[700]!],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SalaryManagementPage(),
          ),
        ),
      ),

      // 6) الخصومات والمكافآت
      _HrCard(
        icon: Icons.receipt_long_rounded,
        title: 'الخصومات والمكافآت',
        subtitle: 'إدارة الخصومات والمكافآت والبدلات',
        gradient: [Colors.red[500]!, Colors.red[700]!],
        badgeCount: _pendingWithdrawals,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DeductionsBonusesPage(),
          ),
        ),
      ),

      // 7) التقارير والإحصائيات
      _HrCard(
        icon: Icons.assessment_rounded,
        title: 'التقارير والإحصائيات',
        subtitle: 'تقارير شاملة مع تصدير CSV',
        gradient: [Colors.cyan[600]!, Colors.cyan[800]!],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const HrReportsPage(),
          ),
        ),
      ),

      // 8) داشبورد المتابعة
      _HrCard(
        icon: Icons.dashboard_rounded,
        title: 'داشبورد المتابعة',
        subtitle: 'إحصائيات وتحليلات الأداء',
        gradient: [const Color(0xFF1A237E), const Color(0xFF283593)],
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

/// بطاقة HR فردية
class _HrCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;
  final int badgeCount;

  const _HrCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  State<_HrCard> createState() => _HrCardState();
}

class _HrCardState extends State<_HrCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        transform: _isHovered
            ? (Matrix4.identity()..translate(0.0, -4.0))
            : Matrix4.identity(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            splashColor: widget.gradient[0].withOpacity(0.1),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isHovered
                      ? widget.gradient[0].withOpacity(0.3)
                      : const Color(0xFFE8E8E8),
                  width: _isHovered ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _isHovered
                        ? widget.gradient[0].withOpacity(0.15)
                        : Colors.black.withOpacity(0.06),
                    blurRadius: _isHovered ? 16 : 10,
                    offset: Offset(0, _isHovered ? 6 : 3),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final r = context.responsive;
                  return Padding(
                    padding: EdgeInsets.all(r.isMobile ? 12 : 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // أيقونة + بادج
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: r.isMobile ? 36 : 46,
                              height: r.isMobile ? 36 : 46,
                              decoration: BoxDecoration(
                                borderRadius:
                                    BorderRadius.circular(r.isMobile ? 10 : 14),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: widget.gradient,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: widget.gradient[0].withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Icon(widget.icon,
                                  color: Colors.white, size: r.isMobile ? 18 : 24),
                            ),
                            if (widget.badgeCount > 0)
                              Positioned(
                                top: -6,
                                right: -6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4), blurRadius: 4)],
                                  ),
                                  constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
                                  child: Text(
                                    widget.badgeCount > 99 ? '99+' : widget.badgeCount.toString(),
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const Spacer(),
                        // العنوان
                        Text(
                          widget.title,
                          style: TextStyle(
                            color: const Color(0xFF2D3436),
                            fontSize: r.bodySize,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // الوصف
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: r.captionSize,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
