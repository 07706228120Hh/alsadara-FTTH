import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'thermal_printer_service.dart';

class PrintTemplateStorage {
  static const _key = 'print_template';

  // القالب الافتراضي
  static PrintTemplate get defaultTemplate => PrintTemplate(
    companyName: 'شركة الصدارة',
    companySubtitle: 'المشغل الرسمي للمشروع الوطني',
    footerMessage: 'شكراً لاختياركم شركة الصدارة',
    contactInfo: 'للاستفسار: 07744077077',
    showCustomerInfo: true,
    showServiceDetails: true,
    showPaymentDetails: true,
    showAdditionalInfo: false,
    showContactInfo: true,
  // تم تعديل الحجم الافتراضي للخط من 12 إلى 10 بناءً على طلب المستخدم
  fontSize: 10.0,
    boldHeaders: true,
  );

  static Future<void> saveTemplate(PrintTemplate template) async {
    final prefs = await SharedPreferences.getInstance();
    final templateData = {
      'companyName': template.companyName,
      'companySubtitle': template.companySubtitle,
      'footerMessage': template.footerMessage,
      'contactInfo': template.contactInfo,
      'showCustomerInfo': template.showCustomerInfo,
      'showServiceDetails': template.showServiceDetails,
      'showPaymentDetails': template.showPaymentDetails,
      'showAdditionalInfo': template.showAdditionalInfo,
      'showContactInfo': template.showContactInfo,
      'fontSize': template.fontSize,
      'boldHeaders': template.boldHeaders,
    };
    await prefs.setString(_key, json.encode(templateData));
  }

  static Future<PrintTemplate> loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final templateString = prefs.getString(_key);

    if (templateString == null) {
      return defaultTemplate;
    }

    try {
      final templateData = json.decode(templateString) as Map<String, dynamic>;
      return PrintTemplate(
        companyName: templateData['companyName'] ?? defaultTemplate.companyName,
        companySubtitle: templateData['companySubtitle'] ?? defaultTemplate.companySubtitle,
        footerMessage: templateData['footerMessage'] ?? defaultTemplate.footerMessage,
        contactInfo: templateData['contactInfo'] ?? defaultTemplate.contactInfo,
        showCustomerInfo: templateData['showCustomerInfo'] ?? defaultTemplate.showCustomerInfo,
        showServiceDetails: templateData['showServiceDetails'] ?? defaultTemplate.showServiceDetails,
        showPaymentDetails: templateData['showPaymentDetails'] ?? defaultTemplate.showPaymentDetails,
        showAdditionalInfo: templateData['showAdditionalInfo'] ?? defaultTemplate.showAdditionalInfo,
        showContactInfo: templateData['showContactInfo'] ?? defaultTemplate.showContactInfo,
        fontSize: (templateData['fontSize'] ?? defaultTemplate.fontSize).toDouble(),
        boldHeaders: templateData['boldHeaders'] ?? defaultTemplate.boldHeaders,
      );
    } catch (e) {
      return defaultTemplate;
    }
  }
}
