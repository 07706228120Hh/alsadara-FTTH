/// لصاقة العنوان الوطني للعقار — QR + NPN + Iq-Pin + عنوان، بصيغة PDF (A6).
///
/// تُطبَع/تُصدَّر عبر حزمة `printing` (ويندوز/هاتف). الأرقام (NPN/IQ-Pin) لاتينية
/// فتظهر دائماً؛ النصّ العربي يُحمَّل عبر خطوط Google (NotoSansArabic) كما في
/// بقية مصدّرات PDF في التطبيق. نمط مطابق للصاقة الساس.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/property.dart';

/// يفتح معاينة طباعة للصاقة العنوان الوطني للعقار (مقاس A6).
Future<void> printPropertyLabel(Property p) async {
  final base = await PdfGoogleFonts.notoSansArabicRegular();
  final bold = await PdfGoogleFonts.notoSansArabicBold();

  final payload = p.qrPayload.isNotEmpty
      ? p.qrPayload
      : (p.qrToken.isNotEmpty ? 'SADARA|P:${p.qrToken}' : '');

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a6,
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      build: (ctx) => pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text('العنوان الوطني',
                style: pw.TextStyle(font: bold, fontSize: 16)),
            pw.SizedBox(height: 8),
            if (payload.isNotEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1)),
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: payload,
                  width: 150,
                  height: 150,
                ),
              ),
            pw.SizedBox(height: 10),
            // رقم العقار الوطني (لاتيني — يظهر دائماً)
            pw.Text(p.npnDisplay.isEmpty ? '#${p.id}' : p.npnDisplay,
                style: pw.TextStyle(font: bold, fontSize: 18)),
            if (p.iqPinDisplay.isNotEmpty)
              pw.Text('IQ-Pin: ${p.iqPinDisplay}',
                  style: pw.TextStyle(font: base, fontSize: 11)),
            pw.SizedBox(height: 6),
            if (p.shortAddress.isNotEmpty)
              pw.Text(p.shortAddress,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: base, fontSize: 10)),
          ],
        ),
      ),
    ),
  );

  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}
