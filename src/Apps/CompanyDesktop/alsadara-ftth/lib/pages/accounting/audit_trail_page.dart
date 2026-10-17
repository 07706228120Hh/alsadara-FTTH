import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/audit_trail_service.dart';
import '../../services/vps_auth_service.dart';

/// صفحة سجل التدقيق - Audit Trail
class AuditTrailPage extends StatefulWidget {
  final String? companyId;

  const AuditTrailPage({super.key, this.companyId});

  @override
  State<AuditTrailPage> createState() => _AuditTrailPageState();
}

class _AuditTrailPageState extends State<AuditTrailPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _records = [];

  // فلاتر
  AuditAction? _filterAction;
  AuditEntityType? _filterEntityType;
  DateTime? _filterFrom;
  DateTime? _filterTo;

  String get _companyId =>
      widget.companyId ?? VpsAuthService.instance.currentCompanyId ?? '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      await AuditTrailService.instance.initialize(_companyId);
      _applyFilters();
    } catch (_) {
      _records = [];
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilters() {
    final results = AuditTrailService.instance.getRecords(
      action: _filterAction,
      entityType: _filterEntityType,
      fromDate: _filterFrom,
      toDate: _filterTo,
    );
    setState(() => _records = results);
  }

  // ─── نبرة وأيقونات حسب نوع العملية ───

  IconData _actionIcon(String action) {
    switch (action) {
      case 'create':
        return Icons.add_circle;
      case 'edit':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      case 'post':
        return Icons.check_circle;
      case 'void_':
        return Icons.cancel;
      case 'closePeriod':
        return Icons.lock;
      case 'reopenPeriod':
        return Icons.lock_open;
      default:
        return Icons.info;
    }
  }

  SdTone _actionTone(String action) {
    switch (action) {
      case 'create':
        return SdStatus.success.tone;
      case 'edit':
        return SdStatus.info.tone;
      case 'delete':
        return SdStatus.danger.tone;
      case 'post':
        return SdGroup.platform.tone;
      case 'void_':
        return SdStatus.warning.tone;
      case 'closePeriod':
        return SdGroup.neutral.tone;
      case 'reopenPeriod':
        return SdGroup.field.tone;
      default:
        return SdGroup.neutral.tone;
    }
  }

  String _actionLabel(String action) {
    for (final e in AuditAction.values) {
      if (e.name == action) return AuditTrailService.actionLabels[e] ?? action;
    }
    return action;
  }

  String _entityLabel(String entityType) {
    for (final e in AuditEntityType.values) {
      if (e.name == entityType) {
        return AuditTrailService.entityLabels[e] ?? entityType;
      }
    }
    return entityType;
  }

  // ─── اختيار نطاق التاريخ ───

  Future<void> _pickDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: (_filterFrom != null && _filterTo != null)
          ? DateTimeRange(start: _filterFrom!, end: _filterTo!)
          : null,
      locale: const Locale('ar'),
    );
    if (picked != null && mounted) {
      setState(() {
        _filterFrom = picked.start;
        _filterTo = picked.end;
      });
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'سجل التدقيق',
          subtitle: '${_records.length} سجل',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh_rounded,
              label: 'تحديث',
              onPressed: _isLoading ? null : _loadData,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildFilterBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _records.isEmpty
                        ? _buildEmptyState()
                        : _buildRecordsList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط الفلاتر
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFilterBar() {
    final isPhone = context.sd.isPhone;
    return Container(
      padding: EdgeInsets.fromLTRB(
          isPhone ? SdSpace.xs : SdSpace.md, SdSpace.sm, isPhone ? SdSpace.xs : SdSpace.md, SdSpace.sm),
      decoration: const BoxDecoration(
        color: SdColors.surface,
        boxShadow: [BoxShadow(color: SdColors.cardEdge, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          // صف 1: فلتر نوع العملية (chips)
          SdFilterChips<AuditAction?>(
            selected: _filterAction,
            onSelected: (val) {
              setState(() => _filterAction = val);
              _applyFilters();
            },
            options: const [
              SdFilterOption(null, 'الكل'),
              SdFilterOption(AuditAction.create, 'إنشاء'),
              SdFilterOption(AuditAction.edit, 'تعديل'),
              SdFilterOption(AuditAction.delete, 'حذف'),
              SdFilterOption(AuditAction.post, 'ترحيل'),
              SdFilterOption(AuditAction.void_, 'إلغاء'),
              SdFilterOption(AuditAction.closePeriod, 'إقفال فترة'),
              SdFilterOption(AuditAction.reopenPeriod, 'إعادة فتح'),
            ],
          ),
          const SizedBox(height: SdSpace.sm),
          // صف 2: فلتر نوع الكيان + التاريخ
          Row(
            children: [
              // قائمة منسدلة لنوع الكيان
              Expanded(
                child: Container(
                  height: context.sd.touchTarget,
                  padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm),
                  decoration: BoxDecoration(
                    color: SdColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(SdRadius.xs),
                    border: Border.all(color: SdColors.edge),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AuditEntityType?>(
                      value: _filterEntityType,
                      isExpanded: true,
                      icon: const Icon(Icons.keyboard_arrow_down,
                          size: 20, color: SdColors.faint),
                      style: const TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: SdColors.ink,
                      ),
                      items: [
                        const DropdownMenuItem<AuditEntityType?>(
                          value: null,
                          child: Text('الكل',
                              style: TextStyle(
                                  fontFamily: SdText.family,
                                  fontSize: 12.5,
                                  color: SdColors.ink)),
                        ),
                        ...AuditEntityType.values.map((e) {
                          return DropdownMenuItem<AuditEntityType?>(
                            value: e,
                            child: Text(
                              AuditTrailService.entityLabels[e] ?? e.name,
                              style: const TextStyle(
                                  fontFamily: SdText.family,
                                  fontSize: 12.5,
                                  color: SdColors.ink),
                            ),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setState(() => _filterEntityType = val);
                        _applyFilters();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SdSpace.sm),
              // زر نطاق التاريخ
              InkWell(
                onTap: () => _pickDateRange(context),
                borderRadius: BorderRadius.circular(SdRadius.xs),
                child: Container(
                  height: context.sd.touchTarget,
                  padding: const EdgeInsets.symmetric(horizontal: SdSpace.sm),
                  decoration: BoxDecoration(
                    color: SdColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(SdRadius.xs),
                    border: Border.all(color: SdColors.edge),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month,
                          size: 18, color: SdColors.primary),
                      const SizedBox(width: SdSpace.xxs),
                      Text(
                        _filterFrom != null && _filterTo != null
                            ? '${DateFormat('yyyy/MM/dd').format(_filterFrom!)} - ${DateFormat('yyyy/MM/dd').format(_filterTo!)}'
                            : 'كل الفترات',
                        style: const TextStyle(
                            fontFamily: SdText.family,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: SdColors.ink),
                      ),
                    ],
                  ),
                ),
              ),
              // زر مسح فلتر التاريخ
              if (_filterFrom != null || _filterTo != null) ...[
                const SizedBox(width: SdSpace.xxs),
                InkWell(
                  onTap: () {
                    setState(() {
                      _filterFrom = null;
                      _filterTo = null;
                    });
                    _applyFilters();
                  },
                  borderRadius: BorderRadius.circular(SdRadius.pill),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close, size: 18, color: SdColors.muted),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // قائمة السجلات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRecordsList() {
    final isPhone = context.sd.isPhone;
    return ListView.builder(
      padding: EdgeInsets.all(isPhone ? SdSpace.xs : SdSpace.md),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final record = _records[index];
        final action = record['action']?.toString() ?? '';
        final entityType = record['entityType']?.toString() ?? '';
        final description = record['entityDescription']?.toString() ?? '';
        final details = record['details']?.toString() ?? '';
        final userName = record['userName']?.toString() ?? '';
        final timestamp = DateTime.tryParse(record['timestamp'] ?? '');
        final tone = _actionTone(action);
        final icon = _actionIcon(action);

        return Container(
          margin: const EdgeInsets.only(bottom: SdSpace.xs),
          padding: EdgeInsets.all(isPhone ? SdSpace.sm : SdSpace.md),
          decoration: BoxDecoration(
            color: index.isEven ? SdColors.surface : SdColors.surfaceAlt,
            borderRadius: BorderRadius.circular(SdRadius.md),
            boxShadow: SdDepth.raised(depth: SdDepth.small),
            border: Border(right: BorderSide(color: tone.base, width: 3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // أيقونة العملية
              Container(
                width: isPhone ? 36 : 40,
                height: isPhone ? 36 : 40,
                decoration: BoxDecoration(
                  color: tone.tint,
                  borderRadius: BorderRadius.circular(SdRadius.xs),
                  boxShadow: [BoxShadow(color: tone.tintEdge, offset: const Offset(0, 2))],
                ),
                child: Icon(icon, color: tone.base, size: isPhone ? 18 : 22),
              ),
              const SizedBox(width: SdSpace.sm),
              // المحتوى
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // السطر الأول: نوع العملية + نوع الكيان
                    Text(
                      '${_actionLabel(action)} ${_entityLabel(entityType)}',
                      style: SdText.label,
                    ),
                    // السطر الثاني: الوصف
                    if (description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description,
                          style: SdText.bodySm,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    // السطر الثالث: التفاصيل
                    if (details.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          details,
                          style: SdText.caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: SdSpace.sm),
              // المستخدم والوقت
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (userName.isNotEmpty)
                    Text(userName, style: SdText.caption),
                  if (timestamp != null)
                    Text(
                      DateFormat('yyyy/MM/dd HH:mm').format(timestamp),
                      style: SdText.caption,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // حالة فارغة
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return const Center(
      child: SingleChildScrollView(
        child: SdEmptyState(
          title: 'لا توجد سجلات',
          icon: Icons.history_rounded,
        ),
      ),
    );
  }
}
