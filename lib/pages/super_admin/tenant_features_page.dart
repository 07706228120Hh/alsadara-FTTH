/// صفحة إدارة ميزات/صلاحيات الشركة
/// يمكن لمدير النظام تفعيل أو تعطيل الميزات لكل شركة
library;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/tenant.dart';
import '../../models/tenant_user.dart';

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
    // تهيئة صلاحيات النظام الأول
    _firstSystemFeatures = {};
    for (var key in defaultFirstSystemPermissions.keys) {
      _firstSystemFeatures[key] =
          widget.tenant.enabledFirstSystemFeatures[key] ?? true;
    }

    // تهيئة صلاحيات النظام الثاني
    _secondSystemFeatures = {};
    for (var key in defaultSecondSystemPermissions.keys) {
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
            content: Text(
              'تم حفظ التغييرات بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _hasChanges = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'حدث خطأ: $e',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red,
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
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'إدارة ميزات الشركة',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              widget.tenant.name,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1a237e),
        foregroundColor: Colors.white,
        actions: [
          if (_hasChanges)
            _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.save),
                    tooltip: 'حفظ التغييرات',
                    onPressed: _saveChanges,
                  ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E5FF),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(
              icon: const Icon(Icons.looks_one),
              text: 'النظام الأول',
            ),
            Tab(
              icon: const Icon(Icons.looks_two),
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
    );
  }

  Widget _buildFeaturesList(Map<String, bool> features, bool isFirstSystem) {
    final featureNames = _getFeatureNames(isFirstSystem);

    return Column(
      children: [
        // أزرار تفعيل/تعطيل الكل
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _enableAll(isFirstSystem),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: Text('تفعيل الكل', style: GoogleFonts.cairo()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _disableAll(isFirstSystem),
                  icon: const Icon(Icons.cancel, size: 18),
                  label: Text('تعطيل الكل', style: GoogleFonts.cairo()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        // عداد الميزات
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF1a237e).withOpacity(0.1),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                'الميزات المفعلة: ${features.values.where((v) => v).length} من ${features.length}',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
        // قائمة الميزات
        Expanded(
          child: ListView.builder(
            itemCount: features.length,
            itemBuilder: (context, index) {
              final key = features.keys.elementAt(index);
              final value = features[key] ?? false;
              final name = featureNames[key] ?? key;
              final icon = _getFeatureIcon(key);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: SwitchListTile(
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
                        color: value ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        name,
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w500,
                          color: value ? Colors.black : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    value ? 'مفعل للشركة' : 'معطل للشركة',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: value ? Colors.green : Colors.red,
                    ),
                  ),
                  activeColor: Colors.green,
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
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'الميزات المعطلة لن تظهر لأي مستخدم في الشركة، حتى المدراء',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
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
        'google_sheets': 'جوجل شيتس',
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
      'google_sheets': Icons.table_chart,
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
