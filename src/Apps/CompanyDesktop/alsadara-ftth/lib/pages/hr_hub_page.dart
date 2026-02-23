/// صفحة مركز الموارد البشرية - HR Hub
/// تحتوي على جميع أزرار الموارد البشرية في شاشة واحدة
library;

import 'package:flutter/material.dart';
import 'attendance_page.dart';
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

class HrHubPage extends StatelessWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;
  @Deprecated('استخدم PermissionManager.instance.canView() مباشرة')
  final Map<String, bool> pageAccess;
  final String? tenantId;
  final String? tenantCode;

  const HrHubPage({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
    this.pageAccess = const {},
    this.tenantId,
    this.tenantCode,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: CustomScrollView(
          slivers: [
            // AppBar مع تصميم متناسق
            SliverAppBar(
              expandedHeight: 160,
              pinned: true,
              backgroundColor: const Color(0xFF0D47A1),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
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
                  child: SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.15),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.3), width: 2),
                          ),
                          child: const Icon(Icons.groups_rounded,
                              color: Colors.white, size: 30),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'الموارد البشرية',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إدارة الموظفين والحضور والرواتب',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // المحتوى - الأزرار
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.4,
                ),
                delegate: SliverChildListDelegate(
                  _buildHrCards(context),
                ),
              ),
            ),
          ],
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
              tenantId ?? VpsAuthService.instance.currentCompanyId;
          final companyCode =
              tenantCode ?? VpsAuthService.instance.currentCompanyCode;
          final companyName = department.isNotEmpty
              ? department
              : (VpsAuthService.instance.currentCompanyName ?? 'الشركة');
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
                          permissions: permissions,
                          pageAccess: pageAccess,
                        )
                      : UsersPage(permissions: permissions),
            ),
          );
        },
      ),

      // 2) البصمة
      _HrCard(
        icon: Icons.fingerprint_rounded,
        title: 'البصمة',
        subtitle: 'تسجيل الحضور والانصراف',
        gradient: [Colors.indigo[500]!, Colors.indigo[700]!],
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AttendancePage(
              username: username,
              center: center,
              permissions: permissions,
            ),
          ),
        ),
      ),

      // 3) جداول الدوام
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
              username: username,
              permissions: permissions,
              department: department,
              center: center,
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

  const _HrCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
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
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // أيقونة
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
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
                      child: Icon(widget.icon, color: Colors.white, size: 24),
                    ),
                    const Spacer(),
                    // العنوان
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Color(0xFF2D3436),
                        fontSize: 14,
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
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
