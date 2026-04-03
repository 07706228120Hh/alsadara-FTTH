import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'api/api_client.dart';
import 'location_offline_queue.dart';
import 'mock_location_detector.dart';

/// خدمة الموقع في الخلفية — تعمل حتى لو التطبيق مغلق
class LocationForegroundService {
  static LocationForegroundService? _instance;
  static LocationForegroundService get instance =>
      _instance ??= LocationForegroundService._();
  LocationForegroundService._();

  bool _isRunning = false;
  bool get isRunning => _isRunning;
  String? _userId;

  /// تهيئة الخدمة (يُستدعى مرة واحدة في main)
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'location_tracking',
        channelName: 'تتبع الموقع',
        channelDescription: 'جاري مشاركة موقعك مع الإدارة',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000), // كل 5 ثواني — لدقة مسار أعلى
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// فحص الجهاز قبل البدء — يكشف تطبيقات الفيك المثبتة
  /// يُرجع null إذا سليم، أو رسالة التحذير
  Future<String?> checkDeviceIntegrity() async {
    final detection = await MockLocationDetector.detectAll();
    if (detection.isEmpty) return null; // ليس Android

    final mockApps = detection['mockApps'] as List? ?? [];
    final hasMockPermApps = detection['hasMockPermissionApps'] == true;
    final isSuspicious = detection['isSuspicious'] == true;

    if (!isSuspicious) return null;

    final warnings = <String>[];
    if (mockApps.isNotEmpty) {
      warnings.add('تم اكتشاف تطبيقات موقع وهمي مثبتة (${mockApps.length})');
    }
    if (hasMockPermApps) {
      warnings.add('يوجد تطبيقات لديها صلاحية Mock Location');
    }

    return warnings.join('\n');
  }

  /// بدء مشاركة الموقع في الخلفية
  Future<bool> start(String userId) async {
    if (_isRunning) return true;
    _userId = userId;

    if (!Platform.isAndroid && !Platform.isIOS) return false;

    final locPerm = await Geolocator.checkPermission();
    if (locPerm == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    // حفظ userId ليكون متاحاً في الـ isolate
    await FlutterForegroundTask.saveData(key: 'userId', value: userId);

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'الصدارة — تتبع الموقع',
      notificationText: 'جاري مشاركة موقعك',
      callback: _startCallback,
    );

    _isRunning = true;
    debugPrint('📍 [LocationService] Started: $_isRunning');
    return _isRunning;
  }

  /// إيقاف مشاركة الموقع
  Future<void> stop() async {
    if (!_isRunning) return;

    await FlutterForegroundTask.stopService();
    _isRunning = false;

    // إبلاغ السيرفر بإيقاف المشاركة
    if (_userId != null) {
      try {
        await ApiClient.instance.delete(
          '/employee-location/${Uri.encodeComponent(_userId!)}',
          (data) => data,
          useInternalKey: true,
        );
      } catch (_) {}
    }
    debugPrint('📍 [LocationService] Stopped');
  }
}

// ═══════════════════════════════════════════════
// Callback يعمل في isolate منفصل (الخلفية)
// ═══════════════════════════════════════════════

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_LocationTaskHandler());
}

class _LocationTaskHandler extends TaskHandler {
  double? _lastLat;
  double? _lastLng;
  double? _lastSentLat;
  double? _lastSentLng;
  DateTime? _lastSendTime;
  DateTime? _lastSentToServer;

  // ═══ متغيرات كشف الفيك السلوكي ═══
  int _zeroAltitudeStreak = 0;
  int _perfectAccuracyStreak = 0;
  int _teleportCount = 0;
  int _fakeFlagCount = 0;
  int _totalSent = 0;

  // ═══ ثوابت التحكم بالدقة ═══
  static const double _minMoveMeters = 3; // أقل حركة تُسجّل (3 متر)
  static const int _maxIdleSeconds = 60;  // يُرسل كل 60 ثانية حتى لو واقف

  // ═══ بطارية ذكية — تقليل GPS عند الثبات ═══
  int _stationaryCount = 0;        // عدد المرات المتتالية بدون حركة
  bool _isInLowPowerMode = false;  // هل مفعّل وضع البطارية
  int _skipCounter = 0;            // عداد التخطي في وضع البطارية

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('📍 [BG-Location] Task started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // ═══ بطارية ذكية ═══
    // إذا في وضع البطارية → نتخطى 2 من كل 3 أحداث (فعلياً كل 15 ثانية بدل 5)
    if (_isInLowPowerMode) {
      _skipCounter++;
      if (_skipCounter < 3) return; // تخطي
      _skipCounter = 0; // نفّذ هذه المرة
    }

    _sendLocation(timestamp);
  }

  Future<void> _sendLocation(DateTime timestamp) async {
    try {
      // استخدام دقة أقل في وضع البطارية
      final accuracy = _isInLowPowerMode
          ? LocationAccuracy.medium
          : LocationAccuracy.high;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          timeLimit: Duration(seconds: 10),
        ),
      );

      // ══════════════════════════════════════
      // 🛡️ كشف الموقع الوهمي — متعدد الطبقات
      // ══════════════════════════════════════

      bool isFake = false;
      final reasons = <String>[];

      // 1️⃣ الفحص الأساسي — isMocked من Android API
      if (position.isMocked) {
        isFake = true;
        reasons.add('isMocked');
      }

      // 2️⃣ فحص الدقة المشبوهة
      // accuracy > 500 شائع داخل المباني — نسجله كسبب لكن لا نحظر لوحده
      if (position.accuracy < 1.0) {
        isFake = true;
        reasons.add('accuracy=${position.accuracy}');
      } else if (position.accuracy > 500) {
        reasons.add('lowAccuracy=${position.accuracy.toStringAsFixed(0)}');
      }

      // 3️⃣ فحص الارتفاع — فيك لوكيشن = altitude 0.0 دائماً
      // ملاحظة: كثير من الأجهزة تُرجع 0.0 داخل المباني — لا نعتبره fake لوحده
      if (position.altitude == 0.0) {
        _zeroAltitudeStreak++;
        if (_zeroAltitudeStreak >= 5) {
          reasons.add('zeroAltitude×$_zeroAltitudeStreak');
          // لا نُعلّم isFake — فقط نسجل كسبب مشبوه
        }
      } else {
        _zeroAltitudeStreak = 0;
      }

      // 4️⃣ فحص دقة مثالية متكررة (1.0 بالضبط)
      // ملاحظة: بعض الأجهزة تُرجع 1.0 حقيقياً — لا نعتبره fake لوحده
      if (position.accuracy == 1.0) {
        _perfectAccuracyStreak++;
        if (_perfectAccuracyStreak >= 3) {
          reasons.add('perfectAccuracy×$_perfectAccuracyStreak');
          // لا نُعلّم isFake — فقط نسجل كسبب مشبوه
        }
      } else {
        _perfectAccuracyStreak = 0;
      }

      // 5️⃣ كشف الانتقال المفاجئ (Teleport)
      if (_lastLat != null && _lastLng != null && _lastSendTime != null) {
        final dist = Geolocator.distanceBetween(
            _lastLat!, _lastLng!, position.latitude, position.longitude);
        final secs = DateTime.now().difference(_lastSendTime!).inSeconds;
        if (secs > 0) {
          final speedMs = dist / secs;
          if (speedMs > 80) {
            // > 288 كم/س
            _teleportCount++;
            isFake = true;
            reasons.add('teleport:${(speedMs * 3.6).toStringAsFixed(0)}km/h');
          }

          // 6️⃣ speed=0 لكن تحرك مسافة كبيرة
          if (position.speed == 0.0 && dist > 100 && secs < 60) {
            reasons.add('speed0+moved${dist.toStringAsFixed(0)}m');
            isFake = true;
          }
        }
      }

      // 7️⃣ فحص إحداثيات مستديرة
      if (_isRoundedCoordinate(position.latitude) &&
          _isRoundedCoordinate(position.longitude)) {
        reasons.add('roundedCoords');
        // لا نرفض لوحده — نضيف للـ score فقط
        if (reasons.length >= 2) isFake = true;
      }

      // ══════════════════════════════════════
      // حفظ المتغيرات
      // ══════════════════════════════════════
      _lastLat = position.latitude;
      _lastLng = position.longitude;
      _lastSendTime = DateTime.now();

      if (isFake) {
        _fakeFlagCount++;
        debugPrint(
            '⚠️ [BG-Location] Suspicious: ${reasons.join(", ")} ($_fakeFlagCount total)');

        // ⚠️ لا نحظر الإرسال — نُرسل مع علامة isFakeDetected=true
        // السيرفر يحفظ البيانات ويقرر إظهارها أم لا
        FlutterForegroundTask.updateService(
          notificationTitle: 'الصدارة — تتبع الموقع',
          notificationText:
              '⚠️ موقع مشبوه (${reasons.first}) — يُرسل للسيرفر',
        );
      }

      // ══════════════════════════════════════
      // ✅ الموقع حقيقي — فلترة ذكية قبل الإرسال
      // ══════════════════════════════════════

      // هل تحرك بما يكفي لتسجيل نقطة جديدة؟
      double movedMeters = 0;
      if (_lastSentLat != null && _lastSentLng != null) {
        movedMeters = Geolocator.distanceBetween(
            _lastSentLat!, _lastSentLng!,
            position.latitude, position.longitude);
      }
      final secsSinceLastSend = _lastSentToServer != null
          ? DateTime.now().difference(_lastSentToServer!).inSeconds
          : 999;

      // ═══ بطارية ذكية — كشف الثبات ═══
      final isMoving = movedMeters >= _minMoveMeters;
      if (!isMoving) {
        _stationaryCount++;
      } else {
        _stationaryCount = 0;
      }

      // 6 مرات ثبات متتالية (30 ثانية بمعدل 5 ثواني) → وضع بطارية
      final shouldBeLowPower = _stationaryCount >= 6;
      if (shouldBeLowPower != _isInLowPowerMode) {
        _isInLowPowerMode = shouldBeLowPower;
        _skipCounter = 0;
        debugPrint(_isInLowPowerMode
            ? '🔋 [BG-Location] Low power mode ON (stationary)'
            : '🏃 [BG-Location] Full power mode ON (moving)');
        FlutterForegroundTask.updateService(
          notificationTitle: 'الصدارة — تتبع الموقع',
          notificationText: _isInLowPowerMode
              ? '🔋 وضع البطارية — ثابت'
              : '🏃 تتبع نشط',
        );
      }

      // يُرسل فقط إذا: تحرك > 3 متر أو مر > 60 ثانية
      final shouldSend = _lastSentLat == null ||
          isMoving ||
          secsSinceLastSend >= _maxIdleSeconds;

      if (!shouldSend) return;

      final userId =
          await FlutterForegroundTask.getData<String>(key: 'userId');
      if (userId == null || userId.isEmpty) return;

      _totalSent++;
      _lastSentLat = position.latitude;
      _lastSentLng = position.longitude;
      _lastSentToServer = DateTime.now();

      final payload = {
        'userId': userId,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'isMocked': position.isMocked,
        'isFakeDetected': isFake,
        'fakeReasons': reasons.isNotEmpty ? reasons.join(',') : null,
        'teleportCount': _teleportCount,
        'fakeFlagCount': _fakeFlagCount,
      };

      bool sent = false;
      try {
        final url =
            Uri.parse('https://api.ramzalsadara.tech/api/employee-location');
        final client = HttpClient()
          ..badCertificateCallback = (_, __, ___) => true;
        final request = await client.postUrl(url);
        request.headers.set('Content-Type', 'application/json');
        request.headers.set('X-Api-Key', 'sadara-internal-2024-secure-key');
        final fakeReasonsJson = reasons.isNotEmpty
            ? '"${reasons.join(',')}"'
            : 'null';
        request.write(
          '{"userId":"$userId"'
          ',"latitude":${position.latitude}'
          ',"longitude":${position.longitude}'
          ',"accuracy":${position.accuracy}'
          ',"altitude":${position.altitude}'
          ',"speed":${position.speed}'
          ',"isMocked":${position.isMocked}'
          ',"isFakeDetected":$isFake'
          ',"fakeReasons":$fakeReasonsJson'
          ',"teleportCount":$_teleportCount'
          ',"fakeFlagCount":$_fakeFlagCount'
          '}',
        );
        final response = await request.close();
        await response.drain();
        client.close();
        sent = response.statusCode >= 200 && response.statusCode < 300;
      } catch (_) {
        sent = false;
      }

      if (!sent) {
        // ❌ لا يوجد إنترنت — حفظ في الطابور المحلي
        await LocationOfflineQueue.enqueue(payload);
        FlutterForegroundTask.updateService(
          notificationTitle: 'الصدارة — تتبع الموقع',
          notificationText:
              '📦 بدون إنترنت — $_totalSent نقطة محفوظة محلياً',
        );
      } else {
        // ✅ نجح — حاول إرسال النقاط المعلقة أيضاً
        await LocationOfflineQueue.flush();
        FlutterForegroundTask.updateService(
          notificationTitle: 'الصدارة — تتبع الموقع',
          notificationText:
              '✅ $_totalSent نقطة | ${movedMeters.toStringAsFixed(0)}م | ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
        );
      }
    } catch (e) {
      debugPrint('📍 [BG-Location] Error: $e');
    }
  }

  /// هل الإحداثية مستديرة بشكل مشبوه؟
  bool _isRoundedCoordinate(double coord) {
    final str = coord.toString();
    final dotIndex = str.indexOf('.');
    if (dotIndex == -1) return true;
    final decimals = str.substring(dotIndex + 1);
    if (decimals.length < 4) return true;
    // 4+ أصفار في النهاية = مشبوه
    final trimmed = decimals.replaceAll(RegExp(r'0+$'), '');
    return (decimals.length - trimmed.length) >= 4;
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('📍 [BG-Location] Task destroyed (timeout: $isTimeout)');
  }
}
