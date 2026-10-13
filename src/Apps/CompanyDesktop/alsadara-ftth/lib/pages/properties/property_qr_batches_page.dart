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
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/property_api_service.dart';
import '../../theme/app_theme.dart';
import 'property_sticker.dart';
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
  // حدّ آمن لعدد الرموز في طباعة واحدة (20 ستيكر/صفحة → ~50 صفحة).
  static const int _maxTokensPerPrint = 1000;

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

  // preview=true ⇒ يفتح معاينة داخل التطبيق (فيها أزرار طباعة + حفظ/فتح PDF).
  // preview=false ⇒ طباعة مباشرة عبر حوار النظام.
  Future<void> _runPrint(PropertyQrBatch b, {required bool preview}) async {
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

    _showBlocking('جارٍ تجهيز الرموز…');
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
      final doc = await _buildGridDoc(tokens, b);
      if (!mounted) return;
      if (preview) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _PdfPreviewScreen(
              doc: doc,
              title: 'دفعة ${_shortId(b.batchId)}',
            ),
          ),
        );
      } else {
        await Printing.layoutPdf(onLayout: (_) async => doc.save());
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _msg('تعذّرت العملية: $e', err: true);
    }
  }

  // تعديل رقم هاتف الطباعة المحفوظ محلياً (يُطبع تحت كل رمز) دون توليد دفعة.
  Future<void> _editContactPhone() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(kPropertyQrContactPhoneKey) ?? '';
    if (!mounted) return;
    final ctrl = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.phone_rounded, color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              Text('هاتف الطباعة',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ],
          ),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.phone,
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: 'رقم الهاتف (يُطبع تحت كل رمز)',
              labelStyle: GoogleFonts.cairo(),
              helperText: 'يُحفظ محلياً ويُستخدم لكل الطباعات',
              helperStyle: GoogleFonts.cairo(fontSize: 11),
              isDense: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text('حفظ',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    await prefs.setString(kPropertyQrContactPhoneKey, saved);
    _msg(saved.isEmpty ? 'أُزيل هاتف الطباعة' : 'حُفظ هاتف الطباعة: $saved');
  }

  // يفتح شاشة الحالات التفصيلية لرموز الدفعة (مستخدَم/فارغ + العقار المرتبط).
  void _openTokens(PropertyQrBatch b) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _BatchTokensScreen(batch: b),
      ),
    );
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

  /// يبني PDF A4: كل ستيكر 5سم × 5سم بالضبط، مرتّب شبكياً بهوامش صغيرة للقصّ.
  /// عدد الأعمدة/الصفوف يُحسب من مقاس A4 تلقائياً (≈ 4×5 = 20 ستيكر/صفحة).
  Future<pw.Document> _buildGridDoc(
      List<PropertyQrToken> tokens, PropertyQrBatch b) async {
    // خط Cairo يغطّي العربية واللاتينية معاً فلا تظهر مربّعات لأي رمز.
    final base = await PdfGoogleFonts.cairoRegular();
    final bold = await PdfGoogleFonts.cairoBold();

    // رقم هاتف الاتصال المحفوظ محلياً — يُطبع تحت كل رمز (بدل التسلسل).
    final prefs = await SharedPreferences.getInstance();
    final phone = (prefs.getString(kPropertyQrContactPhoneKey) ?? '').trim();

    final cm = PdfPageFormat.cm; // نقاط لكل سنتيمتر
    final cell = 5.0 * cm; // الستيكر 5سم × 5سم بالضبط
    final gap = 0.1 * cm; // فاصل صغير بين الستيكرات للقصّ
    final margin = 0.25 * cm; // هامش الصفحة
    const headerH = 24.0; // ارتفاع العنوان أعلى الصفحة

    final pf = PdfPageFormat.a4;
    final usableW = pf.width - 2 * margin;
    final usableH = pf.height - 2 * margin - headerH;
    final cols = ((usableW + gap) / (cell + gap)).floor().clamp(1, 99);
    final rows = ((usableH + gap) / (cell + gap)).floor().clamp(1, 99);
    final perPage = cols * rows;

    final doc = pw.Document();
    for (int start = 0; start < tokens.length; start += perPage) {
      final slice = tokens.sublist(
          start,
          (start + perPage) > tokens.length ? tokens.length : start + perPage);
      doc.addPage(
        pw.Page(
          pageFormat: pf,
          margin: pw.EdgeInsets.all(margin),
          theme: pw.ThemeData.withFont(base: base, bold: bold),
          build: (ctx) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  // رموز لاتينية مثل — و · و # غير موجودة في خط العربية المضمَّن
                  // فتظهر مربّعات؛ نستخدم نصاً عربياً ومسافات موجودة في الخط.
                  'رموز العنوان الوطني   دفعة ${_shortId(b.batchId)}'
                  '${b.note.isNotEmpty ? '   ${b.note}' : ''}',
                  style: pw.TextStyle(font: bold, fontSize: 11),
                ),
                pw.SizedBox(height: 6),
                pw.Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final t in slice)
                      pw.SizedBox(
                        width: cell,
                        height: cell,
                        child: buildStickerCell(
                          payload: t.payload,
                          phone: phone,
                          font: base,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return doc;
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
              tooltip: 'هاتف الطباعة',
              onPressed: _editContactPhone,
              icon: const Icon(Icons.phone_rounded, color: Colors.white),
            ),
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
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed:
                    b.count > 0 ? () => _runPrint(b, preview: true) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4)),
                  minimumSize: const Size(118, 36),
                ),
                icon: const Icon(Icons.visibility_rounded, size: 18),
                label: Text('معاينة / PDF',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed:
                    b.count > 0 ? () => _runPrint(b, preview: false) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.4)),
                  minimumSize: const Size(118, 36),
                ),
                icon: const Icon(Icons.print_rounded, size: 18),
                label: Text('طباعة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: b.count > 0 ? () => _openTokens(b) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.successColor,
                  side: BorderSide(
                      color: AppTheme.successColor.withValues(alpha: 0.4)),
                  minimumSize: const Size(118, 36),
                ),
                icon: const Icon(Icons.fact_check_rounded, size: 18),
                label: Text('الحالات',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
            ],
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
  final _phone = TextEditingController();
  String? _err;

  @override
  void initState() {
    super.initState();
    // تحميل رقم الهاتف المحفوظ محلياً (يُطبع تحت كل رمز).
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      final saved = p.getString(kPropertyQrContactPhoneKey) ?? '';
      if (saved.isNotEmpty) _phone.text = saved;
    });
  }

  @override
  void dispose() {
    _count.dispose();
    _note.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final n = int.tryParse(_count.text.trim());
    if (n == null || n <= 0) {
      setState(() => _err = 'أدخل عدداً صحيحاً أكبر من صفر');
      return;
    }
    if (n > widget.maxCount) {
      setState(() => _err = 'الحدّ الأقصى ${widget.maxCount} رمزاً');
      return;
    }
    // حفظ رقم الهاتف محلياً ليُطبع تحت الرموز ويُعاد استخدامه لاحقاً.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPropertyQrContactPhoneKey, _phone.text.trim());
    if (!mounted) return;
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
              controller: _phone,
              keyboardType: TextInputType.phone,
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: 'رقم الهاتف (يُطبع تحت كل رمز — يُحفظ محلياً)',
                labelStyle: GoogleFonts.cairo(),
                prefixIcon: const Icon(Icons.phone_rounded,
                    color: AppTheme.primaryColor),
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

// ─────────────────────── شاشة معاينة PDF داخل التطبيق ───────────────────────

/// معاينة الرموز كـ PDF داخل التطبيق — مع أزرار مدمجة للطباعة والحفظ/المشاركة
/// (فتح كملف PDF) من شريط PdfPreview.
class _PdfPreviewScreen extends StatelessWidget {
  final pw.Document doc;
  final String title;
  const _PdfPreviewScreen({required this.doc, required this.title});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          title: Text('معاينة $title',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        body: PdfPreview(
          build: (format) => doc.save(),
          canChangePageFormat: false,
          canChangeOrientation: false,
          canDebug: false,
          pdfFileName: 'sadara-qr-$title.pdf',
          loadingWidget: const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }
}

// ──────────────────── شاشة حالات رموز الدفعة (تفصيلية) ────────────────────

/// تعرض رموز الدفعة ضمن نطاق تسلسل، كلٌّ بحالته (مستخدَم/فارغ) والعقار المرتبط
/// (رقم NPN) إن وُجد — مع فلترة بالحالة وبحث سريع. للمتابعة فقط (قراءة).
class _BatchTokensScreen extends StatefulWidget {
  final PropertyQrBatch batch;
  const _BatchTokensScreen({required this.batch});

  @override
  State<_BatchTokensScreen> createState() => _BatchTokensScreenState();
}

enum _TokFilter { all, used, unused }

class _BatchTokensScreenState extends State<_BatchTokensScreen> {
  final _api = PropertyApiService.instance;

  // حدّ النطاق لكل تحميل (الدفعات قد تصل 20000 — نحمّل على دفعات).
  static const int _pageSpan = 500;

  late final _from = TextEditingController(text: '1');
  late final _to = TextEditingController(
      text: '${widget.batch.count < _pageSpan ? widget.batch.count : _pageSpan}');

  List<PropertyQrToken> _tokens = const [];
  _TokFilter _filter = _TokFilter.all;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final from = int.tryParse(_from.text.trim()) ?? 1;
    final to = int.tryParse(_to.text.trim()) ?? from;
    if (to < from) {
      setState(() => _error = 'نطاق غير صحيح');
      return;
    }
    if (to - from + 1 > _pageSpan * 4) {
      setState(() =>
          _error = 'النطاق كبير — حمّل حتى ${_pageSpan * 4} رمزاً في المرة');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.getBatchTokens(widget.batch.batchId,
          fromSerial: from, toSerial: to);
      if (!mounted) return;
      setState(() {
        _tokens = r;
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

  List<PropertyQrToken> get _filtered {
    switch (_filter) {
      case _TokFilter.used:
        return _tokens.where((t) => t.isUsed).toList();
      case _TokFilter.unused:
        return _tokens.where((t) => !t.isUsed).toList();
      case _TokFilter.all:
        return _tokens;
    }
  }

  @override
  Widget build(BuildContext context) {
    final usedCount = _tokens.where((t) => t.isUsed).length;
    final shown = _filtered;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          title: Text('حالات رموز الدفعة',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _from,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            labelText: 'من تسلسل',
                            labelStyle: GoogleFonts.cairo(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _to,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.w700),
                          decoration: InputDecoration(
                            labelText: 'إلى تسلسل',
                            labelStyle: GoogleFonts.cairo(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: _loading ? null : _load,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('تحميل',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _filterChip('الكل (${_tokens.length})', _TokFilter.all),
                      const SizedBox(width: 8),
                      _filterChip('مستخدَم ($usedCount)', _TokFilter.used),
                      const SizedBox(width: 8),
                      _filterChip('فارغ (${_tokens.length - usedCount})',
                          _TokFilter.unused),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(_error!,
                    style: GoogleFonts.cairo(
                        color: AppTheme.errorColor,
                        fontWeight: FontWeight.w700)),
              ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                      ? Center(
                          child: Text('لا رموز ضمن النطاق/الفلتر',
                              style: GoogleFonts.cairo(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) => _tokenTile(shown[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, _TokFilter f) {
    final sel = _filter == f;
    return ChoiceChip(
      label: Text(label,
          style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: sel ? Colors.white : AppTheme.primaryColor)),
      selected: sel,
      selectedColor: AppTheme.primaryColor,
      onSelected: (_) => setState(() => _filter = f),
    );
  }

  Widget _tokenTile(PropertyQrToken t) {
    final used = t.isUsed;
    final c = used ? AppTheme.successColor : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(used ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('تسلسل ${t.serial}',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  used
                      ? (t.npn.isNotEmpty ? 'مستخدَم — عقار ${t.npn}' : 'مستخدَم')
                      : 'فارغ (غير مستخدَم)',
                  style: GoogleFonts.cairo(
                      color: c, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'نسخ الرمز',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: t.qrToken));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('نُسخ الرمز',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
