import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// خدمة التخزين المحلي للبيانات
/// تستخدم لتخزين بيانات المشتركين والإعدادات محلياً
class LocalCacheService {
  static LocalCacheService? _instance;
  static LocalCacheService get instance =>
      _instance ??= LocalCacheService._internal();

  LocalCacheService._internal();

  // مفاتيح التخزين
  static const String _subscribersKey = 'cached_subscribers';
  static const String _subscribersTimestampKey = 'subscribers_timestamp';
  static const String _regionsKey = 'cached_regions';
  static const String _plansKey = 'cached_plans';

  // مدة صلاحية الكاش (24 ساعة افتراضياً)
  static const Duration cacheValidity = Duration(hours: 24);

  /// الحصول على مسار مجلد التخزين
  Future<Directory> get _cacheDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/alsadara_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تخزين المشتركين
  // ═══════════════════════════════════════════════════════════════════════════

  /// حفظ قائمة المشتركين محلياً
  Future<bool> saveSubscribers(List<Map<String, dynamic>> subscribers) async {
    try {
      final cacheDir = await _cacheDirectory;
      final file = File('${cacheDir.path}/subscribers.json');

      // حفظ البيانات
      await file.writeAsString(json.encode({
        'timestamp': DateTime.now().toIso8601String(),
        'count': subscribers.length,
        'data': subscribers,
      }));

      // حفظ وقت التحديث في SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _subscribersTimestampKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_subscribersKey, subscribers.length);

      print('✅ تم حفظ ${subscribers.length} مشترك محلياً');
      return true;
    } catch (e) {
      print('❌ خطأ في حفظ المشتركين: $e');
      return false;
    }
  }

  /// جلب المشتركين المخزنين محلياً
  Future<List<Map<String, dynamic>>?> getSubscribers() async {
    try {
      final cacheDir = await _cacheDirectory;
      final file = File('${cacheDir.path}/subscribers.json');

      if (!await file.exists()) {
        print('⚠️ لا توجد بيانات مخزنة للمشتركين');
        return null;
      }

      final content = await file.readAsString();
      final data = json.decode(content);

      final subscribers = (data['data'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      print('📂 تم جلب ${subscribers.length} مشترك من التخزين المحلي');
      return subscribers;
    } catch (e) {
      print('❌ خطأ في جلب المشتركين: $e');
      return null;
    }
  }

  /// التحقق من صلاحية الكاش
  Future<bool> isSubscribersCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_subscribersTimestampKey);

      if (timestamp == null) return false;

      final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
      final now = DateTime.now();

      return now.difference(cacheTime) < cacheValidity;
    } catch (e) {
      return false;
    }
  }

  /// جلب وقت آخر تحديث للمشتركين
  Future<DateTime?> getSubscribersLastUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_subscribersTimestampKey);
      if (timestamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      return null;
    }
  }

  /// جلب عدد المشتركين المخزنين
  Future<int> getSubscribersCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_subscribersKey) ?? 0;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تخزين المناطق
  // ═══════════════════════════════════════════════════════════════════════════

  /// حفظ قائمة المناطق محلياً
  Future<bool> saveRegions(List<Map<String, dynamic>> regions) async {
    try {
      final cacheDir = await _cacheDirectory;
      final file = File('${cacheDir.path}/regions.json');

      await file.writeAsString(json.encode({
        'timestamp': DateTime.now().toIso8601String(),
        'data': regions,
      }));

      print('✅ تم حفظ ${regions.length} منطقة محلياً');
      return true;
    } catch (e) {
      print('❌ خطأ في حفظ المناطق: $e');
      return false;
    }
  }

  /// جلب المناطق المخزنة محلياً
  Future<List<Map<String, dynamic>>?> getRegions() async {
    try {
      final cacheDir = await _cacheDirectory;
      final file = File('${cacheDir.path}/regions.json');

      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final data = json.decode(content);

      return (data['data'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('❌ خطأ في جلب المناطق: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تخزين الباقات
  // ═══════════════════════════════════════════════════════════════════════════

  /// حفظ قائمة الباقات محلياً
  Future<bool> savePlans(List<Map<String, dynamic>> plans) async {
    try {
      final cacheDir = await _cacheDirectory;
      final file = File('${cacheDir.path}/plans.json');

      await file.writeAsString(json.encode({
        'timestamp': DateTime.now().toIso8601String(),
        'data': plans,
      }));

      print('✅ تم حفظ ${plans.length} باقة محلياً');
      return true;
    } catch (e) {
      print('❌ خطأ في حفظ الباقات: $e');
      return false;
    }
  }

  /// جلب الباقات المخزنة محلياً
  Future<List<Map<String, dynamic>>?> getPlans() async {
    try {
      final cacheDir = await _cacheDirectory;
      final file = File('${cacheDir.path}/plans.json');

      if (!await file.exists()) return null;

      final content = await file.readAsString();
      final data = json.decode(content);

      return (data['data'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      print('❌ خطأ في جلب الباقات: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // البحث في البيانات المخزنة
  // ═══════════════════════════════════════════════════════════════════════════

  /// البحث في المشتركين المخزنين
  Future<List<Map<String, dynamic>>> searchSubscribers({
    String? name,
    String? phone,
    String? region,
    String? plan,
    String? status,
  }) async {
    final subscribers = await getSubscribers();
    if (subscribers == null) return [];

    return subscribers.where((sub) {
      if (name != null &&
          name.isNotEmpty &&
          !(sub['name']
                  ?.toString()
                  .toLowerCase()
                  .contains(name.toLowerCase()) ??
              false)) {
        return false;
      }
      if (phone != null &&
          phone.isNotEmpty &&
          !(sub['phone']?.toString().contains(phone) ?? false)) {
        return false;
      }
      if (region != null &&
          region.isNotEmpty &&
          sub['region']?.toString() != region) {
        return false;
      }
      if (plan != null && plan.isNotEmpty && sub['plan']?.toString() != plan) {
        return false;
      }
      if (status != null &&
          status.isNotEmpty &&
          sub['status']?.toString() != status) {
        return false;
      }
      return true;
    }).toList();
  }

  /// الحصول على المشتركين المنتهية اشتراكاتهم
  Future<List<Map<String, dynamic>>> getExpiredSubscribers() async {
    final subscribers = await getSubscribers();
    if (subscribers == null) return [];

    final now = DateTime.now();
    return subscribers.where((sub) {
      final expiryStr = sub['expiry'] ?? sub['expiryDate'] ?? sub['expires'];
      if (expiryStr == null) return false;

      try {
        final expiry = DateTime.parse(expiryStr.toString());
        return expiry.isBefore(now);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  /// الحصول على المشتركين القريبة من الانتهاء (خلال أيام معينة)
  Future<List<Map<String, dynamic>>> getExpiringSubscribers(
      {int withinDays = 7}) async {
    final subscribers = await getSubscribers();
    if (subscribers == null) return [];

    final now = DateTime.now();
    final futureDate = now.add(Duration(days: withinDays));

    return subscribers.where((sub) {
      final expiryStr = sub['expiry'] ?? sub['expiryDate'] ?? sub['expires'];
      if (expiryStr == null) return false;

      try {
        final expiry = DateTime.parse(expiryStr.toString());
        return expiry.isAfter(now) && expiry.isBefore(futureDate);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // إدارة الكاش
  // ═══════════════════════════════════════════════════════════════════════════

  /// مسح جميع البيانات المخزنة
  Future<bool> clearAllCache() async {
    try {
      final cacheDir = await _cacheDirectory;
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_subscribersKey);
      await prefs.remove(_subscribersTimestampKey);
      await prefs.remove(_regionsKey);
      await prefs.remove(_plansKey);

      print('🗑️ تم مسح جميع البيانات المخزنة');
      return true;
    } catch (e) {
      print('❌ خطأ في مسح الكاش: $e');
      return false;
    }
  }

  /// الحصول على حجم الكاش
  Future<String> getCacheSize() async {
    try {
      final cacheDir = await _cacheDirectory;
      if (!await cacheDir.exists()) return '0 KB';

      int totalSize = 0;
      await for (final file in cacheDir.list(recursive: true)) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      if (totalSize < 1024) {
        return '$totalSize B';
      } else if (totalSize < 1024 * 1024) {
        return '${(totalSize / 1024).toStringAsFixed(1)} KB';
      } else {
        return '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    } catch (e) {
      return 'غير معروف';
    }
  }

  /// معلومات الكاش
  Future<Map<String, dynamic>> getCacheInfo() async {
    final lastUpdate = await getSubscribersLastUpdate();
    final count = await getSubscribersCount();
    final size = await getCacheSize();
    final isValid = await isSubscribersCacheValid();

    return {
      'lastUpdate': lastUpdate?.toString() ?? 'لم يتم التحديث',
      'subscribersCount': count,
      'cacheSize': size,
      'isValid': isValid,
      'validityHours': cacheValidity.inHours,
    };
  }
}
