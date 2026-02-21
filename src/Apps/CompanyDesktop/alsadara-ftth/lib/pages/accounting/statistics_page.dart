import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';
import 'chart_of_accounts_page.dart';

/// صفحة الإحصائيات - داشبورد محاسبي شامل
class StatisticsPage extends StatefulWidget {
  final String? companyId;

  const StatisticsPage({super.key, this.companyId});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _dashboardData;
  Map<String, dynamic>? _fundsData;
  List<dynamic>? _accountsList;

  // الألوان
  static const _bgPage = Color(0xFFF5F6FA);
  static const _bgCard = Colors.white;
  static const _bgToolbar = Color(0xFF2C3E50);
  static const _textDark = Color(0xFF333333);
  static const _textGray = Color(0xFF999999);
  static const _dividerColor = Color(0xFFE8E8E8);
  static const _shadowColor = Color(0x14000000);

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        AccountingService.instance.getDashboard(companyId: widget.companyId),
        AccountingService.instance.getAccounts(companyId: widget.companyId),
        AccountingService.instance.getFundsOverview(companyId: widget.companyId),
      ]);

      if (!mounted) return;

      final dashResult = results[0];
      final accountsResult = results[1];
      final fundsResult = results[2];

      if (dashResult['success'] == true) {
        final data = dashResult['data'] is Map<String, dynamic>
            ? dashResult['data']
            : <String, dynamic>{};

        // إدراج رصيد القاصة (11101)
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
          _accountsList = accountsResult['success'] == true
              ? (accountsResult['data'] as List? ?? [])
              : [];
          _fundsData = fundsResult['success'] == true
              ? (fundsResult['data'] is Map<String, dynamic>
                  ? fundsResult['data']
                  : {})
              : {};
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = dashResult['message'] ?? 'خطأ في جلب البيانات';
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgPage,
        body: Column(
          children: [
            _buildToolbar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF3498DB)))
                  : _errorMessage != null
                      ? _buildErrorView()
                      : _buildDashboard(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
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
              color: const Color(0xFF34495E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.dashboard_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('لوحة الإحصائيات المالية',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const Spacer(),
          // زر شجرة الحسابات
          _toolbarButton(
            icon: Icons.account_tree_rounded,
            label: 'شجرة الحسابات',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ChartOfAccountsPage(companyId: widget.companyId),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.white.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              color: Color(0xFFE74C3C), size: 64),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: const TextStyle(color: _textGray, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadAllData,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: Text('إعادة المحاولة',
                style: GoogleFonts.cairo(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final data = _dashboardData ?? {};
    final collections = data['Collections'] as Map<String, dynamic>? ?? {};
    final expenses = data['Expenses'] as Map<String, dynamic>? ?? {};
    final salaries = data['Salaries'] as Map<String, dynamic>? ?? {};
    final accountBalances =
        data['AccountBalances'] as Map<String, dynamic>? ?? {};
    final pendingDetails =
        data['PendingDetails'] as Map<String, dynamic>? ?? {};
    final journalEntries =
        data['JournalEntries'] as Map<String, dynamic>? ?? {};

    // حسابات صافي الوكلاء والفنيين
    final agentNet = (pendingDetails['AgentNet'] ?? 0) as num;
    final techNet = (pendingDetails['TechnicianNet'] ?? 0) as num;

    // بيانات الصناديق
    final funds = _fundsData ?? {};
    final cashBoxes = funds['CashBoxes'] as List? ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ القسم 1: أرصدة الحسابات الرئيسية ═══
          _sectionHeader('الأرصدة الرئيسية', Icons.account_balance_wallet,
              const Color(0xFF2C3E50)),
          const SizedBox(height: 12),
          _buildCardsGrid([
            _DashCard(
              title: 'رصيد القاصة',
              value: _fmt(accountBalances['CashRegisterBalance']),
              icon: Icons.point_of_sale,
              color: const Color(0xFF16A085),
            ),
            _DashCard(
              title: 'صندوق الشركة الرئيسي',
              value: _fmt(accountBalances['MainCashBoxBalance']),
              icon: Icons.account_balance,
              color: const Color(0xFF2C3E50),
            ),
            _DashCard(
              title: 'رصيد الصفحة',
              value: _fmt(accountBalances['PageBalance']),
              icon: Icons.account_balance_wallet,
              color: const Color(0xFF3498DB),
            ),
            _DashCard(
              title: 'رصيد الصندوق النقدي',
              value: _fmt(accountBalances['CashAccountBalance']),
              icon: Icons.savings,
              color: const Color(0xFF1ABC9C),
            ),
          ], cols: 4),

          const SizedBox(height: 24),

          // ═══ القسم 2: الميزانية العمومية ═══
          _sectionHeader(
              'الميزانية العمومية', Icons.balance, const Color(0xFF8E44AD)),
          const SizedBox(height: 12),
          _buildCardsGrid([
            _DashCard(
              title: 'إجمالي الأصول',
              value: _fmt(accountBalances['TotalAssets']),
              icon: Icons.domain,
              color: const Color(0xFF3498DB),
            ),
            _DashCard(
              title: 'إجمالي الالتزامات',
              value: _fmt(accountBalances['TotalLiabilities']),
              icon: Icons.assignment_late,
              color: const Color(0xFFE67E22),
            ),
            _DashCard(
              title: 'حقوق الملكية',
              value: _fmt(accountBalances['TotalEquity']),
              icon: Icons.shield,
              color: const Color(0xFF9B59B6),
            ),
          ], cols: 3),

          const SizedBox(height: 24),

          // ═══ القسم 3: قائمة الدخل ═══
          _sectionHeader(
              'قائمة الدخل', Icons.receipt_long, const Color(0xFF27AE60)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الإيرادات والمصروفات
              Expanded(
                flex: 2,
                child: _buildCardsGrid([
                  _DashCard(
                    title: 'إجمالي الإيرادات',
                    value: _fmt(accountBalances['TotalRevenue']),
                    icon: Icons.trending_up,
                    color: const Color(0xFF2ECC71),
                  ),
                  _DashCard(
                    title: 'إجمالي المصروفات',
                    value: _fmt(accountBalances['TotalExpenses']),
                    icon: Icons.trending_down,
                    color: const Color(0xFFE74C3C),
                  ),
                ], cols: 2),
              ),
              const SizedBox(width: 16),
              // صافي الدخل بارز
              Expanded(
                flex: 1,
                child: _buildHighlightCard(
                  title: 'صافي الدخل',
                  value: _fmt(accountBalances['NetIncome']),
                  icon: Icons.assessment,
                  color: _getNetIncomeColor(accountBalances['NetIncome']),
                  isPositive: _isPositive(accountBalances['NetIncome']),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ═══ القسم 4: إحصائيات الشهر الحالي ═══
          _sectionHeader('إحصائيات الشهر الحالي', Icons.calendar_today,
              const Color(0xFF2980B9)),
          const SizedBox(height: 12),
          _buildCardsGrid([
            _DashCard(
              title: 'تحصيلات الشهر',
              value: _fmt(collections['MonthlyTotal']),
              icon: Icons.attach_money,
              color: const Color(0xFF1ABC9C),
              subtitle: 'عدد: ${collections['MonthlyCount'] ?? 0}',
            ),
            _DashCard(
              title: 'مصروفات الشهر',
              value: _fmt(expenses['MonthlyTotal']),
              icon: Icons.money_off,
              color: const Color(0xFFE67E22),
              subtitle: 'عدد: ${expenses['MonthlyCount'] ?? 0}',
            ),
            _DashCard(
              title: 'رواتب الشهر',
              value: _fmt(salaries['MonthlyTotal']),
              icon: Icons.payments,
              color: const Color(0xFFE91E63),
              subtitle: 'عدد: ${salaries['MonthlyCount'] ?? 0}',
            ),
            _DashCard(
              title: 'صافي الشهر',
              value: _fmt(data['NetMonthly']),
              icon: Icons.bar_chart,
              color: const Color(0xFF34495E),
            ),
          ], cols: 4),

          const SizedBox(height: 24),

          // ═══ القسم 5: المعلقات والذمم ═══
          _sectionHeader(
              'المعلقات والذمم', Icons.pending_actions, const Color(0xFF8E44AD)),
          const SizedBox(height: 12),
          _buildCardsGrid([
            _DashCard(
              title: 'تحصيلات غير مسلمة',
              value: _fmt(collections['PendingDelivery']),
              icon: Icons.hourglass_top,
              color: const Color(0xFF8E44AD),
              subtitle: 'بانتظار التسليم',
            ),
            _DashCard(
              title: 'رواتب غير مصروفة',
              value: _fmt(salaries['UnpaidTotal']),
              icon: Icons.hourglass_empty,
              color: const Color(0xFFE74C3C),
              subtitle: 'عدد: ${salaries['UnpaidCount'] ?? 0}',
            ),
            _DashCard(
              title: agentNet < 0
                  ? 'ذمم الوكلاء (مدينون)'
                  : 'ذمم الوكلاء (دائنون)',
              value: _fmt(agentNet.abs()),
              icon: Icons.support_agent,
              color: agentNet < 0
                  ? const Color(0xFFE74C3C)
                  : const Color(0xFF2ECC71),
            ),
            _DashCard(
              title: techNet < 0
                  ? 'ذمم الفنيين (مدينون)'
                  : 'ذمم الفنيين (دائنون)',
              value: _fmt(techNet.abs()),
              icon: Icons.engineering,
              color: techNet < 0
                  ? const Color(0xFF8E44AD)
                  : const Color(0xFF27AE60),
            ),
          ], cols: 4),

          const SizedBox(height: 24),

          // ═══ القسم 6: مستحقات المشغلين ═══
          _sectionHeader('مستحقات المشغلين', Icons.people_alt,
              const Color(0xFF9B59B6)),
          const SizedBox(height: 12),
          _buildCardsGrid([
            _DashCard(
              title: 'مستحقات المشغلين',
              value: _fmt(accountBalances['OperatorReceivables']),
              icon: Icons.people,
              color: const Color(0xFF9B59B6),
            ),
          ], cols: 3),

          const SizedBox(height: 24),

          // ═══ القسم 7: الإجماليات الكلية ═══
          _sectionHeader(
              'الإجماليات الكلية', Icons.summarize, const Color(0xFF00897B)),
          const SizedBox(height: 12),
          _buildCardsGrid([
            _DashCard(
              title: 'إجمالي التحصيلات',
              value: _fmt(collections['TotalCollected']),
              icon: Icons.monetization_on,
              color: const Color(0xFF27AE60),
              subtitle: 'عدد: ${collections['TotalCount'] ?? 0}',
            ),
            _DashCard(
              title: 'إجمالي المصروفات',
              value: _fmt(expenses['TotalExpenses']),
              icon: Icons.receipt,
              color: const Color(0xFFE74C3C),
              subtitle: 'عدد: ${expenses['TotalCount'] ?? 0}',
            ),
            _DashCard(
              title: 'إجمالي الرواتب',
              value: _fmt(salaries['TotalSalaries']),
              icon: Icons.account_balance_wallet,
              color: const Color(0xFFE91E63),
              subtitle: 'عدد: ${salaries['TotalCount'] ?? 0}',
            ),
            _DashCard(
              title: 'عدد القيود',
              value: '${journalEntries['TotalCount'] ?? 0}',
              icon: Icons.menu_book,
              color: const Color(0xFF5C6BC0),
              subtitle: 'هذا الشهر: ${journalEntries['MonthlyCount'] ?? 0}',
            ),
          ], cols: 4),

          // ═══ القسم 8: الصناديق النقدية ═══
          if (cashBoxes.isNotEmpty) ...[
            const SizedBox(height: 24),
            _sectionHeader(
                'الصناديق النقدية', Icons.inventory_2, const Color(0xFF00695C)),
            const SizedBox(height: 12),
            _buildCashBoxesSection(cashBoxes),
          ],

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  // عناصر البناء (Widgets)
  // ═══════════════════════════════════════════

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          right: BorderSide(color: color, width: 4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: _textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardsGrid(List<_DashCard> cards, {int cols = 4}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final actualCols = maxW > 1000
            ? cols
            : maxW > 700
                ? (cols > 2 ? cols - 1 : 2)
                : maxW > 450
                    ? 2
                    : 1;
        const spacing = 12.0;
        final cardWidth = (maxW - spacing * (actualCols - 1)) / actualCols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map((c) => SizedBox(width: cardWidth, child: _buildCard(c)))
              .toList(),
        );
      },
    );
  }

  Widget _buildCard(_DashCard card) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _dividerColor),
        boxShadow: const [
          BoxShadow(color: _shadowColor, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: card.color,
              shape: BoxShape.circle,
            ),
            child: Icon(card.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    card.value,
                    style: GoogleFonts.cairo(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _textDark,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 3,
                  width: 50,
                  decoration: BoxDecoration(
                    color: card.color.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  card.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(fontSize: 12, color: _textGray),
                ),
                if (card.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    card.subtitle!,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: card.color.withOpacity(0.7),
                      fontWeight: FontWeight.w600,
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

  Widget _buildHighlightCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isPositive,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [color, color.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.9), size: 36),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  color: Colors.white,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  isPositive ? 'ربح' : 'خسارة',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashBoxesSection(List<dynamic> cashBoxes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = maxW > 900
            ? 3
            : maxW > 500
                ? 2
                : 1;
        const spacing = 12.0;
        final cardWidth = (maxW - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cashBoxes.map((box) {
            final boxMap =
                box is Map<String, dynamic> ? box : <String, dynamic>{};
            final name = boxMap['Name'] ?? boxMap['name'] ?? 'صندوق';
            final balance = boxMap['Balance'] ??
                boxMap['balance'] ??
                boxMap['CurrentBalance'] ??
                0;
            return SizedBox(
              width: cardWidth,
              child: _buildCard(_DashCard(
                title: name.toString(),
                value: _fmt(balance),
                icon: Icons.inventory_2,
                color: const Color(0xFF00897B),
              )),
            );
          }).toList(),
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  // مساعدات (Helpers)
  // ═══════════════════════════════════════════

  Color _getNetIncomeColor(dynamic value) {
    if (value == null) return const Color(0xFF95A5A6);
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    if (n > 0) return const Color(0xFF27AE60);
    if (n < 0) return const Color(0xFFE74C3C);
    return const Color(0xFF95A5A6);
  }

  bool _isPositive(dynamic value) {
    if (value == null) return true;
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return n >= 0;
  }

  String _fmt(dynamic value) {
    if (value == null) return '0 د.ع';
    final num n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    final abs = n.abs();
    final parts = abs.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (int i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(parts[i]);
    }
    final sign = n < 0 ? '-' : '';
    return '$sign${buffer.toString()} د.ع';
  }
}

// ═══════════════════════════════════════════
// نماذج البيانات
// ═══════════════════════════════════════════

class _DashCard {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;

  _DashCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
  });
}
