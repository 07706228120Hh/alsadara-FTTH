/// نموذج إنشاء/تعديل عقار — المحافظة + المنطقة + النقطة الدالة + الموقع (GPS) +
/// النوع + الملكية + ملاحظات. بثيم الصدارة، RTL، ينادي بوّابة `/api/properties`.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/property.dart';
import '../../services/property_api_service.dart';
import '../../theme/app_theme.dart';
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
  late final _area =
      TextEditingController(text: widget.existing?.area ?? '');
  late final _address2 =
      TextEditingController(text: widget.existing?.address2 ?? '');
  late final _address3 =
      TextEditingController(text: widget.existing?.address3 ?? '');
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
  }

  @override
  void dispose() {
    for (final c in [
      _area,
      _address2,
      _address3,
      _ownerName,
      _ownerPhone,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
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
      if (widget.existing == null) {
        await _api.create(
          govCode: _govCode,
          governorate: _govName,
          area: _area.text.trim(),
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
          address2: _address2.text.trim(),
          address3: _address3.text.trim(),
        );
      } else {
        await _api.update(widget.existing!.id, {
          'govCode': _govCode,
          'governorate': _govName,
          'area': _area.text.trim(),
          'latitude': _lat,
          'longitude': _lon,
          'propertyType': _property,
          'ownership': _ownership,
          'notes': _notes.text.trim(),
          'ownerName': _ownerName.text.trim(),
          'ownerPhone': _ownerPhone.text.trim(),
          'address2': _address2.text.trim(),
          'address3': _address3.text.trim(),
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
                const PropSectionHeader(
                    title: 'العنوان الوصفي',
                    icon: Icons.location_city_rounded,
                    gradient: AppTheme.blueGradient),
                const SizedBox(height: 10),
                _panel([
                  _dropdown(),
                  const SizedBox(height: 12),
                  _text(_area, 'المنطقة',
                      icon: Icons.location_on_outlined, requiredField: true),
                  _text(_address2, 'العنوان 2',
                      icon: Icons.signpost_rounded),
                  _text(_address3, 'العنوان 3',
                      icon: Icons.add_road_rounded),
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
    bool requiredField = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        validator: requiredField
            ? (v) => (v == null || v.trim().isEmpty) ? 'حقل مطلوب' : null
            : null,
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
