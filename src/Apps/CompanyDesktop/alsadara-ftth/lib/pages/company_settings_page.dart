/// اسم الصفحة: إعدادات الشركة
/// وصف الصفحة: صفحة عرض وإدارة إعدادات الشركة ومعلوماتها
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2025
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../services/sadara_api_service.dart';
import '../services/vps_auth_service.dart';
import '../services/departments_data_service.dart';
import '../services/centers_data_service.dart';
import '../services/company_settings_service.dart';
import '../services/custom_auth_service.dart';
import 'printer_settings_page.dart';
import 'settings_page.dart';
import 'settings_text_scale_page.dart';
import '../widgets/map_location_picker.dart';

class CompanySettingsPage extends StatefulWidget {
  final String? companyId;
  final String? companyCode;
  final String currentUserRole;
  final String currentUsername;

  const CompanySettingsPage({
    super.key,
    this.companyId,
    this.companyCode,
    required this.currentUserRole,
    required this.currentUsername,
  });

  @override
  State<CompanySettingsPage> createState() => _CompanySettingsPageState();
}

class _CompanySettingsPageState extends State<CompanySettingsPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _companyData;
  String? _errorMessage;

  // Departments state
  List<Map<String, dynamic>> _departments = [];
  bool _isDepartmentsLoading = false;
  int? _expandedDepartmentId;

  // Centers state
  List<Map<String, dynamic>> _centers = [];
  bool _isCentersLoading = false;

  // Tab controller
  late TabController _tabController;

  // Report/Manager settings (VPS)
  final _managerNameCtrl = TextEditingController();
  final _managerWhatsAppCtrl = TextEditingController();
  bool _receiveReports = true;
  bool _bulkSendReport = true;
  bool _dailyReport = false;
  bool _weeklyReport = false;
  bool _isReportSettingsLoading = false;
  bool _isReportSettingsSaving = false;

  // بيانات المستخدم الميداني
  final _fieldUsernameCtrl = TextEditingController();
  final _fieldPasswordCtrl = TextEditingController();
  bool _showFieldPassword = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadCompanyData();
    _loadDepartments();
    _loadCenters();
    _loadReportSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _managerNameCtrl.dispose();
    _managerWhatsAppCtrl.dispose();
    _fieldUsernameCtrl.dispose();
    _fieldPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCompanyData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Try to get company ID from params or VpsAuthService
      final companyId =
          widget.companyId ?? VpsAuthService.instance.currentCompanyId;

      if (companyId == null || companyId.isEmpty) {
        // Fall back to local data from VpsAuthService
        final company = VpsAuthService.instance.currentCompany;
        if (company != null) {
          setState(() {
            _companyData = company.toJson();
            _isLoading = false;
          });
          return;
        }
        setState(() {
          _errorMessage = 'لم يتم العثور على معرّف الشركة';
          _isLoading = false;
        });
        return;
      }

      // Fetch full company details from API
      final response = await ApiService.instance.get('/companies/$companyId');
      if (!mounted) return;

      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _companyData =
              response['data'] is Map<String, dynamic> ? response['data'] : {};
          _isLoading = false;
        });
      } else {
        // Fall back to local data
        final company = VpsAuthService.instance.currentCompany;
        if (company != null) {
          setState(() {
            _companyData = company.toJson();
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage =
                response['message']?.toString() ?? 'فشل في تحميل بيانات الشركة';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      // Fall back to local data on error
      final company = VpsAuthService.instance.currentCompany;
      if (company != null) {
        setState(() {
          _companyData = company.toJson();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'خطأ في الاتصال';
          _isLoading = false;
        });
      }
    }
  }

  // ── ألوان الثيم الفاتح (XONEPROO Style) ──
  static const _bgPage = Color(0xFFF5F6FA);
  static const _bgCard = Colors.white;
  static const _bgToolbar = Color(0xFF2C3E50);
  static const _accent = Color(0xFF3498DB);
  static const _textDark = Color(0xFF333333);
  static const _textGray = Color(0xFF999999);
  static const _textSubtle = Color(0xFF666666);
  static const _shadowColor = Color(0x14000000);
  static const _dividerColor = Color(0xFFE8E8E8);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgPage,
        appBar: _buildAppBar(),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _accent))
            : _errorMessage != null
                ? _buildErrorView()
                : _buildBody(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _bgToolbar,
      elevation: 2,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.settings, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            'إعدادات الشركة',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white70),
          tooltip: 'تحديث البيانات',
          onPressed: _loadCompanyData,
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Color(0xFFE74C3C)),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: GoogleFonts.cairo(color: _textGray, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadCompanyData,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: Text('إعادة المحاولة',
                style: GoogleFonts.cairo(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Tab Bar
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: _accent,
            unselectedLabelColor: _textGray,
            indicatorColor: _accent,
            indicatorWeight: 3,
            labelStyle: GoogleFonts.cairo(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.settings, size: 20), text: 'الإعدادات'),
              Tab(
                  icon: Icon(Icons.account_tree_rounded, size: 20),
                  text: 'الأقسام والمهام'),
              Tab(icon: Icon(Icons.location_on, size: 20), text: 'المراكز'),
              Tab(icon: Icon(Icons.message, size: 20), text: 'واتساب والتقارير'),
            ],
          ),
        ),
        const Divider(height: 1, color: _dividerColor),
        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: الإعدادات
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCompanyProfileCard(),
                    const SizedBox(height: 20),
                    _buildSubscriptionCard(),
                    const SizedBox(height: 20),
                    _buildQuickSettingsSection(),
                    const SizedBox(height: 20),
                    _buildSystemInfoCard(),
                  ],
                ),
              ),
              // Tab 2: الأقسام والمهام
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildDepartmentsSection(),
              ),
              // Tab 3: المراكز
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildCentersSection(),
              ),
              // Tab 4: واتساب والتقارير
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildReportSettingsSection(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompanyProfileCard() {
    final name = _companyData?['Name'] ?? _companyData?['name'] ?? 'غير متوفر';
    final code = _companyData?['Code'] ?? _companyData?['code'] ?? 'غير متوفر';
    final phone = _companyData?['Phone'] ?? _companyData?['phone'] ?? '';
    final email = _companyData?['Email'] ?? _companyData?['email'] ?? '';
    final address = _companyData?['Address'] ?? _companyData?['address'] ?? '';
    final city = _companyData?['City'] ?? _companyData?['city'] ?? '';
    final maxUsers =
        _companyData?['MaxUsers'] ?? _companyData?['maxUsers'] ?? 0;
    final isActive =
        _companyData?['IsActive'] ?? _companyData?['isActive'] ?? true;
    final logoUrl = _companyData?['LogoUrl'] ?? _companyData?['logoUrl'];

    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dividerColor, width: 1),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header with company logo and name
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                // Company Logo
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: _accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _accent.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: logoUrl != null && logoUrl.toString().isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            logoUrl.toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.business,
                              color: _accent,
                              size: 36,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.business,
                          color: _accent,
                          size: 36,
                        ),
                ),
                const SizedBox(width: 16),
                // Company Name & Code
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.toString(),
                        style: GoogleFonts.cairo(
                          color: _textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _accent.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              'كود: $code',
                              style: GoogleFonts.cairo(
                                color: _accent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isActive == true
                                  ? Colors.green.withOpacity(0.1)
                                  : Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActive == true
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.red.withOpacity(0.3),
                              ),
                            ),
                            child: Text(
                              isActive == true ? 'نشط' : 'معطّل',
                              style: GoogleFonts.cairo(
                                color: isActive == true
                                    ? Colors.green[300]
                                    : Colors.red[300],
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Company Details Grid
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                const Divider(color: _dividerColor, height: 1, thickness: 1),
                const SizedBox(height: 16),
                // Details in 2-column grid
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        Icons.phone,
                        'الهاتف',
                        phone.toString().isNotEmpty
                            ? phone.toString()
                            : 'غير محدد',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInfoItem(
                        Icons.email,
                        'البريد الإلكتروني',
                        email.toString().isNotEmpty
                            ? email.toString()
                            : 'غير محدد',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        Icons.location_on,
                        'العنوان',
                        address.toString().isNotEmpty
                            ? address.toString()
                            : 'غير محدد',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInfoItem(
                        Icons.location_city,
                        'المدينة',
                        city.toString().isNotEmpty
                            ? city.toString()
                            : 'غير محدد',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        Icons.people,
                        'الحد الأقصى للمستخدمين',
                        maxUsers.toString(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildInfoItem(
                        Icons.person,
                        'المستخدم الحالي',
                        widget.currentUsername,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _dividerColor,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: _accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.cairo(
                    color: _textGray,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.cairo(
                    color: _textDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    final daysRemaining =
        _companyData?['DaysRemaining'] ?? _companyData?['daysRemaining'] ?? 0;
    final isExpired =
        _companyData?['IsExpired'] ?? _companyData?['isExpired'] ?? false;
    final isExpiringSoon = _companyData?['IsExpiringSoon'] ??
        _companyData?['isExpiringSoon'] ??
        false;
    final subscriptionStatus = _companyData?['SubscriptionStatus'] ??
        _companyData?['subscriptionStatus'] ??
        'Active';
    final subscriptionStartDate = _companyData?['SubscriptionStartDate'] ??
        _companyData?['subscriptionStartDate'];
    final subscriptionEndDate = _companyData?['SubscriptionEndDate'] ??
        _companyData?['subscriptionEndDate'];

    // Determine status color
    Color statusColor;
    IconData statusIcon;
    String statusText;
    if (isExpired == true) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      statusText = 'منتهي';
    } else if (isExpiringSoon == true) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
      statusText = 'ينتهي قريباً';
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = 'نشط';
    }

    // Format dates
    String formatDate(dynamic dateStr) {
      if (dateStr == null) return 'غير محدد';
      try {
        final date = DateTime.parse(dateStr.toString());
        return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return dateStr.toString();
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Subscription Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.card_membership, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'حالة الاشتراك',
                    style: GoogleFonts.cairo(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Status Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusColor, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: GoogleFonts.cairo(
                          color: statusColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                const Divider(color: _dividerColor, height: 1, thickness: 1),
                const SizedBox(height: 16),

                // Days Remaining - Big Number
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withOpacity(0.15),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$daysRemaining',
                        style: GoogleFonts.cairo(
                          color: statusColor,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                      Text(
                        'يوم متبقي',
                        style: GoogleFonts.cairo(
                          color: _textSubtle,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Start & End Dates
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        Icons.event,
                        'بداية الاشتراك',
                        formatDate(subscriptionStartDate),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildInfoItem(
                        Icons.event_busy,
                        'نهاية الاشتراك',
                        formatDate(subscriptionEndDate),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== Departments Logic ====================

  Future<void> _loadDepartments() async {
    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null || companyId.isEmpty) return;

    setState(() => _isDepartmentsLoading = true);
    try {
      final response = await SadaraApiService.instance
          .get('/companies/$companyId/departments');
      if (!mounted) return;
      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _departments = List<Map<String, dynamic>>.from(
            (response['data'] as List).map((d) => Map<String, dynamic>.from(d)),
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading departments');
    } finally {
      if (mounted) setState(() => _isDepartmentsLoading = false);
    }
  }

  Future<void> _addDepartment() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _buildInputDialog(
        title: 'إضافة قسم جديد',
        hint: 'اسم القسم',
        controller: controller,
        icon: Icons.domain_add,
      ),
    );
    if (result == null || result.trim().isEmpty) return;

    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null) return;

    try {
      final response = await SadaraApiService.instance.post(
        '/companies/$companyId/departments',
        body: {'NameAr': result.trim()},
      );
      if (response['success'] == true) {
        DepartmentsDataService.instance.clearCache();
        _showSnack('تم إضافة القسم بنجاح');
        _loadDepartments();
      } else {
        _showSnack(response['message']?.toString() ?? 'فشل في إضافة القسم',
            isError: true);
      }
    } catch (e) {
      _showSnack('خطأ', isError: true);
    }
  }

  Future<void> _deleteDepartment(int deptId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('حذف القسم', style: GoogleFonts.cairo(color: _textDark)),
          content: Text('هل تريد حذف قسم "$name" وجميع مهامه؟',
              style: GoogleFonts.cairo(color: _textSubtle)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    Text('إلغاء', style: GoogleFonts.cairo(color: _textGray))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف', style: GoogleFonts.cairo(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null) return;

    try {
      final response = await SadaraApiService.instance
          .delete('/companies/$companyId/departments/$deptId');
      if (response['success'] == true) {
        DepartmentsDataService.instance.clearCache();
        _showSnack('تم حذف القسم بنجاح');
        _loadDepartments();
      } else {
        _showSnack(response['message']?.toString() ?? 'فشل في الحذف',
            isError: true);
      }
    } catch (e) {
      _showSnack('خطأ', isError: true);
    }
  }

  Future<void> _addTaskToDepartment(int deptId) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _buildInputDialog(
        title: 'إضافة مهمة جديدة',
        hint: 'اسم المهمة',
        controller: controller,
        icon: Icons.add_task,
      ),
    );
    if (result == null || result.trim().isEmpty) return;

    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null) return;

    try {
      final response = await SadaraApiService.instance.post(
        '/companies/$companyId/departments/$deptId/tasks',
        body: {'NameAr': result.trim()},
      );
      if (response['success'] == true) {
        DepartmentsDataService.instance.clearCache();
        _showSnack('تم إضافة المهمة بنجاح');
        _loadDepartments();
      } else {
        _showSnack(response['message']?.toString() ?? 'فشل في إضافة المهمة',
            isError: true);
      }
    } catch (e) {
      _showSnack('خطأ', isError: true);
    }
  }

  Future<void> _deleteTask(int deptId, int taskId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('حذف المهمة', style: GoogleFonts.cairo(color: _textDark)),
          content: Text('هل تريد حذف مهمة "$name"؟',
              style: GoogleFonts.cairo(color: _textSubtle)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    Text('إلغاء', style: GoogleFonts.cairo(color: _textGray))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف', style: GoogleFonts.cairo(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null) return;

    try {
      final response = await SadaraApiService.instance
          .delete('/companies/$companyId/departments/$deptId/tasks/$taskId');
      if (response['success'] == true) {
        DepartmentsDataService.instance.clearCache();
        _showSnack('تم حذف المهمة بنجاح');
        _loadDepartments();
      } else {
        _showSnack(response['message']?.toString() ?? 'فشل في الحذف',
            isError: true);
      }
    } catch (e) {
      _showSnack('خطأ', isError: true);
    }
  }

  Future<void> _seedDefaultDepartments() async {
    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('تهيئة الأقسام الافتراضية',
              style: GoogleFonts.cairo(color: _textDark)),
          content: Text(
            'سيتم إضافة 6 أقسام افتراضية مع مهامها:\nالصيانة، الحسابات، الفنيين، الوكلاء، الاتصالات، اللحام',
            style: GoogleFonts.cairo(color: _textSubtle),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    Text('إلغاء', style: GoogleFonts.cairo(color: _textGray))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('تهيئة', style: GoogleFonts.cairo(color: _accent)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    try {
      final response = await SadaraApiService.instance
          .post('/companies/$companyId/departments/seed-defaults');
      if (response['success'] == true) {
        DepartmentsDataService.instance.clearCache();
        _showSnack('تم تهيئة الأقسام الافتراضية بنجاح');
        _loadDepartments();
      } else {
        _showSnack(response['message']?.toString() ?? 'فشل', isError: true);
      }
    } catch (e) {
      _showSnack('خطأ', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.cairo()),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  Widget _buildInputDialog({
    required String title,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(icon, color: _accent, size: 24),
            const SizedBox(width: 10),
            Text(title,
                style: GoogleFonts.cairo(color: _textDark, fontSize: 18)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.cairo(color: _textDark),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.cairo(color: _textGray),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: _accent.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _accent),
              borderRadius: BorderRadius.circular(10),
            ),
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
          ),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: _textGray)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('إضافة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==================== Centers Logic ====================

  Future<void> _loadCenters() async {
    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null || companyId.isEmpty) return;

    setState(() => _isCentersLoading = true);
    try {
      final response =
          await SadaraApiService.instance.get('/companies/$companyId/centers');
      if (!mounted) return;
      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _centers = List<Map<String, dynamic>>.from(
            (response['data'] as List).map((d) => Map<String, dynamic>.from(d)),
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading centers');
    } finally {
      if (mounted) setState(() => _isCentersLoading = false);
    }
  }

  // ── إعدادات واتساب والتقارير (VPS Settings API) ──

  /// الحصول على tenantId (من widget أو VPS أو CustomAuth)
  String? get _resolvedTenantId =>
      widget.companyId ??
      VpsAuthService.instance.currentCompanyId ??
      CustomAuthService().currentTenantId;

  Future<void> _loadReportSettings() async {
    if (!mounted) return;
    setState(() => _isReportSettingsLoading = true);
    try {
      final tid = _resolvedTenantId;
      debugPrint('📥 تحميل إعدادات التقارير - tenantId: $tid');
      final settings = await CompanySettingsService.getSettings(tenantId: tid);
      if (mounted) {
        setState(() {
          _managerNameCtrl.text = settings.managerName ?? '';
          _managerWhatsAppCtrl.text = settings.managerWhatsApp ?? '';
          _receiveReports = settings.receiveReports;
          _bulkSendReport = settings.bulkSendReport;
          _dailyReport = settings.dailyReport;
          _weeklyReport = settings.weeklyReport;
          _fieldUsernameCtrl.text = settings.fieldUsername ?? '';
          _fieldPasswordCtrl.text = settings.fieldPassword ?? '';
        });
      }
    } catch (e) {
      debugPrint('⚠️ خطأ تحميل إعدادات التقارير');
    } finally {
      if (mounted) setState(() => _isReportSettingsLoading = false);
    }
  }

  Future<void> _saveReportSettings() async {
    final tid = _resolvedTenantId;
    if (tid == null) {
      _showSnack('لا يوجد معرّف شركة - تأكد من تسجيل الدخول');
      return;
    }

    if (!mounted) return;
    setState(() => _isReportSettingsSaving = true);
    try {
      final updated = CompanySettings(
        managerName: _managerNameCtrl.text.trim().isEmpty
            ? null
            : _managerNameCtrl.text.trim(),
        managerWhatsApp: _managerWhatsAppCtrl.text.trim().isEmpty
            ? null
            : _managerWhatsAppCtrl.text.trim(),
        receiveReports: _receiveReports,
        bulkSendReport: _bulkSendReport,
        dailyReport: _dailyReport,
        weeklyReport: _weeklyReport,
        fieldUsername: _fieldUsernameCtrl.text.trim().isEmpty
            ? null
            : _fieldUsernameCtrl.text.trim(),
        fieldPassword: _fieldPasswordCtrl.text.trim().isEmpty
            ? null
            : _fieldPasswordCtrl.text.trim(),
      );

      debugPrint('💾 حفظ إعدادات التقارير - tenantId: $tid');
      final ok = await CompanySettingsService.saveSettings(updated, tenantId: tid);

      if (mounted) {
        if (ok) {
          _showSnack('تم حفظ إعدادات التقارير بنجاح');
        } else {
          _showSnack('فشل في حفظ الإعدادات');
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack('فشل في حفظ الإعدادات');
      }
    } finally {
      if (mounted) setState(() => _isReportSettingsSaving = false);
    }
  }

  String _getSettingDescription(String key) {
    switch (key) {
      case 'manager_name':
        return 'اسم المدير';
      case 'manager_whatsapp':
        return 'رقم واتساب المدير';
      case 'receive_reports':
        return 'تفعيل استلام التقارير';
      case 'bulk_send_report':
        return 'تقرير بعد الإرسال الجماعي';
      case 'daily_report':
        return 'تقرير يومي';
      case 'weekly_report':
        return 'تقرير أسبوعي';
      default:
        return key;
    }
  }

  Widget _buildReportSettingsSection() {
    if (_isReportSettingsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // بطاقة معلومات المدير
        Container(
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _dividerColor),
            boxShadow: const [BoxShadow(color: _shadowColor, blurRadius: 10, offset: Offset(0, 2))],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.person, color: Colors.green, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text('معلومات المدير',
                        style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _managerNameCtrl,
                      decoration: InputDecoration(
                        labelText: 'اسم المدير',
                        labelStyle: GoogleFonts.cairo(),
                        prefixIcon: const Icon(Icons.badge_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _managerWhatsAppCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'رقم واتساب المدير',
                        labelStyle: GoogleFonts.cairo(),
                        hintText: '07xxxxxxxxx',
                        prefixIcon: const Icon(Icons.phone, color: Colors.green),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // بطاقة المستخدم الميداني
        Container(
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _dividerColor),
            boxShadow: const [BoxShadow(color: _shadowColor, blurRadius: 10, offset: Offset(0, 2))],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.engineering, color: Colors.blue, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('المستخدم الميداني',
                              style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
                          Text('يُستخدم لتسجيل الدخول التلقائي لنظام التذاكر',
                              style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey[600])),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _fieldUsernameCtrl,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: 'اسم المستخدم',
                        labelStyle: GoogleFonts.cairo(),
                        prefixIcon: const Icon(Icons.person_outline, color: Colors.blue),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _fieldPasswordCtrl,
                      textDirection: TextDirection.ltr,
                      obscureText: !_showFieldPassword,
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        labelStyle: GoogleFonts.cairo(),
                        prefixIcon: const Icon(Icons.lock_outline, color: Colors.blue),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _showFieldPassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.blue,
                          ),
                          onPressed: () => setState(() => _showFieldPassword = !_showFieldPassword),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // بطاقة إعدادات التقارير
        Container(
          decoration: BoxDecoration(
            color: _bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _dividerColor),
            boxShadow: const [BoxShadow(color: _shadowColor, blurRadius: 10, offset: Offset(0, 2))],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.assessment, color: Colors.orange, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text('إعدادات التقارير',
                        style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: _textDark)),
                  ],
                ),
              ),
              SwitchListTile(
                title: Text('استلام التقارير', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                subtitle: Text('تفعيل أو تعطيل إرسال التقارير للمدير', style: GoogleFonts.cairo(fontSize: 12)),
                value: _receiveReports,
                onChanged: (v) => setState(() => _receiveReports = v),
                activeColor: Colors.green,
              ),
              if (_receiveReports) ...[
                const Divider(height: 1, color: _dividerColor),
                SwitchListTile(
                  title: Text('تقرير الإرسال الجماعي', style: GoogleFonts.cairo()),
                  subtitle: Text('إرسال تقرير بعد كل عملية إرسال جماعي', style: GoogleFonts.cairo(fontSize: 12)),
                  value: _bulkSendReport,
                  onChanged: (v) => setState(() => _bulkSendReport = v),
                  activeColor: _accent,
                ),
                SwitchListTile(
                  title: Text('تقرير يومي', style: GoogleFonts.cairo()),
                  subtitle: Text('ملخص يومي للعمليات', style: GoogleFonts.cairo(fontSize: 12)),
                  value: _dailyReport,
                  onChanged: (v) => setState(() => _dailyReport = v),
                  activeColor: _accent,
                ),
                SwitchListTile(
                  title: Text('تقرير أسبوعي', style: GoogleFonts.cairo()),
                  subtitle: Text('ملخص أسبوعي للعمليات', style: GoogleFonts.cairo(fontSize: 12)),
                  value: _weeklyReport,
                  onChanged: (v) => setState(() => _weeklyReport = v),
                  activeColor: _accent,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // زر الحفظ
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isReportSettingsSaving ? null : _saveReportSettings,
            icon: _isReportSettingsSaving
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: Text(
              _isReportSettingsSaving ? 'جاري الحفظ...' : 'حفظ الإعدادات',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addCenter() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CenterFormDialog(),
    );
    if (result == null) return;

    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null) return;

    try {
      final response = await SadaraApiService.instance.post(
        '/companies/$companyId/centers',
        body: result,
      );
      if (response['success'] == true) {
        CentersDataService.instance.clearCache();
        _showSnack('تم إضافة المركز بنجاح');
        _loadCenters();
      } else {
        _showSnack(response['message']?.toString() ?? 'فشل في إضافة المركز',
            isError: true);
      }
    } catch (e) {
      _showSnack('خطأ', isError: true);
    }
  }

  Future<void> _editCenter(Map<String, dynamic> center) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _CenterFormDialog(center: center),
    );
    if (result == null) return;

    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    final centerId = center['id'] ?? center['Id'];
    if (companyId == null || centerId == null) return;

    try {
      final response = await SadaraApiService.instance.put(
        '/companies/$companyId/centers/$centerId',
        body: result,
      );
      if (response['success'] == true) {
        CentersDataService.instance.clearCache();
        _showSnack('تم تحديث المركز بنجاح');
        _loadCenters();
      } else {
        _showSnack(response['message']?.toString() ?? 'فشل في التحديث',
            isError: true);
      }
    } catch (e) {
      _showSnack('خطأ', isError: true);
    }
  }

  Future<void> _deleteCenter(int centerId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text('حذف المركز', style: GoogleFonts.cairo(color: _textDark)),
          content: Text('هل تريد حذف مركز "$name"؟',
              style: GoogleFonts.cairo(color: _textSubtle)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child:
                    Text('إلغاء', style: GoogleFonts.cairo(color: _textGray))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف', style: GoogleFonts.cairo(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    final companyId =
        widget.companyId ?? VpsAuthService.instance.currentCompanyId;
    if (companyId == null) return;

    try {
      final response = await SadaraApiService.instance
          .delete('/companies/$companyId/centers/$centerId');
      if (response['success'] == true) {
        CentersDataService.instance.clearCache();
        _showSnack('تم حذف المركز بنجاح');
        _loadCenters();
      } else {
        _showSnack(response['message']?.toString() ?? 'فشل في الحذف',
            isError: true);
      }
    } catch (e) {
      _showSnack('خطأ', isError: true);
    }
  }

  // ==================== Centers UI ====================

  Widget _buildCentersSection() {
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _dividerColor, width: 1),
        boxShadow: const [
          BoxShadow(color: _shadowColor, blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: _accent, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'مراكز الشركة ومواقعها',
                    style: GoogleFonts.cairo(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildActionChip(
                  label: 'إضافة مركز',
                  icon: Icons.add_location_alt,
                  color: _accent,
                  onTap: _addCenter,
                ),
              ],
            ),
          ),
          const Divider(color: _dividerColor, height: 1, thickness: 1),

          // Content
          if (_isCentersLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: _accent)),
            )
          else if (_centers.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.location_off,
                      size: 48, color: _textGray.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد مراكز بعد، أضف مركز جديد لتعيين الموظفين فيه',
                    style: GoogleFonts.cairo(color: _textGray, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _centers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _buildCenterCard(_centers[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildCenterCard(Map<String, dynamic> center) {
    final name = (center['Name'] ?? center['name'])?.toString() ?? 'غير مسمى';
    final description =
        (center['Description'] ?? center['description'])?.toString() ?? '';
    final lat = (center['Latitude'] ?? center['latitude'] ?? 0.0) as num;
    final lng = (center['Longitude'] ?? center['longitude'] ?? 0.0) as num;
    final radius =
        (center['RadiusMeters'] ?? center['radiusMeters'] ?? 200) as num;
    final isActive = (center['IsActive'] ?? center['isActive'] ?? true) as bool;
    final centerId = center['Id'] ?? center['id'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFF8F9FA) : const Color(0xFFFFF3F3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? _dividerColor : Colors.red.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          // Location icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isActive
                  ? _accent.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.location_on,
              color: isActive ? _accent : Colors.red,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: GoogleFonts.cairo(
                          color: _textDark,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'معطل',
                          style: GoogleFonts.cairo(
                              color: Colors.red, fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
                if (description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      description,
                      style:
                          GoogleFonts.cairo(color: _textSubtle, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.my_location,
                        size: 13, color: _textGray.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text(
                      '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                      style: GoogleFonts.cairo(
                        color: _textGray,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.circle_outlined,
                        size: 13, color: _textGray.withOpacity(0.7)),
                    const SizedBox(width: 4),
                    Text(
                      'نطاق: $radiusم',
                      style: GoogleFonts.cairo(color: _textGray, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => _editCenter(center),
                icon: const Icon(Icons.edit, color: _accent, size: 20),
                tooltip: 'تعديل',
                splashRadius: 18,
              ),
              IconButton(
                onPressed: () => _deleteCenter(centerId, name),
                icon: const Icon(Icons.delete_outline,
                    color: Colors.red, size: 20),
                tooltip: 'حذف',
                splashRadius: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== Departments UI ====================

  Widget _buildDepartmentsSection() {
    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _dividerColor,
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree, color: _accent, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'أقسام الشركة ومهامها',
                    style: GoogleFonts.cairo(
                      color: _textDark,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_departments.isEmpty && !_isDepartmentsLoading)
                  _buildActionChip(
                    label: 'تهيئة افتراضية',
                    icon: Icons.auto_fix_high,
                    color: Colors.purple,
                    onTap: _seedDefaultDepartments,
                  ),
                const SizedBox(width: 8),
                _buildActionChip(
                  label: 'إضافة قسم',
                  icon: Icons.add,
                  color: _accent,
                  onTap: _addDepartment,
                ),
              ],
            ),
          ),

          const Divider(color: _dividerColor, height: 1, thickness: 1),

          // Content
          if (_isDepartmentsLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: _accent)),
            )
          else if (_departments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.folder_off,
                      size: 48, color: _textGray.withOpacity(0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'لا توجد أقسام بعد، أضف قسم جديد أو استخدم التهيئة الافتراضية',
                    style: GoogleFonts.cairo(color: _textGray, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: _departments
                    .map((dept) => _buildDepartmentCard(dept))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.cairo(
                      color: color, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDepartmentCard(Map<String, dynamic> dept) {
    final deptId = dept['Id'] ?? dept['id'];
    final nameAr = dept['NameAr'] ?? dept['nameAr'] ?? 'غير مسمى';
    final tasks = List<Map<String, dynamic>>.from(
      ((dept['Tasks'] ?? dept['tasks'] ?? []) as List)
          .map((t) => Map<String, dynamic>.from(t)),
    );
    final isExpanded = _expandedDepartmentId == deptId;
    final isActive = dept['IsActive'] ?? dept['isActive'] ?? true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isExpanded ? _accent.withOpacity(0.4) : _dividerColor,
        ),
      ),
      child: Column(
        children: [
          // Department Header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() {
                _expandedDepartmentId = isExpanded ? null : deptId;
              }),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.folder, color: _accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nameAr,
                            style: GoogleFonts.cairo(
                              color: isActive == true ? _textDark : _textGray,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              decoration: isActive == true
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                          ),
                          Text(
                            '${tasks.length} مهمة',
                            style: GoogleFonts.cairo(
                                color: _textGray, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    // Add task button
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline,
                          color: _accent, size: 22),
                      tooltip: 'إضافة مهمة',
                      onPressed: () => _addTaskToDepartment(deptId),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    // Delete department button
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: Colors.red[300], size: 20),
                      tooltip: 'حذف القسم',
                      onPressed: () => _deleteDepartment(deptId, nameAr),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    // Expand/collapse
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: _textGray,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Expanded Tasks
          if (isExpanded)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(10)),
                ),
                child: tasks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'لا توجد مهام بعد',
                          style:
                              GoogleFonts.cairo(color: _textGray, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: tasks.map((task) {
                            final taskId = task['Id'] ?? task['id'];
                            final taskName =
                                task['NameAr'] ?? task['nameAr'] ?? '';
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F6FA),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _dividerColor),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.task_alt,
                                      color: _accent, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    taskName,
                                    style: GoogleFonts.cairo(
                                        color: _textDark, fontSize: 12),
                                  ),
                                  const SizedBox(width: 4),
                                  InkWell(
                                    onTap: () =>
                                        _deleteTask(deptId, taskId, taskName),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Icon(Icons.close,
                                        color: Colors.red[300], size: 14),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'إعدادات سريعة',
          style: GoogleFonts.cairo(
            color: _textDark,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        // Settings Grid
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildSettingsCard(
              icon: Icons.print,
              title: 'إعدادات الطابعة',
              subtitle: 'ضبط إعدادات الطباعة',
              color: Colors.blue,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrinterSettingsPage(),
                  ),
                );
              },
            ),
            _buildSettingsCard(
              icon: Icons.text_fields,
              title: 'حجم النص',
              subtitle: 'ضبط حجم النصوص في التطبيق',
              color: Colors.purple,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsTextScalePage(),
                  ),
                );
              },
            ),
            _buildSettingsCard(
              icon: Icons.notifications,
              title: 'إعدادات الإشعارات',
              subtitle: 'إدارة إشعارات واتساب',
              color: Colors.green,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SettingsPage(
                      currentUserRole: widget.currentUserRole,
                      currentUsername: widget.currentUsername,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    color: _textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.cairo(
                    color: _textGray,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemInfoCard() {
    final adminUserName =
        _companyData?['AdminUserName'] ?? _companyData?['adminUserName'];
    final createdAt = _companyData?['CreatedAt'] ?? _companyData?['createdAt'];
    final employeeCount =
        _companyData?['EmployeeCount'] ?? _companyData?['employeeCount'];

    String formatDate(dynamic dateStr) {
      if (dateStr == null) return 'غير محدد';
      try {
        final date = DateTime.parse(dateStr.toString());
        return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      } catch (_) {
        return dateStr.toString();
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _dividerColor,
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.cyan, size: 24),
                const SizedBox(width: 10),
                Text(
                  'معلومات النظام',
                  style: GoogleFonts.cairo(
                    color: _textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                const Divider(color: _dividerColor, height: 1, thickness: 1),
                const SizedBox(height: 12),
                _buildSystemInfoRow(
                    'الدور الحالي', widget.currentUserRole, Icons.badge),
                if (adminUserName != null)
                  _buildSystemInfoRow('مدير الشركة', adminUserName.toString(),
                      Icons.admin_panel_settings),
                if (employeeCount != null)
                  _buildSystemInfoRow(
                      'عدد الموظفين', employeeCount.toString(), Icons.group),
                if (createdAt != null)
                  _buildSystemInfoRow('تاريخ إنشاء الشركة',
                      formatDate(createdAt), Icons.calendar_today),
                _buildSystemInfoRow('إصدار التطبيق', '1.4.2', Icons.apps),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: Colors.cyan.withOpacity(0.7), size: 18),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: GoogleFonts.cairo(
              color: _textGray,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                color: _textDark,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Center Form Dialog ====================

class _CenterFormDialog extends StatefulWidget {
  final Map<String, dynamic>? center;
  const _CenterFormDialog({this.center});

  @override
  State<_CenterFormDialog> createState() => _CenterFormDialogState();
}

class _CenterFormDialogState extends State<_CenterFormDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _radiusCtrl = TextEditingController();
  bool _isActive = true;

  static const _accent = Color(0xFF3498DB);
  static const _textDark = Color(0xFF333333);
  static const _textGray = Color(0xFF999999);
  static const _bgCard = Colors.white;

  bool get _isEditing => widget.center != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final c = widget.center!;
      _nameCtrl.text = (c['Name'] ?? c['name'])?.toString() ?? '';
      _descCtrl.text = (c['Description'] ?? c['description'])?.toString() ?? '';
      _latCtrl.text = (c['Latitude'] ?? c['latitude'] ?? 0).toString();
      _lngCtrl.text = (c['Longitude'] ?? c['longitude'] ?? 0).toString();
      _radiusCtrl.text =
          (c['RadiusMeters'] ?? c['radiusMeters'] ?? 200).toString();
      _isActive = (c['IsActive'] ?? c['isActive'] ?? true) as bool;
    } else {
      _radiusCtrl.text = '200';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _radiusCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('اسم المركز مطلوب', style: GoogleFonts.cairo()),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('الإحداثيات يجب أن تكون أرقاماً صحيحة',
              style: GoogleFonts.cairo()),
          backgroundColor: Colors.red[700],
        ),
      );
      return;
    }

    final data = <String, dynamic>{
      'Name': _nameCtrl.text.trim(),
      'Description':
          _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      'Latitude': lat,
      'Longitude': lng,
      'RadiusMeters': double.tryParse(_radiusCtrl.text) ?? 200,
    };

    if (_isEditing) {
      data['IsActive'] = _isActive;
    }

    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: _bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(_isEditing ? Icons.edit_location : Icons.add_location_alt,
                color: _accent, size: 26),
            const SizedBox(width: 10),
            Text(
              _isEditing ? 'تعديل المركز' : 'إضافة مركز جديد',
              style: GoogleFonts.cairo(color: _textDark, fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildField(
                  label: 'اسم المركز *',
                  controller: _nameCtrl,
                  icon: Icons.business,
                  hint: 'مثال: المركز الرئيسي',
                ),
                const SizedBox(height: 12),
                _buildField(
                  label: 'الوصف',
                  controller: _descCtrl,
                  icon: Icons.description,
                  hint: 'وصف اختياري للمركز',
                ),
                const SizedBox(height: 16),
                // Coordinates section — map picker
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accent.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.map, color: _accent, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'موقع المركز',
                            style: GoogleFonts.cairo(
                              color: _accent,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            height: 32,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final result = await MapLocationPicker.show(
                                  context,
                                  initialLatitude:
                                      double.tryParse(_latCtrl.text),
                                  initialLongitude:
                                      double.tryParse(_lngCtrl.text),
                                );
                                if (result != null) {
                                  setState(() {
                                    _latCtrl.text =
                                        result.latitude.toStringAsFixed(6);
                                    _lngCtrl.text =
                                        result.longitude.toStringAsFixed(6);
                                  });
                                }
                              },
                              icon: const Icon(Icons.location_on, size: 16),
                              label: Text(
                                _latCtrl.text.isNotEmpty
                                    ? 'تغيير الموقع'
                                    : 'تحديد على الخريطة',
                                style: GoogleFonts.cairo(fontSize: 11),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_latCtrl.text.isNotEmpty &&
                          _lngCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _accent.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Colors.green, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'خط العرض: ${_latCtrl.text}',
                                style: GoogleFonts.cairo(
                                    color: _textDark, fontSize: 12),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                'خط الطول: ${_lngCtrl.text}',
                                style: GoogleFonts.cairo(
                                    color: _textDark, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text(
                          'انقر على "تحديد على الخريطة" لاختيار موقع المركز',
                          style:
                              GoogleFonts.cairo(color: _textGray, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildField(
                  label: 'نطاق الحضور (بالمتر)',
                  controller: _radiusCtrl,
                  icon: Icons.radar,
                  hint: '200',
                  isNumber: true,
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.toggle_on, color: _accent, size: 20),
                      const SizedBox(width: 8),
                      Text('حالة المركز:',
                          style: GoogleFonts.cairo(
                              color: _textDark, fontSize: 13)),
                      const Spacer(),
                      Switch(
                        value: _isActive,
                        activeColor: _accent,
                        onChanged: (v) => setState(() => _isActive = v),
                      ),
                      Text(
                        _isActive ? 'فعال' : 'معطل',
                        style: GoogleFonts.cairo(
                          color: _isActive ? Colors.green : Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo(color: _textGray)),
          ),
          ElevatedButton.icon(
            onPressed: _submit,
            icon: Icon(_isEditing ? Icons.save : Icons.add, size: 18),
            label: Text(
              _isEditing ? 'حفظ التغييرات' : 'إضافة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isNumber = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.cairo(
                color: _textDark, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          style: GoogleFonts.cairo(color: _textDark, fontSize: 13),
          keyboardType: isNumber
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.cairo(color: _textGray, fontSize: 12),
            prefixIcon: Icon(icon, color: _accent, size: 18),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: _accent.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _accent),
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
          ),
        ),
      ],
    );
  }
}
