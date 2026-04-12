import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة المتجر الإلكتروني
class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  String _selectedCategory = 'all';
  final _searchController = TextEditingController();

  final List<Map<String, dynamic>> _categories = [
    {'id': 'all', 'name': 'الكل', 'icon': Icons.apps},
    {'id': 'routers', 'name': 'الراوترات', 'icon': Icons.router},
    {'id': 'cables', 'name': 'الكابلات', 'icon': Icons.cable},
    {'id': 'accessories', 'name': 'ملحقات', 'icon': Icons.devices_other},
  ];

  final List<Map<String, dynamic>> _products = [
    {
      'id': '1',
      'name': 'راوتر فايبر احترافي',
      'description': 'سرعة حتى 1 جيجا، WiFi 6',
      'price': 450,
      'oldPrice': 550,
      'imageUrl': 'https://m.media-amazon.com/images/I/51A3L0yF3WL._AC_SL1000_.jpg',
      'category': 'routers',
      'rating': 4.8,
      'reviews': 124,
    },
    {
      'id': '2',
      'name': 'راوتر منزلي',
      'description': 'مناسب للاستخدام المنزلي',
      'price': 250,
      'imageUrl': 'https://m.media-amazon.com/images/I/51gJMfcHjBL._AC_SL1000_.jpg',
      'category': 'routers',
      'rating': 4.5,
      'reviews': 89,
    },
    {
      'id': '3',
      'name': 'كابل فايبر 10 متر',
      'description': 'كابل فايبر عالي الجودة',
      'price': 35,
      'imageUrl': 'https://m.media-amazon.com/images/I/61tU7Q2TvdL._AC_SL1500_.jpg',
      'category': 'cables',
      'rating': 4.7,
      'reviews': 56,
    },
    {
      'id': '4',
      'name': 'موسع WiFi',
      'description': 'لتقوية الإشارة في جميع الغرف',
      'price': 150,
      'oldPrice': 180,
      'imageUrl': 'https://m.media-amazon.com/images/I/41FvIpi3JkL._AC_SL1000_.jpg',
      'category': 'accessories',
      'rating': 4.3,
      'reviews': 45,
    },
    {
      'id': '5',
      'name': 'سويتش شبكة 8 منافذ',
      'description': 'سويتش احترافي سرعة جيجا',
      'price': 120,
      'imageUrl': 'https://m.media-amazon.com/images/I/61VlJFJOmeL._AC_SL1500_.jpg',
      'category': 'accessories',
      'rating': 4.6,
      'reviews': 32,
    },
  ];

  List<Map<String, dynamic>> get _filteredProducts {
    if (_selectedCategory == 'all') return _products;
    return _products.where((p) => p['category'] == _selectedCategory).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundColor,
        appBar: AppBar(
          title: const Text('المتجر'),
          backgroundColor: AppTheme.storeColor,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/citizen/home'),
          ),
          actions: [
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_cart),
                  onPressed: () => context.go('/citizen/store/cart'),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Text(
                      '2',
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // Search & Categories
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                children: [
                  // Search
                  TextFormField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'ابحث عن منتج...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: AppTheme.backgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Categories
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _categories.map((cat) {
                        final isSelected = _selectedCategory == cat['id'];
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: ChoiceChip(
                            label: Row(
                              children: [
                                Icon(
                                  cat['icon'] as IconData,
                                  size: 16,
                                  color: isSelected
                                      ? Colors.white
                                      : AppTheme.textGrey,
                                ),
                                const SizedBox(width: 4),
                                Text(cat['name']),
                              ],
                            ),
                            selected: isSelected,
                            onSelected: (_) =>
                                setState(() => _selectedCategory = cat['id']),
                            selectedColor: AppTheme.storeColor,
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.textDark,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            // Products Grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isWide ? 4 : 2,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = _filteredProducts[index];
                    return _buildProductCard(product);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final hasDiscount = product['oldPrice'] != null;

    return GestureDetector(
      onTap: () => context.go('/citizen/store/product/${product['id']}'),
      child: Container(
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
            // Image
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: Image.network(
                        product['imageUrl'] ?? '',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image,
                          size: 60,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  if (hasDiscount)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '-${(((product['oldPrice'] - product['price']) / product['oldPrice']) * 100).round()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textDark,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 2),
                        Text(
                          '${product['rating']}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textGrey,
                          ),
                        ),
                        Text(
                          ' (${product['reviews']})',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textGrey,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          '${product['price']} د.ع',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.storeColor,
                          ),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${product['oldPrice']}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textGrey,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
