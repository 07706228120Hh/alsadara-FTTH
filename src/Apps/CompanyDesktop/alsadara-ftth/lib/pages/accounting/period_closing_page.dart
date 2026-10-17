import 'package:flutter/material.dart';
import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../services/period_closing_service.dart';
import '../../services/audit_trail_service.dart';
import '../../services/vps_auth_service.dart';
import '../../theme/accounting_theme.dart';

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
    final confirmColor = closed ? SdColors.warning : SdColors.danger;

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
          closed ? SdColors.success : SdColors.danger,
        );
      }
    } catch (e) {
      if (mounted) {
        AccountingTheme.showSnack(context, 'خطأ', SdColors.danger);
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SdTheme.scope(
      child: Scaffold(
        backgroundColor: SdColors.ground,
        appBar: SdAppBar(
          title: 'إقفال الفترات',
          actions: [
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _loadData,
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildYearSelector(),
              _buildSummaryBar(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildGrid(),
              ),
            ],
          ),
        ),
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
        horizontal: context.sd.gutter,
        vertical: SdSpace.sm,
      ),
      color: SdColors.surface,
      child: Center(
        child: SdFilterChips<int>(
          selected: _selectedYear,
          onSelected: (year) {
            setState(() => _selectedYear = year);
            _loadData();
          },
          options: [
            for (final y in years) SdFilterOption(y, '$y'),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // شريط الملخص
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSummaryBar() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.sd.gutter,
        vertical: SdSpace.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildSummaryChip(
            '$_closedCount فترات مقفلة',
            SdStatus.danger.tone,
          ),
          const SizedBox(width: SdSpace.md),
          _buildSummaryChip(
            '$_openCount فترات مفتوحة',
            SdStatus.success.tone,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, SdTone tone) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SdSpace.md,
        vertical: SdSpace.xs,
      ),
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.pill),
        boxShadow: [BoxShadow(color: tone.tintEdge, offset: const Offset(0, SdDepth.chip))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone.base, shape: BoxShape.circle),
          ),
          const SizedBox(width: SdSpace.xs),
          Text(
            label,
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: tone.text,
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
    final isPhone = context.sd.isPhone;
    final crossAxisCount = isPhone ? 3 : 4;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: context.sd.gutter,
        vertical: SdSpace.sm,
      ),
      child: GridView.count(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: SdSpace.md,
        crossAxisSpacing: SdSpace.md,
        childAspectRatio: isPhone ? 0.85 : 1.0,
        children: List.generate(12, (i) => _buildMonthCard(i + 1)),
      ),
    );
  }

  Widget _buildMonthCard(int month) {
    final closed = _isClosed(month);
    final monthName = _monthNames[month - 1];
    final periodStr = _periodKey(_selectedYear, month);
    final tone = closed ? SdStatus.danger.tone : SdStatus.success.tone;
    final isPhone = context.sd.isPhone;

    return Container(
      decoration: BoxDecoration(
        color: tone.tint,
        borderRadius: BorderRadius.circular(SdRadius.md),
        boxShadow: SdDepth.raised(depth: SdDepth.small, edge: tone.tintEdge),
        border: Border.all(color: tone.tintEdge, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(SdRadius.md),
          onTap: () => _togglePeriod(month),
          child: Padding(
            padding: const EdgeInsets.all(SdSpace.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // اسم الشهر
                Text(
                  monthName,
                  style: isPhone ? SdText.label : SdText.titleSm,
                ),
                const SizedBox(height: SdSpace.xxs),
                // YYYY-MM
                Text(
                  periodStr,
                  style: SdText.caption,
                ),
                const SizedBox(height: SdSpace.xs),
                // أيقونة القفل
                Icon(
                  closed ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: isPhone ? 28 : 34,
                  color: tone.base,
                ),
                const SizedBox(height: SdSpace.xxs),
                // حالة
                Text(
                  closed ? 'مقفلة' : 'مفتوحة',
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: tone.text,
                  ),
                ),
                const SizedBox(height: SdSpace.xs),
                // زر الإجراء
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: ElevatedButton(
                    onPressed: () => _togglePeriod(month),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          closed ? SdColors.success : SdColors.danger,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SdRadius.xs),
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      closed ? 'إعادة فتح' : 'إقفال',
                      style: const TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
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
