/// صفحة تسجيل دخول الشركات عبر VPS API
/// تستخدم VpsAuthService بدلاً من Firebase
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/vps_auth_service.dart';
import '../services/api/api_client.dart';
import '../services/api/api_config.dart';
import 'home_page.dart';
import 'super_admin/super_admin_dashboard.dart';
import '../permissions/permissions.dart';

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

/// نموذج الشركة للقائمة المنسدلة
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

  /// مقارنة الشركات بناءً على الكود
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompanyListItem &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;
}

class VpsTenantLoginPage extends StatefulWidget {
  const VpsTenantLoginPage({super.key});

  @override
  State<VpsTenantLoginPage> createState() => _VpsTenantLoginPageState();
}

class _VpsTenantLoginPageState extends State<VpsTenantLoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = VpsAuthService.instance;

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  bool _rememberMe = false;

  // قائمة الشركات
  List<CompanyListItem> _companies = [];
  CompanyListItem? _selectedCompany;
  bool _loadingCompanies = true;
  String? _companiesLoadError; // رسالة خطأ تحميل الشركات

  // بيانات الدخول المحفوظة
  List<SavedCredential> _savedCredentials = [];
  SavedCredential? _selectedCredential;

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _loadCompanies();
    _loadSavedCredentials();
  }

  /// جلب قائمة الشركات من API
  Future<void> _loadCompanies() async {
    try {
      debugPrint('🔄 جاري جلب قائمة الشركات من API...');

      final response = await ApiClient.instance.get(
        '/companies/list',
        (json) => json,
      );

      debugPrint(
          '📥 استجابة API: success=${response.isSuccess}, statusCode=${response.statusCode}');

      if (response.isSuccess && response.data != null) {
        final data = response.data;
        List<dynamic> companiesList = [];

        if (data is List) {
          companiesList = data;
        } else if (data is Map && data['data'] != null) {
          companiesList = data['data'] as List;
        } else if (data is Map && data['success'] == true) {
          final innerData = data['data'];
          if (innerData is List) {
            companiesList = innerData;
          }
        }

        debugPrint('✅ تم جلب ${companiesList.length} شركة');
        for (var c in companiesList) {
          debugPrint(
              '   - ${c['Name'] ?? c['name']} (${c['Code'] ?? c['code']})');
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
        debugPrint('⚠️ فشل جلب الشركات: ${response.message}');
        setState(() {
          _loadingCompanies = false;
          _companiesLoadError = response.message ?? 'فشل في جلب قائمة الشركات';
        });
      }
    } catch (e) {
      debugPrint('❌ خطأ في جلب قائمة الشركات');
      setState(() {
        _loadingCompanies = false;
        _companiesLoadError = 'خطأ في الاتصال';
      });
    }
  }

  /// تحميل بيانات الدخول المحفوظة
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
      debugPrint('خطأ في تحميل بيانات الدخول المحفوظة');
    }
  }

  /// حفظ بيانات الدخول
  Future<void> _saveCredential() async {
    if (!_rememberMe || _selectedCompany == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // إزالة البيانات القديمة لنفس المستخدم والشركة
      _savedCredentials.removeWhere((c) =>
          c.companyCode == _selectedCompany!.code &&
          c.username == _usernameController.text.trim());

      // إضافة البيانات الجديدة
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

      // الاحتفاظ بأحدث 10 بيانات فقط
      if (_savedCredentials.length > 10) {
        _savedCredentials = _savedCredentials.sublist(0, 10);
      }

      // حفظ في SharedPreferences
      await prefs.setString(
        'vps_saved_credentials',
        jsonEncode(_savedCredentials.map((c) => c.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('خطأ في حفظ بيانات الدخول');
    }
  }

  /// حذف بيانات دخول محفوظة
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف بيانات الدخول'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في حذف بيانات الدخول');
    }
  }

  /// اختيار بيانات دخول محفوظة
  void _selectCredential(SavedCredential credential) {
    setState(() {
      _selectedCredential = credential;
      _usernameController.text = credential.username;
      _passwordController.text = credential.password;

      // البحث عن الشركة في القائمة
      // استخدام indexWhere للتحقق من وجود الشركة
      final companyIndex = _companies.indexWhere(
        (c) => c.code == credential.companyCode,
      );

      if (companyIndex != -1) {
        // الشركة موجودة في القائمة
        _selectedCompany = _companies[companyIndex];
      } else if (credential.companyCode == '1') {
        // مدير النظام
        _selectedCompany = CompanyListItem(
          id: '1',
          name: 'مدير النظام',
          code: '1',
        );
      } else {
        // الشركة غير موجودة - إعادة تعيين
        _selectedCompany = null;
        debugPrint('⚠️ الشركة ${credential.companyCode} غير موجودة في القائمة');
      }
    });
  }

  /// بناء عناصر القائمة المنسدلة للشركات
  List<DropdownMenuItem<CompanyListItem>> _buildCompanyDropdownItems() {
    final List<DropdownMenuItem<CompanyListItem>> items = [];

    // إضافة خيار مدير النظام
    items.add(
      DropdownMenuItem(
        value: CompanyListItem(
          id: '1',
          name: 'مدير النظام',
          code: '1',
        ),
        child: Row(
          children: [
            Icon(Icons.admin_panel_settings,
                color: Colors.amber[700], size: 20),
            const SizedBox(width: 8),
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

    // إضافة فاصل
    items.add(
      const DropdownMenuItem(
        enabled: false,
        child: Divider(),
      ),
    );

    // إضافة الشركات (باستثناء الشركة ذات الكود '1' لتجنب التكرار)
    for (final company in _companies) {
      if (company.code == '1') continue; // تخطي إذا كان الكود '1'

      items.add(
        DropdownMenuItem(
          value: company,
          child: Row(
            children: [
              if (company.logoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.network(
                    '${ApiConfig.baseUrl.replaceAll('/api', '')}${company.logoUrl}',
                    width: 24,
                    height: 24,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(Icons.business,
                        size: 20, color: Colors.indigo[400]),
                  ),
                )
              else
                Icon(Icons.business, size: 20, color: Colors.indigo[400]),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      company.name,
                      style: GoogleFonts.cairo(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      company.code,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return items;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCompany == null) {
      setState(() {
        _errorMessage = 'يرجى اختيار الشركة';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _authService.login(
        companyCodeOrType: _selectedCompany!.code,
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      if (!mounted) return;

      if (result.success) {
        await _saveCredential();
        _navigateAfterLogin();
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'حدث خطأ غير متوقع';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ في الاتصال';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateAfterLogin() async {
    if (_authService.isSuperAdmin) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SuperAdminDashboard()),
      );
    } else if (_authService.currentUser != null &&
        _authService.currentCompany != null) {
      final user = _authService.currentUser!;
      final company = _authService.currentCompany!;

      // V2: تحميل الصلاحيات من PermissionManager
      final pm = PermissionManager.instance;
      if (!pm.isLoaded) {
        await pm.loadPermissions();
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(
            username: user.fullName.isNotEmpty ? user.fullName : user.username,
            permissions: user.isAdmin ? 'مدير' : _mapRoleToArabic(user.role),
            department: company.name,
            center: company.code,
            salary: '0',
            tenantId: company.id,
            tenantCode: company.code,
          ),
        ),
      );
    }
  }

  String _mapRoleToArabic(String role) {
    switch (role.toLowerCase()) {
      case 'company_admin':
      case 'admin':
      case 'manager':
      case 'super_admin':
        return 'مدير';
      case 'technical_leader':
        return 'ليدر';
      case 'technician':
        return 'فني';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    // الحصول على حجم الشاشة
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isSmallScreen = screenWidth < 600;
    final padding = isSmallScreen ? 16.0 : 24.0;
    final cardPadding = isSmallScreen ? 20.0 : 32.0;
    final logoSize = isSmallScreen ? 60.0 : 80.0;
    final maxCardWidth = screenWidth > 500 ? 420.0 : screenWidth - 32;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          // خلفية Navy داكنة من التصميم
          color: Color(0xFF0D1B2A),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: screenHeight - 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الشعار - أيقونة الماسة
                    Container(
                      width: logoSize,
                      height: logoSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFF152238),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF1E3A5F),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.diamond_outlined,
                          size: logoSize * 0.5,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 24 : 40),

                    // بطاقة تسجيل الدخول
                    Container(
                      constraints: BoxConstraints(maxWidth: maxCardWidth),
                      padding: EdgeInsets.all(cardPadding),
                      decoration: BoxDecoration(
                        color: const Color(0xFF152238).withOpacity(0.6),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: const Color(0xFF1E3A5F),
                          width: 1,
                        ),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // العنوان
                            Text(
                              'مرحباً بك',
                              style: GoogleFonts.cairo(
                                fontSize: isSmallScreen ? 22 : 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: isSmallScreen ? 16 : 24),

                            // تبويبات Super Admin / Tenant
                            _buildLoginTabs(),
                            const SizedBox(height: 24),

                            // رسالة الخطأ
                            if (_errorMessage != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFEF4444).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFEF4444)
                                        .withOpacity(0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Color(0xFFEF4444), size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: GoogleFonts.cairo(
                                          color: const Color(0xFFEF4444),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // حقل البريد/اسم المستخدم
                            _buildTextField(
                              controller: _usernameController,
                              label: 'البريد الإلكتروني أو اسم المستخدم',
                              hint: 'user@sadara.com',
                              icon: Icons.email_outlined,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'يرجى إدخال اسم المستخدم';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: isSmallScreen ? 12 : 16),

                            // حقل كلمة المرور
                            _buildTextField(
                              controller: _passwordController,
                              label: 'كلمة المرور',
                              hint: '••••••••',
                              icon: Icons.lock_outline,
                              isPassword: true,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'يرجى إدخال كلمة المرور';
                                }
                                return null;
                              },
                            ),
                            SizedBox(height: isSmallScreen ? 16 : 24),

                            // زر تسجيل الدخول بتدرج ذهبي
                            _buildLoginButton(),
                            SizedBox(height: isSmallScreen ? 16 : 24),

                            // تسجيل الدخول بالبصمة
                            _buildBiometricLogin(),
                            SizedBox(height: isSmallScreen ? 12 : 16),

                            // نسيت كلمة المرور
                            TextButton(
                              onPressed: () {},
                              child: Text(
                                'نسيت كلمة المرور؟',
                                style: GoogleFonts.cairo(
                                  color: const Color(0xFF64748B),
                                  fontSize: isSmallScreen ? 12 : 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// تبويبات الشركة/الوكيل و مدير النظام
  Widget _buildLoginTabs() {
    final isSuperAdmin = _selectedCompany?.code == '1';

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              label: 'شركة / وكيل',
              icon: Icons.people_outline,
              isSelected: !isSuperAdmin,
              onTap: () {
                setState(() {
                  _selectedCompany =
                      _companies.isNotEmpty ? _companies.first : null;
                });
              },
            ),
          ),
          Expanded(
            child: _buildTabButton(
              label: 'مدير النظام',
              icon: Icons.shield_outlined,
              isSelected: isSuperAdmin,
              onTap: () {
                setState(() {
                  _selectedCompany = CompanyListItem(
                    id: '1',
                    name: 'مدير النظام',
                    code: '1',
                  );
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3A5F) : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// حقل إدخال بالتصميم الجديد
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPassword ? _obscurePassword : false,
          textDirection: TextDirection.ltr,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(
              color: const Color(0xFF475569),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              icon,
              color: const Color(0xFF64748B),
              size: 20,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF64748B),
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  )
                : Icon(icon, color: const Color(0xFF64748B), size: 20),
            filled: true,
            fillColor: const Color(0xFF0D1B2A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFEF4444)),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          validator: validator,
          onFieldSubmitted: (_) => _login(),
        ),
      ],
    );
  }

  /// زر تسجيل الدخول بتدرج ذهبي
  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFFD4A574),
              Color(0xFFF59E0B),
              Color(0xFFD97706),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF59E0B).withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _login,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  'تسجيل الدخول',
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }

  /// تسجيل الدخول بالبصمة
  Widget _buildBiometricLogin() {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: const Color(0xFF152238),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF1E3A5F),
            ),
          ),
          child: IconButton(
            onPressed: () {
              // TODO: تنفيذ تسجيل الدخول بالبصمة
            },
            icon: const Icon(
              Icons.fingerprint,
              color: Color(0xFF3B82F6),
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'تسجيل الدخول بالبصمة',
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}
