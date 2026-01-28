import 'package:windows_taskbar/windows_taskbar.dart' as wt;
import 'package:flutter/foundation.dart';

/// خدمة تتحكم في شارة (Badge) أيقونة التطبيق على Windows.
/// تستخدم Taskbar overlay icon أو progress كإشارة عددية مبسطة.
class BadgeService {
  BadgeService._();
  static final BadgeService instance = BadgeService._();

  int _unreadCount = 0;
  final ValueNotifier<int> unreadNotifier = ValueNotifier<int>(0);

  int get unreadCount => _unreadCount;

  Future<void> initialize() async {
  if (!_isWindows) return;
    // لا يوجد تهيئة معقدة حالياً
  }

  Future<void> setUnread(int count) async {
  if (!_isWindows) return;
    _unreadCount = count;
  unreadNotifier.value = _unreadCount;
    if (count <= 0) {
      await _clearOverlay();
    } else {
      await _showNumber(count);
    }
  }

  Future<void> increment() async => setUnread(_unreadCount + 1);
  Future<void> clear() async => setUnread(0);

  Future<void> _clearOverlay() async {
    try {
  try { await wt.WindowsTaskbar.resetOverlayIcon(); } catch (_) {}
  // إيقاف أي progress سابق
  try { await wt.WindowsTaskbar.setProgressMode(wt.TaskbarProgressMode.noProgress); } catch (_) {}
    } catch (_) {}
  }

  Future<void> _showNumber(int number) async {
    // استخدام أيقونات أصول جاهزة (assets) لكل رقم / مجموعة أرقام
    // ملاحظة: windows_taskbar يتوقع كائن ThumbnailToolbarAssetIcon واحد فقط.
    // TODO: أنشئ الأيقونات التالية وضعها في pubspec.yaml تحت assets:
    // assets/badges/badge_0.ico, badge_1.ico ... badge_9.ico, badge_10.ico ... badge_99.ico, badge_99plus.ico
    try {
      final assetName = _assetForNumber(number);
      try { await wt.WindowsTaskbar.setProgressMode(wt.TaskbarProgressMode.noProgress); } catch (_) {}
      try { await wt.WindowsTaskbar.setOverlayIcon(wt.ThumbnailToolbarAssetIcon(assetName)); } catch (_) {}
    } catch (_) {}
  }

  // فحص آمن للويندوز بدون استخدام dart:io (للدعم على الويب والمنصات الأخرى)
  bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  String _assetForNumber(int number) {
    if (number <= 0) return 'assets/badges/badge_0.ico';
    if (number > 99) return 'assets/badges/badge_99plus.ico';
    return 'assets/badges/badge_$number.ico';
  }
}
