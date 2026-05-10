import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import 'voucher_form_page.dart';

class VouchersPage extends StatefulWidget {
  final String companyId;
  const VouchersPage({super.key, required this.companyId});

  @override
  State<VouchersPage> createState() => _VouchersPageState();
}

class _VouchersPageState extends State<VouchersPage>
    with SingleTickerProviderStateMixin {
  final _api = InventoryApiService.instance;
  late TabController _tabController;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _receipts = [];
  List<Map<String, dynamic>> _payments = [];

  static const _paymentLabels = {
    'Cash': 'نقدي',
    'BankTransfer': 'تحويل بنكي',
    'ZainCash': 'زين كاش',
    '0': 'نقدي',
    '1': 'تحويل بنكي',
    '2': 'زين كاش',
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
        _api.getVouchers(companyId: widget.companyId, type: 'Receipt'),
        _api.getVouchers(companyId: widget.companyId, type: 'Payment'),
      ]);

      final rList = (results[0]['data'] as List<dynamic>?) ?? [];
      final pList = (results[1]['data'] as List<dynamic>?) ?? [];

      if (mounted) {
        setState(() {
          _receipts = rList.cast<Map<String, dynamic>>();
          _payments = pList.cast<Map<String, dynamic>>();
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

  Future<void> _deleteVoucher(String id, String voucherNumber) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف السند "$voucherNumber"؟\nسيتم عكس الأرصدة تلقائياً.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteVoucher(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف السند وعكس الأرصدة'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
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
          title: const Text('سندات القبض والصرف'),
          actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        VoucherFormPage(companyId: widget.companyId),
                  ),
                ).then((_) => _loadData());
              },
              icon: const Icon(Icons.add),
              label: const Text('سند جديد'),
            ),
            const SizedBox(width: 12),
          ],
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF1A1A2E),
            unselectedLabelColor: Colors.grey,
            indicatorColor: const Color(0xFF1A1A2E),
            tabs: const [
              Tab(text: 'سندات قبض'),
              Tab(text: 'سندات صرف'),
            ],
          ),
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

    return TabBarView(
      controller: _tabController,
      children: [
        _buildTable(_receipts, 'لا توجد سندات قبض'),
        _buildTable(_payments, 'لا توجد سندات صرف'),
      ],
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> data, String emptyMsg) {
    if (data.isEmpty) {
      return Center(
        child: Text(emptyMsg,
            style: const TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Table(
          border: TableBorder.all(color: Colors.black54),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade200),
              children: const [
                _Cell('رقم السند', isHeader: true),
                _Cell('التاريخ', isHeader: true),
                _Cell('الاسم', isHeader: true),
                _Cell('المبلغ', isHeader: true),
                _Cell('طريقة الدفع', isHeader: true),
                _Cell('إجراءات', isHeader: true),
              ],
            ),
            ...data.asMap().entries.map((entry) {
              final i = entry.key;
              final m = entry.value;
              final vId = (m['Id'] ?? m['id'] ?? '').toString();
              final vNum = (m['VoucherNumber'] ?? m['voucherNumber'] ?? '-').toString();
              return TableRow(
                decoration: BoxDecoration(
                  color: i.isEven ? Colors.white : Colors.grey.shade50,
                ),
                children: [
                  _Cell(vNum),
                  _Cell(_formatDate(
                      (m['Date'] ?? m['date'] ?? '').toString())),
                  _Cell((m['EntityName'] ?? m['entityName'] ?? '-')
                      .toString()),
                  _Cell(fmtN(m['Amount'] ?? m['amount'])),
                  _Cell(_paymentLabels[
                          (m['PaymentMethod'] ?? m['paymentMethod'] ?? '')
                              .toString()] ??
                      '-'),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Tooltip(
                      message: 'حذف',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _deleteVoucher(vId, vNum),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade800),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
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
