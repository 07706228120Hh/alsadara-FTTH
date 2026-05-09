import 'utils/format_utils.dart';
import 'package:flutter/material.dart';
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        appBar: AppBar(
          title: const Text('المخازن', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Color(0xFF1A1A2E))),
          centerTitle: true, elevation: 0,
          backgroundColor: const Color(0xFFF5F6FA),
          foregroundColor: const Color(0xFF1A1A2E),
          actions: [IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadDashboard)],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty ? _buildError() : _buildBody(),
      ),
    );
  }

  Widget _buildError() {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
      const SizedBox(height: 12),
      Text('فشل تحميل البيانات', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
      const SizedBox(height: 12),
      TextButton.icon(onPressed: _loadDashboard, icon: const Icon(Icons.refresh, size: 18), label: const Text('إعادة المحاولة')),
    ]));
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── بطاقات الإحصائيات ──
        _buildStatCards(),
        const SizedBox(height: 24),

        // ── إجراءات سريعة ──
        _buildQuickActions(),
        const SizedBox(height: 24),

        // ── الأقسام ──
        const Text('الأقسام', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 12),
        _buildSectionGrid(),
        const SizedBox(height: 24),

        // ── آخر الحركات ──
        const Text('آخر الحركات', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1A1A2E))),
        const SizedBox(height: 12),
        _buildRecentMovements(),
      ]),
    );
  }

  // ═══════════════════════════════════════════
  //  بطاقات الإحصائيات
  // ═══════════════════════════════════════════

  Widget _buildStatCards() {
    final stats = [
      _StatItem('إجمالي المواد', '${_summary['totalItems'] ?? 0}', Icons.inventory_2_rounded, const Color(0xFF1976D2), const Color(0xFFE3F2FD)),
      _StatItem('قيمة المخزون', fmtN(_summary['totalValue'] ?? _summary['totalStockValue']), Icons.account_balance_wallet_rounded, const Color(0xFF388E3C), const Color(0xFFE8F5E9)),
      _StatItem('مواد ناقصة', '${_summary['lowStockCount'] ?? 0}', Icons.warning_rounded, const Color(0xFFE65100), const Color(0xFFFFF3E0)),
      _StatItem('حركات اليوم', '${_summary['todayMovementsCount'] ?? _summary['todayMovements'] ?? 0}', Icons.trending_up_rounded, const Color(0xFF7B1FA2), const Color(0xFFF3E5F5)),
    ];

    return Row(
      children: stats.map((s) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(color: s.bgColor, borderRadius: BorderRadius.circular(10)),
              child: Icon(s.icon, color: s.color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: s.color)),
              const SizedBox(height: 2),
              Text(s.label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ])),
          ]),
        ),
      )).toList(),
    );
  }

  // ═══════════════════════════════════════════
  //  إجراءات سريعة
  // ═══════════════════════════════════════════

  Widget _buildQuickActions() {
    return Row(children: [
      Expanded(child: _quickBtn('فاتورة بيع', Icons.receipt_long_rounded, const Color(0xFF388E3C), () => _go(InvoiceFormPage(companyId: _cid, invoiceType: 'Sales')))),
      const SizedBox(width: 10),
      Expanded(child: _quickBtn('فاتورة شراء', Icons.add_shopping_cart_rounded, const Color(0xFF1976D2), () => _go(InvoiceFormPage(companyId: _cid, invoiceType: 'Purchase')))),
      const SizedBox(width: 10),
      Expanded(child: _quickBtn('صرف مواد', Icons.engineering_rounded, const Color(0xFFE65100), () => _go(DispensingFormPage(companyId: _cid)))),
    ]);
  }

  Widget _quickBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 2),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  شبكة الأقسام
  // ═══════════════════════════════════════════

  Widget _buildSectionGrid() {
    final row1 = [
      _NavItem('العملاء', Icons.people_rounded, const Color(0xFF0D47A1), () => _go(CustomersPage(companyId: _cid))),
      _NavItem('الفواتير', Icons.receipt_long_rounded, const Color(0xFF2E7D32), () => _go(InvoicesPage(companyId: _cid))),
      _NavItem('السندات', Icons.account_balance_wallet_rounded, const Color(0xFF6A1B9A), () => _go(VouchersPage(companyId: _cid))),
      _NavItem('المرتجعات', Icons.assignment_return_rounded, const Color(0xFFBF360C), () => _go(ReturnsPage(companyId: _cid))),
      _NavItem('الموردين', Icons.local_shipping_rounded, const Color(0xFF795548), () => _go(SuppliersPage(companyId: _cid))),
    ];

    final row2 = [
      _NavItem('المستودعات', Icons.warehouse_rounded, const Color(0xFF3F51B5), () => _go(WarehousesPage(companyId: _cid))),
      _NavItem('المواد', Icons.category_rounded, const Color(0xFF009688), () => _go(MaterialsPage(companyId: _cid))),
      _NavItem('المخزون', Icons.inventory_rounded, const Color(0xFF00838F), () => _go(StockLevelsPage(companyId: _cid))),
      _NavItem('صرف الفنيين', Icons.engineering_rounded, const Color(0xFFE65100), () => _go(DispensingPage(companyId: _cid))),
      _NavItem('الحركات', Icons.swap_horiz_rounded, const Color(0xFF7B1FA2), () => _go(MovementsPage(companyId: _cid))),
      _NavItem('التقارير', Icons.analytics_rounded, const Color(0xFFC62828), () => _go(InventoryReportsPage(companyId: _cid))),
    ];

    Widget buildRow(List<_NavItem> items) => Row(
      children: items.map((item) => Expanded(
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _buildNavTile(item)),
      )).toList(),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Column(children: [
        buildRow(row1),
        const SizedBox(height: 8),
        buildRow(row2),
      ]),
    );
  }

  // ignore: unused_element
  Widget _buildSectionGridOld() {
    final items = <_NavItem>[];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 5,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.8,
      children: items.map((item) => _buildNavTile(item)).toList(),
    );
  }

  Widget _buildNavTile(_NavItem item) {
    return Material(
      color: item.color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: item.color.withOpacity(0.12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: item.color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(item.icon, color: item.color, size: 20),
              ),
              const SizedBox(height: 8),
              Text(item.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: item.color), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  آخر الحركات
  // ═══════════════════════════════════════════

  Widget _buildRecentMovements() {
    if (_recentMovements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.black, width: 2)),
        child: Column(children: [
          Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text('لا توجد حركات حديثة', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)),
        ]),
      );
    }

    final movements = _recentMovements.take(10).toList();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        border: const TableBorder(
          horizontalInside: BorderSide(color: Colors.black, width: 1),
          verticalInside: BorderSide(color: Colors.black, width: 1),
        ),
        columnWidths: const {
          0: FlexColumnWidth(2.2),   // التاريخ
          1: FlexColumnWidth(2.5),   // المادة
          2: FlexColumnWidth(2),     // المستودع
          3: FlexColumnWidth(1.8),   // النوع
          4: FlexColumnWidth(1),     // الكمية
          5: FlexColumnWidth(2),     // المستخدم
        },
        children: [
          // ── Header ──
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFECEFF5)),
            children: ['التاريخ', 'المادة', 'المستودع', 'النوع', 'الكمية', 'المستخدم']
                .map((h) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Center(child: Text(h, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800))),
                    ))
                .toList(),
          ),
          // ── Rows ──
          for (int i = 0; i < movements.length; i++)
            _buildMovementRow(movements[i] as Map<String, dynamic>, i),
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
        color: index.isEven ? Colors.white : const Color(0xFFF8F9FC),
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

  Widget _cell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Center(
        child: Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w600 : FontWeight.normal, color: const Color(0xFF1A1A2E)),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _typeChip(String type) {
    final m = {
      'purchasein': ('وارد شراء', const Color(0xFF388E3C)),
      'purchase': ('وارد', const Color(0xFF388E3C)),
      'in': ('وارد', const Color(0xFF388E3C)),
      'salesout': ('صادر بيع', const Color(0xFFC62828)),
      'sale': ('صادر', const Color(0xFFC62828)),
      'out': ('صادر', const Color(0xFFC62828)),
      'techniciandispensing': ('صرف فني', const Color(0xFFE65100)),
      'dispense': ('صرف', const Color(0xFFE65100)),
      'technicianreturn': ('إرجاع فني', const Color(0xFF00838F)),
      'return': ('إرجاع', const Color(0xFF00838F)),
      'transfer': ('نقل', const Color(0xFF1976D2)),
      'adjustment': ('تعديل', const Color(0xFF7B1FA2)),
      'adjust': ('تعديل', const Color(0xFF7B1FA2)),
      'initialstock': ('رصيد افتتاحي', const Color(0xFF455A64)),
      'damaged': ('تالف', const Color(0xFF880E4F)),
    };
    final entry = m[type.toLowerCase()] ?? (type, Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: entry.$2.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(entry.$1, style: TextStyle(color: entry.$2, fontSize: 11, fontWeight: FontWeight.w600)),
    );
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
  final Color color, bgColor;
  _StatItem(this.label, this.value, this.icon, this.color, this.bgColor);
}

class _NavItem {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _NavItem(this.label, this.icon, this.color, this.onTap);
}
