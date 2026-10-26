import 'package:flutter/material.dart';
import 'dart:async';
import '../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import 'home_page_tasks.dart';
import 'add_task_api_dialog.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../services/api/api_client.dart';
import '../services/notification_service.dart';
import '../services/in_app_notification_service.dart';
import '../services/task_signalr_service.dart';
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
  StreamSubscription? _signalRSubscription; // اشتراك SignalR
  DateTime? _lastRefresh; // آخر وقت تحديث
  final GlobalKey<HomePageTasksState> _homePageTasksKey =
      GlobalKey<HomePageTasksState>();

  // تتبع المهام الجديدة للإشعارات
  Set<String> _knownTaskIds = {};
  bool _isFirstLoad = true;

  // Pagination
  int _currentPage = 1;
  static const int _pageSize = 50;
  bool _hasMorePages = true;
  bool _isLoadingMore = false;

  /// Server statuses of the «مفتوحة» + «قيد التنفيذ» buckets. Page 1 holds only
  /// the newest 50 tasks by creation date, so an older task that is still open
  /// (or was reassigned today) never reached the technician's list. These are
  /// fetched separately and merged. The API filters one status per request.
  static const List<String> _activeStatuses = [
    'Pending',
    'Reviewing',
    'Approved',
    'Assigned',
    'InProgress',
    'OnHold',
  ];
  static const int _activePageSize = 200;
  static const Duration _activeRefreshInterval = Duration(minutes: 3);
  List<Task> _activeCache = [];
  DateTime? _lastActiveFetch;

  // Refresh coalescing
  bool _fetchInFlight = false;
  bool _refetchQueued = false;
  bool _queuedForceActive = false;
  bool _fetchErrorShown = false;
  Timer? _signalRDebounce;

  // إعدادات التحديث
  static const Duration _refreshInterval =
      Duration(seconds: 60); // fallback — SignalR يتكفل بالتحديث الفوري
  static const Duration _minimumRefreshGap =
      Duration(seconds: 5); // حد أدنى بين التحديثات
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchTasks();
    _startAutoRefresh();
    // SignalR — تحديث فوري عند أي تغيير
    TaskSignalRService.instance.connect();
    _signalRSubscription = TaskSignalRService.instance.onAnyChange.listen((_) {
      // Debounce bursts of events into one refresh.
      _signalRDebounce?.cancel();
      _signalRDebounce = Timer(const Duration(seconds: 2), () {
        if (mounted) _fetchTasks(showLoadingIndicator: false);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // إزالة المراقب
    _refreshTimer?.cancel(); // إلغاء المؤقت عند إغلاق الشاشة
    _signalRDebounce?.cancel();
    _signalRSubscription?.cancel();
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

  /// Fetches every active task for the current role filter (see [_activeStatuses]).
  /// Returns the tasks and whether every status request succeeded.
  Future<(List<Task>, bool)> _fetchActiveTasks() async {
    final responses = await Future.wait(_activeStatuses.map((s) async {
      try {
        return await TaskApiService.instance.getRequests(
          page: 1,
          pageSize: _activePageSize,
          status: s,
          technician: _techFilter,
          department: _deptFilter,
          createdByName: _createdByFilter,
        );
      } catch (_) {
        return const <String, dynamic>{};
      }
    }));
    final result = <Task>[];
    var allOk = true;
    for (final r in responses) {
      if (r['success'] != true) {
        allOk = false;
        continue;
      }
      final List<dynamic> items = r['data'] ?? r['Items'] ?? r['items'] ?? [];
      result.addAll(
          items.map((i) => Task.fromApiResponse(i as Map<String, dynamic>)));
    }
    return (result, allOk);
  }

  /// Returns the active tasks, hitting the server at most every
  /// [_activeRefreshInterval] unless [force] (first load, pull-to-refresh,
  /// after a status change). The 60s timer and SignalR reuse the cache so a
  /// refresh stays one request instead of seven.
  Future<List<Task>> _getActiveTasks({required bool force}) async {
    final now = DateTime.now();
    final due = force ||
        _lastActiveFetch == null ||
        now.difference(_lastActiveFetch!) >= _activeRefreshInterval;
    if (!due) return _activeCache;
    final (fetched, allOk) = await _fetchActiveTasks();
    if (allOk) {
      _activeCache = fetched;
      _lastActiveFetch = now;
    } else {
      // Keep previously known active tasks of the failed statuses instead of
      // letting them vanish (and later re-appear as "new" notifications).
      final ids = fetched.map((t) => t.guid).toSet();
      _activeCache = [...fetched, ..._activeCache.where((t) => ids.add(t.guid))];
    }
    return _activeCache;
  }

  /// جلب المهام من الخادم (الصفحة الأولى أو تحديث)
  Future<void> _fetchTasks(
      {bool showLoadingIndicator = true, bool forceActive = false}) async {
    // Coalesce overlapping refreshes (timer + SignalR + resume + actions).
    if (_fetchInFlight) {
      _refetchQueued = true;
      _queuedForceActive = _queuedForceActive || forceActive;
      return;
    }
    _fetchInFlight = true;
    try {
      if (showLoadingIndicator && mounted) {
        setState(() => _isLoading = true);
      } else if (mounted) {
        setState(() => _isRefreshing = true);
      }

      _lastRefresh = DateTime.now();

      debugPrint('📡 جلب المهام: tech=$_techFilter, created=$_createdByFilter, dept=$_deptFilter, token=${ApiClient.instance.authToken != null ? "موجود" : "❌ غير موجود"}');
      // اللوحة تأخذ أرقامها من الخادم (getSummary) → لا داعي لتحميل كل المهام دفعة.
      // القوائم تعمل عبر الترقيم + التحميل الكسول (loadMoreTasks عند 80% تمرير).
      final pageFuture = TaskApiService.instance.getRequests(
        page: 1,
        pageSize: _pageSize,
        technician: _techFilter,
        department: _deptFilter,
        createdByName: _createdByFilter,
      );
      final activeFuture =
          _getActiveTasks(force: forceActive || _isFirstLoad);
      final response = await pageFuture;
      final activeTasks = await activeFuture;
      debugPrint('📡 استجابة المهام: success=${response['success']}, items=${(response['data'] as List?)?.length ?? 0}, active=${activeTasks.length}');

      if (!mounted) return;

      // A rejected request (e.g. 403 missing «tasks.view») used to show
      // «لا توجد مهام حاليا» as if the technician had no tasks. Keep the
      // current list and tell the user why.
      if (response['success'] != true) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
        // Once per failure streak — not on every 60s timer tick.
        if (showLoadingIndicator || !_fetchErrorShown) {
          _fetchErrorShown = true;
          final code = response['statusCode'];
          final msg = code == 403
              ? 'لا تملك صلاحية عرض المهام — راجع مدير النظام'
              : (response['message']?.toString() ?? 'تعذّر جلب المهام');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: SdColors.danger),
          );
        }
        return;
      }
      _fetchErrorShown = false;

      final List<dynamic> items =
          response['data'] ?? response['Items'] ?? response['items'] ?? [];
      final pageTasks = items
          .map((item) => Task.fromApiResponse(item as Map<String, dynamic>))
          .toList();
      final pageIds = pageTasks.map((t) => t.guid).toSet();
      final tasks = [
        ...pageTasks,
        ...activeTasks.where((t) => pageIds.add(t.guid)),
      ];

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
      // Cumulative: a task that drops out of one fetch (failed request, page
      // window) must not be announced as "new" again when it comes back.
      _knownTaskIds.addAll(tasks.map((t) => t.guid));
      _isFirstLoad = false;

      setState(() {
        _tasks = tasks;
        _currentPage = 1;
        _hasMorePages = pageTasks.length >= _pageSize;
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
          const SnackBar(content: Text('حدث خطأ أثناء جلب المهام'), backgroundColor: SdColors.danger),
        );
      }
    } finally {
      _fetchInFlight = false;
      if (_refetchQueued && mounted) {
        final force = _queuedForceActive;
        _refetchQueued = false;
        _queuedForceActive = false;
        _fetchTasks(showLoadingIndicator: false, forceActive: force);
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
        // New list instance: HomePageTasks.didUpdateWidget only recomputes when
        // the list reference changes, so in-place addAll never showed page 2+.
        _tasks = [..._tasks, ...uniqueNew];
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
                await _fetchTasks(
                    showLoadingIndicator: false, forceActive: true);
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
                // After a status change: refresh the active cache too, or a
                // just-completed old task would come back as open from it.
                onRefresh: () =>
                    _fetchTasks(showLoadingIndicator: false, forceActive: true),
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
            _fetchTasks(showLoadingIndicator: false, forceActive: true);

            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('تم إضافة المهمة بنجاح'),
                backgroundColor: SdColors.success,
                duration: Duration(seconds: 3),
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
          backgroundColor: SdColors.success,
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
