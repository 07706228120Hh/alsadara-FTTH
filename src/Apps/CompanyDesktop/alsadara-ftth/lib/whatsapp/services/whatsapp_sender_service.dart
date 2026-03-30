import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'whatsapp_system_settings_service.dart';
import 'whatsapp_server_service.dart';
import 'whatsapp_permissions_service.dart' as perms;
import '../../services/custom_auth_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/whatsapp_business_service.dart';
import '../../services/whatsapp_conversation_service.dart';
import '../../ftth/whatsapp/whatsapp_bottom_window.dart';

/// خدمة إرسال الواتساب الموحدة
/// تختار النظام المناسب حسب إعدادات الشركة ونوع العملية
class WhatsAppSenderService {
  static final CustomAuthService _authService = CustomAuthService();

  /// الحصول على tenantId (Firebase أو VPS)
  static String? get _currentTenantId =>
      _authService.currentTenantId ?? VpsAuthService.instance.currentCompanyId;

  /// الحصول على userId (Firebase أو VPS)
  static String? get _currentUserId =>
      CustomAuthService.currentUser?.id ??
      VpsAuthService.instance.currentUser?.id;

  // ============ إرسال رسالة (يختار النظام تلقائياً) ============
  /// إرسال رسالة واتساب باستخدام النظام المحدد للعملية
  static Future<SendResult> sendMessage({
    required String phone,
    required String message,
    required WhatsAppOperationType operationType,
    BuildContext? context, // مطلوب للتطبيق العادي
    bool skipPermissionCheck =
        false, // تجاوز فحص الصلاحيات (للتجديد من صفحة المشترك)
  }) async {
    try {
      // الحصول على معلومات المستخدم
      final tenantId = _currentTenantId;
      final userId = _currentUserId;

      if (tenantId == null || userId == null) {
        return SendResult(
          success: false,
          error: 'لم يتم تسجيل الدخول',
          system: null,
        );
      }

      // تحديد النظام المستخدم
      final system = await WhatsAppSystemSettingsService.getSystemForOperation(
        operationType,
      );

      // التحقق من الصلاحيات (إلا إذا تم تجاوزه)
      if (!skipPermissionCheck) {
        // تحديد نوع الصلاحية المطلوبة
        final perms.WhatsAppUserPermission permissionType =
            operationType == WhatsAppOperationType.bulk
                ? perms.WhatsAppUserPermission.bulkSend
                : perms.WhatsAppUserPermission.sendRenewal;

        // التحقق من الصلاحيات
        final permissionCheck =
            await perms.WhatsAppPermissionsService.canUserSendMessage(
          tenantId: tenantId,
          userId: userId,
          system: _convertToPermissionSystem(system),
          messageType: permissionType,
        );

        if (!permissionCheck.allowed) {
          return SendResult(
            success: false,
            error: permissionCheck.reason,
            system: null,
          );
        }
      }

      // التحقق من توفر النظام
      final isAvailable =
          await WhatsAppSystemSettingsService.isSystemAvailable(system);

      if (!isAvailable &&
          system != WhatsAppSystem.app &&
          system != WhatsAppSystem.web) {
        return SendResult(
          success: false,
          error:
              'النظام المحدد (${WhatsAppSystemSettingsService.systemNames[system]}) غير مفعّل',
          system: system,
        );
      }

      // الإرسال حسب النظام
      switch (system) {
        case WhatsAppSystem.app:
          return await _sendViaApp(phone, message, context);

        case WhatsAppSystem.web:
          return await _sendViaWeb(phone, message, context);

        case WhatsAppSystem.server:
          return await _sendViaServer(phone, message);

        case WhatsAppSystem.api:
          return await _sendViaApi(phone, message);
      }
    } catch (e) {
      return SendResult(
        success: false,
        error: 'خطأ غير متوقع',
        system: null,
      );
    }
  }

  // ============ إرسال عبر التطبيق العادي ============
  static Future<SendResult> _sendViaApp(
    String phone,
    String message,
    BuildContext? context,
  ) async {
    try {
      final cleanPhone = _cleanPhoneNumber(phone);

      final whatsappUrl = 'whatsapp://send?phone=$cleanPhone';
      final uri = Uri.parse(whatsappUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return SendResult(
          success: true,
          message: 'تم فتح تطبيق الواتساب',
          system: WhatsAppSystem.app,
        );
      } else {
        final webUrl = 'https://wa.me/$cleanPhone';
        final webUri = Uri.parse(webUrl);

        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
          return SendResult(
            success: true,
            message: 'تم فتح واتساب ويب',
            system: WhatsAppSystem.app,
          );
        }

        return SendResult(
          success: false,
          error: 'تطبيق الواتساب غير مثبت على الجهاز',
          system: WhatsAppSystem.app,
        );
      }
    } catch (e) {
      return SendResult(
        success: false,
        error: 'فشل فتح تطبيق الواتساب',
        system: WhatsAppSystem.app,
      );
    }
  }

  // ============ إرسال عبر واتساب ويب (WebView) ============
  static Future<SendResult> _sendViaWeb(
    String phone,
    String message,
    BuildContext? context,
  ) async {
    try {
      if (context == null) {
        return SendResult(
          success: false,
          error: 'السياق غير متوفر لفتح واتساب ويب',
          system: WhatsAppSystem.web,
        );
      }

      final cleanPhone = _cleanPhoneNumber(phone);

      // فتح واتساب ويب في نافذة داخلية مع إرسال تلقائي
      WhatsAppBottomWindow.showBottomWindow(
        context,
        cleanPhone,
        message,
        autoSend: true,
      );

      return SendResult(
        success: true,
        message: 'جاري الإرسال عبر واتساب ويب',
        system: WhatsAppSystem.web,
      );
    } catch (e) {
      return SendResult(
        success: false,
        error: 'فشل فتح واتساب ويب',
        system: WhatsAppSystem.web,
      );
    }
  }

  // ============ إرسال عبر السيرفر ============
  static Future<SendResult> _sendViaServer(String phone, String message) async {
    try {
      final tenantId = _currentTenantId;
      if (tenantId == null) {
        return SendResult(
          success: false,
          error: 'لا يوجد tenant محدد',
          system: WhatsAppSystem.server,
        );
      }

      final cleanPhone = _cleanPhoneNumber(phone);
      final success = await WhatsAppServerService.sendMessage(
        phone: cleanPhone,
        message: message,
        tenantId: tenantId,
      );

      // تسجيل الرسالة في PostgreSQL
      if (success) {
        WhatsAppConversationService.sendMessage(
          phoneNumber: cleanPhone,
          message: message,
        ).catchError((_) {});
      }

      return SendResult(
        success: success,
        message: success ? 'تم الإرسال بنجاح' : null,
        error: !success ? 'فشل الإرسال عبر السيرفر' : null,
        system: WhatsAppSystem.server,
      );
    } catch (e) {
      return SendResult(
        success: false,
        error: 'خطأ في الإرسال عبر السيرفر',
        system: WhatsAppSystem.server,
      );
    }
  }

  // ============ إرسال عبر API ============
  static Future<SendResult> _sendViaApi(String phone, String message) async {
    try {
      final cleanPhone = _cleanPhoneNumber(phone);
      final result = await WhatsAppBusinessService.sendTextMessage(
        to: cleanPhone,
        message: message,
      );

      if (result == null) {
        return SendResult(
          success: false,
          error: 'فشل الإرسال عبر API - لم يتم إعداد API',
          system: WhatsAppSystem.api,
        );
      }

      // Meta API تُرجع messages[] عند النجاح (لا يوجد حقل success)
      final messageId = (result['messages'] as List?)?.firstOrNull?['id']?.toString();

      // تسجيل الرسالة في PostgreSQL
      WhatsAppConversationService.sendMessage(
        phoneNumber: cleanPhone,
        message: message,
      ).catchError((_) {});

      return SendResult(
        success: true,
        message: 'تم الإرسال بنجاح عبر API',
        messageId: messageId,
        system: WhatsAppSystem.api,
      );
    } catch (e) {
      return SendResult(
        success: false,
        error: 'خطأ في الإرسال عبر API',
        system: WhatsAppSystem.api,
      );
    }
  }

  // ============ إرسال مباشر عبر التطبيق (بدون تحقق من الإعدادات) ============
  static Future<bool> openWhatsAppApp({
    required String phone,
    String? message,
  }) async {
    try {
      final cleanPhone = _cleanPhoneNumber(phone);
      final encodedMessage =
          message != null ? Uri.encodeComponent(message) : '';

      final url = message != null && message.isNotEmpty
          ? 'whatsapp://send?phone=$cleanPhone&text=$encodedMessage'
          : 'whatsapp://send?phone=$cleanPhone';

      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }

      // تجربة wa.me
      final webUrl = message != null && message.isNotEmpty
          ? 'https://wa.me/$cleanPhone?text=$encodedMessage'
          : 'https://wa.me/$cleanPhone';

      final webUri = Uri.parse(webUrl);
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return true;
      }

      return false;
    } catch (e) {
      print('❌ خطأ في فتح واتساب');
      return false;
    }
  }

  // ============ تنظيف رقم الهاتف ============
  static String _cleanPhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');

    // إذا بدأ بـ 0، استبدله بـ 964 (العراق)
    if (cleaned.startsWith('0')) {
      cleaned = '964${cleaned.substring(1)}';
    }

    // إذا لم يبدأ برمز الدولة، أضف 964
    if (!cleaned.startsWith('964') && cleaned.length <= 10) {
      cleaned = '964$cleaned';
    }

    return cleaned;
  }

  // ============ تحويل enum النظام للصلاحيات ============
  static perms.WhatsAppSystem _convertToPermissionSystem(
      WhatsAppSystem system) {
    switch (system) {
      case WhatsAppSystem.app:
        return perms.WhatsAppSystem.normal;
      case WhatsAppSystem.web:
        return perms.WhatsAppSystem.normal; // واتساب ويب يُعامل كالعادي
      case WhatsAppSystem.server:
        return perms.WhatsAppSystem.server;
      case WhatsAppSystem.api:
        return perms.WhatsAppSystem.api;
    }
  }

  // ============ التحقق من توفر واتساب ============
  static Future<bool> isWhatsAppInstalled() async {
    try {
      final uri = Uri.parse('whatsapp://send?phone=0');
      return await canLaunchUrl(uri);
    } catch (e) {
      return false;
    }
  }
}

/// نتيجة الإرسال
class SendResult {
  final bool success;
  final String? message;
  final String? error;
  final String? messageId;
  final WhatsAppSystem? system;

  SendResult({
    required this.success,
    this.message,
    this.error,
    this.messageId,
    this.system,
  });

  @override
  String toString() {
    if (success) {
      return '✅ $message (${WhatsAppSystemSettingsService.systemNames[system]})';
    } else {
      return '❌ $error';
    }
  }
}
