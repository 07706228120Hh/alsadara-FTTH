import 'package:flutter/material.dart';
import 'dart:async';
import 'home_page_tasks.dart';
import 'add_task_api_dialog.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../services/api/api_client.dart';
import '../services/notification_service.dart';
import '../services/in_app_notification_service.dart';
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
  Timer? _refreshTimer; // مؤقت التحديث التلقائي
  DateTime? _lastRefresh; // آخر وقت تحديث
  final GlobalKey<HomePageTasksState> _homePageTasksKey =
      GlobalKey<HomePageTasksState>();

  // تتبع المهام الجديدة للإشعارات
  Set<String> _knownTaskIds = {};
  bool _isFirstLoad = true;

  // Pagination
  int _currentPage = 1;
  static const int _pageSize = 500;
  bool _hasMorePages = true;
  bool _isLoadingMore = false;

  // إعدادات التحديث
  static const Duration _refreshInterval =
      Duration(seconds: 20); // تحديث كل 20 ثانية
  static const Duration _minimumRefreshGap =
      Duration(seconds: 5); // حد أدنى بين التحديثات
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchTasks();
    _startAutoRefresh();
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
    // إعادة تشغيل المؤقت عند العودة للصفحة + جلب فوري (مرة واحدة فقط)
    _startAutoRefresh(fetchImmediately: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // عند العودة من الخلفية: إعادة تشغيل المؤقت + جلب فوري
      _startAutoRefresh(fetchImmediately: true);
    } else if (state == AppLifecycleState.paused) {
      // إيقاف المؤقت عند الذهاب للخلفية لتوفير الموارد
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  /// بدء التحديث التلقائي — يلغي أي مؤقت سابق أولاً
  void _startAutoRefresh({bool fetchImmediately = false}) {
    _refreshTimer?.cancel();
    if (fetchImmediately) {
      _fetchTasks(showLoadingIndicator: false);
    }
    _refreshTimer = Timer.periodic(_refreshInterval, (timer) {
      if (mounted) {
        _fetchTasks(showLoadingIndicator: false);
      }
    });
  }

  /// إيقاف وإعادة تشغيل التحديث التلقائي
  void _resetAutoRefresh() {
    _refreshTimer?.cancel();
    _startAutoRefresh();
  }

  /// فلاتر السيرفر حسب دور المستخدم
  bool get _isTechnician =>
      widget.permissions != 'مدير' && widget.permissions != 'ليدر';

  String? get _techFilter {
    return _isTechnician ? widget.username : null;
  }

  /// الفني يحتاج أيضاً يرى المهام التي أنشأها (حتى لو لقسم آخر)
  String? get _createdByFilter {
    return _isTechnician ? widget.username : null;
  }

  String? get _deptFilter {
    if (widget.permissions != 'ليدر') return null;
    // دعم أقسام متعددة مفصولة بفاصلة
    return widget.department.isNotEmpty ? widget.department : null;
  }

  /// جلب المهام من الخادم (الصفحة الأولى أو تحديث)
  Future<void> _fetchTasks({bool showLoadingIndicator = true}) async {
    try {
      if (showLoadingIndicator && mounted) {
        setState(() => _isLoading = true);
      } else if (mounted) {
        setState(() => _isRefreshing = true);
      }

      _lastRefresh = DateTime.now();

      debugPrint('📡 جلب المهام: tech=$_techFilter, created=$_createdByFilter, dept=$_deptFilter, token=${ApiClient.instance.authToken != null ? "موجود" : "❌ غير موجود"}');
      final response = await TaskApiService.instance.getRequests(
        page: 1,
        pageSize: _pageSize,
        technician: _techFilter,
        department: _deptFilter,
        createdByName: _createdByFilter,
      );
      debugPrint('📡 استجابة المهام: success=${response['success']}, items=${(response['data'] as List?)?.length ?? 0}');
      final List<dynamic> items =
          response['data'] ?? response['Items'] ?? response['items'] ?? [];
      final tasks = items
          .map((item) => Task.fromApiResponse(item as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      // كشف المهام الجديدة وإرسال إشعار محلي مفصّل
      if (!_isFirstLoad) {
        final newTasks = tasks.where((t) => !_knownTaskIds.contains(t.guid)).toList();
        for (final task in newTasks) {
          NotificationService.notifyNewTask(
            task: task,
            assignedTo: task.technician.isNotEmpty ? task.technician : 'غير محدد',
            notifyUsers: [widget.username],
          );
          // بانر داخل التطبيق
          InAppNotificationService.instance.show(
            title: 'مهمة جديدة: ${task.title}',
            body: '${task.department} — ${task.username.isNotEmpty ? task.username : "بدون اسم"} • الفني: ${task.technician.isNotEmpty ? task.technician : "غير محدد"}',
            type: InAppNotificationType.task,
            referenceId: task.guid,
          );
        }
      }
      _knownTaskIds = tasks.map((t) => t.guid).toSet();
      _isFirstLoad = false;

      setState(() {
        _tasks = tasks;
        _currentPage = 1;
        _hasMorePages = tasks.length >= _pageSize;
        _tasks.sort((a, b) {
          final da = a.closedAt ?? a.createdAt;
          final db = b.closedAt ?? b.createdAt;
          return db.compareTo(da);
        });
        _isLoading = false;
        _isRefreshing = false;
      });
    } catch (e, stack) {
      debugPrint('❌ خطأ في جلب المهام: $e');
      debugPrint('📋 Stack: $stack');
      if (!mounted) return;
      setState(() { _isLoading = false; _isRefreshing = false; });
      if (showLoadingIndicator) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء جلب المهام'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// تحميل المزيد من المهام (الصفحة التالية)
  Future<void> loadMoreTasks() async {
    if (_isLoadingMore || !_hasMorePages) return;
    _isLoadingMore = true;

    try {
      final nextPage = _currentPage + 1;
      final response = await TaskApiService.instance.getRequests(
        page: nextPage,
        pageSize: _pageSize,
        technician: _techFilter,
        department: _deptFilter,
        createdByName: _createdByFilter,
      );
      final List<dynamic> items =
          response['data'] ?? response['Items'] ?? response['items'] ?? [];
      final newTasks = items
          .map((item) => Task.fromApiResponse(item as Map<String, dynamic>))
          .toList();

      if (!mounted) return;

      // إضافة المهام الجديدة (بدون تكرار)
      final existingIds = _tasks.map((t) => t.guid).toSet();
      final uniqueNew = newTasks.where((t) => !existingIds.contains(t.guid)).toList();

      setState(() {
        _tasks.addAll(uniqueNew);
        _currentPage = nextPage;
        _hasMorePages = newTasks.length >= _pageSize;
        _tasks.sort((a, b) {
          final da = a.closedAt ?? a.createdAt;
          final db = b.closedAt ?? b.createdAt;
          return db.compareTo(da);
        });
      });

      _knownTaskIds.addAll(uniqueNew.map((t) => t.guid));
    } catch (_) {}
    _isLoadingMore = false;
  }

  /// تحديث فوري للمهام
  Future<void> _refreshTasksImmediately() async {
    // تحقق من الحد الأدنى بين التحديثات
    if (_lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < _minimumRefreshGap) {
      debugPrint('⏰ تم تجاهل التحديث - الحد الأدنى للوقت لم يمر بعد');
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
                debugPrint('🔄 تم التحديث اليدوي للمهام');
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
                onLoadMore: loadMoreTasks,
                hasMorePages: _hasMorePages,
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
