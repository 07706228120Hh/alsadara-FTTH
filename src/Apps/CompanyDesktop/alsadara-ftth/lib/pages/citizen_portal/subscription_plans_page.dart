/// صفحة خطط الاشتراك
library;

import 'package:flutter/material.dart';
import 'models/citizen_portal_models.dart';
import 'services/citizen_portal_service.dart';

class SubscriptionPlansPage extends StatefulWidget {
  const SubscriptionPlansPage({super.key});

  @override
  State<SubscriptionPlansPage> createState() => _SubscriptionPlansPageState();
}

class _SubscriptionPlansPageState extends State<SubscriptionPlansPage> {
  final CitizenPortalService _service = CitizenPortalService.instance;

  List<SubscriptionPlanModel> _plans = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final response = await _service.getPlans();

    if (response.isSuccess && response.data != null) {
      setState(() {
        _plans = response.data!;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = response.message ?? 'فشل في تحميل الخطط';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          // شريط الأدوات
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(Icons.local_offer, color: Colors.teal.shade600),
                const SizedBox(width: 12),
                const Text(
                  'إدارة خطط الاشتراك',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadPlans,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث',
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _showPlanDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('خطة جديدة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // القائمة
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.teal),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadPlans,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_plans.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'لا توجد خطط اشتراك',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'ابدأ بإنشاء خطة جديدة',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showPlanDialog(),
              icon: const Icon(Icons.add),
              label: const Text('إنشاء خطة'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPlans,
      color: Colors.teal,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.2,
        ),
        itemCount: _plans.length,
        itemBuilder: (context, index) {
          final plan = _plans[index];
          return _buildPlanCard(plan);
        },
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlanModel plan) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.teal,
    ];
    final color = colors[plan.displayOrder % colors.length];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              color.withAlpha((0.1 * 255).round()),
              color.withAlpha((0.05 * 255).round()),
            ],
          ),
        ),
        child: Stack(
          children: [
            // شارة غير نشط
            if (!plan.isActive)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'غير نشط',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

            // القائمة المنسدلة
            Positioned(
              top: 4,
              right: 4,
              child: PopupMenuButton<String>(
                onSelected: (action) => _onPlanAction(action, plan),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit),
                        SizedBox(width: 8),
                        Text('تعديل'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: plan.isActive ? 'deactivate' : 'activate',
                    child: Row(
                      children: [
                        Icon(plan.isActive
                            ? Icons.visibility_off
                            : Icons.visibility),
                        const SizedBox(width: 8),
                        Text(plan.isActive ? 'إيقاف' : 'تفعيل'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, color: Colors.red),
                        SizedBox(width: 8),
                        Text('حذف', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // المحتوى
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_offer,
                    size: 40,
                    color: color,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    plan.name,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${plan.price.toStringAsFixed(0)} د.ع',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  Text(
                    '${plan.durationDays} يوم',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (plan.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      plan.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onPlanAction(String action, SubscriptionPlanModel plan) {
    switch (action) {
      case 'edit':
        _showPlanDialog(plan: plan);
        break;
      case 'activate':
      case 'deactivate':
        _togglePlanStatus(plan);
        break;
      case 'delete':
        _deletePlan(plan);
        break;
    }
  }

  void _showPlanDialog({SubscriptionPlanModel? plan}) {
    final isEditing = plan != null;
    final nameController = TextEditingController(text: plan?.name ?? '');
    final descController = TextEditingController(text: plan?.description ?? '');
    final priceController =
        TextEditingController(text: plan?.price.toStringAsFixed(0) ?? '');
    final daysController =
        TextEditingController(text: plan?.durationDays.toString() ?? '30');

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(isEditing ? 'تعديل الخطة' : 'خطة جديدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الخطة',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'الوصف (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(
                    labelText: 'السعر (د.ع)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: daysController,
                  decoration: const InputDecoration(
                    labelText: 'المدة (بالأيام)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'name': nameController.text.trim(),
                  'description': descController.text.trim().isEmpty
                      ? null
                      : descController.text.trim(),
                  'price': double.tryParse(priceController.text) ?? 0,
                  'durationDays': int.tryParse(daysController.text) ?? 30,
                  'isActive': true,
                };

                if (isEditing) {
                  await _service.updatePlan(plan.id, data);
                } else {
                  await _service.createPlan(data);
                }

                if (context.mounted) Navigator.pop(context);
                _loadPlans();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: Text(isEditing ? 'حفظ' : 'إنشاء'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePlanStatus(SubscriptionPlanModel plan) async {
    final data = {'isActive': !plan.isActive};
    await _service.updatePlan(plan.id, data);
    _loadPlans();
  }

  Future<void> _deletePlan(SubscriptionPlanModel plan) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف الخطة'),
          content: Text('هل تريد حذف الخطة "${plan.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await _service.deletePlan(plan.id);
      _loadPlans();
    }
  }
}
