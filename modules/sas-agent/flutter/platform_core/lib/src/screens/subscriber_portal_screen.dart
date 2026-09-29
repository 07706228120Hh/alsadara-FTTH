import 'package:flutter/material.dart';

import '../api/subscriber_api.dart';
import '../models/subscriber_row.dart';
import '../widgets/banner.dart';
import 'sas_link_dialog.dart';

/// بوابة المشترك — تعرض رصيده/فواتيره/جلساته/ترافيكه/باقاته من SAS،
/// وتتيح عمليات بوابته (تغيير كلمة المرور، استبدال كرت، تغيير الاشتراك) بعد الربط.
/// المصدر مزدوج بالباكند: مربوط → بوابته الحقيقية، غير مربوط → عرضٌ عبر واجهة الإدارة.
class SubscriberPortalScreen extends StatefulWidget {
  final SubscriberApi api;
  final SubscriberRow account;
  const SubscriberPortalScreen({super.key, required this.api, required this.account});

  @override
  State<SubscriberPortalScreen> createState() => _SubscriberPortalScreenState();
}

class _SubscriberPortalScreenState extends State<SubscriberPortalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _linked = false;
  String _sasUsername = '';
  bool _busy = false;
  int _reloadKey = 0;      // لإعادة بناء FutureBuilders بعد عملية

  int get _accId => widget.account.id;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _loadLinkStatus();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadLinkStatus() async {
    try {
      final s = await widget.api.sasLinkStatus(_accId);
      if (mounted) {
        setState(() {
          _linked = s.linked;
          _sasUsername = s.sasUsername;
        });
      }
    } catch (_) {/* تجاهل — العرض يعمل دون ربط */}
  }

  String _txid() => 'sub-$_accId-${DateTime.now().microsecondsSinceEpoch}';

  /// يضمن الربط قبل عملية كتابية؛ يعرض الحوار إن لزم. يُرجع true إن أصبح مربوطاً.
  Future<bool> _ensureLinked() async {
    if (_linked) return true;
    final ok = await showSasLinkDialog(context,
        api: widget.api, accountId: _accId, initialUsername: widget.account.username);
    if (ok && mounted) {
      setState(() => _linked = true);
      await _loadLinkStatus();
    }
    return ok;
  }

  Future<void> _run(Future<dynamic> Function() call, String okMsg) async {
    setState(() => _busy = true);
    try {
      await call();
      if (mounted) {
        toast(context, 'تم: $okMsg', kind: BannerKind.success);
        setState(() => _reloadKey++);
      }
    } catch (e) {
      if (mounted) toast(context, 'فشل: $e', kind: BannerKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(a.username.isNotEmpty ? a.username : 'حسابي'),
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            tabs: const [
              Tab(text: 'الرصيد'),
              Tab(text: 'الفواتير'),
              Tab(text: 'الجلسات'),
              Tab(text: 'الترافيك'),
              Tab(text: 'الباقات'),
            ],
          ),
        ),
        body: Column(
          children: [
            _linkBanner(),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _future(() => widget.api.sasBalance(_accId), _balanceView),
                  _future(() => widget.api.sasInvoices(_accId), _listView('لا فواتير')),
                  _future(() => widget.api.sasSessions(_accId), _listView('لا جلسات نشطة')),
                  _future(() => widget.api.sasTraffic(_accId), _trafficView),
                  _future(() => widget.api.sasPackages(_accId), _packagesView),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _busy
            ? null
            : FloatingActionButton.extended(
                onPressed: _showActionsSheet,
                icon: const Icon(Icons.bolt),
                label: const Text('عمليات'),
              ),
      ),
    );
  }

  Widget _linkBanner() {
    return Container(
      width: double.infinity,
      color: _linked ? Colors.green.withValues(alpha: 0.10) : Colors.orange.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(_linked ? Icons.link : Icons.link_off,
              size: 18, color: _linked ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _linked
                  ? 'حساب البوابة مربوط ($_sasUsername) — العمليات مفعّلة'
                  : 'العرض يعمل. اربط حساب البوابة لتفعيل العمليات (تغيير كلمة المرور، استبدال كرت).',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_linked)
            TextButton(
              onPressed: () async {
                await widget.api.sasUnlink(_accId);
                if (mounted) setState(() { _linked = false; _sasUsername = ''; });
              },
              child: const Text('فكّ الربط'),
            )
          else
            FilledButton(
              onPressed: _ensureLinked,
              child: const Text('ربط'),
            ),
        ],
      ),
    );
  }

  Widget _future(Future<dynamic> Function() call, Widget Function(dynamic) render) {
    return FutureBuilder<dynamic>(
      key: ValueKey('${call.hashCode}-$_reloadKey'),
      future: call(),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(24),
            child: PBanner.error('تعذّر الجلب: ${snap.error}'),
          ));
        }
        return RefreshIndicator(
          onRefresh: () async => setState(() => _reloadKey++),
          child: render(snap.data),
        );
      },
    );
  }

  // ─── عارضات ───

  Widget _balanceView(dynamic data) {
    final m = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
    final entries = m.entries.where((e) => e.value != null && '${e.value}'.trim().isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final e in entries)
          Card(
            child: ListTile(
              dense: true,
              title: Text(_ar(e.key)),
              trailing: Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        if (entries.isEmpty) const Center(child: Padding(
          padding: EdgeInsets.all(32), child: Text('لا بيانات رصيد'))),
      ],
    );
  }

  Widget Function(dynamic) _listView(String emptyMsg) => (data) {
        final rows = _rows(data);
        if (rows.isEmpty) {
          return ListView(children: [Padding(
            padding: const EdgeInsets.all(32), child: Center(child: Text(emptyMsg)))]);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final r = rows[i];
            final entries = r.entries.where((e) => e.value != null).take(4).toList();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Text('${_ar(e.key)}: ',
                              style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          Flexible(child: Text('${e.value}',
                              style: const TextStyle(fontWeight: FontWeight.w600))),
                        ]),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      };

  Widget _trafficView(dynamic data) {
    final m = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
    final rx = m['rx'];
    final tx = m['tx'];
    if (rx is List || tx is List) {
      final rxL = (rx is List) ? rx : const [];
      final txL = (tx is List) ? tx : const [];
      final n = rxL.length > txL.length ? rxL.length : txL.length;
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: n,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => ListTile(
          dense: true,
          leading: Text('يوم ${i + 1}'),
          title: Row(children: [
            const Icon(Icons.download, size: 14, color: Colors.green),
            Text(' ${i < rxL.length ? rxL[i] : 0}   '),
            const Icon(Icons.upload, size: 14, color: Colors.blue),
            Text(' ${i < txL.length ? txL[i] : 0}'),
          ]),
        ),
      );
    }
    return _balanceView(data);
  }

  Widget _packagesView(dynamic data) {
    final rows = _rows(data);
    if (rows.isEmpty) {
      return ListView(children: const [Padding(
        padding: EdgeInsets.all(32), child: Center(child: Text('لا باقات')))]);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final p = rows[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.wifi),
            title: Text('${p['name'] ?? p['title'] ?? p['id']}'),
            subtitle: p['price'] != null ? Text('السعر: ${p['price']}') : null,
            trailing: _linked
                ? TextButton(
                    onPressed: () => _doChangeSubscription(p['id'] ?? p['service_id']),
                    child: const Text('اشترك'))
                : null,
          ),
        );
      },
    );
  }

  // ─── العمليات ───

  void _showActionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('تغيير كلمة المرور'),
              onTap: () { Navigator.pop(context); _doChangePassword(); },
            ),
            ListTile(
              leading: const Icon(Icons.confirmation_number_outlined),
              title: const Text('استبدال كرت (Redeem)'),
              onTap: () { Navigator.pop(context); _doRedeem(); },
            ),
            ListTile(
              leading: const Icon(Icons.sync_alt),
              title: const Text('تغيير الاشتراك'),
              onTap: () { Navigator.pop(context); _tabs.animateTo(4); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doChangePassword() async {
    if (!await _ensureLinked()) return;
    final ctl = TextEditingController();
    final ok = await _prompt('تغيير كلمة المرور', 'كلمة المرور الجديدة', ctl, obscure: true);
    if (ok != true || ctl.text.isEmpty) return;
    await _run(() => widget.api.sasChangePassword(_accId, ctl.text, txId: _txid()),
        'تم تغيير كلمة المرور');
  }

  Future<void> _doRedeem() async {
    if (!await _ensureLinked()) return;
    final ctl = TextEditingController();
    final ok = await _prompt('استبدال كرت', 'رمز الكرت (PIN)', ctl);
    if (ok != true || ctl.text.trim().isEmpty) return;
    await _run(() => widget.api.sasRedeem(_accId, ctl.text.trim(), txId: _txid()),
        'تمت تعبئة الكرت');
  }

  Future<void> _doChangeSubscription(dynamic serviceId) async {
    if (serviceId == null) return;
    if (!await _ensureLinked()) return;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغيير الاشتراك'),
          content: Text('تأكيد تغيير اشتراكك إلى الباقة رقم $serviceId؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد')),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    await _run(
        () => widget.api.sasChangeSubscription(_accId, serviceId, txId: _txid()),
        'تم تغيير الاشتراك');
  }

  Future<bool?> _prompt(String title, String label, TextEditingController ctl,
      {bool obscure = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            obscureText: obscure,
            autofocus: true,
            decoration: InputDecoration(labelText: label, isDense: true),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تنفيذ')),
          ],
        ),
      ),
    );
  }

  // ─── مساعدات ───

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is Map<String, dynamic>) {
      final d = data['data'];
      if (d is List) return d.cast<Map<String, dynamic>>();
      return const [];
    }
    if (data is List) return data.cast<Map<String, dynamic>>();
    return const [];
  }

  static String _ar(String key) {
    const m = {
      'balance': 'الرصيد',
      'expiration': 'تاريخ الانتهاء',
      'profile': 'الباقة',
      'profile_name': 'الباقة',
      'status': 'الحالة',
      'amount': 'المبلغ',
      'invoice_number': 'رقم الفاتورة',
      'created_at': 'التاريخ',
      'due_date': 'الاستحقاق',
      'framedipaddress': 'IP',
      'nasipaddress': 'NAS',
      'acctsessiontime': 'مدة الجلسة',
    };
    return m[key] ?? key;
  }
}
