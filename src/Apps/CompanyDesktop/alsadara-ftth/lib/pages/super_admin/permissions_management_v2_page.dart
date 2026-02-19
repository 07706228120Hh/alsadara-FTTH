/// 🔐 صفحة إدارة الصلاحيات V2
/// تتيح التحكم الدقيق في صلاحيات الشركات والموظفين
/// مع دعم الإجراءات المفصلة (view, add, edit, delete, export...)
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api/api_client.dart';
import '../../services/permissions_service.dart';
import '../../theme/energy_dashboard_theme.dart';
import '../../config/permission_registry.dart';

/// صفحة إدارة صلاحيات V2 للشركة أو الموظف
class PermissionsManagementV2Page extends StatefulWidget {
  final String companyId;
  final String companyName;
  final String? employeeId;
  final String? employeeName;

  const PermissionsManagementV2Page({
    super.key,
    required this.companyId,
    required this.companyName,
    this.employeeId,
    this.employeeName,
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

  // صلاحيات النظام الأول V2
  Map<String, Map<String, bool>> _firstSystemPermissionsV2 = {};
  // صلاحيات النظام الثاني V2
  Map<String, Map<String, bool>> _secondSystemPermissionsV2 = {};

  // ═══ صلاحيات الشركة (لفلترة صلاحيات الموظف) ═══
  Map<String, bool> _companyFirstFeaturesV1 = {};
  Map<String, bool> _companySecondFeaturesV1 = {};
  Map<String, Map<String, bool>> _companyFirstFeaturesV2 = {};
  Map<String, Map<String, bool>> _companySecondFeaturesV2 = {};

  // قائمة الإجراءات المتاحة
  final List<String> _actions = PermissionsService.availableActions;
  final Map<String, String> _actionNames = PermissionsService.actionNamesAr;

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
      debugPrint('Error loading V2 permissions: $e');
      _initDefaultPermissions();
      setState(() {
        _isLoading = false;
        _error = 'تعذر تحميل الصلاحيات: $e';
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
      debugPrint('Error parsing V2 permissions: $e');
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
      // جلب V1 (ميزات بسيطة)
      final companyRes = await _apiClient.get(
        '/internal/companies/${widget.companyId}',
        (json) => json,
        useInternalKey: true,
      );

      if (companyRes.isSuccess && companyRes.data != null) {
        final data = companyRes.data['data'] ?? companyRes.data;

        // V1 features
        final firstV1 = data['enabledFirstSystemFeatures'] ??
            data['EnabledFirstSystemFeatures'];
        final secondV1 = data['enabledSecondSystemFeatures'] ??
            data['EnabledSecondSystemFeatures'];

        if (firstV1 != null) {
          if (firstV1 is String && firstV1.isNotEmpty) {
            _companyFirstFeaturesV1 =
                Map<String, bool>.from(jsonDecode(firstV1));
          } else if (firstV1 is Map) {
            _companyFirstFeaturesV1 = Map<String, bool>.from(firstV1);
          }
        }
        if (secondV1 != null) {
          if (secondV1 is String && secondV1.isNotEmpty) {
            _companySecondFeaturesV1 =
                Map<String, bool>.from(jsonDecode(secondV1));
          } else if (secondV1 is Map) {
            _companySecondFeaturesV1 = Map<String, bool>.from(secondV1);
          }
        }
      }

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
      debugPrint('Error loading company features for filtering: $e');
    }
  }

  /// هل الميزة مفعلة للشركة؟ (V2 أو V1 fallback)
  bool _isFeatureEnabledForCompany(String featureKey, bool isFirstSystem) {
    // إذا ليس موظف (يعني نعدل صلاحيات الشركة نفسها) → لا قيود
    if (widget.employeeId == null) return true;

    final v2Map =
        isFirstSystem ? _companyFirstFeaturesV2 : _companySecondFeaturesV2;
    final v1Map =
        isFirstSystem ? _companyFirstFeaturesV1 : _companySecondFeaturesV1;

    // تحقق V2: إذا أي إجراء مفعل → الميزة مفعلة
    if (v2Map.containsKey(featureKey)) {
      final actions = v2Map[featureKey]!;
      if (actions.values.any((v) => v == true)) return true;
    }

    // fallback V1: إذا مفعل بشكل بسيط
    if (v1Map.containsKey(featureKey) && v1Map[featureKey] == true) return true;

    // إذا لم تُجلب بيانات الشركة أصلاً، نسمح (للتوافق العكسي)
    if (v1Map.isEmpty && v2Map.isEmpty) return true;

    return false;
  }

  /// هل الإجراء المحدد مفعل للشركة؟ (V2 فقط)
  bool _isActionEnabledForCompany(
      String featureKey, String action, bool isFirstSystem) {
    if (widget.employeeId == null) return true;

    final v2Map =
        isFirstSystem ? _companyFirstFeaturesV2 : _companySecondFeaturesV2;
    final v1Map =
        isFirstSystem ? _companyFirstFeaturesV1 : _companySecondFeaturesV1;

    // V2: تحقق من الإجراء المحدد
    if (v2Map.containsKey(featureKey)) {
      final actions = v2Map[featureKey]!;
      if (actions.containsKey(action)) return actions[action] == true;
      // إذا V2 موجود لكن الإجراء غير محدد → ممنوع
      return false;
    }

    // fallback V1: إذا الميزة مفعلة بشكل بسيط → نسمح بكل الإجراءات
    if (v1Map.containsKey(featureKey) && v1Map[featureKey] == true) return true;

    // إذا لم تُجلب بيانات → نسمح (للتوافق)
    if (v1Map.isEmpty && v2Map.isEmpty) return true;

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
            content: Text('خطأ: $e'),
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
          // زر تحديد الكل
          IconButton(
            onPressed: () => _showBulkActionDialog(),
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'إجراءات جماعية',
            color: EnergyDashboardTheme.textMuted,
          ),
          const SizedBox(width: 8),
          // زر الحفظ
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

  /// بناء تاب الصلاحيات
  Widget _buildPermissionsTab(
    Map<String, Map<String, dynamic>> features,
    Map<String, Map<String, bool>> permissions,
    bool isFirstSystem,
  ) {
    // فلترة الميزات: إذا كان موظف، نعرض فقط الميزات المفعلة للشركة
    final filteredEntries = features.entries.where((entry) {
      return _isFeatureEnabledForCompany(entry.key, isFirstSystem);
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // تنبيه إذا كان هناك ميزات محظورة
          if (widget.employeeId != null &&
              filteredEntries.length < features.length)
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
                      'يتم عرض الصلاحيات المفعلة للشركة فقط (${filteredEntries.length} من ${features.length})',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF795548)),
                    ),
                  ),
                ],
              ),
            ),
          // شريط الإجراءات
          _buildActionsHeader(),
          const SizedBox(height: 12),
          // قائمة الصلاحيات
          Expanded(
            child: filteredEntries.isEmpty
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
                    itemCount: filteredEntries.length,
                    itemBuilder: (context, index) {
                      final entry = filteredEntries[index];
                      final key = entry.key;
                      final feature = entry.value;
                      final featurePermissions = permissions[key] ??
                          {for (var a in _actions) a: false};

                      return _buildPermissionCard(
                        key: key,
                        label: feature['label'] as String,
                        icon: feature['icon'] as IconData,
                        description: feature['description'] as String,
                        permissions: featurePermissions,
                        isFirstSystem: isFirstSystem,
                        onChanged: (action, value) {
                          // تحقق إضافي: لا تسمح بتفعيل إجراء غير مفعل للشركة
                          if (value &&
                              !_isActionEnabledForCompany(
                                  key, action, isFirstSystem)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('هذا الإجراء غير مفعل للشركة'),
                                backgroundColor: Colors.orange,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            permissions[key] ??= {};
                            permissions[key]![action] = value;
                          });
                        },
                        onToggleAll: (value) {
                          setState(() {
                            if (value && widget.employeeId != null) {
                              // عند تحديد الكل: فقط الإجراءات المفعلة للشركة
                              permissions[key] = {
                                for (var a in _actions)
                                  a: _isActionEnabledForCompany(
                                      key, a, isFirstSystem)
                              };
                            } else {
                              permissions[key] = {
                                for (var a in _actions) a: value
                              };
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// بناء شريط رأس الإجراءات
  Widget _buildActionsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0).withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF9C27B0).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 200), // مكان اسم الصلاحية
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _actions.map((action) {
                return SizedBox(
                  width: 70,
                  child: Column(
                    children: [
                      Icon(
                        _getActionIcon(action),
                        size: 18,
                        color: _getActionColor(action),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _actionNames[action] ?? action,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _getActionColor(action),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 50), // مكان زر الكل
        ],
      ),
    );
  }

  /// بناء بطاقة صلاحية واحدة
  Widget _buildPermissionCard({
    required String key,
    required String label,
    required IconData icon,
    required String description,
    required Map<String, bool> permissions,
    required bool isFirstSystem,
    required Function(String action, bool value) onChanged,
    required Function(bool value) onToggleAll,
  }) {
    final allEnabled = _actions.every((a) => permissions[a] == true);
    final someEnabled =
        _actions.any((a) => permissions[a] == true) && !allEnabled;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allEnabled
              ? const Color(0xFF4CAF50).withOpacity(0.5)
              : someEnabled
                  ? const Color(0xFFFF9800).withOpacity(0.5)
                  : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // أيقونة واسم الصلاحية
          SizedBox(
            width: 200,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: allEnabled
                        ? const Color(0xFF4CAF50).withOpacity(0.1)
                        : someEnabled
                            ? const Color(0xFFFF9800).withOpacity(0.1)
                            : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: allEnabled
                        ? const Color(0xFF4CAF50)
                        : someEnabled
                            ? const Color(0xFFFF9800)
                            : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // مربعات الاختيار للإجراءات
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _actions.map((action) {
                final isEnabled = permissions[action] ?? false;
                final isAllowedByCompany =
                    _isActionEnabledForCompany(key, action, isFirstSystem);
                return SizedBox(
                  width: 70,
                  child: Transform.scale(
                    scale: 0.9,
                    child: Tooltip(
                      message: !isAllowedByCompany ? 'غير مفعل للشركة' : '',
                      child: Checkbox(
                        value: isEnabled,
                        onChanged: isAllowedByCompany
                            ? (value) => onChanged(action, value ?? false)
                            : null,
                        activeColor: _getActionColor(action),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // زر تحديد/إلغاء الكل
          SizedBox(
            width: 50,
            child: IconButton(
              onPressed: () => onToggleAll(!allEnabled),
              icon: Icon(
                allEnabled
                    ? Icons.check_box_rounded
                    : someEnabled
                        ? Icons.indeterminate_check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                color: allEnabled
                    ? const Color(0xFF4CAF50)
                    : someEnabled
                        ? const Color(0xFFFF9800)
                        : Colors.grey,
              ),
              tooltip: allEnabled ? 'إلغاء الكل' : 'تحديد الكل',
            ),
          ),
        ],
      ),
    );
  }

  /// الحصول على أيقونة الإجراء
  IconData _getActionIcon(String action) {
    switch (action) {
      case 'view':
        return Icons.visibility_rounded;
      case 'add':
        return Icons.add_circle_rounded;
      case 'edit':
        return Icons.edit_rounded;
      case 'delete':
        return Icons.delete_rounded;
      case 'export':
        return Icons.file_download_rounded;
      case 'import':
        return Icons.file_upload_rounded;
      case 'print':
        return Icons.print_rounded;
      case 'send':
        return Icons.send_rounded;
      default:
        return Icons.check_circle_rounded;
    }
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
      for (var key in _firstSystemFeatures.keys) {
        if (value && widget.employeeId != null) {
          // عند التفعيل: فقط ضمن حدود الشركة
          if (!_isFeatureEnabledForCompany(key, true)) continue;
          _firstSystemPermissionsV2[key] = {
            for (var a in _actions) a: _isActionEnabledForCompany(key, a, true)
          };
        } else {
          _firstSystemPermissionsV2[key] = {for (var a in _actions) a: value};
        }
      }
      for (var key in _secondSystemFeatures.keys) {
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
      for (var key in _firstSystemFeatures.keys) {
        if (widget.employeeId != null &&
            !_isFeatureEnabledForCompany(key, true)) continue;
        _firstSystemPermissionsV2[key] = {
          for (var a in _actions)
            a: a == 'view' && _isActionEnabledForCompany(key, a, true)
        };
      }
      for (var key in _secondSystemFeatures.keys) {
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
