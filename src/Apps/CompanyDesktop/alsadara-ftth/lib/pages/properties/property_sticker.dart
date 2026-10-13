/// الشكل العام الموحّد لملصق العقار (العنوان الوطني): رمز QR + رقم الهاتف وحده
/// أسفله فقط — يُعتمد في كل الطباعات (دفعات QR + الملصق المفرد) وأي تطوير لاحق.
///
/// توحيد المصدر هنا يمنع تباعد التصميم بين الشاشات.
library;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// مفتاح حفظ رقم هاتف الطباعة محلياً (يظهر أسفل كل ملصق).
const String kPropertyQrContactPhoneKey = 'property_qr_contact_phone';

/// يبني خلية الملصق الموحّدة: QR + رقم الهاتف وحده (بلا نصوص إضافية).
/// تملأ المساحة المتاحة لها (تُستخدم داخل شبكة 5سم أو صفحة مفردة).
pw.Widget buildStickerCell({
  required String payload,
  required String phone,
  required pw.Font font,
  double phoneFontSize = 9,
}) {
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
            data: payload,
            drawText: false,
          ),
        ),
        if (phone.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(phone, style: pw.TextStyle(font: font, fontSize: phoneFontSize)),
        ],
      ],
    ),
  );
}

/// يقرأ رقم هاتف الطباعة المحفوظ محلياً (قد يكون فارغاً).
Future<String> loadStickerPhone() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getString(kPropertyQrContactPhoneKey) ?? '').trim();
}

/// يطبع ملصق عقار واحد بالشكل العام الموحّد (QR + هاتف) على صفحة A6.
Future<void> printSinglePropertySticker(String payload) async {
  // Cairo يغطّي العربية واللاتينية معاً (بلا مربّعات).
  final font = await PdfGoogleFonts.cairoRegular();
  final phone = await loadStickerPhone();
  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a6,
      margin: const pw.EdgeInsets.all(14),
      build: (ctx) => buildStickerCell(
        payload: payload,
        phone: phone,
        font: font,
        phoneFontSize: 16,
      ),
    ),
  );
  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}
