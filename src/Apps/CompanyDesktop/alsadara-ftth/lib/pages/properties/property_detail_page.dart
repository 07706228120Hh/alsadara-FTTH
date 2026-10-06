/// تفاصيل العقار — QR مكبّر (العنوان الوطني) + NPN/IqPin + طباعة لصاقة +
/// المواطنون (ربط عبر منتقٍ) + الخدمات (إضافة/حذف) + فتح الموقع + تعديل/حذف.
///
/// نظام أساسي ينادي بوّابة الصدارة `/api/properties`. بثيم الصدارة، RTL.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/property.dart';
import '../../permissions/permission_manager.dart';
import '../../services/property_api_service.dart';
import '../../theme/app_theme.dart';
import 'property_form_page.dart';
import 'property_label.dart';
import 'property_ui.dart';

class PropertyDetailPage extends StatefulWidget {
  final String propertyId;
  const PropertyDetailPage({super.key, required this.propertyId});

  @override
  State<PropertyDetailPage> createState() => _PropertyDetailPageState();
}

class _PropertyDetailPageState extends State<PropertyDetailPage> {
  final _api = PropertyApiService.instance;

  PropertyDetails? _details;
  bool _loading = true;
  String? _error;

  // المهام المرتبطة بالعقار (نظام المهام).
  List<PropertyTaskHit> _tasks = const [];
  bool _tasksLoading = false;
  String? _tasksError;

  bool get _canManage =>
      PermissionManager.instance.canAdd('property_registry');
  bool get _canDelete =>
      PermissionManager.instance.canDelete('property_registry');

  Property? get _p => _details?.property;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.getById(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _details = d;
        _loading = false;
      });
      _loadTasks();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
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

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PropertyFormPage(existing: _p)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('حذف العقار؟',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: Text(
            'سيُحذف العقار ويُفكّ ربط مواطنيه وخدماته (لا يُحذف المواطنون من النظام).',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('إلغاء',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
              child: Text('حذف',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete(widget.propertyId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _msg('تعذّر الحذف: $e', err: true);
    }
  }

  Future<void> _openMap() async {
    final p = _p;
    if (p?.latitude == null || p?.longitude == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${p!.latitude},${p.longitude}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _msg('تعذّر فتح الخرائط', err: true);
    }
  }

  // ─────────────────────────── المواطنون ───────────────────────────

  Future<void> _linkCitizen() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: FractionallySizedBox(
          heightFactor: 0.88,
          child: _CitizenPickerSheet(propertyId: widget.propertyId),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _unlinkCitizen(PropertyResident r) async {
    try {
      await _api.removeResident(widget.propertyId, r.id);
      _load();
    } catch (e) {
      _msg('تعذّر فكّ الربط: $e', err: true);
    }
  }

  // ─────────────────────────── الخدمات ───────────────────────────

  Future<void> _addService() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: FractionallySizedBox(
          heightFactor: 0.9,
          child: _ServiceFormSheet(propertyId: widget.propertyId),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _deleteService(PropertyService s) async {
    try {
      await _api.deleteService(widget.propertyId, s.id);
      _load();
    } catch (e) {
      _msg('تعذّر حذف الخدمة: $e', err: true);
    }
  }

  // ─────────────────────────── المهام المرتبطة ───────────────────────────

  Future<void> _loadTasks() async {
    setState(() {
      _tasksLoading = true;
      _tasksError = null;
    });
    try {
      final t = await _api.getTasks(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _tasks = t;
        _tasksLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tasksError = '$e';
        _tasksLoading = false;
      });
    }
  }

  Future<void> _createTask() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: _TaskFormSheet(propertyId: widget.propertyId),
        ),
      ),
    );
    if (created == true) _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PropUi.pageBg,
        appBar: PropUi.appBar(
          'تفاصيل العقار',
          leadingIcon: Icons.home_work_rounded,
          actions: [
            if (_canManage && _p != null)
              IconButton(
                tooltip: 'تعديل',
                onPressed: _edit,
                icon: const Icon(Icons.edit_rounded, color: Colors.white),
              ),
            if (_canDelete && _p != null)
              IconButton(
                tooltip: 'حذف',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Colors.white),
              ),
            const SizedBox(width: 4),
          ],
        ),
        body: _loading
            ? const PropLoadingView(message: 'جارٍ تحميل العقار…')
            : _error != null
                ? PropErrorView(message: _error!, onRetry: _load)
                : _body(_details!),
      ),
    );
  }

  Widget _body(PropertyDetails d) {
    final p = d.property;
    return PropContentWrap(
      maxWidth: 960,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _qrCard(p),
          const SizedBox(height: 12),
          _detailsCard(p),
          const SizedBox(height: 12),
          _residentsCard(d.residents),
          const SizedBox(height: 12),
          _servicesCard(d.services),
          const SizedBox(height: 12),
          _tasksCard(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _qrCard(Property p) {
    final payload = p.qrPayload.isNotEmpty
        ? p.qrPayload
        : (p.qrToken.isNotEmpty ? 'SADARA|P:${p.qrToken}' : '');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: PropUi.card(),
      child: Column(
        children: [
          Text('العنوان الوطني',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Colors.grey[700])),
          const SizedBox(height: 12),
          if (payload.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.15),
                    width: 1.5),
                boxShadow: PropUi.cardShadow(),
              ),
              child: QrImageView(
                data: payload,
                size: 210,
                version: QrVersions.auto,
                eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: AppTheme.primaryColor),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: PropUi.ink),
              ),
            ),
          const SizedBox(height: 14),
          SelectableText(
            p.displayTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                letterSpacing: 1,
                color: PropUi.ink),
          ),
          if (p.iqPinDisplay.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SelectableText('IQ-Pin: ${p.iqPinDisplay}',
                  style: GoogleFonts.cairo(
                      color: Colors.grey[700], fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => printPropertyLabel(p),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              side: BorderSide(
                  color: AppTheme.primaryColor.withValues(alpha: 0.4)),
            ),
            icon: const Icon(Icons.print_rounded),
            label: Text('طباعة اللصاقة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _detailsCard(Property p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PropUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              PropBadge(
                  label: p.propertyTypeLabel,
                  color: p.isCommercial
                      ? AppTheme.warningColor
                      : AppTheme.primaryColor,
                  icon: p.isCommercial
                      ? Icons.storefront_rounded
                      : Icons.home_rounded),
              PropBadge(
                  label: p.ownershipLabel,
                  color: AppTheme.successColor,
                  icon: Icons.vpn_key_rounded),
              PropBadge(
                  label: '${p.serviceCount} خدمة',
                  color: AppTheme.secondaryColor,
                  icon: Icons.electrical_services_rounded),
            ],
          ),
          const Divider(height: 24),
          _kv('المحافظة', p.governorate),
          _kv('المنطقة', p.area),
          _kv('الحيّ', p.district),
          _kv('أقرب نقطة', p.landmark),
          _kv('التفاصيل', p.addressDetails),
          if (p.notes.trim().isNotEmpty) _kv('ملاحظات', p.notes),
          if (p.latitude != null && p.longitude != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _openMap,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.successColor,
                side: BorderSide(
                    color: AppTheme.successColor.withValues(alpha: 0.4)),
              ),
              icon: const Icon(Icons.map_rounded),
              label: Text(
                  'الموقع: ${p.latitude!.toStringAsFixed(5)}, ${p.longitude!.toStringAsFixed(5)}',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _residentsCard(List<PropertyResident> residents) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PropUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PropSectionHeader(
            title: 'المواطنون',
            icon: Icons.groups_rounded,
            trailingText: '${residents.length}',
            action: _canManage
                ? TextButton.icon(
                    onPressed: _linkCitizen,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text('ربط مواطن',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          if (residents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'لا مواطنون مربوطون بعد — اربط مالكاً أو مستأجراً أو ساكناً.',
                style: GoogleFonts.cairo(
                    color: Colors.grey[600], fontWeight: FontWeight.w600),
              ),
            )
          else
            for (int i = 0; i < residents.length; i++) ...[
              if (i > 0) const Divider(height: 14),
              _residentRow(residents[i]),
            ],
        ],
      ),
    );
  }

  Widget _residentRow(PropertyResident r) {
    return Row(
      children: [
        PropUi.gradientBadge(
          icon: Icons.person_rounded,
          colors: r.isPrimary
              ? AppTheme.greenGradient
              : AppTheme.blueGradient,
          size: 36,
          iconSize: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(r.name.isEmpty ? 'مواطن' : r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w800, color: PropUi.ink)),
                  ),
                  if (r.isPrimary) ...[
                    const SizedBox(width: 6),
                    const PropBadge(
                        label: 'أساسي',
                        color: AppTheme.successColor,
                        icon: Icons.star_rounded),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                [r.relationshipLabel, r.phone]
                    .where((x) => x.trim().isNotEmpty)
                    .join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    GoogleFonts.cairo(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        if (_canManage)
          IconButton(
            tooltip: 'فكّ الربط',
            onPressed: () => _unlinkCitizen(r),
            icon: const Icon(Icons.person_remove_rounded,
                size: 20, color: AppTheme.errorColor),
          ),
      ],
    );
  }

  Widget _servicesCard(List<PropertyService> services) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PropUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PropSectionHeader(
            title: 'الخدمات',
            icon: Icons.electrical_services_rounded,
            gradient: AppTheme.orangeGradient,
            trailingText: '${services.length}',
            action: _canManage
                ? TextButton.icon(
                    onPressed: _addService,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('إضافة خدمة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          if (services.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'لا خدمات مرتبطة بعد — أضف خدمة (إنترنت/ماستر…) لهذا العقار.',
                style: GoogleFonts.cairo(
                    color: Colors.grey[600], fontWeight: FontWeight.w600),
              ),
            )
          else
            for (int i = 0; i < services.length; i++) ...[
              if (i > 0) const Divider(height: 14),
              _serviceRow(services[i]),
            ],
        ],
      ),
    );
  }

  Widget _serviceRow(PropertyService s) {
    final statusColor = switch (s.status.toLowerCase()) {
      'active' => AppTheme.successColor,
      'suspended' => AppTheme.warningColor,
      _ => Colors.grey,
    };
    return Row(
      children: [
        PropUi.gradientBadge(
          icon: switch (s.serviceType.toLowerCase()) {
            'internet' => Icons.wifi_rounded,
            'master' => Icons.cable_rounded,
            'iptv' => Icons.live_tv_rounded,
            _ => Icons.miscellaneous_services_rounded,
          },
          colors: AppTheme.blueGradient,
          size: 36,
          iconSize: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [s.serviceTypeLabel, s.providerTypeLabel]
                    .where((x) => x.trim().isNotEmpty && x != '—')
                    .join(' · '),
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w800, color: PropUi.ink),
              ),
              if ([s.subscriberRef, s.providerRefId]
                  .any((x) => x.trim().isNotEmpty))
                Text(
                  [s.subscriberRef, s.providerRefId]
                      .where((x) => x.trim().isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                      fontSize: 12, color: Colors.grey[600]),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        PropBadge(label: s.statusLabel, color: statusColor),
        if (_canManage)
          IconButton(
            tooltip: 'حذف الخدمة',
            onPressed: () => _deleteService(s),
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppTheme.errorColor),
          ),
      ],
    );
  }

  Widget _tasksCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: PropUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PropSectionHeader(
            title: 'المهام المرتبطة',
            icon: Icons.assignment_rounded,
            gradient: AppTheme.greenGradient,
            trailingText: '${_tasks.length}',
            action: _canManage
                ? TextButton.icon(
                    onPressed: _createTask,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('إنشاء مهمة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          if (_tasksLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: PropLoadingView(),
            )
          else if (_tasksError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('تعذّر تحميل المهام: $_tasksError',
                        style: GoogleFonts.cairo(
                            color: AppTheme.errorColor,
                            fontWeight: FontWeight.w600)),
                  ),
                  TextButton.icon(
                    onPressed: _loadTasks,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('إعادة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            )
          else if (_tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'لا مهام مرتبطة بعد — أنشئ مهمة (صيانة/تركيب…) لهذا العقار.',
                style: GoogleFonts.cairo(
                    color: Colors.grey[600], fontWeight: FontWeight.w600),
              ),
            )
          else
            for (int i = 0; i < _tasks.length; i++) ...[
              if (i > 0) const Divider(height: 14),
              _taskRow(_tasks[i]),
            ],
        ],
      ),
    );
  }

  Widget _taskRow(PropertyTaskHit t) {
    final statusColor = _taskStatusColor(t.status);
    final meta = [
      if (t.department.trim().isNotEmpty) t.department,
      if (t.technicianName.trim().isNotEmpty) t.technicianName,
      if (t.priority > 0) 'أولوية ${t.priority}',
      if (t.requestedAt.trim().isNotEmpty) _shortDate(t.requestedAt),
    ].join(' · ');
    return Row(
      children: [
        PropUi.gradientBadge(
          icon: Icons.assignment_turned_in_rounded,
          colors: AppTheme.greenGradient,
          size: 36,
          iconSize: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.requestNumber.isEmpty ? 'طلب #${t.id}' : t.requestNumber,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w800, color: PropUi.ink),
              ),
              if (meta.trim().isNotEmpty)
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      GoogleFonts.cairo(fontSize: 12, color: Colors.grey[600]),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        PropBadge(label: t.statusLabel, color: statusColor),
      ],
    );
  }

  Color _taskStatusColor(String status) => switch (status.toLowerCase()) {
        'completed' || 'approved' => AppTheme.successColor,
        'inprogress' || 'assigned' => AppTheme.primaryColor,
        'pending' || 'reviewing' || 'onhold' => AppTheme.warningColor,
        'cancelled' || 'rejected' => AppTheme.errorColor,
        _ => Colors.grey,
      };

  String _shortDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  Widget _kv(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: GoogleFonts.cairo(
                    color: Colors.grey[600], fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(v,
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700, color: PropUi.ink)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────── ورقة منتقي المواطن ───────────────────────

class _CitizenPickerSheet extends StatefulWidget {
  final String propertyId;
  const _CitizenPickerSheet({required this.propertyId});

  @override
  State<_CitizenPickerSheet> createState() => _CitizenPickerSheetState();
}

class _CitizenPickerSheetState extends State<_CitizenPickerSheet> {
  final _api = PropertyApiService.instance;
  final _q = TextEditingController();

  List<CitizenHit> _rows = const [];
  bool _loading = false;
  bool _changed = false;
  String _relationship = kRelationshipLabels.keys.first; // Owner
  bool _isPrimary = false;

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
      final r = await _api.searchCitizens(_q.text);
      if (mounted) {
        setState(() {
          _rows = r;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _link(CitizenHit c) async {
    try {
      await _api.addResident(
        widget.propertyId,
        citizenId: c.id,
        relationship: _relationship,
        isPrimary: _isPrimary,
      );
      _changed = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تمّ ربط المواطن',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
              backgroundColor: AppTheme.successColor),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذّر الربط: $e', style: GoogleFonts.cairo()),
              backgroundColor: AppTheme.errorColor),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PropUi.pageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          _grabber(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('ربط مواطن بالعقار',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, _changed),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          // صفة العلاقة + أساسي
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      for (final e in kRelationshipLabels.entries)
                        ChoiceChip(
                          label: Text(e.value,
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: _relationship == e.key
                                      ? Colors.white
                                      : const Color(0xFF475569))),
                          selected: _relationship == e.key,
                          showCheckmark: false,
                          backgroundColor: Colors.white,
                          selectedColor: AppTheme.primaryColor,
                          onSelected: (_) =>
                              setState(() => _relationship = e.key),
                        ),
                    ],
                  ),
                ),
                FilterChip(
                  label: Text('أساسي',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700, fontSize: 12)),
                  selected: _isPrimary,
                  showCheckmark: true,
                  selectedColor:
                      AppTheme.successColor.withValues(alpha: 0.18),
                  onSelected: (v) => setState(() => _isPrimary = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _q,
              onSubmitted: (_) => _search(),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المواطن / الهاتف',
                hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.primaryColor),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: AppTheme.primaryColor),
                  onPressed: _search,
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const PropLoadingView()
                : _rows.isEmpty
                    ? const PropEmptyView(
                        message: 'لا نتائج — جرّب كلمة بحث أخرى',
                        icon: Icons.person_search_rounded)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _citizenCard(_rows[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _citizenCard(CitizenHit c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: PropUi.card(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(c.name.isEmpty ? 'مواطن' : c.name,
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800, color: PropUi.ink)),
                if ([c.phone, c.district].any((x) => x.trim().isNotEmpty))
                  Text(
                    [c.phone, c.district]
                        .where((x) => x.trim().isNotEmpty)
                        .join(' · '),
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _link(c),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text('ربط',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _grabber() => Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(3),
        ),
      );
}

// ─────────────────────── ورقة إضافة خدمة ───────────────────────

class _ServiceFormSheet extends StatefulWidget {
  final String propertyId;
  const _ServiceFormSheet({required this.propertyId});

  @override
  State<_ServiceFormSheet> createState() => _ServiceFormSheetState();
}

class _ServiceFormSheetState extends State<_ServiceFormSheet> {
  final _api = PropertyApiService.instance;
  final _subscriberRef = TextEditingController();
  final _providerRefId = TextEditingController();
  final _notes = TextEditingController();

  String _serviceType = kServiceTypeLabels.keys.first; // Internet
  String _providerType = kProviderTypeLabels.keys.first; // Sas
  String _status = kServiceStatusLabels.keys.first; // Active
  bool _saving = false;

  @override
  void dispose() {
    _subscriberRef.dispose();
    _providerRefId.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.addService(
        widget.propertyId,
        serviceType: _serviceType,
        providerType: _providerType,
        subscriberRef: _subscriberRef.text.trim(),
        providerRefId: _providerRefId.text.trim(),
        status: _status,
        notes: _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('تعذّر إضافة الخدمة: $e', style: GoogleFonts.cairo()),
              backgroundColor: AppTheme.errorColor),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PropUi.pageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('إضافة خدمة للعقار',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                _label('نوع الخدمة'),
                _choiceRow(kServiceTypeLabels, _serviceType,
                    (k) => setState(() => _serviceType = k)),
                const SizedBox(height: 14),
                _label('المزوّد'),
                _choiceRow(kProviderTypeLabels, _providerType,
                    (k) => setState(() => _providerType = k)),
                const SizedBox(height: 14),
                _label('الحالة'),
                _choiceRow(kServiceStatusLabels, _status,
                    (k) => setState(() => _status = k)),
                const SizedBox(height: 14),
                _field(_subscriberRef, 'مرجع المشترك (اسم المستخدم/الرقم)',
                    icon: Icons.badge_rounded),
                _field(_providerRefId, 'معرّف المزوّد (اختياري)',
                    icon: Icons.tag_rounded),
                _field(_notes, 'ملاحظات', icon: Icons.notes_rounded,
                    maxLines: 2),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.add_rounded),
                  label: Text('إضافة الخدمة',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
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

  Widget _field(TextEditingController c, String label,
      {IconData? icon, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.cairo(),
          prefixIcon: icon == null
              ? null
              : Icon(icon, color: AppTheme.primaryColor, size: 20),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}

// ─────────────────────── ورقة إنشاء مهمة ───────────────────────

class _TaskFormSheet extends StatefulWidget {
  final String propertyId;
  const _TaskFormSheet({required this.propertyId});

  @override
  State<_TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<_TaskFormSheet> {
  final _api = PropertyApiService.instance;
  final _department = TextEditingController();
  final _technician = TextEditingController();
  final _note = TextEditingController();

  List<ServiceLookup> _services = const [];
  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  int? _serviceId;
  int? _operationId;
  int _priority = 3;

  @override
  void initState() {
    super.initState();
    _loadLookups();
  }

  @override
  void dispose() {
    _department.dispose();
    _technician.dispose();
    _note.dispose();
    super.dispose();
  }

  List<OperationLookup> get _operations {
    if (_serviceId == null) return const [];
    final svc = _services.where((s) => s.id == _serviceId);
    return svc.isEmpty ? const [] : svc.first.operations;
  }

  Future<void> _loadLookups() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final r = await _api.getServiceLookups();
      if (!mounted) return;
      setState(() {
        _services = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_serviceId == null || _operationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('اختر الخدمة والعملية أولاً',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            backgroundColor: AppTheme.warningColor),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final reqNo = await _api.createTask(
        widget.propertyId,
        serviceId: _serviceId!,
        operationTypeId: _operationId!,
        priority: _priority,
        department: _department.text,
        technician: _technician.text,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                reqNo != null && reqNo.isNotEmpty
                    ? 'تمّ إنشاء المهمة — رقم الطلب $reqNo'
                    : 'تمّ إنشاء المهمة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            backgroundColor: AppTheme.successColor),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('تعذّر إنشاء المهمة: $e', style: GoogleFonts.cairo()),
            backgroundColor: AppTheme.errorColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: PropUi.pageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('إنشاء مهمة لهذا العقار',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context, false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const PropLoadingView(message: 'جارٍ تحميل الخدمات…')
                : _loadError != null
                    ? PropErrorView(message: _loadError!, onRetry: _loadLookups)
                    : _form(),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        _label('الخدمة'),
        if (_services.isEmpty)
          Text('لا توجد خدمات متاحة',
              style: GoogleFonts.cairo(
                  color: Colors.grey[600], fontWeight: FontWeight.w600))
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final s in _services)
                ChoiceChip(
                  label: Text(s.nameAr,
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: _serviceId == s.id
                              ? Colors.white
                              : const Color(0xFF475569))),
                  selected: _serviceId == s.id,
                  showCheckmark: false,
                  backgroundColor: Colors.white,
                  selectedColor: AppTheme.primaryColor,
                  side: BorderSide(
                      color: _serviceId == s.id
                          ? AppTheme.primaryColor
                          : Colors.grey.withValues(alpha: 0.25)),
                  onSelected: (_) => setState(() {
                    _serviceId = s.id;
                    _operationId = null; // إعادة ضبط العملية عند تغيير الخدمة
                  }),
                ),
            ],
          ),
        const SizedBox(height: 14),
        _label('العملية'),
        if (_serviceId == null)
          Text('اختر خدمة لعرض عملياتها',
              style: GoogleFonts.cairo(
                  color: Colors.grey[600], fontWeight: FontWeight.w600))
        else if (_operations.isEmpty)
          Text('لا توجد عمليات لهذه الخدمة',
              style: GoogleFonts.cairo(
                  color: Colors.grey[600], fontWeight: FontWeight.w600))
        else
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final op in _operations)
                ChoiceChip(
                  label: Text(op.nameAr,
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: _operationId == op.id
                              ? Colors.white
                              : const Color(0xFF475569))),
                  selected: _operationId == op.id,
                  showCheckmark: false,
                  backgroundColor: Colors.white,
                  selectedColor: AppTheme.primaryColor,
                  side: BorderSide(
                      color: _operationId == op.id
                          ? AppTheme.primaryColor
                          : Colors.grey.withValues(alpha: 0.25)),
                  onSelected: (_) => setState(() => _operationId = op.id),
                ),
            ],
          ),
        const SizedBox(height: 14),
        _label('الأولوية'),
        Wrap(
          spacing: 8,
          children: [
            for (int p = 1; p <= 5; p++)
              ChoiceChip(
                label: Text('$p',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: _priority == p
                            ? Colors.white
                            : const Color(0xFF475569))),
                selected: _priority == p,
                showCheckmark: false,
                backgroundColor: Colors.white,
                selectedColor: AppTheme.primaryColor,
                side: BorderSide(
                    color: _priority == p
                        ? AppTheme.primaryColor
                        : Colors.grey.withValues(alpha: 0.25)),
                onSelected: (_) => setState(() => _priority = p),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _field(_department, 'القسم (اختياري)', icon: Icons.apartment_rounded),
        _field(_technician, 'الفني (اختياري)', icon: Icons.engineering_rounded),
        _field(_note, 'ملاحظة (اختياري)',
            icon: Icons.notes_rounded, maxLines: 3),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add_task_rounded),
          label: Text('إنشاء',
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.w800, fontSize: 15)),
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Colors.grey[700])),
      );

  Widget _field(TextEditingController c, String label,
      {IconData? icon, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.cairo(),
          prefixIcon: icon == null
              ? null
              : Icon(icon, color: AppTheme.primaryColor, size: 20),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }
}
