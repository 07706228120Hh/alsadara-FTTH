/// 🏢 شاشة تفاصيل الشركة
/// تعرض معلومات الشركة وجميع الإجراءات المتاحة
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/api/auth/super_admin_api.dart';
import '../../services/api/api_client.dart';
import '../../services/api/api_config.dart';
import '../../services/departments_data_service.dart';
import '../../citizen_portal/citizen_portal.dart';
import 'edit_company_page.dart';
import '../../theme/energy_dashboard_theme.dart';
import '../home_page.dart';
import '../../multi_tenant.dart';
import 'permissions_management_v2_page.dart';
import '../../permissions/permissions.dart';

/// حالة الاشتراك
enum CompanyStatus {
  active,
  warning,
  critical,
  expired,
  suspended,
}

class CompanyDetailsPage extends StatefulWidget {
  final Company company;
  final bool isLinkedToCitizen;
  final VoidCallback onRefresh;

  const CompanyDetailsPage({
    super.key,
    required this.company,
    required this.isLinkedToCitizen,
    required this.onRefresh,
  });

  @override
  State<CompanyDetailsPage> createState() => _CompanyDetailsPageState();
}

class _CompanyDetailsPageState extends State<CompanyDetailsPage> {
  final SuperAdminApi _superAdminApi = SuperAdminApi();
  final ApiClient _apiClient = ApiClient.instance;
  late Company _company;
  late bool _isLinkedToCitizen;

  @override
  void initState() {
    super.initState();
    _company = widget.company;
    _isLinkedToCitizen = widget.isLinkedToCitizen;
  }

  @override
  void didUpdateWidget(CompanyDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.company.id != widget.company.id) {
      _company = widget.company;
      _isLinkedToCitizen = widget.isLinkedToCitizen;
    }
  }

  /// إعادة تحميل بيانات الشركة من API
  Future<void> _reloadCompanyData() async {
    try {
      final response = await _apiClient.get(
        '/internal/companies',
        (json) => (json as List).map((e) => Company.fromJson(e)).toList(),
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final updatedCompany = response.data!.firstWhere(
          (c) => c.id == _company.id,
          orElse: () => _company,
        );
        setState(() {
          _company = updatedCompany;
        });
      }
    } catch (e) {
      debugPrint('Error reloading company');
    }
  }

  /// الحصول على حالة الشركة
  CompanyStatus _getCompanyStatus() {
    if (!_company.isActive) return CompanyStatus.suspended;
    if (_company.isExpired) return CompanyStatus.expired;
    if (_company.daysRemaining <= 7) return CompanyStatus.critical;
    if (_company.daysRemaining <= 30) return CompanyStatus.warning;
    return CompanyStatus.active;
  }

  /// الحصول على لون الحالة
  Color _getStatusColor(CompanyStatus status) {
    switch (status) {
      case CompanyStatus.active:
        return const Color(0xFF10B981);
      case CompanyStatus.warning:
        return const Color(0xFFf7971e);
      case CompanyStatus.critical:
        return const Color(0xFFeb3349);
      case CompanyStatus.expired:
        return Colors.red;
      case CompanyStatus.suspended:
        return Colors.grey;
    }
  }

  /// الحصول على نص الحالة
  String _getStatusText(CompanyStatus status) {
    switch (status) {
      case CompanyStatus.active:
        return 'نشط';
      case CompanyStatus.warning:
        return 'تحذير';
      case CompanyStatus.critical:
        return 'حرج';
      case CompanyStatus.expired:
        return 'منتهي';
      case CompanyStatus.suspended:
        return 'معلق';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _getCompanyStatus();
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');
    final screenHeight = MediaQuery.of(context).size.height;
    final isCompact = screenHeight < 800;

    return Scaffold(
      backgroundColor: EnergyDashboardTheme.bgLight,
      appBar: _buildPremiumAppBar(statusColor, statusText, isCompact),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompact ? 16 : 24),
        child: Column(
          children: [
            // الصف الأول: معلومات الشركة + الاشتراك
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // بطاقة معلومات الشركة
                  Expanded(
                    flex: 3,
                    child: _buildCompactInfoCard(dateFormat, isCompact),
                  ),
                  SizedBox(width: isCompact ? 12 : 20),
                  // بطاقة الاشتراك
                  Expanded(
                    flex: 2,
                    child: _buildCompactSubscriptionCard(dateFormat, isCompact),
                  ),
                ],
              ),
            ),

            SizedBox(height: isCompact ? 16 : 24),

            // الصف الثاني: جميع الأزرار
            _buildAllActionsGrid(isCompact),
          ],
        ),
      ),
    );
  }

  /// AppBar فخم مع تصميم عصري
  PreferredSizeWidget _buildPremiumAppBar(
      Color statusColor, String statusText, bool isCompact) {
    return AppBar(
      backgroundColor: EnergyDashboardTheme.bgLightCard,
      elevation: 0,
      toolbarHeight: isCompact ? 60 : 70,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: EnergyDashboardTheme.bgLightCard,
          boxShadow: [
            BoxShadow(
              color: EnergyDashboardTheme.primary.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      leading: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Material(
          color: EnergyDashboardTheme.bgLightSurface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(12),
            child: const Icon(
              Icons.arrow_back_rounded,
              color: EnergyDashboardTheme.textDark,
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          // أيقونة الشركة مع تدرج
          Container(
            padding: EdgeInsets.all(isCompact ? 8 : 10),
            decoration: BoxDecoration(
              gradient: EnergyDashboardTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: EnergyDashboardTheme.glowShadow(
                  EnergyDashboardTheme.primary.withOpacity(0.5)),
            ),
            child: Icon(
              Icons.business_rounded,
              color: Colors.white,
              size: isCompact ? 18 : 22,
            ),
          ),
          const SizedBox(width: 14),
          // اسم الشركة
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _company.name,
                  style: TextStyle(
                    color: EnergyDashboardTheme.textDark,
                    fontSize: isCompact ? 15 : 17,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'كود: ${_company.code}',
                  style: TextStyle(
                    color: EnergyDashboardTheme.textMedium,
                    fontSize: isCompact ? 11 : 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // زر التصدير
        _buildPremiumExportButton(isCompact),
        const SizedBox(width: 10),
        // شارة الحالة
        _buildPremiumStatusBadge(statusColor, statusText, isCompact),
        const SizedBox(width: 16),
      ],
    );
  }

  /// زر تصدير فخم
  Widget _buildPremiumExportButton(bool isCompact) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _exportCompanyData,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 18,
            vertical: isCompact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            gradient: EnergyDashboardTheme.accentGradient,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: EnergyDashboardTheme.accent.withOpacity(0.5),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.file_download_outlined,
                color: Colors.white,
                size: isCompact ? 16 : 18,
              ),
              SizedBox(width: isCompact ? 6 : 8),
              Text(
                'تصدير',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: isCompact ? 12 : 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// شارة الحالة الفخمة
  Widget _buildPremiumStatusBadge(
      Color statusColor, String statusText, bool isCompact) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: isCompact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: statusColor.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: isCompact ? 11 : 13,
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقة معلومات الشركة المضغوطة
  Widget _buildCompactInfoCard(DateFormat dateFormat, bool isCompact) {
    const Color infoIconColor = EnergyDashboardTheme.primary;

    return Container(
      padding: EdgeInsets.all(isCompact ? 16 : 22),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgLightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: EnergyDashboardTheme.primary.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: EnergyDashboardTheme.primary.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // العنوان
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 8 : 10),
                decoration: BoxDecoration(
                  gradient: EnergyDashboardTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: infoIconColor.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(Icons.business_rounded,
                    color: Colors.white, size: isCompact ? 18 : 22),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Text(
                'معلومات الشركة',
                style: TextStyle(
                  color: EnergyDashboardTheme.textDark,
                  fontSize: isCompact ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_isLinkedToCitizen) ...[
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? 10 : 14,
                      vertical: isCompact ? 5 : 7),
                  decoration: BoxDecoration(
                    gradient: EnergyDashboardTheme.accentGradient,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: EnergyDashboardTheme.accent.withOpacity(0.5),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.link_rounded,
                          size: isCompact ? 14 : 16, color: Colors.white),
                      SizedBox(width: isCompact ? 5 : 7),
                      Text(
                        'مرتبطة بالمواطن',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isCompact ? 11 : 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          SizedBox(height: isCompact ? 14 : 20),

          // شبكة المعلومات بتصميم أفقي
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _buildInfoBox(
                    icon: Icons.badge_rounded,
                    label: 'الكود',
                    value: _company.code,
                    isCompact: isCompact,
                  ),
                ),
                SizedBox(width: isCompact ? 8 : 12),
                Expanded(
                  child: _buildInfoBox(
                    icon: Icons.email_rounded,
                    label: 'البريد',
                    value: _company.email ?? 'غير محدد',
                    isCompact: isCompact,
                  ),
                ),
                SizedBox(width: isCompact ? 8 : 12),
                Expanded(
                  child: _buildInfoBox(
                    icon: Icons.phone_rounded,
                    label: 'الهاتف',
                    value: _company.phone ?? 'غير محدد',
                    isCompact: isCompact,
                  ),
                ),
                SizedBox(width: isCompact ? 8 : 12),
                Expanded(
                  child: _buildInfoBox(
                    icon: Icons.calendar_today_rounded,
                    label: 'تاريخ الإنشاء',
                    value: dateFormat.format(_company.createdAt),
                    isCompact: isCompact,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// صندوق معلومات فردي
  Widget _buildInfoBox({
    required IconData icon,
    required String label,
    required String value,
    required bool isCompact,
  }) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            EnergyDashboardTheme.primary.withOpacity(0.12),
            EnergyDashboardTheme.primary.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: EnergyDashboardTheme.primary.withOpacity(0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: EnergyDashboardTheme.primary.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(isCompact ? 10 : 12),
            decoration: BoxDecoration(
              gradient: EnergyDashboardTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: EnergyDashboardTheme.primary.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, size: isCompact ? 20 : 24, color: Colors.white),
          ),
          SizedBox(height: isCompact ? 10 : 12),
          Text(
            label,
            style: TextStyle(
              color: EnergyDashboardTheme.textMedium,
              fontSize: isCompact ? 10 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: isCompact ? 4 : 6),
          Text(
            value,
            style: TextStyle(
              color: EnergyDashboardTheme.textDark,
              fontSize: isCompact ? 12 : 14,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// بطاقة الاشتراك المضغوطة - تصميم جديد
  Widget _buildCompactSubscriptionCard(DateFormat dateFormat, bool isCompact) {
    // ألوان بطاقات الاشتراك - تباين قوي بين الخلفية والنص
    const Color subscriptionBlue = Color(0xFFE0E7FF); // خلفية زرقاء فاتحة
    const Color subscriptionGreen = Color(0xFFD1FAE5); // خلفية خضراء فاتحة
    const Color blueText = Color(0xFF1E3A8A); // نص أزرق داكن جداً
    const Color greenText = Color(0xFF064E3B); // نص أخضر داكن جداً
    const Color orangeText = Color(0xFF9A3412); // برتقالي داكن جداً
    const Color redText = Color(0xFF991B1B); // أحمر داكن جداً

    return Container(
      padding: EdgeInsets.all(isCompact ? 16 : 22),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgLightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: EnergyDashboardTheme.accent.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: EnergyDashboardTheme.accent.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // العنوان
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 8 : 10),
                decoration: BoxDecoration(
                  gradient: EnergyDashboardTheme.accentGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: greenText.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(Icons.receipt_long_rounded,
                    color: Colors.white, size: isCompact ? 18 : 22),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Text(
                'الاشتراك',
                style: TextStyle(
                  color: EnergyDashboardTheme.textDark,
                  fontSize: isCompact ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          SizedBox(height: isCompact ? 16 : 20),

          // إحصائيات الاشتراك - Grid 2x2 بحجم ثابت
          Row(
            children: [
              // البداية
              Expanded(
                child: _buildSubscriptionStatCard(
                  icon: Icons.calendar_month_rounded,
                  label: 'البداية',
                  value: dateFormat.format(_company.subscriptionStartDate),
                  backgroundColor: subscriptionBlue,
                  foregroundColor: blueText,
                  isCompact: isCompact,
                ),
              ),
              SizedBox(width: isCompact ? 8 : 12),
              // النهاية
              Expanded(
                child: _buildSubscriptionStatCard(
                  icon: Icons.event_rounded,
                  label: 'النهاية',
                  value: dateFormat.format(_company.subscriptionEndDate),
                  backgroundColor: subscriptionGreen,
                  foregroundColor:
                      _company.daysRemaining <= 30 ? orangeText : greenText,
                  isCompact: isCompact,
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 10 : 12),
          Row(
            children: [
              // الأيام المتبقية
              Expanded(
                child: _buildSubscriptionStatCard(
                  icon: Icons.timer_rounded,
                  label: 'متبقي',
                  value: '${_company.daysRemaining} يوم',
                  backgroundColor: subscriptionGreen,
                  foregroundColor: _company.daysRemaining <= 7
                      ? redText
                      : _company.daysRemaining <= 30
                          ? orangeText
                          : greenText,
                  isCompact: isCompact,
                  showBadge: _company.daysRemaining <= 30,
                  badgeColor:
                      _company.daysRemaining <= 7 ? redText : orangeText,
                ),
              ),
              SizedBox(width: isCompact ? 8 : 12),
              // الموظفين
              Expanded(
                child: _buildSubscriptionStatCard(
                  icon: Icons.groups_rounded,
                  label: 'الموظفين',
                  value: '${_company.employeeCount}/${_company.maxUsers}',
                  backgroundColor: subscriptionBlue,
                  foregroundColor: _company.employeeCount >= _company.maxUsers
                      ? redText
                      : blueText,
                  isCompact: isCompact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// بطاقة إحصائية اشتراك بالتصميم الجديد
  Widget _buildSubscriptionStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color backgroundColor,
    required Color foregroundColor,
    required bool isCompact,
    bool showBadge = false,
    Color? badgeColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 16,
        vertical: isCompact ? 14 : 18,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: foregroundColor.withOpacity(0.45),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: foregroundColor.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: backgroundColor.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // أيقونة - بخلفية داكنة للتباين
          Container(
            padding: EdgeInsets.all(isCompact ? 10 : 12),
            decoration: BoxDecoration(
              color: foregroundColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: foregroundColor.withOpacity(0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: isCompact ? 20 : 24),
          ),
          SizedBox(width: isCompact ? 10 : 14),
          // النص
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: isCompact ? 12 : 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: isCompact ? 3 : 5),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: TextStyle(
                          color: foregroundColor,
                          fontSize: isCompact ? 15 : 17,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showBadge) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: badgeColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (badgeColor ?? foregroundColor)
                                  .withOpacity(0.7),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// شبكة جميع الأزرار - تصميم جديد منسق
  Widget _buildAllActionsGrid(bool isCompact) {
    // ألوان التصميم الفخم - أغمق وأكثر تبايناً
    const Color primaryBlue = EnergyDashboardTheme.primary;
    const Color lightBlue = Color(0xFF2563EB); // أغمق من 3B82F6
    const Color lightBlueBg = Color(0xFFA5D8FF); // أزرق أغمق
    const Color purple = Color(0xFF7C3AED);
    const Color purpleBg = Color(0xFFC4B5FD); // بنفسجي أغمق
    const Color green = Color(0xFF059669);
    const Color greenBg = Color(0xFF6EE7B7);
    const Color orange = Color(0xFFC2410C);
    const Color orangeLightBg = Color(0xFFFCD34D);
    const Color orangeBg = Color(0xFFFBBF24);
    const Color teal = Color(0xFF0F766E);
    const Color indigo = Color(0xFF4338CA);
    const Color indigoBg = Color(0xFF93C5FD); // نيلي أغمق
    const Color dangerRed = Color(0xFFDC2626);
    const Color dangerBg = Color(0xFFFCA5A5);
    const Color dangerBorder = Color(0xFFEF4444);

    return Container(
      padding: EdgeInsets.all(isCompact ? 18 : 26),
      decoration: BoxDecoration(
        color: EnergyDashboardTheme.bgLightCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: EnergyDashboardTheme.primary.withOpacity(0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: EnergyDashboardTheme.primary.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // عنوان القسم
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(isCompact ? 8 : 10),
                decoration: BoxDecoration(
                  gradient: EnergyDashboardTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: primaryBlue.withOpacity(0.5),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(Icons.settings_rounded,
                    color: Colors.white, size: isCompact ? 18 : 22),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Text(
                'الإجراءات',
                style: TextStyle(
                  color: EnergyDashboardTheme.textDark,
                  fontSize: isCompact ? 14 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 20 : 24),

          // الصف الأول: 4 أزرار
          Row(
            children: [
              Expanded(
                child: _buildNewActionButton(
                  icon: Icons.login_rounded,
                  label: 'الدخول للشركة',
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  onPressed: _enterAsCompany,
                  isCompact: isCompact,
                  isPrimary: true,
                ),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Expanded(
                child: _buildNewActionButton(
                  icon: Icons.people_rounded,
                  label: 'المستخدمين',
                  backgroundColor: indigoBg,
                  foregroundColor: indigo,
                  onPressed: _showCompanyUsers,
                  isCompact: isCompact,
                ),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Expanded(
                child: _buildNewActionButton(
                  icon: Icons.edit_rounded,
                  label: 'تعديل البيانات',
                  backgroundColor: lightBlueBg,
                  foregroundColor: lightBlue,
                  onPressed: _editCompany,
                  isCompact: isCompact,
                ),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Expanded(
                child: _buildNewActionButton(
                  icon: Icons.shield_rounded,
                  label: 'إدارة الصلاحيات',
                  backgroundColor: purpleBg,
                  foregroundColor: purple,
                  onPressed: _managePermissions,
                  isCompact: isCompact,
                ),
              ),
            ],
          ),

          SizedBox(height: isCompact ? 12 : 16),

          // الصف الثاني: 4 أزرار
          Row(
            children: [
              Expanded(
                child: _buildNewActionButton(
                  icon: Icons.autorenew_rounded,
                  label: 'تجديد الاشتراك',
                  backgroundColor: greenBg,
                  foregroundColor: green,
                  onPressed: _renewSubscription,
                  isCompact: isCompact,
                ),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Expanded(
                child: _buildNewActionButton(
                  icon: _isLinkedToCitizen
                      ? Icons.person_off_rounded
                      : Icons.person_add_alt_1_rounded,
                  label: _isLinkedToCitizen
                      ? 'إلغاء ربط المواطن'
                      : 'ربط بوابة المواطن',
                  backgroundColor: _isLinkedToCitizen
                      ? orangeLightBg
                      : const Color(0xFFE0F2F1),
                  foregroundColor: _isLinkedToCitizen ? orange : teal,
                  onPressed: _isLinkedToCitizen
                      ? _unlinkFromCitizenPortal
                      : _linkToCitizenPortal,
                  isCompact: isCompact,
                ),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              Expanded(
                child: _buildNewActionButton(
                  icon: _company.isActive
                      ? Icons.pause_circle_rounded
                      : Icons.play_circle_rounded,
                  label: _company.isActive ? 'تعطيل الشركة' : 'تفعيل الشركة',
                  backgroundColor: _company.isActive ? orangeBg : greenBg,
                  foregroundColor:
                      _company.isActive ? const Color(0xFFE65100) : green,
                  onPressed: _toggleCompanyStatus,
                  isCompact: isCompact,
                ),
              ),
              SizedBox(width: isCompact ? 10 : 14),
              // زر الحذف
              Expanded(
                child: _buildNewActionButton(
                  icon: Icons.delete_forever_rounded,
                  label: 'حذف الشركة',
                  backgroundColor: dangerBg,
                  foregroundColor: dangerRed,
                  onPressed: _deleteCompany,
                  isCompact: isCompact,
                  isDanger: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// زر إجراء بتصميم جديد ومنسق
  Widget _buildNewActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onPressed,
    required bool isCompact,
    bool isPrimary = false,
    bool isDanger = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        hoverColor: foregroundColor.withOpacity(0.35),
        splashColor: foregroundColor.withOpacity(0.25),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 14 : 18,
            vertical: isCompact ? 16 : 20,
          ),
          decoration: BoxDecoration(
            color: isPrimary ? null : backgroundColor,
            gradient: isPrimary ? EnergyDashboardTheme.primaryGradient : null,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDanger
                  ? foregroundColor.withOpacity(0.4)
                  : isPrimary
                      ? Colors.transparent
                      : foregroundColor.withOpacity(0.25),
              width: isDanger ? 2 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isPrimary
                    ? EnergyDashboardTheme.primary.withOpacity(0.35)
                    : foregroundColor.withOpacity(0.35),
                blurRadius: isPrimary ? 14 : 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // أيقونة - بخلفية داكنة للتباين
              Container(
                padding: EdgeInsets.all(isCompact ? 12 : 14),
                decoration: BoxDecoration(
                  color: isPrimary
                      ? Colors.white.withOpacity(0.3)
                      : foregroundColor,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: foregroundColor.withOpacity(0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: isPrimary ? Colors.white : Colors.white,
                  size: isCompact ? 24 : 28,
                ),
              ),
              SizedBox(height: isCompact ? 12 : 14),
              // النص
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? Colors.white : foregroundColor,
                  fontSize: isCompact ? 12 : 14,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// زر إجراء بالتصميم الجديد - أصغر ومتناسق
  Widget _buildStyledActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onPressed,
    required bool isCompact,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        hoverColor: foregroundColor.withOpacity(0.2),
        splashColor: foregroundColor.withOpacity(0.2),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 10 : 14,
            vertical: isCompact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: isPrimary ? null : backgroundColor,
            gradient: isPrimary ? EnergyDashboardTheme.primaryGradient : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary
                  ? Colors.transparent
                  : foregroundColor.withOpacity(0.2),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isPrimary
                    ? EnergyDashboardTheme.primary.withOpacity(0.5)
                    : Colors.black.withOpacity(0.2),
                blurRadius: isPrimary ? 10 : 4,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // أيقونة
              Container(
                padding: EdgeInsets.all(isCompact ? 7 : 9),
                decoration: BoxDecoration(
                  color: isPrimary
                      ? Colors.white.withOpacity(0.2)
                      : foregroundColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isPrimary ? Colors.white : foregroundColor,
                  size: isCompact ? 17 : 21,
                ),
              ),
              SizedBox(width: isCompact ? 8 : 12),
              // النص
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isPrimary ? Colors.white : foregroundColor,
                    fontSize: isCompact ? 11 : 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // إجراءات الشركة
  // ============================================

  /// تصدير بيانات الشركة
  Future<void> _exportCompanyData() async {
    final dateFormat = DateFormat('yyyy-MM-dd', 'ar');
    final exportData = '''
=== بيانات الشركة ===
الاسم: ${_company.name}
الكود: ${_company.code}
البريد: ${_company.email ?? 'غير محدد'}
الهاتف: ${_company.phone ?? 'غير محدد'}
المدينة: ${_company.city ?? 'غير محدد'}
العنوان: ${_company.address ?? 'غير محدد'}

=== الاشتراك ===
تاريخ البداية: ${dateFormat.format(_company.subscriptionStartDate)}
تاريخ النهاية: ${dateFormat.format(_company.subscriptionEndDate)}
الأيام المتبقية: ${_company.daysRemaining} يوم
عدد الموظفين: ${_company.employeeCount}/${_company.maxUsers}
الحالة: ${_company.isActive ? 'نشط' : 'معلق'}

=== معلومات إضافية ===
تاريخ الإنشاء: ${dateFormat.format(_company.createdAt)}
مرتبطة ببوابة المواطن: ${_isLinkedToCitizen ? 'نعم' : 'لا'}
''';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.file_download, color: Color(0xFF4CAF50)),
            SizedBox(width: 8),
            Text('تصدير البيانات'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SelectableText(
                  exportData,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'يمكنك نسخ النص أعلاه',
                        style: TextStyle(color: Colors.blue, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  /// عرض مستخدمي الشركة
  Future<void> _showCompanyUsers() async {
    await showDialog(
      context: context,
      builder: (context) => _CompanyUsersDialog(
        company: _company,
        apiClient: _apiClient,
      ),
    );
  }

  /// الدخول للشركة كمدير
  Future<void> _enterAsCompany() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.login, color: Color(0xFF1a237e)),
            SizedBox(width: 8),
            Text('الدخول للشركة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد الدخول لشركة "${_company.name}" كمدير؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ستحصل على جميع صلاحيات المدير',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.login),
            label: const Text('دخول'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1a237e),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // V2: منح جميع الصلاحيات للسوبر أدمن
      PermissionManager.instance.grantAll([
        'attendance',
        'agent',
        'tasks',
        'zones',
        'ai_search',
        'users_management',
        'reports',
        'settings',
        'dashboard',
        'tickets',
        'notifications',
        'maintenance',
        'users',
        'subscriptions',
        'accounts',
        'account_records',
        'export',
        'technicians',
        'transactions',
        'local_storage',
        'sadara_portal',
        'accounting',
        'diagnostics',
      ]);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => HomePage(
            username: 'Super Admin',
            permissions: 'مدير',
            department: _company.name,
            center: _company.code,
            salary: '0',
            tenantId: _company.id,
            tenantCode: _company.code,
            isSuperAdminMode: true,
          ),
        ),
        (route) => false,
      );
    }
  }

  /// تعديل الشركة
  void _editCompany() {
    final tenant = Tenant(
      id: _company.id,
      name: _company.name,
      code: _company.code,
      email: _company.email,
      phone: _company.phone,
      address: _company.address,
      city: _company.city,
      subscriptionStart: _company.subscriptionStartDate,
      subscriptionEnd: _company.subscriptionEndDate,
      subscriptionPlan: 'monthly',
      maxUsers: _company.maxUsers,
      isActive: _company.isActive,
      createdAt: _company.createdAt,
      createdBy: 'system',
      enabledFirstSystemFeatures: const {},
      enabledSecondSystemFeatures: const {},
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditCompanyPage(tenant: tenant),
      ),
    ).then((_) {
      widget.onRefresh();
      Navigator.pop(context);
    });
  }

  /// إدارة الصلاحيات
  void _managePermissions() async {
    // عرض خيارات إدارة الصلاحيات (V1 أو V2)
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.security_rounded, color: Color(0xFF9C27B0)),
            SizedBox(width: 8),
            Text('إدارة الصلاحيات'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // خيار V2 - الجديد
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star_rounded, color: Color(0xFF4CAF50)),
              ),
              title: const Text('صلاحيات V2 (مفصلة)'),
              subtitle:
                  const Text('تحكم دقيق بكل إجراء (عرض، إضافة، تعديل، حذف...)'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'جديد',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
              onTap: () => Navigator.pop(context, 'v2'),
            ),
            const Divider(),
            // خيار V1 - القديم
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.toggle_on_rounded, color: Colors.grey),
              ),
              title: const Text('صلاحيات V1 (بسيطة)'),
              subtitle: const Text('تفعيل/تعطيل الميزة بالكامل'),
              onTap: () => Navigator.pop(context, 'v1'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (choice == 'v2' && mounted) {
      // فتح صفحة إدارة الصلاحيات V2
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PermissionsManagementV2Page(
            companyId: _company.id,
            companyName: _company.name,
          ),
        ),
      );
      if (result == true) {
        await _reloadCompanyData();
        widget.onRefresh();
      }
    } else if (choice == 'v1' && mounted) {
      // فتح حوار إدارة الصلاحيات V1 القديم
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => _CompanyPermissionsDialog(company: _company),
      );
      if (result == true) {
        await _reloadCompanyData();
        widget.onRefresh();
      }
    }
  }

  /// حذف الشركة
  Future<void> _deleteCompany() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('حذف الشركة'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد حذف شركة "${_company.name}"؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'هذا الإجراء لا يمكن التراجع عنه!',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final response = await _superAdminApi.deleteCompany(_company.id);
      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حذف الشركة بنجاح')),
          );
          widget.onRefresh();
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message ?? 'حدث خطأ')),
          );
        }
      }
    }
  }

  /// تبديل حالة الشركة
  Future<void> _toggleCompanyStatus() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_company.isActive ? 'تعطيل الشركة' : 'تفعيل الشركة'),
        content: Text(
          _company.isActive
              ? 'هل تريد تعطيل شركة "${_company.name}"؟'
              : 'هل تريد تفعيل شركة "${_company.name}"؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _company.isActive ? Colors.orange : Colors.green,
            ),
            child: Text(_company.isActive ? 'تعطيل' : 'تفعيل'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final response = await _superAdminApi.toggleCompanyStatus(_company.id);
      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('تم ${_company.isActive ? "تعطيل" : "تفعيل"} الشركة'),
            ),
          );
          widget.onRefresh();
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message ?? 'حدث خطأ')),
          );
        }
      }
    }
  }

  /// تجديد الاشتراك
  Future<void> _renewSubscription() async {
    int? days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تجديد الاشتراك'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('تجديد اشتراك شركة "${_company.name}"'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildRenewOption(context, 30, 'شهر'),
                _buildRenewOption(context, 90, '3 أشهر'),
                _buildRenewOption(context, 180, '6 أشهر'),
                _buildRenewOption(context, 365, 'سنة'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (days != null && mounted) {
      final response =
          await _superAdminApi.renewSubscription(_company.id, days);
      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم تجديد الاشتراك بنجاح')),
          );
          widget.onRefresh();
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message ?? 'حدث خطأ')),
          );
        }
      }
    }
  }

  Widget _buildRenewOption(BuildContext context, int days, String label) {
    return ElevatedButton(
      onPressed: () => Navigator.pop(context, days),
      style: ElevatedButton.styleFrom(
        backgroundColor: EnergyDashboardTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }

  /// ربط بوابة المواطن
  Future<void> _linkToCitizenPortal() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link, color: Colors.teal),
            SizedBox(width: 8),
            Text('ربط بوابة المواطن'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('هل تريد ربط شركة "${_company.name}" ببوابة المواطن؟'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.teal),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم إلغاء ربط أي شركة أخرى مرتبطة حالياً',
                      style: TextStyle(color: Colors.teal),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.link),
            label: const Text('ربط'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await CompanyApiService.linkToCitizenPortal(_company.id);
        CitizenPortalHelper.clearCache();
        setState(() {
          _isLinkedToCitizen = true;
        });
        widget.onRefresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم ربط الشركة ببوابة المواطن')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ')),
          );
        }
      }
    }
  }

  /// إلغاء ربط بوابة المواطن
  Future<void> _unlinkFromCitizenPortal() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link_off, color: Colors.orange),
            SizedBox(width: 8),
            Text('إلغاء الربط'),
          ],
        ),
        content:
            Text('هل تريد إلغاء ربط شركة "${_company.name}" من بوابة المواطن؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.link_off),
            label: const Text('إلغاء الربط'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await CompanyApiService.unlinkFromCitizenPortal(_company.id);
        CitizenPortalHelper.clearCache();
        setState(() {
          _isLinkedToCitizen = false;
        });
        widget.onRefresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم إلغاء ربط الشركة من بوابة المواطن')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ')),
          );
        }
      }
    }
  }
}

// ============================================
// صندوق حوار إدارة صلاحيات الشركة
// ============================================

class _CompanyPermissionsDialog extends StatefulWidget {
  final Company company;

  const _CompanyPermissionsDialog({required this.company});

  @override
  State<_CompanyPermissionsDialog> createState() =>
      _CompanyPermissionsDialogState();
}

class _CompanyPermissionsDialogState extends State<_CompanyPermissionsDialog>
    with SingleTickerProviderStateMixin {
  final ApiClient _apiClient = ApiClient.instance;
  bool _isLoading = false;
  late TabController _tabController;

  late Map<String, bool> _firstSystemPermissions;
  late Map<String, bool> _secondSystemPermissions;

  final Map<String, Map<String, dynamic>> _firstSystemFeatures = {
    'attendance': {
      'label': 'الحضور والانصراف',
      'icon': Icons.access_time_rounded,
      'description': 'تسجيل حضور وانصراف الموظفين'
    },
    'agent': {
      'label': 'إدارة الوكلاء',
      'icon': Icons.support_agent_rounded,
      'description': 'إدارة وكلاء المبيعات'
    },
    'tasks': {
      'label': 'المهام',
      'icon': Icons.task_alt_rounded,
      'description': 'إدارة المهام والتكليفات'
    },
    'zones': {
      'label': 'المناطق',
      'icon': Icons.map_rounded,
      'description': 'تحديد مناطق العمل'
    },
    'ai_search': {
      'label': 'البحث الذكي',
      'icon': Icons.auto_awesome_rounded,
      'description': 'بحث بالذكاء الاصطناعي'
    },
  };

  final Map<String, Map<String, dynamic>> _secondSystemFeatures = {
    'dashboard': {
      'label': 'لوحة التحكم',
      'icon': Icons.dashboard_rounded,
      'description': 'عرض الإحصائيات الرئيسية'
    },
    'users': {
      'label': 'إدارة المستخدمين',
      'icon': Icons.people_rounded,
      'description': 'إدارة المشتركين والعملاء'
    },
    'subscriptions': {
      'label': 'الاشتراكات',
      'icon': Icons.card_membership_rounded,
      'description': 'إدارة باقات الاشتراك'
    },
    'tasks': {
      'label': 'المهام',
      'icon': Icons.assignment_rounded,
      'description': 'إدارة مهام الصيانة'
    },
    'zones': {
      'label': 'المناطق',
      'icon': Icons.location_on_rounded,
      'description': 'تحديد مناطق التغطية'
    },
    'accounts': {
      'label': 'الحسابات',
      'icon': Icons.account_balance_wallet_rounded,
      'description': 'إدارة الحسابات المالية'
    },
    'export': {
      'label': 'التصدير',
      'icon': Icons.file_download_rounded,
      'description': 'تصدير البيانات والتقارير'
    },
    'agents': {
      'label': 'الوكلاء',
      'icon': Icons.store_rounded,
      'description': 'إدارة نقاط البيع'
    },
    'whatsapp': {
      'label': 'واتساب',
      'icon': Icons.chat_rounded,
      'description': 'التكامل مع واتساب'
    },
    'technicians': {
      'label': 'الفنيين',
      'icon': Icons.engineering_rounded,
      'description': 'إدارة فريق الصيانة'
    },
    'transactions': {
      'label': 'المعاملات',
      'icon': Icons.receipt_long_rounded,
      'description': 'سجل المعاملات المالية'
    },
    'reports': {
      'label': 'التقارير',
      'icon': Icons.analytics_rounded,
      'description': 'تقارير الأداء والمبيعات'
    },
    'settings': {
      'label': 'الإعدادات',
      'icon': Icons.settings_rounded,
      'description': 'إعدادات النظام'
    },
    'notifications': {
      'label': 'الإشعارات',
      'icon': Icons.notifications_rounded,
      'description': 'إدارة الإشعارات'
    },
    'maintenance': {
      'label': 'الصيانة',
      'icon': Icons.build_rounded,
      'description': 'جدولة أعمال الصيانة'
    },
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCurrentPermissions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadCurrentPermissions() {
    _firstSystemPermissions = {
      for (var key in _firstSystemFeatures.keys) key: true,
    };

    _secondSystemPermissions = {
      for (var key in _secondSystemFeatures.keys) key: true,
    };

    if (widget.company.enabledFirstSystemFeatures != null &&
        widget.company.enabledFirstSystemFeatures!.isNotEmpty) {
      final features = widget.company.enabledFirstSystemFeatures!;
      for (var key in _firstSystemPermissions.keys) {
        if (features.containsKey(key)) {
          _firstSystemPermissions[key] = features[key] == true;
        }
      }
    }

    if (widget.company.enabledSecondSystemFeatures != null &&
        widget.company.enabledSecondSystemFeatures!.isNotEmpty) {
      final features = widget.company.enabledSecondSystemFeatures!;
      for (var key in _secondSystemPermissions.keys) {
        if (features.containsKey(key)) {
          _secondSystemPermissions[key] = features[key] == true;
        }
      }
    }
  }

  Future<void> _savePermissions() async {
    setState(() => _isLoading = true);

    try {
      final response = await _apiClient.put(
        '/internal/companies/${widget.company.id}/permissions',
        {
          'enabledFirstSystemFeatures': _firstSystemPermissions,
          'enabledSecondSystemFeatures': _secondSystemPermissions,
        },
        (json) => json,
        useInternalKey: true,
      );

      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم حفظ الصلاحيات بنجاح')),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message ?? 'حدث خطأ')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 700,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.security_rounded,
                      color: Colors.purple, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إدارة صلاحيات الشركة',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.company.name,
                        style: TextStyle(
                          color: EnergyDashboardTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TabBar(
              controller: _tabController,
              labelColor: EnergyDashboardTheme.primaryColor,
              unselectedLabelColor: EnergyDashboardTheme.textMuted,
              indicatorColor: EnergyDashboardTheme.primaryColor,
              tabs: const [
                Tab(text: 'النظام الرئيسي'),
                Tab(text: 'نظام FTTH'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPermissionsGrid(
                      _firstSystemFeatures, _firstSystemPermissions, true),
                  _buildPermissionsGrid(
                      _secondSystemFeatures, _secondSystemPermissions, false),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _savePermissions,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('حفظ الصلاحيات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EnergyDashboardTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsGrid(Map<String, Map<String, dynamic>> features,
      Map<String, bool> permissions, bool isFirstSystem) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: features.length,
      itemBuilder: (context, index) {
        final key = features.keys.elementAt(index);
        final feature = features[key]!;
        final isEnabled = permissions[key] ?? true;

        return InkWell(
          onTap: () {
            setState(() {
              permissions[key] = !isEnabled;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isEnabled
                  ? EnergyDashboardTheme.primaryColor.withOpacity(0.2)
                  : EnergyDashboardTheme.backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isEnabled
                    ? EnergyDashboardTheme.primaryColor.withOpacity(0.5)
                    : EnergyDashboardTheme.borderColor,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  feature['icon'] as IconData,
                  color: isEnabled
                      ? EnergyDashboardTheme.primaryColor
                      : EnergyDashboardTheme.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    feature['label'] as String,
                    style: TextStyle(
                      color: isEnabled
                          ? EnergyDashboardTheme.textPrimary
                          : EnergyDashboardTheme.textMuted,
                      fontSize: 12,
                      fontWeight:
                          isEnabled ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: (value) {
                    setState(() {
                      permissions[key] = value;
                    });
                  },
                  activeColor: EnergyDashboardTheme.primaryColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================
// صندوق حوار مستخدمي الشركة
// ============================================

class _CompanyUsersDialog extends StatefulWidget {
  final Company company;
  final ApiClient apiClient;

  const _CompanyUsersDialog({
    required this.company,
    required this.apiClient,
  });

  @override
  State<_CompanyUsersDialog> createState() => _CompanyUsersDialogState();
}

class _CompanyUsersDialogState extends State<_CompanyUsersDialog> {
  List<CompanyUser> _users = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // محاولة جلب البيانات من API
      final response = await widget.apiClient.get(
        ApiConfig.internalCompanyEmployees(widget.company.id),
        (json) => json,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final List<dynamic> usersJson = response.data is List
            ? response.data
            : (response.data['data'] ?? response.data['users'] ?? []);

        setState(() {
          _users = usersJson.map((json) => CompanyUser.fromJson(json)).toList();
          _isLoading = false;
        });
      } else {
        // إذا فشل، جرب endpoint بديل
        final altResponse = await widget.apiClient.get(
          '/superadmin/companies/${widget.company.id}/users',
          (json) => json,
          useInternalKey: true,
        );

        if (altResponse.isSuccess && altResponse.data != null) {
          final List<dynamic> usersJson = altResponse.data is List
              ? altResponse.data
              : (altResponse.data['data'] ?? altResponse.data['users'] ?? []);

          setState(() {
            _users =
                usersJson.map((json) => CompanyUser.fromJson(json)).toList();
            _isLoading = false;
          });
        } else {
          // عرض رسالة الخطأ مع معلومات أكثر
          setState(() {
            _error = 'هذه الميزة تحتاج تفعيل API المستخدمين على الخادم\n\n'
                'Endpoint: ${ApiConfig.internalCompanyEmployees(widget.company.id)}\n'
                'الرسالة: ${response.message ?? "غير مصرح"}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _error = 'فشل الاتصال بالخادم';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // العنوان
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3F51B5).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.people_rounded,
                      color: Color(0xFF3F51B5), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مستخدمي ${widget.company.name}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_users.length} مستخدم من ${widget.company.maxUsers}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _loadUsers,
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'تحديث',
                ),
                // زر إضافة مستخدم
                FilledButton.icon(
                  onPressed: _users.length >= widget.company.maxUsers
                      ? null
                      : _addNewUser,
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('إضافة مستخدم'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const Divider(height: 24),
            // المحتوى
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: Colors.red.shade300),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  style: TextStyle(color: Colors.red.shade700)),
                              const SizedBox(height: 12),
                              ElevatedButton.icon(
                                onPressed: _loadUsers,
                                icon: const Icon(Icons.refresh),
                                label: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        )
                      : _users.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_off_rounded,
                                      size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 12),
                                  Text('لا يوجد مستخدمين',
                                      style: TextStyle(
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _users.length,
                              itemBuilder: (context, index) {
                                final user = _users[index];
                                return _buildUserCard(user);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(CompanyUser user) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: user.isActive
              ? const Color(0xFF4CAF50).withOpacity(0.2)
              : Colors.grey.withOpacity(0.2),
          child: Icon(
            Icons.person_rounded,
            color: user.isActive ? const Color(0xFF4CAF50) : Colors.grey,
          ),
        ),
        title: Row(
          children: [
            Text(
              user.fullName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: user.isActive
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                user.isActive ? 'نشط' : 'معطل',
                style: TextStyle(
                  fontSize: 10,
                  color: user.isActive
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFF44336),
                ),
              ),
            ),
            if (user.role != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  user.role!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(user.username,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 16),
                if (user.email != null) ...[
                  const Icon(Icons.email_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(user.email!,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // زر الصلاحيات
            IconButton(
              onPressed: () => _managePermissions(user),
              icon:
                  const Icon(Icons.security_rounded, color: Color(0xFF9C27B0)),
              tooltip: 'الصلاحيات',
            ),
            // زر تعديل
            IconButton(
              onPressed: () => _editUser(user),
              icon: const Icon(Icons.edit_rounded, color: Color(0xFF2196F3)),
              tooltip: 'تعديل',
            ),
            // زر كلمة المرور
            IconButton(
              onPressed: () => _showPassword(user),
              icon: const Icon(Icons.key_rounded, color: Color(0xFFFF9800)),
              tooltip: 'كلمة المرور',
            ),
          ],
        ),
      ),
    );
  }

  /// إدارة صلاحيات المستخدم
  Future<void> _managePermissions(CompanyUser user) async {
    // عرض خيارات إدارة الصلاحيات (V1 أو V2)
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.security_rounded, color: Color(0xFF9C27B0)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('صلاحيات ${user.fullName}',
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // خيار V2 - الجديد
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.star_rounded, color: Color(0xFF4CAF50)),
              ),
              title: const Text('صلاحيات V2 (مفصلة)'),
              subtitle:
                  const Text('تحكم دقيق بكل إجراء (عرض، إضافة، تعديل، حذف...)'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'جديد',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
              onTap: () => Navigator.pop(context, 'v2'),
            ),
            const Divider(),
            // خيار V1 - القديم
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.toggle_on_rounded, color: Colors.grey),
              ),
              title: const Text('صلاحيات V1 (بسيطة)'),
              subtitle: const Text('تفعيل/تعطيل الميزة بالكامل'),
              onTap: () => Navigator.pop(context, 'v1'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (choice == 'v2' && mounted) {
      // فتح صفحة إدارة الصلاحيات V2 للموظف
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PermissionsManagementV2Page(
            companyId: widget.company.id,
            companyName: widget.company.name,
            employeeId: user.id,
            employeeName: user.fullName,
          ),
        ),
      );
      if (result == true) {
        _loadUsers();
      }
      return;
    } else if (choice != 'v1') {
      return; // المستخدم ألغى الاختيار
    }

    // ==================== V1 Logic (الكود القديم) ====================
    final apiClient = ApiClient.instance;

    // جلب صلاحيات الشركة المتاحة (نظام FTTH)
    Map<String, bool> companyFeatures = {};

    // تحليل صلاحيات الشركة من النظام الثاني (FTTH)
    try {
      final features = widget.company.enabledSecondSystemFeatures;
      if (features != null) {
        for (var entry in features.entries) {
          companyFeatures[entry.key] = entry.value == true;
        }
      }
    } catch (e) {
      debugPrint('Error parsing company features');
    }

    // قائمة الصلاحيات المتاحة مع الأسماء العربية
    final availablePermissions = {
      'dashboard': 'لوحة التحكم',
      'users': 'إدارة المستخدمين',
      'subscriptions': 'الاشتراكات',
      'tasks': 'المهام',
      'zones': 'المناطق',
      'accounts': 'الحسابات',
      'export': 'التصدير',
      'agents': 'الوكلاء',
      'whatsapp': 'واتساب',
      'technicians': 'الفنيين',
      'transactions': 'المعاملات',
      'reports': 'التقارير',
      'settings': 'الإعدادات',
      'notifications': 'الإشعارات',
      'maintenance': 'الصيانة',
    };

    // تهيئة صلاحيات المستخدم من البيانات الحالية
    Map<String, bool> userPermissions = {};
    for (var key in availablePermissions.keys) {
      userPermissions[key] = false;
    }

    // تحميل صلاحيات المستخدم الحالية
    if (user.secondSystemPermissions != null) {
      try {
        final perms = user.secondSystemPermissions!;
        for (var entry in perms.entries) {
          if (availablePermissions.containsKey(entry.key)) {
            userPermissions[entry.key] = entry.value == true;
          }
        }
      } catch (e) {
        debugPrint('Error parsing user permissions');
      }
    }

    bool isSaving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF9C27B0).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.security_rounded,
                    color: Color(0xFF9C27B0)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('صلاحيات ${user.fullName}'),
                    Text(
                      'تحديد الصلاحيات المتاحة للمستخدم',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // تنبيه
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFE0B2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Color(0xFFFF9800), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'يمكن منح الموظف فقط الصلاحيات المفعّلة للشركة',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // قائمة الصلاحيات
                Expanded(
                  child: ListView(
                    children: availablePermissions.entries.map((entry) {
                      final key = entry.key;
                      final label = entry.value;
                      final isCompanyEnabled = companyFeatures[key] ?? false;
                      final isUserEnabled = userPermissions[key] ?? false;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isCompanyEnabled
                              ? Colors.white
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isCompanyEnabled
                                ? (isUserEnabled
                                    ? const Color(0xFF4CAF50)
                                    : Colors.grey.shade300)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: isUserEnabled,
                          onChanged: isCompanyEnabled
                              ? (value) {
                                  setDialogState(() {
                                    userPermissions[key] = value ?? false;
                                  });
                                }
                              : null,
                          title: Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: isCompanyEnabled
                                  ? EnergyDashboardTheme.textPrimary
                                  : EnergyDashboardTheme.textMuted,
                            ),
                          ),
                          subtitle: !isCompanyEnabled
                              ? const Text(
                                  'غير مفعّل للشركة',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.red,
                                  ),
                                )
                              : null,
                          secondary: Icon(
                            _getPermissionIcon(key),
                            color: isCompanyEnabled
                                ? (isUserEnabled
                                    ? const Color(0xFF4CAF50)
                                    : Colors.grey)
                                : Colors.grey.shade300,
                          ),
                          activeColor: const Color(0xFF4CAF50),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.trailing,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // أزرار سريعة
            TextButton.icon(
              onPressed: () {
                setDialogState(() {
                  for (var key in availablePermissions.keys) {
                    if (companyFeatures[key] == true) {
                      userPermissions[key] = true;
                    }
                  }
                });
              },
              icon: const Icon(Icons.check_box_rounded, size: 18),
              label: const Text('تحديد الكل'),
            ),
            TextButton.icon(
              onPressed: () {
                setDialogState(() {
                  for (var key in availablePermissions.keys) {
                    userPermissions[key] = false;
                  }
                });
              },
              icon: const Icon(Icons.check_box_outline_blank, size: 18),
              label: const Text('إلغاء الكل'),
            ),
            const SizedBox(width: 16),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);

                      try {
                        // حفظ الصلاحيات في API
                        final response = await apiClient.put(
                          '/internal/companies/${widget.company.id}/employees/${user.id}/permissions',
                          {'secondSystemPermissions': userPermissions},
                          (json) => json,
                          useInternalKey: true,
                        );

                        if (context.mounted) {
                          Navigator.pop(context, response.isSuccess);
                          if (response.isSuccess) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم حفظ الصلاحيات بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(response.message ?? 'حدث خطأ'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9C27B0),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    // إعادة تحميل المستخدمين بعد الحفظ
    if (result == true) {
      _loadUsers();
    }
  }

  IconData _getPermissionIcon(String key) {
    switch (key) {
      case 'dashboard':
        return Icons.dashboard_rounded;
      case 'users':
        return Icons.people_rounded;
      case 'subscriptions':
        return Icons.card_membership_rounded;
      case 'tasks':
        return Icons.task_alt_rounded;
      case 'zones':
        return Icons.map_rounded;
      case 'accounts':
        return Icons.account_balance_wallet_rounded;
      case 'export':
        return Icons.download_rounded;
      case 'agents':
        return Icons.support_agent_rounded;
      case 'whatsapp':
        return Icons.chat_rounded;
      case 'technicians':
        return Icons.engineering_rounded;
      case 'transactions':
        return Icons.receipt_long_rounded;
      case 'reports':
        return Icons.analytics_rounded;
      case 'settings':
        return Icons.settings_rounded;
      case 'notifications':
        return Icons.notifications_rounded;
      case 'maintenance':
        return Icons.build_rounded;
      case 'attendance':
        return Icons.access_time_rounded;
      case 'agent':
        return Icons.person_pin_rounded;
      case 'ai_search':
        return Icons.search_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  Map<String, dynamic>? _parseJson(String jsonStr) {
    try {
      return Map<String, dynamic>.from(
          (jsonStr.isNotEmpty) ? _decodeJson(jsonStr) : {});
    } catch (e) {
      return null;
    }
  }

  dynamic _decodeJson(String jsonStr) {
    // Simple JSON parser for basic objects
    if (jsonStr.isEmpty || jsonStr == '{}') return {};
    try {
      // Remove whitespace and parse
      jsonStr = jsonStr.trim();
      if (!jsonStr.startsWith('{')) return {};

      final result = <String, dynamic>{};
      // Remove braces
      jsonStr = jsonStr.substring(1, jsonStr.length - 1);
      if (jsonStr.isEmpty) return result;

      // Split by comma (simple implementation)
      final pairs = jsonStr.split(',');
      for (var pair in pairs) {
        final parts = pair.split(':');
        if (parts.length == 2) {
          var key = parts[0].trim().replaceAll('"', '').replaceAll("'", '');
          var value = parts[1].trim();
          if (value == 'true') {
            result[key] = true;
          } else if (value == 'false') {
            result[key] = false;
          } else {
            result[key] = value.replaceAll('"', '').replaceAll("'", '');
          }
        }
      }
      return result;
    } catch (e) {
      return {};
    }
  }

  /// عرض/تغيير كلمة المرور
  Future<void> _showPassword(CompanyUser user) async {
    final passwordController = TextEditingController();
    bool showNewPassword = false;
    bool isChanging = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.key_rounded, color: Color(0xFFFF9800)),
              const SizedBox(width: 8),
              Text('كلمة مرور ${user.fullName}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // تنبيه أمني
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFE0B2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security_rounded,
                        size: 20, color: Color(0xFFFF9800)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'كلمات المرور مشفرة ولا يمكن عرضها.\nيمكنك فقط تعيين كلمة مرور جديدة.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // تغيير كلمة المرور
              const Text(
                'تعيين كلمة مرور جديدة:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: !showNewPassword,
                decoration: InputDecoration(
                  hintText: 'كلمة المرور الجديدة (6 أحرف على الأقل)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setDialogState(() => showNewPassword = !showNewPassword);
                    },
                    icon: Icon(
                      showNewPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: isChanging
                  ? null
                  : () async {
                      if (passwordController.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('أدخل كلمة المرور الجديدة')),
                        );
                        return;
                      }
                      if (passwordController.text.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'كلمة المرور يجب أن تكون 6 أحرف على الأقل')),
                        );
                        return;
                      }

                      setDialogState(() => isChanging = true);

                      try {
                        final response = await widget.apiClient.patch(
                          ApiConfig.internalEmployeePassword(
                              widget.company.id, user.id),
                          {'NewPassword': passwordController.text},
                          (json) => json,
                          useInternalKey: true,
                        );

                        if (response.isSuccess) {
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تغيير كلمة المرور بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadUsers();
                          }
                        } else {
                          setDialogState(() => isChanging = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(response.message ??
                                    'فشل في تغيير كلمة المرور'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() => isChanging = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isChanging
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// تعديل بيانات المستخدم
  Future<void> _editUser(CompanyUser user) async {
    final nameController = TextEditingController(text: user.fullName);
    final emailController = TextEditingController(text: user.email ?? '');
    final phoneController = TextEditingController(text: user.phone ?? '');
    bool isActive = user.isActive;
    bool isSaving = false;

    // جلب الأقسام من API ديناميكياً
    List<String> departments =
        await DepartmentsDataService.instance.fetchDepartments();
    String? selectedDepartment =
        departments.contains(user.department) ? user.department : null;

    final roles = [
      {'value': 'Employee', 'label': 'موظف'},
      {'value': 'Viewer', 'label': 'مشاهد'},
      {'value': 'Technician', 'label': 'فني'},
      {'value': 'TechnicalLeader', 'label': 'ليدر'},
      {'value': 'Manager', 'label': 'مدير'},
      {'value': 'CompanyAdmin', 'label': 'مدير الشركة'},
    ];
    String selectedRole =
        (user.role != null && roles.any((r) => r['value'] == user.role))
            ? user.role!
            : 'Employee';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit_rounded, color: Color(0xFF2196F3)),
              const SizedBox(width: 8),
              Text('تعديل ${user.fullName}'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'الاسم الكامل',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: 'البريد الإلكتروني',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedDepartment,
                  decoration: InputDecoration(
                    labelText: 'القسم',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.business_outlined),
                  ),
                  items: departments
                      .map((d) => DropdownMenuItem<String>(
                            value: d,
                            child: Text(d),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedDepartment = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: InputDecoration(
                    labelText: 'الدور',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
                  ),
                  items: roles
                      .map((role) => DropdownMenuItem<String>(
                            value: role['value'],
                            child: Text(role['label']!),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedRole = value ?? 'Employee');
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('الحالة'),
                  subtitle: Text(isActive ? 'نشط' : 'معطل'),
                  value: isActive,
                  onChanged: (value) {
                    setDialogState(() => isActive = value);
                  },
                  activeColor: const Color(0xFF4CAF50),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);

                      try {
                        final response = await widget.apiClient.put(
                          ApiConfig.internalEmployeeById(
                              widget.company.id, user.id),
                          {
                            'fullName': nameController.text,
                            'email': emailController.text,
                            'phone': phoneController.text,
                            'isActive': isActive,
                            'department': selectedDepartment ?? '',
                            'role': selectedRole,
                          },
                          (json) => json,
                          useInternalKey: true,
                        );

                        if (response.isSuccess) {
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تحديث بيانات المستخدم بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadUsers();
                          }
                        } else {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(response.message ??
                                    'فشل في تحديث البيانات'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('حفظ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// إضافة مستخدم جديد
  Future<void> _addNewUser() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final departmentController = TextEditingController();
    final centerController = TextEditingController();
    final salaryController = TextEditingController();
    String selectedRole = 'Employee';
    bool isSaving = false;

    final roles = [
      {'value': 'Employee', 'label': 'موظف'},
      {'value': 'Viewer', 'label': 'مشاهد'},
      {'value': 'Technician', 'label': 'فني'},
      {'value': 'TechnicalLeader', 'label': 'ليدر'},
      {'value': 'Manager', 'label': 'مدير'},
      {'value': 'CompanyAdmin', 'label': 'مدير الشركة'},
    ];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_add_rounded,
                    color: Color(0xFF4CAF50)),
              ),
              const SizedBox(width: 12),
              const Text('إضافة مستخدم جديد'),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // معلومات أساسية
                  const Text('المعلومات الأساسية',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2196F3),
                      )),
                  const SizedBox(height: 12),
                  // الاسم الكامل (مطلوب)
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'الاسم الكامل *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.person_outline),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // رقم الهاتف (مطلوب)
                  TextField(
                    controller: phoneController,
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف * (للدخول)',
                      hintText: '05xxxxxxxx',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.phone_outlined),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  // كلمة المرور
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: 'كلمة المرور',
                      hintText: 'اتركه فارغاً للقيمة الافتراضية (123456)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  // البريد الإلكتروني
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      labelText: 'البريد الإلكتروني (اختياري)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.email_outlined),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  // الدور الوظيفي
                  const Text('الدور الوظيفي',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2196F3),
                      )),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
                    decoration: InputDecoration(
                      labelText: 'الدور *',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.badge_outlined),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    items: roles
                        .map((role) => DropdownMenuItem<String>(
                              value: role['value'],
                              child: Text(role['label']!),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setDialogState(() => selectedRole = value ?? 'Employee');
                    },
                  ),
                  const SizedBox(height: 16),
                  // معلومات إضافية
                  const Text('معلومات إضافية (اختياري)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF9E9E9E),
                      )),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: departmentController,
                          decoration: InputDecoration(
                            labelText: 'القسم',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.business_outlined),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: centerController,
                          decoration: InputDecoration(
                            labelText: 'المركز',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: salaryController,
                    decoration: InputDecoration(
                      labelText: 'الراتب',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.attach_money_outlined),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: isSaving
                  ? null
                  : () async {
                      // التحقق من الحقول المطلوبة
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى إدخال الاسم الكامل'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      if (phoneController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('يرجى إدخال رقم الهاتف'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSaving = true);

                      try {
                        final response = await widget.apiClient.post(
                          ApiConfig.internalCompanyEmployees(widget.company.id),
                          {
                            'fullName': nameController.text.trim(),
                            'phoneNumber': phoneController.text.trim(),
                            'email': emailController.text.trim().isNotEmpty
                                ? emailController.text.trim()
                                : null,
                            'password': passwordController.text.isNotEmpty
                                ? passwordController.text
                                : null,
                            'role': selectedRole,
                            'department':
                                departmentController.text.trim().isNotEmpty
                                    ? departmentController.text.trim()
                                    : null,
                            'center': centerController.text.trim().isNotEmpty
                                ? centerController.text.trim()
                                : null,
                            'salary': salaryController.text.trim().isNotEmpty
                                ? salaryController.text.trim()
                                : null,
                          },
                          (json) => json,
                          useInternalKey: true,
                        );

                        if (response.isSuccess) {
                          if (mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم إضافة المستخدم بنجاح'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _loadUsers();
                          }
                        } else {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(response.message ??
                                    'فشل في إضافة المستخدم'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              icon: isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.person_add_rounded),
              label: const Text('إضافة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// نموذج مستخدم الشركة
// ============================================

class CompanyUser {
  final String id;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String? role;
  final String? department;
  final String? password;
  final bool isActive;
  final DateTime? createdAt;
  final Map<String, dynamic>? firstSystemPermissions;
  final Map<String, dynamic>? secondSystemPermissions;

  CompanyUser({
    required this.id,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    this.role,
    this.department,
    this.password,
    required this.isActive,
    this.createdAt,
    this.firstSystemPermissions,
    this.secondSystemPermissions,
  });

  factory CompanyUser.fromJson(Map<String, dynamic> json) {
    return CompanyUser(
      id: (json['id'] ?? json['Id'] ?? json['userId'] ?? json['UserId'])
              ?.toString() ??
          '',
      username: json['username'] ??
          json['Username'] ??
          json['userName'] ??
          json['UserName'] ??
          '',
      fullName: json['fullName'] ??
          json['FullName'] ??
          json['name'] ??
          json['Name'] ??
          '',
      email: json['email'] ?? json['Email'],
      phone: json['phone'] ??
          json['Phone'] ??
          json['phoneNumber'] ??
          json['PhoneNumber'],
      role:
          json['role'] ?? json['Role'] ?? json['jobTitle'] ?? json['JobTitle'],
      department: json['department'] ?? json['Department'],
      password: json['password'] ?? json['Password'],
      isActive: json['isActive'] ?? json['IsActive'] ?? true,
      createdAt: json['createdAt'] != null || json['CreatedAt'] != null
          ? DateTime.tryParse(
              (json['createdAt'] ?? json['CreatedAt']).toString())
          : null,
      firstSystemPermissions: _parsePermissions(
          json['firstSystemPermissions'] ?? json['FirstSystemPermissions']),
      secondSystemPermissions: _parsePermissions(
          json['secondSystemPermissions'] ?? json['SecondSystemPermissions']),
    );
  }

  static Map<String, dynamic>? _parsePermissions(dynamic value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(value));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
