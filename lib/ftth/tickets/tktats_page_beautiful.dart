import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'tktat_details_page.dart';
import '../../utils/status_translator.dart';

class TKTATsPage extends StatefulWidget {
  final String authToken;
  const TKTATsPage({super.key, required this.authToken});

  @override
  State<TKTATsPage> createState() => _TKTATsPageState();
}

class _TKTATsPageState extends State<TKTATsPage> {
  List<dynamic> tktats = [];
  List<dynamic> filteredTKTATs = [];
  bool isLoading = true;
  String message = "";
  int totalTKTATs = 0;
  int currentPage = 1;
  String selectedTicketType = 'all';
  String filterCategory = 'zone';
  String filterText = "";
  Timer? refreshTimer;
  FlutterLocalNotificationsPlugin localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool isFilterVisible = false;

  @override
  void initState() {
    super.initState();
    fetchTKTATs();
    setupNotifications();
    startAutoRefresh();
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  void setupNotifications() {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    localNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> showNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'tktats_channel',
      'TKTATs Updates',
      channelDescription: 'Notification channel for TKTAT updates',
      importance: Importance.high,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await localNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  void startAutoRefresh() {
    Timer.periodic(Duration(seconds: 30), (timer) {
      if (mounted) {
        fetchTKTATs(showNotificationOnNewTKTATs: true);
      }
    });
  }

  Future<void> fetchTKTATs({bool showNotificationOnNewTKTATs = false}) async {
    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      final url = Uri.parse(
          'https://api.ftth.iq/api/support/tickets?pageSize=50&pageNumber=$currentPage&sortCriteria.property=createdAt&sortCriteria.direction=desc&status=0&hierarchyLevel=0');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer ${widget.authToken}',
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newTKTATs = data['items'] ?? [];

        if (showNotificationOnNewTKTATs && newTKTATs.length > tktats.length) {
          await showNotification(
            'TKTATs جديدة!',
            'هناك ${newTKTATs.length - tktats.length} TKTATs جديدة متاحة.',
          );
        }

        setState(() {
          tktats = newTKTATs;
          filterTKTATs();
          totalTKTATs = data['totalCount'] ?? 0;
          isLoading = false;
          message = newTKTATs.isEmpty ? "لا توجد TKTATs متاحة" : "";
        });
      } else {
        setState(() {
          message = "فشل جلب البيانات: ${response.statusCode}";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        message = "حدث خطأ أثناء جلب البيانات: $e";
        isLoading = false;
      });
    }
  }

  void filterTKTATs() {
    if (filterText.isNotEmpty) {
      filteredTKTATs = tktats.where((tktat) {
        final status = canonicalStatusKey(tktat['status']?.toString());
        final valueToFilter =
            tktat[filterCategory]?.toString().toLowerCase() ?? '';
        final matchesFilterText =
            valueToFilter.contains(filterText.toLowerCase());

        if (selectedTicketType == 'all') {
          return matchesFilterText;
        } else if (selectedTicketType == 'company' && status == 'in progress') {
          return matchesFilterText;
        } else if (selectedTicketType == 'agent' && status != 'in progress') {
          return matchesFilterText;
        }
        return false;
      }).toList();
    } else {
      filteredTKTATs = tktats;
    }
  }

  void resetFilters() {
    setState(() {
      filterText = "";
      selectedTicketType = 'all';
      filteredTKTATs = tktats;
    });
  }

  void nextPage() {
    setState(() {
      currentPage++;
    });
    fetchTKTATs();
  }

  void previousPage() {
    if (currentPage > 1) {
      setState(() {
        currentPage--;
      });
      fetchTKTATs();
    }
  }

  void navigateToTaskDetails(BuildContext context, dynamic task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TKTATDetailsPage(
          tktat: task,
          authToken: widget.authToken,
        ),
      ),
    );
  }

  void toggleFilterVisibility() {
    setState(() {
      isFilterVisible = !isFilterVisible;
    });
  }

  // Helper functions
  Color getStatusColor(String? status) => statusColor(status);

  IconData getStatusIcon(String? status) {
    final s = canonicalStatusKey(status);
    switch (s) {
      case 'in progress':
        return Icons.hourglass_empty;
      case 'completed':
        return Icons.check_circle;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      case 'new':
        return Icons.fiber_new;
      case 'assigned':
        return Icons.assignment_ind;
      default:
        return Icons.help_outline;
    }
  }

  Color getPriorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  int getCompanyTicketsCount() {
    return tktats.where((tktat) {
      final status = canonicalStatusKey(tktat['status']?.toString());
      return status == 'in progress';
    }).length;
  }

  int getAgentTicketsCount() {
    return tktats.where((tktat) {
      final status = canonicalStatusKey(tktat['status']?.toString());
      return status != 'in progress' && status.isNotEmpty;
    }).length;
  }

  String translateStatus(String status) => translateTicketStatus(status);

  String translatePriority(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
        return 'عالية';
      case 'medium':
        return 'متوسطة';
      case 'low':
        return 'منخفضة';
      default:
        return priority;
    }
  }

  String formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        toolbarHeight: 50,
        elevation: 0,
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Icon(Icons.task_alt, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              'TKTATs',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          Container(
            margin: EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(
                  isFilterVisible ? Icons.filter_list_off : Icons.filter_list),
              tooltip: isFilterVisible ? 'إخفاء الفلاتر' : 'إظهار الفلاتر',
              onPressed: toggleFilterVisibility,
              color: Colors.white,
              iconSize: 20,
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'إعادة تحميل الصفحة',
              onPressed: () async {
                setState(() => isLoading = true);
                await fetchTKTATs();
              },
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[50]!, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              // Filter Section
              if (isFilterVisible) _buildFilterSection(),

              // Content Area
              Expanded(child: _buildContentArea()),

              // Navigation Section
              _buildNavigationSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[600]!, Colors.blue[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'تصفية TKTATs',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: (value) {
                setState(() {
                  filterText = value;
                });
                filterTKTATs();
              },
              decoration: InputDecoration(
                hintText: 'ابحث في TKTATs...',
                prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              onPressed: resetFilters,
              icon: Icon(Icons.clear_all),
              label: Text('مسح الفلاتر'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[400],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    if (isLoading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
        ),
      );
    } else if (message.isNotEmpty) {
      return Center(
        child: Text(
          message,
          style: TextStyle(fontSize: 16, color: Colors.red[600]),
          textAlign: TextAlign.center,
        ),
      );
    } else if (filteredTKTATs.isEmpty) {
      return Center(
        child: Text(
          'لا توجد TKTATs متاحة',
          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
        ),
      );
    } else {
      return ListView.builder(
        itemCount: filteredTKTATs.length,
        itemBuilder: (context, index) {
          final tktat = filteredTKTATs[index];
          return _buildTKTATCard(tktat);
        },
      );
    }
  }

  Widget _buildTKTATCard(dynamic tktat) {
    final rawStatus = tktat['status']?.toString() ?? '';
    final title = tktat['title'] ?? 'بدون عنوان';

    return Container(
      margin: EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: getStatusColor(rawStatus).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            getStatusIcon(rawStatus),
            color: getStatusColor(rawStatus),
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          translateStatus(rawStatus),
          style: TextStyle(color: getStatusColor(rawStatus)),
        ),
        onTap: () => navigateToTaskDetails(context, tktat),
      ),
    );
  }

  Widget _buildNavigationSection() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton(
            onPressed: currentPage > 1 ? previousPage : null,
            child: Text('السابق'),
          ),
          Text('صفحة $currentPage'),
          ElevatedButton(
            onPressed: nextPage,
            child: Text('التالي'),
          ),
        ],
      ),
    );
  }
}
