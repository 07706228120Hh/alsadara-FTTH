import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/agent_auth_provider.dart';
import '../../services/agent_api_service.dart';

// Alias for readability
const _primaryColor = AppTheme.agentColor;

/// صفحة سداد مديونية - الوكيل يُسدد جزء من رصيده المستحق
class DebtPaymentPage extends StatefulWidget {
  const DebtPaymentPage({super.key});

  @override
  State<DebtPaymentPage> createState() => _DebtPaymentPageState();
}

class _DebtPaymentPageState extends State<DebtPaymentPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  AgentData? _agent;
  bool _isLoading = false;
  int _selectedCategory = 6; // دفع نقدي

  final List<Map<String, dynamic>> _paymentMethods = [
    {'value': 6, 'label': 'دفع نقدي', 'icon': Icons.money},
    {'value': 7, 'label': 'تحويل بنكي', 'icon': Icons.account_balance},
  ];

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _loadAgent() {
    final agentAuth = context.read<AgentAuthProvider>();
    setState(() => _agent = agentAuth.agent);
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    setState(() => _isLoading = true);

    try {
      final agentAuth = context.read<AgentAuthProvider>();
      await agentAuth.agentApi.recordPayment(
        amount: amount,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : 'سداد مديونية',
        category: _selectedCategory,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        // تحديث بيانات الوكيل
        await agentAuth.refreshProfile();
        _loadAgent();
        _showSuccessDialog(amount);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  void _showSuccessDialog(double amount) {
    showDialog(
      context: context,
      barrierDismissible: false,
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
              'تم تسجيل السداد!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'تم تسجيل سداد بمبلغ ${amount.toStringAsFixed(0)} د.ع',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textGrey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _amountController.clear();
                  _descriptionController.clear();
                },
                child: const Text('سداد آخر'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/agent/home');
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
    return Theme(
      data: AppTheme.agentTheme,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            title: const Text('سداد مديونية'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward_ios, size: 20),
              onPressed: () => context.go('/agent/home'),
            ),
          ),
          body: _agent == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ملخص الرصيد
                        _buildBalanceSummary(),
                        const SizedBox(height: 24),

                        // المبلغ
                        const Text('مبلغ السداد', style: AppTheme.headingSmall),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _amountController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: '0',
                            suffixText: 'د.ع',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: _primaryColor,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'أدخل المبلغ';
                            }
                            final amount = double.tryParse(value.trim());
                            if (amount == null || amount <= 0) {
                              return 'أدخل مبلغ صحيح';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),

                        // أزرار المبالغ السريعة
                        _buildQuickAmounts(),
                        const SizedBox(height: 24),

                        // طريقة الدفع
                        const Text('طريقة الدفع', style: AppTheme.headingSmall),
                        const SizedBox(height: 12),
                        _buildPaymentMethods(),
                        const SizedBox(height: 24),

                        // الملاحظات
                        const Text(
                          'ملاحظات (اختياري)',
                          style: AppTheme.headingSmall,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _descriptionController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'أضف ملاحظة...',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // زر إرسال
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _submitPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.successColor,
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
                                    'تأكيد السداد',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildBalanceSummary() {
    final debt = _agent!.netBalance;
    final isInDebt = debt < 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isInDebt
              ? [const Color(0xFFE53935), const Color(0xFFC62828)]
              : [AppTheme.successColor, const Color(0xFF1B5E20)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isInDebt ? Icons.warning_amber_rounded : Icons.check_circle,
                color: Colors.white,
                size: 40,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isInDebt ? 'المبلغ المستحق عليك' : 'رصيدك الحالي',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${debt.abs().toStringAsFixed(0)} د.ع',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildBalanceItem('إجمالي الشحن', _agent!.totalCharges),
              _buildBalanceItem('إجمالي السداد', _agent!.totalPayments),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceItem(String label, double value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(0)} د.ع',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAmounts() {
    final amounts = [5000, 10000, 25000, 50000, 100000];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: amounts.map((amount) {
        return GestureDetector(
          onTap: () => _amountController.text = amount.toString(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              '${amount.toString()} د.ع',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: _primaryColor,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      children: _paymentMethods.map((method) {
        final isSelected = _selectedCategory == method['value'];
        return GestureDetector(
          onTap: () => setState(() => _selectedCategory = method['value']),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? _primaryColor : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  method['icon'],
                  color: isSelected ? _primaryColor : AppTheme.textGrey,
                ),
                const SizedBox(width: 12),
                Text(
                  method['label'],
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? _primaryColor : AppTheme.textDark,
                  ),
                ),
                const Spacer(),
                if (isSelected)
                  const Icon(Icons.check_circle, color: _primaryColor),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
