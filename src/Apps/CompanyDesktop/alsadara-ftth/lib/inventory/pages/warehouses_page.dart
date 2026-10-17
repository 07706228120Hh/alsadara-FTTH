import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
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

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: SdText.bodySm,
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
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(wh == null ? 'إضافة مستودع' : 'تعديل مستودع'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(controller: nameCtrl, decoration: _dec('اسم المستودع *')),
                        const SizedBox(height: 12),
                        TextField(controller: codeCtrl, decoration: _dec('الرمز')),
                        const SizedBox(height: 12),
                        TextField(controller: addressCtrl, decoration: _dec('العنوان')),
                        const SizedBox(height: 12),
                        TextField(controller: descCtrl, maxLines: 2, decoration: _dec('الوصف')),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          title: const Text('مستودع افتراضي'),
                          activeColor: SdColors.primary,
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
                    style: FilledButton.styleFrom(backgroundColor: SdColors.primary),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('حفظ'),
                  ),
                ],
              ),
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
          const SnackBar(content: Text('تم الحفظ بنجاح'), backgroundColor: SdColors.success),
        );
      }
      _loadData();
    } catch (e) {
      debugPrint('createWarehouse error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحفظ: $e'), backgroundColor: SdColors.danger),
        );
      }
    }
  }

  Future<void> _confirmDelete(Warehouse wh) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف المستودع "${wh.name}"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SdColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
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
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'المستودعات',
        actions: [
          SdAppBarAction(icon: Icons.add_rounded, label: 'إضافة مستودع', onPressed: () => _showAddEditDialog()),
          SdAppBarAction(icon: Icons.refresh_rounded, label: 'تحديث', onPressed: _loadData),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (_error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل المستودعات',
          message: _error,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: _loadData),
        ),
      );
    }
    if (_warehouses.isEmpty) {
      return Center(
        child: SdEmptyState(
          title: 'لا توجد مستودعات',
          icon: Icons.warehouse_outlined,
          action: SdButton(label: 'إضافة مستودع', icon: Icons.add_rounded, onPressed: () => _showAddEditDialog()),
        ),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _warehouses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(_warehouses[i]),
      );
    }

    return SingleChildScrollView(
      child: SizedBox(
        width: double.infinity,
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
              DataColumn(label: Text('الرمز')),
              DataColumn(label: Text('الاسم')),
              DataColumn(label: Text('العنوان')),
              DataColumn(label: Text('المسؤول')),
              DataColumn(label: Text('الحالة')),
              DataColumn(label: Text('إجراءات')),
            ],
            rows: [
              for (int i = 0; i < _warehouses.length; i++) _buildDataRow(_warehouses[i], i),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(Warehouse wh, int index) {
    return DataRow(
      color: WidgetStateProperty.all(index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      cells: [
        DataCell(Text(wh.code ?? '-')),
        DataCell(Text(wh.name)),
        DataCell(Text(wh.address ?? '-')),
        DataCell(Text(wh.managerUserName ?? '-')),
        DataCell(SdStatusChip(wh.isActive ? 'نشط' : 'غير نشط',
            status: wh.isActive ? SdStatus.success : SdStatus.danger)),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, size: 20, color: SdColors.primary),
              tooltip: 'تعديل',
              onPressed: () => _showAddEditDialog(wh),
            ),
            IconButton(
              icon: const Icon(Icons.delete, size: 20, color: SdColors.danger),
              tooltip: 'حذف',
              onPressed: () => _confirmDelete(wh),
            ),
          ],
        )),
      ],
    );
  }

  Widget _buildCard(Warehouse wh) {
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(wh.name, style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SdStatusChip(wh.isActive ? 'نشط' : 'غير نشط',
                  status: wh.isActive ? SdStatus.success : SdStatus.danger),
            ],
          ),
          if ((wh.code ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('الرمز: ${wh.code}', style: SdText.caption),
          ],
          const SizedBox(height: 4),
          SdInfoRow(label: 'العنوان', value: wh.address ?? '-'),
          SdInfoRow(label: 'المسؤول', value: wh.managerUserName ?? '-'),
          const Divider(color: SdColors.divider, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(icon: const Icon(Icons.edit, size: 20, color: SdColors.primary), tooltip: 'تعديل', onPressed: () => _showAddEditDialog(wh)),
              IconButton(icon: const Icon(Icons.delete, size: 20, color: SdColors.danger), tooltip: 'حذف', onPressed: () => _confirmDelete(wh)),
            ],
          ),
        ],
      ),
    );
  }
}
