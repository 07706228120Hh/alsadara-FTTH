import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
import '../services/inventory_api_service.dart';
import 'return_form_page.dart';

class ReturnsPage extends StatefulWidget {
  final String companyId;
  const ReturnsPage({super.key, required this.companyId});

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage>
    with SingleTickerProviderStateMixin {
  final _api = InventoryApiService.instance;
  late TabController _tabController;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _salesReturns = [];
  List<Map<String, dynamic>> _purchaseReturns = [];

  static const _statusLabels = {
    'Draft': 'مسودة',
    'Confirmed': 'مؤكد',
    'Cancelled': 'ملغي',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getReturns(companyId: widget.companyId, type: 'SalesReturn'),
        _api.getReturns(companyId: widget.companyId, type: 'PurchaseReturn'),
      ]);

      final srList = (results[0]['data'] as List<dynamic>?) ?? [];
      final prList = (results[1]['data'] as List<dynamic>?) ?? [];

      if (mounted) {
        setState(() {
          _salesReturns = srList.cast<Map<String, dynamic>>();
          _purchaseReturns = prList.cast<Map<String, dynamic>>();
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

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  List<Widget> _buildReturnActions(String id, String status) {
    final actions = <Widget>[];
    if (status == 'Draft') {
      actions.add(_returnActionBtn(Icons.check_circle_outline, 'تأكيد', SdColors.success, () => _confirmReturn(id)));
      actions.add(_returnActionBtn(Icons.cancel_outlined, 'إلغاء', SdColors.warning, () => _cancelReturn(id)));
      actions.add(_returnActionBtn(Icons.delete_outline, 'حذف', SdColors.danger, () => _deleteReturn(id)));
    }
    return actions;
  }

  Widget _returnActionBtn(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 20, color: color)),
      ),
    );
  }

  Future<void> _confirmReturn(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد المرتجع'),
          content: const Text('هل تريد تأكيد هذا المرتجع؟ سيتم تعديل المخزون تلقائياً.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.primary, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)), onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.confirmReturn(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأكيد المرتجع'), backgroundColor: SdColors.success));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  Future<void> _deleteReturn(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المرتجع'),
          content: const Text('هل تريد حذف هذا المرتجع نهائياً؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.danger, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteReturn(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المرتجع'), backgroundColor: SdColors.success));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  Future<void> _cancelReturn(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إلغاء المرتجع'),
          content: const Text('هل تريد إلغاء هذا المرتجع؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.danger, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)), onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء المرتجع')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.cancelReturn(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء المرتجع'), backgroundColor: SdColors.success));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  SdStatus _statusTone(String status) {
    switch (status) {
      case 'Confirmed':
        return SdStatus.success;
      case 'Cancelled':
        return SdStatus.danger;
      default:
        return SdStatus.neutral;
    }
  }

  Widget _statusChip(String status) {
    return SdStatusChip(_statusLabels[status] ?? status, status: _statusTone(status));
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'المرتجعات',
        actions: [
          SdAppBarAction(
            icon: Icons.add_rounded,
            label: 'مرتجع جديد',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReturnFormPage(
                    companyId: widget.companyId,
                    returnType: _tabController.index == 0
                        ? 'SalesReturn'
                        : 'PurchaseReturn',
                  ),
                ),
              ).then((_) => _loadData());
            },
          ),
        ],
        bottom: SdTabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'مرتجع مبيعات'),
            Tab(text: 'مرتجع مشتريات'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: SdSpace.sm),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (_error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل المرتجعات',
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

    return TabBarView(
      controller: _tabController,
      children: [
        _buildList(_salesReturns, 'لا توجد مرتجعات مبيعات'),
        _buildList(_purchaseReturns, 'لا توجد مرتجعات مشتريات'),
      ],
    );
  }

  Widget _buildList(List<Map<String, dynamic>> data, String emptyMsg) {
    if (data.isEmpty) {
      return Center(
        child: SdEmptyState(title: emptyMsg, icon: Icons.assignment_return_outlined),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: data.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(data[i]),
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
                  _HeaderCell('رقم المرتجع'),
                  _HeaderCell('التاريخ'),
                  _HeaderCell('الفاتورة الأصلية'),
                  _HeaderCell('المبلغ'),
                  _HeaderCell('الحالة'),
                  _HeaderCell('إجراءات'),
                ],
              ),
              for (var i = 0; i < data.length; i++) _dataRow(i, data[i]),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _dataRow(int i, Map<String, dynamic> m) {
    final status = (m['Status'] ?? m['status'] ?? '').toString();
    final rId = (m['Id'] ?? m['id'] ?? '').toString();
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _DataCell((m['ReturnNumber'] ?? m['returnNumber'] ?? '-').toString()),
        _DataCell(_formatDate((m['Date'] ?? m['date'] ?? '').toString())),
        _DataCell((m['InvoiceNumber'] ?? m['invoiceNumber'] ?? '-').toString()),
        _DataCell(fmtN(m['TotalAmount'] ?? m['totalAmount'] ?? m['Amount'] ?? m['amount'])),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Center(child: _statusChip(status)),
        ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _buildReturnActions(rId, status),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(Map<String, dynamic> m) {
    final status = (m['Status'] ?? m['status'] ?? '').toString();
    final rId = (m['Id'] ?? m['id'] ?? '').toString();
    final actions = _buildReturnActions(rId, status);
    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#${(m['ReturnNumber'] ?? m['returnNumber'] ?? '-')}',
                    style: SdText.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              _statusChip(status),
            ],
          ),
          const SizedBox(height: 4),
          SdInfoRow(label: 'التاريخ', value: _formatDate((m['Date'] ?? m['date'] ?? '').toString())),
          SdInfoRow(label: 'الفاتورة الأصلية', value: (m['InvoiceNumber'] ?? m['invoiceNumber'] ?? '-').toString()),
          SdInfoRow(label: 'المبلغ', value: fmtN(m['TotalAmount'] ?? m['totalAmount'] ?? m['Amount'] ?? m['amount'])),
          if (actions.isNotEmpty) ...[
            const Divider(color: SdColors.divider, height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
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
