import 'package:flutter/material.dart';
import 'dart:async';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/ftth_connect_service.dart';
import 'ftth_connect_form.dart';

/// صفحة قائمة مهام FTTH (Connect Customer / Sign Contract / Maintenance)
class FtthTasksPage extends StatefulWidget {
  const FtthTasksPage({super.key});

  @override
  State<FtthTasksPage> createState() => _FtthTasksPageState();
}

class _FtthTasksPageState extends State<FtthTasksPage> {
  final _service = FtthConnectService.instance;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  // ─── Responsive helpers ───
  bool get _isPhone =>
      MediaQuery.of(context).size.width < 500;

  double _fs(double size) {
    final v = _isPhone ? size * 0.85 : size;
    return v < 11.5 ? 11.5 : v; // أصغر خط مسموح 11.5 (نظام التصميم الموحّد)
  }

  double _ic(double size) => _isPhone ? size * 0.85 : size;

  // بيانات
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _taskTypes = [];
  int _totalCount = 0;
  bool _isLoading = true;
  String? _error;

  // فلاتر
  int _statusFilter = 1; // 1 = Not started
  final Set<String> _selectedTypeIds = {};
  int _currentPage = 1;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final types = await _service.getTaskTypes();
      if (!mounted) return;
      setState(() {
        _taskTypes = types;
        // تحديد Connect Customer + Sign Contract افتراضياً
        for (final t in types) {
          final name = (t['displayValue'] ?? '').toString().toLowerCase();
          if (name.contains('connect') || name.contains('sign')) {
            _selectedTypeIds.add(t['id'] as String);
          }
        }
      });
      await _fetchTasks();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'فشل تحميل البيانات: $e';
      });
    }
  }

  Future<void> _fetchTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final query = _searchController.text.trim();
      final isPhone = query.isNotEmpty && RegExp(r'^[0-9+]+$').hasMatch(query);

      final result = await _service.getTasks(
        status: _statusFilter,
        typeIds: _selectedTypeIds.toList(),
        pageSize: _pageSize,
        pageNumber: _currentPage,
        customerName: (!isPhone && query.isNotEmpty) ? query : null,
        customerPhone: (isPhone && query.isNotEmpty) ? query : null,
      );
      if (!mounted) return;
      setState(() {
        _tasks = List<Map<String, dynamic>>.from(result['items'] ?? []);
        _totalCount = result['totalCount'] ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '$e';
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 600), () {
      _currentPage = 1;
      _fetchTasks();
    });
  }

  void _openConnectForm(Map<String, dynamic> task) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FtthConnectForm(task: task),
      ),
    ).then((result) {
      if (result == true) _fetchTasks(); // تحديث بعد توصيل ناجح
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (_totalCount / _pageSize).ceil().clamp(1, 9999);

    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'مهام التوصيل — FTTH',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _fetchTasks,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              // ═══ شريط الفلاتر ═══
              _buildFilters(),

              // ═══ المحتوى ═══
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: SdEmptyState(
                              icon: Icons.error_outline,
                              status: SdStatus.danger,
                              title: _error!,
                              action: SdButton(
                                label: 'إعادة المحاولة',
                                icon: Icons.refresh,
                                onPressed: _fetchTasks,
                              ),
                            ),
                          )
                        : _tasks.isEmpty
                            ? const Center(
                                child: SdEmptyState(
                                  icon: Icons.assignment_outlined,
                                  title: 'لا توجد مهام',
                                ),
                              )
                            : ListView.builder(
                                padding: EdgeInsets.symmetric(
                                    horizontal: _isPhone ? 8 : 16, vertical: 8),
                                itemCount: _tasks.length,
                                itemBuilder: (ctx, i) =>
                                    _buildTaskCard(_tasks[i]),
                              ),
              ),

              // ═══ Pagination ═══
              if (!_isLoading && _totalCount > _pageSize)
                _buildPagination(totalPages),
            ],
          ),
        ),
      ),
    );
  }

  // ─── الفلاتر ───
  Widget _buildFilters() {
    return Container(
      padding: EdgeInsets.all(_isPhone ? 8 : 12),
      decoration: const BoxDecoration(
        color: SdColors.surface,
        boxShadow: [
          BoxShadow(color: SdColors.cardEdge, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // حقل البحث
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              hintText: 'بحث باسم الزبون أو رقم الهاتف...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: _ic(18)),
                      onPressed: () {
                        _searchController.clear();
                        _currentPage = 1;
                        _fetchTasks();
                      },
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: SdColors.surfaceAlt,
            ),
          ),
          const SizedBox(height: 10),

          // فلتر الحالة
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SdFilterChips<int>(
              selected: _statusFilter,
              options: const [
                SdFilterOption(0, 'الكل'),
                SdFilterOption(1, 'لم تبدأ'),
                SdFilterOption(2, 'قيد التنفيذ'),
                SdFilterOption(3, 'مكتملة'),
              ],
              onSelected: (value) {
                setState(() => _statusFilter = value);
                _currentPage = 1;
                _fetchTasks();
              },
            ),
          ),
          const SizedBox(height: 8),

          // فلتر النوع
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text('النوع: ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: _fs(13))),
                const SizedBox(width: 8),
                ..._taskTypes.map((t) => Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FilterChip(
                        label: Text(_translateTaskType(t['displayValue'] ?? ''),
                            style: TextStyle(fontSize: _fs(12))),
                        selected: _selectedTypeIds.contains(t['id']),
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedTypeIds.add(t['id'] as String);
                            } else {
                              _selectedTypeIds.remove(t['id']);
                            }
                          });
                          _currentPage = 1;
                          _fetchTasks();
                        },
                        selectedColor: SdColors.primaryTint,
                        checkmarkColor: SdColors.primary,
                        visualDensity: VisualDensity.compact,
                      ),
                    )),
              ],
            ),
          ),

          // العدد الكلي
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'المجموع: $_totalCount مهمة',
                style: TextStyle(color: SdColors.muted, fontSize: _fs(12)),
              ),
            ),
        ],
      ),
    );
  }

  // ─── بطاقة المهمة ───
  Widget _buildTaskCard(Map<String, dynamic> task) {
    final customer = task['customer'] as Map<String, dynamic>?;
    final zone = task['zone'] as Map<String, dynamic>?;
    final self = task['self'] as Map<String, dynamic>?;
    final customerName = customer?['displayValue'] ?? 'بدون اسم';
    final zoneName = zone?['displayValue'] ?? '-';
    final taskName = self?['displayValue'] ?? '-';
    final status = task['status'] ?? '';
    final createdAt = task['createdAt'] ?? '';
    final dueAt = task['dueAt'] ?? '';

    SdStatus statusTone;
    String statusAr;
    switch (status) {
      case 'Not started':
        statusTone = SdStatus.warning;
        statusAr = 'لم تبدأ';
        break;
      case 'In progress':
        statusTone = SdStatus.info;
        statusAr = 'قيد التنفيذ';
        break;
      case 'Completed':
        statusTone = SdStatus.success;
        statusAr = 'مكتملة';
        break;
      default:
        statusTone = SdStatus.neutral;
        statusAr = status;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SdRaised(
        onTap: () => _openConnectForm(task),
        padding: EdgeInsets.all(_isPhone ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // السطر الأول: الاسم + الحالة
            Row(
              children: [
                Expanded(
                  child: Text(
                    customerName,
                    style: TextStyle(
                        fontSize: _fs(15),
                        fontWeight: FontWeight.bold,
                        color: SdColors.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SdStatusChip(statusAr, status: statusTone),
              ],
            ),
            const SizedBox(height: 6),

            // السطر الثاني: النوع + الزون
            Row(
              children: [
                Icon(Icons.cable, size: _ic(14), color: SdColors.faint),
                const SizedBox(width: 4),
                Text(_translateTaskType(taskName),
                    style: TextStyle(fontSize: _fs(12), color: SdColors.muted)),
                SizedBox(width: _isPhone ? 10 : 16),
                Icon(Icons.location_on, size: _ic(14), color: SdColors.faint),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(zoneName,
                      style:
                          TextStyle(fontSize: _fs(12), color: SdColors.muted),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // السطر الثالث: التواريخ
            Row(
              children: [
                Icon(Icons.calendar_today, size: _ic(12), color: SdColors.faint),
                const SizedBox(width: 4),
                Text(_formatDate(createdAt),
                    style: TextStyle(fontSize: _fs(11.5), color: SdColors.faint)),
                if (dueAt.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.timer, size: _ic(12), color: SdColors.faint),
                  const SizedBox(width: 4),
                  Text(_formatDate(dueAt),
                      style:
                          TextStyle(fontSize: _fs(11.5), color: SdColors.faint)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Pagination ───
  Widget _buildPagination(int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: SdColors.surface,
        boxShadow: [
          BoxShadow(color: SdColors.cardEdge, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_right, color: SdColors.primary),
            onPressed: _currentPage > 1
                ? () {
                    _currentPage--;
                    _fetchTasks();
                  }
                : null,
          ),
          Text('$_currentPage / $totalPages',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: SdColors.ink)),
          IconButton(
            icon: const Icon(Icons.chevron_left, color: SdColors.primary),
            onPressed: _currentPage < totalPages
                ? () {
                    _currentPage++;
                    _fetchTasks();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ─── مساعدات ───
  String _translateTaskType(String type) {
    switch (type.toLowerCase()) {
      case 'connect customer':
      case 'install physical devices':
        return 'توصيل مشترك';
      case 'sign contract':
        return 'توقيع عقد';
      case 'maintenance':
        return 'صيانة';
      default:
        return type;
    }
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
