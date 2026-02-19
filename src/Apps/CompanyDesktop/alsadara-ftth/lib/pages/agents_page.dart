/// اسم الصفحة: الوكلاء
/// وصف الصفحة: صفحة إدارة الوكلاء والموزعين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/smart_text_color.dart';
import '../services/task_api_service.dart';

class AgentsPage extends StatefulWidget {
  final String fbg;
  const AgentsPage({super.key, required this.fbg});

  @override
  State<AgentsPage> createState() => _AgentsPageState();
}

class _AgentsPageState extends State<AgentsPage> {
  List<Map<String, dynamic>> agents = [];
  List<Map<String, dynamic>> filteredAgents = [];
  String? selectedGroup;
  TextEditingController searchController = TextEditingController();
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    debugPrint('تهيئة صفحة الوكلاء للمجموعة: ${widget.fbg}');
    _fetchAgentsData();
  }

  Future<void> _fetchAgentsData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      debugPrint('جلب بيانات الوكلاء للمجموعة: ${widget.fbg}');

      final staffData = await TaskApiService.instance.getTaskStaff();
      final List<dynamic> staffList =
          staffData['staff'] ?? staffData['Staff'] ?? [];

      // تجميع الموظفين حسب القسم
      Map<String, List<Map<String, String>>> groupedByDept = {};
      for (var staff in staffList) {
        final name =
            (staff['FullName'] ?? staff['fullName'] ?? '').toString().trim();
        final phone = (staff['PhoneNumber'] ?? staff['phoneNumber'] ?? '')
            .toString()
            .trim();
        final dept = (staff['Department'] ?? staff['department'] ?? 'غير محدد')
            .toString()
            .trim();

        if (name.isNotEmpty) {
          groupedByDept.putIfAbsent(dept, () => []);
          groupedByDept[dept]!.add({'name': name, 'phone': phone});
        }
      }

      // تحويل إلى البنية المتوقعة من الواجهة (group + agent1, agent2, ...)
      final List<Map<String, dynamic>> fetchedAgents =
          groupedByDept.entries.map((entry) {
        final Map<String, dynamic> agentData = {'group': entry.key};
        for (int i = 0; i < entry.value.length; i++) {
          agentData['agent${i + 1}'] = entry.value[i];
        }
        return agentData;
      }).toList();

      // فلترة البيانات حسب FBG المرسل
      List<Map<String, dynamic>> fbgFilteredAgents = [];
      if (widget.fbg.isNotEmpty && widget.fbg != 'الكل') {
        fbgFilteredAgents = fetchedAgents
            .where((agent) =>
                agent['group']?.toString().toLowerCase() ==
                widget.fbg.toLowerCase())
            .toList();
      } else {
        fbgFilteredAgents = fetchedAgents;
      }

      setState(() {
        agents = fbgFilteredAgents;
        filteredAgents = fbgFilteredAgents;
        isLoading = false;
        errorMessage = null;
      });

      debugPrint('تم جلب ${agents.length} مجموعة وكلاء للـ FBG: ${widget.fbg}');

      // إذا كان هناك مجموعة واحدة فقط، قم بعرضها مباشرة
      if (agents.length == 1) {
        _filterAgents(agents[0]['group']);
      }
    } catch (e) {
      debugPrint('خطأ في جلب بيانات الوكلاء: $e');
      setState(() {
        errorMessage = 'خطأ أثناء جلب بيانات الوكلاء: ${e.toString()}';
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء جلب بيانات الوكلاء: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterAgents(String group) {
    setState(() {
      selectedGroup = group;
      filteredAgents =
          agents.where((agent) => agent['group'] == group).toList();
    });
  }

  void _resetView() {
    setState(() {
      selectedGroup = null;
      filteredAgents = agents;
    });
  }

  Future<void> _sendMessage(String phone) async {
    if (!phone.startsWith('+')) {
      phone = '+964${phone.substring(1)}';
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
    // تحديد ألوان التدرج للـ AppBar
    final gradientColors = [Colors.blueAccent, Colors.blue[600]!];

    // تحديد لون النص والأيقونات بطريقة ذكية
    final smartTextColor =
        SmartTextColor.getAppBarTextColorWithGradient(context, gradientColors);
    final smartIconColor = smartTextColor;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
          ),
        ),
        title: Text(
          'وكلاء ${widget.fbg}',
          style: SmartTextColor.getSmartTextStyle(
            context: context,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            gradientColors: gradientColors,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: smartIconColor),
        centerTitle: true,
        elevation: 2,
        leading: selectedGroup != null
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: smartIconColor),
                onPressed: _resetView,
              )
            : null,
        actions: [
          if (agents.isNotEmpty)
            IconButton(
              icon: Icon(Icons.refresh, color: smartIconColor),
              onPressed: _fetchAgentsData,
              tooltip: 'تحديث البيانات',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // عرض معلومات FBG المحدد
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Text(
                'مجموعة: ${widget.fbg}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),

            // شريط البحث (يظهر فقط عند عدم اختيار مجموعة)
            if (selectedGroup == null && agents.length > 1)
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  labelText: 'بحث عن المجموعة',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                onChanged: (value) {
                  setState(() {
                    filteredAgents = agents
                        .where((agent) => agent['group']!
                            .toLowerCase()
                            .contains(value.toLowerCase()))
                        .toList();
                  });
                },
              ),
            const SizedBox(height: 16),

            Expanded(
              child: isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('جاري تحميل بيانات الوكلاء...'),
                        ],
                      ),
                    )
                  : errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 64,
                                color: Colors.red[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'خطأ في تحميل البيانات',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[700],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                errorMessage!,
                                style: TextStyle(
                                  color: Colors.red[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _fetchAgentsData,
                                icon: const Icon(Icons.refresh),
                                label: const Text('إعادة المحاولة'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : filteredAgents.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'لا توجد وكلاء',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'لم يتم العثور على أي وكلاء للمجموعة ${widget.fbg}',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredAgents.length,
                              itemBuilder: (context, index) {
                                final agent = filteredAgents[index];

                                if (selectedGroup == null) {
                                  // عرض قائمة المجموعات
                                  return Card(
                                    elevation: 2,
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 6.0, horizontal: 4.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue[100],
                                        child: Icon(
                                          Icons.group,
                                          color: Colors.blue[700],
                                        ),
                                      ),
                                      title: Text(
                                        agent['group'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'اضغط لعرض الوكلاء',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      trailing:
                                          const Icon(Icons.arrow_forward_ios),
                                      onTap: () =>
                                          _filterAgents(agent['group']),
                                    ),
                                  );
                                } else {
                                  // عرض قائمة الوكلاء في المجموعة المحددة
                                  final agentsList = agent.entries
                                      .where((entry) => entry.key != 'group')
                                      .where((entry) => (entry.value
                                              as Map<String, String>)['name']!
                                          .isNotEmpty)
                                      .toList();

                                  if (agentsList.isEmpty) {
                                    return const Card(
                                      child: ListTile(
                                        title: Text(
                                            'لا توجد وكلاء في هذه المجموعة'),
                                      ),
                                    );
                                  }

                                  return Card(
                                    elevation: 2,
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 6.0, horizontal: 4.0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.blue[50],
                                            borderRadius:
                                                const BorderRadius.only(
                                              topLeft: Radius.circular(12),
                                              topRight: Radius.circular(12),
                                            ),
                                          ),
                                          child: Text(
                                            'مجموعة: ${agent['group']}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue[800],
                                            ),
                                          ),
                                        ),
                                        ...agentsList.map((entry) {
                                          final agentInfo = entry.value
                                              as Map<String, String>;
                                          return ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor:
                                                  Colors.green[100],
                                              child: Icon(
                                                Icons.person,
                                                color: Colors.green[700],
                                              ),
                                            ),
                                            title: Text(
                                              agentInfo['name']!,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Text(
                                              agentInfo['phone']!,
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontFamily: 'monospace',
                                              ),
                                            ),
                                            trailing: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.green,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.chat,
                                                  color: Colors.white,
                                                ),
                                                onPressed: () => _sendMessage(
                                                    agentInfo['phone']!),
                                                tooltip: 'إرسال رسالة واتساب',
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
