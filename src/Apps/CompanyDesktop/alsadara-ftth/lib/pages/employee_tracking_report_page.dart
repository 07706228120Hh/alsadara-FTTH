import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api/api_client.dart';

/// صفحة تقارير تتبع الموظفين — مسار يومي + مسافة + أوقات
class EmployeeTrackingReportPage extends StatefulWidget {
  const EmployeeTrackingReportPage({super.key});

  @override
  State<EmployeeTrackingReportPage> createState() =>
      _EmployeeTrackingReportPageState();
}

class _EmployeeTrackingReportPageState
    extends State<EmployeeTrackingReportPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _employees = [];
  String? _selectedUserId;
  int _selectedHours = 24;

  // بيانات التقرير
  List<LatLng> _pathPoints = [];
  double _totalDistanceKm = 0;
  int _totalPoints = 0;
  String? _firstTime;
  String? _lastTime;
  bool _loadingReport = false;

  final MapController _mapController = MapController();

  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFF38BDF8);

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    try {
      final response = await ApiClient.instance.get(
        '/employee-location/active',
        (data) => data,
        useInternalKey: true,
      );
      if (response.isSuccess && response.data != null) {
        final rawData = response.data;
        final list = rawData is List
            ? rawData
            : (rawData is Map ? (rawData['data'] as List?) ?? [] : []);
        setState(() {
          _employees = list
              .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadReport(String userId) async {
    setState(() {
      _loadingReport = true;
      _pathPoints = [];
      _totalDistanceKm = 0;
      _totalPoints = 0;
      _firstTime = null;
      _lastTime = null;
    });

    try {
      final response = await ApiClient.instance.get(
        '/employee-location/history/$userId?hours=$_selectedHours',
        (data) => data,
        useInternalKey: true,
      );

      if (response.isSuccess && response.data != null) {
        final d = response.data;
        final rawData = d is Map ? d : <String, dynamic>{};
        final points = (rawData['data'] as List?) ?? [];

        final path = <LatLng>[];
        for (final p in points) {
          if (p is Map && p['lat'] != null && p['lng'] != null) {
            final lat = p['lat'] is num
                ? (p['lat'] as num).toDouble()
                : double.tryParse(p['lat'].toString()) ?? 0;
            final lng = p['lng'] is num
                ? (p['lng'] as num).toDouble()
                : double.tryParse(p['lng'].toString()) ?? 0;
            if (lat != 0 && lng != 0) path.add(LatLng(lat, lng));
          }
        }

        String? first;
        String? last;
        if (points.isNotEmpty) {
          final firstRec = points.first['recordedAt']?.toString();
          final lastRec = points.last['recordedAt']?.toString();
          if (firstRec != null) {
            first = _formatTime(DateTime.tryParse(firstRec));
          }
          if (lastRec != null) {
            last = _formatTime(DateTime.tryParse(lastRec));
          }
        }

        setState(() {
          _pathPoints = path;
          _totalDistanceKm =
              (rawData['totalDistanceKm'] as num?)?.toDouble() ?? 0;
          _totalPoints = rawData['totalPoints'] ?? 0;
          _firstTime = first;
          _lastTime = last;
          _loadingReport = false;
        });

        // تحريك الخريطة لتشمل المسار
        if (path.isNotEmpty) {
          final bounds = LatLngBounds.fromPoints(path);
          _mapController.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
          );
        }
      }
    } catch (_) {
      setState(() => _loadingReport = false);
    }
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('hh:mm a').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: Text(
            'تقارير تتبع الموظفين',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _loadEmployees();
                if (_selectedUserId != null) _loadReport(_selectedUserId!);
              },
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Row(
                children: [
                  // الشريط الجانبي — قائمة الموظفين
                  SizedBox(
                    width: 280,
                    child: _buildSidebar(),
                  ),
                  // المحتوى الرئيسي — الخريطة + الإحصائيات
                  Expanded(child: _buildMainContent()),
                ],
              ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          // فلتر الساعات
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.access_time, size: 18, color: _accentColor),
                const SizedBox(width: 8),
                const Text('الفترة:'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    value: _selectedHours,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('ساعة')),
                      DropdownMenuItem(value: 6, child: Text('6 ساعات')),
                      DropdownMenuItem(value: 12, child: Text('12 ساعة')),
                      DropdownMenuItem(value: 24, child: Text('24 ساعة')),
                      DropdownMenuItem(value: 48, child: Text('يومين')),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedHours = v ?? 24);
                      if (_selectedUserId != null) {
                        _loadReport(_selectedUserId!);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // قائمة الموظفين
          Expanded(
            child: _employees.isEmpty
                ? const Center(child: Text('لا يوجد موظفين نشطين'))
                : ListView.separated(
                    itemCount: _employees.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final emp = _employees[i];
                      final userId = emp['userId'] ?? '';
                      final dept = emp['department'] ?? '';
                      final isSelected = _selectedUserId == userId;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: _accentColor.withValues(alpha: 0.1),
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? _accentColor
                              : Colors.grey.shade300,
                          child: Icon(Icons.person,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade600,
                              size: 20),
                        ),
                        title: Text(userId,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            )),
                        subtitle: dept.isNotEmpty ? Text(dept) : null,
                        trailing: isSelected
                            ? const Icon(Icons.chevron_left,
                                color: _accentColor)
                            : null,
                        onTap: () {
                          setState(() => _selectedUserId = userId);
                          _loadReport(userId);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_selectedUserId == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 80, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text('اختر موظفاً لعرض مساره',
                style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // بطاقات الإحصائيات
        _buildStatsRow(),
        // الخريطة
        Expanded(child: _buildMap()),
      ],
    );
  }

  Widget _buildStatsRow() {
    if (_loadingReport) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildStatCard(
            Icons.person,
            _selectedUserId ?? '',
            'الموظف',
            _accentColor,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            Icons.route,
            '${_totalDistanceKm.toStringAsFixed(1)} كم',
            'المسافة الإجمالية',
            Colors.green,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            Icons.location_on,
            '$_totalPoints نقطة',
            'عدد المواقع المسجّلة',
            Colors.orange,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            Icons.login,
            _firstTime ?? '-',
            'أول نشاط',
            Colors.blue,
          ),
          const SizedBox(width: 12),
          _buildStatCard(
            Icons.logout,
            _lastTime ?? '-',
            'آخر نشاط',
            Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: color),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: LatLng(33.3573, 44.4414),
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.alsadara.app',
        ),
        // مسار الحركة
        if (_pathPoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _pathPoints,
                color: _accentColor,
                strokeWidth: 3,
              ),
            ],
          ),
        // نقاط البداية والنهاية
        if (_pathPoints.isNotEmpty)
          MarkerLayer(
            markers: [
              // نقطة البداية (أخضر)
              Marker(
                point: _pathPoints.first,
                width: 30,
                height: 30,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.green.withValues(alpha: 0.4),
                          blurRadius: 6)
                    ],
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 16),
                ),
              ),
              // نقطة النهاية (أحمر)
              if (_pathPoints.length > 1)
                Marker(
                  point: _pathPoints.last,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.red.withValues(alpha: 0.4),
                            blurRadius: 6)
                      ],
                    ),
                    child:
                        const Icon(Icons.stop, color: Colors.white, size: 16),
                  ),
                ),
            ],
          ),
        // رسالة فارغة
        if (_pathPoints.isEmpty && !_loadingReport)
          MarkerLayer(
            markers: [
              Marker(
                point: const LatLng(33.3573, 44.4414),
                width: 200,
                height: 40,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4)
                    ],
                  ),
                  child: const Text('لا توجد بيانات لهذه الفترة',
                      textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
