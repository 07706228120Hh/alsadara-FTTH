/// مساعد «ما بعد التفعيل/التحصيل» المشترك لوحدة وكيل الساس.
///
/// يُجمّع في مكان واحد منطق الطباعة الحرارية + رسالة الواتساب الذي كان
/// مكرَّراً داخل صفحة تفاصيل المشترك، ليستخدمه كلٌّ من:
///  • التفعيل/التمديد/تغيير الباقة الفردي (`sas_subscriber_detail_page.dart`).
///  • التجديد الجماعي المفوتر (`sas_renewal_tab.dart`).
///
/// التصميم:
///  • دالة ثابتة واحدة [SasBillingPostActions.run] تأخذ خريطة إيصال الساس
///    (`receipt`) + سياق المشترك (الاسم/الهاتف/الانتهاء الجديد)، وتُنفّذ
///    الطباعة ثم الواتساب، كلٌّ داخل `try/catch` **مستقل** فلا يُسقط تعذّرُ
///    أحدهما الآخر، ولا يُفشل العملية المالية الناجحة التي سبقته.
///  • لا تعتمد على `BuildContext` ولا على حالة ودجة — خالصة قابلة للاستدعاء
///    خلفياً وتسلسلياً لكل مشترك في دفعة.
///
/// ⚠️ لا تُطبَع/تُرسَل أي كلمة مرور. السعر محسوب خادمياً داخل الإيصال.
library;

import '../../services/print_template_storage.dart';
import '../../services/receipt_template_storage.dart';
import '../../services/thermal_printer_service.dart';
import '../../services/vps_auth_service.dart';
import '../whatsapp/whatsapp.dart';

/// تحويل آمن لرقم — الساس يُعيد حقولاً عددية كنصوص أحياناً.
num? _asNum(dynamic v) =>
    v is num ? v : (v == null ? null : num.tryParse(v.toString()));

/// تنسيق مبلغ: يحذف الكسر العشري إن كان صفراً (12.0 → 12).
String _money(num v) {
  final n = v == v.roundToDouble() ? v.round() : v;
  return n.toString();
}

/// تحويل نوع التحصيل إلى العربية للعرض/الطباعة.
String _collectionTypeAr(String? type) {
  switch (type) {
    case 'cash':
      return 'نقد';
    case 'credit':
      return 'أجل';
    case 'agent':
      return 'وكيل';
    default:
      return type ?? 'نقد';
  }
}

/// منفّذ إجراءات ما بعد التحصيل المشترك (طباعة ثم واتساب، كلٌّ معزول).
class SasBillingPostActions {
  SasBillingPostActions._();

  /// يُطلق الطباعة الحرارية ثم رسالة الواتساب بعد نجاح عملية مفوترة.
  ///
  /// [receipt] خريطة إيصال الساس القادمة من الخادم (operationType/
  /// subscriberUsername/planName/months/basePrice/maintenanceFee/
  /// manualDiscount/collectedAmount/currency/collectionType/transactionId…).
  ///
  /// [customerName] الاسم الكامل للمشترك (للطباعة/الرسالة). إن تُرك فارغاً
  /// يُشتَقّ من `subscriberUsername` في الإيصال.
  /// [phone] رقم الهاتف الخام (يُطبَّع داخلياً؛ تُتخطّى الرسالة إن تعذّر).
  /// [newExpiration] تاريخ الانتهاء الجديد بعد العملية (للطباعة/الرسالة).
  ///
  /// كلٌّ من الطباعة والواتساب في `try/catch` مستقل؛ لا يرمي هذا الاستدعاء.
  static Future<void> run(
    Map<String, dynamic> receipt, {
    String? customerName,
    String? phone,
    String? newExpiration,
  }) async {
    final username = (receipt['subscriberUsername'] ?? '').toString().trim();
    final name = (customerName?.trim().isNotEmpty == true)
        ? customerName!.trim()
        : (username.isNotEmpty ? username : 'مشترك');

    // 1) الطباعة الحرارية.
    try {
      final vars = _buildReceiptVars(
        receipt,
        customerName: name,
        phone: phone,
        newExpiration: newExpiration,
      );
      final conds = ReceiptTemplateStorageV2.buildConditions(
        showCustomerInfo: true,
        showServiceDetails: true,
        showPaymentDetails: true,
        showAdditionalInfo: false, // إخفاء قسم الشبكة/الجهاز (نمط FTTH)
        showContactInfo: true,
      );
      await ThermalPrinterService.printFromReceiptTemplate(
        variableValues: vars,
        conditions: conds,
      );
    } catch (_) {
      // تعذّرت الطباعة — لا نُفشل العملية.
    }

    // 2) رسالة الواتساب (مشروطة بتوفّر الرقم/الإعداد).
    try {
      await _sendWhatsApp(
        receipt,
        customerName: name,
        username: username,
        phone: phone,
        newExpiration: newExpiration,
      );
    } catch (_) {
      // تعذّر الإرسال — صامت (العملية الأساسية نجحت).
    }
  }

  /// يملأ متغيّرات قالب الإيصال من بيانات إيصال الساس + سياق المشترك.
  static Map<String, String> _buildReceiptVars(
    Map<String, dynamic> receipt, {
    required String customerName,
    String? phone,
    String? newExpiration,
  }) {
    final now = DateTime.now();
    final activationDate = '${now.day}/${now.month}/${now.year}';
    final activationTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final opType = (receipt['operationType'] ?? 'تم تفعيل اشتراك').toString();
    final planName = (receipt['planName'] ?? '').toString();
    final months = (receipt['months'] ?? '').toString();
    final collected = _asNum(receipt['collectedAmount']);
    final basePrice = _asNum(receipt['basePrice']);
    final manualDiscount = _asNum(receipt['manualDiscount']);
    final currency = (receipt['currency'] ?? 'IQD').toString();
    final endDate =
        (newExpiration ?? receipt['endDate'] ?? '').toString();
    final activatedBy = VpsAuthService.instance.currentUser?.fullName ?? '';

    final header = PrintTemplateStorage.defaultTemplate;

    return ReceiptTemplateStorageV2.buildVariableValues(
      operationType: opType,
      customerName: customerName,
      customerPhone: (phone?.trim().isNotEmpty == true)
          ? phone!.trim()
          : 'غير متوفر',
      paymentMethod: _collectionTypeAr(receipt['collectionType']?.toString()),
      totalPrice: collected != null ? _money(collected) : '0',
      currency: currency,
      endDate: endDate,
      activatedBy: activatedBy,
      receiptNumber: '0', // يُستبدل بعدّاد الوصل داخل الخدمة
      selectedPlan: planName,
      commitmentPeriod: months,
      activationDate: activationDate,
      activationTime: activationTime,
      basePrice: basePrice != null ? _money(basePrice) : null,
      manualDiscount: manualDiscount != null ? _money(manualDiscount) : null,
      // ترويسة الشركة من القالب.
      companyName: header.companyName,
      companySubtitle: header.companySubtitle,
      contactInfo: header.contactInfo,
      footerMessage: header.footerMessage,
      // المشغّل.
      operatorFullName: activatedBy,
      // حقول الشبكة/الجهاز تُترك فارغة (إيصال ساس أنظف).
    );
  }

  /// يرسل رسالة واتساب «تم التفعيل/التجديد» الغنيّة عبر المُرسِل المضبوط.
  /// صامت إن تعذّر الرقم أو الإعداد (لا يُفشل العملية).
  ///
  /// الإرسال التلقائي الصامت يقتصر على الأنماط الآلية (خادم محلي/Meta)؛ النمط
  /// اليدوي (app) يفتح نافذة لكل رسالة فلا يُشغَّل تلقائياً هنا تفادياً لإزعاج
  /// تدفّق التفعيل/الدفعة (يبقى للإرسال اليدوي/الجماعي من شاشاته).
  static Future<void> _sendWhatsApp(
    Map<String, dynamic> receipt, {
    required String customerName,
    required String username,
    String? phone,
    String? newExpiration,
  }) async {
    final rawPhone = phone?.trim();
    if (rawPhone == null || rawPhone.isEmpty) return;
    final normalized = normalizeIraqiPhone(rawPhone);
    if (normalized == null) return;

    // بناء نصّ الرسالة من القالب الغنيّ المخزّن.
    final store = LocalTemplateStore();
    final tpl = await store.byId(WaTemplateIds.renewed);
    if (tpl == null) return;

    final collected = _asNum(receipt['collectedAmount']);
    final endDate = (newExpiration ?? '').toString();
    final message = tpl.render({
      'name': customerName,
      'username': username,
      'profile': (receipt['planName'] ?? '').toString(),
      'plan': (receipt['planName'] ?? '').toString(),
      'price': collected != null ? _money(collected) : '',
      'currency': (receipt['currency'] ?? 'IQD').toString(),
      'months': (receipt['months'] ?? '').toString(),
      'endDate': endDate,
      'expiration': endDate,
      'paymentMethod': _collectionTypeAr(receipt['collectionType']?.toString()),
      'activatedBy': VpsAuthService.instance.currentUser?.fullName ?? '',
    });

    final settings = await WaSettingsStore().load();
    final sender = settings.buildSender();
    try {
      if (!sender.capabilities.automated) return;
      final status = await sender.status();
      if (!status.ready) return; // الخادم غير جاهز/غير مربوط — تخطَّ بصمت.
      await sender.sendOne(
        WaOutgoing(
          recipient: WaRecipient(name: customerName, rawPhone: rawPhone),
          text: message,
        ),
      );
    } finally {
      sender.dispose();
    }
  }
}
