/// لوحة تحكم نظام المواطن
/// تظهر فقط للشركة المرتبطة بنظام المواطن
library;

import 'package:flutter/material.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../utils/responsive_helper.dart';
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
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: AppBar(
          title: const Text('نظام المواطن'),
          backgroundColor: SdColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
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
            CircularProgressIndicator(color: SdColors.primary),
            SizedBox(height: 16),
            Text('جاري تحميل البيانات...', style: SdText.bodySm),
          ],
        ),
      );
    }

    if (_error != null) {
      return SdEmptyState(
        title: _error!,
        icon: Icons.error_outline_rounded,
        status: SdStatus.danger,
        action: SdButton(
          label: 'إعادة المحاولة',
          icon: Icons.refresh,
          kind: SdButtonKind.secondary,
          onPressed: _loadStats,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      color: SdColors.primary,
      child: Builder(builder: (context) {
        final isMobile = context.responsive.isMobile;
        return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? 10 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان
            Container(
              padding: EdgeInsets.all(isMobile ? 12 : 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [SdColors.primaryMid, SdColors.primary],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: SdDepth.raised(
                    edge: SdColors.primaryEdge, depth: SdDepth.hero),
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
                        Text(
                          'مرحباً بك في نظام المواطن',
                          style: SdText.title.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إدارة المواطنين وطلباتهم واشتراكاتهم',
                          style: SdText.body.copyWith(
                              color: Colors.white.withAlpha((0.9 * 255).round())),
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
            const SdSectionHeader(title: 'إجراءات سريعة'),
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
            SdSectionHeader(
              title: 'أحدث الطلبات',
              trailing: TextButton.icon(
                onPressed: () => _tabController.animateTo(2),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('عرض الكل'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: SdColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SdColors.divider),
              ),
              child: const Center(
                child: Text(
                  'سيتم عرض أحدث الطلبات هنا',
                  style: SdText.bodySm,
                ),
              ),
            ),
          ],
        ),
      );
      }),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SdRaised(
      onTap: onTap,
      radius: SdRadius.sm,
      depth: SdDepth.small,
      color: color.withAlpha((0.1 * 255).round()),
      edgeColor: color.withAlpha((0.3 * 255).round()),
      glowColor: color.withAlpha((0.18 * 255).round()),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      semanticLabel: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem {
  final String title;
  final IconData icon;

  _TabItem({required this.title, required this.icon});
}
