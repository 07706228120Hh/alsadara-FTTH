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
  final String? initialEntryId;

  const JournalEntriesPage({super.key, this.companyId, this.initialEntryId});

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

  // ── تحديد متعدد ──
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  // ── تصفية متقدمة ──
  String _searchQuery = '';
  String _refTypeFilter = 'all'; // all, Manual, CashTransaction, Salary, TechnicianCollection, Expense
  DateTime? _dateFrom;
  DateTime? _dateTo;
  double? _amountMin;
  double? _amountMax;
  String _sortBy = 'date_desc'; // date_desc, date_asc, amount_desc, amount_asc
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// القيود بعد تطبيق الفلاتر المحلية (بحث نصي + نوع مرجع + مبلغ + ترتيب)
  /// التاريخ والحالة يتم تصفيتها من السيرفر مباشرة
  List<dynamic> get _filteredEntries {
    var list = List<dynamic>.from(_entries);

    // بحث نصي (محلي — السيرفر لا يدعم بحث نصي)
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) {
        final desc = (e['Description'] ?? '').toString().toLowerCase();
        final num = (e['EntryNumber'] ?? '').toString().toLowerCase();
        final notes = (e['Notes'] ?? '').toString().toLowerCase();
        return desc.contains(q) || num.contains(q) || notes.contains(q);
      }).toList();
    }

    // نوع المرجع (محلي — السيرفر لا يدعم فلتر نوع المرجع)
    if (_refTypeFilter != 'all') {
      list = list.where((e) => e['ReferenceType']?.toString() == _refTypeFilter).toList();
    }

    // نطاق المبلغ (محلي — السيرفر لا يدعم فلتر المبلغ)
    if (_amountMin != null || _amountMax != null) {
      list = list.where((e) {
        final lines = (e['Lines'] as List?) ?? [];
        final total = lines.fold<double>(0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble());
        if (_amountMin != null && total < _amountMin!) return false;
        if (_amountMax != null && total > _amountMax!) return false;
        return true;
      }).toList();
    }

    // الترتيب (محلي)
    list.sort((a, b) {
      switch (_sortBy) {
        case 'date_asc':
          return (a['EntryDate'] ?? a['CreatedAt'] ?? '').toString()
              .compareTo((b['EntryDate'] ?? b['CreatedAt'] ?? '').toString());
        case 'amount_desc':
          final aAmt = ((a['Lines'] as List?) ?? []).fold<double>(0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble());
          final bAmt = ((b['Lines'] as List?) ?? []).fold<double>(0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble());
          return bAmt.compareTo(aAmt);
        case 'amount_asc':
          final aAmt = ((a['Lines'] as List?) ?? []).fold<double>(0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble());
          final bAmt = ((b['Lines'] as List?) ?? []).fold<double>(0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble());
          return aAmt.compareTo(bAmt);
        default: // date_desc
          return (b['EntryDate'] ?? b['CreatedAt'] ?? '').toString()
              .compareTo((a['EntryDate'] ?? a['CreatedAt'] ?? '').toString());
      }
    });

    return list;
  }

  /// عدد الفلاتر المتقدمة النشطة (التاريخ يحسب فقط إذا حدده المستخدم يدوياً)
  int get _activeFilterCount {
    int count = 0;
    if (_searchQuery.isNotEmpty) count++;
    if (_refTypeFilter != 'all') count++;
    if (_dateFrom != null || _dateTo != null) count++; // تاريخ مخصص
    if (_amountMin != null || _amountMax != null) count++;
    if (_sortBy != 'date_desc') count++;
    return count;
  }

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
      // ── حساب fromDate / toDate ──
      // افتراضي: اليوم + الأمس | إذا حدد المستخدم تاريخ في الفلتر المتقدم يستخدمه
      // toDate يُرسل كنهاية اليوم (23:59:59) حتى يشمل كل قيود ذلك اليوم
      String? fromDate;
      String? toDate;
      if (_dateFrom != null || _dateTo != null) {
        // فلتر متقدم (نضيف 3 ساعات لتعويض طرح السيرفر)
        if (_dateFrom != null) {
          fromDate = _fmtDate(_dateFrom!.add(const Duration(hours: 3)));
        }
        if (_dateTo != null) {
          toDate = _fmtDate(_dateTo!.add(const Duration(days: 1, hours: 3)));
        }
      } else {
        // افتراضي: اليوم فقط (نضيف 3 ساعات لتعويض طرح السيرفر)
        final now = DateTime.now();
        fromDate = _fmtDate(DateTime(now.year, now.month, now.day).add(const Duration(hours: 3)));
        toDate = _fmtDate(DateTime(now.year, now.month, now.day).add(const Duration(days: 1, hours: 3)));
      }

      final result = await AccountingService.instance
          .getJournalEntries(
        companyId: widget.companyId,
        status: _statusFilter != 'all' ? _statusFilter : null,
        fromDate: fromDate,
        toDate: toDate,
        page: page,
        pageSize: 10000, // جلب كل سجلات الفترة — التاريخ يحدّ البيانات طبيعياً
      );
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
          _currentPage = (result['page'] ?? page) as int;
          final totalFromServer = (result['total'] ?? all.length) as int;
          _total = totalFromServer;
          _totalPages = (_total / _pageSize).ceil().clamp(1, 99999);
        }
        _entries = all;
      } else {
        _errorMessage = result['message'] ?? 'خطأ';
      }
    } catch (e) {
      _errorMessage = 'خطأ: $e';
    }
    setState(() {
      _isLoading = false;
    });

    // فتح قيد محدد تلقائياً (من كشف الحسابات)
    if (widget.initialEntryId != null && _entries.isNotEmpty) {
      final match = _entries.where((e) => e['Id']?.toString() == widget.initialEntryId).firstOrNull;
      if (match != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showFullEditDialog(Map<String, dynamic>.from(match));
        });
      } else {
        // القيد ليس في الفترة الحالية — جلبه مباشرة
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final res = await AccountingService.instance.getJournalEntry(widget.initialEntryId!);
          if (res['success'] == true && mounted) {
            _showFullEditDialog(Map<String, dynamic>.from(res['data']));
          }
        });
      }
    }
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
            child: Text('$_total',
                style: GoogleFonts.cairo(
                  fontSize: isMobile ? 10 : context.accR.small,
                  fontWeight: FontWeight.bold,
                  color: AccountingTheme.neonPink,
                )),
          ),
          SizedBox(width: isMobile ? 4 : 0),
          if (!isMobile) const Spacer(),
          // ── أزرار العمليات الجماعية ──
          if (_isSelectionMode && _selectedIds.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AccountingTheme.neonPink.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('محدد: ${_selectedIds.length}',
                  style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AccountingTheme.neonPink)),
            ),
            const SizedBox(width: 4),
            _bulkBtn(
              icon: Icons.select_all,
              label: 'تحديد الكل',
              color: AccountingTheme.neonBlue,
              onTap: () {
                setState(() {
                  final filtered = _filteredEntries;
                  for (final e in filtered) {
                    final id = e['Id']?.toString() ?? '';
                    if (id.isNotEmpty) _selectedIds.add(id);
                  }
                });
              },
            ),
            if (PermissionManager.instance.canEdit('accounting.journals')) ...[
              _bulkBtn(
                icon: Icons.check_circle,
                label: 'ترحيل',
                color: AccountingTheme.success,
                onTap: _bulkPost,
              ),
              _bulkBtn(
                icon: Icons.cancel,
                label: 'إلغاء',
                color: AccountingTheme.warning,
                onTap: _bulkVoid,
              ),
            ],
            if (VpsAuthService.instance.currentUser?.isAdmin == true)
              _bulkBtn(
                icon: Icons.delete_outline,
                label: 'حذف',
                color: AccountingTheme.danger,
                onTap: _bulkDelete,
              ),
            const SizedBox(width: 4),
          ],
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
    final isMobile = context.accR.isMobile;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : context.accR.spaceXL, vertical: context.accR.spaceS),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Column(
        children: [
          // السطر الأول: فلاتر نوع العملية + عداد
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _refChip('all', 'الكل', Icons.select_all, AccountingTheme.neonBlue),
                      _refChip('FtthSubscription', 'تجديدات', Icons.wifi, const Color(0xFF2196F3)),
                      _refChip('TechnicianCollection', 'قبض', Icons.arrow_downward, AccountingTheme.success),
                      _refChip('Expense', 'صرف', Icons.arrow_upward, AccountingTheme.danger),
                      _refChip('Salary', 'رواتب', Icons.payments, const Color(0xFFE91E63)),
                      _refChip('CashDeposit', 'إيداع', Icons.add_circle_outline, const Color(0xFF4CAF50)),
                      _refChip('CashWithdrawal', 'سحب', Icons.remove_circle_outline, const Color(0xFFFF9800)),
                      _refChip('OperatorCashDelivery', 'تسليم كاش', Icons.local_shipping, const Color(0xFF009688)),
                      _refChip('OperatorCreditCollection', 'تحصيل ذمم', Icons.receipt_long, const Color(0xFF673AB7)),
                      _refChip('Manual', 'يدوي', Icons.edit_note, AccountingTheme.textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${_filteredEntries.length} من $_total',
                  style: GoogleFonts.cairo(
                      color: AccountingTheme.textMuted,
                      fontSize: context.accR.small)),
              if (_dateFrom == null && _dateTo == null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AccountingTheme.info.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('اليوم',
                      style: GoogleFonts.cairo(
                          color: AccountingTheme.info,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
          SizedBox(height: context.accR.spaceS),
          // مجموع المبالغ
          Builder(builder: (_) {
            final entries = _filteredEntries;
            double totalDebit = 0;
            for (final e in entries) {
              final lines = (e['Lines'] as List?) ?? [];
              for (final l in lines) {
                totalDebit += ((l['DebitAmount'] ?? 0) as num).toDouble();
              }
            }
            if (entries.isEmpty) return const SizedBox.shrink();
            final fmt = totalDebit.round().toString().replaceAllMapped(
                RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AccountingTheme.neonBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AccountingTheme.neonBlue.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.summarize, size: 16, color: AccountingTheme.neonBlue),
                  const SizedBox(width: 6),
                  Text('مجموع ${entries.length} قيد:',
                      style: GoogleFonts.cairo(
                          fontSize: 12, color: AccountingTheme.textSecondary)),
                  const SizedBox(width: 8),
                  Text('$fmt د.ع',
                      style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AccountingTheme.neonBlue)),
                ],
              ),
            );
          }),
          SizedBox(height: context.accR.spaceS),
          // السطر الثالث: بحث + تصفية متقدمة + تحديد
          Row(
            children: [
              // حقل البحث
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textPrimary, fontSize: 13),
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'بحث بالوصف أو رقم القيد...',
                      hintStyle: TextStyle(
                          color: AccountingTheme.textMuted, fontSize: 12),
                      prefixIcon: Icon(Icons.search,
                          size: 18, color: AccountingTheme.textMuted),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  size: 16, color: AccountingTheme.textMuted),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AccountingTheme.bgCardHover,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              SizedBox(width: context.accR.spaceS),
              // زر التصفية المتقدمة
              Stack(
                children: [
                  InkWell(
                    onTap: _showAdvancedFilterDialog,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _activeFilterCount > 0
                            ? AccountingTheme.neonBlue.withOpacity(0.15)
                            : AccountingTheme.bgCardHover,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: _activeFilterCount > 0
                                ? AccountingTheme.neonBlue.withOpacity(0.5)
                                : AccountingTheme.borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tune,
                              size: 16,
                              color: _activeFilterCount > 0
                                  ? AccountingTheme.neonBlue
                                  : AccountingTheme.textMuted),
                          if (!isMobile) ...[
                            const SizedBox(width: 4),
                            Text('تصفية',
                                style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: _activeFilterCount > 0
                                        ? AccountingTheme.neonBlue
                                        : AccountingTheme.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_activeFilterCount > 0)
                    Positioned(
                      top: -2,
                      left: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AccountingTheme.neonPink,
                          shape: BoxShape.circle,
                        ),
                        child: Text('$_activeFilterCount',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
              SizedBox(width: context.accR.spaceS),
              // زر وضع التحديد
              InkWell(
                onTap: () {
                  setState(() {
                    _isSelectionMode = !_isSelectionMode;
                    if (!_isSelectionMode) _selectedIds.clear();
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: _isSelectionMode
                        ? AccountingTheme.neonPink.withOpacity(0.15)
                        : AccountingTheme.bgCardHover,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _isSelectionMode
                            ? AccountingTheme.neonPink.withOpacity(0.5)
                            : AccountingTheme.borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          _isSelectionMode
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 16,
                          color: _isSelectionMode
                              ? AccountingTheme.neonPink
                              : AccountingTheme.textMuted),
                      if (!isMobile) ...[
                        const SizedBox(width: 4),
                        Text('تحديد',
                            style: GoogleFonts.cairo(
                                fontSize: 12,
                                color: _isSelectionMode
                                    ? AccountingTheme.neonPink
                                    : AccountingTheme.textSecondary)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final filtered = _filteredEntries;
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book,
                color: AccountingTheme.textMuted.withOpacity(0.3),
                size: context.accR.iconXL),
            SizedBox(height: context.accR.spaceM),
            Text(_entries.isEmpty ? 'لا توجد قيود' : 'لا توجد نتائج مطابقة',
                style: GoogleFonts.cairo(
                    color: AccountingTheme.textMuted,
                    fontSize: context.accR.headingSmall)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(context.accR.spaceXL),
      itemCount: filtered.length,
      itemBuilder: (_, i) {
        final entry = filtered[i];
        final status = entry['Status']?.toString() ?? 'Draft';
        final statusInfo = _statusInfo(status);
        final lines = (entry['Lines'] as List?) ?? [];
        final totalDebit = lines.isNotEmpty
            ? lines.fold<double>(0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble())
            : ((entry['TotalDebit'] ?? 0) as num).toDouble();

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
                if (_isSelectionMode) ...[
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: Checkbox(
                      value: _selectedIds.contains(entry['Id']?.toString()),
                      activeColor: AccountingTheme.neonPink,
                      side: BorderSide(color: AccountingTheme.textMuted),
                      onChanged: (v) {
                        setState(() {
                          final id = entry['Id']?.toString() ?? '';
                          if (v == true) {
                            _selectedIds.add(id);
                          } else {
                            _selectedIds.remove(id);
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
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
                  // زر عرض/تعديل التفاصيل — متاح للمسودة والمرحّل
                  if (status != 'Voided' && PermissionManager.instance.canEdit('accounting.journals'))
                    TextButton.icon(
                      onPressed: () => _showFullEditDialog(entry),
                      icon: Icon(Icons.edit_note, size: context.accR.iconXS),
                      label: Text('تفاصيل وتعديل',
                          style: TextStyle(fontSize: context.accR.small)),
                      style: TextButton.styleFrom(
                          foregroundColor: AccountingTheme.info),
                    ),
                  if (status == 'Voided')
                    TextButton.icon(
                      onPressed: () => _showFullEditDialog(entry, readOnly: true),
                      icon: Icon(Icons.visibility, size: context.accR.iconXS),
                      label: Text('عرض التفاصيل',
                          style: TextStyle(fontSize: context.accR.small)),
                      style: TextButton.styleFrom(
                          foregroundColor: AccountingTheme.textMuted),
                    ),
                  if (status == 'Draft') ...[
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
                  if (VpsAuthService.instance.currentUser?.isAdmin == true) ...[
                    SizedBox(width: context.accR.spaceS),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(top: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_totalPages > 1) ...[
            IconButton(
              onPressed: _currentPage > 1 ? () => _loadData(page: _currentPage - 1) : null,
              icon: const Icon(Icons.chevron_right),
              color: AccountingTheme.textSecondary,
              disabledColor: AccountingTheme.textMuted.withOpacity(0.3),
            ),
          ],
          Text(
            'صفحة $_currentPage من $_totalPages',
            style: GoogleFonts.cairo(color: AccountingTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AccountingTheme.neonBlue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'إجمالي: $_total سجل',
              style: GoogleFonts.cairo(
                  color: AccountingTheme.neonBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
          if (_totalPages > 1) ...[
            IconButton(
              onPressed: _currentPage < _totalPages ? () => _loadData(page: _currentPage + 1) : null,
              icon: const Icon(Icons.chevron_left),
              color: AccountingTheme.textSecondary,
              disabledColor: AccountingTheme.textMuted.withOpacity(0.3),
            ),
          ],
        ],
      ),
    );
  }

  void _showAdvancedFilterDialog() {
    // نسخ مؤقتة من القيم الحالية
    var tmpRefType = _refTypeFilter;
    var tmpDateFrom = _dateFrom;
    var tmpDateTo = _dateTo;
    var tmpAmountMin = _amountMin;
    var tmpAmountMax = _amountMax;
    var tmpSortBy = _sortBy;
    final amtMinCtrl = TextEditingController(
        text: _amountMin != null ? _amountMin!.toStringAsFixed(0) : '');
    final amtMaxCtrl = TextEditingController(
        text: _amountMax != null ? _amountMax!.toStringAsFixed(0) : '');

    final refTypes = [
      {'value': 'all', 'label': 'الكل'},
      {'value': 'Manual', 'label': 'يدوي'},
      {'value': 'CashTransaction', 'label': 'حركة صندوق'},
      {'value': 'Salary', 'label': 'رواتب'},
      {'value': 'TechnicianCollection', 'label': 'تحصيل'},
      {'value': 'Expense', 'label': 'مصروف'},
    ];

    final sortOptions = [
      {'value': 'date_desc', 'label': 'الأحدث أولاً'},
      {'value': 'date_asc', 'label': 'الأقدم أولاً'},
      {'value': 'amount_desc', 'label': 'الأعلى مبلغاً'},
      {'value': 'amount_asc', 'label': 'الأقل مبلغاً'},
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, ss) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Row(
              children: [
                Icon(Icons.tune, color: AccountingTheme.neonBlue, size: 22),
                const SizedBox(width: 8),
                Text('تصفية متقدمة',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textPrimary,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: context.accR.isMobile ? double.maxFinite : 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── نوع المرجع ──
                    Text('نوع المرجع',
                        style: GoogleFonts.cairo(
                            color: AccountingTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: refTypes.map((r) {
                        final sel = tmpRefType == r['value'];
                        return ChoiceChip(
                          label: Text(r['label']!,
                              style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: sel
                                      ? Colors.white
                                      : AccountingTheme.textSecondary)),
                          selected: sel,
                          selectedColor: AccountingTheme.neonBlue,
                          backgroundColor: AccountingTheme.bgCardHover,
                          side: BorderSide(
                              color: sel
                                  ? AccountingTheme.neonBlue
                                  : AccountingTheme.borderColor),
                          onSelected: (_) =>
                              ss(() => tmpRefType = r['value']!),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    // ── نطاق التاريخ ──
                    Row(
                      children: [
                        Text('نطاق التاريخ',
                            style: GoogleFonts.cairo(
                                color: AccountingTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (tmpDateFrom == null && tmpDateTo == null)
                          Text('افتراضي: اليوم + أمس',
                              style: GoogleFonts.cairo(
                                  color: AccountingTheme.info,
                                  fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // أزرار سريعة للتاريخ
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _dateQuickChip('اليوم + أمس', null, null, tmpDateFrom, tmpDateTo, (from, to) {
                          ss(() { tmpDateFrom = from; tmpDateTo = to; });
                        }),
                        _dateQuickChip('آخر 7 أيام',
                          DateTime.now().subtract(const Duration(days: 7)),
                          DateTime.now(), tmpDateFrom, tmpDateTo, (from, to) {
                          ss(() { tmpDateFrom = from; tmpDateTo = to; });
                        }),
                        _dateQuickChip('هذا الشهر',
                          DateTime(DateTime.now().year, DateTime.now().month, 1),
                          DateTime.now(), tmpDateFrom, tmpDateTo, (from, to) {
                          ss(() { tmpDateFrom = from; tmpDateTo = to; });
                        }),
                        _dateQuickChip('الكل (بدون فلتر تاريخ)',
                          DateTime(2020), DateTime.now().add(const Duration(days: 1)),
                          tmpDateFrom, tmpDateTo, (from, to) {
                          ss(() { tmpDateFrom = from; tmpDateTo = to; });
                        }),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDateRangePicker(
                                context: ctx,
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                initialDateRange: (tmpDateFrom != null && tmpDateTo != null)
                                    ? DateTimeRange(start: tmpDateFrom!, end: tmpDateTo!)
                                    : null,
                                builder: (c, child) => Theme(
                                  data: ThemeData.dark().copyWith(
                                    colorScheme: ColorScheme.dark(
                                        primary: AccountingTheme.neonBlue)),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                ss(() {
                                  tmpDateFrom = picked.start;
                                  tmpDateTo = picked.end;
                                });
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: AccountingTheme.bgCardHover,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: (tmpDateFrom != null)
                                        ? AccountingTheme.neonBlue.withOpacity(0.5)
                                        : AccountingTheme.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.date_range,
                                      size: 16,
                                      color: tmpDateFrom != null
                                          ? AccountingTheme.neonBlue
                                          : AccountingTheme.textMuted),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      tmpDateFrom != null && tmpDateTo != null
                                          ? '${tmpDateFrom!.day}/${tmpDateFrom!.month}/${tmpDateFrom!.year} — ${tmpDateTo!.day}/${tmpDateTo!.month}/${tmpDateTo!.year}'
                                          : 'اختر نطاق التاريخ',
                                      style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          color: tmpDateFrom != null
                                              ? AccountingTheme.textPrimary
                                              : AccountingTheme.textMuted),
                                    ),
                                  ),
                                  if (tmpDateFrom != null)
                                    InkWell(
                                      onTap: () => ss(() {
                                        tmpDateFrom = null;
                                        tmpDateTo = null;
                                      }),
                                      child: Icon(Icons.clear,
                                          size: 16,
                                          color: AccountingTheme.textMuted),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── نطاق المبلغ ──
                    Text('نطاق المبلغ',
                        style: GoogleFonts.cairo(
                            color: AccountingTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amtMinCtrl,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.cairo(
                                color: AccountingTheme.textPrimary,
                                fontSize: 13),
                            onChanged: (v) =>
                                tmpAmountMin = double.tryParse(v),
                            decoration: InputDecoration(
                              hintText: 'من',
                              hintStyle: TextStyle(
                                  color: AccountingTheme.textMuted,
                                  fontSize: 12),
                              filled: true,
                              fillColor: AccountingTheme.bgCardHover,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text('—',
                              style: TextStyle(
                                  color: AccountingTheme.textMuted)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: amtMaxCtrl,
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.cairo(
                                color: AccountingTheme.textPrimary,
                                fontSize: 13),
                            onChanged: (v) =>
                                tmpAmountMax = double.tryParse(v),
                            decoration: InputDecoration(
                              hintText: 'إلى',
                              hintStyle: TextStyle(
                                  color: AccountingTheme.textMuted,
                                  fontSize: 12),
                              filled: true,
                              fillColor: AccountingTheme.bgCardHover,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // ── الترتيب ──
                    Text('الترتيب',
                        style: GoogleFonts.cairo(
                            color: AccountingTheme.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: sortOptions.map((s) {
                        final sel = tmpSortBy == s['value'];
                        return ChoiceChip(
                          label: Text(s['label']!,
                              style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: sel
                                      ? Colors.white
                                      : AccountingTheme.textSecondary)),
                          selected: sel,
                          selectedColor: AccountingTheme.accent,
                          backgroundColor: AccountingTheme.bgCardHover,
                          side: BorderSide(
                              color: sel
                                  ? AccountingTheme.accent
                                  : AccountingTheme.borderColor),
                          onSelected: (_) =>
                              ss(() => tmpSortBy = s['value']!),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // مسح جميع الفلاتر
                  ss(() {
                    tmpRefType = 'all';
                    tmpDateFrom = null;
                    tmpDateTo = null;
                    tmpAmountMin = null;
                    tmpAmountMax = null;
                    tmpSortBy = 'date_desc';
                    amtMinCtrl.clear();
                    amtMaxCtrl.clear();
                  });
                },
                child: Text('مسح الكل',
                    style: GoogleFonts.cairo(
                        color: AccountingTheme.textMuted, fontSize: 13)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.neonBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  final dateChanged = tmpDateFrom != _dateFrom || tmpDateTo != _dateTo;
                  setState(() {
                    _refTypeFilter = tmpRefType;
                    _dateFrom = tmpDateFrom;
                    _dateTo = tmpDateTo;
                    _amountMin = tmpAmountMin;
                    _amountMax = tmpAmountMax;
                    _sortBy = tmpSortBy;
                  });
                  // إذا تغير التاريخ → يجب إعادة جلب من السيرفر
                  if (dateChanged) _loadData();
                },
                child: Text('تطبيق',
                    style: GoogleFonts.cairo(fontSize: 13)),
              ),
            ],
          ),
        ),
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

  Widget _refChip(String value, String label, IconData icon, Color color) {
    final isSelected = _refTypeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: InkWell(
        onTap: () => setState(() => _refTypeFilter = value),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? color.withOpacity(0.5) : AccountingTheme.borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? color : AccountingTheme.textMuted),
              const SizedBox(width: 4),
              Text(label,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? color : AccountingTheme.textSecondary,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  String _refTypeLabel(dynamic refType) {
    switch (refType?.toString()) {
      case 'Manual':
        return 'يدوي';
      case 'CashTransaction':
        return 'حركة صندوق';
      case 'CashDeposit':
        return 'إيداع';
      case 'CashWithdrawal':
        return 'سحب';
      case 'Salary':
        return 'رواتب';
      case 'TechnicianCollection':
        return 'قبض';
      case 'Expense':
        return 'صرف';
      case 'FtthSubscription':
        return 'تجديد';
      case 'OperatorCashDelivery':
        return 'تسليم كاش';
      case 'OperatorCreditCollection':
        return 'تحصيل ذمم';
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

  /// عرض وتعديل تفاصيل القيد بشكل كامل
  void _showFullEditDialog(Map<String, dynamic> entry, {bool readOnly = false}) {
    final status = entry['Status']?.toString() ?? 'Draft';
    final isVoided = status == 'Voided';
    final effectiveReadOnly = readOnly || isVoided;

    final descCtrl = TextEditingController(text: entry['Description'] ?? '');
    final notesCtrl = TextEditingController(text: entry['Notes'] ?? '');
    DateTime entryDate = DateTime.tryParse(entry['EntryDate']?.toString() ?? '') ?? DateTime.now();

    // تحضير أسطر القيد
    final lines = <Map<String, dynamic>>[];
    for (final l in ((entry['Lines'] as List?) ?? [])) {
      lines.add({
        'accountId': l['AccountId']?.toString() ?? '',
        'accountName': l['AccountName']?.toString() ?? l['Account']?['Name']?.toString() ?? '',
        'debit': ((l['DebitAmount'] ?? 0) as num).toDouble(),
        'credit': ((l['CreditAmount'] ?? 0) as num).toDouble(),
        'description': l['Description']?.toString() ?? '',
        'debitCtrl': TextEditingController(text: ((l['DebitAmount'] ?? 0) as num).toDouble() > 0 ? ((l['DebitAmount'] ?? 0) as num).toStringAsFixed(0) : ''),
        'creditCtrl': TextEditingController(text: ((l['CreditAmount'] ?? 0) as num).toDouble() > 0 ? ((l['CreditAmount'] ?? 0) as num).toStringAsFixed(0) : ''),
        'descCtrl': TextEditingController(text: l['Description']?.toString() ?? ''),
      });
    }

    // قائمة الحسابات المتاحة
    List<Map<String, dynamic>> accounts = [];
    bool accountsLoaded = false;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) {
          // تحميل الحسابات عند أول فتح
          if (!accountsLoaded && !effectiveReadOnly) {
            accountsLoaded = true;
            AccountingService.instance.getAccounts(companyId: widget.companyId).then((res) {
              if (res['success'] == true) {
                final data = res['data'];
                final list = data is List ? data : (data is Map ? (data['items'] ?? []) as List : []);
                final leafAccounts = <Map<String, dynamic>>[];
                for (final a in list) {
                  if (a['IsLeaf'] == true || a['isLeaf'] == true) {
                    leafAccounts.add({
                      'id': (a['Id'] ?? a['id'])?.toString() ?? '',
                      'name': '${a['Code'] ?? a['code'] ?? ''} - ${a['Name'] ?? a['name'] ?? ''}',
                      'code': (a['Code'] ?? a['code'])?.toString() ?? '',
                    });
                  }
                }
                leafAccounts.sort((a, b) => a['code'].compareTo(b['code']));
                setDState(() => accounts = leafAccounts);
              }
            });
          }

          // حساب الإجماليات
          double totalDebit = 0, totalCredit = 0;
          for (final l in lines) {
            totalDebit += double.tryParse(l['debitCtrl'].text) ?? 0;
            totalCredit += double.tryParse(l['creditCtrl'].text) ?? 0;
          }
          final isBalanced = (totalDebit - totalCredit).abs() < 0.01;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: Dialog(
              backgroundColor: AccountingTheme.bgCard,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 750,
                  maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── العنوان ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: AccountingTheme.bgCardHover,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        border: const Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
                      ),
                      child: Row(
                        children: [
                          Icon(effectiveReadOnly ? Icons.visibility : Icons.edit_note,
                              color: AccountingTheme.info, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(effectiveReadOnly ? 'تفاصيل القيد' : 'تعديل القيد',
                                    style: GoogleFonts.cairo(
                                        color: AccountingTheme.textPrimary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                Text('#${entry['EntryNumber'] ?? ''}',
                                    style: GoogleFonts.cairo(
                                        color: AccountingTheme.neonBlue, fontSize: 12)),
                              ],
                            ),
                          ),
                          // حالة القيد
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: (status == 'Posted'
                                      ? AccountingTheme.success
                                      : status == 'Voided'
                                          ? AccountingTheme.danger
                                          : AccountingTheme.warning)
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status == 'Posted' ? 'مرحّل' : status == 'Voided' ? 'ملغي' : 'مسودة',
                              style: GoogleFonts.cairo(
                                color: status == 'Posted'
                                    ? AccountingTheme.success
                                    : status == 'Voided'
                                        ? AccountingTheme.danger
                                        : AccountingTheme.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, size: 20),
                            style: IconButton.styleFrom(foregroundColor: AccountingTheme.textMuted),
                          ),
                        ],
                      ),
                    ),

                    // ── المحتوى ──
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── معلومات عامة ──
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: _editField(
                                    label: 'الوصف',
                                    controller: descCtrl,
                                    readOnly: effectiveReadOnly,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: InkWell(
                                    onTap: effectiveReadOnly ? null : () async {
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: entryDate,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setDState(() => entryDate = picked);
                                      }
                                    },
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'التاريخ',
                                        labelStyle: const TextStyle(color: AccountingTheme.textMuted),
                                        filled: true,
                                        fillColor: AccountingTheme.bgCardHover,
                                        border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide.none),
                                        suffixIcon: Icon(Icons.calendar_today,
                                            size: 16, color: AccountingTheme.textMuted),
                                        isDense: true,
                                      ),
                                      child: Text(
                                        '${entryDate.year}/${entryDate.month.toString().padLeft(2, '0')}/${entryDate.day.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: AccountingTheme.textPrimary, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _editField(label: 'ملاحظات', controller: notesCtrl, readOnly: effectiveReadOnly, maxLines: 2),
                            const SizedBox(height: 8),
                            // معلومات إضافية
                            Wrap(
                              spacing: 16,
                              runSpacing: 4,
                              children: [
                                if (entry['ReferenceType'] != null)
                                  _infoChip('النوع', _refTypeLabel(entry['ReferenceType'])),
                                if (entry['ReferenceId'] != null)
                                  _infoChip('مرجع', entry['ReferenceId'].toString()),
                                if (entry['CreatedBy'] != null)
                                  _infoChip('أنشأه', (entry['CreatedBy']?['FullName'] ?? entry['CreatedBy']?['fullName'] ?? '').toString()),
                                if (entry['ApprovedBy'] != null)
                                  _infoChip('اعتمده', (entry['ApprovedBy']?['FullName'] ?? entry['ApprovedBy']?['fullName'] ?? '').toString()),
                              ],
                            ),

                            const SizedBox(height: 18),
                            const Divider(color: AccountingTheme.borderColor),
                            const SizedBox(height: 10),

                            // ── عنوان الأسطر ──
                            Row(
                              children: [
                                Text('أسطر القيد',
                                    style: GoogleFonts.cairo(
                                        color: AccountingTheme.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                const Spacer(),
                                if (!effectiveReadOnly)
                                  TextButton.icon(
                                    onPressed: () {
                                      setDState(() {
                                        lines.add({
                                          'accountId': '',
                                          'accountName': '',
                                          'debit': 0.0,
                                          'credit': 0.0,
                                          'description': '',
                                          'debitCtrl': TextEditingController(),
                                          'creditCtrl': TextEditingController(),
                                          'descCtrl': TextEditingController(),
                                        });
                                      });
                                    },
                                    icon: const Icon(Icons.add_circle_outline, size: 16),
                                    label: Text('إضافة سطر',
                                        style: GoogleFonts.cairo(fontSize: 12)),
                                    style: TextButton.styleFrom(
                                        foregroundColor: AccountingTheme.neonGreen),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // ── رأس الجدول ──
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: AccountingTheme.bgCardHover,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                border: Border.all(color: AccountingTheme.borderColor),
                              ),
                              child: Row(
                                children: [
                                  if (!effectiveReadOnly)
                                    const SizedBox(width: 32),
                                  Expanded(flex: 3, child: Text('الحساب',
                                      style: GoogleFonts.cairo(color: AccountingTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 100, child: Text('مدين',
                                      style: GoogleFonts.cairo(color: AccountingTheme.neonGreen, fontSize: 11, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center)),
                                  SizedBox(width: 100, child: Text('دائن',
                                      style: GoogleFonts.cairo(color: AccountingTheme.danger, fontSize: 11, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center)),
                                  Expanded(flex: 2, child: Text('البيان',
                                      style: GoogleFonts.cairo(color: AccountingTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold))),
                                ],
                              ),
                            ),

                            // ── أسطر القيد ──
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AccountingTheme.borderColor),
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                              ),
                              child: Column(
                                children: [
                                  for (int i = 0; i < lines.length; i++)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: i.isEven ? Colors.transparent : AccountingTheme.bgCardHover.withOpacity(0.3),
                                        border: i < lines.length - 1
                                            ? const Border(bottom: BorderSide(color: AccountingTheme.borderColor, width: 0.5))
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          // زر حذف السطر
                                          if (!effectiveReadOnly)
                                            SizedBox(
                                              width: 32,
                                              child: lines.length > 2
                                                  ? IconButton(
                                                      onPressed: () => setDState(() => lines.removeAt(i)),
                                                      icon: const Icon(Icons.remove_circle_outline, size: 16),
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      style: IconButton.styleFrom(foregroundColor: AccountingTheme.danger),
                                                    )
                                                  : null,
                                            ),
                                          // الحساب
                                          Expanded(
                                            flex: 3,
                                            child: effectiveReadOnly
                                                ? Text(
                                                    lines[i]['accountName'].toString().isNotEmpty
                                                        ? lines[i]['accountName']
                                                        : 'حساب #${lines[i]['accountId']}',
                                                    style: const TextStyle(color: AccountingTheme.textSecondary, fontSize: 12),
                                                  )
                                                : _accountDropdown(
                                                    accounts: accounts,
                                                    selectedId: lines[i]['accountId'],
                                                    onChanged: (id, name) {
                                                      setDState(() {
                                                        lines[i]['accountId'] = id;
                                                        lines[i]['accountName'] = name;
                                                      });
                                                    },
                                                  ),
                                          ),
                                          // مدين
                                          SizedBox(
                                            width: 100,
                                            child: effectiveReadOnly
                                                ? Text(
                                                    lines[i]['debit'] > 0 ? _fmt(lines[i]['debit']) : '-',
                                                    style: TextStyle(
                                                        color: lines[i]['debit'] > 0 ? AccountingTheme.neonGreen : AccountingTheme.textMuted,
                                                        fontSize: 12),
                                                    textAlign: TextAlign.center,
                                                  )
                                                : _amountField(
                                                    controller: lines[i]['debitCtrl'],
                                                    color: AccountingTheme.neonGreen,
                                                    onChanged: () => setDState(() {}),
                                                  ),
                                          ),
                                          // دائن
                                          SizedBox(
                                            width: 100,
                                            child: effectiveReadOnly
                                                ? Text(
                                                    lines[i]['credit'] > 0 ? _fmt(lines[i]['credit']) : '-',
                                                    style: TextStyle(
                                                        color: lines[i]['credit'] > 0 ? AccountingTheme.danger : AccountingTheme.textMuted,
                                                        fontSize: 12),
                                                    textAlign: TextAlign.center,
                                                  )
                                                : _amountField(
                                                    controller: lines[i]['creditCtrl'],
                                                    color: AccountingTheme.danger,
                                                    onChanged: () => setDState(() {}),
                                                  ),
                                          ),
                                          // البيان
                                          Expanded(
                                            flex: 2,
                                            child: effectiveReadOnly
                                                ? Text(lines[i]['description'] ?? '',
                                                    style: const TextStyle(color: AccountingTheme.textMuted, fontSize: 11))
                                                : TextField(
                                                    controller: lines[i]['descCtrl'],
                                                    style: const TextStyle(color: AccountingTheme.textPrimary, fontSize: 12),
                                                    decoration: InputDecoration(
                                                      hintText: 'بيان...',
                                                      hintStyle: TextStyle(color: AccountingTheme.textMuted.withOpacity(0.4), fontSize: 11),
                                                      filled: true,
                                                      fillColor: AccountingTheme.bgPrimary,
                                                      isDense: true,
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                      border: OutlineInputBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                          borderSide: BorderSide.none),
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),

                            // ── شريط المجاميع ──
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isBalanced
                                    ? AccountingTheme.success.withOpacity(0.1)
                                    : AccountingTheme.danger.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: isBalanced
                                        ? AccountingTheme.success.withOpacity(0.3)
                                        : AccountingTheme.danger.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isBalanced ? Icons.check_circle : Icons.warning,
                                    size: 16,
                                    color: isBalanced ? AccountingTheme.success : AccountingTheme.danger,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(isBalanced ? 'القيد متوازن' : 'القيد غير متوازن!',
                                      style: GoogleFonts.cairo(
                                          color: isBalanced ? AccountingTheme.success : AccountingTheme.danger,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  Text('مدين: ${_fmt(totalDebit)}',
                                      style: GoogleFonts.cairo(
                                          color: AccountingTheme.neonGreen,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 16),
                                  Text('دائن: ${_fmt(totalCredit)}',
                                      style: GoogleFonts.cairo(
                                          color: AccountingTheme.danger,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  if (!isBalanced) ...[
                                    const SizedBox(width: 16),
                                    Text('فرق: ${_fmt((totalDebit - totalCredit).abs())}',
                                        style: GoogleFonts.cairo(
                                            color: AccountingTheme.warning,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── أزرار الحفظ ──
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        color: AccountingTheme.bgCardHover,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                        border: Border(top: BorderSide(color: AccountingTheme.borderColor)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(effectiveReadOnly ? 'إغلاق' : 'إلغاء',
                                style: GoogleFonts.cairo(color: AccountingTheme.textMuted)),
                          ),
                          if (!effectiveReadOnly) ...[
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: isSaving || !isBalanced
                                  ? null
                                  : () async {
                                      // التحقق من وجود حسابات
                                      for (final l in lines) {
                                        if ((l['accountId'] as String).isEmpty) {
                                          _snack('يجب اختيار حساب لكل سطر', AccountingTheme.warning);
                                          return;
                                        }
                                      }
                                      setDState(() => isSaving = true);

                                      // فحص الفترة المحاسبية — نفحص التاريخ الجديد الذي اختاره المستخدم
                                      final allowed = await PeriodClosingService.checkAndWarnIfClosed(
                                        ctx, date: entryDate, companyId: widget.companyId ?? '',
                                      );
                                      if (!allowed) {
                                        setDState(() => isSaving = false);
                                        return;
                                      }

                                      // تجهيز البيانات
                                      final linesDtos = lines.map((l) => {
                                        'AccountId': l['accountId'],
                                        'DebitAmount': double.tryParse(l['debitCtrl'].text) ?? 0,
                                        'CreditAmount': double.tryParse(l['creditCtrl'].text) ?? 0,
                                        'Description': l['descCtrl'].text,
                                      }).toList();

                                      final result = await AccountingService.instance.updateJournalEntry(
                                        entry['Id'].toString(),
                                        {
                                          'Description': descCtrl.text,
                                          'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                                          'EntryDate': entryDate.toIso8601String(),
                                          'Lines': linesDtos,
                                        },
                                      );

                                      if (!ctx.mounted) return;
                                      setDState(() => isSaving = false);

                                      if (result['success'] == true) {
                                        Navigator.pop(ctx);
                                        _snack('تم تحديث القيد بنجاح', AccountingTheme.success);
                                        AuditTrailService.instance.log(
                                          action: AuditAction.edit,
                                          entityType: AuditEntityType.journalEntry,
                                          entityId: entry['Id']?.toString() ?? '',
                                          entityDescription: 'قيد: ${descCtrl.text}',
                                        );
                                        _loadData();
                                      } else {
                                        _snack(result['message'] ?? 'خطأ في تحديث القيد', AccountingTheme.danger);
                                      }
                                    },
                              icon: isSaving
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save, size: 18),
                              label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ التعديلات',
                                  style: GoogleFonts.cairo(fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AccountingTheme.info,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AccountingTheme.textMuted.withOpacity(0.3),
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
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

  Widget _editField({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      style: const TextStyle(color: AccountingTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AccountingTheme.textMuted, fontSize: 12),
        filled: true,
        fillColor: readOnly ? Colors.transparent : AccountingTheme.bgCardHover,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: readOnly ? BorderSide(color: AccountingTheme.borderColor) : BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: readOnly ? BorderSide(color: AccountingTheme.borderColor) : BorderSide.none),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: GoogleFonts.cairo(color: AccountingTheme.textMuted, fontSize: 11)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: AccountingTheme.neonBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(value,
              style: GoogleFonts.cairo(color: AccountingTheme.neonBlue, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _amountField({
    required TextEditingController controller,
    required Color color,
    required VoidCallback onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        hintText: '0',
        hintStyle: TextStyle(color: AccountingTheme.textMuted.withOpacity(0.3), fontSize: 11),
        filled: true,
        fillColor: AccountingTheme.bgPrimary,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _accountDropdown({
    required List<Map<String, dynamic>> accounts,
    required String selectedId,
    required void Function(String id, String name) onChanged,
  }) {
    if (accounts.isEmpty) {
      return const SizedBox(
        height: 30,
        child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return DropdownButtonFormField<String>(
      value: accounts.any((a) => a['id'] == selectedId) ? selectedId : null,
      isExpanded: true,
      isDense: true,
      dropdownColor: AccountingTheme.bgCard,
      style: const TextStyle(color: AccountingTheme.textPrimary, fontSize: 12),
      decoration: InputDecoration(
        filled: true,
        fillColor: AccountingTheme.bgPrimary,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
      ),
      hint: Text('اختر حساب...', style: TextStyle(color: AccountingTheme.textMuted.withOpacity(0.5), fontSize: 11)),
      items: accounts.map((a) => DropdownMenuItem<String>(
        value: a['id'],
        child: Text(a['name'], style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: (val) {
        if (val != null) {
          final acc = accounts.firstWhere((a) => a['id'] == val, orElse: () => {});
          onChanged(val, acc['name'] ?? '');
        }
      },
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

  // ==================== Date quick chip ====================

  Widget _dateQuickChip(
    String label,
    DateTime? from,
    DateTime? to,
    DateTime? currentFrom,
    DateTime? currentTo,
    void Function(DateTime? from, DateTime? to) onSelect,
  ) {
    // null/null يعني "افتراضي: اليوم + أمس"
    final isSelected = (from == null && to == null)
        ? (currentFrom == null && currentTo == null)
        : (currentFrom != null && currentTo != null &&
            currentFrom.year == from!.year && currentFrom.month == from.month && currentFrom.day == from.day &&
            currentTo.year == to!.year && currentTo.month == to.month && currentTo.day == to.day);
    return ChoiceChip(
      label: Text(label,
          style: GoogleFonts.cairo(
              fontSize: 11,
              color: isSelected ? Colors.white : AccountingTheme.textSecondary)),
      selected: isSelected,
      selectedColor: AccountingTheme.info,
      backgroundColor: AccountingTheme.bgCardHover,
      side: BorderSide(
          color: isSelected ? AccountingTheme.info : AccountingTheme.borderColor),
      onSelected: (_) => onSelect(from, to),
      visualDensity: VisualDensity.compact,
    );
  }

  // ==================== Bulk helpers ====================

  Widget _bulkBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _bulkPost() async {
    // فقط المسودات يمكن ترحيلها
    final drafts = _selectedIds.where((id) {
      final e = _entries.firstWhere(
          (e) => e['Id']?.toString() == id,
          orElse: () => null);
      return e != null && e['Status'] == 'Draft';
    }).toList();

    if (drafts.isEmpty) {
      _snack('لا توجد مسودات محددة للترحيل', AccountingTheme.warning);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('ترحيل ${drafts.length} قيد',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: Text(
              'هل تريد ترحيل ${drafts.length} قيد مسودة؟ لا يمكن التعديل بعد الترحيل.',
              style: const TextStyle(color: AccountingTheme.textSecondary)),
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

    int ok = 0, fail = 0;
    for (final id in drafts) {
      final r = await AccountingService.instance.postJournalEntry(id,
          approvedById: VpsAuthService.instance.currentUser?.id);
      if (r['success'] == true) {
        ok++;
      } else {
        fail++;
      }
    }
    _snack('تم ترحيل $ok قيد${fail > 0 ? ' (فشل: $fail)' : ''}',
        fail > 0 ? AccountingTheme.warning : AccountingTheme.success);
    _selectedIds.clear();
    _loadData();
  }

  Future<void> _bulkVoid() async {
    // فقط المرحلة يمكن إلغاؤها
    final posted = _selectedIds.where((id) {
      final e = _entries.firstWhere(
          (e) => e['Id']?.toString() == id,
          orElse: () => null);
      return e != null && e['Status'] == 'Posted';
    }).toList();

    if (posted.isEmpty) {
      _snack('لا توجد قيود مرحلة محددة للإلغاء', AccountingTheme.warning);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('إلغاء ${posted.length} قيد',
              style: TextStyle(color: AccountingTheme.textPrimary)),
          content: Text(
              'هل تريد إلغاء ${posted.length} قيد مرحل؟ سيتم عكس الأرصدة.',
              style: const TextStyle(color: AccountingTheme.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('رجوع',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إلغاء القيود'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;

    int ok = 0, fail = 0;
    for (final id in posted) {
      final r = await AccountingService.instance.voidJournalEntry(id);
      if (r['success'] == true) {
        ok++;
      } else {
        fail++;
      }
    }
    _snack('تم إلغاء $ok قيد${fail > 0 ? ' (فشل: $fail)' : ''}',
        fail > 0 ? AccountingTheme.warning : AccountingTheme.success);
    _selectedIds.clear();
    _loadData();
  }

  Future<void> _bulkDelete() async {
    // مدير الشركة فقط يمكنه الحذف (بأي حالة)
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AccountingTheme.bgCard,
          title: Text('حذف ${ids.length} قيد',
              style: TextStyle(color: AccountingTheme.danger)),
          content: Text(
              'هل تريد حذف ${ids.length} قيد؟ لا يمكن التراجع عن هذا الإجراء.',
              style: const TextStyle(color: AccountingTheme.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: TextStyle(color: AccountingTheme.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AccountingTheme.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    // عرض مؤشر تقدم الحذف
    int ok = 0, fail = 0;
    final total = ids.length;
    final progressNotifier = ValueNotifier<int>(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: AccountingTheme.bgCard,
            title: Text('جاري الحذف...', style: TextStyle(color: AccountingTheme.danger)),
            content: ValueListenableBuilder<int>(
              valueListenable: progressNotifier,
              builder: (_, done, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: done / total,
                    backgroundColor: AccountingTheme.bgCard,
                    valueColor: AlwaysStoppedAnimation(AccountingTheme.danger),
                  ),
                  const SizedBox(height: 12),
                  Text('$done / $total',
                      style: const TextStyle(color: AccountingTheme.textPrimary, fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // حذف بدفعات متوازية (10 طلبات في نفس الوقت)
    const batchSize = 10;
    for (int i = 0; i < ids.length; i += batchSize) {
      final batch = ids.skip(i).take(batchSize).toList();
      final results = await Future.wait(
        batch.map((id) => AccountingService.instance.deleteJournalEntry(id)),
      );
      for (final r in results) {
        if (r['success'] == true) {
          ok++;
        } else {
          fail++;
        }
      }
      progressNotifier.value = ok + fail;
    }

    progressNotifier.dispose();
    if (mounted) Navigator.of(context).pop(); // إغلاق مؤشر التقدم

    if (mounted) {
      _snack('تم حذف $ok قيد${fail > 0 ? ' (فشل: $fail)' : ''}',
          fail > 0 ? AccountingTheme.warning : AccountingTheme.success);
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      _loadData();
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  /// yyyy-MM-dd فقط — صيغة آمنة للسيرفر
  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
