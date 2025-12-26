// lib/widgets/charts_dialog.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class ChartsDialog extends StatelessWidget {
  final Map<String, dynamic> data;
  final String title;
  const ChartsDialog({
    super.key,
    required this.data,
    required this.title,
  });

  // معالجة البيانات لاستخدامها في المخططات
  Map<String, int> _processData() {
    final processedData = <String, int>{};
    data.forEach((key, value) {
      if (value is int && !key.toLowerCase().contains('total')) {
        processedData[key] = value;
      }
    });
    return processedData;
  }

  @override
  Widget build(BuildContext context) {
    final processedData = _processData();

    // التحقق من وجود بيانات
    if (processedData.isEmpty) {
      return AlertDialog(
        title: const Text('تنبيه'),
        content: const Text('لا توجد بيانات متاحة للعرض'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      );
    }

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'إحصائيات $title',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 300,
              child: Row(
                children: [
                  // المخطط الدائري
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sections: _createPieChartSections(processedData),
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        startDegreeOffset: -90,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  // مخطط الأعمدة
                  Expanded(
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: processedData.values
                            .reduce((max, value) => value > max ? value : max)
                            .toDouble(),
                        barGroups: _createBarGroups(processedData),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(
                          show: true,
                          topTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                if (value < 0 ||
                                    value >= processedData.length) {
                                  return const SizedBox();
                                }
                                return Text(
                                  processedData.keys.elementAt(value.toInt()),
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildLegend(processedData),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[800],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(Map<String, int> processedData) {
    final List<Color> colors = [
      Colors.green,
      Colors.red,
      Colors.blue,
      Colors.orange,
      Colors.purple,
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: processedData.entries.map((entry) {
        final index = processedData.keys.toList().indexOf(entry.key);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: colors[index % colors.length],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 4),
            Text(entry.key),
            const SizedBox(width: 4),
            Text('(${entry.value})',
                style: const TextStyle(color: Colors.grey)),
          ],
        );
      }).toList(),
    );
  }

  List<PieChartSectionData> _createPieChartSections(
      Map<String, int> processedData) {
    final List<Color> colors = [
      Colors.green,
      Colors.red,
      Colors.blue,
      Colors.orange,
      Colors.purple,
    ];

    final total = processedData.values.reduce((sum, value) => sum + value);

    return processedData.entries.map((entry) {
      final index = processedData.keys.toList().indexOf(entry.key);
      final percentage = (entry.value / total * 100).roundToDouble();

      return PieChartSectionData(
        color: colors[index % colors.length],
        value: entry.value.toDouble(),
        title: '$percentage%',
        radius: 100,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  List<BarChartGroupData> _createBarGroups(Map<String, int> processedData) {
    final List<Color> colors = [
      Colors.green,
      Colors.red,
      Colors.blue,
      Colors.orange,
      Colors.purple,
    ];

    return processedData.entries.map((entry) {
      final index = processedData.keys.toList().indexOf(entry.key);
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: entry.value.toDouble(),
            color: colors[index % colors.length],
            width: 20,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(6),
            ),
          ),
        ],
      );
    }).toList();
  }
}
