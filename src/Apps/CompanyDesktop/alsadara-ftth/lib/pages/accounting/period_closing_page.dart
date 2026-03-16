import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/period_closing_service.dart';
import '../../services/audit_trail_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';
import '../../theme/accounting_responsive.dart';

/// صفحة إقفال الفترات المحاسبية
/// فقط CompanyAdmin يمكنه الوصول لهذه الصفحة
class PeriodClosingPage extends StatefulWidget {
  final String? companyId;

  const PeriodClosingPage({super.key, this.companyId});

  @override
  State<PeriodClosingPage> createState() => _PeriodClosingPageState();
}

class _PeriodClosingPageState extends State<PeriodClosingPage> {
  bool _isLoading = true;
  int _selectedYear = DateTime.now().year;
  Set<String> _closedPeriods = {};

  static const _monthNames = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];

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
      await PeriodClosingService.instance.loadClosedPeriods(_companyId);
      _closedPeriods =
          PeriodClosingService.instance.getClosedPeriods(_companyId);
    } catch (_) {
      // fallback to empty
      _closedPeriods = {};
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _periodKey(int year, int month) =>
      '$year-${month.toString().padLeft(2, '0')}';

  bool _isClosed(int month) =>
      _closedPeriods.contains(_periodKey(_selectedYear, month));

  int get _closedCount {
    int count = 0;
    for (int m = 1; m <= 12; m++) {
      if (_isClosed(m)) count++;
    }
    return count;
  }

  int get _openCount => 12 - _closedCount;

  Future<void> _togglePeriod(int month) async {
    final monthName = _monthNames[month - 1];
    final closed = _isClosed(month);

    final title = closed ? 'إعادة فتح الفترة' : 'إقفال الفترة';
    final message = closed
        ? 'هل تريد إعادة فتح فترة $monthName $_selectedYear؟ سيتمكن الجميع من التعديل والحذف.'
        : 'هل تريد إقفال فترة $monthName $_selectedYear؟ لن يتمكن الموظفون من التعديل أو الحذف في هذه الفترة.';
    final confirmColor = closed ? AccountingTheme.warning : AccountingTheme.danger;

    final confirmed = await AccountingTheme.confirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: closed ? 'إعادة فتح' : 'إقفال',
      confirmColor: confirmColor,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      if (closed) {
        await PeriodClosingService.instance
            .reopenPeriod(_companyId, _selectedYear, month);
        await AuditTrailService.instance.log(
          action: AuditAction.reopenPeriod,
          entityType: AuditEntityType.period,
          entityId: _periodKey(_selectedYear, month),
          entityDescription: '$monthName $_selectedYear',
          details: 'إعادة فتح فترة $monthName $_selectedYear',
          companyId: _companyId,
        );
      } else {
        await PeriodClosingService.instance
            .closePeriod(_companyId, _selectedYear, month);
        await AuditTrailService.instance.log(
          action: AuditAction.closePeriod,
          entityType: AuditEntityType.period,
          entityId: _periodKey(_selectedYear, month),
          entityDescription: '$monthName $_selectedYear',
          details: 'إقفال فترة $monthName $_selectedYear',
          companyId: _companyId,
        );
      }
      _closedPeriods =
          PeriodClosingService.instance.getClosedPeriods(_companyId);
      if (mounted) {
        AccountingTheme.showSnack(
          context,
          closed
              ? 'تم إعادة فتح فترة $monthName $_selectedYear'
              : 'تم إقفال فترة $monthName $_selectedYear',
          closed ? AccountingTheme.success : AccountingTheme.danger,
        );
      }
    } catch (e) {
      if (mounted) {
        AccountingTheme.showSnack(context, 'خطأ', AccountingTheme.danger);
      }
    }

    if (mounted) setState(() => _isLoading = false);
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
              _buildYearSelector(),
              _buildSummaryBar(),
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: AccountingTheme.neonGreen))
                    : _buildGrid(),
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

  Widget _buildToolbar() {
    final isMobile = context.accR.isMobile;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : context.accR.spaceXL,
        vertical: isMobile ? 6 : context.accR.spaceL,
      ),
      decoration: BoxDecoration(
        color: AccountingTheme.bgCard,
        border:
            Border(bottom: BorderSide(color: AccountingTheme.borderColor)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_forward_rounded),
            tooltip: 'رجوع',
            iconSize: isMobile ? 20 : null,
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
          SizedBox(width: isMobile ? 4 : context.accR.spaceS),
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : context.accR.spaceS),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF795548), Color(0xFF5D4037)],
              ),
              borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
            ),
            child: Icon(Icons.lock_rounded,
                color: Colors.white,
                size: isMobile ? 16 : context.accR.iconM),
          ),
          SizedBox(width: isMobile ? 6 : context.accR.spaceM),
          Expanded(
            child: Text(
              'إقفال الفترات',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                fontSize: isMobile ? 14 : context.accR.headingMedium,
                fontWeight: FontWeight.bold,
                color: AccountingTheme.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: _loadData,
            icon: Icon(Icons.refresh,
                size: isMobile ? 18 : context.accR.iconM),
            tooltip: 'تحديث',
            style: IconButton.styleFrom(
                foregroundColor: AccountingTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط اختيار السنة
  // ═══════════════════════════════════════════════════════════════

  Widget _buildYearSelector() {
    final currentYear = DateTime.now().year;
    final years = [currentYear - 2, currentYear - 1, currentYear];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.accR.isMobile ? 8 : context.accR.spaceXL,
        vertical: context.accR.spaceS,
      ),
      color: AccountingTheme.bgPrimary,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: years.map((year) {
          final isSelected = year == _selectedYear;
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: context.accR.spaceXS),
            child: ChoiceChip(
              label: Text(
                '$year',
                style: GoogleFonts.cairo(
                  fontSize: context.accR.body,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? Colors.white
                      : AccountingTheme.textSecondary,
                ),
              ),
              selected: isSelected,
              selectedColor: AccountingTheme.neonBlue,
              backgroundColor: AccountingTheme.bgCard,
              side: BorderSide(
                color: isSelected
                    ? AccountingTheme.neonBlue
                    : AccountingTheme.borderColor,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              onSelected: (_) {
                setState(() => _selectedYear = year);
                _loadData();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط الملخص
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSummaryBar() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.accR.isMobile ? 8 : context.accR.spaceXL,
        vertical: context.accR.spaceS,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildSummaryChip(
            '$_closedCount فترات مقفلة',
            AccountingTheme.danger,
          ),
          SizedBox(width: context.accR.spaceM),
          _buildSummaryChip(
            '$_openCount فترات مفتوحة',
            AccountingTheme.success,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.accR.spaceM,
        vertical: context.accR.spaceXS,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: context.accR.spaceXS),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: context.accR.small,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شبكة الأشهر
  // ═══════════════════════════════════════════════════════════════

  Widget _buildGrid() {
    final isMobile = context.accR.isMobile;
    final crossAxisCount = isMobile ? 3 : 4;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : context.accR.spaceXL,
        vertical: context.accR.spaceS,
      ),
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: context.accR.spaceM,
        crossAxisSpacing: context.accR.spaceM,
        childAspectRatio: isMobile ? 0.85 : 1.0,
        children: List.generate(12, (i) => _buildMonthCard(i + 1)),
      ),
    );
  }

  Widget _buildMonthCard(int month) {
    final closed = _isClosed(month);
    final monthName = _monthNames[month - 1];
    final periodStr = _periodKey(_selectedYear, month);
    final statusColor =
        closed ? AccountingTheme.danger : AccountingTheme.success;
    final isMobile = context.accR.isMobile;

    return Container(
      decoration: BoxDecoration(
        color: closed
            ? AccountingTheme.danger.withOpacity(0.08)
            : AccountingTheme.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(context.accR.cardRadius),
        border: Border.all(
          color: statusColor.withOpacity(0.4),
          width: 1.5,
        ),
        boxShadow: AccountingTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(context.accR.cardRadius),
          onTap: () => _togglePeriod(month),
          child: Padding(
            padding: EdgeInsets.all(context.accR.cardPad),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // اسم الشهر
                Text(
                  monthName,
                  style: GoogleFonts.cairo(
                    fontSize: isMobile
                        ? context.accR.body
                        : context.accR.headingSmall,
                    fontWeight: FontWeight.bold,
                    color: AccountingTheme.textPrimary,
                  ),
                ),
                SizedBox(height: context.accR.spaceXS),
                // YYYY-MM
                Text(
                  periodStr,
                  style: GoogleFonts.cairo(
                    fontSize: context.accR.small,
                    color: AccountingTheme.textMuted,
                  ),
                ),
                SizedBox(height: context.accR.spaceS),
                // أيقونة القفل
                Icon(
                  closed ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: isMobile ? context.accR.iconL : context.accR.iconXL,
                  color: statusColor,
                ),
                SizedBox(height: context.accR.spaceXS),
                // حالة
                Text(
                  closed ? 'مقفلة' : 'مفتوحة',
                  style: GoogleFonts.cairo(
                    fontSize: context.accR.small,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
                SizedBox(height: context.accR.spaceS),
                // زر الإجراء
                SizedBox(
                  width: double.infinity,
                  height: context.accR.btnHeight * 0.8,
                  child: ElevatedButton(
                    onPressed: () => _togglePeriod(month),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: closed
                          ? AccountingTheme.success
                          : AccountingTheme.danger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(context.accR.btnRadius),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      closed ? 'إعادة فتح' : 'إقفال',
                      style: GoogleFonts.cairo(
                        fontSize: context.accR.small,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
