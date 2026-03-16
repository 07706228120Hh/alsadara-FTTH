/// صفحة إدارة باقات الإنترنت - مدير النظام
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/sadara_api_service.dart';
import '../../theme/energy_dashboard_theme.dart';

class PlansManagementPage extends StatefulWidget {
  const PlansManagementPage({super.key});

  @override
  State<PlansManagementPage> createState() => _PlansManagementPageState();
}

class _PlansManagementPageState extends State<PlansManagementPage> {
  final SadaraApiService _api = SadaraApiService.instance;
  List<Map<String, dynamic>> _plans = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final plans = await _api.getPlans();
      if (!mounted) return;
      setState(() {
        _plans = plans.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'حدث خطأ';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: EnergyDashboardTheme.bgPrimary,
        child: Column(
          children: [
            _buildToolbar(),
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        border: Border(
          bottom: BorderSide(
            color: EnergyDashboardTheme.bgCardHover,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_rounded, color: EnergyDashboardTheme.neonBlue),
          const SizedBox(width: 12),
          const Text(
            'إدارة باقات الإنترنت والأسعار',
            style: TextStyle(
              color: EnergyDashboardTheme.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadPlans,
            icon: Icon(Icons.refresh, color: EnergyDashboardTheme.textMuted),
            tooltip: 'تحديث',
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _showPlanDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('باقة جديدة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: EnergyDashboardTheme.neonBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: EnergyDashboardTheme.neonBlue),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: EnergyDashboardTheme.textMuted)),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: _loadPlans, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    if (_plans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off,
                size: 64, color: EnergyDashboardTheme.textMuted),
            const SizedBox(height: 16),
            const Text('لا توجد باقات',
                style: TextStyle(
                    color: EnergyDashboardTheme.textMuted, fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _showPlanDialog(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة أول باقة'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 380,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        itemCount: _plans.length,
        itemBuilder: (context, index) => _buildPlanCard(_plans[index]),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final isActive = plan['IsActive'] ?? plan['isActive'] ?? true;
    final isFeatured = plan['IsFeatured'] ?? plan['isFeatured'] ?? false;
    final monthlyPrice =
        (plan['MonthlyPrice'] ?? plan['monthlyPrice'] ?? 0).toDouble();
    final installationFee =
        (plan['InstallationFee'] ?? plan['installationFee'] ?? 0).toDouble();
    final speedMbps = plan['SpeedMbps'] ?? plan['speedMbps'];
    final nameAr = plan['NameAr'] ?? plan['nameAr'] ?? plan['Name'] ?? '';
    final badge = plan['Badge'] ?? plan['badge'];
    final colorHex = plan['Color'] ?? plan['color'] ?? '#3B82F6';

    Color planColor;
    try {
      planColor = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (_) {
      planColor = EnergyDashboardTheme.neonBlue;
    }

    return Container(
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? planColor.withOpacity(0.3)
              : EnergyDashboardTheme.bgCardHover,
          width: isFeatured ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: planColor.withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('معطلة',
                                style:
                                    TextStyle(color: Colors.red, fontSize: 11)),
                          ),
                        if (badge != null && badge.isNotEmpty) ...[
                          if (!isActive) const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: planColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(badge,
                                style: TextStyle(
                                    color: planColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert,
                          color: EnergyDashboardTheme.textMuted, size: 20),
                      onSelected: (action) {
                        if (action == 'edit') _showPlanDialog(plan: plan);
                        if (action == 'delete') _deletePlan(plan);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit', child: Text('تعديل')),
                        const PopupMenuItem(
                            value: 'delete',
                            child: Text('حذف',
                                style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Icon(Icons.wifi, size: 36, color: planColor),
                const SizedBox(height: 8),
                Text(
                  nameAr,
                  style: TextStyle(
                    color: EnergyDashboardTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (speedMbps != null)
                  Text(
                    '$speedMbps Mbps',
                    style: TextStyle(
                        color: planColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),

          // Pricing
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildPriceRow('السعر الشهري', monthlyPrice, planColor),
                  const SizedBox(height: 8),
                  _buildPriceRow('رسوم التركيب', installationFee,
                      EnergyDashboardTheme.textMuted),
                  const Divider(height: 20),
                  _buildPriceRow(
                      'المجموع', monthlyPrice + installationFee, Colors.green,
                      isBold: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double amount, Color color,
      {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                TextStyle(color: EnergyDashboardTheme.textMuted, fontSize: 13)),
        Text(
          '${amount.toStringAsFixed(0)} د.ع',
          style: TextStyle(
            color: color,
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final id = (plan['Id'] ?? plan['id'] ?? '').toString();
    final nameAr = plan['NameAr'] ?? plan['nameAr'] ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الباقة'),
        content: Text('هل أنت متأكد من حذف باقة "$nameAr"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.deletePlan(id);
        _loadPlans();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم حذف الباقة'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showPlanDialog({Map<String, dynamic>? plan}) {
    final isEdit = plan != null;
    final nameArCtrl =
        TextEditingController(text: plan?['NameAr'] ?? plan?['nameAr'] ?? '');
    final nameCtrl =
        TextEditingController(text: plan?['Name'] ?? plan?['name'] ?? '');
    final descCtrl = TextEditingController(
        text: plan?['Description'] ?? plan?['description'] ?? '');
    final speedCtrl = TextEditingController(
        text: (plan?['SpeedMbps'] ?? plan?['speedMbps'] ?? '').toString());
    final monthlyCtrl = TextEditingController(
        text:
            (plan?['MonthlyPrice'] ?? plan?['monthlyPrice'] ?? '').toString());
    final yearlyCtrl = TextEditingController(
        text: (plan?['YearlyPrice'] ?? plan?['yearlyPrice'] ?? '').toString());
    final installCtrl = TextEditingController(
        text: (plan?['InstallationFee'] ?? plan?['installationFee'] ?? 0)
            .toString());
    final sortCtrl = TextEditingController(
        text: (plan?['SortOrder'] ?? plan?['sortOrder'] ?? 0).toString());
    final colorCtrl = TextEditingController(
        text: plan?['Color'] ?? plan?['color'] ?? '#3B82F6');
    final badgeCtrl =
        TextEditingController(text: plan?['Badge'] ?? plan?['badge'] ?? '');
    bool isActive = plan?['IsActive'] ?? plan?['isActive'] ?? true;
    bool isFeatured = plan?['IsFeatured'] ?? plan?['isFeatured'] ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(isEdit ? 'تعديل الباقة' : 'إضافة باقة جديدة'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: _dialogField('الاسم بالعربي *', nameArCtrl)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _dialogField('الاسم بالإنجليزي', nameCtrl)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _dialogField('الوصف', descCtrl, maxLines: 2),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                            child: _dialogField('السرعة (Mbps)', speedCtrl,
                                isNumber: true)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _dialogField('الترتيب', sortCtrl,
                                isNumber: true)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('الأسعار (د.ع)',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                  child: _dialogField(
                                      'السعر الشهري *', monthlyCtrl,
                                      isNumber: true)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: _dialogField(
                                      'السعر السنوي', yearlyCtrl,
                                      isNumber: true)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _dialogField('رسوم التركيب', installCtrl,
                              isNumber: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dialogField('اللون (HEX)', colorCtrl)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _dialogField('الشارة (مثل VIP)', badgeCtrl)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: CheckboxListTile(
                            title: const Text('نشطة'),
                            value: isActive,
                            onChanged: (v) =>
                                setDialogState(() => isActive = v ?? true),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        Expanded(
                          child: CheckboxListTile(
                            title: const Text('مميزة'),
                            value: isFeatured,
                            onChanged: (v) =>
                                setDialogState(() => isFeatured = v ?? false),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameArCtrl.text.isEmpty || monthlyCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('يرجى ملء الحقول المطلوبة'),
                          backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  final data = {
                    'Name': nameCtrl.text.isNotEmpty
                        ? nameCtrl.text
                        : nameArCtrl.text,
                    'NameAr': nameArCtrl.text,
                    'Description': descCtrl.text,
                    'SpeedMbps': int.tryParse(speedCtrl.text) ?? 0,
                    'MonthlyPrice': double.tryParse(monthlyCtrl.text) ?? 0,
                    'YearlyPrice': double.tryParse(yearlyCtrl.text),
                    'InstallationFee': double.tryParse(installCtrl.text) ?? 0,
                    'DurationMonths': 1,
                    'IsActive': isActive,
                    'IsFeatured': isFeatured,
                    'SortOrder': int.tryParse(sortCtrl.text) ?? 0,
                    'Color': colorCtrl.text,
                    'Badge': badgeCtrl.text.isNotEmpty ? badgeCtrl.text : null,
                  };

                  try {
                    if (isEdit) {
                      final id = (plan['Id'] ?? plan['id']).toString();
                      await _api.updatePlan(id, data);
                    } else {
                      await _api.createPlan(data);
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadPlans();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              isEdit ? 'تم تحديث الباقة' : 'تم إضافة الباقة'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('خطأ'),
                            backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: EnergyDashboardTheme.neonBlue,
                  foregroundColor: Colors.white,
                ),
                child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dialogField(String label, TextEditingController ctrl,
      {bool isNumber = false, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
          : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
