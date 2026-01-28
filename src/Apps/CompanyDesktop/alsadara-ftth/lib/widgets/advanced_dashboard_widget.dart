import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/task.dart';

class AdvancedDashboardWidget extends StatefulWidget {
  final List<Task> tasks;
  final String userRole;
  final String department;

  const AdvancedDashboardWidget({
    super.key,
    required this.tasks,
    required this.userRole,
    required this.department,
  });

  @override
  _AdvancedDashboardWidgetState createState() =>
      _AdvancedDashboardWidgetState();
}

class _AdvancedDashboardWidgetState extends State<AdvancedDashboardWidget>
    with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // عنوان لوحة التحكم
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.deepPurple.shade600, Colors.purple.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(25),
                topRight: Radius.circular(25),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.dashboard_outlined, color: Colors.white, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'لوحة التحكم المتقدمة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'تحليلات شاملة ومؤشرات الأداء',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    'مباشر',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // شريط التبويب
          Container(
            color: Colors.grey.shade50,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.deepPurple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.deepPurple,
              indicatorWeight: 3,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              tabs: [
                Tab(icon: Icon(Icons.pie_chart), text: 'الإحصائيات'),
                Tab(icon: Icon(Icons.trending_up), text: 'الاتجاهات'),
                Tab(icon: Icon(Icons.people), text: 'الأداء'),
                Tab(icon: Icon(Icons.schedule), text: 'الأوقات'),
              ],
            ),
          ),

          // محتوى التبويبات
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStatisticsTab(),
                _buildTrendsTab(),
                _buildPerformanceTab(),
                _buildTimingTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsTab() {
    var totalTasks = widget.tasks.length;
    var completedTasks = widget.tasks.where((t) => t.status == 'مكتملة').length;
    var inProgressTasks =
        widget.tasks.where((t) => t.status == 'قيد التنفيذ').length;
    var openTasks = widget.tasks.where((t) => t.status == 'مفتوحة').length;
    var cancelledTasks = widget.tasks.where((t) => t.status == 'ملغية').length;

    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          // KPI Cards
          Row(
            children: [
              Expanded(
                  child: _buildKPICard(
                      'إجمالي', totalTasks, Colors.blue, Icons.assignment)),
              SizedBox(width: 12),
              Expanded(
                  child: _buildKPICard('مكتملة', completedTasks, Colors.green,
                      Icons.check_circle)),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _buildKPICard('قيد التنفيذ', inProgressTasks,
                      Colors.orange, Icons.settings)),
              SizedBox(width: 12),
              Expanded(
                  child: _buildKPICard(
                      'مفتوحة', openTasks, Colors.red, Icons.lock_open)),
            ],
          ),

          SizedBox(height: 30),

          // مخطط دائري للحالات
          SizedBox(
            height: 300,
            child: Column(
              children: [
                Text(
                  'توزيع المهام حسب الحالة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                SizedBox(height: 20),
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: [
                        PieChartSectionData(
                          value: completedTasks.toDouble(),
                          title: 'مكتملة\n$completedTasks',
                          color: Colors.green,
                          radius: 80,
                          titleStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          value: inProgressTasks.toDouble(),
                          title: 'قيد التنفيذ\n$inProgressTasks',
                          color: Colors.orange,
                          radius: 80,
                          titleStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          value: openTasks.toDouble(),
                          title: 'مفتوحة\n$openTasks',
                          color: Colors.blue,
                          radius: 80,
                          titleStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        PieChartSectionData(
                          value: cancelledTasks.toDouble(),
                          title: 'ملغية\n$cancelledTasks',
                          color: Colors.red,
                          radius: 80,
                          titleStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20),

          // معدل الإنجاز
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade400, Colors.green.shade600],
              ),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Icon(Icons.speed, color: Colors.white, size: 40),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'معدل الإنجاز',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${totalTasks > 0 ? ((completedTasks / totalTasks) * 100).toStringAsFixed(1) : 0}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsTab() {
    // تحليل الاتجاهات الأسبوعية
    var weeklyData = _getWeeklyTaskData();

    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'اتجاهات المهام الأسبوعية',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 20),

          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          'الأسبوع ${value.toInt()}',
                          style: TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: weeklyData,
                    isCurved: true,
                    color: Colors.blue,
                    barWidth: 3,
                    dotData: FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 30),

          // مؤشرات الاتجاه
          Row(
            children: [
              Expanded(
                child: _buildTrendIndicator(
                  'هذا الأسبوع',
                  '${_getCurrentWeekTasks()}',
                  _getWeeklyGrowth(),
                  _getWeeklyGrowth() >= 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  _getWeeklyGrowth() >= 0 ? Colors.green : Colors.red,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildTrendIndicator(
                  'متوسط أسبوعي',
                  _getWeeklyAverage().toStringAsFixed(1),
                  0,
                  Icons.show_chart,
                  Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceTab() {
    var technicianPerformance = _getTechnicianPerformance();

    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'أداء الفنيين',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 20),

          // قائمة أداء الفنيين
          ...technicianPerformance.entries.map((entry) {
            var efficiency = entry.value['efficiency'] as double;
            var completedTasks = entry.value['completed'] as int;
            var totalTasks = entry.value['total'] as int;

            return Container(
              margin: EdgeInsets.symmetric(vertical: 8),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: efficiency >= 80 ? Colors.green : Colors.orange,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            efficiency >= 80 ? Colors.green : Colors.orange,
                        child: Text(
                          entry.key.substring(0, 1),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$completedTasks من $totalTasks مهمة',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color:
                              efficiency >= 80 ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${efficiency.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: efficiency / 100,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation(
                      efficiency >= 80 ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimingTab() {
    var timeAnalysis = _getTimeAnalysis();

    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'تحليل الأوقات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 20),

          // توزيع المهام حسب الوقت
          SizedBox(
            height: 250,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: timeAnalysis.values
                        .reduce((a, b) => a > b ? a : b)
                        .toDouble() *
                    1.2,
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        switch (value.toInt()) {
                          case 0:
                            return Text('صباحاً',
                                style: TextStyle(fontSize: 10));
                          case 1:
                            return Text('ظهراً',
                                style: TextStyle(fontSize: 10));
                          case 2:
                            return Text('مساءً',
                                style: TextStyle(fontSize: 10));
                          case 3:
                            return Text('ليلاً',
                                style: TextStyle(fontSize: 10));
                          default:
                            return Text('');
                        }
                      },
                    ),
                  ),
                  topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [
                    BarChartRodData(
                        toY: timeAnalysis['morning']!.toDouble(),
                        color: Colors.orange)
                  ]),
                  BarChartGroupData(x: 1, barRods: [
                    BarChartRodData(
                        toY: timeAnalysis['afternoon']!.toDouble(),
                        color: Colors.blue)
                  ]),
                  BarChartGroupData(x: 2, barRods: [
                    BarChartRodData(
                        toY: timeAnalysis['evening']!.toDouble(),
                        color: Colors.purple)
                  ]),
                  BarChartGroupData(x: 3, barRods: [
                    BarChartRodData(
                        toY: timeAnalysis['night']!.toDouble(),
                        color: Colors.indigo)
                  ]),
                ],
              ),
            ),
          ),

          SizedBox(height: 30),

          // إحصائيات الوقت
          Row(
            children: [
              Expanded(
                child: _buildTimeCard(
                    'ذروة النشاط', _getPeakHour(), Icons.schedule),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildTimeCard(
                    'متوسط الإنجاز', _getAverageCompletionTime(), Icons.timer),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(String title, int value, Color color, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 8),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendIndicator(
      String title, String value, double change, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          if (change != 0)
            Text(
              '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeCard(String title, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // وظائف حساب البيانات
  List<FlSpot> _getWeeklyTaskData() {
    // حساب المهام الأسبوعية (مثال)
    return List.generate(8, (index) {
      var tasksThisWeek = widget.tasks.where((task) {
        var weekAgo = DateTime.now().subtract(Duration(days: (7 - index) * 7));
        return task.createdAt.isAfter(weekAgo);
      }).length;
      return FlSpot(index.toDouble(), tasksThisWeek.toDouble());
    });
  }

  int _getCurrentWeekTasks() {
    var weekAgo = DateTime.now().subtract(Duration(days: 7));
    return widget.tasks.where((task) => task.createdAt.isAfter(weekAgo)).length;
  }

  double _getWeeklyGrowth() {
    var thisWeek = _getCurrentWeekTasks();
    var lastWeekStart = DateTime.now().subtract(Duration(days: 14));
    var lastWeekEnd = DateTime.now().subtract(Duration(days: 7));
    var lastWeek = widget.tasks
        .where((task) =>
            task.createdAt.isAfter(lastWeekStart) &&
            task.createdAt.isBefore(lastWeekEnd))
        .length;

    if (lastWeek == 0) return 0;
    return ((thisWeek - lastWeek) / lastWeek) * 100;
  }

  double _getWeeklyAverage() {
    if (widget.tasks.isEmpty) return 0;
    var weeksBack = 4;
    var startDate = DateTime.now().subtract(Duration(days: weeksBack * 7));
    var recentTasks =
        widget.tasks.where((task) => task.createdAt.isAfter(startDate)).length;
    return recentTasks / weeksBack;
  }

  Map<String, Map<String, dynamic>> _getTechnicianPerformance() {
    Map<String, Map<String, dynamic>> performance = {};

    for (var task in widget.tasks) {
      if (!performance.containsKey(task.technician)) {
        performance[task.technician] = {
          'total': 0,
          'completed': 0,
          'efficiency': 0.0,
        };
      }

      performance[task.technician]!['total']++;
      if (task.status == 'مكتملة') {
        performance[task.technician]!['completed']++;
      }

      var total = performance[task.technician]!['total'] as int;
      var completed = performance[task.technician]!['completed'] as int;
      performance[task.technician]!['efficiency'] = (completed / total) * 100;
    }

    return performance;
  }

  Map<String, int> _getTimeAnalysis() {
    Map<String, int> timeAnalysis = {
      'morning': 0,
      'afternoon': 0,
      'evening': 0,
      'night': 0,
    };

    for (var task in widget.tasks) {
      var hour = task.createdAt.hour;
      if (hour >= 6 && hour < 12) {
        timeAnalysis['morning'] = timeAnalysis['morning']! + 1;
      } else if (hour >= 12 && hour < 18) {
        timeAnalysis['afternoon'] = timeAnalysis['afternoon']! + 1;
      } else if (hour >= 18 && hour < 24) {
        timeAnalysis['evening'] = timeAnalysis['evening']! + 1;
      } else {
        timeAnalysis['night'] = timeAnalysis['night']! + 1;
      }
    }

    return timeAnalysis;
  }

  String _getPeakHour() {
    var timeAnalysis = _getTimeAnalysis();
    var maxEntry =
        timeAnalysis.entries.reduce((a, b) => a.value > b.value ? a : b);

    switch (maxEntry.key) {
      case 'morning':
        return '6-12 صباحاً';
      case 'afternoon':
        return '12-6 مساءً';
      case 'evening':
        return '6-12 مساءً';
      default:
        return '12-6 صباحاً';
    }
  }

  String _getAverageCompletionTime() {
    var completedTasks =
        widget.tasks.where((t) => t.status == 'مكتملة' && t.closedAt != null);
    if (completedTasks.isEmpty) return 'غير محدد';

    var totalHours = completedTasks.fold(0,
        (sum, task) => sum + task.closedAt!.difference(task.createdAt).inHours);

    var averageHours = totalHours / completedTasks.length;
    return '${averageHours.toStringAsFixed(1)} ساعة';
  }
}
