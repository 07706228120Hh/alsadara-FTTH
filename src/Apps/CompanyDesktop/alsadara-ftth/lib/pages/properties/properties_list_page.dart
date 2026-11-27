/// قائمة سجل العقارات — بحث + تصفية (نوع/ملكية) + ترقيم + بطاقات + إضافة.
///
/// نظام أساسي ينادي بوّابة الصدارة `/api/properties`. بنظام تصميم الصدارة
/// الموحّد (sd: Cairo + SdColors) ومتجاوب مع سطح المكتب، RTL.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import '../../frontend/components/sd_raised.dart';
import '../../frontend/tokens/sd_colors.dart';
import '../../models/property.dart';
import '../../permissions/permission_manager.dart';
import '../../services/property_api_service.dart';
import 'location_master_page.dart';
import 'property_detail_page.dart';
import 'property_form_page.dart';
import 'property_qr_batches_page.dart';
import 'property_qr_scanner.dart';
import 'property_ui.dart';

/// جزء من شريط النِسَب في لوحة التحليل (تسمية + عدد + لون).
class _Seg {
  final String label;
  final int count;
  final Color color;
  const _Seg(this.label, this.count, this.color);
}

class PropertiesListPage extends StatefulWidget {
  const PropertiesListPage({super.key});

  @override
  State<PropertiesListPage> createState() => _PropertiesListPageState();
}

class _PropertiesListPageState extends State<PropertiesListPage> {
  final _api = PropertyApiService.instance;
  final _q = TextEditingController();
  Timer? _debounce; // بحث فوري مؤجَّل أثناء الكتابة (تصفية حيّة).

  List<Property> _rows = const [];
  bool _loading = true;
  String? _error;
  String? _propertyFilter; // Residential / Commercial
  String? _ownershipFilter; // Owned / Rent
  bool? _hasLocationFilter; // null=الكل · true=لها موقع · false=بلا موقع
  bool? _hasServiceFilter; // null=الكل · true=لها خدمة · false=بلا خدمة
  String? _serviceTypeFilter; // Internet / Master / Iptv / Other
  String _sort = 'newest'; // newest / oldest / npn
  PropertySummary _summary = const PropertySummary();
  bool _showInsights = true; // توسيع لوحة التحليل
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
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  /// بحث فوري: يُصفّي تلقائياً بعد توقّف الكتابة لحظةً (debounce) بلا زرّ.
  void _onQueryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load();
    });
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
        hasLocation: _hasLocationFilter,
        hasService: _hasServiceFilter,
        serviceType: _serviceTypeFilter,
        sort: _sort,
        page: page,
        pageSize: _pageSize,
      );
      // الملخّص عدّادات عامّة (غير متأثّرة بالبحث/الفلتر) — نجلبه مع الصفحة الأولى فقط.
      final summary = page == 1 ? await _api.summary() : _summary;
      if (!mounted) return;
      setState(() {
        _rows = r.items;
        _total = r.total;
        _hasMore = r.hasMore;
        _summary = summary;
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

  void _setHasLocation(bool? v) {
    setState(() => _hasLocationFilter = v);
    _load();
  }

  void _setHasService(bool? v) {
    setState(() => _hasServiceFilter = v);
    _load();
  }

  void _setServiceType(String? v) {
    setState(() => _serviceTypeFilter = v);
    _load();
  }

  void _setSort(String v) {
    setState(() => _sort = v);
    _load();
  }

  bool get _anyFilterActive =>
      _propertyFilter != null ||
      _ownershipFilter != null ||
      _hasLocationFilter != null ||
      _hasServiceFilter != null ||
      _serviceTypeFilter != null;

  void _clearFilters() {
    setState(() {
      _propertyFilter = null;
      _ownershipFilter = null;
      _hasLocationFilter = null;
      _hasServiceFilter = null;
      _serviceTypeFilter = null;
    });
    _load();
  }

  Future<void> _openLocationMaster() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LocationMasterPage()),
    );
  }

  Future<void> _openQrBatches() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const PropertyQrBatchesPage()),
    );
  }

  /// مسح/إدخال رمز QR: يحلّه عبر الخادم ويوجّه حسب النتيجة:
  /// - عقار → يفتح التفاصيل.
  /// - رمز فارغ → يفتح نموذج إنشاء بوضع «رمز فارغ» (مع تمرير الرمز/التسلسل).
  /// - رمز غير معروف (404) → رسالة «رمز غير معروف».
  ///
  /// الإدخال يدعم ماسحات QR على سطح المكتب (تُرسِل الحمولة كنصّ) أو الإدخال اليدوي.
  Future<void> _scanQr() async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => const _QrInputDialog(),
    );
    final token = _extractQrToken(raw);
    if (token == null || token.isEmpty) return;

    _showBlocking('جارٍ البحث عن الرمز…');
    try {
      final r = await _api.resolveQr(token);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // أغلق الحاجب
      if (r.isProperty) {
        final p = r.details!.property;
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => PropertyDetailPage(propertyId: p.id)),
        );
        if (mounted) _load(page: _page);
      } else if (r.blank) {
        if (!_canManage) {
          _snack('رمز فارغ — لا تملك صلاحية إنشاء عقار', err: true);
          return;
        }
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => PropertyFormPage(
              prefilledQrToken: r.qrToken,
              prefilledSerial: r.serial,
            ),
          ),
        );
        if (saved == true && mounted) _load();
      } else {
        _snack('رمز غير معروف', err: true);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      final msg = '$e';
      _snack(msg.contains('404') ? 'رمز غير معروف' : 'تعذّر قراءة الرمز: $msg',
          err: true);
    }
  }

  /// يستخرج الرمز من حمولة مطبوعة `SADARA|P:<token>` أو يُعيد النصّ كما هو.
  String? _extractQrToken(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;
    const prefix = 'SADARA|P:';
    if (s.startsWith(prefix)) return s.substring(prefix.length).trim();
    // قد يصل بصيغة أخرى؛ نمرّره كرمز خام (الخادم يحسم صلاحيته).
    return s;
  }

  void _showBlocking(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(message,
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
        backgroundColor: err ? SdColors.danger : SdColors.success,
      ),
    );
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
              tooltip: 'مسح/إدخال رمز QR',
              onPressed: _scanQr,
              icon: const Icon(Icons.qr_code_scanner_rounded,
                  color: Colors.white),
            ),
            if (_canManage)
              IconButton(
                tooltip: 'دفعات QR',
                onPressed: _openQrBatches,
                icon: const Icon(Icons.qr_code_2_rounded, color: Colors.white),
              ),
            IconButton(
              tooltip: 'المناطق والعناوين',
              onPressed: _openLocationMaster,
              icon: const Icon(Icons.layers_rounded, color: Colors.white),
            ),
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
                onPressed: _scanQr,
                backgroundColor: SdColors.primary,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.qr_code_scanner_rounded,
                    color: Colors.white),
                label: Text('مسح رمز العقار',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800, color: Colors.white)),
              )
            : null,
        body: PropContentWrap(
          maxWidth: 1000,
          child: Column(
            children: [
              _searchBar(),
              _insightsPanel(),
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
        onChanged: _onQueryChanged,
        onSubmitted: (_) {
          _debounce?.cancel();
          _load();
        },
        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'بحث: اسم / هاتف / رقم وطني / عنوان',
          hintStyle: TextStyle(fontFamily: 'Cairo', color: SdColors.faint),
          prefixIcon:
              const Icon(Icons.search_rounded, color: SdColors.primary),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: SdColors.primary),
            onPressed: () => _load(),
          ),
          isDense: true,
        ),
      ),
    );
  }

  /// لوحة تحليل احترافية أعلى القائمة: مؤشّرات رئيسية (KPIs) + أشرطة نِسَب
  /// (نوع/ملكية/تغطية موقع/خدمات). المؤشّرات قابلة للنقر كفلتر سريع.
  Widget _insightsPanel() {
    final s = _summary;
    if (s.total == 0) return const SizedBox(height: 4);
    int pct(int n) => s.total == 0 ? 0 : ((n * 100) / s.total).round();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: PropUi.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded,
                  size: 18, color: SdColors.primary),
              const SizedBox(width: 6),
              Text('تحليل العقارات',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: PropUi.ink)),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _showInsights = !_showInsights),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                      _showInsights
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: SdColors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _kpiTile('الإجمالي', '${s.total}', Icons.home_work_rounded,
                  SdColors.primary, null),
              _kpiTile('تغطية الموقع', '${pct(s.withLocation)}%',
                  Icons.location_on_rounded, SdColors.success,
                  () => _setHasLocation(_hasLocationFilter == true ? null : true)),
              _kpiTile('مشمول بخدمة', '${pct(s.withService)}%',
                  Icons.wifi_rounded, SdColors.info,
                  () => _setHasService(_hasServiceFilter == true ? null : true)),
            ],
          ),
          if (_showInsights) ...[
            const SizedBox(height: 14),
            _proportionRow('نوع العقار', [
              _Seg('سكني', s.residential, SdColors.primary),
              _Seg('تجاري', s.commercial, SdColors.warning),
            ]),
            const SizedBox(height: 11),
            _proportionRow('الملكية', [
              _Seg('ملك', s.owned, SdColors.success),
              _Seg('إيجار', s.rent, SdColors.info),
            ]),
            const SizedBox(height: 11),
            _proportionRow('تغطية الموقع', [
              _Seg('لها موقع', s.withLocation, SdColors.success),
              _Seg('بلا موقع', s.withoutLocation, SdColors.faint),
            ]),
            const SizedBox(height: 11),
            _proportionRow('الخدمات', [
              _Seg('إنترنت', s.internet, SdColors.info),
              _Seg('ماستر', s.master, SdColors.accent),
              _Seg('IPTV', s.iptv, SdColors.warning),
              _Seg('بلا خدمة', s.withoutService, SdColors.faint),
            ]),
          ],
        ],
      ),
    );
  }

  /// مؤشّر رئيسي (KPI) — رقم كبير + أيقونة + تسمية، قابل للنقر كفلتر سريع.
  Widget _kpiTile(
      String label, String value, IconData icon, Color color, VoidCallback? onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: color),
                  const SizedBox(height: 3),
                  Text(value,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: color)),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 10.5,
                          color: SdColors.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// شريط نِسَب أفقي مجزّأ + أسطورة (dot + تسمية + عدد) — عرض احترافي للتوزيع.
  Widget _proportionRow(String title, List<_Seg> segs) {
    final total = segs.fold<int>(0, (a, b) => a + b.count);
    final shown = segs.where((e) => e.count > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: PropUi.ink)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 11,
            child: total == 0
                ? Container(color: SdColors.faint.withValues(alpha: 0.18))
                : Row(
                    children: [
                      for (final e in shown)
                        Expanded(
                            flex: e.count, child: Container(color: e.color)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 3,
          children: [
            for (final e in segs)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: e.color, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('${e.label} ${e.count}',
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: SdColors.muted)),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _filters() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        children: [
          _anyFilterActive
              ? _chip('مسح الفلاتر ✕', false, _clearFilters)
              : _chip('الكل', true, () {}),
          for (final e in kOwnershipLabels.entries)
            _chip(e.value, _ownershipFilter == e.key,
                () => _setOwnership(_ownershipFilter == e.key ? null : e.key)),
          _chip('إنترنت', _serviceTypeFilter == 'Internet',
              () => _setServiceType(
                  _serviceTypeFilter == 'Internet' ? null : 'Internet')),
          _chip('ماستر', _serviceTypeFilter == 'Master',
              () => _setServiceType(
                  _serviceTypeFilter == 'Master' ? null : 'Master')),
          _chip('IPTV', _serviceTypeFilter == 'Iptv',
              () => _setServiceType(_serviceTypeFilter == 'Iptv' ? null : 'Iptv')),
          _sortChip(),
        ],
      ),
    );
  }

  /// شريحة الترتيب (قائمة منسدلة).
  Widget _sortChip() {
    const labels = {'newest': 'الأحدث', 'oldest': 'الأقدم', 'npn': 'رقم وطني'};
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: PopupMenuButton<String>(
        onSelected: _setSort,
        itemBuilder: (_) => [
          for (final e in labels.entries)
            PopupMenuItem(
                value: e.key,
                child: Text(e.value,
                    style: const TextStyle(fontFamily: 'Cairo'))),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(PropUi.radiusPill),
            border: Border.all(color: SdColors.faint.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sort_rounded, size: 16, color: SdColors.muted),
              const SizedBox(width: 4),
              Text(labels[_sort] ?? 'الأحدث',
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: SdColors.muted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: selected ? Colors.white : SdColors.muted)),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        backgroundColor: Colors.white,
        selectedColor: SdColors.primary,
        side: BorderSide(
            color: selected
                ? SdColors.primary
                : SdColors.faint.withValues(alpha: 0.25)),
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
            : 'لا عقارات بعد — امسح رمز العنوان الوطني لبدء إدخال عقار',
        icon: Icons.maps_home_work_outlined,
        action: _canManage && _page == 1
            ? SdButton(
                label: 'مسح رمز العقار',
                icon: Icons.qr_code_scanner_rounded,
                onPressed: _scanQr,
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
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Text('صفحة $_page من $totalPages',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800, color: SdColors.muted)),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _hasMore ? () => _load(page: _page + 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
            label: Text('التالي',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _card(Property p) {
    final commercial = p.isCommercial;
    final tint = commercial ? SdColors.warning : SdColors.primary;
    // اسم/هاتف المواطن للعرض: نُفضّل المواطن الأساسي المرتبط، وإلا مالك العقار
    // المخزّن مباشرةً على السجل (OwnerName/OwnerPhone).
    final residentName = (p.primaryResidentName ?? '').trim().isNotEmpty
        ? p.primaryResidentName!.trim()
        : (p.ownerName ?? '').trim();
    final residentPhone = (p.primaryResidentPhone ?? '').trim().isNotEmpty
        ? p.primaryResidentPhone!.trim()
        : (p.ownerPhone ?? '').trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(PropUi.radius),
        onTap: () => _open(p),
        child: Container(
          decoration: PropUi.card(),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // شريط لوني جانبي حسب نوع العقار (لمسة احترافية).
                Container(width: 4, color: tint),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        PropUi.gradientBadge(
                icon: commercial
                    ? Icons.storefront_rounded
                    : Icons.home_rounded,
                colors: commercial
                    ? SdColors.orangeGradient
                    : SdColors.blueGradient,
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
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: PropUi.ink),
                    ),
                    if (p.shortAddress.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(p.shortAddress,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12, color: SdColors.muted)),
                    ],
                    if (residentName.isNotEmpty ||
                        residentPhone.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_rounded,
                              size: 14, color: SdColors.primary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              residentName.isNotEmpty ? residentName : '—',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: PropUi.ink),
                            ),
                          ),
                          if (residentPhone.isNotEmpty) ...[
                            const SizedBox(width: 10),
                            const Icon(Icons.phone_rounded,
                                size: 13, color: SdColors.success),
                            const SizedBox(width: 3),
                            Text(
                              residentPhone,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: SdColors.muted),
                            ),
                          ],
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _locationTag(p),
                        _tag(p.propertyTypeLabel, tint),
                        _tag(p.ownershipLabel, SdColors.success),
                        ..._serviceTags(p),
                      ],
                    ),
                    if (_cardMeta(p).isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 12, color: SdColors.faint),
                          const SizedBox(width: 3),
                          Text(_cardMeta(p),
                              style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10.5,
                                  color: SdColors.faint)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
                        const Icon(Icons.chevron_left_rounded,
                            color: SdColors.faint),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// شارة مؤشّر الموقع على البطاقة (أخضر=لها إحداثيات · رمادي=بلا موقع) — مرتبطة بالخارطة.
  Widget _locationTag(Property p) {
    final has = p.latitude != null && p.longitude != null;
    return _iconTag(
        has ? 'موقع' : 'بلا موقع',
        has ? Icons.location_on_rounded : Icons.location_off_rounded,
        has ? SdColors.success : SdColors.faint);
  }

  /// سطر معلومات مختصر أسفل البطاقة (عدد الخدمات · تاريخ الإضافة).
  String _cardMeta(Property p) {
    final parts = <String>[];
    if (p.serviceCount > 0) parts.add('${p.serviceCount} خدمة');
    final d = _shortDate(p.createdAt);
    if (d.isNotEmpty) parts.add('أُضيف $d');
    return parts.join('   ·   ');
  }

  String _shortDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}/${two(l.month)}/${two(l.day)}';
  }

  /// شارات خدمات العقار على البطاقة: شارة لكل نوع خدمة مميّز (إنترنت/ماستر/…)
  /// بأيقونة ولون مخصّصين. أنواع مستقبلية غير معروفة تُعرض بتسميتها الخام وأيقونة
  /// محايدة تلقائياً (لا حاجة لتعديل عند إضافة نوع جديد). بلا خدمة ⇒ شارة رمادية.
  List<Widget> _serviceTags(Property p) {
    if (p.serviceTypes.isEmpty) {
      return [_tag('بلا خدمة', SdColors.faint)];
    }
    return [
      for (final type in p.serviceTypes)
        _iconTag(
          serviceTypeLabelOf(type),
          _serviceTypeIcon(type),
          _serviceTypeColor(type),
        ),
    ];
  }

  IconData _serviceTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'internet':
        return Icons.wifi_rounded;
      case 'master':
        return Icons.satellite_alt_rounded;
      case 'iptv':
        return Icons.live_tv_rounded;
      default:
        return Icons.bolt_rounded; // نوع مستقبلي غير معروف
    }
  }

  Color _serviceTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'internet':
        return SdColors.primary;
      case 'master':
        return SdColors.warning;
      case 'iptv':
        return SdColors.success;
      default:
        return SdColors.muted;
    }
  }

  /// شارة بأيقونة + نصّ (لأنواع الخدمات).
  Widget _iconTag(String t, IconData icon, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(PropUi.radiusPill),
          border: Border.all(color: c.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: c),
            const SizedBox(width: 3),
            Text(t,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: c, fontWeight: FontWeight.w700, fontSize: 11)),
          ],
        ),
      );

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(PropUi.radiusPill),
          border: Border.all(color: c.withValues(alpha: 0.22)),
        ),
        child: Text(t,
            style: TextStyle(
                fontFamily: 'Cairo',
                color: c, fontWeight: FontWeight.w700, fontSize: 11)),
      );
}

/// حوار مسح/إدخال رمز QR — يستقبل حمولة من ماسح QR (كنصّ) أو إدخالاً يدوياً.
///
/// على سطح المكتب، ماسحات الـUSB تُرسِل الحمولة كمفاتيح لوحة مفاتيح؛ الحقل
/// مركّز تلقائياً ويُرسِل عند Enter.
class _QrInputDialog extends StatefulWidget {
  const _QrInputDialog();

  @override
  State<_QrInputDialog> createState() => _QrInputDialogState();
}

class _QrInputDialogState extends State<_QrInputDialog> {
  final _c = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _c.text);

  // يفتح ماسح الكاميرا؛ عند اكتشاف رمز يُغلق الحوار ويُكمل مسار الحلّ.
  Future<void> _openCamera() async {
    final res = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PropertyQrScannerScreen()),
    );
    if (!mounted) return;
    if (res != null && res.trim().isNotEmpty) {
      Navigator.pop(context, res.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_scanner_rounded,
                color: SdColors.primary),
            const SizedBox(width: 8),
            Text('مسح/إدخال رمز QR',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'امسح لصاقة العنوان الوطني بالكاميرا أو بماسح QR، أو الصق/اكتب الرمز يدوياً.',
              style:
                  TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: SdColors.muted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _c,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'SADARA|P:… أو الرمز',
                hintStyle: TextStyle(fontFamily: 'Cairo', color: SdColors.faint),
                prefixIcon: const Icon(Icons.qr_code_rounded,
                    color: SdColors.primary),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openCamera,
                style: OutlinedButton.styleFrom(
                  foregroundColor: SdColors.primary,
                  side: BorderSide(
                      color: SdColors.primary.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.photo_camera_rounded, size: 20),
                label: Text('فتح الكاميرا والمسح',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
          FilledButton.icon(
            onPressed: _submit,
            style:
                FilledButton.styleFrom(backgroundColor: SdColors.primary),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text('بحث',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
