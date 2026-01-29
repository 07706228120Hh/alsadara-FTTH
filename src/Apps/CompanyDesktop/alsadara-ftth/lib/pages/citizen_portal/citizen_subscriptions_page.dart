/// صفحة اشتراكات المواطنين
library;

import 'package:flutter/material.dart';
import 'models/citizen_portal_models.dart';
import 'services/citizen_portal_service.dart';

class CitizenSubscriptionsPage extends StatefulWidget {
  const CitizenSubscriptionsPage({super.key});

  @override
  State<CitizenSubscriptionsPage> createState() =>
      _CitizenSubscriptionsPageState();
}

class _CitizenSubscriptionsPageState extends State<CitizenSubscriptionsPage> {
  final CitizenPortalService _service = CitizenPortalService.instance;

  List<CitizenSubscriptionModel> _subscriptions = [];
  bool _isLoading = true;
  String? _error;
  bool? _filterActive;

  @override
  void initState() {
    super.initState();
    _loadSubscriptions();
  }

  Future<void> _loadSubscriptions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final response = await _service.getSubscriptions(
      pageSize: 100,
      isActive: _filterActive,
    );

    if (response.isSuccess && response.data != null) {
      setState(() {
        _subscriptions = response.data!;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = response.message ?? 'فشل في تحميل الاشتراكات';
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
          // شريط الفلترة
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
                // فلتر الحالة
                const Text('الحالة: '),
                const SizedBox(width: 8),
                DropdownButton<bool?>(
                  value: _filterActive,
                  hint: const Text('جميع الاشتراكات'),
                  items: const [
                    DropdownMenuItem(
                        value: null, child: Text('جميع الاشتراكات')),
                    DropdownMenuItem(value: true, child: Text('نشط فقط')),
                    DropdownMenuItem(value: false, child: Text('منتهي')),
                  ],
                  onChanged: (value) {
                    setState(() => _filterActive = value);
                    _loadSubscriptions();
                  },
                ),

                const Spacer(),

                // إحصائيات
                _buildQuickStat(
                  'نشط',
                  _subscriptions
                      .where((s) => s.isActive && !s.isExpired)
                      .length,
                  Colors.green,
                ),
                const SizedBox(width: 8),
                _buildQuickStat(
                  'ينتهي قريباً',
                  _subscriptions.where((s) => s.isExpiringSoon).length,
                  Colors.orange,
                ),
                const SizedBox(width: 8),
                _buildQuickStat(
                  'منتهي',
                  _subscriptions.where((s) => s.isExpired).length,
                  Colors.red,
                ),

                const SizedBox(width: 16),

                // زر التحديث
                IconButton(
                  onPressed: _loadSubscriptions,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث',
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

  Widget _buildQuickStat(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
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
              onPressed: _loadSubscriptions,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_subscriptions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.card_membership_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'لا توجد اشتراكات',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSubscriptions,
      color: Colors.teal,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _subscriptions.length,
        itemBuilder: (context, index) {
          final sub = _subscriptions[index];
          return _buildSubscriptionCard(sub);
        },
      ),
    );
  }

  Widget _buildSubscriptionCard(CitizenSubscriptionModel sub) {
    final color = sub.isExpired
        ? Colors.red
        : sub.isExpiringSoon
            ? Colors.orange
            : Colors.green;

    final statusText = sub.isExpired
        ? 'منتهي'
        : sub.isExpiringSoon
            ? 'ينتهي قريباً'
            : 'نشط';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: color.withAlpha((0.3 * 255).round()),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // أيقونة الحالة
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withAlpha((0.15 * 255).round()),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    sub.isExpired
                        ? Icons.event_busy
                        : sub.isExpiringSoon
                            ? Icons.warning
                            : Icons.event_available,
                    color: color,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),

                // المعلومات
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              sub.planName ?? 'اشتراك',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withAlpha((0.15 * 255).round()),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.person,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            sub.citizenName ?? 'غير محدد',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // التفاصيل
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDetailItem(
                  Icons.monetization_on,
                  'السعر',
                  '${sub.price.toStringAsFixed(0)} د.ع',
                ),
                _buildDetailItem(
                  Icons.calendar_today,
                  'البداية',
                  _formatDate(sub.startDate),
                ),
                _buildDetailItem(
                  Icons.event,
                  'النهاية',
                  _formatDate(sub.endDate),
                ),
                _buildDetailItem(
                  Icons.timer,
                  'المتبقي',
                  sub.isExpired ? 'منتهي' : '${sub.daysRemaining} يوم',
                ),
              ],
            ),

            // أزرار الإجراءات
            if (!sub.isExpired || sub.isExpiringSoon) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (sub.isActive && !sub.isExpired)
                    TextButton.icon(
                      onPressed: () => _cancelSubscription(sub),
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text('إلغاء'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _renewSubscription(sub),
                    icon: const Icon(Icons.autorenew, size: 18),
                    label: const Text('تجديد'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Future<void> _renewSubscription(CitizenSubscriptionModel sub) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تجديد الاشتراك'),
          content: Text(
              'هل تريد تجديد اشتراك "${sub.citizenName}" في "${sub.planName}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: const Text('تجديد'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final response = await _service.renewSubscription(sub.id);
      if (response.isSuccess) {
        _loadSubscriptions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تجديد الاشتراك بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  Future<void> _cancelSubscription(CitizenSubscriptionModel sub) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إلغاء الاشتراك'),
          content: Text('هل تريد إلغاء اشتراك "${sub.citizenName}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('لا'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('نعم، إلغاء'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final response = await _service.cancelSubscription(sub.id);
      if (response.isSuccess) {
        _loadSubscriptions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إلغاء الاشتراك'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
