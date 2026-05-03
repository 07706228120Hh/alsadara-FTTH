import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة الإيرادات - Revenue Page
class RevenuePage extends StatefulWidget {
  final String? companyId;

  const RevenuePage({super.key, this.companyId});

  @override
  State<RevenuePage> createState() => _RevenuePageState();
}

class _RevenuePageState extends State<RevenuePage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _revenueAccounts = [];
  List<dynamic> _allAccounts = [];
  List<dynamic> _revenueEntries = [];

  // فلاتر
  String _selectedRevenueType = 'الكل'; // الكل، اشتراكات، تركيب، صيانة، أخرى
  DateTime? _dateFrom;
  DateTime? _dateTo;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      // جلب الحسابات وتصفية حسابات الإيرادات
      final accountsResult = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (accountsResult['success'] == true) {
        _allAccounts = (accountsResult['data'] as List?) ?? [];
        _revenueAccounts = _allAccounts
            .where((a) =>
                a['AccountType']?.toString() == 'Revenue' ||
                a['Type']?.toString() == 'Revenue' ||
                (a['Code']?.toString() ?? '').startsWith('4'))
            .toList();
        // استبعاد الحسابات الأب (غير النهائية) لتجنب الحساب المزدوج
        _revenueAccounts =
            _revenueAccounts.where((a) => a['IsLeaf'] == true).toList();
        // ترتيب حسب الكود
        _revenueAccounts.sort((a, b) => (a['Code']?.toString() ?? '')
            .compareTo(b['Code']?.toString() ?? ''));
      }

      // جلب القيود المحاسبية
      final entriesResult = await AccountingService.instance
          .getJournalEntries(companyId: widget.companyId);
      if (entriesResult['success'] == true) {
        final allEntries = (entriesResult['data'] as List?) ?? [];
        // تصفية القيود التي تحتوي على حسابات إيرادات
        final revenueAccountIds = _revenueAccounts
            .map((a) => a['Id']?.toString())
            .where((id) => id != null)
            .toSet();

        _revenueEntries = allEntries.where((entry) {
          final lines = entry['Lines'] as List? ?? [];
          return lines.any((line) =>
              revenueAccountIds.contains(line['AccountId']?.toString()));
        }).toList();
      }
    } catch (e) {
      _errorMessage = 'خطأ في الاتصال';
    }
    setState(() => _isLoading = false);
  }

  double get _totalRevenue {
    double total = 0;
    for (final acc in _revenueAccounts) {
      total +=
          ((acc['Balance'] ?? acc['CurrentBalance'] ?? 0) as num).toDouble();
    }
    return total;
  }

  /// القيود المفلترة حسب النوع والتاريخ
  List<dynamic> get _filteredEntries {
    var entries = _revenueEntries;

    // فلتر النوع
    if (_selectedRevenueType != 'الكل') {
      Set<String> typeAccountIds = {};
      String codePrefix = '';
      if (_selectedRevenueType == 'اشتراكات') codePrefix = '41';
      if (_selectedRevenueType == 'تركيب') codePrefix = '42';
      if (_selectedRevenueType == 'صيانة') codePrefix = '43';

      if (codePrefix.isNotEmpty) {
        typeAccountIds = _revenueAccounts
            .where((a) => (a['Code']?.toString() ?? '').startsWith(codePrefix))
            .map((a) => a['Id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      } else {
        // أخرى = ليس 41 أو 42 أو 43
        final knownIds = _revenueAccounts
            .where((a) {
              final code = a['Code']?.toString() ?? '';
              return code.startsWith('41') ||
                  code.startsWith('42') ||
                  code.startsWith('43');
            })
            .map((a) => a['Id']?.toString() ?? '')
            .toSet();
        typeAccountIds = _revenueAccounts
            .map((a) => a['Id']?.toString() ?? '')
            .where((id) => id.isNotEmpty && !knownIds.contains(id))
            .toSet();
      }

      entries = entries.where((entry) {
        final lines = entry['Lines'] as List? ?? [];
        return lines.any(
            (line) => typeAccountIds.contains(line['AccountId']?.toString()));
      }).toList();
    }

    // فلتر التاريخ
    if (_dateFrom != null || _dateTo != null) {
      entries = entries.where((entry) {
        final dateStr = entry['EntryDate'] ?? entry['CreatedAt'];
        if (dateStr == null) return false;
        try {
          final d = DateTime.parse(dateStr.toString()).toLocal();
          if (_dateFrom != null && d.isBefore(_dateFrom!)) return false;
          if (_dateTo != null &&
              d.isAfter(_dateTo!.add(const Duration(days: 1)))) return false;
          return true;
        } catch (_) {
          return false;
        }
      }).toList();
    }

    return entries;
  }

  /// مجموع القيود المفلترة
  double get _filteredTotal {
    double total = 0;
    for (final entry in _filteredEntries) {
      total += ((entry['TotalDebit'] ?? 0) as num).toDouble();
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildPageToolbar(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AccountingTheme.neonGreen))
                    : _errorMessage != null
                        ? Center(
                            child: Text(_errorMessage!,
                                style: const TextStyle(
                                    color: AccountingTheme.danger)))
                        : Column(
                            children: [
                              _buildSummaryAndFilters(),
                              Expanded(child: _buildEntriesList()),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageToolbar() {
    final ar = context.accR;
    final isMob = MediaQuery.of(context).size.width < 700;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceXL, vertical: isMob ? 6 : ar.spaceL),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            tooltip: 'رجوع',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMob ? 4 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonGreenGradient,
              borderRadius: BorderRadius.circular(ar.btnRadius),
            ),
            child: Icon(Icons.trending_up_rounded,
                color: Colors.white, size: isMob ? 18 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('الإيرادات',
              style: GoogleFonts.cairo(
                  fontSize: isMob ? 14 : ar.headingMedium,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary)),
          const Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh, size: isMob ? 18 : ar.iconM),
            tooltip: 'تحديث',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          ElevatedButton.icon(
            onPressed: _showAddRevenueDialog,
            icon: Icon(Icons.add, size: isMob ? 16 : ar.iconM),
            label: Text(isMob ? 'إضافة إيراد' : 'إضافة إيراد',
                style: GoogleFonts.cairo(fontSize: isMob ? 11 : ar.buttonText)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AccountingTheme.neonGreen,
              foregroundColor: Colors.white,
              padding: isMob
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                  : ar.buttonPadding,
              minimumSize: isMob ? const Size(0, 30) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAndFilters() {
    final isMob = MediaQuery.of(context).size.width < 700;
    final filtered = _filteredEntries;
    final hasActiveFilter =
        _selectedRevenueType != 'الكل' || _dateFrom != null || _dateTo != null;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 10 : context.accR.spaceM,
          vertical: isMob ? 8 : context.accR.spaceS),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: const Border(
            bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Column(
        children: [
          // بطاقة الإجمالي
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 14 : 20, vertical: isMob ? 10 : 14),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonGreenGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AccountingTheme.neonGreen.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.trending_up_rounded,
                      color: Colors.white, size: isMob ? 22 : 28),
                ),
                SizedBox(width: isMob ? 10 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasActiveFilter ? 'إيرادات مفلترة' : 'إجمالي الإيرادات',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: isMob ? 12 : 14,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_fmt(hasActiveFilter ? _filteredTotal : _totalRevenue)} د.ع',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: isMob ? 20 : 26,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${filtered.length} قيد',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: isMob ? 12 : 14,
                          fontWeight: FontWeight.w600),
                    ),
                    if (hasActiveFilter)
                      Text(
                        'من ${_revenueEntries.length}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: isMob ? 10 : 12),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: isMob ? 8 : 10),
          // أزرار التصفية
          Row(
            children: [
              // فلتر النوع
              Expanded(
                child: _buildFilterDropdown(isMob),
              ),
              SizedBox(width: isMob ? 6 : 10),
              // فلتر التاريخ من
              _buildDateFilterBtn(
                isMob: isMob,
                label: _dateFrom != null
                    ? _formatDate(_dateFrom!.toIso8601String())
                    : 'من تاريخ',
                icon: Icons.calendar_today,
                isActive: _dateFrom != null,
                onTap: () => _pickDate(isFrom: true),
              ),
              SizedBox(width: isMob ? 4 : 8),
              // فلتر التاريخ إلى
              _buildDateFilterBtn(
                isMob: isMob,
                label: _dateTo != null
                    ? _formatDate(_dateTo!.toIso8601String())
                    : 'إلى تاريخ',
                icon: Icons.event,
                isActive: _dateTo != null,
                onTap: () => _pickDate(isFrom: false),
              ),
              // زر مسح الفلاتر
              if (hasActiveFilter) ...[
                SizedBox(width: isMob ? 4 : 8),
                InkWell(
                  onTap: () => setState(() {
                    _selectedRevenueType = 'الكل';
                    _dateFrom = null;
                    _dateTo = null;
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: EdgeInsets.all(isMob ? 6 : 8),
                    decoration: BoxDecoration(
                      color: AccountingTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AccountingTheme.danger.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.clear_all,
                        color: AccountingTheme.danger, size: isMob ? 18 : 20),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown(bool isMob) {
    const types = ['الكل', 'اشتراكات', 'تركيب', 'صيانة', 'أخرى'];
    return Container(
      height: isMob ? 36 : 40,
      padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 12),
      decoration: BoxDecoration(
        color: _selectedRevenueType != 'الكل'
            ? AccountingTheme.accent.withValues(alpha: 0.1)
            : AccountingTheme.bgCardHover,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _selectedRevenueType != 'الكل'
              ? AccountingTheme.accent.withValues(alpha: 0.4)
              : AccountingTheme.borderColor,
          width: 1.2,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRevenueType,
          isExpanded: true,
          icon: Icon(Icons.filter_list,
              size: isMob ? 16 : 18, color: AccountingTheme.textSecondary),
          style: TextStyle(
              color: Colors.black87,
              fontSize: isMob ? 12 : 14,
              fontWeight: FontWeight.w600),
          dropdownColor: Colors.white,
          items: types.map((t) {
            return DropdownMenuItem(
              value: t,
              child: Text(t, style: TextStyle(fontSize: isMob ? 12 : 14)),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _selectedRevenueType = v);
          },
        ),
      ),
    );
  }

  Widget _buildDateFilterBtn({
    required bool isMob,
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: isMob ? 36 : 40,
        padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 12),
        decoration: BoxDecoration(
          color: isActive
              ? AccountingTheme.info.withValues(alpha: 0.1)
              : AccountingTheme.bgCardHover,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? AccountingTheme.info.withValues(alpha: 0.4)
                : AccountingTheme.borderColor,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: isMob ? 14 : 16,
                color: isActive
                    ? AccountingTheme.info
                    : AccountingTheme.textSecondary),
            SizedBox(width: isMob ? 4 : 6),
            Text(label,
                style: TextStyle(
                    color: isActive ? AccountingTheme.info : Colors.black87,
                    fontSize: isMob ? 11 : 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_dateFrom ?? now) : (_dateTo ?? now),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AccountingTheme.neonGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _dateFrom = picked;
        } else {
          _dateTo = picked;
        }
      });
    }
  }

  Widget _buildEntriesList() {
    final filtered = _filteredEntries;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up,
                color: AccountingTheme.textMuted, size: context.accR.iconEmpty),
            SizedBox(height: context.accR.spaceXL),
            Text('لا توجد قيود إيرادات',
                style: TextStyle(
                    color: AccountingTheme.textSecondary,
                    fontSize: context.accR.headingSmall)),
            SizedBox(height: 8),
            Text('اضغط + لإضافة إيراد جديد',
                style: TextStyle(
                    color: AccountingTheme.textMuted,
                    fontSize: context.accR.financialSmall)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: context.accR.spaceM),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final entry = filtered[i];
        final lines = entry['Lines'] as List? ?? [];
        final status = entry['Status']?.toString() ?? 'Draft';
        final statusInfo = _statusInfo(status);
        final totalDebit = (entry['TotalDebit'] ?? 0 as num).toDouble();

        return Container(
          margin: EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.all(context.accR.spaceL),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(context.accR.cardRadius),
            border: Border(
                right:
                    BorderSide(color: statusInfo['color'] as Color, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry['Description'] ?? '',
                      style: TextStyle(
                          color: AccountingTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: context.accR.body),
                    ),
                  ),
                  // الحالة
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (statusInfo['color'] as Color)
                          .withValues(alpha: 0.15),
                      borderRadius:
                          BorderRadius.circular(context.accR.cardRadius),
                    ),
                    child: Text(
                      statusInfo['label'] as String,
                      style: TextStyle(
                          color: statusInfo['color'] as Color,
                          fontSize: context.accR.small),
                    ),
                  ),
                  SizedBox(width: context.accR.spaceS),
                  Text(
                    '${_fmt(totalDebit)} د.ع',
                    style: TextStyle(
                      color: AccountingTheme.neonGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: context.accR.body,
                    ),
                  ),
                ],
              ),
              if (lines.isNotEmpty) ...[
                SizedBox(height: context.accR.spaceS),
                ...lines.take(4).map((line) {
                  final accName =
                      line['AccountName'] ?? line['AccountCode'] ?? '';
                  final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
                  final credit =
                      ((line['CreditAmount'] ?? 0) as num).toDouble();
                  return Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        SizedBox(width: context.accR.spaceXL),
                        Icon(
                          credit > 0 ? Icons.arrow_back : Icons.arrow_forward,
                          color: credit > 0
                              ? AccountingTheme.accent
                              : AccountingTheme.info,
                          size: context.accR.iconS,
                        ),
                        SizedBox(width: context.accR.spaceXS),
                        Expanded(
                          child: Text(
                            accName.toString(),
                            style: TextStyle(
                                color: AccountingTheme.textMuted,
                                fontSize: context.accR.small),
                          ),
                        ),
                        if (debit > 0)
                          Text('مدين: ${_fmt(debit)}',
                              style: TextStyle(
                                  color: AccountingTheme.info,
                                  fontSize: context.accR.small)),
                        if (credit > 0)
                          Text('دائن: ${_fmt(credit)}',
                              style: TextStyle(
                                  color: AccountingTheme.accent,
                                  fontSize: context.accR.small)),
                      ],
                    ),
                  );
                }),
              ],
              SizedBox(height: context.accR.spaceXS),
              Row(
                children: [
                  Icon(Icons.access_time,
                      color: AccountingTheme.textMuted,
                      size: context.accR.iconXS),
                  SizedBox(width: context.accR.spaceXS),
                  Text(
                    _formatDate(entry['EntryDate'] ?? entry['CreatedAt']),
                    style: TextStyle(
                        color: AccountingTheme.textMuted,
                        fontSize: context.accR.small),
                  ),
                  if (entry['Notes'] != null &&
                      entry['Notes'].toString().isNotEmpty) ...[
                    SizedBox(width: context.accR.spaceM),
                    Tooltip(
                      message: entry['Notes'].toString(),
                      child: Icon(Icons.notes,
                          color: AccountingTheme.textMuted,
                          size: context.accR.iconXS),
                    ),
                  ],
                  const Spacer(),
                  _actionBtn(Icons.edit, AccountingTheme.info,
                      () => _showEditRevenueDialog(entry)),
                  SizedBox(width: context.accR.spaceXS),
                  _actionBtn(Icons.delete_outline, AccountingTheme.danger,
                      () => _confirmDeleteRevenue(entry)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.all(context.accR.spaceXS),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: color, size: context.accR.iconS),
      ),
    );
  }

  void _showEditRevenueDialog(Map<String, dynamic> entry) async {
    if (_allAccounts.isEmpty) {
      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (result['success'] == true) {
        _allAccounts = (result['data'] as List?) ?? [];
      }
    }

    final lines = entry['Lines'] as List? ?? [];
    final description = entry['Description'] ?? '';
    final notes = entry['Notes'] ?? '';
    final entryId = entry['Id']?.toString();
    if (entryId == null) return;

    // استخراج حساب الإيراد (الدائن) وحساب الأصل (المدين) من سطور القيد
    String? revenueAccId;
    String? assetAccId;
    double amount = 0;
    for (final line in lines) {
      final credit = ((line['CreditAmount'] ?? 0) as num).toDouble();
      final debit = ((line['DebitAmount'] ?? 0) as num).toDouble();
      if (credit > 0) {
        revenueAccId = line['AccountId']?.toString();
        amount = credit;
      } else if (debit > 0) {
        assetAccId = line['AccountId']?.toString();
        if (amount == 0) amount = debit;
      }
    }

    final revenueAccounts = _allAccounts
        .where((a) =>
            a['AccountType']?.toString() == 'Revenue' ||
            a['Type']?.toString() == 'Revenue' ||
            (a['Code']?.toString() ?? '').startsWith('4'))
        .where((a) => a['IsLeaf'] == true)
        .toList();

    final assetAccounts = _allAccounts
        .where((a) =>
            a['AccountType']?.toString() == 'Assets' ||
            a['Type']?.toString() == 'Assets' ||
            (a['Code']?.toString() ?? '').startsWith('1'))
        .where((a) => a['IsLeaf'] == true)
        .toList();

    // التأكد من أن القيم الحالية موجودة في القوائم
    if (revenueAccId != null &&
        !revenueAccounts.any((a) => a['Id']?.toString() == revenueAccId)) {
      revenueAccId = revenueAccounts.isNotEmpty
          ? revenueAccounts.first['Id']?.toString()
          : null;
    }
    if (assetAccId != null &&
        !assetAccounts.any((a) => a['Id']?.toString() == assetAccId)) {
      assetAccId = assetAccounts.isNotEmpty
          ? assetAccounts.first['Id']?.toString()
          : null;
    }

    if (!mounted) return;

    final descCtrl = TextEditingController(text: description);
    final amountCtrl = TextEditingController(
        text: amount > 0 ? amount.toStringAsFixed(0) : '');
    final notesCtrl = TextEditingController(text: notes);
    String? selectedRevenueAccId = revenueAccId;
    String? selectedAssetAccId = assetAccId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Text('تعديل الإيراد',
                style: TextStyle(
                    color: AccountingTheme.info, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: context.accR.isMobile
                  ? MediaQuery.of(context).size.width * 0.90
                  : 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field('الوصف *', descCtrl),
                    SizedBox(height: context.accR.spaceM),
                    _field('المبلغ *', amountCtrl, isNumber: true),
                    SizedBox(height: context.accR.spaceM),
                    DropdownButtonFormField<String>(
                      value: selectedRevenueAccId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: revenueAccounts.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Name']}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedRevenueAccId = v),
                      decoration: _inputDeco('حساب الإيراد (دائن)'),
                    ),
                    SizedBox(height: context.accR.spaceM),
                    DropdownButtonFormField<String>(
                      value: selectedAssetAccId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: assetAccounts.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Name']}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedAssetAccId = v),
                      decoration: _inputDeco('حساب القبض (مدين)'),
                    ),
                    SizedBox(height: context.accR.spaceM),
                    _field('ملاحظات', notesCtrl),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء',
                      style: TextStyle(color: AccountingTheme.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.info,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  final newAmount = double.tryParse(amountCtrl.text) ?? 0;
                  if (descCtrl.text.isEmpty || newAmount <= 0) {
                    _snack('الرجاء ملء الوصف والمبلغ', AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);

                  final result = await AccountingService.instance
                      .updateJournalEntry(entryId, {
                    'Description': descCtrl.text,
                    'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    'Lines': [
                      {
                        'AccountId': selectedAssetAccId,
                        'DebitAmount': newAmount,
                        'CreditAmount': 0,
                        'Description': 'قبض إيراد: ${descCtrl.text}',
                      },
                      {
                        'AccountId': selectedRevenueAccId,
                        'DebitAmount': 0,
                        'CreditAmount': newAmount,
                        'Description': 'إيراد: ${descCtrl.text}',
                      },
                    ],
                  });

                  if (result['success'] == true) {
                    _snack('تم تعديل الإيراد', AccountingTheme.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                  }
                },
                child: const Text('حفظ التعديل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDeleteRevenue(Map<String, dynamic> entry) {
    final entryId = entry['Id']?.toString();
    if (entryId == null) return;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('حذف الإيراد',
              style: TextStyle(
                  color: AccountingTheme.danger, fontWeight: FontWeight.bold)),
          content: Text(
            'هل أنت متأكد من حذف الإيراد "${entry['Description'] ?? ''}"؟\nسيتم حذف القيد المحاسبي المرتبط.',
            style: const TextStyle(color: AccountingTheme.textPrimary),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance
                    .deleteJournalEntry(entryId);
                if (result['success'] == true) {
                  _snack('تم حذف الإيراد', AccountingTheme.success);
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                }
              },
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRevenueDialog() async {
    if (_allAccounts.isEmpty) {
      final result = await AccountingService.instance
          .getAccounts(companyId: widget.companyId);
      if (result['success'] == true) {
        _allAccounts = (result['data'] as List?) ?? [];
      }
    }

    // حسابات الإيراد (دائن - حسابات نهائية فقط)
    final revenueAccounts = _allAccounts
        .where((a) =>
            a['AccountType']?.toString() == 'Revenue' ||
            (a['Code']?.toString() ?? '').startsWith('4'))
        .where((a) => a['IsLeaf'] == true)
        .toList();

    // حسابات الأصول (مدين - حسابات نهائية فقط)
    final assetAccounts = _allAccounts
        .where((a) =>
            a['AccountType']?.toString() == 'Assets' ||
            (a['Code']?.toString() ?? '').startsWith('1'))
        .where((a) => a['IsLeaf'] == true)
        .toList();

    if (revenueAccounts.isEmpty) {
      _snack('لا توجد حسابات إيرادات. قم ببذر دليل الحسابات أولاً',
          AccountingTheme.warning);
      return;
    }
    if (assetAccounts.isEmpty) {
      _snack('لا توجد حسابات أصول', AccountingTheme.warning);
      return;
    }

    if (!mounted) return;

    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? selectedRevenueAccId = revenueAccounts.first['Id']?.toString();
    String? selectedAssetAccId = assetAccounts.first['Id']?.toString();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Text('إضافة إيراد',
                style: TextStyle(
                    color: AccountingTheme.success,
                    fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: context.accR.isMobile
                  ? MediaQuery.of(context).size.width * 0.90
                  : 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // الوصف
                    _field('الوصف *', descCtrl),
                    SizedBox(height: context.accR.spaceM),
                    // المبلغ
                    _field('المبلغ *', amountCtrl, isNumber: true),
                    SizedBox(height: context.accR.spaceM),
                    // حساب الإيراد (دائن)
                    DropdownButtonFormField<String>(
                      value: selectedRevenueAccId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: revenueAccounts.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Name']}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedRevenueAccId = v),
                      decoration: _inputDeco('حساب الإيراد (دائن)'),
                    ),
                    SizedBox(height: context.accR.spaceM),
                    // حساب الأصل (مدين - أين يذهب المال)
                    DropdownButtonFormField<String>(
                      value: selectedAssetAccId,
                      dropdownColor: AccountingTheme.bgCard,
                      style:
                          const TextStyle(color: AccountingTheme.textPrimary),
                      isExpanded: true,
                      items: assetAccounts.map<DropdownMenuItem<String>>((a) {
                        return DropdownMenuItem(
                          value: a['Id']?.toString(),
                          child: Text('${a['Name']}',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (v) => ss(() => selectedAssetAccId = v),
                      decoration: _inputDeco('حساب القبض (مدين)'),
                    ),
                    SizedBox(height: context.accR.spaceM),
                    // ملاحظات
                    _field('ملاحظات', notesCtrl),
                    SizedBox(height: context.accR.spaceS),
                    // توضيح القيد
                    Container(
                      padding: EdgeInsets.all(context.accR.spaceM),
                      decoration: BoxDecoration(
                        color: AccountingTheme.success.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                AccountingTheme.success.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('القيد الناتج:',
                              style: TextStyle(
                                  color: AccountingTheme.success,
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold)),
                          SizedBox(height: context.accR.spaceXS),
                          Row(
                            children: [
                              Icon(Icons.arrow_forward,
                                  color: AccountingTheme.accent,
                                  size: context.accR.iconXS),
                              SizedBox(width: context.accR.spaceXS),
                              Expanded(
                                child: Text('حساب القبض ← مدين',
                                    style: TextStyle(
                                        color: AccountingTheme.accent,
                                        fontSize: context.accR.small)),
                              ),
                              Text(
                                  amountCtrl.text.isNotEmpty
                                      ? amountCtrl.text
                                      : '0',
                                  style: TextStyle(
                                      color: AccountingTheme.accent,
                                      fontSize: context.accR.small)),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(Icons.arrow_back,
                                  color: AccountingTheme.success,
                                  size: context.accR.iconXS),
                              SizedBox(width: context.accR.spaceXS),
                              Expanded(
                                child: Text('حساب الإيراد ← دائن',
                                    style: TextStyle(
                                        color: AccountingTheme.success,
                                        fontSize: context.accR.small)),
                              ),
                              Text(
                                  amountCtrl.text.isNotEmpty
                                      ? amountCtrl.text
                                      : '0',
                                  style: TextStyle(
                                      color: AccountingTheme.success,
                                      fontSize: context.accR.small)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء',
                      style: TextStyle(color: AccountingTheme.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AccountingTheme.neonGreen,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  if (descCtrl.text.isEmpty || amount <= 0) {
                    _snack('الرجاء ملء الوصف والمبلغ', AccountingTheme.warning);
                    return;
                  }
                  if (selectedRevenueAccId == null ||
                      selectedAssetAccId == null) {
                    _snack('الرجاء اختيار الحسابات', AccountingTheme.warning);
                    return;
                  }
                  Navigator.pop(ctx);

                  // إنشاء قيد محاسبي: مدين حساب الأصل / دائن حساب الإيراد
                  final userId = VpsAuthService.instance.currentUser?.id;
                  final result =
                      await AccountingService.instance.createJournalEntry(
                    description: descCtrl.text,
                    lines: [
                      {
                        'AccountId': selectedAssetAccId,
                        'DebitAmount': amount,
                        'CreditAmount': 0,
                        'Description': 'قبض إيراد: ${descCtrl.text}',
                      },
                      {
                        'AccountId': selectedRevenueAccId,
                        'DebitAmount': 0,
                        'CreditAmount': amount,
                        'Description': 'إيراد: ${descCtrl.text}',
                      },
                    ],
                    notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                    companyId: widget.companyId ?? '',
                    createdById: userId,
                  );

                  if (result['success'] == true) {
                    // ترحيل القيد مباشرة
                    final entryId = result['data']?['Id']?.toString();
                    if (entryId != null) {
                      await AccountingService.instance
                          .postJournalEntry(entryId, approvedById: userId);
                    }
                    _snack('تم تسجيل الإيراد', AccountingTheme.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                  }
                },
                child: const Text('تسجيل الإيراد'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: _inputDeco(label),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AccountingTheme.textMuted),
      filled: true,
      fillColor: AccountingTheme.bgCardHover,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    );
  }

  Map<String, dynamic> _statusInfo(String status) {
    switch (status) {
      case 'Posted':
        return {'label': 'مرحل', 'color': AccountingTheme.success};
      case 'Voided':
        return {'label': 'ملغي', 'color': AccountingTheme.danger};
      default:
        return {'label': 'مسودة', 'color': AccountingTheme.textMuted};
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _fmt(dynamic value) {
    if (value == null || value == 0) return '0';
    final n = value is num ? value : double.tryParse(value.toString()) ?? 0;
    return n.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString()).toLocal();
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
