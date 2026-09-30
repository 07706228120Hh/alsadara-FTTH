/// شاشة تحرير قوالب واتساب — تعديل النصّ، إدراج متغيّرات، إعادة ضبط، إضافة/حذف.
library;

import 'package:flutter/material.dart';

import '../models/wa_template.dart';
import '../templates/default_templates.dart';
import '../templates/template_store.dart';

class WaTemplatesScreen extends StatefulWidget {
  const WaTemplatesScreen({super.key});
  @override
  State<WaTemplatesScreen> createState() => _WaTemplatesScreenState();
}

class _WaTemplatesScreenState extends State<WaTemplatesScreen> {
  final _store = LocalTemplateStore();
  List<WaTemplate> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await _store.load();
    if (mounted) setState(() { _templates = t; _loading = false; });
  }

  Future<void> _edit(WaTemplate tpl) async {
    final result = await Navigator.of(context).push<WaTemplate>(
      MaterialPageRoute(builder: (_) => _TemplateEditor(template: tpl)),
    );
    if (result != null) {
      await _store.save(result);
      await _load();
    }
  }

  Future<void> _resetBuiltin(WaTemplate tpl) async {
    await _store.delete(tpl.id); // للمدمج = إعادة لأصله
    await _load();
  }

  Future<void> _deleteCustom(WaTemplate tpl) async {
    await _store.delete(tpl.id);
    await _load();
  }

  Future<void> _addCustom() async {
    // معرّف مخصّص فريد بسيط مبني على الطول (بلا Random لتوافق الأدوات).
    final id = 'custom_${_templates.length + 1}_${_templates.map((t) => t.id).join().length}';
    final tpl = WaTemplate(id: id, title: 'قالب جديد', body: 'مرحباً {name} 👋\n');
    await _edit(tpl);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قوالب الرسائل'),
          actions: [
            IconButton(onPressed: _addCustom, icon: const Icon(Icons.add), tooltip: 'قالب جديد'),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _templates.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final t = _templates[i];
                  final modified = t.builtin && _isModified(t);
                  return Card(
                    child: ListTile(
                      title: Row(children: [
                        Flexible(child: Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                        const SizedBox(width: 6),
                        if (t.builtin) const _Tag('مدمج', Colors.blueGrey),
                        if (modified) const _Tag('معدّل', Colors.orange),
                      ]),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(t.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(t);
                          if (v == 'reset') _resetBuiltin(t);
                          if (v == 'delete') _deleteCustom(t);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          if (t.builtin && modified) const PopupMenuItem(value: 'reset', child: Text('إعادة للأصل')),
                          if (!t.builtin) const PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                      onTap: () => _edit(t),
                    ),
                  );
                },
              ),
      ),
    );
  }

  bool _isModified(WaTemplate t) {
    for (final d in kDefaultTemplates) {
      if (d.id == t.id) return d.body != t.body || d.title != t.title;
    }
    return false;
  }
}

/// محرّر قالب واحد — عنوان + نصّ + رقائق إدراج المتغيّرات.
class _TemplateEditor extends StatefulWidget {
  final WaTemplate template;
  const _TemplateEditor({required this.template});
  @override
  State<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends State<_TemplateEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;

  static const _vars = ['name', 'username', 'profile', 'expiration', 'days'];
  static const _varLabels = {
    'name': 'الاسم',
    'username': 'المستخدم',
    'profile': 'الباقة',
    'expiration': 'الانتهاء',
    'days': 'الأيام',
  };

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.template.title);
    _body = TextEditingController(text: widget.template.body);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _insertVar(String v) {
    final sel = _body.selection;
    final text = _body.text;
    final token = '{$v}';
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final next = text.replaceRange(start, end, token);
    _body.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + token.length),
    );
  }

  void _save() {
    Navigator.of(context).pop(widget.template.copyWith(
      title: _title.text.trim().isEmpty ? widget.template.title : _title.text.trim(),
      body: _body.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.template.builtin ? 'تعديل قالب مدمج' : 'تعديل القالب'),
          actions: [
            TextButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('حفظ')),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _body,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'نصّ الرسالة',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            Text('أدرج متغيّراً:', style: tt.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final v in _vars)
                  ActionChip(
                    label: Text('${_varLabels[v]}  {$v}'),
                    onPressed: () => _insertVar(v),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'المتغيّرات تُستبدل تلقائياً لكل مستلِم عند الإرسال. أي متغيّر بلا قيمة يُحذف سطره.',
              style: tt.bodySmall?.copyWith(color: Theme.of(context).hintColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
    );
  }
}
