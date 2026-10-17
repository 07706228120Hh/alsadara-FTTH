/// مشهد تسجيل الدخول ثلاثي الأبعاد التفاعلي — نظام تصميم الصدارة.
///
/// مدينة مصغّرة حقيقية ثلاثية الأبعاد (منظور + إضاءة + ترتيب عمق) مرسومة
/// بمحرّك برمجي خفيف داخل [CustomPainter] دون أي حزمة خارجية:
///  • برج ألياف ضوئية (OLT) في المركز وفوقه شعار التطبيق يطفو مع حلقة مدارية.
///  • سبعة مبانٍ مختلفة (برج سكني، فيلا بحديقة ومسبح، مجمّع أعمال زجاجي،
///    سوق تجاري، مدرسة، منزل، عمارات) بنوافذ مضيئة وأشجار وطرق.
///  • خطوط ألياف تتدفّق فيها نبضات ضوئية من البرج إلى كل مبنى.
///
/// التفاعل:
///  • حركة الفأرة → ميلان خفيف للمشهد (Parallax).
///  • السحب (فأرة/لمس) → تدوير المشهد، العجلة/القرص بإصبعين → تكبير وتصغير.
///  • المرور فوق مبنى → يتوهّج ويظهر اسمه. الضغط عليه → الكاميرا تدخل إليه،
///    يرتفع سقفه، تصبح جدرانه زجاجية، وتظهر طوابقه ونقاط المشتركين
///    (أخضر متصل / أحمر مفصول) مع بطاقة تفاصيل. Esc أو ✕ للعودة.
///  • بعد 5 ثوانٍ دون تفاعل يدور المشهد ببطء تلقائياً.
///
/// الواجهة العامة لم تتغيّر: `SdLoginScene(maxWidth: …)`.
/// البيانات في بطاقة التفاصيل توضيحية حالياً (انظر [SdSceneBuilding]).
///
/// الأداء: الهندسة تُبنى مرّة واحدة، متحكّم واحد، [RepaintBoundary]،
/// وتتوقّف الحركة التلقائية عند `MediaQuery.disableAnimations`.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart'
    show rootBundle, KeyDownEvent, KeyEvent, LogicalKeyboardKey;

// ═══════════════════════════════════════════════════════════════════
// الواجهة العامة
// ═══════════════════════════════════════════════════════════════════

class SdLoginScene extends StatefulWidget {
  const SdLoginScene({
    super.key,
    this.maxWidth = 540,
    this.aspect = 0.92,
    this.interactive = true,
    this.logoAsset = 'assets/logo.png',
  });

  /// أقصى عرض للمشهد.
  final double maxWidth;

  /// الارتفاع = العرض × [aspect].
  final double aspect;

  /// إيقافه يجعل المشهد زخرفياً فقط (دوران تلقائي بلا لمس).
  final bool interactive;

  final String logoAsset;

  @override
  State<SdLoginScene> createState() => _SdLoginSceneState();
}

/// بيانات مبنى في المشهد (توضيحية — تُربط لاحقاً بالبيانات الفعلية).
class SdSceneBuilding {
  SdSceneBuilding({
    required this.id,
    required this.name,
    required this.type,
    required this.x,
    required this.z,
    required this.height,
    required this.floors,
    required this.subscribers,
    required this.online,
    required this.rx,
    required this.fat,
    required this.accent,
  });

  final String id, name, type, rx, fat;
  final double x, z, height;
  final int floors, subscribers, online;
  final Color accent;

  // حالة الحركة (0..1)
  double hover = 0, focus = 0;
  final List<_Part> _parts = [];
  final List<_Dot> _dots = [];
  _V _led = const _V(0, 0, 0);
}

class _SdLoginSceneState extends State<SdLoginScene>
    with SingleTickerProviderStateMixin {
  late final _Scene _scene = _Scene.build();
  late final _Camera _cam = _Camera();
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final FocusNode _focusNode = FocusNode(debugLabel: 'SdLoginScene');

  ui.Image? _logo;
  Duration _last = Duration.zero;
  double _time = 0;
  double _idleSince = -100;
  bool _reduceMotion = false;

  SdSceneBuilding? _hovered;
  SdSceneBuilding? _focused;

  // السحب
  Offset? _dragStart;
  double _dragYaw = 0, _dragPitch = 0, _dragDist = 0;
  bool _dragMoved = false;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _loadLogo();
  }

  Future<void> _loadLogo() async {
    try {
      final data = await rootBundle.load(widget.logoAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _logo = frame.image);
    } catch (_) {
      // البديل النصّي «ص» يُرسم تلقائياً.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    if (!_reduceMotion) _time += dt;
    final k = (dt * 60).clamp(0.0, 3.0); // تطبيع التنعيم لمعدّل الإطارات

    if (_focused == null && !_reduceMotion && _time - _idleSince > 5) {
      _cam.goal.yaw += 0.0016 * k;
    }
    _cam.step(0.08 * k, 0.06 * k);
    for (final b in _scene.buildings) {
      b.hover += ((identical(b, _hovered) ? 1 : 0) - b.hover) * (0.15 * k).clamp(0.0, 1.0);
      b.focus += ((identical(b, _focused) ? 1 : 0) - b.focus) * (0.09 * k).clamp(0.0, 1.0);
    }
    _frame.value++;
  }

  // ─── التفاعل ───────────────────────────────────────────────────

  void _touch() => _idleSince = _time;

  void _setFocus(SdSceneBuilding? b) {
    setState(() => _focused = b);
    final g = _cam.goal;
    if (b != null) {
      g.tx = b.x;
      g.tz = b.z;
      g.ty = b.height * 0.5;
      g.dist = 12.5 + b.height * 0.9;
      g.pitch = 0.48;
      g.yaw = math.atan2(b.x, b.z) + 0.35;
    } else {
      g.tx = 0;
      g.tz = 0;
      g.ty = 1.2;
      g.dist = _Camera.homeDist;
      g.pitch = 0.58;
    }
    _touch();
  }

  SdSceneBuilding? _pick(Offset p) {
    if (_size.isEmpty) return null;
    final proj = _Projector(_cam, _size);
    SdSceneBuilding? best;
    var bestZ = double.infinity;
    for (final b in _scene.buildings) {
      for (final part in b._parts) {
        if (part.tag == _Tag.interior && b.focus < 0.5) continue;
        final dy = part.tag == _Tag.roof ? b.focus * 1.6 : 0.0;
        for (final f in part.faces) {
          if (f.n.dot(proj.eye - f.c) <= 0) continue;
          final pts = [for (final v in f.pts) proj.project(v.addY(dy))];
          if (_inPoly(p, pts)) {
            final z = proj.project(f.c).z;
            if (z < bestZ) {
              bestZ = z;
              best = b;
            }
          }
        }
      }
    }
    return best;
  }

  void _onHover(PointerHoverEvent e) {
    if (_size.isEmpty) return;
    _cam.par.gx = (e.localPosition.dx / _size.width - 0.5) * 2;
    _cam.par.gy = (e.localPosition.dy / _size.height - 0.5) * 2;
    final h = _pick(e.localPosition);
    if (!identical(h, _hovered)) setState(() => _hovered = h);
  }

  void _onExit(PointerExitEvent e) {
    _cam.par.gx = 0;
    _cam.par.gy = 0;
    if (_hovered != null) setState(() => _hovered = null);
  }

  void _onScroll(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final g = _cam.goal;
      g.dist = (g.dist * (1 + e.scrollDelta.dy.sign * 0.08)).clamp(8.0, 34.0);
      _touch();
    }
  }

  void _onScaleStart(ScaleStartDetails d) {
    _dragStart = d.localFocalPoint;
    _dragYaw = _cam.goal.yaw;
    _dragPitch = _cam.goal.pitch;
    _dragDist = _cam.goal.dist;
    _dragMoved = false;
    _touch();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final s = _dragStart;
    if (s == null) return;
    final delta = d.localFocalPoint - s;
    if (delta.distance > 4 || d.scale != 1) _dragMoved = true;
    final g = _cam.goal;
    g.yaw = _dragYaw - delta.dx * 0.008;
    g.pitch = (_dragPitch + delta.dy * 0.005).clamp(0.22, 1.2);
    if (d.pointerCount > 1 && d.scale > 0) {
      g.dist = (_dragDist / d.scale).clamp(8.0, 34.0);
    }
    _touch();
  }

  void _onScaleEnd(ScaleEndDetails d) => _dragStart = null;

  void _onTapUp(TapUpDetails d) {
    if (_dragMoved) return;
    final h = _pick(d.localPosition);
    _setFocus(h != null && !identical(h, _focused) ? h : null);
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.escape &&
        _focused != null) {
      _setFocus(null);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ─── البناء ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = math.min(widget.maxWidth, MediaQuery.sizeOf(context).width);
    final h = w * widget.aspect;
    final narrow = w < 420;

    Widget canvas = CustomPaint(
      size: Size(w, h),
      painter: _ScenePainter(
        scene: _scene,
        cam: _cam,
        logo: _logo,
        timeOf: () => _time,
        hovered: () => _hovered,
        focused: () => _focused,
        onSize: (s) => _size = s,
        repaint: _frame,
      ),
    );

    if (widget.interactive) {
      canvas = Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: Listener(
          onPointerSignal: _onScroll,
          child: MouseRegion(
            cursor: _hovered != null
                ? SystemMouseCursors.click
                : SystemMouseCursors.grab,
            onHover: _onHover,
            onExit: _onExit,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onTapUp: _onTapUp,
              child: canvas,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'مدينة ثلاثية الأبعاد: برج ألياف ضوئية يغذّي المباني. '
          'اسحب للتدوير واضغط على مبنى لعرض تفاصيله',
      child: RepaintBoundary(
        child: SizedBox(
          width: w,
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: canvas),
              if (widget.interactive)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 4,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _focused == null ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Center(
                        child: _Hint(
                          text: narrow
                              ? 'اضغط على مبنى لعرض تفاصيله'
                              : 'اسحب للتدوير · العجلة للتكبير · اضغط على مبنى للدخول لتفاصيله',
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: narrow ? null : 8,
                bottom: narrow ? 8 : null,
                left: 8,
                width: narrow ? w - 16 : math.min(300, w * 0.55),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.94, end: 1.0).animate(a),
                      child: child,
                    ),
                  ),
                  child: _focused == null
                      ? const SizedBox.shrink()
                      : _InfoCard(
                          key: ValueKey(_focused!.id),
                          b: _focused!,
                          onClose: () => _setFocus(null),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// بطاقة التفاصيل والتلميح
// ═══════════════════════════════════════════════════════════════════

class _InfoCard extends StatelessWidget {
  const _InfoCard({super.key, required this.b, required this.onClose});
  final SdSceneBuilding b;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(
        fontFamily: 'Cairo',
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: Color(0x99FFFFFF));
    Widget kv(String v, String k, {Color color = Colors.white, bool ltr = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v,
                textDirection: ltr ? TextDirection.ltr : null,
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: color)),
            Text(k, style: label),
          ],
        ),
      );
    }

    final ratio = b.subscribers == 0 ? 0.0 : b.online / b.subscribers;
    return Semantics(
      container: true,
      label: 'تفاصيل ${b.name}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xD90E1446),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x5980DEEA)),
          boxShadow: const [
            BoxShadow(color: Color(0x40000000), offset: Offset(0, 8)),
            BoxShadow(
                color: Color(0xB3000000),
                blurRadius: 50,
                spreadRadius: -20,
                offset: Offset(0, 30)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name,
                          style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                      Text('${b.type} · ${b.floors} طوابق', style: label),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'إغلاق التفاصيل',
                  child: Material(
                    color: const Color(0x14FFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onClose,
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.close_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: kv('${b.subscribers}', 'مشترك')),
              const SizedBox(width: 8),
              Expanded(
                  child: kv('${b.online}', 'متصل الآن',
                      color: const Color(0xFF69F0AE))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: kv(b.rx, 'الإشارة الضوئية dBm', ltr: true)),
              const SizedBox(width: 8),
              Expanded(child: kv(b.fat, 'صندوق التوزيع')),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 8,
                child: Stack(children: [
                  const Positioned.fill(
                      child: ColoredBox(color: Color(0x1FFFFFFF))),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: ratio,
                    heightFactor: 1,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [Color(0xFF00ACC1), Color(0xFF69F0AE)]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            const Text('بيانات توضيحية — تُربط لاحقاً بالبيانات الفعلية',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0x73FFFFFF))),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xCCFFFFFF))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// الرياضيات والكاميرا
// ═══════════════════════════════════════════════════════════════════

class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  _V operator +(_V o) => _V(x + o.x, y + o.y, z + o.z);
  _V operator -(_V o) => _V(x - o.x, y - o.y, z - o.z);
  _V operator *(double s) => _V(x * s, y * s, z * s);
  double dot(_V o) => x * o.x + y * o.y + z * o.z;
  _V cross(_V o) => _V(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _V get unit {
    final l = math.sqrt(x * x + y * y + z * z);
    return l == 0 ? this : _V(x / l, y / l, z / l);
  }

  _V addY(double dy) => dy == 0 ? this : _V(x, y + dy, z);
}

final _V _light = const _V(-0.55, 1, 0.75).unit;

class _CamState {
  _CamState(this.yaw, this.pitch, this.dist, this.tx, this.ty, this.tz);
  double yaw, pitch, dist, tx, ty, tz;
}

class _Parallax {
  double x = 0, y = 0, gx = 0, gy = 0;
}

class _Camera {
  static const double homeDist = 26;
  final _CamState cur = _CamState(0.62, 0.58, homeDist, 0, 1.2, 0);
  final _CamState goal = _CamState(0.62, 0.58, homeDist, 0, 1.2, 0);
  final _Parallax par = _Parallax();

  void step(double e, double pe) {
    e = e.clamp(0.0, 1.0);
    pe = pe.clamp(0.0, 1.0);
    double l(double a, double b) => a + (b - a) * e;
    cur.yaw = l(cur.yaw, goal.yaw);
    cur.pitch = l(cur.pitch, goal.pitch);
    cur.dist = l(cur.dist, goal.dist);
    cur.tx = l(cur.tx, goal.tx);
    cur.ty = l(cur.ty, goal.ty);
    cur.tz = l(cur.tz, goal.tz);
    par.x += (par.gx - par.x) * pe;
    par.y += (par.gy - par.y) * pe;
  }
}

class _P {
  const _P(this.x, this.y, this.z, this.s);
  final double x, y, z, s;
  Offset get o => Offset(x, y);
}

class _Projector {
  _Projector(_Camera cam, Size size) {
    final c = cam.cur;
    final yaw = c.yaw + cam.par.x * 0.12;
    final pitch = (c.pitch + cam.par.y * 0.06).clamp(0.18, 1.25);
    final t = _V(c.tx, c.ty, c.tz);
    eye = t +
        _V(math.cos(pitch) * math.sin(yaw), math.sin(pitch),
                math.cos(pitch) * math.cos(yaw)) *
            c.dist;
    f = (t - eye).unit;
    r = f.cross(const _V(0, 1, 0)).unit;
    u = r.cross(f);
    focal = math.min(size.width * 1.05, size.height * 1.2) * 1.45;
    cx = size.width / 2;
    cy = size.height * 0.5;
  }

  late final _V eye, f, r, u;
  late final double focal, cx, cy;

  _P project(_V p) {
    final v = p - eye;
    final z = v.dot(f);
    final s = focal / math.max(z, 0.1);
    return _P(cx + v.dot(r) * s, cy - v.dot(u) * s, z, s);
  }
}

bool _inPoly(Offset p, List<_P> pts) {
  var c = false;
  for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    final a = pts[i], b = pts[j];
    if (((a.y > p.dy) != (b.y > p.dy)) &&
        (p.dx < (b.x - a.x) * (p.dy - a.y) / (b.y - a.y) + a.x)) {
      c = !c;
    }
  }
  return c;
}

// ═══════════════════════════════════════════════════════════════════
// نموذج المشهد
// ═══════════════════════════════════════════════════════════════════

enum _Tag { fixed, body, roof, interior }

class _Face {
  _Face(this.pts, this.col, this.emit);
  final List<_V> pts;
  final Color col;
  final bool emit;
  final List<_Face> decals = [];
  _V n = const _V(0, 1, 0);
  _V c = const _V(0, 0, 0);
}

class _Part {
  _Part(this.building, this.tag);
  final SdSceneBuilding? building;
  final _Tag tag;
  final List<_Face> faces = [];
  _V center = const _V(0, 0, 0);

  _Face face(List<_V> pts, Color col, {bool emit = false}) {
    final f = _Face(pts, col, emit);
    faces.add(f);
    return f;
  }

  /// يحسب المراكز والنواظم (للخارج نسبةً إلى مركز الجزء أو [axisOf]).
  void finish({_V Function(_Face f)? axisOf}) {
    var s = const _V(0, 0, 0);
    var n = 0;
    for (final f in faces) {
      for (final v in f.pts) {
        s = s + v;
        n++;
      }
    }
    center = s * (1 / math.max(n, 1));
    for (final f in faces) {
      var c = const _V(0, 0, 0);
      for (final v in f.pts) {
        c = c + v;
      }
      f.c = c * (1 / f.pts.length);
      var nn = (f.pts[1] - f.pts[0]).cross(f.pts[2] - f.pts[0]).unit;
      final ref = axisOf != null ? axisOf(f) : center;
      if (nn.dot(f.c - ref) < 0) nn = nn * -1;
      f.n = nn;
    }
  }
}

class _Box {
  _Box(this.faces, this.x0, this.x1, this.y0, this.y1, this.z0, this.z1);
  final Map<String, _Face> faces;
  final double x0, x1, y0, y1, z0, z1;
}

class _Dot {
  const _Dot(this.p, this.on);
  final _V p;
  final bool on;
}

class _Fiber {
  _Fiber(this.b, this.pts, this.speed, this.phase);
  final SdSceneBuilding b;
  final List<_V> pts;
  final double speed, phase;
}

Color _c(int hex) => Color(0xFF000000 | hex);

_Box _box(_Part p, double x, double y, double z, double w, double h, double d,
    int col,
    {int? top, bool emit = false}) {
  final x0 = x - w / 2, x1 = x + w / 2, z0 = z - d / 2, z1 = z + d / 2;
  final y0 = y, y1 = y + h;
  final s = _c(col), t = _c(top ?? col);
  final m = <String, _Face>{
    'top': p.face([_V(x0, y1, z0), _V(x1, y1, z0), _V(x1, y1, z1), _V(x0, y1, z1)], t),
    'pz': p.face([_V(x0, y0, z1), _V(x1, y0, z1), _V(x1, y1, z1), _V(x0, y1, z1)], s, emit: emit),
    'nz': p.face([_V(x1, y0, z0), _V(x0, y0, z0), _V(x0, y1, z0), _V(x1, y1, z0)], s, emit: emit),
    'px': p.face([_V(x1, y0, z1), _V(x1, y0, z0), _V(x1, y1, z0), _V(x1, y1, z1)], s, emit: emit),
    'nx': p.face([_V(x0, y0, z0), _V(x0, y0, z1), _V(x0, y1, z1), _V(x0, y1, z0)], s, emit: emit),
  };
  return _Box(m, x0, x1, y0, y1, z0, z1);
}

void _prism(_Part p, double x, double y, double z, double r, double h, int n,
    int col,
    [int? topCol]) {
  List<_V> ring(double yy) => [
        for (var i = 0; i < n; i++)
          _V(x + math.cos(i / n * math.pi * 2 + math.pi / n) * r, yy,
              z + math.sin(i / n * math.pi * 2 + math.pi / n) * r),
      ];
  final b = ring(y), t = ring(y + h);
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    p.face([b[i], b[j], t[j], t[i]], _c(col));
  }
  p.face(t, _c(topCol ?? col));
}

void _cone(_Part p, double x, double y, double z, double r, double h, int n,
    int col) {
  final ring = [
    for (var i = 0; i < n; i++)
      _V(x + math.cos(i / n * math.pi * 2) * r, y,
          z + math.sin(i / n * math.pi * 2) * r),
  ];
  final tip = _V(x, y + h, z);
  for (var i = 0; i < n; i++) {
    p.face([ring[i], ring[(i + 1) % n], tip], _c(col));
  }
}

/// شبكة نوافذ (ملصقات) على جانب صندوق.
void _windows(_Box bx, String side, int rows, int cols,
    {int lit = 0xFFE29A,
    int off = 0x2A356F,
    int seed = 0,
    int dark = 1,
    double mx = 0.18,
    double my0 = 0.25,
    double my1 = 0.18,
    double gap = 0.5}) {
  final f = bx.faces[side]!;
  const eps = 0.012;
  final hgt = bx.y1 - bx.y0 - my0 - my1;
  final horiz = side == 'pz' || side == 'nz';
  final wid = (horiz ? bx.x1 - bx.x0 : bx.z1 - bx.z0) - 2 * mx;
  final cw = wid / cols, rh = hgt / rows;
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      final isLit = ((r * 7 + c * 13 + seed) % 5) > dark;
      final a = mx + c * cw + cw * gap * 0.3, b = a + cw * (1 - gap * 0.6);
      final y0 = bx.y0 + my0 + r * rh + rh * 0.18, y1 = y0 + rh * 0.62;
      late List<_V> pts;
      switch (side) {
        case 'pz':
          pts = [_V(bx.x0 + a, y0, bx.z1 + eps), _V(bx.x0 + b, y0, bx.z1 + eps), _V(bx.x0 + b, y1, bx.z1 + eps), _V(bx.x0 + a, y1, bx.z1 + eps)];
        case 'nz':
          pts = [_V(bx.x1 - a, y0, bx.z0 - eps), _V(bx.x1 - b, y0, bx.z0 - eps), _V(bx.x1 - b, y1, bx.z0 - eps), _V(bx.x1 - a, y1, bx.z0 - eps)];
        case 'px':
          pts = [_V(bx.x1 + eps, y0, bx.z1 - a), _V(bx.x1 + eps, y0, bx.z1 - b), _V(bx.x1 + eps, y1, bx.z1 - b), _V(bx.x1 + eps, y1, bx.z1 - a)];
        default:
          pts = [_V(bx.x0 - eps, y0, bx.z0 + a), _V(bx.x0 - eps, y0, bx.z0 + b), _V(bx.x0 - eps, y1, bx.z0 + b), _V(bx.x0 - eps, y1, bx.z0 + a)];
      }
      f.decals.add(_Face(pts, _c(isLit ? lit : off), isLit));
    }
  }
}

class _Scene {
  _Scene._();
  final List<_Part> parts = [];
  final List<SdSceneBuilding> buildings = [];
  final List<_Fiber> fibers = [];
  late final _Part ground, roads;

  _Part _part(SdSceneBuilding? b, _Tag tag) {
    final p = _Part(b, tag);
    parts.add(p);
    if (b != null) b._parts.add(p);
    return p;
  }

  static _Scene build() {
    final s = _Scene._();
    const R = 4.6;
    ({double x, double z}) place(double deg) {
      final a = deg * math.pi / 180;
      return (x: math.sin(a) * R, z: math.cos(a) * R);
    }

    // الأرضية والطرق
    s.ground = s._part(null, _Tag.fixed);
    _box(s.ground, 0, -0.5, 0, 14, 0.5, 14, 0x151D62, top: 0x1C2675);
    s.ground.finish();
    s.roads = s._part(null, _Tag.fixed);
    _box(s.roads, 0, 0, 0, 14, 0.02, 1.3, 0x121852);
    _box(s.roads, 0, 0, 0, 1.3, 0.021, 14, 0x121852);
    s.roads.finish();

    // البرج المركزي (OLT)
    final hub = s._part(null, _Tag.fixed);
    _box(hub, 0, 0, 0, 2.6, 0.35, 2.6, 0x2A3590, top: 0x3A47A8);
    _box(hub, 0, 0.35, 0, 1.7, 0.5, 1.7, 0x1E2A78, top: 0x2D3A99);
    final tw = _box(hub, 0, 0.85, 0, 1.15, 3.6, 1.15, 0x0097A7, top: 0x4DD0E1);
    for (final k in ['pz', 'px', 'nz', 'nx']) {
      _windows(tw, k, 6, 2,
          lit: 0xB2F5FF, off: 0x00707C, seed: 3, dark: 2, mx: 0.16, gap: 0.6);
    }
    _box(hub, 0, 4.45, 0, 0.7, 0.4, 0.7, 0x00838F, top: 0x80DEEA);
    _prism(hub, 0, 4.85, 0, 0.06, 1.0, 6, 0xB2EBF2);
    hub.finish();

    SdSceneBuilding add(SdSceneBuilding b) {
      s.buildings.add(b);
      return b;
    }

    // 1) برج سكني
    {
      final p = place(-40);
      final b = add(SdSceneBuilding(
          id: 'tower', name: 'برج سكني «الياسمين»', type: 'سكني متعدد الطوابق',
          x: p.x, z: p.z, height: 4.2, floors: 7, subscribers: 28, online: 27,
          rx: '-19.4', fat: 'FAT-07', accent: _c(0x7C8CF8)));
      final body = s._part(b, _Tag.body);
      final f = _box(body, b.x, 0, b.z, 1.7, 4.2, 1.7, 0xE9ECF6, top: 0xF7F8FC);
      var i = 0;
      for (final k in ['pz', 'px', 'nz', 'nx']) {
        _windows(f, k, 7, 3, seed: i++ * 5 + 1);
      }
      body.finish();
      final roof = s._part(b, _Tag.roof);
      _box(roof, b.x, 4.2, b.z, 1.85, 0.18, 1.85, 0x3949AB, top: 0x5C6BC0);
      _box(roof, b.x + 0.4, 4.38, b.z - 0.3, 0.5, 0.35, 0.5, 0xC5CBE0);
      roof.finish();
    }
    // 2) فيلا بسقف جملوني وحديقة ومسبح
    {
      final p = place(40);
      final b = add(SdSceneBuilding(
          id: 'villa', name: 'فيلا «النخيل»', type: 'منزل مستقل',
          x: p.x, z: p.z, height: 1.4, floors: 2, subscribers: 1, online: 1,
          rx: '-17.8', fat: 'FAT-03', accent: _c(0xFFB74D)));
      final body = s._part(b, _Tag.body);
      final f = _box(body, b.x, 0, b.z, 2.2, 1.4, 1.6, 0xF3EEE4, top: 0xFBF8F2);
      _windows(f, 'pz', 2, 3, seed: 2, dark: 0, mx: 0.25);
      _windows(f, 'px', 2, 2, seed: 4, dark: 0);
      _windows(f, 'nx', 2, 2, seed: 1, dark: 0);
      _windows(f, 'nz', 2, 3, seed: 3, dark: 0);
      body.finish();
      final roof = s._part(b, _Tag.roof);
      final x0 = b.x - 1.25, x1 = b.x + 1.25, z0 = b.z - 0.95, z1 = b.z + 0.95;
      const y = 1.4, rh = 0.8;
      roof.face([_V(x0, y, z1), _V(x1, y, z1), _V(x1, y + rh, b.z), _V(x0, y + rh, b.z)], _c(0xC0603A));
      roof.face([_V(x1, y, z0), _V(x0, y, z0), _V(x0, y + rh, b.z), _V(x1, y + rh, b.z)], _c(0xA84E2C));
      roof.face([_V(x0 + 0.05, y, z0 + 0.1), _V(x0 + 0.05, y, z1 - 0.1), _V(x0 + 0.05, y + rh - 0.04, b.z)], _c(0xE9E2D4));
      roof.face([_V(x1 - 0.05, y, z1 - 0.1), _V(x1 - 0.05, y, z0 + 0.1), _V(x1 - 0.05, y + rh - 0.04, b.z)], _c(0xE9E2D4));
      roof.finish();
      final gar = s._part(b, _Tag.fixed);
      _box(gar, b.x, 0, b.z + 1.35, 2.4, 0.06, 0.9, 0x2E7D32, top: 0x43A047);
      _box(gar, b.x + 0.5, 0.061, b.z + 1.35, 0.9, 0.02, 0.5, 0x29B6F6, top: 0x4FC3F7);
      gar.finish();
    }
    // 3) مجمّع أعمال زجاجي
    {
      final p = place(140);
      final b = add(SdSceneBuilding(
          id: 'office', name: 'مجمّع الأعمال', type: 'مكاتب شركات',
          x: p.x, z: p.z, height: 2.8, floors: 5, subscribers: 12, online: 12,
          rx: '-16.2', fat: 'FAT-11', accent: _c(0x4DD0E1)));
      final body = s._part(b, _Tag.body);
      final f = _box(body, b.x, 0, b.z, 2.2, 2.8, 1.8, 0x3F51B5, top: 0x5C6BC0);
      var i = 0;
      for (final k in ['pz', 'px', 'nz', 'nx']) {
        _windows(f, k, 5, 5,
            lit: 0xB3E5FC, off: 0x2C3C9C, seed: i++ * 3, dark: 2, mx: 0.08, gap: 0.25);
      }
      body.finish();
      final roof = s._part(b, _Tag.roof);
      _box(roof, b.x, 2.8, b.z, 2.3, 0.14, 1.9, 0x283593, top: 0x3949AB);
      _prism(roof, b.x - 0.5, 2.94, b.z, 0.32, 0.12, 10, 0xECEFF1, 0x80DEEA);
      roof.finish();
    }
    // 4) سوق تجاري بمظلّة
    {
      final p = place(-140);
      final b = add(SdSceneBuilding(
          id: 'market', name: 'السوق التجاري', type: 'محلات تجارية',
          x: p.x, z: p.z, height: 1.2, floors: 1, subscribers: 9, online: 8,
          rx: '-21.6', fat: 'FAT-05', accent: _c(0x81C784)));
      final body = s._part(b, _Tag.body);
      final f = _box(body, b.x, 0, b.z, 2.6, 1.2, 1.6, 0xFAFAFA, top: 0xFFFFFF);
      _windows(f, 'pz', 1, 4, dark: -1, my0: 0.12, my1: 0.4, gap: 0.2);
      _windows(f, 'px', 1, 2, dark: -1, my0: 0.12, my1: 0.4);
      _windows(f, 'nx', 1, 2, dark: -1, my0: 0.12, my1: 0.4);
      body.finish();
      final roof = s._part(b, _Tag.roof);
      _box(roof, b.x, 1.2, b.z, 2.7, 0.12, 1.7, 0x00897B, top: 0x26A69A);
      final z1 = b.z + 0.8;
      roof.face([_V(b.x - 1.3, 1.0, z1), _V(b.x + 1.3, 1.0, z1), _V(b.x + 1.3, 0.85, z1 + 0.45), _V(b.x - 1.3, 0.85, z1 + 0.45)], _c(0xE57373));
      roof.finish();
    }
    // 5) مدرسة
    {
      final p = place(180);
      final b = add(SdSceneBuilding(
          id: 'school', name: 'مدرسة المستقبل', type: 'مؤسسة تعليمية',
          x: p.x, z: p.z, height: 1.8, floors: 2, subscribers: 4, online: 4,
          rx: '-18.9', fat: 'FAT-09', accent: _c(0xBA68C8)));
      final body = s._part(b, _Tag.body);
      final f = _box(body, b.x, 0, b.z, 3.0, 1.8, 1.1, 0xFFF3E0, top: 0xFFF8EE);
      _windows(f, 'pz', 2, 6, seed: 1, dark: 0, gap: 0.3);
      _windows(f, 'nz', 2, 6, seed: 2, dark: 0);
      body.finish();
      final roof = s._part(b, _Tag.roof);
      _box(roof, b.x, 1.8, b.z, 3.1, 0.12, 1.2, 0x8E24AA, top: 0xAB47BC);
      roof.finish();
    }
    // 6) منزل بسقف هرمي (مشترك مفصول — يظهر بالأحمر)
    {
      final p = place(-90);
      final b = add(SdSceneBuilding(
          id: 'house', name: 'منزل «الريان»', type: 'منزل عائلي',
          x: p.x, z: p.z, height: 1.0, floors: 1, subscribers: 1, online: 0,
          rx: '—', fat: 'FAT-02', accent: _c(0xE57373)));
      final body = s._part(b, _Tag.body);
      final f = _box(body, b.x, 0, b.z, 1.5, 1.0, 1.4, 0xECEFF1, top: 0xF5F7F8);
      _windows(f, 'pz', 1, 2, dark: -1, my0: 0.3);
      _windows(f, 'nx', 1, 2, seed: 4, dark: 9, my0: 0.3);
      _windows(f, 'px', 1, 2, seed: 4, dark: 9, my0: 0.3);
      body.finish();
      final roof = s._part(b, _Tag.roof);
      final x0 = b.x - 0.85, x1 = b.x + 0.85, z0 = b.z - 0.8, z1 = b.z + 0.8;
      const y = 1.0, rh = 0.6;
      final tip = _V(b.x, y + rh, b.z);
      roof.face([_V(x0, y, z0), _V(x0, y, z1), tip], _c(0x546E7A));
      roof.face([_V(x0, y, z1), _V(x1, y, z1), tip], _c(0x607D8B));
      roof.face([_V(x1, y, z1), _V(x1, y, z0), tip], _c(0x455A64));
      roof.face([_V(x1, y, z0), _V(x0, y, z0), tip], _c(0x37474F));
      roof.finish();
    }
    // 7) عمارات توأم
    {
      final p = place(90);
      final b = add(SdSceneBuilding(
          id: 'apts', name: 'عمارات «الرافدين»', type: 'سكني',
          x: p.x, z: p.z, height: 2.6, floors: 4, subscribers: 16, online: 15,
          rx: '-20.3', fat: 'FAT-04', accent: _c(0xFFD54F)));
      final body = s._part(b, _Tag.body);
      final f1 = _box(body, b.x - 0.55, 0, b.z, 1.0, 2.6, 1.4, 0xE3E7F5, top: 0xF2F4FA);
      final f2 = _box(body, b.x + 0.6, 0, b.z + 0.1, 1.0, 2.2, 1.2, 0xD7DCEE, top: 0xEEF0F8);
      var i = 2;
      for (final k in ['pz', 'nx', 'nz']) {
        _windows(f1, k, 4, 2, seed: i++);
      }
      i = 6;
      for (final k in ['pz', 'px', 'nz']) {
        _windows(f2, k, 3, 2, seed: i++);
      }
      // كل صندوق نواظمه لمركزه — نحسب لكل وجه أقرب مركز صندوق.
      final c1 = _V(b.x - 0.55, 1.3, b.z), c2 = _V(b.x + 0.6, 1.1, b.z + 0.1);
      body.finish(axisOf: (f) {
        final d1 = (f.c.x - c1.x).abs() <= 0.501 && (f.c.z - c1.z).abs() <= 0.701;
        return d1 ? c1 : c2;
      });
      final roof = s._part(b, _Tag.roof);
      _box(roof, b.x - 0.55, 2.6, b.z, 1.1, 0.1, 1.5, 0xF9A825, top: 0xFFCA28);
      _box(roof, b.x + 0.6, 2.2, b.z + 0.1, 1.1, 0.1, 1.3, 0xF9A825, top: 0xFFCA28);
      final r1 = _V(b.x - 0.55, 2.65, b.z), r2 = _V(b.x + 0.6, 2.25, b.z + 0.1);
      roof.finish(axisOf: (f) =>
          ((f.c.x - r1.x).abs() <= 0.551 && (f.c.z - r1.z).abs() <= 0.751) &&
                  (f.c.y > 2.55)
              ? r1
              : r2);
    }

    // الطوابق الداخلية ونقاط المشتركين (تظهر عند الدخول للمبنى)
    for (final b in s.buildings) {
      final ip = s._part(b, _Tag.interior);
      final n = b.floors;
      for (var i = 0; i < n; i++) {
        final y = (i + 0.5) * b.height / n - 0.05;
        _box(ip, b.x, y, b.z, 1.3, 0.06, 1.1, 0x4DD0E1, top: 0x80DEEA);
        final per = math.max(1, (b.subscribers / n).round());
        for (var k = 0; k < per; k++) {
          final a = k / per * math.pi * 2;
          b._dots.add(_Dot(
              _V(b.x + math.cos(a) * 0.4, y + 0.14, b.z + math.sin(a) * 0.35),
              (i * per + k) < b.online));
        }
      }
      ip.finish();
      // نواظم الشرائح: احسبها نسبةً لمركز كل شريحة
      for (final f in ip.faces) {
        final slabY = f.pts.map((v) => v.y).reduce((a, c) => a + c) / f.pts.length;
        final ref = _V(b.x, slabY - 0.03, b.z);
        var nn = (f.pts[1] - f.pts[0]).cross(f.pts[2] - f.pts[0]).unit;
        if (nn.dot(f.c - ref) < 0) nn = nn * -1;
        f.n = nn;
      }
      b._led = _V(b.x, 0.25, b.z + 0.9);
    }

    // الأشجار
    const treeAt = <List<double>>[
      [-2.4, 2.6], [2.6, -2.5], [-5.8, 1.2], [5.9, 2.7], [-1.9, -5.8],
      [2.2, 5.9], [6.0, -5.6], [-6.2, -5.2], [-6.0, 5.8], [3.0, 2.3],
    ];
    final trees = s._part(null, _Tag.fixed);
    for (var i = 0; i < treeAt.length; i++) {
      final x = treeAt[i][0], z = treeAt[i][1];
      _prism(trees, x, 0, z, 0.08, 0.35, 5, 0x6D4C41);
      _cone(trees, x, 0.3, z, 0.38 + (i % 3) * 0.06, 0.9 + (i % 2) * 0.3, 7,
          i.isOdd ? 0x2E7D32 : 0x388E3C);
    }
    trees.finish(axisOf: (f) {
      var best = treeAt.first;
      var bd = double.infinity;
      for (final t in treeAt) {
        final d = (t[0] - f.c.x) * (t[0] - f.c.x) + (t[1] - f.c.z) * (t[1] - f.c.z);
        if (d < bd) {
          bd = d;
          best = t;
        }
      }
      return _V(best[0], f.c.y - 0.35, best[1]);
    });

    // خطوط الألياف (منحنى بيزييه تربيعي من البرج لكل مبنى)
    for (var i = 0; i < s.buildings.length; i++) {
      final b = s.buildings[i];
      final mid = _V(b.x * 0.55, 0.04, b.z * 0.15);
      final pts = <_V>[];
      for (var k = 0; k <= 24; k++) {
        final t = k / 24, u = 1 - t;
        pts.add(_V(2 * u * t * mid.x + t * t * b.x, 0.04,
            2 * u * t * mid.z + t * t * b.z));
      }
      s.fibers.add(_Fiber(b, pts, 0.22 + (i % 3) * 0.06, i * 0.37));
    }
    return s;
  }
}

// ═══════════════════════════════════════════════════════════════════
// الرسم
// ═══════════════════════════════════════════════════════════════════

enum _K { face, dot, led, pulse }

class _Item {
  _Item(this.z, this.k);
  final double z;
  final _K k;
  _Face? f;
  List<_P>? pr;
  double alpha = 1, hl = 0, dy = 0;
  SdSceneBuilding? b;
  _P? q;
  bool on = true;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter({
    required this.scene,
    required this.cam,
    required this.logo,
    required this.timeOf,
    required this.hovered,
    required this.focused,
    required this.onSize,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _Scene scene;
  final _Camera cam;
  final ui.Image? logo;
  final double Function() timeOf;
  final SdSceneBuilding? Function() hovered;
  final SdSceneBuilding? Function() focused;
  final void Function(Size) onSize;

  static final Paint _fill = Paint()..isAntiAlias = true;
  static final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  Path _path(List<_P> pts) {
    final p = Path()..moveTo(pts[0].x, pts[0].y);
    for (var i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].x, pts[i].y);
    }
    return p..close();
  }

  Path _open(List<_P> pts) {
    final p = Path()..moveTo(pts[0].x, pts[0].y);
    for (var i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].x, pts[i].y);
    }
    return p;
  }

  Color _shade(_Face f, double hl) {
    final lam = math.max(0.0, f.n.dot(_light));
    final k = f.emit ? 1.0 : 0.48 + 0.62 * lam;
    double ch(double v) {
      var c = (v * 255 * k).clamp(0.0, 255.0);
      c = c + (255 - c) * hl;
      return c;
    }

    return Color.fromARGB(255, ch(f.col.r).round(), ch(f.col.g).round(),
        ch(f.col.b).round());
  }

  @override
  void paint(Canvas canvas, Size size) {
    onSize(size);
    final t = timeOf();
    final hov = hovered();
    final foc = focused();
    final pj = _Projector(cam, size);
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // توهّج أرضي
    final gp = pj.project(const _V(0, 0, 0));
    canvas.drawCircle(
      gp.o,
      9 * gp.s,
      _fill
        ..shader = ui.Gradient.radial(gp.o, 9 * gp.s,
            const [Color(0x4700ACC1), Color(0x0000ACC1)]),
    );
    _fill.shader = null;

    final items = <_Item>[];
    for (final p in scene.parts) {
      final b = p.building;
      var dy = 0.0, alpha = 1.0, hl = 0.0;
      if (b != null) {
        hl = b.hover * 0.18;
        if (p.tag == _Tag.roof) dy = b.focus * 1.6;
        if (p.tag == _Tag.body) alpha = 1 - b.focus * 0.72;
        if (p.tag == _Tag.interior) {
          alpha = b.focus;
          if (alpha < 0.02) continue;
        }
        if (foc != null && !identical(b, foc)) alpha *= 0.55;
      } else if (foc != null && !identical(p, scene.ground) && !identical(p, scene.roads)) {
        alpha = 0.6;
      }
      for (final f in p.faces) {
        final c = f.c.addY(dy);
        if (f.n.dot(pj.eye - c) <= 0) continue; // إخفاء الأوجه الخلفية
        var z = pj.project(c).z;
        if (identical(p, scene.ground)) {
          z = 1e9;
        } else if (identical(p, scene.roads)) {
          z = 1e9 - 1;
        }
        items.add(_Item(z, _K.face)
          ..f = f
          ..pr = [for (final v in f.pts) pj.project(v.addY(dy))]
          ..alpha = alpha
          ..hl = hl
          ..b = b
          ..dy = dy);
      }
    }
    for (final b in scene.buildings) {
      if (b.focus > 0.05) {
        for (final d in b._dots) {
          final q = pj.project(d.p);
          items.add(_Item(q.z - 0.01, _K.dot)
            ..q = q
            ..on = d.on
            ..alpha = b.focus);
        }
      }
      final q = pj.project(b._led);
      items.add(_Item(q.z - 0.3, _K.led)
        ..q = q
        ..on = b.online > 0
        ..b = b);
    }
    for (final fb in scene.fibers) {
      for (var k = 0; k < 3; k++) {
        final u = (t * fb.speed + fb.phase + k / 3) % 1;
        final idx = u * (fb.pts.length - 1);
        final i0 = idx.floor(), i1 = math.min(i0 + 1, fb.pts.length - 1);
        final w = idx - i0;
        final a = fb.pts[i0], c = fb.pts[i1];
        final q = pj.project(_V(a.x + (c.x - a.x) * w, 0.08, a.z + (c.z - a.z) * w));
        items.add(_Item(q.z, _K.pulse)..q = q);
      }
    }
    items.sort((a, b) => b.z.compareTo(a.z));

    var i = 0;
    for (; i < items.length && items[i].z >= 1e9 - 1; i++) {
      _draw(canvas, items[i], t, pj);
    }

    // شبكة الأرضية
    _line
      ..strokeWidth = 1
      ..color = const Color(0x384D6CDC);
    for (var g = -7.0; g <= 7; g += 1) {
      _seg(canvas, pj, _V(g, 0.005, -7), _V(g, 0.005, 7));
      _seg(canvas, pj, _V(-7, 0.005, g), _V(7, 0.005, g));
    }
    // خطوط الطرق المتقطّعة
    _line
      ..strokeWidth = 1.4
      ..color = const Color(0x739FA8DA);
    for (final s in const [
      [-7.0, -1.4, 0.0],
      [1.4, 7.0, 0.0],
    ]) {
      _dash(canvas, pj, _V(s[0], 0.03, 0), _V(s[1], 0.03, 0));
      _dash(canvas, pj, _V(0, 0.03, s[0]), _V(0, 0.03, s[1]));
    }
    // حافة المنصّة المضيئة
    _line
      ..strokeWidth = 1.6
      ..color = const Color(0x8C4DD0E1);
    canvas.drawPath(
        _path([for (final v in const [_V(-7, 0, -7), _V(7, 0, -7), _V(7, 0, 7), _V(-7, 0, 7)]) pj.project(v)]),
        _line);
    // ظلال المباني
    _fill.color = const Color(0x59050828);
    for (final b in scene.buildings) {
      final s = 1.1 + b.height * 0.12;
      canvas.drawPath(
          _path([
            pj.project(_V(b.x - s + 0.35, 0.01, b.z - s * 0.8 + 0.45)),
            pj.project(_V(b.x + s + 0.35, 0.01, b.z - s * 0.8 + 0.45)),
            pj.project(_V(b.x + s + 0.55, 0.01, b.z + s * 0.8 + 0.6)),
            pj.project(_V(b.x - s + 0.55, 0.01, b.z + s * 0.8 + 0.6)),
          ]),
          _fill);
    }
    // الألياف
    _line.strokeCap = StrokeCap.round;
    for (final fb in scene.fibers) {
      final pr = [for (final v in fb.pts) pj.project(v)];
      final act = fb.b.hover > 0.5 || identical(fb.b, foc);
      final path = _open(pr);
      _line
        ..strokeWidth = 4.5 * pr[0].s / 40
        ..color = const Color(0xE6080C32);
      canvas.drawPath(path, _line);
      _line
        ..strokeWidth = (act ? 2.6 : 1.8) * pr[0].s / 40
        ..color = act ? const Color(0xF280DEEA) : const Color(0x8C4DD0E1);
      canvas.drawPath(path, _line);
    }
    _line.strokeCap = StrokeCap.butt;

    for (; i < items.length; i++) {
      _draw(canvas, items[i], t, pj);
    }

    _drawLogo(canvas, pj, t);

    if (hov != null && foc == null) {
      final q = pj.project(_V(hov.x, hov.height + 1.0, hov.z));
      _label(canvas, q.o, hov.name, hov.accent);
    }
    canvas.restore();
  }

  void _seg(Canvas c, _Projector pj, _V a, _V b) =>
      c.drawLine(pj.project(a).o, pj.project(b).o, _line);

  void _dash(Canvas c, _Projector pj, _V a, _V b) {
    const n = 14;
    for (var k = 0; k < n; k += 2) {
      final p0 = a + (b - a) * (k / n), p1 = a + (b - a) * ((k + 1) / n);
      c.drawLine(pj.project(p0).o, pj.project(p1).o, _line);
    }
  }

  void _draw(Canvas canvas, _Item it, double t, _Projector pj) {
    switch (it.k) {
      case _K.face:
        {
        final f = it.f!;
        final a = it.alpha.clamp(0.0, 1.0);
        final col = _shade(f, it.hl);
        final path = _path(it.pr!);
        _fill.color = col.withValues(alpha: a);
        canvas.drawPath(path, _fill);
        if (!f.emit) {
          _line
            ..strokeWidth = 0.6
            ..color = Color.fromARGB((a * 255).round(), (col.r * 255 * 0.82).round(),
                (col.g * 255 * 0.82).round(), (col.b * 255 * 0.82).round());
          canvas.drawPath(path, _line);
        }
        final b = it.b;
        if (b != null && b.hover > 0.3 && a > 0.5) {
          _line
            ..strokeWidth = 1.4
            ..color = b.accent.withValues(alpha: b.hover * 0.9);
          canvas.drawPath(path, _line);
        }
        final lam = math.max(0.0, f.n.dot(_light));
        for (final d in f.decals) {
          final pr = [for (final v in d.pts) pj.project(v.addY(it.dy))];
          double k;
          if (d.emit) {
            k = 0.9 + 0.1 * math.sin(t * 2 + d.pts[0].x * 3 + d.pts[0].y * 5);
          } else {
            k = 0.6 + 0.4 * lam;
          }
          _fill.color = Color.fromARGB(
              (a * 255).round(),
              (d.col.r * 255 * k).round().clamp(0, 255),
              (d.col.g * 255 * k).round().clamp(0, 255),
              (d.col.b * 255 * k).round().clamp(0, 255));
          canvas.drawPath(_path(pr), _fill);
        }
        }
      case _K.dot:
        {
        final q = it.q!;
        _fill.color = (it.on ? const Color(0xFF69F0AE) : const Color(0xFFFF5252))
            .withValues(alpha: it.alpha.clamp(0.0, 1.0));
        canvas.drawCircle(q.o, math.max(2.5, 0.06 * q.s), _fill);
        }
      case _K.led:
        {
        final q = it.q!;
        final bl = it.on ? 0.6 + 0.4 * math.sin(t * 4 + it.b!.x) : 1.0;
        final r = math.max(2.5, 0.07 * q.s);
        _fill.color = it.on
            ? Color.fromRGBO(105, 240, 174, 0.25 * bl)
            : const Color(0x40FF5252);
        canvas.drawCircle(q.o, r * 2.6, _fill);
        _fill.color = it.on ? const Color(0xFF69F0AE) : const Color(0xFFFF5252);
        canvas.drawCircle(q.o, r, _fill);
        }
      case _K.pulse:
        {
        final q = it.q!;
        final r = math.max(2.0, 0.09 * q.s) * 3;
        _fill.shader = ui.Gradient.radial(q.o, r, const [
          Color(0xFFE0FFFF),
          Color(0xCC4DD0E1),
          Color(0x004DD0E1),
        ], const [
          0,
          0.35,
          1
        ]);
        canvas.drawCircle(q.o, r, _fill);
        _fill.shader = null;
        }
    }
  }

  void _drawLogo(Canvas canvas, _Projector pj, double t) {
    final bob = math.sin(t * 1.8) * 0.18;
    final lp = pj.project(_V(0, 6.6 + bob, 0));
    final r = 0.72 * lp.s;
    // شعاع من قمّة البرج
    final bp = pj.project(const _V(0, 5.9, 0));
    _fill.shader = ui.Gradient.linear(Offset(0, bp.y), Offset(0, lp.y + r),
        const [Color(0x804DD0E1), Color(0x004DD0E1)]);
    canvas.drawPath(
        Path()
          ..moveTo(bp.x - 6, bp.y)
          ..lineTo(bp.x + 6, bp.y)
          ..lineTo(lp.x + r * 0.5, lp.y + r)
          ..lineTo(lp.x - r * 0.5, lp.y + r)
          ..close(),
        _fill);
    // توهّج
    _fill.shader = ui.Gradient.radial(lp.o, r * 1.9,
        const [Color(0x734DD0E1), Color(0x004DD0E1)], const [0.3, 1]);
    canvas.drawCircle(lp.o, r * 1.9, _fill);
    _fill.shader = null;
    // حلقة مدارية ثلاثية الأبعاد + قمر صغير
    final ring = <_P>[];
    for (var k = 0; k <= 48; k++) {
      final a = k / 48 * math.pi * 2 + t * 0.6;
      ring.add(pj.project(_V(math.cos(a) * 1.5, 6.4 + bob, math.sin(a) * 1.5)));
    }
    _line
      ..strokeWidth = 1.5
      ..color = const Color(0xB3B2EBF2);
    canvas.drawPath(_open(ring), _line);
    final sat = pj.project(_V(math.cos(t * 0.9) * 1.5, 6.4 + bob, math.sin(t * 0.9) * 1.5));
    _fill.color = const Color(0xFFB2F5FF);
    canvas.drawCircle(sat.o, 3.2, _fill);
    // القرص والشعار
    _fill.color = Colors.white;
    canvas.drawCircle(lp.o, r, _fill);
    final img = logo;
    if (img != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: lp.o, radius: r * 0.92)));
      canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromCircle(center: lp.o, radius: r * 0.9),
          Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    } else {
      final tp = TextPainter(
        text: TextSpan(
            text: 'ص',
            style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: r,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1A237E))),
        textDirection: TextDirection.rtl,
      )..layout();
      tp.paint(canvas, lp.o - Offset(tp.width / 2, tp.height / 2));
    }
    _line
      ..strokeWidth = 2
      ..color = const Color(0xD9FFFFFF);
    canvas.drawCircle(lp.o, r, _line);
  }

  void _label(Canvas canvas, Offset at, String text, Color accent) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Colors.white)),
      textDirection: TextDirection.rtl,
    )..layout();
    final w = tp.width + 28;
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(at.dx - w / 2, at.dy - 34, w, 30), const Radius.circular(15));
    _fill.color = const Color(0xDB0B1033);
    canvas.drawRRect(rect, _fill);
    _line
      ..strokeWidth = 1.5
      ..color = accent;
    canvas.drawRRect(rect, _line);
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - 19 - tp.height / 2));
    _fill.color = accent;
    canvas.drawPath(
        Path()
          ..moveTo(at.dx - 6, at.dy - 4)
          ..lineTo(at.dx + 6, at.dy - 4)
          ..lineTo(at.dx, at.dy + 4)
          ..close(),
        _fill);
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) => old.logo != logo;
}
