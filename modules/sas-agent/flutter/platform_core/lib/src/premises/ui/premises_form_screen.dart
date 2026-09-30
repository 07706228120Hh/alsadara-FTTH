/// نموذج إضافة/تعديل عقار — العنوان الوصفي + الموقع (GPS) + النوع + الهاتف.
library;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../api/premises_api.dart';
import '../models/premises.dart';

/// محافظات العراق (تطابق جدول كود المحافظة في محرّك العنونة بالباكند).
const _governorates = [
  'بغداد', 'البصرة', 'نينوى', 'أربيل', 'السليمانية', 'دهوك', 'كركوك', 'الأنبار',
  'ديالى', 'صلاح الدين', 'بابل', 'واسط', 'النجف', 'كربلاء', 'القادسية', 'ميسان',
  'ذي قار', 'المثنى', 'حلبجة',
];

class PremisesFormScreen extends StatefulWidget {
  final PremisesApi api;
  final Premises? existing;
  const PremisesFormScreen({super.key, required this.api, this.existing});
  @override
  State<PremisesFormScreen> createState() => _PremisesFormScreenState();
}

class _PremisesFormScreenState extends State<PremisesFormScreen> {
  final _form = GlobalKey<FormState>();
  late String _gov = widget.existing?.governorate ?? _governorates.first;
  late final _district = TextEditingController(text: widget.existing?.district ?? '');
  late final _landmark = TextEditingController(text: widget.existing?.landmark ?? '');
  late final _details = TextEditingController(text: widget.existing?.addressDetails ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _owner = TextEditingController(text: widget.existing?.ownerName ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String _ownership = widget.existing?.ownership ?? 'owned';
  late String _property = widget.existing?.propertyType ?? 'residential';
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
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _msg('لم يُسمح بالوصول إلى الموقع', err: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() { _lat = pos.latitude; _lon = pos.longitude; });
      _msg('حُدِّد الموقع: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
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
        await widget.api.create(body);
      } else {
        await widget.api.update(widget.existing!.id, body);
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
      SnackBar(content: Text(m), backgroundColor: err ? Colors.red : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(editing ? 'تعديل عقار' : 'عقار جديد')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                initialValue: _gov,
                decoration: const InputDecoration(labelText: 'المحافظة', border: OutlineInputBorder()),
                items: [for (final g in _governorates) DropdownMenuItem(value: g, child: Text(g))],
                onChanged: (v) => setState(() => _gov = v ?? _gov),
              ),
              const SizedBox(height: 12),
              _text(_district, 'المنطقة / الحي'),
              _text(_landmark, 'أقرب نقطة دالة'),
              _text(_details, 'تفاصيل العنوان (زقاق/دار)', maxLines: 2),
              const SizedBox(height: 8),

              // الموقع الجغرافي
              _sectionTitle('الموقع الجغرافي (لتوليد رمز الموقع IQ-Pin)'),
              Row(children: [
                Expanded(
                  child: Text(
                    _lat != null && _lon != null
                        ? '${_lat!.toStringAsFixed(5)}, ${_lon!.toStringAsFixed(5)}'
                        : 'لم يُحدَّد بعد',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location),
                  label: const Text('موقعي الحالي'),
                ),
              ]),
              if (_lat != null || _lon != null)
                TextButton.icon(
                  onPressed: () => setState(() { _lat = null; _lon = null; }),
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('مسح الموقع'),
                ),
              const SizedBox(height: 8),

              // النوع
              _sectionTitle('نوع السكن'),
              Wrap(spacing: 8, children: [
                for (final e in kOwnershipLabels.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _ownership == e.key,
                    onSelected: (_) => setState(() => _ownership = e.key),
                  ),
              ]),
              const SizedBox(height: 8),
              _sectionTitle('نوع العقار'),
              Wrap(spacing: 8, children: [
                for (final e in kPropertyLabels.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _property == e.key,
                    onSelected: (_) => setState(() => _property = e.key),
                  ),
              ]),
              const SizedBox(height: 12),

              _text(_phone, 'رقم الهاتف', keyboard: TextInputType.phone),
              _text(_owner, 'اسم المالك/المستأجر'),
              _text(_notes, 'ملاحظات', maxLines: 2),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(editing ? 'حفظ التعديلات' : 'إنشاء العقار'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(TextEditingController c, String label,
      {int maxLines = 1, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboard,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}
