import 'package:flutter/material.dart';

import '../../frontend/frontend.dart';
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
    gradient: SdColors.orangeGradient,
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
    gradient: SdColors.greenGradient,
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
    gradient: SdColors.greenGradient,
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
    gradient: SdColors.orangeGradient,
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
    gradient: SdColors.orangeGradient,
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
                  gradient: SdColors.blueGradient,
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
        style: TextStyle(fontFamily: 'Cairo', fontSize: 12.sp, color: Colors.grey[600]),
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
                        style: TextStyle(fontFamily: 'Cairo', 
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A2E))),
                    if (subtitle != null) ...[
                      SizedBox(height: 2.h),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontFamily: 'Cairo', 
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

  // التفعيلات (عدد الشهر المختار) — مُصفّاة زمنياً بالشهر/السنة.
  int _activationsTotal = 0;
  String? _activationsError;
  bool _activationsLoading = false;
  // تفصيل يومي اختياري: (اليوم → العدد).
  List<MapEntry<int, int>> _activationsDaily = const [];

  // الشهر/السنة للتصفية الزمنية (تخصّ التفعيلات فقط).
  int _month = DateTime.now().month;
  int _year = DateTime.now().year;

  static const List<String> _arMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

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
      _fetchActivations(id),
    ]);

    if (mounted) setState(() => _loading = false);
  }

  /// جلب تفعيلات الشهر/السنة المختارين فقط عبر `report/activations`.
  /// الرد `Map` فيه `data` قائمة صفوف `{day, profile_id, total}`:
  ///  • `day==null && profile_id==null` → الإجمالي الكلي للشهر.
  ///  • `day!=null && profile_id==null` → إجمالي ذلك اليوم (تفصيل يومي).
  ///  • `profile_id!=null` → تفصيل باقات (يُهمَل هنا).
  Future<void> _fetchActivations(String id) {
    return _api.sasPost(id, 'report/activations', payload: {
      'type': 'daily',
      'month': _month,
      'year': _year,
      'manager_id': -1,
      'sub_managers': 'true',
      'activation_method': 'any',
    }).then((r) {
      final map = r is Map ? r : const {};
      final rows = map['data'] is List ? map['data'] as List : const [];
      int total = 0;
      final daily = <MapEntry<int, int>>[];
      for (final raw in rows) {
        if (raw is! Map) continue;
        final day = raw['day'];
        final profileId = raw['profile_id'];
        if (profileId != null) continue; // تفصيل باقات — يُهمَل.
        if (day == null) {
          total = sasInt(raw['total']); // الإجمالي الكلي للشهر.
        } else {
          daily.add(MapEntry(sasInt(day), sasInt(raw['total'])));
        }
      }
      daily.sort((a, b) => a.key.compareTo(b.key));
      _activationsTotal = total;
      _activationsDaily = daily;
    }).catchError((Object e) {
      _activationsError = _clean(e);
    });
  }

  /// إعادة تحميل التفعيلات فقط عند تغيّر الشهر/السنة (دون إعادة جلب اللقطات).
  Future<void> _loadActivations() async {
    setState(() {
      _activationsLoading = true;
      _activationsError = null;
    });
    await _fetchActivations(widget.account.id);
    if (mounted) setState(() => _activationsLoading = false);
  }

  void _shiftMonth(int delta) {
    var m = _month + delta;
    var y = _year;
    if (m < 1) {
      m = 12;
      y -= 1;
    } else if (m > 12) {
      m = 1;
      y += 1;
    }
    // لا نتجاوز الشهر الحالي.
    final now = DateTime.now();
    if (y > now.year || (y == now.year && m > now.month)) return;
    if (y < 2023) return;
    setState(() {
      _month = m;
      _year = y;
    });
    _loadActivations();
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
                          gradient: SdColors.greenGradient,
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
                          gradient: SdColors.orangeGradient,
                        ),
                        SizedBox(height: 10.h),
                        _distTable(_perManager, _managerError, nameKeys: const [
                          'manager_name',
                          'parent_id'
                        ], firstLabel: 'الوكيل الفرعي'),
                        SizedBox(height: 20.h),
                        SasSectionHeader(
                          title: 'التفعيلات',
                          icon: Icons.bolt_rounded,
                          gradient: SdColors.orangeGradient,
                          trailingText: '${_arMonths[_month - 1]} $_year',
                        ),
                        SizedBox(height: 10.h),
                        _activationsSection(),
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
            color: SdColors.primary,
            icon: Icons.people_rounded),
        SasStatCard(
            label: 'نشط',
            value: '$_active',
            color: SdColors.success,
            icon: Icons.check_circle_rounded),
        SasStatCard(
            label: 'منتهٍ',
            value: '$_expired',
            color: SdColors.danger,
            icon: Icons.cancel_rounded),
      ],
    );
  }

  /// قسم التفعيلات المُصفّى زمنياً: منتقي الشهر/السنة + إجمالي الشهر +
  /// تفصيل يومي اختياري. التصفية الزمنية تخصّ هذا القسم فقط.
  Widget _activationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _monthPicker(),
        SizedBox(height: 6.h),
        Text('ملاحظة: التصفية الزمنية تخصّ «التفعيلات» فقط.',
            style:
                TextStyle(fontFamily: 'Cairo', fontSize: 10.5.sp, color: Colors.grey[600])),
        SizedBox(height: 10.h),
        if (_activationsLoading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 18.h),
            child: Center(
              child: SizedBox(
                width: 24.w,
                height: 24.w,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: SdColors.primary),
              ),
            ),
          )
        else if (_activationsError != null)
          _inlineError(_activationsError!)
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: SasStatCard(
                label: 'إجمالي تفعيلات ${_arMonths[_month - 1]} $_year',
                value: '$_activationsTotal',
                color: SdColors.warning,
                icon: Icons.bolt_rounded),
          ),
          SizedBox(height: 10.h),
          if (_activationsDaily.isEmpty)
            _inlineEmpty('لا تفعيلات في هذا الشهر')
          else
            _dailyTable(),
        ],
      ],
    );
  }

  /// منتقي الشهر/السنة: أزرار سابق/تالٍ + قائمتان منسدلتان.
  Widget _monthPicker() {
    final now = DateTime.now();
    final years = [for (var y = 2023; y <= now.year; y++) y];
    final bool atCurrent = _year == now.year && _month == now.month;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: SasUi.card(),
      child: Row(
        children: [
          IconButton(
            tooltip: 'الشهر السابق',
            visualDensity: VisualDensity.compact,
            onPressed: _activationsLoading ? null : () => _shiftMonth(-1),
            icon: const Icon(Icons.chevron_right_rounded),
            color: SdColors.primary,
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _monthDropdown(),
                SizedBox(width: 8.w),
                _yearDropdown(years),
              ],
            ),
          ),
          IconButton(
            tooltip: 'الشهر التالي',
            visualDensity: VisualDensity.compact,
            onPressed:
                (_activationsLoading || atCurrent) ? null : () => _shiftMonth(1),
            icon: const Icon(Icons.chevron_left_rounded),
            color: atCurrent ? Colors.grey[350] : SdColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _monthDropdown() {
    final now = DateTime.now();
    return DropdownButton<int>(
      value: _month,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(10.r),
      style: TextStyle(fontFamily: 'Cairo', 
          fontSize: 12.5.sp,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A1A2E)),
      items: [
        for (var m = 1; m <= 12; m++)
          DropdownMenuItem(
            value: m,
            // تعطيل الأشهر المستقبلية ضمن السنة الحالية.
            enabled: !(_year == now.year && m > now.month),
            child: Text(_arMonths[m - 1]),
          ),
      ],
      onChanged: _activationsLoading
          ? null
          : (m) {
              if (m == null || m == _month) return;
              final n = DateTime.now();
              if (_year == n.year && m > n.month) return;
              setState(() => _month = m);
              _loadActivations();
            },
    );
  }

  Widget _yearDropdown(List<int> years) {
    final now = DateTime.now();
    return DropdownButton<int>(
      value: _year,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(10.r),
      style: TextStyle(fontFamily: 'Cairo', 
          fontSize: 12.5.sp,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF1A1A2E)),
      items: [
        for (final y in years)
          DropdownMenuItem(value: y, child: Text('$y')),
      ],
      onChanged: _activationsLoading
          ? null
          : (y) {
              if (y == null || y == _year) return;
              var m = _month;
              // إن أصبح الشهر مستقبلياً بعد تغيير السنة، ثبّته على الشهر الحالي.
              if (y == now.year && m > now.month) m = now.month;
              setState(() {
                _year = y;
                _month = m;
              });
              _loadActivations();
            },
    );
  }

  /// جدول التفصيل اليومي (اليوم → عدد التفعيلات).
  Widget _dailyTable() {
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
              SdColors.primary.withValues(alpha: 0.06)),
          headingTextStyle: TextStyle(fontFamily: 'Cairo', 
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              color: SdColors.primary),
          dataTextStyle:
              TextStyle(fontFamily: 'Cairo', fontSize: 12.sp, color: Colors.black87),
          columns: const [
            DataColumn(label: Text('اليوم')),
            DataColumn(label: Text('عدد التفعيلات'), numeric: true),
          ],
          rows: [
            for (final e in _activationsDaily)
              DataRow(cells: [
                DataCell(Text('${e.key} ${_arMonths[_month - 1]}')),
                DataCell(Text('${e.value}',
                    style: TextStyle(fontFamily: 'Cairo', 
                        color: SdColors.warning,
                        fontWeight: FontWeight.w700))),
              ]),
          ],
        ),
      ),
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
              SdColors.primary.withValues(alpha: 0.06)),
          headingTextStyle: TextStyle(fontFamily: 'Cairo', 
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              color: SdColors.primary),
          dataTextStyle:
              TextStyle(fontFamily: 'Cairo', fontSize: 12.sp, color: Colors.black87),
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
                    style: TextStyle(fontFamily: 'Cairo', 
                        color: SdColors.success,
                        fontWeight: FontWeight.w700))),
                DataCell(Text('${sasInt(row['expired'])}',
                    style: TextStyle(fontFamily: 'Cairo', 
                        color: SdColors.danger,
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
          color: SdColors.danger.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12.r),
          border:
              Border.all(color: SdColors.danger.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: SdColors.danger, size: 20.sp),
            SizedBox(width: 8.w),
            Expanded(
                child: Text(msg,
                    style: TextStyle(fontFamily: 'Cairo', 
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
                    style: TextStyle(fontFamily: 'Cairo', 
                        fontSize: 12.5.sp, color: Colors.grey[600]))),
          ],
        ),
      );
}

/// شريط علوي متدرّج موحّد لصفحات التقارير/الترخيص.
PreferredSizeWidget _bar(BuildContext context, String title,
    {VoidCallback? onRefresh}) {
  return SdAppBar(
    title: title,
    actions: [
      if (onRefresh != null)
        SdAppBarAction(
          icon: Icons.refresh_rounded,
          label: 'تحديث',
          onPressed: onRefresh,
        ),
    ],
  );
}
