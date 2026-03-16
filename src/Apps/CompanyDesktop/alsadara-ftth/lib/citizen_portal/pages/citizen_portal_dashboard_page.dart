import 'package:flutter/material.dart';
import '../models/company_model.dart';
import '../services/company_api_service.dart';

/// شاشة بوابة المواطن - تظهر فقط للشركة المرتبطة بنظام المواطن
class CitizenPortalDashboardPage extends StatefulWidget {
  final String companyId; // معرف الشركة الحالية

  const CitizenPortalDashboardPage({
    super.key,
    required this.companyId,
  });

  @override
  State<CitizenPortalDashboardPage> createState() =>
      _CitizenPortalDashboardPageState();
}

class _CitizenPortalDashboardPageState
    extends State<CitizenPortalDashboardPage> {
  bool isLoading = true;
  bool isLinkedCompany = false;
  CompanyModel? linkedCompany;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _checkIfLinkedCompany();
  }

  Future<void> _checkIfLinkedCompany() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final company = await CompanyApiService.getLinkedCompany();

      setState(() {
        linkedCompany = company;
        isLinkedCompany = company != null && company.id == widget.companyId;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('بوابة المواطن'),
          backgroundColor: Colors.teal,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _checkIfLinkedCompany,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (!isLinkedCompany) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('بوابة المواطن'),
          backgroundColor: Colors.teal,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 24),
              const Text(
                'بوابة المواطن غير متاحة',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                'هذه الشركة غير مرتبطة بنظام المواطن',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              if (linkedCompany != null)
                Text(
                  'الشركة المرتبطة حالياً: ${linkedCompany!.name}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                ),
            ],
          ),
        ),
      );
    }

    // الشركة مرتبطة - عرض لوحة التحكم
    return Scaffold(
      appBar: AppBar(
        title: const Text('بوابة المواطن'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkIfLinkedCompany,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal, Colors.teal.shade700],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people, size: 48, color: Colors.white),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'مرحباً بك في بوابة المواطن',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          linkedCompany!.name,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Statistics Cards
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                _buildStatCard(
                  'المواطنين',
                  '0', // TODO: جلب من API
                  Icons.people,
                  Colors.blue,
                ),
                _buildStatCard(
                  'الطلبات الجديدة',
                  '0', // TODO: جلب من API
                  Icons.assignment,
                  Colors.orange,
                ),
                _buildStatCard(
                  'الاشتراكات الفعالة',
                  '0', // TODO: جلب من API
                  Icons.wifi,
                  Colors.green,
                ),
                _buildStatCard(
                  'تذاكر الدعم',
                  '0', // TODO: جلب من API
                  Icons.support_agent,
                  Colors.purple,
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Quick Actions
            const Text(
              'الإجراءات السريعة',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                _buildActionCard(
                  'إدارة المواطنين',
                  Icons.people_outline,
                  Colors.blue,
                  () => _navigateToPage('citizens'),
                ),
                _buildActionCard(
                  'طلبات الاشتراك',
                  Icons.assignment_outlined,
                  Colors.orange,
                  () => _navigateToPage('requests'),
                ),
                _buildActionCard(
                  'الاشتراكات',
                  Icons.wifi,
                  Colors.green,
                  () => _navigateToPage('subscriptions'),
                ),
                _buildActionCard(
                  'الدعم الفني',
                  Icons.support_agent,
                  Colors.purple,
                  () => _navigateToPage('support'),
                ),
                _buildActionCard(
                  'طلبات المتجر',
                  Icons.shopping_cart,
                  Colors.indigo,
                  () => _navigateToPage('store-orders'),
                ),
                _buildActionCard(
                  'التقارير',
                  Icons.bar_chart,
                  Colors.teal,
                  () => _navigateToPage('reports'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: color),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToPage(String page) {
    // TODO: التنقل إلى الصفحات المختلفة
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('سيتم إضافة صفحة $page قريباً')),
    );
  }
}
