import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../api/staff_api.dart';
import '../theme/tokens.dart';
import '../widgets/banner.dart';
import '../widgets/common.dart';

/// شاشة الترخيص والصلاحيات — تعرض استجابة نظام SAS `auth` (GET auth):
/// حالة الترخيص، تاريخ الانتهاء، الميزات المفعّلة، والصلاحيات.
class SasLicenseScreen extends StatefulWidget {
  final StaffApi api;
  final int companyId;
  const SasLicenseScreen({super.key, required this.api, required this.companyId});

  @override
  State<SasLicenseScreen> createState() => _SasLicenseScreenState();
}

class _SasLicenseScreenState extends State<SasLicenseScreen> {
  Map<String, dynamic>? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await widget.api.sasAuthInfo(widget.companyId);
      final data = (r is Map<String, dynamic>)
          ? ((r['data'] is Map) ? r['data'] as Map<String, dynamic> : r)
          : <String, dynamic>{};
      if (mounted) setState(() => _info = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الترخيص والصلاحيات'),
          actions: [
            IconButton(
              onPressed: _load,
              icon: const Icon(PhosphorIconsBold.arrowsClockwise),
            ),
          ],
        ),
        body: _error != null
            ? Center(child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: PBanner.error('تعذّر جلب بيانات الترخيص: $_error'),
              ))
            : _info == null
                ? const LoadingView()
                : ListView(
                    padding: const EdgeInsets.all(Space.lg),
                    children: [
                      _kvCard(pal, t, 'الترخيص', PhosphorIconsDuotone.certificate, {
                        'الحالة': _info!['license_status'] ?? _info!['status'],
                        'تاريخ الانتهاء': _info!['license_expiration'] ?? _info!['expiration'],
                        'الإصدار': _info!['version'],
                      }),
                      const SizedBox(height: Space.md),
                      _listCard(pal, t, 'الميزات المفعّلة',
                          PhosphorIconsDuotone.sparkle, _info!['features']),
                      const SizedBox(height: Space.md),
                      _listCard(pal, t, 'الصلاحيات',
                          PhosphorIconsDuotone.shieldCheck, _info!['permissions']),
                    ],
                  ),
      ),
    );
  }

  Widget _kvCard(PlatformPalette pal, TextTheme t, String title, IconData icon,
      Map<String, dynamic> kv) {
    final entries = kv.entries
        .where((e) => e.value != null && '${e.value}'.trim().isNotEmpty)
        .toList();
    return _card(pal, t, title, icon, [
      if (entries.isEmpty)
        Text('لا بيانات', style: t.bodySmall?.copyWith(color: pal.textMuted))
      else
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 140,
                  child: Text(e.key, style: t.bodySmall?.copyWith(color: pal.textMuted))),
              Expanded(child: Text('${e.value}',
                  style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
            ]),
          ),
    ]);
  }

  Widget _listCard(PlatformPalette pal, TextTheme t, String title, IconData icon,
      dynamic value) {
    final items = <String>[];
    if (value is List) {
      items.addAll(value.map((e) => '$e'));
    } else if (value is Map) {
      value.forEach((k, v) {
        if (v == true || v == 1) items.add('$k');
      });
    }
    return _card(pal, t, title, icon, [
      if (items.isEmpty)
        Text('لا بيانات', style: t.bodySmall?.copyWith(color: pal.textMuted))
      else
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final it in items)
              Chip(
                label: Text(it, style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
    ]);
  }

  Widget _card(PlatformPalette pal, TextTheme t, String title, IconData icon,
      List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: pal.surfaceCard,
        borderRadius: Radii.rLg,
        border: Border.all(color: pal.outline),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: pal.accent),
            const SizedBox(width: Space.xs),
            Text(title,
                style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: Space.sm),
          ...children,
        ],
      ),
    );
  }
}
