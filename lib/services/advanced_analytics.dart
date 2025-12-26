import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/task.dart';

class AdvancedAnalytics {
  // تحليل الأداء حسب الفني
  static Map<String, TaskPerformance> analyzePerformanceByTechnician(
      List<Task> tasks) {
    Map<String, TaskPerformance> performance = {};

    for (var task in tasks) {
      if (!performance.containsKey(task.technician)) {
        performance[task.technician] = TaskPerformance();
      }

      var perf = performance[task.technician]!;
      perf.totalTasks++;

      if (task.status == 'مكتملة') {
        perf.completedTasks++;
        if (task.closedAt != null) {
          var duration = task.closedAt!.difference(task.createdAt);
          perf.totalDuration += duration;
          perf.averageDuration = Duration(
              milliseconds:
                  perf.totalDuration.inMilliseconds ~/ perf.completedTasks);
        }
      }

      perf.efficiency = perf.totalTasks > 0
          ? (perf.completedTasks / perf.totalTasks) * 100
          : 0;
    }

    return performance;
  }

  // تحليل المهام حسب الوقت
  static Map<String, int> analyzeTasksByTime(List<Task> tasks) {
    Map<String, int> timeAnalysis = {
      'صباحاً': 0,
      'ظهراً': 0,
      'مساءً': 0,
      'ليلاً': 0,
    };

    for (var task in tasks) {
      var hour = task.createdAt.hour;
      if (hour >= 6 && hour < 12) {
        timeAnalysis['صباحاً'] = timeAnalysis['صباحاً']! + 1;
      } else if (hour >= 12 && hour < 18) {
        timeAnalysis['ظهراً'] = timeAnalysis['ظهراً']! + 1;
      } else if (hour >= 18 && hour < 24) {
        timeAnalysis['مساءً'] = timeAnalysis['مساءً']! + 1;
      } else {
        timeAnalysis['ليلاً'] = timeAnalysis['ليلاً']! + 1;
      }
    }

    return timeAnalysis;
  }

  // تحليل الاتجاهات الأسبوعية
  static Map<String, double> analyzeWeeklyTrends(List<Task> tasks) {
    Map<String, int> weeklyCount = {};

    // تجميع المهام حسب الأسبوع
    for (var task in tasks) {
      var weekKey = '${task.createdAt.year}-W${_getWeekNumber(task.createdAt)}';
      weeklyCount[weekKey] = (weeklyCount[weekKey] ?? 0) + 1;
    }

    // حساب معدل النمو
    Map<String, double> trends = {};
    var sortedWeeks = weeklyCount.keys.toList()..sort();

    for (int i = 1; i < sortedWeeks.length; i++) {
      var currentWeek = sortedWeeks[i];
      var previousWeek = sortedWeeks[i - 1];
      var currentCount = weeklyCount[currentWeek]!;
      var previousCount = weeklyCount[previousWeek]!;

      var growthRate = previousCount > 0
          ? ((currentCount - previousCount) / previousCount) * 100
          : 0.0;

      trends[currentWeek] = growthRate;
    }

    return trends;
  }

  static int _getWeekNumber(DateTime date) {
    var dayOfYear = date.difference(DateTime(date.year, 1, 1)).inDays;
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  // توقع المهام المستقبلية
  static int predictFutureTasks(List<Task> tasks, int daysAhead) {
    if (tasks.length < 7) return 0;

    // حساب متوسط المهام اليومية
    var recentTasks = tasks
        .where((task) =>
            task.createdAt.isAfter(DateTime.now().subtract(Duration(days: 30))))
        .toList();

    if (recentTasks.isEmpty) return 0;

    var dailyAverage = recentTasks.length / 30;
    return (dailyAverage * daysAhead).round();
  }
}

class TaskPerformance {
  int totalTasks = 0;
  int completedTasks = 0;
  Duration totalDuration = Duration.zero;
  Duration averageDuration = Duration.zero;
  double efficiency = 0.0;
}

// ويدجت لعرض التحليلات المتقدمة
class AdvancedAnalyticsWidget extends StatelessWidget {
  final List<Task> tasks;

  const AdvancedAnalyticsWidget({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    var performance = AdvancedAnalytics.analyzePerformanceByTechnician(tasks);
    var timeAnalysis = AdvancedAnalytics.analyzeTasksByTime(tasks);
    var prediction = AdvancedAnalytics.predictFutureTasks(tasks, 7);

    return Card(
      elevation: 8,
      margin: EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 التحليلات المتقدمة',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            SizedBox(height: 20),

            // أداء الفنيين
            Text(
              'أداء الفنيين:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            ...performance.entries.map((entry) => Container(
                  margin: EdgeInsets.symmetric(vertical: 4),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(entry.key,
                          style: TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                        '${entry.value.efficiency.toStringAsFixed(1)}% (${entry.value.completedTasks}/${entry.value.totalTasks})',
                        style: TextStyle(
                          color: entry.value.efficiency >= 80
                              ? Colors.green
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )),

            SizedBox(height: 20),

            // توزيع المهام حسب الوقت
            Text(
              'توزيع المهام حسب الوقت:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: timeAnalysis.entries.map((entry) {
                    var colors = {
                      'صباحاً': Colors.orange,
                      'ظهراً': Colors.blue,
                      'مساءً': Colors.purple,
                      'ليلاً': Colors.indigo,
                    };

                    return PieChartSectionData(
                      value: entry.value.toDouble(),
                      title: '${entry.key}\n${entry.value}',
                      color: colors[entry.key],
                      radius: 100,
                      titleStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                ),
              ),
            ),

            SizedBox(height: 20),

            // التنبؤ بالمهام
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade600],
                ),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_up, color: Colors.white, size: 30),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'التنبؤ للأسبوع القادم',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'متوقع: $prediction مهمة جديدة',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
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
      ),
    );
  }
}
