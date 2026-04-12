import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
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

  /// تجميع بيانات الفنيين
  List<_TechStat> _buildStats() {
    final map = <String, _TechStat>{};
    for (final t in widget.tasks) {
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

    return Scaffold(
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
      body: stats.isEmpty
          ? const Center(
              child: Text('لا توجد بيانات',
                  style: TextStyle(fontSize: 16, color: Colors.grey)))
          : SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? 10 : 20),
              child: Column(
                children: [
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
    );
  }

  /// رسم بياني شريطي لمقارنة الفنيين
  Widget _buildChart(List<_TechStat> stats, bool isMobile) {
    final top = stats.take(8).toList();
    final maxVal =
        top.fold<int>(0, (m, s) => s.total > m ? s.total : m).toDouble();

    return Container(
      height: isMobile ? 200 : 280,
      padding: EdgeInsets.all(isMobile ? 10 : 16),
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
          Text('مقارنة الفنيين',
              style: TextStyle(
                  fontSize: isMobile ? 14 : 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          // مفتاح الألوان
          Wrap(
            spacing: 12,
            children: [
              _legendDot('مكتملة', const Color(0xFF4CAF50)),
              _legendDot('تنفيذ', const Color(0xFFFF9800)),
              _legendDot('مفتوحة', const Color(0xFF2196F3)),
              _legendDot('ملغية', const Color(0xFFE53935)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.2,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, gIdx, rod, rIdx) {
                      final s = top[group.x];
                      return BarTooltipItem(
                        '${s.name}\nمكتملة: ${s.done} | تنفيذ: ${s.progress}',
                        const TextStyle(fontSize: 11, color: Colors.white),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= top.length) return const SizedBox.shrink();
                        final name = top[idx].name;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            name.length > 6
                                ? '${name.substring(0, 6)}..'
                                : name,
                            style: TextStyle(
                                fontSize: isMobile ? 9 : 11,
                                fontWeight: FontWeight.w600),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                      sideTitles:
                          SideTitles(showTitles: !isMobile, reservedSize: 30)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: !isMobile),
                borderData: FlBorderData(show: false),
                barGroups: top.asMap().entries.map((e) {
                  final s = e.value;
                  final w = isMobile ? 6.0 : 10.0;
                  final r =
                      const BorderRadius.vertical(top: Radius.circular(3));
                  return BarChartGroupData(x: e.key, barsSpace: 2, barRods: [
                    BarChartRodData(
                        toY: s.done.toDouble(),
                        width: w,
                        borderRadius: r,
                        color: const Color(0xFF4CAF50)),
                    BarChartRodData(
                        toY: s.progress.toDouble(),
                        width: w,
                        borderRadius: r,
                        color: const Color(0xFFFF9800)),
                    BarChartRodData(
                        toY: s.open.toDouble(),
                        width: w,
                        borderRadius: r,
                        color: const Color(0xFF2196F3)),
                    BarChartRodData(
                        toY: s.cancelled.toDouble(),
                        width: w,
                        borderRadius: r,
                        color: const Color(0xFFE53935)),
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
