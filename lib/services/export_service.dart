import 'dart:io';
import 'dart:ui';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/task.dart';

class ExportService {
  // تصدير لـ Excel مع تنسيق متقدم
  static Future<String> exportToExcel(
    List<Task> tasks, {
    String? filterInfo,
    bool includeAnalytics = true,
  }) async {
    var excel = Excel.createExcel();
    var sheet = excel['المهام'];

    // إعداد العناوين بتنسيق جميل
    var headers = [
      'رقم المهمة',
      'الحالة',
      'القسم',
      'عنوان المهمة',
      'الليدر',
      'الفني',
      'اسم العميل',
      'رقم الهاتف',
      'FBG',
      'FAT',
      'الموقع',
      'الملاحظات',
      'تاريخ الإنشاء',
      'تاريخ الإغلاق',
      'الملخص',
      'الأولوية',
      'المبلغ',
      'مدة التنفيذ'
    ];

    // إضافة العناوين مع تنسيق
    for (int i = 0; i < headers.length; i++) {
      var cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        backgroundColorHex: ExcelColor.blue,
        fontColorHex: ExcelColor.white,
        bold: true,
      );
    }

    // إضافة البيانات
    for (int i = 0; i < tasks.length; i++) {
      var task = tasks[i];
      var row = i + 1;

      var duration = task.closedAt != null
          ? task.closedAt!.difference(task.createdAt)
          : Duration.zero;

      var rowData = [
        task.id,
        task.status,
        task.department,
        task.title,
        task.leader,
        task.technician,
        task.username,
        task.phone,
        task.fbg,
        task.fat,
        task.location,
        task.notes,
        task.createdAt.toString().split('.')[0],
        task.closedAt?.toString().split('.')[0] ?? '',
        task.summary,
        task.priority,
        task.amount,
        '${duration.inHours}:${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}'
      ];

      for (int j = 0; j < rowData.length; j++) {
        var cell = sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: row));
        cell.value = TextCellValue(rowData[j].toString());

        // تلوين الصفوف حسب الحالة
        Color rowColor = _getStatusColor(task.status);
        int alpha = ((rowColor.a * 255.0).round() & 0xff);
        int red = ((rowColor.r * 255.0).round() & 0xff);
        int green = ((rowColor.g * 255.0).round() & 0xff);
        int blue = ((rowColor.b * 255.0).round() & 0xff);

        String colorHex = alpha.toRadixString(16).padLeft(2, '0') +
            red.toRadixString(16).padLeft(2, '0') +
            green.toRadixString(16).padLeft(2, '0') +
            blue.toRadixString(16).padLeft(2, '0');

        cell.cellStyle = CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(colorHex),
        );
      }
    }

    // إضافة ورقة التحليلات إذا طُلبت
    if (includeAnalytics) {
      _addAnalyticsSheet(excel, tasks);
    }

    // حفظ الملف
    var directory = await getApplicationDocumentsDirectory();
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    var filePath = '${directory.path}/tasks_export_$timestamp.xlsx';

    var fileBytes = excel.save();
    if (fileBytes != null) {
      File(filePath)
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);
    }

    return filePath;
  }

  // تصدير لـ PDF مع تقرير شامل
  static Future<String> exportToPDF(
    List<Task> tasks, {
    String? filterInfo,
    bool includeCharts = true,
  }) async {
    final pdf = pw.Document();

    // الصفحة الأولى - ملخص تنفيذي
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // العنوان الرئيسي
              pw.Container(
                width: double.infinity,
                padding: pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue,
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'تقرير إدارة المهام - FTTH',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      'تاريخ التقرير: ${DateTime.now().toString().split(' ')[0]}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 30),

              // الإحصائيات السريعة
              pw.Text(
                'الملخص التنفيذي',
                style:
                    pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 15),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildPDFStatCard('إجمالي المهام', tasks.length.toString()),
                  _buildPDFStatCard(
                      'مكتملة',
                      tasks
                          .where((t) => t.status == 'مكتملة')
                          .length
                          .toString()),
                  _buildPDFStatCard(
                      'قيد التنفيذ',
                      tasks
                          .where((t) => t.status == 'قيد التنفيذ')
                          .length
                          .toString()),
                  _buildPDFStatCard(
                      'مفتوحة',
                      tasks
                          .where((t) => t.status == 'مفتوحة')
                          .length
                          .toString()),
                ],
              ),

              pw.SizedBox(height: 30),

              // معلومات التصفية
              if (filterInfo != null) ...[
                pw.Text(
                  'معايير التصفية المطبقة:',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Container(
                  padding: pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Text(filterInfo),
                ),
              ],
            ],
          );
        },
      ),
    );

    // الصفحة الثانية - جدول المهام
    if (tasks.isNotEmpty) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: pw.EdgeInsets.all(32),
          build: (pw.Context context) => [
            pw.Text(
              'تفاصيل المهام',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            pw.TableHelper.fromTextArray(
              context: context,
              data: [
                [
                  'رقم المهمة',
                  'الحالة',
                  'القسم',
                  'العنوان',
                  'الفني',
                  'المبلغ',
                  'التاريخ'
                ],
                ...tasks.map((task) => [
                      task.id,
                      task.status,
                      task.department,
                      task.title.length > 20
                          ? '${task.title.substring(0, 20)}...'
                          : task.title,
                      task.technician,
                      task.amount,
                      task.createdAt.toString().split(' ')[0],
                    ]),
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignment: pw.Alignment.center,
              cellPadding: pw.EdgeInsets.all(5),
            ),
          ],
        ),
      );
    }

    // حفظ الملف
    var directory = await getApplicationDocumentsDirectory();
    var timestamp = DateTime.now().millisecondsSinceEpoch;
    var filePath = '${directory.path}/tasks_report_$timestamp.pdf';

    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return filePath;
  }

  // مشاركة الملف
  static Future<void> shareFile(String filePath, String title) async {
    final file = XFile(filePath);
    await Share.shareXFiles(
      [file],
      text: title,
      subject: 'تقرير المهام - FTTH',
    );
  }

  // وظائف مساعدة
  static Color _getStatusColor(String status) {
    switch (status) {
      case 'مكتملة':
        return Color(0xFFE8F5E8);
      case 'قيد التنفيذ':
        return Color(0xFFFFF3CD);
      case 'مفتوحة':
        return Color(0xFFE3F2FD);
      case 'ملغية':
        return Color(0xFFFDEDED);
      default:
        return Color(0xFFF5F5F5);
    }
  }

  static void _addAnalyticsSheet(Excel excel, List<Task> tasks) {
    var analyticsSheet = excel['التحليلات'];

    // إحصائيات عامة
    var stats = [
      ['المؤشر', 'القيمة'],
      ['إجمالي المهام', tasks.length.toString()],
      [
        'المهام المكتملة',
        tasks.where((t) => t.status == 'مكتملة').length.toString()
      ],
      [
        'معدل الإنجاز',
        '${((tasks.where((t) => t.status == 'مكتملة').length / tasks.length) * 100).toStringAsFixed(1)}%'
      ],
      ['متوسط المبلغ', _calculateAverageAmount(tasks).toStringAsFixed(2)],
    ];

    for (int i = 0; i < stats.length; i++) {
      for (int j = 0; j < stats[i].length; j++) {
        var cell = analyticsSheet
            .cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: i));
        cell.value = TextCellValue(stats[i][j]);
        if (i == 0) {
          cell.cellStyle =
              CellStyle(bold: true, backgroundColorHex: ExcelColor.blue);
        }
      }
    }
  }

  static double _calculateAverageAmount(List<Task> tasks) {
    if (tasks.isEmpty) return 0;
    var totalAmount = tasks.fold(
        0.0, (sum, task) => sum + (double.tryParse(task.amount) ?? 0));
    return totalAmount / tasks.length;
  }

  static pw.Widget _buildPDFStatCard(String title, String value) {
    return pw.Container(
      padding: pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(value,
              style:
                  pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 5),
          pw.Text(title, style: pw.TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
