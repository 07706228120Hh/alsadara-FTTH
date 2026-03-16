import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/receipt_template_models.dart';
import 'thermal_printer_service.dart';

/// يبني PDF من ReceiptTemplate + بيانات المتغيرات
class ReceiptPdfBuilder {
  final ReceiptTemplate template;
  final Map<String, String> variableValues;
  final Map<String, bool> conditions;

  ReceiptPdfBuilder({
    required this.template,
    required this.variableValues,
    this.conditions = const {},
  });

  /// بناء مستند PDF
  Future<pw.Document> build() async {
    await ThermalPrinterService.ensureFontsLoaded();

    final pdf = pw.Document();
    final ps = template.pageSettings;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          ps.paperWidthMm * PdfPageFormat.mm,
          200 * PdfPageFormat.mm,
        ),
        margin: pw.EdgeInsets.all(ps.marginMm),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: template.rows
                .where(_isRowVisible)
                .map(_buildRow)
                .toList(),
          );
        },
      ),
    );

    return pdf;
  }

  /// بناء PDF وإرجاع bytes
  Future<Uint8List> buildBytes() async {
    final doc = await build();
    return doc.save();
  }

  // ==================== Visibility ====================

  bool _isRowVisible(ReceiptRow row) {
    if (!row.visible) return false;
    if (row.conditionVariable != null) {
      return conditions[row.conditionVariable] ?? true;
    }
    return true;
  }

  // ==================== Row Building ====================

  pw.Widget _buildRow(ReceiptRow row) {
    switch (row.type) {
      case ReceiptRowType.divider:
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Divider(
            thickness: row.dividerThickness ?? 1,
            color: PdfColors.black,
          ),
        );

      case ReceiptRowType.spacer:
        return pw.SizedBox(height: row.spacerHeight ?? 5);

      case ReceiptRowType.centeredText:
        return _buildCenteredTextRow(row);

      case ReceiptRowType.cells:
        return _buildCellsRow(row);
    }
  }

  // ==================== Centered Text ====================

  pw.Widget _buildCenteredTextRow(ReceiptRow row) {
    if (row.cells.isEmpty) return pw.SizedBox.shrink();

    final cell = row.cells.first;
    final resolvedText = _resolveContent(cell.content);
    if (resolvedText.trim().isEmpty) return pw.SizedBox.shrink();

    final fontSize = template.pageSettings.baseFontSize + cell.textStyle.fontSizeOffset;
    final isBold = cell.textStyle.bold ||
        (cell.isLabel && template.pageSettings.boldHeaders);

    final textWidget = ThermalPrinterService.buildMixedText(
      resolvedText,
      fontSize: fontSize.clamp(6, 30).toDouble(),
      fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      textAlign: _pdfTextAlign(cell.alignment),
    );

    if (row.decoration != null) {
      return _wrapWithDecoration(textWidget, row.decoration!);
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: textWidget,
    );
  }

  // ==================== Cells Row ====================

  pw.Widget _buildCellsRow(ReceiptRow row) {
    if (row.cells.isEmpty) return pw.SizedBox.shrink();

    final ps = template.pageSettings;

    // صف 4 خلايا: نُقسّمه لنصفين (يمين + فاصل + يسار) — مثل الوصل الأصلي
    if (row.cells.length == 4) {
      return _buildFourCellRow(row, ps);
    }

    // صفوف أخرى (1-3 خلايا): التسميات تأخذ حجم نصها فقط، القيم تملأ الباقي
    final children = <pw.Widget>[];
    for (int i = 0; i < row.cells.length; i++) {
      final cell = row.cells[i];
      final cellWidget = _buildCellText(cell, ps);

      if (cell.isLabel) {
        // التسمية: تأخذ فقط حجم نصها
        children.add(cellWidget);
        children.add(pw.SizedBox(width: 3));
      } else {
        // القيمة: تملأ المساحة المتبقية
        children.add(pw.Expanded(flex: cell.flex, child: cellWidget));
      }
    }

    final rowWidget = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: children,
      ),
    );

    if (row.decoration != null) {
      return _wrapWithDecoration(rowWidget, row.decoration!);
    }
    return pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1), child: rowWidget);
  }

  /// بناء صف 4 خلايا: [label1 value1 | label2 value2] — RTL
  /// التسمية تأخذ فقط حجم نصها، والقيمة تملأ الباقي
  pw.Widget _buildFourCellRow(ReceiptRow row, ReceiptPageSettings ps) {
    // بناء نصف (تسمية + قيمة): التسمية بدون Expanded، القيمة Expanded
    pw.Widget buildHalf(ReceiptCell label, ReceiptCell value) {
      return pw.Expanded(
        child: pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Row(
            children: [
              // التسمية: تأخذ فقط حجم نصها
              _buildCellText(label, ps),
              pw.SizedBox(width: 3),
              // القيمة: تملأ المساحة المتبقية
              pw.Expanded(child: _buildCellText(value, ps)),
            ],
          ),
        ),
      );
    }

    final rightHalf = buildHalf(row.cells[0], row.cells[1]);

    final divider = pw.Container(
      width: 1,
      height: 22,
      color: PdfColors.grey400,
      margin: const pw.EdgeInsets.symmetric(horizontal: 4),
    );

    final leftHalf = buildHalf(row.cells[2], row.cells[3]);

    final rowWidget = pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [rightHalf, divider, leftHalf],
      ),
    );

    if (row.decoration != null) {
      return _wrapWithDecoration(rowWidget, row.decoration!);
    }
    return pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 1), child: rowWidget);
  }

  /// بناء نص خلية واحدة
  pw.Widget _buildCellText(ReceiptCell cell, ReceiptPageSettings ps) {
    final resolvedText = _resolveContent(cell.content);
    final fontSize = ps.baseFontSize + cell.textStyle.fontSizeOffset;
    final isBold = cell.textStyle.bold || (cell.isLabel && ps.boldHeaders);

    return ThermalPrinterService.buildMixedText(
      resolvedText,
      fontSize: fontSize.clamp(6, 30).toDouble(),
      fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      textAlign: _pdfTextAlign(cell.alignment),
    );
  }

  // ==================== Decoration ====================

  pw.Widget _wrapWithDecoration(pw.Widget child, ReceiptBoxDecoration deco) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: deco.marginBottom),
      child: pw.Container(
        padding: pw.EdgeInsets.symmetric(
          horizontal: deco.paddingH,
          vertical: deco.paddingV,
        ),
        decoration: deco.borderWidth > 0
            ? pw.BoxDecoration(
                border: pw.Border.all(
                  width: deco.borderWidth,
                  color: PdfColors.black,
                ),
                borderRadius: pw.BorderRadius.circular(deco.borderRadius),
              )
            : null,
        child: child,
      ),
    );
  }

  // ==================== Helpers ====================

  /// استبدال {{variable}} بالقيم الفعلية
  String _resolveContent(String content) {
    return content.replaceAllMapped(
      RegExp(r'\{\{(\w+)\}\}'),
      (match) => variableValues[match.group(1)!] ?? match.group(0)!,
    );
  }

  /// تحويل محاذاة الخلية إلى محاذاة PDF
  pw.TextAlign _pdfTextAlign(ReceiptCellAlignment alignment) {
    switch (alignment) {
      case ReceiptCellAlignment.right:
        return pw.TextAlign.right;
      case ReceiptCellAlignment.center:
        return pw.TextAlign.center;
      case ReceiptCellAlignment.left:
        return pw.TextAlign.left;
    }
  }
}
