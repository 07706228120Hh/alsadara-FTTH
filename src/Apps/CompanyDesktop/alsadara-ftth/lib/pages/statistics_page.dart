/// اسم الصفحة: الإحصائيات
/// وصف الصفحة: صفحة عرض الإحصائيات والتقارير التفصيلية
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
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
      errorMessage = null;
    });

    try {
      await Future.wait([
        fetchStatistics(),
        fetchAgents(),
      ]).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('انتهت مهلة الاتصال بالسيرفر'),
      );
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = e.toString().contains('انتهت مهلة')
              ? 'انتهت مهلة الاتصال — تحقق من الاتصال بالإنترنت'
              : 'حدث خطأ أثناء جلب البيانات';
          isLoading = false;
        });
      }
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
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: SdAppBar(
        title: selectedZone ?? 'إحصائيات الزونات',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
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
        actions: [
          SdAppBarAction(
            icon: Icons.refresh,
            label: 'تحديث',
            onPressed: fetchData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(SdSpace.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: SdColors.primary),
                    SizedBox(height: 20),
                    Text('جاري تحميل الإحصائيات...', style: SdText.titleSm),
                  ],
                ),
              ),
            )
          : errorMessage != null
              ? SdEmptyState(
                  icon: Icons.error_outline,
                  status: SdStatus.danger,
                  title: 'حدث خطأ',
                  message: errorMessage!,
                  action: SdButton(
                    label: 'إعادة المحاولة',
                    icon: Icons.refresh,
                    onPressed: fetchData,
                  ),
                )
              : selectedZone == null
                  ? Column(
                      children: [
                        // شريط البحث والفلتر
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SdCard(
                            title: 'البحث والفلترة',
                            icon: Icons.filter_list,
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border:
                                          Border.all(color: SdColors.divider),
                                      borderRadius:
                                          BorderRadius.circular(SdRadius.sm),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: selectedFilter,
                                        isExpanded: true,
                                        padding: const EdgeInsets.symmetric(
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
                                      prefixIcon: const Icon(Icons.search,
                                          color: SdColors.primary),
                                      border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(SdRadius.sm),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(SdRadius.sm),
                                        borderSide: const BorderSide(
                                            color: SdColors.primary, width: 2),
                                      ),
                                    ),
                                    onChanged: filterStatistics,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // إحصائيات عامة
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: SdStatPedestal(
                            value: totalZonesCount,
                            label: 'عدد الزونات الكلي',
                            tone: SdStatus.danger.tone,
                          ),
                        ),

                        const SizedBox(height: 16),

                        // جدول الإحصائيات — على الهاتف: بطاقات عمودية
                        Expanded(
                          child: context.sd.isPhone
                              ? _buildZonesCardsMobile()
                              : Container(
                            margin:
                                const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: SdColors.surface,
                              borderRadius: BorderRadius.circular(SdRadius.lg),
                              boxShadow: SdDepth.raised(),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(SdRadius.lg),
                              child: SingleChildScrollView(
                                child: Table(
                                  border: TableBorder.all(
                                    color: SdColors.divider,
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
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SdCard(
                            tone: SdGroup.field.tone,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.people,
                                    color: SdColors.accent, size: 28),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    'الوكلاء في الزون: $selectedZone',
                                    style: SdText.title,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
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
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SdCard(
                                  padding: EdgeInsets.zero,
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
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: SdColors.primaryTint,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SdRadius.sm),
                                              ),
                                              child: const Icon(
                                                Icons.person,
                                                color: SdColors.primary,
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
                                                    style: SdText.titleSm,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    agentInfo['phone']!,
                                                    style: SdText.bodySm,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                color: SdColors.whatsapp,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        SdRadius.sm),
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
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
    );
  }

  // ═════════════════════════════
  // عرض الهاتف: بطاقات بدل جدول الزونات العريض
  // (نفس القيم والترتيب تماماً — إعادة تقديم بصري فقط)
  // ═════════════════════════════
  Widget _buildZonesCardsMobile() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: filteredStatistics.length,
      itemBuilder: (context, index) {
        final stat = filteredStatistics[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SdCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // اسم الزون — قابل للنقر لعرض الوكلاء (نفس سلوك الجدول)
                InkWell(
                  onTap: () => filterAgents(stat['FBG']),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 18, color: SdColors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          stat['FBG'].toString(),
                          style: const TextStyle(
                            fontFamily: SdText.family,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: SdColors.primary,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_left,
                          size: 20, color: SdColors.faint),
                    ],
                  ),
                ),
                const Divider(height: 14, color: SdColors.divider),
                _zRow('FATS', stat['FATS'].toString()),
                _zRow('عدد الكلي', stat['total_users'].toString()),
                _zRow('فعالين', stat['non_subscribed_users'].toString()),
                _zRow('الغير فعالين', stat['active_users'].toString()),
                _zRow('المنطقة', stat['region'].toString()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _zRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: SdText.bodySm)),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontFamily: SdText.family,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: SdColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  TableRow _buildHeaderRow() {
    return const TableRow(
      decoration: BoxDecoration(color: SdColors.primary),
      children: [
        CenteredText(text: 'الزون', fontSize: 16, color: Colors.white),
        CenteredText(text: 'FATS', fontSize: 16, color: Colors.white),
        CenteredText(text: 'عدد الكلي', fontSize: 16, color: Colors.white),
        CenteredText(text: 'فعالين', fontSize: 16, color: Colors.white),
        CenteredText(text: 'الغير فعالين', fontSize: 16, color: Colors.white),
        CenteredText(text: 'المنطقة', fontSize: 16, color: Colors.white),
      ],
    );
  }

  TableRow _buildDataRow(Map<String, dynamic> stat) {
    return TableRow(
      decoration: const BoxDecoration(
        color: SdColors.surface,
        border: Border(
          bottom: BorderSide(color: SdColors.divider),
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
              color: SdColors.primary,
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
            fontFamily: SdText.family,
            fontSize: fontSize,
            color: color ?? SdColors.ink,
            fontWeight: color != null ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
