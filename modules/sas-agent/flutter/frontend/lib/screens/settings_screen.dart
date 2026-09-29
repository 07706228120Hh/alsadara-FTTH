import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:platform_core/platform_core.dart';

import 'sas_explorer_screen.dart';

/// شاشة «الإعدادات» — مركز إعداد التطبيق المستقل:
///  • الحساب: هوية الوكيل ونطاقه.
///  • الخادم: العنوان الحالي (محلي/سحابي) وفحص الاتصال.
///  • SAS: مدخل سريع لإعداد اتصال الوكيل بنظام SAS.
///  • المظهر: تبديل الوضع الفاتح/الداكن.
///  • متقدّم — ميزات محفوظة: قدرات المنصّة (OLT/المراقبة/التزويد…) محفوظة في
///    الخادم للاستفادة منها لاحقاً؛ تُعرَض هنا كمداخل مؤجّلة (لا تُحذف).
class SettingsScreen extends StatefulWidget {
  final StaffApi api;
  const SettingsScreen({super.key, required this.api});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _healthOk;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() => _checking = true);
    bool ok;
    try {
      await widget.api.core.get('/api/health');
      ok = true;
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() { _healthOk = ok; _checking = false; });
  }

  Future<void> _load() async => _checkHealth();

  void _openSasConfig() {
    final cid = Session.companyId;
    if (cid == null) {
      showMsg(context, 'لا شركة مرتبطة بهذا الحساب', error: true);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('إعداد اتصالي بـ SAS')),
        body: AgentSasConfigScreen(
          api: widget.api,
          companyId: cid,
          onSaved: () {
            Navigator.of(context).maybePop();
            showMsg(context, 'حُفظت بيانات اتصالك بنظام SAS');
          },
          onCancel: () => Navigator.of(context).maybePop(),
        ),
      ),
    ));
  }

  void _openExplorer() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SasExplorerScreen(api: widget.api),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pal = context.pal;
    final env = PlatformConfig.isDevEnvironment ? 'محلي (تطوير)' : 'سحابي (إنتاج)';

    return TabPage(
      title: 'الإعدادات',
      subtitle: 'الحساب · الخادم · SAS · ميزات محفوظة',
      onRefresh: _load,
      actions: const [ThemeToggleButton()],
      child: ListView(padding: const EdgeInsets.all(14), children: [
        // ── الحساب ──
        const SectionTitle('الحساب'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              KVRow('المستخدم', Session.user ?? '—'),
              KVRow('الدور', _roleAr(Session.role)),
              KVRow('الوكيل', Session.agent.isEmpty ? '—' : Session.agent),
              KVRow('معرّف الشركة', Session.companyId?.toString() ?? '—'),
            ]),
          ),
        ),

        // ── الخادم ──
        const SectionTitle('الخادم'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const KVRow('العنوان', PlatformConfig.apiBase),
              KVRow('البيئة', env),
              const KVRow('الإصدار', PlatformConfig.appVersion),
              const SizedBox(height: 8),
              Row(children: [
                _healthChip(),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _checking ? null : _checkHealth,
                  icon: _checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(PhosphorIconsBold.plugsConnected, size: 18),
                  label: const Text('فحص الاتصال'),
                ),
              ]),
            ]),
          ),
        ),

        // ── SAS ──
        const SectionTitle('نظام SAS'),
        Card(
          child: Column(children: [
            ListTile(
              leading: Icon(PhosphorIconsDuotone.database, color: pal.accent),
              title: const Text('إعداد اتصالي بـ SAS'),
              subtitle: const Text('اسم المستخدم وكلمة المرور الخاصان بك (الخادم موروث من شركتك)'),
              trailing: const Icon(PhosphorIconsBold.caretLeft, size: 16),
              onTap: _openSasConfig,
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(PhosphorIconsDuotone.binoculars, color: pal.info),
              title: const Text('مستكشف SAS — التقاط الطلبات'),
              subtitle: const Text('متصفّح مدمج يفتح لوحة SAS ويلتقط كل طلبات الـ API لتحليلها'),
              trailing: const Icon(PhosphorIconsBold.caretLeft, size: 16),
              onTap: _openExplorer,
            ),
          ]),
        ),

        // ── متقدّم — ميزات محفوظة ──
        const SectionTitle('متقدّم — ميزات محفوظة'),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'هذه القدرات محفوظة في الخادم للاستفادة منها لاحقاً — غير مفعّلة في واجهة الوكيل حالياً.',
            style: tt.bodySmall?.copyWith(color: pal.textMuted, height: 1.5),
          ),
        ),
        Card(
          child: Column(children: [
            for (final f in _preserved) ...[
              ListTile(
                leading: Icon(f.icon, color: pal.textMuted),
                title: Text(f.title),
                subtitle: Text(f.desc, style: tt.bodySmall),
                trailing: const _SavedChip(),
                onTap: () => _showPreservedInfo(f),
              ),
              if (f != _preserved.last) const Divider(height: 1),
            ],
          ]),
        ),

        // ── حول ──
        const SectionTitle('حول التطبيق'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('تطبيق الوكلاء — منتج مستقل',
                  style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'تطبيق مستقل لإدارة عمل الوكيل عبر نظام SAS الخاص بمزوّده — يعمل محلياً على '
                'ويندوز أو متصلاً بخادم سحابي (للهاتف).',
                style: tt.bodySmall?.copyWith(color: pal.textMuted, height: 1.6),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 30),
      ]),
    );
  }

  Widget _healthChip() {
    final ok = _healthOk;
    if (ok == null) {
      return StatusChip('جارٍ الفحص…', color: context.pal.textMuted, icon: PhosphorIconsBold.circleDashed);
    }
    return ok
        ? StatusChip('الخادم متصل', color: context.pal.success, icon: PhosphorIconsBold.checkCircle)
        : StatusChip('لا اتصال بالخادم', color: context.pal.danger, icon: PhosphorIconsBold.warningCircle);
  }

  void _showPreservedInfo(_Feature f) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(f.icon, color: context.pal.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(f.title)),
        ]),
        content: Text(
          '${f.desc}\n\nهذه الميزة محفوظة في الخادم (لم تُحذف) وستُفعَّل في واجهة الوكيل عند الحاجة لاحقاً.',
          style: const TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('حسناً')),
        ],
      ),
    );
  }

  static String _roleAr(String r) {
    switch (r) {
      case 'admin':
        return 'مدير';
      case 'operator':
        return 'مشغّل';
      default:
        return r;
    }
  }
}

/// شارة «محفوظ» للميزات المؤجّلة.
class _SavedChip extends StatelessWidget {
  const _SavedChip();
  @override
  Widget build(BuildContext context) =>
      StatusChip('محفوظ', color: context.pal.textMuted, icon: PhosphorIconsBold.archive);
}

class _Feature {
  final String title;
  final String desc;
  final IconData icon;
  const _Feature(this.title, this.desc, this.icon);
}

/// قدرات المنصّة المحفوظة في الخادم (تُعرَض كمداخل مؤجّلة — لا تُحذف).
const List<_Feature> _preserved = [
  _Feature('إدارة أجهزة OLT', 'الاتصال بأجهزة Huawei OLT عبر SSH/Telnet وإدارتها.', PhosphorIconsDuotone.hardDrives),
  _Feature('المراقبة اللحظية', 'مراقبة دورية للقياسات والقدرة الضوئية مع تنبيهات.', PhosphorIconsDuotone.pulse),
  _Feature('التزويد التلقائي (FTTH)', 'تدفّقات تزويد المشتركين وتسلسل الأوامر الآمن.', PhosphorIconsDuotone.plugs),
  _Feature('SNMP والإنذارات', 'استقبال Traps والاستعلام عبر OID وربطها بالتنبيهات.', PhosphorIconsDuotone.bellRinging),
  _Feature('التشخيص الذكي', 'محرك تشخيص بالقواعد الخبيرة من أدلة HCIA/HCIP.', PhosphorIconsDuotone.stethoscope),
  _Feature('اللوحة الوطنية والحوكمة', 'صور اللوحة الوطنية وطبقات GIS والحوكمة.', PhosphorIconsDuotone.mapTrifold),
  _Feature('العبور و DFOS', 'شبكات العبور ومراقبة الألياف DFOS.', PhosphorIconsDuotone.treeStructure),
  _Feature('المساعد الذكي (AI)', 'مساعد ذكاء اصطناعي هجين للدعم الفني.', PhosphorIconsDuotone.robot),
];
