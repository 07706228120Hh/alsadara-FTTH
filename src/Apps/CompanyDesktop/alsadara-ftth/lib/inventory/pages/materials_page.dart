import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
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

  InputDecoration _dec(String label, {Widget? suffixIcon, Widget? prefixIcon, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: SdText.bodySm,
      hintStyle: SdText.bodySm,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: SdColors.surface,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SdRadius.sm),
        borderSide: const BorderSide(color: SdColors.cardEdge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SdRadius.sm),
        borderSide: const BorderSide(color: SdColors.cardEdge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SdRadius.sm),
        borderSide: const BorderSide(color: SdColors.primary, width: 1.5),
      ),
    );
  }

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
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('إضافة تصنيف سريع'),
              content: SizedBox(
                width: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: _dec('اسم التصنيف *'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      value: parentId,
                      decoration: _dec('تصنيف أب (اختياري)'),
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
                  style: FilledButton.styleFrom(backgroundColor: SdColors.primary, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)),
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
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
                      }
                    }
                  },
                  child: const Text('إضافة'),
                ),
              ],
            ),
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

  // يحسب سعر الشريحة من الكلفة والهامش: هامش موجود ⇒ السعر يُشتقّ؛ فارغ ⇒ لا تغيير (يدوي).
  void _recalcTier(TextEditingController costCtrl, TextEditingController marginCtrl,
      TextEditingController priceCtrl) {
    if (marginCtrl.text.trim().isEmpty) return;
    final cost = parseN(costCtrl.text);
    if (cost <= 0) return;
    final margin = parseN(marginCtrl.text);
    priceCtrl.text = fmtN(cost * (1 + margin / 100));
  }

  // صف شريحة بيع: الاسم + هامش% + السعر، مترابطان.
  Widget _tierPriceRow(String label, TextEditingController costCtrl,
      TextEditingController marginCtrl, TextEditingController priceCtrl) {
    return Row(
      children: [
        SizedBox(
            width: 92,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: marginCtrl,
            keyboardType: TextInputType.number,
            decoration: _dec('%'),
            onChanged: (_) => _recalcTier(costCtrl, marginCtrl, priceCtrl),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: priceCtrl,
            keyboardType: TextInputType.number,
            decoration: _dec('السعر'),
            // تعديل السعر يدوياً يُلغي الهامش فيصبح سعراً ثابتاً.
            onChanged: (_) {
              if (marginCtrl.text.isNotEmpty) marginCtrl.text = '';
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showAddEditDialog([InventoryItem? item]) async {
    final isNew = item == null || item.id.isEmpty;
    final nameCtrl = TextEditingController(text: item?.name ?? '');
    final skuCtrl = TextEditingController(text: isNew ? _generateSku() : item.sku);
    final descCtrl = TextEditingController(text: item?.description ?? '');
    final costCtrl = TextEditingController(text: item != null ? fmtN(item.costPrice) : '');
    final sellCtrl = TextEditingController(text: item?.sellingPrice != null ? fmtN(item!.sellingPrice!) : '');
    final wholesaleCtrl = TextEditingController(text: item?.wholesalePrice != null ? fmtN(item!.wholesalePrice!) : '');
    final bulkCtrl = TextEditingController(text: item?.bulkWholesalePrice != null ? fmtN(item!.bulkWholesalePrice!) : '');
    final retailMarginCtrl = TextEditingController(text: item?.retailMargin != null ? fmtN(item!.retailMargin!) : '');
    final wholesaleMarginCtrl = TextEditingController(text: item?.wholesaleMargin != null ? fmtN(item!.wholesaleMargin!) : '');
    final bulkMarginCtrl = TextEditingController(text: item?.bulkWholesaleMargin != null ? fmtN(item!.bulkWholesaleMargin!) : '');
    final minCtrl = TextEditingController(text: item != null ? '${item.minStockLevel}' : '0');
    final maxCtrl = TextEditingController(text: item != null ? '${item.maxStockLevel}' : '0');

    int? catId = item?.categoryId;
    String unit = item?.unit ?? 'Piece';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setD) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text(item == null || item.id.isEmpty ? 'إضافة مادة' : 'تعديل مادة'),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: nameCtrl, decoration: _dec('اسم المادة *')),
                      const SizedBox(height: 10),
                      // التصنيف مع زر إضافة سريع
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              value: catId,
                              decoration: _dec('التصنيف'),
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
                            icon: const Icon(Icons.add_circle, color: SdColors.primary),
                            tooltip: 'إضافة تصنيف جديد',
                            onPressed: () async {
                              final newId = await _quickAddCategory();
                              if (newId != null) setD(() => catId = newId);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.account_tree_rounded, color: SdColors.accent, size: 20),
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
                        decoration: _dec('الوحدة'),
                        items: _unitMap.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                        onChanged: (v) => setD(() => unit = v ?? 'Piece'),
                      ),
                      const SizedBox(height: 10),
                      // سعر التكلفة — يُعاد منه حساب أسعار الشرائح ذات الهامش
                      TextField(
                        controller: costCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _dec('سعر التكلفة'),
                        onChanged: (_) {
                          _recalcTier(costCtrl, retailMarginCtrl, sellCtrl);
                          _recalcTier(costCtrl, wholesaleMarginCtrl, wholesaleCtrl);
                          _recalcTier(costCtrl, bulkMarginCtrl, bulkCtrl);
                        },
                      ),
                      const SizedBox(height: 12),
                      // عناوين أعمدة شرائح البيع
                      Row(
                        children: const [
                          SizedBox(width: 92, child: Text('الشريحة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SdColors.faint))),
                          SizedBox(width: 8),
                          Expanded(child: Text('هامش %', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SdColors.faint))),
                          SizedBox(width: 8),
                          Expanded(child: Text('السعر', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SdColors.faint))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _tierPriceRow('مفرد', costCtrl, retailMarginCtrl, sellCtrl),
                      const SizedBox(height: 8),
                      _tierPriceRow('جملة', costCtrl, wholesaleMarginCtrl, wholesaleCtrl),
                      const SizedBox(height: 8),
                      _tierPriceRow('جملة الجملة', costCtrl, bulkMarginCtrl, bulkCtrl),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: TextField(controller: minCtrl, keyboardType: TextInputType.number, decoration: _dec('الحد الأدنى'))),
                          const SizedBox(width: 10),
                          Expanded(child: TextField(controller: maxCtrl, keyboardType: TextInputType.number, decoration: _dec('الحد الأقصى'))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(controller: descCtrl, maxLines: 2, decoration: _dec('الوصف')),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: SdColors.primary, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('حفظ'),
                ),
              ],
            ),
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
      'bulkWholesalePrice': bulkCtrl.text.trim().isEmpty ? null : parseN(bulkCtrl.text),
      'retailMarginPercent': retailMarginCtrl.text.trim().isEmpty ? null : parseN(retailMarginCtrl.text),
      'wholesaleMarginPercent': wholesaleMarginCtrl.text.trim().isEmpty ? null : parseN(wholesaleMarginCtrl.text),
      'bulkWholesaleMarginPercent': bulkMarginCtrl.text.trim().isEmpty ? null : parseN(bulkMarginCtrl.text),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحفظ'), backgroundColor: SdColors.success));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
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
      bulkWholesalePrice: item.bulkWholesalePrice,
      retailMargin: item.retailMargin,
      wholesaleMargin: item.wholesaleMargin,
      bulkWholesaleMargin: item.bulkWholesaleMargin,
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
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف "${item.name}"؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.danger, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
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
    final showPagination = !_loading && _error == null && _items.isNotEmpty;
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'المواد والأصناف',
        actions: [
          SdAppBarAction(icon: Icons.account_tree_rounded, label: 'إدارة الأصناف', onPressed: _showCategoriesDialog),
          SdAppBarAction(icon: Icons.add_rounded, label: 'إضافة مادة', onPressed: () => _showAddEditDialog()),
          SdAppBarAction(icon: Icons.refresh_rounded, label: 'تحديث', onPressed: _loadData),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilters(),
          const SizedBox(height: SdSpace.sm),
          Expanded(child: _buildBody()),
          if (showPagination) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final search = TextField(
      controller: _searchCtrl,
      style: SdText.body,
      decoration: _dec('', hint: 'بحث بالاسم...',
          prefixIcon: const Icon(Icons.search, color: SdColors.faint),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear, size: 18, color: SdColors.faint), onPressed: () { _searchCtrl.clear(); _onSearch(); })
              : null),
      onSubmitted: (_) => _onSearch(),
    );

    final categoryDropdown = DropdownButtonFormField<int?>(
      value: _selectedCategoryId,
      decoration: _dec('التصنيف'),
      items: [
        const DropdownMenuItem(value: null, child: Text('الكل')),
        ..._categories.map((c) {
          final prefix = c.parentCategoryId != null ? '  ↳ ' : '';
          return DropdownMenuItem(value: c.id, child: Text('$prefix${c.name}'));
        }),
      ],
      onChanged: (v) { _selectedCategoryId = v; _onSearch(); },
    );

    final lowStockToggle = SdRaised(
      onTap: () { _lowStockOnly = !_lowStockOnly; _onSearch(); },
      toggled: _lowStockOnly,
      semanticLabel: 'ناقص فقط',
      radius: SdRadius.pill,
      depth: 4,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: _lowStockOnly ? SdColors.warning : SdColors.surface,
      edgeColor: _lowStockOnly ? SdColors.warningEdge : SdColors.cardEdge,
      child: Text('ناقص فقط',
          style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _lowStockOnly ? Colors.white : SdColors.ink)),
    );

    if (context.sd.isPhone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: SdSpace.sm),
          Row(
            children: [
              Expanded(child: categoryDropdown),
              const SizedBox(width: 10),
              lowStockToggle,
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(flex: 3, child: search),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: categoryDropdown),
        const SizedBox(width: 12),
        lowStockToggle,
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    if (_error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل المواد',
          message: _error,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: _loadData),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد مواد', icon: Icons.inventory_2_outlined),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildItemCard(_items[i]),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Container(
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.lg),
            boxShadow: SdDepth.raised(),
          ),
          clipBehavior: Clip.antiAlias,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(SdColors.primary),
            headingTextStyle: const TextStyle(
                fontFamily: SdText.family, fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
            dataTextStyle: const TextStyle(
                fontFamily: SdText.family, fontSize: 12.5, fontWeight: FontWeight.w500, color: SdColors.ink),
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
            rows: [
              for (int i = 0; i < _items.length; i++)
                _buildDataRow(_items[i], i),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(InventoryItem item, int index) {
    final stock = item.totalStock ?? 0;
    final isLow = stock < item.minStockLevel && item.minStockLevel > 0;
    return DataRow(
      color: WidgetStateProperty.all(index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      cells: [
        DataCell(Text(item.name)),
        DataCell(Text(item.categoryName ?? '-')),
        DataCell(Text(_unitMap[item.unit] ?? item.unit)),
        DataCell(Text(fmtN(item.costPrice))),
        DataCell(Text(fmtNullable(item.sellingPrice))),
        DataCell(Text(fmtNullable(item.wholesalePrice))),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: isLow ? BoxDecoration(color: SdColors.dangerTint, borderRadius: BorderRadius.circular(SdRadius.xs)) : null,
          child: Text('$stock', style: TextStyle(color: isLow ? SdColors.danger : SdColors.ink, fontWeight: isLow ? FontWeight.w800 : FontWeight.w500)),
        )),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.copy_rounded, size: 20, color: SdColors.primary), tooltip: 'نسخ وتكرار', onPressed: () => _duplicateItem(item)),
          IconButton(icon: const Icon(Icons.edit, size: 20, color: SdColors.primary), tooltip: 'تعديل', onPressed: () => _showAddEditDialog(item)),
          IconButton(icon: const Icon(Icons.delete, size: 20, color: SdColors.danger), tooltip: 'حذف', onPressed: () => _confirmDelete(item)),
        ])),
      ],
    );
  }

  Widget _buildItemCard(InventoryItem item) {
    final stock = item.totalStock ?? 0;
    final isLow = stock < item.minStockLevel && item.minStockLevel > 0;
    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.name, style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SdStatusChip('الرصيد: $stock', status: isLow ? SdStatus.danger : SdStatus.success),
            ],
          ),
          const SizedBox(height: 4),
          SdInfoRow(label: 'التصنيف', value: item.categoryName ?? '-'),
          SdInfoRow(label: 'الوحدة', value: _unitMap[item.unit] ?? item.unit),
          SdInfoRow(label: 'سعر التكلفة', value: fmtN(item.costPrice)),
          SdInfoRow(label: 'سعر البيع', value: fmtNullable(item.sellingPrice)),
          SdInfoRow(label: 'سعر الجملة', value: fmtNullable(item.wholesalePrice)),
          const Divider(color: SdColors.divider, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(icon: const Icon(Icons.copy_rounded, size: 20, color: SdColors.primary), tooltip: 'نسخ وتكرار', onPressed: () => _duplicateItem(item)),
              IconButton(icon: const Icon(Icons.edit, size: 20, color: SdColors.primary), tooltip: 'تعديل', onPressed: () => _showAddEditDialog(item)),
              IconButton(icon: const Icon(Icons.delete, size: 20, color: SdColors.danger), tooltip: 'حذف', onPressed: () => _confirmDelete(item)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.only(top: SdSpace.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.chevron_right, color: SdColors.primary), onPressed: _page > 1 ? () { _page--; _loadData(); } : null),
          Text('صفحة $_page من $_totalPages', style: SdText.label),
          IconButton(icon: const Icon(Icons.chevron_left, color: SdColors.primary), onPressed: _page < _totalPages ? () { _page++; _loadData(); } : null),
          const SizedBox(width: 16),
          Text('الإجمالي: $_total', style: SdText.bodySm),
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

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: SdText.bodySm,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: const BorderSide(color: SdColors.cardEdge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: const BorderSide(color: SdColors.cardEdge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: const BorderSide(color: SdColors.primary, width: 1.5),
        ),
      );

  // بناء الشجرة
  List<InventoryCategory> _getRoots() => _cats.where((c) => c.parentCategoryId == null).toList();
  List<InventoryCategory> _getChildren(int parentId) => _cats.where((c) => c.parentCategoryId == parentId).toList();

  Future<void> _addEdit([InventoryCategory? cat]) async {
    final nameCtrl = TextEditingController(text: cat?.name ?? '');
    final nameEnCtrl = TextEditingController(text: cat?.nameEn ?? '');
    int? parentId = cat?.parentCategoryId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(cat == null ? 'إضافة تصنيف' : 'تعديل تصنيف'),
          content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, decoration: _dec('اسم التصنيف *')),
            const SizedBox(height: 10),
            TextField(controller: nameEnCtrl, decoration: _dec('الاسم بالإنجليزية')),
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              value: parentId,
              decoration: _dec('تصنيف أب'),
              items: [
                const DropdownMenuItem(value: null, child: Text('رئيسي (بدون أب)')),
                ..._cats.where((c) => c.id != cat?.id).map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) => setD(() => parentId = v),
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.primary, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)), onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  Future<void> _delete(InventoryCategory cat) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('حذف تصنيف'),
        content: Text('هل تريد حذف "${cat.name}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.danger, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    ));
    if (ok != true) return;
    try {
      await widget.api.deleteCategory(cat.id);
      widget.onChanged();
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(children: [
          const Icon(Icons.account_tree_rounded, color: SdColors.accent),
          const SizedBox(width: 8),
          const Expanded(child: Text('شجرة الأصناف')),
          IconButton(icon: const Icon(Icons.add_circle, color: SdColors.primary), tooltip: 'إضافة تصنيف', onPressed: () => _addEdit()),
        ]),
        content: SizedBox(
          width: 500,
          height: 400,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
              : _cats.isEmpty
                  ? const Center(child: SdEmptyState(title: 'لا توجد أصناف', icon: Icons.account_tree_rounded))
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
            color: depth == 0 ? SdColors.accentTint : SdColors.surfaceAlt,
            borderRadius: BorderRadius.circular(SdRadius.xs),
            border: Border.all(color: depth == 0 ? SdColors.accentTintEdge : SdColors.divider),
          ),
          child: Row(
            children: [
              Icon(
                children.isNotEmpty ? Icons.folder_rounded : Icons.label_rounded,
                size: 18,
                color: depth == 0 ? SdColors.accent : SdColors.muted,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(cat.name, style: TextStyle(fontFamily: SdText.family, fontSize: 13, fontWeight: depth == 0 ? FontWeight.w700 : FontWeight.w500, color: SdColors.ink))),
              if (cat.nameEn != null && cat.nameEn!.isNotEmpty)
                Text(cat.nameEn!, style: SdText.caption),
              const SizedBox(width: 8),
              InkWell(onTap: () => _addEdit(cat), child: const Icon(Icons.edit, size: 16, color: SdColors.primary)),
              const SizedBox(width: 6),
              InkWell(onTap: () => _delete(cat), child: const Icon(Icons.delete, size: 16, color: SdColors.danger)),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _addEdit()..toString(), // opens add with no parent preselected
                child: const Tooltip(message: 'إضافة فرعي', child: Icon(Icons.add, size: 16, color: SdColors.success)),
              ),
            ],
          ),
        ),
        ...children.map((child) => _buildTreeNode(child, depth + 1)),
      ],
    );
  }
}
