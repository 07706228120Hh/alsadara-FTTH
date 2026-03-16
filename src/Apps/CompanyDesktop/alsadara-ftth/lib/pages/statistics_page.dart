/// اسم الصفحة: الإحصائيات
/// وصف الصفحة: صفحة عرض الإحصائيات والتقارير التفصيلية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/zone_statistics_api_service.dart';
import '../services/task_api_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  _StatisticsPageState createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  List<Map<String, dynamic>> statistics = [];
  List<Map<String, dynamic>> filteredStatistics = [];
  List<Map<String, dynamic>> agents = [];
  List<Map<String, dynamic>> filteredAgents = [];
  bool isLoading = true;
  String? errorMessage;
  String? selectedZone;

  String selectedFilter = "FBG"; // الخيار الافتراضي
  TextEditingController searchController = TextEditingController();
  int totalZonesCount = 0;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    setState(() {
      isLoading = true;
    });

    try {
      await Future.wait([
        fetchStatistics(),
        fetchAgents(),
      ]);
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ أثناء جلب البيانات';
        isLoading = false;
      });
    }
  }

  Future<void> fetchStatistics() async {
    try {
      final data = await ZoneStatisticsApiService.instance.getAll();

      final List<Map<String, dynamic>> fetchedStatistics = data.map((zone) {
        return {
          "FBG": zone['ZoneName'] ?? zone['zoneName'] ?? 'غير معروف',
          "FATS": zone['Fats'] ?? zone['fats'] ?? 0,
          "total_users": zone['TotalUsers'] ?? zone['totalUsers'] ?? 0,
          "active_users": zone['ActiveUsers'] ?? zone['activeUsers'] ?? 0,
          "non_subscribed_users":
              zone['InactiveUsers'] ?? zone['inactiveUsers'] ?? 0,
          "region": zone['RegionName'] ?? zone['regionName'] ?? 'غير محدد',
        };
      }).toList();

      setState(() {
        statistics = fetchedStatistics;
        filteredStatistics = fetchedStatistics;
        totalZonesCount = fetchedStatistics.length;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ';
      });
    }
  }

  Future<void> fetchAgents() async {
    try {
      final data = await TaskApiService.instance.getTaskStaff();
      final staffList = data['staff'] as List? ?? [];

      // تجميع الموظفين حسب القسم
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final staff in staffList) {
        final dept =
            (staff as Map<String, dynamic>)['Department']?.toString() ??
                'غير محدد';
        grouped.putIfAbsent(dept, () => []);
        grouped[dept]!.add(staff);
      }

      final List<Map<String, dynamic>> fetchedAgents =
          grouped.entries.map((entry) {
        final Map<String, dynamic> agentData = {'zone': entry.key};
        for (int i = 0; i < entry.value.length; i++) {
          final staff = entry.value[i];
          agentData['agent${i + 1}'] = {
            'name': staff['FullName']?.toString() ?? '',
            'phone': staff['PhoneNumber']?.toString() ?? '',
          };
        }
        return agentData;
      }).toList();

      setState(() {
        agents = fetchedAgents;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'حدث خطأ';
      });
    }
  }

  void filterStatistics(String query) {
    query = query.toLowerCase();
    int? numericQuery = int.tryParse(query);

    setState(() {
      if (query.isEmpty) {
        filteredStatistics = statistics;
        return;
      }

      filteredStatistics = statistics.where((stat) {
        final columnValue = stat[selectedFilter];

        if (numericQuery != null && columnValue is int) {
          // إذا كانت القيمة عددية، اعرض القيم الأقل أو تساوي
          return columnValue <= numericQuery;
        } else if (columnValue is String) {
          // إذا كانت القيمة نصية، اعرض القيم المطابقة
          return columnValue.toLowerCase().contains(query);
        }

        return false;
      }).toList();
    });
  }

  void filterAgents(String zone) {
    final results = agents.where((agent) => agent['zone'] == zone).toList();

    setState(() {
      filteredAgents = results;
      selectedZone = zone;
    });
  }

  Future<void> sendMessage(String phone) async {
    if (!phone.startsWith('+')) {
      phone = '+964$phone';
    }

    // محاولة فتح تطبيق WhatsApp مباشرة
    final whatsappAppUrl = 'whatsapp://send?phone=$phone';
    final whatsappWebUrl = 'https://wa.me/$phone';

    try {
      // محاولة فتح تطبيق WhatsApp أولاً
      final appUri = Uri.parse(whatsappAppUrl);
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }

      // إذا لم يكن التطبيق متاحاً، فتح WhatsApp Web كبديل
      final webUri = Uri.parse(whatsappWebUrl);
      if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return;
      }

      throw 'لم يتم العثور على تطبيق WhatsApp';
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن فتح تطبيق واتساب')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.red[800]!,
                Colors.red[600]!,
                Colors.red[400]!,
              ],
            ),
          ),
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              selectedZone != null
                  ? Icons.arrow_back_ios
                  : Icons.arrow_back_ios,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () {
            if (selectedZone != null) {
              setState(() {
                selectedZone = null;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.bar_chart,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                selectedZone ?? 'إحصائيات الزونات',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.refresh, color: Colors.white, size: 20),
            ),
            tooltip: 'تحديث',
            onPressed: fetchData,
          ),
        ],
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.red[50]!,
              Colors.white,
            ],
          ),
        ),
        child: _ResponsiveBodyShim(
          child: isLoading
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.red[600]!),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'جاري تحميل الإحصائيات...',
                          style: TextStyle(
                            color: Colors.red[600],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : errorMessage != null
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(30),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            )
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red[600],
                              size: 50,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'حدث خطأ',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[600],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              errorMessage!,
                              style: TextStyle(
                                color: Colors.red[400],
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : selectedZone == null
                      ? Column(
                          children: [
                            // شريط البحث والفلتر العصري
                            Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.filter_list,
                                        color: Colors.red[600],
                                        size: 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'البحث والفلترة',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                                color: Colors.red[300]!),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: selectedFilter,
                                              isExpanded: true,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 16),
                                              onChanged: (value) {
                                                setState(() {
                                                  selectedFilter = value!;
                                                });
                                              },
                                              items: const [
                                                DropdownMenuItem(
                                                  value: "FBG",
                                                  child: Text("الزون"),
                                                ),
                                                DropdownMenuItem(
                                                  value: "region",
                                                  child: Text("المنطقة"),
                                                ),
                                                DropdownMenuItem(
                                                  value: "FATS",
                                                  child: Text("FATS"),
                                                ),
                                                DropdownMenuItem(
                                                  value: "total_users",
                                                  child: Text("عدد الكلي"),
                                                ),
                                                DropdownMenuItem(
                                                  value: "active_users",
                                                  child: Text(" غير الفعالين"),
                                                ),
                                                DropdownMenuItem(
                                                  value: "non_subscribed_users",
                                                  child: Text("الفعالين"),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: searchController,
                                          decoration: InputDecoration(
                                            labelText: 'بحث',
                                            prefixIcon: Icon(Icons.search,
                                                color: Colors.red[600]),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                  color: Colors.red[600]!,
                                                  width: 2),
                                            ),
                                          ),
                                          onChanged: filterStatistics,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // إحصائيات عامة
                            Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.red[600]!, Colors.red[400]!],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.analytics,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'عدد الزونات الكلي: $totalZonesCount',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // جدول الإحصائيات
                            Expanded(
                              child: Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: SingleChildScrollView(
                                    child: Table(
                                      border: TableBorder.all(
                                        color: Colors.grey.shade200,
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
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        )
                      : Column(
                          children: [
                            // عنوان الوكلاء
                            Container(
                              margin: const EdgeInsets.all(16),
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.red[600]!, Colors.red[400]!],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withValues(alpha: 0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Flexible(
                                    child: Text(
                                      'الوكلاء في الزون: $selectedZone',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // قائمة الوكلاء
                            Expanded(
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: filteredAgents.length,
                                itemBuilder: (context, index) {
                                  final agent = filteredAgents[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color:
                                              Colors.red.withValues(alpha: 0.1),
                                          blurRadius: 10,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: agent.entries
                                          .where((entry) => entry.key != 'zone')
                                          .map((entry) {
                                        final agentInfo =
                                            entry.value as Map<String, String>;
                                        return Container(
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.red[50],
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Icon(
                                                  Icons.person,
                                                  color: Colors.red[600],
                                                  size: 24,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      agentInfo['name']!,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      agentInfo['phone']!,
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.green[600]!,
                                                      Colors.green[400]!
                                                    ],
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: IconButton(
                                                  icon: const Icon(
                                                    Icons.message,
                                                    color: Colors.white,
                                                  ),
                                                  onPressed: () => sendMessage(
                                                      agentInfo['phone']!),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
        ),
      ),
    );
  }

  TableRow _buildHeaderRow() {
    return TableRow(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red[600]!, Colors.red[400]!],
        ),
      ),
      children: const [
        CenteredText(text: 'الزون', fontSize: 18, color: Colors.white),
        CenteredText(text: 'FATS', fontSize: 18, color: Colors.white),
        CenteredText(text: 'عدد الكلي', fontSize: 18, color: Colors.white),
        CenteredText(text: 'فعالين', fontSize: 18, color: Colors.white),
        CenteredText(text: 'الغير فعالين', fontSize: 18, color: Colors.white),
        CenteredText(text: 'المنطقة', fontSize: 18, color: Colors.white),
      ],
    );
  }

  TableRow _buildDataRow(Map<String, dynamic> stat) {
    return TableRow(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      children: [
        GestureDetector(
          onTap: () {
            filterAgents(stat['FBG']);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: CenteredText(
              text: stat['FBG'],
              fontSize: 16,
              color: Colors.red[700],
            ),
          ),
        ),
        CenteredText(text: stat['FATS'].toString(), fontSize: 16),
        CenteredText(text: stat['total_users'].toString(), fontSize: 16),
        CenteredText(
            text: stat['non_subscribed_users'].toString(), fontSize: 16),
        CenteredText(text: stat['active_users'].toString(), fontSize: 16),
        CenteredText(text: stat['region'], fontSize: 16),
      ],
    );
  }
}

class _ResponsiveBodyShim extends StatelessWidget {
  final Widget child;
  const _ResponsiveBodyShim({required this.child});
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    double maxWidth;
    if (width > 1440) {
      maxWidth = 1200;
    } else if (width > 1024) {
      maxWidth = 1000;
    } else if (width > 600) {
      maxWidth = 800;
    } else {
      maxWidth = double.infinity;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: child,
        ),
      ),
    );
  }
}

class CenteredText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color? color;

  const CenteredText({
    super.key,
    required this.text,
    this.fontSize = 16,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: fontSize,
            color: color ?? Colors.black,
            fontWeight: color != null ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
