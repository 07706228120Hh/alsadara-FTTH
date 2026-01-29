/// نموذج اختبار التشخيص
class DiagnosticTest {
  final String id;
  final String name;
  final String nameAr;
  final String description;
  final String category;
  final DiagnosticTestType type;
  final Future<DiagnosticTestResult> Function() testFunction;

  DiagnosticTest({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.description,
    required this.category,
    required this.type,
    required this.testFunction,
  });
}

/// أنواع اختبارات التشخيص
enum DiagnosticTestType {
  connection, // اختبار اتصال
  api, // اختبار API
  crud, // اختبار CRUD
  security, // اختبار أمان
  navigation, // اختبار تنقل
  ui, // اختبار واجهة
  performance, // اختبار أداء
  storage, // اختبار تخزين
  system, // اختبار نظام
  companies, // اختبار إدارة الشركات
}

/// نتيجة اختبار التشخيص
class DiagnosticTestResult {
  final String testId;
  final bool success;
  final String message;
  final String? details;
  final Duration duration;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;

  DiagnosticTestResult({
    required this.testId,
    required this.success,
    required this.message,
    this.details,
    required this.duration,
    DateTime? timestamp,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();

  String get statusText => success ? 'نجح ✓' : 'فشل ✗';

  String get durationText => '${duration.inMilliseconds} مللي ثانية';

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'success': success,
        'message': message,
        'details': details,
        'duration': duration.inMilliseconds,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };

  @override
  String toString() {
    return '''
═══════════════════════════════════════
اختبار: $testId
الحالة: $statusText
الرسالة: $message
${details != null ? 'التفاصيل: $details\n' : ''}المدة: $durationText
الوقت: $timestamp
═══════════════════════════════════════''';
  }
}

/// فئة نتائج التشخيص الكاملة
class DiagnosticReport {
  final String reportId;
  final DateTime generatedAt;
  final List<DiagnosticTestResult> results;
  final Map<String, int> categorySummary;
  final int totalTests;
  final int passedTests;
  final int failedTests;
  final Duration totalDuration;

  DiagnosticReport({
    required this.reportId,
    required this.generatedAt,
    required this.results,
    required this.categorySummary,
    required this.totalTests,
    required this.passedTests,
    required this.failedTests,
    required this.totalDuration,
  });

  double get successRate =>
      totalTests > 0 ? (passedTests / totalTests) * 100 : 0;

  String toFullReport() {
    final buffer = StringBuffer();
    buffer.writeln(
        '╔══════════════════════════════════════════════════════════════╗');
    buffer.writeln(
        '║           تقرير تشخيص نظام الصدارة الشامل                    ║');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════╣');
    buffer.writeln('║ رقم التقرير: $reportId');
    buffer.writeln('║ تاريخ الإنشاء: $generatedAt');
    buffer.writeln('║ إجمالي الاختبارات: $totalTests');
    buffer.writeln('║ الاختبارات الناجحة: $passedTests');
    buffer.writeln('║ الاختبارات الفاشلة: $failedTests');
    buffer.writeln('║ نسبة النجاح: ${successRate.toStringAsFixed(1)}%');
    buffer.writeln('║ المدة الإجمالية: ${totalDuration.inSeconds} ثانية');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════╣');
    buffer.writeln(
        '║                      ملخص الفئات                             ║');
    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════╣');

    categorySummary.forEach((category, count) {
      buffer.writeln('║ $category: $count اختبار');
    });

    buffer.writeln(
        '╠══════════════════════════════════════════════════════════════╣');
    buffer.writeln(
        '║                      تفاصيل الاختبارات                       ║');
    buffer.writeln(
        '╚══════════════════════════════════════════════════════════════╝');

    for (var result in results) {
      buffer.writeln(result.toString());
    }

    return buffer.toString();
  }
}
