/// 👤 صفحة الملف الشخصي الشامل للموظف — نظام HR متكامل
/// تبويبات: HR | الحضور | المهام | الرواتب | الصلاحيات | FTTH | المعاملات | التقييم
/// جميع التبويبات والأزرار والحقول مرتبطة بنظام الصلاحيات V2
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/employee_profile_service.dart';
import '../../services/permission_checker.dart';
import 'tabs/hr_info_tab.dart';
import 'tabs/attendance_tab.dart';
import 'tabs/tasks_tab.dart';
import 'tabs/salary_tab.dart';
import 'tabs/permissions_tab.dart';
import 'tabs/ftth_tab.dart';
import 'tabs/transactions_tab.dart';
import 'tabs/performance_tab.dart';

class EmployeeProfilePage extends StatefulWidget {
  final String companyId;
  final String companyName;
  final String employeeId;
  final Map<String, dynamic> employeeData;

  const EmployeeProfilePage({
    super.key,
    required this.companyId,
    required this.companyName,
    required this.employeeId,
    required this.employeeData,
  });

  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage>
    with TickerProviderStateMixin, PermissionCheckerMixin {
  late TabController _tabController;
  final EmployeeProfileService _service = EmployeeProfileService.instance;
  final PermissionManager _pm = PermissionManager.instance;

  Map<String, dynamic> _employee = {};
  bool _isLoading = true;
  String? _error;

  // التبويبات المرئية حسب الصلاحيات
  final List<_TabInfo> _visibleTabs = [];

  @override
  void initState() {
    super.initState();
    _employee = Map<String, dynamic>.from(widget.employeeData);
    _buildVisibleTabs();
    _tabController = TabController(
      length: _visibleTabs.length,
      vsync: this,
    );
    _loadFullProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// بناء قائمة التبويبات المرئية حسب الصلاحيات
  void _buildVisibleTabs() {
    _visibleTabs.clear();

    // 1. HR — يظهر دائماً لمن لديه users.view
    if (_pm.canView('users')) {
      _visibleTabs.add(_TabInfo(
        key: 'hr',
        label: 'بيانات HR',
        icon: Icons.badge_outlined,
      ));
    }

    // 2. الحضور — يحتاج attendance.view
    if (_pm.canView('attendance')) {
      _visibleTabs.add(_TabInfo(
        key: 'attendance',
        label: 'الحضور',
        icon: Icons.fingerprint,
      ));
    }

    // 3. المهام — يحتاج tasks.view
    if (_pm.canView('tasks')) {
      _visibleTabs.add(_TabInfo(
        key: 'tasks',
        label: 'المهام',
        icon: Icons.task_alt,
      ));
    }

    // 4. الرواتب — يحتاج accounts.view أو accounting.view
    if (_pm.canView('accounts') || _pm.canView('accounting')) {
      _visibleTabs.add(_TabInfo(
        key: 'salary',
        label: 'الرواتب',
        icon: Icons.payments_outlined,
      ));
    }

    // 5. الصلاحيات — فقط CompanyAdmin+ (يفحص users.edit)
    if (_pm.canEdit('users')) {
      _visibleTabs.add(_TabInfo(
        key: 'permissions',
        label: 'الصلاحيات',
        icon: Icons.security,
      ));
    }

    // 6. FTTH — يحتاج accounting.view + الموظف مشغل FTTH
    final ftthUser = _employee['ftthUsername'] ??
        _employee['FtthUsername'] ??
        _employee['fTthUsername'];
    final role = _employee['role'] ?? _employee['Role'] ?? '';
    final isTechOrOp =
        role == 'Technician' || role == 'TechnicalLeader' || ftthUser != null;
    if (isTechOrOp && (_pm.canView('accounts') || _pm.canView('accounting'))) {
      _visibleTabs.add(_TabInfo(
        key: 'ftth',
        label: 'FTTH',
        icon: Icons.router,
      ));
    }

    // 7. المعاملات المالية — يحتاج transactions.view أو accounts.view
    if (_pm.canView('transactions') || _pm.canView('technicians')) {
      _visibleTabs.add(_TabInfo(
        key: 'transactions',
        label: 'المعاملات',
        icon: Icons.receipt_long,
      ));
    }

    // 8. التقييم — يحتاج tasks.view
    if (_pm.canView('tasks')) {
      _visibleTabs.add(_TabInfo(
        key: 'performance',
        label: 'التقييم',
        icon: Icons.star_outline,
      ));
    }

    // fallback: لو لا يوجد تبويب واحد مرئي
    if (_visibleTabs.isEmpty) {
      _visibleTabs.add(_TabInfo(
        key: 'hr',
        label: 'بيانات HR',
        icon: Icons.badge_outlined,
      ));
    }
  }

  Future<void> _loadFullProfile() async {
    setState(() => _isLoading = true);
    try {
      final data =
          await _service.getEmployee(widget.companyId, widget.employeeId);
      if (data != null) {
        setState(() {
          _employee = data;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  // ═══════════════ ألوان ═══════════════
  static const _bgPage = Color(0xFFF5F6FA);
  static const _headerBg = Color(0xFF2C3E50);
  static const _accent = Color(0xFF3498DB);
  static const _textDark = Color(0xFF333333);
  static const _textGray = Color(0xFF7F8C8D);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgPage,
        body: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(child: _buildTabContent()),
          ],
        ),
      ),
    );
  }

  /// الشريط العلوي — صورة + اسم + دور + حالة
  Widget _buildHeader() {
    final name = _employee['fullName'] ?? _employee['FullName'] ?? 'موظف';
    final role = _employee['role'] ?? _employee['Role'] ?? '';
    final code = _employee['employeeCode'] ?? _employee['EmployeeCode'] ?? '';
    final dept = _employee['department'] ?? _employee['Department'] ?? '';
    final isActive = _employee['isActive'] ?? _employee['IsActive'] ?? true;
    final phone = _employee['phoneNumber'] ?? _employee['PhoneNumber'] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: _headerBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // زر الرجوع
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_forward_rounded),
              tooltip: 'رجوع',
              style: IconButton.styleFrom(foregroundColor: Colors.white70),
            ),
            const SizedBox(width: 12),
            // الصورة
            CircleAvatar(
              radius: 24,
              backgroundColor: _getRoleColor(role),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.cairo(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // الاسم والمعلومات
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      _headerChip(_getRoleLabel(role), _getRoleColor(role)),
                      if (dept.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _headerChip(dept, Colors.white24),
                      ],
                      if (code.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _headerChip(code, Colors.white24),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // الحالة
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.green.withOpacity(0.2)
                    : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? Colors.green : Colors.red,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isActive ? Icons.check_circle : Icons.cancel,
                    color: isActive ? Colors.green : Colors.red,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isActive ? 'نشط' : 'معطل',
                    style: GoogleFonts.cairo(
                      color: isActive ? Colors.green : Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // هاتف
            if (phone.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.phone, color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(phone,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            const SizedBox(width: 8),
            // زر تحديث
            IconButton(
              onPressed: _loadFullProfile,
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'تحديث',
              style: IconButton.styleFrom(foregroundColor: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: GoogleFonts.cairo(color: Colors.white, fontSize: 11),
      ),
    );
  }

  /// شريط التبويبات
  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelColor: _accent,
        unselectedLabelColor: _textGray,
        indicatorColor: _accent,
        indicatorWeight: 3,
        labelStyle: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
        unselectedLabelStyle: GoogleFonts.cairo(fontSize: 13),
        tabs: _visibleTabs
            .map((t) => Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(t.icon, size: 18),
                      const SizedBox(width: 6),
                      Text(t.label),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  /// محتوى التبويبات
  Widget _buildTabContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, style: GoogleFonts.cairo(color: _textGray)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadFullProfile,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: Text('إعادة المحاولة',
                  style: GoogleFonts.cairo(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: _accent),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: _visibleTabs.map((tab) => _buildTab(tab.key)).toList(),
    );
  }

  Widget _buildTab(String key) {
    switch (key) {
      case 'hr':
        return HrInfoTab(
          employee: _employee,
          companyId: widget.companyId,
          canEdit: _pm.canEdit('users'),
          onSaved: _loadFullProfile,
        );
      case 'attendance':
        return AttendanceTab(
          employeeId: widget.employeeId,
          employeeName: _employee['fullName'] ?? _employee['FullName'] ?? '',
        );
      case 'tasks':
        return TasksTab(
          employeeId: widget.employeeId,
          employeeName: _employee['fullName'] ?? _employee['FullName'] ?? '',
          canAddTask: _pm.canAdd('tasks'),
          canEditTask: _pm.canEdit('tasks'),
        );
      case 'salary':
        return SalaryTab(
          employeeId: widget.employeeId,
          employeeName: _employee['fullName'] ?? _employee['FullName'] ?? '',
          baseSalary: _employee['salary'] ?? _employee['Salary'],
          canEdit: _pm.canEdit('accounts') || _pm.canEdit('accounting'),
        );
      case 'permissions':
        return PermissionsTab(
          companyId: widget.companyId,
          employeeId: widget.employeeId,
          employeeName: _employee['fullName'] ?? _employee['FullName'] ?? '',
          canEdit: _pm.canEdit('users'),
        );
      case 'ftth':
        return FtthTab(
          employeeId: widget.employeeId,
          employeeName: _employee['fullName'] ?? _employee['FullName'] ?? '',
          ftthUsername: _employee['ftthUsername'] ?? _employee['FtthUsername'],
        );
      case 'transactions':
        return TransactionsTab(
          employeeId: widget.employeeId,
          employeeName: _employee['fullName'] ?? _employee['FullName'] ?? '',
          role: _employee['role'] ?? _employee['Role'] ?? '',
          canAdd: _pm.canAdd('transactions') || _pm.canAdd('technicians'),
        );
      case 'performance':
        return PerformanceTab(
          employeeId: widget.employeeId,
          employeeName: _employee['fullName'] ?? _employee['FullName'] ?? '',
        );
      default:
        return const Center(child: Text('تبويب غير معروف'));
    }
  }

  // ═══════════ helpers ═══════════

  Color _getRoleColor(String role) {
    switch (role) {
      case 'SuperAdmin':
        return const Color(0xFFE74C3C);
      case 'CompanyAdmin':
        return const Color(0xFF8E44AD);
      case 'Manager':
        return const Color(0xFF2980B9);
      case 'TechnicalLeader':
        return const Color(0xFF16A085);
      case 'Technician':
        return const Color(0xFF27AE60);
      case 'Viewer':
        return const Color(0xFF95A5A6);
      case 'Employee':
        return const Color(0xFF3498DB);
      default:
        return const Color(0xFF7F8C8D);
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'SuperAdmin':
        return 'مدير النظام';
      case 'CompanyAdmin':
        return 'مدير الشركة';
      case 'Manager':
        return 'مدير';
      case 'TechnicalLeader':
        return 'ليدر فني';
      case 'Technician':
        return 'فني';
      case 'Viewer':
        return 'مشاهد';
      case 'Employee':
        return 'موظف';
      default:
        return role.isEmpty ? 'غير محدد' : role;
    }
  }
}

class _TabInfo {
  final String key;
  final String label;
  final IconData icon;

  _TabInfo({required this.key, required this.label, required this.icon});
}
