import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة WhatsApp Business API للإرسال عبر Meta API
class WhatsAppBusinessService {
  // معلومات API من Meta
  static const String _baseUrl = 'https://graph.facebook.com';
  static const String _apiVersion = 'v21.0'; // آخر إصدار

  // مفاتيح التخزين المحلي
  static const String _userTokenKey = 'whatsapp_user_token';
  static const String _appTokenKey = 'whatsapp_app_token';
  static const String _phoneNumberIdKey = 'whatsapp_phone_number_id';
  static const String _businessAccountIdKey = 'whatsapp_business_account_id';
  static const String _webhookVerifyTokenKey = 'whatsapp_webhook_verify_token';
  static const String _n8nApiTokenKey = 'n8n_api_token';

  // Webhook Verify Token (للـ n8n webhook verification)
  // يستخدم في Meta Webhook Configuration عند ربط webhook URL
  static const String webhookVerifyToken =
      '4bZXa4hJ6whfqWf9JsyNjQpHzaBZOxZA1A81SBGH4ce90e2e';

  // n8n API Token (JWT Token للوصول إلى n8n API)
  // يستخدم للتفاعل مع n8n workflows والحصول على البيانات
  static const String n8nApiToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5ZDFmZTVkNy04OTczLTQ0ZmQtYjQzNi0yNWRhMTUyN2YzOTYiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwiaWF0IjoxNzY1OTQ3NjgzfQ.IjycTVGdoGHjM9xvVO1C2xyeaa0f2v09tpwSXOpq298';

  /// الحصول على جميع إعدادات واجهة WhatsApp
  static Future<Map<String, String>> getConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'userToken': prefs.getString(_userTokenKey) ?? '',
      'appToken': prefs.getString(_appTokenKey) ?? '',
      'phoneNumberId': prefs.getString(_phoneNumberIdKey) ?? '',
      'businessAccountId': prefs.getString(_businessAccountIdKey) ?? '',
      'webhookVerifyToken': prefs.getString(_webhookVerifyTokenKey) ?? '',
      'n8nApiToken': prefs.getString(_n8nApiTokenKey) ?? '',
    };
  }

  /// حفظ User Token (Access Token)
  static Future<void> saveUserToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userTokenKey, token);
      debugPrint('✅ تم حفظ User Token بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ User Token');
    }
  }

  /// حفظ App Token
  static Future<void> saveAppToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_appTokenKey, token);
      debugPrint('✅ تم حفظ App Token بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ App Token');
    }
  }

  /// حفظ Phone Number ID
  static Future<void> savePhoneNumberId(String phoneNumberId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_phoneNumberIdKey, phoneNumberId);
      debugPrint('✅ تم حفظ Phone Number ID بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ Phone Number ID');
    }
  }

  /// حفظ Business Account ID
  static Future<void> saveBusinessAccountId(String accountId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_businessAccountIdKey, accountId);
      debugPrint('✅ تم حفظ Business Account ID بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ Business Account ID');
    }
  }

  /// حفظ Webhook Verify Token
  static Future<void> saveWebhookVerifyToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_webhookVerifyTokenKey, token);
      debugPrint('✅ تم حفظ Webhook Verify Token بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ Webhook Verify Token');
    }
  }

  /// حفظ n8n API Token
  static Future<void> saveN8nApiToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_n8nApiTokenKey, token);
      debugPrint('✅ تم حفظ n8n API Token بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في حفظ n8n API Token');
    }
  }

  /// حفظ جميع بيانات الاعتماد مرة واحدة
  static Future<void> saveCredentials({
    required String userToken,
    String? appToken,
    required String phoneNumberId,
    String? businessAccountId,
    String? webhookVerifyToken,
    String? n8nApiToken,
  }) async {
    await saveUserToken(userToken);
    if (appToken != null) await saveAppToken(appToken);
    await savePhoneNumberId(phoneNumberId);
    if (businessAccountId != null) {
      await saveBusinessAccountId(businessAccountId);
    }
    if (webhookVerifyToken != null) {
      await saveWebhookVerifyToken(webhookVerifyToken);
    }
    if (n8nApiToken != null) {
      await saveN8nApiToken(n8nApiToken);
    }
    debugPrint('✅ تم حفظ جميع بيانات الاعتماد بنجاح');
  }

  /// جلب User Token المحفوظ
  static Future<String?> getUserToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userTokenKey);
  }

  /// جلب App Token المحفوظ
  static Future<String?> getAppToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_appTokenKey);
  }

  /// جلب Phone Number ID المحفوظ
  static Future<String?> getPhoneNumberId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneNumberIdKey);
  }

  /// جلب Access Token المحفوظ (نفس User Token)
  static Future<String?> getAccessToken() async {
    return getUserToken();
  }

  /// جلب Business Account ID المحفوظ
  static Future<String?> getBusinessAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_businessAccountIdKey);
  }

  /// جلب Webhook Verify Token المحفوظ
  static Future<String?> getWebhookVerifyToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_webhookVerifyTokenKey) ?? webhookVerifyToken;
  }

  /// جلب n8n API Token المحفوظ
  static Future<String?> getN8nApiToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_n8nApiTokenKey) ?? n8nApiToken;
  }

  /// التحقق من اكتمال الإعدادات
  static Future<bool> isConfigured() async {
    final userToken = await getUserToken();
    final phoneNumberId = await getPhoneNumberId();
    return userToken != null && phoneNumberId != null;
  }

  /// إرسال رسالة نصية
  static Future<Map<String, dynamic>?> sendTextMessage({
    required String to,
    required String message,
  }) async {
    try {
      if (!await isConfigured()) {
        debugPrint(
            '❌ WhatsApp Business API غير مُعد - يرجى حفظ التوكنات أولاً');
        return null;
      }

      final userToken = await getUserToken();
      final phoneNumberId = await getPhoneNumberId();

      // تنظيف رقم الهاتف (إزالة المسافات والرموز)
      String cleanPhone = to.replaceAll(RegExp(r'[^\d+]'), '');
      if (!cleanPhone.startsWith('+')) {
        if (cleanPhone.startsWith('964')) {
          cleanPhone = '+$cleanPhone';
        } else if (cleanPhone.startsWith('0')) {
          cleanPhone = '+964${cleanPhone.substring(1)}';
        } else {
          cleanPhone = '+964$cleanPhone';
        }
      }

      debugPrint('📤 إرسال رسالة WhatsApp إلى: $cleanPhone');

      final url = Uri.parse('$_baseUrl/$_apiVersion/$phoneNumberId/messages');

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $userToken',
            },
            body: jsonEncode({
              'messaging_product': 'whatsapp',
              'recipient_type': 'individual',
              'to': cleanPhone,
              'type': 'text',
              'text': {
                'preview_url': false,
                'body': message,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 استجابة WhatsApp API: ${response.statusCode}');
      debugPrint('📥 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ تم إرسال الرسالة بنجاح');
        debugPrint('Message ID: ${data['messages']?[0]?['id']}');
        return data;
      } else {
        debugPrint('❌ فشل في إرسال الرسالة - الحالة: ${response.statusCode}');
        debugPrint('📥 Response Body: ${response.body}');

        try {
          final error = jsonDecode(response.body);
          final errorMessage = error['error']?['message'] ?? 'Unknown error';
          final errorCode = error['error']?['code'];
          final errorType = error['error']?['type'];
          final errorSubcode = error['error']?['error_subcode'];

          debugPrint('❌ تفاصيل الخطأ:');
          debugPrint('   Message: $errorMessage');
          debugPrint('   Code: $errorCode');
          debugPrint('   Type: $errorType');
          debugPrint('   Subcode: $errorSubcode');

          // تحليل الأخطاء الشائعة
          if (errorCode == 100) {
            debugPrint('💡 الحل: مشكلة في Phone Number ID أو الصلاحيات');
            debugPrint('   Phone Number ID: $phoneNumberId');
            if (errorSubcode == 33) {
              debugPrint(
                  '   ❌ Phone Number ID غير موجود أو لا تملك صلاحية الوصول إليه');
              debugPrint('   ⚠️ تأكد من:');
              debugPrint('      1. Phone Number ID صحيح من WhatsApp Manager');
              debugPrint(
                  '      2. Token من نفس Business Account الذي يحتوي على Phone Number');
              debugPrint(
                  '      3. Token يملك الصلاحيات: whatsapp_business_messaging & whatsapp_business_management');
            }
          } else if (errorCode == 131026) {
            debugPrint(
                '💡 الحل: الرسالة بحاجة إلى قالب معتمد (Template). لا يمكن إرسال رسائل نصية عادية إلا بعد 24 ساعة من رد المستلم.');
          } else if (errorCode == 131047 || errorCode == 131048) {
            debugPrint(
                '💡 الحل: الرقم $cleanPhone غير متاح على WhatsApp أو غير مسجل كـ recipient.');
          } else if (errorCode == 131031) {
            debugPrint('💡 الحل: رقم المستلم غير صحيح أو التنسيق خاطئ.');
          } else if (errorCode == 80007) {
            debugPrint('💡 الحل: تم تجاوز حد الإرسال. انتظر قليلاً.');
          } else if (errorCode == 368) {
            debugPrint(
                '💡 الحل: الرسالة محظورة مؤقتاً. قد يكون هناك انتهاك للسياسات.');
          }
        } catch (e) {
          debugPrint('⚠️ خطأ في تحليل رسالة الخطأ');
        }
        return null;
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال رسالة WhatsApp');
      return null;
    }
  }

  /// إرسال رسالة قالب (Template Message)
  static Future<Map<String, dynamic>?> sendTemplateMessage({
    required String to,
    required String templateName,
    String languageCode = 'ar',
    List<String>? parameters,
  }) async {
    try {
      if (!await isConfigured()) {
        debugPrint('❌ WhatsApp Business API غير مُعد');
        return null;
      }

      final userToken = await getUserToken();
      final phoneNumberId = await getPhoneNumberId();

      String cleanPhone = to.replaceAll(RegExp(r'[^\d+]'), '');
      if (!cleanPhone.startsWith('+')) {
        if (cleanPhone.startsWith('964')) {
          cleanPhone = '+$cleanPhone';
        } else if (cleanPhone.startsWith('0')) {
          cleanPhone = '+964${cleanPhone.substring(1)}';
        } else {
          cleanPhone = '+964$cleanPhone';
        }
      }

      debugPrint('📤 إرسال Template Message إلى: $cleanPhone');
      debugPrint('Template: $templateName');

      final url = Uri.parse('$_baseUrl/$_apiVersion/$phoneNumberId/messages');

      final bodyComponents = parameters != null && parameters.isNotEmpty
          ? [
              {
                'type': 'body',
                'parameters': parameters
                    .map((param) => {
                          'type': 'text',
                          'text': param,
                        })
                    .toList(),
              }
            ]
          : null;

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $userToken',
            },
            body: jsonEncode({
              'messaging_product': 'whatsapp',
              'to': cleanPhone,
              'type': 'template',
              'template': {
                'name': templateName,
                'language': {
                  'code': languageCode,
                },
                if (bodyComponents != null) 'components': bodyComponents,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 استجابة Template: ${response.statusCode}');
      debugPrint('📥 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ تم إرسال Template بنجاح');
        debugPrint('Message ID: ${data['messages']?[0]?['id']}');
        return data;
      } else {
        debugPrint('❌ فشل في إرسال Template - الحالة: ${response.statusCode}');
        debugPrint('📥 Response Body: ${response.body}');

        try {
          final error = jsonDecode(response.body);
          final errorMessage = error['error']?['message'] ?? 'Unknown error';
          final errorCode = error['error']?['code'];
          final errorType = error['error']?['type'];

          debugPrint('❌ تفاصيل الخطأ:');
          debugPrint('   Message: $errorMessage');
          debugPrint('   Code: $errorCode');
          debugPrint('   Type: $errorType');

          // تحليل أخطاء القوالب
          if (errorCode == 100) {
            final errorSubcode = error['error']?['error_subcode'];
            debugPrint('💡 الحل: مشكلة في Phone Number ID أو الصلاحيات');
            debugPrint('   Phone Number ID: $phoneNumberId');
            if (errorSubcode == 33) {
              debugPrint(
                  '   ❌ Phone Number ID غير موجود أو لا تملك صلاحية الوصول إليه');
              debugPrint('   ⚠️ تأكد من:');
              debugPrint('      1. Phone Number ID صحيح من WhatsApp Manager');
              debugPrint(
                  '      2. Token من نفس Business Account الذي يحتوي على Phone Number');
              debugPrint(
                  '      3. Token يملك الصلاحيات: whatsapp_business_messaging & whatsapp_business_management');
            }
          } else if (errorCode == 132000) {
            debugPrint(
                '💡 الحل: القالب "$templateName" غير موجود أو غير معتمد.');
          } else if (errorCode == 132001) {
            debugPrint(
                '💡 الحل: عدد المتغيرات غير صحيح للقالب "$templateName".');
          } else if (errorCode == 132005) {
            debugPrint('💡 الحل: القالب غير نشط أو معطل.');
          } else if (errorCode == 132012) {
            debugPrint('💡 الحل: القالب بحاجة للمراجعة والموافقة من Meta.');
          }
        } catch (e) {
          debugPrint('⚠️ خطأ في تحليل رسالة الخطأ');
        }
        return null;
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال Template');
      return null;
    }
  }

  /// التحقق من صحة Token - طريقة محسّنة تدعم التوكنات الدائمة
  static Future<bool> verifyToken() async {
    try {
      final userToken = await getUserToken();
      final phoneNumberId = await getPhoneNumberId();

      if (userToken == null || phoneNumberId == null) {
        debugPrint('⚠️ لا توجد بيانات اعتماد محفوظة');
        return false;
      }

      debugPrint('🔍 التحقق من صحة Token...');
      debugPrint('Phone Number ID: $phoneNumberId');
      debugPrint(
          'User Token (أول 30 حرف): ${userToken.substring(0, userToken.length > 30 ? 30 : userToken.length)}...');

      // المحاولة 1: التحقق من Phone Number ID مباشرة
      try {
        final url = Uri.parse('$_baseUrl/$_apiVersion/$phoneNumberId');
        final response = await http.get(
          url,
          headers: {
            'Authorization': 'Bearer $userToken',
          },
        ).timeout(const Duration(seconds: 10));

        debugPrint('📥 Response Status (Method 1): ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          debugPrint('✅ Token صالح (Method 1)');
          debugPrint('Phone Number: ${data['display_phone_number']}');
          debugPrint('Verified Name: ${data['verified_name']}');
          return true;
        }

        // إذا فشلت المحاولة الأولى، نجرب طريقة بديلة
        debugPrint(
            '⚠️ Method 1 failed (${response.statusCode}), trying alternative method...');

        try {
          final errorData = jsonDecode(response.body);
          debugPrint(
              '❌ رسالة الخطأ (Method 1): ${errorData['error']?['message']}');
          debugPrint('❌ نوع الخطأ: ${errorData['error']?['type']}');
          debugPrint('❌ كود الخطأ: ${errorData['error']?['code']}');
        } catch (_) {}
      } catch (e) {
        debugPrint('⚠️ Method 1 exception: $e, trying alternative...');
      }

      // المحاولة 2: التحقق من Token باستخدام الـ Access Token Debug endpoint
      debugPrint('🔍 Trying Method 2: Access Token introspection...');

      try {
        final debugTokenUrl = Uri.parse(
            'https://graph.facebook.com/debug_token?input_token=$userToken&access_token=$userToken');

        final response =
            await http.get(debugTokenUrl).timeout(const Duration(seconds: 10));

        debugPrint('📥 Response Status (Method 2): ${response.statusCode}');

        if (response.statusCode == 200) {
          try {
            final data = jsonDecode(response.body);
            final isValid = data['data']?['is_valid'] ?? false;

            if (isValid == true) {
              debugPrint('✅ Token صالح (Method 2 - Token is valid)');
              // نتحقق من نوع Token
              final tokenType = data['data']?['type'] ?? 'unknown';
              final appId = data['data']?['app_id'] ?? 'unknown';
              debugPrint('   Token Type: $tokenType, App ID: $appId');
              return true;
            } else {
              debugPrint('❌ Token غير صالح (Method 2)');
              return false;
            }
          } catch (e) {
            debugPrint('⚠️ Error parsing debug_token response');
          }
        }
      } catch (e) {
        debugPrint('❌ Method 2 exception');
      }

      // المحاولة 3: التحقق البسيط عبر endpoint الرسائل
      debugPrint('🔍 Trying Method 3: Simple messages endpoint validation...');

      try {
        // نجرب الوصول لـ endpoint الرسائل للتحقق من صحة Token
        final messagesUrl =
            Uri.parse('$_baseUrl/$_apiVersion/$phoneNumberId/messages');

        // نرسل طلب GET بدلاً من POST للتحقق فقط
        final response = await http.get(
          messagesUrl,
          headers: {
            'Authorization': 'Bearer $userToken',
          },
        ).timeout(const Duration(seconds: 10));

        debugPrint('📥 Response Status (Method 3): ${response.statusCode}');
        debugPrint('📥 Response Body (Method 3): ${response.body}');

        // حتى لو أعطى 405 (Method Not Allowed) أو 403، فهذا يعني أن Token صالح
        // لكن الـ method خطأ، وهذا يكفي للتحقق
        if (response.statusCode == 405 ||
            response.statusCode == 403 ||
            response.statusCode == 200) {
          debugPrint('✅ Token صالح (Method 3 - Token recognized by API)');
          return true;
        }

        // إذا كان الخطأ 401، فالتوكن غير صالح
        if (response.statusCode == 401) {
          debugPrint('❌ Token غير صالح - 401 Unauthorized');
          return false;
        }

        // إذا كان الخطأ 400، نحلل السبب
        if (response.statusCode == 400) {
          try {
            final errorData = jsonDecode(response.body);
            final errorMessage = errorData['error']?['message'] ?? '';
            final errorCode = errorData['error']?['code'];

            debugPrint('⚠️ Error 400 Details:');
            debugPrint('   Message: $errorMessage');
            debugPrint('   Code: $errorCode');

            // إذا كان الخطأ متعلق بالتوكن، نرجع false
            if (errorMessage.toLowerCase().contains('token') ||
                errorMessage.toLowerCase().contains('access') ||
                errorCode == 190) {
              // 190 = Invalid OAuth access token
              debugPrint('❌ Token issue detected');
              return false;
            }

            // إذا كان الخطأ عن Phone Number ID أو parameter آخر
            if (errorMessage.toLowerCase().contains('phone') ||
                errorMessage.toLowerCase().contains('parameter') ||
                errorMessage.toLowerCase().contains('required')) {
              debugPrint('⚠️ Error not related to token: $errorMessage');
              debugPrint('✅ Token appears valid (error is about other data)');
              return true;
            }
          } catch (e) {
            debugPrint('⚠️ Error parsing 400 response');
          }
        }
      } catch (e) {
        debugPrint('❌ Method 3 exception');
      }

      // إذا وصلنا هنا، نعتبر أن هناك مشكلة
      debugPrint('❌ لم نتمكن من التحقق من Token بأي طريقة');
      debugPrint('💡 تأكد من:');
      debugPrint('   1. Token صحيح وغير منتهي');
      debugPrint(
          '   2. Phone Number ID صحيح (يجب أن يكون رقم معرف وليس رقم هاتف)');
      debugPrint('   3. رقم الهاتف مفعّل في WhatsApp Business API');
      debugPrint('   4. App ID مرتبط بـ WhatsApp Business Account الصحيح');
      return false;
    } catch (e) {
      debugPrint('❌ خطأ عام في التحقق من Token');
      return false;
    }
  }

  /// جلب رابط تحميل الوسائط من Meta API
  /// يُرجع URL مؤقت لتحميل الملف (صالح لدقائق قليلة)
  static Future<String?> getMediaDownloadUrl(String mediaId) async {
    try {
      final userToken = await getUserToken();
      if (userToken == null) {
        debugPrint('❌ لا يوجد Access Token لتحميل الوسائط');
        return null;
      }

      final url = Uri.parse('$_baseUrl/$_apiVersion/$mediaId');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $userToken'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final downloadUrl = data['url'] as String?;
        debugPrint('✅ تم جلب رابط الوسائط: $mediaId');
        return downloadUrl;
      } else {
        debugPrint('❌ فشل جلب رابط الوسائط: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب رابط الوسائط');
      return null;
    }
  }

  /// تحميل ملف الوسائط كـ bytes
  static Future<Uint8List?> downloadMedia(String mediaId) async {
    try {
      final downloadUrl = await getMediaDownloadUrl(mediaId);
      if (downloadUrl == null) return null;

      final userToken = await getUserToken();
      if (userToken == null) return null;

      final response = await http.get(
        Uri.parse(downloadUrl),
        headers: {'Authorization': 'Bearer $userToken'},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        debugPrint(
            '✅ تم تحميل الوسائط بنجاح: ${response.bodyBytes.length} bytes');
        return response.bodyBytes;
      } else {
        debugPrint('❌ فشل تحميل الوسائط: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل الوسائط');
      return null;
    }
  }

  /// حذف جميع البيانات المحفوظة
  static Future<void> clearCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userTokenKey);
      await prefs.remove(_appTokenKey);
      await prefs.remove(_phoneNumberIdKey);
      await prefs.remove(_businessAccountIdKey);
      debugPrint('✅ تم حذف جميع بيانات الاعتماد');
    } catch (e) {
      debugPrint('❌ خطأ في حذف البيانات');
    }
  }

  /// الحصول على معلومات الإعداد الحالية
  static Future<Map<String, String?>> getConfigInfo() async {
    return {
      'user_token': await getUserToken(),
      'app_token': await getAppToken(),
      'phone_number_id': await getPhoneNumberId(),
      'business_account_id': await getBusinessAccountId(),
    };
  }
}
