import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';

class SuppliersPage extends StatefulWidget {
  final String companyId;
  const SuppliersPage({super.key, required this.companyId});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<Supplier> _suppliers = [];

  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getSuppliers(
        companyId: widget.companyId,
        search: _searchCtrl.text.trim().isEmpty
            ? null
            : _searchCtrl.text.trim(),
      );
      final list = (res['data'] as List<dynamic>?) ?? [];
      _suppliers = list
          .map((e) => Supplier.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  // --------------- CRUD ---------------

  Future<void> _showAddEditDialog([Supplier? sup]) async {
    final nameCtrl = TextEditingController(text: sup?.name ?? '');
    final contactCtrl = TextEditingController(text: sup?.contactPerson ?? '');
    final phoneCtrl = TextEditingController(text: sup?.phone ?? '');
    final emailCtrl = TextEditingController(text: sup?.email ?? '');
    final addressCtrl = TextEditingController(text: sup?.address ?? '');
    final taxCtrl = TextEditingController(text: sup?.taxNumber ?? '');
    final notesCtrl = TextEditingController(text: sup?.notes ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(sup == null ? 'إضافة مورد' : 'تعديل مورد'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'اسم المورد *',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: contactCtrl,
                    decoration: const InputDecoration(
                        labelText: 'الشخص المسؤول',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          decoration: const InputDecoration(
                              labelText: 'الهاتف',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: emailCtrl,
                          decoration: const InputDecoration(
                              labelText: 'البريد الإلكتروني',
                              border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(
                        labelText: 'العنوان',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: taxCtrl,
                    decoration: const InputDecoration(
                        labelText: 'الرقم الضريبي',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حفظ')),
          ],
        );
      },
    );

    if (saved != true) return;
    if (nameCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('اسم المورد مطلوب')));
      }
      return;
    }

    final data = {
      'name': nameCtrl.text.trim(),
      'contactPerson': contactCtrl.text.trim().isEmpty
          ? null
          : contactCtrl.text.trim(),
      'phone':
          phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      'email':
          emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
      'address':
          addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
      'taxNumber':
          taxCtrl.text.trim().isEmpty ? null : taxCtrl.text.trim(),
      'notes':
          notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      'companyId': widget.companyId,
    };

    try {
      if (sup == null) {
        await _api.createSupplier(data: data);
      } else {
        await _api.updateSupplier(sup.id, data: data);
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  Future<void> _confirmDelete(Supplier sup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف المورد "${sup.name}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteSupplier(sup.id);
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
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), elevation: 0,
          title: const Text('الموردين'),
          actions: [
            IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'إضافة مورد',
                onPressed: () => _showAddEditDialog()),
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'تحديث',
                onPressed: _loadData),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'بحث بالاسم أو الهاتف...',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _loadData();
                  },
                )
              : null,
        ),
        onSubmitted: (_) => _loadData(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
                label: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_suppliers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('لا يوجد موردين',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.icon(
                onPressed: () => _showAddEditDialog(),
                icon: const Icon(Icons.add),
                label: const Text('إضافة مورد')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
          columns: const [
            DataColumn(label: Text('الاسم')),
            DataColumn(label: Text('المسؤول')),
            DataColumn(label: Text('الهاتف')),
            DataColumn(label: Text('البريد')),
            DataColumn(label: Text('عدد المشتريات'), numeric: true),
            DataColumn(label: Text('إجمالي المشتريات'), numeric: true),
            DataColumn(label: Text('إجراءات')),
          ],
          rows: _suppliers.map((sup) {
            return DataRow(cells: [
              DataCell(Text(sup.name)),
              DataCell(Text(sup.contactPerson ?? '-')),
              DataCell(Text(sup.phone ?? '-')),
              DataCell(Text(sup.email ?? '-')),
              DataCell(Text('${sup.purchaseOrdersCount ?? 0}')),
              DataCell(Text(
                  fmtNullable(sup.totalPurchases))),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      tooltip: 'تعديل',
                      onPressed: () => _showAddEditDialog(sup)),
                  IconButton(
                      icon: const Icon(Icons.delete,
                          size: 20, color: Colors.red),
                      tooltip: 'حذف',
                      onPressed: () => _confirmDelete(sup)),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
