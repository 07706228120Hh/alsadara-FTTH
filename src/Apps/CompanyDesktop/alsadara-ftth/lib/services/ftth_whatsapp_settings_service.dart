import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'custom_auth_service.dart';
import 'ftth_settings_service.dart';

/// مزامنة إعدادات واتساب نظام FTTH لكل شركة.
///
/// مصدر الحقيقة = السيرفر (جدول CompanyFtthSettings/حقول واتساب)،
/// والـ SharedPreferences مجرّد cache محلي تقرأ منه الخدمات القائمة:
///   - whatsapp_bulk_system      (طريقة الإرسال الجماعي)
///   - whatsapp_renewal_system   (طريقة التجديد)
///   - n8n_webhook_url           (رابط n8n)
///
/// بهذا تتطابق كل الحاسبات تلقائياً، ولا تعود الإعدادات للقديم.
class FtthWhatsAppSettingsService {
  // نفس المفاتيح التي تقرأها WhatsAppSystemSettingsService و WhatsAppBulkSenderService
  static const String keyBulkSystem = 'whatsapp_bulk_system';
  static const String keyRenewalSystem = 'whatsapp_renewal_system';
  static const String keyWebhookUrl = 'n8n_webhook_url';

  static String? get _companyId => CustomAuthService().currentTenantId;

  /// يسحب إعدادات الواتساب من السيرفر إلى الـ cache المحلي.
  /// إن لم يكن على السيرفر قيمة بعد، يرفع القيمة المحلية الحالية (ترحيل ناعم لمرة واحدة).
  /// يُستدعى عند تسجيل الدخول وعند فتح شاشات إعدادات الواتساب.
  static Future<void> syncFromServer() async {
    final companyId = _companyId;
    if (companyId == null || companyId.isEmpty) return;

    try {
      final data = await FtthSettingsService.getSettings(companyId);
      if (data == null) return;

      final prefs = await SharedPreferences.getInstance();

      final serverBulk = (data['whatsappBulkSystem'] as String?)?.trim();
      final serverRenewal = (data['whatsappRenewalSystem'] as String?)?.trim();
      final serverWebhook = (data['whatsappN8nWebhookUrl'] as String?)?.trim();

      // ما ينقص على السيرفر نرفعه من المحلي (ترحيل الإعدادات القديمة لمرة واحدة)
      String? uploadBulk, uploadRenewal, uploadWebhook;

      if (serverBulk != null && serverBulk.isNotEmpty) {
        await prefs.setString(keyBulkSystem, serverBulk);
      } else {
        final local = prefs.getString(keyBulkSystem);
        if (local != null && local.isNotEmpty) uploadBulk = local;
      }

      if (serverRenewal != null && serverRenewal.isNotEmpty) {
        await prefs.setString(keyRenewalSystem, serverRenewal);
      } else {
        final local = prefs.getString(keyRenewalSystem);
        if (local != null && local.isNotEmpty) uploadRenewal = local;
      }

      if (serverWebhook != null && serverWebhook.isNotEmpty) {
        await prefs.setString(keyWebhookUrl, serverWebhook);
      } else {
        final local = prefs.getString(keyWebhookUrl);
        if (local != null && local.isNotEmpty) uploadWebhook = local;
      }

      if (uploadBulk != null ||
          uploadRenewal != null ||
          uploadWebhook != null) {
        await FtthSettingsService.saveWhatsAppSettings(
          companyId: companyId,
          bulkSystem: uploadBulk,
          renewalSystem: uploadRenewal,
          n8nWebhookUrl: uploadWebhook,
        );
      }

      debugPrint('✅ تمت مزامنة إعدادات واتساب FTTH من السيرفر');
    } catch (e) {
      // صامت — الخدمات تستمر بالـ cache المحلي عند تعذّر الاتصال
      debugPrint('⚠️ تعذّرت مزامنة إعدادات واتساب FTTH');
    }
  }

  /// يدفع طريقة الإرسال إلى السيرفر (بعد حفظها محلياً).
  static Future<void> pushSystems({
    required String bulkSystem,
    required String renewalSystem,
  }) async {
    final companyId = _companyId;
    if (companyId == null || companyId.isEmpty) return;
    await FtthSettingsService.saveWhatsAppSettings(
      companyId: companyId,
      bulkSystem: bulkSystem,
      renewalSystem: renewalSystem,
    );
  }

  /// يدفع رابط n8n إلى السيرفر (بعد حفظه محلياً).
  static Future<void> pushWebhookUrl(String url) async {
    final companyId = _companyId;
    if (companyId == null || companyId.isEmpty) return;
    await FtthSettingsService.saveWhatsAppSettings(
      companyId: companyId,
      n8nWebhookUrl: url,
    );
  }
}
