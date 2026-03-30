/// صفحة خريطة الزونات KML
/// تعرض نقاط FAT ومناطق FDT المستوردة من ملف KML
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import 'package:google_fonts/google_fonts.dart';

// ══════════════════════════════════════════════════════════════
// Models
// ══════════════════════════════════════════════════════════════

class FatPoint {
  final String name;
  final LatLng position;
  final String oltId;
  final String activationStatus;
  final String fdt;
  final String project;
  final String zone;

  const FatPoint({
    required this.name,
    required this.position,
    required this.oltId,
    required this.activationStatus,
    required this.fdt,
    required this.project,
    required this.zone,
  });

  bool get isActive =>
      activationStatus.toLowerCase().contains('active') ||
      activationStatus.toLowerCase().contains('مفعل');
}

class FdtRegion {
  final String zoneId;
  final String status;
  final String mahallah;
  final String neighborhood;
  final String subring;
  final int regionUsers;
  final List<LatLng> points;
  final String zone;

  const FdtRegion({
    required this.zoneId,
    required this.status,
    required this.mahallah,
    required this.neighborhood,
    required this.subring,
    required this.regionUsers,
    required this.points,
    required this.zone,
  });
}

// ── Route Step Model ─────────────────────────────────────────
class RouteStep {
  final String instruction; // النص العربي
  final String streetName;
  final double distanceMeters;
  final IconData icon;

  const RouteStep({
    required this.instruction,
    required this.streetName,
    required this.distanceMeters,
    required this.icon,
  });
}

// ══════════════════════════════════════════════════════════════
// KML Parser — Isolate
// ══════════════════════════════════════════════════════════════

class _ParseResult {
  final List<FatPoint> points;
  final List<FdtRegion> regions;
  const _ParseResult(this.points, this.regions);
}

_ParseResult _parseKml(String xmlString) {
  final points = <FatPoint>[];
  final regions = <FdtRegion>[];

  final doc = XmlDocument.parse(xmlString);

  void processFolder(XmlElement folder, String parentName) {
    final nameEl = folder.findElements('name').firstOrNull;
    final name = nameEl?.innerText.trim().replaceAll('.kml', '') ?? parentName;

    for (final sub in folder.findElements('Folder')) {
      processFolder(sub, name);
    }

    for (final pm in folder.findElements('Placemark')) {
      final pmName =
          pm.findElements('name').firstOrNull?.innerText.trim() ?? '';
      final schemaData = pm.findAllElements('SchemaData').firstOrNull;

      // ── FAT Point ─────────────────────────────────────────
      final pointEl = pm.findElements('Point').firstOrNull;
      if (pointEl != null) {
        final coordStr =
            pointEl.findElements('coordinates').firstOrNull?.innerText.trim() ??
                '';
        final parts = coordStr.split(',');
        if (parts.length >= 2) {
          final lng = double.tryParse(parts[0].trim());
          final lat = double.tryParse(parts[1].trim());
          if (lat != null && lng != null) {
            String oltId = '', activation = '', fdt = '', project = '';
            if (schemaData != null) {
              for (final sd in schemaData.findElements('SimpleData')) {
                final n = sd.getAttribute('name') ?? '';
                final v = sd.innerText.trim();
                if (n == 'cab_or_olt_id') oltId = v;
                if (n == 'activation_status') activation = v;
                if (n == 'fdt') fdt = v;
                if (n == 'project') project = v;
              }
            }
            // استخراج رقم FBG من اسم FAT مباشرةً (FAT1-FBG1002 → FBG1002)
            // يكون أدق من حقل fdt الذي قد يحتوي رقمًا مختصرًا
            final fbgMatch =
                RegExp(r'-(FBG\d+)', caseSensitive: false).firstMatch(pmName);
            if (fbgMatch != null) fdt = fbgMatch.group(1)!.toUpperCase();
            points.add(FatPoint(
              name: pmName,
              position: LatLng(lat, lng),
              oltId: oltId,
              activationStatus: activation,
              fdt: fdt,
              project: project,
              zone: name,
            ));
          }
        }
        continue;
      }

      // ── FDT Polygon ────────────────────────────────────────
      final polyEl = pm.findElements('Polygon').firstOrNull;
      if (polyEl != null) {
        final coordStr = polyEl
                .findAllElements('coordinates')
                .firstOrNull
                ?.innerText
                .trim() ??
            '';
        final polyPoints = <LatLng>[];
        for (final entry in coordStr.trim().split(RegExp(r'\s+'))) {
          final parts = entry.split(',');
          if (parts.length >= 2) {
            final lng = double.tryParse(parts[0].trim());
            final lat = double.tryParse(parts[1].trim());
            if (lat != null && lng != null) polyPoints.add(LatLng(lat, lng));
          }
        }
        if (polyPoints.isNotEmpty) {
          String zoneId = '', status = '', mahallah = '', neighborhood = '',
              subring = '';
          int regionUsers = 0;
          if (schemaData != null) {
            for (final sd in schemaData.findElements('SimpleData')) {
              final n = sd.getAttribute('name') ?? '';
              final v = sd.innerText.trim();
              if (n == 'ZoneID') zoneId = v;
              if (n == 'Status') status = v;
              if (n == 'mahallah_ar') mahallah = v;
              if (n == 'neighborhood_ar') neighborhood = v;
              if (n == 'subring_id') subring = v;
              if (n == 'region_users') regionUsers = int.tryParse(v) ?? 0;
            }
          }
          regions.add(FdtRegion(
            zoneId: zoneId,
            status: status,
            mahallah: mahallah,
            neighborhood: neighborhood,
            subring: subring,
            regionUsers: regionUsers,
            points: polyPoints,
            zone: name,
          ));
        }
      }
    }
  }

  final docEl = doc
      .findElements('kml')
      .firstOrNull
      ?.findElements('Document')
      .firstOrNull;
  if (docEl != null) {
    for (final folder in docEl.findElements('Folder')) {
      processFolder(folder, '');
    }
  }
  return _ParseResult(points, regions);
}

// ══════════════════════════════════════════════════════════════
// KML Zones Map Page
// ══════════════════════════════════════════════════════════════

class KmlZonesMapPage extends StatefulWidget {
  const KmlZonesMapPage({super.key});

  @override
  State<KmlZonesMapPage> createState() => _KmlZonesMapPageState();
}

class _KmlZonesMapPageState extends State<KmlZonesMapPage> {
  // ── Theme (نفس ستايل track_users_map_page) ──────────────────
  static const _bg = Color(0xFF0F172A);
  static const _surface = Color(0xFF1E293B);
  static const _accent = Color(0xFF38BDF8);
  static const _card = Color(0xFF1E293B);

  // ── In-memory cache (survives page navigation) ──────────────
  static List<FatPoint>? _cachedPoints;
  static List<FdtRegion>? _cachedRegions;
  static List<String>? _cachedZones;

  // ── State ────────────────────────────────────────────────────
  bool _loading = true;
  String? _error;
  List<FatPoint> _allPoints = [];
  List<FdtRegion> _allRegions = [];
  List<String> _zones = [];

  String _selectedZone = 'الكل';
  String _selectedFbg = 'الكل';
  String _selectedFat = 'الكل';
  bool _showPoints = true;
  bool _showRegions = true;
  bool _showFbgBorders = true;
  bool _showOnlyActive = false;
  bool _isPanelExpanded = true;

  // FBG zones (convex hulls)
  List<String> _fbgs = [];
  Map<String, List<LatLng>> _fbgHulls = {};
  Map<String, Color> _fbgColors = {};

  FatPoint? _selectedPoint;
  FdtRegion? _selectedRegion;

  final _mapController = MapController();
  // keys to force-reset Autocomplete when parent filter changes
  Key _fbgAutoKey = UniqueKey();
  Key _fatAutoKey = UniqueKey();

  static const _center = LatLng(33.3573, 44.4415);
  static const _cacheVersion = '3';

  // ── Navigation State ──────────────────────────────────────────
  LatLng? _myLocation;
  bool _fetchingLocation = false;
  List<LatLng> _routePoints = [];
  double _routeDistanceMeters = 0;
  double _routeDurationSeconds = 0;
  List<RouteStep> _routeSteps = [];
  bool _showDirections = false;
  bool _navigating = false;
  FatPoint? _navDestination;

  @override
  void initState() {
    super.initState();
    if (_cachedPoints != null) {
      // Instant load from memory
      _allPoints = _cachedPoints!;
      _allRegions = _cachedRegions!;
      _zones = _cachedZones!;
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _computeFbgHulls());
    } else {
      _loadKml();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Load & Parse ──────────────────────────────────────────────

  Future<File> _getCacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/kml_cache_v$_cacheVersion.json');
  }

  Future<_ParseResult?> _loadFromCache() async {
    try {
      final file = await _getCacheFile();
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['version'] != _cacheVersion) return null;
      final pts = (json['points'] as List).map((e) => FatPoint(
        name: e['name'] as String,
        position: LatLng(e['lat'] as double, e['lng'] as double),
        oltId: e['olt'] as String,
        activationStatus: e['status'] as String,
        fdt: e['fdt'] as String,
        project: e['project'] as String,
        zone: e['zone'] as String,
      )).toList();
      final rgns = (json['regions'] as List).map((e) => FdtRegion(
        zoneId: e['zoneId'] as String,
        status: e['status'] as String,
        mahallah: e['mahallah'] as String,
        neighborhood: e['neighborhood'] as String,
        subring: e['subring'] as String,
        regionUsers: e['regionUsers'] as int,
        points: (e['points'] as List)
            .map((p) => LatLng(p['lat'] as double, p['lng'] as double))
            .toList(),
        zone: e['zone'] as String,
      )).toList();
      return _ParseResult(pts, rgns);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveToCache(_ParseResult result) async {
    try {
      final file = await _getCacheFile();
      final data = {
        'version': _cacheVersion,
        'points': result.points.map((p) => {
          'name': p.name,
          'lat': p.position.latitude,
          'lng': p.position.longitude,
          'olt': p.oltId,
          'status': p.activationStatus,
          'fdt': p.fdt,
          'project': p.project,
          'zone': p.zone,
        }).toList(),
        'regions': result.regions.map((r) => {
          'zoneId': r.zoneId,
          'status': r.status,
          'mahallah': r.mahallah,
          'neighborhood': r.neighborhood,
          'subring': r.subring,
          'regionUsers': r.regionUsers,
          'points': r.points.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
          'zone': r.zone,
        }).toList(),
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  /// ترتيب طبيعي يأخذ الأرقام بعين الاعتبار (FBG12 قبل FBG112)
  static int _naturalSort(String a, String b) {
    final re = RegExp(r'(\d+)|(\D+)');
    final partsA = re.allMatches(a).toList();
    final partsB = re.allMatches(b).toList();
    for (int i = 0; i < partsA.length && i < partsB.length; i++) {
      final pa = partsA[i].group(0)!;
      final pb = partsB[i].group(0)!;
      final na = int.tryParse(pa);
      final nb = int.tryParse(pb);
      final cmp = (na != null && nb != null)
          ? na.compareTo(nb)
          : pa.compareTo(pb);
      if (cmp != 0) return cmp;
    }
    return partsA.length.compareTo(partsB.length);
  }

  void _computeFbgHulls() {
    final groups = <String, List<LatLng>>{};
    for (final p in _allPoints) {
      if (p.fdt.isNotEmpty) {
        groups.putIfAbsent(p.fdt, () => []).add(p.position);
      }
    }
    final hulls = <String, List<LatLng>>{};
    final colors = <String, Color>{};
    int i = 0;
    for (final entry in groups.entries) {
      if (entry.value.length >= 3) {
        hulls[entry.key] = _convexHull(entry.value);
      }
      colors[entry.key] = HSLColor.fromAHSL(
        1.0, (i * 43.0) % 360.0, 0.75, 0.55).toColor();
      i++;
    }
    if (mounted) {
      setState(() {
        _fbgHulls = hulls;
        _fbgColors = colors;
        _fbgs = ['الكل', ...groups.keys.toList()..sort(_naturalSort)];
      });
    }
  }

  List<LatLng> _convexHull(List<LatLng> pts) {
    if (pts.length < 3) return pts;
    final sorted = [...pts]..sort((a, b) {
      final c = a.longitude.compareTo(b.longitude);
      return c != 0 ? c : a.latitude.compareTo(b.latitude);
    });

    double cross(LatLng O, LatLng A, LatLng B) =>
        (A.longitude - O.longitude) * (B.latitude - O.latitude) -
        (A.latitude - O.latitude) * (B.longitude - O.longitude);

    final hull = <LatLng>[];
    for (final p in sorted) {
      while (hull.length >= 2 && cross(hull[hull.length - 2], hull.last, p) <= 0) {
        hull.removeLast();
      }
      hull.add(p);
    }
    final lower = hull.length + 1;
    for (final p in sorted.reversed) {
      while (hull.length >= lower && cross(hull[hull.length - 2], hull.last, p) <= 0) {
        hull.removeLast();
      }
      hull.add(p);
    }
    hull.removeLast();
    return hull;
  }

  // ══════════════════════════════════════════════════════════════
  // Navigation — GPS + OSRM Routing
  // ══════════════════════════════════════════════════════════════

  Future<void> _startNavigation(FatPoint destination) async {
    setState(() { _fetchingLocation = true; });

    try {
      // 1. طلب صلاحية الموقع
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        if (mounted) {
          _showNavError('لا توجد صلاحية للوصول إلى الموقع');
        }
        return;
      }

      // 2. جلب الموقع الحالي
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final myPos = LatLng(pos.latitude, pos.longitude);

      // 3. جلب المسار من OSRM
      final route = await _fetchOsrmRoute(myPos, destination.position);
      if (route == null) {
        if (mounted) _showNavError('تعذّر جلب المسار — تحقق من الاتصال');
        return;
      }

      if (mounted) {
        setState(() {
          _myLocation = myPos;
          _routePoints = route['points'] as List<LatLng>;
          _routeDistanceMeters = route['distance'] as double;
          _routeDurationSeconds = route['duration'] as double;
          _routeSteps = route['steps'] as List<RouteStep>;
          _navDestination = destination;
          _navigating = true;
          _fetchingLocation = false;
          _selectedPoint = destination;
          _selectedRegion = null;
        });
        // حرك الكاميرا لتشمل المسار كاملاً
        _fitRoute(myPos, destination.position);
      }
    } catch (e) {
      if (mounted) _showNavError('خطأ: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  Future<Map<String, dynamic>?> _fetchOsrmRoute(
      LatLng origin, LatLng dest) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${dest.longitude},${dest.latitude}'
        '?overview=full&geometries=geojson&steps=true&annotations=false';

    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') return null;

    final route = (data['routes'] as List).first as Map<String, dynamic>;
    final distMeters = (route['distance'] as num).toDouble();
    final durSeconds = (route['duration'] as num).toDouble();

    // إحداثيات المسار
    final coords = (route['geometry']['coordinates'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();

    // خطوات الاتجاهات
    final steps = <RouteStep>[];
    final legs = route['legs'] as List;
    for (final leg in legs) {
      for (final step in leg['steps'] as List) {
        final maneuver = step['maneuver'] as Map<String, dynamic>;
        final type = maneuver['type']?.toString() ?? '';
        final modifier = maneuver['modifier']?.toString() ?? '';
        final street = step['name']?.toString() ?? '';
        final dist = (step['distance'] as num).toDouble();

        steps.add(RouteStep(
          instruction: _buildInstruction(type, modifier, street, dist),
          streetName: street,
          distanceMeters: dist,
          icon: _stepIcon(type, modifier),
        ));
      }
    }

    return {
      'points': coords,
      'distance': distMeters,
      'duration': durSeconds,
      'steps': steps,
    };
  }

  String _buildInstruction(
      String type, String modifier, String street, double dist) {
    final streetPart = street.isNotEmpty ? ' على $street' : '';
    final distPart = dist > 0 ? ' — ${_formatDist(dist)}' : '';

    switch (type) {
      case 'depart':
        return 'انطلق$streetPart$distPart';
      case 'arrive':
        return '🎯 وصلت إلى الوجهة';
      case 'turn':
        if (modifier == 'right') return 'انعطف يميناً$streetPart$distPart';
        if (modifier == 'left') return 'انعطف يساراً$streetPart$distPart';
        if (modifier == 'slight right') return 'انعطف قليلاً يميناً$streetPart$distPart';
        if (modifier == 'slight left') return 'انعطف قليلاً يساراً$streetPart$distPart';
        if (modifier == 'sharp right') return 'انعطف حاداً يميناً$streetPart$distPart';
        if (modifier == 'sharp left') return 'انعطف حاداً يساراً$streetPart$distPart';
        if (modifier == 'uturn') return 'استدر$streetPart$distPart';
        return 'انعطف$streetPart$distPart';
      case 'new name':
        return 'استمر$streetPart$distPart';
      case 'continue':
        return 'استمر$streetPart$distPart';
      case 'merge':
        return 'ادمج مع$streetPart$distPart';
      case 'fork':
        if (modifier.contains('right')) return 'خذ المسار الأيمن$distPart';
        if (modifier.contains('left')) return 'خذ المسار الأيسر$distPart';
        return 'استمر في الطريق$distPart';
      case 'roundabout':
        return 'أدخل الدوار ثم اخرج$streetPart$distPart';
      case 'exit roundabout':
        return 'اخرج من الدوار$streetPart$distPart';
      case 'rotary':
        return 'أدخل الدوار$streetPart$distPart';
      default:
        return 'استمر$streetPart$distPart';
    }
  }

  IconData _stepIcon(String type, String modifier) {
    if (type == 'arrive') return Icons.flag_rounded;
    if (type == 'depart') return Icons.my_location_rounded;
    if (type == 'roundabout' || type == 'rotary' || type == 'exit roundabout') {
      return Icons.roundabout_left_rounded;
    }
    switch (modifier) {
      case 'right':       return Icons.turn_right_rounded;
      case 'left':        return Icons.turn_left_rounded;
      case 'slight right':return Icons.turn_slight_right_rounded;
      case 'slight left': return Icons.turn_slight_left_rounded;
      case 'sharp right': return Icons.turn_sharp_right_rounded;
      case 'sharp left':  return Icons.turn_sharp_left_rounded;
      case 'uturn':       return Icons.u_turn_right_rounded;
      default:            return Icons.straight_rounded;
    }
  }

  String _formatDist(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} كم';
    }
    return '${meters.round()} م';
  }

  String _formatDuration(double seconds) {
    final mins = (seconds / 60).round();
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return m > 0 ? '$h س $m د' : '$h ساعة';
    }
    return '$mins دقيقة';
  }

  void _fitRoute(LatLng origin, LatLng dest) {
    final minLat = origin.latitude < dest.latitude ? origin.latitude : dest.latitude;
    final maxLat = origin.latitude > dest.latitude ? origin.latitude : dest.latitude;
    final minLng = origin.longitude < dest.longitude ? origin.longitude : dest.longitude;
    final maxLng = origin.longitude > dest.longitude ? origin.longitude : dest.longitude;
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
    double zoom = 14;
    if (maxDiff > 0.1) zoom = 11;
    else if (maxDiff > 0.05) zoom = 12;
    else if (maxDiff > 0.02) zoom = 13;
    _mapController.move(center, zoom);
  }

  /// تمركز الخريطة وزوم على مجموعة نقاط
  void _fitToPoints(List<LatLng> pts, {double minZoom = 14}) {
    if (pts.isEmpty) return;
    if (pts.length == 1) {
      _mapController.move(pts.first, 16.0);
      return;
    }
    double minLat = pts.first.latitude, maxLat = pts.first.latitude;
    double minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final maxDiff = (maxLat - minLat) > (maxLng - minLng)
        ? (maxLat - minLat)
        : (maxLng - minLng);
    double zoom = minZoom;
    if (maxDiff > 0.1) zoom = 11;
    else if (maxDiff > 0.05) zoom = 12;
    else if (maxDiff > 0.02) zoom = 13;
    else if (maxDiff > 0.01) zoom = 14;
    else if (maxDiff > 0.005) zoom = 15;
    _mapController.move(center, zoom);
  }

  void _clearNavigation() {
    setState(() {
      _navigating = false;
      _routePoints = [];
      _routeSteps = [];
      _routeDistanceMeters = 0;
      _routeDurationSeconds = 0;
      _navDestination = null;
      _showDirections = false;
    });
  }

  void _showNavError(String msg) {
    setState(() => _fetchingLocation = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.cairo()),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadKml() async {
    try {
      // Try cache first (much faster than parsing 7.5MB XML)
      _ParseResult? result = await _loadFromCache();

      if (result == null) {
        final xmlString = await rootBundle.loadString('assets/maps/merged.kml');
        result = await compute(_parseKml, xmlString);
        _saveToCache(result!); // fire and forget
      }

      final parsed = result;
      final zonesSet = <String>{};
      for (final p in parsed.points) {
        if (p.zone.isNotEmpty) zonesSet.add(p.zone);
      }
      for (final r in parsed.regions) {
        if (r.zone.isNotEmpty) zonesSet.add(r.zone);
      }

      if (!mounted) return;
      final zonesList = ['الكل', ...zonesSet.toList()..sort()];

      // Save to static memory cache for instant re-entry
      _cachedPoints = parsed.points;
      _cachedRegions = parsed.regions;
      _cachedZones = zonesList;

      setState(() {
        _allPoints = parsed.points;
        _allRegions = parsed.regions;
        _zones = zonesList;
        _loading = false;
      });

      _computeFbgHulls();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Filtered lists ────────────────────────────────────────────

  List<String> get _fbgsForZone {
    final set = <String>{};
    for (final p in _allPoints) {
      if (_selectedZone != 'الكل' && p.zone != _selectedZone) continue;
      if (p.fdt.isNotEmpty) set.add(p.fdt);
    }
    return ['الكل', ...set.toList()..sort()];
  }

  // يُعيد اسم FAT بدون لاحقة -FBGxxxx (FAT1-FBG1040 → FAT1)
  static String _fatDisplayName(String fullName) =>
      fullName.replaceAll(RegExp(r'-FBG\d+$', caseSensitive: false), '').trim();

  List<String> get _fatsForFbg {
    final seen = <String>{};
    for (final p in _allPoints) {
      if (_selectedZone != 'الكل' && p.zone != _selectedZone) continue;
      if (_selectedFbg != 'الكل' && p.fdt != _selectedFbg) continue;
      seen.add(_fatDisplayName(p.name));
    }
    final names = seen.toList()..sort(_naturalSort);
    return ['الكل', ...names];
  }

  Map<String, List<LatLng>> get _visibleFbgHulls {
    if (!_showFbgBorders) return {};
    if (_selectedZone == 'الكل' && _selectedFbg == 'الكل') return _fbgHulls;
    final fbgsInZone = <String>{};
    for (final p in _allPoints) {
      if (_selectedZone != 'الكل' && p.zone != _selectedZone) continue;
      if (p.fdt.isNotEmpty) fbgsInZone.add(p.fdt);
    }
    if (_selectedFbg != 'الكل') {
      return {if (_fbgHulls.containsKey(_selectedFbg)) _selectedFbg: _fbgHulls[_selectedFbg]!};
    }
    return Map.fromEntries(_fbgHulls.entries.where((e) => fbgsInZone.contains(e.key)));
  }

  List<FatPoint> get _visiblePoints {
    if (!_showPoints) return [];
    return _allPoints.where((p) {
      if (_selectedZone != 'الكل' && p.zone != _selectedZone) return false;
      if (_selectedFbg != 'الكل' && p.fdt != _selectedFbg) return false;
      if (_selectedFat != 'الكل' && _fatDisplayName(p.name) != _selectedFat) return false;
      if (_showOnlyActive && !p.isActive) return false;
      return true;
    }).toList();
  }

  List<FdtRegion> get _visibleRegions {
    if (!_showRegions) return [];
    return _allRegions.where((r) {
      if (_selectedZone != 'الكل' && r.zone != _selectedZone) return false;
      return true;
    }).toList();
  }

  // ── Colors ────────────────────────────────────────────────────

  Color _polygonColor(FdtRegion r) {
    final h = r.zoneId.hashCode;
    return HSLColor.fromAHSL(0.30, (h.abs() % 360).toDouble(), 0.65, 0.55)
        .toColor();
  }

  Color _markerColor(FatPoint p) =>
      p.isActive ? const Color(0xFF22C55E) : const Color(0xFFF97316);

  // ══════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        body: _loading
            ? _buildLoading()
            : _error != null
                ? _buildError()
                : _buildContent(),
      ),
    );
  }

  // ── Loading ───────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: _accent),
          const SizedBox(height: 20),
          Text(
            'جاري تحميل بيانات الزونات...',
            style: GoogleFonts.cairo(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'يُعالج الملف في الخلفية',
            style: GoogleFonts.cairo(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 56),
          const SizedBox(height: 16),
          Text(
            'فشل تحميل الخريطة',
            style: GoogleFonts.cairo(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? '',
            style: GoogleFonts.cairo(color: Colors.white54, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              _cachedPoints = null;
              _cachedRegions = null;
              _cachedZones = null;
              setState(() {
                _loading = true;
                _error = null;
              });
              _loadKml();
            },
            icon: const Icon(Icons.refresh),
            label: Text('إعادة المحاولة', style: GoogleFonts.cairo()),
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
          ),
        ],
      ),
    );
  }

  // ── Main content ──────────────────────────────────────────────

  Widget _buildContent() {
    return Stack(
      children: [
        _buildMap(),
        // back button
        Positioned(
          top: 12,
          right: 12,
          child: _buildTopBar(),
        ),
        // ── Floating action buttons (search + options) ────
        Positioned(
          top: 12,
          left: 12,
          child: Column(
            children: [
              _floatingBtn(
                Icons.search_rounded,
                'بحث',
                () => _showSearchSheet(context),
              ),
              const SizedBox(height: 8),
              _floatingBtn(
                Icons.tune_rounded,
                'خيارات',
                () => _showOptionsSheet(context),
              ),
            ],
          ),
        ),
        // ── Active filter chip ────────────────────────────
        if (_selectedFbg != 'الكل' || _selectedFat != 'الكل')
          Positioned(
            top: 12,
            left: 80,
            right: 80,
            child: _buildActiveFilters(),
          ),
        // detail sheet
        if (_selectedPoint != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildPointSheet(_selectedPoint!),
          ),
        if (_selectedRegion != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildRegionSheet(_selectedRegion!),
          ),
        // ── Route info bar (top, when navigating) ──────
        if (_navigating)
          Positioned(
            top: 64,
            left: 12,
            right: 12,
            child: _buildRouteBar(),
          ),
        // ── Loading indicator (fetching location) ───────
        if (_fetchingLocation)
          Positioned(
            top: 64,
            left: 0,
            right: 0,
            child: Center(child: _buildLoadingNav()),
          ),
        // ── Directions panel ────────────────────────────
        if (_navigating && _showDirections)
          Positioned(
            top: 120,
            left: 12,
            bottom: 12,
            width: 280,
            child: _buildDirectionsPanel(),
          ),
      ],
    );
  }

  Widget _floatingBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Material(
      color: _surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: _accent, size: 20),
        ),
      ),
    );
  }

  Widget _buildActiveFilters() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        if (_selectedFbg != 'الكل')
          _filterChip(_selectedFbg, () {
            setState(() {
              _selectedFbg = 'الكل';
              _selectedFat = 'الكل';
              _fbgAutoKey = UniqueKey();
              _fatAutoKey = UniqueKey();
            });
          }),
        if (_selectedFat != 'الكل')
          _filterChip(_selectedFat, () {
            setState(() {
              _selectedFat = 'الكل';
              _fatAutoKey = UniqueKey();
            });
          }),
      ],
    );
  }

  Widget _filterChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textDirection: TextDirection.ltr,
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                color: Colors.white54, size: 14),
          ),
        ],
      ),
    );
  }

  void _showSearchSheet(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black38,
      builder: (ctx) => Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 50, left: 16, right: 16),
          child: Material(
            color: Colors.transparent,
            child: _SearchSheet(
        fbgAutoKey: _fbgAutoKey,
        fatAutoKey: _fatAutoKey,
        selectedFbg: _selectedFbg,
        selectedFat: _selectedFat,
        fbgsForZone: _fbgsForZone,
        fatsForFbg: _fatsForFbg,
        onSearch: (fbg, fat) {
          setState(() {
            _selectedFbg = fbg;
            _selectedFat = fat;
            _fbgAutoKey = UniqueKey();
            _fatAutoKey = UniqueKey();
          });
          // zoom to selection
          if (fbg != 'الكل') {
            final pts = _allPoints
                .where((p) => p.fdt == fbg)
                .map((p) => p.position)
                .toList();
            _fitToPoints(pts);
          }
          if (fat != 'الكل') {
            final matches = _allPoints.where(
              (p) =>
                  _fatDisplayName(p.name) == fat &&
                  (fbg == 'الكل' || p.fdt == fbg),
            ).toList();
            if (matches.isNotEmpty) {
              _mapController.move(matches.first.position, 17.0);
              setState(() {
                _selectedPoint = matches.first;
                _selectedRegion = null;
              });
            }
          }
          Navigator.pop(ctx);
        },
      ),
          ),
        ),
      ),
    );
  }

  void _showOptionsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'الطبقات',
              style: GoogleFonts.cairo(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            _layerToggle('نقاط FAT', Icons.wifi_tethering, _showPoints,
                const Color(0xFF22C55E), (v) {
              setState(() => _showPoints = v);
              (ctx as Element).markNeedsBuild();
            }),
            _layerToggle('مناطق FDT', Icons.map_outlined, _showRegions,
                _accent, (v) {
              setState(() => _showRegions = v);
              (ctx as Element).markNeedsBuild();
            }),
            _layerToggle('حدود FBG', Icons.border_outer_rounded,
                _showFbgBorders, const Color(0xFFFFD700), (v) {
              setState(() => _showFbgBorders = v);
              (ctx as Element).markNeedsBuild();
            }),
            _layerToggle('المفعّلة فقط', Icons.check_circle_outline,
                _showOnlyActive, const Color(0xFFF97316), (v) {
              setState(() => _showOnlyActive = v);
              (ctx as Element).markNeedsBuild();
            }),
            const SizedBox(height: 14),
            Text(
              'الإحصائيات',
              style: GoogleFonts.cairo(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            _statRow('إجمالي FAT', _visiblePoints.length.toString(),
                const Color(0xFF22C55E)),
            _statRow(
                'المفعّل',
                _visiblePoints.where((p) => p.isActive).length.toString(),
                const Color(0xFF22C55E)),
            _statRow(
                'غير مفعّل',
                _visiblePoints.where((p) => !p.isActive).length.toString(),
                const Color(0xFFF97316)),
            _statRow('مناطق FDT', _visibleRegions.length.toString(), _accent),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────

  Widget _buildTopBar() {
    return _topBtn(
      Icons.arrow_back_rounded,
      'رجوع',
      () => Navigator.pop(context),
    );
  }

  // ── Navigation UI Widgets ─────────────────────────────────────

  Widget _buildLoadingNav() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E40AF),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('جاري تحديد موقعك...',
              style: GoogleFonts.cairo(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildRouteBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E40AF).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.5)),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.navigation_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _navDestination?.name ?? '',
                  style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_formatDist(_routeDistanceMeters)}  •  '
                  '${_formatDuration(_routeDurationSeconds)}',
                  style: GoogleFonts.cairo(
                      color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          // زر الاتجاهات
          GestureDetector(
            onTap: () => setState(() => _showDirections = !_showDirections),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _showDirections
                    ? const Color(0xFF3B82F6)
                    : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.format_list_numbered_rtl,
                      color: Colors.white, size: 14),
                  const SizedBox(width: 4),
                  Text('الاتجاهات',
                      style: GoogleFonts.cairo(
                          color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // زر إلغاء الملاحة
          GestureDetector(
            onTap: _clearNavigation,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.redAccent, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 12)],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.turn_right_rounded,
                    color: Color(0xFF3B82F6), size: 18),
                const SizedBox(width: 8),
                Text(
                  'الاتجاهات (${_routeSteps.length} خطوة)',
                  style: GoogleFonts.cairo(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12),
                ),
              ],
            ),
          ),
          // Steps list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _routeSteps.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: Colors.white12, height: 1),
              itemBuilder: (_, i) {
                final step = _routeSteps[i];
                final isLast = i == _routeSteps.length - 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isLast
                              ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                              : const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          step.icon,
                          color: isLast
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF3B82F6),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              step.instruction,
                              style: GoogleFonts.cairo(
                                  color: Colors.white, fontSize: 12),
                            ),
                            if (step.distanceMeters > 0 && !isLast)
                              Text(
                                _formatDist(step.distanceMeters),
                                style: GoogleFonts.cairo(
                                    color: Colors.white38, fontSize: 10),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }

  Widget _statChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: GoogleFonts.cairo(
            color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ── Side Panel ────────────────────────────────────────────────

  // _buildSidePanel removed — replaced by floating search/options buttons

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.cairo(
          color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: const Color(0xFF1E293B),
        style: GoogleFonts.cairo(color: Colors.white, fontSize: 12),
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.arrow_drop_down, color: Colors.white38, size: 18),
        items: items.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  // Searchable autocomplete field for FBG / FAT
  Widget _buildSearchField({
    required Key key,
    required String hint,
    required String selected,
    required List<String> options,
    required ValueChanged<String> onSelected,
    required VoidCallback onCleared,
  }) {
    final isActive = selected != 'الكل' && selected.isNotEmpty;
    return Autocomplete<String>(
      key: key,
      initialValue: isActive ? TextEditingValue(text: selected) : null,
      optionsBuilder: (tv) {
        final q = tv.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: (v) => onSelected(v == 'الكل' ? 'الكل' : v),
      fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          textDirection: TextDirection.ltr,
          style: GoogleFonts.cairo(color: Colors.white, fontSize: 12),
          textAlign: TextAlign.left,
          decoration: InputDecoration(
            hintText: isActive ? selected : hint,
            hintStyle: GoogleFonts.cairo(
              color: isActive ? Colors.white70 : Colors.white38,
              fontSize: 11,
            ),
            prefixIcon: const Icon(Icons.search_rounded,
                color: Colors.white38, size: 16),
            suffixIcon: isActive
                ? GestureDetector(
                    onTap: () {
                      ctrl.clear();
                      onCleared();
                    },
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 15),
                  )
                : null,
            filled: true,
            fillColor: isActive
                ? _accent.withValues(alpha: 0.12)
                : Colors.white10,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: isActive ? _accent : Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: isActive ? _accent : Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _accent),
            ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSel, opts) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 220,
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8)
                ],
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (_, i) {
                  final opt = opts.elementAt(i);
                  return InkWell(
                    onTap: () => onSel(opt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        border: i > 0
                            ? const Border(
                                top: BorderSide(color: Colors.white12))
                            : null,
                      ),
                      child: Text(
                        opt,
                        textDirection: opt == 'الكل'
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        style: GoogleFonts.cairo(
                          color: opt == 'الكل'
                              ? Colors.white38
                              : Colors.white,
                          fontSize: 12,
                        ),
                        textAlign: opt == 'الكل'
                            ? TextAlign.right
                            : TextAlign.left,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _layerToggle(
    String label,
    IconData icon,
    bool value,
    Color color,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: value ? color : Colors.white24, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.cairo(
                color: value ? Colors.white : Colors.white38,
                fontSize: 12,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: color,
              inactiveTrackColor: Colors.white12,
              inactiveThumbColor: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.cairo(color: Colors.white54, fontSize: 11),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              style: GoogleFonts.cairo(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ── Map ───────────────────────────────────────────────────────

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 11.5,
        onTap: (tapPos, latLng) => setState(() {
          _selectedPoint = null;
          _selectedRegion = null;
        }),
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.sadara.alsadara',
        ),
        // FBG zone borders (convex hull per FBG)
        if (_showFbgBorders && _visibleFbgHulls.isNotEmpty)
          PolygonLayer(
            polygons: _visibleFbgHulls.entries.map((e) {
              final color = _fbgColors[e.key] ?? _accent;
              final isSelected = _selectedFbg == e.key;
              return Polygon(
                points: e.value,
                color: isSelected
                    ? color.withValues(alpha: 0.10)
                    : Colors.transparent,
                borderColor: isSelected
                    ? color
                    : color.withValues(alpha: 0.55),
                borderStrokeWidth: isSelected ? 6.0 : 3.5,
              );
            }).toList(),
          ),
        if (_showRegions)
          PolygonLayer(
            polygons: _visibleRegions.map((r) {
              final color = _polygonColor(r);
              final isSelected = _selectedRegion?.zoneId == r.zoneId;
              return Polygon(
                points: r.points,
                color: isSelected
                    ? color.withValues(alpha: 0.55)
                    : color,
                borderColor: isSelected ? Colors.white : color.withValues(alpha: 0.7),
                borderStrokeWidth: isSelected ? 2.5 : 1.2,
              );
            }).toList(),
          ),
        if (_showPoints)
          MarkerLayer(
            markers: _visiblePoints.map(_buildMarker).toList(),
          ),
        // ── Route polyline ──────────────────────────────────
        if (_navigating && _routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: const Color(0xFF3B82F6),
                strokeWidth: 5.0,
              ),
              Polyline(
                points: _routePoints,
                color: Colors.white.withValues(alpha: 0.35),
                strokeWidth: 8.0,
              ),
            ],
          ),
        // ── My location marker ──────────────────────────────
        if (_myLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _myLocation!,
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Marker _buildMarker(FatPoint p) {
    final color = _markerColor(p);
    final isSelected = _selectedPoint?.name == p.name;
    final sz = isSelected ? 30.0 : 18.0;
    return Marker(
      point: p.position,
      width: sz,
      height: sz,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedPoint = p;
          _selectedRegion = null;
          _mapController.move(p.position, _mapController.camera.zoom);
        }),
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Icon(
              Icons.location_on,
              color: color,
              size: sz,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: isSelected ? 8 : 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            Positioned(
              top: sz * 0.07,
              child: Icon(
                Icons.wifi_rounded,
                color: Colors.white,
                size: sz * 0.40,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Legend ────────────────────────────────────────────────────

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendRow(const Color(0xFF22C55E), 'FAT مفعّل'),
          const SizedBox(height: 4),
          _legendRow(const Color(0xFFF97316), 'FAT غير مفعّل'),
          const SizedBox(height: 4),
          _legendRow(
              HSLColor.fromAHSL(0.5, 200, 0.65, 0.55).toColor(), 'منطقة FDT'),
          const SizedBox(height: 4),
          _legendRowBorder(const Color(0xFFFFD700), 'حدود FBG'),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  Widget _legendRowBorder(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color, width: 2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.cairo(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  // ── Detail Sheets ─────────────────────────────────────────────

  Widget _buildPointSheet(FatPoint p) {
    final color = _markerColor(p);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, -4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.wifi_tethering, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      p.zone,
                      style: GoogleFonts.cairo(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // status badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text(
                  p.isActive ? 'مفعّل' : 'غير مفعّل',
                  style: GoogleFonts.cairo(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectedPoint = null),
                child: const Icon(Icons.close, color: Colors.white38, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              if (p.oltId.isNotEmpty) _infoField('OLT', p.oltId),
              if (p.fdt.isNotEmpty) _infoField('FDT', p.fdt),
              if (p.project.isNotEmpty) _infoField('المشروع', p.project),
              _infoField(
                'الإحداثيات',
                '${p.position.latitude.toStringAsFixed(5)}, '
                    '${p.position.longitude.toStringAsFixed(5)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          // ── زر ابدأ الملاحة ───────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _fetchingLocation
                  ? null
                  : () => _startNavigation(p),
              icon: _fetchingLocation
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.navigation_rounded, size: 18),
              label: Text(
                _fetchingLocation ? 'جاري التحديد...' : 'ابدأ الملاحة',
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegionSheet(FdtRegion r) {
    final color = _polygonColor(r);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 16, offset: Offset(0, -4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.map_outlined, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  r.zoneId.isNotEmpty ? r.zoneId : 'منطقة FDT',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              if (r.regionUsers > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${r.regionUsers} مستخدم',
                    style: GoogleFonts.cairo(
                        color: _accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _selectedRegion = null),
                child: const Icon(Icons.close, color: Colors.white38, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            children: [
              if (r.subring.isNotEmpty) _infoField('Sub-ring', r.subring),
              if (r.mahallah.isNotEmpty) _infoField('المحلة', r.mahallah),
              if (r.neighborhood.isNotEmpty)
                _infoField('الحي', r.neighborhood),
              if (r.status.isNotEmpty) _infoField('الحالة', r.status),
              _infoField('المنطقة', r.zone),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.cairo(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ── Search Bottom Sheet ─────────────────────────────────────────

class _SearchSheet extends StatefulWidget {
  final Key fbgAutoKey;
  final Key fatAutoKey;
  final String selectedFbg;
  final String selectedFat;
  final List<String> fbgsForZone;
  final List<String> fatsForFbg;
  final void Function(String fbg, String fat) onSearch;

  const _SearchSheet({
    required this.fbgAutoKey,
    required this.fatAutoKey,
    required this.selectedFbg,
    required this.selectedFat,
    required this.fbgsForZone,
    required this.fatsForFbg,
    required this.onSearch,
  });

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late String _fbg;
  late String _fat;
  late List<String> _currentFats;

  @override
  void initState() {
    super.initState();
    _fbg = widget.selectedFbg;
    _fat = widget.selectedFat;
    _currentFats = widget.fatsForFbg;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // FBG field
          _sheetField(
            label: 'FBG',
            hint: 'اكتب رقم FBG...',
            selected: _fbg,
            options: widget.fbgsForZone,
            onSelected: (v) => setState(() {
              _fbg = v;
              _fat = 'الكل';
            }),
            onCleared: () => setState(() {
              _fbg = 'الكل';
              _fat = 'الكل';
            }),
          ),
          const SizedBox(height: 10),
          // FAT field
          _sheetField(
            label: 'FAT',
            hint: 'اكتب رقم FAT...',
            selected: _fat,
            options: _currentFats,
            onSelected: (v) => setState(() => _fat = v),
            onCleared: () => setState(() => _fat = 'الكل'),
          ),
          const SizedBox(height: 14),
          // Search + Clear buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => widget.onSearch(_fbg, _fat),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: Text('بحث', style: GoogleFonts.cairo(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0EA5E9),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (_fbg != 'الكل' || _fat != 'الكل') ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    widget.onSearch('الكل', 'الكل');
                  },
                  child: Text(
                    'مسح',
                    style: GoogleFonts.cairo(color: Colors.white54),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _sheetField({
    required String label,
    required String hint,
    required String selected,
    required List<String> options,
    required ValueChanged<String> onSelected,
    required VoidCallback onCleared,
  }) {
    final isActive = selected != 'الكل' && selected.isNotEmpty;
    return Autocomplete<String>(
      initialValue: isActive ? TextEditingValue(text: selected) : null,
      optionsBuilder: (tv) {
        final q = tv.text.trim().toLowerCase();
        if (q.isEmpty) return options;
        return options.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: (v) => onSelected(v == 'الكل' ? 'الكل' : v),
      fieldViewBuilder: (ctx, ctrl, focusNode, onSubmit) {
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          textDirection: TextDirection.ltr,
          style: GoogleFonts.cairo(color: Colors.white, fontSize: 13),
          textAlign: TextAlign.left,
          decoration: InputDecoration(
            labelText: label,
            labelStyle: GoogleFonts.cairo(color: Colors.white38, fontSize: 12),
            hintText: isActive ? selected : hint,
            hintStyle: GoogleFonts.cairo(
              color: isActive ? Colors.white70 : Colors.white38,
              fontSize: 12,
            ),
            prefixIcon:
                const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
            suffixIcon: isActive
                ? GestureDetector(
                    onTap: () {
                      ctrl.clear();
                      onCleared();
                    },
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 16),
                  )
                : null,
            filled: true,
            fillColor:
                isActive ? const Color(0xFF0EA5E9).withValues(alpha: 0.12) : Colors.white10,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isActive ? const Color(0xFF0EA5E9) : Colors.white12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: isActive ? const Color(0xFF0EA5E9) : Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF0EA5E9)),
            ),
          ),
        );
      },
      optionsViewBuilder: (ctx, onSel, opts) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: MediaQuery.of(ctx).size.width - 32,
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8)
                ],
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (_, i) {
                  final opt = opts.elementAt(i);
                  return InkWell(
                    onTap: () => onSel(opt),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        border: i > 0
                            ? const Border(
                                top: BorderSide(color: Colors.white12))
                            : null,
                      ),
                      child: Text(
                        opt,
                        textDirection:
                            opt == 'الكل' ? TextDirection.rtl : TextDirection.ltr,
                        style: GoogleFonts.cairo(
                          color: opt == 'الكل' ? Colors.white38 : Colors.white,
                          fontSize: 12,
                        ),
                        textAlign:
                            opt == 'الكل' ? TextAlign.right : TextAlign.left,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
