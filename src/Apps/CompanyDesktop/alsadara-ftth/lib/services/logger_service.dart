/// خدمة التسجيل المركزية (Logger Service)
/// توفر واجهة موحدة لتسجيل الرسائل بدلاً من print()
/// تدعم مستويات مختلفة: debug, info, warning, error
library;

import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// مستويات التسجيل
enum LogLevel {
  debug, // للتطوير فقط
  info, // معلومات عامة
  warning, // تحذيرات
  error, // أخطاء
  none, // إيقاف التسجيل
}

/// خدمة التسجيل المركزية
class LoggerService {
  // ====== Singleton Pattern ======
  static final LoggerService _instance = LoggerService._internal();
  static LoggerService get instance => _instance;
  factory LoggerService() => _instance;
  LoggerService._internal();

  // ====== Configuration ======

  /// مستوى التسجيل الحالي (افتراضي: debug في التطوير، info في الإنتاج)
  LogLevel _level = kDebugMode ? LogLevel.debug : LogLevel.info;

  /// تفعيل/إيقاف التسجيل
  bool _enabled = true;

  /// إظهار الوقت مع الرسائل
  bool _showTimestamp = true;

  /// إظهار اسم الملف ورقم السطر
  bool _showLocation = kDebugMode;

  // ====== Getters & Setters ======

  LogLevel get level => _level;
  set level(LogLevel value) => _level = value;

  bool get enabled => _enabled;
  set enabled(bool value) => _enabled = value;

  bool get showTimestamp => _showTimestamp;
  set showTimestamp(bool value) => _showTimestamp = value;

  bool get showLocation => _showLocation;
  set showLocation(bool value) => _showLocation = value;

  // ====== Logging Methods ======

  /// تسجيل رسالة debug (للتطوير فقط)
  void debug(String message,
      {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.debug, message,
        tag: tag, error: error, stackTrace: stackTrace);
  }

  /// تسجيل رسالة info (معلومات عامة)
  void info(String message,
      {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.info, message,
        tag: tag, error: error, stackTrace: stackTrace);
  }

  /// تسجيل تحذير
  void warning(String message,
      {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.warning, message,
        tag: tag, error: error, stackTrace: stackTrace);
  }

  /// تسجيل خطأ
  void error(String message,
      {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message,
        tag: tag, error: error, stackTrace: stackTrace);
  }

  /// تسجيل نجاح (اختصار لـ info مع أيقونة ✅)
  void success(String message, {String? tag}) {
    _log(LogLevel.info, '✅ $message', tag: tag);
  }

  /// تسجيل فشل (اختصار لـ error مع أيقونة ❌)
  void failure(String message,
      {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, '❌ $message',
        tag: tag, error: error, stackTrace: stackTrace);
  }

  // ====== Internal Methods ======

  void _log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // التحقق من التفعيل والمستوى
    if (!_enabled || level.index < _level.index) return;

    // بناء الرسالة
    final buffer = StringBuffer();

    // إضافة الوقت
    if (_showTimestamp) {
      final now = DateTime.now();
      final time = '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      buffer.write('[$time] ');
    }

    // إضافة أيقونة المستوى
    buffer.write(_getLevelIcon(level));
    buffer.write(' ');

    // إضافة التاغ
    if (tag != null) {
      buffer.write('[$tag] ');
    }

    // إضافة الرسالة
    buffer.write(message);

    // إضافة الخطأ إن وجد
    if (error != null) {
      buffer.write('\n   Error: $error');
    }

    // طباعة الرسالة
    final output = buffer.toString();

    if (kDebugMode) {
      // استخدام developer.log للتطوير (يظهر في DevTools)
      developer.log(
        output,
        name: tag ?? 'App',
        level: _getDeveloperLogLevel(level),
        error: error,
        stackTrace: stackTrace,
      );
    } else {
      // في الإنتاج: طباعة فقط للأخطاء والتحذيرات
      if (level == LogLevel.error || level == LogLevel.warning) {
        // ignore: avoid_print
        print(output);
        if (stackTrace != null) {
          // ignore: avoid_print
          print(stackTrace);
        }
      }
    }
  }

  String _getLevelIcon(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '🔴';
      case LogLevel.none:
        return '';
    }
  }

  int _getDeveloperLogLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500; // FINE
      case LogLevel.info:
        return 800; // INFO
      case LogLevel.warning:
        return 900; // WARNING
      case LogLevel.error:
        return 1000; // SEVERE
      case LogLevel.none:
        return 0;
    }
  }
}

// ====== Global Access ======

/// الوصول السريع للـ Logger
final logger = LoggerService.instance;

/// دوال مختصرة للاستخدام السريع
void logDebug(String message, {String? tag}) => logger.debug(message, tag: tag);
void logInfo(String message, {String? tag}) => logger.info(message, tag: tag);
void logWarning(String message, {String? tag}) =>
    logger.warning(message, tag: tag);
void logError(String message,
        {String? tag, Object? error, StackTrace? stackTrace}) =>
    logger.error(message, tag: tag, error: error, stackTrace: stackTrace);
void logSuccess(String message, {String? tag}) =>
    logger.success(message, tag: tag);
void logFailure(String message, {String? tag, Object? error}) =>
    logger.failure(message, tag: tag, error: error);

// ====== Extension for Easy Migration ======

/// Extension لتسهيل الانتقال من print
/// استخدم: 'message'.log() بدلاً من print('message')
extension StringLogging on String {
  void log({String? tag}) => logger.info(this, tag: tag);
  void logD({String? tag}) => logger.debug(this, tag: tag);
  void logW({String? tag}) => logger.warning(this, tag: tag);
  void logE({String? tag, Object? error}) =>
      logger.error(this, tag: tag, error: error);
}
