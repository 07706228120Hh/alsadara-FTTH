import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة شحن رصيد الماستر
class RechargeCardPage extends StatefulWidget {
  const RechargeCardPage({super.key});

  @override
  State<RechargeCardPage> createState() => _RechargeCardPageState();
}

class _RechargeCardPageState extends State<RechargeCardPage> {
  int? _selectedAmount;
  final _customAmountController = TextEditingController();
  bool _isLoading = false;

  final List<int> _quickAmounts = [50, 100, 200, 500, 1000];

  int get _amount =>
      _selectedAmount ?? int.tryParse(_customAmountController.text) ?? 0;

  @override
  void dispose() {
    _customAmountController.dispose();
    super.dispose();
  }

  Future<void> _processRecharge() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى تحديد مبلغ الشحن')));
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() => _isLoading = false);
      context.go('/citizen/payment?amount=$_amount&type=master_recharge');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('شحن رصيد'),
          backgroundColor: AppTheme.masterCardColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/master'),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // البطاقة المحددة
              _buildSelectedCard(),

              const SizedBox(height: 24),

              // مبالغ سريعة
              const Text(
                'اختر مبلغ الشحن',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 16),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _quickAmounts.map((amount) {
                  final isSelected = _selectedAmount == amount;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedAmount = amount;
                        _customAmountController.clear();
                      });
                    },
                    child: Container(
                      width: 100,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.masterCardColor
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.masterCardColor
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$amount',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textDark,
                            ),
                          ),
                          Text(
                            'د.ع',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white70
                                  : AppTheme.textGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // مبلغ مخصص
              const Text(
                'أو أدخل مبلغ مخصص',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _customAmountController,
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    setState(() => _selectedAmount = null);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'أدخل المبلغ',
                  suffixText: 'د.ع',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ملخص
              if (_amount > 0)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'مبلغ الشحن',
                            style: TextStyle(color: AppTheme.textGrey),
                          ),
                          Text(
                            '$_amount د.ع',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'رسوم الخدمة',
                            style: TextStyle(color: AppTheme.textGrey),
                          ),
                          Text(
                            '0 د.ع',
                            style: TextStyle(color: AppTheme.successColor),
                          ),
                        ],
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
                            ),
                          ),
                          Text(
                            '$_amount د.ع',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.masterCardColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),

              // زر الشحن
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _amount <= 0 || _isLoading
                      ? null
                      : _processRecharge,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.masterCardColor,
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
                          'متابعة الدفع',
                          style: TextStyle(
                            fontSize: 16,
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

  Widget _buildSelectedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.masterCardColor,
            AppTheme.masterCardColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.credit_card, color: Colors.white, size: 40),
          SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '**** **** **** 4532',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'الرصيد الحالي: 2,450.00 د.ع',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
