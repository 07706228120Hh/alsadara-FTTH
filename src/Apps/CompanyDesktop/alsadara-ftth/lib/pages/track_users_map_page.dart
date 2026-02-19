/// اسم الصفحة: خريطة تتبع المستخدمين
/// وصف الصفحة: صفحة خريطة تتبع مواقع المستخدمين
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class TrackUsersMapPage extends StatefulWidget {
  const TrackUsersMapPage({super.key});

  @override
  State<TrackUsersMapPage> createState() => _TrackUsersMapPageState();
}

class _TrackUsersMapPageState extends State<TrackUsersMapPage> {
  final String apiUrl =
      'https://script.google.com/macros/s/AKfycbwPlZrDSpjRRUQCAB1EfQwFsk8G4yaRLJvq6rL2I7pvrmnQHzTH3HqBTskW18M6TfWY/exec';
  final Set<Marker> _markers = {};
  bool _loading = true;
  Timer? _timer;

  static const LatLng _defaultCenter = LatLng(33.3573338, 44.4414648);

  @override
  void initState() {
    super.initState();
    _fetchAndUpdateMarkers();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchAndUpdateMarkers();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAndUpdateMarkers() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
    });
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        debugPrint("بيانات من السيرفر: $data");
        final Set<Marker> markers = {};

        for (var item in data) {
          final isActive = item["active"] == true ||
              item["active"] == "1" ||
              item["active"] == 1 ||
              item["active"] == "TRUE" ||
              item["active"] == "true";

          if (isActive &&
              item["lat"] != null &&
              item["lng"] != null &&
              item["lat"].toString().isNotEmpty &&
              item["lng"].toString().isNotEmpty) {
            double? lat = double.tryParse(item["lat"].toString());
            double? lng = double.tryParse(item["lng"].toString());
            if (lat != null && lng != null && lat != 0 && lng != 0) {
              markers.add(
                Marker(
                  markerId: MarkerId(item["اسم المستخدم"] ?? ''),
                  position: LatLng(lat, lng),
                  infoWindow: InfoWindow(
                    title: item["اسم المستخدم"] ?? '',
                    snippet: item["القسم"] ?? '',
                    onTap: () {
                      _showUserDetailsDialog(context, item);
                    },
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure),
                ),
              );
            }
          }
        }
        if (!mounted) return;
        setState(() {
          _markers
            ..clear()
            ..addAll(markers);
        });
      } else {
        debugPrint('فشل في جلب البيانات: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint("خطأ عند جلب المواقع: $e");
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  void _showUserDetailsDialog(BuildContext context, Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(user["اسم المستخدم"] ?? ""),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoTile("القسم", user["القسم"]),
            _infoTile("الصلاحيات", user["الصلاحيات"]),
            _infoTile("المركز", user["المركز"]),
            _infoTile("رقم الهاتف", user["رقم الهاتف"]),
            _infoTile("آخر تحديث", user["last update"]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _infoTile(String title, dynamic value) {
    return value == null || value.toString().isEmpty
        ? const SizedBox()
        : ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              "$title:",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(value.toString()),
          );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تتبع الكادر على الخريطة"),
        backgroundColor: Colors.blue[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAndUpdateMarkers,
            tooltip: "تحديث المواقع",
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _defaultCenter,
              zoom: 12,
            ),
            markers: _markers,
            onMapCreated: (controller) {
              // Map controller callback - not needed for current functionality
            },
          ),
          if (_loading)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
          if (!_loading && _markers.isEmpty)
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  "لا يوجد مستخدمين نشطين حالياً",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
