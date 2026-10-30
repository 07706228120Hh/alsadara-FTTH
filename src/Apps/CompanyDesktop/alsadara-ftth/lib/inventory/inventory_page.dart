import 'utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../frontend/frontend.dart';
import 'widgets/inv_frame.dart';
import 'services/inventory_api_service.dart';
import 'pages/warehouses_page.dart';
import 'pages/materials_page.dart';
import 'pages/suppliers_page.dart';
import 'pages/dispensing_page.dart';
import 'pages/stock_levels_page.dart';
import 'pages/movements_page.dart';
import 'pages/inventory_reports_page.dart';
import 'pages/dispensing_form_page.dart';
import 'pages/customers_page.dart';
import 'pages/invoices_page.dart';
import 'pages/invoice_form_page.dart';
import 'pages/vouchers_page.dart';
import 'pages/returns_page.dart';

class InventoryPage extends StatefulWidget {
  final String? companyId;
  const InventoryPage({super.key, this.companyId});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  bool _isLoading = true;
  Map<String, dynamic> _summary = {};
  List<dynamic> _recentMovements = [];
  String _errorMessage = '';
  final _api = InventoryApiService.instance;

  String get _cid => widget.companyId ?? '';

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      final result = await _api.getDashboardSummary(companyId: _cid);
      if (!mounted) return;
      setState(() {
        _summary = result['data'] ?? {};
        _recentMovements = (_summary['recentMovements'] as List<dynamic>?) ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _errorMessage = '$e'; _isLoading = false; });
    }
  }

  void _go(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final loadingOrError = _isLoading || _errorMessage.isNotEmpty;
    return SdPage(
      scrollable: !loadingOrError,
      appBar: SdAppBar(
        title: 'المخازن',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loadDashboard,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
          : _errorMessage.isNotEmpty
              ? _buildError()
              : _buildBody(),
    );
  }

  Widget _buildError() {
    return Center(
      child: SdEmptyState(
        title: 'فشل تحميل البيانات',
        message: 'تعذّر جلب ملخّص المخازن. تحقّق من الاتصال وحاول مجدداً.',
        icon: Icons.error_outline_rounded,
        status: SdStatus.danger,
        action: SdButton(
          label: 'إعادة المحاولة',
          icon: Icons.refresh_rounded,
          kind: SdButtonKind.secondary,
          onPressed: _loadDashboard,
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStatCards(),
        const SizedBox(height: SdSpace.lg),
        _buildQuickActions(),
        const SizedBox(height: SdSpace.lg),
        const SdSectionHeader(title: 'الأقسام'),
        _buildSectionGrid(),
        const SizedBox(height: SdSpace.lg),
        const SdSectionHeader(title: 'آخر الحركات'),
        _buildRecentMovements(),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  بطاقات الإحصائيات
  // ═══════════════════════════════════════════

  Widget _buildStatCards() {
    final stats = [
      _StatItem('إجمالي المواد', '${_summary['totalItems'] ?? 0}',
          Icons.inventory_2_rounded, SdStatus.info.tone),
      _StatItem('قيمة المخزون', fmtN(_summary['totalValue'] ?? _summary['totalStockValue']),
          Icons.account_balance_wallet_rounded, SdStatus.success.tone),
      _StatItem('مواد ناقصة', '${_summary['lowStockCount'] ?? 0}',
          Icons.warning_rounded, SdStatus.warning.tone),
      _StatItem('حركات اليوم', '${_summary['todayMovementsCount'] ?? _summary['todayMovements'] ?? 0}',
          Icons.trending_up_rounded, SdGroup.platform.tone),
    ];

    return SdTileGrid(
      minTileWidth: 180,
      maxColumns: 4,
      phoneColumns: 2,
      children: [for (final s in stats) _statCard(s)],
    );
  }

  Widget _statCard(_StatItem s) {
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: SdDepth.raised(),
      ),
      padding: const EdgeInsets.all(SdSpace.md),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: s.tone.tint,
              borderRadius: BorderRadius.circular(SdRadius.sm),
              boxShadow: [BoxShadow(color: s.tone.tintEdge, offset: const Offset(0, 3))],
            ),
            child: Icon(s.icon, color: s.tone.base, size: 22),
          ),
          const SizedBox(width: SdSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(s.value,
                      maxLines: 1,
                      style: SdText.numberSm.copyWith(fontSize: 20, color: s.tone.edge)),
                ),
                const SizedBox(height: 2),
                Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: SdText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  إجراءات سريعة
  // ═══════════════════════════════════════════

  Widget _buildQuickActions() {
    final buttons = [
      SdButton(
        label: 'فاتورة بيع',
        icon: Icons.receipt_long_rounded,
        expand: true,
        onPressed: () => _go(InvoiceFormPage(companyId: _cid, invoiceType: 'Sales')),
      ),
      SdButton(
        label: 'فاتورة شراء',
        icon: Icons.add_shopping_cart_rounded,
        kind: SdButtonKind.accent,
        expand: true,
        onPressed: () => _go(InvoiceFormPage(companyId: _cid, invoiceType: 'Purchase')),
      ),
      SdButton(
        label: 'صرف مواد',
        icon: Icons.engineering_rounded,
        kind: SdButtonKind.secondary,
        expand: true,
        onPressed: () => _go(DispensingFormPage(companyId: _cid)),
      ),
    ];

    if (context.sd.isPhone) {
      return Column(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            buttons[i],
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: buttons[i]),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  شبكة الأقسام
  // ═══════════════════════════════════════════

  Widget _buildSectionGrid() {
    final items = [
      _NavItem('العملاء', Icons.people_rounded, () => _go(CustomersPage(companyId: _cid))),
      _NavItem('الفواتير', Icons.receipt_long_rounded, () => _go(InvoicesPage(companyId: _cid))),
      _NavItem('السندات', Icons.account_balance_wallet_rounded, () => _go(VouchersPage(companyId: _cid))),
      _NavItem('المرتجعات', Icons.assignment_return_rounded, () => _go(ReturnsPage(companyId: _cid))),
      _NavItem('الموردين', Icons.local_shipping_rounded, () => _go(SuppliersPage(companyId: _cid))),
      _NavItem('المستودعات', Icons.warehouse_rounded, () => _go(WarehousesPage(companyId: _cid))),
      _NavItem('المواد', Icons.category_rounded, () => _go(MaterialsPage(companyId: _cid))),
      _NavItem('المخزون', Icons.inventory_rounded, () => _go(StockLevelsPage(companyId: _cid))),
      _NavItem('صرف الفنيين', Icons.engineering_rounded, () => _go(DispensingPage(companyId: _cid))),
      _NavItem('الحركات', Icons.swap_horiz_rounded, () => _go(MovementsPage(companyId: _cid))),
      _NavItem('التقارير', Icons.analytics_rounded, () => _go(InventoryReportsPage(companyId: _cid))),
    ];

    return SdTileGrid(
      minTileWidth: 210,
      maxColumns: 4,
      phoneColumns: 2,
      children: [
        for (final item in items)
          SdMenuTile(
            title: item.label,
            icon: item.icon,
            group: SdGroup.admin,
            onTap: item.onTap,
          ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  آخر الحركات
  // ═══════════════════════════════════════════

  Widget _buildRecentMovements() {
    if (_recentMovements.isEmpty) {
      return const InvCard(
        child: SdEmptyState(
          title: 'لا توجد حركات حديثة',
          icon: Icons.inbox_rounded,
        ),
      );
    }

    final movements = _recentMovements.take(10).toList().cast<Map<String, dynamic>>();

    if (context.sd.isPhone) {
      return Column(
        children: [
          for (var i = 0; i < movements.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _movementCard(movements[i]),
          ],
        ],
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: SdDepth.raised(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.2), // التاريخ
          1: FlexColumnWidth(2.5), // المادة
          2: FlexColumnWidth(2),   // المستودع
          3: FlexColumnWidth(1.8), // النوع
          4: FlexColumnWidth(1),   // الكمية
          5: FlexColumnWidth(2),   // المستخدم
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: SdColors.primary),
            children: ['التاريخ', 'المادة', 'المستودع', 'النوع', 'الكمية', 'المستخدم']
                .map((h) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Center(
                        child: Text(h,
                            style: const TextStyle(
                                fontFamily: SdText.family,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ))
                .toList(),
          ),
          for (int i = 0; i < movements.length; i++) _buildMovementRow(movements[i], i),
        ],
      ),
    );
  }

  TableRow _buildMovementRow(Map<String, dynamic> map, int index) {
    final date = (map['CreatedAt'] ?? map['createdAt'] ?? '').toString();
    final itemName = (map['ItemName'] ?? map['itemName'] ?? '-').toString();
    final warehouse = (map['WarehouseName'] ?? map['warehouseName'] ?? '-').toString();
    final type = (map['MovementType'] ?? map['type'] ?? '').toString();
    final qty = map['Quantity'] ?? map['quantity'] ?? 0;
    final userName = (map['UserName'] ?? map['userName'] ?? '-').toString();

    return TableRow(
      decoration: BoxDecoration(
        color: index.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _cell(_fmtDate(date)),
        _cell(itemName, bold: true),
        _cell(warehouse),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Center(child: _typeChip(type)),
        ),
        _cell(fmtN(qty)),
        _cell(userName),
      ],
    );
  }

  Widget _movementCard(Map<String, dynamic> map) {
    final date = (map['CreatedAt'] ?? map['createdAt'] ?? '').toString();
    final itemName = (map['ItemName'] ?? map['itemName'] ?? '-').toString();
    final warehouse = (map['WarehouseName'] ?? map['warehouseName'] ?? '-').toString();
    final type = (map['MovementType'] ?? map['type'] ?? '').toString();
    final qty = map['Quantity'] ?? map['quantity'] ?? 0;
    final userName = (map['UserName'] ?? map['userName'] ?? '-').toString();

    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(itemName, style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              _typeChip(type),
            ],
          ),
          const SizedBox(height: 4),
          SdInfoRow(label: 'المستودع', value: warehouse),
          SdInfoRow(label: 'الكمية', value: fmtN(qty)),
          SdInfoRow(label: 'المستخدم', value: userName),
          SdInfoRow(label: 'التاريخ', value: _fmtDate(date)),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: SdColors.ink),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _typeChip(String type) {
    final m = {
      'purchasein': ('وارد شراء', SdStatus.success),
      'purchase': ('وارد', SdStatus.success),
      'in': ('وارد', SdStatus.success),
      'salesout': ('صادر بيع', SdStatus.danger),
      'sale': ('صادر', SdStatus.danger),
      'out': ('صادر', SdStatus.danger),
      'techniciandispensing': ('صرف فني', SdStatus.warning),
      'dispense': ('صرف', SdStatus.warning),
      'technicianreturn': ('إرجاع فني', SdStatus.info),
      'return': ('إرجاع', SdStatus.info),
      'transfer': ('نقل', SdStatus.info),
      'adjustment': ('تعديل', SdStatus.neutral),
      'adjust': ('تعديل', SdStatus.neutral),
      'initialstock': ('رصيد افتتاحي', SdStatus.neutral),
      'damaged': ('تالف', SdStatus.danger),
    };
    final entry = m[type.toLowerCase()] ?? (type, SdStatus.neutral);
    return SdStatusChip(entry.$1, status: entry.$2);
  }

  String _fmtDate(String raw) {
    if (raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return raw; }
  }
}

class _StatItem {
  final String label, value;
  final IconData icon;
  final SdTone tone;
  _StatItem(this.label, this.value, this.icon, this.tone);
}

class _NavItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  _NavItem(this.label, this.icon, this.onTap);
}
