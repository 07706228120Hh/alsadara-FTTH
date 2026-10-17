import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme/accounting_responsive.dart';
import '../../services/api/api_config.dart';

import '../../frontend/tokens/sd_colors.dart' show SdColors;
/// صفحة تقارير التسديدات اليومية — عرض للمحاسب
class SettlementReportsPage extends StatefulWidget {
  final String? companyId;
  const SettlementReportsPage({super.key, this.companyId});

  @override
  State<SettlementReportsPage> createState() => _SettlementReportsPageState();
}

class _SettlementReportsPageState extends State<SettlementReportsPage> {
  static String get _vpsBaseUrl => '${ApiConfig.vpsBaseUrl}/api/internal';
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
        const SnackBar(content: Text('المبلغ المستلم يجب أن يكون أكبر من صفر'), backgroundColor: SdColors.danger));
      return;
    }
    setState(() => _isPosting = true);
    try {
      final result = await _apiPost('settlement-reports/$reportId/accountant-post', {'receivedAmount': amount});
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'تم الترحيل بنجاح'), backgroundColor: SdColors.success));
        await _loadReports(); // تحديث البيانات
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'فشل الترحيل'), backgroundColor: SdColors.danger));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: SdColors.danger));
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
        backgroundColor: SdColors.ground,
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
        color: SdColors.surface,
        border: Border(bottom: BorderSide(color: SdColors.divider)),
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
              gradient: const LinearGradient(colors: [SdColors.accent, SdColors.accent]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.receipt_long, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('تقارير التسديدات اليومية',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold, color: SdColors.ink)),
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
        color: SdColors.surface,
        border: Border(bottom: BorderSide(color: SdColors.divider)),
      ),
      child: isMob
          ? Column(
              children: [
                // فلتر المشغل
                DropdownButtonFormField<String>(
                  value: _filterOperator,
                  isDense: true,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.black87),
                  decoration: InputDecoration(
                    labelText: 'المشغل',
                    labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
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
                            labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            suffixIcon: const Icon(Icons.calendar_today, size: 16),
                          ),
                          child: Text(_filterFrom != null ? fmt.format(_filterFrom!) : 'الكل',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
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
                            labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            suffixIcon: const Icon(Icons.calendar_today, size: 16),
                          ),
                          child: Text(_filterTo != null ? fmt.format(_filterTo!) : 'الكل',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
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
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'المشغل',
                labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
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
                  labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: const Icon(Icons.calendar_today, size: 16),
                ),
                child: Text(_filterFrom != null ? fmt.format(_filterFrom!) : 'الكل',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
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
                  labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: const Icon(Icons.calendar_today, size: 16),
                ),
                child: Text(_filterTo != null ? fmt.format(_filterTo!) : 'الكل',
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
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
                  child: _statCard('نقد النظام', '${fmt.format(_totalSystemCash)} د.ع', Icons.attach_money, SdColors.success, expanded: false),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 22) / 2,
                  child: _statCard('المصاريف', '${fmt.format(_totalExpenses)} د.ع', Icons.remove_circle_outline, SdColors.warningEdge, expanded: false),
                ),
                SizedBox(
                  width: (MediaQuery.of(context).size.width - 22) / 2,
                  child: _statCard('النقد الصافي', '${fmt.format(_totalNetCash)} د.ع', Icons.account_balance_wallet, SdColors.info, expanded: false),
                ),
              ],
            )
          : IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statCard('التقارير', '$_totalReports', Icons.description, const Color(0xFF880E4F)),
            const SizedBox(width: 6),
            _statCard('نقد النظام', '${fmt.format(_totalSystemCash)} د.ع', Icons.attach_money, SdColors.success),
            const SizedBox(width: 6),
            _statCard('المصاريف', '${fmt.format(_totalExpenses)} د.ع', Icons.remove_circle_outline, SdColors.warningEdge),
            const SizedBox(width: 6),
            _statCard('النقد الصافي', '${fmt.format(_totalNetCash)} د.ع', Icons.account_balance_wallet, SdColors.info),
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
                  Text(title, style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
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
      return Center(child: Text(_error!, style: TextStyle(fontFamily: 'Cairo', color: SdColors.danger)));
    }
    if (_reports.isEmpty) {
      return Center(child: Text('لا توجد تقارير', style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint, fontSize: 16)));
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
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SdColors.divider),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: hasJournal ? SdColors.success : SdColors.faint,
            child: Icon(hasJournal ? Icons.check : Icons.hourglass_empty, color: Colors.white, size: 18),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(operatorName, style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              if (extractedDelivery.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: SdColors.infoTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SdColors.infoTintEdge),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_pin, size: 14, color: SdColors.info),
                      const SizedBox(width: 4),
                      Text('← $extractedDelivery', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: SdColors.info)),
                    ],
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              Icon(Icons.calendar_today, size: 12, color: SdColors.faint),
              const SizedBox(width: 4),
              Text(dateDisplay, style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: SdColors.muted)),
              const Spacer(),
              Text('صافي: ', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: SdColors.muted)),
              Text('${fmt.format(netCash)} د.ع',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w900, color: SdColors.success)),
            ],
          ),
          children: [
            // ═══ 1. حساب المشغل ═══
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: SdColors.primaryTint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SdColors.primaryTintEdge),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance, size: 18, color: SdColors.primary),
                  const SizedBox(width: 8),
                  Text('صندوق المشغل: ', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: SdColors.primary)),
                  Expanded(
                    child: Text('صندوق $operatorName (1110)',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: SdColors.primaryEdge)),
                  ),
                  if (sysTotal > 0)
                    Text('إجمالي: ${fmt.format(sysTotal)} د.ع',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: SdColors.primary)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ═══ 2. تفاصيل الاشتراكات (6 بطاقات) ═══
            if (sysTotal > 0) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: SdColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SdColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('تفاصيل اشتراكات اليوم', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: SdColors.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _miniCard('إجمالي', sysTotal, fmt, const Color(0xFF880E4F)),
                        _miniCard('نقد', sysCash, fmt, SdColors.success),
                        _miniCard('آجل', sysCredit, fmt, SdColors.warningEdge),
                        _miniCard('ماستر', sysMaster, fmt, SdColors.platformEdge),
                        _miniCard('وكيل', sysAgent, fmt, SdColors.info),
                        _miniCard('فني', sysTech, fmt, SdColors.accent),
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
                  border: Border.all(color: SdColors.edge),
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: SdColors.warningTint,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(width: 24, child: Center(child: Text('ت', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: Center(child: Text('المبلغ', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 8),
                          Expanded(flex: 2, child: Center(child: Text('الصنف', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)))),
                          const SizedBox(width: 8),
                          Expanded(flex: 3, child: Center(child: Text('التفاصيل', style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)))),
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
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: SdColors.divider))),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(width: 24, child: Center(child: Text('${idx + 1}', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)))),
                            const SizedBox(width: 8),
                            Expanded(flex: 2, child: Center(child: Text('${fmt.format(amount)} د.ع', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)))),
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
                                      style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: _categoryColor(category), fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(flex: 3, child: Text(note, style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: SdColors.muted))),
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
                color: SdColors.successTint,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SdColors.successTintEdge),
              ),
              child: Row(
                children: [
                  _summaryChip('نقد النظام', sysCash, fmt, SdColors.success, Icons.attach_money),
                  if (totalExpenses > 0) ...[
                    const SizedBox(width: 8),
                    _summaryChip('المصاريف', -totalExpenses, fmt, SdColors.warning, Icons.remove_circle_outline),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: SdColors.successTint,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            Icon(Icons.account_balance_wallet, size: 16, color: SdColors.successEdge),
                            const SizedBox(width: 4),
                            Text('النقد الصافي', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w900, color: SdColors.successEdge)),
                          ]),
                          Text('${fmt.format(netCash)} د.ع',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w900, color: SdColors.successEdge)),
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
                  color: SdColors.infoTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SdColors.infoTintEdge),
                ),
                child: Row(
                  children: [
                    Icon(Icons.payments, size: 18, color: SdColors.info),
                    const SizedBox(width: 8),
                    Text('المبلغ المستلم', style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12, fontWeight: FontWeight.bold, color: SdColors.info)),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _receivedAmountControllers[reportId],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold, color: SdColors.infoEdge),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixText: 'د.ع',
                          suffixStyle: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: SdColors.faint),
                        ),
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: _isPosting ? null : () => _postReport(report),
                      icon: Icon(_isPosting ? Icons.hourglass_empty : Icons.send, size: 16),
                      label: Text(_isPosting ? 'جاري...' : 'ترحيل',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SdColors.success,
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
                  color: SdColors.successTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SdColors.successTintEdge),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 18, color: SdColors.success),
                    const SizedBox(width: 8),
                    Text('تم الترحيل — المبلغ المستلم: ',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w600, color: SdColors.success)),
                    Text('${fmt.format(receivedAmount > 0 ? receivedAmount : netCash)} د.ع',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w900, color: SdColors.successEdge)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ═══ 5. القيد المحاسبي ═══
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasJournal ? SdColors.accentTint : SdColors.groundAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hasJournal ? SdColors.accentTintEdge : SdColors.edge),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(hasJournal ? Icons.check_circle : Icons.cancel,
                          size: 16, color: hasJournal ? SdColors.accent : SdColors.faint),
                      const SizedBox(width: 6),
                      Text(hasJournal ? 'القيد المحاسبي' : 'بدون قيد محاسبي',
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold,
                              color: hasJournal ? SdColors.accent : SdColors.faint)),
                    ],
                  ),
                  if (hasJournal && netCash > 0) ...[
                    const SizedBox(height: 8),
                    // سطر Debit
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: SdColors.infoTint, borderRadius: BorderRadius.circular(4)),
                          child: Text('مدين', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: SdColors.info)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('صندوق $extractedDelivery',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: SdColors.accent))),
                        Text('${fmt.format(netCash)} د.ع',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: SdColors.info)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // سطر Credit
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: SdColors.dangerTint, borderRadius: BorderRadius.circular(4)),
                          child: Text('دائن', style: TextStyle(fontFamily: 'Cairo', fontSize: 10, fontWeight: FontWeight.bold, color: SdColors.danger)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text('صندوق $operatorName',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: SdColors.accent))),
                        Text('${fmt.format(netCash)} د.ع',
                            style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold, color: SdColors.danger)),
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
                  Icon(Icons.notes, size: 14, color: SdColors.faint),
                  const SizedBox(width: 6),
                  Expanded(child: Text(displayNotes, style: TextStyle(fontFamily: 'Cairo', fontSize: 11, color: SdColors.muted))),
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
          Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 9, fontWeight: FontWeight.w600, color: color)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value > 0 ? fmt.format(value) : '0',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.w900, color: color)),
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
              Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ]),
            Text('${fmt.format(value)} د.ع',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold, color: color)),
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
        Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: size, color: color, fontWeight: bold ? FontWeight.w900 : FontWeight.w600)),
        const Spacer(),
        Text('${fmt.format(value)} د.ع',
            style: TextStyle(fontFamily: 'Cairo', fontSize: size + 1, fontWeight: bold ? FontWeight.w900 : FontWeight.bold, color: color)),
      ],
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'مصاريف': return SdColors.warning;
      case 'أخرى': return SdColors.muted;
      default: return SdColors.platformBase;
    }
  }
}
