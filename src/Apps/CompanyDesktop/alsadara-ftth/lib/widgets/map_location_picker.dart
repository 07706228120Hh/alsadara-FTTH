/// ويدجت اختيار الموقع من الخريطة
/// يعرض خريطة تفاعلية لتحديد الإحداثيات بالنقر
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';

/// نتيجة اختيار الموقع
class PickedLocation {
  final double latitude;
  final double longitude;

  const PickedLocation({required this.latitude, required this.longitude});
}

/// دايلوج اختيار الموقع من الخريطة
class MapLocationPicker extends StatefulWidget {
  /// الإحداثيات الابتدائية (إن وُجدت)
  final double? initialLatitude;
  final double? initialLongitude;

  const MapLocationPicker({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  /// يفتح الدايلوج ويعيد الموقع المختار أو null
  static Future<PickedLocation?> show(
    BuildContext context, {
    double? initialLatitude,
    double? initialLongitude,
  }) {
    return showDialog<PickedLocation>(
      context: context,
      barrierDismissible: false,
      builder: (context) => MapLocationPicker(
        initialLatitude: initialLatitude,
        initialLongitude: initialLongitude,
      ),
    );
  }

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  late final MapController _mapController;
  LatLng? _selectedLocation;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  double _currentZoom = 14.0;
  bool _isSatellite = true;

  // بغداد كإحداثيات افتراضية
  static const _defaultLat = 33.312805;
  static const _defaultLng = 44.361488;

  static const _accent = Color(0xFF3498DB);
  static const _textDark = Color(0xFF333333);
  static const _textGray = Color(0xFF999999);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    final hasInitial = widget.initialLatitude != null &&
        widget.initialLongitude != null &&
        widget.initialLatitude != 0 &&
        widget.initialLongitude != 0;

    if (hasInitial) {
      _selectedLocation =
          LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }

    _latCtrl = TextEditingController(
      text: hasInitial ? widget.initialLatitude!.toStringAsFixed(6) : '',
    );
    _lngCtrl = TextEditingController(
      text: hasInitial ? widget.initialLongitude!.toStringAsFixed(6) : '',
    );
  }

  @override
  void dispose() {
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedLocation = point;
      _latCtrl.text = point.latitude.toStringAsFixed(6);
      _lngCtrl.text = point.longitude.toStringAsFixed(6);
    });
  }

  void _goToManualCoords() {
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    if (lat != null && lng != null) {
      final point = LatLng(lat, lng);
      setState(() => _selectedLocation = point);
      _mapController.move(point, _currentZoom);
    }
  }

  void _confirm() {
    if (_selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('يرجى تحديد موقع على الخريطة', style: GoogleFonts.cairo()),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      PickedLocation(
        latitude: _selectedLocation!.latitude,
        longitude: _selectedLocation!.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _selectedLocation ?? const LatLng(_defaultLat, _defaultLng);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.all(24),
        child: Container(
          width: 700,
          height: 560,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              // === Header ===
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_accent, _accent.withOpacity(0.8)],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'تحديد الموقع على الخريطة',
                      style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'انقر على الخريطة لتحديد الموقع',
                      style: GoogleFonts.cairo(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // === Map ===
              Expanded(
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: _currentZoom,
                        onTap: _onTap,
                        onPositionChanged: (pos, _) {
                          if (pos.zoom != null) {
                            _currentZoom = pos.zoom!;
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: _isSatellite
                              ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.alsadara.ftth',
                        ),
                        if (_selectedLocation != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _selectedLocation!,
                                width: 50,
                                height: 50,
                                child: const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_pin,
                                      color: Colors.red,
                                      size: 40,
                                    ),
                                    SizedBox(height: 2),
                                  ],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),

                    // Zoom controls
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Column(
                        children: [
                          _mapBtn(Icons.add, () {
                            _currentZoom = (_currentZoom + 1).clamp(2, 18);
                            _mapController.move(
                                _mapController.camera.center, _currentZoom);
                          }),
                          const SizedBox(height: 4),
                          _mapBtn(Icons.remove, () {
                            _currentZoom = (_currentZoom - 1).clamp(2, 18);
                            _mapController.move(
                                _mapController.camera.center, _currentZoom);
                          }),
                        ],
                      ),
                    ),

                    // Reset to selected marker
                    if (_selectedLocation != null)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: _mapBtn(Icons.my_location, () {
                          _mapController.move(_selectedLocation!, _currentZoom);
                        }),
                      ),

                    // Map layer toggle
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () =>
                              setState(() => _isSatellite = !_isSatellite),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isSatellite
                                      ? Icons.map_outlined
                                      : Icons.satellite_alt,
                                  size: 18,
                                  color: _textDark,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isSatellite ? 'خريطة' : 'قمر صناعي',
                                  style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    color: _textDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // === Coordinates bar ===
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  children: [
                    // Lat field
                    Expanded(
                      child: _coordField(
                        label: 'خط العرض',
                        controller: _latCtrl,
                        icon: Icons.north,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Lng field
                    Expanded(
                      child: _coordField(
                        label: 'خط الطول',
                        controller: _lngCtrl,
                        icon: Icons.east,
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Go button
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: _goToManualCoords,
                        icon: const Icon(Icons.search, size: 16),
                        label: Text('انتقال',
                            style: GoogleFonts.cairo(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // === Actions ===
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_selectedLocation != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${_selectedLocation!.latitude.toStringAsFixed(6)}, ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                              style: GoogleFonts.cairo(
                                color: _textGray,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('إلغاء',
                          style: GoogleFonts.cairo(color: _textGray)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _confirm,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(
                        'تأكيد الموقع',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mapBtn(IconData icon, VoidCallback onTap) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: _textDark),
        ),
      ),
    );
  }

  Widget _coordField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: GoogleFonts.cairo(color: _textDark, fontSize: 12),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(color: _textGray, fontSize: 11),
        prefixIcon: Icon(icon, color: _accent, size: 16),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _accent.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _accent),
          borderRadius: BorderRadius.circular(8),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
