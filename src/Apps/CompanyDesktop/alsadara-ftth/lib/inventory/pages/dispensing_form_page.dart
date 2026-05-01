import 'package:flutter/material.dart';
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
  const DispensingFormPage({super.key, required this.companyId});

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

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _api.getWarehouses(companyId: widget.companyId),
        _api.getItems(companyId: widget.companyId, pageSize: 500),
        SadaraApiService.instance.get('/servicerequests/task-staff'),
      ]);
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
        _loading = false;
      });
      _addItem();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحميل البيانات: $e'), backgroundColor: Colors.red));
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
                    title: Text(item.name, style: TextStyle(fontSize: 13, color: alreadyAdded ? Colors.grey : null)),
                    subtitle: alreadyAdded ? const Text('مضاف مسبقاً', style: TextStyle(fontSize: 11, color: Colors.grey)) : null,
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف مادة واحدة على الأقل'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _saving = true);

    final data = {
      'companyId': widget.companyId,
      'technicianId': _selectedTechnicianId,
      'warehouseId': _selectedWarehouseId,
      'type': 0, // صرف
      'notes': _notesController.text.isEmpty ? null : _notesController.text,
      'items': validItems.map((e) => {
        'inventoryItemId': e.inventoryItemId,
        'quantity': int.tryParse(e.qtyController.text) ?? 0,
      }).toList(),
    };

    try {
      await _api.createDispensing(data: data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم صرف المواد بنجاح'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)), titleTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700), elevation: 0, title: const Text('صرف مواد')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    _buildItemsSection(),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 48,
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('حفظ', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                decoration: const InputDecoration(labelText: 'الفني *', border: OutlineInputBorder()),
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
                decoration: const InputDecoration(labelText: 'المستودع *', border: OutlineInputBorder()),
                validator: (v) => v == null ? 'اختر المستودع' : null,
                items: _warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                onChanged: (v) => setState(() => _selectedWarehouseId = v),
              ),
            ),
            // ملاحظات
            SizedBox(
              width: 400,
              child: TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(labelText: 'ملاحظات', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('المواد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _showMultiSelectDialog,
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: const Text('تحديد متعدد'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: _addItem,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة مادة'),
              ),
            ]),
            const SizedBox(height: 12),
            for (int i = 0; i < _items.length; i++) _buildItemRow(i),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final entry = _items[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text('${index + 1}.', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: DropdownButtonFormField<String>(
              value: entry.inventoryItemId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'المادة', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
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
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextFormField(
              controller: entry.qtyController,
              decoration: const InputDecoration(labelText: 'الكمية', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.delete_outline, color: _items.length > 1 ? Colors.red : Colors.grey),
            onPressed: _items.length > 1 ? () => _removeItem(index) : null,
          ),
        ],
      ),
    );
  }
}
