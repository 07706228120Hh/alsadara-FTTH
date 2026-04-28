import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';

class InventoryReportsPage extends StatefulWidget {
  final String companyId;
  const InventoryReportsPage({super.key, required this.companyId});

  @override
  State<InventoryReportsPage> createState() => _InventoryReportsPageState();
}

class _InventoryReportsPageState extends State<InventoryReportsPage>
    with SingleTickerProviderStateMixin {
  final _api = InventoryApiService.instance;
  late TabController _tabController;

  // Valuation tab
  bool _valuationLoading = true;
  String? _valuationError;
  List<Map<String, dynamic>> _valuationData = [];
  double _totalValue = 0;

  // Holdings tab
  bool _holdingsLoading = true;
  String? _holdingsError;
  List<Map<String, dynamic>> _holdingsData = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadValuation();
    _loadHoldings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadValuation() async {
    setState(() {
      _valuationLoading = true;
      _valuationError = null;
    });
    try {
      final res =
          await _api.getValuationReport(companyId: widget.companyId);
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _valuationData = list.cast<Map<String, dynamic>>();
          _totalValue = _valuationData.fold(
              0.0,
              (sum, item) =>
                  sum +
                  ((item['totalValue'] as num?)?.toDouble() ?? 0.0));
          _valuationLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _valuationError = e.toString();
          _valuationLoading = false;
        });
      }
    }
  }

  Future<void> _loadHoldings() async {
    setState(() {
      _holdingsLoading = true;
      _holdingsError = null;
    });
    try {
      final res = await _api.getTechnicianHoldingsReport(
          companyId: widget.companyId);
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _holdingsData = list.cast<Map<String, dynamic>>();
          _holdingsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _holdingsError = e.toString();
          _holdingsLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), elevation: 0,
          title: const Text('تقارير المخزون'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'تقييم المخزون'),
              Tab(text: 'عُهد الفنيين'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildValuationTab(),
            _buildHoldingsTab(),
          ],
        ),
      ),
    );
  }

  // ─────────────────── Tab 1: Valuation ───────────────────

  Widget _buildValuationTab() {
    if (_valuationLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_valuationError != null) {
      return _errorWidget(_valuationError!, _loadValuation);
    }
    if (_valuationData.isEmpty) {
      return const Center(
        child: Text('لا توجد بيانات',
            style: TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              Icon(Icons.assessment, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'إجمالي قيمة المخزون: ',
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                fmtN(_totalValue),
                style: TextStyle(
                    fontSize: 20,
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(Colors.grey.shade100),
                columnSpacing: 24,
                columns: const [
                  DataColumn(label: Text('المادة')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(label: Text('الكمية الكلية'), numeric: true),
                  DataColumn(
                      label: Text('متوسط التكلفة'), numeric: true),
                  DataColumn(
                      label: Text('القيمة الإجمالية'), numeric: true),
                ],
                rows: _valuationData.map((item) {
                  final name = item['itemName'] as String? ?? '-';
                  final sku = item['sku'] as String? ?? '-';
                  final qty =
                      (item['totalQuantity'] as num?)?.toInt() ?? 0;
                  final avgCost =
                      (item['averageCost'] as num?)?.toDouble() ?? 0.0;
                  final totalVal =
                      (item['totalValue'] as num?)?.toDouble() ?? 0.0;
                  return DataRow(cells: [
                    DataCell(Text(name)),
                    DataCell(Text(sku)),
                    DataCell(Text('$qty')),
                    DataCell(Text(fmtN(avgCost))),
                    DataCell(Text(fmtN(totalVal),
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────── Tab 2: Technician Holdings ───────────────────

  Widget _buildHoldingsTab() {
    if (_holdingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_holdingsError != null) {
      return _errorWidget(_holdingsError!, _loadHoldings);
    }
    if (_holdingsData.isEmpty) {
      return const Center(
        child: Text('لا توجد عُهد حالية',
            style: TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _holdingsData.length,
      itemBuilder: (context, index) {
        final techData = _holdingsData[index];
        final techName =
            techData['technicianName'] as String? ?? 'فني غير معروف';
        final items = techData['items'] as List<dynamic>? ?? [];
        final totalHeld = items.fold<int>(
            0,
            (sum, item) =>
                sum +
                (((item as Map<String, dynamic>)['quantity'] as num?)
                        ?.toInt() ??
                    0));

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Colors.teal.shade100,
              child: Icon(Icons.engineering, color: Colors.teal.shade700),
            ),
            title: Text(techName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$totalHeld قطعة في ${items.length} مادة'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Table(
                  border: TableBorder.all(color: Colors.grey.shade300),
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.2),
                  },
                  children: [
                    TableRow(
                      decoration:
                          BoxDecoration(color: Colors.grey.shade100),
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('المادة',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('المصروف',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('المُرجع',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('المتبقي',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    ...items.map((item) {
                      final m = item as Map<String, dynamic>;
                      final qty =
                          (m['quantity'] as num?)?.toInt() ?? 0;
                      final returned =
                          (m['returnedQuantity'] as num?)?.toInt() ??
                              0;
                      final remaining = qty - returned;
                      return TableRow(children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                              m['itemName'] as String? ?? '-'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('$qty'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('$returned'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('$remaining',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: remaining > 0
                                    ? Colors.orange.shade800
                                    : Colors.green.shade700,
                              )),
                        ),
                      ]);
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _errorWidget(String error, VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text(error, style: TextStyle(color: Colors.red.shade700)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
