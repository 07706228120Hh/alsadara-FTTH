import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة إتمام الشراء
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  String _selectedPayment = 'card';
  bool _isLoading = false;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  // Mock cart data
  final int _subtotal = 520;
  final int _shipping = 0;
  int get _total => _subtotal + _shipping;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isLoading = false);
      if (_selectedPayment == 'card') {
        context.go('/citizen/payment?amount=$_total&type=store_order');
      } else {
        _showSuccessDialog();
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
              'تم تأكيد الطلب!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'رقم الطلب: #ORD-12345\nسيتم التواصل معك لتأكيد التوصيل',
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
        appBar: AppBar(
          title: const Text('إتمام الشراء'),
          backgroundColor: AppTheme.storeColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/store/cart'),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // معلومات التوصيل
                const Text(
                  'معلومات التوصيل',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'الاسم الكامل',
                    prefixIcon: const Icon(Icons.person_outline),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (v) => v?.isEmpty == true ? 'مطلوب' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'رقم الجوال',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (v) => v?.isEmpty == true ? 'مطلوب' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _addressController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'العنوان التفصيلي',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    hintText: 'المدينة، الحي، الشارع، رقم المنزل',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  validator: (v) => v?.isEmpty == true ? 'مطلوب' : null,
                ),

                const SizedBox(height: 32),

                // طريقة الدفع
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
                  'card',
                  'بطاقة مصرفية',
                  'Visa, Mastercard, مدى',
                  Icons.credit_card,
                ),
                const SizedBox(height: 12),
                _buildPaymentOption(
                  'cod',
                  'الدفع عند الاستلام',
                  'ادفع نقداً عند التوصيل',
                  Icons.payments_outlined,
                ),

                const SizedBox(height: 32),

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
                      _buildOrderItem('راوتر فايبر احترافي', 1, 450),
                      _buildOrderItem('كابل فايبر 10 متر', 2, 70),
                      const Divider(height: 24),
                      _buildSummaryRow('المجموع الفرعي', '$_subtotal د.ع'),
                      _buildSummaryRow(
                        'الشحن',
                        _shipping == 0 ? 'مجاني' : '$_shipping د.ع',
                        isFree: _shipping == 0,
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
                            '$_total د.ع',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.storeColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // زر إتمام الطلب
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _placeOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.storeColor,
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
                        : Text(
                            _selectedPayment == 'card'
                                ? 'الدفع الآن'
                                : 'تأكيد الطلب',
                            style: const TextStyle(
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.storeColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.storeColor : AppTheme.textGrey,
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
                          ? AppTheme.storeColor
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
              activeColor: AppTheme.storeColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItem(String name, int qty, int price) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$name x$qty', style: const TextStyle(color: AppTheme.textGrey)),
          Text(
            '$price د.ع',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isFree = false}) {
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
              color: isFree ? AppTheme.successColor : AppTheme.textDark,
            ),
          ),
        ],
      ),
    );
  }
}
