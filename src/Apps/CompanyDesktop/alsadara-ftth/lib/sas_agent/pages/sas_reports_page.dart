import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_theme.dart';
import '../../utils/responsive_helper.dart';
import '../models/sas_account.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_format.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_report_table.dart';
import '../widgets/sas_state_views.dart';

/// التقارير العشرة الجاهزة من نظام الساس — كلٌّ عبر بروكسي `sasPost` بمسار
/// `index/*|report/*` المسموح. الأعمدة/المنسّقات مطابقة للمصدر (bytes/عملة).
final List<SasReportDef> kSasReports = [
  SasReportDef(
    title: 'التفعيلات',
    path: 'index/activations',
    icon: Icons.bolt_rounded,
    gradient: AppTheme.orangeGradient,
    cols: const [
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('user_details.username', 'المشترك'),
      SasReportCol('user_details.firstname', 'الاسم'),
      SasReportCol('manager_details.username', 'المدير'),
      SasReportCol('profile_details.name', 'الباقة'),
      SasReportCol('price', 'السعر', fmt: sasMoney, numeric: true),
      SasReportCol('activation_method', 'الطريقة'),
      SasReportCol('new_expiration', 'الانتهاء الجديد'),
    ],
  ),
  SasReportDef(
    title: 'الجلسات',
    path: 'index/sessions',
    icon: Icons.history_rounded,
    cols: const [
      SasReportCol('acctstarttime', 'البدء'),
      SasReportCol('acctstoptime', 'الانتهاء',
          fmt: _sessionEnd),
      SasReportCol('username', 'المشترك'),
      SasReportCol('framedipaddress', 'IP'),
      SasReportCol('callingstationid', 'MAC', fmt: sasDash),
      SasReportCol('acctoutputoctets', 'تنزيل', fmt: sasBytes, numeric: true),
      SasReportCol('acctinputoctets', 'رفع', fmt: sasBytes, numeric: true),
      SasReportCol('acctterminatecause', 'سبب الإنهاء', fmt: sasDash),
    ],
  ),
  SasReportDef(
    title: 'فواتير المشتركين',
    path: 'index/UserInvoices',
    icon: Icons.receipt_long_rounded,
    gradient: AppTheme.greenGradient,
    cols: const [
      SasReportCol('invoice_number', 'رقم الفاتورة'),
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('user_details.username', 'المشترك'),
      SasReportCol('type', 'النوع'),
      SasReportCol('amount', 'المبلغ', fmt: sasMoney, numeric: true),
      SasReportCol('description', 'التفاصيل'),
      SasReportCol('paid', 'مدفوع'),
    ],
  ),
  SasReportDef(
    title: 'فواتير المدراء',
    path: 'index/ManagerInvoices',
    icon: Icons.description_rounded,
    cols: const [
      SasReportCol('invoice_number', 'رقم الفاتورة'),
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('description', 'التفاصيل'),
      SasReportCol('amount', 'المبلغ', fmt: sasMoney, numeric: true),
      SasReportCol('payment_method', 'طريقة الدفع'),
      SasReportCol('owner_details.username', 'المالك'),
    ],
  ),
  SasReportDef(
    title: 'السجل المالي',
    path: 'index/ManagerJournal',
    icon: Icons.menu_book_rounded,
    gradient: AppTheme.greenGradient,
    cols: const [
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('operation', 'العملية'),
      SasReportCol('amount', 'المبلغ', fmt: sasMoney, numeric: true),
      SasReportCol('balance', 'الرصيد', numeric: true),
      SasReportCol('cr', 'دائن'),
      SasReportCol('dr', 'مدين'),
    ],
  ),
  SasReportDef(
    title: 'إيصالات المدراء',
    path: 'index/ManagerReceipts',
    icon: Icons.receipt_rounded,
    cols: const [
      SasReportCol('receipt_number', 'رقم الإيصال'),
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('type', 'النوع'),
      SasReportCol('amount', 'المبلغ', fmt: sasMoney, numeric: true),
      SasReportCol('description', 'التفاصيل'),
    ],
  ),
  SasReportDef(
    title: 'انتقال الأموال',
    path: 'report/depodrawal',
    icon: Icons.swap_horiz_rounded,
    gradient: AppTheme.orangeGradient,
    cols: const [
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('operation', 'العملية'),
      SasReportCol('cr_manager', 'من'),
      SasReportCol('dr_manager', 'إلى'),
      SasReportCol('amount', 'المبلغ', fmt: sasMoney, numeric: true),
      SasReportCol('comment', 'ملاحظات', fmt: sasDash),
    ],
  ),
  SasReportDef(
    title: 'سجل الديون',
    path: 'index/ManagerDebtsJournal',
    icon: Icons.balance_rounded,
    gradient: AppTheme.orangeGradient,
    cols: const [
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('operation', 'العملية'),
      SasReportCol('amount', 'المبلغ', fmt: sasMoney, numeric: true),
      SasReportCol('cr', 'دائن'),
      SasReportCol('dr', 'مدين'),
    ],
  ),
  SasReportDef(
    title: 'محاولات الدخول',
    path: 'index/userauthlog',
    icon: Icons.login_rounded,
    cols: const [
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('username', 'المشترك'),
      SasReportCol('reply', 'النتيجة'),
      SasReportCol('mac', 'MAC', fmt: sasDash),
      SasReportCol('nas_ip_address', 'NAS', fmt: sasDash),
    ],
  ),
  SasReportDef(
    title: 'سجل النظام',
    path: 'index/syslog',
    icon: Icons.terminal_rounded,
    cols: const [
      SasReportCol('created_at', 'التاريخ'),
      SasReportCol('event', 'الحدث'),
      SasReportCol('description', 'الوصف'),
      SasReportCol('manager_details.username', 'المدير'),
      SasReportCol('ip', 'IP'),
    ],
  ),
];

String _sessionEnd(dynamic v) => v == null ? 'متصل الآن' : '$v';

/// صفحة قائمة التقارير — تفتح كل تقرير بجدول مُرقّم، وتصل للتقارير المجمّعة.
class SasReportsPage extends StatelessWidget {
  final SasAccount account;
  const SasReportsPage({super.key, required this.account});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: _bar(context, 'التقارير'),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: context.responsive.maxContentWidth),
            child: ListView(
              padding: EdgeInsets.all(14.w),
              children: [
                _hint('تقارير نظام الساس للحساب «${account.displayName}» — كل '
                    'تقرير بصفحاته الكاملة وبحثه.'),
                SizedBox(height: 10.h),
                _tile(
                  context,
                  title: 'التقارير المجمّعة',
                  subtitle: 'ملخّص المشتركين + حسب الباقة + حسب المدير + التفعيلات',
                  icon: Icons.insights_rounded,
                  gradient: AppTheme.blueGradient,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SasAggregateReportsPage(account: account),
                  )),
                ),
                SizedBox(height: 8.h),
                for (final r in kSasReports) ...[
                  _tile(
                    context,
                    title: r.title,
                    subtitle: null,
                    icon: r.icon,
                    gradient: r.gradient,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _SingleReportScreen(
                          account: account, def: r),
                    )),
                  ),
                  SizedBox(height: 8.h),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(String text) => Text(
        text,
        style: GoogleFonts.cairo(fontSize: 12.sp, color: Colors.grey[600]),
      );

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
              const Icon(Icons.chevron_left_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

/// شاشة تقرير مفرد بجدول مُرقّم.
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
        appBar: _bar(context, def.title),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: context.responsive.maxContentWidth),
            child: SasReportTable(accountId: account.id, def: def),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── التقارير المجمّعة ───────────────────────────

/// التقارير المجمّعة (ملخّص/حسب الباقة/حسب المدير/التفعيلات اليومية) —
/// عبر `sasGet('usersReport/summary')` و`sasPost('usersReport/perProfile'|
/// 'perManager')` و`sasPost('index/activations')`.
class SasAggregateReportsPage extends StatefulWidget {
  final SasAccount account;
  const SasAggregateReportsPage({super.key, required this.account});

  @override
  State<SasAggregateReportsPage> createState() =>
      _SasAggregateReportsPageState();
}

class _SasAggregateReportsPageState extends State<SasAggregateReportsPage> {
  final _api = SasAgentApiService.instance;

  // الملخّص
  int _total = 0, _active = 0, _expired = 0;
  String? _summaryError;

  // حسب الباقة/المدير
  List<Map<String, dynamic>> _perProfile = const [];
  String? _profileError;
  List<Map<String, dynamic>> _perManager = const [];
  String? _managerError;

  // التفعيلات (عدد الشهر)
  int _activationsTotal = 0;
  String? _activationsError;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _summaryError = _profileError = _managerError = _activationsError = null;
    });
    final id = widget.account.id;

    await Future.wait([
      _api.sasGet(id, 'usersReport/summary').then((r) {
        final d = r is Map ? (r['data'] is Map ? r['data'] as Map : null) : null;
        _total = sasInt(d?['total']);
        _active = sasInt(d?['active']);
        _expired = sasInt(d?['expired']);
      }).catchError((Object e) {
        _summaryError = _clean(e);
      }),
      _api.sasPost(id, 'usersReport/perProfile').then((r) {
        _perProfile = sasExtractList(r);
      }).catchError((Object e) {
        _profileError = _clean(e);
      }),
      _api.sasGet(id, 'usersReport/perManager').then((r) {
        _perManager = sasExtractList(r);
      }).catchError((Object e) {
        _managerError = _clean(e);
      }),
      _api.sasPost(id, 'index/activations',
          payload: {'page': 1, 'count': 1}).then((r) {
        final map = r is Map ? r : const {};
        _activationsTotal = sasInt(map['total']);
      }).catchError((Object e) {
        _activationsError = _clean(e);
      }),
    ]);

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: _bar(context, 'التقارير المجمّعة', onRefresh: _loading ? null : _loadAll),
        body: _loading
            ? const SasLoadingView(message: 'جاري جلب التقارير المجمّعة…')
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxWidth: context.responsive.maxContentWidth),
                  child: RefreshIndicator(
                    onRefresh: _loadAll,
                    child: ListView(
                      padding: EdgeInsets.all(14.w),
                      children: [
                        const SasSectionHeader(
                          title: 'إجمالي المشتركين',
                          icon: Icons.groups_rounded,
                        ),
                        SizedBox(height: 10.h),
                        _summarySection(),
                        SizedBox(height: 20.h),
                        const SasSectionHeader(
                          title: 'توزيع الباقات',
                          icon: Icons.inventory_2_rounded,
                          gradient: AppTheme.greenGradient,
                        ),
                        SizedBox(height: 10.h),
                        _distTable(_perProfile, _profileError, nameKeys: const [
                          'profile_name',
                          'profile_id'
                        ], firstLabel: 'الباقة'),
                        SizedBox(height: 20.h),
                        const SasSectionHeader(
                          title: 'توزيع الوكلاء الفرعيين',
                          icon: Icons.account_tree_rounded,
                          gradient: AppTheme.orangeGradient,
                        ),
                        SizedBox(height: 10.h),
                        _distTable(_perManager, _managerError, nameKeys: const [
                          'manager_name',
                          'parent_id'
                        ], firstLabel: 'الوكيل الفرعي'),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _summarySection() {
    if (_summaryError != null) return _inlineError(_summaryError!);
    return Wrap(
      spacing: 10.w,
      runSpacing: 10.h,
      children: [
        SasStatCard(
            label: 'الإجمالي',
            value: '$_total',
            color: AppTheme.primaryColor,
            icon: Icons.people_rounded),
        SasStatCard(
            label: 'نشط',
            value: '$_active',
            color: AppTheme.successColor,
            icon: Icons.check_circle_rounded),
        SasStatCard(
            label: 'منتهٍ',
            value: '$_expired',
            color: AppTheme.errorColor,
            icon: Icons.cancel_rounded),
        SasStatCard(
            label: 'تفعيلات الشهر',
            value: _activationsError != null ? '-' : '$_activationsTotal',
            color: AppTheme.warningColor,
            icon: Icons.bolt_rounded),
      ],
    );
  }

  Widget _distTable(
    List<Map<String, dynamic>> rows,
    String? error, {
    required List<String> nameKeys,
    required String firstLabel,
  }) {
    if (error != null) return _inlineError(error);
    if (rows.isEmpty) {
      return _inlineEmpty('لا بيانات لعرضها');
    }
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 26,
          headingRowHeight: 44,
          dataRowMinHeight: 38,
          dataRowMaxHeight: 48,
          headingRowColor: WidgetStatePropertyAll(
              AppTheme.primaryColor.withValues(alpha: 0.06)),
          headingTextStyle: GoogleFonts.cairo(
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              color: AppTheme.primaryColor),
          dataTextStyle:
              GoogleFonts.cairo(fontSize: 12.sp, color: Colors.black87),
          columns: [
            DataColumn(label: Text(firstLabel)),
            const DataColumn(label: Text('الكلي'), numeric: true),
            const DataColumn(label: Text('نشط'), numeric: true),
            const DataColumn(label: Text('منتهٍ'), numeric: true),
          ],
          rows: [
            for (final row in rows)
              DataRow(cells: [
                DataCell(Text(_firstNonEmpty(row, nameKeys))),
                DataCell(Text('${sasInt(row['c'])}')),
                DataCell(Text('${sasInt(row['active'])}',
                    style: GoogleFonts.cairo(
                        color: AppTheme.successColor,
                        fontWeight: FontWeight.w700))),
                DataCell(Text('${sasInt(row['expired'])}',
                    style: GoogleFonts.cairo(
                        color: AppTheme.errorColor,
                        fontWeight: FontWeight.w700))),
              ]),
          ],
        ),
      ),
    );
  }

  String _firstNonEmpty(Map<String, dynamic> row, List<String> keys) {
    for (final k in keys) {
      final v = row[k];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return '-';
  }

  Widget _inlineError(String msg) => Container(
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: AppTheme.errorColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12.r),
          border:
              Border.all(color: AppTheme.errorColor.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: AppTheme.errorColor, size: 20.sp),
            SizedBox(width: 8.w),
            Expanded(
                child: Text(msg,
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp, color: Colors.grey[800]))),
          ],
        ),
      );

  Widget _inlineEmpty(String msg) => Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.20)),
        ),
        child: Row(
          children: [
            Icon(Icons.inbox_rounded, color: Colors.grey[400], size: 20.sp),
            SizedBox(width: 8.w),
            Expanded(
                child: Text(msg,
                    style: GoogleFonts.cairo(
                        fontSize: 12.5.sp, color: Colors.grey[600]))),
          ],
        ),
      );
}

/// شريط علوي متدرّج موحّد لصفحات التقارير/الترخيص.
PreferredSizeWidget _bar(BuildContext context, String title,
    {VoidCallback? onRefresh}) {
  return AppBar(
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
    title: Text(title,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 17)),
    actions: [
      if (onRefresh != null)
        IconButton(
            onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded)),
    ],
  );
}
