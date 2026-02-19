import 'package:flutter/material.dart';
import 'dart:async';
import 'home_page_tasks.dart';
import 'add_task_api_dialog.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../widgets/maintenance_messages_dialog.dart';

class TaskListScreen extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;

  const TaskListScreen({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
  });

  @override
  State<TaskListScreen> createState() => _TaskListScreenState();
}

class _TaskListScreenState extends State<TaskListScreen>
    with WidgetsBindingObserver {
  List<Task> _tasks = []; // قائمة المهام
  bool _isLoading = true; // حالة التحميل
  bool _isRefreshing = false; // حالة التحديث
  Timer? _refreshTimer; // ����ؤقت التحديث التلقائي
  DateTime? _lastRefresh; // آخر وقت تحديث
  final GlobalKey<HomePageTasksState> _homePageTasksKey =
      GlobalKey<HomePageTasksState>();

  // إعدادات التحديث
  static const Duration _refreshInterval =
      Duration(seconds: 60); // تحديث كل 60 ثانية
  static const Duration _minimumRefreshGap =
      Duration(seconds: 5); // حد أدنى بين التحديثات
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // مراقبة دورة حياة ال��طبيق
    _fetchTasks(); // جلب المهام عند بداية التحميل
    _startAutoRefresh(); // بدء التحديث التلقائي
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // إزالة المراقب
    _refreshTimer?.cancel(); // إلغاء المؤقت عند إغلاق الشاشة
    super.dispose();
  }

  @override
  void deactivate() {
    // إيقاف المؤقت عند مغادرة الصفحة (Navigator.push فوقها)
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    // إعادة تشغيل المؤقت عند العودة للصفحة
    _startAutoRefresh();
    _fetchTasks(showLoadingIndicator: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // عند العودة للتطبيق من ��لخلفية، قم بتحديث المهام
    if (state == AppLifecycleState.resumed) {
      print('🔄 التطبيق عاد للمقدمة - تحديث المهام...');
      _fetchTasks(showLoadingIndicator: false);
    }
  }

  /// بدء التحديث التلقائي
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(_refreshInterval, (timer) {
      if (mounted) {
        _fetchTasks(showLoadingIndicator: false); // تحديث بدون مؤشر تحميل
      }
    });
  }

  /// إيقاف وإعادة تشغيل التحديث التلقائي
  void _resetAutoRefresh() {
    _refreshTimer?.cancel();
    _startAutoRefresh();
  }

  /// جلب المهام من الخادم
  Future<void> _fetchTasks({bool showLoadingIndicator = true}) async {
    try {
      // تحديث حالة التحميل إذا كان مطلوباً
      if (showLoadingIndicator && mounted) {
        setState(() {
          _isLoading = true;
        });
      } else if (mounted) {
        setState(() {
          _isRefreshing = true;
        });
      }

      // تحديث آخر وقت تحديث
      _lastRefresh = DateTime.now();

      // فلترة من السيرفر حسب دور المستخدم
      // الفني ← مهامه فقط، الليدر ← قسمه فقط، المدير ← الكل
      final String? techFilter =
          widget.permissions == 'فني' ? widget.username : null;
      final String? deptFilter =
          widget.permissions == 'ليدر' ? widget.department : null;

      final response = await TaskApiService.instance.getRequests(
        pageSize: 200,
        technician: techFilter,
        department: deptFilter,
      );
      final List<dynamic> items =
          response['data'] ?? response['Items'] ?? response['items'] ?? [];
      final tasks = items
          .map((item) => Task.fromApiResponse(item as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      setState(() {
        _tasks = tasks;
        // فرز المهام: الأحدث (حسب closedAt إن وجدت وإلا createdAt) في الأعلى
        _tasks.sort((a, b) {
          final da = a.closedAt ?? a.createdAt;
          final db = b.closedAt ?? b.createdAt;
          return db.compareTo(da); // تنازلي
        });
        _isLoading = false;
        _isRefreshing = false;
      });

      print('✅ تم تحديث ${tasks.length} مهمة في ${DateTime.now()}');
    } catch (e) {
      print('❌ خطأ في جلب المهام: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });

      // إظهار رسالة خطأ فقط في التحديث اليدوي
      if (showLoadingIndicator) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء جلب المهام: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// تحديث فوري للمهام
  Future<void> _refreshTasksImmediately() async {
    // تحقق من الحد الأدنى بين التحديثات
    if (_lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < _minimumRefreshGap) {
      print('⏰ تم تجاهل التحديث - الحد الأدنى للوقت لم يمر بعد');
      return;
    }

    // إعادة تشغيل مؤقت التحديث التلقائي
    _resetAutoRefresh();

    // جلب المهام فوراً بدون مؤشر تحميل
    await _fetchTasks(showLoadingIndicator: false);
  }

  // دالة لتحديث المهمة عند تغيير الحالة
  // ملاحظة: التحديث في API يتم من task_card._updateStatusViaApi
  // هنا فقط نحدث الحالة المحلية
  void _handleTaskStatusChanged(Task updatedTask) {
    if (!mounted) return;
    setState(() {
      final index = _tasks.indexWhere((task) => task.id == updatedTask.id);
      if (index != -1) {
        _tasks[index] = updatedTask;
      }
      // إعادة الفرز بعد التغيير
      _tasks.sort((a, b) {
        final da = a.closedAt ?? a.createdAt;
        final db = b.closedAt ?? b.createdAt;
        return db.compareTo(da);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _fetchTasks(showLoadingIndicator: false);
                print('🔄 تم التحديث اليدوي للمهام');
              },
              child: HomePageTasks(
                key: _homePageTasksKey,
                username: widget.username,
                permissions: widget.permissions,
                department: widget.department,
                center: widget.center,
                currentUserRole: widget.permissions,
                tasks: _tasks, // تمرير قائمة المهام بدون أزرار تصفية
                onTaskStatusChanged:
                    _handleTaskStatusChanged, // تمرير دالة تحديث المهمة
                onShowMenu: _showMenu,
                onShowFilter: _showFilter,
                onRefresh: () => _fetchTasks(showLoadingIndicator: false),
              ),
            ),
    );
  }

  // عرض نافذة إضافة مهمة جديدة عبر API
  void _showAddTaskDialog(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AddTaskApiDialog(
          currentUsername: widget.username,
          currentUserRole: widget.permissions,
          currentUserDepartment: widget.department,
          onTaskCreated: (taskData) {
            // تحديث القائمة بعد إضافة مهمة
            _fetchTasks(showLoadingIndicator: false);

            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text('تم إضافة المهمة بنجاح'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          },
        );
      },
    );
  }

  /// إظهار القائمة الجانبية
  void _showMenu() {
    _homePageTasksKey.currentState?.openDrawer();
  }

  /// إظهار نافذة التصفية
  void _showFilter() {
    _homePageTasksKey.currentState?.showFilterPopup();
  }

  /// إظهار حوار إعدادات رسائل الصيانة
  void _showMaintenanceMessagesDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => MaintenanceMessagesDialog(
        currentUserName: widget.username,
      ),
    );

    // إذا تم حفظ الرسائل بنجاح، عرض رسالة تأكيد
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث رسائل الصيانة بنجاح'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
}

class NavigationItem {
  final String title;
  final IconData icon;
  final Color color;
  final String status;

  const NavigationItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.status,
  });
}
