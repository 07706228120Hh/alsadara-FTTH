import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../utils/smart_text_color.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../services/task_export_service.dart';
import 'task_status_colors.dart';
import 'widgets/task_common_widgets.dart';
import '../frontend/tokens/sd_colors.dart' show SdColors;
import '../frontend/components/sd_app_bar.dart';

class ReportsPage extends StatefulWidget {
  final List<Task> tasks;
  final List<Task> filteredTasks;
  final Function(BuildContext) showFilterPopup;
  final Function(List<Task>) calculateTotalAmount;
  final Function(Task) calculateTaskDuration;

  const ReportsPage({
    super.key,
    required this.tasks,
    required this.filteredTasks,
    required this.showFilterPopup,
    required this.calculateTotalAmount,
    required this.calculateTaskDuration,
  });

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  // Filter variables
  String? selectedDepartment;
  String? selectedTechnician;
  String? selectedFBG;
  List<Task> currentFilteredTasks = [];
  bool showFilterDetails = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Dashboard toggle
  bool _showDashboard = false;

  // بحث سيرفر
  Timer? _searchDebounce;
  bool _isSearching = false;
  List<Task>? _serverSearchResults;
  int _serverSearchTotal = 0;

  // فلتر التاريخ
  DateTimeRange? _dateRange;
  String _dateLabel = 'الكل';

  // كل المهام من السيرفر
  List<Task> _allTasks = [];
  bool _isLoadingAll = false;

  @override
  void initState() {
    super.initState();
    currentFilteredTasks = widget.tasks;
    // جلب كل المهام من السيرفر عند فتح الصفحة
    _fetchAllTasks();
  }

  /// جلب كل المهام من السيرفر (بدون حد 50)
  Future<void> _fetchAllTasks() async {
    setState(() => _isLoadingAll = true);
    try {
      // جلب عدة صفحات لتغطية كل المهام
      List<Task> allFetched = [];
      int page = 1;
      const batchSize = 500;
      bool hasMore = true;

      while (hasMore) {
        final response = await TaskApiService.instance.getRequests(
          page: page,
          pageSize: batchSize,
        );
        if (!mounted) return;
        final List<dynamic> items =
            response['data'] ?? response['Items'] ?? response['items'] ?? [];
        final batch = items
            .map((item) => Task.fromApiResponse(item as Map<String, dynamic>))
            .toList();
        allFetched.addAll(batch);
        debugPrint(
            '📊 التقارير: صفحة $page — جلب ${batch.length} مهمة (المجموع: ${allFetched.length})');
        hasMore = batch.length >= batchSize;
        page++;
      }

      if (!mounted) return;
      _allTasks = allFetched;
      setState(() {
        _isLoadingAll = false;
        currentFilteredTasks = _allTasks;
      });
    } catch (e) {
      debugPrint('❌ خطأ في جلب كل المهام: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingAll = false;
        _allTasks = widget.tasks;
        currentFilteredTasks = _allTasks;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(ReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks && _serverSearchResults == null) {
      _applyLocalFilters();
    }
  }

  // ══════════════════════════════════════
  //  بحث سيرفر مع debounce
  // ══════════════════════════════════════

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _searchDebounce?.cancel();

    if (value.trim().isEmpty) {
      // مسح البحث → رجوع للبيانات المحلية
      setState(() {
        _serverSearchResults = null;
        _isSearching = false;
      });
      _applyLocalFilters();
      return;
    }

    // debounce 400ms قبل إرسال طلب للسيرفر
    setState(() => _isSearching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _performServerSearch(value.trim());
    });
  }

  Future<void> _performServerSearch(String query) async {
    if (!mounted) return;

    try {
      final response = await TaskApiService.instance.getRequests(
        page: 1,
        pageSize: 1000,
        search: query,
        fromDate: _dateRange?.start,
        toDate: _dateRange?.end,
      );

      if (!mounted) return;

      final List<dynamic> items =
          response['data'] ?? response['Items'] ?? response['items'] ?? [];
      final total = response['total'] ?? items.length;
      final tasks = items
          .map((item) => Task.fromApiResponse(item as Map<String, dynamic>))
          .toList();

      setState(() {
        _serverSearchResults = tasks;
        _serverSearchTotal =
            total is int ? total : int.tryParse('$total') ?? tasks.length;
        _isSearching = false;
        // تطبيق الفلاتر المحلية على نتائج السيرفر
        _applyLocalFiltersOnList(tasks);
      });
    } catch (e) {
      debugPrint('خطأ في البحث: $e');
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  // ══════════════════════════════════════
  //  جلب بيانات بفلتر تاريخ من السيرفر
  // ══════════════════════════════════════

  Future<void> _fetchWithDateFilter() async {
    setState(() => _isSearching = true);

    try {
      final response = await TaskApiService.instance.getRequests(
        page: 1,
        pageSize: 1000,
        search: _searchQuery.trim().isNotEmpty ? _searchQuery.trim() : null,
        fromDate: _dateRange?.start,
        toDate: _dateRange?.end,
      );

      if (!mounted) return;

      final List<dynamic> items =
          response['data'] ?? response['Items'] ?? response['items'] ?? [];
      final total = response['total'] ?? items.length;
      final tasks = items
          .map((item) => Task.fromApiResponse(item as Map<String, dynamic>))
          .toList();

      setState(() {
        _serverSearchResults = tasks;
        _serverSearchTotal =
            total is int ? total : int.tryParse('$total') ?? tasks.length;
        _isSearching = false;
        _applyLocalFiltersOnList(tasks);
      });
    } catch (e) {
      debugPrint('خطأ في جلب البيانات بالتاريخ: $e');
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  // ══════════════════════════════════════
  //  فلاتر محلية (قسم، فني، FBG)
  // ══════════════════════════════════════

  void _applyLocalFilters() {
    final source = _serverSearchResults ??
        (_allTasks.isNotEmpty ? _allTasks : widget.tasks);
    _applyLocalFiltersOnList(source);
  }

  void _applyLocalFiltersOnList(List<Task> source) {
    setState(() {
      currentFilteredTasks = source.where((task) {
        if (selectedDepartment != null && task.department != selectedDepartment)
          return false;
        if (selectedTechnician != null && task.technician != selectedTechnician)
          return false;
        if (selectedFBG != null && task.fbg != selectedFBG) return false;
        return true;
      }).toList();
      showFilterDetails = false;
    });
  }

  void _clearAllFilters() {
    setState(() {
      selectedDepartment = null;
      selectedTechnician = null;
      selectedFBG = null;
      _dateRange = null;
      _dateLabel = 'الكل';
      _searchQuery = '';
      _searchController.clear();
      _serverSearchResults = null;
      _isSearching = false;
      currentFilteredTasks = _allTasks.isNotEmpty ? _allTasks : widget.tasks;
      showFilterDetails = false;
    });
  }

  // ══════════════════════════════════════
  //  اختيار التاريخ
  // ══════════════════════════════════════

  void _setQuickDate(String label, DateTimeRange? range) {
    setState(() {
      _dateLabel = label;
      _dateRange = range;
    });
    if (range != null) {
      _fetchWithDateFilter();
    } else {
      // "الكل" → رجوع للبيانات المحلية
      if (_searchQuery.trim().isEmpty) {
        setState(() {
          _serverSearchResults = null;
        });
        _applyLocalFilters();
      } else {
        _fetchWithDateFilter();
      }
    }
  }

  Future<void> _showCustomDatePicker() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _dateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
      locale: const Locale('ar'),
      helpText: 'اختر نطاق التاريخ',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
      saveText: 'تطبيق',
    );

    if (picked != null && mounted) {
      final fmt = DateFormat('MM/dd');
      _setQuickDate(
        '${fmt.format(picked.start)} - ${fmt.format(picked.end)}',
        picked,
      );
    }
  }

  // ══════════════════════════════════════
  //  حوار التصفية
  // ══════════════════════════════════════

  void _showCustomFilterPopup() {
    final source = _serverSearchResults ??
        (_allTasks.isNotEmpty ? _allTasks : widget.tasks);
    Set<String> departments = source
        .map((task) => task.department)
        .where((dept) => dept.isNotEmpty)
        .toSet();
    Set<String> technicians = source
        .map((task) => task.technician)
        .where((tech) => tech.isNotEmpty)
        .toSet();
    Set<String> fbgs =
        source.map((task) => task.fbg).where((fbg) => fbg.isNotEmpty).toSet();

    setState(() => showFilterDetails = true);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'تصفية التقارير',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Department Filter
                const Text('القسم:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedDepartment,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text('اختر القسم'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('جميع الأقسام'),
                    ),
                    ...departments.map((dept) => DropdownMenuItem<String>(
                          value: dept,
                          child: Text(dept),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedDepartment = value);
                  },
                ),
                const SizedBox(height: 16),

                // Technician Filter
                const Text('الفني:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedTechnician,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text('اختر الفني'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('جميع الفنيين'),
                    ),
                    ...technicians.map((tech) => DropdownMenuItem<String>(
                          value: tech,
                          child: Text(tech),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedTechnician = value);
                  },
                ),
                const SizedBox(height: 16),

                // FBG Filter
                const Text('FBG:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedFBG,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text('اختر FBG'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('جميع FBG'),
                    ),
                    ...fbgs.map((fbg) => DropdownMenuItem<String>(
                          value: fbg,
                          child: Text(fbg),
                        )),
                  ],
                  onChanged: (value) {
                    setDialogState(() => selectedFBG = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  selectedDepartment = null;
                  selectedTechnician = null;
                  selectedFBG = null;
                  showFilterDetails = false;
                });
                _applyLocalFilters();
                Navigator.pop(context);
              },
              child: const Text('مسح الكل'),
            ),
            TextButton(
              onPressed: () {
                setState(() => showFilterDetails = false);
                Navigator.pop(context);
              },
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                _applyLocalFilters();
                Navigator.pop(context);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  بناء الواجهة
  // ══════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final gradientColors = [Colors.blueAccent, SdColors.info];
    final smartTextColor =
        SmartTextColor.getAppBarTextColorWithGradient(context, gradientColors);
    final smartIconColor = smartTextColor;

    final bool hasActiveFilters = selectedDepartment != null ||
        selectedTechnician != null ||
        selectedFBG != null ||
        _dateRange != null;

    return Scaffold(
      appBar: SdAppBar(title: _showDashboard ? 'لوحة التحكم' : 'التقارير', actions: [
          // Toggle Dashboard / Reports
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewToggleButton(
                  icon: Icons.list_alt,
                  label: 'التقارير',
                  isSelected: !_showDashboard,
                  color: smartTextColor,
                  onTap: () => setState(() => _showDashboard = false),
                ),
                _buildViewToggleButton(
                  icon: Icons.dashboard,
                  label: 'لوحة التحكم',
                  isSelected: _showDashboard,
                  color: smartTextColor,
                  onTap: () => setState(() => _showDashboard = true),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // أزرار التصدير
          PopupMenuButton<String>(
            icon: Icon(Icons.file_download_outlined, color: smartIconColor),
            tooltip: 'تصدير',
            onSelected: (value) async {
              try {
                if (value == 'excel') {
                  await TaskExportService.exportToExcel(
                      tasks: currentFilteredTasks);
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('تم تصدير Excel'),
                        backgroundColor: SdColors.success));
                } else {
                  await TaskExportService.exportToPdf(
                      tasks: currentFilteredTasks);
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('تم تصدير PDF'),
                        backgroundColor: SdColors.success));
                }
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('خطأ في التصدير'),
                      backgroundColor: SdColors.danger));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'excel',
                  child: Row(children: [
                    Icon(Icons.table_chart, color: SdColors.success, size: 20),
                    SizedBox(width: 8),
                    Text('تصدير Excel'),
                  ])),
              PopupMenuItem(
                  value: 'pdf',
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf, color: SdColors.danger, size: 20),
                    SizedBox(width: 8),
                    Text('تصدير PDF'),
                  ])),
            ],
          ),
          IconButton(
            icon: Icon(Icons.filter_list, color: smartIconColor),
            onPressed: _showCustomFilterPopup,
            tooltip: 'تصفية',
          ),
          if (hasActiveFilters)
            IconButton(
              icon: Icon(Icons.clear_all, color: smartIconColor),
              onPressed: _clearAllFilters,
              tooltip: 'مسح الفلاتر',
            ),
        ]),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SdColors.infoTint, Colors.white],
          ),
        ),
        child: Column(
          children: [
            // ── أزرار فلتر التاريخ السريعة ──
            _buildDateFilterChips(),

            // ── الفلاتر المطبقة ──
            if (showFilterDetails && hasActiveFilters) _buildActiveFilters(),

            // ── بطاقات الإحصائيات ──
            _buildStatsCards(),

            // ── المحتوى: لوحة التحكم أو القائمة ──
            if (_showDashboard)
              Expanded(
                child: (_isSearching || _isLoadingAll)
                    ? const Center(
                        child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('جاري تحميل البيانات...',
                              style: TextStyle(color: SdColors.faint)),
                        ],
                      ))
                    : currentFilteredTasks.isEmpty
                        ? _buildEmptyState()
                        : _buildDashboard(),
              )
            else ...[
              // ── مربع البحث (سيرفر) ──
              _buildSearchBox(),
              const SizedBox(height: 8),

              // ── عدد النتائج ──
              if (_serverSearchResults != null || _dateRange != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: SdColors.faint),
                      const SizedBox(width: 4),
                      Text(
                        'نتائج السيرفر: $_serverSearchTotal مهمة (معروض: ${currentFilteredTasks.length})',
                        style: TextStyle(fontSize: 12, color: SdColors.faint),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),

              // ── قائمة المهام ──
              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : currentFilteredTasks.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            itemCount: currentFilteredTasks.length,
                            itemBuilder: (context, index) {
                              return _buildTaskCard(
                                  currentFilteredTasks[index]);
                            },
                          ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  أزرار التاريخ السريعة
  // ══════════════════════════════════════

  Widget _buildDateFilterChips() {
    final now = DateTime.now();
    final today = DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: now,
    );
    final yesterday = DateTimeRange(
      start: DateTime(now.year, now.month, now.day - 1),
      end: DateTime(now.year, now.month, now.day - 1, 23, 59, 59),
    );
    final last7 = DateTimeRange(
      start: now.subtract(const Duration(days: 7)),
      end: now,
    );
    final thisMonth = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: [
            _dateChip('الكل', null),
            const SizedBox(width: 6),
            _dateChip('اليوم', today),
            const SizedBox(width: 6),
            _dateChip('أمس', yesterday),
            const SizedBox(width: 6),
            _dateChip('هذا الشهر', thisMonth),
            const SizedBox(width: 6),
            ActionChip(
              avatar: Icon(
                Icons.date_range,
                size: 16,
                color: _dateLabel != 'الكل' &&
                        _dateLabel != 'اليوم' &&
                        _dateLabel != 'أمس' &&
                        _dateLabel != 'هذا الشهر'
                    ? Colors.white
                    : SdColors.info,
              ),
              label: Text(
                _dateLabel != 'الكل' &&
                        _dateLabel != 'اليوم' &&
                        _dateLabel != 'أمس' &&
                        _dateLabel != 'هذا الشهر'
                    ? _dateLabel
                    : 'مخصص',
                style: TextStyle(
                  fontSize: 12,
                  color: _dateLabel != 'الكل' &&
                          _dateLabel != 'اليوم' &&
                          _dateLabel != 'أمس' &&
                          _dateLabel != 'هذا الشهر'
                      ? Colors.white
                      : null,
                ),
              ),
              backgroundColor: _dateLabel != 'الكل' &&
                      _dateLabel != 'اليوم' &&
                      _dateLabel != 'أمس' &&
                      _dateLabel != 'هذا الشهر'
                  ? SdColors.info
                  : null,
              onPressed: _showCustomDatePicker,
            ),
          ],
        ),
      ),
    );
  }

  Widget _dateChip(String label, DateTimeRange? range) {
    final isSelected = _dateLabel == label;
    return ChoiceChip(
      label: Text(label,
          style:
              TextStyle(fontSize: 12, color: isSelected ? Colors.white : null)),
      selected: isSelected,
      selectedColor: SdColors.info,
      onSelected: (_) => _setQuickDate(label, range),
    );
  }

  // ══════════════════════════════════════
  //  الفلاتر المطبقة
  // ══════════════════════════════════════

  Widget _buildActiveFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: SdColors.infoTint,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: SdColors.infoTintEdge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('الفلاتر المطبقة:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => showFilterDetails = false),
                tooltip: 'إخفاء',
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              if (selectedDepartment != null)
                Chip(
                  label: Text('القسم: $selectedDepartment'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() => selectedDepartment = null);
                    _applyLocalFilters();
                  },
                ),
              if (selectedTechnician != null)
                Chip(
                  label: Text('الفني: $selectedTechnician'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() => selectedTechnician = null);
                    _applyLocalFilters();
                  },
                ),
              if (selectedFBG != null)
                Chip(
                  label: Text('FBG: $selectedFBG'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () {
                    setState(() => selectedFBG = null);
                    _applyLocalFilters();
                  },
                ),
              if (_dateRange != null)
                Chip(
                  label: Text('التاريخ: $_dateLabel'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _setQuickDate('الكل', null),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  بطاقات الإحصائيات
  // ══════════════════════════════════════

  Widget _buildStatsCards() {
    return Container(
      margin: const EdgeInsets.all(16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isSmallScreen = constraints.maxWidth < 700;

          return Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15.0),
              boxShadow: [
                BoxShadow(
                  color: SdColors.faint.withValues(alpha: 0.3),
                  spreadRadius: 2,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: isSmallScreen
                ? Column(
                    children: [
                      Row(children: [
                        Expanded(
                            child: AppStatCard(
                                title: 'المجموع الكلي',
                                value: currentFilteredTasks.length.toString(),
                                icon: Icons.assignment,
                                color: SdColors.info,
                                isSmallScreen: true)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: AppStatCard(
                                title: 'المكتملة',
                                value: currentFilteredTasks
                                    .where((t) => t.status == 'مكتملة')
                                    .length
                                    .toString(),
                                icon: Icons.check_circle,
                                color: SdColors.success,
                                isSmallScreen: true)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                            child: AppStatCard(
                                title: 'الملغية',
                                value: currentFilteredTasks
                                    .where((t) => t.status == 'ملغية')
                                    .length
                                    .toString(),
                                icon: Icons.cancel,
                                color: SdColors.danger,
                                isSmallScreen: true)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: AppStatCard(
                                title: 'المبلغ الإجمالي',
                                value:
                                    '${formatTaskAmount(widget.calculateTotalAmount(currentFilteredTasks) as num)} د.ع',
                                icon: Icons.account_balance_wallet,
                                color: SdColors.warning,
                                isSmallScreen: true)),
                      ]),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                          child: AppStatCard(
                              title: 'المجموع الكلي',
                              value: currentFilteredTasks.length.toString(),
                              icon: Icons.assignment,
                              color: SdColors.info,
                              isSmallScreen: false)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: AppStatCard(
                              title: 'المكتملة',
                              value: currentFilteredTasks
                                  .where((t) => t.status == 'مكتملة')
                                  .length
                                  .toString(),
                              icon: Icons.check_circle,
                              color: SdColors.success,
                              isSmallScreen: false)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: AppStatCard(
                              title: 'الملغية',
                              value: currentFilteredTasks
                                  .where((t) => t.status == 'ملغية')
                                  .length
                                  .toString(),
                              icon: Icons.cancel,
                              color: SdColors.danger,
                              isSmallScreen: false)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: AppStatCard(
                              title: 'المبلغ الإجمالي',
                              value:
                                  '${formatTaskAmount(widget.calculateTotalAmount(currentFilteredTasks) as num)} د.ع',
                              icon: Icons.account_balance_wallet,
                              color: SdColors.warning,
                              isSmallScreen: false)),
                    ],
                  ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════
  //  مربع البحث
  // ══════════════════════════════════════

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: TextField(
        controller: _searchController,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText:
              'بحث في كل المهام (اسم العميل، الهاتف، الفني، رقم المهمة...)',
          hintStyle: TextStyle(fontSize: 13, color: SdColors.faint),
          prefixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: SdColors.edge),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: SdColors.edge),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: SdColors.info, width: 1.5),
          ),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  // ══════════════════════════════════════
  //  حالة فارغة
  // ══════════════════════════════════════

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 80, color: SdColors.faint),
          const SizedBox(height: 16),
          Text(
            'لا توجد مهام تطابق الفلاتر المحددة',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: SdColors.muted),
          ),
          const SizedBox(height: 8),
          Text(
            'قم بتعديل الفلاتر أو مسحها لرؤية المزيد من المهام',
            style: TextStyle(fontSize: 16, color: SdColors.faint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  بطاقة إحصائيات
  // ══════════════════════════════════════

  // ══════════════════════════════════════
  //  بطاقة المهمة — مختصرة + توسيع عند الضغط
  // ══════════════════════════════════════

  final Set<int> _expandedCards = {};

  Widget _buildTaskCard(Task task) {
    final Color statusColor = _getStatusColor(task.status);
    final fmt = DateFormat('yyyy/MM/dd - HH:mm');
    final int cardIndex = currentFilteredTasks.indexOf(task);
    final bool isExpanded = _expandedCards.contains(cardIndex);

    // تحديد إن كان هناك تفاصيل مخفية لعرضها
    final bool hasHiddenDetails = task.username.isNotEmpty ||
        task.leader.isNotEmpty ||
        task.location.isNotEmpty ||
        task.priority.isNotEmpty ||
        task.notes.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.0),
        onTap: hasHiddenDetails
            ? () => setState(() {
                  if (isExpanded) {
                    _expandedCards.remove(cardIndex);
                  } else {
                    _expandedCards.add(cardIndex);
                  }
                })
            : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.0),
            border: Border(right: BorderSide(color: statusColor, width: 4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── الصف العلوي: العنوان + الحالة ──
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueAccent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(task.status,
                          style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── البيانات الظاهرة دائماً ──
                _buildCompactRow(Icons.business, 'القسم', task.department,
                    Icons.person, 'الفني', task.technician),
                const SizedBox(height: 6),
                _buildCompactRow(Icons.router, 'FBG', task.fbg, Icons.phone,
                    'الهاتف', task.phone),
                const SizedBox(height: 6),
                _buildCompactRow(
                    Icons.attach_money,
                    'المبلغ',
                    '${task.amountFormatted} د.ع',
                    Icons.calendar_today,
                    'الإنشاء',
                    fmt.format(task.createdAt)),
                const SizedBox(height: 6),
                _buildDetailRow(Icons.access_time, 'وقت التنفيذ',
                    widget.calculateTaskDuration(task)),

                // ── سهم التوسيع ──
                if (hasHiddenDetails)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: SdColors.faint,
                        ),
                        Text(
                          isExpanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
                          style:
                              TextStyle(fontSize: 11, color: SdColors.faint),
                        ),
                      ],
                    ),
                  ),

                // ── التفاصيل المخفية (تظهر عند الضغط) ──
                if (isExpanded) ...[
                  const Divider(height: 16),

                  // اسم العميل مميز
                  if (task.username.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: SdColors.infoTint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SdColors.infoTintEdge),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_pin,
                              size: 18, color: SdColors.info),
                          const SizedBox(width: 8),
                          Text('العميل: ',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: SdColors.info,
                                  fontSize: 14)),
                          Expanded(
                            child: Text(task.username,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: SdColors.infoEdge,
                                    fontSize: 14)),
                          ),
                        ],
                      ),
                    ),

                  if (task.leader.isNotEmpty)
                    _buildDetailRow(
                        Icons.supervisor_account, 'الليدر', task.leader),
                  if (task.location.isNotEmpty)
                    _buildDetailRow(Icons.location_on, 'الموقع', task.location),
                  if (task.priority.isNotEmpty)
                    _buildDetailRow(Icons.flag, 'الأولوية', task.priority),
                  if (task.notes.isNotEmpty)
                    _buildDetailRow(Icons.note, 'ملاحظات', task.notes),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// صف مضغوط: حقلين بجانب بعض
  Widget _buildCompactRow(
    IconData icon1,
    String label1,
    String value1,
    IconData icon2,
    String label2,
    String value2,
  ) {
    return Row(
      children: [
        Expanded(child: _buildDetailRowInline(icon1, label1, value1)),
        const SizedBox(width: 8),
        Expanded(child: _buildDetailRowInline(icon2, label2, value2)),
      ],
    );
  }

  Widget _buildDetailRowInline(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 14, color: SdColors.faint),
        const SizedBox(width: 4),
        Text('$label: ',
            style: TextStyle(
                fontWeight: FontWeight.w500,
                color: SdColors.muted,
                fontSize: 12)),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: SdColors.muted),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
                fontWeight: FontWeight.w500,
                color: SdColors.muted,
                fontSize: 14),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // مصدر موحّد لألوان الحالات (يشمل «مفتوحة» التي كانت ناقصة سابقاً).
  Color _getStatusColor(String status) => TaskStatusColors.colorFor(status);

  // ══════════════════════════════════════
  //  زر التبديل بين العروض
  // ══════════════════════════════════════

  Widget _buildViewToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  لوحة التحكم الرئيسية
  // ══════════════════════════════════════

  Widget _buildDashboard() {
    final isWide = MediaQuery.of(context).size.width >= 700;

    final children = <Widget>[
      if (isWide) ...[
        // الصف الأول: PieChart + SLA + متوسط الإنجاز
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildStatusPieChart()),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  _buildSlaComplianceCard(),
                  const SizedBox(height: 12),
                  _buildAvgCompletionTimeCard(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildDelayedTasksCard(),
        const SizedBox(height: 12),
        // الصف الثاني: المهام حسب القسم + أفضل الفنيين
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildDepartmentBarChart()),
            const SizedBox(width: 12),
            Expanded(child: _buildTopTechniciansChart()),
          ],
        ),
        const SizedBox(height: 12),
        _buildDailyTasksLineChart(),
      ] else ...[
        _buildStatusPieChart(),
        const SizedBox(height: 12),
        _buildSlaComplianceCard(),
        const SizedBox(height: 12),
        _buildAvgCompletionTimeCard(),
        const SizedBox(height: 12),
        _buildDelayedTasksCard(),
        const SizedBox(height: 12),
        _buildDepartmentBarChart(),
        const SizedBox(height: 12),
        _buildTopTechniciansChart(),
        const SizedBox(height: 12),
        _buildDailyTasksLineChart(),
      ],
      const SizedBox(height: 16),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: children,
    );
  }

  // ══════════════════════════════════════
  //  بطاقة رسم بياني مع عنوان
  // ══════════════════════════════════════

  Widget _buildChartCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    double? height = 320,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Divider(color: SdColors.divider),
            const SizedBox(height: 8),
            if (height != null)
              SizedBox(height: height, child: child)
            else
              child,
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  A. المهام حسب الحالة — PieChart
  // ══════════════════════════════════════

  Widget _buildStatusPieChart() {
    final statusCounts = <String, int>{};
    for (final task in currentFilteredTasks) {
      final s = task.status.isNotEmpty ? task.status : 'غير محدد';
      statusCounts[s] = (statusCounts[s] ?? 0) + 1;
    }

    if (statusCounts.isEmpty) {
      return _buildChartCard(
        title: 'المهام حسب الحالة',
        icon: Icons.pie_chart,
        iconColor: Colors.blueAccent,
        height: 300,
        child: const Center(child: Text('لا توجد بيانات')),
      );
    }

    // ألوان الحالات من المصدر الموحّد (يشمل كل الحالات والمرادفات).
    final total = currentFilteredTasks.length;
    final entries = statusCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return _buildChartCard(
      title: 'المهام حسب الحالة',
      icon: Icons.pie_chart,
      iconColor: Colors.blueAccent,
      height: 300,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 36,
                sections: entries.map((e) {
                  final pct = (e.value / total * 100).toStringAsFixed(1);
                  final color = TaskStatusColors.colorFor(e.key);
                  return PieChartSectionData(
                    value: e.value.toDouble(),
                    color: color,
                    title: '$pct%',
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    radius: 52,
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: entries.map((e) {
                  final color = TaskStatusColors.colorFor(e.key);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${e.key} (${e.value})',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  B. المهام حسب القسم — BarChart أفقي
  // ══════════════════════════════════════

  Widget _buildDepartmentBarChart() {
    final deptCounts = <String, int>{};
    for (final task in currentFilteredTasks) {
      final d = task.department.isNotEmpty ? task.department : 'غير محدد';
      deptCounts[d] = (deptCounts[d] ?? 0) + 1;
    }

    if (deptCounts.isEmpty) {
      return _buildChartCard(
        title: 'المهام حسب القسم',
        icon: Icons.business,
        iconColor: SdColors.primary,
        height: 300,
        child: const Center(child: Text('لا توجد بيانات')),
      );
    }

    final entries = deptCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.first.value.toDouble();
    final barColors = [
      SdColors.primary,
      SdColors.info,
      SdColors.accent,
      SdColors.accent,
      SdColors.info,
      SdColors.faint,
      SdColors.platformBase,
    ];

    final chartHeight = math.max(entries.length * 44.0, 200.0);

    return _buildChartCard(
      title: 'المهام حسب القسم',
      icon: Icons.business,
      iconColor: SdColors.primary,
      height: chartHeight + 80,
      child: RotatedBox(
        quarterTurns: 0,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxVal * 1.15,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final name = entries[group.x.toInt()].key;
                  return BarTooltipItem(
                    '$name\n${rod.toY.toInt()} مهمة',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 42,
                  getTitlesWidget: (value, meta) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= entries.length)
                      return const SizedBox();
                    final name = entries[idx].key;
                    return SideTitleWidget(
                      meta: meta,
                      child: SizedBox(
                        width: 60,
                        child: Text(
                          name.length > 10
                              ? '${name.substring(0, 10)}..'
                              : name,
                          style: const TextStyle(fontSize: 9),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (value, meta) {
                    if (value == 0 ||
                        value % math.max(1, (maxVal / 5).ceil()) != 0) {
                      if (value != maxVal.roundToDouble() && value != 0) {
                        return const SizedBox();
                      }
                    }
                    return Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10, color: SdColors.faint),
                    );
                  },
                ),
              ),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: math.max(1, (maxVal / 5).ceilToDouble()),
              getDrawingHorizontalLine: (value) => FlLine(
                color: SdColors.divider,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(entries.length, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: entries[i].value.toDouble(),
                    color: barColors[i % barColors.length],
                    width: math.min(28, 200.0 / entries.length),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  C. المهام اليومية — LineChart (آخر 14 يوم)
  // ══════════════════════════════════════

  Widget _buildDailyTasksLineChart() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days =
        List.generate(14, (i) => today.subtract(Duration(days: 13 - i)));

    final dayCounts = <DateTime, int>{};
    for (final d in days) {
      dayCounts[d] = 0;
    }
    for (final task in currentFilteredTasks) {
      final taskDay = DateTime(
          task.createdAt.year, task.createdAt.month, task.createdAt.day);
      if (dayCounts.containsKey(taskDay)) {
        dayCounts[taskDay] = dayCounts[taskDay]! + 1;
      }
    }

    final spots = <FlSpot>[];
    final daysList = days.toList();
    double maxY = 0;
    for (int i = 0; i < daysList.length; i++) {
      final count = dayCounts[daysList[i]]?.toDouble() ?? 0;
      spots.add(FlSpot(i.toDouble(), count));
      if (count > maxY) maxY = count;
    }
    if (maxY == 0) maxY = 5;

    final fmt = DateFormat('MM/dd');

    return _buildChartCard(
      title: 'المهام اليومية (آخر 14 يوم)',
      icon: Icons.show_chart,
      iconColor: SdColors.accent,
      height: 280,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.2,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final day = daysList[spot.x.toInt()];
                  return LineTooltipItem(
                    '${fmt.format(day)}\n${spot.y.toInt()} مهمة',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: math.max(1, (maxY / 5).ceilToDouble()),
            getDrawingHorizontalLine: (value) => FlLine(
              color: SdColors.divider,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= daysList.length)
                    return const SizedBox();
                  // Show every other label to avoid crowding
                  if (idx % 2 != 0 && daysList.length > 7)
                    return const SizedBox();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      fmt.format(daysList[idx]),
                      style: const TextStyle(fontSize: 9, color: SdColors.faint),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: math.max(1, (maxY / 5).ceilToDouble()),
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: SdColors.faint),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: SdColors.edge),
              left: BorderSide(color: SdColors.edge),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: SdColors.accent,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: SdColors.accent,
                  strokeWidth: 1.5,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: SdColors.accent.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  D. أفضل الفنيين — BarChart أفقي
  // ══════════════════════════════════════

  Widget _buildTopTechniciansChart() {
    final techCounts = <String, int>{};
    for (final task in currentFilteredTasks) {
      if (task.technician.isNotEmpty && task.status == 'مكتملة') {
        techCounts[task.technician] = (techCounts[task.technician] ?? 0) + 1;
      }
    }

    if (techCounts.isEmpty) {
      return _buildChartCard(
        title: 'أفضل 5 فنيين (مهام مكتملة)',
        icon: Icons.engineering,
        iconColor: SdColors.platformBase,
        height: 300,
        child: const Center(child: Text('لا توجد بيانات')),
      );
    }

    final entries = techCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = entries.take(5).toList();
    final maxVal = top5.first.value.toDouble();

    final techColors = [
      SdColors.platformBase,
      SdColors.platformTintEdge,
      SdColors.platformBase,
      SdColors.platformTintEdge,
      Colors.purpleAccent,
    ];

    return _buildChartCard(
      title: 'أفضل 5 فنيين (مهام مكتملة)',
      icon: Icons.engineering,
      iconColor: SdColors.platformBase,
      height: 300,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxVal * 1.2,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final name = top5[group.x.toInt()].key;
                return BarTooltipItem(
                  '$name\n${rod.toY.toInt()} مهمة مكتملة',
                  const TextStyle(color: Colors.white, fontSize: 12),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 42,
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= top5.length) return const SizedBox();
                  final name = top5[idx].key;
                  return SideTitleWidget(
                    meta: meta,
                    child: SizedBox(
                      width: 60,
                      child: Text(
                        name.length > 10 ? '${name.substring(0, 10)}..' : name,
                        style: const TextStyle(fontSize: 9),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: math.max(1, (maxVal / 5).ceilToDouble()),
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: SdColors.faint),
                  );
                },
              ),
            ),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: math.max(1, (maxVal / 5).ceilToDouble()),
            getDrawingHorizontalLine: (value) => FlLine(
              color: SdColors.divider,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: List.generate(top5.length, (i) {
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: top5[i].value.toDouble(),
                  color: techColors[i % techColors.length],
                  width: 24,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  // ══════════════════════════════════════
  //  E. نسبة الالتزام بـ SLA
  // ══════════════════════════════════════

  Widget _buildSlaComplianceCard() {
    final tasksWithSla = currentFilteredTasks.where((t) => t.hasSla).toList();

    if (tasksWithSla.isEmpty) {
      return _buildStatInfoCard(
        title: 'الالتزام بـ SLA',
        icon: Icons.timer,
        iconColor: SdColors.info,
        value: 'لا يوجد',
        subtitle: 'لا توجد مهام بموعد نهائي',
        valueColor: SdColors.faint,
      );
    }

    // مكتملة أو ملغية بنجاح: slaStatus == 'done' وأُغلقت قبل الموعد
    int compliant = 0;
    for (final task in tasksWithSla) {
      if ((task.isCompleted || task.isCancelled) &&
          task.closedAt != null &&
          task.slaDeadline != null) {
        if (task.closedAt!.isBefore(task.slaDeadline!) ||
            task.closedAt!.isAtSameMomentAs(task.slaDeadline!)) {
          compliant++;
        }
      }
    }

    final rate = (compliant / tasksWithSla.length * 100);
    final Color rateColor;
    if (rate >= 80) {
      rateColor = SdColors.success;
    } else if (rate >= 50) {
      rateColor = SdColors.warning;
    } else {
      rateColor = SdColors.danger;
    }

    return _buildStatInfoCard(
      title: 'الالتزام بـ SLA',
      icon: Icons.timer,
      iconColor: SdColors.info,
      value: '${rate.toStringAsFixed(1)}%',
      subtitle: '$compliant من ${tasksWithSla.length} مهمة ضمن الموعد',
      valueColor: rateColor,
    );
  }

  // ══════════════════════════════════════
  //  F. متوسط وقت الإنجاز
  // ══════════════════════════════════════

  Widget _buildAvgCompletionTimeCard() {
    final completed = currentFilteredTasks
        .where((t) => t.isCompleted && t.closedAt != null)
        .toList();

    if (completed.isEmpty) {
      return _buildStatInfoCard(
        title: 'وقت الإنجاز (الوسيط)',
        icon: Icons.speed,
        iconColor: SdColors.warning,
        value: 'لا يوجد',
        subtitle: 'لا توجد مهام مكتملة',
        valueColor: SdColors.faint,
      );
    }

    // حساب المدة لكل مهمة
    final durations = completed
        .map((t) => t.closedAt!.difference(t.createdAt).inMinutes)
        .where((m) => m > 0) // تجاهل القيم السالبة أو الصفرية
        .toList()
      ..sort();

    if (durations.isEmpty) {
      return _buildStatInfoCard(
        title: 'وقت الإنجاز (الوسيط)',
        icon: Icons.speed,
        iconColor: SdColors.warning,
        value: 'لا يوجد',
        subtitle: 'لا توجد بيانات صالحة',
        valueColor: SdColors.faint,
      );
    }

    // الوسيط (median) — لا يتأثر بالقيم المتطرفة
    final median = durations[durations.length ~/ 2].toDouble();

    // المهام الواقعية فقط (< 72 ساعة) للمتوسط
    final realistic = durations.where((m) => m <= 4320).toList(); // 72 ساعة
    final outliers = durations.length - realistic.length;
    final realisticAvg = realistic.isNotEmpty
        ? realistic.reduce((a, b) => a + b) / realistic.length
        : median;

    String formatted;
    Color valueColor;
    // نعرض الوسيط كقيمة رئيسية
    if (median < 60) {
      formatted = '${median.toStringAsFixed(0)} دقيقة';
      valueColor = SdColors.success;
    } else if (median < 1440) {
      final hours = (median / 60).toStringAsFixed(1);
      formatted = '$hours ساعة';
      valueColor = median < 480 ? SdColors.success : SdColors.warning;
    } else {
      final days = (median / 1440).toStringAsFixed(1);
      formatted = '$days يوم';
      valueColor = SdColors.danger;
    }

    // نص المتوسط الواقعي
    String avgText;
    if (realisticAvg < 60) {
      avgText = '${realisticAvg.toStringAsFixed(0)} دقيقة';
    } else if (realisticAvg < 1440) {
      avgText = '${(realisticAvg / 60).toStringAsFixed(1)} ساعة';
    } else {
      avgText = '${(realisticAvg / 1440).toStringAsFixed(1)} يوم';
    }

    final subtitle = 'من ${completed.length} مهمة'
        '${outliers > 0 ? ' ($outliers متطرفة مستبعدة)' : ''}'
        '\nالمتوسط الواقعي: $avgText';

    return _buildStatInfoCard(
      title: 'وقت الإنجاز (الوسيط)',
      icon: Icons.speed,
      iconColor: SdColors.warning,
      value: formatted,
      subtitle: subtitle,
      valueColor: valueColor,
    );
  }

  // ══════════════════════════════════════
  //  G. المهام المتأخرة وأسباب التأخير
  // ══════════════════════════════════════

  /// تنسيق مدة (دقائق) كنص مقروء
  String _formatDuration(int totalMinutes) {
    if (totalMinutes < 60) return '$totalMinutes د';
    if (totalMinutes < 1440) {
      final h = totalMinutes ~/ 60;
      final m = totalMinutes % 60;
      return m > 0 ? '$hس $mد' : '$hس';
    }
    final d = totalMinutes ~/ 1440;
    final h = (totalMinutes % 1440) ~/ 60;
    return h > 0 ? '$dي $hس' : '$dي';
  }

  Widget _buildDelayedTasksCard() {
    final now = DateTime.now();

    // === 1. المهام المفتوحة/قيد التنفيذ المتأخرة حالياً (> 24 ساعة) ===
    final openDelayed = currentFilteredTasks
        .where((t) => !t.isCompleted && !t.isCancelled)
        .map((t) {
          final minutes = now.difference(t.createdAt).inMinutes;
          return (task: t, minutes: minutes);
        })
        .where((e) => e.minutes > 1440) // أكثر من 24 ساعة
        .toList()
      ..sort((a, b) => b.minutes.compareTo(a.minutes));

    // === 2. المهام المكتملة — تحليل سرعة الإنجاز ===
    final allCompletedRaw = currentFilteredTasks
        .where((t) => t.isCompleted && t.closedAt != null)
        .map((t) {
          final minutes = t.closedAt!.difference(t.createdAt).inMinutes;
          return (task: t, minutes: minutes);
        })
        .where((e) => e.minutes > 0)
        .toList()
      ..sort((a, b) => a.minutes.compareTo(b.minutes)); // ترتيب تصاعدي للحسابات

    // حساب الوسيط لتحديد الحدود ديناميكياً
    final int medianMin = allCompletedRaw.isNotEmpty
        ? allCompletedRaw[allCompletedRaw.length ~/ 2].minutes
        : 60;
    // P90 — النسبة المئوية 90
    final int p90 = allCompletedRaw.isNotEmpty
        ? allCompletedRaw[(allCompletedRaw.length * 0.9).floor()].minutes
        : 480;

    // الحدود الديناميكية بناءً على البيانات الفعلية
    final int slowThreshold = p90; // بطيئة: فوق P90
    final int delayedThreshold = p90 * 3; // متأخرة: 3 أضعاف P90

    // استبعاد المنسية (> 7 أيام)
    final allCompleted = allCompletedRaw
        .where((e) => e.minutes <= 10080)
        .toList()
      ..sort((a, b) => b.minutes.compareTo(a.minutes)); // ترتيب تنازلي للعرض

    // تصنيف ديناميكي
    final completedDelayed =
        allCompleted.where((e) => e.minutes > delayedThreshold).toList();
    final completedSlow = allCompleted
        .where(
            (e) => e.minutes > slowThreshold && e.minutes <= delayedThreshold)
        .toList();
    final completedFast =
        allCompleted.where((e) => e.minutes <= slowThreshold).toList();

    // مهام مستبعدة (> 7 أيام)
    final excludedCount =
        allCompletedRaw.where((e) => e.minutes > 10080).length;

    // تحليل حسب القسم/الفني/النوع — كل المكتملة الواقعية (لعرض المتوسط الحقيقي)
    final perfByDept = <String, List<int>>{};
    final perfByTech = <String, List<int>>{};
    final perfByType = <String, List<int>>{};
    for (final e in allCompleted) {
      final dept =
          e.task.department.isNotEmpty ? e.task.department : 'غير محدد';
      final tech =
          e.task.technician.isNotEmpty ? e.task.technician : 'غير معيّن';
      final type = e.task.title.isNotEmpty ? e.task.title : 'غير محدد';
      perfByDept.putIfAbsent(dept, () => []).add(e.minutes);
      perfByTech.putIfAbsent(tech, () => []).add(e.minutes);
      perfByType.putIfAbsent(type, () => []).add(e.minutes);
    }
    // ترتيب حسب الوسيط (الأبطأ أولاً)
    int calcMedian(List<int> list) {
      final sorted = List<int>.from(list)..sort();
      return sorted[sorted.length ~/ 2];
    }

    final deptSorted = perfByDept.entries.toList()
      ..sort((a, b) => calcMedian(b.value).compareTo(calcMedian(a.value)));
    final techSorted = perfByTech.entries.toList()
      ..sort((a, b) => calcMedian(b.value).compareTo(calcMedian(a.value)));
    final typeSorted = perfByType.entries.toList()
      ..sort((a, b) => calcMedian(b.value).compareTo(calcMedian(a.value)));

    return _buildChartCard(
      title: 'تحليل التأخير والأداء',
      icon: Icons.warning_amber_rounded,
      iconColor: SdColors.danger,
      height: null, // ارتفاع تلقائي
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ══ مهام مفتوحة متأخرة الآن ══
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: openDelayed.isEmpty
                  ? SdColors.successTint
                  : SdColors.dangerTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: openDelayed.isEmpty
                      ? SdColors.successTintEdge
                      : SdColors.dangerTintEdge),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        openDelayed.isEmpty
                            ? Icons.check_circle
                            : Icons.access_alarm,
                        size: 20,
                        color: openDelayed.isEmpty ? SdColors.success : SdColors.danger),
                    const SizedBox(width: 6),
                    Text(
                      openDelayed.isEmpty
                          ? 'لا توجد مهام مفتوحة متأخرة'
                          : '${openDelayed.length} مهمة مفتوحة متأخرة الآن',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: openDelayed.isEmpty
                            ? SdColors.success
                            : SdColors.danger,
                      ),
                    ),
                  ],
                ),
                if (openDelayed.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...openDelayed.take(5).map((e) => Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text('#${e.task.id}',
                                style: TextStyle(
                                    fontSize: 10, color: SdColors.faint)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${e.task.title} — ${e.task.technician.isNotEmpty ? e.task.technician : "غير معيّن"}',
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: SdColors.danger,
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(_formatDuration(e.minutes),
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      )),
                  if (openDelayed.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('و ${openDelayed.length - 5} مهمة أخرى...',
                          style:
                              TextStyle(fontSize: 11, color: SdColors.danger)),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ══ تصنيف سرعة المكتملة ══
          Row(
            children: [
              Expanded(
                  child: _buildDelayStatChip(
                      '${completedDelayed.length}',
                      'متأخرة (> ${_formatDuration(delayedThreshold)})',
                      SdColors.danger)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildDelayStatChip(
                      '${completedSlow.length}',
                      'بطيئة (${_formatDuration(slowThreshold)}-${_formatDuration(delayedThreshold)})',
                      SdColors.warning)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildDelayStatChip(
                      '${completedFast.length}',
                      'سريعة (< ${_formatDuration(slowThreshold)})',
                      SdColors.success)),
            ],
          ),

          if (excludedCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '* $excludedCount مهمة مستبعدة (أكثر من 7 أيام — غالباً مهام منسية)',
                style: TextStyle(
                    fontSize: 11,
                    color: SdColors.faint,
                    fontStyle: FontStyle.italic),
              ),
            ),

          if (completedDelayed.isNotEmpty) ...[
            const SizedBox(height: 16),

            // ══ الأقسام ══
            _buildPerfSection(
                'متوسط الإنجاز حسب القسم:', deptSorted, SdColors.info, medianMin),
            const SizedBox(height: 12),

            _buildPerfSection('متوسط الإنجاز حسب الفني:', techSorted,
                SdColors.warning, medianMin),
            const SizedBox(height: 12),

            _buildPerfSection('متوسط الإنجاز حسب نوع المهمة:', typeSorted,
                SdColors.platformBase, medianMin),
            const SizedBox(height: 16),

            // ══ أبطأ 5 مهام مكتملة ══
            const Text('أبطأ 5 مهام مكتملة:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ...allCompleted.take(5).map((e) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: SdColors.dangerTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SdColors.dangerTintEdge),
                  ),
                  child: Row(
                    children: [
                      Text('#${e.task.id}',
                          style:
                              TextStyle(fontSize: 10, color: SdColors.faint)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.task.title,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                              '${e.task.department} — ${e.task.technician.isNotEmpty ? e.task.technician : "غير معيّن"}',
                              style: TextStyle(
                                  fontSize: 11, color: SdColors.muted)),
                        ],
                      )),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: SdColors.danger,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(_formatDuration(e.minutes),
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  /// قسم أداء (قسم/فني/نوع) — يعرض الوسيط لكل فئة مع لون حسب المقارنة بالوسيط العام
  Widget _buildPerfSection(String title, List<MapEntry<String, List<int>>> data,
      Color baseColor, int globalMedian) {
    if (data.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        ...data.take(5).map((e) {
          final sorted = List<int>.from(e.value)..sort();
          final med = sorted[sorted.length ~/ 2];
          // لون حسب المقارنة: أخضر إذا أسرع من الوسيط العام، أحمر إذا أبطأ بكثير
          final Color chipColor;
          if (med <= globalMedian) {
            chipColor = SdColors.success;
          } else if (med <= globalMedian * 3) {
            chipColor = SdColors.warning;
          } else {
            chipColor = SdColors.danger;
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.7),
                        shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(e.key,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600))),
                Text('${e.value.length} مهمة',
                    style: TextStyle(fontSize: 12, color: SdColors.muted)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: chipColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('وسيط ${_formatDuration(med)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: chipColor,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDelayStatChip(String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(count,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  بطاقة إحصاء معلوماتية (SLA + متوسط)
  // ══════════════════════════════════════

  Widget _buildStatInfoCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required String value,
    required String subtitle,
    required Color valueColor,
  }) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: SdColors.muted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
