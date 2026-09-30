import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../services/sas_agent_api_service.dart';
import 'sas_format.dart';
import 'sas_metrics.dart';
import 'sas_state_views.dart';

/// تعريف عمود جدول تقرير. `key` يدعم النقطة للوصول المتداخل.
class SasReportCol {
  final String key;
  final String label;
  final String Function(dynamic v)? fmt;
  final bool numeric;
  const SasReportCol(this.key, this.label, {this.fmt, this.numeric = false});
}

/// تعريف تقرير: عنوان + أيقونة + مسار ساس (index/*|report/*) + أعمدة.
class SasReportDef {
  final String title;
  final String path;
  final IconData icon;
  final List<SasReportCol> cols;
  final List<Color> gradient;

  const SasReportDef({
    required this.title,
    required this.path,
    required this.icon,
    required this.cols,
    this.gradient = AppTheme.blueGradient,
  });
}

/// عارض تقرير ساس مُرقّم بجدول — يجلب عبر [SasAgentApiService.sasPost] بمسار
/// [SasReportDef.path] مع ترقيم/بحث/اتجاه. يُعالج تحديد الحقن (whitelist) في
/// الخادم عبر عرض حالة خطأ واضحة وزر إعادة.
///
/// يعمل داخل بطاقة الصدارة الفخمة، ويحصر عرض الجدول بتمرير أفقي آمن.
class SasReportTable extends StatefulWidget {
  final String accountId;
  final SasReportDef def;

  /// حمولة إضافية ثابتة تُدمج مع {page,count,search,direction} (لتقارير خاصّة).
  final Map<String, dynamic> extraPayload;

  /// إظهار حقل البحث العلوي.
  final bool searchable;

  const SasReportTable({
    super.key,
    required this.accountId,
    required this.def,
    this.extraPayload = const {},
    this.searchable = true,
  });

  @override
  State<SasReportTable> createState() => _SasReportTableState();
}

class _SasReportTableState extends State<SasReportTable> {
  final _api = SasAgentApiService.instance;
  final _searchCtl = TextEditingController();

  List<Map<String, dynamic>> _rows = const [];
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loading = true;
  bool _forbidden = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  bool _isForbidden(String msg) {
    final m = msg.toLowerCase();
    return m.contains('403') ||
        m.contains('forbidden') ||
        m.contains('غير مصرّح') ||
        m.contains('غير مصرح');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _forbidden = false;
    });
    try {
      final res = await _api.sasPost(widget.accountId, widget.def.path, payload: {
        'page': _page,
        'count': 15,
        'direction': 'desc',
        'search': _searchCtl.text.trim(),
        ...widget.extraPayload,
      });
      final map = res is Map ? res : const {};
      final data = (map['data'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _rows = data
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _total = sasInt(map['total'], _rows.length);
        _lastPage = sasInt(map['last_page'], 1);
        _loading = false;
      });
    } catch (e) {
      final msg = _clean(e);
      if (mounted) {
        setState(() {
          _error = msg;
          _forbidden = _isForbidden(msg);
          _loading = false;
        });
      }
    }
  }

  String _cell(Map<String, dynamic> row, SasReportCol c) {
    final raw = sasNested(row, c.key);
    if (c.fmt != null) return c.fmt!(raw);
    return (raw == null || '$raw'.isEmpty) ? '-' : '$raw';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.searchable) _searchBar(),
        Expanded(child: _body()),
        if (!_loading && _error == null && _rows.isNotEmpty) _pager(),
      ],
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 8.h),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                _page = 1;
                _load();
              },
              style: GoogleFonts.cairo(fontSize: 13.sp),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'بحث…',
                hintStyle: GoogleFonts.cairo(fontSize: 12.5.sp),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          IconButton.filledTonal(
            onPressed: _loading
                ? null
                : () {
                    _page = 1;
                    _load();
                  },
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const SasLoadingView(message: 'جاري جلب التقرير…');
    if (_forbidden) {
      return SasEmptyView(
        message: 'هذا التقرير غير متاح لحسابك (محجوب من نظام الساس).',
        icon: Icons.lock_outline_rounded,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
        ),
      );
    }
    if (_error != null) return SasErrorView(message: _error!, onRetry: _load);
    if (_rows.isEmpty) {
      return SasEmptyView(
        message: 'لا سجلّات في هذا التقرير',
        icon: widget.def.icon,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: Text('تحديث', style: GoogleFonts.cairo()),
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 8.h),
      child: Container(
        decoration: SasUi.card(),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 22,
            headingRowHeight: 44,
            dataRowMinHeight: 38,
            dataRowMaxHeight: 54,
            headingRowColor: WidgetStatePropertyAll(
                AppTheme.primaryColor.withValues(alpha: 0.06)),
            headingTextStyle: GoogleFonts.cairo(
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryColor),
            dataTextStyle:
                GoogleFonts.cairo(fontSize: 12.sp, color: Colors.black87),
            columns: [
              for (final c in widget.def.cols)
                DataColumn(label: Text(c.label), numeric: c.numeric),
            ],
            rows: [
              for (final row in _rows)
                DataRow(cells: [
                  for (final c in widget.def.cols)
                    DataCell(Text(_cell(row, c))),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pager() {
    return Material(
      elevation: 6,
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _page > 1
                  ? () {
                      _page--;
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            Text('صفحة $_page من $_lastPage · الإجمالي $_total',
                style: GoogleFonts.cairo(
                    fontSize: 12.5.sp, fontWeight: FontWeight.w700)),
            IconButton(
              onPressed: _page < _lastPage
                  ? () {
                      _page++;
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
