import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

/// خدمة تصدير التقارير المحاسبية إلى PDF مع معاينة الطباعة
class AccountingPdfExportService {
  // ─── ألوان مشتركة ───
  static const _headerBg = PdfColor.fromInt(0xFF2C3E50);
  static const _headerText = PdfColors.white;
  static final _totalBg = PdfColor.fromHex('#E8E8E8');
  static final _greenBg = PdfColor.fromHex('#E8F8F0');
  static final _redBg = PdfColor.fromHex('#FDE8E8');
  static final _positiveColor = PdfColor.fromHex('#27AE60');
  static final _negativeColor = PdfColor.fromHex('#E74C3C');

  // ─── تنسيق الأرقام ───
  static final _currencyFmt = NumberFormat('#,##0', 'ar');

  static String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return _currencyFmt.format(n.round());
  }

  // ─── رأس الصفحة ───
  static pw.Widget _buildHeader(String title, {String? subtitle}) {
    final dateFmt = DateFormat('yyyy/MM/dd');
    final dateStr = dateFmt.format(DateTime.now());

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              dateStr,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
              textDirection: pw.TextDirection.rtl,
            ),
          ],
        ),
        if (subtitle != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                subtitle,
                style: const pw.TextStyle(
                    fontSize: 12, color: PdfColors.grey600),
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 8),
      ],
    );
  }

  // ─── تذييل الصفحة ───
  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'صفحة ${context.pageNumber} من ${context.pagesCount}',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  // ─── أنماط خلايا الجدول ───
  static pw.TextStyle _headerCellStyle() {
    return pw.TextStyle(
      fontWeight: pw.FontWeight.bold,
      color: _headerText,
      fontSize: 10,
    );
  }

  static pw.TextStyle _normalCellStyle() {
    return const pw.TextStyle(fontSize: 9);
  }

  static pw.TextStyle _boldCellStyle() {
    return pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
  }

  // ═══════════════════════════════════════════════════════════════
  // 1. تصدير ميزان المراجعة
  // ═══════════════════════════════════════════════════════════════
  static Future<void> exportTrialBalance(List<dynamic> accounts) async {
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();
    final theme = pw.ThemeData.withFont(base: arabicFont, bold: arabicBold);

    final doc = pw.Document(theme: theme);

    double totalDebit = 0;
    double totalCredit = 0;

    // حساب المجاميع مسبقاً
    for (final a in accounts) {
      final bal =
          ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num).toDouble();
      if (bal > 0) {
        totalDebit += bal;
      } else if (bal < 0) {
        totalCredit += bal.abs();
      }
    }

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => _buildHeader('ميزان المراجعة'),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          pw.TableHelper.fromTextArray(
            context: ctx,
            cellAlignment: pw.Alignment.centerRight,
            headerDirection: pw.TextDirection.rtl,
            headerDecoration:
                const pw.BoxDecoration(color: _headerBg),
            headerStyle: _headerCellStyle(),
            cellStyle: _normalCellStyle(),
            headerAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
            headers: ['#', 'الكود', 'اسم الحساب', 'النوع', 'مدين', 'دائن'],
            data: [
              // صفوف البيانات
              ...List.generate(accounts.length, (i) {
                final a = accounts[i];
                final bal = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num)
                    .toDouble();
                final debit = bal > 0 ? bal : 0.0;
                final credit = bal < 0 ? bal.abs() : 0.0;

                return [
                  '${i + 1}',
                  a['Code']?.toString() ?? '',
                  a['Name']?.toString() ?? '',
                  a['AccountType']?.toString() ??
                      a['Type']?.toString() ??
                      '',
                  debit > 0 ? _formatNumber(debit) : '',
                  credit > 0 ? _formatNumber(credit) : '',
                ];
              }),
              // صف الإجمالي
              [
                '',
                '',
                'الإجمالي',
                '',
                _formatNumber(totalDebit),
                _formatNumber(totalCredit),
              ],
            ],
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                    color: PdfColors.grey300, width: 0.5),
              ),
            ),
            oddRowDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F9F9F9'),
            ),
            cellAlignments: {
              0: pw.Alignment.center,
              1: pw.Alignment.centerRight,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
          // صف الإجمالي مميز
          pw.Container(
            color: _totalBg,
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(_formatNumber(totalCredit),
                    style: _boldCellStyle(),
                    textDirection: pw.TextDirection.rtl),
                pw.Text(_formatNumber(totalDebit),
                    style: _boldCellStyle(),
                    textDirection: pw.TextDirection.rtl),
                pw.Text('الإجمالي',
                    style: _boldCellStyle(),
                    textDirection: pw.TextDirection.rtl),
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save());
  }

  // ═══════════════════════════════════════════════════════════════
  // 2. تصدير قائمة الدخل
  // ═══════════════════════════════════════════════════════════════
  static Future<void> exportIncomeStatement({
    required List<dynamic> revenue,
    required List<dynamic> expenses,
    required double totalRevenue,
    required double totalExpenses,
    required double netIncome,
    String? dateRange,
  }) async {
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();
    final theme = pw.ThemeData.withFont(base: arabicFont, bold: arabicBold);

    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => _buildHeader(
          'قائمة الدخل',
          subtitle: dateRange,
        ),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          // ─── قسم الإيرادات ───
          _buildSectionHeader('الإيرادات', _greenBg),
          pw.SizedBox(height: 4),
          _buildThreeColumnTable(
            ctx: ctx,
            items: revenue.map((a) {
              final bal = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num)
                  .toDouble()
                  .abs();
              return [
                a['Code']?.toString() ?? '',
                a['Name']?.toString() ?? '',
                _formatNumber(bal),
              ];
            }).toList(),
          ),
          _buildSubtotalRow('إجمالي الإيرادات', totalRevenue, _greenBg),
          pw.SizedBox(height: 16),

          // ─── قسم المصروفات ───
          _buildSectionHeader('المصروفات', _redBg),
          pw.SizedBox(height: 4),
          _buildThreeColumnTable(
            ctx: ctx,
            items: expenses.map((a) {
              final bal = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num)
                  .toDouble()
                  .abs();
              return [
                a['Code']?.toString() ?? '',
                a['Name']?.toString() ?? '',
                _formatNumber(bal),
              ];
            }).toList(),
          ),
          _buildSubtotalRow('إجمالي المصروفات', totalExpenses, _redBg),
          pw.SizedBox(height: 16),

          // ─── صافي الربح / الخسارة ───
          pw.Container(
            color: netIncome >= 0 ? _greenBg : _redBg,
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _formatNumber(netIncome.abs()),
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                    color: netIncome >= 0 ? _positiveColor : _negativeColor,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  netIncome >= 0 ? 'صافي الربح' : 'صافي الخسارة',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                    color: netIncome >= 0 ? _positiveColor : _negativeColor,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save());
  }

  // ═══════════════════════════════════════════════════════════════
  // 3. تصدير الميزانية العمومية
  // ═══════════════════════════════════════════════════════════════
  static Future<void> exportBalanceSheet({
    required List<dynamic> assets,
    required List<dynamic> liabilities,
    required List<dynamic> equity,
    required double totalAssets,
    required double totalLiabilities,
    required double totalEquity,
    double retainedEarnings = 0,
  }) async {
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();
    final theme = pw.ThemeData.withFont(base: arabicFont, bold: arabicBold);

    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => _buildHeader('الميزانية العمومية'),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          // ─── قسم الأصول ───
          _buildSectionHeader('الأصول', _greenBg),
          pw.SizedBox(height: 4),
          _buildThreeColumnTable(
            ctx: ctx,
            items: assets.map((a) {
              final bal = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num)
                  .toDouble()
                  .abs();
              return [
                a['Code']?.toString() ?? '',
                a['Name']?.toString() ?? '',
                _formatNumber(bal),
              ];
            }).toList(),
          ),
          _buildSubtotalRow('إجمالي الأصول', totalAssets, _totalBg),
          pw.SizedBox(height: 16),

          // ─── قسم الخصوم ───
          _buildSectionHeader('الخصوم', _redBg),
          pw.SizedBox(height: 4),
          _buildThreeColumnTable(
            ctx: ctx,
            items: liabilities.map((a) {
              final bal = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num)
                  .toDouble()
                  .abs();
              return [
                a['Code']?.toString() ?? '',
                a['Name']?.toString() ?? '',
                _formatNumber(bal),
              ];
            }).toList(),
          ),
          _buildSubtotalRow('إجمالي الخصوم', totalLiabilities, _totalBg),
          pw.SizedBox(height: 16),

          // ─── قسم حقوق الملكية ───
          _buildSectionHeader('حقوق الملكية', PdfColor.fromHex('#E8EAF6')),
          pw.SizedBox(height: 4),
          _buildThreeColumnTable(
            ctx: ctx,
            items: [
              ...equity.map((a) {
                final bal = ((a['Balance'] ?? a['CurrentBalance'] ?? 0) as num)
                    .toDouble()
                    .abs();
                return [
                  a['Code']?.toString() ?? '',
                  a['Name']?.toString() ?? '',
                  _formatNumber(bal),
                ];
              }),
              if (retainedEarnings != 0)
                [
                  '',
                  'الأرباح المحتجزة',
                  _formatNumber(retainedEarnings),
                ],
            ],
          ),
          _buildSubtotalRow('إجمالي حقوق الملكية', totalEquity, _totalBg),
          pw.SizedBox(height: 16),

          // ─── إجمالي الالتزامات وحقوق الملكية ───
          pw.Container(
            color: _totalBg,
            padding:
                const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _formatNumber(
                      totalLiabilities + totalEquity + retainedEarnings),
                  style: _boldCellStyle(),
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'إجمالي الالتزامات وحقوق الملكية',
                  style: _boldCellStyle(),
                  textDirection: pw.TextDirection.rtl,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save());
  }

  // ═══════════════════════════════════════════════════════════════
  // 4. تصدير قائمة التدفقات النقدية
  // ═══════════════════════════════════════════════════════════════
  static Future<void> exportCashFlow({
    required List<Map<String, dynamic>> operating,
    required List<Map<String, dynamic>> investing,
    required List<Map<String, dynamic>> financing,
    required double totalOperating,
    required double totalInvesting,
    required double totalFinancing,
    String? dateRange,
  }) async {
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();
    final theme = pw.ThemeData.withFont(base: arabicFont, bold: arabicBold);

    final doc = pw.Document(theme: theme);

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => _buildHeader(
          'قائمة التدفقات النقدية',
          subtitle: dateRange,
        ),
        footer: (ctx) => _buildFooter(ctx),
        build: (ctx) => [
          // ─── الأنشطة التشغيلية ───
          _buildSectionHeader('أنشطة تشغيلية', _greenBg),
          pw.SizedBox(height: 4),
          _buildTwoColumnTable(
            ctx: ctx,
            items: operating
                .map((item) => [
                      item['description']?.toString() ?? '',
                      _formatNumber(item['amount']),
                    ])
                .toList(),
          ),
          _buildSubtotalRow('إجمالي أنشطة تشغيلية', totalOperating, _totalBg),
          pw.SizedBox(height: 16),

          // ─── الأنشطة الاستثمارية ───
          _buildSectionHeader('أنشطة استثمارية', PdfColor.fromHex('#E8EAF6')),
          pw.SizedBox(height: 4),
          _buildTwoColumnTable(
            ctx: ctx,
            items: investing
                .map((item) => [
                      item['description']?.toString() ?? '',
                      _formatNumber(item['amount']),
                    ])
                .toList(),
          ),
          _buildSubtotalRow(
              'إجمالي أنشطة استثمارية', totalInvesting, _totalBg),
          pw.SizedBox(height: 16),

          // ─── الأنشطة التمويلية ───
          _buildSectionHeader('أنشطة تمويلية', _redBg),
          pw.SizedBox(height: 4),
          _buildTwoColumnTable(
            ctx: ctx,
            items: financing
                .map((item) => [
                      item['description']?.toString() ?? '',
                      _formatNumber(item['amount']),
                    ])
                .toList(),
          ),
          _buildSubtotalRow('إجمالي أنشطة تمويلية', totalFinancing, _totalBg),
          pw.SizedBox(height: 16),

          // ─── صافي التدفق النقدي ───
          _buildNetCashFlowRow(
              totalOperating + totalInvesting + totalFinancing),
        ],
      ),
    );

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save());
  }

  // ═══════════════════════════════════════════════════════════════
  // ودجات مساعدة مشتركة
  // ═══════════════════════════════════════════════════════════════

  /// عنوان قسم ملون
  static pw.Widget _buildSectionHeader(String title, PdfColor bgColor) {
    return pw.Container(
      width: double.infinity,
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: pw.Text(
        '── $title ──',
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 11,
        ),
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  /// صف مجموع فرعي
  static pw.Widget _buildSubtotalRow(
      String label, double amount, PdfColor bgColor) {
    return pw.Container(
      color: bgColor,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            _formatNumber(amount),
            style: _boldCellStyle(),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Text(
            label,
            style: _boldCellStyle(),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  /// صف صافي التدفق النقدي
  static pw.Widget _buildNetCashFlowRow(double netCashFlow) {
    final isPositive = netCashFlow >= 0;
    return pw.Container(
      color: isPositive ? _greenBg : _redBg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            _formatNumber(netCashFlow.abs()),
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 12,
              color: isPositive ? _positiveColor : _negativeColor,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Text(
            'صافي التدفق النقدي',
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 12,
              color: isPositive ? _positiveColor : _negativeColor,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  /// جدول بثلاثة أعمدة (الكود، اسم الحساب، المبلغ)
  static pw.Widget _buildThreeColumnTable({
    required pw.Context ctx,
    required List<List<String>> items,
  }) {
    if (items.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(
          'لا توجد بيانات',
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey500,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }

    return pw.TableHelper.fromTextArray(
      context: ctx,
      cellAlignment: pw.Alignment.centerRight,
      headerDirection: pw.TextDirection.rtl,
      headerDecoration: const pw.BoxDecoration(color: _headerBg),
      headerStyle: _headerCellStyle(),
      cellStyle: _normalCellStyle(),
      headers: ['الكود', 'اسم الحساب', 'المبلغ'],
      headerAlignments: {
        0: pw.Alignment.centerRight,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
      },
      cellAlignments: {
        0: pw.Alignment.centerRight,
        1: pw.Alignment.centerRight,
        2: pw.Alignment.centerRight,
      },
      data: items,
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      oddRowDecoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F9F9F9'),
      ),
    );
  }

  /// جدول بعمودين (البند، المبلغ)
  static pw.Widget _buildTwoColumnTable({
    required pw.Context ctx,
    required List<List<String>> items,
  }) {
    if (items.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(8),
        child: pw.Text(
          'لا توجد بيانات',
          style: const pw.TextStyle(
            fontSize: 9,
            color: PdfColors.grey500,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }

    return pw.TableHelper.fromTextArray(
      context: ctx,
      cellAlignment: pw.Alignment.centerRight,
      headerDirection: pw.TextDirection.rtl,
      headerDecoration: const pw.BoxDecoration(color: _headerBg),
      headerStyle: _headerCellStyle(),
      cellStyle: _normalCellStyle(),
      headers: ['البند', 'المبلغ'],
      headerAlignments: {
        0: pw.Alignment.centerRight,
        1: pw.Alignment.centerRight,
      },
      cellAlignments: {
        0: pw.Alignment.centerRight,
        1: pw.Alignment.centerRight,
      },
      data: items,
      rowDecoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      oddRowDecoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F9F9F9'),
      ),
    );
  }
}
