/// خدمة WhatsApp Server للتواصل مع سيرفر whatsapp-web.js
/// السيرفر: http://145.223.82.114:3000
/// يدعم Multi-Tenant - كل شركة برقمها الخاص
/// التخزين: Firebase (رئيسي) + SharedPreferences (cache محلي)
library;

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/custom_auth_service.dart';

class WhatsAppServerService {
  // عنوان السيرفر الافتراضي على Hostinger
  static const String _defaultServerUrl = 'http://145.223.82.114:3000';

  // مفاتيح SharedPreferences (cache محلي)
  static const String _keyServerUrl = 'whatsapp_server_url';
  static const String _keyServerEnabled = 'whatsapp_server_enabled';
  static const String _keyBulkDelayValue = 'whatsapp_bulk_delay_value';
  static const String _keyBulkDelayUnit = 'whatsapp_bulk_delay_unit';

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final CustomAuthService _authService = CustomAuthService();

  /// مسار إعدادات الواتساب في Firebase
  static String _getSettingsPath(String tenantId) {
    return 'tenants/$tenantId/settings/whatsapp_server';
  }

  /// الحصول على tenantId الحالي
  static String? get _currentTenantId => _authService.currentTenantId;

  // ─── Firebase Methods ───────────────────────────────────────

  /// حفظ كل الإعدادات في Firebase + cache محلي
  static Future<bool> _saveToFirebase({
    String? serverUrl,
    bool? enabled,
    int? delayValue,
    String? delayUnit,
    String? tenantId,
  }) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return false;

      final data = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (serverUrl != null) data['serverUrl'] = serverUrl;
      if (enabled != null) data['enabled'] = enabled;
      if (delayValue != null) data['bulkDelayValue'] = delayValue;
      if (delayUnit != null) data['bulkDelayUnit'] = delayUnit;

      await _firestore.doc(_getSettingsPath(tid)).set(
            data,
            SetOptions(merge: true),
          );
      debugPrint('✅ تم حفظ إعدادات الواتساب في Firebase');
      return true;
    } catch (e) {
      debugPrint('⚠️ فشل حفظ Firebase');
      return false;
    }
  }

  /// قراءة الإعدادات من Firebase
  static Future<Map<String, dynamic>?> _loadFromFirebase(
      {String? tenantId}) async {
    try {
      final tid = tenantId ?? _currentTenantId;
      if (tid == null) return null;

      final doc = await _firestore.doc(_getSettingsPath(tid)).get();
      if (doc.exists && doc.data() != null) {
        debugPrint('✅ تم تحميل إعدادات الواتساب من Firebase');
        return doc.data()!;
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ فشل قراءة Firebase');
      return null;
    }
  }

  /// مزامنة من Firebase إلى cache محلي
  static Future<void> syncFromFirebase({String? tenantId}) async {
    final data = await _loadFromFirebase(tenantId: tenantId);
    if (data == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (data['serverUrl'] != null) {
        await prefs.setString(_keyServerUrl, data['serverUrl']);
      }
      if (data['enabled'] != null) {
        await prefs.setBool(_keyServerEnabled, data['enabled']);
      }
      if (data['bulkDelayValue'] != null) {
        await prefs.setInt(_keyBulkDelayValue, data['bulkDelayValue']);
      }
      if (data['bulkDelayUnit'] != null) {
        await prefs.setString(_keyBulkDelayUnit, data['bulkDelayUnit']);
      }
      debugPrint('✅ تمت مزامنة الإعدادات من Firebase إلى الـ cache المحلي');
    } catch (e) {
      debugPrint('⚠️ فشل مزامنة الـ cache');
    }
  }

  // ─── Public API (Firebase أولاً، ثم cache محلي) ────────────

  /// الحصول على عنوان السيرفر للشركة
  static Future<String> getServerUrl({String? tenantId}) async {
    try {
      // محاولة من Firebase أولاً
      final fbData = await _loadFromFirebase(tenantId: tenantId);
      if (fbData != null && fbData['serverUrl'] != null) {
        final url = fbData['serverUrl'] as String;
        // تحديث الـ cache المحلي
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_keyServerUrl, url);
        return url;
      }
    } catch (e) {
      debugPrint('⚠️ فشل جلب من Firebase');
    }

    // fallback: cache محلي
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyServerUrl) ?? _defaultServerUrl;
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب عنوان السيرفر');
      return _defaultServerUrl;
    }
  }

  /// حفظ عنوان السيرفر للشركة (Firebase + cache)
  static Future<bool> saveServerUrl(String url, {String? tenantId}) async {
    try {
      // حفظ محلياً
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyServerUrl, url);
      await prefs.setBool(_keyServerEnabled, true);

      // حفظ في Firebase
      await _saveToFirebase(
        serverUrl: url,
        enabled: true,
        tenantId: tenantId,
      );

      debugPrint('✅ تم حفظ عنوان السيرفر');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في حفظ عنوان السيرفر');
      return false;
    }
  }

  /// الحصول على إعدادات السيرفر الكاملة
  static Future<Map<String, dynamic>> getServerSettings(
      {String? tenantId}) async {
    try {
      // محاولة من Firebase أولاً
      final fbData = await _loadFromFirebase(tenantId: tenantId);
      if (fbData != null) {
        return {
          'serverUrl': fbData['serverUrl'] ?? _defaultServerUrl,
          'enabled': fbData['enabled'] ?? false,
        };
      }
    } catch (e) {
      debugPrint('⚠️ فشل جلب من Firebase');
    }

    // fallback: cache محلي
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'serverUrl': prefs.getString(_keyServerUrl) ?? _defaultServerUrl,
        'enabled': prefs.getBool(_keyServerEnabled) ?? false,
      };
    } catch (e) {
      return {'serverUrl': _defaultServerUrl, 'enabled': false};
    }
  }

  /// حفظ إعدادات الإرسال الجماعي (Firebase + cache)
  static Future<bool> saveBulkSettings({
    required int delayValue,
    required String delayUnit, // 'seconds' أو 'minutes'
    String? tenantId,
  }) async {
    try {
      // حفظ محلياً
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyBulkDelayValue, delayValue);
      await prefs.setString(_keyBulkDelayUnit, delayUnit);

      // حفظ في Firebase
      await _saveToFirebase(
        delayValue: delayValue,
        delayUnit: delayUnit,
        tenantId: tenantId,
      );

      debugPrint('✅ تم حفظ إعدادات الإرسال الجماعي: $delayValue $delayUnit');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في حفظ إعدادات الإرسال الجماعي');
      return false;
    }
  }

  /// الحصول على إعدادات الإرسال الجماعي
  static Future<Map<String, dynamic>> getBulkSettings(
      {String? tenantId}) async {
    try {
      // محاولة من Firebase أولاً
      final fbData = await _loadFromFirebase(tenantId: tenantId);
      if (fbData != null && fbData['bulkDelayValue'] != null) {
        return {
          'delayValue': fbData['bulkDelayValue'] ?? 5,
          'delayUnit': fbData['bulkDelayUnit'] ?? 'seconds',
        };
      }
    } catch (e) {
      debugPrint('⚠️ فشل جلب من Firebase');
    }

    // fallback: cache محلي
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'delayValue': prefs.getInt(_keyBulkDelayValue) ?? 5,
        'delayUnit': prefs.getString(_keyBulkDelayUnit) ?? 'seconds',
      };
    } catch (e) {
      debugPrint('⚠️ خطأ في جلب إعدادات الإرسال الجماعي');
      return {'delayValue': 5, 'delayUnit': 'seconds'};
    }
  }

  /// الحصول على الفاصل الزمني بالثواني
  static Future<int> getBulkDelayInSeconds({String? tenantId}) async {
    final settings = await getBulkSettings(tenantId: tenantId);
    final value = settings['delayValue'] as int;
    final unit = settings['delayUnit'] as String;

    if (unit == 'minutes') {
      return value * 60;
    }
    return value;
  }

  /// التحقق من اتصال السيرفر
  static Future<bool> isServerOnline({String? tenantId}) async {
    try {
      final serverUrl = await getServerUrl(tenantId: tenantId);
      final response = await http
          .get(Uri.parse(serverUrl))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ السيرفر غير متاح');
      return false;
    }
  }

  /// إنشاء جلسة جديدة للشركة
  static Future<Map<String, dynamic>> createSession(String tenantId) async {
    try {
      final serverUrl = await getServerUrl(tenantId: tenantId);
      debugPrint('🔄 إنشاء جلسة للشركة: $tenantId');

      final response = await http.post(
        Uri.parse('$serverUrl/session/$tenantId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);
      debugPrint('📥 الرد: $data');

      return data;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء الجلسة');
      return {'error': 'حدث خطأ'};
    }
  }

  /// الحصول على QR Code كـ Base64 Image
  static Future<String?> getQRImage(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      final response = await http
          .get(Uri.parse('$serverUrl/qr-image/$tenantId'))
          .timeout(const Duration(seconds: 10));

      debugPrint('📥 QR Response (${response.statusCode}): ${response.body}');

      final data = jsonDecode(response.body);
      // تجربة أسماء fields مختلفة (حسب إصدار السيرفر)
      return data['qrImage'] ??
          data['qr'] ??
          data['qrcode'] ??
          data['image'] ??
          data['data'];
    } catch (e) {
      debugPrint('❌ خطأ في جلب QR');
      return null;
    }
  }

  /// جلب رد الـ QR الخام للتشخيص
  static Future<String> getQRImageRaw(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      final response = await http
          .get(Uri.parse('$serverUrl/qr-image/$tenantId'))
          .timeout(const Duration(seconds: 10));
      return 'HTTP ${response.statusCode}: ${response.body}';
    } catch (e) {
      return 'Error';
    }
  }

  /// جلب رد الـ status الخام للتشخيص
  static Future<String> getStatusRaw(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      final response = await http
          .get(Uri.parse('$serverUrl/status/$tenantId'))
          .timeout(const Duration(seconds: 10));
      return 'HTTP ${response.statusCode}: ${response.body}';
    } catch (e) {
      return 'Error';
    }
  }

  /// محاولة جلب QR من status endpoint (بعض السيرفرات تضعه هناك)
  static Future<String?> getQRFromStatus(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      final response = await http
          .get(Uri.parse('$serverUrl/status/$tenantId'))
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      return data['qr'] ??
          data['qrCode'] ??
          data['qrImage'] ??
          data['qrcode'];
    } catch (e) {
      return null;
    }
  }

  /// إنشاء جلسة والحصول على الرد الخام للتشخيص
  static Future<String> createSessionRaw(String tenantId) async {
    try {
      final serverUrl = await getServerUrl(tenantId: tenantId);
      final response = await http.post(
        Uri.parse('$serverUrl/session/$tenantId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      return 'HTTP ${response.statusCode}: ${response.body}';
    } catch (e) {
      return 'Error';
    }
  }

  /// التحقق من حالة الاتصال
  static Future<Map<String, dynamic>> getStatus(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      final response = await http
          .get(Uri.parse('$serverUrl/status/$tenantId'))
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return {
        'connected': data['connected'] == true,
        'phone': data['phone'],
        'name': data['name'],
      };
    } catch (e) {
      debugPrint('❌ خطأ في جلب الحالة');
      return {'connected': false, 'error': 'حدث خطأ'};
    }
  }

  /// إرسال رسالة واحدة — يعيد null عند النجاح، أو رسالة الخطأ عند الفشل
  static Future<String?> sendMessageWithError({
    required String tenantId,
    required String phone,
    required String message,
  }) async {
    try {
      final serverUrl = await getServerUrl();
      debugPrint('📤 إرسال رسالة إلى $phone (tenantId: $tenantId, url: $serverUrl)');

      final response = await http
          .post(
            Uri.parse('$serverUrl/send/$tenantId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'phone': phone,
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('📥 HTTP ${response.statusCode}: ${response.body}');

      // المحاولة بـ JSON أولاً
      try {
        final data = jsonDecode(response.body);
        // قبول أي صيغة نجاح شائعة من السيرفر
        final isSuccess = data['success'] == true ||
            data['status'] == 'success' ||
            data['status'] == 'sent' ||
            data['sent'] == true;

        if (isSuccess || response.statusCode == 200) {
          debugPrint('✅ تم إرسال الرسالة بنجاح');
          return null; // null = نجاح
        }

        final errorMsg = data['error']?.toString() ??
            data['message']?.toString() ??
            'HTTP ${response.statusCode}: ${response.body}';
        debugPrint('❌ فشل الإرسال: $errorMsg');
        return errorMsg;
      } catch (_) {
        // الرد ليس JSON — اعتبره نجاحاً إن كان 200
        if (response.statusCode == 200) {
          debugPrint('✅ تم الإرسال (رد غير JSON)');
          return null;
        }
        return 'HTTP ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      debugPrint('❌ خطأ في الإرسال');
      return 'حدث خطأ';
    }
  }

  /// إرسال رسالة واحدة (متوافق مع الكود القديم)
  static Future<bool> sendMessage({
    required String tenantId,
    required String phone,
    required String message,
  }) async {
    final error = await sendMessageWithError(
      tenantId: tenantId,
      phone: phone,
      message: message,
    );
    return error == null;
  }

  /// إرسال رسائل متعددة
  static Future<List<Map<String, dynamic>>> sendBulkMessages({
    required String tenantId,
    required List<Map<String, String>> messages,
  }) async {
    try {
      final serverUrl = await getServerUrl();
      debugPrint('📤 إرسال ${messages.length} رسالة...');

      final response = await http
          .post(
            Uri.parse('$serverUrl/send-bulk/$tenantId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'messages': messages}),
          )
          .timeout(const Duration(seconds: 120));

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        debugPrint('✅ تم إرسال الرسائل');
        return List<Map<String, dynamic>>.from(data['results'] ?? []);
      } else {
        debugPrint('❌ فشل الإرسال: ${data['error']}');
        return [];
      }
    } catch (e) {
      debugPrint('❌ خطأ في الإرسال الجماعي');
      return [];
    }
  }

  /// قطع الاتصال
  static Future<bool> disconnect(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      final response = await http.delete(
        Uri.parse('$serverUrl/session/$tenantId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      debugPrint('🔌 تم قطع الاتصال: $data');
      return data['status'] == 'disconnected';
    } catch (e) {
      debugPrint('❌ خطأ في قطع الاتصال');
      return false;
    }
  }

  /// الحصول على قائمة الشركات المتصلة
  static Future<List<Map<String, dynamic>>> getConnectedClients() async {
    try {
      final serverUrl = await getServerUrl();
      final response = await http
          .get(Uri.parse('$serverUrl/clients'))
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('❌ خطأ في جلب قائمة العملاء');
      return [];
    }
  }

  /// التحقق من جاهزية الخدمة
  static Future<bool> isReady(String tenantId) async {
    final status = await getStatus(tenantId);
    return status['connected'] == true;
  }

  /// إعادة تشغيل الجلسة (بدون QR — يحتفظ ببيانات المصادقة)
  static Future<Map<String, dynamic>> restartSession(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      debugPrint('🔄 إعادة تشغيل الجلسة: $tenantId');
      final response = await http.post(
        Uri.parse('$serverUrl/restart/$tenantId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body);
      debugPrint('📥 restart response: $data');
      return data;
    } catch (e) {
      debugPrint('❌ خطأ في إعادة تشغيل الجلسة');
      return {'success': false, 'error': 'حدث خطأ'};
    }
  }

  /// إعادة تعيين كاملة (يحذف بيانات المصادقة — يحتاج QR جديد)
  static Future<Map<String, dynamic>> fullResetSession(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      debugPrint('🔄 إعادة تعيين كاملة: $tenantId');
      final response = await http.post(
        Uri.parse('$serverUrl/full-reset/$tenantId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body);
      debugPrint('📥 full-reset response: $data');
      return data;
    } catch (e) {
      debugPrint('❌ خطأ في إعادة التعيين');
      return {'success': false, 'error': 'حدث خطأ'};
    }
  }

  /// فحص صحة الجلسة
  static Future<Map<String, dynamic>> getHealth(String tenantId) async {
    try {
      final serverUrl = await getServerUrl();
      final response = await http
          .get(Uri.parse('$serverUrl/health/$tenantId'))
          .timeout(const Duration(seconds: 10));
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('❌ خطأ في فحص الصحة');
      return {'healthy': false, 'error': 'حدث خطأ'};
    }
  }

  /// إرسال رسالة تلقائية (helper method)
  static Future<bool> sendAutoMessage({
    required String tenantId,
    required String phone,
    required String customerName,
    required String messageTemplate,
    Map<String, String>? variables,
  }) async {
    String message = messageTemplate;
    message = message.replaceAll('{name}', customerName);
    message = message.replaceAll('{customer_name}', customerName);

    if (variables != null) {
      variables.forEach((key, value) {
        message = message.replaceAll('{$key}', value);
      });
    }

    return sendMessage(
      tenantId: tenantId,
      phone: phone,
      message: message,
    );
  }
}

/// قوالب الرسائل الافتراضية للسيرفر
class WhatsAppServerMessageTemplates {
  /// رسالة تأكيد التجديد
  static String renewalConfirmation({
    required String customerName,
    required String expiryDate,
    required String amount,
  }) {
    return '''
✅ تم تجديد اشتراكك بنجاح!

مرحباً $customerName 👋

تم تجديد اشتراكك حتى تاريخ: $expiryDate
المبلغ المدفوع: $amount د.ع

شكراً لثقتك بنا! 🙏
''';
  }

  /// رسالة تذكير بانتهاء الاشتراك
  static String expiryReminder({
    required String customerName,
    required String expiryDate,
    required String daysLeft,
  }) {
    return '''
⚠️ تذكير بانتهاء الاشتراك

مرحباً $customerName 👋

اشتراكك سينتهي بتاريخ: $expiryDate
المتبقي: $daysLeft يوم

يرجى التجديد لتجنب انقطاع الخدمة.
''';
  }

  /// رسالة ترحيب بمشترك جديد
  static String welcomeMessage({
    required String customerName,
    required String packageName,
  }) {
    return '''
🎉 مرحباً بك!

أهلاً $customerName 👋

تم تفعيل اشتراكك بنجاح!
الباقة: $packageName

نتمنى لك تجربة إنترنت سريعة ومستقرة! 🚀
''';
  }
}
