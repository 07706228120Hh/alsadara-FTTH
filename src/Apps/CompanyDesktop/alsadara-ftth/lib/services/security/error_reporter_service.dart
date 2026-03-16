/// خدمة تقارير الأخطاء - Error Reporting
/// تسجيل وإرسال الأخطاء للتحليل
/// المؤلف: تطبيق الصدارة
/// تاريخ الإنشاء: 2026
library;

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// خدمة تقارير الأخطاء
class ErrorReporterService {
  static ErrorReporterService? _instance;
  static ErrorReporterService get instance =>
      _instance ??= ErrorReporterService._();

  ErrorReporterService._();

  // الإعدادات
  static const int maxLocalLogs = 100;
  static const String logFileName = 'error_logs.json';

  // حماية من التكرار السريع (throttle)
  DateTime _lastReportTime = DateTime(2000);
  String _lastErrorMessage = '';
  int _suppressedCount = 0;
  static const Duration _throttleDuration = Duration(seconds: 2);
  bool _isSaving = false; // منع الكتابة المتزامنة

  // معلومات الجهاز والتطبيق
  Map<String, dynamic>? _deviceInfo;
  Map<String, dynamic>? _appInfo;

  /// تهيئة الخدمة
  Future<void> initialize() async {
    await _loadDeviceInfo();
    await _loadAppInfo();
    print('✅ ErrorReporter: تم تهيئة خدمة تقارير الأخطاء');
  }

  /// تحميل معلومات الجهاز
  Future<void> _loadDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isWindows) {
        final windows = await deviceInfo.windowsInfo;
        _deviceInfo = {
          'platform': 'Windows',
          'computerName': windows.computerName,
          'numberOfCores': windows.numberOfCores,
          'systemMemoryInMegabytes': windows.systemMemoryInMegabytes,
          'productName': windows.productName,
          'buildNumber': windows.buildNumber,
        };
      } else if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        _deviceInfo = {
          'platform': 'Android',
          'model': android.model,
          'manufacturer': android.manufacturer,
          'version': android.version.release,
          'sdkInt': android.version.sdkInt,
        };
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        _deviceInfo = {
          'platform': 'iOS',
          'model': ios.model,
          'systemVersion': ios.systemVersion,
          'name': ios.name,
        };
      }
    } catch (e) {
      _deviceInfo = {'platform': Platform.operatingSystem};
    }
  }

  /// تحميل معلومات التطبيق
  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      _appInfo = {
        'appName': info.appName,
        'packageName': info.packageName,
        'version': info.version,
        'buildNumber': info.buildNumber,
      };
    } catch (e) {
      _appInfo = {'version': 'unknown'};
    }
  }

  /// تسجيل خطأ
  Future<void> reportError({
    required dynamic error,
    StackTrace? stackTrace,
    String? context,
    Map<String, dynamic>? metadata,
    ErrorSeverity severity = ErrorSeverity.error,
  }) async {
    final errorReport = ErrorReport(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      error: error.toString(),
      stackTrace: stackTrace?.toString(),
      context: context,
      severity: severity,
      deviceInfo: _deviceInfo,
      appInfo: _appInfo,
      metadata: metadata,
    );

    // طباعة في Debug mode
    if (kDebugMode) {
      _printError(errorReport);
    }

    // حفظ محلياً
    await _saveLocally(errorReport);

    // يمكن إضافة إرسال للسيرفر هنا
    // await _sendToServer(errorReport);
  }

  /// تسجيل خطأ Flutter (مع حماية من التكرار السريع)
  /// يعيد true إذا تم تسجيل الخطأ، false إذا تم تجاهله (مكرر)
  bool captureFlutterError(FlutterErrorDetails details) {
    final now = DateTime.now();
    final errorMsg = details.exception.toString();

    // تجاهل الأخطاء المتكررة بسرعة (نفس الخطأ خلال أقل من ثانيتين)
    if (errorMsg == _lastErrorMessage &&
        now.difference(_lastReportTime) < _throttleDuration) {
      _suppressedCount++;
      return false; // تم التجاهل
    }

    // طباعة عدد الأخطاء المكبوتة إن وجدت
    if (_suppressedCount > 0) {
      if (kDebugMode) {
        print('⚠️ ErrorReporter: تم تجاهل $_suppressedCount خطأ متكرر');
      }
      _suppressedCount = 0;
    }

    _lastReportTime = now;
    _lastErrorMessage = errorMsg;

    reportError(
      error: details.exception,
      stackTrace: details.stack,
      context: details.context?.toString(),
      severity: ErrorSeverity.critical,
      metadata: {
        'library': details.library,
        'silent': details.silent,
      },
    );
    return true; // تم التسجيل
  }

  /// طباعة الخطأ
  void _printError(ErrorReport report) {
    final emoji = _getSeverityEmoji(report.severity);
    print('$emoji ═══════════════════════════════════════');
    print('$emoji ERROR REPORT');
    print('$emoji Time: ${report.timestamp}');
    print('$emoji Context: ${report.context ?? 'Unknown'}');
    print('$emoji Severity: ${report.severity.name}');
    print('$emoji Error: ${report.error}');
    if (report.stackTrace != null) {
      print('$emoji Stack Trace:');
      print(report.stackTrace);
    }
    print('$emoji ═══════════════════════════════════════');
  }

  String _getSeverityEmoji(ErrorSeverity severity) {
    switch (severity) {
      case ErrorSeverity.info:
        return 'ℹ️';
      case ErrorSeverity.warning:
        return '⚠️';
      case ErrorSeverity.error:
        return '❌';
      case ErrorSeverity.critical:
        return '🔴';
    }
  }

  /// حفظ محلياً (مع حماية من الكتابة المتزامنة)
  Future<void> _saveLocally(ErrorReport report) async {
    // منع الكتابة المتزامنة التي تسبب تجميد
    if (_isSaving) return;
    _isSaving = true;
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$logFileName');

      List<Map<String, dynamic>> logs = [];

      // قراءة السجلات الموجودة
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          logs = List<Map<String, dynamic>>.from(jsonDecode(content));
        }
      }

      // إضافة السجل الجديد
      logs.add(report.toJson());

      // الاحتفاظ بآخر maxLocalLogs فقط
      if (logs.length > maxLocalLogs) {
        logs = logs.sublist(logs.length - maxLocalLogs);
      }

      // حفظ
      await file.writeAsString(jsonEncode(logs));
    } catch (e) {
      if (kDebugMode) {
        print('❌ ErrorReporter: فشل الحفظ المحلي');
      }
    } finally {
      _isSaving = false;
    }
  }

  /// قراءة السجلات المحلية
  Future<List<ErrorReport>> getLocalLogs() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$logFileName');

      if (!await file.exists()) {
        return [];
      }

      final content = await file.readAsString();
      if (content.isEmpty) return [];

      final logs = List<Map<String, dynamic>>.from(jsonDecode(content));
      return logs.map((json) => ErrorReport.fromJson(json)).toList();
    } catch (e) {
      print('❌ ErrorReporter: فشل قراءة السجلات');
      return [];
    }
  }

  /// مسح السجلات المحلية
  Future<void> clearLocalLogs() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}/$logFileName');

      if (await file.exists()) {
        await file.delete();
      }
      print('✅ ErrorReporter: تم مسح السجلات');
    } catch (e) {
      print('❌ ErrorReporter: فشل مسح السجلات');
    }
  }

  /// تصدير السجلات كنص
  Future<String> exportLogsAsText() async {
    final logs = await getLocalLogs();
    final buffer = StringBuffer();

    buffer.writeln('═══════════════════════════════════════');
    buffer.writeln('       تقرير أخطاء تطبيق الصدارة');
    buffer.writeln('       تاريخ التصدير: ${DateTime.now()}');
    buffer.writeln('═══════════════════════════════════════\n');

    for (final log in logs) {
      buffer.writeln('─────────────────────────────────────');
      buffer.writeln('التاريخ: ${log.timestamp}');
      buffer.writeln('الشدة: ${log.severity.name}');
      buffer.writeln('السياق: ${log.context ?? 'غير محدد'}');
      buffer.writeln('الخطأ: ${log.error}');
      if (log.stackTrace != null) {
        buffer.writeln('Stack Trace:');
        buffer.writeln(log.stackTrace);
      }
      buffer.writeln('');
    }

    return buffer.toString();
  }

  /// إحصائيات الأخطاء
  Future<Map<String, dynamic>> getErrorStats() async {
    final logs = await getLocalLogs();

    final stats = <String, int>{
      'total': logs.length,
      'critical': 0,
      'error': 0,
      'warning': 0,
      'info': 0,
    };

    for (final log in logs) {
      stats[log.severity.name] = (stats[log.severity.name] ?? 0) + 1;
    }

    return stats;
  }
}

/// شدة الخطأ
enum ErrorSeverity {
  info,
  warning,
  error,
  critical,
}

/// تقرير خطأ
class ErrorReport {
  final String id;
  final DateTime timestamp;
  final String error;
  final String? stackTrace;
  final String? context;
  final ErrorSeverity severity;
  final Map<String, dynamic>? deviceInfo;
  final Map<String, dynamic>? appInfo;
  final Map<String, dynamic>? metadata;

  ErrorReport({
    required this.id,
    required this.timestamp,
    required this.error,
    this.stackTrace,
    this.context,
    required this.severity,
    this.deviceInfo,
    this.appInfo,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'error': error,
        'stackTrace': stackTrace,
        'context': context,
        'severity': severity.name,
        'deviceInfo': deviceInfo,
        'appInfo': appInfo,
        'metadata': metadata,
      };

  factory ErrorReport.fromJson(Map<String, dynamic> json) => ErrorReport(
        id: json['id'],
        timestamp: DateTime.parse(json['timestamp']),
        error: json['error'],
        stackTrace: json['stackTrace'],
        context: json['context'],
        severity: ErrorSeverity.values.firstWhere(
          (e) => e.name == json['severity'],
          orElse: () => ErrorSeverity.error,
        ),
        deviceInfo: json['deviceInfo'],
        appInfo: json['appInfo'],
        metadata: json['metadata'],
      );
}
