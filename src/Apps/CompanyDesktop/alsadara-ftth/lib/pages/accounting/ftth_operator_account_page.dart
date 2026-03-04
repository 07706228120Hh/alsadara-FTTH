import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة كشف حساب مشغل FTTH
/// تعرض ملخص العمليات المالية لمشغل محدد (نقد/آجل/ماستر/وكيل)
class FtthOperatorAccountPage extends StatefulWidget {
  final String userId;
  final String operatorName;
  final String? companyId;

  const FtthOperatorAccountPage({
    super.key,
    required this.userId,
    required this.operatorName,
    this.companyId,
  });

  @override
  State<FtthOperatorAccountPage> createState() =>
      _FtthOperatorAccountPageState();
}

class _FtthOperatorAccountPageState extends State<FtthOperatorAccountPage> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _data;
  List<dynamic> _transactions = [];

  // فلاتر التاريخ
  DateTime? _fromDate;
  DateTime? _toDate;
  String _dateLabel = 'الكل';

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  final _currencyFormat = NumberFormat('#,###', 'ar');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String? _getAuthToken() {
    return VpsAuthService.instance.accessToken;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      var url =
          'https://api.ramzalsadara.tech/api/ftth-accounting/operator-summary/${widget.userId}?companyId=$_companyId';
      if (_fromDate != null) {
        url += '&from=${_fromDate!.toIso8601String().split('T')[0]}';
      }
      if (_toDate != null) {
        url += '&to=${_toDate!.toIso8601String().split('T')[0]}';
      }

      final token = _getAuthToken();
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
          'X-Api-Key': 'sadara-internal-2024-secure-key',
        },
      );

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          _data = result['data'] as Map<String, dynamic>?;
          _transactions = (_data?['transactions'] as List?) ?? [];
        } else {
          _errorMessage = result['message'] ?? 'خطأ';
        }
      } else {
        _errorMessage = 'خطأ في الاتصال: ${response.statusCode}';
      }
    } catch (e) {
      _errorMessage = 'خطأ: $e';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        appBar: AppBar(
          backgroundColor: AccountingTheme.bgSidebar,
          iconTheme: IconThemeData(color: Colors.white),
          title: Text(
            'كشف حساب: ${widget.operatorName}',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: context.accR.headingSmall,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.date_range, color: Colors.white70),
              onPressed: _showDateFilterDialog,
              tooltip: 'فلتر التاريخ',
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: _loadData,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: context.accR.iconXL, color: Colors.red.shade300),
                        SizedBox(height: context.accR.spaceM),
                        Text(_errorMessage!,
                            style: TextStyle(color: Colors.red.shade700)),
                        SizedBox(height: context.accR.spaceM),
                        ElevatedButton(
                            onPressed: _loadData,
                            child: const Text('إعادة المحاولة')),
                      ],
                    ),
                  )
                : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_data == null) return const Center(child: Text('لا توجد بيانات'));

    return SingleChildScrollView(
      padding: EdgeInsets.all(context.accR.spaceXL),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // فلتر التاريخ
          if (_dateLabel != 'الكل')
            Container(
              margin: EdgeInsets.only(bottom: context.accR.spaceM),
              padding: EdgeInsets.symmetric(horizontal: context.accR.spaceM, vertical: context.accR.spaceXS),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_alt, size: context.accR.iconS, color: Colors.blue.shade700),
                  SizedBox(width: context.accR.spaceXS),
                  Text(_dateLabel,
                      style:
                          TextStyle(fontSize: context.accR.small, color: Colors.blue.shade700)),
                  SizedBox(width: context.accR.spaceS),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _fromDate = null;
                        _toDate = null;
                        _dateLabel = 'الكل';
                      });
                      _loadData();
                    },
                    child: Icon(Icons.close,
                        size: context.accR.iconS, color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),

          // ملخص البطاقات
          _buildSummaryCards(),
          SizedBox(height: context.accR.spaceXL),

          // جدول العمليات
          _buildTransactionsTable(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final total = (_data?['totalAmount'] ?? 0).toDouble();
    final cash = (_data?['cashAmount'] ?? 0).toDouble();
    final credit = (_data?['creditAmount'] ?? 0).toDouble();
    final master = (_data?['masterAmount'] ?? 0).toDouble();
    final agent = (_data?['agentAmount'] ?? 0).toDouble();
    final unclassified = (_data?['unclassifiedAmount'] ?? 0).toDouble();

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _summaryCard(
            'إجمالي العمليات',
            total,
            '${_data?['totalActivations'] ?? 0} عملية',
            AccountingTheme.neonBlue,
            icon: Icons.receipt_long),
        _summaryCard('نقد', cash, '${_data?['cashCount'] ?? 0} عملية',
            Colors.green.shade600,
            icon: Icons.attach_money),
        _summaryCard('آجل', credit, '${_data?['creditCount'] ?? 0} عملية',
            Colors.orange.shade600,
            icon: Icons.schedule),
        _summaryCard('ماستر', master, '${_data?['masterCount'] ?? 0} عملية',
            Colors.purple.shade600,
            icon: Icons.credit_card),
        _summaryCard('وكيل', agent, '${_data?['agentCount'] ?? 0} عملية',
            Colors.blue.shade600,
            icon: Icons.store),
        if (unclassified > 0)
          _summaryCard('غير مصنف', unclassified,
              '${_data?['unclassifiedCount'] ?? 0} عملية', Colors.grey.shade600,
              icon: Icons.help_outline),
      ],
    );
  }

  Widget _summaryCard(String title, double amount, String subtitle, Color color,
      {IconData? icon}) {
    return SizedBox(
      width: 180,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.accR.cardRadius)),
        child: Padding(
          padding: EdgeInsets.all(context.accR.spaceL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: context.accR.iconM, color: color),
                    SizedBox(width: context.accR.spaceXS),
                  ],
                  Expanded(
                    child: Text(title,
                        style: GoogleFonts.cairo(
                            fontSize: context.accR.small,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ),
                ],
              ),
              SizedBox(height: context.accR.spaceS),
              Text(
                '${_currencyFormat.format(amount)} د.ع',
                style: GoogleFonts.cairo(
                    fontSize: context.accR.headingSmall, fontWeight: FontWeight.bold, color: color),
              ),
              SizedBox(height: context.accR.spaceXS),
              Text(subtitle,
                  style: TextStyle(fontSize: context.accR.small, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetOwedCard() {
    final remainingCash = (_data?['remainingCash'] ?? 0).toDouble();
    final remainingCredit = (_data?['remainingCredit'] ?? 0).toDouble();
    final netOwed = (_data?['netOwed'] ?? 0).toDouble();
    final deliveredCash = (_data?['deliveredCash'] ?? 0).toDouble();
    final collectedCredit = (_data?['collectedCredit'] ?? 0).toDouble();

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.accR.cardRadius)),
      color: netOwed > 0 ? Colors.red.shade50 : Colors.green.shade50,
      child: Padding(
        padding: EdgeInsets.all(context.accR.spaceXL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  netOwed > 0
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle,
                  color:
                      netOwed > 0 ? Colors.red.shade700 : Colors.green.shade700,
                  size: context.accR.iconL,
                ),
                SizedBox(width: context.accR.spaceS),
                Text(
                  'المبالغ المستحقة',
                  style: GoogleFonts.cairo(
                      fontSize: context.accR.body,
                      fontWeight: FontWeight.bold,
                      color: netOwed > 0
                          ? Colors.red.shade700
                          : Colors.green.shade700),
                ),
              ],
            ),
            const Divider(),
            _netRow('نقد مُجمّع', (_data?['cashAmount'] ?? 0).toDouble(),
                Colors.green),
            _netRow('نقد مُسلَّم', deliveredCash, Colors.teal),
            _netRow('باقي النقد', remainingCash,
                remainingCash > 0 ? Colors.red : Colors.green),
            SizedBox(height: context.accR.spaceS),
            _netRow('آجل مُسجّل', (_data?['creditAmount'] ?? 0).toDouble(),
                Colors.orange),
            _netRow('آجل مُحصّل', collectedCredit, Colors.teal),
            _netRow('باقي الآجل', remainingCredit,
                remainingCredit > 0 ? Colors.red : Colors.green),
            Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('صافي المستحق',
                    style: GoogleFonts.cairo(
                        fontSize: context.accR.body, fontWeight: FontWeight.bold)),
                Text(
                  '${_currencyFormat.format(netOwed)} د.ع',
                  style: GoogleFonts.cairo(
                    fontSize: context.accR.headingSmall,
                    fontWeight: FontWeight.bold,
                    color: netOwed > 0
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _netRow(String label, double amount, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: context.accR.financialSmall, color: Colors.grey.shade700)),
          Text(
            '${_currencyFormat.format(amount)} د.ع',
            style: TextStyle(
                fontSize: context.accR.financialSmall, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTable() {
    if (_transactions.isEmpty) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(context.accR.spaceXXL),
          child: Center(
            child: Text('لا توجد عمليات',
                style: TextStyle(color: Colors.grey.shade500)),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(context.accR.cardRadius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(context.accR.spaceL),
            child: Text('العمليات (${_transactions.length})',
                style: GoogleFonts.cairo(
                    fontSize: context.accR.body, fontWeight: FontWeight.w600)),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    border: TableBorder.all(
                        color: Colors.grey.shade300, width: 0.5),
                    headingRowColor:
                        WidgetStateProperty.all(Colors.grey.shade100),
                    headingRowHeight: 36,
                    dataRowMinHeight: 30,
                    dataRowMaxHeight: 48,
                    columnSpacing: 0,
                    horizontalMargin: 8,
                    columns: const [
                      DataColumn(label: _ColHead('#')),
                      DataColumn(label: _ColHead('م.العميل')),
                      DataColumn(label: _ColHead('العميل')),
                      DataColumn(label: _ColHead('الهاتف')),
                      DataColumn(label: _ColHead('م.الاشتراك')),
                      DataColumn(label: _ColHead('الباقة')),
                      DataColumn(label: _ColHead('المبلغ')),
                      DataColumn(label: _ColHead('الالتزام')),
                      DataColumn(label: _ColHead('التكرار')),
                      DataColumn(label: _ColHead('النوع')),
                      DataColumn(label: _ColHead('التحصيل')),
                      DataColumn(label: _ColHead('المنطقة')),
                      DataColumn(label: _ColHead('الفني')),
                      DataColumn(label: _ColHead('المُنفذ')),
                      DataColumn(label: _ColHead('التاريخ')),
                      DataColumn(label: _ColHead('البداية')),
                      DataColumn(label: _ColHead('النهاية')),
                      DataColumn(label: _ColHead('الحالة')),
                      DataColumn(label: _ColHead('الدفع')),
                      DataColumn(label: _ColHead('محفظة قبل')),
                      DataColumn(label: _ColHead('محفظة بعد')),
                      DataColumn(label: _ColHead('الجهاز')),
                      DataColumn(label: _ColHead('طباعة')),
                      DataColumn(label: _ColHead('واتساب')),
                      DataColumn(label: _ColHead('مطابقة')),
                      DataColumn(label: _ColHead('محاسبة')),
                      DataColumn(label: _ColHead('ملاحظات')),
                    ],
                    rows: _transactions.asMap().entries.map((entry) {
                      final i = entry.key;
                      final tx = entry.value as Map<String, dynamic>;
                      final walletBefore =
                          (tx['WalletBalanceBefore'] as num?)?.toDouble();
                      final walletAfter =
                          (tx['WalletBalanceAfter'] as num?)?.toDouble();

                      return DataRow(cells: [
                        // #
                        DataCell(Center(
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    fontSize: context.accR.small,
                                    fontWeight: FontWeight.w600)))),
                        // م.العميل
                        DataCell(Center(
                            child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tx['CustomerId'] ?? '-',
                                style: TextStyle(fontSize: context.accR.caption),
                                overflow: TextOverflow.ellipsis),
                            if (tx['CustomerId'] != null)
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                      ClipboardData(text: tx['CustomerId']));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('تم النسخ'),
                                          duration: Duration(seconds: 1)));
                                },
                                child: Padding(
                                  padding: EdgeInsets.only(right: 2),
                                  child: Icon(Icons.copy,
                                      size: context.accR.iconXS, color: Colors.grey.shade500),
                                ),
                              ),
                          ],
                        ))),
                        // العميل
                        DataCell(Center(
                            child: Text(tx['CustomerName'] ?? '-',
                                style: TextStyle(fontSize: context.accR.small),
                                overflow: TextOverflow.ellipsis))),
                        // الهاتف
                        DataCell(Center(
                            child: Text(tx['PhoneNumber'] ?? '-',
                                style: TextStyle(fontSize: context.accR.small)))),
                        // م.الاشتراك
                        DataCell(Center(
                            child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tx['SubscriptionId'] ?? '-',
                                style: TextStyle(fontSize: context.accR.caption),
                                overflow: TextOverflow.ellipsis),
                            if (tx['SubscriptionId'] != null)
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(
                                      text: tx['SubscriptionId']));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('تم النسخ'),
                                          duration: Duration(seconds: 1)));
                                },
                                child: Padding(
                                  padding: EdgeInsets.only(right: 2),
                                  child: Icon(Icons.copy,
                                      size: context.accR.iconXS, color: Colors.grey.shade500),
                                ),
                              ),
                          ],
                        ))),
                        // الباقة
                        DataCell(Center(
                            child: Text(tx['PlanName'] ?? '-',
                                style: TextStyle(fontSize: context.accR.small)))),
                        // المبلغ
                        DataCell(Center(
                            child: Text(
                          _currencyFormat
                              .format((tx['PlanPrice'] ?? 0).toDouble()),
                          style: TextStyle(
                              fontSize: context.accR.small,
                              fontWeight: FontWeight.w700,
                              color: Colors.green.shade700),
                        ))),
                        // الالتزام
                        DataCell(Center(
                            child: Text(
                                tx['CommitmentPeriod'] != null
                                    ? '${tx['CommitmentPeriod']} شهر'
                                    : '-',
                                style: TextStyle(fontSize: context.accR.small)))),
                        // التكرار
                        DataCell(
                          Center(child: Builder(builder: (_) {
                            final cycle = tx['RenewalCycleMonths'] as int?;
                            final paid =
                                (tx['PaidMonths'] as num?)?.toInt() ?? 0;
                            if (cycle == null || cycle <= 0) {
                              return Icon(Icons.add_circle_outline,
                                  size: context.accR.iconS, color: Colors.grey.shade400);
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: paid >= cycle
                                    ? Colors.green.shade50
                                    : Colors.deepPurple.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: paid >= cycle
                                      ? Colors.green.shade300
                                      : Colors.deepPurple.shade300,
                                ),
                              ),
                              child: Text(
                                '$paid/$cycle شهر',
                                style: TextStyle(
                                  fontSize: context.accR.caption,
                                  fontWeight: FontWeight.w700,
                                  color: paid >= cycle
                                      ? Colors.green.shade700
                                      : Colors.deepPurple.shade700,
                                ),
                              ),
                            );
                          })),
                          onTap: () => _showRenewalCycleDialog(tx),
                        ),
                        // النوع
                        DataCell(Center(
                            child: _buildTypeBadge(tx['OperationType'] ?? ''))),
                        // التحصيل
                        DataCell(Center(
                            child: _buildCollectionBadge(
                                tx['CollectionType'] ?? ''))),
                        // المنطقة
                        DataCell(Center(
                            child: Text(tx['ZoneName'] ?? tx['ZoneId'] ?? '-',
                                style: TextStyle(fontSize: context.accR.small),
                                overflow: TextOverflow.ellipsis))),
                        // الفني
                        DataCell(Center(
                            child: Text(tx['TechnicianName'] ?? '-',
                                style: TextStyle(fontSize: context.accR.small)))),
                        // المُنفذ
                        DataCell(Center(
                            child: Text(tx['ActivatedBy'] ?? '-',
                                style: TextStyle(fontSize: context.accR.small),
                                overflow: TextOverflow.ellipsis))),
                        // التاريخ
                        DataCell(Center(
                            child: Text(_formatDate(tx['ActivationDate']),
                                style: TextStyle(fontSize: context.accR.caption)))),
                        // البداية
                        DataCell(Center(
                            child: Text(tx['StartDate'] ?? '-',
                                style: TextStyle(fontSize: context.accR.caption)))),
                        // النهاية
                        DataCell(Center(
                            child: Text(tx['EndDate'] ?? '-',
                                style: TextStyle(fontSize: context.accR.caption)))),
                        // الحالة
                        DataCell(Center(
                            child:
                                _buildStatusBadge(tx['CurrentStatus'] ?? ''))),
                        // الدفع
                        DataCell(Center(
                            child: Text(
                                tx['PaymentStatus'] ??
                                    tx['PaymentMethod'] ??
                                    '-',
                                style: TextStyle(fontSize: context.accR.small)))),
                        // محفظة قبل
                        DataCell(Center(
                            child: Text(
                                walletBefore != null
                                    ? _currencyFormat.format(walletBefore)
                                    : '-',
                                style: TextStyle(fontSize: context.accR.caption)))),
                        // محفظة بعد
                        DataCell(Center(
                            child: Text(
                                walletAfter != null
                                    ? _currencyFormat.format(walletAfter)
                                    : '-',
                                style: TextStyle(fontSize: context.accR.caption)))),
                        // الجهاز
                        DataCell(Center(
                            child: Text(tx['DeviceUsername'] ?? '-',
                                style: TextStyle(fontSize: context.accR.caption),
                                overflow: TextOverflow.ellipsis))),
                        // طباعة
                        DataCell(Center(
                            child: tx['IsPrinted'] == true
                                ? Icon(Icons.print,
                                    size: context.accR.iconS, color: Colors.green.shade600)
                                : Icon(Icons.print_disabled,
                                    size: context.accR.iconS, color: Colors.grey.shade400))),
                        // واتساب
                        DataCell(Center(
                            child: tx['IsWhatsAppSent'] == true
                                ? Icon(Icons.check_circle,
                                    size: context.accR.iconS, color: Colors.green.shade600)
                                : Icon(Icons.cancel_outlined,
                                    size: context.accR.iconS, color: Colors.grey.shade400))),
                        // مطابقة
                        DataCell(Center(
                            child: tx['IsReconciled'] == true
                                ? Icon(Icons.check_circle,
                                    size: context.accR.iconS, color: Colors.green.shade600)
                                : Icon(Icons.cancel_outlined,
                                    size: context.accR.iconS, color: Colors.grey.shade400))),
                        // محاسبة
                        DataCell(Center(
                            child: tx['JournalEntryId'] != null
                                ? Icon(Icons.check_circle,
                                    size: context.accR.iconS, color: Colors.green.shade600)
                                : Icon(Icons.remove_circle_outline,
                                    size: context.accR.iconS, color: Colors.grey.shade400))),
                        // ملاحظات
                        DataCell(Center(
                            child: Text(tx['SubscriptionNotes'] ?? '-',
                                style: TextStyle(fontSize: context.accR.caption),
                                overflow: TextOverflow.ellipsis))),
                      ]);
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge(String type) {
    final lower = type.toLowerCase();
    String label;
    Color bgColor;
    Color txtColor;
    if (lower.contains('renew')) {
      label = 'تجديد';
      bgColor = Colors.blue.shade50;
      txtColor = Colors.blue.shade700;
    } else if (lower.contains('change')) {
      label = 'تغيير';
      bgColor = Colors.orange.shade50;
      txtColor = Colors.orange.shade700;
    } else if (lower.contains('schedule')) {
      label = 'جدولة';
      bgColor = Colors.purple.shade50;
      txtColor = Colors.purple.shade700;
    } else {
      label = 'شراء';
      bgColor = Colors.teal.shade50;
      txtColor = Colors.teal.shade700;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
      ),
      child: Text(label, style: TextStyle(fontSize: context.accR.caption, color: txtColor)),
    );
  }

  Widget _buildStatusBadge(String status) {
    if (status.isEmpty) return Text('-', style: TextStyle(fontSize: context.accR.small));
    final lower = status.toLowerCase();
    Color color;
    if (lower.contains('active')) {
      color = Colors.green.shade700;
    } else if (lower.contains('suspend') || lower.contains('block')) {
      color = Colors.red.shade700;
    } else if (lower.contains('trial')) {
      color = Colors.orange.shade700;
    } else {
      color = Colors.grey.shade700;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: context.accR.spaceXS, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(status,
          style: TextStyle(
              fontSize: context.accR.caption, fontWeight: FontWeight.w600, color: color),
          overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildCollectionBadge(String type) {
    MaterialColor color;
    String label;
    switch (type.toLowerCase()) {
      case 'cash':
        color = Colors.green;
        label = 'نقد';
        break;
      case 'credit':
        color = Colors.orange;
        label = 'آجل';
        break;
      case 'master':
        color = Colors.purple;
        label = 'ماستر';
        break;
      case 'agent':
        color = Colors.blue;
        label = 'وكيل';
        break;
      default:
        color = Colors.grey;
        label = type.isNotEmpty ? type : '-';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
      ),
      child: Text(label, style: TextStyle(fontSize: context.accR.caption, color: color.shade700)),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dt = DateTime.parse(date.toString());
      return DateFormat('yyyy/MM/dd', 'ar').format(dt);
    } catch (_) {
      return date.toString();
    }
  }

  /// دايلوق تعيين دورة التكرار مباشرة من جدول العمليات
  void _showRenewalCycleDialog(Map<String, dynamic> tx) {
    final logId = tx['Id'];
    if (logId == null) return;
    final currentCycle = tx['RenewalCycleMonths'] as int?;
    final customerName = tx['CustomerName'] ?? '-';
    final planName = tx['PlanName'] ?? '-';
    final collectionType =
        (tx['CollectionType'] ?? '').toString().toLowerCase();

    final options = [
      {'label': 'بدون', 'value': 0},
      {'label': 'شهر', 'value': 1},
      {'label': '2 أشهر', 'value': 2},
      {'label': '3 أشهر', 'value': 3},
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تعيين التكرار',
            style:
                GoogleFonts.cairo(fontSize: context.accR.body, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$customerName - $planName',
                style: GoogleFonts.cairo(
                    fontSize: context.accR.small, color: Colors.grey.shade700)),
            if (collectionType == 'cash')
              Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('نقد - الشهر الأول مدفوع تلقائياً',
                    style:
                        TextStyle(fontSize: context.accR.small, color: Colors.teal.shade700)),
              ),
            SizedBox(height: context.accR.spaceM),
            Wrap(
              spacing: 8,
              children: options.map((opt) {
                final val = opt['value'] as int;
                final isSelected = (currentCycle ?? 0) == val;
                return ChoiceChip(
                  label: Text(opt['label'] as String,
                      style: GoogleFonts.cairo(fontSize: context.accR.small)),
                  selected: isSelected,
                  selectedColor: Colors.deepPurple.shade100,
                  onSelected: (_) async {
                    Navigator.pop(ctx);
                    await _applyRenewalCycle(
                        logId, val == 0 ? null : val, collectionType);
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyRenewalCycle(
      dynamic logId, int? cycleMonths, String collectionType) async {
    try {
      // حساب PaidMonths: إذا نقد وأكثر من شهر = 1 (الأول مدفوع)
      int? paidMonths;
      if (collectionType == 'cash' && cycleMonths != null && cycleMonths > 1) {
        paidMonths = 1;
      } else {
        paidMonths = 0;
      }

      final result = await AccountingService.instance.setRenewalCycle(
        logId: int.parse(logId.toString()),
        cycleMonths: cycleMonths,
        paidMonths: paidMonths,
      );

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cycleMonths != null
                ? 'تم تعيين التكرار: $cycleMonths شهر'
                : 'تم إلغاء التكرار'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 2),
          ),
        );
        _loadData(); // إعادة تحميل البيانات
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'خطأ'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  void _showDateFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('فلتر التاريخ', style: GoogleFonts.cairo()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dateFilterOption('اليوم', () {
              final now = DateTime.now();
              _fromDate = DateTime(now.year, now.month, now.day);
              _toDate = now;
              _dateLabel = 'اليوم';
            }),
            _dateFilterOption('آخر 7 أيام', () {
              _toDate = DateTime.now();
              _fromDate = _toDate!.subtract(const Duration(days: 7));
              _dateLabel = 'آخر 7 أيام';
            }),
            _dateFilterOption('هذا الشهر', () {
              final now = DateTime.now();
              _fromDate = DateTime(now.year, now.month, 1);
              _toDate = now;
              _dateLabel = 'هذا الشهر';
            }),
            _dateFilterOption('الكل', () {
              _fromDate = null;
              _toDate = null;
              _dateLabel = 'الكل';
            }),
          ],
        ),
      ),
    );
  }

  Widget _dateFilterOption(String label, VoidCallback setDates) {
    return ListTile(
      title: Text(label, style: GoogleFonts.cairo(fontSize: context.accR.body)),
      trailing: _dateLabel == label
          ? Icon(Icons.check, color: Colors.green.shade600)
          : null,
      onTap: () {
        setDates();
        Navigator.pop(context);
        _loadData();
      },
    );
  }
}

/// عنوان عمود مختصر
class _ColHead extends StatelessWidget {
  final String text;
  const _ColHead(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(text,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.accR.small),
            overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
