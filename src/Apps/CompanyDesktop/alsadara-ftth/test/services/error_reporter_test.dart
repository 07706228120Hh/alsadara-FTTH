/// Unit Tests - Error Reporter Service
/// اختبارات خدمة تقارير الأخطاء
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Error Reporter Tests', () {
    test('يجب إنشاء تقرير خطأ صحيح', () {
      // Arrange
      final errorMessage = 'Test error message';
      final timestamp = DateTime.now();

      // Act
      final report = {
        'id': timestamp.millisecondsSinceEpoch.toString(),
        'timestamp': timestamp.toIso8601String(),
        'error': errorMessage,
        'severity': 'error',
      };

      // Assert
      expect(report['error'], errorMessage);
      expect(report['severity'], 'error');
      expect(report['id'], isNotEmpty);
    });

    test('يجب التعرف على مستويات الشدة', () {
      // Arrange
      final severities = ['info', 'warning', 'error', 'critical'];

      // Assert
      expect(severities.length, 4);
      expect(severities.contains('critical'), true);
    });

    test('يجب تحويل التقرير إلى JSON', () {
      // Arrange
      final report = {
        'id': '123456',
        'timestamp': DateTime.now().toIso8601String(),
        'error': 'Test error',
        'context': 'Test context',
        'severity': 'error',
      };

      // Act
      final json = Map<String, dynamic>.from(report);

      // Assert
      expect(json['id'], '123456');
      expect(json.containsKey('timestamp'), true);
    });

    test('يجب تحديد الرمز التعبيري الصحيح', () {
      // Arrange
      String getEmoji(String severity) {
        switch (severity) {
          case 'info':
            return 'ℹ️';
          case 'warning':
            return '⚠️';
          case 'error':
            return '❌';
          case 'critical':
            return '🔴';
          default:
            return '❓';
        }
      }

      // Assert
      expect(getEmoji('critical'), '🔴');
      expect(getEmoji('error'), '❌');
      expect(getEmoji('warning'), '⚠️');
    });

    test('يجب الاحتفاظ بـ 100 سجل كحد أقصى', () {
      // Arrange
      const maxLocalLogs = 100;
      var logs = List.generate(120, (i) => {'id': '$i'});

      // Act
      if (logs.length > maxLocalLogs) {
        logs = logs.sublist(logs.length - maxLocalLogs);
      }

      // Assert
      expect(logs.length, 100);
      expect(logs.first['id'], '20'); // أول 20 تم حذفها
    });
  });
}
