/// تبويب الرواتب — سجل الرواتب والخصومات والحوافز
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/employee_profile_service.dart';

class SalaryTab extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final dynamic baseSalary;
  final bool canEdit;

  const SalaryTab({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.baseSalary,
    required this.canEdit,
  });

  @override
  State<SalaryTab> createState() => _SalaryTabState();
}

class _SalaryTabState extends State<SalaryTab> {
  final _service = EmployeeProfileService.instance;
  bool _loading = true;
  List<Map<String, dynamic>> _salaries = [];

  static const _accent = Color(0xFF3498DB);
  static const _green = Color(0xFF27AE60);
  static const _red = Color(0xFFE74C3C);
  static const _gray = Color(0xFF95A5A6);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getSalaries(widget.employeeId);
      setState(() {
        _salaries = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _overviewCards(),
          const SizedBox(height: 16),
          _salaryHistory(),
        ],
      ),
    );
  }

  Widget _overviewCards() {
    final base = _parseDouble(widget.baseSalary);
    double totalPaid = 0;
    double totalDeductions = 0;
    double totalBonuses = 0;

    for (final s in _salaries) {
      totalPaid +=
          _parseDouble(s['netAmount'] ?? s['NetAmount'] ?? s['amount'] ?? 0);
      totalDeductions += _parseDouble(s['deductions'] ?? s['Deductions'] ?? 0);
      totalBonuses += _parseDouble(s['bonuses'] ?? s['Bonuses'] ?? 0);
    }

    return Row(
      children: [
        _infoCard('الراتب الأساسي', base, _accent, Icons.payments),
        const SizedBox(width: 12),
        _infoCard(
            'إجمالي المدفوع', totalPaid, _green, Icons.account_balance_wallet),
        const SizedBox(width: 12),
        _infoCard(
            'إجمالي الخصومات', totalDeductions, _red, Icons.remove_circle),
        const SizedBox(width: 12),
        _infoCard(
            'إجمالي الحوافز', totalBonuses, Colors.amber.shade700, Icons.star),
      ],
    );
  }

  Widget _infoCard(String label, double value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(height: 8),
            Text(
              _formatCurrency(value),
              style: GoogleFonts.cairo(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            Text(label, style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
          ],
        ),
      ),
    );
  }

  Widget _salaryHistory() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                Text('سجل الرواتب',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                  color: _accent,
                ),
              ],
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator(color: _accent)),
            )
          else if (_salaries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.payment,
                        size: 48, color: _gray.withOpacity(0.5)),
                    const SizedBox(height: 8),
                    Text('لا توجد سجلات رواتب',
                        style: GoogleFonts.cairo(color: _gray)),
                  ],
                ),
              ),
            )
          else
            ..._salaries.map((s) => _salaryRow(s)),
        ],
      ),
    );
  }

  Widget _salaryRow(Map<String, dynamic> s) {
    final month = s['month'] ?? s['Month'] ?? s['period'] ?? '';
    final net =
        _parseDouble(s['netAmount'] ?? s['NetAmount'] ?? s['amount'] ?? 0);
    final deductions = _parseDouble(s['deductions'] ?? s['Deductions'] ?? 0);
    final bonuses = _parseDouble(s['bonuses'] ?? s['Bonuses'] ?? 0);
    final status = (s['status'] ?? s['Status'] ?? 'paid').toString();
    final isPaid = status.toLowerCase() == 'paid' || status == 'مدفوع';
    final paidDate = s['paidAt'] ?? s['PaidAt'] ?? s['paidDate'] ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          // الشهر
          SizedBox(
            width: 120,
            child: Text(month.toString(),
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          // صافي
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatCurrency(net),
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: _green)),
                Row(
                  children: [
                    if (deductions > 0)
                      Text('خصم: ${_formatCurrency(deductions)}  ',
                          style: GoogleFonts.cairo(fontSize: 10, color: _red)),
                    if (bonuses > 0)
                      Text('حافز: ${_formatCurrency(bonuses)}',
                          style: GoogleFonts.cairo(
                              fontSize: 10, color: Colors.amber.shade700)),
                  ],
                ),
              ],
            ),
          ),
          // الحالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: (isPaid ? _green : _red).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isPaid ? 'مدفوع' : 'معلق',
              style: GoogleFonts.cairo(
                  color: isPaid ? _green : _red,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          // تاريخ الدفع
          if (paidDate.toString().isNotEmpty)
            Text(_formatDate(paidDate.toString()),
                style: GoogleFonts.cairo(fontSize: 10, color: _gray)),
        ],
      ),
    );
  }

  double _parseDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _formatCurrency(double v) {
    return '${v.round()} د.ع';
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
