import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../providers/agent_auth_provider.dart';
import '../../services/agent_api_service.dart';

/// صفحة تقارير الوكيل
class AgentReportsPage extends StatefulWidget {
  const AgentReportsPage({super.key});

  @override
  State<AgentReportsPage> createState() => _AgentReportsPageState();
}

class _AgentReportsPageState extends State<AgentReportsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedPeriod = 'month';
  DateTimeRange? _customRange;
  bool _isLoading = true;

  // Computed Data
  List<AgentTransactionData> _periodTransactions = [];
  Map<String, double> _summaryData = {
    'totalSales': 0,
    'totalTransactions': 0,
    'income': 0,
    'expense': 0,
  };
  List<Map<String, dynamic>> _salesByService = [];
  List<Map<String, dynamic>> _dailySales = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Determine Date Range
    DateTime now = DateTime.now();
    DateTime start;
    DateTime end = now;

    if (_customRange != null) {
      start = _customRange!.start;
      end = _customRange!.end;
    } else {
      switch (_selectedPeriod) {
        case 'today':
          start = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          start = now.subtract(const Duration(days: 7));
          break;
        case 'month':
          start = DateTime(now.year, now.month, 1);
          break;
        case 'year':
          start = DateTime(now.year, 1, 1);
          break;
        default:
          start = DateTime(now.year, now.month, 1);
      }
    }

    final allTransactions = await context
        .read<AgentAuthProvider>()
        .getTransactions(
          pageSize: 100,
          startDate: start,
          endDate: end.add(const Duration(days: 1)),
        );

    _computeStats(allTransactions);

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _computeStats(List<AgentTransactionData> transactions) {
    _periodTransactions = transactions;

    double totalSales = 0;
    double income = 0;
    double expense = 0;
    Map<int, double> typeMap = {};
    Map<String, double> dayMap = {};

    for (var tx in transactions) {
      if (!tx.isIncoming) {
        totalSales += tx.amount;
        expense += tx.amount;

        // Type Distribution (only for expenses/sales)
        typeMap[tx.category] = (typeMap[tx.category] ?? 0) + tx.amount;
      } else {
        income += tx.amount;
      }

      // Daily Sales (Expenses)
      if (!tx.isIncoming) {
        String dayKey = intl.DateFormat('EEE', 'ar').format(tx.createdAt);
        dayMap[dayKey] = (dayMap[dayKey] ?? 0) + tx.amount;
      }
    }

    _summaryData = {
      'totalSales': totalSales,
      'totalTransactions': transactions.length.toDouble(),
      'income': income,
      'expense': expense,
    };

    _salesByService = typeMap.entries.map((e) {
      String name;
      Color color;
      switch (e.key) {
        case 0:
          name = 'اشتراك جديد';
          color = AppTheme.successColor;
          break;
        case 1:
          name = 'تجديد';
          color = AppTheme.agentColor;
          break;
        case 2:
          name = 'صيانة';
          color = AppTheme.primaryColor;
          break;
        case 3:
          name = 'تحصيل فواتير';
          color = AppTheme.accentColor;
          break;
        default:
          name = 'أخرى';
          color = AppTheme.textGrey;
      }
      return {
        'name': name,
        'value': e.value,
        'count': transactions
            .where((t) => t.category == e.key && !t.isIncoming)
            .length,
        'color': color,
      };
    }).toList();

    _dailySales = dayMap.entries.map((e) {
      return {'day': e.key, 'value': e.value};
    }).toList();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Theme(
      data: AppTheme.agentTheme,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AppTheme.backgroundColor,
          appBar: AppBar(
            title: const Text('التقارير والإحصائيات'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/agent/home'),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: _showExportDialog,
                tooltip: 'تصدير',
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadData,
                tooltip: 'تحديث',
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: const [
                Tab(text: 'نظرة عامة', icon: Icon(Icons.dashboard)),
                Tab(text: 'المبيعات', icon: Icon(Icons.bar_chart)),
              ],
            ),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // اختيار الفترة
                    _buildPeriodSelector(),

                    // محتوى التبويبات
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewTab(isWide),
                          _buildSalesTab(isWide),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildPeriodChip('today', 'اليوم'),
            const SizedBox(width: 8),
            _buildPeriodChip('week', 'هذا الأسبوع'),
            const SizedBox(width: 8),
            _buildPeriodChip('month', 'هذا الشهر'),
            const SizedBox(width: 8),
            _buildPeriodChip('year', 'هذا العام'),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.date_range, size: 18),
              label: Text(
                _customRange != null
                    ? '${intl.DateFormat('MM/dd').format(_customRange!.start)} - ${intl.DateFormat('MM/dd').format(_customRange!.end)}'
                    : 'فترة مخصصة',
              ),
              onPressed: _selectCustomRange,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (range != null) {
      setState(() {
        _customRange = range;
        _selectedPeriod = 'custom';
      });
      _loadData();
    }
  }

  Widget _buildPeriodChip(String value, String label) {
    final isSelected = _selectedPeriod == value;
    return ChoiceChip(
      selected: isSelected,
      label: Text(label),
      selectedColor: AppTheme.agentColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppTheme.textDark,
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedPeriod = value;
            _customRange = null;
          });
          _loadData();
        }
      },
    );
  }

  Widget _buildOverviewTab(bool isWide) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ملخص الأرقام
          if (isWide)
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'إجمالي المبيعات',
                    '${_summaryData['totalSales']!.toStringAsFixed(0)} د.ع',
                    Icons.attach_money,
                    AppTheme.successColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'عدد العمليات',
                    '${_summaryData['totalTransactions']!.toInt()}',
                    Icons.receipt_long,
                    AppTheme.infoColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    'إجمالي الإيداع',
                    '${_summaryData['income']!.toStringAsFixed(0)} د.ع',
                    Icons.account_balance_wallet,
                    AppTheme.accentColor,
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                _buildStatCard(
                  'إجمالي المبيعات',
                  '${_summaryData['totalSales']!.toStringAsFixed(0)} د.ع',
                  Icons.attach_money,
                  AppTheme.successColor,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'عدد العمليات',
                        '${_summaryData['totalTransactions']!.toInt()}',
                        Icons.receipt_long,
                        AppTheme.infoColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'الإيداع',
                        '${_summaryData['income']!.toStringAsFixed(0)} د.ع',
                        Icons.account_balance_wallet,
                        AppTheme.accentColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 24),

          // توزيع المبيعات حسب الخدمة
          _buildSectionTitle('توزيع المبيعات حسب الخدمة'),
          const SizedBox(height: 16),
          _buildServiceDistribution(),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textGrey,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppTheme.textDark,
      ),
    );
  }

  Widget _buildServiceDistribution() {
    if (_salesByService.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد بيانات',
          style: TextStyle(color: AppTheme.textGrey),
        ),
      );
    }

    final total = _salesByService.fold<double>(
      0,
      (sum, item) => sum + (item['value'] as num).toDouble(),
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          // شريط التوزيع
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 24,
              child: Row(
                children: _salesByService.map((item) {
                  final percentage = total == 0
                      ? 0.0
                      : (item['value'] as num) / total;
                  return Expanded(
                    flex: (percentage * 100).round(),
                    child: Container(color: item['color'] as Color),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // تفاصيل الخدمات
          ..._salesByService.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: item['color'] as Color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item['name'] as String,
                      style: const TextStyle(color: AppTheme.textDark),
                    ),
                  ),
                  Text(
                    '${item['count']} عملية',
                    style: const TextStyle(color: AppTheme.textGrey),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    '${(item['value'] as double).toStringAsFixed(0)} د.ع',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTab(bool isWide) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isWide ? 32 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رسم بياني للمبيعات اليومية
          _buildSectionTitle('المبيعات اليومية'),
          const SizedBox(height: 16),
          _buildDailySalesChart(),
          const SizedBox(height: 24),

          // جدول المبيعات
          _buildSectionTitle('تفاصيل العمليات'),
          const SizedBox(height: 16),
          _buildSalesTable(),
        ],
      ),
    );
  }

  Widget _buildDailySalesChart() {
    if (_dailySales.isEmpty) {
      return const SizedBox(
        height: 100,
        child: Center(child: Text('لا توجد بيانات')),
      );
    }

    final maxValue = _dailySales.fold<double>(
      0,
      (max, item) => (item['value'] as num) > max
          ? (item['value'] as num).toDouble()
          : max,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _dailySales.map((item) {
                final height = maxValue == 0
                    ? 0.0
                    : ((item['value'] as num) / maxValue) * 180;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${((item['value'] as num) / 1000).toStringAsFixed(1)}K',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textGrey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: height,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppTheme.agentColor.withOpacity(0.5),
                                AppTheme.agentColor,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: _dailySales
                .map(
                  (item) => Expanded(
                    child: Text(
                      item['day'] as String,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textGrey,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesTable() {
    if (_periodTransactions.isEmpty) {
      return const SizedBox(
        height: 50,
        child: Center(child: Text('لا توجد عمليات')),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          // رأس الجدول
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.agentColor.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'العملية',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'الوصف',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    'المبلغ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(
                  child: Text(
                    'التاريخ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // صفوف الجدول (Limit to last 10 for detailed view)
          ..._periodTransactions
              .take(10)
              .map(
                (t) => Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: AppTheme.borderColor.withOpacity(0.5),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${t.id}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textGrey,
                              ),
                            ),
                            Text(t.description ?? t.typeName),
                          ],
                        ),
                      ),
                      Expanded(flex: 2, child: Text(t.description ?? '-')),
                      Expanded(
                        child: Text(
                          '${t.amount.toStringAsFixed(0)} د.ع',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: t.isIncoming
                                ? AppTheme.successColor
                                : Colors.red,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          intl.DateFormat('MM/dd').format(t.createdAt),
                          style: const TextStyle(color: AppTheme.textGrey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصدير التقرير'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('ملف PDF'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('جاري تصدير PDF...')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.green),
              title: const Text('ملف Excel'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('جاري تصدير Excel...')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
