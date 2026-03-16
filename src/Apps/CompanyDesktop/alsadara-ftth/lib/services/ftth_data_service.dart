import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// خدمة إدارة بيانات FTTH Dashboard
/// تقوم بتحليل وتخزين بيانات المناطق والاشتراكات
class FtthDataService {
  static FtthDataService? _instance;
  static FtthDataService get instance =>
      _instance ??= FtthDataService._internal();
  FtthDataService._internal();

  /// قائمة بيانات المناطق
  List<ZoneData> _zones = [];
  List<ZoneData> get zones => _zones;

  /// آخر وقت تحديث
  DateTime? _lastUpdate;
  DateTime? get lastUpdate => _lastUpdate;

  /// تحميل البيانات من ملف JSON
  Future<bool> loadFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final content = await file.readAsString();
      final data = jsonDecode(content);

      return _parseData(data);
    } catch (e) {
      print('Error loading FTTH data');
      return false;
    }
  }

  /// تحميل آخر ملف محفوظ
  Future<bool> loadLatestFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('ftth_data_'))
          .toList();

      if (files.isEmpty) return false;

      // ترتيب حسب آخر تعديل
      files
          .sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      return loadFromFile(files.first.path);
    } catch (e) {
      print('Error finding latest FTTH file');
      return false;
    }
  }

  /// تحليل البيانات من JSON
  bool _parseData(Map<String, dynamic> data) {
    try {
      _zones.clear();

      final charts = data['charts'] as List? ?? [];

      for (final chart in charts) {
        final chartData = chart['data'];
        if (chartData == null) continue;

        final result = chartData['result'];
        if (result == null || result is! List) continue;

        for (final r in result) {
          final rows = r['data'];
          if (rows == null || rows is! List) continue;

          for (final row in rows) {
            if (row is! Map) continue;

            // استخراج بيانات المنطقة
            final zone = _parseZoneFromRow(row);
            if (zone != null) {
              // تحديث أو إضافة
              final existingIndex =
                  _zones.indexWhere((z) => z.zoneName == zone.zoneName);
              if (existingIndex >= 0) {
                _zones[existingIndex] = zone;
              } else {
                _zones.add(zone);
              }
            }
          }
        }
      }

      _lastUpdate = DateTime.now();
      return _zones.isNotEmpty;
    } catch (e) {
      print('Error parsing FTTH data');
      return false;
    }
  }

  /// تحليل صف واحد من البيانات
  ZoneData? _parseZoneFromRow(Map<dynamic, dynamic> row) {
    try {
      // البحث عن اسم المنطقة
      String? zoneName;
      String? userStatus;
      int? count;

      for (final key in row.keys) {
        final value = row[key];
        final keyStr = key.toString().toLowerCase();

        if (keyStr.contains('zone') ||
            keyStr == 'zonename' ||
            keyStr == 'zone_name') {
          zoneName = value?.toString();
        } else if (keyStr.contains('status') ||
            keyStr == 'userstatus' ||
            keyStr == 'user_status') {
          userStatus = value?.toString();
        } else if (keyStr.contains('count') ||
            keyStr == 'count' ||
            keyStr == 'total') {
          count = int.tryParse(value?.toString() ?? '');
        }
      }

      // إذا كان هناك Zone واحد فقط في البيانات
      if (zoneName == null && row.containsKey('Zone')) {
        zoneName = row['Zone']?.toString();
      }
      if (userStatus == null && row.containsKey('userStatus')) {
        userStatus = row['userStatus']?.toString();
      }
      if (count == null && row.containsKey('count')) {
        count = int.tryParse(row['count']?.toString() ?? '');
      }

      if (zoneName == null || zoneName.isEmpty) return null;

      return ZoneData(
        zoneName: zoneName,
        userStatus: userStatus ?? 'Unknown',
        count: count ?? 1,
      );
    } catch (e) {
      return null;
    }
  }

  /// الحصول على إحصائيات المناطق
  ZoneStatistics getStatistics() {
    int total = 0;
    int active = 0;
    int expired = 0;
    int inactive = 0;

    for (final zone in _zones) {
      final count = zone.count;
      total += count;

      switch (zone.userStatus.toLowerCase()) {
        case 'active':
          active += count;
          break;
        case 'expired':
          expired += count;
          break;
        case 'inactive':
          inactive += count;
          break;
      }
    }

    return ZoneStatistics(
      totalZones: _zones.length,
      totalSubscribers: total,
      activeSubscribers: active,
      expiredSubscribers: expired,
      inactiveSubscribers: inactive,
    );
  }

  /// البحث عن منطقة
  List<ZoneData> searchZones(String query) {
    if (query.isEmpty) return _zones;

    final q = query.toLowerCase();
    return _zones.where((z) => z.zoneName.toLowerCase().contains(q)).toList();
  }

  /// الحصول على المناطق حسب الحالة
  List<ZoneData> getZonesByStatus(String status) {
    return _zones
        .where((z) => z.userStatus.toLowerCase() == status.toLowerCase())
        .toList();
  }

  /// تصدير البيانات كـ CSV
  String exportToCsv() {
    final buffer = StringBuffer();
    buffer.writeln('Zone,Status,Count');

    for (final zone in _zones) {
      buffer.writeln('${zone.zoneName},${zone.userStatus},${zone.count}');
    }

    return buffer.toString();
  }

  /// حفظ CSV إلى ملف
  Future<String?> saveCsvToFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/ftth_zones_$timestamp.csv');

      await file.writeAsString(exportToCsv());
      return file.path;
    } catch (e) {
      print('Error saving CSV');
      return null;
    }
  }
}

/// بيانات منطقة واحدة
class ZoneData {
  final String zoneName;
  final String userStatus;
  final int count;

  ZoneData({
    required this.zoneName,
    required this.userStatus,
    required this.count,
  });

  @override
  String toString() => 'ZoneData($zoneName, $userStatus, $count)';
}

/// إحصائيات المناطق
class ZoneStatistics {
  final int totalZones;
  final int totalSubscribers;
  final int activeSubscribers;
  final int expiredSubscribers;
  final int inactiveSubscribers;

  ZoneStatistics({
    required this.totalZones,
    required this.totalSubscribers,
    required this.activeSubscribers,
    required this.expiredSubscribers,
    required this.inactiveSubscribers,
  });

  double get activePercentage =>
      totalSubscribers > 0 ? (activeSubscribers / totalSubscribers * 100) : 0;

  double get expiredPercentage =>
      totalSubscribers > 0 ? (expiredSubscribers / totalSubscribers * 100) : 0;

  double get inactivePercentage =>
      totalSubscribers > 0 ? (inactiveSubscribers / totalSubscribers * 100) : 0;
}
