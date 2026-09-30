/// تفاصيل العقار — QR + العنوان الوطني + صورة الدار + الاشتراكات المرتبطة.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/premises_api.dart';
import '../models/premises.dart';
import '../print/premises_label.dart';
import 'premises_form_screen.dart';

class PremisesDetailScreen extends StatefulWidget {
  final PremisesApi api;
  final int premisesId;
  const PremisesDetailScreen({super.key, required this.api, required this.premisesId});
  @override
  State<PremisesDetailScreen> createState() => _PremisesDetailScreenState();
}

class _PremisesDetailScreenState extends State<PremisesDetailScreen> {
  Premises? _p;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = await widget.api.get(widget.premisesId);
      if (mounted) setState(() { _p = p; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _msg(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: err ? Colors.red : null));
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PremisesFormScreen(api: widget.api, existing: _p)));
    if (saved == true) _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف العقار؟'),
        content: const Text('سيُحذف العقار وصورته ويُفكّ ربط اشتراكاته (لا تُحذف الاشتراكات).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete(widget.premisesId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _msg('تعذّر الحذف: $e', err: true);
    }
  }

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('كاميرا'),
              onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('من الملفات'),
              onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (src == null) return;
    try {
      final XFile? x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 82);
      if (x == null) return;
      await widget.api.uploadPhoto(widget.premisesId, x.path);
      _msg('حُفظت صورة الدار');
      _load();
    } catch (e) {
      _msg('تعذّر رفع الصورة: $e', err: true);
    }
  }

  Future<void> _openMap() async {
    final p = _p;
    if (p?.lat == null || p?.lon == null) return;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=${p!.lat},${p.lon}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _linkDialog() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: _LinkSheet(api: widget.api, premisesId: widget.premisesId),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _unlink(int subId) async {
    try {
      await widget.api.unlink(widget.premisesId, [subId]);
      _load();
    } catch (e) {
      _msg('تعذّر فكّ الربط: $e', err: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل العقار'),
          actions: [
            IconButton(onPressed: _edit, icon: const Icon(Icons.edit), tooltip: 'تعديل'),
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: 'حذف'),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                : _body(_p!),
      ),
    );
  }

  Widget _body(Premises p) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _qrCard(p),
        _photoCard(p),
        _detailsCard(p),
        _subscribersCard(p),
      ],
    );
  }

  Widget _qrCard(Premises p) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            if (p.qrPayload.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.white,
                child: QrImageView(data: p.qrPayload, size: 190, version: QrVersions.auto),
              ),
            const SizedBox(height: 10),
            SelectableText(p.npnDisplay,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: 1)),
            if (p.iqpinDisplay.isNotEmpty)
              Text('IQ-Pin: ${p.iqpinDisplay}',
                  style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => printPremisesLabel(p),
              icon: const Icon(Icons.print),
              label: const Text('طباعة اللصاقة'),
            ),
          ]),
        ),
      );

  Widget _photoCard(Premises p) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.home_outlined),
              const SizedBox(width: 8),
              const Expanded(child: Text('صورة الدار', style: TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.add_a_photo, size: 18),
                label: Text(p.hasPhoto ? 'تغيير' : 'إضافة'),
              ),
            ]),
            const SizedBox(height: 8),
            if (p.hasPhoto)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  widget.api.photoUrl(p.id),
                  headers: widget.api.authHeaders,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _photoPlaceholder(),
                ),
              )
            else
              _photoPlaceholder(),
          ]),
        ),
      );

  Widget _photoPlaceholder() => Container(
        height: 140,
        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
        child: const Center(child: Icon(Icons.image_outlined, size: 40, color: Colors.grey)),
      );

  Widget _detailsCard(Premises p) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 6, children: [
              _chip(propertyLabel(p.propertyType), Colors.indigo),
              _chip(ownershipLabel(p.ownership), Colors.teal),
              _chip('${p.subscriberCount} اشتراك', Colors.blueGrey),
            ]),
            const Divider(height: 20),
            _kv('المحافظة', p.governorate),
            _kv('المنطقة', p.district),
            _kv('أقرب نقطة', p.landmark),
            _kv('التفاصيل', p.addressDetails),
            _kv('الهاتف', p.phone),
            _kv('المالك/المستأجر', p.ownerName),
            if (p.notes.trim().isNotEmpty) _kv('ملاحظات', p.notes),
            if (p.lat != null && p.lon != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openMap,
                icon: const Icon(Icons.map_outlined),
                label: Text('الموقع: ${p.lat!.toStringAsFixed(5)}, ${p.lon!.toStringAsFixed(5)}'),
              ),
            ],
          ]),
        ),
      );

  Widget _subscribersCard(Premises p) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.people_outline),
              const SizedBox(width: 8),
              Expanded(child: Text('الاشتراكات (${p.subscriberCount})',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton.icon(
                onPressed: _linkDialog,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('ربط اشتراك'),
              ),
            ]),
            const SizedBox(height: 6),
            if (p.subscribers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا اشتراكات مرتبطة بعد — اربط اشتراكاً واحداً أو أكثر بهذا العقار.'),
              )
            else
              for (final s in p.subscribers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(s.username, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([s.name, s.profile].where((x) => x.trim().isNotEmpty).join(' · ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.link_off, size: 20),
                    tooltip: 'فكّ الربط',
                    onPressed: () => _unlink(s.id),
                  ),
                ),
          ]),
        ),
      );

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
      );

  Widget _kv(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 110, child: Text(k, style: TextStyle(color: Colors.grey[600]))),
        Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// ورقة بحث وربط الاشتراكات بالعقار.
class _LinkSheet extends StatefulWidget {
  final PremisesApi api;
  final int premisesId;
  const _LinkSheet({required this.api, required this.premisesId});
  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.linkCandidates(q: _q.text.trim());
      if (mounted) setState(() { _rows = r; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _link(int subId) async {
    try {
      await widget.api.link(widget.premisesId, [subId]);
      _changed = true;
      _search();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمّ الربط')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر الربط: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          const Expanded(child: Text('ربط اشتراك بالعقار',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          IconButton(onPressed: () => Navigator.pop(context, _changed), icon: const Icon(Icons.close)),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: _q,
          decoration: InputDecoration(
            hintText: 'ابحث باسم المستخدم/الاسم/الهاتف',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
          ),
          onSubmitted: (_) => _search(),
        ),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _rows[i];
                  final linkedHere = r['premises_id'] == widget.premisesId;
                  final linkedElse = r['premises_id'] != null && !linkedHere;
                  return ListTile(
                    title: Text('${r['username']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([r['name'], r['phone']]
                        .where((x) => (x ?? '').toString().trim().isNotEmpty).join(' · ')),
                    trailing: linkedHere
                        ? const Chip(label: Text('مربوط هنا'))
                        : FilledButton(
                            onPressed: () => _link(r['id'] as int),
                            child: Text(linkedElse ? 'نقل هنا' : 'ربط'),
                          ),
                  );
                },
              ),
      ),
    ]);
  }
}
