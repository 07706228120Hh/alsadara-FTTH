/// صفحة تسجيل دخول فخمة ومتجاوبة
/// تدعم جميع أحجام الشاشات (حاسوب، تابلت، هاتف)
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../frontend/frontend.dart';
import '../../services/vps_auth_service.dart';
import '../../services/api/api_client.dart';
import '../../permissions/permissions.dart';
import '../../widgets/update_dialog.dart';
import '../../services/auto_update_service.dart';
import '../../services/dual_auth_service.dart';
import '../../services/fcm_token_service.dart';
import '../../services/notification_service.dart';
import '../../ftth/widgets/floating_toolbar.dart';
import '../home_page.dart';
import '../super_admin/super_admin_dashboard.dart';
import '../../network_quality/network_quality_home_page.dart';

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

  // فحص التحديثات اليدوي (زر في شاشة الدخول)
  bool _checkingUpdate = false;

  // Animations
  late AnimationController _formAnimController;
  late Animation<double> _formSlideAnimation;
  late Animation<double> _formFadeAnimation;

  @override
  void initState() {
    super.initState();
    // إزالة الشريط العائم وكبته طوال وجود شاشة الدخول (يمنع ظهوره أثناء انتقالات الدخول/الخروج)
    FloatingToolbar.dispose();
    FloatingToolbar.setSuppressed(true);
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
    // رفع الكبت بعد مغادرة شاشة الدخول (ظهور الأيقونة في التطبيق طبيعي)
    FloatingToolbar.setSuppressed(false);
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
        _showSnackBar('تم حذف بيانات الدخول', SdColors.warning);
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
    // كل هذه العمليات تعمل في الخلفية بدون انتظار — الانتقال فوري
    DualAuthService.instance.clearFtthData();
    _performSilentFtthLogin();
    FcmTokenService.instance.registerToken();
    FcmTokenService.instance.listenForTokenRefresh();
    NotificationService.requestBatteryOptimizationExemption();

    if (_authService.isSuperAdmin) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SuperAdminDashboard(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, __, ___, child) => child,
        ),
      );
      _checkForUpdatesAfterLogin();
    } else if (_authService.currentUser != null &&
        _authService.currentCompany != null) {
      final user = _authService.currentUser!;
      final company = _authService.currentCompany!;

      // تحميل الصلاحيات في الخلفية — لا ينتظر
      final pm = PermissionManager.instance;
      if (!pm.isLoaded) {
        pm.loadPermissions();
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
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (_, __, ___, child) => child,
        ),
      );
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
  ///
  /// يستخدم المسار الذكي الجديد (الحسابات المرتبطة المتعددة) مع تدرّج آمن:
  /// عند غياب الصلاحية/الحسابات أو أي خطأ يرجع تلقائياً للمسار القديم.
  /// عند تعدّد حسابات FTTH يُعرض حوار الاختيار فوق الصفحة الرئيسية.
  Future<void> _performSilentFtthLogin() async {
    try {
      // لا حوار اختيار عند الدخول — ندخل تلقائياً بالحساب الأساسي؛
      // التبديل يتم لاحقاً من مُبدّل الحساب في الشريط العلوي داخل التطبيق.
      final result = await DualAuthService.instance.smartFtthLogin();
      if (result.success) {
        print('✅ [Login] تم تسجيل دخول FTTH بصمت: ${result.ftthUsername}');
      } else if (result.cancelled) {
        print('ℹ️ [Login] أُلغي اختيار حساب FTTH');
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

  /// فحص يدوي للتحديثات من زر شاشة الدخول (قبل تسجيل الدخول).
  /// يعرض نتيجة واضحة في كل حالة: تحديث متوفّر / أنت على الأحدث / تعذّر الفحص.
  Future<void> _manualCheckForUpdate() async {
    if (_checkingUpdate) return;
    if (!Platform.isWindows && !Platform.isAndroid) {
      _showSnackBar('التحديث مدعوم على Windows و Android فقط', SdColors.danger);
      return;
    }
    setState(() => _checkingUpdate = true);
    try {
      final info = await AutoUpdateService.instance.checkForUpdateManual();
      if (!mounted) return;
      if (info != null && info.downloadUrl.isNotEmpty) {
        // تحديث متوفّر — افتح حوار التحميل/التثبيت المعتاد.
        final current = await AutoUpdateService.instance.getCurrentVersion();
        if (!mounted) return;
        await UpdateDialog.show(context, info, current);
      } else if (info != null && info.downloadUrl.isEmpty) {
        // إصدار أحدث موجود لكن بلا ملف تثبيت مناسب لهذه المنصة.
        _showSnackBar(
            'يتوفّر إصدار أحدث (v${info.version}) لكن لا يوجد ملف تثبيت متاح لهذه المنصة',
            SdColors.danger);
      } else {
        final current = await AutoUpdateService.instance.getCurrentVersion();
        if (!mounted) return;
        _showSnackBar('أنت على أحدث إصدار (v$current)', SdColors.success);
      }
    } on UpdateCheckException catch (e) {
      // رسالة دقيقة حسب السبب (حدّ معدّل / حجب / لا إنترنت) بدل جملة عامة مضلِّلة.
      if (mounted) _showSnackBar(e.userMessage, SdColors.danger);
    } catch (_) {
      if (mounted) {
        _showSnackBar('تعذّر التحقق من التحديثات — حاول لاحقاً', SdColors.danger);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
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
        content: Text(message, style: SdText.body.copyWith(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ============================================
  // View helpers (عرض فقط — لا منطق مصادقة)
  // ============================================

  /// وضع «مدير النظام» مشتقّ من اختيار الشركة الحالية (code == '1').
  bool get _isAdminMode => _selectedCompany?.code == '1';

  /// التبديل إلى «موظف شركة»: إلغاء اختيار مدير النظام إن كان مفعّلاً.
  void _selectEmployeeMode() {
    if (_selectedCompany?.code == '1') {
      setState(() {
        _selectedCompany = null;
        _selectedCredential = null;
      });
    }
  }

  /// التبديل إلى «مدير النظام»: ضبط الشركة على العنصر id=1 (نفس المنطق السابق).
  void _selectAdminMode() {
    setState(() {
      _selectedCompany = CompanyListItem(id: '1', name: 'مدير النظام', code: '1');
      _selectedCredential = null;
    });
  }

  // ============================================
  // Build Methods
  // ============================================

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.primaryEdge,
        body: Stack(
          children: [
            _buildBackground(),
            SafeArea(
              child: AnimatedBuilder(
                animation: _formAnimController,
                builder: (context, child) => Opacity(
                  opacity: _formFadeAnimation.value,
                  child: Transform.translate(
                    offset: Offset(0, _formSlideAnimation.value),
                    child: child,
                  ),
                ),
                child: SdAdaptive(
                  phone: _buildPhoneLayout,
                  tablet: _buildTabletLayout,
                  desktop: _buildDesktopLayout,
                ),
              ),
            ),
            if (_isLoading || _isNavigating) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  /// خلفية ثلاثية الأبعاد حقيقية تملأ الشاشة (مدينة الصدارة الليلية — Three.js).
  /// على سطح المكتب يُزاح مركز المشهد لليسار ليترك مكان بطاقة الدخول.
  Widget _buildBackground() {
    final w = MediaQuery.sizeOf(context).width;
    final desktop = w >= 1024;
    return SdLogin3DBackground(
      shiftX: desktop ? -235 : 0,
      lowQuality: w < 600,
    );
  }

  // ── التخطيطات ──

  /// الهاتف: رأس بالشعار + مشهد مصغّر + بطاقة تتداخل فوقه.
  Widget _buildPhoneLayout(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: _buildBrandHeader(logoSize: 42, titleSize: 20),
          ),
          // نافذة شفافة تُظهر المدينة ثلاثية الأبعاد خلف المحتوى.
          SizedBox(height: math.min(300, MediaQuery.of(context).size.height * 0.34)),
          Transform.translate(
            offset: const Offset(0, -26),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _buildAuthCard(context),
            ),
          ),
        ],
      ),
    );
  }

  /// الآيباد العمودي: عمود واحد موسّط، المشهد فوق البطاقة.
  Widget _buildTabletLayout(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBrandHeader(logoSize: 48, titleSize: 24),
              const SizedBox(height: 8),
              const SizedBox(height: 320), // نافذة على المدينة ثلاثية الأبعاد
              const SizedBox(height: 8),
              _buildAuthCard(context),
            ],
          ),
        ),
      ),
    );
  }

  /// سطح المكتب/الآيباد الأفقي: يمين البطاقة المرفوعة، يسار المشهد والميزات.
  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // يمين (في RTL = أول عنصر): بطاقة الدخول.
        SizedBox(
          width: 470,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(60, 40, 40, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: _buildAuthCard(context, tilt: true),
              ),
            ),
          ),
        ),
        // يسار: المشهد + العنوان + الميزات.
        Expanded(child: _buildBrandPane(context)),
      ],
    );
  }

  /// لوحة التعريف (المشهد + العنوان + الميزات) لسطح المكتب.
  Widget _buildBrandPane(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 44, 70, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBrandHeader(logoSize: 54, titleSize: 30),
          // المساحة الوسطى فارغة: المدينة ثلاثية الأبعاد في الخلفية تستقبل الماوس هنا.
          const Expanded(child: SizedBox.shrink()),
          // طبقة تعتيم متدرّجة خلف العنوان والميزات لإبراز النصّ فوق المدينة المزدحمة.
          Container(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x000A1838),
                  Color(0xA60A1838),
                  Color(0xD60A1838),
                ],
                stops: [0.0, 0.42, 1.0],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildBrandTitle(),
                const SizedBox(height: 18),
                _buildFeatureRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// رأس العلامة: مكعّب الشعار «ص» + اسم المنصّة + العنوان الفرعي الذهبي.
  Widget _buildBrandHeader({required double logoSize, required double titleSize}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogoCube(logoSize),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'منصة الصدارة',
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: titleSize,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.15,
              ),
            ),
            Text(
              'لإدارة شبكات الألياف والعمليات',
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: titleSize * 0.42 + 1,
                fontWeight: FontWeight.w700,
                color: SdColors.gold,
                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// مكعّب الشعار الأبيض «ص».
  Widget _buildLogoCube(double size) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.002)
        ..rotateX(0.18)
        ..rotateY(0.22),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Colors.white, SdColors.infoTint],
          ),
          boxShadow: const [
            BoxShadow(color: SdColors.platformLight, offset: Offset(-2, 2)),
            BoxShadow(color: Color(0xFF7986CB), offset: Offset(-4, 4)),
            BoxShadow(
                color: Color(0x73000000), offset: Offset(-8, 12), blurRadius: 18),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }

  /// عنوان اللوحة اليسرى مع السطر الثاني بتدرّج تركوازي ← ذهبي.
  Widget _buildBrandTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: const TextSpan(
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.3,
              shadows: [
                Shadow(color: Color(0xCC000000), offset: Offset(0, 2), blurRadius: 12),
              ],
            ),
            children: [
              TextSpan(text: 'إدارة متكاملة لشبكتك'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'نظام موحّد للشركات والوكلاء والفنيين بأعلى معايير الأمان والموثوقية.',
          style: TextStyle(
            fontFamily: SdText.family,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.86),
            height: 1.6,
            shadows: const [
              Shadow(color: Color(0x80000000), offset: Offset(0, 1), blurRadius: 6),
            ],
          ),
        ),
      ],
    );
  }

  /// ثلاث ميزات بمكعبات أيقونات.
  Widget _buildFeatureRow() {
    const items = [
      (Icons.shield_rounded, SdGroup.admin, 'حماية متقدمة', 'تشفير وصلاحيات دقيقة'),
      (Icons.bolt_rounded, SdGroup.field, 'أداء فائق', 'استجابة لحظية'),
      (Icons.cloud_rounded, SdGroup.platform, 'مزامنة سحابية', 'بياناتك على كل أجهزتك'),
    ];
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _buildFeatureCard(items[i].$1, items[i].$2, items[i].$3, items[i].$4)),
        ],
      ],
    );
  }

  Widget _buildFeatureCard(IconData icon, SdGroup group, String title, String sub) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0x591B2F5E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          SdIconCube(icon: icon, group: group, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.66),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── البطاقة ──

  /// بطاقة الدخول البيضاء المرفوعة (مع ميلان خفيف على سطح المكتب).
  /// بطاقة زجاجية داكنة شفافة (تُظهر المدينة ثلاثية الأبعاد خلفها) بحجم مدمج.
  Widget _buildAuthCard(BuildContext context, {bool tilt = false}) {
    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x8C1A2C66), Color(0xB30B1B3F)],
        ),
        borderRadius: BorderRadius.circular(26),
        // إطار ذهبي بارز يُبرز البطاقة على الخلفية الكحلية.
        border: Border.all(color: SdColors.gold.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: _buildLoginForm(context),
          ),
          // خط ذهبي علوي.
          Positioned(
            top: 0,
            right: 36,
            left: 36,
            child: Container(
              height: 4,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
                gradient: LinearGradient(
                  colors: [SdColors.accentLight, SdColors.primary, SdColors.gold],
                ),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
    // ظل خارجي ناعم تحت الزجاج.
    card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), offset: Offset(0, 24), blurRadius: 48, spreadRadius: -16),
        ],
      ),
      child: card,
    );

    if (tilt) {
      card = Transform(
        alignment: Alignment.centerRight,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0011)
          ..rotateY(0.05),
        child: card,
      );
    }
    return card;
  }

  /// محتوى البطاقة بالترتيب المعتمد.
  Widget _buildLoginForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildCardHeader(),
          const SizedBox(height: 10),
          if (_errorMessage != null) ...[
            _buildErrorMessage(),
            const SizedBox(height: 8),
          ],
          _buildModeSegmented(),
          const SizedBox(height: 8),
          if (_isAdminMode) _buildAdminNote() else _buildCompanySelector(),
          const SizedBox(height: 8),
          _buildUsernameField(),
          const SizedBox(height: 8),
          _buildPasswordField(),
          const SizedBox(height: 4),
          _buildRememberRow(),
          if (_savedCredentials.isNotEmpty) ...[
            const SizedBox(height: 6),
            _buildSavedCredentialsDropdown(),
          ],
          const SizedBox(height: 10),
          _buildLoginButton(),
          const SizedBox(height: 8),
          _buildOfflineRouterSetupButton(),
          const SizedBox(height: 8),
          Center(child: _buildVersionText()),
        ],
      ),
    );
  }

  /// رأس البطاقة: مكعّب قفل + «مرحباً بعودتك» + شارة اتصال حيّة.
  Widget _buildCardHeader() {
    return Row(
      children: [
        SdIconCube(icon: Icons.lock_rounded, group: SdGroup.admin, size: 42),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'مرحباً بعودتك',
                style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              Text(
                'سجّل الدخول لمتابعة عملك',
                style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xB3FFFFFF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildUpdateIconButton(),
        const SizedBox(width: 8),
        _LiveStatusBadge(
          loading: _loadingCompanies,
          offline: _companiesLoadError != null,
        ),
      ],
    );
  }

  /// المفتاح المقسّم: موظف شركة | مدير النظام.
  Widget _buildModeSegmented() {
    return SdSegmented(
      segments: const [
        SdSegment('موظف شركة', icon: Icons.apartment_rounded),
        SdSegment('مدير النظام', icon: Icons.verified_user_rounded),
      ],
      selected: _isAdminMode ? 1 : 0,
      height: 40,
      glass: true,
      onChanged: (i) => i == 1 ? _selectAdminMode() : _selectEmployeeMode(),
    );
  }

  /// لافتة توضيحية لوضع مدير النظام (بديل قائمة الشركات).
  Widget _buildAdminNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: SdColors.warningTint,
        borderRadius: BorderRadius.circular(14),
        border: SdOutline.all,
        boxShadow: const [BoxShadow(color: Color(0xFFFFE082), offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_rounded, size: 20, color: Color(0xFF7A4F01)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'دخول مدير النظام — يفتح لوحة الإدارة العليا',
              style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF7A4F01),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// تسمية حقل فوق الإطار.
  Widget _buildFieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 3),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: SdText.family,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Color(0xCCFFFFFF),
        ),
      ),
    );
  }

  /// إطار حقل مرفوع (خلفية فاتحة + حافّة سفلية).
  Widget _buildFieldFrame({required Widget child, double minHeight = 44}) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x38FFFFFF)),
      ),
      child: Center(child: child),
    );
  }

  /// منتقي الشركة (يظهر في وضع موظف شركة فقط).
  Widget _buildCompanySelector() {
    if (_loadingCompanies) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFieldLabel('الشركة'),
          _buildFieldFrame(
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SdColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text('جاري تحميل الشركات...', style: _glassHint),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('الشركة'),
        _buildFieldFrame(
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [SdColors.accentGlow, SdColors.accent],
                  ),
                  boxShadow: const [
                    BoxShadow(color: SdColors.accentEdge, offset: Offset(0, 3)),
                  ],
                ),
                child: const Icon(Icons.business_rounded, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<CompanyListItem>(
                    value: _selectedCompany,
                    isExpanded: true,
                    isDense: true,
                    hint: Text('اختر الشركة', style: _glassHint),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Color(0xCCFFFFFF)),
                    borderRadius: BorderRadius.circular(16),
                    selectedItemBuilder: (context) => _companies
                        .where((c) => c.code != '1')
                        .map((c) => Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(c.name,
                                  style: _glassText,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    items: _buildCompanyDropdownItems(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCompany = value;
                        _selectedCredential = null;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<DropdownMenuItem<CompanyListItem>> _buildCompanyDropdownItems() {
    final items = <DropdownMenuItem<CompanyListItem>>[];
    for (final company in _companies) {
      if (company.code == '1') continue; // «مدير النظام» عبر المفتاح المقسّم
      items.add(
        DropdownMenuItem(
          value: company,
          child: Row(
            children: [
              Expanded(
                child: Text(company.name,
                    style: SdText.label, overflow: TextOverflow.ellipsis),
              ),
              Text(company.code, style: SdText.caption),
            ],
          ),
        ),
      );
    }
    return items;
  }

  Widget _buildUsernameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('اسم المستخدم'),
        _buildFieldFrame(
          child: Row(
            children: [
              const Icon(Icons.person_rounded, color: SdColors.accentLight, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _usernameController,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: _glassText,
                  cursorColor: SdColors.accentLight,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    filled: false,
                    hintText: 'اسم المستخدم أو رقم الهاتف',
                    hintStyle: _glassHint,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'يرجى إدخال اسم المستخدم'
                      : null,
                  onChanged: (_) => setState(() => _selectedCredential = null),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('كلمة المرور'),
        _buildFieldFrame(
          child: Row(
            children: [
              const Icon(Icons.lock_rounded, color: SdColors.accentLight, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.right,
                  style: _glassText,
                  cursorColor: SdColors.accentLight,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    filled: false,
                    hintText: '••••••••',
                    hintStyle: _glassHint,
                    errorStyle: const TextStyle(height: 0, fontSize: 0),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'يرجى إدخال كلمة المرور'
                      : null,
                  onFieldSubmitted: (_) => _login(),
                ),
              ),
              SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: const Color(0xB3FFFFFF),
                    size: 19,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  tooltip: _obscurePassword ? 'إظهار كلمة المرور' : 'إخفاء كلمة المرور',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRememberRow() {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              SdToggle(
                value: _rememberMe,
                onChanged: (value) => setState(() => _rememberMe = value),
                label: 'تذكرني',
              ),
              const SizedBox(width: 10),
              Text('تذكرني', style: _glassText.copyWith(fontSize: 13)),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 13, color: Color(0x99FFFFFF)),
              const SizedBox(width: 4),
              Text('اتصال مشفّر', style: _glassHint.copyWith(fontSize: 11.5)),
            ],
          ),
        ],
      ),
    );
  }

  /// الحسابات المحفوظة — قائمة منسدلة (تجاوز معتمد: Dropdown لا شرائح).
  Widget _buildSavedCredentialsDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('حسابات محفوظة على هذا الجهاز'),
        _buildFieldFrame(
          child: Row(
            children: [
              const Icon(Icons.bookmark_rounded, color: SdColors.accentLight, size: 19),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<SavedCredential>(
                    value: _selectedCredential,
                    isExpanded: true,
                    isDense: true,
                    hint: Text('اختر حساباً للدخول السريع', style: _glassHint),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Color(0xCCFFFFFF)),
                    borderRadius: BorderRadius.circular(16),
                    selectedItemBuilder: (context) {
                      return _savedCredentials.map((credential) {
                        return Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            '${credential.username} · ${credential.companyName}',
                            style: _glassText,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList();
                    },
                    items: _savedCredentials.map((credential) {
                      return DropdownMenuItem<SavedCredential>(
                        value: credential,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: SdColors.primaryTint,
                              child: Text(
                                credential.username.isNotEmpty
                                    ? credential.username[0].toUpperCase()
                                    : '؟',
                                style: const TextStyle(
                                  color: SdColors.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                  fontFamily: SdText.family,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(credential.username,
                                      style: SdText.label,
                                      overflow: TextOverflow.ellipsis),
                                  Text(credential.companyName,
                                      style: SdText.caption,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 18, color: SdColors.faint),
                              onPressed: () => _deleteCredential(credential),
                              padding: EdgeInsets.zero,
                              constraints:
                                  const BoxConstraints(minWidth: 44, minHeight: 44),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (credential) {
                      if (credential != null) _selectCredential(credential);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    final t = SdStatus.danger.tone;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.tint,
        borderRadius: BorderRadius.circular(SdRadius.sm),
        border: Border.all(color: t.tintEdge),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: t.text, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: SdText.bodySm.copyWith(color: t.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    return SdButton(
      label: 'تسجيل الدخول',
      icon: Icons.login_rounded,
      kind: SdButtonKind.accent,
      expand: true,
      height: 50,
      onPressed: _isLoading ? null : _login,
    );
  }

  Widget _buildOfflineRouterSetupButton() {
    return SdButton(
      label: 'إعداد الراوتر (أوفلاين)',
      icon: Icons.settings_input_antenna,
      kind: SdButtonKind.secondary,
      expand: true,
      height: 44,
      onPressed: () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NetworkToolsHomePage()));
      },
    );
  }

  /// زر أيقونة صغير في رأس البطاقة للتحقق اليدوي من التحديثات.
  Widget _buildUpdateIconButton() {
    return Tooltip(
      message: 'التحقق من التحديثات',
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _checkingUpdate ? null : _manualCheckForUpdate,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _checkingUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.system_update_alt_rounded,
                    size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionText() {
    final label = _appVersion.isEmpty
        ? 'منصة الصدارة'
        : 'الإصدار v$_appVersion · منصة الصدارة';
    return Text(
      label,
      style: const TextStyle(
        fontFamily: SdText.family,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0x99FFFFFF),
      ),
    );
  }

  // أنماط النص فوق البطاقة الزجاجية الداكنة.
  static const TextStyle _glassText = TextStyle(
    fontFamily: SdText.family,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Colors.white,
  );
  static const TextStyle _glassHint = TextStyle(
    fontFamily: SdText.family,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Color(0x8CFFFFFF),
  );

  /// شاشة التحميل: مكعّب درع يدور + ثلاث مراحل مربوطة بـ _isLoading/_isNavigating.
  Widget _buildLoadingOverlay() {
    final step = _isNavigating ? 2 : 1; // 1=تحقق، 2=صلاحيات/تحضير
    const steps = ['التحقق من البيانات', 'تحميل الصلاحيات', 'تحضير لوحة التحكم'];
    final title = _isNavigating ? 'جارٍ تحضير لوحة التحكم…' : 'جارٍ تسجيل الدخول…';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(opacity: value, child: child),
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.1,
            colors: [SdColors.primaryLight, SdColors.primary, SdColors.primaryEdge],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SpinShieldCube(size: 96),
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: SdColors.accentGlow.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Column(
                  children: [
                    for (var i = 0; i < steps.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: _buildLoadingStep(
                          steps[i],
                          done: i < step,
                          active: i == step,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingStep(String label, {required bool done, required bool active}) {
    final Color dotColor = done
        ? const Color(0xFF69F0AE)
        : active
            ? SdColors.accentGlow
            : Colors.white.withValues(alpha: 0.18);
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            boxShadow: done
                ? const [BoxShadow(color: Color(0xFF69F0AE), blurRadius: 10)]
                : active
                    ? [
                        BoxShadow(
                          color: SdColors.accentGlow.withValues(alpha: 0.25),
                          blurRadius: 0,
                          spreadRadius: 5,
                        )
                      ]
                    : null,
          ),
          child: done
              ? const Icon(Icons.check_rounded, size: 10, color: SdColors.primaryEdge)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: (done || active)
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }
}

/// شارة اتصال حيّة: أخضر نابض (متصل) / أحمر (غير متصل) / رمادي (جارٍ الفحص).
class _LiveStatusBadge extends StatefulWidget {
  const _LiveStatusBadge({required this.loading, required this.offline});
  final bool loading;
  final bool offline;

  @override
  State<_LiveStatusBadge> createState() => _LiveStatusBadgeState();
}

class _LiveStatusBadgeState extends State<_LiveStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LiveStatusBadge old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final connected = !widget.loading && !widget.offline;
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (connected && !reduce) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      if (_pulse.isAnimating) _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    late final Color bg, fg, dot;
    late final String label;
    if (widget.loading) {
      bg = SdColors.ground;
      fg = SdColors.muted;
      dot = SdColors.faint;
      label = 'جارٍ الفحص';
    } else if (widget.offline) {
      bg = SdColors.dangerTint;
      fg = SdColors.danger;
      dot = SdColors.danger;
      label = 'غير متصل';
    } else {
      bg = SdColors.successTint;
      fg = SdColors.successEdge;
      dot = SdColors.success;
      label = 'متصل';
    }

    final connected = !widget.loading && !widget.offline;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          connected
              ? AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final p = _pulse.value;
                    return Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dot,
                        boxShadow: [
                          BoxShadow(
                            color: dot.withValues(alpha: 0.55 * (1 - p)),
                            spreadRadius: 6 * p,
                          ),
                        ],
                      ),
                    );
                  },
                )
              : Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// مكعّب درع يدور حول المحور العمودي (شاشة التحميل).
class _SpinShieldCube extends StatefulWidget {
  const _SpinShieldCube({this.size = 96});
  final double size;

  @override
  State<_SpinShieldCube> createState() => _SpinShieldCubeState();
}

class _SpinShieldCubeState extends State<_SpinShieldCube>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      if (_spin.isAnimating) _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _spin,
      builder: (context, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015)
            ..rotateX(-0.42)
            ..rotateY(_spin.value * 2 * math.pi),
          child: child,
        );
      },
      child: Container(
        width: s,
        height: s,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(s * 0.16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, SdColors.infoTint],
          ),
          border: Border.all(color: const Color(0x261A237E)),
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/logo.png',
            width: s * 0.62,
            height: s * 0.62,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
