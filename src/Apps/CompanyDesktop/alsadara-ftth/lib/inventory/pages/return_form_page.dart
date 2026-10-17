import '../utils/format_utils.dart';
import 'package:flutter/material.dart';
import '../../frontend/frontend.dart';
import '../services/inventory_api_service.dart';

class ReturnFormPage extends StatefulWidget {
  final String companyId;
  final String returnType; // 'SalesReturn' or 'PurchaseReturn'
  final String? invoiceId;

  const ReturnFormPage({
    super.key,
    required this.companyId,
    required this.returnType,
    this.invoiceId,
  });

  @override
  State<ReturnFormPage> createState() => _ReturnFormPageState();
}

class _ReturnFormPageState extends State<ReturnFormPage> {
  final _api = InventoryApiService.instance;
  final _formKey = GlobalKey<FormState>();

  bool _loading = true;
  bool _saving = false;
  bool _loadingItems = false;

  List<Map<String, dynamic>> _invoices = [];
  String? _selectedInvoiceId;
  List<Map<String, dynamic>> _invoiceItems = [];
  List<TextEditingController> _qtyControllers = [];

  String _refundMethod = 'Cash'; // Cash, Credit, None
  String? _selectedCashBoxId;
  List<Map<String, dynamic>> _cashBoxes = [];
  final _reasonController = TextEditingController();

  static const _refundMethods = {
    'Cash': 'نقد',
    'Credit': 'خصم من الرصيد',
    'None': 'بدون',
  };

  @override
  void initState() {
    super.initState();
    _selectedInvoiceId = widget.invoiceId;
    _loadDropdowns();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    for (final c in _qtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    try {
      final invoiceType =
          widget.returnType == 'SalesReturn' ? 'Sales' : 'Purchase';
      final results = await Future.wait([
        _api.getInvoices(
          companyId: widget.companyId,
          type: invoiceType,
          status: 'Confirmed',
        ),
        _api.getWarehouses(companyId: widget.companyId),
      ]);

      final invList = (results[0]['data'] as List<dynamic>?) ?? [];
      final whList = (results[1]['data'] as List<dynamic>?) ?? [];

      if (mounted) {
        setState(() {
          _invoices = invList.cast<Map<String, dynamic>>();
          _cashBoxes = whList.cast<Map<String, dynamic>>();
          _loading = false;
        });

        // If invoiceId was pre-set, load its items
        if (_selectedInvoiceId != null) {
          _loadInvoiceItems(_selectedInvoiceId!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnackBar('فشل تحميل البيانات: $e', isError: true);
      }
    }
  }

  Future<void> _loadInvoiceItems(String invoiceId) async {
    setState(() => _loadingItems = true);
    try {
      final res = await _api.getInvoice(invoiceId);
      final data = res['data'] as Map<String, dynamic>? ?? res;
      final items = (data['Items'] ?? data['items'] ?? []) as List<dynamic>;

      // Dispose old controllers
      for (final c in _qtyControllers) {
        c.dispose();
      }

      if (mounted) {
        setState(() {
          _invoiceItems = items.cast<Map<String, dynamic>>();
          _qtyControllers = List.generate(
            _invoiceItems.length,
            (_) => TextEditingController(text: '0'),
          );
          _loadingItems = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingItems = false);
        _showSnackBar('فشل تحميل بنود الفاتورة: $e', isError: true);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedInvoiceId == null) {
      _showSnackBar('يرجى اختيار الفاتورة الأصلية', isError: true);
      return;
    }

    // Validate at least one item has qty > 0
    final returnItems = <Map<String, dynamic>>[];
    for (var i = 0; i < _invoiceItems.length; i++) {
      final qty = int.tryParse(_qtyControllers[i].text) ?? 0;
      if (qty > 0) {
        final item = _invoiceItems[i];
        returnItems.add({
          'inventoryItemId':
              (item['InventoryItemId'] ?? item['inventoryItemId'] ?? '').toString(),
          'itemName': (item['ItemName'] ?? item['itemName'] ?? '').toString(),
          'quantity': qty,
          'unitPrice': item['UnitPrice'] ?? item['unitPrice'] ?? 0,
        });
      }
    }

    if (returnItems.isEmpty) {
      _showSnackBar('يرجى إدخال كمية مرتجعة لبند واحد على الأقل',
          isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final data = {
        'returnType': widget.returnType == 'SalesReturn' ? 0 : 1,
        'invoiceId': _selectedInvoiceId,
        'items': returnItems,
        'reason': _reasonController.text,
        'refundMethod': _refundMethod,
        'cashBoxId':
            _refundMethod == 'Cash' ? _selectedCashBoxId : null,
        'companyId': widget.companyId,
      };

      final createRes = await _api.createReturn(data: data);
      final returnId =
          (createRes['data']?['Id'] ?? createRes['data']?['id'] ?? createRes['id'] ?? '')
              .toString();

      // Auto-confirm
      if (returnId.isNotEmpty) {
        await _api.confirmReturn(returnId);
      }

      if (mounted) {
        _showSnackBar('تم إنشاء المرتجع وتأكيده بنجاح');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('فشل الحفظ: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  InputDecoration _dec(String? label, {bool dense = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: SdText.bodySm,
      filled: true,
      fillColor: SdColors.surface,
      isDense: dense,
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.returnType == 'SalesReturn'
        ? 'مرتجع مبيعات'
        : 'مرتجع مشتريات';

    return SdPage(
      scrollable: false,
      maxWidth: SdSpace.formMax,
      appBar: SdAppBar(title: title),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: SdColors.primary))
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // الخطوة 1: اختيار الفاتورة
          SdCard(
            title: '1. اختر الفاتورة الأصلية',
            icon: Icons.receipt_long_rounded,
            child: DropdownButtonFormField<String>(
              value: _selectedInvoiceId,
              isExpanded: true,
              style: SdText.label,
              decoration: _dec('الفاتورة'),
              items: _invoices.map((e) {
                final id = (e['Id'] ?? e['id'] ?? '').toString();
                final num =
                    (e['InvoiceNumber'] ?? e['invoiceNumber'] ?? '-').toString();
                final name =
                    (e['EntityName'] ?? e['entityName'] ?? '').toString();
                return DropdownMenuItem(
                    value: id,
                    child: Text('$num - $name', overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: widget.invoiceId != null
                  ? null
                  : (v) {
                      setState(() => _selectedInvoiceId = v);
                      if (v != null) _loadInvoiceItems(v);
                    },
              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
            ),
          ),
          const SizedBox(height: SdSpace.lg),

          // الخطوة 2: الكميات + التفاصيل
          if (_loadingItems)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: SdColors.primary),
              ),
            )
          else if (_invoiceItems.isNotEmpty) ...[
            _buildItemsCard(),
            const SizedBox(height: SdSpace.lg),
            _buildDetailsCard(),
            const SizedBox(height: SdSpace.xl),
            _buildSaveButton(),
            const SizedBox(height: SdSpace.md),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsCard() {
    final phone = context.sd.isPhone;
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SdSectionHeader(title: '2. حدد كميات الإرجاع'),
          if (phone)
            for (var i = 0; i < _invoiceItems.length; i++) _itemCardPhone(i)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _itemsTable(),
            ),
        ],
      ),
    );
  }

  Widget _itemsTable() {
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
              _HeaderCell('الكمية الأصلية'),
              _HeaderCell('كمية الإرجاع'),
            ],
          ),
          for (var i = 0; i < _invoiceItems.length; i++) _dataRow(i),
        ],
      ),
    );
  }

  TableRow _dataRow(int i) {
    final m = _invoiceItems[i];
    final originalQty = (m['Quantity'] ?? m['quantity'] ?? 0);
    return TableRow(
      decoration: BoxDecoration(
        color: i.isEven ? SdColors.surface : SdColors.surfaceAlt,
      ),
      children: [
        _DataCell((m['ItemName'] ?? m['itemName'] ?? '-').toString()),
        _DataCell(fmtN(originalQty)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SizedBox(
            width: 80,
            child: _qtyField(i, originalQty),
          ),
        ),
      ],
    );
  }

  Widget _qtyField(int i, dynamic originalQty) {
    return TextFormField(
      controller: _qtyControllers[i],
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: SdText.label,
      decoration: _dec(null, dense: true),
      validator: (v) {
        final qty = int.tryParse(v ?? '') ?? 0;
        final max = (originalQty is int)
            ? originalQty
            : (int.tryParse('$originalQty') ?? 0);
        if (qty < 0) return 'غير صالح';
        if (qty > max) return 'أكبر من المتاح';
        return null;
      },
    );
  }

  Widget _itemCardPhone(int i) {
    final m = _invoiceItems[i];
    final originalQty = (m['Quantity'] ?? m['quantity'] ?? 0);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(SdSpace.sm),
      decoration: BoxDecoration(
        color: SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.md),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text((m['ItemName'] ?? m['itemName'] ?? '-').toString(), style: SdText.label),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text('الأصلية: ${fmtN(originalQty)}', style: SdText.bodySm),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: _qtyField(i, originalQty),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // السبب
          TextFormField(
            controller: _reasonController,
            maxLines: 2,
            style: SdText.label,
            decoration: _dec('سبب الإرجاع'),
          ),
          const SizedBox(height: 16),

          // طريقة الاسترداد
          DropdownButtonFormField<String>(
            value: _refundMethod,
            style: SdText.label,
            decoration: _dec('طريقة الاسترداد'),
            items: _refundMethods.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _refundMethod = v ?? 'Cash'),
          ),

          // الصندوق (إذا الاسترداد نقد)
          if (_refundMethod == 'Cash') ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCashBoxId,
              isExpanded: true,
              style: SdText.label,
              decoration: _dec('الصندوق'),
              items: _cashBoxes.map((e) {
                final id = (e['Id'] ?? e['id'] ?? '').toString();
                final name = (e['Name'] ?? e['name'] ?? '-').toString();
                return DropdownMenuItem(
                    value: id, child: Text(name, overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (v) => setState(() => _selectedCashBoxId = v),
              validator: (v) =>
                  _refundMethod == 'Cash' && (v == null || v.isEmpty)
                      ? 'مطلوب'
                      : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    if (_saving) {
      return Opacity(
        opacity: .7,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SdRadius.md),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SdColors.primaryMid, SdColors.primary],
            ),
            boxShadow: const [BoxShadow(color: SdColors.primaryEdge, offset: Offset(0, 6))],
          ),
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
          ),
        ),
      );
    }
    return SdButton(
      label: 'إنشاء وتأكيد المرتجع',
      icon: Icons.assignment_return,
      expand: true,
      onPressed: _save,
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
  const _DataCell(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontFamily: SdText.family,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: SdColors.ink),
      ),
    );
  }
}
