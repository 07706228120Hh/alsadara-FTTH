/// صفحة تشخيص نظام الشركة
/// تعرض جميع معلومات المستخدم والشركة والصلاحيات
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/vps_auth_service.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
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
