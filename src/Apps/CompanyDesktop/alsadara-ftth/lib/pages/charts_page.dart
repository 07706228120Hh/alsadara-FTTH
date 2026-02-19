/// اسم الصفحة: الرسوم البيانية
/// وصف الصفحة: صفحة عرض الرسوم البيانية والمخططات التحليلية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets/responsive_body.dart';
import '../services/zone_statistics_api_service.dart';

class ChartsPage extends StatefulWidget {
  const ChartsPage({super.key});
  @override
  State<ChartsPage> createState() => _ChartsPageState();
}

class _ChartsPageState extends State<ChartsPage> {
  bool isLoading = true;
  String? errorMessage;

  List<int> totalUsersPerZone = [];
  List<int> nonSubscribedUsersPerZone = [];
  List<String> zones = [];

  @override
  void initState() {
    super.initState();
    fetchChartData();
  }

  Future<void> fetchChartData() async {
    try {
      final data = await ZoneStatisticsApiService.instance.getAll();

      if (data.isNotEmpty) {
        final List<String> zonesTmp = [];
        final List<int> totalUsersTmp = [];
        final List<int> nonSubscribedTmp = [];

        for (final zone in data) {
          zonesTmp.add(
              (zone['ZoneName'] ?? zone['zoneName'] ?? 'غير معروف').toString());
          totalUsersTmp
              .add((zone['TotalUsers'] ?? zone['totalUsers'] ?? 0) as int);
          nonSubscribedTmp.add(
              (zone['InactiveUsers'] ?? zone['inactiveUsers'] ?? 0) as int);
        }

        setState(() {
          zones = zonesTmp;
          totalUsersPerZone = totalUsersTmp;
          nonSubscribedUsersPerZone = nonSubscribedTmp;
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'لم يتم العثور على بيانات.';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'المخططات',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
        ),
        backgroundColor: Colors.blue[800],
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                )
              : ResponsiveBody(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Expanded(
                        child: _buildChart(
                          'مخطط الزونات وعدد المستخدمين الكلي',
                          totalUsersPerZone,
                          isTotalUsers: true,
                          chartWidth: width,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _buildChart(
                          'مخطط الزونات وعدد المستخدمين غير المجددين',
                          nonSubscribedUsersPerZone,
                          isTotalUsers: false,
                          chartWidth: width,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildChart(String title, List<int> data,
      {required bool isTotalUsers, required double chartWidth}) {
    final int count = data.isEmpty ? 1 : data.length;
    double barWidth = chartWidth / (count * 3); // ضبط عرض الأعمدة
    barWidth = barWidth.clamp(6.0, 28.0); // تأمين قيمة معقولة للعرض

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            Expanded(
              child: BarChart(
                BarChartData(
                  barGroups: List.generate(data.length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: data[index].toDouble(),
                          color: isTotalUsers
                              ? (data[index] < 200
                                  ? Colors.red
                                  : (data[index] <= 300
                                      ? Colors.blue
                                      : Colors.green))
                              : Colors.orange,
                          width: barWidth,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false), // إزالة النصوص
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipPadding: const EdgeInsets.all(6),
                      tooltipRoundedRadius: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final zoneLabel =
                            (groupIndex >= 0 && groupIndex < zones.length)
                                ? zones[groupIndex]
                                : '#${groupIndex + 1}';
                        return BarTooltipItem(
                          'الزون: $zoneLabel\nعدد: ${rod.toY.toInt()}',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
