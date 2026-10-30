import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../widgets/inv_frame.dart';
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
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد الحذف'),
          content: Text('هل تريد حذف العميل "$name"؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SdColors.danger, side: const BorderSide(color: kInvFrameEdge, width: kInvFrameWidth)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
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
    late final String label;
    late final SdTone tone;
    switch (type) {
      case 'Cash':
        label = 'نقدي';
        tone = SdStatus.success.tone;
        break;
      case 'Credit':
        label = 'آجل';
        tone = SdStatus.warning.tone;
        break;
      case 'VIP':
        label = 'VIP';
        tone = SdGroup.platform.tone;
        break;
      default:
        label = type.isEmpty ? '-' : type;
        tone = SdGroup.neutral.tone;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        boxShadow: [BoxShadow(color: tone.tintEdge, offset: const Offset(0, SdDepth.chip))],
      ),
      child: Text(label,
          style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: tone.text)),
    );
  }

  // --------------- build ---------------

  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      appBar: SdAppBar(
        title: 'العملاء',
        actions: [
          SdAppBarAction(
            icon: Icons.add_rounded,
            label: 'عميل جديد',
            onPressed: _navigateToAdd,
          ),
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loadData,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSearchBar(),
          const SizedBox(height: SdSpace.sm),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final searchField = TextField(
      controller: _searchCtrl,
      style: SdText.body,
      decoration: InputDecoration(
        hintText: 'بحث بالاسم أو الكود أو الهاتف...',
        hintStyle: SdText.bodySm,
        prefixIcon: const Icon(Icons.search, color: SdColors.faint),
        filled: true,
        fillColor: SdColors.surface,
        isDense: true,
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
        suffixIcon: _searchCtrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18, color: SdColors.faint),
                onPressed: () {
                  _searchCtrl.clear();
                  _loadData();
                },
              )
            : null,
      ),
      onSubmitted: (_) => _loadData(),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField,
        const SizedBox(height: SdSpace.sm),
        SdFilterChips<String>(
          options: [for (final t in _typeFilters) SdFilterOption(t, t)],
          selected: _selectedType,
          onSelected: (v) {
            _selectedType = v;
            _loadData();
          },
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: SdColors.primary));
    if (_error != null) {
      return Center(
        child: SdEmptyState(
          title: 'تعذّر تحميل العملاء',
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
    if (_customers.isEmpty) {
      return Center(
        child: SdEmptyState(
          title: 'لا يوجد عملاء',
          icon: Icons.people_outline_rounded,
          action: SdButton(
            label: 'إضافة عميل',
            icon: Icons.add_rounded,
            onPressed: _navigateToAdd,
          ),
        ),
      );
    }

    if (context.sd.isPhone) {
      return ListView.separated(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        itemCount: _customers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _buildCard(_customers[i]),
      );
    }

    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: SdColors.surface,
          borderRadius: BorderRadius.circular(SdRadius.lg),
          boxShadow: SdDepth.raised(),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
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
            TableRow(
              decoration: const BoxDecoration(color: SdColors.primary),
              children: ['الكود', 'الاسم', 'الهاتف', 'النوع', 'سقف الائتمان', 'الرصيد', 'إجراءات']
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
            for (int i = 0; i < _customers.length; i++) _buildRow(_customers[i], i),
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
        color: index.isEven ? SdColors.surface : SdColors.surfaceAlt,
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
                fontFamily: SdText.family,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: balanceNum > 0 ? SdColors.danger : SdColors.success,
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
                  icon: const Icon(Icons.edit, size: 20, color: SdColors.primary),
                  tooltip: 'تعديل',
                  onPressed: () => _navigateToEdit(id),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: SdColors.danger),
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

  Widget _buildCard(Map<String, dynamic> m) {
    final code = _v(m, 'customerCode');
    final name = _v(m, 'name');
    final phone = _v(m, 'phone');
    final type = _v(m, 'customerType');
    final creditLimit = _raw(m, 'creditLimit');
    final balance = _raw(m, 'balance');
    final balanceNum = balance is num ? balance : (num.tryParse('$balance') ?? 0);
    final id = _v(m, 'id');

    return GestureDetector(
      onTap: () => _navigateToDetails(id),
      child: InvCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: SdText.label, maxLines: 2, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                _typeChip(type),
              ],
            ),
            if (code.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('الكود: $code', style: SdText.caption),
            ],
            const SizedBox(height: 4),
            if (phone.isNotEmpty) SdInfoRow(label: 'الهاتف', value: phone, ltrValue: true),
            SdInfoRow(label: 'سقف الائتمان', value: creditLimit != null ? fmtN(creditLimit) : '-'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text('الرصيد', style: SdText.bodySm),
                  const Spacer(),
                  Text(
                    balanceNum == 0 ? '0' : fmtN(balanceNum),
                    style: TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: balanceNum > 0 ? SdColors.danger : SdColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: SdColors.divider, height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _navigateToEdit(id),
                  icon: const Icon(Icons.edit, size: 18, color: SdColors.primary),
                  label: const Text('تعديل', style: TextStyle(color: SdColors.primary)),
                ),
                TextButton.icon(
                  onPressed: () => _confirmDelete(m),
                  icon: const Icon(Icons.delete, size: 18, color: SdColors.danger),
                  label: const Text('حذف', style: TextStyle(color: SdColors.danger)),
                ),
              ],
            ),
          ],
        ),
      ),
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
          fontFamily: SdText.family,
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: SdColors.ink,
        ),
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}
