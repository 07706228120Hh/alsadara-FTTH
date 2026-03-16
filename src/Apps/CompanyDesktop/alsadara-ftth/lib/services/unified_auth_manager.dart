import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// نظام موحد لإدارة المصادقة مع تجديد تلقائي ذكي
/// يحل مشكلة انتهاء التوكن ويضمن استمرارية الجلسة
class UnifiedAuthManager {
  static UnifiedAuthManager? _instance;
  static UnifiedAuthManager get instance =>
      _instance ??= UnifiedAuthManager._internal();
  UnifiedAuthManager._internal();

  // Controllers للحالة
  final _authStateController = StreamController<AuthState>.broadcast();
  final _tokenStatusController = StreamController<TokenStatus>.broadcast();

  // Timers للتجديد
  Timer? _tokenRefreshTimer;
  Timer? _tokenCheckTimer;
  Timer? _preemptiveRefreshTimer;

  // حالة المصادقة
  AuthState _currentState = AuthState.checking;
  TokenInfo? _tokenInfo;
  UserSession? _userSession;

  // معلومات الاتصال
  static const String _baseUrl = 'https://admin.ftth.iq/api/auth/Contractor';
  static const Duration _tokenCheckInterval = Duration(minutes: 1);
  static const Duration _preemptiveRefreshThreshold = Duration(minutes: 5);
  static const Duration _forceRefreshThreshold = Duration(minutes: 2);

  // مفاتيح التخزين
  static const String _tokenInfoKey = 'unified_token_info';
  static const String _userSessionKey = 'unified_user_session';
  static const String _lastRefreshKey = 'unified_last_refresh';

  // الوصول للحالة
  Stream<AuthState> get authStateStream => _authStateController.stream;
  Stream<TokenStatus> get tokenStatusStream => _tokenStatusController.stream;
  AuthState get currentState => _currentState;
  TokenInfo? get tokenInfo => _tokenInfo;
  UserSession? get userSession => _userSession;

  /// تهيئة النظام والتحقق من الجلسة المحفوظة
  Future<void> initialize() async {
    debugPrint('🔐 تهيئة نظام المصادقة الموحد...');

    await _loadStoredSession();

    if (_tokenInfo != null && _userSession != null) {
      if (_isTokenValid()) {
        _setState(AuthState.authenticated);
        _startTokenManagement();
      } else if (_canRefreshToken()) {
        _setState(AuthState.refreshing);
        final success = await _refreshToken();
        if (success) {
          _setState(AuthState.authenticated);
          _startTokenManagement();
        } else {
          await _clearSession();
          _setState(AuthState.unauthenticated);
        }
      } else {
        await _clearSession();
        _setState(AuthState.unauthenticated);
      }
    } else {
      _setState(AuthState.unauthenticated);
    }
  }

  /// تسجيل الدخول مع تجديد تلقائي ذكي
  Future<LoginResult> login(String username, String password,
      {bool rememberMe = false}) async {
    debugPrint('🔐 بدء تسجيل الدخول: $username');

    _setState(AuthState.authenticating);

    try {
      // تنظيف البيانات السابقة
      await _clearSession();

      final encodedBody =
          'username=${Uri.encodeQueryComponent(username.trim())}&password=${Uri.encodeQueryComponent(password)}&grant_type=password';

      final response = await _makeAuthRequest('$_baseUrl/token', encodedBody);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['access_token'] == null) {
          _setState(AuthState.unauthenticated);
          return LoginResult.failure('استجابة غير متوقعة من الخادم');
        }

        // إنشاء معلومات التوكن
        _tokenInfo = TokenInfo.fromJson(data);

        // إنشاء جلسة المستخدم
        _userSession = UserSession(
          username: username,
          loginTime: DateTime.now(),
          rememberMe: rememberMe,
        );

        // حفظ الجلسة
        await _saveSession();
        await _saveLastRefreshTime();

        // بدء إدارة التوكن
        _startTokenManagement();

        _setState(AuthState.authenticated);

        debugPrint('✅ تم تسجيل الدخول بنجاح');
        return LoginResult.success(_tokenInfo!, _userSession!);
      } else if (response.statusCode == 400 || response.statusCode == 401) {
        _setState(AuthState.unauthenticated);
        return LoginResult.failure('بيانات الدخول غير صحيحة');
      } else {
        _setState(AuthState.unauthenticated);
        return LoginResult.failure('فشل الاتصال: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الدخول');
      _setState(AuthState.unauthenticated);
      return LoginResult.failure('خطأ في الاتصال');
    }
  }

  /// الحصول على توكن صالح مع تجديد تلقائي
  Future<String?> getValidAccessToken() async {
    if (_tokenInfo == null) {
      debugPrint('❌ لا يوجد توكن محفوظ');
      return null;
    }

    // إذا كان التوكن صالح
    if (_isTokenValid()) {
      return _tokenInfo!.accessToken;
    }

    // إذا كان يحتاج تجديد فوري
    if (_needsImmediateRefresh()) {
      debugPrint('🔄 التوكن يحتاج تجديد فوري');
      final success = await _refreshToken();
      return success ? _tokenInfo!.accessToken : null;
    }

    // إذا لا يمكن تجديده
    if (!_canRefreshToken()) {
      debugPrint('❌ انتهت صلاحية Refresh Token');
      await logout();
      return null;
    }

    return _tokenInfo!.accessToken;
  }

  /// تجديد التوكن مع إعادة المحاولة
  Future<bool> _refreshToken({int maxRetries = 2}) async {
    if (_tokenInfo?.refreshToken == null) {
      debugPrint('❌ لا يوجد Refresh Token');
      return false;
    }

    debugPrint('🔄 تجديد التوكن...');

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final body =
            'refresh_token=${_tokenInfo!.refreshToken}&grant_type=refresh_token';
        final response = await _makeAuthRequest('$_baseUrl/refresh', body);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          _tokenInfo = TokenInfo.fromJson(data);
          await _saveSession();
          await _saveLastRefreshTime();

          _emitTokenStatus(TokenStatus.refreshed);
          debugPrint('✅ تم تجديد التوكن بنجاح');
          return true;
        } else if (response.statusCode == 400 || response.statusCode == 401) {
          debugPrint('❌ Refresh Token غير صالح');
          return false;
        }

        // إعادة محاولة للأخطاء المؤقتة
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
          debugPrint('🔄 إعادة محاولة التجديد ($attempt/$maxRetries)');
        }
      } catch (e) {
        debugPrint('❌ خطأ في محاولة التجديد $attempt');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }

    debugPrint('❌ فشل في تجديد التوكن بعد $maxRetries محاولات');
    return false;
  }

  /// بدء إدارة التوكن التلقائية
  void _startTokenManagement() {
    _stopTokenManagement();

    // فحص دوري للتوكن
    _tokenCheckTimer = Timer.periodic(_tokenCheckInterval, (timer) async {
      await _checkTokenStatus();
    });

    // تجديد استباقي
    _schedulePreemptiveRefresh();
  }

  /// إيقاف إدارة التوكن
  void _stopTokenManagement() {
    _tokenCheckTimer?.cancel();
    _tokenRefreshTimer?.cancel();
    _preemptiveRefreshTimer?.cancel();
  }

  /// جدولة التجديد الاستباقي
  void _schedulePreemptiveRefresh() {
    _preemptiveRefreshTimer?.cancel();

    if (_tokenInfo == null) return;

    final timeToExpiry = _tokenInfo!.expiryTime.difference(DateTime.now());
    final refreshTime = timeToExpiry - _preemptiveRefreshThreshold;

    if (refreshTime.isNegative) {
      // يحتاج تجديد فوري
      _refreshToken();
      return;
    }

    debugPrint(
        '⏰ جدولة التجديد الاستباقي خلال: ${refreshTime.inMinutes} دقيقة');

    _preemptiveRefreshTimer = Timer(refreshTime, () async {
      debugPrint('🔄 بدء التجديد الاستباقي');
      _emitTokenStatus(TokenStatus.refreshing);
      await _refreshToken();
    });
  }

  /// فحص حالة التوكن
  Future<void> _checkTokenStatus() async {
    if (_tokenInfo == null) return;

    if (_needsImmediateRefresh()) {
      debugPrint('⚠️ التوكن يحتاج تجديد عاجل');
      _emitTokenStatus(TokenStatus.expiringSoon);

      if (_canRefreshToken()) {
        final success = await _refreshToken();
        if (!success) {
          await logout();
        }
      } else {
        await logout();
      }
    } else if (_shouldPreemptivelyRefresh()) {
      debugPrint('🔄 بدء التجديد الاستباقي المجدول');
      _emitTokenStatus(TokenStatus.refreshing);
      await _refreshToken();
    }
  }

  /// تسجيل الخروج مع تنظيف كامل
  Future<void> logout() async {
    debugPrint('🚪 تسجيل الخروج...');

    _stopTokenManagement();
    await _clearSession();

    _setState(AuthState.unauthenticated);
    _emitTokenStatus(TokenStatus.revoked);

    debugPrint('✅ تم تسجيل الخروج بنجاح');
  }

  /// إنشاء رؤوس HTTP مع التوكن
  Future<Map<String, String>> getAuthHeaders() async {
    final token = await getValidAccessToken();
    if (token == null) {
      throw AuthException('لا يوجد توكن صالح');
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  /// طلب HTTP محمي مع إعادة محاولة التوكن
  Future<http.Response> authenticatedRequest(
    String method,
    String url, {
    Map<String, String>? headers,
    Object? body,
    int maxRetries = 1,
  }) async {
    for (int attempt = 1; attempt <= maxRetries + 1; attempt++) {
      try {
        final authHeaders = await getAuthHeaders();
        final allHeaders = {...authHeaders, ...?headers};

        http.Response response;
        switch (method.toUpperCase()) {
          case 'GET':
            response = await http.get(Uri.parse(url), headers: allHeaders);
            break;
          case 'POST':
            response = await http.post(Uri.parse(url),
                headers: allHeaders, body: body);
            break;
          case 'PUT':
            response =
                await http.put(Uri.parse(url), headers: allHeaders, body: body);
            break;
          case 'DELETE':
            response = await http.delete(Uri.parse(url), headers: allHeaders);
            break;
          default:
            throw AuthException('طريقة HTTP غير مدعومة: $method');
        }

        // إذا كان الرد 401، جرب تجديد التوكن
        if (response.statusCode == 401 && attempt <= maxRetries) {
          debugPrint('🔄 استجابة 401، محاولة تجديد التوكن...');

          final refreshed = await _refreshToken();
          if (refreshed) {
            debugPrint('✅ تم تجديد التوكن، إعادة المحاولة...');
            continue;
          } else {
            debugPrint('❌ فشل تجديد التوكن');
            await logout();
            throw AuthException('انتهت جلسة المستخدم');
          }
        }

        return response;
      } catch (e) {
        if (e is AuthException) rethrow;
        if (attempt > maxRetries) {
          throw AuthException('خطأ في الطلب');
        }
        debugPrint('⚠️ خطأ في المحاولة $attempt');
        await Future.delayed(Duration(seconds: attempt));
      }
    }

    throw AuthException('فشل في تنفيذ الطلب');
  }

  // ===== دوال مساعدة =====

  bool _isTokenValid() {
    if (_tokenInfo == null) return false;
    return DateTime.now()
        .isBefore(_tokenInfo!.expiryTime.subtract(const Duration(minutes: 1)));
  }

  bool _needsImmediateRefresh() {
    if (_tokenInfo == null) return false;
    return DateTime.now()
        .isAfter(_tokenInfo!.expiryTime.subtract(_forceRefreshThreshold));
  }

  bool _shouldPreemptivelyRefresh() {
    if (_tokenInfo == null) return false;
    return DateTime.now()
        .isAfter(_tokenInfo!.expiryTime.subtract(_preemptiveRefreshThreshold));
  }

  bool _canRefreshToken() {
    if (_tokenInfo?.refreshToken == null) return false;
    return DateTime.now().isBefore(_tokenInfo!.refreshExpiryTime);
  }

  Future<http.Response> _makeAuthRequest(String url, String body) async {
    return await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
            'Accept': 'application/json, text/plain, */*',
            'Origin': 'https://admin.ftth.iq',
            'Referer': 'https://admin.ftth.iq/auth/login',
            'x-client-app': '53d57a7f-3f89-4e9d-873b-3d071bc6dd9f',
            'x-kl-ajax-request': 'Ajax_Request',
            'x-user-role': '0',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 15));
  }

  void _setState(AuthState state) {
    if (_currentState != state) {
      _currentState = state;
      if (!_authStateController.isClosed) {
        _authStateController.add(state);
      }
    }
  }

  void _emitTokenStatus(TokenStatus status) {
    if (!_tokenStatusController.isClosed) {
      _tokenStatusController.add(status);
    }
  }

  // ===== تخزين البيانات =====

  Future<void> _saveSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_tokenInfo != null) {
        await prefs.setString(_tokenInfoKey, jsonEncode(_tokenInfo!.toJson()));
      }

      if (_userSession != null) {
        await prefs.setString(
            _userSessionKey, jsonEncode(_userSession!.toJson()));
      }
    } catch (e) {
      debugPrint('❌ خطأ في حفظ الجلسة');
    }
  }

  Future<void> _loadStoredSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final tokenJson = prefs.getString(_tokenInfoKey);
      if (tokenJson != null) {
        _tokenInfo = TokenInfo.fromJson(jsonDecode(tokenJson));
      }

      final sessionJson = prefs.getString(_userSessionKey);
      if (sessionJson != null) {
        _userSession = UserSession.fromJson(jsonDecode(sessionJson));
      }
    } catch (e) {
      debugPrint('❌ خطأ في تحميل الجلسة');
      await _clearSession();
    }
  }

  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenInfoKey);
      await prefs.remove(_userSessionKey);
      await prefs.remove(_lastRefreshKey);

      _tokenInfo = null;
      _userSession = null;
    } catch (e) {
      debugPrint('❌ خطأ في مسح الجلسة');
    }
  }

  Future<void> _saveLastRefreshTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastRefreshKey, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('❌ خطأ في حفظ وقت التجديد');
    }
  }

  void dispose() {
    _stopTokenManagement();
    _authStateController.close();
    _tokenStatusController.close();
  }
}

// ===== نماذج البيانات =====

class TokenInfo {
  final String accessToken;
  final String refreshToken;
  final DateTime expiryTime;
  final DateTime refreshExpiryTime;
  final String tokenType;

  TokenInfo({
    required this.accessToken,
    required this.refreshToken,
    required this.expiryTime,
    required this.refreshExpiryTime,
    required this.tokenType,
  });

  factory TokenInfo.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final expiresIn = (json['expires_in'] ?? 3600) as num;
    final refreshExpiresIn = (json['refresh_expires_in'] ?? 691200) as num;

    return TokenInfo(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiryTime: now.add(Duration(seconds: expiresIn.toInt())),
      refreshExpiryTime: now.add(Duration(seconds: refreshExpiresIn.toInt())),
      tokenType: json['token_type'] ?? 'Bearer',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expiry_time': expiryTime.toIso8601String(),
      'refresh_expiry_time': refreshExpiryTime.toIso8601String(),
      'token_type': tokenType,
    };
  }

  Duration get timeToExpiry => expiryTime.difference(DateTime.now());
  Duration get timeToRefreshExpiry =>
      refreshExpiryTime.difference(DateTime.now());
  bool get isExpired => DateTime.now().isAfter(expiryTime);
  bool get isRefreshExpired => DateTime.now().isAfter(refreshExpiryTime);
}

class UserSession {
  final String username;
  final DateTime loginTime;
  final bool rememberMe;
  final Map<String, dynamic> metadata;

  UserSession({
    required this.username,
    required this.loginTime,
    required this.rememberMe,
    this.metadata = const {},
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      username: json['username'] as String,
      loginTime: DateTime.parse(json['login_time'] as String),
      rememberMe: json['remember_me'] as bool,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'login_time': loginTime.toIso8601String(),
      'remember_me': rememberMe,
      'metadata': metadata,
    };
  }

  Duration get sessionDuration => DateTime.now().difference(loginTime);
}

class LoginResult {
  final bool isSuccess;
  final TokenInfo? tokenInfo;
  final UserSession? userSession;
  final String? errorMessage;

  LoginResult._({
    required this.isSuccess,
    this.tokenInfo,
    this.userSession,
    this.errorMessage,
  });

  factory LoginResult.success(TokenInfo tokenInfo, UserSession userSession) {
    return LoginResult._(
      isSuccess: true,
      tokenInfo: tokenInfo,
      userSession: userSession,
    );
  }

  factory LoginResult.failure(String errorMessage) {
    return LoginResult._(
      isSuccess: false,
      errorMessage: errorMessage,
    );
  }
}

// ===== تعدادات الحالة =====

enum AuthState {
  checking,
  unauthenticated,
  authenticating,
  authenticated,
  refreshing,
  error,
}

enum TokenStatus {
  valid,
  expiringSoon,
  refreshing,
  refreshed,
  expired,
  revoked,
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}
