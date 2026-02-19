/// صفحة تشخيص نظام الشركة
/// تعرض جميع معلومات المستخدم والشركة والصلاحيات
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/vps_auth_service.dart';
import '../services/sadara_api_service.dart';
import '../services/api/api_client.dart';
import '../services/api/api_config.dart';

/// صفحة تشخيص نظام الشركة
class CompanyDiagnosticsPage extends StatefulWidget {
  final String? tenantId;
  final String? tenantCode;
  final Map<String, bool>? pageAccess;

  const CompanyDiagnosticsPage({
    super.key,
    this.tenantId,
    this.tenantCode,
    this.pageAccess,
  });

  @override
  State<CompanyDiagnosticsPage> createState() => _CompanyDiagnosticsPageState();
}

class _CompanyDiagnosticsPageState extends State<CompanyDiagnosticsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final VpsAuthService _authService = VpsAuthService.instance;
  bool _isLoading = false;
  String? _apiTestResult;
  bool? _apiTestSuccess;
  List<Map<String, dynamic>>? _employees;
  bool _loadingEmployees = false;

  // --- حالة تشخيص المنصة ---
  bool _portalTesting = false;
  final List<_PortalDiagResult> _portalResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '🔧 تشخيص النظام',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.indigo[700],
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: Colors.amber,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.person), text: 'المستخدم'),
              Tab(icon: Icon(Icons.business), text: 'الشركة'),
              Tab(icon: Icon(Icons.security), text: 'الصلاحيات'),
              Tab(icon: Icon(Icons.cloud), text: 'API'),
              Tab(icon: Icon(Icons.group), text: 'الموظفين'),
              Tab(icon: Icon(Icons.hub), text: 'المنصة'),
              Tab(icon: Icon(Icons.storage), text: 'الجلسة'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {}),
              tooltip: 'تحديث',
            ),
            IconButton(
              icon: const Icon(Icons.copy_all),
              onPressed: _copyAllDiagnostics,
              tooltip: 'نسخ الكل',
            ),
          ],
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildUserTab(),
            _buildCompanyTab(),
            _buildPermissionsTab(),
            _buildApiTab(),
            _buildEmployeesTab(),
            _buildPortalDiagnosticsTab(),
            _buildSessionTab(),
          ],
        ),
      ),
    );
  }

  /// تبويب معلومات المستخدم
  Widget _buildUserTab() {
    final user = _authService.currentUser;

    if (user == null) {
      return _buildEmptyState('لم يتم تسجيل الدخول', Icons.person_off);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard(
            title: '👤 معلومات المستخدم الأساسية',
            icon: Icons.person,
            color: Colors.blue,
            children: [
              _buildInfoTile('المعرف (ID)', user.id, Icons.fingerprint),
              _buildInfoTile(
                  'اسم المستخدم', user.username, Icons.account_circle),
              _buildInfoTile('الاسم الكامل', user.fullName, Icons.badge),
              _buildInfoTile(
                  'البريد الإلكتروني', user.email ?? 'غير محدد', Icons.email),
              _buildInfoTile(
                  'رقم الهاتف', user.phone ?? 'غير محدد', Icons.phone),
              _buildInfoTile('الدور', user.role, Icons.work),
              _buildInfoTile(
                  'نشط', user.isActive ? '✅ نعم' : '❌ لا', Icons.toggle_on),
              _buildInfoTile('مدير شركة', user.isAdmin ? '✅ نعم' : '❌ لا',
                  Icons.admin_panel_settings),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: '📋 قائمة الصلاحيات (permissions)',
            icon: Icons.list,
            color: Colors.green,
            children: [
              if (user.permissions.isEmpty)
                const ListTile(
                  leading: Icon(Icons.warning, color: Colors.orange),
                  title: Text('لا توجد صلاحيات'),
                )
              else
                ...user.permissions.map(
                    (p) => _buildInfoTile(p, '✅ مفعل', Icons.check_circle)),
            ],
          ),
        ],
      ),
    );
  }

  /// تبويب معلومات الشركة
  Widget _buildCompanyTab() {
    final company = _authService.currentCompany;

    if (company == null) {
      return _buildEmptyState(
          'لم يتم تحميل بيانات الشركة', Icons.business_center);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard(
            title: '🏢 معلومات الشركة',
            icon: Icons.business,
            color: Colors.purple,
            children: [
              _buildInfoTile('المعرف (ID)', company.id, Icons.fingerprint),
              _buildInfoTile('اسم الشركة', company.name, Icons.business),
              _buildInfoTile('كود الشركة', company.code, Icons.qr_code),
              _buildInfoTile(
                  'الشعار', company.logoUrl ?? 'غير محدد', Icons.image),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: '📅 معلومات الاشتراك',
            icon: Icons.calendar_today,
            color: company.isExpired ? Colors.red : Colors.teal,
            children: [
              _buildInfoTile(
                'تاريخ انتهاء الاشتراك',
                company.subscriptionEndDate.toString().split(' ')[0],
                Icons.event,
              ),
              _buildInfoTile(
                'الأيام المتبقية',
                '${company.daysRemaining} يوم',
                Icons.timer,
              ),
              _buildInfoTile(
                'حالة الاشتراك',
                company.subscriptionStatus,
                Icons.info,
              ),
              _buildInfoTile(
                'منتهي',
                company.isExpired ? '❌ نعم' : '✅ لا',
                company.isExpired ? Icons.error : Icons.check_circle,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: '⚡ ميزات النظام الأول المفعلة',
            icon: Icons.flash_on,
            color: Colors.orange,
            children: [
              if (company.enabledFirstSystemFeatures.isEmpty)
                const ListTile(
                  leading: Icon(Icons.warning, color: Colors.orange),
                  title: Text('لا توجد ميزات مفعلة'),
                )
              else
                ...company.enabledFirstSystemFeatures.entries.map(
                  (e) => _buildInfoTile(
                    e.key,
                    e.value ? '✅ مفعل' : '❌ معطل',
                    e.value ? Icons.check_circle : Icons.cancel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: '⚡ ميزات النظام الثاني المفعلة',
            icon: Icons.flash_on,
            color: Colors.cyan,
            children: [
              if (company.enabledSecondSystemFeatures.isEmpty)
                const ListTile(
                  leading: Icon(Icons.warning, color: Colors.orange),
                  title: Text('لا توجد ميزات مفعلة'),
                )
              else
                ...company.enabledSecondSystemFeatures.entries.map(
                  (e) => _buildInfoTile(
                    e.key,
                    e.value ? '✅ مفعل' : '❌ معطل',
                    e.value ? Icons.check_circle : Icons.cancel,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// تبويب الصلاحيات
  Widget _buildPermissionsTab() {
    final user = _authService.currentUser;
    final company = _authService.currentCompany;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // صلاحيات المستخدم - النظام الأول
          _buildSectionCard(
            title: '🔐 صلاحيات المستخدم - النظام الأول',
            icon: Icons.security,
            color: Colors.indigo,
            children: [
              if (user?.firstSystemPermissions.isEmpty ?? true)
                const ListTile(
                  leading: Icon(Icons.warning, color: Colors.orange),
                  title: Text('لا توجد صلاحيات'),
                  subtitle: Text('المستخدم ليس لديه صلاحيات في النظام الأول'),
                )
              else
                ...user!.firstSystemPermissions.entries.map(
                  (e) => _buildInfoTile(
                    e.key,
                    e.value ? '✅ مفعل' : '❌ معطل',
                    e.value ? Icons.check_circle : Icons.cancel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // صلاحيات المستخدم - النظام الثاني
          _buildSectionCard(
            title: '🔐 صلاحيات المستخدم - النظام الثاني',
            icon: Icons.security,
            color: Colors.deepPurple,
            children: [
              if (user?.secondSystemPermissions.isEmpty ?? true)
                const ListTile(
                  leading: Icon(Icons.warning, color: Colors.orange),
                  title: Text('لا توجد صلاحيات'),
                  subtitle: Text('المستخدم ليس لديه صلاحيات في النظام الثاني'),
                )
              else
                ...user!.secondSystemPermissions.entries.map(
                  (e) => _buildInfoTile(
                    e.key,
                    e.value ? '✅ مفعل' : '❌ معطل',
                    e.value ? Icons.check_circle : Icons.cancel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // pageAccess المُمرر للصفحة
          _buildSectionCard(
            title: '📄 pageAccess (المُمرر للواجهة)',
            icon: Icons.pages,
            color: Colors.brown,
            children: [
              if (widget.pageAccess?.isEmpty ?? true)
                const ListTile(
                  leading: Icon(Icons.warning, color: Colors.orange),
                  title: Text('لا توجد صلاحيات صفحات'),
                )
              else
                ...widget.pageAccess!.entries.map(
                  (e) => _buildInfoTile(
                    e.key,
                    e.value ? '✅ مفعل' : '❌ معطل',
                    e.value ? Icons.check_circle : Icons.cancel,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // مقارنة صلاحيات الشركة مع المستخدم
          _buildSectionCard(
            title: '📊 مقارنة الصلاحيات',
            icon: Icons.compare_arrows,
            color: Colors.teal,
            children: [
              ListTile(
                leading: const Icon(Icons.info, color: Colors.blue),
                title: const Text('ملاحظة'),
                subtitle: Text(
                  user?.isAdmin == true
                      ? 'المستخدم مدير شركة - يحصل على جميع صلاحيات الشركة'
                      : 'المستخدم موظف - يحصل فقط على الصلاحيات المخصصة له',
                ),
              ),
              const Divider(),
              _buildInfoTile(
                'عدد صلاحيات الشركة (النظام 1)',
                '${company?.enabledFirstSystemFeatures.values.where((v) => v).length ?? 0}',
                Icons.business,
              ),
              _buildInfoTile(
                'عدد صلاحيات المستخدم (النظام 1)',
                '${user?.firstSystemPermissions.values.where((v) => v).length ?? 0}',
                Icons.person,
              ),
              _buildInfoTile(
                'عدد صلاحيات الشركة (النظام 2)',
                '${company?.enabledSecondSystemFeatures.values.where((v) => v).length ?? 0}',
                Icons.business,
              ),
              _buildInfoTile(
                'عدد صلاحيات المستخدم (النظام 2)',
                '${user?.secondSystemPermissions.values.where((v) => v).length ?? 0}',
                Icons.person,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// تبويب اختبار API
  Widget _buildApiTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard(
            title: '🌐 معلومات الاتصال',
            icon: Icons.cloud,
            color: Colors.blue,
            children: [
              _buildInfoTile(
                'عنوان API',
                ApiConfig.baseUrl,
                Icons.link,
              ),
              _buildInfoTile(
                'التوكن موجود',
                _authService.accessToken != null ? '✅ نعم' : '❌ لا',
                Icons.vpn_key,
              ),
              if (_authService.accessToken != null)
                _buildInfoTile(
                  'طول التوكن',
                  '${_authService.accessToken!.length} حرف',
                  Icons.text_fields,
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: '🧪 اختبار الاتصال',
            icon: Icons.science,
            color: _apiTestSuccess == null
                ? Colors.grey
                : (_apiTestSuccess! ? Colors.green : Colors.red),
            children: [
              ListTile(
                leading: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _apiTestSuccess == null
                            ? Icons.help
                            : (_apiTestSuccess!
                                ? Icons.check_circle
                                : Icons.error),
                        color: _apiTestSuccess == null
                            ? Colors.grey
                            : (_apiTestSuccess! ? Colors.green : Colors.red),
                      ),
                title: Text(_apiTestResult ?? 'اضغط لاختبار الاتصال'),
                subtitle: _apiTestSuccess != null
                    ? Text(_apiTestSuccess! ? 'الاتصال ناجح' : 'فشل الاتصال')
                    : null,
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _testApiConnection,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('اختبار الاتصال بالخادم'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: '📝 معلومات التنقية (Debug)',
            icon: Icons.bug_report,
            color: Colors.orange,
            children: [
              _buildInfoTile(
                'tenantId (المُمرر)',
                widget.tenantId ?? 'غير محدد',
                Icons.business,
              ),
              _buildInfoTile(
                'tenantCode (المُمرر)',
                widget.tenantCode ?? 'غير محدد',
                Icons.qr_code,
              ),
              _buildInfoTile(
                'نوع المستخدم',
                _authService.currentUserType?.name ?? 'غير محدد',
                Icons.person,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// تبويب الجلسة
  Widget _buildSessionTab() {
    final user = _authService.currentUser;
    final company = _authService.currentCompany;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard(
            title: '🔑 حالة الجلسة',
            icon: Icons.lock,
            color: Colors.green,
            children: [
              _buildInfoTile(
                'مسجل الدخول',
                _authService.isLoggedIn ? '✅ نعم' : '❌ لا',
                Icons.login,
              ),
              _buildInfoTile(
                'Super Admin',
                _authService.isSuperAdmin ? '✅ نعم' : '❌ لا',
                Icons.admin_panel_settings,
              ),
              _buildInfoTile(
                'موظف شركة',
                _authService.isCompanyEmployee ? '✅ نعم' : '❌ لا',
                Icons.work,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: '📦 البيانات الخام (JSON)',
            icon: Icons.code,
            color: Colors.grey,
            children: [
              ExpansionTile(
                leading: const Icon(Icons.person),
                title: const Text('بيانات المستخدم'),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey[100],
                    child: SelectableText(
                      user != null
                          ? const JsonEncoder.withIndent('  ')
                              .convert(user.toJson())
                          : 'لا توجد بيانات',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                leading: const Icon(Icons.business),
                title: const Text('بيانات الشركة'),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey[100],
                    child: SelectableText(
                      company != null
                          ? const JsonEncoder.withIndent('  ')
                              .convert(company.toJson())
                          : 'لا توجد بيانات',
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // زر تسجيل الخروج
          ElevatedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تسجيل الخروج'),
                  content: const Text('هل تريد تسجيل الخروج من النظام؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('تسجيل الخروج'),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await _authService.logout();
                if (mounted) {
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (route) => false);
                }
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  /// بناء كارت قسم
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copySection(title, children),
                  tooltip: 'نسخ',
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  /// بناء صف معلومات
  Widget _buildInfoTile(String label, String value, IconData icon) {
    return ListTile(
      leading: Icon(icon, size: 20, color: Colors.grey[600]),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: SelectableText(value),
      dense: true,
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 18),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: '$label: $value'));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('تم نسخ: $label'),
                duration: const Duration(seconds: 1)),
          );
        },
        tooltip: 'نسخ',
      ),
    );
  }

  /// حالة فارغة
  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.cairo(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// اختبار اتصال API
  Future<void> _testApiConnection() async {
    setState(() {
      _isLoading = true;
      _apiTestResult = 'جاري الاختبار...';
      _apiTestSuccess = null;
    });

    try {
      final response = await ApiClient.instance.get<Map<String, dynamic>>(
        '/health',
        (json) => json as Map<String, dynamic>,
      );
      setState(() {
        _isLoading = false;
        if (response.isSuccess) {
          _apiTestResult = 'الخادم يعمل بشكل صحيح ✅';
          _apiTestSuccess = true;
        } else {
          _apiTestResult = 'الخادم أرجع: ${response.statusCode}';
          _apiTestSuccess = false;
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _apiTestResult = 'خطأ: $e';
        _apiTestSuccess = false;
      });
    }
  }

  /// نسخ قسم معين
  void _copySection(String title, List<Widget> children) {
    final buffer = StringBuffer();
    buffer.writeln('=== $title ===');
    // نسخ البيانات المتاحة
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('تم نسخ: $title'),
          duration: const Duration(seconds: 1)),
    );
  }

  /// نسخ كل التشخيصات
  void _copyAllDiagnostics() {
    final user = _authService.currentUser;
    final company = _authService.currentCompany;

    final buffer = StringBuffer();
    buffer.writeln('==============================');
    buffer.writeln('تقرير تشخيص نظام الشركة');
    buffer.writeln('التاريخ: ${DateTime.now()}');
    buffer.writeln('==============================\n');

    buffer.writeln('=== معلومات المستخدم ===');
    if (user != null) {
      buffer.writeln('المعرف: ${user.id}');
      buffer.writeln('اسم المستخدم: ${user.username}');
      buffer.writeln('الاسم الكامل: ${user.fullName}');
      buffer.writeln('البريد: ${user.email ?? "غير محدد"}');
      buffer.writeln('الهاتف: ${user.phone ?? "غير محدد"}');
      buffer.writeln('الدور: ${user.role}');
      buffer.writeln('مدير: ${user.isAdmin}');
      buffer.writeln('نشط: ${user.isActive}');
      buffer.writeln('الصلاحيات: ${user.permissions.join(", ")}');
      buffer.writeln('صلاحيات النظام 1: ${user.firstSystemPermissions}');
      buffer.writeln('صلاحيات النظام 2: ${user.secondSystemPermissions}');
    } else {
      buffer.writeln('لا يوجد مستخدم');
    }

    buffer.writeln('\n=== معلومات الشركة ===');
    if (company != null) {
      buffer.writeln('المعرف: ${company.id}');
      buffer.writeln('الاسم: ${company.name}');
      buffer.writeln('الكود: ${company.code}');
      buffer.writeln('انتهاء الاشتراك: ${company.subscriptionEndDate}');
      buffer.writeln('الأيام المتبقية: ${company.daysRemaining}');
      buffer.writeln('الحالة: ${company.subscriptionStatus}');
      buffer.writeln('ميزات النظام 1: ${company.enabledFirstSystemFeatures}');
      buffer.writeln('ميزات النظام 2: ${company.enabledSecondSystemFeatures}');
    } else {
      buffer.writeln('لا توجد شركة');
    }

    buffer.writeln('\n=== pageAccess ===');
    buffer.writeln(widget.pageAccess?.toString() ?? 'غير محدد');

    buffer.writeln('\n=== معلومات API ===');
    buffer.writeln('عنوان API: ${ApiConfig.baseUrl}');
    buffer.writeln('tenantId: ${widget.tenantId}');
    buffer.writeln('tenantCode: ${widget.tenantCode}');

    // تشخيص المنصة
    buffer.writeln('\n=== تشخيص منصة الصدارة ===');
    final sadaraApi = SadaraApiService.instance;
    buffer.writeln(
        'SadaraAPI مصادق: ${sadaraApi.isAuthenticated ? "نعم" : "لا"}');
    buffer.writeln(
        'VPS Token: ${_authService.accessToken != null ? "موجود (${_authService.accessToken!.length} حرف)" : "غير موجود"}');
    buffer.writeln(
        'ApiClient Token: ${ApiClient.instance.authToken != null ? "موجود (${ApiClient.instance.authToken!.length} حرف)" : "غير موجود"}');
    buffer.writeln('عنوان API المنصة: ${SadaraApiService.baseUrl}');
    if (_portalResults.isNotEmpty) {
      buffer.writeln('\n--- نتائج التشخيص ---');
      for (final r in _portalResults) {
        buffer.writeln('${r.title}: ${r.status}');
        if (r.duration != null) {
          buffer.writeln('  الزمن: ${r.duration!.inMilliseconds} مللي ثانية');
        }
        if (r.details != null) {
          buffer.writeln('  التفاصيل: ${r.details}');
        }
      }
    } else {
      buffer.writeln('لم يتم تشغيل تشخيص المنصة بعد');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ تم نسخ تقرير التشخيص الكامل'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// تبويب الموظفين
  Widget _buildEmployeesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard(
            title: '👥 قائمة موظفي الشركة',
            icon: Icons.group,
            color: Colors.teal,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton.icon(
                  onPressed: _loadingEmployees ? null : _fetchEmployees,
                  icon: _loadingEmployees
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(_loadingEmployees
                      ? 'جاري التحميل...'
                      : 'جلب قائمة الموظفين'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
              if (_employees != null) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'إجمالي الموظفين: ${_employees!.length}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                ..._employees!.map((emp) => Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: emp['Role'] == 'CompanyAdmin'
                              ? Colors.amber
                              : Colors.blue,
                          child: Icon(
                            emp['Role'] == 'CompanyAdmin'
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          emp['FullName'] ?? 'بدون اسم',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('📱 ${emp['PhoneNumber'] ?? 'غير محدد'}'),
                            Text('👔 ${emp['Role'] ?? 'غير محدد'}'),
                            if (emp['Department'] != null)
                              Text('🏢 ${emp['Department']}'),
                          ],
                        ),
                        trailing: Icon(
                          emp['IsActive'] == true
                              ? Icons.check_circle
                              : Icons.cancel,
                          color: emp['IsActive'] == true
                              ? Colors.green
                              : Colors.red,
                        ),
                        isThreeLine: true,
                      ),
                    )),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// تبويب تشخيص منصة الصدارة
  Widget _buildPortalDiagnosticsTab() {
    final sadaraApi = SadaraApiService.instance;
    final vps = VpsAuthService.instance;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // معلومات التوكن والاتصال
          _buildSectionCard(
            title: '🔑 حالة المصادقة للمنصة',
            icon: Icons.vpn_key,
            color: Colors.deepPurple,
            children: [
              _buildInfoTile(
                'SadaraAPI مصادق',
                sadaraApi.isAuthenticated ? '✅ نعم' : '❌ لا',
                Icons.lock,
              ),
              _buildInfoTile(
                'VPS Token',
                vps.accessToken != null
                    ? '✅ موجود (${vps.accessToken!.length} حرف)'
                    : '❌ غير موجود',
                Icons.token,
              ),
              _buildInfoTile(
                'ApiClient Token',
                ApiClient.instance.authToken != null
                    ? '✅ موجود (${ApiClient.instance.authToken!.length} حرف)'
                    : '❌ غير موجود',
                Icons.key,
              ),
              _buildInfoTile(
                'عنوان API المنصة',
                SadaraApiService.baseUrl,
                Icons.link,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // زر تشغيل التشخيص
          _buildSectionCard(
            title: '🧪 تشخيص جلب بيانات المنصة',
            icon: Icons.science,
            color: _portalResults.isEmpty
                ? Colors.grey
                : (_portalResults.every((r) => r.success)
                    ? Colors.green
                    : Colors.orange),
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton.icon(
                  onPressed: _portalTesting ? null : _runPortalDiagnostics,
                  icon: _portalTesting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_portalTesting
                      ? 'جاري التشخيص...'
                      : 'تشغيل تشخيص المنصة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ),
              if (_portalResults.isNotEmpty) ...[
                const Divider(),
                ..._portalResults.map((r) => ListTile(
                      leading: _portalTesting && r.status == 'جاري...'
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              r.success
                                  ? Icons.check_circle
                                  : (r.status == 'جاري...'
                                      ? Icons.hourglass_top
                                      : Icons.error),
                              color: r.success
                                  ? Colors.green
                                  : (r.status == 'جاري...'
                                      ? Colors.blue
                                      : Colors.red),
                            ),
                      title: Text(
                        r.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.status),
                          if (r.duration != null)
                            Text(
                              '⏱ ${r.duration!.inMilliseconds} مللي ثانية',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          if (r.details != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SelectableText(
                                  r.details!,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      isThreeLine: r.details != null,
                    )),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// تشغيل تشخيص المنصة الكامل
  Future<void> _runPortalDiagnostics() async {
    final api = SadaraApiService.instance;
    final vps = VpsAuthService.instance;

    setState(() {
      _portalTesting = true;
      _portalResults.clear();
      _portalResults.addAll([
        _PortalDiagResult(title: '1️⃣ فحص التوكن', status: 'جاري...'),
        _PortalDiagResult(title: '2️⃣ استعادة الجلسة', status: 'بانتظار...'),
        _PortalDiagResult(title: '3️⃣ جلب كل الطلبات', status: 'بانتظار...'),
        _PortalDiagResult(title: '4️⃣ فرز طلبات المواطن', status: 'بانتظار...'),
        _PortalDiagResult(title: '5️⃣ فرز طلبات الوكيل', status: 'بانتظار...'),
        _PortalDiagResult(title: '6️⃣ جلب الإحصائيات', status: 'بانتظار...'),
      ]);
    });

    // ====== 1. فحص التوكن ======
    final sw1 = Stopwatch()..start();
    final hasToken =
        vps.accessToken != null || ApiClient.instance.authToken != null;
    sw1.stop();
    setState(() {
      _portalResults[0] = _PortalDiagResult(
        title: '1️⃣ فحص التوكن',
        status: hasToken
            ? 'تم العثور على توكن (VPS: ${vps.accessToken != null ? "✅" : "❌"}, ApiClient: ${ApiClient.instance.authToken != null ? "✅" : "❌"})'
            : '❌ لا يوجد توكن في أي مصدر',
        success: hasToken,
        duration: sw1.elapsed,
      );
      _portalResults[1] =
          _PortalDiagResult(title: '2️⃣ استعادة الجلسة', status: 'جاري...');
    });

    // ====== 2. استعادة الجلسة (إذا لم يكن هناك توكن) ======
    final sw2 = Stopwatch()..start();
    bool sessionRestored = hasToken;
    if (!hasToken) {
      try {
        final restored = await vps.restoreSession();
        if (!restored) {
          await vps.refreshAccessToken();
        }
        sessionRestored = vps.accessToken != null;
      } catch (e) {
        sessionRestored = false;
      }
    }
    sw2.stop();
    setState(() {
      _portalResults[1] = _PortalDiagResult(
        title: '2️⃣ استعادة الجلسة',
        status: sessionRestored
            ? (hasToken
                ? '✅ التوكن كان موجوداً مسبقاً'
                : '✅ تم استعادة الجلسة بنجاح')
            : '❌ فشل في استعادة الجلسة - يرجى تسجيل الدخول مجدداً',
        success: sessionRestored,
        duration: sw2.elapsed,
      );
      _portalResults[2] =
          _PortalDiagResult(title: '3️⃣ جلب كل الطلبات', status: 'جاري...');
    });

    // ====== 3. جلب كل الطلبات ======
    List<dynamic> allResults = [];
    final sw3 = Stopwatch()..start();
    try {
      allResults = await api.getServiceRequests(page: 1, pageSize: 200);
      sw3.stop();
      setState(() {
        _portalResults[2] = _PortalDiagResult(
          title: '3️⃣ جلب كل الطلبات',
          status: '✅ تم جلب ${allResults.length} طلب بنجاح',
          success: true,
          duration: sw3.elapsed,
          details: allResults.isNotEmpty
              ? 'أول طلب: ${const JsonEncoder.withIndent("  ").convert(allResults.first)}'
                  .substring(
                      0,
                      500.clamp(
                          0,
                          allResults.isNotEmpty
                              ? const JsonEncoder.withIndent("  ")
                                  .convert(allResults.first)
                                  .length
                              : 0))
              : 'لا توجد طلبات',
        );
      });
    } catch (e) {
      sw3.stop();
      setState(() {
        _portalResults[2] = _PortalDiagResult(
          title: '3️⃣ جلب كل الطلبات',
          status: '❌ فشل في جلب الطلبات',
          success: false,
          duration: sw3.elapsed,
          details: e.toString(),
        );
      });
    }

    // ====== 4. فرز طلبات المواطن ======
    setState(() {
      _portalResults[3] =
          _PortalDiagResult(title: '4️⃣ فرز طلبات المواطن', status: 'جاري...');
    });
    final sw4 = Stopwatch()..start();
    int citizenCount = 0;
    try {
      for (final r in allResults) {
        if (r is Map<String, dynamic>) {
          final details = r['details'];
          if (details != null) {
            try {
              final parsed = json.decode(details.toString());
              if (parsed is Map) {
                final source = parsed['source']?.toString().toLowerCase() ?? '';
                if (source != 'agent_portal') citizenCount++;
              } else {
                citizenCount++;
              }
            } catch (_) {
              citizenCount++;
            }
          } else {
            citizenCount++;
          }
        }
      }
      sw4.stop();
      setState(() {
        _portalResults[3] = _PortalDiagResult(
          title: '4️⃣ فرز طلبات المواطن',
          status: '✅ عدد طلبات المواطن: $citizenCount',
          success: true,
          duration: sw4.elapsed,
        );
      });
    } catch (e) {
      sw4.stop();
      setState(() {
        _portalResults[3] = _PortalDiagResult(
          title: '4️⃣ فرز طلبات المواطن',
          status: '❌ خطأ في فرز الطلبات: $e',
          success: false,
          duration: sw4.elapsed,
        );
      });
    }

    // ====== 5. فرز طلبات الوكيل ======
    setState(() {
      _portalResults[4] =
          _PortalDiagResult(title: '5️⃣ فرز طلبات الوكيل', status: 'جاري...');
    });
    final sw5 = Stopwatch()..start();
    int agentCount = 0;
    try {
      for (final r in allResults) {
        if (r is Map<String, dynamic>) {
          final details = r['details'];
          if (details != null) {
            try {
              final parsed = json.decode(details.toString());
              if (parsed is Map) {
                final source = parsed['source']?.toString().toLowerCase() ?? '';
                if (source == 'agent_portal') agentCount++;
              }
            } catch (_) {}
          }
        }
      }
      sw5.stop();
      setState(() {
        _portalResults[4] = _PortalDiagResult(
          title: '5️⃣ فرز طلبات الوكيل',
          status: '✅ عدد طلبات الوكيل: $agentCount',
          success: true,
          duration: sw5.elapsed,
        );
      });
    } catch (e) {
      sw5.stop();
      setState(() {
        _portalResults[4] = _PortalDiagResult(
          title: '5️⃣ فرز طلبات الوكيل',
          status: '❌ خطأ في فرز الطلبات: $e',
          success: false,
          duration: sw5.elapsed,
        );
      });
    }

    // ====== 6. جلب الإحصائيات ======
    setState(() {
      _portalResults[5] =
          _PortalDiagResult(title: '6️⃣ جلب الإحصائيات', status: 'جاري...');
    });
    final sw6 = Stopwatch()..start();
    try {
      final stats = await api.getServiceRequestStatistics();
      sw6.stop();
      setState(() {
        _portalResults[5] = _PortalDiagResult(
          title: '6️⃣ جلب الإحصائيات',
          status: '✅ تم جلب الإحصائيات بنجاح',
          success: true,
          duration: sw6.elapsed,
          details: const JsonEncoder.withIndent('  ').convert(stats),
        );
      });
    } catch (e) {
      sw6.stop();
      setState(() {
        _portalResults[5] = _PortalDiagResult(
          title: '6️⃣ جلب الإحصائيات',
          status: '❌ فشل: $e',
          success: false,
          duration: sw6.elapsed,
          details: e.toString(),
        );
      });
    }

    setState(() {
      _portalTesting = false;
    });
  }

  /// جلب قائمة الموظفين من API
  Future<void> _fetchEmployees() async {
    final company = _authService.currentCompany;
    if (company == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ لا توجد شركة محددة'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _loadingEmployees = true;
    });

    try {
      final response = await ApiClient.instance.get(
        '/companies/${company.id}/employees',
        (json) => json,
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data;
        if (data is Map && data['data'] != null) {
          setState(() {
            _employees = List<Map<String, dynamic>>.from(data['data']);
          });
        } else if (data is List) {
          setState(() {
            _employees = List<Map<String, dynamic>>.from(data);
          });
        }

        // البحث عن "صباح"
        final sabah = _employees
            ?.where((e) =>
                (e['FullName']?.toString().contains('صباح') ?? false) ||
                (e['PhoneNumber']?.toString().contains('صباح') ?? false))
            .toList();

        if (sabah != null && sabah.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '✅ تم العثور على "${sabah.first['FullName']}" في قائمة الموظفين!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل جلب الموظفين: ${response.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ خطأ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _loadingEmployees = false;
      });
    }
  }
}

/// نتيجة اختبار تشخيص المنصة
class _PortalDiagResult {
  final String title;
  final String status;
  final bool success;
  final Duration? duration;
  final String? details;

  _PortalDiagResult({
    required this.title,
    required this.status,
    this.success = false,
    this.duration,
    this.details,
  });
}
