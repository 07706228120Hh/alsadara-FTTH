import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_billing_post_actions.dart';
import '../widgets/sas_citizen_statement.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_state_views.dart';
import 'sas_subscriber_form_page.dart';

/// تحويل آمن لرقم — نظام الساس يُعيد حقولاً عددية كنصوص أحياناً.
num? _asNum(dynamic v) =>
    v is num ? v : (v == null ? null : num.tryParse(v.toString()));

/// شاشة تفاصيل مشترك ساس الكاملة بثيم الصدارة.
///
/// تعرض: بطاقة ترويسة (اسم/حالة/رصيد/انتهاء) + شريط إجراءات (تفعيل/تمديد/تغيير
/// باقة/إضافة ترافيك/إيداع/سحب/إعادة تسمية/تعديل/حذف/استرداد/Ping) + بطاقات حقول
/// (هوية/تواصل/اشتراك/شبكة/تواريخ) + تبويبات فرعية (السجل/الجلسات/الفواتير/
/// الإيصالات/القيود/الحصص/الترافيك).
///
/// ⚠️ لا تُعرَض/تُطبَع أي كلمة مرور. العمليات المالية والحذف تتطلّب تأكيداً.
class SasSubscriberDetailPage extends StatefulWidget {
  final SasAccount account;

  /// معرّف المشترك في نظام الساس.
  final String userId;

  /// اسم المستخدم الأوّلي (من القائمة) يُعرض أثناء التحميل.
  final String? username;

  const SasSubscriberDetailPage({
    super.key,
    required this.account,
    required this.userId,
    this.username,
  });

  @override
  State<SasSubscriberDetailPage> createState() =>
      _SasSubscriberDetailPageState();
}

class _SasSubscriberDetailPageState extends State<SasSubscriberDetailPage>
    with SingleTickerProviderStateMixin {
  final _api = SasAgentApiService.instance;

  String get _aid => widget.account.id;
  String get _uid => widget.userId;

  Map<String, dynamic>? _detail;
  Map<String, dynamic>? _overview;
  String? _loadError;
  bool _loadingMain = true;
  bool _busy = false;

  late final TabController _innerTabs;

  @override
  void initState() {
    super.initState();
    _innerTabs = TabController(length: 9, vsync: this);
    _loadMain();
  }

  @override
  void dispose() {
    _innerTabs.dispose();
    super.dispose();
  }

  // ─── جلب التفاصيل الرئيسية ───

  Future<void> _loadMain() async {
    setState(() {
      _loadingMain = true;
      _loadError = null;
    });
    try {
      final detail = await _api.getUserDetail(_aid, _uid);
      Map<String, dynamic>? overview;
      try {
        overview = await _api.getUserOverview(_aid, _uid);
      } catch (_) {
        // النظرة العامة اختيارية — لا نُفشل الشاشة لو تعذّرت.
      }
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _overview = overview;
        _loadingMain = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString().replaceFirst('Exception: ', '').trim();
        _loadingMain = false;
      });
    }
  }

  // ─── تشغيل إجراء موحّد مع رسالة نجاح/فشل + إعادة تحميل ───

  Future<void> _run(Future<dynamic> Function() call, String okMsg) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      String msg = okMsg;
      if (res is Map) {
        final m = res['message'] ?? res['status'];
        if (m != null && '$m'.trim().isNotEmpty) msg = '$m';
      }
      if (mounted) {
        _toast('تم: $msg');
        await _loadMain();
      }
    } catch (e) {
      if (mounted) {
        _toast('فشل: ${e.toString().replaceFirst('Exception: ', '').trim()}',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor:
            isError ? AppTheme.errorColor : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── الواجهة ───

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            widget.username ?? d?['username']?.toString() ?? 'تفاصيل المشترك',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w800, color: Colors.white),
          ),
          actions: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(left: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.white),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loadMain,
              ),
          ],
        ),
        body: _loadingMain
            ? const SasLoadingView(message: 'جاري جلب بيانات المشترك…')
            : (_loadError != null && d == null)
                ? SasErrorView(message: _loadError!, onRetry: _loadMain)
                : _buildBody(d!),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> d) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: ListView(
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 24.h),
          children: [
            _headerCard(d),
            SizedBox(height: 12.h),
            _actionBar(),
            SizedBox(height: 12.h),
            _fieldCards(d),
            SizedBox(height: 12.h),
            _innerTabsCard(),
          ],
        ),
      ),
    );
  }

  // ─── بطاقة الترويسة ───

  Widget _headerCard(Map<String, dynamic> d) {
    final ov = _overview;
    final username =
        (d['username'] ?? widget.username ?? '—').toString();
    final fullName =
        '${d['firstname'] ?? ''} ${d['lastname'] ?? ''}'.trim();
    final statusRaw = d['status'] ?? ov?['status'];
    final statusLabel = _statusLabel(statusRaw);
    final statusColor = _statusColor(statusRaw);
    final balance =
        (ov?['balance'] ?? d['balance'])?.toString() ?? '—';
    final expiration = (d['expiration'] ?? '—').toString();
    final parent =
        (ov?['parent_username'] ?? d['parent_username'] ?? d['parent_id'])
                ?.toString() ??
            '—';

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54.w,
                height: 54.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      statusColor.withValues(alpha: 0.20),
                      statusColor.withValues(alpha: 0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: statusColor.withValues(alpha: 0.28)),
                ),
                child: Icon(Icons.person_rounded,
                    color: statusColor, size: 27.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        username,
                        style: GoogleFonts.robotoMono(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A1A2E)),
                      ),
                    ),
                    if (fullName.isNotEmpty) ...[
                      SizedBox(height: 2.h),
                      Text(fullName,
                          style: GoogleFonts.cairo(
                              fontSize: 12.5.sp,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500)),
                    ],
                  ],
                ),
              ),
              SasStatusBadge(label: statusLabel, color: statusColor),
            ],
          ),
          SizedBox(height: 14.h),
          Wrap(
            spacing: 18.w,
            runSpacing: 8.h,
            children: [
              _headerChip(Icons.account_circle_rounded, 'الوكيل', parent),
              _headerChip(Icons.account_balance_wallet_rounded, 'الرصيد',
                  balance,
                  color: AppTheme.successColor),
              _headerChip(Icons.event_busy_rounded, 'الانتهاء', expiration,
                  mono: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerChip(IconData icon, String label, String value,
      {Color? color, bool mono = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15.sp, color: Colors.grey[500]),
        SizedBox(width: 4.w),
        Text('$label: ',
            style: GoogleFonts.cairo(
                fontSize: 11.5.sp, color: Colors.grey[600])),
        mono
            ? Directionality(
                textDirection: TextDirection.ltr,
                child: Text(value,
                    style: GoogleFonts.robotoMono(
                        fontSize: 11.5.sp,
                        color: color ?? const Color(0xFF1A1A2E))),
              )
            : Text(value,
                style: GoogleFonts.cairo(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w800,
                    color: color ?? const Color(0xFF1A1A2E))),
      ],
    );
  }

  // ─── شريط الإجراءات ───

  Widget _actionBar() {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SasSectionHeader(
            title: 'الإجراءات',
            icon: Icons.bolt_rounded,
            gradient: AppTheme.blueGradient,
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _actionBtn('تفعيل', Icons.play_arrow_rounded,
                  AppTheme.successColor, _busy ? null : _doActivate),
              _actionBtn('تمديد', Icons.event_available_rounded,
                  AppTheme.infoColor, _busy ? null : _doExtend),
              _actionBtn('تغيير الباقة', Icons.swap_horiz_rounded,
                  AppTheme.accentColor, _busy ? null : _doChangeProfile),
              _actionBtn('إضافة ترافيك', Icons.speed_rounded,
                  AppTheme.infoColor, _busy ? null : _doAddTraffic),
              _actionBtn('إيداع رصيد', Icons.add_card_rounded,
                  AppTheme.successColor,
                  _busy ? null : () => _doBalance('deposit', 'إيداع رصيد')),
              _actionBtn('سحب رصيد', Icons.money_off_rounded,
                  AppTheme.warningColor,
                  _busy ? null : () => _doBalance('withdraw', 'سحب رصيد')),
              _actionBtn('إعادة تسمية', Icons.drive_file_rename_outline_rounded,
                  Colors.blueGrey, _busy ? null : _doRename),
              _actionBtn('Ping', Icons.network_ping_rounded, Colors.blueGrey,
                  _busy ? null : _doPing),
              _actionBtn('تعديل', Icons.edit_rounded, AppTheme.primaryColor,
                  _busy ? null : _doEdit),
              _actionBtn('استرداد', Icons.receipt_long_rounded,
                  AppTheme.warningColor, _busy ? null : _doRefund,
                  outlined: true),
              _actionBtn('حذف', Icons.delete_outline_rounded,
                  AppTheme.errorColor, _busy ? null : _doDelete,
                  outlined: true, danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color,
      VoidCallback? onTap,
      {bool outlined = false, bool danger = false}) {
    final labelStyle = GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 12.5);
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? AppTheme.errorColor : color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SasUi.radiusSm)),
        ),
        icon: Icon(icon, size: 17),
        label: Text(label, style: labelStyle),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label, style: labelStyle),
    );
  }

  // ─── بطاقات الحقول ───

  Widget _fieldCards(Map<String, dynamic> d) {
    final ov = _overview;
    return Column(
      children: [
        _fieldSection('الهوية', Icons.badge_rounded, AppTheme.blueGradient, [
          _fv('المستخدم', d['username'], mono: true),
          _fv('الاسم الأول', d['firstname']),
          _fv('الاسم الأخير', d['lastname']),
          _fv('الهوية الوطنية', d['national_id'], mono: true),
          _fv('رقم العقد', d['contract_id'], mono: true),
        ]),
        SizedBox(height: 12.h),
        _fieldSection('التواصل', Icons.phone_rounded, AppTheme.greenGradient, [
          _fv('الهاتف', d['phone'], mono: true),
          _fv('البريد الإلكتروني', d['email']),
          _fv('المدينة', d['city']),
          _fv('العنوان', d['address']),
          _fv('الشارع', d['street']),
          _fv('الدولة', d['country']),
        ]),
        SizedBox(height: 12.h),
        _fieldSection('الاشتراك', Icons.wifi_rounded, AppTheme.orangeGradient, [
          _fv('الباقة', ov?['profile_name'] ?? d['profile_id']),
          _fv('الحالة', _statusLabel(d['status'] ?? ov?['status'])),
          _fv('تاريخ الانتهاء', d['expiration'], mono: true),
          _fv('الرصيد', ov?['balance'] ?? d['balance'], mono: true),
          _fv('المرور المتبقي (تنزيل)', ov?['remaining_rx']),
          _fv('المرور المتبقي (رفع)', ov?['remaining_tx']),
          _fv('جلسات متزامنة', d['simultaneous_sessions']),
          _fv('الوكيل', ov?['parent_username'] ?? d['parent_username']),
          _fv('المجموعة', d['group_id']),
        ]),
        SizedBox(height: 12.h),
        _fieldSection('الشبكة', Icons.lan_rounded,
            const [Color(0xFF7B1FA2), Color(0xFF9C27B0)], [
          _fv('IP ثابت', d['static_ip'], mono: true),
          _fv('آخر عنوان IP', d['last_ip_address'], mono: true),
          _fv('مصادقة MAC', d['mac_auth']),
          _fv(
              'إحداثيات GPS',
              d['gps_lat'] != null ? '${d['gps_lat']}, ${d['gps_lng']}' : null,
              mono: true),
        ]),
        SizedBox(height: 12.h),
        _fieldSection('التواريخ والملاحظات', Icons.history_rounded,
            const [Color(0xFF455A64), Color(0xFF607D8B)], [
          _fv('آخر اتصال', d['last_online'], mono: true),
          _fv('تاريخ الإنشاء', d['created_at'], mono: true),
          _fv('تاريخ التحديث', d['updated_at'], mono: true),
          _fv('ملاحظات', d['notes']),
        ]),
      ],
    );
  }

  _FieldVal _fv(String label, dynamic value, {bool mono = false}) =>
      _FieldVal(label: label, value: value, mono: mono);

  Widget _fieldSection(
      String title, IconData icon, List<Color> gradient, List<_FieldVal> fields) {
    final nonEmpty = fields
        .where((f) => f.value != null && '${f.value}'.trim().isNotEmpty)
        .toList();
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SasSectionHeader(title: title, icon: icon, gradient: gradient),
          SizedBox(height: 10.h),
          if (nonEmpty.isEmpty)
            Text('لا بيانات',
                style: GoogleFonts.cairo(
                    fontSize: 12.sp, color: Colors.grey[500]))
          else
            for (final f in nonEmpty) _fieldRow(f),
        ],
      ),
    );
  }

  Widget _fieldRow(_FieldVal f) {
    final strVal = '${f.value ?? '—'}';
    final isEmpty = strVal.trim().isEmpty || strVal == 'null';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150.w,
            child: Text(f.label,
                style: GoogleFonts.cairo(
                    fontSize: 12.sp,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600)),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: f.mono
                ? Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(isEmpty ? '—' : strVal,
                        style: GoogleFonts.robotoMono(
                            fontSize: 12.5.sp,
                            color: isEmpty
                                ? Colors.grey[400]
                                : const Color(0xFF1A1A2E)),
                        overflow: TextOverflow.ellipsis),
                  )
                : Text(isEmpty ? '—' : strVal,
                    style: GoogleFonts.cairo(
                        fontSize: 13.sp,
                        color: isEmpty
                            ? Colors.grey[400]
                            : const Color(0xFF1A1A2E),
                        fontWeight:
                            isEmpty ? FontWeight.w400 : FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // ─── التبويبات الفرعية ───

  Widget _innerTabsCard() {
    return Container(
      decoration: SasUi.card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.04),
              border: Border(
                bottom:
                    BorderSide(color: Colors.grey.withValues(alpha: 0.12)),
              ),
            ),
            child: TabBar(
              controller: _innerTabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                gradient: const LinearGradient(colors: AppTheme.blueGradient),
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle:
                  GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 12.5),
              unselectedLabelStyle:
                  GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 12.5),
              tabs: const [
                Tab(text: 'معلومات المواطن'),
                Tab(text: 'كشف الحساب'),
                Tab(text: 'السجل'),
                Tab(text: 'الجلسات'),
                Tab(text: 'الفواتير'),
                Tab(text: 'الإيصالات'),
                Tab(text: 'القيود'),
                Tab(text: 'الحصص'),
                Tab(text: 'الترافيك'),
              ],
            ),
          ),
          SizedBox(
            height: 340.h,
            child: TabBarView(
              controller: _innerTabs,
              children: [
                _CitizenInfoTab(aid: _aid, uid: _uid),
                SasCitizenStatementView(
                  accountId: _aid,
                  userId: _uid,
                  subscriberName: _subscriberFullName(),
                ),
                _HistoryTab(aid: _aid, uid: _uid),
                _IndexListTab(
                  aid: _aid,
                  path: 'index/UserSessions/$_uid',
                  emptyMsg: 'لا جلسات مسجّلة',
                  cols: const [
                    ('acctstarttime', 'البدء'),
                    ('acctstoptime', 'الانتهاء'),
                    ('framedipaddress', 'IP'),
                    ('callingstationid', 'MAC'),
                    ('acctterminatecause', 'سبب الإنهاء'),
                  ],
                ),
                _IndexListTab(
                  aid: _aid,
                  path: 'index/UserInvoices/$_uid',
                  emptyMsg: 'لا فواتير',
                  cols: const [
                    ('invoice_number', 'رقم الفاتورة'),
                    ('created_at', 'التاريخ'),
                    ('type', 'النوع'),
                    ('amount', 'المبلغ'),
                    ('description', 'التفاصيل'),
                  ],
                ),
                _IndexListTab(
                  aid: _aid,
                  path: 'index/UserReceipts/$_uid',
                  emptyMsg: 'لا إيصالات',
                  cols: const [
                    ('receipt_number', 'رقم الإيصال'),
                    ('created_at', 'التاريخ'),
                    ('type', 'النوع'),
                    ('amount', 'المبلغ'),
                    ('description', 'التفاصيل'),
                  ],
                ),
                _IndexListTab(
                  aid: _aid,
                  path: 'index/UserJournal/$_uid',
                  emptyMsg: 'لا قيود مالية',
                  cols: const [
                    ('created_at', 'التاريخ'),
                    ('type', 'النوع'),
                    ('amount', 'المبلغ'),
                    ('description', 'التفاصيل'),
                  ],
                ),
                _IndexListTab(
                  aid: _aid,
                  path: 'index/Quota/$_uid',
                  emptyMsg: 'لا حصص',
                  cols: const [
                    ('created_at', 'التاريخ'),
                    ('rxtx_mbytes', 'الكمية (MB)'),
                    ('effective_date', 'يسري من'),
                    ('comment', 'ملاحظة'),
                  ],
                ),
                _IndexListTab(
                  aid: _aid,
                  path: 'user/traffic',
                  payload: {'user_id': _uid},
                  emptyMsg: 'لا سجلّات ترافيك',
                  cols: const [
                    ('date', 'التاريخ'),
                    ('rx', 'تنزيل'),
                    ('tx', 'رفع'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── الإجراءات المفوترة: تفعيل / تمديد / تغيير باقة ───
  //
  // كلّها تمرّ بالخط المطابق لـ FTTH:
  //   جلب السعر (activationData) → حوار تحصيل غنيّ → activateBilled →
  //   إعادة تحميل (الانتهاء الجديد) → طباعة ثم واتساب (خلفياً، معزول).

  Future<void> _doActivate() => _runBilledAction(
        action: 'activate',
        operationType: 'تم تفعيل اشتراك',
        confirmColor: AppTheme.successColor,
      );

  Future<void> _doExtend() async {
    final months = await _askMonths(title: 'تمديد الخدمة', confirmText: 'متابعة');
    if (months == null) return;
    await _runBilledAction(
      action: 'extend',
      operationType: 'تم التمديد',
      months: months,
      confirmColor: AppTheme.infoColor,
    );
  }

  Future<void> _doChangeProfile() async {
    List<Map<String, dynamic>> profiles;
    try {
      profiles = await _api.getPackages(_aid);
    } catch (e) {
      _toast('تعذّر جلب الباقات: $e', isError: true);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: Text('اختر الباقة الجديدة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          children: [
            for (final p in profiles)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: Text('${p['name'] ?? p['id']}',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    final profileId =
        _asNum(chosen['id'])?.toInt().toString() ?? chosen['id']?.toString();
    if (profileId == null || profileId.isEmpty) {
      _toast('باقة غير صالحة', isError: true);
      return;
    }
    await _runBilledAction(
      action: 'changeProfile',
      operationType: 'تم تغيير الباقة',
      profileId: profileId,
      profileNameHint: chosen['name']?.toString(),
      confirmColor: AppTheme.accentColor,
    );
  }

  String? get _username => widget.username ?? _detail?['username']?.toString();

  /// حوار إدخال عدد الأشهر (للتمديد) — يعيد عدداً ≥ 1 أو null عند الإلغاء.
  Future<int?> _askMonths(
      {required String title, required String confirmText}) async {
    final ctl = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (ctx) => _InputDialog(
        title: title,
        controller: ctl,
        label: 'عدد الأشهر',
        keyboard: TextInputType.number,
        digitsOnly: true,
        confirmText: confirmText,
        parse: (t) {
          final n = int.tryParse(t.trim()) ?? 1;
          return n < 1 ? 1 : n;
        },
      ),
    );
  }

  /// الخط المفوتر الموحّد: يجلب السعر، يعرض حوار التحصيل، ينفّذ `activateBilled`،
  /// يعيد التحميل، ثم يُطلق الطباعة/الواتساب خلفياً.
  Future<void> _runBilledAction({
    required String action,
    required String operationType,
    int? months,
    String? profileId,
    String? profileNameHint,
    Color confirmColor = AppTheme.primaryColor,
  }) async {
    // 1) جلب بيانات التفعيل (السعر + رصيد الوكيل + VAT + اسم الباقة) — خادمياً.
    setState(() => _busy = true);
    Map<String, dynamic> actData = const {};
    try {
      final raw = await _api.sasGet(_aid, 'user/activationData/$_uid');
      actData = _asMap(raw);
    } catch (_) {
      // قد لا تتوفّر (التمديد مثلاً) — نكمل بعرض «غير متاح» بسلاسة.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    final price = _asNum(actData['n_required_amount'] ??
        actData['required_amount'] ??
        actData['price']);
    final managerBalance = _asNum(actData['manager_balance'] ??
        actData['managerBalance'] ??
        actData['balance']);
    final vat = _asNum(actData['vat']);
    final planName = (profileNameHint?.trim().isNotEmpty == true)
        ? profileNameHint!.trim()
        : (actData['profile_name'] ??
                actData['profileName'] ??
                _overview?['profile_name'] ??
                _detail?['profile_id'])
            ?.toString();

    // 2) حوار التحصيل الغنيّ.
    final collection = await _showCollectionDialog(
      operationType: operationType,
      planName: planName,
      months: months,
      price: price,
      vat: vat,
      managerBalance: managerBalance,
      confirmColor: confirmColor,
    );
    if (collection == null || !mounted) return;

    // 3) التنفيذ المفوتر ثم إعادة التحميل + ما بعد التفعيل (طباعة/واتساب).
    setState(() => _busy = true);
    try {
      final res = await _api.activateBilled(
        _aid,
        _uid,
        action: action,
        months: months,
        profileId: profileId,
        collectionType: collection.collectionType,
        maintenanceFee: collection.maintenanceFee,
        manualDiscount: collection.manualDiscount,
        systemDiscountEnabled: true,
        phone: _subscriberPhone(),
        subscriberUsername: _username,
        transactionId: _txn(),
      );
      if (!mounted) return;
      _toast('تم: $operationType');
      await _loadMain();
      // مزامنة الحساب (سحب SAS4→محلي) ثم إشعار كل التبويبات المفتوحة لتتحدّث —
      // معزولة (فشلها لا يُسقط العملية). لا نحجب الطباعة/الواتساب خلفها.
      await SasRefreshBus.instance
          .syncAndNotify(_aid, reason: 'billed-$action');
      final receipt = (res['receipt'] is Map)
          ? (res['receipt'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      // ما بعد التحصيل (طباعة ثم واتساب) عبر المساعد المشترك — كلٌّ معزول.
      await SasBillingPostActions.run(
        receipt,
        customerName: _subscriberFullName(),
        phone: _subscriberPhone(),
        newExpiration: _detail?['expiration']?.toString(),
      );
    } catch (e) {
      if (mounted) {
        _toast('فشل: ${e.toString().replaceFirst('Exception: ', '').trim()}',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// رقم هاتف المشترك من التفاصيل (خام، يُطبَّع لاحقاً عند الإرسال).
  String? _subscriberPhone() {
    final p = (_detail?['phone'] ?? _detail?['mobile'] ?? _overview?['phone'])
        ?.toString()
        .trim();
    return (p == null || p.isEmpty) ? null : p;
  }

  // ─── إضافة ترافيك ───

  Future<void> _doAddTraffic() async {
    final ctl = TextEditingController();
    final val = await showDialog<double>(
      context: context,
      builder: (ctx) => _InputDialog(
        title: 'إضافة ترافيك',
        controller: ctl,
        label: 'الكمية (MB)',
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        confirmText: 'تنفيذ',
        parse: (t) => double.tryParse(t.trim()) ?? 0,
      ),
    );
    if (val == null || val <= 0) return;
    await _run(
      () => _api.userAction(_aid, _uid, 'addTraffic', params: {
        'amount': val,
        'value': val,
        'traffic': val,
        'target': 'rxtx_mbytes',
        'username': _username ?? '',
        'transaction_id': _txn(),
      }),
      'تم إضافة الترافيك',
    );
  }

  // ─── إيداع/سحب رصيد (تأكيد مالي) ───

  Future<void> _doBalance(String action, String title) async {
    final ctl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => _InputDialog(
        title: title,
        controller: ctl,
        label: 'المبلغ',
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        confirmText: 'متابعة',
        parse: (t) => double.tryParse(t.trim()) ?? 0,
      ),
    );
    if (amount == null || amount <= 0) return;
    // تأكيد ثانٍ للعملية المالية.
    final ok = await _confirm(
      title: title,
      body: 'سيتم $title بمقدار $amount للمشترك «${_username ?? _uid}». تأكيد؟',
      confirmText: 'تأكيد',
      confirmColor: action == 'deposit'
          ? AppTheme.successColor
          : AppTheme.warningColor,
    );
    if (ok != true) return;
    await _run(
      () => _api.userAction(_aid, _uid, action, params: {
        'amount': amount,
        'user_username': _username ?? '',
        'comment': '',
        'transaction_id': _txn(),
      }),
      title,
    );
  }

  // ─── إعادة تسمية ───

  Future<void> _doRename() async {
    final current = _username ?? '';
    final ctl = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _InputDialog(
        title: 'إعادة تسمية المشترك',
        controller: ctl,
        label: 'اسم المستخدم الجديد',
        confirmText: 'تغيير',
        parse: (t) => t.trim(),
      ),
    );
    if (newName == null || newName.isEmpty || newName == current) return;
    await _run(
      () => _api.userAction(_aid, _uid, 'rename',
          params: {'new_username': newName}),
      'تم تغيير الاسم',
    );
  }

  // ─── Ping ───

  Future<void> _doPing() async {
    await _run(
      () => _api.userAction(_aid, _uid, 'ping'),
      'تم إرسال Ping',
    );
  }

  // ─── تعديل (فتح النموذج) ───

  Future<void> _doEdit() async {
    final d = _detail;
    if (d == null) return;
    // نضمّ معرّف المشترك للحمولة ليستخدمه النموذج في التعديل.
    final withId = {...d, 'id': _uid};
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SasSubscriberFormPage(
          account: widget.account,
          existing: withId,
        ),
      ),
    );
    if (changed == true) await _loadMain();
  }

  // ─── استرداد (تأكيد مالي مع عرض بيانات) ───

  Future<void> _doRefund() async {
    Map<String, dynamic> data = const {};
    try {
      data = await _api.getUserRefundData(_aid, _uid);
    } catch (e) {
      _toast('تعذّر جلب بيانات الاسترداد: $e', isError: true);
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('إلغاء الخدمة واسترداد الرصيد',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.warningColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _refundRow('المبلغ المسترد', data['refund_amount']),
              _refundRow('سعر الباقة', data['price']),
              _refundRow('الأيام المتبقية', data['remaining_days']),
              _refundRow('الباقة', data['profile_name']),
              const SizedBox(height: 12),
              Text('سيُلغى اشتراك المشترك ويُسترد المبلغ أعلاه. متابعة؟',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.warningColor),
              child: Text('تأكيد الاسترداد',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => _api.refundUser(_aid, _uid),
      'تم إلغاء الخدمة والاسترداد',
    );
  }

  Widget _refundRow(String label, dynamic value) {
    if (value == null || '$value'.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text('$label: ',
            style: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 13)),
        Flexible(
            child: Text('$value',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800))),
      ]),
    );
  }

  // ─── حذف (تأكيد مزدوج) ───

  Future<void> _doDelete() async {
    final first = await _confirm(
      title: 'حذف المشترك',
      body: 'سيُحذف المشترك «${_username ?? _uid}» نهائياً من نظام الساس. '
          'هذا الإجراء لا يمكن التراجع عنه.',
      confirmText: 'متابعة',
      confirmColor: AppTheme.errorColor,
    );
    if (first != true || !mounted) return;
    final second = await _confirm(
      title: 'تأكيد نهائي',
      body: 'هل أنت متأكد تماماً؟ الحذف دائم.',
      confirmText: 'نعم، احذف',
      confirmColor: AppTheme.errorColor,
    );
    if (second != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _api.deleteUser(_aid, _uid);
      if (mounted) {
        _toast('تم حذف المشترك');
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _toast('فشل الحذف: ${e.toString().replaceFirst('Exception: ', '')}',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─── حوار التحصيل الغنيّ (على نمط FTTH) ───

  /// يعرض ملخّص العملية (المشترك/الباقة/المدة/السعر/رصيد الوكيل) + منتقي نوع
  /// التحصيل + حقلَي أجور الصيانة والخصم اليدوي (اختياريان). يتحقّق من كفاية
  /// الرصيد قبل الإتاحة. يعيد [_SasCollection] عند التأكيد أو null عند الإلغاء.
  Future<_SasCollection?> _showCollectionDialog({
    required String operationType,
    String? planName,
    int? months,
    num? price,
    num? vat,
    num? managerBalance,
    Color confirmColor = AppTheme.primaryColor,
  }) {
    String collectionType = 'cash';
    final maintenanceCtl = TextEditingController();
    final discountCtl = TextEditingController();

    // رصيد كافٍ؟ (السعر ≤ رصيد الوكيل) — إن تعذّر السعر/الرصيد نسمح بالمتابعة.
    bool sufficient() {
      if (price == null || managerBalance == null) return true;
      return price <= managerBalance;
    }

    return showDialog<_SasCollection>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
            final enough = sufficient();
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SasUi.radius)),
              title: Row(
                children: [
                  Icon(Icons.point_of_sale_rounded, color: confirmColor, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('تأكيد التحصيل — $operationType',
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w800, color: confirmColor)),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: confirmColor.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(SasUi.radiusSm),
                          border: Border.all(
                              color: confirmColor.withValues(alpha: 0.18)),
                        ),
                        child: Column(
                          children: [
                            _summaryRow('المشترك', _username ?? _uid, mono: true),
                            if (planName != null && planName.trim().isNotEmpty)
                              _summaryRow('الباقة', planName),
                            if (months != null)
                              _summaryRow('المدة', '$months شهر'),
                            _summaryRow(
                                'السعر',
                                price != null
                                    ? _money(price)
                                    : 'غير متاح',
                                strong: true,
                                color: confirmColor),
                            if (vat != null && vat > 0)
                              _summaryRow('ضريبة (VAT)', _money(vat)),
                            _summaryRow(
                              'رصيد الوكيل',
                              managerBalance != null
                                  ? _money(managerBalance)
                                  : 'غير متاح',
                              color: enough
                                  ? AppTheme.successColor
                                  : AppTheme.errorColor,
                              strong: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('نوع التحصيل',
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.grey[700])),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _collectionChip('cash', 'نقد', collectionType,
                              (v) => setLocal(() => collectionType = v)),
                          _collectionChip('credit', 'أجل المشغّل',
                              collectionType,
                              (v) => setLocal(() => collectionType = v)),
                          _collectionChip('agent', 'وكيل', collectionType,
                              (v) => setLocal(() => collectionType = v)),
                          _collectionChip('citizen', 'آجل (ذمة المواطن)',
                              collectionType,
                              (v) => setLocal(() => collectionType = v)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _miniField(
                                maintenanceCtl, 'أجور صيانة (اختياري)'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _miniField(
                                discountCtl, 'خصم يدوي (اختياري)'),
                          ),
                        ],
                      ),
                      if (!enough) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: AppTheme.errorColor, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'رصيد الوكيل لا يكفي لإتمام هذه العملية.',
                                style: GoogleFonts.cairo(
                                    color: AppTheme.errorColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('إلغاء',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                ),
                FilledButton(
                  onPressed: enough
                      ? () => Navigator.pop(
                            ctx,
                            _SasCollection(
                              collectionType: collectionType,
                              maintenanceFee:
                                  num.tryParse(maintenanceCtl.text.trim()),
                              manualDiscount:
                                  num.tryParse(discountCtl.text.trim()),
                            ),
                          )
                      : null,
                  style: FilledButton.styleFrom(backgroundColor: confirmColor),
                  child: Text('تأكيد وتحصيل',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool strong = false, bool mono = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('$label: ',
              style: GoogleFonts.cairo(
                  color: Colors.grey[600], fontSize: 12.5)),
          Expanded(
            child: mono
                ? Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(value,
                        textAlign: TextAlign.start,
                        style: GoogleFonts.robotoMono(
                            fontSize: 12.5,
                            fontWeight:
                                strong ? FontWeight.w800 : FontWeight.w600,
                            color: color ?? const Color(0xFF1A1A2E))),
                  )
                : Text(value,
                    style: GoogleFonts.cairo(
                        fontSize: 12.5,
                        fontWeight:
                            strong ? FontWeight.w800 : FontWeight.w600,
                        color: color ?? const Color(0xFF1A1A2E))),
          ),
        ],
      ),
    );
  }

  Widget _collectionChip(String value, String label, String selected,
      ValueChanged<String> onPick) {
    final active = value == selected;
    return ChoiceChip(
      selected: active,
      onSelected: (_) => onPick(value),
      label: Text(label,
          style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : Colors.grey[700])),
      selectedColor: AppTheme.primaryColor,
      backgroundColor: Colors.grey.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm)),
    );
  }

  Widget _miniField(TextEditingController ctl, String label) {
    return TextField(
      controller: ctl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: GoogleFonts.cairo(fontWeight: FontWeight.w700, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 11.5),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm)),
      ),
    );
  }

  String _money(num v) {
    final n = v == v.roundToDouble() ? v.round() : v;
    return n.toString();
  }

  /// الاسم الكامل للمشترك من التفاصيل، وإلا اسم المستخدم.
  String _subscriberFullName() {
    final f = (_detail?['firstname'] ?? '').toString().trim();
    final l = (_detail?['lastname'] ?? '').toString().trim();
    final full = '$f $l'.trim();
    return full.isNotEmpty ? full : (_username ?? _uid);
  }

  // ─── حوار تأكيد موحّد ───

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String confirmText,
    Color confirmColor = AppTheme.primaryColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title,
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: confirmColor)),
          content: Text(body,
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: confirmColor),
              child: Text(confirmText,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  // معرّف عملية فريد لمنع تكرار العمليات المالية.
  String _txn() => 'txn-${DateTime.now().microsecondsSinceEpoch}';

  /// يفكّ غلاف `data` إن وُجد، وإلا يعيد الخريطة كما هي.
  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) {
      final data = raw['data'];
      if (data is Map) return data.cast<String, dynamic>();
      return raw.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }
}

// ─── نتيجة حوار التحصيل ───

/// اختيار المستخدم في حوار التحصيل: نوع التحصيل + الحقول الاختيارية.
class _SasCollection {
  final String collectionType; // cash | credit | agent
  final num? maintenanceFee;
  final num? manualDiscount;

  const _SasCollection({
    required this.collectionType,
    this.maintenanceFee,
    this.manualDiscount,
  });
}

// ─── نموذج حقل داخلي ───

class _FieldVal {
  final String label;
  final dynamic value;
  final bool mono;
  const _FieldVal({required this.label, required this.value, this.mono = false});
}

// ─── حوار إدخال عام (يعيد قيمة مُحوَّلة عبر parse أو null) ───

class _InputDialog<T> extends StatelessWidget {
  final String title;
  final TextEditingController controller;
  final String label;
  final String confirmText;
  final TextInputType? keyboard;
  final bool digitsOnly;
  final T Function(String) parse;

  const _InputDialog({
    required this.title,
    required this.controller,
    required this.label,
    required this.confirmText,
    required this.parse,
    this.keyboard,
    this.digitsOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(title,
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          inputFormatters:
              digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.cairo(color: Colors.grey[600]),
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SasUi.radiusSm)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700))),
          FilledButton(
            onPressed: () => Navigator.pop(context, parse(controller.text)),
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            child: Text(confirmText,
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─── تبويب السجل (عبر getUserHistory) ───

class _HistoryTab extends StatefulWidget {
  final String aid;
  final String uid;
  const _HistoryTab({required this.aid, required this.uid});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _api = SasAgentApiService.instance;
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.getUserHistory(widget.aid, widget.uid);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', '').trim());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SasErrorView(message: 'تعذّر جلب السجل: $_error', onRetry: () {
        setState(() {
          _error = null;
          _rows = null;
        });
        _load();
      });
    }
    if (_rows == null) return const SasLoadingView();
    if (_rows!.isEmpty) {
      return const SasEmptyView(
          message: 'لا أحداث مسجّلة', icon: Icons.history_rounded);
    }
    return ListView.separated(
      padding: EdgeInsets.all(10.w),
      itemCount: _rows!.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.12)),
      itemBuilder: (_, i) {
        final row = _rows![i];
        final event =
            (row['event'] ?? row['action'] ?? '—').toString();
        final desc =
            (row['description'] ?? row['details'] ?? '').toString();
        final date = (row['created_at'] ?? '').toString();
        return ListTile(
          dense: true,
          leading: Icon(Icons.history_rounded,
              size: 18, color: AppTheme.primaryColor),
          title: Text(event,
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          subtitle: desc.isEmpty
              ? null
              : Text(desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(fontSize: 11.5)),
          trailing: Text(date,
              style: GoogleFonts.robotoMono(
                  fontSize: 10.5, color: Colors.grey[500])),
        );
      },
    );
  }
}

// ─── تبويب «معلومات المواطن» الموسّعة (11 حقلاً: هوية · تواصل · موقع) ───

/// نموذج منظّم بمجموعات لعرض/تحرير حقول المواطن الإضافية عبر
/// get/saveSubscriberProfile. منفصل عن تفاصيل الساس (يبقى عبر المزامنة).
class _CitizenInfoTab extends StatefulWidget {
  final String aid;
  final String uid;
  const _CitizenInfoTab({required this.aid, required this.uid});

  @override
  State<_CitizenInfoTab> createState() => _CitizenInfoTabState();
}

class _CitizenInfoTabState extends State<_CitizenInfoTab> {
  final _api = SasAgentApiService.instance;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  // متحكّمات الحقول الـ11.
  final _nationalId = TextEditingController();
  final _fullNameQuad = TextEditingController();
  final _birthDate = TextEditingController();
  final _altPhone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _propertyType = TextEditingController();
  final _landmark = TextEditingController();
  String _gender = '';

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _nationalId,
      _fullNameQuad,
      _birthDate,
      _altPhone,
      _whatsapp,
      _email,
      _address,
      _latitude,
      _longitude,
      _propertyType,
      _landmark,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await _api.getSubscriberProfile(widget.aid, widget.uid);
      if (!mounted) return;
      _nationalId.text = p.nationalId;
      _fullNameQuad.text = p.fullNameQuad;
      _birthDate.text = p.birthDate;
      _altPhone.text = p.altPhone;
      _whatsapp.text = p.whatsappNumber;
      _email.text = p.email;
      _address.text = p.addressDetail;
      _latitude.text = p.latitude;
      _longitude.text = p.longitude;
      _propertyType.text = p.propertyType;
      _landmark.text = p.landmark;
      setState(() {
        _gender = p.gender;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _clean(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_canManage) return;
    setState(() => _saving = true);
    final fields = SasSubscriberProfile(
      nationalId: _nationalId.text.trim(),
      fullNameQuad: _fullNameQuad.text.trim(),
      birthDate: _birthDate.text.trim(),
      gender: _gender,
      altPhone: _altPhone.text.trim(),
      whatsappNumber: _whatsapp.text.trim(),
      email: _email.text.trim(),
      addressDetail: _address.text.trim(),
      latitude: _latitude.text.trim(),
      longitude: _longitude.text.trim(),
      propertyType: _propertyType.text.trim(),
      landmark: _landmark.text.trim(),
    );
    try {
      final ok =
          await _api.saveSubscriberProfile(widget.aid, widget.uid, fields);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'تم حفظ معلومات المواطن' : 'تعذّر الحفظ',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: ok ? AppTheme.successColor : AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('فشل: ${_clean(e)}',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب معلومات المواطن…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _load);
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 12.h),
            children: [
              _group('الهوية', Icons.badge_rounded, AppTheme.blueGradient, [
                _field(_fullNameQuad, 'الاسم الرباعي'),
                _field(_nationalId, 'الهوية الوطنية', mono: true),
                _field(_birthDate, 'تاريخ الميلاد',
                    hint: 'YYYY-MM-DD', mono: true),
                _genderField(),
              ]),
              SizedBox(height: 12.h),
              _group('التواصل', Icons.phone_rounded, AppTheme.greenGradient, [
                _field(_altPhone, 'هاتف بديل',
                    mono: true, keyboard: TextInputType.phone),
                _field(_whatsapp, 'رقم واتساب',
                    mono: true, keyboard: TextInputType.phone),
                _field(_email, 'البريد الإلكتروني',
                    keyboard: TextInputType.emailAddress),
              ]),
              SizedBox(height: 12.h),
              _group('الموقع / العقار', Icons.location_on_rounded,
                  AppTheme.orangeGradient, [
                _field(_address, 'تفاصيل العنوان'),
                _field(_propertyType, 'نوع العقار'),
                _field(_landmark, 'أقرب نقطة دالّة'),
                Row(
                  children: [
                    Expanded(
                        child: _field(_latitude, 'خط العرض (lat)',
                            mono: true,
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true, signed: true))),
                    SizedBox(width: 10.w),
                    Expanded(
                        child: _field(_longitude, 'خط الطول (lng)',
                            mono: true,
                            keyboard: const TextInputType.numberWithOptions(
                                decimal: true, signed: true))),
                  ],
                ),
              ]),
            ],
          ),
        ),
        _saveBar(),
      ],
    );
  }

  Widget _group(
      String title, IconData icon, List<Color> gradient, List<Widget> fields) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SasSectionHeader(title: title, icon: icon, gradient: gradient),
          SizedBox(height: 12.h),
          for (int i = 0; i < fields.length; i++) ...[
            if (i > 0) SizedBox(height: 10.h),
            fields[i],
          ],
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctl, String label,
      {bool mono = false, String? hint, TextInputType? keyboard}) {
    return TextField(
      controller: ctl,
      enabled: _canManage,
      keyboardType: keyboard,
      style: mono
          ? GoogleFonts.robotoMono(fontWeight: FontWeight.w700, fontSize: 13.sp)
          : GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13.sp),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle:
            GoogleFonts.cairo(color: Colors.grey[600], fontSize: 12.sp),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
      ),
    );
  }

  Widget _genderField() {
    return Row(
      children: [
        Text('الجنس:',
            style: GoogleFonts.cairo(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w700,
                color: Colors.grey[700])),
        SizedBox(width: 10.w),
        _genderChip('male', 'ذكر'),
        SizedBox(width: 8.w),
        _genderChip('female', 'أنثى'),
      ],
    );
  }

  Widget _genderChip(String value, String label) {
    final active = _gender == value;
    return ChoiceChip(
      selected: active,
      onSelected: _canManage ? (_) => setState(() => _gender = value) : null,
      label: Text(label,
          style: GoogleFonts.cairo(
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : Colors.grey[700])),
      selectedColor: AppTheme.primaryColor,
      backgroundColor: Colors.grey.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
    );
  }

  Widget _saveBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
            top: BorderSide(color: Colors.grey.withValues(alpha: 0.12))),
      ),
      child: Row(
        children: [
          const Spacer(),
          FilledButton.icon(
            onPressed: (!_canManage || _saving) ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              disabledBackgroundColor: Colors.grey.withValues(alpha: 0.30),
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 11.h),
            ),
            icon: _saving
                ? SizedBox(
                    width: 16.w,
                    height: 16.w,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_canManage ? 'حفظ' : 'لا صلاحية',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ─── تبويب قائمة عام عبر sasPost (جلسات/فواتير/إيصالات/قيود/حصص/ترافيك) ───

class _IndexListTab extends StatefulWidget {
  final String aid;
  final String path;
  final Map<String, dynamic> payload;
  final List<(String, String)> cols;
  final String emptyMsg;

  const _IndexListTab({
    required this.aid,
    required this.path,
    required this.cols,
    required this.emptyMsg,
    this.payload = const {},
  });

  @override
  State<_IndexListTab> createState() => _IndexListTabState();
}

class _IndexListTabState extends State<_IndexListTab> {
  final _api = SasAgentApiService.instance;
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // مسارات index/* تدعم الترقيم؛ user/traffic يقبل الحمولة الممرّرة كما هي.
      final payload = widget.path.startsWith('index/')
          ? {
              'page': 1,
              'count': 30,
              'direction': 'desc',
              'search': '',
              ...widget.payload,
            }
          : widget.payload;
      final res = await _api.sasPost(widget.aid, widget.path, payload: payload);
      final rows = sasExtractList(res);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = e.toString().replaceFirst('Exception: ', '').trim());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SasErrorView(message: 'تعذّر الجلب: $_error', onRetry: () {
        setState(() {
          _error = null;
          _rows = null;
        });
        _load();
      });
    }
    if (_rows == null) return const SasLoadingView();
    if (_rows!.isEmpty) {
      return SasEmptyView(
          message: widget.emptyMsg, icon: Icons.inbox_rounded);
    }
    return ListView.separated(
      padding: EdgeInsets.all(10.w),
      itemCount: _rows!.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.12)),
      itemBuilder: (_, i) {
        final row = _rows![i];
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 4.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final c in widget.cols)
                Padding(
                  padding: EdgeInsets.only(bottom: 3.h),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96.w,
                        child: Text(c.$2,
                            style: GoogleFonts.cairo(
                                color: Colors.grey[600],
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text(
                          row[c.$1] == null || '${row[c.$1]}'.isEmpty
                              ? '—'
                              : '${row[c.$1]}',
                          style: GoogleFonts.cairo(
                              fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── مساعدات الحالة ───

String _statusLabel(dynamic status) {
  if (status is Map) {
    return (status['status'] == true) ? 'نشط' : 'متوقّف';
  }
  switch ('$status') {
    case 'active':
      return 'نشط';
    case 'expired':
      return 'منتهٍ';
    case 'disabled':
    case 'inactive':
      return 'متوقّف';
    case 'online':
      return 'متصل';
    case 'offline':
      return 'غير متصل';
    case '1':
    case 'true':
      return 'نشط';
    case '0':
    case 'false':
      return 'متوقّف';
    default:
      return '$status' == 'null' ? '—' : '$status';
  }
}

Color _statusColor(dynamic status) {
  final label = _statusLabel(status);
  switch (label) {
    case 'نشط':
    case 'متصل':
      return AppTheme.successColor;
    case 'منتهٍ':
      return AppTheme.warningColor;
    case 'متوقّف':
    case 'غير متصل':
      return AppTheme.errorColor;
    default:
      return Colors.blueGrey;
  }
}
