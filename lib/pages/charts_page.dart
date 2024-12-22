import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChartsPage extends StatefulWidget {
  const ChartsPage({super.key});

  @override
  _ChartsPageState createState() => _ChartsPageState();
}

class _ChartsPageState extends State<ChartsPage> {
  final String apiKey = 'AIzaSyDdwZK0D8uRoPSKS0axA5dQjwMCQJtF1BU';
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  final String range = 'Sheet1!A2:E';

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
    final url =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range?key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['values'] != null) {
          final rows = data['values'] as List;

          setState(() {
            zones = rows.map((row) => row[0].toString()).toList();
            totalUsersPerZone =
                rows.map((row) => int.tryParse(row[2]) ?? 0).toList();
            nonSubscribedUsersPerZone =
                rows.map((row) => int.tryParse(row[3]) ?? 0).toList();
            isLoading = false;
          });
        } else {
          setState(() {
            errorMessage = 'لم يتم العثور على بيانات.';
            isLoading = false;
          });
        }
      } else {
        setState(() {
          errorMessage = 'خطأ في جلب البيانات: ${response.statusCode}';
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
              : Padding(
                  padding: const EdgeInsets.all(8.0),
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
    final barWidth = chartWidth / (data.length * 3); // ضبط عرض الأعمدة

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
                        return BarTooltipItem(
                          'الزون: ${zones[groupIndex]}\nعدد: ${rod.toY.toInt()}',
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
