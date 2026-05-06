import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/smart_text_color.dart';
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../services/task_export_service.dart';

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

  // بحث سيرفر
  Timer? _searchDebounce;
  bool _isSearching = false;
  List<Task>? _serverSearchResults;
  int _serverSearchTotal = 0;

  // فلتر التاريخ
  DateTimeRange? _dateRange;
  String _dateLabel = 'الكل';

  @override
  void initState() {
    super.initState();
    currentFilteredTasks = widget.tasks;
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
        _serverSearchTotal = total is int ? total : int.tryParse('$total') ?? tasks.length;
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
        _serverSearchTotal = total is int ? total : int.tryParse('$total') ?? tasks.length;
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
    final source = _serverSearchResults ?? widget.tasks;
    _applyLocalFiltersOnList(source);
  }

  void _applyLocalFiltersOnList(List<Task> source) {
    setState(() {
      currentFilteredTasks = source.where((task) {
        if (selectedDepartment != null && task.department != selectedDepartment) return false;
        if (selectedTechnician != null && task.technician != selectedTechnician) return false;
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
      currentFilteredTasks = widget.tasks;
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
      initialDateRange: _dateRange ?? DateTimeRange(
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
    final source = _serverSearchResults ?? widget.tasks;
    Set<String> departments = source
        .map((task) => task.department)
        .where((dept) => dept.isNotEmpty)
        .toSet();
    Set<String> technicians = source
        .map((task) => task.technician)
        .where((tech) => tech.isNotEmpty)
        .toSet();
    Set<String> fbgs = source
        .map((task) => task.fbg)
        .where((fbg) => fbg.isNotEmpty)
        .toSet();

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
    final gradientColors = [Colors.blueAccent, Colors.blue[700]!];
    final smartTextColor =
        SmartTextColor.getAppBarTextColorWithGradient(context, gradientColors);
    final smartIconColor = smartTextColor;

    final bool hasActiveFilters = selectedDepartment != null ||
        selectedTechnician != null ||
        selectedFBG != null ||
        _dateRange != null;

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
          'التقارير',
          style: SmartTextColor.getSmartTextStyle(
            context: context,
            fontSize: 24,
            fontWeight: FontWeight.bold,
            gradientColors: gradientColors,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: smartIconColor),
        elevation: 4,
        actions: [
          // أزرار التصدير
          PopupMenuButton<String>(
            icon: Icon(Icons.file_download_outlined, color: smartIconColor),
            tooltip: 'تصدير',
            onSelected: (value) async {
              try {
                if (value == 'excel') {
                  await TaskExportService.exportToExcel(tasks: currentFilteredTasks);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصدير Excel'), backgroundColor: Colors.green));
                } else {
                  await TaskExportService.exportToPdf(tasks: currentFilteredTasks);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصدير PDF'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('خطأ في التصدير'), backgroundColor: Colors.red));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'excel', child: Row(children: [
                Icon(Icons.table_chart, color: Colors.green, size: 20), SizedBox(width: 8), Text('تصدير Excel'),
              ])),
              PopupMenuItem(value: 'pdf', child: Row(children: [
                Icon(Icons.picture_as_pdf, color: Colors.red, size: 20), SizedBox(width: 8), Text('تصدير PDF'),
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
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
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

            // ── مربع البحث (سيرفر) ──
            _buildSearchBox(),
            const SizedBox(height: 8),

            // ── عدد النتائج ──
            if (_serverSearchResults != null || _dateRange != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      'نتائج السيرفر: $_serverSearchTotal مهمة (معروض: ${currentFilteredTasks.length})',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: currentFilteredTasks.length,
                          itemBuilder: (context, index) {
                            return _buildTaskCard(currentFilteredTasks[index]);
                          },
                        ),
            ),
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
            _dateChip('7 أيام', last7),
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
                        _dateLabel != '7 أيام' &&
                        _dateLabel != 'هذا الشهر'
                    ? Colors.white
                    : Colors.blue[700],
              ),
              label: Text(
                _dateLabel != 'الكل' &&
                        _dateLabel != 'اليوم' &&
                        _dateLabel != 'أمس' &&
                        _dateLabel != '7 أيام' &&
                        _dateLabel != 'هذا الشهر'
                    ? _dateLabel
                    : 'مخصص',
                style: TextStyle(
                  fontSize: 12,
                  color: _dateLabel != 'الكل' &&
                          _dateLabel != 'اليوم' &&
                          _dateLabel != 'أمس' &&
                          _dateLabel != '7 أيام' &&
                          _dateLabel != 'هذا الشهر'
                      ? Colors.white
                      : null,
                ),
              ),
              backgroundColor: _dateLabel != 'الكل' &&
                      _dateLabel != 'اليوم' &&
                      _dateLabel != 'أمس' &&
                      _dateLabel != '7 أيام' &&
                      _dateLabel != 'هذا الشهر'
                  ? Colors.blue[700]
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
      label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : null)),
      selected: isSelected,
      selectedColor: Colors.blue[700],
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
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(color: Colors.blue.shade200),
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
                  color: Colors.grey.withValues(alpha: 0.3),
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
                        Expanded(child: _buildStatCard('المجموع الكلي', currentFilteredTasks.length.toString(), Icons.assignment, Colors.blue, true)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildStatCard('المكتملة', currentFilteredTasks.where((t) => t.status == 'مكتملة').length.toString(), Icons.check_circle, Colors.green, true)),
                      ]),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(child: _buildStatCard('الملغية', currentFilteredTasks.where((t) => t.status == 'ملغية').length.toString(), Icons.cancel, Colors.red, true)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildStatCard('المبلغ الإجمالي', '${widget.calculateTotalAmount(currentFilteredTasks).toStringAsFixed(0)} د.ع', Icons.account_balance_wallet, Colors.orange, true)),
                      ]),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(child: _buildStatCard('المجموع الكلي', currentFilteredTasks.length.toString(), Icons.assignment, Colors.blue, false)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('المكتملة', currentFilteredTasks.where((t) => t.status == 'مكتملة').length.toString(), Icons.check_circle, Colors.green, false)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('الملغية', currentFilteredTasks.where((t) => t.status == 'ملغية').length.toString(), Icons.cancel, Colors.red, false)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildStatCard('المبلغ الإجمالي', '${widget.calculateTotalAmount(currentFilteredTasks).toStringAsFixed(0)} د.ع', Icons.account_balance_wallet, Colors.orange, false)),
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
          hintText: 'بحث في كل المهام (اسم العميل، الهاتف، الفني، رقم المهمة...)',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          prefixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            borderSide: BorderSide(color: Colors.blue.shade400, width: 1.5),
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
          Icon(Icons.assignment_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'لا توجد مهام تطابق الفلاتر المحددة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'قم بتعديل الفلاتر أو مسحها لرؤية المزيد من المهام',
            style: TextStyle(fontSize: 16, color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════
  //  بطاقة إحصائيات
  // ══════════════════════════════════════

  Widget _buildStatCard(String title, String value, IconData icon, Color color,
      bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 8.0 : 12.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: isSmallScreen ? 24 : 32, color: color),
          SizedBox(height: isSmallScreen ? 6 : 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          SizedBox(height: isSmallScreen ? 2 : 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: TextStyle(
                fontSize: isSmallScreen ? 10 : 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

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
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(task.status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // ── البيانات الظاهرة دائماً ──
                _buildCompactRow(Icons.business, 'القسم', task.department, Icons.person, 'الفني', task.technician),
                const SizedBox(height: 6),
                _buildCompactRow(Icons.router, 'FBG', task.fbg, Icons.phone, 'الهاتف', task.phone),
                const SizedBox(height: 6),
                _buildCompactRow(Icons.attach_money, 'المبلغ', '${task.amount} د.ع', Icons.calendar_today, 'الإنشاء', fmt.format(task.createdAt)),
                const SizedBox(height: 6),
                _buildDetailRow(Icons.access_time, 'وقت التنفيذ', widget.calculateTaskDuration(task)),

                // ── سهم التوسيع ──
                if (hasHiddenDetails)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                          size: 20,
                          color: Colors.grey[400],
                        ),
                        Text(
                          isExpanded ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
                          style: TextStyle(fontSize: 11, color: Colors.grey[400]),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_pin, size: 18, color: Colors.blue[700]),
                          const SizedBox(width: 8),
                          Text('العميل: ', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[700], fontSize: 14)),
                          Expanded(
                            child: Text(task.username, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue[900], fontSize: 14)),
                          ),
                        ],
                      ),
                    ),

                  if (task.leader.isNotEmpty)
                    _buildDetailRow(Icons.supervisor_account, 'الليدر', task.leader),
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
    IconData icon1, String label1, String value1,
    IconData icon2, String label2, String value2,
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
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[600], fontSize: 12)),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12, color: Colors.black87), overflow: TextOverflow.ellipsis),
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
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey[700], fontSize: 14),
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'مكتملة':
        return Colors.green;
      case 'قيد التنفيذ':
        return Colors.orange;
      case 'جديدة':
        return Colors.blue;
      case 'ملغية':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
