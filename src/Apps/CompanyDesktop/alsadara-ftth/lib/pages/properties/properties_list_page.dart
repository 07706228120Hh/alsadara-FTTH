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
import 'location_master_page.dart';
import 'property_detail_page.dart';
import 'property_form_page.dart';
import 'property_qr_batches_page.dart';
import 'property_qr_scanner.dart';
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
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
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
        content: Text(m, style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: err ? AppTheme.errorColor : AppTheme.successColor,
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
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.qr_code_scanner_rounded,
                    color: Colors.white),
                label: Text('مسح رمز العقار',
                    style: GoogleFonts.cairo(
                        fontWeight: FontWeight.w800, color: Colors.white)),
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
            : 'لا عقارات بعد — امسح رمز العنوان الوطني لبدء إدخال عقار',
        icon: Icons.maps_home_work_outlined,
        action: _canManage && _page == 1
            ? FilledButton.icon(
                onPressed: _scanQr,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text('مسح رمز العقار',
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
                color: AppTheme.primaryColor),
            const SizedBox(width: 8),
            Text('مسح/إدخال رمز QR',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'امسح لصاقة العنوان الوطني بالكاميرا أو بماسح QR، أو الصق/اكتب الرمز يدوياً.',
              style:
                  GoogleFonts.cairo(fontSize: 12.5, color: Colors.grey[700]),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _c,
              focusNode: _focus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'SADARA|P:… أو الرمز',
                hintStyle: GoogleFonts.cairo(color: Colors.grey[500]),
                prefixIcon: const Icon(Icons.qr_code_rounded,
                    color: AppTheme.primaryColor),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openCamera,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(
                      color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.photo_camera_rounded, size: 20),
                label: Text('فتح الكاميرا والمسح',
                    style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          ),
          FilledButton.icon(
            onPressed: _submit,
            style:
                FilledButton.styleFrom(backgroundColor: AppTheme.primaryColor),
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text('بحث',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
