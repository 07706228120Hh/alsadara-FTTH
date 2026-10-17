/// صفحة إدارة ميزات/صلاحيات الشركة
/// يمكن لمدير النظام تفعيل أو تعطيل الميزات لكل شركة
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/tenant.dart';
import '../../permissions/permission_registry.dart';
import '../../frontend/frontend.dart';

class TenantFeaturesPage extends StatefulWidget {
  final Tenant tenant;

  const TenantFeaturesPage({super.key, required this.tenant});

  @override
  State<TenantFeaturesPage> createState() => _TenantFeaturesPageState();
}

class _TenantFeaturesPageState extends State<TenantFeaturesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, bool> _firstSystemFeatures;
  late Map<String, bool> _secondSystemFeatures;
  bool _isLoading = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initFeatures();
  }

  void _initFeatures() {
    // تهيئة ميزات النظام الأول من PermissionRegistry (مفاتيح رئيسية فقط)
    _firstSystemFeatures = {};
    for (var key in PermissionRegistry.firstSystemKeys) {
      _firstSystemFeatures[key] =
          widget.tenant.enabledFirstSystemFeatures[key] ?? true;
    }

    // تهيئة ميزات النظام الثاني من PermissionRegistry (مفاتيح رئيسية فقط)
    _secondSystemFeatures = {};
    for (var key in PermissionRegistry.secondSystemKeys) {
      _secondSystemFeatures[key] =
          widget.tenant.enabledSecondSystemFeatures[key] ?? true;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('tenants')
          .doc(widget.tenant.id)
          .update({
        'enabledFirstSystemFeatures': _firstSystemFeatures,
        'enabledSecondSystemFeatures': _secondSystemFeatures,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ التغييرات بنجاح',
                style: SdText.body.copyWith(color: Colors.white)),
            backgroundColor: SdColors.success,
          ),
        );
        setState(() => _hasChanges = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ',
                style: SdText.body.copyWith(color: Colors.white)),
            backgroundColor: SdColors.danger,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  void _enableAll(bool isFirstSystem) {
    setState(() {
      if (isFirstSystem) {
        _firstSystemFeatures.updateAll((key, value) => true);
      } else {
        _secondSystemFeatures.updateAll((key, value) => true);
      }
      _hasChanges = true;
    });
  }

  void _disableAll(bool isFirstSystem) {
    setState(() {
      if (isFirstSystem) {
        _firstSystemFeatures.updateAll((key, value) => false);
      } else {
        _secondSystemFeatures.updateAll((key, value) => false);
      }
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'إدارة ميزات الشركة',
          subtitle: widget.tenant.name,
          actions: [
            if (_hasChanges)
              SdAppBarAction(
                icon: Icons.save,
                label: 'حفظ التغييرات',
                onPressed: _isLoading ? null : _saveChanges,
              ),
          ],
          bottom: SdTabBar(
            controller: _tabController,
            height: 72,
            tabs: const [
              Tab(
                icon: Icon(Icons.looks_one),
                text: 'النظام الأول',
              ),
              Tab(
                icon: Icon(Icons.looks_two),
                text: 'النظام الثاني',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildFeaturesList(_firstSystemFeatures, true),
            _buildFeaturesList(_secondSystemFeatures, false),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesList(Map<String, bool> features, bool isFirstSystem) {
    final featureNames = _getFeatureNames(isFirstSystem);

    return Column(
      children: [
        // أزرار تفعيل/تعطيل الكل
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: SdColors.surfaceAlt,
            border: Border(
              bottom: BorderSide(color: SdColors.divider),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: SdButton(
                  label: 'تفعيل الكل',
                  icon: Icons.check_circle,
                  expand: true,
                  onPressed: () => _enableAll(isFirstSystem),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SdButton(
                  label: 'تعطيل الكل',
                  icon: Icons.cancel,
                  kind: SdButtonKind.danger,
                  expand: true,
                  onPressed: () => _disableAll(isFirstSystem),
                ),
              ),
            ],
          ),
        ),
        // عداد الميزات
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: SdColors.primaryTint,
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: SdColors.muted),
              const SizedBox(width: 8),
              Text(
                'الميزات المفعلة: ${features.values.where((v) => v).length} من ${features.length}',
                style: SdText.bodySm,
              ),
            ],
          ),
        ),
        // قائمة الميزات
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: features.length,
            itemBuilder: (context, index) {
              final key = features.keys.elementAt(index);
              final value = features[key] ?? false;
              final name = featureNames[key] ?? key;
              final icon = _getFeatureIcon(key);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SdCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: value,
                    onChanged: (newValue) {
                      setState(() {
                        features[key] = newValue;
                        _hasChanges = true;
                      });
                    },
                    title: Row(
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: value ? SdColors.success : SdColors.faint,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          name,
                          style: SdText.label.copyWith(
                            color: value ? SdColors.ink : SdColors.muted,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      value ? 'مفعل للشركة' : 'معطل للشركة',
                      style: SdText.caption.copyWith(
                        color: value ? SdColors.success : SdColors.danger,
                      ),
                    ),
                    activeColor: SdColors.success,
                  ),
                ),
              );
            },
          ),
        ),
        // تحذير
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SdColors.warningTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SdColors.warningTintEdge),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: SdColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'الميزات المعطلة لن تظهر لأي مستخدم في الشركة، حتى المدراء',
                  style: SdText.caption.copyWith(color: SdColors.warningText),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, String> _getFeatureNames(bool isFirstSystem) {
    if (isFirstSystem) {
      return {
        'attendance': 'الحضور والانصراف',
        'agent': 'الوكيل',
        'tasks': 'المهام',
        'zones': 'المناطق',
        'ai_search': 'البحث الذكي',
      };
    } else {
      return {
        'users': 'إدارة المستخدمين',
        'subscriptions': 'الاشتراكات',
        'tasks': 'المهام',
        'zones': 'المناطق',
        'accounts': 'الحسابات',
        'account_records': 'سجلات الحسابات',
        'export': 'التصدير',
        'agents': 'الوكلاء',
        'google_sheets': 'حفظ في الخادم',
        'whatsapp': 'واتساب',
        'wallet_balance': 'رصيد المحفظة',
        'expiring_soon': 'تنتهي قريباً',
        'quick_search': 'البحث السريع',
        'technicians': 'الفنيين',
        'transactions': 'المعاملات',
        'notifications': 'الإشعارات',
        'audit_logs': 'سجلات التدقيق',
        'whatsapp_link': 'رابط واتساب',
        'whatsapp_settings': 'إعدادات واتساب',
        'plans_bundles': 'الباقات والخطط',
        'whatsapp_business_api': 'واتساب بزنس API',
        'whatsapp_bulk_sender': 'إرسال جماعي واتساب',
        'whatsapp_conversations_fab': 'محادثات واتساب',
        'local_storage': 'التخزين المحلي',
        'local_storage_import': 'استيراد التخزين المحلي',
      };
    }
  }

  IconData _getFeatureIcon(String key) {
    final icons = {
      'attendance': Icons.access_time,
      'agent': Icons.support_agent,
      'tasks': Icons.task_alt,
      'zones': Icons.map,
      'ai_search': Icons.search,
      'users': Icons.people,
      'subscriptions': Icons.card_membership,
      'accounts': Icons.account_balance,
      'account_records': Icons.receipt_long,
      'export': Icons.file_download,
      'agents': Icons.support_agent,
      'google_sheets': Icons.cloud_upload,
      'whatsapp': Icons.chat,
      'wallet_balance': Icons.account_balance_wallet,
      'expiring_soon': Icons.timer,
      'quick_search': Icons.search,
      'technicians': Icons.engineering,
      'transactions': Icons.swap_horiz,
      'notifications': Icons.notifications,
      'audit_logs': Icons.history,
      'whatsapp_link': Icons.link,
      'whatsapp_settings': Icons.settings,
      'plans_bundles': Icons.inventory,
      'whatsapp_business_api': Icons.api,
      'whatsapp_bulk_sender': Icons.send,
      'whatsapp_conversations_fab': Icons.forum,
      'local_storage': Icons.storage,
      'local_storage_import': Icons.upload,
    };
    return icons[key] ?? Icons.settings;
  }
}
