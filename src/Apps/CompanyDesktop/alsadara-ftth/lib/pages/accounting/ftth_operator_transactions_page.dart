/// صفحة عرض جميع عمليات مشغل معين من لوحة تحكم FTTH
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/accounting_responsive.dart';
import '../../utils/responsive_helper.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/plan_pricing_service.dart';

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
  final int planDuration;
  final double remainingBalance; // الرصيد بعد العملية
  final String paymentMode; // طريقة الدفع
  final String paymentMethod; // نوع الدفع
  final String startsAt; // بداية الاشتراك
  final String endsAt; // نهاية الاشتراك

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
    this.planDuration = 0,
    this.remainingBalance = 0.0,
    this.paymentMode = '',
    this.paymentMethod = '',
    this.startsAt = '',
    this.endsAt = '',
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
        planDuration: (tx['planDuration'] ?? 0) is int
            ? tx['planDuration'] ?? 0
            : int.tryParse('${tx['planDuration']}') ?? 0,
        remainingBalance: ((tx['remainingBalance'] ?? 0.0) is num)
            ? (tx['remainingBalance'] ?? 0.0).toDouble()
            : double.tryParse('${tx['remainingBalance']}') ?? 0.0,
        paymentMode: tx['paymentMode']?.toString() ?? '',
        paymentMethod: tx['paymentMethod']?.toString() ?? '',
        startsAt: tx['startsAt']?.toString() ?? '',
        endsAt: tx['endsAt']?.toString() ?? '',
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
        case 'plan':
          cmp = a.planName.compareTo(b.planName);
          break;
        case 'zone':
          cmp = a.zoneId.compareTo(b.zoneId);
          break;
        case 'duration':
          cmp = a.planDuration.compareTo(b.planDuration);
          break;
        case 'balance':
          cmp = a.remainingBalance.compareTo(b.remainingBalance);
          break;
        case 'discount':
          const rnChg = {
            'PLAN_RENEW',
            'AUTO_RENEW',
            'PLAN_EMI_RENEW',
            'PLAN_CHANGE',
            'SCHEDULE_CHANGE',
            'PLAN_SCHEDULE',
          };
          final dA = rnChg.contains(a.type)
              ? (PlanPricingService.instance
                      .getDiscount(a.planName, a.amount) ??
                  0)
              : 0.0;
          final dB = rnChg.contains(b.type)
              ? (PlanPricingService.instance
                      .getDiscount(b.planName, b.amount) ??
                  0)
              : 0.0;
          cmp = dA.compareTo(dB);
          break;
        case 'startDate':
          cmp = a.startsAt.compareTo(b.startsAt);
          break;
        case 'endDate':
          cmp = a.endsAt.compareTo(b.endsAt);
          break;
        case 'payment':
          cmp = a.paymentMode.compareTo(b.paymentMode);
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
      'PLAN_EMI_RENEW',
      'PurchaseSubscriptionFromTrial',
    };
    const sched = {
      'PLAN_SCHEDULE',
      'SCHEDULE_CHANGE',
      'SCHEDULE_CANCEL',
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
    if (sched.contains(type)) return 'scheduled';
    if (comm.contains(type)) return 'commission';
    if (rev.contains(type)) return 'reversal';
    if (wal.contains(type)) return 'wallet';
    return 'other';
  }

  static String _categorizeArabic(String type) {
    switch (_categorizeType(type)) {
      case 'subscription':
        return 'اشتراكات';
      case 'scheduled':
        return 'مجدول';
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
      case 'scheduled':
      case 'مجدول':
        return Colors.indigo;
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
      'مجدول',
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
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: context.accR.headingSmall),
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
    final isMob = context.responsive.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.accR.spaceM, vertical: context.accR.spaceS),
      color: Colors.grey.shade50,
      child: isMob
          ? Wrap(
              spacing: context.accR.spaceS,
              runSpacing: context.accR.spaceS,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - context.accR.spaceM * 2 - context.accR.spaceS) / 2,
                  child: _statCard('الإجمالي', '${_filtered.length}', Colors.teal),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - context.accR.spaceM * 2 - context.accR.spaceS) / 2,
                  child: _statCard(
                      'السالب',
                      '${_currencyFormat.format(_negativeAmount.abs())} د.ع',
                      Colors.red),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - context.accR.spaceM * 2 - context.accR.spaceS) / 2,
                  child: _statCard('الموجب', '${_currencyFormat.format(_positiveAmount)} د.ع',
                      Colors.green),
                ),
                if (widget.attributedOps > 0)
                  SizedBox(
                    width: (MediaQuery.of(context).size.width - context.accR.spaceM * 2 - context.accR.spaceS) / 2,
                    child: _statCard(
                        'منسوب تلقائياً', '${widget.attributedOps}', Colors.indigo),
                  ),
              ],
            )
          : Row(
              children: [
                _statCard('الإجمالي', '${_filtered.length}', Colors.teal),
                SizedBox(width: context.accR.spaceS),
                _statCard(
                    'السالب',
                    '${_currencyFormat.format(_negativeAmount.abs())} د.ع',
                    Colors.red),
                SizedBox(width: context.accR.spaceS),
                _statCard('الموجب', '${_currencyFormat.format(_positiveAmount)} د.ع',
                    Colors.green),
                if (widget.attributedOps > 0) ...[
                  SizedBox(width: context.accR.spaceS),
                  _statCard(
                      'منسوب تلقائياً', '${widget.attributedOps}', Colors.indigo),
                ],
              ],
            ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    final card = Container(
      padding: EdgeInsets.symmetric(vertical: context.accR.spaceS, horizontal: context.accR.spaceS),
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
                  fontSize: context.accR.caption,
                  color: color.shade700,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    fontSize: context.accR.small,
                    fontWeight: FontWeight.bold,
                    color: color.shade800),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
    if (!context.responsive.isMobile) {
      return Expanded(child: card);
    }
    return card;
  }

  Widget _buildSearchAndFilters(List<String> categories) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.accR.spaceM, vertical: context.accR.spaceXS),
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
                      hintStyle: TextStyle(fontSize: context.accR.small),
                      prefixIcon: Icon(Icons.search, size: context.accR.iconM),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, size: context.accR.iconS),
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
                    style: TextStyle(fontSize: context.accR.small),
                    onChanged: (v) {
                      setState(() {
                        _searchQuery = v;
                        _applyFilters();
                      });
                    },
                  ),
                ),
              ),
              SizedBox(width: context.accR.spaceS),
              // الترتيب
              PopupMenuButton<String>(
                tooltip: 'ترتيب',
                icon: Icon(Icons.sort, size: context.accR.iconM),
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
          SizedBox(height: context.accR.spaceXS),
          // فلتر Fiber + فلاتر التصنيف
          Row(
            children: [
              // زر Fiber فقط
              FilterChip(
                label: Text('Fiber فقط', style: TextStyle(fontSize: context.accR.small)),
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
              SizedBox(width: context.accR.spaceS),
              // فلاتر التصنيف
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => SizedBox(width: context.accR.spaceXS),
                    itemBuilder: (_, i) {
                      final cat = categories[i];
                      final isSelected = _selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat, style: TextStyle(fontSize: context.accR.small)),
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
              size: context.accR.iconS,
              color: Colors.teal,
            ),
          SizedBox(width: context.accR.spaceXS),
          Text(label, style: TextStyle(fontSize: context.accR.small)),
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
            Icon(Icons.inbox_outlined, size: context.accR.iconXL, color: Colors.grey.shade400),
            SizedBox(height: context.accR.spaceS),
            Text('لا توجد عمليات',
                style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    // خريطة أعمدة الترتيب
    const sortKeys = [
      '', // #
      'date',
      'type',
      'customer',
      'plan',
      'amount',
      'discount',
      'balance',
      'duration',
      'startDate',
      'endDate',
      'payment',
      'zone',
      '', // ملاحظات
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
            ),
            child: SingleChildScrollView(
              child: DataTable(
                border: TableBorder.all(color: Colors.black54, width: 0.5),
                columnSpacing: 0,
                horizontalMargin: 8,
                headingRowHeight: 30,
                dataRowMinHeight: 24,
                dataRowMaxHeight: 36,
                headingRowColor: WidgetStateProperty.all(Colors.teal.shade50),
                headingTextStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: context.accR.financialSmall,
                    color: Colors.black87),
                sortColumnIndex: sortKeys.contains(_sortBy)
                    ? sortKeys.indexOf(_sortBy)
                    : null,
                sortAscending: _isAscending,
                columns: [
                  DataColumn(
                      label: Expanded(child: Center(child: Text('#'))),
                      numeric: true),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('التاريخ'))),
                    onSort: (_, asc) => _onColumnSort('date', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('النوع'))),
                    onSort: (_, asc) => _onColumnSort('type', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('العميل'))),
                    onSort: (_, asc) => _onColumnSort('customer', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('م.العميل'))),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('الباقة'))),
                    onSort: (_, asc) => _onColumnSort('plan', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('المبلغ'))),
                    numeric: true,
                    onSort: (_, asc) => _onColumnSort('amount', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('الخصم'))),
                    numeric: true,
                    onSort: (_, asc) => _onColumnSort('discount', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('الرصيد'))),
                    numeric: true,
                    onSort: (_, asc) => _onColumnSort('balance', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('المدة'))),
                    numeric: true,
                    onSort: (_, asc) => _onColumnSort('duration', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('البداية'))),
                    onSort: (_, asc) => _onColumnSort('startDate', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('النهاية'))),
                    onSort: (_, asc) => _onColumnSort('endDate', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('الدفع'))),
                    onSort: (_, asc) => _onColumnSort('payment', asc),
                  ),
                  DataColumn(
                    label: Expanded(child: Center(child: Text('المنطقة'))),
                    onSort: (_, asc) => _onColumnSort('zone', asc),
                  ),
                  DataColumn(
                      label: Expanded(child: Center(child: Text('ملاحظات')))),
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
                      DataCell(Text('${i + 1}',
                          style: TextStyle(fontSize: context.accR.small))),
                      DataCell(Text(_formatDate(tx.occuredAt),
                          style: TextStyle(fontSize: context.accR.caption))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: catColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                            border:
                                Border.all(color: catColor.withOpacity(0.4)),
                          ),
                          child: Text(
                            _translateType(tx.type),
                            style: TextStyle(
                                fontSize: context.accR.caption,
                                fontWeight: FontWeight.w600,
                                color: catColor.shade700),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(tx.customerName.isNotEmpty ? tx.customerName : '-',
                            style: TextStyle(
                                fontSize: context.accR.small, fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      DataCell(
                        tx.customerId.isNotEmpty
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(tx.customerId,
                                      style: TextStyle(fontSize: context.accR.caption),
                                      overflow: TextOverflow.ellipsis),
                                  SizedBox(width: 2),
                                  InkWell(
                                    onTap: () {
                                      Clipboard.setData(
                                          ClipboardData(text: tx.customerId));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text('تم النسخ'),
                                              duration: Duration(seconds: 1)));
                                    },
                                    child: Icon(Icons.copy,
                                        size: context.accR.iconXS, color: Colors.grey.shade500),
                                  ),
                                ],
                              )
                            : Text('-', style: TextStyle(fontSize: context.accR.caption)),
                      ),
                      DataCell(
                        SizedBox(
                          width: 120,
                          child: Text(tx.planName,
                              style: TextStyle(
                                  fontSize: context.accR.caption, color: Colors.grey.shade700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataCell(Text(
                        '${_currencyFormat.format(tx.amount.abs())} د.ع',
                        style: TextStyle(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.bold,
                            color: tx.amount < 0
                                ? Colors.red.shade700
                                : Colors.green.shade700),
                      )),
                      // عمود الخصم (تجديد وتغيير فقط - الشراء له أسعار مختلفة)
                      DataCell(() {
                        const renewChangeTypes = {
                          'PLAN_RENEW',
                          'AUTO_RENEW',
                          'PLAN_EMI_RENEW',
                          'PLAN_CHANGE',
                          'SCHEDULE_CHANGE',
                          'PLAN_SCHEDULE',
                        };
                        if (!renewChangeTypes.contains(tx.type)) {
                          return Text('-',
                              style: TextStyle(
                                  fontSize: context.accR.caption, color: Colors.grey.shade400));
                        }
                        final discount = PlanPricingService.instance
                            .getDiscount(tx.planName, tx.amount);
                        if (discount != null) {
                          return Text(
                            _currencyFormat.format(discount),
                            style: TextStyle(
                                fontSize: context.accR.caption,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade800),
                          );
                        }
                        return Text('-',
                            style: TextStyle(
                                fontSize: context.accR.caption, color: Colors.grey.shade400));
                      }()),
                      DataCell(Text(
                        tx.remainingBalance != 0
                            ? _currencyFormat.format(tx.remainingBalance.abs())
                            : '-',
                        style: TextStyle(
                            fontSize: context.accR.caption, color: Colors.grey.shade600),
                      )),
                      DataCell(Text(
                        tx.planDuration > 0
                            ? '${tx.planDuration} يوم'
                            : _calcDuration(tx.startsAt, tx.endsAt),
                        style: TextStyle(
                            fontSize: context.accR.caption, color: Colors.grey.shade600),
                      )),
                      DataCell(Text(
                        tx.startsAt.isNotEmpty ? _formatDate(tx.startsAt) : '-',
                        style: TextStyle(
                            fontSize: context.accR.caption, color: Colors.grey.shade600),
                      )),
                      DataCell(Text(
                        tx.endsAt.isNotEmpty ? _formatDate(tx.endsAt) : '-',
                        style: TextStyle(
                            fontSize: context.accR.caption, color: Colors.grey.shade600),
                      )),
                      DataCell(Text(
                        tx.paymentMode.isNotEmpty
                            ? tx.paymentMode
                            : tx.paymentMethod.isNotEmpty
                                ? tx.paymentMethod
                                : '-',
                        style: TextStyle(
                            fontSize: context.accR.caption, color: Colors.grey.shade600),
                      )),
                      DataCell(Text(
                        tx.zoneId.isNotEmpty ? tx.zoneId : '-',
                        style: TextStyle(
                            fontSize: context.accR.caption, color: Colors.grey.shade600),
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
                                  border:
                                      Border.all(color: Colors.indigo.shade200),
                                ),
                                child: Text('منسوب تلقائياً',
                                    style: TextStyle(
                                        fontSize: context.accR.caption,
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
                                  border:
                                      Border.all(color: Colors.green.shade200),
                                ),
                                child: Text('audit: ${tx.auditCreator}',
                                    style: TextStyle(
                                        fontSize: context.accR.caption,
                                        color: Colors.green.shade800,
                                        fontWeight: FontWeight.w600)),
                              ),
                            if (tx.deviceUsername.isNotEmpty)
                              Text('📡 ${tx.deviceUsername}',
                                  style: TextStyle(
                                      fontSize: context.accR.caption,
                                      color: Colors.grey.shade500)),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  /// حساب المدة من تاريخ البداية والنهاية
  String _calcDuration(String startsAt, String endsAt) {
    if (startsAt.isEmpty || endsAt.isEmpty) return '-';
    try {
      final start = DateTime.parse(startsAt);
      final end = DateTime.parse(endsAt);
      final days = end.difference(start).inDays;
      if (days <= 0) return '-';
      if (days <= 31) return '$days يوم';
      final months = (days / 30).round();
      if (months == 1) return 'شهر';
      if (months == 2) return 'شهرين';
      if (months <= 10) return '$months أشهر';
      return '$months شهر';
    } catch (_) {
      return '-';
    }
  }

  void _onColumnSort(String column, bool ascending) {
    setState(() {
      if (_sortBy == column) {
        _isAscending = !_isAscending;
      } else {
        _sortBy = column;
        _isAscending = ascending;
      }
      _applyFilters();
    });
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
