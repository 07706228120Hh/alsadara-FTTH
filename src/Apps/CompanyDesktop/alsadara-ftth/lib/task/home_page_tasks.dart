import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/responsive_helper.dart';
import '../models/task.dart';
import 'task_card.dart';
import 'add_task_api_dialog.dart';
import '../ftth/tickets/tickets_login_page.dart';
import 'reports_page.dart';
import '../services/whatsapp_template_storage.dart';

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

  void _applyPermissionFilter() {
    print(
        '🔍 [FILTER] Role: "${widget.currentUserRole}", Username: "${widget.username}", Department: "${widget.department}"');
    print('🔍 [FILTER] Total tasks: ${_currentTasks.length}');
    for (var task in _currentTasks) {
      print(
          '🔍 [FILTER] Task ${task.id}: technician="${task.technician}", createdBy="${task.createdBy}", dept="${task.department}"');
    }
    final role = _normalizeRole(widget.currentUserRole);
    setState(() {
      if (role == 'مدير') {
        // المدير يرى جميع المهام
        _filteredTasks = _currentTasks;
      } else if (role == 'ليدر') {
        // الليدر يرى: مهام قسمه + المعيّنة له + التي أنشأها
        final dept = widget.department;
        _filteredTasks = _currentTasks
            .where((task) =>
                task.technician == widget.username ||
                task.createdBy == widget.username ||
                (dept.isNotEmpty && task.department == dept))
            .toList();
      } else if (role == 'فني') {
        // الفني يرى: المهام المعيّنة له + التي أنشأها
        _filteredTasks = _currentTasks
            .where((task) =>
                task.technician == widget.username ||
                task.createdBy == widget.username)
            .toList();
      } else {
        // موظف عادي: يرى المهام المعيّنة له + التي أنشأها
        _filteredTasks = _currentTasks
            .where((task) =>
                task.technician == widget.username ||
                task.createdBy == widget.username)
            .toList();
      }

      _filteredTasks.sort((a, b) {
        final da = a.closedAt ?? a.createdAt;
        final db = b.closedAt ?? b.createdAt;
        return db.compareTo(da);
      });

      // تطبيق فلتر التاريخ
      _filteredTasks = _applyDateFilter(_filteredTasks);
    });
  }

  void _filterTasksByStatus(String status) {
    setState(() {
      if (status == 'اللوحة') {
        _applyPermissionFilter();
      } else {
        List<Task> statusFilteredTasks =
            _currentTasks.where((task) => task.status == status).toList();

        // تطبيق فلتر الصلاحيات على المهام المفلترة حسب الحالة
        final role2 = _normalizeRole(widget.currentUserRole);
        if (role2 == 'مدير') {
          // المدير يرى جميع المهام
          _filteredTasks = statusFilteredTasks;
        } else if (role2 == 'ليدر') {
          // الليدر يرى: المهام المعينة له + المهام التي أنشأها شخصياً
          _filteredTasks = statusFilteredTasks
              .where((task) =>
                  task.technician == widget.username ||
                  task.createdBy == widget.username)
              .toList();
        } else if (role2 == 'فني') {
          // الفني يرى: المهام المخصصة له + المهام التي أنشأها شخصياً
          _filteredTasks = statusFilteredTasks
              .where((task) =>
                  task.technician == widget.username ||
                  task.createdBy == widget.username)
              .toList();
        } else {
          // أي دور آخر يرى فقط المهام التي أنشأها
          _filteredTasks = statusFilteredTasks
              .where((task) => task.createdBy == widget.username)
              .toList();
        }

        _filteredTasks.sort((a, b) {
          final da = a.closedAt ?? a.createdAt;
          final db = b.closedAt ?? b.createdAt;
          return db.compareTo(da);
        });

        // إذا كنا في تبويب المكتملة ونشط زر اليوم فقط، نرشح حسب تاريخ اليوم (حسب closedAt ثم createdAt)
        if (status == 'مكتملة' && _completedTodayOnly) {
          final now = DateTime.now();
          _filteredTasks = _filteredTasks.where((t) {
            final d = (t.closedAt ?? t.createdAt);
            return d.year == now.year &&
                d.month == now.month &&
                d.day == now.day;
          }).toList();
        }
        // إذا كنا في تبويب الملغية ونشط زر اليوم فقط
        if (status == 'ملغية' && _cancelledTodayOnly) {
          final now = DateTime.now();
          _filteredTasks = _filteredTasks.where((t) {
            final d = (t.closedAt ?? t.createdAt);
            return d.year == now.year &&
                d.month == now.month &&
                d.day == now.day;
          }).toList();
        }

        // تطبيق فلتر التاريخ
        _filteredTasks = _applyDateFilter(_filteredTasks);
      }
    });
  }

  /// تطبيق فلتر التاريخ على قائمة المهام
  List<Task> _applyDateFilter(List<Task> tasks) {
    if (_dateFilter == 'all') return tasks;
    final now = DateTime.now();
    final DateTime targetDate;
    if (_dateFilter == 'yesterday') {
      targetDate = now.subtract(const Duration(days: 1));
    } else {
      targetDate = now; // today
    }
    return tasks.where((t) {
      final d = t.createdAt;
      return d.year == targetDate.year &&
          d.month == targetDate.month &&
          d.day == targetDate.day;
    }).toList();
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 4 بطاقات إحصائية ──
          LayoutBuilder(builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 600;
            if (isMobile) {
              return Column(
                children: [
                  IntrinsicHeight(
                    child: Row(children: [
                      Expanded(child: _buildStatCard('مفتوحة', openTasks, totalTasks, const Color(0xFF3B82F6), Icons.inbox_rounded, compact: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildStatCard('قيد التنفيذ', inProgressTasks, totalTasks, const Color(0xFFF59E0B), Icons.sync_rounded, compact: true)),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  IntrinsicHeight(
                    child: Row(children: [
                      Expanded(child: _buildStatCard('مكتملة', completedTasks, totalTasks, const Color(0xFF10B981), Icons.check_circle_rounded, compact: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildStatCard('ملغية', canceledTasks, totalTasks, const Color(0xFFEF4444), Icons.cancel_rounded, compact: true)),
                    ]),
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: _buildStatCard('مفتوحة', openTasks, totalTasks, const Color(0xFF3B82F6), Icons.inbox_rounded)),
                const SizedBox(width: 14),
                Expanded(child: _buildStatCard('قيد التنفيذ', inProgressTasks, totalTasks, const Color(0xFFF59E0B), Icons.sync_rounded)),
                const SizedBox(width: 14),
                Expanded(child: _buildStatCard('مكتملة', completedTasks, totalTasks, const Color(0xFF10B981), Icons.check_circle_rounded)),
                const SizedBox(width: 14),
                Expanded(child: _buildStatCard('ملغية', canceledTasks, totalTasks, const Color(0xFFEF4444), Icons.cancel_rounded)),
              ],
            );
          }),
          const SizedBox(height: 20),

          // ── بطاقة توزيع المهام حسب الفني ──
          _buildTechnicianDistributionCard(),
        ],
      ),
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
          // رأس الجدول
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2F7),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              border: Border.all(color: const Color(0xFFDDE3EA), width: 0.8),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 50,
                  child: Text('الإجمالي',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280))),
                ),
                SizedBox(
                  width: 45,
                  child: Text('ملغية',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE53935))),
                ),
                SizedBox(
                  width: 45,
                  child: Text('مكتملة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF4CAF50))),
                ),
                SizedBox(
                  width: 45,
                  child: Text('تنفيذ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF9800))),
                ),
                SizedBox(
                  width: 50,
                  child: Text('مفتوحة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2196F3))),
                ),
                Expanded(
                  child: Text('القسم',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280))),
                ),
                Expanded(
                  child: Text('الفني',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280))),
                ),
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

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isEven ? Colors.white : const Color(0xFFF9FAFB),
                border: Border(
                  bottom: BorderSide(color: const Color(0xFFE5E7EB), width: 0.8),
                  left: BorderSide(color: const Color(0xFFE5E7EB), width: 0.8),
                  right: BorderSide(color: const Color(0xFFE5E7EB), width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  // الإجمالي
                  SizedBox(
                    width: 50,
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
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // ملغية
                  SizedBox(
                    width: 45,
                    child: Text(
                      '$canceled',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: canceled > 0
                            ? const Color(0xFFE53935)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ),
                  // مكتملة
                  SizedBox(
                    width: 45,
                    child: Text(
                      '$done',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: done > 0
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ),
                  // تنفيذ
                  SizedBox(
                    width: 45,
                    child: Text(
                      '$progress',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: progress > 0
                            ? const Color(0xFFFF9800)
                            : const Color(0xFFD1D5DB),
                      ),
                    ),
                  ),
                  // مفتوحة
                  SizedBox(
                    width: 50,
                    child: Text(
                      '$open',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
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
                        fontSize: 12,
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
                        Icon(Icons.person_rounded,
                            size: 16, color: const Color(0xFF4FC3F7)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          // صف الإجمالي
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  width: 50,
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
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text(
                    '${_filteredTasks.where((t) => t.status == 'ملغية').length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFE53935),
                    ),
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text(
                    '${_filteredTasks.where((t) => t.status == 'مكتملة').length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text(
                    '${_filteredTasks.where((t) => t.status == 'قيد التنفيذ').length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFF9800),
                    ),
                  ),
                ),
                SizedBox(
                  width: 50,
                  child: Text(
                    '${_filteredTasks.where((t) => t.status == 'مفتوحة').length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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

  /// بطاقة إحصائية
  Widget _buildStatCard(
      String label, int count, int total, Color color, IconData icon, {bool compact = false}) {
    double pct = total > 0 ? (count / total) * 100 : 0;
    final pad = compact ? 12.0 : 18.0;
    final numSize = compact ? 32.0 : 42.0;
    final lblSize = compact ? 13.0 : 16.0;
    final iconSize = compact ? 20.0 : 24.0;
    final iconPad = compact ? 8.0 : 10.0;
    final gap1 = compact ? 10.0 : 14.0;
    final gap2 = compact ? 6.0 : 8.0;
    final gap3 = compact ? 8.0 : 10.0;
    final pctSize = compact ? 12.0 : 14.0;

    return Container(
      padding: EdgeInsets.all(pad),
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
                size: compact ? 20 : 26,
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
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 4),
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
            child: ListView.builder(
              itemCount: _filteredTasks.length,
              itemBuilder: (context, index) {
                final task = _filteredTasks[index];
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  elevation: 4,
                  child: TaskCard(
                    task: task,
                    currentUserRole: widget.currentUserRole,
                    currentUserName: widget.username,
                    onStatusChanged: (updatedTask) {
                      setState(() {
                        final taskIndex = _currentTasks
                            .indexWhere((t) => t.id == updatedTask.id);
                        if (taskIndex != -1) {
                          _currentTasks[taskIndex] = updatedTask;
                          // إعادة الفرز بعد التحديث
                          _currentTasks.sort((a, b) {
                            final da = a.closedAt ?? a.createdAt;
                            final db = b.closedAt ?? b.createdAt;
                            return db.compareTo(da);
                          });
                        }
                        _applyPermissionFilter();
                        _filterTasksByStatus(_getStatusByIndex(currentIndex));
                      });
                      widget.onTaskStatusChanged(updatedTask);
                    },
                  ),
                );
              },
            ),
          );

    // إذا كنا في تبويب المهام المكتملة (index == 3) نضيف أزرار (اليوم / الكل)
    if (currentIndex == 3) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Container(
              padding: const EdgeInsets.all(10),
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
                      icon: const Icon(Icons.today, size: 24),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('اليوم فقط',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          _buildCountChip(_countToday('مكتملة')),
                        ],
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                        minimumSize: const Size.fromHeight(54),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _completedTodayOnly
                          ? () {
                              _completedTodayOnly = false;
                              _filterTasksByStatus('مكتملة');
                            }
                          : null,
                      icon: const Icon(Icons.all_inbox, size: 24),
                      label: const Text('الكل',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                        minimumSize: const Size.fromHeight(54),
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
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Container(
              padding: const EdgeInsets.all(10),
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
                      icon: const Icon(Icons.today, size: 24),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('اليوم فقط',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          _buildCountChip(_countToday('ملغية')),
                        ],
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                        minimumSize: const Size.fromHeight(54),
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _cancelledTodayOnly
                          ? () {
                              _cancelledTodayOnly = false;
                              _filterTasksByStatus('ملغية');
                            }
                          : null,
                      icon: const Icon(Icons.all_inbox, size: 24),
                      label: const Text('الكل',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 12),
                        minimumSize: const Size.fromHeight(54),
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
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                            const TextStyle(fontSize: 9, color: Colors.white),
                      ),
                      backgroundColor: Colors.red,
                      child: Icon(
                        icon,
                        color: isSelected ? Colors.white : color,
                        size: 20,
                      ),
                    )
                  : Icon(
                      icon,
                      color: isSelected ? Colors.white : color,
                      size: 20,
                    ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF6B7280),
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  height: 1.0,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    final current = filters.firstWhere((f) => f['value'] == _dateFilter);
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
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 20),
          isDense: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          selectedItemBuilder: (ctx) => filters.map((f) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(f['icon'] as IconData, size: 15, color: const Color(0xFF4FC3F7)),
              const SizedBox(width: 6),
              Text(f['label'] as String, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          )).toList(),
          items: filters.map((f) => DropdownMenuItem<String>(
            value: f['value'] as String,
            child: Row(
              children: [
                Icon(f['icon'] as IconData, size: 16, color: _dateFilter == f['value'] ? const Color(0xFF4FC3F7) : Colors.white54),
                const SizedBox(width: 8),
                Text(f['label'] as String),
              ],
            ),
          )).toList(),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFF5F7FA),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildDateFilterButton('اليوم', 'today', Icons.today),
          const SizedBox(width: 10),
          _buildDateFilterButton('أمس', 'yesterday', Icons.history),
          const SizedBox(width: 10),
          _buildDateFilterButton('الكل', 'all', Icons.all_inclusive),
        ],
      ),
    );
  }

  Widget _buildDateFilterButton(String label, String value, IconData icon, {bool compact = false}) {
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
              color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.3),
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

  /// شريط الأدوات العلوي مع زر إضافة المهام
  Widget _buildTopActionBar() {
    final r = context.responsive;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: r.contentPaddingH,
        vertical: r.isMobile ? 10 : 15,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        minimum: const EdgeInsets.only(top: 0),
        child: Row(
          children: [
            // زر العودة
            IconButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: Icon(Icons.arrow_back,
                  size: r.appBarIconSize, color: Colors.white),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),

            const SizedBox(width: 6),

            // زر القائمة الجانبية
            if (_shouldShowDrawer())
              IconButton(
                onPressed: openDrawer,
                icon: Icon(Icons.menu,
                    size: r.appBarIconSize, color: Colors.white),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),

            const SizedBox(width: 8),

            // قائمة تصفية التاريخ
            _buildDateFilterDropdown(),

            const Spacer(),

            // أيقونة الإشعارات الجديدة - إضافة جديدة
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications,
                        size: 30, color: Color(0xFF4FC3F7)),
                    tooltip: 'الإشعارات',
                    onPressed: () {
                      // الانتقال مباشرة لنافذة تسجيل الدخول للتذاكر
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => TicketsLoginPage(),
                        ),
                      );
                    },
                    padding: const EdgeInsets.all(6),
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (showNotificationBadge && newTasksCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.red[600],
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.5),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        constraints: BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          newTasksCount > 99 ? '99+' : newTasksCount.toString(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // زر إضافة مهمة جديدة (للمدير والليدر فقط)
            if (widget.currentUserRole == 'مدير' ||
                widget.currentUserRole == 'ليدر')
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: IconButton(
                  icon: const Icon(Icons.add_task,
                      size: 26, color: Color(0xFF66BB6A)),
                  tooltip: 'إضافة مهمة جديدة',
                  onPressed: () => _showAddTaskDialog(),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),

            const SizedBox(width: 6),

            // زر إضافة شراء اشتراك - يظهر للجميع
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: IconButton(
                icon: const Icon(Icons.add_shopping_cart,
                    size: 26, color: Color(0xFF4FC3F7)),
                tooltip: 'إضافة شراء اشتراك',
                onPressed: () => _showAddSubscriptionDialog(),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),

          ],
        ),
      ),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('التصفية'),
        content: const Text('سيتم تطوير نظام التصفية قريباً'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF5F7FA),
      drawer: _shouldShowDrawer()
          ? _buildDrawer()
          : null, // إظهار القائمة الجانبية فقط للليدر والمدير
      body: Column(
        children: [
          // شريط الأدوات العلوي مع زر إضافة المهام
          _buildTopActionBar(),
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
                        : _buildTaskListView(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
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
            height: 75,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
              ],
            ),
          ),
        ),
      ),
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
                      widget.currentUserRole == 'مدير'
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
                    if (widget.currentUserRole == 'مدير' ||
                        widget.currentUserRole == 'ليدر')
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
          : SizedBox(
              width: double.maxFinite,
              height: 400,
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
