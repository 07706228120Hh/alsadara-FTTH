import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

class SystemAuditPage extends StatefulWidget {
  final String? companyId;
  const SystemAuditPage({super.key, this.companyId});
  @override
  State<SystemAuditPage> createState() => _SystemAuditPageState();
}

class _SystemAuditPageState extends State<SystemAuditPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _summary;
  List<dynamic> _issues = [];
  late TabController _tabCtrl;
  String _filterSeverity = 'all';

  // تبويبات
  static const _tabs = [
    _TabDef('الكل', Icons.list_alt, null),
    _TabDef('قيود غير متزنة', Icons.balance,
        {'UnbalancedEntry', 'EntryLineMismatch', 'InsufficientLines'}),
    _TabDef('قيود يتيمة', Icons.link_off, {'OrphanEntry', 'DuplicateEntry'}),
    _TabDef('عمليات بدون قيد', Icons.receipt_long, {
      'SalaryNoEntry',
      'CashTxNoEntry',
      'CollectionNoEntry',
      'FixedExpenseNoEntry',
      'ExpenseNoEntry',
      'FtthNoEntry'
    }),
    _TabDef('أرصدة', Icons.account_balance_wallet, {
      'CashBoxMismatch',
      'CashBoxAccountMismatch',
      'NegativeCashBox',
      'TechBalanceMismatch',
      'AgentBalanceMismatch',
      'SuspiciousBalance',
      'ExpenseAmountMismatch'
    }),
    _TabDef('أخرى', Icons.more_horiz,
        {'VoidedCashNoReverse', 'StaleSalary', 'LeafWithChildren'}),
  ];

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) setState(() {});
    });
    _runAudit();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _runAudit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final cid = _companyId.isNotEmpty ? _companyId : null;
      final result = await AccountingService.instance.runAudit(companyId: cid);
      if (result['success'] == true) {
        final data =
            result['data'] is Map<String, dynamic> ? result['data'] : result;
        setState(() {
          _summary = data['summary'] as Map<String, dynamic>?;
          _issues = (data['issues'] is List) ? data['issues'] : [];
        });
      } else {
        setState(() => _errorMessage = result['message'] ?? 'خطأ');
      }
    } catch (e) {
      setState(() => _errorMessage = 'خطأ في الاتصال: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<dynamic> get _filteredIssues {
    final tab = _tabs[_tabCtrl.index];
    return _issues.where((i) {
      if (tab.categories != null && !tab.categories!.contains(i['category']))
        return false;
      if (_filterSeverity != 'all' && i['severity'] != _filterSeverity)
        return false;
      return true;
    }).toList();
  }

  int _countForTab(int idx) {
    final tab = _tabs[idx];
    if (tab.categories == null) return _issues.length;
    return _issues.where((i) => tab.categories!.contains(i['category'])).length;
  }

  void _filterBySeverity(String severity) {
    setState(() {
      _filterSeverity = _filterSeverity == severity ? 'all' : severity;
    });
  }

  Color _severityColor(String s) => switch (s) {
        'critical' => const Color(0xFFE53935),
        'high' => const Color(0xFFFF6F00),
        'medium' => const Color(0xFFFFA726),
        'warning' => const Color(0xFF42A5F5),
        _ => Colors.grey,
      };
  IconData _severityIcon(String s) => switch (s) {
        'critical' => Icons.error,
        'high' => Icons.warning_amber_rounded,
        'medium' => Icons.info_outline,
        'warning' => Icons.lightbulb_outline,
        _ => Icons.help_outline,
      };
  String _severityLabel(String s) => switch (s) {
        'critical' => 'حرج',
        'high' => 'عالي',
        'medium' => 'متوسط',
        'warning' => 'تنبيه',
        _ => s,
      };
  String _categoryLabel(String c) => switch (c) {
        'UnbalancedEntry' => 'قيد غير متوازن',
        'CashBoxMismatch' => 'خلل رصيد صندوق',
        'CashBoxAccountMismatch' => 'صندوق ≠ حساب',
        'VoidedCashNoReverse' => 'إلغاء بدون عكس',
        'ExpenseNoEntry' => 'مصروف بدون قيد',
        'ExpenseAmountMismatch' => 'مصروف ≠ قيد',
        'TechBalanceMismatch' => 'خلل رصيد فني',
        'FtthNoEntry' => 'FTTH بدون قيد',
        'SuspiciousBalance' => 'رصيد مشبوه',
        'OrphanEntry' => 'قيد بدون معاملة',
        'SalaryNoEntry' => 'راتب بدون قيد',
        'CashTxNoEntry' => 'عملية صندوق بدون قيد',
        'CollectionNoEntry' => 'تحصيل بدون قيد',
        'FixedExpenseNoEntry' => 'مصروف ثابت بدون قيد',
        'NegativeCashBox' => 'صندوق سالب',
        'DuplicateEntry' => 'قيد مكرر',
        'EntryLineMismatch' => 'أسطر ≠ إجمالي',
        'InsufficientLines' => 'قيد ناقص الأسطر',
        'AgentBalanceMismatch' => 'خلل رصيد وكيل',
        'StaleSalary' => 'راتب معلق قديم',
        'LeafWithChildren' => 'حساب leaf له أبناء',
        _ => c,
      };
  String _fieldLabel(String k) => switch (k) {
        'entryNumber' => 'رقم القيد',
        'entryId' => 'معرّف القيد',
        'date' => 'التاريخ',
        'difference' => 'الفرق',
        'cashBoxId' => 'معرّف الصندوق',
        'cashBoxName' => 'اسم الصندوق',
        'storedBalance' => 'الرصيد المخزن',
        'computedBalance' => 'الرصيد المحسوب',
        'accountCode' => 'كود الحساب',
        'accountBalance' => 'رصيد الحساب',
        'boxBalance' => 'رصيد الصندوق',
        'expenseId' => 'معرّف المصروف',
        'expenseAmount' => 'مبلغ المصروف',
        'journalAmount' => 'مبلغ القيد',
        'amount' => 'المبلغ',
        'technicianId' => 'معرّف الفني',
        'technicianName' => 'اسم الفني',
        'agentId' => 'معرّف الوكيل',
        'agentName' => 'اسم الوكيل',
        'salaryId' => 'معرّف الراتب',
        'period' => 'الفترة',
        'logId' => 'رقم العملية',
        'customerName' => 'اسم المشترك',
        'planPrice' => 'سعر الباقة',
        'collectionType' => 'نوع التحصيل',
        'referenceType' => 'نوع المرجع',
        'referenceId' => 'معرّف المرجع',
        'count' => 'العدد',
        'balance' => 'الرصيد',
        'transactionId' => 'معرّف العملية',
        'paymentId' => 'معرّف الدفعة',
        'lineCount' => 'عدد الأسطر',
        'headerDebit' => 'مدين الإجمالي',
        'headerCredit' => 'دائن الإجمالي',
        'linesDebit' => 'مدين الأسطر',
        'linesCredit' => 'دائن الأسطر',
        'createdAt' => 'تاريخ الإنشاء',
        'accountId' => 'معرّف الحساب',
        'collectionId' => 'معرّف التحصيل',
        'entries' => 'القيود المكررة',
        _ => k,
      };

  void _copyText(BuildContext ctx, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('تم النسخ', style: GoogleFonts.cairo()),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating));
  }

  void _showDetail(BuildContext ctx, dynamic issue) {
    final severity = (issue['severity'] ?? '') as String;
    final category = (issue['category'] ?? '') as String;
    final message = (issue['message'] ?? '') as String;
    final color = _severityColor(severity);
    final excluded = {'severity', 'category', 'message'};
    final details = <MapEntry<String, dynamic>>[];
    if (issue is Map) {
      for (final e in (issue as Map<String, dynamic>).entries)
        if (!excluded.contains(e.key) && e.value != null) details.add(e);
    }

    showDialog(
        context: ctx,
        builder: (_) => Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                              color: color.withOpacity(0.08),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16)),
                              border: Border(
                                  bottom: BorderSide(
                                      color: color.withOpacity(0.2)))),
                          child: Row(children: [
                            Icon(_severityIcon(severity),
                                color: color, size: 28),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    _badge(_severityLabel(severity),
                                        color.withOpacity(0.15), color),
                                    const SizedBox(width: 6),
                                    _badge(
                                        _categoryLabel(category),
                                        Colors.grey.shade100,
                                        Colors.grey.shade600),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(message,
                                      style: GoogleFonts.cairo(
                                          fontSize: 14,
                                          color: Colors.grey.shade800)),
                                ])),
                            IconButton(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close, size: 20)),
                          ]),
                        ),
                        if (details.isNotEmpty)
                          Flexible(
                              child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                children: details.map((e) {
                              final label = _fieldLabel(e.key);
                              final val = e.value.toString();
                              return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                          width: 130,
                                          child: Text(label,
                                              style: GoogleFonts.cairo(
                                                  fontSize: 12,
                                                  color: Colors.grey.shade500,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      Expanded(
                                          child: SelectableText(val,
                                              style: GoogleFonts.cairo(
                                                  fontSize: 13,
                                                  color:
                                                      Colors.grey.shade800))),
                                      InkWell(
                                          onTap: () => _copyText(ctx, val),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(Icons.copy,
                                                  size: 16,
                                                  color:
                                                      Colors.grey.shade400))),
                                    ],
                                  ));
                            }).toList()),
                          )),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  final all = details
                                      .map((e) =>
                                          '${_fieldLabel(e.key)}: ${e.value}')
                                      .join('\n');
                                  _copyText(ctx, '$message\n$all');
                                },
                                icon: const Icon(Icons.copy_all, size: 18),
                                label: Text('نسخ كل التفاصيل',
                                    style: GoogleFonts.cairo(fontSize: 13)),
                              ),
                            )),
                      ],
                    )),
              ),
            ));
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text,
            style: GoogleFonts.cairo(
                fontSize: 11, color: fg, fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    final ar = context.accR;
    final isMob = ar.isMobile;
    return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: AccountingTheme.bgPrimary,
          body: SafeArea(
              child: Column(children: [
            // شريط العنوان
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: isMob ? 12 : 20, vertical: isMob ? 8 : 12),
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xFF1A237E), Color(0xFF283593)])),
              child: Row(children: [
                IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back_rounded,
                        color: Colors.white, size: isMob ? 20 : 24),
                    tooltip: 'رجوع',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32)),
                const SizedBox(width: 4),
                Icon(Icons.verified_user,
                    color: Colors.white, size: isMob ? 20 : 28),
                const SizedBox(width: 8),
                Text('التدقيق المحاسبي الشامل',
                    style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: isMob ? 14 : 20,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                if (!_isLoading)
                  IconButton(
                      onPressed: _runAudit,
                      icon: Icon(Icons.refresh,
                          color: Colors.white70, size: isMob ? 18 : 24),
                      tooltip: 'إعادة التدقيق'),
              ]),
            ),
            // تبويبات
            if (!_isLoading && _errorMessage == null)
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  labelColor: const Color(0xFF1A237E),
                  unselectedLabelColor: Colors.grey.shade500,
                  indicatorColor: const Color(0xFF1A237E),
                  labelStyle: GoogleFonts.cairo(
                      fontSize: isMob ? 11 : 13, fontWeight: FontWeight.bold),
                  unselectedLabelStyle:
                      GoogleFonts.cairo(fontSize: isMob ? 11 : 13),
                  tabs: List.generate(_tabs.length, (i) {
                    final t = _tabs[i];
                    final cnt = _countForTab(i);
                    return Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(t.icon, size: 16),
                      const SizedBox(width: 4),
                      Text(t.label),
                      if (cnt > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: cnt > 0
                                  ? const Color(0xFFE53935).withOpacity(0.1)
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('$cnt',
                              style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  color: cnt > 0
                                      ? const Color(0xFFE53935)
                                      : Colors.grey,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ]));
                  }),
                ),
              ),
            // المحتوى
            Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                const Icon(Icons.error_outline,
                                    size: 48, color: Colors.red),
                                const SizedBox(height: 8),
                                Text(_errorMessage!,
                                    style: GoogleFonts.cairo(
                                        color: Colors.red, fontSize: 14)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                    onPressed: _runAudit,
                                    icon: const Icon(Icons.refresh),
                                    label: Text('إعادة المحاولة',
                                        style: GoogleFonts.cairo())),
                              ]))
                        : _buildContent(ar, isMob)),
          ])),
        ));
  }

  Widget _buildContent(AccountingResponsive ar, bool isMob) {
    final filtered = _filteredIssues;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 12 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSummaryCards(ar, isMob),
        SizedBox(height: isMob ? 8 : 12),
        if (filtered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: AccountingTheme.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AccountingTheme.success)),
            child: Column(children: [
              Icon(Icons.check_circle,
                  size: 48, color: AccountingTheme.success),
              const SizedBox(height: 8),
              Text('لا توجد مشاكل في هذا التبويب',
                  style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.success)),
            ]),
          )
        else
          ...filtered.map((issue) => _buildIssueCard(issue, ar, isMob)),
      ]),
    );
  }

  Widget _buildSummaryCards(AccountingResponsive ar, bool isMob) {
    final s = _summary ?? {};
    final total = (s['totalIssues'] ?? 0) as int;
    final critical = (s['critical'] ?? 0) as int;
    final high = (s['high'] ?? 0) as int;
    final medium = (s['medium'] ?? 0) as int;
    final warning = (s['warning'] ?? 0) as int;
    return Wrap(spacing: isMob ? 8 : 12, runSpacing: isMob ? 8 : 12, children: [
      _summaryChip('الإجمالي', total,
          total == 0 ? AccountingTheme.success : Colors.grey.shade700, isMob,
          onTap: () => setState(() => _filterSeverity = 'all')),
      _summaryChip('حرج', critical, const Color(0xFFE53935), isMob,
          onTap: () => _filterBySeverity('critical'),
          active: _filterSeverity == 'critical'),
      _summaryChip('عالي', high, const Color(0xFFFF6F00), isMob,
          onTap: () => _filterBySeverity('high'),
          active: _filterSeverity == 'high'),
      _summaryChip('متوسط', medium, const Color(0xFFFFA726), isMob,
          onTap: () => _filterBySeverity('medium'),
          active: _filterSeverity == 'medium'),
      _summaryChip('تنبيه', warning, const Color(0xFF42A5F5), isMob,
          onTap: () => _filterBySeverity('warning'),
          active: _filterSeverity == 'warning'),
    ]);
  }

  Widget _summaryChip(String label, int count, Color color, bool isMob,
      {VoidCallback? onTap, bool active = false}) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: isMob ? 12 : 16, vertical: isMob ? 6 : 10),
          decoration: BoxDecoration(
              color: active ? color.withOpacity(0.2) : color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: active ? color : color.withOpacity(0.3),
                  width: active ? 2 : 1)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$count',
                style: GoogleFonts.cairo(
                    fontSize: isMob ? 18 : 24,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(width: 6),
            Text(label,
                style:
                    GoogleFonts.cairo(fontSize: isMob ? 11 : 13, color: color)),
          ]),
        ));
  }

  Widget _buildIssueCard(dynamic issue, AccountingResponsive ar, bool isMob) {
    final severity = (issue['severity'] ?? 'medium') as String;
    final category = (issue['category'] ?? '') as String;
    final message = (issue['message'] ?? '') as String;
    final color = _severityColor(severity);
    final entryNumber = issue['entryNumber']?.toString();
    final amount = issue['amount'] ?? issue['difference'];

    return InkWell(
      onTap: () => _showDetail(context, issue),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: EdgeInsets.only(bottom: isMob ? 8 : 10),
        padding: EdgeInsets.all(isMob ? 10 : 14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border(right: BorderSide(color: color, width: 4)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2))
            ]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_severityIcon(severity), color: color, size: isMob ? 20 : 24),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  _badge(
                      _severityLabel(severity), color.withOpacity(0.1), color),
                  const SizedBox(width: 6),
                  _badge(_categoryLabel(category), Colors.grey.shade100,
                      Colors.grey.shade600),
                  if (entryNumber != null) ...[
                    const SizedBox(width: 6),
                    _badge(
                        entryNumber,
                        const Color(0xFF1A237E).withOpacity(0.08),
                        const Color(0xFF1A237E)),
                  ],
                  const Spacer(),
                  if (amount != null)
                    Text((amount as num).toStringAsFixed(0),
                        style: GoogleFonts.cairo(
                            fontSize: isMob ? 11 : 13,
                            color: color,
                            fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_left,
                      size: 18, color: Colors.grey.shade400),
                ]),
                const SizedBox(height: 6),
                Text(message,
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 12 : 14,
                        color: Colors.grey.shade800)),
              ])),
        ]),
      ),
    );
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  final Set<String>? categories;
  const _TabDef(this.label, this.icon, this.categories);
}
