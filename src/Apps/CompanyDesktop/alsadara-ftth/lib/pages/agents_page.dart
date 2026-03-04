/// اسم الصفحة: الوكلاء
/// وصف الصفحة: صفحة إدارة الوكلاء والموزعين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/smart_text_color.dart';
import '../services/task_api_service.dart';
import '../utils/responsive_helper.dart';

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

    final whatsappAppUrl = 'whatsapp://send?phone=$phone';
    final whatsappWebUrl = 'https://wa.me/$phone';

    try {
      final appUri = Uri.parse(whatsappAppUrl);
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }

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

  /// استخراج قائمة الوكلاء بأمان من بيانات المجموعة
  List<MapEntry<String, dynamic>> _safeAgentsList(Map<String, dynamic> agent) {
    try {
      return agent.entries
          .where((entry) => entry.key != 'group')
          .where((entry) {
        if (entry.value is Map) {
          final name = (entry.value as Map)['name']?.toString() ?? '';
          return name.isNotEmpty;
        }
        return false;
      }).toList();
    } catch (e) {
      debugPrint('⚠️ خطأ في استخراج قائمة الوكلاء: $e');
      return [];
    }
  }

  /// استخراج معلومات وكيل بأمان
  Map<String, String> _safeAgentInfo(dynamic value) {
    if (value is Map) {
      return {
        'name': (value['name'] ?? '').toString(),
        'phone': (value['phone'] ?? '').toString(),
      };
    }
    return {'name': '', 'phone': ''};
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final gradientColors = [Colors.blueAccent, Colors.blue[600]!];
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
            fontSize: r.appBarTitleSize,
            fontWeight: FontWeight.bold,
            gradientColors: gradientColors,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: smartIconColor, size: r.appBarIconSize),
        centerTitle: true,
        elevation: 2,
        leading: selectedGroup != null
            ? IconButton(
                icon: Icon(Icons.arrow_back,
                    color: smartIconColor, size: r.appBarIconSize),
                onPressed: _resetView,
              )
            : null,
        actions: [
          if (agents.isNotEmpty)
            IconButton(
              icon: Icon(Icons.refresh,
                  color: smartIconColor, size: r.appBarIconSize),
              onPressed: _fetchAgentsData,
              tooltip: 'تحديث البيانات',
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(r.contentPaddingH),
          child: Column(
            children: [
              // عرض معلومات FBG المحدد
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(r.cardPadding),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(r.buttonRadius),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'مجموعة: ${widget.fbg}',
                  style: TextStyle(
                    fontSize: r.cardTitleSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: r.gridSpacing * 1.5),

              // شريط البحث
              if (selectedGroup == null && agents.length > 1)
                TextField(
                  controller: searchController,
                  style: TextStyle(fontSize: r.bodySize),
                  decoration: InputDecoration(
                    labelText: 'بحث عن المجموعة',
                    labelStyle: TextStyle(fontSize: r.bodySize),
                    prefixIcon: Icon(Icons.search, size: r.iconSizeMedium),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(r.cardRadius),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: r.contentPaddingH,
                      vertical: r.isMobile ? 10 : 14,
                    ),
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
              SizedBox(height: r.gridSpacing),

              // المحتوى الرئيسي
              Expanded(
                child: _buildContent(r),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ResponsiveHelper r) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: r.gridSpacing),
            Text('جاري تحميل بيانات الوكلاء...',
                style: TextStyle(fontSize: r.bodySize)),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                size: r.emptyStateIconSize, color: Colors.red[300]),
            SizedBox(height: r.gridSpacing),
            Text(
              'خطأ في تحميل البيانات',
              style: TextStyle(
                fontSize: r.titleSize,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: r.contentPaddingH),
              child: Text(
                errorMessage!,
                style: TextStyle(
                  color: Colors.red[600],
                  fontSize: r.captionSize,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: r.gridSpacing),
            ElevatedButton.icon(
              onPressed: _fetchAgentsData,
              icon: Icon(Icons.refresh, size: r.iconSizeSmall),
              label: Text('إعادة المحاولة',
                  style: TextStyle(fontSize: r.buttonTextSize)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: r.contentPaddingH,
                  vertical: r.isMobile ? 8 : 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (filteredAgents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline,
                size: r.emptyStateIconSize, color: Colors.grey[400]),
            SizedBox(height: r.gridSpacing),
            Text(
              'لا توجد وكلاء',
              style: TextStyle(
                fontSize: r.titleSize,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: r.contentPaddingH),
              child: Text(
                'لم يتم العثور على أي وكلاء للمجموعة ${widget.fbg}',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: r.captionSize,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredAgents.length,
      itemBuilder: (context, index) {
        final agent = filteredAgents[index];

        if (selectedGroup == null) {
          return _buildGroupCard(agent, r);
        } else {
          return _buildAgentsCard(agent, r);
        }
      },
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> agent, ResponsiveHelper r) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(
        vertical: r.isMobile ? 4 : 6,
        horizontal: r.isMobile ? 2 : 4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r.cardRadius),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: r.contentPaddingH,
          vertical: r.isMobile ? 4 : 8,
        ),
        leading: CircleAvatar(
          radius: r.isMobile ? 18 : 22,
          backgroundColor: Colors.blue[100],
          child: Icon(Icons.group,
              color: Colors.blue[700], size: r.iconSizeMedium),
        ),
        title: Text(
          agent['group'],
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: r.cardTitleSize,
          ),
        ),
        subtitle: Text(
          'اضغط لعرض الوكلاء',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: r.cardSubtitleSize,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: r.iconSizeSmall),
        onTap: () => _filterAgents(agent['group']),
      ),
    );
  }

  Widget _buildAgentsCard(Map<String, dynamic> agent, ResponsiveHelper r) {
    final agentsList = _safeAgentsList(agent);

    if (agentsList.isEmpty) {
      return Card(
        child: ListTile(
          title: Text('لا توجد وكلاء في هذه المجموعة',
              style: TextStyle(fontSize: r.bodySize)),
        ),
      );
    }

    return Card(
      elevation: 2,
      margin: EdgeInsets.symmetric(
        vertical: r.isMobile ? 4 : 6,
        horizontal: r.isMobile ? 2 : 4,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(r.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(r.cardPadding),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(r.cardRadius),
                topRight: Radius.circular(r.cardRadius),
              ),
            ),
            child: Text(
              'مجموعة: ${agent['group']}',
              style: TextStyle(
                fontSize: r.cardTitleSize,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
          ),
          ...agentsList.map((entry) {
            final agentInfo = _safeAgentInfo(entry.value);
            return ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: r.contentPaddingH,
                vertical: r.isMobile ? 2 : 4,
              ),
              leading: CircleAvatar(
                radius: r.isMobile ? 16 : 20,
                backgroundColor: Colors.green[100],
                child: Icon(Icons.person,
                    color: Colors.green[700], size: r.iconSizeSmall),
              ),
              title: Text(
                agentInfo['name']!,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: r.bodySize,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                agentInfo['phone']!,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontFamily: 'monospace',
                  fontSize: r.captionSize,
                ),
              ),
              trailing: SizedBox(
                width: r.isMobile ? 36 : 42,
                height: r.isMobile ? 36 : 42,
                child: Material(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _sendMessage(agentInfo['phone']!),
                    child: Icon(Icons.chat,
                        color: Colors.white, size: r.iconSizeSmall),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
