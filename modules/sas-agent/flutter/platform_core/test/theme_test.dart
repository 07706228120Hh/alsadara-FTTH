import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_core/platform_core.dart';

/// نسبة التباين WCAG بين لونين.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }
  final l1 = lum(a), l2 = lum(b);
  final hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('PlatformTheme', () {
    for (final brand in AppBrand.values) {
      for (final b in Brightness.values) {
        test('يُبنى بلا استثناء — ${brand.slug} / ${b.name}', () {
          final theme = PlatformTheme.build(brand, b);
          expect(theme.brightness, b);
          expect(theme.useMaterial3, isTrue);
          final pal = theme.extension<PlatformPalette>();
          expect(pal, isNotNull);
          expect(pal!.accent, brand.accentFor(b));
          expect(theme.textTheme.bodyMedium?.fontFamily, PlatformType.sansFamily);
        });
      }
    }

    test('اللون الأساسي واحد لكل التطبيقات (اللكنة فقط تختلف)', () {
      final primaries = AppBrand.values.map((b) => PlatformTheme.build(b, Brightness.light).colorScheme.primary).toSet();
      expect(primaries.length, 1);
    });
  });

  group('PlatformPalette — التباين', () {
    for (final (name, pal) in [('light', PlatformPalette.light), ('dark', PlatformPalette.dark)]) {
      test('النص على الخلفيات ≥ 4.5 — $name', () {
        for (final bg in [pal.surface, pal.surfaceCard, pal.surfaceVariant]) {
          expect(_contrast(pal.text, bg), greaterThanOrEqualTo(4.5), reason: 'text on $bg');
          expect(_contrast(pal.textMuted, bg), greaterThanOrEqualTo(4.5), reason: 'muted on $bg');
        }
      });
      test('الألوان الدلالية مقروءة على البطاقة ≥ 3 — $name', () {
        for (final c in [pal.success, pal.warning, pal.danger, pal.info]) {
          expect(_contrast(c, pal.surfaceCard), greaterThanOrEqualTo(3.0), reason: '$c');
        }
      });
    }

    test('status() يعيد الألوان الدلالية', () {
      const p = PlatformPalette.light;
      expect(p.status('active'), p.success);
      expect(p.status('open'), p.danger);
      expect(p.status('expired'), p.warning);
      expect(p.status('in_progress'), p.info);
      expect(p.status('whatever'), p.textMuted);
    });
  });

  group('AppBrand', () {
    test('الأنظمة الأربعة بلا البوّابة', () {
      expect(AppBrand.systems, hasLength(4));
      expect(AppBrand.systems, isNot(contains(AppBrand.portal)));
    });
    test('أسماء فريدة', () {
      expect(AppBrand.values.map((b) => b.title).toSet().length, AppBrand.values.length);
      expect(AppBrand.values.map((b) => b.slug).toSet().length, AppBrand.values.length);
    });
  });

  group('PhoneField', () {
    test('تطبيع الأرقام العراقية', () {
      expect(PhoneField.normalize('0770 123 4567'), '07701234567');
      expect(PhoneField.normalize('+964 770 123 4567'), '07701234567');
      expect(PhoneField.normalize('009647701234567'), '07701234567');
      expect(PhoneField.normalize('٠٧٧٠١٢٣٤٥٦٧'), '07701234567');
      expect(PhoneField.normalize('7701234567'), '07701234567');
    });
    test('التحقّق', () {
      expect(PhoneField.isValid('07701234567'), isTrue);
      expect(PhoneField.isValid('07101234567'), isFalse);
      expect(PhoneField.isValid('123'), isFalse);
    });
  });
}
