/// تبويب «مواقع المستخدمين» — خريطة ثنائية الأبعاد بقمر صناعي بمستوى تطبيقات
/// الخرائط العالمية، تعرض مواقع العقارات (المنازل) التي تملك إحداثيات.
///
/// المزايا: أساس قمر صناعي هجين (Esri + طرق/تسميات OpenFreeMap) + مبدّل شوارع،
/// تحكّم سلس (تحريك/تقريب/تبعيد/بوصلة/موقعي/توسيط)، دبابيس مصمّمة، تجميع للكثافة،
/// Heatmap، بحث فوري، Bottom Sheet أصلية غنية، ومسار ملاحي داخل التطبيق من موقعك
/// إلى المنزل (OSRM العام) مع المسافة والزمن وقائمة الخطوات. **بلا أي 3D**.
///
/// نظام أساسي ينادي بوّابة الصدارة `/api/properties/map-points`. يعرض عبر WebView
/// (MapLibre GL) ليعمل على Windows وAndroid وiOS. مزوّدات مجّانية بلا مفتاح. RTL.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart' as mobile_webview;
import 'package:webview_windows/webview_windows.dart' as windows_webview;

import '../../frontend/tokens/sd_colors.dart';
import '../../models/property.dart' show serviceTypeLabelOf;
import '../../services/property_api_service.dart';
import 'property_detail_page.dart';
import 'property_ui.dart';

/// نمط الخريطة المعروض.
enum _MapMode { satellite, streets }

class UserLocationsMapPage extends StatefulWidget {
  const UserLocationsMapPage({super.key});

  @override
  State<UserLocationsMapPage> createState() => _UserLocationsMapPageState();
}

class _UserLocationsMapPageState extends State<UserLocationsMapPage>
    with WidgetsBindingObserver {
  final _api = PropertyApiService.instance;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  List<PropertyMapPoint> _searchResults = const [];

  /// تحديث حيّ دوري صامت: يُظهر المواقع الجديدة (من أي موظف/جهاز) تلقائياً.
  Timer? _poll;
  bool _refreshing = false;
  static const Duration _pollEvery = Duration(seconds: 25);

  List<PropertyMapPoint> _points = const [];
  Map<String, PropertyMapPoint> _byId = const {};
  bool _loading = true;
  String? _error;
  String? _typeFilter; // Residential / Commercial

  _MapMode _mode = _MapMode.satellite;
  bool _heatmap = false;
  bool _mapLoaded = false;

  // حالة المسار الملاحي.
  bool _routing = false;
  _RouteInfo? _route;

  // متحكّمات WebView (المنصّة المناسبة فقط تُهيّأ).
  mobile_webview.WebViewController? _mobileController;
  windows_webview.WebviewController? _windowsController;
  StreamSubscription<dynamic>? _winMsgSub;
  bool _viewReady = false;

  bool get _isWindows => Platform.isWindows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocus.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    _winMsgSub?.cancel();
    if (_isWindows) _windowsController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند عودة التطبيق للمقدّمة: حدِّث فوراً لإظهار أي مواقع أُضيفت أثناء الغياب.
    if (state == AppLifecycleState.resumed) _silentRefresh();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) => _silentRefresh());
  }

  /// إعادة جلب صامتة للنقاط وتحديث الخريطة في مكانها دون وميض أو تغيير المنظور.
  Future<void> _silentRefresh() async {
    if (!mounted || _refreshing || _loading) return;
    _refreshing = true;
    try {
      final pts = await _api.mapPoints(propertyType: _typeFilter);
      if (!mounted) return;
      final wasEmpty = _points.isEmpty;
      final changed = pts.length != _points.length || !_sameIds(pts, _points);
      _points = pts;
      _byId = {for (final p in pts) p.id: p};
      if (mounted) setState(() {}); // تحديث عدّاد المواقع/الحالة الفارغة
      if (!changed) return;
      if (wasEmpty && pts.isNotEmpty) {
        // لم تكن الخريطة مبنيّة (حالة فارغة) — ابنها الآن ليظهر أول موقع تلقائياً.
        await _renderMap();
      } else if (_mapLoaded) {
        await _js('window.sadaraUpdate && sadaraUpdate(${_featuresJson(pts)});');
      }
    } catch (_) {/* تجاهل أخطاء التحديث الصامت */} finally {
      _refreshing = false;
    }
  }

  bool _sameIds(List<PropertyMapPoint> a, List<PropertyMapPoint> b) {
    if (a.length != b.length) return false;
    final sa = a.map((e) => e.id).toSet();
    return b.every((e) => sa.contains(e.id));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _mapLoaded = false;
      _route = null;
    });
    try {
      final pts = await _api.mapPoints(propertyType: _typeFilter);
      if (!mounted) return;
      setState(() {
        _points = pts;
        _byId = {for (final p in pts) p.id: p};
        _loading = false;
      });
      await _renderMap();
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _setType(String? v) {
    if (_typeFilter == v) return;
    setState(() => _typeFilter = v);
    _load();
  }

  // ─────────────────────────── تهيئة/تحميل WebView ───────────────────────────

  Future<void> _renderMap() async {
    if (_points.isEmpty) return;
    final html = _buildMapHtml(_points);
    try {
      if (_isWindows) {
        await _ensureWindowsController();
        await _windowsController!.loadStringContent(html);
      } else {
        await _ensureMobileController();
        await _mobileController!.loadHtmlString(html);
      }
      if (mounted) setState(() => _viewReady = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر عرض الخريطة: $e');
    }
  }

  Future<void> _ensureWindowsController() async {
    if (_windowsController != null) return;
    final c = windows_webview.WebviewController();
    await c.initialize();
    _winMsgSub = c.webMessage.listen(_onWebMessage);
    _windowsController = c;
  }

  Future<void> _ensureMobileController() async {
    if (_mobileController != null) return;
    _mobileController = mobile_webview.WebViewController()
      ..setJavaScriptMode(mobile_webview.JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('SadaraMap',
          onMessageReceived: (m) => _onWebMessage(m.message));
  }

  Future<void> _js(String script) async {
    try {
      if (_isWindows) {
        await _windowsController?.executeScript(script);
      } else {
        await _mobileController?.runJavaScript(script);
      }
    } catch (_) {/* تُتجاهَل أخطاء التنفيذ العابرة */}
  }

  /// استقبال رسائل الخريطة: جهوزية / اختيار منزل / نتيجة مسار.
  void _onWebMessage(dynamic raw) {
    try {
      final s = raw is String ? raw : '$raw';
      final txt = s.trim();
      if (!txt.startsWith('{')) return;
      final m = jsonDecode(txt) as Map<String, dynamic>;
      switch ((m['action'] ?? '').toString()) {
        case 'ready':
          if (mounted) setState(() => _mapLoaded = true);
          break;
        case 'select':
          final p = _byId[(m['id'] ?? '').toString()];
          if (p != null) _showPointSheet(p);
          break;
        case 'route':
          if (mounted) {
            setState(() {
              _routing = false;
              _route = _RouteInfo.fromJson(m);
            });
          }
          break;
        case 'routeError':
          if (mounted) setState(() => _routing = false);
          _snack('تعذّر حساب المسار — تحقّق من الاتصال', err: true);
          break;
      }
    } catch (_) {/* تجاهل الرسائل غير المتوقّعة */}
  }

  // ─────────────────────────── أزرار الخريطة الأصلية ───────────────────────────

  void _setMode(_MapMode m) {
    if (_mode == m) return;
    setState(() => _mode = m);
    _js("window.sadaraSetMode && sadaraSetMode('${m == _MapMode.satellite ? 'satellite' : 'streets'}');");
  }

  void _toggleHeatmap() {
    setState(() => _heatmap = !_heatmap);
    _js('window.sadaraToggleHeat && sadaraToggleHeat($_heatmap);');
  }

  void _zoomIn() => _js('window.sadaraZoom && sadaraZoom(1);');
  void _zoomOut() => _js('window.sadaraZoom && sadaraZoom(-1);');
  void _resetNorth() => _js('window.sadaraNorth && sadaraNorth();');
  void _fitAll() => _js('window.sadaraFit && sadaraFit();');

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _snack('خدمة الموقع غير مفعّلة على الجهاز', err: true);
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _snack('لم يُسمح بالوصول إلى الموقع', err: true);
        return null;
      }
      return await Geolocator.getCurrentPosition();
    } catch (_) {
      _snack('تعذّر تحديد الموقع', err: true);
      return null;
    }
  }

  Future<void> _goToMyLocation() async {
    final pos = await _currentPosition();
    if (pos == null) return;
    await _js('window.sadaraFly && sadaraFly(${pos.longitude}, ${pos.latitude}, 16);');
    await _js('window.sadaraMe && sadaraMe(${pos.longitude}, ${pos.latitude});');
  }

  /// يرشّح العقارات المطابقة للنصّ (اسم/هاتف/رقم وطني/منطقة) — لقائمة الاقتراحات.
  List<PropertyMapPoint> _match(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return const [];
    final digits = s.replaceAll(RegExp(r'\D'), '');
    return _points.where((p) {
      return p.name.toLowerCase().contains(s) ||
          p.npnDisplay.toLowerCase().contains(s) ||
          p.area.toLowerCase().contains(s) ||
          (digits.length >= 3 &&
              p.phone.replaceAll(RegExp(r'\D'), '').contains(digits));
    }).take(20).toList();
  }

  /// يُحدِّث قائمة النتائج أثناء الكتابة (بحث فوري).
  void _onSearchChanged(String q) {
    setState(() => _searchResults = _match(q));
  }

  /// اختيار مواطن/عقار من قائمة النتائج: ينتقل إليه ويفتح بطاقته.
  void _selectResult(PropertyMapPoint p) {
    _searchFocus.unfocus();
    setState(() => _searchResults = const []);
    _js('window.sadaraFly && sadaraFly(${p.lng}, ${p.lat}, 18);');
    _showPointSheet(p);
  }

  void _runSearch(String q) {
    final hits = _match(q);
    if (hits.isEmpty) {
      _snack('لا نتيجة مطابقة على الخريطة', err: true);
      return;
    }
    _selectResult(hits.first);
  }

  // ─────────────────────────── المسار الملاحي ───────────────────────────

  Future<void> _routeTo(PropertyMapPoint p) async {
    final pos = await _currentPosition();
    if (pos == null) return;
    setState(() => _routing = true);
    await _js('window.sadaraMe && sadaraMe(${pos.longitude}, ${pos.latitude});');
    await _js('window.sadaraRoute && sadaraRoute(${pos.longitude}, ${pos.latitude}, ${p.lng}, ${p.lat});');
  }

  void _clearRoute() {
    setState(() => _route = null);
    _js('window.sadaraClearRoute && sadaraClearRoute();');
  }

  // ─────────────────────────── Bottom Sheet أصلية ───────────────────────────

  void _showPointSheet(PropertyMapPoint p) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _PointSheet(
          point: p,
          onDetails: () {
            Navigator.pop(context);
            _openProperty(p.id);
          },
          onCall:
              p.phone.trim().isEmpty ? null : () => _launch('tel:${p.phone.trim()}'),
          onWhatsapp:
              p.phone.trim().isEmpty ? null : () => _openWhatsapp(p.phone),
          onCopy: p.phone.trim().isEmpty ? null : () => _copyPhone(p.phone),
          onRoute: () {
            Navigator.pop(context);
            _routeTo(p);
          },
        ),
      ),
    );
  }

  Future<void> _openProperty(String id) async {
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PropertyDetailPage(propertyId: id)),
    );
  }

  Future<void> _launch(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      _snack('تعذّر فتح الرابط', err: true);
    }
  }

  /// يحوّل رقم هاتف عراقي إلى صيغة دولية (964) لرابط واتساب.
  String _waNumber(String phone) {
    var d = phone.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('00')) d = d.substring(2);
    if (d.startsWith('964')) return d;
    if (d.startsWith('0')) return '964${d.substring(1)}';
    if (d.length == 10 && d.startsWith('7')) return '964$d';
    return d;
  }

  void _openWhatsapp(String phone) {
    final n = _waNumber(phone);
    if (n.isEmpty) {
      _snack('رقم غير صالح', err: true);
      return;
    }
    _launch('https://wa.me/$n');
  }

  Future<void> _copyPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone.trim()));
    _snack('نُسخ الرقم: ${phone.trim()}');
  }

  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m,
          style:
              const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
      backgroundColor: err ? SdColors.danger : SdColors.success,
    ));
  }

  // ─────────────────────────── الواجهة ───────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: PropUi.pageBg,
        appBar: PropUi.appBar(
          'مواقع المستخدمين',
          leadingIcon: Icons.map_rounded,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const PropLoadingView(message: 'جارٍ تحميل المواقع…');
    if (_error != null) return PropErrorView(message: _error!, onRetry: _load);
    if (_points.isEmpty) {
      return PropEmptyView(
        message: _typeFilter == null
            ? 'لا توجد عقارات بإحداثيات موقع بعد — حدِّد موقع العقار عند إضافته '
                'بزرّ «موقعي» لتظهر هنا على الخريطة'
            : 'لا توجد عقارات بهذا النوع تملك موقعاً',
        icon: Icons.location_off_rounded,
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: _mapView()),
        if (!_viewReady || !_mapLoaded)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFFEAEFF5),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        _topControls(),
        _sideControls(),
        if (_route == null) _legend(),
        if (_routing) _routingBanner(),
        if (_route != null) _routePanel(_route!),
      ],
    );
  }

  Widget _mapView() {
    if (_isWindows) {
      return _windowsController == null
          ? const SizedBox.shrink()
          : windows_webview.Webview(_windowsController!);
    }
    return _mobileController == null
        ? const SizedBox.shrink()
        : mobile_webview.WebViewWidget(controller: _mobileController!);
  }

  // شريط علوي: بحث + فلاتر + مبدّل النمط (بتصميم زجاجي عائم).
  Widget _topControls() {
    return Positioned(
      top: 10,
      left: 10,
      right: 10,
      child: Column(
        children: [
          _glass(
            child: Row(
              children: [
                const SizedBox(width: 6),
                const Icon(Icons.search_rounded, color: SdColors.primary, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _search,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: _onSearchChanged,
                    onSubmitted: _runSearch,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'بحث: اسم / هاتف / رقم وطني',
                      hintStyle:
                          TextStyle(fontFamily: 'Cairo', color: SdColors.faint),
                    ),
                  ),
                ),
                if (_search.text.isNotEmpty)
                  InkWell(
                    onTap: () {
                      _search.clear();
                      setState(() => _searchResults = const []);
                    },
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close_rounded,
                          size: 18, color: SdColors.muted),
                    ),
                  )
                else ...[
                  Text('${_points.length}',
                      style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          color: SdColors.primary)),
                  const SizedBox(width: 4),
                  const Icon(Icons.place_rounded,
                      size: 16, color: SdColors.primary),
                  const SizedBox(width: 2),
                ],
              ],
            ),
          ),
          if (_searchFocus.hasFocus && _search.text.trim().isNotEmpty)
            _searchResultsCard(),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _pill('الكل', _typeFilter == null, () => _setType(null)),
                _pill('سكني', _typeFilter == 'Residential',
                    () => _setType('Residential')),
                _pill('تجاري', _typeFilter == 'Commercial',
                    () => _setType('Commercial')),
                const SizedBox(width: 8),
                _modePill('قمر صناعي', Icons.satellite_alt_rounded,
                    _mode == _MapMode.satellite, () => _setMode(_MapMode.satellite)),
                _modePill('شوارع', Icons.map_rounded, _mode == _MapMode.streets,
                    () => _setMode(_MapMode.streets)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // قائمة نتائج البحث الحيّة (اقتراحات) أسفل حقل البحث — اختَر مواطناً للانتقال إليه.
  Widget _searchResultsCard() {
    final results = _searchResults;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: results.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('لا نتيجة مطابقة',
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w600,
                        color: SdColors.muted)),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: results.length,
              separatorBuilder: (_, __) => Divider(
                  height: 1, color: SdColors.faint.withValues(alpha: 0.18)),
              itemBuilder: (_, i) {
                final p = results[i];
                final title = p.name.trim().isNotEmpty
                    ? p.name.trim()
                    : (p.npnDisplay.isNotEmpty ? p.npnDisplay : 'عقار');
                final sub = [
                  if (p.name.trim().isNotEmpty && p.npnDisplay.isNotEmpty)
                    p.npnDisplay,
                  if (p.phone.trim().isNotEmpty) p.phone.trim(),
                  if (p.area.trim().isNotEmpty) p.area.trim(),
                ].join(' · ');
                final tint = p.isCommercial
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF2563EB);
                return InkWell(
                  onTap: () => _selectResult(p),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: tint.withValues(alpha: 0.12),
                              shape: BoxShape.circle),
                          child: Icon(
                              p.isCommercial
                                  ? Icons.storefront_rounded
                                  : Icons.home_rounded,
                              size: 18,
                              color: tint),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: SdColors.ink)),
                              if (sub.isNotEmpty)
                                Text(sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11.5,
                                        color: SdColors.muted)),
                            ],
                          ),
                        ),
                        const Icon(Icons.north_east_rounded,
                            size: 16, color: SdColors.faint),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  // أزرار عائمة جانبية: تقريب/تبعيد + بوصلة + موقعي + توسيط + كثافة.
  Widget _sideControls() {
    return Positioned(
      bottom: 24,
      left: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _fabGroup([
            _fabItem(Icons.add_rounded, 'تقريب', _zoomIn),
            const Divider(height: 1, thickness: 1),
            _fabItem(Icons.remove_rounded, 'تبعيد', _zoomOut),
          ]),
          const SizedBox(height: 10),
          _fab(Icons.explore_rounded, 'الشمال', _resetNorth),
          const SizedBox(height: 10),
          _fab(Icons.my_location_rounded, 'موقعي', _goToMyLocation),
          const SizedBox(height: 10),
          _fab(Icons.fit_screen_rounded, 'توسيط الكل', _fitAll),
          const SizedBox(height: 10),
          _fab(Icons.local_fire_department_rounded, 'كثافة', _toggleHeatmap,
              active: _heatmap),
        ],
      ),
    );
  }

  Widget _legend() {
    return Positioned(
      bottom: 24,
      right: 12,
      child: _glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _legendRow(const Color(0xFF2563EB), 'سكني'),
            const SizedBox(height: 6),
            _legendRow(const Color(0xFFF59E0B), 'تجاري'),
          ],
        ),
      ),
    );
  }

  Widget _legendRow(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: SdColors.ink)),
        ],
      );

  Widget _routingBanner() {
    return Positioned(
      bottom: 24,
      right: 12,
      child: _glass(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('جارٍ حساب المسار…',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _routePanel(_RouteInfo r) {
    return Positioned(
      left: 10,
      right: 10,
      bottom: 14,
      child: _RoutePanel(route: r, onClose: _clearRoute),
    );
  }

  Widget _glass({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }

  Widget _fab(IconData icon, String tip, VoidCallback onTap,
      {bool active = false}) {
    return Tooltip(
      message: tip,
      child: Material(
        color: active ? SdColors.primary : Colors.white,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child:
                Icon(icon, size: 22, color: active ? Colors.white : SdColors.primary),
          ),
        ),
      ),
    );
  }

  Widget _fabGroup(List<Widget> children) {
    return Material(
      color: Colors.white,
      elevation: 4,
      borderRadius: BorderRadius.circular(23),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _fabItem(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
            width: 46,
            height: 44,
            child: Icon(icon, size: 22, color: SdColors.primary)),
      ),
    );
  }

  Widget _pill(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: _glass(
        padding: EdgeInsets.zero,
        child: Material(
          color: selected ? SdColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: selected ? Colors.white : SdColors.muted)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modePill(
      String label, IconData icon, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: _glass(
        padding: EdgeInsets.zero,
        child: Material(
          color: selected ? SdColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 16, color: selected ? Colors.white : SdColors.muted),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: selected ? Colors.white : SdColors.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────── بناء HTML للخريطة ───────────────────────────

  /// يبني مصفوفة GeoJSON المختصرة (نقاط العقارات) كنصّ JSON — تُستخدم في بناء
  /// الصفحة أولاً وفي التحديث الحيّ الصامت لاحقاً.
  String _featuresJson(List<PropertyMapPoint> points) {
    final features = points
        .where((p) => p.lat != 0 || p.lng != 0)
        .map((p) => {
              'id': p.id,
              'lng': p.lng,
              'lat': p.lat,
              'commercial': p.isCommercial,
            })
        .toList();
    return jsonEncode(features);
  }

  String _buildMapHtml(List<PropertyMapPoint> points) {
    final data = _featuresJson(points);

    return '''<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no" />
<link href="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css" rel="stylesheet" />
<script src="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"></script>
<style>
  html, body, #map { margin:0; padding:0; height:100%; width:100%; background:#EAEFF5; }
  .maplibregl-ctrl-top-left { margin-top:92px; }
  #err { position:absolute; inset:0; display:none; align-items:center; justify-content:center;
    text-align:center; padding:24px; color:#b91c1c; font-weight:700;
    font-family:-apple-system,"Segoe UI",Tahoma,sans-serif; }
</style>
</head>
<body>
<div id="map"></div>
<div id="err">تعذّر تشغيل محرّك الخريطة — تحقّق من الاتصال بالإنترنت</div>
<script>
  var RAW = $data;
  var RES = '#2563EB', COM = '#F59E0B';
  var STREETS = 'https://tiles.openfreemap.org/styles/liberty';
  var COLOR = ['case',['get','commercial'],COM,RES];
  var lastRoute = null, meLngLat = null;

  function post(obj){
    try {
      var s = JSON.stringify(obj);
      if (window.chrome && window.chrome.webview) { window.chrome.webview.postMessage(s); }
      else if (window.SadaraMap && window.SadaraMap.postMessage) { window.SadaraMap.postMessage(s); }
    } catch(e){}
  }

  function fc(){ return { type:'FeatureCollection', features: RAW.map(function(p){
    return { type:'Feature', geometry:{ type:'Point', coordinates:[p.lng,p.lat] },
      properties:{ id:p.id, commercial:!!p.commercial } };
  })}; }
  function bounds(){ var b=new maplibregl.LngLatBounds(); RAW.forEach(function(p){ b.extend([p.lng,p.lat]); }); return b; }

  // نمط القمر الصناعي الهجين: صور Esri + طرق وتسميات OpenFreeMap فوقها.
  function satelliteStyle(){
    return {
      version:8,
      glyphs:'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
      sources:{
        sat:{ type:'raster', tileSize:256,
          tiles:['https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'],
          attribution:'© Esri, Maxar, Earthstar Geographics' },
        ofm:{ type:'vector', url:'https://tiles.openfreemap.org/planet' }
      },
      layers:[
        { id:'sat', type:'raster', source:'sat' },
        { id:'roads', type:'line', source:'ofm', 'source-layer':'transportation',
          paint:{ 'line-color':'#ffffff', 'line-opacity':0.45,
            'line-width':['interpolate',['linear'],['zoom'],8,0.4,16,2.4] } },
        { id:'road-labels', type:'symbol', source:'ofm', 'source-layer':'transportation_name',
          layout:{ 'text-field':['get','name'], 'text-size':11, 'symbol-placement':'line' },
          paint:{ 'text-color':'#ffffff', 'text-halo-color':'#000000', 'text-halo-width':1.2 } },
        { id:'place-labels', type:'symbol', source:'ofm', 'source-layer':'place',
          layout:{ 'text-field':['get','name'], 'text-size':13 },
          paint:{ 'text-color':'#ffffff', 'text-halo-color':'#000000', 'text-halo-width':1.4 } }
      ]
    };
  }

  var map, heatOn=false;
  try {
    map = new maplibregl.Map({ container:'map', style:satelliteStyle(),
      center:[44.0,33.3], zoom:5, pitch:0, bearing:0, maxPitch:0,
      attributionControl:{compact:true} });
  } catch(e){ document.getElementById('err').style.display='flex'; }

  function addData(){
    if (map.getSource('pts')) return;
    map.addSource('pts', { type:'geojson', data: fc(), cluster:true, clusterRadius:48, clusterMaxZoom:14 });

    map.addLayer({ id:'heat', type:'heatmap', source:'pts', layout:{visibility:'none'},
      paint:{ 'heatmap-radius':['interpolate',['linear'],['zoom'],5,8,14,40],
        'heatmap-opacity':0.8,
        'heatmap-color':['interpolate',['linear'],['heatmap-density'],
          0,'rgba(37,99,235,0)',0.3,'#60a5fa',0.6,'#f59e0b',1,'#ef4444'] } });

    map.addLayer({ id:'clusters', type:'circle', source:'pts', filter:['has','point_count'],
      paint:{ 'circle-color':'#1d4ed8', 'circle-opacity':0.92,
        'circle-radius':['step',['get','point_count'],16,25,22,100,30],
        'circle-stroke-width':2, 'circle-stroke-color':'#ffffff' } });
    map.addLayer({ id:'cluster-count', type:'symbol', source:'pts', filter:['has','point_count'],
      layout:{ 'text-field':['get','point_count_abbreviated'], 'text-size':13 },
      paint:{ 'text-color':'#ffffff' } });

    map.addLayer({ id:'dot-glow', type:'circle', source:'pts', filter:['!',['has','point_count']],
      paint:{ 'circle-color':COLOR, 'circle-opacity':0.22, 'circle-radius':16 } });
    map.addLayer({ id:'dots', type:'circle', source:'pts', filter:['!',['has','point_count']],
      paint:{ 'circle-color':COLOR, 'circle-radius':8,
        'circle-stroke-width':3, 'circle-stroke-color':'#ffffff' } });

    map.on('click','clusters', function(e){
      var f=map.queryRenderedFeatures(e.point,{layers:['clusters']});
      var cid=f[0].properties.cluster_id;
      map.getSource('pts').getClusterExpansionZoom(cid).then(function(z){
        map.easeTo({ center:f[0].geometry.coordinates, zoom:z });
      }).catch(function(){});
    });
    function sel(e){ post({action:'select', id:String(e.features[0].properties.id)}); }
    map.on('click','dots', sel);
    ['dots','clusters'].forEach(function(l){
      map.on('mouseenter',l,function(){ map.getCanvas().style.cursor='pointer'; });
      map.on('mouseleave',l,function(){ map.getCanvas().style.cursor=''; });
    });

    if (lastRoute) drawRoute(lastRoute);
    if (meLngLat) drawMe(meLngLat);
  }

  function fitView(){
    if (RAW.length===1){ map.jumpTo({ center:[RAW[0].lng,RAW[0].lat], zoom:16 }); }
    else if (RAW.length>1){ try{ map.fitBounds(bounds(),{ padding:80, maxZoom:16 }); }catch(e){} }
  }

  function drawRoute(geo){
    lastRoute = geo;
    if (map.getSource('route')){ map.getSource('route').setData(geo); return; }
    map.addSource('route',{ type:'geojson', data:geo });
    map.addLayer({ id:'route-cap', type:'line', source:'route',
      layout:{'line-cap':'round','line-join':'round'},
      paint:{'line-color':'#ffffff','line-width':9,'line-opacity':0.9} });
    map.addLayer({ id:'route', type:'line', source:'route',
      layout:{'line-cap':'round','line-join':'round'},
      paint:{'line-color':'#2563EB','line-width':5} });
  }
  function drawMe(c){
    meLngLat = c;
    var d={ type:'FeatureCollection', features:[{ type:'Feature', geometry:{type:'Point',coordinates:c}, properties:{} }] };
    if (map.getSource('me')){ map.getSource('me').setData(d); return; }
    map.addSource('me',{ type:'geojson', data:d });
    map.addLayer({ id:'me-glow', type:'circle', source:'me',
      paint:{'circle-color':'#10b981','circle-opacity':0.25,'circle-radius':18} });
    map.addLayer({ id:'me', type:'circle', source:'me',
      paint:{'circle-color':'#10b981','circle-radius':7,'circle-stroke-width':3,'circle-stroke-color':'#ffffff'} });
  }

  if (map){
    map.addControl(new maplibregl.ScaleControl(), 'top-left');
    map.on('load', function(){ addData(); fitView(); post({action:'ready'}); });

    window.sadaraSetMode = function(mode){
      var target = (mode==='satellite') ? satelliteStyle() : STREETS;
      map.setStyle(target);
      map.once('styledata', function(){ addData(); if(heatOn) applyHeat(true); });
    };
    function applyHeat(on){
      heatOn=on;
      if(!map.getLayer('heat')) return;
      map.setLayoutProperty('heat','visibility', on?'visible':'none');
      ['dots','dot-glow','clusters','cluster-count'].forEach(function(l){
        if(map.getLayer(l)) map.setLayoutProperty(l,'visibility', on?'none':'visible');
      });
    }
    window.sadaraToggleHeat = function(on){ applyHeat(!!on); };
    window.sadaraFit = function(){ fitView(); };
    window.sadaraFly = function(lng,lat,z){ map.flyTo({ center:[lng,lat], zoom:z||16, essential:true }); };
    window.sadaraZoom = function(d){
      var z = map.getZoom() + (d>0 ? 1.1 : -1.1);
      map.easeTo({ zoom: Math.max(2, Math.min(20, z)), duration:280 });
    };
    window.sadaraNorth = function(){ map.easeTo({ bearing:0 }); };
    window.sadaraMe = function(lng,lat){ drawMe([lng,lat]); };
    // تحديث حيّ صامت: يستبدل النقاط ويحدّث المصدر دون تغيير منظور المستخدم.
    window.sadaraUpdate = function(features){
      try {
        RAW = features || [];
        if (map.getSource('pts')) map.getSource('pts').setData(fc());
      } catch(e){}
    };
    window.sadaraClearRoute = function(){
      lastRoute=null;
      if (map.getLayer('route')){ map.removeLayer('route'); }
      if (map.getLayer('route-cap')){ map.removeLayer('route-cap'); }
      if (map.getSource('route')){ map.removeSource('route'); }
    };
    window.sadaraRoute = function(fx,fy,tx,ty){
      var url='https://router.project-osrm.org/route/v1/driving/'+fx+','+fy+';'+tx+','+ty+'?overview=full&geometries=geojson&steps=true';
      fetch(url).then(function(r){ return r.json(); }).then(function(j){
        if(!j.routes || !j.routes.length){ post({action:'routeError'}); return; }
        var rt=j.routes[0];
        drawRoute(rt.geometry);
        try{ var b=new maplibregl.LngLatBounds(); rt.geometry.coordinates.forEach(function(c){ b.extend(c); });
          map.fitBounds(b,{ padding:{top:120,bottom:220,left:60,right:60} }); }catch(e){}
        var steps=[];
        (rt.legs||[]).forEach(function(leg){ (leg.steps||[]).forEach(function(s){
          steps.push({ name:(s.name||''),
            type:(s.maneuver&&s.maneuver.type)||'',
            modifier:(s.maneuver&&s.maneuver.modifier)||'',
            dist:s.distance||0 }); }); });
        post({ action:'route', distance:rt.distance, duration:rt.duration, steps:steps });
      }).catch(function(){ post({action:'routeError'}); });
    };
  }
</script>
</body>
</html>''';
  }
}

// ─────────────────────────── نماذج/مكوّنات مساعدة ───────────────────────────

/// ملخّص مسار ملاحي (مسافة/زمن + خطوات).
class _RouteInfo {
  final double distanceMeters;
  final double durationSeconds;
  final List<_RouteStep> steps;

  const _RouteInfo(this.distanceMeters, this.durationSeconds, this.steps);

  factory _RouteInfo.fromJson(Map<String, dynamic> m) {
    double d(dynamic v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
    final raw = (m['steps'] as List?) ?? const [];
    return _RouteInfo(
      d(m['distance']),
      d(m['duration']),
      raw
          .whereType<Map>()
          .map((e) => _RouteStep.fromJson(e.cast<String, dynamic>()))
          .where((s) => s.text.isNotEmpty)
          .toList(),
    );
  }

  String get distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} كم'
      : '${distanceMeters.round()} م';

  String get durationLabel {
    final min = (durationSeconds / 60).round();
    if (min < 60) return '$min دقيقة';
    final h = min ~/ 60, m = min % 60;
    return m == 0 ? '$h ساعة' : '$h ساعة $m د';
  }
}

class _RouteStep {
  final String text;
  final IconData icon;
  final double distanceMeters;

  const _RouteStep(this.text, this.icon, this.distanceMeters);

  factory _RouteStep.fromJson(Map<String, dynamic> j) {
    final type = (j['type'] ?? '').toString();
    final mod = (j['modifier'] ?? '').toString();
    final name = (j['name'] ?? '').toString().trim();
    final dist = (j['dist'] is num) ? (j['dist'] as num).toDouble() : 0.0;
    final (label, icon) = _describe(type, mod);
    final text = name.isEmpty ? label : '$label — $name';
    return _RouteStep(text, icon, dist);
  }

  static (String, IconData) _describe(String type, String mod) {
    switch (type) {
      case 'depart':
        return ('انطلق', Icons.trip_origin_rounded);
      case 'arrive':
        return ('الوصول إلى الوجهة', Icons.flag_rounded);
      case 'roundabout':
      case 'rotary':
        return ('ادخل الدوّار', Icons.roundabout_right_rounded);
      case 'merge':
        return ('اندمج', Icons.merge_rounded);
      case 'fork':
        return ('عند المفترق', Icons.call_split_rounded);
      case 'continue':
        return ('تابع مستقيماً', Icons.straight_rounded);
    }
    // turn / end of road / new name …
    switch (mod) {
      case 'left':
      case 'slight left':
      case 'sharp left':
        return ('انعطف يساراً', Icons.turn_left_rounded);
      case 'right':
      case 'slight right':
      case 'sharp right':
        return ('انعطف يميناً', Icons.turn_right_rounded);
      case 'straight':
        return ('تابع مستقيماً', Icons.straight_rounded);
      case 'uturn':
        return ('استدر عائداً', Icons.u_turn_left_rounded);
    }
    return ('تابع', Icons.navigation_rounded);
  }

  String get distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} كم'
      : '${distanceMeters.round()} م';
}

/// لوحة المسار الملاحي (ملخّص + خطوات قابلة للطيّ) تظهر أسفل الخريطة.
class _RoutePanel extends StatefulWidget {
  final _RouteInfo route;
  final VoidCallback onClose;
  const _RoutePanel({required this.route, required this.onClose});

  @override
  State<_RoutePanel> createState() => _RoutePanelState();
}

class _RoutePanelState extends State<_RoutePanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 10,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_rounded, color: SdColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Text(r.durationLabel,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: SdColors.ink)),
                      const SizedBox(width: 8),
                      Text('· ${r.distanceLabel}',
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: SdColors.muted)),
                    ],
                  ),
                ),
                if (r.steps.isNotEmpty)
                  IconButton(
                    tooltip: _expanded ? 'إخفاء الخطوات' : 'عرض الخطوات',
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(_expanded
                        ? Icons.expand_more_rounded
                        : Icons.list_rounded),
                  ),
                IconButton(
                  tooltip: 'مسح المسار',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, color: SdColors.danger),
                ),
              ],
            ),
            if (_expanded && r.steps.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(top: 6),
                  itemCount: r.steps.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: SdColors.faint.withValues(alpha: 0.2)),
                  itemBuilder: (_, i) {
                    final s = r.steps[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Icon(s.icon, size: 20, color: SdColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(s.text,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                          ),
                          if (s.distanceMeters > 0)
                            Text(s.distanceLabel,
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11.5,
                                    color: SdColors.muted)),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ورقة سفلية أصلية لتفاصيل موقع عقار + إجراءات (تفاصيل/مسار/اتصال).
class _PointSheet extends StatelessWidget {
  final PropertyMapPoint point;
  final VoidCallback onDetails;
  final VoidCallback? onCall;
  final VoidCallback? onWhatsapp;
  final VoidCallback? onCopy;
  final VoidCallback onRoute;

  const _PointSheet({
    required this.point,
    required this.onDetails,
    required this.onCall,
    required this.onWhatsapp,
    required this.onCopy,
    required this.onRoute,
  });

  @override
  Widget build(BuildContext context) {
    final p = point;
    final tint =
        p.isCommercial ? const Color(0xFFF59E0B) : const Color(0xFF2563EB);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: SdColors.faint.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(
                    p.isCommercial
                        ? Icons.storefront_rounded
                        : Icons.home_rounded,
                    color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.npnDisplay.isNotEmpty ? p.npnDisplay : 'عقار',
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w800,
                            fontSize: 16)),
                    if (p.area.isNotEmpty)
                      Text(p.area,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12.5,
                              color: SdColors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (p.name.isNotEmpty) _row(Icons.person_rounded, p.name),
          if (p.phone.isNotEmpty)
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(8),
              child: _row(Icons.phone_rounded, p.phone,
                  ltr: true,
                  color: SdColors.success,
                  trailing: onCopy == null ? null : Icons.copy_rounded),
            ),
          if (p.serviceTypes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in p.serviceTypes)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                        color: SdColors.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(serviceTypeLabelOf(t),
                        style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: SdColors.primary)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onRoute,
              style: FilledButton.styleFrom(
                  backgroundColor: SdColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: const Text('المسار من موقعي',
                  style:
                      TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _action(Icons.open_in_new_rounded, 'تفاصيل', onDetails, SdColors.info),
              if (onWhatsapp != null)
                _action(Icons.chat_rounded, 'واتساب', onWhatsapp!,
                    const Color(0xFF25D366)),
              if (onCall != null)
                _action(Icons.call_rounded, 'اتصال', onCall!, SdColors.success),
              if (onCopy != null)
                _action(Icons.copy_rounded, 'نسخ', onCopy!, SdColors.muted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text,
      {bool ltr = false, Color color = SdColors.ink, IconData? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                textDirection: ltr ? TextDirection.ltr : null,
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5)),
          ),
          if (trailing != null)
            Icon(trailing, size: 15, color: SdColors.faint),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, Color c) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration:
                  BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: c),
            ),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: c)),
          ],
        ),
      ),
    );
  }
}
