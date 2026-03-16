/// اسم الصفحة: النظام المتقدم FTTH
/// وصف الصفحة: النظام المتقدم لإدارة الألياف البصرية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;
import 'package:url_launcher/url_launcher.dart';

/// النظام الثالث - نظام إدارة داشبورد FTTH المتقدم
class FTTHAdvancedSystemPage extends StatelessWidget {
  const FTTHAdvancedSystemPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        primarySwatch: Colors.blue,
        primaryColor: const Color(0xFF667eea),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF667eea),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF667eea),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          titleTextStyle: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF667eea),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 12,
            ),
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: Colors.grey.shade300,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
      child: const AdvancedSplashScreen(),
    );
  }
}

// ===== خدمة المصادقة المتقدمة =====
class AdvancedAuthService {
  static const String _baseUrl = 'https://admin.ftth.iq/api';
  static const String _tokenKey = 'ftth_advanced_auth_tokens';
  static const String _userKey = 'ftth_advanced_user_info';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static UserInfo? _currentUser;
  static AuthTokens? _currentTokens;

  static Future<LoginResult> login(String username, String password) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/Contractor/token'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> tokenData = jsonDecode(response.body);
        final tokens = AuthTokens.fromJson(tokenData);

        final userInfo = await _getUserInfo(tokens.accessToken);

        await _saveTokens(tokens);
        await _saveUserInfo(userInfo);

        _currentTokens = tokens;
        _currentUser = userInfo;

        return LoginResult.success(tokens, userInfo);
      } else {
        throw Exception('فشل في تسجيل الدخول: ${response.statusCode}');
      }
    } catch (e) {
      if (username == 'sa' && password == 'Ss123456123456') {
        // إنشاء نظام تجريبي محسن
        final mockTokens = AuthTokens(
          accessToken:
              'demo_access_token_${DateTime.now().millisecondsSinceEpoch}',
          refreshToken:
              'demo_refresh_token_${DateTime.now().millisecondsSinceEpoch}',
          expiresIn: 3600,
          tokenType: 'Bearer',
        );

        final mockUserInfo = UserInfo(
          username: 'sa',
          accountId: '2261175',
          roles: ['SuperAdminMember', 'ContractorMember'],
          groups: ['/Team_Contractor_2261175_Members'],
          loginTime: DateTime.now(),
          email: 'sa@ftth.iq',
        );

        await _saveTokens(mockTokens);
        await _saveUserInfo(mockUserInfo);

        _currentTokens = mockTokens;
        _currentUser = mockUserInfo;

        debugPrint(
            'تسجيل دخول تجريبي نجح - سيتم استخدام رابط تجريبي للداشبورد');
        return LoginResult.success(mockTokens, mockUserInfo);
      }

      return LoginResult.failure('اسم المستخدم أو كلمة المرور غير صحيحة');
    }
  }

  static Future<UserInfo> _getUserInfo(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/me'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> userData = jsonDecode(response.body);
        return UserInfo.fromJson(userData);
      } else {
        throw Exception('فشل في الحصول على معلومات المستخدم');
      }
    } catch (e) {
      return UserInfo(
        username: 'sa',
        accountId: '2261175',
        roles: ['SuperAdminMember', 'ContractorMember'],
        groups: ['/Team_Contractor_2261175_Members'],
        loginTime: DateTime.now(),
        email: 'sa@ftth.iq',
      );
    }
  }

  static Future<AuthTokens?> refreshToken() async {
    final currentTokens = await getStoredTokens();
    if (currentTokens?.refreshToken == null) {
      return null;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/auth/refresh'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'refresh_token': currentTokens!.refreshToken,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> tokenData = jsonDecode(response.body);
        final newTokens = AuthTokens.fromJson(tokenData);

        await _saveTokens(newTokens);
        _currentTokens = newTokens;

        return newTokens;
      } else {
        throw Exception('فشل في تجديد التوكن');
      }
    } catch (e) {
      return null;
    }
  }

  static Future<bool> isAuthenticated() async {
    final tokens = await getStoredTokens();
    final userInfo = await getStoredUserInfo();

    if (tokens?.accessToken == null || userInfo == null) {
      return false;
    }

    final tokenAge = DateTime.now().difference(tokens!.issuedAt);
    final tokenExpiry = Duration(seconds: tokens.expiresIn);

    if (tokenAge >= tokenExpiry) {
      final newTokens = await refreshToken();
      return newTokens != null;
    }

    return true;
  }

  static Future<AuthTokens?> getStoredTokens() async {
    if (_currentTokens != null) return _currentTokens;

    try {
      final tokensJson = await _secureStorage.read(key: _tokenKey);
      if (tokensJson != null) {
        final Map<String, dynamic> tokensData = jsonDecode(tokensJson);
        _currentTokens = AuthTokens.fromJson(tokensData);
        return _currentTokens;
      }
    } catch (e) {
      debugPrint('خطأ في قراءة التوكنات');
    }
    return null;
  }

  static Future<UserInfo?> getStoredUserInfo() async {
    if (_currentUser != null) return _currentUser;

    try {
      final userJson = await _secureStorage.read(key: _userKey);
      if (userJson != null) {
        final Map<String, dynamic> userData = jsonDecode(userJson);
        _currentUser = UserInfo.fromJson(userData);
        return _currentUser;
      }
    } catch (e) {
      debugPrint('خطأ في قراءة معلومات المستخدم');
    }
    return null;
  }

  static Future<void> _saveTokens(AuthTokens tokens) async {
    try {
      final tokensJson = jsonEncode(tokens.toJson());
      await _secureStorage.write(key: _tokenKey, value: tokensJson);
    } catch (e) {
      debugPrint('خطأ في حفظ التوكنات');
    }
  }

  static Future<void> _saveUserInfo(UserInfo userInfo) async {
    try {
      final userJson = jsonEncode(userInfo.toJson());
      await _secureStorage.write(key: _userKey, value: userJson);
    } catch (e) {
      debugPrint('خطأ في حفظ معلومات المستخدم');
    }
  }

  static Future<void> logout() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
      await _secureStorage.delete(key: _userKey);
      _currentTokens = null;
      _currentUser = null;
    } catch (e) {
      debugPrint('خطأ في تسجيل الخروج');
    }
  }

  static Future<String> getDashboardUrl(String dashboardId) async {
    final tokens = await getStoredTokens();
    const baseUrl = 'https://dashboard.ftth.iq/embedded/';

    if (tokens?.accessToken != null) {
      // إذا كان التوكن تجريبي، استخدم رابط تجريبي بدلاً من APISIX
      if (tokens!.accessToken.startsWith('demo_access_token_')) {
        // رابط تجريبي يعمل بدون مصادقة APISIX
        return 'https://dashboard.ftth.iq/public-chart/f5c4dd61-c4db-457a-9ad4-7cd7a30fb8b1/0a7fd1ba-1e24-4f62-8c8a-7d764eef3d9e?demo=true';
      }
      return '$baseUrl$dashboardId?token=${tokens.accessToken}';
    }

    return '$baseUrl$dashboardId';
  }

  static UserInfo? get currentUser => _currentUser;
  static AuthTokens? get currentTokens => _currentTokens;
}

// ===== نماذج البيانات =====
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String tokenType;
  final DateTime issuedAt;

  AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
    DateTime? issuedAt,
  }) : issuedAt = issuedAt ?? DateTime.now();

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] ?? '',
      refreshToken: json['refresh_token'] ?? '',
      expiresIn: json['expires_in'] ?? 3600,
      tokenType: json['token_type'] ?? 'Bearer',
      issuedAt: json['issued_at'] != null
          ? DateTime.parse(json['issued_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'expires_in': expiresIn,
      'token_type': tokenType,
      'issued_at': issuedAt.toIso8601String(),
    };
  }
}

class UserInfo {
  final String username;
  final String accountId;
  final List<String> roles;
  final List<String> groups;
  final DateTime loginTime;
  final String? email;

  UserInfo({
    required this.username,
    required this.accountId,
    required this.roles,
    required this.groups,
    required this.loginTime,
    this.email,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      username: json['username'] ?? '',
      accountId: json['accountId'] ?? json['account_id'] ?? '',
      roles: List<String>.from(json['roles'] ?? []),
      groups: List<String>.from(json['groups'] ?? []),
      loginTime: json['loginTime'] != null
          ? DateTime.parse(json['loginTime'])
          : DateTime.now(),
      email: json['email'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'accountId': accountId,
      'roles': roles,
      'groups': groups,
      'loginTime': loginTime.toIso8601String(),
      'email': email,
    };
  }
}

class LoginResult {
  final bool isSuccess;
  final AuthTokens? tokens;
  final UserInfo? userInfo;
  final String? errorMessage;

  LoginResult._({
    required this.isSuccess,
    this.tokens,
    this.userInfo,
    this.errorMessage,
  });

  factory LoginResult.success(AuthTokens tokens, UserInfo userInfo) {
    return LoginResult._(
      isSuccess: true,
      tokens: tokens,
      userInfo: userInfo,
    );
  }

  factory LoginResult.failure(String errorMessage) {
    return LoginResult._(
      isSuccess: false,
      errorMessage: errorMessage,
    );
  }
}

// ===== شاشة البداية المتقدمة =====
class AdvancedSplashScreen extends StatefulWidget {
  const AdvancedSplashScreen({super.key});

  @override
  State<AdvancedSplashScreen> createState() => _AdvancedSplashScreenState();
}

class _AdvancedSplashScreenState extends State<AdvancedSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.forward();
    _checkAuthStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthStatus() async {
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;

    try {
      final isAuthenticated = await AdvancedAuthService.isAuthenticated();

      if (isAuthenticated) {
        final userInfo = await AdvancedAuthService.getStoredUserInfo();
        final tokens = await AdvancedAuthService.getStoredTokens();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => AdvancedDashboardPage(
              username: userInfo?.username ?? '',
              accessToken: tokens?.accessToken ?? '',
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const AdvancedLoginPage(),
          ),
        );
      }
    } catch (e) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const AdvancedLoginPage(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(60),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.dashboard,
                    size: 60,
                    color: Color(0xFF667eea),
                  ),
                ),
                const SizedBox(height: 30),
                const Text(
                  'النظام المتقدم',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'FTTH Dashboard Pro',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 50),
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== صفحة تسجيل الدخول المتقدمة =====
class AdvancedLoginPage extends StatefulWidget {
  const AdvancedLoginPage({super.key});

  @override
  State<AdvancedLoginPage> createState() => _AdvancedLoginPageState();
}

class _AdvancedLoginPageState extends State<AdvancedLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      final result = await AdvancedAuthService.login(username, password);

      if (result.isSuccess) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => AdvancedDashboardPage(
                username: result.userInfo?.username ?? '',
                accessToken: result.tokens?.accessToken ?? '',
              ),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = result.errorMessage;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ أثناء تسجيل الدخول';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFF667eea),
              Color(0xFF764ba2),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Card(
                elevation: 15,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.dashboard,
                          size: 80,
                          color: Color(0xFF667eea),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'النظام المتقدم',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF667eea),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'تسجيل الدخول إلى لوحة التحكم',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 40),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'اسم المستخدم',
                            prefixIcon: Icon(Icons.person),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال اسم المستخدم';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال كلمة المرور';
                            }
                            return null;
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              border: Border.all(color: Colors.red[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red[700]),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            child: _isLoading
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text(
                                    'تسجيل الدخول',
                                    style: TextStyle(fontSize: 18),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'بيانات تجريبية:\nاسم المستخدم: sa\nكلمة المرور: Ss123456123456',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== لوحة التحكم المتقدمة =====
class AdvancedDashboardPage extends StatefulWidget {
  final String username;
  final String accessToken;

  const AdvancedDashboardPage({
    super.key,
    required this.username,
    required this.accessToken,
  });

  @override
  State<AdvancedDashboardPage> createState() => _AdvancedDashboardPageState();
}

class _AdvancedDashboardPageState extends State<AdvancedDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  UserInfo? _userInfo;
  AuthTokens? _authTokens;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final userInfo = await AdvancedAuthService.getStoredUserInfo();
      final tokens = await AdvancedAuthService.getStoredTokens();

      setState(() {
        _userInfo = userInfo;
        _authTokens = tokens;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج من النظام المتقدم؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('تسجيل الخروج'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await AdvancedAuthService.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AdvancedLoginPage()),
          (route) => false,
        );
      }
    }
  }

  Future<void> _openDashboard(String dashboardId, String title) async {
    try {
      final url = await AdvancedAuthService.getDashboardUrl(dashboardId);
      final tokens = await AdvancedAuthService.getStoredTokens();

      // تحقق إذا كان النظام تجريبي
      bool isDemoMode =
          tokens?.accessToken.startsWith('demo_access_token_') ?? false;

      if (isDemoMode) {
        // إظهار رسالة للوضع التجريبي
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  '🔧 الوضع التجريبي: سيتم فتح رابط تجريبي عام للمعاينة'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }

      // في Windows، افتح مباشرة في المتصفح الخارجي
      if (Platform.isWindows) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('لا يمكن فتح الرابط'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // على الأنظمة الأخرى، حاول استخدام WebView
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdvancedWebViewPage(
              url: url,
              title: title,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في فتح الداشبورد'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يمكن فتح الرابط'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('النظام المتقدم - لوحة التحكم'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'تسجيل الخروج',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle:
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'لوحات التحكم'),
            Tab(icon: Icon(Icons.person), text: 'الملف الشخصي'),
            Tab(icon: Icon(Icons.security), text: 'التوكنات'),
            Tab(icon: Icon(Icons.settings), text: 'الإعدادات'),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF7FAFC),
              Colors.white,
            ],
            stops: [0.0, 0.3],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            double contentWidth = maxWidth;
            if (maxWidth > 1440) {
              contentWidth = 1200;
            } else if (maxWidth > 1024) {
              contentWidth = 1100;
            } else if (maxWidth > 600) {
              contentWidth = 900;
            }

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDashboardsTab(),
                    _buildProfileTab(),
                    _buildTokensTab(),
                    _buildSettingsTab(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDashboardsTab() {
    // تحقق من الوضع التجريبي
    final tokens = AdvancedAuthService.currentTokens;
    bool isDemoMode =
        tokens?.accessToken.startsWith('demo_access_token_') ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // رسالة الوضع التجريبي
          if (isDemoMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.science, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🔧 الوضع التجريبي نشط - البيانات المعروضة للاختبار فقط',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.dashboard,
                  size: 50,
                  color: Colors.white,
                ),
                const SizedBox(height: 10),
                Text(
                  'مرحباً ${_userInfo?.username ?? widget.username}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'النظام المتقدم لإدارة FTTH',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _buildDashboardCard(
                  title: 'داشبورد المقاولين',
                  subtitle: 'إدارة شاملة للمقاولين',
                  icon: Icons.business,
                  color: Colors.blue,
                  onTap: () => _openDashboard('1', 'داشبورد المقاولين'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDashboardCard(
                  title: 'داشبورد التحليلات',
                  subtitle: 'تحليلات متقدمة',
                  icon: Icons.analytics,
                  color: Colors.green,
                  onTap: () => _openDashboard('7', 'داشبورد التحليلات'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildLinksCard(),
        ],
      ),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 40,
                color: color,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinksCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.link, color: Color(0xFF667eea)),
                SizedBox(width: 8),
                Text(
                  'الروابط المفيدة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildLinkItem(
              title: 'لوحة الإدارة',
              url: 'https://admin.ftth.iq',
              icon: Icons.admin_panel_settings,
            ),
            const Divider(),
            _buildLinkItem(
              title: 'نظام التحليلات',
              url: 'https://dashboard.ftth.iq',
              icon: Icons.analytics,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkItem({
    required String title,
    required String url,
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF667eea)),
      title: Text(title),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => _openExternalUrl(url),
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.person, color: Color(0xFF667eea), size: 30),
                  SizedBox(width: 12),
                  Text(
                    'الملف الشخصي',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildInfoRow(
                  'اسم المستخدم', _userInfo?.username ?? widget.username),
              _buildInfoRow('معرف الحساب', _userInfo?.accountId ?? 'غير محدد'),
              _buildInfoRow(
                  'البريد الإلكتروني', _userInfo?.email ?? 'غير محدد'),
              _buildInfoRow(
                  'الأدوار', _userInfo?.roles.join(', ') ?? 'غير محدد'),
              _buildInfoRow(
                  'المجموعات', _userInfo?.groups.join(', ') ?? 'غير محدد'),
              _buildInfoRow(
                  'وقت تسجيل الدخول',
                  _userInfo?.loginTime.toString().substring(0, 19) ??
                      'غير محدد'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokensTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.security, color: Color(0xFF667eea), size: 30),
                  SizedBox(width: 12),
                  Text(
                    'إدارة التوكنات',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildTokenField(
                  'Access Token', _authTokens?.accessToken ?? 'غير متوفر'),
              _buildTokenField(
                  'Refresh Token', _authTokens?.refreshToken ?? 'غير متوفر'),
              _buildInfoCard(
                'انتهاء الصلاحية',
                '${_authTokens?.expiresIn ?? 0} ثانية',
                Icons.timer,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // تجديد التوكن
                    try {
                      final newTokens =
                          await AdvancedAuthService.refreshToken();
                      if (newTokens != null) {
                        setState(() {
                          _authTokens = newTokens;
                        });

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تجديد التوكن بنجاح'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } else {
                        throw Exception('فشل في تجديد التوكن');
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('خطأ في تجديد التوكن'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('تجديد التوكن'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.length > 50 ? '${value.substring(0, 50)}...' : value,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم نسخ التوكن')),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF667eea), size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF2D3748),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.settings, color: Color(0xFF667eea), size: 30),
                      SizedBox(width: 12),
                      Text(
                        'إعدادات النظام',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildSettingItem('إصدار التطبيق', '3.0.0', Icons.info),
                  _buildSettingItem('نوع النظام', 'متقدم', Icons.star),
                  _buildSettingItem('حالة الاتصال', 'متصل', Icons.wifi,
                      valueColor: Colors.green),
                  _buildSettingItem('آخر تحديث',
                      DateTime.now().toString().substring(0, 19), Icons.update),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج من النظام'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(
    String title,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF667eea), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: valueColor ?? const Color(0xFF2D3748),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ===== صفحة WebView المتقدمة =====
class AdvancedWebViewPage extends StatefulWidget {
  final String url;
  final String title;

  const AdvancedWebViewPage({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  State<AdvancedWebViewPage> createState() => _AdvancedWebViewPageState();
}

class _AdvancedWebViewPageState extends State<AdvancedWebViewPage> {
  WebViewController? _controller;
  windows_webview.WebviewController? _windowsController;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isWindows = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() async {
    try {
      // تحقق من نوع المنصة
      _isWindows = Platform.isWindows;

      if (_isWindows) {
        // على Windows، اعرض رسالة ووفر خيار المتصفح الخارجي
        setState(() {
          _errorMessage =
              'WebView قد لا يعمل بشكل مثالي على Windows. يُنصح بفتح الرابط في المتصفح الخارجي.';
          _isLoading = false;
        });
      } else {
        _initializeFlutterWebView();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في تهيئة WebView';
        _isLoading = false;
      });
    }
  }

  void _initializeFlutterWebView() {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            },
            onPageFinished: (String url) {
              setState(() {
                _isLoading = false;
              });
            },
            onWebResourceError: (WebResourceError error) {
              setState(() {
                String errorMsg = 'خطأ في تحميل الصفحة: ${error.description}';

                // معالجة خاصة لخطأ 401
                if (error.description.contains('401') ||
                    error.description.contains('Authorization Required') ||
                    error.description.contains('Unauthorized')) {
                  errorMsg = '''
خطأ في المصادقة (401):
• قد يكون التوكن منتهي الصلاحية
• للنظام التجريبي: تم فتح رابط تجريبي لا يحتاج مصادقة
• للنظام الحقيقي: يرجى تسجيل الدخول بحساب صحيح
• يُنصح بفتح الرابط في المتصفح الخارجي لمعاينة أفضل
                  '''
                      .trim();
                } else if (error.description
                        .contains('net::ERR_NETWORK_CHANGED') ||
                    error.description
                        .contains('net::ERR_INTERNET_DISCONNECTED')) {
                  errorMsg =
                      'خطأ في الاتصال بالإنترنت. يرجى التحقق من الاتصال والمحاولة مرة أخرى.';
                }

                _errorMessage = errorMsg;
                _isLoading = false;
              });
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في تهيئة WebView';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    // تنظيف الموارد إذا لزم الأمر
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (!_isWindows && _controller != null) {
                _controller!.reload();
              } else {
                // إعادة تهيئة
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _initializeWebView();
              }
            },
            tooltip: 'إعادة تحميل',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: () async {
              final uri = Uri.parse(widget.url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            tooltip: 'فتح في المتصفح',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.warning,
              size: 64,
              color: Colors.orange,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16, color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                final uri = Uri.parse(widget.url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('لا يمكن فتح الرابط'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.open_in_browser),
              label: const Text('فتح في المتصفح الخارجي'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _initializeWebView();
              },
              child: const Text('إعادة المحاولة'),
            ),
            const SizedBox(height: 20),
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  const Text(
                    'معلومات الرابط:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.url,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري التحميل...'),
          ],
        ),
      );
    }

    if (_isWindows && _windowsController != null) {
      return windows_webview.Webview(_windowsController!);
    } else if (_isWindows && _windowsController != null) {
      return windows_webview.Webview(_windowsController!);
    } else if (!_isWindows && _controller != null) {
      return WebViewWidget(controller: _controller!);
    }

    return const Center(
      child: Text('جاري تهيئة WebView...'),
    );
  }
}
