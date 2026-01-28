import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة إرسال رسائل WhatsApp جماعية عبر n8n
class WhatsAppBulkSenderService {
  static const String _webhookUrlKey = 'n8n_webhook_url';

  /// حفظ رابط webhook
  static Future<void> saveWebhookUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webhookUrlKey, url);
    debugPrint('✅ تم حفظ رابط Webhook');
  }

  /// قراءة رابط webhook
  static Future<String?> getWebhookUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_webhookUrlKey);
  }

  /// التحقق من وجود webhook URL
  static Future<bool> isWebhookConfigured() async {
    final url = await getWebhookUrl();
    return url != null && url.isNotEmpty;
  }

  /// إرسال رسائل WhatsApp لمجموعة مواطنين
  ///
  /// المعاملات:
  /// - [citizens]: قائمة المواطنين مع بياناتهم
  /// - [phoneNumberId]: رقم الهاتف من WhatsApp Business API
  /// - [accessToken]: التوكن من Meta Business
  /// - [defaultMessage]: رسالة افتراضية (اختياري)
  static Future<Map<String, dynamic>> sendBulkMessages({
    required List<Map<String, dynamic>> citizens,
    required String phoneNumberId,
    required String accessToken,
    String? defaultMessage,
  }) async {
    try {
      debugPrint('📤 بدء إرسال رسائل جماعية لـ ${citizens.length} مواطن...');

      // قراءة webhook URL من الإعدادات
      final webhookUrl = await getWebhookUrl();
      if (webhookUrl == null || webhookUrl.isEmpty) {
        return {
          'success': false,
          'message': 'يرجى إعداد رابط Webhook من الإعدادات أولاً',
        };
      }

      final data = {
        'whatsappPhoneNumberId': phoneNumberId,
        'accessToken': accessToken,
        if (defaultMessage != null) 'defaultMessage': defaultMessage,
        'citizens': citizens,
      };

      debugPrint('📡 إرسال البيانات إلى n8n...');
      debugPrint('   URL: $webhookUrl');
      debugPrint('   البيانات المرسلة: ${jsonEncode(data)}');

      final response = await http.post(
        Uri.parse(webhookUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      debugPrint('📥 استلام رد من n8n:');
      debugPrint('   Status Code: ${response.statusCode}');
      debugPrint('   Response Body: ${response.body}');

      if (response.statusCode == 200) {
        // التحقق من أن الرد ليس فارغاً
        if (response.body.isEmpty) {
          debugPrint('⚠️ الرد فارغ من n8n');
          return {
            'success': false,
            'message': 'استجابة فارغة من الخادم. تحقق من إعدادات n8n workflow',
          };
        }

        try {
          final result = jsonDecode(response.body);

          // التحقق من وجود بيانات النتائج
          if (result is Map) {
            final resultMap = result as Map<String, dynamic>;
            debugPrint('✅ اكتمل الإرسال:');
            debugPrint(
                '   - عدد الرسائل المرسلة: ${resultMap['totalSent'] ?? 'غير محدد'}');
            debugPrint(
                '   - عدد الفاشلة: ${resultMap['totalFailed'] ?? 'غير محدد'}');
            debugPrint(
                '   - نسبة النجاح: ${resultMap['successRate'] ?? 'غير محدد'}');
            debugPrint('   ℹ️ الرسائل يتم حفظها في Firebase عبر n8n workflow');

            return {
              'success': true,
              'data': resultMap,
            };
          } else {
            debugPrint('⚠️ تنسيق الرد غير متوقع');
            return {
              'success': false,
              'message': 'تنسيق استجابة غير صحيح من الخادم',
            };
          }
        } catch (e) {
          debugPrint('❌ خطأ في تحليل JSON: $e');
          debugPrint('   الرد الخام: ${response.body}');
          return {
            'success': false,
            'message': 'خطأ في تحليل استجابة الخادم: ${response.body}',
          };
        }
      } else {
        debugPrint('❌ خطأ في الإرسال: ${response.statusCode}');
        debugPrint('   الرد: ${response.body}');

        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}',
          'message': 'خطأ من الخادم: ${response.body}',
        };
      }
    } catch (e) {
      debugPrint('❌ خطأ في الاتصال: $e');
      return {
        'success': false,
        'error': 'Connection error',
        'message': e.toString(),
      };
    }
  }

  /// إرسال رسائل باستخدام قوالب WhatsApp المعتمدة
  ///
  /// المعاملات:
  /// - [templateType]: نوع القالب (sadara_reminder, sadara_renewed, sadara_expired)
  /// - [recipients]: قائمة المستلمين مع بياناتهم
  /// - [phoneNumberId]: رقم الهاتف من WhatsApp Business API
  /// - [accessToken]: التوكن من Meta Business
  /// - [offerText]: نص العرض (للقالب sadara_expired)
  /// - [contactNumbers]: أرقام التواصل
  /// - [location]: الموقع
  static Future<Map<String, dynamic>> sendTemplateMessages({
    required String templateType,
    required List<Map<String, dynamic>> recipients,
    required String phoneNumberId,
    required String accessToken,
    String? offerText,
    String? contactNumbers,
    String? location,
  }) async {
    try {
      debugPrint(
          '📤 بدء إرسال رسائل قالب $templateType لـ ${recipients.length} مستلم...');

      // قراءة webhook URL من الإعدادات
      final webhookUrl = await getWebhookUrl();
      if (webhookUrl == null || webhookUrl.isEmpty) {
        return {
          'success': false,
          'message': 'يرجى إعداد رابط Webhook من الإعدادات أولاً',
        };
      }

      // تحويل الرابط إلى رابط القوالب
      final templateWebhookUrl = webhookUrl.replaceAll(
        'send-whatsapp-messages',
        'send-whatsapp-template',
      );

      final data = {
        'templateType': templateType,
        'recipients': recipients,
        'phoneNumberId': phoneNumberId,
        'accessToken': accessToken,
        'offerText': offerText ?? 'لدينا عروض مميزة لك!',
        'contactNumbers': contactNumbers ?? '07705210210 - 07717727720',
        'location': location ??
            'بغداد/حي الامانة https://maps.app.goo.gl/hfYqRMZNr2qYnsV3A',
      };

      debugPrint('📡 إرسال البيانات إلى n8n...');
      debugPrint('   URL: $templateWebhookUrl');
      debugPrint('   Template Type: $templateType');
      debugPrint('   Recipients Count: ${recipients.length}');

      final response = await http
          .post(
            Uri.parse(templateWebhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 30)); // timeout قصير للرد الفوري

      debugPrint('📥 استلام رد من n8n:');
      debugPrint('   Status Code: ${response.statusCode}');
      debugPrint('   Response Body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return {
            'success': false,
            'message': 'استجابة فارغة من الخادم. تحقق من إعدادات n8n workflow',
          };
        }

        try {
          final result = jsonDecode(response.body);

          if (result is Map) {
            final resultMap = result as Map<String, dynamic>;

            // التحقق من نوع الرد (فوري أو نهائي)
            final status = resultMap['status']?.toString();

            if (status == 'processing') {
              // رد Fire-and-Forget - الإرسال يتم في الخلفية
              debugPrint('🚀 تم استلام الطلب - الإرسال يتم في الخلفية');
              debugPrint('   - Batch ID: ${resultMap['batchId']}');
              debugPrint('   - Total: ${resultMap['total']}');

              return {
                'success': true,
                'isAsync': true,
                'data': resultMap,
                'message': 'تم إرسال الطلب بنجاح. سيتم الإرسال في الخلفية.',
              };
            } else {
              // رد تقليدي - الإرسال اكتمل
              debugPrint('✅ اكتمل الإرسال:');
              debugPrint(
                  '   - عدد الرسائل المرسلة: ${resultMap['totalSent'] ?? resultMap['sent'] ?? 'غير محدد'}');
              debugPrint(
                  '   - عدد الفاشلة: ${resultMap['totalFailed'] ?? resultMap['failed'] ?? 'غير محدد'}');
              debugPrint(
                  '   - نسبة النجاح: ${resultMap['successRate'] ?? resultMap['rate'] ?? 'غير محدد'}');

              return {
                'success': true,
                'isAsync': false,
                'data': resultMap,
              };
            }
          } else {
            return {
              'success': false,
              'message': 'تنسيق استجابة غير صحيح من الخادم',
            };
          }
        } catch (e) {
          debugPrint('❌ خطأ في تحليل JSON: $e');
          return {
            'success': false,
            'message': 'خطأ في تحليل استجابة الخادم: ${response.body}',
          };
        }
      } else {
        debugPrint('❌ خطأ في الإرسال: ${response.statusCode}');
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}',
          'message': 'خطأ من الخادم: ${response.body}',
        };
      }
    } catch (e) {
      debugPrint('❌ خطأ في الاتصال: $e');
      return {
        'success': false,
        'error': 'Connection error',
        'message': e.toString(),
      };
    }
  }

  /// إرسال رسالة واحدة مخصصة
  static Future<Map<String, dynamic>> sendSingleMessage({
    required String name,
    required String phoneNumber,
    required String message,
    required String phoneNumberId,
    required String accessToken,
  }) async {
    return sendBulkMessages(
      citizens: [
        {
          'name': name,
          'phoneNumber': phoneNumber,
          'message': message,
        }
      ],
      phoneNumberId: phoneNumberId,
      accessToken: accessToken,
    );
  }

  /// إرسال تذكير قبل انتهاء الاشتراك
  static Future<Map<String, dynamic>> sendExpiryReminders({
    required List<Map<String, dynamic>> subscribers,
    required String phoneNumberId,
    required String accessToken,
  }) async {
    return sendTemplateMessages(
      templateType: 'sadara_reminder',
      recipients: subscribers,
      phoneNumberId: phoneNumberId,
      accessToken: accessToken,
    );
  }

  /// إرسال إشعار تجديد ناجح
  static Future<Map<String, dynamic>> sendRenewalConfirmations({
    required List<Map<String, dynamic>> subscribers,
    required String phoneNumberId,
    required String accessToken,
  }) async {
    return sendTemplateMessages(
      templateType: 'sadara_renewed',
      recipients: subscribers,
      phoneNumberId: phoneNumberId,
      accessToken: accessToken,
    );
  }

  /// إرسال عرض للمشتركين المنتهية اشتراكاتهم
  static Future<Map<String, dynamic>> sendExpiredOffers({
    required List<Map<String, dynamic>> subscribers,
    required String phoneNumberId,
    required String accessToken,
    required String offerText,
  }) async {
    return sendTemplateMessages(
      templateType: 'sadara_expired',
      recipients: subscribers,
      phoneNumberId: phoneNumberId,
      accessToken: accessToken,
      offerText: offerText,
    );
  }
}
