import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../services/inventory_api_service.dart';
import 'invoice_form_page.dart';
import 'invoice_details_page.dart';

class InvoicesPage extends StatefulWidget {
  final String companyId;
  const InvoicesPage({super.key, required this.companyId});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage>
    with SingleTickerProviderStateMixin {
  final _api = InventoryApiService.instance;
  late final TabController _tabController;

  // ---- Sales tab state ----
  bool _salesLoading = true;
  String? _salesError;
  List<Map<String, dynamic>> _salesInvoices = [];
  String? _salesStatusFilter;
  DateTime? _salesDateFrom;
  DateTime? _salesDateTo;

  // ---- Purchase tab state ----
  bool _purchaseLoading = true;
  String? _purchaseError;
  List<Map<String, dynamic>> _purchaseInvoices = [];
  String? _purchaseStatusFilter;
  DateTime? _purchaseDateFrom;
  DateTime? _purchaseDateTo;

  static const _statusMap = <String?, String>{
    null: 'الكل',
    'Draft': 'مسودة',
    'Confirmed': 'مؤكدة',
    'PartiallyPaid': 'مدفوعة جزئياً',
    'Paid': 'مدفوعة',
    'Cancelled': 'ملغاة',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    _loadSales();
    _loadPurchases();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ================================================================
  //  Data loading
  // ================================================================

  Future<void> _loadSales() async {
    setState(() {
      _salesLoading = true;
      _salesError = null;
    });
    try {
      final res = await _api.getInvoices(
        companyId: widget.companyId,
        type: 'Sales',
        status: _salesStatusFilter,
        from: _salesDateFrom?.toIso8601String().split('T').first,
        to: _salesDateTo?.toIso8601String().split('T').first,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _salesInvoices =
              list.map((e) => e as Map<String, dynamic>).toList();
          _salesLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _salesError = e.toString();
          _salesLoading = false;
        });
      }
    }
  }

  Future<void> _loadPurchases() async {
    setState(() {
      _purchaseLoading = true;
      _purchaseError = null;
    });
    try {
      final res = await _api.getInvoices(
        companyId: widget.companyId,
        type: 'Purchase',
        status: _purchaseStatusFilter,
        from: _purchaseDateFrom?.toIso8601String().split('T').first,
        to: _purchaseDateTo?.toIso8601String().split('T').first,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _purchaseInvoices =
              list.map((e) => e as Map<String, dynamic>).toList();
          _purchaseLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _purchaseError = e.toString();
          _purchaseLoading = false;
        });
      }
    }
  }

  // ================================================================
  //  Helpers
  // ================================================================

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  String _formatDateStr(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return _formatDate(dt);
  }

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

  Future<void> _pickDate(bool isFrom, {required bool isSales}) async {
    final current = isSales
        ? (isFrom ? _salesDateFrom : _salesDateTo)
        : (isFrom ? _purchaseDateFrom : _purchaseDateTo);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isSales) {
          if (isFrom) {
            _salesDateFrom = picked;
          } else {
            _salesDateTo = picked;
          }
        } else {
          if (isFrom) {
            _purchaseDateFrom = picked;
          } else {
            _purchaseDateTo = picked;
          }
        }
      });
      isSales ? _loadSales() : _loadPurchases();
    }
  }

  SdStatus _statusTone(String? status) {
    switch (status) {
      case 'Confirmed':
        return SdStatus.info;
      case 'PartiallyPaid':
        return SdStatus.warning;
      case 'Paid':
        return SdStatus.success;
      case 'Cancelled':
        return SdStatus.danger;
      default:
        return SdStatus.neutral;
    }
  }

  Widget _statusChip(String? status) {
    final label = _statusMap[status] ?? (status ?? '-');
    return SdStatusChip(label, status: _statusTone(status));
  }

  Widget _paymentChip(String? paymentType) {
    late final String label;
    late final SdStatus status;
    switch (paymentType) {
      case 'Cash':
        label = 'نقدي';
        status = SdStatus.success;
        break;
      case 'Credit':
        label = 'آجل';
        status = SdStatus.warning;
        break;
      case 'Partial':
        label = 'جزئي';
        status = SdStatus.info;
        break;
      default:
        label = paymentType ?? '-';
        status = SdStatus.neutral;
    }
    return SdStatusChip(label, status: status);
  }

  // ================================================================
  //  Build
  // ================================================================

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'الفواتير',
        actions: [
          SdAppBarAction(
            icon: Icons.add_rounded,
            label: 'فاتورة بيع',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InvoiceFormPage(
                    companyId: widget.companyId,
                    invoiceType: 'Sales',
                  ),
                ),
              ).then((_) {
                _loadSales();
              });
            },
          ),
          SdAppBarAction(
            icon: Icons.add_rounded,
            label: 'فاتورة شراء',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InvoiceFormPage(
                    companyId: widget.companyId,
                    invoiceType: 'Purchase',
                  ),
                ),
              ).then((_) {
                _loadPurchases();
              });
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabBar(),
          const SizedBox(height: SdSpace.sm),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent(
                  isSales: true,
                  loading: _salesLoading,
                  error: _salesError,
                  invoices: _salesInvoices,
                  statusFilter: _salesStatusFilter,
                  dateFrom: _salesDateFrom,
                  dateTo: _salesDateTo,
                  onStatusChanged: (v) {
                    setState(() => _salesStatusFilter = v);
                    _loadSales();
                  },
                  onClearFilters: () {
                    setState(() {
                      _salesStatusFilter = null;
                      _salesDateFrom = null;
                      _salesDateTo = null;
                    });
                    _loadSales();
                  },
                  onReload: _loadSales,
                  counterpartLabel: 'العميل',
                ),
                _buildTabContent(
                  isSales: false,
                  loading: _purchaseLoading,
                  error: _purchaseError,
                  invoices: _purchaseInvoices,
                  statusFilter: _purchaseStatusFilter,
                  dateFrom: _purchaseDateFrom,
                  dateTo: _purchaseDateTo,
                  onStatusChanged: (v) {
                    setState(() => _purchaseStatusFilter = v);
                    _loadPurchases();
                  },
                  onClearFilters: () {
                    setState(() {
                      _purchaseStatusFilter = null;
                      _purchaseDateFrom = null;
                      _purchaseDateTo = null;
                    });
                    _loadPurchases();
                  },
                  onReload: _loadPurchases,
                  counterpartLabel: 'المورد',
                ),
              ],
            ),
          ),
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
          Tab(text: 'فواتير البيع'),
          Tab(text: 'فواتير الشراء'),
        ],
      ),
    );
  }

  // ================================================================
  //  Tab content
  // ================================================================

  Widget _buildTabContent({
    required bool isSales,
    required bool loading,
    required String? error,
    required List<Map<String, dynamic>> invoices,
    required String? statusFilter,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required ValueChanged<String?> onStatusChanged,
    required VoidCallback onClearFilters,
    required VoidCallback onReload,
    required String counterpartLabel,
  }) {
    return Column(
      children: [
        // Filters row
        Padding(
          padding: const EdgeInsets.only(bottom: SdSpace.xs),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  value: statusFilter,
                  decoration: _dec('الحالة'),
                  items: _statusMap.entries
                      .map((e) => DropdownMenuItem(
                          value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: onStatusChanged,
                ),
              ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
                label: Text(dateFrom != null
                    ? 'من: ${_formatDate(dateFrom)}'
                    : 'من تاريخ'),
                onPressed: () => _pickDate(true, isSales: isSales),
              ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
                label: Text(dateTo != null
                    ? 'إلى: ${_formatDate(dateTo)}'
                    : 'إلى تاريخ'),
                onPressed: () => _pickDate(false, isSales: isSales),
              ),
              if (dateFrom != null || dateTo != null || statusFilter != null)
                ActionChip(
                  avatar: const Icon(Icons.clear, size: 18),
                  label: const Text('مسح الفلاتر'),
                  onPressed: onClearFilters,
                ),
            ],
          ),
        ),
        // Body
        Expanded(
          child: _buildTabBody(
            loading: loading,
            error: error,
            invoices: invoices,
            onReload: onReload,
            counterpartLabel: counterpartLabel,
            isSales: isSales,
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody({
    required bool loading,
    required String? error,
    required List<Map<String, dynamic>> invoices,
    required VoidCallback onReload,
    required String counterpartLabel,
    required bool isSales,
  }) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل الفواتير',
          message: error,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: onReload),
        ),
      );
    }
    if (invoices.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد فواتير', icon: Icons.receipt_long_outlined),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: invoices.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildInvoiceCard(invoices[i], counterpartLabel, isSales),
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
              // Header row
              TableRow(
                decoration: const BoxDecoration(color: SdColors.primary),
                children: [
                  _headerCell('رقم الفاتورة'),
                  _headerCell(counterpartLabel),
                  _headerCell('التاريخ'),
                  _headerCell('المبلغ'),
                  _headerCell('المدفوع'),
                  _headerCell('المتبقي'),
                  _headerCell('نوع الدفع'),
                  _headerCell('الحالة'),
                  _headerCell('إجراءات'),
                ],
              ),
              // Data rows
              for (var i = 0; i < invoices.length; i++)
                _buildDataRow(invoices[i], i, counterpartLabel, isSales),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontFamily: SdText.family, fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white),
      ),
    );
  }

  TableRow _buildDataRow(
    Map<String, dynamic> inv,
    int index,
    String counterpartLabel,
    bool isSales,
  ) {
    final id = inv['Id']?.toString() ?? '';
    final invoiceNumber = inv['InvoiceNumber']?.toString() ?? '-';
    final counterpart = isSales
        ? (inv['CustomerName']?.toString() ?? '-')
        : (inv['SupplierName']?.toString() ?? '-');
    final date = _formatDateStr(inv['InvoiceDate']?.toString());
    final amount = fmtN(inv['TotalAmount']);
    final paid = fmtN(inv['PaidAmount']);
    final remaining = fmtN(inv['RemainingAmount']);
    final paymentType = inv['PaymentType']?.toString();
    final status = inv['Status']?.toString();

    return TableRow(
      decoration: BoxDecoration(
        color: index.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _tappableCell(child: _text(invoiceNumber), onTap: () => _navigateToDetails(id)),
        _tappableCell(child: _text(counterpart), onTap: () => _navigateToDetails(id)),
        _tappableCell(child: _text(date), onTap: () => _navigateToDetails(id)),
        _tappableCell(child: _text(amount), onTap: () => _navigateToDetails(id)),
        _tappableCell(child: _text(paid), onTap: () => _navigateToDetails(id)),
        _tappableCell(child: _text(remaining), onTap: () => _navigateToDetails(id)),
        _tappableCell(child: _paymentChip(paymentType), onTap: () => _navigateToDetails(id)),
        _tappableCell(child: _statusChip(status), onTap: () => _navigateToDetails(id)),
        // أزرار الإجراءات
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _buildInvoiceActions(id, status, isSales),
          ),
        ),
      ],
    );
  }

  Widget _text(String value) => Text(value,
      textAlign: TextAlign.center,
      style: const TextStyle(fontFamily: SdText.family, fontSize: 12.5, fontWeight: FontWeight.w500, color: SdColors.ink));

  Widget _buildInvoiceCard(Map<String, dynamic> inv, String counterpartLabel, bool isSales) {
    final id = inv['Id']?.toString() ?? '';
    final invoiceNumber = inv['InvoiceNumber']?.toString() ?? '-';
    final counterpart = isSales
        ? (inv['CustomerName']?.toString() ?? '-')
        : (inv['SupplierName']?.toString() ?? '-');
    final date = _formatDateStr(inv['InvoiceDate']?.toString());
    final amount = fmtN(inv['TotalAmount']);
    final paid = fmtN(inv['PaidAmount']);
    final remaining = fmtN(inv['RemainingAmount']);
    final paymentType = inv['PaymentType']?.toString();
    final status = inv['Status']?.toString();

    return GestureDetector(
      onTap: () => _navigateToDetails(id),
      child: SdCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('#$invoiceNumber', style: SdText.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                _statusChip(status),
              ],
            ),
            const SizedBox(height: 4),
            SdInfoRow(label: counterpartLabel, value: counterpart),
            SdInfoRow(label: 'التاريخ', value: date),
            SdInfoRow(label: 'المبلغ', value: amount),
            SdInfoRow(label: 'المدفوع', value: paid),
            SdInfoRow(label: 'المتبقي', value: remaining),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text('نوع الدفع', style: SdText.bodySm),
                  const Spacer(),
                  _paymentChip(paymentType),
                ],
              ),
            ),
            const Divider(color: SdColors.divider, height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _buildInvoiceActions(id, status, isSales),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildInvoiceActions(String id, String? status, bool isSales) {
    final actions = <Widget>[];

    // تعديل — فقط للمسودة
    if (status == 'Draft') {
      actions.add(_invoiceActionBtn(Icons.edit_outlined, 'تعديل', SdColors.primary, () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => InvoiceFormPage(companyId: widget.companyId, invoiceType: isSales ? 'Sales' : 'Purchase'),
        )).then((_) { _loadSales(); _loadPurchases(); });
      }));
    }

    // تأكيد — فقط للمسودة
    if (status == 'Draft') {
      actions.add(_invoiceActionBtn(Icons.check_circle_outline, 'تأكيد', SdColors.success, () => _confirmInvoice(id)));
    }

    // إلغاء — فقط للمسودة (الفواتير المؤكدة تحتاج مرتجع)
    if (status == 'Draft') {
      actions.add(_invoiceActionBtn(Icons.cancel_outlined, 'إلغاء', SdColors.danger, () => _cancelInvoice(id)));
    }

    // عرض التفاصيل — دائماً
    actions.add(_invoiceActionBtn(Icons.visibility_outlined, 'عرض', SdColors.muted, () => _navigateToDetails(id)));

    return actions;
  }

  Widget _invoiceActionBtn(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 20, color: color)),
      ),
    );
  }

  Future<void> _confirmInvoice(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الفاتورة'),
          content: const Text('هل تريد تأكيد هذه الفاتورة؟ سيتم خصم/إضافة المخزون تلقائياً.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.primary), onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.confirmInvoice(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تأكيد الفاتورة بنجاح'), backgroundColor: SdColors.success));
      _loadSales(); _loadPurchases();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التأكيد: $e'), backgroundColor: SdColors.danger));
    }
  }

  Future<void> _cancelInvoice(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إلغاء الفاتورة'),
          content: const Text('هل تريد إلغاء هذه الفاتورة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تراجع')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء الفاتورة')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.cancelInvoice(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الفاتورة'), backgroundColor: SdColors.success));
      _loadSales(); _loadPurchases();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  Widget _tappableCell({required Widget child, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Center(child: child),
      ),
    );
  }

  void _navigateToDetails(String invoiceId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceDetailsPage(
          companyId: widget.companyId,
          invoiceId: invoiceId,
        ),
      ),
    ).then((_) {
      _loadSales();
      _loadPurchases();
    });
  }
}
