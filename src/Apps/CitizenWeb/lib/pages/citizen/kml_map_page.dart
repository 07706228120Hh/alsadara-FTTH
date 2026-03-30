import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

// ══════════════════════════════════════════════════════════════
// Models
// ══════════════════════════════════════════════════════════════

class FatPoint {
  final String name;
  final LatLng position;
  final String oltId;
  final String activationStatus;
  final String fdt;
  final String zone;

  const FatPoint({
    required this.name,
    required this.position,
    required this.oltId,
    required this.activationStatus,
    required this.fdt,
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
  final List<LatLng> points;
  final String zone;

  const FdtRegion({
    required this.zoneId,
    required this.status,
    required this.mahallah,
    required this.neighborhood,
    required this.points,
    required this.zone,
  });
}

// ══════════════════════════════════════════════════════════════
// KML Parser — runs in Dart isolate via compute()
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

      // Point → FAT
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
            String oltId = '', activation = '', fdt = '';
            if (schemaData != null) {
              for (final sd in schemaData.findElements('SimpleData')) {
                final n = sd.getAttribute('name') ?? '';
                final v = sd.innerText.trim();
                if (n == 'cab_or_olt_id') oltId = v;
                if (n == 'activation_status') activation = v;
                if (n == 'fdt') fdt = v;
              }
            }
            points.add(
              FatPoint(
                name: pmName,
                position: LatLng(lat, lng),
                oltId: oltId,
                activationStatus: activation,
                fdt: fdt,
                zone: name,
              ),
            );
          }
        }
        continue;
      }

      // Polygon → FDT region
      final polyEl = pm.findElements('Polygon').firstOrNull;
      if (polyEl != null) {
        final coordStr =
            polyEl
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
          String zoneId = '', status = '', mahallah = '', neighborhood = '';
          if (schemaData != null) {
            for (final sd in schemaData.findElements('SimpleData')) {
              final n = sd.getAttribute('name') ?? '';
              final v = sd.innerText.trim();
              if (n == 'ZoneID') zoneId = v;
              if (n == 'Status') status = v;
              if (n == 'mahallah_ar') mahallah = v;
              if (n == 'neighborhood_ar') neighborhood = v;
            }
          }
          regions.add(
            FdtRegion(
              zoneId: zoneId,
              status: status,
              mahallah: mahallah,
              neighborhood: neighborhood,
              points: polyPoints,
              zone: name,
            ),
          );
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
// KML Map Page
// ══════════════════════════════════════════════════════════════

class KmlMapPage extends StatefulWidget {
  const KmlMapPage({super.key});

  @override
  State<KmlMapPage> createState() => _KmlMapPageState();
}

class _KmlMapPageState extends State<KmlMapPage> {
  bool _loading = true;
  String? _error;
  List<FatPoint> _allPoints = [];
  List<FdtRegion> _allRegions = [];
  List<String> _zones = [];

  String _selectedZone = 'الكل';
  bool _showPoints = true;
  bool _showRegions = true;
  bool _showOnlyActive = false;

  FatPoint? _selectedPoint;

  final _mapController = MapController();
  static const _initialCenter = LatLng(33.38, 44.47);

  @override
  void initState() {
    super.initState();
    _loadKml();
  }

  Future<void> _loadKml() async {
    try {
      final xmlString = await rootBundle.loadString('assets/kml/merged.kml');
      final result = await compute(_parseKml, xmlString);

      final zonesSet = <String>{};
      for (final p in result.points) {
        if (p.zone.isNotEmpty) zonesSet.add(p.zone);
      }
      for (final r in result.regions) {
        if (r.zone.isNotEmpty) zonesSet.add(r.zone);
      }

      if (!mounted) return;
      setState(() {
        _allPoints = result.points;
        _allRegions = result.regions;
        _zones = ['الكل', ...zonesSet.toList()..sort()];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<FatPoint> get _visiblePoints {
    if (!_showPoints) return [];
    return _allPoints.where((p) {
      if (_selectedZone != 'الكل' && p.zone != _selectedZone) return false;
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

  Color _polygonColor(FdtRegion r) {
    final h = r.zoneId.hashCode;
    final hue = (h.abs() % 360).toDouble();
    return HSLColor.fromAHSL(0.30, hue, 0.65, 0.50).toColor();
  }

  Color _markerColor(FatPoint p) =>
      p.isActive ? const Color(0xFF2E7D32) : const Color(0xFFE65100);

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        appBar: _buildAppBar(),
        body: _loading
            ? _buildLoading()
            : _error != null
            ? _buildError()
            : _buildMap(),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF1565C0),
      foregroundColor: Colors.white,
      title: const Text(
        'خريطة تغطية الشبكة',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      actions: [
        if (!_loading && _error == null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8, bottom: 8),
            child: Chip(
              backgroundColor: Colors.white12,
              label: Text(
                '${_visiblePoints.length} نقطة FAT',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
            child: Chip(
              backgroundColor: Colors.white12,
              label: Text(
                '${_visibleRegions.length} منطقة',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF1565C0)),
          SizedBox(height: 16),
          Text(
            'جاري تحميل الخريطة...',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          SizedBox(height: 8),
          Text(
            'قد يستغرق ذلك لحظات',
            style: TextStyle(color: Colors.white38, fontSize: 13),
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
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          const Text(
            'فشل تحميل الخريطة',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _error ?? '',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _loadKml();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    return Stack(
      children: [
        // ── FlutterMap ────────────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: 11.5,
            onTap: (tapPos, latLng) => setState(() => _selectedPoint = null),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.sadara.citizen_portal',
            ),
            if (_showRegions)
              PolygonLayer(
                polygons: _visibleRegions.map((r) {
                  final color = _polygonColor(r);
                  return Polygon(
                    points: r.points,
                    color: color,
                    borderColor: color.withValues(alpha: 0.7),
                    borderStrokeWidth: 1.2,
                  );
                }).toList(),
              ),
            if (_showPoints)
              MarkerLayer(markers: _visiblePoints.map(_buildMarker).toList()),
          ],
        ),

        // ── Filter Panel ──────────────────────────────────────
        Positioned(top: 12, right: 12, child: _buildFilterPanel()),

        // ── Legend ────────────────────────────────────────────
        Positioned(
          bottom: _selectedPoint != null ? 200 : 12,
          right: 12,
          child: _buildLegend(),
        ),

        // ── Detail Sheet ──────────────────────────────────────
        if (_selectedPoint != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildPointSheet(_selectedPoint!),
          ),
      ],
    );
  }

  Marker _buildMarker(FatPoint p) {
    final color = _markerColor(p);
    final isSelected = _selectedPoint?.name == p.name;
    return Marker(
      point: p.position,
      width: isSelected ? 34 : 26,
      height: isSelected ? 34 : 26,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedPoint = p;
          _mapController.move(p.position, _mapController.camera.zoom);
        }),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.yellow : Colors.white,
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: isSelected ? 8 : 4,
                spreadRadius: isSelected ? 2 : 1,
              ),
            ],
          ),
          child: Icon(
            Icons.wifi_tethering,
            color: Colors.white,
            size: isSelected ? 16 : 12,
          ),
        ),
      ),
    );
  }

  // ── Filter Panel ─────────────────────────────────────────────

  Widget _buildFilterPanel() {
    return Container(
      width: 195,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha:0.93),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, color: Colors.white70, size: 14),
              SizedBox(width: 6),
              Text(
                'الفلاتر',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'المنطقة',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _selectedZone,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A2B3C),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              underline: const SizedBox.shrink(),
              icon: const Icon(
                Icons.arrow_drop_down,
                color: Colors.white54,
                size: 18,
              ),
              items: _zones
                  .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedZone = v ?? 'الكل'),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          _buildToggle(
            'نقاط FAT',
            Icons.wifi_tethering,
            _showPoints,
            (v) => setState(() => _showPoints = v),
            const Color(0xFF2E7D32),
          ),
          _buildToggle(
            'مناطق FDT',
            Icons.map_outlined,
            _showRegions,
            (v) => setState(() => _showRegions = v),
            const Color(0xFF1565C0),
          ),
          _buildToggle(
            'المفعّلة فقط',
            Icons.check_circle_outline,
            _showOnlyActive,
            (v) => setState(() => _showOnlyActive = v),
            const Color(0xFFE65100),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(
    String label,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
    Color color,
  ) {
    return Row(
      children: [
        Icon(icon, color: value ? color : Colors.white38, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: value ? Colors.white : Colors.white54,
              fontSize: 12,
            ),
          ),
        ),
        Transform.scale(
          scale: 0.72,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: color,
            inactiveTrackColor: Colors.white12,
            inactiveThumbColor: Colors.white38,
          ),
        ),
      ],
    );
  }

  // ── Legend ────────────────────────────────────────────────────

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha:0.9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendItem(const Color(0xFF2E7D32), 'FAT مفعّل'),
          const SizedBox(height: 4),
          _legendItem(const Color(0xFFE65100), 'FAT غير مفعّل'),
          const SizedBox(height: 4),
          _legendItem(
            HSLColor.fromAHSL(0.5, 210, 0.65, 0.50).toColor(),
            'منطقة FDT',
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
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
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  // ── Detail Sheet ──────────────────────────────────────────────

  Widget _buildPointSheet(FatPoint p) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _markerColor(p).withValues(alpha:0.4)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 12,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _markerColor(p).withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.wifi_tethering,
                  color: _markerColor(p),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      p.zone,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _markerColor(p).withValues(alpha:0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _markerColor(p).withValues(alpha:0.4)),
                ),
                child: Text(
                  p.isActive ? 'مفعّل' : 'غير مفعّل',
                  style: TextStyle(
                    color: _markerColor(p),
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
          const SizedBox(height: 10),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              if (p.oltId.isNotEmpty) _infoChip('OLT', p.oltId),
              if (p.fdt.isNotEmpty) _infoChip('FDT', p.fdt),
              _infoChip(
                'إحداثيات',
                '${p.position.latitude.toStringAsFixed(4)}, '
                    '${p.position.longitude.toStringAsFixed(4)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
