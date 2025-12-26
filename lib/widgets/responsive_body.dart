import 'package:flutter/widgets.dart';
import '../utils/breakpoints.dart';

class ResponsiveBody extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;

  const ResponsiveBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final computedMaxWidth = maxWidth ?? _defaultMaxWidth(width);
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: computedMaxWidth),
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        );
      },
    );
  }

  double _defaultMaxWidth(double screenWidth) {
    if (AppBreakpoints.isLargeDesktop(screenWidth)) return 1200;
    if (AppBreakpoints.isDesktop(screenWidth)) return 1000;
    if (AppBreakpoints.isTablet(screenWidth)) return 800;
    return double.infinity;
  }
}
