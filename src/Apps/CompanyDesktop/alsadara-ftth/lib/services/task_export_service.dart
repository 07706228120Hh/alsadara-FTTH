import 'dart:io';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/task.dart';

/// خدمة تصدير تقارير المهام إلى Excel و PDF
class TaskExportService {
  static final _currencyFmt = NumberFormat('#,##0', 'ar');
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');

  // ─── ألوان Excel ───
  static final _headerBg = ExcelColor.fromHexString('FF1A237E');
  static final _headerFont = ExcelColor.white;
  static final _totalBg = ExcelColor.fromHexString('FFE8E8E8');
  static final _greenBg = ExcelColor.fromHexString('FFE8F8F0');
  static final _redBg = ExcelColor.fromHexString('FFFDE8E8');
  static final _orangeBg = ExcelColor.fromHexString('FFFFF3E0');

  static CellStyle get _headerStyle => CellStyle(
        backgroundColorHex: _headerBg,
        fontColorHex: _headerFont,
        bold: true,
        horizontalAlign: HorizontalAlign.Center,
      );

  static CellStyle get _totalStyle => CellStyle(
        backgroundColorHex: _totalBg,
        bold: true,
      );

  // ═══════════════════════════════════════════════════════
  // تصدير Excel
  // ═══════════════════════════════════════════════════════

  /// تصدير المهام إلى ملف Excel
  static Future<String> exportToExcel({
    required List<Task> tasks,
    String? department,
    String? technician,
    String? dateRange,
  }) async {
    final excel = Excel.createExcel();

    // ─── ورقة المهام ───
    final sheet = excel['المهام'];
    excel.delete('Sheet1');

    // العناوين
    final headers = [
      '#', 'العنوان', 'الحالة', 'القسم', 'الفني', 'الليدر',
      'العميل', 'الهاتف', 'FBG', 'FAT', 'الموقع',
      'الأولوية', 'المبلغ', 'تاريخ الإنشاء', 'تاريخ الإغلاق',
      'المدة', 'الملاحظات',
    ];
    _addRow(sheet, 0, headers, style: _headerStyle);

    // تعيين عرض الأعمدة
    sheet.setColumnWidth(0, 6);   // #
    sheet.setColumnWidth(1, 25);  // العنوان
    sheet.setColumnWidth(2, 12);  // الحالة
    sheet.setColumnWidth(3, 12);  // القسم
    sheet.setColumnWidth(4, 14);  // الفني
    sheet.setColumnWidth(5, 14);  // الليدر
    sheet.setColumnWidth(6, 18);  // العميل
    sheet.setColumnWidth(7, 15);  // الهاتف
    sheet.setColumnWidth(12, 12); // المبلغ
    sheet.setColumnWidth(13, 16); // تاريخ الإنشاء
    sheet.setColumnWidth(14, 16); // تاريخ الإغلاق

    // البيانات
    for (int i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      final duration = t.closedAt != null
          ? '${t.closedAt!.difference(t.createdAt).inHours}h ${t.closedAt!.difference(t.createdAt).inMinutes.remainder(60)}m'
          : '-';

      final rowStyle = _getStatusCellStyle(t.status);

      _addRow(sheet, i + 1, [
        '${i + 1}',
        t.title,
        t.status,
        t.department,
        t.technician,
        t.leader,
        t.username,
        t.phone,
        t.fbg,
        t.fat,
        t.location,
        t.priority,
        t.amount.isNotEmpty ? t.amount : '0',
        _dateTimeFmt.format(t.createdAt),
        t.closedAt != null ? _dateTimeFmt.format(t.closedAt!) : '-',
        duration,
        t.notes,
      ], style: rowStyle);
    }

    // صف الإجمالي
    final totalAmount = tasks.fold<double>(0, (sum, t) {
      return sum + (double.tryParse(t.amount.replaceAll('\$', '').replaceAll(',', '')) ?? 0);
    });
    final totalRow = tasks.length + 1;
    _addRow(sheet, totalRow, [
      '', 'الإجمالي: ${tasks.length} مهمة', '', '', '', '', '', '', '', '', '',
      '', _currencyFmt.format(totalAmount.round()), '', '', '', '',
    ], style: _totalStyle);

    // ─── ورقة الإحصائيات ───
    _addStatsSheet(excel, tasks);

    // ─── ورقة أداء الفنيين ───
    _addTechnicianSheet(excel, tasks);

    // حفظ وفتح
    return await _saveAndOpen(excel, 'تقرير_المهام');
  }

  /// إضافة ورقة إحصائيات
  static void _addStatsSheet(Excel excel, List<Task> tasks) {
    final sheet = excel['إحصائيات'];
    _addRow(sheet, 0, ['الإحصائية', 'القيمة'], style: _headerStyle);
    sheet.setColumnWidth(0, 25);
    sheet.setColumnWidth(1, 15);

    final open = tasks.where((t) => t.status == 'مفتوحة').length;
    final progress = tasks.where((t) => t.status == 'قيد التنفيذ').length;
    final done = tasks.where((t) => t.status == 'مكتملة').length;
    final cancelled = tasks.where((t) => t.status == 'ملغية').length;

    final stats = [
      ['إجمالي المهام', '${tasks.length}'],
      ['مفتوحة', '$open'],
      ['قيد التنفيذ', '$progress'],
      ['مكتملة', '$done'],
      ['ملغية', '$cancelled'],
      ['نسبة الإنجاز', '${tasks.isEmpty ? 0 : (done * 100 / tasks.length).toStringAsFixed(1)}%'],
    ];
    for (int i = 0; i < stats.length; i++) {
      _addRow(sheet, i + 1, stats[i]);
    }
  }

  /// إضافة ورقة أداء الفنيين
  static void _addTechnicianSheet(Excel excel, List<Task> tasks) {
    final sheet = excel['أداء الفنيين'];
    _addRow(sheet, 0, [
      'الفني', 'القسم', 'الإجمالي', 'مفتوحة', 'تنفيذ', 'مكتملة', 'ملغية',
      'نسبة الإنجاز', 'متوسط المدة',
    ], style: _headerStyle);

    sheet.setColumnWidth(0, 18);
    sheet.setColumnWidth(1, 14);

    final techMap = <String, Map<String, dynamic>>{};
    for (final t in tasks) {
      if (t.technician.trim().isEmpty) continue;
      techMap.putIfAbsent(t.technician, () => {
        'dept': t.department, 'total': 0, 'open': 0,
        'progress': 0, 'done': 0, 'cancelled': 0, 'totalHours': 0.0,
      });
      techMap[t.technician]!['total']++;
      if (t.status == 'مفتوحة') techMap[t.technician]!['open']++;
      if (t.status == 'قيد التنفيذ') techMap[t.technician]!['progress']++;
      if (t.status == 'مكتملة') {
        techMap[t.technician]!['done']++;
        if (t.closedAt != null) {
          techMap[t.technician]!['totalHours'] += t.closedAt!.difference(t.createdAt).inMinutes / 60.0;
        }
      }
      if (t.status == 'ملغية') techMap[t.technician]!['cancelled']++;
    }

    final sorted = techMap.entries.toList()
      ..sort((a, b) => (b.value['total'] as int).compareTo(a.value['total'] as int));

    for (int i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      final s = e.value;
      final total = s['total'] as int;
      final done = s['done'] as int;
      final avgHours = done > 0 ? (s['totalHours'] as double) / done : 0.0;

      _addRow(sheet, i + 1, [
        e.key,
        s['dept'].toString(),
        '$total',
        '${s['open']}',
        '${s['progress']}',
        '$done',
        '${s['cancelled']}',
        total > 0 ? '${(done * 100 / total).toStringAsFixed(0)}%' : '0%',
        done > 0 ? '${avgHours.toStringAsFixed(1)} ساعة' : '-',
      ]);
    }
  }

  // ═══════════════════════════════════════════════════════
  // تصدير PDF
  // ═══════════════════════════════════════════════════════

  /// تصدير المهام إلى PDF
  static Future<String> exportToPdf({
    required List<Task> tasks,
    String? title,
  }) async {
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBoldFont = await PdfGoogleFonts.cairoBold();

    final pdf = pw.Document();
    final reportTitle = title ?? 'تقرير المهام';
    final now = _dateTimeFmt.format(DateTime.now());

    // إحصائيات
    final total = tasks.length;
    final done = tasks.where((t) => t.status == 'مكتملة').length;
    final cancelled = tasks.where((t) => t.status == 'ملغية').length;
    final open = tasks.where((t) => t.status == 'مفتوحة').length;
    final progress = tasks.where((t) => t.status == 'قيد التنفيذ').length;
    final totalAmount = tasks.fold<double>(0, (sum, t) {
      return sum + (double.tryParse(t.amount.replaceAll('\$', '').replaceAll(',', '')) ?? 0);
    });

    // تقسيم المهام إلى صفحات (15 مهمة لكل صفحة)
    final pageSize = 15;
    final pageCount = (tasks.length / pageSize).ceil().clamp(1, 100);

    for (int page = 0; page < pageCount; page++) {
      final start = page * pageSize;
      final end = (start + pageSize).clamp(0, tasks.length);
      final pageTasks = tasks.sublist(start, end);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBoldFont),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // الترويسة
              if (page == 0) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.indigo900,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(now, style: pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                      pw.Text(reportTitle, style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 8),

                // بطاقات الإحصائيات
                pw.Row(
                  children: [
                    _pdfStatCard('الإجمالي', '$total', PdfColors.blue),
                    pw.SizedBox(width: 8),
                    _pdfStatCard('مفتوحة', '$open', PdfColors.orange),
                    pw.SizedBox(width: 8),
                    _pdfStatCard('تنفيذ', '$progress', PdfColors.amber),
                    pw.SizedBox(width: 8),
                    _pdfStatCard('مكتملة', '$done', PdfColors.green),
                    pw.SizedBox(width: 8),
                    _pdfStatCard('ملغية', '$cancelled', PdfColors.red),
                    pw.SizedBox(width: 8),
                    _pdfStatCard('المبلغ', _currencyFmt.format(totalAmount.round()), PdfColors.purple),
                  ],
                ),
                pw.SizedBox(height: 10),
              ],

              // جدول المهام
              pw.TableHelper.fromTextArray(
                headerDirection: pw.TextDirection.rtl,
                cellAlignment: pw.Alignment.centerRight,
                headerAlignment: pw.Alignment.center,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
                cellStyle: const pw.TextStyle(fontSize: 7),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo900),
                rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
                headers: ['#', 'العنوان', 'الحالة', 'القسم', 'الفني', 'العميل', 'الهاتف', 'المبلغ', 'التاريخ'],
                data: pageTasks.asMap().entries.map((e) {
                  final t = e.value;
                  final idx = start + e.key + 1;
                  return [
                    '$idx',
                    t.title.length > 25 ? '${t.title.substring(0, 25)}...' : t.title,
                    t.status,
                    t.department,
                    t.technician,
                    t.username,
                    t.phone,
                    t.amount.isNotEmpty ? t.amount : '-',
                    DateFormat('MM/dd').format(t.createdAt),
                  ];
                }).toList(),
              ),

              pw.Spacer(),

              // التذييل
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('صفحة ${page + 1} من $pageCount', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                  pw.Text('شركة رمز الصدارة — نظام إدارة المهام', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // حفظ
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/تقرير_المهام_${_dateFmt.format(DateTime.now())}.pdf';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());

    try { await OpenFilex.open(path); } catch (_) {}
    return path;
  }

  /// بطاقة إحصائية في PDF
  static pw.Expanded _pdfStatCard(String label, String value, PdfColor color) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: pw.BoxDecoration(
          color: color.shade(0.95),
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: color, width: 1),
        ),
        child: pw.Column(
          children: [
            pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
            pw.SizedBox(height: 2),
            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
      ),
    );
  }

  /// مشاركة الملف
  static Future<void> shareFile(String path) async {
    await Share.shareXFiles([XFile(path)]);
  }

  // ─── Helpers ───

  static CellStyle? _getStatusCellStyle(String status) {
    switch (status) {
      case 'مكتملة': return CellStyle(backgroundColorHex: _greenBg);
      case 'ملغية': return CellStyle(backgroundColorHex: _redBg);
      case 'قيد التنفيذ': return CellStyle(backgroundColorHex: _orangeBg);
      default: return null;
    }
  }

  static Future<String> _saveAndOpen(Excel excel, String reportName) async {
    final dir = await getApplicationDocumentsDirectory();
    final ts = _dateFmt.format(DateTime.now());
    final path = '${dir.path}/${reportName}_$ts.xlsx';
    final bytes = excel.save();
    if (bytes != null) {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes);
    }
    try { await OpenFilex.open(path); } catch (_) {}
    return path;
  }

  static void _addRow(Sheet sheet, int row, List<String> values, {CellStyle? style}) {
    for (int i = 0; i < values.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
      cell.value = TextCellValue(values[i]);
      if (style != null) cell.cellStyle = style;
    }
  }
}
