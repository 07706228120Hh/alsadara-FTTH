import 'package:flutter/material.dart';

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../models/sas_account.dart';
import '../widgets/sas_report_table.dart';
import '../widgets/sas_state_views.dart';
import 'sas_debtors_page.dart';
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
    return SasContentWrap(
      maxWidth: 1180,
      child: LayoutBuilder(
        builder: (context, c) {
          // شبكة بطاقات تكيّفية: عمود واحد على الضيّق وعمودان على العريض.
          final cols = c.maxWidth >= 720 ? 2 : 1;
          final summaryTiles = <Widget>[
            _tile(
              context,
              title: 'التقارير المجمّعة',
              subtitle:
                  'ملخّص المشتركين + حسب الباقة + حسب المدير + تفعيلات الشهر',
              icon: Icons.insights_rounded,
              tone: SdGroup.admin.tone,
              onTap: () =>
                  _open(context, SasAggregateReportsPage(account: account)),
            ),
            _tile(
              context,
              title: 'سجل الحركات',
              subtitle:
                  'العمليات المفوترة (تفعيل/تمديد/تغيير باقة) + المبالغ المحصّلة',
              icon: Icons.receipt_long_rounded,
              tone: SdStatus.success.tone,
              onTap: () => _open(context, SasTransactionsPage(account: account)),
            ),
            _tile(
              context,
              title: 'المدينون (ذمم المواطنين)',
              subtitle:
                  'المشتركون المدينون بالآجل + الرصيد المستحق · كشف وتسديد',
              icon: Icons.account_balance_wallet_rounded,
              tone: SdStatus.danger.tone,
              onTap: () => _open(context, SasDebtorsPage(account: account)),
            ),
            _tile(
              context,
              title: 'الترخيص والصلاحيات',
              subtitle: 'حالة الترخيص · الانتهاء · الإصدار · الميزات المفعّلة',
              icon: Icons.verified_user_rounded,
              tone: SdStatus.warning.tone,
              onTap: () => _open(context, SasLicensePage(account: account)),
            ),
          ];
          final detailTiles = [
            for (final r in kSasReports)
              _tile(
                context,
                title: r.title,
                subtitle: null,
                icon: r.icon,
                tone: SdGroup.platform.tone,
                onTap: () => _open(
                  context,
                  _SingleReportScreen(account: account, def: r),
                ),
              ),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
            children: [
              _banner(),
              const SizedBox(height: SdSpace.md),
              const SdSectionHeader(title: 'ملخّصات'),
              const SizedBox(height: SdSpace.xs),
              _grid(summaryTiles, cols),
              const SizedBox(height: SdSpace.lg),
              SdSectionHeader(
                  title: 'التقارير التفصيلية', tone: SdGroup.field.tone),
              const SizedBox(height: SdSpace.xs),
              _grid(detailTiles, cols),
            ],
          );
        },
      ),
    );
  }

  /// يرتّب بطاقات التقارير في شبكة بعدد أعمدة [cols] بفراغات متساوية.
  Widget _grid(List<Widget> tiles, int cols) {
    if (cols == 1) {
      return Column(
        children: [
          for (int i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(height: SdSpace.xs),
            tiles[i],
          ],
        ],
      );
    }
    final rows = <Widget>[];
    for (int i = 0; i < tiles.length; i += cols) {
      final cells = <Widget>[];
      for (int j = 0; j < cols; j++) {
        final idx = i + j;
        if (j > 0) cells.add(const SizedBox(width: SdSpace.xs));
        cells.add(Expanded(
          child: idx < tiles.length ? tiles[idx] : const SizedBox.shrink(),
        ));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: SdSpace.xs));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ));
    }
    return Column(children: rows);
  }

  Widget _banner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [SdColors.primaryMid, SdColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(SdRadius.lg),
        boxShadow: [
          BoxShadow(color: SdColors.primaryEdge, offset: const Offset(0, 5)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: const Icon(Icons.bar_chart_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('التقارير',
                    style: TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                  'تقارير نظام الساس للحساب «${account.displayName}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: SdText.family,
                    fontSize: 11.5,
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
    required SdTone tone,
    required VoidCallback onTap,
  }) {
    return SdRaised(
      onTap: onTap,
      radius: SdRadius.lg,
      padding: const EdgeInsets.all(12),
      semanticLabel: title,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tone.tint,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: tone.tintEdge, offset: const Offset(0, 3))
              ],
            ),
            child: Icon(icon, color: tone.base, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: SdText.label),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SdText.caption),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_left_rounded,
              color: SdColors.faint, size: 20),
        ],
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
    return SdPage(
      maxWidth: SdSpace.contentMax,
      scrollable: false,
      padding: EdgeInsets.zero,
      appBar: SdAppBar(title: def.title),
      body: SasReportTable(accountId: account.id, def: def),
    );
  }
}
