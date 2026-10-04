import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
import '../models/sas_ticket.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_state_views.dart';
import 'sas_ticket_detail_page.dart';

/// تبويب «تذاكر» — نظام تذاكر أصلي لوحدة «وكيل الساس» (user-scoped).
///
/// يعرض: بطاقات إحصاء (إجمالي/مفتوحة/قيد المعالجة/محلولة) · قائمة تذاكر
/// بفلترة (حالة/تصنيف) + بحث + ترقيم + شارات دلالية · زر «تذكرة جديدة».
/// النقر على تذكرة يفتح [SasTicketDetailPage]. الكتابة محكومة بـ
/// `canAdd('sas_agent')`.
class SasTicketsTab extends StatefulWidget {
  const SasTicketsTab({super.key});

  @override
  State<SasTicketsTab> createState() => _SasTicketsTabState();
}

class _SasTicketsTabState extends State<SasTicketsTab> {
  final _api = SasAgentApiService.instance;
  final _searchCtl = TextEditingController();

  SasTicketStats _stats = SasTicketStats.empty;
  List<SasTicket> _rows = [];
  int _total = 0;
  int _page = 1;
  int _count = 20;

  bool _loading = true;
  bool _paging = false;
  String? _error;

  String? _status = 'open';
  String? _category;
  String _search = '';

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');
  bool get _hasMore => _page * _count < _total;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  /// تحميل كامل (إحصاء + الصفحة الأولى). يُستدعى عند البدء وعند تغيّر الفلاتر.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final results = await Future.wait([
        _api.getTicketsStats(),
        _api.getTickets(
          status: _status,
          category: _category,
          search: _search,
          page: 1,
          count: _count,
        ),
      ]);
      if (!mounted) return;
      final stats = results[0] as SasTicketStats;
      final pageData = results[1] as SasTicketsPage;
      setState(() {
        _stats = stats;
        _rows = pageData.rows;
        _total = pageData.total;
        _count = pageData.count > 0 ? pageData.count : _count;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _clean(e);
          _loading = false;
        });
      }
    }
  }

  /// تحميل الصفحة التالية وإلحاقها.
  Future<void> _loadMore() async {
    if (_paging || !_hasMore) return;
    setState(() => _paging = true);
    try {
      final next = _page + 1;
      final pageData = await _api.getTickets(
        status: _status,
        category: _category,
        search: _search,
        page: next,
        count: _count,
      );
      if (!mounted) return;
      setState(() {
        _page = next;
        _rows = [..._rows, ...pageData.rows];
        _total = pageData.total;
        _paging = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _paging = false);
        _snack(_clean(e), error: true);
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
    ));
  }

  void _applyStatus(String? v) {
    setState(() => _status = v);
    _load();
  }

  void _applyCategory(String? v) {
    setState(() => _category = v);
    _load();
  }

  void _applySearch(String v) {
    setState(() => _search = v.trim());
    _load();
  }

  Future<void> _openTicket(SasTicket t) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SasTicketDetailPage(ticketId: t.id),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _newTicket() async {
    if (!_canManage) return;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewTicketDialog(api: _api),
    );
    if (created == true) {
      _snack('تم إنشاء التذكرة');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SasContentWrap(
      maxWidth: 1100,
      child: Column(
        children: [
          _statsRow(),
          _controls(),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _statsRow() {
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 4.h),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SasStatCard(
              label: 'الإجمالي',
              value: '${_stats.total}',
              color: AppTheme.primaryColor,
              icon: Icons.confirmation_number_rounded,
            ),
            SizedBox(width: 10.w),
            SasStatCard(
              label: 'مفتوحة',
              value: '${_stats.open}',
              color: const Color(0xFF3949AB),
              icon: Icons.mark_email_unread_rounded,
            ),
            SizedBox(width: 10.w),
            SasStatCard(
              label: 'قيد المعالجة',
              value: '${_stats.inProgress}',
              color: AppTheme.warningColor,
              icon: Icons.autorenew_rounded,
            ),
            SizedBox(width: 10.w),
            SasStatCard(
              label: 'محلولة',
              value: '${_stats.resolved}',
              color: AppTheme.successColor,
              icon: Icons.check_circle_rounded,
            ),
            SizedBox(width: 10.w),
            SasStatCard(
              label: 'مغلقة',
              value: '${_stats.closed}',
              color: Colors.blueGrey,
              icon: Icons.lock_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 8.h, 14.w, 4.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: SasUi.card(),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField()),
              SizedBox(width: 10.w),
              _newTicketButton(),
            ],
          ),
          SizedBox(height: 10.h),
          _statusChips(),
          SizedBox(height: 8.h),
          _categoryChips(),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchCtl,
      textInputAction: TextInputAction.search,
      onSubmitted: _applySearch,
      style: GoogleFonts.cairo(fontSize: 13.sp),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'بحث بالموضوع أو المشترك…',
        hintStyle: GoogleFonts.cairo(fontSize: 12.5.sp, color: Colors.grey[500]),
        prefixIcon: Icon(Icons.search_rounded, size: 20.sp),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close_rounded, size: 18.sp),
                onPressed: () {
                  _searchCtl.clear();
                  _applySearch('');
                },
              ),
        filled: true,
        fillColor: SasUi.pageBg,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _newTicketButton() {
    return FilledButton.icon(
      onPressed: _canManage ? _newTicket : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.primaryColor,
        disabledBackgroundColor: Colors.grey.withValues(alpha: 0.30),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
      ),
      icon: Icon(Icons.add_rounded, size: 18.sp),
      label: Text(_canManage ? 'تذكرة جديدة' : 'لا صلاحية',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 12.5.sp)),
    );
  }

  Widget _statusChips() {
    return _chipRow<String?>(
      options: {
        null: 'الكل',
        for (final e in sasTicketStatuses.entries) e.key: e.value,
      },
      value: _status,
      onChanged: _applyStatus,
    );
  }

  Widget _categoryChips() {
    return _chipRow<String?>(
      options: {
        null: 'كل التصنيفات',
        for (final e in sasTicketCategories.entries) e.key: e.value,
      },
      value: _category,
      onChanged: _applyCategory,
    );
  }

  Widget _chipRow<T>({
    required Map<T, String> options,
    required T value,
    required ValueChanged<T> onChanged,
  }) {
    return SizedBox(
      height: 34.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final e in options.entries) ...[
            _filterChip(
              label: e.value,
              selected: e.key == value,
              onTap: () => onChanged(e.key),
            ),
            SizedBox(width: 6.w),
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SasUi.radiusPill.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor
              : AppTheme.primaryColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(SasUi.radiusPill.r),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : AppTheme.primaryColor.withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12.sp,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppTheme.primaryColor,
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري تحميل التذاكر…');
    }
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return SasEmptyView(
        message: 'لا تذاكر تطابق التصفية الحالية',
        icon: Icons.confirmation_number_outlined,
        action: _canManage
            ? FilledButton.icon(
                onPressed: _newTicket,
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor),
                icon: const Icon(Icons.add_rounded),
                label: Text('تذكرة جديدة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              )
            : null,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
              _hasMore &&
              !_paging) {
            _loadMore();
          }
          return false;
        },
        child: ListView.separated(
          padding: EdgeInsets.fromLTRB(14.w, 6.h, 14.w, 16.h),
          itemCount: _rows.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, __) => SizedBox(height: 8.h),
          itemBuilder: (_, i) {
            if (i >= _rows.length) return _pagingFooter();
            return _ticketCard(_rows[i]);
          },
        ),
      ),
    );
  }

  Widget _pagingFooter() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14.h),
      child: Center(
        child: _paging
            ? SizedBox(
                width: 22.w,
                height: 22.w,
                child: const CircularProgressIndicator(strokeWidth: 2.4),
              )
            : Text('عرض ${_rows.length} من $_total',
                style: GoogleFonts.cairo(
                    fontSize: 11.5.sp, color: Colors.grey[500])),
      ),
    );
  }

  Widget _ticketCard(SasTicket t) {
    return InkWell(
      onTap: () => _openTicket(t),
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: Container(
        padding: EdgeInsets.all(13.w),
        decoration: SasUi.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.subject.isEmpty ? '(بلا موضوع)' : t.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A2E)),
                  ),
                ),
                SizedBox(width: 8.w),
                Icon(Icons.chevron_left_rounded,
                    size: 20.sp, color: Colors.grey[400]),
              ],
            ),
            if (t.body.isNotEmpty) ...[
              SizedBox(height: 4.h),
              Text(
                t.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                    fontSize: 12.sp, color: Colors.grey[600], height: 1.4),
              ),
            ],
            SizedBox(height: 10.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 6.h,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SasStatusBadge(
                  label: sasStatusAr(t.status),
                  color: _statusColor(t.status),
                  icon: _statusIcon(t.status),
                ),
                SasStatusBadge(
                  label: sasPriorityAr(t.priority),
                  color: _priorityColor(t.priority),
                  icon: Icons.flag_rounded,
                ),
                SasStatusBadge(
                  label: sasCategoryAr(t.category),
                  color: Colors.blueGrey,
                  icon: Icons.label_rounded,
                ),
                if (t.repliesCount > 0)
                  _metaChip(Icons.forum_rounded, '${t.repliesCount}'),
                if (t.subscriberRef.isNotEmpty)
                  _metaChip(Icons.person_rounded, t.subscriberRef),
                if (t.updatedAt != null)
                  _metaChip(Icons.schedule_rounded, _fmtShort(t.updatedAt!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13.sp, color: Colors.grey[500]),
        SizedBox(width: 3.w),
        Text(text,
            style: GoogleFonts.cairo(
                fontSize: 11.sp,
                color: Colors.grey[600],
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// نموذج إنشاء تذكرة جديدة (موضوع/نص/تصنيف/أولوية).
class _NewTicketDialog extends StatefulWidget {
  final SasAgentApiService api;
  const _NewTicketDialog({required this.api});

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subjectCtl = TextEditingController();
  final _bodyCtl = TextEditingController();
  final _subscriberCtl = TextEditingController();

  String _category = 'complaint';
  String _priority = 'normal';
  bool _busy = false;

  @override
  void dispose() {
    _subjectCtl.dispose();
    _bodyCtl.dispose();
    _subscriberCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false) || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.api.createTicket(
        subject: _subjectCtl.text.trim(),
        body: _bodyCtl.text.trim(),
        category: _category,
        priority: _priority,
        subscriberRef: _subscriberCtl.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            e.toString().replaceFirst('Exception: ', '').trim(),
            style: GoogleFonts.cairo()),
        backgroundColor: AppTheme.errorColor,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            SasUi.gradientBadge(
              icon: Icons.add_comment_rounded,
              colors: AppTheme.blueGradient,
              size: 34,
              iconSize: 17,
            ),
            SizedBox(width: 10.w),
            Text('تذكرة جديدة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ],
        ),
        content: SizedBox(
          width: 440.w,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    controller: _subjectCtl,
                    label: 'الموضوع',
                    icon: Icons.title_rounded,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'الموضوع مطلوب' : null,
                  ),
                  SizedBox(height: 12.h),
                  _field(
                    controller: _bodyCtl,
                    label: 'التفاصيل',
                    icon: Icons.notes_rounded,
                    maxLines: 4,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'التفاصيل مطلوبة' : null,
                  ),
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      Expanded(
                        child: _dropdown(
                          label: 'التصنيف',
                          value: _category,
                          items: sasTicketCategories,
                          onChanged: (v) => setState(() => _category = v!),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: _dropdown(
                          label: 'الأولوية',
                          value: _priority,
                          items: sasTicketPriorities,
                          onChanged: (v) => setState(() => _priority = v!),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  _field(
                    controller: _subscriberCtl,
                    label: 'مرجع المشترك (اختياري)',
                    icon: Icons.person_search_rounded,
                    required: false,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            icon: _busy
                ? SizedBox(
                    width: 16.w,
                    height: 16.w,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: Text('إنشاء',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    bool required = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: GoogleFonts.cairo(fontSize: 13.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(fontSize: 12.5.sp),
        prefixIcon: Icon(icon, size: 19.sp),
        alignLabelWithHint: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      style: GoogleFonts.cairo(fontSize: 13.sp, color: Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(fontSize: 12.5.sp),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
      ),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
              value: e.key,
              child: Text(e.value, style: GoogleFonts.cairo(fontSize: 13.sp))),
      ],
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────── مساعدات مشتركة ───────────────────────────

Color _statusColor(String s) {
  switch (s) {
    case 'open':
      return AppTheme.primaryColor;
    case 'in_progress':
      return AppTheme.warningColor;
    case 'resolved':
      return AppTheme.successColor;
    case 'closed':
      return Colors.blueGrey;
    default:
      return Colors.grey;
  }
}

IconData _statusIcon(String s) {
  switch (s) {
    case 'open':
      return Icons.mark_email_unread_rounded;
    case 'in_progress':
      return Icons.autorenew_rounded;
    case 'resolved':
      return Icons.check_circle_rounded;
    case 'closed':
      return Icons.lock_rounded;
    default:
      return Icons.help_outline_rounded;
  }
}

Color _priorityColor(String p) {
  switch (p) {
    case 'urgent':
      return AppTheme.errorColor;
    case 'high':
      return const Color(0xFFF4511E);
    case 'normal':
      return Colors.blueGrey;
    case 'low':
      return Colors.grey;
    default:
      return Colors.blueGrey;
  }
}

String _fmtShort(DateTime d) {
  final dl = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dl.year}/${two(dl.month)}/${two(dl.day)}';
}
