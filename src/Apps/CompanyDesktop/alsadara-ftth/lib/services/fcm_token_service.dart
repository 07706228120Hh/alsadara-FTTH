import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
import 'firebase_availability.dart';

class FcmTokenService {
  static FcmTokenService? _instance;
  static FcmTokenService get instance => _instance ??= FcmTokenService._();
  FcmTokenService._();

  String? _currentToken;
  String? get currentToken => _currentToken;

  /// Register FCM token with the backend after login
  Future<void> registerToken() async {
    if (!FirebaseAvailability.isAvailable) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;

      if (!ApiClient.instance.isAuthenticated) return;

      final platform = Platform.isAndroid
          ? 'android'
          : Platform.isIOS
              ? 'ios'
              : Platform.isWindows
                  ? 'windows'
                  : 'unknown';

      final response = await ApiClient.instance.post(
        '/fcm-tokens/register',
        {
          'token': token,
          'devicePlatform': platform,
        },
        (data) => data,
      );

      if (response.isSuccess) {
        debugPrint('[FCM] Token registered successfully');
      } else {
        debugPrint('[FCM] Token registration response: ${response.message}');
      }
    } catch (e) {
      debugPrint('[FCM] Failed to register token: $e');
    }
  }

  /// Unregister FCM token (on logout)
  Future<void> unregisterToken() async {
    if (_currentToken == null) return;
    try {
      if (!ApiClient.instance.isAuthenticated) return;

      await ApiClient.instance.post(
        '/fcm-tokens/unregister',
        {'token': _currentToken},
        (data) => data,
      );
      _currentToken = null;
      debugPrint('[FCM] Token unregistered');
    } catch (e) {
      debugPrint('[FCM] Failed to unregister token: $e');
    }
  }

  /// Listen for token refresh
  void listenForTokenRefresh() {
    if (!FirebaseAvailability.isAvailable) return;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _currentToken = newToken;
      registerToken();
    });
  }
}
