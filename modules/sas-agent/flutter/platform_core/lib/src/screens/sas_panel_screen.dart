import 'package:flutter/material.dart';

import '../api/staff_api.dart';
import 'sas_license_screen.dart';
import 'sas_manager_form.dart';
import 'sas_subscriber_detail.dart';
import 'sas_subscriber_form.dart';

/// تحويل آمن لرقم — SAS يُعيد بعض الحقول العددية كنصوص ("5160", "60746478").
num? _asNum(dynamic v) => v is num ? v : (v == null ? null : num.tryParse(v.toString()));

/// واجهة SAS الكاملة داخل المنصّة — تفتح كما تفتح لوحة SAS وتعرض/تدير بياناتها:
/// المشتركون (بحث/ترقيم/تفاصيل/إجراءات) · المتصلون الآن · الوكلاء · الباقات · المالية · صحّة النظام.
/// البيانات حيّة عبر بروكسي الباكند المعزول بالنطاق (شركة ترى شركتها، وكيل يرى مشتركيه).
class SasPanelScreen extends StatefulWidget {
  final StaffApi api;
  final int companyId;
  final bool isAgent;
  const SasPanelScreen({
    super.key,
    required this.api,
    required this.companyId,
    this.isAgent = false,
  });

  @override
  State<SasPanelScreen> createState() => _SasPanelScreenState();
}

class _SasPanelScreenState extends State<SasPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _summary;
  String? _summaryError;

  // تعدّد حسابات SAS للوكيل: قائمة الحسابات المضبوطة + الحساب المُختار (null = كل الحسابات).
  List<Map<String, dynamic>> _accounts = const [];
  int? _accountId;                     // الحساب المُختار للفلترة/التوجيه (null = دمج الكل)
  late StaffApi _scopedApi;            // نسخة API مُنطّقة بالحساب المُختار (تُحقن account_id تلقائياً)

  // الوكيل: 5 تبويبات (+ سجلّ الدخول + سجلّ النظام). الشركة: 8 (+ الوكلاء + المالية + صحّة النظام).
  int get _tabCount => widget.isAgent ? 5 : 8;

  /// حساب الإنشاء الافتراضي: المُختار، وإلا أول حساب مضبوط (لإنشاء مشترك في وضع «الكل»).
  int? get _createAccountId =>
      _accountId ?? (_accounts.isNotEmpty ? _accounts.first['id'] as int? : null);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
    _scopedApi = widget.api;
    _loadAccounts();
    _loadSummary();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    if (!widget.isAgent) return;       // الشركة/الجهة الرقابية: حساب واحد — لا محدّد
    try {
      final r = await widget.api.sasContextAccounts(widget.companyId);
      final all = ((r['accounts'] as List?) ?? const []).cast<Map<String, dynamic>>();
      final usable = all.where((a) => a['configured'] == true).toList();
      if (mounted) setState(() => _accounts = usable);
    } catch (_) {/* الفلتر تجميلي — تجاهل الفشل */}
  }

  void _setAccount(int? id) {
    setState(() {
      _accountId = id;
      _scopedApi = widget.api.scopedToSasAccount(id);
      _summary = null;
      _summaryError = null;
    });
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    try {
      final d = await _scopedApi.sasDashboard(widget.companyId);
      if (mounted) setState(() => _summary = d);
    } catch (e) {
      if (mounted) setState(() => _summaryError = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cid = widget.companyId;
    final api = _scopedApi;
    return Column(
      children: [
        _summaryBar(),
        if (widget.isAgent && _accounts.length > 1) _accountSelector(),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            const Tab(text: 'المشتركون'),
            const Tab(text: 'المتصلون الآن'),
            if (!widget.isAgent) const Tab(text: 'الوكلاء'),
            const Tab(text: 'الباقات'),
            const Tab(text: 'سجلّ الدخول'),
            const Tab(text: 'سجلّ النظام'),
            if (!widget.isAgent) const Tab(text: 'المالية'),
            if (!widget.isAgent) const Tab(text: 'صحّة النظام'),
          ],
        ),
        Expanded(
          // مفتاح الحساب: تبديل الحساب يُعيد بناء التبويبات فتُحمَّل من الحساب الجديد.
          child: KeyedSubtree(
            key: ValueKey<int?>(_accountId),
            child: TabBarView(
              controller: _tabs,
              children: [
                _SubscribersTab(api: api, cid: cid, isAgent: widget.isAgent,
                    createAccountId: _createAccountId),
                _OnlineTab(api: api, cid: cid),
                if (!widget.isAgent) _ManagersTab(api: api, cid: cid),
                _ProfilesTab(api: api, cid: cid),
                _LogTab(api: api, cid: cid, kind: _LogKind.auth),
                _LogTab(api: api, cid: cid, kind: _LogKind.syslog),
                if (!widget.isAgent) _FinanceTab(api: api, cid: cid),
                if (!widget.isAgent) _SystemHealthTab(api: api, cid: cid),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _accountSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [
        const Icon(Icons.filter_alt_outlined, size: 18),
        const SizedBox(width: 8),
        const Text('الحساب:'),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButton<int?>(
            isExpanded: true,
            value: _accountId,
            onChanged: _setAccount,
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('كل الحسابات (مدموجة)')),
              for (final a in _accounts)
                DropdownMenuItem<int?>(
                  value: a['id'] as int?,
                  child: Text('${a['label'] ?? a['sas_username'] ?? 'حساب'}',
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _summaryBar() {
    if (_summaryError != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text('تعذّر جلب ملخّص SAS: $_summaryError',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    final s = _summary;
    final items = <({String label, dynamic value, Color color})>[
      (label: 'الإجمالي', value: s?['total'], color: Colors.blueGrey),
      (label: 'نشط', value: s?['active'], color: Colors.green),
      (label: 'منتهٍ', value: s?['expired'], color: Colors.orange),
      (label: 'متصل الآن', value: s?['online'], color: Colors.teal),
      (label: 'غير متصل', value: s?['offline'], color: Colors.redAccent),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: _StatChip(label: it.label, value: s == null ? '…' : '${it.value ?? '-'}', color: it.color),
            ),
          if (!widget.isAgent)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SasLicenseScreen(
                    api: widget.api, companyId: widget.companyId),
                ),
              ),
              icon: const Icon(Icons.verified_user_outlined, size: 18),
              label: const Text('الترخيص'),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ─────────────────────────── تبويب المشتركين ───────────────────────────

class _SubscribersTab extends StatefulWidget {
  final StaffApi api;
  final int cid;
  final bool isAgent;
  final int? createAccountId;   // حساب SAS لإنشاء مشترك جديد تحته (وضع «الكل»)
  const _SubscribersTab({required this.api, required this.cid, required this.isAgent,
      this.createAccountId});

  @override
  State<_SubscribersTab> createState() => _SubscribersTabState();
}

class _SubscribersTabState extends State<_SubscribersTab> {
  final _rows = <Map<String, dynamic>>[];
  final _searchCtl = TextEditingController();
  int _page = 1;
  int _total = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _page = 1;
        _rows.clear();
      }
    });
    try {
      final r = await widget.api.sasUsers(widget.cid,
          page: _page, count: 50, search: _searchCtl.text.trim());
      setState(() {
        _rows.addAll(r.rows);
        _total = r.total;
        _page += 1;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtl,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _load(reset: true),
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم/المستخدم…',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => _load(reset: true),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _openCreate,
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('مشترك جديد'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('خطأ: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _rows.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                if (i == _rows.length) return _footer();
                return _SubscriberCard(
                  row: _rows[i],
                  onTap: () => _openDetail(_rows[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_rows.length < _total) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.expand_more),
            label: Text('تحميل المزيد (${_rows.length}/$_total)'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: Text('إجمالي المشتركين: $_total')),
    );
  }

  Future<void> _openCreate() async {
    // إنشاء المشترك يُوجَّه إلى حساب SAS محدّد (المُختار أو الافتراضي) لتجنّب الغموض.
    final api = widget.createAccountId != null
        ? widget.api.scopedToSasAccount(widget.createAccountId)
        : widget.api;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SasSubscriberForm(
          api: api,
          companyId: widget.cid,
          isAgent: widget.isAgent,
        ),
      ),
    );
    if (created == true) _load(reset: true);
  }

  void _openDetail(Map<String, dynamic> row) {
    final uid = _asNum(row['id'])?.toInt();
    if (uid == null) return;
    final username = (row['username'] as String?) ?? '';
    // توجيه كل عمليات التفاصيل إلى حساب المشترك المصدر (وسم الصفّ _account_id).
    final accId = _asNum(row['_account_id'])?.toInt();
    final api = accId != null ? widget.api.scopedToSasAccount(accId) : widget.api;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(username.isNotEmpty ? username : 'تفاصيل المشترك'),
          ),
          body: SasSubscriberDetail(
            api: api,
            companyId: widget.cid,
            userId: uid,
            isAgent: widget.isAgent,
            username: username,
          ),
        ),
      ),
    );
  }
}

/// استخراج نصّ حالة مقروء من حقل status (قد يكون Map مركّب في SAS).
String _statusLabel(dynamic status) {
  if (status is Map) {
    final active = status['status'] == true;
    return active ? 'نشط' : 'متوقّف';
  }
  if (status is String) return status;
  return '-';
}

Color _statusColor(dynamic status) {
  final active = (status is Map) ? status['status'] == true : status == 'active';
  return active ? Colors.green : Colors.redAccent;
}

String _profileName(Map<String, dynamic> row) {
  final p = row['profile_details'];
  if (p is Map && p['name'] != null) return '${p['name']}';
  return '${row['profile_id'] ?? row['profile'] ?? '-'}';
}

class _SubscriberCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;
  const _SubscriberCard({required this.row, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final online = row['online_status'] == true || row['online'] == true;
    final statusColor = _statusColor(row['status']);
    final name = ('${row['firstname'] ?? ''} ${row['lastname'] ?? ''}').trim();
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Icon(Icons.person, color: statusColor),
        ),
        title: Row(
          children: [
            Flexible(child: Text('${row['username'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis)),
            if (online) ...[
              const SizedBox(width: 6),
              const Icon(Icons.circle, size: 10, color: Colors.teal),
            ],
          ],
        ),
        subtitle: Text(
          '${name.isEmpty ? '' : '$name · '}باقة: ${_profileName(row)}'
          '${row['expiration'] != null ? ' · انتهاء: ${row['expiration']}' : ''}'
          '${(row['_account_label'] ?? '').toString().isNotEmpty ? ' · حساب: ${row['_account_label']}' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(_statusLabel(row['status']),
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ),
    );
  }
}

// ─────────────────────────── تفاصيل + إجراءات المشترك ───────────────────────────

class _SubscriberDetailSheet extends StatefulWidget {
  final StaffApi api;
  final int cid;
  final int uid;
  final Map<String, dynamic> listRow;
  final bool canManage;
  final VoidCallback onChanged;
  const _SubscriberDetailSheet({
    required this.api,
    required this.cid,
    required this.uid,
    required this.listRow,
    required this.canManage,
    required this.onChanged,
  });

  @override
  State<_SubscriberDetailSheet> createState() => _SubscriberDetailSheetState();
}

class _SubscriberDetailSheetState extends State<_SubscriberDetailSheet> {
  Map<String, dynamic>? _detail;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.sasUser(widget.cid, widget.uid);
      if (mounted) setState(() => _detail = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail ?? widget.listRow;
    final fields = _keyFields(d);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.teal.withValues(alpha: 0.15),
                child: const Icon(Icons.person, color: Colors.teal),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${d['username'] ?? '-'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text('${(d['firstname'] ?? '')} ${(d['lastname'] ?? '')}'.trim(),
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              if (_detail == null && _error == null)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Text('تعذّر جلب التفاصيل الكاملة: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (widget.canManage) _actionsBar(),
          const Divider(height: 24),
          for (final f in fields) _fieldRow(f.$1, f.$2),
        ],
      ),
    );
  }

  Widget _actionsBar() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _actBtn('تغيير الباقة', Icons.swap_horiz, _changeProfile),
        _actBtn('تمديد/تجديد', Icons.event_repeat, _extend),
        _actBtn('إضافة رصيد', Icons.add_card, () => _amountAction('deposit', 'إضافة رصيد')),
        _actBtn('سحب رصيد', Icons.money_off, () => _amountAction('withdraw', 'سحب رصيد')),
        _actBtn('تفعيل', Icons.play_arrow, () => _simpleAction('activate', 'تفعيل الخدمة')),
        _actBtn('Ping', Icons.wifi_tethering, () => _simpleAction('ping', 'اختبار اتصال')),
      ],
    );
  }

  Widget _actBtn(String label, IconData icon, VoidCallback onTap) {
    return FilledButton.tonalIcon(
      onPressed: _busy ? null : onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String ok) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      final msg = (res['message'] ?? res['status'] ?? ok).toString();
      _snack('تم: $msg');
      await _load();
      widget.onChanged();
    } catch (e) {
      _snack('فشل: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _simpleAction(String action, String title) async {
    final ok = await _confirm(title, 'تنفيذ «$title» على هذا المشترك؟');
    if (ok) await _run(() => widget.api.sasUserAction(widget.cid, widget.uid, action), title);
  }

  Future<void> _amountAction(String action, String title) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'المبلغ'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تنفيذ')),
        ],
      ),
    );
    final amount = double.tryParse(ctl.text.trim());
    if (ok == true && amount != null) {
      await _run(() => widget.api.sasUserAction(widget.cid, widget.uid, action,
          payload: {'amount': amount}), title);
    }
  }

  Future<void> _changeProfile() async {
    List<Map<String, dynamic>> profiles;
    try {
      profiles = await widget.api.sasProfiles(widget.cid);
    } catch (e) {
      _snack('تعذّر جلب الباقات: $e', error: true);
      return;
    }
    if (!mounted) return;
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('اختر الباقة الجديدة'),
        children: [
          for (final p in profiles)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, _asNum(p['id'])?.toInt()),
              child: Text('${p['name'] ?? p['id']}'),
            ),
        ],
      ),
    );
    if (chosen != null) {
      await _run(() => widget.api.sasUserAction(widget.cid, widget.uid, 'changeProfile',
          payload: {'profile_id': chosen}), 'تغيير الباقة');
    }
  }

  Future<void> _extend() async {
    final ctl = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تمديد/تجديد الخدمة'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'عدد الفترات/الأشهر'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تمديد')),
        ],
      ),
    );
    final n = int.tryParse(ctl.text.trim());
    if (ok == true && n != null) {
      await _run(() => widget.api.sasUserAction(widget.cid, widget.uid, 'extend',
          payload: {'periods': n, 'count': n}), 'تمديد الخدمة');
    }
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد')),
        ],
      ),
    );
    return ok == true;
  }

  Widget _fieldRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text('${value ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  List<(String, dynamic)> _keyFields(Map<String, dynamic> d) {
    dynamic v(String k) => d[k];
    return [
      ('المستخدم', v('username')),
      ('الاسم', '${v('firstname') ?? ''} ${v('lastname') ?? ''}'.trim()),
      ('الحالة', _statusLabel(v('status'))),
      ('الباقة', _profileName(d)),
      ('تاريخ الانتهاء', v('expiration')),
      ('الأيام المتبقية', v('remaining_days')),
      ('الوكيل (المالك)', v('parent_username') ?? v('parent_id')),
      ('الرصيد', v('balance')),
      ('الهاتف', v('phone')),
      ('البريد', v('email')),
      ('المدينة', v('city')),
      ('العنوان', v('address')),
      ('IP ثابت', v('static_ip')),
      ('آخر IP', v('last_ip_address')),
      ('آخر اتصال', v('last_online')),
      ('جلسات متزامنة', v('simultaneous_sessions')),
      ('رقم العقد', v('contract_id')),
      ('الهوية الوطنية', v('national_id')),
      ('ملاحظات', v('notes')),
      ('أُنشئ في', v('created_at')),
    ];
  }
}

// ─────────────────────────── تبويب المتصلين — مُثرى ───────────────────────────

class _OnlineTab extends StatefulWidget {
  final StaffApi api;
  final int cid;
  const _OnlineTab({required this.api, required this.cid});

  @override
  State<_OnlineTab> createState() => _OnlineTabState();
}

class _OnlineTabState extends State<_OnlineTab> {
  late Future<({List<Map<String, dynamic>> rows, int total})> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.sasOnline(widget.cid, count: 200);
  }

  void _reload() => setState(() => _future = widget.api.sasOnline(widget.cid, count: 200));

  /// تحويل ثواني إلى نص مقروء (أيام/ساعات/دقائق/ثواني).
  String _sessionDuration(dynamic secs) {
    final s = _asNum(secs)?.toInt() ?? 0;
    if (s <= 0) return '-';
    final d = s ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (d > 0) return '$dي $hس';
    if (h > 0) return '$hس $mد';
    if (m > 0) return '$mد $secث';
    return '$secث';
  }

  /// تحويل بايتات إلى MB أو GB مقروء.
  String _bytes(dynamic b) {
    final n = _asNum(b)?.toDouble() ?? 0.0;
    if (n <= 0) return '-';
    if (n >= 1073741824) return '${(n / 1073741824).toStringAsFixed(2)} GB';
    return '${(n / 1048576).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<Map<String, dynamic>> rows, int total})>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('خطأ: ${snap.error}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة')),
              ],
            ),
          );
        }
        final rows = snap.data?.rows ?? const [];
        final total = snap.data?.total ?? 0;
        if (rows.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                const SizedBox(height: 8),
                const Text('لا جلسات متصلة الآن'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تحديث')),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              if (i == rows.length) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Center(child: Text('الإجمالي المتصل: $total')),
                );
              }
              final s = rows[i];
              return _OnlineSessionCard(
                session: s,
                duration: _sessionDuration(s['acctsessiontime']),
                download: _bytes(s['acctoutputoctets']),
                upload: _bytes(s['acctinputoctets']),
              );
            },
          ),
        );
      },
    );
  }
}

class _OnlineSessionCard extends StatelessWidget {
  final Map<String, dynamic> session;
  final String duration;
  final String download;
  final String upload;
  const _OnlineSessionCard({
    required this.session,
    required this.duration,
    required this.download,
    required this.upload,
  });

  @override
  Widget build(BuildContext context) {
    final s = session;
    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الصف الأول: اسم المستخدم + الباقة
            Row(
              children: [
                const Icon(Icons.wifi, size: 18, color: Colors.teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${s['username'] ?? '-'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${s['user_profile_name'] ?? s['profile_id'] ?? '-'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // الصف الثاني: عناوين IP (اتجاه LTR دائماً)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _MonoLabel('IP المشترك', '${s['framedipaddress'] ?? '-'}', monoStyle),
                  _MonoLabel('NAS IP', '${s['nasipaddress'] ?? '-'}', monoStyle),
                  if (s['callingstationid'] != null)
                    _MonoLabel('MAC', '${s['callingstationid']}', monoStyle),
                  if (s['framedprotocol'] != null)
                    _MonoLabel('بروتوكول', '${s['framedprotocol']}', monoStyle),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // الصف الثالث: مدّة الجلسة + رفع/تنزيل + FUP
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _InfoChip(icon: Icons.timer_outlined, label: 'مدّة الجلسة', value: duration),
                _InfoChip(icon: Icons.download_outlined, label: 'تنزيل', value: download),
                _InfoChip(icon: Icons.upload_outlined, label: 'رفع', value: upload),
                if (s['fup'] != null)
                  _InfoChip(icon: Icons.data_usage, label: 'FUP', value: '${s['fup']}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonoLabel extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle monoStyle;
  const _MonoLabel(this.label, this.value, this.monoStyle);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: monoStyle),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.blueGrey),
        const SizedBox(width: 4),
        Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─────────────────────────── تبويب الوكلاء — إدارة كاملة ───────────────────────────

class _ManagersTab extends StatefulWidget {
  final StaffApi api;
  final int cid;
  const _ManagersTab({required this.api, required this.cid});

  @override
  State<_ManagersTab> createState() => _ManagersTabState();
}

class _ManagersTabState extends State<_ManagersTab> {
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.sasManagers(widget.cid, count: 500);
      if (mounted) {
        setState(() {
          _rows = r.rows;
          _total = r.total;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('خطأ: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة')),
          ],
        ),
      );
    }
    return Column(
      children: [
        // شريط أدوات علوي
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              Text('الوكلاء ($_total)',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openManagerForm(),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('وكيل جديد'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showTree,
                icon: const Icon(Icons.account_tree_outlined, size: 18),
                label: const Text('الشجرة الهرمية'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'تحديث',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _rows.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 80),
                      Center(child: Text('لا وكلاء — أضف وكيلاً جديداً')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _ManagerCard(
                      manager: _rows[i],
                      onTap: () => _openActions(_rows[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// فتح نموذج إضافة/تعديل وكيل.
  Future<void> _openManagerForm({Map<String, dynamic>? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => SasManagerForm(
          api: widget.api,
          companyId: widget.cid,
          existing: existing,
        ),
      ),
    );
    if (saved == true) _load();
  }

  /// فتح ورقة إجراءات الوكيل.
  void _openActions(Map<String, dynamic> m) {
    final mid = _asNum(m['id'])?.toInt();
    if (mid == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ManagerActionsSheet(
        api: widget.api,
        cid: widget.cid,
        mid: mid,
        manager: m,
        onChanged: _load,
        onEdit: () {
          Navigator.pop(context);            // أغلق الورقة ثم افتح نموذج التعديل
          _openManagerForm(existing: m);
        },
      ),
    );
  }

  /// عرض الشجرة الهرمية للوكلاء.
  Future<void> _showTree() async {
    dynamic tree;
    String? err;
    try {
      tree = await widget.api.sasGet(widget.cid, 'manager/tree');
    } catch (e) {
      err = '$e';
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('الشجرة الهرمية للوكلاء'),
        content: SizedBox(
          width: 400,
          height: 400,
          child: err != null
              ? Center(
                  child: Text('تعذّر جلب الشجرة: $err',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)))
              : _ManagerTree(data: tree),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
        ],
      ),
    );
  }
}

class _ManagerCard extends StatelessWidget {
  final Map<String, dynamic> manager;
  final VoidCallback onTap;
  const _ManagerCard({required this.manager, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = manager;
    final name = ('${m['firstname'] ?? ''} ${m['lastname'] ?? ''}').trim();
    final enabled = m['enabled'] != false;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: (enabled ? Colors.indigo : Colors.grey)
                        .withValues(alpha: 0.15),
                    child: Icon(Icons.badge,
                        color: enabled ? Colors.indigo : Colors.grey),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['username'] ?? '-'}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        if (name.isNotEmpty)
                          Text(name,
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  if (!enabled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('معطّل',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _MgrStat(icon: Icons.people, label: 'المشتركون',
                      value: '${m['users_count'] ?? 0}', color: Colors.teal),
                  _MgrStat(icon: Icons.account_balance_wallet, label: 'الرصيد',
                      value: '${m['balance'] ?? 0}', color: Colors.green),
                  _MgrStat(icon: Icons.stars, label: 'نقاط المكافأة',
                      value: '${m['reward_points'] ?? 0}', color: Colors.orange),
                  _MgrStat(icon: Icons.discount, label: 'الخصم',
                      value: '${m['discount_rate'] ?? 0}%', color: Colors.purple),
                  if (m['city'] != null)
                    _MgrStat(icon: Icons.location_city, label: 'المدينة',
                        value: '${m['city']}', color: Colors.blueGrey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MgrStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _MgrStat(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text('$label: ',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

/// ورقة إجراءات الوكيل (إيداع/سحب/نقاط/دين/حذف).
class _ManagerActionsSheet extends StatefulWidget {
  final StaffApi api;
  final int cid;
  final int mid;
  final Map<String, dynamic> manager;
  final VoidCallback onChanged;
  final VoidCallback onEdit;
  const _ManagerActionsSheet({
    required this.api,
    required this.cid,
    required this.mid,
    required this.manager,
    required this.onChanged,
    required this.onEdit,
  });

  @override
  State<_ManagerActionsSheet> createState() => _ManagerActionsSheetState();
}

class _ManagerActionsSheetState extends State<_ManagerActionsSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final name = ('${m['firstname'] ?? ''} ${m['lastname'] ?? ''}').trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // رأس الورقة
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0x1A3F51B5),
                  child: Icon(Icons.badge, color: Colors.indigo),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${m['username'] ?? '-'}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                      if (name.isNotEmpty)
                        Text(name,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(height: 20),
            // الإجراءات
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actBtn('تعديل البيانات', Icons.edit, Colors.indigo,
                    widget.onEdit),
                _actBtn('إيداع رصيد', Icons.add_card, Colors.green,
                    () => _amountAction('deposit', 'إيداع رصيد', 'المبلغ')),
                _actBtn('سحب رصيد', Icons.money_off, Colors.orange,
                    () => _amountAction('withdraw', 'سحب رصيد', 'المبلغ')),
                _actBtn('إضافة نقاط', Icons.stars, Colors.amber,
                    () => _pointsAction('addRewardPoints', 'إضافة نقاط مكافأة')),
                _actBtn('خصم نقاط', Icons.remove_circle_outline, Colors.deepOrange,
                    () => _pointsAction('deductRewardPoints', 'خصم نقاط مكافأة')),
                _actBtn('سداد دين', Icons.receipt_long, Colors.teal,
                    () => _amountAction('payDebt', 'سداد دين', 'المبلغ')),
                _actBtn('حذف الوكيل', Icons.delete_forever, Colors.red,
                    _deleteManager),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return FilledButton.tonalIcon(
      onPressed: _busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.12),
        foregroundColor: color,
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Future<void> _run(Future<dynamic> Function() call, String ok) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      final msg = res is Map
          ? (res['message'] ?? res['status'] ?? ok).toString()
          : ok;
      _snack('تم: $msg');
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _snack('فشل: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor:
          error ? Theme.of(context).colorScheme.error : null,
    ));
  }

  Future<void> _amountAction(
      String action, String title, String fieldLabel) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: fieldLabel),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تنفيذ')),
        ],
      ),
    );
    final amount = double.tryParse(ctl.text.trim());
    if (ok == true && amount != null) {
      await _run(
          () => widget.api.sasManagerAction(
              widget.cid, widget.mid, action, {'amount': amount}),
          title);
    }
  }

  Future<void> _pointsAction(String action, String title) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'النقاط'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('تنفيذ')),
        ],
      ),
    );
    final pts = int.tryParse(ctl.text.trim());
    if (ok == true && pts != null) {
      await _run(
          () => widget.api.sasManagerAction(
              widget.cid, widget.mid, action, {'points': pts}),
          title);
    }
  }

  Future<void> _deleteManager() async {
    // تأكيد مزدوج للإجراء الخطر
    final ok1 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الوكيل'),
        content: Text(
            'هل أنت متأكّد من حذف الوكيل «${widget.manager['username'] ?? ''}»؟\nهذا الإجراء لا يمكن التراجع عنه.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم، احذف'),
          ),
        ],
      ),
    );
    if (ok1 != true || !mounted) return;
    // تأكيد ثانٍ
    final ok2 = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد الحذف النهائي'),
        content: const Text(
            'تأكيد أخير: سيُحذف الوكيل بشكل دائم. هل تريد المتابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف نهائي'),
          ),
        ],
      ),
    );
    if (ok2 != true) return;
    await _run(
        () async {
          await widget.api.sasDeleteManager(widget.cid, widget.mid);
          return <String, dynamic>{'message': 'تم الحذف'};
        },
        'حذف الوكيل');
  }
}

/// عرض الشجرة الهرمية — قائمة متدرّجة بسيطة بناءً على parent_id.
class _ManagerTree extends StatelessWidget {
  final dynamic data;
  const _ManagerTree({required this.data});

  List<Map<String, dynamic>> _flatten(dynamic d) {
    if (d is List) return d.cast<Map<String, dynamic>>();
    if (d is Map) {
      final list = d['data'] ?? d['managers'] ?? d['rows'] ?? [];
      if (list is List) return list.cast<Map<String, dynamic>>();
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _flatten(data);
    if (nodes.isEmpty) {
      return const Center(child: Text('لا بيانات للشجرة'));
    }
    // بناء خريطة parent_id → أبناء
    final Map<dynamic, List<Map<String, dynamic>>> children = {};
    for (final n in nodes) {
      final pid = n['parent_id'];
      children.putIfAbsent(pid, () => []).add(n);
    }
    // عرض الجذور (parent_id = null أو 0 أو غير موجود)
    final roots = nodes
        .where((n) =>
            n['parent_id'] == null ||
            n['parent_id'] == 0 ||
            !nodes.any((p) => p['id'] == n['parent_id']))
        .toList();

    return ListView(
      children: [
        for (final root in roots)
          _TreeNode(node: root, children: children, depth: 0),
      ],
    );
  }
}

class _TreeNode extends StatelessWidget {
  final Map<String, dynamic> node;
  final Map<dynamic, List<Map<String, dynamic>>> children;
  final int depth;
  const _TreeNode(
      {required this.node,
      required this.children,
      required this.depth});

  @override
  Widget build(BuildContext context) {
    final kids = children[node['id']] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(start: depth * 20.0, top: 4, bottom: 4),
          child: Row(
            children: [
              Icon(
                kids.isEmpty ? Icons.person_outline : Icons.account_tree,
                size: 16,
                color: Colors.indigo.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                '${node['username'] ?? node['id']}',
                style: TextStyle(
                  fontWeight:
                      depth == 0 ? FontWeight.w700 : FontWeight.normal,
                  fontSize: depth == 0 ? 14 : 13,
                ),
              ),
              if (node['users_count'] != null) ...[
                const SizedBox(width: 6),
                Text(
                  '(${node['users_count']} مشترك)',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ],
          ),
        ),
        for (final kid in kids)
          _TreeNode(node: kid, children: children, depth: depth + 1),
      ],
    );
  }
}

// ─────────────────────────── تبويب الباقات ───────────────────────────

class _ProfilesTab extends StatefulWidget {
  final StaffApi api;
  final int cid;
  const _ProfilesTab({required this.api, required this.cid});

  @override
  State<_ProfilesTab> createState() => _ProfilesTabState();
}

class _ProfilesTabState extends State<_ProfilesTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.sasProfiles(widget.cid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('خطأ: ${snap.error}'));
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) return const Center(child: Text('لا باقات'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.card_membership, color: Colors.deepPurple),
              title: Text('${rows[i]['name'] ?? rows[i]['id']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text('#${rows[i]['id']}'),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────── تبويب المالية ───────────────────────────

class _FinanceTab extends StatefulWidget {
  final StaffApi api;
  final int cid;
  const _FinanceTab({required this.api, required this.cid});

  @override
  State<_FinanceTab> createState() => _FinanceTabState();
}

class _FinanceTabState extends State<_FinanceTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.api.sasGet(widget.cid, 'advancedDashboard/finance');
      // قد تعود البيانات مباشرةً أو داخل مفتاح data/result
      Map<String, dynamic> d;
      if (raw is Map<String, dynamic>) {
        d = (raw['data'] is Map<String, dynamic>)
            ? raw['data'] as Map<String, dynamic>
            : raw;
      } else {
        d = const {};
      }
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('تعذّر جلب بيانات المالية: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    final d = _data ?? {};
    if (d.isEmpty) {
      return const Center(child: Text('لا بيانات مالية متاحة'));
    }
    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('البيانات المالية',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            // عرض كل حقل رقمي كبطاقة KPI
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in d.entries)
                  if (_isNumeric(entry.value))
                    _FinanceKpiCard(
                      label: _financeLabel(entry.key),
                      value: _formatFinanceValue(entry.key, entry.value),
                      icon: _financeIcon(entry.key),
                      color: _financeColor(entry.key),
                    ),
              ],
            ),
            // عرض الحقول النصية كقائمة
            if (d.entries.any((e) => !_isNumeric(e.value))) ...[
              const SizedBox(height: 20),
              const Text('معلومات إضافية',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: Colors.grey)),
              const SizedBox(height: 8),
              for (final entry in d.entries)
                if (!_isNumeric(entry.value) && entry.value != null)
                  _FieldRow(label: _financeLabel(entry.key),
                      value: '${entry.value}'),
            ],
          ],
        ),
      ),
    );
  }

  bool _isNumeric(dynamic v) => v is num;

  String _formatFinanceValue(String key, dynamic v) {
    final n = (v as num).toDouble();
    // افتراض: حقول الرصيد/الدخل/الديون عملة، النسب %
    if (key.toLowerCase().contains('rate') ||
        key.toLowerCase().contains('percent') ||
        key.toLowerCase().contains('ratio')) {
      return '${n.toStringAsFixed(1)}%';
    }
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(2)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n % 1 == 0 ? '${n.toInt()}' : n.toStringAsFixed(2);
  }

  String _financeLabel(String key) {
    const labels = <String, String>{
      'total_income': 'إجمالي الدخل',
      'income': 'الدخل',
      'revenue': 'الإيرادات',
      'total_debt': 'إجمالي الديون',
      'debt': 'الديون',
      'balance': 'الرصيد الإجمالي',
      'total_balance': 'إجمالي الأرصدة',
      'managers_balance': 'أرصدة الوكلاء',
      'agents_balance': 'أرصدة الوكلاء',
      'expenses': 'المصاريف',
      'profit': 'الأرباح',
      'subscriptions': 'الاشتراكات',
      'total_subscriptions': 'إجمالي الاشتراكات',
      'renewals': 'التجديدات',
      'new_users': 'مشتركون جدد',
      'expired_users': 'مشتركون منتهون',
    };
    return labels[key] ?? key.replaceAll('_', ' ');
  }

  IconData _financeIcon(String key) {
    if (key.contains('income') || key.contains('revenue') || key.contains('profit')) {
      return Icons.trending_up;
    }
    if (key.contains('debt') || key.contains('expense')) {
      return Icons.trending_down;
    }
    if (key.contains('balance')) return Icons.account_balance_wallet;
    if (key.contains('subscription') || key.contains('renewal')) {
      return Icons.subscriptions;
    }
    if (key.contains('user') || key.contains('subscriber')) return Icons.people;
    return Icons.bar_chart;
  }

  Color _financeColor(String key) {
    if (key.contains('income') || key.contains('revenue') || key.contains('profit')) {
      return Colors.green;
    }
    if (key.contains('debt') || key.contains('expense')) return Colors.red;
    if (key.contains('balance')) return Colors.teal;
    if (key.contains('subscription')) return Colors.deepPurple;
    if (key.contains('user')) return Colors.blue;
    return Colors.blueGrey;
  }
}

class _FinanceKpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _FinanceKpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final String value;
  const _FieldRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── تبويب صحّة النظام ───────────────────────────

class _SystemHealthTab extends StatefulWidget {
  final StaffApi api;
  final int cid;
  const _SystemHealthTab({required this.api, required this.cid});

  @override
  State<_SystemHealthTab> createState() => _SystemHealthTabState();
}

class _SystemHealthTabState extends State<_SystemHealthTab> {
  Map<String, dynamic>? _health;
  double? _cpu;
  double? _memory;
  double? _disk;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // جلب بالتوازي — نتجاهل الفشل الجزئي
      final results = await Future.wait([
        widget.api.sasGet(widget.cid, 'advancedDashboard/systemHealth').catchError((_) => null),
        widget.api.sasGet(widget.cid, 'advancedDashboard/CpuUsage').catchError((_) => null),
        widget.api.sasGet(widget.cid, 'advancedDashboard/MemoryUsage').catchError((_) => null),
        widget.api.sasGet(widget.cid, 'advancedDashboard/DiskUsage').catchError((_) => null),
      ]);

      if (!mounted) return;

      // systemHealth
      final rawHealth = results[0];
      Map<String, dynamic>? health;
      if (rawHealth is Map<String, dynamic>) {
        health = (rawHealth['data'] is Map<String, dynamic>)
            ? rawHealth['data'] as Map<String, dynamic>
            : rawHealth;
      }

      // دالة مساعدة لاستخراج النسبة المئوية من استجابة متنوّعة الأشكال
      double? extractPercent(dynamic raw, List<String> keys) {
        if (raw == null) return null;
        Map<String, dynamic> d = {};
        if (raw is Map<String, dynamic>) {
          d = (raw['data'] is Map<String, dynamic>)
              ? raw['data'] as Map<String, dynamic>
              : raw;
        }
        for (final k in keys) {
          final v = d[k];
          if (v is num) {
            final pct = v.toDouble();
            return (pct > 1.0) ? pct : pct * 100; // تطبيع 0-1 إلى 0-100
          }
        }
        return null;
      }

      setState(() {
        _health = health;
        _cpu = extractPercent(
            results[1], ['cpu', 'cpu_usage', 'usage', 'value', 'percent']);
        _memory = extractPercent(
            results[2], ['memory', 'mem', 'memory_usage', 'usage', 'value', 'percent']);
        _disk = extractPercent(
            results[3], ['disk', 'disk_usage', 'usage', 'value', 'percent']);
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _health == null && _cpu == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('تعذّر جلب بيانات صحّة النظام: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _load(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('صحّة النظام',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                    tooltip: 'تحديث',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 16),
            // مؤشّرات الاستخدام
            if (_cpu != null)
              _UsageBar(
                  label: 'المعالج (CPU)',
                  percent: _cpu!,
                  icon: Icons.memory),
            if (_memory != null)
              _UsageBar(
                  label: 'الذاكرة (RAM)',
                  percent: _memory!,
                  icon: Icons.storage),
            if (_disk != null)
              _UsageBar(
                  label: 'القرص (Disk)',
                  percent: _disk!,
                  icon: Icons.disc_full),
            if (_cpu == null && _memory == null && _disk == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لم تُتَح بيانات الاستخدام',
                    style: TextStyle(color: Colors.grey)),
              ),
            // بيانات الصحّة العامّة
            if (_health != null && _health!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('حالة الخدمات',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final entry in _health!.entries)
                    _ServiceStatusCard(
                        name: entry.key, value: entry.value),
                ],
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('ملاحظة: بعض البيانات تعذّر جلبها ($_error)',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.orange)),
              ),
          ],
        ),
      ),
    );
  }
}

/// شريط استخدام ملوّن (أخضر < 70% ≤ برتقالي < 90% ≤ أحمر).
class _UsageBar extends StatelessWidget {
  final String label;
  final double percent; // 0–100
  final IconData icon;
  const _UsageBar(
      {required this.label, required this.percent, required this.icon});

  Color get _color {
    if (percent < 70) return Colors.green;
    if (percent < 90) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final pct = percent.clamp(0.0, 100.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _color),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const Spacer(),
              Text('${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _color,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 10,
              backgroundColor: _color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation<Color>(_color),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة حالة خدمة واحدة.
class _ServiceStatusCard extends StatelessWidget {
  final String name;
  final dynamic value;
  const _ServiceStatusCard({required this.name, required this.value});

  bool get _isOk {
    if (value is bool) return value as bool;
    if (value is String) {
      final lower = (value as String).toLowerCase();
      return lower == 'ok' || lower == 'up' || lower == 'running' ||
          lower == 'active' || lower == 'true' || lower == '1';
    }
    if (value is num) return (value as num) > 0;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ok = _isOk;
    final color = ok ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.replaceAll('_', ' '),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              Text(ok ? 'يعمل' : 'توقّف',
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────── سجلّ الدخول / سجلّ النظام (تبويبات قوائم) ───────────────────
enum _LogKind { auth, syslog }

class _LogTab extends StatefulWidget {
  final StaffApi api;
  final int cid;
  final _LogKind kind;
  const _LogTab({required this.api, required this.cid, required this.kind});
  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  late Future<({List<Map<String, dynamic>> rows, int total})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({List<Map<String, dynamic>> rows, int total})> _load() =>
      widget.kind == _LogKind.auth
          ? widget.api.sasAuthLog(widget.cid, count: 200)
          : widget.api.sasSyslog(widget.cid, count: 200);

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({List<Map<String, dynamic>> rows, int total})>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('تعذّر جلب السجلّ: ${snap.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('إعادة')),
            ]),
          );
        }
        final rows = snap.data?.rows ?? const [];
        if (rows.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.history, size: 48, color: Colors.grey),
              const SizedBox(height: 8),
              const Text('لا سجلّات'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: _reload, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
            ]),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => _LogCard(row: rows[i], kind: widget.kind),
          ),
        );
      },
    );
  }
}

class _LogCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final _LogKind kind;
  const _LogCard({required this.row, required this.kind});

  String _s(dynamic v) => (v ?? '').toString();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (kind == _LogKind.auth) {
      final reply = _s(row['reply']);
      final accepted = reply.toLowerCase().contains('accept');
      return Card(
        child: ListTile(
          leading: Icon(accepted ? Icons.check_circle : Icons.cancel,
              color: accepted ? Colors.green : Colors.redAccent),
          title: Text(_s(row['username']),
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(reply.isEmpty ? '-' : reply,
                style: tt.bodySmall?.copyWith(color: accepted ? Colors.green : Colors.redAccent)),
            if (_s(row['mac']).isNotEmpty) Text('MAC: ${_s(row['mac'])}', style: tt.bodySmall),
            if (_s(row['nas_ip_address']).isNotEmpty)
              Text('NAS: ${_s(row['nas_ip_address'])}', style: tt.bodySmall),
          ]),
          trailing: Text(_s(row['created_at']), style: tt.bodySmall, textAlign: TextAlign.end),
          isThreeLine: true,
        ),
      );
    }
    // syslog
    final by = row['manager_details'];
    final byName = by is Map ? _s(by['username']) : _s(row['created_by']);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.article_outlined, color: Colors.blueGrey),
        title: Text(_s(row['event']).isEmpty ? _s(row['description']) : _s(row['event']),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_s(row['description']).isNotEmpty && _s(row['event']).isNotEmpty)
            Text(_s(row['description']), style: tt.bodySmall),
          Text([
            if (byName.isNotEmpty) 'بواسطة $byName',
            if (_s(row['ip']).isNotEmpty) 'IP ${_s(row['ip'])}',
          ].join(' · '), style: tt.bodySmall),
        ]),
        trailing: Text(_s(row['created_at']), style: tt.bodySmall, textAlign: TextAlign.end),
        isThreeLine: true,
      ),
    );
  }
}


