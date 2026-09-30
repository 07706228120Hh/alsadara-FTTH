import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';

/// تبويب «تصريح/بلنك» — يعرض تقرير الوكيل من `GET /accounts/{id}/report`
/// بشكل مقروء (ملخّص علوي + جدول صفوف + قيم مفردة).
class SasReportTab extends StatefulWidget {
  final SasAccount account;
  const SasReportTab({super.key, required this.account});

  @override
  State<SasReportTab> createState() => _SasReportTabState();
}

class _SasReportTabState extends State<SasReportTab> {
  final _api = SasAgentApiService.instance;

  Map<String, dynamic>? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SasReportTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) _load();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.getReport(widget.account.id);
      if (mounted) setState(() => _report = r);
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SasLoadingView(message: 'جاري جلب التصريح…');
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);

    final report = _report ?? const {};
    // استخرج الأقسام: قيم مفردة (scalars) + قوائم صفوف (rows).
    final scalars = <MapEntry<String, dynamic>>[];
    final tables = <String, List<Map<String, dynamic>>>{};

    report.forEach((key, value) {
      if (value is List) {
        final rows = value
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        if (rows.isNotEmpty) tables[key] = rows;
      } else if (value is Map) {
        value.forEach((k, v) {
          if (v is! Map && v is! List) {
            scalars.add(MapEntry('$key.$k', v));
          }
        });
      } else {
        scalars.add(MapEntry(key, value));
      }
    });

    if (scalars.isEmpty && tables.isEmpty) {
      return SasEmptyView(
        message: 'لا يتوفّر تصريح لهذا الحساب بعد',
        icon: Icons.assignment_outlined,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('تحديث', style: GoogleFonts.cairo()),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(14.w),
        children: [
          _reportBanner(),
          SizedBox(height: 16.h),
          if (scalars.isNotEmpty) ...[
            const SasSectionHeader(
              title: 'ملخّص التصريح',
              icon: Icons.summarize_rounded,
              gradient: AppTheme.orangeGradient,
            ),
            SizedBox(height: 10.h),
            _summaryCard(scalars),
          ],
          for (final entry in tables.entries) ...[
            SizedBox(height: 18.h),
            _tableSection(entry.key, entry.value),
          ],
        ],
      ),
    );
  }

  /// شريط علوي متدرّج بعنوان التصريح واسم الحساب.
  Widget _reportBanner() {
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
            child: Icon(Icons.assignment_rounded,
                color: Colors.white, size: 24.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'التصريح الشهري',
                  style: GoogleFonts.cairo(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  widget.account.displayName,
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

  Widget _summaryCard(List<MapEntry<String, dynamic>> scalars) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      decoration: SasUi.card(),
      child: Column(
        children: [
          for (int i = 0; i < scalars.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.grey.withValues(alpha: 0.10)),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      scalars[i].key,
                      style: GoogleFonts.cairo(
                        fontSize: 12.5.sp,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '${scalars[i].value}',
                      textAlign: TextAlign.end,
                      style: GoogleFonts.cairo(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.primaryColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tableSection(String title, List<Map<String, dynamic>> rows) {
    // اجمع أعمدة موحّدة من أول صف (مفاتيح scalar فقط).
    final columns = rows.first.entries
        .where((e) => e.value is! Map && e.value is! List)
        .map((e) => e.key)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SasSectionHeader(
          title: title,
          icon: Icons.table_rows_rounded,
          trailingText: '${rows.length}',
        ),
        SizedBox(height: 10.h),
        if (columns.isEmpty)
          Text('لا أعمدة قابلة للعرض',
              style: GoogleFonts.cairo(
                  fontSize: 12.sp, color: Colors.grey[500]))
        else
          Container(
            decoration: SasUi.card(),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                    AppTheme.primaryColor.withValues(alpha: 0.06)),
                headingTextStyle: GoogleFonts.cairo(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryColor),
                dataTextStyle:
                    GoogleFonts.cairo(fontSize: 12.sp, color: Colors.black87),
                columns: [
                  for (final c in columns) DataColumn(label: Text(c)),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        for (final c in columns)
                          DataCell(Text('${row[c] ?? '-'}')),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
