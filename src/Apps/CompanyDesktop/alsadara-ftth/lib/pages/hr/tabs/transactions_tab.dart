/// تبويب المعاملات المالية — تحصيلات ومدفوعات الفني
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../services/employee_profile_service.dart';

class TransactionsTab extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String role;
  final bool canAdd;

  const TransactionsTab({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.role,
    required this.canAdd,
  });

  @override
  State<TransactionsTab> createState() => _TransactionsTabState();
}

class _TransactionsTabState extends State<TransactionsTab> {
  final _service = EmployeeProfileService.instance;
  bool _loading = true;
  List<Map<String, dynamic>> _transactions = [];
  String _filter = 'all'; // all, charge, payment

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
      final data = await _service.getTechnicianTransactions(widget.employeeId);
      setState(() {
        _transactions = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return _transactions;
    return _transactions.where((t) {
      final type = (t['type'] ?? t['Type'] ?? '').toString().toLowerCase();
      if (_filter == 'charge') {
        return type.contains('charge') || type.contains('تحصيل');
      }
      return type.contains('payment') || type.contains('دفع');
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _summaryBar(),
        const SizedBox(height: 4),
        _filterBar(),
        const SizedBox(height: 4),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _accent))
              : _transactionsList(),
        ),
      ],
    );
  }

  Widget _summaryBar() {
    double totalCharges = 0;
    double totalPayments = 0;

    for (final t in _transactions) {
      final type = (t['type'] ?? t['Type'] ?? '').toString().toLowerCase();
      final amount = _parseDouble(t['amount'] ?? t['Amount'] ?? 0);
      if (type.contains('charge') || type.contains('تحصيل')) {
        totalCharges += amount;
      } else {
        totalPayments += amount;
      }
    }
    final balance = totalCharges - totalPayments;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          _summaryCard('التحصيلات', totalCharges, _green, Icons.arrow_downward),
          const SizedBox(width: 12),
          _summaryCard('المدفوعات', totalPayments, _red, Icons.arrow_upward),
          const SizedBox(width: 12),
          _summaryCard(
            'الرصيد',
            balance,
            balance >= 0 ? _green : _red,
            Icons.account_balance_wallet,
          ),
          const SizedBox(width: 12),
          _summaryCard('عدد العمليات', _transactions.length.toDouble(), _accent,
              Icons.receipt_long),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, double val, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
          ],
          border: Border(bottom: BorderSide(color: color, width: 3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              _formatCurrency(val),
              style: GoogleFonts.cairo(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
            Text(label, style: GoogleFonts.cairo(fontSize: 10, color: _gray)),
          ],
        ),
      ),
    );
  }

  Widget _filterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _chipBtn('الكل', 'all'),
          const SizedBox(width: 8),
          _chipBtn('تحصيلات', 'charge'),
          const SizedBox(width: 8),
          _chipBtn('مدفوعات', 'payment'),
          const Spacer(),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: _accent, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _chipBtn(String label, String val) {
    final selected = _filter == val;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: _accent,
      labelStyle: GoogleFonts.cairo(
          color: selected ? Colors.white : Colors.black87, fontSize: 11),
      onSelected: (_) => setState(() => _filter = val),
    );
  }

  Widget _transactionsList() {
    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 48, color: _gray.withOpacity(0.5)),
            const SizedBox(height: 8),
            Text('لا توجد معاملات', style: GoogleFonts.cairo(color: _gray)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: items.length,
      itemBuilder: (ctx, i) => _txCard(items[i]),
    );
  }

  Widget _txCard(Map<String, dynamic> tx) {
    final type = (tx['type'] ?? tx['Type'] ?? '').toString();
    final isCharge =
        type.toLowerCase().contains('charge') || type.contains('تحصيل');
    final amount = _parseDouble(tx['amount'] ?? tx['Amount'] ?? 0);
    final desc = tx['description'] ?? tx['Description'] ?? tx['notes'] ?? '';
    final date = tx['createdAt'] ?? tx['CreatedAt'] ?? tx['date'] ?? '';
    final customer = tx['customerName'] ?? tx['CustomerName'] ?? '';
    final receivedBy = tx['receivedBy'] ?? tx['ReceivedBy'] ?? '';
    final color = isCharge ? _green : _red;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
        ],
        border: Border(right: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          // أيقونة
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(
              isCharge ? Icons.arrow_downward : Icons.arrow_upward,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // التفاصيل
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCharge ? 'تحصيل' : 'دفعة',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (customer.toString().isNotEmpty)
                  Text('العميل: $customer',
                      style: GoogleFonts.cairo(fontSize: 11, color: _gray)),
                if (desc.toString().isNotEmpty)
                  Text(desc.toString(),
                      style: GoogleFonts.cairo(fontSize: 11, color: _gray),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // المبلغ
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isCharge ? '+' : '-'}${_formatCurrency(amount)}',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 14, color: color),
              ),
              Text(_formatDate(date.toString()),
                  style: GoogleFonts.cairo(fontSize: 10, color: _gray)),
            ],
          ),
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
    return '${v.abs().round()} د.ع';
  }

  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
