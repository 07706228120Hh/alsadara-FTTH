import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
import '../services/inventory_api_service.dart';

/// شاشة تنبيهات المخزون — نفاد/نقص/تجاوز الحد + دُفعات منتهية/قاربت الانتهاء.
class InventoryAlertsPage extends StatefulWidget {
  final String companyId;
  const InventoryAlertsPage({super.key, required this.companyId});

  @override
  State<InventoryAlertsPage> createState() => _InventoryAlertsPageState();
}

class _InventoryAlertsPageState extends State<InventoryAlertsPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

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
      final res = await _api.getInventoryAlerts(companyId: widget.companyId);
      final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted) {
        setState(() {
          _data = data;
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

  // قراءة مفتاح بصيغتي camelCase/PascalCase.
  dynamic _v(Map map, String camel) {
    final pascal = camel.isEmpty ? camel : camel[0].toUpperCase() + camel.substring(1);
    return map[camel] ?? map[pascal];
  }

  int _count(String camel) => (_v(_data, camel) as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> _list(String camel) {
    final raw = _v(_data, camel) as List<dynamic>? ?? [];
    return raw.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '-';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    final l = dt.toLocal();
    return '${l.year}/${l.month.toString().padLeft(2, '0')}/${l.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'تنبيهات المخزون',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loadData,
          ),
        ],
      ),
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
          title: 'تعذّر تحميل التنبيهات',
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
    if (_count('totalAlerts') == 0) {
      return const Center(
        child: SdEmptyState(
          title: 'لا توجد تنبيهات',
          message: 'جميع مستويات المخزون ضمن الحدود ولا توجد دُفعات منتهية.',
          icon: Icons.check_circle_outline_rounded,
          status: SdStatus.success,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: SdSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCounters(),
          const SizedBox(height: SdSpace.lg),
          ..._buildStockSection('نفاد المخزون', 'outOfStock', SdStatus.danger),
          ..._buildStockSection('نقص المخزون', 'lowStock', SdStatus.warning),
          ..._buildStockSection('تجاوز الحد الأقصى', 'overStock', SdStatus.info),
          ..._buildExpirySection('دُفعات منتهية الصلاحية', 'expired', SdStatus.danger),
          ..._buildExpirySection('دُفعات قاربت الانتهاء', 'expiringSoon', SdStatus.warning),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  بطاقات العدّادات
  // ═══════════════════════════════════════════

  Widget _buildCounters() {
    final counters = [
      _CounterItem('نفاد', _count('outOfStockCount'), Icons.remove_shopping_cart_rounded, SdStatus.danger),
      _CounterItem('نقص', _count('lowStockCount'), Icons.trending_down_rounded, SdStatus.warning),
      _CounterItem('تجاوز الحد', _count('overStockCount'), Icons.trending_up_rounded, SdStatus.info),
      _CounterItem('منتهية', _count('expiredCount'), Icons.event_busy_rounded, SdStatus.danger),
      _CounterItem('قاربت الانتهاء', _count('expiringSoonCount'), Icons.schedule_rounded, SdStatus.warning),
    ];
    return SdTileGrid(
      minTileWidth: 150,
      maxColumns: 5,
      phoneColumns: 2,
      children: [for (final c in counters) _counterCard(c)],
    );
  }

  Widget _counterCard(_CounterItem c) {
    final tone = c.status.tone;
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        border: Border.all(color: kInvFrameEdge, width: kInvFrameWidth),
        boxShadow: SdDepth.raised(),
      ),
      padding: const EdgeInsets.all(SdSpace.md),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tone.tint,
              borderRadius: BorderRadius.circular(SdRadius.sm),
              boxShadow: [BoxShadow(color: tone.tintEdge, offset: const Offset(0, 3))],
            ),
            child: Icon(c.icon, color: tone.base, size: 22),
          ),
          const SizedBox(width: SdSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${c.count}',
                    maxLines: 1,
                    style: SdText.numberSm.copyWith(fontSize: 20, color: tone.edge)),
                const SizedBox(height: 2),
                Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: SdText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  أقسام مخزون (نفاد/نقص/تجاوز)
  // ═══════════════════════════════════════════

  List<Widget> _buildStockSection(String title, String key, SdStatus status) {
    final rows = _list(key);
    if (rows.isEmpty) return const [];
    return [
      SdSectionHeader(title: '$title (${rows.length})'),
      const SizedBox(height: SdSpace.sm),
      if (context.sd.isPhone)
        for (final r in rows) ...[
          _stockCard(r, status),
          const SizedBox(height: 10),
        ]
      else
        _stockTable(rows, status),
      const SizedBox(height: SdSpace.lg),
    ];
  }

  Widget _stockTable(List<Map<String, dynamic>> rows, SdStatus status) {
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
          0: FlexColumnWidth(3),
          1: FlexColumnWidth(1.6),
          2: FlexColumnWidth(1.4),
          3: FlexColumnWidth(1.4),
          4: FlexColumnWidth(1.4),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: SdColors.primary),
            children: ['المادة', 'الرمز', 'المتوفر', 'الحد الأدنى', 'الحد الأقصى']
                .map(_headerCell)
                .toList(),
          ),
          for (int i = 0; i < rows.length; i++) _stockRow(rows[i], i, status),
        ],
      ),
    );
  }

  TableRow _stockRow(Map<String, dynamic> r, int index, SdStatus status) {
    final name = (_v(r, 'name') ?? '-').toString();
    final sku = (_v(r, 'sku') ?? '-').toString();
    final unit = (_v(r, 'unit') ?? '').toString();
    final qty = _v(r, 'totalQuantity');
    final min = _v(r, 'minStockLevel');
    final max = _v(r, 'maxStockLevel');
    final qtyText = unit.isEmpty ? fmtN(qty) : '${fmtN(qty)} $unit';
    return TableRow(
      decoration: BoxDecoration(color: index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      children: [
        _cell(name, bold: true),
        _cell(sku),
        _cell(qtyText, color: status.tone.edge, bold: true),
        _cell(fmtN(min)),
        _cell(fmtN(max)),
      ],
    );
  }

  Widget _stockCard(Map<String, dynamic> r, SdStatus status) {
    final name = (_v(r, 'name') ?? '-').toString();
    final sku = (_v(r, 'sku') ?? '-').toString();
    final unit = (_v(r, 'unit') ?? '').toString();
    final qty = _v(r, 'totalQuantity');
    final min = _v(r, 'minStockLevel');
    final max = _v(r, 'maxStockLevel');
    final qtyText = unit.isEmpty ? fmtN(qty) : '${fmtN(qty)} $unit';
    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SdStatusChip(qtyText, status: status),
            ],
          ),
          const SizedBox(height: 4),
          if (sku != '-' && sku.isNotEmpty) SdInfoRow(label: 'الرمز', value: sku),
          SdInfoRow(label: 'الحد الأدنى', value: fmtN(min)),
          SdInfoRow(label: 'الحد الأقصى', value: fmtN(max)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  أقسام الصلاحية (منتهية/قاربت الانتهاء)
  // ═══════════════════════════════════════════

  List<Widget> _buildExpirySection(String title, String key, SdStatus status) {
    final rows = _list(key);
    if (rows.isEmpty) return const [];
    return [
      SdSectionHeader(title: '$title (${rows.length})'),
      const SizedBox(height: SdSpace.sm),
      if (context.sd.isPhone)
        for (final r in rows) ...[
          _expiryCard(r, status),
          const SizedBox(height: 10),
        ]
      else
        _expiryTable(rows, status),
      const SizedBox(height: SdSpace.lg),
    ];
  }

  Widget _expiryTable(List<Map<String, dynamic>> rows, SdStatus status) {
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
          0: FlexColumnWidth(2.6),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(1.6),
          3: FlexColumnWidth(1.2),
          4: FlexColumnWidth(1.6),
        },
        children: [
          TableRow(
            decoration: const BoxDecoration(color: SdColors.primary),
            children: ['المادة', 'المستودع', 'رقم الدُّفعة', 'الكمية', 'الصلاحية']
                .map(_headerCell)
                .toList(),
          ),
          for (int i = 0; i < rows.length; i++) _expiryRow(rows[i], i, status),
        ],
      ),
    );
  }

  TableRow _expiryRow(Map<String, dynamic> r, int index, SdStatus status) {
    final name = (_v(r, 'itemName') ?? '-').toString();
    final warehouse = (_v(r, 'warehouseName') ?? '-').toString();
    final batch = (_v(r, 'batchNumber') ?? '').toString();
    final qty = _v(r, 'quantity');
    final expiry = _v(r, 'expiryDate');
    return TableRow(
      decoration: BoxDecoration(color: index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      children: [
        _cell(name, bold: true),
        _cell(warehouse),
        _cell(batch.isEmpty ? '-' : batch),
        _cell(fmtN(qty)),
        _cell(_fmtDate(expiry), color: status.tone.edge, bold: true),
      ],
    );
  }

  Widget _expiryCard(Map<String, dynamic> r, SdStatus status) {
    final name = (_v(r, 'itemName') ?? '-').toString();
    final warehouse = (_v(r, 'warehouseName') ?? '-').toString();
    final batch = (_v(r, 'batchNumber') ?? '').toString();
    final qty = _v(r, 'quantity');
    final expiry = _v(r, 'expiryDate');
    return InvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              SdStatusChip(_fmtDate(expiry), status: status),
            ],
          ),
          const SizedBox(height: 4),
          SdInfoRow(label: 'المستودع', value: warehouse),
          if (batch.isNotEmpty) SdInfoRow(label: 'رقم الدُّفعة', value: batch),
          SdInfoRow(label: 'الكمية', value: fmtN(qty)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  خلايا الجدول
  // ═══════════════════════════════════════════

  Widget _headerCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Center(
        child: Text(text,
            style: const TextStyle(
                fontFamily: SdText.family,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
      ),
    );
  }

  Widget _cell(String text, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: color ?? SdColors.ink),
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _CounterItem {
  final String label;
  final int count;
  final IconData icon;
  final SdStatus status;
  _CounterItem(this.label, this.count, this.icon, this.status);
}
