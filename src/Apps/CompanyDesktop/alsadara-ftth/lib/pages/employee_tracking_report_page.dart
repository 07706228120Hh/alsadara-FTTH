import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api/api_client.dart';
import '../permissions/permission_manager.dart';

/// صفحة تقارير تتبع الموظفين — مسار يومي + مسافة + أوقات
class EmployeeTrackingReportPage extends StatefulWidget {
  const EmployeeTrackingReportPage({super.key});

  @override
  State<EmployeeTrackingReportPage> createState() =>
      _EmployeeTrackingReportPageState();
}

class _EmployeeTrackingReportPageState
    extends State<EmployeeTrackingReportPage> with TickerProviderStateMixin {
  bool _loading = true;
  List<Map<String, dynamic>> _employees = [];
  String? _selectedUserId;
  int _selectedHours = 24;

  // بيانات التقرير
  List<LatLng> _pathPoints = [];     // نقاط GPS الخام
  List<LatLng> _snappedPath = [];    // المسار الملصوق على الشوارع (OSRM)
  List<Map<String, dynamic>> _stops = []; // نقاط التوقف
  List<double> _speeds = [];          // سرعة كل segment (كم/س)
  double _totalDistanceKm = 0;
  double? _roadDistanceKm;          // المسافة على الطريق الفعلي
  int _totalPoints = 0;
  String? _firstTime;
  String? _lastTime;
  bool _loadingReport = false;

  // ═══ Route Replay ═══
  bool _isReplaying = false;
  int _replayIndex = 0;
  Timer? _replayTimer;

  final MapController _mapController = MapController();

  static const _primaryColor = Color(0xFF0F172A);
  static const _accentColor = Color(0xFF38BDF8);

  // ═══ ألوان السرعة ═══
  static const _speedSlow = Color(0xFF22C55E);    // أخضر < 10 كم/س (مشي)
  static const _speedMedium = Color(0xFFF59E0B);  // أصفر 10-40 كم/س
  static const _speedFast = Color(0xFFEF4444);    // أحمر > 40 كم/س

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _replayTimer?.cancel();
    super.dispose();
  }

  // ═══ Route Replay ═══

  void _startReplay() {
    if (_pathPoints.length < 2) return;
    _replayTimer?.cancel();
    setState(() {
      _isReplaying = true;
      _replayIndex = 0;
    });
    _replayTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_replayIndex >= _pathPoints.length - 1) {
        timer.cancel();
        setState(() => _isReplaying = false);
        return;
      }
      setState(() => _replayIndex++);
      // تتبع الماركر المتحرك
      _mapController.move(_pathPoints[_replayIndex], _mapController.camera.zoom);
    });
  }

  void _stopReplay() {
    _replayTimer?.cancel();
    setState(() => _isReplaying = false);
  }

  Color _speedColor(double kmh) {
    if (kmh < 10) return _speedSlow;
    if (kmh < 40) return _speedMedium;
    return _speedFast;
  }

  Future<void> _loadEmployees() async {
    try {
      final response = await ApiClient.instance.get(
        '/employee-location/tracked-users?hours=$_selectedHours',
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
      _snappedPath = [];
      _stops = [];
      _totalDistanceKm = 0;
      _roadDistanceKm = null;
      _totalPoints = 0;
      _firstTime = null;
      _lastTime = null;
    });

    try {
      // نجلب البيانات عبر HTTP مباشرة لنحصل على الـ wrapper الكامل
      // (ApiClient يفك {success, data} فنفقد snappedPath و stops)
      final response = await ApiClient.instance.getRaw(
        '/employee-location/history/$userId?hours=$_selectedHours&snap=true',
        useInternalKey: true,
      );

      if (response != null) {
        final body = response;
        final points = (body['data'] as List?) ?? [];
        final distKm = (body['totalDistanceKm'] as num?)?.toDouble() ?? 0;
        final totalPts = (body['totalPoints'] as num?)?.toInt() ?? 0;
        final roadDist = (body['roadDistanceKm'] as num?)?.toDouble();

        // ═══ نقاط GPS الخام ═══
        final path = _parseLatLngList(points);

        // ═══ المسار الملصوق على الشوارع (OSRM) ═══
        final snappedRaw = (body['snappedPath'] as List?) ?? [];
        final snapped = _parseLatLngList(snappedRaw);

        // ═══ نقاط التوقف ═══
        final stopsRaw = (body['stops'] as List?) ?? [];
        final stops = stopsRaw
            .whereType<Map<String, dynamic>>()
            .toList();

        // ═══ حساب السرعة لكل segment ═══
        final speeds = <double>[];
        for (int i = 0; i < points.length - 1; i++) {
          final p1 = points[i];
          final p2 = points[i + 1];
          if (p1 is Map && p2 is Map) {
            final t1 = DateTime.tryParse(p1['recordedAt']?.toString() ?? '');
            final t2 = DateTime.tryParse(p2['recordedAt']?.toString() ?? '');
            final s = (p1['speed'] as num?)?.toDouble();
            if (s != null && s > 0) {
              speeds.add(s * 3.6); // m/s → km/h
            } else if (t1 != null && t2 != null) {
              final secs = t2.difference(t1).inSeconds;
              if (secs > 0 && i < path.length - 1 && i < path.length) {
                final d = _haversineKm(
                  path[i].latitude, path[i].longitude,
                  path[i + 1].latitude, path[i + 1].longitude,
                ) * 1000; // km → m
                speeds.add((d / secs) * 3.6); // m/s → km/h
              } else {
                speeds.add(0);
              }
            } else {
              speeds.add(0);
            }
          } else {
            speeds.add(0);
          }
        }

        // ═══ أوقات ═══
        String? first;
        String? last;
        if (points.isNotEmpty) {
          final firstRec = points.first is Map ? points.first['recordedAt']?.toString() : null;
          final lastRec = points.last is Map ? points.last['recordedAt']?.toString() : null;
          if (firstRec != null) first = _formatTime(DateTime.tryParse(firstRec));
          if (lastRec != null) last = _formatTime(DateTime.tryParse(lastRec));
        }

        setState(() {
          _pathPoints = path;
          _snappedPath = snapped;
          _stops = stops;
          _speeds = speeds;
          _totalDistanceKm = distKm;
          _roadDistanceKm = roadDist;
          _totalPoints = totalPts;
          _firstTime = first;
          _lastTime = last;
          _loadingReport = false;
          _isReplaying = false;
          _replayIndex = 0;
          _replayTimer?.cancel();
        });

        // تحريك الخريطة لتشمل المسار
        final allPoints = snapped.isNotEmpty ? snapped : path;
        if (allPoints.isNotEmpty) {
          final bounds = LatLngBounds.fromPoints(allPoints);
          _mapController.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
          );
        }
      } else {
        setState(() => _loadingReport = false);
      }
    } catch (_) {
      setState(() => _loadingReport = false);
    }
  }

  /// تحويل قائمة Maps إلى قائمة LatLng
  List<LatLng> _parseLatLngList(List items) {
    final result = <LatLng>[];
    for (final p in items) {
      if (p is Map && p['lat'] != null && p['lng'] != null) {
        final lat = (p['lat'] is num) ? (p['lat'] as num).toDouble()
            : double.tryParse(p['lat'].toString()) ?? 0;
        final lng = (p['lng'] is num) ? (p['lng'] as num).toDouble()
            : double.tryParse(p['lng'].toString()) ?? 0;
        if (lat != 0 && lng != 0) result.add(LatLng(lat, lng));
      }
    }
    return result;
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('hh:mm a').format(dt.toLocal());
  }

  /// حوار مسح البيانات — للمدير فقط
  void _showPurgeDialog() {
    int days = 0; // 0 = مسح الكل
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
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
                  DropdownMenuItem(value: 0, child: Text('مسح جميع البيانات')),
                  DropdownMenuItem(value: 7, child: Text('أقدم من 7 أيام')),
                  DropdownMenuItem(value: 14, child: Text('أقدم من 14 يوم')),
                  DropdownMenuItem(value: 30, child: Text('أقدم من 30 يوم')),
                  DropdownMenuItem(value: 60, child: Text('أقدم من 60 يوم')),
                ],
                onChanged: (v) => setDialogState(() => days = v ?? 0),
              ),
              const SizedBox(height: 8),
              if (days == 0)
                Text('⚠️ سيتم حذف جميع السجلات والمواقع الحالية!',
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
                await _executePurge(days);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executePurge(int days) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      // جلب الدور من PermissionManager
      final role = PermissionManager.instance.canDelete('admin')
          ? 'admin'
          : PermissionManager.instance.canDelete('tracking')
              ? 'manager'
              : '';

      final endpoint = days == 0
          ? '/employee-location/purge?all=true'
          : '/employee-location/purge?olderThanDays=$days';
      final response = await ApiClient.instance.deleteRaw(
        endpoint,
        useInternalKey: true,
        extraHeaders: {'X-Caller-Role': role},
      );

      if (response != null && response['success'] == true) {
        final count = response['deletedCount'] ?? 0;
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(days == 0
                ? '✅ تم حذف جميع البيانات ($count سجل)'
                : '✅ تم حذف $count سجل (أقدم من $days يوم)'),
            backgroundColor: Colors.green,
          ),
        );
        _loadEmployees();
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('❌ ${response?['message'] ?? 'فشل الحذف'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('❌ خطأ في الاتصال'), backgroundColor: Colors.red),
      );
    }
  }

  bool get _isMobile => MediaQuery.of(context).size.width < 600;

  @override
  Widget build(BuildContext context) {
    final mobile = _isMobile;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          toolbarHeight: mobile ? 46 : kToolbarHeight,
          title: Text(
            mobile ? 'تقارير التتبع' : 'تقارير تتبع الموظفين',
            style: GoogleFonts.cairo(fontWeight: FontWeight.bold, fontSize: mobile ? 15 : 20),
          ),
          actions: [
            // 🗑️ زر مسح البيانات — للمدير فقط
            if (PermissionManager.instance.canDelete('tracking') ||
                PermissionManager.instance.canView('accounting'))
              IconButton(
                icon: Icon(Icons.delete_sweep, color: Colors.redAccent, size: mobile ? 20 : 24),
                tooltip: 'مسح بيانات التتبع القديمة',
                onPressed: _showPurgeDialog,
              ),
            IconButton(
              icon: Icon(Icons.refresh, size: mobile ? 20 : 24),
              onPressed: () {
                _loadEmployees();
                if (_selectedUserId != null) _loadReport(_selectedUserId!);
              },
            ),
          ],
        ),
        // على الهاتف: drawer للموظفين | على الحاسوب: sidebar ثابت
        drawer: mobile ? Drawer(child: _buildSidebar()) : null,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : mobile
                ? _buildMobileLayout()
                : Row(
                    children: [
                      SizedBox(
                        width: (MediaQuery.of(context).size.width * 0.25).clamp(200, 280),
                        child: _buildSidebar(),
                      ),
                      Expanded(child: _buildMainContent()),
                    ],
                  ),
      ),
    );
  }

  /// Layout للهاتف — الخريطة بكامل الشاشة + زر فتح قائمة الموظفين
  Widget _buildMobileLayout() {
    return Stack(
      children: [
        _buildMainContent(),
        // زر فتح القائمة الجانبية
        if (_selectedUserId == null)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              heroTag: 'employees',
              backgroundColor: _primaryColor,
              icon: const Icon(Icons.people, color: Colors.white, size: 18),
              label: Text(
                'الموظفين (${_employees.length})',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
      ],
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
                      _loadEmployees(); // إعادة تحميل القائمة حسب الفترة الجديدة
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
                          // إغلاق الـ Drawer على الهاتف
                          if (_isMobile) Navigator.of(context).pop();
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
        // الخريطة مع أزرار التحكم
        Expanded(
          child: Stack(
            children: [
              _buildMap(),
              // ═══ أزرار التحكم ═══
              if (_pathPoints.length > 2)
                Positioned(
                  bottom: _isMobile ? 64 : 16,
                  left: _isMobile ? 8 : 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // زر إعادة التشغيل
                      FloatingActionButton.small(
                        heroTag: 'replay',
                        backgroundColor: _isReplaying ? Colors.red : Colors.deepPurple,
                        onPressed: _isReplaying ? _stopReplay : _startReplay,
                        child: Icon(
                          _isReplaying ? Icons.stop : Icons.replay,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // مفتاح الألوان
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _legendItem(_speedSlow, 'مشي (< 10 كم/س)'),
                            _legendItem(_speedMedium, 'قيادة (10-40 كم/س)'),
                            _legendItem(_speedFast, 'سريع (> 40 كم/س)'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              // ═══ شريط تقدم الريبلاي ═══
              if (_isReplaying)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.play_arrow, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _pathPoints.isEmpty ? 0 : _replayIndex / (_pathPoints.length - 1),
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_replayIndex + 1} / ${_pathPoints.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 16, height: 4, color: color),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    if (_loadingReport) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }

    final mobile = _isMobile;
    final cards = <Widget>[
      _buildStatCard(Icons.person, _selectedUserId ?? '', 'الموظف', _accentColor),
      _buildStatCard(
        Icons.route,
        _roadDistanceKm != null
            ? '${_roadDistanceKm!.toStringAsFixed(1)} كم'
            : '${_totalDistanceKm.toStringAsFixed(1)} كم',
        _roadDistanceKm != null ? 'المسافة (طريق)' : 'المسافة',
        Colors.green,
      ),
      _buildStatCard(Icons.location_on, '$_totalPoints', 'نقاط', Colors.orange),
      if (_stops.isNotEmpty)
        _buildStatCard(Icons.pause_circle, '${_stops.length}', 'توقفات', Colors.orange.shade700),
      _buildStatCard(Icons.login, _firstTime ?? '-', 'أول نشاط', Colors.blue),
      _buildStatCard(Icons.logout, _lastTime ?? '-', 'آخر نشاط', Colors.purple),
    ];

    if (mobile) {
      // على الهاتف: شريط قابل للتمرير أفقياً
      final cardW = ((MediaQuery.of(context).size.width - 32) / 3.5).clamp(85.0, 130.0);
      return SizedBox(
        height: 70,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: cards.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => SizedBox(width: cardW, child: cards[i]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String value, String label, Color color) {
    final mobile = _isMobile;
    return Container(
      padding: EdgeInsets.all(mobile ? 8 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: mobile ? 18 : 22),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: mobile ? 11 : 14, color: color),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(fontSize: mobile ? 8 : 10, color: Colors.grey.shade600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildMap() {
    // المسار الرئيسي: snapped (على الشوارع) أو smoothed (تنعيم محلي)
    final hasSnapped = _snappedPath.length > 1;
    final displayPath = hasSnapped ? _snappedPath : _smoothPoints(_pathPoints);

    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: LatLng(33.3573, 44.4414),
        initialZoom: 12,
        minZoom: 5,
        maxZoom: 19,
        interactionOptions: InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.alsadara.app',
          maxZoom: 19,
        ),
        // ═══ خط GPS الخام — شفاف كمرجع (فقط إذا يوجد snapped) ═══
        if (hasSnapped && _pathPoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _pathPoints,
                color: Colors.white.withValues(alpha: 0.25),
                strokeWidth: 2,
                pattern: const StrokePattern.dotted(),
              ),
            ],
          ),
        // ═══ المسار الرئيسي — متدرج اللون ═══
        if (displayPath.length > 1)
          PolylineLayer(
            polylines: _buildGradientPolylines(displayPath),
          ),
        // ═══ نقاط GPS الوسيطة ═══
        if (_pathPoints.length > 2)
          CircleLayer(
            circles: [
              for (int i = 1; i < _pathPoints.length - 1; i++)
                CircleMarker(
                  point: _pathPoints[i],
                  radius: 3.5,
                  color: _accentColor.withValues(alpha: 0.5),
                  borderColor: Colors.white,
                  borderStrokeWidth: 1,
                ),
            ],
          ),
        // ═══ نقاط التوقف (برتقالي مع مدة) ═══
        if (_stops.isNotEmpty)
          MarkerLayer(
            markers: [
              for (final stop in _stops)
                if (stop['lat'] != null && stop['lng'] != null)
                  Marker(
                    point: LatLng(
                      (stop['lat'] as num).toDouble(),
                      (stop['lng'] as num).toDouble(),
                    ),
                    width: 60,
                    height: 45,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${(stop['durationMinutes'] as num?)?.toStringAsFixed(0) ?? '?'} د',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(color: Colors.orange.withValues(alpha: 0.5), blurRadius: 6),
                            ],
                          ),
                          child: const Icon(Icons.pause, color: Colors.white, size: 10),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        // ═══ أسهم الاتجاه ═══
        if (displayPath.length > 3)
          MarkerLayer(
            markers: _buildDirectionArrows(displayPath),
          ),
        // ═══ نقاط البداية والنهاية ═══
        if (_pathPoints.isNotEmpty)
          MarkerLayer(
            markers: [
              Marker(
                point: _pathPoints.first,
                width: 36,
                height: 36,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(color: Colors.green.withValues(alpha: 0.5), blurRadius: 8),
                    ],
                  ),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                ),
              ),
              if (_pathPoints.length > 1)
                Marker(
                  point: _pathPoints.last,
                  width: 36,
                  height: 36,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(color: Colors.red.withValues(alpha: 0.5), blurRadius: 8),
                      ],
                    ),
                    child: const Icon(Icons.stop, color: Colors.white, size: 18),
                  ),
                ),
            ],
          ),
        // ═══ ماركر إعادة التشغيل المتحرك ═══
        if (_isReplaying && _replayIndex < _pathPoints.length)
          MarkerLayer(
            markers: [
              Marker(
                point: _pathPoints[_replayIndex],
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.deepPurple,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(color: Colors.deepPurple.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 2),
                    ],
                  ),
                  child: const Icon(Icons.person_pin, color: Colors.white, size: 20),
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
                width: _isMobile ? 160 : 200,
                height: 40,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: const Text('لا توجد بيانات لهذه الفترة', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
      ],
    );
  }

  /// تنعيم المسار — Catmull-Rom spline بين النقاط
  List<LatLng> _smoothPoints(List<LatLng> points) {
    if (points.length < 3) return points;
    final result = <LatLng>[points.first];
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[max(0, i - 1)];
      final p1 = points[i];
      final p2 = points[min(points.length - 1, i + 1)];
      final p3 = points[min(points.length - 1, i + 2)];

      // حساب المسافة بين النقطتين — إذا قريبة لا نحتاج تنعيم
      final dLat = (p2.latitude - p1.latitude).abs() * 111320;
      final dLng = (p2.longitude - p1.longitude).abs() * 111320 * 0.7;
      final dist = sqrt(dLat * dLat + dLng * dLng);

      if (dist < 10) {
        // أقل من 10 متر — نقطة مباشرة
        result.add(p2);
        continue;
      }

      // Catmull-Rom interpolation — نضيف 3 نقاط وسيطة
      final steps = dist > 100 ? 5 : 3;
      for (int s = 1; s <= steps; s++) {
        final t = s / (steps + 1);
        final t2 = t * t;
        final t3 = t2 * t;
        final lat = 0.5 * ((2 * p1.latitude) +
            (-p0.latitude + p2.latitude) * t +
            (2 * p0.latitude - 5 * p1.latitude + 4 * p2.latitude - p3.latitude) * t2 +
            (-p0.latitude + 3 * p1.latitude - 3 * p2.latitude + p3.latitude) * t3);
        final lng = 0.5 * ((2 * p1.longitude) +
            (-p0.longitude + p2.longitude) * t +
            (2 * p0.longitude - 5 * p1.longitude + 4 * p2.longitude - p3.longitude) * t2 +
            (-p0.longitude + 3 * p1.longitude - 3 * p2.longitude + p3.longitude) * t3);
        result.add(LatLng(lat, lng));
      }
      result.add(p2);
    }
    return result;
  }

  /// بناء خطوط ملونة حسب السرعة (أخضر/أصفر/أحمر)
  List<Polyline> _buildGradientPolylines(List<LatLng> points) {
    if (points.length < 2) return [];
    final segments = <Polyline>[];
    final useSpeedColors = _speeds.isNotEmpty && points == _pathPoints;

    for (int i = 0; i < points.length - 1; i++) {
      Color color;
      if (useSpeedColors && i < _speeds.length) {
        color = _speedColor(_speeds[i]);
      } else {
        // fallback — تدرج زمني
        final progress = i / (points.length - 1);
        color = Color.lerp(
          const Color(0x6038BDF8),
          const Color(0xFF0284C7),
          progress,
        )!;
      }
      segments.add(Polyline(
        points: [points[i], points[i + 1]],
        color: color,
        strokeWidth: 4,
      ));
    }
    return segments;
  }

  /// أسهم اتجاه الحركة — كل بضع نقاط
  List<Marker> _buildDirectionArrows(List<LatLng> points) {
    final arrows = <Marker>[];
    // سهم كل ~5 نقاط أو كل ~50 متر
    int step = max(3, points.length ~/ 15);
    for (int i = step; i < points.length - 1; i += step) {
      final from = points[i - 1];
      final to = points[i];
      // حساب زاوية الاتجاه
      final angle = atan2(
        (to.longitude - from.longitude) * 0.7,
        to.latitude - from.latitude,
      );
      arrows.add(Marker(
        point: to,
        width: 20,
        height: 20,
        child: Transform.rotate(
          angle: -angle + pi / 2, // تحويل إلى اتجاه الخريطة
          child: Icon(
            Icons.navigation,
            color: const Color(0xFF0284C7),
            size: 16,
          ),
        ),
      ));
    }
    return arrows;
  }
}
