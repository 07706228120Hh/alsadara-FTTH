import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _StatisticsPageState createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final String apiKey = 'AIzaSyDdwZK0D8uRoPSKS0axA5dQjwMCQJtF1BU';
  final String spreadsheetId = '1MGY8UhtHaUiRaUKbohEi3a74jgEh7NeOuTEHBQ83KZc';
  final String range = 'Sheet1!A2:F';

  List<Map<String, dynamic>> statistics = [];
  List<Map<String, dynamic>> filteredStatistics = [];
  bool isLoading = true;
  String? errorMessage;
  TextEditingController searchController = TextEditingController();

  Future<void> fetchStatistics() async {
    final url =
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$range?key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['values'] != null) {
          final rows = data['values'] as List;

          final List<Map<String, dynamic>> fetchedStatistics = rows.map((row) {
            return {
              "FBG": row.isNotEmpty ? row[0] : 'غير معروف',
              "FATS": row.length > 1 ? row[1] : '0',
              "total_users": row.length > 2 ? row[2] : '0',
              "active_users": row.length > 3 ? row[3] : '0',
              "non_subscribed_users": row.length > 4 ? row[4] : '0',
              "region": row.length > 5 ? row[5] : 'غير محدد',
            };
          }).toList();

          setState(() {
            statistics = fetchedStatistics;
            filteredStatistics = fetchedStatistics;
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

  void filterStatistics(String query) {
    final results = statistics.where((stat) {
      final fbg = stat['FBG'].toString().toLowerCase();
      return fbg.contains(query.toLowerCase());
    }).toList();

    setState(() {
      filteredStatistics = results;
    });
  }

  @override
  void initState() {
    super.initState();
    fetchStatistics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'إحصائيات الزونات',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 28, 169, 125),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 18),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          labelText: 'ابحث عن الزون',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: filterStatistics,
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          Table(
                            border: TableBorder.all(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                            columnWidths: const {
                              0: FlexColumnWidth(1.5),
                              1: FlexColumnWidth(1),
                              2: FlexColumnWidth(1),
                              3: FlexColumnWidth(1),
                              4: FlexColumnWidth(1),
                              5: FlexColumnWidth(1.5),
                            },
                            children: [
                              _buildHeaderRow(),
                              ...filteredStatistics.map((stat) {
                                return _buildDataRow(stat);
                              }).toList(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  TableRow _buildHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
      ),
      children: const [
        CenteredText(text: 'الزون', fontSize: 18),
        CenteredText(text: 'FATS', fontSize: 18),
        CenteredText(text: 'عدد الكلي', fontSize: 18),
        CenteredText(text: 'الغير فعالين', fontSize: 18),
        CenteredText(text: 'الفعالين', fontSize: 18),
        CenteredText(text: 'المنطقة', fontSize: 18),
      ],
    );
  }

  TableRow _buildDataRow(Map<String, dynamic> stat) {
    return TableRow(
      children: [
        CenteredText(text: stat['FBG'], fontSize: 16),
        CenteredText(text: stat['FATS'], fontSize: 16),
        CenteredText(text: stat['total_users'], fontSize: 16),
        CenteredText(text: stat['active_users'], fontSize: 16),
        CenteredText(text: stat['non_subscribed_users'], fontSize: 16),
        CenteredText(text: stat['region'], fontSize: 16),
      ],
    );
  }
}

class CenteredText extends StatelessWidget {
  final String text;
  final double fontSize;

  const CenteredText({super.key, required this.text, this.fontSize = 16});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}
