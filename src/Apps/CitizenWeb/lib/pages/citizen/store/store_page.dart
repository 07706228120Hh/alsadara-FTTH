import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sadara_design/sadara_design.dart';

/// المتجر الإلكتروني — موحّد على نظام تصميم الصدارة (3D).
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
    final q = _searchController.text.trim();
    var list = _selectedCategory == 'all'
        ? _products
        : _products.where((p) => p['category'] == _selectedCategory).toList();
    if (q.isNotEmpty) {
      list = list
          .where((p) => (p['name'] as String).contains(q))
          .toList();
    }
    return list;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: SdAppBar(
        title: 'المتجر',
        onBack: () => context.go('/citizen/home'),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart_rounded),
                onPressed: () => context.go('/citizen/store/cart'),
              ),
              const Positioned(right: 4, top: 4, child: SdBadge(count: 2)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SdSpace.gutter, SdSpace.sm, SdSpace.gutter, 0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'ابحث عن منتج…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: SdSpace.sm),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: _categories.map((cat) {
                      final sel = _selectedCategory == cat['id'];
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(cat['icon'] as IconData,
                                  size: 16,
                                  color: sel ? Colors.white : SdColors.muted),
                              const SizedBox(width: 4),
                              Text(cat['name'] as String),
                            ],
                          ),
                          selected: sel,
                          onSelected: (_) =>
                              setState(() => _selectedCategory = cat['id'] as String),
                          selectedColor: SdColors.primary,
                          labelStyle: TextStyle(
                            fontFamily: SdText.family,
                            fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : SdColors.ink,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SdSpace.sm),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(SdSpace.gutter, 0, SdSpace.gutter, SdSpace.lg),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: isWide ? 4 : 2,
                childAspectRatio: 0.68,
                crossAxisSpacing: SdSpace.sm,
                mainAxisSpacing: SdSpace.sm,
              ),
              itemCount: _filteredProducts.length,
              itemBuilder: (context, i) => _productCard(_filteredProducts[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productCard(Map<String, dynamic> p) {
    final hasDiscount = p['oldPrice'] != null;
    return SdRaised(
      onTap: () => context.go('/citizen/store/product/${p['id']}'),
      radius: SdRadius.lg,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(SdRadius.lg)),
                  child: Container(
                    width: double.infinity,
                    color: SdColors.surfaceAlt,
                    child: Image.network(
                      p['imageUrl'] ?? '',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.image_rounded, size: 48, color: SdColors.faint)),
                    ),
                  ),
                ),
                if (hasDiscount)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: SdColors.danger,
                        borderRadius: BorderRadius.circular(SdRadius.xs),
                      ),
                      child: Text(
                        '-${(((p['oldPrice'] - p['price']) / p['oldPrice']) * 100).round()}%',
                        style: const TextStyle(
                            fontFamily: SdText.family,
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(SdSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p['name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SdText.label),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: SdColors.gold, size: 15),
                      const SizedBox(width: 2),
                      Text('${p['rating']}', style: SdText.caption),
                      Text(' (${p['reviews']})', style: SdText.caption),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text('${p['price']} د.ع',
                          style: SdText.label.copyWith(color: SdColors.success)),
                      if (hasDiscount) ...[
                        const SizedBox(width: 4),
                        Text('${p['oldPrice']}',
                            style: SdText.caption.copyWith(
                                decoration: TextDecoration.lineThrough)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
