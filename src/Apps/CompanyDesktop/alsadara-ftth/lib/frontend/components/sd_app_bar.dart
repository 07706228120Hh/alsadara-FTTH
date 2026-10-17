/// الشريط العلوي الموحّد: نيلي بحافّة سفلية بارزة، عنوان + سطر حالة اختياري،
/// وأزرار إجراءات بأسماء (لا أيقونات مبهمة).
library;

import 'package:flutter/material.dart';

import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_responsive.dart';
import '../tokens/sd_typography.dart';

class SdAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SdAppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleOk,
    this.actions,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.onBack,
    this.bottom,
  });

  final String title;

  /// سطر ثانوي تحت العنوان (مثل حالة الاتصال).
  final String? subtitle;

  /// null = سطر عادي، true = نقطة خضراء، false = نقطة حمراء.
  final bool? subtitleOk;
  final List<Widget>? actions;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  /// سلوك مخصّص لزر العودة الموحّد (مثل تنظيف قبل pop)؛ null = Navigator.maybePop.
  final VoidCallback? onBack;

  /// شريط سفلي اختياري (عادةً [SdTabBar] للتبويبات). يُعرض فوق حافّة البروز
  /// داخل منطقة `AppBar.bottom`؛ null = لا شريط (السلوك الأصلي).
  final PreferredSizeWidget? bottom;

  static const double _edge = 6;

  double get _bottomHeight => bottom?.preferredSize.height ?? 0;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (subtitle != null ? 10 : 0) + _edge + _bottomHeight);

  /// زر العودة الموحّد: يُبنى تلقائياً في فتحة leading حين يمكن العودة ولا يوجد
  /// leading مخصّص، بدل سهم Material العادي — ليكون الشكل والمكان والاتجاه
  /// موحّدين في كل الشاشات.
  Widget? _resolveLeading(BuildContext context) {
    if (leading != null) return leading;
    if (!automaticallyImplyLeading) return null;
    // صفحة جذرية فيها درج (القائمة الجانبية على الهاتف) → زر قائمة في مكان الرجوع.
    // (إن أمكن الرجوع يبقى زر الرجوع، ويُضاف زر القائمة في آخر الإجراءات.)
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null && scaffold.hasDrawer && !Navigator.of(context).canPop()) {
      return _SdBackButton(
        icon: Icons.menu_rounded,
        label: 'القائمة',
        onBack: () => scaffold.openDrawer(),
      );
    }
    if (!Navigator.of(context).canPop()) return null;
    return _SdBackButton(onBack: onBack);
  }

  @override
  Widget build(BuildContext context) {
    final resolvedLeading = _resolveLeading(context);
    final scaffold = Scaffold.maybeOf(context);
    final menuInActions = automaticallyImplyLeading &&
        leading == null &&
        scaffold != null &&
        scaffold.hasDrawer &&
        Navigator.of(context).canPop();
    final allActions = <Widget>[
      ...?actions,
      if (menuInActions)
        _SdBackButton(
          icon: Icons.menu_rounded,
          label: 'القائمة',
          onBack: () => scaffold.openDrawer(),
        ),
    ];
    return AppBar(
      backgroundColor: SdColors.primary,
      flexibleSpace: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: [SdColors.primaryEdge, SdColors.primary, SdColors.primaryEdge],
          ),
        ),
      ),
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leading: resolvedLeading,
      leadingWidth: resolvedLeading is _SdBackButton
          ? context.sd.touchTarget + SdSpace.sm + SdSpace.xs
          : null,
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: kToolbarHeight + (subtitle != null ? 10 : 0),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: context.sd.appBarTitle,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFF3DFA6))),
          if (subtitle != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitleOk != null) ...[
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: subtitleOk! ? const Color(0xFF66BB6A) : const Color(0xFFEF5350),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: SdText.family,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC8E6C9))),
                ),
              ],
            ),
        ],
      ),
      actions: allActions.isEmpty
          ? null
          : [
              ...allActions,
              const SizedBox(width: SdSpace.xs),
            ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(_edge + _bottomHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (bottom != null) bottom!,
            const SizedBox(
              height: _edge,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [SdColors.gold, Color(0x00C9A44C)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط تبويبات موحّد بثيم sd — يُمرَّر كـ [SdAppBar.bottom].
///
/// خلفية نيلية (SdColors.primary)، التبويب المحدّد ومؤشّره أبيض، وغير المحدّد
/// أبيض شفاف، بخط Cairo. يحافظ على نفس [TabController] والفهارس.
class SdTabBar extends StatelessWidget implements PreferredSizeWidget {
  const SdTabBar({
    super.key,
    required this.tabs,
    this.controller,
    this.isScrollable = false,
    this.height = 48,
  });

  final List<Widget> tabs;
  final TabController? controller;
  final bool isScrollable;

  /// ارتفاع الشريط (ارفعه للتبويبات ذات الأيقونة + النص).
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SdColors.primary,
      height: height,
      child: TabBar(
        controller: controller,
        tabs: tabs,
        isScrollable: isScrollable,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
            fontFamily: SdText.family, fontSize: 14, fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(
            fontFamily: SdText.family, fontSize: 14, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// زر العودة الموحّد في فتحة leading: بنفس لغة SdAppBarAction (حاوية نيلية
/// بحافّة سفلية خفيفة) لكن أيقونة فقط مع تلميح «رجوع» — ثابت الشكل والمكان
/// والاتجاه في كل الشاشات. يستخدم `Icons.arrow_back` الذي ينعكس تلقائياً في RTL،
/// وينادي `Navigator.maybePop` كالسلوك الافتراضي.
class _SdBackButton extends StatelessWidget {
  const _SdBackButton({
    this.onBack,
    this.icon = Icons.arrow_back,
    this.label = 'رجوع',
  });
  final VoidCallback? onBack;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final size = context.sd.touchTarget;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: SdSpace.xs),
      child: Tooltip(
        message: label,
        child: Semantics(
          button: true,
          label: label,
          child: Material(
            color: SdColors.primaryMid,
            borderRadius: BorderRadius.circular(SdRadius.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(SdRadius.sm),
              onTap: onBack ?? () => Navigator.maybePop(context),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(SdRadius.sm),
                  border: SdOutline.all,
                  boxShadow: const [
                    BoxShadow(color: SdColors.primaryEdge, offset: Offset(0, 4)),
                  ],
                ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زر إجراء في الشريط العلوي: أيقونة + اسم (يختفي الاسم في الشاشات الضيقة
/// ويبقى كتلميح).
class SdAppBarAction extends StatelessWidget {
  const SdAppBarAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.success = false,
    this.iconOnly = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// تنبيه (مثل «الموقع متوقف») بلون أحمر فاتح.
  final bool danger;

  /// حالة نشطة/سليمة بلون أخضر (مثل «الموقع يعمل»).
  final bool success;

  /// أيقونة فقط دائماً (بلا نص) — التسمية تبقى تلميحاً.
  final bool iconOnly;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    // الاسم بجانب الأيقونة عند اتّساع العرض فقط؛ وإلا أيقونة + تلميح (يمنع تجاوز
    // صفّ الأزرار على العروض المتوسّطة مع تسميات أطول أو أزرار أكثر).
    final l = context.sd;
    final wide = MediaQuery.sizeOf(context).width >= 1160;
    final bg = danger
        ? SdColors.dangerTint
        : success
            ? SdColors.successTint
            : SdColors.primaryMid;
    final fg = danger
        ? const Color(0xFFB71C1C)
        : success
            ? const Color(0xFF1B5E20)
            : Colors.white;
    final edge = danger
        ? const Color(0xFFE57373)
        : success
            ? const Color(0xFF66BB6A)
            : const Color(0xFF0B1150);
    final button = Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(SdRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(SdRadius.sm),
          onTap: onPressed,
          child: Container(
            height: l.touchTarget,
            constraints: BoxConstraints(minWidth: l.touchTarget),
            padding: EdgeInsets.symmetric(horizontal: wide ? 14 : 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SdRadius.sm),
              border: SdOutline.all,
              boxShadow: [BoxShadow(color: edge, offset: const Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: fg),
                if (wide && !iconOnly) ...[
                  const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                          fontFamily: SdText.family,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: fg)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: (badge ?? 0) > 0
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  button,
                  PositionedDirectional(
                    top: -4,
                    end: -4,
                    child: _MiniBadge(count: badge!),
                  ),
                ],
              )
            : button,
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SdColors.danger,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: SdColors.primary, width: 1.5),
      ),
      child: Text(count > 99 ? '+99' : '$count',
          style: const TextStyle(
              fontFamily: SdText.family,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.1)),
    );
  }
}
