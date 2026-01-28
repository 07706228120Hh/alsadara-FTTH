/// خدمة Rate Limiting - حماية من هجمات Brute Force
/// تمنع محاولات تسجيل الدخول المتكررة
/// المؤلف: تطبيق الصدارة
/// تاريخ الإنشاء: 2026
library;

import 'package:shared_preferences/shared_preferences.dart';

/// خدمة الحد من المحاولات
class RateLimiterService {
  static RateLimiterService? _instance;
  static RateLimiterService get instance =>
      _instance ??= RateLimiterService._();

  RateLimiterService._();

  // إعدادات الحماية
  static const int maxAttempts = 5; // الحد الأقصى للمحاولات
  static const int lockoutMinutes = 15; // مدة الحظر بالدقائق
  static const int resetMinutes = 30; // إعادة تعيين العداد بعد

  // مفاتيح التخزين
  static const String _attemptsKey = 'rate_limit_attempts';
  static const String _lockoutKey = 'rate_limit_lockout';
  static const String _lastAttemptKey = 'rate_limit_last_attempt';

  /// التحقق من إمكانية المحاولة
  Future<RateLimitResult> canAttempt(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_lockoutKey}_$identifier';
    final attemptsKey = '${_attemptsKey}_$identifier';
    final lastAttemptKey = '${_lastAttemptKey}_$identifier';

    // التحقق من وجود حظر نشط
    final lockoutTime = prefs.getInt(key);
    if (lockoutTime != null) {
      final lockoutDate = DateTime.fromMillisecondsSinceEpoch(lockoutTime);
      final now = DateTime.now();

      if (now.isBefore(lockoutDate)) {
        final remaining = lockoutDate.difference(now);
        return RateLimitResult(
          allowed: false,
          remainingAttempts: 0,
          lockoutRemaining: remaining,
          message: 'تم حظرك مؤقتاً. حاول بعد ${remaining.inMinutes} دقيقة',
        );
      } else {
        // انتهى الحظر - إعادة تعيين
        await _resetAttempts(identifier);
      }
    }

    // التحقق من إعادة تعيين العداد بعد فترة
    final lastAttempt = prefs.getInt(lastAttemptKey);
    if (lastAttempt != null) {
      final lastAttemptDate = DateTime.fromMillisecondsSinceEpoch(lastAttempt);
      final now = DateTime.now();
      if (now.difference(lastAttemptDate).inMinutes >= resetMinutes) {
        await _resetAttempts(identifier);
      }
    }

    final attempts = prefs.getInt(attemptsKey) ?? 0;
    final remaining = maxAttempts - attempts;

    return RateLimitResult(
      allowed: true,
      remainingAttempts: remaining,
      lockoutRemaining: null,
      message: remaining <= 2 ? 'تبقى $remaining محاولات' : null,
    );
  }

  /// تسجيل محاولة فاشلة
  Future<RateLimitResult> recordFailedAttempt(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final attemptsKey = '${_attemptsKey}_$identifier';
    final lockoutKey = '${_lockoutKey}_$identifier';
    final lastAttemptKey = '${_lastAttemptKey}_$identifier';

    final attempts = (prefs.getInt(attemptsKey) ?? 0) + 1;
    await prefs.setInt(attemptsKey, attempts);
    await prefs.setInt(lastAttemptKey, DateTime.now().millisecondsSinceEpoch);

    if (attempts >= maxAttempts) {
      // تفعيل الحظر
      final lockoutUntil =
          DateTime.now().add(Duration(minutes: lockoutMinutes));
      await prefs.setInt(lockoutKey, lockoutUntil.millisecondsSinceEpoch);

      print('🚫 RateLimiter: تم حظر $identifier لمدة $lockoutMinutes دقيقة');

      return RateLimitResult(
        allowed: false,
        remainingAttempts: 0,
        lockoutRemaining: Duration(minutes: lockoutMinutes),
        message:
            'تم حظرك لمدة $lockoutMinutes دقيقة بسبب المحاولات الفاشلة المتكررة',
      );
    }

    final remaining = maxAttempts - attempts;
    print(
        '⚠️ RateLimiter: محاولة فاشلة لـ $identifier - تبقى $remaining محاولات');

    return RateLimitResult(
      allowed: true,
      remainingAttempts: remaining,
      lockoutRemaining: null,
      message: 'تبقى $remaining محاولات قبل الحظر',
    );
  }

  /// تسجيل محاولة ناجحة (إعادة تعيين العداد)
  Future<void> recordSuccessfulAttempt(String identifier) async {
    await _resetAttempts(identifier);
    print(
        '✅ RateLimiter: تسجيل دخول ناجح لـ $identifier - تم إعادة تعيين العداد');
  }

  /// إعادة تعيين المحاولات
  Future<void> _resetAttempts(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_attemptsKey}_$identifier');
    await prefs.remove('${_lockoutKey}_$identifier');
    await prefs.remove('${_lastAttemptKey}_$identifier');
  }

  /// إعادة تعيين يدوي (للمدير)
  Future<void> resetForUser(String identifier) async {
    await _resetAttempts(identifier);
    print('🔄 RateLimiter: تم إعادة تعيين الحظر لـ $identifier يدوياً');
  }

  /// الحصول على حالة المستخدم
  Future<Map<String, dynamic>> getStatus(String identifier) async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = prefs.getInt('${_attemptsKey}_$identifier') ?? 0;
    final lockoutTime = prefs.getInt('${_lockoutKey}_$identifier');

    bool isLocked = false;
    int? minutesRemaining;

    if (lockoutTime != null) {
      final lockoutDate = DateTime.fromMillisecondsSinceEpoch(lockoutTime);
      if (DateTime.now().isBefore(lockoutDate)) {
        isLocked = true;
        minutesRemaining = lockoutDate.difference(DateTime.now()).inMinutes;
      }
    }

    return {
      'attempts': attempts,
      'maxAttempts': maxAttempts,
      'isLocked': isLocked,
      'minutesRemaining': minutesRemaining,
      'remainingAttempts': maxAttempts - attempts,
    };
  }
}

/// نتيجة فحص Rate Limit
class RateLimitResult {
  final bool allowed;
  final int remainingAttempts;
  final Duration? lockoutRemaining;
  final String? message;

  RateLimitResult({
    required this.allowed,
    required this.remainingAttempts,
    this.lockoutRemaining,
    this.message,
  });

  @override
  String toString() {
    return 'RateLimitResult(allowed: $allowed, remaining: $remainingAttempts, lockout: $lockoutRemaining)';
  }
}
