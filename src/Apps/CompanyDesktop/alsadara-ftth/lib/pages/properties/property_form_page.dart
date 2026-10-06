/// نموذج إنشاء/تعديل عقار — المحافظة + المنطقة + النقطة الدالة + الموقع (GPS) +
/// النوع + الملكية + ملاحظات. بثيم الصدارة، RTL، ينادي بوّابة `/api/properties`.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/property.dart';
import '../../services/property_api_service.dart';
import '../../theme/app_theme.dart';
import 'location_master_page.dart';
import 'property_ui.dart';

/// محافظات العراق مع رمز المحافظة (GovCode) المطابق لمحرّك العنونة بالباكند.
const List<MapEntry<int, String>> _governorates = [
  MapEntry(1, 'بغداد'),
  MapEntry(2, 'البصرة'),
  MapEntry(3, 'نينوى'),
  MapEntry(4, 'أربيل'),
  MapEntry(5, 'السليمانية'),
  MapEntry(6, 'دهوك'),
  MapEntry(7, 'كركوك'),
  MapEntry(8, 'الأنبار'),
  MapEntry(9, 'ديالى'),
  MapEntry(10, 'صلاح الدين'),
  MapEntry(11, 'بابل'),
  MapEntry(12, 'واسط'),
  MapEntry(13, 'النجف'),
  MapEntry(14, 'كربلاء'),
  MapEntry(15, 'القادسية'),
  MapEntry(16, 'ميسان'),
  MapEntry(17, 'ذي قار'),
  MapEntry(18, 'المثنى'),
  MapEntry(19, 'حلبجة'),
];

class PropertyFormPage extends StatefulWidget {
  final Property? existing;
  const PropertyFormPage({super.key, this.existing});

  @override
  State<PropertyFormPage> createState() => _PropertyFormPageState();
}

class _PropertyFormPageState extends State<PropertyFormPage> {
  final _api = PropertyApiService.instance;
  final _form = GlobalKey<FormState>();

  late int _govCode = _resolveGovCode();
  late final _ownerName =
      TextEditingController(text: widget.existing?.ownerName ?? '');
  late final _ownerPhone =
      TextEditingController(text: widget.existing?.ownerPhone ?? '');
  late final _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  late String _ownership = _normalize(
      widget.existing?.ownership, kOwnershipLabels.keys.first); // Owned
  late String _property = _normalize(
      widget.existing?.propertyType, kPropertyTypeLabels.keys.first); // Residential
  double? _lat;
  double? _lon;
  bool _locating = false;
  bool _saving = false;

  // ─── البنية الهرمية للمواقع (المنطقة → العنوان 2 → العنوان 3) ───
  List<PropRegion> _regions = const [];
  List<AddressNode> _address2Options = const [];
  List<AddressNode> _address3Options = const [];
  String? _regionId;
  String? _address2Id;
  String? _address3Id;
  bool _loadingRegions = true;
  bool _loadingA2 = false;
  bool _loadingA3 = false;
  String? _locError;

  // أجر الصيانة الإجمالي التراكمي (منطقة + عنوان2 + عنوان3) — للعرض فقط.
  num? _totalFee;
  bool _loadingFee = false;
  int _feeReq = 0; // عدّاد لتجاهل استجابات طلبات قديمة (آخر طلب يفوز)

  int _resolveGovCode() {
    final e = widget.existing;
    if (e == null) return _governorates.first.key;
    if (e.govCode > 0) return e.govCode;
    // مطابقة بالاسم إن غاب الرمز
    for (final g in _governorates) {
      if (g.value == e.governorate) return g.key;
    }
    return _governorates.first.key;
  }

  /// يوحّد قيمة قادمة من الـAPI لمطابقة مفاتيح الخريطة (غير حسّاس لحالة الأحرف).
  String _normalize(String? v, String fallback) {
    if (v == null || v.trim().isEmpty) return fallback;
    for (final k in [...kOwnershipLabels.keys, ...kPropertyTypeLabels.keys]) {
      if (k.toLowerCase() == v.toLowerCase()) return k;
    }
    return v;
  }

  String get _govName =>
      _governorates.firstWhere((g) => g.key == _govCode).value;

  @override
  void initState() {
    super.initState();
    _lat = widget.existing?.latitude;
    _lon = widget.existing?.longitude;
    _loadRegions();
  }

  @override
  void dispose() {
    for (final c in [_ownerName, _ownerPhone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// يحمّل المناطق، ثم — عند التعديل — يعيد اختيار المنطقة/العناوين المطابقة تِباعاً.
  Future<void> _loadRegions() async {
    setState(() {
      _loadingRegions = true;
      _locError = null;
    });
    try {
      final regions = await _api.getRegions();
      if (!mounted) return;
      final preset = widget.existing?.regionId;
      final hasPreset =
          preset != null && regions.any((r) => r.id == preset);
      setState(() {
        _regions = regions;
        _regionId = hasPreset ? preset : null;
        _loadingRegions = false;
      });
      if (hasPreset) {
        await _loadAddress2(initial: widget.existing?.address2Id);
        if (!mounted) return;
        await _refreshTotalFee();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locError = '$e';
        _loadingRegions = false;
      });
    }
  }

  /// يحمّل عناوين (2) للمنطقة الحالية. [initial] يُعاد اختياره إن وُجد (للتعديل).
  Future<void> _loadAddress2({String? initial}) async {
    final rid = _regionId;
    if (rid == null) return;
    setState(() {
      _loadingA2 = true;
      _address2Options = const [];
      _address2Id = null;
      _address3Options = const [];
      _address3Id = null;
    });
    try {
      final list = await _api.getAddress2(rid);
      if (!mounted) return;
      final has = initial != null && list.any((a) => a.id == initial);
      setState(() {
        _address2Options = list;
        _address2Id = has ? initial : null;
        _loadingA2 = false;
      });
      if (has) {
        await _loadAddress3(initial: widget.existing?.address3Id);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingA2 = false);
      _msg('تعذّر تحميل العنوان 2: $e', err: true);
    }
  }

  /// يحمّل عناوين (3) للعنوان 2 الحالي. [initial] يُعاد اختياره إن وُجد.
  Future<void> _loadAddress3({String? initial}) async {
    final a2 = _address2Id;
    if (a2 == null) return;
    setState(() {
      _loadingA3 = true;
      _address3Options = const [];
      _address3Id = null;
    });
    try {
      final list = await _api.getAddress3(a2);
      if (!mounted) return;
      final has = initial != null && list.any((a) => a.id == initial);
      setState(() {
        _address3Options = list;
        _address3Id = has ? initial : null;
        _loadingA3 = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingA3 = false);
      _msg('تعذّر تحميل العنوان 3: $e', err: true);
    }
  }

  String? get _regionName {
    if (_regionId == null) return null;
    for (final r in _regions) {
      if (r.id == _regionId) return r.name;
    }
    return null;
  }

  String? get _address2Name {
    if (_address2Id == null) return null;
    for (final a in _address2Options) {
      if (a.id == _address2Id) return a.name;
    }
    return null;
  }

  String? get _address3Name {
    if (_address3Id == null) return null;
    for (final a in _address3Options) {
      if (a.id == _address3Id) return a.name;
    }
    return null;
  }

  /// يعيد حساب أجر الصيانة الإجمالي التراكمي عبر الخادم عند تغيّر أي مستوى.
  /// آخر طلب يفوز (عبر [_feeReq]) لتفادي تعارض الاستجابات المتأخّرة.
  Future<void> _refreshTotalFee() async {
    final rid = _regionId;
    if (rid == null) {
      if (mounted) {
        setState(() {
          _totalFee = null;
          _loadingFee = false;
        });
      }
      return;
    }
    final reqId = ++_feeReq;
    setState(() => _loadingFee = true);
    try {
      final total = await _api.computeMaintenanceFee(
        regionId: rid,
        address2Id: _address2Id,
        address3Id: _address3Id,
      );
      if (!mounted || reqId != _feeReq) return;
      setState(() {
        _totalFee = total;
        _loadingFee = false;
      });
    } catch (_) {
      if (!mounted || reqId != _feeReq) return;
      setState(() => _loadingFee = false);
    }
  }

  String _fmtFee(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _msg('خدمة الموقع غير مفعّلة على الجهاز', err: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _msg('لم يُسمح بالوصول إلى الموقع', err: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lon = pos.longitude;
      });
      _msg('حُدِّد الموقع: '
          '${pos.latitude.toStringAsFixed(5)}, '
          '${pos.longitude.toStringAsFixed(5)}');
    } catch (e) {
      _msg('تعذّر تحديد الموقع: $e', err: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      // اللقطات النصّية = أسماء المختارات (تظهر على بطاقة الـQR/الطباعة).
      final areaSnap = _regionName ?? '';
      final a2Snap = _address2Name ?? '';
      final a3Snap = _address3Name ?? '';
      if (widget.existing == null) {
        await _api.create(
          govCode: _govCode,
          governorate: _govName,
          area: areaSnap,
          district: '',
          landmark: '',
          addressDetails: '',
          latitude: _lat,
          longitude: _lon,
          propertyType: _property,
          ownership: _ownership,
          notes: _notes.text.trim(),
          ownerName: _ownerName.text.trim(),
          ownerPhone: _ownerPhone.text.trim(),
          address2: a2Snap,
          address3: a3Snap,
          regionId: _regionId,
          address2Id: _address2Id,
          address3Id: _address3Id,
        );
      } else {
        await _api.update(widget.existing!.id, {
          'govCode': _govCode,
          'governorate': _govName,
          'area': areaSnap,
          'latitude': _lat,
          'longitude': _lon,
          'propertyType': _property,
          'ownership': _ownership,
          'notes': _notes.text.trim(),
          'ownerName': _ownerName.text.trim(),
          'ownerPhone': _ownerPhone.text.trim(),
          'address2': a2Snap,
          'address3': a3Snap,
          'regionId': _regionId,
          'address2Id': _address2Id,
          'address3Id': _address3Id,
        });
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _msg('تعذّر الحفظ: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _msg(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: err ? AppTheme.errorColor : AppTheme.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PropUi.pageBg,
        appBar: PropUi.appBar(editing ? 'تعديل عقار' : 'عقار جديد',
            leadingIcon: Icons.edit_location_alt_rounded),
        body: Form(
          key: _form,
          child: PropContentWrap(
            maxWidth: 760,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: PropSectionHeader(
                          title: 'العنوان الوصفي',
                          icon: Icons.location_city_rounded,
                          gradient: AppTheme.blueGradient),
                    ),
                    TextButton.icon(
                      onPressed: _openLocationMaster,
                      icon: const Icon(Icons.layers_rounded, size: 18),
                      label: Text('إدارة المناطق',
                          style:
                              GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _panel([
                  _dropdown(),
                  const SizedBox(height: 12),
                  if (_locError != null) ...[
                    _locErrorRow(),
                    const SizedBox(height: 12),
                  ],
                  _regionDropdown(),
                  const SizedBox(height: 12),
                  _address2Dropdown(),
                  const SizedBox(height: 12),
                  _address3Dropdown(),
                  if (_regionId != null) ...[
                    const SizedBox(height: 12),
                    _feeSummary(),
                  ],
                ]),
                const SizedBox(height: 16),
                const PropSectionHeader(
                    title: 'صاحب الدار',
                    icon: Icons.person_pin_circle_rounded,
                    gradient: AppTheme.orangeGradient),
                const SizedBox(height: 10),
                _panel([
                  _text(_ownerName, 'اسم صاحب الدار',
                      icon: Icons.person_outline_rounded),
                  _text(_ownerPhone, 'رقم هاتف صاحب الدار',
                      icon: Icons.phone_rounded,
                      keyboard: TextInputType.phone),
                ]),
                const SizedBox(height: 16),
                const PropSectionHeader(
                    title: 'الموقع الجغرافي',
                    icon: Icons.my_location_rounded,
                    gradient: AppTheme.greenGradient),
                const SizedBox(height: 10),
                _panel([_locationRow()]),
                const SizedBox(height: 16),
                const PropSectionHeader(
                    title: 'التصنيف',
                    icon: Icons.category_rounded,
                    gradient: AppTheme.orangeGradient),
                const SizedBox(height: 10),
                _panel([
                  _chipsLabel('نوع العقار'),
                  _choiceRow(kPropertyTypeLabels, _property,
                      (k) => setState(() => _property = k)),
                  const SizedBox(height: 12),
                  _chipsLabel('نوع الملكية'),
                  _choiceRow(kOwnershipLabels, _ownership,
                      (k) => setState(() => _ownership = k)),
                ]),
                const SizedBox(height: 16),
                const PropSectionHeader(
                    title: 'معلومات إضافية',
                    icon: Icons.notes_rounded,
                    gradient: AppTheme.blueGradient),
                const SizedBox(height: 10),
                _panel([
                  _text(_notes, 'ملاحظات',
                      icon: Icons.notes_rounded, maxLines: 3),
                ]),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Icon(editing
                          ? Icons.save_rounded
                          : Icons.check_circle_rounded),
                  label: Text(editing ? 'حفظ التعديلات' : 'إنشاء العقار',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: PropUi.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  Widget _dropdown() {
    return DropdownButtonFormField<int>(
      initialValue: _govCode,
      isExpanded: true,
      style: GoogleFonts.cairo(
          fontWeight: FontWeight.w600, color: PropUi.ink),
      decoration: InputDecoration(
        labelText: 'المحافظة',
        labelStyle: GoogleFonts.cairo(),
        prefixIcon:
            const Icon(Icons.location_on_rounded, color: AppTheme.primaryColor),
        isDense: true,
      ),
      items: [
        for (final g in _governorates)
          DropdownMenuItem(
              value: g.key, child: Text(g.value, style: GoogleFonts.cairo())),
      ],
      onChanged: (v) => setState(() => _govCode = v ?? _govCode),
    );
  }

  Future<void> _openLocationMaster() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LocationMasterPage()),
    );
    if (!mounted) return;
    // قد تتغيّر المناطق/العناوين بعد الإدارة → أعِد التحميل مع الإبقاء على الاختيار.
    final keepRegion = _regionId;
    final keepA2 = _address2Id;
    final keepA3 = _address3Id;
    await _loadRegions();
    if (!mounted || keepRegion == null) return;
    if (_regions.any((r) => r.id == keepRegion)) {
      setState(() => _regionId = keepRegion);
      await _loadAddress2(initial: keepA2);
      if (mounted && keepA2 != null && _address2Id == keepA2) {
        await _loadAddress3(initial: keepA3);
      }
    }
  }

  Widget _locErrorRow() {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 18, color: AppTheme.errorColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text('تعذّر تحميل المناطق — $_locError',
              style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.errorColor)),
        ),
        TextButton(
          onPressed: _loadRegions,
          child: Text('إعادة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _regionDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _regionId,
      isExpanded: true,
      style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: PropUi.ink),
      decoration: InputDecoration(
        labelText: 'المنطقة',
        labelStyle: GoogleFonts.cairo(),
        prefixIcon: _loadingRegions
            ? const _MiniSpinner()
            : const Icon(Icons.location_on_outlined,
                color: AppTheme.primaryColor),
        isDense: true,
      ),
      items: [
        DropdownMenuItem(
            value: null,
            child: Text('— بلا منطقة —',
                style: GoogleFonts.cairo(color: Colors.grey[600]))),
        for (final r in _regions)
          DropdownMenuItem(
              value: r.id, child: Text(r.name, style: GoogleFonts.cairo())),
      ],
      onChanged: _loadingRegions
          ? null
          : (v) {
              setState(() => _regionId = v);
              if (v == null) {
                setState(() {
                  _address2Options = const [];
                  _address2Id = null;
                  _address3Options = const [];
                  _address3Id = null;
                });
                _refreshTotalFee();
              } else {
                _loadAddress2();
                _refreshTotalFee();
              }
            },
    );
  }

  Widget _address2Dropdown() {
    final enabled = _regionId != null && !_loadingA2;
    return DropdownButtonFormField<String?>(
      initialValue: _address2Id,
      isExpanded: true,
      style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: PropUi.ink),
      decoration: InputDecoration(
        labelText: 'العنوان 2',
        labelStyle: GoogleFonts.cairo(),
        prefixIcon: _loadingA2
            ? const _MiniSpinner()
            : const Icon(Icons.signpost_rounded, color: AppTheme.primaryColor),
        isDense: true,
      ),
      items: [
        DropdownMenuItem(
            value: null,
            child: Text('— بلا عنوان 2 —',
                style: GoogleFonts.cairo(color: Colors.grey[600]))),
        for (final a in _address2Options)
          DropdownMenuItem(
              value: a.id, child: Text(a.name, style: GoogleFonts.cairo())),
      ],
      onChanged: enabled
          ? (v) {
              setState(() => _address2Id = v);
              if (v == null) {
                setState(() {
                  _address3Options = const [];
                  _address3Id = null;
                });
                _refreshTotalFee();
              } else {
                _loadAddress3();
                _refreshTotalFee();
              }
            }
          : null,
    );
  }

  Widget _address3Dropdown() {
    final enabled = _address2Id != null && !_loadingA3;
    return DropdownButtonFormField<String?>(
      initialValue: _address3Id,
      isExpanded: true,
      style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: PropUi.ink),
      decoration: InputDecoration(
        labelText: 'العنوان 3',
        labelStyle: GoogleFonts.cairo(),
        prefixIcon: _loadingA3
            ? const _MiniSpinner()
            : const Icon(Icons.add_road_rounded, color: AppTheme.primaryColor),
        isDense: true,
      ),
      items: [
        DropdownMenuItem(
            value: null,
            child: Text('— بلا عنوان 3 —',
                style: GoogleFonts.cairo(color: Colors.grey[600]))),
        for (final a in _address3Options)
          DropdownMenuItem(
              value: a.id, child: Text(a.name, style: GoogleFonts.cairo())),
      ],
      onChanged: enabled
          ? (v) {
              setState(() => _address3Id = v);
              _refreshTotalFee();
            }
          : null,
    );
  }

  /// بطاقة ملخّص «أجر الصيانة الإجمالي» (تراكمي: منطقة + عنوان2 + عنوان3).
  /// مشتقّة للعرض فقط — لا تُحفظ على العقار.
  Widget _feeSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.warningColor.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_rounded,
              color: AppTheme.warningColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('أجر الصيانة الإجمالي',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: PropUi.ink)),
                Text('تراكمي: منطقة + عنوان 2 + عنوان 3',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_loadingFee)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.warningColor),
            )
          else
            Text('${_fmtFee(_totalFee ?? 0)} د.ع',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: AppTheme.warningColor)),
        ],
      ),
    );
  }

  Widget _locationRow() {
    final hasLoc = _lat != null && _lon != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(hasLoc ? Icons.place_rounded : Icons.location_off_rounded,
                color: hasLoc ? AppTheme.successColor : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasLoc
                    ? '${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}'
                    : 'لم يُحدَّد الموقع بعد',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700,
                    color: hasLoc ? PropUi.ink : Colors.grey[600]),
              ),
            ),
            FilledButton.icon(
              onPressed: _locating ? null : _useMyLocation,
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.successColor),
              icon: _locating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text('موقعي',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        if (hasLoc)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() {
                _lat = null;
                _lon = null;
              }),
              icon: const Icon(Icons.clear_rounded,
                  size: 16, color: AppTheme.errorColor),
              label: Text('مسح الموقع',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700, color: AppTheme.errorColor)),
            ),
          ),
      ],
    );
  }

  Widget _chipsLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.grey[700])),
      );

  Widget _choiceRow(
      Map<String, String> options, String value, ValueChanged<String> onSet) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final e in options.entries)
          ChoiceChip(
            label: Text(e.value,
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: value == e.key
                        ? Colors.white
                        : const Color(0xFF475569))),
            selected: value == e.key,
            showCheckmark: false,
            backgroundColor: Colors.white,
            selectedColor: AppTheme.primaryColor,
            side: BorderSide(
                color: value == e.key
                    ? AppTheme.primaryColor
                    : Colors.grey.withValues(alpha: 0.25)),
            onSelected: (_) => onSet(e.key),
          ),
      ],
    );
  }

  Widget _text(
    TextEditingController c,
    String label, {
    int maxLines = 1,
    TextInputType? keyboard,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.cairo(),
          prefixIcon: icon == null
              ? null
              : Icon(icon, color: AppTheme.primaryColor, size: 20),
          isDense: true,
        ),
      ),
    );
  }
}

/// مؤشّر تحميل صغير يحل محل أيقونة prefix في القوائم المنسدلة أثناء الجلب.
class _MiniSpinner extends StatelessWidget {
  const _MiniSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppTheme.primaryColor),
      ),
    );
  }
}
