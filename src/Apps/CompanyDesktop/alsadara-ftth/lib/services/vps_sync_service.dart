import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api/api_client.dart';
import 'api/api_config.dart';
import 'local_cache_service.dart';
import 'local_database_service.dart';
import 'custom_auth_service.dart';
import 'vps_auth_service.dart';
import 'ftth_settings_service.dart';

/// خدمة تنزيل بيانات المشتركين من VPS (بدل الاتصال المباشر بـ FTTH)
///
/// التدفق:
///   FTTH Server → VPS Background Sync → VPS Database
///                                            ↓
///   Flutter App ← /download أو /updated-since ← VPS API
///                                            ↓
///                                       Local Cache
class VpsSyncService extends ChangeNotifier {
  static final VpsSyncService _instance = VpsSyncService._internal();
  static VpsSyncService get instance => _instance;

  VpsSyncService._internal();

  static final _client = ApiClient.instance;
  static final _localCache = LocalCacheService.instance;
  static final _localDb = LocalDatabaseService.instance;

  Timer? _autoSyncTimer;

  // حالة التنزيل
  bool _isSyncing = false;
  String _statusMessage = '';
  double _progress = 0; // 0.0 → 1.0
  VpsSyncResult? _lastResult;
  DateTime? _lastSuccessfulSync;

  bool get isSyncing => _isSyncing;
  String get statusMessage => _statusMessage;
  double get progress => _progress;
  VpsSyncResult? get lastResult => _lastResult;
  DateTime? get lastSuccessfulSync => _lastSuccessfulSync;

  static String? get _tenantId =>
      CustomAuthService().currentTenantId ??
      VpsAuthService.instance.currentCompanyId;

  /// فحص هل توجد بيانات على السيرفر قبل التنزيل
  static Future<VpsServerCheck> checkServerData() async {
    final tenantId = _tenantId;
    if (tenantId == null) {
      return VpsServerCheck(available: false, error: 'لا يوجد tenant');
    }

    try {
      // استخدام sync-status لمعرفة عدد المشتركين على السيرفر
      final status = await FtthSettingsService.getSyncStatus(tenantId);
      if (status == null) {
        return VpsServerCheck(
            available: false, error: 'لا يمكن الاتصال بالسيرفر');
      }

      final configured = status['configured'] == true;
      final serverCount = status['currentDbCount'] ?? 0;
      final lastSync = status['lastSyncAt'] != null
          ? DateTime.tryParse(status['lastSyncAt'])
          : null;

      if (!configured) {
        return VpsServerCheck(
          available: false,
          error: 'لم يتم إعداد مزامنة FTTH بعد',
        );
      }

      if (serverCount == 0) {
        return VpsServerCheck(
          available: false,
          serverCount: 0,
          lastServerSync: lastSync,
          error: 'لا توجد بيانات على السيرفر — قم بتشغيل المزامنة أولاً',
        );
      }

      // مقارنة مع الكاش المحلي
      final localCount = await _localCache.getSubscribersCount();
      final localUpdate = await _localCache.getSubscribersLastUpdate();

      return VpsServerCheck(
        available: true,
        serverCount: serverCount,
        localCount: localCount,
        lastServerSync: lastSync,
        lastLocalUpdate: localUpdate,
      );
    } catch (e) {
      return VpsServerCheck(available: false, error: 'فشل فحص السيرفر');
    }
  }

  /// تنزيل البيانات من VPS وتخزينها محلياً
  /// يستخدم التحديث التزايدي إذا كان هناك كاش محلي
  Future<VpsSyncResult> syncFromVps() async {
    if (_isSyncing) {
      debugPrint('⚠️ VPS sync already in progress');
      return VpsSyncResult(success: false, error: 'التنزيل قيد التنفيذ بالفعل');
    }

    final tenantId = _tenantId;
    debugPrint('🔍 VPS sync: tenantId = $tenantId');
    if (tenantId == null) {
      debugPrint('❌ VPS sync: no tenantId');
      _showError('لا يوجد tenant — تأكد من تسجيل الدخول');
      return VpsSyncResult(success: false, error: 'لا يوجد tenant');
    }

    _isSyncing = true;
    _progress = 0;
    _statusMessage = 'جاري فحص البيانات...';
    notifyListeners();

    try {
      // فحص السيرفر أولاً
      _statusMessage = 'جاري فحص بيانات السيرفر...';
      _progress = 0.05;
      notifyListeners();

      final check = await checkServerData();
      debugPrint(
          '📊 VPS check: available=${check.available}, server=${check.serverCount}, error=${check.error}');
      if (!check.available) {
        final result = VpsSyncResult(
            success: false, error: check.error ?? 'لا توجد بيانات');
        _finish(result);
        return result;
      }

      _statusMessage = 'توجد ${check.serverCount} مشترك — جاري التنزيل...';
      _progress = 0.1;
      notifyListeners();

      // تحقق من آخر تحديث محلي
      final lastUpdate = await _localCache.getSubscribersLastUpdate();

      VpsSyncResult result;
      if (lastUpdate != null) {
        result = await _incrementalSync(tenantId, lastUpdate);
      } else {
        result = await _fullDownload(tenantId);
      }

      _finish(result);
      return result;
    } catch (e) {
      final result = VpsSyncResult(success: false, error: 'فشل المزامنة: $e');
      _finish(result);
      return result;
    }
  }

  /// إعادة تنزيل كامل (تجاهل الكاش)
  Future<VpsSyncResult> forceFullSync() async {
    if (_isSyncing) {
      return VpsSyncResult(success: false, error: 'التنزيل قيد التنفيذ بالفعل');
    }

    final tenantId = _tenantId;
    if (tenantId == null) {
      _showError('لا يوجد tenant — تأكد من تسجيل الدخول');
      return VpsSyncResult(success: false, error: 'لا يوجد tenant');
    }

    _isSyncing = true;
    _progress = 0;
    _statusMessage = 'جاري فحص السيرفر...';
    notifyListeners();

    try {
      final check = await checkServerData();
      if (!check.available) {
        final result = VpsSyncResult(
            success: false, error: check.error ?? 'لا توجد بيانات');
        _finish(result);
        return result;
      }

      _statusMessage = 'جاري تنزيل ${check.serverCount} مشترك...';
      _progress = 0.1;
      notifyListeners();

      final result = await _fullDownload(tenantId);
      _finish(result);
      return result;
    } catch (e) {
      final result = VpsSyncResult(success: false, error: 'فشل التنزيل: $e');
      _finish(result);
      return result;
    }
  }

  void _finish(VpsSyncResult result) {
    _isSyncing = false;
    _lastResult = result;
    if (result.success) _lastSuccessfulSync = DateTime.now();
    // عند الخطأ نبقي progress > 0 لإظهار رسالة الخطأ في الواجهة
    _progress = result.success ? 1.0 : 0.01;
    _statusMessage = result.success
        ? (result.isIncremental
            ? (result.downloadedCount == 0
                ? 'لا توجد تحديثات جديدة'
                : 'تم تحديث ${result.downloadedCount} مشترك')
            : 'تم تنزيل ${result.totalCount} مشترك')
        : (result.error ?? 'فشل');
    debugPrint(
        '📋 VPS sync finished: success=${result.success}, msg=$_statusMessage');
    notifyListeners();

    // إعادة تعيين الحالة بعد 5 ثواني
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isSyncing) {
        _progress = 0;
        _statusMessage = '';
        notifyListeners();
      }
    });
  }

  /// إظهار خطأ مؤقت في الواجهة (للحالات التي لا يتم فيها تشغيل _finish)
  void _showError(String message) {
    _statusMessage = message;
    _progress = 0.01;
    _lastResult = VpsSyncResult(success: false, error: message);
    notifyListeners();
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isSyncing) {
        _progress = 0;
        _statusMessage = '';
        notifyListeners();
      }
    });
  }

  /// تنزيل كامل من VPS (أول مرة أو إعادة تعيين)
  Future<VpsSyncResult> _fullDownload(String tenantId) async {
    _statusMessage = 'جاري تنزيل البيانات الكاملة...';
    _progress = 0.2;
    notifyListeners();

    final url = ApiConfig.subscriberCacheDownload(tenantId);
    debugPrint('📥 VPS download: GET $url');

    // الباك اند يُرجع { success: true, count: N, data: [...] }
    // ApiClient يفك الـ wrapper تلقائياً ويُرسل body['data'] للـ parser
    // لذلك الـ parser يستقبل List مباشرة (ليس Map)
    final res = await _client.get(
      url,
      (json) => json, // نستقبل أي نوع — قد يكون List أو Map
      useInternalKey: true,
    );

    debugPrint(
        '📥 VPS download result: success=${res.success}, hasData=${res.data != null}, type=${res.data?.runtimeType}, msg=${res.message}, status=${res.statusCode}');

    if (!res.success || res.data == null) {
      return VpsSyncResult(
          success: false,
          error: res.message ?? 'فشل تنزيل البيانات (${res.statusCode})');
    }

    _statusMessage = 'جاري معالجة البيانات...';
    _progress = 0.6;
    notifyListeners();

    // ApiClient يفك wrapper { success, data } تلقائياً
    // لذلك res.data يكون إما:
    //   - List (body['data'] — المصفوفة مباشرة)
    //   - Map (body كاملاً إذا لم يُفك)
    List subscribers;
    int count;
    if (res.data is List) {
      subscribers = res.data as List;
      count = subscribers.length;
    } else if (res.data is Map) {
      final data = res.data as Map<String, dynamic>;
      subscribers = data['data'] as List? ?? [];
      count = data['count'] ?? subscribers.length;
    } else {
      return VpsSyncResult(success: false, error: 'تنسيق بيانات غير متوقع');
    }
    debugPrint('📥 VPS download: received $count subscribers');
    // تحويل PascalCase → camelCase (VPS يُرجع PascalCase)
    final list = _listToCamelCase(subscribers);

    _statusMessage = 'جاري حفظ $count مشترك محلياً...';
    _progress = 0.8;
    notifyListeners();

    // حفظ في LocalCacheService (للمزامنة التزايدية)
    await _localCache.saveSubscribers(list);

    // حفظ في LocalDatabaseService (لصفحة التخزين المحلي)
    await _localDb.batchInsertSubscribers(list);

    _progress = 1.0;
    notifyListeners();

    return VpsSyncResult(
      success: true,
      totalCount: count,
      downloadedCount: list.length,
      isIncremental: false,
    );
  }

  /// تحديث تزايدي — جلب التحديثات فقط منذ آخر مزامنة
  Future<VpsSyncResult> _incrementalSync(
      String tenantId, DateTime since) async {
    _statusMessage = 'جاري جلب التحديثات...';
    _progress = 0.2;
    notifyListeners();

    final res = await _client.get(
      ApiConfig.subscriberCacheUpdatedSince(tenantId, since),
      (json) => json, // نستقبل أي نوع
      useInternalKey: true,
    );

    if (!res.success || res.data == null) {
      return VpsSyncResult(
          success: false, error: res.message ?? 'فشل جلب التحديثات');
    }

    _progress = 0.5;
    notifyListeners();

    // نفس المنطق — ApiClient قد يفك الـ wrapper
    List updates;
    int updatedCount;
    if (res.data is List) {
      updates = res.data as List;
      updatedCount = updates.length;
    } else if (res.data is Map) {
      final data = res.data as Map<String, dynamic>;
      updates = data['data'] as List? ?? [];
      updatedCount = data['count'] ?? updates.length;
    } else {
      return VpsSyncResult(success: false, error: 'تنسيق بيانات غير متوقع');
    }

    if (updates.isEmpty) {
      return VpsSyncResult(
        success: true,
        totalCount: 0,
        downloadedCount: 0,
        isIncremental: true,
        message: 'لا توجد تحديثات جديدة',
      );
    }

    _statusMessage = 'جاري دمج $updatedCount تحديث...';
    _progress = 0.7;
    notifyListeners();

    // تحويل PascalCase → camelCase
    final camelUpdates = _listToCamelCase(updates);

    // دمج التحديثات مع الكاش المحلي
    final existing = await _localCache.getSubscribers() ?? [];
    final existingMap = <String, Map<String, dynamic>>{};
    for (final sub in existing) {
      final id = sub['subscriptionId']?.toString() ?? '';
      if (id.isNotEmpty) existingMap[id] = sub;
    }

    int newCount = 0;
    int updCount = 0;
    for (final update in camelUpdates) {
      final id = update['subscriptionId']?.toString() ?? '';
      if (id.isEmpty) continue;

      if (existingMap.containsKey(id)) {
        existingMap[id] = update;
        updCount++;
      } else {
        existingMap[id] = update;
        newCount++;
      }
    }

    _statusMessage = 'جاري الحفظ...';
    _progress = 0.9;
    notifyListeners();

    final mergedList = existingMap.values.toList();
    // حفظ في LocalCacheService (للمزامنة التزايدية)
    await _localCache.saveSubscribers(mergedList);

    // حفظ التحديثات في LocalDatabaseService (لصفحة التخزين المحلي)
    await _localDb.batchInsertSubscribers(camelUpdates);

    return VpsSyncResult(
      success: true,
      totalCount: existingMap.length,
      downloadedCount: updatedCount,
      newCount: newCount,
      updatedCount: updCount,
      isIncremental: true,
    );
  }

  // ═══════════════════════════════════════
  // المزامنة التلقائية
  // ═══════════════════════════════════════

  /// مزامنة عند الحاجة — تُزامن إذا:
  /// 1. لا توجد بيانات محلية (أول مرة)
  /// 2. مرّ أكثر من [minInterval] منذ آخر مزامنة ناجحة
  /// تُستخدم عند فتح صفحة التخزين المحلي لضمان البيانات محدثة
  Future<VpsSyncResult?> syncIfNeeded({
    Duration minInterval = const Duration(minutes: 5),
  }) async {
    if (_isSyncing) return null;

    // إذا لم تمر مدة كافية منذ آخر مزامنة ناجحة، لا حاجة
    if (_lastSuccessfulSync != null) {
      final elapsed = DateTime.now().difference(_lastSuccessfulSync!);
      if (elapsed < minInterval) {
        debugPrint(
            '⏭️ VPS syncIfNeeded: skipped (last sync ${elapsed.inSeconds}s ago)');
        return null;
      }
    }

    // فحص إذا توجد بيانات محلية
    final localCount = await _localCache.getSubscribersCount();
    if (localCount == 0) {
      // لا توجد بيانات — تنزيل كامل
      debugPrint('📥 VPS syncIfNeeded: no local data, starting full sync');
      return syncFromVps();
    }

    // توجد بيانات — تحديث تزايدي
    debugPrint('🔄 VPS syncIfNeeded: checking for updates');
    return syncFromVps();
  }

  /// بدء المزامنة التلقائية (تُستدعى عند فتح التطبيق)
  void startAutoSync({Duration interval = const Duration(minutes: 30)}) {
    // تنزيل أولي صامت بعد 5 ثواني
    Future.delayed(const Duration(seconds: 5), () {
      _silentSync();
    });

    // تكرار كل interval
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(interval, (_) {
      _silentSync();
    });

    debugPrint('🔄 VPS Auto-sync started (interval: ${interval.inMinutes}min)');
  }

  /// إيقاف المزامنة التلقائية
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    debugPrint('⏹️ VPS Auto-sync stopped');
  }

  /// مزامنة صامتة (لا تُظهر أي شيء عند النجاح بدون تحديثات)
  Future<void> _silentSync() async {
    if (_isSyncing) return;

    final tenantId = _tenantId;
    if (tenantId == null) return;

    // لا نريد إظهار progress bar للمزامنة التلقائية إلا إذا كان أول تنزيل
    final lastUpdate = await _localCache.getSubscribersLastUpdate();
    final isFirstTime = lastUpdate == null;

    if (isFirstTime) {
      // أول مرة — نفحص السيرفر أولاً
      final check = await checkServerData();
      if (!check.available || check.serverCount == 0) return;
    }

    _isSyncing = true;
    // لا نُظهر progress إلا إذا كان أول مرة
    if (isFirstTime) {
      _statusMessage = 'جاري تنزيل البيانات تلقائياً...';
      _progress = 0.1;
      notifyListeners();
    }

    try {
      VpsSyncResult result;
      if (isFirstTime) {
        result = await _fullDownload(tenantId);
      } else {
        // تحديث تزايدي صامت
        final res = await _client.get(
          ApiConfig.subscriberCacheUpdatedSince(tenantId, lastUpdate),
          (json) => json, // نستقبل أي نوع
          useInternalKey: true,
        );

        if (!res.success || res.data == null) {
          _isSyncing = false;
          notifyListeners();
          return;
        }

        // ApiClient قد يفك الـ wrapper تلقائياً
        List updates;
        if (res.data is List) {
          updates = res.data as List;
        } else if (res.data is Map) {
          updates = (res.data as Map)['data'] as List? ?? [];
        } else {
          _isSyncing = false;
          notifyListeners();
          return;
        }
        if (updates.isEmpty) {
          _isSyncing = false;
          notifyListeners();
          return; // لا تحديثات — صامت تماماً
        }

        // يوجد تحديثات — نُظهر progress
        _statusMessage = 'جاري تحديث ${updates.length} مشترك...';
        _progress = 0.5;
        notifyListeners();

        // تحويل PascalCase → camelCase ثم دمج
        final camelUpdates = _listToCamelCase(updates);
        final existing = await _localCache.getSubscribers() ?? [];
        final map = <String, Map<String, dynamic>>{};
        for (final sub in existing) {
          final id = sub['subscriptionId']?.toString() ?? '';
          if (id.isNotEmpty) map[id] = sub;
        }
        for (final u in camelUpdates) {
          final id = u['subscriptionId']?.toString() ?? '';
          if (id.isNotEmpty) map[id] = u;
        }
        await _localCache.saveSubscribers(map.values.toList());
        // حفظ في LocalDatabaseService أيضاً
        await _localDb.batchInsertSubscribers(camelUpdates);

        result = VpsSyncResult(
          success: true,
          totalCount: map.length,
          downloadedCount: updates.length,
          isIncremental: true,
        );
      }

      _finish(result);
      debugPrint(
          '✅ VPS auto-sync: ${result.totalCount} total, ${result.downloadedCount} downloaded');
    } catch (e) {
      _isSyncing = false;
      _progress = 0;
      _statusMessage = '';
      notifyListeners();
      debugPrint('❌ VPS auto-sync error: $e');
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  /// تحويل مفاتيح Map من PascalCase إلى camelCase
  /// VPS API يُرجع PascalCase (مثل SubscriptionId) لأن ASP.NET PropertyNamingPolicy = null
  /// لكن LocalDatabaseService يتوقع camelCase (مثل subscriptionId)
  static Map<String, dynamic> _toCamelCase(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (key.isEmpty) return MapEntry(key, value);
      final camel = key[0].toLowerCase() + key.substring(1);
      return MapEntry(camel, value);
    });
  }

  /// تحويل قائمة Maps من PascalCase إلى camelCase
  static List<Map<String, dynamic>> _listToCamelCase(List items) {
    return items
        .map((e) => _toCamelCase(Map<String, dynamic>.from(e)))
        .toList();
  }
}

/// نتيجة فحص بيانات السيرفر
class VpsServerCheck {
  final bool available;
  final int serverCount;
  final int localCount;
  final DateTime? lastServerSync;
  final DateTime? lastLocalUpdate;
  final String? error;

  VpsServerCheck({
    required this.available,
    this.serverCount = 0,
    this.localCount = 0,
    this.lastServerSync,
    this.lastLocalUpdate,
    this.error,
  });

  bool get hasNewData {
    if (localCount == 0 && serverCount > 0) return true;
    if (lastServerSync == null || lastLocalUpdate == null)
      return serverCount > 0;
    return lastServerSync!.isAfter(lastLocalUpdate!);
  }
}

class VpsSyncResult {
  final bool success;
  final String? error;
  final String? message;
  final int totalCount;
  final int downloadedCount;
  final int newCount;
  final int updatedCount;
  final bool isIncremental;

  VpsSyncResult({
    required this.success,
    this.error,
    this.message,
    this.totalCount = 0,
    this.downloadedCount = 0,
    this.newCount = 0,
    this.updatedCount = 0,
    this.isIncremental = false,
  });
}
