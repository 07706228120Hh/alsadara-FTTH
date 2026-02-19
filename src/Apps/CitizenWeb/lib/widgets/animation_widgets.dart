import 'package:flutter/material.dart';

/// Animation Widgets
/// مكونات الحركة والأنيميشن

/// Fade In Animation
class FadeInAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  const FadeInAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.delay = Duration.zero,
    this.curve = Curves.easeOut,
  });

  @override
  State<FadeInAnimation> createState() => _FadeInAnimationState();
}

class _FadeInAnimationState extends State<FadeInAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fadeAnimation, child: widget.child);
  }
}

/// Slide In Animation
class SlideInAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final SlideDirection direction;
  final double offset;

  const SlideInAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.delay = Duration.zero,
    this.curve = Curves.easeOut,
    this.direction = SlideDirection.bottom,
    this.offset = 50,
  });

  @override
  State<SlideInAnimation> createState() => _SlideInAnimationState();
}

class _SlideInAnimationState extends State<SlideInAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    Offset beginOffset;
    switch (widget.direction) {
      case SlideDirection.top:
        beginOffset = Offset(0, -widget.offset / 100);
        break;
      case SlideDirection.bottom:
        beginOffset = Offset(0, widget.offset / 100);
        break;
      case SlideDirection.left:
        beginOffset = Offset(-widget.offset / 100, 0);
        break;
      case SlideDirection.right:
        beginOffset = Offset(widget.offset / 100, 0);
        break;
    }

    _slideAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(opacity: _fadeAnimation, child: widget.child),
    );
  }
}

enum SlideDirection { top, bottom, left, right }

/// Scale In Animation
class ScaleInAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;
  final double beginScale;

  const ScaleInAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.delay = Duration.zero,
    this.curve = Curves.easeOut,
    this.beginScale = 0.8,
  });

  @override
  State<ScaleInAnimation> createState() => _ScaleInAnimationState();
}

class _ScaleInAnimationState extends State<ScaleInAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _scaleAnimation = Tween<double>(
      begin: widget.beginScale,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: widget.curve));

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(opacity: _fadeAnimation, child: widget.child),
    );
  }
}

/// Staggered List Animation
class StaggeredListAnimation extends StatelessWidget {
  final List<Widget> children;
  final Duration itemDuration;
  final Duration itemDelay;
  final SlideDirection direction;

  const StaggeredListAnimation({
    super.key,
    required this.children,
    this.itemDuration = const Duration(milliseconds: 400),
    this.itemDelay = const Duration(milliseconds: 100),
    this.direction = SlideDirection.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: children.asMap().entries.map((entry) {
        return SlideInAnimation(
          duration: itemDuration,
          delay: Duration(milliseconds: entry.key * itemDelay.inMilliseconds),
          direction: direction,
          child: entry.value,
        );
      }).toList(),
    );
  }
}

/// Bounce Animation
class BounceAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final bool repeat;

  const BounceAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1000),
    this.repeat = true,
  });

  @override
  State<BounceAnimation> createState() => _BounceAnimationState();
}

class _BounceAnimationState extends State<BounceAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(
      begin: 0.0,
      end: -10.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.repeat) {
      _controller.repeat(reverse: true);
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      listenable: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: widget.child,
        );
      },
    );
  }
}

/// Animated Builder Helper
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

/// Rotation Animation
class RotationAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final bool repeat;

  const RotationAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 2),
    this.repeat = true,
  });

  @override
  State<RotationAnimation> createState() => _RotationAnimationState();
}

class _RotationAnimationState extends State<RotationAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    if (widget.repeat) {
      _controller.repeat();
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(turns: _controller, child: widget.child);
  }
}

/// Hero Animation Wrapper
class HeroWrapper extends StatelessWidget {
  final String tag;
  final Widget child;

  const HeroWrapper({super.key, required this.tag, required this.child});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Animated Counter
class AnimatedCounter extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final Duration duration;
  final String? prefix;
  final String? suffix;

  const AnimatedCounter({
    super.key,
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 500),
    this.prefix,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      builder: (context, val, child) {
        return Text('${prefix ?? ''}$val${suffix ?? ''}', style: style);
      },
    );
  }
}

/// Animated Progress Bar
class AnimatedProgressBar extends StatelessWidget {
  final double value;
  final Color? backgroundColor;
  final Color? progressColor;
  final double height;
  final Duration duration;

  const AnimatedProgressBar({
    super.key,
    required this.value,
    this.backgroundColor,
    this.progressColor,
    this.height = 8,
    this.duration = const Duration(milliseconds: 500),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.grey[300],
        borderRadius: BorderRadius.circular(height / 2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: duration,
            curve: Curves.easeOut,
            builder: (context, val, child) {
              return Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: constraints.maxWidth * val,
                  decoration: BoxDecoration(
                    color: progressColor ?? Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Shake Animation
class ShakeAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double offset;
  final VoidCallback? onComplete;

  const ShakeAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 500),
    this.offset = 10,
    this.onComplete,
  });

  @override
  State<ShakeAnimation> createState() => ShakeAnimationState();
}

class ShakeAnimationState extends State<ShakeAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(
      begin: 0,
      end: widget.offset,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticIn));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });
  }

  void shake() {
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      listenable: _animation,
      builder: (context, child) {
        final sineValue =
            _animation.value *
            (1 - _controller.value) *
            ((_controller.value * 4 * 3.14159).clamp(-1, 1));
        return Transform.translate(
          offset: Offset(sineValue, 0),
          child: widget.child,
        );
      },
    );
  }
}

/// Flip Animation
class FlipAnimation extends StatefulWidget {
  final Widget front;
  final Widget back;
  final Duration duration;
  final bool isFlipped;

  const FlipAnimation({
    super.key,
    required this.front,
    required this.back,
    this.duration = const Duration(milliseconds: 600),
    this.isFlipped = false,
  });

  @override
  State<FlipAnimation> createState() => _FlipAnimationState();
}

class _FlipAnimationState extends State<FlipAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _animation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    if (widget.isFlipped) {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(FlipAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFlipped != oldWidget.isFlipped) {
      if (widget.isFlipped) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      listenable: _animation,
      builder: (context, child) {
        final angle = _animation.value * 3.14159;
        final showFront = angle < 3.14159 / 2;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: showFront
              ? widget.front
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(3.14159),
                  child: widget.back,
                ),
        );
      },
    );
  }
}
