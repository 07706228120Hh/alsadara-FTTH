import 'package:cloud_firestore/cloud_firestore.dart';
import 'custom_auth_service.dart';

/// أنواع قوالب الواتساب
enum WhatsAppTemplateType {
  renewal, // قالب التجديد
  expiringSoon, // قالب تذكير قبل الانتهاء
  expired, // قالب اشتراك منتهي
  notification, // قالب تبليغ عام
}

/// خدمة إدارة قوالب الواتساب - خاصة بكل شركة (tenant)
/// تُستخدم مع: إرسال الرسائل الجماعية وصفحة تفاصيل المشترك
class WhatsAppTemplatesService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CustomAuthService _authService = CustomAuthService();

  // ============ أسماء القوالب بالعربية ============
  static const Map<WhatsAppTemplateType, String> templateNames = {
    WhatsAppTemplateType.renewal: 'قالب التجديد',
    WhatsAppTemplateType.expiringSoon: 'قالب تذكير قبل الانتهاء',
    WhatsAppTemplateType.expired: 'قالب اشتراك منتهي',
    WhatsAppTemplateType.notification: 'قالب تبليغ',
  };

  // ============ أوصاف القوالب ============
  static const Map<WhatsAppTemplateType, String> templateDescriptions = {
    WhatsAppTemplateType.renewal: 'يُرسل تلقائياً بعد تجديد اشتراك المشترك',
    WhatsAppTemplateType.expiringSoon:
        'يُرسل للمشتركين الذين سينتهي اشتراكهم قريباً',
    WhatsAppTemplateType.expired: 'يُرسل للمشتركين المنتهية اشتراكاتهم',
    WhatsAppTemplateType.notification:
        'يُرسل كتبليغ عام لمجموعة أو كل المشتركين',
  };

  // ============ القوالب الافتراضية ============
  static const Map<WhatsAppTemplateType, String> defaultTemplates = {
    WhatsAppTemplateType.renewal: '''==============================
👋 مرحباً {customerName}
الهاتف: {customerPhone}
==============================
✅ تم: {operation}
------------------------------
الخطة: {planName}
فترة الالتزام: {commitmentPeriod} شهر
FBG: {fbg}
FAT: {fat}
تاريخ الانتهاء: {endDate}
طريقة الدفع: {paymentMethod}
القيمة: {totalPrice} {currency}
------------------------------
المحاسب: {activatedBy}
تاريخ الوصل: {todayDate}
الوقت: {todayTime}
==============================
شكراً لثقتك بنا! 🙏''',
    WhatsAppTemplateType.expiringSoon: '''⚠️ تذكير بانتهاء الاشتراك

مرحباً {customerName} 👋

اشتراكك سينتهي بتاريخ: {endDate}
المتبقي: {days_left} يوم
الباقة: {planName}
FBG: {fbg}

يرجى التجديد لتجنب انقطاع الخدمة.
للتجديد تواصل معنا 📞''',
    WhatsAppTemplateType.expired: '''📢 اشتراكك منتهي!

مرحباً {customerName} 👋

انتهى اشتراكك بتاريخ: {endDate}
الباقة السابقة: {planName}
FBG: {fbg}

🎁 عرض خاص للتجديد!
{offer}

للتجديد تواصل معنا الآن 📞''',
    WhatsAppTemplateType.notification: '''📣 تبليغ هام

مرحباً {customerName} 👋

{message}

مع تحيات إدارة الشركة 🙏''',
  };

  // ============ المتغيرات المتاحة لكل قالب ============
  static const Map<WhatsAppTemplateType, List<String>> templateVariables = {
    WhatsAppTemplateType.renewal: [
      '{customerName}',
      '{customerPhone}',
      '{operation}',
      '{planName}',
      '{commitmentPeriod}',
      '{totalPrice}',
      '{currency}',
      '{paymentMethod}',
      '{endDate}',
      '{activatedBy}',
      '{fbg}',
      '{fat}',
      '{todayDate}',
      '{todayTime}',
    ],
    WhatsAppTemplateType.expiringSoon: [
      '{customerName}',
      '{customerPhone}',
      '{planName}',
      '{endDate}',
      '{days_left}',
      '{fbg}',
      '{fat}',
    ],
    WhatsAppTemplateType.expired: [
      '{customerName}',
      '{customerPhone}',
      '{planName}',
      '{endDate}',
      '{offer}',
      '{fbg}',
      '{fat}',
    ],
    WhatsAppTemplateType.notification: [
      '{customerName}',
      '{customerPhone}',
      '{message}',
    ],
  };

  // ============ وصف المتغيرات ============
  static const Map<String, String> variableDescriptions = {
    '{customerName}': 'اسم المشترك',
    '{customerPhone}': 'رقم الهاتف',
    '{operation}': 'نوع العملية (شراء/تجديد)',
    '{planName}': 'اسم الباقة',
    '{commitmentPeriod}': 'فترة الالتزام (بالشهور)',
    '{totalPrice}': 'السعر الإجمالي',
    '{currency}': 'العملة',
    '{paymentMethod}': 'طريقة الدفع',
    '{endDate}': 'تاريخ انتهاء الاشتراك',
    '{activatedBy}': 'منفذ العملية',
    '{fbg}': 'رقم FBG',
    '{fat}': 'رقم FAT',
    '{todayDate}': 'تاريخ اليوم',
    '{todayTime}': 'الوقت الحالي',
    '{days_left}': 'الأيام المتبقية',
    '{offer}': 'نص العرض',
    '{message}': 'نص الرسالة/التبليغ',
  };

  // ============ الحصول على معرف الشركة الحالية ============
  static String? get _currentTenantId => _authService.currentTenantId;

  // ============ مسار التخزين في Firestore ============
  static String _getTemplatesPath(String tenantId) {
    return 'tenants/$tenantId/settings/whatsapp_templates';
  }

  // ============ تحويل نوع القالب إلى نص ============
  static String _templateTypeToString(WhatsAppTemplateType type) {
    switch (type) {
      case WhatsAppTemplateType.renewal:
        return 'renewal';
      case WhatsAppTemplateType.expiringSoon:
        return 'expiring_soon';
      case WhatsAppTemplateType.expired:
        return 'expired';
      case WhatsAppTemplateType.notification:
        return 'notification';
    }
  }

  // ============ حفظ قالب ============
  static Future<bool> saveTemplate({
    required WhatsAppTemplateType type,
    required String template,
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) {
        print('❌ لا يوجد tenant محدد');
        return false;
      }

      final docRef = _firestore.doc(_getTemplatesPath(tid));

      await docRef.set({
        _templateTypeToString(type): template,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ تم حفظ قالب ${templateNames[type]}');
      return true;
    } catch (e) {
      print('❌ خطأ في حفظ القالب: $e');
      return false;
    }
  }

  // ============ تحميل قالب ============
  static Future<String> getTemplate({
    required WhatsAppTemplateType type,
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) {
        return defaultTemplates[type]!;
      }

      final docRef = _firestore.doc(_getTemplatesPath(tid));
      final doc = await docRef.get();

      if (doc.exists) {
        final data = doc.data();
        final templateKey = _templateTypeToString(type);
        if (data != null && data[templateKey] != null) {
          return data[templateKey] as String;
        }
      }

      return defaultTemplates[type]!;
    } catch (e) {
      print('⚠️ خطأ في تحميل القالب، استخدام الافتراضي: $e');
      return defaultTemplates[type]!;
    }
  }

  // ============ تحميل جميع القوالب ============
  static Future<Map<WhatsAppTemplateType, String>> getAllTemplates({
    String? tenantId,
  }) async {
    final templates = <WhatsAppTemplateType, String>{};
    for (final type in WhatsAppTemplateType.values) {
      templates[type] = await getTemplate(type: type, tenantId: tenantId);
    }
    return templates;
  }

  // ============ إعادة تعيين قالب للافتراضي ============
  static Future<bool> resetToDefault({
    required WhatsAppTemplateType type,
    String? tenantId,
  }) async {
    return saveTemplate(
      type: type,
      template: defaultTemplates[type]!,
      tenantId: tenantId,
    );
  }

  // ============ إعادة تعيين جميع القوالب للافتراضي ============
  static Future<bool> resetAllToDefault({String? tenantId}) async {
    try {
      for (final type in WhatsAppTemplateType.values) {
        await resetToDefault(type: type, tenantId: tenantId);
      }
      return true;
    } catch (e) {
      print('❌ خطأ في إعادة تعيين القوالب: $e');
      return false;
    }
  }

  // ============ توليد رسالة من القالب ============
  static Future<String> generateMessage({
    required WhatsAppTemplateType type,
    required Map<String, String> variables,
    String? tenantId,
  }) async {
    String template = await getTemplate(type: type, tenantId: tenantId);
    variables.forEach((key, value) {
      template = template.replaceAll(key, value);
    });
    return template;
  }
}
