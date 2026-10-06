/// شاشة «المناطق والعناوين» — إدارة البنية الهرمية للمواقع بتنقّل تنازلي:
/// المنطقة → العنوان 2 → العنوان 3. نظام أساسي ينادي بوّابة الصدارة
/// `/api/properties/{regions|address2|address3}`. بثيم الصدارة، RTL.
///
/// أزرار التعديل/الحذف تظهر فقط لمن يملك صلاحية الإضافة/الحذف على
/// `property_registry` (نفس الحارس المستخدم في بقية شاشات العقارات).
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/property.dart';
import '../../permissions/permission_manager.dart';
import '../../services/property_api_service.dart';
import '../../theme/app_theme.dart';
import 'property_ui.dart';

class LocationMasterPage extends StatefulWidget {
  const LocationMasterPage({super.key});

  @override
  State<LocationMasterPage> createState() => _LocationMasterPageState();
}

/// مستوى التنقّل الحالي.
enum _Level { regions, address2, address3 }

class _LocationMasterPageState extends State<LocationMasterPage> {
  final _api = PropertyApiService.instance;

  _Level _level = _Level.regions;

  List<PropRegion> _regions = const [];
  List<AddressNode> _address2 = const [];
  List<AddressNode> _address3 = const [];

  PropRegion? _selectedRegion; // سياق المستوى 2/3
  AddressNode? _selectedAddress2; // سياق المستوى 3

  bool _loading = true;
  String? _error;

  bool get _canManage =>
      PermissionManager.instance.canAdd('property_registry') ||
      PermissionManager.instance.canDelete('property_registry');

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  // ─────────────────────────── تحميل البيانات ───────────────────────────

  Future<void> _loadRegions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.getRegions();
      if (!mounted) return;
      setState(() {
        _regions = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadAddress2(PropRegion region) async {
    setState(() {
      _loading = true;
      _error = null;
      _level = _Level.address2;
      _selectedRegion = region;
      _selectedAddress2 = null;
    });
    try {
      final r = await _api.getAddress2(region.id);
      if (!mounted) return;
      setState(() {
        _address2 = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reloadAddress2() async {
    final region = _selectedRegion;
    if (region == null) return;
    try {
      final r = await _api.getAddress2(region.id);
      if (!mounted) return;
      setState(() => _address2 = r);
    } catch (e) {
      if (!mounted) return;
      _msg('$e', err: true);
    }
  }

  Future<void> _loadAddress3(AddressNode a2) async {
    setState(() {
      _loading = true;
      _error = null;
      _level = _Level.address3;
      _selectedAddress2 = a2;
    });
    try {
      final r = await _api.getAddress3(a2.id);
      if (!mounted) return;
      setState(() {
        _address3 = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _reloadAddress3() async {
    final a2 = _selectedAddress2;
    if (a2 == null) return;
    try {
      final r = await _api.getAddress3(a2.id);
      if (!mounted) return;
      setState(() => _address3 = r);
    } catch (e) {
      if (!mounted) return;
      _msg('$e', err: true);
    }
  }

  void _goBack() {
    switch (_level) {
      case _Level.address3:
        setState(() {
          _level = _Level.address2;
          _selectedAddress2 = null;
          _address3 = const [];
        });
        break;
      case _Level.address2:
        setState(() {
          _level = _Level.regions;
          _selectedRegion = null;
          _address2 = const [];
        });
        break;
      case _Level.regions:
        Navigator.of(context).maybePop();
        break;
    }
  }

  Future<void> _refresh() async {
    switch (_level) {
      case _Level.regions:
        await _loadRegions();
        break;
      case _Level.address2:
        if (_selectedRegion != null) await _loadAddress2(_selectedRegion!);
        break;
      case _Level.address3:
        if (_selectedAddress2 != null) await _loadAddress3(_selectedAddress2!);
        break;
    }
  }

  // ─────────────────────────── عمليات المنطقة ───────────────────────────

  Future<void> _addRegion() async {
    final r = await _showRegionDialog();
    if (r == null) return;
    try {
      await _api.createRegion(
        name: r.name,
        code: r.code,
        governorate: r.governorate,
        city: r.city,
        maintenanceFee: r.maintenanceFee,
        isActive: r.isActive,
      );
      if (!mounted) return;
      _msg('أُضيفت المنطقة');
      await _loadRegions();
    } catch (e) {
      if (!mounted) return;
      _msg('تعذّرت الإضافة: $e', err: true);
    }
  }

  Future<void> _editRegion(PropRegion region) async {
    final r = await _showRegionDialog(existing: region);
    if (r == null) return;
    try {
      await _api.updateRegion(region.id, {
        'name': r.name,
        'code': r.code,
        'governorate': r.governorate,
        'city': r.city,
        'maintenanceFee': r.maintenanceFee,
        'isActive': r.isActive,
      });
      if (!mounted) return;
      _msg('حُفظت التعديلات');
      await _loadRegions();
    } catch (e) {
      if (!mounted) return;
      _msg('تعذّر الحفظ: $e', err: true);
    }
  }

  Future<void> _deleteRegion(PropRegion region) async {
    final ok = await _confirmDelete('حذف المنطقة «${region.name}»؟');
    if (ok != true) return;
    try {
      await _api.deleteRegion(region.id);
      if (!mounted) return;
      _msg('حُذفت المنطقة');
      await _loadRegions();
    } catch (e) {
      if (!mounted) return;
      _msg('$e', err: true);
    }
  }

  // ─────────────────────────── عمليات العنوان 2/3 ───────────────────────────

  Future<void> _addAddress2() async {
    final region = _selectedRegion;
    if (region == null) return;
    final r = await _showNodeDialog('عنوان 2 جديد');
    if (r == null) return;
    try {
      await _api.createAddress2(region.id, r.name, isActive: r.isActive);
      if (!mounted) return;
      _msg('أُضيف العنوان');
      await _reloadAddress2();
    } catch (e) {
      if (!mounted) return;
      _msg('تعذّرت الإضافة: $e', err: true);
    }
  }

  Future<void> _editAddress2(AddressNode node) async {
    final r = await _showNodeDialog('تعديل عنوان 2', existing: node);
    if (r == null) return;
    try {
      await _api.updateAddress2(node.id, name: r.name, isActive: r.isActive);
      if (!mounted) return;
      _msg('حُفظت التعديلات');
      await _reloadAddress2();
    } catch (e) {
      if (!mounted) return;
      _msg('تعذّر الحفظ: $e', err: true);
    }
  }

  Future<void> _deleteAddress2(AddressNode node) async {
    final ok = await _confirmDelete('حذف العنوان «${node.name}»؟');
    if (ok != true) return;
    try {
      await _api.deleteAddress2(node.id);
      if (!mounted) return;
      _msg('حُذف العنوان');
      await _reloadAddress2();
    } catch (e) {
      if (!mounted) return;
      _msg('$e', err: true);
    }
  }

  Future<void> _addAddress3() async {
    final a2 = _selectedAddress2;
    if (a2 == null) return;
    final r = await _showNodeDialog('عنوان 3 جديد');
    if (r == null) return;
    try {
      await _api.createAddress3(a2.id, r.name, isActive: r.isActive);
      if (!mounted) return;
      _msg('أُضيف العنوان');
      await _reloadAddress3();
    } catch (e) {
      if (!mounted) return;
      _msg('تعذّرت الإضافة: $e', err: true);
    }
  }

  Future<void> _editAddress3(AddressNode node) async {
    final r = await _showNodeDialog('تعديل عنوان 3', existing: node);
    if (r == null) return;
    try {
      await _api.updateAddress3(node.id, name: r.name, isActive: r.isActive);
      if (!mounted) return;
      _msg('حُفظت التعديلات');
      await _reloadAddress3();
    } catch (e) {
      if (!mounted) return;
      _msg('تعذّر الحفظ: $e', err: true);
    }
  }

  Future<void> _deleteAddress3(AddressNode node) async {
    final ok = await _confirmDelete('حذف العنوان «${node.name}»؟');
    if (ok != true) return;
    try {
      await _api.deleteAddress3(node.id);
      if (!mounted) return;
      _msg('حُذف العنوان');
      await _reloadAddress3();
    } catch (e) {
      if (!mounted) return;
      _msg('$e', err: true);
    }
  }

  // ─────────────────────────── الحوارات ───────────────────────────

  Future<_RegionInput?> _showRegionDialog({PropRegion? existing}) {
    return showDialog<_RegionInput>(
      context: context,
      builder: (_) => _RegionDialog(existing: existing),
    );
  }

  Future<_NodeInput?> _showNodeDialog(String title, {AddressNode? existing}) {
    return showDialog<_NodeInput>(
      context: context,
      builder: (_) => _NodeDialog(title: title, existing: existing),
    );
  }

  Future<bool?> _confirmDelete(String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('تأكيد الحذف',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          content: Text(message,
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.errorColor),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('حذف',
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
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

  // ─────────────────────────── البناء ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PropUi.pageBg,
        appBar: PropUi.appBar(
          _title,
          leadingIcon: Icons.layers_rounded,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: _canManage ? _fab() : null,
        body: PropContentWrap(
          maxWidth: 820,
          child: Column(
            children: [
              _breadcrumb(),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  String get _title {
    switch (_level) {
      case _Level.regions:
        return 'المناطق والعناوين';
      case _Level.address2:
        return 'العناوين (2)';
      case _Level.address3:
        return 'العناوين (3)';
    }
  }

  Widget _fab() {
    final String label;
    final VoidCallback onTap;
    final IconData icon;
    switch (_level) {
      case _Level.regions:
        label = 'منطقة جديدة';
        icon = Icons.add_location_alt_rounded;
        onTap = _addRegion;
        break;
      case _Level.address2:
        label = 'عنوان 2 جديد';
        icon = Icons.add_road_rounded;
        onTap = _addAddress2;
        break;
      case _Level.address3:
        label = 'عنوان 3 جديد';
        icon = Icons.add_road_rounded;
        onTap = _addAddress3;
        break;
    }
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: AppTheme.primaryColor,
      icon: Icon(icon),
      label:
          Text(label, style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
    );
  }

  Widget _breadcrumb() {
    final crumbs = <Widget>[
      _crumb('المناطق', _level == _Level.regions,
          () => setState(() => _goBackTo(_Level.regions))),
    ];
    if (_selectedRegion != null) {
      crumbs
        ..add(_sep())
        ..add(_crumb(_selectedRegion!.name, _level == _Level.address2,
            () => setState(() => _goBackTo(_Level.address2))));
    }
    if (_selectedAddress2 != null) {
      crumbs
        ..add(_sep())
        ..add(_crumb(_selectedAddress2!.name, _level == _Level.address3, null));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Row(
        children: [
          if (_level != _Level.regions) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _goBack,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.arrow_forward_rounded,
                    size: 20, color: AppTheme.primaryColor),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: crumbs),
            ),
          ),
        ],
      ),
    );
  }

  /// يقفز لمستوى أعلى عبر مسار التنقّل (لا يستدعي شبكة — البيانات محمّلة).
  void _goBackTo(_Level target) {
    if (target == _Level.regions) {
      _level = _Level.regions;
      _selectedRegion = null;
      _selectedAddress2 = null;
      _address2 = const [];
      _address3 = const [];
    } else if (target == _Level.address2) {
      _level = _Level.address2;
      _selectedAddress2 = null;
      _address3 = const [];
    }
  }

  Widget _sep() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.chevron_left_rounded,
            size: 18, color: Colors.grey[400]),
      );

  Widget _crumb(String label, bool active, VoidCallback? onTap) {
    final text = Text(label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.cairo(
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
            color: active ? AppTheme.primaryColor : Colors.grey[600]));
    if (onTap == null || active) return text;
    return InkWell(onTap: onTap, child: text);
  }

  Widget _body() {
    if (_loading) {
      return const PropLoadingView(message: 'جارٍ التحميل…');
    }
    if (_error != null) {
      return PropErrorView(message: _error!, onRetry: _refresh);
    }
    switch (_level) {
      case _Level.regions:
        return _regionsList();
      case _Level.address2:
        return _nodesList(_address2, _editAddress2, _deleteAddress2,
            onOpen: _loadAddress3, emptyMsg: 'لا عناوين (2) بعد');
      case _Level.address3:
        return _nodesList(_address3, _editAddress3, _deleteAddress3,
            onOpen: null, emptyMsg: 'لا عناوين (3) بعد');
    }
  }

  Widget _regionsList() {
    if (_regions.isEmpty) {
      return PropEmptyView(
        message: 'لا مناطق بعد',
        icon: Icons.map_outlined,
        action: _canManage
            ? FilledButton.icon(
                onPressed: _addRegion,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                icon: const Icon(Icons.add_location_alt_rounded),
                label: Text('منطقة جديدة',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              )
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
      itemCount: _regions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _regionCard(_regions[i]),
    );
  }

  Widget _regionCard(PropRegion r) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PropUi.radius),
        onTap: () => _loadAddress2(r),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: PropUi.card(),
          child: Row(
            children: [
              PropUi.gradientBadge(
                icon: Icons.location_city_rounded,
                colors: AppTheme.blueGradient,
                size: 44,
                iconSize: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: PropUi.ink)),
                        ),
                        const SizedBox(width: 8),
                        PropBadge(
                          label: r.isActive ? 'نشط' : 'موقوف',
                          color: r.isActive
                              ? AppTheme.successColor
                              : Colors.grey,
                          icon: r.isActive
                              ? Icons.check_circle_rounded
                              : Icons.pause_circle_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _tag('أجر الصيانة: ${_fmtFee(r.maintenanceFee)}',
                            AppTheme.warningColor),
                        if ((r.code ?? '').isNotEmpty)
                          _tag('رمز: ${r.code}', AppTheme.secondaryColor),
                        if ((r.governorate ?? '').isNotEmpty)
                          _tag(r.governorate!, AppTheme.primaryColor),
                        if ((r.city ?? '').isNotEmpty)
                          _tag(r.city!, AppTheme.primaryColor),
                      ],
                    ),
                  ],
                ),
              ),
              if (_canManage) _rowActions(() => _editRegion(r), () => _deleteRegion(r)),
              const Icon(Icons.chevron_left_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nodesList(
    List<AddressNode> nodes,
    Future<void> Function(AddressNode) onEdit,
    Future<void> Function(AddressNode) onDelete, {
    required Future<void> Function(AddressNode)? onOpen,
    required String emptyMsg,
  }) {
    if (nodes.isEmpty) {
      return PropEmptyView(message: emptyMsg, icon: Icons.signpost_outlined);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
      itemCount: nodes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final n = nodes[i];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(PropUi.radius),
            onTap: onOpen == null ? null : () => onOpen(n),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: PropUi.card(),
              child: Row(
                children: [
                  PropUi.gradientBadge(
                    icon: Icons.signpost_rounded,
                    colors: AppTheme.greenGradient,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(n.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: PropUi.ink)),
                        ),
                        const SizedBox(width: 8),
                        PropBadge(
                          label: n.isActive ? 'نشط' : 'موقوف',
                          color:
                              n.isActive ? AppTheme.successColor : Colors.grey,
                        ),
                      ],
                    ),
                  ),
                  if (_canManage)
                    _rowActions(() => onEdit(n), () => onDelete(n)),
                  if (onOpen != null)
                    const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _rowActions(VoidCallback onEdit, VoidCallback onDelete) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (PermissionManager.instance.canEdit('property_registry'))
          IconButton(
            tooltip: 'تعديل',
            visualDensity: VisualDensity.compact,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded,
                size: 19, color: AppTheme.primaryColor),
          ),
        if (PermissionManager.instance.canDelete('property_registry'))
          IconButton(
            tooltip: 'حذف',
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded,
                size: 19, color: AppTheme.errorColor),
          ),
      ],
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(PropUi.radiusPill),
          border: Border.all(color: c.withValues(alpha: 0.22)),
        ),
        child: Text(t,
            style: GoogleFonts.cairo(
                color: c, fontWeight: FontWeight.w700, fontSize: 11)),
      );

  String _fmtFee(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }
}

// ─────────────────────────── مُدخلات الحوارات ───────────────────────────

class _RegionInput {
  final String name;
  final String? code;
  final String? governorate;
  final String? city;
  final num maintenanceFee;
  final bool isActive;
  const _RegionInput({
    required this.name,
    this.code,
    this.governorate,
    this.city,
    this.maintenanceFee = 0,
    this.isActive = true,
  });
}

class _NodeInput {
  final String name;
  final bool isActive;
  const _NodeInput({required this.name, this.isActive = true});
}

// ─────────────────────────── حوار المنطقة ───────────────────────────

class _RegionDialog extends StatefulWidget {
  final PropRegion? existing;
  const _RegionDialog({this.existing});

  @override
  State<_RegionDialog> createState() => _RegionDialogState();
}

class _RegionDialogState extends State<_RegionDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _gov =
      TextEditingController(text: widget.existing?.governorate ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _fee = TextEditingController(
      text: widget.existing == null
          ? ''
          : _feeText(widget.existing!.maintenanceFee));
  late bool _active = widget.existing?.isActive ?? true;

  static String _feeText(num v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  @override
  void dispose() {
    for (final c in [_name, _code, _gov, _city, _fee]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_RegionInput(
      name: _name.text.trim(),
      code: _code.text.trim().isEmpty ? null : _code.text.trim(),
      governorate: _gov.text.trim().isEmpty ? null : _gov.text.trim(),
      city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      maintenanceFee: num.tryParse(_fee.text.trim()) ?? 0,
      isActive: _active,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(editing ? 'تعديل منطقة' : 'منطقة جديدة',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(_name, 'اسم المنطقة',
                      icon: Icons.location_city_rounded, required: true),
                  _field(_code, 'الرمز (اختياري)', icon: Icons.tag_rounded),
                  _field(_gov, 'المحافظة (اختياري)',
                      icon: Icons.map_rounded),
                  _field(_city, 'المدينة (اختياري)',
                      icon: Icons.location_on_outlined),
                  _field(_fee, 'أجر الصيانة الشهري',
                      icon: Icons.payments_rounded,
                      keyboard: const TextInputType.numberWithOptions(
                          decimal: true),
                      numeric: true),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _active,
                    activeThumbColor: AppTheme.successColor,
                    title: Text('نشطة',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            onPressed: _submit,
            child: Text(editing ? 'حفظ' : 'إضافة',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    IconData? icon,
    bool required = false,
    bool numeric = false,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        validator: (v) {
          final t = (v ?? '').trim();
          if (required && t.isEmpty) return 'حقل مطلوب';
          if (numeric && t.isNotEmpty && num.tryParse(t) == null) {
            return 'أدخل رقماً صحيحاً';
          }
          return null;
        },
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

// ─────────────────────────── حوار العنوان ───────────────────────────

class _NodeDialog extends StatefulWidget {
  final String title;
  final AddressNode? existing;
  const _NodeDialog({required this.title, this.existing});

  @override
  State<_NodeDialog> createState() => _NodeDialogState();
}

class _NodeDialogState extends State<_NodeDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late bool _active = widget.existing?.isActive ?? true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.of(context)
        .pop(_NodeInput(name: _name.text.trim(), isActive: _active));
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text(widget.title,
            style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 400,
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'حقل مطلوب' : null,
                  decoration: InputDecoration(
                    labelText: 'الاسم',
                    labelStyle: GoogleFonts.cairo(),
                    prefixIcon: const Icon(Icons.signpost_rounded,
                        color: AppTheme.primaryColor, size: 20),
                    isDense: true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  activeThumbColor: AppTheme.successColor,
                  title: Text('نشط',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            onPressed: _submit,
            child: Text(widget.existing == null ? 'إضافة' : 'حفظ',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
