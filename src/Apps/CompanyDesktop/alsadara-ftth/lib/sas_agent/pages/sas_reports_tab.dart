import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_report_table.dart';
import '../widgets/sas_state_views.dart';
import 'sas_license_page.dart';
import 'sas_reports_page.dart' show kSasReports, SasAggregateReportsPage;
import 'sas_transactions_page.dart';

/// تبويب «التقارير» — يرقّي التقارير من زرٍّ داخل «نظام الساس» إلى تبويب مستقل
/// مطابقةً لتطبيق الوكلاء المرجعي. يعرض:
///  • التقارير المجمّعة (ملخّص + حسب الباقة + حسب المدير + تفعيلات الشهر).
///  • التقارير العشرة الجاهزة من نظام الساس (كلّ منها بجدول مُرقّم قابل للبحث).
///  • الترخيص والصلاحيات (auth) كمدخل ضمن التقارير.
///
/// يعمل على الحساب المحدّد فقط؛ كلّ تقرير يُفتح بصفحته الكاملة بحالات
/// تحميل/خطأ/فراغ عبر [SasReportTable].
class SasReportsTab extends StatelessWidget {
  final SasAccount account;
  const SasReportsTab({super.key, required this.account});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
      children: [
        _banner(),
        SizedBox(height: 16.h),

        // التقارير المجمّعة + الترخيص (بطاقات بارزة).
        const SasSectionHeader(
          title: 'ملخّصات',
          icon: Icons.insights_rounded,
        ),
        SizedBox(height: 10.h),
        _tile(
          context,
          title: 'التقارير المجمّعة',
          subtitle: 'ملخّص المشتركين + حسب الباقة + حسب المدير + تفعيلات الشهر',
          icon: Icons.insights_rounded,
          gradient: AppTheme.blueGradient,
          onTap: () =>
              _open(context, SasAggregateReportsPage(account: account)),
        ),
        SizedBox(height: 8.h),
        _tile(
          context,
          title: 'سجل الحركات',
          subtitle: 'العمليات المفوترة (تفعيل/تمديد/تغيير باقة) + المبالغ المحصّلة',
          icon: Icons.receipt_long_rounded,
          gradient: AppTheme.greenGradient,
          onTap: () => _open(context, SasTransactionsPage(account: account)),
        ),
        SizedBox(height: 8.h),
        _tile(
          context,
          title: 'الترخيص والصلاحيات',
          subtitle: 'حالة الترخيص · الانتهاء · الإصدار · الميزات المفعّلة',
          icon: Icons.verified_user_rounded,
          gradient: AppTheme.orangeGradient,
          onTap: () => _open(context, SasLicensePage(account: account)),
        ),

        SizedBox(height: 20.h),

        // التقارير التفصيلية العشرة.
        const SasSectionHeader(
          title: 'التقارير التفصيلية',
          icon: Icons.table_chart_rounded,
          gradient: AppTheme.greenGradient,
        ),
        SizedBox(height: 10.h),
        for (final r in kSasReports) ...[
          _tile(
            context,
            title: r.title,
            subtitle: null,
            icon: r.icon,
            gradient: r.gradient,
            onTap: () => _open(
              context,
              _SingleReportScreen(account: account, def: r),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ],
    );
  }

  Widget _banner() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppTheme.blueGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        boxShadow: SasUi.cardShadow(AppTheme.primaryColor),
      ),
      child: Row(
        children: [
          Container(
            width: 46.w,
            height: 46.w,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child:
                Icon(Icons.bar_chart_rounded, color: Colors.white, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'التقارير',
                  style: GoogleFonts.cairo(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'تقارير نظام الساس للحساب «${account.displayName}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 11.5.sp,
                    color: Colors.white.withValues(alpha: 0.80),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(SasUi.radius.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(SasUi.radius.r),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.all(12.w),
          decoration: SasUi.card(),
          child: Row(
            children: [
              SasUi.gradientBadge(
                  icon: icon, colors: gradient, size: 42, iconSize: 21),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.cairo(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A2E))),
                    if (subtitle != null) ...[
                      SizedBox(height: 2.h),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                              fontSize: 11.sp, color: Colors.grey[600])),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded,
                  color: Colors.grey[400], size: 20.sp),
            ],
          ),
        ),
      ),
    );
  }
}

/// شاشة تقرير مفرد بجدول مُرقّم — نسخة تبويب التقارير (مطابقة لنظيرتها في
/// `sas_reports_page.dart` لكنها معزولة هنا لتجنّب الاعتماد على رمز خاص).
class _SingleReportScreen extends StatelessWidget {
  final SasAccount account;
  final SasReportDef def;
  const _SingleReportScreen({required this.account, required this.def});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          toolbarHeight: 56,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          title: Text(def.title,
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 17)),
        ),
        body: SasReportTable(accountId: account.id, def: def),
      ),
    );
  }
}
