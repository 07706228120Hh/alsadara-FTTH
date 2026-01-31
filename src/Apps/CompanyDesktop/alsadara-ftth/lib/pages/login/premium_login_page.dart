/// صفحة تسجيل دخول فخمة ومتجاوبة
/// تدعم جميع أحجام الشاشات (حاسوب، تابلت، هاتف)
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/vps_auth_service.dart';
import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';
import '../home_page.dart';
import '../super_admin/super_admin_dashboard.dart';

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

  // Animations
  late AnimationController _backgroundAnimController;
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
    _loadCompanies();
    _loadSavedCredentials();
  }

  void _initAnimations() {
    _backgroundAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

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
    _backgroundAnimController.dispose();
    _formAnimController.dispose();
    super.dispose();
  }

  // ============================================
  // Data Loading
  // ============================================

  Future<void> _loadCompanies() async {
    try {
      final response = await ApiClient.instance.get(
        '/companies/list',
        (json) => json,
      );

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
      } else {
        setState(() {
          _loadingCompanies = false;
          _companiesLoadError = response.message ?? 'فشل في جلب قائمة الشركات';
        });
      }
    } catch (e) {
      setState(() {
        _loadingCompanies = false;
        _companiesLoadError = 'خطأ في الاتصال بالخادم';
      });
    }
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
      debugPrint('خطأ في تحميل بيانات الدخول المحفوظة: $e');
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
      debugPrint('خطأ في حفظ بيانات الدخول: $e');
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
      debugPrint('خطأ في حذف بيانات الدخول: $e');
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
        await _saveCredential();
        HapticFeedback.heavyImpact();
        _navigateAfterLogin();
      } else {
        HapticFeedback.vibrate();
        setState(
            () => _errorMessage = result.errorMessage ?? 'حدث خطأ غير متوقع');
      }
    } catch (e) {
      HapticFeedback.vibrate();
      setState(() => _errorMessage = 'حدث خطأ في الاتصال');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateAfterLogin() {
    if (_authService.isSuperAdmin) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SuperAdminDashboard(),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } else if (_authService.currentUser != null &&
        _authService.currentCompany != null) {
      final user = _authService.currentUser!;
      final company = _authService.currentCompany!;

      final Map<String, bool> pageAccess = {};
      for (final permission in user.permissions) {
        pageAccess[permission] = true;
      }
      user.firstSystemPermissions.forEach((key, value) {
        if (value) pageAccess[key] = true;
      });
      user.secondSystemPermissions.forEach((key, value) {
        if (value) pageAccess[key] = true;
      });

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => HomePage(
            username: user.fullName.isNotEmpty ? user.fullName : user.username,
            permissions: user.isAdmin ? 'مدير' : user.role,
            department: company.name,
            center: company.code,
            salary: '0',
            pageAccess: pageAccess,
            tenantId: company.id,
            tenantCode: company.code,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
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
            ],
          );
        },
      ),
    );
  }

  /// خلفية متحركة فخمة
  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _backgroundAnimController,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(
                math.cos(_backgroundAnimController.value * 2 * math.pi),
                math.sin(_backgroundAnimController.value * 2 * math.pi),
              ),
              end: Alignment(
                -math.cos(_backgroundAnimController.value * 2 * math.pi),
                -math.sin(_backgroundAnimController.value * 2 * math.pi),
              ),
              colors: const [
                Color(0xFF0f0c29),
                Color(0xFF302b63),
                Color(0xFF24243e),
              ],
            ),
          ),
          child: Stack(
            children: [
              // Floating orbs
              ..._buildFloatingOrbs(),
              // Blur overlay
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                child: Container(color: Colors.transparent),
              ),
            ],
          ),
        );
      },
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
    return AnimatedBuilder(
      animation: _backgroundAnimController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(
            math.sin(_backgroundAnimController.value * 2 * math.pi) * 20,
            math.cos(_backgroundAnimController.value * 2 * math.pi) * 20,
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: colors.map((c) => c.withOpacity(opacity)).toList(),
              ),
            ),
          ),
        );
      },
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
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
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
      ),
    );
  }

  /// تخطيط التابلت
  Widget _buildTabletLayout(BoxConstraints constraints) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 500),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCompactHeader(),
        const SizedBox(height: 16),
        _buildGlassCard(
          child: _buildLoginForm(isCompact: true),
        ),
      ],
    );
  }

  /// قسم الترحيب للسطح المكتب
  Widget _buildWelcomeSection({required bool isDesktop}) {
    return Container(
      padding: const EdgeInsets.all(48),
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
    return Column(
      children: [
        _buildAnimatedLogo(size: 60),
        const SizedBox(height: 16),
        Text(
          'منصة صدارة',
          style: GoogleFonts.cairo(
            fontSize: 32,
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

  /// شعار متحرك
  Widget _buildAnimatedLogo({required double size}) {
    return AnimatedBuilder(
      animation: _backgroundAnimController,
      builder: (context, child) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
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
      },
    );
  }

  /// بطاقة زجاجية
  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: BorderRadius.circular(24),
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
      ),
    );
  }

  /// نموذج تسجيل الدخول
  Widget _buildLoginForm({required bool isCompact}) {
    return Padding(
      padding: EdgeInsets.all(isCompact ? 24 : 40),
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
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1a1a2e),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'أدخل بياناتك للوصول إلى حسابك',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
            ],

            // شارة VPS API
            _buildApiStatusBadge(),
            const SizedBox(height: 20),

            // رسالة الخطأ
            if (_errorMessage != null) ...[
              _buildErrorMessage(),
              const SizedBox(height: 16),
            ],

            // قائمة الشركات
            _buildCompanySelector(),
            const SizedBox(height: 16),

            // اسم المستخدم
            _buildUsernameField(),
            const SizedBox(height: 16),

            // كلمة المرور
            _buildPasswordField(),
            const SizedBox(height: 16),

            // تذكرني
            _buildRememberMeCheckbox(),
            const SizedBox(height: 16),

            // الحسابات المحفوظة (قائمة منسدلة)
            if (_savedCredentials.isNotEmpty) _buildSavedCredentialsDropdown(),
            const SizedBox(height: 24),

            // زر الدخول
            _buildLoginButton(),
          ],
        ),
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
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _primaryGradient),
        borderRadius: BorderRadius.circular(14),
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
                      fontSize: 18,
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
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
      hintStyle: GoogleFonts.cairo(color: Colors.grey[400], fontSize: 13),
      prefixIcon: Icon(icon, color: _primaryGradient[0]),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _primaryGradient[0], width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
