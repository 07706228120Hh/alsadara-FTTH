import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';

class WarehousesPage extends StatefulWidget {
  final String companyId;
  const WarehousesPage({super.key, required this.companyId});

  @override
  State<WarehousesPage> createState() => _WarehousesPageState();
}

class _WarehousesPageState extends State<WarehousesPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<Warehouse> _warehouses = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getWarehouses(companyId: widget.companyId);
      final list = (res['data'] as List<dynamic>?) ?? [];
      _warehouses =
          list.map((e) => Warehouse.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  // --------------- CRUD dialogs ---------------

  Future<void> _showAddEditDialog([Warehouse? wh]) async {
    final nameCtrl = TextEditingController(text: wh?.name ?? '');
    final codeCtrl = TextEditingController(text: wh?.code ?? '');
    final addressCtrl = TextEditingController(text: wh?.address ?? '');
    final descCtrl = TextEditingController(text: wh?.description ?? '');
    bool isDefault = wh?.isDefault ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(wh == null ? 'إضافة مستودع' : 'تعديل مستودع'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'اسم المستودع *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الرمز',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addressCtrl,
                        decoration: const InputDecoration(
                          labelText: 'العنوان',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'الوصف',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('مستودع افتراضي'),
                        value: isDefault,
                        onChanged: (v) =>
                            setDialogState(() => isDefault = v ?? false),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) return;
    if (nameCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اسم المستودع مطلوب')),
        );
      }
      return;
    }

    final data = {
      'name': nameCtrl.text.trim(),
      'code': codeCtrl.text.trim().isEmpty ? null : codeCtrl.text.trim(),
      'address':
          addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
      'description':
          descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
      'isDefault': isDefault,
      'companyId': widget.companyId,
    };

    try {
      if (wh == null) {
        final result = await _api.createWarehouse(data: data);
        debugPrint('createWarehouse result: $result');
      } else {
        await _api.updateWarehouse(wh.id, data: data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم الحفظ بنجاح'), backgroundColor: Colors.green),
        );
      }
      _loadData();
    } catch (e) {
      debugPrint('createWarehouse error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDelete(Warehouse wh) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف المستودع "${wh.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.deleteWarehouse(wh.id);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  // --------------- Build ---------------

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)), titleTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700), elevation: 0,
          title: const Text('المستودعات'),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'إضافة مستودع',
              onPressed: () => _showAddEditDialog(),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadData,
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_warehouses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warehouse_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('لا توجد مستودعات',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة مستودع'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
          headingRowColor:
              WidgetStateProperty.all(Colors.grey.shade100),
          columns: const [
            DataColumn(label: Text('الرمز')),
            DataColumn(label: Text('الاسم')),
            DataColumn(label: Text('العنوان')),
            DataColumn(label: Text('المسؤول')),
            DataColumn(label: Text('الحالة')),
            DataColumn(label: Text('إجراءات')),
          ],
          rows: _warehouses.map((wh) {
            return DataRow(cells: [
              DataCell(Text(wh.code ?? '-')),
              DataCell(Text(wh.name)),
              DataCell(Text(wh.address ?? '-')),
              DataCell(Text(wh.managerUserName ?? '-')),
              DataCell(
                Chip(
                  label: Text(
                    wh.isActive ? 'نشط' : 'غير نشط',
                    style: TextStyle(
                      color: wh.isActive ? Colors.green.shade800 : Colors.red.shade800,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor:
                      wh.isActive ? Colors.green.shade50 : Colors.red.shade50,
                  side: BorderSide.none,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    tooltip: 'تعديل',
                    onPressed: () => _showAddEditDialog(wh),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.delete, size: 20, color: Colors.red),
                    tooltip: 'حذف',
                    onPressed: () => _confirmDelete(wh),
                  ),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
