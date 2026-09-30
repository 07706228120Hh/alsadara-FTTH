import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_report.dart';
import 'sas_metrics.dart';
import 'sas_state_views.dart';

/// ودجات عرض خاصّة بتبويب «التصريح/البلنك» ومشتركين الانتهاء — عرض فقط.

/// اللون الدلالي لكل حكم مقاطعة (متطابق مع منطق العرض في مرجع الوحدة).
Color sasVerdictColor(SasVerdict v) {
  switch (v) {
    case SasVerdict.matched:
      return AppTheme.successColor; // أخضر
    case SasVerdict.companySuspicious:
      return AppTheme.warningColor; // برتقالي
    case SasVerdict.agentSuspicious:
      return AppTheme.errorColor; // أحمر
    case SasVerdict.noReport:
      return Colors.grey.shade500; // رمادي
  }
}

IconData _verdictIcon(SasVerdict v) {
  switch (v) {
    case SasVerdict.matched:
      return Icons.verified_rounded;
    case SasVerdict.companySuspicious:
      return Icons.report_gmailerrorred_rounded;
    case SasVerdict.agentSuspicious:
      return Icons.warning_amber_rounded;
    case SasVerdict.noReport:
      return Icons.help_outline_rounded;
  }
}

/// بطاقة المقاطعة (البلنك): شارة حكم كبيرة بلون دلالي + مصرّح/فعلي/فارق + شرح عربي.
class SasReconciliationCard extends StatelessWidget {
  final SasReconciliation recon;

  const SasReconciliationCard({super.key, required this.recon});

  static int _abs(int x) => x < 0 ? -x : x;

  @override
  Widget build(BuildContext context) {
    final color = sasVerdictColor(recon.verdict);
    final diffColor =
        recon.diff == 0 ? AppTheme.successColor : AppTheme.warningColor;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: SasUi.card(borderColor: color.withValues(alpha: 0.30)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شارة الحكم الكبيرة.
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SasUi.radiusPill.r),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_verdictIcon(recon.verdict), size: 18.sp, color: color),
                SizedBox(width: 7.w),
                Text(
                  recon.verdict.labelAr,
                  style: GoogleFonts.cairo(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.h),
          // صفوف القيم.
          _kv('ما تنسبه الشركة إليك (فعلي)',
              recon.verdict == SasVerdict.noReport && recon.actual == 0
                  ? '—'
                  : '${recon.actual}'),
          _divider(),
          _kv(
            'ما صرّحت به',
            recon.verdict == SasVerdict.noReport ? '—' : '${recon.declared}',
          ),
          _divider(),
          _kv(
            'الفارق',
            recon.verdict == SasVerdict.noReport
                ? '—'
                : (recon.diff > 0 ? '+${recon.diff}' : '${recon.diff}'),
            valueColor:
                recon.verdict == SasVerdict.noReport ? null : diffColor,
          ),
          if (recon.source.trim().isNotEmpty) ...[
            _divider(),
            _kv('المصدر', recon.source),
          ],
          SizedBox(height: 12.h),
          // الشرح العربي.
          Container(
            padding: EdgeInsets.all(11.w),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16.sp, color: color),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    recon.verdict.explanationAr,
                    style: GoogleFonts.cairo(
                      fontSize: 12.sp,
                      height: 1.55,
                      color: Colors.grey[800],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7.h),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              k,
              style: GoogleFonts.cairo(
                fontSize: 12.5.sp,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Text(
            v,
            style: GoogleFonts.cairo(
              fontSize: 14.sp,
              fontWeight: FontWeight.w900,
              color: valueColor ?? AppTheme.primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey.withValues(alpha: 0.10),
      );
}

/// تعريف شريحة عدّاد انتهاء (قيمة مفتاح `expiring` + تسمية + لون + عدد).
class SasExpiryChipDef {
  final String key; // overdue/today/soon3/soon7
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  const SasExpiryChipDef({
    required this.key,
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });
}

/// شرائح عدّادات الانتهاء القابلة للنقر (منتهٍ/اليوم/٣ أيام/أسبوع).
///
/// [selected] المفتاح المفعّل حالياً (أو null)، و[onSelect] يبدّل الفلتر
/// (تمرير null لإلغاء الفلتر عند إعادة النقر على الشريحة نفسها).
class SasExpiryChips extends StatelessWidget {
  final SasExpiryCounts counts;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const SasExpiryChips({
    super.key,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final defs = <SasExpiryChipDef>[
      SasExpiryChipDef(
        key: 'overdue',
        label: 'منتهٍ',
        count: counts.overdue,
        color: AppTheme.errorColor,
        icon: Icons.event_busy_rounded,
      ),
      SasExpiryChipDef(
        key: 'today',
        label: 'اليوم',
        count: counts.today,
        color: AppTheme.warningColor,
        icon: Icons.today_rounded,
      ),
      SasExpiryChipDef(
        key: 'soon3',
        label: '٣ أيام',
        count: counts.soon3,
        color: const Color(0xFFF57C00),
        icon: Icons.hourglass_bottom_rounded,
      ),
      SasExpiryChipDef(
        key: 'soon7',
        label: 'أسبوع',
        count: counts.soon7,
        color: AppTheme.infoColor,
        icon: Icons.date_range_rounded,
      ),
    ];

    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        for (final d in defs) _chip(d),
      ],
    );
  }

  Widget _chip(SasExpiryChipDef d) {
    final isSel = selected == d.key;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radiusPill.r),
        onTap: () => onSelect(isSel ? null : d.key),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
          decoration: BoxDecoration(
            color: isSel
                ? d.color.withValues(alpha: 0.18)
                : d.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(SasUi.radiusPill.r),
            border: Border.all(
              color: d.color.withValues(alpha: isSel ? 0.55 : 0.25),
              width: isSel ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(d.icon, size: 14.sp, color: d.color),
              SizedBox(width: 6.w),
              Text(
                d.label,
                style: GoogleFonts.cairo(
                  fontSize: 11.5.sp,
                  fontWeight: FontWeight.w800,
                  color: d.color,
                ),
              ),
              SizedBox(width: 6.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 1.h),
                decoration: BoxDecoration(
                  color: d.color,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  '${d.count}',
                  style: GoogleFonts.cairo(
                    fontSize: 10.5.sp,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
