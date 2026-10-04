import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:google_fonts/google_fonts.dart';

import '../../permissions/permission_manager.dart';
import '../../theme/app_theme.dart';
import '../models/sas_account.dart';
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
import '../widgets/sas_metrics.dart';
import '../widgets/sas_refresh_bus.dart';
import '../widgets/sas_state_views.dart';

/// صفحة «أسعار الباقات» — يحدّد الوكيل **سعر البيع** لكلّ باقة (ما يُحصَّل من
/// المشترك).
///
/// النموذج: الوكيل يُدخل سعر البيع فقط. السعر الأساسي (الكلفة) ديناميكي يُجلب
/// تلقائياً وقت التجديد من الساس (المبلغ الفعلي المخصوم من رصيد الصفحة)، والربح
/// يُحسب خادمياً = سعر البيع + أجور الصيانة − الأساسي. لذا لا تُعرض الكلفة ولا
/// الربح في البطاقة.
///
/// تعرض قائمة الباقات (من `getPackagePrices`) ببطاقات مدمجة قابلة للتعديل:
/// اسم الباقة + مفتاح التفعيل (في صف) + حقل سعر البيع أسفله. زر «حفظ» يرسل الكلّ
/// عبر `savePackagePrices`.
///
/// التعديل محكوم بصلاحية `sas_agent` (الحماية النهائية في الخادم).
class SasPackagePricesPage extends StatefulWidget {
  final SasAccount account;
  const SasPackagePricesPage({super.key, required this.account});

  @override
  State<SasPackagePricesPage> createState() => _SasPackagePricesPageState();
}

class _SasPackagePricesPageState extends State<SasPackagePricesPage> {
  final _api = SasAgentApiService.instance;

  List<SasPackagePrice> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// تعديلات غير محفوظة — نمنع إعادة التحميل الصامت من الناقل حتى لا تُفقَد.
  bool _dirty = false;

  /// اشتراك ناقل التحديث المشترك — يعيد جلب الأسعار عند أي حدث (ما لم تكن هناك
  /// تعديلات غير محفوظة).
  StreamSubscription<SasRefreshEvent>? _busSub;

  bool get _canManage => PermissionManager.instance.canAdd('sas_agent');

  @override
  void initState() {
    super.initState();
    _load();
    _busSub = SasRefreshBus.instance.stream.listen(_onBusEvent);
  }

  @override
  void dispose() {
    _busSub?.cancel();
    super.dispose();
  }

  /// عند إشعار الناقل الخاص بهذا الحساب: أعد الجلب بصمت — إلا إن كان المستخدم
  /// يُعدّل أسعاراً لم تُحفَظ بعد (لا نُطيح بتعديلاته).
  void _onBusEvent(SasRefreshEvent e) {
    if (!mounted || _loading || _saving || _dirty) return;
    if (!e.matches(widget.account.id)) return;
    _load(silent: true);
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '').trim();

  /// [silent] يعيد الجلب دون إظهار حالة تحميل (بلا وميض) — عند إشعار الناقل.
  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final list = await _api.getPackagePrices(widget.account.id);
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
        _dirty = false; // البيانات الآن مطابقة للخادم.
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

  Future<void> _save() async {
    if (!_canManage) return;
    setState(() => _saving = true);
    try {
      final ok = await _api.savePackagePrices(widget.account.id, _items);
      if (!mounted) return;
      _snack(ok ? 'تم حفظ أسعار الباقات' : 'تعذّر الحفظ', error: !ok);
      if (ok) await _load();
    } catch (e) {
      if (mounted) _snack(_clean(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppTheme.errorColor : AppTheme.successColor,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// تحديث يدوي (زر): مزامنة الحساب (قد تجلب باقات جديدة) ثم إعادة تحميل الأسعار
  /// + إشعار بقية التبويبات. المزامنة معزولة؛ إعادة التحميل تُسقط أي تعديل غير
  /// محفوظ (فعل صريح من المستخدم).
  Future<void> _refreshManual() async {
    await SasRefreshBus.instance
        .syncAndNotify(widget.account.id, reason: 'prices-refresh-button');
    if (mounted) await _load();
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
                colors: AppTheme.blueGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('أسعار الباقات',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.white)),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : _refreshManual,
            ),
          ],
        ),
        body: _body(),
        bottomNavigationBar:
            (_loading || _error != null || _items.isEmpty) ? null : _saveBar(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const SasLoadingView(message: 'جاري جلب أسعار الباقات…');
    }
    if (_error != null) {
      return SasErrorView(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return const SasEmptyView(
        message: 'لا توجد باقات لتسعيرها',
        icon: Icons.inventory_2_rounded,
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView(
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 96.h),
          children: [
            _accountStrip(),
            SizedBox(height: 10.h),
            _hint(),
            SizedBox(height: 12.h),
            for (int i = 0; i < _items.length; i++) ...[
              _priceCard(_items[i]),
              SizedBox(height: 10.h),
            ],
          ],
        ),
      ),
    );
  }

  /// شريط علوي صغير يوضّح أن الأسعار خاصة بالحساب النشط الحالي.
  Widget _accountStrip() {
    final name = widget.account.label.trim().isNotEmpty
        ? widget.account.label.trim()
        : widget.account.username;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        border:
            Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_circle_rounded,
              color: AppTheme.primaryColor, size: 20.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.cairo(
                    fontSize: 12.5.sp, color: Colors.grey[800]),
                children: [
                  const TextSpan(text: 'الباقات لحساب: '),
                  TextSpan(
                    text: name,
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hint() {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: AppTheme.infoColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(SasUi.radiusSm.r),
        border: Border.all(color: AppTheme.infoColor.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              color: AppTheme.infoColor, size: 20.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              'حدّد سعر البيع لكل باقة (يُحصَّل من المشترك). السعر الأساسي يُخصم '
              'تلقائياً من رصيد الصفحة وقت التجديد، والربح = سعر البيع + أجور '
              'الصيانة − الأساسي. فعّل/عطّل الباقة من المفتاح، ثم اضغط «حفظ».',
              style: GoogleFonts.cairo(
                  fontSize: 12.sp, color: Colors.grey[800], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceCard(SasPackagePrice p) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: SasUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SasUi.gradientBadge(
                icon: Icons.wifi_tethering_rounded,
                colors: const [AppTheme.infoColor, AppTheme.secondaryColor],
                size: 38,
                iconSize: 19,
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  p.profileName.isEmpty ? p.profileId : p.profileName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 14.5.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E)),
                ),
              ),
              SizedBox(width: 8.w),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('مفعّل',
                      style: GoogleFonts.cairo(
                          fontSize: 11.sp, color: Colors.grey[600])),
                  Switch(
                    value: p.isActive,
                    activeThumbColor: AppTheme.successColor,
                    onChanged: _canManage
                        ? (v) => setState(() {
                              p.isActive = v;
                              _dirty = true;
                            })
                        : null,
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 8.h),
          _numField(
            label: 'سعر البيع (يُحصَّل من المشترك)',
            initial: p.sellingPrice,
            enabled: _canManage,
            onChanged: (v) => setState(() {
              p.sellingPrice = v;
              _dirty = true;
            }),
          ),
        ],
      ),
    );
  }

  Widget _numField({
    required String label,
    required num initial,
    required bool enabled,
    required ValueChanged<num> onChanged,
  }) {
    return TextFormField(
      initialValue: _fmt(initial),
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: GoogleFonts.robotoMono(fontWeight: FontWeight.w700, fontSize: 13.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: Colors.grey[600], fontSize: 11.5.sp),
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(SasUi.radiusSm.r)),
      ),
      onChanged: (t) => onChanged(num.tryParse(t.trim()) ?? 0),
    );
  }

  Widget _saveBar() {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 12.h),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.inventory_2_rounded,
                size: 18.sp, color: AppTheme.primaryColor),
            SizedBox(width: 8.w),
            Text('${_items.length} باقة',
                style: GoogleFonts.cairo(
                    fontSize: 12.5.sp, fontWeight: FontWeight.w700)),
            const Spacer(),
            FilledButton.icon(
              onPressed: (!_canManage || _saving) ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                disabledBackgroundColor: Colors.grey.withValues(alpha: 0.30),
                padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 12.h),
              ),
              icon: _saving
                  ? SizedBox(
                      width: 16.w,
                      height: 16.w,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_canManage ? 'حفظ' : 'لا صلاحية',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  /// صياغة رقم بلا كسور زائدة (123.0 → 123).
  String _fmt(num v) =>
      (v == v.roundToDouble()) ? v.round().toString() : v.toString();
}
