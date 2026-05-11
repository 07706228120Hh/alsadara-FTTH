import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api/api_client.dart';
import 'auth_service.dart';
import 'local_database_service.dart';
import 'sync_service.dart';
import 'custom_auth_service.dart';
import 'vps_auth_service.dart';

/// نتيجة الرفع
class VpsUploadResult {
  final bool success;
  final int uploadedCount;
  final int newCount;
  final int updatedCount;
  final int skippedCount;
  final String? error;

  VpsUploadResult({
    required this.success,
    this.uploadedCount = 0,
    this.newCount = 0,
    this.updatedCount = 0,
    this.skippedCount = 0,
    this.error,
  });
}

/// خدمة رفع البيانات من الجهاز الرئيسي (Master) إلى السيرفر
/// + مزامنة تلقائية: جلب من FTTH → رفع للسيرفر (كل فترة ضمن الساعات النشطة)
class VpsUploadService extends ChangeNotifier {
  static final VpsUploadService _instance = VpsUploadService._internal();
  static VpsUploadService get instance => _instance;
  VpsUploadService._internal();

  static final _client = ApiClient.instance;
  static final _localDb = LocalDatabaseService.instance;
  final _syncService = SyncService();

  static const int _batchSize = 500;
  static const int _maxRetries = 3;

  bool _isUploading = false;
  double _progress = 0;
  String _statusMessage = '';
  VpsUploadResult? _lastResult;
  Timer? _autoSyncTimer;
  bool _isAutoSyncing = false;

  bool get isUploading => _isUploading;
  bool get isAutoSyncing => _isAutoSyncing;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  VpsUploadResult? get lastResult => _lastResult;

  static String? get _tenantId =>
      CustomAuthService().currentTenantId ??
      VpsAuthService.instance.currentCompanyId;

  // ═══════════════════════════════════════
  // حفظ/قراءة الإعدادات محلياً (SharedPreferences)
  // ═══════════════════════════════════════

  static const _kMasterEnabled = 'master_sync_enabled';
  static const _kSyncStartHour = 'master_sync_start_hour';
  static const _kSyncEndHour = 'master_sync_end_hour';
  static const _kSyncInterval = 'master_sync_interval_minutes';
  static const _kLastMasterSync = 'master_sync_last_at';

  /// حفظ إعدادات الجهاز الرئيسي محلياً (تُستدعى عند حفظ الإعدادات)
  static Future<void> saveLocalSettings({
    required bool isMasterSyncEnabled,
    int syncStartHour = 6,
    int syncEndHour = 23,
    int syncIntervalMinutes = 60,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMasterEnabled, isMasterSyncEnabled);
    await prefs.setInt(_kSyncStartHour, syncStartHour);
    await prefs.setInt(_kSyncEndHour, syncEndHour);
    await prefs.setInt(_kSyncInterval, syncIntervalMinutes);
  }

  /// هل هذا الجهاز هو المزامن الرئيسي؟ (قراءة محلية سريعة)
  static Future<bool> isMasterDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kMasterEnabled) ?? false;
  }

  /// حفظ وقت آخر مزامنة محلياً — بـ UTC لتوافق مع السيرفر
  Future<void> _saveLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kLastMasterSync, DateTime.now().toUtc().toIso8601String());
  }

  // ═══════════════════════════════════════
  // المزامنة التلقائية — جلب من FTTH + رفع للسيرفر
  // ═══════════════════════════════════════

  /// بدء المزامنة التلقائية (تُستدعى عند فتح التطبيق)
  void startAutoSync() {
    // أول محاولة بعد 15 ثانية
    Future.delayed(const Duration(seconds: 15), () => _autoSyncCycle());

    // تكرار كل 5 دقائق (يفحص الإعدادات في كل دورة)
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _autoSyncCycle();
    });

    debugPrint('🔄 Master auto-sync timer started (checks every 5 min)');
  }

  /// إيقاف المزامنة التلقائية
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    debugPrint('⏹️ Master auto-sync stopped');
  }

  /// دورة واحدة: فحص الإعدادات → جلب من FTTH → رفع للسيرفر
  Future<void> _autoSyncCycle() async {
    if (_isAutoSyncing || _isUploading) return;

    final tenantId = _tenantId;
    if (tenantId == null) return;

    try {
      // 1. فحص محلي سريع — هل هذا الجهاز master؟
      final prefs = await SharedPreferences.getInstance();
      final isMaster = prefs.getBool(_kMasterEnabled) ?? false;
      if (!isMaster) return;

      // 2. فحص الساعات النشطة (من الإعدادات المحلية)
      final now = DateTime.now();
      final startHour = prefs.getInt(_kSyncStartHour) ?? 6;
      final endHour = prefs.getInt(_kSyncEndHour) ?? 23;
      if (endHour > 0 && (now.hour < startHour || now.hour >= endHour)) return;

      // 3. فحص الفاصل الزمني (من الإعدادات المحلية)
      final intervalMinutes = prefs.getInt(_kSyncInterval) ?? 60;
      final lastSyncStr = prefs.getString(_kLastMasterSync);
      if (lastSyncStr != null) {
        final lastSync = DateTime.tryParse(lastSyncStr);
        if (lastSync != null &&
            now.toUtc().difference(lastSync).inMinutes < intervalMinutes) return;
      }

      debugPrint('🔄 Master auto-sync: بدء الدورة التلقائية...');
      _isAutoSyncing = true;
      notifyListeners();

      // 4. جلب من FTTH
      final token = await AuthService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        debugPrint('❌ Master auto-sync: لا يوجد توكن FTTH');
        _isAutoSyncing = false;
        notifyListeners();
        return;
      }

      _statusMessage = 'جلب البيانات من FTTH...';
      notifyListeners();

      final syncResult = await _syncService.fullSync(
        token: token,
        onProgress: (p) {
          _statusMessage = p.message;
          notifyListeners();
        },
      );

      if (!syncResult.success) {
        debugPrint(
            '❌ Master auto-sync: فشل الجلب من FTTH — ${syncResult.error}');
        _isAutoSyncing = false;
        _statusMessage = '';
        notifyListeners();
        return;
      }

      debugPrint(
          '✅ Master auto-sync: جلب ${syncResult.subscribersCount} مشترك من FTTH');

      // 5. رفع للسيرفر
      _statusMessage = 'رفع البيانات للسيرفر...';
      notifyListeners();

      final uploadResult = await uploadToVps();

      if (uploadResult.success) {
        await _saveLastSyncTime();
        debugPrint(
            '🎉 Master auto-sync: اكتملت الدورة — ${uploadResult.uploadedCount} مشترك');
      } else {
        debugPrint('❌ Master auto-sync: فشل الرفع — ${uploadResult.error}');
      }
    } catch (e) {
      debugPrint('❌ Master auto-sync error: $e');
    } finally {
      // حماية: دائماً نعيد تعيين الحالة حتى لو حدث exception غير متوقع
      _isAutoSyncing = false;
      _statusMessage = '';
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════
  // رفع البيانات للسيرفر — مع retry
  // ═══════════════════════════════════════

  /// رفع كل بيانات المشتركين المحليين إلى السيرفر
  Future<VpsUploadResult> uploadToVps() async {
    if (_isUploading) {
      return VpsUploadResult(success: false, error: 'الرفع قيد التنفيذ');
    }

    final tenantId = _tenantId;
    if (tenantId == null) {
      return VpsUploadResult(success: false, error: 'لا يوجد معرف الشركة');
    }

    _isUploading = true;
    _progress = 0;
    _statusMessage = 'تحضير البيانات...';
    notifyListeners();

    try {
      // 1. قراءة كل المشتركين من التخزين المحلي
      final allSubscribers = await _localDb.getAllSubscribers();
      if (allSubscribers.isEmpty) {
        _isUploading = false;
        notifyListeners();
        return VpsUploadResult(success: false, error: 'لا توجد بيانات محلية');
      }

      // 2. تحويل snake_case → camelCase للسيرفر
      final converted =
          allSubscribers.map((sub) => _snakeToCamelCase(sub)).toList();

      // 3. تقسيم لدفعات
      final totalBatches = (converted.length / _batchSize).ceil();
      int totalNew = 0, totalUpdated = 0, totalSkipped = 0;

      debugPrint(
          '📤 بدء رفع ${converted.length} مشترك في $totalBatches دفعة');

      // 4. رفع كل دفعة — مع retry
      for (int i = 0; i < totalBatches; i++) {
        final start = i * _batchSize;
        final end = (start + _batchSize).clamp(0, converted.length);
        final batch = converted.sublist(start, end);
        final isLast = i == totalBatches - 1;

        _statusMessage =
            'رفع الدفعة ${i + 1}/$totalBatches (${batch.length} مشترك)';
        _progress = (i + 1) / totalBatches;
        notifyListeners();

        // retry مع backoff — مطابق لآلية الجلب في sync_service
        bool batchSuccess = false;
        for (int attempt = 1; attempt <= _maxRetries; attempt++) {
          try {
            final res = await _client.post(
              '/subscriber-cache/$tenantId/upload',
              {
                'subscribers': batch,
                'batchIndex': i,
                'totalBatches': totalBatches,
                'isLastBatch': isLast,
              },
              (json) => json as Map<String, dynamic>,
              useInternalKey: true,
            );

            if (res.success) {
              final data = res.data;
              if (data != null) {
                totalNew += (data['newCount'] as int?) ?? 0;
                totalUpdated += (data['updatedCount'] as int?) ?? 0;
                totalSkipped += (data['skippedCount'] as int?) ?? 0;
              }
              batchSuccess = true;
              break; // نجحت — انتقل للدفعة التالية
            }

            // فشل HTTP — retry
            if (attempt < _maxRetries) {
              debugPrint(
                  '⚠️ دفعة ${i + 1} فشلت (محاولة $attempt/$_maxRetries): ${res.message}');
              await Future.delayed(Duration(seconds: attempt * 2));
            }
          } catch (e) {
            if (attempt < _maxRetries) {
              debugPrint(
                  '⚠️ دفعة ${i + 1} خطأ (محاولة $attempt/$_maxRetries): $e');
              await Future.delayed(Duration(seconds: attempt * 2));
            }
          }
        }

        if (!batchSuccess) {
          _isUploading = false;
          _statusMessage = 'فشل في الدفعة ${i + 1} بعد $_maxRetries محاولات';
          notifyListeners();
          return VpsUploadResult(
            success: false,
            uploadedCount: start,
            error: 'فشل الدفعة ${i + 1} بعد $_maxRetries محاولات',
          );
        }

        debugPrint('✅ دفعة ${i + 1}/$totalBatches: ${batch.length} مشترك');
      }

      _progress = 1.0;
      _statusMessage = 'اكتمل الرفع — ${converted.length} مشترك';
      _lastResult = VpsUploadResult(
        success: true,
        uploadedCount: converted.length,
        newCount: totalNew,
        updatedCount: totalUpdated,
        skippedCount: totalSkipped,
      );
      _isUploading = false;
      notifyListeners();

      debugPrint(
          '🎉 رفع ناجح: ${converted.length} مشترك (جديد: $totalNew, محدّث: $totalUpdated, بدون تغيير: $totalSkipped)');
      return _lastResult!;
    } catch (e) {
      _isUploading = false;
      _statusMessage = 'خطأ: $e';
      notifyListeners();
      debugPrint('❌ خطأ في الرفع: $e');
      return VpsUploadResult(success: false, error: e.toString());
    }
  }

  // ═══════════════════════════════════════
  // تحويل البيانات
  // ═══════════════════════════════════════

  /// تحويل حقول المشترك من snake_case (محلي) إلى camelCase (سيرفر)
  static Map<String, dynamic> _snakeToCamelCase(Map<String, dynamic> map) {
    // ServicesJson: إذا List → encode، إذا String → استخدمه كما هو، إذا null → null
    final services = map['services'];
    String? servicesJson;
    if (services is List) {
      servicesJson = jsonEncode(services);
    } else if (services is String && services.isNotEmpty) {
      servicesJson = services; // بالفعل JSON string
    }

    return {
      'subscriptionId': map['subscription_id'] ?? '',
      'customerId': map['customer_id'] ?? '',
      'username': map['username'] ?? '',
      'displayName': map['display_name'] ?? '',
      'status': map['status'] ?? '',
      'autoRenew': map['auto_renew'] ?? false,
      'profileName': map['profile_name'] ?? '',
      'bundleId': map['bundle_id'] ?? '',
      'zoneId': map['zone_id'] ?? '',
      'zoneName': map['zone_name'] ?? '',
      'startedAt': map['started_at'] ?? '',
      'expires': map['expires'] ?? '',
      'commitmentPeriod': map['commitment_period'] ?? '',
      'phone': map['phone'] ?? '',
      'lockedMac': map['locked_mac'] ?? '',
      'fdtName': map['fdt_name'] ?? '',
      'fatName': map['fat_name'] ?? '',
      'deviceSerial': map['device_serial'] ?? '',
      'gpsLat': map['gps_lat'],
      'gpsLng': map['gps_lng'],
      'isTrial': map['is_trial'] ?? false,
      'isPending': map['is_pending'] ?? false,
      'isSuspended': map['is_suspended'] ?? false,
      'suspensionReason': map['suspension_reason'] ?? '',
      'detailsFetched': map['details_fetched'] ?? false,
      'servicesJson': servicesJson,
    };
  }
}
