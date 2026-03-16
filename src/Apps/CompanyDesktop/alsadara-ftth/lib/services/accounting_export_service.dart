import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';

/// خدمة تصدير التقارير المحاسبية إلى Excel
class AccountingExportService {
  static final _currencyFmt = NumberFormat('#,##0', 'ar');
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  static String _fmtNum(dynamic v) {
    if (v == null) return '0';
    final n = v is num ? v : double.tryParse(v.toString()) ?? 0;
    return _currencyFmt.format(n.round());
  }

  // ─── ألوان مشتركة ───
  static final _headerBg = ExcelColor.fromHexString('FF2C3E50');
  static final _headerFont = ExcelColor.white;
  static final _totalBg = ExcelColor.fromHexString('FFE8E8E8');
  static final _greenBg = ExcelColor.fromHexString('FFE8F8F0');
  static final _redBg = ExcelColor.fromHexString('FFFDE8E8');

  static CellStyle get _headerStyle => CellStyle(
        backgroundColorHex: _headerBg,
        fontColorHex: _headerFont,
        bold: true,
      );

  static CellStyle get _totalStyle => CellStyle(
        backgroundColorHex: _totalBg,
        bold: true,
      );

  // ─── حفظ وفتح الملف ───
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
    try {
      await OpenFile.open(path);
    } catch (_) {}
    return path;
  }

  // ─── إضافة صف بيانات ───
  static void _addRow(Sheet sheet, int row, List<String> values,
      {CellStyle? style}) {
    for (int i = 0; i < values.length; i++) {
      final cell =
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row));
      cell.value = TextCellValue(values[i]);
      if (style != null) cell.cellStyle = style;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 1. تصدير ميزان المراجعة
  // ═══════════════════════════════════════════════════════════════
  static Future<String> exportTrialBalance(List<dynamic> accounts) async {
    final excel = Excel.createExcel();
    final sheet = excel['ميزان المراجعة'];

    _addRow(sheet, 0, ['#', 'الكود', 'اسم الحساب', 'النوع', 'مدين', 'دائن'],
        style: _headerStyle);

    double totalDebit = 0, totalCredit = 0;
    for (int i = 0; i < accounts.length; i++) {
      final a = accounts[i];
      final bal =
          ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
      final debit = bal > 0 ? bal : 0.0;
      final credit = bal < 0 ? bal.abs() : 0.0;
      totalDebit += debit;
      totalCredit += credit;

      _addRow(sheet, i + 1, [
        '${i + 1}',
        a['Code']?.toString() ?? '',
        a['Name']?.toString() ?? '',
        a['AccountType']?.toString() ?? a['Type']?.toString() ?? '',
        debit > 0 ? _fmtNum(debit) : '',
        credit > 0 ? _fmtNum(credit) : '',
      ]);
    }

    _addRow(sheet, accounts.length + 1,
        ['', '', 'الإجمالي', '', _fmtNum(totalDebit), _fmtNum(totalCredit)],
        style: _totalStyle);

    return _saveAndOpen(excel, 'trial_balance');
  }

  // ═══════════════════════════════════════════════════════════════
  // 2. تصدير قائمة الدخل
  // ═══════════════════════════════════════════════════════════════
  static Future<String> exportIncomeStatement({
    required List<dynamic> revenue,
    required List<dynamic> expenses,
    required double totalRevenue,
    required double totalExpenses,
    required double netIncome,
    String? dateRange,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['قائمة الدخل'];

    if (dateRange != null) {
      _addRow(sheet, 0, ['قائمة الدخل - $dateRange'], style: _headerStyle);
    }
    final startRow = dateRange != null ? 2 : 0;

    // الإيرادات
    _addRow(sheet, startRow, ['الكود', 'اسم الحساب', 'المبلغ'],
        style: _headerStyle);
    _addRow(sheet, startRow + 1, ['', '── الإيرادات ──', ''],
        style: CellStyle(bold: true, backgroundColorHex: _greenBg));

    int row = startRow + 2;
    for (final a in revenue) {
      final bal =
          ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble().abs();
      _addRow(sheet, row, [
        a['Code']?.toString() ?? '',
        a['Name']?.toString() ?? '',
        _fmtNum(bal),
      ]);
      row++;
    }
    _addRow(sheet, row, ['', 'إجمالي الإيرادات', _fmtNum(totalRevenue)],
        style: _totalStyle);
    row += 2;

    // المصروفات
    _addRow(sheet, row, ['', '── المصروفات ──', ''],
        style: CellStyle(bold: true, backgroundColorHex: _redBg));
    row++;
    for (final a in expenses) {
      final bal =
          ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble().abs();
      _addRow(sheet, row, [
        a['Code']?.toString() ?? '',
        a['Name']?.toString() ?? '',
        _fmtNum(bal),
      ]);
      row++;
    }
    _addRow(sheet, row, ['', 'إجمالي المصروفات', _fmtNum(totalExpenses)],
        style: _totalStyle);
    row += 2;

    // صافي الربح
    _addRow(sheet, row, [
      '',
      netIncome >= 0 ? 'صافي الربح' : 'صافي الخسارة',
      _fmtNum(netIncome.abs()),
    ],
        style: CellStyle(
          bold: true,
          backgroundColorHex: netIncome >= 0 ? _greenBg : _redBg,
        ));

    return _saveAndOpen(excel, 'income_statement');
  }

  // ═══════════════════════════════════════════════════════════════
  // 3. تصدير الميزانية العمومية
  // ═══════════════════════════════════════════════════════════════
  static Future<String> exportBalanceSheet({
    required List<dynamic> assets,
    required List<dynamic> liabilities,
    required List<dynamic> equity,
    required double totalAssets,
    required double totalLiabilities,
    required double totalEquity,
    required double retainedEarnings,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['الميزانية العمومية'];

    _addRow(sheet, 0, ['الكود', 'اسم الحساب', 'المبلغ'], style: _headerStyle);

    int row = 1;
    // الأصول
    _addRow(sheet, row, ['', '── الأصول ──', ''],
        style: CellStyle(bold: true));
    row++;
    for (final a in assets) {
      final bal =
          ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble().abs();
      _addRow(sheet, row,
          [a['Code']?.toString() ?? '', a['Name']?.toString() ?? '', _fmtNum(bal)]);
      row++;
    }
    _addRow(sheet, row, ['', 'إجمالي الأصول', _fmtNum(totalAssets)],
        style: _totalStyle);
    row += 2;

    // الالتزامات
    _addRow(sheet, row, ['', '── الالتزامات ──', ''],
        style: CellStyle(bold: true));
    row++;
    for (final a in liabilities) {
      final bal =
          ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble().abs();
      _addRow(sheet, row,
          [a['Code']?.toString() ?? '', a['Name']?.toString() ?? '', _fmtNum(bal)]);
      row++;
    }
    _addRow(sheet, row, ['', 'إجمالي الالتزامات', _fmtNum(totalLiabilities)],
        style: _totalStyle);
    row += 2;

    // حقوق الملكية
    _addRow(sheet, row, ['', '── حقوق الملكية ──', ''],
        style: CellStyle(bold: true));
    row++;
    for (final a in equity) {
      final bal =
          ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble().abs();
      _addRow(sheet, row,
          [a['Code']?.toString() ?? '', a['Name']?.toString() ?? '', _fmtNum(bal)]);
      row++;
    }
    if (retainedEarnings != 0) {
      _addRow(
          sheet, row, ['', 'الأرباح المحتجزة', _fmtNum(retainedEarnings)]);
      row++;
    }
    _addRow(
        sheet,
        row,
        [
          '',
          'إجمالي الالتزامات وحقوق الملكية',
          _fmtNum(totalLiabilities + totalEquity + retainedEarnings)
        ],
        style: _totalStyle);

    return _saveAndOpen(excel, 'balance_sheet');
  }

  // ═══════════════════════════════════════════════════════════════
  // 4. تصدير التدفقات النقدية
  // ═══════════════════════════════════════════════════════════════
  static Future<String> exportCashFlow({
    required List<Map<String, dynamic>> operating,
    required List<Map<String, dynamic>> investing,
    required List<Map<String, dynamic>> financing,
    required double totalOperating,
    required double totalInvesting,
    required double totalFinancing,
    String? dateRange,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['التدفقات النقدية'];

    _addRow(sheet, 0, ['البند', 'المبلغ'], style: _headerStyle);

    int row = 1;
    void addSection(
        String title, List<Map<String, dynamic>> items, double total) {
      _addRow(sheet, row, ['── $title ──', ''],
          style: CellStyle(bold: true));
      row++;
      for (final item in items) {
        _addRow(sheet, row, [
          item['description']?.toString() ?? '',
          _fmtNum(item['amount']),
        ]);
        row++;
      }
      _addRow(sheet, row, ['إجمالي $title', _fmtNum(total)],
          style: _totalStyle);
      row += 2;
    }

    addSection('الأنشطة التشغيلية', operating, totalOperating);
    addSection('الأنشطة الاستثمارية', investing, totalInvesting);
    addSection('الأنشطة التمويلية', financing, totalFinancing);

    _addRow(
        sheet,
        row,
        [
          'صافي التدفق النقدي',
          _fmtNum(totalOperating + totalInvesting + totalFinancing)
        ],
        style: CellStyle(bold: true, backgroundColorHex: _greenBg));

    return _saveAndOpen(excel, 'cash_flow');
  }

  // ═══════════════════════════════════════════════════════════════
  // 5. تصدير أعمار الديون
  // ═══════════════════════════════════════════════════════════════
  static Future<String> exportAgingReport({
    required List<Map<String, dynamic>> debts,
    required Map<String, double> categoryTotals,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['أعمار الديون'];

    _addRow(
        sheet, 0, ['الفني', 'المبلغ', 'التاريخ', 'العمر (أيام)', 'الفئة'],
        style: _headerStyle);

    for (int i = 0; i < debts.length; i++) {
      final d = debts[i];
      _addRow(sheet, i + 1, [
        d['technician']?.toString() ?? '',
        _fmtNum(d['amount']),
        d['date']?.toString() ?? '',
        d['ageDays']?.toString() ?? '',
        d['category']?.toString() ?? '',
      ]);
    }

    int row = debts.length + 2;
    _addRow(sheet, row, ['── ملخص حسب الفئة ──', '', '', '', ''],
        style: CellStyle(bold: true));
    row++;
    for (final e in categoryTotals.entries) {
      _addRow(sheet, row, [e.key, _fmtNum(e.value), '', '', '']);
      row++;
    }
    _addRow(
        sheet,
        row,
        [
          'الإجمالي',
          _fmtNum(categoryTotals.values.fold(0.0, (a, b) => a + b)),
          '',
          '',
          ''
        ],
        style: _totalStyle);

    return _saveAndOpen(excel, 'aging_report');
  }

  // ═══════════════════════════════════════════════════════════════
  // 6. تصدير المقارنة الشهرية
  // ═══════════════════════════════════════════════════════════════
  static Future<String> exportMonthlyComparison({
    required List<Map<String, dynamic>> monthlyData,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['المقارنة الشهرية'];

    _addRow(
        sheet,
        0,
        [
          'الشهر',
          'الإيرادات',
          'المصروفات',
          'صافي الربح',
          'التغير %'
        ],
        style: _headerStyle);

    for (int i = 0; i < monthlyData.length; i++) {
      final m = monthlyData[i];
      _addRow(sheet, i + 1, [
        m['month']?.toString() ?? '',
        _fmtNum(m['revenue']),
        _fmtNum(m['expenses']),
        _fmtNum(m['netIncome']),
        m['changePercent'] != null
            ? '${(m['changePercent'] as num).toStringAsFixed(1)}%'
            : '-',
      ]);
    }

    return _saveAndOpen(excel, 'monthly_comparison');
  }
}
