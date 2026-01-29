/// لوحة تحكم نظام المواطن
/// تظهر فقط للشركة المرتبطة بنظام المواطن
library;

import 'package:flutter/material.dart';
import 'models/citizen_portal_models.dart';
import 'services/citizen_portal_service.dart';
import 'widgets/citizen_stats_card.dart';
import 'citizens_list_page.dart';
import 'citizen_requests_page.dart';
import 'citizen_subscriptions_page.dart';
import 'citizen_payments_page.dart';
import 'subscription_plans_page.dart';

class CitizenPortalDashboard extends StatefulWidget {
  const CitizenPortalDashboard({super.key});

  @override
  State<CitizenPortalDashboard> createState() => _CitizenPortalDashboardState();
}

class _CitizenPortalDashboardState extends State<CitizenPortalDashboard>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CitizenPortalService _service = CitizenPortalService.instance;

  CitizenPortalStats? _stats;
  bool _isLoading = true;
  String? _error;

  final List<_TabItem> _tabs = [
    _TabItem(
      title: 'الرئيسية',
      icon: Icons.dashboard_rounded,
    ),
    _TabItem(
      title: 'المواطنين',
      icon: Icons.people_rounded,
    ),
    _TabItem(
      title: 'الطلبات',
      icon: Icons.list_alt_rounded,
    ),
    _TabItem(
      title: 'الاشتراكات',
      icon: Icons.card_membership_rounded,
    ),
    _TabItem(
      title: 'المدفوعات',
      icon: Icons.payments_rounded,
    ),
    _TabItem(
      title: 'خطط الاشتراك',
      icon: Icons.local_offer_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final response = await _service.getStats();
    if (response.isSuccess && response.data != null) {
      setState(() {
        _stats = response.data;
        _isLoading = false;
      });
    } else {
      setState(() {
        _error = response.message ?? 'فشل في تحميل الإحصائيات';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Row(
            children: [
              Icon(Icons.people_alt_rounded, size: 28),
              SizedBox(width: 12),
              Text(
                'نظام المواطن',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: _tabs
                .map((tab) => Tab(
                      child: Row(
                        children: [
                          Icon(tab.icon, size: 20),
                          const SizedBox(width: 8),
                          Text(tab.title),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildDashboardTab(),
            const CitizensListPage(),
            const CitizenRequestsPage(),
            const CitizenSubscriptionsPage(),
            const CitizenPaymentsPage(),
            const SubscriptionPlansPage(),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.teal),
            SizedBox(height: 16),
            Text('جاري تحميل البيانات...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadStats,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: Colors.teal,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade400, Colors.teal.shade600],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal.withAlpha((0.3 * 255).round()),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha((0.2 * 255).round()),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.people_alt_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'مرحباً بك في نظام المواطن',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إدارة المواطنين وطلباتهم واشتراكاتهم',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withAlpha((0.9 * 255).round()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // بطاقات الإحصائيات
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                CitizenStatsCard(
                  title: 'إجمالي المواطنين',
                  value: '${_stats?.totalCitizens ?? 0}',
                  subtitle: '${_stats?.activeCitizens ?? 0} نشط',
                  icon: Icons.people_rounded,
                  color: Colors.blue,
                  onTap: () => _tabController.animateTo(1),
                ),
                CitizenStatsCard(
                  title: 'الطلبات الجديدة',
                  value: '${_stats?.pendingRequests ?? 0}',
                  subtitle: 'من ${_stats?.totalRequests ?? 0} طلب',
                  icon: Icons.pending_actions_rounded,
                  color: Colors.orange,
                  onTap: () => _tabController.animateTo(2),
                ),
                CitizenStatsCard(
                  title: 'الاشتراكات النشطة',
                  value: '${_stats?.activeSubscriptions ?? 0}',
                  subtitle: 'اشتراك فعال',
                  icon: Icons.card_membership_rounded,
                  color: Colors.purple,
                  onTap: () => _tabController.animateTo(3),
                ),
                CitizenStatsCard(
                  title: 'الإيرادات الشهرية',
                  value:
                      '${(_stats?.monthlyRevenue ?? 0).toStringAsFixed(0)} د.ع',
                  subtitle:
                      'إجمالي: ${(_stats?.totalRevenue ?? 0).toStringAsFixed(0)} د.ع',
                  icon: Icons.trending_up_rounded,
                  color: Colors.green,
                  onTap: () => _tabController.animateTo(4),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // روابط سريعة
            const Text(
              'إجراءات سريعة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildQuickAction(
                  icon: Icons.person_add_rounded,
                  label: 'إضافة مواطن',
                  color: Colors.blue,
                  onTap: () {
                    // TODO: فتح نافذة إضافة مواطن
                  },
                ),
                _buildQuickAction(
                  icon: Icons.add_task_rounded,
                  label: 'طلب جديد',
                  color: Colors.orange,
                  onTap: () {
                    // TODO: فتح نافذة إضافة طلب
                  },
                ),
                _buildQuickAction(
                  icon: Icons.card_giftcard_rounded,
                  label: 'اشتراك جديد',
                  color: Colors.purple,
                  onTap: () {
                    // TODO: فتح نافذة إضافة اشتراك
                  },
                ),
                _buildQuickAction(
                  icon: Icons.local_offer_rounded,
                  label: 'إدارة الخطط',
                  color: Colors.teal,
                  onTap: () => _tabController.animateTo(5),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // أحدث الطلبات
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'أحدث الطلبات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _tabController.animateTo(2),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('عرض الكل'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'سيتم عرض أحدث الطلبات هنا',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: color.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withAlpha((0.3 * 255).round()),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String title;
  final IconData icon;

  _TabItem({required this.title, required this.icon});
}
