import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
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
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteVoucher(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف السند وعكس الأرصدة'), backgroundColor: SdColors.success));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
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
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'سندات القبض والصرف',
        actions: [
          SdAppBarAction(
            icon: Icons.add_rounded,
            label: 'سند جديد',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VoucherFormPage(companyId: widget.companyId),
                ),
              ).then((_) => _loadData());
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabBar(),
          const SizedBox(height: SdSpace.sm),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(depth: SdDepth.small),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: SdColors.primary,
        unselectedLabelColor: SdColors.muted,
        indicatorColor: SdColors.primary,
        labelStyle: SdText.label,
        unselectedLabelStyle: SdText.label.copyWith(fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'سندات قبض'),
          Tab(text: 'سندات صرف'),
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
          title: 'تعذّر تحميل السندات',
          message: _error,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: _loadData),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildList(_receipts, 'لا توجد سندات قبض'),
        _buildList(_payments, 'لا توجد سندات صرف'),
      ],
    );
  }

  Widget _buildList(List<Map<String, dynamic>> data, String emptyMsg) {
    if (data.isEmpty) {
      return Center(
        child: SdEmptyState(title: emptyMsg, icon: Icons.receipt_long_outlined),
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
                    color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
                  ),
                  children: [
                    _Cell(vNum),
                    _Cell(_formatDate((m['Date'] ?? m['date'] ?? '').toString())),
                    _Cell((m['EntityName'] ?? m['entityName'] ?? '-').toString()),
                    _Cell(fmtN(m['Amount'] ?? m['amount'])),
                    _Cell(_paymentLabels[(m['PaymentMethod'] ?? m['paymentMethod'] ?? '').toString()] ?? '-'),
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: Tooltip(
                        message: 'حذف',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => _deleteVoucher(vId, vNum),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.delete_outline, size: 20, color: SdColors.danger),
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
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> m) {
    final vId = (m['Id'] ?? m['id'] ?? '').toString();
    final vNum = (m['VoucherNumber'] ?? m['voucherNumber'] ?? '-').toString();
    final name = (m['EntityName'] ?? m['entityName'] ?? '-').toString();
    final amount = fmtN(m['Amount'] ?? m['amount']);
    final method = _paymentLabels[(m['PaymentMethod'] ?? m['paymentMethod'] ?? '').toString()] ?? '-';
    final date = _formatDate((m['Date'] ?? m['date'] ?? '').toString());

    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('#$vNum', style: SdText.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(amount, style: SdText.label.copyWith(color: SdColors.primary)),
            ],
          ),
          const SizedBox(height: 4),
          SdInfoRow(label: 'الاسم', value: name),
          SdInfoRow(label: 'التاريخ', value: date),
          SdInfoRow(label: 'طريقة الدفع', value: method),
          const Divider(color: SdColors.divider, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _deleteVoucher(vId, vNum),
                icon: const Icon(Icons.delete_outline, size: 18, color: SdColors.danger),
                label: const Text('حذف', style: TextStyle(color: SdColors.danger)),
              ),
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: SdText.family,
          fontWeight: isHeader ? FontWeight.w800 : FontWeight.w500,
          fontSize: 12.5,
          color: isHeader ? Colors.white : SdColors.ink,
        ),
      ),
    );
  }
}
