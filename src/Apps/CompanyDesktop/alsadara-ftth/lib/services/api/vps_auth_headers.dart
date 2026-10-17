/// ترويسات المصادقة لنداءات خادم الصدارة (VPS) التي كانت تعتمد المفتاح الداخلي المضمّن.
///
/// منذ المرحلة 0-أ (تدقيق 2026-10-17) تُصادَق نقاط `/api/internal/*` و`/api/ftth-accounting/*`
/// بتوكن JWT الخاص بالمستخدم: الخادم يشتق الشركة والمستخدم من التوكن ولا يثق بأي
/// companyId/userId في الجسم. لذلك لا يُرسل التطبيق أي مفتاح ثابت لهذه النقاط.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../vps_auth_service.dart';

/// انتهت جلسة الصدارة ولم ينجح التحديث — على المستخدم إعادة تسجيل الدخول.
class VpsSessionExpiredException implements Exception {
  const VpsSessionExpiredException();

  /// رسالة عربية جاهزة للعرض للمستخدم.
  static const String userMessage = 'انتهت الجلسة — أعد تسجيل الدخول';

  String get message => userMessage;

  @override
  String toString() => userMessage;
}

class VpsAuthHeaders {
  VpsAuthHeaders._();

  /// تحديث واحد مشترك عند تزامن عدة طلبات مع توكن منتهٍ.
  static Future<bool>? _refreshing;

  /// يُعيد توكن الوصول الحالي، ويحدّثه أولاً إن كان منتهياً أو على وشك الانتهاء.
  /// يرمي [VpsSessionExpiredException] إذا كان التوكن منتهياً فعلاً وفشل تحديثه
  /// (بدل إرسال توكن منتهٍ بصمت).
  static Future<String?> validToken() async {
    final auth = VpsAuthService.instance;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return null;
    if (_isExpiringSoon(token)) {
      final refreshed = await refreshNow();
      if (!refreshed && _expiresWithin(token, Duration.zero)) {
        throw const VpsSessionExpiredException();
      }
    }
    final current = auth.accessToken;
    return (current == null || current.isEmpty) ? null : current;
  }

  /// تحديث فوري مشترك (قبل الانتهاء أو بعد 401). يُعيد true إن صار لدينا توكن صالح.
  /// يتبنّى أولاً توكناً أحدث كتبته خدمة الموقع الخلفية (isolate منفصل) — لأن توكن التحديث
  /// يُدوَّر عند كل تحديث، فالتحديث بنسخة قديمة في الذاكرة سيفشل.
  static Future<bool> refreshNow() async {
    if (await _adoptFromStorage()) return true;
    _refreshing ??= VpsAuthService.instance
        .refreshAccessToken()
        .catchError((_) => false)
        .whenComplete(() => _refreshing = null);
    if (await _refreshing!) return true;
    return _adoptFromStorage();
  }

  /// يتبنّى توكناً محفوظاً أحدث وصالحاً (دون طلب شبكة) عبر استعادة الجلسة من التخزين.
  static Future<bool> _adoptFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final stored = prefs.getString(VpsAuthService.storageKeyAccessToken);
      if (stored == null ||
          stored.isEmpty ||
          stored == VpsAuthService.instance.accessToken ||
          _isExpiringSoon(stored)) {
        return false;
      }
      return await VpsAuthService.instance.restoreSession();
    } catch (_) {
      return false;
    }
  }

  /// ترويسات جاهزة لـ package:http (مع Content-Type افتراضياً).
  static Future<Map<String, String>> build({bool json = true}) async {
    final token = await validToken();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// ينفّذ طلباً بترويسات JWT؛ عند 401 يحدّث التوكن مرة واحدة ويعيد المحاولة.
  /// إن فشل التحديث أو تكرر 401 يرمي [VpsSessionExpiredException] (رسالة عربية لإعادة الدخول).
  ///
  /// مثال: `await VpsAuthHeaders.send((h) => http.post(uri, headers: h, body: body));`
  static Future<http.Response> send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool json = true,
  }) async {
    final first = await request(await build(json: json));
    if (first.statusCode != 401) return first;

    final refreshed = await refreshNow();
    if (!refreshed) throw const VpsSessionExpiredException();

    final retry = await request(await build(json: json));
    if (retry.statusCode == 401) throw const VpsSessionExpiredException();
    return retry;
  }

  /// ينتهي خلال دقيقتين؟ (هامش التحديث المسبق)
  static bool _isExpiringSoon(String jwt) =>
      _expiresWithin(jwt, const Duration(minutes: 2));

  /// هل ينتهي التوكن خلال [margin]؟ (قراءة `exp` من الحمولة دون تحقق توقيع — للتوقيت فقط)
  static bool _expiresWithin(String jwt, Duration margin) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return false;
      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
      return expiresAt.isBefore(DateTime.now().toUtc().add(margin));
    } catch (_) {
      return false;
    }
  }
}
