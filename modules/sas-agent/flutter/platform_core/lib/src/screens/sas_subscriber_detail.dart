import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api/staff_api.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/banner.dart';
import '../widgets/common.dart';

/// تحويل آمن لرقم — SAS يُعيد حقولاً عددية كنصوص أحياناً.
num? _asNum(dynamic v) => v is num ? v : (v == null ? null : num.tryParse(v.toString()));

/// شاشة تفاصيل مشترك SAS الكاملة — تفتح من لوحة SAS أو من أي مكان في المنصّة.
/// تجلب: تفاصيل المستخدم الكاملة + overview عند الفتح.
/// تبويبات: السجلّ · القيود · الترافيك.
/// إجراءات: تفعيل · تمديد · تغيير الباقة · إضافة ترافيك · إيداع · سحب · إعادة تسمية · ping · حذف.
class SasSubscriberDetail extends StatefulWidget {
  final StaffApi api;
  final int companyId;
  final int userId;

  /// عندما يكون الحساب وكيلاً — يُخفي بعض الإجراءات الإدارية.
  final bool isAgent;

  /// اسم المستخدم الأوّلي (من قائمة) يُعرض أثناء التحميل.
  final String? username;

  const SasSubscriberDetail({
    super.key,
    required this.api,
    required this.companyId,
    required this.userId,
    this.isAgent = false,
    this.username,
  });

  @override
  State<SasSubscriberDetail> createState() => _SasSubscriberDetailState();
}

class _SasSubscriberDetailState extends State<SasSubscriberDetail>
    with SingleTickerProviderStateMixin {
  // ─── بيانات ───
  Map<String, dynamic>? _detail;
  Map<String, dynamic>? _overview;
  String? _loadError;
  bool _loadingMain = true;

  // ─── تبويبات داخلية ───
  late final TabController _innerTabs;

  // حالة كل تبويب (يُجلب عند أول فتح)
  bool _historyLoaded = false;
  bool _journalLoaded = false;
  bool _trafficLoaded = false;
  bool _advancedLoaded = false;

  List<Map<String, dynamic>>? _historyRows;
  String? _historyError;

  List<Map<String, dynamic>>? _journalRows;
  String? _journalError;

  Map<String, dynamic>? _trafficData;
  String? _trafficError;

  // تبويب «متقدّم»: MAC + سمات Radius المخصّصة
  List<Map<String, dynamic>>? _macRows;
  List<Map<String, dynamic>>? _radiusRows;
  String? _advancedError;

  // ─── إجراءات ───
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _innerTabs = TabController(length: 8, vsync: this)
      ..addListener(_onTabChanged);
    _loadMain();
  }

  @override
  void dispose() {
    _innerTabs.removeListener(_onTabChanged);
    _innerTabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_innerTabs.indexIsChanging) return;
    // 0 السجل · 1 القيود · 2 الجلسات · 3 الفواتير · 4 إيصالات · 5 حصص (ذاتية) · 6 الترافيك · 7 متقدّم
    switch (_innerTabs.index) {
      case 0:
        if (!_historyLoaded) _loadHistory();
      case 1:
        if (!_journalLoaded) _loadJournal();
      case 6:
        if (!_trafficLoaded) _loadTraffic();
      case 7:
        if (!_advancedLoaded) _loadAdvanced();
    }
  }

  // ─── جلب التفاصيل الرئيسية ───

  Future<void> _loadMain() async {
    setState(() {
      _loadingMain = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        widget.api.sasUser(widget.companyId, widget.userId),
        widget.api.sasGet(widget.companyId, 'user/overview/${widget.userId}'),
      ]);
      if (!mounted) return;
      final rawDetail = results[0] as Map<String, dynamic>;
      final rawOverview = results[1];
      setState(() {
        _detail = (rawDetail['data'] is Map)
            ? (rawDetail['data'] as Map<String, dynamic>)
            : rawDetail;
        _overview = (rawOverview is Map<String, dynamic>)
            ? ((rawOverview['data'] is Map)
                ? (rawOverview['data'] as Map<String, dynamic>)
                : rawOverview)
            : null;
        _loadingMain = false;
      });
      // جلب السجلّ فور التحميل (التبويب الأول مفتوح)
      if (!_historyLoaded) _loadHistory();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loadingMain = false;
      });
    }
  }

  // ─── تبويب السجلّ ───

  Future<void> _loadHistory() async {
    _historyLoaded = true;
    try {
      final r = await widget.api.sasPostList(
        widget.companyId,
        'index/UserHistory/${widget.userId}',
      );
      if (!mounted) return;
      final rows = _extractList(r);
      setState(() => _historyRows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _historyError = '$e');
    }
  }

  // ─── تبويب القيود ───

  Future<void> _loadJournal() async {
    _journalLoaded = true;
    try {
      final r = await widget.api.sasPostList(
        widget.companyId,
        'index/UserJournal/${widget.userId}',
      );
      if (!mounted) return;
      final rows = _extractList(r);
      setState(() => _journalRows = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _journalError = '$e');
    }
  }

  // ─── تبويب الترافيك ───

  Future<void> _loadTraffic() async {
    _trafficLoaded = true;
    try {
      final r = await widget.api.sasPostList(
        widget.companyId,
        'user/traffic',
        {'user_id': widget.userId},
      );
      if (!mounted) return;
      setState(() {
        if (r is Map<String, dynamic>) {
          _trafficData = r;
        } else {
          _trafficData = {'data': r};
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _trafficError = '$e');
    }
  }

  // ─── تبويب متقدّم: MAC + سمات Radius ───

  Future<void> _loadAdvanced() async {
    _advancedLoaded = true;
    try {
      final results = await Future.wait([
        widget.api.sasMac(widget.companyId, widget.userId),
        widget.api.sasCustomRadius(widget.companyId, widget.userId),
      ]);
      if (!mounted) return;
      setState(() {
        _macRows = _extractList(results[0]);
        _radiusRows = _extractList(results[1]);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _advancedError = '$e');
    }
  }

  // ─── مساعد استخراج القائمة ───

  static List<Map<String, dynamic>> _extractList(dynamic r) {
    if (r is Map<String, dynamic>) {
      final d = r['data'];
      if (d is List) return d.cast<Map<String, dynamic>>();
    }
    if (r is List) return r.cast<Map<String, dynamic>>();
    return [];
  }

  // ─── الواجهة ───

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    final d = _detail;
    final ov = _overview;

    return Scaffold(
      backgroundColor: pal.surface,
      body: _loadingMain
          ? const LoadingView()
          : _loadError != null && d == null
              ? _buildError(pal)
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader(d!, ov, pal, t)),
                    SliverToBoxAdapter(child: _buildActionBar(pal)),
                    SliverToBoxAdapter(child: _buildFieldCards(d, ov, pal, t)),
                    SliverToBoxAdapter(child: _buildInnerTabs(pal)),
                  ],
                ),
    );
  }

  Widget _buildError(PlatformPalette pal) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PBanner.error('تعذّر جلب بيانات المشترك:\n$_loadError'),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: _loadMain,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 16),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── ترويسة المشترك ───

  Widget _buildHeader(
    Map<String, dynamic> d,
    Map<String, dynamic>? ov,
    PlatformPalette pal,
    TextTheme t,
  ) {
    final username = (d['username'] ?? widget.username ?? '—') as String;
    final firstname = (d['firstname'] as String?) ?? '';
    final lastname = (d['lastname'] as String?) ?? '';
    final fullName = '$firstname $lastname'.trim();
    final statusRaw = d['status'] ?? ov?['status'];
    final statusLabel = _statusLabel(statusRaw);
    final statusColor = pal.status(_statusKey(statusRaw));
    final parent = (ov?['parent_username'] ?? d['parent_username'] ?? d['parent_id'] as dynamic)
        ?.toString() ?? '—';
    final balance = (ov?['balance'] ?? d['balance'])?.toString() ?? '—';
    final expiration = (d['expiration'] as String?) ?? '—';

    return Container(
      color: pal.surfaceCard,
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: statusColor.withValues(alpha: 0.14),
                child: Icon(PhosphorIconsDuotone.user, color: statusColor, size: 28),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            username,
                            style: PlatformType.mono(
                              size: 20,
                              weight: FontWeight.w800,
                              color: pal.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        StatusChip(
                          statusLabel,
                          color: statusColor,
                          icon: _statusIcon(statusRaw),
                        ),
                      ],
                    ),
                    if (fullName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        fullName,
                        style: t.bodyMedium?.copyWith(color: pal.textMuted),
                      ),
                    ],
                  ],
                ),
              ),
              if (_loadingMain)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.lg,
            runSpacing: Space.xs,
            children: [
              _headerChip(
                PhosphorIconsBold.userCircle,
                'الوكيل',
                parent,
                pal,
                t,
              ),
              _headerChip(
                PhosphorIconsBold.wallet,
                'الرصيد',
                balance,
                pal,
                t,
                color: pal.success,
              ),
              _headerChip(
                PhosphorIconsBold.calendarX,
                'الانتهاء',
                expiration,
                pal,
                t,
                mono: true,
              ),
            ],
          ),
          if (_loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.sm),
              child: PBanner.error(
                'بعض البيانات غير مكتملة: $_loadError',
                dense: true,
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerChip(
    IconData icon,
    String label,
    String value,
    PlatformPalette pal,
    TextTheme t, {
    Color? color,
    bool mono = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: pal.textMuted),
        const SizedBox(width: 4),
        Text('$label: ', style: t.bodySmall?.copyWith(color: pal.textMuted)),
        Text(
          value,
          style: mono
              ? PlatformType.mono(size: 12, color: color ?? pal.text)
              : t.bodySmall?.copyWith(
                  color: color ?? pal.text,
                  fontWeight: FontWeight.w700,
                ),
        ),
      ],
    );
  }

  // ─── شريط الإجراءات ───

  Widget _buildActionBar(PlatformPalette pal) {
    return Container(
      color: pal.surfaceCard,
      padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: pal.outline),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              _actionBtn(
                'تفعيل',
                PhosphorIconsBold.play,
                pal.success,
                _busy ? null : _doActivate,
              ),
              _actionBtn(
                'تمديد',
                PhosphorIconsBold.calendarPlus,
                pal.info,
                _busy ? null : _doExtend,
              ),
              _actionBtn(
                'تغيير الباقة',
                PhosphorIconsBold.arrowsHorizontal,
                pal.accent,
                _busy ? null : _doChangeProfile,
              ),
              _actionBtn(
                'إضافة ترافيك',
                PhosphorIconsBold.wifiHigh,
                pal.info,
                _busy ? null : _doAddTraffic,
              ),
              _actionBtn(
                'إيداع رصيد',
                PhosphorIconsBold.currencyDollar,
                pal.success,
                _busy ? null : () => _doBalance('deposit', 'إيداع رصيد'),
              ),
              _actionBtn(
                'سحب رصيد',
                PhosphorIconsBold.arrowCircleDown,
                pal.warning,
                _busy ? null : () => _doBalance('withdraw', 'سحب رصيد'),
              ),
              _actionBtn(
                'إعادة تسمية',
                PhosphorIconsBold.pencil,
                pal.textMuted,
                _busy ? null : _doRename,
              ),
              _actionBtn(
                _isEnabled ? 'تعطيل الحساب' : 'تفعيل الحساب',
                PhosphorIconsBold.power,
                _isEnabled ? pal.warning : pal.success,
                _busy ? null : _doToggleEnabled,
              ),
              _actionBtn(
                'كلمة المرور',
                PhosphorIconsBold.key,
                pal.textMuted,
                _busy ? null : _doChangePassword,
              ),
              _actionBtn(
                'تعديل البيانات',
                PhosphorIconsBold.note,
                pal.textMuted,
                _busy ? null : _doEditInfo,
              ),
              _actionBtn(
                'عناوين MAC',
                PhosphorIconsBold.identificationCard,
                pal.textMuted,
                _busy ? null : _doManageMac,
              ),
              _actionBtn(
                'Ping',
                PhosphorIconsBold.wifiMedium,
                pal.textMuted,
                _busy ? null : _doPing,
              ),
              _actionBtn(
                'إلغاء/استرداد',
                PhosphorIconsBold.receiptX,
                pal.warning,
                _busy ? null : _doRefund,
                filled: false,
              ),
              if (!widget.isAgent)
                _actionBtn(
                  'حذف',
                  PhosphorIconsBold.trash,
                  pal.danger,
                  _busy ? null : _doDelete,
                  filled: false,
                  danger: true,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    bool filled = true,
    bool danger = false,
  }) {
    if (filled) {
      return FilledButton.tonalIcon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        ),
        icon: Icon(icon, size: 16, color: onTap == null ? null : color),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
        foregroundColor: danger ? context.pal.danger : null,
        side: danger ? BorderSide(color: context.pal.danger.withValues(alpha: 0.5)) : null,
      ),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }

  // ─── بطاقات الحقول ───

  Widget _buildFieldCards(
    Map<String, dynamic> d,
    Map<String, dynamic>? ov,
    PlatformPalette pal,
    TextTheme t,
  ) {
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldSection(
            'الهوية',
            PhosphorIconsDuotone.identificationCard,
            pal,
            t,
            [
              _fv('المستخدم', d['username'], mono: true),
              _fv('الاسم الأول', d['firstname']),
              _fv('الاسم الأخير', d['lastname']),
              _fv('الهوية الوطنية', d['national_id'], mono: true),
              _fv('رقم العقد', d['contract_id'], mono: true),
            ],
          ),
          const SizedBox(height: Space.md),
          _fieldSection(
            'التواصل',
            PhosphorIconsDuotone.phone,
            pal,
            t,
            [
              _fv('الهاتف', d['phone'], mono: true),
              _fv('البريد الإلكتروني', d['email']),
              _fv('المدينة', d['city']),
              _fv('العنوان', d['address']),
              _fv('الشارع', d['street']),
              _fv('الشقة', d['apartment']),
              _fv('الدولة', d['country']),
            ],
          ),
          const SizedBox(height: Space.md),
          _fieldSection(
            'الاشتراك',
            PhosphorIconsDuotone.wifiHigh,
            pal,
            t,
            [
              _fv('الباقة', ov?['profile_name'] ?? d['profile_id']),
              _fv('الحالة', _statusLabel(d['status'] ?? ov?['status'])),
              _fv('تاريخ الانتهاء', d['expiration'], mono: true),
              _fv('الرصيد', ov?['balance'] ?? d['balance'], mono: true),
              _fv('المرور المتبقي (تنزيل)', ov?['remaining_rx']),
              _fv('المرور المتبقي (رفع)', ov?['remaining_tx']),
              _fv('جلسات متزامنة', d['simultaneous_sessions']),
              _fv('الوكيل', ov?['parent_username'] ?? d['parent_username']),
              _fv('المجموعة', d['group_id']),
              _fv('الشركة', d['company']),
              _fv('الخدمة', d['service']),
            ],
          ),
          const SizedBox(height: Space.md),
          _fieldSection(
            'الشبكة',
            PhosphorIconsDuotone.networkSlash,
            pal,
            t,
            [
              _fv('IP ثابت', d['static_ip'], mono: true),
              _fv('آخر عنوان IP', d['last_ip_address'], mono: true),
              _fv('مصادقة MAC', d['mac_auth']),
              _fv('إحداثيات GPS', d['gps_lat'] != null
                  ? '${d['gps_lat']}, ${d['gps_lng']}'
                  : null, mono: true),
            ],
          ),
          const SizedBox(height: Space.md),
          _fieldSection(
            'التواريخ والملاحظات',
            PhosphorIconsDuotone.clockCounterClockwise,
            pal,
            t,
            [
              _fv('آخر اتصال', d['last_online'], mono: true),
              _fv('تاريخ الإنشاء', d['created_at'], mono: true),
              _fv('تاريخ التحديث', d['updated_at'], mono: true),
              _fv('ملاحظات', d['notes']),
            ],
          ),
        ],
      ),
    );
  }

  // حقل تفاصيل مرن: يُجاهل null ويعرض '—'
  _FieldVal _fv(String label, dynamic value, {bool mono = false}) =>
      _FieldVal(label: label, value: value, mono: mono);

  Widget _fieldSection(
    String title,
    IconData icon,
    PlatformPalette pal,
    TextTheme t,
    List<_FieldVal> fields,
  ) {
    final nonEmpty = fields.where((f) => f.value != null && '${f.value}'.trim().isNotEmpty).toList();
    return Container(
      decoration: BoxDecoration(
        color: pal.surfaceCard,
        borderRadius: Radii.rLg,
        border: Border.all(color: pal.outline),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: pal.accent),
              const SizedBox(width: Space.xs),
              Text(
                title,
                style: t.titleSmall?.copyWith(
                  color: pal.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          if (nonEmpty.isEmpty)
            Text('لا بيانات', style: t.bodySmall?.copyWith(color: pal.textMuted))
          else
            for (final f in nonEmpty)
              _buildFieldRow(f, pal, t),
        ],
      ),
    );
  }

  Widget _buildFieldRow(_FieldVal f, PlatformPalette pal, TextTheme t) {
    final strVal = '${f.value ?? '—'}';
    final isEmpty = strVal.trim().isEmpty || strVal == 'null';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              f.label,
              style: t.bodySmall?.copyWith(color: pal.textMuted),
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: f.mono
                ? Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      isEmpty ? '—' : strVal,
                      style: PlatformType.mono(
                        size: 13,
                        color: isEmpty ? pal.textMuted : pal.text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : Text(
                    isEmpty ? '—' : strVal,
                    style: t.bodyMedium?.copyWith(
                      color: isEmpty ? pal.textMuted : pal.text,
                      fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ],
      ),
    );
  }

  // ─── التبويبات الداخلية ───

  Widget _buildInnerTabs(PlatformPalette pal) {
    return Container(
      margin: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
      decoration: BoxDecoration(
        color: pal.surfaceCard,
        borderRadius: Radii.rLg,
        border: Border.all(color: pal.outline),
      ),
      child: Column(
        children: [
          TabBar(
            controller: _innerTabs,
            isScrollable: true,
            tabs: const [
              Tab(text: 'السجلّ'),
              Tab(text: 'القيود'),
              Tab(text: 'الجلسات'),
              Tab(text: 'الفواتير'),
              Tab(text: 'الإيصالات'),
              Tab(text: 'الحصص'),
              Tab(text: 'الترافيك'),
              Tab(text: 'متقدّم'),
            ],
          ),
          SizedBox(
            height: 320,
            child: TabBarView(
              controller: _innerTabs,
              children: [
                _HistoryTabBody(rows: _historyRows, error: _historyError),
                _JournalTabBody(rows: _journalRows, error: _journalError),
                _SubListTab(api: widget.api, cid: widget.companyId,
                    path: 'index/UserSessions/${widget.userId}', cols: const [
                  ('acctstarttime', 'البدء'), ('acctstoptime', 'الانتهاء'),
                  ('framedipaddress', 'IP'), ('callingstationid', 'MAC'),
                  ('acctterminatecause', 'سبب الإنهاء'),
                ]),
                _SubListTab(api: widget.api, cid: widget.companyId,
                    path: 'index/UserInvoices/${widget.userId}', cols: const [
                  ('invoice_number', 'رقم الفاتورة'), ('created_at', 'التاريخ'),
                  ('type', 'النوع'), ('amount', 'المبلغ'), ('description', 'التفاصيل'),
                ]),
                _SubListTab(api: widget.api, cid: widget.companyId,
                    path: 'index/UserReceipts/${widget.userId}', cols: const [
                  ('receipt_number', 'رقم الإيصال'), ('created_at', 'التاريخ'),
                  ('type', 'النوع'), ('amount', 'المبلغ'), ('description', 'التفاصيل'),
                ]),
                _SubListTab(api: widget.api, cid: widget.companyId,
                    path: 'index/Quota/${widget.userId}', cols: const [
                  ('created_at', 'التاريخ'), ('rxtx_mbytes', 'الكمية (MB)'),
                  ('effective_date', 'يسري من'), ('comment', 'ملاحظة'),
                ]),
                _TrafficTabBody(data: _trafficData, error: _trafficError),
                _AdvancedTabBody(
                  macRows: _macRows,
                  radiusRows: _radiusRows,
                  error: _advancedError,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── الإجراءات ───

  Future<void> _run(Future<dynamic> Function() call, String okMsg) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      String msg = okMsg;
      if (res is Map<String, dynamic>) {
        msg = (res['message'] ?? res['status'] ?? okMsg).toString();
      }
      if (mounted) {
        toast(context, 'تم: $msg', kind: BannerKind.success);
        await _loadMain();
      }
    } catch (e) {
      if (mounted) toast(context, 'فشل: $e', kind: BannerKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doActivate() async {
    // جلب بيانات التفعيل أولاً ثم تأكيد
    Map<String, dynamic>? actData;
    try {
      final r = await widget.api.sasGet(widget.companyId, 'user/activationData/${widget.userId}');
      if (r is Map<String, dynamic>) {
        actData = (r['data'] is Map) ? (r['data'] as Map<String, dynamic>) : r;
      }
    } catch (_) {
      // إن فشل الجلب نستمر بلا بيانات
    }
    if (!mounted) return;

    final ok = await _showActivateDialog(actData);
    if (ok != true) return;

    await _run(
      () => widget.api.sasUserActionFull(
        widget.companyId,
        widget.userId,
        'activate',
        {                               // §29: method + money_collected + transaction_id
          'method': 'credit',           // تفعيل من رصيد المدير
          'money_collected': true,
          'transaction_id': _txn(),
          if (actData?['profile_id'] != null) 'profile_id': actData!['profile_id'],
        },
      ),
      'تم تفعيل المشترك',
    );
  }

  Future<bool?> _showActivateDialog(Map<String, dynamic>? data) {
    final pal = context.pal;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تفعيل الخدمة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data != null) ...[
                Text('بيانات التفعيل:',
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: Space.sm),
                for (final entry in data.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Text('${entry.key}: ',
                          style: TextStyle(color: pal.textMuted, fontSize: 13)),
                      Flexible(
                        child: Text('${entry.value ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                const SizedBox(height: Space.md),
              ],
              const Text('تأكيد تفعيل هذا المشترك؟'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تفعيل')),
          ],
        ),
      ),
    );
  }

  Future<void> _doExtend() async {
    // جلب بيانات التمديد + الامتدادات المسموحة
    Map<String, dynamic>? extData;
    List<Map<String, dynamic>> allowedExts = [];
    try {
      final r = await widget.api.sasGet(widget.companyId, 'user/extensionData/${widget.userId}');
      if (r is Map<String, dynamic>) {
        extData = (r['data'] is Map) ? (r['data'] as Map<String, dynamic>) : r;
      }
      final profileId = _asNum(extData?['profile_id'])?.toInt() ??
          _asNum(_detail?['profile_id'])?.toInt();
      if (profileId != null) {
        final ar = await widget.api.sasGet(
            widget.companyId, 'allowedExtensions/$profileId');
        final list = (ar is Map<String, dynamic>) ? (ar['data'] ?? ar) : ar;
        if (list is List) allowedExts = list.cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (!mounted) return;

    final result = await _showExtendDialog(extData, allowedExts);
    if (result == null) return;

    await _run(
      () => widget.api.sasUserActionFull(
        widget.companyId,
        widget.userId,
        'extend',
        {                               // §33: profile_id + method + transaction_id (+ مرادفات تحوّط)
          ...result,
          'method': 'credit',
          'transaction_id': _txn(),
          if (result['extension_id'] != null) 'profile_id': result['extension_id'],
        },
      ),
      'تم التمديد',
    );
  }

  Future<Map<String, dynamic>?> _showExtendDialog(
    Map<String, dynamic>? extData,
    List<Map<String, dynamic>> allowedExts,
  ) {
    final periodsCtl = TextEditingController(text: '1');
    int? selectedExtId;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx2, setLocal) => AlertDialog(
            title: const Text('تمديد الخدمة'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (allowedExts.isNotEmpty) ...[
                    const Text('اختر نوع التمديد:'),
                    const SizedBox(height: Space.xs),
                    RadioGroup<int>(
                      groupValue: selectedExtId,
                      onChanged: (v) => setLocal(() => selectedExtId = v),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final ext in allowedExts)
                            RadioListTile<int>(
                              title: Text('${ext['name'] ?? ext['id']}'),
                              subtitle: ext['price'] != null
                                  ? Text('السعر: ${ext['price']}')
                                  : null,
                              value: _asNum(ext['id'])?.toInt() ?? 0,
                              dense: true,
                            ),
                        ],
                      ),
                    ),
                    const Divider(),
                  ],
                  const Text('عدد الفترات:'),
                  const SizedBox(height: Space.xs),
                  TextField(
                    controller: periodsCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الفترات/الأشهر',
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('إلغاء')),
              FilledButton(
                onPressed: () {
                  final n = int.tryParse(periodsCtl.text.trim()) ?? 1;
                  Navigator.pop(ctx2, {
                    'periods': n,
                    'count': n,
                    if (selectedExtId != null) 'extension_id': selectedExtId,
                  });
                },
                child: const Text('تمديد'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doChangeProfile() async {
    List<Map<String, dynamic>> profiles;
    try {
      profiles = await widget.api.sasProfiles(widget.companyId);
    } catch (e) {
      if (mounted) toast(context, 'تعذّر جلب الباقات: $e', kind: BannerKind.error);
      return;
    }
    if (!mounted) return;

    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SimpleDialog(
          title: const Text('اختر الباقة الجديدة'),
          children: [
            for (final p in profiles)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, (p['id'] as num?)?.toInt()),
                child: Text('${p['name'] ?? p['id']}'),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    await _run(
      () => widget.api.sasUserActionFull(
        widget.companyId,
        widget.userId,
        'changeProfile',
        {'profile_id': chosen, 'method': 'credit', 'transaction_id': _txn()},  // §34
      ),
      'تم تغيير الباقة',
    );
  }

  // معرّف عملية فريد لمنع تكرار العمليات المالية (كل عمليات SAS المالية تحمله)
  String _txn() => 'txn-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _doAddTraffic() async {
    final ctl = TextEditingController();
    final ok = await _showAmountDialog('إضافة ترافيك', 'الكمية (MB/GB)', ctl);
    if (!ok || ctl.text.trim().isEmpty) return;
    final val = double.tryParse(ctl.text.trim());
    if (val == null) return;

    await _run(
      () => widget.api.sasUserActionFull(
        widget.companyId,
        widget.userId,
        'addTraffic',
        {                               // §30: username + amount + target + transaction_id
          'amount': val, 'value': val, 'traffic': val,
          'target': 'rxtx_mbytes',
          'username': _detail?['username'] ?? widget.username ?? '',
          'transaction_id': _txn(),
        },
      ),
      'تم إضافة الترافيك',
    );
  }

  Future<void> _doBalance(String action, String title) async {
    final ctl = TextEditingController();
    final ok = await _showAmountDialog(title, 'المبلغ', ctl);
    if (!ok || ctl.text.trim().isEmpty) return;
    final amount = double.tryParse(ctl.text.trim());
    if (amount == null) return;

    await _run(
      () => widget.api.sasUserActionFull(
        widget.companyId,
        widget.userId,
        action,
        {                               // §35/§36: user_username + comment + transaction_id
          'amount': amount,
          'user_username': _detail?['username'] ?? widget.username ?? '',
          'comment': '',
          'transaction_id': _txn(),
        },
      ),
      title,
    );
  }

  Future<void> _doRename() async {
    final currentUser = (_detail?['username'] ?? widget.username ?? '') as String;
    final ctl = TextEditingController(text: currentUser);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إعادة تسمية المشترك'),
          content: TextField(
            controller: ctl,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم الجديد',
              isDense: true,
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تغيير')),
          ],
        ),
      ),
    );
    final newName = ctl.text.trim();
    if (ok != true || newName.isEmpty || newName == currentUser) return;

    await _run(
      () => widget.api.sasUserActionFull(
        widget.companyId,
        widget.userId,
        'rename',
        {'new_username': newName},
      ),
      'تم تغيير الاسم',
    );
  }

  Future<void> _doPing() async {
    await _run(
      () => widget.api.sasUserActionFull(
        widget.companyId,
        widget.userId,
        'ping',
      ),
      'تم إرسال Ping',
    );
  }

  bool get _isEnabled => _detail?['enabled'] == 1 || _detail?['enabled'] == true;

  // ─── تعطيل/تفعيل الحساب ───
  Future<void> _doToggleEnabled() async {
    final disable = _isEnabled;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(disable ? 'تعطيل الحساب' : 'تفعيل الحساب'),
          content: Text(disable
              ? 'سيُمنع المشترك من الدخول حتى إعادة تفعيله. متابعة؟'
              : 'سيُعاد تفعيل حساب المشترك. متابعة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text(disable ? 'تعطيل' : 'تفعيل')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => widget.api.sasUpdateUser(widget.companyId, widget.userId, {'enabled': disable ? 0 : 1}),
      disable ? 'تم التعطيل' : 'تم التفعيل',
    );
  }

  // ─── تغيير كلمة مرور المشترك ───
  Future<void> _doChangePassword() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغيير كلمة مرور المشترك'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة', isDense: true),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    final pw = ctl.text.trim();
    if (ok != true || pw.isEmpty) return;
    await _run(
      () => widget.api.sasUpdateUser(widget.companyId, widget.userId, {'password': pw}),
      'تم تغيير كلمة المرور',
    );
  }

  // ─── تعديل بيانات المشترك ───
  Future<void> _doEditInfo() async {
    final fn = TextEditingController(text: _detail?['firstname']?.toString() ?? '');
    final ln = TextEditingController(text: _detail?['lastname']?.toString() ?? '');
    final ph = TextEditingController(text: _detail?['phone']?.toString() ?? '');
    final city = TextEditingController(text: _detail?['city']?.toString() ?? '');
    final addr = TextEditingController(text: _detail?['address']?.toString() ?? '');
    final notes = TextEditingController(text: _detail?['notes']?.toString() ?? '');
    Widget f(String label, TextEditingController c, {int lines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c, minLines: lines, maxLines: lines,
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل بيانات المشترك'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              f('الاسم الأول', fn), f('الاسم الثاني', ln), f('الهاتف', ph),
              f('المدينة', city), f('العنوان', addr), f('ملاحظات', notes, lines: 2),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(
      () => widget.api.sasUpdateUser(widget.companyId, widget.userId, {
        'firstname': fn.text.trim(), 'lastname': ln.text.trim(), 'phone': ph.text.trim(),
        'city': city.text.trim(), 'address': addr.text.trim(), 'notes': notes.text.trim(),
      }),
      'تم تحديث البيانات',
    );
  }

  // ─── إدارة عناوين MAC المسموحة ───
  Future<void> _doManageMac() async {
    final macs = TextEditingController(text: _detail?['allowed_macs']?.toString() ?? '');
    bool macAuth = _detail?['mac_auth'] == 1 || _detail?['mac_auth'] == true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('عناوين MAC المسموحة'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ربط الحساب بعناوين MAC (mac_auth)'),
                value: macAuth,
                onChanged: (v) => setD(() => macAuth = v),
              ),
              TextField(
                controller: macs,
                decoration: const InputDecoration(
                  labelText: 'العناوين (افصل بينها بفاصلة)',
                  hintText: 'AA:BB:CC:DD:EE:FF, 11:22:33:44:55:66',
                  isDense: true,
                ),
              ),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    final v = macs.text.trim();
    await _run(
      () => widget.api.sasUpdateUser(widget.companyId, widget.userId, {
        'mac_auth': macAuth ? 1 : 0,
        'allowed_macs': v.isEmpty ? null : v,
      }),
      'تم تحديث عناوين MAC',
    );
  }

  Future<void> _doDelete() async {
    // تأكيد مزدوج للإجراء الخطير
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'حذف المشترك',
            style: TextStyle(color: context.pal.danger),
          ),
          content: Text(
            'سيُحذف المشترك «${_detail?['username'] ?? widget.userId}» نهائياً من SAS. '
            'هذا الإجراء لا يمكن التراجع عنه.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.pal.danger,
                side: BorderSide(color: context.pal.danger),
              ),
              child: const Text('متأكد، تابع'),
            ),
          ],
        ),
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            'تأكيد نهائي',
            style: TextStyle(color: context.pal.danger),
          ),
          content: const Text('هل أنت متأكد تماماً؟ الحذف دائم.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('لا، إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: context.pal.danger,
              ),
              child: const Text('نعم، احذف'),
            ),
          ],
        ),
      ),
    );
    if (second != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.api.sasDeleteUser(widget.companyId, widget.userId);
      if (mounted) {
        toast(context, 'تم حذف المشترك', kind: BannerKind.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) toast(context, 'فشل الحذف: $e', kind: BannerKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRefund() async {
    // 1) جلب بيانات الاسترداد لعرضها قبل التأكيد
    Map<String, dynamic> data = const {};
    try {
      final r = await widget.api.sasRefundData(widget.companyId, widget.userId);
      data = (r['data'] is Map) ? (r['data'] as Map<String, dynamic>) : r;
    } catch (e) {
      if (mounted) toast(context, 'تعذّر جلب بيانات الاسترداد: $e', kind: BannerKind.error);
      return;
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('إلغاء الخدمة واسترداد الرصيد',
              style: TextStyle(color: context.pal.warning)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _refundRow(ctx, 'المبلغ المسترد', data['refund_amount']),
              _refundRow(ctx, 'سعر الباقة', data['price']),
              _refundRow(ctx, 'الأيام المتبقية', data['remaining_days']),
              _refundRow(ctx, 'الباقة', data['profile_name']),
              const SizedBox(height: Space.md),
              const Text('سيُلغى اشتراك المشترك ويُسترد المبلغ أعلاه. متابعة؟'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: context.pal.warning),
              child: const Text('تأكيد الاسترداد'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    await _run(
      () => widget.api.sasRefund(widget.companyId, widget.userId),
      'تم إلغاء الخدمة والاسترداد',
    );
  }

  Widget _refundRow(BuildContext ctx, String label, dynamic value) {
    if (value == null || '$value'.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text('$label: ',
            style: TextStyle(color: ctx.pal.textMuted, fontSize: 13)),
        Flexible(child: Text('$value',
            style: const TextStyle(fontWeight: FontWeight.w700))),
      ]),
    );
  }

  // ─── مساعد حوار مبلغ/قيمة ───

  Future<bool> _showAmountDialog(
    String title,
    String fieldLabel,
    TextEditingController ctl,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: fieldLabel, isDense: true),
            autofocus: true,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تنفيذ')),
          ],
        ),
      ),
    );
    return ok == true;
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
    default:
      return '$status' == 'null' ? '—' : '$status';
  }
}

String _statusKey(dynamic status) {
  if (status is Map) return status['status'] == true ? 'active' : 'expired';
  final s = '$status';
  if (s == 'true' || s == 'active') return 'active';
  if (s == 'expired' || s == 'false') return 'expired';
  return s;
}

IconData _statusIcon(dynamic status) {
  final key = _statusKey(status);
  switch (key) {
    case 'active':
      return PhosphorIconsBold.checkCircle;
    case 'expired':
      return PhosphorIconsBold.xCircle;
    default:
      return PhosphorIconsBold.minusCircle;
  }
}

// ─── نموذج حقل داخلي ───

class _FieldVal {
  final String label;
  final dynamic value;
  final bool mono;
  const _FieldVal({required this.label, required this.value, this.mono = false});
}

// ─── جسم تبويب السجلّ ───

class _HistoryTabBody extends StatelessWidget {
  final List<Map<String, dynamic>>? rows;
  final String? error;
  const _HistoryTabBody({this.rows, this.error});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;

    if (error != null) {
      return Center(child: PBanner.error('تعذّر جلب السجلّ: $error'));
    }
    if (rows == null) {
      return const LoadingView();
    }
    if (rows!.isEmpty) {
      return const EmptyView(
        icon: PhosphorIconsDuotone.clockCounterClockwise,
        title: 'لا سجلّات',
        subtitle: 'لا أحداث مسجّلة لهذا المشترك.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Space.sm),
      itemCount: rows!.length,
      separatorBuilder: (_, __) => Divider(color: pal.outline, height: 1),
      itemBuilder: (ctx, i) {
        final row = rows![i];
        final event = (row['event'] ?? row['action'] ?? '—') as String;
        final desc = (row['description'] ?? row['details'] ?? '') as String;
        final date = (row['created_at'] ?? '') as String;
        final manager = row['manager_details'];
        return ListTile(
          dense: true,
          leading: Icon(PhosphorIconsBold.clockCounterClockwise,
              size: 16, color: pal.accent),
          title: Text(event, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: desc.isNotEmpty
              ? Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis)
              : null,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                date,
                style: PlatformType.mono(size: 11, color: pal.textMuted),
              ),
              if (manager != null)
                Text('بواسطة: $manager',
                    style: t.bodySmall?.copyWith(color: pal.textMuted)),
            ],
          ),
        );
      },
    );
  }
}

// ─── جسم تبويب القيود ───

class _JournalTabBody extends StatelessWidget {
  final List<Map<String, dynamic>>? rows;
  final String? error;
  const _JournalTabBody({this.rows, this.error});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;

    if (error != null) {
      return Center(child: PBanner.error('تعذّر جلب القيود: $error'));
    }
    if (rows == null) return const LoadingView();
    if (rows!.isEmpty) {
      return const EmptyView(
        icon: PhosphorIconsDuotone.receipt,
        title: 'لا قيود مالية',
        subtitle: 'لا حركات مالية مسجّلة.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(Space.sm),
      itemCount: rows!.length,
      separatorBuilder: (_, __) => Divider(color: pal.outline, height: 1),
      itemBuilder: (ctx, i) {
        final row = rows![i];
        final type = (row['type'] ?? row['action'] ?? '—') as String;
        final amount = row['amount'] ?? row['value'];
        final date = (row['created_at'] ?? '') as String;
        final note = (row['note'] ?? row['description'] ?? '') as String;
        final isPositive = (amount is num) ? amount > 0 : false;
        final amountColor = isPositive ? pal.success : pal.danger;

        return ListTile(
          dense: true,
          leading: Icon(
            isPositive
                ? PhosphorIconsBold.arrowCircleUp
                : PhosphorIconsBold.arrowCircleDown,
            size: 16,
            color: amountColor,
          ),
          title: Text(type, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: note.isNotEmpty ? Text(note) : null,
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (amount != null)
                Text(
                  '${isPositive ? '+' : ''}$amount',
                  style: PlatformType.mono(
                      size: 13,
                      weight: FontWeight.w700,
                      color: amountColor),
                ),
              Text(date,
                  style: PlatformType.mono(size: 11, color: pal.textMuted)),
            ],
          ),
        );
      },
    );
  }
}

// ─── جسم تبويب «متقدّم»: MAC + سمات Radius المخصّصة ───

class _AdvancedTabBody extends StatelessWidget {
  final List<Map<String, dynamic>>? macRows;
  final List<Map<String, dynamic>>? radiusRows;
  final String? error;
  const _AdvancedTabBody({this.macRows, this.radiusRows, this.error});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;

    if (error != null) {
      return Center(child: PBanner.error('تعذّر جلب البيانات المتقدّمة: $error'));
    }
    if (macRows == null && radiusRows == null) return const LoadingView();

    final macs = macRows ?? const [];
    final radius = radiusRows ?? const [];
    if (macs.isEmpty && radius.isEmpty) {
      return const EmptyView(
        icon: PhosphorIconsDuotone.identificationCard,
        title: 'لا بيانات متقدّمة',
        subtitle: 'لا عناوين MAC أو سمات Radius مخصّصة لهذا المشترك.',
      );
    }

    Widget header(IconData icon, String title) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.sm, Space.md, Space.sm, Space.xs),
          child: Row(children: [
            Icon(icon, size: 16, color: pal.accent),
            const SizedBox(width: Space.xs),
            Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.all(Space.sm),
      children: [
        header(PhosphorIconsBold.deviceMobile, 'عناوين MAC'),
        if (macs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Text('لا عناوين MAC', style: t.bodySmall?.copyWith(color: pal.textMuted)),
          )
        else
          for (final m in macs)
            ListTile(
              dense: true,
              leading: Icon(PhosphorIconsBold.deviceMobile, size: 16, color: pal.info),
              title: Directionality(
                textDirection: TextDirection.ltr,
                child: Text('${m['mac'] ?? m['callingstationid'] ?? m['value'] ?? m}',
                    style: PlatformType.mono(size: 13, color: pal.text)),
              ),
            ),
        Divider(color: pal.outline),
        header(PhosphorIconsBold.slidersHorizontal, 'سمات Radius المخصّصة'),
        if (radius.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Text('لا سمات مخصّصة', style: t.bodySmall?.copyWith(color: pal.textMuted)),
          )
        else
          for (final r in radius)
            ListTile(
              dense: true,
              leading: Icon(PhosphorIconsBold.slidersHorizontal, size: 16, color: pal.accent),
              title: Text('${r['attribute'] ?? r['name'] ?? r['key'] ?? '—'}',
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              subtitle: Text('${r['value'] ?? r['op'] ?? ''}'),
            ),
      ],
    );
  }
}

// ─── جسم تبويب الترافيك ───

class _TrafficTabBody extends StatelessWidget {
  final Map<String, dynamic>? data;
  final String? error;
  const _TrafficTabBody({this.data, this.error});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;

    if (error != null) {
      return Center(child: PBanner.error('تعذّر جلب الترافيك: $error'));
    }
    if (data == null) return const LoadingView();

    // استخراج القائمة إن وُجدت أو عرض الحقول كـ KV
    final listData = data!['data'];
    if (listData is List && listData.isNotEmpty) {
      final rows = listData.cast<Map<String, dynamic>>();
      return ListView.separated(
        padding: const EdgeInsets.all(Space.sm),
        itemCount: rows.length,
        separatorBuilder: (_, __) => Divider(color: pal.outline, height: 1),
        itemBuilder: (ctx, i) {
          final row = rows[i];
          final date = (row['date'] ?? row['created_at'] ?? '—') as String;
          final rx = row['rx'] ?? row['download'];
          final tx = row['tx'] ?? row['upload'];
          return ListTile(
            dense: true,
            leading: Icon(PhosphorIconsBold.wifiHigh, size: 16, color: pal.info),
            title: Text(date, style: PlatformType.mono(size: 13)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (rx != null) ...[
                  Icon(PhosphorIconsBold.arrowDown, size: 12, color: pal.success),
                  Text('$rx', style: PlatformType.num(color: pal.success)),
                  const SizedBox(width: Space.sm),
                ],
                if (tx != null) ...[
                  Icon(PhosphorIconsBold.arrowUp, size: 12, color: pal.info),
                  Text('$tx', style: PlatformType.num(color: pal.info)),
                ],
              ],
            ),
          );
        },
      );
    }

    // عرض الحقول كـ KV إن لم تكن قائمة
    final fields = <MapEntry<String, dynamic>>[];
    for (final e in data!.entries) {
      if (e.key != 'data') fields.add(e);
    }
    if (fields.isEmpty) {
      return const EmptyView(
        icon: PhosphorIconsDuotone.wifiSlash,
        title: 'لا بيانات ترافيك',
        subtitle: 'لا سجلّات ترافيك متاحة لهذا المشترك.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(Space.md),
      children: [
        for (final e in fields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text('${e.key}: ',
                    style: t.bodySmall?.copyWith(color: pal.textMuted)),
                Flexible(
                  child: Text(
                    '${e.value ?? '—'}',
                    style: PlatformType.mono(size: 13, color: pal.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// تبويب قائمة عام لمشترك (جلسات/فواتير/…) — يجلب index/{Entity}/{userId} ويعرض صفوفه.
class _SubListTab extends StatefulWidget {
  final StaffApi api;
  final int cid;
  final String path;
  final List<(String, String)> cols;
  const _SubListTab({required this.api, required this.cid, required this.path, required this.cols});
  @override
  State<_SubListTab> createState() => _SubListTabState();
}

class _SubListTabState extends State<_SubListTab> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.sasPostList(widget.cid, widget.path,
          {'page': 1, 'count': 30, 'direction': 'desc', 'search': ''});
      final data = (r is Map ? (r['data'] as List?) : (r as List?)) ?? const [];
      if (!mounted) return;
      setState(() {
        _rows = data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(16),
          child: Text('تعذّر الجلب: $_error', style: TextStyle(color: pal.danger))));
    }
    if (_rows.isEmpty) return const Center(child: Text('لا سجلّات'));
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: _rows.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: pal.outline),
      itemBuilder: (_, i) {
        final row = _rows[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in widget.cols)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 92,
                      child: Text(c.$2, style: TextStyle(color: pal.textMuted, fontSize: 12))),
                  Expanded(child: Text(
                      row[c.$1] == null || '${row[c.$1]}'.isEmpty ? '—' : '${row[c.$1]}',
                      style: const TextStyle(fontSize: 12.5))),
                ]),
              ),
          ]),
        );
      },
    );
  }
}
