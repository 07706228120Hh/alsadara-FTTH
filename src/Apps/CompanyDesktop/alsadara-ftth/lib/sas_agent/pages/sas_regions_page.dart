import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
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
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
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
          title: Text('حذف المنطقة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: Text('حذف المنطقة «${r.name}»؟',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء', style: GoogleFonts.cairo())),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: SasUi.pageBg,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: AppTheme.primaryColor,
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppTheme.orangeGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('المناطق وأجور الصيانة',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.white)),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        floatingActionButton: _canManage
            ? FloatingActionButton.extended(
                backgroundColor: AppTheme.primaryColor,
                onPressed: _loading ? null : () => _addOrEdit(),
                icon: const Icon(Icons.add_location_alt_rounded,
                    color: Colors.white),
                label: Text('منطقة جديدة',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w700, color: Colors.white)),
              )
            : null,
        body: _body(),
      ),
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
      return const SasEmptyView(
        message: 'لا توجد مناطق — أضف منطقة لربط المشتركين وتطبيق أجور الصيانة',
        icon: Icons.map_rounded,
      );
    }
    // شبكة بطاقات متجاوبة: بطاقة مدمجة عمودية بعرض ثابت (~340) تمنع اقتطاع النصوص.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 96.h),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
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
                  for (final r in _items)
                    SizedBox(width: w, child: _regionCard(r)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// بطاقة منطقة مدمجة: ترويسة (أيقونة + اسم + حالة) · تفاصيل · أجور الصيانة · إجراءات.
  Widget _regionCard(SasRegion r) {
    final statusColor = r.isActive ? AppTheme.successColor : Colors.grey;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ترويسة: أيقونة + اسم + شارة حالة.
          Row(
            children: [
              Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
                ),
                child: Icon(Icons.location_on_rounded,
                    color: statusColor, size: 20.sp),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  r.name.isEmpty ? '—' : r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w800, fontSize: 14.sp),
                ),
              ),
              if (!r.isActive) _chip('موقوفة', Colors.grey),
            ],
          ),
          SizedBox(height: 10.h),
          // تفاصيل: الموقع + عدد المشتركين.
          Row(
            children: [
              Icon(Icons.groups_rounded, size: 14.sp, color: Colors.grey[500]),
              SizedBox(width: 4.w),
              Expanded(
                child: Text(
                  [
                    if (r.governorate.isNotEmpty) r.governorate,
                    if (r.city.isNotEmpty) r.city,
                    '${r.subscribersCount} مشترك',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 11.5.sp, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          // أجور الصيانة (بارزة).
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: AppTheme.warningColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
              border: Border.all(
                  color: AppTheme.warningColor.withValues(alpha: 0.20)),
            ),
            child: Row(
              children: [
                Icon(Icons.build_rounded,
                    size: 14.sp, color: AppTheme.warningColor),
                SizedBox(width: 6.w),
                Text('أجور الصيانة',
                    style: GoogleFonts.cairo(
                        fontSize: 11.sp, color: Colors.grey[700])),
                const Spacer(),
                Text('${r.maintenanceFee} د.ع',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.sp,
                        color: AppTheme.warningColor)),
              ],
            ),
          ),
          if (_canManage) ...[
            SizedBox(height: 6.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _addOrEdit(r),
                  icon: Icon(Icons.edit_rounded,
                      color: AppTheme.infoColor, size: 17.sp),
                  label: Text('تعديل',
                      style: GoogleFonts.cairo(
                          color: AppTheme.infoColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5.sp)),
                ),
                TextButton.icon(
                  onPressed: () => _delete(r),
                  icon: Icon(Icons.delete_outline_rounded,
                      color: AppTheme.errorColor, size: 17.sp),
                  label: Text('حذف',
                      style: GoogleFonts.cairo(
                          color: AppTheme.errorColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5.sp)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(text,
            style: GoogleFonts.cairo(
                fontSize: 10.sp, fontWeight: FontWeight.w700, color: color)),
      );
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
    _fee = TextEditingController(
        text: e == null ? '' : _fmt(e.maintenanceFee));
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
        content: Text('اسم المنطقة مطلوب',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: AppTheme.errorColor,
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
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tf(_name, 'اسم المنطقة *'),
                SizedBox(height: 10.h),
                _tf(_fee, 'أجور الصيانة (د.ع)',
                    number: true, hint: 'تُطبَّق تلقائياً على مشتركي المنطقة'),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    Expanded(child: _tf(_gov, 'المحافظة')),
                    SizedBox(width: 10.w),
                    Expanded(child: _tf(_city, 'المدينة/القضاء')),
                  ],
                ),
                SizedBox(height: 10.h),
                _tf(_code, 'رمز اختياري'),
                SizedBox(height: 10.h),
                _tf(_notes, 'ملاحظات'),
                SizedBox(height: 6.h),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  activeThumbColor: AppTheme.successColor,
                  title: Text('مفعّلة',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('إلغاء', style: GoogleFonts.cairo())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            onPressed: _submit,
            child: Text('حفظ',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
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
      style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13.sp),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 12.sp),
        hintStyle: GoogleFonts.cairo(color: Colors.grey[400], fontSize: 10.5.sp),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
      ),
    );
  }
}
