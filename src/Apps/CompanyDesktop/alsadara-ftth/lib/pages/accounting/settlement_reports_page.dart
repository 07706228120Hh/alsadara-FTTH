import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة تقارير التسديدات اليومية — عرض للمحاسب
class SettlementReportsPage extends StatefulWidget {
  final String? companyId;
  const SettlementReportsPage({super.key, this.companyId});

  @override
  State<SettlementReportsPage> createState() => _SettlementReportsPageState();
}

class _SettlementReportsPageState extends State<SettlementReportsPage> {
  static const String _vpsBaseUrl = 'https://api.ramzalsadara.tech/api/internal';
  static const String _vpsApiKey = 'sadara-internal-2024-secure-key';

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = [];
  List<String> _operators = ['الكل'];
  String _filterOperator = 'الكل';
  DateTime? _filterFrom;
  DateTime? _filterTo;

  // إحصائيات
  double _totalNetCash = 0;
  double _totalExpenses = 0;
  double _totalSystemCash = 0;
  int _totalReports = 0;

  // controllers للمبلغ المستلم (مفتاح = report Id)
  final Map<int, TextEditingController> _receivedAmountControllers = {};
  bool _isPosting = false;

  @override
  void dispose() {
    for (final c in _receivedAmountControllers.values) { c.dispose(); }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // افتراضي: آخر 7 أيام
    _filterTo = DateTime.now();
    _filterFrom = DateTime.now().subtract(const Duration(days: 7));
    _loadReports();
  }

  Future<dynamic> _apiGet(String path) async {
    final client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
    final request = await client.getUrl(Uri.parse('$_vpsBaseUrl/$path'));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json');
    request.headers.set('X-Api-Key', _vpsApiKey);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    if (response.statusCode != 200) throw Exception('خطأ: ${response.statusCode}');
    return json.decode(body);
  }

  Future<dynamic> _apiPost(String path, Map<String, dynamic> data) async {
    final client = HttpClient()..badCertificateCallback = (cert, host, port) => true;
    final request = await client.postUrl(Uri.parse('$_vpsBaseUrl/$path'));
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Accept', 'application/json');
    request.headers.set('X-Api-Key', _vpsApiKey);
    request.add(utf8.encode(json.encode(data)));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    client.close();
    return json.decode(body);
  }

  Future<void> _postReport(Map<String, dynamic> report) async {
    final reportId = report['Id'] ?? report['id'];
    final ctrl = _receivedAmountControllers[reportId];
    final amount = double.tryParse(ctrl?.text.replaceAll(',', '') ?? '') ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ المستلم يجب أن يكون أكبر من صفر'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _isPosting = true);
    try {
      final result = await _apiPost('settlement-reports/$reportId/accountant-post', {'receivedAmount': amount});
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'تم الترحيل بنجاح'), backgroundColor: Colors.green));
        await _loadReports(); // تحديث البيانات
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'فشل الترحيل'), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _isPosting = false);
  }

  Future<void> _loadReports() async {
    // مسح controllers القديمة عند إعادة التحميل
    for (final c in _receivedAmountControllers.values) { c.dispose(); }
    _receivedAmountControllers.clear();
    setState(() { _isLoading = true; _error = null; });
    try {
      String path = 'settlement-reports?pageSize=5000';
      if (_filterFrom != null) path += '&fromDate=${DateFormat('yyyy-MM-dd').format(_filterFrom!)}';
      if (_filterTo != null) path += '&toDate=${DateFormat('yyyy-MM-dd').format(_filterTo!)}';
      if (_filterOperator != 'الكل') path += '&operatorName=${Uri.encodeComponent(_filterOperator)}';

      final result = await _apiGet(path);
      if (result is List) {
        _reports = result.map((r) => Map<String, dynamic>.from(r)).toList();
        // جمع أسماء المشغلين
        final ops = <String>{'الكل'};
        for (final r in _reports) {
          final name = (r['OperatorName'] ?? r['operatorName'] ?? '').toString();
          if (name.isNotEmpty) ops.add(name);
        }
        _operators = ops.toList();
        _computeStats();
      }
    } catch (e) {
      _error = 'خطأ في جلب التقارير: $e';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _computeStats() {
    _totalNetCash = 0;
    _totalExpenses = 0;
    _totalSystemCash = 0;
    _totalReports = _reports.length;
    for (final r in _reports) {
      _totalNetCash += _toDouble(r['NetCashAmount'] ?? r['netCashAmount']);
      _totalExpenses += _toDouble(r['TotalExpenses'] ?? r['totalExpenses']);
      _totalSystemCash += _toDouble(r['SystemCashTotal'] ?? r['systemCashTotal']);
    }
  }

  double _toDouble(dynamic v) => (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(),
              _buildFilters(),
              _buildStatsRow(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final ar = context.accR;
    final isMob = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : ar.spaceL, vertical: isMob ? 6 : ar.spaceM),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_forward_rounded, size: 22),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF16A085), Color(0xFF1ABC9C)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('تقارير التسديدات اليومية',
                style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.bold, color: AccountingTheme.textPrimary)),
          ),
          IconButton(
            onPressed: _loadReports,
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final fmt = DateFormat('yyyy/MM/dd');
    final isMob = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: isMob
          ? Column(
              children: [
                // فلتر المشغل
                DropdownButtonFormField<String>(
                  value: _filterOperator,
                  isDense: true,
                  style: GoogleFonts.cairo(fontSize: 13, color: Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'المشغل',
                    labelStyle: GoogleFonts.cairo(fontSize: 12),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: _operators.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                  onChanged: (v) { _filterOperator = v ?? 'الكل'; _loadReports(); },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _filterFrom ?? DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) { _filterFrom = picked; _loadReports(); }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'من',
                            labelStyle: GoogleFonts.cairo(fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            suffixIcon: const Icon(Icons.calendar_today, size: 16),
                          ),
                          child: Text(_filterFrom != null ? fmt.format(_filterFrom!) : 'الكل',
                              style: GoogleFonts.cairo(fontSize: 13)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _filterTo ?? DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) { _filterTo = picked; _loadReports(); }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'إلى',
                            labelStyle: GoogleFonts.cairo(fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            suffixIcon: const Icon(Icons.calendar_today, size: 16),
                          ),
                          child: Text(_filterTo != null ? fmt.format(_filterTo!) : 'الكل',
                              style: GoogleFonts.cairo(fontSize: 13)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
        children: [
          // فلتر المشغل
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              value: _filterOperator,
              isDense: true,
              style: GoogleFonts.cairo(fontSize: 13, color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'المشغل',
                labelStyle: GoogleFonts.cairo(fontSize: 12),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: _operators.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) { _filterOperator = v ?? 'الكل'; _loadReports(); },
            ),
          ),
          const SizedBox(width: 12),
          // من تاريخ
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _filterFrom ?? DateTime.now(),
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (picked != null) { _filterFrom = picked; _loadReports(); }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'من',
                  labelStyle: GoogleFonts.cairo(fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: const Icon(Icons.calendar_today, size: 16),
                ),
                child: Text(_filterFrom != null ? fmt.format(_filterFrom!) : 'الكل',
                    style: GoogleFonts.cairo(fontSize: 13)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // إلى تاريخ
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _filterTo ?? DateTime.now(),
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (picked != null) { _filterTo = picked; _loadReports(); }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'إلى',
                  labelStyle: GoogleFonts.cairo(fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: const Icon(Icons.calendar_today, size: 16),
                ),
                child: Text(_filterTo != null ? fmt.format(_filterTo!) : 'الكل',
                    style: GoogleFonts.cairo(fontSize: 13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final fmt = NumberFormat('#,###');
    final isMob = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 16, vertical: 8),
      child: isMob
          ? Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 22) / 2,
                  child: _statCard('التقارير', '$_totalReports', Icons.description, const Color(0xFF880E4F), expanded: false),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 22) / 2,
                  child: _statCard('نقد النظام', '${fmt.format(_totalSystemCash)} د.ع', Icons.attach_money, const Color(0xFF2E7D32), expanded: false),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 22) / 2,
                  child: _statCard('المصاريف', '${fmt.format(_totalExpenses)} د.ع', Icons.remove_circle_outline, const Color(0xFFE65100), expanded: false),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 22) / 2,
                  child: _statCard('النقد الصافي', '${fmt.format(_totalNetCash)} د.ع', Icons.account_balance_wallet, const Color(0xFF1565C0), expanded: false),
                ),
              ],
            )
          : IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statCard('التقارير', '$_totalReports', Icons.description, const Color(0xFF880E4F)),
            const SizedBox(width: 6),
            _statCard('نقد النظام', '${fmt.format(_totalSystemCash)} د.ع', Icons.attach_money, const Color(0xFF2E7D32)),
            const SizedBox(width: 6),
            _statCard('المصاريف', '${fmt.format(_totalExpenses)} د.ع', Icons.remove_circle_outline, const Color(0xFFE65100)),
            const SizedBox(width: 6),
            _statCard('النقد الصافي', '${fmt.format(_totalNetCash)} د.ع', Icons.account_balance_wallet, const Color(0xFF1565C0)),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color, {bool expanded = true}) {
    final content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, color.withOpacity(0.8)]),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black26),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(title, style: GoogleFonts.cairo(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: GoogleFonts.cairo(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    if (expanded) return Expanded(child: content);
    return content;
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: GoogleFonts.cairo(color: Colors.red)));
    }
    if (_reports.isEmpty) {
      return Center(child: Text('لا توجد تقارير', style: GoogleFonts.cairo(color: Colors.grey, fontSize: 16)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _reports.length,
      itemBuilder: (ctx, i) => _buildReportCard(_reports[i]),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final fmt = NumberFormat('#,###');
    final operatorName = report['OperatorName'] ?? report['operatorName'] ?? '';
    final reportDate = report['ReportDate'] ?? report['reportDate'] ?? '';
    final deliveredTo = report['DeliveredToName'] ?? report['deliveredToName'] ?? '';
    final notes = (report['Notes'] ?? report['notes'] ?? '').toString();
    final hasJournal = report['JournalEntryId'] != null || report['journalEntryId'] != null;

    // parse items
    final itemsStr = report['ItemsJson'] ?? report['itemsJson'] ?? '[]';
    List<dynamic> items = [];
    try { items = json.decode(itemsStr); } catch (_) {}

    // استخراج اسم المستلم من الملاحظات
    String displayNotes = notes;
    String extractedDelivery = deliveredTo;
    if (notes.startsWith('[تسليم:')) {
      final endIdx = notes.indexOf(']');
      if (endIdx > 0) {
        if (extractedDelivery.isEmpty) extractedDelivery = notes.substring(7, endIdx).trim();
        displayNotes = notes.substring(endIdx + 1).trim();
      }
    }

    // بيانات النظام
    final sysTotal = _toDouble(report['SystemTotal'] ?? report['systemTotal']);
    final sysCash = _toDouble(report['SystemCashTotal'] ?? report['systemCashTotal']);
    final sysCredit = _toDouble(report['SystemCreditTotal'] ?? report['systemCreditTotal']);
    final sysMaster = _toDouble(report['SystemMasterTotal'] ?? report['systemMasterTotal']);
    final sysTech = _toDouble(report['SystemTechTotal'] ?? report['systemTechTotal']);
    final sysAgent = _toDouble(report['SystemAgentTotal'] ?? report['systemAgentTotal']);
    final totalExpenses = _toDouble(report['TotalExpenses'] ?? report['totalExpenses']);
    final netCash = _toDouble(report['NetCashAmount'] ?? report['netCashAmount']);
    final receivedAmount = _toDouble(report['ReceivedAmount'] ?? report['receivedAmount']);
    final reportId = (report['Id'] ?? report['id']) as int;

    // تهيئة controller المبلغ المستلم
    if (!_receivedAmountControllers.containsKey(reportId)) {
      final defaultVal = receivedAmount > 0 ? receivedAmount : netCash;
      _receivedAmountControllers[reportId] = TextEditingController(
          text: defaultVal > 0 ? fmt.format(defaultVal) : '');
    }

    // تاريخ مُنسّق
    String dateDisplay = reportDate;
    try {
      final dt = DateTime.parse(reportDate).toLocal();
      dateDisplay = DateFormat('yyyy/MM/dd (E)', 'ar').format(dt);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AccountingTheme.borderColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: hasJournal ? const Color(0xFF2E7D32) : Colors.grey.shade400,
            child: Icon(hasJournal ? Icons.check : Icons.hourglass_empty, color: Colors.white, size: 18),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(operatorName, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              if (extractedDelivery.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_pin, size: 14, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Text('← $extractedDelivery', style: GoogleFonts.cairo(fontSize: 11, color: Colors.blue.shade700)),
                    ],
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(dateDisplay, style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600)),
              const Spacer(),
              Text('صافي: ', style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade600)),
              Text('${fmt.format(netCash)} د.ع',
                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w900, color: const Color(0xFF2E7D32))),
            ],
          ),
          children: [
            // ═══ 1. حساب المشغل ═══
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance, size: 18, color: Colors.indigo.shade700),
                  const SizedBox(width: 8),
                  Text('صندوق المشغل: ', style: GoogleFonts.cairo(fontSize: 12, color: Colors.indigo.shade700)),
                  Expanded(
                    child: Text('صندوق $operatorName (1110)',
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                  ),
                  if (sysTotal > 0)
                    Text('إجمالي: ${fmt.format(sysTotal)} د.ع',
                        style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ═══ 2. تفاصيل الاشتراكات (6 بطاقات) ═══
            if (sysTotal > 0) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تفاصيل اشتراكات اليوم', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _miniCard('إجمالي', sysTotal, fmt, const Color(0xFF880E4F)),
                        _miniCard('نقد', sysCash, fmt, const Color(0xFF2E7D32)),
                        _miniCard('آجل', sysCredit, fmt, const Color(0xFFE65100)),
                        _miniCard('ماستر', sysMaster, fmt, const Color(0xFF4A148C)),
                        _miniCard('وكيل', sysAgent, fmt, const Color(0xFF1565C0)),
                        _miniCard('فني', sysTech, fmt, const Color(0xFF00695C)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ═══ 3. البنود (مصاريف/أخرى) ═══
            if (items.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: Colors.orange.shade50,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(width: 24, child: Center(child: Text('ت', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: Center(child: Text('المبلغ', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: Center(child: Text('الصنف', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 8),
                          Expanded(flex: 3, child: Center(child: Text('التفاصيل', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold)))),
                        ],
                      ),
                    ),
                    ...items.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final item = entry.value;
                      final note = item['note'] ?? '';
                      final amount = _toDouble(item['amount']);
                      final category = item['category'] ?? '';
                      return Container(
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(width: 24, child: Center(child: Text('${idx + 1}', style: GoogleFonts.cairo(fontSize: 11)))),
                            const SizedBox(width: 8),
                            Expanded(flex: 2, child: Center(child: Text('${fmt.format(amount)} د.ع', style: GoogleFonts.cairo(fontSize: 11)))),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _categoryColor(category).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(category.isEmpty ? '-' : category,
                                      style: GoogleFonts.cairo(fontSize: 11, color: _categoryColor(category), fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(flex: 3, child: Text(note, style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700))),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ═══ 4. ملخص مالي: نقد → مصاريف → صافي ═══
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  _summaryChip('نقد النظام', sysCash, fmt, Colors.green.shade800, Icons.attach_money),
                  if (totalExpenses > 0) ...[
                    const SizedBox(width: 8),
                    _summaryChip('المصاريف', -totalExpenses, fmt, Colors.orange.shade800, Icons.remove_circle_outline),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(Icons.account_balance_wallet, size: 16, color: Colors.green.shade900),
                            const SizedBox(width: 4),
                            Text('النقد الصافي', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.green.shade900)),
                          ]),
                          Text('${fmt.format(netCash)} د.ع',
                              style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.green.shade900)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ═══ 4.5 المبلغ المستلم + زر ترحيل ═══
            if (!hasJournal) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.payments, size: 18, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Text('المبلغ المستلم', style: GoogleFonts.cairo(
                        fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _receivedAmountControllers[reportId],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixText: 'د.ع',
                          suffixStyle: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
                        ),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _isPosting ? null : () => _postReport(report),
                      icon: Icon(_isPosting ? Icons.hourglass_empty : Icons.send, size: 16),
                      label: Text(_isPosting ? 'جاري...' : 'ترحيل',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text('تم الترحيل — المبلغ المستلم: ',
                        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
                    Text('${fmt.format(receivedAmount > 0 ? receivedAmount : netCash)} د.ع',
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.green.shade900)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ═══ 5. القيد المحاسبي ═══
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasJournal ? Colors.teal.shade50 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hasJournal ? Colors.teal.shade300 : Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(hasJournal ? Icons.check_circle : Icons.cancel,
                          size: 16, color: hasJournal ? Colors.teal.shade700 : Colors.grey),
                      const SizedBox(width: 6),
                      Text(hasJournal ? 'القيد المحاسبي' : 'بدون قيد محاسبي',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold,
                              color: hasJournal ? Colors.teal.shade800 : Colors.grey)),
                    ],
                  ),
                  if (hasJournal && netCash > 0) ...[
                    const SizedBox(height: 8),
                    // سطر Debit
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                          child: Text('مدين', style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('صندوق $extractedDelivery',
                            style: GoogleFonts.cairo(fontSize: 11, color: Colors.teal.shade800))),
                        Text('${fmt.format(netCash)} د.ع',
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // سطر Credit
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                          child: Text('دائن', style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('صندوق $operatorName',
                            style: GoogleFonts.cairo(fontSize: 11, color: Colors.teal.shade800))),
                        Text('${fmt.format(netCash)} د.ع',
                            style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ملاحظات
            if (displayNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.notes, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(child: Text(displayNotes, style: GoogleFonts.cairo(fontSize: 11, color: Colors.grey.shade700))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniCard(String label, double value, NumberFormat fmt, Color color) {
    // Calculate width to fit 3 per row on mobile, 6 on desktop
    final screenW = MediaQuery.of(context).size.width;
    final cardW = screenW < 600 ? (screenW - 72) / 3 : (screenW - 100) / 6;
    return Container(
      width: cardW.clamp(60, 140),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value > 0 ? fmt.format(value) : '0',
                style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w900, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, double value, NumberFormat fmt, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ]),
            Text('${fmt.format(value)} د.ع',
                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double value, NumberFormat fmt, Color color, IconData icon, {bool bold = false, double size = 12}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: GoogleFonts.cairo(fontSize: size, color: color, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
        const Spacer(),
        Text('${fmt.format(value)} د.ع',
            style: GoogleFonts.cairo(fontSize: size + 1, fontWeight: bold ? FontWeight.w900 : FontWeight.bold, color: color)),
      ],
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'مصاريف': return Colors.orange.shade700;
      case 'أخرى': return Colors.grey.shade600;
      default: return Colors.deepPurple;
    }
  }
}
