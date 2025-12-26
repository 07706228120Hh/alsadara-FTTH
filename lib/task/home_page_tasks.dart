import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis_auth/auth_io.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/task.dart';
import 'task_card.dart';
import 'add_task_dialog.dart';
import '../ftth/tickets/tickets_login_page.dart';
import '../services/google_sheets_service.dart'; // إضافة خدمة Google Sheets
import 'reports_page.dart'; // إضافة صفحة التقارير
import '../services/whatsapp_template_storage.dart'; // إضافة خدمة تخزين قوالب الواتساب
import '../pages/settings_page.dart'; // إضافة صفحة الإعدادات

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
  });

  @override
  HomePageTasksState createState() => HomePageTasksState();
}

class HomePageTasksState extends State<HomePageTasks> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // استخدام متغيرات البيئة الآمنة بدلاً من كشف البيانات
  String get spreadsheetId => dotenv.env['GOOGLE_SHEETS_SPREADSHEET_ID'] ?? '';

  AuthClient? _client;
  List<Task> _currentTasks = [];
  List<Task> _filteredTasks = [];
  bool isLoading = true;
  String? errorMessage;
  int currentIndex = 0;

  Timer? _updateTimer;

  // متغيرات الإشعارات الجديدة
  int newTasksCount = 0; // عدد المهام الجديدة
  List<Task> notifications = []; // قائمة الإشعارات
  bool showNotificationBadge = false; // لإظهار دائرة الإشعار الحمراء
  Set<String> seenTaskIds = <String>{}; // لتتبع المهام المرئية سابقاً
  // عرض مهام اليوم فقط في صفحة المكتملة
  bool _completedTodayOnly = false;
  // عرض مهام اليوم فقط في صفحة الملغية
  bool _cancelledTodayOnly = false;

  @override
  void initState() {
    super.initState();
    _initializeSheetsAPI();
    _startAutoRefresh();

    // ربط الدوال مع الـ callbacks
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupCallbacks();
    });
  }

  void _setupCallbacks() {
    // ربط دالة فتح القائمة
    if (widget.onShowMenu != null) {
      // يمكننا استخدام هذا لاحقاً
    }

    // ربط دالة فتح التصفية
    if (widget.onShowFilter != null) {
      // يمكننا استخدام هذا لاحقاً
    }
  }

  void openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void showFilterPopup() {
    _showFilterPopup(context);
  }

  Future<void> _initializeSheetsAPI() async {
    try {
      final jsonString =
          await rootBundle.loadString('assets/service_account.json');
      final accountCredentials =
          ServiceAccountCredentials.fromJson(jsonDecode(jsonString));
      final scopes = [sheets.SheetsApi.spreadsheetsScope];
      _client = await clientViaServiceAccount(accountCredentials, scopes);
      // Create sheets API with authenticated client
      await _fetchTasks();
    } catch (e) {
      setState(() {
        errorMessage = 'خطأ ��ثناء تهيئة Google Sheets API: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _fetchTasks() async {
    try {
      print('🔄 بدء جلب المهام باستخدام GoogleSheetsService...');

      // استخدام GoogleSheetsService بدلاً من الطريقة المباشرة
      List<Task> fetchedTasks = await GoogleSheetsService.fetchTasks();

      print('✅ تم جلب ${fetchedTasks.length} مهمة بنجاح');

      if (!mounted) return;
      setState(() {
        _currentTasks = fetchedTasks;
        // فرز المهام: الأحدث أولاً (باستخدام closedAt وإذا كانت null نستخدم createdAt)
        _currentTasks.sort((a, b) {
          final da = a.closedAt ?? a.createdAt;
          final db = b.closedAt ?? b.createdAt;
          return db.compareTo(da);
        });
        _applyPermissionFilter();
        _filterTasksByStatus(_getStatusByIndex(currentIndex));
        isLoading = false;
        errorMessage = null; // مسح أي رسائل خطأ سابقة
      });
    } catch (e) {
      print('❌ خطأ في جلب المهام: $e');
      setState(() {
        errorMessage = 'خطأ أثناء جلب المهام: $e';
        isLoading = false;
      });
    }
  }

  void _startAutoRefresh() {
    _updateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchTasks();
    });
  }

  void _stopAutoRefresh() {
    _updateTimer?.cancel();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    _client?.close();
    super.dispose();
  }

  void _applyPermissionFilter() {
    setState(() {
      if (widget.currentUserRole == 'مدير') {
        // المدير يرى جميع المهام
        _filteredTasks = _currentTasks;
      } else if (widget.currentUserRole == 'ليدر') {
        // الليدر يرى: مهام قسمه + المهام التي أنشأها شخصياً (مثل شراء الاشتراك)
        _filteredTasks = _currentTasks
            .where((task) =>
                task.department == widget.department ||
                task.createdBy == widget.username)
            .toList();
      } else if (widget.currentUserRole == 'فني') {
        // الفني يرى: المهام المخصصة له + المهام التي أنشأها شخصياً (مثل شراء الاشتراك)
        _filteredTasks = _currentTasks
            .where((task) =>
                task.technician == widget.username ||
                task.createdBy == widget.username)
            .toList();
      } else {
        // أي دور آخر يرى فقط المهام التي أنشأها
        _filteredTasks = _currentTasks
            .where((task) => task.createdBy == widget.username)
            .toList();
      }

      _filteredTasks.sort((a, b) {
        final da = a.closedAt ?? a.createdAt;
        final db = b.closedAt ?? b.createdAt;
        return db.compareTo(da);
      });
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
        if (widget.currentUserRole == 'مدير') {
          // المدير يرى جميع المهام
          _filteredTasks = statusFilteredTasks;
        } else if (widget.currentUserRole == 'ليدر') {
          // الليدر يرى: مهام قسمه + المهام التي أنشأها شخصياً
          _filteredTasks = statusFilteredTasks
              .where((task) =>
                  task.department == widget.department ||
                  task.createdBy == widget.username)
              .toList();
        } else if (widget.currentUserRole == 'فني') {
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
      }
    });
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

  /// بناء وا��هة اللوحة الرئيسية
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
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),

          // بطاقات الإحصائيات
          Row(
            children: [
              Expanded(
                child: _buildModernStatCard(
                  'مفتوحة',
                  openTasks,
                  Colors.blue[600]!,
                  Icons.lock_open,
                  totalTasks,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModernStatCard(
                  'قيد التنفيذ',
                  inProgressTasks,
                  Colors.orange[600]!,
                  Icons.settings,
                  totalTasks,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _buildModernStatCard(
                  'مكتملة',
                  completedTasks,
                  Colors.green[600]!,
                  Icons.check_circle,
                  totalTasks,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildModernStatCard(
                  'ملغية',
                  canceledTasks,
                  Colors.red[600]!,
                  Icons.cancel,
                  totalTasks,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // المخط�� البياني
          Container(
            height: 300,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Text(
                  'توزيع المهام',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: (totalTasks * 1.2).toDouble(),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                value.toInt().toString(),
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              switch (value.toInt()) {
                                case 1:
                                  return Text('مفتوحة',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11));
                                case 2:
                                  return Text('تنفيذ',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11));
                                case 3:
                                  return Text('مكتملة',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11));
                                case 4:
                                  return Text('ملغية',
                                      style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11));
                                default:
                                  return const Text('');
                              }
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 1,
                        getDrawingHorizontalLine: (value) {
                          return FlLine(
                            color: Colors.grey[300]!,
                            strokeWidth: 1,
                          );
                        },
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          bottom:
                              BorderSide(color: Colors.grey[300]!, width: 1),
                          left: BorderSide(color: Colors.grey[300]!, width: 1),
                        ),
                      ),
                      barGroups: [
                        BarChartGroupData(x: 1, barRods: [
                          BarChartRodData(
                            toY: openTasks.toDouble(),
                            color: Colors.blue[600]!,
                            width: 40,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ]),
                        BarChartGroupData(x: 2, barRods: [
                          BarChartRodData(
                            toY: inProgressTasks.toDouble(),
                            color: Colors.orange[600]!,
                            width: 40,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ]),
                        BarChartGroupData(x: 3, barRods: [
                          BarChartRodData(
                            toY: completedTasks.toDouble(),
                            color: Colors.green[600]!,
                            width: 40,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ]),
                        BarChartGroupData(x: 4, barRods: [
                          BarChartRodData(
                            toY: canceledTasks.toDouble(),
                            color: Colors.red[600]!,
                            width: 40,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ]),
                      ],
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

  /// بناء بطاقة إحصائيات عصرية
  Widget _buildModernStatCard(
      String title, int count, Color color, IconData icon, int total) {
    double percentage = total > 0 ? (count / total) * 100 : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.1), color.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
        ],
      ),
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                border: Border.all(color: Colors.grey.shade300, width: 1),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.08),
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
                border: Border.all(color: Colors.grey.shade300, width: 1),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.08),
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
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
          constraints: const BoxConstraints(
            minHeight: 55,
            maxHeight: 60,
          ),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color,
                      color.withValues(alpha: 0.7),
                    ],
                  )
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white,
                      Colors.grey[50]!,
                    ],
                  ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
            border: Border.all(
              color: isSelected
                  ? color.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.2),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? Colors.white : color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : color,
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
      debugPrint('حدث خطأ أثناء فتح التقارير: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء فتح التقارير: $e'),
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

  /// شريط الأدوات العل��ي مع زر إضافة المهام
  Widget _buildTopActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[50]!, Colors.white],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: SafeArea(
        minimum: const EdgeInsets.only(top: 0),
        child: Row(
          children: [
            // زر القائمة في أعلى اليسار (فقط للليدر والمدير)
            if (_shouldShowDrawer())
              IconButton(
                onPressed: openDrawer,
                icon: const Icon(Icons.menu, size: 30),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.blue.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),

            // مساحة إضافية للفني بدلاً من زر القائمة
            if (!_shouldShowDrawer()) const SizedBox(width: 36),

            const SizedBox(width: 8),

            // الترحيب بالمستخدم في الوسط
            Expanded(
              child: Text(
                'مرحباً ${widget.username}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(width: 8),

            // أيقونة الإشعارات الجديدة - إضافة جديدة
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications, size: 30),
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

            // زر إضافة شراء اشتراك - يظهر للجميع
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: IconButton(
                icon: const Icon(Icons.add_shopping_cart, size: 26),
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

            const SizedBox(width: 6),

            // زر العودة في أعلى اليمين
            IconButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.keyboard_return, size: 30),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
      builder: (context) => AddTaskDialog(
        currentUsername: widget.username,
        currentUserRole: widget.currentUserRole,
        currentUserDepartment: widget.department,
        onTaskAdded: (newTask) {
          // إضافة المهمة الجديدة للقائمة وتحديث الواجهة
          setState(() {
            _currentTasks.insert(0, newTask);
            _currentTasks.sort((a, b) {
              final da = a.closedAt ?? a.createdAt;
              final db = b.closedAt ?? b.createdAt;
              return db.compareTo(da);
            });
            _applyPermissionFilter();
            _filterTasksByStatus(_getStatusByIndex(currentIndex));
          });

          // عرض رسالة نجاح مع تفاصيل الإشعارات
          _showTaskAddedSuccessMessage(newTask);
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
      builder: (context) => AddTaskDialog(
        currentUsername: widget.username,
        currentUserRole: widget.currentUserRole,
        currentUserDepartment: widget.department,
        onTaskAdded: (newTask) {
          // إضافة المهمة الجديدة للقائمة وتحديث الواجهة
          setState(() {
            _currentTasks.insert(0, newTask);
            _currentTasks.sort((a, b) {
              final da = a.closedAt ?? a.createdAt;
              final db = b.closedAt ?? b.createdAt;
              return db.compareTo(da);
            });
            _applyPermissionFilter();
            _filterTasksByStatus(_getStatusByIndex(currentIndex));
          });

          // عرض رسالة نجاح مع تفاصيل الإشعارات
          _showTaskAddedSuccessMessage(newTask);
        },
      ),
    );
  }

  /// عرض رسالة نجاح مع تفاصيل الإشعارات المرسلة
  void _showTaskAddedSuccessMessage(Task task) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'تم إضافة المهمة بنج��ح!',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('المهمة: ${task.title}'),
              Text('مكلف بها: ${task.technician}'),
              const Text('✅ تم إرسال إشعارات فورية للفريق المعني'),
            ],
          ),
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        action: SnackBarAction(
          label: '��غلاق',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
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
      drawer: _shouldShowDrawer()
          ? _buildDrawer()
          : null, // إظهار القائمة الجانبية فقط للليدر والمدير
      body: Column(
        children: [
          // شريط الأدوات العل��ي مع زر إضافة المهام
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
                              onPressed: _fetchTasks,
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
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.blue[50]!.withValues(alpha: 0.8),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, -5),
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.blue.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -10),
            ),
          ],
          border: Border(
            top: BorderSide(
              color: Colors.blue.withValues(alpha: 0.1),
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
                    // إضافة مهمة جديدة (للمدير والليدر فقط)
                    if (widget.currentUserRole == 'مدير' ||
                        widget.currentUserRole == 'ليدر')
                      _buildDrawerItem(
                        icon: Icons.add_task,
                        title: 'إضافة مهمة جديدة',
                        subtitle: 'إنشاء مهمة جديدة',
                        onTap: () {
                          Navigator.pop(context);
                          _showAddTaskDialog();
                        },
                        color: Colors.green,
                      ),

                    // إضافة شراء اشتراك (للجميع)
                    _buildDrawerItem(
                      icon: Icons.add_shopping_cart,
                      title: 'إضافة شراء اشتراك',
                      subtitle: 'طلب شراء اشتراك جديد',
                      onTap: () {
                        Navigator.pop(context);
                        _showAddSubscriptionDialog();
                      },
                      color: Colors.purple,
                    ),

                    // التقارير (للمدير والليدر فقط)
                    if (widget.currentUserRole == 'مدير' ||
                        widget.currentUserRole == 'ليدر')
                      _buildDrawerItem(
                        icon: Icons.analytics,
                        title: 'التقارير والإحصائيات',
                        subtitle: 'عرض التقارير الت��صيلية',
                        onTap: () {
                          Navigator.pop(context);
                          _showAllTasks();
                        },
                        color: Colors.blue,
                      ),

                    // إعدادات المستخدم (للمدير فقط)
                    if (widget.currentUserRole == 'مدير')
                      _buildDrawerItem(
                        icon: Icons.settings,
                        title: 'الإعدادات',
                        subtitle: 'إعدادات الحساب والتطبيق',
                        onTap: () {
                          Navigator.pop(context);
                          // الانتقال إلى صفحة الإعدادات
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SettingsPage(
                                currentUserRole: widget.currentUserRole,
                                currentUsername: widget.username,
                              ),
                            ),
                          );
                        },
                        color: Colors.orange,
                      ),

                    // تعديل رسالة الواتساب (للمدير والليدر فقط)
                    if (widget.currentUserRole == 'مدير' ||
                        widget.currentUserRole == 'ليدر')
                      _buildDrawerItem(
                        icon: Icons.message_outlined,
                        title: 'تعديل رسالة الواتساب',
                        subtitle: 'تخصيص قالب رسائل الواتساب',
                        onTap: () {
                          Navigator.pop(context);
                          _showWhatsAppTemplateEditor();
                        },
                        color: Colors.green,
                      ),

                    // خط فاصل
                    const Divider(),

                    // معلومات حول التطبيق
                    _buildDrawerItem(
                      icon: Icons.info,
                      title: 'حول التطبيق',
                      subtitle: 'معلومات الإصدار والدعم',
                      onTap: () {
                        Navigator.pop(context);
                        _showAboutDialog();
                      },
                      color: Colors.grey,
                    ),

                    // تسجيل الخروج
                    _buildDrawerItem(
                      icon: Icons.logout,
                      title: 'تسجيل الخروج',
                      subtitle: 'الخروج من الحساب',
                      onTap: () {
                        Navigator.pop(context);
                        _showLogoutDialog();
                      },
                      color: Colors.red,
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
            content: Text('خطأ في حفظ القالب: $e'),
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
