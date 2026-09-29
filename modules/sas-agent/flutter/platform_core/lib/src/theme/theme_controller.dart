import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// وضع العرض (نظام/فاتح/داكن) محفوظ محلياً — مشترك بين كل التطبيقات.
class ThemeController extends ValueNotifier<ThemeMode> {
  static const _key = 'pc_theme_mode';
  ThemeController([super.initial = ThemeMode.system]);

  /// المتحكّم الافتراضي المشترك (يمكن إنشاء واحد آخر للاختبارات).
  static final ThemeController instance = ThemeController();

  Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      value = switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // تخزين غير متاح — نبقى على وضع النظام
    }
  }

  Future<void> set(ThemeMode m) async {
    value = m;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, m.name);
    } catch (_) {}
  }

  /// نظام → فاتح → داكن → نظام
  Future<void> cycle() => set(switch (value) {
        ThemeMode.system => ThemeMode.light,
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.system,
      });

  static String label(ThemeMode m) => switch (m) {
        ThemeMode.system => 'حسب النظام',
        ThemeMode.light => 'الوضع الفاتح',
        ThemeMode.dark => 'الوضع الداكن',
      };

  static IconData icon(ThemeMode m) => switch (m) {
        ThemeMode.system => PhosphorIconsBold.monitor,
        ThemeMode.light => PhosphorIconsBold.sun,
        ThemeMode.dark => PhosphorIconsBold.moon,
      };
}

/// زر تبديل الوضع — يُوضع في الشريط العلوي/شاشة الدخول لكل التطبيقات.
class ThemeToggleButton extends StatelessWidget {
  final ThemeController? controller;
  final bool compact;
  const ThemeToggleButton({super.key, this.controller, this.compact = true});

  @override
  Widget build(BuildContext context) {
    final c = controller ?? ThemeController.instance;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: c,
      builder: (context, mode, _) {
        if (compact) {
          return IconButton(
            tooltip: ThemeController.label(mode),
            icon: Icon(ThemeController.icon(mode), size: 20),
            onPressed: c.cycle,
          );
        }
        return SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: [
            for (final m in ThemeMode.values)
              ButtonSegment(value: m, icon: Icon(ThemeController.icon(m), size: 16), label: Text(ThemeController.label(m))),
          ],
          selected: {mode},
          onSelectionChanged: (s) => c.set(s.first),
        );
      },
    );
  }
}
