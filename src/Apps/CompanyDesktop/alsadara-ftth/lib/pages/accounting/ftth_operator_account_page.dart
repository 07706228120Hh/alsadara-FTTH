import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart' hide TextDirection;
import 'package:shared_preferences/shared_preferences.dart';
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
  final DateTime? initialFromDate;
  final DateTime? initialToDate;
  final String? initialDateLabel;
  final bool isTechnician;

  const FtthOperatorAccountPage({
    super.key,
    required this.userId,
    required this.operatorName,
    this.companyId,
    this.initialFromDate,
    this.initialToDate,
    this.initialDateLabel,
    this.isTechnician = false,
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
  String _txSearchQuery = '';
  final _txSearchController = TextEditingController();

  /// حقل بحث قابل للتصفية — يعمل داخل Dialog بدون مشاكل Overlay
  Widget _buildSearchableField({
    required String label,
    required String hint,
    required List<dynamic> list,
    required String? selectedId,
    required InputDecoration Function(String) fieldDeco,
    required Widget Function(String, Widget) fieldRow,
    required void Function(String? id, String name) onSelected,
    required VoidCallback onClear,
    required StateSetter setDialogState,
  }) {
    if (list.isEmpty) {
      return fieldRow(label, const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      ));
    }
    // تصفية العناصر بدون ID + إزالة التكرار (API يرجع Id أو id)
    final valid = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in list) {
      final id = (item['id'] ?? item['Id'])?.toString() ?? '';
      if (id.isNotEmpty && seen.add(id)) {
        // توحيد المفاتيح
        valid.add({
          'id': id,
          'name': (item['name'] ?? item['Name'] ?? item['FullName'] ?? '').toString(),
        });
      }
    }
    // الاسم المختار حالياً
    String selectedName = '';
    if (selectedId != null) {
      final match = valid.where((i) => i['id'] == selectedId).firstOrNull;
      if (match != null) selectedName = match['name'] ?? '';
    }

    return fieldRow(label, _SearchableDropdownField(
      hint: hint,
      items: valid,
      selectedName: selectedName,
      fieldDeco: fieldDeco,
      onSelected: onSelected,
      onClear: onClear,
    ));
  }

  // ===== تعريفات الأعمدة =====
  static const _columnKeys = <String>[
    'edit', 'index', 'customerId', 'customerName', 'phone', 'subscriptionId',
    'plan', 'amount', 'pageDeduction', 'revenue', 'expense', 'commitment', 'renewal', 'type', 'collection',
    'zone', 'technician', 'activatedBy', 'date', 'startDate', 'endDate',
    'status', 'payment', 'walletBefore', 'walletAfter', 'device',
    'printed', 'whatsapp', 'reconciled', 'accounting', 'notes',
  ];

  static const _columnLabels = <String, String>{
    'index': '#',
    'customerId': 'م.العميل',
    'customerName': 'العميل',
    'phone': 'الهاتف',
    'subscriptionId': 'م.الاشتراك',
    'plan': 'الباقة',
    'amount': 'المبلغ',
    'pageDeduction': 'المستقطع',
    'revenue': 'الإيرادات',
    'expense': 'المصاريف',
    'commitment': 'الالتزام',
    'renewal': 'التكرار',
    'type': 'النوع',
    'collection': 'التحصيل',
    'zone': 'المنطقة',
    'technician': 'الفني',
    'activatedBy': 'المُنفذ',
    'date': 'التاريخ',
    'startDate': 'البداية',
    'endDate': 'النهاية',
    'status': 'الحالة',
    'payment': 'الدفع',
    'walletBefore': 'محفظة قبل',
    'walletAfter': 'محفظة بعد',
    'device': 'الجهاز',
    'printed': 'طباعة',
    'whatsapp': 'واتساب',
    'reconciled': 'مطابقة',
    'accounting': 'محاسبة',
    'notes': 'ملاحظات',
    'edit': 'تعديل',
  };

  // حالة إظهار/إخفاء الأعمدة
  Set<String> _visibleColumns = {
    'edit', 'index', 'customerId', 'customerName', 'phone', 'subscriptionId',
    'plan', 'amount', 'pageDeduction', 'revenue', 'expense', 'commitment', 'renewal', 'type', 'collection',
    'zone', 'technician', 'activatedBy', 'date', 'startDate', 'endDate',
    'status', 'payment', 'walletBefore', 'walletAfter', 'device',
    'printed', 'whatsapp', 'reconciled', 'accounting', 'notes',
  };

  // حالة الترتيب
  String? _sortKey;
  bool _sortAscending = true;

  // حالة الفلاتر
  final Map<String, String> _columnFilters = {};

  // مفتاح حفظ الأعمدة المرئية محلياً
  static const _visibleColumnsKey = 'ftth_operator_account_visible_columns';

  @override
  void initState() {
    super.initState();
    _loadSavedColumns();
    // تطبيق فلاتر التاريخ المُمررة من الصفحة السابقة
    if (widget.initialFromDate != null || widget.initialToDate != null) {
      _fromDate = widget.initialFromDate;
      _toDate = widget.initialToDate;
      _dateLabel = widget.initialDateLabel ?? 'مخصص';
    }
    _loadData();
  }

  Future<void> _loadSavedColumns() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_visibleColumnsKey);
    if (saved != null && saved.isNotEmpty && mounted) {
      setState(() => _visibleColumns = saved.toSet());
    }
  }

  Future<void> _saveColumns() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_visibleColumnsKey, _visibleColumns.toList());
  }

  String? _getAuthToken() {
    return VpsAuthService.instance.accessToken;
  }

  Future<void> _fixPageDeductions() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصحيح المستقطع'),
        content: Text(
          'سيتم إعادة حساب المستقطع (BasePrice) لجميع عمليات هذا المشغل'
          '${_fromDate != null || _toDate != null ? ' في الفترة المحددة' : ''}'
          ' ليطابق مبالغ FTTH.\n\n'
          'سيتم إلغاء القيود المحاسبية القديمة وإنشاء قيود جديدة بالأرقام الصحيحة.\n\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تصحيح', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جارٍ تصحيح المستقطع...'), duration: Duration(seconds: 30)),
    );

    try {
      final result = await AccountingService.instance.recalculateSyncRevenues(
        companyId: widget.companyId,
        userId: widget.userId,
        from: _fromDate,
        to: _toDate,
        forceAll: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      final updated = result['updated'] ?? 0;
      final accCreated = result['accountingCreated'] ?? 0;
      final accUpdated = result['accountingUpdated'] ?? 0;
      final failed = result['failed'] ?? 0;
      final totalFound = result['totalFound'] ?? 0;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(updated > 0 ? Icons.check_circle : Icons.info, color: updated > 0 ? Colors.green : Colors.blue),
            const SizedBox(width: 8),
            const Text('نتيجة التصحيح'),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('العمليات المفحوصة: $totalFound'),
            Text('تم تحديث: $updated', style: TextStyle(color: updated > 0 ? Colors.green.shade700 : null, fontWeight: FontWeight.bold)),
            if (accCreated > 0) Text('قيود جديدة: $accCreated', style: TextStyle(color: Colors.blue.shade700)),
            if (accUpdated > 0) Text('قيود ملغية: $accUpdated', style: TextStyle(color: Colors.orange.shade700)),
            if (failed > 0) Text('فشل: $failed', style: TextStyle(color: Colors.red.shade700)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      );

      if (updated > 0 || accCreated > 0) _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _recalculateSyncRevenues() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة حساب الإيرادات'),
        content: const Text(
          'سيتم إعادة حساب خصم الشركة وأجور الصيانة لجميع العمليات المتزامنة التي ليس لديها إيرادات.\n\n'
          'سيتم إلغاء القيود المحاسبية القديمة وإنشاء قيود جديدة بالأرقام الصحيحة.\n\n'
          'هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تنفيذ')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جارٍ إعادة حساب الإيرادات...'), duration: Duration(seconds: 30)),
    );

    try {
      final result = await AccountingService.instance.recalculateSyncRevenues(companyId: widget.companyId, userId: widget.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      final msg = result['message'] ?? 'تم';
      final updated = result['updated'] ?? 0;
      final accCreated = result['accountingCreated'] ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$msg'),
          backgroundColor: updated > 0 ? Colors.green.shade700 : Colors.blueGrey,
          duration: const Duration(seconds: 5),
        ),
      );

      if (updated > 0 || accCreated > 0) _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      var url =
          'https://api.ramzalsadara.tech/api/ftth-accounting/operator-summary/${widget.userId}?companyId=$_companyId';
      if (widget.isTechnician) {
        url += '&isTechnician=true';
      }
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

      debugPrint('🔍 operator-summary URL: $url');
      debugPrint('🔍 operator-summary status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('🔍 operator-summary body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['success'] == true) {
          _data = result['data'] as Map<String, dynamic>?;
          _transactions = (_data?['transactions'] as List?) ?? [];
        } else {
          _errorMessage = result['message'] ?? 'خطأ';
        }
      } else {
        // عرض تفاصيل الخطأ للتشخيص
        String serverMsg = '';
        try {
          final errBody = jsonDecode(response.body);
          serverMsg = errBody['message'] ?? response.body;
        } catch (_) {
          serverMsg = response.body;
        }
        _errorMessage = 'خطأ ${response.statusCode}: $serverMsg';
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
            if (!_isLoading && _data != null)
              _appBarButton(Icons.list_alt, 'العمليات (${_getProcessedTransactions().length}${_getProcessedTransactions().length != _transactions.length ? '/${_transactions.length}' : ''})', () {}),
            _appBarButton(Icons.view_column, 'الأعمدة', _showColumnSelectorDialog),
            _appBarButton(Icons.filter_list, 'تصفية', _showFilterDialog,
                highlighted: _columnFilters.values.any((v) => v.isNotEmpty)),
            if (_columnFilters.values.any((v) => v.isNotEmpty) || _sortKey != null)
              _appBarButton(Icons.clear_all, 'مسح', () {
                setState(() {
                  _columnFilters.clear();
                  _sortKey = null;
                  _sortAscending = true;
                });
              }),
            if (_dateLabel != 'الكل')
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt, size: context.accR.iconXS, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text(_dateLabel,
                        style: GoogleFonts.cairo(fontSize: context.accR.caption, color: Colors.white)),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                          _dateLabel = 'الكل';
                        });
                        _loadData();
                      },
                      child: Icon(Icons.close, size: context.accR.iconXS, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            IconButton(
              icon: Icon(Icons.compare_arrows, color: Colors.orangeAccent, size: context.accR.iconAppBar),
              onPressed: _fixPageDeductions,
              tooltip: 'تصحيح المستقطع (مطابقة FTTH)',
            ),
            IconButton(
              icon: Icon(Icons.calculate_outlined, color: Colors.purpleAccent, size: context.accR.iconAppBar),
              onPressed: _recalculateSyncRevenues,
              tooltip: 'إعادة حساب الإيرادات',
            ),
            IconButton(
              icon: Icon(Icons.date_range, color: Colors.white70, size: context.accR.iconAppBar),
              onPressed: _showDateFilterDialog,
              tooltip: 'فلتر التاريخ',
            ),
            IconButton(
              icon: Icon(Icons.refresh, color: Colors.white70, size: context.accR.iconAppBar),
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
      padding: EdgeInsets.all(context.accR.spaceS),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ملخص البطاقات
          _buildSummaryCards(),
          SizedBox(height: context.accR.spaceS),

          // جدول العمليات
          _buildTransactionsTable(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final ar = context.accR;
    final total = (_data?['totalAmount'] ?? 0).toDouble();
    final cash = (_data?['cashAmount'] ?? 0).toDouble();
    final credit = (_data?['creditAmount'] ?? 0).toDouble();
    final master = (_data?['masterAmount'] ?? 0).toDouble();
    final agent = (_data?['agentAmount'] ?? 0).toDouble();
    final unclassified = (_data?['unclassifiedAmount'] ?? 0).toDouble();

    final cards = <Map<String, dynamic>>[
      {'title': 'إجمالي العمليات', 'amount': total, 'count': _data?['totalActivations'] ?? 0,
       'icon': Icons.receipt_long, 'colors': [const Color(0xFF3498DB), const Color(0xFF2980B9)]},
      {'title': 'نقد', 'amount': cash, 'count': _data?['cashCount'] ?? 0,
       'icon': Icons.attach_money, 'colors': [const Color(0xFF2ECC71), const Color(0xFF27AE60)]},
      {'title': 'آجل', 'amount': credit, 'count': _data?['creditCount'] ?? 0,
       'icon': Icons.schedule, 'colors': [const Color(0xFFE67E22), const Color(0xFFD35400)]},
      {'title': 'ماستر', 'amount': master, 'count': _data?['masterCount'] ?? 0,
       'icon': Icons.credit_card, 'colors': [const Color(0xFF8E44AD), const Color(0xFF7D3C98)]},
      {'title': 'وكيل', 'amount': agent, 'count': _data?['agentCount'] ?? 0,
       'icon': Icons.store, 'colors': [const Color(0xFF2C3E50), const Color(0xFF1A252F)]},
      if (unclassified > 0)
        {'title': 'غير مصنف', 'amount': unclassified, 'count': _data?['unclassifiedCount'] ?? 0,
         'icon': Icons.help_outline, 'colors': [const Color(0xFF95A5A6), const Color(0xFF7F8C8D)]},
    ];

    return Column(
      children: [
        Row(
          children: cards.map((c) => Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: ar.spaceXS / 2),
              child: _gradientCard(
                title: c['title'],
                amount: (c['amount'] as num).toDouble(),
                count: c['count'],
                icon: c['icon'],
                colors: c['colors'],
              ),
            ),
          )).toList(),
        ),
        SizedBox(height: ar.spaceXS),
        _buildNetOwedCard(),
      ],
    );
  }

  Widget _gradientCard({
    required String title,
    required double amount,
    required dynamic count,
    required IconData icon,
    required List<Color> colors,
  }) {
    final ar = context.accR;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: ar.spaceM, vertical: ar.spaceS),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(ar.cardRadius),
        boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: ar.iconM),
          SizedBox(width: ar.spaceS),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: GoogleFonts.cairo(fontSize: ar.caption, color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w500)),
              Text('${_currencyFormat.format(amount)} د.ع',
                  style: GoogleFonts.cairo(fontSize: ar.small, color: Colors.white, fontWeight: FontWeight.bold)),
              Text('$count عملية', style: GoogleFonts.cairo(fontSize: ar.caption, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetOwedCard() {
    final ar = context.accR;
    final remainingCash = (_data?['remainingCash'] ?? 0).toDouble();
    final remainingCredit = (_data?['remainingCredit'] ?? 0).toDouble();
    final netOwed = (_data?['netOwed'] ?? 0).toDouble();
    final deliveredCash = (_data?['deliveredCash'] ?? 0).toDouble();
    final collectedCredit = (_data?['collectedCredit'] ?? 0).toDouble();
    final cashAmount = (_data?['cashAmount'] ?? 0).toDouble();
    final creditAmount = (_data?['creditAmount'] ?? 0).toDouble();
    final hasDebt = netOwed > 0;

    Widget netMiniCard(String title, List<({String label, double amount, bool bold})> items, List<Color> colors) {
      return Expanded(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: ar.spaceM, vertical: ar.spaceS),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(ar.cardRadius),
            boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: GoogleFonts.cairo(fontSize: ar.caption, fontWeight: FontWeight.bold, color: Colors.white)),
              SizedBox(height: ar.spaceXS),
              ...items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.label, style: GoogleFonts.cairo(fontSize: ar.caption, color: Colors.white.withValues(alpha: 0.85))),
                    Text('${_currencyFormat.format(item.amount)} د.ع',
                        style: GoogleFonts.cairo(fontSize: ar.caption, fontWeight: item.bold ? FontWeight.bold : FontWeight.w500, color: Colors.white)),
                  ],
                ),
              )),
            ],
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          netMiniCard('النقد', [
            (label: 'مُجمّع', amount: cashAmount, bold: false),
            (label: 'مُسلَّم', amount: deliveredCash, bold: false),
            (label: 'الباقي', amount: remainingCash, bold: true),
          ], [const Color(0xFF2ECC71), const Color(0xFF27AE60)]),
          SizedBox(width: ar.spaceXS),
          netMiniCard('الآجل', [
            (label: 'مُسجّل', amount: creditAmount, bold: false),
            (label: 'مُحصّل', amount: collectedCredit, bold: false),
            (label: 'الباقي', amount: remainingCredit, bold: true),
          ], [const Color(0xFFE67E22), const Color(0xFFD35400)]),
          SizedBox(width: ar.spaceXS),
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: ar.spaceM, vertical: ar.spaceS),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: hasDebt
                      ? [const Color(0xFFE74C3C), const Color(0xFFC0392B)]
                      : [const Color(0xFF27AE60), const Color(0xFF1E8449)],
                ),
                borderRadius: BorderRadius.circular(ar.cardRadius),
                boxShadow: [BoxShadow(
                  color: (hasDebt ? const Color(0xFFE74C3C) : const Color(0xFF27AE60)).withValues(alpha: 0.2),
                  blurRadius: 6, offset: const Offset(0, 2),
                )],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(hasDebt ? Icons.warning_amber_rounded : Icons.check_circle, color: Colors.white, size: ar.iconM),
                  SizedBox(width: ar.spaceS),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('المستحقة', style: GoogleFonts.cairo(fontSize: ar.caption, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text('${_currencyFormat.format(netOwed)} د.ع',
                          style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _netRow(String label, double amount, {bool bold = false}) {
    final ar = context.accR;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: GoogleFonts.cairo(fontSize: ar.caption, color: Colors.white.withValues(alpha: 0.8))),
          SizedBox(width: ar.spaceXS),
          Text('${_currencyFormat.format(amount)} د.ع',
              style: GoogleFonts.cairo(fontSize: ar.caption, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: Colors.white)),
        ],
      ),
    );
  }

  // ===== دوال مساعدة للجدول الديناميكي =====

  String _getStringValue(Map<String, dynamic> tx, String key) {
    switch (key) {
      case 'customerId': return tx['CustomerId']?.toString() ?? '';
      case 'customerName': return tx['CustomerName']?.toString() ?? '';
      case 'phone': return tx['PhoneNumber']?.toString() ?? '';
      case 'subscriptionId': return tx['SubscriptionId']?.toString() ?? '';
      case 'plan': return tx['PlanName']?.toString() ?? '';
      case 'amount': return (tx['PlanPrice'] ?? 0).toString();
      case 'pageDeduction': return (tx['PageDeduction'] ?? 0).toString();
      case 'revenue': return (tx['Revenue'] ?? 0).toString();
      case 'expense': return (tx['Expense'] ?? 0).toString();
      case 'commitment': return tx['CommitmentPeriod']?.toString() ?? '';
      case 'renewal': return tx['RenewalCycleMonths']?.toString() ?? '';
      case 'type':
        final t = (tx['OperationType'] ?? '').toString().toLowerCase();
        if (t.contains('renew')) return 'تجديد';
        if (t.contains('change')) return 'تغيير';
        if (t.contains('schedule')) return 'جدولة';
        return 'شراء';
      case 'collection':
        switch ((tx['CollectionType'] ?? '').toString().toLowerCase()) {
          case 'cash': return 'نقد';
          case 'credit': return 'آجل';
          case 'master': return 'ماستر';
          case 'agent': return 'وكيل';
          default: return tx['CollectionType']?.toString() ?? '';
        }
      case 'zone': return tx['ZoneName']?.toString() ?? tx['ZoneId']?.toString() ?? '';
      case 'technician': return tx['TechnicianName']?.toString() ?? '';
      case 'activatedBy': return tx['ActivatedBy']?.toString() ?? '';
      case 'date': return tx['ActivationDate']?.toString() ?? '';
      case 'startDate': return tx['StartDate']?.toString() ?? '';
      case 'endDate': return tx['EndDate']?.toString() ?? '';
      case 'status': return tx['CurrentStatus']?.toString() ?? '';
      case 'payment': return tx['PaymentStatus']?.toString() ?? tx['PaymentMethod']?.toString() ?? '';
      case 'walletBefore': return (tx['WalletBalanceBefore'] ?? '').toString();
      case 'walletAfter': return (tx['WalletBalanceAfter'] ?? '').toString();
      case 'device': return tx['DeviceUsername']?.toString() ?? '';
      case 'printed': return tx['IsPrinted'] == true ? 'نعم' : 'لا';
      case 'whatsapp': return tx['IsWhatsAppSent'] == true ? 'نعم' : 'لا';
      case 'reconciled': return tx['IsReconciled'] == true ? 'نعم' : 'لا';
      case 'accounting': return tx['JournalEntryId'] != null ? 'نعم' : 'لا';
      case 'notes': return tx['SubscriptionNotes']?.toString() ?? '';
      default: return '';
    }
  }

  dynamic _getSortValue(Map<String, dynamic> tx, String key) {
    switch (key) {
      case 'amount': return (tx['PlanPrice'] ?? 0).toDouble();
      case 'pageDeduction': return (tx['PageDeduction'] ?? 0).toDouble();
      case 'revenue': return (tx['Revenue'] ?? 0).toDouble();
      case 'expense': return (tx['Expense'] ?? 0).toDouble();
      case 'commitment': return (tx['CommitmentPeriod'] ?? 0).toDouble();
      case 'renewal': return (tx['RenewalCycleMonths'] ?? 0).toDouble();
      case 'walletBefore': return (tx['WalletBalanceBefore'] ?? 0).toDouble();
      case 'walletAfter': return (tx['WalletBalanceAfter'] ?? 0).toDouble();
      default: return _getStringValue(tx, key).toLowerCase();
    }
  }

  List<Map<String, dynamic>> _getProcessedTransactions() {
    var list = _transactions.map((e) => e as Map<String, dynamic>).toList();

    // بحث نصي
    if (_txSearchQuery.isNotEmpty) {
      final q = _txSearchQuery.toLowerCase();
      list = list.where((tx) {
        final name = (tx['CustomerName'] ?? '').toString().toLowerCase();
        final phone = (tx['PhoneNumber'] ?? '').toString().toLowerCase();
        final tech = (tx['TechnicianName'] ?? '').toString().toLowerCase();
        final zone = (tx['ZoneId'] ?? '').toString().toLowerCase();
        final subId = (tx['SubscriptionId'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q) || tech.contains(q) || zone.contains(q) || subId.contains(q);
      }).toList();
    }

    // تطبيق الفلاتر
    for (final entry in _columnFilters.entries) {
      if (entry.value.isEmpty) continue;
      final filterValue = entry.value.toLowerCase();
      list = list.where((tx) {
        final cellValue = _getStringValue(tx, entry.key).toLowerCase();
        return cellValue.contains(filterValue);
      }).toList();
    }

    // تطبيق الترتيب
    if (_sortKey != null) {
      list.sort((a, b) {
        final va = _getSortValue(a, _sortKey!);
        final vb = _getSortValue(b, _sortKey!);
        int cmp;
        if (va is num && vb is num) {
          cmp = va.compareTo(vb);
        } else {
          cmp = va.toString().compareTo(vb.toString());
        }
        return _sortAscending ? cmp : -cmp;
      });
    }

    return list;
  }

  DataCell _buildCell(String key, Map<String, dynamic> tx, int displayIndex) {
    final ar = context.accR;
    switch (key) {
      case 'index':
        return DataCell(Center(child: Text('${displayIndex + 1}', style: TextStyle(fontSize: ar.small, fontWeight: FontWeight.w600))));
      case 'customerId':
        return DataCell(Center(child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tx['CustomerId'] ?? '-', style: TextStyle(fontSize: ar.caption), overflow: TextOverflow.ellipsis),
            if (tx['CustomerId'] != null)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: tx['CustomerId']));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ'), duration: Duration(seconds: 1)));
                },
                child: Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.copy, size: ar.iconXS, color: Colors.grey.shade500)),
              ),
          ],
        )));
      case 'customerName':
        return DataCell(Center(child: Text(tx['CustomerName'] ?? '-', style: TextStyle(fontSize: ar.small), overflow: TextOverflow.ellipsis)));
      case 'phone':
        return DataCell(Center(child: Text(tx['PhoneNumber'] ?? '-', style: TextStyle(fontSize: ar.small))));
      case 'subscriptionId':
        return DataCell(Center(child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tx['SubscriptionId'] ?? '-', style: TextStyle(fontSize: ar.caption), overflow: TextOverflow.ellipsis),
            if (tx['SubscriptionId'] != null)
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: tx['SubscriptionId']));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ'), duration: Duration(seconds: 1)));
                },
                child: Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.copy, size: ar.iconXS, color: Colors.grey.shade500)),
              ),
          ],
        )));
      case 'plan':
        return DataCell(Center(child: Text(tx['PlanName'] ?? '-', style: TextStyle(fontSize: ar.small))));
      case 'amount':
        return DataCell(Center(child: Text(
          _currencyFormat.format((tx['PlanPrice'] ?? 0).toDouble()),
          style: TextStyle(fontSize: ar.small, fontWeight: FontWeight.w700, color: Colors.green.shade700),
        )));
      case 'pageDeduction':
        return DataCell(Center(child: Text(
          _currencyFormat.format((tx['PageDeduction'] ?? 0).toDouble()),
          style: TextStyle(fontSize: ar.small, fontWeight: FontWeight.w700),
        )));
      case 'revenue':
        final rev = (tx['Revenue'] ?? 0).toDouble();
        return DataCell(Center(child: Text(
          _currencyFormat.format(rev),
          style: TextStyle(fontSize: ar.small, fontWeight: FontWeight.w600,
              color: rev > 0 ? Colors.green.shade700 : Colors.grey.shade400),
        )));
      case 'expense':
        final exp = (tx['Expense'] ?? 0).toDouble();
        return DataCell(Center(child: Text(
          _currencyFormat.format(exp),
          style: TextStyle(fontSize: ar.small, fontWeight: FontWeight.w600,
              color: exp > 0 ? Colors.red.shade700 : Colors.grey.shade400),
        )));
      case 'commitment':
        return DataCell(Center(child: Text(
          tx['CommitmentPeriod'] != null ? '${tx['CommitmentPeriod']} شهر' : '-',
          style: TextStyle(fontSize: ar.small),
        )));
      case 'renewal':
        final cycle = tx['RenewalCycleMonths'] as int?;
        final paid = (tx['PaidMonths'] as num?)?.toInt() ?? 0;
        return DataCell(
          Center(child: Builder(builder: (_) {
            if (cycle == null || cycle <= 0) {
              return Icon(Icons.add_circle_outline, size: ar.iconS, color: Colors.grey.shade400);
            }
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: paid >= cycle ? Colors.green.shade50 : Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: paid >= cycle ? Colors.green.shade300 : Colors.deepPurple.shade300),
              ),
              child: Text('$paid/$cycle شهر', style: TextStyle(fontSize: ar.caption, fontWeight: FontWeight.w700, color: paid >= cycle ? Colors.green.shade700 : Colors.deepPurple.shade700)),
            );
          })),
          onTap: () => _showRenewalCycleDialog(tx),
        );
      case 'type':
        return DataCell(Center(child: _buildTypeBadge(tx['OperationType'] ?? '')));
      case 'collection':
        return DataCell(Center(child: _buildCollectionBadge(tx['CollectionType'] ?? '')));
      case 'zone':
        return DataCell(Center(child: Text(tx['ZoneName'] ?? tx['ZoneId'] ?? '-', style: TextStyle(fontSize: ar.small), overflow: TextOverflow.ellipsis)));
      case 'technician':
        return DataCell(Center(child: Text(tx['TechnicianName'] ?? '-', style: TextStyle(fontSize: ar.small))));
      case 'activatedBy':
        return DataCell(Center(child: Text(tx['ActivatedBy'] ?? '-', style: TextStyle(fontSize: ar.small), overflow: TextOverflow.ellipsis)));
      case 'date':
        return DataCell(Center(child: Text(_formatDate(tx['ActivationDate']), style: TextStyle(fontSize: ar.caption))));
      case 'startDate':
        return DataCell(Center(child: Text(tx['StartDate'] ?? '-', style: TextStyle(fontSize: ar.caption))));
      case 'endDate':
        return DataCell(Center(child: Text(tx['EndDate'] ?? '-', style: TextStyle(fontSize: ar.caption))));
      case 'status':
        return DataCell(Center(child: _buildStatusBadge(tx['CurrentStatus'] ?? '')));
      case 'payment':
        final payVal = tx['PaymentMethod']?.toString() ?? tx['PaymentStatus']?.toString() ?? '-';
        return DataCell(Center(child: _buildCollectionBadge(payVal)));
      case 'walletBefore':
        final wb = (tx['WalletBalanceBefore'] as num?)?.toDouble();
        return DataCell(Center(child: Text(wb != null ? _currencyFormat.format(wb) : '-', style: TextStyle(fontSize: ar.caption))));
      case 'walletAfter':
        final wa = (tx['WalletBalanceAfter'] as num?)?.toDouble();
        return DataCell(Center(child: Text(wa != null ? _currencyFormat.format(wa) : '-', style: TextStyle(fontSize: ar.caption))));
      case 'device':
        return DataCell(Center(child: Text(tx['DeviceUsername'] ?? '-', style: TextStyle(fontSize: ar.caption), overflow: TextOverflow.ellipsis)));
      case 'printed':
        return DataCell(Center(child: tx['IsPrinted'] == true
            ? Icon(Icons.print, size: ar.iconS, color: Colors.green.shade600)
            : Icon(Icons.print_disabled, size: ar.iconS, color: Colors.grey.shade400)));
      case 'whatsapp':
        return DataCell(Center(child: tx['IsWhatsAppSent'] == true
            ? Icon(Icons.check_circle, size: ar.iconS, color: Colors.green.shade600)
            : Icon(Icons.cancel_outlined, size: ar.iconS, color: Colors.grey.shade400)));
      case 'reconciled':
        return DataCell(Center(child: tx['IsReconciled'] == true
            ? Icon(Icons.check_circle, size: ar.iconS, color: Colors.green.shade600)
            : Icon(Icons.cancel_outlined, size: ar.iconS, color: Colors.grey.shade400)));
      case 'accounting':
        return DataCell(Center(child: tx['JournalEntryId'] != null
            ? Icon(Icons.check_circle, size: ar.iconS, color: Colors.green.shade600)
            : Icon(Icons.remove_circle_outline, size: ar.iconS, color: Colors.grey.shade400)));
      case 'notes':
        return DataCell(Center(child: Text(tx['SubscriptionNotes'] ?? '-', style: TextStyle(fontSize: ar.caption), overflow: TextOverflow.ellipsis)));
      case 'edit':
        return DataCell(Center(
          child: InkWell(
            onTap: () => _showEditTransactionDialog(tx),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit, size: 12, color: Colors.blue.shade700),
                  const SizedBox(width: 3),
                  Text('تعديل', style: TextStyle(fontSize: 10, color: Colors.blue.shade700, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ));
      default:
        return DataCell(Center(child: Text('-')));
    }
  }

  Widget _toolbarButton(IconData icon, String label, VoidCallback onTap, {bool highlighted = false, Color? color}) {
    final ar = context.accR;
    final c = color ?? (highlighted ? Colors.blue.shade700 : Colors.grey.shade600);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ar.btnRadius),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: ar.spaceS, vertical: ar.spaceXS),
        decoration: BoxDecoration(
          color: highlighted ? Colors.blue.shade50 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(ar.btnRadius),
          border: Border.all(color: highlighted ? Colors.blue.shade200 : Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: ar.iconS, color: c),
            SizedBox(width: ar.spaceXS),
            Text(label, style: GoogleFonts.cairo(fontSize: ar.small, color: c, fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _appBarButton(IconData icon, String label, VoidCallback onTap, {bool highlighted = false}) {
    final ar = context.accR;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: highlighted ? Colors.amber.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: highlighted ? Colors.amber.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: ar.iconXS, color: highlighted ? Colors.amber : Colors.white70),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.cairo(fontSize: ar.caption, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  // controllers للفلاتر في رأس الأعمدة
  final Map<String, TextEditingController> _headerFilterControllers = {};

  TextEditingController _getFilterCtrl(String key) {
    return _headerFilterControllers.putIfAbsent(key, () {
      final ctrl = TextEditingController(text: _columnFilters[key] ?? '');
      return ctrl;
    });
  }

  Widget _buildColumnLabel(String key) {
    final label = _columnLabels[key] ?? key;
    if (key == 'edit' || key == 'index') {
      return Expanded(child: Center(child: Text(label,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.accR.small, color: Colors.white),
          overflow: TextOverflow.ellipsis)));
    }
    final ctrl = _getFilterCtrl(key);
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: context.accR.small, color: Colors.white),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          SizedBox(
            height: 24,
            child: TextField(
              controller: ctrl,
              style: const TextStyle(fontSize: 10, color: Colors.white),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '...',
                hintStyle: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.4)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                filled: true,
                fillColor: Colors.white.withOpacity(0.15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
                suffixIcon: ctrl.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () { ctrl.clear(); setState(() => _columnFilters.remove(key)); },
                        child: Icon(Icons.close, size: 10, color: Colors.white.withOpacity(0.7)))
                    : null,
                suffixIconConstraints: const BoxConstraints(maxWidth: 16, maxHeight: 16),
              ),
              onChanged: (v) => setState(() {
                if (v.trim().isEmpty) {
                  _columnFilters.remove(key);
                } else {
                  _columnFilters[key] = v.trim();
                }
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsTable() {
    final processed = _getProcessedTransactions();
    final visibleKeys = _columnKeys.where((k) => k == 'edit' || _visibleColumns.contains(k)).toList();
    final activeFilterCount = _columnFilters.values.where((v) => v.isNotEmpty).length;

    if (_transactions.isEmpty) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(context.accR.spaceXXL),
          child: Center(
            child: Text('لا توجد عمليات', style: TextStyle(color: Colors.grey.shade500)),
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
          // حقل البحث
          Padding(
            padding: EdgeInsets.fromLTRB(context.accR.spaceL, context.accR.spaceS, context.accR.spaceL, 0),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _txSearchController,
                onChanged: (v) => setState(() => _txSearchQuery = v.trim()),
                style: GoogleFonts.cairo(fontSize: 12),
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  hintText: 'بحث عن عميل، هاتف، فني، وكيل، منطقة...',
                  hintStyle: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
                  suffixIcon: _txSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          onPressed: () {
                            _txSearchController.clear();
                            setState(() => _txSearchQuery = '');
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.black, width: 1.5)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.black, width: 1.5)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blue, width: 2)),
                ),
              ),
            ),
          ),
          // عدد النتائج المفلترة
          if (activeFilterCount > 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.accR.spaceL, vertical: 4),
              child: Row(children: [
                Icon(Icons.filter_alt, size: 14, color: Colors.blue.shade700),
                const SizedBox(width: 4),
                Text('${processed.length} نتيجة من ${_transactions.length}', style: GoogleFonts.cairo(fontSize: 11, color: Colors.blue.shade700)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() { _columnFilters.clear(); _headerFilterControllers.forEach((_, c) => c.clear()); }),
                  icon: const Icon(Icons.clear_all, size: 14),
                  label: Text('مسح الكل', style: GoogleFonts.cairo(fontSize: 11)),
                  style: TextButton.styleFrom(foregroundColor: Colors.red.shade600, padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                ),
              ]),
            ),
          if (processed.isEmpty)
            Padding(
              padding: EdgeInsets.all(context.accR.spaceXXL),
              child: Center(child: Text('لا توجد نتائج مطابقة', style: TextStyle(color: Colors.grey.shade500))),
            )
          else
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    showCheckboxColumn: false,
                    sortColumnIndex: _sortKey != null && visibleKeys.contains(_sortKey)
                        ? visibleKeys.indexOf(_sortKey!)
                        : null,
                    sortAscending: _sortAscending,
                    border: TableBorder.all(color: Colors.grey.shade300, width: 0.5),
                    headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3E50)),
                    headingRowHeight: 56,
                    dataRowMinHeight: context.accR.tableRowMinH,
                    dataRowMaxHeight: context.accR.tableRowMaxH,
                    columnSpacing: 0,
                    horizontalMargin: context.accR.spaceS,
                    columns: [
                      ...visibleKeys.map((key) {
                        return DataColumn(
                          label: _buildColumnLabel(key),
                          onSort: (key == 'index' || key == 'edit') ? null : (_, __) {
                            setState(() {
                              if (_sortKey == key) {
                                if (!_sortAscending) {
                                  _sortKey = null;
                                  _sortAscending = true;
                                } else {
                                  _sortAscending = false;
                                }
                              } else {
                                _sortKey = key;
                                _sortAscending = true;
                              }
                            });
                          },
                        );
                      }),
                    ],
                    rows: processed.asMap().entries.map((entry) {
                      final i = entry.key;
                      final tx = entry.value;
                      return DataRow(
                        color: WidgetStateProperty.resolveWith<Color?>((states) {
                          if (states.contains(WidgetState.hovered)) return Colors.blue.shade50;
                          return i.isEven ? Colors.white : Colors.grey.shade50;
                        }),
                        cells: visibleKeys.map((key) => _buildCell(key, tx, i)).toList(),
                      );
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
    if (lower.contains('renew') || lower.contains('تجديد')) {
      label = 'تجديد';
      bgColor = Colors.blue.shade50;
      txtColor = Colors.blue.shade700;
    } else if (lower.contains('schedule') || lower.contains('جدولة')) {
      label = 'جدولة';
      bgColor = Colors.purple.shade50;
      txtColor = Colors.purple.shade700;
    } else if (lower.contains('change') || lower.contains('تغيير')) {
      label = 'تغيير';
      bgColor = Colors.orange.shade50;
      txtColor = Colors.orange.shade700;
    } else if (lower.contains('purchase') || lower.contains('شراء')) {
      label = 'شراء';
      bgColor = Colors.teal.shade50;
      txtColor = Colors.teal.shade700;
    } else {
      label = type.isNotEmpty ? type : 'تجديد';
      bgColor = Colors.grey.shade50;
      txtColor = Colors.grey.shade700;
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
      case 'technician':
      case 'فني':
        color = Colors.teal;
        label = 'فني';
        break;
      case 'نقد':
        color = Colors.green;
        label = 'نقد';
        break;
      case 'آجل':
        color = Colors.orange;
        label = 'آجل';
        break;
      case 'وكيل':
        color = Colors.blue;
        label = 'وكيل';
        break;
      case 'ماستر':
        color = Colors.purple;
        label = 'ماستر';
        break;
      case 'محفظة':
        color = Colors.green;
        label = 'محفظة';
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
      final dt = DateTime.parse(date.toString()).toLocal();
      return DateFormat('yyyy/MM/dd', 'ar').format(dt);
    } catch (_) {
      return date.toString();
    }
  }

  // ===== نافذة اختيار الأعمدة =====
  void _showColumnSelectorDialog() {
    final tempVisible = Set<String>.from(_visibleColumns);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: EdgeInsets.all(context.accR.spaceL),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF3498DB)]),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.view_column, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('اختيار الأعمدة', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: context.accR.body)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        if (tempVisible.length == _columnKeys.length) {
                          tempVisible.clear();
                          tempVisible.add('index');
                        } else {
                          tempVisible.addAll(_columnKeys);
                        }
                      });
                    },
                    child: Text(
                      tempVisible.length == _columnKeys.length ? 'إلغاء الكل' : 'تحديد الكل',
                      style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: min(400, MediaQuery.of(context).size.width * 0.85),
              height: min(500, MediaQuery.of(context).size.height * 0.6),
              child: ListView(
                children: _columnKeys.map((key) {
                  return CheckboxListTile(
                    title: Text(_columnLabels[key] ?? key, style: GoogleFonts.cairo(fontSize: 14)),
                    value: tempVisible.contains(key),
                    activeColor: const Color(0xFF3498DB),
                    onChanged: (val) {
                      setDialogState(() {
                        if (val == true) {
                          tempVisible.add(key);
                        } else if (tempVisible.length > 1) {
                          tempVisible.remove(key);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actionsPadding: EdgeInsets.all(context.accR.spaceM),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade600)),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() => _visibleColumns = tempVisible);
                  _saveColumns();
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('تطبيق', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===== نافذة التصفية =====
  void _showFilterDialog() {
    final tempFilters = Map<String, String>.from(_columnFilters);
    final filterableKeys = _columnKeys.where((k) => k != 'index').toList();
    final controllers = <String, TextEditingController>{};
    for (final key in filterableKeys) {
      controllers[key] = TextEditingController(text: tempFilters[key] ?? '');
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: EdgeInsets.zero,
            title: Container(
              padding: EdgeInsets.all(context.accR.spaceL),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF3498DB)]),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_list, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('تصفية البيانات', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.bold, fontSize: context.accR.body)),
                  const Spacer(),
                  if (tempFilters.values.any((v) => v.isNotEmpty))
                    TextButton(
                      onPressed: () {
                        setDialogState(() {
                          tempFilters.clear();
                          for (final c in controllers.values) {
                            c.clear();
                          }
                        });
                      },
                      child: Text('مسح الكل', style: GoogleFonts.cairo(color: Colors.white70, fontSize: 12)),
                    ),
                ],
              ),
            ),
            content: SizedBox(
              width: min(550, MediaQuery.of(context).size.width * 0.85),
              height: min(500, MediaQuery.of(context).size.height * 0.6),
              child: ListView.builder(
                itemCount: filterableKeys.length,
                itemBuilder: (ctx, i) {
                  final key = filterableKeys[i];
                  final label = _columnLabels[key] ?? key;

                  // جمع القيم الفريدة
                  final uniqueValues = <String>{};
                  for (final t in _transactions) {
                    final v = _getStringValue(t as Map<String, dynamic>, key);
                    if (v.isNotEmpty && v != '-' && v != '0' && v != '0.0') {
                      uniqueValues.add(v);
                    }
                  }
                  final sortedValues = uniqueValues.toList()..sort();
                  final hasValue = (tempFilters[key] ?? '').isNotEmpty;

                  // إذا عدد القيم قليل → dropdown، وإلا → text field
                  if (sortedValues.isNotEmpty && sortedValues.length <= 12) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 85,
                            child: Text(label, style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: hasValue ? FontWeight.bold : FontWeight.w500,
                              color: hasValue ? Colors.blue.shade700 : Colors.grey.shade700,
                            )),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: sortedValues.contains(tempFilters[key]) ? tempFilters[key] : null,
                              isExpanded: true,
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: hasValue ? Colors.blue.shade300 : Colors.grey.shade300),
                                ),
                              ),
                              hint: Text('الكل', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                              items: sortedValues.map((v) => DropdownMenuItem(
                                value: v,
                                child: Text(v, style: GoogleFonts.cairo(fontSize: 12), overflow: TextOverflow.ellipsis),
                              )).toList(),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == null || val.isEmpty) {
                                    tempFilters.remove(key);
                                  } else {
                                    tempFilters[key] = val;
                                  }
                                });
                              },
                            ),
                          ),
                          if (hasValue)
                            IconButton(
                              icon: Icon(Icons.close, size: 16, color: Colors.red.shade400),
                              onPressed: () => setDialogState(() => tempFilters.remove(key)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            ),
                        ],
                      ),
                    );
                  } else {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 85,
                            child: Text(label, style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: hasValue ? FontWeight.bold : FontWeight.w500,
                              color: hasValue ? Colors.blue.shade700 : Colors.grey.shade700,
                            )),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controllers[key],
                              style: GoogleFonts.cairo(fontSize: 12),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: hasValue ? Colors.blue.shade300 : Colors.grey.shade300),
                                ),
                                hintText: 'اكتب للتصفية...',
                                hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                              ),
                              onChanged: (val) => tempFilters[key] = val,
                            ),
                          ),
                          if (hasValue)
                            IconButton(
                              icon: Icon(Icons.close, size: 16, color: Colors.red.shade400),
                              onPressed: () {
                                controllers[key]!.clear();
                                setDialogState(() => tempFilters.remove(key));
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            ),
                        ],
                      ),
                    );
                  }
                },
              ),
            ),
            actionsPadding: EdgeInsets.all(context.accR.spaceM),
            actions: [
              TextButton(
                onPressed: () {
                  for (final c in controllers.values) { c.dispose(); }
                  Navigator.pop(ctx);
                },
                child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade600)),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _columnFilters.clear();
                    for (final entry in tempFilters.entries) {
                      if (entry.value.trim().isNotEmpty) {
                        _columnFilters[entry.key] = entry.value.trim();
                      }
                    }
                  });
                  for (final c in controllers.values) { c.dispose(); }
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('تطبيق', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// دايلوق تعديل بيانات المعاملة
  void _showEditTransactionDialog(Map<String, dynamic> tx) {
    final logId = tx['Id']?.toString() ?? tx['id']?.toString();
    if (logId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن التعديل - معرف السجل غير متوفر'), backgroundColor: Colors.red),
      );
      return;
    }

    final ar = context.accR;
    // controllers لكل الحقول
    final customerNameCtrl = TextEditingController(text: tx['CustomerName']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: tx['PhoneNumber']?.toString() ?? '');
    final planNameCtrl = TextEditingController(text: tx['PlanName']?.toString() ?? '');
    final planPriceCtrl = TextEditingController(text: (tx['PlanPrice'] ?? 0).toString());
    final commitmentCtrl = TextEditingController(text: tx['CommitmentPeriod']?.toString() ?? '');
    final activatedByCtrl = TextEditingController(text: tx['ActivatedBy']?.toString() ?? '');
    final zoneCtrl = TextEditingController(text: tx['ZoneId']?.toString() ?? '');
    final techNameCtrl = TextEditingController(text: tx['TechnicianName']?.toString() ?? '');
    final paymentMethodCtrl = TextEditingController(text: tx['PaymentMethod']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: tx['SubscriptionNotes']?.toString() ?? '');
    final reconcNotesCtrl = TextEditingController(text: tx['ReconciliationNotes']?.toString() ?? '');
    final basePriceCtrl = TextEditingController(text: (tx['BasePrice'] ?? 0).toString());
    final compDiscountCtrl = TextEditingController(text: (tx['CompanyDiscount'] ?? 0).toString());
    final manDiscountCtrl = TextEditingController(text: (tx['ManualDiscount'] ?? 0).toString());
    final maintFeeCtrl = TextEditingController(text: (tx['MaintenanceFee'] ?? 0).toString());
    final renewMonthsCtrl = TextEditingController(text: (tx['RenewalCycleMonths'] ?? 0).toString());
    final paidMonthsCtrl = TextEditingController(text: (tx['PaidMonths'] ?? 0).toString());

    String collectionType = (tx['CollectionType'] ?? '').toString().toLowerCase();
    String operationType = (tx['OperationType'] ?? '').toString();
    String paymentStatus = (tx['PaymentStatus'] ?? '').toString();
    bool isPrinted = tx['IsPrinted'] == true;
    bool isWhatsApp = tx['IsWhatsAppSent'] == true;
    bool isReconciled = tx['IsReconciled'] == true;
    String? linkedTechId = tx['LinkedTechnicianId']?.toString();
    String? linkedAgentId = tx['LinkedAgentId']?.toString();

    // تاريخ التفعيل
    DateTime activationDate = (() {
      try {
        final p = DateTime.parse(tx['ActivationDate']?.toString() ?? '');
        return p.isUtc ? p.toLocal() : p;
      } catch (_) { return DateTime.now(); }
    })();

    bool isSaving = false;
    List<Map<String, dynamic>> techList = [];
    List<Map<String, dynamic>> agentList = [];
    bool listsLoaded = false;

    final collectionOptions = [
      {'value': '', 'label': 'غير محدد'},
      {'value': 'cash', 'label': 'نقد'},
      {'value': 'credit', 'label': 'آجل'},
      {'value': 'master', 'label': 'ماستر'},
      {'value': 'agent', 'label': 'وكيل'},
      {'value': 'technician', 'label': 'فني'},
    ];

    final opTypeValues = ['تجديد', 'شراء', 'تغيير', 'جدولة', 'purchase', 'renewal', 'change'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          // جلب الفنيين/الوكلاء مرة واحدة
          if (!listsLoaded) {
            listsLoaded = true;
            AccountingService.instance.getTechniciansList(companyId: _companyId).then((list) {
              if (ctx.mounted) setDialogState(() => techList = list);
            });
            AccountingService.instance.getAgentsList(companyId: _companyId).then((list) {
              if (ctx.mounted) setDialogState(() => agentList = list);
            });
          }

          Widget sectionTitle(String title) => Padding(
            padding: EdgeInsets.only(top: ar.spaceM, bottom: ar.spaceXS),
            child: Text(title, style: GoogleFonts.cairo(fontSize: ar.small, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
          );

          InputDecoration fieldDeco(String hint) => InputDecoration(
            filled: true, fillColor: Colors.white, hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF3498DB), width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            isDense: true,
          );

          Widget fieldRow(String label, Widget child) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 100, child: Text(label, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
                Expanded(child: child),
              ],
            ),
          );

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: SizedBox(
                width: min(600, MediaQuery.of(context).size.width * 0.9),
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
                  children: [
                    // العنوان
                    Container(
                      padding: EdgeInsets.all(ar.spaceM),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF3498DB)]),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.edit_note, color: Colors.white, size: 22),
                          SizedBox(width: ar.spaceS),
                          Text('تعديل المعاملة', style: GoogleFonts.cairo(fontSize: ar.body, fontWeight: FontWeight.bold, color: Colors.white)),
                          const Spacer(),
                          InkWell(onTap: () => Navigator.pop(ctx), child: const Icon(Icons.close, color: Colors.white70, size: 20)),
                        ],
                      ),
                    ),
                    // المحتوى
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(ar.spaceM),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ═══ بيانات العميل ═══
                            sectionTitle('بيانات العميل'),
                            fieldRow('اسم العميل', TextField(controller: customerNameCtrl, style: GoogleFonts.cairo(fontSize: 12), decoration: fieldDeco('اسم العميل'))),
                            fieldRow('الهاتف', TextField(controller: phoneCtrl, style: GoogleFonts.cairo(fontSize: 12), decoration: fieldDeco('رقم الهاتف'))),

                            // ═══ بيانات الاشتراك ═══
                            sectionTitle('بيانات الاشتراك'),
                            fieldRow('الباقة', TextField(controller: planNameCtrl, style: GoogleFonts.cairo(fontSize: 12), decoration: fieldDeco('اسم الباقة'))),
                            fieldRow('السعر', TextField(controller: planPriceCtrl, readOnly: true, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700), decoration: fieldDeco('سعر الباقة').copyWith(filled: true, fillColor: Colors.green.shade50))),
                            fieldRow('الالتزام', TextField(controller: commitmentCtrl, style: GoogleFonts.cairo(fontSize: 12), decoration: fieldDeco('فترة الالتزام'))),
                            fieldRow('نوع العملية', Wrap(
                              spacing: 6,
                              children: ['تجديد', 'شراء', 'تغيير', 'جدولة'].map((v) => ChoiceChip(
                                label: Text(v, style: GoogleFonts.cairo(fontSize: 11)),
                                selected: operationType == v || operationType.toLowerCase() == v.toLowerCase(),
                                onSelected: (_) => setDialogState(() => operationType = v),
                                selectedColor: Colors.blue.shade100,
                                visualDensity: VisualDensity.compact,
                              )).toList(),
                            )),
                            fieldRow('المنفذ', TextField(controller: activatedByCtrl, style: GoogleFonts.cairo(fontSize: 12), decoration: fieldDeco('منفذ العملية'))),
                            fieldRow('التاريخ', InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(context: ctx, initialDate: activationDate, firstDate: DateTime(2024), lastDate: DateTime.now().add(const Duration(days: 1)), locale: const Locale('ar'));
                                if (picked != null) setDialogState(() => activationDate = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8), color: Colors.white),
                                child: Row(children: [
                                  Text('${activationDate.year}/${activationDate.month.toString().padLeft(2,'0')}/${activationDate.day.toString().padLeft(2,'0')}', style: GoogleFonts.cairo(fontSize: 12)),
                                  const Spacer(),
                                  Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                                ]),
                              ),
                            )),
                            fieldRow('المنطقة', TextField(controller: zoneCtrl, style: GoogleFonts.cairo(fontSize: 12), decoration: fieldDeco('معرف المنطقة'))),

                            // ═══ التحصيل والربط ═══
                            sectionTitle('التحصيل والربط'),
                            fieldRow('نوع التحصيل', Wrap(
                              spacing: 6,
                              children: [
                                {'value': 'cash', 'label': 'نقد'},
                                {'value': 'credit', 'label': 'آجل'},
                                {'value': 'technician', 'label': 'فني'},
                                {'value': 'agent', 'label': 'وكيل'},
                                {'value': 'master', 'label': 'ماستر'},
                              ].map((o) => ChoiceChip(
                                label: Text(o['label']!, style: GoogleFonts.cairo(fontSize: 11)),
                                selected: collectionType == o['value'],
                                onSelected: (_) => setDialogState(() {
                                  collectionType = o['value']!;
                                  linkedTechId = null;
                                  linkedAgentId = null;
                                  paymentMethodCtrl.text = o['label']!;
                                  if (o['value'] != 'technician') techNameCtrl.clear();
                                }),
                                selectedColor: Colors.blue.shade100,
                                visualDensity: VisualDensity.compact,
                              )).toList(),
                            )),
                            // اختيار فني — بحث وتصفية
                            if (collectionType == 'technician')
                              _buildSearchableField(
                                label: 'الفني',
                                hint: 'ابحث عن فني...',
                                list: techList,
                                selectedId: linkedTechId,
                                fieldDeco: fieldDeco,
                                fieldRow: fieldRow,
                                onSelected: (id, name) => setDialogState(() {
                                  linkedTechId = id;
                                  techNameCtrl.text = name;
                                }),
                                onClear: () => setDialogState(() {
                                  linkedTechId = null;
                                  techNameCtrl.clear();
                                }),
                                setDialogState: setDialogState,
                              ),
                            // اختيار وكيل — بحث وتصفية
                            if (collectionType == 'agent')
                              _buildSearchableField(
                                label: 'الوكيل',
                                hint: 'ابحث عن وكيل...',
                                list: agentList,
                                selectedId: linkedAgentId,
                                fieldDeco: fieldDeco,
                                fieldRow: fieldRow,
                                onSelected: (id, name) => setDialogState(() {
                                  linkedAgentId = id;
                                  techNameCtrl.text = name;
                                }),
                                onClear: () => setDialogState(() {
                                  linkedAgentId = null;
                                  techNameCtrl.clear();
                                }),
                                setDialogState: setDialogState,
                              ),
                            fieldRow('حالة الدفع', TextField(
                              controller: TextEditingController(text: paymentStatus),
                              style: GoogleFonts.cairo(fontSize: 12),
                              decoration: fieldDeco('مسدد / غير مسدد'),
                              onChanged: (v) => paymentStatus = v,
                            )),
                            fieldRow('طريقة الدفع', TextField(controller: paymentMethodCtrl, style: GoogleFonts.cairo(fontSize: 12), decoration: fieldDeco('طريقة الدفع'))),

                            // ═══ الحالات ═══
                            sectionTitle('الحالات'),
                            Row(
                              children: [
                                Expanded(child: SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('طباعة', style: GoogleFonts.cairo(fontSize: 12)), value: isPrinted, onChanged: (v) => setDialogState(() => isPrinted = v))),
                                Expanded(child: SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('واتساب', style: GoogleFonts.cairo(fontSize: 12)), value: isWhatsApp, onChanged: (v) => setDialogState(() => isWhatsApp = v))),
                                Expanded(child: SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('مطابقة', style: GoogleFonts.cairo(fontSize: 12)), value: isReconciled, onChanged: (v) => setDialogState(() => isReconciled = v))),
                              ],
                            ),

                            // ═══ محاسبية ═══
                            sectionTitle('بيانات محاسبية'),
                            fieldRow('السعر الأساسي', TextField(controller: basePriceCtrl, style: GoogleFonts.cairo(fontSize: 12), keyboardType: TextInputType.number, decoration: fieldDeco('سعر الباقة من جدول الأسعار'),
                              onChanged: (_) => setDialogState(() {
                                final base = double.tryParse(basePriceCtrl.text) ?? 0;
                                final compDisc = double.tryParse(compDiscountCtrl.text) ?? 0;
                                final manDisc = double.tryParse(manDiscountCtrl.text) ?? 0;
                                final maint = double.tryParse(maintFeeCtrl.text) ?? 0;
                                planPriceCtrl.text = (base - compDisc - manDisc + maint).toStringAsFixed(0);
                              }),
                            )),
                            fieldRow('خصم الشركة', TextField(controller: compDiscountCtrl, style: GoogleFonts.cairo(fontSize: 12), keyboardType: TextInputType.number, decoration: fieldDeco('0'),
                              onChanged: (_) => setDialogState(() {
                                final base = double.tryParse(basePriceCtrl.text) ?? 0;
                                final compDisc = double.tryParse(compDiscountCtrl.text) ?? 0;
                                final manDisc = double.tryParse(manDiscountCtrl.text) ?? 0;
                                final maint = double.tryParse(maintFeeCtrl.text) ?? 0;
                                planPriceCtrl.text = (base - compDisc - manDisc + maint).toStringAsFixed(0);
                              }),
                            )),
                            fieldRow('خصم يدوي', TextField(controller: manDiscountCtrl, style: GoogleFonts.cairo(fontSize: 12), keyboardType: TextInputType.number, decoration: fieldDeco('0'),
                              onChanged: (_) => setDialogState(() {
                                final base = double.tryParse(basePriceCtrl.text) ?? 0;
                                final compDisc = double.tryParse(compDiscountCtrl.text) ?? 0;
                                final manDisc = double.tryParse(manDiscountCtrl.text) ?? 0;
                                final maint = double.tryParse(maintFeeCtrl.text) ?? 0;
                                planPriceCtrl.text = (base - compDisc - manDisc + maint).toStringAsFixed(0);
                              }))),
                            fieldRow('رسوم صيانة', TextField(controller: maintFeeCtrl, style: GoogleFonts.cairo(fontSize: 12), keyboardType: TextInputType.number, decoration: fieldDeco('0'),
                              onChanged: (_) => setDialogState(() {
                                final base = double.tryParse(basePriceCtrl.text) ?? 0;
                                final compDisc = double.tryParse(compDiscountCtrl.text) ?? 0;
                                final manDisc = double.tryParse(manDiscountCtrl.text) ?? 0;
                                final maint = double.tryParse(maintFeeCtrl.text) ?? 0;
                                planPriceCtrl.text = (base - compDisc - manDisc + maint).toStringAsFixed(0);
                              }))),

                            // ═══ تكرار ═══
                            sectionTitle('التكرار'),
                            fieldRow('أشهر التكرار', TextField(controller: renewMonthsCtrl, style: GoogleFonts.cairo(fontSize: 12), keyboardType: TextInputType.number, decoration: fieldDeco('0'))),
                            fieldRow('أشهر مدفوعة', TextField(controller: paidMonthsCtrl, style: GoogleFonts.cairo(fontSize: 12), keyboardType: TextInputType.number, decoration: fieldDeco('0'))),

                            // ═══ ملاحظات ═══
                            sectionTitle('ملاحظات'),
                            TextField(controller: notesCtrl, style: GoogleFonts.cairo(fontSize: 12), maxLines: 2, decoration: fieldDeco('ملاحظات الاشتراك')),
                            const SizedBox(height: 8),
                            TextField(controller: reconcNotesCtrl, style: GoogleFonts.cairo(fontSize: 12), maxLines: 2, decoration: fieldDeco('ملاحظات المطابقة')),
                          ],
                        ),
                      ),
                    ),
                    // الأزرار
                    Container(
                      padding: EdgeInsets.all(ar.spaceM),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('إلغاء', style: GoogleFonts.cairo(color: Colors.grey.shade600))),
                          SizedBox(width: ar.spaceS),
                          ElevatedButton(
                            onPressed: isSaving ? null : () async {
                              setDialogState(() => isSaving = true);
                              try {
                                // مطابقة الفني من الاسم إذا لم يُختر من القائمة
                                if (collectionType == 'technician' && linkedTechId == null) {
                                  final searchName = techNameCtrl.text.trim();
                                  if (searchName.isNotEmpty && techList.isNotEmpty) {
                                    final match = techList.where((t) => (t['name'] ?? t['Name'] ?? '').toString().contains(searchName) || searchName.contains((t['name'] ?? t['Name'] ?? '').toString())).firstOrNull;
                                    if (match != null) linkedTechId = match['id']?.toString();
                                  }
                                  // إذا ما زال null، نبحث بالاسم القديم من المعاملة
                                  if (linkedTechId == null) {
                                    final origName = tx['TechnicianName']?.toString() ?? '';
                                    if (origName.isNotEmpty && techList.isNotEmpty) {
                                      final match = techList.where((t) => (t['name'] ?? t['Name'] ?? '') == origName).firstOrNull;
                                      if (match != null) linkedTechId = match['id']?.toString();
                                    }
                                  }
                                }
                                // مطابقة الوكيل
                                if (collectionType == 'agent' && linkedAgentId == null && agentList.isNotEmpty) {
                                  final searchName = techNameCtrl.text.trim();
                                  if (searchName.isNotEmpty) {
                                    final match = agentList.where((a) => (a['name'] ?? a['Name'] ?? '').toString().contains(searchName)).firstOrNull;
                                    if (match != null) linkedAgentId = match['id']?.toString();
                                  }
                                }
                                debugPrint('📝 Save: collType=$collectionType, techId=$linkedTechId, techName=${techNameCtrl.text}');
                                final fields = <String, dynamic>{
                                  'CustomerName': customerNameCtrl.text.trim(),
                                  'PhoneNumber': phoneCtrl.text.trim(),
                                  'PlanName': planNameCtrl.text.trim(),
                                  'PlanPrice': double.tryParse(planPriceCtrl.text) ?? 0,
                                  'CommitmentPeriod': int.tryParse(commitmentCtrl.text.trim()) ?? 0,
                                  'OperationType': operationType,
                                  'ActivatedBy': activatedByCtrl.text.trim(),
                                  'ActivationDate': activationDate.toIso8601String(),
                                  'ZoneId': zoneCtrl.text.trim(),
                                  'CollectionType': collectionType,
                                  'TechnicianName': techNameCtrl.text.trim(),
                                  'PaymentStatus': paymentStatus,
                                  'PaymentMethod': paymentMethodCtrl.text.trim().isNotEmpty
                                      ? paymentMethodCtrl.text.trim()
                                      : const {'cash': 'نقد', 'credit': 'آجل', 'technician': 'فني', 'agent': 'وكيل', 'master': 'ماستر'}[collectionType] ?? collectionType,
                                  'IsPrinted': isPrinted,
                                  'IsWhatsAppSent': isWhatsApp,
                                  'IsReconciled': isReconciled,
                                  'ReconciliationNotes': reconcNotesCtrl.text.trim(),
                                  'SubscriptionNotes': notesCtrl.text.trim(),
                                  'BasePrice': double.tryParse(basePriceCtrl.text) ?? 0,
                                  'CompanyDiscount': double.tryParse(compDiscountCtrl.text) ?? 0,
                                  'ManualDiscount': double.tryParse(manDiscountCtrl.text) ?? 0,
                                  'MaintenanceFee': double.tryParse(maintFeeCtrl.text) ?? 0,
                                  'RenewalCycleMonths': int.tryParse(renewMonthsCtrl.text) ?? 0,
                                  'PaidMonths': int.tryParse(paidMonthsCtrl.text) ?? 0,
                                };
                                // دائماً أرسل الفني والوكيل — إزالة القيم الفارغة لتجنب خطأ Guid parsing
                                if (linkedTechId != null && linkedTechId!.isNotEmpty) {
                                  fields['LinkedTechnicianId'] = linkedTechId;
                                }
                                fields['HasLinkedTechnicianId'] = true;
                                if (linkedAgentId != null && linkedAgentId!.isNotEmpty) {
                                  fields['LinkedAgentId'] = linkedAgentId;
                                }
                                fields['HasLinkedAgentId'] = true;
                                debugPrint('📝 Saving logId=$logId, CollectionType=${fields['CollectionType']}, LinkedTech=${fields['LinkedTechnicianId']}');
                                final result = await AccountingService.instance.updateSubscriptionLog(logId: int.parse(logId.toString()), fields: fields);
                                debugPrint('📝 Result: ${result['success']} - ${result['message']}');
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                if (result['success'] == true) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تحديث المعاملة بنجاح'), backgroundColor: Colors.green.shade600, duration: const Duration(seconds: 2)));
                                  _loadData();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result['message'] ?? 'خطأ في التحديث'), backgroundColor: Colors.red.shade600));
                                }
                              } catch (e) {
                                setDialogState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red.shade600));
                              }
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10)),
                            child: isSaving
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : Text('حفظ', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// صف معلومة في dialog التعديل
  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Text('$label: ',
              style: GoogleFonts.cairo(
                fontSize: context.accR.caption,
                color: Colors.grey.shade600,
              )),
          Expanded(
            child: Text(value,
                style: GoogleFonts.cairo(
                  fontSize: context.accR.caption,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
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
          content: Text('خطأ'),
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

/// ويدجت بحث قابل للتصفية — يستخدم بدلاً من DropdownButtonFormField
class _SearchableDropdownField extends StatefulWidget {
  final String hint;
  final List<Map<String, dynamic>> items;
  final String selectedName;
  final InputDecoration Function(String) fieldDeco;
  final void Function(String? id, String name) onSelected;
  final VoidCallback onClear;

  const _SearchableDropdownField({
    required this.hint,
    required this.items,
    required this.selectedName,
    required this.fieldDeco,
    required this.onSelected,
    required this.onClear,
  });

  @override
  State<_SearchableDropdownField> createState() => _SearchableDropdownFieldState();
}

class _SearchableDropdownFieldState extends State<_SearchableDropdownField> {
  late TextEditingController _ctrl;
  bool _showList = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.selectedName);
    _query = '';
  }

  @override
  void didUpdateWidget(covariant _SearchableDropdownField old) {
    super.didUpdateWidget(old);
    if (old.selectedName != widget.selectedName) {
      _ctrl.text = widget.selectedName;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return widget.items.where((i) {
      final name = (i['name'] ?? i['Name'] ?? '').toString().toLowerCase();
      return name.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 45,
          child: TextField(
            controller: _ctrl,
            style: GoogleFonts.cairo(fontSize: 12, color: Colors.black),
            decoration: widget.fieldDeco(widget.hint).copyWith(
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() {
                          _query = '';
                          _showList = false;
                        });
                        widget.onClear();
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  : const Icon(Icons.search, size: 16, color: Colors.grey),
            ),
            onTap: () => setState(() => _showList = true),
            onChanged: (v) => setState(() {
              _query = v.trim();
              _showList = true;
            }),
          ),
        ),
        if (_showList && _filtered.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final item = _filtered[i];
                final name = item['name'] ?? item['Name'] ?? '';
                final isSelected = item['id']?.toString() == widget.selectedName;
                return InkWell(
                  onTap: () {
                    _ctrl.text = name;
                    setState(() {
                      _showList = false;
                      _query = '';
                    });
                    widget.onSelected(item['id']?.toString(), name);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: isSelected ? const Color(0xFF3498DB).withValues(alpha: 0.1) : null,
                    child: Text(name, style: GoogleFonts.cairo(fontSize: 12)),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

