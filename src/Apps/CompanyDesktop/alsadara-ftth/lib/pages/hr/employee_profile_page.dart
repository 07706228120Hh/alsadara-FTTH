/// 👤 صفحة الملف الشخصي الشامل للموظف — نظام HR متكامل
/// تبويبات: HR | الحضور | المهام | الرواتب | الصلاحيات | FTTH | المعاملات | التقييم
/// جميع التبويبات والأزرار والحقول مرتبطة بنظام الصلاحيات V2
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/employee_profile_service.dart';
import '../../services/permission_checker.dart';
import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';
import '../super_admin/permissions_management_v2_page.dart';
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
          // إعادة بناء التبويبات بعد تحميل البيانات الكاملة (تحتوي FTTH)
          _visibleTabs.clear();
          _buildVisibleTabs();
          _tabController.dispose();
          _tabController = TabController(
            length: _visibleTabs.length,
            vsync: this,
          );
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
            // ═══ أزرار الإجراءات ═══
            // تغيير كلمة المرور
            _headerActionBtn(
              icon: Icons.key_rounded,
              tooltip: 'تغيير كلمة المرور',
              color: const Color(0xFFFF9800),
              onTap: () => _showPasswordDialog(),
            ),
            const SizedBox(width: 4),
            // الصلاحيات
            if (_pm.canEdit('users'))
              _headerActionBtn(
                icon: Icons.shield_outlined,
                tooltip: 'إدارة الصلاحيات',
                color: const Color(0xFFAB47BC),
                onTap: () => _openPermissionsPage(),
              ),
            if (_pm.canEdit('users')) const SizedBox(width: 4),
            // حذف الموظف
            if (_pm.canDelete('users'))
              _headerActionBtn(
                icon: Icons.delete_outline_rounded,
                tooltip: 'حذف الموظف',
                color: const Color(0xFFFF5252),
                onTap: () => _deleteEmployee(),
              ),
            if (_pm.canDelete('users')) const SizedBox(width: 4),
            // زر تحديث
            _headerActionBtn(
              icon: Icons.refresh_rounded,
              tooltip: 'تحديث',
              color: Colors.white70,
              onTap: _loadFullProfile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerActionBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }

  /// ═══ حوار تغيير كلمة المرور ═══
  Future<void> _showPasswordDialog() async {
    final passwordController = TextEditingController();
    bool showPassword = false;
    bool isSaving = false;
    final empName = _employee['fullName'] ?? _employee['FullName'] ?? 'الموظف';
    final empId = widget.employeeId;
    final currentPassword = _employee['password'] ?? _employee['Password'];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.key_rounded,
                      color: Color(0xFFFF9800), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'كلمة مرور $empName',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentPassword != null &&
                    currentPassword.toString().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFE0B2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Color(0xFFFF9800), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('كلمة المرور الحالية:',
                                  style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      color: const Color(0xFF795548))),
                              const SizedBox(height: 2),
                              SelectableText(
                                currentPassword.toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: currentPassword.toString()));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('تم نسخ كلمة المرور'),
                                  duration: Duration(seconds: 1)),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          tooltip: 'نسخ',
                        ),
                      ],
                    ),
                  ),
                Text('كلمة المرور الجديدة:',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  obscureText: !showPassword,
                  decoration: InputDecoration(
                    hintText: 'أدخل كلمة المرور الجديدة',
                    hintStyle: GoogleFonts.cairo(fontSize: 13),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setDialogState(() => showPassword = !showPassword),
                      icon: Icon(
                          showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          size: 20),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إغلاق', style: GoogleFonts.cairo()),
              ),
              ElevatedButton.icon(
                onPressed: isSaving || passwordController.text.isEmpty
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          final response = await ApiClient.instance.patch(
                            ApiConfig.internalEmployeePassword(
                                widget.companyId, empId),
                            {'NewPassword': passwordController.text},
                            (json) => json,
                            useInternalKey: true,
                          );
                          if (response.isSuccess && mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('تم تغيير كلمة المرور بنجاح',
                                    style: GoogleFonts.cairo()),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadFullProfile();
                          } else {
                            setDialogState(() => isSaving = false);
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('خطأ: $e'),
                                  backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text('حفظ', style: GoogleFonts.cairo()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF9800),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ═══ فتح صفحة إدارة الصلاحيات ═══
  Future<void> _openPermissionsPage() async {
    final empName = _employee['fullName'] ?? _employee['FullName'] ?? '';
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PermissionsManagementV2Page(
          companyId: widget.companyId,
          companyName: widget.companyName,
          employeeId: widget.employeeId,
          employeeName: empName,
        ),
      ),
    );
    if (result == true) _loadFullProfile();
  }

  /// ═══ حذف الموظف ═══
  Future<void> _deleteEmployee() async {
    final empName = _employee['fullName'] ?? _employee['FullName'] ?? 'الموظف';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.red.shade400),
              const SizedBox(width: 8),
              Text('تأكيد الحذف',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت متأكد من حذف الموظف "$empName"؟\nهذا الإجراء لا يمكن التراجع عنه.',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('حذف', style: GoogleFonts.cairo(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      try {
        final response = await ApiClient.instance.delete(
          ApiConfig.internalEmployeeById(widget.companyId, widget.employeeId),
          (json) => json,
          useInternalKey: true,
        );
        if (response.isSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم حذف الموظف بنجاح', style: GoogleFonts.cairo()),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(); // العودة لقائمة الموظفين
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'فشل في حذف الموظف',
                  style: GoogleFonts.cairo()),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
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
