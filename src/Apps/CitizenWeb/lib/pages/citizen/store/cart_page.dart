import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة سلة التسوق
class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final List<Map<String, dynamic>> _cartItems = [
    {'id': '1', 'name': 'راوتر فايبر احترافي', 'price': 450, 'quantity': 1},
    {'id': '3', 'name': 'كابل فايبر 10 متر', 'price': 35, 'quantity': 2},
  ];

  int get _subtotal => _cartItems.fold(
    0,
    (sum, item) => sum + ((item['price'] as int) * (item['quantity'] as int)),
  );

  int get _shipping => _subtotal >= 500 ? 0 : 25;
  int get _total => _subtotal + _shipping;

  void _updateQuantity(int index, int delta) {
    setState(() {
      final newQty = (_cartItems[index]['quantity'] as int) + delta;
      if (newQty <= 0) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index]['quantity'] = newQty;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('سلة التسوق'),
          backgroundColor: AppTheme.storeColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/store'),
          ),
        ),
        body: _cartItems.isEmpty
            ? _buildEmptyCart()
            : Column(
                children: [
                  // Cart Items
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _cartItems.length,
                      itemBuilder: (context, index) {
                        final item = _cartItems[index];
                        return _buildCartItem(item, index);
                      },
                    ),
                  ),

                  // Summary & Checkout
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildSummaryRow('المجموع الفرعي', '$_subtotal د.ع'),
                        _buildSummaryRow(
                          'الشحن',
                          _shipping == 0 ? 'مجاني' : '$_shipping د.ع',
                          isFree: _shipping == 0,
                        ),
                        if (_subtotal < 500)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'أضف ${500 - _subtotal} د.ع للشحن المجاني',
                              style: const TextStyle(
                                color: AppTheme.accentColor,
                                fontSize: 12,
                              ),
                            ),
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
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () =>
                                context.go('/citizen/store/checkout'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.storeColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'إتمام الشراء',
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
                ],
              ),
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'سلة التسوق فارغة',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textGrey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'ابدأ بإضافة منتجات إلى سلتك',
            style: TextStyle(color: AppTheme.textGrey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.go('/citizen/store'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.storeColor,
            ),
            child: const Text('تصفح المتجر'),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItem(Map<String, dynamic> item, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Image placeholder
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.image, color: Colors.grey),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${item['price']} د.ع',
                  style: const TextStyle(
                    color: AppTheme.storeColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Quantity
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: () => _updateQuantity(index, -1),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                Text(
                  '${item['quantity']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => _updateQuantity(index, 1),
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
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
