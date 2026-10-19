import 'package:flutter/material.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_responsive.dart';
import '../../permissions/permissions.dart';

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
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'الإيرادات',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _loadData,
            ),
            if (PermissionManager.instance.canAdd('accounting.revenue'))
              SdAppBarAction(
                icon: Icons.add,
                label: 'إضافة إيراد',
                onPressed: _showAddRevenueDialog,
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? Center(
                      child: Text(_errorMessage!,
                          style: const TextStyle(
                              color: SdColors.danger)))
                  : Column(
                      children: [
                        _buildSummaryAndFilters(),
                        Expanded(child: _buildEntriesList()),
                      ],
                    ),
        ),
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
      decoration: const BoxDecoration(
        color: SdColors.surface,
        border: Border(bottom: BorderSide(color: SdColors.divider)),
      ),
      child: Column(
        children: [
          // بطاقة الإجمالي
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 14 : 20, vertical: isMob ? 10 : 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  SdStatus.success.tone.light,
                  SdStatus.success.tone.base,
                ],
              ),
              borderRadius: BorderRadius.circular(SdRadius.md),
              boxShadow: [
                BoxShadow(
                  color: SdStatus.success.tone.edge,
                  offset: const Offset(0, SdDepth.button),
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
                            fontSize: isMob ? 11.5 : 12),
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
                      color: SdStatus.danger.tone.tint,
                      borderRadius: BorderRadius.circular(SdRadius.xs),
                      border: Border.all(color: SdStatus.danger.tone.tintEdge),
                    ),
                    child: Icon(Icons.clear_all,
                        color: SdStatus.danger.tone.base, size: isMob ? 18 : 20),
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
            ? SdColors.primaryTint
            : SdColors.surfaceAlt,
        borderRadius: BorderRadius.circular(SdRadius.xs),
        border: Border.all(
          color: _selectedRevenueType != 'الكل'
              ? SdColors.primaryTintEdge
              : SdColors.edge,
          width: 1.2,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedRevenueType,
          isExpanded: true,
          icon: Icon(Icons.filter_list,
              size: isMob ? 16 : 18, color: SdColors.muted),
          style: TextStyle(
              fontFamily: SdText.family,
              color: SdColors.ink,
              fontSize: isMob ? 12.5 : 14,
              fontWeight: FontWeight.w600),
          dropdownColor: Colors.white,
          items: types.map((t) {
            return DropdownMenuItem(
              value: t,
              child: Text(t, style: TextStyle(fontSize: isMob ? 12.5 : 14)),
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
              ? SdStatus.info.tone.tint
              : SdColors.surfaceAlt,
          borderRadius: BorderRadius.circular(SdRadius.xs),
          border: Border.all(
            color: isActive ? SdStatus.info.tone.tintEdge : SdColors.edge,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: isMob ? 14 : 16,
                color: isActive ? SdStatus.info.tone.base : SdColors.muted),
            SizedBox(width: isMob ? 4 : 6),
            Text(label,
                style: TextStyle(
                    fontFamily: SdText.family,
                    color: isActive ? SdStatus.info.tone.text : SdColors.ink,
                    fontSize: isMob ? 11.5 : 13,
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
              primary: SdColors.success,
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
      return const SingleChildScrollView(
        child: SdEmptyState(
          title: 'لا توجد قيود إيرادات',
          message: 'اضغط + لإضافة إيراد جديد',
          icon: Icons.trending_up,
          status: SdStatus.success,
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(context.accR.spaceM, SdSpace.xs, context.accR.spaceM, SdSpace.md),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final entry = filtered[i];
        final lines = entry['Lines'] as List? ?? [];
        final status = entry['Status']?.toString() ?? 'Draft';
        final statusTone = _statusTone(status);
        final totalDebit = (entry['TotalDebit'] ?? 0 as num).toDouble();

        return Container(
          margin: const EdgeInsets.only(bottom: SdSpace.xs),
          padding: const EdgeInsets.all(SdSpace.md),
          decoration: BoxDecoration(
            color: SdColors.surface,
            borderRadius: BorderRadius.circular(SdRadius.md),
            boxShadow: SdDepth.raised(depth: SdDepth.small),
            border: Border(
                right: BorderSide(color: statusTone.base, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry['Description'] ?? '',
                      style: SdText.label,
                    ),
                  ),
                  // الحالة
                  SdStatusChip(_statusLabel(status), status: _statusEnum(status)),
                  SizedBox(width: context.accR.spaceS),
                  Text(
                    '${_fmt(totalDebit)} د.ع',
                    style: TextStyle(
                      fontFamily: SdText.family,
                      color: SdStatus.success.tone.base,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
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
                              ? SdColors.accent
                              : SdStatus.info.tone.base,
                          size: context.accR.iconS,
                        ),
                        SizedBox(width: context.accR.spaceXS),
                        Expanded(
                          child: Text(
                            accName.toString(),
                            style: SdText.caption,
                          ),
                        ),
                        if (debit > 0)
                          Text('مدين: ${_fmt(debit)}',
                              style: TextStyle(
                                  fontFamily: SdText.family,
                                  color: SdStatus.info.tone.text,
                                  fontSize: 11.5)),
                        if (credit > 0)
                          Text('دائن: ${_fmt(credit)}',
                              style: const TextStyle(
                                  fontFamily: SdText.family,
                                  color: SdColors.accentEdge,
                                  fontSize: 11.5)),
                      ],
                    ),
                  );
                }),
              ],
              SizedBox(height: context.accR.spaceXS),
              Row(
                children: [
                  const Icon(Icons.access_time,
                      color: SdColors.faint, size: 14),
                  SizedBox(width: context.accR.spaceXS),
                  Text(
                    _formatDate(entry['EntryDate'] ?? entry['CreatedAt']),
                    style: SdText.caption,
                  ),
                  if (entry['Notes'] != null &&
                      entry['Notes'].toString().isNotEmpty) ...[
                    SizedBox(width: context.accR.spaceM),
                    Tooltip(
                      message: entry['Notes'].toString(),
                      child: const Icon(Icons.notes,
                          color: SdColors.faint, size: 14),
                    ),
                  ],
                  const Spacer(),
                  if (PermissionManager.instance.canEdit('accounting.revenue')) ...[
                    _actionBtn(Icons.edit, SdStatus.info.tone.base,
                        () => _showEditRevenueDialog(entry)),
                    SizedBox(width: context.accR.spaceXS),
                  ],
                  if (PermissionManager.instance.canDelete('accounting.revenue'))
                    _actionBtn(Icons.delete_outline, SdStatus.danger.tone.base,
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
            backgroundColor: SdColors.surface,
            title: Text('تعديل الإيراد',
                style: TextStyle(
                    color: SdColors.info, fontWeight: FontWeight.bold)),
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
                      dropdownColor: SdColors.surface,
                      style:
                          const TextStyle(color: SdColors.ink),
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
                      dropdownColor: SdColors.surface,
                      style:
                          const TextStyle(color: SdColors.ink),
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
                      style: TextStyle(color: SdColors.faint))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.info,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  final newAmount = double.tryParse(amountCtrl.text) ?? 0;
                  if (descCtrl.text.isEmpty || newAmount <= 0) {
                    _snack('الرجاء ملء الوصف والمبلغ', SdColors.warning);
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
                    _snack('تم تعديل الإيراد', SdColors.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', SdColors.danger);
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
          backgroundColor: SdColors.surface,
          title: Text('حذف الإيراد',
              style: TextStyle(
                  color: SdColors.danger, fontWeight: FontWeight.bold)),
          content: Text(
            'هل أنت متأكد من حذف الإيراد "${entry['Description'] ?? ''}"؟\nسيتم حذف القيد المحاسبي المرتبط.',
            style: const TextStyle(color: SdColors.ink),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء',
                    style: TextStyle(color: SdColors.faint))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () async {
                Navigator.pop(ctx);
                final result = await AccountingService.instance
                    .deleteJournalEntry(entryId);
                if (result['success'] == true) {
                  _snack('تم حذف الإيراد', SdColors.success);
                  _loadData();
                } else {
                  _snack(result['message'] ?? 'خطأ', SdColors.danger);
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
          SdColors.warning);
      return;
    }
    if (assetAccounts.isEmpty) {
      _snack('لا توجد حسابات أصول', SdColors.warning);
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
            backgroundColor: SdColors.surface,
            title: Text('إضافة إيراد',
                style: TextStyle(
                    color: SdColors.success,
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
                      dropdownColor: SdColors.surface,
                      style:
                          const TextStyle(color: SdColors.ink),
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
                      dropdownColor: SdColors.surface,
                      style:
                          const TextStyle(color: SdColors.ink),
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
                        color: SdColors.success.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                SdColors.success.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('القيد الناتج:',
                              style: TextStyle(
                                  color: SdColors.success,
                                  fontSize: context.accR.small,
                                  fontWeight: FontWeight.bold)),
                          SizedBox(height: context.accR.spaceXS),
                          Row(
                            children: [
                              Icon(Icons.arrow_forward,
                                  color: SdColors.success,
                                  size: context.accR.iconXS),
                              SizedBox(width: context.accR.spaceXS),
                              Expanded(
                                child: Text('حساب القبض ← مدين',
                                    style: TextStyle(
                                        color: SdColors.success,
                                        fontSize: context.accR.small)),
                              ),
                              Text(
                                  amountCtrl.text.isNotEmpty
                                      ? amountCtrl.text
                                      : '0',
                                  style: TextStyle(
                                      color: SdColors.success,
                                      fontSize: context.accR.small)),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(Icons.arrow_back,
                                  color: SdColors.success,
                                  size: context.accR.iconXS),
                              SizedBox(width: context.accR.spaceXS),
                              Expanded(
                                child: Text('حساب الإيراد ← دائن',
                                    style: TextStyle(
                                        color: SdColors.success,
                                        fontSize: context.accR.small)),
                              ),
                              Text(
                                  amountCtrl.text.isNotEmpty
                                      ? amountCtrl.text
                                      : '0',
                                  style: TextStyle(
                                      color: SdColors.success,
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
                      style: TextStyle(color: SdColors.faint))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: SdColors.success,
                    foregroundColor: Colors.white),
                onPressed: () async {
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  if (descCtrl.text.isEmpty || amount <= 0) {
                    _snack('الرجاء ملء الوصف والمبلغ', SdColors.warning);
                    return;
                  }
                  if (selectedRevenueAccId == null ||
                      selectedAssetAccId == null) {
                    _snack('الرجاء اختيار الحسابات', SdColors.warning);
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
                    _snack('تم تسجيل الإيراد', SdColors.success);
                    _loadData();
                  } else {
                    _snack(result['message'] ?? 'خطأ', SdColors.danger);
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
      style: const TextStyle(color: SdColors.ink),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: _inputDeco(label),
    );
  }

  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: SdColors.faint),
      filled: true,
      fillColor: SdColors.surfaceAlt,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
    );
  }

  SdStatus _statusEnum(String status) {
    switch (status) {
      case 'Posted':
        return SdStatus.success;
      case 'Voided':
        return SdStatus.danger;
      default:
        return SdStatus.neutral;
    }
  }

  SdTone _statusTone(String status) => _statusEnum(status).tone;

  String _statusLabel(String status) {
    switch (status) {
      case 'Posted':
        return 'مرحل';
      case 'Voided':
        return 'ملغي';
      default:
        return 'مسودة';
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
