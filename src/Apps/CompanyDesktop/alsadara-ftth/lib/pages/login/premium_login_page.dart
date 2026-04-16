/// صفحة تسجيل دخول فخمة ومتجاوبة
/// تدعم جميع أحجام الشاشات (حاسوب، تابلت، هاتف)
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/vps_auth_service.dart';
import '../../services/api/api_client.dart';
import '../../permissions/permissions.dart';
import '../../widgets/update_dialog.dart';
import '../../services/dual_auth_service.dart';
import '../../services/fcm_token_service.dart';
import '../home_page.dart';
import '../super_admin/super_admin_dashboard.dart';
import '../offline_router_setup_page.dart';

// ============================================
// نماذج البيانات
// ============================================

/// نموذج بيانات تسجيل الدخول المحفوظة
class SavedCredential {
  final String companyCode;
  final String companyName;
  final String username;
  final String password;
  final DateTime savedAt;

  SavedCredential({
    required this.companyCode,
    required this.companyName,
    required this.username,
    required this.password,
    required this.savedAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedCredential &&
          companyCode == other.companyCode &&
          username == other.username;

  @override
  int get hashCode => companyCode.hashCode ^ username.hashCode;

  Map<String, dynamic> toJson() => {
        'companyCode': companyCode,
        'companyName': companyName,
        'username': username,
        'password': password,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedCredential.fromJson(Map<String, dynamic> json) =>
      SavedCredential(
        companyCode: json['companyCode'] ?? '',
        companyName: json['companyName'] ?? '',
        username: json['username'] ?? '',
        password: json['password'] ?? '',
        savedAt: json['savedAt'] != null
            ? DateTime.parse(json['savedAt'])
            : DateTime.now(),
      );

  String get displayName => '$username - $companyName';
}

/// نموذج الشركة
class CompanyListItem {
  final String id;
  final String name;
  final String code;
  final String? logoUrl;

  CompanyListItem({
    required this.id,
    required this.name,
    required this.code,
    this.logoUrl,
  });

  factory CompanyListItem.fromJson(Map<String, dynamic> json) =>
      CompanyListItem(
        id: json['Id']?.toString() ?? json['id']?.toString() ?? '',
        name: json['Name'] ?? json['name'] ?? '',
        code: json['Code'] ?? json['code'] ?? '',
        logoUrl: json['LogoUrl'] ?? json['logoUrl'],
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyListItem &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;
}

// ============================================
// الصفحة الرئيسية
// ============================================

class PremiumLoginPage extends StatefulWidget {
  const PremiumLoginPage({super.key});

  @override
  State<PremiumLoginPage> createState() => _PremiumLoginPageState();
}

class _PremiumLoginPageState extends State<PremiumLoginPage>
    with TickerProviderStateMixin {
  // Controllers
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = VpsAuthService.instance;

  // State
  bool _isLoading = false;
  bool _isNavigating = false; // حالة التحميل بعد نجاح الدخول
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _rememberMe = false;

  // Companies
  List<CompanyListItem> _companies = [];
  CompanyListItem? _selectedCompany;
  bool _loadingCompanies = true;
  String? _companiesLoadError;

  // Saved credentials
  List<SavedCredential> _savedCredentials = [];
  SavedCredential? _selectedCredential;

  // App version
  String _appVersion = '';

  // Animations
  late AnimationController _formAnimController;
  late Animation<double> _formSlideAnimation;
  late Animation<double> _formFadeAnimation;

  // ألوان التصميم
  static const _primaryGradient = [
    Color(0xFF667eea),
    Color(0xFF764ba2),
  ];
  static const _secondaryGradient = [
    Color(0xFF11998e),
    Color(0xFF38ef7d),
  ];

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _loadAllData();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  /// تحميل جميع البيانات مع SharedPreferences موحد
  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();
    _loadCompanies(prefs);
    _loadSavedCredentials(prefs);
  }

  void _initAnimations() {
    _formAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _formSlideAnimation = Tween<double>(begin: 50, end: 0).animate(
      CurvedAnimation(parent: _formAnimController, curve: Curves.easeOutCubic),
    );

    _formFadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _formAnimController, curve: Curves.easeOut),
    );

    _formAnimController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _formAnimController.dispose();
    super.dispose();
  }

  // ============================================
  // Data Loading
  // ============================================

  Future<void> _loadCompanies([SharedPreferences? prefsParam]) async {
    // تحميل الكاش أولاً للظهور الفوري
    try {
      final prefs = prefsParam ?? await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('cached_companies_list');
      if (cachedJson != null && mounted) {
        final List<dynamic> cachedList = jsonDecode(cachedJson);
        setState(() {
          _companies = cachedList
              .map((c) => CompanyListItem.fromJson(c as Map<String, dynamic>))
              .toList();
          _loadingCompanies = false;
        });
      }
    } catch (_) {}

    // جلب من السيرفر في الخلفية
    try {
      final response = await ApiClient.instance.get(
        '/companies/list',
        (json) => json,
      );

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        final data = response.data;
        List<dynamic> companiesList = [];

        if (data is List) {
          companiesList = data;
        } else if (data is Map && data['data'] != null) {
          companiesList = data['data'] as List;
        } else if (data is Map && data['success'] == true) {
          final innerData = data['data'];
          if (innerData is List) companiesList = innerData;
        }

        setState(() {
          _companies = companiesList
              .map((c) => CompanyListItem.fromJson(c as Map<String, dynamic>))
              .toList();
          _loadingCompanies = false;
          _companiesLoadError =
              _companies.isEmpty ? 'لا توجد شركات مسجلة' : null;
        });

        // حفظ الكاش
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              'cached_companies_list', jsonEncode(companiesList));
        } catch (_) {}
      } else {
        setState(() {
          _loadingCompanies = false;
          _companiesLoadError = response.message ?? 'فشل في جلب قائمة الشركات';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCompanies = false;
        _companiesLoadError =
            _companies.isEmpty ? 'خطأ في الاتصال بالخادم' : null;
      });
    }
  }

  Future<void> _loadSavedCredentials([SharedPreferences? prefsParam]) async {
    try {
      final prefs = prefsParam ?? await SharedPreferences.getInstance();
      final savedJson = prefs.getString('vps_saved_credentials');

      if (savedJson != null) {
        final List<dynamic> savedList = jsonDecode(savedJson);
        setState(() {
          _savedCredentials = savedList
              .map((item) =>
                  SavedCredential.fromJson(item as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('خطأ في تحميل بيانات الدخول المحفوظة');
    }
  }

  Future<void> _saveCredential() async {
    if (!_rememberMe || _selectedCompany == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      _savedCredentials.removeWhere((c) =>
          c.companyCode == _selectedCompany!.code &&
          c.username == _usernameController.text.trim());

      _savedCredentials.insert(
        0,
        SavedCredential(
          companyCode: _selectedCompany!.code,
          companyName: _selectedCompany!.name,
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          savedAt: DateTime.now(),
        ),
      );

      if (_savedCredentials.length > 10) {
        _savedCredentials = _savedCredentials.sublist(0, 10);
      }

      await prefs.setString(
        'vps_saved_credentials',
        jsonEncode(_savedCredentials.map((c) => c.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('خطأ في حفظ بيانات الدخول');
    }
  }

  Future<void> _deleteCredential(SavedCredential credential) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _savedCredentials.removeWhere((c) =>
            c.companyCode == credential.companyCode &&
            c.username == credential.username);
        _selectedCredential = null;
      });

      await prefs.setString(
        'vps_saved_credentials',
        jsonEncode(_savedCredentials.map((c) => c.toJson()).toList()),
      );

      if (mounted) {
        _showSnackBar('تم حذف بيانات الدخول', Colors.orange);
      }
    } catch (e) {
      debugPrint('خطأ في حذف بيانات الدخول');
    }
  }

  void _selectCredential(SavedCredential credential) {
    setState(() {
      _selectedCredential = credential;
      _usernameController.text = credential.username;
      _passwordController.text = credential.password;

      final companyIndex =
          _companies.indexWhere((c) => c.code == credential.companyCode);

      if (companyIndex != -1) {
        _selectedCompany = _companies[companyIndex];
      } else if (credential.companyCode == '1') {
        _selectedCompany = CompanyListItem(
          id: '1',
          name: 'مدير النظام',
          code: '1',
        );
      } else {
        _selectedCompany = null;
      }
    });
  }

  // ============================================
  // Login
  // ============================================

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCompany == null) {
      setState(() => _errorMessage = 'يرجى اختيار الشركة');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Haptic feedback
    HapticFeedback.mediumImpact();

    try {
      final result = await _authService.login(
        companyCodeOrType: _selectedCompany!.code,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (result.success) {
        // حفظ بيانات الدخول في الخلفية (بدون انتظار)
        _saveCredential();
        HapticFeedback.heavyImpact();
        // إظهار شاشة التحميل الجميلة والانتقال فوراً
        setState(() => _isNavigating = true);
        _navigateAfterLogin();
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _isLoading = false;
          _errorMessage = result.errorMessage ?? 'حدث خطأ غير متوقع';
        });
      }
    } catch (e) {
      HapticFeedback.vibrate();
      setState(() {
        _isLoading = false;
        _errorMessage = 'حدث خطأ في الاتصال';
      });
    }
  }

  void _navigateAfterLogin() async {
    try {
    // مسح بيانات FTTH القديمة قبل الانتقال لمنع رؤية home_page لبيانات المستخدم السابق
    await DualAuthService.instance.clearFtthData();
    // 🔄 تسجيل دخول FTTH الصامت في الخلفية (لا ينتظر)
    _performSilentFtthLogin();
    // 🔔 تسجيل FCM token في الخلفية (لا ينتظر)
    FcmTokenService.instance.registerToken();
    FcmTokenService.instance.listenForTokenRefresh();

    if (_authService.isSuperAdmin) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SuperAdminDashboard(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 150),
        ),
      );
      // فحص التحديثات بعد الانتقال (بدون حظر)
      _checkForUpdatesAfterLogin();
    } else if (_authService.currentUser != null &&
        _authService.currentCompany != null) {
      final user = _authService.currentUser!;
      final company = _authService.currentCompany!;

      // V2: تحميل الصلاحيات من PermissionManager
      try {
        final pm = PermissionManager.instance;
        if (!pm.isLoaded) {
          await pm.loadPermissions();
        }
      } catch (e) {
        debugPrint('⚠️ فشل تحميل الصلاحيات: $e');
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => HomePage(
            username: user.fullName.isNotEmpty ? user.fullName : user.username,
            permissions: user.isAdmin ? 'مدير' : _mapRoleToArabic(user.role),
            department: user.department?.isNotEmpty == true ? user.department! : company.name,
            center: company.code,
            salary: '0',
            tenantId: company.id,
            tenantCode: company.code,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 150),
        ),
      );
      // فحص التحديثات بعد الانتقال (بدون حظر)
      _checkForUpdatesAfterLogin();
    }
    } catch (e) {
      debugPrint('❌ خطأ في التنقل بعد الدخول: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isNavigating = false;
          _errorMessage = 'حدث خطأ أثناء تحميل الصفحة الرئيسية';
        });
      }
    }
  }

  /// تسجيل دخول FTTH صامت في الخلفية (لا يمنع التنقل)
  Future<void> _performSilentFtthLogin() async {
    try {
      final result = await DualAuthService.instance.silentFtthLogin();
      if (result.success) {
        print('✅ [Login] تم تسجيل دخول FTTH بصمت: ${result.ftthUsername}');
      } else if (result.noCredentials) {
        print(
            'ℹ️ [Login] لا توجد بيانات FTTH مربوطة - سيتم عرض صفحة تسجيل الدخول عند الحاجة');
      } else {
        print('⚠️ [Login] فشل تسجيل دخول FTTH الصامت: ${result.message}');
      }
    } catch (e) {
      print('⚠️ [Login] خطأ في تسجيل دخول FTTH الصامت');
    }
  }

  /// فحص التحديثات في الخلفية بعد تسجيل الدخول (بدون حظر)
  /// يعمل فقط على Windows — على Android التحديث يدوي
  void _checkForUpdatesAfterLogin() {
    if (!Platform.isWindows) return;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        UpdateManager.checkAndShowUpdateDialog(context);
      }
    });
  }

  /// تحويل الدور من الإنجليزية (VPS API) إلى العربية
  String _mapRoleToArabic(String role) {
    switch (role.toLowerCase()) {
      case 'company_admin':
      case 'admin':
      case 'manager':
      case 'super_admin':
        return 'مدير';
      case 'technical_leader':
      case 'technicalleader':
        return 'ليدر';
      case 'technician':
        return 'فني';
      default:
        return role; // الموظفين وغيرهم يبقون كما هم
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ============================================
  // Build Methods
  // ============================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // تحديد نوع الشاشة
          final isDesktop = constraints.maxWidth >= 1024;
          final isTablet =
              constraints.maxWidth >= 600 && constraints.maxWidth < 1024;
          final isMobile = constraints.maxWidth < 600;

          return Stack(
            children: [
              // خلفية متحركة
              _buildAnimatedBackground(),

              // المحتوى الرئيسي
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 24,
                      vertical: isMobile ? 16 : 32,
                    ),
                    child: AnimatedBuilder(
                      animation: _formAnimController,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, _formSlideAnimation.value),
                          child: Opacity(
                            opacity: _formFadeAnimation.value,
                            child: isDesktop
                                ? _buildDesktopLayout(constraints)
                                : isTablet
                                    ? _buildTabletLayout(constraints)
                                    : _buildMobileLayout(constraints),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              // شاشة تحميل جميلة أثناء تسجيل الدخول أو الانتقال
              if (_isLoading || _isNavigating) _buildLoginLoadingOverlay(),
            ],
          );
        },
      ),
    );
  }

  /// شاشة تحميل جميلة تظهر أثناء تسجيل الدخول وعند الانتقال
  Widget _buildLoginLoadingOverlay() {
    final isAfterLogin = _isNavigating;
    final title =
        isAfterLogin ? 'جاري تحضير لوحة التحكم...' : 'جاري تسجيل الدخول...';
    final subtitle =
        isAfterLogin ? 'يرجى الانتظار لحظات' : 'جاري التحقق من بياناتك';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: child,
        );
      },
      child: Container(
        color: const Color(0xFF1a1535).withOpacity(0.97),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // أيقونة Lottie جميلة
              Container(
                width: MediaQuery.of(context).size.width < 400 ? 140 : 200,
                height: MediaQuery.of(context).size.width < 400 ? 140 : 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _primaryGradient[0].withOpacity(0.3),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              // نص التحميل الرئيسي
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  title,
                  key: ValueKey(title),
                  style: GoogleFonts.cairo(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // نص فرعي
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  subtitle,
                  key: ValueKey(subtitle),
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    color: Colors.white54,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              // شريط تحميل متدرج
              SizedBox(
                width: MediaQuery.of(context).size.width < 400 ? 200 : 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _primaryGradient[0],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // نقاط متحركة
              SizedBox(
                width: 60,
                child: _AnimatedDots(
                  color: _primaryGradient[0].withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// خلفية ثابتة فخمة (بدون تحريك لأداء أفضل)
  Widget _buildAnimatedBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0f0c29),
            Color(0xFF302b63),
            Color(0xFF24243e),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Floating orbs (ثابتة)
          ..._buildFloatingOrbs(),
          // Overlay خفيف بدلاً من BackdropFilter (أداء أفضل على Windows)
          Container(color: const Color(0xFF1a1535).withOpacity(0.6)),
        ],
      ),
    );
  }

  List<Widget> _buildFloatingOrbs() {
    return [
      Positioned(
        top: -100,
        left: -100,
        child: _buildOrb(300, _primaryGradient, 0.3),
      ),
      Positioned(
        bottom: -150,
        right: -150,
        child: _buildOrb(400, _secondaryGradient, 0.2),
      ),
      Positioned(
        top: MediaQuery.of(context).size.height * 0.3,
        right: -50,
        child: _buildOrb(200, _primaryGradient.reversed.toList(), 0.15),
      ),
    ];
  }

  Widget _buildOrb(double size, List<Color> colors, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: colors.map((c) => c.withOpacity(opacity)).toList(),
        ),
      ),
    );
  }

  /// تخطيط سطح المكتب (شاشة مقسومة)
  Widget _buildDesktopLayout(BoxConstraints constraints) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: 1200,
        maxHeight: constraints.maxHeight * 0.9,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a1535).withOpacity(0.85),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // القسم الأيسر - الترحيب
              Expanded(
                flex: 5,
                child: _buildWelcomeSection(isDesktop: true),
              ),
              // القسم الأيمن - النموذج
              Expanded(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(32),
                    ),
                  ),
                  child: _buildLoginForm(isCompact: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// تخطيط التابلت
  Widget _buildTabletLayout(BoxConstraints constraints) {
    return Container(
      constraints: BoxConstraints(maxWidth: constraints.maxWidth < 500 ? constraints.maxWidth - 16 : 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCompactHeader(),
          const SizedBox(height: 24),
          _buildGlassCard(
            child: _buildLoginForm(isCompact: true),
          ),
        ],
      ),
    );
  }

  /// تخطيط الهاتف
  Widget _buildMobileLayout(BoxConstraints constraints) {
    final isSmall = constraints.maxWidth < 420;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactHeader(),
        SizedBox(height: isSmall ? 8 : 16),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isSmall ? 4 : 12),
          child: _buildGlassCard(
            child: _buildLoginForm(isCompact: true),
          ),
        ),
      ],
    );
  }

  /// قسم الترحيب للسطح المكتب
  Widget _buildWelcomeSection({required bool isDesktop}) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 48 : 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الشعار المتحرك
          _buildAnimatedLogo(size: 80),
          const SizedBox(height: 32),

          // العنوان الرئيسي
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Colors.white, Color(0xFF667eea)],
            ).createShader(bounds),
            child: Text(
              'مرحباً بك في',
              style: GoogleFonts.cairo(
                fontSize: 24,
                fontWeight: FontWeight.w300,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            'منصة صدارة',
            style: GoogleFonts.cairo(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),

          // الوصف
          Text(
            'نظام إدارة متكامل للشركات والمؤسسات\nمع أعلى معايير الأمان والموثوقية',
            style: GoogleFonts.cairo(
              fontSize: 16,
              color: Colors.white70,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 32),

          // الميزات
          _buildFeaturesList(),
        ],
      ),
    );
  }

  Widget _buildFeaturesList() {
    final features = [
      {'icon': Icons.security, 'text': 'حماية متقدمة'},
      {'icon': Icons.speed, 'text': 'أداء فائق السرعة'},
      {'icon': Icons.cloud_sync, 'text': 'مزامنة سحابية'},
    ];

    return Row(
      children: features.map((f) {
        return Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(f['icon'] as IconData,
                    color: Colors.white70, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                f['text'] as String,
                style: GoogleFonts.cairo(
                  color: Colors.white70,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// رأس مضغوط للتابلت والهاتف
  Widget _buildCompactHeader() {
    final w = MediaQuery.of(context).size.width;
    final isSmall = w < 420;
    return Column(
      children: [
        _buildAnimatedLogo(size: isSmall ? 40 : 60),
        SizedBox(height: isSmall ? 6 : 16),
        Text(
          'منصة صدارة',
          style: GoogleFonts.cairo(
            fontSize: isSmall ? 18 : 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'تسجيل الدخول',
          style: GoogleFonts.cairo(
            fontSize: 16,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  /// شعار ثابت
  Widget _buildAnimatedLogo({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _primaryGradient,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: _primaryGradient[0].withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(
        Icons.fiber_smart_record,
        size: size * 0.5,
        color: Colors.white,
      ),
    );
  }

  /// بطاقة زجاجية
  Widget _buildGlassCard({required Widget child}) {
    final r = MediaQuery.of(context).size.width < 500 ? 16.0 : 24.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  /// نموذج تسجيل الدخول
  Widget _buildLoginForm({required bool isCompact}) {
    final isMobile = MediaQuery.of(context).size.width < 500;
    final pad = isMobile ? 14.0 : (isCompact ? 24.0 : 40.0);
    final gap = isMobile ? 10.0 : 16.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(pad),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCompact) ...[
              Text(
                'تسجيل الدخول',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 20 : 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1a1a2e),
                ),
              ),
              SizedBox(height: isMobile ? 4 : 8),
              Text(
                'أدخل بياناتك للوصول إلى حسابك',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 12 : 14,
                  color: Colors.grey[600],
                ),
              ),
              SizedBox(height: isMobile ? 2 : 6),
              Text(
                'v$_appVersion',
                style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[400]),
              ),
              SizedBox(height: isMobile ? 12 : 24),
            ],

            _buildApiStatusBadge(),
            SizedBox(height: isMobile ? 10 : 20),

            if (_errorMessage != null) ...[
              _buildErrorMessage(),
              SizedBox(height: gap),
            ],

            _buildCompanySelector(),
            SizedBox(height: gap),
            _buildUsernameField(),
            SizedBox(height: gap),
            _buildPasswordField(),
            SizedBox(height: gap),
            _buildRememberMeCheckbox(),
            SizedBox(height: gap),
            if (_savedCredentials.isNotEmpty) _buildSavedCredentialsDropdown(),
            SizedBox(height: isMobile ? 14 : 24),
            _buildLoginButton(),
            SizedBox(height: gap),
            _buildOfflineRouterSetupButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineRouterSetupButton() {
    final isSmall = MediaQuery.of(context).size.width < 420;
    return SizedBox(
      height: isSmall ? 38 : 44,
      child: OutlinedButton.icon(
        icon: Icon(Icons.settings_input_antenna, size: isSmall ? 16 : 18, color: _primaryGradient[0]),
        label: Text(
          'إعداد الراوتر (أوفلاين)',
          style: GoogleFonts.cairo(
            fontSize: isSmall ? 12 : 14,
            fontWeight: FontWeight.w700,
            color: _primaryGradient[0],
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: _primaryGradient[0].withOpacity(0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isSmall ? 10 : 14)),
        ),
        onPressed: () {
          Navigator.push(context,
            MaterialPageRoute(builder: (_) => const OfflineRouterSetupPage()));
        },
      ),
    );
  }

  Widget _buildApiStatusBadge() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF11998e).withOpacity(0.1),
              const Color(0xFF38ef7d).withOpacity(0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF11998e).withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF11998e),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'متصل بـ VPS API',
              style: GoogleFonts.cairo(
                fontSize: 12,
                color: const Color(0xFF11998e),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// قائمة منسدلة للحسابات المحفوظة
  Widget _buildSavedCredentialsDropdown() {
    return DropdownButtonFormField<SavedCredential>(
      value: _selectedCredential,
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down, color: _primaryGradient[0]),
      decoration: _buildInputDecoration(
        label: 'حسابات محفوظة',
        hint: 'اختر حساب محفوظ للدخول السريع',
        icon: Icons.bookmark_rounded,
      ),
      items: _savedCredentials.map((credential) {
        return DropdownMenuItem<SavedCredential>(
          value: credential,
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: _primaryGradient[0].withOpacity(0.2),
                child: Text(
                  credential.username[0].toUpperCase(),
                  style: TextStyle(
                    color: _primaryGradient[0],
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      credential.username,
                      style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      credential.companyName,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 16, color: Colors.grey[400]),
                onPressed: () => _deleteCredential(credential),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'حذف',
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (credential) {
        if (credential != null) {
          _selectCredential(credential);
        }
      },
      selectedItemBuilder: (context) {
        return _savedCredentials.map((credential) {
          return Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: _primaryGradient[0],
                child: Text(
                  credential.username[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${credential.username} - ${credential.companyName}',
                  style: GoogleFonts.cairo(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }).toList();
      },
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.cairo(color: Colors.red[700], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompanySelector() {
    if (_loadingCompanies) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_primaryGradient[0]),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'جاري تحميل الشركات...',
              style: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<CompanyListItem>(
      value: _selectedCompany,
      isExpanded: true,
      icon: Icon(Icons.keyboard_arrow_down, color: _primaryGradient[0]),
      decoration: _buildInputDecoration(
        label: 'الشركة',
        hint: 'اختر الشركة',
        icon: Icons.business_rounded,
      ),
      items: _buildCompanyDropdownItems(),
      onChanged: (value) {
        setState(() {
          _selectedCompany = value;
          _selectedCredential = null;
        });
      },
      validator: (value) => value == null ? 'يرجى اختيار الشركة' : null,
    );
  }

  List<DropdownMenuItem<CompanyListItem>> _buildCompanyDropdownItems() {
    final items = <DropdownMenuItem<CompanyListItem>>[];

    // مدير النظام
    items.add(
      DropdownMenuItem(
        value: CompanyListItem(id: '1', name: 'مدير النظام', code: '1'),
        child: Row(
          children: [
            Icon(Icons.admin_panel_settings,
                color: Colors.amber[700], size: 20),
            const SizedBox(width: 10),
            Text(
              'مدير النظام',
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold,
                color: Colors.amber[700],
              ),
            ),
          ],
        ),
      ),
    );

    // فاصل
    items.add(const DropdownMenuItem(enabled: false, child: Divider()));

    // الشركات
    for (final company in _companies) {
      if (company.code == '1') continue;
      items.add(
        DropdownMenuItem(
          value: company,
          child: Row(
            children: [
              Icon(Icons.business_rounded,
                  color: _primaryGradient[0], size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  company.name,
                  style: GoogleFonts.cairo(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                company.code,
                style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    return items;
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      textDirection: TextDirection.ltr,
      style: GoogleFonts.cairo(),
      decoration: _buildInputDecoration(
        label: 'اسم المستخدم',
        hint: 'أدخل اسم المستخدم أو رقم الهاتف',
        icon: Icons.person_rounded,
      ),
      validator: (value) => value == null || value.trim().isEmpty
          ? 'يرجى إدخال اسم المستخدم'
          : null,
      onChanged: (_) => setState(() => _selectedCredential = null),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textDirection: TextDirection.ltr,
      style: GoogleFonts.cairo(),
      decoration: _buildInputDecoration(
        label: 'كلمة المرور',
        hint: 'أدخل كلمة المرور',
        icon: Icons.lock_rounded,
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey[500],
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (value) =>
          value == null || value.isEmpty ? 'يرجى إدخال كلمة المرور' : null,
      onFieldSubmitted: (_) => _login(),
    );
  }

  Widget _buildRememberMeCheckbox() {
    return Row(
      children: [
        Transform.scale(
          scale: 1.1,
          child: Checkbox(
            value: _rememberMe,
            onChanged: (value) => setState(() => _rememberMe = value ?? false),
            activeColor: _primaryGradient[0],
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _rememberMe = !_rememberMe),
          child: Text(
            'تذكرني',
            style: GoogleFonts.cairo(color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    final isSmall = MediaQuery.of(context).size.width < 420;
    return Container(
      height: isSmall ? 44 : 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _primaryGradient),
        borderRadius: BorderRadius.circular(isSmall ? 10 : 14),
        boxShadow: [
          BoxShadow(
            color: _primaryGradient[0].withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.login_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    'تسجيل الدخول',
                    style: GoogleFonts.cairo(
                      fontSize: MediaQuery.of(context).size.width < 420 ? 14 : 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final isSmall = MediaQuery.of(context).size.width < 420;
    final radius = isSmall ? 8.0 : 12.0;
    final vPad = isSmall ? 10.0 : 16.0;
    final hPad = isSmall ? 10.0 : 16.0;

    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: isSmall,
      labelStyle: GoogleFonts.cairo(color: Colors.grey[600], fontSize: isSmall ? 12 : 14),
      hintStyle: GoogleFonts.cairo(color: Colors.grey[400], fontSize: isSmall ? 11 : 13),
      prefixIcon: Icon(icon, color: _primaryGradient[0], size: isSmall ? 18 : 24),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: _primaryGradient[0], width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
    );
  }
}

/// نقاط متحركة تعطي إحساس بالتحميل
class _AnimatedDots extends StatefulWidget {
  final Color color;
  const _AnimatedDots({required this.color});

  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final delay = index * 0.33;
            final t = ((_controller.value + delay) % 1.0);
            final sinVal = math.sin(t * math.pi);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: 0.5 + 0.5 * sinVal,
                child: Opacity(
                  opacity: (0.3 + 0.7 * sinVal).clamp(0.0, 1.0),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
