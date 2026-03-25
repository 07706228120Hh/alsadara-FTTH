import 'dart:async';
import 'package:flutter/foundation.dart';
import 'attendance_api_service.dart';
import 'notification_service.dart';
import 'vps_auth_service.dart';

/// خدمة تذكير الحضور — إشعار محلي إذا لم يسجل الموظف حضوره بعد 30 دقيقة من بداية الدوام
class AttendanceReminderService {
  AttendanceReminderService._();
  static final AttendanceReminderService instance = AttendanceReminderService._();

  Timer? _timer;
  bool _hasNotifiedToday = false;
  DateTime? _lastNotifiedDate;

  /// تشغيل الخدمة (تُستدعى من الصفحة الرئيسية)
  void start() {
    stop();
    // فحص كل 5 دقائق
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _check());
    // فحص فوري أيضاً
    _check();
  }

  /// إيقاف الخدمة
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// إعادة تعيين لليوم التالي
  void _resetIfNewDay() {
    final today = DateTime.now();
    if (_lastNotifiedDate == null ||
        _lastNotifiedDate!.day != today.day ||
        _lastNotifiedDate!.month != today.month ||
        _lastNotifiedDate!.year != today.year) {
      _hasNotifiedToday = false;
      _lastNotifiedDate = today;
    }
  }

  Future<void> _check() async {
    try {
      _resetIfNewDay();
      if (_hasNotifiedToday) return;

      // جلب بيانات المستخدم الحالي
      final user = VpsAuthService.instance.currentUser;
      if (user == null) return;

      final userId = user.id;
      if (userId.isEmpty) return;

      // تحقق: هل الوقت الآن بعد بداية الدوام + 30 دقيقة؟
      final now = DateTime.now();
      final hour = now.hour;

      // نفترض أن الدوام يبدأ بين 7:00 - 10:00 صباحاً
      // إذا الوقت قبل 7:30 أو بعد 12:00 لا داعي للتحقق
      if (hour < 7 || hour >= 12) return;

      // فحص هل سجّل حضور اليوم
      final today = DateTime.now();
      final year = today.year;
      final month = today.month;

      final result = await AttendanceApiService.instance.getMonthlyAttendance(
        userId: userId,
        year: year,
        month: month,
      );

      if (result.containsKey('records')) {
        final records = result['records'] as List<dynamic>? ?? [];
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

        final hasCheckedIn = records.any((r) =>
            r['date'] == todayStr && r['checkInTime'] != null);

        if (!hasCheckedIn && hour >= 7 && now.minute >= 30 || hour >= 8) {
          // لم يسجل حضور + مر 30 دقيقة على بداية الدوام
          await NotificationService.showLocalNotification(
            title: 'تذكير الحضور',
            body: 'لم تسجل حضورك بعد! سجّل حضورك الآن لتجنب التأخير.',
          );
          _hasNotifiedToday = true;
          debugPrint('[AttendanceReminder] تم إرسال تذكير الحضور');
        }
      }
    } catch (e) {
      debugPrint('[AttendanceReminder] خطأ: $e');
    }
  }
}
