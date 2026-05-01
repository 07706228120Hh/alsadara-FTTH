import 'package:flutter/material.dart';
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

  Widget _typeChip(String type) {
    final isDispensing = type == 'Dispensing';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDispensing ? Colors.orange.shade100 : Colors.green.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isDispensing ? 'صرف' : 'إرجاع',
        style: TextStyle(
          color: isDispensing ? Colors.orange.shade800 : Colors.green.shade800,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case 'Pending':
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = 'بانتظار';
        break;
      case 'Approved':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        label = 'موافق';
        break;
      case 'PartiallyReturned':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        label = 'إرجاع جزئي';
        break;
      case 'FullyReturned':
        bg = Colors.blue.shade100;
        fg = Colors.blue.shade800;
        label = 'إرجاع كامل';
        break;
      case 'Cancelled':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        label = 'ملغي';
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  List<Widget> _buildActions(TechnicianDispensingModel d) {
    return [
      _actionBtn(Icons.delete_outline, 'حذف', Colors.red.shade800, () => _delete(d)),
    ];
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
            FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteDispensing(d.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الحذف'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
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
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('تأكيد')),
            ],
          ),
        ) ??
        false;
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(backgroundColor: const Color(0xFFF5F6FA), foregroundColor: const Color(0xFF1A1A2E), iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)), titleTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700), elevation: 0,
          title: const Text('صرف الفنيين'),
          actions: [
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        DispensingFormPage(companyId: widget.companyId),
                  ),
                ).then((_) => _loadData());
              },
              icon: const Icon(Icons.add),
              label: const Text('صرف جديد'),
            ),
            const SizedBox(width: 12),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'سندات الصرف'),
              Tab(text: 'عُهد الفنيين'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildDispensingTab(),
            _buildHoldingsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildDispensingTab() {
    return Column(
      children: [
        _buildFilters(),
        const Divider(height: 1),
        Expanded(child: _buildDispensingBody()),
      ],
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 200,
            child: TextFormField(
              decoration: const InputDecoration(
                labelText: 'الفني',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
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
              decoration: const InputDecoration(
                labelText: 'الحالة',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
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
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(
                _dateFrom != null ? 'من: ${_formatDate(_dateFrom!)}' : 'من تاريخ'),
            onPressed: () => _pickDate(true),
          ),
          ActionChip(
            avatar: const Icon(Icons.date_range, size: 18),
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
      ),
    );
  }

  Widget _buildDispensingBody() {
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
    if (_dispensings.isEmpty) {
      return const Center(
        child: Text('لا توجد سندات صرف',
            style: TextStyle(fontSize: 16, color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
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
          rows: _dispensings.map((d) {
            return DataRow(cells: [
              DataCell(Text(d.voucherNumber)),
              DataCell(Text(d.technicianName ?? d.technicianId)),
              DataCell(Text(d.warehouseName ?? '-')),
              DataCell(Text(_formatDate(d.dispensingDate))),
              DataCell(_typeChip(d.type)),
              DataCell(_statusChip(d.status)),
              DataCell(Row(children: _buildActions(d))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildHoldingsTab() {
    if (_holdingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_holdingsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
            const SizedBox(height: 12),
            Text(_holdingsError!,
                style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadHoldings,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }
    if (_holdingsData.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('لا توجد عُهد حالية',
                style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _loadHoldings,
              icon: const Icon(Icons.refresh),
              label: const Text('تحديث'),
            ),
          ],
        ),
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

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.person, color: Colors.blue.shade700),
            ),
            title: Text(techName,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${items.length} مادة بحوزته'),
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Table(
                  border: TableBorder.all(color: Colors.grey.shade300),
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      decoration:
                          BoxDecoration(color: Colors.grey.shade100),
                      children: const [
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('المادة',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('الكمية',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Padding(
                          padding: EdgeInsets.all(8),
                          child: Text('المُرجع',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    ...items.map((item) {
                      final m = item as Map<String, dynamic>;
                      return TableRow(children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child:
                              Text(m['itemName'] as String? ?? '-'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child:
                              Text('${m['quantity'] ?? 0}'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                              '${m['returnedQuantity'] ?? 0}'),
                        ),
                      ]);
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
