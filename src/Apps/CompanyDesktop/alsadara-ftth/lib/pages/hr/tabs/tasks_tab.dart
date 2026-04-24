/// تبويب المهام — عرض مهام الموظف مع الحالات والمشرفين
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/employee_profile_service.dart';

class TasksTab extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final bool canAddTask;
  final bool canEditTask;

  const TasksTab({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.canAddTask,
    required this.canEditTask,
  });

  @override
  State<TasksTab> createState() => _TasksTabState();
}

class _TasksTabState extends State<TasksTab> {
  final _service = EmployeeProfileService.instance;
  bool _loading = true;
  List<Map<String, dynamic>> _tasks = [];
  String _filter = 'all'; // all, pending, inProgress, completed, overdue

  static const _accent = Color(0xFF3498DB);
  static const _green = Color(0xFF27AE60);
  static const _red = Color(0xFFE74C3C);
  static const _orange = Color(0xFFF39C12);
  static const _purple = Color(0xFF8E44AD);
  static const _gray = Color(0xFF95A5A6);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getEmployeeTasks(widget.employeeId);
      setState(() {
        _tasks = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _tasks;
    return _tasks.where((t) {
      final s = (t['status'] ?? t['Status'] ?? '').toString().toLowerCase();
      switch (_filter) {
        case 'pending':
          return s == 'pending' || s == 'معلقة';
        case 'inProgress':
          return s == 'inprogress' || s == 'in_progress' || s == 'قيد التنفيذ';
        case 'completed':
          return s == 'completed' || s == 'done' || s == 'مكتملة';
        case 'overdue':
          return s == 'overdue' || s == 'متأخرة';
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    return Column(
      children: [
        _header(),
        const SizedBox(height: 4),
        _filterChips(),
        const SizedBox(height: 8),
        Expanded(child: _tasksList()),
      ],
    );
  }

  Widget _header() {
    final total = _tasks.length;
    final completed = _tasks.where((t) {
      final s = (t['status'] ?? t['Status'] ?? '').toString().toLowerCase();
      return s == 'completed' || s == 'done' || s == 'مكتملة';
    }).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _miniStat('إجمالي', total, _accent),
          const SizedBox(width: 12),
          _miniStat('مكتملة', completed, _green),
          const SizedBox(width: 12),
          _miniStat('نسبة الإنجاز', total > 0 ? (completed * 100 ~/ total) : 0,
              _purple,
              suffix: '%'),
          const Spacer(),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: _accent),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, int val, Color c, {String suffix = ''}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$val$suffix',
              style: GoogleFonts.cairo(
                  fontSize: 16, fontWeight: FontWeight.bold, color: c)),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
        ],
      ),
    );
  }

  Widget _filterChips() {
    const filters = [
      ('all', 'الكل', Icons.list),
      ('pending', 'معلقة', Icons.hourglass_empty),
      ('inProgress', 'قيد التنفيذ', Icons.autorenew),
      ('completed', 'مكتملة', Icons.check_circle),
      ('overdue', 'متأخرة', Icons.warning),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: filters.map((f) {
          final selected = _filter == f.$1;
          return ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(f.$3, size: 14, color: selected ? Colors.white : _gray),
                  const SizedBox(width: 4),
                  Text(f.$2),
                ],
              ),
              selected: selected,
              selectedColor: _accent,
              labelStyle: GoogleFonts.cairo(
                  color: selected ? Colors.white : Colors.black87,
                  fontSize: 11),
              onSelected: (_) => setState(() => _filter = f.$1),
          );
        }).toList(),
      ),
    );
  }

  Widget _tasksList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.task_outlined, size: 48, color: _gray.withOpacity(0.5)),
            const SizedBox(height: 8),
            Text('لا توجد مهام',
                style: GoogleFonts.cairo(color: _gray, fontSize: 14)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _taskCard(items[i]),
    );
  }

  Widget _taskCard(Map<String, dynamic> task) {
    final title =
        task['title'] ?? task['Title'] ?? task['description'] ?? 'مهمة';
    final status = (task['status'] ?? task['Status'] ?? '').toString();
    final priority = (task['priority'] ?? task['Priority'] ?? '').toString();
    final assignedBy =
        task['assignedBy'] ?? task['AssignedBy'] ?? task['createdByName'] ?? '';
    final dueDate = task['dueDate'] ?? task['DueDate'] ?? '';
    final createdAt = task['createdAt'] ?? task['CreatedAt'] ?? '';
    final statusColor = _getStatusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
        border: Border(right: BorderSide(color: statusColor, width: 4)),
      ),
      child: Padding(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width < 500 ? 8 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                _statusBadge(status, statusColor),
                if (priority.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  _priorityBadge(priority),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (assignedBy.toString().isNotEmpty) ...[
                  const Icon(Icons.person_outline, size: 14, color: _gray),
                  const SizedBox(width: 4),
                  Text('بواسطة: $assignedBy',
                      style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
                  const SizedBox(width: 16),
                ],
                if (dueDate.toString().isNotEmpty) ...[
                  const Icon(Icons.event, size: 14, color: _gray),
                  const SizedBox(width: 4),
                  Text(_formatDate(dueDate.toString()),
                      style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
                ],
                const Spacer(),
                if (createdAt.toString().isNotEmpty)
                  Text(_formatDate(createdAt.toString()),
                      style: GoogleFonts.cairo(fontSize: 10, color: _gray)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _getStatusLabel(status),
        style: GoogleFonts.cairo(
            color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _priorityBadge(String priority) {
    final p = priority.toLowerCase();
    Color c;
    String label;
    if (p == 'high' || p == 'عالية') {
      c = _red;
      label = 'عالية';
    } else if (p == 'medium' || p == 'متوسطة') {
      c = _orange;
      label = 'متوسطة';
    } else {
      c = _green;
      label = 'منخفضة';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: GoogleFonts.cairo(
              color: c, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'completed' || s == 'done') return _green;
    if (s == 'inprogress' || s == 'in_progress') return _accent;
    if (s == 'overdue') return _red;
    if (s == 'pending') return _orange;
    return _gray;
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'معلقة';
      case 'inprogress':
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
      case 'done':
        return 'مكتملة';
      case 'overdue':
        return 'متأخرة';
      default:
        return status;
    }
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
