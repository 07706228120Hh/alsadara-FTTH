import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
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
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'تقارير المخزون',
        bottom: SdTabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'تقييم المخزون'),
            Tab(text: 'عُهد الفنيين'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: SdSpace.sm),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildValuationTab(),
                _buildHoldingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────── Tab 1: Valuation ───────────────────

  Widget _buildValuationTab() {
    if (_valuationLoading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (_valuationError != null) {
      return _errorWidget(_valuationError!, _loadValuation);
    }
    if (_valuationData.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد بيانات', icon: Icons.assessment_outlined),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTotalBanner(),
        const SizedBox(height: SdSpace.sm),
        Expanded(child: _buildValuationListOrTable()),
      ],
    );
  }

  Widget _buildTotalBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SdSpace.md),
      decoration: BoxDecoration(
        color: SdColors.infoTint,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(edge: SdColors.infoTintEdge, depth: SdDepth.small),
      ),
      child: Row(
        children: [
          const Icon(Icons.assessment, color: SdColors.info),
          const SizedBox(width: 8),
          const Text('إجمالي قيمة المخزون: ',
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 14,
                  color: SdColors.infoEdge,
                  fontWeight: FontWeight.w700)),
          Expanded(
            child: Text(
              fmtN(_totalValue),
              style: const TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 20,
                  color: SdColors.infoEdge,
                  fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValuationListOrTable() {
    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _valuationData.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _valuationCard(_valuationData[i]),
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
                  _HeaderCell('المادة'),
                  _HeaderCell('الكمية الكلية'),
                  _HeaderCell('متوسط التكلفة'),
                  _HeaderCell('القيمة الإجمالية'),
                ],
              ),
              for (var i = 0; i < _valuationData.length; i++)
                _valuationRow(i, _valuationData[i]),
            ],
          ),
        ),
      ),
    );
  }

  TableRow _valuationRow(int i, Map<String, dynamic> item) {
    final name = item['itemName'] as String? ?? '-';
    final qty = (item['totalQuantity'] as num?)?.toInt() ?? 0;
    final avgCost = (item['averageCost'] as num?)?.toDouble() ?? 0.0;
    final totalVal = (item['totalValue'] as num?)?.toDouble() ?? 0.0;
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _DataCell(name),
        _DataCell('$qty'),
        _DataCell(fmtN(avgCost)),
        _DataCell(fmtN(totalVal), bold: true),
      ],
    );
  }

  Widget _valuationCard(Map<String, dynamic> item) {
    final name = item['itemName'] as String? ?? '-';
    final qty = (item['totalQuantity'] as num?)?.toInt() ?? 0;
    final avgCost = (item['averageCost'] as num?)?.toDouble() ?? 0.0;
    final totalVal = (item['totalValue'] as num?)?.toDouble() ?? 0.0;
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: SdText.label),
          const SizedBox(height: 4),
          SdInfoRow(label: 'الكمية الكلية', value: '$qty'),
          SdInfoRow(label: 'متوسط التكلفة', value: fmtN(avgCost)),
          SdInfoRow(label: 'القيمة الإجمالية', value: fmtN(totalVal)),
        ],
      ),
    );
  }

  // ─────────────────── Tab 2: Technician Holdings ───────────────────

  Widget _buildHoldingsTab() {
    if (_holdingsLoading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (_holdingsError != null) {
      return _errorWidget(_holdingsError!, _loadHoldings);
    }
    if (_holdingsData.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد عُهد حالية', icon: Icons.engineering_outlined),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: _holdingsData.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final techData = _holdingsData[index];
        final techName =
            (techData['TechnicianName'] ?? techData['technicianName']) as String? ?? 'فني غير معروف';
        final items = (techData['Items'] ?? techData['items']) as List<dynamic>? ?? [];
        final totalHeld = items.fold<int>(
            0,
            (sum, item) {
              final m = item as Map<String, dynamic>;
              return sum + (((m['Quantity'] ?? m['quantity']) as num?)?.toInt() ?? 0);
            });

        return Container(
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.lg),
            boxShadow: SdDepth.raised(),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: SdColors.accentTint,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [BoxShadow(color: SdColors.accentTintEdge, offset: Offset(0, 3))],
                ),
                child: const Icon(Icons.engineering, color: SdColors.accent, size: 20),
              ),
              title: Text(techName, style: SdText.titleSm),
              subtitle: Text('$totalHeld قطعة في ${items.length} مادة', style: SdText.bodySm),
              childrenPadding: const EdgeInsets.fromLTRB(SdSpace.md, 0, SdSpace.md, SdSpace.sm),
              children: [
                if (context.sd.isPhone)
                  for (final item in items) _holdingItemCardPhone(item as Map<String, dynamic>)
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _holdingsTable(items),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _holdingsTable(List<dynamic> items) {
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
              _HeaderCell('المصروف'),
              _HeaderCell('المُرجع'),
              _HeaderCell('المتبقي'),
            ],
          ),
          for (var i = 0; i < items.length; i++)
            _holdingRow(i, items[i] as Map<String, dynamic>),
        ],
      ),
    );
  }

  TableRow _holdingRow(int i, Map<String, dynamic> m) {
    final qty = ((m['Quantity'] ?? m['quantity']) as num?)?.toInt() ?? 0;
    final returned =
        ((m['ReturnedQuantity'] ?? m['returnedQuantity']) as num?)?.toInt() ?? 0;
    final remaining = qty - returned;
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _DataCell((m['ItemName'] ?? m['itemName']) as String? ?? '-'),
        _DataCell('$qty'),
        _DataCell('$returned'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            '$remaining',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: remaining > 0 ? SdColors.warningText : SdColors.success,
            ),
          ),
        ),
      ],
    );
  }

  Widget _holdingItemCardPhone(Map<String, dynamic> m) {
    final qty = ((m['Quantity'] ?? m['quantity']) as num?)?.toInt() ?? 0;
    final returned =
        ((m['ReturnedQuantity'] ?? m['returnedQuantity']) as num?)?.toInt() ?? 0;
    final remaining = qty - returned;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(SdSpace.sm),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((m['ItemName'] ?? m['itemName']) as String? ?? '-', style: SdText.label),
          const SizedBox(height: 4),
          SdInfoRow(label: 'المصروف', value: '$qty'),
          SdInfoRow(label: 'المُرجع', value: '$returned'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text('المتبقي', style: SdText.bodySm),
                const Spacer(),
                Text('$remaining',
                    style: TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: remaining > 0 ? SdColors.warningText : SdColors.success,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorWidget(String error, VoidCallback onRetry) {
    return Center(
      child: SdEmptyState(
        title: 'تعذّر تحميل التقرير',
        message: error,
        icon: Icons.error_outline_rounded,
        status: SdStatus.danger,
        action: SdButton(
          label: 'إعادة المحاولة',
          icon: Icons.refresh_rounded,
          kind: SdButtonKind.secondary,
          onPressed: onRetry,
        ),
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
  final bool bold;
  const _DataCell(this.text, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
            fontFamily: SdText.family,
            fontSize: 12.5,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
            color: SdColors.ink),
      ),
    );
  }
}
