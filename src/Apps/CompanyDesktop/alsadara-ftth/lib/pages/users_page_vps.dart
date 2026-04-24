/// 👥 صفحة إدارة موظفي الشركة - VPS API
/// تعرض موظفي الشركة من قاعدة بيانات PostgreSQL عبر VPS API
/// مع إمكانية إضافة/تعديل/حذف الموظفين وإدارة الصلاحيات
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/responsive_helper.dart';
import '../services/api/api_client.dart';
import '../services/api/api_config.dart';
import '../services/departments_data_service.dart';
import '../services/centers_data_service.dart';
import 'super_admin/permissions_management_v2_page.dart';
import '../permissions/permissions.dart';
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

  // فلاتر التصفية
  String? _filterDepartment;
  String? _filterRole;
  String? _filterCenter;

  // وضع التحديد الجماعي
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _isBulkApplying = false;

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
      debugPrint('❌ خطأ في جلب الموظفين');
      setState(() {
        _error = 'خطأ في الاتصال';
        _isLoading = false;
      });
    }
  }

  /// فلترة الموظفين حسب البحث + الفلاتر
  void _filterEmployees(String query) {
    setState(() {
      _searchQuery = query;
      _filteredEmployees = _employees.where((emp) {
        // فلتر البحث النصي
        if (query.isNotEmpty) {
          final q = query.toLowerCase();
          final matchesSearch = emp.fullName.toLowerCase().contains(q) ||
              emp.phoneNumber.contains(q) ||
              (emp.email?.toLowerCase().contains(q) ?? false) ||
              (emp.role?.toLowerCase().contains(q) ?? false) ||
              (_getRoleNameAr(emp.role).toLowerCase().contains(q));
          if (!matchesSearch) return false;
        }
        // فلتر القسم
        if (_filterDepartment != null && emp.department != _filterDepartment) return false;
        // فلتر الدور
        if (_filterRole != null && emp.role != _filterRole) return false;
        // فلتر موقع العمل
        if (_filterCenter != null && emp.center != _filterCenter) return false;
        return true;
      }).toList();
    });
  }

  /// إعادة تطبيق الفلاتر
  void _applyFilters() => _filterEmployees(_searchQuery);

  /// الحصول على القيم الفريدة لحقل معين
  List<String> _getUniqueValues(String Function(EmployeeModel) getter) {
    return _employees
        .map(getter)
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  bool get _hasActiveFilters => _filterDepartment != null || _filterRole != null || _filterCenter != null;

  // ═══════════════ ألوان التصميم الفاتح ═══════════════
  static const _dark1 = Color(0xFFF5F6FA); // خلفية فاتحة رئيسية
  static const _dark2 = Color(0xFFFFFFFF); // بطاقات بيضاء
  static const _dark3 = Color(0xFFF0F1F5); // بطاقات ثانوية
  static const _accent = Color(0xFF6C63FF); // أرجواني عصري
  static const _accentLight = Color(0xFF8B83FF);
  static const _gold = Color(0xFFD4AF37); // ذهبي فخم
  static const _goldLight = Color(0xFFE8D48B);
  static const _textWhite = Color(0xFF2D3250); // نص داكن على خلفية فاتحة
  static const _textGray = Color(0xFF6B7280);
  static const _success = Color(0xFF22C55E);
  static const _danger = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _dark1,
        body: SafeArea(
          child: Column(
            children: [
              _buildPremiumHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  /// شريط علوي فخم بتدرج لوني
  Widget _buildPremiumHeader() {
    final r = context.responsive;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(r.contentPaddingH, 10, 8, 12),
          child: Row(
            children: [
              // زر الرجوع
              _glassButton(
                icon: Icons.arrow_forward_rounded,
                onTap: () => Navigator.of(context).pop(),
                size: r.isMobile ? 32 : 38,
              ),
              const SizedBox(width: 16),
              // أيقونة فخمة
              Container(
                width: r.isMobile ? 36 : 44,
                height: r.isMobile ? 36 : 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_accent, _accentLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(Icons.groups_rounded,
                    color: Colors.white, size: r.isMobile ? 20 : 24),
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
                        fontSize: r.titleSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.companyName,
                      style: GoogleFonts.cairo(
                        color: _textGray,
                        fontSize: r.captionSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              // عداد الموظفين
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: r.isMobile ? 8 : 14, vertical: r.isMobile ? 4 : 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accent.withOpacity(0.2),
                      _accent.withOpacity(0.08)
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_alt_rounded,
                        size: r.isMobile ? 12 : 15, color: _accentLight),
                    SizedBox(width: r.isMobile ? 4 : 6),
                    Text(
                      '${_employees.length} / ${widget.maxUsers}',
                      style: GoogleFonts.cairo(
                        color: _accentLight,
                        fontSize: r.isMobile ? 10 : 12,
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
                size: r.isMobile ? 32 : 38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// زر زجاجي شفاف
  Widget _glassButton(
      {required IconData icon, required VoidCallback onTap, double size = 36}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Icon(icon, color: _textGray, size: 18),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Column(
          children: [
            _buildSearchBar(),
            _buildFilterBar(),
            if (_selectionMode) _buildSelectionBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: _accent))
                  : _error != null
                      ? _buildErrorWidget()
                      : _filteredEmployees.isEmpty
                          ? _buildEmptyWidget()
                          : _buildEmployeesList(),
            ),
          ],
        ),
        // شريط التطبيق الجماعي
        if (_selectionMode && _selectedIds.isNotEmpty)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildBulkActionBar(),
          ),
      ],
    );
  }

  Widget _buildSelectionBar() {
    final allVisibleSelected = _filteredEmployees.every((e) => _selectedIds.contains(e.id));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: _accent.withOpacity(0.06),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (allVisibleSelected) {
                  _selectedIds.clear();
                } else {
                  for (final e in _filteredEmployees) {
                    _selectedIds.add(e.id);
                  }
                }
              });
            },
            borderRadius: BorderRadius.circular(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allVisibleSelected ? Icons.check_box : Icons.check_box_outline_blank,
                  color: _accent, size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  allVisibleSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل (${_filteredEmployees.length})',
                  style: GoogleFonts.cairo(fontSize: 12, color: _accent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '${_selectedIds.length} محدد',
            style: GoogleFonts.cairo(fontSize: 12, color: _textWhite, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () => setState(() {
              _selectionMode = false;
              _selectedIds.clear();
            }),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('إلغاء', style: GoogleFonts.cairo(fontSize: 11, color: _danger, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, -3))],
        border: Border(top: BorderSide(color: _accent.withOpacity(0.2))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.security_rounded, color: _accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'تعيين صلاحيات لـ ${_selectedIds.length} موظف',
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: _textWhite),
              ),
              if (_isBulkApplying) ...[
                const SizedBox(width: 12),
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PermissionRegistry.templateNames.entries.map((t) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _isBulkApplying ? null : () => _applyBulkTemplate(t.key),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _accent.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PermissionRegistry.templateIcons[t.key], size: 18, color: _accent),
                        const SizedBox(width: 6),
                        Text(t.value, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: _textWhite)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _applyBulkTemplate(String templateKey) async {
    final templateName = PermissionRegistry.templateNames[templateKey] ?? templateKey;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد التعيين الجماعي', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          content: Text(
            'سيتم تطبيق قالب "$templateName" على ${_selectedIds.length} موظف.\n\nسيتم استبدال صلاحياتهم الحالية. هل تريد المتابعة؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('إلغاء', style: GoogleFonts.cairo())),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: Text('تطبيق', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBulkApplying = true);

    final template = PermissionRegistry.getTemplate(templateKey);
    const allActions = ['view', 'add', 'edit', 'delete', 'export', 'import', 'print', 'send'];

    // بناء Map<String, Map<String, bool>> لكل نظام
    Map<String, Map<String, bool>> buildPerms(List<PermissionEntry> system) {
      final perms = <String, Map<String, bool>>{};
      // أولاً: إغلاق كل الميزات
      for (final p in system) {
        perms[p.key] = {for (final a in allActions) a: false};
      }
      // ثانياً: تفعيل ما في القالب
      for (final entry in template.entries) {
        if (perms.containsKey(entry.key)) {
          final actions = entry.value['actions'] ?? [];
          for (final a in allActions) {
            perms[entry.key]![a] = actions.contains(a);
          }
        }
      }
      return perms;
    }

    final firstPerms = buildPerms(PermissionRegistry.firstSystem);
    final secondPerms = buildPerms(PermissionRegistry.secondSystem);

    int successCount = 0;
    int failCount = 0;

    for (final empId in _selectedIds) {
      try {
        final response = await _apiClient.put(
          '/internal/companies/${widget.companyId}/employees/$empId/permissions-v2',
          {
            'firstSystemPermissionsV2': firstPerms,
            'secondSystemPermissionsV2': secondPerms,
          },
          (json) => json,
          useInternalKey: true,
        );
        if (response.isSuccess) {
          successCount++;
        } else {
          failCount++;
        }
      } catch (_) {
        failCount++;
      }
    }

    if (!mounted) return;
    setState(() {
      _isBulkApplying = false;
      _selectionMode = false;
      _selectedIds.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failCount == 0
              ? 'تم تطبيق "$templateName" على $successCount موظف بنجاح'
              : 'نجح: $successCount | فشل: $failCount',
          style: GoogleFonts.cairo(),
        ),
        backgroundColor: failCount == 0 ? const Color(0xFF27AE60) : const Color(0xFFF39C12),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildFilterBar() {
    final r = context.responsive;
    final departments = _getUniqueValues((e) => e.department ?? '');
    final roles = _getUniqueValues((e) => e.role ?? '');
    final centers = _getUniqueValues((e) => e.center ?? '');

    if (_employees.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: r.contentPaddingH),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                SizedBox(
                  width: r.isMobile ? 110 : 150,
                  child: _buildFilterChip('القسم', _filterDepartment, departments, (v) {
                    setState(() => _filterDepartment = v);
                    _applyFilters();
                  }, (e) => e),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: r.isMobile ? 110 : 150,
                  child: _buildFilterChip('الدور', _filterRole, roles, (v) {
                    setState(() => _filterRole = v);
                    _applyFilters();
                  }, (e) => _getRoleNameAr(e)),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: r.isMobile ? 120 : 160,
                  child: _buildFilterChip('موقع العمل', _filterCenter, centers, (v) {
                    setState(() => _filterCenter = v);
                    _applyFilters();
                  }, (e) => e),
                ),
                if (_hasActiveFilters) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      setState(() { _filterDepartment = null; _filterRole = null; _filterCenter = null; });
                      _applyFilters();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.filter_alt_off, color: _danger, size: 20),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // زر التحديد الجماعي
                InkWell(
                  onTap: () => setState(() {
                    _selectionMode = !_selectionMode;
                    if (!_selectionMode) _selectedIds.clear();
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _selectionMode ? _accent.withValues(alpha: 0.15) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _selectionMode ? _accent : Colors.grey.shade300),
                    ),
                    child: Icon(Icons.checklist_rounded,
                        color: _selectionMode ? _accent : _textGray, size: 20),
                  ),
                ),
              ],
            ),
          ),
          if (_hasActiveFilters)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${_filteredEmployees.length} من ${_employees.length} موظف',
                style: GoogleFonts.cairo(fontSize: 11, color: _textGray),
              ),
            ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? selected, List<String> options,
      ValueChanged<String?> onChanged, String Function(String) displayName) {
    final r = context.responsive;
    return Container(
      height: r.isMobile ? 32 : 38,
      decoration: BoxDecoration(
        color: selected != null ? _accent.withValues(alpha: 0.1) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected != null ? _accent : Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          isDense: true,
          hint: Padding(
            padding: EdgeInsets.symmetric(horizontal: r.isMobile ? 4 : 10),
            child: Text(label, style: GoogleFonts.cairo(fontSize: r.captionSize, color: _textGray)),
          ),
          icon: Padding(
            padding: EdgeInsets.only(left: r.isMobile ? 2 : 6),
            child: Icon(selected != null ? Icons.close : Icons.arrow_drop_down,
                size: r.isMobile ? 14 : 18, color: selected != null ? _danger : _textGray),
          ),
          padding: EdgeInsets.symmetric(horizontal: r.isMobile ? 4 : 10),
          borderRadius: BorderRadius.circular(10),
          style: GoogleFonts.cairo(fontSize: r.captionSize, color: _textWhite),
          onTap: selected != null ? () {
            onChanged(null);
          } : null,
          items: options.map((o) => DropdownMenuItem(
            value: o,
            child: Text(displayName(o), style: GoogleFonts.cairo(fontSize: 12)),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final r = context.responsive;
    return Container(
      padding: EdgeInsets.fromLTRB(r.contentPaddingH, r.isMobile ? 8 : 14, r.contentPaddingH, r.isMobile ? 6 : 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(r.isMobile ? 10 : 14),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          onChanged: _filterEmployees,
          style: GoogleFonts.cairo(color: _textWhite, fontSize: r.bodySize),
          decoration: InputDecoration(
            hintText: 'بحث بالاسم، الهاتف، أو الدور...',
            hintStyle: GoogleFonts.cairo(color: _textGray, fontSize: r.captionSize + 1),
            prefixIcon:
                Icon(Icons.search_rounded, color: _accent, size: r.iconSizeSmall),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    onPressed: () {
                      _searchController.clear();
                      _filterEmployees('');
                    },
                    icon: Icon(Icons.close_rounded,
                        color: _textGray, size: r.iconSizeSmall),
                  )
                : null,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(
              horizontal: r.isMobile ? 10 : 16,
              vertical: r.isMobile ? 10 : 14,
            ),
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
            child:
                const Icon(Icons.cloud_off_rounded, size: 40, color: _danger),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
            child: const Icon(Icons.person_search_rounded,
                size: 40, color: _accent),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmployeesList() {
    final r = context.responsive;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(r.contentPaddingH, 6, r.contentPaddingH, 90),
      itemCount: _filteredEmployees.length,
      itemBuilder: (context, index) {
        final employee = _filteredEmployees[index];
        return _buildEmployeeCard(employee, index);
      },
    );
  }

  Widget _buildEmployeeCard(EmployeeModel employee, int index) {
    final r = context.responsive;
    final roleColor = _getRoleColor(employee.role);
    final roleLabel = _getRoleNameAr(employee.role);
    final isSelected = _selectedIds.contains(employee.id);

    return Padding(
      padding: EdgeInsets.only(bottom: r.isMobile ? 8 : 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _selectionMode
              ? () => setState(() {
                    isSelected ? _selectedIds.remove(employee.id) : _selectedIds.add(employee.id);
                  })
              : () => _showEmployeeDetails(employee),
          onLongPress: !_selectionMode
              ? () => setState(() {
                    _selectionMode = true;
                    _selectedIds.add(employee.id);
                  })
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? _accent.withOpacity(0.04) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? _accent
                    : employee.isActive
                        ? roleColor.withOpacity(0.2)
                        : Colors.grey.shade300,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
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
                          ? [
                              roleColor.withOpacity(0.6),
                              roleColor,
                              roleColor.withOpacity(0.6)
                            ]
                          : [
                              Colors.grey.shade300,
                              Colors.grey.shade400,
                              Colors.grey.shade300,
                            ],
                    ),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    r.isMobile ? 10 : 16,
                    r.isMobile ? 10 : 14,
                    r.isMobile ? 10 : 16,
                    r.isMobile ? 10 : 14,
                  ),
                  child: Row(
                    children: [
                      // ═══ Checkbox في وضع التحديد ═══
                      if (_selectionMode) ...[
                        Icon(
                          isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                          color: isSelected ? _accent : _textGray,
                          size: r.isMobile ? 18 : 22,
                        ),
                        SizedBox(width: r.isMobile ? 6 : 10),
                      ],
                      // ═══ أفاتار فخم ═══
                      Container(
                        width: r.isMobile ? 40 : 52,
                        height: r.isMobile ? 40 : 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: employee.isActive
                                ? [
                                    roleColor.withOpacity(0.3),
                                    roleColor.withOpacity(0.1)
                                  ]
                                : [
                                    Colors.grey.withOpacity(0.2),
                                    Colors.grey.withOpacity(0.05)
                                  ],
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
                          boxShadow: employee.isActive
                              ? [
                                  BoxShadow(
                                    color: roleColor.withOpacity(0.15),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            employee.fullName.isNotEmpty
                                ? employee.fullName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.cairo(
                              fontSize: r.isMobile ? 16 : 22,
                              fontWeight: FontWeight.bold,
                              color: employee.isActive ? roleColor : _textGray,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: r.isMobile ? 10 : 14),
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
                                fontSize: r.bodySize + 1,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: r.isMobile ? 2 : 4),
                            // الدور + الكود + القسم
                            Row(
                              children: [
                                // شارة الدور
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        roleColor.withOpacity(0.2),
                                        roleColor.withOpacity(0.08),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: roleColor.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    roleLabel,
                                    style: GoogleFonts.cairo(
                                      fontSize: r.captionSize - 1,
                                      color: roleColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (employee.employeeCode != null) ...[
                                  SizedBox(width: r.isMobile ? 4 : 8),
                                  Icon(Icons.badge_outlined,
                                      size: r.isMobile ? 10 : 12,
                                      color: _textGray.withOpacity(0.6)),
                                  const SizedBox(width: 3),
                                  Flexible(
                                    child: Text(
                                      employee.employeeCode!,
                                      style: GoogleFonts.cairo(
                                        fontSize: r.captionSize - 1,
                                        color: _textGray,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            SizedBox(height: r.isMobile ? 3 : 5),
                            // الهاتف
                            Row(
                              children: [
                                Icon(Icons.phone_rounded,
                                    size: r.isMobile ? 11 : 13, color: _accent.withOpacity(0.7)),
                                SizedBox(width: r.isMobile ? 3 : 5),
                                Text(
                                  employee.phoneNumber,
                                  style: GoogleFonts.cairo(
                                      fontSize: r.captionSize, color: _textGray),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // ═══ حالة + سهم ═══
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // شارة الحالة
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: r.isMobile ? 6 : 10, vertical: r.isMobile ? 2 : 3),
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
                                    color:
                                        employee.isActive ? _success : _danger,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (employee.isActive
                                                ? _success
                                                : _danger)
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
                                    fontSize: r.captionSize - 1,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        employee.isActive ? _success : _danger,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: r.isMobile ? 6 : 12),
                          // سهم للدخول
                          Container(
                            width: r.isMobile ? 22 : 28,
                            height: r.isMobile ? 22 : 28,
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: _accent.withOpacity(0.2)),
                            ),
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 13,
                              color: _accent,
                            ),
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
        label: Text('إضافة موظف',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
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
              content: Text('خطأ'),
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
                              content: Text('خطأ'),
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
        return 'ليدر';
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
    {'value': 'TechnicalLeader', 'label': 'ليدر'},
    {'value': 'Manager', 'label': 'مدير'},
    {'value': 'CompanyAdmin', 'label': 'مدير الشركة'},
  ];

  List<String> _departments = [];
  bool _isDepartmentsLoading = true;
  // أقسام متعددة
  List<String> _selectedDepartments = [];
  String? _primaryDepartment;

  List<String> _centersList = [];
  bool _isCentersLoading = true;

  bool get isEditing => widget.employee != null;

  @override
  void initState() {
    super.initState();
    _loadDepartments();
    _loadCenters();
    if (isEditing) {
      final emp = widget.employee!;
      _nameController.text = emp.fullName;
      _phoneController.text = emp.phoneNumber;
      _emailController.text = emp.email ?? '';
      _departmentController.text = emp.department ?? '';
      if (emp.department != null && emp.department!.isNotEmpty) {
        _selectedDepartments = [emp.department!];
        _primaryDepartment = emp.department;
      }
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

  Future<void> _loadDepartments() async {
    final depts = await DepartmentsDataService.instance.fetchDepartments();
    if (mounted) {
      setState(() {
        _departments = depts;
        _isDepartmentsLoading = false;
      });
    }
  }

  Future<void> _loadCenters() async {
    final names = await CentersDataService.instance.fetchCenters();
    if (mounted) {
      setState(() {
        _centersList = names;
        _isCentersLoading = false;
      });
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
        'department': _primaryDepartment ?? (_selectedDepartments.isNotEmpty ? _selectedDepartments.first : null),
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
            content: Text('خطأ'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        width: math.min(500, screenSize.width * 0.9),
        constraints: BoxConstraints(maxHeight: math.min(700, screenSize.height * 0.8)),
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
                            child: _isDepartmentsLoading
                                ? const SizedBox(height: 48, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                                : InputDecorator(
                                    decoration: _inputDecoration(
                                      'الأقسام${_selectedDepartments.isNotEmpty ? " (${_selectedDepartments.length})" : ""}',
                                      Icons.business_outlined,
                                    ),
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        ..._selectedDepartments.map((d) => Chip(
                                          label: Text(
                                            d == _primaryDepartment ? '$d (رئيسي)' : d,
                                            style: TextStyle(fontSize: 11, color: d == _primaryDepartment ? Colors.white : null),
                                          ),
                                          backgroundColor: d == _primaryDepartment ? Colors.blue : null,
                                          deleteIcon: const Icon(Icons.close, size: 14),
                                          onDeleted: () => setState(() {
                                            _selectedDepartments.remove(d);
                                            if (_primaryDepartment == d) {
                                              _primaryDepartment = _selectedDepartments.isNotEmpty ? _selectedDepartments.first : null;
                                            }
                                          }),
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                        )),
                                        // زر إضافة قسم
                                        ActionChip(
                                          label: const Text('+ إضافة', style: TextStyle(fontSize: 11)),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          onPressed: () {
                                            final available = _getAllDepartments().where((d) => !_selectedDepartments.contains(d)).toList();
                                            if (available.isEmpty) return;
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => SimpleDialog(
                                                title: const Text('اختر قسم', style: TextStyle(fontSize: 15)),
                                                children: available.map((d) => SimpleDialogOption(
                                                  onPressed: () {
                                                    Navigator.pop(ctx);
                                                    setState(() {
                                                      _selectedDepartments.add(d);
                                                      _primaryDepartment ??= d;
                                                    });
                                                  },
                                                  child: Text(d),
                                                )).toList(),
                                              ),
                                            );
                                          },
                                        ),
                                        // زر تعيين رئيسي
                                        if (_selectedDepartments.length > 1)
                                          ActionChip(
                                            avatar: const Icon(Icons.star, size: 14, color: Colors.amber),
                                            label: const Text('رئيسي', style: TextStyle(fontSize: 10)),
                                            visualDensity: VisualDensity.compact,
                                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (ctx) => SimpleDialog(
                                                  title: const Text('اختر القسم الرئيسي', style: TextStyle(fontSize: 15)),
                                                  children: _selectedDepartments.map((d) => SimpleDialogOption(
                                                    onPressed: () {
                                                      Navigator.pop(ctx);
                                                      setState(() => _primaryDepartment = d);
                                                    },
                                                    child: Row(children: [
                                                      if (d == _primaryDepartment) const Icon(Icons.star, size: 16, color: Colors.amber),
                                                      if (d == _primaryDepartment) const SizedBox(width: 6),
                                                      Text(d),
                                                    ]),
                                                  )).toList(),
                                                ),
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _isCentersLoading
                                ? const SizedBox(
                                    height: 48,
                                    child: Center(
                                        child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))))
                                : DropdownButtonFormField<String>(
                                    value: _centersList.contains(
                                                _centerController.text) &&
                                            _centerController.text.isNotEmpty
                                        ? _centerController.text
                                        : null,
                                    decoration: _inputDecoration(
                                        'المركز', Icons.location_on_outlined),
                                    items: [
                                      if (_centerController.text.isNotEmpty &&
                                          !_centersList
                                              .contains(_centerController.text))
                                        DropdownMenuItem(
                                            value: _centerController.text,
                                            child:
                                                Text(_centerController.text)),
                                      ..._centersList.map((c) =>
                                          DropdownMenuItem(
                                              value: c, child: Text(c))),
                                    ],
                                    onChanged: (v) {
                                      setState(() {
                                        _centerController.text = v ?? '';
                                      });
                                    },
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
