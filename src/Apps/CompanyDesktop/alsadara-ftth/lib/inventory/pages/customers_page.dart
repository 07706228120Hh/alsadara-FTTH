import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../services/inventory_api_service.dart';
import 'customer_form_page.dart';
import 'customer_details_page.dart';

class CustomersPage extends StatefulWidget {
  final String companyId;
  const CustomersPage({super.key, required this.companyId});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  final _api = InventoryApiService.instance;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _customers = [];

  final _searchCtrl = TextEditingController();
  String _selectedType = 'الكل';

  static const List<String> _typeFilters = ['الكل', 'نقدي', 'آجل', 'VIP'];

  /// Maps Arabic filter label to the API type value
  static const Map<String, String> _typeToApi = {
    'نقدي': 'Cash',
    'آجل': 'Credit',
    'VIP': 'VIP',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.getCustomers(
        companyId: widget.companyId,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        type: _selectedType == 'الكل' ? null : _typeToApi[_selectedType],
      );
      final list = (res['data'] as List<dynamic>?) ?? [];
      _customers = list.cast<Map<String, dynamic>>();
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  // --------------- helpers ---------------

  String _v(Map<String, dynamic> m, String key) {
    // Backend uses PascalCase (PropertyNamingPolicy = null)
    final pascal = key[0].toUpperCase() + key.substring(1);
    final val = m[pascal] ?? m[key];
    return val?.toString() ?? '';
  }

  dynamic _raw(Map<String, dynamic> m, String key) {
    final pascal = key[0].toUpperCase() + key.substring(1);
    return m[pascal] ?? m[key];
  }

  // --------------- navigation ---------------

  Future<void> _navigateToAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormPage(companyId: widget.companyId),
      ),
    );
    _loadData();
  }

  Future<void> _navigateToEdit(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormPage(companyId: widget.companyId, customerId: id),
      ),
    );
    _loadData();
  }

  Future<void> _navigateToDetails(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerDetailsPage(companyId: widget.companyId, customerId: id),
      ),
    );
    _loadData();
  }

  // --------------- delete ---------------

  Future<void> _confirmDelete(Map<String, dynamic> m) async {
    final name = _v(m, 'name');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف العميل "$name"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final id = _v(m, 'id');
      await _api.deleteCustomer(id);
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  // --------------- type chip ---------------

  Widget _typeChip(String type) {
    Color bg;
    Color fg;
    String label;
    switch (type) {
      case 'Cash':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        label = 'نقدي';
        break;
      case 'Credit':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        label = 'آجل';
        break;
      case 'VIP':
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade800;
        label = 'VIP';
        break;
      default:
        bg = Colors.grey.shade100;
        fg = Colors.grey.shade700;
        label = type.isEmpty ? '-' : type;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  // --------------- build ---------------

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F6FA),
          foregroundColor: const Color(0xFF1A1A2E),
          iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
          titleTextStyle: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 18, fontWeight: FontWeight.w700),
          elevation: 0,
          title: const Text('العملاء'),
          actions: [
            TextButton.icon(
              onPressed: _navigateToAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('عميل جديد +'),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: _loadData,
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الكود أو الهاتف...',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _loadData();
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => _loadData(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: DropdownButtonFormField<String>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'النوع',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _typeFilters
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                _selectedType = v ?? 'الكل';
                _loadData();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
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
    if (_customers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('لا يوجد عملاء', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _navigateToAdd,
              icon: const Icon(Icons.add),
              label: const Text('إضافة عميل'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
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
            0: FlexColumnWidth(1.2), // الكود
            1: FlexColumnWidth(2.5), // الاسم
            2: FlexColumnWidth(1.8), // الهاتف
            3: FlexColumnWidth(1.2), // النوع
            4: FlexColumnWidth(1.5), // سقف الائتمان
            5: FlexColumnWidth(1.5), // الرصيد
            6: FlexColumnWidth(1.2), // إجراءات
          },
          children: [
            // ── Header ──
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFECEFF5)),
              children: ['الكود', 'الاسم', 'الهاتف', 'النوع', 'سقف الائتمان', 'الرصيد', 'إجراءات']
                  .map((h) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        child: Center(
                          child: Text(h, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade800)),
                        ),
                      ))
                  .toList(),
            ),
            // ── Rows ──
            for (int i = 0; i < _customers.length; i++)
              _buildRow(_customers[i], i),
          ],
        ),
      ),
    );
  }

  TableRow _buildRow(Map<String, dynamic> m, int index) {
    final code = _v(m, 'customerCode');
    final name = _v(m, 'name');
    final phone = _v(m, 'phone');
    final type = _v(m, 'customerType');
    final creditLimit = _raw(m, 'creditLimit');
    final balance = _raw(m, 'balance');
    final balanceNum = balance is num ? balance : (num.tryParse('$balance') ?? 0);
    final id = _v(m, 'id');

    return TableRow(
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : const Color(0xFFF8F9FC),
      ),
      children: [
        _tappableCell(id, child: _cellText(code.isEmpty ? '-' : code)),
        _tappableCell(id, child: _cellText(name, bold: true)),
        _tappableCell(id, child: _cellText(phone.isEmpty ? '-' : phone)),
        _tappableCell(
          id,
          child: Center(child: _typeChip(type)),
        ),
        _tappableCell(id, child: _cellText(creditLimit != null ? fmtN(creditLimit) : '-')),
        _tappableCell(
          id,
          child: Center(
            child: Text(
              balanceNum == 0 ? '0' : fmtN(balanceNum),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: balanceNum > 0 ? Colors.red.shade700 : Colors.green.shade700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  tooltip: 'تعديل',
                  onPressed: () => _navigateToEdit(id),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  tooltip: 'حذف',
                  onPressed: () => _confirmDelete(m),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Wraps a cell so the whole row area is tappable to open details.
  Widget _tappableCell(String id, {required Widget child}) {
    return InkWell(
      onTap: () => _navigateToDetails(id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: child,
      ),
    );
  }

  Widget _cellText(String text, {bool bold = false}) {
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: const Color(0xFF1A1A2E),
        ),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}
