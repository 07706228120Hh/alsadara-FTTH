import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../frontend/frontend.dart';
import '../models/receipt_template_models.dart';
import '../services/receipt_template_storage.dart';
import '../services/receipt_pdf_builder.dart';
import '../services/print_template_storage.dart';
import '../services/thermal_printer_service.dart';

/// صفحة محرر قالب الوصل المرئي
class ReceiptTemplateEditorPage extends StatefulWidget {
  const ReceiptTemplateEditorPage({super.key});

  @override
  State<ReceiptTemplateEditorPage> createState() =>
      _ReceiptTemplateEditorPageState();
}

class _ReceiptTemplateEditorPageState extends State<ReceiptTemplateEditorPage> {
  ReceiptTemplate _template = ReceiptTemplate.defaultTemplate();
  String? _selectedRowId;
  String? _selectedCellId;
  Uint8List? _previewImage;
  bool _isLoadingPreview = false;
  bool _isSaving = false;
  Timer? _previewDebounce;
  Map<String, String> _companyValues = {};
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    final template = await ReceiptTemplateStorageV2.loadTemplate();
    await _loadCompanyValues();
    await _loadLogoBytes();
    setState(() => _template = template);
    _regeneratePreview();
  }

  /// تحميل اللوغو: مخصص (SharedPreferences) أو الافتراضي (assets)
  static const _logoKey = 'receipt_custom_logo';

  Future<void> _loadLogoBytes() async {
    // أولاً: لوغو مخصص
    final prefs = await SharedPreferences.getInstance();
    final customLogo = prefs.getString(_logoKey);
    if (customLogo != null && customLogo.isNotEmpty) {
      _logoBytes = base64Decode(customLogo);
      return;
    }
    // ثانياً: اللوغو الافتراضي
    try {
      final data = await rootBundle.load('assets/logo.png');
      _logoBytes = data.buffer.asUint8List();
    } catch (_) {}
  }

  Future<void> _pickCustomLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    final bytes = await File(path).readAsBytes();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_logoKey, base64Encode(bytes));
    _logoBytes = bytes;
    _onTemplateChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير الشعار'), backgroundColor: SdColors.success, duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _resetLogo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_logoKey);
    await _loadLogoBytes();
    _onTemplateChanged();
  }

  Future<void> _loadCompanyValues() async {
    final pt = await PrintTemplateStorage.loadTemplate();
    _companyValues = {
      'companyName': pt.companyName,
      'companySubtitle': pt.companySubtitle,
      'contactInfo': pt.contactInfo,
      'footerMessage': pt.footerMessage,
    };
  }

  void _onTemplateChanged() {
    _previewDebounce?.cancel();
    _previewDebounce =
        Timer(const Duration(milliseconds: 400), _regeneratePreview);
  }

  Future<void> _regeneratePreview() async {
    if (_isLoadingPreview) return;
    setState(() => _isLoadingPreview = true);

    try {
      final previewValues = {
        ...TemplateVariableRegistry.sampleValues,
        ..._companyValues,
      };
      final builder = ReceiptPdfBuilder(
        template: _template,
        variableValues: previewValues,
        conditions: {
          'showCustomerInfo': true,
          'showServiceDetails': true,
          'showPaymentDetails': true,
          'showAdditionalInfo': false,
          'showContactInfo': true,
          'hasNotes': true,
        },
        logoImageBytes: _logoBytes,
      );
      final bytes = await builder.buildBytes();
      final pages = Printing.raster(bytes, pages: [0], dpi: 150);
      await for (final page in pages) {
        final image = await page.toPng();
        if (mounted) {
          setState(() {
            _previewImage = image;
            _isLoadingPreview = false;
          });
        }
        break; // صفحة واحدة فقط
      }
    } catch (e) {
      debugPrint('❌ خطأ في المعاينة');
      if (mounted) setState(() => _isLoadingPreview = false);
    }
  }

  Future<void> _saveTemplate() async {
    setState(() => _isSaving = true);
    try {
      await ReceiptTemplateStorageV2.saveTemplate(_template);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ القالب بنجاح'),
            backgroundColor: SdColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _resetTemplate() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SdColors.surface,
        title: const Text('استعادة القالب الافتراضي', style: SdText.titleSm),
        content: const Text(
            'سيتم حذف جميع التعديلات والعودة للقالب الأصلي. هل أنت متأكد؟',
            style: SdText.body),
        actions: [
          SdButton(
            label: 'إلغاء',
            kind: SdButtonKind.secondary,
            height: 44,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          SdButton(
            label: 'استعادة',
            kind: SdButtonKind.danger,
            height: 44,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ReceiptTemplateStorageV2.resetTemplate();
      setState(() {
        _template = ReceiptTemplate.defaultTemplate();
        _selectedRowId = null;
        _selectedCellId = null;
      });
      _regeneratePreview();
    }
  }

  Future<void> _resetReceiptCounter() async {
    final current = await ThermalPrinterService.getCurrentReceiptCounter();
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SdColors.surface,
        title: const Text('تصفير عداد الوصل', style: SdText.titleSm),
        content: Text(
            'العداد الحالي: $current\nسيتم إعادة تعيينه إلى 0. هل أنت متأكد؟',
            style: SdText.body),
        actions: [
          SdButton(
            label: 'إلغاء',
            kind: SdButtonKind.secondary,
            height: 44,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          SdButton(
            label: 'تصفير',
            kind: SdButtonKind.danger,
            height: 44,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ThermalPrinterService.resetReceiptCounter();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصفير عداد الوصل'),
            backgroundColor: SdColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ==================== Row Operations ====================

  void _updateRow(String rowId, ReceiptRow Function(ReceiptRow) updater) {
    setState(() {
      _template = _template.copyWith(
        rows:
            _template.rows.map((r) => r.id == rowId ? updater(r) : r).toList(),
      );
    });
    _onTemplateChanged();
  }

  void _updateCell(
      String rowId, String cellId, ReceiptCell Function(ReceiptCell) updater) {
    _updateRow(rowId, (row) {
      return row.copyWith(
        cells: row.cells.map((c) => c.id == cellId ? updater(c) : c).toList(),
      );
    });
  }

  void _addRow(ReceiptRowType type) {
    final id = generateReceiptId();
    ReceiptRow newRow;
    switch (type) {
      case ReceiptRowType.divider:
        newRow = ReceiptRow(id: id, type: type, dividerThickness: 1);
        break;
      case ReceiptRowType.spacer:
        newRow = ReceiptRow(id: id, type: type, spacerHeight: 5);
        break;
      case ReceiptRowType.centeredText:
        newRow = ReceiptRow(
          id: id,
          type: type,
          cells: [
            ReceiptCell(
                id: generateReceiptId(),
                content: 'نص جديد',
                alignment: ReceiptCellAlignment.center)
          ],
        );
        break;
      case ReceiptRowType.image:
        newRow = ReceiptRow(id: id, type: type, imageWidth: 60, imageHeight: 60);
        break;
      case ReceiptRowType.cells:
        newRow = ReceiptRow(
          id: id,
          type: type,
          decoration: const ReceiptBoxDecoration(),
          cells: [
            ReceiptCell(
                id: generateReceiptId(),
                content: 'تسمية:',
                flex: 3,
                isLabel: true,
                alignment: ReceiptCellAlignment.right),
            ReceiptCell(
                id: generateReceiptId(),
                content: '{{customerName}}',
                flex: 4,
                alignment: ReceiptCellAlignment.left),
          ],
        );
        break;
    }
    setState(() {
      _template = _template.copyWith(rows: [..._template.rows, newRow]);
      _selectedRowId = id;
      _selectedCellId = null;
    });
    _onTemplateChanged();
  }

  void _deleteRow(String rowId) {
    setState(() {
      _template = _template.copyWith(
          rows: _template.rows.where((r) => r.id != rowId).toList());
      if (_selectedRowId == rowId) {
        _selectedRowId = null;
        _selectedCellId = null;
      }
    });
    _onTemplateChanged();
  }

  void _moveRow(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final rows = List<ReceiptRow>.from(_template.rows);
      final row = rows.removeAt(oldIndex);
      rows.insert(newIndex, row);
      _template = _template.copyWith(rows: rows);
    });
    _onTemplateChanged();
  }

  void _addCellToRow(String rowId) {
    _updateRow(rowId, (row) {
      if (row.cells.length >= 4) return row;
      final newCell = ReceiptCell(
        id: generateReceiptId(),
        content: 'جديد',
        alignment: ReceiptCellAlignment.center,
      );
      return row.copyWith(cells: [...row.cells, newCell]);
    });
  }

  void _deleteCellFromRow(String rowId, String cellId) {
    _updateRow(rowId, (row) {
      return row.copyWith(
          cells: row.cells.where((c) => c.id != cellId).toList());
    });
    if (_selectedCellId == cellId) {
      setState(() => _selectedCellId = null);
    }
  }

  void _moveCellInRow(String rowId, int oldIndex, int newIndex) {
    _updateRow(rowId, (row) {
      if (oldIndex < 0 ||
          oldIndex >= row.cells.length ||
          newIndex < 0 ||
          newIndex >= row.cells.length) return row;
      final cells = List<ReceiptCell>.from(row.cells);
      final cell = cells.removeAt(oldIndex);
      cells.insert(newIndex, cell);
      return row.copyWith(cells: cells);
    });
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: _buildAppBar(),
        body: Row(
          children: [
            // يسار: قائمة الصفوف
            SizedBox(width: 260, child: _buildRowList()),
            const VerticalDivider(width: 1, color: SdColors.divider),
            // وسط: المعاينة
            Expanded(child: _buildPreview()),
            const VerticalDivider(width: 1, color: SdColors.divider),
            // يمين: لوحة الخصائص
            SizedBox(width: 290, child: _buildPropertiesPanel()),
          ],
        ),
      ),
    );
  }

  // ==================== AppBar ====================

  PreferredSizeWidget _buildAppBar() {
    return SdAppBar(
      title: 'محرر قالب الوصل',
      actions: [
        // تصفير عداد الوصل
        SdAppBarAction(
          icon: Icons.restart_alt,
          label: 'تصفير العداد',
          onPressed: _resetReceiptCounter,
          danger: true,
        ),
        // تغيير الشعار (ضغطة طويلة = استعادة الشعار الافتراضي)
        GestureDetector(
          onLongPress: _resetLogo,
          child: SdAppBarAction(
            icon: Icons.image,
            label: 'تغيير الشعار',
            onPressed: _pickCustomLogo,
          ),
        ),
        // معلومات الشركة
        SdAppBarAction(
          icon: Icons.business,
          label: 'معلومات الشركة',
          onPressed: _showCompanyInfoDialog,
        ),
        // إعدادات الصفحة
        SdAppBarAction(
          icon: Icons.settings,
          label: 'إعدادات الصفحة',
          onPressed: _showPageSettingsDialog,
        ),
        // استعادة
        SdAppBarAction(
          icon: Icons.restore,
          label: 'استعادة',
          onPressed: _resetTemplate,
        ),
        // حفظ
        SdAppBarAction(
          icon: Icons.save,
          label: 'حفظ',
          onPressed: _isSaving ? null : _saveTemplate,
        ),
      ],
    );
  }

  // ==================== Left Panel: Row List ====================

  Widget _buildRowList() {
    return Container(
      color: SdColors.surface,
      child: Column(
        children: [
          // عنوان + زر إضافة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: SdColors.surfaceAlt,
              border: Border(bottom: BorderSide(color: SdColors.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.list, color: SdColors.muted, size: 18),
                const SizedBox(width: 8),
                const Text('الصفوف', style: SdText.titleSm),
                const Spacer(),
                PopupMenuButton<ReceiptRowType>(
                  icon: const Icon(Icons.add_circle_outline,
                      color: SdColors.primary, size: 22),
                  tooltip: 'إضافة صف',
                  onSelected: _addRow,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: ReceiptRowType.cells, child: Text('صف خلايا')),
                    const PopupMenuItem(
                        value: ReceiptRowType.centeredText,
                        child: Text('نص وسطي')),
                    const PopupMenuItem(
                        value: ReceiptRowType.divider, child: Text('خط فاصل')),
                    const PopupMenuItem(
                        value: ReceiptRowType.spacer, child: Text('مسافة')),
                  ],
                ),
              ],
            ),
          ),
          // قائمة الصفوف
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _template.rows.length,
              onReorder: _moveRow,
              itemBuilder: (context, index) {
                final row = _template.rows[index];
                final isSelected = row.id == _selectedRowId;
                return _buildRowListTile(row, index, isSelected);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRowListTile(ReceiptRow row, int index, bool isSelected) {
    final icon = _getRowTypeIcon(row.type);
    final color = _getRowTypeColor(row.type);

    return Container(
      key: ValueKey(row.id),
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? color.withOpacity(0.12) : SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isSelected ? color : SdColors.divider,
            width: isSelected ? 1.5 : 1),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 4, right: 8),
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle, color: SdColors.faint, size: 18),
        ),
        title: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                row.displayLabel,
                style: const TextStyle(
                    fontFamily: SdText.family,
                    color: SdColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // إظهار/إخفاء
            InkWell(
              onTap: () =>
                  _updateRow(row.id, (r) => r.copyWith(visible: !r.visible)),
              child: Icon(
                row.visible ? Icons.visibility : Icons.visibility_off,
                size: 16,
                color: row.visible ? SdColors.success : SdColors.danger,
              ),
            ),
            const SizedBox(width: 6),
            // حذف
            InkWell(
              onTap: () => _deleteRow(row.id),
              child: const Icon(Icons.close, size: 16, color: SdColors.danger),
            ),
          ],
        ),
        onTap: () {
          setState(() {
            _selectedRowId = row.id;
            _selectedCellId = null;
          });
        },
      ),
    );
  }

  // ==================== Center: Preview ====================

  Widget _buildPreview() {
    return Container(
      color: SdColors.ground,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: SdColors.surfaceAlt,
              border: Border(bottom: BorderSide(color: SdColors.divider)),
            ),
            child: Row(
              children: [
                const Icon(Icons.preview, color: SdColors.muted, size: 18),
                const SizedBox(width: 8),
                const Text('المعاينة', style: SdText.titleSm),
                const Spacer(),
                if (_isLoadingPreview)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: SdColors.primary)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: SdColors.muted, size: 18),
                  tooltip: 'تحديث المعاينة',
                  onPressed: _regeneratePreview,
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                // ملاحظة: حاوية المعاينة تمثّل الوصل كما يُطبع (ورق أبيض بنص
                // أسود) — تُترك ألوانها كما هي عمداً ولا تُحوّل لنمط sd.
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black38,
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: _previewImage != null
                      ? Image.memory(_previewImage!, fit: BoxFit.contain)
                      : const SizedBox(
                          height: 400,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Right Panel: Properties ====================

  Widget _buildPropertiesPanel() {
    return Container(
      color: SdColors.surface,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: SdColors.surfaceAlt,
              border: Border(bottom: BorderSide(color: SdColors.divider)),
            ),
            child: const Row(
              children: [
                Icon(Icons.tune, color: SdColors.muted, size: 18),
                SizedBox(width: 8),
                Text('الخصائص', style: SdText.titleSm),
              ],
            ),
          ),
          Expanded(
            child: _selectedRowId == null
                ? const Center(
                    child: Text('اختر صفاً لتعديل خصائصه',
                        style: TextStyle(
                            fontFamily: SdText.family,
                            color: SdColors.faint,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                  )
                : _buildSelectedProperties(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedProperties() {
    final row = _template.rows.firstWhere((r) => r.id == _selectedRowId,
        orElse: () => _template.rows.first);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // نوع الصف
        _propLabel('نوع الصف'),
        _propChip(_getRowTypeName(row.type), _getRowTypeColor(row.type)),
        const SizedBox(height: 12),

        // شرط الإظهار
        _propLabel('شرط الإظهار'),
        _buildConditionDropdown(row),
        const SizedBox(height: 12),

        // خصائص حسب النوع
        if (row.type == ReceiptRowType.divider) ...[
          _propLabel('سمك الخط'),
          _buildSlider(row.dividerThickness ?? 1, 0.5, 5, (v) {
            _updateRow(row.id, (r) => r.copyWith(dividerThickness: () => v));
          }),
        ],

        if (row.type == ReceiptRowType.spacer) ...[
          _propLabel('ارتفاع المسافة'),
          _buildSlider(row.spacerHeight ?? 5, 1, 30, (v) {
            _updateRow(row.id, (r) => r.copyWith(spacerHeight: () => v));
          }),
        ],

        // الحدود (للصفوف التي تدعمها)
        if (row.type == ReceiptRowType.cells ||
            row.type == ReceiptRowType.centeredText) ...[
          _propLabel('الحدود'),
          _buildBorderToggle(row),
          if (row.decoration != null) ..._buildDecorationProps(row),
          const SizedBox(height: 16),

          // الخلايا
          _propLabel('الخلايا (${row.cells.length})'),
          const SizedBox(height: 4),
          ...row.cells
              .asMap()
              .entries
              .map((e) => _buildCellTile(row, e.value, e.key)),
          if (row.cells.length < 4 && row.type == ReceiptRowType.cells)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SdButton(
                label: 'إضافة خلية',
                icon: Icons.add,
                kind: SdButtonKind.secondary,
                height: 40,
                expand: true,
                onPressed: () => _addCellToRow(row.id),
              ),
            ),

          // خصائص الخلية المختارة
          if (_selectedCellId != null) ...[
            const SizedBox(height: 16),
            const Divider(color: SdColors.divider),
            const SizedBox(height: 8),
            _buildCellProperties(row),
          ],
        ],
      ],
    );
  }

  // ==================== Cell Tile ====================

  Widget _buildCellTile(ReceiptRow row, ReceiptCell cell, int index) {
    final isSelected = cell.id == _selectedCellId;
    final isFirst = index == 0;
    final isLast = index == row.cells.length - 1;
    final canMove = row.cells.length > 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: isSelected ? SdColors.primaryTint : SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isSelected ? SdColors.primary : SdColors.divider,
            width: 1),
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedCellId = cell.id),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              // أزرار التحريك
              if (canMove)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: isFirst
                          ? null
                          : () => _moveCellInRow(row.id, index, index - 1),
                      child: Icon(Icons.arrow_upward,
                          size: 14,
                          color: isFirst ? SdColors.faint : SdColors.warning),
                    ),
                    InkWell(
                      onTap: isLast
                          ? null
                          : () => _moveCellInRow(row.id, index, index + 1),
                      child: Icon(Icons.arrow_downward,
                          size: 14,
                          color: isLast ? SdColors.faint : SdColors.warning),
                    ),
                  ],
                ),
              if (canMove) const SizedBox(width: 6),
              // المحتوى
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cell.content.length > 25
                          ? '${cell.content.substring(0, 25)}...'
                          : cell.content,
                      style: const TextStyle(
                          fontFamily: SdText.family,
                          color: SdColors.ink,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'flex: ${cell.flex} | ${_alignmentName(cell.alignment)}',
                      style: const TextStyle(
                          fontFamily: SdText.family,
                          color: SdColors.muted,
                          fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              // زر الحذف
              if (row.cells.length > 1)
                InkWell(
                  onTap: () => _deleteCellFromRow(row.id, cell.id),
                  child: const Icon(Icons.remove_circle_outline,
                      size: 16, color: SdColors.danger),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== Cell Properties ====================

  Widget _buildCellProperties(ReceiptRow row) {
    final cell = row.cells.firstWhere((c) => c.id == _selectedCellId,
        orElse: () => row.cells.first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _propLabel('محتوى الخلية'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(text: cell.content),
                style: const TextStyle(
                    fontFamily: SdText.family,
                    color: SdColors.ink,
                    fontSize: 12.5),
                decoration: _inputDecoration('المحتوى'),
                onSubmitted: (v) {
                  _updateCell(row.id, cell.id, (c) => c.copyWith(content: v));
                },
              ),
            ),
            const SizedBox(width: 4),
            _buildVariableInsertButton(row.id, cell.id),
          ],
        ),
        const SizedBox(height: 10),

        // المحاذاة
        _propLabel('المحاذاة'),
        Row(
          children: [
            _alignBtn(row.id, cell, ReceiptCellAlignment.right,
                Icons.format_align_right, 'يمين'),
            const SizedBox(width: 4),
            _alignBtn(row.id, cell, ReceiptCellAlignment.center,
                Icons.format_align_center, 'وسط'),
            const SizedBox(width: 4),
            _alignBtn(row.id, cell, ReceiptCellAlignment.left,
                Icons.format_align_left, 'يسار'),
          ],
        ),
        const SizedBox(height: 10),

        // حجم الخط
        _propLabel(
            'حجم الخط (${cell.textStyle.fontSizeOffset >= 0 ? '+' : ''}${cell.textStyle.fontSizeOffset.toStringAsFixed(1)})'),
        _buildSlider(cell.textStyle.fontSizeOffset, -4, 8, (v) {
          _updateCell(
              row.id,
              cell.id,
              (c) => c.copyWith(
                    textStyle: c.textStyle.copyWith(fontSizeOffset: v),
                  ));
        }),

        // نسبة العرض
        _propLabel('نسبة العرض (flex: ${cell.flex})'),
        _buildSlider(cell.flex.toDouble(), 1, 8, (v) {
          _updateCell(row.id, cell.id, (c) => c.copyWith(flex: v.round()));
        }),

        // عريض / تسمية
        Row(
          children: [
            Expanded(
              child: CheckboxListTile(
                dense: true,
                activeColor: SdColors.primary,
                value: cell.textStyle.bold,
                onChanged: (v) {
                  _updateCell(
                      row.id,
                      cell.id,
                      (c) => c.copyWith(
                            textStyle: c.textStyle.copyWith(bold: v ?? false),
                          ));
                },
                title: const Text('عريض',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        color: SdColors.ink,
                        fontSize: 12)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                dense: true,
                activeColor: SdColors.primary,
                value: cell.isLabel,
                onChanged: (v) {
                  _updateCell(
                      row.id, cell.id, (c) => c.copyWith(isLabel: v ?? false));
                },
                title: const Text('تسمية',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        color: SdColors.ink,
                        fontSize: 12)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==================== Variable Insert ====================

  Widget _buildVariableInsertButton(String rowId, String cellId) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.data_object, color: SdColors.warning, size: 20),
      tooltip: 'إدراج متغير',
      onSelected: (variable) {
        _updateCell(rowId, cellId, (c) => c.copyWith(content: '{{$variable}}'));
      },
      itemBuilder: (_) {
        final items = <PopupMenuEntry<String>>[];
        for (final category in TemplateVariableRegistry.categories) {
          items.add(PopupMenuItem(
            enabled: false,
            child: Text(
              TemplateVariableRegistry.categoryDisplayName(category),
              style: const TextStyle(
                  fontFamily: SdText.family,
                  color: SdColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
          ));
          for (final v in TemplateVariableRegistry.allVariables
              .where((v) => v.category == category)) {
            items.add(PopupMenuItem(
              value: v.key,
              child: Text('${v.displayName}  {{${v.key}}}',
                  style: const TextStyle(fontSize: 12)),
            ));
          }
          items.add(const PopupMenuDivider());
        }
        return items;
      },
    );
  }

  // ==================== Border / Decoration ====================

  Widget _buildBorderToggle(ReceiptRow row) {
    final hasBorder = row.decoration != null;
    return SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      activeColor: SdColors.primary,
      value: hasBorder,
      onChanged: (v) {
        _updateRow(
            row.id,
            (r) => r.copyWith(
                  decoration: () => v ? const ReceiptBoxDecoration() : null,
                ));
      },
      title: Text(hasBorder ? 'مفعّلة' : 'بدون حدود',
          style: const TextStyle(
              fontFamily: SdText.family, color: SdColors.muted, fontSize: 12)),
    );
  }

  List<Widget> _buildDecorationProps(ReceiptRow row) {
    final d = row.decoration!;
    return [
      _propLabel('سمك الحدود (${d.borderWidth.toStringAsFixed(1)})'),
      _buildSlider(d.borderWidth, 0, 3, (v) {
        _updateRow(row.id,
            (r) => r.copyWith(decoration: () => d.copyWith(borderWidth: v)));
      }),
      _propLabel('الزوايا (${d.borderRadius.toStringAsFixed(0)})'),
      _buildSlider(d.borderRadius, 0, 12, (v) {
        _updateRow(row.id,
            (r) => r.copyWith(decoration: () => d.copyWith(borderRadius: v)));
      }),
      _propLabel('الحشو الأفقي (${d.paddingH.toStringAsFixed(0)})'),
      _buildSlider(d.paddingH, 0, 16, (v) {
        _updateRow(row.id,
            (r) => r.copyWith(decoration: () => d.copyWith(paddingH: v)));
      }),
      _propLabel('الحشو العمودي (${d.paddingV.toStringAsFixed(0)})'),
      _buildSlider(d.paddingV, 0, 16, (v) {
        _updateRow(row.id,
            (r) => r.copyWith(decoration: () => d.copyWith(paddingV: v)));
      }),
      _propLabel('الهامش السفلي (${d.marginBottom.toStringAsFixed(0)})'),
      _buildSlider(d.marginBottom, 0, 16, (v) {
        _updateRow(row.id,
            (r) => r.copyWith(decoration: () => d.copyWith(marginBottom: v)));
      }),
    ];
  }

  // ==================== Condition Dropdown ====================

  Widget _buildConditionDropdown(ReceiptRow row) {
    return DropdownButtonFormField<String?>(
      value: row.conditionVariable,
      dropdownColor: SdColors.surface,
      style: const TextStyle(
          fontFamily: SdText.family, color: SdColors.ink, fontSize: 12.5),
      decoration: _inputDecoration(''),
      items: const [
        DropdownMenuItem(
            value: null,
            child: Text('بدون شرط (دائماً)', style: TextStyle(fontSize: 12))),
        DropdownMenuItem(
            value: 'showCustomerInfo',
            child: Text('معلومات العميل', style: TextStyle(fontSize: 12))),
        DropdownMenuItem(
            value: 'showServiceDetails',
            child: Text('تفاصيل الخدمة', style: TextStyle(fontSize: 12))),
        DropdownMenuItem(
            value: 'showPaymentDetails',
            child: Text('تفاصيل الدفع', style: TextStyle(fontSize: 12))),
        DropdownMenuItem(
            value: 'showAdditionalInfo',
            child: Text('معلومات إضافية', style: TextStyle(fontSize: 12))),
        DropdownMenuItem(
            value: 'showContactInfo',
            child: Text('معلومات الاتصال', style: TextStyle(fontSize: 12))),
        DropdownMenuItem(
            value: 'hasNotes',
            child: Text('الملاحظات', style: TextStyle(fontSize: 12))),
      ],
      onChanged: (v) {
        _updateRow(row.id, (r) => r.copyWith(conditionVariable: () => v));
      },
    );
  }

  // ==================== Company Info Dialog ====================

  void _showCompanyInfoDialog() async {
    final oldTemplate = await PrintTemplateStorage.loadTemplate();
    var companyName = oldTemplate.companyName;
    var companySubtitle = oldTemplate.companySubtitle;
    var contactInfo = oldTemplate.contactInfo;
    var footerMessage = oldTemplate.footerMessage;

    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: SdColors.surface,
          title: const Row(
            children: [
              Icon(Icons.business, color: SdColors.accent, size: 22),
              SizedBox(width: 8),
              Text('معلومات الشركة', style: SdText.titleSm),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: TextEditingController(text: companyName),
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      color: SdColors.ink,
                      fontSize: 13),
                  decoration: _companyInputDecoration('اسم الشركة'),
                  onChanged: (v) => companyName = v,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: TextEditingController(text: companySubtitle),
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      color: SdColors.ink,
                      fontSize: 13),
                  decoration: _companyInputDecoration('السطر الفرعي'),
                  onChanged: (v) => companySubtitle = v,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: TextEditingController(text: contactInfo),
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      color: SdColors.ink,
                      fontSize: 13),
                  decoration: _companyInputDecoration('معلومات الاتصال'),
                  onChanged: (v) => contactInfo = v,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: TextEditingController(text: footerMessage),
                  style: const TextStyle(
                      fontFamily: SdText.family,
                      color: SdColors.ink,
                      fontSize: 13),
                  decoration: _companyInputDecoration('رسالة التذييل'),
                  maxLines: 2,
                  onChanged: (v) => footerMessage = v,
                ),
              ],
            ),
          ),
          actions: [
            SdButton(
              label: 'إلغاء',
              kind: SdButtonKind.secondary,
              height: 44,
              onPressed: () => Navigator.pop(ctx, false),
            ),
            SdButton(
              label: 'حفظ',
              height: 44,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      final newTemplate = PrintTemplate(
        companyName: companyName,
        companySubtitle: companySubtitle,
        footerMessage: footerMessage,
        contactInfo: contactInfo,
        showCustomerInfo: oldTemplate.showCustomerInfo,
        showServiceDetails: oldTemplate.showServiceDetails,
        showPaymentDetails: oldTemplate.showPaymentDetails,
        showAdditionalInfo: oldTemplate.showAdditionalInfo,
        showContactInfo: oldTemplate.showContactInfo,
        fontSize: oldTemplate.fontSize,
        boldHeaders: oldTemplate.boldHeaders,
      );
      await PrintTemplateStorage.saveTemplate(newTemplate);

      // تحديث قيم المعاينة بالقيم الجديدة
      _companyValues = {
        'companyName': companyName,
        'companySubtitle': companySubtitle,
        'contactInfo': contactInfo,
        'footerMessage': footerMessage,
      };
      _regeneratePreview();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ معلومات الشركة'),
            backgroundColor: SdColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  InputDecoration _companyInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
          fontFamily: SdText.family, color: SdColors.muted, fontSize: 12),
      filled: true,
      fillColor: SdColors.surfaceAlt,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SdColors.divider)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SdColors.divider)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: SdColors.accent, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    );
  }

  // ==================== Page Settings Dialog ====================

  void _showPageSettingsDialog() {
    var ps = _template.pageSettings;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: SdColors.surface,
          title: const Text('إعدادات الصفحة', style: SdText.titleSm),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // حجم الخط الأساسي
              Row(
                children: [
                  const Text('حجم الخط الأساسي:',
                      style: TextStyle(
                          fontFamily: SdText.family,
                          color: SdColors.muted,
                          fontSize: 13)),
                  const Spacer(),
                  Text(ps.baseFontSize.toStringAsFixed(1),
                      style: const TextStyle(
                          fontFamily: SdText.family,
                          color: SdColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              Slider(
                value: ps.baseFontSize,
                min: 6,
                max: 18,
                divisions: 24,
                activeColor: SdColors.primary,
                onChanged: (v) =>
                    setDialogState(() => ps = ps.copyWith(baseFontSize: v)),
              ),
              // عرض الورق
              Row(
                children: [
                  const Text('عرض الورق (mm):',
                      style: TextStyle(
                          fontFamily: SdText.family,
                          color: SdColors.muted,
                          fontSize: 13)),
                  const Spacer(),
                  Text(ps.paperWidthMm.toStringAsFixed(0),
                      style: const TextStyle(
                          fontFamily: SdText.family,
                          color: SdColors.ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              Slider(
                value: ps.paperWidthMm,
                min: 48,
                max: 80,
                divisions: 32,
                activeColor: SdColors.primary,
                onChanged: (v) =>
                    setDialogState(() => ps = ps.copyWith(paperWidthMm: v)),
              ),
              // عناوين عريضة
              CheckboxListTile(
                value: ps.boldHeaders,
                activeColor: SdColors.primary,
                onChanged: (v) => setDialogState(
                    () => ps = ps.copyWith(boldHeaders: v ?? true)),
                title: const Text('عناوين عريضة',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        color: SdColors.ink,
                        fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            SdButton(
              label: 'إلغاء',
              kind: SdButtonKind.secondary,
              height: 44,
              onPressed: () => Navigator.pop(ctx),
            ),
            SdButton(
              label: 'تطبيق',
              height: 44,
              onPressed: () {
                setState(
                    () => _template = _template.copyWith(pageSettings: ps));
                _onTemplateChanged();
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Helper Widgets ====================

  Widget _propLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 2),
      child: Text(label,
          style: const TextStyle(
              fontFamily: SdText.family,
              color: SdColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w700)),
    );
  }

  Widget _propChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text,
          style: TextStyle(
              fontFamily: SdText.family,
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800)),
    );
  }

  Widget _buildSlider(
      double value, double min, double max, ValueChanged<double> onChanged) {
    return SliderTheme(
      data: const SliderThemeData(
        trackHeight: 3,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: SdColors.primary,
        inactiveTrackColor: SdColors.divider,
        thumbColor: SdColors.primary,
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    );
  }

  Widget _alignBtn(String rowId, ReceiptCell cell, ReceiptCellAlignment align,
      IconData icon, String tooltip) {
    final isActive = cell.alignment == align;
    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () =>
              _updateCell(rowId, cell.id, (c) => c.copyWith(alignment: align)),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? SdColors.primaryTint : SdColors.surfaceAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: isActive ? SdColors.primary : SdColors.divider),
            ),
            child: Icon(icon,
                size: 16,
                color: isActive ? SdColors.primary : SdColors.faint),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
          fontFamily: SdText.family, color: SdColors.faint, fontSize: 12),
      filled: true,
      fillColor: SdColors.surfaceAlt,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: SdColors.divider)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: SdColors.divider)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: SdColors.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      isDense: true,
    );
  }

  // ==================== Helpers ====================

  IconData _getRowTypeIcon(ReceiptRowType type) {
    switch (type) {
      case ReceiptRowType.cells:
        return Icons.table_rows;
      case ReceiptRowType.centeredText:
        return Icons.text_fields;
      case ReceiptRowType.divider:
        return Icons.horizontal_rule;
      case ReceiptRowType.spacer:
        return Icons.space_bar;
      case ReceiptRowType.image:
        return Icons.image;
    }
  }

  Color _getRowTypeColor(ReceiptRowType type) {
    switch (type) {
      case ReceiptRowType.cells:
        return SdColors.info;
      case ReceiptRowType.centeredText:
        return SdColors.warning;
      case ReceiptRowType.divider:
        return SdColors.muted;
      case ReceiptRowType.spacer:
        return SdColors.accent;
      case ReceiptRowType.image:
        return SdColors.platformBase;
    }
  }

  String _getRowTypeName(ReceiptRowType type) {
    switch (type) {
      case ReceiptRowType.cells:
        return 'صف خلايا';
      case ReceiptRowType.centeredText:
        return 'نص وسطي';
      case ReceiptRowType.divider:
        return 'خط فاصل';
      case ReceiptRowType.spacer:
        return 'مسافة';
      case ReceiptRowType.image:
        return 'شعار';
    }
  }

  String _alignmentName(ReceiptCellAlignment a) {
    switch (a) {
      case ReceiptCellAlignment.right:
        return 'يمين';
      case ReceiptCellAlignment.center:
        return 'وسط';
      case ReceiptCellAlignment.left:
        return 'يسار';
    }
  }
}
