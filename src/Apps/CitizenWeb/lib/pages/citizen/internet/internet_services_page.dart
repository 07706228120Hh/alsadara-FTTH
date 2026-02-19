import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/app_theme.dart';

/// صفحة خدمات الإنترنت - تنسيق موحد مع خلفية متحركة
class InternetServicesPage extends StatefulWidget {
  const InternetServicesPage({super.key});

  @override
  State<InternetServicesPage> createState() => _InternetServicesPageState();
}

class _InternetServicesPageState extends State<InternetServicesPage>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _particleController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    // موجات متحركة
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // جزيئات متحركة
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();

    // نبض متحرك
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _waveController.dispose();
    _particleController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Stack(
          children: [
            // ═══════════════════════════════════════
            // الخلفية المتحركة
            // ═══════════════════════════════════════
            _buildAnimatedBackground(),

            // ═══════════════════════════════════════
            // المحتوى الرئيسي
            // ═══════════════════════════════════════
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 16),
                    Expanded(child: _buildContent(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// الخلفية المتحركة الجميلة
  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _waveController,
        _particleController,
        _pulseController,
      ]),
      builder: (context, child) {
        return CustomPaint(
          painter: _AnimatedBackgroundPainter(
            waveProgress: _waveController.value,
            particleProgress: _particleController.value,
            pulseProgress: _pulseController.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }

  /// الهيدر الموحد: زر العودة + العنوان
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        // زر العودة الموحد
        _buildBackButton(context),
        const SizedBox(width: 16),
        // العنوان
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'خدمات الإنترنت',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'اختر الخدمة المطلوبة',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
        // أيقونة الصفحة
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.wifi, color: Colors.white, size: 28),
        ),
      ],
    );
  }

  /// زر العودة الموحد
  Widget _buildBackButton(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/citizen/home'),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.arrow_back_ios_new, // سهم لليسار ←
          color: Colors.black87,
          size: 18,
        ),
      ),
    );
  }

  /// محتوى الصفحة: بطاقات الخدمات
  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final spacing = 16.0;

        // حساب أفضل حجم للبطاقات بناءً على المساحة المتاحة
        final maxGridWidth = screenWidth > 500 ? 450.0 : screenWidth - 32;
        final cardWidth = (maxGridWidth - spacing) / 2;
        final cardHeight = (screenHeight - spacing - 20) / 2;
        final aspectRatio = cardWidth / cardHeight.clamp(150, 200);

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxGridWidth),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: aspectRatio.clamp(0.75, 1.0),
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildServiceCard(
                  context,
                  icon: Icons.fiber_new,
                  title: 'اشتراك جديد',
                  subtitle: 'طلب خط إنترنت جديد',
                  color: const Color(0xFF9C27B0),
                  onTap: () => context.go('/citizen/internet/new'),
                ),
                _buildServiceCard(
                  context,
                  icon: Icons.autorenew,
                  title: 'تجديد الاشتراك',
                  subtitle: 'تجديد باقتك الشهرية',
                  color: const Color(0xFF4CAF50),
                  onTap: () => context.go('/citizen/internet/renewal'),
                ),
                _buildServiceCard(
                  context,
                  icon: Icons.build_circle,
                  title: 'طلب صيانة',
                  subtitle: 'إصلاح الأعطال',
                  color: const Color(0xFFFF9800),
                  onTap: () => context.go('/citizen/internet/maintenance'),
                ),
                _buildServiceCard(
                  context,
                  icon: Icons.trending_up,
                  title: 'ترقية الباقة',
                  subtitle: 'الانتقال لباقة أسرع',
                  color: const Color(0xFF2196F3),
                  onTap: () => context.go('/citizen/internet/upgrade'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildServiceCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, color.withOpacity(0.08)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.25), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.15),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // الأيقونة
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [color, color.withOpacity(0.7)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 26),
                ),
                const SizedBox(height: 12),
                // العنوان
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                // الوصف
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                // زر صغير
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ابدأ',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_back_ios_new, size: 10, color: color),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// رسام الخلفية المتحركة
class _AnimatedBackgroundPainter extends CustomPainter {
  final double waveProgress;
  final double particleProgress;
  final double pulseProgress;

  _AnimatedBackgroundPainter({
    required this.waveProgress,
    required this.particleProgress,
    required this.pulseProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // خلفية متدرجة أساسية
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFFF8FAFF),
          const Color(0xFFE8F0FE),
          const Color(0xFFF0F4FF),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // رسم الموجات المتحركة
    _drawWaves(canvas, size);

    // رسم الدوائر النابضة
    _drawPulsingCircles(canvas, size);

    // رسم الجزيئات المتطايرة
    _drawParticles(canvas, size);

    // رسم خطوط الشبكة الخفيفة
    _drawGrid(canvas, size);
  }

  void _drawWaves(Canvas canvas, Size size) {
    final wavePaint = Paint()..style = PaintingStyle.fill;

    // موجة 1 - أزرق فاتح
    final wave1Path = Path();
    wave1Path.moveTo(0, size.height * 0.85);
    for (double x = 0; x <= size.width; x += 1) {
      final y =
          size.height * 0.85 +
          math.sin(
                (x / size.width * 2 * math.pi) + (waveProgress * 2 * math.pi),
              ) *
              20 +
          math.sin(
                (x / size.width * 4 * math.pi) +
                    (waveProgress * 2 * math.pi * 0.5),
              ) *
              10;
      wave1Path.lineTo(x, y);
    }
    wave1Path.lineTo(size.width, size.height);
    wave1Path.lineTo(0, size.height);
    wave1Path.close();

    wavePaint.shader =
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF2196F3).withOpacity(0.15),
            const Color(0xFF2196F3).withOpacity(0.25),
          ],
        ).createShader(
          Rect.fromLTWH(0, size.height * 0.8, size.width, size.height * 0.2),
        );
    canvas.drawPath(wave1Path, wavePaint);

    // موجة 2 - بنفسجي
    final wave2Path = Path();
    wave2Path.moveTo(0, size.height * 0.9);
    for (double x = 0; x <= size.width; x += 1) {
      final y =
          size.height * 0.9 +
          math.sin(
                (x / size.width * 3 * math.pi) +
                    (waveProgress * 2 * math.pi * 1.5),
              ) *
              15 +
          math.cos(
                (x / size.width * 2 * math.pi) + (waveProgress * 2 * math.pi),
              ) *
              8;
      wave2Path.lineTo(x, y);
    }
    wave2Path.lineTo(size.width, size.height);
    wave2Path.lineTo(0, size.height);
    wave2Path.close();

    wavePaint.shader =
        LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF9C27B0).withOpacity(0.1),
            const Color(0xFF9C27B0).withOpacity(0.2),
          ],
        ).createShader(
          Rect.fromLTWH(0, size.height * 0.85, size.width, size.height * 0.15),
        );
    canvas.drawPath(wave2Path, wavePaint);
  }

  void _drawPulsingCircles(Canvas canvas, Size size) {
    final circlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // دوائر في الزوايا
    final circles = [
      Offset(size.width * 0.1, size.height * 0.15),
      Offset(size.width * 0.9, size.height * 0.2),
      Offset(size.width * 0.15, size.height * 0.7),
      Offset(size.width * 0.85, size.height * 0.75),
    ];

    final colors = [
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFFFF9800),
      const Color(0xFF9C27B0),
    ];

    for (int i = 0; i < circles.length; i++) {
      final baseRadius = 30 + (i * 10);
      final animatedRadius = baseRadius + (pulseProgress * 15);
      final opacity = 0.3 - (pulseProgress * 0.2);

      circlePaint.color = colors[i].withOpacity(opacity.clamp(0.05, 0.3));
      canvas.drawCircle(circles[i], animatedRadius, circlePaint);

      // دائرة داخلية
      circlePaint.color = colors[i].withOpacity(0.15);
      canvas.drawCircle(circles[i], baseRadius * 0.6, circlePaint);
    }
  }

  void _drawParticles(Canvas canvas, Size size) {
    final particlePaint = Paint()..style = PaintingStyle.fill;

    final random = math.Random(42); // ثابت للتناسق
    for (int i = 0; i < 25; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;

      // حركة دائرية
      final angle = (particleProgress * 2 * math.pi) + (i * 0.5);
      final radius = 20 + (i % 5) * 10;
      final x = baseX + math.cos(angle) * radius * 0.3;
      final y = baseY + math.sin(angle) * radius * 0.3;

      final particleSize = 2.0 + random.nextDouble() * 4;
      final opacity = 0.1 + random.nextDouble() * 0.2;

      final colors = [
        const Color(0xFF2196F3),
        const Color(0xFF4CAF50),
        const Color(0xFF9C27B0),
        const Color(0xFFFF9800),
      ];

      particlePaint.color = colors[i % 4].withOpacity(opacity);
      canvas.drawCircle(Offset(x, y), particleSize, particlePaint);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF2196F3).withOpacity(0.03)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const spacing = 40.0;

    // خطوط عمودية
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // خطوط أفقية
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimatedBackgroundPainter oldDelegate) {
    return oldDelegate.waveProgress != waveProgress ||
        oldDelegate.particleProgress != particleProgress ||
        oldDelegate.pulseProgress != pulseProgress;
  }
}
