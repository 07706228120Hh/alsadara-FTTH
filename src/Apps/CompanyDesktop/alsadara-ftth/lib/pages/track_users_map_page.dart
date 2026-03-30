import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:latlong2/latlong.dart';
import '../services/api/api_client.dart';
import 'employee_tracking_report_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';

class TrackUsersMapPage extends StatefulWidget {
  const TrackUsersMapPage({super.key});

  @override
  State<TrackUsersMapPage> createState() => _TrackUsersMapPageState();
}

class _TrackUsersMapPageState extends State<TrackUsersMapPage>
    with TickerProviderStateMixin {
  // يستخدم Sadara API بدل Google Sheets

  final MapController _mapController = MapController();
  final Map<String, List<LatLng>> _userPaths = {};
  final Set<String> _hiddenPaths = {};
  String _searchQuery = "";

  List<Marker> _markers = [];
  List<dynamic> _rawData = [];
  bool _loading = true;
  Timer? _timer;
  MbTilesTileProvider? _mbtilesProvider;
  bool _isPanelExpanded = true;

  // تنبيهات
  int _staleCount = 0;
  int _stoppedCount = 0;
  List<dynamic> _alerts = [];

  static const LatLng _defaultCenter = LatLng(33.3573338, 44.4414648);

  // الألوان الفخمة (مطابقة للصفحة الرئيسية الجديدة)
  final Color _primaryColor = const Color(0xFF0F172A); // Slate 900
  final Color _accentColor = const Color(0xFF38BDF8); // Cyan 400
  final Color _surfaceColor = const Color(0xFFF8FAFC); // Slate 50
  final Color _cardColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _initOfflineMap();
    _fetchAndUpdateMarkers();
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _fetchAndUpdateMarkers();
    });
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
    final List<Marker> newMarkers = [];

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

        newMarkers.add(
          Marker(
            point: pos,
            width: 120,
            height: 120,
            child: _buildProfessionalMarker(userName, item),
          ),
        );
      }
    }
    setState(() => _markers = newMarkers);
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
    return GestureDetector(
      onTap: () => _showUserDetailsDialog(context, data),
      child: Column(
        children: [
          // فقاعة الاسم الأنيقة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: _accentColor.withOpacity(0.5), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              name,
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          // العلامة النبضية
          _PulsingPin(color: _accentColor),
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
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.alsadara.app',
                tileProvider: _mbtilesProvider,
              ),
              PolylineLayer(
                polylines: _userPaths.entries
                    .where((e) => !_hiddenPaths.contains(e.key))
                    .map((entry) {
                  return Polyline(
                    points: entry.value,
                    color: _accentColor.withOpacity(0.4),
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: _primaryColor,
      title: Text(
        "تتبع الفنيين - نظام الذكاء المكاني",
        style:
            GoogleFonts.cairo(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      actions: [
        // زر التنبيهات
        if (_staleCount + _stoppedCount > 0)
          IconButton(
            icon: Badge(
              label: Text('${_staleCount + _stoppedCount}'),
              backgroundColor: Colors.red,
              child: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            ),
            onPressed: _showAlerts,
            tooltip: "تنبيهات",
          ),
        IconButton(
          icon: const Icon(Icons.analytics_outlined, color: Colors.white),
          onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const EmployeeTrackingReportPage())),
          tooltip: "تقارير التتبع",
        ),
        IconButton(
          icon: Icon(Icons.refresh_rounded, color: _accentColor),
          onPressed: _fetchAndUpdateMarkers,
          tooltip: "تحديث البيانات",
        ),
        const SizedBox(width: 8),
      ],
      iconTheme: const IconThemeData(color: Colors.white),
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
            width: 400,
            height: 300,
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
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      right: 16,
      top: 16,
      bottom: 16,
      width: _isPanelExpanded
          ? (MediaQuery.of(context).size.width * 0.75).clamp(240.0, 320.0)
          : 60,
      child: Container(
        decoration: BoxDecoration(
          color: _cardColor.withOpacity(0.95),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child:
            _isPanelExpanded ? _buildExpandedPanel() : _buildCollapsedPanel(),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ترويسة اللوحة
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(Icons.people_alt_rounded, color: _accentColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "الفنيين المتصلين",
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _primaryColor,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: () => setState(() => _isPanelExpanded = false),
              ),
            ],
          ),
        ),

        // خانة البحث
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (val) {
              setState(() => _searchQuery = val);
              _applyFilters();
            },
            decoration: InputDecoration(
              hintText: "بحث عن فني...",
              hintStyle: GoogleFonts.cairo(fontSize: 14),
              prefixIcon: Icon(Icons.search_rounded, color: Colors.grey[400]),
              filled: true,
              fillColor: _surfaceColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        const SizedBox(height: 12),
        const Divider(height: 1),

        // قائمة الفنيين
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final isHidden = _hiddenPaths.contains(user);

              return InkWell(
                onTap: () {
                  // تحريك الخريطة لموقع الفني
                  if (_userPaths[user]!.isNotEmpty) {
                    _mapController.move(_userPaths[user]!.last, 15);
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _accentColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            user.isNotEmpty ? user[0] : "?",
                            style: TextStyle(
                              color: _accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user,
                              style: GoogleFonts.cairo(
                                fontWeight: FontWeight.bold,
                                color: _primaryColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              "نشط الآن",
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          isHidden
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 20,
                          color: isHidden ? Colors.grey : _accentColor,
                        ),
                        onPressed: () {
                          setState(() {
                            if (isHidden)
                              _hiddenPaths.remove(user);
                            else
                              _hiddenPaths.add(user);
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
