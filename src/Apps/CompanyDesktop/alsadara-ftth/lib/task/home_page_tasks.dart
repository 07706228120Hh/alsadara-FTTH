import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/responsive_helper.dart';
import '../models/task.dart';
import 'task_card.dart';
import 'add_task_api_dialog.dart';
import '../pages/ftth/ftth_company_page.dart';
import 'reports_page.dart';
import 'technician_performance_page.dart';
import '../services/whatsapp_template_storage.dart';
import '../ftth/tasks/customer_search_connect_page.dart';
import '../services/task_api_service.dart';

class HomePageTasks extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;
  final String currentUserRole;
  final List<Task> tasks;
  final Function(Task) onTaskStatusChanged;
  final VoidCallback? onShowMenu;
  final VoidCallback? onShowFilter;
  final VoidCallback? onRefresh;
  final VoidCallback? onLoadMore;
  final bool hasMorePages;

  const HomePageTasks({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
    required this.currentUserRole,
    required this.tasks,
    required this.onTaskStatusChanged,
    this.onShowMenu,
    this.onShowFilter,
    this.onRefresh,
    this.onLoadMore,
    this.hasMorePages = true,
  });

  @override
  HomePageTasksState createState() => HomePageTasksState();
}

class HomePageTasksState extends State<HomePageTasks> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<Task> _currentTasks = [];
  List<Task> _filteredTasks = [];
  bool isLoading = false;
  String? errorMessage;
  int currentIndex = 0;

  // البحث
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isServerSearching = false;
  List<Task>? _serverSearchResults; // null = لا يوجد بحث سيرفر نشط

  // فلاتر متقدمة
  String? _filterDepartment;
  String? _filterTechnician;
  String? _filterPriority;
  String? _filterTaskType;

  // متغيرات الإشعارات الجديدة
  int newTasksCount = 0; // عدد المهام الجديدة
  List<Task> notifications = []; // قائمة الإشعارات
  bool showNotificationBadge = false; // لإظهار دائرة الإشعار الحمراء
  Set<String> seenTaskIds = <String>{}; // لتتبع المهام المرئية سابقاً
  // فلتر التاريخ: 'today' | 'yesterday' | 'all'
  String _dateFilter = 'today';

  // عرض مهام اليوم فقط في صفحة المكتملة
  bool _completedTodayOnly = false;
  // عرض مهام اليوم فقط في صفحة الملغية
  bool _cancelledTodayOnly = false;
  // فلتر التحصيل: الحالة والفني
  String _collectionStatusFilter = 'الكل'; // الكل، معلقة، مكتملة، متأخرة
  String? _collectionTechFilter;
  // فلتر "مهامي فقط" — للمدير والليدر لعرض المهام الموجهة لهم فقط
  bool _myTasksOnly = true;

  @override
  void initState() {
    super.initState();
    // استخدام المهام الممررة من task_list_screen مباشرة
    _currentTasks = widget.tasks;
    _applyPermissionFilter();
    _filterTasksByStatus(_getStatusByIndex(currentIndex));
  }

  @override
  void didUpdateWidget(HomePageTasks oldWidget) {
    super.didUpdateWidget(oldWidget);
    // تحديث المهام عند تغييرها من الأب (task_list_screen)
    if (oldWidget.tasks != widget.tasks) {
      setState(() {
        _currentTasks = widget.tasks;
        _applyPermissionFilter();
        _filterTasksByStatus(_getStatusByIndex(currentIndex));
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void showFilterPopup() {
    _showFilterPopup(context);
  }

  /// تحويل الدور من الإنجليزية إلى العربية
  String _normalizeRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
      case 'superadmin':
      case 'مدير':
        return 'مدير';
      case 'technicalleader':
      case 'leader':
      case 'ليدر':
        return 'ليدر';
      case 'technician':
      case 'فني':
        return 'فني';
      default:
        return role;
    }
  }

  /// تنظيف اسم القسم للمقارنة (إزالة "ال" التعريف والمسافات)
  String _normalizeDept(String dept) {
    var d = dept.trim().toLowerCase();
    if (d.startsWith('ال')) d = d.substring(2);
    return d;
  }

  /// تطبيق فلتر الصلاحيات على قائمة مهام — منطق موحّد لكل الأدوار
  List<Task> _applyRoleFilter(List<Task> tasks, {bool forceMyOnly = false}) {
    final role = _normalizeRole(widget.currentUserRole);
    final myOnly = forceMyOnly || _myTasksOnly;

    debugPrint('🔍 [RoleFilter] role=$role, username="${widget.username}", dept="${widget.department}", myOnly=$myOnly, tasksCount=${tasks.length}');

    // "مهامي فقط" — يعرض فقط المهام الموجهة للمستخدم أو التي أنشأها
    if (myOnly && (role == 'مدير' || role == 'ليدر')) {
      return tasks
          .where((task) =>
              task.technician == widget.username ||
              task.createdBy == widget.username)
          .toList();
    }

    if (role == 'مدير') {
      return tasks;
    } else if (role == 'ليدر') {
      // دعم أقسام متعددة مفصولة بفاصلة (مثلاً "الصيانة,الحسابات")
      final deptString = widget.department;
      final departments = deptString.isNotEmpty
          ? deptString.split(',').map((d) => _normalizeDept(d)).where((d) => d.isNotEmpty).toSet()
          : <String>{};
      final result = tasks
          .where((task) {
              final match = task.technician == widget.username ||
                  task.createdBy == widget.username ||
                  (departments.isNotEmpty && departments.contains(_normalizeDept(task.department)));
              return match;
          })
          .toList();
      debugPrint('🔍 [RoleFilter] ليدر: depts=$departments, ${tasks.length} → ${result.length}');
      return result;
    } else {
      // فني أو موظف عادي: المعيّنة له + التي أنشأها
      return tasks
          .where((task) =>
              task.technician == widget.username ||
              task.createdBy == widget.username)
          .toList();
    }
  }

  void _applyPermissionFilter() {
    setState(() {
      _filteredTasks = _applyRoleFilter(_currentTasks);

      _filteredTasks.sort((a, b) {
        final da = a.closedAt ?? a.createdAt;
        final db = b.closedAt ?? b.createdAt;
        return db.compareTo(da);
      });

      _filteredTasks = _applyDateFilter(_filteredTasks);
    });
  }

  void _filterTasksByStatus(String status) {
    setState(() {
      // إذا يوجد نتائج بحث من السيرفر، نعرضها مباشرة
      if (_serverSearchResults != null) {
        _filteredTasks = _serverSearchResults!;
        return;
      }
      if (status == 'اللوحة') {
        _applyPermissionFilter();
      } else if (status == 'تحصيل') {
        // فلتر مهام التحصيل
        var collectionTasks = _currentTasks
            .where((task) => task.title.contains('تحصيل مبلغ') || task.title.contains('استحصال مبلغ'))
            .toList();

        // فلتر الحالة الفرعي
        final now = DateTime.now();
        if (_collectionStatusFilter == 'معلقة') {
          collectionTasks = collectionTasks.where((t) => t.status == 'مفتوحة' || t.status == 'قيد التنفيذ').toList();
        } else if (_collectionStatusFilter == 'مكتملة غير مفعّل') {
          collectionTasks = collectionTasks.where((t) => t.status == 'مكتملة' && !t.notes.contains('[مفعّل]')).toList();
        } else if (_collectionStatusFilter == 'مكتملة مفعّل') {
          collectionTasks = collectionTasks.where((t) => t.status == 'مكتملة' && t.notes.contains('[مفعّل]')).toList();
        } else if (_collectionStatusFilter == 'متأخرة') {
          collectionTasks = collectionTasks.where((t) =>
              (t.status == 'مفتوحة' || t.status == 'قيد التنفيذ') &&
              now.difference(t.createdAt).inHours >= 24).toList();
        }

        // فلتر الفني
        if (_collectionTechFilter != null && _collectionTechFilter!.isNotEmpty) {
          collectionTasks = collectionTasks.where((t) => t.technician.trim() == _collectionTechFilter).toList();
        }

        // تبويب التحصيل يتأثر بفلتر الدور — الليدر يرى مهام قسمه فقط
        final savedMyOnly = _myTasksOnly;
        _myTasksOnly = false;
        _filteredTasks = _applyRoleFilter(collectionTasks);
        _myTasksOnly = savedMyOnly;
        _filteredTasks.sort((a, b) {
          final da = a.closedAt ?? a.createdAt;
          final db = b.closedAt ?? b.createdAt;
          return db.compareTo(da);
        });
        _filteredTasks = _applyDateFilter(_filteredTasks);
      } else {
        // فلتر الحالة ثم فلتر الصلاحيات (منطق موحّد)
        final statusFilteredTasks =
            _currentTasks.where((task) => task.status == status).toList();
        _filteredTasks = _applyRoleFilter(statusFilteredTasks);

        _filteredTasks.sort((a, b) {
          final da = a.closedAt ?? a.createdAt;
          final db = b.closedAt ?? b.createdAt;
          return db.compareTo(da);
        });

        // فلتر اليوم فقط للمكتملة والملغية
        if (status == 'مكتملة' && _completedTodayOnly) {
          final now = DateTime.now();
          _filteredTasks = _filteredTasks.where((t) {
            final d = (t.closedAt ?? t.createdAt);
            return d.year == now.year &&
                d.month == now.month &&
                d.day == now.day;
          }).toList();
        }
        if (status == 'ملغية' && _cancelledTodayOnly) {
          final now = DateTime.now();
          _filteredTasks = _filteredTasks.where((t) {
            final d = (t.closedAt ?? t.createdAt);
            return d.year == now.year &&
                d.month == now.month &&
                d.day == now.day;
          }).toList();
        }

        _filteredTasks = _applyDateFilter(_filteredTasks);
      }
    });
  }

  /// تطبيق فلتر التاريخ على قائمة المهام
  List<Task> _applyDateFilter(List<Task> tasks) {
    List<Task> result = tasks;
    if (_dateFilter != 'all') {
      final now = DateTime.now();
      final DateTime targetDate;
      if (_dateFilter == 'yesterday') {
        targetDate = now.subtract(const Duration(days: 1));
      } else {
        targetDate = now; // today
      }
      result = result.where((t) {
        final d = t.createdAt;
        return d.year == targetDate.year &&
            d.month == targetDate.month &&
            d.day == targetDate.day;
      }).toList();
    }
    // تطبيق البحث النصي
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((t) {
        return t.title.toLowerCase().contains(q) ||
            t.username.toLowerCase().contains(q) ||
            t.phone.contains(q) ||
            t.technician.toLowerCase().contains(q) ||
            t.id.contains(q) ||
            t.fbg.toLowerCase().contains(q) ||
            t.notes.toLowerCase().contains(q) ||
            t.agentName.toLowerCase().contains(q);
      }).toList();
    }
    // تطبيق الفلاتر المتقدمة
    if (_filterDepartment != null && _filterDepartment!.isNotEmpty) {
      result = result.where((t) => t.department == _filterDepartment).toList();
    }
    if (_filterTechnician != null && _filterTechnician!.isNotEmpty) {
      result = result.where((t) => t.technician == _filterTechnician).toList();
    }
    if (_filterPriority != null && _filterPriority!.isNotEmpty) {
      result = result.where((t) => t.priority == _filterPriority).toList();
    }
    if (_filterTaskType != null && _filterTaskType!.isNotEmpty) {
      result = result.where((t) => t.title == _filterTaskType).toList();
    }
    return result;
  }

  /// الحصول على القيم الفريدة من المهام لقوائم الفلتر
  List<String> _getUniqueDepartments() {
    return _currentTasks
        .map((t) => t.department)
        .where((d) => d.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> _getUniqueTechnicians() {
    return _currentTasks
        .map((t) => t.technician)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  List<String> _getUniqueTaskTypes() {
    return _currentTasks
        .map((t) => t.title)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  double _calculateTotalAmount(List<Task> tasks) {
    return tasks.fold(0, (sum, task) {
      // إزالة رمز $ وأي رموز أخرى غير مرغوب فيها من المبلغ
      String cleanAmount =
          task.amount.replaceAll('\$', '').replaceAll(',', '').trim();
      final amount = double.tryParse(cleanAmount) ?? 0;
      return sum + amount;
    });
  }

  /// الحصول على حالة المهمة حسب الفهرس
  String _getStatusByIndex(int index) {
    switch (index) {
      case 1:
        return 'مفتوحة';
      case 2:
        return 'قيد التنفيذ';
      case 3:
        return 'مكتملة';
      case 4:
        return 'ملغية';
      case 5:
        return 'تحصيل';
      default:
        return 'اللوحة';
    }
  }

  /// بناء واجهة اللوحة الرئيسية
  Widget _buildDashboardView() {
    int openTasks =
        _filteredTasks.where((task) => task.status == 'مفتوحة').length;
    int inProgressTasks =
        _filteredTasks.where((task) => task.status == 'قيد التنفيذ').length;
    int completedTasks =
        _filteredTasks.where((task) => task.status == 'مكتملة').length;
    int canceledTasks =
        _filteredTasks.where((task) => task.status == 'ملغية').length;
    int totalTasks = _filteredTasks.length;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width < 420 ? 8 : 20,
          vertical: MediaQuery.of(context).size.width < 420 ? 8 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 4 بطاقات إحصائية ──
          LayoutBuilder(builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            final isSmall = constraints.maxWidth < 420;
            final cardGap = isSmall ? 6.0 : 10.0;
            if (isMobile) {
              return Column(
                children: [
                  IntrinsicHeight(
                    child: Row(children: [
                      Expanded(
                          child: _buildStatCard('مفتوحة', openTasks, totalTasks,
                              const Color(0xFF3B82F6), Icons.inbox_rounded,
                              compact: true, tiny: isSmall)),
                      SizedBox(width: cardGap),
                      Expanded(
                          child: _buildStatCard(
                              'قيد التنفيذ',
                              inProgressTasks,
                              totalTasks,
                              const Color(0xFFF59E0B),
                              Icons.sync_rounded,
                              compact: true,
                              tiny: isSmall)),
                    ]),
                  ),
                  SizedBox(height: cardGap),
                  IntrinsicHeight(
                    child: Row(children: [
                      Expanded(
                          child: _buildStatCard(
                              'مكتملة',
                              completedTasks,
                              totalTasks,
                              const Color(0xFF10B981),
                              Icons.check_circle_rounded,
                              compact: true,
                              tiny: isSmall)),
                      SizedBox(width: cardGap),
                      Expanded(
                          child: _buildStatCard(
                              'ملغية',
                              canceledTasks,
                              totalTasks,
                              const Color(0xFFEF4444),
                              Icons.cancel_rounded,
                              compact: true,
                              tiny: isSmall)),
                    ]),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                    child: _buildStatCard('مفتوحة', openTasks, totalTasks,
                        const Color(0xFF3B82F6), Icons.inbox_rounded)),
                const SizedBox(width: 14),
                Expanded(
                    child: _buildStatCard(
                        'قيد التنفيذ',
                        inProgressTasks,
                        totalTasks,
                        const Color(0xFFF59E0B),
                        Icons.sync_rounded)),
                const SizedBox(width: 14),
                Expanded(
                    child: _buildStatCard('مكتملة', completedTasks, totalTasks,
                        const Color(0xFF10B981), Icons.check_circle_rounded)),
                const SizedBox(width: 14),
                Expanded(
                    child: _buildStatCard('ملغية', canceledTasks, totalTasks,
                        const Color(0xFFEF4444), Icons.cancel_rounded)),
              ],
            );
          }),
          const SizedBox(height: 14),

          // ── بطاقة توزيع المهام حسب الفني ──
          _buildTechnicianDistributionCard(),
        ],
      ),
    );
  }

  /// لوحة إحصائيات التحصيل
  Widget _buildCollectionStatsCard() {
    final collectionTasks = _currentTasks.where((t) =>
        t.title.contains('تحصيل مبلغ') || t.title.contains('استحصال مبلغ')).toList();
    if (collectionTasks.isEmpty) return const SizedBox.shrink();

    final pending = collectionTasks.where((t) => t.status == 'مفتوحة' || t.status == 'قيد التنفيذ').toList();
    final completed = collectionTasks.where((t) => t.status == 'مكتملة').toList();
    final now = DateTime.now();
    final completedToday = completed.where((t) {
      final d = t.closedAt ?? t.createdAt;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).toList();

    // حساب المبالغ
    double totalPending = 0;
    for (final t in pending) {
      final amt = double.tryParse(t.amount.replaceAll(RegExp(r'[^\d]'), ''));
      if (amt != null) totalPending += amt;
    }
    double totalCompletedToday = 0;
    for (final t in completedToday) {
      final amt = double.tryParse(t.amount.replaceAll(RegExp(r'[^\d]'), ''));
      if (amt != null) totalCompletedToday += amt;
    }

    // المتأخرة (> 24 ساعة)
    final overdue = pending.where((t) => now.difference(t.createdAt).inHours >= 24).length;

    // تقرير الفنيين
    final Map<String, Map<String, dynamic>> techReport = {};
    for (final t in collectionTasks) {
      final tech = t.technician.trim();
      if (tech.isEmpty) continue;
      techReport.putIfAbsent(tech, () => {'pending': 0, 'done': 0, 'total': 0, 'amount': 0.0, 'amountDone': 0.0});
      techReport[tech]!['total'] = (techReport[tech]!['total'] as int) + 1;
      final amt = double.tryParse(t.amount.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
      if (t.status == 'مكتملة') {
        techReport[tech]!['done'] = (techReport[tech]!['done'] as int) + 1;
        techReport[tech]!['amountDone'] = (techReport[tech]!['amountDone'] as double) + amt;
      } else if (t.status == 'مفتوحة' || t.status == 'قيد التنفيذ') {
        techReport[tech]!['pending'] = (techReport[tech]!['pending'] as int) + 1;
      }
      techReport[tech]!['amount'] = (techReport[tech]!['amount'] as double) + amt;
    }

    final isSmall = MediaQuery.of(context).size.width < 420;
    final fs = isSmall ? 11.0 : 13.0;

    return Container(
      padding: EdgeInsets.all(isSmall ? 10 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF8F00), width: 1.5),
        boxShadow: [BoxShadow(color: const Color(0xFFFF8F00).withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // العنوان
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.attach_money, color: Color(0xFFFF8F00), size: 20),
          ),
          const SizedBox(width: 10),
          Text('إحصائيات التحصيل', style: TextStyle(fontSize: isSmall ? 14 : 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(12)),
            child: Text('${collectionTasks.length} مهمة', style: TextStyle(fontSize: 11, color: const Color(0xFFFF8F00), fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 14),

        // ── إحصائيات سريعة ──
        Row(children: [
          Expanded(child: _collectionStatTile('معلقة', '${pending.length}', Colors.orange, Icons.schedule, isSmall)),
          SizedBox(width: isSmall ? 4 : 8),
          Expanded(child: _collectionStatTile('محصّلة اليوم', '${completedToday.length}', Colors.green, Icons.check_circle, isSmall)),
          SizedBox(width: isSmall ? 4 : 8),
          Expanded(child: _collectionStatTile('متأخرة', '$overdue', overdue > 0 ? Colors.red : Colors.grey, Icons.warning_amber, isSmall)),
        ]),
        SizedBox(height: isSmall ? 6 : 10),
        Row(children: [
          Expanded(child: _collectionStatTile('مبالغ معلقة', '${totalPending.toStringAsFixed(0)} د.ع', Colors.orange, Icons.account_balance_wallet, isSmall)),
          SizedBox(width: isSmall ? 4 : 8),
          Expanded(child: _collectionStatTile('محصّل اليوم', '${totalCompletedToday.toStringAsFixed(0)} د.ع', Colors.green, Icons.paid, isSmall)),
        ]),

        // ── تقرير الفنيين ──
        if (techReport.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Text('تحصيلات الفنيين', style: TextStyle(fontSize: fs + 1, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          ...techReport.entries.map((e) {
            final name = e.key;
            final data = e.value;
            final total = data['total'] as int;
            final done = data['done'] as int;
            final pend = data['pending'] as int;
            final amtDone = data['amountDone'] as double;
            final pct = total > 0 ? (done / total * 100).round() : 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                CircleAvatar(
                  radius: isSmall ? 12 : 14,
                  backgroundColor: const Color(0xFFFFF3E0),
                  child: Text(name.isNotEmpty ? name[0] : '?', style: TextStyle(fontSize: isSmall ? 10 : 12, fontWeight: FontWeight.bold, color: const Color(0xFFFF8F00))),
                ),
                SizedBox(width: isSmall ? 6 : 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: TextStyle(fontSize: fs, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      isSmall
                          ? '$done/$total ($pct%) — $pend معلق'
                          : 'محصّل: $done/$total ($pct%) — معلق: $pend — مبلغ: ${amtDone.toStringAsFixed(0)} د.ع',
                      style: TextStyle(fontSize: isSmall ? 9 : fs - 1, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
                ),
                SizedBox(
                  width: isSmall ? 30 : 40,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total > 0 ? done / total : 0,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation(pct >= 80 ? Colors.green : (pct >= 50 ? Colors.orange : Colors.red)),
                      minHeight: isSmall ? 4 : 6,
                    ),
                  ),
                ),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _collectionStatTile(String label, String value, Color color, IconData icon, [bool isSmall = false]) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: isSmall ? 6 : 8, horizontal: isSmall ? 4 : 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: isSmall ? 14 : 18),
        SizedBox(height: isSmall ? 2 : 4),
        Text(value, style: TextStyle(fontSize: isSmall ? 10 : 13, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: TextStyle(fontSize: isSmall ? 8 : 10, color: color.withValues(alpha: 0.8)), textAlign: TextAlign.center),
      ]),
    );
  }

  /// بطاقة توزيع المهام على الفنيين
  Widget _buildTechnicianDistributionCard() {
    // تجميع المهام حسب الفني مع القسم
    final Map<String, Map<String, dynamic>> techStats = {};
    for (final task in _filteredTasks) {
      final name = task.technician.trim();
      if (name.isEmpty) continue;
      techStats.putIfAbsent(
          name,
          () => {
                'total': 0,
                'open': 0,
                'progress': 0,
                'done': 0,
                'canceled': 0,
                'department': task.department.trim(),
              });
      techStats[name]!['total'] = (techStats[name]!['total'] as int) + 1;
      if (task.status == 'مفتوحة') {
        techStats[name]!['open'] = (techStats[name]!['open'] as int) + 1;
      } else if (task.status == 'قيد التنفيذ') {
        techStats[name]!['progress'] =
            (techStats[name]!['progress'] as int) + 1;
      } else if (task.status == 'مكتملة') {
        techStats[name]!['done'] = (techStats[name]!['done'] as int) + 1;
      } else if (task.status == 'ملغية') {
        techStats[name]!['canceled'] =
            (techStats[name]!['canceled'] as int) + 1;
      }
    }

    final sorted = techStats.entries.toList()
      ..sort((a, b) =>
          (b.value['total'] as int).compareTo(a.value['total'] as int));

    if (sorted.isEmpty) return const SizedBox.shrink();

    final isSmall = MediaQuery.of(context).size.width < 420;

    // على الشاشات الصغيرة: عرض بطاقات بدلاً من جدول
    if (isSmall) {
      return _buildTechnicianCards(sorted);
    }

    final fs = 11.0;
    final colW = 45.0;
    final totalW = 50.0;
    final hPad = 16.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2F7),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              border: Border.all(color: const Color(0xFFDDE3EA), width: 0.8),
            ),
            child: Row(
              children: [
                SizedBox(
                    width: totalW,
                    child: Text('الإجمالي',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B7280)))),
                SizedBox(
                    width: colW,
                    child: Text('ملغية',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFE53935)))),
                SizedBox(
                    width: colW,
                    child: Text('مكتملة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF4CAF50)))),
                SizedBox(
                    width: colW,
                    child: Text('تنفيذ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFF9800)))),
                SizedBox(
                    width: totalW,
                    child: Text('مفتوحة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF2196F3)))),
                Expanded(
                    child: Text('القسم',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B7280)))),
                Expanded(
                    child: Text('الفني',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B7280)))),
              ],
            ),
          ),

          // صفوف الجدول
          ...sorted.asMap().entries.map((mapEntry) {
            final idx = mapEntry.key;
            final entry = mapEntry.value;
            final name = entry.key;
            final stats = entry.value;
            final total = stats['total'] as int;
            final open = stats['open'] as int;
            final progress = stats['progress'] as int;
            final done = stats['done'] as int;
            final canceled = stats['canceled'] as int;
            final dept = stats['department'] as String;
            final isEven = idx % 2 == 0;
            const numFs = 14.0;
            const txtFs = 12.0;

            return Container(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
              decoration: BoxDecoration(
                color: isEven ? Colors.white : const Color(0xFFF9FAFB),
                border: Border(
                  bottom:
                      BorderSide(color: const Color(0xFFE5E7EB), width: 0.8),
                  left: BorderSide(color: const Color(0xFFE5E7EB), width: 0.8),
                  right: BorderSide(color: const Color(0xFFE5E7EB), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  // الإجمالي
                  SizedBox(
                    width: totalW,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$total',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: numFs,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // ملغية
                  SizedBox(
                    width: colW,
                    child: Text(
                      '$canceled',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: numFs,
                        fontWeight: FontWeight.w800,
                        color: canceled > 0
                            ? const Color(0xFFE53935)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ),
                  // مكتملة
                  SizedBox(
                    width: colW,
                    child: Text(
                      '$done',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: numFs,
                        fontWeight: FontWeight.w800,
                        color: done > 0
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ),
                  // تنفيذ
                  SizedBox(
                    width: colW,
                    child: Text(
                      '$progress',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: numFs,
                        fontWeight: FontWeight.w800,
                        color: progress > 0
                            ? const Color(0xFFFF9800)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ),
                  // مفتوحة
                  SizedBox(
                    width: totalW,
                    child: Text(
                      '$open',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: numFs,
                        fontWeight: FontWeight.w800,
                        color: open > 0
                            ? const Color(0xFF2196F3)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ),
                  // القسم
                  Expanded(
                    child: Text(
                      dept.isNotEmpty ? dept : '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: txtFs,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF9CA3AF),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // اسم الفني
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.person_rounded,
                            size: 16, color: Color(0xFF4FC3F7)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          // صف الإجمالي
          Container(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2F7),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
              border: Border.all(color: const Color(0xFFDDE3EA), width: 0.8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: totalW,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4FC3F7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_filteredTasks.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: colW,
                  child: Text(
                    '${_filteredTasks.where((t) => t.status == 'ملغية').length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFE53935),
                    ),
                  ),
                ),
                SizedBox(
                  width: colW,
                  child: Text(
                    '${_filteredTasks.where((t) => t.status == 'مكتملة').length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ),
                SizedBox(
                  width: colW,
                  child: Text(
                    '${_filteredTasks.where((t) => t.status == 'قيد التنفيذ').length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFF9800),
                    ),
                  ),
                ),
                SizedBox(
                  width: totalW,
                  child: Text(
                    '${_filteredTasks.where((t) => t.status == 'مفتوحة').length}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                ),
                const Expanded(child: SizedBox()),
                const Expanded(
                  child: Text(
                    'المجموع',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// بطاقات الفنيين للشاشات الصغيرة (بديل الجدول)
  Widget _buildTechnicianCards(
      List<MapEntry<String, Map<String, dynamic>>> sorted) {
    return Column(
      children: sorted.map((entry) {
        final name = entry.key;
        final stats = entry.value;
        final total = stats['total'] as int;
        final open = stats['open'] as int;
        final progress = stats['progress'] as int;
        final done = stats['done'] as int;
        final canceled = stats['canceled'] as int;
        final dept = stats['department'] as String;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // اسم الفني والقسم
              Row(
                children: [
                  Icon(Icons.person_rounded,
                      size: 16, color: const Color(0xFF4FC3F7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (dept.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(dept,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280))),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // إحصائيات الحالات
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildMiniStatChip('مفتوحة', open, const Color(0xFF2196F3)),
                  _buildMiniStatChip(
                      'تنفيذ', progress, const Color(0xFFFF9800)),
                  _buildMiniStatChip('مكتملة', done, const Color(0xFF4CAF50)),
                  _buildMiniStatChip(
                      'ملغية', canceled, const Color(0xFFE53935)),
                  _buildMiniStatChip(
                      'تحصيل',
                      _filteredTasks.where((t) => t.title.contains('تحصيل مبلغ') || t.title.contains('استحصال مبلغ')).length,
                      const Color(0xFFFF8F00)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$total',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// شريحة إحصائية صغيرة للبطاقات
  Widget _buildMiniStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: count > 0 ? color.withValues(alpha: 0.1) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: count > 0 ? color : const Color(0xFFD1D5DB),
        ),
      ),
    );
  }

  /// بطاقة إحصائية
  Widget _buildStatCard(
      String label, int count, int total, Color color, IconData icon,
      {bool compact = false, bool tiny = false}) {
    double pct = total > 0 ? (count / total) * 100 : 0;
    final pad = tiny ? 8.0 : (compact ? 12.0 : 18.0);
    final numSize = tiny ? 22.0 : (compact ? 32.0 : 42.0);
    final lblSize = tiny ? 10.0 : (compact ? 13.0 : 16.0);
    final iconSize = tiny ? 16.0 : (compact ? 20.0 : 24.0);
    final iconPad = tiny ? 5.0 : (compact ? 8.0 : 10.0);
    final gap1 = tiny ? 6.0 : (compact ? 10.0 : 14.0);
    final gap2 = tiny ? 3.0 : (compact ? 6.0 : 8.0);
    final gap3 = tiny ? 4.0 : (compact ? 8.0 : 10.0);
    final pctSize = tiny ? 9.0 : (compact ? 12.0 : 14.0);
    final radius = tiny ? 10.0 : 16.0;

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // السطر العلوي: أيقونة
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.all(iconPad),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: iconSize),
              ),
              Icon(
                Icons.trending_up_rounded,
                color: color.withValues(alpha: 0.4),
                size: tiny ? 14 : (compact ? 20 : 26),
              ),
            ],
          ),
          SizedBox(height: gap1),
          // الرقم الكبير
          Text(
            '$count',
            style: TextStyle(
              fontSize: numSize,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1F2937),
              height: 1,
            ),
          ),
          SizedBox(height: gap2),
          // العنوان
          Text(
            label,
            style: TextStyle(
              fontSize: lblSize,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF4B5563),
            ),
          ),
          SizedBox(height: gap3),
          // شارة النسبة
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${pct.toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: pctSize,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// عداد دائري لكل حالة (قديم)
  Widget _buildCircularCounter(
      String label, int count, int total, Color color, IconData icon) {
    double pct = total > 0 ? count / total : 0;

    return Column(
      children: [
        // الدائرة مع توهج
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // خلفية الدائرة
              SizedBox(
                width: 90,
                height: 90,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    const Color(0xFF667EEA).withValues(alpha: 0.15),
                  ),
                ),
              ),
              // التقدم الفعلي
              SizedBox(
                width: 90,
                height: 90,
                child: CircularProgressIndicator(
                  value: pct,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              // الرقم في المنتصف
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A202C),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${(pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // الأيقونة
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        // العنوان
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF374151),
          ),
        ),
      ],
    );
  }

  /// عدّ المهام ذات الحالة المحددة بتاريخ اليوم (حسب closedAt ثم createdAt)
  int _countToday(String status) {
    final now = DateTime.now();
    return _currentTasks.where((t) {
      if (t.status != status) return false;
      final d = (t.closedAt ?? t.createdAt);
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
  }

  /// ويدجت بسيطة لعرض العدد كشيب صغيرة
  Widget _buildCountChip(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  /// شريط فلتر التحصيل
  Widget _buildCollectionFilterBar() {
    final isSmall = MediaQuery.of(context).size.width < 420;
    final chipFs = isSmall ? 10.0 : 12.0;

    // جمع أسماء الفنيين من مهام التحصيل
    final techNames = _currentTasks
        .where((t) => t.title.contains('تحصيل مبلغ') || t.title.contains('استحصال مبلغ'))
        .map((t) => t.technician.trim())
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 6 : 12, vertical: isSmall ? 4 : 6),
      color: const Color(0xFFFFF8E1),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in ['الكل', 'معلقة', 'مكتملة غير مفعّل', 'مكتملة مفعّل', 'متأخرة', 'إحصائيات'])
            Padding(
              padding: EdgeInsets.only(left: isSmall ? 4 : 6),
              child: ChoiceChip(
                label: Text(f, style: TextStyle(fontSize: chipFs)),
                selected: _collectionStatusFilter == f,
                selectedColor: f == 'متأخرة' ? Colors.red.shade100 : const Color(0xFFFFE0B2),
                visualDensity: isSmall ? VisualDensity.compact : VisualDensity.standard,
                materialTapTargetSize: isSmall ? MaterialTapTargetSize.shrinkWrap : MaterialTapTargetSize.padded,
                padding: isSmall ? const EdgeInsets.symmetric(horizontal: 4) : null,
                onSelected: (_) {
                  setState(() {
                    _collectionStatusFilter = f;
                    _filterTasksByStatus('تحصيل');
                  });
                },
              ),
            ),
          if (techNames.isNotEmpty) ...[
            SizedBox(width: isSmall ? 6 : 12),
            Container(
              height: isSmall ? 28 : 32,
              padding: EdgeInsets.symmetric(horizontal: isSmall ? 6 : 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _collectionTechFilter,
                  hint: Text('كل الفنيين', style: TextStyle(fontSize: chipFs)),
                  isDense: true,
                  style: TextStyle(fontSize: chipFs, color: Colors.black87),
                  items: [
                    DropdownMenuItem(value: '', child: Text('كل الفنيين', style: TextStyle(fontSize: chipFs))),
                    ...techNames.map((n) => DropdownMenuItem(value: n, child: Text(n, style: TextStyle(fontSize: chipFs), overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _collectionTechFilter = (v != null && v.isNotEmpty) ? v : null;
                      _filterTasksByStatus('تحصيل');
                    });
                  },
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  /// بحث في السيرفر عن كل المهام
  Future<void> _searchOnServer(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _serverSearchResults = null;
        _isServerSearching = false;
      });
      _applyPermissionFilter();
      _filterTasksByStatus(_getStatusByIndex(currentIndex));
      return;
    }
    setState(() => _isServerSearching = true);
    try {
      final response = await TaskApiService.instance.searchAllTasks(query.trim());
      final List<dynamic> items = response['data'] ?? [];
      final tasks = items
          .map((item) => Task.fromApiResponse(item as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _serverSearchResults = tasks;
          _isServerSearching = false;
          _filteredTasks = tasks;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isServerSearching = false);
    }
  }

  /// شريط البحث
  Widget _buildSearchBar() {
    final isSmall = MediaQuery.of(context).size.width < 420;
    return Padding(
      padding: EdgeInsets.fromLTRB(isSmall ? 8 : 12, 8, isSmall ? 8 : 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: isSmall ? 13 : 14),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم، الهاتف، الفني...',
                hintStyle: TextStyle(
                    fontSize: isSmall ? 12 : 13, color: Colors.grey.shade400),
                prefixIcon: Icon(Icons.search,
                    size: isSmall ? 20 : 22, color: Colors.grey.shade500),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade500),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                            _serverSearchResults = null;
                          });
                          _applyPermissionFilter();
                          _filterTasksByStatus(_getStatusByIndex(currentIndex));
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 14, vertical: isSmall ? 10 : 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1A237E), width: 1.5),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                  if (value.trim().isEmpty) {
                    _serverSearchResults = null;
                  }
                });
                // بحث محلي فوري
                _applyPermissionFilter();
                _filterTasksByStatus(_getStatusByIndex(currentIndex));
              },
              onSubmitted: (value) {
                // عند الضغط على Enter: بحث في السيرفر
                if (value.trim().isNotEmpty) _searchOnServer(value);
              },
            ),
          ),
          const SizedBox(width: 6),
          // زر بحث في كل المهام (سيرفر)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isServerSearching ? null : () {
                if (_searchQuery.isNotEmpty) _searchOnServer(_searchQuery);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: EdgeInsets.all(isSmall ? 10 : 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isServerSearching
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(Icons.manage_search, size: isSmall ? 20 : 22, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// بناء قائمة المهام
  Widget _buildTaskListView() {
    final listContent = _filteredTasks.isEmpty
        ? const Expanded(
            child: Center(
              child: Text(
                'لا توجد مهام حاليا',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF9CA3AF)),
              ),
            ),
          )
        : Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                // تحميل المزيد عند الوصول لـ 80% من القائمة
                if (scrollInfo.metrics.pixels >
                        scrollInfo.metrics.maxScrollExtent * 0.8 &&
                    widget.hasMorePages) {
                  widget.onLoadMore?.call();
                }
                return false;
              },
              child: ListView.builder(
                itemCount:
                    _filteredTasks.length + (widget.hasMorePages && _filteredTasks.length == _currentTasks.length ? 1 : 0),
                itemBuilder: (context, index) {
                  // مؤشر تحميل المزيد
                  if (index >= _filteredTasks.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))),
                    );
                  }
                  final task = _filteredTasks[index];
                  return TaskCard(
                    task: task,
                    currentUserRole: widget.currentUserRole,
                    currentUserName: widget.username,
                    onStatusChanged: (updatedTask) {
                      // إعادة تحميل المهام من السيرفر لتحديث البيانات
                      widget.onRefresh?.call();
                      widget.onTaskStatusChanged(updatedTask);
                    },
                  );
                },
              ),
            ),
          );

    // إذا كنا في تبويب المهام المكتملة (index == 3) نضيف أزرار (اليوم / الكل)
    if (currentIndex == 3) {
      final isSmallScreen = MediaQuery.of(context).size.width < 420;
      final btnIconSize = isSmallScreen ? 18.0 : 24.0;
      final btnFontSize = isSmallScreen ? 12.0 : 14.0;
      final btnPadV = isSmallScreen ? 10.0 : 16.0;
      final btnHeight = isSmallScreen ? 44.0 : 54.0;
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(isSmallScreen ? 8 : 12, 8, isSmallScreen ? 8 : 12, 4),
            child: Container(
              padding: EdgeInsets.all(isSmallScreen ? 6 : 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _completedTodayOnly
                          ? null
                          : () {
                              _completedTodayOnly = true;
                              _filterTasksByStatus('مكتملة');
                            },
                      icon: Icon(Icons.today, size: btnIconSize),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text('اليوم فقط',
                                style: TextStyle(
                                    fontSize: btnFontSize, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 4),
                          _buildCountChip(_countToday('مكتملة')),
                        ],
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: btnPadV, horizontal: isSmallScreen ? 6 : 12),
                        minimumSize: Size.fromHeight(btnHeight),
                        backgroundColor: _completedTodayOnly
                            ? Colors.green[700]
                            : Colors.green[500],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.green[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 6 : 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _completedTodayOnly
                          ? () {
                              _completedTodayOnly = false;
                              _filterTasksByStatus('مكتملة');
                            }
                          : null,
                      icon: Icon(Icons.all_inbox, size: btnIconSize),
                      label: Text('الكل',
                          style: TextStyle(
                              fontSize: btnFontSize, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: btnPadV, horizontal: isSmallScreen ? 6 : 12),
                        minimumSize: Size.fromHeight(btnHeight),
                        backgroundColor: _completedTodayOnly
                            ? Colors.blue[600]
                            : Colors.blue[800],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.blue[400],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          listContent,
        ],
      );
    }

    // تبويب المهام الملغية (index == 4)
    if (currentIndex == 4) {
      final isSmallScreen = MediaQuery.of(context).size.width < 420;
      final btnIconSize = isSmallScreen ? 18.0 : 24.0;
      final btnFontSize = isSmallScreen ? 12.0 : 14.0;
      final btnPadV = isSmallScreen ? 10.0 : 16.0;
      final btnHeight = isSmallScreen ? 44.0 : 54.0;
      return Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(isSmallScreen ? 8 : 12, 8, isSmallScreen ? 8 : 12, 4),
            child: Container(
              padding: EdgeInsets.all(isSmallScreen ? 6 : 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelledTodayOnly
                          ? null
                          : () {
                              _cancelledTodayOnly = true;
                              _filterTasksByStatus('ملغية');
                            },
                      icon: Icon(Icons.today, size: btnIconSize),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text('اليوم فقط',
                                style: TextStyle(
                                    fontSize: btnFontSize, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 4),
                          _buildCountChip(_countToday('ملغية')),
                        ],
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: btnPadV, horizontal: isSmallScreen ? 6 : 12),
                        minimumSize: Size.fromHeight(btnHeight),
                        backgroundColor: _cancelledTodayOnly
                            ? Colors.red[700]
                            : Colors.red[500],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.red[300],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 6 : 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelledTodayOnly
                          ? () {
                              _cancelledTodayOnly = false;
                              _filterTasksByStatus('ملغية');
                            }
                          : null,
                      icon: Icon(Icons.all_inbox, size: btnIconSize),
                      label: Text('الكل',
                          style: TextStyle(
                              fontSize: btnFontSize, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: btnPadV, horizontal: isSmallScreen ? 6 : 12),
                        minimumSize: Size.fromHeight(btnHeight),
                        backgroundColor: _cancelledTodayOnly
                            ? Colors.blue[600]
                            : Colors.blue[800],
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.blue[400],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          listContent,
        ],
      );
    }

    // غير تبويب المكتملة: نرجع كما كان (قائمة فقط)
    return Column(children: [listContent]);
  }

  /// بناء زر التنقل العصري
  Widget _buildModernNavButton({
    required int index,
    required IconData icon,
    required String label,
    required Color color,
    int badgeCount = 0,
  }) {
    bool isSelected = currentIndex == index;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 500;
    final isSmallMobile = screenWidth < 380;
    final iconSize = isSmallMobile ? 16.0 : isMobile ? 18.0 : 20.0;
    final fontSize = isSmallMobile ? 8.0 : isMobile ? 9.0 : 11.0;
    final hMargin = isSmallMobile ? 1.0 : isMobile ? 2.0 : 3.0;
    final hPadding = isSmallMobile ? 2.0 : isMobile ? 3.0 : 4.0;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            currentIndex = index;
            _filterTasksByStatus(_getStatusByIndex(index));
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: hMargin),
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: hPadding),
          constraints: const BoxConstraints(
            minHeight: 48,
            maxHeight: 56,
          ),
          decoration: BoxDecoration(
            color: isSelected ? color : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : const Color(0xFFE5E7EB),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              badgeCount > 0
                  ? Badge(
                      label: Text(
                        badgeCount.toString(),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white),
                      ),
                      backgroundColor: Colors.red,
                      child: Icon(
                        icon,
                        color: isSelected ? Colors.white : color,
                        size: iconSize,
                      ),
                    )
                  : Icon(
                      icon,
                      color: isSelected ? Colors.white : color,
                      size: iconSize,
                    ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF6B7280),
                    fontSize: fontSize,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    height: 1.0,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// عرض جميع المهام في التقارير
  void _showAllTasks() {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReportsPage(
            tasks: _currentTasks,
            filteredTasks: _filteredTasks,
            showFilterPopup: _showFilterPopup,
            calculateTotalAmount: _calculateTotalAmount,
            calculateTaskDuration: _calculateTaskDuration,
          ),
        ),
      );
    } catch (e) {
      debugPrint('حدث خطأ أثناء فتح التقارير');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء فتح التقارير'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// حساب مدة تنفيذ المهمة
  String _calculateTaskDuration(Task task) {
    if (task.closedAt == null) {
      return 'لم يتم الإغلاق بعد';
    }
    final duration = task.closedAt!.difference(task.createdAt);
    return '${duration.inHours} ساعة و ${duration.inMinutes.remainder(60)} دقيقة';
  }

  Widget _buildDateFilterDropdown() {
    const filters = [
      {'label': 'اليوم', 'value': 'today', 'icon': Icons.today},
      {'label': 'أمس', 'value': 'yesterday', 'icon': Icons.history},
      {'label': 'الكل', 'value': 'all', 'icon': Icons.all_inclusive},
    ];
    final current = filters.firstWhere((f) => f['value'] == _dateFilter, orElse: () => filters.first);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _dateFilter,
          dropdownColor: const Color(0xFF1E3A5F),
          icon: const Icon(Icons.arrow_drop_down,
              color: Colors.white70, size: 20),
          isDense: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          selectedItemBuilder: (ctx) => filters
              .map((f) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(f['icon'] as IconData,
                          size: 15, color: const Color(0xFF4FC3F7)),
                      const SizedBox(width: 6),
                      Text(f['label'] as String,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ],
                  ))
              .toList(),
          items: filters
              .map((f) => DropdownMenuItem<String>(
                    value: f['value'] as String,
                    child: Row(
                      children: [
                        Icon(f['icon'] as IconData,
                            size: 16,
                            color: _dateFilter == f['value']
                                ? const Color(0xFF4FC3F7)
                                : Colors.white54),
                        const SizedBox(width: 8),
                        Text(f['label'] as String),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _dateFilter = v;
              _applyPermissionFilter();
              _filterTasksByStatus(_getStatusByIndex(currentIndex));
            });
          },
        ),
      ),
    );
  }

  /// شريط تصفية التاريخ
  Widget _buildDateFilterBar() {
    final isSmall = MediaQuery.of(context).size.width < 420;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isSmall ? 8 : 20, vertical: 8),
      color: const Color(0xFFF5F7FA),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildDateFilterButton('اليوم', 'today', Icons.today, compact: isSmall),
          SizedBox(width: isSmall ? 6 : 10),
          _buildDateFilterButton('أمس', 'yesterday', Icons.history, compact: isSmall),
          SizedBox(width: isSmall ? 6 : 10),
          _buildDateFilterButton('الكل', 'all', Icons.all_inclusive, compact: isSmall),
        ],
      ),
    );
  }

  Widget _buildDateFilterButton(String label, String value, IconData icon,
      {bool compact = false}) {
    final isSelected = _dateFilter == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _dateFilter = value;
            _applyPermissionFilter();
            _filterTasksByStatus(_getStatusByIndex(currentIndex));
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 18,
            vertical: compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF00B4D8), Color(0xFF4FC3F7)],
                  )
                : null,
            color: isSelected ? null : Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : Colors.white.withValues(alpha: 0.3),
              width: 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? 13 : 16,
                color: Colors.white.withValues(alpha: isSelected ? 1.0 : 0.7),
              ),
              SizedBox(width: compact ? 4 : 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: compact ? 11 : 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.white.withValues(alpha: isSelected ? 1.0 : 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// شريط الأدوات العلوي — مبسّط للموبايل
  Widget _buildTopActionBar() {
    final r = context.responsive;
    final isMobile = MediaQuery.of(context).size.width < 500;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── الصف الأول: رجوع + عنوان + إشعارات + قائمة ───
            Padding(
              padding: EdgeInsets.fromLTRB(
                  r.contentPaddingH, 8, r.contentPaddingH, 4),
              child: Row(
                children: [
                  // رجوع
                  _buildBarIcon(
                      Icons.arrow_back, () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),

                  // عنوان الصفحة
                  Expanded(
                    child: Text(
                      'إدارة المهام',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 16 : 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  // إشعارات
                  Stack(
                    children: [
                      _buildBarIcon(Icons.notifications_outlined, () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const FtthCompanyPage()));
                      }),
                      if (showNotificationBadge && newTasksCount > 0)
                        Positioned(
                          right: 2,
                          top: 2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.red[600],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 18, minHeight: 18),
                            child: Text(
                              newTasksCount > 99
                                  ? '99+'
                                  : newTasksCount.toString(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),

                  // بحث مشترك — توصيل
                  _buildBarIcon(Icons.person_search, () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerSearchConnectPage()));
                  }),
                  const SizedBox(width: 4),

                  // قائمة خيارات (بدل أزرار متفرقة)
                  _buildBarIcon(Icons.more_vert, () => _showMoreMenu()),
                ],
              ),
            ),

            // ─── الصف الثاني: فلاتر (تاريخ + متقدم) ───
            Padding(
              padding: EdgeInsets.fromLTRB(
                  r.contentPaddingH, 0, r.contentPaddingH, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // فلتر التاريخ — chips مدمجة
                    _buildDateFilterChip('اليوم', 'today'),
                    const SizedBox(width: 6),
                    _buildDateFilterChip('أمس', 'yesterday'),
                    const SizedBox(width: 6),
                    _buildDateFilterChip('الكل', 'all'),

                    // زر "مهامي" — يظهر للمدير والليدر فقط
                    if (_normalizeRole(widget.currentUserRole) == 'مدير' ||
                        _normalizeRole(widget.currentUserRole) == 'ليدر') ...[
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () {
                          setState(() => _myTasksOnly = !_myTasksOnly);
                          _filterTasksByStatus(_getStatusByIndex(currentIndex));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _myTasksOnly
                                ? Colors.amber.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: _myTasksOnly
                                ? Border.all(color: Colors.amber, width: 1.5)
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _myTasksOnly ? Icons.person : Icons.person_outline,
                                color: _myTasksOnly ? Colors.amber : Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'مهامي',
                                style: TextStyle(
                                  color: _myTasksOnly ? Colors.amber : Colors.white70,
                                  fontSize: 12,
                                  fontWeight: _myTasksOnly ? FontWeight.bold : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(width: 10),

                    // فلتر متقدم
                    GestureDetector(
                      onTap: () => _showFilterPopup(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (_filterDepartment != null ||
                                  _filterTechnician != null ||
                                  _filterPriority != null ||
                                  _filterTaskType != null)
                              ? Colors.orangeAccent.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: (_filterDepartment != null ||
                                  _filterTechnician != null ||
                                  _filterPriority != null ||
                                  _filterTaskType != null)
                              ? Border.all(color: Colors.orangeAccent, width: 1)
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tune_rounded,
                                size: 14,
                                color: (_filterDepartment != null ||
                                        _filterTechnician != null ||
                                        _filterPriority != null)
                                    ? Colors.orangeAccent
                                    : Colors.white70),
                            const SizedBox(width: 4),
                            Text('فلتر',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: (_filterDepartment != null ||
                                          _filterTechnician != null ||
                                          _filterPriority != null)
                                      ? Colors.orangeAccent
                                      : Colors.white70,
                                )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// أيقونة شريط أدوات موحّدة
  Widget _buildBarIcon(IconData icon, VoidCallback onTap) {
    final isMobile = MediaQuery.of(context).size.width < 500;
    final iconSize = isMobile ? 18.0 : 22.0;
    final pad = isMobile ? 6.0 : 8.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }

  /// chip فلتر تاريخ صغير
  Widget _buildDateFilterChip(String label, String value) {
    final isActive = _dateFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _dateFilter = value;
          _applyPermissionFilter();
          _filterTasksByStatus(_getStatusByIndex(currentIndex));
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isActive ? Colors.white54 : Colors.white.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? Colors.white : Colors.white60,
          ),
        ),
      ),
    );
  }

  /// قائمة "المزيد" — تحتوي الأزرار المنقولة من الشريط
  /// خيارات الزر العائم — مهمة جديدة + شراء اشتراك (حسب الصلاحيات)
  void _showFabOptions() {
    final normalizedRole = _normalizeRole(widget.currentUserRole);
    final isMgr = normalizedRole == 'مدير';
    final isLeader = normalizedRole == 'ليدر';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              if (isMgr || isLeader)
                _buildMenuTile(Icons.add_task, 'إضافة مهمة جديدة', Colors.green,
                    () {
                  Navigator.pop(ctx);
                  _showAddTaskDialog();
                }),
              _buildMenuTile(
                  Icons.add_shopping_cart, 'شراء اشتراك', Colors.blue, () {
                Navigator.pop(ctx);
                _showAddSubscriptionDialog();
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreMenu() {
    openDrawer();
  }

  Widget _buildMenuTile(
      IconData icon, String title, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 22),
      ),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }

  /// عرض dialog إضافة شراء اشتراك
  void _showAddSubscriptionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddTaskApiDialog(
        currentUsername: widget.username,
        currentUserRole: widget.currentUserRole,
        currentUserDepartment: widget.department,
        onTaskCreated: (Map<String, dynamic> data) {
          // تحديث القائمة من الخادم
          widget.onRefresh?.call();
          _showTaskAddedSuccessSnack();
        },
        // تمرير قيم مبدئية لشراء الاشتراك
        initialCustomerName: '',
        initialCustomerPhone: '',
        initialCustomerLocation: '',
        initialTaskType: 'شراء اشتراك',
        initialNotes: 'طلب شراء اشتراك جديد',
      ),
    );
  }

  /// عرض dialog إضافة المهام مع الإشعارات
  void _showAddTaskDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AddTaskApiDialog(
        currentUsername: widget.username,
        currentUserRole: widget.currentUserRole,
        currentUserDepartment: widget.department,
        onTaskCreated: (Map<String, dynamic> data) {
          // تحديث القائمة من الخادم
          widget.onRefresh?.call();
          _showTaskAddedSuccessSnack();
        },
      ),
    );
  }

  /// عرض رسالة نجاح مع تفاصيل الإشعارات المرسلة
  void _showTaskAddedSuccessSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(8),
          child: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم إضافة المهمة بنجاح! ✅',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showFilterPopup(BuildContext context) {
    String? tempDept = _filterDepartment;
    String? tempTech = _filterTechnician;
    String? tempPriority = _filterPriority;
    String? tempTaskType = _filterTaskType;

    final departments = _getUniqueDepartments();
    final technicians = _getUniqueTechnicians();
    final taskTypes = _getUniqueTaskTypes();
    const priorities = ['عاجل', 'عالي', 'متوسط', 'منخفض'];

    final hasActiveFilters = _filterDepartment != null ||
        _filterTechnician != null ||
        _filterPriority != null ||
        _filterTaskType != null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.filter_list_rounded,
                      color: Color(0xFF1A237E), size: 22),
                  const SizedBox(width: 8),
                  const Text('فلترة متقدمة',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (hasActiveFilters ||
                      tempDept != null ||
                      tempTech != null ||
                      tempPriority != null)
                    TextButton(
                      onPressed: () {
                        setDialogState(() {
                          tempDept = null;
                          tempTech = null;
                          tempPriority = null;
                          tempTaskType = null;
                        });
                      },
                      child: const Text('مسح الكل',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // فلتر القسم
                      const Text('القسم',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: tempDept,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'جميع الأقسام',
                          hintStyle: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('جميع الأقسام')),
                          ...departments.map((d) => DropdownMenuItem(
                              value: d,
                              child: Text(d,
                                  style: const TextStyle(fontSize: 13)))),
                        ],
                        onChanged: (v) => setDialogState(() => tempDept = v),
                      ),
                      const SizedBox(height: 14),

                      // فلتر الفني
                      const Text('الفني',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: tempTech,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'جميع الفنيين',
                          hintStyle: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('جميع الفنيين')),
                          ...technicians.map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t,
                                  style: const TextStyle(fontSize: 13)))),
                        ],
                        onChanged: (v) => setDialogState(() => tempTech = v),
                      ),
                      const SizedBox(height: 14),

                      // فلتر نوع المهمة
                      const Text('نوع المهمة',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: tempTaskType,
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'جميع الأنواع',
                          hintStyle: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                              value: null, child: Text('جميع الأنواع')),
                          ...taskTypes.map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t,
                                  style: const TextStyle(fontSize: 13)))),
                        ],
                        onChanged: (v) => setDialogState(() => tempTaskType = v),
                      ),
                      const SizedBox(height: 14),

                      // فلتر الأولوية
                      const Text('الأولوية',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          ChoiceChip(
                            label: const Text('الكل',
                                style: TextStyle(fontSize: 12)),
                            selected: tempPriority == null,
                            onSelected: (_) =>
                                setDialogState(() => tempPriority = null),
                          ),
                          ...priorities.map((p) => ChoiceChip(
                                label: Text(p,
                                    style: const TextStyle(fontSize: 12)),
                                selected: tempPriority == p,
                                selectedColor: _getPriorityChipColor(p),
                                onSelected: (_) => setDialogState(() =>
                                    tempPriority =
                                        tempPriority == p ? null : p),
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _filterDepartment = tempDept;
                      _filterTechnician = tempTech;
                      _filterPriority = tempPriority;
                      _filterTaskType = tempTaskType;
                      _applyPermissionFilter();
                      _filterTasksByStatus(_getStatusByIndex(currentIndex));
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('تطبيق'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getPriorityChipColor(String priority) {
    switch (priority) {
      case 'عاجل':
        return Colors.red.shade100;
      case 'عالي':
        return Colors.orange.shade100;
      case 'متوسط':
        return Colors.yellow.shade100;
      case 'منخفض':
        return Colors.green.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: _shouldShowDrawer() ? _buildDrawer() : null,
      // زر عائم — يفتح خيارات الإضافة
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFabOptions(),
        backgroundColor: const Color(0xFF1A237E),
        elevation: 6,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      body: Column(
        children: [
          // شريط الأدوات العلوي مع زر إضافة المهام
          _buildTopActionBar(),
          // شريط البحث — يظهر في تبويبات القوائم فقط (ليس اللوحة والإحصائيات)
          if (currentIndex != 0 && currentIndex != 6) _buildSearchBar(),
          if (currentIndex == 5) _buildCollectionFilterBar(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.red[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'حدث خطأ في تحميل المهام',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              errorMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: widget.onRefresh,
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
                    : currentIndex == 0
                        ? _buildDashboardView()
                        : (currentIndex == 5 && _collectionStatusFilter == 'إحصائيات')
                            ? SingleChildScrollView(
                                child: _buildCollectionStatsCard(),
                              )
                            : _buildTaskListView(),
          ),
        ],
      ),
      bottomNavigationBar: Builder(builder: (context) {
        final navScreenWidth = MediaQuery.of(context).size.width;
        final navIsSmall = navScreenWidth < 420;
        final navHeight = navIsSmall ? 60.0 : 75.0;
        final navPadV = navIsSmall ? 4.0 : 8.0;
        final navPadH = navIsSmall ? 2.0 : 6.0;
        return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
          border: const Border(
            top: BorderSide(
              color: Color(0xFFE5E7EB),
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: Container(
            height: navHeight,
            padding: EdgeInsets.symmetric(horizontal: navPadH, vertical: navPadV),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModernNavButton(
                  index: 0,
                  icon: Icons.dashboard,
                  label: 'اللوحة',
                  color: Colors.purple[600]!,
                ),
                _buildModernNavButton(
                  index: 1,
                  icon: Icons.lock_open,
                  label: 'مفتوحة',
                  color: Colors.blue[600]!,
                ),
                _buildModernNavButton(
                  index: 2,
                  icon: Icons.settings,
                  label: 'قيد التنفيذ',
                  color: Colors.orange[600]!,
                ),
                _buildModernNavButton(
                  index: 3,
                  icon: Icons.check_circle,
                  label: 'مكتملة',
                  color: Colors.green[600]!,
                ),
                _buildModernNavButton(
                  index: 4,
                  icon: Icons.cancel,
                  label: 'ملغية',
                  color: Colors.red[600]!,
                ),
                _buildModernNavButton(
                  index: 5,
                  icon: Icons.attach_money,
                  label: 'تحصيل',
                  color: Colors.amber[700]!,
                ),
              ],
            ),
          ),
        ),
      );
      }),
    );
  }

  /// تحديد ما إذا كان يجب إظهار القائمة الجانبية
  bool _shouldShowDrawer() {
    return true; // إظهار القائمة لجميع المستخدمين للوصول للإعدادات
  }

  /// بناء القائمة الجانبية
  Widget _buildDrawer() {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade800,
              Colors.blue.shade600,
            ],
          ),
        ),
        child: Column(
          children: [
            // رأس القائمة الجانبية
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade900, Colors.blue.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                      _normalizeRole(widget.currentUserRole) == 'مدير'
                          ? Icons.admin_panel_settings
                          : Icons.supervisor_account,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    widget.currentUserRole,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    widget.department,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // محتوى القائمة الجانبية
            Expanded(
              child: Container(
                color: Colors.white,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    // التقارير (للمدير والليدر فقط)
                    if (_normalizeRole(widget.currentUserRole) == 'مدير' ||
                        _normalizeRole(widget.currentUserRole) == 'ليدر')
                      _buildDrawerItem(
                        icon: Icons.analytics,
                        title: 'التقارير والإحصائيات',
                        subtitle: 'عرض التقارير التفصيلية',
                        onTap: () {
                          Navigator.pop(context);
                          _showAllTasks();
                        },
                        color: Colors.blue,
                      ),
                    // لوحة أداء الفنيين (للمدير والليدر فقط)
                    if (_normalizeRole(widget.currentUserRole) == 'مدير' ||
                        _normalizeRole(widget.currentUserRole) == 'ليدر')
                      _buildDrawerItem(
                        icon: Icons.leaderboard,
                        title: 'أداء الفنيين',
                        subtitle: 'إحصائيات ومقارنة الأداء',
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TechnicianPerformancePage(
                                    tasks: _currentTasks),
                              ));
                        },
                        color: Colors.deepPurple,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// بناء عنصر في القائمة الجانبية
  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 12,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  /// عرض نافذة حول التطبيق
  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'نظام إدارة المهام',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.task, size: 50, color: Colors.blue),
      children: [
        const Text('نظام متطور لإدارة مهام الصيانة والدعم الفني'),
        const SizedBox(height: 10),
        Text('المستخدم: ${widget.username}'),
        Text('الدور: ${widget.currentUserRole}'),
        Text('القسم: ${widget.department}'),
      ],
    );
  }

  /// عرض نافذة تأكيد تسجيل الخروج
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('تأكيد تسجيل الخروج'),
          content: const Text('هل أنت متأكد من رغبتك في تسجيل الخروج؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('تسجيل الخروج',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  /// عرض محرر قالب رسالة الواتساب
  void _showWhatsAppTemplateEditor() {
    showDialog(
      context: context,
      builder: (context) => _WhatsAppTemplateEditorDialog(),
    );
  }
}

/// نافذة محرر قالب رسالة ال��اتساب
class _WhatsAppTemplateEditorDialog extends StatefulWidget {
  @override
  State<_WhatsAppTemplateEditorDialog> createState() =>
      _WhatsAppTemplateEditorDialogState();
}

class _WhatsAppTemplateEditorDialogState
    extends State<_WhatsAppTemplateEditorDialog> {
  final TextEditingController _templateController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentTemplate();
  }

  Future<void> _loadCurrentTemplate() async {
    try {
      final template = await WhatsAppTemplateStorage.loadTemplate();
      setState(() {
        _templateController.text = template ?? _getDefaultTemplate();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _templateController.text = _getDefaultTemplate();
        _isLoading = false;
      });
    }
  }

  String _getDefaultTemplate() {
    return '''السلام عليكم ورحمة الله وبركاته
👤 اس�� المستخدم: {username}
📞 رقم الهاتف: {phone}
📋 تم إنشاء مهمة جديدة:
🆔 معرف المهمة: {id}
📝 العنوان: {title}
📊 الحالة: {status}
👨‍🔧 الفني المختص: {technician}
📱 هاتف الفني: {technician_phone}
📡 FBG: {fbg}
🔌 FAT: {fat}
💰 المبلغ: {amount}
🕐 تاريخ الإنشاء: {created_at}
👨‍💻 منشئ المهمة: {created_by}

شركة رمز الصدارة المشغل الرسمي للمشروع الوطني 
فريق الدعم الفني''';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.message_outlined, color: Colors.green),
          SizedBox(width: 8),
          Text('تعديل قالب رسالة الواتساب'),
        ],
      ),
      content: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: double.maxFinite,
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'يمكنك استخدام المتغيرات التالية:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _buildVariableChip('{id}', 'معرف المهمة'),
                      _buildVariableChip('{title}', 'عنوان المهمة'),
                      _buildVariableChip('{status}', 'حالة المهمة'),
                      _buildVariableChip('{department}', 'القسم'),
                      _buildVariableChip('{leader}', 'اسم الليدر'),
                      _buildVariableChip('{technician}', 'اسم الفني'),
                      _buildVariableChip('{username}', 'اسم المستخدم'),
                      _buildVariableChip('{phone}', 'رقم هاتف المستخدم'),
                      _buildVariableChip(
                          '{technician_phone}', 'رقم هاتف الفني'),
                      _buildVariableChip('{fbg}', 'FBG'),
                      _buildVariableChip('{fat}', 'FAT'),
                      _buildVariableChip('{location}', 'الموقع'),
                      _buildVariableChip('{notes}', 'الملاحظات'),
                      _buildVariableChip('{summary}', 'ملخص المهمة'),
                      _buildVariableChip('{priority}', 'الأولوية'),
                      _buildVariableChip('{amount}', 'المبلغ'),
                      _buildVariableChip('{created_at}', 'تاريخ الإنشاء'),
                      _buildVariableChip('{closed_at}', 'تاريخ الإغلاق'),
                      _buildVariableChip('{created_by}', 'منشئ المهمة'),
                      _buildVariableChip('{agents}', 'الوكلاء'),
                      _buildVariableChip('{duration}', 'مدة تنفيذ المهمة'),
                    ],
                  ),
                  SizedBox(height: 16),
                  Text(
                    'القالب:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: _templateController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'أدخل قالب رسالة الواتساب...',
                      ),
                    ),
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('إلغاء'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _templateController.text = _getDefaultTemplate();
            });
          },
          child: Text('استعادة الافتراضي'),
        ),
        ElevatedButton(
          onPressed: _saveTemplate,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: Text('حفظ', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildVariableChip(String variable, String description) {
    return Tooltip(
      message: description,
      child: Chip(
        label: Text(variable, style: TextStyle(fontSize: 12)),
        backgroundColor: Colors.blue.shade50,
        side: BorderSide(color: Colors.blue.shade200),
      ),
    );
  }

  Future<void> _saveTemplate() async {
    try {
      await WhatsAppTemplateStorage.saveTemplate(_templateController.text);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ قالب رسالة الواتساب بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حفظ القالب'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _templateController.dispose();
    super.dispose();
  }
}
