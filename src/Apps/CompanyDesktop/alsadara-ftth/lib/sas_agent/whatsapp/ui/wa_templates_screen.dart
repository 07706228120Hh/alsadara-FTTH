/// شاشة تحرير قوالب واتساب — بثيم الصدارة (Cairo/AppTheme/SasUi).
///
/// تعديل النصّ، إدراج متغيّرات، إعادة ضبط المدمج، إضافة/حذف مخصّص.
/// عرض فقط لواجهة القوالب — المنطق في `LocalTemplateStore` بلا تغيير.
library;

import 'package:flutter/material.dart';

import '../../../frontend/frontend.dart';
import '../../widgets/sas_metrics.dart';
import '../../widgets/sas_state_views.dart';
import '../models/wa_template.dart';
import '../templates/default_templates.dart';
import '../templates/template_store.dart';

/// لون واتساب المعتمد في الوحدة (شارات/تمييزات خفيفة).
const Color _kWaGreen = SdColors.whatsapp;

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
    if (mounted) {
      setState(() {
        _templates = t;
        _loading = false;
      });
    }
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
    final id =
        'custom_${_templates.length + 1}_${_templates.map((t) => t.id).join().length}';
    final tpl = WaTemplate(id: id, title: 'قالب جديد', body: 'مرحباً {name} 👋\n');
    await _edit(tpl);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: _waAppBar(
          context,
          title: 'قوالب الرسائل',
          actions: [
            IconButton(
              onPressed: _addCustom,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              tooltip: 'قالب جديد',
            ),
          ],
        ),
        body: _loading
            ? const SasLoadingView(message: 'جاري تحميل القوالب…')
            : SasContentWrap(
                maxWidth: 860,
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 20.h),
                  itemCount: _templates.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (_, i) => _templateCard(_templates[i]),
                ),
              ),
      ),
    );
  }

  Widget _templateCard(WaTemplate t) {
    final modified = t.builtin && _isModified(t);
    return Container(
      decoration: SasUi.card(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _edit(t),
          borderRadius: BorderRadius.circular(SasUi.radius.r),
          child: Padding(
            padding: EdgeInsets.all(13.w),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SasUi.gradientBadge(
                  icon: Icons.chat_bubble_rounded,
                  colors: const [_kWaGreen, SdColors.whatsappEdge],
                  size: 40,
                  iconSize: 19,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6.w,
                        runSpacing: 4.h,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            t.title,
                            style: TextStyle(fontFamily: 'Cairo', 
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w800,
                              color: SdColors.ink,
                            ),
                          ),
                          if (t.builtin)
                            const SasStatusBadge(
                                label: 'مدمج',
                                color: SdColors.info,
                                icon: Icons.verified_rounded),
                          if (modified)
                            const SasStatusBadge(
                                label: 'معدّل',
                                color: SdColors.warning,
                                icon: Icons.edit_rounded),
                        ],
                      ),
                      SizedBox(height: 6.h),
                      Text(
                        t.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: 'Cairo', 
                          fontSize: 11.5.sp,
                          color: SdColors.muted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded,
                      color: SdColors.faint, size: 20.sp),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                  onSelected: (v) {
                    if (v == 'edit') _edit(t);
                    if (v == 'reset') _resetBuiltin(t);
                    if (v == 'delete') _deleteCustom(t);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_rounded,
                            size: 18, color: SdColors.primary),
                        SizedBox(width: 8.w),
                        Text('تعديل', style: TextStyle(fontFamily: 'Cairo', )),
                      ]),
                    ),
                    if (t.builtin && modified)
                      PopupMenuItem(
                        value: 'reset',
                        child: Row(children: [
                          Icon(Icons.restart_alt_rounded,
                              size: 18, color: SdColors.warning),
                          SizedBox(width: 8.w),
                          Text('إعادة للأصل', style: TextStyle(fontFamily: 'Cairo', )),
                        ]),
                      ),
                    if (!t.builtin)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_rounded,
                              size: 18, color: SdColors.danger),
                          SizedBox(width: 8.w),
                          Text('حذف',
                              style: TextStyle(fontFamily: 'Cairo', 
                                  color: SdColors.danger)),
                        ]),
                      ),
                  ],
                ),
              ],
            ),
          ),
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

/// محرّر قالب واحد — عنوان + نصّ + رقائق إدراج المتغيّرات (بثيم الصدارة).
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: _waAppBar(
          context,
          title: widget.template.builtin ? 'تعديل قالب مدمج' : 'تعديل القالب',
          actions: [
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded, color: Colors.white),
              label: Text('حفظ',
                  style: TextStyle(fontFamily: 'Cairo', 
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        body: SasContentWrap(
          maxWidth: 760,
          child: ListView(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
          children: [
            Container(
              padding: EdgeInsets.all(14.w),
              decoration: SasUi.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('العنوان',
                      style: TextStyle(fontFamily: 'Cairo', 
                          fontSize: 12.sp, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: _title,
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp),
                    decoration: const InputDecoration(isDense: true),
                  ),
                  SizedBox(height: 16.h),
                  Text('نصّ الرسالة',
                      style: TextStyle(fontFamily: 'Cairo', 
                          fontSize: 12.sp, fontWeight: FontWeight.w800)),
                  SizedBox(height: 8.h),
                  TextField(
                    controller: _body,
                    maxLines: 8,
                    style: TextStyle(fontFamily: 'Cairo', fontSize: 13.sp, height: 1.5),
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14.h),
            Container(
              padding: EdgeInsets.all(14.w),
              decoration: SasUi.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('أدرج متغيّراً:',
                      style: TextStyle(fontFamily: 'Cairo', 
                          fontSize: 12.sp, fontWeight: FontWeight.w800)),
                  SizedBox(height: 10.h),
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: [
                      for (final v in _vars)
                        ActionChip(
                          label: Text('${_varLabels[v]}  {$v}',
                              style: TextStyle(fontFamily: 'Cairo', 
                                  fontSize: 11.5.sp,
                                  fontWeight: FontWeight.w700)),
                          backgroundColor:
                              SdColors.primary.withValues(alpha: 0.06),
                          side: BorderSide(
                              color:
                                  SdColors.primary.withValues(alpha: 0.25)),
                          onPressed: () => _insertVar(v),
                        ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    'المتغيّرات تُستبدل تلقائياً لكل مستلِم عند الإرسال. أي متغيّر بلا قيمة يُحذف سطره.',
                    style: TextStyle(fontFamily: 'Cairo', 
                        fontSize: 11.sp, color: SdColors.muted, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// شريط تطبيق بثيم الصدارة (تدرّج أزرق + عنوان Cairo أبيض) — مشترك لشاشات الوحدة.
PreferredSizeWidget _waAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
}) {
  return SdAppBar(title: title, actions: actions);
}
