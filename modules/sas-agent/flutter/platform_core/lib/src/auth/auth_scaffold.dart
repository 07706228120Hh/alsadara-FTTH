import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../theme/brand.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import '../widgets/brand_widgets.dart';
import 'server_status.dart';

/// التخطيط الموحّد لكل شاشات الدخول في المنصّة (الوزارة/الشركات/الوكلاء/المشتركون).
///
/// - ≥ 840px: لوحة هوية على اليمين (RTL) + بطاقة النموذج على اليسار.
/// - أقل: عمود واحد بشارة التطبيق ثم النموذج.
/// - ثابت في الكل: شارة الهوية، شارة البيئة، حالة الخادم، الإصدار، الدعم، تبديل الوضع.
class AuthScaffold extends StatefulWidget {
  final AppBrand brand;
  /// وصف قصير تحت اسم التطبيق (مثل: «ادخل بحساب الوكيل الذي أصدرته لك شركتك»).
  final String hint;
  /// نقاط تعريفية تظهر في لوحة الهوية على الشاشات العريضة.
  final List<String> highlights;
  /// محتوى النموذج (حقول + زر).
  final Widget form;
  /// عنوان النموذج (افتراضي: «تسجيل الدخول»).
  final String formTitle;

  const AuthScaffold({
    super.key,
    required this.brand,
    required this.hint,
    required this.form,
    this.highlights = const [],
    this.formTitle = 'تسجيل الدخول',
  });

  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

class _AuthScaffoldState extends State<AuthScaffold> with SingleTickerProviderStateMixin {
  // تُهيَّأ في initState لا كسولاً: على الموبايل لا يُبنى _brandPanel فلا يُلمَس _bg،
  // وإنشاؤه لاحقاً داخل dispose كان يبحث عن TickerMode في شجرة معطّلة ⇒ انهيار.
  late final ServerStatus _status;
  late final AnimationController _bg;

  @override
  void initState() {
    super.initState();
    _status = ServerStatus()..start();
    _bg = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _status.dispose();
    _bg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= Bp.tablet;
        if (!wide) return _narrow(context);
        return Row(children: [
          SizedBox(width: (c.maxWidth * 0.46).clamp(360.0, 620.0), child: _brandPanel(context)),
          Expanded(child: _formArea(context, showBadge: false)),
        ]);
      }),
    );
  }

  // ── لوحة الهوية (شاشات عريضة) ──
  Widget _brandPanel(BuildContext context) {
    final b = widget.brand;
    return AnimatedBuilder(
      animation: _bg,
      builder: (context, _) => BrandPanel(
        brand: b,
        animation: _bg.value,
        child: Padding(
          padding: const EdgeInsets.all(Space.x4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              BrandMark(brand: b, size: 46),
              const SizedBox(width: Space.md),
              const Text(PlatformConfig.platformName,
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const Spacer(),
            FadeSlide(
              child: Text(b.title,
                  style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800, height: 1.15)),
            ),
            const SizedBox(height: Space.sm),
            FadeSlide(
              delay: const Duration(milliseconds: 80),
              child: Text(b.tagline,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 15, height: 1.5)),
            ),
            if (widget.highlights.isNotEmpty) ...[
              const SizedBox(height: Space.xxl),
              for (var i = 0; i < widget.highlights.length; i++)
                FadeSlide(
                  delay: Duration(milliseconds: 140 + i * 70),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Space.md),
                    child: Row(children: [
                      Icon(PhosphorIconsFill.checkCircle, color: Colors.white.withValues(alpha: 0.85), size: 18),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(widget.highlights[i],
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, height: 1.45)),
                      ),
                    ]),
                  ),
                ),
            ],
            const Spacer(),
            Text('© ${PlatformConfig.platformName}',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  // ── عمود واحد (موبايل) ──
  Widget _narrow(BuildContext context) {
    final accent = widget.brand.accentFor(Theme.of(context).brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.10), context.pal.surface],
          stops: const [0, 0.45],
        ),
      ),
      child: _formArea(context, showBadge: true),
    );
  }

  // ── منطقة النموذج ──
  Widget _formArea(BuildContext context, {required bool showBadge}) {
    final t = Theme.of(context).textTheme;
    final pal = context.pal;
    return SafeArea(
      child: Stack(children: [
        const Positioned(top: 4, left: 4, child: ThemeToggleButton()),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.x3),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (showBadge) ...[
                  FadeSlide(
                    child: Column(children: [
                      BrandMark(brand: widget.brand, size: 72),
                      const SizedBox(height: Space.lg),
                      Text(widget.brand.title,
                          textAlign: TextAlign.center,
                          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(PlatformConfig.platformName,
                          textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: pal.textMuted)),
                    ]),
                  ),
                  const SizedBox(height: Space.xxl),
                ],
                FadeSlide(
                  delay: const Duration(milliseconds: 90),
                  child: Container(
                    padding: const EdgeInsets.all(Space.xxl),
                    decoration: BoxDecoration(
                      color: pal.surfaceCard,
                      borderRadius: Radii.rXl,
                      border: Border.all(color: pal.outline),
                      boxShadow: Elev.card(context),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                      // رابط المنصّة الرئيسية (البوّابة) — أعلى بطاقة الدخول للتنقّل بين الأنظمة
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => launchUrl(Uri.parse(PlatformConfig.portalUrl),
                              mode: LaunchMode.externalApplication),
                          icon: const Icon(PhosphorIconsBold.house, size: 14),
                          label: Text('${PlatformConfig.platformName} — البوّابة',
                              style: t.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700, color: pal.textMuted)),
                        ),
                      ),
                      const SizedBox(height: Space.sm),
                      Row(children: [
                        if (!showBadge) ...[
                          BrandMark(brand: widget.brand, size: 40, glow: false),
                          const SizedBox(width: Space.md),
                        ],
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(widget.formTitle, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            if (!showBadge)
                              Text(widget.brand.title, style: t.bodySmall?.copyWith(color: pal.textMuted)),
                          ]),
                        ),
                        const EnvBadge(),
                      ]),
                      const SizedBox(height: Space.xs),
                      Text(widget.hint, style: t.bodyMedium?.copyWith(color: pal.textMuted, height: 1.5)),
                      const SizedBox(height: Space.xl),
                      widget.form,
                    ]),
                  ),
                ),
                const SizedBox(height: Space.lg),
                FadeSlide(delay: const Duration(milliseconds: 160), child: _footer(context)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _footer(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pal = context.pal;
    return Column(children: [
      ServerStatusDot(status: _status),
      const SizedBox(height: Space.xs),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
        Text('الإصدار ${PlatformConfig.appVersion}', style: t.bodySmall?.copyWith(color: pal.textMuted)),
        if (PlatformConfig.supportUrl.isNotEmpty) ...[
          Text('·', style: t.bodySmall?.copyWith(color: pal.textMuted)),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2)),
            onPressed: () => launchUrl(Uri.parse(PlatformConfig.supportUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(PhosphorIconsBold.headset, size: 14),
            label: const Text('الدعم الفني', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ]),
    ]);
  }
}
