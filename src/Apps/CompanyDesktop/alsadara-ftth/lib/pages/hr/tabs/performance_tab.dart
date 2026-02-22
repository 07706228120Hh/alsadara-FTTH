/// تبويب التقييم — تقييم أداء الموظف بناءً على المهام والحضور والمعاملات
/// يحسب نسبة الإنجاز + الالتزام + تقييم نجومي
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/employee_profile_service.dart';

class PerformanceTab extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const PerformanceTab({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<PerformanceTab> {
  final _service = EmployeeProfileService.instance;
  bool _loading = true;

  // بيانات محسوبة
  int _totalTasks = 0;
  int _completedTasks = 0;
  int _attendanceDays = 0;
  int _absentDays = 0;
  int _lateDays = 0;
  int _totalAudits = 0;
  int _goodAudits = 0;

  static const _accent = Color(0xFF3498DB);
  static const _green = Color(0xFF27AE60);
  static const _red = Color(0xFFE74C3C);
  static const _orange = Color(0xFFF39C12);
  static const _purple = Color(0xFF8E44AD);
  static const _gray = Color(0xFF95A5A6);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();

      // تحميل المهام
      final tasks = await _service.getEmployeeTasks(widget.employeeId);
      _totalTasks = tasks.length;
      _completedTasks = tasks.where((t) {
        final s = (t['status'] ?? t['Status'] ?? '').toString().toLowerCase();
        return s == 'completed' || s == 'done';
      }).length;

      // تحميل الحضور للشهر الحالي
      final attendance = await _service.getMonthlyAttendance(
          widget.employeeId, now.month, now.year);
      for (final r in attendance) {
        final s = (r['status'] ?? r['Status'] ?? '').toString().toLowerCase();
        if (s == 'present' || s == 'حاضر') {
          _attendanceDays++;
        } else if (s == 'absent' || s == 'غائب') {
          _absentDays++;
        } else if (s == 'late' || s == 'متأخر') {
          _lateDays++;
        }
      }

      // تحميل التدقيقات
      final audits = await _service.getTaskAudits(widget.employeeId);
      _totalAudits = audits.length;
      _goodAudits = audits.where((a) {
        final rating =
            (a['rating'] ?? a['Rating'] ?? '').toString().toLowerCase();
        return rating == 'good' ||
            rating == 'excellent' ||
            rating == 'جيد' ||
            rating == 'ممتاز';
      }).length;
    } catch (_) {}
    setState(() => _loading = false);
  }

  double get _taskCompletion =>
      _totalTasks > 0 ? _completedTasks / _totalTasks : 0;

  double get _attendanceRate {
    final total = _attendanceDays + _absentDays + _lateDays;
    return total > 0 ? _attendanceDays / total : 0;
  }

  double get _auditScore => _totalAudits > 0 ? _goodAudits / _totalAudits : 0;

  double get _overallScore =>
      (_taskCompletion * 0.4 + _attendanceRate * 0.35 + _auditScore * 0.25);

  int get _stars => (_overallScore * 5).round().clamp(0, 5);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _overallCard(),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: _metricCard('إنجاز المهام', _taskCompletion, _green,
                      Icons.task_alt, '$_completedTasks / $_totalTasks')),
              const SizedBox(width: 16),
              Expanded(
                  child: _metricCard('الالتزام بالحضور', _attendanceRate,
                      _accent, Icons.fingerprint, '$_attendanceDays يوم حضور')),
              const SizedBox(width: 16),
              Expanded(
                  child: _metricCard('جودة العمل', _auditScore, _purple,
                      Icons.verified, '$_goodAudits / $_totalAudits تدقيق')),
            ],
          ),
          const SizedBox(height: 20),
          _breakdownCard(),
        ],
      ),
    );
  }

  Widget _overallCard() {
    final score = (_overallScore * 100).round();
    final Color scoreColor;
    final String evalText;

    if (score >= 80) {
      scoreColor = _green;
      evalText = 'أداء ممتاز';
    } else if (score >= 60) {
      scoreColor = _accent;
      evalText = 'أداء جيد';
    } else if (score >= 40) {
      scoreColor = _orange;
      evalText = 'أداء متوسط';
    } else {
      scoreColor = _red;
      evalText = 'يحتاج تحسين';
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scoreColor.withOpacity(0.08),
            Colors.white,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
        border: Border.all(color: scoreColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Score circle
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: _overallScore,
                  strokeWidth: 8,
                  backgroundColor: Colors.grey.shade200,
                  color: scoreColor,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score%',
                      style: GoogleFonts.cairo(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('التقييم العام',
                    style: GoogleFonts.cairo(fontSize: 12, color: _gray)),
                Text(evalText,
                    style: GoogleFonts.cairo(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: scoreColor)),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(5, (i) {
                    return Icon(
                      i < _stars ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 28,
                    );
                  }),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadAll,
            icon: const Icon(Icons.refresh),
            color: _accent,
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, double progress, Color color, IconData icon,
      String detail) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(title,
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 12),
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: Colors.grey.shade200,
                  color: color,
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold, fontSize: 16, color: color),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(detail, style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
        ],
      ),
    );
  }

  Widget _breakdownCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.analytics, color: _accent, size: 20),
                const SizedBox(width: 8),
                Text('تفصيل التقييم',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          _breakdownRow('إنجاز المهام', '40%', _taskCompletion, _green),
          _breakdownRow('الالتزام بالحضور', '35%', _attendanceRate, _accent),
          _breakdownRow('جودة العمل (تدقيق)', '25%', _auditScore, _purple),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: _gray),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'التقييم يُحسب تلقائياً: 40% مهام + 35% حضور + 25% تدقيق',
                    style: GoogleFonts.cairo(fontSize: 10, color: _gray),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _breakdownRow(
      String label, String weight, double progress, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: GoogleFonts.cairo(fontSize: 12)),
          ),
          Text(weight, style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('${(progress * 100).round()}%',
              style: GoogleFonts.cairo(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
