/// 👥 صفحة إدارة موظفي الشركة - VPS API
/// تعرض موظفي الشركة من قاعدة بيانات PostgreSQL عبر VPS API
/// مع إمكانية إضافة/تعديل/حذف الموظفين وإدارة الصلاحيات
library;

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api/api_client.dart';
import '../services/api/api_config.dart';
import 'super_admin/permissions_management_v2_page.dart';
import '../services/permission_checker.dart';
import 'hr/employee_profile_page.dart';

/// صفحة إدارة موظفي الشركة عبر VPS
class UsersPageVPS extends StatefulWidget {
  final String companyId;
  final String companyName;
  final Map<String, dynamic>? permissions;
  final int maxUsers;

  const UsersPageVPS({
    super.key,
    required this.companyId,
    required this.companyName,
    this.permissions,
    this.maxUsers = 100,
  });

  @override
  State<UsersPageVPS> createState() => _UsersPageVPSState();
}

class _UsersPageVPSState extends State<UsersPageVPS> {
  final ApiClient _apiClient = ApiClient.instance;
  final TextEditingController _searchController = TextEditingController();

  List<EmployeeModel> _employees = [];
  List<EmployeeModel> _filteredEmployees = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// تحميل الموظفين من VPS API
  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('📡 جلب موظفي الشركة: ${widget.companyId}');

      final response = await _apiClient.get(
        ApiConfig.internalCompanyEmployees(widget.companyId),
        (json) => json,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final List<dynamic> usersJson = response.data is List
            ? response.data
            : (response.data['data'] ?? response.data['users'] ?? []);

        setState(() {
          _employees =
              usersJson.map((json) => EmployeeModel.fromJson(json)).toList();
          _filteredEmployees = _employees;
          _isLoading = false;
        });

        debugPrint('✅ تم جلب ${_employees.length} موظف');
      } else {
        setState(() {
          _error = response.message ?? 'فشل في جلب الموظفين';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب الموظفين: $e');
      setState(() {
        _error = 'خطأ في الاتصال: $e';
        _isLoading = false;
      });
    }
  }

  /// فلترة الموظفين حسب البحث
  void _filterEmployees(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredEmployees = _employees;
      } else {
        _filteredEmployees = _employees.where((emp) {
          return emp.fullName.toLowerCase().contains(query.toLowerCase()) ||
              emp.phoneNumber.contains(query) ||
              (emp.email?.toLowerCase().contains(query.toLowerCase()) ??
                  false) ||
              (emp.role?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  // ═══════════════ ألوان التصميم الفخم ═══════════════
  static const _dark1 = Color(0xFF1A1D2E); // خلفية داكنة رئيسية
  static const _dark2 = Color(0xFF232740); // بطاقات
  static const _dark3 = Color(0xFF2D3250); // بطاقات ثانوية
  static const _accent = Color(0xFF6C63FF); // أرجواني عصري
  static const _accentLight = Color(0xFF8B83FF);
  static const _gold = Color(0xFFD4AF37); // ذهبي فخم
  static const _goldLight = Color(0xFFE8D48B);
  static const _textWhite = Color(0xFFF1F1F5);
  static const _textGray = Color(0xFF8B8DA3);
  static const _success = Color(0xFF00E676);
  static const _danger = Color(0xFFFF5252);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _dark1,
        body: Column(
          children: [
            _buildPremiumHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  /// شريط علوي فخم بتدرج لوني
  Widget _buildPremiumHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1D2E), Color(0xFF2D3250), Color(0xFF1A1D2E)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        border: Border(
          bottom: BorderSide(color: Color(0xFF3A3F5C), width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 14),
          child: Row(
            children: [
              // زر الرجوع
              _glassButton(
                icon: Icons.arrow_forward_rounded,
                onTap: () => Navigator.of(context).pop(),
                size: 38,
              ),
              const SizedBox(width: 16),
              // أيقونة فخمة
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_gold, Color(0xFFF5E6A3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.groups_rounded, color: Color(0xFF1A1D2E), size: 24),
              ),
              const SizedBox(width: 14),
              // العنوان
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'إدارة الموظفين',
                      style: GoogleFonts.cairo(
                        color: _textWhite,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.companyName,
                      style: GoogleFonts.cairo(
                        color: _goldLight,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // عداد الموظفين
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_accent.withOpacity(0.2), _accent.withOpacity(0.08)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_alt_rounded, size: 15, color: _accentLight),
                    const SizedBox(width: 6),
                    Text(
                      '${_employees.length} / ${widget.maxUsers}',
                      style: GoogleFonts.cairo(
                        color: _accentLight,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _glassButton(
                icon: Icons.refresh_rounded,
                onTap: _loadEmployees,
                size: 38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// زر زجاجي شفاف
  Widget _glassButton({required IconData icon, required VoidCallback onTap, double size = 36}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(icon, color: _textGray, size: 18),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: _accent))
              : _error != null
                  ? _buildErrorWidget()
                  : _filteredEmployees.isEmpty
                      ? _buildEmptyWidget()
                      : _buildEmployeesList(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Container(
        decoration: BoxDecoration(
          color: _dark2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF3A3F5C)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterEmployees,
          style: GoogleFonts.cairo(color: _textWhite, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'بحث بالاسم، الهاتف، أو الدور...',
            hintStyle: GoogleFonts.cairo(color: _textGray, fontSize: 13),
            prefixIcon: const Icon(Icons.search_rounded, color: _accent, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _searchController.clear();
                      _filterEmployees('');
                    },
                    icon: const Icon(Icons.close_rounded, color: _textGray, size: 18),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _danger.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.cloud_off_rounded, size: 40, color: _danger),
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            style: GoogleFonts.cairo(color: _danger, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _loadEmployees,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_search_rounded, size: 40, color: _accent),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'لا توجد نتائج للبحث "$_searchQuery"'
                : 'لا يوجد موظفين بعد',
            style: GoogleFonts.cairo(color: _textGray, fontSize: 14),
          ),
          const SizedBox(height: 20),
          if (_searchQuery.isEmpty &&
              PermissionManager.instance.canAdd('users'))
            ElevatedButton.icon(
              onPressed: () => _showAddEmployeeDialog(),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: Text('إضافة أول موظف', style: GoogleFonts.cairo()),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmployeesList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 90),
      itemCount: _filteredEmployees.length,
      itemBuilder: (context, index) {
        final employee = _filteredEmployees[index];
        return _buildEmployeeCard(employee, index);
      },
    );
  }

  Widget _buildEmployeeCard(EmployeeModel employee, int index) {
    final roleColor = _getRoleColor(employee.role);
    final roleLabel = _getRoleNameAr(employee.role);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showEmployeeDetails(employee),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _dark2,
                  _dark3.withOpacity(0.7),
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: employee.isActive
                    ? roleColor.withOpacity(0.25)
                    : const Color(0xFF3A3F5C),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                if (employee.isActive)
                  BoxShadow(
                    color: roleColor.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Column(
              children: [
                // ═══ الشريط العلوي الملون ═══
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: employee.isActive
                          ? [roleColor.withOpacity(0.6), roleColor, roleColor.withOpacity(0.6)]
                          : [const Color(0xFF3A3F5C), const Color(0xFF4A4F6C), const Color(0xFF3A3F5C)],
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      // ═══ أفاتار فخم ═══
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: employee.isActive
                                ? [roleColor.withOpacity(0.3), roleColor.withOpacity(0.1)]
                                : [Colors.grey.withOpacity(0.2), Colors.grey.withOpacity(0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: employee.isActive
                                ? roleColor.withOpacity(0.4)
                                : Colors.grey.withOpacity(0.2),
                            width: 1.5,
                          ),
                          boxShadow: employee.isActive ? [
                            BoxShadow(
                              color: roleColor.withOpacity(0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ] : null,
                        ),
                        child: Center(
                          child: Text(
                            employee.fullName.isNotEmpty
                                ? employee.fullName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.cairo(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: employee.isActive ? roleColor : _textGray,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // ═══ المعلومات ═══
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // الاسم
                            Text(
                              employee.fullName,
                              style: GoogleFonts.cairo(
                                color: _textWhite,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // الدور + الكود + القسم
                            Row(
                              children: [
                                // شارة الدور
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        roleColor.withOpacity(0.2),
                                        roleColor.withOpacity(0.08),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: roleColor.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    roleLabel,
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      color: roleColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (employee.employeeCode != null) ...[
                                  const SizedBox(width: 8),
                                  Icon(Icons.badge_outlined, size: 12, color: _textGray.withOpacity(0.6)),
                                  const SizedBox(width: 3),
                                  Text(
                                    employee.employeeCode!,
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      color: _textGray,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 5),
                            // الهاتف
                            Row(
                              children: [
                                Icon(Icons.phone_rounded, size: 13, color: _accent.withOpacity(0.7)),
                                const SizedBox(width: 5),
                                Text(
                                  employee.phoneNumber,
                                  style: GoogleFonts.cairo(fontSize: 12, color: _textGray),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // ═══ حالة + أزرار ═══
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // شارة الحالة
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: employee.isActive
                                  ? _success.withOpacity(0.12)
                                  : _danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: employee.isActive
                                    ? _success.withOpacity(0.3)
                                    : _danger.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: employee.isActive ? _success : _danger,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (employee.isActive ? _success : _danger)
                                            .withOpacity(0.5),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  employee.isActive ? 'نشط' : 'معطل',
                                  style: GoogleFonts.cairo(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: employee.isActive ? _success : _danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          // أزرار الإجراءات
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _actionBtn(
                                icon: Icons.shield_outlined,
                                color: const Color(0xFFAB47BC),
                                tooltip: 'الصلاحيات',
                                onTap: () => _managePermissions(employee),
                              ),
                              const SizedBox(width: 6),
                              if (PermissionManager.instance.canEdit('users'))
                                _actionBtn(
                                  icon: Icons.edit_outlined,
                                  color: _accent,
                                  tooltip: 'تعديل',
                                  onTap: () => _editEmployee(employee),
                                ),
                              if (PermissionManager.instance.canEdit('users'))
                                const SizedBox(width: 6),
                              _actionBtn(
                                icon: Icons.key_rounded,
                                color: _gold,
                                tooltip: 'كلمة المرور',
                                onTap: () => _showPasswordDialog(employee),
                              ),
                              const SizedBox(width: 6),
                              _actionBtn(
                                icon: Icons.arrow_back_ios_new_rounded,
                                color: _textGray,
                                tooltip: 'الملف الشخصي',
                                onTap: () => _showEmployeeDetails(employee),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// زر إجراء صغير
  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
        ),
      ),
    );
  }

  Widget? _buildFAB() {
    if (_employees.length >= widget.maxUsers) return null;
    if (!PermissionManager.instance.canAdd('users')) return null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [_accent, Color(0xFF8B83FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: () => _showAddEmployeeDialog(),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
        label: Text('إضافة موظف', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
      ),
    );
  }

  /// عرض الملف الشخصي الشامل للموظف (نظام HR)
  void _showEmployeeDetails(EmployeeModel employee) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeProfilePage(
          companyId: widget.companyId,
          companyName: widget.companyName,
          employeeId: employee.id,
          employeeData: employee.rawJson,
        ),
      ),
    ).then((_) => _loadEmployees());
  }

  /// إدارة صلاحيات الموظف
  Future<void> _managePermissions(EmployeeModel employee) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => PermissionsManagementV2Page(
          companyId: widget.companyId,
          companyName: widget.companyName,
          employeeId: employee.id,
          employeeName: employee.fullName,
        ),
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  /// إضافة موظف جديد
  Future<void> _showAddEmployeeDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddEditEmployeeDialog(
        companyId: widget.companyId,
        apiClient: _apiClient,
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  /// تعديل موظف
  Future<void> _editEmployee(EmployeeModel employee) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddEditEmployeeDialog(
        companyId: widget.companyId,
        apiClient: _apiClient,
        employee: employee,
      ),
    );

    if (result == true) {
      _loadEmployees();
    }
  }

  /// حذف موظف
  Future<void> _deleteEmployee(EmployeeModel employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('تأكيد الحذف'),
          ],
        ),
        content: Text('هل أنت متأكد من حذف الموظف "${employee.fullName}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final response = await _apiClient.delete(
          ApiConfig.internalEmployeeById(widget.companyId, employee.id),
          (json) => json,
          useInternalKey: true,
        );

        if (response.isSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف الموظف بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          _loadEmployees();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'فشل في حذف الموظف'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  /// عرض كلمة المرور
  Future<void> _showPasswordDialog(EmployeeModel employee) async {
    final passwordController = TextEditingController();
    bool showPassword = false;
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.key_rounded, color: Color(0xFFFF9800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'كلمة مرور ${employee.fullName}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // كلمة المرور الحالية
              if (employee.password != null && employee.password!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFE0B2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Color(0xFFFF9800), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'كلمة المرور الحالية:',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF795548)),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              employee.password!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: employee.password!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم نسخ كلمة المرور'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        tooltip: 'نسخ',
                      ),
                    ],
                  ),
                ),
              // تغيير كلمة المرور
              const Text(
                'تغيير كلمة المرور:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: !showPassword,
                decoration: InputDecoration(
                  hintText: 'كلمة المرور الجديدة',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setDialogState(() => showPassword = !showPassword),
                    icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            ElevatedButton.icon(
              onPressed: isSaving || passwordController.text.isEmpty
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);

                      try {
                        final response = await _apiClient.patch(
                          ApiConfig.internalEmployeePassword(
                              widget.companyId, employee.id),
                          {'NewPassword': passwordController.text},
                          (json) => json,
                          useInternalKey: true,
                        );

                        if (response.isSuccess) {
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تغيير كلمة المرور بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadEmployees();
                          }
                        } else {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(response.message ??
                                    'فشل في تغيير كلمة المرور'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// الحصول على لون الدور
  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'companyadmin':
        return const Color(0xFFE040FB); // بنفسجي متوهج
      case 'manager':
        return const Color(0xFF448AFF); // أزرق
      case 'technicalleader':
        return const Color(0xFF00E5FF); // سماوي
      case 'technician':
        return const Color(0xFF69F0AE); // أخضر فاتح
      case 'viewer':
        return const Color(0xFF90A4AE); // رمادي
      case 'employee':
        return const Color(0xFF7C4DFF); // أرجواني
      default:
        return const Color(0xFFFFAB40); // برتقالي
    }
  }

  /// الحصول على اسم الدور بالعربي
  String _getRoleNameAr(String? role) {
    switch (role?.toLowerCase()) {
      case 'companyadmin':
        return 'مدير الشركة';
      case 'manager':
        return 'مدير';
      case 'technicalleader':
        return 'ليدر فني';
      case 'technician':
        return 'فني';
      case 'viewer':
        return 'مشاهد';
      case 'employee':
        return 'موظف';
      default:
        return role ?? 'غير محدد';
    }
  }
}

// ============================================
// نموذج الموظف
// ============================================

class EmployeeModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String? role;
  final String? department;
  final String? employeeCode;
  final String? center;
  final String? salary;
  final String? password;
  final bool isActive;
  final DateTime? createdAt;
  final Map<String, dynamic>? firstSystemPermissions;
  final Map<String, dynamic>? secondSystemPermissions;
  final Map<String, dynamic> rawJson;

  EmployeeModel({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.email,
    this.role,
    this.department,
    this.employeeCode,
    this.center,
    this.salary,
    this.password,
    required this.isActive,
    this.createdAt,
    this.firstSystemPermissions,
    this.secondSystemPermissions,
    required this.rawJson,
  });

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    return EmployeeModel(
      id: (json['id'] ?? json['Id'] ?? json['userId'] ?? json['UserId'])
              ?.toString() ??
          '',
      fullName: json['fullName'] ??
          json['FullName'] ??
          json['name'] ??
          json['Name'] ??
          '',
      phoneNumber: json['phoneNumber'] ??
          json['PhoneNumber'] ??
          json['phone'] ??
          json['Phone'] ??
          '',
      email: json['email'] ?? json['Email'],
      role:
          json['role'] ?? json['Role'] ?? json['jobTitle'] ?? json['JobTitle'],
      department: json['department'] ?? json['Department'],
      employeeCode: json['employeeCode'] ?? json['EmployeeCode'],
      center: json['center'] ?? json['Center'],
      salary: json['salary']?.toString() ?? json['Salary']?.toString(),
      password: json['password'] ?? json['Password'],
      isActive: json['isActive'] ?? json['IsActive'] ?? true,
      createdAt: json['createdAt'] != null || json['CreatedAt'] != null
          ? DateTime.tryParse(
              (json['createdAt'] ?? json['CreatedAt']).toString())
          : null,
      firstSystemPermissions: _parsePermissions(
          json['firstSystemPermissions'] ?? json['FirstSystemPermissions']),
      secondSystemPermissions: _parsePermissions(
          json['secondSystemPermissions'] ?? json['SecondSystemPermissions']),
      rawJson: json,
    );
  }

  static Map<String, dynamic>? _parsePermissions(dynamic value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(value));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

// ============================================
// نافذة تفاصيل الموظف
// ============================================

class _EmployeeDetailsDialog extends StatelessWidget {
  final EmployeeModel employee;
  final VoidCallback onEdit;
  final VoidCallback onManagePermissions;
  final VoidCallback? onDelete;

  const _EmployeeDetailsDialog({
    required this.employee,
    required this.onEdit,
    required this.onManagePermissions,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // الأفاتار
            CircleAvatar(
              radius: 40,
              backgroundColor: const Color(0xFF1976D2).withOpacity(0.1),
              child: Text(
                employee.fullName.isNotEmpty
                    ? employee.fullName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1976D2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // الاسم
            Text(
              employee.fullName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            // الدور
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _getRoleNameAr(employee.role),
                style: const TextStyle(
                  color: Color(0xFF1976D2),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // المعلومات
            _buildInfoRow(Icons.phone_rounded, 'الهاتف', employee.phoneNumber),
            if (employee.email != null && employee.email!.isNotEmpty)
              _buildInfoRow(Icons.email_rounded, 'البريد', employee.email!),
            if (employee.department != null && employee.department!.isNotEmpty)
              _buildInfoRow(
                  Icons.business_rounded, 'القسم', employee.department!),
            if (employee.center != null && employee.center!.isNotEmpty)
              _buildInfoRow(
                  Icons.location_on_rounded, 'المركز', employee.center!),
            if (employee.employeeCode != null)
              _buildInfoRow(
                  Icons.badge_rounded, 'الكود', employee.employeeCode!),
            const SizedBox(height: 24),
            // الأزرار
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onManagePermissions,
                    icon: const Icon(Icons.security_rounded),
                    label: const Text('الصلاحيات'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF9C27B0),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded),
                    label: const Text('تعديل'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2196F3),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_rounded),
                    label: const Text('حذف'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          onDelete != null ? Colors.red : Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('إغلاق'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }

  String _getRoleNameAr(String? role) {
    switch (role?.toLowerCase()) {
      case 'companyadmin':
        return 'مدير الشركة';
      case 'manager':
        return 'مدير';
      case 'technicalleader':
        return 'ليدر فني';
      case 'technician':
        return 'فني';
      case 'viewer':
        return 'مشاهد';
      case 'employee':
        return 'موظف';
      default:
        return role ?? 'غير محدد';
    }
  }
}

// ============================================
// نافذة إضافة/تعديل موظف
// ============================================

class _AddEditEmployeeDialog extends StatefulWidget {
  final String companyId;
  final ApiClient apiClient;
  final EmployeeModel? employee;

  const _AddEditEmployeeDialog({
    required this.companyId,
    required this.apiClient,
    this.employee,
  });

  @override
  State<_AddEditEmployeeDialog> createState() => _AddEditEmployeeDialogState();
}

class _AddEditEmployeeDialogState extends State<_AddEditEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _departmentController = TextEditingController();
  final _centerController = TextEditingController();
  final _salaryController = TextEditingController();

  String _selectedRole = 'Employee';
  bool _isActive = true;
  bool _isSaving = false;

  static const List<Map<String, String>> _roles = [
    {'value': 'Employee', 'label': 'موظف'},
    {'value': 'Viewer', 'label': 'مشاهد'},
    {'value': 'Technician', 'label': 'فني'},
    {'value': 'TechnicalLeader', 'label': 'ليدر فني'},
    {'value': 'Manager', 'label': 'مدير'},
    {'value': 'CompanyAdmin', 'label': 'مدير الشركة'},
  ];

  static const List<String> _departments = [
    'الصيانة',
    'الحسابات',
    'الفنيين',
    'الوكلاء',
    'الاتصالات',
    'اللحام',
  ];

  bool get isEditing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      final emp = widget.employee!;
      _nameController.text = emp.fullName;
      _phoneController.text = emp.phoneNumber;
      _emailController.text = emp.email ?? '';
      _departmentController.text = emp.department ?? '';
      _centerController.text = emp.center ?? '';
      _salaryController.text = emp.salary ?? '';
      // التأكد أن الدور موجود في القائمة
      final role = emp.role ?? 'Employee';
      final roleExists =
          _roles.any((r) => r['value']!.toLowerCase() == role.toLowerCase());
      _selectedRole = roleExists
          ? _roles.firstWhere(
              (r) => r['value']!.toLowerCase() == role.toLowerCase())['value']!
          : 'Employee';
      _isActive = emp.isActive;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _departmentController.dispose();
    _centerController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final data = {
        'fullName': _nameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'email': _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : null,
        'role': _selectedRole,
        'department': _departmentController.text.trim().isNotEmpty
            ? _departmentController.text.trim()
            : null,
        'center': _centerController.text.trim().isNotEmpty
            ? _centerController.text.trim()
            : null,
        'salary': _salaryController.text.trim().isNotEmpty
            ? _salaryController.text.trim()
            : null,
        'isActive': _isActive,
      };

      // إضافة كلمة المرور فقط عند الإضافة أو إذا تم تعديلها
      if (!isEditing || _passwordController.text.isNotEmpty) {
        data['password'] = _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null;
      }

      final response = isEditing
          ? await widget.apiClient.put(
              ApiConfig.internalEmployeeById(
                  widget.companyId, widget.employee!.id),
              data,
              (json) => json,
              useInternalKey: true,
            )
          : await widget.apiClient.post(
              ApiConfig.internalCompanyEmployees(widget.companyId),
              data,
              (json) => json,
              useInternalKey: true,
            );

      if (response.isSuccess) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isEditing
                  ? 'تم تحديث الموظف بنجاح'
                  : 'تم إضافة الموظف بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() => _isSaving = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ??
                  'فشل في ${isEditing ? 'تحديث' : 'إضافة'} الموظف'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // العنوان
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isEditing
                    ? const Color(0xFF2196F3)
                    : const Color(0xFF4CAF50),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(
                    isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'تعديل موظف' : 'إضافة موظف جديد',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            // النموذج
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // المعلومات الأساسية
                      _buildSectionTitle(
                          'المعلومات الأساسية', Icons.person_rounded),
                      const SizedBox(height: 12),
                      // الاسم
                      TextFormField(
                        controller: _nameController,
                        decoration: _inputDecoration(
                            'الاسم الكامل *', Icons.person_outline),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      // الهاتف
                      TextFormField(
                        controller: _phoneController,
                        decoration: _inputDecoration(
                            'رقم الهاتف * (للدخول)', Icons.phone_outlined),
                        keyboardType: TextInputType.phone,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'مطلوب' : null,
                      ),
                      const SizedBox(height: 12),
                      // كلمة المرور
                      TextFormField(
                        controller: _passwordController,
                        decoration: _inputDecoration(
                          isEditing
                              ? 'كلمة المرور الجديدة (اختياري)'
                              : 'كلمة المرور (افتراضي: 123456)',
                          Icons.lock_outline,
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      // البريد
                      TextFormField(
                        controller: _emailController,
                        decoration: _inputDecoration(
                            'البريد الإلكتروني (اختياري)',
                            Icons.email_outlined),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 20),
                      // الدور والحالة
                      _buildSectionTitle('الدور والحالة', Icons.badge_rounded),
                      const SizedBox(height: 12),
                      // الدور
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: _inputDecoration(
                            'الدور الوظيفي *', Icons.work_outline),
                        items: _roles
                            .map((r) => DropdownMenuItem(
                                  value: r['value'],
                                  child: Text(r['label']!),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedRole = v!),
                      ),
                      const SizedBox(height: 12),
                      // الحالة
                      SwitchListTile(
                        title: const Text('الحساب نشط'),
                        subtitle: Text(_isActive
                            ? 'يمكنه تسجيل الدخول'
                            : 'محظور من الدخول'),
                        value: _isActive,
                        onChanged: (v) => setState(() => _isActive = v),
                        secondary: Icon(
                          _isActive ? Icons.check_circle : Icons.block,
                          color: _isActive ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // معلومات إضافية
                      _buildSectionTitle(
                          'معلومات إضافية (اختياري)', Icons.info_outline),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _departmentController.text.isNotEmpty &&
                                      _getAllDepartments()
                                          .contains(_departmentController.text)
                                  ? _departmentController.text
                                  : null,
                              decoration: _inputDecoration(
                                  _departmentController.text.isNotEmpty &&
                                          !_departments.contains(
                                              _departmentController.text)
                                      ? 'القسم (الحالي: ${_departmentController.text})'
                                      : 'القسم',
                                  Icons.business_outlined),
                              items: _getAllDepartments()
                                  .map((d) => DropdownMenuItem(
                                      value: d, child: Text(d)))
                                  .toList(),
                              onChanged: (v) {
                                setState(() {
                                  _departmentController.text = v ?? '';
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _centerController,
                              decoration: _inputDecoration(
                                  'المركز', Icons.location_on_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _salaryController,
                        decoration:
                            _inputDecoration('الراتب', Icons.attach_money),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // الأزرار
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(isEditing
                              ? Icons.save_rounded
                              : Icons.person_add_rounded),
                      label: Text(isEditing ? 'حفظ التغييرات' : 'إضافة الموظف'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isEditing
                            ? const Color(0xFF2196F3)
                            : const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// قائمة الأقسام مع إضافة القسم الحالي إذا لم يكن في القائمة الافتراضية
  List<String> _getAllDepartments() {
    final current = _departmentController.text;
    if (current.isNotEmpty && !_departments.contains(current)) {
      return [current, ..._departments];
    }
    return _departments;
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF1976D2)),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1976D2),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: Colors.grey.shade50,
    );
  }
}
