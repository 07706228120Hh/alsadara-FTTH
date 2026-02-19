import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/agent_auth_provider.dart';
import '../../services/agent_api_service.dart';

/// صفحة طلب رصيد للوكيل
class BalanceRequestPage extends StatefulWidget {
  const BalanceRequestPage({super.key});

  @override
  State<BalanceRequestPage> createState() => _BalanceRequestPageState();
}

class _BalanceRequestPageState extends State<BalanceRequestPage> {
  final _formKey = GlobalKey<FormState>();
  int? _selectedAmount;
  final _customAmountController = TextEditingController();
  String _selectedMethod = 'transfer';
  bool _isLoading = false;
  AgentData? _agent;

  final List<int> _quickAmounts = [1000, 2000, 5000, 10000, 20000];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final agentAuth = context.read<AgentAuthProvider>();
    if (mounted) {
      setState(() => _agent = agentAuth.agent);
    }
  }

  int get _amount =>
      _selectedAmount ?? int.tryParse(_customAmountController.text) ?? 0;

  @override
  void dispose() {
    _customAmountController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى تحديد المبلغ')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final agentAuth = context.read<AgentAuthProvider>();
      // category: 7=BankTransfer, 6=CashPayment
      final category = _selectedMethod == 'transfer' ? 7 : 6;
      final description = _selectedMethod == 'transfer'
          ? 'طلب رصيد (تحويل بنكي)'
          : 'طلب رصيد (نقدي)';

      final success = await agentAuth.requestCharge(
        amount: _amount.toDouble(),
        description: description,
        category: category,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          // تحديث بيانات الوكيل
          await agentAuth.refreshProfile();
          setState(() => _agent = agentAuth.agent);

          if (_selectedMethod == 'transfer') {
            _showTransferDialog();
          } else {
            _showSuccessDialog();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(agentAuth.error ?? 'فشل في تقديم الطلب'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
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

  void _showTransferDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('معلومات التحويل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('يرجى تحويل المبلغ إلى الحساب التالي:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBankInfo('البنك', 'بنك الراجحي'),
                  _buildBankInfo('رقم الحساب', 'SA1234567890123456789'),
                  _buildBankInfo('المبلغ', '$_amount د.ع'),
                  _buildBankInfo('المستفيد', 'شركة الصدارة للاتصالات'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'بعد التحويل، يرجى إرفاق إيصال التحويل',
              style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccessDialog();
            },
            child: const Text('تم التحويل'),
          ),
        ],
      ),
    );
  }

  Widget _buildBankInfo(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textGrey)),
          SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
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
              'تم تقديم الطلب!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'رقم الطلب: #REQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
              style: const TextStyle(color: AppTheme.textGrey),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedMethod == 'credit'
                  ? 'تمت إضافة $_amount د.ع إلى رصيدك'
                  : 'سيتم إضافة الرصيد بعد التحقق من التحويل',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textGrey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
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
            title: const Text('طلب رصيد'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
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
                        // رصيدك الحالي
                        _buildBalanceCard(),

                        const SizedBox(height: 24),

                        // المبلغ المطلوب
                        const Text(
                          'المبلغ المطلوب',
                          style: AppTheme.headingSmall,
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.agentColor
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppTheme.agentColor
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Text(
                                  '$amount',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : AppTheme.textDark,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _customAmountController,
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            if (v.isNotEmpty) {
                              setState(() => _selectedAmount = null);
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'أو أدخل مبلغ مخصص',
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

                        // طريقة الدفع
                        const Text(
                          'طريقة الحصول على الرصيد',
                          style: AppTheme.headingSmall,
                        ),
                        const SizedBox(height: 16),

                        _buildMethodOption(
                          'transfer',
                          'تحويل بنكي',
                          'حول المبلغ واحصل على الرصيد فوراً',
                          Icons.account_balance,
                        ),
                        const SizedBox(height: 12),
                        _buildMethodOption(
                          'credit',
                          'نقدي',
                          'دفع نقدي مباشر',
                          Icons.credit_score,
                        ),

                        const SizedBox(height: 24),

                        // ملخص
                        if (_amount > 0) _buildSummary(),

                        const SizedBox(height: 24),

                        // زر الطلب
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _amount <= 0 || _isLoading
                                ? null
                                : _submitRequest,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.agentColor,
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
                                    'تقديم الطلب',
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

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor, // Use Primary for Balance Card
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'رصيدك الحالي',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_agent?.netBalance.toStringAsFixed(0) ?? 0} د.ع',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Text(
                  'إجمالي التسديد',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  '${_agent?.totalPayments.toStringAsFixed(0) ?? 0}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMethodOption(
    String value,
    String title,
    String subtitle,
    IconData icon, {
    String? subtitle2,
  }) {
    final isSelected = _selectedMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.agentColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.agentColor : AppTheme.textGrey,
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
                          ? AppTheme.agentColor
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
                  if (subtitle2 != null)
                    Text(
                      subtitle2,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.successColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: _selectedMethod,
              onChanged: (v) => setState(() => _selectedMethod = v!),
              activeColor: AppTheme.agentColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'المبلغ المطلوب',
                style: TextStyle(color: AppTheme.textGrey),
              ),
              Text(
                '$_amount د.ع',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الطريقة', style: TextStyle(color: AppTheme.textGrey)),
              Text(
                _selectedMethod == 'transfer' ? 'تحويل بنكي' : 'آجل',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الرصيد المتوقع',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${((_agent?.netBalance ?? 0) + _amount).toStringAsFixed(0)} د.ع', // Calculated on Net Balance
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.successColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
