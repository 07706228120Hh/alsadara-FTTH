import 'dart:math' as math;
import 'package:flutter/material.dart';

/// بيانات الجسيم المتحرك
class Particle {
  double x, y, radius, speed, opacity;
  Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.opacity,
  });
}

/// رسام خلفية الجسيمات المتحركة
class ParticleBackgroundPainter extends CustomPainter {
  final double progress;
  final List<Particle> particles;

  ParticleBackgroundPainter({required this.progress, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    // الخلفية المتدرجة
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0D1B2A), Color(0xFF1B2838), Color(0xFF0D2137)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // رسم الجسيمات
    for (var p in particles) {
      final offsetY = (p.y + progress * p.speed * size.height) % size.height;
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: p.opacity * 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(p.x * size.width, offsetY), p.radius, paint);
    }

    // دوائر الإضاءة الكبيرة
    final glow1 = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF667eea).withValues(alpha: 0.08),
              const Color(0xFF667eea).withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.8, size.height * 0.2),
              radius: 200 + math.sin(progress * math.pi * 2) * 20,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.8, size.height * 0.2),
      200 + math.sin(progress * math.pi * 2) * 20,
      glow1,
    );

    final glow2 = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF764ba2).withValues(alpha: 0.06),
              const Color(0xFF764ba2).withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.2, size.height * 0.8),
              radius: 160 + math.cos(progress * math.pi * 2) * 15,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.8),
      160 + math.cos(progress * math.pi * 2) * 15,
      glow2,
    );
  }

  @override
  bool shouldRepaint(covariant ParticleBackgroundPainter old) =>
      old.progress != progress;
}

/// إنشاء جسيمات عشوائية
List<Particle> generateParticles(int count) {
  final rng = math.Random(42);
  return List.generate(count, (_) {
    return Particle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      radius: rng.nextDouble() * 2 + 0.5,
      speed: rng.nextDouble() * 0.3 + 0.1,
      opacity: rng.nextDouble() * 0.5 + 0.2,
    );
  });
}
