/// مكوّنات العرض ثلاثي الأبعاد لوحدة «فحص جودة الإنترنت» — Network Quality
///
/// مجسّمات متساوية القياس (Isometric) مرسومة بـ CustomPainter بلا حزم إضافية:
/// مشهد الشبكة (فايبر → ONU → راوتر → المتصلون)، منصّة التقدّم الدائرية المائلة،
/// قرص الدرجة الكلّية، أعمدة السرعة/زمن الاستجابة/WiFi المجسّمة، شريط الإشارة
/// الضوئية البارز، وأزرار/بطاقات «مادّية» بحافّة سفلية تغوص عند الضغط.
///
/// كل الرسوم مصمَّمة على إحداثيات ثابتة (design space) وتُحجَّم تلقائياً للعرض
/// المتاح، فتبقى متطابقة على ويندوز وأندرويد.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/device_models.dart';
import '../models/quality_models.dart';
import '../services/network_quality_controller.dart' show QualityStage, QualityStageX;
import '../../frontend/tokens/sd_colors.dart' show SdColors;

// ═══════════════════════════ الألوان ═══════════════════════════

class Nq3d {
  Nq3d._();
  static const indigo = SdColors.primary;
  static const indigoDark = Color(0xFF0F1660);
  static const indigoLight = SdColors.primaryLight;
  static const indigoSoft = SdColors.primarySoft;
  static const teal = Color(0xFF00838F);
  static const tealDark = Color(0xFF005662);
  static const fiber = Color(0xFF00ACC1);
  static const ground = Color(0xFFF2F4F8);
  static const groundAlt = Color(0xFFEEF1F6);
  static const ink = Color(0xFF1B1E2B);
  static const muted = Color(0xFF5B6070);
  static const faint = Color(0xFF8A90A2);
  static const edge = Color(0xFFDCE0EC);
  static const cardEdge = Color(0xFFD6DBEA);
  static const sideLeft = Color(0xFFE3E6F0);
  static const sideRight = Color(0xFFC5CBE0);
  static const outline = Color(0xFFD3D8E8);
  static const gridLine = Color(0xFFE6E9F3);
  static const trace = Color(0xFF7E57C2);
  static const glow = Color(0x591A237E);
}

/// شريط تطبيق موحّد بحافّة سفلية بارزة.
PreferredSizeWidget nq3dAppBar(String title, {List<Widget>? actions}) {
  return AppBar(
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    centerTitle: true,
    backgroundColor: Nq3d.indigo,
    foregroundColor: Colors.white,
    elevation: 0,
    scrolledUnderElevation: 0,
    actions: actions,
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(6),
      child: SizedBox(
        height: 6,
        width: double.infinity,
        child: ColoredBox(color: Nq3d.indigoDark),
      ),
    ),
  );
}

/// ظلّ «مادّي»: حافّة صلبة أسفل العنصر + توهّج ناعم.
List<BoxShadow> raisedShadow({
  Color edge = Nq3d.edge,
  double depth = 5,
  Color glow = Nq3d.glow,
}) {
  return [
    BoxShadow(color: edge, offset: Offset(0, depth)),
    BoxShadow(
      color: glow,
      offset: Offset(0, depth + 12),
      blurRadius: 28,
      spreadRadius: -14,
    ),
  ];
}

// ═══════════════════════════ هندسة المجسّمات ═══════════════════════════

/// صندوق متساوي القياس: [top] هو الرأس الخلفي للوجه العلوي، [a] الطول على
/// المحور (يمين‑أسفل)، [b] العمق على المحور (يسار‑أسفل)، [h] الارتفاع.
class IsoBox {
  const IsoBox(this.top, this.a, this.b, this.h);
  final Offset top;
  final double a;
  final double b;
  final double h;

  static const double _k = 0.8660254;

  /// عمود بقاعدة مربّعة [w] وارتفاع [height]؛ [x] محور العمود و[yBase] الرأس
  /// الخلفي لقاعدته.
  factory IsoBox.prism(double x, double yBase, double w, double height) =>
      IsoBox(Offset(x, yBase - height), w, w, height);

  Offset get right => top + Offset(a * _k, a * .5);
  Offset get front => top + Offset((a - b) * _k, (a + b) * .5);
  Offset get left => top + Offset(-b * _k, b * .5);

  List<Offset> get topFace => [top, right, front, left];
  List<Offset> get leftFace =>
      [left, front, front.translate(0, h), left.translate(0, h)];
  List<Offset> get rightFace =>
      [front, right, right.translate(0, h), front.translate(0, h)];

  /// صورة الصندوق الخارجية (لرسم «خيال» العمود الأقصى).
  List<Offset> get silhouette => [
        top,
        right,
        right.translate(0, h),
        front.translate(0, h),
        left.translate(0, h),
        left,
      ];
}

/// ألوان أوجه المجسّم الثلاثة.
class IsoShade {
  const IsoShade(this.top, this.left, this.right, [this.stroke]);
  final Color top;
  final Color left;
  final Color right;
  final Color? stroke;

  static const light =
      IsoShade(Colors.white, Nq3d.sideLeft, Nq3d.sideRight, Nq3d.outline);
  static const platform = IsoShade(Colors.white, Nq3d.edge, Nq3d.sideRight);
  static const router =
      IsoShade(Nq3d.indigoLight, Nq3d.indigo, Nq3d.indigoDark);
  static const accessPoint =
      IsoShade(Color(0xFF9575CD), Color(0xFF5E35B1), Color(0xFF4527A0));
  static const muted =
      IsoShade(Nq3d.groundAlt, Nq3d.edge, Nq3d.sideRight);
  static const teal =
      IsoShade(SdColors.accentTintEdge, Nq3d.fiber, Nq3d.teal);
  static const amber =
      IsoShade(SdColors.warningTintEdge, Color(0xFFFFB74D), SdColors.warning);
}

/// ألوان أوجه المجسّم حسب التقييم.
IsoShade ratingShade(QualityRating r) {
  switch (r) {
    case QualityRating.excellent:
      return const IsoShade(
          Color(0xFF81C784), SdColors.success, SdColors.success);
    case QualityRating.good:
      return const IsoShade(
          Color(0xFFC5E1A5), Color(0xFF9CCC65), Color(0xFF689F38));
    case QualityRating.fair:
      return const IsoShade(
          Color(0xFFFFE082), Color(0xFFFBC02D), Color(0xFFF57F17));
    case QualityRating.poor:
      return const IsoShade(
          Color(0xFFFFCC80), Color(0xFFFB8C00), SdColors.warningEdge);
    case QualityRating.bad:
      return const IsoShade(
          Color(0xFFEF9A9A), SdColors.danger, Color(0xFFB71C1C));
    case QualityRating.unknown:
      return IsoShade.muted;
  }
}

Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

Color _a(Color c, double opacity) =>
    c.withValues(alpha: (c.a * opacity).clamp(0.0, 1.0));

void paintIsoBox(Canvas canvas, IsoBox box, IsoShade s, {double opacity = 1}) {
  if (opacity <= 0.001) return;
  final p = Paint()..style = PaintingStyle.fill;
  canvas.drawPath(_poly(box.leftFace), p..color = _a(s.left, opacity));
  canvas.drawPath(_poly(box.rightFace), p..color = _a(s.right, opacity));
  canvas.drawPath(_poly(box.topFace), p..color = _a(s.top, opacity));
  if (s.stroke != null) {
    canvas.drawPath(
      _poly(box.topFace),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _a(s.stroke!, opacity),
    );
  }
}

void _dashed(Canvas canvas, Path path, Paint paint,
    {double dash = 5, double gap = 6, double phase = 0}) {
  final period = dash + gap;
  for (final m in path.computeMetrics()) {
    double d = -(phase % period);
    while (d < m.length) {
      final s = math.max(0.0, d);
      final e = math.min(m.length, d + dash);
      if (e > s) canvas.drawPath(m.extractPath(s, e), paint);
      d += period;
    }
  }
}

void _label(Canvas canvas, String text, Offset center,
    {double size = 11,
    FontWeight weight = FontWeight.w800,
    Color color = const Color(0xFF3D4356),
    double opacity = 1,
    TextDirection dir = TextDirection.rtl}) {
  if (opacity <= 0.001) return;
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: size,
        fontWeight: weight,
        height: 1.1,
        color: _a(color, opacity),
      ),
    ),
    textDirection: dir,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

Paint _stroke(Color c, double w, {bool round = true}) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = round ? StrokeCap.round : StrokeCap.butt
  ..strokeJoin = StrokeJoin.round
  ..color = c;

Paint _fill(Color c) => Paint()
  ..style = PaintingStyle.fill
  ..color = c;

/// رسّام يعمل على مساحة تصميم ثابتة ويُحجَّم للحجم الفعلي.
abstract class _DesignPainter extends CustomPainter {
  _DesignPainter(this.design, {super.repaint});
  final Size design;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / design.width, size.height / design.height);
    paintDesign(canvas);
    canvas.restore();
  }

  void paintDesign(Canvas canvas);
}

/// يلفّ رسّاماً بمساحة تصميم ثابتة داخل عرض متجاوب يحفظ النسبة.
class _DesignCanvas extends StatelessWidget {
  const _DesignCanvas({
    super.key,
    required this.design,
    required this.painter,
    this.maxWidth,
    this.semanticLabel,
    this.overlay,
  });
  final Size design;
  final CustomPainter painter;
  final double? maxWidth;
  final String? semanticLabel;
  final Widget Function(double scale)? overlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      double w = c.maxWidth.isFinite ? c.maxWidth : design.width;
      if (maxWidth != null) w = math.min(w, maxWidth!);
      final scale = w / design.width;
      final h = design.height * scale;
      return Center(
        child: Semantics(
          label: semanticLabel,
          image: semanticLabel != null,
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ExcludeSemantics(
                    child: CustomPaint(painter: painter),
                  ),
                ),
                if (overlay != null) Positioned.fill(child: overlay!(scale)),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// متحكّم حركة متكرّرة مشترك (للتدفّق/النبض/الطفو).
mixin _LoopTicker<T extends StatefulWidget> on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: loopDuration,
  )..repeat();

  Duration get loopDuration => const Duration(milliseconds: 2200);

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}

// ═══════════════════ 1) مشهد الواجهة الرئيسية ═══════════════════

/// مشهد مجسّم: كابل فايبر يدخل الـONU ثم الراوتر مع بثّ WiFi.
class HomeNetworkScene3D extends StatefulWidget {
  const HomeNetworkScene3D({super.key, this.maxWidth = 360});
  final double maxWidth;

  @override
  State<HomeNetworkScene3D> createState() => _HomeNetworkScene3DState();
}

class _HomeNetworkScene3DState extends State<HomeNetworkScene3D>
    with SingleTickerProviderStateMixin<HomeNetworkScene3D>, _LoopTicker<HomeNetworkScene3D> {
  @override
  Duration get loopDuration => const Duration(milliseconds: 1800);

  @override
  Widget build(BuildContext context) {
    return _DesignCanvas(
      design: const Size(360, 214),
      maxWidth: widget.maxWidth,
      semanticLabel: 'مشهد ثلاثي الأبعاد: كابل فايبر يدخل وحدة ONU ثم الراوتر',
      painter: _HomeScenePainter(loop),
    );
  }
}

class _HomeScenePainter extends _DesignPainter {
  _HomeScenePainter(this.t) : super(const Size(360, 214), repaint: t);
  final Animation<double> t;

  @override
  void paintDesign(Canvas canvas) {
    final v = t.value;
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(180, 196), width: 300, height: 32),
        _fill(const Color(0x1A1A237E)));
    paintIsoBox(canvas, const IsoBox(Offset(180, 40), 150, 150, 10),
        IsoShade.platform);
    canvas.drawPath(
        _poly(const [
          Offset(180, 58),
          Offset(278.7, 115),
          Offset(180, 172),
          Offset(81.3, 115)
        ]),
        _stroke(Nq3d.gridLine, 1));

    // الفايبر الداخل إلى الـONU.
    final fin = Path()
      ..moveTo(58, 121)
      ..quadraticBezierTo(72, 110, 90, 122);
    canvas.drawPath(fin, _stroke(_a(Nq3d.fiber, .25), 8));
    canvas.drawPath(fin, _stroke(Nq3d.fiber, 2.5));

    // وصلة ONU → الراوتر (بيانات متدفّقة).
    final link = Path()
      ..moveTo(133, 132)
      ..quadraticBezierTo(152, 152, 175, 116);
    canvas.drawPath(link, _stroke(_a(Nq3d.fiber, .25), 8));
    _dashed(canvas, link, _stroke(Nq3d.fiber, 2.5),
        dash: 5, gap: 6, phase: -v * 22);

    // الـONU.
    paintIsoBox(canvas, const IsoBox(Offset(110, 92), 44, 34, 16),
        IsoShade.light);
    canvas.drawCircle(const Offset(96, 123), 2.4, _fill(Nq3d.teal));
    canvas.drawCircle(
        const Offset(104, 127.5), 2.4, _fill(SdColors.success));
    _label(canvas, 'ONU', const Offset(114, 84), dir: TextDirection.ltr);

    // هوائيات الراوتر.
    canvas.drawLine(const Offset(190, 69), const Offset(190, 30),
        _stroke(Nq3d.indigoDark, 4));
    canvas.drawLine(const Offset(240, 92), const Offset(240, 52),
        _stroke(Nq3d.indigoDark, 4));

    // الراوتر.
    paintIsoBox(canvas, const IsoBox(Offset(200, 63), 70, 50, 22),
        IsoShade.router);
    canvas.drawPath(
        _poly(const [
          Offset(200, 69),
          Offset(248, 96.7),
          Offset(217.3, 114.5),
          Offset(169.3, 86.8)
        ]),
        _stroke(const Color(0x2EFFFFFF), 1));
    const leds = [
      (Offset(171.9, 107.8), SdColors.accentTintEdge),
      (Offset(180.9, 113), SdColors.accentTintEdge),
      (Offset(190, 118.3), Color(0xFFA5D6A7)),
      (Offset(199.1, 123.5), Nq3d.indigoSoft),
    ];
    for (var i = 0; i < leds.length; i++) {
      final blink = i < 2 ? (0.55 + 0.45 * math.sin((v + i * .25) * 2 * math.pi).abs()) : 1.0;
      canvas.drawCircle(leds[i].$1, 2.6, _fill(_a(leds[i].$2, blink)));
    }

    // بثّ WiFi (موجتان تنبضان).
    final w1 = Path()
      ..moveTo(204, 30)
      ..arcToPoint(const Offset(236, 30), radius: const Radius.circular(22));
    final w2 = Path()
      ..moveTo(210, 37)
      ..arcToPoint(const Offset(230, 37), radius: const Radius.circular(13));
    final pulse = 0.55 + 0.45 * math.sin(v * 2 * math.pi);
    canvas.drawPath(w1, _stroke(_a(Nq3d.teal, .9 * pulse), 3));
    canvas.drawPath(w2, _stroke(_a(Nq3d.teal, .7 + .3 * (1 - pulse)), 3));
    canvas.drawCircle(const Offset(220, 43), 3, _fill(Nq3d.teal));
  }

  @override
  bool shouldRepaint(covariant _HomeScenePainter old) => false;
}

// ═══════════════════ 2) خريطة الشبكة لشاشة الإعداد ═══════════════════

/// خريطة شبكة مجسّمة تضيء أجزاؤها حسب الفحوص المختارة.
class NetworkTopology3D extends StatefulWidget {
  const NetworkTopology3D({
    super.key,
    required this.devices,
    required this.fiber,
    required this.speed,
    required this.trace,
    this.maxWidth = 360,
  });
  final bool devices;
  final bool fiber;
  final bool speed;
  final bool trace;
  final double maxWidth;

  @override
  State<NetworkTopology3D> createState() => _NetworkTopology3DState();
}

class _TopologyState {
  double dev = 1, fib = 1, spd = 1, trc = 0;
}

class _NetworkTopology3DState extends State<NetworkTopology3D>
    with SingleTickerProviderStateMixin<NetworkTopology3D>, _LoopTicker<NetworkTopology3D> {
  final _s = _TopologyState();

  @override
  Duration get loopDuration => const Duration(milliseconds: 1600);

  @override
  void initState() {
    super.initState();
    _s
      ..dev = widget.devices ? 1 : .18
      ..fib = widget.fiber ? 1 : .15
      ..spd = widget.speed ? 1 : 0
      ..trc = widget.trace ? 1 : 0;
    loop.addListener(_ease);
  }

  // تقريب تدريجي نحو الحالة المطلوبة على كل إطار (انتقال ناعم).
  void _ease() {
    double step(double cur, double target) =>
        (target - cur).abs() < .01 ? target : cur + (target - cur) * .18;
    _s
      ..dev = step(_s.dev, widget.devices ? 1 : .18)
      ..fib = step(_s.fib, widget.fiber ? 1 : .15)
      ..spd = step(_s.spd, widget.speed ? 1 : 0)
      ..trc = step(_s.trc, widget.trace ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return _DesignCanvas(
      design: const Size(360, 250),
      maxWidth: widget.maxWidth,
      semanticLabel:
          'خريطة الشبكة: الفايبر ثم ONU ثم الراوتر ثم الأجهزة المتصلة، تضيء العناصر حسب الفحوص المختارة',
      painter: _TopologyPainter(loop, _s),
    );
  }
}

class _TopologyPainter extends _DesignPainter {
  _TopologyPainter(this.t, this.s) : super(const Size(360, 250), repaint: t);
  final Animation<double> t;
  final _TopologyState s;

  static const _client = IsoShade.light;

  void _clientBox(Canvas canvas, Offset top, Color screen, double op) {
    paintIsoBox(canvas, IsoBox(top, 28, 28, 18), _client, opacity: op);
    canvas.drawPath(
        _poly([
          top + const Offset(0, 6),
          top + const Offset(13.8, 14),
          top + const Offset(0, 22),
          top + const Offset(-13.8, 14),
        ]),
        _fill(_a(screen, op)));
  }

  @override
  void paintDesign(Canvas canvas) {
    final v = t.value;
    canvas.save();
    canvas.translate(0, 30);

    canvas.drawOval(
        Rect.fromCenter(center: const Offset(180, 205), width: 320, height: 28),
        _fill(const Color(0x1A1A237E)));
    paintIsoBox(
        canvas, const IsoBox(Offset(180, 10), 180, 180, 9), IsoShade.platform);
    canvas.drawPath(
        _poly(const [
          Offset(180, 28),
          Offset(304.7, 100),
          Offset(180, 172),
          Offset(55.3, 100)
        ]),
        _stroke(Nq3d.gridLine, 1));

    // الفايبر.
    final fiber = Path()
      ..moveTo(40, 57)
      ..lineTo(70, 73.5)
      ..lineTo(106.4, 94.5);
    canvas.drawPath(fiber, _stroke(_a(Nq3d.fiber, .25 * s.fib), 9));
    canvas.drawPath(fiber, _stroke(_a(Nq3d.fiber, s.fib), 2.6));
    if (s.fib > .5) {
      _dashed(canvas, fiber, _stroke(_a(Colors.white, .8 * s.fib), 1.4),
          dash: 3, gap: 14, phase: -v * 34);
    }

    // ONU → الراوتر.
    canvas.drawLine(const Offset(106.4, 94.5), const Offset(186.9, 116),
        _stroke(Nq3d.indigoLight, 2.6));

    // الراوتر → المتصلون (لاسلكي متدفّق).
    final clients = Path()
      ..moveTo(186.9, 116)
      ..lineTo(214.6, 64)
      ..moveTo(186.9, 116)
      ..lineTo(249.3, 84)
      ..moveTo(186.9, 116)
      ..lineTo(283.9, 104);
    _dashed(canvas, clients, _stroke(_a(Nq3d.indigoSoft, s.dev), 1.8),
        dash: 3, gap: 5, phase: -v * 16);

    // الصناديق من الخلف للأمام.
    _clientBox(canvas, const Offset(214.6, 32), Nq3d.indigoSoft, s.dev);
    _clientBox(canvas, const Offset(249.3, 52), Nq3d.teal, s.dev);

    paintIsoBox(canvas, const IsoBox(Offset(102.1, 59), 44, 34, 16),
        IsoShade.light);
    canvas.drawCircle(const Offset(86.1, 89), 2.6, _fill(_a(Nq3d.fiber, s.fib)));
    canvas.drawCircle(
        const Offset(94.1, 93.5), 2.6, _fill(SdColors.success));

    _clientBox(canvas, const Offset(283.9, 72), Nq3d.indigoSoft, s.dev);

    paintIsoBox(canvas, const IsoBox(Offset(180, 70), 60, 44, 20),
        IsoShade.router);
    canvas.drawCircle(const Offset(154, 108), 2.4, _fill(SdColors.accentTintEdge));
    canvas.drawCircle(
        const Offset(162, 112.6), 2.4, _fill(SdColors.accentTintEdge));
    canvas.drawCircle(
        const Offset(170, 117.2), 2.4, _fill(const Color(0xFFA5D6A7)));

    // أسهم السرعة على سطح الراوتر.
    if (s.spd > .01) {
      final bob = math.sin(v * 2 * math.pi) * 1.5;
      final down = Path()
        ..moveTo(180, 88 + bob)
        ..lineTo(180, 102 + bob)
        ..moveTo(175.5, 97.5 + bob)
        ..lineTo(180, 102 + bob)
        ..lineTo(184.5, 97.5 + bob);
      final up = Path()
        ..moveTo(194, 102 - bob)
        ..lineTo(194, 88 - bob)
        ..moveTo(189.5, 92.5 - bob)
        ..lineTo(194, 88 - bob)
        ..lineTo(198.5, 92.5 - bob);
      canvas.drawPath(down, _stroke(_a(Colors.white, s.spd), 2.4));
      canvas.drawPath(up, _stroke(_a(const Color(0xFFFFCC80), s.spd), 2.4));
    }

    // تتبّع المسار حتى الخادم.
    if (s.trc > .01) {
      final route = Path()
        ..moveTo(180, 68)
        ..quadraticBezierTo(240, -28, 306, -4);
      _dashed(canvas, route, _stroke(_a(Nq3d.trace, s.trc), 2),
          dash: 2, gap: 6, phase: -v * 16);
      for (final p in const [Offset(205, 34), Offset(236, 12), Offset(270, 0)]) {
        canvas.drawCircle(p, 3.5, _fill(_a(Nq3d.trace, s.trc)));
      }
      canvas.drawCircle(const Offset(320, -6), 15,
          _fill(_a(const Color(0xFFEDE7F6), s.trc)));
      canvas.drawCircle(
          const Offset(320, -6), 15, _stroke(_a(Nq3d.trace, s.trc), 2));
      final globe = Path()
        ..moveTo(305, -6)
        ..lineTo(335, -6)
        ..moveTo(320, -21)
        ..cubicTo(312, -12, 312, 0, 320, 9)
        ..moveTo(320, -21)
        ..cubicTo(328, -12, 328, 0, 320, 9);
      canvas.drawPath(globe, _stroke(_a(Nq3d.trace, s.trc), 1.6));
    }

    _label(canvas, 'ONU', const Offset(100, 48), dir: TextDirection.ltr);
    _label(canvas, 'الراوتر', const Offset(194, 156));
    _label(canvas, 'المتصلون', const Offset(262, 134), opacity: s.dev);
    _label(canvas, 'فايبر', const Offset(52, 42),
        size: 10, weight: FontWeight.w700, color: Nq3d.teal, opacity: s.fib);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TopologyPainter old) => true;
}

// ═══════════════════ 3) منصّة التقدّم الدائرية ═══════════════════

/// منصّة دائرية مائلة يمتلئ حولها شريط التقدّم مع نبض مسح وعنصر طافٍ.
/// [progress] بين 0..1، أو null لتقدّم غير محدّد (دوران).
class ProgressDisc3D extends StatefulWidget {
  const ProgressDisc3D({
    super.key,
    required this.progress,
    required this.center,
    this.maxWidth = 360,
  });
  final double? progress;
  final Widget center;
  final double maxWidth;

  @override
  State<ProgressDisc3D> createState() => _ProgressDisc3DState();
}

class _ProgressDisc3DState extends State<ProgressDisc3D>
    with SingleTickerProviderStateMixin<ProgressDisc3D>, _LoopTicker<ProgressDisc3D> {
  @override
  Duration get loopDuration => const Duration(milliseconds: 2200);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: widget.progress ?? 0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (ctx, p, _) => _DesignCanvas(
        design: const Size(360, 270),
        maxWidth: widget.maxWidth,
        painter: _ProgressDiscPainter(
            loop, widget.progress == null ? null : p),
        overlay: (scale) => AnimatedBuilder(
          animation: loop,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, -5 * math.sin(loop.value * math.pi) * scale),
            child: child,
          ),
          child: Align(
            alignment: const Alignment(0, -0.42),
            child: widget.center,
          ),
        ),
      ),
    );
  }
}

class _ProgressDiscPainter extends _DesignPainter {
  _ProgressDiscPainter(this.t, this.p) : super(const Size(360, 270), repaint: t);
  final Animation<double> t;
  final double? p;

  @override
  void paintDesign(Canvas canvas) {
    final v = t.value;
    const c = Offset(180, 200);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(180, 236), width: 304, height: 44),
        _fill(const Color(0x1A1A237E)));
    // جسم القرص (السماكة).
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(180, 216), width: 280, height: 108),
        _fill(Nq3d.sideRight));
    canvas.drawRect(const Rect.fromLTWH(40, 200, 280, 16), _fill(Nq3d.sideRight));
    final face = Rect.fromCenter(center: c, width: 280, height: 108);
    canvas.drawOval(face, _fill(Colors.white));
    canvas.drawOval(face, _stroke(Nq3d.edge, 1));
    canvas.drawOval(Rect.fromCenter(center: c, width: 200, height: 77),
        _stroke(Nq3d.gridLine, 1));
    canvas.drawOval(Rect.fromCenter(center: c, width: 132, height: 51),
        _stroke(Nq3d.gridLine, 1));

    // نبض المسح.
    canvas.drawOval(
        Rect.fromCenter(center: c, width: 2 * (20 + 100 * v), height: 2 * (7.7 + 38.3 * v)),
        _stroke(_a(Nq3d.fiber, .7 * (1 - v)), 2));

    // المسار والتقدّم.
    final ring = Rect.fromCenter(center: c, width: 244, height: 94);
    canvas.drawOval(ring, _stroke(Nq3d.sideLeft, 11));
    final prog = _stroke(Nq3d.indigo, 11);
    if (p == null) {
      canvas.drawArc(ring, v * 2 * math.pi, math.pi / 2, false, prog);
    } else if (p! > 0.002) {
      canvas.drawArc(ring, 0, 2 * math.pi * p!.clamp(0.0, 1.0), false, prog);
    }

    // شعاع ضوئي نحو العنصر الطافي.
    final beam = Path()
      ..moveTo(166, 200)
      ..lineTo(194, 200)
      ..lineTo(188, 120)
      ..lineTo(172, 120)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0x7300ACC1), Color(0x0000ACC1)],
        ).createShader(const Rect.fromLTWH(166, 120, 28, 80)),
    );
    canvas.drawOval(Rect.fromCenter(center: c, width: 88, height: 26),
        _fill(const Color(0x1F1A237E)));
  }

  @override
  bool shouldRepaint(covariant _ProgressDiscPainter old) => old.p != p;
}

// ═══════════════════ 4) قرص الدرجة الكلّية ═══════════════════

/// قرص مجسّم على خلفية داكنة يعرض الدرجة الكلّية (0..100) بحلقة ملوّنة بالتقييم.
class ScoreDisc3D extends StatelessWidget {
  const ScoreDisc3D({
    super.key,
    required this.score,
    required this.color,
    this.maxWidth = 320,
    this.semanticLabel,
  });
  final double score;
  final Color color;
  final double maxWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final target = score.clamp(0.0, 100.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (ctx, s, _) => _DesignCanvas(
        design: const Size(320, 206),
        maxWidth: maxWidth,
        semanticLabel: semanticLabel,
        painter: _ScoreDiscPainter(s / 100, color),
        overlay: (scale) => Align(
          alignment: const Alignment(0, -0.38),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.round().toString(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 64 * scale,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              Text(
                'من 100',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .72),
                  fontSize: 13 * scale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreDiscPainter extends _DesignPainter {
  _ScoreDiscPainter(this.f, this.color) : super(const Size(320, 206));
  final double f;
  final Color color;

  @override
  void paintDesign(Canvas canvas) {
    const c = Offset(160, 150);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(160, 186), width: 268, height: 36),
        _fill(const Color(0x47000000)));
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(160, 166), width: 248, height: 92),
        _fill(const Color(0xFF080C3A)));
    canvas.drawRect(
        const Rect.fromLTWH(36, 150, 248, 16), _fill(const Color(0xFF080C3A)));
    final face = Rect.fromCenter(center: c, width: 248, height: 92);
    canvas.drawOval(face, _fill(const Color(0xFF23308F)));
    canvas.drawOval(face, _stroke(const Color(0x1AFFFFFF), 1));
    final ring = Rect.fromCenter(center: c, width: 208, height: 77.2);
    canvas.drawOval(ring, _stroke(const Color(0x24FFFFFF), 11));
    if (f > 0.002) {
      canvas.drawArc(ring, 0, 2 * math.pi * f, false, _stroke(color, 11));
    }
    canvas.drawOval(Rect.fromCenter(center: c, width: 124, height: 46),
        _fill(const Color(0x0DFFFFFF)));
    canvas.drawOval(Rect.fromCenter(center: c, width: 80, height: 24),
        _fill(const Color(0x52000000)));
  }

  @override
  bool shouldRepaint(covariant _ScoreDiscPainter old) =>
      old.f != f || old.color != color;
}

// ═══════════════════ 5) عمود السرعة المجسّم ═══════════════════

/// عمود مجسّم يرتفع حسب [fraction] (0..1) مع «خيال» الحدّ الأقصى.
class IsoSpeedColumn extends StatelessWidget {
  const IsoSpeedColumn({
    super.key,
    required this.fraction,
    required this.shade,
    this.width = 80,
    this.ghostColor = const Color(0x2EFFFFFF),
  });
  final double fraction;
  final IsoShade shade;
  final double width;
  final Color ghostColor;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutBack,
      builder: (ctx, f, _) => SizedBox(
        width: width,
        height: width * 128 / 80,
        child: CustomPaint(
          painter: _SpeedColumnPainter(f.clamp(0.0, 1.0), shade, ghostColor),
        ),
      ),
    );
  }
}

class _SpeedColumnPainter extends _DesignPainter {
  _SpeedColumnPainter(this.f, this.shade, this.ghost) : super(const Size(80, 128));
  final double f;
  final IsoShade shade;
  final Color ghost;

  @override
  void paintDesign(Canvas canvas) {
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(40, 122), width: 60, height: 10),
        _fill(const Color(0x47000000)));
    final max = IsoBox.prism(40, 96, 22, 84);
    _dashed(canvas, _poly(max.silhouette), _stroke(ghost, 1), dash: 3, gap: 3);
    paintIsoBox(canvas, IsoBox.prism(40, 96, 22, math.max(3, 84 * f)), shade);
  }

  @override
  bool shouldRepaint(covariant _SpeedColumnPainter old) =>
      old.f != f || old.shade != shade;
}

// ═══════════════════ 6) أعمدة زمن الاستجابة ═══════════════════

/// ثلاثة أعمدة مجسّمة: الأدنى/المتوسط/الأعلى لزمن الاستجابة مع خطّ حدّ «ممتاز».
class PingPrisms3D extends StatelessWidget {
  const PingPrisms3D({
    super.key,
    required this.minMs,
    required this.avgMs,
    required this.maxMs,
    required this.rate,
    this.excellentLimitMs = 20,
  });
  final double? minMs;
  final double? avgMs;
  final double? maxMs;
  final QualityRating Function(double?) rate;
  final double excellentLimitMs;

  @override
  Widget build(BuildContext context) {
    final vals = [minMs, avgMs, maxMs];
    final top = vals.whereType<double>().fold<double>(0, math.max);
    final scale = math.max(top * 1.25, excellentLimitMs * 2.2);
    return Semantics(
      label:
          'زمن الاستجابة: الأدنى ${minMs?.toStringAsFixed(0) ?? '—'}، المتوسط ${avgMs?.toStringAsFixed(0) ?? '—'}، الأعلى ${maxMs?.toStringAsFixed(0) ?? '—'} ميلي ثانية',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (ctx, k, _) => SizedBox(
            height: 170,
            width: double.infinity,
            child: CustomPaint(
              painter: _PingPainter(vals, scale, k, rate, excellentLimitMs),
            ),
          ),
        ),
      ),
    );
  }
}

class _PingPainter extends CustomPainter {
  _PingPainter(this.vals, this.scale, this.k, this.rate, this.limit);
  final List<double?> vals;
  final double scale;
  final double k;
  final QualityRating Function(double?) rate;
  final double limit;

  static const _captions = ['الأدنى', 'المتوسط', 'الأعلى'];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    const baseY = 118.0;
    const maxH = 88.0;
    const pw = 24.0;
    // أرضية.
    canvas.drawPath(
        _poly([
          const Offset(8, baseY + 18),
          Offset(w - 8, baseY + 18),
          Offset(w - 18, baseY + 30),
          const Offset(-2, baseY + 30),
        ]),
        _fill(Nq3d.groundAlt));
    // خطّ حدّ الممتاز.
    final ly = baseY + pw - (limit / scale) * maxH;
    _dashed(canvas, Path()..moveTo(8, ly)..lineTo(w - 8, ly),
        _stroke(const Color(0x992E7D32), 1, round: false),
        dash: 4, gap: 4);
    _label(canvas, 'حدّ الممتاز ${limit.toStringAsFixed(0)}ms',
        Offset(w - 52, ly - 9),
        size: 10, weight: FontWeight.w700, color: SdColors.success);

    for (var i = 0; i < 3; i++) {
      final x = w * (0.2 + i * 0.3);
      final v = vals[i];
      if (v == null) {
        _label(canvas, '—', Offset(x, baseY), size: 14, color: Nq3d.faint);
      } else {
        final hgt = math.max(3.0, (v / scale) * maxH * k);
        final box = IsoBox.prism(x, baseY, pw, hgt);
        paintIsoBox(canvas, box, ratingShade(rate(v)));
        _label(canvas, '${v.toStringAsFixed(0)} ms', Offset(x, box.top.dy - 10),
            size: 12, weight: FontWeight.w900, color: Nq3d.ink,
            dir: TextDirection.ltr);
      }
      _label(canvas, _captions[i], Offset(x, baseY + pw + 26),
          size: 11, weight: FontWeight.w700, color: Nq3d.muted);
    }
  }

  @override
  bool shouldRepaint(covariant _PingPainter old) =>
      old.k != k || old.scale != scale || old.vals != vals;
}

// ═══════════════════ 7) أعمدة إشارة WiFi ═══════════════════

int wifiActiveBars(QualityRating r) {
  switch (r) {
    case QualityRating.excellent:
      return 5;
    case QualityRating.good:
      return 4;
    case QualityRating.fair:
      return 3;
    case QualityRating.poor:
      return 2;
    case QualityRating.bad:
      return 1;
    case QualityRating.unknown:
      return 0;
  }
}

/// خمسة أعمدة مجسّمة متصاعدة ملوّنة بالتقييم.
class WifiPrisms3D extends StatelessWidget {
  const WifiPrisms3D({super.key, required this.rating, this.width = 120});
  final QualityRating rating;
  final double width;

  @override
  Widget build(BuildContext context) {
    final n = wifiActiveBars(rating);
    return Semantics(
      label: 'قوة إشارة WiFi: $n من 5',
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: width * 96 / 120,
          child: CustomPaint(painter: _WifiPainter(n, ratingShade(rating))),
        ),
      ),
    );
  }
}

class _WifiPainter extends _DesignPainter {
  _WifiPainter(this.active, this.shade) : super(const Size(120, 96));
  final int active;
  final IsoShade shade;

  @override
  void paintDesign(Canvas canvas) {
    const hs = [14.0, 26.0, 38.0, 50.0, 62.0];
    for (var i = 0; i < 5; i++) {
      paintIsoBox(canvas, IsoBox.prism(14 + i * 23.0, 76, 10, hs[i]),
          i < active ? shade : IsoShade.muted);
    }
  }

  @override
  bool shouldRepaint(covariant _WifiPainter old) =>
      old.active != active || old.shade != shade;
}

// ═══════════════════ 8) شريط الإشارة الضوئية البارز ═══════════════════

/// شريط Rx مجسّم مقسّم بعتبات QualityScorer.rateOpticalRx
/// (-8..-15 ممتاز، -15..-22 جيد، -22..-25 مقبول، -25..-27 ضعيف، أقل من -27 سيّئ).
class OpticalBand3D extends StatelessWidget {
  const OpticalBand3D({super.key, required this.rxDbm});
  final double rxDbm;

  static const double _from = -8;
  static const double _to = -30;
  static const _stops = [-8.0, -15.0, -22.0, -25.0, -27.0, -30.0];
  static const _colors = [
    SdColors.success,
    Color(0xFF9CCC65),
    Color(0xFFFBC02D),
    SdColors.warning,
    SdColors.danger,
  ];

  double _frac(double dbm) => ((_from - dbm) / (_from - _to)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'قدرة الاستقبال ${rxDbm.toStringAsFixed(1)} dBm على مقياس من -8 إلى -30',
      child: ExcludeSemantics(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: LayoutBuilder(builder: (ctx, c) {
            final w = c.maxWidth;
            final mx = _frac(rxDbm) * w;
            return SizedBox(
              height: 74,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 24,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: const [
                          BoxShadow(color: Color(0xFFB9BFD3), offset: Offset(0, 6)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Row(
                          children: [
                            for (var i = 0; i < 5; i++)
                              Expanded(
                                flex: ((_stops[i] - _stops[i + 1]) * 10).round(),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color.lerp(_colors[i], Colors.white, .22)!,
                                        _colors[i],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // دبّوس القراءة.
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: mx),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    builder: (_, x, child) =>
                        Positioned(left: x - 11, top: -2, child: child!),
                    child: Transform.rotate(
                      angle: -math.pi / 4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Nq3d.indigo,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                          boxShadow: [
                            BoxShadow(color: Nq3d.indigoDark, offset: Offset(-2, 3)),
                            BoxShadow(
                                color: Color(0x660F1660),
                                offset: Offset(0, 6),
                                blurRadius: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                  for (final s in _stops)
                    Positioned(
                      top: 50,
                      left: (_frac(s) * w - 14).clamp(0.0, w - 28),
                      width: 28,
                      child: Text(
                        s.toStringAsFixed(0),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Nq3d.muted),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ═══════════════════ 8b) تتبّع المسار ثلاثي الأبعاد ═══════════════════

/// قفزة واحدة في مسار الحزم (tracert/traceroute).
class TraceHop {
  const TraceHop({
    required this.index,
    this.ip = '',
    this.ms,
    this.timedOut = false,
  });
  final int index;
  final String ip;
  final double? ms; // أول زمن استجابة متاح للقفزة
  final bool timedOut;

  /// يحلّل خرج tracert (ويندوز) / traceroute (لينكس/أندرويد) إلى قفزات.
  static List<TraceHop> parse(List<String> raw) {
    final hops = <TraceHop>[];
    final ipReg = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})');
    final msReg = RegExp(r'([\d.]+)\s*ms', caseSensitive: false);
    final idxReg = RegExp(r'^\s*(\d+)\s');
    for (final line in raw) {
      final idxM = idxReg.firstMatch(line);
      if (idxM == null) continue; // سطر رأس/وصف — تجاهله
      final idx = int.tryParse(idxM.group(1)!) ?? (hops.length + 1);
      final ipM = ipReg.firstMatch(line);
      final msM = msReg.firstMatch(line);
      final hasStar = line.contains('*');
      if (ipM == null) {
        hops.add(TraceHop(index: idx, timedOut: true));
      } else {
        hops.add(TraceHop(
          index: idx,
          ip: ipM.group(1)!,
          ms: msM != null ? double.tryParse(msM.group(1)!) : null,
          timedOut: hasStar && msM == null,
        ));
      }
    }
    return hops;
  }
}

/// مشهد مجسّم (Isometric) لمسار الحزم: جهازك ← قفزات متتابعة على مسار منحنٍ
/// ← الكرة الأرضية/الخادم، مع كشف تدريجي متحرّك للقفزات وتدفّق على المسار.
class TraceRoute3D extends StatefulWidget {
  const TraceRoute3D({super.key, required this.hops, this.maxWidth = 360});
  final List<TraceHop> hops;
  final double maxWidth;

  @override
  State<TraceRoute3D> createState() => _TraceRoute3DState();
}

class _TraceRoute3DState extends State<TraceRoute3D>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  late AnimationController _reveal;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: Duration(
          milliseconds: 400 + 260 * widget.hops.length.clamp(1, 16)),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant TraceRoute3D old) {
    super.didUpdateWidget(old);
    if (old.hops.length != widget.hops.length) {
      _reveal
        ..duration = Duration(
            milliseconds: 400 + 260 * widget.hops.length.clamp(1, 16))
        ..forward(from: 0);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DesignCanvas(
      design: const Size(360, 232),
      maxWidth: widget.maxWidth,
      semanticLabel:
          'مسار الحزم ثلاثي الأبعاد من جهازك عبر ${widget.hops.length} قفزة إلى الوجهة',
      painter: _TracePainter(
        Listenable.merge([_loop, _reveal]),
        _loop,
        _reveal,
        widget.hops,
      ),
    );
  }
}

class _TracePainter extends _DesignPainter {
  _TracePainter(Listenable repaint, this.loop, this.reveal, this.hops)
      : super(const Size(360, 232), repaint: repaint);
  final Animation<double> loop;
  final Animation<double> reveal;
  final List<TraceHop> hops;

  static const _device = Offset(44, 176);
  static const _server = Offset(312, 60);
  static const _ctrl = Offset(150, 36);

  static Offset _qbez(Offset p0, Offset p1, Offset p2, double t) {
    final u = 1 - t;
    return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
  }

  Offset _nodeAt(int i, int n) =>
      _qbez(_device, _ctrl, _server, n <= 1 ? 0.5 : i / (n - 1));

  @override
  void paintDesign(Canvas canvas) {
    final v = loop.value;
    final rv = reveal.value;
    final n = hops.length;
    final visible = rv * n; // عدد القفزات المكشوفة (كسري)

    // أرضية/ظلّ.
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(180, 210), width: 320, height: 26),
        _fill(const Color(0x141A237E)));

    // المسار الكامل الباهت (خطّ إرشادي).
    final full = Path()
      ..moveTo(_device.dx, _device.dy)
      ..quadraticBezierTo(_ctrl.dx, _ctrl.dy, _server.dx, _server.dy);
    canvas.drawPath(full, _stroke(const Color(0x22000000), 2.2));

    // المسار المكشوف (حتى آخر قفظة ظاهرة) مع تدفّق متقطّع.
    if (n > 0 && visible > 0.02) {
      final endT = (visible / n).clamp(0.0, 1.0);
      final revealed = _partialBez(endT);
      canvas.drawPath(revealed, _stroke(_a(Nq3d.trace, 0.35), 7));
      _dashed(canvas, revealed, _stroke(Nq3d.trace, 2.4),
          dash: 3, gap: 7, phase: -v * 22);
      // حزمة متحرّكة على المسار المكشوف.
      final pm = revealed.computeMetrics().toList();
      if (pm.isNotEmpty) {
        final metric = pm.first;
        final pos = metric.getTangentForOffset(metric.length * (v % 1.0));
        if (pos != null) {
          canvas.drawCircle(pos.position, 4.2, _fill(Colors.white));
          canvas.drawCircle(pos.position, 4.2, _stroke(Nq3d.trace, 2));
        }
      }
    }

    // جهاز المستخدم (حاسبة مجسّمة).
    paintIsoBox(canvas, IsoBox(_device + const Offset(0, -16), 30, 24, 12),
        IsoShade.router);
    _label(canvas, 'جهازك', _device + const Offset(0, 16),
        size: 10.5, color: Nq3d.ink);

    // الكرة الأرضية / الخادم في النهاية.
    final serverRevealed = visible >= n - 0.01 && n > 0;
    final globeOp = serverRevealed ? 1.0 : 0.35;
    canvas.drawCircle(_server, 17, _fill(_a(const Color(0xFFEDE7F6), globeOp)));
    canvas.drawCircle(_server, 17, _stroke(_a(Nq3d.trace, globeOp), 2));
    final globe = Path()
      ..moveTo(_server.dx - 17, _server.dy)
      ..lineTo(_server.dx + 17, _server.dy)
      ..moveTo(_server.dx, _server.dy - 17)
      ..cubicTo(_server.dx - 9, _server.dy - 7, _server.dx - 9,
          _server.dy + 7, _server.dx, _server.dy + 17)
      ..moveTo(_server.dx, _server.dy - 17)
      ..cubicTo(_server.dx + 9, _server.dy - 7, _server.dx + 9,
          _server.dy + 7, _server.dx, _server.dy + 17);
    canvas.drawPath(globe, _stroke(_a(Nq3d.trace, globeOp), 1.6));
    _label(canvas, 'الوجهة', _server + const Offset(0, 30),
        size: 10.5, color: Nq3d.trace, opacity: globeOp);

    // عقد القفزات المكشوفة.
    for (var i = 0; i < n; i++) {
      final appear = (visible - i).clamp(0.0, 1.0);
      if (appear <= 0.01) continue;
      final c = _nodeAt(i, n);
      final hop = hops[i];
      final isLast = i == n - 1;
      // نبض على آخر قفزة مكشوفة أثناء الكشف.
      final pulsing = appear < 1.0;
      final r = (isLast ? 7.0 : 5.5) * (0.6 + 0.4 * appear);
      if (hop.timedOut) {
        canvas.drawCircle(c, r, _fill(_a(const Color(0xFFBDBDBD), appear)));
        canvas.drawCircle(
            c, r, _stroke(_a(const Color(0xFF9E9E9E), appear), 1.5));
      } else {
        if (pulsing) {
          canvas.drawCircle(
              c, r + 5 * (1 - appear) + 2, _fill(_a(Nq3d.trace, 0.2 * appear)));
        }
        canvas.drawCircle(c, r + 2.5, _fill(_a(Colors.white, appear)));
        canvas.drawCircle(c, r, _fill(_a(Nq3d.trace, appear)));
        canvas.drawCircle(c, r * 0.4, _fill(_a(Colors.white, appear)));
      }
      // رقم القفزة فوق العقدة.
      _label(canvas, '${hop.index}', c + const Offset(0, -13),
          size: 9.5,
          weight: FontWeight.w900,
          color: Nq3d.trace,
          opacity: appear,
          dir: TextDirection.ltr);
    }
  }

  /// جزء من منحنى بيزييه من البداية حتى الكسر [endT] (0..1).
  Path _partialBez(double endT) {
    final path = Path()..moveTo(_device.dx, _device.dy);
    const steps = 28;
    final last = (steps * endT).clamp(0, steps).toDouble();
    for (var i = 1; i <= last; i++) {
      final t = i / steps;
      final p = _qbez(_device, _ctrl, _server, t);
      path.lineTo(p.dx, p.dy);
    }
    // نقطة النهاية الدقيقة.
    final pe = _qbez(_device, _ctrl, _server, endT);
    path.lineTo(pe.dx, pe.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant _TracePainter old) => true;
}

// ═══════════════════ 9) أيقونة جهاز مجسّمة ═══════════════════

class IsoDeviceIcon extends StatelessWidget {
  const IsoDeviceIcon({super.key, required this.type, this.size = 48});
  final DeviceType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 44 / 48,
      child: CustomPaint(painter: _IsoDevicePainter(type)),
    );
  }
}

class _IsoDevicePainter extends _DesignPainter {
  _IsoDevicePainter(this.type) : super(const Size(52, 48));
  final DeviceType type;

  @override
  void paintDesign(Canvas canvas) {
    canvas.translate(26, 4);
    final IsoShade shade;
    switch (type) {
      case DeviceType.onu:
        shade = IsoShade.light;
        break;
      case DeviceType.router:
        shade = IsoShade.router;
        break;
      case DeviceType.accessPoint:
        shade = IsoShade.accessPoint;
        break;
      default:
        shade = IsoShade.muted;
    }
    const box = IsoBox(Offset(0, 0), 25.4, 23.1, 10);
    if (type == DeviceType.router || type == DeviceType.accessPoint) {
      canvas.drawLine(const Offset(-6, 4), const Offset(-6, -4),
          _stroke(shade.right, 2.4));
    }
    paintIsoBox(canvas, box, shade);
    if (type == DeviceType.onu) {
      canvas.drawCircle(const Offset(-12, 19), 2, _fill(Nq3d.fiber));
    } else if (type == DeviceType.router || type == DeviceType.accessPoint) {
      canvas.drawCircle(const Offset(-12, 19), 2, _fill(SdColors.accentTintEdge));
      canvas.drawCircle(const Offset(-6, 22.5), 2, _fill(const Color(0xFFA5D6A7)));
    }
  }

  @override
  bool shouldRepaint(covariant _IsoDevicePainter old) => old.type != type;
}

// ═══════════════════ 10) عناصر «مادّية» تفاعلية ═══════════════════

/// زر/بطاقة بارزة بحافّة سفلية صلبة: ترتفع وتميل عند المرور (سطح المكتب)
/// وتغوص عند الضغط.
class Raised3D extends StatefulWidget {
  const Raised3D({
    super.key,
    required this.child,
    this.onTap,
    this.color = Colors.white,
    this.gradient,
    this.edgeColor = Nq3d.edge,
    this.glowColor = Nq3d.glow,
    this.radius = 20,
    this.depth = 5,
    this.padding = const EdgeInsets.all(18),
    this.tilt = false,
    this.semanticLabel,
    this.toggled,
  });
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final Gradient? gradient;
  final Color edgeColor;
  final Color glowColor;
  final double radius;
  final double depth;
  final EdgeInsetsGeometry padding;
  final bool tilt;
  final String? semanticLabel;
  final bool? toggled;

  @override
  State<Raised3D> createState() => _Raised3DState();
}

class _Raised3DState extends State<Raised3D> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final d = _down ? 1.0 : widget.depth;
    final dy = _down ? widget.depth - 1 : (_hover ? -3.0 : 0.0);
    final m = Matrix4.translationValues(0, dy, 0);
    if (_hover && widget.tilt && !_down) {
      m.multiply(Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateX(0.10));
    }
    final r = BorderRadius.circular(widget.radius);
    return Semantics(
      button: widget.toggled == null,
      toggled: widget.toggled,
      label: widget.semanticLabel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: m,
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.gradient == null ? widget.color : null,
          gradient: widget.gradient,
          borderRadius: r,
          boxShadow: [
            BoxShadow(color: widget.edgeColor, offset: Offset(0, d)),
            BoxShadow(
              color: widget.glowColor,
              offset: Offset(0, d + 12),
              blurRadius: _down ? 10 : 28,
              spreadRadius: -14,
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: widget.onTap,
            onHighlightChanged: (v) => setState(() => _down = v),
            onHover: (v) => setState(() => _hover = v),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// مربّع أيقونة بارز (مكعّب صغير بحافّة سفلية).
class RaisedIconTile extends StatelessWidget {
  const RaisedIconTile({
    super.key,
    required this.icon,
    required this.color,
    required this.edgeColor,
    this.background,
    this.gradient,
    this.size = 36,
    this.iconSize,
    this.radius = 10,
    this.depth = 3,
  });
  final IconData icon;
  final Color color;
  final Color edgeColor;
  final Color? background;
  final Gradient? gradient;
  final double size;
  final double? iconSize;
  final double radius;
  final double depth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: gradient == null ? background : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: edgeColor, offset: Offset(0, depth))],
      ),
      child: Icon(icon, color: color, size: iconSize ?? size * .55),
    );
  }
}

/// مفتاح تشغيل مجسّم (عرض فقط؛ التبديل يتمّ من البطاقة الحاوية).
class Toggle3D extends StatelessWidget {
  const Toggle3D({super.key, required this.value});
  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 50,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: value
              ? const [Color(0xFF0B1150), Nq3d.indigo]
              : const [Color(0xFFCDD2E4), Nq3d.sideLeft],
        ),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        alignment: value
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? Colors.white : Nq3d.faint,
            boxShadow: [
              BoxShadow(
                  color: value ? const Color(0xFFC5CAE9) : Nq3d.muted,
                  offset: const Offset(0, 3)),
              const BoxShadow(
                  color: Color(0x40000000), offset: Offset(0, 4), blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// شارة تقييم بارزة (لون نص داكن على خلفية فاتحة لتباين واضح).
class RatingChip3D extends StatelessWidget {
  const RatingChip3D(this.rating, {super.key, this.fontSize = 11});
  final QualityRating rating;
  final double fontSize;

  static (Color fg, Color bg, Color edge) colorsFor(QualityRating r) {
    switch (r) {
      case QualityRating.excellent:
        return (SdColors.successEdge, SdColors.successTint, const Color(0xFFC8E6C9));
      case QualityRating.good:
        return (const Color(0xFF33691E), const Color(0xFFF1F8E9), const Color(0xFFDCEDC8));
      case QualityRating.fair:
        return (const Color(0xFF7A5D00), const Color(0xFFFFF8E1), const Color(0xFFFFECB3));
      case QualityRating.poor:
        return (const Color(0xFFBF360C), SdColors.warningTint, SdColors.warningTintEdge);
      case QualityRating.bad:
        return (const Color(0xFFB71C1C), const Color(0xFFFFEBEE), const Color(0xFFFFCDD2));
      case QualityRating.unknown:
        return (Nq3d.muted, Nq3d.groundAlt, Nq3d.edge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg, edge) = colorsFor(rating);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: edge, offset: const Offset(0, 2))],
      ),
      child: Text(rating.arabicLabel,
          style: TextStyle(
              fontSize: fontSize, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

// ═══════════════════ 11) مشاهد مراحل الفحص المتحرّكة ═══════════════════

/// حالة مرحلة في خطّ زمن الفحص.
enum StageStatus { pending, active, done }

/// أيقونة كل مرحلة فحص.
IconData stageIcon(QualityStage s) {
  switch (s) {
    case QualityStage.device:
      return Icons.computer_rounded;
    case QualityStage.devices:
      return Icons.lan_rounded;
    case QualityStage.wifi:
      return Icons.wifi_rounded;
    case QualityStage.optical:
      return Icons.cable_rounded;
    case QualityStage.ping:
      return Icons.network_ping_rounded;
    case QualityStage.dns:
      return Icons.dns_rounded;
    case QualityStage.download:
      return Icons.download_rounded;
    case QualityStage.upload:
      return Icons.upload_rounded;
    case QualityStage.traceroute:
      return Icons.route_rounded;
    case QualityStage.done:
      return Icons.check_rounded;
    case QualityStage.idle:
      return Icons.hourglass_empty_rounded;
  }
}

/// مشهد مجسّم متحرّك خاص بكل مرحلة؛ يتبدّل بقلبة ثلاثية الأبعاد عند تغيّر المرحلة.
class StageScene3D extends StatefulWidget {
  const StageScene3D({super.key, required this.stage, this.maxWidth = 380});
  final QualityStage stage;
  final double maxWidth;

  @override
  State<StageScene3D> createState() => _StageScene3DState();
}

class _StageScene3DState extends State<StageScene3D>
    with SingleTickerProviderStateMixin<StageScene3D>, _LoopTicker<StageScene3D> {
  @override
  Duration get loopDuration => const Duration(milliseconds: 2000);

  @override
  Widget build(BuildContext context) {
    final stage =
        widget.stage == QualityStage.idle ? QualityStage.device : widget.stage;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => AnimatedBuilder(
        animation: anim,
        child: child,
        builder: (_, c) {
          final a = anim.value;
          return Opacity(
            opacity: a.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0015)
                ..rotateY((1 - a) * math.pi / 2.2),
              child: c,
            ),
          );
        },
      ),
      child: _DesignCanvas(
        key: ValueKey(stage),
        design: const Size(360, 150),
        maxWidth: widget.maxWidth,
        semanticLabel: 'مرحلة الفحص الحالية: ${stage.arabicLabel}',
        painter: _StagePainter(loop, stage),
      ),
    );
  }
}

class _StagePainter extends _DesignPainter {
  _StagePainter(this.t, this.stage) : super(const Size(360, 150), repaint: t);
  final Animation<double> t;
  final QualityStage stage;

  static const double _k = 0.8660254;
  static const double _tau = 2 * math.pi;

  /// نقطة على سطح المنصّة بإحداثيات (u,v) ∈ [0..110].
  Offset _p(double u, double v) => Offset(180 + (u - v) * _k, 30 + (u + v) * .5);

  /// صندوق قاعدته الخلفية على النقطة (u,v) من المنصّة.
  IsoBox _on(double u, double v, double a, double b, double h) =>
      IsoBox(_p(u, v).translate(0, -h), a, b, h);

  Offset _topCenter(IsoBox b) =>
      Offset((b.top.dx + b.front.dx) / 2, (b.top.dy + b.front.dy) / 2);

  void _cube(Canvas c, Offset top, double s, IsoShade shade, {double op = 1}) =>
      paintIsoBox(c, IsoBox(top, s, s, s * .75), shade, opacity: op);

  void _glowDot(Canvas c, Offset p, Color color, {double r = 3.2, double op = 1}) {
    c.drawCircle(p, r * 2, _fill(_a(color, .30 * op)));
    c.drawCircle(p, r, _fill(_a(Colors.white, op)));
  }

  @override
  void paintDesign(Canvas canvas) {
    final v = t.value;
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(180, 146), width: 250, height: 14),
        _fill(const Color(0x141A237E)));
    paintIsoBox(canvas, const IsoBox(Offset(180, 30), 110, 110, 8),
        IsoShade.platform);
    canvas.drawPath(_poly([_p(10, 10), _p(100, 10), _p(100, 100), _p(10, 100)]),
        _stroke(Nq3d.gridLine, 1));

    switch (stage) {
      case QualityStage.idle:
      case QualityStage.device:
        _device(canvas, v);
        break;
      case QualityStage.devices:
        _devices(canvas, v);
        break;
      case QualityStage.wifi:
        _wifi(canvas, v);
        break;
      case QualityStage.optical:
        _optical(canvas, v);
        break;
      case QualityStage.ping:
        _ping(canvas, v);
        break;
      case QualityStage.dns:
        _dns(canvas, v);
        break;
      case QualityStage.download:
        _transfer(canvas, v, down: true);
        break;
      case QualityStage.upload:
        _transfer(canvas, v, down: false);
        break;
      case QualityStage.traceroute:
        _trace(canvas, v);
        break;
      case QualityStage.done:
        _done(canvas, v);
        break;
    }
  }

  // جهاز الفحص: حاسبة بشاشة يمسحها خطّ ضوئي + شريحة معالج نابضة.
  void _device(Canvas c, double v) {
    paintIsoBox(c, _on(28, 40, 54, 38, 4), IsoShade.light);
    final b0 = _p(28, 40).translate(0, -4);
    final b1 = _p(82, 40).translate(0, -4);
    c.drawPath(_poly([b0, b1, b1.translate(0, -38), b0.translate(0, -38)]),
        _fill(Nq3d.indigoDark));
    final i0 = Offset.lerp(b0, b1, .07)!;
    final i1 = Offset.lerp(b0, b1, .93)!;
    c.drawPath(
        _poly([
          i0.translate(0, -4),
          i1.translate(0, -4),
          i1.translate(0, -34),
          i0.translate(0, -34)
        ]),
        _fill(Nq3d.indigoLight));
    // أسطر مواصفات على الشاشة.
    for (var r = 0; r < 4; r++) {
      final ry = -10.0 - r * 6;
      final len = [.75, .55, .65, .4][r];
      c.drawLine(Offset.lerp(i0, i1, .12)!.translate(0, ry),
          Offset.lerp(i0, i1, .12 + .76 * len)!.translate(0, ry),
          _stroke(const Color(0x66FFFFFF), 2));
    }
    final s = (math.sin(v * _tau) + 1) / 2;
    final y = -(5 + 28 * s);
    final l0 = Offset.lerp(i0, i1, .02)!.translate(0, y);
    final l1 = Offset.lerp(i0, i1, .98)!.translate(0, y);
    c.drawLine(l0, l1, _stroke(_a(Nq3d.fiber, .3), 6));
    c.drawLine(l0, l1, _stroke(SdColors.accentTintEdge, 2));
    // شريحة المعالج.
    final chip = _on(86, 70, 20, 20, 5);
    paintIsoBox(c, chip, IsoShade.router);
    final pulse = .25 + .45 * (math.sin(v * _tau * 2) + 1) / 2;
    c.drawPath(_poly(chip.topFace), _fill(_a(Nq3d.fiber, pulse)));
    _label(c, 'CPU', _topCenter(chip),
        size: 8, color: Colors.white, dir: TextDirection.ltr);
  }

  // اكتشاف الأجهزة: راوتر يبثّ موجة رادار وتظهر الأجهزة تباعاً.
  void _devices(Canvas c, double v) {
    final center = _p(55, 55);
    final r = 8 + 62 * v;
    c.drawOval(Rect.fromCenter(center: center, width: r * 2, height: r * 1.15),
        _stroke(_a(Nq3d.teal, 1 - v), 2));
    c.drawOval(
        Rect.fromCenter(center: center, width: r * 1.2, height: r * .69),
        _stroke(_a(Nq3d.fiber, (1 - v) * .5), 1.4));
    const spots = [(48.0, 10.0), (10.0, 48.0), (86.0, 48.0), (48.0, 86.0)];
    final ops = <double>[];
    for (var i = 0; i < 4; i++) {
      ops.add(((v - (.12 + i * .17)) * 6).clamp(0.0, 1.0));
    }
    final router = _on(45, 45, 20, 20, 12);
    final rc = _topCenter(router);
    for (var i = 0; i < 4; i++) {
      if (ops[i] <= 0) continue;
      final (u, w) = spots[i];
      _dashed(c, Path()..moveTo(rc.dx, rc.dy + 8)..lineTo(_p(u + 7, w + 7).dx, _p(u + 7, w + 7).dy),
          _stroke(_a(Nq3d.indigoSoft, ops[i]), 1.4),
          dash: 3, gap: 4, phase: -v * 20);
    }
    void client(int i) {
      if (ops[i] <= 0) return;
      final (u, w) = spots[i];
      final h = 10 * Curves.easeOutBack.transform(ops[i]);
      final box = _on(u, w, 14, 14, math.max(1.0, h));
      paintIsoBox(c, box, IsoShade.light, opacity: ops[i]);
      c.drawCircle(_topCenter(box), 2.6,
          _fill(_a(i.isEven ? Nq3d.indigoSoft : Nq3d.teal, ops[i])));
    }

    client(0);
    client(1);
    c.drawLine(router.top.translate(2, 6), router.top.translate(2, -10),
        _stroke(Nq3d.indigoDark, 3));
    paintIsoBox(c, router, IsoShade.router);
    client(2);
    client(3);
  }

  // WiFi: موجات بثّ متتالية + أعمدة إشارة ترتفع.
  void _wifi(Canvas c, double v) {
    for (var i = 0; i < 4; i++) {
      final g = ((v * 1.6 - i * .18)).clamp(0.0, 1.0);
      final h = (6 + i * 7) * Curves.easeOutBack.transform(g);
      paintIsoBox(c, _on(70 + i * 9, 14, 7, 7, math.max(1.0, h)), IsoShade.teal);
    }
    final router = _on(36, 50, 28, 24, 12);
    final a1 = Offset.lerp(router.left, router.top, .55)!;
    final a2 = Offset.lerp(router.top, router.right, .45)!;
    c.drawLine(a1, a1.translate(0, -22), _stroke(Nq3d.indigoDark, 3));
    c.drawLine(a2, a2.translate(0, -22), _stroke(Nq3d.indigoDark, 3));
    paintIsoBox(c, router, IsoShade.router);
    final ac = Offset((a1.dx + a2.dx) / 2, a1.dy - 22);
    for (var i = 0; i < 3; i++) {
      final f = (v + i / 3) % 1;
      final r = 8 + 26 * f;
      c.drawArc(Rect.fromCircle(center: ac, radius: r), -math.pi * .82,
          math.pi * .64, false, _stroke(_a(Nq3d.teal, 1 - f), 2.6));
    }
    c.drawCircle(ac, 3, _fill(Nq3d.teal));
  }

  // الإشارة الضوئية: نبضات ضوء تسري في كابل الفايبر نحو الـONU.
  void _optical(Canvas c, double v) {
    final onu = _on(54, 40, 32, 26, 13);
    final entry = Offset.lerp(onu.left, onu.front, .18)!.translate(0, 8);
    final cable = Path()
      ..moveTo(_p(0, 58).dx, _p(0, 58).dy)
      ..quadraticBezierTo(_p(22, 70).dx, _p(22, 70).dy, entry.dx, entry.dy);
    c.drawPath(cable, _stroke(_a(Nq3d.fiber, .22), 9));
    c.drawPath(cable, _stroke(Nq3d.teal, 2.6));
    final m = cable.computeMetrics().first;
    for (var i = 0; i < 3; i++) {
      final f = (v + i / 3) % 1;
      final pos = m.getTangentForOffset(m.length * f)!.position;
      _glowDot(c, pos, Nq3d.fiber, op: math.sin(f * math.pi));
    }
    paintIsoBox(c, onu, IsoShade.light);
    final led = Offset.lerp(onu.left, onu.front, .35)!.translate(0, 6);
    final blink = .4 + .6 * (math.sin(v * _tau * 3) + 1) / 2;
    c.drawCircle(led, 5, _fill(_a(Nq3d.fiber, .25 * blink)));
    c.drawCircle(led, 2.6, _fill(_a(Nq3d.fiber, blink)));
    c.drawCircle(Offset.lerp(onu.left, onu.front, .55)!.translate(0, 7), 2.4,
        _fill(SdColors.success));
    final bob = math.sin(v * _tau) * 3;
    final tag = onu.top.translate(6, -18 + bob);
    final rr = RRect.fromRectAndRadius(
        Rect.fromCenter(center: tag, width: 50, height: 18),
        const Radius.circular(9));
    c.drawRRect(rr.shift(const Offset(0, 3)), _fill(Nq3d.tealDark));
    c.drawRRect(rr, _fill(Nq3d.teal));
    _label(c, 'Rx / Tx', tag,
        size: 9.5, color: Colors.white, dir: TextDirection.ltr);
  }

  // زمن الاستجابة: حزمة تذهب للخادم وتعود (ذهاب/إياب).
  void _ping(Canvas c, double v) {
    final server = _on(78, 16, 18, 18, 36);
    paintIsoBox(c, server, IsoShade.router);
    for (var r = 0; r < 3; r++) {
      final on = ((v * 6).floor() % 3) == r;
      c.drawCircle(
          Offset.lerp(server.left, server.front, .4)!.translate(0, 10 + r * 9),
          2.2,
          _fill(on ? SdColors.accentTintEdge : const Color(0x4D80DEEA)));
    }
    final client = _on(12, 66, 22, 22, 12);
    paintIsoBox(c, client, IsoShade.light);
    final a = _topCenter(client).translate(0, -6);
    final b = _topCenter(server).translate(0, -6);
    final p = v < .5 ? v * 2 : (1 - v) * 2;
    final e = Curves.easeInOut.transform(p);
    // أثر المسار.
    final arc = Path()..moveTo(a.dx, a.dy);
    for (var i = 1; i <= 20; i++) {
      final q = i / 20;
      final pt = Offset.lerp(a, b, q)!.translate(0, -34 * math.sin(math.pi * q));
      arc.lineTo(pt.dx, pt.dy);
    }
    _dashed(c, arc, _stroke(const Color(0x665C6BC0), 1.4), dash: 2, gap: 5);
    final pos = Offset.lerp(a, b, e)!.translate(0, -34 * math.sin(math.pi * e));
    _cube(c, pos.translate(0, -4), 9, v < .5 ? IsoShade.teal : ratingShade(QualityRating.excellent));
    // تموّج عند الوصول.
    final hit = v < .5 ? b : a;
    final near = (1 - (p - (v < .5 ? 1 : 0)).abs()).clamp(0.0, 1.0);
    if (p > .85) {
      c.drawOval(Rect.fromCenter(center: hit.translate(0, 6), width: 40 * near, height: 18 * near),
          _stroke(_a(Nq3d.teal, 1 - (p - .85) / .15), 1.6));
    }
    _label(c, v < .5 ? 'ذهاب' : 'إياب', _p(40, 30).translate(0, -22),
        size: 10, color: Nq3d.muted);
  }

  // DNS: خادم أسماء من ثلاث طبقات + سؤال يصعد وجواب يعود.
  void _dns(Canvas c, double v) {
    final active = (v * 3).floor() % 3;
    IsoBox? topSlab;
    for (var k = 0; k < 3; k++) {
      final slab = IsoBox(_p(70, 22).translate(0, -10 - k * 12.0), 24, 24, 10);
      paintIsoBox(c, slab, IsoShade.router);
      c.drawCircle(Offset.lerp(slab.left, slab.front, .3)!.translate(0, 5), 2.2,
          _fill(k == active ? const Color(0xFFA5D6A7) : const Color(0x4DA5D6A7)));
      topSlab = slab;
    }
    final top = topSlab!;
    _label(c, 'DNS', _topCenter(top).translate(0, -16 + math.sin(v * _tau) * 2),
        size: 11, weight: FontWeight.w900, color: Nq3d.indigo,
        dir: TextDirection.ltr);
    final client = _on(14, 64, 22, 22, 12);
    paintIsoBox(c, client, IsoShade.light);
    final a = _topCenter(client).translate(0, -4);
    final b = _topCenter(top).translate(0, 4);
    final goUp = v < .5;
    final f = Curves.easeInOut.transform(goUp ? v * 2 : (v - .5) * 2);
    final pos = goUp ? Offset.lerp(a, b, f)! : Offset.lerp(b, a, f)!;
    final lift = -22 * math.sin(math.pi * f);
    c.drawLine(a, b, _stroke(const Color(0x335C6BC0), 1.4));
    _glowDot(c, pos.translate(0, lift),
        goUp ? Nq3d.indigoSoft : SdColors.success, r: 4);
    _label(c, goUp ? 'سؤال' : 'جواب', pos.translate(0, lift - 14),
        size: 9.5, color: goUp ? Nq3d.indigo : SdColors.success);
  }

  // التنزيل/الرفع: مكعّبات بيانات تتدفّق بين السحابة والراوتر.
  void _transfer(Canvas c, double v, {required bool down}) {
    final shade = down ? IsoShade.teal : IsoShade.amber;
    final router = _on(44, 46, 24, 24, 12);
    final meter = _on(84, 30, 10, 10, 4 + 30 * Curves.easeOut.transform(v));
    paintIsoBox(c, _on(84, 30, 10, 10, 34), IsoShade.muted, opacity: .35);
    paintIsoBox(c, meter, shade);
    paintIsoBox(c, router, IsoShade.router);
    // السحابة.
    const cc = Offset(150, 14);
    final cloud = Paint()..color = Colors.white;
    final edge = _stroke(Nq3d.outline, 1.2);
    for (final (o, r) in const [
      (Offset(-14, 4), 9.0),
      (Offset(0, -2), 12.0),
      (Offset(14, 4), 9.0),
    ]) {
      c.drawCircle(cc + o, r, edge);
    }
    for (final (o, r) in const [
      (Offset(-14, 4), 9.0),
      (Offset(0, -2), 12.0),
      (Offset(14, 4), 9.0),
    ]) {
      c.drawCircle(cc + o, r - .6, cloud);
    }
    c.drawRect(Rect.fromCenter(center: cc.translate(0, 7), width: 28, height: 8), cloud);
    final top = _topCenter(router).translate(0, -4);
    final from = down ? cc.translate(0, 10) : top;
    final to = down ? top : cc.translate(0, 10);
    for (var i = 0; i < 4; i++) {
      final f = (v + i / 4) % 1;
      final pos = Offset.lerp(from, to, Curves.easeIn.transform(f))!;
      _cube(c, pos.translate(-4, -4), 8, shade, op: math.sin(f * math.pi));
    }
    _label(c, down ? '↓' : '↑', cc, size: 13, weight: FontWeight.w900,
        color: down ? Nq3d.teal : SdColors.warning,
        dir: TextDirection.ltr);
  }

  // تتبّع المسار: ضوء يقفز بين القفزات حتى الخادم.
  void _trace(Canvas c, double v) {
    const hops = [(6.0, 92.0), (28.0, 64.0), (50.0, 80.0), (72.0, 44.0), (94.0, 18.0)];
    final pts = [for (final (u, w) in hops) _p(u + 4, w + 4)];
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    _dashed(c, path, _stroke(_a(Nq3d.trace, .5), 1.8), dash: 3, gap: 5, phase: -v * 20);
    final reached = v * (pts.length - 1);
    final order = [for (var i = 0; i < hops.length; i++) i]
      ..sort((x, y) => (hops[x].$1 + hops[x].$2).compareTo(hops[y].$1 + hops[y].$2));
    for (final i in order) {
      final (u, w) = hops[i];
      final lit = reached >= i - .05;
      paintIsoBox(c, _on(u, w, 9, 9, lit ? 10 : 6),
          lit ? const IsoShade(Color(0xFFB39DDB), Nq3d.trace, Color(0xFF5E35B1)) : IsoShade.muted);
    }
    final m = path.computeMetrics().first;
    final pos = m.getTangentForOffset(m.length * v)!.position;
    _glowDot(c, pos.translate(0, -8), Nq3d.trace, r: 3.6);
  }

  // اكتمل: مكعّب أخضر بعلامة صحّ وشرارات.
  void _done(Canvas c, double v) {
    final box = _on(36, 36, 38, 38, 16 + 2 * math.sin(v * _tau));
    paintIsoBox(c, box, ratingShade(QualityRating.excellent));
    final ctr = _topCenter(box);
    final check = Path()
      ..moveTo(ctr.dx - 10, ctr.dy)
      ..lineTo(ctr.dx - 2, ctr.dy + 6)
      ..lineTo(ctr.dx + 12, ctr.dy - 6);
    c.drawPath(check, _stroke(Colors.white, 4));
    for (var i = 0; i < 6; i++) {
      final ang = i / 6 * _tau + v * _tau * .3;
      final d = 46 + 6 * math.sin(v * _tau + i);
      final p = ctr + Offset(math.cos(ang) * d, math.sin(ang) * d * .5 - 10);
      c.drawCircle(p, 2.2, _fill(_a(const Color(0xFF66BB6A), .5 + .5 * math.sin(v * _tau + i))));
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => old.stage != stage;
}

// ═══════════════════ 12) شارة مرحلة مجسّمة + صفّ خطّ الزمن ═══════════════════

/// مكعّب أيقونة للمرحلة: رمادي بالانتظار، نيلي نابض يدور حوله مؤشّر أثناء
/// التنفيذ، وينقلب بحركة ثلاثية الأبعاد إلى علامة صحّ خضراء عند الانتهاء.
class StageBadge3D extends StatefulWidget {
  const StageBadge3D({
    super.key,
    required this.stage,
    required this.status,
    this.size = 32,
  });
  final QualityStage stage;
  final StageStatus status;
  final double size;

  @override
  State<StageBadge3D> createState() => _StageBadge3DState();
}

class _StageBadge3DState extends State<StageBadge3D>
    with TickerProviderStateMixin<StageBadge3D> {
  AnimationController? _spin;

  void _sync() {
    if (widget.status == StageStatus.active) {
      _spin ??= AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat();
    } else {
      _spin?.dispose();
      _spin = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StageBadge3D old) {
    super.didUpdateWidget(old);
    if (old.status != widget.status) _sync();
  }

  @override
  void dispose() {
    _spin?.dispose();
    super.dispose();
  }

  Widget _tile(Key key, IconData icon, Color bg, Color edge, Color fg, double depth) {
    final s = widget.size;
    return Container(
      key: key,
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(s * .3),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(bg, Colors.white, .18)!, bg],
        ),
        boxShadow: [BoxShadow(color: edge, offset: Offset(0, depth))],
      ),
      child: Icon(icon, size: s * .55, color: fg),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.status;
    final Widget tile;
    switch (st) {
      case StageStatus.done:
        tile = _tile(const ValueKey('done'), Icons.check_rounded,
            SdColors.success, SdColors.successEdge, Colors.white, 3);
        break;
      case StageStatus.active:
        tile = _tile(const ValueKey('active'), stageIcon(widget.stage),
            Nq3d.indigo, Nq3d.indigoDark, Colors.white, 4);
        break;
      case StageStatus.pending:
        tile = _tile(const ValueKey('pending'), stageIcon(widget.stage),
            Nq3d.sideLeft, Nq3d.sideRight, Nq3d.faint, 2);
        break;
    }
    final flipping = AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      transitionBuilder: (child, anim) => AnimatedBuilder(
        animation: anim,
        child: child,
        builder: (_, c) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.003)
            ..rotateY((1 - anim.value) * math.pi / 2),
          child: c,
        ),
      ),
      child: tile,
    );
    final spin = _spin;
    final box = widget.size + 14;
    return SizedBox(
      width: box,
      height: box,
      child: spin == null
          ? Center(child: flipping)
          : AnimatedBuilder(
              animation: spin,
              builder: (_, child) {
                final a = spin.value * 2 * math.pi;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(box),
                      painter: _SpinRingPainter(spin.value),
                    ),
                    Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.translationValues(0, -2 * math.sin(a), 0)
                        ..multiply(Matrix4.identity()
                          ..setEntry(3, 2, 0.003)
                          ..rotateY(.35 * math.sin(a))),
                      child: child,
                    ),
                  ],
                );
              },
              child: flipping,
            ),
    );
  }
}

class _SpinRingPainter extends CustomPainter {
  _SpinRingPainter(this.v);
  final double v;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);
    canvas.drawOval(r, _stroke(const Color(0x1F1A237E), 2.5));
    canvas.drawArc(r, v * 2 * math.pi - math.pi / 2, math.pi * .7, false,
        _stroke(Nq3d.fiber, 2.5));
  }

  @override
  bool shouldRepaint(covariant _SpinRingPainter old) => old.v != v;
}

/// صفّ في خطّ زمن الفحص: يدخل بانزلاق متتابع، ويُبرَز صفّ المرحلة الجارية،
/// ويمتلئ موصل الخطّ بالأخضر عند الانتهاء.
class StageTimelineRow3D extends StatelessWidget {
  const StageTimelineRow3D({
    super.key,
    required this.stage,
    required this.status,
    required this.index,
    required this.isLast,
  });
  final QualityStage stage;
  final StageStatus status;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final active = status == StageStatus.active;
    final done = status == StageStatus.done;
    final statusText = done
        ? 'تم'
        : active
            ? 'جارٍ…'
            : 'بالانتظار';
    return Semantics(
      label: '${stage.arabicLabel} — $statusText',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 380 + index * 90),
          curve: Curves.easeOutCubic,
          builder: (_, a, child) => Opacity(
            opacity: a,
            child: Transform.translate(
                offset: Offset(0, (1 - a) * 14), child: child),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFEEF0FA) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    StageBadge3D(stage: stage, status: status),
                    if (!isLast)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 3,
                        height: 8,
                        decoration: BoxDecoration(
                          color: done ? SdColors.success : Nq3d.sideLeft,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 13),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: active ? 14 : 13,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                        color: done || active ? Nq3d.ink : Nq3d.faint,
                      ),
                      child: Text(stage.arabicLabel),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Text(
                    done
                        ? 'تم'
                        : active
                            ? 'جارٍ…'
                            : '',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: done ? SdColors.success : Nq3d.indigo),
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

/// شريط مراحل أفقي (Horizontal stepper) بشارات 3D موصولة بروابط — RTL.
/// يحجّم الشارات تلقائياً لتملأ العرض؛ وإن تعذّر (شاشة ضيّقة جداً) يسمح بتمرير
/// أفقي للشريط فقط. [currentIndex] فهرس المرحلة الجارية (−1 إن لا شيء)،
/// و[allDone] يجعل الكلّ «تم».
class StageStrip3D extends StatelessWidget {
  const StageStrip3D({
    super.key,
    required this.stages,
    required this.currentIndex,
    required this.allDone,
    this.minBadge = 18,
    this.maxBadge = 34,
  });
  final List<QualityStage> stages;
  final int currentIndex;
  final bool allDone;
  final double minBadge;
  final double maxBadge;

  StageStatus _statusOf(int i) {
    if (allDone || (currentIndex >= 0 && i < currentIndex)) {
      return StageStatus.done;
    }
    if (!allDone && i == currentIndex) return StageStatus.active;
    return StageStatus.pending;
  }

  @override
  Widget build(BuildContext context) {
    final n = stages.length;
    if (n == 0) return const SizedBox.shrink();
    return LayoutBuilder(builder: (ctx, c) {
      const conn = 8.0;
      final w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
      // احسب حجم الشارة بحيث تملأ الصفوف العرض المتاح (box = badge + 14).
      final boxEach = (w - (n - 1) * conn) / n;
      final badge = (boxEach - 14).clamp(minBadge, maxBadge).toDouble();
      final box = badge + 14;
      final needed = n * box + (n - 1) * conn;
      final fits = needed <= w + 0.5;

      final row = Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < n; i++) ...[
              StageBadge3D(
                  stage: stages[i], status: _statusOf(i), size: badge),
              if (i < n - 1)
                Container(
                  width: conn,
                  height: 3,
                  decoration: BoxDecoration(
                    color: (allDone || i < currentIndex)
                        ? SdColors.success
                        : Nq3d.sideLeft,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ],
        ),
      );

      final strip = SizedBox(
        height: box,
        child: fits
            ? Center(child: row)
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true, // يبدأ من اليمين (RTL)
                child: row,
              ),
      );
      return Semantics(
        label: 'مراحل الفحص: ${currentIndex + 1} من $n',
        child: ExcludeSemantics(child: strip),
      );
    });
  }
}
