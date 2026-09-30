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
          Text(
            'التصريح الشهري — ${widget.account.displayName}',
            style: GoogleFonts.cairo(
                fontSize: 16.sp, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 12.h),
          if (scalars.isNotEmpty) _summaryCard(scalars),
          for (final entry in tables.entries) ...[
            SizedBox(height: 16.h),
            _tableSection(entry.key, entry.value),
          ],
        ],
      ),
    );
  }

  Widget _summaryCard(List<MapEntry<String, dynamic>> scalars) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          for (final e in scalars)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      e.key,
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
                      '${e.value}',
                      textAlign: TextAlign.end,
                      style: GoogleFonts.cairo(
                          fontSize: 13.sp, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
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
        Row(
          children: [
            Icon(Icons.table_rows_rounded,
                size: 18.sp, color: AppTheme.primaryColor),
            SizedBox(width: 8.w),
            Text(
              title,
              style: GoogleFonts.cairo(
                fontSize: 14.sp,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryColor,
              ),
            ),
            SizedBox(width: 6.w),
            Text('(${rows.length})',
                style: GoogleFonts.cairo(
                    fontSize: 12.sp, color: Colors.grey[600])),
          ],
        ),
        SizedBox(height: 8.h),
        if (columns.isEmpty)
          Text('لا أعمدة قابلة للعرض',
              style: GoogleFonts.cairo(
                  fontSize: 12.sp, color: Colors.grey[500]))
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.22)),
            ),
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
