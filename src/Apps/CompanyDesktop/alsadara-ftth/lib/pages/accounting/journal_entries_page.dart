import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/period_closing_service.dart';
import '../../services/audit_trail_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';
import '../../widgets/accounting_skeleton.dart';
import '../../permissions/permissions.dart';

/// صفحة القيود المحاسبية
class JournalEntriesPage extends StatefulWidget {
  final String? companyId;

  const JournalEntriesPage({super.key, this.companyId});

  @override
  State<JournalEntriesPage> createState() => _JournalEntriesPageState();
}

class _JournalEntriesPageState extends State<JournalEntriesPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _entries = [];
  String _statusFilter = 'all'; // all, Draft, Posted, Voided
  int _currentPage = 1;
  int _totalPages = 1;
  int _total = 0;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await AccountingService.instance
          .getJournalEntries(companyId: widget.companyId);
      if (result['success'] == true) {
        List all;
        if (result['data'] is Map) {
          final dataMap = result['data'] as Map<String, dynamic>;
          all = (dataMap['items'] ?? dataMap['entries'] ?? []) as List;
          _currentPage = (dataMap['page'] ?? page) as int;
          _totalPages = (dataMap['totalPages'] ?? 1) as int;
          _total = (dataMap['total'] ?? all.length) as int;
        } else {
          all = (result['data'] is List) ? result['data'] as List : [];
          _currentPage = 1;
          _totalPages = 1;
          _total = all.length;
        }
        if (_statusFilter != 'all') {
          _entries = all
              .where((e) => e['Status']?.toString() == _statusFilter)
              .toList();
        } else {
          _entries = all;
        }
      } else {
        _errorMessage = result['message'] ?? 'خطأ';
      }
    } catch (e) {
      _errorMessage = 'خطأ';
    }
    setState(() {
      _isLoading = false;
    });
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
              _buildToolbar(),
              _buildFilterBar(),
              Expanded(
                child: _isLoading
                    ? const AccountingSkeleton(rows: 8, columns: 4)
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  color: AccountingTheme.textMuted
                                      .withOpacity(0.3),
                                  size: context.accR.iconXL),
                              SizedBox(height: context.accR.spaceM),
                              Text(_errorMessage!,
                                  style: GoogleFonts.cairo(
                                      color: AccountingTheme.textSecondary,
                                      fontSize: context.accR.body)),
                            ],
                          ))
                        : _buildList(),
              ),
              _buildPaginationBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final isMobile = context.accR.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : context.accR.spaceXL,
          vertical: isMobile ? 6 : context.accR.spaceL),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            iconSize: isMobile ? 20 : 24,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          if (!isMobile) SizedBox(width: context.accR.spaceS),
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : context.accR.spaceS),
            decoration: BoxDecoration(
              gradient: AccountingTheme.neonGreenGradient,
              borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
            ),
            child: Icon(Icons.menu_book_rounded,
                color: Colors.white, size: isMobile ? 16 : context.accR.iconM),
          ),
          SizedBox(width: isMobile ? 6 : context.accR.spaceM),
          Expanded(
            child: Text('القيود المحاسبية',
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 14 : context.accR.headingMedium,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.textPrimary,
                )),
          ),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 6 : 8, vertical: isMobile ? 1 : 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonPink.withOpacity(0.2),
              borderRadius: BorderRadius.circular(context.accR.cardRadius),
            ),
            child: Text('${_entries.length}',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 10 : context.accR.small,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonPink,
                )),
          ),
          SizedBox(width: isMobile ? 4 : 0),
          if (!isMobile) Spacer(),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh, size: isMobile ? 18 : context.accR.iconM),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMobile ? 0 : context.accR.spaceXS),
          if (PermissionManager.instance.canAdd('accounting.journals'))
            isMobile
                ? SizedBox(
                    height: 30,
                    child: ElevatedButton(
                      onPressed: _showCreateDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AccountingTheme.neonGreen,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size(30, 30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Icon(Icons.add, size: 16),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _showCreateDialog,
                    icon: Icon(Icons.add, size: context.accR.iconS),
                    label: Text('إنشاء قيد',
                        style: GoogleFonts.cairo(
                            fontSize: context.accR.financialSmall)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AccountingTheme.neonGreen,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: context.accR.spaceL,
                          vertical: context.accR.spaceS),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final filters = [
      {
        'value': 'all',
        'label': 'الكل',
        'icon': Icons.check,
        'color': AccountingTheme.neonBlue
      },
      {
        'value': 'Draft',
        'label': 'مسودة',
        'icon': Icons.drafts,
        'color': AccountingTheme.textMuted
      },
      {
        'value': 'Posted',
        'label': 'مرحل',
        'icon': Icons.check_circle,
        'color': AccountingTheme.neonGreen
      },
      {
        'value': 'Voided',
        'label': 'ملغي',
        'icon': Icons.cancel,
        'color': AccountingTheme.danger
      },
    ];

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.accR.spaceXL, vertical: context.accR.spaceM),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          ...filters.map((f) {
            final isSelected = _statusFilter == f['value'];
            final color = f['color'] as Color;
            return Padding(
              padding: EdgeInsets.only(left: 8),
              child: InkWell(
                onTap: () {
                  setState(() => _statusFilter = f['value'] as String);
                  _loadData();
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: context.accR.spaceM,
                      vertical: context.accR.spaceXS),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? color.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? color.withOpacity(0.5)
                          : AccountingTheme.borderColor,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        Icon(f['icon'] as IconData,
                            size: context.accR.iconS, color: color),
                        SizedBox(width: context.accR.spaceXS),
                      ],
                      Text(f['label'] as String,
                          style: GoogleFonts.cairo(
                            fontSize: context.accR.small,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? color
                                : AccountingTheme.textSecondary,
                          )),
                    ],
                  ),
                ),
              ),
            );
          }),
          Spacer(),
          Text('${_entries.length} قيد',
              style: GoogleFonts.cairo(
                  color: AccountingTheme.textMuted,
                  fontSize: context.accR.financialSmall)),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book,
                color: AccountingTheme.textMuted.withOpacity(0.3),
                size: context.accR.iconXL),
            SizedBox(height: context.accR.spaceM),
            Text('لا توجد قيود',
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textMuted,
                    fontSize: context.accR.headingSmall)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(context.accR.spaceXL),
      itemCount: _entries.length,
      itemBuilder: (_, i) {
        final entry = _entries[i];
        final status = entry['Status']?.toString() ?? 'Draft';
        final statusInfo = _statusInfo(status);
        final lines = (entry['Lines'] as List?) ?? [];
        final totalDebit = lines.fold<double>(
            0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble());

        return Container(
          margin: EdgeInsets.only(bottom: context.accR.spaceS),
          decoration: BoxDecoration(
            color: AccountingTheme.bgCard,
            borderRadius: BorderRadius.circular(context.accR.cardRadius),
            border: Border.all(color: AccountingTheme.borderColor),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1)),
            ],
          ),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            iconColor: AccountingTheme.textMuted,
            collapsedIconColor: AccountingTheme.textMuted,
            title: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color:
                        (statusInfo['color'] as Color).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: (statusInfo['color'] as Color)
                            .withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    statusInfo['label'] as String,
                    style: GoogleFonts.cairo(
                        color: statusInfo['color'] as Color,
                        fontSize: context.accR.small,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(width: context.accR.spaceM),
                Expanded(
                  child: Text(
                    entry['Description'] ??
                        'قيد #${entry['EntryNumber'] ?? i + 1}',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textPrimary,
                        fontSize: context.accR.body),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${_fmt(totalDebit)} د.ع',
                  style: GoogleFonts.cairo(
                      color: AccountingTheme.neonGreen,
                      fontSize: context.accR.financialSmall,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (entry['EntryNumber'] != null)
                    Text('#${entry['EntryNumber']}  ',
                        style: GoogleFonts.cairo(
                            color: AccountingTheme.neonBlue,
                            fontSize: context.accR.small)),
                  Text(_formatDate(entry['EntryDate'] ?? entry['CreatedAt']),
                      style: GoogleFonts.cairo(
                          color: AccountingTheme.textMuted,
                          fontSize: context.accR.small)),
                  if (entry['ReferenceType'] != null) ...[
                    Text('  |  ',
                        style: TextStyle(color: AccountingTheme.textMuted)),
                    Text(_refTypeLabel(entry['ReferenceType']),
                        style: GoogleFonts.cairo(
                            color: AccountingTheme.textSecondary,
                            fontSize: context.accR.small)),
                  ],
                ],
              ),
            ),
            children: [
              // خطوط القيد
              if (lines.isNotEmpty) ...[
                Container(
                  decoration: BoxDecoration(
                    color: AccountingTheme.bgCardHover,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Text('الحساب',
                                    style: TextStyle(
                                        color: AccountingTheme.textMuted,
                                        fontSize: context.accR.small))),
                            SizedBox(
                                width: 80,
                                child: Text('مدين',
                                    style: TextStyle(
                                        color: AccountingTheme.neonGreen,
                                        fontSize: context.accR.small),
                                    textAlign: TextAlign.center)),
                            SizedBox(
                                width: 80,
                                child: Text('دائن',
                                    style: TextStyle(
                                        color: AccountingTheme.danger,
                                        fontSize: context.accR.small),
                                    textAlign: TextAlign.center)),
                          ],
                        ),
                      ),
                      const Divider(
                          color: AccountingTheme.borderColor, height: 1),
                      ...lines.map<Widget>((line) {
                        final debit =
                            ((line['DebitAmount'] ?? 0) as num).toDouble();
                        final credit =
                            ((line['CreditAmount'] ?? 0) as num).toDouble();
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  line['AccountName'] ??
                                      'حساب #${line['AccountId']}',
                                  style: TextStyle(
                                      color: AccountingTheme.textSecondary,
                                      fontSize: context.accR.financialSmall),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  debit > 0 ? _fmt(debit) : '-',
                                  style: TextStyle(
                                      color: debit > 0
                                          ? AccountingTheme.neonGreen
                                          : AccountingTheme.textMuted,
                                      fontSize: context.accR.financialSmall),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  credit > 0 ? _fmt(credit) : '-',
                                  style: TextStyle(
                                      color: credit > 0
                                          ? AccountingTheme.danger
                                          : AccountingTheme.textMuted,
                                      fontSize: context.accR.financialSmall),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
              SizedBox(height: context.accR.spaceS),
              // الأزرار
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status == 'Draft') ...[
                    if (PermissionManager.instance.canEdit('accounting.journals'))
                      TextButton.icon(
                        onPressed: () => _showEditEntryDialog(entry),
                        icon: Icon(Icons.edit, size: context.accR.iconXS),
                        label: Text('تعديل',
                            style: TextStyle(fontSize: context.accR.small)),
                        style: TextButton.styleFrom(
                            foregroundColor: AccountingTheme.info),
                      ),
                    SizedBox(width: context.accR.spaceS),
                    if (PermissionManager.instance.canEdit('accounting.journals'))
                      TextButton.icon(
                        onPressed: () => _postEntry(entry),
                        icon: Icon(Icons.check_circle, size: context.accR.iconXS),
                        label: Text('ترحيل',
                            style: TextStyle(fontSize: context.accR.small)),
                        style: TextButton.styleFrom(
                            foregroundColor: AccountingTheme.success),
                      ),
                    SizedBox(width: context.accR.spaceS),
                  ],
                  if (status == 'Posted')
                    if (PermissionManager.instance.canEdit('accounting.journals'))
                      TextButton.icon(
                        onPressed: () => _voidEntry(entry),
                        icon: Icon(Icons.cancel, size: context.accR.iconXS),
                        label: Text('إلغاء',
                            style: TextStyle(fontSize: context.accR.small)),
                        style: TextButton.styleFrom(
                            foregroundColor: AccountingTheme.danger),
                      ),
                  if (status != 'Voided') ...[
                    SizedBox(width: context.accR.spaceS),
                    if (PermissionManager.instance.canDelete('accounting.journals'))
                      TextButton.icon(
                        onPressed: () => _confirmDeleteEntry(entry),
                        icon:
                            Icon(Icons.delete_outline, size: context.accR.iconXS),
                        label: Text('حذف',
                            style: TextStyle(fontSize: context.accR.small)),
                        style: TextButton.styleFrom(
                            foregroundColor: AccountingTheme.danger),
                      ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaginationBar() {
    if (_totalPages <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(top: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1 ? () => _loadData(page: _currentPage - 1) : null,
            icon: const Icon(Icons.chevron_right, color: AccountingTheme.textSecondary),
          ),
          Text(
            'صفحة $_currentPage من $_totalPages ($_total سجل)',
            style: GoogleFonts.cairo(color: AccountingTheme.textSecondary, fontSize: 13),
          ),
          IconButton(
            onPressed: _currentPage < _totalPages ? () => _loadData(page: _currentPage + 1) : null,
            icon: const Icon(Icons.chevron_left, color: AccountingTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog() async {
    // جلب دليل الحسابات أولاً
    final accountsResult = await AccountingService.instance
        .getAccounts(companyId: widget.companyId);
    if (accountsResult['success'] != true) {
      _snack('خطأ في جلب الحسابات', AccountingTheme.danger);
      return;
    }
    final accounts = (accountsResult['data'] as List?) ?? [];
    if (accounts.length < 2) {
      _snack('يجب أن يكون لديك حسابين على الأقل لإنشاء قيد',
          AccountingTheme.warning);
      return;
    }

    if (!mounted) return;

    final descCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final lines = <Map<String, dynamic>>[
      {'accountId': null, 'debit': 0.0, 'credit': 0.0},
      {'accountId': null, 'debit': 0.0, 'credit': 0.0},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) {
          final totalDebit =
              lines.fold<double>(0, (s, l) => s + (l['debit'] as double));
          final totalCredit =
              lines.fold<double>(0, (s, l) => s + (l['credit'] as double));
          final isBalanced =
              totalDebit > 0 && (totalDebit - totalCredit).abs() < 0.01;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: AccountingTheme.bgCard,
              title: Text('إنشاء قيد محاسبي',
                  style: TextStyle(color: AccountingTheme.textPrimary)),
              content: SizedBox(
                width: context.accR.dialogLargeW,
                height: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field('الوصف', descCtrl),
                      SizedBox(height: context.accR.spaceM),
                      // خطوط القيد
                      Text('خطوط القيد:',
                          style: TextStyle(
                              color: AccountingTheme.textPrimary,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: context.accR.spaceS),
                      ...List.generate(lines.length, (i) {
                        final amtDebitCtrl = TextEditingController(
                          text: lines[i]['debit'] > 0
                              ? lines[i]['debit'].toString()
                              : '',
                        );
                        final amtCreditCtrl = TextEditingController(
                          text: lines[i]['credit'] > 0
                              ? lines[i]['credit'].toString()
                              : '',
                        );

                        return Container(
                          margin: EdgeInsets.only(bottom: context.accR.spaceS),
                          padding: EdgeInsets.all(context.accR.spaceS),
                          decoration: BoxDecoration(
                            color: AccountingTheme.bgCardHover,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  value: lines[i]['accountId']?.toString(),
                                  dropdownColor: AccountingTheme.bgCard,
                                  style: TextStyle(
                                      color: AccountingTheme.textPrimary,
                                      fontSize: context.accR.small),
                                  isExpanded: true,
                                  items: accounts
                                      .map<DropdownMenuItem<String>>((a) {
                                    return DropdownMenuItem(
                                      value: a['Id']?.toString(),
                                      child: Text('${a['Code']} - ${a['Name']}',
                                          overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                  onChanged: (v) =>
                                      ss(() => lines[i]['accountId'] = v),
                                  decoration: InputDecoration(
                                    labelText: 'الحساب',
                                    labelStyle: TextStyle(
                                        color: AccountingTheme.textMuted,
                                        fontSize: context.accR.small),
                                    filled: true,
                                    fillColor: AccountingTheme.bgCardHover,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                  ),
                                ),
                              ),
                              SizedBox(width: context.accR.spaceS),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: amtDebitCtrl,
                                  style: TextStyle(
                                      color: AccountingTheme.success,
                                      fontSize: context.accR.financialSmall),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => ss(() => lines[i]['debit'] =
                                      double.tryParse(v) ?? 0.0),
                                  decoration: InputDecoration(
                                    labelText: 'مدين',
                                    labelStyle: TextStyle(
                                        color: AccountingTheme.accent,
                                        fontSize: context.accR.caption),
                                    filled: true,
                                    fillColor: AccountingTheme.bgCardHover,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                  ),
                                ),
                              ),
                              SizedBox(width: context.accR.spaceS),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: amtCreditCtrl,
                                  style: TextStyle(
                                      color: AccountingTheme.danger,
                                      fontSize: context.accR.financialSmall),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => ss(() => lines[i]
                                      ['credit'] = double.tryParse(v) ?? 0.0),
                                  decoration: InputDecoration(
                                    labelText: 'دائن',
                                    labelStyle: TextStyle(
                                        color: AccountingTheme.danger,
                                        fontSize: context.accR.caption),
                                    filled: true,
                                    fillColor: AccountingTheme.bgCardHover,
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                  ),
                                ),
                              ),
                              if (lines.length > 2)
                                IconButton(
                                  icon: Icon(Icons.remove_circle,
                                      color: AccountingTheme.danger,
                                      size: context.accR.iconM),
                                  onPressed: () => ss(() => lines.removeAt(i)),
                                ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () => ss(() => lines.add(
                            {'accountId': null, 'debit': 0.0, 'credit': 0.0})),
                        icon: Icon(Icons.add, size: context.accR.iconXS),
                        label: Text('إضافة سطر',
                            style: TextStyle(fontSize: context.accR.small)),
                        style: TextButton.styleFrom(
                            foregroundColor: AccountingTheme.accent),
                      ),
                      SizedBox(height: context.accR.spaceS),
                      // الإجماليات
                      Container(
                        padding: EdgeInsets.all(context.accR.spaceS),
                        decoration: BoxDecoration(
                          color: isBalanced
                              ? AccountingTheme.success.withValues(alpha: 0.2)
                              : AccountingTheme.danger.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: isBalanced
                                  ? AccountingTheme.success
                                  : AccountingTheme.danger,
                              width: 0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text('مدين: ${_fmt(totalDebit)}',
                                style: TextStyle(
                                    color: AccountingTheme.accent,
                                    fontSize: context.accR.financialSmall)),
                            Text('دائن: ${_fmt(totalCredit)}',
                                style: TextStyle(
                                    color: AccountingTheme.danger,
                                    fontSize: context.accR.financialSmall)),
                            Icon(
                              isBalanced ? Icons.check_circle : Icons.warning,
                              color: isBalanced
                                  ? AccountingTheme.success
                                  : AccountingTheme.danger,
                              size: context.accR.iconM,
                            ),
                            Text(
                              isBalanced ? 'متوازن' : 'غير متوازن',
                              style: TextStyle(
                                  color: isBalanced
                                      ? AccountingTheme.success
                                      : AccountingTheme.danger,
                                  fontSize: context.accR.small),
                            ),
                          ],
                        ),
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
                    backgroundColor: isBalanced
                        ? AccountingTheme.neonGreen
                        : AccountingTheme.textMuted,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isBalanced
                      ? () async {
                          if (descCtrl.text.isEmpty) {
                            _snack('الرجاء إدخال وصف', AccountingTheme.warning);
                            return;
                          }
                          // تحقق من اختيار الحسابات
                          final validLines = lines
                              .where((l) =>
                                  l['accountId'] != null &&
                                  (l['debit'] > 0 || l['credit'] > 0))
                              .toList();
                          if (validLines.length < 2) {
                            _snack('يجب أن يكون هناك سطران على الأقل',
                                AccountingTheme.warning);
                            return;
                          }
                          Navigator.pop(ctx);
                          // فحص الفترة المحاسبية
                          final periodOk = await PeriodClosingService.checkAndWarnIfClosed(
                            context, date: DateTime.now(), companyId: widget.companyId ?? '',
                          );
                          if (!periodOk) return;
                          final userId =
                              VpsAuthService.instance.currentUser?.id;
                          final result = await AccountingService.instance
                              .createJournalEntry(
                            description: descCtrl.text,
                            lines: validLines
                                .map((l) => {
                                      'AccountId': l['accountId'],
                                      'DebitAmount': l['debit'],
                                      'CreditAmount': l['credit'],
                                    })
                                .toList(),
                            notes:
                                notesCtrl.text.isEmpty ? null : notesCtrl.text,
                            companyId: widget.companyId ?? '',
                            createdById: userId,
                          );
                          if (result['success'] == true) {
                            _snack('تم إنشاء القيد', AccountingTheme.success);
                            AuditTrailService.instance.log(
                              action: AuditAction.create,
                              entityType: AuditEntityType.journalEntry,
                              entityId: result['data']?['Id']?.toString() ?? '',
                              entityDescription: 'قيد: ${descCtrl.text}',
                            );
                            _loadData();
                          } else {
                            _snack(result['message'] ?? 'خطأ',
                                AccountingTheme.danger);
                          }
                        }
                      : null,
                  child: const Text('إنشاء'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _postEntry(dynamic entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('ترحيل القيد',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: const Text(
              'هل تريد ترحيل هذا القيد؟ لا يمكن التعديل بعد الترحيل.',
              style: TextStyle(color: AccountingTheme.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.success),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ترحيل'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    // فحص الفترة المحاسبية
    final postDate = DateTime.tryParse(entry['EntryDate']?.toString() ?? entry['CreatedAt']?.toString() ?? '');
    if (postDate != null) {
      final allowed = await PeriodClosingService.checkAndWarnIfClosed(
        context, date: postDate, companyId: widget.companyId ?? '',
      );
      if (!allowed) return;
    }

    final result = await AccountingService.instance.postJournalEntry(
        entry['Id'].toString(),
        approvedById: VpsAuthService.instance.currentUser?.id);
    if (result['success'] == true) {
      _snack('تم ترحيل القيد', AccountingTheme.success);
      AuditTrailService.instance.log(
        action: AuditAction.post,
        entityType: AuditEntityType.journalEntry,
        entityId: entry['Id']?.toString() ?? '',
        entityDescription: 'قيد: ${entry['Description'] ?? ''}',
      );
      _loadData();
    } else {
      _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
    }
  }

  void _voidEntry(dynamic entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('إلغاء القيد',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: Text('هل تريد إلغاء هذا القيد؟ سيتم عكس جميع الأرصدة.',
              style: TextStyle(color: AccountingTheme.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('رجوع',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء القيد'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    // فحص الفترة المحاسبية
    final voidDate = DateTime.tryParse(entry['EntryDate']?.toString() ?? entry['CreatedAt']?.toString() ?? '');
    if (voidDate != null) {
      final allowed = await PeriodClosingService.checkAndWarnIfClosed(
        context, date: voidDate, companyId: widget.companyId ?? '',
      );
      if (!allowed) return;
    }

    final result = await AccountingService.instance
        .voidJournalEntry(entry['Id'].toString());
    if (result['success'] == true) {
      _snack('تم إلغاء القيد', AccountingTheme.success);
      AuditTrailService.instance.log(
        action: AuditAction.void_,
        entityType: AuditEntityType.journalEntry,
        entityId: entry['Id']?.toString() ?? '',
        entityDescription: 'قيد: ${entry['Description'] ?? ''}',
      );
      _loadData();
    } else {
      _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
    }
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

  String _refTypeLabel(dynamic refType) {
    switch (refType?.toString()) {
      case 'Manual':
        return 'يدوي';
      case 'CashTransaction':
        return 'حركة صندوق';
      case 'Salary':
        return 'رواتب';
      case 'TechnicianCollection':
        return 'تحصيل';
      case 'Expense':
        return 'مصروف';
      default:
        return refType?.toString() ?? '';
    }
  }

  Widget _field(String label, TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: AccountingTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
        filled: true,
        fillColor: AccountingTheme.bgCardHover,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none),
      ),
    );
  }

  void _showEditEntryDialog(Map<String, dynamic> entry) {
    final descCtrl = TextEditingController(text: entry['Description'] ?? '');
    final notesCtrl = TextEditingController(text: entry['Notes'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تعديل القيد',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: SizedBox(
            width: context.accR.dialogSmallW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: descCtrl,
                  style: const TextStyle(color: AccountingTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'الوصف',
                    labelStyle:
                        const TextStyle(color: AccountingTheme.textMuted),
                    filled: true,
                    fillColor: AccountingTheme.bgCardHover,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: context.accR.spaceM),
                TextField(
                  controller: notesCtrl,
                  style: const TextStyle(color: AccountingTheme.textPrimary),
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'ملاحظات',
                    labelStyle:
                        const TextStyle(color: AccountingTheme.textMuted),
                    filled: true,
                    fillColor: AccountingTheme.bgCardHover,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.info,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                // فحص الفترة المحاسبية
                final editDate = DateTime.tryParse(entry['EntryDate']?.toString() ?? entry['CreatedAt']?.toString() ?? '');
                if (editDate != null) {
                  final allowed = await PeriodClosingService.checkAndWarnIfClosed(
                    context, date: editDate, companyId: widget.companyId ?? '',
                  );
                  if (!allowed) return;
                }
                final result =
                    await AccountingService.instance.updateJournalEntry(
                  entry['Id'].toString(),
                  {
                    'Description': descCtrl.text,
                    'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                  },
                );
                if (result['success'] == true) {
                  _snack('تم تحديث القيد', AccountingTheme.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.edit,
                    entityType: AuditEntityType.journalEntry,
                    entityId: entry['Id']?.toString() ?? '',
                    entityDescription: 'قيد: ${descCtrl.text}',
                  );
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', AccountingTheme.danger);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteEntry(Map<String, dynamic> entry) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('تأكيد الحذف',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
            'هل تريد حذف القيد "${entry['Description'] ?? 'قيد #${entry['EntryNumber']}'}"؟\nسيتم عكس أرصدة الحسابات المتأثرة.',
            style: const TextStyle(color: AccountingTheme.textPrimary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: AccountingTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                // فحص الفترة المحاسبية
                final delDate = DateTime.tryParse(entry['EntryDate']?.toString() ?? entry['CreatedAt']?.toString() ?? '');
                if (delDate != null) {
                  final allowed = await PeriodClosingService.checkAndWarnIfClosed(
                    context, date: delDate, companyId: widget.companyId ?? '',
                  );
                  if (!allowed) return;
                }
                final result = await AccountingService.instance
                    .deleteJournalEntry(entry['Id'].toString());
                if (result['success'] == true) {
                  _snack('تم حذف القيد', AccountingTheme.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.delete,
                    entityType: AuditEntityType.journalEntry,
                    entityId: entry['Id']?.toString() ?? '',
                    entityDescription: 'قيد: ${entry['Description'] ?? ''}',
                  );
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

  void _snack(String msg, Color color) {
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
      final d = DateTime.parse(date.toString());
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
