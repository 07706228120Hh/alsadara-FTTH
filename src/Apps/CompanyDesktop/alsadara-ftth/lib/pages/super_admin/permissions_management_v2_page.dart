/// 🔐 صفحة إدارة الصلاحيات V2
/// تتيح التحكم الدقيق في صلاحيات الشركات والموظفين
/// مع دعم الإجراءات المفصلة (view, add, edit, delete, export...)
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/api/api_client.dart';
import '../../permissions/permissions.dart';
import '../../theme/energy_dashboard_theme.dart';

/// صفحة إدارة صلاحيات V2 للشركة أو الموظف
class PermissionsManagementV2Page extends StatefulWidget {
  final String companyId;
  final String companyName;
  final String? employeeId;
  final String? employeeName;
  final bool embedded;

  const PermissionsManagementV2Page({
    super.key,
    required this.companyId,
    required this.companyName,
    this.employeeId,
    this.employeeName,
    this.embedded = false,
  });

  @override
  State<PermissionsManagementV2Page> createState() =>
      _PermissionsManagementV2PageState();
}

class _PermissionsManagementV2PageState
    extends State<PermissionsManagementV2Page>
    with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient.instance;
  late TabController _tabController;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _selectedTemplate;
  final Set<String> _expandedKeys = {};

  // صلاحيات النظام الأول V2
  Map<String, Map<String, bool>> _firstSystemPermissionsV2 = {};
  // صلاحيات النظام الثاني V2
  Map<String, Map<String, bool>> _secondSystemPermissionsV2 = {};

  // ═══ صلاحيات الشركة (لفلترة صلاحيات الموظف) ═══
  Map<String, Map<String, bool>> _companyFirstFeaturesV2 = {};
  Map<String, Map<String, bool>> _companySecondFeaturesV2 = {};

  // قائمة الإجراءات المتاحة
  final List<String> _actions = PermissionService.availableActions;
  final Map<String, String> _actionNames = PermissionService.actionNamesAr;

  // أسماء الصلاحيات - النظام الأول (تُولّد تلقائياً من السجل المركزي)
  final Map<String, Map<String, dynamic>> _firstSystemFeatures =
      PermissionRegistry.buildV2FeaturesMap(PermissionRegistry.firstSystem);

  // أسماء الصلاحيات - النظام الثاني (تُولّد تلقائياً من السجل المركزي)
  final Map<String, Map<String, dynamic>> _secondSystemFeatures =
      PermissionRegistry.buildV2FeaturesMap(PermissionRegistry.secondSystem);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    PermissionRegistry.loadCustomTemplates();
    _loadPermissions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// تحميل الصلاحيات من API
  Future<void> _loadPermissions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // ═══ إذا كان موظف، نحتاج جلب صلاحيات الشركة أولاً للفلترة ═══
      if (widget.employeeId != null) {
        await _loadCompanyFeatures();
      }

      final String endpoint = widget.employeeId != null
          ? '/internal/companies/${widget.companyId}/employees/${widget.employeeId}/permissions-v2'
          : '/internal/companies/${widget.companyId}/permissions-v2';

      final response = await _apiClient.get(
        endpoint,
        (json) => json,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data['data'] ?? response.data;

        // تحليل صلاحيات النظام الأول V2
        _firstSystemPermissionsV2 = _parsePermissionsV2(
          widget.employeeId != null
              ? data['firstSystemPermissionsV2'] ??
                  data['FirstSystemPermissionsV2']
              : data['enabledFirstSystemFeaturesV2'] ??
                  data['EnabledFirstSystemFeaturesV2'],
          _firstSystemFeatures.keys.toList(),
        );

        // تحليل صلاحيات النظام الثاني V2
        _secondSystemPermissionsV2 = _parsePermissionsV2(
          widget.employeeId != null
              ? data['secondSystemPermissionsV2'] ??
                  data['SecondSystemPermissionsV2']
              : data['enabledSecondSystemFeaturesV2'] ??
                  data['EnabledSecondSystemFeaturesV2'],
          _secondSystemFeatures.keys.toList(),
        );

        setState(() => _isLoading = false);
      } else {
        // إذا فشل جلب V2، نهيئ قيم افتراضية
        _initDefaultPermissions();
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading V2 permissions');
      _initDefaultPermissions();
      setState(() {
        _isLoading = false;
        _error = 'تعذر تحميل الصلاحيات';
      });
    }
  }

  /// تحليل صلاحيات V2 من JSON
  Map<String, Map<String, bool>> _parsePermissionsV2(
      dynamic jsonData, List<String> keys) {
    Map<String, Map<String, bool>> result = {};

    // تهيئة جميع المفاتيح بقيم افتراضية
    for (String key in keys) {
      result[key] = {for (String action in _actions) action: false};
    }

    if (jsonData == null) return result;

    try {
      Map<String, dynamic> parsed;
      if (jsonData is String && jsonData.isNotEmpty) {
        parsed = Map<String, dynamic>.from(jsonDecode(jsonData));
      } else if (jsonData is Map) {
        parsed = Map<String, dynamic>.from(jsonData);
      } else {
        return result;
      }

      for (var entry in parsed.entries) {
        if (keys.contains(entry.key) && entry.value is Map) {
          Map<String, bool> actions = {};
          for (var actionEntry in (entry.value as Map).entries) {
            actions[actionEntry.key.toString()] = actionEntry.value == true;
          }
          result[entry.key] = actions;
        }
      }
    } catch (e) {
      debugPrint('Error parsing V2 permissions');
    }

    return result;
  }

  /// تهيئة صلاحيات افتراضية
  void _initDefaultPermissions() {
    _firstSystemPermissionsV2 = {
      for (String key in _firstSystemFeatures.keys)
        key: {for (String action in _actions) action: false}
    };
    _secondSystemPermissionsV2 = {
      for (String key in _secondSystemFeatures.keys)
        key: {for (String action in _actions) action: false}
    };
  }

  /// جلب صلاحيات/ميزات الشركة لاستخدامها كفلتر عند تعديل صلاحيات الموظف
  Future<void> _loadCompanyFeatures() async {
    try {
      // جلب V2 (ميزات مفصلة)
      final v2Res = await _apiClient.get(
        '/internal/companies/${widget.companyId}/permissions-v2',
        (json) => json,
        useInternalKey: true,
      );

      if (v2Res.isSuccess && v2Res.data != null) {
        final data = v2Res.data['data'] ?? v2Res.data;

        final firstV2 = data['enabledFirstSystemFeaturesV2'] ??
            data['EnabledFirstSystemFeaturesV2'];
        final secondV2 = data['enabledSecondSystemFeaturesV2'] ??
            data['EnabledSecondSystemFeaturesV2'];

        _companyFirstFeaturesV2 =
            _parsePermissionsV2(firstV2, _firstSystemFeatures.keys.toList());
        _companySecondFeaturesV2 =
            _parsePermissionsV2(secondV2, _secondSystemFeatures.keys.toList());
      }
    } catch (e) {
      debugPrint('Error loading company features for filtering');
    }
  }

  /// هل الميزة مفعلة للشركة؟ (V2 فقط)
  bool _isFeatureEnabledForCompany(String featureKey, bool isFirstSystem) {
    if (widget.employeeId == null) return true;

    final v2Map =
        isFirstSystem ? _companyFirstFeaturesV2 : _companySecondFeaturesV2;

    if (v2Map.containsKey(featureKey)) {
      final actions = v2Map[featureKey]!;
      if (actions.values.any((v) => v == true)) return true;
    }

    // إذا لم تُجلب بيانات الشركة أصلاً، نسمح
    if (v2Map.isEmpty) return true;

    return false;
  }

  /// هل الإجراء المحدد مفعل للشركة؟ (V2 فقط)
  bool _isActionEnabledForCompany(
      String featureKey, String action, bool isFirstSystem) {
    if (widget.employeeId == null) return true;

    final v2Map =
        isFirstSystem ? _companyFirstFeaturesV2 : _companySecondFeaturesV2;

    if (v2Map.containsKey(featureKey)) {
      final actions = v2Map[featureKey]!;
      if (actions.containsKey(action)) return actions[action] == true;
      return false;
    }

    // إذا لم تُجلب بيانات → نسمح
    if (v2Map.isEmpty) return true;

    return false;
  }

  /// حفظ الصلاحيات
  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);

    try {
      final String endpoint = widget.employeeId != null
          ? '/internal/companies/${widget.companyId}/employees/${widget.employeeId}/permissions-v2'
          : '/internal/companies/${widget.companyId}/permissions-v2';

      final Map<String, dynamic> body = widget.employeeId != null
          ? {
              'firstSystemPermissionsV2': _firstSystemPermissionsV2,
              'secondSystemPermissionsV2': _secondSystemPermissionsV2,
            }
          : {
              'enabledFirstSystemFeaturesV2': _firstSystemPermissionsV2,
              'enabledSecondSystemFeaturesV2': _secondSystemPermissionsV2,
            };

      final response = await _apiClient.put(
        endpoint,
        body,
        (json) => json,
        useInternalKey: true,
      );

      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('تم حفظ الصلاحيات V2 بنجاح'),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'فشل في حفظ الصلاحيات'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildEmbeddedBody();
    return _buildFullPage();
  }

  /// الوضع المضمّن — بدون Scaffold، يُستخدم داخل تبويب
  Widget _buildEmbeddedBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _buildErrorWidget();

    return Column(
      children: [
        // شريط أدوات: تبويبات النظامين + أزرار
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: EnergyDashboardTheme.surfaceColor,
            border: Border(
                bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              // تبويبات النظامين — SegmentedButton style
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTabButton(
                      index: 0,
                      icon: Icons.home_work_rounded,
                      label: 'النظام الرئيسي',
                      color: const Color(0xFF9C27B0),
                    ),
                    const SizedBox(width: 4),
                    _buildTabButton(
                      index: 1,
                      icon: Icons.wifi_rounded,
                      label: 'نظام FTTH',
                      color: const Color(0xFF2196F3),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // زر إجراءات جماعية
              IconButton(
                onPressed: () => _showBulkActionDialog(),
                icon: const Icon(Icons.checklist_rounded, size: 20),
                tooltip: 'إجراءات جماعية',
                color: EnergyDashboardTheme.textMuted,
              ),
              const SizedBox(width: 4),
              // زر الحفظ
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _savePermissions,
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text('حفظ', style: GoogleFonts.cairo(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        // محتوى التبويبات
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPermissionsTab(
                _firstSystemFeatures,
                _firstSystemPermissionsV2,
                true,
              ),
              _buildPermissionsTab(
                _secondSystemFeatures,
                _secondSystemPermissionsV2,
                false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// الوضع الكامل — صفحة مستقلة مع Scaffold
  Widget _buildFullPage() {
    final isEmployee = widget.employeeId != null;
    final title = isEmployee
        ? 'صلاحيات ${widget.employeeName ?? "الموظف"}'
        : 'صلاحيات شركة ${widget.companyName}';

    return Scaffold(
      backgroundColor: EnergyDashboardTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: EnergyDashboardTheme.surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: EnergyDashboardTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF9C27B0).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.security_rounded,
                  color: Color(0xFF9C27B0), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: EnergyDashboardTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'نظام الصلاحيات المفصل V2',
                    style: TextStyle(
                      color: EnergyDashboardTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showBulkActionDialog(),
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'إجراءات جماعية',
            color: EnergyDashboardTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _savePermissions,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF9C27B0),
          unselectedLabelColor: EnergyDashboardTheme.textMuted,
          indicatorColor: const Color(0xFF9C27B0),
          indicatorWeight: 3,
          tabs: const [
            Tab(
              icon: Icon(Icons.home_work_rounded, size: 20),
              text: 'النظام الرئيسي',
            ),
            Tab(
              icon: Icon(Icons.wifi_rounded, size: 20),
              text: 'نظام FTTH',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorWidget()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPermissionsTab(
                      _firstSystemFeatures,
                      _firstSystemPermissionsV2,
                      true,
                    ),
                    _buildPermissionsTab(
                      _secondSystemFeatures,
                      _secondSystemPermissionsV2,
                      false,
                    ),
                  ],
                ),
    );
  }

  /// زر تبويب مخصص (SegmentedButton style)
  Widget _buildTabButton({
    required int index,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    final isSelected = _tabController.index == index;
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء widget الخطأ
  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            _error ?? 'حدث خطأ',
            style: TextStyle(color: Colors.red.shade700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadPermissions,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  /// بناء تاب الصلاحيات — عرض هرمي مع تجميع الأبناء
  Widget _buildPermissionsTab(
    Map<String, Map<String, dynamic>> features,
    Map<String, Map<String, bool>> permissions,
    bool isFirstSystem,
  ) {
    final entries = isFirstSystem
        ? PermissionRegistry.firstSystem
        : PermissionRegistry.secondSystem;
    final grouped = PermissionRegistry.getGrouped(entries);

    // فلترة: إذا كان موظف، نعرض فقط الميزات المفعلة للشركة
    final filteredGroups = grouped.entries.where((g) {
      return _isFeatureEnabledForCompany(g.key.key, isFirstSystem);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // تنبيه إذا كان هناك ميزات محظورة
          if (widget.employeeId != null &&
              filteredGroups.length < grouped.length)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Color(0xFFFF9800), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'يتم عرض الصلاحيات المفعلة للشركة فقط (${filteredGroups.length} من ${grouped.length})',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF795548)),
                    ),
                  ),
                ],
              ),
            ),
          // القوالب الجاهزة (للموظفين فقط)
          _buildTemplateBar(),
          // شريط عناوين الأعمدة
          _buildColumnsHeader(),
          const SizedBox(height: 8),
          // قائمة الصلاحيات الهرمية
          Expanded(
            child: filteredGroups.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.block,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد ميزات مفعلة لهذه الشركة في هذا النظام',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredGroups.length,
                    itemBuilder: (context, index) {
                      final group = filteredGroups[index];
                      final parent = group.key;
                      final children = group.value
                          .where((c) => _isFeatureEnabledForCompany(
                              c.key, isFirstSystem))
                          .toList();
                      final hasChildren = children.isNotEmpty;
                      final isExpanded = _expandedKeys.contains(parent.key);

                      // حساب عدد الأبناء المفعّلين
                      int enabledChildren = 0;
                      for (final c in children) {
                        if (permissions[c.key]?['view'] == true) {
                          enabledChildren++;
                        }
                      }

                      final parentPerms = permissions[parent.key] ??
                          {for (var a in _actions) a: false};
                      final allEnabled = (parent.allowedActions ?? _actions)
                          .every((a) => parentPerms[a] == true);
                      final someEnabled = (parent.allowedActions ?? _actions)
                              .any((a) => parentPerms[a] == true) &&
                          !allEnabled;

                      return Column(
                        children: [
                          // ═══ بطاقة الأب ═══
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: allEnabled
                                    ? const Color(0xFF4CAF50).withOpacity(0.5)
                                    : someEnabled
                                        ? const Color(0xFFFF9800)
                                            .withOpacity(0.5)
                                        : Colors.grey.shade200,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: hasChildren
                                  ? () {
                                      setState(() {
                                        if (isExpanded) {
                                          _expandedKeys.remove(parent.key);
                                        } else {
                                          _expandedKeys.add(parent.key);
                                        }
                                      });
                                    }
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  children: [
                                    // سهم التوسيع
                                    if (hasChildren)
                                      Icon(
                                        isExpanded
                                            ? Icons.expand_more_rounded
                                            : Icons.chevron_left_rounded,
                                        size: 20,
                                        color: const Color(0xFF9C27B0),
                                      )
                                    else
                                      const SizedBox(width: 20),
                                    const SizedBox(width: 4),
                                    // أيقونة
                                    Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: allEnabled
                                            ? const Color(0xFF4CAF50)
                                                .withOpacity(0.1)
                                            : someEnabled
                                                ? const Color(0xFFFF9800)
                                                    .withOpacity(0.1)
                                                : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        parent.icon,
                                        size: 18,
                                        color: allEnabled
                                            ? const Color(0xFF4CAF50)
                                            : someEnabled
                                                ? const Color(0xFFFF9800)
                                                : Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // اسم الصلاحية
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            parent.labelAr,
                                            style: GoogleFonts.cairo(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (hasChildren)
                                            Text(
                                              '$enabledChildren/${children.length} فرعي',
                                              style: GoogleFonts.cairo(
                                                fontSize: 9,
                                                color: enabledChildren > 0
                                                    ? const Color(0xFF27AE60)
                                                    : const Color(0xFF95A5A6),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    // مربعات الاختيار
                                    ..._actions.map((action) {
                                      final allowed =
                                          parent.allowedActions ?? _actions;
                                      if (!allowed.contains(action)) {
                                        return const SizedBox(width: 44);
                                      }
                                      final isEnabled =
                                          parentPerms[action] == true;
                                      final isAllowedByCompany =
                                          _isActionEnabledForCompany(
                                              parent.key,
                                              action,
                                              isFirstSystem);
                                      return SizedBox(
                                        width: 44,
                                        height: 36,
                                        child: Checkbox(
                                          value: isEnabled,
                                          onChanged: isAllowedByCompany
                                              ? (v) {
                                                  setState(() {
                                                    permissions[parent.key] ??=
                                                        {};
                                                    permissions[parent.key]![
                                                        action] = v ?? false;
                                                  });
                                                }
                                              : null,
                                          activeColor: _getActionColor(action),
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          visualDensity: VisualDensity.compact,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                        ),
                                      );
                                    }),
                                    // زر تبديل الكل
                                    SizedBox(
                                      width: 44,
                                      child: IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        iconSize: 18,
                                        onPressed: () {
                                          setState(() {
                                            final newVal = !allEnabled;
                                            if (newVal &&
                                                widget.employeeId != null) {
                                              permissions[parent.key] = {
                                                for (var a in _actions)
                                                  a: _isActionEnabledForCompany(
                                                      parent.key,
                                                      a,
                                                      isFirstSystem)
                                              };
                                            } else {
                                              permissions[parent.key] = {
                                                for (var a in _actions)
                                                  a: newVal
                                              };
                                            }
                                            for (final child in children) {
                                              if (newVal &&
                                                  widget.employeeId != null) {
                                                permissions[child.key] = {
                                                  for (var a in _actions)
                                                    a: _isActionEnabledForCompany(
                                                        child.key,
                                                        a,
                                                        isFirstSystem)
                                                };
                                              } else {
                                                permissions[child.key] = {
                                                  for (var a in _actions)
                                                    a: newVal
                                                };
                                              }
                                            }
                                          });
                                        },
                                        icon: Icon(
                                          allEnabled
                                              ? Icons.check_box_rounded
                                              : someEnabled
                                                  ? Icons
                                                      .indeterminate_check_box_rounded
                                                  : Icons
                                                      .check_box_outline_blank_rounded,
                                          color: allEnabled
                                              ? const Color(0xFF4CAF50)
                                              : someEnabled
                                                  ? const Color(0xFFFF9800)
                                                  : Colors.grey,
                                          size: 18,
                                        ),
                                        tooltip: allEnabled
                                            ? 'إلغاء الكل'
                                            : 'تحديد الكل',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // ═══ الأبناء — يظهرون عند التوسيع ═══
                          if (hasChildren && isExpanded)
                            Container(
                              margin: const EdgeInsets.only(
                                  right: 24, bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8F9FA),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFFEEEEEE)),
                              ),
                              child: Column(
                                children: children.map((child) {
                                  final childPerms =
                                      permissions[child.key] ??
                                          {for (var a in _actions) a: false};
                                  final childAllowed =
                                      child.allowedActions ?? _actions;
                                  final childAllEnabled = childAllowed
                                      .every((a) => childPerms[a] == true);
                                  final childSomeEnabled = childAllowed
                                          .any((a) => childPerms[a] == true) &&
                                      !childAllEnabled;

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(
                                              color: Color(0xFFEEEEEE))),
                                    ),
                                    child: Row(
                                      children: [
                                        // مسافة فارغة بدل سهم التوسيع
                                        const SizedBox(width: 24),
                                        // أيقونة
                                        Icon(child.icon,
                                            size: 16,
                                            color:
                                                childPerms['view'] == true
                                                    ? const Color(0xFF9C27B0)
                                                    : Colors.grey.shade400),
                                        const SizedBox(width: 8),
                                        // اسم الصلاحية الفرعية
                                        Expanded(
                                          child: Text(
                                            child.labelAr,
                                            style: GoogleFonts.cairo(
                                              fontSize: 11,
                                              color:
                                                  childPerms['view'] == true
                                                      ? Colors.black87
                                                      : Colors.black45,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // مربعات الاختيار
                                        ..._actions.map((action) {
                                          if (!childAllowed.contains(action)) {
                                            return const SizedBox(width: 44);
                                          }
                                          final isEnabled =
                                              childPerms[action] == true;
                                          final isAllowedByCompany =
                                              _isActionEnabledForCompany(
                                                  child.key,
                                                  action,
                                                  isFirstSystem);
                                          return SizedBox(
                                            width: 44,
                                            height: 36,
                                            child: Checkbox(
                                              value: isEnabled,
                                              onChanged: isAllowedByCompany
                                                  ? (v) {
                                                      setState(() {
                                                        permissions[
                                                                child.key] ??=
                                                            {};
                                                        permissions[child.key]![
                                                                action] =
                                                            v ?? false;
                                                      });
                                                    }
                                                  : null,
                                              activeColor:
                                                  _getActionColor(action),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          );
                                        }),
                                        // زر تبديل الكل للابن
                                        SizedBox(
                                          width: 44,
                                          child: IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                const BoxConstraints(),
                                            iconSize: 16,
                                            onPressed: () {
                                              setState(() {
                                                final newVal =
                                                    !childAllEnabled;
                                                if (newVal &&
                                                    widget.employeeId !=
                                                        null) {
                                                  permissions[child.key] = {
                                                    for (var a in _actions)
                                                      a: _isActionEnabledForCompany(
                                                          child.key,
                                                          a,
                                                          isFirstSystem)
                                                  };
                                                } else {
                                                  permissions[child.key] = {
                                                    for (var a in _actions)
                                                      a: newVal
                                                  };
                                                }
                                              });
                                            },
                                            icon: Icon(
                                              childAllEnabled
                                                  ? Icons.check_box_rounded
                                                  : childSomeEnabled
                                                      ? Icons
                                                          .indeterminate_check_box_rounded
                                                      : Icons
                                                          .check_box_outline_blank_rounded,
                                              color: childAllEnabled
                                                  ? const Color(0xFF4CAF50)
                                                  : childSomeEnabled
                                                      ? const Color(0xFFFF9800)
                                                      : Colors.grey,
                                              size: 16,
                                            ),
                                            tooltip: childAllEnabled
                                                ? 'إلغاء الكل'
                                                : 'تحديد الكل',
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// شريط عناوين الأعمدة — محاذي لمربعات الاختيار
  Widget _buildColumnsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF9C27B0).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // مسافة سهم التوسيع + أيقونة + اسم
          const Expanded(child: SizedBox()),
          // عناوين الأعمدة
          ..._actions.map((action) {
            return SizedBox(
              width: 44,
              child: Text(
                _actionNames[action] ?? action,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _getActionColor(action),
                ),
                textAlign: TextAlign.center,
              ),
            );
          }),
          // عمود "الكل"
          SizedBox(
            width: 44,
            child: Text(
              'الكل',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// تطبيق قالب صلاحيات جاهز مع مراعاة فلترة صلاحيات الشركة
  void _applyTemplate(String templateName) {
    final template = PermissionRegistry.getTemplate(templateName);
    setState(() {
      _selectedTemplate = templateName;

      // مسح الصلاحيات الحالية
      for (var key in _firstSystemPermissionsV2.keys) {
        _firstSystemPermissionsV2[key] = {for (var a in _actions) a: false};
      }
      for (var key in _secondSystemPermissionsV2.keys) {
        _secondSystemPermissionsV2[key] = {for (var a in _actions) a: false};
      }

      // تطبيق القالب — على كلا النظامين (بعض المفاتيح مشتركة)
      for (final entry in template.entries) {
        final key = entry.key;
        final actions = entry.value['actions'] as List? ?? [];

        final inFirst =
            PermissionRegistry.firstSystem.any((e) => e.key == key);
        final inSecond =
            PermissionRegistry.secondSystem.any((e) => e.key == key);

        void applyTo(Map<String, Map<String, bool>> permsMap,
            bool isFirstSystem) {
          if (!permsMap.containsKey(key)) return;
          for (final a in _actions) {
            final wanted = actions.contains(a);
            if (wanted &&
                widget.employeeId != null &&
                !_isActionEnabledForCompany(key, a, isFirstSystem)) {
              permsMap[key]![a] = false;
            } else {
              permsMap[key]![a] = wanted;
            }
          }
        }

        if (inFirst) applyTo(_firstSystemPermissionsV2, true);
        if (inSecond) applyTo(_secondSystemPermissionsV2, false);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'تم تطبيق قالب: ${PermissionRegistry.templateNames[templateName]}'),
        backgroundColor: const Color(0xFF4CAF50),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// شريط القوالب الجاهزة — يظهر فقط عند تعديل صلاحيات موظف
  Widget _buildTemplateBar() {
    if (widget.employeeId == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF39C12).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFFF39C12).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on_rounded,
                  color: Color(0xFFF39C12), size: 18),
              const SizedBox(width: 6),
              Text('قوالب جاهزة — تطبيق سريع',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: const Color(0xFFF39C12))),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: PermissionRegistry.templateNames.entries.map((e) {
              final selected = _selectedTemplate == e.key;
              final isCustom = PermissionRegistry.isCustomized(e.key);
              final icon = PermissionRegistry.templateIcons[e.key] ??
                  Icons.person_outline;
              return GestureDetector(
                onLongPress: () => _showEditTemplateDialog(e.key),
                child: ActionChip(
                  avatar: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        selected ? Icons.check_circle : icon,
                        size: 16,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF9C27B0),
                      ),
                      if (isCustom)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF39C12),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(e.value,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            color:
                                selected ? Colors.white : Colors.black87,
                          )),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _showEditTemplateDialog(e.key),
                        child: Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: selected
                              ? Colors.white70
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                  backgroundColor:
                      selected ? const Color(0xFF9C27B0) : Colors.white,
                  side: BorderSide(
                      color: selected
                          ? const Color(0xFF9C27B0)
                          : isCustom
                              ? const Color(0xFFF39C12)
                              : Colors.grey.shade300),
                  onPressed: () => _applyTemplate(e.key),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// dialog تعديل القالب
  void _showEditTemplateDialog(String templateKey) {
    final templateName = PermissionRegistry.templateNames[templateKey] ?? '';
    final template = PermissionRegistry.getTemplate(templateKey);
    final isCustom = PermissionRegistry.isCustomized(templateKey);

    // بناء نسخة قابلة للتعديل من القالب
    final editPerms = <String, Map<String, bool>>{};

    // تهيئة كل الميزات بـ false
    for (final sys in [
      PermissionRegistry.firstSystem,
      PermissionRegistry.secondSystem
    ]) {
      for (final e in sys) {
        editPerms[e.key] = {for (var a in _actions) a: false};
      }
    }

    // تطبيق صلاحيات القالب الحالي
    for (final entry in template.entries) {
      final key = entry.key;
      final actions = entry.value['actions'] as List? ?? [];
      if (editPerms.containsKey(key)) {
        for (final a in _actions) {
          editPerms[key]![a] = actions.contains(a);
        }
      }
    }

    final expandedKeys = <String>{};

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Widget buildSystemSection(
                String title, List<PermissionEntry> system) {
              final parents =
                  system.where((e) => e.isTopLevel).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9C27B0).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.folder_rounded,
                            size: 16, color: Color(0xFF9C27B0)),
                        const SizedBox(width: 6),
                        Text(title,
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: const Color(0xFF9C27B0))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...parents.map((parent) {
                    final children = system
                        .where((e) => e.parent == parent.key)
                        .toList();
                    final isExpanded =
                        expandedKeys.contains(parent.key);
                    final allowedActions =
                        parent.allowedActions ?? _actions;
                    final enabledCount = _actions
                        .where((a) =>
                            editPerms[parent.key]?[a] == true)
                        .length;

                    return Column(
                      children: [
                        InkWell(
                          onTap: children.isEmpty
                              ? null
                              : () {
                                  setDialogState(() {
                                    if (isExpanded) {
                                      expandedKeys
                                          .remove(parent.key);
                                    } else {
                                      expandedKeys.add(parent.key);
                                    }
                                  });
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 2),
                            child: Row(
                              children: [
                                if (children.isNotEmpty)
                                  Icon(
                                    isExpanded
                                        ? Icons
                                            .keyboard_arrow_down_rounded
                                        : Icons
                                            .keyboard_arrow_left_rounded,
                                    size: 18,
                                    color: Colors.grey,
                                  )
                                else
                                  const SizedBox(width: 18),
                                Icon(parent.icon,
                                    size: 16,
                                    color: enabledCount > 0
                                        ? const Color(0xFF9C27B0)
                                        : Colors.grey),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    parent.labelAr,
                                    style: GoogleFonts.cairo(
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight.w600),
                                  ),
                                ),
                                // أزرار الإجراءات — عرض كل الأعمدة
                                ..._actions.map((a) {
                                  if (!allowedActions.contains(a)) {
                                    return const SizedBox(width: 32);
                                  }
                                  final enabled =
                                      editPerms[parent.key]?[a] ==
                                          true;
                                  return SizedBox(
                                    width: 32,
                                    height: 28,
                                    child: Checkbox(
                                      value: enabled,
                                      onChanged: (v) {
                                        setDialogState(() {
                                          editPerms[parent.key]![a] =
                                              v ?? false;
                                        });
                                      },
                                      materialTapTargetSize:
                                          MaterialTapTargetSize
                                              .shrinkWrap,
                                      activeColor:
                                          _getActionColor(a),
                                    ),
                                  );
                                }),
                                // زر تحديد/إلغاء الصف كامل
                                SizedBox(
                                  width: 32,
                                  height: 28,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    iconSize: 16,
                                    onPressed: () {
                                      setDialogState(() {
                                        final allOn = allowedActions
                                            .every((a) =>
                                                editPerms[parent
                                                        .key]?[a] ==
                                                    true);
                                        for (final a
                                            in allowedActions) {
                                          editPerms[parent.key]![
                                              a] = !allOn;
                                        }
                                      });
                                    },
                                    icon: Icon(
                                      allowedActions.every((a) =>
                                              editPerms[parent
                                                      .key]?[a] ==
                                                  true)
                                          ? Icons
                                              .check_box_rounded
                                          : Icons
                                              .check_box_outline_blank_rounded,
                                      color: allowedActions.every(
                                              (a) =>
                                                  editPerms[parent
                                                          .key]?[a] ==
                                                      true)
                                          ? const Color(0xFF9C27B0)
                                          : Colors.grey,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isExpanded)
                          ...children.map((child) {
                            final childAllowed =
                                child.allowedActions ?? _actions;
                            return Padding(
                              padding: const EdgeInsetsDirectional
                                  .only(start: 24),
                              child: Row(
                                children: [
                                  const SizedBox(width: 18),
                                  Icon(child.icon,
                                      size: 14,
                                      color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(child.labelAr,
                                        style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            color: Colors
                                                .grey.shade700)),
                                  ),
                                  ..._actions.map((a) {
                                    if (!childAllowed.contains(a)) {
                                      return const SizedBox(
                                          width: 32);
                                    }
                                    final enabled =
                                        editPerms[child.key]?[a] ==
                                            true;
                                    return SizedBox(
                                      width: 32,
                                      height: 26,
                                      child: Checkbox(
                                        value: enabled,
                                        onChanged: (v) {
                                          setDialogState(() {
                                            editPerms[child.key]![
                                                a] = v ?? false;
                                          });
                                        },
                                        materialTapTargetSize:
                                            MaterialTapTargetSize
                                                .shrinkWrap,
                                        activeColor:
                                            _getActionColor(a),
                                      ),
                                    );
                                  }),
                                  // زر تحديد/إلغاء الصف كامل
                                  SizedBox(
                                    width: 32,
                                    height: 26,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      iconSize: 14,
                                      onPressed: () {
                                        setDialogState(() {
                                          final allOn = childAllowed
                                              .every((a) =>
                                                  editPerms[child
                                                          .key]?[a] ==
                                                      true);
                                          for (final a
                                              in childAllowed) {
                                            editPerms[child.key]![
                                                a] = !allOn;
                                          }
                                        });
                                      },
                                      icon: Icon(
                                        childAllowed.every((a) =>
                                                editPerms[child
                                                        .key]?[a] ==
                                                    true)
                                            ? Icons
                                                .check_box_rounded
                                            : Icons
                                                .check_box_outline_blank_rounded,
                                        color: childAllowed.every(
                                                (a) =>
                                                    editPerms[child
                                                            .key]?[a] ==
                                                        true)
                                            ? const Color(
                                                0xFF9C27B0)
                                            : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        const Divider(height: 1),
                      ],
                    );
                  }),
                ],
              );
            }

            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    PermissionRegistry.templateIcons[templateKey] ??
                        Icons.edit_rounded,
                    color: const Color(0xFF9C27B0),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تعديل قالب: $templateName',
                      style: GoogleFonts.cairo(
                          fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (isCustom)
                    Tooltip(
                      message: 'القالب معدّل — اضغط لإعادة الافتراضي',
                      child: InkWell(
                        onTap: () async {
                          await PermissionRegistry.resetTemplate(
                              templateKey);
                          Navigator.pop(ctx);
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'تم إعادة "$templateName" للافتراضي'),
                              backgroundColor:
                                  const Color(0xFF2196F3),
                            ),
                          );
                        },
                        child: const Icon(Icons.restore_rounded,
                            size: 20, color: Color(0xFFF39C12)),
                      ),
                    ),
                ],
              ),
              content: SizedBox(
                width: 700,
                height: 500,
                child: Column(
                  children: [
                    // رأس الأعمدة
                    Row(
                      children: [
                        const SizedBox(width: 56),
                        Expanded(
                          child: Text('الميزة',
                              style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey)),
                        ),
                        ..._actions.map((a) => SizedBox(
                              width: 32,
                              child: Text(
                                _actionNames[a] ?? a,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: _getActionColor(a)),
                              ),
                            )),
                        SizedBox(
                          width: 32,
                          child: Text('الكل',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cairo(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade600)),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            buildSystemSection('النظام الرئيسي',
                                PermissionRegistry.firstSystem),
                            const SizedBox(height: 12),
                            buildSystemSection('نظام FTTH',
                                PermissionRegistry.secondSystem),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child:
                      Text('إلغاء', style: GoogleFonts.cairo()),
                ),
                if (isCustom)
                  TextButton(
                    onPressed: () async {
                      await PermissionRegistry.resetTemplate(
                          templateKey);
                      Navigator.pop(ctx);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'تم إعادة "$templateName" للافتراضي'),
                          backgroundColor: const Color(0xFF2196F3),
                        ),
                      );
                    },
                    child: Text('إعادة للافتراضي',
                        style: GoogleFonts.cairo(
                            color: const Color(0xFFF39C12))),
                  ),
                ElevatedButton.icon(
                  onPressed: () async {
                    // تحويل editPerms إلى صيغة القالب
                    final newTemplate =
                        <String, Map<String, List<String>>>{};
                    for (final entry in editPerms.entries) {
                      final enabledActions = entry.value.entries
                          .where((e) => e.value)
                          .map((e) => e.key)
                          .toList();
                      if (enabledActions.isNotEmpty) {
                        newTemplate[entry.key] = {
                          'actions': enabledActions
                        };
                      }
                    }

                    await PermissionRegistry.saveCustomTemplate(
                        templateKey, newTemplate);
                    Navigator.pop(ctx);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'تم حفظ التعديلات على "$templateName"'),
                        backgroundColor: const Color(0xFF4CAF50),
                      ),
                    );
                  },
                  icon: const Icon(Icons.save_rounded, size: 16),
                  label: Text('حفظ',
                      style: GoogleFonts.cairo(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// الحصول على لون الإجراء
  Color _getActionColor(String action) {
    switch (action) {
      case 'view':
        return const Color(0xFF2196F3);
      case 'add':
        return const Color(0xFF4CAF50);
      case 'edit':
        return const Color(0xFFFF9800);
      case 'delete':
        return const Color(0xFFF44336);
      case 'export':
        return const Color(0xFF9C27B0);
      case 'import':
        return const Color(0xFF009688);
      case 'print':
        return const Color(0xFF607D8B);
      case 'send':
        return const Color(0xFF00BCD4);
      default:
        return Colors.grey;
    }
  }

  /// عرض حوار الإجراءات الجماعية
  void _showBulkActionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.checklist_rounded, color: Color(0xFF9C27B0)),
            SizedBox(width: 8),
            Text('إجراءات جماعية'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اختر الإجراء المراد تطبيقه على جميع الصلاحيات:'),
            const SizedBox(height: 16),
            // تحديد الكل
            ListTile(
              leading:
                  const Icon(Icons.check_box_rounded, color: Color(0xFF4CAF50)),
              title: const Text('تحديد جميع الصلاحيات'),
              subtitle: const Text('تفعيل جميع الإجراءات لجميع الصلاحيات'),
              onTap: () {
                _bulkToggleAll(true);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            // إلغاء الكل
            ListTile(
              leading: const Icon(Icons.check_box_outline_blank_rounded,
                  color: Colors.grey),
              title: const Text('إلغاء جميع الصلاحيات'),
              subtitle: const Text('تعطيل جميع الإجراءات لجميع الصلاحيات'),
              onTap: () {
                _bulkToggleAll(false);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            // تفعيل العرض فقط
            ListTile(
              leading: const Icon(Icons.visibility_rounded,
                  color: Color(0xFF2196F3)),
              title: const Text('العرض فقط'),
              subtitle: const Text('تفعيل صلاحية العرض فقط لجميع الميزات'),
              onTap: () {
                _bulkSetViewOnly();
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  /// تحديد/إلغاء جميع الصلاحيات
  void _bulkToggleAll(bool value) {
    setState(() {
      for (var entry in PermissionRegistry.firstSystem) {
        final key = entry.key;
        if (value && widget.employeeId != null) {
          if (!_isFeatureEnabledForCompany(key, true)) continue;
          _firstSystemPermissionsV2[key] = {
            for (var a in _actions) a: _isActionEnabledForCompany(key, a, true)
          };
        } else {
          _firstSystemPermissionsV2[key] = {for (var a in _actions) a: value};
        }
      }
      for (var entry in PermissionRegistry.secondSystem) {
        final key = entry.key;
        if (value && widget.employeeId != null) {
          if (!_isFeatureEnabledForCompany(key, false)) continue;
          _secondSystemPermissionsV2[key] = {
            for (var a in _actions) a: _isActionEnabledForCompany(key, a, false)
          };
        } else {
          _secondSystemPermissionsV2[key] = {for (var a in _actions) a: value};
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text(value ? 'تم تفعيل جميع الصلاحيات' : 'تم تعطيل جميع الصلاحيات'),
        backgroundColor: value ? Colors.green : Colors.orange,
      ),
    );
  }

  /// تفعيل العرض فقط
  void _bulkSetViewOnly() {
    setState(() {
      for (var entry in PermissionRegistry.firstSystem) {
        final key = entry.key;
        if (widget.employeeId != null &&
            !_isFeatureEnabledForCompany(key, true)) continue;
        _firstSystemPermissionsV2[key] = {
          for (var a in _actions)
            a: a == 'view' && _isActionEnabledForCompany(key, a, true)
        };
      }
      for (var entry in PermissionRegistry.secondSystem) {
        final key = entry.key;
        if (widget.employeeId != null &&
            !_isFeatureEnabledForCompany(key, false)) continue;
        _secondSystemPermissionsV2[key] = {
          for (var a in _actions)
            a: a == 'view' && _isActionEnabledForCompany(key, a, false)
        };
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تفعيل صلاحية العرض فقط لجميع الميزات'),
        backgroundColor: Colors.blue,
      ),
    );
  }
}
