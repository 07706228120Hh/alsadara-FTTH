import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat, DateFormat;
import '../../frontend/frontend.dart';
import '../../services/ftth_connect_service.dart';
import '../../services/linked_accounts_service.dart';
import 'ftth_add_operator_page.dart';

/// صفحة إدارة مشغّلي شريك FTTH مختار: قائمة + تعديل + شحن محفظة + إضافة.
/// كل العمليات تمرّ باعتماد الشريك المختار (توكن مؤقّت من بوّابة الصدارة).
/// الحذف غير مُفعَّل بعد (ينتظر التقاط عقده من البوابة).
class FtthOperatorsManagePage extends StatefulWidget {
  const FtthOperatorsManagePage({super.key});

  @override
  State<FtthOperatorsManagePage> createState() =>
      _FtthOperatorsManagePageState();
}

class _FtthOperatorsManagePageState extends State<FtthOperatorsManagePage> {
  final _ftth = FtthConnectService.instance;
  final _linked = LinkedAccountsService.instance;
  final _currency = NumberFormat('#,##0', 'en_US');

  bool _loadingPartners = true;
  String? _partnersError;
  List<Map<String, dynamic>> _partners = [];
  Map<String, dynamic>? _selectedPartner;
  String? _token;
  String? _serverUrl;

  bool _loadingData = false;
  String? _dataError;
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _zones = []; // {id, name}
  List<Map<String, dynamic>> _policies = [];
  List<Map<String, dynamic>> _members = [];

  // بحث وتصفية
  final _searchCtrl = TextEditingController();
  String _search = '';
  bool _onlyLowBalance = false;
  String? _roleFilter; // null = كل الأدوار
  static const double _lowBalanceThreshold = 1000000; // أقل من مليون = يحتاج شحن

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  double _memberBalance(Map<String, dynamic> m) =>
      ((m['walletSetup'] as Map?)?['balance'] as num?)?.toDouble() ?? 0;

  String _memberName(Map<String, dynamic> m) {
    final n = '${m['firstName'] ?? ''} ${m['lastName'] ?? ''}'.trim();
    return n.isNotEmpty ? n : (m['username']?.toString() ?? '');
  }

  String _roleName(Map<String, dynamic> m) =>
      (m['role'] as Map?)?['displayValue']?.toString() ??
      (m['role'] as Map?)?['name']?.toString() ??
      '';

  // أدوار متاحة للفلترة (بالترتيب الأبجدي، بلا الحساب الرئيسي).
  List<String> get _availableRoles {
    final s = <String>{};
    for (final m in _members) {
      if (m['isMainPartner'] == true) continue;
      final r = _roleName(m);
      if (r.isNotEmpty) s.add(r);
    }
    final list = s.toList()..sort();
    return list;
  }

  // يحتاج محفظة مموّلة = دور مالي مقيّد بمناطق (ZoneAdmin): monetary=true & allZones=false.
  // يستثني SuperAdmin (allZones=true) والفني (monetary=false) — لا يحتاجون رصيداً.
  bool _needsWallet(Map<String, dynamic> m) {
    if (m['isMainPartner'] == true) return false;
    final role = m['role'] as Map?;
    return role?['canPerformMonetaryAction'] == true &&
        role?['canAccessAllPartnerZones'] != true;
  }

  // رصيد منخفض = يحتاج محفظة ورصيده < الحد.
  bool _isLow(Map<String, dynamic> m) =>
      _needsWallet(m) && _memberBalance(m) < _lowBalanceThreshold;

  List<Map<String, dynamic>> get _filteredMembers {
    final q = _search.trim().toLowerCase();
    final list = _members.where((m) {
      if (_onlyLowBalance && !_isLow(m)) return false;
      if (_roleFilter != null && _roleName(m) != _roleFilter) return false;
      if (q.isEmpty) return true;
      final first = (m['firstName']?.toString() ?? '');
      final last = (m['lastName']?.toString() ?? '');
      final hay = '$first $last ${m['username'] ?? ''} ${m['phoneNumber'] ?? ''}'
          .toLowerCase();
      return hay.contains(q);
    }).toList();
    // ترتيب ذكي: الحساب الرئيسي أولاً، ثم المحتاجون للشحن (الأقل رصيداً أولاً)، ثم أبجدياً.
    list.sort((a, b) {
      final am = a['isMainPartner'] == true ? 0 : 1;
      final bm = b['isMainPartner'] == true ? 0 : 1;
      if (am != bm) return am - bm;
      final al = _isLow(a) ? 0 : 1;
      final bl = _isLow(b) ? 0 : 1;
      if (al != bl) return al - bl;
      if (al == 0) return _memberBalance(a).compareTo(_memberBalance(b));
      return _memberName(a).compareTo(_memberName(b));
    });
    return list;
  }

  // ملخّص مالي
  double get _totalBalance =>
      _members.fold(0.0, (s, m) => s + _memberBalance(m));
  int get _lowCount => _members.where(_isLow).length;
  int get _operatorsCount =>
      _members.where((m) => m['isMainPartner'] != true).length;

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  // ─── شركاء ───
  Future<void> _loadPartners() async {
    setState(() {
      _loadingPartners = true;
      _partnersError = null;
    });
    try {
      final res = await _linked.getPartners();
      if (!mounted) return;
      if (res['success'] == true) {
        _partners = _asList(res['data'])
            .where((p) => (p['isActive'] ?? true) != false)
            .toList();
        setState(() => _loadingPartners = false);
        if (_partners.length == 1) _onPartnerChanged(_partners.first);
      } else {
        setState(() {
          _partnersError = res['message']?.toString() ?? 'تعذّر جلب الشركاء';
          _loadingPartners = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _partnersError = 'تعذّر جلب الشركاء';
        _loadingPartners = false;
      });
    }
  }

  List<Map<String, dynamic>> _asList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map) {
      final inner = data['data'] ?? data['items'];
      if (inner is List) {
        return inner
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  Future<void> _onPartnerChanged(Map<String, dynamic>? p) async {
    if (p == null) return;
    setState(() {
      _selectedPartner = p;
      _token = null;
      _serverUrl = null;
      _roles = [];
      _zones = [];
      _policies = [];
      _members = [];
      _loadingData = true;
      _dataError = null;
    });
    try {
      final login = await _linked.loginPartner(p['id'].toString());
      if (!mounted) return;
      if (login['success'] != true) {
        throw Exception(login['message']?.toString() ?? 'فشل الدخول');
      }
      final raw = login['data'];
      final payload = (raw is Map && raw['data'] is Map)
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
      _token = payload['accessToken']?.toString();
      _serverUrl =
          payload['serverUrl']?.toString() ?? p['serverUrl']?.toString();
      if (_token == null || _token!.isEmpty) {
        throw Exception('لم يُعِد الخادم توكناً');
      }
      await _reload();
      if (mounted) setState(() => _loadingData = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _dataError =
            'تعذّر تحميل بيانات الشريك — تأكّد من صحّة اعتماد الحساب الرئيسي';
        _loadingData = false;
      });
    }
  }

  /// تحميل الأدوار/المناطق/السياسة + أعضاء الفريق للشريك الحالي.
  Future<void> _reload() async {
    final results = await Future.wait([
      _ftth.getTeamRoles(token: _token, baseUrl: _serverUrl),
      _ftth.getZones(token: _token, baseUrl: _serverUrl),
      _ftth.getPasswordPolicies(token: _token, baseUrl: _serverUrl),
      _fetchAllMembers(),
    ]);
    if (!mounted) return;
    _roles = results[0];
    _zones = _normalizeZones(results[1]);
    _policies = results[2];
    _members = results[3];
  }

  /// جلب كل المشغّلين عبر الصفحات (pageSize=50 لتفادي حجب الـWAF للصفحات الكبيرة).
  Future<List<Map<String, dynamic>>> _fetchAllMembers() async {
    const size = 50;
    final all = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final res = await _ftth.getTeamMembers(
          token: _token, baseUrl: _serverUrl, pageNumber: page, pageSize: size);
      final items = List<Map<String, dynamic>>.from(res['items'] ?? []);
      all.addAll(items);
      final total = (res['totalCount'] as num?)?.toInt() ?? all.length;
      if (items.length < size || all.length >= total || page >= 50) break;
      page++;
    }
    return all;
  }

  Future<void> _refreshMembers() async {
    try {
      final all = await _fetchAllMembers();
      if (!mounted) return;
      setState(() => _members = all);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _normalizeZones(List<Map<String, dynamic>> raw) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final z in raw) {
      final self = z['self'] as Map<String, dynamic>?;
      final id = (self?['id'] ?? z['id'] ?? z['zoneId'])?.toString() ?? '';
      final name = (self?['displayValue'] ??
                  z['displayValue'] ??
                  z['zoneName'] ??
                  z['name'] ??
                  id)
              ?.toString() ??
          id;
      if (id.isEmpty || !seen.add(id)) continue;
      out.add({'id': id, 'name': name});
    }
    return out;
  }

  void _snack(String msg, SdStatus status) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: status.tone.base,
    ));
  }

  void _copy(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    _snack('نُسخ $label', SdStatus.success);
  }

  /// آخر دخول بصيغة عربية موجزة، أو null إن لم يدخل.
  String? _formatLastLogin(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return null;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
    return DateFormat('yyyy/MM/dd', 'en_US').format(dt);
  }

  // ═══════════════════════════════════════════
  //  إضافة
  // ═══════════════════════════════════════════
  Future<void> _openAdd() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const FtthAddOperatorPage()),
    );
    if (created == true) _refreshMembers();
  }

  // ═══════════════════════════════════════════
  //  تعديل
  // ═══════════════════════════════════════════
  Future<void> _openEdit(Map<String, dynamic> member) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _EditOperatorPage(
          member: member,
          roles: _roles,
          zones: _zones,
          policies: _policies,
          token: _token,
          baseUrl: _serverUrl,
        ),
      ),
    );
    if (saved == true) {
      _snack('تم حفظ التعديلات', SdStatus.success);
      _refreshMembers();
    }
  }

  // ═══════════════════════════════════════════
  //  شحن المحفظة
  // ═══════════════════════════════════════════
  Future<void> _openTopUp(Map<String, dynamic> member) async {
    final amountCtrl = TextEditingController();
    final username = member['username']?.toString() ?? '';
    final currentBalance =
        ((member['walletSetup'] as Map?)?['balance'] as num?)?.toDouble() ?? 0;

    final amount = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('شحن محفظة المشغّل',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: StatefulBuilder(
          builder: (ctx, setD) {
            final entered = num.tryParse(amountCtrl.text.trim()) ?? 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المشغّل: $username',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        color: SdColors.muted)),
                Text('الرصيد الحالي: ${_currency.format(currentBalance)} د.ع',
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        color: SdColors.muted)),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setD(() {}),
                  decoration: _dec('مبلغ الشحن (د.ع)', hint: '0'),
                ),
                const SizedBox(height: 10),
                if (entered > 0)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: SdColors.warningTint,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SdColors.warningTintEdge),
                    ),
                    child: Text(
                      '⚠️ سيُخصم ${_currency.format(entered)} د.ع من محفظة الشريك الرئيسية ويُضاف للمشغّل. الرصيد الجديد ≈ ${_currency.format(currentBalance + entered)}.',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8D6E00)),
                    ),
                  ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () {
              final v = num.tryParse(amountCtrl.text.trim()) ?? 0;
              if (v <= 0) return;
              Navigator.pop(ctx, v);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.accent, foregroundColor: Colors.white),
            child: const Text('تأكيد الشحن',
                style:
                    TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (amount == null) return;
    final result = await _ftth.refillTeamMemberWallet(
      id: member['id'].toString(),
      amount: amount,
      token: _token,
      baseUrl: _serverUrl,
    );
    if (!mounted) return;
    if (result['success'] == true) {
      _snack('تم شحن ${_currency.format(amount)} د.ع', SdStatus.success);
      _refreshMembers();
    } else {
      _snack(result['error']?.toString() ?? 'فشل الشحن', SdStatus.danger);
    }
  }

  // ═══════════════════════════════════════════
  //  البناء
  // ═══════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return SdPage(
      scrollable: false,
      padding: EdgeInsets.zero,
      maxWidth: double.infinity,
      appBar: SdAppBar(
        title: 'إدارة المشغّلين',
        actions: [
          if (_selectedPartner != null && !_loadingData)
            SdAppBarAction(
              icon: Icons.refresh,
              label: 'تحديث',
              onPressed: _refreshMembers,
            ),
          SdAppBarAction(
            icon: Icons.person_add_alt_1,
            label: 'إضافة مشغّل',
            success: true,
            onPressed: _openAdd,
          ),
        ],
      ),
      body: _loadingPartners
          ? const Center(child: CircularProgressIndicator())
          : _partnersError != null
              ? Center(
                  child: SdEmptyState(
                    title: _partnersError!,
                    icon: Icons.error_outline,
                    status: SdStatus.danger,
                    action: SdButton(
                        label: 'إعادة المحاولة',
                        icon: Icons.refresh,
                        onPressed: _loadPartners),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      child: _partnerDropdown(),
                    ),
                    Expanded(child: _membersArea()),
                  ],
                ),
    );
  }

  Widget _partnerDropdown() {
    if (_partners.isEmpty) {
      return const Text(
          'لا يوجد شركاء — أضِف شريكاً من «الشركاء الرئيسيون» أولاً.',
          style: TextStyle(fontFamily: 'Cairo', color: SdColors.faint));
    }
    return DropdownButtonFormField<Map<String, dynamic>>(
      value: _selectedPartner,
      isExpanded: true,
      decoration: _dec('الشريك *'),
      items: _partners
          .map((p) => DropdownMenuItem(
                value: p,
                child: Text(
                    p['name']?.toString() ??
                        p['mainUsername']?.toString() ??
                        '-',
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13.5)),
              ))
          .toList(),
      onChanged: _onPartnerChanged,
    );
  }

  Widget _membersArea() {
    if (_selectedPartner == null) {
      return const Center(
        child: Text('اختر الشريك لعرض مشغّليه',
            style: TextStyle(fontFamily: 'Cairo', color: SdColors.muted)),
      );
    }
    if (_loadingData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_dataError != null) {
      return Center(
        child: SdEmptyState(
          title: _dataError!,
          icon: Icons.error_outline,
          status: SdStatus.danger,
          action: SdButton(
              label: 'إعادة المحاولة',
              icon: Icons.refresh,
              onPressed: () => _onPartnerChanged(_selectedPartner)),
        ),
      );
    }
    if (_members.isEmpty) {
      return const Center(child: SdEmptyState(title: 'لا يوجد مشغّلون'));
    }
    final list = _filteredMembers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryBar(),
        _searchBar(_lowCount),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshMembers,
            color: SdColors.accent,
            child: list.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(child: SdEmptyState(title: 'لا نتائج مطابقة')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _memberCard(list[i]),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _summaryBar() {
    Widget stat(IconData ic, String label, String value, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: SdColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SdColors.edge),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(ic, size: 14, color: c),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: c)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(label,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        color: SdColors.muted)),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Row(
        children: [
          stat(Icons.account_balance_wallet, 'إجمالي الأرصدة',
              '${_currency.format(_totalBalance)} د.ع', SdColors.success),
          const SizedBox(width: 8),
          stat(Icons.groups_2_outlined, 'المشغّلون', '$_operatorsCount',
              SdColors.accent),
          const SizedBox(width: 8),
          stat(Icons.error_outline, 'يحتاج شحن', '$_lowCount',
              _lowCount > 0 ? SdColors.danger : SdColors.muted),
        ],
      ),
    );
  }

  Widget _searchBar(int lowCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            decoration: _dec(
              'بحث بالاسم أو المستخدم أو الهاتف',
              suffix: _search.isEmpty
                  ? const Icon(Icons.search, color: SdColors.faint, size: 20)
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  selected: _onlyLowBalance,
                  onSelected: (v) => setState(() => _onlyLowBalance = v),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(Icons.warning_amber_rounded,
                      size: 16,
                      color: _onlyLowBalance ? Colors.white : SdColors.danger),
                  label: Text('رصيد منخفض ($lowCount)',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _onlyLowBalance
                              ? Colors.white
                              : SdColors.danger)),
                  backgroundColor: SdColors.dangerTint,
                  selectedColor: SdColors.danger,
                  side: const BorderSide(color: SdColors.dangerTintEdge),
                ),
                const SizedBox(width: 6),
                _roleChip('الكل', _roleFilter == null,
                    () => setState(() => _roleFilter = null)),
                for (final r in _availableRoles) ...[
                  const SizedBox(width: 6),
                  _roleChip(r, _roleFilter == r,
                      () => setState(() => _roleFilter = r)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
                'المعروض: ${_filteredMembers.length} / ${_operatorsCount + 1}',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 11.5, color: SdColors.muted)),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      label: Text(label,
          style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : SdColors.accent)),
      backgroundColor: SdColors.accentTint,
      selectedColor: SdColors.accent,
      side: const BorderSide(color: SdColors.accentTintEdge),
    );
  }

  Widget _memberCard(Map<String, dynamic> m) {
    final username = m['username']?.toString() ?? '-';
    final first = m['firstName']?.toString() ?? '';
    final last = m['lastName']?.toString() ?? '';
    final name = '$first $last'.trim();
    final phone = m['phoneNumber']?.toString() ?? '';
    final role = (m['role'] as Map?)?['displayValue']?.toString() ?? '-';
    final balance = _memberBalance(m);
    final isMain = m['isMainPartner'] == true;
    final hasWallet = _needsWallet(m);
    final zoneCount = (m['zoneIds'] as List?)?.length ?? 0;
    // الدور يحتاج مناطق صراحةً إذا لم يكن له وصول لكل مناطق الشريك.
    final needsZones =
        (m['role'] as Map?)?['canAccessAllPartnerZones'] != true && !isMain;
    final low = _isLow(m);
    final noName = name.isEmpty && !isMain;
    final lastLogin = _formatLastLogin(m['lastLoginAt']);

    return Container(
      decoration: BoxDecoration(
        color: low ? SdColors.dangerTint : SdColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: low ? SdColors.danger : SdColors.edge,
            width: low ? 1.3 : 1),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person,
                  color: low ? SdColors.danger : SdColors.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name.isNotEmpty ? name : username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
                        ),
                        if (noName) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: SdColors.warningTint,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: SdColors.warningTintEdge),
                            ),
                            child: const Text('بلا اسم',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: SdColors.warningText)),
                          ),
                        ],
                      ],
                    ),
                    InkWell(
                      onTap: () => _copy(username, 'اسم المستخدم'),
                      onLongPress: phone.isEmpty
                          ? null
                          : () => _copy(phone, 'رقم الهاتف'),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                                '$username${phone.isNotEmpty ? ' • $phone' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11.5,
                                    color: SdColors.muted)),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.copy,
                              size: 11, color: SdColors.faint),
                        ],
                      ),
                    ),
                    if (lastLogin != null)
                      Text('آخر دخول: $lastLogin',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10,
                              color: SdColors.faint)),
                  ],
                ),
              ),
              SdStatusChip(role, status: SdStatus.info),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasWallet || isMain)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_balance_wallet_outlined,
                              size: 16,
                              color: low ? SdColors.danger : SdColors.muted),
                          const SizedBox(width: 4),
                          Text('${_currency.format(balance)} د.ع',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: low
                                      ? SdColors.danger
                                      : (balance > 0
                                          ? SdColors.success
                                          : SdColors.faint))),
                          if (low) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.error_outline,
                                size: 14, color: SdColors.danger),
                            const Text(' يحتاج شحن',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: SdColors.danger)),
                          ],
                        ],
                      ),
                    if (needsZones)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map_outlined,
                              size: 15,
                              color: zoneCount == 0
                                  ? SdColors.danger
                                  : SdColors.muted),
                          const SizedBox(width: 3),
                          Text('$zoneCount منطقة',
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: zoneCount == 0
                                      ? SdColors.danger
                                      : SdColors.muted)),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (!isMain) ...[
                _smallBtn('تعديل', Icons.edit, SdColors.info,
                    () => _openEdit(m)),
                if (hasWallet) ...[
                  const SizedBox(width: 6),
                  _smallBtn('شحن', Icons.add_card, SdColors.accent,
                      () => _openTopUp(m)),
                ],
              ] else
                const Text('الحساب الرئيسي',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: SdColors.faint)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smallBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// حقل إدخال موحّد.
InputDecoration _dec(String label, {String? hint, Widget? suffix}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixIcon: suffix,
    labelStyle: const TextStyle(fontFamily: 'Cairo', color: SdColors.muted),
    hintStyle: const TextStyle(fontFamily: 'Cairo', color: SdColors.faint),
    filled: true,
    fillColor: SdColors.surface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: border(SdColors.edge),
    enabledBorder: border(SdColors.edge),
    focusedBorder: border(SdColors.accent, 1.5),
    errorBorder: border(SdColors.danger),
    focusedErrorBorder: border(SdColors.danger, 1.5),
  );
}

// ═══════════════════════════════════════════════════════════════════
//  صفحة تعديل مشغّل
// ═══════════════════════════════════════════════════════════════════
class _EditOperatorPage extends StatefulWidget {
  final Map<String, dynamic> member;
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> zones; // {id, name}
  final List<Map<String, dynamic>> policies;
  final String? token;
  final String? baseUrl;

  const _EditOperatorPage({
    required this.member,
    required this.roles,
    required this.zones,
    required this.policies,
    required this.token,
    required this.baseUrl,
  });

  @override
  State<_EditOperatorPage> createState() => _EditOperatorPageState();
}

class _EditOperatorPageState extends State<_EditOperatorPage> {
  final _ftth = FtthConnectService.instance;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _phoneCtrl;
  final _passwordCtrl = TextEditingController();

  Map<String, dynamic>? _role;
  final Set<String> _zones = {};
  bool _changePassword = false;
  bool _obscure = true;
  bool _saving = false;

  int _minLength = 8;
  bool _needUpper = false, _needLower = false, _needDigit = false;

  @override
  void initState() {
    super.initState();
    final m = widget.member;
    _firstCtrl = TextEditingController(text: m['firstName']?.toString() ?? '');
    _lastCtrl = TextEditingController(text: m['lastName']?.toString() ?? '');
    _phoneCtrl = TextEditingController(text: m['phoneNumber']?.toString() ?? '');
    // الدور الحالي: مطابقة بالـ id ضمن قائمة الأدوار
    final roleId = (m['role'] as Map?)?['id']?.toString();
    _role = widget.roles.firstWhere(
      (r) => r['id']?.toString() == roleId,
      orElse: () => <String, dynamic>{},
    );
    if (_role!.isEmpty) _role = null;
    final zoneIds = (m['zoneIds'] as List?)?.map((e) => e.toString()) ?? [];
    _zones.addAll(zoneIds);
    _applyPolicy();
    _passwordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _applyPolicy() {
    for (final p in widget.policies) {
      final t = (p['type'] as Map?)?['displayValue']?.toString() ?? '';
      final v = p['value']?.toString();
      switch (t) {
        case 'MinimumLength':
          _minLength = int.tryParse(v ?? '') ?? _minLength;
          break;
        case 'UppercaseCharacters':
          _needUpper = true;
          break;
        case 'LowercaseCharacters':
          _needLower = true;
          break;
        case 'Digits':
          _needDigit = true;
          break;
      }
    }
  }

  List<(String, bool)> get _passwordChecks {
    final p = _passwordCtrl.text;
    return [
      ('على الأقل $_minLength أحرف', p.length >= _minLength),
      if (_needUpper) ('حرف كبير (A-Z)', p.contains(RegExp(r'[A-Z]'))),
      if (_needLower) ('حرف صغير (a-z)', p.contains(RegExp(r'[a-z]'))),
      if (_needDigit) ('رقم (0-9)', p.contains(RegExp(r'[0-9]'))),
    ];
  }

  bool get _passwordValid => _passwordChecks.every((c) => c.$2);

  bool get _zonesRequired =>
      !((_role?['canAccessAllPartnerZones'] as bool?) ?? false);

  Future<void> _openZonePicker() async {
    final temp = Set<String>.from(_zones);
    final searchCtrl = TextEditingController();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final q = searchCtrl.text.trim().toLowerCase();
        final filtered = q.isEmpty
            ? widget.zones
            : widget.zones
                .where((z) => z['name'].toString().toLowerCase().contains(q))
                .toList();
        return AlertDialog(
          title: Row(children: [
            const Icon(Icons.map_outlined, color: SdColors.accent, size: 20),
            const SizedBox(width: 8),
            const Text('اختيار المناطق',
                style:
                    TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${temp.length} مختارة',
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    color: SdColors.accent,
                    fontWeight: FontWeight.w700)),
          ]),
          content: SizedBox(
            width: 460,
            height: 520,
            child: Column(children: [
              TextField(
                controller: searchCtrl,
                onChanged: (_) => setD(() {}),
                decoration: _dec('بحث عن منطقة...',
                    suffix: const Icon(Icons.search,
                        size: 18, color: SdColors.muted)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  onPressed: () => setD(() =>
                      temp.addAll(widget.zones.map((z) => z['id'].toString()))),
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('تحديد الكل',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: SdColors.accent),
                ),
                TextButton.icon(
                  onPressed: () => setD(() => temp.clear()),
                  icon: const Icon(Icons.remove_done, size: 18),
                  label: const Text('إلغاء تحديد الكل',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: SdColors.danger),
                ),
              ]),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text('لا توجد مناطق مطابقة',
                            style: TextStyle(
                                fontFamily: 'Cairo', color: SdColors.faint)))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final z = filtered[i];
                          final id = z['id'].toString();
                          return CheckboxListTile(
                            dense: true,
                            value: temp.contains(id),
                            activeColor: SdColors.accent,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(z['name'].toString(),
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 13)),
                            onChanged: (v) => setD(() {
                              if (v == true) {
                                temp.add(id);
                              } else {
                                temp.remove(id);
                              }
                            }),
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child:
                    const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, temp),
              style: ElevatedButton.styleFrom(
                  backgroundColor: SdColors.accent,
                  foregroundColor: Colors.white),
              child: Text('تم (${temp.length})',
                  style: const TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
            ),
          ],
        );
      }),
    );
    if (result != null) {
      setState(() {
        _zones
          ..clear()
          ..addAll(result);
      });
    }
  }

  void _snack(String msg, SdStatus status) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: status.tone.base,
    ));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_role == null) {
      _snack('اختر الدور', SdStatus.warning);
      return;
    }
    if (_changePassword && !_passwordValid) {
      _snack('كلمة المرور لا تطابق السياسة', SdStatus.warning);
      return;
    }
    if (_zonesRequired && _zones.isEmpty) {
      _snack('اختر منطقة واحدة على الأقل', SdStatus.warning);
      return;
    }

    // ── إرسال الحقول المتغيّرة فقط (نموذج «تعديل لكل حقل») ──
    // خادم FTTH يمسح الاسم عند أي طلب يغيّر الزونات؛ لذلك نفصل الاهتمامات:
    // لا نُرسل zoneIds إلا إذا تغيّرت فعلاً، ولا نُرسل الاسم إلا إذا تغيّر.
    final m = widget.member;
    final origFirst = (m['firstName']?.toString() ?? '').trim();
    final origLast = (m['lastName']?.toString() ?? '').trim();
    final origPhone = (m['phoneNumber']?.toString() ?? '').trim();
    final origRole = (m['role'] as Map?)?['id']?.toString();
    final origZones =
        ((m['zoneIds'] as List?)?.map((e) => e.toString()).toSet()) ??
            <String>{};

    final curFirst = _firstCtrl.text.trim();
    final curLast = _lastCtrl.text.trim();
    final curPhone = _phoneCtrl.text.trim();
    final curRole = _role!['id'].toString();
    final curZones = _zones;

    final nameChanged = curFirst != origFirst || curLast != origLast;
    final phoneChanged = curPhone != origPhone;
    final roleChanged = curRole != origRole;
    final zonesChanged = !_setEquals(curZones, origZones);

    if (!nameChanged &&
        !phoneChanged &&
        !roleChanged &&
        !zonesChanged &&
        !_changePassword) {
      setState(() => _saving = false);
      Navigator.of(context).pop(false);
      return;
    }

    // عند تغيير الزونات يُمسَح الاسم على الخادم ⇒ أعِد ختمه بالقيمة الحالية.
    final mustStampName = nameChanged || zonesChanged;
    setState(() => _saving = true);
    final result = await _ftth.updateTeamMember(
      id: widget.member['id'].toString(),
      firstName: mustStampName ? curFirst : null,
      lastName: mustStampName ? curLast : null,
      phoneNumber: phoneChanged ? curPhone : null,
      password: _changePassword ? _passwordCtrl.text : null,
      roleId: roleChanged ? curRole : null,
      zoneIds: (_zonesRequired && zonesChanged) ? curZones.toList() : null,
      token: widget.token,
      baseUrl: widget.baseUrl,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result['success'] == true) {
      Navigator.of(context).pop(true);
    } else {
      _snack(result['error']?.toString() ?? 'فشل الحفظ', SdStatus.danger);
    }
  }

  bool _setEquals(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  bool get _dirty {
    final m = widget.member;
    final origFirst = (m['firstName']?.toString() ?? '').trim();
    final origLast = (m['lastName']?.toString() ?? '').trim();
    final origPhone = (m['phoneNumber']?.toString() ?? '').trim();
    final origRole = (m['role'] as Map?)?['id']?.toString();
    final origZones =
        ((m['zoneIds'] as List?)?.map((e) => e.toString()).toSet()) ??
            <String>{};
    return _firstCtrl.text.trim() != origFirst ||
        _lastCtrl.text.trim() != origLast ||
        _phoneCtrl.text.trim() != origPhone ||
        (_role?['id']?.toString()) != origRole ||
        !_setEquals(_zones, origZones) ||
        _changePassword;
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغييرات غير محفوظة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: const Text('لديك تعديلات لم تُحفظ. هل تريد المغادرة وتجاهلها؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('البقاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: SdColors.danger,
                foregroundColor: Colors.white),
            child: const Text('تجاهل والمغادرة',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.member['username']?.toString() ?? '';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: SdPage(
        scrollable: true,
        maxWidth: 720,
        appBar: SdAppBar(title: 'تعديل: $username'),
        body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SdCard(
              title: 'المعلومات',
              icon: Icons.badge_outlined,
              child: Column(children: [
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstCtrl,
                      decoration: _dec('الاسم الأول'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastCtrl,
                      decoration: _dec('الاسم الأخير'),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                    LengthLimitingTextInputFormatter(14),
                  ],
                  decoration: _dec('رقم الهاتف *'),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'مطلوب';
                    if (s.replaceAll('+', '').length < 10) return 'رقم غير صحيح';
                    return null;
                  },
                ),
              ]),
            ),
            const SizedBox(height: 14),
            SdCard(
              title: 'الدور',
              icon: Icons.admin_panel_settings_outlined,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: DropdownButtonFormField<Map<String, dynamic>>(
                  value: _role,
                  isExpanded: true,
                  decoration: _dec('الدور *'),
                  items: widget.roles
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text(r['displayValue']?.toString() ?? '-',
                                style: const TextStyle(
                                    fontFamily: 'Cairo', fontSize: 13.5)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _role = v;
                    if (!_zonesRequired) _zones.clear();
                  }),
                  validator: (v) => v == null ? 'مطلوب' : null,
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (_zonesRequired)
              SdCard(
                title: 'المناطق *',
                icon: Icons.map_outlined,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: widget.zones.isEmpty ? null : _openZonePicker,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: SdColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: SdColors.edge),
                          ),
                          child: Row(children: [
                            const Icon(Icons.checklist_rtl,
                                size: 20, color: SdColors.muted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _zones.isEmpty
                                    ? 'اختر المناطق'
                                    : '${_zones.length} منطقة مختارة',
                                style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13.5,
                                    color: _zones.isEmpty
                                        ? SdColors.faint
                                        : SdColors.primary,
                                    fontWeight: _zones.isEmpty
                                        ? FontWeight.w400
                                        : FontWeight.w700),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down,
                                color: SdColors.muted),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const SdCard(
                title: 'المناطق',
                icon: Icons.public,
                child: Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('هذا الدور يصل إلى كل مناطق الشريك.',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12.5,
                          color: SdColors.muted)),
                ),
              ),
            const SizedBox(height: 14),
            SdCard(
              title: 'كلمة المرور',
              icon: Icons.lock_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(
                      child: Text('تغيير كلمة المرور',
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                    SdToggle(
                      value: _changePassword,
                      onChanged: (v) => setState(() => _changePassword = v),
                    ),
                  ]),
                  if (_changePassword) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      decoration: _dec('كلمة المرور الجديدة',
                          suffix: IconButton(
                            icon: Icon(
                                _obscure
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                size: 20,
                                color: SdColors.muted),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          )),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: _passwordChecks
                          .map((c) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                      c.$2
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      size: 15,
                                      color: c.$2
                                          ? SdColors.success
                                          : SdColors.faint),
                                  const SizedBox(width: 4),
                                  Text(c.$1,
                                      style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontSize: 11.5,
                                          color: c.$2
                                              ? SdColors.success
                                              : SdColors.muted)),
                                ],
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SdButton(
              label: 'حفظ التعديلات',
              icon: Icons.save,
              kind: SdButtonKind.accent,
              expand: true,
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
  }
}
