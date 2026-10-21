import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../widgets/window_close_handler_fixed.dart' show navigatorKey;
import '../pages/login/premium_login_page.dart';
import 'task_signalr_service.dart';
import 'dual_auth_service.dart';
import 'vps_auth_service.dart';
import 'fcm_token_service.dart';
import 'api/api_client.dart';

/// خدمة الإخراج الإجباري العالمي.
///
/// تستمع لحدث "ForceLogout" الذي يبثّه الخادم عبر SignalR (يطلقه مدير الشركة من
/// «إعدادات الشركة»). عند استلامه — ما لم يكن المستخدم الحالي هو الضاغط نفسه
/// (exceptUserId) — تُنفّذ تسجيل خروج كامل وتعيد التطبيق لشاشة الدخول فوراً.
///
/// تُشغَّل مرة واحدة من قشرة ما بعد المصادقة (HomePage)، وتُوقَف عند الخروج.
class ForceLogoutService {
  ForceLogoutService._();
  static final ForceLogoutService instance = ForceLogoutService._();

  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _started = false;
  bool _loggingOut = false;

  /// بدء المراقبة (idempotent) — يضمن اتصال SignalR ويشترك في حدث الإخراج.
  void start() {
    if (_started) return;
    _started = true;
    _loggingOut = false;

    // ضمان اتصال TaskHub طوال الجلسة (idempotent داخلياً).
    TaskSignalRService.instance.connect();

    _sub?.cancel();
    _sub = TaskSignalRService.instance.onForceLogout.listen(_handleForceLogout);
  }

  /// إيقاف المراقبة (عند تسجيل الخروج العادي).
  void stop() {
    _sub?.cancel();
    _sub = null;
    _started = false;
    _loggingOut = false;
  }

  Future<void> _handleForceLogout(Map<String, dynamic> data) async {
    if (_loggingOut) return;

    // استثناء الضاغط: إن طابق exceptUserId هوية المستخدم الحالي، نتجاهل الحدث.
    final exceptUserId = data['exceptUserId']?.toString();
    final currentUserId = _currentUserId();
    if (exceptUserId != null &&
        currentUserId != null &&
        exceptUserId == currentUserId) {
      return;
    }

    _loggingOut = true;
    if (kDebugMode) debugPrint('🚪 ForceLogout مُستلَم — تنفيذ خروج إجباري');

    // إلغاء تسجيل FCM (منع إشعارات المستخدم السابق) — أفضل جهد.
    try {
      await FcmTokenService.instance.unregisterToken();
    } catch (_) {}

    // تسجيل الخروج من كلا النظامين (VPS + FTTH).
    try {
      await DualAuthService.instance.logoutAll();
    } catch (_) {}

    // قطع اتصال SignalR وإنهاء الاشتراك (يُعاد في start() عند الدخول التالي).
    try {
      await TaskSignalRService.instance.disconnect();
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    _started = false;

    // الانتقال لشاشة الدخول عالمياً + رسالة.
    final nav = navigatorKey.currentState;
    if (nav != null) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PremiumLoginPage()),
        (route) => false,
      );
    }

    try {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text(
              'تم إنهاء جلستك من قبل مدير الشركة. الرجاء تسجيل الدخول من جديد.',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (_) {}
  }

  /// هوية المستخدم الحالي من التوكن (sub / nameidentifier).
  String? _currentUserId() {
    final token =
        VpsAuthService.instance.accessToken ?? ApiClient.instance.authToken;
    if (token == null || token.isEmpty) return null;
    try {
      final payload = JwtDecoder.decode(token);
      return (payload['sub'] ??
              payload['nameid'] ??
              payload[
                  'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'])
          ?.toString();
    } catch (_) {
      return null;
    }
  }
}
