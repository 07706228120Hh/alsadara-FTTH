import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../theme/accounting_theme.dart';
import 'chart_of_accounts_page.dart';

/// صفحة الإحصائيات - Statistics Page
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: Column(
          children: [
            _buildToolbar(),
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
                                color: AccountingTheme.accent))
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

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF2C3E50),
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
            child: const Icon(Icons.analytics, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text('الإحصائيات',
              style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(foregroundColor: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(
          left: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // عنوان القائمة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.menu, color: Color(0xFF2C3E50), size: 18),
                const SizedBox(width: 8),
                Text(
                  'القائمة',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF2C3E50),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8E8E8)),
          const SizedBox(height: 8),
          // شجرة الحسابات
          _sidebarItem(
            icon: Icons.account_tree_rounded,
            label: 'شجرة الحسابات',
            color: const Color(0xFF3498DB),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ChartOfAccountsPage(companyId: widget.companyId),
                ),
              );
            },
          ),
          // التقارير
          _sidebarItem(
            icon: Icons.summarize_rounded,
            label: 'التقارير',
            color: const Color(0xFF8E44AD),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('قريباً...',
                      style: GoogleFonts.cairo(color: Colors.white)),
                  backgroundColor: const Color(0xFF8E44AD),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _sidebarItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: color.withOpacity(0.08),
          splashColor: color.withOpacity(0.15),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF333333),
                    ),
                  ),
                ),
                Icon(Icons.chevron_left, color: Colors.grey.shade400, size: 18),
              ],
            ),
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
              color: AccountingTheme.danger, size: 64),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style:
                const TextStyle(color: AccountingTheme.textMuted, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, color: Colors.white),
            label: Text('إعادة المحاولة',
                style: GoogleFonts.cairo(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final data = _dashboardData ?? {};
    final collections = data['Collections'] as Map<String, dynamic>? ?? {};
    final expenses = data['Expenses'] as Map<String, dynamic>? ?? {};
    final salaries = data['Salaries'] as Map<String, dynamic>? ?? {};
    final accountBalances =
        data['AccountBalances'] as Map<String, dynamic>? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ═══ أرصدة الحسابات ═══
          _sectionTitle('أرصدة الحسابات', Icons.account_balance),
          const SizedBox(height: 12),
          _buildCardsRow([
            _StatCard(
              title: 'إجمالي الأصول',
              value: _fmt(accountBalances['TotalAssets']),
              icon: Icons.account_balance,
              color: const Color(0xFF3498DB),
            ),
            _StatCard(
              title: 'إجمالي الالتزامات',
              value: _fmt(accountBalances['TotalLiabilities']),
              icon: Icons.balance,
              color: const Color(0xFFE67E22),
            ),
            _StatCard(
              title: 'حقوق الملكية',
              value: _fmt(accountBalances['TotalEquity']),
              icon: Icons.shield,
              color: const Color(0xFF9B59B6),
            ),
          ]),
          const SizedBox(height: 12),
          _buildCardsRow([
            _StatCard(
              title: 'إجمالي الإيرادات',
              value: _fmt(accountBalances['TotalRevenue']),
              icon: Icons.trending_up,
              color: const Color(0xFF2ECC71),
            ),
            _StatCard(
              title: 'إجمالي المصروفات',
              value: _fmt(accountBalances['TotalExpenses']),
              icon: Icons.trending_down,
              color: const Color(0xFFE74C3C),
            ),
            _StatCard(
              title: 'صافي الدخل',
              value: _fmt(accountBalances['NetIncome']),
              icon: Icons.assessment,
              color: const Color(0xFFF1C40F),
            ),
          ]),
          const SizedBox(height: 12),
          _buildCardsRow([
            _StatCard(
              title: 'رصيد الصندوق',
              value: _fmt(accountBalances['CashAccountBalance']),
              icon: Icons.account_balance_wallet,
              color: const Color(0xFF1ABC9C),
            ),
          ]),

          const SizedBox(height: 28),
          const Divider(color: Color(0xFFE8E8E8)),
          const SizedBox(height: 20),

          // ═══ إحصائيات الشهر ═══
          _sectionTitle('إحصائيات الشهر الحالي', Icons.calendar_today),
          const SizedBox(height: 12),
          _buildCardsRow([
            _StatCard(
              title: 'تحصيلات الشهر',
              value: _fmt(collections['MonthlyTotal']),
              icon: Icons.attach_money,
              color: const Color(0xFF1ABC9C),
            ),
            _StatCard(
              title: 'مصروفات الشهر',
              value: _fmt(expenses['MonthlyTotal']),
              icon: Icons.money_off,
              color: const Color(0xFFE67E22),
            ),
            _StatCard(
              title: 'رواتب الشهر',
              value: _fmt(salaries['MonthlyTotal']),
              icon: Icons.payments,
              color: const Color(0xFFE91E63),
            ),
          ]),
          const SizedBox(height: 12),
          _buildCardsRow([
            _StatCard(
              title: 'غير مسلمة',
              value: _fmt(collections['PendingDelivery']),
              icon: Icons.pending_actions,
              color: const Color(0xFF8E44AD),
            ),
            _StatCard(
              title: 'رواتب غير مصروفة',
              value: _fmt(salaries['UnpaidTotal']),
              icon: Icons.hourglass_empty,
              color: const Color(0xFFE74C3C),
            ),
            _StatCard(
              title: 'صافي الشهر',
              value: _fmt(data['NetMonthly']),
              icon: Icons.bar_chart,
              color: const Color(0xFF34495E),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF333333), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF333333),
          ),
        ),
      ],
    );
  }

  Widget _buildCardsRow(List<_StatCard> cards) {
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
          children: cards.map((card) {
            return SizedBox(
              width: cardWidth,
              child: _buildStatCardWidget(card),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildStatCardWidget(_StatCard card) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
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
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF333333),
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 3,
                  width: 60,
                  decoration: BoxDecoration(
                    color: card.color.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  card.title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: const Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(dynamic value) {
    if (value == null) return '0 د.ع';
    final num n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    final parts = n.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    final isNegative = parts.isNotEmpty && parts[0] == '-';
    final digits = isNegative ? parts.sublist(1) : parts;
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return '${isNegative ? '-' : ''}${buffer.toString()} د.ع';
  }
}

class _StatCard {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
}
