/// تبويب الحضور — مرتبط بنظام البصمة
/// يعرض: سجل الحضور الشهري، إحصائيات، تقويم بصري
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/employee_profile_service.dart';

class AttendanceTab extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const AttendanceTab({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  final _service = EmployeeProfileService.instance;
  bool _loading = true;
  List<Map<String, dynamic>> _records = [];
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  static const _accent = Color(0xFF3498DB);
  static const _green = Color(0xFF27AE60);
  static const _red = Color(0xFFE74C3C);
  static const _orange = Color(0xFFF39C12);
  static const _gray = Color(0xFF95A5A6);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getMonthlyAttendance(
        widget.employeeId,
        _selectedMonth,
        _selectedYear,
      );
      setState(() {
        _records = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmall = screenWidth < 500;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isSmall ? 10 : 20),
      child: Column(
        children: [
          _monthSelector(),
          const SizedBox(height: 16),
          _statsCards(),
          const SizedBox(height: 16),
          _attendanceTable(),
        ],
      ),
    );
  }

  Widget _monthSelector() {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                if (_selectedMonth == 1) {
                  _selectedMonth = 12;
                  _selectedYear--;
                } else {
                  _selectedMonth--;
                }
              });
              _load();
            },
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 12),
          Text(
            '${months[_selectedMonth - 1]} $_selectedYear',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.bold, fontSize: 16, color: _accent),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () {
              setState(() {
                if (_selectedMonth == 12) {
                  _selectedMonth = 1;
                  _selectedYear++;
                } else {
                  _selectedMonth++;
                }
              });
              _load();
            },
            icon: const Icon(Icons.chevron_left),
          ),
        ],
      ),
    );
  }

  Widget _statsCards() {
    int present = 0, absent = 0, late = 0, leave = 0;
    for (final r in _records) {
      final status =
          (r['status'] ?? r['Status'] ?? '').toString().toLowerCase();
      if (status == 'present' || status == 'حاضر') {
        present++;
      } else if (status == 'absent' || status == 'غائب') {
        absent++;
      } else if (status == 'late' || status == 'متأخر') {
        late++;
      } else if (status == 'leave' || status == 'إجازة') {
        leave++;
      }
    }

    final isSmall = MediaQuery.of(context).size.width < 500;
    if (isSmall) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: (MediaQuery.of(context).size.width - 28) / 2,
            child: _statCard('حاضر', present, _green, Icons.check_circle),
          ),
          SizedBox(
            width: (MediaQuery.of(context).size.width - 28) / 2,
            child: _statCard('غائب', absent, _red, Icons.cancel),
          ),
          SizedBox(
            width: (MediaQuery.of(context).size.width - 28) / 2,
            child: _statCard('متأخر', late, _orange, Icons.access_time),
          ),
          SizedBox(
            width: (MediaQuery.of(context).size.width - 28) / 2,
            child: _statCard('إجازة', leave, _gray, Icons.event_busy),
          ),
        ],
      );
    }
    return Row(
      children: [
        _statCard('حاضر', present, _green, Icons.check_circle),
        const SizedBox(width: 12),
        _statCard('غائب', absent, _red, Icons.cancel),
        const SizedBox(width: 12),
        _statCard('متأخر', late, _orange, Icons.access_time),
        const SizedBox(width: 12),
        _statCard('إجازة', leave, _gray, Icons.event_busy),
      ],
    );
  }

  Widget _statCard(String label, int count, Color color, IconData icon) {
    final isSmall = MediaQuery.of(context).size.width < 500;
    final card = Container(
      padding: EdgeInsets.all(isSmall ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
        border: Border(bottom: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: GoogleFonts.cairo(
                fontSize: 22, fontWeight: FontWeight.bold, color: color),
          ),
          Text(label,
              style: GoogleFonts.cairo(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
    if (isSmall) return card;
    return Expanded(child: card);
  }

  Widget _attendanceTable() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }

    if (_records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            const Icon(Icons.event_busy, size: 48, color: _gray),
            const SizedBox(height: 8),
            Text('لا توجد بيانات حضور لهذا الشهر',
                style: GoogleFonts.cairo(color: _gray)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
          headingRowColor: WidgetStateProperty.all(_accent.withOpacity(0.1)),
          columnSpacing: MediaQuery.of(context).size.width < 500 ? 10 : 20,
          columns: [
            DataColumn(
                label: Text('التاريخ',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('الحالة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('وقت الحضور',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('وقت الانصراف',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
            DataColumn(
                label: Text('ملاحظات',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
          ],
          rows: _records.map((r) {
            final status = (r['status'] ?? r['Status'] ?? '').toString();
            final statusColor = _getStatusColor(status);
            return DataRow(cells: [
              DataCell(Text(
                _formatDate(r['date'] ?? r['Date'] ?? ''),
                style: GoogleFonts.cairo(fontSize: 12),
              )),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _getStatusLabel(status),
                  style: GoogleFonts.cairo(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              )),
              DataCell(Text(
                r['checkIn'] ?? r['CheckIn'] ?? r['checkInTime'] ?? '—',
                style: GoogleFonts.cairo(fontSize: 12),
              )),
              DataCell(Text(
                r['checkOut'] ?? r['CheckOut'] ?? r['checkOutTime'] ?? '—',
                style: GoogleFonts.cairo(fontSize: 12),
              )),
              DataCell(Text(
                r['notes'] ?? r['Notes'] ?? '',
                style: GoogleFonts.cairo(fontSize: 12, color: _gray),
              )),
            ]);
          }).toList(),
        ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s == 'present' || s == 'حاضر') return _green;
    if (s == 'absent' || s == 'غائب') return _red;
    if (s == 'late' || s == 'متأخر') return _orange;
    return _gray;
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return 'حاضر';
      case 'absent':
        return 'غائب';
      case 'late':
        return 'متأخر';
      case 'leave':
        return 'إجازة';
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
