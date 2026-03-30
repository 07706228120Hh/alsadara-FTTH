import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// ويدجت للنص المكتوب حرفاً حرفاً
class TypedTextWidget extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration charDuration;

  const TypedTextWidget({
    super.key,
    required this.text,
    required this.style,
    this.charDuration = const Duration(milliseconds: 60),
  });

  @override
  State<TypedTextWidget> createState() => _TypedTextWidgetState();
}

class _TypedTextWidgetState extends State<TypedTextWidget> {
  int _charCount = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.charDuration, (_) {
      if (_charCount < widget.text.length) {
        setState(() => _charCount++);
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(widget.text.substring(0, _charCount), style: widget.style);
  }
}

/// ويدجت للظهور التدريجي عند التمرير
class FadeInOnScroll extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Offset slideOffset;

  const FadeInOnScroll({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.delay = Duration.zero,
    this.slideOffset = const Offset(0, 30),
  });

  @override
  State<FadeInOnScroll> createState() => _FadeInOnScrollState();
}

class _FadeInOnScrollState extends State<FadeInOnScroll>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _opacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _offset = Tween<Offset>(
      begin: widget.slideOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onVisibility(bool visible) {
    if (visible && !_triggered) {
      _triggered = true;
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // تفعيل تلقائي بعد تأخير قصير إذا كان العنصر مرئياً
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onVisibility(true);
    });

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Transform.translate(
          offset: _offset.value,
          child: Opacity(opacity: _opacity.value, child: widget.child),
        );
      },
    );
  }
}

/// ويدجت العداد المتحرك
class AnimatedCounterWidget extends StatefulWidget {
  final int target;
  final String suffix;
  final TextStyle style;
  final Duration duration;

  const AnimatedCounterWidget({
    super.key,
    required this.target,
    this.suffix = '',
    required this.style,
    this.duration = const Duration(milliseconds: 2000),
  });

  @override
  State<AnimatedCounterWidget> createState() => _AnimatedCounterWidgetState();
}

class _AnimatedCounterWidgetState extends State<AnimatedCounterWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(
      begin: 0,
      end: widget.target.toDouble(),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    // بدء العد بعد تأخير
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Text(
          '${_animation.value.toInt()}${widget.suffix}',
          style: widget.style,
        );
      },
    );
  }
}

/// بطاقة الإحصائيات
class StatCard extends StatelessWidget {
  final IconData icon;
  final int value;
  final String suffix;
  final String label;
  final List<Color> gradient;

  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.suffix,
    required this.label,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 800;
    return Container(
      width: isMobile ? (MediaQuery.of(context).size.width - 60) / 2 : null,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 14 : 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(isMobile ? 10 : 12),
            ),
            child: Icon(icon, color: Colors.white, size: isMobile ? 20 : 24),
          ),
          SizedBox(height: isMobile ? 8 : 12),
          AnimatedCounterWidget(
            target: value,
            suffix: suffix,
            style: TextStyle(
              fontSize: isMobile ? 20 : 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: isMobile ? 11 : 13,
              color: Colors.white.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// بطاقة شهادة عميل
class TestimonialCard extends StatelessWidget {
  final String name;
  final String role;
  final String quote;
  final int stars;

  const TestimonialCard({
    super.key,
    required this.name,
    required this.role,
    required this.quote,
    this.stars = 5,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: List.generate(
              stars,
              (_) => const Icon(
                Icons.star_rounded,
                color: Color(0xFFFFB800),
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '"$quote"',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF4B5563),
              height: 1.6,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0] : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    role,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// بطاقة خدمة أنيقة و مدمجة
class LuxuryServiceCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradient;
  final List<String> features;
  final String route;

  const LuxuryServiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
    required this.features,
    required this.route,
  });

  @override
  State<LuxuryServiceCard> createState() => _LuxuryServiceCardState();
}

class _LuxuryServiceCardState extends State<LuxuryServiceCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _glowCtrl;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(widget.route),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          transform: Matrix4.identity()
            ..translate(0.0, _isHovered ? -6.0 : 0.0),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isHovered
                  ? widget.gradient[0].withValues(alpha: 0.4)
                  : const Color(0xFFE2E8F0),
              width: _isHovered ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered
                    ? widget.gradient[0].withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: _isHovered ? 28 : 12,
                offset: Offset(0, _isHovered ? 12 : 4),
                spreadRadius: _isHovered ? 1 : 0,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // أيقونة الخدمة بتدرج لوني مع توهج نابض
                  AnimatedBuilder(
                    animation: _glowCtrl,
                    builder: (_, __) {
                      final glowValue = _glowCtrl.value;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: _isHovered ? 58 : 52,
                        height: _isHovered ? 58 : 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: widget.gradient,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: widget.gradient[0].withValues(
                                alpha: _isHovered
                                    ? 0.4 + glowValue * 0.15
                                    : 0.2,
                              ),
                              blurRadius: _isHovered ? 18 : 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.icon,
                          color: Colors.white,
                          size: _isHovered ? 28 : 24,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 14),
                  // العنوان والوصف
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.description,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // سهم التنقل
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _isHovered
                          ? widget.gradient[0].withValues(alpha: 0.12)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: _isHovered
                          ? widget.gradient[0]
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // خط فاصل يتحول إلى تدرج لوني عند Hover
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: 1.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isHovered
                        ? widget.gradient
                        : [const Color(0xFFE2E8F0), const Color(0xFFE2E8F0)],
                  ),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(height: 12),
              // شارات المميزات
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.features.map((f) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _isHovered
                          ? widget.gradient[0].withValues(alpha: 0.08)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isHovered
                            ? widget.gradient[0].withValues(alpha: 0.2)
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Text(
                      f,
                      style: TextStyle(
                        fontSize: 11,
                        color: _isHovered
                            ? widget.gradient[0]
                            : const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
