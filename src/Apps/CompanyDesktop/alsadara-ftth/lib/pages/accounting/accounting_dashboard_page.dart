import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../services/permission_checker.dart';
import 'chart_of_accounts_page.dart';
import 'salaries_page.dart';
import 'collections_page.dart';
import 'expenses_page.dart';
import 'journal_entries_page.dart';
import 'compound_journal_entry_page.dart';
import 'revenue_page.dart';
import 'client_accounts_page.dart';
import 'statistics_page.dart';
import '../super_admin/agents_management_page.dart';
import 'ftth_operators_dashboard_page.dart';
import 'funds_overview_page.dart';
import 'fixed_expenses_page.dart';
import 'withdrawal_requests_page.dart';

/// لوحة المحاسبة الرئيسية
class AccountingDashboardPage extends StatefulWidget {
  final String? companyId;

  const AccountingDashboardPage({super.key, this.companyId});

  @override
  State<AccountingDashboardPage> createState() =>
      _AccountingDashboardPageState();
}

class _AccountingDashboardPageState extends State<AccountingDashboardPage>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _dashboardData;
  bool _sidebarExpanded = false;
  Timer? _autoCollapseTimer;

  // ── خلفية متحركة ──
  late final AnimationController _bgAnimController;
  late final AnimationController _particleController;
  final List<_FloatingShape> _shapes = [];

  // رموز محاسبية ومالية
  static const _symbols = [
    '\$',
    '٪',
    '¥',
    '€',
    '£',
    '₹',
    '﷼',
    '₿',
    '∑',
    '±',
    '📊',
    '💰',
    '💵',
    '🏦',
    '📈',
    '💳',
    '🧾',
    '📋',
    '🔢',
    '💲',
  ];

  void _initShapes() {
    final rng = Random();
    for (int i = 0; i < 35; i++) {
      _shapes.add(_FloatingShape(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: rng.nextDouble() * 26 + 24, // حجم الرمز 24-50
        speedX: (rng.nextDouble() - 0.5) * 0.25,
        speedY: (rng.nextDouble() - 0.5) * 0.25,
        opacity: rng.nextDouble() * 0.15 + 0.20, // 20-35% شفافية (خلف البطاقات)
        color: [
          const Color(0xFF3498DB),
          const Color(0xFF1ABC9C),
          const Color(0xFF9B59B6),
          const Color(0xFF2ECC71),
          const Color(0xFFE67E22),
          const Color(0xFF5C6BC0),
          const Color(0xFF2C3E50),
          const Color(0xFFE74C3C),
        ][rng.nextInt(8)],
        symbol: _symbols[rng.nextInt(_symbols.length)],
        rotation: rng.nextDouble() * 0.5 - 0.25, // دوران خفيف
        rotationSpeed: (rng.nextDouble() - 0.5) * 0.02,
      ));
    }
  }

  @override
  void dispose() {
    _autoCollapseTimer?.cancel();
    _bgAnimController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _bgAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _initShapes();
    _particleController.addListener(() {
      for (final s in _shapes) {
        s.x += s.speedX * 0.003;
        s.y += s.speedY * 0.003;
        s.rotation += s.rotationSpeed * 0.05;
        if (s.x < -0.08) s.x = 1.08;
        if (s.x > 1.08) s.x = -0.08;
        if (s.y < -0.08) s.y = 1.08;
        if (s.y > 1.08) s.y = -0.08;
      }
    });
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // جلب الداشبورد + قائمة الحسابات بالتوازي
      final results = await Future.wait([
        AccountingService.instance.getDashboard(companyId: widget.companyId),
        AccountingService.instance.getAccounts(companyId: widget.companyId),
      ]);
      if (!mounted) return;

      final result = results[0];
      final accountsResult = results[1];

      if (result['success'] == true) {
        final data = result['data'] is Map<String, dynamic>
            ? result['data']
            : <String, dynamic>{};

        // إدراج رصيد القاصة (11101) من قائمة الحسابات إذا لم يكن في الداشبورد
        final balances = data['AccountBalances'] as Map<String, dynamic>? ?? {};
        if (balances['CashRegisterBalance'] == null &&
            accountsResult['success'] == true) {
          final accounts = accountsResult['data'] as List? ?? [];
          for (final acct in accounts) {
            if (acct is Map && acct['Code']?.toString() == '11101') {
              balances['CashRegisterBalance'] = acct['CurrentBalance'] ?? 0;
              break;
            }
          }
          data['AccountBalances'] = balances;
        }

        setState(() {
          _dashboardData = data;
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
                    child: Stack(
                      children: [
                        // 1) خلفية متحركة (تدرج + موجات)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: _bgAnimController,
                            builder: (context, _) => CustomPaint(
                              painter: _BgGradientPainter(
                                animValue: _bgAnimController.value,
                              ),
                            ),
                          ),
                        ),
                        // 2) رموز محاسبية عائمة (خلف البطاقات)
                        Positioned.fill(
                          child: AnimatedBuilder(
                            animation: Listenable.merge(
                                [_bgAnimController, _particleController]),
                            builder: (context, _) => CustomPaint(
                              painter: _SymbolsPainter(
                                shapes: _shapes,
                              ),
                            ),
                          ),
                        ),
                        // 3) المحتوى (بطاقات + أزرار) - فوق الكل
                        _isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF3498DB)))
                            : _errorMessage != null
                                ? _buildErrorView()
                                : _buildContent(),
                      ],
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
            permKey: 'accounting.chart',
            onTap: () =>
                _navigateTo(ChartOfAccountsPage(companyId: widget.companyId)),
          ),
          _sidebarBtn(
            icon: Icons.menu_book,
            label: 'القيود المحاسبية',
            color: const Color(0xFF2ECC71),
            permKey: 'accounting.journals',
            onTap: () =>
                _navigateTo(JournalEntriesPage(companyId: widget.companyId)),
          ),
          _sidebarBtn(
            icon: Icons.payments,
            label: 'الرواتب',
            color: const Color(0xFFE91E63),
            permKey: 'accounting.salaries',
            onTap: () => _navigateTo(SalariesPage(companyId: widget.companyId)),
          ),
          _sidebarBtn(
            icon: Icons.analytics,
            label: 'الإحصائيات',
            color: const Color(0xFF34495E),
            permKey: 'accounting.statistics',
            onTap: () =>
                _navigateTo(StatisticsPage(companyId: widget.companyId)),
          ),
          _sidebarBtn(
            icon: Icons.receipt_long,
            label: 'المصاريف الثابتة',
            color: const Color(0xFFE67E22),
            permKey: 'accounting.fixed_expenses',
            onTap: () =>
                _navigateTo(FixedExpensesPage(companyId: widget.companyId)),
          ),
          _sidebarBtn(
            icon: Icons.money_off,
            label: 'طلبات السحب',
            color: const Color(0xFFE74C3C),
            permKey: 'accounting.withdrawals',
            onTap: () => _navigateTo(
                WithdrawalRequestsPage(companyId: widget.companyId)),
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
    String? permKey,
  }) {
    // V3: إخفاء العنصر إذا لا يملك صلاحية العرض
    if (permKey != null && !PermissionManager.instance.canView(permKey)) {
      return const SizedBox.shrink();
    }
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
      padding: EdgeInsets.only(
        left: padding,
        right: padding,
        top: 0,
        bottom: padding,
      ),
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
    final fixedExpenses = data['FixedExpenses'] as Map<String, dynamic>? ?? {};

    final agentNet = (pendingDetails['AgentNet'] ?? 0) as num;
    final techNet = (pendingDetails['TechnicianNet'] ?? 0) as num;
    final agentIsDebtor = agentNet < 0;
    final techIsDebtor = techNet < 0;

    // بيانات الرواتب
    final unpaidSalaries = salaries['UnpaidTotal'] ?? 0;
    final paidCount = salaries['PaidCount'] ?? 0;
    final pendingCount = salaries['PendingCount'] ?? 0;
    final totalEmployees = salaries['TotalEmployees'] ?? 0;
    final advances = data['Advances'] as Map<String, dynamic>? ?? {};

    final items = <_SummaryItem>[
      _SummaryItem(
        title: 'رصيد القاصة',
        value: _formatCurrency(accountBalances['CashRegisterBalance']),
        icon: Icons.point_of_sale,
        color: const Color(0xFF16A085),
      ),
      _SummaryItem(
        title: 'صندوق الشركة الرئيسي',
        value: _formatCurrency(accountBalances['MainCashBoxBalance']),
        icon: Icons.account_balance,
        color: const Color(0xFF2C3E50),
      ),
      _SummaryItem(
        title: 'رصيد الصفحة',
        value: _formatCurrency(accountBalances['PageBalance']),
        icon: Icons.account_balance_wallet,
        color: const Color(0xFF3498DB),
      ),
      _SummaryItem(
        title: 'المصاريف',
        value: _formatCurrency(accountBalances['TotalExpenses']),
        icon: Icons.trending_down,
        color: const Color(0xFFE74C3C),
      ),
      _SummaryItem(
        title: 'الالتزامات',
        value: _formatCurrency(accountBalances['TotalLiabilities']),
        icon: Icons.assignment_late,
        color: const Color(0xFFE67E22),
      ),
      _SummaryItem(
        title: 'رواتب غير مدفوعة',
        value: _formatCurrency(unpaidSalaries),
        subtitle: '$pendingCount معلق من $totalEmployees موظف',
        icon: Icons.payments_outlined,
        color: const Color(0xFFD32F2F),
      ),
      _SummaryItem(
        title: 'مستحقات المشغلين',
        value: _formatCurrency(accountBalances['OperatorReceivables']),
        icon: Icons.people,
        color: const Color(0xFF9B59B6),
      ),
      _SummaryItem(
        title: agentIsDebtor
            ? 'مستحقات الوكلاء (مدينون)'
            : 'مستحقات الوكلاء (دائن)',
        value: _formatCurrency(agentNet.abs()),
        icon: Icons.support_agent,
        color:
            agentIsDebtor ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71),
      ),
      _SummaryItem(
        title: techIsDebtor
            ? 'مستحقات الفنيين (مدينون)'
            : 'مستحقات الفنيين (دائن)',
        value: _formatCurrency(techNet.abs()),
        icon: Icons.engineering,
        color: techIsDebtor ? const Color(0xFF8E44AD) : const Color(0xFF27AE60),
      ),
      _SummaryItem(
        title: 'رواتب مدفوعة',
        value: '$paidCount',
        subtitle: 'من $totalEmployees موظف',
        icon: Icons.check_circle_outline,
        color: const Color(0xFF4CAF50),
      ),
      _SummaryItem(
        title: 'سلف مدفوعة',
        value: _formatCurrency(advances['TotalPaid']),
        subtitle: '${advances['Count'] ?? 0} سلفة هذا الشهر',
        icon: Icons.money_off,
        color: const Color(0xFFFF5722),
      ),
      _SummaryItem(
        title: 'إيجارات المكاتب',
        value: _formatCurrency(fixedExpenses['OfficeRent']),
        icon: Icons.business,
        color: const Color(0xFFE67E22),
      ),
      _SummaryItem(
        title: 'تكلفة المولد',
        value: _formatCurrency(fixedExpenses['GeneratorCost']),
        icon: Icons.flash_on,
        color: const Color(0xFFF39C12),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        // 5 أعمدة للشاشات الكبيرة، 4 للمتوسطة، 2 للصغيرة
        final cols = maxW > 1200
            ? 5
            : maxW > 800
                ? 4
                : maxW > 500
                    ? 3
                    : 2;
        final spacing = 10.0;
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
        border: Border.all(color: Colors.black, width: 1),
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
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: _textGray,
                    ),
                  ),
                ),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: item.color.withOpacity(0.7),
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
    final pm = PermissionManager.instance;
    final sections = <_SectionItem>[
      if (pm.canView('accounting.compound_journals'))
        _SectionItem(
          title: 'قيد مركب',
          subtitle: 'إدخال قيد محاسبي مركب',
          icon: Icons.post_add,
          color: const Color(0xFF8E44AD),
          onTap: () => _navigateTo(
              CompoundJournalEntryPage(companyId: widget.companyId)),
        ),
      if (pm.canView('accounting.expenses') ||
          pm.canView('accounting.revenue'))
        _SectionItem(
          title: 'المصاريف والإيرادات',
          subtitle: 'تسجيل ومتابعة المصاريف والإيرادات',
          icon: Icons.swap_horiz,
          color: const Color(0xFF1ABC9C),
          onTap: () => _showExpensesRevenueDialog(),
        ),
      if (pm.canView('accounting.client_accounts'))
        _SectionItem(
          title: 'حسابات العملاء',
          subtitle: 'إضافة وإدارة حسابات العملاء',
          icon: Icons.people,
          color: const Color(0xFF2196F3),
          onTap: () =>
              _navigateTo(ClientAccountsPage(companyId: widget.companyId)),
        ),
      if (pm.canView('accounting.collections'))
        _SectionItem(
          title: 'تحصيلات الفنيين',
          subtitle: 'متابعة تحصيلات الفنيين',
          icon: Icons.engineering,
          color: const Color(0xFF9B59B6),
          onTap: () =>
              _navigateTo(CollectionsPage(companyId: widget.companyId)),
        ),
      if (pm.canView('accounting.agent_transactions'))
        _SectionItem(
          title: 'إدارة الوكلاء',
          subtitle: 'إضافة وإدارة الوكلاء والمحاسبة',
          icon: Icons.support_agent,
          color: const Color(0xFF3F51B5),
          onTap: () => _navigateTo(
              AgentsManagementPage(companyId: widget.companyId)),
        ),
      if (pm.canView('accounting.ftth_operators'))
        _SectionItem(
          title: 'حسابات التفعيلات',
          subtitle: 'لوحة متابعة حسابات التفعيلات',
          icon: Icons.wifi_tethering,
          color: const Color(0xFF00897B),
          onTap: () => _navigateTo(
              FtthOperatorsDashboardPage(companyId: widget.companyId)),
        ),
      if (pm.canView('accounting.funds_overview'))
        _SectionItem(
          title: 'مراقبة الأموال',
          subtitle: 'أرصدة الصناديق والذمم والإيرادات',
          icon: Icons.account_balance,
          color: const Color(0xFF5C6BC0),
          onTap: () =>
              _navigateTo(FundsOverviewPage(companyId: widget.companyId)),
        ),
      if (pm.canView('accounting.withdrawals'))
        _SectionItem(
          title: 'طلبات سحب الأموال',
          subtitle: 'مراجعة وصرف طلبات السحب',
          icon: Icons.money_off,
          color: const Color(0xFFE74C3C),
          onTap: () => _navigateTo(
              WithdrawalRequestsPage(companyId: widget.companyId)),
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
          border: Border.all(color: Colors.black, width: 1),
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

  void _showExpensesRevenueDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: Text(
            'المصاريف والإيرادات',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _navigateTo(ExpensesPage(companyId: widget.companyId));
              },
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE74C3C).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.receipt,
                        color: Color(0xFFE74C3C), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('المصروفات',
                      style: GoogleFonts.cairo(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Divider(height: 1),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                _navigateTo(RevenuePage(companyId: widget.companyId));
              },
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1ABC9C).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.trending_up,
                        color: Color(0xFF1ABC9C), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text('الإيرادات',
                      style: GoogleFonts.cairo(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateTo(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _loadDashboard();
  }

  static final _currencyFmt = NumberFormat('#,##0', 'ar');

  String _formatCurrency(dynamic value) {
    if (value == null) return '0';
    final num n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return '${_currencyFmt.format(n.round())} د.ع';
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

// ── الأشكال العائمة (رموز محاسبية) ──
class _FloatingShape {
  double x, y;
  final double radius;
  final double speedX, speedY;
  final double opacity;
  final Color color;
  final String symbol;
  double rotation;
  final double rotationSpeed;

  _FloatingShape({
    required this.x,
    required this.y,
    required this.radius,
    required this.speedX,
    required this.speedY,
    required this.opacity,
    required this.color,
    required this.symbol,
    required this.rotation,
    required this.rotationSpeed,
  });
}

// ── رسام الخلفية (تدرج + موجات + توهج) ──
class _BgGradientPainter extends CustomPainter {
  final double animValue;
  _BgGradientPainter({required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xFFF5F6FA),
          Color(0xFFEEF1F8),
          Color(0xFFF0F4FF),
          Color(0xFFF5F6FA),
        ],
        stops: [
          0.0,
          (0.3 + 0.1 * _sin(animValue * 2 * _pi)).clamp(0.0, 1.0),
          (0.7 + 0.1 * _sin(animValue * 2 * _pi + 1)).clamp(0.0, 1.0),
          1.0,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final wavePaint = Paint()
      ..color = const Color(0x0A3498DB)
      ..style = PaintingStyle.fill;
    final wavePath = Path();
    wavePath.moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 1) {
      final y = size.height -
          40 -
          _sin((x / size.width * 2 * _pi) + animValue * 2 * _pi) * 12 -
          _sin((x / size.width * 4 * _pi) + animValue * 2 * _pi * 0.7) * 6;
      wavePath.lineTo(x, y);
    }
    wavePath.lineTo(size.width, size.height);
    wavePath.close();
    canvas.drawPath(wavePath, wavePaint);

    final wave2Paint = Paint()
      ..color = const Color(0x081ABC9C)
      ..style = PaintingStyle.fill;
    final wave2Path = Path();
    wave2Path.moveTo(0, size.height);
    for (double x = 0; x <= size.width; x += 1) {
      final y = size.height -
          20 -
          _sin((x / size.width * 3 * _pi) + animValue * 2 * _pi + 2) * 10 -
          _cos((x / size.width * 2 * _pi) + animValue * 2 * _pi * 0.5) * 5;
      wave2Path.lineTo(x, y);
    }
    wave2Path.lineTo(size.width, size.height);
    wave2Path.close();
    canvas.drawPath(wave2Path, wave2Paint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        center: Alignment(
          -0.7 + 0.2 * _sin(animValue * 2 * _pi),
          -0.8 + 0.15 * _cos(animValue * 2 * _pi),
        ),
        radius: 0.7,
        colors: const [Color(0x083498DB), Color(0x00FFFFFF)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), glowPaint);
  }

  static double _sin(double x) {
    x = x % (2 * _pi);
    double result = 0, term = x;
    for (int i = 1; i <= 7; i++) {
      result += term;
      term *= -x * x / ((2 * i) * (2 * i + 1));
    }
    return result;
  }

  static double _cos(double x) => _sin(x + _pi / 2);
  static const double _pi = 3.14159265358979;

  @override
  bool shouldRepaint(covariant _BgGradientPainter oldDelegate) => true;
}

// ── رسام الرموز العائمة (فوق البطاقات) ──
class _SymbolsPainter extends CustomPainter {
  final List<_FloatingShape> shapes;
  _SymbolsPainter({required this.shapes});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in shapes) {
      final cx = s.x * size.width;
      final cy = s.y * size.height;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(s.rotation);
      final tp = TextPainter(
        text: TextSpan(
          text: s.symbol,
          style: TextStyle(
            fontSize: s.radius,
            color: s.color.withOpacity(s.opacity),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SymbolsPainter oldDelegate) => true;
}
