import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:platform_core/platform_core.dart';

/// إدارة الوكلاء للأدمن الداخلي:
///  • إنشاء حسابات دخول للوكلاء مباشرةً (اسم مستخدم + كلمة مرور + معلومات + مزوّد).
///    يدخل الوكيل بحسابه ثم يضبط خادم SAS الخاص به وبياناته.
///  • عرض حالة كل حساب (هل ضبط الوكيل بيانات SAS؟) وحذفه.
///  • (إرث) الوكلاء المُزامَنون من SAS + البلنك الموحّد — يظهر عند توفّر مزامنة.
class AdminAgentsScreen extends StatefulWidget {
  final StaffApi api;
  const AdminAgentsScreen({super.key, required this.api});
  @override
  State<AdminAgentsScreen> createState() => _AdminAgentsScreenState();
}

class _AdminAgentsScreenState extends State<AdminAgentsScreen> {
  List<Map<String, dynamic>> _accounts = [];
  List<AgentRow> _agents = [];
  Map<String, ReconRow> _recon = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final accounts = await widget.api.listAgentAccounts();
      // الوكلاء المُزامَنون + البلنك (أفضل-جهد — قد يكونان فارغين قبل المزامنة)
      List<AgentRow> agents = const [];
      Map<String, ReconRow> recon = {};
      try {
        agents = await widget.api.agents();
        final r = await widget.api.reconciliation();
        recon = {for (final x in r.rows) x.agentUsername: x};
      } catch (_) {/* لا مزامنة بعد — نتجاهل */}
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _agents = agents;
          _recon = recon;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _createAccount() async {
    final username = TextEditingController();
    final password = TextEditingController();
    final name = TextEditingController();
    final phone = TextEditingController();
    final provider = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إنشاء حساب وكيل'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _f(username, 'اسم المستخدم (للدخول) *'),
              _f(password, 'كلمة المرور * (8 محارف على الأقل)', obscure: true),
              _f(name, 'اسم الوكيل'),
              _f(phone, 'الهاتف', keyboard: TextInputType.phone),
              _f(provider, 'المزوّد/الشركة (يُنشأ إن لم يوجد)'),
              const SizedBox(height: 6),
              const Text('يدخل الوكيل بهذا الحساب ثم يضبط خادم SAS الخاص به وبياناته.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إنشاء')),
          ],
        ),
      ),
    );
    if (created != true) return;
    if (username.text.trim().isEmpty || password.text.length < 8) {
      if (mounted) showMsg(context, 'اسم المستخدم مطلوب وكلمة المرور 8 محارف على الأقل', error: true);
      return;
    }
    try {
      await widget.api.createAgentAccount(
        username: username.text.trim(),
        password: password.text,
        displayName: name.text.trim(),
        phone: phone.text.trim(),
        provider: provider.text.trim(),
      );
      if (!mounted) return;
      showMsg(context, 'أُنشئ حساب الوكيل «${username.text.trim()}»');
      _load();
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteAccount(Map<String, dynamic> acc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حذف حساب «${acc['username']}»؟'),
          content: const Text('لن يستطيع الوكيل الدخول بعد الحذف.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteAgentAccount((acc['id'] as num).toInt());
      if (!mounted) return;
      showMsg(context, 'حُذف الحساب');
      _load();
    } catch (e) {
      if (mounted) showMsg(context, friendlyError(e), error: true);
    }
  }

  Widget _f(TextEditingController c, String label,
      {bool obscure = false, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TabPage(
      title: 'الوكلاء',
      subtitle: '${Fmt.n(_accounts.length)} حساب وكيل',
      onRefresh: _load,
      actions: [
        IconButton(
          tooltip: 'إنشاء حساب وكيل',
          onPressed: Session.isAdmin ? _createAccount : null,
          icon: const Icon(PhosphorIconsBold.userPlus),
        ),
      ],
      child: Content(
        child: _loading
            ? const SkeletonList()
            : _error != null
                ? ErrorView(_error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                    children: [
                      // ── حسابات الوكلاء (الأساس) ──
                      if (_accounts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: EmptyView(
                            icon: PhosphorIconsDuotone.userPlus,
                            title: 'لا حسابات وكلاء بعد',
                            subtitle: 'اضغط زرّ الإنشاء (+) لإضافة حساب وكيل جديد',
                          ),
                        )
                      else
                        for (final acc in _accounts)
                          _AccountCard(
                            acc: acc,
                            onDelete: Session.isAdmin ? () => _deleteAccount(acc) : null,
                          ),

                      // ── (إرث) الوكلاء المُزامَنون من SAS ──
                      if (_agents.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('وكلاء مُزامَنون من SAS (البلنك الموحّد)',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        for (final a in _agents)
                          _AgentCard(a: a, r: _recon[a.username]),
                      ],
                    ],
                  ),
      ),
    );
  }
}

/// بطاقة حساب وكيل أنشأه الأدمن.
class _AccountCard extends StatelessWidget {
  final Map<String, dynamic> acc;
  final VoidCallback? onDelete;
  const _AccountCard({required this.acc, this.onDelete});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final configured = acc['sas_configured'] == true;
    final name = (acc['display_name'] as String?)?.trim() ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(children: [
          CircleAvatar(
            backgroundColor: (configured ? Colors.green : Colors.orange).withValues(alpha: 0.15),
            child: Icon(configured ? PhosphorIconsBold.checkCircle : PhosphorIconsBold.clock,
                color: configured ? Colors.green : Colors.orange, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name.isNotEmpty ? name : '${acc['username']}',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text('@${acc['username']}'
                  '${(acc['provider'] as String?)?.isNotEmpty == true ? ' · ${acc['provider']}' : ''}',
                  style: tt.bodySmall),
              if ((acc['phone'] as String?)?.isNotEmpty == true)
                Text('${acc['phone']}', style: tt.bodySmall),
              Text(configured
                  ? 'ضبط اتصاله بـ SAS ✓ (${acc['sas_username'] ?? ''})'
                  : 'لم يضبط اتصاله بـ SAS بعد',
                  style: tt.bodySmall?.copyWith(
                      color: configured ? Colors.green : Colors.orange)),
            ]),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: 'حذف الحساب',
              onPressed: onDelete,
              icon: const Icon(PhosphorIconsDuotone.trash),
            ),
        ]),
      ),
    );
  }
}

/// بطاقة وكيل مُزامَن من SAS (إرث — البلنك الموحّد).
class _AgentCard extends StatelessWidget {
  final AgentRow a;
  final ReconRow? r;
  const _AgentCard({required this.a, required this.r});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final verdict = r?.verdict ?? 'no_report';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name.isNotEmpty ? a.name : a.username,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text('@${a.username}${a.parentUsername.isNotEmpty ? ' · تحت ${a.parentUsername}' : ''}',
                    style: tt.bodySmall),
              ]),
            ),
            StatusChip(verdictAr[verdict] ?? verdict, color: statusColor(verdict)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _mini(context, 'SAS', Fmt.n(a.usersCount)),
            _mini(context, 'تصريحه', r == null || verdict == 'no_report' ? '—' : Fmt.n(r!.agentDeclared)),
            _mini(context, 'الفارق', r == null || verdict == 'no_report' ? '—' : Fmt.n(r!.diff),
                color: (r?.diff ?? 0) == 0 ? null : BrandColors.amber),
            _mini(context, 'الرصيد', Fmt.n(a.balance)),
          ]),
        ]),
      ),
    );
  }

  Widget _mini(BuildContext c, String k, String v, {Color? color}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: Theme.of(c).textTheme.bodySmall),
          Text(v, style: Theme.of(c).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
        ]),
      );
}
