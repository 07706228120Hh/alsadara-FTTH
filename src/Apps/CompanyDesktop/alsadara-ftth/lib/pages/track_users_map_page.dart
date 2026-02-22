/// اسم الصفحة: خريطة تتبع المستخدمين المطورة
/// وصف الصفحة: صفحة خريطة تتبع مواقع المستخدمين مع دعم العمل بدون إنترنت ورسم المسارات
/// المؤلف: تطبيق السدارة
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

class TrackUsersMapPage extends StatefulWidget {
  const TrackUsersMapPage({super.key});

  @override
  State<TrackUsersMapPage> createState() => _TrackUsersMapPageState();
}

class _TrackUsersMapPageState extends State<TrackUsersMapPage> {
  final String apiUrl =
      'https://script.google.com/macros/s/AKfycbwPlZrDSpjRRUQCAB1EfQwFsk8G4yaRLJvq6rL2I7pvrmnQHzTH3HqBTskW18M6TfWY/exec';

  final MapController _mapController = MapController();
  final Map<String, List<LatLng>> _userPaths = {};
  final Set<String> _hiddenPaths = {}; // قائمة المستخدمين المخفي مسارهم
  String _searchQuery = "";

  List<Marker> _markers = [];
  List<dynamic> _rawData = []; // البيانات الخام لغرض الفلترة
  bool _loading = true;
  Timer? _timer;
  MbTilesTileProvider? _mbtilesProvider;

  static const LatLng _defaultCenter = LatLng(33.3573338, 44.4414648);

  @override
  void initState() {
    super.initState();
    _initOfflineMap();
    _fetchAndUpdateMarkers();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchAndUpdateMarkers();
    });
  }

  Future<void> _initOfflineMap() async {
    try {
      // نسخ ملف MBTiles من assets إلى مجلد التطبيق المحلي
      final appDir = await getApplicationDocumentsDirectory();
      final mbtilesFile = File('${appDir.path}/iraq.mbtiles');

      if (!await mbtilesFile.exists()) {
        // محاولة نسخ الملف من assets
        try {
          final data = await rootBundle.load('assets/maps/iraq.mbtiles');
          await mbtilesFile.writeAsBytes(
            data.buffer.asUint8List(),
            flush: true,
          );
          debugPrint('تم نسخ ملف MBTiles إلى: ${mbtilesFile.path}');
        } catch (e) {
          debugPrint('ملف iraq.mbtiles غير موجود في الـ assets: $e');
          return;
        }
      }

      final provider = MbTilesTileProvider.fromPath(path: mbtilesFile.path);

      setState(() {
        _mbtilesProvider = provider;
      });
      debugPrint("تم تفعيل نظام الخرائط المحلية بنجاح.");
    } catch (e) {
      debugPrint(
        "تنبيه: لم يتم العثور على ملف iraq.mbtiles في الـ assets، سيتم التحميل عبر الإنترنت: $e",
      );
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
    setState(() {
      _loading = true;
    });
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        _rawData = data;
        _applyFilters();
      }
    } catch (e) {
      debugPrint("خطأ عند جلب المواقع: $e");
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  void _applyFilters() {
    final List<Marker> newMarkers = [];

    for (var item in _rawData) {
      final userName = item["اسم المستخدم"] ?? 'غير معروف';
      final department = item["القسم"] ?? '';

      // التصفية حسب البحث
      if (_searchQuery.isNotEmpty &&
          !userName.toLowerCase().contains(_searchQuery.toLowerCase()) &&
          !department.toLowerCase().contains(_searchQuery.toLowerCase())) {
        continue;
      }

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
          final pos = LatLng(lat, lng);

          // تحديث المسار
          if (!_userPaths.containsKey(userName)) {
            _userPaths[userName] = [];
          }
          if (_userPaths[userName]!.isEmpty ||
              _userPaths[userName]!.last != pos) {
            _userPaths[userName]!.add(pos);
            if (_userPaths[userName]!.length > 50) {
              _userPaths[userName]!.removeAt(0);
            }
          }

          newMarkers.add(
            Marker(
              point: pos,
              width: 80,
              height: 80,
              child: GestureDetector(
                onTap: () => _showUserDetailsDialog(context, item),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue[900]!, width: 1),
                      ),
                      child: Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.location_on, color: Colors.blue, size: 40),
                  ],
                ),
              ),
            ),
          );
        }
      }
    }
    setState(() {
      _markers = newMarkers;
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

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final users = _userPaths.keys.toList();
          return DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: "بحث عن فني...",
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (val) {
                        setState(() => _searchQuery = val);
                        _applyFilters();
                        setSheetState(() {});
                      },
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final user = users[index];
                        final isHidden = _hiddenPaths.contains(user);
                        return ListTile(
                          title: Text(user),
                          trailing: IconButton(
                            icon: Icon(
                              isHidden
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: isHidden ? Colors.grey : Colors.blue,
                            ),
                            onPressed: () {
                              setState(() {
                                if (isHidden) {
                                  _hiddenPaths.remove(user);
                                } else {
                                  _hiddenPaths.add(user);
                                }
                              });
                              setSheetState(() {});
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("تتبع الفنيين - خريطة ذكية"),
        backgroundColor: Colors.blue[900],
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
            tooltip: "تصفية الفنيين والمسارات",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAndUpdateMarkers,
            tooltip: "تحديث المواقع",
          ),
        ],
      ),
      body: Stack(
        children: [
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
                tileProvider:
                    _mbtilesProvider, // سيستخدم MBTiles إذا توفر، وإلا سيعود للـ URL
              ),
              PolylineLayer(
                polylines: _userPaths.entries
                    .where(
                  (e) => !_hiddenPaths.contains(e.key),
                ) // إخفاء المسارات المختارة
                    .map((entry) {
                  return Polyline(
                    points: entry.value,
                    color: Colors.blue.withOpacity(0.6),
                    strokeWidth: 4,
                  );
                }).toList(),
              ),
              MarkerLayer(markers: _markers),
            ],
          ),
          if (_loading)
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
