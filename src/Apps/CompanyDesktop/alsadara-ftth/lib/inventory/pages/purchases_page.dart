import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';
import 'purchase_form_page.dart';

class PurchasesPage extends StatefulWidget {
  final String companyId;
  const PurchasesPage({super.key, required this.companyId});

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<PurchaseOrder> _orders = [];
  int _totalCount = 0;
  int _page = 1;
  final int _pageSize = 20;

  // Filters
  String? _statusFilter;
  String? _supplierFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  List<Supplier> _suppliers = [];

  static const _statusMap = {
    null: 'الكل',
    'Draft': 'مسودة',
    'Approved': 'معتمد',
    'PartiallyReceived': 'استلام جزئي',
    'Received': 'مستلم',
    'Cancelled': 'ملغي',
  };

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _loadData();
  }

  Future<void> _loadSuppliers() async {
    try {
      final res =
          await _api.getSuppliers(companyId: widget.companyId);
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _suppliers =
              list.map((e) => Supplier.fromJson(e as Map<String, dynamic>)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getPurchaseOrders(
        companyId: widget.companyId,
        status: _statusFilter,
        supplierId: _supplierFilter,
        from: _dateFrom?.toIso8601String().split('T').first,
        to: _dateTo?.toIso8601String().split('T').first,
        page: _page,
        pageSize: _pageSize,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _orders = list
              .map((e) =>
                  PurchaseOrder.fromJson(e as Map<String, dynamic>))
              .toList();
          _totalCount = res['totalCount'] as int? ?? _orders.length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  SdStatus _statusTone(String status) {
    switch (status) {
      case 'Approved':
        return SdStatus.info;
      case 'PartiallyReceived':
        return SdStatus.warning;
      case 'Received':
        return SdStatus.success;
      case 'Cancelled':
        return SdStatus.danger;
      default:
        return SdStatus.neutral;
    }
  }

  Widget _statusChip(String status) {
    final label = _statusMap[status] ?? status;
    return SdStatusChip(label, status: _statusTone(status));
  }

  List<Widget> _buildActions(PurchaseOrder order) {
    final actions = <Widget>[];

    // تعديل — فقط للمسودة والمعتمد
    if (order.status == 'Draft' || order.status == 'Approved') {
      actions.add(_actionBtn(Icons.edit_outlined, 'تعديل', SdColors.primary, () => _editOrder(order)));
    }

    // اعتماد — فقط للمسودة
    if (order.status == 'Draft') {
      actions.add(_actionBtn(Icons.check_circle_outline, 'اعتماد', SdColors.success, () => _approveOrder(order)));
    }

    // استلام — فقط للمعتمد أو استلام جزئي
    if (order.status == 'Approved' || order.status == 'PartiallyReceived') {
      actions.add(_actionBtn(Icons.inventory_2_outlined, 'استلام', SdColors.accent, () => _receiveOrder(order)));
    }

    // إلغاء — للمسودة والمعتمد والاستلام الجزئي
    if (order.status == 'Draft' || order.status == 'Approved' || order.status == 'PartiallyReceived') {
      actions.add(_actionBtn(Icons.cancel_outlined, 'إلغاء', SdColors.warning, () => _cancelOrder(order)));
    }

    // حذف — فقط للمسودة
    if (order.status == 'Draft') {
      actions.add(_actionBtn(Icons.delete_outline, 'حذف', SdColors.danger, () => _deleteOrder(order)));
    }

    return actions;
  }

  Future<void> _deleteOrder(PurchaseOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف أمر الشراء "${order.orderNumber}"؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
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
      // نستخدم cancel كحذف ناعم (soft delete)
      await _api.cancelPurchaseOrder(order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف'), backgroundColor: SdColors.success));
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
      }
    }
  }

  Widget _actionBtn(
      IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  void _editOrder(PurchaseOrder order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseFormPage(
          companyId: widget.companyId,
          existingOrder: order,
        ),
      ),
    ).then((_) => _loadData());
  }

  Future<void> _approveOrder(PurchaseOrder order) async {
    final confirmed = await _confirmDialog('اعتماد أمر الشراء', 'هل أنت متأكد من اعتماد أمر الشراء ${order.orderNumber}؟');
    if (!confirmed) return;
    try {
      await _api.approvePurchaseOrder(order.id);
      _showSnackBar('تم اعتماد أمر الشراء بنجاح');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الاعتماد: $e', isError: true);
    }
  }

  Future<void> _cancelOrder(PurchaseOrder order) async {
    final confirmed = await _confirmDialog('إلغاء أمر الشراء', 'هل أنت متأكد من إلغاء أمر الشراء ${order.orderNumber}؟');
    if (!confirmed) return;
    try {
      await _api.cancelPurchaseOrder(order.id);
      _showSnackBar('تم إلغاء أمر الشراء');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الإلغاء: $e', isError: true);
    }
  }

  Future<void> _receiveOrder(PurchaseOrder order) async {
    // For now, receive all remaining items
    final confirmed = await _confirmDialog('استلام أمر الشراء', 'هل تريد استلام كامل الأصناف المتبقية في أمر الشراء ${order.orderNumber}؟');
    if (!confirmed) return;
    try {
      // Fetch full order to get items
      final fullRes = await _api.getPurchaseOrder(order.id);
      final fullOrder = PurchaseOrder.fromJson(fullRes['data'] as Map<String, dynamic>? ?? fullRes);
      final receiveItems = (fullOrder.items ?? []).map((item) {
        return {
          'purchaseOrderItemId': item.id,
          'receivedQuantity': item.quantity - item.receivedQuantity,
        };
      }).where((m) => (m['receivedQuantity'] as int) > 0).toList();

      if (receiveItems.isEmpty) {
        _showSnackBar('لا توجد أصناف متبقية للاستلام');
        return;
      }
      await _api.receivePurchaseOrder(order.id, items: receiveItems);
      _showSnackBar('تم الاستلام بنجاح');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الاستلام: $e', isError: true);
    }
  }

  Future<bool> _confirmDialog(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: SdColors.primary),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('تأكيد')),
              ],
            ),
          ),
        ) ??
        false;
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? SdColors.danger : SdColors.success,
      ),
    );
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
      _page = 1;
      _loadData();
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: SdText.bodySm,
        filled: true,
        fillColor: SdColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'أوامر الشراء',
        actions: [
          SdAppBarAction(
            icon: Icons.add_rounded,
            label: 'أمر شراء جديد',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PurchaseFormPage(companyId: widget.companyId),
                ),
              ).then((_) => _loadData());
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilters(),
          const SizedBox(height: SdSpace.xs),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            value: _statusFilter,
            style: SdText.label,
            decoration: _dec('الحالة'),
            items: _statusMap.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              setState(() => _statusFilter = v);
              _page = 1;
              _loadData();
            },
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            value: _supplierFilter,
            isExpanded: true,
            style: SdText.label,
            decoration: _dec('المورد'),
            items: [
              const DropdownMenuItem(value: null, child: Text('الكل')),
              ..._suppliers.map((s) =>
                  DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) {
              setState(() => _supplierFilter = v);
              _page = 1;
              _loadData();
            },
          ),
        ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
          label: Text(_dateFrom != null ? 'من: ${_formatDate(_dateFrom!)}' : 'من تاريخ'),
          onPressed: () => _pickDate(true),
        ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
          label: Text(_dateTo != null ? 'إلى: ${_formatDate(_dateTo!)}' : 'إلى تاريخ'),
          onPressed: () => _pickDate(false),
        ),
        if (_dateFrom != null || _dateTo != null || _statusFilter != null || _supplierFilter != null)
          ActionChip(
            avatar: const Icon(Icons.clear, size: 18),
            label: const Text('مسح الفلاتر'),
            onPressed: () {
              setState(() {
                _statusFilter = null;
                _supplierFilter = null;
                _dateFrom = null;
                _dateTo = null;
              });
              _page = 1;
              _loadData();
            },
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (_error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل أوامر الشراء',
          message: _error,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(
            label: 'إعادة المحاولة',
            icon: Icons.refresh_rounded,
            kind: SdButtonKind.secondary,
            onPressed: _loadData,
          ),
        ),
      );
    }
    if (_orders.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد أوامر شراء', icon: Icons.shopping_cart_outlined),
      );
    }

    final totalPages = (_totalCount / _pageSize).ceil();

    return Column(
      children: [
        Expanded(child: _buildListOrTable()),
        if (totalPages > 1) _buildPager(totalPages),
      ],
    );
  }

  Widget _buildListOrTable() {
    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(_orders[i]),
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
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              const TableRow(
                decoration: BoxDecoration(color: SdColors.primary),
                children: [
                  _HeaderCell('رقم الأمر'),
                  _HeaderCell('المورد'),
                  _HeaderCell('المستودع'),
                  _HeaderCell('التاريخ'),
                  _HeaderCell('المبلغ'),
                  _HeaderCell('الحالة'),
                  _HeaderCell('عدد الأصناف'),
                  _HeaderCell('إجراءات'),
                ],
              ),
              for (var i = 0; i < _orders.length; i++) _dataRow(i, _orders[i]),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _dataRow(int i, PurchaseOrder o) {
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _DataCell(o.orderNumber),
        _DataCell(o.supplierName ?? '-'),
        _DataCell(o.warehouseName ?? '-'),
        _DataCell(_formatDate(o.orderDate)),
        _DataCell(fmtN(o.netAmount)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Center(child: _statusChip(o.status)),
        ),
        _DataCell('${o.itemsCount ?? o.items?.length ?? 0}'),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Row(mainAxisSize: MainAxisSize.min, children: _buildActions(o)),
        ),
      ],
    );
  }

  Widget _buildCard(PurchaseOrder o) {
    final actions = _buildActions(o);
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#${o.orderNumber}',
                    style: SdText.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _statusChip(o.status),
            ],
          ),
          const SizedBox(height: 4),
          SdInfoRow(label: 'المورد', value: o.supplierName ?? '-'),
          SdInfoRow(label: 'المستودع', value: o.warehouseName ?? '-'),
          SdInfoRow(label: 'التاريخ', value: _formatDate(o.orderDate)),
          SdInfoRow(label: 'المبلغ', value: fmtN(o.netAmount)),
          SdInfoRow(label: 'عدد الأصناف', value: '${o.itemsCount ?? o.items?.length ?? 0}'),
          if (actions.isNotEmpty) ...[
            const Divider(color: SdColors.divider, height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ],
      ),
    );
  }

  Widget _buildPager(int totalPages) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_right, color: SdColors.primary),
            onPressed: _page > 1
                ? () {
                    setState(() => _page--);
                    _loadData();
                  }
                : null,
          ),
          Text('صفحة $_page من $totalPages', style: SdText.label),
          IconButton(
            icon: const Icon(Icons.chevron_left, color: SdColors.primary),
            onPressed: _page < totalPages
                ? () {
                    setState(() => _page++);
                    _loadData();
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  const _HeaderCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontFamily: SdText.family,
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: Colors.white),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  const _DataCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontFamily: SdText.family,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: SdColors.ink),
      ),
    );
  }
}
