import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة ترقية الباقة
class UpgradePage extends StatefulWidget {
  const UpgradePage({super.key});

  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

class _UpgradePageState extends State<UpgradePage> {
  String? _selectedPlan;
  bool _isLoading = false;

  // الباقة الحالية
  final Map<String, dynamic> _currentPlan = {
    'name': 'باقة 100 ميجا',
    'speed': 100,
    'price': 150,
  };

  // الباقات المتاحة
  final List<Map<String, dynamic>> _availablePlans = [
    {
      'id': '200mb',
      'name': 'باقة 200 ميجا',
      'speed': 200,
      'price': 200,
      'features': ['سرعة أعلى', 'أولوية في الدعم', 'راوتر محسّن'],
      'popular': false,
    },
    {
      'id': '500mb',
      'name': 'باقة 500 ميجا',
      'speed': 500,
      'price': 300,
      'features': ['سرعة فائقة', 'دعم 24/7', 'راوتر متطور', 'IP ثابت'],
      'popular': true,
    },
    {
      'id': '1gb',
      'name': 'باقة 1 جيجا',
      'speed': 1000,
      'price': 450,
      'features': [
        'أقصى سرعة',
        'دعم VIP',
        'راوتر احترافي',
        'IP ثابت',
        'أولوية مطلقة',
      ],
      'popular': false,
    },
  ];

  Future<void> _processUpgrade() async {
    if (_selectedPlan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الباقة الجديدة')),
      );
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isLoading = false);
      final plan = _availablePlans.firstWhere((p) => p['id'] == _selectedPlan);
      final priceDiff = plan['price'] - _currentPlan['price'];
      context.go('/citizen/payment?amount=$priceDiff&type=upgrade');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // الباقة الحالية
                        _buildCurrentPlanCard(),

                        const SizedBox(height: 24),

                        // الباقات المتاحة
                        const Text(
                          'الباقات المتاحة للترقية',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textDark,
                          ),
                        ),
                        const SizedBox(height: 16),

                        ..._availablePlans.map((plan) => _buildPlanCard(plan)),

                        const SizedBox(height: 24),

                        // ملاحظة
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.infoColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.infoColor.withOpacity(0.3),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: AppTheme.infoColor,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'سيتم احتساب فرق السعر فقط للمدة المتبقية من اشتراكك الحالي',
                                  style: TextStyle(color: AppTheme.infoColor),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // زر الترقية
                        _buildSubmitButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _buildBackButton(),
        const Expanded(
          child: Text(
            'ترقية الباقة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
        ),
        const SizedBox(width: 40),
      ],
    );
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => context.go('/citizen/internet'),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_ios_new,
          color: AppTheme.primaryColor,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _selectedPlan == null || _isLoading ? null : _processUpgrade,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4CAF50),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                'ترقية الآن',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _buildCurrentPlanCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.wifi, color: AppTheme.textGrey, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'باقتك الحالية',
                  style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
                ),
                Text(
                  _currentPlan['name'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  '${_currentPlan['price']} د.ع/شهر',
                  style: const TextStyle(color: AppTheme.textGrey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan) {
    final isSelected = _selectedPlan == plan['id'];
    final isPopular = plan['popular'] as bool;
    final priceDiff = plan['price'] - _currentPlan['price'];

    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan['id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          plan['speed'] >= 1000
                              ? Icons.rocket_launch
                              : Icons.speed,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan['name'],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textDark,
                              ),
                            ),
                            Text(
                              '${plan['speed'] >= 1000 ? "${plan['speed'] ~/ 1000} جيجا" : "${plan['speed']} ميجا"} في الثانية',
                              style: const TextStyle(color: AppTheme.textGrey),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${plan['price']} د.ع',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const Text(
                            '/شهر',
                            style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (plan['features'] as List<String>).map((feature) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: AppTheme.successColor,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              feature,
                              style: const TextStyle(
                                color: AppTheme.successColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.arrow_upward,
                          color: AppTheme.accentColor,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'فرق السعر: +$priceDiff د.ع/شهر',
                          style: const TextStyle(
                            color: AppTheme.accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (isPopular)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    color: AppTheme.accentColor,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'الأكثر طلباً',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            if (isSelected)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppTheme.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
