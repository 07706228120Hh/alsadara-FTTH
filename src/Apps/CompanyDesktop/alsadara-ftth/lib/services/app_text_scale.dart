import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTextScale {
  static final AppTextScale instance = AppTextScale._();
  AppTextScale._();

  static const _prefsKey = 'app_text_scale';
  final ValueNotifier<double> notifier = ValueNotifier<double>(1.0);
  bool _loaded = false;

  double get value => notifier.value;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(_prefsKey);
      if (stored != null) notifier.value = stored;
    } catch (_) {}
    _loaded = true;
  }

  Future<void> set(double scale) async {
    // Clamp to sensible range
    final clamped = scale.clamp(0.8, 1.3);
    notifier.value = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsKey, clamped);
    } catch (_) {}
  }

  Future<void> reset() => set(1.0);
}
