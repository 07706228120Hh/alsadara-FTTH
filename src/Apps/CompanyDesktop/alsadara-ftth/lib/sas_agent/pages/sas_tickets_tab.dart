import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../permissions/permission_manager.dart';
import '../models/sas_ticket.dart';
import '../services/sas_agent_api_service.dart';
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
      content: Text(msg, style: const TextStyle(fontFamily: SdText.family)),
      backgroundColor: error ? SdColors.danger : SdColors.success,
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SasStatCard(
              label: 'الإجمالي',
              value: '${_stats.total}',
              color: SdColors.primary,
              icon: Icons.confirmation_number_rounded,
            ),
            const SizedBox(width: 10),
            SasStatCard(
              label: 'مفتوحة',
              value: '${_stats.open}',
              color: SdColors.info,
              icon: Icons.mark_email_unread_rounded,
            ),
            const SizedBox(width: 10),
            SasStatCard(
              label: 'قيد المعالجة',
              value: '${_stats.inProgress}',
              color: SdColors.warning,
              icon: Icons.autorenew_rounded,
            ),
            const SizedBox(width: 10),
            SasStatCard(
              label: 'محلولة',
              value: '${_stats.resolved}',
              color: SdColors.success,
              icon: Icons.check_circle_rounded,
            ),
            const SizedBox(width: 10),
            SasStatCard(
              label: 'مغلقة',
              value: '${_stats.closed}',
              color: SdGroup.neutral.tone.base,
              icon: Icons.lock_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: SdDepth.raised(),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField()),
              const SizedBox(width: 10),
              _newTicketButton(),
            ],
          ),
          const SizedBox(height: 10),
          _statusChips(),
          const SizedBox(height: 8),
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
      style: const TextStyle(
          fontFamily: SdText.family, fontSize: 13, color: SdColors.ink),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'بحث بالموضوع أو المشترك…',
        hintStyle: const TextStyle(
            fontFamily: SdText.family, fontSize: 12.5, color: SdColors.faint),
        prefixIcon: const Icon(Icons.search_rounded,
            size: 20, color: SdColors.primary),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _searchCtl.clear();
                  _applySearch('');
                },
              ),
        filled: true,
        fillColor: SdColors.ground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _newTicketButton() {
    return SdButton(
      label: _canManage ? 'تذكرة جديدة' : 'لا صلاحية',
      icon: Icons.add_rounded,
      height: 46,
      onPressed: _canManage ? _newTicket : null,
    );
  }

  Widget _statusChips() {
    return SdFilterChips<String?>(
      options: [
        const SdFilterOption<String?>(null, 'الكل'),
        for (final e in sasTicketStatuses.entries)
          SdFilterOption<String?>(e.key, e.value),
      ],
      selected: _status,
      onSelected: _applyStatus,
    );
  }

  Widget _categoryChips() {
    return SdFilterChips<String?>(
      options: [
        const SdFilterOption<String?>(null, 'كل التصنيفات'),
        for (final e in sasTicketCategories.entries)
          SdFilterOption<String?>(e.key, e.value),
      ],
      selected: _category,
      onSelected: _applyCategory,
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري تحميل التذاكر…');
    }
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return SdEmptyState(
        title: 'لا تذاكر تطابق التصفية الحالية',
        icon: Icons.confirmation_number_outlined,
        action: _canManage
            ? SdButton(
                label: 'تذكرة جديدة',
                icon: Icons.add_rounded,
                onPressed: _newTicket,
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
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
          itemCount: _rows.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, __) => const SizedBox(height: SdSpace.xs),
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
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: _paging
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: SdColors.primary),
              )
            : Text('عرض ${_rows.length} من $_total',
                style: SdText.caption.copyWith(color: SdColors.faint)),
      ),
    );
  }

  Widget _ticketCard(SasTicket t) {
    return SdRaised(
      onTap: () => _openTicket(t),
      radius: SdRadius.lg,
      padding: const EdgeInsets.all(13),
      semanticLabel: t.subject.isEmpty ? '(بلا موضوع)' : t.subject,
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
                  style: SdText.label,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_left_rounded,
                  size: 20, color: SdColors.faint),
            ],
          ),
          if (t.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              t.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SdText.bodySm,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SdStatusChip(sasStatusAr(t.status),
                  status: _statusStatus(t.status), icon: _statusIcon(t.status)),
              SdStatusChip(sasPriorityAr(t.priority),
                  status: _priorityStatus(t.priority),
                  icon: Icons.flag_rounded),
              SdStatusChip(sasCategoryAr(t.category),
                  status: SdStatus.neutral, icon: Icons.label_rounded),
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
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: SdColors.faint),
        const SizedBox(width: 3),
        Text(text, style: SdText.caption),
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
            style: const TextStyle(fontFamily: SdText.family)),
        backgroundColor: SdColors.danger,
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
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: SdColors.primaryTint,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                      color: SdColors.primaryTintEdge, offset: Offset(0, 3))
                ],
              ),
              child: const Icon(Icons.add_comment_rounded,
                  color: SdColors.primary, size: 17),
            ),
            const SizedBox(width: 10),
            const Text('تذكرة جديدة',
                style: TextStyle(
                    fontFamily: SdText.family, fontWeight: FontWeight.w800)),
          ],
        ),
        content: SizedBox(
          width: 440,
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
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'الموضوع مطلوب'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _bodyCtl,
                    label: 'التفاصيل',
                    icon: Icons.notes_rounded,
                    maxLines: 4,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'التفاصيل مطلوبة'
                        : null,
                  ),
                  const SizedBox(height: 12),
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
                      const SizedBox(width: 10),
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
                  const SizedBox(height: 12),
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
            child:
                const Text('إلغاء', style: TextStyle(fontFamily: SdText.family)),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: SdColors.primary),
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('إنشاء',
                style: TextStyle(
                    fontFamily: SdText.family, fontWeight: FontWeight.w800)),
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
      style: const TextStyle(
          fontFamily: SdText.family, fontSize: 13, color: SdColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            fontFamily: SdText.family, fontSize: 12.5, color: SdColors.muted),
        prefixIcon: Icon(icon, size: 19, color: SdColors.primary),
        alignLabelWithHint: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SdRadius.sm)),
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
      style: const TextStyle(
          fontFamily: SdText.family, fontSize: 13, color: SdColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            fontFamily: SdText.family, fontSize: 12.5, color: SdColors.muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SdRadius.sm)),
      ),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(
              value: e.key,
              child: Text(e.value,
                  style: const TextStyle(
                      fontFamily: SdText.family, fontSize: 13))),
      ],
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────── مساعدات مشتركة ───────────────────────────

SdStatus _statusStatus(String s) {
  switch (s) {
    case 'open':
      return SdStatus.info;
    case 'in_progress':
      return SdStatus.warning;
    case 'resolved':
      return SdStatus.success;
    case 'closed':
      return SdStatus.neutral;
    default:
      return SdStatus.neutral;
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

SdStatus _priorityStatus(String p) {
  switch (p) {
    case 'urgent':
      return SdStatus.danger;
    case 'high':
      return SdStatus.warning;
    case 'normal':
      return SdStatus.neutral;
    case 'low':
      return SdStatus.neutral;
    default:
      return SdStatus.neutral;
  }
}

String _fmtShort(DateTime d) {
  final dl = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${dl.year}/${two(dl.month)}/${two(dl.day)}';
}
