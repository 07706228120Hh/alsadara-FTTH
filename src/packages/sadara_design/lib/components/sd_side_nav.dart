/// القائمة الجانبية الموحّدة — نظام تصميم الصدارة (الإصدار 2).
///
/// مكوّن واحد لكل الصفحات بدل القوائم الجانبية والأدراج المتفرّقة:
///  • الهاتف (<600): درج (Drawer) من جهة البداية، عرض حتى 304 أو 86% من الشاشة.
///  • الآيباد وسطح المكتب: شريط أيقونات ثلاثية الأبعاد بعرض 72.
///    عند اقتراب الماوس من الأيقونات تتوسّع القائمة (224) وتدفع الصفحة جانباً
///    بسلاسة فلا يُغطّى أي زر، وتعود شريطاً تلقائياً عند إبعاد الماوس عنها.
///    زر التثبيت 📌 في رأس القائمة يبقيها مفتوحة دائماً (مفيد للّمس)،
///    والتثبيت مشترك بين كل الصفحات خلال الجلسة ([SdSideNav.pinned]).
///
/// كل عنصر زر مستقل ملوّن بلون مجموعته، ثلاثي الأبعاد: تدرّج + حافة سفلية صلبة
/// + إطار أسود + مكعّب أيقونة أبيض. يرتفع عند المرور، وينضغط عند النقر،
/// والعنصر الحالي بحلقة بيضاء ومؤشّر. نفس المقاسات في كل الصفحات:
/// ارتفاع 46، مكعّب 30 (أيقونة 17)، نص 13.5 عريض أبيض.
///
/// الاستخدام الأسهل عبر [SdNavShell]:
/// ```dart
/// SdNavShell(
///   appBar: SdAppBar(title: 'الرئيسية'),
///   title: 'رمز الصدارة',
///   sections: [SdNavSection(title: 'الإدارة', items: [...])],
///   footer: [SdNavItem(id: 'logout', label: 'تسجيل الخروج', icon: Icons.logout, danger: true, onTap: _logout)],
///   selectedId: 'home',
///   body: ...,
/// )
/// ```
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/sd_theme.dart';
import '../tokens/sd_colors.dart';
import '../tokens/sd_metrics.dart';
import '../tokens/sd_responsive.dart';
import '../tokens/sd_typography.dart';
import 'sd_basics.dart';

// ═══════════════════════════════════════════════════════════════════
// النموذج
// ═══════════════════════════════════════════════════════════════════

/// عنصر في القائمة الجانبية.
class SdNavItem {
  const SdNavItem({
    required this.id,
    required this.label,
    required this.icon,
    this.onTap,
    this.group = SdGroup.admin,
    this.badge,
    this.danger = false,
    this.enabled = true,
    this.hint,
  });

  /// معرّف ثابت (يُقارن مع [SdSideNav.selectedId]).
  final String id;
  final String label;
  final IconData icon;

  /// يُستدعى بعد إغلاق الدرج/القائمة المنبثقة تلقائياً.
  final VoidCallback? onTap;

  /// لون الزر حسب مجموعة الخدمة.
  final SdGroup group;

  /// رقم الشارة (0/null = بلا شارة).
  final int? badge;

  /// عنصر خطِر (تسجيل الخروج/حذف) بلون أحمر.
  final bool danger;

  /// false = يظهر رمادياً (مثلاً لا صلاحية) ويبقى قابلاً للضغط إن وُجد onTap.
  final bool enabled;

  /// سطر وصفي صغير تحت الاسم (يظهر في الوضع الموسّع فقط).
  final String? hint;
}

/// مجموعة عناصر بعنوان اختياري.
class SdNavSection {
  const SdNavSection({this.title, required this.items});
  final String? title;
  final List<SdNavItem> items;
}

// ═══════════════════════════════════════════════════════════════════
// الهيكل: صفحة + قائمة جانبية متجاوبة
// ═══════════════════════════════════════════════════════════════════

class SdNavShell extends StatelessWidget {
  const SdNavShell({
    super.key,
    required this.body,
    required this.sections,
    this.footer = const [],
    this.appBar,
    this.selectedId,
    this.title,
    this.subtitle,
    this.logo,
    this.backgroundColor,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.scaffoldKey,
    this.applyTheme = true,
    this.showNav = true,
  });

  final Widget body;
  final List<SdNavSection> sections;
  final List<SdNavItem> footer;
  final PreferredSizeWidget? appBar;
  final String? selectedId;
  final String? title;
  final String? subtitle;
  final Widget? logo;
  final Color? backgroundColor;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final GlobalKey<ScaffoldState>? scaffoldKey;

  /// يطبّق SdTheme + RTL على الصفحة.
  final bool applyTheme;

  /// false = إخفاء القائمة (مثلاً أثناء التحميل).
  final bool showNav;

  @override
  Widget build(BuildContext context) {
    final page = Builder(builder: (context) {
      final phone = context.sd.isPhone;
      SdSideNav nav({required bool inDrawer}) => SdSideNav(
            sections: sections,
            footer: footer,
            selectedId: selectedId,
            title: title,
            subtitle: subtitle,
            logo: logo,
            inDrawer: inDrawer,
          );
      return Scaffold(
        key: scaffoldKey,
        backgroundColor: backgroundColor ?? SdColors.ground,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        drawer: showNav && phone ? SdSideNav.drawer(context, nav(inDrawer: true)) : null,
        body: showNav && !phone
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  nav(inDrawer: false),
                  Expanded(child: body),
                ],
              )
            : body,
      );
    });
    return applyTheme ? SdTheme.scope(child: page) : page;
  }
}

// ═══════════════════════════════════════════════════════════════════
// القائمة نفسها
// ═══════════════════════════════════════════════════════════════════

class SdSideNav extends StatefulWidget {
  const SdSideNav({
    super.key,
    required this.sections,
    this.footer = const [],
    this.selectedId,
    this.title,
    this.subtitle,
    this.logo,
    this.inDrawer = false,
  });

  final List<SdNavSection> sections;
  final List<SdNavItem> footer;
  final String? selectedId;
  final String? title;
  final String? subtitle;
  final Widget? logo;

  /// true داخل درج الهاتف: موسّعة دائماً، وتُغلق الدرج قبل التنفيذ.
  final bool inDrawer;

  /// تثبيت القائمة مفتوحة (مشترك بين الصفحات). false = تنبثق عند اقتراب الماوس.
  static final ValueNotifier<bool> pinned = ValueNotifier<bool>(false);

  static const double expandedWidth = 224;
  static const double collapsedWidth = 68;

  /// يلفّ القائمة بدرج موحّد الشكل للهاتف (يصلح كـ drawer أو endDrawer).
  static Widget drawer(BuildContext context, Widget nav) {
    final w = MediaQuery.sizeOf(context).width;
    return Drawer(
      width: (w * 0.86).clamp(240.0, 304.0),
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(),
      child: nav,
    );
  }

  @override
  State<SdSideNav> createState() => _SdSideNavState();
}

class _SdSideNavState extends State<SdSideNav> {
  bool _hover = false;
  bool _open = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ─── فتح/إغلاق بالاقتراب: تتوسّع القائمة وتدفع الصفحة جانباً ──────

  void _setHover(bool v) {
    _hover = v;
    _timer?.cancel();
    if (SdSideNav.pinned.value) return;
    if (v && !_open) {
      // تأخير قصير يمنع الفتح عند مرور الماوس عرضاً.
      _timer = Timer(const Duration(milliseconds: 140), () {
        if (mounted && _hover) setState(() => _open = true);
      });
    } else if (!v && _open) {
      _timer = Timer(const Duration(milliseconds: 280), () {
        if (mounted && !_hover) setState(() => _open = false);
      });
    }
  }

  void _hideNow() {
    _timer?.cancel();
    if (_open) setState(() => _open = false);
  }

  void _togglePin() {
    final now = !SdSideNav.pinned.value;
    _hideNow();
    SdSideNav.pinned.value = now;
  }

  void _activate(SdNavItem item) {
    final cb = item.onTap;
    if (widget.inDrawer) {
      Navigator.of(context).maybePop();
      if (cb != null) {
        // ننتظر إغلاق الدرج حتى لا يتعارض مع الانتقال لصفحة أخرى.
        Future.delayed(const Duration(milliseconds: 220), cb);
      }
    } else {
      _hideNow();
      cb?.call();
    }
  }

  // ─── البناء ────────────────────────────────────────────────────

  Widget _panel({required bool collapsed, required bool overlay}) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Container(
      decoration: BoxDecoration(
        color: SdColors.surface,
        borderRadius: BorderRadius.circular(SdRadius.xl),
        border: SdOutline.all,
        boxShadow: overlay
            ? [
                ...SdDepth.raised(),
                BoxShadow(
                  color: const Color(0x401A237E),
                  blurRadius: 40,
                  offset: Offset(rtl ? -16 : 16, 10),
                ),
              ]
            : SdDepth.raised(),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: widget.title,
            subtitle: widget.subtitle,
            logo: widget.logo,
            collapsed: collapsed,
            canPin: !widget.inDrawer,
            pinned: SdSideNav.pinned.value,
            onPin: _togglePin,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  collapsed ? 0 : 12, 8, collapsed ? 0 : 12, 10),
              children: [
                for (var s = 0; s < widget.sections.length; s++) ...[
                  if (s > 0 || widget.sections[s].title != null)
                    _SectionTitle(
                        text: widget.sections[s].title, collapsed: collapsed),
                  for (final item in widget.sections[s].items)
                    _NavTile(
                      item: item,
                      selected: item.id == widget.selectedId,
                      collapsed: collapsed,
                      onTap: () => _activate(item),
                    ),
                ],
              ],
            ),
          ),
          if (widget.footer.isNotEmpty) ...[
            const Divider(height: 1, thickness: 1, color: SdColors.divider),
            Padding(
              padding: EdgeInsets.fromLTRB(
                  collapsed ? 0 : 12, 8, collapsed ? 0 : 12, 10),
              child: Column(
                children: [
                  for (final item in widget.footer)
                    _NavTile(
                      item: item,
                      selected: item.id == widget.selectedId,
                      collapsed: collapsed,
                      onTap: () => _activate(item),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inDrawer) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: _panel(collapsed: false, overlay: false),
        ),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: SdSideNav.pinned,
      builder: (context, pinned, _) {
        final expanded = pinned || _open;
        // أثناء التوسّع تُرسم اللوحة الكاملة بعرضها النهائي وتُقصّ، فلا يحدث
        // تجاوز (overflow) في الإطارات الوسيطة للحركة.
        final Widget content = expanded
            ? ClipRect(
                child: OverflowBox(
                  alignment: AlignmentDirectional.centerStart,
                  minWidth: SdSideNav.expandedWidth,
                  maxWidth: SdSideNav.expandedWidth,
                  child: _panel(collapsed: false, overlay: false),
                ),
              )
            : _panel(collapsed: true, overlay: false);

        return Semantics(
          container: true,
          label: 'القائمة الجانبية',
          child: MouseRegion(
            onEnter: (_) => _setHover(true),
            onExit: (_) => _setHover(false),
            child: AnimatedContainer(
              duration: SdMotion.normal,
              curve: SdMotion.standard,
              width: expanded ? SdSideNav.expandedWidth : SdSideNav.collapsedWidth,
              margin: const EdgeInsetsDirectional.fromSTEB(12, 12, 0, 12),
              child: content,
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// أجزاء داخلية
// ═══════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.logo,
    required this.collapsed,
    required this.canPin,
    required this.pinned,
    required this.onPin,
  });
  final String? title, subtitle;
  final Widget? logo;
  final bool collapsed, canPin, pinned;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final pin = canPin
        ? Tooltip(
            message: pinned ? 'إلغاء التثبيت (إخفاء تلقائي)' : 'تثبيت القائمة مفتوحة',
            child: Material(
              color: pinned ? SdColors.primary : SdColors.surfaceAlt,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SdRadius.sm),
                side: SdOutline.side,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(SdRadius.sm),
                onTap: onPin,
                child: SizedBox(
                  width: SdSpace.touch,
                  height: SdSpace.touch,
                  child: Icon(
                    pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 20,
                    color: pinned ? Colors.white : SdColors.primary,
                  ),
                ),
              ),
            ),
          )
        : null;

    final mark = logo ??
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [SdColors.primaryLight, SdColors.primary],
            ),
            borderRadius: BorderRadius.circular(12),
            border: SdOutline.all,
            boxShadow: const [
              BoxShadow(color: SdColors.primaryEdge, offset: Offset(0, 3)),
            ],
          ),
          child: const Text('ص',
              style: TextStyle(
                  fontFamily: SdText.family,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
        );

    if (collapsed) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: SdColors.divider)),
        ),
        child: Center(child: SizedBox(width: 40, height: 40, child: mark)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: SdColors.divider)),
      ),
      child: Row(
        children: [
          SizedBox(width: 40, height: 40, child: mark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title ?? 'القائمة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SdText.titleSm),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SdText.caption),
              ],
            ),
          ),
          if (pin != null) pin,
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.collapsed});
  final String? text;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    if (collapsed || text == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Divider(height: 1, thickness: 1, color: SdColors.divider),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(6, 14, 6, 6),
      child: Text(text!,
          style: const TextStyle(
              fontFamily: SdText.family,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: SdColors.muted,
              letterSpacing: .2)),
    );
  }
}

/// زر قائمة مستقل ملوّن ثلاثي الأبعاد.
class _NavTile extends StatefulWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });
  final SdNavItem item;
  final bool selected, collapsed;
  final VoidCallback onTap;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  static const _dangerTone = SdTone(
    light: Color(0xFFEF5350),
    base: Color(0xFFC62828),
    edge: Color(0xFF7F0000),
    tint: Color(0xFFFFEBEE),
    tintEdge: Color(0xFFFFCDD2),
    text: Color(0xFFB71C1C),
  );

  static const _offTone = SdTone(
    light: Color(0xFFB0BEC5),
    base: Color(0xFF90A4AE),
    edge: Color(0xFF546E7A),
    tint: Color(0xFFECEFF1),
    tintEdge: Color(0xFFCFD8DC),
    text: Color(0xFF546E7A),
  );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final t = !item.enabled
        ? _offTone
        : item.danger
            ? _dangerTone
            : item.group.tone;
    final sel = widget.selected;
    final badge = item.badge ?? 0;

    // عمق الحافة: عادي 5، مرور 7، ضغط 1.
    final depth = _down ? 1.0 : (_hover ? 8.0 : 5.0);
    final lift = _down ? 4.0 : (_hover ? -4.0 : 0.0);
    // عند المرور: يرتفع الزر ويكبر قليلاً ويزداد سطوعاً ويميل مكعّب الأيقونة.
    final top = _hover ? Color.lerp(t.light, Colors.white, .22)! : t.light;

    // مكعّب الأيقونة الأبيض داخل الزر الملوّن.
    final cube = AnimatedContainer(
      duration: SdMotion.fast,
      curve: SdMotion.bounce,
      width: 30,
      height: 30,
      transformAlignment: Alignment.center,
      transform: _hover
          ? (Matrix4.identity()
            ..setEntry(3, 2, 0.002)
            ..rotateY(-0.35)
            ..rotateX(0.15)
            ..scale(1.12, 1.12, 1.0))
          : Matrix4.identity(),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFE8ECF6)],
        ),
        borderRadius: BorderRadius.circular(10),
        border: SdOutline.all,
        boxShadow: [BoxShadow(color: t.edge.withValues(alpha: .35), offset: const Offset(0, 2), blurRadius: 4)],
      ),
      child: Icon(item.icon, size: 17, color: t.base),
    );

    // الشريط المطوي: مربّع ملوّن مدمج 44×44 بأيقونة بيضاء (بلا مكعّب داخلي).
    final Widget content = widget.collapsed
        ? Center(child: Icon(item.icon, size: 21, color: Colors.white))
        : Row(
            children: [
              cube,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: SdText.family,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Color(0x59000000), offset: Offset(0, 1), blurRadius: 1),
                            ])),
                    if (item.hint != null)
                      Text(item.hint!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: SdText.family,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xDDFFFFFF))),
                  ],
                ),
              ),
              if (sel)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsetsDirectional.only(start: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: SdOutline.all,
                  ),
                ),
            ],
          );

    final button = AnimatedContainer(
      duration: SdMotion.fast,
      curve: Curves.easeOut,
      height: widget.collapsed ? 44 : (item.hint != null ? 54 : 46),
      width: widget.collapsed ? 44 : null,
      transformAlignment: Alignment.center,
      transform: Matrix4.translationValues(0, lift, 0)
        ..scale(_hover && !_down ? (widget.collapsed ? 1.08 : 1.03) : 1.0,
            _hover && !_down ? (widget.collapsed ? 1.08 : 1.03) : 1.0, 1.0),
      padding: EdgeInsets.symmetric(horizontal: widget.collapsed ? 0 : 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.collapsed ? 13 : SdRadius.md),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, t.base],
        ),
        border: _focus
            ? Border.all(color: SdColors.accentGlow, width: SdOutline.focusWidth)
            : sel
                ? Border.all(color: Colors.white, width: SdOutline.focusWidth)
                : SdOutline.all,
        boxShadow: [
          // لمعة علوية داخلية
          BoxShadow(
            color: Colors.white.withValues(alpha: sel ? .35 : .18),
            offset: const Offset(0, 1),
            spreadRadius: -1,
          ),
          // الحافة الصلبة (سماكة المجسّم)
          BoxShadow(
              color: t.edge.withValues(alpha: .5),
              offset: Offset(0, (widget.collapsed ? depth * .75 : depth) * .5),
              blurRadius: 2),
          // توهّج ناعم بلون الزر
          BoxShadow(
            color: t.base.withValues(alpha: _hover ? .6 : .28),
            offset: Offset(0, depth + 8),
            blurRadius: _hover ? 22 : 12,
            spreadRadius: -6,
          ),
          if (sel)
            const BoxShadow(color: Colors.white, spreadRadius: 2.5),
        ],
      ),
      child: content,
    );

    final withBadge = Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        if (badge > 0)
          PositionedDirectional(
            top: -7,
            end: -6,
            child: SdBadge(count: badge),
          ),
      ],
    );

    final interactive = FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      onShowHoverHighlight: (_) {},
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() {
          _hover = false;
          _down = false;
        }),
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) {
          setState(() => _down = false);
          widget.onTap();
        },
        child: Padding(
          // مسافة بين الأزرار تترك مكاناً للحافة السفلية — أزرار معزولة.
          padding: widget.collapsed
              ? const EdgeInsets.only(top: 3, bottom: 8)
              : const EdgeInsets.only(top: 4, bottom: 9),
          child: widget.collapsed ? Center(child: withBadge) : withBadge,
        ),
      ),
      ),
    );

    return Semantics(
      button: true,
      selected: sel,
      enabled: item.enabled,
      label: item.label,
      child: widget.collapsed
          ? Tooltip(
              message: item.label,
              preferBelow: false,
              waitDuration: const Duration(milliseconds: 400),
              child: interactive,
            )
          : interactive,
    );
  }
}
