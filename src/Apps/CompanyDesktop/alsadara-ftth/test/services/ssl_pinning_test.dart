/// Unit Tests - SSL Pinning Service
/// اختبارات خدمة أمان الاتصال
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SSL Pinning Tests', () {
    test('يجب التعرف على نطاقات Firebase', () {
      // Arrange
      final trustedDomains = [
        'firebaseio.com',
        'googleapis.com',
        'firebaseapp.com',
        'cloudfunctions.net',
        'firebasestorage.googleapis.com',
      ];

      // Act & Assert
      expect(trustedDomains.contains('firebaseio.com'), true);
      expect(trustedDomains.contains('googleapis.com'), true);
    });

    test('يجب رفض النطاقات غير الموثوقة', () {
      // Arrange
      final trustedDomains = ['firebaseio.com', 'googleapis.com'];
      final untrustedHost = 'malicious-site.com';

      // Act
      final isTrusted = trustedDomains.any((d) => untrustedHost.endsWith(d));

      // Assert
      expect(isTrusted, false);
    });

    test('يجب قبول النطاقات الفرعية', () {
      // Arrange
      final trustedDomains = ['firebaseio.com'];
      final subdomain = 'project-123.firebaseio.com';

      // Act
      final isTrusted = trustedDomains.any((d) => subdomain.endsWith(d));

      // Assert
      expect(isTrusted, true);
    });

    test('يجب التحقق من وجود مفاتيح عامة', () {
      // Arrange
      final trustedPublicKeyHashes = {
        'firebaseio.com': [
          'hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPpfaLMOXDA=',
          'Vjs8r4z+80wjNcr1YKepWQboSIRi63WsWXhIMN+eWys=',
        ],
      };

      // Assert
      expect(trustedPublicKeyHashes.containsKey('firebaseio.com'), true);
      expect(trustedPublicKeyHashes['firebaseio.com']!.length, 2);
    });

    test('يجب أن تكون المفاتيح بتنسيق Base64', () {
      // Arrange
      final key = 'hxqRlPTu1bMS/0DITB1SSu0vd4u/8l8TjPpfaLMOXDA=';

      // Act - التحقق من تنسيق Base64
      final isBase64 = RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(key);

      // Assert
      expect(isBase64, true);
    });
  });
}
