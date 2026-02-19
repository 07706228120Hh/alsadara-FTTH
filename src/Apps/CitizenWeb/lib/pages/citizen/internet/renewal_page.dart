import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة تجديد الاشتراك
class RenewalPage extends StatefulWidget {
  const RenewalPage({super.key});

  @override
  State<RenewalPage> createState() => _RenewalPageState();
}

class _RenewalPageState extends State<RenewalPage> {
  int _selectedMonths = 1;
  String _selectedPayment = 'electronic';
  bool _isLoading = false;

  // بيانات الاشتراك الحالي (سيتم جلبها من API)
  final Map<String, dynamic> _currentSubscription = {
    'plan': 'باقة 100 ميجا',
    'monthlyPrice': 150,
    'expiryDate': '2025-02-15',
    'daysLeft': 45,
  };

  int get _totalPrice =>
      (_currentSubscription['monthlyPrice'] as int) * _selectedMonths;

  Future<void> _processRenewal() async {
    setState(() => _isLoading = true);

    // TODO: معالجة التجديد عبر API
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isLoading = false);
      if (_selectedPayment == 'electronic') {
        context.go('/citizen/payment?amount=$_totalPrice&type=renewal');
      } else {
        _showSuccessDialog();
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: AppTheme.successColor,
                size: 60,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'تم تقديم طلب التجديد!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'سيتم تفعيل الاشتراك بعد استلام الدفعة',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textGrey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/citizen/home');
                },
                child: const Text('العودة للرئيسية'),
              ),
            ),
          ],
        ),
      ),
    );
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
                // الهيدر الموحد
                _buildHeader(),
                const SizedBox(height: 16),
                // المحتوى
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // الاشتراك الحالي
                        _buildCurrentSubscriptionCard(),
                        const SizedBox(height: 20),
                        // مدة التجديد
                        _buildDurationSelector(),
                        const SizedBox(height: 20),
                        // طريقة الدفع
                        _buildPaymentMethodSelector(),
                        const SizedBox(height: 20),
                        // ملخص الطلب
                        _buildOrderSummary(),
                        const SizedBox(height: 24),
                        // زر التجديد
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
        const SizedBox(width: 16),
        const Expanded(
          child: Text(
            'تجديد الاشتراك',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF4CAF50),
                const Color(0xFF4CAF50).withOpacity(0.7),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.autorenew, color: Colors.white, size: 24),
        ),
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
          shape: BoxShape.circle,
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
          color: Colors.black87,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _processRenewal,
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
                'تأكيد التجديد',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _buildCurrentSubscriptionCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wifi, color: Colors.white),
              SizedBox(width: 8),
              Text('اشتراكك الحالي', style: TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _currentSubscription['plan'],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_currentSubscription['monthlyPrice']} د.ع/شهر',
                style: const TextStyle(color: Colors.white70),
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
                child: Text(
                  'متبقي ${_currentSubscription['daysLeft']} يوم',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'مدة التجديد',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildMonthOption(1, 'شهر'),
              const SizedBox(width: 12),
              _buildMonthOption(3, '3 أشهر', discount: 5),
              const SizedBox(width: 12),
              _buildMonthOption(6, '6 أشهر', discount: 10),
              const SizedBox(width: 12),
              _buildMonthOption(12, 'سنة', discount: 15),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthOption(int months, String label, {int discount = 0}) {
    final isSelected = _selectedMonths == months;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMonths = months),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
            border: isSelected ? null : Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (discount > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.2)
                        : AppTheme.successColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '-$discount%',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'طريقة الدفع',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          _buildPaymentOption(
            'electronic',
            'الدفع الإلكتروني',
            'بطاقة مصرفية أو محفظة إلكترونية',
            Icons.credit_card,
          ),
          const SizedBox(height: 12),
          _buildPaymentOption(
            'agent',
            'الدفع عبر وكيل',
            'زيارة أقرب وكيل معتمد',
            Icons.store,
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(
    String value,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final isSelected = _selectedPayment == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedPayment = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.1)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryColor : AppTheme.textGrey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.textDark,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: _selectedPayment,
              onChanged: (v) => setState(() => _selectedPayment = v!),
              activeColor: AppTheme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderSummary() {
    final discount = _selectedMonths >= 12
        ? 15
        : (_selectedMonths >= 6 ? 10 : (_selectedMonths >= 3 ? 5 : 0));
    final originalPrice = _totalPrice;
    final discountAmount = (originalPrice * discount / 100).round();
    final finalPrice = originalPrice - discountAmount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ملخص الطلب',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow('الباقة', _currentSubscription['plan']),
          _buildSummaryRow('المدة', '$_selectedMonths شهر'),
          _buildSummaryRow('السعر', '$originalPrice د.ع'),
          if (discount > 0)
            _buildSummaryRow(
              'الخصم ($discount%)',
              '-$discountAmount د.ع',
              isDiscount: true,
            ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الإجمالي',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              Text(
                '$finalPrice د.ع',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isDiscount = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textGrey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDiscount ? AppTheme.successColor : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
