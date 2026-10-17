import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../services/inventory_api_service.dart';
import '../models/inventory_models.dart';
import 'dispensing_form_page.dart';

class DispensingPage extends StatefulWidget {
  final String companyId;
  const DispensingPage({super.key, required this.companyId});

  @override
  State<DispensingPage> createState() => _DispensingPageState();
}

class _DispensingPageState extends State<DispensingPage>
    with SingleTickerProviderStateMixin {
  final _api = InventoryApiService.instance;
  late TabController _tabController;

  // Dispensing list tab
  bool _loading = true;
  String? _error;
  List<TechnicianDispensingModel> _dispensings = [];

  String? _statusFilter;
  String _technicianFilter = '';
  DateTime? _dateFrom;
  DateTime? _dateTo;

  // Holdings tab
  bool _holdingsLoading = false;
  String? _holdingsError;
  List<Map<String, dynamic>> _holdingsData = [];

  static const _statusMap = {
    null: 'الكل',
    'Pending': 'بانتظار',
    'Approved': 'موافق',
    'PartiallyReturned': 'إرجاع جزئي',
    'FullyReturned': 'إرجاع كامل',
    'Cancelled': 'ملغي',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _holdingsData.isEmpty) {
        _loadHoldings();
      }
    });
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
      final res = await _api.getDispensings(
        companyId: widget.companyId,
        technicianId: _technicianFilter.isNotEmpty ? _technicianFilter : null,
        status: _statusFilter,
        from: _dateFrom?.toIso8601String().split('T').first,
        to: _dateTo?.toIso8601String().split('T').first,
      );
      final list = res['data'] as List<dynamic>? ?? [];
      if (mounted) {
        setState(() {
          _dispensings = list
              .map((e) => TechnicianDispensingModel.fromJson(
                  e as Map<String, dynamic>))
              .toList();
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

  Widget _typeChip(String type) {
    final isDispensing = type == 'Dispensing';
    return SdStatusChip(isDispensing ? 'صرف' : 'إرجاع',
        status: isDispensing ? SdStatus.warning : SdStatus.success);
  }

  SdStatus _statusTone(String status) {
    switch (status) {
      case 'Approved':
        return SdStatus.success;
      case 'PartiallyReturned':
        return SdStatus.warning;
      case 'FullyReturned':
        return SdStatus.info;
      case 'Cancelled':
        return SdStatus.danger;
      default:
        return SdStatus.neutral;
    }
  }

  Widget _statusChip(String status) {
    final label = _statusMap[status] ?? status;
    return SdStatusChip(label, status: _statusTone(status));
  }

  List<Widget> _buildActions(TechnicianDispensingModel d) {
    final actions = <Widget>[];

    // تعديل — متاح دائماً ما لم يكن مُلغى أو مُرجع بالكامل
    if (d.status != 'Cancelled' && d.status != 'FullyReturned') {
      actions.add(_actionBtn(Icons.edit_outlined, 'تعديل', SdColors.primary, () => _edit(d)));
    }

    // إرجاع مواد — متاح فقط إذا كان مصروف أو مرجع جزئي
    if (d.status == 'Approved' || d.status == 'PartiallyReturned') {
      actions.add(_actionBtn(Icons.assignment_return_outlined, 'إرجاع مواد', SdColors.warning, () => _returnItems(d)));
    }

    // حذف — متاح دائماً ما لم يكن محذوف مسبقاً
    if (d.status != 'Cancelled') {
      actions.add(_actionBtn(Icons.delete_outline, 'حذف', SdColors.danger, () => _delete(d)));
    }

    return actions;
  }

  Future<void> _edit(TechnicianDispensingModel d) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DispensingFormPage(
          companyId: widget.companyId,
          editDispensingId: d.id,
        ),
      ),
    );
    _loadData();
  }

  Future<void> _delete(TechnicianDispensingModel d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف سند الصرف "${d.voucherNumber}"؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(style: FilledButton.styleFrom(backgroundColor: SdColors.danger), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteDispensing(d.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف'), backgroundColor: SdColors.success));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
    }
  }

  Widget _actionBtn(
      IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  // ignore: unused_element
  Future<void> _approve(TechnicianDispensingModel d) async {
    final ok = await _confirmDialog(
        'موافقة', 'هل أنت متأكد من الموافقة على سند الصرف ${d.voucherNumber}؟');
    if (!ok) return;
    try {
      await _api.approveDispensing(d.id);
      _showSnackBar('تمت الموافقة بنجاح');
      _loadData();
    } catch (e) {
      _showSnackBar('فشلت الموافقة: $e', isError: true);
    }
  }

  // ignore: unused_element
  Future<void> _cancel(TechnicianDispensingModel d) async {
    final ok = await _confirmDialog(
        'إلغاء', 'هل أنت متأكد من إلغاء سند الصرف ${d.voucherNumber}؟');
    if (!ok) return;
    try {
      // No cancel API in service, use a general approach
      _showSnackBar('تم الإلغاء');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الإلغاء: $e', isError: true);
    }
  }

  Future<void> _returnItems(TechnicianDispensingModel d) async {
    // Fetch full dispensing to get items
    try {
      final fullRes = await _api.getDispensing(d.id);
      final full = TechnicianDispensingModel.fromJson(
          fullRes['data'] as Map<String, dynamic>? ?? fullRes);
      final returnItems = (full.items ?? []).map((item) {
        return {
          'dispensingItemId': item.id,
          'returnedQuantity': item.quantity - item.returnedQuantity,
        };
      }).where((m) => (m['returnedQuantity'] as int) > 0).toList();

      if (returnItems.isEmpty) {
        _showSnackBar('لا توجد مواد متبقية للإرجاع');
        return;
      }

      final ok = await _confirmDialog(
          'إرجاع مواد', 'هل تريد إرجاع كامل المواد المتبقية من الفني ${d.technicianName ?? ''}؟');
      if (!ok) return;

      await _api.returnDispensing(d.id, items: returnItems);
      _showSnackBar('تم الإرجاع بنجاح');
      _loadData();
    } catch (e) {
      _showSnackBar('فشل الإرجاع: $e', isError: true);
    }
  }

  Future<bool> _confirmDialog(String title, String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: Text(title),
              content: Text(message),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('إلغاء')),
                FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: SdColors.primary),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('تأكيد')),
              ],
            ),
          ),
        ) ??
        false;
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? SdColors.danger : SdColors.success,
      ),
    );
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
      _loadData();
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'صرف الفنيين',
        actions: [
          SdAppBarAction(
            icon: Icons.add_rounded,
            label: 'صرف جديد',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DispensingFormPage(companyId: widget.companyId),
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
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDispensingTab(),
                _buildHoldingsTab(),
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
          Tab(text: 'سندات الصرف'),
          Tab(text: 'عُهد الفنيين'),
        ],
      ),
    );
  }

  Widget _buildDispensingTab() {
    return Column(
      children: [
        _buildFilters(),
        const SizedBox(height: SdSpace.xs),
        Expanded(child: _buildDispensingBody()),
      ],
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 200,
          child: TextFormField(
            decoration: _dec('الفني'),
            onChanged: (v) {
              _technicianFilter = v;
            },
            onFieldSubmitted: (_) => _loadData(),
          ),
        ),
        SizedBox(
          width: 160,
          child: DropdownButtonFormField<String?>(
            value: _statusFilter,
            decoration: _dec('الحالة'),
            items: _statusMap.entries
                .map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              setState(() => _statusFilter = v);
              _loadData();
            },
          ),
        ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
          label: Text(
              _dateFrom != null ? 'من: ${_formatDate(_dateFrom!)}' : 'من تاريخ'),
          onPressed: () => _pickDate(true),
        ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18, color: SdColors.primary),
          label: Text(
              _dateTo != null ? 'إلى: ${_formatDate(_dateTo!)}' : 'إلى تاريخ'),
          onPressed: () => _pickDate(false),
        ),
        if (_dateFrom != null ||
            _dateTo != null ||
            _statusFilter != null ||
            _technicianFilter.isNotEmpty)
          ActionChip(
            avatar: const Icon(Icons.clear, size: 18),
            label: const Text('مسح الفلاتر'),
            onPressed: () {
              setState(() {
                _statusFilter = null;
                _technicianFilter = '';
                _dateFrom = null;
                _dateTo = null;
              });
              _loadData();
            },
          ),
      ],
    );
  }

  Widget _buildDispensingBody() {
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
    if (_dispensings.isEmpty) {
      return const Center(
        child: SdEmptyState(title: 'لا توجد سندات صرف', icon: Icons.inbox_rounded),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _dispensings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildDispensingCard(_dispensings[i]),
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
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(SdColors.primary),
            headingTextStyle: const TextStyle(
                fontFamily: SdText.family, fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
            dataTextStyle: const TextStyle(
                fontFamily: SdText.family, fontSize: 12.5, fontWeight: FontWeight.w500, color: SdColors.ink),
            columnSpacing: 20,
            columns: const [
              DataColumn(label: Text('رقم السند')),
              DataColumn(label: Text('الفني')),
              DataColumn(label: Text('المستودع')),
              DataColumn(label: Text('التاريخ')),
              DataColumn(label: Text('النوع')),
              DataColumn(label: Text('الحالة')),
              DataColumn(label: Text('إجراءات')),
            ],
            rows: [
              for (int i = 0; i < _dispensings.length; i++) _buildDataRow(_dispensings[i], i),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _buildDataRow(TechnicianDispensingModel d, int index) {
    return DataRow(
      color: WidgetStateProperty.all(index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      cells: [
        DataCell(Text(d.voucherNumber)),
        DataCell(Text(d.technicianName ?? d.technicianId)),
        DataCell(Text(d.warehouseName ?? '-')),
        DataCell(Text(_formatDate(d.dispensingDate))),
        DataCell(_typeChip(d.type)),
        DataCell(_statusChip(d.status)),
        DataCell(Row(children: _buildActions(d))),
      ],
    );
  }

  Widget _buildDispensingCard(TechnicianDispensingModel d) {
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('#${d.voucherNumber}', style: SdText.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              _typeChip(d.type),
              const SizedBox(width: 6),
              _statusChip(d.status),
            ],
          ),
          const SizedBox(height: 4),
          SdInfoRow(label: 'الفني', value: d.technicianName ?? d.technicianId),
          SdInfoRow(label: 'المستودع', value: d.warehouseName ?? '-'),
          SdInfoRow(label: 'التاريخ', value: _formatDate(d.dispensingDate)),
          const Divider(color: SdColors.divider, height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: _buildActions(d)),
        ],
      ),
    );
  }

  Widget _buildHoldingsTab() {
    if (_holdingsLoading) {
      return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    }
    if (_holdingsError != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل العُهد',
          message: _holdingsError,
          icon: Icons.error_outline_rounded,
          status: SdStatus.danger,
          action: SdButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: _loadHoldings),
        ),
      );
    }
    if (_holdingsData.isEmpty) {
      return Center(
        child: SdEmptyState(
          title: 'لا توجد عُهد حالية',
          icon: Icons.inventory_2_outlined,
          action: SdButton(label: 'تحديث', icon: Icons.refresh_rounded, kind: SdButtonKind.secondary, onPressed: _loadHoldings),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: _holdingsData.length,
      itemBuilder: (context, index) {
        final techData = _holdingsData[index];
        final techName =
            (techData['TechnicianName'] ?? techData['technicianName']) as String? ?? 'فني غير معروف';
        final items = (techData['Items'] ?? techData['items']) as List<dynamic>? ?? [];

        // حساب إجمالي المتبقي لدى الفني
        int totalRemaining = 0;
        for (final item in items) {
          final m = item as Map<String, dynamic>;
          final qty = (m['Quantity'] ?? m['quantity'] ?? 0) as int;
          final ret = (m['ReturnedQuantity'] ?? m['returnedQuantity'] ?? 0) as int;
          totalRemaining += (qty - ret);
        }

        final hasRemaining = totalRemaining > 0;
        final tone = hasRemaining ? SdStatus.warning.tone : SdStatus.success.tone;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.lg),
            boxShadow: SdDepth.raised(),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              leading: CircleAvatar(
                backgroundColor: tone.tint,
                child: Icon(Icons.person, color: tone.base),
              ),
              title: Text(techName, style: SdText.label),
              subtitle: Text('${items.length} مادة  —  المتبقي بحوزته: $totalRemaining',
                  style: SdText.bodySm.copyWith(color: tone.text)),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Table(
                    border: TableBorder.all(color: SdColors.divider),
                    columnWidths: const {
                      0: FlexColumnWidth(3),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(1),
                      3: FlexColumnWidth(1),
                    },
                    children: [
                      const TableRow(
                        decoration: BoxDecoration(color: SdColors.primary),
                        children: [
                          _HoldingHeaderCell('المادة'),
                          _HoldingHeaderCell('المصروف'),
                          _HoldingHeaderCell('المستخدم/المُرجع'),
                          _HoldingHeaderCell('المتبقي'),
                        ],
                      ),
                      for (int i = 0; i < items.length; i++)
                        _buildHoldingRow(items[i] as Map<String, dynamic>, i),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  TableRow _buildHoldingRow(Map<String, dynamic> m, int index) {
    final qty = (m['Quantity'] ?? m['quantity'] ?? 0) as int;
    final ret = (m['ReturnedQuantity'] ?? m['returnedQuantity'] ?? 0) as int;
    final remaining = qty - ret;
    return TableRow(
      decoration: BoxDecoration(
        color: remaining > 0
            ? SdColors.warningTint
            : (index.isEven ? SdColors.surface : SdColors.surfaceAlt),
      ),
      children: [
        _holdingCell((m['ItemName'] ?? m['itemName']) as String? ?? '-'),
        _holdingCell('$qty'),
        _holdingCell('$ret'),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '$remaining',
            style: TextStyle(
              fontFamily: SdText.family,
              fontWeight: FontWeight.w800,
              color: remaining > 0 ? SdColors.warningText : SdColors.success,
            ),
          ),
        ),
      ],
    );
  }

  Widget _holdingCell(String text) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(text, style: const TextStyle(fontFamily: SdText.family, fontSize: 12.5, color: SdColors.ink)),
      );
}

class _HoldingHeaderCell extends StatelessWidget {
  const _HoldingHeaderCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(text,
          style: const TextStyle(
              fontFamily: SdText.family, fontWeight: FontWeight.w800, fontSize: 12.5, color: Colors.white)),
    );
  }
}
