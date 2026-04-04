import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api/api_client.dart';
import '../permissions/permission_manager.dart';
import 'employee_tracking_report_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';
import 'package:signalr_netcore/signalr_client.dart';

class TrackUsersMapPage extends StatefulWidget {
  const TrackUsersMapPage({super.key});

  @override
  State<TrackUsersMapPage> createState() => _TrackUsersMapPageState();
}

/// بيانات محافظة: مركز + زوم + حدود
class _ProvinceData {
  final double lat, lng;
  final double zoom;
  final double swLat, swLng, neLat, neLng;
  const _ProvinceData(this.lat, this.lng, this.zoom, this.swLat, this.swLng, this.neLat, this.neLng);

  LatLng get center => LatLng(lat, lng);
  LatLngBounds get bounds => LatLngBounds(LatLng(swLat, swLng), LatLng(neLat, neLng));
}

class _TrackUsersMapPageState extends State<TrackUsersMapPage>
    with TickerProviderStateMixin {
  // يستخدم Sadara API بدل Google Sheets

  final MapController _mapController = MapController();
  final Map<String, List<LatLng>> _userPaths = {};
  final Set<String> _hiddenPaths = {};
  String _searchQuery = "";

  List<Marker> _markers = [];
  Map<String, Marker> _markersByUser = {}; // لربط كل ماركر باسم المستخدم
  List<dynamic> _rawData = [];
  bool _loading = true;
  Timer? _timer;
  MbTilesTileProvider? _mbtilesProvider;
  bool _isPanelExpanded = false;

  // SignalR — بث مباشر
  HubConnection? _hubConnection;
  bool _isSignalRConnected = false;

  // تنبيهات
  int _staleCount = 0;
  int _stoppedCount = 0;
  List<dynamic> _alerts = [];

  // ═══ محافظات العراق ═══
  static const _prefKey = 'tracking_selected_province';
  String _selectedProvince = 'بغداد';

  static const Map<String, _ProvinceData> _provinces = {
    'بغداد':     _ProvinceData(33.3153, 44.3661, 11, 32.95, 44.10, 33.65, 44.65),
    'البصرة':    _ProvinceData(30.5085, 47.7834, 10, 29.80, 46.80, 31.40, 48.60),
    'نينوى':     _ProvinceData(36.3350, 43.1189, 10, 35.10, 41.70, 37.35, 44.30),
    'أربيل':     _ProvinceData(36.1912, 44.0089, 10, 35.60, 43.40, 36.90, 44.90),
    'النجف':     _ProvinceData(32.0000, 44.3364, 9,  30.50, 42.50, 33.00, 45.50),
    'كربلاء':    _ProvinceData(32.6160, 44.0243, 11, 32.10, 43.40, 33.10, 44.60),
    'ذي قار':    _ProvinceData(31.0500, 46.2500, 10, 30.40, 45.40, 31.90, 47.20),
    'بابل':      _ProvinceData(32.4681, 44.4213, 11, 32.00, 44.00, 33.00, 45.00),
    'ديالى':     _ProvinceData(33.7700, 45.0000, 10, 33.10, 44.30, 34.80, 46.00),
    'الأنبار':   _ProvinceData(33.4260, 43.3000, 8,  31.00, 38.70, 35.20, 44.50),
    'واسط':      _ProvinceData(32.5000, 45.7500, 10, 31.80, 44.90, 33.40, 46.60),
    'ميسان':     _ProvinceData(31.8500, 47.0300, 10, 31.10, 46.10, 32.70, 47.80),
    'كركوك':     _ProvinceData(35.4681, 44.3922, 10, 34.60, 43.50, 36.00, 45.30),
    'صلاح الدين': _ProvinceData(34.5600, 43.6800, 9, 33.60, 42.60, 35.50, 45.00),
    'المثنى':    _ProvinceData(31.3100, 45.2800, 9,  30.00, 44.00, 32.10, 46.40),
    'القادسية':  _ProvinceData(31.9800, 44.9300, 10, 31.40, 44.30, 32.50, 45.60),
    'دهوك':      _ProvinceData(36.8600, 43.0000, 10, 36.40, 42.30, 37.40, 44.20),
    'السليمانية': _ProvinceData(35.5600, 45.4400, 10, 34.70, 44.60, 36.40, 46.40),
  };

  static const LatLng _defaultCenter = LatLng(33.3573338, 44.4414648);

  // الألوان
  final Color _primaryColor = const Color(0xFF0F172A);
  final Color _accentColor = const Color(0xFF38BDF8);
  final Color _surfaceColor = const Color(0xFFF8FAFC);
  final Color _cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _loadSavedProvince();
    _initOfflineMap();
    _fetchAndUpdateMarkers();
    _connectSignalR();
    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _fetchAndUpdateMarkers();
    });
  }

  Future<void> _loadSavedProvince() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && _provinces.containsKey(saved)) {
      setState(() => _selectedProvince = saved);
      final p = _provinces[saved]!;
      _mapController.move(p.center, p.zoom);
    }
  }

  Future<void> _selectProvince(String name) async {
    final p = _provinces[name];
    if (p == null) return;
    setState(() => _selectedProvince = name);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: p.bounds, padding: const EdgeInsets.all(20)),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, name);
  }

  /// الاتصال بـ SignalR Hub للبث المباشر
  Future<void> _connectSignalR() async {
    try {
      final apiKey = 'sadara-internal-2024-secure-key';
      final hubUrl = 'https://api.ramzalsadara.tech/hubs/location?apiKey=$apiKey';

      _hubConnection = HubConnectionBuilder()
          .withUrl(hubUrl)
          .withAutomaticReconnect()
          .build();

      // ═══ استلام تحديث موقع فوري ═══
      _hubConnection!.on('LocationUpdated', (args) {
        if (!mounted || args == null || args.isEmpty) return;
        final data = args[0] as Map<String, dynamic>?;
        if (data == null) return;

        final userId = data['userId']?.toString() ?? '';
        if (userId.isEmpty) return;

        final isFake = data['isFake'] == true;

        // تحديث النقطة في _rawData
        final idx = _rawData.indexWhere((e) => e['اسم المستخدم'] == userId);
        final mapped = {
          'اسم المستخدم': userId,
          'القسم': data['department'] ?? '',
          'المركز': '',
          'رقم الهاتف': '',
          'lat': data['lat'],
          'lng': data['lng'],
          'active': true,
          'last update': data['timestamp'] ?? '',
          'isFake': isFake,
        };

        if (idx >= 0) {
          _rawData[idx] = mapped;
        } else {
          _rawData.add(mapped);
        }
        _applyFilters();

        // 🚫 تنبيه فوري عند كشف فيك لوكيشن
        if (isFake && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🚫 تحذير: $userId يستخدم موقع وهمي!'),
              backgroundColor: Colors.red.shade700,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'عرض',
                textColor: Colors.white,
                onPressed: () {
                  final lat = double.tryParse(data['lat'].toString());
                  final lng = double.tryParse(data['lng'].toString());
                  if (lat != null && lng != null) {
                    _mapController.move(LatLng(lat, lng), 15);
                  }
                },
              ),
            ),
          );
        }
      });

      // ═══ موظف أوقف المشاركة ═══
      _hubConnection!.on('UserStopped', (args) {
        if (!mounted || args == null || args.isEmpty) return;
        final userId = args[0]?.toString() ?? '';
        _rawData.removeWhere((e) => e['اسم المستخدم'] == userId);
        _applyFilters();
      });

      _hubConnection!.onclose(({error}) {
        if (mounted) setState(() => _isSignalRConnected = false);
        debugPrint('🔴 [SignalR] Disconnected: $error');
      });

      _hubConnection!.onreconnected(({connectionId}) {
        if (mounted) setState(() => _isSignalRConnected = true);
        debugPrint('🟢 [SignalR] Reconnected: $connectionId');
        _fetchAndUpdateMarkers(); // تحديث كامل بعد إعادة الاتصال
      });

      await _hubConnection!.start();
      if (mounted) setState(() => _isSignalRConnected = true);
      debugPrint('🟢 [SignalR] Connected');
    } catch (e) {
      debugPrint('⚠️ [SignalR] Connection failed: $e — falling back to polling');
      // Polling يعمل كـ fallback تلقائياً
    }
  }

  Future<void> _initOfflineMap() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final mbtilesFile = File('${appDir.path}/iraq.mbtiles');

      if (!await mbtilesFile.exists()) {
        try {
          final data = await rootBundle.load('assets/maps/iraq.mbtiles');
          await mbtilesFile.writeAsBytes(data.buffer.asUint8List(),
              flush: true);
        } catch (e) {
          debugPrint('Offline map file not found in assets');
          return;
        }
      }

      final provider = MbTilesTileProvider.fromPath(path: mbtilesFile.path);
      setState(() {
        _mbtilesProvider = provider;
      });
    } catch (e) {
      debugPrint("Offline map initialization error: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _hubConnection?.stop();
    _mbtilesProvider?.dispose();
    super.dispose();
  }

  Future<void> _fetchAndUpdateMarkers() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final response = await ApiClient.instance.get(
        '/employee-location/active',
        (data) => data,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        final rawData = response.data;
        final List<dynamic> data = rawData is List
            ? rawData
            : (rawData is Map ? (rawData['data'] as List?) ?? [] : []);
        // تحويل من camelCase API إلى Arabic keys (للتوافق مع الكود الحالي)
        final List<Map<String, dynamic>> mapped = [];
        for (final item in data) {
          if (item is! Map<String, dynamic>) continue;
          mapped.add({
            'اسم المستخدم': item['userId'] ?? '',
            'القسم': item['department'] ?? '',
            'المركز': item['center'] ?? '',
            'رقم الهاتف': item['phone'] ?? '',
            'lat': item['lat'],
            'lng': item['lng'],
            'active': item['active'] ?? false,
            'last update': item['lastUpdate'] ?? '',
          });
        }
        _rawData = mapped;
        _applyFilters();
      }
    } catch (e) {
      debugPrint("Error fetching positions: $e");
    }

    // جلب التنبيهات
    try {
      final alertResponse = await ApiClient.instance.get(
        '/employee-location/alerts?staleMinutes=5',
        (data) => data,
        useInternalKey: true,
      );
      if (alertResponse.isSuccess && alertResponse.data != null) {
        final d = alertResponse.data;
        if (d is Map) {
          _staleCount = d['staleCount'] ?? 0;
          _stoppedCount = d['stoppedCount'] ?? 0;
          _alerts = (d['data'] as List?) ?? [];
        }
      }
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  void _applyFilters() {
    final Map<String, Marker> newMarkersByUser = {};

    for (var item in _rawData) {
      final userName = item["اسم المستخدم"] ?? 'غير معروف';
      final department = item["القسم"] ?? '';

      if (_searchQuery.isNotEmpty &&
          !userName.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !department.toLowerCase().contains(_searchQuery.toLowerCase())) {
        continue;
      }

      final isActive = _checkIsActive(item["active"]);

      if (isActive && _isValidCoord(item["lat"], item["lng"])) {
        double lat = double.parse(item["lat"].toString());
        double lng = double.parse(item["lng"].toString());
        final pos = LatLng(lat, lng);

        _updateUserPath(userName, pos);

        final markerSize = _isMobile ? 80.0 : 120.0;
        newMarkersByUser[userName] = Marker(
          point: pos,
          width: markerSize,
          height: markerSize,
          child: _buildProfessionalMarker(userName, item),
        );
      }
    }
    setState(() {
      _markersByUser = newMarkersByUser;
      _markers = newMarkersByUser.entries
          .where((e) => !_hiddenPaths.contains(e.key))
          .map((e) => e.value)
          .toList();
    });
  }

  bool _checkIsActive(dynamic val) {
    if (val == null) return false;
    final s = val.toString().toLowerCase();
    return s == "true" || s == "1" || s == "active";
  }

  bool _isValidCoord(dynamic lat, dynamic lng) {
    if (lat == null || lng == null) return false;
    double? la = double.tryParse(lat.toString());
    double? ln = double.tryParse(lng.toString());
    return la != null && ln != null && la != 0 && ln != 0;
  }

  void _updateUserPath(String userName, LatLng pos) {
    if (!_userPaths.containsKey(userName)) {
      _userPaths[userName] = [];
    }
    if (_userPaths[userName]!.isEmpty || _userPaths[userName]!.last != pos) {
      _userPaths[userName]!.add(pos);
      if (_userPaths[userName]!.length > 100) {
        _userPaths[userName]!.removeAt(0);
      }
    }
  }

  Widget _buildProfessionalMarker(String name, Map<String, dynamic> data) {
    final isFake = data['isFake'] == true;
    final markerColor = isFake ? Colors.red : _primaryColor;
    final pinColor = isFake ? Colors.red : _accentColor;

    return GestureDetector(
      onTap: () => _showUserDetailsDialog(context, data),
      child: Column(
        children: [
          // فقاعة الاسم الأنيقة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: markerColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: pinColor.withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isFake) const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Text('🚫', style: TextStyle(fontSize: 12)),
                ),
                Text(
                  name,
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // العلامة النبضية
          _PulsingPin(color: pinColor),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceColor,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // الخريطة
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: (_provinces[_selectedProvince]?.center) ?? _defaultCenter,
              initialZoom: (_provinces[_selectedProvince]?.zoom) ?? 12,
              minZoom: 5,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all, // تفعيل كل التفاعلات (زوم + سحب + دوران)
              ),
            ),
            children: [
              // خريطة بطابع أزرق داكن — CartoDB Dark Matter
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.alsadara.app',
                tileProvider: _mbtilesProvider,
                maxZoom: 19,
              ),
              PolylineLayer(
                polylines: _userPaths.entries
                    .where((e) => !_hiddenPaths.contains(e.key))
                    .map((entry) {
                  return Polyline(
                    points: entry.value,
                    color: _accentColor.withOpacity(0.6),
                    strokeWidth: 3,
                    strokeCap: StrokeCap.round,
                  );
                }).toList(),
              ),
              MarkerLayer(markers: _markers),
            ],
          ),

          // لوحة الفنيين الجانبية العائمة
          _buildFloatingTechnicianPanel(),

          // مؤشر التحميل الصغير
          if (_loading)
            Positioned(
              bottom: 24,
              left: 24,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _primaryColor.withOpacity(0.8),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 600;

  /// هل المستخدم مدير أو مدير شركة؟ (يملك delete على tracking أو view على accounting)
  bool get _isManagerOrAbove =>
      PermissionManager.instance.canDelete('tracking') ||
      PermissionManager.instance.canView('accounting');

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: _primaryColor,
      toolbarHeight: _isMobile ? 46 : kToolbarHeight,
      title: Text(
        _isMobile ? "تتبع الفنيين" : "تتبع الفنيين - نظام الذكاء المكاني",
        style: GoogleFonts.cairo(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontSize: _isMobile ? 15 : 20,
        ),
      ),
      actions: [
        // ═══ اختيار المحافظة ═══
        SizedBox(
          width: _isMobile ? 95 : 130,
          height: 32,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedProvince,
                dropdownColor: _primaryColor,
                isExpanded: true,
                icon: Icon(Icons.arrow_drop_down, color: Colors.white, size: _isMobile ? 14 : 18),
                style: GoogleFonts.cairo(color: Colors.white, fontSize: _isMobile ? 10 : 13),
                items: _provinces.keys.map((name) => DropdownMenuItem(
                  value: name,
                  child: Text(name, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) { if (v != null) _selectProvince(v); },
              ),
            ),
          ),
        ),
        const SizedBox(width: 2),
        // مؤشر حالة البث — نقطة صغيرة فقط
        Tooltip(
          message: _isSignalRConnected ? 'بث مباشر متصل' : 'تحديث تلقائي',
          child: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isSignalRConnected ? Colors.greenAccent : Colors.orange,
            ),
          ),
        ),
        if (_staleCount + _stoppedCount > 0)
          IconButton(
            icon: Badge(
              label: Text('${_staleCount + _stoppedCount}'),
              backgroundColor: Colors.red,
              child: Icon(Icons.warning_amber_rounded, color: Colors.orange, size: _isMobile ? 20 : 24),
            ),
            onPressed: _showAlerts,
            tooltip: "تنبيهات",
          ),
        // 🗑️ مسح بيانات التتبع — للمدير فقط
        if (_isManagerOrAbove)
          IconButton(
            icon: Icon(Icons.delete_sweep, color: Colors.redAccent, size: _isMobile ? 20 : 24),
            tooltip: 'مسح بيانات التتبع القديمة',
            onPressed: _showPurgeDialog,
          ),
        IconButton(
          icon: Icon(Icons.analytics_outlined, color: Colors.white, size: _isMobile ? 20 : 24),
          onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EmployeeTrackingReportPage())),
          tooltip: "تقارير التتبع",
        ),
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: _accentColor, size: _isMobile ? 20 : 24),
          onPressed: _fetchAndUpdateMarkers,
          tooltip: "تحديث البيانات",
        ),
        SizedBox(width: _isMobile ? 2 : 8),
      ],
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }

  void _showPurgeDialog() {
    // 0 = مسح الكل
    int days = 0;
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('مسح بيانات التتبع'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('اختر نطاق المسح:'),
                const SizedBox(height: 16),
                DropdownButton<int>(
                  value: days,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('🗑️ مسح جميع البيانات')),
                    DropdownMenuItem(value: 7, child: Text('أقدم من 7 أيام')),
                    DropdownMenuItem(value: 14, child: Text('أقدم من 14 يوم')),
                    DropdownMenuItem(value: 30, child: Text('أقدم من 30 يوم')),
                    DropdownMenuItem(value: 60, child: Text('أقدم من 60 يوم')),
                  ],
                  onChanged: (v) => setDialogState(() => days = v ?? 0),
                ),
                const SizedBox(height: 8),
                if (days == 0)
                  Text('⚠️ سيتم حذف جميع سجلات التتبع والمواقع الحالية!',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold))
                else
                  Text('⚠️ هذا الإجراء لا يمكن التراجع عنه',
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                icon: const Icon(Icons.delete_forever, color: Colors.white),
                label: Text(days == 0 ? 'مسح الكل' : 'مسح',
                    style: const TextStyle(color: Colors.white)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  try {
                    final role = 'manager';
                    final endpoint = days == 0
                        ? '/employee-location/purge?all=true'
                        : '/employee-location/purge?olderThanDays=$days';
                    final response = await ApiClient.instance.deleteRaw(
                      endpoint,
                      useInternalKey: true,
                      extraHeaders: {'X-Caller-Role': role},
                    );
                    if (response != null && response['success'] == true) {
                      _fetchAndUpdateMarkers(); // تحديث القائمة بعد المسح
                      scaffoldMessenger.showSnackBar(SnackBar(
                        content: Text('✅ تم حذف ${response['deletedCount']} سجل'),
                        backgroundColor: Colors.green,
                      ));
                    } else {
                      scaffoldMessenger.showSnackBar(SnackBar(
                        content: Text('❌ ${response?['message'] ?? 'فشل'}'),
                        backgroundColor: Colors.red,
                      ));
                    }
                  } catch (_) {
                    scaffoldMessenger.showSnackBar(const SnackBar(
                      content: Text('❌ خطأ في الاتصال'),
                      backgroundColor: Colors.red,
                    ));
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlerts() {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 8),
              Text('تنبيهات ($_staleCount متأخر، $_stoppedCount متوقف)'),
            ],
          ),
          content: SizedBox(
            width: _isMobile ? double.maxFinite : 400,
            height: _isMobile ? 250 : 300,
            child: _alerts.isEmpty
                ? const Center(child: Text('لا توجد تنبيهات'))
                : ListView.separated(
                    itemCount: _alerts.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final a = _alerts[i] is Map ? _alerts[i] as Map : {};
                      final type = a['alertType'] ?? '';
                      final user = a['userId'] ?? '';
                      final mins = a['minutesAgo'] ?? 0;
                      return ListTile(
                        leading: Icon(
                          type == 'stale' ? Icons.timer_off : Icons.location_off,
                          color: type == 'stale' ? Colors.orange : Colors.red,
                        ),
                        title: Text(user),
                        subtitle: Text(
                          type == 'stale'
                              ? 'لم يحدّث منذ $mins دقيقة'
                              : 'أوقف مشاركة الموقع',
                        ),
                        trailing: Text(a['department'] ?? ''),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingTechnicianPanel() {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;
    final mobile = _isMobile;

    // على الهاتف: لوحة من الأسفل | على الحاسوب: لوحة جانبية
    if (mobile) {
      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        left: 8,
        right: 8,
        bottom: 8,
        height: _isPanelExpanded ? (screenH * 0.45).clamp(200.0, 350.0) : 48,
        child: Container(
          decoration: BoxDecoration(
            color: _cardColor.withValues(alpha: 0.97),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, -4)),
            ],
          ),
          child: _isPanelExpanded ? _buildExpandedPanel() : _buildCollapsedMobilePanel(),
        ),
      );
    }

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      right: 16,
      top: 16,
      bottom: 16,
      width: _isPanelExpanded
          ? (screenW * 0.3).clamp(220.0, 320.0)
          : 60,
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black12),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: _isPanelExpanded ? _buildExpandedPanel() : _buildCollapsedPanel(),
      ),
    );
  }

  Widget _buildCollapsedMobilePanel() {
    final count = _userPaths.keys.length;
    return InkWell(
      onTap: () => setState(() => _isPanelExpanded = true),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.people_alt_rounded, color: _accentColor, size: 20),
            const SizedBox(width: 8),
            Text('$count فني متصل', style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.bold, color: _primaryColor)),
            const Spacer(),
            Icon(Icons.keyboard_arrow_up_rounded, color: _primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedPanel() {
    return Column(
      children: [
        const SizedBox(height: 16),
        IconButton(
          icon: Icon(Icons.chevron_left_rounded, color: _primaryColor),
          onPressed: () => setState(() => _isPanelExpanded = true),
        ),
        const Spacer(),
        Icon(Icons.people_alt_rounded, color: _accentColor),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildExpandedPanel() {
    final users = _userPaths.keys.toList();
    final mobile = _isMobile;
    final double pad = mobile ? 12 : 20;
    final double titleSize = mobile ? 14 : 18;
    final double avatarSize = mobile ? 32 : 40;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(pad),
          child: Row(
            children: [
              Icon(Icons.people_alt_rounded, color: _accentColor, size: mobile ? 18 : 24),
              SizedBox(width: mobile ? 6 : 12),
              Expanded(
                child: Text(
                  "الفنيين المتصلين (${users.length})",
                  style: GoogleFonts.cairo(fontSize: titleSize, fontWeight: FontWeight.bold, color: _primaryColor),
                ),
              ),
              IconButton(
                icon: Icon(mobile ? Icons.keyboard_arrow_down_rounded : Icons.chevron_right_rounded, size: mobile ? 22 : 24),
                onPressed: () => setState(() => _isPanelExpanded = false),
                constraints: BoxConstraints(minWidth: mobile ? 32 : 48, minHeight: mobile ? 32 : 48),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),

        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: SizedBox(
            height: mobile ? 36 : 44,
            child: TextField(
              onChanged: (val) {
                setState(() => _searchQuery = val);
                _applyFilters();
              },
              style: GoogleFonts.cairo(fontSize: mobile ? 12 : 14),
              decoration: InputDecoration(
                hintText: "بحث عن فني...",
                hintStyle: GoogleFonts.cairo(fontSize: mobile ? 12 : 14),
                prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400], size: mobile ? 18 : 22),
                filled: true,
                fillColor: _surfaceColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(mobile ? 10 : 16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
        ),

        SizedBox(height: mobile ? 6 : 12),
        const Divider(height: 1),

        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(vertical: mobile ? 4 : 8),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final isHidden = _hiddenPaths.contains(user);

              return InkWell(
                onTap: () {
                  if (_userPaths[user]!.isNotEmpty) {
                    _mapController.move(_userPaths[user]!.last, 15);
                    if (mobile) setState(() => _isPanelExpanded = false);
                  }
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad, vertical: mobile ? 6 : 10),
                  child: Row(
                    children: [
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: _accentColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            user.isNotEmpty ? user[0] : "?",
                            style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold, fontSize: mobile ? 13 : 16),
                          ),
                        ),
                      ),
                      SizedBox(width: mobile ? 8 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user, style: GoogleFonts.cairo(fontWeight: FontWeight.bold, color: _primaryColor, fontSize: mobile ? 12 : 14), overflow: TextOverflow.ellipsis),
                            Text("نشط الآن", style: GoogleFonts.cairo(fontSize: mobile ? 10 : 11, color: Colors.green)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: mobile ? 18 : 20,
                          color: isHidden ? Colors.grey : _accentColor,
                        ),
                        constraints: BoxConstraints(minWidth: mobile ? 32 : 48, minHeight: mobile ? 32 : 48),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() {
                            if (isHidden)
                              _hiddenPaths.remove(user);
                            else
                              _hiddenPaths.add(user);
                            _markers = _markersByUser.entries
                                .where((e) => !_hiddenPaths.contains(e.key))
                                .map((e) => e.value)
                                .toList();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showUserDetailsDialog(BuildContext context, Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: _cardColor,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: _accentColor.withOpacity(0.2),
              child: Icon(Icons.person_pin_rounded, color: _accentColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                user["اسم المستخدم"] ?? "",
                style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _professionalInfoTile(Icons.work_rounded, "القسم", user["القسم"]),
            _professionalInfoTile(
                Icons.location_city_rounded, "المركز", user["المركز"]),
            _professionalInfoTile(
                Icons.phone_rounded, "رقم الهاتف", user["رقم الهاتف"]),
            _professionalInfoTile(
                Icons.history_rounded, "آخر تحديث", user["last update"]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'إغلاق',
              style: GoogleFonts.cairo(
                  color: _primaryColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _professionalInfoTile(IconData icon, String title, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey[500]),
              ),
              Text(
                value.toString(),
                style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _primaryColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// علامة الموقع النبضية
class _PulsingPin extends StatefulWidget {
  final Color color;
  const _PulsingPin({required this.color});

  @override
  State<_PulsingPin> createState() => _PulsingPinState();
}

class _PulsingPinState extends State<_PulsingPin>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // النبضة الخارجية
            Container(
              width: 30 * _controller.value,
              height: 30 * _controller.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withOpacity(1 - _controller.value),
              ),
            ),
            // النقطة المركزية
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
