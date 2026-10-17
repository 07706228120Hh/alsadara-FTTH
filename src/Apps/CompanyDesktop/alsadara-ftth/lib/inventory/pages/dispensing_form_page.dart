import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';
import '../../services/sadara_api_service.dart';

class _DispenseItemEntry {
  String? inventoryItemId;
  String? itemName;
  final TextEditingController qtyController = TextEditingController();
  void dispose() => qtyController.dispose();
}

class DispensingFormPage extends StatefulWidget {
  final String companyId;
  final String? editDispensingId;
  const DispensingFormPage({super.key, required this.companyId, this.editDispensingId});

  @override
  State<DispensingFormPage> createState() => _DispensingFormPageState();
}

class _DispensingFormPageState extends State<DispensingFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;

  List<Warehouse> _warehouses = [];
  List<InventoryItem> _inventoryItems = [];
  List<Map<String, dynamic>> _staffList = [];

  String? _selectedWarehouseId;
  String? _selectedTechnicianId;
  final _notesController = TextEditingController();
  List<_DispenseItemEntry> _items = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final item in _items) { item.dispose(); }
    super.dispose();
  }

  bool get _isEdit => widget.editDispensingId != null;

  Future<void> _loadData() async {
    try {
      final futures = <Future>[
        _api.getWarehouses(companyId: widget.companyId),
        _api.getItems(companyId: widget.companyId, pageSize: 500),
        SadaraApiService.instance.get('/servicerequests/task-staff'),
      ];
      if (_isEdit) {
        futures.add(_api.getDispensing(widget.editDispensingId!));
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _warehouses = (results[0]['data'] as List? ?? []).map((e) => Warehouse.fromJson(e as Map<String, dynamic>)).toList();
        _inventoryItems = (results[1]['data'] as List? ?? []).map((e) => InventoryItem.fromJson(e as Map<String, dynamic>)).toList();
        // الموظفين — data قد يكون {leaders:[], technicians:[]} أو مباشرة List
        final staffData = results[2]['data'];
        List staffRaw;
        if (staffData is List) {
          staffRaw = staffData;
        } else if (staffData is Map) {
          staffRaw = staffData['technicians'] as List? ?? staffData['leaders'] as List? ?? [];
        } else {
          staffRaw = [];
        }
        _staffList = staffRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        // ── تعبئة البيانات في وضع التعديل ──
        if (_isEdit && results.length > 3) {
          final editData = results[3] as Map<String, dynamic>;
          final dispensing = TechnicianDispensingModel.fromJson(
              editData['data'] as Map<String, dynamic>? ?? editData);
          _selectedTechnicianId = dispensing.technicianId;
          _selectedWarehouseId = dispensing.warehouseId;
          _notesController.text = dispensing.notes ?? '';
          // تعبئة المواد
          if (dispensing.items != null && dispensing.items!.isNotEmpty) {
            for (final item in dispensing.items!) {
              final entry = _DispenseItemEntry()
                ..inventoryItemId = item.inventoryItemId
                ..itemName = item.itemName;
              entry.qtyController.text = item.quantity.toString();
              _items.add(entry);
            }
          }
        }

        _loading = false;
      });
      if (!_isEdit) _addItem();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحميل البيانات: $e'), backgroundColor: SdColors.danger));
      }
    }
  }

  void _addItem() => setState(() => _items.add(_DispenseItemEntry()));

  void _removeItem(int i) {
    if (_items.length <= 1) return;
    setState(() { _items[i].dispose(); _items.removeAt(i); });
  }

  // تحديد متعدد
  Future<void> _showMultiSelectDialog() async {
    final selected = <String>{};
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('اختيار مواد متعددة'),
            content: SizedBox(
              width: 400, height: 400,
              child: ListView(
                children: _inventoryItems.map((item) {
                  final alreadyAdded = _items.any((e) => e.inventoryItemId == item.id);
                  return CheckboxListTile(
                    value: selected.contains(item.id) || alreadyAdded,
                    enabled: !alreadyAdded,
                    activeColor: SdColors.primary,
                    title: Text(item.name,
                        style: TextStyle(
                            fontFamily: SdText.family,
                            fontSize: 13,
                            color: alreadyAdded ? SdColors.faint : SdColors.ink)),
                    subtitle: alreadyAdded
                        ? const Text('مضاف مسبقاً',
                            style: TextStyle(
                                fontFamily: SdText.family, fontSize: 11.5, color: SdColors.faint))
                        : null,
                    dense: true,
                    onChanged: alreadyAdded ? null : (v) => setD(() {
                      if (v == true) selected.add(item.id); else selected.remove(item.id);
                    }),
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: SdColors.primary),
                onPressed: selected.isEmpty ? null : () {
                  for (final id in selected) {
                    final item = _inventoryItems.firstWhere((i) => i.id == id);
                    final entry = _DispenseItemEntry()
                      ..inventoryItemId = item.id
                      ..itemName = item.name;
                    _items.add(entry);
                  }
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: Text('إضافة ${selected.length} مادة'),
              ),
            ],
          ),
        );
      }),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final validItems = _items.where((e) => e.inventoryItemId != null).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف مادة واحدة على الأقل'), backgroundColor: SdColors.warning));
      return;
    }
    // التحقق من أن كل مادة لديها كمية > 0
    final zeroQtyItems = validItems.where((e) => (int.tryParse(e.qtyController.text) ?? 0) <= 0).toList();
    if (zeroQtyItems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل كمية صحيحة لكل مادة'), backgroundColor: SdColors.warning));
      return;
    }
    setState(() => _saving = true);

    final itemsData = validItems.map((e) => {
      'inventoryItemId': e.inventoryItemId,
      'quantity': int.tryParse(e.qtyController.text) ?? 0,
    }).toList();

    try {
      if (_isEdit) {
        // تعديل
        await _api.updateDispensing(widget.editDispensingId!, data: {
          'technicianId': _selectedTechnicianId,
          'warehouseId': _selectedWarehouseId,
          'notes': _notesController.text.isEmpty ? null : _notesController.text,
          'items': itemsData,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تعديل سند الصرف بنجاح'), backgroundColor: SdColors.success));
          Navigator.pop(context);
        }
      } else {
        // إنشاء جديد
        await _api.createDispensing(data: {
          'companyId': widget.companyId,
          'technicianId': _selectedTechnicianId,
          'warehouseId': _selectedWarehouseId,
          'type': 0, // صرف
          'notes': _notesController.text.isEmpty ? null : _notesController.text,
          'items': itemsData,
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم صرف المواد بنجاح'), backgroundColor: SdColors.success));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: SdColors.danger));
      }
    }
  }

  InputDecoration _dec(String? label, {bool dense = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: SdText.bodySm,
      filled: true,
      fillColor: SdColors.surface,
      isDense: dense,
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : null,
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

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      maxWidth: SdSpace.formMax,
      appBar: SdAppBar(title: _isEdit ? 'تعديل سند صرف' : 'صرف مواد'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildHeader(),
                  const SizedBox(height: SdSpace.lg),
                  _buildItemsSection(),
                  const SizedBox(height: SdSpace.xl),
                  _buildSaveButton(),
                  const SizedBox(height: SdSpace.md),
                ],
              ),
            ),
    );
  }

  Widget _buildSaveButton() {
    if (_saving) {
      return Opacity(
        opacity: .7,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SdRadius.md),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SdColors.primaryMid, SdColors.primary],
            ),
            boxShadow: const [BoxShadow(color: SdColors.primaryEdge, offset: Offset(0, 6))],
          ),
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
          ),
        ),
      );
    }
    return SdButton(
      label: _isEdit ? 'حفظ التعديلات' : 'حفظ',
      icon: Icons.save_rounded,
      expand: true,
      onPressed: _save,
    );
  }

  Widget _buildHeader() {
    return SdCard(
      title: 'بيانات الصرف',
      icon: Icons.outbox_rounded,
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: [
          // الفني (dropdown من الموظفين)
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              value: _selectedTechnicianId,
              isExpanded: true,
              style: SdText.label,
              decoration: _dec('الفني *'),
              validator: (v) => v == null ? 'اختر الفني' : null,
              items: _staffList.map((s) {
                final id = (s['Id'] ?? s['id'])?.toString() ?? '';
                final name = (s['Name'] ?? s['name'])?.toString() ?? '';
                final role = (s['Role'] ?? s['role'])?.toString() ?? '';
                return DropdownMenuItem(value: id, child: Text('$name${role.isNotEmpty ? " ($role)" : ""}', overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (v) => setState(() => _selectedTechnicianId = v),
            ),
          ),
          // المستودع
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              value: _selectedWarehouseId,
              isExpanded: true,
              style: SdText.label,
              decoration: _dec('المستودع *'),
              validator: (v) => v == null ? 'اختر المستودع' : null,
              items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _selectedWarehouseId = v),
            ),
          ),
          // ملاحظات
          SizedBox(
            width: 400,
            child: TextFormField(
              controller: _notesController,
              style: SdText.label,
              decoration: _dec('ملاحظات'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    final phone = context.sd.isPhone;
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const SdSectionHeader(title: 'المواد'),
            const Spacer(),
            _toolbarBtn(Icons.checklist_rounded, 'تحديد متعدد', _showMultiSelectDialog),
            const SizedBox(width: 8),
            _toolbarBtn(Icons.add, 'إضافة مادة', _addItem),
          ]),
          const SizedBox(height: 12),
          for (int i = 0; i < _items.length; i++)
            phone ? _buildItemCardPhone(i) : _buildItemRow(i),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, String label, VoidCallback onTap) {
    return SdRaised(
      onTap: onTap,
      semanticLabel: label,
      radius: SdRadius.sm,
      depth: 3,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: SdColors.surfaceAlt,
      edgeColor: SdColors.cardEdge,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: SdColors.primary),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: SdColors.primary)),
        ],
      ),
    );
  }

  Widget _itemDropdown(_DispenseItemEntry entry, int index) => DropdownButtonFormField<String>(
        value: entry.inventoryItemId,
        isExpanded: true,
        style: SdText.label,
        decoration: _dec('المادة', dense: true),
        items: _inventoryItems.map((item) => DropdownMenuItem(value: item.id, child: Text(item.name, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) {
          setState(() {
            entry.inventoryItemId = v;
            final found = _inventoryItems.where((i) => i.id == v);
            if (found.isNotEmpty) entry.itemName = found.first.name;
            // سطر جديد تلقائي
            if (index == _items.length - 1) _addItem();
          });
        },
      );

  Widget _qtyField(_DispenseItemEntry entry) => TextFormField(
        controller: entry.qtyController,
        style: SdText.label,
        decoration: _dec('الكمية', dense: true),
        keyboardType: TextInputType.number,
      );

  Widget _buildItemRow(int index) {
    final entry = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${index + 1}.', style: SdText.label),
          ),
          Expanded(flex: 4, child: _itemDropdown(entry, index)),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: _qtyField(entry)),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.delete_outline, color: _items.length > 1 ? SdColors.danger : SdColors.faint),
            onPressed: _items.length > 1 ? () => _removeItem(index) : null,
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }

  Widget _buildItemCardPhone(int index) {
    final entry = _items[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(SdSpace.sm),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${index + 1}.', style: SdText.label),
              const SizedBox(width: 6),
              Expanded(child: _itemDropdown(entry, index)),
              IconButton(
                icon: Icon(Icons.delete_outline, color: _items.length > 1 ? SdColors.danger : SdColors.faint),
                onPressed: _items.length > 1 ? () => _removeItem(index) : null,
                tooltip: 'حذف',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _qtyField(entry),
        ],
      ),
    );
  }
}
