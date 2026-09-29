import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api/staff_api.dart';
import '../theme/tokens.dart';
import '../widgets/banner.dart';
import '../widgets/inputs.dart';
import 'sas_panel_screen.dart';

/// قسم SAS الذكي داخل تطبيق الشركة/الوكيل:
/// - الشركة: إن لم تُضبط بيانات الاتصال → شاشة إعداد الشركة؛ وإلا اللوحة + زرّ تعديل.
/// - الوكيل: إن لم تضبط شركته الخادم → رسالة؛ وإلا إن لم يضبط الوكيل حسابه → شاشة إعداد
///   الوكيل (اسم مستخدم + كلمة مرور، والخادم موروث من الشركة)؛ وإلا اللوحة + زرّ تعديل.
class SasSection extends StatefulWidget {
  final StaffApi api;
  final int companyId;
  final bool isAgent;
  const SasSection({
    super.key,
    required this.api,
    required this.companyId,
    this.isAgent = false,
  });

  @override
  State<SasSection> createState() => _SasSectionState();
}

class _SasSectionState extends State<SasSection> {
  bool _loading = true;
  bool _editing = false;
  String? _error;
  bool _configured = false;      // الشركة: هل ضُبط اتصالها؟
  bool _agentReady = false;      // الوكيل: هل ضبط خادمه واسم مستخدمه وكلمة مروره؟

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.isAgent) {
        // الوكيل قد يربط عدة حسابات SAS — جاهز إن كان أيّ حساب مضبوطاً بالكامل.
        final accounts = await widget.api.agentSasAccounts();
        if (!mounted) return;
        setState(() {
          _agentReady = accounts.any((a) => a['configured'] == true);
          _editing = false;
          _loading = false;
        });
      } else {
        final c = await widget.api.companyConfig(widget.companyId);
        if (!mounted) return;
        setState(() {
          _configured = ((c['sas_host'] as String?) ?? '').isNotEmpty &&
              ((c['sas_username'] as String?) ?? '').isNotEmpty;
          _editing = false;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Widget _panelWithEdit({required bool isAgent}) => Column(children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(PhosphorIconsBold.gear, size: 15),
              label: Text(isAgent ? 'حساباتي على SAS' : 'إعداد الاتصال بـ SAS'),
            ),
          ),
        ),
        Expanded(
          child: SasPanelScreen(
              api: widget.api, companyId: widget.companyId, isAgent: isAgent),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('تعذّر تحميل إعداد SAS: $_error',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.pal.danger)),
        ),
      );
    }

    if (widget.isAgent) {
      if (!_agentReady || _editing) {
        return AgentSasAccountsScreen(
          api: widget.api,
          companyId: widget.companyId,
          onChanged: _check,
          onDone: _agentReady ? () => setState(() => _editing = false) : null,
        );
      }
      return _panelWithEdit(isAgent: true);
    }

    // الشركة
    if (!_configured || _editing) {
      return SasConfigScreen(
        api: widget.api,
        companyId: widget.companyId,
        onSaved: _check,
        onCancel: _configured ? () => setState(() => _editing = false) : null,
      );
    }
    return _panelWithEdit(isAgent: false);
  }
}

/// شاشة «إعداد الاتصال بـ SAS» — تضبطها الشركة بنفسها (خادم + مستخدم + كلمة مرور).
class SasConfigScreen extends StatefulWidget {
  final StaffApi api;
  final int companyId;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;
  const SasConfigScreen({
    super.key,
    required this.api,
    required this.companyId,
    this.onSaved,
    this.onCancel,
  });

  @override
  State<SasConfigScreen> createState() => _SasConfigScreenState();
}

class _SasConfigScreenState extends State<SasConfigScreen> {
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _https = false;
  bool _verifyTls = false;
  bool _hasPassword = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _testMsg;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await widget.api.companyConfig(widget.companyId);
      if (!mounted) return;
      setState(() {
        _host.text = c['sas_host'] as String? ?? '';
        _user.text = c['sas_username'] as String? ?? '';
        _https = c['sas_https'] == true;
        _verifyTls = c['sas_verify_tls'] == true;
        _hasPassword = c['has_password'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _test() async {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _error = 'أدخل عنوان الخادم واسم المستخدم أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _testMsg = null;
      _testOk = null;
    });
    try {
      final r = await widget.api.testSas(widget.companyId,
          host: _host.text.trim(),
          username: _user.text.trim(),
          password: _pass.text.isEmpty ? null : _pass.text,
          https: _https,
          verifyTls: _verifyTls);
      if (!mounted) return;
      final ok = r['ok'] == true;
      setState(() {
        _testOk = ok;
        _testMsg = ok
            ? 'الاتصال ناجح — إجمالي المشتركين: ${r['summary']?['total'] ?? '؟'}'
            : 'فشل الاتصال: ${r['error'] ?? ''}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMsg = 'تعذّر الاختبار: $e';
        _busy = false;
      });
    }
  }

  Future<void> _save() async {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _error = 'أدخل عنوان الخادم واسم المستخدم');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.saveSasConfig(widget.companyId,
          host: _host.text.trim(),
          username: _user.text.trim(),
          password: _pass.text.isEmpty ? null : _pass.text,
          https: _https,
          verifyTls: _verifyTls);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حُفظت بيانات الاتصال بنظام SAS')));
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(PhosphorIconsDuotone.database, color: pal.accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text('إعداد الاتصال بنظام SAS',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (widget.onCancel != null)
                TextButton(onPressed: _busy ? null : widget.onCancel, child: const Text('إلغاء')),
            ]),
            const SizedBox(height: 6),
            Text(
                'أدخل عنوان خادم SAS4 المباشر وبيانات مستخدم الـ API الخاص بشركتك. '
                'بعد الحفظ الناجح تعمل لوحة SAS داخل التطبيق مباشرةً.',
                style: t.bodyMedium?.copyWith(color: pal.textMuted, height: 1.5)),
            const SizedBox(height: Space.xl),
            if (_error != null) ...[
              PBanner.error(_error!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _host,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                labelText: 'عنوان خادم SAS4 (host أو IP[:port])',
                hintText: 'itpc4.company.com',
                prefixIcon: Icon(PhosphorIconsBold.globe, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'مستخدم API',
                prefixIcon: Icon(PhosphorIconsBold.user, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            PasswordField(
                controller: _pass,
                enabled: !_busy,
                label: _hasPassword ? 'كلمة المرور (اتركها فارغة للإبقاء)' : 'كلمة المرور'),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('استخدام HTTPS'),
              value: _https,
              onChanged: _busy ? null : (v) => setState(() => _https = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تحقّق شهادة TLS'),
              subtitle: const Text('أطفئه للشهادات الذاتية'),
              value: _verifyTls,
              onChanged: _busy ? null : (v) => setState(() => _verifyTls = v),
            ),
            if (_testMsg != null) ...[
              const SizedBox(height: 10),
              _testOk == true ? PBanner.success(_testMsg!) : PBanner.error(_testMsg!),
            ],
            const SizedBox(height: Space.lg),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: const Icon(PhosphorIconsBold.plugsConnected, size: 18),
                  label: const Text('اختبار الاتصال'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(PhosphorIconsBold.floppyDisk, size: 18),
                  label: const Text('حفظ'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// شاشة «حساباتي على SAS» — يدير الوكيل **عدة حسابات SAS** (قد تكون على خوادم مختلفة).
/// كل حساب يُزامَن مستقلاً، وتُدمَج مشتركوه في اللوحة، وتُوجَّه أي عملية تلقائياً لحسابه.
class AgentSasAccountsScreen extends StatefulWidget {
  final StaffApi api;
  final int companyId;
  final VoidCallback? onChanged;   // بعد أي تغيير (لإعادة فحص الجاهزية في SasSection)
  final VoidCallback? onDone;      // زر «تمّ» — متاح إن كان هناك حساب مضبوط
  const AgentSasAccountsScreen({
    super.key,
    required this.api,
    required this.companyId,
    this.onChanged,
    this.onDone,
  });

  @override
  State<AgentSasAccountsScreen> createState() => _AgentSasAccountsScreenState();
}

class _AgentSasAccountsScreenState extends State<AgentSasAccountsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _accounts = const [];

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
      final a = await widget.api.agentSasAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = a;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _AgentSasAccountFormDialog(api: widget.api, existing: existing),
    );
    if (changed == true) {
      await _load();
      widget.onChanged?.call();
    }
  }

  Future<void> _sync(int id) async {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('جارٍ مزامنة الحساب…')));
    try {
      final r = await widget.api.syncAgentSasAccount(id);
      final n = (r['count'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تمت مزامنة $n مشترك من الحساب')));
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّرت المزامنة: $e')));
    }
  }

  Future<void> _delete(int id, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: Text('حذف حساب «$label» ومشتركيه المحليين؟ لا يؤثّر على خادم SAS نفسه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: context.pal.danger),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteAgentSasAccount(id);
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر الحذف: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(PhosphorIconsDuotone.stackPlus, color: pal.accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text('حساباتي على SAS',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (widget.onDone != null)
                TextButton(onPressed: widget.onDone, child: const Text('تمّ')),
            ]),
            const SizedBox(height: 6),
            Text(
                'اربط حساباً أو أكثر من حسابات SAS الخاصّة بك (قد تكون على خوادم مختلفة). '
                'يظهر كل مشتركيك مدموجين، وأي عملية تُوجَّه تلقائياً إلى الحساب الصحيح.',
                style: t.bodyMedium?.copyWith(color: pal.textMuted, height: 1.5)),
            const SizedBox(height: Space.lg),
            if (_error != null) ...[
              PBanner.error(_error!),
              const SizedBox(height: 12),
            ],
            if (_accounts.isEmpty)
              Container(
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(
                  color: pal.surfaceVariant,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: pal.outline),
                ),
                child: Row(children: [
                  Icon(PhosphorIconsBold.info, color: pal.textMuted, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('لا حسابات بعد — أضف أول حساب SAS للبدء.')),
                ]),
              ),
            for (final a in _accounts) _AccountCard(
              account: a,
              onEdit: () => _openForm(existing: a),
              onSync: (a['configured'] == true) ? () => _sync(a['id'] as int) : null,
              onDelete: () => _delete(a['id'] as int, (a['label'] ?? '') as String),
            ),
            const SizedBox(height: Space.lg),
            FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(PhosphorIconsBold.plus, size: 18),
              label: const Text('إضافة حساب SAS'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// بطاقة حساب SAS واحد داخل مدير الحسابات.
class _AccountCard extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback onEdit;
  final VoidCallback? onSync;
  final VoidCallback onDelete;
  const _AccountCard({
    required this.account,
    required this.onEdit,
    required this.onSync,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    final label = (account['label'] ?? account['sas_username'] ?? 'حساب') as String;
    final user = (account['sas_username'] ?? '') as String;
    final host = (account['sas_host'] ?? '') as String;
    final configured = account['configured'] == true;
    final enabled = account['enabled'] == true;
    final lastOk = account['last_sync_ok'] == true;
    final lastErr = (account['last_sync_error'] ?? '') as String;
    final subs = (account['subscribers'] as num?)?.toInt();
    final Color statusColor = !configured
        ? pal.textMuted
        : (lastOk ? pal.success : (lastErr.isNotEmpty ? pal.danger : pal.warning));
    final String statusText = !configured
        ? 'غير مكتمل الإعداد'
        : (lastOk ? 'مزامنة ناجحة' : (lastErr.isNotEmpty ? 'فشل المزامنة' : 'بانتظار المزامنة'));
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: pal.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: pal.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(enabled ? PhosphorIconsFill.circle : PhosphorIconsBold.circle,
              size: 10, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis),
          ),
          if (subs != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: pal.surfaceVariant,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: Text('$subs مشترك', style: t.labelSmall?.copyWith(color: pal.textMuted)),
            ),
        ]),
        const SizedBox(height: 6),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              host.isEmpty ? user : '$user @ $host',
              style: t.bodySmall?.copyWith(color: pal.textMuted),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(statusText, style: t.labelSmall?.copyWith(color: statusColor)),
        const SizedBox(height: 6),
        Row(children: [
          TextButton.icon(
            onPressed: onEdit,
            icon: const Icon(PhosphorIconsBold.pencilSimple, size: 15),
            label: const Text('تعديل'),
          ),
          if (onSync != null)
            TextButton.icon(
              onPressed: onSync,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 15),
              label: const Text('مزامنة'),
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: onDelete,
            icon: Icon(PhosphorIconsBold.trash, size: 15, color: pal.danger),
            label: Text('حذف', style: TextStyle(color: pal.danger)),
          ),
        ]),
      ]),
    );
  }
}

/// نموذج إضافة/تعديل حساب SAS للوكيل — يُرجع true عند الحفظ.
class _AgentSasAccountFormDialog extends StatefulWidget {
  final StaffApi api;
  final Map<String, dynamic>? existing;
  const _AgentSasAccountFormDialog({required this.api, this.existing});

  @override
  State<_AgentSasAccountFormDialog> createState() => _AgentSasAccountFormDialogState();
}

class _AgentSasAccountFormDialogState extends State<_AgentSasAccountFormDialog> {
  late final TextEditingController _label;
  late final TextEditingController _host;
  late final TextEditingController _user;
  final _pass = TextEditingController();
  bool _https = false;
  bool _verifyTls = false;
  bool _hasPassword = false;
  bool _busy = false;
  String? _error;
  String? _testMsg;
  bool? _testOk;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: (e?['label'] ?? '') as String);
    _host = TextEditingController(text: (e?['sas_host'] ?? '') as String);
    _user = TextEditingController(text: (e?['sas_username'] ?? '') as String);
    _https = e?['sas_https'] == true;
    _verifyTls = e?['sas_verify_tls'] == true;
    _hasPassword = e?['has_password'] == true;
  }

  @override
  void dispose() {
    _label.dispose();
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    if (!_isEdit) {
      setState(() => _error = 'احفظ الحساب أولاً ثم اختبره');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _testMsg = null;
      _testOk = null;
    });
    try {
      final r = await widget.api.testAgentSasAccount(widget.existing!['id'] as int,
          host: _host.text.trim().isEmpty ? null : _host.text.trim(),
          username: _user.text.trim().isEmpty ? null : _user.text.trim(),
          password: _pass.text.isEmpty ? null : _pass.text,
          https: _https,
          verifyTls: _verifyTls);
      if (!mounted) return;
      final ok = r['ok'] == true;
      setState(() {
        _testOk = ok;
        _testMsg = ok
            ? 'الاتصال ناجح — إجمالي مشتركيك: ${r['summary']?['total'] ?? '؟'}'
            : 'فشل الاتصال: ${r['error'] ?? ''}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMsg = 'تعذّر الاختبار: $e';
        _busy = false;
      });
    }
  }

  Future<void> _save() async {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _error = 'أدخل عنوان الخادم واسم المستخدم');
      return;
    }
    if (!_isEdit && _pass.text.isEmpty) {
      setState(() => _error = 'كلمة المرور مطلوبة للحساب الجديد');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await widget.api.updateAgentSasAccount(widget.existing!['id'] as int,
            label: _label.text.trim(),
            host: _host.text.trim(),
            username: _user.text.trim(),
            password: _pass.text.isEmpty ? null : _pass.text,
            https: _https,
            verifyTls: _verifyTls);
      } else {
        await widget.api.addAgentSasAccount(
            label: _label.text.trim(),
            host: _host.text.trim(),
            username: _user.text.trim(),
            password: _pass.text,
            https: _https,
            verifyTls: _verifyTls);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'تعديل حساب SAS' : 'إضافة حساب SAS'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_error != null) ...[
              PBanner.error(_error!),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _label,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'اسم مميّز للحساب (اختياري)',
                hintText: 'مثال: مزوّد أ',
                prefixIcon: Icon(PhosphorIconsBold.tag, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _host,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'عنوان خادم SAS (host أو IP[:port])',
                hintText: 'itpc4.provider.com',
                prefixIcon: Icon(PhosphorIconsBold.globe, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _user,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'اسم مستخدم SAS',
                prefixIcon: Icon(PhosphorIconsBold.user, size: 18),
              ),
            ),
            const SizedBox(height: 10),
            PasswordField(
                controller: _pass,
                enabled: !_busy,
                label: _hasPassword ? 'كلمة المرور (اتركها فارغة للإبقاء)' : 'كلمة المرور'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('استخدام HTTPS'),
              value: _https,
              onChanged: _busy ? null : (v) => setState(() => _https = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تحقّق شهادة TLS'),
              subtitle: const Text('أطفئه للشهادات الذاتية'),
              value: _verifyTls,
              onChanged: _busy ? null : (v) => setState(() => _verifyTls = v),
            ),
            if (_testMsg != null) ...[
              const SizedBox(height: 8),
              _testOk == true ? PBanner.success(_testMsg!) : PBanner.error(_testMsg!),
            ],
          ]),
        ),
      ),
      actions: [
        if (_isEdit)
          TextButton.icon(
            onPressed: _busy ? null : _test,
            icon: const Icon(PhosphorIconsBold.plugsConnected, size: 16),
            label: const Text('اختبار'),
          ),
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('إلغاء')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}

/// شاشة «إعداد اتصال الوكيل بـ SAS» — (احتياطية/توافق) لحساب واحد عبر /agent/sas-config.
/// الواجهة الأساسية الآن AgentSasAccountsScreen (تدعم عدة حسابات).
class AgentSasConfigScreen extends StatefulWidget {
  final StaffApi api;
  final int companyId;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;
  const AgentSasConfigScreen({
    super.key,
    required this.api,
    required this.companyId,
    this.onSaved,
    this.onCancel,
  });

  @override
  State<AgentSasConfigScreen> createState() => _AgentSasConfigScreenState();
}

class _AgentSasConfigScreenState extends State<AgentSasConfigScreen> {
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _https = false;
  bool _verifyTls = false;
  bool _hasPassword = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _testMsg;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await widget.api.agentSasConfig();
      if (!mounted) return;
      setState(() {
        _host.text = c['sas_host'] as String? ?? '';
        _user.text = c['sas_username'] as String? ?? '';
        _https = c['sas_https'] == true;
        _verifyTls = c['sas_verify_tls'] == true;
        _hasPassword = c['has_password'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _test() async {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _error = 'أدخل عنوان الخادم واسم المستخدم أولاً');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _testMsg = null;
      _testOk = null;
    });
    try {
      // نمرّر خادم الوكيل وبياناته (الباكند يستخدم إعداد الوكيل نفسه).
      final r = await widget.api.testSas(widget.companyId,
          host: _host.text.trim(),
          username: _user.text.trim(),
          password: _pass.text.isEmpty ? null : _pass.text,
          https: _https,
          verifyTls: _verifyTls);
      if (!mounted) return;
      final ok = r['ok'] == true;
      setState(() {
        _testOk = ok;
        _testMsg = ok
            ? 'الاتصال ناجح بحسابك — إجمالي مشتركيك: ${r['summary']?['total'] ?? '؟'}'
            : 'فشل الاتصال: ${r['error'] ?? ''}';
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testOk = false;
        _testMsg = 'تعذّر الاختبار: $e';
        _busy = false;
      });
    }
  }

  Future<void> _save() async {
    if (_host.text.trim().isEmpty || _user.text.trim().isEmpty) {
      setState(() => _error = 'أدخل عنوان الخادم واسم المستخدم');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await widget.api.saveAgentSasConfig(
          host: _host.text.trim(),
          username: _user.text.trim(),
          password: _pass.text.isEmpty ? null : _pass.text,
          https: _https,
          verifyTls: _verifyTls);
      if (!mounted) return;
      // حفظ محلي بعد الحفظ: إن اكتمل الإعداد نسحب مشتركيه ونخزّنها محلياً الآن.
      if (res['configured'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('حُفظت البيانات — جارٍ سحب مشتركيك وحفظهم محلياً…')));
        String msg = 'حُفظت بيانات اتصالك بنظام SAS';
        try {
          final sync = await widget.api.syncAgentNow();
          final n = (sync['count'] as num?)?.toInt() ?? 0;
          msg = 'حُفظ · تمت مزامنة $n مشترك محلياً';
        } catch (e) {
          msg = 'حُفظت البيانات، لكن تعذّرت المزامنة الآن: $e';
        }
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      } else {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('حُفظت بيانات اتصالك بنظام SAS')));
      }
      widget.onSaved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(PhosphorIconsDuotone.identificationCard, color: pal.accent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text('إعداد اتصالك بنظام SAS',
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (widget.onCancel != null)
                TextButton(onPressed: _busy ? null : widget.onCancel, child: const Text('إلغاء')),
            ]),
            const SizedBox(height: 6),
            Text(
                'تتصل بنظام SAS بحساب المدير الخاص بك: أدخل عنوان خادم SAS واسم مستخدمك '
                'وكلمة مرورك — فترى مشتركيك فقط.',
                style: t.bodyMedium?.copyWith(color: pal.textMuted, height: 1.5)),
            const SizedBox(height: Space.lg),
            if (_error != null) ...[
              PBanner.error(_error!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _host,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'عنوان خادم SAS (host أو IP[:port])',
                hintText: 'itpc4.provider.com',
                prefixIcon: Icon(PhosphorIconsBold.globe, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'اسم مستخدم SAS الخاص بك',
                prefixIcon: Icon(PhosphorIconsBold.user, size: 18),
              ),
            ),
            const SizedBox(height: 12),
            PasswordField(
                controller: _pass,
                enabled: !_busy,
                label: _hasPassword ? 'كلمة المرور (اتركها فارغة للإبقاء)' : 'كلمة المرور'),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('استخدام HTTPS'),
              value: _https,
              onChanged: _busy ? null : (v) => setState(() => _https = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تحقّق شهادة TLS'),
              subtitle: const Text('أطفئه للشهادات الذاتية'),
              value: _verifyTls,
              onChanged: _busy ? null : (v) => setState(() => _verifyTls = v),
            ),
            if (_testMsg != null) ...[
              const SizedBox(height: 10),
              _testOk == true ? PBanner.success(_testMsg!) : PBanner.error(_testMsg!),
            ],
            const SizedBox(height: Space.lg),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: const Icon(PhosphorIconsBold.plugsConnected, size: 18),
                  label: const Text('اختبار الاتصال'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(PhosphorIconsBold.floppyDisk, size: 18),
                  label: const Text('حفظ'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
