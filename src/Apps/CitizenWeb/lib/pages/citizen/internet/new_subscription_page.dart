import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة اشتراك جديد - تنسيق موحد
class NewSubscriptionPage extends StatefulWidget {
  const NewSubscriptionPage({super.key});

  @override
  State<NewSubscriptionPage> createState() => _NewSubscriptionPageState();
}

class _NewSubscriptionPageState extends State<NewSubscriptionPage> {
  int _currentStep = 0;
  String? _selectedPlan;

  final _addressController = TextEditingController();
  String _selectedCity = 'القطيف';

  final List<String> _cities = [
    'القطيف',
    'الدمام',
    'الخبر',
    'الظهران',
    'سيهات',
  ];

  final List<Map<String, dynamic>> _plans = [
    {'id': '50mb', 'speed': 50, 'price': 100, 'popular': false},
    {'id': '100mb', 'speed': 100, 'price': 150, 'popular': true},
    {'id': '200mb', 'speed': 200, 'price': 200, 'popular': false},
    {'id': '500mb', 'speed': 500, 'price': 300, 'popular': false},
  ];

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0 && _selectedPlan == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى اختيار باقة')));
      return;
    }
    if (_currentStep == 1 && _addressController.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى إدخال العنوان')));
      return;
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _submitRequest();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) setState(() => _currentStep--);
  }

  void _submitRequest() {
    final plan = _plans.firstWhere((p) => p['id'] == _selectedPlan);
    context.go(
      '/citizen/payment?amount=${plan['price']}&type=new_subscription',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        // بدون AppBar - نستخدم هيدر مخصص
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // ═══════════════════════════════════════
                // الهيدر: زر العودة + العنوان
                // ═══════════════════════════════════════
                _buildHeader(),
                const SizedBox(height: 12),

                // ═══════════════════════════════════════
                // مؤشر الخطوات
                // ═══════════════════════════════════════
                _buildStepperHeader(),
                const SizedBox(height: 12),

                // ═══════════════════════════════════════
                // المحتوى
                // ═══════════════════════════════════════
                Expanded(child: _buildStepContent()),

                // ═══════════════════════════════════════
                // أزرار التنقل
                // ═══════════════════════════════════════
                _buildNavigationButtons(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// الهيدر الموحد
  Widget _buildHeader() {
    return Row(
      children: [
        // زر العودة الموحد
        _buildBackButton(),
        const SizedBox(width: 16),
        // العنوان
        const Expanded(
          child: Text(
            'اشتراك جديد',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        // أيقونة الصفحة
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF9C27B0),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.fiber_new, color: Colors.white, size: 24),
        ),
      ],
    );
  }

  /// زر العودة الموحد
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
          Icons.arrow_forward_ios, // سهم لليمين →
          color: Colors.black87,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    final steps = ['الباقة', 'العنوان', 'التأكيد'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black54, width: 2),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Expanded(
              child: Container(
                height: 2,
                color: index ~/ 2 < _currentStep
                    ? AppTheme.primaryColor
                    : Colors.grey[300],
              ),
            );
          }
          final stepIndex = index ~/ 2;
          final isActive = stepIndex == _currentStep;
          final isCompleted = stepIndex < _currentStep;
          return Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppTheme.successColor
                      : (isActive ? AppTheme.primaryColor : Colors.grey[300]),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Icons.check, color: Colors.white, size: 16)
                      : Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            color: isActive ? Colors.white : AppTheme.textGrey,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[stepIndex],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  color: isActive ? AppTheme.primaryColor : AppTheme.textGrey,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildPlanSelection();
      case 1:
        return _buildAddressForm();
      case 2:
        return _buildConfirmation();
      default:
        return const SizedBox();
    }
  }

  Widget _buildPlanSelection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardHeight = (constraints.maxHeight - 8) / 2;
        final cardWidth = (constraints.maxWidth - 8) / 2;
        final aspectRatio = cardWidth / cardHeight;

        return GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: aspectRatio,
          physics: const NeverScrollableScrollPhysics(),
          children: _plans.map((plan) {
            final isSelected = _selectedPlan == plan['id'];
            final color = plan['popular']
                ? const Color(0xFF9C27B0)
                : AppTheme.primaryColor;

            return GestureDetector(
              onTap: () => setState(() => _selectedPlan = plan['id']),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? color : Colors.black54,
                    width: isSelected ? 3 : 2,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(isSelected ? 0.2 : 0.1),
                      color.withOpacity(isSelected ? 0.3 : 0.15),
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    // شارة "الأكثر طلباً"
                    if (plan['popular'])
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'الأكثر طلباً',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    // محتوى البطاقة
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.speed,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${plan['speed']} ميجا',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${plan['price']} د.ع/شهر',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAddressForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'المدينة',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black54, width: 2),
          ),
          child: DropdownButton<String>(
            value: _selectedCity,
            isExpanded: true,
            underline: const SizedBox(),
            items: _cities.map((city) {
              return DropdownMenuItem(value: city, child: Text(city));
            }).toList(),
            onChanged: (v) => setState(() => _selectedCity = v!),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'العنوان التفصيلي',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _addressController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: 'الحي، الشارع، رقم المبنى...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black54, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.black54, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmation() {
    final plan = _plans.firstWhere(
      (p) => p['id'] == _selectedPlan,
      orElse: () => _plans[0],
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black54, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ملخص الطلب',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow('الباقة', '${plan['speed']} ميجا'),
          _buildSummaryRow('السعر الشهري', '${plan['price']} د.ع'),
          _buildSummaryRow('المدينة', _selectedCity),
          _buildSummaryRow(
            'العنوان',
            _addressController.text.isEmpty ? '-' : _addressController.text,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppTheme.primaryColor),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'سيتم التواصل معك خلال 24 ساعة لتأكيد الموعد',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _previousStep,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.black54, width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'السابق',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            flex: _currentStep == 0 ? 1 : 1,
            child: ElevatedButton(
              onPressed: _nextStep,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9C27B0),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _currentStep == 2 ? 'تأكيد الطلب' : 'التالي',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
