/// تبويب FTTH — بيانات المشغل وملخص العمليات
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/employee_profile_service.dart';

class FtthTab extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String? ftthUsername;

  const FtthTab({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.ftthUsername,
  });

  @override
  State<FtthTab> createState() => _FtthTabState();
}

class _FtthTabState extends State<FtthTab> {
  final _service = EmployeeProfileService.instance;
  bool _loading = true;
  Map<String, dynamic> _summary = {};

  static const _accent = Color(0xFF3498DB);
  static const _green = Color(0xFF27AE60);
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
      final data = await _service.getFtthOperatorSummary(widget.employeeId);
      setState(() {
        _summary = data ?? {};
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _operatorInfo(),
          const SizedBox(height: 16),
          _statsRow(),
          const SizedBox(height: 16),
          _activitySection(),
        ],
      ),
    );
  }

  Widget _operatorInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.router, color: _accent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('مشغل FTTH',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.person, size: 14, color: _gray),
                    const SizedBox(width: 4),
                    Text(
                      'اسم المستخدم: ${widget.ftthUsername ?? "غير مربوط"}',
                      style: GoogleFonts.cairo(fontSize: 12, color: _gray),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.ftthUsername != null
                  ? _green.withOpacity(0.15)
                  : _orange.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.ftthUsername != null ? 'مربوط' : 'غير مربوط',
              style: GoogleFonts.cairo(
                color: widget.ftthUsername != null ? _green : _orange,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 20),
            color: _accent,
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    final totalOps =
        _summary['totalOperations'] ?? _summary['TotalOperations'] ?? 0;
    final successOps = _summary['successfulOperations'] ??
        _summary['SuccessfulOperations'] ??
        0;
    final pendingOps =
        _summary['pendingOperations'] ?? _summary['PendingOperations'] ?? 0;
    final totalCharges = _summary['totalCharges'] ??
        _summary['TotalCharges'] ??
        _summary['techTotalCharges'] ??
        0;

    return Row(
      children: [
        _statCard('إجمالي العمليات', totalOps, _accent, Icons.build),
        const SizedBox(width: 12),
        _statCard('ناجحة', successOps, _green, Icons.check_circle),
        const SizedBox(width: 12),
        _statCard('معلقة', pendingOps, _orange, Icons.hourglass_empty),
        const SizedBox(width: 12),
        _statCard('إجمالي الرسوم', totalCharges, _purple, Icons.payments),
      ],
    );
  }

  Widget _statCard(String label, dynamic value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
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
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              value.toString(),
              style: GoogleFonts.cairo(
                  fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
            Text(label, style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
          ],
        ),
      ),
    );
  }

  Widget _activitySection() {
    final activities = _summary['recentActivity'] ?? _summary['RecentActivity'];
    final actList = activities is List
        ? activities.cast<Map<String, dynamic>>()
        : <Map<String, dynamic>>[];

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
                const Icon(Icons.history, color: _accent, size: 20),
                const SizedBox(width: 8),
                Text('آخر العمليات',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
          if (actList.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Center(
                child: Text('لا توجد عمليات حديثة',
                    style: GoogleFonts.cairo(color: _gray)),
              ),
            )
          else
            ...actList.take(10).map((a) {
              final type = a['type'] ?? a['Type'] ?? '';
              final desc = a['description'] ?? a['Description'] ?? '';
              final dateStr = a['date'] ?? a['Date'] ?? a['createdAt'] ?? '';

              return ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: _accent.withOpacity(0.15),
                  child: const Icon(Icons.build, size: 16, color: _accent),
                ),
                title: Text(type.toString(),
                    style: GoogleFonts.cairo(fontSize: 13)),
                subtitle: Text(desc.toString(),
                    style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
                trailing: Text(_formatDate(dateStr.toString()),
                    style: GoogleFonts.cairo(fontSize: 10, color: _gray)),
              );
            }),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
