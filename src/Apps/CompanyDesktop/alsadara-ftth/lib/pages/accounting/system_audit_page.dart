import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// شاشة التدقيق المحاسبي الشامل
class SystemAuditPage extends StatefulWidget {
  final String? companyId;
  const SystemAuditPage({super.key, this.companyId});

  @override
  State<SystemAuditPage> createState() => _SystemAuditPageState();
}

class _SystemAuditPageState extends State<SystemAuditPage> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _summary;
  List<dynamic> _issues = [];
  String _filterCategory = 'all';
  String _filterSeverity = 'all';

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  @override
  void initState() {
    super.initState();
    _runAudit();
  }

  Future<void> _runAudit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final cid = _companyId.isNotEmpty ? _companyId : null;
      final result =
          await AccountingService.instance.runAudit(companyId: cid);
      if (result['success'] == true) {
        setState(() {
          _summary = result['summary'] as Map<String, dynamic>?;
          _issues = (result['issues'] is List) ? result['issues'] : [];
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
    return _issues.where((i) {
      if (_filterCategory != 'all' && i['category'] != _filterCategory)
        return false;
      if (_filterSeverity != 'all' && i['severity'] != _filterSeverity)
        return false;
      return true;
    }).toList();
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical': return const Color(0xFFE53935);
      case 'high': return const Color(0xFFFF6F00);
      case 'medium': return const Color(0xFFFFA726);
      case 'warning': return const Color(0xFF42A5F5);
      default: return Colors.grey;
    }
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'critical': return Icons.error;
      case 'high': return Icons.warning_amber_rounded;
      case 'medium': return Icons.info_outline;
      case 'warning': return Icons.lightbulb_outline;
      default: return Icons.help_outline;
    }
  }

  String _severityLabel(String severity) {
    switch (severity) {
      case 'critical': return 'حرج';
      case 'high': return 'عالي';
      case 'medium': return 'متوسط';
      case 'warning': return 'تنبيه';
      default: return severity;
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'UnbalancedEntry': return 'قيد غير متوازن';
      case 'CashBoxMismatch': return 'خلل رصيد صندوق';
      case 'CashBoxAccountMismatch': return 'صندوق ≠ حساب';
      case 'VoidedCashNoReverse': return 'إلغاء بدون عكس';
      case 'ExpenseNoEntry': return 'مصروف بدون قيد';
      case 'ExpenseAmountMismatch': return 'مصروف ≠ قيد';
      case 'TechBalanceMismatch': return 'خلل رصيد فني';
      case 'FtthNoEntry': return 'FTTH بدون قيد';
      case 'SuspiciousBalance': return 'رصيد مشبوه';
      case 'OrphanEntry': return 'قيد بدون معاملة';
      case 'SalaryNoEntry': return 'راتب بدون قيد';
      case 'CashTxNoEntry': return 'عملية صندوق بدون قيد';
      case 'CollectionNoEntry': return 'تحصيل بدون قيد';
      case 'FixedExpenseNoEntry': return 'مصروف ثابت بدون قيد';
      case 'NegativeCashBox': return 'صندوق سالب';
      case 'DuplicateEntry': return 'قيد مكرر';
      case 'EntryLineMismatch': return 'أسطر ≠ إجمالي';
      case 'InsufficientLines': return 'قيد ناقص الأسطر';
      case 'AgentBalanceMismatch': return 'خلل رصيد وكيل';
      case 'StaleSalary': return 'راتب معلق قديم';
      case 'LeafWithChildren': return 'حساب leaf له أبناء';
      default: return category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.accR;
    final isMob = ar.isMobile;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              // ─── شريط العنوان ───
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: isMob ? 12 : 20, vertical: isMob ? 8 : 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A237E), Color(0xFF283593)],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: isMob ? 20 : 24),
                      tooltip: 'رجوع',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
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
                        tooltip: 'إعادة التدقيق',
                      ),
                  ],
                ),
              ),

              // ─── المحتوى ───
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
                                      style: GoogleFonts.cairo()),
                                ),
                              ],
                            ),
                          )
                        : _buildContent(ar, isMob),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(AccountingResponsive ar, bool isMob) {
    final filtered = _filteredIssues;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMob ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(ar, isMob),
          SizedBox(height: isMob ? 12 : 20),
          _buildFilters(ar, isMob),
          SizedBox(height: isMob ? 8 : 12),

          if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AccountingTheme.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AccountingTheme.success),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_circle,
                      size: 48, color: AccountingTheme.success),
                  const SizedBox(height: 8),
                  Text(
                    _filterCategory == 'all' && _filterSeverity == 'all'
                        ? 'لا توجد مشاكل — النظام سليم'
                        : 'لا توجد مشاكل في هذا التصنيف',
                    style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.success),
                  ),
                ],
              ),
            )
          else
            ...filtered.map((issue) => _buildIssueCard(issue, ar, isMob)),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(AccountingResponsive ar, bool isMob) {
    final s = _summary ?? {};
    final total = (s['totalIssues'] ?? 0) as int;
    final critical = (s['critical'] ?? 0) as int;
    final high = (s['high'] ?? 0) as int;
    final medium = (s['medium'] ?? 0) as int;
    final warning = (s['warning'] ?? 0) as int;

    return Wrap(
      spacing: isMob ? 8 : 12,
      runSpacing: isMob ? 8 : 12,
      children: [
        _summaryChip('الإجمالي', total, total == 0 ? AccountingTheme.success : Colors.grey.shade700, isMob),
        _summaryChip('حرج', critical, const Color(0xFFE53935), isMob),
        _summaryChip('عالي', high, const Color(0xFFFF6F00), isMob),
        _summaryChip('متوسط', medium, const Color(0xFFFFA726), isMob),
        _summaryChip('تنبيه', warning, const Color(0xFF42A5F5), isMob),
      ],
    );
  }

  Widget _summaryChip(String label, int count, Color color, bool isMob) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 12 : 16, vertical: isMob ? 6 : 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: GoogleFonts.cairo(
                  fontSize: isMob ? 18 : 24,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: isMob ? 11 : 13, color: color)),
        ],
      ),
    );
  }

  Widget _buildFilters(AccountingResponsive ar, bool isMob) {
    final categories = ['all', ..._issues.map((i) => i['category'] as String).toSet()];
    final severities = ['all', 'critical', 'high', 'medium', 'warning'];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterCategory,
              dropdownColor: Colors.white,
              style: GoogleFonts.cairo(color: Colors.grey.shade800, fontSize: isMob ? 12 : 14),
              items: categories
                  .map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c == 'all' ? 'كل التصنيفات' : _categoryLabel(c))))
                  .toList(),
              onChanged: (v) => setState(() => _filterCategory = v ?? 'all'),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _filterSeverity,
              dropdownColor: Colors.white,
              style: GoogleFonts.cairo(color: Colors.grey.shade800, fontSize: isMob ? 12 : 14),
              items: severities
                  .map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s == 'all' ? 'كل الخطورات' : _severityLabel(s))))
                  .toList(),
              onChanged: (v) => setState(() => _filterSeverity = v ?? 'all'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIssueCard(dynamic issue, AccountingResponsive ar, bool isMob) {
    final severity = (issue['severity'] ?? 'medium') as String;
    final category = (issue['category'] ?? '') as String;
    final message = (issue['message'] ?? '') as String;
    final color = _severityColor(severity);

    return Container(
      margin: EdgeInsets.only(bottom: isMob ? 8 : 10),
      padding: EdgeInsets.all(isMob ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(right: BorderSide(color: color, width: 4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_severityIcon(severity), color: color, size: isMob ? 20 : 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_severityLabel(severity),
                          style: GoogleFonts.cairo(
                              fontSize: isMob ? 9 : 11,
                              color: color,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_categoryLabel(category),
                          style: GoogleFonts.cairo(
                              fontSize: isMob ? 9 : 11,
                              color: Colors.grey.shade600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(message,
                    style: GoogleFonts.cairo(
                        fontSize: isMob ? 12 : 14,
                        color: Colors.grey.shade800)),
                if (issue['difference'] != null) ...[
                  const SizedBox(height: 4),
                  Text('الفرق: ${(issue['difference'] as num).toStringAsFixed(0)}',
                      style: GoogleFonts.cairo(
                          fontSize: isMob ? 10 : 12, color: color, fontWeight: FontWeight.bold)),
                ],
                if (issue['entryNumber'] != null) ...[
                  const SizedBox(height: 2),
                  Text('رقم القيد: ${issue['entryNumber']}',
                      style: GoogleFonts.cairo(
                          fontSize: isMob ? 10 : 12, color: Colors.grey.shade500)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
