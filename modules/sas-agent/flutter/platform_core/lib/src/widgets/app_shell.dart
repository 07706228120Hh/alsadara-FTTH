import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/staff_login_screen.dart' show LogoutButton;
import '../session.dart';
import '../theme/brand.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'brand_widgets.dart';

/// تبويب في الهيكل الرئيسي. [group] يجمّع التبويبات في Rail على الشاشات العريضة،
/// و[badge] يعرض عدّاداً (تذاكر مفتوحة مثلاً) يُحدَّث عبر ValueNotifier.
class ShellTab {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
  final String? group;
  final ValueListenable<int>? badge;
  /// عنوان/وصف الصفحة — إن حُدّد يُعرض شريط ترويسة فوق المحتوى (بدل AppBar داخل كل شاشة).
  final String? title;
  final String? subtitle;
  const ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.group,
    this.badge,
    this.title,
    this.subtitle,
  });
}

/// هيكل التطبيق الموحّد:
/// - شريط علوي واحد (شارة الهوية · عنوان الصفحة · إجراءات · تبديل الوضع · قائمة المستخدم).
/// - Rail جانبي بمجموعات على الشاشات العريضة، شريط سفلي (+ «المزيد») على الموبايل.
/// - شريط «لا اتصال» عند [offline] = true.
/// RTL يُفرض في [PlatformApp] فقط — لا Directionality هنا.
class AppShell extends StatefulWidget {
  final AppBrand brand;
  final List<ShellTab> tabs;
  final List<Widget> trailingActions;
  /// إجراءات تُعرض في شريط الترويسة (يمين المحتوى) على الشاشات العريضة، وفي AppBar على الموبايل.
  final List<Widget> headerActions;
  final VoidCallback? onLoggedOut;
  final ValueListenable<bool>? offline;
  /// اسم/وصف المستخدم في القائمة (افتراضي من الجلسة).
  final String? userTitle;
  final String? userSubtitle;
  /// أقصى عدد تبويبات في الشريط السفلي قبل «المزيد».
  final int maxBottomTabs;

  const AppShell({
    super.key,
    required this.brand,
    required this.tabs,
    this.trailingActions = const [],
    this.headerActions = const [],
    this.onLoggedOut,
    this.offline,
    this.userTitle,
    this.userSubtitle,
    this.maxBottomTabs = 4,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final Map<int, Widget> _cache = {};
  String get _prefKey => 'pc_tab_${widget.brand.slug}';

  @override
  void initState() {
    super.initState();
    _restoreTab();
  }

  Future<void> _restoreTab() async {
    try {
      final p = await SharedPreferences.getInstance();
      final i = p.getInt(_prefKey);
      if (i != null && i >= 0 && i < widget.tabs.length && mounted) setState(() => _index = i);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant AppShell old) {
    super.didUpdateWidget(old);
    // تغيّرت قائمة التبويبات (نطاق/دور مختلف) → أعد بناء الصفحات
    if (old.tabs.length != widget.tabs.length ||
        !Iterable.generate(widget.tabs.length).every((i) => old.tabs[i].label == widget.tabs[i].label)) {
      _cache.clear();
      if (_index >= widget.tabs.length) _index = 0;
    }
  }

  void _select(int i) {
    setState(() => _index = i);
    _persistTab(i);
  }

  Future<void> _persistTab(int i) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_prefKey, i);
    } catch (_) {}
  }

  Widget _page(int i) => _cache[i] ??= widget.tabs[i].builder();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= Bp.tablet;
      final idx = _index.clamp(0, widget.tabs.length - 1);
      final current = widget.tabs[idx];
      final body = Column(children: [
        if (widget.offline != null) _OfflineBar(offline: widget.offline!),
        if (wide && (current.title != null || widget.headerActions.isNotEmpty))
          _PageHeader(title: current.title ?? current.label, subtitle: current.subtitle, actions: widget.headerActions),
        Expanded(
          child: IndexedStack(
            index: idx,
            children: List.generate(
              widget.tabs.length,
              (i) => i == idx || _cache.containsKey(i) ? _page(i) : const SizedBox(),
            ),
          ),
        ),
      ]);

      if (wide) {
        return Scaffold(
          body: Row(children: [
            _Rail(
              brand: widget.brand,
              tabs: widget.tabs,
              index: _index,
              extended: c.maxWidth >= Bp.wide,
              onSelect: _select,
              trailing: [
                ...widget.trailingActions,
                _UserMenu(brand: widget.brand, onLoggedOut: widget.onLoggedOut, title: widget.userTitle, subtitle: widget.userSubtitle),
              ],
            ),
            VerticalDivider(width: 1, color: context.pal.outline),
            Expanded(child: body),
          ]),
        );
      }

      final visible = widget.tabs.length <= widget.maxBottomTabs + 1
          ? widget.tabs.length
          : widget.maxBottomTabs;
      final hasMore = visible < widget.tabs.length;
      final bottomIndex = _index < visible ? _index : visible; // «المزيد» مختار إن كان التبويب مخفياً
      return Scaffold(
        appBar: AppBar(
          titleSpacing: Space.lg,
          title: BrandBadge(brand: widget.brand, markSize: 32, showPlatform: false),
          actions: [
            ...widget.headerActions,
            ...widget.trailingActions,
            const ThemeToggleButton(),
            _UserMenu(brand: widget.brand, onLoggedOut: widget.onLoggedOut, title: widget.userTitle, subtitle: widget.userSubtitle),
            const SizedBox(width: 4),
          ],
        ),
        body: body,
        bottomNavigationBar: widget.tabs.length < 2 ? null : _FloatingNav(child: NavigationBar(
          selectedIndex: bottomIndex,
          onDestinationSelected: (i) {
            if (hasMore && i == visible) {
              _showMore(context, visible);
            } else {
              _select(i);
            }
          },
          destinations: [
            for (var i = 0; i < visible; i++) _dest(widget.tabs[i]),
            if (hasMore)
              const NavigationDestination(
                icon: Icon(PhosphorIconsRegular.dotsThreeCircle),
                selectedIcon: Icon(PhosphorIconsFill.dotsThreeCircle),
                label: 'المزيد',
              ),
          ],
        )),
      );
    });
  }

  NavigationDestination _dest(ShellTab t) => NavigationDestination(
        icon: _Badged(badge: t.badge, child: Icon(t.icon)),
        selectedIcon: _Badged(badge: t.badge, child: Icon(t.selectedIcon)),
        label: t.label,
      );

  void _showMore(BuildContext context, int from) {
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 8), children: [
          for (var i = from; i < widget.tabs.length; i++)
            ListTile(
              leading: _Badged(badge: widget.tabs[i].badge, child: Icon(i == _index ? widget.tabs[i].selectedIcon : widget.tabs[i].icon)),
              title: Text(widget.tabs[i].label),
              selected: i == _index,
              onTap: () {
                Navigator.pop(c);
                _select(i);
              },
            ),
        ]),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final AppBrand brand;
  final List<ShellTab> tabs;
  final int index;
  final bool extended;
  final ValueChanged<int> onSelect;
  final List<Widget> trailing;
  const _Rail({
    required this.brand,
    required this.tabs,
    required this.index,
    required this.extended,
    required this.onSelect,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    final width = extended ? 252.0 : 84.0;
    final groups = <String?, List<int>>{};
    for (var i = 0; i < tabs.length; i++) {
      groups.putIfAbsent(tabs[i].group, () => []).add(i);
    }
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF0B111B) : pal.surfaceCard,
      ),
      child: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.lg, Space.md, Space.md),
            child: extended
                ? BrandBadge(brand: brand, markSize: 38)
                : BrandMark(brand: brand, size: 40, glow: false),
          ),
          const EnvBadge(),
          const SizedBox(height: Space.sm),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: Space.sm), children: [
              for (final e in groups.entries) ...[
                if (e.key != null && extended)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.xs),
                    child: Text(e.key!, style: t.labelSmall?.copyWith(color: pal.textMuted, letterSpacing: 0.3)),
                  )
                else if (e.key != null)
                  Divider(height: Space.lg, indent: Space.md, endIndent: Space.md, color: pal.outline),
                for (final i in e.value) _RailItem(tab: tabs[i], selected: i == index, extended: extended, onTap: () => onSelect(i)),
              ],
            ]),
          ),
          Divider(height: 1, color: pal.outline),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: extended
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [const ThemeToggleButton(), ...trailing])
                : Column(mainAxisSize: MainAxisSize.min, children: [const ThemeToggleButton(), ...trailing]),
          ),
        ]),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final ShellTab tab;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  const _RailItem({required this.tab, required this.selected, required this.extended, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    final color = selected ? pal.accent : pal.textMuted;
    final child = extended
        ? Row(children: [
            _Badged(badge: tab.badge, child: Icon(selected ? tab.selectedIcon : tab.icon, color: color, size: 21)),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge?.copyWith(color: selected ? pal.accent : pal.textMuted, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
            ),
          ])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            _Badged(badge: tab.badge, child: Icon(selected ? tab.selectedIcon : tab.icon, color: color, size: 22)),
            const SizedBox(height: 3),
            Text(tab.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(color: selected ? pal.text : pal.textMuted, fontWeight: FontWeight.w700, fontSize: 10.5)),
          ]);
    final material = Ink(
        decoration: BoxDecoration(
          borderRadius: Radii.rMd,
          border: Border.all(color: selected ? pal.accent.withValues(alpha: 0.28) : Colors.transparent),
          gradient: selected
              ? LinearGradient(
                  begin: AlignmentDirectional.centerEnd,
                  end: AlignmentDirectional.centerStart,
                  colors: [pal.accent.withValues(alpha: 0.03), pal.accent.withValues(alpha: context.isDark ? 0.15 : 0.12)],
                )
              : null,
        ),
        child: InkWell(
          borderRadius: Radii.rMd,
          onTap: onTap,
          child: Padding(
            padding: extended
                ? const EdgeInsets.symmetric(horizontal: Space.md, vertical: 11)
                : const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: child,
          ),
        ),
      );
    final wrapped = Material(type: MaterialType.transparency, child: material);
    final item = extended ? wrapped : Tooltip(message: tab.label, child: wrapped);
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: item);
  }
}

/// شارة عدد فوق أيقونة (تُخفى عند صفر).
class _Badged extends StatelessWidget {
  final ValueListenable<int>? badge;
  final Widget child;
  const _Badged({this.badge, required this.child});
  @override
  Widget build(BuildContext context) {
    if (badge == null) return child;
    return ValueListenableBuilder<int>(
      valueListenable: badge!,
      builder: (context, n, _) => Badge(
        isLabelVisible: n > 0,
        label: Text(n > 99 ? '99+' : '$n'),
        child: child,
      ),
    );
  }
}

/// قائمة المستخدم: الاسم، الدور/النطاق، تسجيل الخروج.
class _UserMenu extends StatelessWidget {
  final AppBrand brand;
  final VoidCallback? onLoggedOut;
  final String? title;
  final String? subtitle;
  const _UserMenu({required this.brand, this.onLoggedOut, this.title, this.subtitle});

  String get _name {
    final n = title ?? (Session.user ?? '');
    return n.isEmpty ? 'مستخدم' : n;
  }
  String get _sub {
    if (subtitle != null) return subtitle!;
    final parts = <String>[
      switch (Session.kind) {
        AccountKind.regulator => 'الجهة الرقابية',
        AccountKind.company => 'حساب شركة',
        AccountKind.agent => 'حساب وكيل',
        AccountKind.subscriber => 'مشترك',
      },
      if (Session.role.isNotEmpty && Session.kind != AccountKind.subscriber) Session.role,
      if (Session.agent.isNotEmpty) '@${Session.agent}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    return PopupMenuButton<String>(
      tooltip: 'الحساب',
      position: PopupMenuPosition.under,
      onSelected: (v) {
        if (v == 'logout' && onLoggedOut != null) LogoutButton.confirmAndLogout(context, onLoggedOut!);
      },
      itemBuilder: (c) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: pal.accent.withValues(alpha: 0.15),
              child: Text(_name.characters.first.toUpperCase(),
                  style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: Space.md),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_name, style: t.titleSmall?.copyWith(color: pal.text), overflow: TextOverflow.ellipsis),
                Text(_sub, style: t.bodySmall?.copyWith(color: pal.textMuted), overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
        const PopupMenuDivider(),
        if (onLoggedOut != null)
          const PopupMenuItem<String>(
            value: 'logout',
            child: Row(children: [
              Icon(PhosphorIconsBold.signOut, size: 18),
              SizedBox(width: 10),
              Text('تسجيل الخروج'),
            ]),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: pal.accent.withValues(alpha: 0.15),
          child: Text(_name.characters.first.toUpperCase(),
              style: TextStyle(color: pal.accent, fontWeight: FontWeight.w800, fontSize: 13)),
        ),
      ),
    );
  }
}

/// شريط ترويسة الصفحة (عريض): عنوان + وصف + إجراءات.
class _PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const _PageHeader({required this.title, this.subtitle, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final t = Theme.of(context).textTheme;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: Space.x3 - 4),
      decoration: BoxDecoration(
        color: pal.surface.withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: pal.outline)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25, fontSize: 18)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: pal.textMuted)),
          ]),
        ),
        for (final a in actions) ...[const SizedBox(width: Space.sm), a],
      ]),
    );
  }
}

/// شريط تنقّل سفلي عائم بحواف دائرية (موبايل).
class _FloatingNav extends StatelessWidget {
  final Widget child;
  const _FloatingNav({required this.child});
  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: pal.surfaceCard.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: pal.outline),
          boxShadow: Elev.float(context),
        ),
        child: NavigationBarTheme(
          data: NavigationBarTheme.of(context).copyWith(
            backgroundColor: Colors.transparent,
            height: 64,
            indicatorColor: pal.accent.withValues(alpha: 0.14),
            indicatorShape: const StadiumBorder(),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _OfflineBar extends StatelessWidget {
  final ValueListenable<bool> offline;
  const _OfflineBar({required this.offline});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: offline,
        builder: (context, off, _) => AnimatedSwitcher(
          duration: Motion.normal,
          child: !off
              ? const SizedBox.shrink()
              : Material(
                  color: context.pal.danger,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: Space.lg, vertical: 6),
                    child: Row(children: [
                      Icon(PhosphorIconsBold.wifiSlash, color: Colors.white, size: 16),
                      SizedBox(width: Space.sm),
                      Expanded(
                        child: Text('لا اتصال بالخادم — تحقّق من الشبكة',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ]),
                  ),
                ),
        ),
      );
}

/// صفحة داخل التبويب: عنوان + إجراءات + سحب للتحديث + عرض أقصى.
/// (على الموبايل الشريط العلوي يحمل شارة التطبيق، فتُعرض هذه الترويسة داخل المحتوى.)
class TabPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final Widget child;
  final Widget? fab;
  final double maxWidth;
  const TabPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.onRefresh,
    this.fab,
    this.maxWidth = 1100,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pal = context.pal;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.sm),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, style: t.bodySmall?.copyWith(color: pal.textMuted)),
          ]),
        ),
        if (onRefresh != null)
          IconButton(tooltip: 'تحديث', icon: const Icon(PhosphorIconsBold.arrowsClockwise, size: 20), onPressed: onRefresh),
        ...actions,
      ]),
    );
    final content = onRefresh == null ? child : RefreshIndicator(onRefresh: onRefresh!, child: child);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: fab,
      body: Content(
        maxWidth: maxWidth,
        child: Column(children: [header, Expanded(child: content)]),
      ),
    );
  }
}

/// غلاف محتوى بعرض أقصى على الشاشات العريضة.
class Content extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const Content({super.key, required this.child, this.maxWidth = 1100});
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
