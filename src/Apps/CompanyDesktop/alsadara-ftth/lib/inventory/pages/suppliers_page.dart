import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
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
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(sup == null ? 'إضافة مورد' : 'تعديل مورد'),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(controller: nameCtrl, decoration: _dec('اسم المورد *')),
                    const SizedBox(height: 10),
                    TextField(controller: contactCtrl, decoration: _dec('الشخص المسؤول')),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: phoneCtrl, decoration: _dec('الهاتف'))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: emailCtrl, decoration: _dec('البريد الإلكتروني'))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(controller: addressCtrl, decoration: _dec('العنوان')),
                    const SizedBox(height: 10),
                    TextField(controller: taxCtrl, decoration: _dec('الرقم الضريبي')),
                    const SizedBox(height: 10),
                    TextField(controller: notesCtrl, maxLines: 2, decoration: _dec('ملاحظات')),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: SdColors.primary),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('حفظ')),
            ],
          ),
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
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف المورد "${sup.name}"؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: SdColors.danger),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('حذف')),
          ],
        ),
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
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'الموردين',
        actions: [
          SdAppBarAction(icon: Icons.add_rounded, label: 'إضافة مورد', onPressed: () => _showAddEditDialog()),
          SdAppBarAction(icon: Icons.refresh_rounded, label: 'تحديث', onPressed: _loadData),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchBar(),
          const SizedBox(height: SdSpace.sm),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchCtrl,
      style: SdText.body,
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو الهاتف...',
        hintStyle: SdText.bodySm,
        prefixIcon: const Icon(Icons.search, color: SdColors.faint),
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
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18, color: SdColors.faint),
                onPressed: () {
                  _searchCtrl.clear();
                  _loadData();
                },
              )
            : null,
      ),
      onSubmitted: (_) => _loadData(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    if (_error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل الموردين',
          message: _error,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: _loadData),
        ),
      );
    }
    if (_suppliers.isEmpty) {
      return Center(
        child: SdEmptyState(
          title: 'لا يوجد موردين',
          icon: Icons.local_shipping_outlined,
          action: SdButton(label: 'إضافة مورد', icon: Icons.add_rounded, onPressed: () => _showAddEditDialog()),
        ),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _suppliers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(_suppliers[i]),
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
              DataColumn(label: Text('المسؤول')),
              DataColumn(label: Text('الهاتف')),
              DataColumn(label: Text('البريد')),
              DataColumn(label: Text('عدد المشتريات'), numeric: true),
              DataColumn(label: Text('إجمالي المشتريات'), numeric: true),
              DataColumn(label: Text('إجراءات')),
            ],
            rows: [
              for (int i = 0; i < _suppliers.length; i++) _buildDataRow(_suppliers[i], i),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(Supplier sup, int index) {
    return DataRow(
      color: WidgetStateProperty.all(index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      cells: [
        DataCell(Text(sup.name)),
        DataCell(Text(sup.contactPerson ?? '-')),
        DataCell(Text(sup.phone ?? '-')),
        DataCell(Text(sup.email ?? '-')),
        DataCell(Text('${sup.purchaseOrdersCount ?? 0}')),
        DataCell(Text(fmtNullable(sup.totalPurchases))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
                icon: const Icon(Icons.edit, size: 20, color: SdColors.primary),
                tooltip: 'تعديل',
                onPressed: () => _showAddEditDialog(sup)),
            IconButton(
                icon: const Icon(Icons.delete, size: 20, color: SdColors.danger),
                tooltip: 'حذف',
                onPressed: () => _confirmDelete(sup)),
          ],
        )),
      ],
    );
  }

  Widget _buildCard(Supplier sup) {
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sup.name, style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          if ((sup.contactPerson ?? '').isNotEmpty) SdInfoRow(label: 'المسؤول', value: sup.contactPerson!),
          if ((sup.phone ?? '').isNotEmpty) SdInfoRow(label: 'الهاتف', value: sup.phone!, ltrValue: true),
          if ((sup.email ?? '').isNotEmpty) SdInfoRow(label: 'البريد', value: sup.email!, ltrValue: true),
          SdInfoRow(label: 'عدد المشتريات', value: '${sup.purchaseOrdersCount ?? 0}'),
          SdInfoRow(label: 'إجمالي المشتريات', value: fmtNullable(sup.totalPurchases)),
          const Divider(color: SdColors.divider, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(icon: const Icon(Icons.edit, size: 20, color: SdColors.primary), tooltip: 'تعديل', onPressed: () => _showAddEditDialog(sup)),
              IconButton(icon: const Icon(Icons.delete, size: 20, color: SdColors.danger), tooltip: 'حذف', onPressed: () => _confirmDelete(sup)),
            ],
          ),
        ],
      ),
    );
  }
}
