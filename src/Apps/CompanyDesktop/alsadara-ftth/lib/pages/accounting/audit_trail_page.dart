import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../services/audit_trail_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

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

  // ─── ألوان وأيقونات حسب نوع العملية ───

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

  Color _actionColor(String action) {
    switch (action) {
      case 'create':
        return const Color(0xFF2ECC71);
      case 'edit':
        return const Color(0xFF3498DB);
      case 'delete':
        return const Color(0xFFE74C3C);
      case 'post':
        return const Color(0xFF9B59B6);
      case 'void_':
        return const Color(0xFFE67E22);
      case 'closePeriod':
        return const Color(0xFF795548);
      case 'reopenPeriod':
        return const Color(0xFF009688);
      default:
        return AccountingTheme.textMuted;
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
    final ar = context.accR;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AccountingTheme.bgPrimary,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(ar),
              _buildFilterBar(ar),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: AccountingTheme.neonGreen))
                    : _records.isEmpty
                        ? _buildEmptyState(ar)
                        : _buildRecordsList(ar),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط الأدوات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildToolbar(AccountingResponsive ar) {
    final isMob = ar.isMobile;
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
            icon: Icon(Icons.arrow_forward_rounded, size: isMob ? 20 : 24),
            tooltip: 'رجوع',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMob ? 4 : ar.spaceS),
          Container(
            padding: EdgeInsets.all(isMob ? 4 : ar.spaceS),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF455A64), Color(0xFF37474F)],
              ),
              borderRadius: BorderRadius.circular(isMob ? 6 : 8),
            ),
            child: Icon(Icons.history_rounded,
                color: Colors.white, size: isMob ? 16 : ar.iconM),
          ),
          SizedBox(width: isMob ? 6 : ar.spaceM),
          Text('سجل التدقيق',
              style: GoogleFonts.cairo(
                fontSize: isMob ? 14 : ar.headingMedium,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              )),
          SizedBox(width: isMob ? 6 : ar.spaceS),
          // شارة عدد السجلات
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: isMob ? 6 : 10, vertical: isMob ? 2 : 3),
            decoration: BoxDecoration(
              color: AccountingTheme.neonBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AccountingTheme.neonBlue.withOpacity(0.3)),
            ),
            child: Text(
              '${_records.length}',
              style: GoogleFonts.cairo(
                fontSize: isMob ? 10 : ar.small,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.neonBlue,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _isLoading ? null : _loadData,
            icon: Icon(Icons.refresh_rounded, size: isMob ? 18 : 22),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.neonBlue),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط الفلاتر
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFilterBar(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isMob ? 8 : ar.spaceL, vertical: isMob ? 6 : ar.spaceS),
      decoration: const BoxDecoration(
        color: AccountingTheme.bgCard,
        border: Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Column(
        children: [
          // صف 1: فلتر نوع العملية (chips)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildActionChip(null, 'الكل', ar),
                _buildActionChip(AuditAction.create, 'إنشاء', ar),
                _buildActionChip(AuditAction.edit, 'تعديل', ar),
                _buildActionChip(AuditAction.delete, 'حذف', ar),
                _buildActionChip(AuditAction.post, 'ترحيل', ar),
                _buildActionChip(AuditAction.void_, 'إلغاء', ar),
                _buildActionChip(AuditAction.closePeriod, 'إقفال فترة', ar),
                _buildActionChip(AuditAction.reopenPeriod, 'إعادة فتح', ar),
              ],
            ),
          ),
          SizedBox(height: isMob ? 6 : ar.spaceS),
          // صف 2: فلتر نوع الكيان + التاريخ
          Row(
            children: [
              // قائمة منسدلة لنوع الكيان
              Expanded(
                child: Container(
                  height: isMob ? 32 : ar.btnHeight,
                  padding: EdgeInsets.symmetric(horizontal: isMob ? 8 : 12),
                  decoration: BoxDecoration(
                    color: AccountingTheme.bgSecondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AccountingTheme.borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AuditEntityType?>(
                      value: _filterEntityType,
                      isExpanded: true,
                      icon: Icon(Icons.keyboard_arrow_down,
                          size: isMob ? 16 : 20,
                          color: AccountingTheme.textMuted),
                      style: GoogleFonts.cairo(
                        fontSize: isMob ? 11 : ar.body,
                        color: AccountingTheme.textSecondary,
                      ),
                      items: [
                        DropdownMenuItem<AuditEntityType?>(
                          value: null,
                          child: Text('الكل',
                              style: GoogleFonts.cairo(
                                  fontSize: isMob ? 11 : ar.body,
                                  color: AccountingTheme.textSecondary)),
                        ),
                        ...AuditEntityType.values.map((e) {
                          return DropdownMenuItem<AuditEntityType?>(
                            value: e,
                            child: Text(
                              AuditTrailService.entityLabels[e] ?? e.name,
                              style: GoogleFonts.cairo(
                                  fontSize: isMob ? 11 : ar.body,
                                  color: AccountingTheme.textSecondary),
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
              SizedBox(width: isMob ? 6 : ar.spaceM),
              // زر نطاق التاريخ
              InkWell(
                onTap: () => _pickDateRange(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: isMob ? 32 : ar.btnHeight,
                  padding: EdgeInsets.symmetric(
                      horizontal: isMob ? 8 : 12),
                  decoration: BoxDecoration(
                    color: AccountingTheme.bgSecondary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AccountingTheme.borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month,
                          size: isMob ? 14 : 18,
                          color: AccountingTheme.neonBlue),
                      SizedBox(width: 4),
                      Text(
                        _filterFrom != null && _filterTo != null
                            ? '${DateFormat('yyyy/MM/dd').format(_filterFrom!)} - ${DateFormat('yyyy/MM/dd').format(_filterTo!)}'
                            : 'كل الفترات',
                        style: GoogleFonts.cairo(
                            fontSize: isMob ? 10 : ar.small,
                            color: AccountingTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              // زر مسح فلتر التاريخ
              if (_filterFrom != null || _filterTo != null) ...[
                SizedBox(width: 4),
                InkWell(
                  onTap: () {
                    setState(() {
                      _filterFrom = null;
                      _filterTo = null;
                    });
                    _applyFilters();
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Icon(Icons.close,
                      size: isMob ? 16 : 18,
                      color: AccountingTheme.textMuted),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip(
      AuditAction? action, String label, AccountingResponsive ar) {
    final isMob = ar.isMobile;
    final isSelected = _filterAction == action;
    return Padding(
      padding: EdgeInsets.only(left: isMob ? 4 : 6),
      child: InkWell(
        onTap: () {
          setState(() => _filterAction = action);
          _applyFilters();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: isMob ? 8 : 12, vertical: isMob ? 4 : 6),
          decoration: BoxDecoration(
            color: isSelected
                ? AccountingTheme.neonBlue
                : AccountingTheme.bgSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AccountingTheme.neonBlue
                  : AccountingTheme.borderColor,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: isMob ? 10 : ar.small,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : AccountingTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // قائمة السجلات
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRecordsList(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return ListView.builder(
      padding: EdgeInsets.all(isMob ? 8 : ar.spaceL),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        final record = _records[index];
        final action = record['action']?.toString() ?? '';
        final entityType = record['entityType']?.toString() ?? '';
        final description = record['entityDescription']?.toString() ?? '';
        final details = record['details']?.toString() ?? '';
        final userName = record['userName']?.toString() ?? '';
        final timestamp = DateTime.tryParse(record['timestamp'] ?? '');
        final color = _actionColor(action);
        final icon = _actionIcon(action);

        return Container(
          margin: EdgeInsets.only(bottom: isMob ? 4 : 6),
          padding: EdgeInsets.all(isMob ? 10 : ar.cardPad),
          decoration: BoxDecoration(
            color: index.isEven
                ? AccountingTheme.bgCard
                : AccountingTheme.tableRowAlt,
            borderRadius: BorderRadius.circular(ar.cardRadius),
            border: Border.all(color: AccountingTheme.borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // أيقونة العملية
              Container(
                width: isMob ? 32 : 40,
                height: isMob ? 32 : 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon,
                    color: color, size: isMob ? 16 : ar.iconM),
              ),
              SizedBox(width: isMob ? 8 : ar.spaceM),
              // المحتوى
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // السطر الأول: نوع العملية + نوع الكيان
                    Text(
                      '${_actionLabel(action)} ${_entityLabel(entityType)}',
                      style: GoogleFonts.cairo(
                        fontSize: isMob ? 12 : ar.body,
                        fontWeight: FontWeight.bold,
                        color: AccountingTheme.textPrimary,
                      ),
                    ),
                    // السطر الثاني: الوصف
                    if (description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description,
                          style: GoogleFonts.cairo(
                            fontSize: isMob ? 11 : ar.small,
                            color: AccountingTheme.textSecondary,
                          ),
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
                          style: GoogleFonts.cairo(
                            fontSize: isMob ? 10 : ar.caption,
                            color: AccountingTheme.textMuted,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: isMob ? 6 : ar.spaceM),
              // المستخدم والوقت
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (userName.isNotEmpty)
                    Text(
                      userName,
                      style: GoogleFonts.cairo(
                        fontSize: isMob ? 9 : ar.caption,
                        color: AccountingTheme.textMuted,
                      ),
                    ),
                  if (timestamp != null)
                    Text(
                      DateFormat('yyyy/MM/dd HH:mm').format(timestamp),
                      style: GoogleFonts.cairo(
                        fontSize: isMob ? 9 : ar.caption,
                        color: AccountingTheme.textMuted,
                      ),
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

  Widget _buildEmptyState(AccountingResponsive ar) {
    final isMob = ar.isMobile;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded,
              color: AccountingTheme.textMuted,
              size: isMob ? 48 : ar.iconEmpty),
          SizedBox(height: isMob ? 12 : ar.spaceL),
          Text(
            'لا توجد سجلات',
            style: GoogleFonts.cairo(
              fontSize: isMob ? 14 : ar.headingSmall,
              color: AccountingTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
