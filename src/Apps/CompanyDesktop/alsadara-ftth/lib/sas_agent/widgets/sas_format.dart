import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../theme/app_theme.dart';
import 'sas_metrics.dart';
import 'sas_state_views.dart';

/// أدوات تنسيق مشتركة لوحدة «وكيل الساس» (أرقام/بايتات/عملة/مدة) + ودجات
/// عرض صغيرة (KPI · شريط استخدام · حالة خدمة). عرض فقط — لا استدعاءات API.

/// تحويل آمن لرقم — الساس يعيد بعض الحقول العددية كنصوص ("5160").
num? sasNum(dynamic v) =>
    v is num ? v : (v == null ? null : num.tryParse(v.toString()));

int sasInt(dynamic v, [int d = 0]) {
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? d;
}

/// بايتات → نص مقروء (KB/MB/GB).
String sasBytes(dynamic b) {
  final n = sasNum(b)?.toDouble() ?? 0.0;
  if (n <= 0) return '-';
  if (n >= 1073741824) return '${(n / 1073741824).toStringAsFixed(2)} GB';
  if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1024).toStringAsFixed(0)} KB';
}

/// ثوانٍ → مدة مقروءة (أيام/ساعات/دقائق/ثوانٍ).
String sasDuration(dynamic secs) {
  final s = sasInt(secs);
  if (s <= 0) return '-';
  final d = s ~/ 86400;
  final h = (s % 86400) ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (d > 0) return '$dي $hس';
  if (h > 0) return '$hس $mد';
  if (m > 0) return '$mد $secث';
  return '$secث';
}

/// عملة عراقية.
String sasMoney(dynamic v) => v == null ? '-' : 'IQD $v';

/// منسّق الفواصل الألفية (بلا كسور للأعداد الصحيحة، منزلتان للكسور).
final NumberFormat _iqdWhole = NumberFormat('#,##0', 'en');
final NumberFormat _iqdFrac = NumberFormat('#,##0.00', 'en');

/// رصيد/مبلغ كامل بعملة IQD مع فواصل ألفية — للبطاقات البارزة (الرصيد).
/// مثال: 704.80 ⇒ "704.80 IQD"، 1250000 ⇒ "1,250,000 IQD".
String sasMoneyIqd(dynamic v) {
  final n = sasNum(v)?.toDouble();
  if (n == null) return '-';
  final text = n % 1 == 0 ? _iqdWhole.format(n) : _iqdFrac.format(n);
  return '$text IQD';
}

/// شرطة عند الفراغ.
String sasDash(dynamic v) => (v == null || '$v'.isEmpty) ? '-' : '$v';

/// رقم مالي مختصر (M/K) مع دعم النسب (%).
String sasMoneyShort(String key, dynamic v) {
  final n = sasNum(v)?.toDouble();
  if (n == null) return '$v';
  final k = key.toLowerCase();
  if (k.contains('rate') || k.contains('percent') || k.contains('ratio')) {
    return '${n.toStringAsFixed(1)}%';
  }
  if (n.abs() >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
  if (n.abs() >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n % 1 == 0 ? '${n.toInt()}' : n.toStringAsFixed(2);
}

/// وصول متداخل بمفتاح منقّط (user_details.username).
dynamic sasNested(Map<String, dynamic> row, String key) {
  dynamic cur = row;
  for (final part in key.split('.')) {
    if (cur is Map && cur.containsKey(part)) {
      cur = cur[part];
    } else {
      return null;
    }
  }
  return cur;
}

// ─────────────────────────── ودجات KPI/الصحّة ───────────────────────────

/// بطاقة KPI مالية صغيرة (أيقونة + قيمة مختصرة + عنوان).
class SasKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const SasKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 165.w,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1.2),
        boxShadow: SasUi.cardShadow(color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38.w,
            height: 38.w,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11.r),
            ),
            child: Icon(icon, color: color, size: 20.sp),
          ),
          SizedBox(height: 10.h),
          Text(
            value,
            style: GoogleFonts.cairo(
                fontSize: 20.sp, fontWeight: FontWeight.w900, color: color),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
                fontSize: 11.sp,
                color: Colors.grey[700],
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// شريط استخدام ملوّن (أخضر < 70% · برتقالي < 90% · أحمر).
class SasUsageBar extends StatelessWidget {
  final String label;
  final double percent; // 0–100
  final IconData icon;
  const SasUsageBar(
      {super.key,
      required this.label,
      required this.percent,
      required this.icon});

  Color get _color {
    if (percent < 70) return AppTheme.successColor;
    if (percent < 90) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  @override
  Widget build(BuildContext context) {
    final pct = percent.clamp(0.0, 100.0);
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18.sp, color: _color),
              SizedBox(width: 8.w),
              Text(label,
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700, fontSize: 13.sp)),
              const Spacer(),
              Text('${pct.toStringAsFixed(1)}%',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800,
                      color: _color,
                      fontSize: 13.sp)),
            ],
          ),
          SizedBox(height: 6.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(6.r),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 10.h,
              backgroundColor: _color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة حالة خدمة واحدة (يعمل/متوقّف).
class SasServiceCard extends StatelessWidget {
  final String name;
  final dynamic value;
  const SasServiceCard({super.key, required this.name, required this.value});

  bool get _isOk {
    final v = value;
    if (v is bool) return v;
    if (v is num) return v > 0;
    if (v is String) {
      final l = v.toLowerCase();
      return l == 'ok' ||
          l == 'up' ||
          l == 'running' ||
          l == 'active' ||
          l == 'true' ||
          l == '1';
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ok = _isOk;
    final color = ok ? AppTheme.successColor : AppTheme.errorColor;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 18.sp, color: color),
          SizedBox(width: 8.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name.replaceAll('_', ' '),
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700, fontSize: 12.5.sp)),
              Text(ok ? 'يعمل' : 'متوقّف',
                  style: GoogleFonts.cairo(
                      fontSize: 11.sp,
                      color: color,
                      fontWeight: FontWeight.w800)),
            ],
          ),
        ],
      ),
    );
  }
}

/// شارة إعلامية صغيرة (أيقونة + عنوان + قيمة) للجلسات ونحوها.
class SasInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  const SasInfoChip(
      {super.key,
      required this.icon,
      required this.label,
      required this.value,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.blueGrey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14.sp, color: c),
        SizedBox(width: 4.w),
        Text('$label: ',
            style: GoogleFonts.cairo(fontSize: 11.5.sp, color: Colors.grey[600])),
        Text(value,
            style: GoogleFonts.cairo(
                fontSize: 11.5.sp, fontWeight: FontWeight.w700)),
      ],
    );
  }
}
