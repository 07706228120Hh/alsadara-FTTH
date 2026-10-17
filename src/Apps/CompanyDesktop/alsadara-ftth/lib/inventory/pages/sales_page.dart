import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';
import 'sale_form_page.dart';

class SalesPage extends StatefulWidget {
  final String companyId;
  const SalesPage({super.key, required this.companyId});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<SalesOrder> _orders = [];
  int _totalCount = 0;
  int _page = 1;
  final int _pageSize = 20;

  String? _statusFilter;
  DateTime? _dateFrom;
  DateTime? _dateTo;

  static const _statusMap = {
    null: 'الكل',
    'Draft': 'مسودة',
    'Confirmed': 'مؤكد',
    'Delivered': 'تم التسليم',
    'Cancelled': 'ملغي',
  };

  static const _paymentLabels = {
    'Cash': 'نقدي',
    'BankTransfer': 'تحويل بنكي',
    'ZainCash': 'زين كاش',
  };

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
      final res = await _api.getSalesOrders(
        companyId: widget.companyId,
        status: _statusFilter,
        from: _dateFrom?.toIso8601String().split('T').first,
        to: _dateTo?.toIso8601String().split('T').first,
        page: _page,
        pageSize: _pageSize,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _orders = list
              .map((e) => SalesOrder.fromJson(e as Map<String, dynamic>))
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
      case 'Confirmed':
        return SdStatus.success;
      case 'Delivered':
        return SdStatus.info;
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

  List<Widget> _buildActions(SalesOrder order) {
    final actions = <Widget>[];

    // تعديل — فقط للمسودة
    if (order.status == 'Draft') {
      actions.add(_actionBtn(Icons.edit_outlined, 'تعديل', SdColors.primary, () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => SaleFormPage(companyId: widget.companyId),
        )).then((_) => _loadData());
      }));
    }

    // تأكيد — فقط للمسودة
    if (order.status == 'Draft') {
      actions.add(_actionBtn(Icons.check_circle_outline, 'تأكيد', SdColors.success,
          () => _confirmOrder(order)));
    }

    // إلغاء — للمسودة والمؤكد
    if (order.status == 'Draft' || order.status == 'Confirmed') {
      actions.add(_actionBtn(Icons.cancel_outlined, 'إلغاء', SdColors.danger,
          () => _cancelOrder(order)));
    }

    return actions;
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

  Future<void> _confirmOrder(SalesOrder order) async {
    final ok = await _confirmDialog(
        'تأكيد عملية البيع', 'هل أنت متأكد من تأكيد عملية البيع ${order.orderNumber}؟');
    if (!ok) return;
    try {
      await _api.confirmSalesOrder(order.id);
      _showSnackBar('تم تأكيد عملية البيع');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل التأكيد: $e', isError: true);
    }
  }

  Future<void> _cancelOrder(SalesOrder order) async {
    final ok = await _confirmDialog(
        'إلغاء عملية البيع', 'هل أنت متأكد من إلغاء عملية البيع ${order.orderNumber}؟');
    if (!ok) return;
    try {
      await _api.cancelSalesOrder(order.id);
      _showSnackBar('تم إلغاء عملية البيع');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الإلغاء: $e', isError: true);
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
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء')),
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
        title: 'المبيعات',
        actions: [
          SdAppBarAction(
            icon: Icons.add_rounded,
            label: 'بيع جديد',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SaleFormPage(companyId: widget.companyId),
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
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
          label: Text(
              _dateFrom != null ? 'من: ${_formatDate(_dateFrom!)}' : 'من تاريخ'),
          onPressed: () => _pickDate(true),
        ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
          label: Text(
              _dateTo != null ? 'إلى: ${_formatDate(_dateTo!)}' : 'إلى تاريخ'),
          onPressed: () => _pickDate(false),
        ),
        if (_dateFrom != null || _dateTo != null || _statusFilter != null)
          ActionChip(
            avatar: const Icon(Icons.clear, size: 18),
            label: const Text('مسح الفلاتر'),
            onPressed: () {
              setState(() {
                _statusFilter = null;
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
          title: 'تعذّر تحميل المبيعات',
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
        child: SdEmptyState(title: 'لا توجد عمليات بيع', icon: Icons.point_of_sale_outlined),
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
                  _HeaderCell('رقم العملية'),
                  _HeaderCell('العميل'),
                  _HeaderCell('المستودع'),
                  _HeaderCell('التاريخ'),
                  _HeaderCell('المبلغ'),
                  _HeaderCell('طريقة الدفع'),
                  _HeaderCell('الحالة'),
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

  TableRow _dataRow(int i, SalesOrder o) {
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _DataCell(o.orderNumber),
        _DataCell(o.customerName ?? '-'),
        _DataCell(o.warehouseName ?? '-'),
        _DataCell(_formatDate(o.orderDate)),
        _DataCell(fmtN(o.netAmount)),
        _DataCell(_paymentLabels[o.paymentMethod] ?? o.paymentMethod ?? '-'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Center(child: _statusChip(o.status)),
        ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Row(mainAxisSize: MainAxisSize.min, children: _buildActions(o)),
        ),
      ],
    );
  }

  Widget _buildCard(SalesOrder o) {
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
          SdInfoRow(label: 'العميل', value: o.customerName ?? '-'),
          SdInfoRow(label: 'المستودع', value: o.warehouseName ?? '-'),
          SdInfoRow(label: 'التاريخ', value: _formatDate(o.orderDate)),
          SdInfoRow(label: 'المبلغ', value: fmtN(o.netAmount)),
          SdInfoRow(label: 'طريقة الدفع', value: _paymentLabels[o.paymentMethod] ?? o.paymentMethod ?? '-'),
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
