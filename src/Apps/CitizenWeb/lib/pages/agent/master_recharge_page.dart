import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/agent_auth_provider.dart';
import '../../services/agent_api_service.dart';

/// صفحة شحن ماستر - الوكيل يطلب شحن بطاقات ماستر كارد
class MasterRechargePage extends StatefulWidget {
  const MasterRechargePage({super.key});

  @override
  State<MasterRechargePage> createState() => _MasterRechargePageState();
}

class _MasterRechargePageState extends State<MasterRechargePage> {
  AgentData? _agent;
  bool _isLoading = false;
  int _quantity = 1;
  int _selectedDenomination = 5000; // القيمة الافتراضية

  final List<Map<String, dynamic>> _denominations = [
    {'value': 1000, 'label': '1,000 د.ع'},
    {'value': 2000, 'label': '2,000 د.ع'},
    {'value': 5000, 'label': '5,000 د.ع'},
    {'value': 10000, 'label': '10,000 د.ع'},
    {'value': 25000, 'label': '25,000 د.ع'},
    {'value': 50000, 'label': '50,000 د.ع'},
  ];

  int get _totalAmount => _selectedDenomination * _quantity;

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

  Future<void> _submitRequest() async {
    if (_quantity <= 0) return;

    setState(() => _isLoading = true);

    try {
      final agentAuth = context.read<AgentAuthProvider>();
      await agentAuth.agentApi.createServiceRequest(
        serviceId: 10, // Master Card Service
        operationTypeId: 9, // Master Recharge
        customerName: _agent?.name ?? '',
        customerPhone: _agent?.phoneNumber ?? '',
        notes:
            'طلب شحن ماستر كارد - فئة: $_selectedDenomination د.ع - عدد: $_quantity - إجمالي: $_totalAmount د.ع',
      );

      if (mounted) {
        setState(() => _isLoading = false);
        _showSuccessDialog();
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
              'تم إرسال الطلب!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'طلب شحن $_quantity بطاقة ماستر بقيمة $_selectedDenomination د.ع',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textGrey),
            ),
            const SizedBox(height: 8),
            Text(
              'الإجمالي: $_totalAmount د.ع',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: AppTheme.masterCardColor,
              ),
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
            title: const Text('شحن ماستر'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // رصيد الوكيل
                      _buildBalanceCard(),
                      const SizedBox(height: 24),

                      // اختيار فئة الكارت
                      const Text('فئة البطاقة', style: AppTheme.headingSmall),
                      const SizedBox(height: 16),
                      _buildDenominationGrid(),
                      const SizedBox(height: 24),

                      // الكمية
                      const Text('الكمية', style: AppTheme.headingSmall),
                      const SizedBox(height: 16),
                      _buildQuantitySelector(),
                      const SizedBox(height: 24),

                      // ملخص الطلب
                      if (_totalAmount > 0) _buildSummary(),
                      const SizedBox(height: 24),

                      // زر الطلب
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading || _quantity <= 0
                              ? null
                              : _submitRequest,
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
                                  'إرسال الطلب',
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
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.masterCardColor, Color(0xFF1565C0)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          const Icon(Icons.credit_card, color: Colors.white, size: 40),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'رصيدك الحالي',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_agent?.netBalance.toStringAsFixed(0) ?? 0} د.ع',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
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

  Widget _buildDenominationGrid() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _denominations.map((d) {
        final isSelected = _selectedDenomination == d['value'];
        return GestureDetector(
          onTap: () => setState(() => _selectedDenomination = d['value']),
          child: Container(
            width: 140,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.masterCardColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppTheme.masterCardColor
                    : Colors.grey[300]!,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected ? AppTheme.cardShadow : null,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.credit_card,
                  size: 24,
                  color: isSelected ? Colors.white : AppTheme.textGrey,
                ),
                const SizedBox(height: 8),
                Text(
                  d['label'],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildQuantitySelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
            icon: const Icon(Icons.remove_circle_outline, size: 32),
            color: AppTheme.masterCardColor,
          ),
          const SizedBox(width: 24),
          Text(
            '$_quantity',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 24),
          IconButton(
            onPressed: _quantity < 100
                ? () => setState(() => _quantity++)
                : null,
            icon: const Icon(Icons.add_circle_outline, size: 32),
            color: AppTheme.masterCardColor,
          ),
        ],
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
          _buildSummaryRow('فئة البطاقة', '$_selectedDenomination د.ع'),
          const SizedBox(height: 8),
          _buildSummaryRow('الكمية', '$_quantity بطاقة'),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الإجمالي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              Text(
                '$_totalAmount د.ع',
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
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textGrey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
