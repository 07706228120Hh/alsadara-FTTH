import 'package:flutter/material.dart';

/// ويدجت هيكل تحميل للصفحات المحاسبية
class AccountingSkeleton extends StatefulWidget {
  final int rows;
  final int columns;
  const AccountingSkeleton({super.key, this.rows = 5, this.columns = 4});

  @override
  State<AccountingSkeleton> createState() => _AccountingSkeletonState();
}

class _AccountingSkeletonState extends State<AccountingSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header skeleton
              Container(
                height: 20,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Color.lerp(
                    const Color(0xFFE8E8E8),
                    const Color(0xFFF5F5F5),
                    _animation.value,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Row skeletons
              ...List.generate(widget.rows, (rowIndex) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: List.generate(widget.columns, (colIndex) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 14,
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          const Color(0xFFE8E8E8),
                          const Color(0xFFF5F5F5),
                          _animation.value,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  )),
                ),
              )),
            ],
          ),
        );
      },
    );
  }
}

/// ويدجت هيكل تحميل للبطاقات
class AccountingCardSkeleton extends StatefulWidget {
  final int count;
  const AccountingCardSkeleton({super.key, this.count = 4});

  @override
  State<AccountingCardSkeleton> createState() => _AccountingCardSkeletonState();
}

class _AccountingCardSkeletonState extends State<AccountingCardSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(widget.count, (_) => Container(
              width: 200,
              height: 100,
              decoration: BoxDecoration(
                color: Color.lerp(
                  const Color(0xFFE8E8E8),
                  const Color(0xFFF5F5F5),
                  _animation.value,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            )),
          ),
        );
      },
    );
  }
}
