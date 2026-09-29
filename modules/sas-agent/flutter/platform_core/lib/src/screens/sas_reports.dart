// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api/staff_api.dart';
import 'sas_aggregate_reports.dart';

/// عمود في جدول تقرير. `key` يدعم النقطة للوصول المتداخل (user_details.username).
class ReportCol {
  final String key;
  final String label;
  final String Function(dynamic v)? fmt;
  final bool numeric;
  const ReportCol(this.key, this.label, {this.fmt, this.numeric = false});
}

/// تعريف تقرير: عنوان + مسار SAS + أعمدة. `perUser` تعني أن المسار يلحق به /{userId}.
class ReportDef {
  final String title;
  final String path;
  final IconData icon;
  final List<ReportCol> cols;
  final bool perUser;
  const ReportDef(this.title, this.path, this.icon, this.cols, {this.perUser = false});
}

String _bytes(dynamic v) {
  final n = (v is num) ? v.toDouble() : double.tryParse('$v') ?? 0;
  if (n <= 0) return '-';
  if (n >= 1073741824) return '${(n / 1073741824).toStringAsFixed(2)} GB';
  if (n >= 1048576) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1024).toStringAsFixed(0)} KB';
}

String _money(dynamic v) => v == null ? '-' : 'IQD $v';
String _dash(dynamic v) => (v == null || '$v'.isEmpty) ? '-' : '$v';

/// كل التقارير العامّة (القائمة الجانبية) — مبنية على نقاط SAS الحقيقية المكتشَفة.
final List<ReportDef> kSasReports = [
  ReportDef('التفعيلات', 'index/activations', PhosphorIconsDuotone.lightning, [
    ReportCol('created_at', 'التاريخ'),
    ReportCol('user_details.username', 'المشترك'),
    ReportCol('user_details.firstname', 'الاسم'),
    ReportCol('manager_details.username', 'المدير'),
    ReportCol('profile_details.name', 'الباقة'),
    ReportCol('price', 'السعر', fmt: _money, numeric: true),
    ReportCol('activation_method', 'الطريقة'),
    ReportCol('old_expiration', 'الانتهاء السابق'),
    ReportCol('new_expiration', 'الانتهاء الجديد'),
  ]),
  ReportDef('الجلسات', 'index/UserSessions', PhosphorIconsDuotone.clockCounterClockwise, [
    ReportCol('acctstarttime', 'البدء'),
    ReportCol('acctstoptime', 'الانتهاء', fmt: (v) => v == null ? 'متصل الآن' : '$v'),
    ReportCol('username', 'المشترك'),
    ReportCol('framedipaddress', 'IP'),
    ReportCol('callingstationid', 'MAC'),
    ReportCol('acctoutputoctets', 'تحميل', fmt: _bytes, numeric: true),
    ReportCol('acctinputoctets', 'رفع', fmt: _bytes, numeric: true),
    ReportCol('acctterminatecause', 'سبب الإنهاء', fmt: _dash),
  ]),
  ReportDef('فواتير المشتركين', 'index/UserInvoices', PhosphorIconsDuotone.receipt, [
    ReportCol('invoice_number', 'رقم الفاتورة'),
    ReportCol('created_at', 'التاريخ'),
    ReportCol('user_details.username', 'المشترك'),
    ReportCol('type', 'النوع'),
    ReportCol('amount', 'المبلغ', fmt: _money, numeric: true),
    ReportCol('description', 'التفاصيل'),
    ReportCol('paid', 'مدفوع'),
  ]),
  ReportDef('فواتير المدراء', 'index/ManagerInvoices', PhosphorIconsDuotone.fileText, [
    ReportCol('invoice_number', 'رقم الفاتورة'),
    ReportCol('created_at', 'التاريخ'),
    ReportCol('description', 'التفاصيل'),
    ReportCol('amount', 'المبلغ', fmt: _money, numeric: true),
    ReportCol('payment_method', 'طريقة الدفع'),
    ReportCol('owner_details.username', 'المالك'),
  ]),
  ReportDef('السجل المالي', 'index/ManagerJournal', PhosphorIconsDuotone.book, [
    ReportCol('created_at', 'التاريخ'),
    ReportCol('operation', 'العملية'),
    ReportCol('amount', 'المبلغ', fmt: _money, numeric: true),
    ReportCol('balance', 'الرصيد', numeric: true),
    ReportCol('cr', 'دائن'),
    ReportCol('dr', 'مدين'),
  ]),
  ReportDef('إيصالات المدراء', 'index/ManagerReceipts', PhosphorIconsDuotone.receiptX, [
    ReportCol('receipt_number', 'رقم الإيصال'),
    ReportCol('created_at', 'التاريخ'),
    ReportCol('type', 'النوع'),
    ReportCol('amount', 'المبلغ', fmt: _money, numeric: true),
    ReportCol('description', 'التفاصيل'),
  ]),
  ReportDef('انتقال الأموال', 'report/depodrawal', PhosphorIconsDuotone.arrowsLeftRight, [
    ReportCol('created_at', 'التاريخ'),
    ReportCol('operation', 'العملية'),
    ReportCol('cr_manager', 'من'),
    ReportCol('dr_manager', 'إلى'),
    ReportCol('amount', 'المبلغ', fmt: _money, numeric: true),
    ReportCol('comment', 'ملاحظات', fmt: _dash),
  ]),
  ReportDef('سجل الديون', 'index/ManagerDebtsJournal', PhosphorIconsDuotone.scales, [
    ReportCol('created_at', 'التاريخ'),
    ReportCol('operation', 'العملية'),
    ReportCol('amount', 'المبلغ', fmt: _money, numeric: true),
    ReportCol('cr', 'دائن'),
    ReportCol('dr', 'مدين'),
  ]),
  ReportDef('محاولات الدخول', 'index/userauthlog', PhosphorIconsDuotone.signIn, [
    ReportCol('created_at', 'التاريخ'),
    ReportCol('username', 'المشترك'),
    ReportCol('reply', 'النتيجة'),
    ReportCol('mac', 'MAC', fmt: _dash),
    ReportCol('nas_ip_address', 'NAS', fmt: _dash),
  ]),
  ReportDef('سجل النظام', 'index/syslog', PhosphorIconsDuotone.terminalWindow, [
    ReportCol('created_at', 'التاريخ'),
    ReportCol('event', 'الحدث'),
    ReportCol('description', 'الوصف'),
    ReportCol('manager_details.username', 'المدير'),
    ReportCol('ip', 'IP'),
  ]),
];

// ───────────────────────── مركز التقارير (القائمة الجانبية) ─────────────────────────
class SasReportsHub extends StatelessWidget {
  final StaffApi api;
  final int cid;
  const SasReportsHub({super.key, required this.api, required this.cid});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(padding: const EdgeInsets.all(12), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Text('التقارير من نظام SAS — كل تقرير بصفحاته الكاملة.',
              style: tt.bodySmall?.copyWith(color: Colors.grey)),
        ),
        // تقارير تجميعية (ملخّصات/إحصائيات — شاشات مخصّصة)
        Card(
          child: ListTile(
            leading: Icon(PhosphorIconsDuotone.usersThree, color: Theme.of(context).colorScheme.primary),
            title: const Text('العملاء', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('ملخّص المشتركين: الإجمالي/النشط/المنتهي + حسب الباقة وحسب الوكيل الفرعي'),
            trailing: const Icon(PhosphorIconsBold.caretLeft, size: 16),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SasClientsReport(api: api, cid: cid))),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(PhosphorIconsDuotone.chartBar, color: Theme.of(context).colorScheme.primary),
            title: const Text('إحصائيات التفعيل', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('عدد التفعيلات لكل يوم في الشهر + الإجمالي'),
            trailing: const Icon(PhosphorIconsBold.caretLeft, size: 16),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SasActivationsStats(api: api, cid: cid))),
          ),
        ),
        for (final r in kSasReports)
          Card(
            child: ListTile(
              leading: Icon(r.icon, color: Theme.of(context).colorScheme.primary),
              title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(PhosphorIconsBold.caretLeft, size: 16),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SasReportScreen(api: api, cid: cid, def: r))),
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────── عارض تقرير مُرقّم (جدول) ─────────────────────────
class SasReportScreen extends StatefulWidget {
  final StaffApi api;
  final int cid;
  final ReportDef def;
  final int? userId;       // لتقارير المشترك (index/X/{id})
  const SasReportScreen({super.key, required this.api, required this.cid, required this.def, this.userId});

  @override
  State<SasReportScreen> createState() => _SasReportScreenState();
}

class _SasReportScreenState extends State<SasReportScreen> {
  List<Map<String, dynamic>> _rows = [];
  int _page = 1, _lastPage = 1, _total = 0;
  bool _loading = true;
  String? _error;

  String get _path => widget.userId != null ? '${widget.def.path}/${widget.userId}' : widget.def.path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // بلا sortBy موحّد — بعض الجداول (UserSessions) بلا عمود id فتفشل؛ SAS يرتّب افتراضياً بالأحدث.
      final r = await widget.api.sasPostList(widget.cid, _path,
          {'page': _page, 'count': 15, 'direction': 'desc', 'search': ''});
      final m = (r is Map) ? r : const {};
      final data = (m['data'] as List?) ?? const [];
      if (!mounted) return;
      int asInt(dynamic v, int d) => v is num ? v.toInt() : (int.tryParse('$v') ?? d);
      setState(() {
        _rows = data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _total = asInt(m['total'], _rows.length);
        _lastPage = asInt(m['last_page'], 1);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  dynamic _get(Map<String, dynamic> row, String key) {
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

  String _cell(Map<String, dynamic> row, ReportCol c) {
    final raw = _get(row, c.key);
    if (c.fmt != null) return c.fmt!(raw);
    return (raw == null || '$raw'.isEmpty) ? '-' : '$raw';
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.def;
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(def.title),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(22),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('الإجمالي: $_total', style: tt.bodySmall),
            ),
          ),
          actions: [
            IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _load,
                icon: const Icon(PhosphorIconsBold.arrowsClockwise)),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(20),
                    child: Text('تعذّر جلب التقرير: $_error',
                        style: TextStyle(color: Theme.of(context).colorScheme.error))))
                : _rows.isEmpty
                    ? const Center(child: Text('لا سجلّات في هذا التقرير'))
                    : Column(children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columnSpacing: 22,
                                headingRowHeight: 42,
                                dataRowMinHeight: 38,
                                dataRowMaxHeight: 52,
                                columns: [
                                  for (final c in def.cols)
                                    DataColumn(label: Text(c.label,
                                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                                        numeric: c.numeric),
                                ],
                                rows: [
                                  for (final row in _rows)
                                    DataRow(cells: [
                                      for (final c in def.cols)
                                        DataCell(Text(_cell(row, c),
                                            style: const TextStyle(fontSize: 12.5))),
                                    ]),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _pager(),
                      ]),
      ),
    );
  }

  Widget _pager() => Material(
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                onPressed: _page > 1 ? () { setState(() => _page--); _load(); } : null,
                icon: const Icon(PhosphorIconsBold.caretRight)),
            Text('صفحة $_page من $_lastPage'),
            IconButton(
                onPressed: _page < _lastPage ? () { setState(() => _page++); _load(); } : null,
                icon: const Icon(PhosphorIconsBold.caretLeft)),
          ]),
        ),
      );
}
