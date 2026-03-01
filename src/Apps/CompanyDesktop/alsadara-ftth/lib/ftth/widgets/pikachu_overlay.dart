/// نظام بيكاتشو العائم - يتبع الماوس في جميع الشاشات
/// يظهر فوق كل شيء ويتحرك بسلاسة خلف مؤشر الماوس
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PikachuOverlay {
  static OverlayEntry? _pikachuEntry;
  static OverlayEntry? _toggleButtonEntry;
  static bool _isShowing = false;
  static bool _showPikachu = true;

  // موقع بيكاتشو
  static Offset _pikachuPosition = const Offset(100, 100);
  static Offset _targetPosition = const Offset(100, 100);
  static bool _facingRight = true;

  // مؤقت الحركة
  static Timer? _moveTimer;
  static int _idleFrames = 0; // عداد الإطارات بدون حركة

  // للتحكم في إعادة البناء
  static final _notifier = ValueNotifier<Offset>(const Offset(100, 100));

  /// تهيئة وإظهار بيكاتشو
  static Future<void> init(BuildContext context) async {
    await _loadSetting();
    if (_showPikachu) {
      show(context);
    }
    _showToggleButton(context);
    // لا نبدأ المؤقت هنا - سيبدأ فقط عند تحريك الماوس
  }

  /// تحميل الإعداد من SharedPreferences
  static Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _showPikachu = prefs.getBool('show_pikachu') ?? true;
    } catch (e) {
      debugPrint('❌ خطأ في تحميل إعداد بيكاتشو: $e');
    }
  }

  /// حفظ الإعداد
  static Future<void> _saveSetting(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('show_pikachu', value);
      _showPikachu = value;
    } catch (e) {
      debugPrint('❌ خطأ في حفظ إعداد بيكاتشو: $e');
    }
  }

  /// بدء مؤقت الحركة السلسة (يتوقف تلقائياً عند الوصول للهدف)
  static void _startMoveTimer() {
    if (_moveTimer?.isActive ?? false) return; // يعمل بالفعل
    _idleFrames = 0;
    _moveTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      // تحريك بيكاتشو بسلاسة نحو الهدف
      final dx = (_targetPosition.dx - _pikachuPosition.dx) * 0.08;
      final dy = (_targetPosition.dy - _pikachuPosition.dy) * 0.08;

      if (dx.abs() > 0.1 || dy.abs() > 0.1) {
        _idleFrames = 0;
        _pikachuPosition = Offset(
          _pikachuPosition.dx + dx,
          _pikachuPosition.dy + dy,
        );

        // تحديد اتجاه الوجه بناءً على الحركة
        if (dx.abs() > 0.5) {
          _facingRight = dx > 0;
        }

        _notifier.value = _pikachuPosition;
      } else {
        _idleFrames++;
        // إيقاف المؤقت بعد 30 إطار بدون حركة (~0.5 ثانية)
        if (_idleFrames > 30) {
          timer.cancel();
          _moveTimer = null;
        }
      }
    });
  }

  /// تحديث موقع الهدف (يُستدعى من MouseRegion)
  /// بيكاتشو يبقى دائماً خلف الماوس بحسب اتجاه الحركة
  static Offset _lastMousePosition = const Offset(0, 0);
  static bool _movingRight = true;

  static void updateTargetPosition(Offset position) {
    // حساب اتجاه الحركة فقط إذا تحرك الماوس مسافة كافية (لتجنب التذبذب)
    final deltaX = position.dx - _lastMousePosition.dx;
    if (deltaX.abs() > 5) {
      // عتبة 5 بكسل
      _movingRight = deltaX > 0;
      _lastMousePosition = position;
    }

    // الإزاحة بحسب الاتجاه: بيكاتشو دائماً خلف الماوس
    final xOffset = _movingRight ? -160.0 : 60.0;
    _targetPosition = Offset(position.dx + xOffset, position.dy - 80);

    // تشغيل مؤقت الحركة فقط عند تحرك الماوس
    _startMoveTimer();
  }

  /// إظهار بيكاتشو
  static void show(BuildContext context) {
    if (_isShowing) return;

    try {
      final overlay = Overlay.of(context, rootOverlay: true);

      _pikachuEntry = OverlayEntry(
        builder: (context) => ValueListenableBuilder<Offset>(
          valueListenable: _notifier,
          builder: (context, position, child) {
            return Positioned(
              left: position.dx,
              top: position.dy,
              child: IgnorePointer(
                child: Transform.scale(
                  scaleX: _facingRight ? 1 : -1,
                  child: const SizedBox(
                    width: 200,
                    height: 200,
                    child: Text('⚡', style: TextStyle(fontSize: 80)),
                  ),
                ),
              ),
            );
          },
        ),
      );

      overlay.insert(_pikachuEntry!);
      _isShowing = true;
    } catch (e) {
      debugPrint('❌ خطأ في إظهار بيكاتشو: $e');
    }
  }

  /// إخفاء بيكاتشو
  static void hide() {
    _pikachuEntry?.remove();
    _pikachuEntry = null;
    _isShowing = false;
  }

  /// إظهار زر التحكم
  static void _showToggleButton(BuildContext context) {
    _toggleButtonEntry?.remove();

    try {
      final overlay = Overlay.of(context, rootOverlay: true);

      _toggleButtonEntry = OverlayEntry(
        builder: (context) => Positioned(
          bottom: 90,
          right: 20,
          child: StatefulBuilder(
            builder: (context, setState) {
              return FloatingActionButton.small(
                heroTag: 'pikachu_toggle_global',
                backgroundColor:
                    _showPikachu ? Colors.amber : Colors.grey.shade400,
                onPressed: () async {
                  final newValue = !_showPikachu;
                  await _saveSetting(newValue);

                  if (newValue) {
                    show(context);
                  } else {
                    hide();
                  }

                  // إعادة بناء الزر لتحديث اللون والأيقونة
                  _toggleButtonEntry?.markNeedsBuild();
                },
                tooltip: _showPikachu ? 'إخفاء بيكاتشو' : 'إظهار بيكاتشو',
                child: Text(
                  _showPikachu ? '⚡' : '👻',
                  style: const TextStyle(fontSize: 20),
                ),
              );
            },
          ),
        ),
      );

      overlay.insert(_toggleButtonEntry!);
    } catch (e) {
      debugPrint('❌ خطأ في إظهار زر بيكاتشو: $e');
    }
  }

  /// تنظيف الموارد
  static void dispose() {
    _moveTimer?.cancel();
    hide();
    _toggleButtonEntry?.remove();
    _toggleButtonEntry = null;
  }

  /// هل بيكاتشو معروض حالياً
  static bool get isShowing => _isShowing;

  /// هل بيكاتشو مُفعل
  static bool get isEnabled => _showPikachu;

  /// التأكد من إظهار بيكاتشو (يُستدعى عند العودة للصفحة)
  static Future<void> ensureVisible(BuildContext context) async {
    if (_toggleButtonEntry == null) {
      await init(context);
    } else if (_showPikachu && !_isShowing) {
      show(context);
    }
  }
}

/// Widget يلتقط حركة الماوس ويمررها لبيكاتشو
class PikachuMouseTracker extends StatelessWidget {
  final Widget child;

  const PikachuMouseTracker({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        PikachuOverlay.updateTargetPosition(event.position);
      },
      child: child,
    );
  }
}
