import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';

class MaterialsPage extends StatefulWidget {
  final String companyId;
  const MaterialsPage({super.key, required this.companyId});

  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends State<MaterialsPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<InventoryItem> _items = [];
  List<InventoryCategory> _categories = [];

  int _page = 1;
  final int _pageSize = 20;
  int _total = 0;

  final _searchCtrl = TextEditingController();
  int? _selectedCategoryId;
  bool _lowStockOnly = false;

  static const Map<String, String> _unitMap = {
    'Piece': 'قطعة', 'Meter': 'متر', 'Roll': 'لفة', 'Box': 'صندوق',
    'Kilogram': 'كغم', 'Liter': 'لتر', 'Set': 'طقم', 'Pair': 'زوج', 'Other': 'أخرى',
  };

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await _api.getCategories(companyId: widget.companyId);
      final list = (res['data'] as List<dynamic>?) ?? [];
      _categories = list.map((e) => InventoryCategory.fromJson(e as Map<String, dynamic>)).toList();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _api.getItems(
        companyId: widget.companyId,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        categoryId: _selectedCategoryId != null ? '$_selectedCategoryId' : null,
        lowStockOnly: _lowStockOnly ? true : null,
        page: _page, pageSize: _pageSize,
      );
      final list = (res['data'] as List<dynamic>?) ?? [];
      _items = list.map((e) => InventoryItem.fromJson(e as Map<String, dynamic>)).toList();
      _total = (res['total'] as int?) ?? _items.length;
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onSearch() { _page = 1; _loadData(); }
  int get _totalPages => (_total / _pageSize).ceil().clamp(1, 99999);

  // ═══════════════════════════════════════════
  //  إدارة الأصناف (Categories)
  // ═══════════════════════════════════════════

  Future<void> _showCategoriesDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => _CategoriesManagerDialog(
        companyId: widget.companyId,
        api: _api,
        onChanged: () => _loadCategories(),
      ),
    );
  }

  Future<int?> _quickAddCategory() async {
    final nameCtrl = TextEditingController();
    int? parentId;

    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: const Text('إضافة تصنيف سريع'),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم التصنيف *', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    value: parentId,
                    decoration: const InputDecoration(labelText: 'تصنيف أب (اختياري)', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('بدون')),
                      ..._categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                    ],
                    onChanged: (v) => setD(() => parentId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  try {
                    final res = await _api.createCategory(data: {
                      'name': nameCtrl.text.trim(),
                      'parentCategoryId': parentId,
                      'companyId': widget.companyId,
                    });
                    await _loadCategories();
                    final newId = res['data']?['Id'] ?? res['data']?['id'];
                    if (ctx.mounted) Navigator.pop(ctx, newId is int ? newId : int.tryParse('$newId'));
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                child: const Text('إضافة'),
              ),
            ],
          );
        });
      },
    );
    return result;
  }

  // ═══════════════════════════════════════════
  //  إضافة/تعديل مادة
  // ═══════════════════════════════════════════

  String _generateSku() {
    final now = DateTime.now();
    return 'M${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _showAddEditDialog([InventoryItem? item]) async {
    final isNew = item == null || item.id.isEmpty;
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final skuCtrl = TextEditingController(text: isNew ? _generateSku() : item.sku);
    final descCtrl = TextEditingController(text: item?.description ?? '');
    final costCtrl = TextEditingController(text: item != null ? fmtN(item.costPrice) : '');
    final sellCtrl = TextEditingController(text: item?.sellingPrice != null ? fmtN(item!.sellingPrice!) : '');
    final wholesaleCtrl = TextEditingController(text: item?.wholesalePrice != null ? fmtN(item!.wholesalePrice!) : '');
    final minCtrl = TextEditingController(text: item != null ? '${item.minStockLevel}' : '0');
    final maxCtrl = TextEditingController(text: item != null ? '${item.maxStockLevel}' : '0');

    int? catId = item?.categoryId;
    String unit = item?.unit ?? 'Piece';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return AlertDialog(
            title: Text(item == null || item.id.isEmpty ? 'إضافة مادة' : 'تعديل مادة'),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المادة *', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                    // التصنيف مع زر إضافة سريع
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            value: catId,
                            decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('بدون تصنيف')),
                              ..._categories.map((c) {
                                final prefix = c.parentCategoryId != null ? '  ↳ ' : '';
                                return DropdownMenuItem(value: c.id, child: Text('$prefix${c.name}'));
                              }),
                            ],
                            onChanged: (v) => setD(() => catId = v),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.blue),
                          tooltip: 'إضافة تصنيف جديد',
                          onPressed: () async {
                            final newId = await _quickAddCategory();
                            if (newId != null) setD(() => catId = newId);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.account_tree_rounded, color: Colors.teal, size: 20),
                          tooltip: 'إدارة شجرة الأصناف',
                          onPressed: () async {
                            await _showCategoriesDialog();
                            setD(() {}); // refresh dropdown
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: unit,
                      decoration: const InputDecoration(labelText: 'الوحدة', border: OutlineInputBorder()),
                      items: _unitMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: (v) => setD(() => unit = v ?? 'Piece'),
                    ),
                    const SizedBox(height: 10),
                    // الأسعار: 3 حقول
                    Row(
                      children: [
                        Expanded(child: TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر التكلفة', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: sellCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر البيع', border: OutlineInputBorder()))),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(controller: wholesaleCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'سعر الجملة', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: minCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الحد الأدنى', border: OutlineInputBorder()))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: maxCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الحد الأقصى', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: descCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'الوصف', border: OutlineInputBorder())),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
            ],
          );
        });
      },
    );

    if (saved != true || nameCtrl.text.trim().isEmpty) return;

    final data = {
      'name': nameCtrl.text.trim(),
      'sku': skuCtrl.text.trim(),
      'categoryId': catId,
      'unit': unit,
      'costPrice': parseN(costCtrl.text),
      'sellingPrice': sellCtrl.text.trim().isEmpty ? null : parseN(sellCtrl.text),
      'wholesalePrice': wholesaleCtrl.text.trim().isEmpty ? null : parseN(wholesaleCtrl.text),
      'minStockLevel': int.tryParse(minCtrl.text) ?? 0,
      'maxStockLevel': int.tryParse(maxCtrl.text) ?? 0,
      'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      'companyId': widget.companyId,
    };

    try {
      if (item == null || item.id.isEmpty) {
        await _api.createItem(data: data);
      } else {
        await _api.updateItem(item.id, data: data);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  /// نسخ مادة — يفتح نافذة إضافة مادة جديدة بنفس البيانات مع تغيير الاسم
  void _duplicateItem(InventoryItem item) {
    // ننشئ نسخة وهمية بدون id لتُعامل كإضافة جديدة
    final copy = InventoryItem(
      id: '', // فارغ = إضافة جديدة
      name: '${item.name} (نسخة)',
      sku: '',
      unit: item.unit,
      costPrice: item.costPrice,
      sellingPrice: item.sellingPrice,
      wholesalePrice: item.wholesalePrice,
      minStockLevel: item.minStockLevel,
      maxStockLevel: item.maxStockLevel,
      categoryId: item.categoryId,
      categoryName: item.categoryName,
      description: item.description,
      isActive: true,
      companyId: item.companyId,
    );
    _showAddEditDialog(copy);
  }

  Future<void> _confirmDelete(InventoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف "${item.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteItem(item.id);
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  // ═══════════════════════════════════════════
  //  Build
  // ═══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)), titleTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700), elevation: 0,
          title: const Text('المواد والأصناف'),
          actions: [
            IconButton(icon: const Icon(Icons.account_tree_rounded), tooltip: 'إدارة الأصناف', onPressed: _showCategoriesDialog),
            IconButton(icon: const Icon(Icons.add), tooltip: 'إضافة مادة', onPressed: () => _showAddEditDialog()),
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'تحديث', onPressed: _loadData),
          ],
        ),
        body: Column(
          children: [
            _buildFilters(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
            if (!_loading && _error == null && _items.isNotEmpty) _buildPagination(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'بحث بالاسم...', prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(), isDense: true,
              suffixIcon: _searchCtrl.text.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchCtrl.clear(); _onSearch(); }) : null,
            ),
            onSubmitted: (_) => _onSearch(),
          )),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: DropdownButtonFormField<int?>(
            value: _selectedCategoryId,
            decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem(value: null, child: Text('الكل')),
              ..._categories.map((c) {
                final prefix = c.parentCategoryId != null ? '  ↳ ' : '';
                return DropdownMenuItem(value: c.id, child: Text('$prefix${c.name}'));
              }),
            ],
            onChanged: (v) { _selectedCategoryId = v; _onSearch(); },
          )),
          const SizedBox(width: 12),
          FilterChip(label: const Text('ناقص فقط'), selected: _lowStockOnly, onSelected: (v) { _lowStockOnly = v; _onSearch(); }),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _loadData, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
    ]));
    if (_items.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
      const SizedBox(height: 12),
      const Text('لا توجد مواد', style: TextStyle(fontSize: 16, color: Colors.grey)),
    ]));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
          columns: const [
            DataColumn(label: Text('الاسم')),
            DataColumn(label: Text('التصنيف')),
            DataColumn(label: Text('الوحدة')),
            DataColumn(label: Text('التكلفة'), numeric: true),
            DataColumn(label: Text('البيع'), numeric: true),
            DataColumn(label: Text('الجملة'), numeric: true),
            DataColumn(label: Text('الرصيد'), numeric: true),
            DataColumn(label: Text('إجراءات')),
          ],
          rows: _items.map((item) {
            final stock = item.totalStock ?? 0;
            final isLow = stock < item.minStockLevel && item.minStockLevel > 0;
            return DataRow(cells: [
              DataCell(Text(item.name)),
              DataCell(Text(item.categoryName ?? '-')),
              DataCell(Text(_unitMap[item.unit] ?? item.unit)),
              DataCell(Text(fmtN(item.costPrice))),
              DataCell(Text(fmtNullable(item.sellingPrice))),
              DataCell(Text(fmtNullable(item.wholesalePrice))),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: isLow ? BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)) : null,
                child: Text('$stock', style: TextStyle(color: isLow ? Colors.red.shade800 : null, fontWeight: isLow ? FontWeight.bold : null)),
              )),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.copy_rounded, size: 20, color: Colors.blue), tooltip: 'نسخ وتكرار', onPressed: () => _duplicateItem(item)),
                IconButton(icon: const Icon(Icons.edit, size: 20), tooltip: 'تعديل', onPressed: () => _showAddEditDialog(item)),
                IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), tooltip: 'حذف', onPressed: () => _confirmDelete(item)),
              ])),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _page > 1 ? () { _page--; _loadData(); } : null),
          Text('صفحة $_page من $_totalPages'),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _page < _totalPages ? () { _page++; _loadData(); } : null),
          const SizedBox(width: 16),
          Text('الإجمالي: $_total', style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  نافذة إدارة شجرة الأصناف
// ═══════════════════════════════════════════════════════════

class _CategoriesManagerDialog extends StatefulWidget {
  final String companyId;
  final InventoryApiService api;
  final VoidCallback onChanged;
  const _CategoriesManagerDialog({required this.companyId, required this.api, required this.onChanged});

  @override
  State<_CategoriesManagerDialog> createState() => _CategoriesManagerDialogState();
}

class _CategoriesManagerDialogState extends State<_CategoriesManagerDialog> {
  List<InventoryCategory> _cats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await widget.api.getCategories(companyId: widget.companyId);
      final list = (res['data'] as List<dynamic>?) ?? [];
      _cats = list.map((e) => InventoryCategory.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  // بناء الشجرة
  List<InventoryCategory> _getRoots() => _cats.where((c) => c.parentCategoryId == null).toList();
  List<InventoryCategory> _getChildren(int parentId) => _cats.where((c) => c.parentCategoryId == parentId).toList();

  Future<void> _addEdit([InventoryCategory? cat]) async {
    final nameCtrl = TextEditingController(text: cat?.name ?? '');
    final nameEnCtrl = TextEditingController(text: cat?.nameEn ?? '');
    int? parentId = cat?.parentCategoryId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text(cat == null ? 'إضافة تصنيف' : 'تعديل تصنيف'),
        content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم التصنيف *', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: nameEnCtrl, decoration: const InputDecoration(labelText: 'الاسم بالإنجليزية', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          DropdownButtonFormField<int?>(
            value: parentId,
            decoration: const InputDecoration(labelText: 'تصنيف أب', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('رئيسي (بدون أب)')),
              ..._cats.where((c) => c.id != cat?.id).map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
            ],
            onChanged: (v) => setD(() => parentId = v),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      )),
    );

    if (saved != true || nameCtrl.text.trim().isEmpty) return;
    try {
      if (cat == null) {
        await widget.api.createCategory(data: {
          'name': nameCtrl.text.trim(),
          'nameEn': nameEnCtrl.text.trim().isEmpty ? null : nameEnCtrl.text.trim(),
          'parentCategoryId': parentId,
          'companyId': widget.companyId,
        });
      } else {
        await widget.api.updateCategory(cat.id, data: {
          'name': nameCtrl.text.trim(),
          'nameEn': nameEnCtrl.text.trim().isEmpty ? null : nameEnCtrl.text.trim(),
          'parentCategoryId': parentId,
        });
      }
      widget.onChanged();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(InventoryCategory cat) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('حذف تصنيف'),
      content: Text('هل تريد حذف "${cat.name}"؟'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
      ],
    ));
    if (ok != true) return;
    try {
      await widget.api.deleteCategory(cat.id);
      widget.onChanged();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(children: [
          const Icon(Icons.account_tree_rounded, color: Colors.teal),
          const SizedBox(width: 8),
          const Expanded(child: Text('شجرة الأصناف')),
          IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue), tooltip: 'إضافة تصنيف', onPressed: () => _addEdit()),
        ]),
        content: SizedBox(
          width: 500,
          height: 400,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _cats.isEmpty
                  ? const Center(child: Text('لا توجد أصناف', style: TextStyle(color: Colors.grey)))
                  : ListView(children: _getRoots().map((root) => _buildTreeNode(root, 0)).toList()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _buildTreeNode(InventoryCategory cat, int depth) {
    final children = _getChildren(cat.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(right: depth * 24.0, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: depth == 0 ? Colors.teal.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: depth == 0 ? Colors.teal.shade200 : Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(
                children.isNotEmpty ? Icons.folder_rounded : Icons.label_rounded,
                size: 18,
                color: depth == 0 ? Colors.teal : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(cat.name, style: TextStyle(fontSize: 13, fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.normal))),
              if (cat.nameEn != null && cat.nameEn!.isNotEmpty)
                Text(cat.nameEn!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(width: 8),
              InkWell(onTap: () => _addEdit(cat), child: const Icon(Icons.edit, size: 16, color: Colors.blue)),
              const SizedBox(width: 6),
              InkWell(onTap: () => _delete(cat), child: const Icon(Icons.delete, size: 16, color: Colors.red)),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _addEdit()..toString(), // opens add with no parent preselected
                child: Tooltip(message: 'إضافة فرعي', child: Icon(Icons.add, size: 16, color: Colors.green.shade700)),
              ),
            ],
          ),
        ),
        ...children.map((child) => _buildTreeNode(child, depth + 1)),
      ],
    );
  }
}
