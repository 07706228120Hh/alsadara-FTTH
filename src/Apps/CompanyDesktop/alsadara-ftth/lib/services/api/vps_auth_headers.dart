/// ترويسات المصادقة لنداءات خادم الصدارة (VPS) التي كانت تعتمد المفتاح الداخلي المضمّن.
///
/// منذ المرحلة 0-أ (تدقيق 2026-10-17) تُصادَق نقاط `/api/internal/*` و`/api/ftth-accounting/*`
/// بتوكن JWT الخاص بالمستخدم: الخادم يشتق الشركة والمستخدم من التوكن ولا يثق بأي
/// companyId/userId في الجسم. لذلك لا يُرسل التطبيق أي مفتاح ثابت لهذه النقاط.
library;

import 'dart:async';
import 'dart:convert';

import '../vps_auth_service.dart';

class VpsAuthHeaders {
  VpsAuthHeaders._();

  /// تحديث واحد مشترك عند تزامن عدة طلبات مع توكن منتهٍ.
  static Future<bool>? _refreshing;

  /// يُعيد توكن الوصول الحالي، ويحدّثه أولاً إن كان منتهياً أو على وشك الانتهاء.
  static Future<String?> validToken() async {
    final auth = VpsAuthService.instance;
    final token = auth.accessToken;
    if (token == null || token.isEmpty) return null;
    if (_isExpiringSoon(token)) {
      _refreshing ??=
          auth.refreshAccessToken().whenComplete(() => _refreshing = null);
      await _refreshing;
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

  /// هل ينتهي التوكن خلال دقيقتين؟ (قراءة `exp` من الحمولة دون تحقق توقيع — للتوقيت فقط)
  static bool _isExpiringSoon(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return false;
      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
      return expiresAt
          .isBefore(DateTime.now().toUtc().add(const Duration(minutes: 2)));
    } catch (_) {
      return false;
    }
  }
}
