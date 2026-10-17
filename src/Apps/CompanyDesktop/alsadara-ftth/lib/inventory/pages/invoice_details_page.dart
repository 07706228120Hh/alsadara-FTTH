import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../services/inventory_api_service.dart';
import 'voucher_form_page.dart';
import 'return_form_page.dart';

class InvoiceDetailsPage extends StatefulWidget {
  final String companyId;
  final String invoiceId;

  const InvoiceDetailsPage({
    super.key,
    required this.companyId,
    required this.invoiceId,
  });

  @override
  State<InvoiceDetailsPage> createState() => _InvoiceDetailsPageState();
}

class _InvoiceDetailsPageState extends State<InvoiceDetailsPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  static const _typeLabels = {
    'Sales': 'فاتورة مبيعات',
    'Purchase': 'فاتورة مشتريات',
  };

  static const _statusLabels = {
    'Draft': 'مسودة',
    'Confirmed': 'مؤكدة',
    'Cancelled': 'ملغاة',
  };

  static const _paymentLabels = {
    'Cash': 'نقدي',
    'BankTransfer': 'تحويل بنكي',
    'ZainCash': 'زين كاش',
    'Credit': 'آجل',
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
      final res = await _api.getInvoice(widget.invoiceId);
      if (mounted) {
        setState(() {
          _data = res['data'] as Map<String, dynamic>? ?? res;
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

  String _val(String key) {
    final v = _data[key] ?? _data[key[0].toLowerCase() + key.substring(1)];
    return v?.toString() ?? '-';
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
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

  Future<void> _confirmInvoice() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('تأكيد الفاتورة'),
              content: const Text('هل أنت متأكد من تأكيد هذه الفاتورة؟'),
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
    if (!ok) return;
    try {
      await _api.confirmInvoice(widget.invoiceId);
      _showSnackBar('تم تأكيد الفاتورة');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل التأكيد: $e', isError: true);
    }
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

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      maxWidth: SdSpace.formMax,
      appBar: const SdAppBar(title: 'تفاصيل الفاتورة'),
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
          title: 'تعذّر تحميل الفاتورة',
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

    final status = (_data['Status'] ?? _data['status'] ?? '').toString();
    final type = (_data['Type'] ?? _data['type'] ?? '').toString();
    final items = (_data['Items'] ?? _data['items'] ?? []) as List<dynamic>;
    final vouchers =
        (_data['Vouchers'] ?? _data['vouchers'] ?? []) as List<dynamic>;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // رأس الفاتورة
        SdCard(
          title: 'بيانات الفاتورة',
          icon: Icons.description_rounded,
          trailing: _statusChip(status),
          child: Column(
            children: [
              SdInfoRow(label: 'رقم الفاتورة', value: _val('InvoiceNumber')),
              SdInfoRow(label: 'نوع الفاتورة', value: _typeLabels[type] ?? type),
              SdInfoRow(label: 'التاريخ', value: _formatDate(_val('InvoiceDate'))),
              SdInfoRow(
                  label: 'العميل/المورد',
                  value: (_data['EntityName'] ?? _data['entityName'] ?? '-').toString()),
              SdInfoRow(
                  label: 'طريقة الدفع',
                  value: _paymentLabels[_val('PaymentMethod')] ?? _val('PaymentMethod')),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.lg),

        // المواد
        _buildItemsSection(items),
        const SizedBox(height: SdSpace.lg),

        // المجاميع
        SdCard(
          title: 'المجاميع',
          icon: Icons.calculate_rounded,
          child: Column(
            children: [
              _totalRow('المجموع الفرعي', _val('SubTotal')),
              _totalRow('الخصم', _val('TotalDiscount')),
              _totalRow('الضريبة', _val('TaxAmount')),
              const Divider(height: 20, color: SdColors.divider),
              _totalRow('الصافي', _val('NetAmount'), bold: true),
              _totalRow('المدفوع', _val('PaidAmount')),
              _totalRow('المتبقي', _val('RemainingAmount'), bold: true),
            ],
          ),
        ),
        const SizedBox(height: SdSpace.lg),

        // أزرار الإجراءات
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            if (status == 'Draft')
              SdButton(
                label: 'تأكيد الفاتورة',
                icon: Icons.check_circle_outline,
                onPressed: _confirmInvoice,
              ),
            SdButton(
              label: 'إنشاء مرتجع',
              icon: Icons.assignment_return,
              kind: SdButtonKind.secondary,
              onPressed: () {
                final returnType =
                    type == 'Sales' ? 'SalesReturn' : 'PurchaseReturn';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReturnFormPage(
                      companyId: widget.companyId,
                      returnType: returnType,
                      invoiceId: widget.invoiceId,
                    ),
                  ),
                );
              },
            ),
            SdButton(
              label: 'سند قبض/صرف',
              icon: Icons.receipt_long,
              kind: SdButtonKind.secondary,
              onPressed: () {
                final voucherType = type == 'Sales' ? 'Receipt' : 'Payment';
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VoucherFormPage(
                      companyId: widget.companyId,
                      voucherType: voucherType,
                      invoiceId: widget.invoiceId,
                      entityId: (_data['EntityId'] ?? _data['entityId'] ?? '')
                          .toString(),
                      entityName:
                          (_data['EntityName'] ?? _data['entityName'] ?? '')
                              .toString(),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: SdSpace.lg),

        // السندات المرتبطة
        if (vouchers.isNotEmpty) ...[
          _buildVouchersSection(vouchers),
          const SizedBox(height: SdSpace.md),
        ],
      ],
    );
  }

  // ── قسم المواد ──
  Widget _buildItemsSection(List<dynamic> items) {
    final phone = context.sd.isPhone;
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SdSectionHeader(title: 'المواد'),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('لا توجد مواد', style: SdText.bodySm),
            )
          else if (phone)
            for (var i = 0; i < items.length; i++)
              _itemCardPhone(items[i] as Map<String, dynamic>)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _itemsTable(items),
            ),
        ],
      ),
    );
  }

  Widget _itemsTable(List<dynamic> items) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SdRadius.sm),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          const TableRow(
            decoration: BoxDecoration(color: SdColors.primary),
            children: [
              _HeaderCell('المادة'),
              _HeaderCell('الكمية'),
              _HeaderCell('السعر'),
              _HeaderCell('الخصم'),
              _HeaderCell('المجموع'),
            ],
          ),
          for (var i = 0; i < items.length; i++)
            _dataRow(i, items[i] as Map<String, dynamic>),
        ],
      ),
    );
  }

  TableRow _dataRow(int i, Map<String, dynamic> m) {
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _DataCell((m['ItemName'] ?? m['itemName'] ?? '-').toString()),
        _DataCell(fmtN(m['Quantity'] ?? m['quantity'])),
        _DataCell(fmtN(m['UnitPrice'] ?? m['unitPrice'])),
        _DataCell(fmtN(m['Discount'] ?? m['discount'] ?? 0)),
        _DataCell(fmtN(m['Total'] ?? m['total'])),
      ],
    );
  }

  Widget _itemCardPhone(Map<String, dynamic> m) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(SdSpace.sm),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((m['ItemName'] ?? m['itemName'] ?? '-').toString(), style: SdText.label),
          const SizedBox(height: 4),
          SdInfoRow(label: 'الكمية', value: fmtN(m['Quantity'] ?? m['quantity'])),
          SdInfoRow(label: 'السعر', value: fmtN(m['UnitPrice'] ?? m['unitPrice'])),
          SdInfoRow(label: 'الخصم', value: fmtN(m['Discount'] ?? m['discount'] ?? 0)),
          SdInfoRow(label: 'المجموع', value: fmtN(m['Total'] ?? m['total'])),
        ],
      ),
    );
  }

  // ── قسم السندات ──
  Widget _buildVouchersSection(List<dynamic> vouchers) {
    final phone = context.sd.isPhone;
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SdSectionHeader(title: 'سندات مرتبطة'),
          if (phone)
            for (var i = 0; i < vouchers.length; i++)
              _voucherCardPhone(vouchers[i] as Map<String, dynamic>)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _vouchersTable(vouchers),
            ),
        ],
      ),
    );
  }

  Widget _vouchersTable(List<dynamic> vouchers) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SdRadius.sm),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          const TableRow(
            decoration: BoxDecoration(color: SdColors.primary),
            children: [
              _HeaderCell('رقم السند'),
              _HeaderCell('النوع'),
              _HeaderCell('المبلغ'),
              _HeaderCell('التاريخ'),
              _HeaderCell('طريقة الدفع'),
            ],
          ),
          for (var i = 0; i < vouchers.length; i++)
            _voucherRow(i, vouchers[i] as Map<String, dynamic>),
        ],
      ),
    );
  }

  TableRow _voucherRow(int i, Map<String, dynamic> m) {
    final vType = (m['VoucherType'] ?? m['voucherType'] ?? '').toString();
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _DataCell((m['VoucherNumber'] ?? m['voucherNumber'] ?? '-').toString()),
        _DataCell(vType == '0' || vType == 'Receipt' ? 'قبض' : 'صرف'),
        _DataCell(fmtN(m['Amount'] ?? m['amount'])),
        _DataCell(_formatDate((m['Date'] ?? m['date'] ?? '').toString())),
        _DataCell(_paymentLabels[
                (m['PaymentMethod'] ?? m['paymentMethod'] ?? '').toString()] ??
            '-'),
      ],
    );
  }

  Widget _voucherCardPhone(Map<String, dynamic> m) {
    final vType = (m['VoucherType'] ?? m['voucherType'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(SdSpace.sm),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('#${(m['VoucherNumber'] ?? m['voucherNumber'] ?? '-')}', style: SdText.label),
          const SizedBox(height: 4),
          SdInfoRow(label: 'النوع', value: vType == '0' || vType == 'Receipt' ? 'قبض' : 'صرف'),
          SdInfoRow(label: 'المبلغ', value: fmtN(m['Amount'] ?? m['amount'])),
          SdInfoRow(label: 'التاريخ', value: _formatDate((m['Date'] ?? m['date'] ?? '').toString())),
          SdInfoRow(
              label: 'طريقة الدفع',
              value: _paymentLabels[
                      (m['PaymentMethod'] ?? m['paymentMethod'] ?? '').toString()] ??
                  '-'),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: bold ? SdText.titleSm : SdText.body),
          Text(fmtN(value),
              style: bold
                  ? SdText.titleSm.copyWith(color: SdColors.primary)
                  : SdText.label),
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
