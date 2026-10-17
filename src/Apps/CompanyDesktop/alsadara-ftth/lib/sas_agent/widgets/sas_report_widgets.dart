import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_report.dart';

/// ودجات عرض خاصّة بتبويب «التصريح/البلنك» ومشتركين الانتهاء — عرض فقط، بنبرة sd.

/// اللون الدلالي لكل حكم مقاطعة (متطابق مع منطق العرض في مرجع الوحدة).
Color sasVerdictColor(SasVerdict v) {
  switch (v) {
    case SasVerdict.matched:
      return SdColors.success; // أخضر
    case SasVerdict.companySuspicious:
      return SdColors.warning; // برتقالي
    case SasVerdict.agentSuspicious:
      return SdColors.danger; // أحمر
    case SasVerdict.noReport:
      return SdColors.faint; // رمادي
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

  @override
  Widget build(BuildContext context) {
    final color = sasVerdictColor(recon.verdict);
    final diffColor = recon.diff == 0 ? SdColors.success : SdColors.warning;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.lg),
        border: Border.all(color: color.withValues(alpha: 0.30), width: 1.2),
        boxShadow: SdDepth.raised(glow: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // شارة الحكم الكبيرة.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(SdRadius.pill),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_verdictIcon(recon.verdict), size: 18, color: color),
                const SizedBox(width: 7),
                Text(
                  recon.verdict.labelAr,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 12),
          // الشرح العربي.
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(SdRadius.sm),
              border: Border.all(color: color.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recon.verdict.explanationAr,
                    style: SdText.body,
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(k, style: SdText.bodySm),
          ),
          const SizedBox(width: 10),
          Text(
            v,
            style: TextStyle(
              fontFamily: SdText.family,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: valueColor ?? SdColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(
        height: 1,
        thickness: 1,
        color: SdColors.divider,
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
        color: SdColors.danger,
        icon: Icons.event_busy_rounded,
      ),
      SasExpiryChipDef(
        key: 'today',
        label: 'اليوم',
        count: counts.today,
        color: SdColors.warning,
        icon: Icons.today_rounded,
      ),
      SasExpiryChipDef(
        key: 'soon3',
        label: '٣ أيام',
        count: counts.soon3,
        color: SdColors.warning,
        icon: Icons.hourglass_bottom_rounded,
      ),
      SasExpiryChipDef(
        key: 'soon7',
        label: 'أسبوع',
        count: counts.soon7,
        color: SdColors.info,
        icon: Icons.date_range_rounded,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
        borderRadius: BorderRadius.circular(SdRadius.pill),
        onTap: () => onSelect(isSel ? null : d.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSel
                ? d.color.withValues(alpha: 0.18)
                : d.color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(SdRadius.pill),
            border: Border.all(
              color: d.color.withValues(alpha: isSel ? 0.55 : 0.25),
              width: isSel ? 1.6 : 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(d.icon, size: 14, color: d.color),
              const SizedBox(width: 6),
              Text(
                d.label,
                style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: d.color,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: d.color,
                  borderRadius: BorderRadius.circular(SdRadius.pill),
                ),
                child: Text(
                  '${d.count}',
                  style: const TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
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
