import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import 'chart_of_accounts_page.dart';
import 'salaries_page.dart';
import 'collections_page.dart';
import 'expenses_page.dart';
import 'journal_entries_page.dart';
import 'compound_journal_entry_page.dart';
import 'revenue_page.dart';
import 'client_accounts_page.dart';
import 'statistics_page.dart';
import 'agent_commission_page.dart';
import 'agent_transactions_page.dart';
import '../super_admin/agents_management_page.dart';

/// لوحة المحاسبة الرئيسية
class AccountingDashboardPage extends StatefulWidget {
  final String? companyId;

  const AccountingDashboardPage({super.key, this.companyId});

  @override
  State<AccountingDashboardPage> createState() =>
      _AccountingDashboardPageState();
}

class _AccountingDashboardPageState extends State<AccountingDashboardPage> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _dashboardData;
  bool _sidebarExpanded = false;
  Timer? _autoCollapseTimer;

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await AccountingService.instance.getDashboard(
        companyId: widget.companyId,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        setState(() {
          _dashboardData =
              result['data'] is Map<String, dynamic> ? result['data'] : {};
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'خطأ في جلب البيانات';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'خطأ في الاتصال: $e';
        _isLoading = false;
      });
    }
  }

  // ── ألوان الثيم الفاتح (XONEPROO Style) ──
  static const _bgPage = Color(0xFFF5F6FA);
  static const _bgCard = Colors.white;
  static const _bgToolbar = Color(0xFF2C3E50);
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
        body: Column(
          children: [
            _buildPageToolbar(),
            Expanded(
              child: Row(
                children: [
                  // ═══ القائمة الجانبية ═══
                  _buildSidebar(),
                  // ═══ المحتوى الرئيسي ═══
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF3498DB)))
                        : _errorMessage != null
                            ? _buildErrorView()
                            : _buildContent(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    final expanded = _sidebarExpanded;
    final width = expanded ? 200.0 : 56.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
      decoration: BoxDecoration(
        color: _bgCard,
        border: const Border(
          left: BorderSide(color: _dividerColor, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // زر طي/فتح القائمة
          InkWell(
            onTap: () {
              _autoCollapseTimer?.cancel();
              setState(() => _sidebarExpanded = !_sidebarExpanded);
              if (_sidebarExpanded) {
                _autoCollapseTimer = Timer(const Duration(seconds: 3), () {
                  if (mounted && _sidebarExpanded) {
                    setState(() => _sidebarExpanded = false);
                  }
                });
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  AnimatedRotation(
                    turns: expanded ? 0.0 : 0.5,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.menu_open,
                        color: _bgToolbar, size: 20),
                  ),
                  if (expanded) ...[
                    const SizedBox(width: 8),
                    Text(
                      'القائمة',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _bgToolbar,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: _dividerColor),
          const SizedBox(height: 8),
          _sidebarBtn(
            icon: Icons.account_tree_rounded,
            label: 'شجرة الحسابات',
            color: const Color(0xFF3498DB),
            onTap: () =>
                _navigateTo(ChartOfAccountsPage(companyId: widget.companyId)),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _sidebarBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final expanded = _sidebarExpanded;
    return Tooltip(
      message: expanded ? '' : label,
      preferBelow: false,
      child: Padding(
        padding:
            EdgeInsets.symmetric(horizontal: expanded ? 8 : 6, vertical: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            hoverColor: color.withOpacity(0.08),
            splashColor: color.withOpacity(0.15),
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 10 : 0, vertical: 10),
              child: expanded
                  ? Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, color: color, size: 17),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            label,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _textDark,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_left, color: _textGray, size: 16),
                      ],
                    )
                  : Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 19),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _bgToolbar,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3498DB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.dashboard_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('الحسابات',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const Spacer(),
          IconButton(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE74C3C), size: 64),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(color: _textGray, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadDashboard,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: Text('إعادة المحاولة',
                style: GoogleFonts.cairo(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final screenSize = MediaQuery.of(context).size;
    final isCompact = screenSize.width < 600;
    final padding = isCompact ? 12.0 : 24.0;
    final spacing = isCompact ? 12.0 : 20.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 📊 بطاقات الإحصائيات (صف أفقي)
          _buildSummaryCards(),
          SizedBox(height: spacing),
          // عنوان الأقسام
          Text(
            'الأقسام',
            style: GoogleFonts.cairo(
              color: _textDark,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: spacing * 0.6),
          // الأقسام
          _buildSectionsGrid(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final data = _dashboardData ?? {};
    final collections = data['Collections'] as Map<String, dynamic>? ?? {};
    final expenses = data['Expenses'] as Map<String, dynamic>? ?? {};
    final salaries = data['Salaries'] as Map<String, dynamic>? ?? {};
    final journalEntries =
        data['JournalEntries'] as Map<String, dynamic>? ?? {};
    final accountBalances =
        data['AccountBalances'] as Map<String, dynamic>? ?? {};
    final pendingDetails =
        data['PendingDetails'] as Map<String, dynamic>? ?? {};

    final agentNet = (pendingDetails['AgentNet'] ?? 0) as num;
    final techNet = (pendingDetails['TechnicianNet'] ?? 0) as num;
    final agentIsDebtor = agentNet < 0;
    final techIsDebtor = techNet < 0;

    final items = <_SummaryItem>[
      _SummaryItem(
        title: 'رصيد الصندوق',
        value: _formatCurrency(accountBalances['CashAccountBalance']),
        icon: Icons.account_balance_wallet,
        color: const Color(0xFF3498DB),
      ),
      _SummaryItem(
        title: 'إجمالي المصروفات',
        value: _formatCurrency(accountBalances['TotalExpenses']),
        icon: Icons.trending_down,
        color: const Color(0xFFE74C3C),
      ),
      _SummaryItem(
        title: 'رواتب الشهر',
        value: _formatCurrency(salaries['MonthlyTotal']),
        icon: Icons.payments,
        color: const Color(0xFF1ABC9C),
      ),
      _SummaryItem(
        title: agentIsDebtor
            ? 'مستحقات الوكلاء (مديون)'
            : 'مستحقات الوكلاء (دائن)',
        value: _formatCurrency(agentNet.abs()),
        icon: Icons.support_agent,
        color:
            agentIsDebtor ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71),
      ),
      _SummaryItem(
        title:
            techIsDebtor ? 'مستحقات الفنيين (مديون)' : 'مستحقات الفنيين (دائن)',
        value: _formatCurrency(techNet.abs()),
        icon: Icons.engineering,
        color: techIsDebtor ? const Color(0xFF8E44AD) : const Color(0xFF27AE60),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = maxW > 1200
            ? 5
            : maxW > 900
                ? 4
                : maxW > 600
                    ? 3
                    : 2;
        final spacing = 16.0;
        final cardWidth = (maxW - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: items
              .map((item) => SizedBox(
                    width: cardWidth,
                    child: _buildCompactStatCard(item),
                  ))
              .toList(),
        );
      },
    );
  }

  /// بطاقة إحصائية بأسلوب XONEPROO - بيضاء مع أيقونة دائرية ملونة
  Widget _buildCompactStatCard(_SummaryItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // أيقونة دائرية ملونة
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: item.color,
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          // القيمة والعنوان
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    item.value,
                    style: GoogleFonts.cairo(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                // خط تقدم ملون
                Container(
                  height: 3,
                  width: 60,
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: _textGray,
                  ),
                ),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle!,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: _textSubtle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionsGrid() {
    final sections = [
      _SectionItem(
        title: 'القيود المحاسبية',
        subtitle: 'إنشاء ومراجعة القيود',
        icon: Icons.menu_book,
        color: const Color(0xFF2ECC71),
        onTap: () =>
            _navigateTo(JournalEntriesPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'قيد مركب',
        subtitle: 'إدخال قيد محاسبي مركب',
        icon: Icons.post_add,
        color: const Color(0xFF8E44AD),
        onTap: () =>
            _navigateTo(CompoundJournalEntryPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'الإيرادات',
        subtitle: 'تسجيل ومتابعة الإيرادات',
        icon: Icons.trending_up,
        color: const Color(0xFF1ABC9C),
        onTap: () => _navigateTo(RevenuePage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'حسابات العملاء',
        subtitle: 'إضافة وإدارة حسابات العملاء',
        icon: Icons.people,
        color: const Color(0xFF2196F3),
        onTap: () =>
            _navigateTo(ClientAccountsPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'الرواتب',
        subtitle: 'إدارة رواتب الموظفين',
        icon: Icons.payments,
        color: const Color(0xFFE91E63),
        onTap: () => _navigateTo(SalariesPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'تحصيلات الفنيين',
        subtitle: 'متابعة تحصيلات الفنيين',
        icon: Icons.engineering,
        color: const Color(0xFF9B59B6),
        onTap: () => _navigateTo(CollectionsPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'المصروفات',
        subtitle: 'تسجيل ومتابعة المصروفات',
        icon: Icons.receipt,
        color: const Color(0xFFE74C3C),
        onTap: () => _navigateTo(ExpensesPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'الإحصائيات',
        subtitle: 'تفاصيل الأرصدة والتقارير',
        icon: Icons.analytics,
        color: const Color(0xFF34495E),
        onTap: () => _navigateTo(StatisticsPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'عمولات الوكلاء',
        subtitle: 'نسب العمولة حسب الباقات',
        icon: Icons.percent,
        color: const Color(0xFF8E44AD),
        onTap: () =>
            _navigateTo(AgentCommissionPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'معاملات الوكلاء',
        subtitle: 'عرض جميع معاملات الوكلاء',
        icon: Icons.receipt_long,
        color: const Color(0xFF2980B9),
        onTap: () =>
            _navigateTo(AgentTransactionsPage(companyId: widget.companyId)),
      ),
      _SectionItem(
        title: 'إدارة الوكلاء',
        subtitle: 'إضافة وإدارة الوكلاء والمحاسبة',
        icon: Icons.support_agent,
        color: const Color(0xFF3F51B5),
        onTap: () => _navigateTo(const AgentsManagementPage()),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = maxW > 900
            ? 3
            : maxW > 500
                ? 2
                : 1;
        final spacing = 16.0;
        final cardWidth = (maxW - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              sections.map((s) => _buildSectionCard(s, cardWidth)).toList(),
        );
      },
    );
  }

  Widget _buildSectionCard(_SectionItem section, double width) {
    return InkWell(
      onTap: section.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: _shadowColor,
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // أيقونة دائرية ملونة
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: section.color,
                shape: BoxShape.circle,
              ),
              child: Icon(section.icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.title,
                    style: GoogleFonts.cairo(
                      color: _textDark,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    section.subtitle,
                    style: GoogleFonts.cairo(
                      color: _textGray,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_back_ios_new, color: _textGray, size: 14),
          ],
        ),
      ),
    );
  }

  void _navigateTo(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _loadDashboard();
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '0';
    final num n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    // تنسيق العدد بفاصلة الآلاف
    final abs = n.abs();
    final parts = abs.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(parts[i]);
    }
    return '${buffer.toString()} د.ع';
  }

  /// تنسيق مع إشارة (مديون/دائن)
  String _formatSignedCurrency(num value) {
    final formatted = _formatCurrency(value.abs());
    if (value < 0) return '-$formatted (مديون)';
    if (value > 0) return '+$formatted (دائن)';
    return formatted;
  }
}

class _SummaryItem {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  _SummaryItem({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _SectionItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  _SectionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
