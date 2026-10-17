import 'package:flutter/material.dart';
import '../../services/accounting_service.dart';
import '../../services/vps_auth_service.dart';
import '../../services/period_closing_service.dart';
import '../../services/audit_trail_service.dart';
import '../../theme/accounting_responsive.dart';
import '../../widgets/accounting_skeleton.dart';
import '../../permissions/permissions.dart';
import '../../frontend/frontend.dart';

/// صفحة القيود المحاسبية
class JournalEntriesPage extends StatefulWidget {
  final String? companyId;
  final String? initialEntryId;

  const JournalEntriesPage({super.key, this.companyId, this.initialEntryId});

  @override
  State<JournalEntriesPage> createState() => _JournalEntriesPageState();
}

class _JournalEntriesPageState extends State<JournalEntriesPage> {
  bool _isLoading = false;
  String? _errorMessage;
  List<dynamic> _entries = [];
  String _statusFilter = 'all'; // all, Draft, Posted, Voided
  int _currentPage = 1;
  int _totalPages = 1;
  int _total = 0;
  static const int _pageSize = 50;

  // ── هل تم البحث/التحميل ──
  bool _hasSearched = false;

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

    // بحث نصي شامل (محلي — السيرفر لا يدعم بحث نصي)
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((e) {
        final desc = (e['Description'] ?? '').toString().toLowerCase();
        final entryNum = (e['EntryNumber'] ?? '').toString().toLowerCase();
        final notes = (e['Notes'] ?? '').toString().toLowerCase();
        final refType = _refTypeLabel(e['ReferenceType']).toLowerCase();
        // بحث في أسماء الحسابات والمبالغ
        final lines = (e['Lines'] as List?) ?? [];
        final accountNames = lines.map((l) =>
            (l['AccountName'] ?? l['Account']?['Name'] ?? '').toString().toLowerCase()).join(' ');
        final totalDebit = lines.fold<double>(0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble());
        final totalStr = _fmt(totalDebit).toLowerCase();
        return desc.contains(q) || entryNum.contains(q) || notes.contains(q) ||
            refType.contains(q) || accountNames.contains(q) ||
            totalStr.contains(q);
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
    if (widget.initialEntryId != null) {
      _hasSearched = true;
    }
    // تحميل قيود اليوم بشكل صامت (بدون عرض حتى يبحث المستخدم)
    _loadData();
  }

  Future<void> _loadData({int page = 1, bool showResults = false}) async {
    if (showResults) _hasSearched = true;
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
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      maxWidth: double.infinity,
      appBar: SdAppBar(
        title: 'القيود المحاسبية',
        actions: [
          // ── أزرار العمليات الجماعية ──
          if (_isSelectionMode && _selectedIds.isNotEmpty) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: SdColors.platformLight.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('محدد: ${_selectedIds.length}',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: SdColors.platformLight)),
              ),
            ),
            const SizedBox(width: 4),
            _bulkBtn(
              icon: Icons.select_all,
              label: 'تحديد الكل',
              color: SdColors.primary,
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
                color: SdColors.success,
                onTap: _bulkPost,
              ),
              _bulkBtn(
                icon: Icons.cancel,
                label: 'إلغاء',
                color: SdColors.warning,
                onTap: _bulkVoid,
              ),
            ],
            if (VpsAuthService.instance.currentUser?.isAdmin == true)
              _bulkBtn(
                icon: Icons.delete_outline,
                label: 'حذف',
                color: SdColors.danger,
                onTap: _bulkDelete,
              ),
            const SizedBox(width: 4),
          ],
          if (_hasSearched)
            SdAppBarAction(
              icon: Icons.home_rounded,
              label: 'الشاشة الرئيسية',
              onPressed: () {
                setState(() {
                  _hasSearched = false;
                  _searchQuery = '';
                  _searchCtrl.clear();
                  _refTypeFilter = 'all';
                  _dateFrom = null;
                  _dateTo = null;
                  _amountMin = null;
                  _amountMax = null;
                  _selectedIds.clear();
                  _isSelectionMode = false;
                });
                // إعادة تحميل قيود اليوم بشكل صامت
                _loadData();
              },
            ),
          SdAppBarAction(
            icon: Icons.refresh,
            label: 'تحديث',
            onPressed: () => _loadData(showResults: _hasSearched),
          ),
          if (PermissionManager.instance.canAdd('accounting.journals'))
            SdAppBarAction(
              icon: Icons.add,
              label: 'إنشاء قيد',
              onPressed: _showCreateDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchHeader(),
          Expanded(
            child: !_hasSearched
                ? _buildEmptyHint()
                : _isLoading
                    ? const AccountingSkeleton(rows: 8, columns: 4)
                    : _errorMessage != null
                        ? Center(
                            child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  color: SdColors.faint
                                      .withOpacity(0.3),
                                  size: context.accR.iconXL),
                              SizedBox(height: context.accR.spaceM),
                              Text(_errorMessage!,
                                  style: TextStyle(
                                      fontFamily: 'Cairo',
                                      color: SdColors.muted,
                                      fontSize: context.accR.body)),
                            ],
                          ))
                        : _buildList(),
          ),
          if (_hasSearched) _buildPaginationBar(),
        ],
      ),
    );
  }

  /// رسالة عندما لم يبحث المستخدم بعد
  Widget _buildEmptyHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded,
              color: SdColors.faint.withOpacity(0.15), size: 56),
          const SizedBox(height: 12),
          Text('ابدأ بالكتابة في حقل البحث أو اختر فترة زمنية',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14, color: SdColors.faint)),
        ],
      ),
    );
  }

  /// شريط البحث والأزرار السريعة (دائماً في الأعلى)
  Widget _buildSearchHeader() {
    final isMobile = context.accR.isMobile;
    final filtered = _hasSearched ? _filteredEntries : <dynamic>[];
    final hasActiveFilter = _refTypeFilter != 'all' || _dateFrom != null ||
        _dateTo != null || _searchQuery.isNotEmpty;

    // حساب المجموع
    double totalDebit = 0;
    for (final e in filtered) {
      final lines = (e['Lines'] as List?) ?? [];
      for (final l in lines) {
        totalDebit += ((l['DebitAmount'] ?? 0) as num).toDouble();
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 10 : context.accR.spaceXL, vertical: 8),
      decoration: BoxDecoration(
        color: SdColors.surface,
        border: Border(bottom: BorderSide(color: SdColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // السطر الأول: بحث + تحديد
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        color: SdColors.ink, fontSize: 14),
                    onChanged: (v) {
                      setState(() {
                        _searchQuery = v;
                        if (v.isNotEmpty) _hasSearched = true;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'بحث برقم القيد، الوصف، اسم الحساب، المبلغ...',
                      hintStyle: TextStyle(
                          color: SdColors.faint, fontSize: 13),
                      prefixIcon: Icon(Icons.search,
                          size: 20, color: SdColors.primary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  size: 16, color: SdColors.faint),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: SdColors.surfaceAlt,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: SdColors.primary.withOpacity(0.5))),
                    ),
                  ),
                ),
              ),
              if (_hasSearched) ...[
                const SizedBox(width: 8),
                // زر تحديد
                InkWell(
                  onTap: () {
                    setState(() {
                      _isSelectionMode = !_isSelectionMode;
                      if (!_isSelectionMode) _selectedIds.clear();
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _isSelectionMode
                          ? SdColors.platformLight.withOpacity(0.15)
                          : SdColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _isSelectionMode
                              ? SdColors.platformLight.withOpacity(0.5)
                              : SdColors.divider),
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
                                ? SdColors.platformLight
                                : SdColors.faint),
                        if (!isMobile) ...[
                          const SizedBox(width: 4),
                          Text('تحديد',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: _isSelectionMode
                                      ? SdColors.platformLight
                                      : SdColors.muted)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // السطر الثاني: أزرار الفترات + أنواع العمليات + الكل + إلغاء
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _quickPeriodBtn(
                        label: 'الكل',
                        icon: Icons.select_all,
                        color: SdColors.primary,
                        isActive: _refTypeFilter == 'all' && _dateFrom != null &&
                            _dateFrom!.year == 2020,
                        onTap: () {
                          _refTypeFilter = 'all';
                          _dateFrom = DateTime(2020);
                          _dateTo = DateTime.now().add(const Duration(days: 1));
                          _loadData(showResults: true);
                        },
                      ),
                      const SizedBox(width: 6),
                      _quickPeriodBtn(
                        label: 'اليوم',
                        icon: Icons.today,
                        color: SdColors.primary,
                        isActive: _hasSearched && _dateFrom == null && _dateTo == null,
                        onTap: () {
                          _refTypeFilter = 'all';
                          _dateFrom = null;
                          _dateTo = null;
                          _loadData(showResults: true);
                        },
                      ),
                      const SizedBox(width: 6),
                      _quickPeriodBtn(
                        label: 'أمس',
                        icon: Icons.history,
                        color: SdColors.muted,
                        onTap: () {
                          _refTypeFilter = 'all';
                          final yesterday = DateTime.now().subtract(const Duration(days: 1));
                          _dateFrom = DateTime(yesterday.year, yesterday.month, yesterday.day);
                          _dateTo = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
                          _loadData(showResults: true);
                        },
                      ),
                      const SizedBox(width: 6),
                      _quickPeriodBtn(
                        label: 'هذا الشهر',
                        icon: Icons.calendar_month,
                        color: SdColors.success,
                        onTap: () {
                          _refTypeFilter = 'all';
                          final now = DateTime.now();
                          _dateFrom = DateTime(now.year, now.month, 1);
                          _dateTo = now;
                          _loadData(showResults: true);
                        },
                      ),
                      const SizedBox(width: 10),
                      Container(width: 1, height: 20, color: SdColors.divider),
                      const SizedBox(width: 10),
                      _quickRefBtn('FtthSubscription', 'تجديدات', Icons.wifi, SdColors.info),
                      const SizedBox(width: 6),
                      _quickRefBtn('TechnicianCollection', 'قبض', Icons.arrow_downward, SdColors.success),
                      const SizedBox(width: 6),
                      _quickRefBtn('Expense', 'صرف', Icons.arrow_upward, SdColors.danger),
                      const SizedBox(width: 6),
                      _quickRefBtn('OperatorCashDelivery', 'تسليم كاش', Icons.local_shipping, SdColors.accent),
                      const SizedBox(width: 6),
                      _quickRefBtn('OperatorCreditCollection', 'تحصيل ذمم', Icons.receipt_long, const Color(0xFF673AB7)),
                      const SizedBox(width: 6),
                      _quickRefBtn('Manual', 'يدوي', Icons.edit_note, SdColors.faint),
                    ],
                  ),
                ),
              ),
              // بطاقة المجموع (مربع مدمج في الشريط)
              if (_hasSearched && filtered.isNotEmpty && !_isLoading) ...[
                const SizedBox(width: 8),
                Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: SdColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SdColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${filtered.length}',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11, fontWeight: FontWeight.bold,
                              color: SdColors.primary)),
                      const SizedBox(width: 4),
                      Text('${_fmt(totalDebit)} د.ع',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: SdColors.primary)),
                    ],
                  ),
                ),
              ],
              // إلغاء التصفية
              if (hasActiveFilter && _hasSearched) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    setState(() {
                      _searchQuery = '';
                      _searchCtrl.clear();
                      _refTypeFilter = 'all';
                      _hasSearched = false;
                    });
                    _dateFrom = null;
                    _dateTo = null;
                    _loadData();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: SdColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SdColors.danger.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear_all, size: 14, color: SdColors.danger),
                        const SizedBox(width: 4),
                        Text('مسح',
                            style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 11, color: SdColors.danger)),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickPeriodBtn({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.2) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? color : color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _quickRefBtn(String refType, String label, IconData icon, Color color) {
    final isActive = _refTypeFilter == refType && _hasSearched;
    return InkWell(
      onTap: () {
        _refTypeFilter = refType;
        _dateFrom = DateTime(2020);
        _dateTo = DateTime.now().add(const Duration(days: 1));
        _loadData(showResults: true);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? color.withOpacity(0.15) : SdColors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? color.withOpacity(0.5) : SdColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: isActive ? color : color.withOpacity(0.7)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? color : SdColors.muted)),
          ],
        ),
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
                color: SdColors.faint.withOpacity(0.3),
                size: context.accR.iconXL),
            SizedBox(height: context.accR.spaceM),
            Text(_entries.isEmpty ? 'لا توجد قيود' : 'لا توجد نتائج مطابقة',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: SdColors.faint,
                    fontSize: context.accR.headingSmall)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── رأس الجدول ──
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: SdColors.surfaceAlt,
            border: Border.all(color: SdColors.divider, width: 0.5),
          ),
          child: Row(
            children: [
              if (_isSelectionMode) _headerCell('', width: 36),
              _headerCell('الحالة', width: 60),
              _headerCell('رقم القيد', width: 120),
              _headerCellExpanded('الوصف'),
              _headerCell('النوع', width: 70),
              _headerCell('التاريخ', width: 95),
              _headerCell('المبلغ', width: 110),
              _headerCell('', width: 40),
            ],
          ),
        ),
        // ── صفوف الجدول ──
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, i) {
              final entry = filtered[i];
              final status = entry['Status']?.toString() ?? 'Draft';
              final statusInfo = _statusInfo(status);
              final lines = (entry['Lines'] as List?) ?? [];
              final totalDebit = lines.isNotEmpty
                  ? lines.fold<double>(0, (s, l) => s + ((l['DebitAmount'] ?? 0) as num).toDouble())
                  : ((entry['TotalDebit'] ?? 0) as num).toDouble();

              return InkWell(
                onTap: () {
                  if (_isSelectionMode) {
                    setState(() {
                      final id = entry['Id']?.toString() ?? '';
                      if (_selectedIds.contains(id)) _selectedIds.remove(id);
                      else _selectedIds.add(id);
                    });
                  } else {
                    _showFullEditDialog(entry, readOnly: status == 'Voided');
                  }
                },
                hoverColor: SdColors.primary.withOpacity(0.05),
                child: Container(
                  decoration: BoxDecoration(
                    color: i % 2 == 0 ? SdColors.surface : SdColors.surfaceAlt.withOpacity(0.5),
                    border: Border(
                      bottom: BorderSide(color: SdColors.divider, width: 0.5),
                      right: BorderSide(color: SdColors.divider, width: 0.5),
                      left: BorderSide(color: SdColors.divider, width: 0.5),
                    ),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isSelectionMode)
                          _rowCell(width: 36, child: Checkbox(
                            value: _selectedIds.contains(entry['Id']?.toString()),
                            activeColor: SdColors.platformLight,
                            side: BorderSide(color: SdColors.faint),
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) {
                              setState(() {
                                final id = entry['Id']?.toString() ?? '';
                                if (v == true) _selectedIds.add(id);
                                else _selectedIds.remove(id);
                              });
                            },
                          )),
                        // الحالة
                        _rowCell(width: 60, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (statusInfo['color'] as Color).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(statusInfo['label'] as String,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: statusInfo['color'] as Color,
                                  fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center),
                        )),
                        // رقم القيد
                        _rowCell(width: 120, child: Text(
                          entry['EntryNumber'] ?? '',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.primary,
                              fontSize: 11, fontWeight: FontWeight.w600),
                        )),
                        // الوصف
                        _rowCellExpanded(child: Text(
                          entry['Description'] ?? '',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.ink,
                              fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        )),
                        // النوع
                        _rowCell(width: 70, child: Text(
                          _refTypeLabel(entry['ReferenceType']),
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.muted,
                              fontSize: 10),
                          textAlign: TextAlign.center,
                        )),
                        // التاريخ
                        _rowCell(width: 95, child: Text(
                          _formatDate(entry['EntryDate'] ?? entry['CreatedAt']),
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.faint,
                              fontSize: 10),
                          textAlign: TextAlign.center,
                        )),
                        // المبلغ
                        _rowCell(width: 110, child: Text(
                          '${_fmt(totalDebit)} د.ع',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              color: SdColors.success,
                              fontSize: 12, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        )),
                        // القائمة
                        _rowCell(width: 40, child: PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          iconSize: 18,
                          icon: Icon(Icons.more_vert, color: SdColors.faint, size: 16),
                          color: SdColors.surface,
                          onSelected: (a) {
                            switch (a) {
                              case 'edit': _showFullEditDialog(entry); break;
                              case 'view': _showFullEditDialog(entry, readOnly: true); break;
                              case 'post': _postEntry(entry); break;
                              case 'void': _voidEntry(entry); break;
                              case 'delete': _confirmDeleteEntry(entry); break;
                            }
                          },
                          itemBuilder: (_) => [
                            if (status != 'Voided' && PermissionManager.instance.canEdit('accounting.journals'))
                              _menuItem('edit', Icons.edit_note, 'تعديل', SdColors.info),
                            if (status == 'Voided')
                              _menuItem('view', Icons.visibility, 'عرض', SdColors.faint),
                            if (status == 'Draft' && PermissionManager.instance.canEdit('accounting.journals'))
                              _menuItem('post', Icons.check_circle, 'ترحيل', SdColors.success),
                            if (status == 'Posted' && PermissionManager.instance.canEdit('accounting.journals'))
                              _menuItem('void', Icons.cancel, 'إلغاء', SdColors.danger),
                            if (VpsAuthService.instance.currentUser?.isAdmin == true)
                              _menuItem('delete', Icons.delete_outline, 'حذف', SdColors.danger),
                          ],
                        )),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── مساعدات الجدول ──

  Widget _headerCell(String text, {required double width}) {
    return Container(
      width: width,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: SdColors.divider, width: 0.5)),
      ),
      child: Text(text, style: TextStyle(
          fontFamily: 'Cairo',
          color: SdColors.faint, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _headerCellExpanded(String text) {
    return Expanded(child: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: SdColors.divider, width: 0.5)),
      ),
      child: Text(text, style: TextStyle(
          fontFamily: 'Cairo',
          color: SdColors.faint, fontSize: 11, fontWeight: FontWeight.bold)),
    ));
  }

  Widget _rowCell({required double width, required Widget child}) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: SdColors.divider, width: 0.5)),
      ),
      child: child,
    );
  }

  Widget _rowCellExpanded({required Widget child}) {
    return Expanded(child: Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: SdColors.divider, width: 0.5)),
      ),
      child: child,
    ));
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, Color color) {
    return PopupMenuItem(value: value, child: Row(children: [
      Icon(icon, size: 16, color: color), const SizedBox(width: 8),
      Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: SdColors.ink)),
    ]));
  }

  Widget _buildPaginationBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: SdColors.surface,
        border: Border(top: BorderSide(color: SdColors.divider)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_totalPages > 1) ...[
            IconButton(
              onPressed: _currentPage > 1 ? () => _loadData(page: _currentPage - 1) : null,
              icon: const Icon(Icons.chevron_right),
              color: SdColors.muted,
              disabledColor: SdColors.faint.withOpacity(0.3),
            ),
          ],
          Text(
            'صفحة $_currentPage من $_totalPages',
            style: TextStyle(fontFamily: 'Cairo', color: SdColors.muted, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: SdColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'إجمالي: $_total سجل',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  color: SdColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
          if (_totalPages > 1) ...[
            IconButton(
              onPressed: _currentPage < _totalPages ? () => _loadData(page: _currentPage + 1) : null,
              icon: const Icon(Icons.chevron_left),
              color: SdColors.muted,
              disabledColor: SdColors.faint.withOpacity(0.3),
            ),
          ],
        ],
      ),
    );
  }

  void _showCreateDialog() async {
    // جلب دليل الحسابات أولاً
    final accountsResult = await AccountingService.instance
        .getAccounts(companyId: widget.companyId);
    if (accountsResult['success'] != true) {
      _snack('خطأ في جلب الحسابات', SdColors.danger);
      return;
    }
    final accounts = (accountsResult['data'] as List?) ?? [];
    if (accounts.length < 2) {
      _snack('يجب أن يكون لديك حسابين على الأقل لإنشاء قيد',
          SdColors.warning);
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
              backgroundColor: SdColors.surface,
              title: Text('إنشاء قيد محاسبي',
                  style: TextStyle(color: SdColors.ink)),
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
                              color: SdColors.ink,
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
                            color: SdColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  value: lines[i]['accountId']?.toString(),
                                  dropdownColor: SdColors.surface,
                                  style: TextStyle(
                                      color: SdColors.ink,
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
                                        color: SdColors.faint,
                                        fontSize: context.accR.small),
                                    filled: true,
                                    fillColor: SdColors.surfaceAlt,
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
                                      color: SdColors.success,
                                      fontSize: context.accR.financialSmall),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => ss(() => lines[i]['debit'] =
                                      double.tryParse(v) ?? 0.0),
                                  decoration: InputDecoration(
                                    labelText: 'مدين',
                                    labelStyle: TextStyle(
                                        color: SdColors.success,
                                        fontSize: context.accR.caption),
                                    filled: true,
                                    fillColor: SdColors.surfaceAlt,
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
                                      color: SdColors.danger,
                                      fontSize: context.accR.financialSmall),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => ss(() => lines[i]
                                      ['credit'] = double.tryParse(v) ?? 0.0),
                                  decoration: InputDecoration(
                                    labelText: 'دائن',
                                    labelStyle: TextStyle(
                                        color: SdColors.danger,
                                        fontSize: context.accR.caption),
                                    filled: true,
                                    fillColor: SdColors.surfaceAlt,
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
                                      color: SdColors.danger,
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
                            foregroundColor: SdColors.success),
                      ),
                      SizedBox(height: context.accR.spaceS),
                      // الإجماليات
                      Container(
                        padding: EdgeInsets.all(context.accR.spaceS),
                        decoration: BoxDecoration(
                          color: isBalanced
                              ? SdColors.success.withValues(alpha: 0.2)
                              : SdColors.danger.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: isBalanced
                                  ? SdColors.success
                                  : SdColors.danger,
                              width: 0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text('مدين: ${_fmt(totalDebit)}',
                                style: TextStyle(
                                    color: SdColors.success,
                                    fontSize: context.accR.financialSmall)),
                            Text('دائن: ${_fmt(totalCredit)}',
                                style: TextStyle(
                                    color: SdColors.danger,
                                    fontSize: context.accR.financialSmall)),
                            Icon(
                              isBalanced ? Icons.check_circle : Icons.warning,
                              color: isBalanced
                                  ? SdColors.success
                                  : SdColors.danger,
                              size: context.accR.iconM,
                            ),
                            Text(
                              isBalanced ? 'متوازن' : 'غير متوازن',
                              style: TextStyle(
                                  color: isBalanced
                                      ? SdColors.success
                                      : SdColors.danger,
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
                        style: TextStyle(color: SdColors.faint))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isBalanced
                        ? SdColors.success
                        : SdColors.faint,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isBalanced
                      ? () async {
                          if (descCtrl.text.isEmpty) {
                            _snack('الرجاء إدخال وصف', SdColors.warning);
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
                                SdColors.warning);
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
                            _snack('تم إنشاء القيد', SdColors.success);
                            AuditTrailService.instance.log(
                              action: AuditAction.create,
                              entityType: AuditEntityType.journalEntry,
                              entityId: result['data']?['Id']?.toString() ?? '',
                              entityDescription: 'قيد: ${descCtrl.text}',
                            );
                            _loadData();
                          } else {
                            _snack(result['message'] ?? 'خطأ',
                                SdColors.danger);
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
          backgroundColor: SdColors.surface,
          title: Text('ترحيل القيد',
              style: TextStyle(color: SdColors.ink)),
          content: const Text(
              'هل تريد ترحيل هذا القيد؟ لا يمكن التعديل بعد الترحيل.',
              style: TextStyle(color: SdColors.muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: TextStyle(color: SdColors.faint))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.success),
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
      _snack('تم ترحيل القيد', SdColors.success);
      AuditTrailService.instance.log(
        action: AuditAction.post,
        entityType: AuditEntityType.journalEntry,
        entityId: entry['Id']?.toString() ?? '',
        entityDescription: 'قيد: ${entry['Description'] ?? ''}',
      );
      _loadData();
    } else {
      _snack(result['message'] ?? 'خطأ', SdColors.danger);
    }
  }

  void _voidEntry(dynamic entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          title: Text('إلغاء القيد',
              style: TextStyle(color: SdColors.ink)),
          content: Text('هل تريد إلغاء هذا القيد؟ سيتم عكس جميع الأرصدة.',
              style: TextStyle(color: SdColors.muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('رجوع',
                    style: TextStyle(color: SdColors.faint))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger),
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
      _snack('تم إلغاء القيد', SdColors.success);
      AuditTrailService.instance.log(
        action: AuditAction.void_,
        entityType: AuditEntityType.journalEntry,
        entityId: entry['Id']?.toString() ?? '',
        entityDescription: 'قيد: ${entry['Description'] ?? ''}',
      );
      _loadData();
    } else {
      _snack(result['message'] ?? 'خطأ', SdColors.danger);
    }
  }

  Map<String, dynamic> _statusInfo(String status) {
    switch (status) {
      case 'Posted':
        return {'label': 'مرحل', 'color': SdColors.success};
      case 'Voided':
        return {'label': 'ملغي', 'color': SdColors.danger};
      default:
        return {'label': 'مسودة', 'color': SdColors.faint};
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
              color: isSelected ? color.withOpacity(0.5) : SdColors.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: isSelected ? color : SdColors.faint),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? color : SdColors.muted,
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
      style: const TextStyle(color: SdColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: SdColors.faint),
        filled: true,
        fillColor: SdColors.surfaceAlt,
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
    DateTime entryDate = DateTime.tryParse(entry['EntryDate']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    TimeOfDay entryTime = TimeOfDay(hour: entryDate.hour, minute: entryDate.minute);

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
              backgroundColor: SdColors.surface,
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
                        color: SdColors.surfaceAlt,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        border: const Border(bottom: BorderSide(color: SdColors.divider)),
                      ),
                      child: Row(
                        children: [
                          Icon(effectiveReadOnly ? Icons.visibility : Icons.edit_note,
                              color: SdColors.info, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(effectiveReadOnly ? 'تفاصيل القيد' : 'تعديل القيد',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: SdColors.ink,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                Text('#${entry['EntryNumber'] ?? ''}',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: SdColors.primary, fontSize: 12)),
                              ],
                            ),
                          ),
                          // حالة القيد
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: (status == 'Posted'
                                      ? SdColors.success
                                      : status == 'Voided'
                                          ? SdColors.danger
                                          : SdColors.warning)
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status == 'Posted' ? 'مرحّل' : status == 'Voided' ? 'ملغي' : 'مسودة',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                color: status == 'Posted'
                                    ? SdColors.success
                                    : status == 'Voided'
                                        ? SdColors.danger
                                        : SdColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, size: 20),
                            style: IconButton.styleFrom(foregroundColor: SdColors.faint),
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
                                        setDState(() => entryDate = DateTime(picked.year, picked.month, picked.day, entryTime.hour, entryTime.minute));
                                      }
                                    },
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'التاريخ',
                                        labelStyle: const TextStyle(color: SdColors.faint),
                                        filled: true,
                                        fillColor: SdColors.surfaceAlt,
                                        border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide.none),
                                        suffixIcon: Icon(Icons.calendar_today,
                                            size: 16, color: SdColors.faint),
                                        isDense: true,
                                      ),
                                      child: Text(
                                        '${entryDate.year}/${entryDate.month.toString().padLeft(2, '0')}/${entryDate.day.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: SdColors.ink, fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!effectiveReadOnly) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(width: 90, child: InkWell(
                                    onTap: () async {
                                      final picked = await showTimePicker(context: ctx, initialTime: entryTime);
                                      if (picked != null) setDState(() {
                                        entryTime = picked;
                                        entryDate = DateTime(entryDate.year, entryDate.month, entryDate.day, picked.hour, picked.minute);
                                      });
                                    },
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'الوقت',
                                        labelStyle: const TextStyle(color: SdColors.faint),
                                        filled: true,
                                        fillColor: SdColors.surfaceAlt,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                        suffixIcon: Icon(Icons.access_time, size: 16, color: SdColors.faint),
                                        isDense: true,
                                      ),
                                      child: Text(
                                        '${entryTime.hour.toString().padLeft(2, '0')}:${entryTime.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(color: SdColors.ink, fontSize: 13),
                                      ),
                                    ),
                                  )),
                                ],
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
                            const Divider(color: SdColors.divider),
                            const SizedBox(height: 10),

                            // ── عنوان الأسطر ──
                            Row(
                              children: [
                                Text('أسطر القيد',
                                    style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: SdColors.ink,
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
                                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                                    style: TextButton.styleFrom(
                                        foregroundColor: SdColors.success),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // ── رأس الجدول ──
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: SdColors.surfaceAlt,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                border: Border.all(color: SdColors.divider),
                              ),
                              child: Row(
                                children: [
                                  if (!effectiveReadOnly)
                                    const SizedBox(width: 32),
                                  Expanded(flex: 3, child: Text('الحساب',
                                      style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint, fontSize: 11, fontWeight: FontWeight.bold))),
                                  SizedBox(width: 100, child: Text('مدين',
                                      style: TextStyle(fontFamily: 'Cairo', color: SdColors.success, fontSize: 11, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center)),
                                  SizedBox(width: 100, child: Text('دائن',
                                      style: TextStyle(fontFamily: 'Cairo', color: SdColors.danger, fontSize: 11, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center)),
                                  Expanded(flex: 2, child: Text('البيان',
                                      style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint, fontSize: 11, fontWeight: FontWeight.bold))),
                                ],
                              ),
                            ),

                            // ── أسطر القيد ──
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: SdColors.divider),
                                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                              ),
                              child: Column(
                                children: [
                                  for (int i = 0; i < lines.length; i++)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: i.isEven ? Colors.transparent : SdColors.surfaceAlt.withOpacity(0.3),
                                        border: i < lines.length - 1
                                            ? const Border(bottom: BorderSide(color: SdColors.divider, width: 0.5))
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
                                                      style: IconButton.styleFrom(foregroundColor: SdColors.danger),
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
                                                    style: const TextStyle(color: SdColors.muted, fontSize: 12),
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
                                                        color: lines[i]['debit'] > 0 ? SdColors.success : SdColors.faint,
                                                        fontSize: 12),
                                                    textAlign: TextAlign.center,
                                                  )
                                                : _amountField(
                                                    controller: lines[i]['debitCtrl'],
                                                    color: SdColors.success,
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
                                                        color: lines[i]['credit'] > 0 ? SdColors.danger : SdColors.faint,
                                                        fontSize: 12),
                                                    textAlign: TextAlign.center,
                                                  )
                                                : _amountField(
                                                    controller: lines[i]['creditCtrl'],
                                                    color: SdColors.danger,
                                                    onChanged: () => setDState(() {}),
                                                  ),
                                          ),
                                          // البيان
                                          Expanded(
                                            flex: 2,
                                            child: effectiveReadOnly
                                                ? Text(lines[i]['description'] ?? '',
                                                    style: const TextStyle(color: SdColors.faint, fontSize: 11))
                                                : TextField(
                                                    controller: lines[i]['descCtrl'],
                                                    style: const TextStyle(color: SdColors.ink, fontSize: 12),
                                                    decoration: InputDecoration(
                                                      hintText: 'بيان...',
                                                      hintStyle: TextStyle(color: SdColors.faint.withOpacity(0.4), fontSize: 11),
                                                      filled: true,
                                                      fillColor: SdColors.ground,
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
                                    ? SdColors.success.withOpacity(0.1)
                                    : SdColors.danger.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: isBalanced
                                        ? SdColors.success.withOpacity(0.3)
                                        : SdColors.danger.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isBalanced ? Icons.check_circle : Icons.warning,
                                    size: 16,
                                    color: isBalanced ? SdColors.success : SdColors.danger,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(isBalanced ? 'القيد متوازن' : 'القيد غير متوازن!',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: isBalanced ? SdColors.success : SdColors.danger,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const Spacer(),
                                  Text('مدين: ${_fmt(totalDebit)}',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: SdColors.success,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(width: 16),
                                  Text('دائن: ${_fmt(totalCredit)}',
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: SdColors.danger,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                  if (!isBalanced) ...[
                                    const SizedBox(width: 16),
                                    Text('فرق: ${_fmt((totalDebit - totalCredit).abs())}',
                                        style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: SdColors.warning,
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
                        color: SdColors.surfaceAlt,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                        border: Border(top: BorderSide(color: SdColors.divider)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(effectiveReadOnly ? 'إغلاق' : 'إلغاء',
                                style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint)),
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
                                          _snack('يجب اختيار حساب لكل سطر', SdColors.warning);
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
                                      final linesDtos = <Map<String, dynamic>>[];
                                      for (final l in lines) {
                                        linesDtos.add({
                                          'AccountId': l['accountId'],
                                          'DebitAmount': double.tryParse((l['debitCtrl'] as TextEditingController).text) ?? 0.0,
                                          'CreditAmount': double.tryParse((l['creditCtrl'] as TextEditingController).text) ?? 0.0,
                                          'Description': (l['descCtrl'] as TextEditingController).text,
                                        });
                                      }

                                      final body = {
                                        'Description': descCtrl.text,
                                        'Notes': notesCtrl.text.isEmpty ? null : notesCtrl.text,
                                        'EntryDate': entryDate.toIso8601String(),
                                        'Lines': linesDtos,
                                      };
                                      debugPrint('📝 [JE-UPDATE] id=${entry['Id']}, lines=${linesDtos.length}');
                                      for (int i = 0; i < linesDtos.length; i++) {
                                        debugPrint('   line[$i]: acc=${linesDtos[i]['AccountId']}, D=${linesDtos[i]['DebitAmount']}, C=${linesDtos[i]['CreditAmount']}');
                                      }
                                      final result = await AccountingService.instance.updateJournalEntry(
                                        entry['Id'].toString(),
                                        body,
                                      );
                                      debugPrint('📝 [JE-UPDATE] result: success=${result['success']}, msg=${result['message']}, code=${result['statusCode']}');

                                      if (!ctx.mounted) return;
                                      setDState(() => isSaving = false);

                                      if (result['success'] == true) {
                                        Navigator.pop(ctx);
                                        _snack('تم تحديث القيد بنجاح', SdColors.success);
                                        AuditTrailService.instance.log(
                                          action: AuditAction.edit,
                                          entityType: AuditEntityType.journalEntry,
                                          entityId: entry['Id']?.toString() ?? '',
                                          entityDescription: 'قيد: ${descCtrl.text}',
                                        );
                                        _loadData();
                                      } else {
                                        _snack(result['message'] ?? 'خطأ في تحديث القيد', SdColors.danger);
                                      }
                                    },
                              icon: isSaving
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.save, size: 18),
                              label: Text(isSaving ? 'جاري الحفظ...' : 'حفظ التعديلات',
                                  style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SdColors.info,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: SdColors.faint.withOpacity(0.3),
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
      style: const TextStyle(color: SdColors.ink, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: SdColors.faint, fontSize: 12),
        filled: true,
        fillColor: readOnly ? Colors.transparent : SdColors.surfaceAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: readOnly ? BorderSide(color: SdColors.divider) : BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: readOnly ? BorderSide(color: SdColors.divider) : BorderSide.none),
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint, fontSize: 11)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: SdColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(value,
              style: TextStyle(fontFamily: 'Cairo', color: SdColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
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
        hintStyle: TextStyle(color: SdColors.faint.withOpacity(0.3), fontSize: 11),
        filled: true,
        fillColor: SdColors.ground,
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
      dropdownColor: SdColors.surface,
      style: const TextStyle(color: SdColors.ink, fontSize: 12),
      decoration: InputDecoration(
        filled: true,
        fillColor: SdColors.ground,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: BorderSide.none),
      ),
      hint: Text('اختر حساب...', style: TextStyle(color: SdColors.faint.withOpacity(0.5), fontSize: 11)),
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
          backgroundColor: SdColors.surface,
          title: Text('تأكيد الحذف',
              style: TextStyle(color: SdColors.danger)),
          content: Text(
            'هل تريد حذف القيد "${entry['Description'] ?? 'قيد #${entry['EntryNumber']}'}"؟\nسيتم عكس أرصدة الحسابات المتأثرة.',
            style: const TextStyle(color: SdColors.ink),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء',
                  style: TextStyle(color: SdColors.faint)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger,
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
                  _snack('تم حذف القيد', SdColors.success);
                  AuditTrailService.instance.log(
                    action: AuditAction.delete,
                    entityType: AuditEntityType.journalEntry,
                    entityId: entry['Id']?.toString() ?? '',
                    entityDescription: 'قيد: ${entry['Description'] ?? ''}',
                  );
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
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: isSelected ? Colors.white : SdColors.muted)),
      selected: isSelected,
      selectedColor: SdColors.info,
      backgroundColor: SdColors.surfaceAlt,
      side: BorderSide(
          color: isSelected ? SdColors.info : SdColors.divider),
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
                  style: TextStyle(
                      fontFamily: 'Cairo',
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
      _snack('لا توجد مسودات محددة للترحيل', SdColors.warning);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          title: Text('ترحيل ${drafts.length} قيد',
              style: TextStyle(color: SdColors.ink)),
          content: Text(
              'هل تريد ترحيل ${drafts.length} قيد مسودة؟ لا يمكن التعديل بعد الترحيل.',
              style: const TextStyle(color: SdColors.muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: TextStyle(color: SdColors.faint))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.success),
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
        fail > 0 ? SdColors.warning : SdColors.success);
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
      _snack('لا توجد قيود مرحلة محددة للإلغاء', SdColors.warning);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: SdColors.surface,
          title: Text('إلغاء ${posted.length} قيد',
              style: TextStyle(color: SdColors.ink)),
          content: Text(
              'هل تريد إلغاء ${posted.length} قيد مرحل؟ سيتم عكس الأرصدة.',
              style: const TextStyle(color: SdColors.muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('رجوع',
                    style: TextStyle(color: SdColors.faint))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger),
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
        fail > 0 ? SdColors.warning : SdColors.success);
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
          backgroundColor: SdColors.surface,
          title: Text('حذف ${ids.length} قيد',
              style: TextStyle(color: SdColors.danger)),
          content: Text(
              'هل تريد حذف ${ids.length} قيد؟ لا يمكن التراجع عن هذا الإجراء.',
              style: const TextStyle(color: SdColors.muted)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: TextStyle(color: SdColors.faint))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.danger,
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
            backgroundColor: SdColors.surface,
            title: Text('جاري الحذف...', style: TextStyle(color: SdColors.danger)),
            content: ValueListenableBuilder<int>(
              valueListenable: progressNotifier,
              builder: (_, done, __) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: done / total,
                    backgroundColor: SdColors.surface,
                    valueColor: AlwaysStoppedAnimation(SdColors.danger),
                  ),
                  const SizedBox(height: 12),
                  Text('$done / $total',
                      style: const TextStyle(color: SdColors.ink, fontSize: 16)),
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
          fail > 0 ? SdColors.warning : SdColors.success);
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
