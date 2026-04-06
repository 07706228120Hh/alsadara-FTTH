import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// كشف الموقع الوهمي — طبقات متعددة (Native + Flutter + سلوكي)
class MockLocationDetector {
  static const _channel = MethodChannel('com.alsadara/mock_detector');

  // ═══ حدود الكشف السلوكي ═══
  static const double _minRealisticAltitude = -100; // البحر الميت
  static const double _maxRealisticAltitude = 5000; // جبال عالية
  static const double _maxSpeedMs = 80; // ~288 كم/س — أقصى سرعة واقعية
  static const double _suspiciousAccuracyExact = 1.0; // دقة مثالية = مشبوه

  // ═══ تاريخ النقاط السابقة للتحليل السلوكي ═══
  static double? _lastLat;
  static double? _lastLng;
  static double? _lastAltitude;
  static DateTime? _lastTime;
  static int _teleportCount = 0;
  static int _perfectAccuracyCount = 0;
  static int _zeroAltitudeCount = 0;
  static int _totalChecks = 0;

  /// فحص شامل من Native Android — يُرجع تفاصيل كاملة
  /// يعمل فقط على Android، يُرجع {} على غيره
  static Future<Map<String, dynamic>> detectAll() async {
    if (!Platform.isAndroid) return {};
    try {
      final result = await _channel.invokeMethod('detectAll');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      debugPrint('⚠️ [MockDetector] Native detectAll failed: $e');
      return {};
    }
  }

  /// فحص سريع من Native — هل الجهاز مشبوه؟
  static Future<bool> isDeviceSuspicious() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod('isSuspicious') as bool;
    } catch (e) {
      debugPrint('⚠️ [MockDetector] Native isSuspicious failed: $e');
      return false;
    }
  }

  /// فحص سلوكي لنقطة موقع واحدة
  /// يُرجع Map فيه: isFake, reasons[], suspicionScore (0-100)
  static Map<String, dynamic> analyzePosition({
    required double latitude,
    required double longitude,
    required double accuracy,
    required double altitude,
    required bool isMocked,
    double? speed,
  }) {
    _totalChecks++;
    final reasons = <String>[];
    int score = 0;

    // 1️⃣ فحص isMocked الأساسي
    if (isMocked) {
      reasons.add('isMocked=true');
      score += 50;
    }

    // 2️⃣ فحص الارتفاع — فيك لوكيشن عادةً altitude = 0.0
    if (altitude == 0.0 && latitude != 0.0) {
      _zeroAltitudeCount++;
      // إذا تكرر 0.0 أكثر من 3 مرات متتالية = مشبوه جداً
      if (_zeroAltitudeCount >= 3) {
        reasons.add('altitude=0 متكرر ($_zeroAltitudeCount مرات)');
        score += 30;
      }
    } else {
      _zeroAltitudeCount = 0; // إعادة تصفير إذا جاء ارتفاع حقيقي
    }

    // 3️⃣ فحص ارتفاع غير واقعي
    if (altitude != 0.0 &&
        (altitude < _minRealisticAltitude || altitude > _maxRealisticAltitude)) {
      reasons.add('altitude غير واقعي: $altitude');
      score += 40;
    }

    // 4️⃣ فحص الدقة المثالية — GPS حقيقي لا يعطي 1.0 بالضبط
    if (accuracy == _suspiciousAccuracyExact) {
      _perfectAccuracyCount++;
      if (_perfectAccuracyCount >= 3) {
        reasons.add('دقة مثالية متكررة: $accuracy');
        score += 25;
      }
    } else {
      _perfectAccuracyCount = 0;
    }

    // 5️⃣ فحص الانتقال المفاجئ (Teleport)
    if (_lastLat != null && _lastLng != null && _lastTime != null) {
      final elapsed = DateTime.now().difference(_lastTime!).inSeconds;
      if (elapsed > 0 && elapsed < 120) {
        // حساب المسافة بالمتر (تقريبي)
        final dLat = (latitude - _lastLat!) * 111320;
        final dLng = (longitude - _lastLng!) * 111320 * 0.7; // تقريب cos(33°)
        final distM = _sqrt(dLat * dLat + dLng * dLng);
        final speedMs = distM / elapsed;

        if (speedMs > _maxSpeedMs) {
          _teleportCount++;
          reasons.add(
              'انتقال مفاجئ: ${(speedMs * 3.6).toStringAsFixed(0)} كم/س');
          score += 40;
        }

        // 6️⃣ فحص سرعة ثابتة تماماً — الفيك يعطي أحياناً speed = 0 دائماً
        if (speed != null && speed == 0.0 && distM > 50) {
          reasons.add('speed=0 لكن تحرك ${distM.toStringAsFixed(0)}م');
          score += 20;
        }
      }
    }

    // 7️⃣ فحص إحداثيات مستديرة بشكل مشبوه (مثل 33.300000, 44.400000)
    final latStr = latitude.toString();
    final lngStr = longitude.toString();
    if (_hasExcessiveZeros(latStr) && _hasExcessiveZeros(lngStr)) {
      reasons.add('إحداثيات مستديرة بشكل مشبوه');
      score += 15;
    }

    // حفظ للنقطة التالية
    _lastLat = latitude;
    _lastLng = longitude;
    _lastAltitude = altitude;
    _lastTime = DateTime.now();

    // تحديد النتيجة النهائية
    final isFake = score >= 50;

    return {
      'isFake': isFake,
      'score': score.clamp(0, 100),
      'reasons': reasons,
      'teleportCount': _teleportCount,
      'totalChecks': _totalChecks,
    };
  }

  /// إعادة تصفير الإحصائيات
  static void reset() {
    _lastLat = null;
    _lastLng = null;
    _lastAltitude = null;
    _lastTime = null;
    _teleportCount = 0;
    _perfectAccuracyCount = 0;
    _zeroAltitudeCount = 0;
    _totalChecks = 0;
  }

  // ═══ مساعدات ═══

  static bool _hasExcessiveZeros(String coordStr) {
    final dotIndex = coordStr.indexOf('.');
    if (dotIndex == -1) return true;
    final decimals = coordStr.substring(dotIndex + 1);
    if (decimals.length < 4) return true;
    // أكثر من 3 أصفار في النهاية
    final trailingZeros = decimals.length - decimals.replaceAll(RegExp(r'0+$'), '').length;
    return trailingZeros >= 4;
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double g = x / 2;
    for (int i = 0; i < 15; i++) {
      g = (g + x / g) / 2;
    }
    return g;
  }
}
