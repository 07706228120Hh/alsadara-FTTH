import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/task.dart';

/// لوحة أداء الفنيين — إحصائيات ورسوم بيانية
class TechnicianPerformancePage extends StatefulWidget {
  final List<Task> tasks;

  const TechnicianPerformancePage({super.key, required this.tasks});

  @override
  State<TechnicianPerformancePage> createState() =>
      _TechnicianPerformancePageState();
}

class _TechnicianPerformancePageState extends State<TechnicianPerformancePage> {
  String _sortBy = 'total'; // total, done, rate, avgTime

  // فلاتر
  String? _selectedTechnician;
  DateTimeRange? _dateRange;

  /// المهام بعد تطبيق الفلاتر
  List<Task> get _filteredTasks {
    var tasks = widget.tasks;

    // فلتر التاريخ
    if (_dateRange != null) {
      final start = DateTime(_dateRange!.start.year, _dateRange!.start.month, _dateRange!.start.day);
      final end = DateTime(_dateRange!.end.year, _dateRange!.end.month, _dateRange!.end.day, 23, 59, 59);
      tasks = tasks.where((t) =>
          t.createdAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
          t.createdAt.isBefore(end.add(const Duration(seconds: 1)))).toList();
    }

    // فلتر الفني
    if (_selectedTechnician != null) {
      tasks = tasks.where((t) => t.technician == _selectedTechnician).toList();
    }

    return tasks;
  }

  /// قائمة أسماء الفنيين (بدون تكرار)
  List<String> get _technicianNames {
    final names = <String>{};
    for (final t in widget.tasks) {
      if (t.technician.trim().isNotEmpty) names.add(t.technician);
    }
    final list = names.toList()..sort();
    return list;
  }

  /// تجميع بيانات الفنيين
  List<_TechStat> _buildStats() {
    final map = <String, _TechStat>{};
    for (final t in _filteredTasks) {
      if (t.technician.trim().isEmpty) continue;
      map.putIfAbsent(t.technician,
          () => _TechStat(name: t.technician, department: t.department));
      final s = map[t.technician]!;
      s.total++;
      if (t.status == 'مفتوحة') s.open++;
      if (t.status == 'قيد التنفيذ') s.progress++;
      if (t.status == 'مكتملة') {
        s.done++;
        if (t.closedAt != null) {
          s.totalMinutes += t.closedAt!.difference(t.createdAt).inMinutes;
        }
      }
      if (t.status == 'ملغية') s.cancelled++;
      final amt =
          double.tryParse(t.amount.replaceAll('\$', '').replaceAll(',', '')) ??
              0;
      s.totalAmount += amt;
    }

    final list = map.values.toList();
    switch (_sortBy) {
      case 'done':
        list.sort((a, b) => b.done.compareTo(a.done));
        break;
      case 'rate':
        list.sort((a, b) => b.completionRate.compareTo(a.completionRate));
        break;
      case 'avgTime':
        list.sort((a, b) => a.avgMinutes.compareTo(b.avgMinutes));
        break;
      default:
        list.sort((a, b) => b.total.compareTo(a.total));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _buildStats();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text('أداء الفنيين',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: const Color(0xFF1A237E),
          foregroundColor: Colors.white,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort),
              tooltip: 'ترتيب حسب',
              onSelected: (v) => setState(() => _sortBy = v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'total', child: Text('الإجمالي')),
                PopupMenuItem(value: 'done', child: Text('المكتملة')),
                PopupMenuItem(value: 'rate', child: Text('نسبة الإنجاز')),
                PopupMenuItem(value: 'avgTime', child: Text('أسرع إنجاز')),
              ],
            ),
          ],
        ),
        body: stats.isEmpty && _filteredTasks.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('لا توجد بيانات',
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                    if (_selectedTechnician != null || _dateRange != null) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _selectedTechnician = null;
                          _dateRange = null;
                        }),
                        icon: const Icon(Icons.filter_alt_off),
                        label: const Text('إزالة الفلاتر'),
                      ),
                    ],
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.all(isMobile ? 10 : 20),
                child: Column(
                  children: [
                    // ─── شريط الفلاتر ───
                    _buildFiltersBar(isMobile),
                    SizedBox(height: isMobile ? 10 : 16),

                    // ─── الرسم البياني ───
                    _buildChart(stats, isMobile),
                    SizedBox(height: isMobile ? 12 : 20),

                    // ─── بطاقات الفنيين ───
                    ...stats
                        .asMap()
                        .entries
                        .map((e) => _buildTechCard(e.key + 1, e.value, isMobile)),
                  ],
                ),
              ),
      ),
    );
  }

  /// شريط الفلاتر — فني + تاريخ
  Widget _buildFiltersBar(bool isMobile) {
    final dateFormat = DateFormat('yyyy/MM/dd');
    final hasFilters = _selectedTechnician != null || _dateRange != null;

    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // أيقونة الفلتر
          Icon(Icons.filter_alt_outlined, size: 20, color: hasFilters ? const Color(0xFF1A237E) : Colors.grey),

          // فلتر الفني
          Container(
            constraints: BoxConstraints(maxWidth: isMobile ? 160 : 220),
            height: 38,
            decoration: BoxDecoration(
              color: _selectedTechnician != null
                  ? const Color(0xFF1A237E).withValues(alpha: 0.08)
                  : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _selectedTechnician != null
                    ? const Color(0xFF1A237E).withValues(alpha: 0.3)
                    : Colors.grey.shade300,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTechnician,
                isExpanded: true,
                isDense: true,
                hint: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('جميع الفنيين',
                      style: TextStyle(fontSize: isMobile ? 11 : 13, color: Colors.grey.shade600)),
                ),
                icon: Icon(
                  _selectedTechnician != null ? Icons.close : Icons.arrow_drop_down,
                  size: 18,
                  color: _selectedTechnician != null ? Colors.red : Colors.grey,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                borderRadius: BorderRadius.circular(10),
                style: TextStyle(fontSize: isMobile ? 11 : 13, color: const Color(0xFF2D3250)),
                onTap: _selectedTechnician != null
                    ? () {
                        setState(() => _selectedTechnician = null);
                      }
                    : null,
                items: _technicianNames
                    .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedTechnician = v),
              ),
            ),
          ),

          // فلتر التاريخ
          InkWell(
            onTap: _pickDateRange,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _dateRange != null
                    ? const Color(0xFF1A237E).withValues(alpha: 0.08)
                    : const Color(0xFFF5F7FA),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _dateRange != null
                      ? const Color(0xFF1A237E).withValues(alpha: 0.3)
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.date_range, size: 16,
                      color: _dateRange != null ? const Color(0xFF1A237E) : Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    _dateRange != null
                        ? '${dateFormat.format(_dateRange!.start)} — ${dateFormat.format(_dateRange!.end)}'
                        : 'كل الأوقات',
                    style: TextStyle(
                      fontSize: isMobile ? 11 : 12,
                      color: _dateRange != null ? const Color(0xFF1A237E) : Colors.grey.shade600,
                      fontWeight: _dateRange != null ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (_dateRange != null) ...[
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => setState(() => _dateRange = null),
                      child: const Icon(Icons.close, size: 16, color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // أزرار سريعة للتاريخ
          _quickDateChip('اليوم', 0),
          _quickDateChip('أسبوع', 7),
          _quickDateChip('شهر', 30),

          // إزالة الكل
          if (hasFilters)
            InkWell(
              onTap: () => setState(() {
                _selectedTechnician = null;
                _dateRange = null;
              }),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_alt_off, size: 14, color: Colors.red),
                    const SizedBox(width: 4),
                    Text('مسح', style: TextStyle(fontSize: isMobile ? 10 : 11, color: Colors.red, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quickDateChip(String label, int daysAgo) {
    final now = DateTime.now();
    final start = daysAgo == 0
        ? DateTime(now.year, now.month, now.day)
        : DateTime(now.year, now.month, now.day).subtract(Duration(days: daysAgo));
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final isActive = _dateRange != null &&
        _dateRange!.start.year == start.year &&
        _dateRange!.start.month == start.month &&
        _dateRange!.start.day == start.day &&
        _dateRange!.end.year == end.year &&
        _dateRange!.end.month == end.month &&
        _dateRange!.end.day == end.day;

    return InkWell(
      onTap: () => setState(() {
        _dateRange = DateTimeRange(start: start, end: end);
      }),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1A237E) : const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? const Color(0xFF1A237E) : Colors.grey.shade300,
          ),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 11,
          color: isActive ? Colors.white : Colors.grey.shade700,
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        )),
      ),
    );
  }

  Future<void> _pickDateRange() async {
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
    );
    if (picked != null && mounted) {
      setState(() => _dateRange = picked);
    }
  }

  /// رسم بياني شريطي لمقارنة الفنيين — محسّن
  Widget _buildChart(List<_TechStat> stats, bool isMobile) {
    final top = stats.take(10).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    final maxVal =
        top.fold<int>(0, (m, s) => s.total > m ? s.total : m).toDouble();

    return Container(
      height: isMobile ? 280 : 360,
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('مقارنة الفنيين',
                  style: TextStyle(
                      fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${top.length} فني',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 6),
          // مفتاح الألوان
          Wrap(
            spacing: isMobile ? 8 : 16,
            children: [
              _legendDot('مكتملة', const Color(0xFF4CAF50)),
              _legendDot('تنفيذ', const Color(0xFFFF9800)),
              _legendDot('مفتوحة', const Color(0xFF2196F3)),
              _legendDot('ملغية', const Color(0xFFE53935)),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.25,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    tooltipPadding: const EdgeInsets.all(8),
                    tooltipMargin: 8,
                    getTooltipItem: (group, gIdx, rod, rIdx) {
                      final s = top[group.x];
                      final labels = ['مكتملة', 'تنفيذ', 'مفتوحة', 'ملغية'];
                      final values = [s.done, s.progress, s.open, s.cancelled];
                      return BarTooltipItem(
                        '${s.name}\n${labels[rIdx]}: ${values[rIdx]}',
                        const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: isMobile ? 50 : 44,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= top.length) return const SizedBox.shrink();
                        final name = top[idx].name;
                        final displayName = name.length > 8
                            ? '${name.substring(0, 8)}..'
                            : name;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: RotatedBox(
                            quarterTurns: isMobile ? 1 : 0,
                            child: Text(
                              displayName,
                              style: TextStyle(
                                  fontSize: isMobile ? 9 : 11,
                                  fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
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
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            value.toInt().toString(),
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxVal > 10 ? (maxVal / 5).ceilToDouble() : 2,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.shade200,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                    right: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                barGroups: top.asMap().entries.map((e) {
                  final s = e.value;
                  final w = isMobile ? 8.0 : 14.0;
                  final r =
                      const BorderRadius.vertical(top: Radius.circular(4));
                  return BarChartGroupData(x: e.key, barsSpace: isMobile ? 2 : 3, barRods: [
                    BarChartRodData(
                      toY: s.done.toDouble(),
                      width: w,
                      borderRadius: r,
                      color: const Color(0xFF4CAF50),
                    ),
                    BarChartRodData(
                      toY: s.progress.toDouble(),
                      width: w,
                      borderRadius: r,
                      color: const Color(0xFFFF9800),
                    ),
                    BarChartRodData(
                      toY: s.open.toDouble(),
                      width: w,
                      borderRadius: r,
                      color: const Color(0xFF2196F3),
                    ),
                    BarChartRodData(
                      toY: s.cancelled.toDouble(),
                      width: w,
                      borderRadius: r,
                      color: const Color(0xFFE53935),
                    ),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
      ],
    );
  }

  /// بطاقة أداء فني
  Widget _buildTechCard(int rank, _TechStat s, bool isMobile) {
    final rateColor = s.completionRate >= 70
        ? const Color(0xFF4CAF50)
        : s.completionRate >= 40
            ? const Color(0xFFFF9800)
            : const Color(0xFFE53935);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            rank <= 3 ? Border.all(color: _rankColor(rank), width: 1.5) : null,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          // الصف الأول: الترتيب + الاسم + القسم
          Row(
            children: [
              // ترتيب
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _rankColor(rank),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text('#$rank',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    if (s.department.isNotEmpty)
                      Text(s.department,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              // نسبة الإنجاز
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: rateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${s.completionRate.toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: rateColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // الصف الثاني: إحصائيات
          Row(
            children: [
              _miniStat('الإجمالي', '${s.total}', const Color(0xFF3B82F6)),
              _miniStat('مكتملة', '${s.done}', const Color(0xFF4CAF50)),
              _miniStat('تنفيذ', '${s.progress}', const Color(0xFFFF9800)),
              _miniStat('ملغية', '${s.cancelled}', const Color(0xFFE53935)),
              _miniStat('المتوسط', s.done > 0 ? s.avgHoursFormatted : '-',
                  const Color(0xFF9C27B0)),
            ],
          ),

          // شريط التقدم
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: s.total > 0 ? s.done / s.total : 0,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(rateColor),
              minHeight: 6,
            ),
          ),

          // المبلغ
          if (s.totalAmount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.payments_outlined,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Text('${s.totalAmount.toStringAsFixed(0)} د.ع',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          Text(label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Color _rankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // ذهبي
      case 2:
        return const Color(0xFFC0C0C0); // فضي
      case 3:
        return const Color(0xFFCD7F32); // برونزي
      default:
        return const Color(0xFF9CA3AF);
    }
  }
}

/// بيانات أداء فني
class _TechStat {
  final String name;
  final String department;
  int total = 0;
  int open = 0;
  int progress = 0;
  int done = 0;
  int cancelled = 0;
  int totalMinutes = 0;
  double totalAmount = 0;

  _TechStat({required this.name, required this.department});

  double get completionRate => total > 0 ? (done * 100 / total) : 0;
  double get avgMinutes => done > 0 ? totalMinutes / done : double.infinity;

  String get avgHoursFormatted {
    if (done == 0) return '-';
    final avg = totalMinutes / done;
    if (avg < 60) return '${avg.toStringAsFixed(0)}د';
    final h = (avg / 60).floor();
    final m = (avg % 60).round();
    return '$hس${m > 0 ? ' $mد' : ''}';
  }
}
