import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../../frontend/frontend.dart'; // نظام تصميم الصدارة الموحّد (sd)
import '../../permissions/permission_manager.dart';
import '../models/sas_account.dart';
import '../models/sas_accounting.dart';
import '../services/sas_agent_api_service.dart';
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
          style: const TextStyle(
              fontFamily: SdText.family, fontWeight: FontWeight.w600)),
      backgroundColor: error ? SdColors.danger : SdColors.success,
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
    final hasItems = !_loading && _error == null && _items.isNotEmpty;
    return SdPage(
      maxWidth: SdSpace.formMax,
      scrollable: hasItems,
      appBar: SdAppBar(
        title: 'أسعار الباقات',
        actions: [
          SdAppBarAction(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onPressed: _loading ? null : _refreshManual,
          ),
        ],
      ),
      bottomBar: hasItems ? _saveBar() : null,
      body: _body(),
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
      return const SdEmptyState(
        title: 'لا توجد باقات لتسعيرها',
        icon: Icons.inventory_2_rounded,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _accountStrip(),
        const SizedBox(height: SdSpace.sm),
        _hint(),
        const SizedBox(height: SdSpace.sm),
        for (int i = 0; i < _items.length; i++) ...[
          _priceCard(_items[i]),
          const SizedBox(height: SdSpace.sm),
        ],
      ],
    );
  }

  /// شريط علوي صغير يوضّح أن الأسعار خاصة بالحساب النشط الحالي.
  Widget _accountStrip() {
    final name = widget.account.label.trim().isNotEmpty
        ? widget.account.label.trim()
        : widget.account.username;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: SdColors.primaryTint,
        borderRadius: BorderRadius.circular(SdRadius.sm),
        border: Border.all(color: SdColors.primaryTintEdge),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_circle_rounded,
              color: SdColors.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: SdText.bodySm.copyWith(color: SdColors.ink),
                children: [
                  const TextSpan(text: 'الباقات لحساب: '),
                  TextSpan(
                    text: name,
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        fontWeight: FontWeight.w800,
                        color: SdColors.primary),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SdColors.infoTint,
        borderRadius: BorderRadius.circular(SdRadius.sm),
        border: Border.all(color: SdColors.infoTintEdge),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: SdColors.info, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'حدّد سعر البيع لكل باقة (يُحصَّل من المشترك). السعر الأساسي يُخصم '
              'تلقائياً من رصيد الصفحة وقت التجديد، والربح = سعر البيع + أجور '
              'الصيانة − الأساسي. فعّل/عطّل الباقة من المفتاح، ثم اضغط «حفظ».',
              style: SdText.bodySm
                  .copyWith(color: SdColors.infoEdge, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceCard(SasPackagePrice p) {
    return SdCard(
      tone: SdStatus.info.tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: SdColors.infoTint,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: const [
                    BoxShadow(
                        color: SdColors.infoTintEdge, offset: Offset(0, 3))
                  ],
                ),
                child: const Icon(Icons.wifi_tethering_rounded,
                    color: SdColors.info, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  p.profileName.isEmpty ? p.profileId : p.profileName,
                  overflow: TextOverflow.ellipsis,
                  style: SdText.titleSm,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('مفعّل', style: SdText.caption),
                  Switch(
                    value: p.isActive,
                    activeThumbColor: SdColors.success,
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
          const SizedBox(height: 8),
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
    OutlineInputBorder border(Color color, [double width = 1.2]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          borderSide: BorderSide(color: color, width: width),
        );
    return TextFormField(
      initialValue: _fmt(initial),
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: const TextStyle(
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: SdColors.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
            fontFamily: SdText.family, color: SdColors.muted, fontSize: 11.5),
        isDense: true,
        filled: true,
        fillColor: SdColors.surface,
        border: border(SdColors.edge),
        enabledBorder: border(SdColors.edge),
        focusedBorder: border(SdColors.primary, 1.6),
      ),
      onChanged: (t) => onChanged(num.tryParse(t.trim()) ?? 0),
    );
  }

  Widget _saveBar() {
    return Row(
      children: [
        const Icon(Icons.inventory_2_rounded,
            size: 18, color: SdColors.primary),
        const SizedBox(width: 8),
        Text('${_items.length} باقة', style: SdText.bodySm),
        const Spacer(),
        if (_saving)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: SdColors.primary),
          )
        else
          SdButton(
            label: _canManage ? 'حفظ' : 'لا صلاحية',
            icon: Icons.save_rounded,
            onPressed: _canManage ? _save : null,
          ),
      ],
    );
  }

  /// صياغة رقم بلا كسور زائدة (123.0 → 123).
  String _fmt(num v) =>
      (v == v.roundToDouble()) ? v.round().toString() : v.toString();
}
