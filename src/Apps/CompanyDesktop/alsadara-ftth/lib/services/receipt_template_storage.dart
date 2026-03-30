import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/receipt_template_models.dart';

/// تخزين وتحميل قالب الوصل الجديد (V2)
/// يدعم الترحيل التلقائي من النظام القديم (PrintTemplate)
class ReceiptTemplateStorageV2 {
  static const _key = 'receipt_template_v2';
  static const _oldKey = 'print_template'; // المفتاح القديم
  static const _currentVersion = 9; // v9: إضافة صف الملاحظات

  /// تحميل القالب — يُرحّل من النظام القديم تلقائياً إذا لزم
  static Future<ReceiptTemplate> loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);

    if (jsonStr != null) {
      try {
        final saved = ReceiptTemplate.fromJson(json.decode(jsonStr) as Map<String, dynamic>);
        // إذا كان القالب المحفوظ أقدم من النسخة الحالية — ترحيل ذكي
        if (saved.version < _currentVersion) {
          debugPrint('📋 تحديث القالب من v${saved.version} إلى v$_currentVersion');
          final migrated = _migrateToLatest(saved);
          await saveTemplate(migrated);
          return migrated;
        }
        return saved;
      } catch (e) {
        debugPrint('⚠️ خطأ في تحميل القالب V2: $e — استخدام الافتراضي');
      }
    }

    // محاولة الترحيل من النظام القديم
    final oldStr = prefs.getString(_oldKey);
    if (oldStr != null) {
      try {
        final oldData = json.decode(oldStr) as Map<String, dynamic>;
        final migrated = _migrateFromV1(oldData);
        // حفظ القالب المُرحّل (بدون حذف القديم — للأمان)
        await saveTemplate(migrated);
        debugPrint('✅ تم ترحيل قالب الوصل من V1 إلى V2');
        return migrated;
      } catch (e) {
        debugPrint('⚠️ فشل ترحيل القالب القديم');
      }
    }

    return ReceiptTemplate.defaultTemplate();
  }

  /// حفظ القالب
  static Future<void> saveTemplate(ReceiptTemplate template) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, json.encode(template.toJson()));
  }

  /// حذف القالب المحفوظ (العودة للافتراضي)
  static Future<void> resetTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// ترحيل ذكي — يضيف الصفوف المفقودة مع الحفاظ على تخصيصات المستخدم
  static ReceiptTemplate _migrateToLatest(ReceiptTemplate saved) {
    final rows = List<ReceiptRow>.from(saved.rows);

    // v9: تقليل المسافات في كل الصفوف ذات الحدود
    const tightDecoration = ReceiptBoxDecoration(
      borderWidth: 0.8,
      borderRadius: 3,
      paddingH: 2,
      paddingV: 1,
      marginBottom: 1,
    );
    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.decoration != null && row.decoration!.borderWidth > 0) {
        rows[i] = row.copyWith(
          decoration: () => tightDecoration,
        );
      }
    }

    // v9: إضافة صف الملاحظات إذا لم يكن موجوداً
    final hasNotesRow = rows.any((r) => r.cells.any((c) => c.content.contains('subscriptionNotes')));
    if (!hasNotesRow) {
      const bordered = ReceiptBoxDecoration(
        borderWidth: 0.8,
        borderRadius: 3,
      );
      final notesRow = ReceiptRow(
        id: 'r9',
        type: ReceiptRowType.cells,
        conditionVariable: 'hasNotes',
        decoration: bordered,
        cells: [
          ReceiptCell(
            id: 'r9c1',
            content: 'ملاحظات:',
            flex: 3,
            alignment: ReceiptCellAlignment.right,
            isLabel: true,
            textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
          ),
          ReceiptCell(
            id: 'r9c2',
            content: '{{subscriptionNotes}}',
            flex: 11,
            alignment: ReceiptCellAlignment.right,
            textStyle: const ReceiptTextStyle(fontSizeOffset: -0.5),
          ),
        ],
      );
      // إدراج قبل آخر صف (فوتر معلومات الاتصال)
      if (rows.length >= 2) {
        rows.insert(rows.length - 1, notesRow);
      } else {
        rows.add(notesRow);
      }
      debugPrint('📝 تم إضافة صف الملاحظات للقالب');
    }

    return saved.copyWith(version: _currentVersion, rows: rows);
  }

  /// ترحيل من النظام القديم (PrintTemplate → ReceiptTemplate)
  static ReceiptTemplate _migrateFromV1(Map<String, dynamic> oldData) {
    final defaultTmpl = ReceiptTemplate.defaultTemplate();

    // تحديث إعدادات الصفحة من القيم القديمة
    final pageSettings = defaultTmpl.pageSettings.copyWith(
      baseFontSize: (oldData['fontSize'] as num?)?.toDouble(),
      boldHeaders: oldData['boldHeaders'] as bool?,
    );

    // تحديث نصوص الترويسة والتذييل في الصفوف
    final rows = defaultTmpl.rows.map((row) {
      if (row.cells.isEmpty) return row;
      final content = row.cells.first.content;

      // تحديث النصوص الثابتة من القيم القديمة
      if (content == '{{companyName}}' || content == '{{companySubtitle}}' ||
          content == '{{contactInfo}}' || content == '{{footerMessage}}') {
        // هذه متغيرات — ستُملأ عند الطباعة من القيم المحفوظة
        // لا حاجة لتغييرها في القالب
      }

      // تحديث شرط الإظهار بناءً على التوغلات القديمة
      if (row.conditionVariable == 'showCustomerInfo' && oldData['showCustomerInfo'] == false) {
        return row.copyWith(visible: false);
      }
      if (row.conditionVariable == 'showServiceDetails' && oldData['showServiceDetails'] == false) {
        return row.copyWith(visible: false);
      }
      if (row.conditionVariable == 'showPaymentDetails' && oldData['showPaymentDetails'] == false) {
        return row.copyWith(visible: false);
      }
      if (row.conditionVariable == 'showContactInfo' && oldData['showContactInfo'] == false) {
        return row.copyWith(visible: false);
      }

      return row;
    }).toList();

    return defaultTmpl.copyWith(
      pageSettings: pageSettings,
      rows: rows,
    );
  }

  /// بناء خريطة قيم المتغيرات من بيانات الطباعة الفعلية
  static Map<String, String> buildVariableValues({
    // ── أساسي ──
    required String operationType,
    required String customerName,
    required String customerPhone,
    String? customerAddress,
    required String paymentMethod, // فقط نوع الدفع: نقد/أجل/ماستر/وكيل/فني
    required String totalPrice,
    required String currency,
    required String endDate,
    required String activatedBy,
    required String receiptNumber,
    required String selectedPlan,
    required String commitmentPeriod,
    required String activationDate,
    required String activationTime,
    String? fdtInfo,
    String? fatInfo,
    String? subscriptionNotes,
    int? copyNumber,
    // ── الترويسة ──
    String companyName = 'شركة الصدارة',
    String companySubtitle = 'المشغل الرسمي للمشروع الوطني',
    String contactInfo = 'للاستفسار: 07744077077',
    String footerMessage = 'شكراً لاختياركم شركة الصدارة',
    // ── الفني / الوكيل (مفصولة) ──
    String? technicianName,
    String? technicianUsername,
    String? technicianPhone,
    String? agentName,
    String? agentCode,
    String? agentPhone,
    // ── الأسعار المفصّلة ──
    String? basePrice,
    String? discount,
    String? discountPercentage,
    String? manualDiscount,
    String? salesType,
    String? walletBalance,
    // ── بيانات الاشتراك الإضافية ──
    String? currentPlan,
    String? expiryDate,
    String? subscriptionStartDate,
    String? remainingDays,
    String? subscriptionStatus,
    String? customerId,
    String? partnerName,
    // ── الشبكة والجهاز ──
    String? fbgInfo,
    String? zoneDisplayValue,
    String? deviceUsername,
    String? deviceSerial,
    String? macAddress,
    String? deviceModel,
    // ── المشغّل (سيرفرنا) ──
    String? operatorFullName,
    String? operatorPhone,
    String? operatorDepartment,
    String? operatorCenter,
    String? operatorRole,
  }) {
    final now = DateTime.now();

    // قص اسم العميل لأول 3 أسماء فقط (الاسم + الأب + الجد)
    final nameParts = customerName.trim().split(RegExp(r'\s+'));
    final shortCustomerName = nameParts.length > 3
        ? nameParts.take(3).join(' ')
        : customerName.trim();

    // اسم المحصّل: الفني إذا موجود، وإلا الوكيل
    final collectorName = (technicianName?.isNotEmpty == true)
        ? technicianName!
        : (agentName?.isNotEmpty == true)
            ? agentName!
            : '';

    return {
      // الترويسة
      'companyName': companyName,
      'companySubtitle': companySubtitle,
      'contactInfo': contactInfo,
      'footerMessage': footerMessage,
      // العميل
      'customerName': shortCustomerName,
      'customerPhone': customerPhone,
      'customerAddress': customerAddress ?? '',
      'customerId': customerId ?? '',
      'partnerName': partnerName ?? '',
      // الدفع
      'paymentMethod': paymentMethod,
      'totalPrice': totalPrice,
      'currency': currency,
      'basePrice': basePrice ?? totalPrice,
      'discount': discount ?? '0',
      'discountPercentage': discountPercentage ?? '0',
      'manualDiscount': manualDiscount ?? '0',
      'salesType': salesType ?? '',
      'walletBalance': walletBalance ?? '',
      // الفني / الوكيل
      'collectorName': collectorName,
      'technicianName': technicianName ?? '',
      'technicianUsername': technicianUsername ?? '',
      'technicianPhone': technicianPhone ?? '',
      'agentName': agentName ?? '',
      'agentCode': agentCode ?? '',
      'agentPhone': agentPhone ?? '',
      // الخدمة
      'selectedPlan': selectedPlan,
      'currentPlan': currentPlan ?? selectedPlan,
      'commitmentPeriod': commitmentPeriod,
      'endDate': endDate,
      'expiryDate': expiryDate ?? '',
      'subscriptionStartDate': subscriptionStartDate ?? '',
      'remainingDays': remainingDays ?? '',
      'subscriptionStatus': subscriptionStatus ?? '',
      'subscriptionNotes': subscriptionNotes ?? '',
      // الشبكة والجهاز
      'fdtInfo': fdtInfo ?? '',
      'fatInfo': fatInfo ?? '',
      'fbgInfo': fbgInfo ?? '',
      'zoneDisplayValue': zoneDisplayValue ?? '',
      'deviceUsername': deviceUsername ?? '',
      'deviceSerial': deviceSerial ?? '',
      'macAddress': macAddress ?? '',
      'deviceModel': deviceModel ?? '',
      // المشغّل (سيرفرنا)
      'operatorFullName': operatorFullName ?? '',
      'operatorPhone': operatorPhone ?? '',
      'operatorDepartment': operatorDepartment ?? '',
      'operatorCenter': operatorCenter ?? '',
      'operatorRole': operatorRole ?? '',
      // النظام
      'operationType': operationType,
      'activatedBy': activatedBy,
      'receiptNumber': receiptNumber,
      'activationDate': activationDate,
      'activationTime': activationTime,
      'copyNumber': (copyNumber ?? 1).toString(),
      'currentDate': '${now.day}/${now.month}/${now.year}',
    };
  }

  /// بناء خريطة الشروط من PrintTemplate القديم
  static Map<String, bool> buildConditions({
    bool showCustomerInfo = true,
    bool showServiceDetails = true,
    bool showPaymentDetails = true,
    bool showAdditionalInfo = false,
    bool showContactInfo = true,
    String? subscriptionNotes,
  }) {
    return {
      'showCustomerInfo': showCustomerInfo,
      'showServiceDetails': showServiceDetails,
      'showPaymentDetails': showPaymentDetails,
      'showAdditionalInfo': showAdditionalInfo,
      'showContactInfo': showContactInfo,
      'hasNotes': subscriptionNotes != null && subscriptionNotes.trim().isNotEmpty,
    };
  }
}
