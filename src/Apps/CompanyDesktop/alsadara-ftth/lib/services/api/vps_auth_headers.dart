/// ترويسات المصادقة لنداءات خادم الصدارة (VPS) التي كانت تعتمد المفتاح الداخلي المضمّن.
///
/// منذ المرحلة 0-أ (تدقيق 2026-10-17) تُصادَق نقاط `/api/internal/*` و`/api/ftth-accounting/*`
/// بتوكن JWT الخاص بالمستخدم: الخادم يشتق الشركة والمستخدم من التوكن ولا يثق بأي
/// companyId/userId في الجسم. لذلك لا يُرسل التطبيق أي مفتاح ثابت لهذه النقاط.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

  static Future<bool> _refreshOnce() {
    return _refreshing ??= VpsAuthService.instance
        .refreshAccessToken()
        .catchError((_) => false)
        .whenComplete(() => _refreshing = null);
  }

  /// يُعيد توكن الوصول الحالي، ويحدّثه أولاً إن كان منتهياً أو على وشك الانتهاء.
  /// يرمي [VpsSessionExpiredException] إذا كان التوكن منتهياً فعلاً وفشل تحديثه
  /// (بدل إرسال توكن منتهٍ بصمت).
  static Future<String?> validToken() async {
    final auth = VpsAuthService.instance;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return null;
    if (_expiresWithin(token, const Duration(minutes: 2))) {
      final refreshed = await _refreshOnce();
      if (!refreshed && _expiresWithin(token, Duration.zero)) {
        throw const VpsSessionExpiredException();
      }
    }
    final current = auth.accessToken;
    return (current == null || current.isEmpty) ? null : current;
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

    final refreshed = await _refreshOnce();
    if (!refreshed) throw const VpsSessionExpiredException();

    final retry = await request(await build(json: json));
    if (retry.statusCode == 401) throw const VpsSessionExpiredException();
    return retry;
  }

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
