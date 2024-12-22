import 'package:flutter/material.dart';
import 'charts_page.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({super.key});

  @override
  _AnalysisPageState createState() => _AnalysisPageState();
}

class _AnalysisPageState extends State<AnalysisPage> {
  final String apiKey = 'AIzaSyDdwZK0D8uRoPSKS0axA5dQjwMCQJtF1BU';
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  final String range = 'Sheet1!A2:E';

  bool isLoading = true;
  String? errorMessage;

  int totalZones = 0;
  int totalUsers = 0;
  int totalActiveUsers = 0;
  int totalInactiveUsers = 0;

  int minFats = 0;
  int maxFats = 0;
  double avgFats = 0.0;

  int minUsers = 0;
  int maxUsers = 0;
  double avgUsers = 0.0;

  @override
  void initState() {
    super.initState();
    fetchAnalysisData();
  }

  Future<void> fetchAnalysisData() async {
    final url =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range?key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['values'] != null) {
          final rows = data['values'] as List;

          int fatsSum = 0;
          int usersSum = 0;
          int activeUsersSum = 0;
          int inactiveUsersSum = 0;

          List<int> fatsList = [];
          List<int> usersList = [];

          for (var row in rows) {
            if (row.length > 1) {
              int fats = int.tryParse(row[1]) ?? 0;
              fatsSum += fats;
              fatsList.add(fats);
            }
            if (row.length > 2) {
              int users = int.tryParse(row[2]) ?? 0;
              usersSum += users;
              usersList.add(users);
            }
            if (row.length > 3) {
              int inactiveUsers = int.tryParse(row[3]) ?? 0;
              inactiveUsersSum += inactiveUsers;
            }
            if (row.length > 4) {
              int activeUsers = int.tryParse(row[4]) ?? 0;
              activeUsersSum += activeUsers;
            }
          }

          setState(() {
            totalZones = rows.length;
            totalUsers = usersSum;
            totalActiveUsers = activeUsersSum;
            totalInactiveUsers = inactiveUsersSum;

            if (fatsList.isNotEmpty) {
              minFats = fatsList.reduce((a, b) => a < b ? a : b);
              maxFats = fatsList.reduce((a, b) => a > b ? a : b);
              avgFats = fatsSum / fatsList.length;
            }

            if (usersList.isNotEmpty) {
              minUsers = usersList.reduce((a, b) => a < b ? a : b);
              maxUsers = usersList.reduce((a, b) => a > b ? a : b);
              avgUsers = usersSum / usersList.length;
            }

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

  Widget buildSection(String title, List<Widget> items, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Column(children: items),
          ],
        ),
      ),
    );
  }

  Widget buildStatisticRow(
      {required IconData icon, required String title, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحليل المعلومات'),
        backgroundColor: Colors.blue[800],
        centerTitle: true,
        actions: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChartsPage(),
                    ),
                  );
                },
                icon:
                    const Icon(Icons.bar_chart, size: 18, color: Colors.white),
                label: const Text(
                  'عرض المخططات',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ],
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
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16.0),
                  children: [
                    buildSection(
                        'إحصائيات عامة',
                        [
                          buildStatisticRow(
                            icon: Icons.location_on,
                            title: 'عدد الزونات الكلي',
                            value: totalZones.toString(),
                          ),
                          buildStatisticRow(
                            icon: Icons.people,
                            title: 'عدد المستخدمين الكلي',
                            value: totalUsers.toString(),
                          ),
                          buildStatisticRow(
                            icon: Icons.check_circle,
                            title: 'عدد المستخدمين الفعّالين',
                            value: totalActiveUsers.toString(),
                          ),
                          buildStatisticRow(
                            icon: Icons.cancel,
                            title: 'عدد غير المفعلين',
                            value: totalInactiveUsers.toString(),
                          ),
                        ],
                        Colors.blue[700]!),
                    const SizedBox(height: 8),
                    buildSection(
                        'إحصائيات FATS',
                        [
                          buildStatisticRow(
                            icon: Icons.trending_up,
                            title: 'أكبر عدد',
                            value: maxFats.toString(),
                          ),
                          buildStatisticRow(
                            icon: Icons.trending_down,
                            title: 'أصغر عدد',
                            value: minFats.toString(),
                          ),
                          buildStatisticRow(
                            icon: Icons.timeline,
                            title: 'المعدل',
                            value: avgFats.toStringAsFixed(2),
                          ),
                        ],
                        const Color.fromARGB(255, 41, 96, 103)),
                    const SizedBox(height: 8),
                    buildSection(
                        'إحصائيات المستخدمين',
                        [
                          buildStatisticRow(
                            icon: Icons.trending_up,
                            title: 'أكبر عدد',
                            value: maxUsers.toString(),
                          ),
                          buildStatisticRow(
                            icon: Icons.trending_down,
                            title: 'أصغر عدد',
                            value: minUsers.toString(),
                          ),
                          buildStatisticRow(
                            icon: Icons.timeline,
                            title: 'المعدل',
                            value: avgUsers.toStringAsFixed(2),
                          ),
                        ],
                        Colors.green[600]!),
                  ],
                ),
    );
  }
}
