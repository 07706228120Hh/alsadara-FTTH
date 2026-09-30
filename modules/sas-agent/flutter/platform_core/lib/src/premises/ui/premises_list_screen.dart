/// قائمة العقارات — بحث + تصفية بالنوع/الملكية + إضافة + فتح التفاصيل.
library;

import 'package:flutter/material.dart';

import '../api/premises_api.dart';
import '../models/premises.dart';
import 'premises_detail_screen.dart';
import 'premises_form_screen.dart';

class PremisesListScreen extends StatefulWidget {
  final PremisesApi api;
  const PremisesListScreen({super.key, required this.api});
  @override
  State<PremisesListScreen> createState() => _PremisesListScreenState();
}

class _PremisesListScreenState extends State<PremisesListScreen> {
  final _q = TextEditingController();
  List<Premises> _rows = [];
  bool _loading = true;
  String? _error;
  String? _propertyFilter;
  String? _ownershipFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final r = await widget.api.list(
        q: _q.text.trim().isEmpty ? null : _q.text.trim(),
        propertyType: _propertyFilter,
        ownership: _ownershipFilter,
        count: 200,
      );
      if (mounted) setState(() { _rows = r; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PremisesFormScreen(api: widget.api)));
    if (saved == true) _load();
  }

  Future<void> _open(Premises p) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PremisesDetailScreen(api: widget.api, premisesId: p.id)));
    if (changed == true || changed == null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('العقارات'),
          actions: [
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_home_work),
          label: const Text('عقار جديد'),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                hintText: 'بحث: رقم وطني / هاتف / مالك / عنوان',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _load),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [
              _filterChip('الكل', _propertyFilter == null && _ownershipFilter == null,
                  () => setState(() { _propertyFilter = null; _ownershipFilter = null; _load(); })),
              for (final e in kPropertyLabels.entries)
                _filterChip(e.value, _propertyFilter == e.key,
                    () => setState(() { _propertyFilter = e.key; _load(); })),
              for (final e in kOwnershipLabels.entries)
                _filterChip(e.value, _ownershipFilter == e.key,
                    () => setState(() { _ownershipFilter = e.key; _load(); })),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
                    : _rows.isEmpty
                        ? const Center(child: Text('لا عقارات بعد — أضف عقاراً بالزرّ أدناه'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, i) => _card(_rows[i]),
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );

  Widget _card(Premises p) => Card(
        child: ListTile(
          onTap: () => _open(p),
          leading: CircleAvatar(
            backgroundColor: Colors.indigo.withValues(alpha: 0.12),
            child: Icon(
              p.propertyType == 'commercial' ? Icons.storefront : Icons.home,
              color: Colors.indigo,
            ),
          ),
          title: Text(p.npnDisplay.isEmpty ? 'عقار #${p.id}' : p.npnDisplay,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.shortAddress.isNotEmpty) Text(p.shortAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text([
              propertyLabel(p.propertyType),
              ownershipLabel(p.ownership),
              '${p.subscriberCount} اشتراك',
              if (p.phone.trim().isNotEmpty) p.phone,
            ].join(' · '), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ]),
          trailing: const Icon(Icons.chevron_left),
        ),
      );
}
