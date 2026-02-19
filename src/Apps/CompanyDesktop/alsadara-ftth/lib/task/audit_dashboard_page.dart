import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/task.dart';
import '../services/task_api_service.dart';

// ═══════════════════════════════════════════════════════════════
//  Premium Dark Theme Constants
// ═══════════════════════════════════════════════════════════════
const _bgDark = Color(0xFF0B1121);
const _bgCard = Color(0xFF111B2E);
const _navy = Color(0xFF1B2A4A);
const _navyDark = Color(0xFF0A0F1A);
const _blue = Color(0xFF4A9FFF);
const _green = Color(0xFF2ECC71);
const _red = Color(0xFFFF5252);
const _amber = Color(0xFFFFB74D);
const _orange = Color(0xFFFF7043);
const _purple = Color(0xFFAB47BC);
const _cyan = Color(0xFF26C6DA);
const _teal = Color(0xFF26A69A);
const _textPrimary = Color(0xFFE8EAF0);
const _textSecondary = Color(0xFF8892A4);
const _glassBorder = Color(0x20FFFFFF);
const _glassCard = Color(0x12FFFFFF);

// ═══════════════════ In-Memory Cache ═══════════════════
class _AuditCache {
  static List<Task>? cachedTasks;
  static Map<String, dynamic>? cachedAudits;
  static DateTime? lastFetchTime;

  static bool get hasCache =>
      cachedTasks != null &&
      lastFetchTime != null &&
      DateTime.now().difference(lastFetchTime!).inMinutes < 5;

  static void clear() {
    cachedTasks = null;
    cachedAudits = null;
    lastFetchTime = null;
  }
}

class AuditDashboardPage extends StatefulWidget {
  final String username;
  final String permissions;
  final String department;
  final String center;

  const AuditDashboardPage({
    super.key,
    required this.username,
    required this.permissions,
    required this.department,
    required this.center,
  });

  @override
  State<AuditDashboardPage> createState() => _AuditDashboardPageState();
}

class _AuditDashboardPageState extends State<AuditDashboardPage>
    with TickerProviderStateMixin {
  List<Task> _allTasks = [];
  List<Task> _completedTasks = [];
  List<Task> _cancelledTasks = [];
  bool _isLoading = true;

  final Map<String, String> _auditStatus = {};
  final Map<String, int> _ratings = {};
  final Map<String, String> _auditNotes = {};

  // ═══ فلتر التاريخ ═══
  DateTime? _filterStart;
  DateTime? _filterEnd;
  String _filterLabel = 'الكل';

  // ═══ تبديل القائمة الجانبية ═══
  int _sideTab = 2; // 0=الأقسام, 1=أنواع المهام, 2=تقدم التدقيق

  late AnimationController _staggerController;
  late AnimationController _gaugeController;
  late Animation<double> _gaugeAnimation;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _gaugeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _gaugeAnimation = CurvedAnimation(
      parent: _gaugeController,
      curve: Curves.easeOutCubic,
    );

    // ── تحميل من الكاش فوراً ──
    if (_AuditCache.hasCache) {
      _loadFromCache();
      _isLoading = false;
    }

    // تحميل/تحديث البيانات في الخلفية
    _fetchData();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _gaugeController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    debugPrint('📊 [AuditDashboard] بدء جلب البيانات...');
    final sw = Stopwatch()..start();

    try {
      // جلب الطلبات والتدقيقات بالتوازي — timeout 10 ثوانٍ
      final results = await Future.wait([
        TaskApiService.instance.getRequests(pageSize: 200),
        TaskApiService.instance.getAuditsBulk(),
      ]).timeout(const Duration(seconds: 10));

      sw.stop();
      debugPrint(
          '📊 [AuditDashboard] وقت الاستجابة: ${sw.elapsedMilliseconds}ms');

      if (!mounted) return;

      final tasksResp = results[0];
      final auditsResp = results[1];

      if (tasksResp['success'] != true) {
        debugPrint(
            '❌ [AuditDashboard] فشل: ${tasksResp['message']} (${tasksResp['statusCode']})');
      } else {
        _processResults(tasksResp, auditsResp);
        // حفظ في الكاش
        _AuditCache.cachedTasks = List.from(_allTasks);
        _AuditCache.cachedAudits = {
          'status': Map.from(_auditStatus),
          'ratings': Map.from(_ratings),
          'notes': Map.from(_auditNotes),
        };
        _AuditCache.lastFetchTime = DateTime.now();
        debugPrint('✅ [AuditDashboard] تم تحميل ${_allTasks.length} مهمة');
      }
    } on TimeoutException {
      debugPrint('⏰ [AuditDashboard] انتهت مهلة الاتصال');
    } catch (e) {
      debugPrint('❌ [AuditDashboard] خطأ: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _staggerController.forward(from: 0);
        _gaugeController.forward(from: 0);
      }
    }
  }

  /// تحميل البيانات من الكاش المحلي
  void _loadFromCache() {
    if (_AuditCache.cachedTasks != null) {
      _allTasks = List.from(_AuditCache.cachedTasks!);
      _completedTasks = _allTasks.where((t) => t.status == 'مكتملة').toList();
      _cancelledTasks = _allTasks.where((t) => t.status == 'ملغية').toList();
    }
    if (_AuditCache.cachedAudits != null) {
      final cached = _AuditCache.cachedAudits!;
      _auditStatus
        ..clear()
        ..addAll(Map<String, String>.from(cached['status'] ?? {}));
      _ratings
        ..clear()
        ..addAll(Map<String, int>.from(cached['ratings'] ?? {}));
      _auditNotes
        ..clear()
        ..addAll(Map<String, String>.from(cached['notes'] ?? {}));
    }
  }

  /// معالجة نتائج API
  void _processResults(
      Map<String, dynamic> tasksResp, Map<String, dynamic> auditsResp) {
    if (tasksResp['success'] == true && tasksResp['data'] is List) {
      _allTasks = (tasksResp['data'] as List)
          .map((item) =>
              Task.fromApiResponse(Map<String, dynamic>.from(item as Map)))
          .toList();
      _completedTasks = _allTasks.where((t) => t.status == 'مكتملة').toList();
      _cancelledTasks = _allTasks.where((t) => t.status == 'ملغية').toList();
    }
    if (auditsResp['success'] == true && auditsResp['data'] is Map) {
      final audits = Map<String, dynamic>.from(auditsResp['data'] as Map);
      _auditStatus.clear();
      _ratings.clear();
      _auditNotes.clear();
      for (final entry in audits.entries) {
        final data = entry.value;
        if (data is Map) {
          _auditStatus[entry.key] = data['AuditStatus']?.toString() ?? 'لم يتم';
          final rating = data['Rating'] as int? ?? 0;
          if (rating > 0) _ratings[entry.key] = rating;
          final notes = data['Notes']?.toString();
          if (notes != null && notes.isNotEmpty) {
            _auditNotes[entry.key] = notes;
          }
        }
      }
    }
  }

  // ═══════════════════ Filtered Lists ═══════════════════

  List<Task> get _filteredTasks {
    if (_filterStart == null || _filterEnd == null) return _allTasks;
    return _allTasks.where((t) {
      return !t.createdAt.isBefore(_filterStart!) &&
          t.createdAt.isBefore(_filterEnd!);
    }).toList();
  }

  List<Task> get _filteredCompleted =>
      _filteredTasks.where((t) => t.status == 'مكتملة').toList();

  List<Task> get _filteredCancelled =>
      _filteredTasks.where((t) => t.status == 'ملغية').toList();

  // ═══════════════════ Computed Stats ═══════════════════

  int get _totalTasks => _filteredTasks.length;
  int get _openTasks => _filteredTasks
      .where((t) => t.status == 'مفتوحة' || t.status == 'قيد التنفيذ')
      .length;
  int get _inProgressTasks =>
      _filteredTasks.where((t) => t.status == 'قيد التنفيذ').length;
  int get _completedCount => _filteredCompleted.length;
  int get _cancelledCount => _filteredCancelled.length;

  /// مكتملة ضمن الوقت (≤ 90 دقيقة)
  int get _completedOnTime => _filteredCompleted.where((t) {
        if (t.closedAt == null) return false;
        return t.closedAt!.difference(t.createdAt).inMinutes <= 90;
      }).length;

  /// مكتملة خارج الوقت (> 90 دقيقة)
  int get _completedLate => _filteredCompleted.where((t) {
        if (t.closedAt == null) return true;
        return t.closedAt!.difference(t.createdAt).inMinutes > 90;
      }).length;

  List<Task> get _auditableTasks => _filteredTasks
      .where((t) => t.status == 'مكتملة' || t.status == 'ملغية')
      .toList();

  /// المهام اللي راجعها المدقق (سليمة فقط — بدون المشاكل)
  int get _auditedCleanCount {
    final ids = _auditableTasks.map((t) => t.id).toSet();
    return _auditStatus.entries
        .where((e) => ids.contains(e.key) && e.value == 'تم التدقيق')
        .length;
  }

  /// إجمالي المهام المُدققة (سليمة + مشاكل = كل اللي راجعها المدقق)
  int get _auditedCount => _auditedCleanCount + _issueCount;

  /// المهام اللي ما راجعها المدقق بعد
  int get _notAuditedCount {
    return _auditableTasks.length - _auditedCount;
  }

  /// المهام اللي فيها مشاكل (جزء من "تم التدقيق")
  int get _issueCount {
    final ids = _auditableTasks.map((t) => t.id).toSet();
    return _auditStatus.entries
        .where((e) => ids.contains(e.key) && e.value == 'مشكلة')
        .length;
  }

  double get _auditProgress {
    final total = _auditableTasks.length;
    if (total == 0) return 0;
    return _auditedCount / total;
  }

  double get _overallAvgRating {
    final ids = _auditableTasks.map((t) => t.id).toSet();
    final filtered = _ratings.entries.where((e) => ids.contains(e.key));
    if (filtered.isEmpty) return 0;
    return filtered.map((e) => e.value).reduce((a, b) => a + b) /
        filtered.length;
  }

  // ═══ تقييم الوقت ═══
  // الحد الأقصى 90 دقيقة (ساعة ونصف) — بعدها يعتبر فشل
  static int _calcTimeRating(int minutes) {
    if (minutes <= 20) return 5; // ممتاز — أقل من 20 دقيقة
    if (minutes <= 40) return 4; // جيد جداً
    if (minutes <= 60) return 3; // جيد — ساعة
    if (minutes <= 90) return 2; // مقبول — ساعة ونصف (الحد الأقصى)
    return 1; // فشل — أكثر من ساعة ونصف
  }

  double get _overallTimeRating {
    int sum = 0, count = 0;
    for (final task in _auditableTasks) {
      if (task.closedAt != null) {
        final mins = task.closedAt!.difference(task.createdAt).inMinutes;
        if (mins >= 0) {
          sum += _calcTimeRating(mins);
          count++;
        }
      }
    }
    return count > 0 ? sum / count : 0;
  }

  // Department distribution
  Map<String, int> get _departmentDistribution {
    final map = <String, int>{};
    for (final task in _filteredTasks) {
      final dept = task.department.isNotEmpty ? task.department : 'غير محدد';
      map[dept] = (map[dept] ?? 0) + 1;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  Map<String, _TechnicianStats> get _technicianStats {
    final map = <String, _TechnicianStats>{};
    for (final task in _auditableTasks) {
      final name = task.technician.isNotEmpty ? task.technician : 'غير محدد';
      map.putIfAbsent(name, () => _TechnicianStats(name));
      map[name]!.totalTasks++;
      if (task.status == 'مكتملة') map[name]!.completed++;
      if (task.status == 'ملغية') map[name]!.cancelled++;
      // مكتملة بالوقت / متأخرة
      if (task.status == 'مكتملة' && task.closedAt != null) {
        final mins = task.closedAt!.difference(task.createdAt).inMinutes;
        if (mins <= 90) {
          map[name]!.onTime++;
        } else {
          map[name]!.late_++;
        }
      }
      final status = _auditStatus[task.id];
      if (status == 'تم التدقيق') map[name]!.audited++;
      if (status == 'مشكلة') map[name]!.issues++;
      final rating = _ratings[task.id];
      if (rating != null && rating > 0) {
        map[name]!.ratingSum += rating;
        map[name]!.ratingCount++;
      }
      // تقييم الوقت
      if (task.closedAt != null) {
        final mins = task.closedAt!.difference(task.createdAt).inMinutes;
        if (mins >= 0) {
          map[name]!.timeRatingSum += _calcTimeRating(mins);
          map[name]!.timeRatingCount++;
        }
      }
    }
    return map;
  }

  Map<String, int> get _taskTypeDistribution {
    final map = <String, int>{};
    for (final task in _filteredTasks) {
      final type = task.title.isNotEmpty ? task.title : 'غير محدد';
      map[type] = (map[type] ?? 0) + 1;
    }
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(8));
  }

  List<Task> get _issueTasks {
    return _auditableTasks.where((t) => _auditStatus[t.id] == 'مشكلة').toList();
  }

  Map<String, _MonthlyStats> get _monthlyStats {
    final map = <String, _MonthlyStats>{};
    for (final task in _filteredTasks) {
      final key = DateFormat('yyyy-MM').format(task.createdAt);
      map.putIfAbsent(key, () => _MonthlyStats(key));
      map[key]!.total++;
      if (task.status == 'مكتملة') map[key]!.completed++;
      if (task.status == 'ملغية') map[key]!.cancelled++;
    }
    final sorted = map.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    return Map.fromEntries(sorted.take(6));
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bgDark,
        body: _isLoading ? _buildLoading() : _buildDashboard(),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_bgDark, Color(0xFF0E1726), _bgDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: _blue.withValues(alpha: 0.3), blurRadius: 30)
                ],
              ),
              child: const CircularProgressIndicator(
                color: _blue,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
              ),
            ),
            const SizedBox(height: 20),
            const Text('جاري تحميل البيانات...',
                style: TextStyle(
                    color: _textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Dashboard Layout - Single Screen with Staggered Animations
  // ═══════════════════════════════════════════════════════════════

  Widget _staggerChild(int index, int total, Widget child) {
    final begin = index / total;
    final end = min(1.0, begin + 0.4);
    final anim = CurvedAnimation(
      parent: _staggerController,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - anim.value)),
          child: child,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  New Scrollable Dashboard Layout
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDashboard() {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // 1. Top Key Metrics Cards
                _staggerChild(0, 3, _buildTopMetricsRow()),
                const SizedBox(height: 20),

                // 2. Detailed Lists Section (Technicians + Departments)
                _staggerChild(
                    1,
                    3,
                    SizedBox(
                      height: 420,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                              flex: 2, child: _buildTechnicianTableSection()),
                          const SizedBox(width: 20),
                          Expanded(
                              flex: 1, child: _buildSecondaryStatsColumn()),
                        ],
                      ),
                    )),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Section 1: Top Metrics Cards
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTopMetricsRow() {
    return SizedBox(
      height: 140,
      child: Row(
        children: [
          // 1) إجمالي المهام
          _metricCard(
            title: 'إجمالي المهام',
            value: '$_totalTasks',
            subValue: 'كل المهام المسجلة',
            icon: Icons.assignment_rounded,
            color: _blue,
            gradient: [
              _blue.withValues(alpha: 0.8),
              _blue.withValues(alpha: 0.4)
            ],
          ),
          const SizedBox(width: 12),
          // 2) المفتوحة
          _metricCard(
            title: 'المفتوحة',
            value: '$_openTasks',
            subValue: 'قيد الانتظار أو التنفيذ',
            icon: Icons.pending_actions_rounded,
            color: _cyan,
            gradient: [
              _cyan.withValues(alpha: 0.8),
              _cyan.withValues(alpha: 0.4)
            ],
          ),
          const SizedBox(width: 12),
          // 3) مكتملة ضمن الوقت
          _metricCard(
            title: 'مكتملة بالوقت',
            value: '$_completedOnTime',
            subValue: '≤ ساعة ونص',
            icon: Icons.check_circle_rounded,
            color: _green,
            gradient: [
              _green.withValues(alpha: 0.8),
              _green.withValues(alpha: 0.4)
            ],
          ),
          const SizedBox(width: 12),
          // 4) مكتملة خارج الوقت
          _metricCard(
            title: 'متأخرة',
            value: '$_completedLate',
            subValue: '> ساعة ونص',
            icon: Icons.timer_off_rounded,
            color: _orange,
            gradient: [
              _orange.withValues(alpha: 0.8),
              _orange.withValues(alpha: 0.4)
            ],
            isAlert: _completedLate > 0,
          ),
          const SizedBox(width: 12),
          // 5) الملغية
          _metricCard(
            title: 'الملغية',
            value: '$_cancelledCount',
            subValue: 'مهام تم إلغاؤها',
            icon: Icons.cancel_rounded,
            color: _red,
            gradient: [
              _red.withValues(alpha: 0.8),
              _red.withValues(alpha: 0.4)
            ],
            isAlert: _cancelledCount > 0,
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subValue,
    required IconData icon,
    required Color color,
    required List<Color> gradient,
    bool isAlert = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: isAlert ? color.withValues(alpha: 0.5) : _glassBorder,
              width: isAlert ? 1.5 : 1),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          color: _textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            Center(
              child: Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1)),
            ),
            Text(subValue,
                style: TextStyle(
                    color:
                        isAlert ? color : _textSecondary.withValues(alpha: 0.7),
                    fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Top Bar — Premium Glass
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    final issues = _issueTasks;
    return ClipRRect(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _bgCard.withValues(alpha: 0.9),
              _navy.withValues(alpha: 0.7),
            ],
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
          ),
          border:
              const Border(bottom: BorderSide(color: _glassBorder, width: 1)),
          boxShadow: [
            BoxShadow(
              color: _blue.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _topBtn(Icons.arrow_forward_rounded, () => Navigator.pop(context)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_blue, _cyan]),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: _blue.withValues(alpha: 0.3), blurRadius: 8)
                ],
              ),
              child: const Icon(Icons.dashboard_customize_rounded,
                  color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFF64B5F6), Color(0xFF42A5F5)],
              ).createShader(bounds),
              child: const Text('لوحة تحكم التدقيق',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Text(DateFormat('yyyy/MM/dd').format(DateTime.now()),
                style: const TextStyle(color: _textSecondary, fontSize: 11)),
            const Spacer(),
            // ── أزرار فلتر التاريخ ──
            _filterChip('الكل', _filterLabel == 'الكل', () {
              setState(() {
                _filterStart = null;
                _filterEnd = null;
                _filterLabel = 'الكل';
              });
            }),
            const SizedBox(width: 6),
            _filterChip('اليوم', _filterLabel == 'اليوم', () {
              final now = DateTime.now();
              final start = DateTime(now.year, now.month, now.day);
              setState(() {
                _filterStart = start;
                _filterEnd = start.add(const Duration(days: 1));
                _filterLabel = 'اليوم';
              });
            }),
            const SizedBox(width: 6),
            _filterChip('الأمس', _filterLabel == 'الأمس', () {
              final now = DateTime.now();
              final yesterday = DateTime(now.year, now.month, now.day)
                  .subtract(const Duration(days: 1));
              setState(() {
                _filterStart = yesterday;
                _filterEnd = yesterday.add(const Duration(days: 1));
                _filterLabel = 'الأمس';
              });
            }),
            const SizedBox(width: 6),
            _filterChip(
              _filterLabel != 'الكل' &&
                      _filterLabel != 'اليوم' &&
                      _filterLabel != 'الأمس'
                  ? _filterLabel
                  : 'تاريخ',
              _filterLabel != 'الكل' &&
                  _filterLabel != 'اليوم' &&
                  _filterLabel != 'الأمس',
              () => _pickDateRange(),
              icon: Icons.date_range_rounded,
            ),
            const SizedBox(width: 10),
            _topBtn(Icons.refresh_rounded, _fetchData),
          ],
        ),
      ),
    );
  }

  // ── فلتر التاريخ ──
  Widget _filterChip(String label, bool active, VoidCallback onTap,
      {IconData? icon}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? _blue.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? _blue : _glassBorder,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: active ? _blue : _textSecondary, size: 14),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                  color: active ? _blue : _textSecondary,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.bold : FontWeight.w500,
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _filterStart != null && _filterEnd != null
          ? DateTimeRange(
              start: _filterStart!,
              end: _filterEnd!.subtract(const Duration(days: 1)))
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)), end: now),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: _blue,
              onPrimary: Colors.white,
              surface: _bgCard,
              onSurface: _textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      final fmt = DateFormat('MM/dd');
      setState(() {
        _filterStart = picked.start;
        _filterEnd = DateTime(picked.end.year, picked.end.month, picked.end.day)
            .add(const Duration(days: 1));
        _filterLabel =
            '${fmt.format(picked.start)} - ${fmt.format(picked.end)}';
      });
    }
  }

  Widget _topBadge(IconData icon, String val, String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.15), blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 14),
          const SizedBox(width: 5),
          Text(val,
              style: TextStyle(
                  color: c, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: _textSecondary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _topBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: _glassCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _glassBorder),
        ),
        child: Icon(icon, color: _textSecondary, size: 18),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Section 2: Main Charts
  // ═══════════════════════════════════════════════════════════════

  Widget _buildMonthlyChartSection() {
    final monthly = _monthlyStats;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('الإحصائيات الشهرية',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('مقارنة أداء المهام خلال الأشهر الماضية',
                      style: TextStyle(color: _textSecondary, fontSize: 12)),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bar_chart_rounded, color: _blue),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: monthly.isEmpty
                ? _emptyState()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final entries =
                          monthly.entries.toList().reversed.toList();
                      final maxTotal =
                          entries.map((e) => e.value.total).reduce(max);
                      // Use simpler bar chart
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: entries.map((entry) {
                          final stats = entry.value;
                          final dt = DateTime.tryParse('${entry.key}-01');
                          final label = dt != null
                              ? DateFormat('MMM', 'ar').format(dt)
                              : entry.key;
                          final ratio =
                              maxTotal > 0 ? stats.total / maxTotal : 0.0;

                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${stats.total}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    // Background Track
                                    Container(
                                      width: 24,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    // Animated Bar
                                    FractionallySizedBox(
                                      heightFactor: ratio.clamp(0.0, 1.0),
                                      child: Container(
                                        width: 24,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              _blue,
                                              _blue.withValues(alpha: 0.6)
                                            ],
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  _blue.withValues(alpha: 0.4),
                                              blurRadius: 10,
                                              offset: const Offset(0, -4),
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(label,
                                  style: const TextStyle(
                                      color: _textSecondary, fontSize: 12)),
                            ],
                          );
                        }).toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditGaugeSection() {
    final auditable = _auditableTasks.length;
    final pct = _auditProgress * 100;
    final gaugeColor = _auditProgress >= 0.8
        ? _green
        : _auditProgress >= 0.5
            ? _amber
            : _red;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('تقدم التدقيق',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('نسبة الإنجاز الكلية',
              style: TextStyle(color: _textSecondary, fontSize: 12)),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer Glow
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                    BoxShadow(
                        color: gaugeColor.withValues(alpha: 0.15),
                        blurRadius: 40)
                  ]),
                ),
                SizedBox(
                  width: 160,
                  height: 160,
                  child: AnimatedBuilder(
                    animation: _gaugeAnimation,
                    builder: (_, __) {
                      return CircularProgressIndicator(
                        value: _auditProgress * _gaugeAnimation.value,
                        strokeWidth: 16,
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation(gaugeColor),
                        strokeCap: StrokeCap.round,
                      );
                    },
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: gaugeColor,
                            fontSize: 36,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('$_auditedCount / $auditable',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _bgDark,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _miniStatItem('تم التدقيق', '$_auditedCount', _green),
                Container(width: 1, height: 24, color: Colors.white10),
                _miniStatItem('لم يتم', '$_notAuditedCount', _amber),
                Container(width: 1, height: 24, color: Colors.white10),
                _miniStatItem('مشاكل', '$_issueCount', _red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label,
            style: const TextStyle(color: _textSecondary, fontSize: 10)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Section 3: Detailed Lists
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTechnicianTableSection() {
    final stats = _technicianStats;
    final sorted = stats.values.toList()
      ..sort((a, b) => b.totalTasks.compareTo(a.totalTasks));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('أداء الفنيين',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.people_rounded, color: _purple),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _bgDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: const Row(
              children: [
                Expanded(
                    flex: 3,
                    child: Text('الفني',
                        style: TextStyle(color: _textSecondary, fontSize: 11))),
                Expanded(
                    flex: 2,
                    child: Text('الإنجاز',
                        style: TextStyle(color: _textSecondary, fontSize: 11),
                        textAlign: TextAlign.center)),
                Expanded(
                    child: Text('المهام',
                        style: TextStyle(color: _textSecondary, fontSize: 11),
                        textAlign: TextAlign.center)),
                Expanded(
                    child: Text('مكتملة',
                        style: TextStyle(color: _textSecondary, fontSize: 11),
                        textAlign: TextAlign.center)),
                Expanded(
                    child: Text('بالوقت',
                        style: TextStyle(color: _green, fontSize: 11),
                        textAlign: TextAlign.center)),
                Expanded(
                    child: Text('متأخرة',
                        style: TextStyle(color: _orange, fontSize: 11),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('⏱ الوقت',
                        style: TextStyle(color: _textSecondary, fontSize: 11),
                        textAlign: TextAlign.center)),
                Expanded(
                    flex: 2,
                    child: Text('⭐ التقييم',
                        style: TextStyle(color: _textSecondary, fontSize: 11),
                        textAlign: TextAlign.center)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // List
          Expanded(
            child: sorted.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: sorted.length,
                    itemBuilder: (context, idx) {
                      final tech = sorted[idx];
                      final rate = tech.totalTasks > 0
                          ? tech.completed / tech.totalTasks
                          : 0.0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.02)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: _getTechColor(idx)
                                        .withValues(alpha: 0.2),
                                    child: Text(
                                        tech.name.isNotEmpty
                                            ? tech.name[0]
                                            : '?',
                                        style: TextStyle(
                                            color: _getTechColor(idx),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(tech.name,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: rate,
                                      minHeight: 6,
                                      backgroundColor:
                                          Colors.white.withValues(alpha: 0.1),
                                      valueColor:
                                          AlwaysStoppedAnimation(_green),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${(rate * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                          color: _green,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            Expanded(
                                child: Text('${tech.totalTasks}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                            Expanded(
                                child: Text('${tech.completed}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: _green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                            // بالوقت
                            Expanded(
                                child: Text('${tech.onTime}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: _green,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                            // متأخرة
                            Expanded(
                                child: Text('${tech.late_}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: tech.late_ > 0
                                            ? _orange
                                            : _textSecondary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))),
                            // تقييم الوقت
                            Expanded(
                              flex: 2,
                              child: tech.avgTimeRating > 0
                                  ? _buildStarsRow(tech.avgTimeRating, _cyan)
                                  : const Text('—',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: _textSecondary, fontSize: 12)),
                            ),
                            // تقييم المدقق
                            Expanded(
                              flex: 2,
                              child: tech.avgRating > 0
                                  ? _buildStarsRow(tech.avgRating, _amber)
                                  : const Text('—',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: _textSecondary, fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryStatsColumn() {
    return Column(
      children: [
        // أزرار التبديل
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _bgDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _glassBorder),
          ),
          child: Row(
            children: [
              _sideTabBtn(0, Icons.apartment_rounded, 'الأقسام'),
              const SizedBox(width: 4),
              _sideTabBtn(1, Icons.category_rounded, 'المهام'),
              const SizedBox(width: 4),
              _sideTabBtn(2, Icons.fact_check_rounded, 'التدقيق'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // المحتوى
        Expanded(
          child: _sideTab == 2
              ? _buildAuditGaugeSection()
              : _sideTab == 0
                  ? _buildDeptCardsView()
                  : _buildCompactListCard(
                      'أنواع المهام',
                      Icons.category_rounded,
                      _taskTypeDistribution,
                    ),
        ),
      ],
    );
  }

  Widget _sideTabBtn(int index, IconData icon, String label) {
    final active = _sideTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _sideTab = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? _blue.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:
                active ? Border.all(color: _blue.withValues(alpha: 0.4)) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? _blue : _textSecondary, size: 14),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    color: active ? _blue : _textSecondary,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  /// عرض الأقسام كبطاقات شبكية
  Widget _buildDeptCardsView() {
    const chartColors = [
      _blue,
      _green,
      _cyan,
      _amber,
      _orange,
      _purple,
      _teal,
      _red
    ];
    final data = _departmentDistribution;
    final total = data.values.fold(0, (a, b) => a + b);
    final entries = data.entries.toList();
    final maxVal =
        entries.isEmpty ? 1 : entries.map((e) => e.value).reduce(max);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.apartment_rounded, color: _grayIcon, size: 18),
              const SizedBox(width: 8),
              const Text('الأقسام',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$total إجمالي',
                    style: const TextStyle(
                        color: _blue,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Bar Chart
          Expanded(
            child: data.isEmpty
                ? _emptyState()
                : LayoutBuilder(builder: (context, constraints) {
                    const labelHeight = 40.0; // name + pct
                    const topNumHeight = 20.0; // count above bar
                    final maxBarH = constraints.maxHeight -
                        labelHeight -
                        topNumHeight -
                        8; // gaps
                    const minBarWidth = 48.0;
                    final fitsInline =
                        entries.length * minBarWidth <= constraints.maxWidth;

                    Widget buildBar(int i) {
                      final e = entries[i];
                      final color = chartColors[i % chartColors.length];
                      final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
                      final barH = max(6.0, ratio * max(maxBarH, 20.0));
                      final pct = total > 0
                          ? (e.value / total * 100).toStringAsFixed(0)
                          : '0';
                      return SizedBox(
                        width: fitsInline ? null : minBarWidth,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${e.value}',
                                style: TextStyle(
                                    color: color,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Container(
                              width: fitsInline ? double.infinity : 28,
                              height: barH,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    color,
                                    color.withValues(alpha: 0.5),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5)),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: labelHeight,
                              child: Column(
                                children: [
                                  Text(e.key,
                                      style: const TextStyle(
                                          color: _textSecondary, fontSize: 9),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  Text('$pct%',
                                      style: TextStyle(
                                          color: color.withValues(alpha: 0.7),
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (fitsInline) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(
                            entries.length,
                            (i) => Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 2),
                                    child: buildBar(i)))),
                      );
                    }
                    // Scrollable when too many departments
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children:
                            List.generate(entries.length, (i) => buildBar(i)),
                      ),
                    );
                  }),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactListCard(
      String title, IconData icon, Map<String, int> data) {
    const barColors = [
      _blue,
      _green,
      _cyan,
      _amber,
      _orange,
      _purple,
      _teal,
      _red
    ];
    final total = data.values.fold(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _grayIcon, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$total إجمالي',
                    style: const TextStyle(
                        color: _blue,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: data.isEmpty
                ? _emptyState()
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: data.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, idx) {
                      final entry = data.entries.toList()[idx];
                      final pct = total > 0 ? entry.value / total : 0.0;
                      final color = barColors[idx % barColors.length];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(entry.key,
                                    style: const TextStyle(
                                        color: _textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('${entry.value}',
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 36,
                                child: Text(
                                    '${(pct * 100).toStringAsFixed(0)}%',
                                    textAlign: TextAlign.left,
                                    style: TextStyle(
                                        color: color.withValues(alpha: 0.8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 6,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.05),
                              valueColor: AlwaysStoppedAnimation(
                                  color.withValues(alpha: 0.7)),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static const _grayIcon = Color(0xFF6C757D);

  Color _getTechColor(int idx) {
    const colors = [
      _blue,
      _green,
      _orange,
      _purple,
      _red,
      _cyan,
      _teal,
      Color(0xFF795548),
      Color(0xFF607D8B),
      Color(0xFFAD1457),
    ];
    return colors[idx % colors.length];
  }

  // ═══════════════════════════════════════════════════════════════
  //  Shared Widgets
  // ═══════════════════════════════════════════════════════════════

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _cyan, size: 16),
        const SizedBox(width: 6),
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _textPrimary)),
      ],
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4)
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 10, color: _textSecondary)),
      ],
    );
  }

  Widget _emptyState() {
    return const Center(
      child: Text('لا توجد بيانات',
          style: TextStyle(fontSize: 12, color: _textSecondary)),
    );
  }

  /// بناء صف نجمات (5 نجمات) حسب التقييم
  Widget _buildStarsRow(double rating, Color color) {
    final int fullStars = rating.floor();
    final bool hasHalf = (rating - fullStars) >= 0.3;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < fullStars) {
          return Icon(Icons.star_rounded, color: color, size: 14);
        } else if (i == fullStars && hasHalf) {
          return Icon(Icons.star_half_rounded, color: color, size: 14);
        } else {
          return Icon(Icons.star_outline_rounded,
              color: color.withValues(alpha: 0.3), size: 14);
        }
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  Data Models
// ═══════════════════════════════════════════════════════════════

class _TechnicianStats {
  final String name;
  int totalTasks = 0;
  int completed = 0;
  int cancelled = 0;
  int audited = 0;
  int issues = 0;
  int ratingSum = 0;
  int ratingCount = 0;
  int timeRatingSum = 0;
  int timeRatingCount = 0;
  int onTime = 0;
  int late_ = 0;

  _TechnicianStats(this.name);

  double get avgRating => ratingCount > 0 ? ratingSum / ratingCount : 0;
  double get avgTimeRating =>
      timeRatingCount > 0 ? timeRatingSum / timeRatingCount : 0;
}

class _MonthlyStats {
  final String key;
  int total = 0;
  int completed = 0;
  int cancelled = 0;

  _MonthlyStats(this.key);
}

// ═══ Donut Chart Painter ═══
class _DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double total;

  _DonutChartPainter({
    required this.values,
    required this.colors,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    const strokeWidth = 20.0;
    final rect =
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // Background ring
    final bgPaint = Paint()
      ..color = const Color(0x10FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius - strokeWidth / 2, bgPaint);

    if (total <= 0) return;

    double startAngle = -pi / 2; // Start from top
    for (int i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * pi;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.total != total;
  }
}
