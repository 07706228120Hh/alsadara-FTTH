import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة طلب بطاقة ماستر جديدة
class NewMasterCardPage extends StatefulWidget {
  const NewMasterCardPage({super.key});

  @override
  State<NewMasterCardPage> createState() => _NewMasterCardPageState();
}

class _NewMasterCardPageState extends State<NewMasterCardPage> {
  final _formKey = GlobalKey<FormState>();
  String _selectedCardType = 'standard';
  String _deliveryMethod = 'home';
  bool _isLoading = false;

  final _addressController = TextEditingController();

  final List<Map<String, dynamic>> _cardTypes = [
    {
      'id': 'standard',
      'name': 'بطاقة عادية',
      'description': 'بطاقة ماستر كارد أساسية',
      'price': 50,
      'features': ['سحب نقدي', 'شراء إلكتروني', 'دعم عالمي'],
    },
    {
      'id': 'gold',
      'name': 'بطاقة ذهبية',
      'description': 'مزايا إضافية وحدود أعلى',
      'price': 150,
      'features': ['سحب نقدي غير محدود', 'تأمين سفر', 'كاش باك 1%', 'دعم VIP'],
    },
  ];

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_deliveryMethod == 'home' && !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isLoading = false);
      final card = _cardTypes.firstWhere((c) => c['id'] == _selectedCardType);
      context.go(
        '/citizen/payment?amount=${card['price']}&type=new_master_card',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCard = _cardTypes.firstWhere(
      (c) => c['id'] == _selectedCardType,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('طلب بطاقة جديدة'),
          backgroundColor: AppTheme.masterCardColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/master'),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // نوع البطاقة
                const Text(
                  'اختر نوع البطاقة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 16),

                ..._cardTypes.map((card) => _buildCardTypeOption(card)),

                const SizedBox(height: 24),

                // طريقة التوصيل
                const Text(
                  'طريقة الاستلام',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 16),

                _buildDeliveryOption(
                  'home',
                  'توصيل للمنزل',
                  'توصيل خلال 3-5 أيام عمل',
                  Icons.home,
                  extraCost: 25,
                ),
                const SizedBox(height: 12),
                _buildDeliveryOption(
                  'branch',
                  'استلام من الفرع',
                  'جاهزة للاستلام خلال يومين',
                  Icons.store,
                ),

                if (_deliveryMethod == 'home') ...[
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _addressController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'عنوان التوصيل',
                      hintText: 'أدخل عنوانك بالتفصيل',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'يرجى إدخال العنوان';
                      }
                      return null;
                    },
                  ),
                ],

                const SizedBox(height: 24),

                // ملخص الطلب
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
                        'ملخص الطلب',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSummaryRow('نوع البطاقة', selectedCard['name']),
                      _buildSummaryRow(
                        'رسوم البطاقة',
                        '${selectedCard['price']} د.ع',
                      ),
                      if (_deliveryMethod == 'home')
                        _buildSummaryRow('رسوم التوصيل', '25 د.ع'),
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
                            '${(selectedCard['price'] as int) + (_deliveryMethod == 'home' ? 25 : 0)} د.ع',
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

                // زر الطلب
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitRequest,
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
      ),
    );
  }

  Widget _buildCardTypeOption(Map<String, dynamic> card) {
    final isSelected = _selectedCardType == card['id'];
    final isGold = card['id'] == 'gold';

    return GestureDetector(
      onTap: () => setState(() => _selectedCardType = card['id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          gradient: isGold
              ? const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                )
              : null,
          color: isGold ? null : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.masterCardColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.credit_card,
                    color: isGold ? Colors.white : AppTheme.masterCardColor,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          card['name'],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isGold ? Colors.white : AppTheme.textDark,
                          ),
                        ),
                        Text(
                          card['description'],
                          style: TextStyle(
                            color: isGold ? Colors.white70 : AppTheme.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${card['price']} د.ع',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isGold ? Colors.white : AppTheme.masterCardColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: (card['features'] as List<String>).map((feature) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isGold
                          ? Colors.white.withOpacity(0.2)
                          : AppTheme.masterCardColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check,
                          size: 12,
                          color: isGold
                              ? Colors.white
                              : AppTheme.masterCardColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          feature,
                          style: TextStyle(
                            fontSize: 12,
                            color: isGold
                                ? Colors.white
                                : AppTheme.masterCardColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveryOption(
    String value,
    String title,
    String subtitle,
    IconData icon, {
    int extraCost = 0,
  }) {
    final isSelected = _deliveryMethod == value;
    return GestureDetector(
      onTap: () => setState(() => _deliveryMethod = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.masterCardColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.masterCardColor : AppTheme.textGrey,
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
                          ? AppTheme.masterCardColor
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
            if (extraCost > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+$extraCost د.ع',
                  style: const TextStyle(
                    color: AppTheme.accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const SizedBox(width: 8),
            Radio<String>(
              value: value,
              groupValue: _deliveryMethod,
              onChanged: (v) => setState(() => _deliveryMethod = v!),
              activeColor: AppTheme.masterCardColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textGrey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
