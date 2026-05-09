import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
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

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    switch (status) {
      case 'Draft':
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        break;
      case 'Confirmed':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        break;
      case 'Cancelled':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusLabels[status] ?? status,
        style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _confirmInvoice() async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تأكيد الفاتورة'),
            content: const Text('هل أنت متأكد من تأكيد هذه الفاتورة؟'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('تأكيد')),
            ],
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
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F6FA),
          foregroundColor: const Color(0xFF1A1A2E),
          iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
          titleTextStyle: const TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 18,
              fontWeight: FontWeight.w700),
          elevation: 0,
          title: const Text('تفاصيل الفاتورة'),
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
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
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

    final status = (_data['Status'] ?? _data['status'] ?? '').toString();
    final type = (_data['Type'] ?? _data['type'] ?? '').toString();
    final items = (_data['Items'] ?? _data['items'] ?? []) as List<dynamic>;
    final vouchers =
        (_data['Vouchers'] ?? _data['vouchers'] ?? []) as List<dynamic>;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Invoice header info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _infoRow('رقم الفاتورة', _val('InvoiceNumber')),
                  _infoRow(
                      'نوع الفاتورة', _typeLabels[type] ?? type),
                  _infoRow('التاريخ',
                      _formatDate(_val('InvoiceDate'))),
                  _infoRow(
                      'العميل/المورد',
                      (_data['EntityName'] ?? _data['entityName'] ?? '-')
                          .toString()),
                  _infoRow(
                      'طريقة الدفع',
                      _paymentLabels[_val('PaymentMethod')] ??
                          _val('PaymentMethod')),
                  Row(
                    children: [
                      const Text('الحالة: ',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      _statusChip(status),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Items table
          const Text('المواد',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              border: TableBorder.all(color: Colors.black54),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade200),
                  children: const [
                    _Cell('المادة', isHeader: true),
                    _Cell('الكمية', isHeader: true),
                    _Cell('السعر', isHeader: true),
                    _Cell('الخصم', isHeader: true),
                    _Cell('المجموع', isHeader: true),
                  ],
                ),
                ...items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final m = entry.value as Map<String, dynamic>;
                  return TableRow(
                    decoration: BoxDecoration(
                      color: i.isEven ? Colors.white : Colors.grey.shade50,
                    ),
                    children: [
                      _Cell((m['ItemName'] ?? m['itemName'] ?? '-').toString()),
                      _Cell(fmtN(m['Quantity'] ?? m['quantity'])),
                      _Cell(fmtN(m['UnitPrice'] ?? m['unitPrice'])),
                      _Cell(fmtN(m['Discount'] ?? m['discount'] ?? 0)),
                      _Cell(fmtN(m['Total'] ?? m['total'])),
                    ],
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Totals
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _totalRow('المجموع الفرعي', _val('SubTotal')),
                  _totalRow('الخصم', _val('TotalDiscount')),
                  _totalRow('الضريبة', _val('TaxAmount')),
                  const Divider(),
                  _totalRow('الصافي', _val('NetAmount'), bold: true),
                  _totalRow('المدفوع', _val('PaidAmount')),
                  _totalRow('المتبقي', _val('RemainingAmount'),
                      bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (status == 'Draft')
                FilledButton.icon(
                  onPressed: _confirmInvoice,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('تأكيد الفاتورة'),
                ),
              OutlinedButton.icon(
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
                icon: const Icon(Icons.assignment_return),
                label: const Text('إنشاء مرتجع'),
              ),
              OutlinedButton.icon(
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
                icon: const Icon(Icons.receipt_long),
                label: const Text('سند قبض/صرف'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Vouchers list
          if (vouchers.isNotEmpty) ...[
            const Text('سندات مرتبطة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                border: TableBorder.all(color: Colors.black54),
                defaultColumnWidth: const IntrinsicColumnWidth(),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade200),
                    children: const [
                      _Cell('رقم السند', isHeader: true),
                      _Cell('النوع', isHeader: true),
                      _Cell('المبلغ', isHeader: true),
                      _Cell('التاريخ', isHeader: true),
                      _Cell('طريقة الدفع', isHeader: true),
                    ],
                  ),
                  ...vouchers.asMap().entries.map((entry) {
                    final i = entry.key;
                    final m = entry.value as Map<String, dynamic>;
                    final vType =
                        (m['VoucherType'] ?? m['voucherType'] ?? '').toString();
                    return TableRow(
                      decoration: BoxDecoration(
                        color: i.isEven ? Colors.white : Colors.grey.shade50,
                      ),
                      children: [
                        _Cell((m['VoucherNumber'] ?? m['voucherNumber'] ?? '-')
                            .toString()),
                        _Cell(vType == '0' || vType == 'Receipt'
                            ? 'قبض'
                            : 'صرف'),
                        _Cell(fmtN(m['Amount'] ?? m['amount'])),
                        _Cell(_formatDate(
                            (m['Date'] ?? m['date'] ?? '').toString())),
                        _Cell(_paymentLabels[
                                (m['PaymentMethod'] ?? m['paymentMethod'] ?? '')
                                    .toString()] ??
                            '-'),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
          Text(fmtN(value),
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final bool isHeader;
  const _Cell(this.text, {this.isHeader = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: isHeader ? 13 : 12,
        ),
      ),
    );
  }
}
