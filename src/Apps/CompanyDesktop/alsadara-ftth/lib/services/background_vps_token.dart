/// توكن JWT لخدمات الخلفية التي تعمل في isolate منفصل (خدمة الموقع الأمامية على Android/iOS).
///
/// منذ المرحلة 0 / A2 لا يرسل التطبيق أي مفتاح داخلي ثابت: نقاط `/api/employee-location` تُصادَق بتوكن
/// المستخدم. الـ isolate الخلفي لا يشارك ذاكرة `VpsAuthService`، لذا يقرأ الجلسة نفسها من
/// SharedPreferences (مع `reload` لرؤية ما كتبه الـ isolate الرئيسي)، ويحدّثها بنفسه عند قرب الانتهاء
/// ثم يكتبها بالمفاتيح نفسها — فيتبنّاها الـ isolate الرئيسي لاحقاً (`VpsAuthHeaders`).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api_config.dart';
import 'vps_auth_service.dart';

class BackgroundVpsToken {
  BackgroundVpsToken._();

  static Future<String?>? _refreshing;

  /// يُعيد توكن وصول صالحاً (يحدّثه إن كان على وشك الانتهاء)، أو null إن لا توجد جلسة.
  static Future<String?> get() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final token = prefs.getString(VpsAuthService.storageKeyAccessToken);
      if (token == null || token.isEmpty) return null;
      if (!_expiringSoon(prefs)) return token;

      _refreshing ??= _refresh(prefs).whenComplete(() => _refreshing = null);
      final refreshed = await _refreshing;
      return refreshed ?? token;
    } catch (e) {
      debugPrint('⚠️ [BG-Token] read failed');
      return null;
    }
  }

  static bool _expiringSoon(SharedPreferences prefs) {
    final raw = prefs.getString(VpsAuthService.storageKeyTokenExpiresAt);
    final expiresAt = raw == null ? null : DateTime.tryParse(raw);
    if (expiresAt == null) return false; // لا نعرف — نجرّب التوكن كما هو
    return expiresAt.isBefore(DateTime.now().add(const Duration(minutes: 2)));
  }

  /// تحديث بتوكن التحديث المحفوظ (موظف شركة فقط) وحفظ النتيجة بالمفاتيح نفسها.
  static Future<String?> _refresh(SharedPreferences prefs) async {
    final refreshToken = prefs.getString(VpsAuthService.storageKeyRefreshToken);
    final userType = prefs.getString(VpsAuthService.storageKeyUserType);
    if (refreshToken == null || refreshToken.isEmpty) return null;
    if (userType != null && userType != 'companyEmployee') return null;

    final client = HttpClient()..badCertificateCallback = (_, __, ___) => true;
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final uri =
          Uri.parse('${ApiConfig.baseUrl}${ApiConfig.companyRefreshToken}');
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode({'refreshToken': refreshToken})));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // ربما حدّثه الـ isolate الرئيسي للتو — نعيد قراءة المخزَّن.
        await prefs.reload();
        return _expiringSoon(prefs)
            ? null
            : prefs.getString(VpsAuthService.storageKeyAccessToken);
      }
      final decoded = jsonDecode(body);
      final data = decoded is Map && decoded['data'] is Map
          ? decoded['data'] as Map
          : decoded as Map;
      final token = data['token']?.toString() ?? '';
      final newRefresh = data['refreshToken']?.toString() ?? '';
      if (token.isEmpty || newRefresh.isEmpty) return null;
      final expiresAt = data['expiresAt'] != null
          ? DateTime.tryParse(data['expiresAt'].toString())
          : null;
      await prefs.setString(VpsAuthService.storageKeyAccessToken, token);
      await prefs.setString(VpsAuthService.storageKeyRefreshToken, newRefresh);
      await prefs.setString(
          VpsAuthService.storageKeyTokenExpiresAt,
          (expiresAt ?? DateTime.now().add(const Duration(minutes: 55)))
              .toIso8601String());
      return token;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
