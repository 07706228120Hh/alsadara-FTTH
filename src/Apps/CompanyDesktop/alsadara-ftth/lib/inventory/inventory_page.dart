import 'utils/format_utils.dart';
import 'package:flutter/material.dart';
import 'services/inventory_api_service.dart';
import 'pages/warehouses_page.dart';
import 'pages/materials_page.dart';
import 'pages/suppliers_page.dart';
import 'pages/purchases_page.dart';
import 'pages/sales_page.dart';
import 'pages/dispensing_page.dart';
import 'pages/stock_levels_page.dart';
import 'pages/movements_page.dart';
import 'pages/inventory_reports_page.dart';

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
          centerTitle: true,
          elevation: 0,
          backgroundColor: const Color(0xFFF5F6FA),
          foregroundColor: const Color(0xFF1A1A2E),
          iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
          actions: [
            IconButton(icon: const Icon(Icons.refresh, size: 20, color: Color(0xFF1A1A2E)), onPressed: _loadDashboard),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text('فشل تحميل البيانات', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── الإحصائيات (شريط صغير) ──
          _buildMiniStats(),
          const SizedBox(height: 20),

          // ── الأقسام ──
          _buildSectionButtons(),
          const SizedBox(height: 20),

          // ── آخر الحركات ──
          _buildRecentMovements(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  شريط الإحصائيات المصغر
  // ═══════════════════════════════════════════

  Widget _buildMiniStats() {
    final stats = [
      _StatItem('المواد', '${_summary['totalItems'] ?? 0}', Icons.inventory_2_outlined, Colors.blue),
      _StatItem('قيمة المخزون', _fmt(_summary['totalStockValue']), Icons.attach_money, Colors.green),
      _StatItem('ناقص', '${_summary['lowStockCount'] ?? 0}', Icons.warning_amber_rounded, Colors.orange),
      _StatItem('حركات اليوم', '${_summary['todayMovements'] ?? 0}', Icons.swap_horiz, Colors.purple),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: stats.map((s) => Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(s.icon, size: 18, color: s.color),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: s.color)),
                  Text(s.label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                ],
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  أزرار الأقسام
  // ═══════════════════════════════════════════

  Widget _buildSectionButtons() {
    final items = [
      _NavItem('المستودعات', Icons.warehouse_rounded, const Color(0xFF3F51B5), () => _go(WarehousesPage(companyId: _cid))),
      _NavItem('المواد', Icons.category_rounded, const Color(0xFF009688), () => _go(MaterialsPage(companyId: _cid))),
      _NavItem('الموردين', Icons.local_shipping_rounded, const Color(0xFF795548), () => _go(SuppliersPage(companyId: _cid))),
      _NavItem('الشراء', Icons.shopping_cart_rounded, const Color(0xFF1976D2), () => _go(PurchasesPage(companyId: _cid))),
      _NavItem('المبيعات', Icons.point_of_sale_rounded, const Color(0xFF388E3C), () => _go(SalesPage(companyId: _cid))),
      _NavItem('صرف الفنيين', Icons.engineering_rounded, const Color(0xFFE65100), () => _go(DispensingPage(companyId: _cid))),
      _NavItem('المخزون', Icons.inventory_rounded, const Color(0xFF00838F), () => _go(StockLevelsPage(companyId: _cid))),
      _NavItem('الحركات', Icons.swap_horiz_rounded, const Color(0xFF7B1FA2), () => _go(MovementsPage(companyId: _cid))),
      _NavItem('التقارير', Icons.analytics_rounded, const Color(0xFFC62828), () => _go(InventoryReportsPage(companyId: _cid))),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) => _buildNavButton(item)).toList(),
    );
  }

  Widget _buildNavButton(_NavItem item) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 130,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: item.color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('لا توجد حركات حديثة', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
          headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
          dataTextStyle: const TextStyle(fontSize: 12),
          columnSpacing: 20,
          horizontalMargin: 12,
          columns: const [
            DataColumn(label: Text('التاريخ')),
            DataColumn(label: Text('المادة')),
            DataColumn(label: Text('المستودع')),
            DataColumn(label: Text('النوع')),
            DataColumn(label: Text('الكمية')),
            DataColumn(label: Text('المستخدم')),
          ],
          rows: _recentMovements.take(10).map((m) {
            final map = m as Map<String, dynamic>;
            return DataRow(cells: [
              DataCell(Text(_fmtDate(map['date'] ?? ''))),
              DataCell(Text(map['itemName'] ?? '-')),
              DataCell(Text(map['warehouseName'] ?? '-')),
              DataCell(_typeChip(map['type'] ?? '')),
              DataCell(Text('${map['quantity'] ?? 0}')),
              DataCell(Text(map['userName'] ?? '-')),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _typeChip(String type) {
    final map = {
      'purchase': ('وارد', Colors.green),
      'in': ('وارد', Colors.green),
      'sale': ('صادر', Colors.red),
      'out': ('صادر', Colors.red),
      'transfer': ('نقل', Colors.blue),
      'dispense': ('صرف', Colors.orange),
      'return': ('إرجاع', Colors.teal),
      'adjust': ('تعديل', Colors.purple),
    };
    final entry = map[type.toLowerCase()] ?? (type, Colors.grey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: entry.$2.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(entry.$1, style: TextStyle(color: entry.$2, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  String _fmt(dynamic v) => fmtN(v);

  String _fmtDate(String raw) {
    if (raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw);
      return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) { return raw; }
  }
}

class _StatItem {
  final String label, value;
  final IconData icon;
  final Color color;
  _StatItem(this.label, this.value, this.icon, this.color);
}

class _NavItem {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _NavItem(this.label, this.icon, this.color, this.onTap);
}
