/// قائمة سجل العقارات — بحث + تصفية (نوع/ملكية) + ترقيم + بطاقات + إضافة.
///
/// نظام أساسي ينادي بوّابة الصدارة `/api/properties`. بثيم الصدارة (Cairo/
/// AppTheme) ومتجاوب مع سطح المكتب، RTL.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/property.dart';
import '../../permissions/permission_manager.dart';
import '../../services/property_api_service.dart';
import '../../theme/app_theme.dart';
import 'property_detail_page.dart';
import 'property_form_page.dart';
import 'property_ui.dart';

class PropertiesListPage extends StatefulWidget {
  const PropertiesListPage({super.key});

  @override
  State<PropertiesListPage> createState() => _PropertiesListPageState();
}

class _PropertiesListPageState extends State<PropertiesListPage> {
  final _api = PropertyApiService.instance;
  final _q = TextEditingController();

  List<Property> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _propertyFilter; // Residential / Commercial
  String? _ownershipFilter; // Owned / Rent
  int _page = 1;
  int _total = 0;
  bool _hasMore = false;
  static const int _pageSize = 30;

  bool get _canManage =>
      PermissionManager.instance.canAdd('property_registry');

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

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });
    try {
      final r = await _api.list(
        q: _q.text,
        propertyType: _propertyFilter,
        ownership: _ownershipFilter,
        page: page,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _rows = r.items;
        _total = r.total;
        _hasMore = r.hasMore;
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

  void _setProperty(String? v) {
    setState(() => _propertyFilter = v);
    _load();
  }

  void _setOwnership(String? v) {
    setState(() => _ownershipFilter = v);
    _load();
  }

  Future<void> _add() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PropertyFormPage()),
    );
    if (saved == true) _load();
  }

  Future<void> _open(Property p) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PropertyDetailPage(propertyId: p.id)),
    );
    if (mounted) _load(page: _page);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PropUi.pageBg,
        appBar: PropUi.appBar(
          'سجل العقارات',
          leadingIcon: Icons.home_work_rounded,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : () => _load(page: _page),
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
            const SizedBox(width: 4),
          ],
        ),
        floatingActionButton: _canManage
            ? FloatingActionButton.extended(
                onPressed: _add,
                backgroundColor: AppTheme.primaryColor,
                icon: const Icon(Icons.add_home_work_rounded),
                label: Text('عقار جديد',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              )
            : null,
        body: PropContentWrap(
          maxWidth: 1000,
          child: Column(
            children: [
              _searchBar(),
              _filters(),
              Expanded(child: _list()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: TextField(
        controller: _q,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _load(),
        style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'بحث: رقم وطني / عنوان / نقطة دالة',
          hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
          prefixIcon:
              const Icon(Icons.search_rounded, color: AppTheme.primaryColor),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.primaryColor),
            onPressed: () => _load(),
          ),
          isDense: true,
        ),
      ),
    );
  }

  Widget _filters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          _chip('الكل',
              _propertyFilter == null && _ownershipFilter == null, () {
            setState(() {
              _propertyFilter = null;
              _ownershipFilter = null;
            });
            _load();
          }),
          for (final e in kPropertyTypeLabels.entries)
            _chip(e.value, _propertyFilter == e.key,
                () => _setProperty(_propertyFilter == e.key ? null : e.key)),
          for (final e in kOwnershipLabels.entries)
            _chip(e.value, _ownershipFilter == e.key,
                () => _setOwnership(_ownershipFilter == e.key ? null : e.key)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label,
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: selected ? Colors.white : const Color(0xFF475569))),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        backgroundColor: Colors.white,
        selectedColor: AppTheme.primaryColor,
        side: BorderSide(
            color: selected
                ? AppTheme.primaryColor
                : Colors.grey.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PropUi.radiusPill)),
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return const PropLoadingView(message: 'جارٍ تحميل العقارات…');
    }
    if (_error != null) {
      return PropErrorView(message: _error!, onRetry: () => _load(page: _page));
    }
    if (_rows.isEmpty) {
      return PropEmptyView(
        message: _page > 1
            ? 'لا مزيد من العقارات في هذه الصفحة'
            : 'لا عقارات بعد — أضف عقاراً بالزرّ أدناه',
        icon: Icons.maps_home_work_outlined,
        action: _canManage && _page == 1
            ? FilledButton.icon(
                onPressed: _add,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                icon: const Icon(Icons.add_home_work_rounded),
                label: Text('عقار جديد',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              )
            : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 96),
      itemCount: _rows.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        if (i == _rows.length) return _pager();
        return _card(_rows[i]);
      },
    );
  }

  Widget _pager() {
    final totalPages =
        _total <= 0 ? _page : ((_total + _pageSize - 1) ~/ _pageSize);
    if (_page <= 1 && !_hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
            label: Text('السابق',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Text('صفحة $_page من $totalPages',
              style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w800, color: Colors.grey[700])),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _hasMore ? () => _load(page: _page + 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            label: Text('التالي',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _card(Property p) {
    final commercial = p.isCommercial;
    final tint = commercial ? AppTheme.warningColor : AppTheme.primaryColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PropUi.radius),
        onTap: () => _open(p),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: PropUi.card(),
          child: Row(
            children: [
              PropUi.gradientBadge(
                icon: commercial
                    ? Icons.storefront_rounded
                    : Icons.home_rounded,
                colors: commercial
                    ? AppTheme.orangeGradient
                    : AppTheme.blueGradient,
                size: 46,
                iconSize: 23,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: PropUi.ink),
                    ),
                    if (p.shortAddress.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(p.shortAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                              fontSize: 12, color: Colors.grey[600])),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _tag(p.propertyTypeLabel, tint),
                        _tag(p.ownershipLabel, AppTheme.successColor),
                        _tag('${p.serviceCount} خدمة',
                            AppTheme.secondaryColor),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
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
}
