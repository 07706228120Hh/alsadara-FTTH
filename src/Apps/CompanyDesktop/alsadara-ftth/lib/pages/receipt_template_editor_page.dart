import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/receipt_template_models.dart';
import '../services/receipt_template_storage.dart';
import '../services/receipt_pdf_builder.dart';

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
    setState(() => _template = template);
    _regeneratePreview();
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
      final builder = ReceiptPdfBuilder(
        template: _template,
        variableValues: TemplateVariableRegistry.sampleValues,
        conditions: {
          'showCustomerInfo': true,
          'showServiceDetails': true,
          'showPaymentDetails': true,
          'showAdditionalInfo': false,
          'showContactInfo': true,
          'hasNotes': true,
        },
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
            backgroundColor: Colors.green,
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
        title: const Text('استعادة القالب الافتراضي'),
        content: const Text(
            'سيتم حذف جميع التعديلات والعودة للقالب الأصلي. هل أنت متأكد؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('استعادة', style: TextStyle(color: Colors.white)),
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
        backgroundColor: const Color(0xFF1a1a2e),
        appBar: _buildAppBar(),
        body: Row(
          children: [
            // يسار: قائمة الصفوف
            SizedBox(width: 260, child: _buildRowList()),
            const VerticalDivider(width: 1, color: Colors.white24),
            // وسط: المعاينة
            Expanded(child: _buildPreview()),
            const VerticalDivider(width: 1, color: Colors.white24),
            // يمين: لوحة الخصائص
            SizedBox(width: 290, child: _buildPropertiesPanel()),
          ],
        ),
      ),
    );
  }

  // ==================== AppBar ====================

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF16213e),
      title: const Text('محرر قالب الوصل',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        // إعدادات الصفحة
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
          tooltip: 'إعدادات الصفحة',
          onPressed: _showPageSettingsDialog,
        ),
        const SizedBox(width: 8),
        // استعادة
        TextButton.icon(
          onPressed: _resetTemplate,
          icon: const Icon(Icons.restore, color: Colors.orange, size: 18),
          label: const Text('استعادة',
              style: TextStyle(color: Colors.orange, fontSize: 13)),
        ),
        const SizedBox(width: 8),
        // حفظ
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveTemplate,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 18),
          label: const Text('حفظ'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  // ==================== Left Panel: Row List ====================

  Widget _buildRowList() {
    return Container(
      color: const Color(0xFF1a1a2e),
      child: Column(
        children: [
          // عنوان + زر إضافة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF16213e),
            child: Row(
              children: [
                const Icon(Icons.list, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                const Text('الصفوف',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                PopupMenuButton<ReceiptRowType>(
                  icon: const Icon(Icons.add_circle_outline,
                      color: Colors.blue, size: 22),
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
        color: isSelected
            ? color.withOpacity(0.2)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: color, width: 1.5) : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 4, right: 8),
        leading: ReorderableDragStartListener(
          index: index,
          child: Icon(Icons.drag_handle, color: Colors.white38, size: 18),
        ),
        title: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                row.displayLabel,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.9), fontSize: 12),
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
                color:
                    row.visible ? Colors.green.shade300 : Colors.red.shade300,
              ),
            ),
            const SizedBox(width: 6),
            // حذف
            InkWell(
              onTap: () => _deleteRow(row.id),
              child: Icon(Icons.close, size: 16, color: Colors.red.shade300),
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
      color: const Color(0xFF2a2a3e),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF16213e),
            child: Row(
              children: [
                const Icon(Icons.preview, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                const Text('المعاينة',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                if (_isLoadingPreview)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.blue)),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh,
                      color: Colors.white54, size: 18),
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
      color: const Color(0xFF1a1a2e),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF16213e),
            child: const Row(
              children: [
                Icon(Icons.tune, color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Text('الخصائص',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _selectedRowId == null
                ? const Center(
                    child: Text('اختر صفاً لتعديل خصائصه',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
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
              child: OutlinedButton.icon(
                onPressed: () => _addCellToRow(row.id),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('إضافة خلية', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade300,
                  side: BorderSide(color: Colors.blue.shade700),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
            ),

          // خصائص الخلية المختارة
          if (_selectedCellId != null) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
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
        color: isSelected
            ? Colors.blue.withOpacity(0.15)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
        border: isSelected
            ? Border.all(color: Colors.blue.shade400, width: 1)
            : null,
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
                          color:
                              isFirst ? Colors.white12 : Colors.amber.shade300),
                    ),
                    InkWell(
                      onTap: isLast
                          ? null
                          : () => _moveCellInRow(row.id, index, index + 1),
                      child: Icon(Icons.arrow_downward,
                          size: 14,
                          color:
                              isLast ? Colors.white12 : Colors.amber.shade300),
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
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.85), fontSize: 11),
                    ),
                    Text(
                      'flex: ${cell.flex} | ${_alignmentName(cell.alignment)}',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
              // زر الحذف
              if (row.cells.length > 1)
                InkWell(
                  onTap: () => _deleteCellFromRow(row.id, cell.id),
                  child: Icon(Icons.remove_circle_outline,
                      size: 16, color: Colors.red.shade300),
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
                style: const TextStyle(color: Colors.white, fontSize: 12),
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
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            Expanded(
              child: CheckboxListTile(
                dense: true,
                value: cell.isLabel,
                onChanged: (v) {
                  _updateCell(
                      row.id, cell.id, (c) => c.copyWith(isLabel: v ?? false));
                },
                title: const Text('تسمية',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
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
      icon: Icon(Icons.data_object, color: Colors.amber.shade400, size: 20),
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
              style: TextStyle(
                  color: Colors.blue.shade700,
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
      value: hasBorder,
      onChanged: (v) {
        _updateRow(
            row.id,
            (r) => r.copyWith(
                  decoration: () => v ? const ReceiptBoxDecoration() : null,
                ));
      },
      title: Text(hasBorder ? 'مفعّلة' : 'بدون حدود',
          style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
      dropdownColor: const Color(0xFF2a2a3e),
      style: const TextStyle(color: Colors.white, fontSize: 12),
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

  // ==================== Page Settings Dialog ====================

  void _showPageSettingsDialog() {
    var ps = _template.pageSettings;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1e1e2e),
          title: const Text('إعدادات الصفحة',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // حجم الخط الأساسي
              Row(
                children: [
                  const Text('حجم الخط الأساسي:',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  Text(ps.baseFontSize.toStringAsFixed(1),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              Slider(
                value: ps.baseFontSize,
                min: 6,
                max: 18,
                divisions: 24,
                onChanged: (v) =>
                    setDialogState(() => ps = ps.copyWith(baseFontSize: v)),
              ),
              // عرض الورق
              Row(
                children: [
                  const Text('عرض الورق (mm):',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  Text(ps.paperWidthMm.toStringAsFixed(0),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              Slider(
                value: ps.paperWidthMm,
                min: 48,
                max: 80,
                divisions: 32,
                onChanged: (v) =>
                    setDialogState(() => ps = ps.copyWith(paperWidthMm: v)),
              ),
              // عناوين عريضة
              CheckboxListTile(
                value: ps.boldHeaders,
                onChanged: (v) => setDialogState(
                    () => ps = ps.copyWith(boldHeaders: v ?? true)),
                title: const Text('عناوين عريضة',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(
                    () => _template = _template.copyWith(pageSettings: ps));
                _onTemplateChanged();
                Navigator.pop(ctx);
              },
              child: const Text('تطبيق'),
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
          style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600)),
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
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Widget _buildSlider(
      double value, double min, double max, ValueChanged<double> onChanged) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: Colors.blue.shade400,
        inactiveTrackColor: Colors.white12,
        thumbColor: Colors.blue.shade300,
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
              color:
                  isActive ? Colors.blue.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: isActive ? Colors.blue : Colors.white24),
            ),
            child: Icon(icon,
                size: 16,
                color: isActive ? Colors.blue.shade300 : Colors.white38),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.white24)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.white24)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Colors.blue.shade400)),
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
    }
  }

  Color _getRowTypeColor(ReceiptRowType type) {
    switch (type) {
      case ReceiptRowType.cells:
        return Colors.blue.shade300;
      case ReceiptRowType.centeredText:
        return Colors.amber.shade300;
      case ReceiptRowType.divider:
        return Colors.grey.shade400;
      case ReceiptRowType.spacer:
        return Colors.teal.shade300;
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
