import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_theme.dart';

/// صفحة الدفع الإلكتروني
class PaymentPage extends StatefulWidget {
  final String? amount;
  final String? type;

  const PaymentPage({super.key, this.amount, this.type});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  String _selectedMethod = 'card';
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _saveCard = false;

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String get _pageTitle {
    switch (widget.type) {
      case 'renewal':
        return 'تجديد الاشتراك';
      case 'upgrade':
        return 'ترقية الباقة';
      case 'new_subscription':
        return 'اشتراك جديد';
      case 'master_recharge':
        return 'شحن رصيد';
      case 'new_master_card':
        return 'بطاقة جديدة';
      case 'store_order':
        return 'دفع الطلب';
      default:
        return 'الدفع';
    }
  }

  Future<void> _processPayment() async {
    if (_selectedMethod == 'card') {
      if (_cardNumberController.text.isEmpty ||
          _expiryController.text.isEmpty ||
          _cvvController.text.isEmpty ||
          _nameController.text.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('يرجى ملء جميع الحقول')));
        return;
      }
    }

    setState(() => _isLoading = true);

    // Simulate payment processing
    await Future.delayed(const Duration(seconds: 3));

    if (mounted) {
      setState(() => _isLoading = false);
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success Animation Container
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: AppTheme.successGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 50),
            ),
            const SizedBox(height: 24),
            const Text(
              'تمت العملية بنجاح!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textDark,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'تم دفع ${widget.amount} د.ع',
              style: const TextStyle(fontSize: 18, color: AppTheme.textGrey),
            ),
            const SizedBox(height: 8),
            const Text(
              'رقم العملية: #TRX-28475',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/citizen/home');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'العودة للرئيسية',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
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
        appBar: AppBar(
          title: Text(_pageTitle),
          backgroundColor: AppTheme.primaryColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Amount Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Text(
                      'المبلغ المطلوب',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.amount ?? "0"} د.ع',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Payment Methods
              const Text(
                'اختر طريقة الدفع',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),

              // Payment Method Cards
              Row(
                children: [
                  _buildMethodCard('card', 'بطاقة مصرفية', Icons.credit_card),
                  const SizedBox(width: 12),
                  _buildMethodCard('apple', 'Apple Pay', Icons.apple),
                  const SizedBox(width: 12),
                  _buildMethodCard('stc', 'STC Pay', Icons.phone_android),
                ],
              ),

              const SizedBox(height: 24),

              // Card Form (if card selected)
              if (_selectedMethod == 'card') ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'بيانات البطاقة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Card Number
                      TextFormField(
                        controller: _cardNumberController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'رقم البطاقة',
                          hintText: '0000 0000 0000 0000',
                          prefixIcon: const Icon(Icons.credit_card),
                          filled: true,
                          fillColor: AppTheme.backgroundColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Expiry & CVV
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _expiryController,
                              decoration: InputDecoration(
                                labelText: 'تاريخ الانتهاء',
                                hintText: 'MM/YY',
                                filled: true,
                                fillColor: AppTheme.backgroundColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _cvvController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: 'CVV',
                                hintText: '***',
                                filled: true,
                                fillColor: AppTheme.backgroundColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Card Holder Name
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'اسم حامل البطاقة',
                          hintText: 'كما هو مطبوع على البطاقة',
                          filled: true,
                          fillColor: AppTheme.backgroundColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Save Card
                      CheckboxListTile(
                        value: _saveCard,
                        onChanged: (v) => setState(() => _saveCard = v!),
                        title: const Text('حفظ البطاقة للمرات القادمة'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                ),
              ],

              // Wallet Methods Info
              if (_selectedMethod != 'card') ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _selectedMethod == 'apple'
                            ? Icons.apple
                            : Icons.phone_android,
                        size: 48,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedMethod == 'apple' ? 'Apple Pay' : 'STC Pay',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'سيتم توجيهك للتطبيق لإتمام الدفع',
                        style: TextStyle(color: AppTheme.textGrey),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Security Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: AppTheme.successColor),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'جميع المعاملات مشفرة ومحمية بتقنية SSL',
                        style: TextStyle(color: AppTheme.successColor),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Pay Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _processPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'ادفع ${widget.amount ?? "0"} د.ع',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMethodCard(String value, String label, IconData icon) {
    final isSelected = _selectedMethod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMethod = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : AppTheme.textGrey,
                size: 28,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textDark,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
