/// صفحة عرض جميع عمليات مشغل معين من لوحة تحكم FTTH
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// نموذج بسيط لعملية مشغل
class _OpTransaction {
  final String id;
  final String type;
  final double amount;
  final String subscriptionId;
  final String customerName;
  final String customerId;
  final String planName;
  final String occuredAt;
  final String createdBy;
  final String zoneId;
  final String deviceUsername;
  final String auditCreator;

  _OpTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.subscriptionId = '',
    this.customerName = '',
    this.customerId = '',
    this.planName = '',
    this.occuredAt = '',
    this.createdBy = '',
    this.zoneId = '',
    this.deviceUsername = '',
    this.auditCreator = '',
  });
}

/// صفحة عمليات المشغل
class FtthOperatorTransactionsPage extends StatefulWidget {
  final String operatorName;
  final List<Map<String, dynamic>> transactions;
  final int attributedOps;

  const FtthOperatorTransactionsPage({
    super.key,
    required this.operatorName,
    required this.transactions,
    this.attributedOps = 0,
  });

  @override
  State<FtthOperatorTransactionsPage> createState() =>
      _FtthOperatorTransactionsPageState();
}

class _FtthOperatorTransactionsPageState
    extends State<FtthOperatorTransactionsPage> {
  final _currencyFormat = NumberFormat('#,###', 'ar');
  late List<_OpTransaction> _allTransactions;
  late List<_OpTransaction> _filtered;
  String _searchQuery = '';
  String _sortBy = 'date';
  bool _isAscending = false;
  String _selectedCategory = 'الكل';
  bool _fiberOnly = true; // إظهار باقات Fiber فقط افتراضياً
  final _searchController = TextEditingController();

  // إحصائيات
  double _totalAmount = 0;
  double _positiveAmount = 0;
  double _negativeAmount = 0;
  Map<String, int> _typeCounts = {};

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _initData() {
    _allTransactions = widget.transactions.map((tx) {
      final amtVal = tx['amount'] ?? 0.0;
      final double amount =
          (amtVal is num) ? amtVal.toDouble() : double.tryParse('$amtVal') ?? 0;
      return _OpTransaction(
        id: tx['id']?.toString() ?? '',
        type: tx['type']?.toString() ?? '',
        amount: amount,
        subscriptionId: tx['subscriptionId']?.toString() ?? '',
        customerName: tx['customerName']?.toString() ?? '',
        customerId: tx['customerId']?.toString() ?? '',
        planName: tx['planName']?.toString() ?? '',
        occuredAt: tx['occuredAt']?.toString() ?? '',
        createdBy: tx['createdBy']?.toString() ?? '',
        zoneId: tx['zoneId']?.toString() ?? '',
        deviceUsername: tx['deviceUsername']?.toString() ?? '',
        auditCreator: tx['auditCreator']?.toString() ?? '',
      );
    }).toList();

    _applyFilters();
    _calculateStats();
  }

  void _calculateStats() {
    _totalAmount = 0;
    _positiveAmount = 0;
    _negativeAmount = 0;
    _typeCounts = {};

    for (final tx in _filtered) {
      _totalAmount += tx.amount;
      if (tx.amount >= 0) {
        _positiveAmount += tx.amount;
      } else {
        _negativeAmount += tx.amount;
      }
      _typeCounts[tx.type] = (_typeCounts[tx.type] ?? 0) + 1;
    }
  }

  void _applyFilters() {
    _filtered = List.from(_allTransactions);

    // فلتر البحث
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      _filtered = _filtered.where((tx) {
        return tx.customerName.toLowerCase().contains(q) ||
            tx.planName.toLowerCase().contains(q) ||
            tx.customerId.toLowerCase().contains(q) ||
            tx.subscriptionId.toLowerCase().contains(q) ||
            tx.deviceUsername.toLowerCase().contains(q) ||
            _translateType(tx.type).contains(q) ||
            tx.type.toLowerCase().contains(q);
      }).toList();
    }

    // فلتر Fiber فقط
    if (_fiberOnly) {
      _filtered = _filtered.where((tx) {
        return tx.planName.toLowerCase().contains('fiber');
      }).toList();
    }

    // فلتر التصنيف
    if (_selectedCategory != 'الكل') {
      _filtered = _filtered.where((tx) {
        return _categorizeArabic(tx.type) == _selectedCategory;
      }).toList();
    }

    // الترتيب
    _filtered.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'amount':
          cmp = a.amount.abs().compareTo(b.amount.abs());
          break;
        case 'type':
          cmp = a.type.compareTo(b.type);
          break;
        case 'customer':
          cmp = a.customerName.compareTo(b.customerName);
          break;
        case 'date':
        default:
          cmp = a.occuredAt.compareTo(b.occuredAt);
      }
      return _isAscending ? cmp : -cmp;
    });

    _calculateStats();
  }

  static String _categorizeType(String type) {
    const sub = {
      'PLAN_PURCHASE',
      'PLAN_RENEW',
      'PLAN_CHANGE',
      'PLAN_SUBSCRIBE',
      'AUTO_RENEW',
      'PLAN_SCHEDULE',
      'SCHEDULE_CHANGE',
      'PLAN_EMI_RENEW',
      'PurchaseSubscriptionFromTrial',
    };
    const comm = {
      'PURCHASE_COMMISSION',
      'CASHBACK_COMMISSION',
      'MAINTENANCE_COMMISSION',
      'HIERACHY_COMMISSION',
      'WALLET_TRANSFER_COMMISSION',
      'COMMISSION_TRANSFER',
    };
    const rev = {
      'PURCHASE_REVERSAL',
      'PURCH_COMM_REVERSAL',
      'RENEW_REVERSAL',
      'HIER_COMM_REVERSAL',
      'MAINT_COMM_REVERSAL',
      'WALLET_REVERSAL',
    };
    const wal = {
      'WALLET_TOPUP',
      'WALLET_REFUND',
      'WALLET_TRANSFER',
      'WALLET_TRANSFER_FEE',
    };
    if (sub.contains(type)) return 'subscription';
    if (comm.contains(type)) return 'commission';
    if (rev.contains(type)) return 'reversal';
    if (wal.contains(type)) return 'wallet';
    return 'other';
  }

  static String _categorizeArabic(String type) {
    switch (_categorizeType(type)) {
      case 'subscription':
        return 'اشتراكات';
      case 'commission':
        return 'عمولات';
      case 'reversal':
        return 'عكس/ارتجاع';
      case 'wallet':
        return 'محفظة';
      default:
        return 'أخرى';
    }
  }

  static String _translateType(String type) {
    const map = {
      'PLAN_PURCHASE': 'شراء باقة',
      'PLAN_RENEW': 'تجديد',
      'PLAN_CHANGE': 'تغيير باقة',
      'PLAN_SUBSCRIBE': 'اشتراك',
      'AUTO_RENEW': 'تجديد تلقائي',
      'PLAN_SCHEDULE': 'جدولة',
      'SCHEDULE_CHANGE': 'تغيير جدولة',
      'PLAN_EMI_RENEW': 'تجديد قسط',
      'PURCHASE_COMMISSION': 'عمولة شراء',
      'CASHBACK_COMMISSION': 'عمولة استرداد',
      'MAINTENANCE_COMMISSION': 'عمولة صيانة',
      'HIERACHY_COMMISSION': 'عمولة هرمية',
      'WALLET_TRANSFER_COMMISSION': 'عمولة تحويل',
      'COMMISSION_TRANSFER': 'تحويل عمولة',
      'PURCHASE_REVERSAL': 'عكس شراء',
      'PURCH_COMM_REVERSAL': 'عكس عمولة شراء',
      'RENEW_REVERSAL': 'عكس تجديد',
      'HIER_COMM_REVERSAL': 'عكس عمولة هرمية',
      'MAINT_COMM_REVERSAL': 'عكس عمولة صيانة',
      'WALLET_REVERSAL': 'عكس محفظة',
      'WALLET_TOPUP': 'شحن محفظة',
      'WALLET_REFUND': 'استرداد محفظة',
      'WALLET_TRANSFER': 'تحويل محفظة',
      'WALLET_TRANSFER_FEE': 'رسوم تحويل',
      'BAL_CARD_SELL': 'بيع بطاقة',
      'CASHOUT': 'سحب نقدي',
      'HARDWARE_SELL': 'بيع أجهزة',
      'TERMINATE': 'إنهاء',
      'TERMINATE_SUBSCRIPTION': 'إنهاء اشتراك',
      'SCHEDULE_CANCEL': 'إلغاء جدولة',
      'TRIAL_PERIOD': 'فترة تجريبية',
      'PLAN_SUSPEND': 'تعليق',
      'PLAN_REACTIVATE': 'إعادة تفعيل',
      'REFILL_TEAM_MEMBER_BALANCE': 'تعبئة رصيد فريق',
      'PurchaseSubscriptionFromTrial': 'شراء من تجربة',
    };
    return map[type] ?? type;
  }

  Color _categoryColor(String cat) {
    switch (cat) {
      case 'subscription':
      case 'اشتراكات':
        return Colors.teal;
      case 'commission':
      case 'عمولات':
        return Colors.purple;
      case 'reversal':
      case 'عكس/ارتجاع':
        return Colors.orange;
      case 'wallet':
      case 'محفظة':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String isoDate) {
    if (isoDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return DateFormat('yyyy/MM/dd  HH:mm').format(dt);
    } catch (_) {
      return isoDate;
    }
  }

  Future<void> _copyAllToClipboard() async {
    final buf = StringBuffer();
    buf.writeln('عمليات المشغل: ${widget.operatorName}');
    buf.writeln('العدد: ${_filtered.length}');
    buf.writeln('═' * 50);
    for (int i = 0; i < _filtered.length; i++) {
      final tx = _filtered[i];
      buf.writeln(
          '${i + 1}. ${_translateType(tx.type)} | ${tx.customerName} | ${_currencyFormat.format(tx.amount.abs())} د.ع | ${_formatDate(tx.occuredAt)}');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم نسخ جميع العمليات'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      'الكل',
      'اشتراكات',
      'عمولات',
      'عكس/ارتجاع',
      'محفظة',
      'أخرى'
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'عمليات: ${widget.operatorName}',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: 'نسخ الكل',
              onPressed: _copyAllToClipboard,
            ),
          ],
        ),
        body: Column(
          children: [
            // ── بطاقات الإحصائيات ──
            _buildStatsBar(),
            // ── شريط البحث والفلاتر ──
            _buildSearchAndFilters(categories),
            // ── الجدول ──
            Expanded(child: _buildTable()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade50,
      child: Row(
        children: [
          _statCard('الإجمالي', '${_filtered.length}', Colors.teal),
          const SizedBox(width: 8),
          _statCard(
              'السالب',
              '${_currencyFormat.format(_negativeAmount.abs())} د.ع',
              Colors.red),
          const SizedBox(width: 8),
          _statCard('الموجب', '${_currencyFormat.format(_positiveAmount)} د.ع',
              Colors.green),
          if (widget.attributedOps > 0) ...[
            const SizedBox(width: 8),
            _statCard(
                'منسوب تلقائياً', '${widget.attributedOps}', Colors.indigo),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color.shade700,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color.shade800),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(List<String> categories) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
      ),
      child: Column(
        children: [
          // شريط البحث
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'بحث بالعميل، الباقة، النوع...',
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _applyFilters();
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 0),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) {
                      setState(() {
                        _searchQuery = v;
                        _applyFilters();
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // الترتيب
              PopupMenuButton<String>(
                tooltip: 'ترتيب',
                icon: const Icon(Icons.sort, size: 20),
                onSelected: (v) {
                  setState(() {
                    if (_sortBy == v) {
                      _isAscending = !_isAscending;
                    } else {
                      _sortBy = v;
                      _isAscending = v == 'date' ? false : true;
                    }
                    _applyFilters();
                  });
                },
                itemBuilder: (_) => [
                  _sortItem('date', 'التاريخ'),
                  _sortItem('amount', 'المبلغ'),
                  _sortItem('type', 'النوع'),
                  _sortItem('customer', 'العميل'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          // فلتر Fiber + فلاتر التصنيف
          Row(
            children: [
              // زر Fiber فقط
              FilterChip(
                label: Text('Fiber فقط', style: TextStyle(fontSize: 11)),
                selected: _fiberOnly,
                selectedColor: Colors.green.shade100,
                checkmarkColor: Colors.green.shade800,
                onSelected: (v) {
                  setState(() {
                    _fiberOnly = v;
                    _applyFilters();
                  });
                },
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              ),
              const SizedBox(width: 8),
              // فلاتر التصنيف
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final cat = categories[i];
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat, style: TextStyle(fontSize: 11)),
                        selected: isSelected,
                        selectedColor: Colors.teal.shade100,
                        onSelected: (_) {
                          setState(() {
                            _selectedCategory = cat;
                            _applyFilters();
                          });
                        },
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 0),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortItem(String value, String label) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          if (_sortBy == value)
            Icon(
              _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: Colors.teal,
            ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTable() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('لا توجد عمليات',
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 14,
          horizontalMargin: 12,
          headingRowHeight: 36,
          dataRowMinHeight: 40,
          dataRowMaxHeight: 70,
          headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
          columns: const [
            DataColumn(label: Text('#', style: TextStyle(fontSize: 11))),
            DataColumn(label: Text('التاريخ', style: TextStyle(fontSize: 11))),
            DataColumn(label: Text('النوع', style: TextStyle(fontSize: 11))),
            DataColumn(label: Text('العميل', style: TextStyle(fontSize: 11))),
            DataColumn(label: Text('الباقة', style: TextStyle(fontSize: 11))),
            DataColumn(label: Text('المبلغ', style: TextStyle(fontSize: 11))),
            DataColumn(label: Text('المنطقة', style: TextStyle(fontSize: 11))),
            DataColumn(label: Text('ملاحظات', style: TextStyle(fontSize: 11))),
          ],
          rows: _filtered.asMap().entries.map((entry) {
            final i = entry.key;
            final tx = entry.value;
            final catColor = _categoryColor(_categorizeType(tx.type));
            final isAttributed = tx.createdBy.startsWith('⇐');

            return DataRow(
              color: WidgetStateProperty.resolveWith((states) {
                if (isAttributed) return Colors.indigo.shade50;
                if (i.isEven) return Colors.white;
                return Colors.grey.shade50;
              }),
              cells: [
                DataCell(
                    Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                DataCell(Text(_formatDate(tx.occuredAt),
                    style: const TextStyle(fontSize: 10))),
                DataCell(
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: catColor.withOpacity(0.4)),
                    ),
                    child: Text(
                      _translateType(tx.type),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: catColor.shade700),
                    ),
                  ),
                ),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (tx.customerName.isNotEmpty)
                        Text(tx.customerName,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      if (tx.customerId.isNotEmpty)
                        Text(tx.customerId,
                            style: TextStyle(
                                fontSize: 9, color: Colors.grey.shade500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 120,
                    child: Text(tx.planName,
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(Text(
                  '${_currencyFormat.format(tx.amount.abs())} د.ع',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: tx.amount < 0
                          ? Colors.red.shade700
                          : Colors.green.shade700),
                )),
                DataCell(Text(
                  tx.zoneId.isNotEmpty ? tx.zoneId : '-',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                )),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isAttributed)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.indigo.shade200),
                          ),
                          child: Text('منسوب تلقائياً',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.indigo.shade700,
                                  fontWeight: FontWeight.w600)),
                        ),
                      if (tx.auditCreator.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Text('audit: ${tx.auditCreator}',
                              style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.w600)),
                        ),
                      if (tx.deviceUsername.isNotEmpty)
                        Text('📡 ${tx.deviceUsername}',
                            style: TextStyle(
                                fontSize: 9, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Extension لسهولة الألوان
extension _ColorShade on Color {
  Color get shade700 {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness * 0.6).clamp(0.0, 1.0)).toColor();
  }

  Color get shade800 {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness * 0.45).clamp(0.0, 1.0)).toColor();
  }
}
