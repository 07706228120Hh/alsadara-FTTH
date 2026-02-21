import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/agent_api_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';

/// صفحة معاملات الوكلاء
/// تعرض جميع المعاملات المالية للوكلاء (أجور، تسديدات، خصومات، تعديلات)
class AgentTransactionsPage extends StatefulWidget {
  final String? companyId;

  const AgentTransactionsPage({super.key, this.companyId});

  @override
  State<AgentTransactionsPage> createState() => _AgentTransactionsPageState();
}

class _AgentTransactionsPageState extends State<AgentTransactionsPage> {
  bool _isLoading = true;
  String? _errorMessage;
  List<dynamic> _transactions = [];
  Map<String, dynamic>? _summary;

  // فلاتر
  int? _typeFilter; // null = الكل
  DateTime? _fromDate;
  DateTime? _toDate;
  String _dateLabel = 'الكل';
  bool _showDateFilter = false;
  int _currentPage = 1;
  int _totalPages = 1;
  int _total = 0;
  static const int _pageSize = 30;

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

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
      final result = await AgentApiService.instance.getAllTransactions(
        companyId: _companyId,
        type: _typeFilter,
        from: _fromDate,
        to: _toDate,
        page: _currentPage,
        pageSize: _pageSize,
      );
      if (result['success'] == true) {
        _transactions = (result['data'] is List) ? result['data'] as List : [];
        _summary = result['summary'] as Map<String, dynamic>?;
        _total = result['total'] ?? 0;
        _totalPages = result['totalPages'] ?? 1;
      } else {
        _errorMessage = result['message'] ?? 'خطأ';
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
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            '📋 معاملات الوكلاء',
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                _currentPage = 1;
                _loadData();
              },
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildError()
                : _buildBody(),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 64, color: AccountingTheme.danger),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: GoogleFonts.cairo(fontSize: 16)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
            label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ملخص
          if (_summary != null) _buildSummaryCards(),
          const SizedBox(height: 20),

          // فلتر التاريخ (قائمة منسدلة)
          _buildDateDropdown(),
          const SizedBox(height: 12),

          // فلتر النوع
          _buildFilters(),
          const SizedBox(height: 16),

          // الجدول
          Expanded(child: _buildTransactionsTable()),

          // الصفحات
          if (_totalPages > 1) _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final charges = (_summary?['totalCharges'] ?? 0).toDouble();
    final payments = (_summary?['totalPayments'] ?? 0).toDouble();
    final net = (_summary?['netBalance'] ?? 0).toDouble();
    final agentCount = (_summary?['agentCount'] ?? 0);

    return Row(
      children: [
        _buildSummaryCard(
          'إجمالي الأجور',
          charges,
          Icons.trending_down,
          AccountingTheme.danger,
        ),
        const SizedBox(width: 16),
        _buildSummaryCard(
          'إجمالي التسديدات',
          payments,
          Icons.trending_up,
          AccountingTheme.success,
        ),
        const SizedBox(width: 16),
        _buildSummaryCard(
          'الصافي',
          net,
          Icons.account_balance_wallet,
          net >= 0 ? AccountingTheme.neonBlue : AccountingTheme.danger,
        ),
        const SizedBox(width: 16),
        _buildInfoCard(
          'عدد الوكلاء',
          agentCount.toString(),
          Icons.people,
          AccountingTheme.neonPurple,
        ),
        const SizedBox(width: 16),
        _buildInfoCard(
          'عدد المعاملات',
          _total.toString(),
          Icons.receipt_long,
          const Color(0xFF34495E),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
      String label, double amount, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(label,
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: AccountingTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatNumber(amount)} د.ع',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AccountingTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(label,
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: AccountingTheme.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setDateFilter(String label, DateTime? from, DateTime? to) {
    setState(() {
      _dateLabel = label;
      _fromDate = from;
      _toDate = to;
      _currentPage = 1;
      _showDateFilter = false; // أغلق القائمة بعد الاختيار
    });
    _loadData();
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 7)), end: now),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: AccountingTheme.neonBlue,
              ),
            ),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      final from =
          DateTime(picked.start.year, picked.start.month, picked.start.day);
      final to = DateTime(
          picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      _setDateFilter(
        '${from.day}/${from.month} - ${to.day}/${to.month}',
        from,
        to,
      );
    }
  }

  Widget _buildDateDropdown() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = DateTime(yesterdayStart.year, yesterdayStart.month,
        yesterdayStart.day, 23, 59, 59);

    final hasFilter = _dateLabel != 'الكل';

    return Column(
      children: [
        // زر التاريخ الرئيسي (يعمل كزر للقائمة المنسدلة)
        InkWell(
          onTap: () => setState(() => _showDateFilter = !_showDateFilter),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AccountingTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _showDateFilter
                    ? AccountingTheme.neonBlue
                    : AccountingTheme.borderColor,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today,
                    size: 18,
                    color: hasFilter
                        ? AccountingTheme.neonBlue
                        : AccountingTheme.textMuted),
                const SizedBox(width: 8),
                Text('التاريخ:',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w600,
                        color: AccountingTheme.textPrimary)),
                const SizedBox(width: 8),
                if (hasFilter)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: AccountingTheme.neonBlue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(_dateLabel,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        )),
                  )
                else
                  Text('الكل',
                      style: GoogleFonts.cairo(
                          fontSize: 13, color: AccountingTheme.textMuted)),
                const Spacer(),
                AnimatedRotation(
                  turns: _showDateFilter ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down,
                      color: AccountingTheme.textMuted),
                ),
              ],
            ),
          ),
        ),

        // محتوى القائمة المنسدلة
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AccountingTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AccountingTheme.neonBlue.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildDateChip('الكل', 'الكل', null, null),
                _buildDateChip('اليوم', 'اليوم', todayStart, todayEnd),
                _buildDateChip('أمس', 'أمس', yesterdayStart, yesterdayEnd),
                _buildDateChip('آخر 7 أيام', 'آخر 7 أيام',
                    todayStart.subtract(const Duration(days: 7)), todayEnd),
                _buildDateChip('آخر 30 يوم', 'آخر 30 يوم',
                    todayStart.subtract(const Duration(days: 30)), todayEnd),
                ActionChip(
                  avatar: Icon(Icons.date_range,
                      size: 16,
                      color: _dateLabel != 'الكل' &&
                              _dateLabel != 'اليوم' &&
                              _dateLabel != 'أمس' &&
                              _dateLabel != 'آخر 7 أيام' &&
                              _dateLabel != 'آخر 30 يوم'
                          ? Colors.white
                          : AccountingTheme.textMuted),
                  label: Text('تحديد فترة...',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _dateLabel != 'الكل' &&
                                _dateLabel != 'اليوم' &&
                                _dateLabel != 'أمس' &&
                                _dateLabel != 'آخر 7 أيام' &&
                                _dateLabel != 'آخر 30 يوم'
                            ? Colors.white
                            : AccountingTheme.textSecondary,
                      )),
                  backgroundColor: _dateLabel != 'الكل' &&
                          _dateLabel != 'اليوم' &&
                          _dateLabel != 'أمس' &&
                          _dateLabel != 'آخر 7 أيام' &&
                          _dateLabel != 'آخر 30 يوم'
                      ? AccountingTheme.neonBlue
                      : AccountingTheme.bgSecondary,
                  onPressed: _pickCustomDateRange,
                ),
              ],
            ),
          ),
          crossFadeState: _showDateFilter
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 250),
        ),
      ],
    );
  }

  Widget _buildDateChip(
      String label, String matchLabel, DateTime? from, DateTime? to) {
    final isSelected = _dateLabel == matchLabel;
    return FilterChip(
      label: Text(label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AccountingTheme.textSecondary,
          )),
      selected: isSelected,
      selectedColor: AccountingTheme.neonBlue,
      backgroundColor: AccountingTheme.bgSecondary,
      checkmarkColor: Colors.white,
      onSelected: (_) => _setDateFilter(matchLabel, from, to),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AccountingTheme.borderColor),
      ),
      child: Row(
        children: [
          Text('تصفية حسب النوع:',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w600,
                  color: AccountingTheme.textPrimary)),
          const SizedBox(width: 12),
          _buildFilterChip('الكل', null),
          const SizedBox(width: 8),
          _buildFilterChip('أجور', 0),
          const SizedBox(width: 8),
          _buildFilterChip('تسديد', 1),
          const SizedBox(width: 8),
          _buildFilterChip('خصم', 2),
          const SizedBox(width: 8),
          _buildFilterChip('تعديل', 3),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int? type) {
    final isSelected = _typeFilter == type;
    return FilterChip(
      label: Text(label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AccountingTheme.textSecondary,
          )),
      selected: isSelected,
      selectedColor: AccountingTheme.neonBlue,
      backgroundColor: AccountingTheme.bgSecondary,
      checkmarkColor: Colors.white,
      onSelected: (_) {
        setState(() {
          _typeFilter = type;
          _currentPage = 1;
        });
        _loadData();
      },
    );
  }

  Widget _buildTransactionsTable() {
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long,
                size: 64,
                color: AccountingTheme.textMuted.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('لا توجد معاملات',
                style: GoogleFonts.cairo(
                    fontSize: 16, color: AccountingTheme.textMuted)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: DataTable(
              headingRowColor:
                  WidgetStateProperty.all(AccountingTheme.bgSecondary),
              columnSpacing: 24,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 64,
              columns: [
                DataColumn(
                    label: Text('#',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('الوكيل',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('النوع',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('الفئة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('المبلغ',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('الرصيد بعدها',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('الوصف',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('رقم القيد',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
                DataColumn(
                    label: Text('التاريخ',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold))),
              ],
              rows: _transactions.asMap().entries.map((entry) {
                final idx = entry.key;
                final tx = entry.value as Map<String, dynamic>;
                final rowNum = (_currentPage - 1) * _pageSize + idx + 1;

                return DataRow(cells: [
                  DataCell(Text('$rowNum',
                      style: GoogleFonts.cairo(
                          fontSize: 12, color: AccountingTheme.textMuted))),
                  DataCell(
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx['agentName'] ?? '',
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          tx['agentCode'] ?? '',
                          style: GoogleFonts.cairo(
                              fontSize: 11, color: AccountingTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  DataCell(_buildTypeBadge(tx['type'] ?? '', tx['typeValue'])),
                  DataCell(Text(
                    _categoryLabel(tx['category'] ?? '', tx['categoryValue']),
                    style: GoogleFonts.cairo(fontSize: 12),
                  )),
                  DataCell(Text(
                    '${_formatNumber(tx['amount'])} د.ع',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: _typeColor(tx['typeValue']),
                    ),
                  )),
                  DataCell(Text(
                    '${_formatNumber(tx['balanceAfter'])} د.ع',
                    style: GoogleFonts.cairo(fontSize: 12),
                  )),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        tx['description'] ?? '',
                        style: GoogleFonts.cairo(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                  DataCell(Text(
                    tx['journalEntryNumber']?.toString() ?? '-',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: AccountingTheme.textMuted),
                  )),
                  DataCell(Text(
                    _formatDate(tx['createdAt']),
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: AccountingTheme.textMuted),
                  )),
                ]);
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTypeBadge(String type, dynamic typeValue) {
    final int tv = (typeValue is int) ? typeValue : 0;
    String label;
    Color color;
    IconData icon;

    switch (tv) {
      case 0:
        label = 'أجور';
        color = AccountingTheme.danger;
        icon = Icons.arrow_downward;
        break;
      case 1:
        label = 'تسديد';
        color = AccountingTheme.success;
        icon = Icons.arrow_upward;
        break;
      case 2:
        label = 'خصم';
        color = const Color(0xFFE67E22);
        icon = Icons.remove_circle_outline;
        break;
      case 3:
        label = 'تعديل';
        color = AccountingTheme.neonBlue;
        icon = Icons.edit;
        break;
      default:
        label = type;
        color = AccountingTheme.textMuted;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.cairo(
                  fontSize: 11, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Color _typeColor(dynamic typeValue) {
    final int tv = (typeValue is int) ? typeValue : 0;
    switch (tv) {
      case 0:
        return AccountingTheme.danger;
      case 1:
        return AccountingTheme.success;
      case 2:
        return const Color(0xFFE67E22);
      case 3:
        return AccountingTheme.neonBlue;
      default:
        return AccountingTheme.textPrimary;
    }
  }

  String _categoryLabel(String category, dynamic categoryValue) {
    final int cv = (categoryValue is int) ? categoryValue : 99;
    switch (cv) {
      case 0:
        return 'اشتراك جديد';
      case 1:
        return 'تجديد اشتراك';
      case 2:
        return 'صيانة';
      case 3:
        return 'تحصيل فواتير';
      case 4:
        return 'تركيب';
      case 5:
        return 'نقل خدمة';
      case 6:
        return 'تسديد نقدي';
      case 7:
        return 'تحويل بنكي';
      case 99:
        return 'أخرى';
      default:
        return category;
    }
  }

  Widget _buildPagination() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
            tooltip: 'الصفحة السابقة',
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AccountingTheme.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AccountingTheme.borderColor),
            ),
            child: Text(
              'صفحة $_currentPage من $_totalPages  (${_formatNumber(_total)} معاملة)',
              style: GoogleFonts.cairo(
                  fontSize: 13, color: AccountingTheme.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
            tooltip: 'الصفحة التالية',
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic value) {
    if (value == null) return '-';
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}'
          '  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value.toString();
    }
  }

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final n = (value is num)
        ? value.toDouble()
        : (double.tryParse(value.toString()) ?? 0);
    if (n == n.truncateToDouble()) {
      return n.toInt().toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
    }
    return n.toStringAsFixed(1);
  }
}
