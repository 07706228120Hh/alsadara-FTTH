/// شاشة «دفعات QR» — توليد دفعة رموز QR فارغة مسبقاً + طباعة شبكية (A4) للقصّ،
/// ثم تُملأ لاحقاً عند مسح الرمز (يفتح نموذج عقار بوضع رمز فارغ).
///
/// نظام أساسي ينادي بوّابة الصدارة `/api/properties/qr-batches`. بثيم الصدارة،
/// RTL. الطباعة الشبكية على نطاق تسلسل محدود (تفادي توليد الآلاف دفعةً واحدة).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../services/property_api_service.dart';
import '../../theme/app_theme.dart';
import 'property_ui.dart';

class PropertyQrBatchesPage extends StatefulWidget {
  const PropertyQrBatchesPage({super.key});

  @override
  State<PropertyQrBatchesPage> createState() => _PropertyQrBatchesPageState();
}

class _PropertyQrBatchesPageState extends State<PropertyQrBatchesPage> {
  final _api = PropertyApiService.instance;

  List<PropertyQrBatch> _rows = const [];
  bool _loading = true;
  String? _error;

  // حدود/افتراضيات التوليد.
  static const int _defaultCount = 10000;
  static const int _maxCount = 20000;
  // حدّ آمن لعدد الرموز في طباعة واحدة (24 خلية/صفحة → ~42 صفحة).
  static const int _maxTokensPerPrint = 1000;
  // شبكة الطباعة A4.
  static const int _cols = 4;
  static const int _rowsPerPage = 6;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.listQrBatches();
      if (!mounted) return;
      setState(() {
        _rows = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _msg(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: err ? AppTheme.errorColor : AppTheme.successColor,
      ),
    );
  }

  // ─────────────────────────── توليد دفعة ───────────────────────────

  Future<void> _generate() async {
    final result = await showDialog<_GenerateResult>(
      context: context,
      builder: (_) => const _GenerateDialog(
        defaultCount: _defaultCount,
        maxCount: _maxCount,
      ),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      await _api.generateQrBatch(result.count, note: result.note);
      _msg('تمّ توليد دفعة بـ ${result.count} رمزاً');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _msg('تعذّر توليد الدفعة: $e', err: true);
    }
  }

  // ─────────────────────────── الطباعة الشبكية ───────────────────────────

  Future<void> _print(PropertyQrBatch b) async {
    final range = await showDialog<_PrintRange>(
      context: context,
      builder: (_) => _PrintRangeDialog(
        batch: b,
        maxTokensPerPrint: _maxTokensPerPrint,
      ),
    );
    if (range == null) return;

    // تنبيه عند نطاق كبير.
    final span = range.toSerial - range.fromSerial + 1;
    if (span > _maxTokensPerPrint) {
      _msg('النطاق كبير جداً ($span) — الحدّ $_maxTokensPerPrint لكل طباعة',
          err: true);
      return;
    }

    _showBlocking('جارٍ تجهيز الرموز للطباعة…');
    try {
      final tokens = await _api.getBatchTokens(
        b.batchId,
        fromSerial: range.fromSerial,
        toSerial: range.toSerial,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // أغلق الحاجب
      if (tokens.isEmpty) {
        _msg('لا رموز ضمن النطاق المحدّد', err: true);
        return;
      }
      await _layoutGridPdf(tokens, b);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _msg('تعذّرت الطباعة: $e', err: true);
    }
  }

  void _showBlocking(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(message,
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// يولّد PDF A4 شبكي: 4×6 خلايا/صفحة، كل خلية QR + الرقم التسلسلي للقصّ.
  Future<void> _layoutGridPdf(
      List<PropertyQrToken> tokens, PropertyQrBatch b) async {
    final base = await PdfGoogleFonts.notoSansArabicRegular();
    final bold = await PdfGoogleFonts.notoSansArabicBold();
    final perPage = _cols * _rowsPerPage;

    final doc = pw.Document();

    for (int start = 0; start < tokens.length; start += perPage) {
      final slice = tokens.sublist(
          start,
          (start + perPage) > tokens.length
              ? tokens.length
              : (start + perPage));
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(18),
          theme: pw.ThemeData.withFont(base: base, bold: bold),
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'رموز العنوان الوطني — دفعة ${_shortId(b.batchId)}'
                  '${b.note.isNotEmpty ? ' · ${b.note}' : ''}',
                  style: pw.TextStyle(font: bold, fontSize: 11),
                ),
                pw.SizedBox(height: 8),
                pw.Expanded(
                  child: pw.GridView(
                    crossAxisCount: _cols,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: [
                      for (final t in slice) _cell(t, base),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  pw.Widget _cell(PropertyQrToken t, pw.Font base) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5, color: PdfColors.grey400),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: t.payload,
              drawText: false,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text('#${t.serial}',
              style: pw.TextStyle(font: base, fontSize: 9)),
        ],
      ),
    );
  }

  String _shortId(String id) =>
      id.length <= 8 ? id : id.substring(0, 8);

  String _shortDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PropUi.pageBg,
        appBar: PropUi.appBar(
          'دفعات QR',
          leadingIcon: Icons.qr_code_2_rounded,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : _generate,
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.add_box_rounded, color: Colors.white),
          label: Text('توليد دفعة',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        body: PropContentWrap(
          maxWidth: 900,
          child: _loading
              ? const PropLoadingView(message: 'جارٍ تحميل الدفعات…')
              : _error != null
                  ? PropErrorView(message: _error!, onRetry: _load)
                  : _rows.isEmpty
                      ? PropEmptyView(
                          message:
                              'لا دفعات بعد — ولّد دفعة رموز QR فارغة للطباعة.',
                          icon: Icons.qr_code_scanner_rounded,
                          action: FilledButton.icon(
                            onPressed: _generate,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 12),
                            ),
                            icon: const Icon(Icons.add_box_rounded,
                                color: Colors.white),
                            label: Text('توليد دفعة',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _batchCard(_rows[i]),
                        ),
        ),
      ),
    );
  }

  Widget _batchCard(PropertyQrBatch b) {
    final fullyUsed = b.remaining == 0 && b.count > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PropUi.card(),
      child: Row(
        children: [
          PropUi.gradientBadge(
            icon: Icons.qr_code_2_rounded,
            colors: AppTheme.blueGradient,
            size: 46,
            iconSize: 23,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  b.note.isNotEmpty ? b.note : 'دفعة ${_shortId(b.batchId)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: PropUi.ink),
                ),
                if (b.createdAt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(_shortDate(b.createdAt),
                      style: GoogleFonts.cairo(
                          fontSize: 12, color: Colors.grey[600])),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _tag('العدد ${b.count}', AppTheme.primaryColor),
                    _tag('المستخدَم ${b.usedCount}', AppTheme.warningColor),
                    _tag(
                        fullyUsed ? 'مكتملة' : 'المتبقّي ${b.remaining}',
                        fullyUsed
                            ? Colors.grey
                            : AppTheme.successColor),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: b.count > 0 ? () => _print(b) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side:
                  BorderSide(color: AppTheme.primaryColor.withValues(alpha: 0.4)),
            ),
            icon: const Icon(Icons.print_rounded, size: 18),
            label: Text('طباعة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(PropUi.radiusPill),
          border: Border.all(color: c.withValues(alpha: 0.22)),
        ),
        child: Text(t,
            style: GoogleFonts.cairo(
                color: c, fontWeight: FontWeight.w700, fontSize: 11)),
      );
}

// ─────────────────────── حوار توليد دفعة ───────────────────────

class _GenerateResult {
  final int count;
  final String? note;
  const _GenerateResult(this.count, this.note);
}

class _GenerateDialog extends StatefulWidget {
  final int defaultCount;
  final int maxCount;
  const _GenerateDialog({required this.defaultCount, required this.maxCount});

  @override
  State<_GenerateDialog> createState() => _GenerateDialogState();
}

class _GenerateDialogState extends State<_GenerateDialog> {
  late final _count =
      TextEditingController(text: '${widget.defaultCount}');
  final _note = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final n = int.tryParse(_count.text.trim());
    if (n == null || n <= 0) {
      setState(() => _err = 'أدخل عدداً صحيحاً أكبر من صفر');
      return;
    }
    if (n > widget.maxCount) {
      setState(() => _err = 'الحدّ الأقصى ${widget.maxCount} رمزاً');
      return;
    }
    Navigator.pop(
        context,
        _GenerateResult(
            n, _note.text.trim().isEmpty ? null : _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.add_box_rounded, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text('توليد دفعة رموز QR',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _count,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'عدد الرموز (حتى ${widget.maxCount})',
                labelStyle: GoogleFonts.cairo(),
                prefixIcon: const Icon(Icons.numbers_rounded,
                    color: AppTheme.primaryColor),
                errorText: _err,
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                labelStyle: GoogleFonts.cairo(),
                prefixIcon: const Icon(Icons.notes_rounded,
                    color: AppTheme.primaryColor),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: Text('توليد',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── حوار نطاق الطباعة ───────────────────────

class _PrintRange {
  final int fromSerial;
  final int toSerial;
  const _PrintRange(this.fromSerial, this.toSerial);
}

class _PrintRangeDialog extends StatefulWidget {
  final PropertyQrBatch batch;
  final int maxTokensPerPrint;
  const _PrintRangeDialog(
      {required this.batch, required this.maxTokensPerPrint});

  @override
  State<_PrintRangeDialog> createState() => _PrintRangeDialogState();
}

class _PrintRangeDialogState extends State<_PrintRangeDialog> {
  late final _from = TextEditingController(text: '1');
  late final _to = TextEditingController(
      text: '${widget.batch.count < widget.maxTokensPerPrint ? widget.batch.count : widget.maxTokensPerPrint}');
  String? _err;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _submit() {
    final f = int.tryParse(_from.text.trim());
    final t = int.tryParse(_to.text.trim());
    if (f == null || t == null || f <= 0 || t <= 0) {
      setState(() => _err = 'أدخل نطاقاً صحيحاً');
      return;
    }
    if (f > t) {
      setState(() => _err = '«من» يجب أن يكون أصغر من «إلى»');
      return;
    }
    if (t > widget.batch.count) {
      setState(() => _err = 'الحدّ الأعلى للدفعة ${widget.batch.count}');
      return;
    }
    final span = t - f + 1;
    if (span > widget.maxTokensPerPrint) {
      setState(() =>
          _err = 'النطاق $span كبير — الحدّ ${widget.maxTokensPerPrint} لكل طباعة');
      return;
    }
    Navigator.pop(context, _PrintRange(f, t));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.print_rounded, color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text('نطاق الطباعة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'دفعة بـ ${widget.batch.count} رمزاً. اختر نطاق تسلسل للطباعة '
              '(حتى ${widget.maxTokensPerPrint} لكل مرّة).',
              style:
                  GoogleFonts.cairo(fontSize: 12.5, color: Colors.grey[700]),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'من تسلسل',
                      labelStyle: GoogleFonts.cairo(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      labelText: 'إلى تسلسل',
                      labelStyle: GoogleFonts.cairo(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!,
                  style: GoogleFonts.cairo(
                      color: AppTheme.errorColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
          FilledButton.icon(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white),
            label: Text('طباعة',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
