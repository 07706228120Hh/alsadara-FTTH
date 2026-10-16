/// هيكل الصفحة الموحّد: RTL + خلفية الثيم + الشريط الموحّد + عرض محتوى أقصى،
/// مع حشو وتباعد يتكيّفان مع الهاتف والآيباد وسطح المكتب واحترام حواف النظام.
library;

import 'package:flutter/material.dart';

import '../theme/sd_theme.dart';
import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_responsive.dart';

class SdPage extends StatelessWidget {
  const SdPage({
    super.key,
    required this.body,
    this.appBar,
    this.maxWidth = SdSpace.contentMax,
    this.padding,
    this.scrollable = true,
    this.floatingActionButton,
    this.bottomBar,
    this.drawer,
    this.endDrawer,
    this.applyTheme = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final double maxWidth;

  /// null = حشو تلقائي حسب الجهاز.
  final EdgeInsetsGeometry? padding;

  /// false عندما يحتوي body على قائمة قابلة للتمرير بنفسها.
  final bool scrollable;
  final Widget? floatingActionButton;

  /// شريط سفلي (يُستخدم غالباً على الهاتف لأزرار الإجراء الرئيسية).
  final Widget? bottomBar;
  final Widget? drawer;
  final Widget? endDrawer;

  /// يطبّق SdTheme على الصفحة (افتراضياً) دون المساس بثيم التطبيق العام.
  final bool applyTheme;

  @override
  Widget build(BuildContext context) {
    final page = Builder(builder: (ctx) {
      final l = ctx.sd;
      final pad = padding ??
          EdgeInsets.fromLTRB(l.gutter, l.pick(phone: 14.0, tablet: 20.0, desktop: 24.0), l.gutter,
              l.pick(phone: 24.0, tablet: 28.0, desktop: 32.0));
      final content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: pad, child: body),
        ),
      );
      return Scaffold(
        backgroundColor: SdColors.ground,
        appBar: appBar,
        drawer: drawer,
        endDrawer: endDrawer,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomBar == null
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(l.gutter, 8, l.gutter, 10),
                  child: bottomBar,
                ),
              ),
        body: SafeArea(
          top: appBar == null,
          bottom: bottomBar == null,
          child: scrollable ? SingleChildScrollView(child: content) : content,
        ),
      );
    });
    return applyTheme
        ? SdTheme.scope(child: page)
        : Directionality(textDirection: TextDirection.rtl, child: page);
  }
}
