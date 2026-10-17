import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';

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
        'critical' => SdColors.danger,
        'high' => SdColors.warning,
        'medium' => SdStatus.warning.tone.light,
        'warning' => SdColors.info,
        _ => SdColors.faint,
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
    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
        content: Text('تم النسخ', style: TextStyle(fontFamily: SdText.family)),
        duration: Duration(seconds: 1),
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
                backgroundColor: SdColors.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(SdRadius.md)),
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(SdSpace.md),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.08),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(SdRadius.md)),
                              border: Border(
                                  bottom: BorderSide(
                                      color: color.withValues(alpha: 0.2)))),
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
                                        color.withValues(alpha: 0.15), color),
                                    const SizedBox(width: 6),
                                    _badge(
                                        _categoryLabel(category),
                                        SdColors.surfaceAlt,
                                        SdColors.muted),
                                  ]),
                                  const SizedBox(height: 6),
                                  Text(message,
                                      style: const TextStyle(
                                          fontFamily: SdText.family,
                                          fontSize: 14,
                                          color: SdColors.ink)),
                                ])),
                            IconButton(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close, size: 20)),
                          ]),
                        ),
                        if (details.isNotEmpty)
                          Flexible(
                              child: SingleChildScrollView(
                            padding: const EdgeInsets.all(SdSpace.md),
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
                                              style: const TextStyle(
                                                  fontFamily: SdText.family,
                                                  fontSize: 12,
                                                  color: SdColors.faint,
                                                  fontWeight:
                                                      FontWeight.bold))),
                                      Expanded(
                                          child: SelectableText(val,
                                              style: const TextStyle(
                                                  fontFamily: SdText.family,
                                                  fontSize: 13,
                                                  color: SdColors.ink))),
                                      InkWell(
                                          onTap: () => _copyText(ctx, val),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child: const Padding(
                                              padding: EdgeInsets.all(4),
                                              child: Icon(Icons.copy,
                                                  size: 16,
                                                  color: SdColors.faint))),
                                    ],
                                  ));
                            }).toList()),
                          )),
                        Padding(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                                label: const Text('نسخ كل التفاصيل',
                                    style: TextStyle(
                                        fontFamily: SdText.family,
                                        fontSize: 13)),
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
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(SdRadius.xs)),
        child: Text(text,
            style: TextStyle(
                fontFamily: SdText.family,
                fontSize: 11.5,
                color: fg,
                fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    final isMob = context.sd.isPhone;
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'التدقيق المحاسبي الشامل',
          actions: [
            if (!_isLoading)
              SdAppBarAction(
                icon: Icons.refresh,
                label: 'إعادة التدقيق',
                onPressed: _runAudit,
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(children: [
            // تبويبات
            if (!_isLoading && _errorMessage == null)
              Container(
                color: SdColors.surface,
                child: TabBar(
                  controller: _tabCtrl,
                  isScrollable: true,
                  labelColor: SdColors.primary,
                  unselectedLabelColor: SdColors.faint,
                  indicatorColor: SdColors.primary,
                  labelStyle: const TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                  unselectedLabelStyle: const TextStyle(
                      fontFamily: SdText.family, fontSize: 13),
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
                              color: SdColors.dangerTint,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('$cnt',
                              style: const TextStyle(
                                  fontFamily: SdText.family,
                                  fontSize: 11.5,
                                  color: SdColors.danger,
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
                                    size: 48, color: SdColors.danger),
                                const SizedBox(height: 8),
                                Text(_errorMessage!,
                                    style: const TextStyle(
                                        fontFamily: SdText.family,
                                        color: SdColors.danger,
                                        fontSize: 14)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                    onPressed: _runAudit,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('إعادة المحاولة',
                                        style: TextStyle(
                                            fontFamily: SdText.family))),
                              ]))
                        : _buildContent(isMob)),
          ]),
        ),
      ),
    );
  }

  Widget _buildContent(bool isMob) {
    final filtered = _filteredIssues;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 12 : 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSummaryCards(isMob),
        SizedBox(height: isMob ? 8 : 12),
        if (filtered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
                color: SdColors.successTint,
                borderRadius: BorderRadius.circular(SdRadius.sm),
                border: Border.all(color: SdColors.success)),
            child: const Column(children: [
              Icon(Icons.check_circle, size: 48, color: SdColors.success),
              SizedBox(height: 8),
              Text('لا توجد مشاكل في هذا التبويب',
                  style: TextStyle(
                      fontFamily: SdText.family,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: SdColors.success)),
            ]),
          )
        else
          ...filtered.map((issue) => _buildIssueCard(issue, isMob)),
      ]),
    );
  }

  Widget _buildSummaryCards(bool isMob) {
    final s = _summary ?? {};
    final total = (s['totalIssues'] ?? 0) as int;
    final critical = (s['critical'] ?? 0) as int;
    final high = (s['high'] ?? 0) as int;
    final medium = (s['medium'] ?? 0) as int;
    final warning = (s['warning'] ?? 0) as int;
    return Wrap(spacing: isMob ? 8 : 12, runSpacing: isMob ? 8 : 12, children: [
      _summaryChip('الإجمالي', total,
          total == 0 ? SdColors.success : SdColors.muted, isMob,
          onTap: () => setState(() => _filterSeverity = 'all')),
      _summaryChip('حرج', critical, _severityColor('critical'), isMob,
          onTap: () => _filterBySeverity('critical'),
          active: _filterSeverity == 'critical'),
      _summaryChip('عالي', high, _severityColor('high'), isMob,
          onTap: () => _filterBySeverity('high'),
          active: _filterSeverity == 'high'),
      _summaryChip('متوسط', medium, _severityColor('medium'), isMob,
          onTap: () => _filterBySeverity('medium'),
          active: _filterSeverity == 'medium'),
      _summaryChip('تنبيه', warning, _severityColor('warning'), isMob,
          onTap: () => _filterBySeverity('warning'),
          active: _filterSeverity == 'warning'),
    ]);
  }

  Widget _summaryChip(String label, int count, Color color, bool isMob,
      {VoidCallback? onTap, bool active = false}) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SdRadius.sm),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: isMob ? 12 : 16, vertical: isMob ? 6 : 10),
          decoration: BoxDecoration(
              color: active
                  ? color.withValues(alpha: 0.2)
                  : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(SdRadius.sm),
              border: Border.all(
                  color: active ? color : color.withValues(alpha: 0.3),
                  width: active ? 2 : 1)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$count',
                style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: isMob ? 18 : 24,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: isMob ? 12 : 13,
                    color: color)),
          ]),
        ));
  }

  Widget _buildIssueCard(dynamic issue, bool isMob) {
    final severity = (issue['severity'] ?? 'medium') as String;
    final category = (issue['category'] ?? '') as String;
    final message = (issue['message'] ?? '') as String;
    final color = _severityColor(severity);
    final entryNumber = issue['entryNumber']?.toString();
    final amount = issue['amount'] ?? issue['difference'];

    return InkWell(
      onTap: () => _showDetail(context, issue),
      borderRadius: BorderRadius.circular(SdRadius.sm),
      child: Container(
        margin: EdgeInsets.only(bottom: isMob ? 8 : 10),
        padding: EdgeInsets.all(isMob ? 10 : 14),
        decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.sm),
            border: Border(right: BorderSide(color: color, width: 4)),
            boxShadow: SdDepth.raised(depth: SdDepth.small)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_severityIcon(severity), color: color, size: isMob ? 20 : 24),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  _badge(_severityLabel(severity),
                      color.withValues(alpha: 0.1), color),
                  const SizedBox(width: 6),
                  _badge(_categoryLabel(category), SdColors.surfaceAlt,
                      SdColors.muted),
                  if (entryNumber != null) ...[
                    const SizedBox(width: 6),
                    _badge(entryNumber, SdColors.primaryTint,
                        SdColors.primary),
                  ],
                  const Spacer(),
                  if (amount != null)
                    Text((amount as num).toStringAsFixed(0),
                        style: TextStyle(
                            fontFamily: SdText.family,
                            fontSize: isMob ? 12 : 13,
                            color: color,
                            fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_left,
                      size: 18, color: SdColors.faint),
                ]),
                const SizedBox(height: 6),
                Text(message,
                    style: TextStyle(
                        fontFamily: SdText.family,
                        fontSize: isMob ? 12 : 14,
                        color: SdColors.ink)),
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
