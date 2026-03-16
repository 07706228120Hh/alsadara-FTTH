import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'escpos_cutter.dart';
import 'printer_settings_storage.dart';
import 'receipt_pdf_builder.dart';
import 'receipt_template_storage.dart';

enum PrinterType { bluetooth, defaultPrinter }

/// نموذج إعدادات قالب الطباعة
class PrintTemplate {
  final String companyName;
  final String companySubtitle;
  final String footerMessage;
  final String contactInfo;
  final bool showCustomerInfo;
  final bool showServiceDetails;
  final bool showPaymentDetails;
  final bool showAdditionalInfo;
  final bool showContactInfo;
  final double fontSize;
  final bool boldHeaders;

  PrintTemplate({
    required this.companyName,
    required this.companySubtitle,
    required this.footerMessage,
    required this.contactInfo,
    required this.showCustomerInfo,
    required this.showServiceDetails,
    required this.showPaymentDetails,
    required this.showAdditionalInfo,
    required this.showContactInfo,
    required this.fontSize,
    required this.boldHeaders,
  });
}

class ThermalPrinterService {
  static const String _tag = 'ThermalPrinterService';
  // العرض القابل للطباعة بالميليمتر
  static const double _paperWidthMm = 72;
  // تم إلغاء دعم طابعة البلوتوث. سيتم استخدام الطابعة الافتراضية دائماً.
  static PrinterType currentPrinterType = PrinterType.defaultPrinter;
  static pw.Font? _arabicFont;
  static pw.Font? _englishFont;

  // ============ Public API for ReceiptPdfBuilder ============
  static pw.Font? get arabicFont => _arabicFont;
  static pw.Font? get englishFont => _englishFont;
  static Future<void> ensureFontsLoaded() => _loadFonts();
  static pw.Widget buildMixedText(
    String text, {
    double fontSize = 12,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    PdfColor? color,
    pw.TextAlign textAlign = pw.TextAlign.right,
  }) =>
      _buildMixedText(text,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
          textAlign: textAlign);
  // =========================================================

  /// تحميل الخطوط (العربي والإنجليزي)
  static Future<void> _loadFonts() async {
    // تحميل الخط العربي
    if (_arabicFont == null) {
      try {
        try {
          final fontData =
              await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf');
          _arabicFont = pw.Font.ttf(fontData);
          debugPrint('$_tag: Custom Arabic font loaded successfully');
        } catch (e) {
          final fontData = await PdfGoogleFonts.notoSansArabicRegular();
          _arabicFont = fontData;
          debugPrint('$_tag: Google Fonts Arabic font loaded successfully');
        }
      } catch (e) {
        debugPrint('$_tag: Error loading Arabic font');
        _arabicFont = null;
      }
    }

    // تحميل خط إنجليزي يدعم الرموز والأرقام
    if (_englishFont == null) {
      try {
        final fontData = await PdfGoogleFonts.notoSansRegular();
        _englishFont = fontData;
        debugPrint('$_tag: English font loaded successfully');
      } catch (e) {
        debugPrint('$_tag: Error loading English font');
        _englishFont = null;
      }
    }
  }

  /// تحميل الخط العربي (للتوافق مع الكود القديم)
  static Future<void> _loadArabicFont() async {
    await _loadFonts();
  }

  /// إنشاء نص ذكي يدعم العربية والإنجليزية معاً - محسّن
  static pw.Widget _buildMixedText(
    String text, {
    double fontSize = 12,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    PdfColor? color,
    pw.TextAlign textAlign = pw.TextAlign.right,
  }) {
    // تنظيف النص
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return pw.Text('');
    }

    // تحليل محتوى النص
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(cleanText);
    final hasEnglish = RegExp(r'[a-zA-Z]').hasMatch(cleanText);
    final hasNumbers = RegExp(r'[0-9]').hasMatch(cleanText);
    final hasSymbols =
        RegExp(r'[/:.\-_@#$%^&*()+=<>?$£€¥]').hasMatch(cleanText);

    // تحديد الخط المناسب
    pw.Font? selectedFont;
    pw.TextDirection direction;

    if (hasArabic && !hasEnglish && !hasNumbers && !hasSymbols) {
      // نص عربي خالص - استخدم الخط العربي
      selectedFont = _arabicFont;
      direction = pw.TextDirection.rtl;
    } else if (!hasArabic && (hasEnglish || hasNumbers || hasSymbols)) {
      // نص إنجليزي أو أرقام أو رموز - استخدم الخط الإنجليزي
      selectedFont = _englishFont;
      direction = pw.TextDirection.ltr;
    } else if (hasArabic && (hasEnglish || hasNumbers || hasSymbols)) {
      // نص مختلط - نحتاج لحل خاص
      return _buildMixedTextComplex(
          cleanText, fontSize, fontWeight, color, textAlign);
    } else {
      // افتراضي
      selectedFont = _englishFont ?? _arabicFont;
      direction = hasArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    }

    return pw.Text(
      cleanText,
      style: pw.TextStyle(
        font: selectedFont,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
      textAlign: textAlign,
      textDirection: direction,
    );
  }

  /// إنشاء نص مختلط معقد يحتوي على عربي وإنجليزي/رموز
  static pw.Widget _buildMixedTextComplex(
    String text,
    double fontSize,
    pw.FontWeight fontWeight,
    PdfColor? color,
    pw.TextAlign textAlign,
  ) {
    // تقسيم النص إلى أجزاء عربية وإنجليزية
    final parts = <pw.InlineSpan>[];
    final words = text.split(' ');

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(word);

      if (hasArabic) {
        // كلمة عربية
        parts.add(
          pw.TextSpan(
            text: word,
            style: pw.TextStyle(
              font: _arabicFont,
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
            ),
          ),
        );
      } else {
        // كلمة إنجليزية أو رقم أو رمز
        parts.add(
          pw.TextSpan(
            text: word,
            style: pw.TextStyle(
              font: _englishFont,
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: color,
            ),
          ),
        );
      }

      // إضافة مسافة بين الكلمات (ما عدا الكلمة الأخيرة)
      if (i < words.length - 1) {
        parts.add(
          pw.TextSpan(
            text: ' ',
            style: pw.TextStyle(
              font: _englishFont ?? _arabicFont,
              fontSize: fontSize,
            ),
          ),
        );
      }
    }

    return pw.RichText(
      text: pw.TextSpan(children: parts),
      textAlign: textAlign,
      textDirection: pw.TextDirection.rtl,
    );
  }

  /// إنشاء نص عربي مع دعم الخط
  static pw.Widget _buildArabicText(
    String text, {
    double fontSize = 12,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    PdfColor? color,
    pw.TextAlign textAlign = pw.TextAlign.right,
  }) {
    // توجيه الطلب إلى _buildMixedText لضمان الاتساق
    return _buildMixedText(
      text,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      textAlign: textAlign,
    );
  }

  /// طباعة وصل تجديد الاشتراك
  static Future<bool> printSubscriptionReceipt({
    required String operationType,
    required String selectedPlan,
    required String selectedCommitmentPeriod,
    required String totalPrice,
    required String currency,
    required String selectedPaymentMethod,
    required String endDate,
    required String customerName,
    required String customerPhone,
    String? customerAddress,
    bool isNewSubscription = false,
  }) async {
    try {
      // تحميل الخط العربي أولاً
      await _loadArabicFont();
      // دائماً الطباعة على الطابعة الافتراضية
      return await _printToDefaultPrinter(
        operationType: operationType,
        selectedPlan: selectedPlan,
        selectedCommitmentPeriod: selectedCommitmentPeriod,
        totalPrice: totalPrice,
        currency: currency,
        selectedPaymentMethod: selectedPaymentMethod,
        endDate: endDate,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        isNewSubscription: isNewSubscription,
      );
    } catch (e) {
      debugPrint('$_tag: Error printing receipt');
      return false;
    }
  }

  /// اختبار الطباعة
  static Future<bool> testPrint() async {
    try {
      // تحميل الخط العربي أولاً
      await _loadArabicFont();
      // الطباعة على الطابعة الافتراضية فقط
      return await _testPrintDefaultPrinter();
    } catch (e) {
      debugPrint('$_tag: Error in test print');
      return false;
    }
  }

  /// اختبار الطباعة على الطابعة الافتراضية
  static Future<bool> _testPrintDefaultPrinter() async {
    try {
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس اختبار الطباعة
                pw.Center(
                  child: _buildArabicText(
                    'اختبار الطباعة',
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildArabicText(
                    'شركة FTTH للإنترنت',
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 3),

                // اختبار الخطوط والأحجام
                _buildArabicText(
                  'اختبار الخطوط والأحجام:',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildArabicText('خط صغير - حجم 8', fontSize: 8),
                _buildArabicText('خط صغير - حجم 10', fontSize: 10),
                _buildArabicText('خط متوسط - حجم 12', fontSize: 12),
                _buildArabicText('خط كبير - حجم 16',
                    fontSize: 16, fontWeight: pw.FontWeight.bold),
                _buildArabicText('خط كبير جداً - حجم 20',
                    fontSize: 20, fontWeight: pw.FontWeight.bold),
                pw.SizedBox(height: 3), // اختبار النصوص العربية والإنجليزية
                _buildArabicText(
                  'اختبار اللغات:',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildArabicText('النص العربي: مرحباً بكم في FTTH',
                    fontSize: 10),
                pw.Text('English Text: Welcome to FTTH',
                    style: pw.TextStyle(fontSize: 10)),
                _buildArabicText('أرقام: ١٢٣٤٥٦٧٨٩٠', fontSize: 10),
                pw.Text('Numbers: 1234567890',
                    style: pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 3),

                // اختبار التوزيع والجداول
                _buildArabicText(
                  'اختبار التوزيع:',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildPdfRowArabic('اليسار:', 'اليمين'),
                _buildPdfRowArabic('المفتاح:', 'القيمة'),
                _buildPdfRowArabic('السعر:', '1000 دينار'),
                pw.SizedBox(height: 3),

                // معلومات الاختبار
                _buildArabicText(
                  'معلومات الاختبار:',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildPdfRowMixed('تاريخ الاختبار:', _getCurrentDate()),
                _buildPdfRowMixed('وقت الاختبار:', _getCurrentTime()),
                _buildPdfRowArabic('نوع الطابعة:', 'الطابعة الافتراضية'),
                _buildPdfRowMixed('حجم الورق:', '72mm × 200mm'),
                pw.SizedBox(height: 4),

                pw.Center(
                  child: _buildArabicText(
                    'تم اختبار الطباعة بنجاح!',
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'اختبار_الطباعة_${DateTime.now().millisecondsSinceEpoch}',
      );

      debugPrint('$_tag: Default printer test completed successfully');
      return true;
    } catch (e) {
      debugPrint('$_tag: Error in default printer test');
      return false;
    }
  }

  /// طباعة على الطابعة الافتراضية باستخدام PDF
  static Future<bool> _printToDefaultPrinter({
    required String operationType,
    required String selectedPlan,
    required String selectedCommitmentPeriod,
    required String totalPrice,
    required String currency,
    required String selectedPaymentMethod,
    required String endDate,
    required String customerName,
    required String customerPhone,
    String? customerAddress,
    bool isNewSubscription = false,
  }) async {
    try {
      // إنشاء مستند PDF للطباعة
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الوصل
                pw.Center(
                  child: _buildArabicText(
                    'شركة FTTH للإنترنت',
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildArabicText(
                    'للإنترنت عالي السرعة',
                    fontSize: 12,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.Center(
                  child: _buildArabicText(
                    operationType,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 3),

                // بيانات العميل
                _buildArabicText(
                  'بيانات العميل',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildPdfRowArabic('الاسم الكامل:', customerName),
                _buildPdfRowArabic('رقم الهاتف:', customerPhone),
                if (customerAddress != null && customerAddress.isNotEmpty)
                  _buildPdfRowArabic('العنوان:', customerAddress),
                pw.SizedBox(height: 3), // تفاصيل الخدمة
                _buildArabicText(
                  'تفاصيل الخدمة',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildPdfRowArabic('نوع الخدمة:', selectedPlan),
                _buildPdfRowArabic(
                    'مدة الالتزام:', '$selectedCommitmentPeriod شهر'),
                pw.SizedBox(height: 3),

                // تفاصيل الدفع
                _buildArabicText(
                  'تفاصيل الدفع',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildArabicText('المبلغ الإجمالي:',
                        fontSize: 12, fontWeight: pw.FontWeight.bold),
                    _buildArabicText('$totalPrice $currency',
                        fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ],
                ),
                _buildPdfRowArabic('طريقة الدفع:', selectedPaymentMethod),
                _buildPdfRowArabic('تاريخ الانتهاء:', endDate),
                pw.SizedBox(height: 3),
                if (isNewSubscription) ...[
                  _buildArabicText(
                    'ملاحظة هامة:',
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  _buildArabicText(
                    'تم تحويل الاشتراك من تجريبي إلى مدفوع',
                    fontSize: 10,
                  ),
                  pw.SizedBox(height: 3),
                ],

                // معلومات إضافية
                _buildArabicText(
                  'معلومات إضافية',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildPdfRowMixed('تاريخ الإصدار:', _getCurrentDate()),
                _buildPdfRowMixed('وقت الإصدار:', _getCurrentTime()),
                _buildPdfRowMixed('رقم المعاملة:',
                    'TXN${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'),
                pw.SizedBox(height: 4), // رسالة شكر ومعلومات التواصل
                pw.Center(
                  child: _buildArabicText(
                    'شكراً لاختياركم خدماتنا',
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 3),
                _buildArabicText(
                  'معلومات التواصل',
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildArabicText('خدمة العملاء: 07801234567', fontSize: 10),
                _buildArabicText('الدعم الفني: 07809876543', fontSize: 10),
                _buildArabicText('الموقع: www.ftth-iq.com', fontSize: 10),
                pw.SizedBox(height: 3),
                pw.Center(
                  child: _buildArabicText(
                    'نتمنى لكم تجربة ممتعة مع خدماتنا',
                    fontSize: 10,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      ); // عرض نافذة الطباعة بدلاً من الطباعة المباشرة
      debugPrint('$_tag: Opening print dialog instead of direct printing...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          debugPrint('$_tag: Generating PDF for print dialog...');
          return pdf.save();
        },
        name: 'وصل_${operationType}_${DateTime.now().millisecondsSinceEpoch}',
      );
      debugPrint('$_tag: Print dialog opened successfully');

      debugPrint('$_tag: PDF receipt printed successfully');

      // إرسال أمر القطع (ESC/POS) بعد الطباعة إذا كان مفعلاً
      try {
        final settings = await PrinterSettingsStorage.loadCutSettings();
        if (settings.enabled && settings.host.isNotEmpty) {
          if (settings.delayMs > 0) {
            await Future<void>.delayed(
                Duration(milliseconds: settings.delayMs));
          }
          await EscposCutterService.sendCut(
            host: settings.host,
            port: settings.port,
            feedLines: settings.feedLines,
            partial: true,
          );
          debugPrint('$_tag: ESC/POS cut command sent');
        }
      } catch (e) {
        debugPrint('$_tag: Failed to send cut command');
      }
      return true;
    } catch (e) {
      debugPrint('$_tag: Error printing PDF receipt');
      return false;
    }
  }

  /// دالة مساعدة لإنشاء صف في PDF مع إبعاد العمود الأول
  static pw.Widget _buildPdfRowArabic(String label, String value) {
    return pw.Row(
      children: [
        // إضافة مسافة في بداية الصف لإبعاد العمود الأول عن الحافة
        pw.SizedBox(width: 4),
        pw.Expanded(
          flex: 3,
          child: _buildMixedText(
            label,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            textAlign: pw.TextAlign.right,
          ),
        ),
        pw.SizedBox(width: 0.2),
        pw.Expanded(
          flex: 2,
          child: _buildMixedText(
            value,
            fontSize: 10,
            textAlign: pw.TextAlign.left,
          ),
        ),
      ],
    );
  }

  /// إنشاء صف PDF مع دعم النص المختلط (عربي + إنجليزي) مع إبعاد العمود الأول
  static pw.Widget _buildPdfRowMixed(String label, String value,
      {double fontSize = 10}) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // إضافة مسافة في بداية الصف لإبعاد العمود الأول عن الحافة
          pw.SizedBox(width: 4),
          pw.Expanded(
            flex: 5,
            child: _buildMixedText(
              value,
              fontSize: fontSize,
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.SizedBox(width: 0.2),
          pw.Expanded(
            flex: 4,
            child: _buildMixedText(
              label,
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              textAlign: pw.TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  /// تحديد حجم الخط المناسب لعرض 72mm حسب طول النص
  static double _getOptimalFontSize(String text, double baseSize) {
    // قلل الأحجام قليلاً ومنعها من النزول تحت 7
    double size = baseSize;
    if (text.length <= 8) {
      size = baseSize;
    } else if (text.length <= 12)
      size = baseSize - 0.7;
    else if (text.length <= 16)
      size = baseSize - 1.2;
    else
      size = baseSize - 1.6;
    return size < 7.0 ? 7.0 : size;
  }

  /// تقصير النص حسب طوله لعرض 72mm
  static String _limitTextFor78mm(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// تحويل المليمتر إلى نقاط PDF
  static double _mm(double mm) => mm * PdfPageFormat.mm;

  /// دالة مساعدة للحصول على التاريخ الحالي
  static String _getCurrentDate() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
  }

  /// دالة مساعدة للحصول على الوقت الحالي
  static String _getCurrentTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  /// دالة لإنشاء صف بـ 4 أعمدة مع إبعاد العمود الأول عن بداية الصفحة
  static pw.Widget _buildPdfRow4Columns(
      String label1, String value1, String label2, String value2,
      {double fontSize = 10}) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        children: [
          // تقليل المسافة في بداية الصف (العمود الأول عن الحافة اليمنى)
          pw.SizedBox(width: 2),
          pw.Expanded(
            flex: 2,
            child: _buildMixedText(
              label1,
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: _buildMixedText(
              value1,
              fontSize: fontSize,
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Expanded(
            flex: 2,
            child: _buildMixedText(
              label2,
              fontSize: fontSize,
              fontWeight: pw.FontWeight.bold,
              textAlign: pw.TextAlign.right,
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: _buildMixedText(
              value2,
              fontSize: fontSize,
              textAlign: pw.TextAlign.right,
            ),
          ),
          // زيادة المسافة في نهاية الصف (العمود الرابع عن الحافة اليسرى)
          pw.SizedBox(width: 6),
        ],
      ),
    );
  }

  /// دالة محسنة لبناء صف بـ 4 أعمدة مع خيارات لعكس الأعمدة وتحسين الخدمة وإبعاد العمود الأول عن الحافة
  static pw.Widget _buildPdfRow4ColumnsOptimized(
      String label1, String value1, String label2, String value2,
      {double fontSize = 8.5,
      bool reverse = false,
      bool highlightService = false,
      double gapBeforeDivider = 0.8,
      double gapAfterDivider = 0.8,
      double leadingPaddingWidth = 3,
      double trailingPaddingWidth = 6,
      double gapLabel1ToDivider = 0.8,
      double gapDividerToValue2 = 0.8,
      bool labelBeforeValue = false,
      int value1Flex = 5,
      int label1Flex = 2,
      int value2Flex = 5,
      int label2Flex = 2}) {
    // تحسين القيم لعرض 72mm مع إعطاء أولوية للأسماء الثلاثية
    String optimizedValue1 = value1;
    String optimizedValue2 = value2;

    // للأسماء: إظهار الاسم الثلاثي كاملاً (أول 3 كلمات كحد أقصى) بدون اقتطاع حروف
    if (label1.contains('الاسم') || label1.contains('اسم')) {
      final words = value1
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      optimizedValue1 = (words.length > 3 ? words.take(3) : words).join(' ');
    } else {
      optimizedValue1 = _limitTextFor78mm(value1, 12);
    }
    if (label2.contains('الاسم') || label2.contains('اسم')) {
      final words = value2
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      optimizedValue2 = (words.length > 3 ? words.take(3) : words).join(' ');
    } else {
      optimizedValue2 = _limitTextFor78mm(value2, 12);
    } // تقليل مسافة العمود الأول عن الحافة اليمنى
    final leadingPadding = pw.SizedBox(width: leadingPaddingWidth);
    // زيادة مسافة العمود الرابع عن الحافة اليسرى
    final trailingPadding = pw.SizedBox(width: trailingPaddingWidth);
    final List<pw.Widget> rowChildren = reverse
        ? [
            leadingPadding,
            ...(labelBeforeValue
                ? [
                    pw.Expanded(
                      flex: label2Flex,
                      child: _buildMixedText(
                        label2,
                        fontSize: _getOptimalFontSize(label2, fontSize - 1),
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(width: gapBeforeDivider),
                    pw.Expanded(
                      flex: value2Flex,
                      child: highlightService
                          ? pw.Container(
                              padding: pw.EdgeInsets.symmetric(
                                  vertical: 1, horizontal: 2),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.amber100,
                                borderRadius: pw.BorderRadius.circular(2),
                              ),
                              child: _buildMixedText(
                                optimizedValue2,
                                fontSize: _getOptimalFontSize(
                                    optimizedValue2, fontSize),
                                fontWeight: pw.FontWeight.bold,
                                textAlign: pw.TextAlign.left,
                              ),
                            )
                          : _buildMixedText(
                              optimizedValue2,
                              fontSize: _getOptimalFontSize(
                                  optimizedValue2, fontSize),
                              textAlign: pw.TextAlign.left,
                            ),
                    ),
                  ]
                : [
                    pw.Expanded(
                      flex: value2Flex,
                      child: highlightService
                          ? pw.Container(
                              padding: pw.EdgeInsets.symmetric(
                                  vertical: 1, horizontal: 2),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.amber100,
                                borderRadius: pw.BorderRadius.circular(2),
                              ),
                              child: _buildMixedText(
                                optimizedValue2,
                                fontSize: _getOptimalFontSize(
                                    optimizedValue2, fontSize),
                                fontWeight: pw.FontWeight.bold,
                                textAlign: pw.TextAlign.left,
                              ),
                            )
                          : _buildMixedText(
                              optimizedValue2,
                              fontSize: _getOptimalFontSize(
                                  optimizedValue2, fontSize),
                              textAlign: pw.TextAlign.left,
                            ),
                    ),
                    pw.SizedBox(width: gapBeforeDivider),
                    pw.Expanded(
                      flex: label2Flex,
                      child: _buildMixedText(
                        label2,
                        fontSize: _getOptimalFontSize(label2, fontSize - 1),
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ]),
            // إبعاد العمود الثاني عن خط الوسط قبل الفاصل
            pw.SizedBox(width: gapLabel1ToDivider),
            pw.Container(
              width: 0.6,
              height: fontSize + 2,
              color: PdfColors.grey800,
              margin: pw.EdgeInsets.symmetric(horizontal: 0.2),
            ),
            // مسافة بين الفاصل وبداية العمود الثالث
            pw.SizedBox(width: gapDividerToValue2),
            ...(labelBeforeValue
                ? [
                    pw.Expanded(
                      flex: label1Flex,
                      child: _buildMixedText(
                        label1,
                        fontSize: _getOptimalFontSize(label1, fontSize - 1),
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(width: gapAfterDivider),
                    pw.Expanded(
                      flex: value1Flex,
                      child: _buildMixedText(
                        optimizedValue1,
                        fontSize:
                            _getOptimalFontSize(optimizedValue1, fontSize),
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                  ]
                : [
                    pw.Expanded(
                      flex: value1Flex,
                      child: _buildMixedText(
                        optimizedValue1,
                        fontSize:
                            _getOptimalFontSize(optimizedValue1, fontSize),
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                    pw.SizedBox(width: gapAfterDivider),
                    pw.Expanded(
                      flex: label1Flex,
                      child: _buildMixedText(
                        label1,
                        fontSize: _getOptimalFontSize(label1, fontSize - 1),
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ]),
            // استخدام المسافة المحسنة في نهاية الصف
            trailingPadding,
          ]
        : [
            leadingPadding,
            ...(labelBeforeValue
                ? [
                    pw.Expanded(
                      flex: label1Flex,
                      child: _buildMixedText(
                        label1,
                        fontSize: _getOptimalFontSize(label1, fontSize - 1),
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                    pw.SizedBox(width: gapBeforeDivider),
                    pw.Expanded(
                      flex: value1Flex,
                      child: _buildMixedText(
                        optimizedValue1,
                        fontSize:
                            _getOptimalFontSize(optimizedValue1, fontSize),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ]
                : [
                    pw.Expanded(
                      flex: value1Flex,
                      child: _buildMixedText(
                        optimizedValue1,
                        fontSize:
                            _getOptimalFontSize(optimizedValue1, fontSize),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(width: gapBeforeDivider),
                    pw.Expanded(
                      flex: label1Flex,
                      child: _buildMixedText(
                        label1,
                        fontSize: _getOptimalFontSize(label1, fontSize - 1),
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                  ]),
            // مسافة بين العمود الثاني وخط الوسط
            pw.SizedBox(width: gapLabel1ToDivider),
            pw.Container(
              width: 0.6,
              height: fontSize + 2,
              color: PdfColors.grey800,
              margin: pw.EdgeInsets.symmetric(horizontal: 0.2),
            ),
            // مسافة بين الفاصل وبداية العمود الثالث
            pw.SizedBox(width: gapDividerToValue2),
            ...(labelBeforeValue
                ? [
                    pw.Expanded(
                      flex: label2Flex,
                      child: _buildMixedText(
                        label2,
                        fontSize: _getOptimalFontSize(label2, fontSize - 1),
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                    pw.SizedBox(width: gapAfterDivider),
                    pw.Expanded(
                      flex: value2Flex,
                      child: highlightService
                          ? pw.Container(
                              padding: pw.EdgeInsets.symmetric(
                                  vertical: 1, horizontal: 2),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.amber100,
                                borderRadius: pw.BorderRadius.circular(2),
                              ),
                              child: _buildMixedText(
                                optimizedValue2,
                                fontSize: _getOptimalFontSize(
                                    optimizedValue2, fontSize),
                                fontWeight: pw.FontWeight.bold,
                                textAlign: pw.TextAlign.right,
                              ),
                            )
                          : _buildMixedText(
                              optimizedValue2,
                              fontSize: _getOptimalFontSize(
                                  optimizedValue2, fontSize),
                              textAlign: pw.TextAlign.right,
                            ),
                    ),
                  ]
                : [
                    pw.Expanded(
                      flex: value2Flex,
                      child: highlightService
                          ? pw.Container(
                              padding: pw.EdgeInsets.symmetric(
                                  vertical: 1, horizontal: 2),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.amber100,
                                borderRadius: pw.BorderRadius.circular(2),
                              ),
                              child: _buildMixedText(
                                optimizedValue2,
                                fontSize: _getOptimalFontSize(
                                    optimizedValue2, fontSize),
                                fontWeight: pw.FontWeight.bold,
                                textAlign: pw.TextAlign.right,
                              ),
                            )
                          : _buildMixedText(
                              optimizedValue2,
                              fontSize: _getOptimalFontSize(
                                  optimizedValue2, fontSize),
                              textAlign: pw.TextAlign.right,
                            ),
                    ),
                    pw.SizedBox(width: gapAfterDivider),
                    pw.Expanded(
                      flex: label2Flex,
                      child: _buildMixedText(
                        label2,
                        fontSize: _getOptimalFontSize(label2, fontSize - 1),
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                  ]),
            // استخدام المسافة المحسنة في نهاية الصف
            trailingPadding,
          ];

    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(children: rowChildren),
    );
  }

  /// تحديد نوع الطابعة
  static void setPrinterType(PrinterType type) {
    // تجاهل اختيار البلوتوث، الإبقاء على الطابعة الافتراضية دائماً
    currentPrinterType = PrinterType.defaultPrinter;
    debugPrint('$_tag: Bluetooth printing disabled. Using default printer');
  }

  /// الحصول على نوع الطابعة الحالي
  static PrinterType getCurrentPrinterType() {
    // دائماً الطابعة الافتراضية
    return PrinterType.defaultPrinter;
  }

  // تمت إزالة جميع دوال البلوتوث (الاتصال، الأذونات، والأجهزة).

  /// فحص توفر طابعة على النظام (بدون طباعة)
  static Future<bool> hasAvailablePrinter() async {
    try {
      final printers = await Printing.listPrinters();
      if (printers.isEmpty) return false;
      // إذا وُجدت طابعة افتراضية نعتبرها متاحة، وإلا يكفي وجود أي طابعة
      final defaultPrinter = printers.firstWhere(
        (p) => p.isDefault,
        orElse: () => printers.first,
      );
      return defaultPrinter.isAvailable;
    } catch (e) {
      debugPrint('$_tag: Error checking printers availability');
      return false;
    }
  }

  /// اختبار بسيط للطباعة مع تشخيص المشاكل
  static Future<Map<String, String>> quickPrintTest() async {
    Map<String, String> results = {};

    try {
      // 1. فحص الطابعات المتوفرة
      debugPrint('$_tag: Checking available printers...');
      final printers = await Printing.listPrinters();
      results['printers_count'] = '${printers.length}';

      if (printers.isEmpty) {
        results['error'] = 'لا توجد طابعات متوفرة على النظام';
        return results;
      }

      // 2. اختيار الطابعة
      final defaultPrinter = printers.firstWhere(
        (printer) => printer.isDefault,
        orElse: () => printers.first,
      );
      results['selected_printer'] = defaultPrinter.name;
      results['printer_available'] = defaultPrinter.isAvailable.toString();

      // 3. إنشاء PDF اختبار بسيط
      debugPrint('$_tag: Creating test PDF...');
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'FTTH اختبار الطباعة',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 4),
                pw.Text('التاريخ: ${DateTime.now().toString().split('.')[0]}'),
                pw.Text('الطابعة: ${defaultPrinter.name}'),
                pw.SizedBox(height: 4),
                pw.Text('النص العربي: مرحبا بكم'),
                pw.Text('English text: Hello World'),
                pw.SizedBox(height: 4),
                pw.Text('--- انتهى الاختبار ---'),
              ],
            );
          },
        ),
      );

      final pdfBytes = await pdf.save();
      results['pdf_size'] = '${pdfBytes.length} bytes';

      // 4. محاولة الطباعة
      debugPrint('$_tag: Attempting to print...');
      await Printing.directPrintPdf(
        printer: defaultPrinter,
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );

      results['print_status'] = 'تم إرسال الطباعة بنجاح';
      results['success'] = 'true';

      debugPrint('$_tag: Print test completed successfully');
    } catch (e) {
      results['error'] = 'خطأ في الطباعة';
      results['success'] = 'false';
      debugPrint('$_tag: Print test failed');
    }

    return results;
  }

  /// عرض نتائج اختبار الطباعة في dialog
  static Future<void> showPrintTestDialog(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('جاري اختبار الطباعة...'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('يرجى الانتظار...')
          ],
        ),
      ),
    );

    final results = await quickPrintTest();

    Navigator.of(context).pop(); // إغلاق dialog التحميل

    // عرض النتائج
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          results['success'] == 'true' ? 'نجح الاختبار!' : 'فشل الاختبار',
          style: TextStyle(
            color: results['success'] == 'true' ? Colors.green : Colors.red,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (results['error'] != null) ...[
                Text('خطأ:',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.red)),
                Text(results['error']!),
                SizedBox(height: 8),
              ],
              Text('عدد الطابعات: ${results['printers_count'] ?? 'غير معروف'}'),
              if (results['selected_printer'] != null) ...[
                Text('الطابعة المحددة: ${results['selected_printer']}'),
                Text(
                    'متاحة: ${results['printer_available'] == 'true' ? 'نعم' : 'لا'}'),
              ],
              if (results['pdf_size'] != null)
                Text('حجم PDF: ${results['pdf_size']}'),
              if (results['print_status'] != null)
                Text('حالة الطباعة: ${results['print_status']}'),
              SizedBox(height: 16),
              if (results['success'] == 'true') ...[
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('✓ تم إرسال الوصل للطابعة بنجاح!',
                          style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('إذا لم تر الوصل المطبوع، تحقق من:',
                          style: TextStyle(fontSize: 12)),
                      Text('• تشغيل الطابعة', style: TextStyle(fontSize: 12)),
                      Text('• وجود ورق وحبر', style: TextStyle(fontSize: 12)),
                      Text('• إعدادات الطابعة', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('✗ فشل في الطباعة',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('الحلول المقترحة:', style: TextStyle(fontSize: 12)),
                      Text('• تأكد من تثبيت طابعة',
                          style: TextStyle(fontSize: 12)),
                      Text('• تأكد من تشغيل الطابعة',
                          style: TextStyle(fontSize: 12)),
                      Text('• أعد تشغيل التطبيق',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('موافق'),
          ),
          if (results['success'] != 'true')
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                showPrintTestDialog(context); // إعادة المحاولة
              },
              child: Text('إعادة المحاولة'),
            ),
        ],
      ),
    );
  }

  /// تشخيص مشاكل الطباعة
  static Future<Map<String, dynamic>> diagnosePrintingIssues() async {
    Map<String, dynamic> diagnostic = {
      'printerType': currentPrinterType.toString(),
      'arabicFontLoaded': _arabicFont != null,
      'availablePrinters': [],
      'errors': [],
      'recommendations': [],
    };

    try {
      // فحص الخط العربي
      await _loadArabicFont();
      diagnostic['arabicFontLoaded'] = _arabicFont != null;

      if (_arabicFont == null) {
        diagnostic['errors'].add('فشل تحميل الخط العربي');
        diagnostic['recommendations']
            .add('تأكد من وجود اتصال بالإنترنت لتحميل خطوط Google');
      }

      // فحص الطابعات المتاحة (الطابعة الافتراضية فقط)
      try {
        final printers = await Printing.listPrinters();
        diagnostic['availablePrinters'] = printers.map((p) => p.name).toList();

        if (printers.isEmpty) {
          diagnostic['errors'].add('لا توجد طابعات مثبتة على النظام');
          diagnostic['recommendations']
              .add('تأكد من تثبيت وتشغيل طابعة على النظام');
        } else {
          diagnostic['recommendations']
              .add('تم العثور على ${printers.length} طابعة');
        }
      } catch (e) {
        diagnostic['errors'].add('خطأ في جلب قائمة الطابعات');
        diagnostic['recommendations']
            .add('تحقق من صلاحيات التطبيق للوصول للطابعات');
      }

      // اختبار إنشاء PDF
      try {
        final testPdf = pw.Document();
        testPdf.addPage(
          pw.Page(
            build: (context) => _buildArabicText('اختبار بسيط', fontSize: 12),
          ),
        );
        final pdfBytes = await testPdf.save();
        diagnostic['pdfGeneration'] = 'نجح';
        diagnostic['pdfSize'] = '${pdfBytes.length} بايت';
      } catch (e) {
        diagnostic['errors'].add('خطأ في إنشاء PDF');
        diagnostic['pdfGeneration'] = 'فشل';
      }
    } catch (e) {
      diagnostic['errors'].add('خطأ عام في التشخيص');
    }

    return diagnostic;
  }

  /// طباعة الوصل مع إظهار نافذة الطباعة
  static Future<bool> printSubscriptionReceiptWithDialog({
    required String operationType,
    required String selectedPlan,
    required String selectedCommitmentPeriod,
    required String totalPrice,
    required String currency,
    required String selectedPaymentMethod,
    required String endDate,
    required String customerName,
    required String customerPhone,
    String? customerAddress,
    bool isNewSubscription = false,
  }) async {
    try {
      // تحميل الخط العربي أولاً
      await _loadArabicFont();

      // إنشاء مستند PDF
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الوصل
                pw.Center(
                  child: _buildArabicText(
                    'شركة FTTH للإنترنت',
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildArabicText(
                    'للإنترنت عالي السرعة',
                    fontSize: 12,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.Center(
                  child: _buildArabicText(
                    operationType,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 3),

                // بيانات العميل
                _buildArabicText(
                  'بيانات العميل',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildPdfRowArabic('الاسم الكامل:', customerName),
                _buildPdfRowArabic('رقم الهاتف:', customerPhone),
                if (customerAddress != null && customerAddress.isNotEmpty)
                  _buildPdfRowArabic('العنوان:', customerAddress),
                pw.SizedBox(height: 3), // تفاصيل الخدمة
                _buildArabicText(
                  'تفاصيل الخدمة',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildPdfRowArabic('نوع الخدمة:', selectedPlan),
                _buildPdfRowArabic(
                    'مدة الالتزام:', '$selectedCommitmentPeriod شهر'),
                pw.SizedBox(height: 3),

                // تفاصيل الدفع
                _buildArabicText(
                  'تفاصيل الدفع',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _buildArabicText('المبلغ الإجمالي:',
                        fontSize: 12, fontWeight: pw.FontWeight.bold),
                    _buildArabicText('$totalPrice $currency',
                        fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ],
                ),
                _buildPdfRowArabic('طريقة الدفع:', selectedPaymentMethod),
                _buildPdfRowArabic('تاريخ الانتهاء:', endDate),
                pw.SizedBox(height: 3),

                if (isNewSubscription) ...[
                  _buildArabicText(
                    'ملاحظة هامة:',
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  _buildArabicText(
                    'تم تحويل الاشتراك من تجريبي إلى مدفوع',
                    fontSize: 10,
                  ),
                  pw.SizedBox(height: 3),
                ],

                // معلومات إضافية
                _buildArabicText(
                  'معلومات إضافية',
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildPdfRowMixed('تاريخ الإصدار:', _getCurrentDate()),
                _buildPdfRowMixed('وقت الإصدار:', _getCurrentTime()),
                _buildPdfRowMixed('رقم المعاملة:',
                    'TXN${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}'),
                pw.SizedBox(height: 4), // رسالة شكر ومعلومات التواصل
                pw.Center(
                  child: _buildArabicText(
                    'شكراً لاختياركم خدماتنا',
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 3),
                _buildArabicText(
                  'معلومات التواصل',
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
                pw.Divider(thickness: 1),
                _buildArabicText('خدمة العملاء: 07801234567', fontSize: 10),
                _buildArabicText('الدعم الفني: 07809876543', fontSize: 10),
                _buildArabicText('الموقع: www.ftth-iq.com', fontSize: 10),
                pw.SizedBox(height: 3),
                pw.Center(
                  child: _buildArabicText(
                    'نتمنى لكم تجربة ممتعة مع خدماتنا',
                    fontSize: 10,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      );

      // عرض نافذة الطباعة
      debugPrint('$_tag: Opening print dialog...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          debugPrint('$_tag: Generating PDF for print dialog...');
          return pdf.save();
        },
        name: 'وصل_${operationType}_${DateTime.now().millisecondsSinceEpoch}',
      );

      debugPrint('$_tag: Print dialog opened successfully');
      return true;
    } catch (e) {
      debugPrint('$_tag: Error opening print dialog');
      return false;
    }
  }

  /// طباعة وصل مخصص بقالب قابل للتعديل
  static Future<bool> printCustomSubscriptionReceipt({
    required String operationType,
    required String selectedPlan,
    required String selectedCommitmentPeriod,
    required String totalPrice,
    required String currency,
    required String selectedPaymentMethod,
    required String endDate,
    required String customerName,
    required String customerPhone,
    String? customerAddress,
    bool isNewSubscription = false,
    PrintTemplate? customTemplate,
    required String activationDate,
    required String activationTime,
    String? fdtInfo,
    String? fatInfo,
    String? activatedBy,
    String? subscriptionNotes, // إضافة معامل الملاحظات
    int? copyNumber, // رقم النسخة المطبوعة (1 = أصلي، 2+ = نسخة مكررة)
    bool saveAsPdf = false, // حفظ كملف PDF بدلاً من الطباعة
  }) async {
    try {
      // تحميل الخط العربي أولاً
      await _loadArabicFont();

      // الطباعة على الطابعة الافتراضية فقط
      return await _printCustomToDefaultPrinter(
        operationType: operationType,
        selectedPlan: selectedPlan,
        selectedCommitmentPeriod: selectedCommitmentPeriod,
        totalPrice: totalPrice,
        currency: currency,
        selectedPaymentMethod: selectedPaymentMethod,
        endDate: endDate,
        customerName: customerName,
        customerPhone: customerPhone,
        customerAddress: customerAddress,
        isNewSubscription: isNewSubscription,
        customTemplate: customTemplate,
        activationDate: activationDate,
        activationTime: activationTime,
        fdtInfo: fdtInfo,
        fatInfo: fatInfo,
        activatedBy: activatedBy,
        subscriptionNotes: subscriptionNotes, // تمرير الملاحظات
        copyNumber: copyNumber,
        saveAsPdf: saveAsPdf,
      );
    } catch (e) {
      debugPrint('$_tag: Error printing custom receipt');
      return false;
    }
  }

  /// طباعة/حفظ وصل باستخدام نظام القالب الجديد (V2)
  static Future<bool> printFromReceiptTemplate({
    required Map<String, String> variableValues,
    Map<String, bool> conditions = const {},
    bool saveAsPdf = false,
  }) async {
    try {
      final template = await ReceiptTemplateStorageV2.loadTemplate();

      final builder = ReceiptPdfBuilder(
        template: template,
        variableValues: variableValues,
        conditions: conditions,
      );

      final pdfBytes = await builder.buildBytes();

      if (saveAsPdf) {
        debugPrint('$_tag: Saving V2 receipt as PDF file...');
        final customerName = variableValues['customerName'] ?? '';
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'حفظ الوصل كـ PDF',
          fileName:
              'وصل_${customerName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (result != null) {
          await File(result).writeAsBytes(pdfBytes);
          debugPrint('$_tag: V2 PDF saved to: $result');
        } else {
          debugPrint('$_tag: User cancelled PDF save');
          return false;
        }
      } else {
        debugPrint('$_tag: Printing V2 receipt...');
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => pdfBytes,
          name:
              'وصل_${variableValues['operationType'] ?? ''}_${DateTime.now().millisecondsSinceEpoch}',
        );
        debugPrint('$_tag: V2 receipt printed successfully');

        // أمر القطع بعد الطباعة
        try {
          final settings = await PrinterSettingsStorage.loadCutSettings();
          if (settings.enabled && settings.host.isNotEmpty) {
            if (settings.delayMs > 0) {
              await Future<void>.delayed(
                  Duration(milliseconds: settings.delayMs));
            }
            await EscposCutterService.sendCut(
              host: settings.host,
              port: settings.port,
              feedLines: settings.feedLines,
            );
          }
        } catch (cutErr) {
          debugPrint('$_tag: Cut command error (non-fatal): $cutErr');
        }
      }

      return true;
    } catch (e) {
      debugPrint('$_tag: Error printing V2 receipt');
      return false;
    }
  }

  /// طباعة مخصصة على الطابعة الافتراضية
  static Future<bool> _printCustomToDefaultPrinter({
    required String operationType,
    required String selectedPlan,
    required String selectedCommitmentPeriod,
    required String totalPrice,
    required String currency,
    required String selectedPaymentMethod,
    required String endDate,
    required String customerName,
    required String customerPhone,
    String? customerAddress,
    bool isNewSubscription = false,
    PrintTemplate? customTemplate,
    required String activationDate,
    required String activationTime,
    String? fdtInfo,
    String? fatInfo,
    String? activatedBy,
    String? subscriptionNotes, // إضافة معامل الملاحظات
    int? copyNumber, // رقم النسخة المطبوعة
    bool saveAsPdf = false, // حفظ كملف PDF بدلاً من الطباعة
  }) async {
    try {
      final pdf = pw.Document();
      final template = customTemplate ??
          PrintTemplate(
            companyName: 'شركة FTTH للإنترنت',
            companySubtitle: 'للإنترنت عالي السرعة',
            footerMessage: 'شكراً لاختياركم خدماتنا',
            contactInfo:
                'خدمة العملاء: 07801234567\nالدعم الفني: 07809876543\nالموقع: www.ftth-iq.com',
            showCustomerInfo: true,
            showServiceDetails: true,
            showPaymentDetails: true,
            showAdditionalInfo: true,
            showContactInfo: true,
            // تعديل الحجم الافتراضي للخط من 12 إلى 10 حسب التغيير المطلوب
            fontSize: 10.0,
            boldHeaders: true,
          );

      final receiptNumber = await getAndIncrementDailyReceiptNumber();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الوصل
                pw.Center(
                  child: _buildMixedText(
                    template.companyName,
                    fontSize: template.fontSize + 6,
                    fontWeight: template.boldHeaders
                        ? pw.FontWeight.bold
                        : pw.FontWeight.normal,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                if (template.companySubtitle.isNotEmpty) ...[
                  pw.Center(
                    child: _buildMixedText(
                      template.companySubtitle,
                      fontSize: template.fontSize,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],
                pw.Divider(thickness: 2),
                // عرض حالة العملية، وإذا كانت تجديداً ضع المبلغ بجانبها في نفس السطر
                if (operationType.contains('تجديد'))
                  pw.Center(
                    child: pw.Container(
                      padding:
                          pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: pw.BoxDecoration(
                        border:
                            pw.Border.all(color: PdfColors.black, width: 1.2),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          _buildMixedText(
                            operationType,
                            fontSize: template.fontSize + 3,
                            fontWeight: template.boldHeaders
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                            textAlign: pw.TextAlign.right,
                          ),
                          pw.Padding(
                            padding: pw.EdgeInsets.symmetric(horizontal: 6),
                            child: pw.Container(
                              width: 1,
                              height: template.fontSize + 10,
                              color: PdfColors.black,
                            ),
                          ),
                          _buildMixedText(
                            'المبلغ:',
                            fontSize: template.fontSize + 2,
                            fontWeight: template.boldHeaders
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                            textAlign: pw.TextAlign.left,
                          ),
                          pw.SizedBox(width: 3),
                          _buildMixedText(
                            totalPrice,
                            fontSize: template.fontSize + 2,
                            fontWeight: template.boldHeaders
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                            textAlign: pw.TextAlign.left,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  pw.Center(
                    child: _buildMixedText(
                      operationType,
                      fontSize: template.fontSize + 3,
                      fontWeight: template.boldHeaders
                          ? pw.FontWeight.bold
                          : pw.FontWeight.normal,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                pw.Divider(thickness: 2), pw.SizedBox(height: 5),

                // تعريف نمط الصندوق للصفوف
                // (يُستخدم لاحقاً لكل صف معلومات)
                // عرض رقم النسخة إذا كانت نسخة مكررة (2+)
                if (copyNumber != null && copyNumber > 1)
                  pw.Center(
                    child: pw.Container(
                      padding:
                          pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      margin: pw.EdgeInsets.only(bottom: 4),
                      decoration: pw.BoxDecoration(
                        border:
                            pw.Border.all(color: PdfColors.black, width: 1.5),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: _buildMixedText(
                        'نسخة $copyNumber',
                        fontSize: template.fontSize + 2,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ),

                // السطر الأول: المنشط والوصل داخل صندوق
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  margin: pw.EdgeInsets.only(bottom: 3),
                  child: _buildPdfRow4ColumnsOptimized(
                    'المنشط:',
                    activatedBy != null && activatedBy.isNotEmpty
                        ? (activatedBy.length > 8
                            ? '${activatedBy.substring(0, 8)}...'
                            : activatedBy)
                        : 'غير محدد',
                    'الوصل:',
                    receiptNumber.toString(),
                    fontSize: template.fontSize - 1.0,
                    gapBeforeDivider: _mm(10),
                    gapAfterDivider: _mm(1.4),
                    leadingPaddingWidth: _mm(0),
                    trailingPaddingWidth: _mm(1),
                    gapLabel1ToDivider: _mm(6.5),
                    gapDividerToValue2: _mm(0.3),
                    value1Flex: 4,
                    label1Flex: 3,
                    value2Flex: 4,
                    label2Flex: 3,
                  ),
                ),

                // السطر الثاني: الاسم والرقم (يظهر فقط إذا كان عرض معلومات العميل مفعلاً)
                if (template.showCustomerInfo)
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    padding:
                        pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    margin: pw.EdgeInsets.only(bottom: 3),
                    child: _buildPdfRow4ColumnsOptimized(
                      'الاسم:',
                      customerName,
                      'الرقم:',
                      customerPhone,
                      fontSize: template.fontSize - 0.5,
                      leadingPaddingWidth: _mm(0),
                      trailingPaddingWidth: _mm(2),
                      gapBeforeDivider: _mm(0.3),
                      gapAfterDivider: _mm(3.0),
                      gapLabel1ToDivider: _mm(1.5),
                      gapDividerToValue2: _mm(0.3),
                    ),
                  ),

                // السطر الثالث: الدفع والانتهاء (تابع لتفاصيل الدفع)
                if (template.showPaymentDetails)
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    padding:
                        pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    margin: pw.EdgeInsets.only(bottom: 3),
                    child: _buildPdfRow4ColumnsOptimized(
                      'الدفع:',
                      selectedPaymentMethod,
                      'الانتهاء:',
                      endDate.length > 10 ? endDate.substring(0, 10) : endDate,
                      fontSize: template.fontSize - 0.5,
                      leadingPaddingWidth: _mm(0),
                      trailingPaddingWidth: _mm(2),
                      gapBeforeDivider: _mm(0.3),
                      gapAfterDivider: _mm(3.0),
                      gapLabel1ToDivider: _mm(1.5),
                      gapDividerToValue2: _mm(0.3),
                    ),
                  ),

                // السطر الرابع: التفعيل والوقت
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  padding: pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  margin: pw.EdgeInsets.only(bottom: 3),
                  child: _buildPdfRow4ColumnsOptimized(
                    'التفعيل:',
                    activationDate,
                    'الوقت:',
                    activationTime,
                    fontSize: template.fontSize - 0.5,
                    leadingPaddingWidth: _mm(0),
                    trailingPaddingWidth: _mm(2),
                    gapBeforeDivider: _mm(0.3),
                    gapAfterDivider: _mm(3.0),
                    gapLabel1ToDivider: _mm(1.5),
                    gapDividerToValue2: _mm(0.3),
                    value1Flex: 4,
                    label1Flex: 3,
                  ),
                ),

                // السطر الخامس: FAT و FDT + سطر الخدمة والمدة (تابع لتفاصيل الخدمة)
                if (template.showServiceDetails) ...[
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    padding:
                        pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    margin: pw.EdgeInsets.only(bottom: 3),
                    child: _buildPdfRow4ColumnsOptimized(
                      ':FAT',
                      fatInfo != null && fatInfo.isNotEmpty
                          ? (fatInfo.length > 10
                              ? '${fatInfo.substring(0, 10)}...'
                              : fatInfo)
                          : 'غير محدد',
                      ':FDT',
                      fdtInfo != null && fdtInfo.isNotEmpty
                          ? (fdtInfo.length > 10
                              ? '${fdtInfo.substring(0, 10)}...'
                              : fdtInfo)
                          : 'غير محدد',
                      fontSize: template.fontSize - 0.5,
                      leadingPaddingWidth: _mm(0),
                      trailingPaddingWidth: _mm(2),
                      gapBeforeDivider: _mm(0.3),
                      gapAfterDivider: _mm(3.0),
                      gapLabel1ToDivider: _mm(1.5),
                      gapDividerToValue2: _mm(0.3),
                      labelBeforeValue: false,
                    ),
                  ),
                  pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.black, width: 0.8),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    padding:
                        pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    margin: pw.EdgeInsets.only(bottom: 3),
                    child: _buildPdfRow4ColumnsOptimized(
                      'الخدمة:',
                      selectedPlan,
                      'المدة:',
                      '$selectedCommitmentPeriod شهر',
                      fontSize: template.fontSize - 0.5,
                      leadingPaddingWidth: _mm(0),
                      trailingPaddingWidth: _mm(2),
                      gapBeforeDivider: _mm(0.3),
                      gapAfterDivider: _mm(1.5),
                      gapLabel1ToDivider: _mm(1.2),
                      gapDividerToValue2: _mm(0.3),
                      label1Flex: 3,
                      value1Flex: 4,
                      label2Flex: 3,
                      value2Flex: 4,
                    ),
                  ),

                  // إضافة صف الملاحظات داخل مربع
                  if (subscriptionNotes != null &&
                      subscriptionNotes.trim().isNotEmpty)
                    pw.Container(
                      decoration: pw.BoxDecoration(
                        border:
                            pw.Border.all(color: PdfColors.black, width: 0.8),
                        borderRadius: pw.BorderRadius.circular(3),
                      ),
                      padding:
                          pw.EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      margin: pw.EdgeInsets.only(bottom: 3),
                      child: pw.Center(
                        child: _buildMixedText(
                          subscriptionNotes.trim(),
                          fontSize: template.fontSize,
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ),
                ],
                // أزيل مربع المبلغ الإجمالي لتجنب التكرار (المبلغ يظهر مع حالة التجديد أعلى)
                pw.SizedBox(height: 4),

                // ملاحظة للاشتراك الجديد
                if (isNewSubscription) ...[
                  pw.SizedBox(height: 4),
                  pw.Center(
                    child: _buildMixedText(
                      'تم تحويل الاشتراك من تجريبي إلى مدفوع',
                      fontSize: template.fontSize - 1,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],

                // معلومات إضافية (حسب القالب)
                if (template.showAdditionalInfo) ...[
                  pw.SizedBox(height: 4),
                  pw.Center(
                    child: _buildMixedText(
                      'تاريخ الإصدار: ${_getCurrentDate()}',
                      fontSize: template.fontSize - 2,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],

                // معلومات الاتصال (حسب القالب)
                if (template.showContactInfo &&
                    template.contactInfo.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 1),
                  ...template.contactInfo
                      .split('\n')
                      .where((l) => l.trim().isNotEmpty)
                      .map((line) => pw.Center(
                            child: _buildMixedText(
                              line.trim(),
                              fontSize: template.fontSize - 1,
                              textAlign: pw.TextAlign.center,
                            ),
                          )),
                ],

                // خاتمة مخصصة من القالب
                if (template.footerMessage.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Center(
                    child: _buildMixedText(
                      template.footerMessage.trim(),
                      fontSize: template.fontSize - 1,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      );

      // حفظ كـ PDF مباشرة أو طباعة
      if (saveAsPdf) {
        debugPrint('$_tag: Saving receipt as PDF file...');
        final pdfBytes = await pdf.save();
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'حفظ الوصل كـ PDF',
          fileName:
              'وصل_${customerName}_${DateTime.now().millisecondsSinceEpoch}.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (result != null) {
          await File(result).writeAsBytes(pdfBytes);
          debugPrint('$_tag: PDF saved to: $result');
        } else {
          debugPrint('$_tag: User cancelled PDF save');
          return false;
        }
      } else {
        // عرض نافذة الطباعة
        debugPrint('$_tag: Opening print dialog for custom template...');
        await Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async {
            debugPrint('$_tag: Generating PDF for custom template...');
            return pdf.save();
          },
          name:
              'وصل_مخصص_${operationType}_${DateTime.now().millisecondsSinceEpoch}',
        );
        debugPrint('$_tag: Custom PDF receipt printed successfully');

        // إرسال أمر القطع (ESC/POS) بعد الطباعة إذا كان مفعلاً (الوصل المخصص)
        try {
          final settings = await PrinterSettingsStorage.loadCutSettings();
          if (settings.enabled && settings.host.isNotEmpty) {
            if (settings.delayMs > 0) {
              await Future<void>.delayed(
                  Duration(milliseconds: settings.delayMs));
            }
            await EscposCutterService.sendCut(
              host: settings.host,
              port: settings.port,
              feedLines: settings.feedLines,
              partial: true,
            );
            debugPrint('$_tag: ESC/POS cut command sent (custom)');
          }
        } catch (e) {
          debugPrint('$_tag: Failed to send cut command (custom)');
        }
      }

      return true;
    } catch (e) {
      debugPrint('$_tag: Error printing custom PDF receipt');
      return false;
    }
  }

  /// اختبار طباعة النصوص المختلطة
  static Future<bool> testMixedTextPrint() async {
    try {
      // تحميل الخطوط أولاً
      await _loadFonts();

      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat(78 * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // اختبار النصوص المختلفة
                pw.Center(
                  child: _buildMixedText(
                    'اختبار النصوص المختلطة',
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 3),

                // اختبار التواريخ
                _buildMixedText('تاريخ اليوم: 17/06/2025', fontSize: 12),
                pw.SizedBox(height: 3),

                // اختبار الوقت
                _buildMixedText('الوقت: 14:30:25', fontSize: 12),
                pw.SizedBox(height: 3),

                // اختبار العملة
                _buildMixedText('السعر: 600.000 IQD', fontSize: 12),
                pw.SizedBox(height: 3),

                // اختبار رقم الهاتف
                _buildMixedText('الهاتف: 07801234567', fontSize: 12),
                pw.SizedBox(height: 3),

                // اختبار البريد الإلكتروني
                _buildMixedText('البريد: user@email.com', fontSize: 12),
                pw.SizedBox(height: 3),

                // اختبار الموقع
                _buildMixedText('الموقع: www.ftth-iq.com', fontSize: 12),
                pw.SizedBox(height: 3),

                // اختبار نص مختلط معقد
                _buildMixedText('العميل: أحمد محمد Ahmed', fontSize: 12),
                pw.SizedBox(height: 3),

                // اختبار خطة مختلطة
                _buildMixedText('الخطة: Basic Plan 25 Mbps', fontSize: 12),
                pw.SizedBox(height: 3),

                // اختبار حالة مختلطة
                _buildMixedText('الحالة: Active نشط', fontSize: 12),
                pw.SizedBox(height: 3),
                // اختبار رموز خاصة
                _buildMixedText('رموز: / - _ . @ # \$ % & * ( )', fontSize: 12),
                pw.SizedBox(height: 3),

                pw.Divider(thickness: 1),
                pw.Center(
                  child: _buildMixedText(
                    'انتهى اختبار النصوص المختلطة',
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      );

      // عرض نافذة الطباعة
      debugPrint('$_tag: Opening mixed text test print dialog...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          debugPrint('$_tag: Generating PDF for mixed text test...');
          return pdf.save();
        },
        name: 'اختبار_النصوص_المختلطة_${DateTime.now().millisecondsSinceEpoch}',
      );
      debugPrint('$_tag: Mixed text test printed successfully');

      return true;
    } catch (e) {
      debugPrint('$_tag: Error in mixed text test print');
      return false;
    }
  }

  /// اختبار طباعة الوصل بتخطيط 4 أعمدة الجديد
  static Future<bool> testNewLayoutPrint() async {
    try {
      // تحميل الخطوط أولاً
      await _loadFonts();

      final pdf = pw.Document();
      final receiptNumber = await getAndIncrementDailyReceiptNumber();

      pdf.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat(78 * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الوصل
                pw.Center(
                  child: _buildMixedText(
                    'شركة FTTH للإنترنت',
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildMixedText(
                    'للإنترنت عالي السرعة',
                    fontSize: 12,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.Center(
                  child: _buildMixedText(
                    'وصل تجديد اشتراك - التخطيط الجديد',
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.SizedBox(height: 5),

                // معلومات العميل والخدمة في 4 أعمدة
                _buildPdfRow4Columns(
                  'الاسم:',
                  'أحمد محمد',
                  'الخدمة:',
                  'FIBER 50',
                  fontSize: 10,
                ),
                _buildPdfRow4Columns(
                  'الهاتف:',
                  '07801234567',
                  'المدة:',
                  '12 شهر',
                  fontSize: 10,
                ),

                // تفاصيل الدفع
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 3,
                      child: _buildMixedText(
                        'المبلغ الإجمالي:',
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(width: 0.2),
                    pw.Expanded(
                      flex: 2,
                      child: _buildMixedText(
                        '600.000 IQD',
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                  ],
                ),

                _buildPdfRow4Columns(
                  'الدفع:',
                  'نقد',
                  'الانتهاء:',
                  '2025-06-17',
                  fontSize: 10,
                ),

                // معلومات إضافية
                _buildPdfRow4Columns(
                  'التفعيل:',
                  '2024-06-17',
                  'الوقت:',
                  '14:30:25',
                  fontSize: 10,
                ),
                _buildPdfRow4Columns(
                  'الوصل:',
                  receiptNumber.toString(),
                  'المنشط:',
                  'محمد أحمد',
                  fontSize: 10,
                ),
                _buildPdfRow4Columns(
                  'FDT:',
                  'FDT-001-A',
                  'FAT:',
                  'FAT-002-B',
                  fontSize: 10,
                ),

                pw.SizedBox(height: 8),

                // رسالة شكر
                pw.Center(
                  child: _buildMixedText(
                    'شكراً لاختياركم خدماتنا',
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),

                pw.SizedBox(height: 4),

                // معلومات التواصل
                pw.Center(
                  child: _buildMixedText(
                    'خدمة العملاء: 07801234567',
                    fontSize: 8,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildMixedText(
                    'الدعم الفني: 07809876543',
                    fontSize: 8,
                    textAlign: pw.TextAlign.center,
                  ),
                ),

                pw.SizedBox(height: 4),

                pw.Center(
                  child: _buildMixedText(
                    'تم الاختبار بنجاح - التخطيط الجديد 72mm',
                    fontSize: 8,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      );

      // عرض نافذة الطباعة
      debugPrint('$_tag: Opening new layout test print dialog...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          debugPrint('$_tag: Generating PDF for new layout test...');
          return pdf.save();
        },
        name:
            'اختبار_التخطيط_الجديد_4_أعمدة_${DateTime.now().millisecondsSinceEpoch}',
      );
      debugPrint('$_tag: New layout test printed successfully');

      return true;
    } catch (e) {
      debugPrint('$_tag: Error in new layout test print');
      return false;
    }
  }

  /// دالة اختبار للتخطيط الجديد المحسن لعرض 72mm
  static Future<bool> testNewLayout72mm() async {
    try {
      debugPrint('$_tag: Testing new 72mm layout...');

      // تحميل الخط العربي
      await _loadArabicFont();

      // بيانات تجريبية
      final testData = {
        'customerName': 'أحمد محمد علي',
        'customerPhone': '07801234567',
        'selectedPlan': 'FIBER 50',
        'selectedCommitmentPeriod': '12',
        'totalPrice': '150000',
        'currency': 'IQD',
        'selectedPaymentMethod': 'نقد',
        'endDate': '2025-12-31',
        'activationDate': '2025-06-18',
        'activationTime': '14:30:00',
        'activatedBy': 'المشغل',
        'fdtInfo': 'FDT-12345',
        'fatInfo': 'FAT-67890',
      };

      return await _printTestReceiptNew72mm(testData);
    } catch (e) {
      debugPrint('$_tag: Error in test');
      return false;
    }
  }

  /// طباعة وصل اختبار بالتخطيط الجديد
  static Future<bool> _printTestReceiptNew72mm(
      Map<String, String> testData) async {
    try {
      final pdf = pw.Document();
      final receiptNumber = await getAndIncrementDailyReceiptNumber();

      pdf.addPage(
        pw.Page(
          pageFormat:
              PdfPageFormat(78 * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الوصل
                pw.Center(
                  child: _buildMixedText(
                    'شركة FTTH للإنترنت',
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildMixedText(
                    'للإنترنت عالي السرعة',
                    fontSize: 12,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 1.5),
                pw.Center(
                  child: _buildMixedText(
                    'وصل تجديد اشتراك - اختبار التخطيط الجديد',
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 1.5),
                pw.SizedBox(height: 5),

                // التخطيط الجديد بـ 6 أسطر

                // السطر الأول: المنشط والوصل
                _buildPdfRow4ColumnsOptimized(
                  'المنشط:',
                  testData['activatedBy']!,
                  'الوصل:',
                  receiptNumber.toString(),
                  fontSize: 10,
                ),

                // السطر الثاني: الاسم والرقم
                _buildPdfRow4ColumnsOptimized(
                  'الاسم:',
                  testData['customerName']!,
                  'الرقم:',
                  testData['customerPhone']!,
                  fontSize: 10,
                ),

                // السطر الثالث: الدفع والانتهاء
                _buildPdfRow4ColumnsOptimized(
                  'الدفع:',
                  testData['selectedPaymentMethod']!,
                  'الانتهاء:',
                  testData['endDate']!.substring(0, 10),
                  fontSize: 10,
                ),

                // السطر الرابع: التفعيل والوقت
                _buildPdfRow4ColumnsOptimized(
                  'التفعيل:',
                  testData['activationDate']!,
                  'الوقت:',
                  testData['activationTime']!.substring(0, 5),
                  fontSize: 10,
                ),

                // السطر الخامس: FAT و FDT
                _buildPdfRow4ColumnsOptimized(
                  'FAT:',
                  testData['fatInfo']!,
                  'FDT:',
                  testData['fdtInfo']!,
                  fontSize: 10,
                ),

                pw.SizedBox(height: 6),

                // السطر الأخير: المبلغ داخل مربع
                pw.Container(
                  width: double.infinity,
                  padding: pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 2),
                    borderRadius: pw.BorderRadius.circular(3),
                    color: PdfColors.grey100,
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          _buildMixedText(
                            'المبلغ الإجمالي',
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            textAlign: pw.TextAlign.right,
                          ),
                          _buildMixedText(
                            '${testData['totalPrice']} ${testData['currency']}',
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            textAlign: pw.TextAlign.left,
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 2),
                      pw.Center(
                        child: _buildMixedText(
                          'الخدمة: ${testData['selectedPlan']} (${testData['selectedCommitmentPeriod']} شهر)',
                          fontSize: 9,
                          fontWeight: pw.FontWeight.normal,
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 8),

                // رسالة شكر
                pw.Center(
                  child: _buildMixedText(
                    'شكراً لاختياركم خدماتنا',
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),

                pw.SizedBox(height: 4),

                // معلومات التواصل
                pw.Center(
                  child: _buildMixedText(
                    'خدمة العملاء: 07801234567',
                    fontSize: 8,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildMixedText(
                    'الدعم الفني: 07809876543',
                    fontSize: 8,
                    textAlign: pw.TextAlign.center,
                  ),
                ),

                pw.SizedBox(height: 4),

                pw.Center(
                  child: _buildMixedText(
                    'تم الاختبار بنجاح - التخطيط الجديد 72mm',
                    fontSize: 8,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      );

      // عرض نافذة الطباعة
      debugPrint('$_tag: Opening test print dialog...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'test_receipt_72mm_${DateTime.now().millisecondsSinceEpoch}',
      );

      debugPrint('$_tag: Test print completed successfully');
      return true;
    } catch (e) {
      debugPrint('$_tag: Error in test print');
      return false;
    }
  }

  /// اختبار التخطيط المحسن للوصل مع منع قطع النص
  static Future<bool> testOptimizedLayoutPrint() async {
    try {
      await _loadFonts();

      final pdf = pw.Document();
      final receiptNumber = await getAndIncrementDailyReceiptNumber();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 180 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1.5),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الوصل
                pw.Center(
                    child: _buildMixedText('شركة FTTH للإنترنت',
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.center)),
                pw.Center(
                    child: _buildMixedText('للإنترنت عالي السرعة',
                        fontSize: 10, textAlign: pw.TextAlign.center)),
                pw.Divider(thickness: 1.5),
                pw.Center(
                    child: _buildMixedText('وصل تجديد اشتراك',
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.center)),
                pw.Divider(thickness: 1.5),
                pw.SizedBox(height: 3),

                // الأسطر الـ 5 بالترتيب المطلوب
                _buildPdfRow4ColumnsOptimized('المنشط:', 'محمد أحمد علي',
                    'الوصل:', receiptNumber.toString(),
                    fontSize: 9),
                _buildPdfRow4ColumnsOptimized(
                    'الاسم:', 'أحمد محمد علي حسين', 'الرقم:', '07801234567',
                    fontSize: 9),
                _buildPdfRow4ColumnsOptimized(
                    'الدفع:', 'نقد', 'الانتهاء:', '2025-12-17',
                    fontSize: 9),
                _buildPdfRow4ColumnsOptimized(
                    'التفعيل:', '2024-12-17', 'الوقت:', '14:30:25',
                    fontSize: 9),
                _buildPdfRow4ColumnsOptimized(
                    'FAT:', 'FAT-002-B-123', 'FDT:', 'FDT-001-A-456',
                    fontSize: 9),

                pw.SizedBox(height: 4),

                // المبلغ داخل مربع
                pw.Container(
                  width: double.infinity,
                  padding: pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Center(
                    child: _buildMixedText(
                      'المبلغ الإجمالي: 75000 دينار عراقي',
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ),

                pw.SizedBox(height: 6),

                // رسالة شكر
                pw.Center(
                    child: _buildMixedText('شكراً لاختياركم خدماتنا',
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.center)),
                pw.SizedBox(height: 2),
                pw.Center(
                    child: _buildMixedText('خدمة العملاء: 07801234567',
                        fontSize: 8, textAlign: pw.TextAlign.center)),
                pw.Center(
                    child: _buildMixedText('www.ftth-iq.com',
                        fontSize: 8, textAlign: pw.TextAlign.center)),
              ],
            );
          },
        ),
      );

      // عرض نافذة الطباعة
      debugPrint('$_tag: Opening optimized test print dialog...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'اختبار_التخطيط_المحسن_${DateTime.now().millisecondsSinceEpoch}',
      );

      debugPrint('$_tag: Optimized test print completed successfully');
      return true;
    } catch (e) {
      debugPrint('$_tag: Error in optimized test print');
      return false;
    }
  }

  /// اختبار التخطيط النهائي مع الخطوط العمودية والمسافات المحسنة
  static Future<bool> testFinalOptimizedLayout() async {
    try {
      await _loadFonts();
      final pdf = pw.Document();
      final receiptNumber = await getAndIncrementDailyReceiptNumber();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 180 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(1.5),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الوصل
                pw.Center(
                    child: _buildMixedText('شركة FTTH للإنترنت',
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.center)),
                pw.Center(
                    child: _buildMixedText('للإنترنت عالي السرعة',
                        fontSize: 10, textAlign: pw.TextAlign.center)),
                pw.Divider(thickness: 1.5),
                pw.Center(
                    child: _buildMixedText('وصل تجديد اشتراك',
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.center)),
                pw.Divider(thickness: 1.5),
                pw.SizedBox(height: 3),

                // الأسطر الـ 5 بالترتيب المطلوب
                _buildPdfRow4ColumnsOptimized('المنشط:', 'محمد أحمد علي',
                    'الوصل:', receiptNumber.toString(),
                    fontSize: 9),
                _buildPdfRow4ColumnsOptimized(
                    'الاسم:', 'أحمد محمد علي حسين', 'الرقم:', '07801234567',
                    fontSize: 9),
                _buildPdfRow4ColumnsOptimized(
                    'الدفع:', 'نقد', 'الانتهاء:', '2025-12-17',
                    fontSize: 9),
                _buildPdfRow4ColumnsOptimized(
                    'التفعيل:', '2024-12-17', 'الوقت:', '14:30:25',
                    fontSize: 9),
                _buildPdfRow4ColumnsOptimized(
                    'FAT:', 'FAT-002-B-123', 'FDT:', 'FDT-001-A-456',
                    fontSize: 9),

                pw.SizedBox(height: 4),

                // المبلغ داخل مربع
                pw.Container(
                  width: double.infinity,
                  padding: pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Center(
                    child: _buildMixedText(
                      'المبلغ الإجمالي: 75000 دينار عراقي',
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ),

                pw.SizedBox(height: 6),
                pw.Center(
                    child: _buildMixedText('شكراً لاختياركم خدماتنا',
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        textAlign: pw.TextAlign.center)),
                pw.SizedBox(height: 2),
                pw.Center(
                    child: _buildMixedText('خدمة العملاء: 07801234567',
                        fontSize: 8, textAlign: pw.TextAlign.center)),
                pw.Center(
                    child: _buildMixedText('www.ftth-iq.com',
                        fontSize: 8, textAlign: pw.TextAlign.center)),
              ],
            );
          },
        ),
      );

      // عرض نافذة الطباعة
      debugPrint('$_tag: Opening final optimized test print dialog...');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name:
            'اختبار_التخطيط_النهائي_المحسن_${DateTime.now().millisecondsSinceEpoch}',
      );

      debugPrint('$_tag: Final optimized test print completed successfully');
      return true;
    } catch (e) {
      debugPrint('$_tag: Error in final optimized test print');
      return false;
    }
  }

  /// اختبار التخطيط المحسن الجديد مع تقريب الأعمدة وإظهار الاسم الثلاثي كاملاً
  static Future<bool> testSuperOptimizedLayout() async {
    try {
      await _loadFonts();

      final pdf = pw.Document();
      final receiptNumber = await getAndIncrementDailyReceiptNumber();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الوصل
                pw.Center(
                  child: _buildMixedText(
                    'شركة FTTH للإنترنت',
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildMixedText(
                    'للإنترنت عالي السرعة',
                    fontSize: 10,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 2),
                pw.Center(
                  child: _buildMixedText(
                    'وصل تجديد اشتراك - محسن جديد',
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 3),

                // السطر الأول: المنشط والوصل مع اسم ثلاثي طويل
                _buildPdfRow4ColumnsOptimized(
                  'المنشط:',
                  'محمد أحمد علي عبدالله الجبوري',
                  'الوصل:',
                  receiptNumber.toString(),
                  fontSize: 9,
                ),

                // السطر الثاني: الاسم والرقم مع اسم طويل جداً (سيتم تقصيره إلى 3 كلمات)
                _buildPdfRow4ColumnsOptimized(
                  'الاسم:',
                  'علي حسن محمد عباس عبدالرحمن الجبوري الطويل جداً من بغداد',
                  'الرقم:',
                  '07801234567',
                  fontSize: 9,
                ),

                // السطر الثالث: الدفع والانتهاء
                _buildPdfRow4ColumnsOptimized(
                  'الدفع:',
                  'نقد',
                  'الانتهاء:',
                  '2025-12-17',
                  fontSize: 9,
                ),

                // السطر الرابع: التفعيل والوقت
                _buildPdfRow4ColumnsOptimized(
                  'التفعيل:',
                  '2024-06-17',
                  'الوقت:',
                  '14:30:25',
                  fontSize: 9,
                ),

                // السطر الخامس: FAT و FDT مع نصوص طويلة
                _buildPdfRow4ColumnsOptimized(
                  'FAT:',
                  'FAT-002-B-SECTOR-A-MAIN',
                  'FDT:',
                  'FDT-001-A-MAIN-LINE-EXTENDED',
                  fontSize: 9,
                ),

                // السطر السادس: السرعة والسعر
                _buildPdfRow4ColumnsOptimized(
                  'السرعة:',
                  '50 ميجا',
                  'السعر:',
                  '75000 دينار',
                  fontSize: 9,
                ),

                pw.SizedBox(height: 5),

                // المبلغ الإجمالي داخل مربع مميز
                pw.Container(
                  width: double.infinity,
                  padding: pw.EdgeInsets.all(5),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(width: 2),
                    borderRadius: pw.BorderRadius.circular(4),
                    color: PdfColors.grey100,
                  ),
                  child: pw.Center(
                    child: _buildMixedText(
                      'المبلغ الإجمالي: 75000 دينار عراقي',
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ),

                pw.SizedBox(height: 5),

                // معلومات إضافية
                pw.Divider(),
                pw.Center(
                  child: _buildMixedText(
                    'تاريخ الإصدار: ${_getCurrentDate()}',
                    fontSize: 8,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Center(
                  child: _buildMixedText(
                    'تم إنشاء هذا الوصل تلقائياً - FTTH System',
                    fontSize: 7,
                    textAlign: pw.TextAlign.center,
                  ),
                ),

                pw.SizedBox(height: 3),
                pw.Center(
                  child: _buildMixedText(
                    'اختبار التخطيط المحسن الجديد - 72mm',
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name:
            'اختبار_التخطيط_المحسن_الجديد_${DateTime.now().millisecondsSinceEpoch}',
      );

      debugPrint('$_tag: Super optimized layout test completed successfully');
      return true;
    } catch (e) {
      debugPrint('$_tag: Error in super optimized layout test');
      return false;
    }
  }

  /// دالة للحصول على رقم وصل يومي متسلسل
  static Future<int> getAndIncrementDailyReceiptNumber() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today =
          DateTime.now().toIso8601String().split('T')[0]; // YYYY-MM-DD
      final todayKey = 'daily_receipt_$today';

      // الحصول على العدد الحالي لليوم
      int currentNumber = prefs.getInt(todayKey) ?? 0;

      // زيادة العدد
      currentNumber++;

      // حفظ العدد الجديد
      await prefs.setInt(todayKey, currentNumber);

      return currentNumber;
    } catch (e) {
      debugPrint('$_tag: Error getting receipt number');
      // إرجاع رقم عشوائي في حالة الخطأ
      return DateTime.now().millisecondsSinceEpoch % 10000;
    }
  }

  /// طباعة ملخص إعدادات تخطيط الوصل (تشخيصي)
  static Future<bool> printReceiptLayoutSettings() async {
    try {
      await _loadArabicFont();
      final pdf = pw.Document();

      pw.Widget rowKV(String k, String v) => _buildPdfRowArabic(k, v);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
              _paperWidthMm * PdfPageFormat.mm, 200 * PdfPageFormat.mm),
          margin: pw.EdgeInsets.all(2),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: _buildMixedText(
                    'ملخص إعدادات تخطيط الوصل',
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 4),
                _buildMixedText('عام:',
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
                pw.Divider(thickness: 1),
                rowKV('عرض الورق', '${_paperWidthMm.toStringAsFixed(0)}mm'),
                rowKV('الارتفاع (اختباري)', '200mm'),
                pw.SizedBox(height: 4),
                _buildMixedText('الصف 1: المنشط / الوصل',
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
                pw.Divider(thickness: 1),
                rowKV('fontSize', 'template.fontSize - 1.0'),
                rowKV('leadingPaddingWidth', '0mm'),
                rowKV('gapBeforeDivider (قيمة↔عنوان المنشط)', '10mm'),
                rowKV('gapLabel1ToDivider (عنوان المنشط↔الفاصل)', '6.5mm'),
                rowKV('gapDividerToValue2 (الفاصل↔قيمة الوصل)', '0.3mm'),
                rowKV('gapAfterDivider (بعد الفاصل جهة الوصل)', '1.4mm'),
                rowKV('trailingPaddingWidth', '1mm'),
                rowKV('flex (value1,label1,value2,label2)', '4, 3, 4, 3'),
                pw.SizedBox(height: 4),
                _buildMixedText('الصف 2: الاسم / الرقم',
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
                pw.Divider(thickness: 1),
                rowKV('fontSize', 'template.fontSize - 0.5'),
                rowKV('leadingPaddingWidth', '0mm'),
                rowKV('gapBeforeDivider', '0.3mm'),
                rowKV('gapLabel1ToDivider', '1.5mm'),
                rowKV('gapDividerToValue2', '0.3mm'),
                rowKV('gapAfterDivider', '3.0mm'),
                rowKV('trailingPaddingWidth', '2mm'),
                rowKV('flex (value1,label1,value2,label2)', '5, 2, 5, 2'),
                pw.SizedBox(height: 4),
                _buildMixedText('الصف 3: الدفع / الانتهاء',
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
                pw.Divider(thickness: 1),
                rowKV('fontSize', 'template.fontSize - 0.5'),
                rowKV('leadingPaddingWidth', '0mm'),
                rowKV('gapBeforeDivider', '0.3mm'),
                rowKV('gapLabel1ToDivider', '1.5mm'),
                rowKV('gapDividerToValue2', '0.3mm'),
                rowKV('gapAfterDivider', '3.0mm'),
                rowKV('trailingPaddingWidth', '2mm'),
                rowKV('flex (value1,label1,value2,label2)', '5, 2, 5, 2'),
                pw.SizedBox(height: 4),
                _buildMixedText('الصف 4: التفعيل / الوقت',
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
                pw.Divider(thickness: 1),
                rowKV('fontSize', 'template.fontSize - 0.5'),
                rowKV('leadingPaddingWidth', '0mm'),
                rowKV('gapBeforeDivider', '0.3mm'),
                rowKV('gapLabel1ToDivider', '1.5mm'),
                rowKV('gapDividerToValue2', '0.3mm'),
                rowKV('gapAfterDivider', '3.0mm'),
                rowKV('trailingPaddingWidth', '2mm'),
                rowKV('flex (value1,label1,value2,label2)', '4, 3, 5, 2'),
                pw.SizedBox(height: 4),
                _buildMixedText('الصف 5: FAT / FDT',
                    fontSize: 12, fontWeight: pw.FontWeight.bold),
                pw.Divider(thickness: 1),
                rowKV('fontSize', 'template.fontSize - 0.5'),
                rowKV('leadingPaddingWidth', '0mm'),
                rowKV('gapBeforeDivider', '0.3mm'),
                rowKV('gapLabel1ToDivider', '1.5mm'),
                rowKV('gapDividerToValue2', '0.3mm'),
                rowKV('gapAfterDivider', '3.0mm'),
                rowKV('trailingPaddingWidth', '2mm'),
                rowKV('flex (value1,label1,value2,label2)', '5, 2, 5, 2'),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'إعدادات_تخطيط_الوصل_${DateTime.now().millisecondsSinceEpoch}',
      );
      return true;
    } catch (e) {
      debugPrint('$_tag: Error printing layout settings');
      return false;
    }
  }
}
