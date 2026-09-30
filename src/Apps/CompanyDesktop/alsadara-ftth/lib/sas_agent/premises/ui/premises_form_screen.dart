/// نموذج إضافة/تعديل عقار — العنوان الوصفي + الموقع (GPS لتوليد IQ-Pin) +
/// النوع/الملكية + الهاتف والمالك والملاحظات. بثيم منصّة الصدارة.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';
import '../../services/sas_agent_api_service.dart';
import '../../widgets/sas_state_views.dart';
import '../models/premises.dart';

/// محافظات العراق (تطابق جدول كود المحافظة في محرّك العنونة بالباكند).
const _governorates = [
  'بغداد', 'البصرة', 'نينوى', 'أربيل', 'السليمانية', 'دهوك', 'كركوك',
  'الأنبار', 'ديالى', 'صلاح الدين', 'بابل', 'واسط', 'النجف', 'كربلاء',
  'القادسية', 'ميسان', 'ذي قار', 'المثنى', 'حلبجة',
];

class PremisesFormScreen extends StatefulWidget {
  final Premises? existing;
  const PremisesFormScreen({super.key, this.existing});

  @override
  State<PremisesFormScreen> createState() => _PremisesFormScreenState();
}

class _PremisesFormScreenState extends State<PremisesFormScreen> {
  final _api = SasAgentApiService.instance;
  final _form = GlobalKey<FormState>();

  late String _gov = widget.existing?.governorate.isNotEmpty == true
      ? widget.existing!.governorate
      : _governorates.first;
  late final _district =
      TextEditingController(text: widget.existing?.district ?? '');
  late final _landmark =
      TextEditingController(text: widget.existing?.landmark ?? '');
  late final _details =
      TextEditingController(text: widget.existing?.addressDetails ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _owner =
      TextEditingController(text: widget.existing?.ownerName ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String _ownership = widget.existing?.ownership.isNotEmpty == true
      ? widget.existing!.ownership
      : 'owned';
  late String _property = widget.existing?.propertyType.isNotEmpty == true
      ? widget.existing!.propertyType
      : 'residential';
  double? _lat;
  double? _lon;
  bool _locating = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lat = widget.existing?.lat;
    _lon = widget.existing?.lon;
  }

  @override
  void dispose() {
    for (final c in [_district, _landmark, _details, _phone, _owner, _notes]) {
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
    final body = <String, dynamic>{
      'governorate': _gov,
      'district': _district.text.trim(),
      'landmark': _landmark.text.trim(),
      'address_details': _details.text.trim(),
      'lat': _lat,
      'lon': _lon,
      'phone': _phone.text.trim(),
      'ownership': _ownership,
      'property_type': _property,
      'owner_name': _owner.text.trim(),
      'notes': _notes.text.trim(),
    };
    try {
      if (widget.existing == null) {
        await _api.createPremise(body);
      } else {
        await _api.updatePremise(widget.existing!.id, body);
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
        backgroundColor: SasUi.pageBg,
        appBar: _appBar(editing),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _section('العنوان الوصفي', Icons.location_city_rounded,
                  AppTheme.blueGradient),
              const SizedBox(height: 10),
              _panel([
                _dropdown(),
                const SizedBox(height: 12),
                _text(_district, 'المنطقة / الحي',
                    icon: Icons.map_rounded, requiredField: true),
                _text(_landmark, 'أقرب نقطة دالة',
                    icon: Icons.push_pin_rounded),
                _text(_details, 'تفاصيل العنوان (زقاق/دار)',
                    icon: Icons.signpost_rounded, maxLines: 2),
              ]),
              const SizedBox(height: 16),

              _section('الموقع الجغرافي (لتوليد رمز IQ-Pin)',
                  Icons.my_location_rounded, AppTheme.greenGradient),
              const SizedBox(height: 10),
              _panel([_locationRow()]),
              const SizedBox(height: 16),

              _section('التصنيف', Icons.category_rounded,
                  AppTheme.orangeGradient),
              const SizedBox(height: 10),
              _panel([
                _chipsLabel('نوع الملكية'),
                _choiceRow(kOwnershipLabels, _ownership,
                    (k) => setState(() => _ownership = k)),
                const SizedBox(height: 12),
                _chipsLabel('نوع العقار'),
                _choiceRow(kPropertyLabels, _property,
                    (k) => setState(() => _property = k)),
              ]),
              const SizedBox(height: 16),

              _section('معلومات إضافية', Icons.contacts_rounded,
                  AppTheme.blueGradient),
              const SizedBox(height: 10),
              _panel([
                _text(_phone, 'رقم الهاتف',
                    icon: Icons.phone_rounded,
                    keyboard: TextInputType.phone),
                _text(_owner, 'اسم المالك/المستأجر',
                    icon: Icons.person_rounded),
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
    );
  }

  PreferredSizeWidget _appBar(bool editing) {
    return AppBar(
      elevation: 0,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: AppTheme.blueGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Text(editing ? 'تعديل عقار' : 'عقار جديد',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 17)),
    );
  }

  Widget _section(String title, IconData icon, List<Color> gradient) =>
      SasSectionHeader(title: title, icon: icon, gradient: gradient);

  Widget _panel(List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: SasUi.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  Widget _dropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _gov,
      isExpanded: true,
      style: GoogleFonts.cairo(
          fontWeight: FontWeight.w600, color: const Color(0xFF1A1A2E)),
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
              value: g, child: Text(g, style: GoogleFonts.cairo())),
      ],
      onChanged: (v) => setState(() => _gov = v ?? _gov),
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
                    color: hasLoc ? const Color(0xFF1A1A2E) : Colors.grey[600]),
              ),
            ),
            FilledButton.icon(
              onPressed: _locating ? null : _useMyLocation,
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.successColor),
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
                      fontWeight: FontWeight.w700,
                      color: AppTheme.errorColor)),
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
