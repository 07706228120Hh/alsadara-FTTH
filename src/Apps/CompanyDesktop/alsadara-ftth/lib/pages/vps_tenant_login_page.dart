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
      debugPrint('❌ خطأ في جلب قائمة الشركات: $e');
      setState(() {
        _loadingCompanies = false;
        _companiesLoadError = 'خطأ في الاتصال: $e';
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
      debugPrint('خطأ في تحميل بيانات الدخول المحفوظة: $e');
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
      debugPrint('خطأ في حفظ بيانات الدخول: $e');
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
      debugPrint('خطأ في حذف بيانات الدخول: $e');
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
        _errorMessage = 'حدث خطأ في الاتصال: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateAfterLogin() {
    if (_authService.isSuperAdmin) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SuperAdminDashboard()),
      );
    } else if (_authService.currentUser != null &&
        _authService.currentCompany != null) {
      final user = _authService.currentUser!;
      final company = _authService.currentCompany!;

      // تحويل الصلاحيات
      final Map<String, bool> pageAccess = {};
      for (final permission in user.permissions) {
        pageAccess[permission] = true;
      }
      // إضافة صلاحيات النظام الأول والثاني
      user.firstSystemPermissions.forEach((key, value) {
        if (value) pageAccess[key] = true;
      });
      user.secondSystemPermissions.forEach((key, value) {
        if (value) pageAccess[key] = true;
      });

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomePage(
            username: user.fullName.isNotEmpty ? user.fullName : user.username,
            permissions: user.isAdmin ? 'مدير' : user.role,
            department: company.name,
            center: company.code,
            salary: '0',
            pageAccess: pageAccess,
            tenantId: company.id,
            tenantCode: company.code,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              const Color(0xFF1a237e),
              const Color(0xFF0d47a1),
              Colors.indigo[400]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 450),
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // الشعار
                        AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.indigo[700]!,
                                    Colors.indigo[500]!,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.indigo.withValues(alpha: 0.3),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.fiber_smart_record,
                                size: 64,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 24),

                        // العنوان
                        Text(
                          'منصة صدارة',
                          style: GoogleFonts.cairo(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo[900],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'تسجيل الدخول',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),

                        // شارة VPS API
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_done,
                                  size: 16, color: Colors.green[700]),
                              const SizedBox(width: 4),
                              Text(
                                'VPS API',
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // قسم بيانات الدخول المحفوظة
                        if (_savedCredentials.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.bookmark,
                                        color: Colors.blue[700], size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'حسابات محفوظة',
                                      style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[700],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                DropdownButtonFormField<SavedCredential>(
                                  value: _selectedCredential,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    hintText: 'اختر حساب محفوظ',
                                    hintStyle: GoogleFonts.cairo(),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                  items: _savedCredentials.map((credential) {
                                    return DropdownMenuItem(
                                      value: credential,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              credential.displayName,
                                              style: GoogleFonts.cairo(
                                                  fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                size: 18, color: Colors.red),
                                            onPressed: () {
                                              Navigator.pop(context);
                                              _deleteCredential(credential);
                                            },
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      _selectCredential(value);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                        ],

                        // رسالة الخطأ
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline,
                                    color: Colors.red[700]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: GoogleFonts.cairo(
                                      color: Colors.red[700],
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // رسالة خطأ تحميل الشركات
                        if (_companiesLoadError != null && !_loadingCompanies)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber,
                                    color: Colors.orange[700]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _companiesLoadError!,
                                    style: GoogleFonts.cairo(
                                      color: Colors.orange[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _loadingCompanies = true;
                                      _companiesLoadError = null;
                                    });
                                    _loadCompanies();
                                  },
                                  child: Text(
                                    'إعادة المحاولة',
                                    style: GoogleFonts.cairo(
                                      color: Colors.orange[700],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // قائمة الشركات المنسدلة
                        _loadingCompanies
                            ? Container(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'جاري تحميل قائمة الشركات...',
                                      style: GoogleFonts.cairo(
                                          color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              )
                            : DropdownButtonFormField<CompanyListItem>(
                                value: _selectedCompany,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'اختر الشركة',
                                  labelStyle: GoogleFonts.cairo(),
                                  hintText: _companies.isEmpty
                                      ? 'لا توجد شركات (اختر مدير النظام)'
                                      : 'اختر الشركة من القائمة',
                                  hintStyle: GoogleFonts.cairo(fontSize: 12),
                                  prefixIcon: const Icon(Icons.business),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                                items: _buildCompanyDropdownItems(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedCompany = value;
                                    _selectedCredential = null;
                                  });
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'يرجى اختيار الشركة';
                                  }
                                  return null;
                                },
                              ),
                        const SizedBox(height: 16),

                        // اسم المستخدم
                        TextFormField(
                          controller: _usernameController,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'اسم المستخدم / رقم الهاتف',
                            labelStyle: GoogleFonts.cairo(),
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'يرجى إدخال اسم المستخدم';
                            }
                            return null;
                          },
                          onChanged: (_) {
                            setState(() => _selectedCredential = null);
                          },
                        ),
                        const SizedBox(height: 16),

                        // كلمة المرور
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            labelStyle: GoogleFonts.cairo(),
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(
                                    () => _obscurePassword = !_obscurePassword);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'يرجى إدخال كلمة المرور';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 16),

                        // تذكرني
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() => _rememberMe = value ?? false);
                              },
                              activeColor: Colors.indigo[700],
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _rememberMe = !_rememberMe);
                                },
                                child: Text(
                                  'تذكرني (حفظ بيانات الدخول)',
                                  style: GoogleFonts.cairo(
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // زر تسجيل الدخول
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 3,
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
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.login),
                                      const SizedBox(width: 8),
                                      Text(
                                        'تسجيل الدخول',
                                        style: GoogleFonts.cairo(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // معلومات إضافية
                        if (_savedCredentials.isNotEmpty)
                          Text(
                            '${_savedCredentials.length} حسابات محفوظة',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: Colors.grey[500],
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
