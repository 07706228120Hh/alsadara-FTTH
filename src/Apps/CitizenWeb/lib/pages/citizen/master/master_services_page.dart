import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة خدمات الماستر كارد
class MasterServicesPage extends StatelessWidget {
  const MasterServicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = [
      {
        'title': 'شحن رصيد',
        'description': 'شحن رصيد بطاقتك الحالية',
        'icon': Icons.account_balance_wallet,
        'color': AppTheme.masterCardColor,
        'route': '/citizen/master/recharge',
      },
      {
        'title': 'طلب بطاقة جديدة',
        'description': 'احصل على بطاقة ماستر جديدة',
        'icon': Icons.add_card,
        'color': Colors.green,
        'route': '/citizen/master/new-card',
      },
      {
        'title': 'توصيل البطاقة',
        'description': 'تتبع طلب توصيل بطاقتك',
        'icon': Icons.local_shipping,
        'color': Colors.orange,
        'route': '/citizen/master/delivery',
      },
      {
        'title': 'كشف حساب',
        'description': 'عرض سجل المعاملات والأرصدة',
        'icon': Icons.receipt_long,
        'color': Colors.purple,
        'route': '/citizen/master/statement',
      },
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('خدمات الماستر'),
          backgroundColor: AppTheme.masterCardColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/home'),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // بطاقتي
              _buildMyCardSection(),

              const SizedBox(height: 24),

              // الخدمات
              const Text(
                'الخدمات المتاحة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),

              ...services.map(
                (service) => _buildServiceCard(
                  context,
                  title: service['title'] as String,
                  description: service['description'] as String,
                  icon: service['icon'] as IconData,
                  color: service['color'] as Color,
                  route: service['route'] as String,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyCardSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.masterCardColor,
            AppTheme.masterCardColor.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppTheme.masterCardColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'بطاقتي',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.greenAccent,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'نشطة',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '**** **** **** 4532',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الرصيد المتاح',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '2,450.00 د.ع',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.credit_card,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(
    BuildContext context, {
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String route,
  }) {
    return GestureDetector(
      onTap: () => context.go(route),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppTheme.textGrey,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: AppTheme.textGrey,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
