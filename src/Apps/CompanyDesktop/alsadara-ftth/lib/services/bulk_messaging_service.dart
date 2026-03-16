/// خدمة الإرسال الجماعي الموحدة
/// تدير إرسال رسائل واتساب جماعية عبر Server أو API
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../whatsapp/services/whatsapp_system_settings_service.dart';
import '../whatsapp/services/whatsapp_server_service.dart';
import 'whatsapp_bulk_sender_service.dart';
import 'whatsapp_templates_service.dart';
import 'company_settings_service.dart';
import 'custom_auth_service.dart';
import 'message_log_service.dart';

/// نموذج رسالة الإرسال الجماعي
class BulkMessage {
  final String phone;
  final String subscriberName;
  final String? subscriptionType;
  final String? planName;
  final String? fbg;
  final String? fat;
  final int? daysRemaining;
  final double? amount;
  final String? endDate;
  final String? offer;
  final String? customMessage;

  BulkMessage({
    required this.phone,
    required this.subscriberName,
    this.subscriptionType,
    this.planName,
    this.fbg,
    this.fat,
    this.daysRemaining,
    this.amount,
    this.endDate,
    this.offer,
    this.customMessage,
  });

  /// تحويل إلى Map للمتغيرات
  Map<String, String> toVariables() {
    return {
      '{customerName}': subscriberName,
      '{customerPhone}': phone,
      '{planName}': planName ?? '',
      '{fbg}': fbg ?? '',
      '{fat}': fat ?? '',
      '{days_left}': daysRemaining?.toString() ?? '',
      '{endDate}': endDate ?? '',
      '{offer}': offer ?? '',
      '{message}': customMessage ?? '',
      '{totalPrice}': amount?.toStringAsFixed(0) ?? '',
    };
  }
}

/// نتيجة الإرسال الجماعي
class BulkSendResult {
  final int totalSent;
  final int totalFailed;
  final List<String> failedPhones;
  final Duration totalTime;
  final String method; // 'Server' أو 'API'
  final String? errorMessage;
  final int retriesCount; // عدد مرات إعادة المحاولة
  final int retriedSuccessCount; // عدد الرسائل التي نجحت بعد إعادة المحاولة

  BulkSendResult({
    required this.totalSent,
    required this.totalFailed,
    required this.failedPhones,
    required this.totalTime,
    required this.method,
    this.errorMessage,
    this.retriesCount = 0,
    this.retriedSuccessCount = 0,
  });

  bool get isSuccess => totalFailed == 0 && errorMessage == null;
  double get successRate =>
      totalSent + totalFailed > 0 ? totalSent / (totalSent + totalFailed) : 0;

  /// تقرير ملخص
  String get summaryReport {
    final buffer = StringBuffer();
    buffer.writeln('📊 تقرير الإرسال الجماعي');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('✅ المرسل: $totalSent');
    buffer.writeln('❌ الفاشل: $totalFailed');
    buffer
        .writeln('📈 نسبة النجاح: ${(successRate * 100).toStringAsFixed(1)}%');
    buffer.writeln('⏱️ الوقت: ${_formatDuration(totalTime)}');
    buffer.writeln('🔧 الطريقة: $method');

    if (retriesCount > 0) {
      buffer.writeln('');
      buffer.writeln('🔄 إعادة المحاولة: $retriesCount مرة');
      buffer.writeln('✅ نجح بعد الإعادة: $retriedSuccessCount');
    }

    if (failedPhones.isNotEmpty && failedPhones.length <= 10) {
      buffer.writeln('');
      buffer.writeln('📵 الأرقام الفاشلة:');
      for (final phone in failedPhones) {
        buffer.writeln('  • $phone');
      }
    }

    return buffer.toString();
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes > 0) {
      return '${d.inMinutes} دقيقة و ${d.inSeconds % 60} ثانية';
    }
    return '${d.inSeconds} ثانية';
  }
}

/// أنواع قوالب الإرسال الجماعي
enum BulkTemplateType {
  expiringSoon, // تذكير قبل الانتهاء
  expired, // منتهي
  renewal, // تجديد
  notification, // تبليغ عام
}

/// خدمة الإرسال الجماعي الموحدة
class BulkMessagingService {
  static final CustomAuthService _authService = CustomAuthService();

  /// إرسال رسائل جماعية
  static Future<BulkSendResult> send({
    required List<BulkMessage> messages,
    required BulkTemplateType templateType,
    Function(int sent, int total, String? currentPhone)? onProgress,
    String? tenantId,
  }) async {
    final startTime = DateTime.now();
    final tid = tenantId ?? _authService.currentTenantId;

    if (tid == null) {
      return BulkSendResult(
        totalSent: 0,
        totalFailed: messages.length,
        failedPhones: messages.map((m) => m.phone).toList(),
        totalTime: Duration.zero,
        method: 'Unknown',
        errorMessage: 'لا يوجد tenant محدد',
      );
    }

    if (messages.isEmpty) {
      return BulkSendResult(
        totalSent: 0,
        totalFailed: 0,
        failedPhones: [],
        totalTime: Duration.zero,
        method: 'None',
      );
    }

    try {
      // 1. قراءة إعدادات النظام
      final systemSettings =
          await WhatsAppSystemSettingsService.getSystemSettings(tenantId: tid);
      final bulkSystem = systemSettings['bulk'] ?? WhatsAppSystem.server;

      debugPrint('🔧 نظام الإرسال المحدد: $bulkSystem');

      BulkSendResult result;

      // 2. اختيار طريقة الإرسال
      if (bulkSystem == WhatsAppSystem.server) {
        result = await _sendViaServer(
          messages: messages,
          templateType: templateType,
          tenantId: tid,
          onProgress: onProgress,
        );
      } else if (bulkSystem == WhatsAppSystem.api) {
        result = await _sendViaAPI(
          messages: messages,
          templateType: templateType,
          tenantId: tid,
          onProgress: onProgress,
        );
      } else {
        return BulkSendResult(
          totalSent: 0,
          totalFailed: messages.length,
          failedPhones: messages.map((m) => m.phone).toList(),
          totalTime: DateTime.now().difference(startTime),
          method: bulkSystem.toString(),
          errorMessage: 'نظام الإرسال غير مدعوم للإرسال الجماعي',
        );
      }

      // 3. تسجيل النتيجة في السجل اليومي
      await MessageLogService.logBulkResult(
        sent: result.totalSent,
        failed: result.totalFailed,
        failedPhones: result.failedPhones,
        tenantId: tid,
      );

      // 4. إرسال تقرير للمدير
      await _sendReportToManager(result, tid);

      return result;
    } catch (e) {
      debugPrint('❌ خطأ في الإرسال الجماعي');
      return BulkSendResult(
        totalSent: 0,
        totalFailed: messages.length,
        failedPhones: messages.map((m) => m.phone).toList(),
        totalTime: DateTime.now().difference(startTime),
        method: 'Error',
        errorMessage: e.toString(),
      );
    }
  }

  /// الحد الأقصى لإعادة المحاولة
  static const int _maxRetryAttempts = 2;
  /// عدد الفشل المتتالي قبل محاولة إعادة تشغيل الجلسة
  static const int _consecutiveFailuresThreshold = 3;

  /// التحقق من الاتصال وإعادة تشغيل الجلسة إذا لزم الأمر
  static Future<bool> _ensureConnection({
    required String tenantId,
    Function(int sent, int total, String? currentPhone)? onProgress,
  }) async {
    // فحص الحالة
    final status = await WhatsAppServerService.getStatus(tenantId);
    if (status['connected'] == true) return true;

    debugPrint('🔄 الواتساب غير متصل - إعادة تشغيل الجلسة...');
    onProgress?.call(-1, -1, '🔄 إعادة تشغيل جلسة الواتساب...');

    // إعادة تشغيل الجلسة (بدون QR)
    await WhatsAppServerService.restartSession(tenantId);

    // انتظار الاتصال (حتى 30 ثانية)
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final newStatus = await WhatsAppServerService.getStatus(tenantId);
      if (newStatus['connected'] == true) {
        debugPrint('✅ تم إعادة الاتصال بنجاح');
        onProgress?.call(-1, -1, '✅ تم إعادة الاتصال');
        await Future.delayed(const Duration(seconds: 2)); // استقرار
        return true;
      }
    }

    debugPrint('❌ فشل إعادة الاتصال بعد 30 ثانية');
    return false;
  }

  /// الإرسال عبر السيرفر
  static Future<BulkSendResult> _sendViaServer({
    required List<BulkMessage> messages,
    required BulkTemplateType templateType,
    required String tenantId,
    Function(int sent, int total, String? currentPhone)? onProgress,
  }) async {
    final startTime = DateTime.now();
    debugPrint('📤 بدء الإرسال عبر السيرفر...');

    // 1. التحقق من الاتصال أولاً
    final connected = await _ensureConnection(
      tenantId: tenantId,
      onProgress: onProgress,
    );
    if (!connected) {
      return BulkSendResult(
        totalSent: 0,
        totalFailed: messages.length,
        failedPhones: messages.map((m) => m.phone).toList(),
        totalTime: DateTime.now().difference(startTime),
        method: 'Server',
        errorMessage: 'الواتساب غير متصل - فشل إعادة الاتصال',
      );
    }

    // 2. قراءة القالب
    final waTemplateType = _toWhatsAppTemplateType(templateType);
    final template = await WhatsAppTemplatesService.getTemplate(
      type: waTemplateType,
      tenantId: tenantId,
    );

    // 3. قراءة الفاصل الزمني
    final delaySeconds =
        await WhatsAppServerService.getBulkDelayInSeconds(tenantId: tenantId);
    debugPrint('⏱️ الفاصل الزمني: $delaySeconds ثانية');

    // 4. بناء الرسائل
    final formattedMessages = <Map<String, String>>[];
    for (final msg in messages) {
      final messageText = _applyTemplate(template, msg.toVariables());
      formattedMessages.add({
        'phone': _formatPhoneForWhatsApp(msg.phone),
        'message': messageText,
      });
    }

    // 5. إرسال للسيرفر مع متابعة التقدم وإعادة المحاولة
    int sent = 0;
    int failed = 0;
    int consecutiveFailures = 0;
    int totalRetries = 0;
    int retriedSuccess = 0;
    final failedMessages = <Map<String, String>>[]; // الرسائل الفاشلة للإعادة

    for (int i = 0; i < formattedMessages.length; i++) {
      final msg = formattedMessages[i];
      onProgress?.call(sent + failed, messages.length, msg['phone']);

      try {
        final success = await WhatsAppServerService.sendMessage(
          tenantId: tenantId,
          phone: msg['phone']!,
          message: msg['message']!,
        );

        if (success) {
          sent++;
          consecutiveFailures = 0;
        } else {
          consecutiveFailures++;
          failedMessages.add(msg);

          // عند تجاوز حد الفشل المتتالي → إعادة تشغيل الجلسة
          if (consecutiveFailures >= _consecutiveFailuresThreshold) {
            debugPrint('⚠️ $consecutiveFailures فشل متتالي - فحص الاتصال...');
            final reconnected = await _ensureConnection(
              tenantId: tenantId,
              onProgress: onProgress,
            );
            if (reconnected) {
              consecutiveFailures = 0;
            } else {
              // فشل إعادة الاتصال — نضيف باقي الرسائل كفاشلة
              debugPrint('❌ فشل إعادة الاتصال - إيقاف الإرسال');
              for (int j = i + 1; j < formattedMessages.length; j++) {
                failedMessages.add(formattedMessages[j]);
              }
              break;
            }
          }
        }
      } catch (e) {
        consecutiveFailures++;
        failedMessages.add(msg);
        debugPrint('❌ فشل إرسال إلى ${msg['phone']}');

        if (consecutiveFailures >= _consecutiveFailuresThreshold) {
          debugPrint('⚠️ $consecutiveFailures فشل متتالي (exception) - فحص الاتصال...');
          final reconnected = await _ensureConnection(
            tenantId: tenantId,
            onProgress: onProgress,
          );
          if (reconnected) {
            consecutiveFailures = 0;
          } else {
            for (int j = i + 1; j < formattedMessages.length; j++) {
              failedMessages.add(formattedMessages[j]);
            }
            break;
          }
        }
      }

      // انتظار الفاصل الزمني (إلا للرسالة الأخيرة)
      if (i < formattedMessages.length - 1) {
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }

    // 6. إعادة محاولة إرسال الرسائل الفاشلة
    if (failedMessages.isNotEmpty) {
      debugPrint('🔄 إعادة محاولة ${failedMessages.length} رسالة فاشلة...');

      for (int attempt = 0; attempt < _maxRetryAttempts && failedMessages.isNotEmpty; attempt++) {
        totalRetries++;
        debugPrint('🔄 محاولة إعادة #${attempt + 1}...');

        // التأكد من الاتصال قبل كل محاولة إعادة
        final reconnected = await _ensureConnection(
          tenantId: tenantId,
          onProgress: onProgress,
        );
        if (!reconnected) {
          debugPrint('❌ فشل الاتصال - إيقاف إعادة المحاولة');
          break;
        }

        // انتظار قبل إعادة المحاولة
        await Future.delayed(const Duration(seconds: 3));

        final retryList = List<Map<String, String>>.from(failedMessages);
        failedMessages.clear();

        for (int i = 0; i < retryList.length; i++) {
          final msg = retryList[i];
          onProgress?.call(-1, retryList.length, '🔄 إعادة ${i + 1}/${retryList.length}: ${msg['phone']}');

          try {
            final success = await WhatsAppServerService.sendMessage(
              tenantId: tenantId,
              phone: msg['phone']!,
              message: msg['message']!,
            );

            if (success) {
              sent++;
              retriedSuccess++;
              debugPrint('✅ نجح إعادة الإرسال: ${msg['phone']}');
            } else {
              failedMessages.add(msg);
            }
          } catch (e) {
            failedMessages.add(msg);
            debugPrint('❌ فشل إعادة الإرسال: ${msg['phone']}');
          }

          if (i < retryList.length - 1) {
            await Future.delayed(Duration(seconds: delaySeconds));
          }
        }

        debugPrint('🔄 نتيجة المحاولة #${attempt + 1}: نجح $retriedSuccess، باقي ${failedMessages.length}');

        // إذا نجحت كل الرسائل لا حاجة لمحاولات أخرى
        if (failedMessages.isEmpty) break;
      }
    }

    failed = failedMessages.length;
    final finalFailedPhones = failedMessages.map((m) => m['phone']!).toList();

    onProgress?.call(messages.length, messages.length, null);

    return BulkSendResult(
      totalSent: sent,
      totalFailed: failed,
      failedPhones: finalFailedPhones,
      totalTime: DateTime.now().difference(startTime),
      method: 'Server',
      retriesCount: totalRetries,
      retriedSuccessCount: retriedSuccess,
    );
  }

  /// الإرسال عبر API (n8n)
  static Future<BulkSendResult> _sendViaAPI({
    required List<BulkMessage> messages,
    required BulkTemplateType templateType,
    required String tenantId,
    Function(int sent, int total, String? currentPhone)? onProgress,
  }) async {
    final startTime = DateTime.now();
    debugPrint('📤 بدء الإرسال عبر API...');

    // قراءة إعدادات API
    final webhookUrl =
        await WhatsAppBulkSenderService.getWebhookUrl();
    if (webhookUrl == null || webhookUrl.isEmpty) {
      return BulkSendResult(
        totalSent: 0,
        totalFailed: messages.length,
        failedPhones: messages.map((m) => m.phone).toList(),
        totalTime: DateTime.now().difference(startTime),
        method: 'API',
        errorMessage: 'رابط Webhook غير مُعد',
      );
    }

    // تحويل الرسائل لصيغة API
    final citizens = messages.map((msg) {
      return {
        'phone': _formatPhoneForWhatsApp(msg.phone),
        'name': msg.subscriberName,
        'template': _getAPITemplateName(templateType),
        'variables': {
          'name': msg.subscriberName,
          'days': msg.daysRemaining?.toString() ?? '',
          'plan': msg.planName ?? '',
        },
      };
    }).toList();

    onProgress?.call(0, messages.length, null);

    // إرسال عبر n8n
    // ملاحظة: يحتاج phoneNumberId و accessToken من الإعدادات
    final result = await WhatsAppBulkSenderService.sendBulkMessages(
      citizens: citizens,
      phoneNumberId: '', // سيتم قراءته من الإعدادات
      accessToken: '', // سيتم قراءته من الإعدادات
    );

    onProgress?.call(messages.length, messages.length, null);

    if (result['success'] == true) {
      final data = result['data'] as Map<String, dynamic>?;
      return BulkSendResult(
        totalSent: data?['totalSent'] ?? messages.length,
        totalFailed: data?['totalFailed'] ?? 0,
        failedPhones: List<String>.from(data?['failedPhones'] ?? []),
        totalTime: DateTime.now().difference(startTime),
        method: 'API',
      );
    } else {
      return BulkSendResult(
        totalSent: 0,
        totalFailed: messages.length,
        failedPhones: messages.map((m) => m.phone).toList(),
        totalTime: DateTime.now().difference(startTime),
        method: 'API',
        errorMessage: result['message'] ?? 'فشل في الإرسال',
      );
    }
  }

  /// إرسال تقرير للمدير
  static Future<void> _sendReportToManager(
      BulkSendResult result, String tenantId) async {
    try {
      // التحقق من تفعيل تقارير الإرسال الجماعي
      final isEnabled = await CompanySettingsService.isReportEnabled(
        'bulk_send',
        tenantId: tenantId,
      );

      if (!isEnabled) {
        debugPrint('📵 تقارير الإرسال الجماعي معطلة');
        return;
      }

      final managerPhone =
          await CompanySettingsService.getManagerWhatsApp(tenantId: tenantId);
      if (managerPhone == null || managerPhone.isEmpty) {
        debugPrint('📵 لا يوجد رقم واتساب للمدير');
        return;
      }

      // إرسال التقرير عبر السيرفر
      await WhatsAppServerService.sendMessage(
        tenantId: tenantId,
        phone: _formatPhoneForWhatsApp(managerPhone),
        message: result.summaryReport,
      );

      debugPrint('✅ تم إرسال التقرير للمدير');
    } catch (e) {
      debugPrint('❌ فشل إرسال التقرير للمدير');
    }
  }

  /// تحويل نوع القالب
  static WhatsAppTemplateType _toWhatsAppTemplateType(BulkTemplateType type) {
    switch (type) {
      case BulkTemplateType.expiringSoon:
        return WhatsAppTemplateType.expiringSoon;
      case BulkTemplateType.expired:
        return WhatsAppTemplateType.expired;
      case BulkTemplateType.renewal:
        return WhatsAppTemplateType.renewal;
      case BulkTemplateType.notification:
        return WhatsAppTemplateType.notification;
    }
  }

  /// الحصول على اسم قالب API
  static String _getAPITemplateName(BulkTemplateType type) {
    switch (type) {
      case BulkTemplateType.expiringSoon:
        return 'sadara_reminder';
      case BulkTemplateType.expired:
        return 'sadara_expired';
      case BulkTemplateType.renewal:
        return 'sadara_renewed';
      case BulkTemplateType.notification:
        return 'sadara_notification';
    }
  }

  /// تطبيق القالب على المتغيرات
  static String _applyTemplate(String template, Map<String, String> variables) {
    String result = template;
    variables.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
    return result;
  }

  /// تنسيق رقم الهاتف للواتساب
  static String _formatPhoneForWhatsApp(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');

    // إزالة 00 من البداية
    if (cleaned.startsWith('00')) {
      cleaned = cleaned.substring(2);
    }

    // تحويل 07 إلى 9647
    if (cleaned.startsWith('07')) {
      cleaned = '964${cleaned.substring(1)}';
    }

    // تحويل 7 إلى 9647
    if (cleaned.startsWith('7') && cleaned.length == 10) {
      cleaned = '964$cleaned';
    }

    return cleaned;
  }

  /// التحقق من جاهزية النظام للإرسال
  static Future<Map<String, dynamic>> checkReadiness({String? tenantId}) async {
    final tid = tenantId ?? CustomAuthService().currentTenantId;
    if (tid == null) {
      return {'ready': false, 'error': 'لا يوجد tenant محدد'};
    }

    final systemSettings =
        await WhatsAppSystemSettingsService.getSystemSettings(tenantId: tid);
    final bulkSystem = systemSettings['bulk'] ?? WhatsAppSystem.server;

    if (bulkSystem == WhatsAppSystem.server) {
      // التحقق من اتصال السيرفر
      final status = await WhatsAppServerService.getStatus(tid);
      if (status['connected'] != true) {
        return {
          'ready': false,
          'system': 'Server',
          'error': 'السيرفر غير متصل - يرجى ربط الواتساب أولاً',
        };
      }
      return {'ready': true, 'system': 'Server'};
    } else if (bulkSystem == WhatsAppSystem.api) {
      // التحقق من إعداد webhook
      final hasWebhook =
          await WhatsAppBulkSenderService.isWebhookConfigured();
      if (!hasWebhook) {
        return {
          'ready': false,
          'system': 'API',
          'error': 'رابط Webhook غير مُعد',
        };
      }
      return {'ready': true, 'system': 'API'};
    }

    return {
      'ready': false,
      'system': bulkSystem.toString(),
      'error': 'نظام غير مدعوم',
    };
  }
}
