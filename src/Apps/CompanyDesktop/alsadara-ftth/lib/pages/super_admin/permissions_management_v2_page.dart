/// 🔐 صفحة إدارة الصلاحيات V2
/// تتيح التحكم الدقيق في صلاحيات الشركات والموظفين
/// مع دعم الإجراءات المفصلة (view, add, edit, delete, export...)
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/api/api_client.dart';
import '../../services/permissions_service.dart';
import 'admin_theme.dart';

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

  // قائمة الإجراءات المتاحة
  final List<String> _actions = PermissionsService.availableActions;
  final Map<String, String> _actionNames = PermissionsService.actionNamesAr;

  // أسماء الصلاحيات بالعربي - النظام الأول
  final Map<String, Map<String, dynamic>> _firstSystemFeatures = {
    'attendance': {
      'label': 'الحضور والانصراف',
      'icon': Icons.access_time_rounded,
      'description': 'تسجيل حضور وانصراف الموظفين',
    },
    'agent': {
      'label': 'إدارة الوكلاء',
      'icon': Icons.support_agent_rounded,
      'description': 'إدارة وكلاء المبيعات والتوزيع',
    },
    'tasks': {
      'label': 'المهام',
      'icon': Icons.task_alt_rounded,
      'description': 'إدارة المهام والتكليفات',
    },
    'zones': {
      'label': 'المناطق',
      'icon': Icons.map_rounded,
      'description': 'تحديد مناطق العمل والتغطية',
    },
    'ai_search': {
      'label': 'البحث الذكي',
      'icon': Icons.auto_awesome_rounded,
      'description': 'بحث بالذكاء الاصطناعي',
    },
  };

  // أسماء الصلاحيات بالعربي - النظام الثاني
  final Map<String, Map<String, dynamic>> _secondSystemFeatures = {
    'users': {
      'label': 'إدارة المستخدمين',
      'icon': Icons.people_rounded,
      'description': 'إدارة المشتركين والعملاء',
    },
    'subscriptions': {
      'label': 'الاشتراكات',
      'icon': Icons.card_membership_rounded,
      'description': 'إدارة باقات الاشتراك',
    },
    'tasks': {
      'label': 'المهام',
      'icon': Icons.assignment_rounded,
      'description': 'إدارة مهام الصيانة والتركيب',
    },
    'zones': {
      'label': 'المناطق',
      'icon': Icons.location_on_rounded,
      'description': 'تحديد مناطق التغطية',
    },
    'accounts': {
      'label': 'الحسابات',
      'icon': Icons.account_balance_wallet_rounded,
      'description': 'إدارة الحسابات المالية',
    },
    'account_records': {
      'label': 'سجلات الحسابات',
      'icon': Icons.receipt_long_rounded,
      'description': 'عرض سجلات المعاملات',
    },
    'export': {
      'label': 'التصدير',
      'icon': Icons.file_download_rounded,
      'description': 'تصدير البيانات والتقارير',
    },
    'agents': {
      'label': 'الوكلاء',
      'icon': Icons.store_rounded,
      'description': 'إدارة نقاط البيع',
    },
    'google_sheets': {
      'label': 'Google Sheets',
      'icon': Icons.table_chart_rounded,
      'description': 'التكامل مع جداول Google',
    },
    'whatsapp': {
      'label': 'واتساب',
      'icon': Icons.chat_rounded,
      'description': 'إرسال رسائل واتساب',
    },
    'wallet_balance': {
      'label': 'رصيد المحفظة',
      'icon': Icons.account_balance_rounded,
      'description': 'عرض أرصدة المحفظة',
    },
    'expiring_soon': {
      'label': 'اشتراكات منتهية قريباً',
      'icon': Icons.warning_amber_rounded,
      'description': 'عرض الاشتراكات القريبة من الانتهاء',
    },
    'quick_search': {
      'label': 'البحث السريع',
      'icon': Icons.search_rounded,
      'description': 'البحث السريع في البيانات',
    },
    'technicians': {
      'label': 'الفنيين',
      'icon': Icons.engineering_rounded,
      'description': 'إدارة فريق الصيانة',
    },
    'transactions': {
      'label': 'المعاملات',
      'icon': Icons.swap_horiz_rounded,
      'description': 'سجل المعاملات المالية',
    },
    'notifications': {
      'label': 'الإشعارات',
      'icon': Icons.notifications_rounded,
      'description': 'إدارة الإشعارات',
    },
    'audit_logs': {
      'label': 'سجل التدقيق',
      'icon': Icons.history_rounded,
      'description': 'سجل العمليات والتغييرات',
    },
    'whatsapp_link': {
      'label': 'ربط واتساب',
      'icon': Icons.qr_code_rounded,
      'description': 'ربط حساب واتساب',
    },
    'whatsapp_settings': {
      'label': 'إعدادات واتساب',
      'icon': Icons.settings_rounded,
      'description': 'إعدادات رسائل واتساب',
    },
    'plans_bundles': {
      'label': 'الباقات والعروض',
      'icon': Icons.local_offer_rounded,
      'description': 'إدارة باقات الاشتراك',
    },
    'whatsapp_business_api': {
      'label': 'WhatsApp Business API',
      'icon': Icons.business_rounded,
      'description': 'إعدادات API الأعمال',
    },
    'whatsapp_bulk_sender': {
      'label': 'الإرسال الجماعي',
      'icon': Icons.send_rounded,
      'description': 'إرسال رسائل جماعية',
    },
    'whatsapp_conversations_fab': {
      'label': 'محادثات واتساب',
      'icon': Icons.forum_rounded,
      'description': 'عرض زر المحادثات',
    },
    'local_storage': {
      'label': 'التخزين المحلي',
      'icon': Icons.storage_rounded,
      'description': 'التخزين المحلي للمشتركين',
    },
    'local_storage_import': {
      'label': 'استيراد البيانات',
      'icon': Icons.upload_file_rounded,
      'description': 'استيراد من التخزين المحلي',
    },
  };

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
      backgroundColor: AdminTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: AdminTheme.surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AdminTheme.textPrimary),
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
                      color: AdminTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'نظام الصلاحيات المفصل V2',
                    style: TextStyle(
                      color: AdminTheme.textMuted,
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
            color: AdminTheme.textMuted,
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
          unselectedLabelColor: AdminTheme.textMuted,
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
    final featuresList = features.entries.toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // شريط الإجراءات
          _buildActionsHeader(),
          const SizedBox(height: 12),
          // قائمة الصلاحيات
          Expanded(
            child: ListView.builder(
              itemCount: featuresList.length,
              itemBuilder: (context, index) {
                final entry = featuresList[index];
                final key = entry.key;
                final feature = entry.value;
                final featurePermissions =
                    permissions[key] ?? {for (var a in _actions) a: false};

                return _buildPermissionCard(
                  key: key,
                  label: feature['label'] as String,
                  icon: feature['icon'] as IconData,
                  description: feature['description'] as String,
                  permissions: featurePermissions,
                  onChanged: (action, value) {
                    setState(() {
                      permissions[key] ??= {};
                      permissions[key]![action] = value;
                    });
                  },
                  onToggleAll: (value) {
                    setState(() {
                      permissions[key] = {for (var a in _actions) a: value};
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
        color: const Color(0xFF9C27B0).withOpacity(0.05),
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
            color: Colors.black.withOpacity(0.04),
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
                return SizedBox(
                  width: 70,
                  child: Transform.scale(
                    scale: 0.9,
                    child: Checkbox(
                      value: isEnabled,
                      onChanged: (value) => onChanged(action, value ?? false),
                      activeColor: _getActionColor(action),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
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
        _firstSystemPermissionsV2[key] = {for (var a in _actions) a: value};
      }
      for (var key in _secondSystemFeatures.keys) {
        _secondSystemPermissionsV2[key] = {for (var a in _actions) a: value};
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
        _firstSystemPermissionsV2[key] = {
          for (var a in _actions) a: a == 'view'
        };
      }
      for (var key in _secondSystemFeatures.keys) {
        _secondSystemPermissionsV2[key] = {
          for (var a in _actions) a: a == 'view'
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
