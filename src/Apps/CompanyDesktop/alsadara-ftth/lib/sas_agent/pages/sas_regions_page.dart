import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../permissions/permission_manager.dart';
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_state_views.dart';

/// صفحة «المناطق وأجور الصيانة» — بيانات رئيسية على مستوى الشركة.
///
/// كل منطقة لها مبلغ صيانة ثابت يُطبَّق تلقائياً على مشتركيها عند التفعيل/التجديد.
/// CRUD كامل (إضافة/تعديل/حذف)؛ الحذف يُرفَض إن كانت المنطقة مرتبطة بمشتركين.
/// التعديل محكوم بصلاحية `sas_agent` (الحماية النهائية في الخادم).
class SasRegionsPage extends StatefulWidget {
  const SasRegionsPage({super.key});

  @override
  State<SasRegionsPage> createState() => _SasRegionsPageState();
}

class _SasRegionsPageState extends State<SasRegionsPage> {
  final _api = SasAgentApiService.instance;

  List<SasRegion> _items = [];
  bool _loading = true;
  String? _error;

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getRegions();
      if (!mounted) return;
      setState(() {
        _items = list;
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

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontFamily: SdText.family, fontWeight: FontWeight.w600)),
      backgroundColor: error ? SdColors.danger : SdColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _addOrEdit([SasRegion? existing]) async {
    if (!_canManage) return;
    final result = await showDialog<SasRegion>(
      context: context,
      builder: (_) => _RegionFormDialog(existing: existing),
    );
    if (result == null) return;
    setState(() => _loading = true);
    try {
      bool ok;
      if (existing == null) {
        ok = (await _api.createRegion(result)) != null;
      } else {
        ok = await _api.updateRegion(existing.id, result);
      }
      if (!mounted) return;
      _toast(ok ? 'تم الحفظ' : 'تعذّر الحفظ', error: !ok);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _toast('فشل: ${_clean(e)}', error: true);
      }
    }
  }

  Future<void> _delete(SasRegion r) async {
    if (!_canManage) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف المنطقة',
              style: TextStyle(
                  fontFamily: SdText.family, fontWeight: FontWeight.w800)),
          content: Text('حذف المنطقة «${r.name}»؟',
              style: const TextStyle(
                  fontFamily: SdText.family, fontWeight: FontWeight.w600)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(fontFamily: SdText.family))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: SdColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف',
                  style: TextStyle(
                      fontFamily: SdText.family, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    setState(() => _loading = true);
    try {
      final ok = await _api.deleteRegion(r.id);
      if (!mounted) return;
      _toast(ok ? 'تم حذف المنطقة' : 'تعذّر الحذف', error: !ok);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _toast('فشل: ${_clean(e)}', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasList = !_loading && _error == null && _items.isNotEmpty;
    return SdPage(
      maxWidth: 1240,
      scrollable: false,
      padding: hasList ? EdgeInsets.zero : null,
      appBar: SdAppBar(
        title: 'المناطق وأجور الصيانة',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              backgroundColor: SdColors.primary,
              onPressed: _loading ? null : () => _addOrEdit(),
              icon: const Icon(Icons.add_location_alt_rounded,
                  color: Colors.white),
              label: const Text('منطقة جديدة',
                  style: TextStyle(
                      fontFamily: SdText.family,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            )
          : null,
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب المناطق…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const SdEmptyState(
        title: 'لا توجد مناطق',
        message: 'أضف منطقة لربط المشتركين وتطبيق أجور الصيانة',
        icon: Icons.map_rounded,
      );
    }
    // شبكة بطاقات متجاوبة: بطاقة مدمجة عمودية بعرض ثابت (~340) تمنع اقتطاع النصوص.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          SdSpace.gutter, SdSpace.md, SdSpace.gutter, 96),
      child: LayoutBuilder(
        builder: (ctx, c) {
          const double minCard = 320;
          const double gap = 12;
          final cols = (c.maxWidth / minCard).floor().clamp(1, 4);
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final r in _items) SizedBox(width: w, child: _regionCard(r)),
            ],
          );
        },
      ),
    );
  }

  /// بطاقة منطقة مدمجة: ترويسة (أيقونة + اسم + حالة) · تفاصيل · أجور الصيانة · إجراءات.
  Widget _regionCard(SasRegion r) {
    final tone = r.isActive ? SdStatus.success.tone : SdGroup.neutral.tone;
    return SdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ترويسة: أيقونة + اسم + شارة حالة.
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tone.tint,
                  borderRadius: BorderRadius.circular(SdRadius.sm),
                  boxShadow: [
                    BoxShadow(color: tone.tintEdge, offset: const Offset(0, 3))
                  ],
                ),
                child: Icon(Icons.location_on_rounded,
                    color: tone.base, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.name.isEmpty ? '—' : r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SdText.label,
                ),
              ),
              if (!r.isActive)
                const SdStatusChip('موقوفة', status: SdStatus.neutral),
            ],
          ),
          const SizedBox(height: 10),
          // تفاصيل: الموقع + عدد المشتركين.
          Row(
            children: [
              const Icon(Icons.groups_rounded, size: 14, color: SdColors.faint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  [
                    if (r.governorate.isNotEmpty) r.governorate,
                    if (r.city.isNotEmpty) r.city,
                    '${r.subscribersCount} مشترك',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SdText.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // أجور الصيانة (بارزة).
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: SdColors.warningTint,
              borderRadius: BorderRadius.circular(SdRadius.sm),
              border: Border.all(color: SdColors.warningTintEdge),
            ),
            child: Row(
              children: [
                const Icon(Icons.build_rounded,
                    size: 14, color: SdColors.warning),
                const SizedBox(width: 6),
                Text('أجور الصيانة', style: SdText.caption),
                const Spacer(),
                Text('${r.maintenanceFee} د.ع',
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: SdColors.warningText)),
              ],
            ),
          ),
          if (_canManage) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _addOrEdit(r),
                  icon: const Icon(Icons.edit_rounded,
                      color: SdColors.info, size: 17),
                  label: Text('تعديل',
                      style: SdText.caption.copyWith(color: SdColors.info)),
                ),
                TextButton.icon(
                  onPressed: () => _delete(r),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: SdColors.danger, size: 17),
                  label: Text('حذف',
                      style: SdText.caption.copyWith(color: SdColors.danger)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// حوار إضافة/تعديل منطقة.
class _RegionFormDialog extends StatefulWidget {
  final SasRegion? existing;
  const _RegionFormDialog({this.existing});

  @override
  State<_RegionFormDialog> createState() => _RegionFormDialogState();
}

class _RegionFormDialogState extends State<_RegionFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _gov;
  late final TextEditingController _city;
  late final TextEditingController _fee;
  late final TextEditingController _notes;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _code = TextEditingController(text: e?.code ?? '');
    _gov = TextEditingController(text: e?.governorate ?? '');
    _city = TextEditingController(text: e?.city ?? '');
    _fee = TextEditingController(text: e == null ? '' : _fmt(e.maintenanceFee));
    _notes = TextEditingController(text: e?.notes ?? '');
    _active = e?.isActive ?? true;
  }

  String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  @override
  void dispose() {
    for (final c in [_name, _code, _gov, _city, _fee, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('اسم المنطقة مطلوب',
            style: TextStyle(
                fontFamily: SdText.family, fontWeight: FontWeight.w600)),
        backgroundColor: SdColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final fee = num.tryParse(_fee.text.trim()) ?? 0;
    Navigator.pop(
      context,
      SasRegion(
        id: widget.existing?.id ?? '',
        name: name,
        code: _code.text.trim(),
        governorate: _gov.text.trim(),
        city: _city.text.trim(),
        maintenanceFee: fee < 0 ? 0 : fee,
        isActive: _active,
        notes: _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.existing == null ? 'منطقة جديدة' : 'تعديل المنطقة',
            style: const TextStyle(
                fontFamily: SdText.family, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tf(_name, 'اسم المنطقة *'),
                const SizedBox(height: 10),
                _tf(_fee, 'أجور الصيانة (د.ع)',
                    number: true, hint: 'تُطبَّق تلقائياً على مشتركي المنطقة'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _tf(_gov, 'المحافظة')),
                    const SizedBox(width: 10),
                    Expanded(child: _tf(_city, 'المدينة/القضاء')),
                  ],
                ),
                const SizedBox(height: 10),
                _tf(_code, 'رمز اختياري'),
                const SizedBox(height: 10),
                _tf(_notes, 'ملاحظات'),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  activeThumbColor: SdColors.success,
                  title: const Text('مفعّلة',
                      style: TextStyle(
                          fontFamily: SdText.family,
                          fontWeight: FontWeight.w700)),
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء',
                  style: TextStyle(fontFamily: SdText.family))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SdColors.primary),
            onPressed: _submit,
            child: const Text('حفظ',
                style: TextStyle(
                    fontFamily: SdText.family, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _tf(TextEditingController c, String label,
      {bool number = false, String? hint}) {
    return TextField(
      controller: c,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      style: const TextStyle(
          fontFamily: SdText.family,
          fontWeight: FontWeight.w600,
          fontSize: 13,
          color: SdColors.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(
            fontFamily: SdText.family, color: SdColors.muted, fontSize: 12),
        hintStyle: const TextStyle(
            fontFamily: SdText.family, color: SdColors.faint, fontSize: 11.5),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SdRadius.sm)),
      ),
    );
  }
}
